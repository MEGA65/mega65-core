-- Testbench for ethernet.vhdl's SD-over-Ethernet path (#965): frames on the
-- RMII pins into the netsd receive ring, and a frame from the netsd send
-- buffer out on the RMII pins.
--
--   * a good frame (preamble, SFD, bytes, FCS) arrives: it is committed with
--     its length (FCS included) and reads back byte for byte;
--   * a frame with a bad FCS is not committed;
--   * a 60-byte frame put in the send buffer goes out (after the CPU frames'
--     priority, of which there are none here) with preamble, SFD, the bytes
--     and a correct FCS, and netsd_tx_busy falls afterwards.
--
--   ghdl -a --std=93c -fsynopsys -frelaxed (debugtools, ghdl_ram8x2048,
--     eth_beacon_ram, crc, ethernet_miim, asym_ram, eth_netsd_buf,
--     ethernet, this) ; ghdl -r ... tb_ethernet_netsd
-- Passes when it reports PASS.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;

entity tb_ethernet_netsd is
end entity;

architecture sim of tb_ethernet_netsd is
  signal cpuclock, clock50, clock200 : std_logic := '0';
  signal finished : boolean := false;

  signal eth_rxd : unsigned(1 downto 0) := "00";
  signal eth_rxdv : std_logic := '0';
  signal eth_txd : unsigned(1 downto 0);
  signal eth_txen : std_logic;
  signal eth_mdio : std_logic := 'H';

  signal rx_ready, rx_release, tx_we, tx_go, tx_busy : std_logic := '0';
  signal rx_len, tx_waddr, tx_len : unsigned(10 downto 0) := (others => '0');
  signal rx_raddr : unsigned(9 downto 0) := (others => '0');
  signal rx_rdata, tx_wdata : unsigned(7 downto 0) := (others => '0');
  signal mac : unsigned(47 downto 0);

  type bytes_t is array (natural range <>) of unsigned(7 downto 0);

  function crc32(b : bytes_t) return unsigned is
    variable c : unsigned(31 downto 0) := (others => '1');
  begin
    for i in b'range loop
      c := c xor resize(b(i), 32);
      for k in 0 to 7 loop
        if c(0) = '1' then
          c := shift_right(c, 1) xor x"EDB88320";
        else
          c := shift_right(c, 1);
        end if;
      end loop;
    end loop;
    return not c;
  end function;

  function frame_bytes(n : natural; seed : natural) return bytes_t is
    variable f : bytes_t(0 to n - 1);
  begin
    for i in 0 to n - 1 loop
      f(i) := to_unsigned((i * 37 + seed) mod 256, 8);
    end loop;
    f(0 to 5) := (x"02", x"47", x"53", x"65", x"65", x"65");   -- to us
    return f;
  end function;

  constant RX1 : bytes_t := frame_bytes(100, 3);
  constant TX1 : bytes_t := frame_bytes(60, 11);
