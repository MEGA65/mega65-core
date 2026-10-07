-- SSNAIL floating-point unit.
--
-- A small multi-cycle IEEE 754 unit, bit-exact with numpy's float32/float16
-- (round to nearest, ties to even; subnormals in and out).  One operation at
-- a time: assert start for one cycle with op/a/b; done pulses with the
-- result about seven cycles later (division and square root: about 55).  Throughput is not the point: the vector
-- operations it serves are a small share of the run time next to GEMV.
--
-- Every operation reduces to (sign, exponent, 48-bit significand) and goes
-- through one shared back end: leading-zero count, normalising shift,
-- subnormal shift, rounding.  Each step is its own cycle, to keep the logic
-- between registers shallow at 162 MHz.
--
-- Significand convention in the back end: value = m / 2^46 * 2^(e - 127),
-- i.e. a normalised F32 has its hidden bit at m(46).
--
-- NaN results are canonical (F32 $7FC00000, F16 $7E00).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ssnail_fpu_pkg is
  constant FOP_ADD : unsigned(3 downto 0) := "0000";  -- a + b
  constant FOP_MUL : unsigned(3 downto 0) := "0001";  -- a * b
  constant FOP_F16TOF32 : unsigned(3 downto 0) := "0010";  -- a(15:0) F16 -> F32 (exact)
  constant FOP_F32TOF16 : unsigned(3 downto 0) := "0011";  -- a -> F16 in result(15:0)
  constant FOP_BF16TOF32 : unsigned(3 downto 0) := "0100";  -- a(15:0) BF16 -> F32 (exact)
  constant FOP_I2F : unsigned(3 downto 0) := "0101";  -- a signed 32-bit -> F32
  constant FOP_DIV : unsigned(3 downto 0) := "0110";  -- a / b (correctly rounded)
  constant FOP_ROUNDF : unsigned(3 downto 0) := "0111";  -- C roundf(a) -> signed 32-bit
                                                          -- (saturating; NaN -> 0)
  constant FOP_SQRT     : unsigned(3 downto 0) := "1000";  -- sqrt(a) (correctly rounded)
  constant FOP_TRUNC    : unsigned(3 downto 0) := "1001";  -- a -> signed 32-bit, toward
                                                           -- zero (saturating; NaN -> 0)
end package;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ssnail_fpu_pkg.all;

entity ssnail_fpu is
  port (
    clock  : in  std_logic;
    start  : in  std_logic;
    op     : in  unsigned(3 downto 0);
    a, b   : in  unsigned(31 downto 0);
    done   : out std_logic := '0';
    result : out unsigned(31 downto 0) := (others => '0')
    );
end ssnail_fpu;

architecture multicycle of ssnail_fpu is

  type state_t is (S_IDLE, S_ALIGN, S_ADD, S_LZC, S_SHIFT, S_DENORM, S_ROUND,
                   S_DNORM, S_DIV, S_SQNORM, S_SQRT);
  signal state : state_t := S_IDLE;

  signal to_f16  : std_logic := '0';        -- round to F16 instead of F32
  signal special : std_logic := '0';        -- result already decided
  signal sp_val  : unsigned(31 downto 0) := (others => '0');

  -- Operands for addition, ordered |big| >= |small|
  signal big_m, small_m : unsigned(47 downto 0) := (others => '0');
  signal big_e  : integer range -1024 to 1023 := 0;
  signal sh_d   : integer range 0 to 2047 := 0;
  signal subtract : std_logic := '0';
  signal both_zero_sign : std_logic := '0';
  signal add_zero_sign  : std_logic := '0';

  -- Back end
  signal rs : std_logic := '0';
  signal re : integer range -2048 to 2047 := 0;
  signal rm : unsigned(47 downto 0) := (others => '0');
  signal lz_pos : integer range -1 to 47 := -1;
  signal zero_sign : std_logic := '0';
  -- Division
  signal dv_ma, dv_mb : unsigned(23 downto 0) := (others => '0');
  signal dv_ea, dv_eb : integer range -1024 to 1023 := 0;
  signal dv_r  : unsigned(25 downto 0) := (others => '0');
  signal dv_q  : unsigned(46 downto 0) := (others => '0');
  signal dv_i  : integer range -1 to 46 := 0;
  -- Square root: integer square root of a 94-bit radicand, 2 bits per step
  signal sq_rad  : unsigned(93 downto 0) := (others => '0');
  signal sq_rem  : unsigned(49 downto 0) := (others => '0');
  signal sq_res  : unsigned(46 downto 0) := (others => '0');
  signal sq_e    : integer range -1024 to 1023 := 0;

  -- Unpack an F32: sign, exponent field (1 for subnormals), 24-bit significand
  procedure unpack32(x : in unsigned(31 downto 0); s : out std_logic;
                     e : out integer; m : out unsigned(23 downto 0)) is
  begin
    s := x(31);
    if x(30 downto 23) = 0 then
      e := 1;
      m := '0' & x(22 downto 0);
    else
      e := to_integer(x(30 downto 23));
      m := '1' & x(22 downto 0);
    end if;
  end procedure;

  function is_nan32(x : unsigned(31 downto 0)) return boolean is
  begin
    return x(30 downto 23) = x"FF" and x(22 downto 0) /= 0;
  end function;

  function is_inf32(x : unsigned(31 downto 0)) return boolean is
  begin
    return x(30 downto 23) = x"FF" and x(22 downto 0) = 0;
  end function;

  function is_zero32(x : unsigned(31 downto 0)) return boolean is
  begin
    return x(30 downto 0) = 0;
  end function;

  constant NAN32 : unsigned(31 downto 0) := x"7FC00000";
  constant NAN16 : unsigned(31 downto 0) := x"00007E00";

