--------------------------------------------------------------------------------
-- sd_eth: an SD card on the other end of the Ethernet (MEGA65/mega65-core#965)
--
-- Copyright (C) 2026 Paul Gardner-Stephen and the MEGA65 project.
-- Released under the GNU Lesser General Public License v3 (as LICENSE.txt).
--
-- Speaks sdcard_native's host interface (command mailbox, status, read
-- stream with a good/bad verdict per block, write fetch), so that
-- sdcard_native_dual can put it in slot 0's place: everything above (the
-- sector cache with its read-ahead, the F011 path, the FAT32 engine) works
-- unchanged.  Sectors come from src/tools/netsd.py on a PC, over UDP/IPv4
-- (port 6565); docs/sdcard-native/sd-over-ethernet.md has the protocol.
-- No CPU work per sector: frames are built, sent, received, checked and
-- decrypted here.
--
--   C_INIT   HELLO, broadcast, until a reply (or G_HELLO_TRIES tries): it
--            gives our IPv4 address, the server's, the card size and the
--            server nonce.  The server's MAC is the reply's source.
--   C_READ   READ requests of up to 8 sectors.  An open-ended read (count =
--            0, grants with C_MORE) asks 8 sectors ahead of the data whatever
--            the grants, so the PC's latency hides behind the stream; frames
--            for blocks not yet granted wait in the receive ring.
--   C_WRITE  one WRITE per block, then its status.
--   C_INFO   512 zero bytes (there is no CSD).
--   C_PROBE, C_ACCEPT, C_CLEAR: accepted, nothing to do.
-- A request is sent again after G_RETRY_US without progress, up to
-- G_TRIES times; then the command fails (ERR_RD_TMO / ERR_WR_TMO).  A read
-- block whose tag is wrong is reported with rd_bad and asked for again.
--
-- ARP requests for our address are answered, so that the PC can send to us.
--
-- Ascon-AEAD128 (ascon_aead128), with a 128-bit key loaded through the
-- control register; per frame, nonce = session | sequence | LBA | server
-- nonce (3 bytes) | op (bit 7: response); AD = the 16-byte netsd header;
-- the payload encrypted (encrypt on) or added to the AD (authenticate only).
-- HELLO and its reply are authenticated, never encrypted (the server finds
-- the key by the MAC in it).
--
-- CONTROL REGISTER ($D6F1, through sdcardio_native):
--   write, bit 7 = 0: shift bits 6..0 into a 168-bit register (24 writes;
--     ignored while on, so that the key in use stays put):
--     bits 167..160 flags (bit 0 authenticate, bit 1 encrypt), 159..32 the
--     key (byte i of the key in bits 159-8i..152-8i: the first key byte
--     first), 31..0 entropy (XORed with a free-running cycle counter to make
--     the session ID).
--   write, bit 7 = 1: bits 6..0 = our host octet.  Non-zero: take the flags
--     and session from the shift register (the key stays in it) and switch
--     on (slot 0 is then this card; C_INIT to connect).  Zero: switch off and
--     clear the register, key and all.
--   read: bit 7 on, bit 6 connected, bit 5 authenticate, bit 4 encrypt,
--     bits 3..0 the status of the last NAK.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sd_eth is
  generic (
    G_WR_LAT      : natural := 2;          -- wr_fetch -> wr_data (cpuclocks)
    G_US          : natural := 40;         -- cpuclocks per microsecond
    G_RETRY_US    : natural := 20000;      -- request sent again after this
    G_TRIES       : natural := 10;
    G_HELLO_US    : natural := 250000;     -- HELLO sent again after this
    G_HELLO_TRIES : natural := 12          -- 3 s
    );
  port (
    clock       : in  std_logic;

    ctl_write   : in  std_logic;
    ctl_wdata   : in  unsigned(7 downto 0);
    ctl_status  : out unsigned(7 downto 0);
    active      : out std_logic;           -- slot 0 is this card

    -- host side, as sdcard_native ---------------------------------------------
    cmd_valid   : in  std_logic;
    cmd_ready   : out std_logic;
    cmd_code    : in  unsigned(3 downto 0);
    cmd_addr    : in  unsigned(31 downto 0);
    cmd_count   : in  unsigned(15 downto 0);
    cmd_arg     : in  unsigned(15 downto 0);
    card_ready  : out std_logic;
    busy        : out std_logic;
    waiting     : out std_logic;
    error       : out std_logic;
    err_code    : out unsigned(7 downto 0);
    blocks_done : out unsigned(15 downto 0);
    capacity_valid : out std_logic;
    last_sector : out unsigned(31 downto 0);
    rd_valid    : out std_logic;
    rd_data     : out unsigned(7 downto 0);
    rd_offset   : out unsigned(8 downto 0);
    rd_block    : out unsigned(15 downto 0);
    rd_good     : out std_logic;
    rd_bad      : out std_logic;
    wr_fetch    : out std_logic;
    wr_offset   : out unsigned(8 downto 0);
    wr_block    : out unsigned(15 downto 0);
    wr_data     : in  unsigned(7 downto 0);

    -- Ethernet side (eth_netsd_buf, cpuclock side) -----------------------------
    mac         : in  unsigned(47 downto 0);
    rx_ready    : in  std_logic;            -- a frame is at the head of the ring
    rx_len      : in  unsigned(10 downto 0);  -- its length, FCS included
    rx_raddr    : out unsigned(9 downto 0);
    rx_rdata    : in  unsigned(7 downto 0);   -- rx_raddr's byte, 2 cycles on
    rx_release  : out std_logic;
    tx_we       : out std_logic;
    tx_waddr    : out unsigned(10 downto 0);
    tx_wdata    : out unsigned(7 downto 0);
    tx_go       : out std_logic;
    tx_base     : out std_logic;            -- 0 netsd frame, 1 ARP reply
    tx_len      : out unsigned(10 downto 0);
    tx_busy     : in  std_logic
    );
end entity;

