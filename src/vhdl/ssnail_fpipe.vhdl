-- SSNAIL pipelined F32 multiplier and adder.
--
-- One operation a cycle each, a fixed latency (FMUL_LAT, FADD_LAT from v
-- to rv), and a tag carried alongside.  Bit-exact with ssnail_fpu (and so
-- with numpy's float32): round to nearest, ties to even; subnormals in and
-- out; NaN results canonical ($7FC00000); x + (-x) = +0, (-0) + (-0) = -0.
--
-- Both end in the same rounding and packing: a 24-bit significand m (the
-- hidden bit at m(23)), its exponent E >= 1 (a subnormal has E = 1 and
-- m(23) = 0), guard and sticky bits; the result is ((E - 1) << 23) + m,
-- plus one to round up (a carry runs into the exponent, as it should),
-- and an infinity from $7F800000 up.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ssnail_fpipe_pkg is
  constant FMUL_LAT : integer := 8;
  constant FADD_LAT : integer := 8;
  function fp_pack(s : std_logic; e : integer; m : unsigned(23 downto 0);
                   g, st : std_logic) return unsigned;
  function lzc(x : unsigned) return integer;
end package;

package body ssnail_fpipe_pkg is
  function fp_pack(s : std_logic; e : integer; m : unsigned(23 downto 0);
                   g, st : std_logic) return unsigned is
    variable r : unsigned(33 downto 0);
  begin
    r := shift_left(to_unsigned(e - 1, 34), 23) + resize(m, 34);
    if g = '1' and (st = '1' or m(0) = '1') then
      r := r + 1;
    end if;
    if r >= x"7F800000" then
      r := resize(x"7F800000", 34);
    end if;
    return s & r(30 downto 0);
  end function;
  -- leading zeros of x (x'length if zero)
  function lzc(x : unsigned) return integer is
    variable v : unsigned(x'length - 1 downto 0) := x;
  begin
    for i in v'high downto 0 loop
      if v(i) = '1' then
        return v'high - i;
      end if;
    end loop;
    return v'length;
  end function;
end package body;

-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ssnail_fpipe_pkg.all;

entity ssnail_fmul_p is
  generic (TAGW : integer := 8);
  port (
    clock : in std_logic;
    v     : in std_logic;
    a, b  : in unsigned(31 downto 0);
    tag   : in unsigned(TAGW - 1 downto 0);
    rv    : out std_logic;
    r     : out unsigned(31 downto 0);
    rtag  : out unsigned(TAGW - 1 downto 0)
  );
end entity;

architecture rtl of ssnail_fmul_p is
  -- special results: 0 none, 1 NaN, 2 infinity, 3 zero
  type spec_t is array (1 to 7) of unsigned(1 downto 0);
  type tag_t is array (0 to 7) of unsigned(TAGW - 1 downto 0);
  type int_t is array (2 to 6) of integer range -512 to 511;
  signal vp : std_logic_vector(0 to 7) := (others => '0');
  signal tg : tag_t := (others => (others => '0'));
  signal sp : spec_t := (others => "00");
  signal sg : std_logic_vector(1 to 7) := (others => '0');
  signal a0, b0 : unsigned(31 downto 0) := (others => '0');
  signal ma1, mb1 : unsigned(23 downto 0) := (others => '0');
  signal es1 : integer range -512 to 511 := 0;
  signal e0 : int_t := (others => 0);            -- exponent if the top bit is m(47)
  signal m2, m3, m4 : unsigned(47 downto 0) := (others => '0');
  signal lz4 : integer range 0 to 48 := 0;
  signal left5 : boolean := true;
  signal sh5 : integer range 0 to 63 := 0;
  signal m5 : unsigned(47 downto 0) := (others => '0');
  signal e5, e6 : integer range -512 to 511 := 1;
  signal n6 : unsigned(47 downto 0) := (others => '0');
  signal rs6 : std_logic := '0';
  signal r7 : unsigned(31 downto 0) := (others => '0');
begin
  rv <= vp(7);
  r <= r7;
  rtag <= tg(7);

  process (clock) is
    variable ea, eb : integer range 0 to 255;
    variable an, bn, ai, bi, az, bz : boolean;
    variable el : integer range -512 to 511;
    variable rw : unsigned(47 downto 0);
    variable st : std_logic;
  begin
    if rising_edge(clock) then
      -- 0: inputs
      vp(0) <= v; tg(0) <= tag; a0 <= a; b0 <= b;

      -- 1: unpack (a subnormal: exponent 1, no hidden bit); specials
      vp(1) <= vp(0); tg(1) <= tg(0);
      ea := to_integer(a0(30 downto 23));
      eb := to_integer(b0(30 downto 23));
      an := ea = 255 and a0(22 downto 0) /= 0;
      bn := eb = 255 and b0(22 downto 0) /= 0;
      ai := ea = 255 and a0(22 downto 0) = 0;
      bi := eb = 255 and b0(22 downto 0) = 0;
      az := a0(30 downto 0) = 0;
      bz := b0(30 downto 0) = 0;
      sg(1) <= a0(31) xor b0(31);
      if an or bn or (ai and bz) or (az and bi) then
        sp(1) <= "01";
      elsif ai or bi then
        sp(1) <= "10";
      elsif az or bz then
        sp(1) <= "11";
      else
        sp(1) <= "00";
      end if;
      if ea = 0 then ma1 <= '0' & a0(22 downto 0); ea := 1; else ma1 <= '1' & a0(22 downto 0); end if;
      if eb = 0 then mb1 <= '0' & b0(22 downto 0); eb := 1; else mb1 <= '1' & b0(22 downto 0); end if;
      es1 <= ea + eb - 126;

      -- 2, 3: the product (DSP, two register stages)
      for i in 2 to 7 loop
        vp(i) <= vp(i - 1); tg(i) <= tg(i - 1); sp(i) <= sp(i - 1); sg(i) <= sg(i - 1);
      end loop;
      m2 <= ma1 * mb1;
      e0(2) <= es1;
      m3 <= m2;
      e0(3) <= e0(2);

      -- 4: leading zeros
      m4 <= m3;
      lz4 <= lzc(m3);
      e0(4) <= e0(3);

      -- 5: the shift: normalise, or as far as exponent 1 (subnormal), or
      -- right into the subnormal range
      m5 <= m4;
      el := e0(4) - lz4;
      if el >= 1 then
        left5 <= true; sh5 <= lz4; e5 <= el;
      elsif e0(4) >= 1 then
        left5 <= true; sh5 <= e0(4) - 1; e5 <= 1;
      else
        left5 <= false; e5 <= 1;
        if 1 - e0(4) > 50 then sh5 <= 50; else sh5 <= 1 - e0(4); end if;
      end if;

      -- 6: shifted; bits shifted out to the right are sticky
      e6 <= e5;
      if left5 then
        n6 <= shift_left(m5, sh5);
        rs6 <= '0';
      else
        rw := shift_right(m5, sh5);
        n6 <= rw;
        if shift_left(rw, sh5) /= m5 then rs6 <= '1'; else rs6 <= '0'; end if;
      end if;

      -- 7: rounded, packed
      if n6(22 downto 0) /= 0 or rs6 = '1' then st := '1'; else st := '0'; end if;
      case sp(6) is
        when "01" => r7 <= x"7FC00000";
        when "10" => r7 <= sg(6) & "111" & x"F800000";
        when "11" => r7 <= sg(6) & "000" & x"0000000";
        when others => r7 <= fp_pack(sg(6), e6, n6(47 downto 24), n6(23), st);
      end case;
    end if;
  end process;
end architecture;

-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ssnail_fpipe_pkg.all;

entity ssnail_fadd_p is
  generic (TAGW : integer := 8);
  port (
    clock : in std_logic;
    v     : in std_logic;
    a, b  : in unsigned(31 downto 0);
    tag   : in unsigned(TAGW - 1 downto 0);
    rv    : out std_logic;
    r     : out unsigned(31 downto 0);
    rtag  : out unsigned(TAGW - 1 downto 0)
  );
end entity;

architecture rtl of ssnail_fadd_p is
  -- special results: 0 none, 1 NaN, 2 the big operand (an infinity), 3 a
  -- zero of sign sg (both operands zero)
  type spec_t is array (1 to 7) of unsigned(1 downto 0);
  type tag_t is array (0 to 7) of unsigned(TAGW - 1 downto 0);
  signal vp : std_logic_vector(0 to 7) := (others => '0');
  signal tg : tag_t := (others => (others => '0'));
  signal sp : spec_t := (others => "00");
  signal a0, b0 : unsigned(31 downto 0) := (others => '0');
  signal x1, y1 : unsigned(31 downto 0) := (others => '0');   -- |x1| >= |y1|
  signal zs1 : std_logic := '0';
  signal sg : std_logic_vector(2 to 7) := (others => '0');    -- result sign
  signal sub2, sub3 : std_logic := '0';
  signal e2, e3, e4, e5, e6 : integer range 0 to 511 := 1;
  signal d2 : integer range 0 to 255 := 0;
  signal mx2, my2 : unsigned(23 downto 0) := (others => '0');
  signal x3, y3 : unsigned(26 downto 0) := (others => '0');   -- with 3 low bits
  signal s4 : unsigned(27 downto 0) := (others => '0');
  signal ovf5, left_ok5 : boolean := false;
  signal sh5 : integer range 0 to 27 := 0;
  signal s5 : unsigned(27 downto 0) := (others => '0');
  signal z5, z6 : boolean := false;
  signal n6 : unsigned(26 downto 0) := (others => '0');
  signal r7 : unsigned(31 downto 0) := (others => '0');
  signal xr : unsigned(31 downto 0) := (others => '0');
  type w_t is array (2 to 6) of unsigned(31 downto 0);
  signal xw : w_t := (others => (others => '0'));            -- the big operand
begin
  rv <= vp(7);
  r <= r7;
  rtag <= tg(7);

  process (clock) is
    variable an, bn, ai, bi : boolean;
    variable ex, ey : integer range 0 to 255;
    variable yy : unsigned(26 downto 0);
    variable lz : integer range 0 to 27;
    variable st : std_logic;
  begin
    if rising_edge(clock) then
      -- 0: inputs
      vp(0) <= v; tg(0) <= tag; a0 <= a; b0 <= b;

      -- 1: specials; order by magnitude (the integer order of the bits)
      vp(1) <= vp(0); tg(1) <= tg(0);
      an := a0(30 downto 23) = x"FF" and a0(22 downto 0) /= 0;
      bn := b0(30 downto 23) = x"FF" and b0(22 downto 0) /= 0;
      ai := a0(30 downto 23) = x"FF" and a0(22 downto 0) = 0;
      bi := b0(30 downto 23) = x"FF" and b0(22 downto 0) = 0;
      if an or bn or (ai and bi and a0(31) /= b0(31)) then
        sp(1) <= "01";
      elsif ai or bi then
        sp(1) <= "10";
      elsif a0(30 downto 0) = 0 and b0(30 downto 0) = 0 then
        sp(1) <= "11";
      else
        sp(1) <= "00";
      end if;
      zs1 <= a0(31) and b0(31);
      if b0(30 downto 0) > a0(30 downto 0) then
        x1 <= b0; y1 <= a0;
      else
        x1 <= a0; y1 <= b0;
      end if;

      -- 2: unpack both (a subnormal: exponent 1, no hidden bit)
      for i in 2 to 7 loop
        vp(i) <= vp(i - 1); tg(i) <= tg(i - 1); sp(i) <= sp(i - 1);
      end loop;
      ex := to_integer(x1(30 downto 23));
      ey := to_integer(y1(30 downto 23));
      if ex = 0 then mx2 <= '0' & x1(22 downto 0); ex := 1; else mx2 <= '1' & x1(22 downto 0); end if;
      if ey = 0 then my2 <= '0' & y1(22 downto 0); ey := 1; else my2 <= '1' & y1(22 downto 0); end if;
      e2 <= ex;
      d2 <= ex - ey;
      sub2 <= x1(31) xor y1(31);
      if sp(1) = "11" then sg(2) <= zs1; else sg(2) <= x1(31); end if;
      xw(2) <= x1;

      -- 3: align the small one (3 more low bits: guard, round, sticky)
      for i in 3 to 7 loop sg(i) <= sg(i - 1); end loop;
      for i in 3 to 6 loop xw(i) <= xw(i - 1); end loop;
      e3 <= e2; sub3 <= sub2;
      x3 <= mx2 & "000";
      if d2 >= 27 then
        yy := (others => '0');
        if my2 /= 0 then yy(0) := '1'; end if;
      else
        yy := shift_right(my2 & "000", d2);
        if shift_left(yy, d2) /= (my2 & "000") then yy(0) := '1'; end if;
      end if;
      y3 <= yy;

      -- 4: add or subtract (the big one is never smaller)
      e4 <= e3;
      if sub3 = '1' then
        s4 <= ('0' & x3) - ('0' & y3);
      else
        s4 <= ('0' & x3) + ('0' & y3);
      end if;

      -- 5: normalising shift: right one on a carry; else left by the
      -- leading zeros, but not below exponent 1
      s5 <= s4;
      z5 <= s4 = 0;
      lz := lzc(s4(26 downto 0));
      if s4(27) = '1' then
        ovf5 <= true; sh5 <= 0; e5 <= e4 + 1;
      elsif e4 - lz >= 1 then
        ovf5 <= false; sh5 <= lz; e5 <= e4 - lz;
      else
        ovf5 <= false; sh5 <= e4 - 1; e5 <= 1;
      end if;

      -- 6: shifted
      e6 <= e5; z6 <= z5;
      if ovf5 then
        n6 <= s5(27 downto 2) & (s5(1) or s5(0));
      else
        n6 <= shift_left(s5(26 downto 0), sh5);
      end if;

      -- 7: rounded, packed
      st := n6(1) or n6(0);
      case sp(6) is
        when "01" => r7 <= x"7FC00000";
        when "10" => r7 <= xw(6);
        when "11" => r7 <= sg(6) & "000" & x"0000000";
        when others =>
          if z6 then
            r7 <= (others => '0');                 -- x + (-x) = +0
          else
            r7 <= fp_pack(sg(6), e6, n6(26 downto 3), n6(2), st);
          end if;
      end case;
    end if;
  end process;
end architecture;
