-- Replays fpu_vectors.txt (from gen_fpu_vectors.py) through ssnail_fpu.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use work.ssnail_fpu_pkg.all;
use work.debugtools.all;

entity tb_ssnail_fpu is
end entity;

architecture test of tb_ssnail_fpu is
  signal clock : std_logic := '0';
  signal start, done : std_logic := '0';
  signal op : unsigned(3 downto 0) := "0000";
  signal a, b, result : unsigned(31 downto 0) := (others => '0');
  signal finished : boolean := false;
begin
  clock <= not clock after 3 ns when not finished;
  fpu : entity work.ssnail_fpu port map (clock => clock, start => start, op => op,
                                         a => a, b => b, done => done, result => result);
  process
    file f : text open read_mode is "fpu_vectors.txt";
    variable l : line;
    variable vop : integer;
    variable va, vb, ve : std_logic_vector(31 downto 0);
    variable got, expv : unsigned(31 downto 0);
    variable n, bad : integer := 0;
    variable nan_e, nan_g : boolean;
    type counts_t is array (0 to 9) of integer;
    variable per_op, bad_op : counts_t := (others => 0);
  begin
    while not endfile(f) loop
      readline(f, l);
      read(l, vop); hread(l, va); hread(l, vb); hread(l, ve);
      wait until rising_edge(clock);
      op <= to_unsigned(vop, 4); a <= unsigned(va); b <= unsigned(vb); start <= '1';
      wait until rising_edge(clock);
      start <= '0';
      loop
        wait until rising_edge(clock);
        exit when done = '1';
      end loop;
      got := result;
      expv := unsigned(ve);
      if vop = 7 or vop = 9 then
        nan_e := false; nan_g := false;
      elsif vop = 3 then
        nan_e := expv(14 downto 10) = "11111" and expv(9 downto 0) /= 0;
        nan_g := got(14 downto 10) = "11111" and got(9 downto 0) /= 0;
      else
        nan_e := expv(30 downto 23) = x"FF" and expv(22 downto 0) /= 0;
        nan_g := got(30 downto 23) = x"FF" and got(22 downto 0) /= 0;
      end if;
      n := n + 1;
      per_op(vop) := per_op(vop) + 1;
      if not ((nan_e and nan_g) or (not nan_e and got = expv)) then
        bad := bad + 1;
        bad_op(vop) := bad_op(vop) + 1;
        if bad <= 12 then
          report "MISMATCH op " & integer'image(vop) & " a=" & to_hstring(unsigned(va))
            & " b=" & to_hstring(unsigned(vb)) & " got " & to_hstring(got)
            & " expected " & to_hstring(expv) severity error;
        end if;
      end if;
    end loop;
    for i in 0 to 9 loop
      report "op " & integer'image(i) & ": " & integer'image(per_op(i) - bad_op(i)) & "/"
        & integer'image(per_op(i)) & " exact";
    end loop;
    if bad = 0 then
      report "TB_SSNAIL_FPU: ALL PASSED (" & integer'image(n) & " vectors)";
    else
      report "TB_SSNAIL_FPU: " & integer'image(bad) & " FAILURES" severity error;
    end if;
    finished <= true;
    wait;
  end process;
end test;