architecture rtl of sd_eth is

  constant C_INIT   : unsigned(3 downto 0) := x"1";
  constant C_READ   : unsigned(3 downto 0) := x"2";
  constant C_WRITE  : unsigned(3 downto 0) := x"3";
  constant C_MORE   : unsigned(3 downto 0) := x"4";
  constant C_STOP   : unsigned(3 downto 0) := x"5";
  constant C_INFO   : unsigned(3 downto 0) := x"B";
  constant C_INIT_BOTH : unsigned(3 downto 0) := x"A";

  constant ERR_NONE     : unsigned(7 downto 0) := x"00";
  constant ERR_NOCARD   : unsigned(7 downto 0) := x"01";
  constant ERR_CMD      : unsigned(7 downto 0) := x"10";
  constant ERR_RD_TMO   : unsigned(7 downto 0) := x"20";
  constant ERR_WR_ERR   : unsigned(7 downto 0) := x"31";
  constant ERR_WR_TMO   : unsigned(7 downto 0) := x"32";
  constant ERR_BUSY     : unsigned(7 downto 0) := x"40";
  constant ERR_NOTREADY : unsigned(7 downto 0) := x"41";
  constant ERR_RANGE    : unsigned(7 downto 0) := x"44";

  constant OP_HELLO : unsigned(7 downto 0) := x"01";
  constant OP_READ  : unsigned(7 downto 0) := x"02";
  constant OP_WRITE : unsigned(7 downto 0) := x"03";
  constant OP_NAK   : unsigned(7 downto 0) := x"7F";

  constant HDR_LEN : natural := 58;        -- Ethernet + IPv4 + UDP + netsd

  -- control ---------------------------------------------------------------------
  signal sr        : unsigned(167 downto 0) := (others => '0');
  signal on_i      : std_logic := '0';
  signal octet     : unsigned(6 downto 0) := (others => '0');
  signal key       : unsigned(127 downto 0);  -- sr's key bits, byte i at 8i
  signal auth      : std_logic := '0';
  signal enc       : std_logic := '0';
  signal session   : unsigned(31 downto 0) := (others => '0');
  signal cycles    : unsigned(31 downto 0) := (others => '0');
  signal last_nak  : unsigned(3 downto 0) := (others => '0');

  -- the connection --------------------------------------------------------------
  signal my_ip     : unsigned(31 downto 0) := (others => '0');   -- a.b.c.d: a high
  signal srv_ip    : unsigned(31 downto 0) := (others => '0');
  signal srv_mac   : unsigned(47 downto 0) := (others => '1');
  signal rs        : unsigned(23 downto 0) := (others => '0');   -- server nonce
  signal capacity  : unsigned(31 downto 0) := (others => '0');
  signal connected : std_logic := '0';
  signal seq       : unsigned(31 downto 0) := (others => '0');

  -- host status -----------------------------------------------------------------
  signal ready_i   : std_logic := '1';
  signal err_i     : std_logic := '0';
  signal errc_i    : unsigned(7 downto 0) := ERR_NONE;

  -- the transfer ----------------------------------------------------------------
  type st_t is (T_IDLE, T_HELLO, T_HELLO_WAIT, T_READ, T_READ_WAIT,
                T_WRITE, T_WRITE_WAIT, T_INFO,
                -- frame building
                B_CSUM, B_FOLD, B_INIT, B_HDR, B_ADEND1, B_PAY, B_PAY_FETCH,
                B_PAY_PUT, B_PAY_WR, B_ADEND2, B_FINAL, B_TAG, B_SEND,
                -- ARP reply
                A_BUILD, A_SEND,
                -- frame parsing
                P_HDR, P_HDR_USE, P_DECIDE, P_INIT, P_AD, P_AD_USE, P_ADEND1,
                P_PAY, P_PAY_USE, P_PAY_OUT, P_ADEND2, P_FINAL, P_TAG, P_TAG_USE,
                P_DONE);
  signal st, ret   : st_t := T_IDLE;       -- ret: where a build/parse returns
  signal xfer_op   : unsigned(3 downto 0) := x"0";   -- C_READ/C_WRITE/C_INFO/0
  signal hello_on  : std_logic := '0';
  signal next_lba  : unsigned(31 downto 0) := (others => '0');   -- addr + done_n
  signal room      : unsigned(31 downto 0) := (others => '0');   -- card left from it
  signal x_count   : unsigned(15 downto 0) := (others => '0');   -- 0: open
  signal granted   : unsigned(15 downto 0) := (others => '0');
  signal stopping  : std_logic := '0';     -- no more grants will come
  signal done_n    : unsigned(15 downto 0) := (others => '0');   -- blocks done
  signal req_first : unsigned(15 downto 0) := (others => '0');
  signal req_n     : unsigned(3 downto 0) := (others => '0');
  signal req_left  : unsigned(3 downto 0) := (others => '0');
  signal req_open  : std_logic := '0';     -- a request is outstanding
  signal held      : std_logic := '0';     -- the head frame waits for a grant
  signal tries     : unsigned(7 downto 0) := (others => '0');
  signal us_div    : unsigned(7 downto 0) := (others => '0');
  signal us_tick   : std_logic := '0';
  signal timer     : unsigned(19 downto 0) := (others => '0');   -- us

  -- frame building --------------------------------------------------------------
  signal b_op      : unsigned(7 downto 0) := (others => '0');
  signal b_lba     : unsigned(31 downto 0) := (others => '0');
  signal b_plen    : unsigned(9 downto 0) := (others => '0');    -- 16 or 512
  signal b_hello   : std_logic := '0';
  signal b_auth    : std_logic := '0';
  signal b_enc     : std_logic := '0';
  signal b_ip_len  : unsigned(15 downto 0) := (others => '0');
  signal b_udp_len : unsigned(15 downto 0) := (others => '0');
  signal csum      : unsigned(16 downto 0) := (others => '0');
  signal b_frame_len : unsigned(10 downto 0) := (others => '0');
  signal i         : unsigned(10 downto 0) := (others => '0');   -- byte index
  signal lat       : unsigned(3 downto 0) := (others => '0');
  signal pbyte     : unsigned(7 downto 0) := (others => '0');

  -- frame parsing ---------------------------------------------------------------
  signal f_dst     : unsigned(47 downto 0) := (others => '0');   -- Ethernet destination
  signal f_tpa     : unsigned(31 downto 0) := (others => '0');   -- ARP target IP
  signal f_dip     : unsigned(31 downto 0) := (others => '0');   -- IP destination
  signal f_sess    : unsigned(31 downto 0) := (others => '0');
  signal f_seq     : unsigned(31 downto 0) := (others => '0');
  signal f_echo    : unsigned(47 downto 0) := (others => '0');   -- HELLO's MAC echo
  signal f_smac    : unsigned(47 downto 0) := (others => '0');
  signal f_type    : unsigned(15 downto 0) := (others => '0');
  signal f_ok      : std_logic := '0';     -- fixed fields as expected so far
  signal f_arp_ok  : std_logic := '0';
  signal f_spa     : unsigned(31 downto 0) := (others => '0');   -- ARP sender IP
  signal f_sip     : unsigned(31 downto 0) := (others => '0');   -- IP source
  signal f_udp_len : unsigned(15 downto 0) := (others => '0');
  signal f_flags   : unsigned(7 downto 0) := (others => '0');
  signal f_op      : unsigned(7 downto 0) := (others => '0');
  signal f_lba     : unsigned(31 downto 0) := (others => '0');
  signal p_plen    : unsigned(9 downto 0) := (others => '0');
  signal p_auth, p_enc : std_logic := '0';
  signal p_good    : std_logic := '0';     -- the tag matched (or no tag)
  signal p_status  : unsigned(7 downto 0) := (others => '0');
  signal p_nakop   : unsigned(7 downto 0) := (others => '0');
  signal p_block   : unsigned(15 downto 0) := (others => '0');
  signal p_byte    : unsigned(7 downto 0) := (others => '0');   -- plaintext

  -- Ascon -------------------------------------------------------------------------
  signal a_init, a_valid, a_adend, a_final : std_logic := '0';
  signal a_mode    : unsigned(1 downto 0) := "00";
  signal a_in      : unsigned(7 downto 0) := (others => '0');
  signal a_out     : unsigned(7 downto 0);
  signal a_tagidx  : unsigned(3 downto 0) := (others => '0');
  signal a_tag     : unsigned(7 downto 0);
  signal a_busy    : std_logic;
  signal a_nonce   : unsigned(127 downto 0);
  signal n_parse   : std_logic := '0';     -- the nonce is for a received frame

  -- outputs -------------------------------------------------------------------------
  signal rd_valid_i, rd_good_i, rd_bad_i, wr_fetch_i : std_logic := '0';
  signal rd_data_i : unsigned(7 downto 0) := (others => '0');
  signal rd_off_i  : unsigned(8 downto 0) := (others => '0');
  signal rd_blk_i  : unsigned(15 downto 0) := (others => '0');
  signal wr_off_i  : unsigned(8 downto 0) := (others => '0');
  signal wr_blk_i  : unsigned(15 downto 0) := (others => '0');
  signal rx_raddr_i : unsigned(9 downto 0) := (others => '0');
  signal rx_rel_i, tx_we_i, tx_go_i, tx_base_i : std_logic := '0';
  signal tx_waddr_i : unsigned(10 downto 0) := (others => '0');
  signal tx_wdata_i : unsigned(7 downto 0) := (others => '0');
  signal tx_len_i  : unsigned(10 downto 0) := (others => '0');

  subtype byte_t is unsigned(7 downto 0);

  function be(v : unsigned(31 downto 0); k : natural) return byte_t is
  begin                                     -- byte k (0 = most significant)
    return resize(shift_right(v, 24 - 8 * k), 8);
  end function;

  function le(v : unsigned(31 downto 0); k : natural) return byte_t is
  begin                                     -- byte k (0 = least significant)
    return resize(shift_right(v, 8 * k), 8);
  end function;

  function macbyte(m : unsigned(47 downto 0); k : natural) return byte_t is
  begin                                     -- byte k as sent (0 first)
    return resize(shift_right(m, 40 - 8 * k), 8);
  end function;

