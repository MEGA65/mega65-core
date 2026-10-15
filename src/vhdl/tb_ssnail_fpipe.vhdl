-- Streams fpipe_vectors.txt's ADD and MUL vectors (from gen_fpipe_vectors.py)
-- through ssnail_fadd_p and ssnail_fmul_p, one a cycle, results matched to
-- the vectors by tag.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use work.debugtools.all;

entity tb_ssnail_fpipe is
end entity;

architecture test of tb_ssnail_fpipe is
  constant NMAX : integer := 400000;
  signal clock : std_logic := '0';
  signal finished : boolean := false;
  signal av, mv, arv, mrv : std_logic := '0';
  signal aa, ab, ma, mb, ar, mr : unsigned(31 downto 0) := (others => '0');
  signal atag, mtag, artag, mrtag : unsigned(18 downto 0) := (others => '0');
begin
  clock <= not clock after 3 ns when not finished;
  fa : entity work.ssnail_fadd_p generic map (TAGW => 19)
    port map (clock => clock, v => av, a => aa, b => ab, tag => atag, rv => arv, r => ar, rtag => artag);
  fm : entity work.ssnail_fmul_p generic map (TAGW => 19)
    port map (clock => clock, v => mv, a => ma, b => mb, tag => mtag, rv => mrv, r => mr, rtag => mrtag);

  process
    type w_t is array (0 to NMAX - 1) of unsigned(31 downto 0);
    type i_t is array (0 to NMAX - 1) of integer range 0 to 15;
    variable va, vb, ve : w_t;
    variable vop : i_t;
    file f : text open read_mode is "fpipe_vectors.txt";
    variable l : line;
    variable o : integer;
    variable x, y, z : std_logic_vector(31 downto 0);
    variable n, na, nm, ia, im, got_a, got_m, bad : integer := 0;
    procedure chk(r : unsigned(31 downto 0); t : unsigned(18 downto 0); name : string) is
      variable e : unsigned(31 downto 0);
      variable ne, ng : boolean;
    begin
      e := ve(to_integer(t));
      ne := e(30 downto 23) = x"FF" and e(22 downto 0) /= 0;
      ng := r(30 downto 23) = x"FF" and r(22 downto 0) /= 0;
      if not ((ne and ng) or (not ne and r = e)) then
        bad := bad + 1;
        if bad < 25 then
          report "MISMATCH " & name & " a=" & to_hstring(va(to_integer(t))) & " b="
            & to_hstring(vb(to_integer(t))) & " got " & to_hstring(r) & " expected " & to_hstring(e)
            severity error;
        end if;
      end if;
    end procedure;
  begin
    while not endfile(f) loop
      readline(f, l);
      read(l, o); hread(l, x); hread(l, y); hread(l, z);
      if o = 0 or o = 1 then
        vop(n) := o; va(n) := unsigned(x); vb(n) := unsigned(y); ve(n) := unsigned(z);
        if o = 0 then na := na + 1; else nm := nm + 1; end if;
        n := n + 1;
      end if;
    end loop;
    -- both units fed every cycle, each from its own vectors; results checked
    -- as they come out
    loop
      while ia < n and vop(ia) /= 0 loop ia := ia + 1; end loop;
      while im < n and vop(im) /= 1 loop im := im + 1; end loop;
      av <= '0'; mv <= '0';
      if ia < n then av <= '1'; aa <= va(ia); ab <= vb(ia); atag <= to_unsigned(ia, 19); ia := ia + 1; end if;
      if im < n then mv <= '1'; ma <= va(im); mb <= vb(im); mtag <= to_unsigned(im, 19); im := im + 1; end if;
      wait until rising_edge(clock);
      if arv = '1' then chk(ar, artag, "ADD"); got_a := got_a + 1; end if;
      if mrv = '1' then chk(mr, mrtag, "MUL"); got_m := got_m + 1; end if;
      exit when got_a = na and got_m = nm;
    end loop;
    if bad = 0 then
      report "TB_SSNAIL_FPIPE: ALL PASSED (" & integer'image(got_a) & " adds, "
        & integer'image(got_m) & " multiplies)";
    else
      report "TB_SSNAIL_FPIPE: " & integer'image(bad) & " FAILURES" severity error;
    end if;
    finished <= true;
    wait;
  end process;
end architecture;
