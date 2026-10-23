-- SHITE: Spreadsheet Hardware Integrated Technology Engine
--
-- SSNAIL's coprocessor for opcodes $40-$4F (see docs/shite/README.md and
-- the reference model SSNAIL/shite.py).  SSNAIL hands over its LUMP ports
-- for the length of an instruction (ssnail_top multiplexes them).
--
-- Every instruction is microcode: RECALC ($40), REBALANCE_ROW ($41),
-- FIND_CELL ($42), FORMAT_CELLS ($43), COMPILE ($44), DECOMPILE ($45),
-- RENDER ($46), PARSE ($47), MOVE_CELLS ($48), CELLS_MOVED ($49) (shite_useq,
-- shite_ucode.asm; docs/shite/MICROCODE.md).  This entity holds the engine,
-- the codec units (shite_formula_codec, shite_cell_text and the shared
-- shite_number_text), and a small state machine serving the engine's memory
-- requests and its jobs on the units.
-- Memory is reached one 8-byte group at a time.
--
-- Runs on sclock (40.5 MHz on the boards): shite_bridge (clock162) takes SSNAIL's coprocessor
-- port and issues the LUMP commands, the events crossing as toggles
-- (start_t, done_t, g_t, g_ack_t) with their data held meanwhile.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lumptypes.all;
use work.shite_codec_pkg.all;

entity shite is
  port (
    clock : in std_logic;                 -- sclock
    -- from SSNAIL's coprocessor port, through shite_bridge: held from
    -- start_t's change until done_t's
    start_t : in  std_logic;
    op     : in  unsigned(7 downto 0);
    ra     : in  unsigned(31 downto 0);
    rb     : in  unsigned(31 downto 0);
    rc     : in  unsigned(31 downto 0);   -- R[c bits 3-0]
    rd     : in  unsigned(31 downto 0);   -- R[c bits 7-4]
    z      : in  unsigned(31 downto 0);   -- the instruction's Z
    x      : in  unsigned(27 downto 0);
    abort  : in  std_logic;
    done_t : out std_logic := '0';
    err    : out unsigned(7 downto 0) := (others => '0');
    wr     : out std_logic := '0';
    result : out unsigned(31 downto 0) := (others => '0');
    map_hr_base, map_hr_size, map_sd_base, map_sd_size : in unsigned(7 downto 0);
    -- memory, one 8-byte group (shite_bridge issues it): the fields held
    -- from g_t's change until g_ack_t's, with the bytes read or the error
    g_t     : out std_logic := '0';
    g_write : out std_logic;
    g_sd    : out std_logic := '0';
    g_addr  : out unsigned(26 downto 0) := (others => '0');
    g_wd    : out unsigned(63 downto 0);
    g_be    : out std_logic_vector(7 downto 0);
    g_ack_t : in  std_logic;
    g_rd    : in  unsigned(63 downto 0);
    g_err   : in  std_logic
    );
end shite;

