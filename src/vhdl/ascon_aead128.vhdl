-- Ascon-AEAD128 (NIST SP 800-232), byte-serial, one permutation round per
-- clock.  For SD over Ethernet (MEGA65/mega65-core#965).
--
-- Bytes go straight into the rate (S0/S1) as they arrive, so the user
-- needs no block buffer.  The rate is a byte-rotating shift register: each
-- byte is taken at the low byte and the result goes in at the top, so after
-- 16 bytes the block is aligned again for the permutation, and no byte
-- position multiplexers are needed.  A short last block (ad_end or final
-- after a number of bytes that isn't a multiple of 16) is padded at the low
-- byte and then rotated into alignment, one cycle per missing byte.  The
-- output byte is the low byte XOR the input byte, and the tag bytes are read
-- from S3/S4 through a 16:1 multiplexer (the last round of final adds the
-- key there, as the last round of init does): no output registers.
--
-- Size (Yosys synth_xilinx, xc7): about 1200 LUTs and 339 flops, of which
-- the round function with the state register is about 650; the rest is the
-- byte, load and key multiplexing.  Vivado's figure is still to be had.
--
-- Use, after init:
--   1. the associated data, any number of bytes with mode AD, then ad_end
--      (ad_end with no AD bytes is just the domain separation);
--   2. the message, any number of bytes with mode ENC or DEC; byte_out is
--      the ciphertext (ENC) or plaintext (DEC) byte for byte_in, in the same
--      cycle (combinational);
--   3. final; when busy falls, tag_byte is byte tag_idx of the tag.
-- Every 16th byte starts 8 rounds; init, ad_end (with AD) and final start
-- 12, 8 and 12.  Inputs are taken only while busy = '0'.  A 512-byte
-- sector with a 16-byte header: 13 + 9 + 512 + 32*8 + 12 = ~800 cycles if
-- the bytes come every cycle, so the rounds hide behind any byte rate below
-- about 2 bytes per 3 cycles.
--
-- The tag and output bytes are left unregistered on purpose; register them
-- in the user if timing needs it.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ascon_aead128 is
  port (
    clk       : in  std_logic;
    init      : in  std_logic;
    key       : in  unsigned(127 downto 0);   -- byte i in bits 8i+7..8i
    nonce     : in  unsigned(127 downto 0);
    byte_valid : in std_logic;
    mode      : in  unsigned(1 downto 0);     -- 00 AD, 01 ENC, 10 DEC
    byte_in   : in  unsigned(7 downto 0);
    byte_out  : out unsigned(7 downto 0);
    ad_end    : in  std_logic;
    final     : in  std_logic;
    tag_idx   : in  unsigned(3 downto 0);
    tag_byte  : out unsigned(7 downto 0);
    busy      : out std_logic
    );
end entity;

architecture rtl of ascon_aead128 is

  -- version 1, a = 12, b = 8, 128-bit tag, rate 16 bytes
  constant IV : unsigned(63 downto 0) := x"00001000808c0001";

  subtype word is unsigned(63 downto 0);
  type state_t is array (0 to 4) of word;

  type phase_t is (P_Idle, P_Rounds, P_Align);

  signal s       : state_t := (others => (others => '0'));
  signal phase   : phase_t := P_Idle;
  signal rounds  : unsigned(3 downto 0) := (others => '0');  -- rounds left
  signal rc_idx  : unsigned(3 downto 0) := (others => '0');  -- round number
  signal key_in  : std_logic := '0';     -- after these rounds: S3/S4 ^= key
  signal sep     : std_logic := '0';     -- after these rounds: S4 ^= 1 << 63
  signal pos     : unsigned(3 downto 0) := (others => '0');  -- bytes in block
  signal ad_any  : std_logic := '0';     -- AD bytes since init
  signal then_final : std_logic := '0';  -- what follows the alignment
  signal busy_i  : std_logic := '0';

  function round(x : state_t; r : unsigned(3 downto 0)) return state_t is
    variable a : state_t := x;
    variable t : state_t;
    variable y : state_t;
  begin
    a(2)(7 downto 0) := a(2)(7 downto 0)
                        xor to_unsigned(16#f0# - to_integer(r) * 16#0f#, 8);
    a(0) := a(0) xor a(4);
    a(4) := a(4) xor a(3);
    a(2) := a(2) xor a(1);
    for i in 0 to 4 loop
      t(i) := (not a(i)) and a((i + 1) mod 5);
    end loop;
    for i in 0 to 4 loop
      a(i) := a(i) xor t((i + 1) mod 5);
    end loop;
    a(1) := a(1) xor a(0);
    a(0) := a(0) xor a(4);
    a(3) := a(3) xor a(2);
    a(2) := not a(2);
    y(0) := a(0) xor rotate_right(a(0), 19) xor rotate_right(a(0), 28);
    y(1) := a(1) xor rotate_right(a(1), 61) xor rotate_right(a(1), 39);
    y(2) := a(2) xor rotate_right(a(2), 1) xor rotate_right(a(2), 6);
    y(3) := a(3) xor rotate_right(a(3), 10) xor rotate_right(a(3), 17);
    y(4) := a(4) xor rotate_right(a(4), 7) xor rotate_right(a(4), 41);
    return y;
  end function;

  signal rate     : unsigned(127 downto 0);
  signal tag_word : unsigned(127 downto 0);

begin

  busy <= busy_i;
  rate <= s(1) & s(0);
  byte_out <= rate(7 downto 0) xor byte_in;
  tag_word <= s(4) & s(3);
  -- The tag is S3/S4 xor the key: the last round of final adds the key
  -- there, as the last round of init does.
  tag_byte <= tag_word(to_integer(tag_idx) * 8 + 7 downto to_integer(tag_idx) * 8);

  process(clk)
    variable x : state_t;
    variable r : unsigned(127 downto 0);
    variable b : unsigned(7 downto 0);

    -- start the rounds that end a short block (after alignment)
    procedure finish_block(fin : std_logic) is
    begin
      if fin = '1' then
        s(2) <= s(2) xor key(63 downto 0);
        s(3) <= s(3) xor key(127 downto 64);
        rounds <= to_unsigned(12, 4);
        rc_idx <= to_unsigned(0, 4);
        key_in <= '1';
      else
        rounds <= to_unsigned(8, 4);
        rc_idx <= to_unsigned(4, 4);
        sep <= '1';
      end if;
      phase <= P_Rounds;
    end procedure;
  begin
    if rising_edge(clk) then
      r := rate;
      case phase is
        when P_Rounds =>
          x := round(s, rc_idx);
          rc_idx <= rc_idx + 1;
          rounds <= rounds - 1;
          if rounds = 1 then
            phase <= P_Idle;
            busy_i <= '0';
            if key_in = '1' then
              x(3) := x(3) xor key(63 downto 0);
              x(4) := x(4) xor key(127 downto 64);
            end if;
            if sep = '1' then
              x(4)(63) := not x(4)(63);
            end if;
            key_in <= '0';
            sep <= '0';
          end if;
          s <= x;
        when P_Align =>
          -- rotate a short block into place, one byte a cycle
          r := r(7 downto 0) & r(127 downto 8);
          s(0) <= r(63 downto 0);
          s(1) <= r(127 downto 64);
          pos <= pos + 1;
          if pos = 15 then
            finish_block(then_final);
          end if;
        when P_Idle =>
          if init = '1' then
            s <= (IV, key(63 downto 0), key(127 downto 64),
                  nonce(63 downto 0), nonce(127 downto 64));
            rounds <= to_unsigned(12, 4);
            rc_idx <= to_unsigned(0, 4);
            key_in <= '1';
            pos <= (others => '0');
            ad_any <= '0';
            phase <= P_Rounds;
            busy_i <= '1';
          elsif byte_valid = '1' then
            if mode = "10" then
              b := byte_in;                              -- DEC: S takes C
            else
              b := r(7 downto 0) xor byte_in;            -- AD, ENC: S ^= byte
            end if;
            r := b & r(127 downto 8);
            s(0) <= r(63 downto 0);
            s(1) <= r(127 downto 64);
            if mode = "00" then
              ad_any <= '1';
            end if;
            pos <= pos + 1;
            if pos = 15 then
              rounds <= to_unsigned(8, 4);
              rc_idx <= to_unsigned(4, 4);
              phase <= P_Rounds;
              busy_i <= '1';
            end if;
          elsif (ad_end = '1' and ad_any = '1') or final = '1' then
            -- pad at the low byte (byte pos of the block), then align
            r(0) := not r(0);
            s(0)(0) <= r(0);
            then_final <= final;
            busy_i <= '1';
            if pos = 0 then
              finish_block(final);
            else
              phase <= P_Align;
            end if;
          elsif ad_end = '1' then
            s(4)(63) <= not s(4)(63);                    -- no AD: separation only
          end if;
      end case;
    end if;
  end process;

end architecture;
