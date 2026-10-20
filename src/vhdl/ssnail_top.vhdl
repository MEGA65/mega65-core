-- SSNAIL with its coprocessors: the LLM / vector units (has_llm, inside
-- ssnail) and SHITE, the spreadsheet engine (has_shite).  SSNAIL dispatches
-- SHITE's opcodes and hands it the LUMP ports for each one (cop_own), so
-- the ports are simply multiplexed here: no arbitration.
--
-- SHITE runs on clock81 (half clock162, from the same MMCM): shite_bridge
-- is its clock162 side, the coprocessor port and the LUMP commands.
--
-- The same ports as ssnail.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ssnail_top is
  generic (
    has_sdram : boolean := false;
    has_llm   : boolean := true;
    has_shite : boolean := false
    );
  port (
    cpuclock     : in  std_logic;
    reset        : in  std_logic;
    irq          : out std_logic := '1';
    ssnail_cs    : in  std_logic;
    fastio_addr  : in  unsigned(19 downto 0);
    fastio_write : in  std_logic;
    fastio_read  : in  std_logic;
    fastio_wdata : in  unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0);

    clock162 : in std_logic;
    clock81  : in std_logic := '0';     -- SHITE's (needed with has_shite)

    hr_cmd_valid   : out std_logic := '0';
    hr_cmd_ready   : in  std_logic := '0';
    hr_cmd_op      : out unsigned(1 downto 0) := "00";
    hr_cmd_addr    : out unsigned(26 downto 0) := (others => '0');
    hr_cmd_len     : out unsigned(8 downto 0) := (others => '0');
    hr_rdata       : in  unsigned(15 downto 0) := x"0000";
    hr_rdata_valid : in  std_logic := '0';
    hr_wdata_req   : in  std_logic := '0';
    hr_wdata       : out unsigned(15 downto 0) := x"0000";
    hr_wdata_be    : out std_logic_vector(1 downto 0) := "11";
    hr_cmd_done    : in  std_logic := '0';
    hr_error       : in  std_logic := '0';

    sd_cmd_valid   : out std_logic := '0';
    sd_cmd_ready   : in  std_logic := '0';
    sd_cmd_op      : out unsigned(1 downto 0) := "00";
    sd_cmd_addr    : out unsigned(26 downto 0) := (others => '0');
    sd_cmd_len     : out unsigned(8 downto 0) := (others => '0');
    sd_rdata       : in  unsigned(15 downto 0) := x"0000";
    sd_rdata_valid : in  std_logic := '0';
    sd_wdata_req   : in  std_logic := '0';
    sd_wdata       : out unsigned(15 downto 0) := x"0000";
    sd_wdata_be    : out std_logic_vector(1 downto 0) := "11";
    sd_cmd_done    : in  std_logic := '0';
    sd_error       : in  std_logic := '0'
    );
end ssnail_top;

architecture rtl of ssnail_top is
  -- SSNAIL's side of the ports
  signal n_hr_cmd_valid, n_hr_cmd_ready, n_hr_rdata_valid, n_hr_wdata_req, n_hr_cmd_done, n_hr_error : std_logic;
  signal n_hr_cmd_op : unsigned(1 downto 0);
  signal n_hr_cmd_addr : unsigned(26 downto 0);
  signal n_hr_cmd_len : unsigned(8 downto 0);
  signal n_hr_wdata : unsigned(15 downto 0);
  signal n_hr_wdata_be : std_logic_vector(1 downto 0);
  signal n_sd_cmd_valid, n_sd_cmd_ready, n_sd_rdata_valid, n_sd_wdata_req, n_sd_cmd_done, n_sd_error : std_logic;
  signal n_sd_cmd_op : unsigned(1 downto 0);
  signal n_sd_cmd_addr : unsigned(26 downto 0);
  signal n_sd_cmd_len : unsigned(8 downto 0);
  signal n_sd_wdata : unsigned(15 downto 0);
  signal n_sd_wdata_be : std_logic_vector(1 downto 0);
  -- SHITE's
  signal s_hr_cmd_valid, s_sd_cmd_valid : std_logic := '0';
  signal s_hr_cmd_op, s_sd_cmd_op : unsigned(1 downto 0) := "00";
  signal s_hr_cmd_addr, s_sd_cmd_addr : unsigned(26 downto 0) := (others => '0');
  signal s_hr_cmd_len, s_sd_cmd_len : unsigned(8 downto 0) := (others => '0');
  signal s_hr_wdata, s_sd_wdata : unsigned(15 downto 0) := x"0000";
  signal s_hr_wdata_be, s_sd_wdata_be : std_logic_vector(1 downto 0) := "11";
  -- the coprocessor port
  signal own : std_logic;
  signal cop_start, cop_own, cop_abort, cop_done, cop_wr : std_logic := '0';
  signal cop_op, cop_err : unsigned(7 downto 0) := (others => '0');
  signal cop_ra, cop_rb, cop_rc, cop_rd, cop_z, cop_result : unsigned(31 downto 0) := (others => '0');
  signal cop_x : unsigned(27 downto 0) := (others => '0');
  signal map_hr_base, map_hr_size, map_sd_base, map_sd_size : unsigned(7 downto 0);
  -- the bridge <-> SHITE (clock81)
  signal b_start_t, b_abort, b_done_t, b_wr, b_g_t, b_g_write, b_g_sd, b_g_ack_t, b_g_err : std_logic := '0';
  signal b_op, b_err : unsigned(7 downto 0) := (others => '0');
  signal b_ra, b_rb, b_rc, b_rd, b_z, b_result : unsigned(31 downto 0) := (others => '0');
  signal b_x : unsigned(27 downto 0) := (others => '0');
  signal b_hr_base, b_hr_size, b_sd_base, b_sd_size : unsigned(7 downto 0) := (others => '0');
  signal b_g_addr : unsigned(26 downto 0) := (others => '0');
  signal b_g_wd, b_g_rd : unsigned(63 downto 0) := (others => '0');
  signal b_g_be : std_logic_vector(7 downto 0) := (others => '1');
