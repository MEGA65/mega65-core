--------------------------------------------------------------------------------
-- tb_fat32_engine: replays a transcript of the instruction-set simulator
-- (MEGA65/mega65-core#766) against fat32_engine, comparing the whole sector
-- buffer, the status, $D681-$D684 and every sector written, after every
-- command.
--
--   python3 src/tools/test_fat32_engine.py --short --rtl
--   (or --trace trace.txt, then ghdl -r --std=08 tb_fat32_engine -gG_TRACE=trace.txt)
--
-- Transcript lines (hex):
--   S slot lba data       a sector as the commands first read it (512 bytes)
--   W addr bytes          the buffer before the next command
--   C cmd arg hyp media   a command (media: the cards changed)
--   V slot lba data       a sector it wrote (in order)
--   E addr bytes          the buffer after it (the changes)
--   R status arg steps    its result (steps: the simulator's instructions)
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_fat32_engine is
  generic (
    G_TRACE  : string := "trace.txt";
    G_RD_LAT : positive := 2;
    G_SEC_DELAY : natural := 20         -- cycles a sector operation takes
    );
end entity;

architecture tb of tb_fat32_engine is

  signal clock : std_logic := '0';
  signal done  : boolean := false;

  signal start, hyp : std_logic := '0';
  signal media : std_logic_vector(1 downto 0) := "00";
  signal cmd    : unsigned(7 downto 0) := (others => '0');
  signal arg_in : unsigned(31 downto 0) := (others => '0');
  signal busy   : std_logic;
  signal status : unsigned(7 downto 0);
  signal arg_out : unsigned(31 downto 0);
  signal mem_raddr, mem_waddr : unsigned(11 downto 0);
  signal mem_rdata, mem_wdata : unsigned(7 downto 0) := (others => '0');
  signal mem_we : std_logic;
  signal sec_req, sec_write, sec_cpu, sec_slot : std_logic;
  signal sec_lba : unsigned(31 downto 0);
  signal sec_done, sec_err : std_logic := '0';

  constant HBITS  : natural := 15;      -- the sector table: 32768 (hashed)
  constant NSEC   : natural := 2 ** HBITS;
  constant MAXW   : natural := 4096;    -- sectors written by one command

begin

  clock <= not clock after 12345 ps when not done;

  dut : entity work.fat32_engine
    generic map (G_RD_LAT => G_RD_LAT)
    port map (
      clock => clock, reset => '0',
      start => start, cmd => cmd, arg_in => arg_in, hypervisor => hyp, media => media,
      busy => busy, status => status, arg_out => arg_out,
      mem_raddr => mem_raddr, mem_rdata => mem_rdata, mem_we => mem_we,
      mem_waddr => mem_waddr, mem_wdata => mem_wdata,
      sec_req => sec_req, sec_write => sec_write, sec_cpu => sec_cpu,
      sec_slot => sec_slot, sec_lba => sec_lba, sec_done => sec_done,
      sec_err => sec_err);

  run : process
    type t_mem is array(0 to 4095) of natural range 0 to 255;
    type t_secdata is array(0 to NSEC * 512 - 1) of natural range 0 to 255;
    type t_seckey is array(0 to NSEC - 1) of unsigned(32 downto 0);
    type t_used is array(0 to NSEC - 1) of boolean;
    type t_wdata is array(0 to MAXW * 512 - 1) of natural range 0 to 255;
    type t_wkey is array(0 to MAXW - 1) of unsigned(32 downto 0);
    type t_pipe is array(0 to 7) of natural range 0 to 255;
    variable mem, expect : t_mem := (others => 0);
    variable secdata : t_secdata;
    variable seckey  : t_seckey;
    variable used    : t_used := (others => false);
    variable nsecs   : natural := 0;
    variable wdata   : t_wdata;
    variable wkey    : t_wkey;
    variable nw, nv  : natural := 0;
    variable pipe    : t_pipe := (others => 0);
    file f           : text;
    variable ln      : line;
    variable pos     : natural;
    variable kind    : character;
    variable a, b, n : natural;
    variable v32     : unsigned(31 downto 0);
    variable fails, cmds : natural := 0;
    variable cycles, total_cycles, total_steps, total_writes : natural := 0;
    variable sec_wait : natural := 0;
    variable key     : unsigned(32 downto 0);
    variable slotno  : integer;
    variable shown   : natural;

    function hexval(ch : character) return natural is
    begin
      case ch is
        when '0' to '9' => return character'pos(ch) - character'pos('0');
        when 'A' to 'F' => return character'pos(ch) - character'pos('A') + 10;
        when 'a' to 'f' => return character'pos(ch) - character'pos('a') + 10;
        when others => return 0;
      end case;
    end function;

    procedure skip_spaces is
    begin
      while pos <= ln'length and ln(pos) = ' ' loop
        pos := pos + 1;
      end loop;
    end procedure;

    -- the next hex field as an unsigned (at most 32 bits)
    procedure field(v : out unsigned(31 downto 0)) is
      variable acc : unsigned(31 downto 0) := (others => '0');
    begin
      skip_spaces;
      while pos <= ln'length and ln(pos) /= ' ' loop
        acc := acc(27 downto 0) & to_unsigned(hexval(ln(pos)), 4);
        pos := pos + 1;
      end loop;
      v := acc;
    end procedure;

    -- the table slot of a sector (create: claim a free one), -1: none
    procedure lookup(k : unsigned(32 downto 0); create : boolean; idx : out integer) is
      variable h : natural;
    begin
      h := to_integer(k(HBITS - 1 downto 0) xor (k(32) & k(HBITS + 13 downto HBITS)));
      for i in 0 to NSEC - 1 loop
        if not used(h) then
          if create then
            used(h) := true;
            seckey(h) := k;
            nsecs := nsecs + 1;
            idx := h;
          else
            idx := -1;
          end if;
          return;
        elsif seckey(h) = k then
          idx := h;
          return;
        end if;
        h := (h + 1) mod NSEC;
      end loop;
      assert false report "sector table full" severity failure;
    end procedure;

    -- one clock, with the memory and the card served
    procedure tick is
    begin
      wait until rising_edge(clock);
      -- read port: G_RD_LAT cycles from the address register
      for i in 7 downto 1 loop
        pipe(i) := pipe(i - 1);
      end loop;
      pipe(0) := mem(to_integer(mem_raddr));
      mem_rdata <= to_unsigned(pipe(G_RD_LAT - 1), 8);
      if mem_we = '1' then
        mem(to_integer(mem_waddr)) := to_integer(mem_wdata);
      end if;
      sec_done <= '0';
      if sec_req = '1' and sec_done = '0' then
        if sec_wait < G_SEC_DELAY then
          sec_wait := sec_wait + 1;
        else
          sec_wait := 0;
          key := sec_slot & sec_lba;
          sec_err <= '0';
          if sec_write = '1' then
            -- kept for the V lines, and for later reads
            assert nw < MAXW report "too many sector writes in one command" severity failure;
            wkey(nw) := key;
            lookup(key, true, slotno);
            for k in 0 to 511 loop
              if sec_cpu = '1' then
                b := mem(16#E00# + k);
              else
                b := mem(16#800# + k);
              end if;
              wdata(nw * 512 + k) := b;
              secdata(slotno * 512 + k) := b;
            end loop;
            nw := nw + 1;
          else
            lookup(key, false, slotno);
            if slotno < 0 then
              sec_err <= '1';
            else
              for k in 0 to 511 loop
                if sec_cpu = '1' then
                  mem(16#E00# + k) := secdata(slotno * 512 + k);
                else
                  mem(16#800# + k) := secdata(slotno * 512 + k);
                end if;
              end loop;
            end if;
          end if;
          sec_done <= '1';
        end if;
      end if;
    end procedure;

  begin
    file_open(f, G_TRACE, read_mode);
    while not endfile(f) loop
      readline(f, ln);
      next when ln'length = 0;
      kind := ln(1);
      pos := 2;
      case kind is
        when 'S' =>
          field(v32);
          key(32) := v32(0);
          field(v32);
          key(31 downto 0) := v32;
          lookup(key, true, slotno);
          skip_spaces;
          for k in 0 to 511 loop
            secdata(slotno * 512 + k) := hexval(ln(pos + 2 * k)) * 16 + hexval(ln(pos + 2 * k + 1));
          end loop;
        when 'W' | 'E' =>
          field(v32);
          a := to_integer(v32);
          skip_spaces;
          n := (ln'length - pos + 1) / 2;
          for k in 0 to n - 1 loop
            b := hexval(ln(pos + 2 * k)) * 16 + hexval(ln(pos + 2 * k + 1));
            expect((a + k) mod 4096) := b;
            if kind = 'W' then
              mem((a + k) mod 4096) := b;
            end if;
          end loop;
        when 'C' =>
          field(v32);
          cmd <= v32(7 downto 0);
          field(v32);
          arg_in <= v32;
          field(v32);
          hyp <= v32(0);
          field(v32);
          media <= std_logic_vector(v32(1 downto 0));
          nw := 0;
          nv := 0;
          start <= '1';
          tick;
          start <= '0';
          cycles := 1;
          tick;
          while busy = '1' loop
            tick;
            cycles := cycles + 1;
            assert cycles < 200_000_000 report "command never ends" severity failure;
          end loop;
          cmds := cmds + 1;
        when 'V' =>
          field(v32);
          key(32) := v32(0);
          field(v32);
          key(31 downto 0) := v32;
          skip_spaces;
          if nv >= nw then
            report "command " & integer'image(cmds) & " ($" & to_hstring(cmd)
              & "): a sector write missing, LBA $" & to_hstring(key(31 downto 0)) severity error;
            fails := fails + 1;
          elsif wkey(nv) /= key then
            report "command " & integer'image(cmds) & " ($" & to_hstring(cmd) & "): write "
              & integer'image(nv) & " to LBA $" & to_hstring(wkey(nv)(31 downto 0))
              & ", expected $" & to_hstring(key(31 downto 0)) severity error;
            fails := fails + 1;
          else
            shown := 0;
            for k in 0 to 511 loop
              if wdata(nv * 512 + k) /= hexval(ln(pos + 2 * k)) * 16 + hexval(ln(pos + 2 * k + 1)) then
                shown := shown + 1;
              end if;
            end loop;
            if shown /= 0 then
              report "command " & integer'image(cmds) & " ($" & to_hstring(cmd) & "): write "
                & integer'image(nv) & " to LBA $" & to_hstring(key(31 downto 0)) & ": "
                & integer'image(shown) & " bytes differ" severity error;
              fails := fails + 1;
            end if;
          end if;
          nv := nv + 1;
        when 'R' =>
          if nw /= nv then
            report "command " & integer'image(cmds) & " ($" & to_hstring(cmd) & "): "
              & integer'image(nw) & " sector writes, expected " & integer'image(nv) severity error;
            fails := fails + 1;
          end if;
          total_writes := total_writes + nw;
          field(v32);
          if status /= v32(7 downto 0) then
            report "command " & integer'image(cmds) & " ($" & to_hstring(cmd) & "): status "
              & to_hstring(status) & ", expected " & to_hstring(v32(7 downto 0)) severity error;
            fails := fails + 1;
          end if;
          field(v32);
          if arg_out /= v32 then
            report "command " & integer'image(cmds) & ": arg " & to_hstring(arg_out)
              & ", expected " & to_hstring(v32) severity error;
            fails := fails + 1;
          end if;
          field(v32);
          total_steps := total_steps + to_integer(v32);
          total_cycles := total_cycles + cycles;
          shown := 0;
          for i in 0 to 4095 loop
            if mem(i) /= expect(i) then
              if shown < 8 then
                report "command " & integer'image(cmds) & " ($" & to_hstring(cmd)
                  & "): buffer $" & to_hstring(to_unsigned(i, 12)) & " = "
                  & integer'image(mem(i)) & ", expected " & integer'image(expect(i))
                  severity error;
              end if;
              shown := shown + 1;
            end if;
          end loop;
          if shown /= 0 then
            fails := fails + 1;
            mem := expect;               -- (carry on from the right state)
          end if;
          if fails > 20 then
            report "too many failures" severity failure;
          end if;
        when others =>
          null;
      end case;
    end loop;
    report integer'image(cmds) & " commands, " & integer'image(nsecs) & " sectors, "
      & integer'image(total_writes) & " written, "
      & integer'image(total_cycles) & " cycles for " & integer'image(total_steps)
      & " simulator instructions";
    if fails = 0 then
      report "ALL FAT32 ENGINE TESTS PASSED";
    else
      report integer'image(fails) & " TESTS FAILED" severity error;
    end if;
    done <= true;
    wait;
  end process;

end architecture;