begin
  cpuclock <= not cpuclock after 12.345 ns when not finished;
  clock50 <= not clock50 after 10 ns when not finished;
  clock200 <= not clock200 after 2.5 ns when not finished;

  dut : entity work.ethernet
    generic map (num_buffers => 4, netsd => true)
    port map (
      clock => cpuclock, clock50mhz => clock50, clock200 => clock200, reset => '1',
      irq => open, ethernet_cs => '0', cpu_ethernet_stream => open,
      eth_remote_control => '0', eth_load_enable => '0',
      eth_mdio => eth_mdio, eth_mdc => open, eth_reset => open,
      eth_rxd_in => eth_rxd, eth_txd_out => eth_txd, eth_txen_out => eth_txen,
      eth_rxdv_in => eth_rxdv, eth_rxer => '0', eth_interrupt => '0',
      fastio_addr => (others => '0'), fastio_write => '0', fastio_read => '0',
      fastio_wdata => (others => '0'), fastio_rdata => open,
      buffer_moby_toggle => '0', buffer_offset => (others => '0'), buffer_address => open,
      buffer_rdata => (others => '0'), instruction_strobe => '0',
      raster_number => (others => '0'), vicii_raster => (others => '0'),
      badline_toggle => '0', debug_vector => (others => '0'), d031_write_toggle => '0',
      cpu_arrest => open, eth_keycode_toggle => open, eth_keycode => open,
      netsd_mac => mac, netsd_rx_ready => rx_ready, netsd_rx_len => rx_len,
      netsd_rx_raddr => rx_raddr, netsd_rx_rdata => rx_rdata, netsd_rx_release => rx_release,
      netsd_tx_we => tx_we, netsd_tx_waddr => tx_waddr, netsd_tx_wdata => tx_wdata,
      netsd_tx_go => tx_go, netsd_tx_base => '0', netsd_tx_len => tx_len,
      netsd_tx_busy => tx_busy);

  process
    variable errors : integer := 0;
    variable fcs : unsigned(31 downto 0);
    variable got : bytes_t(0 to 199);
    variable n, bitn : integer;
    variable sh : unsigned(7 downto 0);
    variable inframe : boolean;

    procedure check(c : boolean; msg : string) is
    begin
      if not c then
        report "FAIL: " & msg severity error;
        errors := errors + 1;
      end if;
    end procedure;

    -- one byte on the RMII receive pins, low dibit first, set up on the
    -- falling edge so the 200 MHz sampler sees it settled
    procedure rmii_byte(b : unsigned(7 downto 0)) is
    begin
      for d in 0 to 3 loop
        wait until falling_edge(clock50);
        eth_rxdv <= '1';
        eth_rxd <= b(2 * d + 1 downto 2 * d);
      end loop;
    end procedure;

    procedure send_frame(f : bytes_t; good : boolean) is
      variable c : unsigned(31 downto 0);
    begin
      for i in 0 to 6 loop
        rmii_byte(x"55");
      end loop;
      rmii_byte(x"D5");
      for i in f'range loop
        rmii_byte(f(i));
      end loop;
      c := crc32(f);
      if not good then
        c := c xor x"00000100";
      end if;
      for i in 0 to 3 loop
        rmii_byte(c(8 * i + 7 downto 8 * i));
      end loop;
      wait until falling_edge(clock50);
      eth_rxdv <= '0';
      eth_rxd <= "00";
      for i in 0 to 100 loop
        wait until falling_edge(clock50);
      end loop;
    end procedure;
  begin
    wait for 2 us;
    report "MAC " & to_hstring(mac);

    -- a good frame
    send_frame(RX1, true);
    wait until rising_edge(cpuclock) and rx_ready = '1' for 20 us;
    check(rx_ready = '1', "good frame committed");
    check(to_integer(rx_len) = RX1'length + 4, "length " & integer'image(to_integer(rx_len)));
    for i in RX1'range loop
      wait until rising_edge(cpuclock);
      rx_raddr <= to_unsigned(i, 10);
      wait until rising_edge(cpuclock);
      wait until rising_edge(cpuclock);
      wait until rising_edge(cpuclock);
      if rx_rdata /= RX1(i) then
        check(false, "byte " & integer'image(i) & " $" & to_hstring(rx_rdata) & " want $" & to_hstring(RX1(i)));
        exit;
      end if;
    end loop;
    wait until rising_edge(cpuclock);
    rx_release <= '1';
    wait until rising_edge(cpuclock);
    rx_release <= '0';
    wait for 1 us;
    check(rx_ready = '0', "released");

    -- a bad FCS: not committed
    send_frame(RX1, false);
    wait for 5 us;
    check(rx_ready = '0', "bad frame not committed");

    -- a frame out
    for i in TX1'range loop
      wait until rising_edge(cpuclock);
      tx_we <= '1';
      tx_waddr <= to_unsigned(i, 11);
      tx_wdata <= TX1(i);
    end loop;
    wait until rising_edge(cpuclock);
    tx_we <= '0';
    tx_len <= to_unsigned(TX1'length, 11);
    tx_go <= '1';
    wait until rising_edge(cpuclock);
    tx_go <= '0';
    wait until rising_edge(cpuclock);
    check(tx_busy = '1', "busy while sending");
    -- collect the dibits while TXEN, sampled at the 50 MHz rising edge
    wait until eth_txen = '1' for 50 us;
    check(eth_txen = '1', "TXEN");
    n := 0;
    bitn := 0;
    sh := x"00";
    inframe := false;
    while eth_txen = '1' loop
      wait until rising_edge(clock50);
      exit when eth_txen = '0';
      sh := eth_txd & sh(7 downto 2);
      bitn := bitn + 2;
      if not inframe then
        -- hunt for the SFD's last dibit (11) after preamble (01s)
        if eth_txd = "11" then
          inframe := true;
          bitn := 0;
        end if;
      elsif bitn = 8 then
        if n <= got'high then
          got(n) := sh;
        end if;
        n := n + 1;
        bitn := 0;
      end if;
    end loop;
    check(n = TX1'length + 4, "sent " & integer'image(n) & " bytes, want " & integer'image(TX1'length + 4));
    for i in TX1'range loop
      if got(i) /= TX1(i) then
        check(false, "sent byte " & integer'image(i) & " $" & to_hstring(got(i)) & " want $" & to_hstring(TX1(i)));
        exit;
      end if;
    end loop;
    fcs := crc32(TX1);
    check(got(60) = fcs(7 downto 0) and got(61) = fcs(15 downto 8)
          and got(62) = fcs(23 downto 16) and got(63) = fcs(31 downto 24),
          "FCS " & to_hstring(got(60)) & to_hstring(got(61)) & to_hstring(got(62)) & to_hstring(got(63))
          & " want (LE) " & to_hstring(fcs));
    wait for 5 us;
    check(tx_busy = '0', "not busy after");

    if errors = 0 then
      report "PASS";
    else
      report "FAILED: " & integer'image(errors) & " errors" severity failure;
    end if;
    finished <= true;
    wait;
  end process;
end architecture;