begin

  crypto : entity work.ascon_aead128
    port map (clk => clock, init => a_init, key => key, nonce => a_nonce,
              byte_valid => a_valid, mode => a_mode, byte_in => a_in,
              byte_out => a_out, ad_end => a_adend, final => a_final,
              tag_idx => a_tagidx, tag_byte => a_tag, busy => a_busy);

  -- the key is the shift register's middle (it doesn't shift while on)
  key_bytes : for q in 0 to 15 generate
    key(8 * q + 7 downto 8 * q) <= sr(159 - 8 * q downto 152 - 8 * q);
  end generate;

  active <= on_i;
  ctl_status <= on_i & connected & auth & enc & last_nak;
  card_ready <= connected;
  cmd_ready <= ready_i;
  busy <= '1' when xfer_op /= x"0" or hello_on = '1' else '0';
  waiting <= '1' when (xfer_op = C_READ or xfer_op = C_WRITE) and x_count = 0
             and stopping = '0' and done_n = granted and req_open = '0' else '0';
  error <= err_i;
  err_code <= errc_i;
  blocks_done <= done_n;
  capacity_valid <= connected;
  last_sector <= capacity - 1;
  rd_valid <= rd_valid_i;
  rd_data <= rd_data_i;
  rd_offset <= rd_off_i;
  rd_block <= rd_blk_i;
  rd_good <= rd_good_i;
  rd_bad <= rd_bad_i;
  wr_fetch <= wr_fetch_i;
  wr_offset <= wr_off_i;
  wr_block <= wr_blk_i;
  -- Ascon takes the nonce at init: session | sequence | LBA | server nonce
  -- (none for HELLO) | op, bit 7 for a response
  a_nonce <= (f_op or x"80") & x"000000" & f_lba & seq & session
               when n_parse = '1' and f_op = OP_HELLO else
             (f_op or x"80") & rs & f_lba & seq & session when n_parse = '1' else
             b_op & x"000000" & b_lba & seq & session when b_op = OP_HELLO else
             b_op & rs & b_lba & seq & session;
  rx_raddr <= rx_raddr_i;
  rx_release <= rx_rel_i;
  tx_we <= tx_we_i;
  tx_waddr <= tx_waddr_i;
  tx_wdata <= tx_wdata_i;
  tx_go <= tx_go_i;
  tx_base <= tx_base_i;
  tx_len <= tx_len_i;

  process(clock)

    -- the header of the frame being built, byte k (0..57)
    impure function hdr(k : natural) return byte_t is
      variable flags : unsigned(7 downto 0);
    begin
      flags := x"10";
      flags(1) := b_auth;
      flags(2) := b_enc;
      case k is
        when 0 => if b_hello = '1' then return x"ff"; end if; return srv_mac(47 downto 40);
        when 1 => if b_hello = '1' then return x"ff"; end if; return srv_mac(39 downto 32);
        when 2 => if b_hello = '1' then return x"ff"; end if; return srv_mac(31 downto 24);
        when 3 => if b_hello = '1' then return x"ff"; end if; return srv_mac(23 downto 16);
        when 4 => if b_hello = '1' then return x"ff"; end if; return srv_mac(15 downto 8);
        when 5 => if b_hello = '1' then return x"ff"; end if; return srv_mac(7 downto 0);
        when 6 => return mac(47 downto 40);
        when 7 => return mac(39 downto 32);
        when 8 => return mac(31 downto 24);
        when 9 => return mac(23 downto 16);
        when 10 => return mac(15 downto 8);
        when 11 => return mac(7 downto 0);
        when 12 => return x"08";
        when 13 => return x"00";
        when 14 => return x"45";
        when 15 => return x"00";
        when 16 => return b_ip_len(15 downto 8);
        when 17 => return b_ip_len(7 downto 0);
        when 18 | 19 => return x"00";
        when 20 => return x"40";              -- don't fragment
        when 21 => return x"00";
        when 22 => return x"40";              -- TTL 64
        when 23 => return x"11";              -- UDP
        when 24 => return not csum(15 downto 8);
        when 25 => return not csum(7 downto 0);
        when 26 => if b_hello = '1' then return x"00"; end if; return my_ip(31 downto 24);
        when 27 => if b_hello = '1' then return x"00"; end if; return my_ip(23 downto 16);
        when 28 => if b_hello = '1' then return x"00"; end if; return my_ip(15 downto 8);
        when 29 => if b_hello = '1' then return x"00"; end if; return my_ip(7 downto 0);
        when 30 => if b_hello = '1' then return x"ff"; end if; return srv_ip(31 downto 24);
        when 31 => if b_hello = '1' then return x"ff"; end if; return srv_ip(23 downto 16);
        when 32 => if b_hello = '1' then return x"ff"; end if; return srv_ip(15 downto 8);
        when 33 => if b_hello = '1' then return x"ff"; end if; return srv_ip(7 downto 0);
        when 34 | 36 => return x"19";         -- port 6565
        when 35 | 37 => return x"a5";
        when 38 => return b_udp_len(15 downto 8);
        when 39 => return b_udp_len(7 downto 0);
        when 40 | 41 => return x"00";         -- no UDP checksum
        when 42 => return x"4d";              -- 'M'
        when 43 => return x"53";              -- 'S'
        when 44 => return flags;
        when 45 => return b_op;
        when 46 => return session(7 downto 0);
        when 47 => return session(15 downto 8);
        when 48 => return session(23 downto 16);
        when 49 => return session(31 downto 24);
        when 50 => return seq(7 downto 0);
        when 51 => return seq(15 downto 8);
        when 52 => return seq(23 downto 16);
        when 53 => return seq(31 downto 24);
        when 54 => return b_lba(7 downto 0);
        when 55 => return b_lba(15 downto 8);
        when 56 => return b_lba(23 downto 16);
        when 57 => return b_lba(31 downto 24);
        when others => return x"00";
      end case;
    end function;

    -- the IPv4 header's 16-bit words, for the checksum
    impure function ip_word(k : natural) return unsigned is
    begin
      case k is
        when 0 => return x"4500";
        when 1 => return b_ip_len;
        when 2 => return x"0000";
        when 3 => return x"4000";
        when 4 => return x"4011";
        when 5 => if b_hello = '1' then return x"0000"; end if; return my_ip(31 downto 16);
        when 6 => if b_hello = '1' then return x"0000"; end if; return my_ip(15 downto 0);
        when 7 => if b_hello = '1' then return x"ffff"; end if; return srv_ip(31 downto 16);
        when others => if b_hello = '1' then return x"ffff"; end if; return srv_ip(15 downto 0);
      end case;
    end function;

    -- payload byte k of a request (not WRITE: that is fetched)
    impure function req_payload(k : natural) return byte_t is
    begin
      if b_op = OP_HELLO then
        case k is
          when 0 => return mac(47 downto 40);
          when 1 => return mac(39 downto 32);
          when 2 => return mac(31 downto 24);
          when 3 => return mac(23 downto 16);
          when 4 => return mac(15 downto 8);
          when 5 => return mac(7 downto 0);
          when 6 => return '0' & octet;
          when 7 => return x"01";             -- capabilities: Ascon-AEAD128
          when 8 => return cycles(7 downto 0);
          when 9 => return cycles(15 downto 8);
          when 10 => return cycles(23 downto 16);
          when 11 => return cycles(31 downto 24);
          when 12 => return session(7 downto 0);
          when 13 => return session(15 downto 8);
          when 14 => return session(23 downto 16);
          when 15 => return session(31 downto 24);
          when others => return x"00";
        end case;
      elsif k = 0 then
        return x"0" & req_n;                  -- READ: the count
      end if;
      return x"00";
    end function;

    -- start building a request frame
    procedure build(op : unsigned(7 downto 0); lba : unsigned(31 downto 0);
                    plen : natural; back : st_t) is
      variable payload : natural;
    begin
      payload := 16 + plen;
      if auth = '1' then
        payload := payload + 16;
      end if;
      b_op <= op;
      b_lba <= lba;
      b_plen <= to_unsigned(plen, 10);
      b_hello <= '0';
      if op = OP_HELLO then
        b_hello <= '1';
      end if;
      b_auth <= auth;
      b_enc <= enc;
      if op = OP_HELLO then
        b_enc <= '0';
      end if;
      b_udp_len <= to_unsigned(8 + payload, 16);
      b_ip_len <= to_unsigned(28 + payload, 16);
      csum <= (others => '0');
      i <= (others => '0');
      ret <= back;
      st <= B_CSUM;
    end procedure;

    procedure fail(code : unsigned(7 downto 0)) is
    begin
      err_i <= '1';
      errc_i <= code;
      xfer_op <= x"0";
      hello_on <= '0';
      req_open <= '0';
      st <= T_IDLE;
    end procedure;

    procedure start_rx(k : natural) is
    begin
      rx_raddr_i <= to_unsigned(k, 10);
      i <= to_unsigned(k, 11);
    end procedure;

    variable sum   : unsigned(16 downto 0);
    variable b     : unsigned(7 downto 0);
    variable want  : unsigned(15 downto 0);
    variable n     : unsigned(3 downto 0);
    variable diff  : unsigned(32 downto 0);
    variable k     : natural;
  begin
    if rising_edge(clock) then
      -- strobes
      rd_valid_i <= '0';
      rd_good_i <= '0';
      rd_bad_i <= '0';
      wr_fetch_i <= '0';
      rx_rel_i <= '0';
      tx_we_i <= '0';
      tx_go_i <= '0';
      a_init <= '0';
      a_valid <= '0';
      a_adend <= '0';
      a_final <= '0';
      ready_i <= '1';

      cycles <= cycles + 1;
      us_tick <= '0';
      if us_div = G_US - 1 then
        us_div <= (others => '0');
        us_tick <= '1';
      else
        us_div <= us_div + 1;
      end if;
      if us_tick = '1' and timer /= x"fffff" then
        timer <= timer + 1;
      end if;

      -- the transfer ------------------------------------------------------------------
      case st is
        when T_IDLE =>
          if rx_ready = '1' then
            ret <= T_IDLE;
            start_rx(0);
            st <= P_HDR;
          end if;

        -- HELLO ---------------------------------------------------------------------------
        when T_HELLO =>
          seq <= seq + 1;
          build(OP_HELLO, x"00000000", 16, T_HELLO_WAIT);
          timer <= (others => '0');
          tries <= tries + 1;
        when T_HELLO_WAIT =>
          if connected = '1' then
            hello_on <= '0';
            st <= T_IDLE;
          elsif rx_ready = '1' then
            ret <= T_HELLO_WAIT;
            start_rx(0);
            st <= P_HDR;
          elsif timer >= G_HELLO_US then
            if tries >= G_HELLO_TRIES then
              fail(ERR_NOCARD);
            else
              st <= T_HELLO;
            end if;
          end if;

        -- READ ------------------------------------------------------------------------------
        when T_READ =>
          -- what may be asked for: the granted blocks, or (open-ended and
          -- not stopping) 8 ahead of the data, never past the card's end
          if x_count /= 0 then
            want := x_count - done_n;
          elsif stopping = '1' then
            want := granted - done_n;
          else
            want := to_unsigned(8, 16);
          end if;
          if want > 8 then
            want := to_unsigned(8, 16);
          end if;
          if room < 8 and resize(room, 16) < want then
            want := resize(room, 16);
          end if;
          n := want(3 downto 0);
          if done_n = granted and (x_count /= 0 or stopping = '1') then
            xfer_op <= x"0";                -- all done
            st <= T_IDLE;
          elsif req_open = '0' and n /= 0 then
            req_first <= done_n;
            req_n <= n;
            req_left <= n;
            req_open <= '1';
            held <= '0';
            seq <= seq + 1;
            timer <= (others => '0');
            build(OP_READ, next_lba, 16, T_READ_WAIT);
          else
            st <= T_READ_WAIT;
          end if;
        when T_READ_WAIT =>
          if done_n = granted then
            timer <= (others => '0');       -- the host is behind, not the PC
          end if;
          if rx_ready = '1' and (held = '0' or done_n /= granted) then
            ret <= T_READ_WAIT;
            start_rx(0);
            st <= P_HDR;
          elsif req_open = '0' or (done_n = granted and stopping = '1') then
            st <= T_READ;
          elsif timer >= G_RETRY_US then
            if tries >= G_TRIES then
              fail(ERR_RD_TMO);
            else
              tries <= tries + 1;
              req_open <= '0';              -- ask again from the first missing
              st <= T_READ;
            end if;
          end if;

        -- WRITE -----------------------------------------------------------------------------
        when T_WRITE =>
          if done_n = granted and (x_count /= 0 or stopping = '1') then
            xfer_op <= x"0";
            st <= T_IDLE;
          elsif done_n /= granted then
            req_first <= done_n;
            req_open <= '1';
            seq <= seq + 1;
            timer <= (others => '0');
            build(OP_WRITE, next_lba, 512, T_WRITE_WAIT);
          elsif rx_ready = '1' then
            ret <= T_WRITE;                  -- waiting for a grant
            start_rx(0);
            st <= P_HDR;
          end if;
        when T_WRITE_WAIT =>
          if rx_ready = '1' then
            ret <= T_WRITE_WAIT;
            start_rx(0);
            st <= P_HDR;
          elsif req_open = '0' then
            st <= T_WRITE;
          elsif timer >= G_RETRY_US then
            if tries >= G_TRIES then
              fail(ERR_WR_TMO);
            elsif tx_busy = '0' and tx_go_i = '0' then
              tries <= tries + 1;
              timer <= (others => '0');
              tx_base_i <= '0';             -- the frame is still there: again
              tx_len_i <= b_frame_len;
              tx_go_i <= '1';
            end if;
          end if;

        when T_INFO =>
          -- C_INFO: there is no CSD; 512 zero bytes
          if i = 512 then
            rd_good_i <= '1';
            done_n <= to_unsigned(1, 16);
            xfer_op <= x"0";
            st <= T_IDLE;
          else
            rd_valid_i <= '1';
            rd_data_i <= x"00";
            rd_off_i <= i(8 downto 0);
            rd_blk_i <= (others => '0');
            i <= i + 1;
          end if;

        -- building a request in the TX buffer -------------------------------------------
        when B_CSUM =>
          -- the IPv4 header checksum, a word a cycle
          sum := ('0' & csum(15 downto 0)) + ip_word(to_integer(i(3 downto 0))) + csum(16 downto 16);
          csum <= sum;
          i <= i + 1;
          if i = 8 then
            st <= B_FOLD;
          end if;
        when B_FOLD =>
          sum := ('0' & csum(15 downto 0)) + csum(16 downto 16);
          csum <= '0' & (sum(15 downto 0) + sum(16 downto 16));
          i <= (others => '0');
          st <= B_INIT;
        when B_INIT =>
          if b_auth = '0' then
            st <= B_HDR;
          elsif a_busy = '0' then
            n_parse <= '0';
            a_init <= '1';
            st <= B_HDR;
          end if;
        when B_HDR =>
          if b_auth = '0' or i < 42 or (a_busy = '0' and a_init = '0' and a_valid = '0') then
            b := hdr(to_integer(i));
            tx_we_i <= '1';
            tx_waddr_i <= i;
            tx_wdata_i <= b;
            if b_auth = '1' and i >= 42 then
              a_valid <= '1';
              a_mode <= "00";
              a_in <= b;
            end if;
            i <= i + 1;
            if i = HDR_LEN - 1 then
              if b_auth = '1' and b_enc = '1' then
                st <= B_ADEND1;
              else
                i <= (others => '0');
                st <= B_PAY;
              end if;
            end if;
          end if;
        when B_ADEND1 =>
          if a_busy = '0' and a_valid = '0' then
            a_adend <= '1';
            i <= (others => '0');
            st <= B_PAY;
          end if;
        when B_PAY =>
          if b_auth = '0' or (a_busy = '0' and a_valid = '0' and a_adend = '0') then
            if b_op = OP_WRITE then
              wr_fetch_i <= '1';
              wr_off_i <= i(8 downto 0);
              wr_blk_i <= req_first;
              lat <= to_unsigned(G_WR_LAT + 1, 4);   -- as sdcard_native samples it
              st <= B_PAY_FETCH;
            else
              pbyte <= req_payload(to_integer(i(3 downto 0)));
              st <= B_PAY_PUT;
            end if;
          end if;
        when B_PAY_FETCH =>
          lat <= lat - 1;
          if lat = 1 then
            pbyte <= wr_data;
            st <= B_PAY_PUT;
          end if;
        when B_PAY_PUT =>
          -- hand the byte to Ascon; its output is there next cycle
          if b_auth = '1' then
            a_valid <= '1';
            a_in <= pbyte;
            if b_enc = '1' then
              a_mode <= "01";
            else
              a_mode <= "00";
            end if;
          end if;
          st <= B_PAY_WR;
        when B_PAY_WR =>
          tx_we_i <= '1';
          tx_waddr_i <= i + HDR_LEN;
          if b_auth = '1' and b_enc = '1' then
            tx_wdata_i <= a_out;
          else
            tx_wdata_i <= pbyte;
          end if;
          i <= i + 1;
          st <= B_PAY;
          if i = b_plen - 1 then
            if b_auth = '0' then
              st <= B_SEND;
            elsif b_enc = '1' then
              st <= B_FINAL;
            else
              st <= B_ADEND2;
            end if;
          end if;
        when B_ADEND2 =>
          if a_busy = '0' and a_valid = '0' then
            a_adend <= '1';
            st <= B_FINAL;
          end if;
        when B_FINAL =>
          if a_busy = '0' and a_valid = '0' and a_adend = '0' then
            a_final <= '1';
            i <= (others => '0');
            a_tagidx <= (others => '0');
            st <= B_TAG;
          end if;
        when B_TAG =>
          if a_busy = '0' and a_final = '0' then
            a_tagidx <= i(3 downto 0) + 1;
            tx_we_i <= '1';
            tx_waddr_i <= i + HDR_LEN + b_plen;
            tx_wdata_i <= a_tag;
            i <= i + 1;
            if i = 15 then
              st <= B_SEND;
            end if;
          end if;
        when B_SEND =>
          if tx_busy = '0' and tx_go_i = '0' then
            tx_base_i <= '0';
            tx_len_i <= resize(b_ip_len, 11) + 14;
            b_frame_len <= resize(b_ip_len, 11) + 14;
            tx_go_i <= '1';
            st <= ret;
          end if;

        -- answering an ARP request ------------------------------------------------------
        when A_BUILD =>
          k := to_integer(i);
          case k is
            when 0 => b := f_smac(47 downto 40);
            when 1 => b := f_smac(39 downto 32);
            when 2 => b := f_smac(31 downto 24);
            when 3 => b := f_smac(23 downto 16);
            when 4 => b := f_smac(15 downto 8);
            when 5 => b := f_smac(7 downto 0);
            when 6 => b := mac(47 downto 40);
            when 7 => b := mac(39 downto 32);
            when 8 => b := mac(31 downto 24);
            when 9 => b := mac(23 downto 16);
            when 10 => b := mac(15 downto 8);
            when 11 => b := mac(7 downto 0);
            when 12 => b := x"08";
            when 13 => b := x"06";
            when 14 => b := x"00";
            when 15 => b := x"01";
            when 16 => b := x"08";
            when 17 => b := x"00";
            when 18 => b := x"06";
            when 19 => b := x"04";
            when 20 => b := x"00";
            when 21 => b := x"02";               -- reply
            when 22 => b := mac(47 downto 40);
            when 23 => b := mac(39 downto 32);
            when 24 => b := mac(31 downto 24);
            when 25 => b := mac(23 downto 16);
            when 26 => b := mac(15 downto 8);
            when 27 => b := mac(7 downto 0);
            when 28 => b := my_ip(31 downto 24);
            when 29 => b := my_ip(23 downto 16);
            when 30 => b := my_ip(15 downto 8);
            when 31 => b := my_ip(7 downto 0);
            when 32 => b := f_smac(47 downto 40);
            when 33 => b := f_smac(39 downto 32);
            when 34 => b := f_smac(31 downto 24);
            when 35 => b := f_smac(23 downto 16);
            when 36 => b := f_smac(15 downto 8);
            when 37 => b := f_smac(7 downto 0);
            when 38 => b := f_spa(31 downto 24);
            when 39 => b := f_spa(23 downto 16);
            when 40 => b := f_spa(15 downto 8);
            when 41 => b := f_spa(7 downto 0);
            when others => b := x"00";           -- padding to 60
          end case;
          if tx_busy = '0' or tx_base_i = '0' then  -- not over one being sent
            tx_we_i <= '1';
            tx_waddr_i <= i + 1024;
            tx_wdata_i <= b;
            i <= i + 1;
            if i = 59 then
              st <= A_SEND;
            end if;
          end if;
        when A_SEND =>
          if tx_busy = '0' and tx_go_i = '0' then
            tx_base_i <= '1';
            tx_len_i <= to_unsigned(60, 11);
            tx_go_i <= '1';
            st <= ret;
          end if;

        -- parsing the frame at the head of the receive ring ----------------------------
        when P_HDR =>
          -- (rx_raddr was set; its byte comes two cycles on)
          st <= P_HDR_USE;
        when P_HDR_USE =>
          b := rx_rdata;
          k := to_integer(i);
          rx_raddr_i <= resize(i + 1, 10);
          i <= i + 1;
          st <= P_HDR;
          if k = 0 then
            f_ok <= '1';
            f_arp_ok <= '1';
          end if;
          case k is
            when 0 to 5 => f_dst <= f_dst(39 downto 0) & b;
            when 6 to 11 => f_smac <= f_smac(39 downto 0) & b;
            when 12 | 13 => f_type <= f_type(7 downto 0) & b;
            when others => null;
          end case;
          -- ARP: htype 1, ptype 0800, 6, 4, oper 1 (request), SPA, TPA
          case k is
            when 14 | 17 | 20 => if b /= x"00" then f_arp_ok <= '0'; end if;
            when 16 => if b /= x"08" then f_arp_ok <= '0'; end if;
            when 15 | 21 => if b /= x"01" then f_arp_ok <= '0'; end if;
            when 18 => if b /= x"06" then f_arp_ok <= '0'; end if;
            when 19 => if b /= x"04" then f_arp_ok <= '0'; end if;
            when 28 to 31 => f_spa <= f_spa(23 downto 0) & b;
            when 38 to 41 => f_tpa <= f_tpa(23 downto 0) & b;
            when others => null;
          end case;
          -- IPv4 / UDP / netsd
          case k is
            when 14 => if b /= x"45" then f_ok <= '0'; end if;
            when 20 => if b(5 downto 0) /= 0 then f_ok <= '0'; end if;  -- no fragments
            when 21 => if b /= x"00" then f_ok <= '0'; end if;
            when 23 => if b /= x"11" then f_ok <= '0'; end if;
            when 26 to 29 => f_sip <= f_sip(23 downto 0) & b;
            when 30 to 33 => f_dip <= f_dip(23 downto 0) & b;
            when 34 | 36 => if b /= x"19" then f_ok <= '0'; end if;
            when 35 | 37 => if b /= x"a5" then f_ok <= '0'; end if;
            when 38 | 39 => f_udp_len <= f_udp_len(7 downto 0) & b;
            when 42 => if b /= x"4d" then f_ok <= '0'; end if;
            when 43 => if b /= x"53" then f_ok <= '0'; end if;
            when 44 => f_flags <= b;
            when 45 => f_op <= b;
            when 46 to 49 => f_sess <= b & f_sess(31 downto 8);
            when 50 to 53 => f_seq <= b & f_seq(31 downto 8);
            when 54 to 57 => f_lba <= b & f_lba(31 downto 8);
            when others => null;
          end case;
          if k = HDR_LEN - 1 then
            st <= P_DECIDE;
          end if;

        when P_DECIDE =>
          st <= P_DONE;                     -- unless something below wants it
          p_good <= '0';
          p_auth <= f_flags(1);
          p_enc <= f_flags(2);
          if f_op = OP_HELLO then
            p_plen <= to_unsigned(32, 10);
          elsif f_op = OP_READ then
            p_plen <= to_unsigned(512, 10);
          else
            p_plen <= to_unsigned(16, 10);
          end if;
          p_status <= x"00";
          p_nakop <= x"00";
          p_block <= x"ffff";
          -- the UDP length must be what the op carries, and fit the frame
          if f_flags(1) = '1' then
            want := to_unsigned(8 + 16 + 16, 16);
          else
            want := to_unsigned(8 + 16, 16);
          end if;
          if f_op = OP_HELLO then
            want := want + 32;
          elsif f_op = OP_READ then
            want := want + 512;
          else
            want := want + 16;
          end if;
          if f_type = x"0806" then
            if f_arp_ok = '1' and f_tpa = my_ip and connected = '1'
              and (f_dst = x"ffffffffffff" or f_dst = mac) and rx_len >= 46 then
              i <= (others => '0');
              rx_rel_i <= '1';               -- the reply needs nothing more from it
              st <= A_BUILD;
            end if;
          elsif f_type = x"0800" and f_ok = '1' and f_sess = session and f_seq = seq
            and f_udp_len = want and resize(rx_len, 16) >= want + 38
            and f_flags(7 downto 4) = x"1" and f_flags(0) = '1' and f_flags(1) = auth
            and ((f_op = OP_HELLO and f_flags(2) = '0') or (f_op /= OP_HELLO and f_flags(2) = enc)) then
            if f_op = OP_HELLO then
              if ret = T_HELLO_WAIT and (f_dst = mac or f_dst = x"ffffffffffff") then
                st <= P_INIT;
              end if;
            elsif connected = '1' and f_dst = mac and f_dip = my_ip and f_sip = srv_ip then
              if f_op = OP_READ then
                if ret = T_READ_WAIT and req_open = '1' and f_lba = next_lba then
                  if done_n = granted then
                    held <= '1';             -- not granted yet: leave it there
                    st <= ret;
                  else
                    p_block <= done_n;
                    st <= P_INIT;
                  end if;
                end if;
              elsif (f_op = OP_WRITE and ret = T_WRITE_WAIT and f_lba = next_lba)
                or (f_op = OP_NAK and (ret = T_READ_WAIT or ret = T_WRITE_WAIT)) then
                st <= P_INIT;
              end if;
            end if;
          end if;

        when P_INIT =>
          if p_auth = '0' then
            p_good <= '1';
            i <= (others => '0');
            rx_raddr_i <= to_unsigned(HDR_LEN, 10);
            st <= P_PAY;
          elsif a_busy = '0' then
            n_parse <= '1';
            a_init <= '1';
            start_rx(42);
            st <= P_AD;
          end if;
        when P_AD =>
          st <= P_AD_USE;
        when P_AD_USE =>
          if a_busy = '0' and a_init = '0' and a_valid = '0' then
            a_valid <= '1';
            a_mode <= "00";
            a_in <= rx_rdata;
            rx_raddr_i <= resize(i + 1, 10);
            i <= i + 1;
            st <= P_AD;
            if i = HDR_LEN - 1 then
              if p_enc = '1' then
                st <= P_ADEND1;
              else
                i <= (others => '0');
                rx_raddr_i <= to_unsigned(HDR_LEN, 10);
                st <= P_PAY;
              end if;
            end if;
          end if;
        when P_ADEND1 =>
          if a_busy = '0' and a_valid = '0' then
            a_adend <= '1';
            i <= (others => '0');
            rx_raddr_i <= to_unsigned(HDR_LEN, 10);
            st <= P_PAY;
          end if;
        when P_PAY =>
          st <= P_PAY_USE;
        when P_PAY_USE =>
          if p_auth = '0' or (a_busy = '0' and a_valid = '0' and a_adend = '0' and a_init = '0') then
            p_byte <= rx_rdata;
            if p_auth = '1' then
              a_valid <= '1';
              a_in <= rx_rdata;
              if p_enc = '1' then
                a_mode <= "10";
              else
                a_mode <= "00";
              end if;
            end if;
            rx_raddr_i <= resize(i + 1 + HDR_LEN, 10);
            st <= P_PAY_OUT;
          end if;
        when P_PAY_OUT =>
          -- the plaintext byte: Ascon's output now, if it is decrypting
          if p_auth = '1' and p_enc = '1' then
            b := a_out;
          else
            b := p_byte;
          end if;
          k := to_integer(i(9 downto 0));
          if f_op = OP_READ then
            rd_valid_i <= '1';
            rd_data_i <= b;
            rd_off_i <= i(8 downto 0);
            rd_blk_i <= p_block;
          elsif f_op = OP_HELLO then
            case k is
              when 0 to 3 => my_ip <= my_ip(23 downto 0) & b;
              when 4 to 7 => srv_ip <= srv_ip(23 downto 0) & b;
              when 8 to 11 => capacity <= b & capacity(31 downto 8);
              when 16 to 18 => rs <= b & rs(23 downto 8);
              when 24 to 29 => f_echo <= f_echo(39 downto 0) & b;
              when others => null;
            end case;
          else
            if k = 0 then p_status <= b; end if;
            if k = 1 then p_nakop <= b; end if;
          end if;
          i <= i + 1;
          st <= P_PAY_USE;
          if i = p_plen - 1 then
            if p_auth = '0' then
              st <= P_DONE;
            elsif p_enc = '1' then
              st <= P_FINAL;
            else
              st <= P_ADEND2;
            end if;
          end if;
        when P_ADEND2 =>
          if a_busy = '0' and a_valid = '0' then
            a_adend <= '1';
            st <= P_FINAL;
          end if;
        when P_FINAL =>
          if a_busy = '0' and a_valid = '0' and a_adend = '0' then
            a_final <= '1';
            p_good <= '1';
            i <= (others => '0');
            a_tagidx <= (others => '0');
            rx_raddr_i <= resize(p_plen + HDR_LEN, 10);
            st <= P_TAG;
          end if;
        when P_TAG =>
          st <= P_TAG_USE;
        when P_TAG_USE =>
          if a_busy = '0' and a_final = '0' then
            if rx_rdata /= a_tag then
              p_good <= '0';
            end if;
            a_tagidx <= i(3 downto 0) + 1;
            rx_raddr_i <= resize(p_plen + HDR_LEN + i + 1, 10);
            i <= i + 1;
            st <= P_TAG;
            if i = 15 then
              st <= P_DONE;
            end if;
          end if;

        when P_DONE =>
          rx_rel_i <= '1';
          st <= ret;
          if f_op = OP_READ and p_block /= x"ffff" then
            if p_block = done_n and xfer_op = C_READ then
              if p_good = '1' then
                rd_good_i <= '1';
                done_n <= done_n + 1;
                next_lba <= next_lba + 1;
                room <= room - 1;
                tries <= (others => '0');
                timer <= (others => '0');
                req_left <= req_left - 1;
                if req_left = 1 then
                  req_open <= '0';
                end if;
              else
                rd_bad_i <= '1';
                req_open <= '0';           -- ask for it again
              end if;
            end if;
          elsif p_good = '1' and f_type = x"0800" then
            if f_op = OP_HELLO and ret = T_HELLO_WAIT and f_echo = mac then
              connected <= '1';
              srv_mac <= f_smac;
            elsif f_op = OP_WRITE and ret = T_WRITE_WAIT then
              if p_status = 0 then
                done_n <= done_n + 1;
                next_lba <= next_lba + 1;
                room <= room - 1;
                tries <= (others => '0');
                req_open <= '0';
              elsif p_status = 1 then
                fail(ERR_RANGE);
              else
                fail(ERR_WR_ERR);
              end if;
            elsif f_op = OP_NAK then
              last_nak <= p_status(3 downto 0);
              if p_status = 4 then
                connected <= '0';
                fail(ERR_NOTREADY);
              elsif p_status = 1 then
                fail(ERR_RANGE);
              elsif ret = T_WRITE_WAIT then
                fail(ERR_WR_ERR);
              else
                fail(ERR_CMD);
              end if;
            end if;
          end if;
        when others =>
          st <= T_IDLE;
      end case;

      -- commands (after the transfer, so that they win) ---------------------------------
      diff := ('0' & capacity) - ('0' & cmd_addr);   -- the card from cmd_addr on
      if cmd_valid = '1' and ready_i = '1' then
        ready_i <= '0';                    -- status shows it next cycle
        case cmd_code is
          when C_INIT | C_INIT_BOTH =>
            err_i <= '0';
            errc_i <= ERR_NONE;
            connected <= '0';
            xfer_op <= x"0";
            req_open <= '0';
            if on_i = '1' then
              tries <= (others => '0');
              session <= session + 1;      -- a new session for each init
              hello_on <= '1';
              st <= T_HELLO;
            else
              hello_on <= '0';
              err_i <= '1';
              errc_i <= ERR_NOCARD;
              st <= T_IDLE;
            end if;
          when C_READ | C_WRITE | C_INFO =>
            if xfer_op /= x"0" or hello_on = '1' then
              err_i <= '1';
              errc_i <= ERR_BUSY;
            elsif connected = '0' then
              err_i <= '1';
              errc_i <= ERR_NOTREADY;
            elsif cmd_code /= C_INFO and
              (diff(32) = '1' or diff(31 downto 0) = 0 or
               (diff(31 downto 16) = 0 and cmd_count > diff(15 downto 0))) then
              err_i <= '1';
              errc_i <= ERR_RANGE;
            else
              err_i <= '0';
              errc_i <= ERR_NONE;
              next_lba <= cmd_addr;
              room <= diff(31 downto 0);
              x_count <= cmd_count;
              granted <= cmd_count;
              if cmd_count = 0 then
                granted <= to_unsigned(1, 16);
              end if;
              stopping <= '0';
              done_n <= (others => '0');
              req_open <= '0';
              held <= '0';
              tries <= (others => '0');
              xfer_op <= cmd_code;
              if cmd_code = C_READ then
                st <= T_READ;
              elsif cmd_code = C_WRITE then
                st <= T_WRITE;
              else
                i <= (others => '0');
                st <= T_INFO;
              end if;
            end if;
          when C_MORE =>
            if (xfer_op = C_READ or xfer_op = C_WRITE) and x_count = 0 and stopping = '0' then
              granted <= granted + 1;
              stopping <= cmd_arg(0);
              held <= '0';
            end if;
          when C_STOP =>
            stopping <= '1';
            held <= '0';
          when others =>                   -- PROBE, ACCEPT, CLEAR, ...
            if xfer_op = x"0" and hello_on = '0' then
              err_i <= '0';
              errc_i <= ERR_NONE;
            end if;
        end case;
      end if;

      -- the control register ------------------------------------------------------------
      if ctl_write = '1' then
        if ctl_wdata(7) = '0' then
          if on_i = '0' then                -- (the key in use stays put)
            sr <= sr(160 downto 0) & ctl_wdata(6 downto 0);
          end if;
        else
          connected <= '0';
          xfer_op <= x"0";
          hello_on <= '0';
          req_open <= '0';
          st <= T_IDLE;
          if ctl_wdata(6 downto 0) /= 0 then
            on_i <= '1';
            octet <= ctl_wdata(6 downto 0);
            auth <= sr(160) or sr(161);     -- encrypting implies authenticating
            enc <= sr(161);
            session <= sr(31 downto 0) xor cycles;
          else
            on_i <= '0';
            sr <= (others => '0');           -- (the key with it)
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture;
