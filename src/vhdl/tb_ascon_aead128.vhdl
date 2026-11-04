-- Testbench for ascon_aead128 (#965): runs an operation script from
-- src/tools/gen_ascon_vectors.py and checks every output block and tag.
--
--   python3 src/tools/gen_ascon_vectors.py ascon_vectors.txt
--   ghdl -a --std=08 src/vhdl/ascon_aead128.vhdl src/vhdl/tb_ascon_aead128.vhdl
--   ghdl -r --std=08 tb_ascon_aead128      (reads ascon_vectors.txt from the
--                                          current directory; -gG_VECTORS=)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_ascon_aead128 is
  generic (G_VECTORS : string := "ascon_vectors.txt");
end entity;

architecture sim of tb_ascon_aead128 is
  signal clk      : std_logic := '0';
  signal op_valid : std_logic := '0';
  signal op       : unsigned(2 downto 0) := "000";
  signal key      : unsigned(127 downto 0) := (others => '0');
  signal nonce    : unsigned(127 downto 0) := (others => '0');
  signal blk_in   : unsigned(127 downto 0) := (others => '0');
  signal blk_len  : unsigned(4 downto 0) := (others => '0');
  signal busy     : std_logic;
  signal blk_out  : unsigned(127 downto 0);
  signal tag_out  : unsigned(127 downto 0);
  signal done     : boolean := false;

  function low_mask(len : integer) return unsigned is
    variable m : unsigned(127 downto 0) := (others => '0');
  begin
    for i in 0 to 15 loop
      if i < len then
        m(i * 8 + 7 downto i * 8) := (others => '1');
      end if;
    end loop;
    return m;
  end function;
begin

  clk <= not clk after 12 ns when not done;

  dut : entity work.ascon_aead128
    port map (clk => clk, op_valid => op_valid, op => op, key => key, nonce => nonce,
              blk_in => blk_in, blk_len => blk_len, busy => busy,
              blk_out => blk_out, tag_out => tag_out);

  process
    file f : text open read_mode is G_VECTORS;
    variable l : line;
    variable c : character;
    variable n : integer;
    variable a, b : std_logic_vector(127 downto 0);
    variable ops, errors, cycles : integer := 0;

    procedure issue(o : unsigned(2 downto 0)) is
    begin
      op <= o;
      op_valid <= '1';
      wait until rising_edge(clk);
      op_valid <= '0';
      wait until rising_edge(clk);        -- blk_out is registered
      cycles := cycles + 1;
      while busy = '1' loop
        wait until rising_edge(clk);
        cycles := cycles + 1;
      end loop;
      ops := ops + 1;
    end procedure;
  begin
    wait until rising_edge(clk);
    while not endfile(f) loop
      readline(f, l);
      next when l'length = 0;
      read(l, c);
      case c is
        when 'I' =>
          hread(l, a);
          hread(l, b);
          key <= unsigned(a);
          nonce <= unsigned(b);
          issue("000");
        when 'A' =>
          read(l, n);
          hread(l, a);
          blk_in <= unsigned(a);
          blk_len <= to_unsigned(n, 5);
          issue("001");
        when 'S' =>
          issue("010");
        when 'E' | 'D' =>
          read(l, n);
          hread(l, a);
          hread(l, b);
          blk_in <= unsigned(a);
          blk_len <= to_unsigned(n, 5);
          if c = 'E' then
            issue("011");
          else
            issue("100");
          end if;
          if (blk_out and low_mask(n)) /= unsigned(b) then
            report "op " & integer'image(ops) & " (" & c & "): got " & to_hstring(blk_out and low_mask(n))
              & " want " & to_hstring(b) severity error;
            errors := errors + 1;
          end if;
        when 'F' =>
          hread(l, a);
          issue("101");
          if tag_out /= unsigned(a) then
            report "op " & integer'image(ops) & ": tag " & to_hstring(tag_out) & " want " & to_hstring(a)
              severity error;
            errors := errors + 1;
          end if;
        when others =>
          report "bad script line" severity failure;
      end case;
    end loop;
    report "ascon: " & integer'image(ops) & " operations, " & integer'image(errors) & " errors"
      severity note;
    assert errors = 0 report "FAILED" severity failure;
    report "PASS" severity note;
    done <= true;
    wait;
  end process;
end architecture;
