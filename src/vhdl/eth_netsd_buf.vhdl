--------------------------------------------------------------------------------
-- eth_netsd_buf: the frame buffers between ethernet.vhdl (50 MHz) and sd_eth
-- (cpuclock), for SD over Ethernet (MEGA65/mega65-core#965).
--
-- Copyright (C) 2026 Paul Gardner-Stephen and the MEGA65 project.
-- Released under the GNU Lesser General Public License v3 (as LICENSE.txt).
--
-- RX: a ring of four 1 KB slots (one RAMB36), written on the 50 MHz side as
-- frames arrive, independently of the CPU's own receive buffers.  A frame
-- goes into the slot at the tail if that slot is free, and is committed only
-- if its CRC is good and it fits (FCS included); otherwise the slot is used
-- again.  The cpuclock side sees the slot at the head (rx_ready, rx_len,
-- rx_raddr -> rx_rdata, registered) and frees it with rx_release.  Frames
-- stay in order.
--
-- TX: 2 KB (one RAMB18), written on the cpuclock side: bytes 0..1023 the
-- netsd frame, 1024..2047 the ARP reply.  tx_go (with tx_base, tx_len)
-- hands one to the 50 MHz side; tx_busy until the Ethernet TX state
-- machine says it went (tx50_done).
--
-- Crossings: toggles with two-flop synchronisers; lengths and the base are
-- held stable from before their toggle until the other side answers.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity eth_netsd_buf is
  port (
    clock50     : in  std_logic;
    cpuclock    : in  std_logic;

    -- 50 MHz: from the RX state machine
    rx50_start  : in  std_logic;            -- a frame begins
    rx50_we     : in  std_logic;            -- one byte of it
    rx50_addr   : in  unsigned(10 downto 0);  -- its offset in the frame
    rx50_data   : in  unsigned(7 downto 0);
    rx50_end    : in  std_logic;            -- the frame is over
    rx50_ok     : in  std_logic;            -- with a good CRC
    rx50_len    : in  unsigned(10 downto 0);  -- bytes, FCS included

    -- 50 MHz: to the TX state machine
    tx50_pending : out std_logic;
    tx50_len    : out unsigned(10 downto 0);
    tx50_raddr  : in  unsigned(10 downto 0);
    tx50_rdata  : out unsigned(7 downto 0);
    tx50_done   : in  std_logic;

    -- cpuclock: to sd_eth
    rx_ready    : out std_logic;
    rx_len      : out unsigned(10 downto 0);
    rx_raddr    : in  unsigned(9 downto 0);
    rx_rdata    : out unsigned(7 downto 0);
    rx_release  : in  std_logic;
    tx_we       : in  std_logic;
    tx_waddr    : in  unsigned(10 downto 0);
    tx_wdata    : in  unsigned(7 downto 0);
    tx_go       : in  std_logic;
    tx_base     : in  std_logic;
    tx_len      : in  unsigned(10 downto 0);
    tx_busy     : out std_logic
    );
end entity;

architecture rtl of eth_netsd_buf is

  type rx_mem_t is array (0 to 4095) of unsigned(7 downto 0);
  type tx_mem_t is array (0 to 2047) of unsigned(7 downto 0);
  type len_t is array (0 to 3) of unsigned(10 downto 0);

  signal rx_mem : rx_mem_t;
  signal tx_mem : tx_mem_t;

  -- RX, 50 MHz side
  signal tail     : unsigned(1 downto 0) := "00";
  signal claimed  : std_logic := '0';
  signal commit_t : std_logic_vector(3 downto 0) := (others => '0');
  signal free_s1, free_s2 : std_logic_vector(3 downto 0) := (others => '0');
  signal lens     : len_t := (others => (others => '0'));

  -- RX, cpuclock side
  signal head     : unsigned(1 downto 0) := "00";
  signal free_t   : std_logic_vector(3 downto 0) := (others => '0');
  signal commit_s1, commit_s2 : std_logic_vector(3 downto 0) := (others => '0');

  -- TX
  signal req_t, ack_t : std_logic := '0';
  signal req_s1, req_s2, ack_s1, ack_s2 : std_logic := '0';
  signal base_r   : std_logic := '0';
  signal len_r    : unsigned(10 downto 0) := (others => '0');

  attribute ram_style : string;
  attribute ram_style of rx_mem : signal is "block";
  attribute ram_style of tx_mem : signal is "block";
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of free_s1, free_s2, commit_s1, commit_s2 : signal is "TRUE";
  attribute ASYNC_REG of req_s1, req_s2, ack_s1, ack_s2 : signal is "TRUE";

begin

  -- RX: 50 MHz --------------------------------------------------------------------
  process(clock50)
    variable t : natural;
  begin
    if rising_edge(clock50) then
      free_s1 <= free_t;
      free_s2 <= free_s1;
      t := to_integer(tail);
      if rx50_start = '1' then
        -- the tail slot is free when its commit and free toggles agree
        if commit_t(t) = free_s2(t) then
          claimed <= '1';
        else
          claimed <= '0';                   -- ring full: this frame is lost
        end if;
      end if;
      if rx50_we = '1' and claimed = '1' and rx50_addr < 1024 then
        rx_mem(t * 1024 + to_integer(rx50_addr(9 downto 0))) <= rx50_data;
      end if;
      if rx50_end = '1' then
        if claimed = '1' and rx50_ok = '1' and rx50_len <= 1024 and rx50_len >= 18 then
          lens(t) <= rx50_len;
          commit_t(t) <= not commit_t(t);
          tail <= tail + 1;
        end if;
        claimed <= '0';
      end if;
    end if;
  end process;

  -- RX: cpuclock -----------------------------------------------------------------
  -- (low while a release is under way: the head moves at the end of that
  -- cycle, and the slot after it may still be filling)
  rx_ready <= '1' when commit_s2(to_integer(head)) /= free_t(to_integer(head))
              and rx_release = '0' else '0';
  rx_len <= lens(to_integer(head));

  process(cpuclock)
  begin
    if rising_edge(cpuclock) then
      commit_s1 <= commit_t;
      commit_s2 <= commit_s1;
      rx_rdata <= rx_mem(to_integer(head) * 1024 + to_integer(rx_raddr));
      if rx_release = '1' and commit_s2(to_integer(head)) /= free_t(to_integer(head)) then
        free_t(to_integer(head)) <= not free_t(to_integer(head));
        head <= head + 1;
      end if;
    end if;
  end process;

  -- TX: cpuclock -----------------------------------------------------------------
  tx_busy <= req_t xor ack_s2;

  process(cpuclock)
  begin
    if rising_edge(cpuclock) then
      ack_s1 <= ack_t;
      ack_s2 <= ack_s1;
      if tx_we = '1' then
        tx_mem(to_integer(tx_waddr)) <= tx_wdata;
      end if;
      if tx_go = '1' and (req_t xor ack_s2) = '0' then
        base_r <= tx_base;
        len_r <= tx_len;
        req_t <= not req_t;
      end if;
    end if;
  end process;

  -- TX: 50 MHz -------------------------------------------------------------------
  tx50_pending <= req_s2 xor ack_t;
  tx50_len <= len_r;

  process(clock50)
  begin
    if rising_edge(clock50) then
      req_s1 <= req_t;
      req_s2 <= req_s1;
      tx50_rdata <= tx_mem(to_integer(base_r & tx50_raddr(9 downto 0)));
      if tx50_done = '1' and (req_s2 xor ack_t) = '1' then
        ack_t <= not ack_t;
      end if;
    end if;
  end process;

end architecture;