architecture rtl of shite is

  -- SSNAIL's error codes
  constant ERR_NONE      : unsigned(7 downto 0) := x"00";
  constant ERR_ADDRESS   : unsigned(7 downto 0) := x"02";
  constant ERR_READ      : unsigned(7 downto 0) := x"04";

  type state_t is (
    S_IDLE, S_FINISH,
    -- the microcode engine running the instruction (U_MACK: a job's end)
    U_RUN, U_MACK,
    -- memory primitives: one 8-byte group
    M_DEC, M_ISSUE, M_WAIT,
    -- a job on a codec unit (the microcode's), its RAM requests served
    SJ_WAIT, SJ_DONE, SJ_GAP
    );
  signal st, mem_ret, sj_ret : state_t := S_IDLE;

  -- the microcode engine (shite_useq): its start, end, memory
  signal u_start, u_done, u_wr, u_req_t, u_req_seen, u_ack_t, u_mwrite : std_logic := '0';
  signal u_err : unsigned(7 downto 0);
  signal u_res : unsigned(31 downto 0);
  signal u_maddr : unsigned(27 downto 0);
  signal u_mwd : unsigned(63 downto 0);
  signal u_mbe : std_logic_vector(7 downto 0);
  signal u_mjob, u_xwe : std_logic;
  signal u_xsel : unsigned(5 downto 0);
  signal u_xwd, u_xin : unsigned(63 downto 0);

  -- the instruction
  signal r_op : unsigned(7 downto 0) := (others => '0');
  signal r_a, r_b, r_c, r_d, r_z : unsigned(31 downto 0) := (others => '0');
  signal desc : unsigned(27 downto 0) := (others => '0');

  -- memory primitive: m_addr (8-aligned), m_write; m_rd / m_wd; m_be (bytes)
  signal m_addr : unsigned(27 downto 0) := (others => '0');
  signal m_write : std_logic := '0';
  signal m_rd, m_wd : unsigned(63 downto 0) := (others => '0');
  signal m_be : std_logic_vector(7 downto 0) := (others => '1');
  signal m_is_sd, m_ok : std_logic := '0';
  signal m_local : unsigned(26 downto 0) := (others => '0');
  -- the crossings' toggles, registered, and the last seen
  signal s_r, s_seen, a_r, a_seen, g_tr, done_tr : std_logic := '0';
  -- (the group's bytes and error, registered with a_r: a crossing from
  -- clock162 has one clock162 period, too short for M_WAIT's choice)
  signal g_rd_r : unsigned(63 downto 0) := (others => '0');
  signal g_err_r : std_logic := '0';
  signal abt : std_logic := '0';
  signal mp_hr_base, mp_hr_size, mp_sd_base, mp_sd_size : unsigned(7 downto 0) := (others => '0');

  -- The codec units
  signal co_start, ce_start, nu_start_self : std_logic := '0';
  signal co_decompile : std_logic := '0';
  signal co_source, co_dest, co_names : unsigned(27 downto 0) := (others => '0');
  signal co_len, co_cap : unsigned(15 downto 0) := (others => '0');
  signal co_row : unsigned(19 downto 0) := (others => '0');
  signal co_col : unsigned(23 downto 0) := (others => '0');
  signal co_dsep, co_asep : codec_byte := x"2E";
  signal co_busy, co_done, ce_busy, ce_done, nu_busy, nu_done : std_logic;
  signal co_error, ce_error, nu_error, co_hosts : codec_byte;
  signal co_epos, co_rlen, ce_rlen, nu_epos, nu_rlen : unsigned(15 downto 0);
  signal ce_colour : unsigned(3 downto 0);
  -- the cell renderer's job
  signal ce_kind : unsigned(3 downto 0) := (others => '0');
  signal ce_value, ce_format : unsigned(63 downto 0) := (others => '0');
  signal ce_text, ce_scratch, ce_dest : unsigned(27 downto 0) := (others => '0');
  signal ce_tlen, ce_cap : unsigned(15 downto 0) := (others => '0');
  signal ce_width : codec_byte := (others => '0');
  signal ce_upper : std_logic := '0';
  signal ce_ascii : std_logic := '0';
  signal ce_screen : std_logic;
  -- the shared number converter: its job from the codec, the renderer or
  -- the execution unit itself (PARSE)
  signal nu_start, nu_format, nu_negative, nu_kind, nu_display : std_logic;
  signal nu_source, nu_dest : unsigned(27 downto 0);
  signal nu_len, nu_cap : unsigned(15 downto 0);
  signal nu_value : unsigned(63 downto 0);
  signal nu_scale, nu_dsep, nu_decimals, nu_width : codec_byte;
  signal nu_style : unsigned(3 downto 0);
  signal nu_rvalue : unsigned(63 downto 0);
  signal nu_rkind : std_logic;
  signal nu_rscale : codec_byte;
  -- the codec's and renderer's requests to the converter
  signal cn_start, cn_format, cn_negative, cn_kind : std_logic;
  signal cn_source, cn_dest : unsigned(27 downto 0);
  signal cn_len, cn_cap : unsigned(15 downto 0);
  signal cn_value : unsigned(63 downto 0);
  signal cn_scale, cn_dsep : codec_byte;
  signal en_start, en_kind : std_logic;
  signal en_value : unsigned(63 downto 0);
  signal en_scale, en_dsep, en_decimals, en_width : codec_byte;
  signal en_dest : unsigned(27 downto 0);
  signal en_style : unsigned(3 downto 0);
  signal sf_source : unsigned(27 downto 0) := (others => '0');   -- PARSE's text
  signal sf_len : unsigned(15 downto 0) := (others => '0');
  -- which client asked the converter: 0 the codec, 1 the renderer, 2 PARSE
  signal nu_client : unsigned(1 downto 0) := "00";
  signal x_job : unsigned(1 downto 0) := "00";      -- 0 codec, 1 renderer, 2 PARSE
  signal x_unit_abort : std_logic := '0';
  -- their RAM requests (held valid until ready)
  signal co_rv, co_rw, ce_rv, ce_rw, nu_rv, nu_rw : std_logic;
  signal co_ra, ce_ra, nu_ra : unsigned(27 downto 0);
  signal co_wd, ce_wd, nu_wd : unsigned(63 downto 0);
  signal co_be, ce_be, nu_be : std_logic_vector(7 downto 0);
  signal co_rdy, ce_rdy, nu_rdy, sj_rerr : std_logic := '0';
  signal sj_rdata : unsigned(63 downto 0) := (others => '0');
  signal sj_who : unsigned(1 downto 0) := "00";     -- 0 codec, 1 renderer, 2 converter
  signal sj_mode : boolean := false;                -- memory faults go to the unit
  signal sj_fault : boolean := false;
  signal sj_seen_done : boolean := false;

begin
  ce_screen <= not ce_ascii;

  -- The microcode engine
  useq : entity work.shite_useq
    port map (
      clock => clock, start => u_start,
      i_op => r_op, i_a => r_a, i_b => r_b, i_c => r_c, i_d => r_d, i_z => r_z, i_x => desc,
      abort => abt,
      done => u_done, err => u_err, wr => u_wr, result => u_res,
      req_t => u_req_t, m_job => u_mjob, m_write => u_mwrite, m_addr => u_maddr, m_wd => u_mwd,
      m_be => u_mbe, ack_t => u_ack_t, m_rd => m_rd,
      x_we => u_xwe, x_sel => u_xsel, x_wd => u_xwd, x_in => u_xin);

  -- its reads of the codec units' results (IN; the ports' numbers are the
  -- microcode's I_ names)
  with to_integer(u_xsel) select u_xin <=
    resize(co_error, 64) when 0,
    resize(co_rlen, 64) when 1,
    resize(co_epos, 64) when 2,
    resize(co_hosts, 64) when 3,
    resize(ce_error, 64) when 4,
    resize(ce_colour, 64) when 5,
    resize(nu_error, 64) when 6,
    nu_rvalue when 7,
    (63 downto 1 => '0') & nu_rkind when 8,
    resize(nu_rscale, 64) when 9,
    (others => '0') when others;

  -- The codec units (their RAM through the adapter below, SJ_)
  codec : entity work.shite_formula_codec
    port map (
      clock => clock, reset => '0', start => co_start, decompile => co_decompile,
      abort => x_unit_abort,
      source => co_source, destination => co_dest, names => co_names,
      source_length => co_len, output_capacity => co_cap,
      formula_row => co_row, formula_column => co_col,
      decimal_separator => co_dsep, argument_separator => co_asep,
      busy => co_busy, done => co_done, error => co_error, error_position => co_epos,
      result_length => co_rlen, host_calls => co_hosts,
      ram_valid => co_rv, ram_write => co_rw, ram_address => co_ra, ram_wdata => co_wd,
      ram_byte_enable => co_be, ram_ready => co_rdy, ram_error => sj_rerr, ram_rdata => sj_rdata,
      number_start => cn_start, number_format => cn_format, number_negative => cn_negative,
      number_source => cn_source, number_destination => cn_dest,
      number_length => cn_len, number_capacity => cn_cap,
      number_value => cn_value, number_kind => cn_kind, number_scale => cn_scale,
      number_decimal_separator => cn_dsep,
      number_done => nu_done, number_error => nu_error,
      number_error_position => nu_epos, number_result_length => nu_rlen,
      number_result_value => nu_rvalue, number_result_kind => nu_rkind,
      number_result_scale => nu_rscale);

  renderer : entity work.shite_cell_text
    port map (
      clock => clock, reset => '0', start => ce_start, abort => x_unit_abort,
      kind => ce_kind, value => ce_value, cell_format => ce_format,
      text_source => ce_text, scratch => ce_scratch, destination => ce_dest,
      text_length => ce_tlen, capacity => ce_cap,
      width => ce_width, decimal_separator => co_dsep,
      screen_codes => ce_screen, upper_case => ce_upper,
      busy => ce_busy, done => ce_done, error => ce_error, result_length => ce_rlen,
      colour => ce_colour,
      ram_valid => ce_rv, ram_write => ce_rw, ram_address => ce_ra, ram_wdata => ce_wd,
      ram_byte_enable => ce_be, ram_ready => ce_rdy, ram_error => sj_rerr, ram_rdata => sj_rdata,
      number_start => en_start, number_value => en_value, number_kind => en_kind,
      number_scale => en_scale, number_decimal_separator => en_dsep,
      number_destination => en_dest, number_style => en_style,
      number_decimals => en_decimals, number_width => en_width,
      number_done => nu_done, number_error => nu_error, number_result_length => nu_rlen);

  -- the converter's job: from whichever client is asking (one at a time)
  nu_start <= cn_start or en_start or nu_start_self;
  converter_job : process (nu_client, cn_format, cn_negative, cn_source, cn_dest, cn_len, cn_cap,
                           cn_value, cn_kind, cn_scale, cn_dsep, en_value, en_kind, en_scale, en_dsep,
                           en_dest, en_style, en_decimals, en_width, sf_source, sf_len, co_dsep)
  begin
    -- (the codec's)
    nu_format <= cn_format; nu_negative <= cn_negative; nu_source <= cn_source; nu_dest <= cn_dest;
    nu_len <= cn_len; nu_cap <= cn_cap; nu_value <= cn_value; nu_kind <= cn_kind; nu_scale <= cn_scale;
    nu_dsep <= cn_dsep; nu_display <= '0'; nu_style <= x"0"; nu_decimals <= x"02"; nu_width <= x"FF";
    if nu_client = "01" then                  -- the renderer: display text, 512 bytes of scratch
      nu_format <= '1'; nu_negative <= '0'; nu_source <= (others => '0'); nu_dest <= en_dest;
      nu_len <= (others => '0'); nu_cap <= to_unsigned(512, 16); nu_value <= en_value;
      nu_kind <= en_kind; nu_scale <= en_scale; nu_dsep <= en_dsep; nu_display <= '1';
      nu_style <= en_style; nu_decimals <= en_decimals; nu_width <= en_width;
    elsif nu_client = "10" then               -- PARSE: the literal
      nu_format <= '0'; nu_negative <= '0'; nu_source <= sf_source; nu_dest <= (others => '0');
      nu_len <= sf_len; nu_cap <= (others => '0'); nu_value <= (others => '0'); nu_kind <= '0';
      nu_scale <= (others => '0'); nu_dsep <= co_dsep;
    end if;
  end process;

  converter : entity work.shite_number_text
    port map (
      clock => clock, reset => '0', start => nu_start, format => nu_format, negative => nu_negative,
      source => nu_source, destination => nu_dest, input_length => nu_len, capacity => nu_cap,
      value => nu_value, kind => nu_kind, scale => nu_scale, decimal_separator => nu_dsep,
      display => nu_display, display_style => nu_style, display_decimals => nu_decimals,
      display_width => nu_width,
      busy => nu_busy, done => nu_done, error => nu_error, error_position => nu_epos,
      result_length => nu_rlen, result_value => nu_rvalue, result_kind => nu_rkind,
      result_scale => nu_rscale, abort => x_unit_abort,
      ram_valid => nu_rv, ram_write => nu_rw, ram_address => nu_ra, ram_wdata => nu_wd,
      ram_byte_enable => nu_be, ram_ready => nu_rdy, ram_error => sj_rerr, ram_rdata => sj_rdata);

  g_t <= g_tr;
  done_t <= done_tr;
  g_write <= m_write; g_wd <= m_wd; g_be <= m_be;

  process (clock)
    variable mb : unsigned(7 downto 0);

    procedure mem_read(a : unsigned(27 downto 0); ret : state_t) is
    begin
      m_addr <= a(27 downto 3) & "000"; m_write <= '0'; mem_ret <= ret; st <= M_DEC;
    end procedure;
    procedure mem_write(a : unsigned(27 downto 0); d : unsigned(63 downto 0);
                        be : std_logic_vector(7 downto 0); ret : state_t) is
    begin
      m_addr <= a(27 downto 3) & "000"; m_write <= '1'; m_wd <= d; m_be <= be;
      mem_ret <= ret; st <= M_DEC;
    end procedure;
    procedure fault(code : unsigned(7 downto 0)) is
    begin
      err <= code; st <= S_FINISH;
    end procedure;
  begin
    if rising_edge(clock) then
      -- (from clock162: registered before any use)
      s_r <= start_t; a_r <= g_ack_t; abt <= abort;
      g_rd_r <= g_rd; g_err_r <= g_err;
      mp_hr_base <= map_hr_base; mp_hr_size <= map_hr_size;
      mp_sd_base <= map_sd_base; mp_sd_size <= map_sd_size;

      -- the memory map (SSNAIL's), a cycle after m_addr
      mb := m_addr(27 downto 20);
      if mb >= mp_hr_base and resize(mb, 9) < resize(mp_hr_base, 9) + resize(mp_hr_size, 9) then
        m_ok <= '1'; m_is_sd <= '0';
        m_local <= resize(mb - mp_hr_base, 7) & m_addr(19 downto 0);
      elsif mb >= mp_sd_base and resize(mb, 9) < resize(mp_sd_base, 9) + resize(mp_sd_size, 9) then
        m_ok <= '1'; m_is_sd <= '1';
        m_local <= resize(mb - mp_sd_base, 7) & m_addr(19 downto 0);
      else
        m_ok <= '0';
      end if;

      u_start <= '0';

      -- the codec units: one-cycle pulses, and their jobs' ends latched
      co_start <= '0'; ce_start <= '0'; nu_start_self <= '0';
      co_rdy <= '0'; ce_rdy <= '0'; nu_rdy <= '0'; sj_rerr <= '0';
      if (x_job = "00" and co_done = '1') or (x_job = "01" and ce_done = '1')
        or (x_job = "10" and nu_done = '1') then
        sj_seen_done <= true;
      end if;
      x_unit_abort <= abt;
      if u_xwe = '1' then
        case to_integer(u_xsel) is
          when 0 => co_source <= u_xwd(27 downto 0);
          when 1 => co_len <= u_xwd(15 downto 0);
          when 2 => co_cap <= u_xwd(15 downto 0);
          when 3 => co_row <= u_xwd(19 downto 0);
          when 4 => co_col <= u_xwd(23 downto 0);
          when 5 => co_dest <= u_xwd(27 downto 0);
          when 6 => co_decompile <= u_xwd(0);
          when 7 => co_names <= u_xwd(27 downto 0);
          when 8 => co_dsep <= u_xwd(7 downto 0);
          when 9 => co_asep <= u_xwd(7 downto 0);
          when 10 => ce_kind <= u_xwd(3 downto 0);
          when 11 => ce_format <= u_xwd;
          when 12 => ce_width <= u_xwd(7 downto 0);
          when 13 => ce_upper <= u_xwd(0);
          when 14 => ce_value <= u_xwd;
          when 15 => ce_text <= u_xwd(27 downto 0);
          when 16 => ce_tlen <= u_xwd(15 downto 0);
          when 17 => ce_dest <= u_xwd(27 downto 0);
          when 18 => ce_scratch <= u_xwd(27 downto 0);
          when 19 => ce_cap <= u_xwd(15 downto 0);
          when 20 => sf_source <= u_xwd(27 downto 0);
          when 21 => sf_len <= u_xwd(15 downto 0);
          when 22 => ce_ascii <= u_xwd(0);
          when others => null;
        end case;
      end if;

      case st is
        when S_IDLE =>
          if s_r /= s_seen then
            s_seen <= s_r;
            err <= ERR_NONE; wr <= '0';
            r_op <= op; r_a <= ra; r_b <= rb; r_c <= rc; r_d <= rd; r_z <= z; desc <= x;
            u_start <= '1'; st <= U_RUN;            -- (the microcode's)
            u_req_seen <= u_req_t;
          end if;

        when S_FINISH =>
          done_tr <= not done_tr;
          st <= S_IDLE;

        -- the microcode engine: its memory requests, its end
        when U_RUN =>
          if u_req_t /= u_req_seen then
            u_req_seen <= u_req_t;
            if u_mjob = '1' then                    -- a job on unit u_maddr(1:0)
              sj_seen_done <= false; sj_mode <= true; sj_ret <= U_MACK;
              st <= SJ_WAIT;
              case u_maddr(1 downto 0) is
                when "00" => x_job <= "00"; nu_client <= "00"; co_start <= '1';
                when "01" => x_job <= "01"; nu_client <= "01"; ce_start <= '1';
                when others => x_job <= "10"; nu_client <= "10"; nu_start_self <= '1';
              end case;
            elsif u_mwrite = '1' then
              mem_write(u_maddr, u_mwd, u_mbe, U_RUN);
            else
              mem_read(u_maddr, U_RUN);
            end if;
          elsif u_done = '1' then
            err <= u_err; wr <= u_wr;
            if u_wr = '1' then result <= u_res; end if;
            st <= S_FINISH;
          end if;
        when U_MACK =>
          sj_mode <= false;
          u_ack_t <= not u_ack_t; st <= U_RUN;

        when M_DEC =>
          st <= M_ISSUE;                    -- (the map decodes m_addr now)
        when M_ISSUE =>
          if m_ok = '0' and sj_mode then
            sj_fault <= true; st <= mem_ret;      -- (to the unit: ram_error)
          elsif m_ok = '0' then
            fault(ERR_ADDRESS);
          else
            g_sd <= m_is_sd; g_addr <= m_local; g_tr <= not g_tr;
            st <= M_WAIT;
          end if;
        when M_WAIT =>
          if a_r /= a_seen then
            a_seen <= a_r;
            if g_err_r = '1' then
              if sj_mode then sj_fault <= true; st <= mem_ret; else fault(ERR_READ); end if;
            else
              m_rd <= g_rd_r;
              st <= mem_ret;
              if mem_ret = U_RUN then u_ack_t <= not u_ack_t; end if;   -- (the engine's)
            end if;
          end if;

        -- the units' RAM: whichever holds ram_valid (one at a time) gets one
        -- eight-byte transaction; ready (and ram_error) back for one cycle
        when SJ_WAIT =>
          sj_fault <= false;
          if sj_seen_done then
            st <= sj_ret;
          elsif nu_rv = '1' then
            sj_who <= "10";
            if nu_rw = '1' then mem_write(nu_ra, nu_wd, nu_be, SJ_DONE); else mem_read(nu_ra, SJ_DONE); end if;
          elsif co_rv = '1' then
            sj_who <= "00";
            if co_rw = '1' then mem_write(co_ra, co_wd, co_be, SJ_DONE); else mem_read(co_ra, SJ_DONE); end if;
          elsif ce_rv = '1' then
            sj_who <= "01";
            if ce_rw = '1' then mem_write(ce_ra, ce_wd, ce_be, SJ_DONE); else mem_read(ce_ra, SJ_DONE); end if;
          end if;
        when SJ_DONE =>
          sj_rdata <= m_rd;
          if sj_fault then sj_rerr <= '1'; end if;
          case sj_who is
            when "00" => co_rdy <= '1';
            when "01" => ce_rdy <= '1';
            when others => nu_rdy <= '1';
          end case;
          st <= SJ_GAP;
        when SJ_GAP =>                          -- (the unit sees ready now, and moves on)
          st <= SJ_WAIT;

        when others =>
          st <= S_IDLE;
      end case;
    end if;
  end process;

end rtl;
