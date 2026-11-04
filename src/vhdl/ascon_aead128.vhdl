-- Ascon-AEAD128 (NIST SP 800-232), one permutation round per clock.
--
-- For SD over Ethernet (MEGA65/mega65-core#965).  Block interface: the
-- user packs 16 bytes at a time, little-endian (byte i of the block in bits
-- 8i+7..8i, as Ascon loads its 64-bit words), and issues operations:
--
--   OP_INIT  key, nonce -> state; 12 rounds; key into S3/S4         13 cycles
--   OP_AD    absorb an associated-data block; then 8 rounds            9 cycles
--            len = 16: a full block; len < 16: the last, padded block
--            (len = 0 is the padding-only block after a whole number
--            of blocks).  Skip OP_AD altogether when there is no AD.
--   OP_SEP   domain separation after the AD (S4 ^= 1 << 63)            1 cycle
--   OP_ENC   encrypt a plaintext block: blk_out = ciphertext (only the
--            first len bytes mean anything).  len = 16 permutes 8 rounds
--            after; len < 16 is the last block (always give one, len = 0
--            if the plaintext is a whole number of blocks)
--   OP_DEC   decrypt a ciphertext block: blk_out = plaintext, as OP_ENC
--   OP_FINAL 12 rounds with the key; tag_out = the tag                 13 cycles
--
-- op_valid is taken only while busy = '0'.  blk_out is registered and
-- valid from the cycle after op_valid until the next op.  tag_out is valid
-- once busy falls after OP_FINAL.  The caller compares received tags (in
-- constant time is not needed in hardware: there is no timing side channel
-- worth the name in a fixed-length compare).
--
-- Cost: 320 state flops; the round is a 5-input S-box per bit column plus a
-- three-input XOR per bit, about 640 LUTs, plus the input multiplexing.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ascon_aead128 is
  port (
    clk      : in  std_logic;
    op_valid : in  std_logic;
    op       : in  unsigned(2 downto 0);
    key      : in  unsigned(127 downto 0);
    nonce    : in  unsigned(127 downto 0);
    blk_in   : in  unsigned(127 downto 0);
    blk_len  : in  unsigned(4 downto 0);    -- 0..16
    busy     : out std_logic;
    blk_out  : out unsigned(127 downto 0);
    tag_out  : out unsigned(127 downto 0)
    );
end entity;

architecture rtl of ascon_aead128 is

  constant OP_INIT  : unsigned(2 downto 0) := "000";
  constant OP_AD    : unsigned(2 downto 0) := "001";
  constant OP_SEP   : unsigned(2 downto 0) := "010";
  constant OP_ENC   : unsigned(2 downto 0) := "011";
  constant OP_DEC   : unsigned(2 downto 0) := "100";
  constant OP_FINAL : unsigned(2 downto 0) := "101";

  -- version 1, a = 12, b = 8, 128-bit tag, rate 16 bytes
  constant IV : unsigned(63 downto 0) := x"00001000808c0001";

  subtype word is unsigned(63 downto 0);
  type state_t is array (0 to 4) of word;

  signal s       : state_t := (others => (others => '0'));
  signal rounds  : unsigned(3 downto 0) := (others => '0');  -- rounds left
  signal rc_idx  : unsigned(3 downto 0) := (others => '0');  -- round number r
  signal final_k : std_logic := '0';     -- after these rounds: S3/S4 ^= key
  signal tag_k   : std_logic := '0';     -- after these rounds: make the tag
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

  -- The 0x01 padding byte at byte len (nothing for a full block)
  function pad(len : unsigned(4 downto 0)) return unsigned is
    variable p : unsigned(127 downto 0) := (others => '0');
  begin
    if len < 16 then
      p(to_integer(len(3 downto 0)) * 8) := '1';
    end if;
    return p;
  end function;

  -- Ones in the bytes below len
  function low_mask(len : unsigned(4 downto 0)) return unsigned is
    variable m : unsigned(127 downto 0) := (others => '0');
  begin
    for i in 0 to 15 loop
      if i < to_integer(len) then
        m(i * 8 + 7 downto i * 8) := (others => '1');
      end if;
    end loop;
    return m;
  end function;

begin

  busy <= busy_i;

  process(clk)
    variable rate : unsigned(127 downto 0);
    variable x    : state_t;
    variable m    : unsigned(127 downto 0);
  begin
    if rising_edge(clk) then
      if busy_i = '1' then
        x := round(s, rc_idx);
        rc_idx <= rc_idx + 1;
        if rounds = 1 then
          busy_i <= '0';
          if final_k = '1' then
            x(3) := x(3) xor key(63 downto 0);
            x(4) := x(4) xor key(127 downto 64);
          end if;
          if tag_k = '1' then
            tag_out <= (x(4) xor key(127 downto 64)) & (x(3) xor key(63 downto 0));
          end if;
          final_k <= '0';
          tag_k <= '0';
        end if;
        rounds <= rounds - 1;
        s <= x;
      elsif op_valid = '1' then
        rate := s(1) & s(0);
        case op is
          when OP_INIT =>
            s <= (IV, key(63 downto 0), key(127 downto 64),
                  nonce(63 downto 0), nonce(127 downto 64));
            rounds <= to_unsigned(12, 4);
            rc_idx <= to_unsigned(0, 4);
            final_k <= '1';
            busy_i <= '1';
          when OP_AD =>
            rate := rate xor (blk_in and low_mask(blk_len)) xor pad(blk_len);
            s(0) <= rate(63 downto 0);
            s(1) <= rate(127 downto 64);
            rounds <= to_unsigned(8, 4);
            rc_idx <= to_unsigned(4, 4);
            busy_i <= '1';
          when OP_SEP =>
            s(4)(63) <= not s(4)(63);
          when OP_ENC =>
            rate := rate xor (blk_in and low_mask(blk_len)) xor pad(blk_len);
            blk_out <= rate;
            s(0) <= rate(63 downto 0);
            s(1) <= rate(127 downto 64);
            if blk_len = 16 then
              rounds <= to_unsigned(8, 4);
              rc_idx <= to_unsigned(4, 4);
              busy_i <= '1';
            end if;
          when OP_DEC =>
            m := low_mask(blk_len);
            blk_out <= rate xor blk_in;
            rate := ((blk_in and m) or (rate and not m)) xor pad(blk_len);
            s(0) <= rate(63 downto 0);
            s(1) <= rate(127 downto 64);
            if blk_len = 16 then
              rounds <= to_unsigned(8, 4);
              rc_idx <= to_unsigned(4, 4);
              busy_i <= '1';
            end if;
          when OP_FINAL =>
            s(2) <= s(2) xor key(63 downto 0);
            s(3) <= s(3) xor key(127 downto 64);
            rounds <= to_unsigned(12, 4);
            rc_idx <= to_unsigned(0, 4);
            tag_k <= '1';
            busy_i <= '1';
          when others =>
            null;
        end case;
      end if;
    end if;
  end process;

end architecture;
