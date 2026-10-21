-- SHITE's clock162 side.  The engine itself (shite) runs on sclock, which
-- comes from the same MMCM as clock162 at an integer fraction of its rate
-- (a quarter, on the boards), so the crossings are synchronous: every signal crossing either way leaves a flip-flop and
-- arrives at one (no logic between), and Vivado times each against
-- clock162's period.  Events cross as toggles, their data held from the
-- toggle's change until the answer.
--
-- The coprocessor port: SSNAIL's cop_start captures the instruction here
-- and toggles start_t; shite's done_t toggle becomes cop_done, one cycle,
-- with err / wr / result registered beside it.
--
-- The memory: one 8-byte group per request (g_t toggles, its fields held),
-- issued here as a LUMP command on the HyperRAM or SDRAM port; the eight
-- bytes read, or the error, come back with g_ack_t.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lumptypes.all;

entity shite_bridge is
  port (
    clock162 : in std_logic;

    -- SSNAIL's coprocessor port
    cop_start  : in  std_logic;
    cop_op     : in  unsigned(7 downto 0);
    cop_ra, cop_rb, cop_rc, cop_rd, cop_z : in unsigned(31 downto 0);
    cop_x      : in  unsigned(27 downto 0);
    cop_abort  : in  std_logic;
    cop_done   : out std_logic := '0';
    cop_err    : out unsigned(7 downto 0) := (others => '0');
    cop_wr     : out std_logic := '0';
    cop_result : out unsigned(31 downto 0) := (others => '0');
    map_hr_base, map_hr_size, map_sd_base, map_sd_size : in unsigned(7 downto 0);

    -- to shite (sclock)
    start_t : out std_logic := '0';
    op      : out unsigned(7 downto 0) := (others => '0');
    ra, rb, rc, rd, z : out unsigned(31 downto 0) := (others => '0');
    x       : out unsigned(27 downto 0) := (others => '0');
    abort   : out std_logic := '0';
    done_t  : in  std_logic;
    err     : in  unsigned(7 downto 0);
    wr      : in  std_logic;
    result  : in  unsigned(31 downto 0);
    m_hr_base, m_hr_size, m_sd_base, m_sd_size : out unsigned(7 downto 0) := (others => '0');
    g_t     : in  std_logic;
    g_write : in  std_logic;
    g_sd    : in  std_logic;
    g_addr  : in  unsigned(26 downto 0);
    g_wd    : in  unsigned(63 downto 0);
    g_be    : in  std_logic_vector(7 downto 0);
    g_ack_t : out std_logic := '0';
    g_rd    : out unsigned(63 downto 0) := (others => '0');
    g_err   : out std_logic := '0';

    -- LUMP masters (valid only while SSNAIL has handed them over)
    hr_cmd_valid   : out std_logic := '0';
    hr_cmd_ready   : in  std_logic;
    hr_cmd_op      : out unsigned(1 downto 0) := "00";
    hr_cmd_addr    : out unsigned(26 downto 0) := (others => '0');
    hr_cmd_len     : out unsigned(8 downto 0) := (others => '0');
    hr_rdata       : in  unsigned(15 downto 0);
    hr_rdata_valid : in  std_logic;
    hr_wdata_req   : in  std_logic;
    hr_wdata       : out unsigned(15 downto 0) := x"0000";
    hr_wdata_be    : out std_logic_vector(1 downto 0) := "11";
    hr_cmd_done    : in  std_logic;
    hr_error       : in  std_logic;
    sd_cmd_valid   : out std_logic := '0';
    sd_cmd_ready   : in  std_logic;
    sd_cmd_op      : out unsigned(1 downto 0) := "00";
    sd_cmd_addr    : out unsigned(26 downto 0) := (others => '0');
    sd_cmd_len     : out unsigned(8 downto 0) := (others => '0');
    sd_rdata       : in  unsigned(15 downto 0);
    sd_rdata_valid : in  std_logic;
    sd_wdata_req   : in  std_logic;
    sd_wdata       : out unsigned(15 downto 0) := x"0000";
    sd_wdata_be    : out std_logic_vector(1 downto 0) := "11";
    sd_cmd_done    : in  std_logic;
    sd_error       : in  std_logic
    );
end shite_bridge;

