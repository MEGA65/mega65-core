-- Testbench for sd_eth + eth_netsd_buf (#965), run by src/tools/sim_netsd.py,
-- which plays the PC: every frame sd_eth sends goes, as a line of hex, into
-- the named pipe tb_tx.fifo; the harness answers with frames (lines of hex)
-- on tb_rx.fifo, then a line ".", using netsd.py's own Server (and its
-- Ascon, which is independent of ascon_aead128).  The simulation stands
-- still while the harness thinks.
--
-- The host side drives sdcard_native's interface as the sector cache and
-- sdcardio_native would: init, single and multi-sector reads, an open-ended
-- read granted block by block (the cache's way), writes into the system
-- partition read back and compared, a refused write (the FAT32 partition is
-- read-only), a read past the end.  Every block read is logged to
-- tb_reads.txt ("R lba hex"), which the harness checks against the card.
--
-- G_FLAGS: bit 0 authenticate, bit 1 encrypt.  G_SYS_LBA: a sector in the
-- card's system partition (writable even read-only).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_sd_eth is
  generic (
    G_FLAGS   : natural := 0;
    G_SYS_LBA : natural := 100000
    );
end entity;

architecture sim of tb_sd_eth is

  -- the key both sides use: 40 41 42 ... 4f
  function test_key return unsigned is
    variable k : unsigned(127 downto 0);
  begin
    for i in 0 to 15 loop
      k(127 - 8 * i downto 120 - 8 * i) := to_unsigned(16#40# + i, 8);
    end loop;
    return k;                               -- first key byte at the top
  end function;

  signal cpuclock : std_logic := '0';
  signal clock50  : std_logic := '0';
  signal finished : boolean := false;

  signal ctl_write : std_logic := '0';
  signal ctl_wdata : unsigned(7 downto 0) := x"00";
  signal ctl_status : unsigned(7 downto 0);
  signal active : std_logic;
  signal cmd_valid : std_logic := '0';
  signal cmd_ready : std_logic;
  signal cmd_code : unsigned(3 downto 0) := x"0";
  signal cmd_addr : unsigned(31 downto 0) := (others => '0');
  signal cmd_count, cmd_arg : unsigned(15 downto 0) := (others => '0');
  signal card_ready, busy, waiting, err_flag : std_logic;
  signal err_code : unsigned(7 downto 0);
  signal blocks_done : unsigned(15 downto 0);
  signal capacity_valid : std_logic;
  signal last_sector : unsigned(31 downto 0);
  signal rd_valid, rd_good, rd_bad, wr_fetch : std_logic;
  signal rd_data : unsigned(7 downto 0);
  signal rd_offset, wr_offset : unsigned(8 downto 0);
  signal rd_block, wr_block : unsigned(15 downto 0);
  signal wr_data : unsigned(7 downto 0) := x"00";

  signal mac : unsigned(47 downto 0) := x"024753656599";
  signal rx_ready, rx_release, tx_we, tx_go, tx_base, tx_busy : std_logic;
  signal rx_len, tx_waddr, tx_len : unsigned(10 downto 0);
  signal rx_raddr : unsigned(9 downto 0);
  signal rx_rdata, tx_wdata : unsigned(7 downto 0);

  signal rx50_start, rx50_we, rx50_end, rx50_ok : std_logic := '0';
  signal rx50_addr, rx50_len : unsigned(10 downto 0) := (others => '0');
  signal rx50_data : unsigned(7 downto 0) := x"00";
  signal tx50_pending, tx50_done : std_logic := '0';
  signal tx50_len, tx50_raddr : unsigned(10 downto 0) := (others => '0');
  signal tx50_rdata : unsigned(7 downto 0);

  -- write data the host offers: a pattern of block and offset
  function pattern(blk : natural; off : natural) return unsigned is
  begin
    return to_unsigned((blk * 7 + off * 13 + 16#5a#) mod 256, 8);
  end function;
  signal wr_d1 : unsigned(7 downto 0) := x"00";
  signal wr_base : natural := 0;

begin

  cpuclock <= not cpuclock after 12.345 ns when not finished;
  clock50 <= not clock50 after 10 ns when not finished;

  dut : entity work.sd_eth
    generic map (G_WR_LAT => 2, G_US => 40, G_RETRY_US => 400, G_TRIES => 6,
                 G_HELLO_US => 3000, G_HELLO_TRIES => 4)
    port map (
      clock => cpuclock, ctl_write => ctl_write, ctl_wdata => ctl_wdata,
      ctl_status => ctl_status, active => active,
      cmd_valid => cmd_valid, cmd_ready => cmd_ready, cmd_code => cmd_code,
      cmd_addr => cmd_addr, cmd_count => cmd_count, cmd_arg => cmd_arg,
      card_ready => card_ready, busy => busy, waiting => waiting, error => err_flag,
      err_code => err_code, blocks_done => blocks_done,
      capacity_valid => capacity_valid, last_sector => last_sector,
      rd_valid => rd_valid, rd_data => rd_data, rd_offset => rd_offset,
      rd_block => rd_block, rd_good => rd_good, rd_bad => rd_bad,
      wr_fetch => wr_fetch, wr_offset => wr_offset, wr_block => wr_block, wr_data => wr_data,
      mac => mac, rx_ready => rx_ready, rx_len => rx_len, rx_raddr => rx_raddr,
      rx_rdata => rx_rdata, rx_release => rx_release, tx_we => tx_we,
      tx_waddr => tx_waddr, tx_wdata => tx_wdata, tx_go => tx_go, tx_base => tx_base,
      tx_len => tx_len, tx_busy => tx_busy);

  frames : entity work.eth_netsd_buf
    port map (
      clock50 => clock50, cpuclock => cpuclock,
      rx50_start => rx50_start, rx50_we => rx50_we, rx50_addr => rx50_addr,
      rx50_data => rx50_data, rx50_end => rx50_end, rx50_ok => rx50_ok, rx50_len => rx50_len,
      tx50_pending => tx50_pending, tx50_len => tx50_len, tx50_raddr => tx50_raddr,
      tx50_rdata => tx50_rdata, tx50_done => tx50_done,
      rx_ready => rx_ready, rx_len => rx_len, rx_raddr => rx_raddr, rx_rdata => rx_rdata,
      rx_release => rx_release, tx_we => tx_we, tx_waddr => tx_waddr, tx_wdata => tx_wdata,
      tx_go => tx_go, tx_base => tx_base, tx_len => tx_len, tx_busy => tx_busy);

  -- the host's sector buffer: the byte for a fetch in the cycle two after
  -- it (as sdcard_native takes it: G_WR_LAT = 2)
  process(cpuclock)
  begin
    if rising_edge(cpuclock) then
      wr_d1 <= pattern(wr_base + to_integer(wr_block), to_integer(wr_offset));
      wr_data <= wr_d1;
    end if;
  end process;

  -- the wire, at 50 MHz ------------------------------------------------------------
  wire : process
    file txf : text;
    file rxf : text;
    variable l : line;
    variable c, c2 : character;
    variable n : integer;
    variable frame : unsigned(8 * 1100 - 1 downto 0);
    variable ok : boolean;

    function hexval(ch : character) return integer is
    begin
      case ch is
        when '0' to '9' => return character'pos(ch) - character'pos('0');
        when 'a' to 'f' => return character'pos(ch) - character'pos('a') + 10;
        when others => return 0;
      end case;
    end function;
    constant HEX : string(1 to 16) := "0123456789abcdef";
  begin
    file_open(txf, "tb_tx.fifo", write_mode);
    file_open(rxf, "tb_rx.fifo", read_mode);
    loop
      wait until rising_edge(clock50) and (tx50_pending = '1' or finished);
      exit when finished;
      -- read the frame out of the buffer as the TX state machine would
      l := new string'("");
      for a in 0 to to_integer(tx50_len) - 1 loop
        tx50_raddr <= to_unsigned(a, 11);
        wait until rising_edge(clock50);
        wait until rising_edge(clock50);
        wait for 1 ns;
        write(l, HEX(to_integer(tx50_rdata(7 downto 4)) + 1));
        write(l, HEX(to_integer(tx50_rdata(3 downto 0)) + 1));
      end loop;
      -- its time on the wire (about 4 clocks a byte at 100 Mb/s)
      for w in 0 to to_integer(tx50_len) * 4 loop
        wait until rising_edge(clock50);
      end loop;
      writeline(txf, l);
      flush(txf);
      tx50_done <= '1';
      wait until rising_edge(clock50);
      tx50_done <= '0';
      wait until rising_edge(clock50) and tx50_pending = '0';
      -- the answer: frames, then "."
      loop
        readline(rxf, l);
        exit when l'length = 0 or l(l'left) = '.';
        -- inter-frame gap
        for w in 0 to 50 loop
          wait until rising_edge(clock50);
        end loop;
        n := l'length / 2;
        rx50_start <= '1';
        wait until rising_edge(clock50);
        rx50_start <= '0';
        for k in 0 to n - 1 loop
          read(l, c);
          read(l, c2);
          rx50_we <= '1';
          rx50_addr <= to_unsigned(k, 11);
          rx50_data <= to_unsigned(hexval(c) * 16 + hexval(c2), 8);
          wait until rising_edge(clock50);
          rx50_we <= '0';
          for w in 1 to 3 loop
            wait until rising_edge(clock50);
          end loop;
        end loop;
        rx50_end <= '1';
        rx50_ok <= '1';
        rx50_len <= to_unsigned(n + 4, 11);
        wait until rising_edge(clock50);
        rx50_end <= '0';
      end loop;
    end loop;
    file_close(txf);
    file_close(rxf);
    wait;
  end process;

  -- the host -----------------------------------------------------------------------------
  host : process
    file logf : text open write_mode is "tb_reads.txt";
    variable l : line;
    variable buf : unsigned(4095 downto 0);
    variable errors : integer := 0;
    variable good, bad : integer := 0;
    variable sr : unsigned(167 downto 0);
    constant HEX : string(1 to 16) := "0123456789abcdef";

    procedure cmd(code : unsigned(3 downto 0); addr : natural; count : natural; arg : natural) is
    begin
      wait until rising_edge(cpuclock) and cmd_ready = '1';
      cmd_code <= code;
      cmd_addr <= to_unsigned(addr, 32);
      cmd_count <= to_unsigned(count, 16);
      cmd_arg <= to_unsigned(arg, 16);
      cmd_valid <= '1';
      wait until rising_edge(cpuclock);
      cmd_valid <= '0';
      wait until rising_edge(cpuclock) and cmd_ready = '1';
    end procedure;

    procedure check(cond : boolean; msg : string) is
    begin
      if not cond then
        report "FAIL: " & msg severity error;
        errors := errors + 1;
      end if;
    end procedure;

    procedure log_block(lba : natural) is
    begin
      write(l, string'("R "));
      write(l, lba);
      write(l, string'(" "));
      for k in 0 to 511 loop
        write(l, HEX(to_integer(buf(8 * k + 7 downto 8 * k + 4)) + 1));
        write(l, HEX(to_integer(buf(8 * k + 3 downto 8 * k)) + 1));
      end loop;
      writeline(logf, l);
    end procedure;

    -- collect blocks until the transfer ends (busy low) or n are good;
    -- open: grant one more after each good block until n are granted
    procedure collect(addr : natural; n : natural; open_ended : boolean) is
      variable got, granted : natural := 0;
    begin
      granted := 1;
      loop
        wait until rising_edge(cpuclock);
        if rd_valid = '1' then
          buf(8 * to_integer(rd_offset) + 7 downto 8 * to_integer(rd_offset)) := rd_data;
        end if;
        if rd_bad = '1' then
          bad := bad + 1;
        end if;
        if rd_good = '1' then
          check(to_integer(rd_block) = got, "block order");
          log_block(addr + to_integer(rd_block));
          good := good + 1;
          got := got + 1;
          if open_ended and granted < n then
            -- the cache grants the next one
            wait until rising_edge(cpuclock) and cmd_ready = '1';
            cmd_code <= x"4";
            cmd_arg <= (others => '0');
            if granted + 1 = n then
              cmd_arg <= x"0001";            -- the last one
            end if;
            cmd_valid <= '1';
            wait until rising_edge(cpuclock);
            cmd_valid <= '0';
            granted := granted + 1;
          end if;
        end if;
        exit when busy = '0' and cmd_ready = '1' and got > 0 and got >= n;
        exit when err_flag = '1' and cmd_ready = '1';
      end loop;
      check(err_flag = '0', "read error $" & to_hstring(err_code) & " at " & integer'image(addr));
      check(got = n, "read " & integer'image(got) & " of " & integer'image(n) & " blocks at "
            & integer'image(addr));
      wait until rising_edge(cpuclock) and busy = '0';
    end procedure;

    procedure wait_idle is
    begin
      wait until rising_edge(cpuclock) and busy = '0' and cmd_ready = '1';
    end procedure;
  begin
    wait for 200 ns;
    -- the key, flags and entropy, 7 bits a write, then on with octet 65
    sr := to_unsigned(G_FLAGS, 8) & test_key & x"12345678";
    for w in 23 downto 0 loop
      wait until rising_edge(cpuclock);
      ctl_wdata <= '0' & sr(7 * w + 6 downto 7 * w);
      ctl_write <= '1';
      wait until rising_edge(cpuclock);
      ctl_write <= '0';
    end loop;
    wait until rising_edge(cpuclock);
    ctl_wdata <= x"80" or to_unsigned(65, 8);
    ctl_write <= '1';
    wait until rising_edge(cpuclock);
    ctl_write <= '0';
    wait until rising_edge(cpuclock);
    check(active = '1', "on");

    -- connect
    cmd(x"1", 0, 0, 0);
    wait_idle;
    check(card_ready = '1' and err_flag = '0', "connected (error $" & to_hstring(err_code) & ")");
    check(capacity_valid = '1', "capacity known");
    report "connected; last sector " & integer'image(to_integer(last_sector)) &
      ", status $" & to_hstring(ctl_status);

    -- single sector, the MBR
    cmd(x"2", 0, 1, 0);
    collect(0, 1, false);
    -- three sectors from the FAT32 boot sector
    cmd(x"2", 2048, 3, 0);
    collect(2048, 3, false);
    -- an open-ended read granted block by block, 12 blocks (more than one
    -- request of 8), across the FATs
    cmd(x"2", 2048 + 560, 0, 0);
    collect(2048 + 560, 12, true);
    -- eight from the data area, where the files are
    cmd(x"2", 2048 + 568 + 2 * 600, 8, 0);
    collect(2048 + 568 + 2 * 600, 8, false);

    -- writes into the system partition, read back
    wr_base <= 0;
    cmd(x"3", G_SYS_LBA, 2, 0);
    wait_idle;
    check(err_flag = '0' and blocks_done = 2, "write 2 (error $" & to_hstring(err_code) & ")");
    cmd(x"2", G_SYS_LBA, 2, 0);
    collect(G_SYS_LBA, 2, false);
    for k in 0 to 511 loop
      check(buf(8 * k + 7 downto 8 * k) = pattern(1, k), "written data read back");
      exit when buf(8 * k + 7 downto 8 * k) /= pattern(1, k);
    end loop;
    -- an open-ended write of 3
    wr_base <= 10;
    cmd(x"3", G_SYS_LBA + 10, 0, 0);
    for g in 1 to 2 loop
      wait until rising_edge(cpuclock) and to_integer(blocks_done) = g;
      if g = 2 then
        cmd(x"4", 0, 0, 1);
      else
        cmd(x"4", 0, 0, 0);
      end if;
    end loop;
    wait_idle;
    check(err_flag = '0' and blocks_done = 3, "open write 3");
    cmd(x"2", G_SYS_LBA + 12, 1, 0);
    collect(G_SYS_LBA + 12, 1, false);
    check(buf(7 downto 0) = pattern(12, 0) and buf(4095 downto 4088) = pattern(12, 511),
          "open-ended write's third block");

    -- the FAT32 partition is read-only: refused
    cmd(x"3", 2048 + 600, 1, 0);
    wait_idle;
    check(err_flag = '1' and err_code = x"31", "read-only write refused ($" & to_hstring(err_code) & ")");
    -- past the end
    cmd(x"2", to_integer(last_sector) + 1, 1, 0);
    wait_idle;
    check(err_flag = '1' and err_code = x"44", "range");
    -- still fine afterwards
    cmd(x"2", 0, 1, 0);
    collect(0, 1, false);
    -- connect again (a new session, after one with a server nonce) and read
    cmd(x"1", 0, 0, 0);
    wait_idle;
    check(card_ready = '1' and err_flag = '0', "connected again (error $" & to_hstring(err_code) & ")");
    cmd(x"2", 2048, 2, 0);
    collect(2048, 2, false);

    -- switch off
    wait until rising_edge(cpuclock);
    ctl_wdata <= x"80";
    ctl_write <= '1';
    wait until rising_edge(cpuclock);
    ctl_write <= '0';
    wait until rising_edge(cpuclock);
    check(active = '0' and card_ready = '0', "off");

    report "tb_sd_eth: " & integer'image(good) & " blocks read, " & integer'image(bad)
      & " bad tags, " & integer'image(errors) & " errors";
    write(l, string'("DONE "));
    write(l, errors);
    writeline(logf, l);
    file_close(logf);
    finished <= true;
    if errors = 0 then
      report "PASS";
    else
      report "FAILED" severity failure;
    end if;
    wait;
  end process;

  watchdog : process
  begin
    wait for 200 ms;
    if not finished then
      report "watchdog: stuck" severity failure;
    end if;
    wait;
  end process;

end architecture;