begin

  process (clock) is
    variable sa, sb : std_logic;
    variable ea, eb : integer range -1024 to 1023;
    variable ma, mb : unsigned(23 downto 0);
    variable wa, wb : unsigned(47 downto 0);
    variable swap   : boolean;
    variable sm     : unsigned(47 downto 0);
    variable sticky : std_logic;
    variable sum    : unsigned(47 downto 0);
    variable pos    : integer range -1 to 47;
    variable k      : integer range -64 to 63;
    variable emin, ebias, sh : integer range -4096 to 4095;
    variable keep   : unsigned(24 downto 0);
    variable rbit, stk, up : std_logic;
    variable efield : integer range -4096 to 4095;
    variable mag    : unsigned(31 downto 0);
    variable h      : unsigned(15 downto 0);
    variable sh2    : integer range -512 to 511;
    variable v2     : unsigned(31 downto 0);
    variable ri     : unsigned(31 downto 0);
    variable la, lb : integer range 0 to 24;
  begin
    if rising_edge(clock) then
      done <= '0';
      case state is

        when S_IDLE =>
          if start = '1' then
            special <= '0';
            to_f16 <= '0';
            zero_sign <= '0';
            if op = FOP_ADD then
              -- -------------------------------------------------- add
              if is_nan32(a) or is_nan32(b) or
                (is_inf32(a) and is_inf32(b) and a(31) /= b(31)) then
                special <= '1'; sp_val <= NAN32;
                state <= S_ROUND;
              elsif is_inf32(a) then
                special <= '1'; sp_val <= a;
                state <= S_ROUND;
              elsif is_inf32(b) then
                special <= '1'; sp_val <= b;
                state <= S_ROUND;
              else
                unpack32(a, sa, ea, ma);
                unpack32(b, sb, eb, mb);
                wa := "0" & ma & "00000000000000000000000";   -- hidden bit at 46
                wb := "0" & mb & "00000000000000000000000";
                swap := (eb > ea) or (eb = ea and mb > ma);
                if swap then
                  big_m <= wb; small_m <= wa; big_e <= eb;
                  sh_d <= eb - ea;
                  rs <= sb;
                else
                  big_m <= wa; small_m <= wb; big_e <= ea;
                  sh_d <= ea - eb;
                  rs <= sa;
                end if;
                if sa /= sb then subtract <= '1'; else subtract <= '0'; end if;
                -- Zero results: (-0) + (-0) = -0; exact cancellation = +0
                if is_zero32(a) and is_zero32(b) then
                  zero_sign <= sa and sb;
                else
                  zero_sign <= '0';
                end if;
                state <= S_ALIGN;
              end if;
            elsif op = FOP_MUL then
              -- -------------------------------------------------- multiply
              if is_nan32(a) or is_nan32(b) or
                (is_inf32(a) and is_zero32(b)) or (is_zero32(a) and is_inf32(b)) then
                special <= '1'; sp_val <= NAN32;
                state <= S_ROUND;
              elsif is_inf32(a) or is_inf32(b) then
                special <= '1'; sp_val <= (a(31) xor b(31)) & "1111111100000000000000000000000";
                state <= S_ROUND;
              else
                unpack32(a, sa, ea, ma);
                unpack32(b, sb, eb, mb);
                rs <= sa xor sb;
                zero_sign <= sa xor sb;
                -- 24 x 24 -> 48 bits; with the hidden bits at 23, the product's
                -- point is at 46, matching the back end's convention
                rm <= ma * mb;
                re <= ea + eb - 127;
                state <= S_LZC;
              end if;
            elsif op = FOP_F16TOF32 then
              h := a(15 downto 0);
              if h(14 downto 10) = "11111" then
                special <= '1';
                if h(9 downto 0) /= 0 then
                  sp_val <= NAN32;
                else
                  sp_val <= h(15) & "1111111100000000000000000000000";
                end if;
                state <= S_ROUND;
              else
                rs <= h(15);
                zero_sign <= h(15);
                if h(14 downto 10) = 0 then
                  rm <= "0" & '0' & h(9 downto 0) & "000000000000000000000000000000000000";
                  re <= 1 - 15 + 127;
                else
                  rm <= "0" & '1' & h(9 downto 0) & "000000000000000000000000000000000000";
                  re <= to_integer(h(14 downto 10)) - 15 + 127;
                end if;
                state <= S_LZC;
              end if;
            elsif op = FOP_BF16TOF32 then
              special <= '1';
              if a(14 downto 7) = x"FF" and a(6 downto 0) /= 0 then
                sp_val <= NAN32;
              else
                sp_val <= a(15 downto 0) & x"0000";
              end if;
              state <= S_ROUND;
            elsif op = FOP_F32TOF16 then
              to_f16 <= '1';
              if is_nan32(a) then
                special <= '1'; sp_val <= NAN16;
                state <= S_ROUND;
              elsif is_inf32(a) then
                special <= '1'; sp_val <= x"0000" & a(31) & "111110000000000";
                state <= S_ROUND;
              else
                unpack32(a, sa, ea, ma);
                rs <= sa;
                zero_sign <= sa;
                rm <= "0" & ma & "00000000000000000000000";
                re <= ea;
                state <= S_LZC;
              end if;
            elsif op = FOP_DIV then
              -- -------------------------------------------------- divide
              if is_nan32(a) or is_nan32(b) or (is_inf32(a) and is_inf32(b))
                or (is_zero32(a) and is_zero32(b)) then
                special <= '1'; sp_val <= NAN32;
                state <= S_ROUND;
              elsif is_inf32(a) or is_zero32(b) then
                special <= '1'; sp_val <= (a(31) xor b(31)) & "1111111100000000000000000000000";
                state <= S_ROUND;
              elsif is_zero32(a) or is_inf32(b) then
                special <= '1'; sp_val <= (a(31) xor b(31)) & "0000000000000000000000000000000";
                state <= S_ROUND;
              else
                unpack32(a, sa, ea, ma);
                unpack32(b, sb, eb, mb);
                rs <= sa xor sb;
                dv_ma <= ma; dv_mb <= mb; dv_ea <= ea; dv_eb <= eb;
                state <= S_DNORM;
              end if;
            elsif op = FOP_SQRT then
              -- -------------------------------------------------- sqrt
              if is_nan32(a) or (a(31) = '1' and not is_zero32(a)) then
                special <= '1'; sp_val <= NAN32;      -- NaN, or negative
                state <= S_ROUND;
              elsif is_zero32(a) or is_inf32(a) then
                special <= '1'; sp_val <= a;          -- +-0, +inf
                state <= S_ROUND;
              else
                unpack32(a, sa, ea, ma);
                rs <= '0';
                dv_ma <= ma; dv_ea <= ea;
                state <= S_SQNORM;
              end if;
            elsif op = FOP_TRUNC then
              -- -------------------------------------------------- truncate
              special <= '1';
              if is_nan32(a) or a(30 downto 23) < 127 then
                sp_val <= (others => '0');          -- NaN, or |a| < 1
              else
                -- |a| = m * 2^(e - 150)
                sh2 := to_integer(a(30 downto 23)) - 150;
                if sh2 >= 8 then                    -- |a| >= 2^31
                  if a(31) = '1' then sp_val <= x"80000000"; else sp_val <= x"7FFFFFFF"; end if;
                else
                  if sh2 >= 0 then
                    ri := shift_left(x"00" & '1' & a(22 downto 0), sh2);
                  else
                    ri := shift_right(x"00" & '1' & a(22 downto 0), -sh2);
                  end if;
                  if a(31) = '1' then
                    sp_val <= (not ri) + 1;
                  else
                    sp_val <= ri;
                  end if;
                end if;
              end if;
              state <= S_ROUND;
            elsif op = FOP_ROUNDF then
              -- -------------------------------------------------- roundf
              special <= '1';
              if is_nan32(a) or a(30 downto 23) < 126 then
                sp_val <= (others => '0');          -- NaN, or |a| < 0.5
              else
                -- 2|a| = m * 2^(e - 149); v2 = floor(2|a|); round = (v2 + 1) / 2
                sh2 := to_integer(a(30 downto 23)) - 149;
                if sh2 >= 9 then                  -- |a| >= 2^31
                  if a(31) = '1' then sp_val <= x"80000000"; else sp_val <= x"7FFFFFFF"; end if;
                else
                  if sh2 >= 0 then
                    v2 := shift_left(x"00" & '1' & a(22 downto 0), sh2);
                  else
                    v2 := shift_right(x"00" & '1' & a(22 downto 0), -sh2);
                  end if;
                  ri := shift_right(v2 + 1, 1);
                  if a(31) = '1' then
                    sp_val <= (not ri) + 1;
                  else
                    sp_val <= ri;
                  end if;
                end if;
              end if;
              state <= S_ROUND;
            else                                  -- FOP_I2F
              rs <= a(31);
              zero_sign <= '0';
              if a(31) = '1' then
                mag := (not a) + 1;
              else
                mag := a;
              end if;
              rm <= x"0000" & mag;
              re <= 127 + 46;
              state <= S_LZC;
            end if;
          end if;

        when S_DNORM =>
          -- Normalise subnormal operands so both significands have their
          -- leading 1 at bit 23
          la := 0; lb := 0;
          for i in 0 to 23 loop
            if dv_ma(i) = '1' then la := 23 - i; end if;
            if dv_mb(i) = '1' then lb := 23 - i; end if;
          end loop;
          dv_ma <= shift_left(dv_ma, la);
          dv_mb <= shift_left(dv_mb, lb);
          dv_ea <= dv_ea - la;
          dv_eb <= dv_eb - lb;
          dv_r <= "00" & shift_left(dv_ma, la);
          dv_i <= 46;
          state <= S_DIV;

        when S_SQNORM =>
          -- value = m * 2^(e - 150), m normalised to bit 23.  Make the
          -- exponent even, then sqrt(m' * 2^69) is the result significand
          -- with its point at bit 46: q = isqrt(m' << 69), in [2^46, 2^47).
          la := 0;
          for i in 0 to 23 loop
            if dv_ma(i) = '1' then la := 23 - i; end if;
          end loop;
          -- unbiased exponent of the normalised value
          if ((dv_ea - la - 127) mod 2) = 0 then
            sq_rad <= resize(shift_left(dv_ma, la), 25) & "000000000000000000000000000000000000000000000000000000000000000000000";
            sq_e <= (dv_ea - la - 127) / 2;
          else
            sq_rad <= resize(shift_left(dv_ma, la), 25) & "000000000000000000000000000000000000000000000000000000000000000000000";
            sq_rad <= (shift_left(resize(shift_left(dv_ma, la), 25), 1))
                      & "000000000000000000000000000000000000000000000000000000000000000000000";
            sq_e <= (dv_ea - la - 127 - 1) / 2;
          end if;
          sq_rem <= (others => '0');
          sq_res <= (others => '0');
          dv_i <= 46;
          state <= S_SQRT;

        when S_SQRT =>
          if dv_i >= 0 then
            -- bring down the next two radicand bits; try (res << 2) | 1
            sq_rem <= (sq_rem(47 downto 0) & sq_rad(93 downto 92));
            if (sq_rem(47 downto 0) & sq_rad(93 downto 92)) >= (("0" & sq_res & "01")) then
              sq_rem <= (sq_rem(47 downto 0) & sq_rad(93 downto 92)) - ("0" & sq_res & "01");
              sq_res <= sq_res(45 downto 0) & '1';
            else
              sq_res <= sq_res(45 downto 0) & '0';
            end if;
            sq_rad <= sq_rad(91 downto 0) & "00";
            dv_i <= dv_i - 1;
          else
            if sq_rem /= 0 then
              rm <= '0' & sq_res(46 downto 1) & '1';      -- sticky
            else
              rm <= '0' & sq_res;
            end if;
            re <= sq_e + 127;
            state <= S_LZC;
          end if;

        when S_DIV =>
          -- Restoring division, one quotient bit per cycle:
          -- q = floor(ma * 2^46 / mb), in [2^45, 2^47)
          if dv_i >= 0 then
            if dv_r >= ("00" & dv_mb) then
              dv_q(dv_i) <= '1';
              dv_r <= (dv_r - ("00" & dv_mb)) sll 1;
            else
              dv_q(dv_i) <= '0';
              dv_r <= dv_r sll 1;
            end if;
            dv_i <= dv_i - 1;
          else
            -- remainder /= 0 -> sticky into bit 0
            if dv_r /= 0 then
              rm <= '0' & dv_q(46 downto 1) & '1';
            else
              rm <= '0' & dv_q;
            end if;
            re <= dv_ea - dv_eb + 127;
            state <= S_LZC;
          end if;

        when S_ALIGN =>
          -- Shift the smaller significand right, folding lost bits into
          -- bit 0 (sticky); 23 spare bits below the rounding point make
          -- that exact for round-to-nearest-even.
          if sh_d >= 48 then
            if small_m /= 0 then
              small_m <= (0 => '1', others => '0');
            end if;
          else
            sm := shift_right(small_m, sh_d);
            sticky := '0';
            for i in 0 to 47 loop
              if i < sh_d and small_m(i) = '1' then
                sticky := '1';
              end if;
            end loop;
            small_m <= sm(47 downto 1) & (sm(0) or sticky);
          end if;
          state <= S_ADD;

        when S_ADD =>
          if subtract = '1' then
            sum := big_m - small_m;
          else
            sum := big_m + small_m;
          end if;
          rm <= sum;
          re <= big_e;
          if sum = 0 then
            -- exact zero: keep the both-zero sign, else +0
            rs <= zero_sign;
          end if;
          state <= S_LZC;

        when S_LZC =>
          pos := -1;
          for i in 0 to 47 loop
            if rm(i) = '1' then
              pos := i;
            end if;
          end loop;
          lz_pos <= pos;
          state <= S_SHIFT;

        when S_SHIFT =>
          -- Bring the leading 1 to bit 46 (or down from 47 by one)
          if lz_pos = 47 then
            rm <= '0' & rm(47 downto 2) & (rm(1) or rm(0));
            re <= re + 1;
          elsif lz_pos >= 0 then
            k := 46 - lz_pos;
            rm <= shift_left(rm, k);
            re <= re - k;
          end if;
          state <= S_DENORM;

        when S_DENORM =>
          -- Below the smallest normal exponent: shift right into a subnormal
          if to_f16 = '1' then
            emin := 1 + 127 - 15;
          else
            emin := 1;
          end if;
          if re < emin and rm /= 0 then
            sh := emin - re;
            if sh >= 48 then
              rm <= (0 => '1', others => '0');
            else
              sm := shift_right(rm, sh);
              sticky := '0';
              for i in 0 to 47 loop
                if i < sh and rm(i) = '1' then
                  sticky := '1';
                end if;
              end loop;
              rm <= sm(47 downto 1) & (sm(0) or sticky);
            end if;
            re <= emin;
          end if;
          state <= S_ROUND;

        when S_ROUND =>
          if special = '1' then
            result <= sp_val;
          elsif rm = 0 then
            if to_f16 = '1' then
              result <= x"0000" & rs & "000000000000000";
            else
              result <= rs & "0000000000000000000000000000000";
            end if;
          elsif to_f16 = '0' then
            keep := '0' & rm(46 downto 23);
            rbit := rm(22);
            stk := '0';
            if rm(21 downto 0) /= 0 then stk := '1'; end if;
            up := rbit and (stk or keep(0));
            if up = '1' then keep := keep + 1; end if;
            if rm(46) = '1' then efield := re; else efield := 0; end if;
            if keep(24) = '1' then
              keep := '0' & keep(24 downto 1);
              efield := efield + 1;
            elsif efield = 0 and keep(23) = '1' then
              efield := 1;
            end if;
            if efield >= 255 then
              result <= rs & "1111111100000000000000000000000";
            else
              result <= rs & to_unsigned(efield, 8) & keep(22 downto 0);
            end if;
          else
            keep := "00000000000000" & rm(46 downto 36);
            rbit := rm(35);
            stk := '0';
            if rm(34 downto 0) /= 0 then stk := '1'; end if;
            up := rbit and (stk or keep(0));
            if up = '1' then keep := keep + 1; end if;
            if rm(46) = '1' then efield := re - 127 + 15; else efield := 0; end if;
            if keep(11) = '1' then
              keep := '0' & keep(24 downto 1);
              efield := efield + 1;
            elsif efield = 0 and keep(10) = '1' then
              efield := 1;
            end if;
            if efield >= 31 then
              result <= x"0000" & rs & "111110000000000";
            else
              result <= x"0000" & rs & to_unsigned(efield, 5) & keep(9 downto 0);
            end if;
          end if;
          done <= '1';
          state <= S_IDLE;
      end case;
    end if;
  end process;

end multicycle;