architecture rtl of shite_bridge is
  signal s_t, d1, d2 : std_logic := '0';
  -- the group engine
  signal g1, g_seen, a_t : std_logic := '0';
  signal busy : boolean := false;
  signal e_write, e_sd, e_dn : std_logic := '0';
  signal e_wd : unsigned(63 downto 0) := (others => '0');
  signal e_be : std_logic_vector(7 downto 0) := (others => '1');
  signal e_rd : unsigned(63 downto 0) := (others => '0');
  signal e_words, e_wk : unsigned(2 downto 0) := (others => '0');
  signal hr_v, sd_v : std_logic := '0';
begin
  start_t <= s_t;
  g_ack_t <= a_t;
  g_rd <= e_rd;
  hr_cmd_valid <= hr_v;
  sd_cmd_valid <= sd_v;

  process (clock162)
    variable w : unsigned(15 downto 0);
    variable b : std_logic_vector(1 downto 0);
  begin
    if rising_edge(clock162) then
      -- the coprocessor port
      if cop_start = '1' then
        op <= cop_op; ra <= cop_ra; rb <= cop_rb; rc <= cop_rc; rd <= cop_rd;
        z <= cop_z; x <= cop_x;
        s_t <= not s_t;
      end if;
      abort <= cop_abort;
      m_hr_base <= map_hr_base; m_hr_size <= map_hr_size;
      m_sd_base <= map_sd_base; m_sd_size <= map_sd_size;
      d1 <= done_t; d2 <= d1;
      cop_done <= d1 xor d2;                -- (err / wr / result arrived with d1)
      cop_err <= err; cop_wr <= wr; cop_result <= result;

      -- the memory: one group
      g1 <= g_t;
      if hr_cmd_ready = '1' then hr_v <= '0'; end if;
      if sd_cmd_ready = '1' then sd_v <= '0'; end if;

      -- write data: each request is answered the next cycle
      if busy and e_write = '1' and e_wk /= 4
        and ((hr_wdata_req = '1' and e_sd = '0') or (sd_wdata_req = '1' and e_sd = '1')) then
        w := e_wd(to_integer(e_wk) * 16 + 15 downto to_integer(e_wk) * 16);
        b := e_be(to_integer(e_wk) * 2 + 1) & e_be(to_integer(e_wk) * 2);
        hr_wdata <= w; sd_wdata <= w;
        hr_wdata_be <= b; sd_wdata_be <= b;
        e_wk <= e_wk + 1;
      end if;

      if not busy then
        if g1 /= g_seen then
          g_seen <= g1;
          e_write <= g_write; e_sd <= g_sd; e_wd <= g_wd; e_be <= g_be;
          e_words <= (others => '0'); e_wk <= (others => '0'); e_dn <= '0';
          if g_write = '1' then
            hr_cmd_op <= LUMP_OP_WRITE; sd_cmd_op <= LUMP_OP_WRITE;
          else
            hr_cmd_op <= LUMP_OP_READ; sd_cmd_op <= LUMP_OP_READ;
          end if;
          hr_cmd_addr <= g_addr; sd_cmd_addr <= g_addr;
          hr_cmd_len <= to_unsigned(8, 9); sd_cmd_len <= to_unsigned(8, 9);
          if g_sd = '1' then sd_v <= '1'; else hr_v <= '1'; end if;
          busy <= true;
        end if;
      else
        if e_sd = '1' then
          if sd_rdata_valid = '1' and e_write = '0' then
            e_rd <= sd_rdata & e_rd(63 downto 16);
            e_words <= e_words + 1;
          end if;
          if sd_cmd_done = '1' then e_dn <= '1'; end if;
        else
          if hr_rdata_valid = '1' and e_write = '0' then
            e_rd <= hr_rdata & e_rd(63 downto 16);
            e_words <= e_words + 1;
          end if;
          if hr_cmd_done = '1' then e_dn <= '1'; end if;
        end if;
        if (e_sd = '1' and sd_error = '1') or (e_sd = '0' and hr_error = '1') then
          g_err <= '1'; a_t <= not a_t; busy <= false;
        elsif e_dn = '1' and (e_write = '1' or e_words = 4) then
          g_err <= '0'; a_t <= not a_t; busy <= false;
        end if;
      end if;
    end if;
  end process;
end rtl;