begin

  core : entity work.ssnail
    generic map (has_sdram => has_sdram, has_llm => has_llm, has_cop => has_shite)
    port map (
      cpuclock => cpuclock, reset => reset, irq => irq, ssnail_cs => ssnail_cs,
      fastio_addr => fastio_addr, fastio_write => fastio_write, fastio_read => fastio_read,
      fastio_wdata => fastio_wdata, fastio_rdata => fastio_rdata,
      clock162 => clock162,
      hr_cmd_valid => n_hr_cmd_valid, hr_cmd_ready => n_hr_cmd_ready,
      hr_cmd_op => n_hr_cmd_op, hr_cmd_addr => n_hr_cmd_addr, hr_cmd_len => n_hr_cmd_len,
      hr_rdata => hr_rdata, hr_rdata_valid => n_hr_rdata_valid,
      hr_wdata_req => n_hr_wdata_req, hr_wdata => n_hr_wdata, hr_wdata_be => n_hr_wdata_be,
      hr_cmd_done => n_hr_cmd_done, hr_error => n_hr_error,
      sd_cmd_valid => n_sd_cmd_valid, sd_cmd_ready => n_sd_cmd_ready,
      sd_cmd_op => n_sd_cmd_op, sd_cmd_addr => n_sd_cmd_addr, sd_cmd_len => n_sd_cmd_len,
      sd_rdata => sd_rdata, sd_rdata_valid => n_sd_rdata_valid,
      sd_wdata_req => n_sd_wdata_req, sd_wdata => n_sd_wdata, sd_wdata_be => n_sd_wdata_be,
      sd_cmd_done => n_sd_cmd_done, sd_error => n_sd_error,
      cop_start => cop_start, cop_own => cop_own, cop_op => cop_op,
      cop_ra => cop_ra, cop_rb => cop_rb, cop_rc => cop_rc, cop_rd => cop_rd, cop_z => cop_z,
      cop_x => cop_x,
      cop_done => cop_done, cop_err => cop_err, cop_wr => cop_wr, cop_result => cop_result,
      cop_abort => cop_abort,
      map_hr_base => map_hr_base, map_hr_size => map_hr_size,
      map_sd_base => map_sd_base, map_sd_size => map_sd_size);

  shite_gen : if has_shite generate
    br : entity work.shite_bridge
      port map (
        clock162 => clock162,
        cop_start => cop_start, cop_op => cop_op,
        cop_ra => cop_ra, cop_rb => cop_rb, cop_rc => cop_rc, cop_rd => cop_rd, cop_z => cop_z,
        cop_x => cop_x, cop_abort => cop_abort,
        cop_done => cop_done, cop_err => cop_err, cop_wr => cop_wr, cop_result => cop_result,
        map_hr_base => map_hr_base, map_hr_size => map_hr_size,
        map_sd_base => map_sd_base, map_sd_size => map_sd_size,
        start_t => b_start_t, op => b_op, ra => b_ra, rb => b_rb, rc => b_rc, rd => b_rd,
        z => b_z, x => b_x, abort => b_abort,
        done_t => b_done_t, err => b_err, wr => b_wr, result => b_result,
        m_hr_base => b_hr_base, m_hr_size => b_hr_size, m_sd_base => b_sd_base, m_sd_size => b_sd_size,
        g_t => b_g_t, g_write => b_g_write, g_sd => b_g_sd, g_addr => b_g_addr,
        g_wd => b_g_wd, g_be => b_g_be, g_ack_t => b_g_ack_t, g_rd => b_g_rd, g_err => b_g_err,
        hr_cmd_valid => s_hr_cmd_valid, hr_cmd_ready => hr_cmd_ready,
        hr_cmd_op => s_hr_cmd_op, hr_cmd_addr => s_hr_cmd_addr, hr_cmd_len => s_hr_cmd_len,
        hr_rdata => hr_rdata, hr_rdata_valid => hr_rdata_valid,
        hr_wdata_req => hr_wdata_req, hr_wdata => s_hr_wdata, hr_wdata_be => s_hr_wdata_be,
        hr_cmd_done => hr_cmd_done, hr_error => hr_error,
        sd_cmd_valid => s_sd_cmd_valid, sd_cmd_ready => sd_cmd_ready,
        sd_cmd_op => s_sd_cmd_op, sd_cmd_addr => s_sd_cmd_addr, sd_cmd_len => s_sd_cmd_len,
        sd_rdata => sd_rdata, sd_rdata_valid => sd_rdata_valid,
        sd_wdata_req => sd_wdata_req, sd_wdata => s_sd_wdata, sd_wdata_be => s_sd_wdata_be,
        sd_cmd_done => sd_cmd_done, sd_error => sd_error);

    sh : entity work.shite
      port map (
        clock => clock81,
        start_t => b_start_t, op => b_op, ra => b_ra, rb => b_rb, rc => b_rc,
        rd => b_rd, z => b_z, x => b_x,
        abort => b_abort, done_t => b_done_t, err => b_err, wr => b_wr, result => b_result,
        map_hr_base => b_hr_base, map_hr_size => b_hr_size,
        map_sd_base => b_sd_base, map_sd_size => b_sd_size,
        g_t => b_g_t, g_write => b_g_write, g_sd => b_g_sd, g_addr => b_g_addr,
        g_wd => b_g_wd, g_be => b_g_be, g_ack_t => b_g_ack_t, g_rd => b_g_rd, g_err => b_g_err);
  end generate;

  -- The ports: SHITE's while SSNAIL has handed them over, else SSNAIL's.
  -- SSNAIL sees no responses meanwhile (it has nothing outstanding).
  -- Without SHITE all of this is wires (own is a constant 0).
  hr_cmd_valid <= s_hr_cmd_valid when own = '1' else n_hr_cmd_valid;
  hr_cmd_op    <= s_hr_cmd_op    when own = '1' else n_hr_cmd_op;
  hr_cmd_addr  <= s_hr_cmd_addr  when own = '1' else n_hr_cmd_addr;
  hr_cmd_len   <= s_hr_cmd_len   when own = '1' else n_hr_cmd_len;
  hr_wdata     <= s_hr_wdata     when own = '1' else n_hr_wdata;
  hr_wdata_be  <= s_hr_wdata_be  when own = '1' else n_hr_wdata_be;
  sd_cmd_valid <= s_sd_cmd_valid when own = '1' else n_sd_cmd_valid;
  sd_cmd_op    <= s_sd_cmd_op    when own = '1' else n_sd_cmd_op;
  sd_cmd_addr  <= s_sd_cmd_addr  when own = '1' else n_sd_cmd_addr;
  sd_cmd_len   <= s_sd_cmd_len   when own = '1' else n_sd_cmd_len;
  sd_wdata     <= s_sd_wdata     when own = '1' else n_sd_wdata;
  sd_wdata_be  <= s_sd_wdata_be  when own = '1' else n_sd_wdata_be;

  own <= cop_own when has_shite else '0';
  n_hr_cmd_ready   <= hr_cmd_ready   and not own;
  n_hr_rdata_valid <= hr_rdata_valid and not own;
  n_hr_wdata_req   <= hr_wdata_req   and not own;
  n_hr_cmd_done    <= hr_cmd_done    and not own;
  n_hr_error       <= hr_error       and not own;
  n_sd_cmd_ready   <= sd_cmd_ready   and not own;
  n_sd_rdata_valid <= sd_rdata_valid and not own;
  n_sd_wdata_req   <= sd_wdata_req   and not own;
  n_sd_cmd_done    <= sd_cmd_done    and not own;
  n_sd_error       <= sd_error       and not own;

end rtl;
