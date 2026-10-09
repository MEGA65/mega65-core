library IEEE;
use IEEE.STD_LOGIC_1164.all;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;
use work.lumptypes.all;

entity sdram_controller is
  generic (in_simulation : in boolean := false);
  port (pixelclock : in std_logic;      -- For slow devices bus interface is
        -- actually on pixelclock to reduce latencies
        -- Also pixelclock is the natural clock speed we apply to the HyperRAM.
        clock162   : in std_logic;      -- Used for fast clock for SDRAM

        clock162r  : in std_logic;      -- read register clock

        identical_clocks : in std_logic;

        -- Read capture training.  clock162r comes from an MMCM of its own,
        -- whose phase relative to clock162 is different after every lock, so
        -- after initialisation the controller sweeps clock162r through a
        -- whole cycle with the MMCM's dynamic fine phase shift (PSCLK =
        -- clock162), finds the widest window of clean reads and centres it.
        -- Leave ps_done unconnected ('0') if there is no phase shifter: the
        -- training then stops at once and nothing changes.
        ps_en     : out std_logic := '0';
        ps_incdec : out std_logic := '1';
        ps_done   : in  std_logic := '0';
        -- That MMCM's LOCKED (asynchronous): training waits for it, as
        -- phase steps before lock can leave the phase shifter unresponsive
        ps_locked : in  std_logic := '1';

        -- Option to ignore 100usec initialisation sequence for SDRAM (to
        -- speed up simulation)
        enforce_100us_delay : in boolean := true;

        -- Simple counter for number of requests received
        request_counter : out std_logic := '0';

        read_request  : in std_logic;
        write_request : in std_logic;
        address       : in unsigned(26 downto 0);
        wdata         : in unsigned(7 downto 0);

        -- Optional 16-bit interface (for Amiga core use)
        -- (That it is optional, is why the write_en is inverted for the
        -- low-byte).
        -- 16-bit transactions MUST occur on an even numbered address, or
        -- else expect odd and horrible things to happen.
        wdata_hi   : in  unsigned(7 downto 0) := x"00";
        wen_hi     : in  std_logic            := '0';
        wen_lo     : in  std_logic            := '1';
        rdata_hi   : out unsigned(7 downto 0);
        rdata_16en : in  std_logic            := '0';  -- set this high to be able
                                                       -- to read 16-bit values

        rdata : out unsigned(7 downto 0);

        data_ready_toggle : out std_logic := '0';

        -- Starts busy until SDRAM is initialised
        busy : out std_logic := '1';

        -- Export current cache line for speeding up reads from slow_devices controller
        -- by skipping the need to hand us the request and get the response back.
        current_cache_line                          : out   cache_row_t           := (others => (others => '0'));
        current_cache_line_address                  : inout unsigned(26 downto 3) := (others => '0');
        current_cache_line_valid                    : out   std_logic             := '0';
        expansionram_current_cache_line_next_toggle : in    std_logic             := '0';
        expansionram_current_cache_line_prev_toggle : in    std_logic             := '0';

        -- Allow VIC-IV to request lines of data also.
        -- We then pump it out byte-by-byte when ready
        -- VIC-IV can address only 512KB at a time, so we have a banking register
        viciv_addr           : in  unsigned(18 downto 3) := (others => '0');
        viciv_request_toggle : in  std_logic             := '0';
        viciv_data_out       : out unsigned(7 downto 0)  := x"00";
        viciv_data_strobe    : out std_logic             := '0';

        -- LUMP (Linear Uncomplicated Memory Port) for SSNAIL.
        -- Clocked by clock162.  See lump_queue.vhdl for the contract.
        -- Addresses are local to this SDRAM (bit 26 is ignored).
        lump_cmd_valid   : in  std_logic             := '0';
        lump_cmd_ready   : out std_logic             := '1';
        lump_cmd_op      : in  unsigned(1 downto 0)  := "00";
        lump_cmd_addr    : in  unsigned(26 downto 0) := (others => '0');
        lump_cmd_len     : in  unsigned(8 downto 0)  := (others => '0');
        lump_rdata       : out unsigned(15 downto 0) := x"0000";
        lump_rdata_valid : out std_logic             := '0';
        lump_wdata_req   : out std_logic             := '0';
        lump_wdata       : in  unsigned(15 downto 0) := x"0000";
        lump_wdata_be    : in  std_logic_vector(1 downto 0) := "11";
        lump_cmd_done    : out std_logic             := '0';
        lump_error       : out std_logic             := '0';
        lump_idle        : out std_logic             := '1';

        -- SDRAM interface (e.g. AS4C16M16SA-6TCN, IS42S16400F, etc.)
        sdram_a     : out   unsigned(12 downto 0);
        sdram_ba    : out   unsigned(1 downto 0);
        sdram_dq    : inout unsigned(15 downto 0);
        sdram_cke   : out   std_logic := '1';
        sdram_cs_n  : out   std_logic := '0';
        sdram_ras_n : out   std_logic;
        sdram_cas_n : out   std_logic;
        sdram_we_n  : out   std_logic;
        sdram_dqml  : out   std_logic;
        sdram_dqmh  : out   std_logic

        );
end sdram_controller;

architecture tacoma_narrows of sdram_controller is

  signal last_data_ready_toggle : std_logic := '0';

  -- Run the SDRAM init sequence at power-on (after the 100us delay); the
  -- read capture training follows at its end.  (Was '1', skipping init,
  -- while debugging power-up problems that were probably the untrained
  -- read capture clock.)
  signal sdram_prepped         : std_logic             := '0';
  -- The SDRAM requires a 100us setup time
  signal sdram_100us_countdown : integer               := 16_200;
  signal sdram_do_init         : std_logic             := '1';
  signal sdram_init_phase      : integer range 0 to 63 := 0;

  type sdram_cmd_t is (CMD_NOP, CMD_SET_MODE_REG,
                       CMD_PRECHARGE,
                       CMD_AUTO_REFRESH,
                       CMD_ACTIVATE_ROW,
                       CMD_READ,
                       CMD_WRITE,
                       CMD_STOP
                       );

  -- Initialisation sequence required for SDRAM according to
  -- the "INITIALIZE AND LOAD MODE REGISTER" section of the
  -- datasheet.
  type sdram_init_t is array (0 to 31) of sdram_cmd_t;
  signal init_cmds : sdram_init_t := (
    2      => CMD_PRECHARGE,
    6      => CMD_AUTO_REFRESH,
    16     => CMD_AUTO_REFRESH,
    30     => CMD_SET_MODE_REG,
    others => CMD_NOP);

  -- SDRAM state machine.  IDLE must be the last in the list,
  -- so that the shallow auto-progression logic can progress
  -- through.
  type sdram_state_t is (CLOSE_AND_SWITCH_ROW,
                         CLOSE_AND_SWITCH_ROW_2,
                         CLOSE_AND_SWITCH_ROW_3,
                         CLOSE_AND_SWITCH_ROW_4,
                         ACTIVATE_WAIT,
                         ACTIVATE_WAIT_1,
                         ACTIVATE_WAIT_2,
                         READ_WAIT,
                         READ_WAIT_2,
                         READ_WAIT_3,
                         READ_WAIT_4,
                         READ_WAIT_5,
                         READ_0,
                         READ_1,
                         READ_2,
                         READ_3,
                         READ_4,
                         WRITE_1,
                         WRITE_2,
                         CLOSE_FOR_REFRESH,
                         CLOSE_FOR_REFRESH_2,
                         CLOSE_FOR_REFRESH_3,
                         CLOSE_FOR_REFRESH_4,
                         REFRESH_1,
                         REFRESH_2,
                         REFRESH_3,
                         REFRESH_4,
                         REFRESH_5,
                         REFRESH_6,
                         REFRESH_7,
                         REFRESH_8,
                         REFRESH_9,
                         NON_RAM_READ,
                         -- LUMP states.  These always set sdram_state
                         -- explicitly, so their position here only matters
                         -- in that they must come before IDLE.
                         LUMP_PRECHARGE,
                         LUMP_ACTIVATE,
                         LUMP_READ,
                         LUMP_READ_DRAIN,
                         LUMP_WRITE,
                         LUMP_WRITE_RECOVER,
                         TRAIN,
                         IDLE);
  signal sdram_state : sdram_state_t := IDLE;

  signal rdata_line       : unsigned(63 downto 0);
  signal latched_addr     : unsigned(26 downto 0);
  signal rdata_buf        : unsigned(7 downto 0);
  signal rdata_hi_buf     : unsigned(7 downto 0);
  signal read_latched     : std_logic := '0';
  signal write_latched    : std_logic := '0';
  signal wdata_latched    : unsigned(7 downto 0);
  signal wdata_hi_latched : unsigned(7 downto 0);
  signal latched_wen_lo   : std_logic := '0';
  signal latched_wen_hi   : std_logic := '0';

  signal read_jobs  : unsigned(7 downto 0) := to_unsigned(0, 8);
  signal write_jobs : unsigned(7 downto 0) := to_unsigned(0, 8);

  signal nonram_val : unsigned(7 downto 0);

  signal reactive_cache_line_if_safe  : std_logic := '0';
  signal write_targets_cache_line     : std_logic := '0';
  signal current_cache_line_valid_int : std_logic := '0';
  signal sdram_dq_latched             : unsigned(15 downto 0);

  signal next_toggle_drive : std_logic := '0';
  signal prev_toggle_drive : std_logic := '0';

  signal prev_current_cache_line_next_toggle : std_logic := '0';
  signal prev_current_cache_line_prev_toggle : std_logic := '0';
  signal cache_line_prev_address             : unsigned(26 downto 3);
  signal cache_line_next_address             : unsigned(26 downto 3);
  signal silent_read                         : std_logic := '0';

  -- 8K refreshes required every 64ms.
  -- ie one every 7.812 usec
  -- We have 162 clock cycles per usec, so one refresh every
  -- 1,265 cycles is required.
  constant refresh_interval    : integer   := 1265;
  signal refresh_due           : std_logic := '0';
  signal refresh_due_countdown : integer   := refresh_interval - 1;

  signal read_complete_strobe : std_logic              := '0';
  signal read_publish_strobe  : std_logic              := '0';
  signal active_row           : std_logic              := '0';
  signal active_row_addr      : unsigned(25 downto 11) := (others => '0');

  signal resets : unsigned(7 downto 0) := x"00";

  signal sdram_dq_out : unsigned(15 downto 0);
  signal sdram_dq_oe_n : std_logic_vector(15 downto 0);

  -- LUMP port state
  signal lump_q_valid  : std_logic := '0';
  signal lump_q_op     : unsigned(1 downto 0) := "00";
  signal lump_q_addr   : unsigned(26 downto 0) := (others => '0');
  signal lump_q_len    : unsigned(8 downto 0) := (others => '0');
  signal lump_q_pop    : std_logic := '0';
  signal lump_active   : std_logic := '0';
  signal lump_is_write : std_logic := '0';
  signal lump_bank     : unsigned(1 downto 0) := "00";
  signal lump_row      : unsigned(12 downto 0) := (others => '0');
  -- Word column (address bits 10 downto 1) of the next READ/WRITE command
  signal lump_col      : unsigned(9 downto 0) := (others => '0');
  -- Number of READ (4-word) or WRITE (1-word) commands still to issue,
  -- minus two.  Goes negative exactly on the last command, so the sign bit is
  -- the "last" flag with no compare logic.
  signal lump_cnt      : signed(8 downto 0) := (others => '1');
  signal lump_wait     : integer range 0 to 7 := 0;
  signal lump_phase    : unsigned(1 downto 0) := "00";
  -- Write data requests still to make, minus one: requests are issued
  -- while the sign bit is clear.
  signal lump_wreq_cnt : signed(8 downto 0) := (others => '1');
  -- Pre-registered dispatch decisions and set-up values for IDLE
  signal lump_go        : std_logic := '0';  -- READ/WRITE at queue head
  signal lump_inv_go    : std_logic := '0';  -- INVALIDATE at queue head
  signal lump_row_match : std_logic := '0';  -- head is in the open row
  signal lump_is_write_pre : std_logic := '0';
  signal lump_cnt_init  : signed(8 downto 0) := (others => '1');
  -- Read data capture pipeline: bit k set => a READ was issued k+1 cycles ago
  signal lump_rd_pipe  : std_logic_vector(0 to 8) := (others => '0');
  signal lump_rd_issue : std_logic := '0';

  -- The one place read data crosses from clock162r to clock162.  Both the
  -- CPU line fill and LUMP read from here, so they can never disagree.
  signal dq_x          : unsigned(15 downto 0) := (others => '0');
  -- Read data cycle: words are taken from dq_x at T+7-rd_c .. T+10-rd_c
  -- after a READ at T.  Set by training; until training succeeds (or with
  -- no phase shifter) it is 0 or 1 from identical_clocks ($D7FE bit 5), the
  -- old behaviour plus the dq_x stage.
  signal rd_c          : unsigned(1 downto 0) := "00";
  signal trained_c     : unsigned(1 downto 0) := "00";
  -- dq_x takes the data either straight from sdram_dq_latched (h = 0) or
  -- via dq_f on the falling edge of clock162 (h = 1).  That moves the point
  -- where a clock162r edge is too close to a clock162 edge by half a cycle.
  signal dq_f          : unsigned(15 downto 0) := (others => '0');
  signal x_h           : std_logic := '0';
  signal trained_h     : std_logic := '0';

  -- Training.  Test words live at the top 8 bytes of the SDRAM
  -- (bank 3, last row, word columns 1020-1023).
  --
  -- 1. Coarse: 8 phases, 45 degrees (35 fine steps) apart.  At each, one
  --    READ (done twice, results must agree) captures 7 words around the
  --    burst from both crossing paths, and finds where the 4-word pattern
  --    sits: that gives the read cycle for each path, or "not clean".
  -- 2. The longest run of clean coarse phases (either path) is the window.
  -- 3. Fine: step out from its first and last coarse phase one fine step at
  --    a time to find the exact edges, and take the middle.
  -- 4. Path: test the middle and a quarter-window either side; use the path
  --    whose cycle is the same at all three (direct path preferred), so the
  --    phase is well away from that path's crossing point.
  constant TR_STEPS    : integer := 280;   -- fine steps per clock162 cycle
                                           -- (VCO 810 MHz / 5, 1/56 VCO each)
  constant TR_COARSE   : integer := 35;    -- fine steps per coarse step
  constant TR_PATTERN  : unsigned(63 downto 0) := x"3CA5C35AA53C5AC3";
  type tr_state_t is (T_START, T_PROBED, T_OPENED, T_SAVED, T_SAVE_READ,
                      T_WRITTEN, T_CO_TEST, T_CO_REC, T_CO_NEXT,
                      T_RUN, T_RUN_DONE,
                      T_FL_STEP, T_FL_T, T_FL_REC, T_FR_GO, T_FR_STEP, T_FR_T, T_FR_REC,
                      T_MID, T_MID2, T_MID3, T_PATH_GO, T_PATH_T, T_PATH_REC, T_PATH_PICK,
                      T_RESTORE, T_RESTORE_W, T_FINISH, T_ABORT,
                      T_TEST0, T_TEST1, T_TEST2, T_TEST3,
                      M_PS, M_PSW, M_WAIT, M_RWAIT, M_WRITE,
                      M_SEEK, M_SEEK2, M_STEPN);
  signal tr_st         : tr_state_t := T_START;
  signal tr_ret        : tr_state_t := T_START;   -- micro-ops
  signal tr_ret_n      : tr_state_t := T_START;   -- M_STEPN / M_SEEK
  signal tr_ret_t      : tr_state_t := T_START;   -- the test sequence
  signal tr_req        : std_logic := '0';   -- train after init
  signal tr_mode       : unsigned(1 downto 0) := "00"; -- 0 train, 1 +1, 2 -1
  signal tr_active     : std_logic := '0';
  signal tr_ok         : std_logic := '0';   -- last training found a window
  signal tr_weak       : std_logic := '0';   -- narrow, or no stable path
  signal tr_no_ps      : std_logic := '0';   -- no phase shifter answered
  signal ps_locked_s1, ps_locked_s2 : std_logic := '0';  -- synchroniser
  signal tr_count      : unsigned(7 downto 0) := x"00";
  signal tr_dec        : std_logic := '0';
  signal tr_to         : integer range 0 to 127 := 0;
  signal tr_cnt        : integer range 0 to 15 := 0;
  signal tr_k          : integer range 0 to 15 := 0;
  signal tr_r          : std_logic := '0';
  signal tr_wi         : integer range 0 to 3 := 0;
  signal tr_restore    : std_logic := '0';
  signal tr_had_ok     : std_logic := '0';
  signal tr_saved      : unsigned(63 downto 0) := (others => '0');
  -- 7 captured words per path: word i = the value at edge T+3+i
  signal wa, wb        : unsigned(111 downto 0) := (others => '0');
  -- Test results (both reads agreed): clean, and the read cycle
  signal t_va, t_vb    : std_logic := '0';
  signal t_ca, t_cb    : unsigned(1 downto 0) := "00";
  signal r1_va, r1_vb  : std_logic := '0';
  signal r1_ca, r1_cb  : unsigned(1 downto 0) := "00";
  signal tr_pos        : integer range 0 to TR_STEPS-1 := 0;
  signal tr_n          : integer range 0 to TR_STEPS := 0;
  signal tr_ndec       : std_logic := '0';
  signal tr_target     : integer range 0 to TR_STEPS-1 := 0;
  signal tr_delta      : integer range -TR_STEPS to TR_STEPS := 0;
  signal tr_p          : integer range 0 to 8 := 0;
  type cmap_t is array (0 to 7) of unsigned(7 downto 0);
  -- Coarse results: bit 2 path 0 clean, 1-0 its cycle; bit 6 path 1 clean,
  -- 5-4 its cycle
  signal cmap          : cmap_t := (others => x"00");
  signal tr_i          : integer range 0 to 16 := 0;
  signal tr_run        : integer range 0 to 8 := 0;
  signal tr_rs, tr_bs  : integer range 0 to 7 := 0;
  signal tr_bl         : integer range 0 to 8 := 0;
  signal tr_fc         : integer range 0 to TR_COARSE := 0;
  signal tr_left       : integer range 0 to TR_STEPS-1 := 0;
  signal tr_right      : integer range 0 to TR_STEPS-1 := 0;
  signal tr_width      : integer range 0 to TR_STEPS := 0;
  signal tr_centre     : integer range 0 to TR_STEPS-1 := 0;
  signal tr_qd         : integer range 0 to TR_STEPS/4 := 0;
  signal tr_q          : integer range 0 to 3 := 0;
  signal pa_ok, pb_ok  : std_logic := '0';
  signal pa_c, pb_c    : unsigned(1 downto 0) := "00";
  signal cen_va, cen_vb : std_logic := '0';
  signal cen_ca, cen_cb : unsigned(1 downto 0) := "00";

  -- Where the pattern starts in 7 captured words: j = 0..3, or 7 if not
  -- there.  (The 4 words are all different, so at most one j matches.)
  function tr_find(w : unsigned(111 downto 0)) return integer is
  begin
    for j in 0 to 3 loop
      if w(16*j+63 downto 16*j) = TR_PATTERN then
        return j;
      end if;
    end loop;
    return 7;
  end function;
  -- (fine position arithmetic, all mod TR_STEPS)
  function tr_wrap(x : integer) return integer is
  begin
    if x >= TR_STEPS then return x - TR_STEPS;
    elsif x < 0 then return x + TR_STEPS;
    else return x; end if;
  end function;

  attribute iob : string;
  attribute iob of sdram_dq_out : signal is "true";
  attribute iob of sdram_dq_oe_n : signal is "true";
  attribute iob of sdram_dq_latched : signal is "true";

begin

  lump_queue0 : entity work.lump_queue
    port map (
      clock      => clock162,
      in_valid   => lump_cmd_valid,
      in_ready   => lump_cmd_ready,
      in_op      => lump_cmd_op,
      in_addr    => lump_cmd_addr,
      in_len     => lump_cmd_len,
      head_valid => lump_q_valid,
      head_op    => lump_q_op,
      head_addr  => lump_q_addr,
      head_len   => lump_q_len,
      pop        => lump_q_pop
      );

  sdram_dq_gen : for i in sdram_dq'range generate
     sdram_dq(i) <= sdram_dq_out(i) when sdram_dq_oe_n(i) = '0' else 'Z';
  end generate sdram_dq_gen;

  process(clock162r) is
  begin

    if rising_edge(clock162r) then
      sdram_dq_latched <= sdram_dq;
    end if;
  end process;

  process(clock162) is
  begin
    if falling_edge(clock162) then
      dq_f <= sdram_dq_latched;
    end if;
  end process;

  process(clock162, pixelclock) is
    procedure sdram_emit_command(cmd : sdram_cmd_t) is
    begin
      case cmd is
        when CMD_SET_MODE_REG =>
          sdram_ras_n <= '0';
          sdram_cas_n <= '0';
          sdram_we_n  <= '0';
        when CMD_PRECHARGE =>
          sdram_ras_n <= '0';
          sdram_cas_n <= '1';
          sdram_we_n  <= '0';
          sdram_a(10) <= '1';
        when CMD_AUTO_REFRESH =>
          sdram_ras_n <= '0';
          sdram_cas_n <= '0';
          sdram_we_n  <= '1';
        when CMD_ACTIVATE_ROW =>
          -- sdram_ba=BANK and sdram_a=ROW
          sdram_ras_n <= '0';
          sdram_cas_n <= '1';
          sdram_we_n  <= '1';
        when CMD_READ =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '0';
          sdram_we_n  <= '1';
        when CMD_WRITE =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '0';
          sdram_we_n  <= '0';
        when CMD_STOP =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '1';
          sdram_we_n  <= '0';
        when CMD_NOP =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '1';
          sdram_we_n  <= '1';
        when others =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '1';
          sdram_we_n  <= '1';
      end case;
    end procedure;

    variable tj       : integer range 0 to 7;
    variable tva, tvb : std_logic;
    variable tca, tcb : unsigned(1 downto 0);
  begin
    if rising_edge(clock162) then

      sdram_dq_oe_n <= (others => '1');
      sdram_dqml <= '1';
      sdram_dqmh <= '1';

      -- LUMP: single-cycle strobes default low
      lump_q_pop       <= '0';
      lump_rdata_valid <= '0';
      lump_wdata_req   <= '0';
      lump_cmd_done    <= '0';
      lump_error       <= '0';
      lump_rd_issue    <= '0';
      lump_idle        <= not (lump_q_valid or lump_active or lump_q_pop);

      -- LUMP write data request stream: one request per cycle once started.
      -- (Each word is then used two cycles later, see LUMP_WRITE)
      if lump_wreq_cnt(8) = '0' then
        lump_wdata_req <= '1';
        lump_wreq_cnt  <= lump_wreq_cnt - 1;
      end if;

      -- Pre-compute the IDLE-state LUMP decisions one cycle ahead.  The
      -- cycle after a pop, lump_q_pop='1' forces the flags low, and the head
      -- has been updated by the time they are next computed.  The branch
      -- that consumes a command also clears its flag explicitly.
      -- lump_row_match may be one cycle stale only if active_row_addr changed
      -- in the previous cycle, which only happens in ACTIVATE_WAIT_2 and
      -- LUMP_ACTIVATE, neither of which is ever immediately followed by IDLE.
      lump_go     <= lump_q_valid and (not lump_q_op(1)) and (not lump_q_pop);
      lump_inv_go <= lump_q_valid and lump_q_op(1) and (not lump_q_pop);
      if lump_q_addr(25 downto 11) = active_row_addr(25 downto 11) then
        lump_row_match <= '1';
      else
        lump_row_match <= '0';
      end if;
      lump_is_write_pre <= lump_q_op(0);
      if lump_q_op(0) = '1' then
        -- WRITE: one command per 16-bit word
        lump_cnt_init <= signed(resize(lump_q_len(8 downto 1), 9)) - 2;
      else
        -- READ: one command per 4 words (8 bytes)
        lump_cnt_init <= signed(resize(lump_q_len(8 downto 3), 9)) - 2;
      end if;

      -- LUMP read data capture.  A READ (burst length 4) emitted at edge T
      -- delivers words at edges T+6..T+9 (T+5..T+8 with identical_clocks),
      -- as seen in sdram_dq_latched, matching READ_1..READ_4 of the CPU
      -- read path.  lump_rd_issue is set
      -- at edge T, so at edge T+k we see lump_rd_pipe(k-2).
      -- (Words reach dq_x one cycle after sdram_dq_latched: they are taken
      -- at T+7-rd_c .. T+10-rd_c.)
      if x_h = '1' then
        dq_x <= dq_f;
      else
        dq_x <= sdram_dq_latched;
      end if;
      if tr_ok = '1' then
        x_h  <= trained_h;
        rd_c <= trained_c;
      else
        -- not trained (yet, or no phase shifter): $D7FE bit 5 as before
        x_h  <= '0';
        rd_c <= '0' & identical_clocks;
      end if;
      ps_en <= '0';
      ps_locked_s1 <= ps_locked;
      ps_locked_s2 <= ps_locked_s1;
      lump_rd_pipe(0) <= lump_rd_issue;
      lump_rd_pipe(1 to 8) <= lump_rd_pipe(0 to 7);
      if (rd_c = "00" and (lump_rd_pipe(5) or lump_rd_pipe(6) or lump_rd_pipe(7) or lump_rd_pipe(8)) = '1')
        or (rd_c = "01" and (lump_rd_pipe(4) or lump_rd_pipe(5) or lump_rd_pipe(6) or lump_rd_pipe(7)) = '1')
        or (rd_c = "10" and (lump_rd_pipe(3) or lump_rd_pipe(4) or lump_rd_pipe(5) or lump_rd_pipe(6)) = '1')
        or (rd_c = "11" and (lump_rd_pipe(2) or lump_rd_pipe(3) or lump_rd_pipe(4) or lump_rd_pipe(5)) = '1')
      then
        lump_rdata       <= dq_x;
        lump_rdata_valid <= '1';
      end if;

      if refresh_due_countdown /= 0 then
        refresh_due_countdown <= refresh_due_countdown - 1;
        refresh_due           <= '0';
      else
        refresh_due <= '1';
      end if;

      if current_cache_line_address(26 downto 3) /= latched_addr(26 downto 3) then
        write_targets_cache_line <= '0';
      else
        write_targets_cache_line <= '1';
      end if;

      cache_line_prev_address <= current_cache_line_address(26 downto 3) - 1;
      cache_line_next_address <= current_cache_line_address(26 downto 3) + 1;

      if reactive_cache_line_if_safe = '1' and write_targets_cache_line = '0' then
        current_cache_line_valid     <= '1';
        current_cache_line_valid_int <= '1';
        reactive_cache_line_if_safe  <= '0';
      end if;

      -- Keep logic flat by pre-extracting read data
      -- report "RDATA_BUF: Reading from offset " & to_string(std_logic_vector(latched_addr(2 downto 0))) &
      -- ", = $" & to_hexstring(rdata_line);
      case latched_addr(2 downto 0) is
        when "000" =>
          rdata_buf    <= rdata_line(7 downto 0);
          rdata_hi_buf <= rdata_line(15 downto 8);
        when "001" =>
          rdata_buf    <= rdata_line(15 downto 8);
          rdata_hi_buf <= rdata_line(23 downto 16);
        when "010" =>
          rdata_buf    <= rdata_line(23 downto 16);
          rdata_hi_buf <= rdata_line(31 downto 24);
        when "011" =>
          rdata_buf    <= rdata_line(31 downto 24);
          rdata_hi_buf <= rdata_line(39 downto 32);
        when "100" =>
          rdata_buf    <= rdata_line(39 downto 32);
          rdata_hi_buf <= rdata_line(47 downto 40);
        when "101" =>
          rdata_buf    <= rdata_line(47 downto 40);
          rdata_hi_buf <= rdata_line(55 downto 48);
        when "110" =>
          rdata_buf    <= rdata_line(55 downto 48);
          rdata_hi_buf <= rdata_line(63 downto 56);
        when others =>                  -- "111" =>
          rdata_buf    <= rdata_line(63 downto 56);
          rdata_hi_buf <= rdata_line(7 downto 0);
      end case;

      case latched_addr(7 downto 0) is
        -- "SDRAM" at $C000000
        when x"00" =>
          nonram_val <= x"53";
        when x"01" =>
          nonram_val <= x"44";
        when x"02" =>
          nonram_val <= x"52";
        when x"03" =>
          nonram_val <= x"41";
        when x"04" =>
          nonram_val <= x"4d";
        -- Number of reads and writes done
        when x"05" =>
          nonram_val <= read_jobs;
        when x"06" =>
          nonram_val <= write_jobs;
        when x"07" =>
          nonram_val <= resets;
        -- Read capture training ($C000008-$C00001F)
        when x"08" =>
          nonram_val <= tr_ok & tr_active & tr_no_ps & tr_weak
                        & rd_c & trained_c;
        when x"09" => nonram_val <= to_unsigned(tr_width, 9)(7 downto 0);
        when x"0a" => nonram_val <= "0000000" & to_unsigned(tr_width, 9)(8);
        when x"0b" => nonram_val <= to_unsigned(tr_centre, 9)(7 downto 0);
        when x"0c" => nonram_val <= "0000000" & to_unsigned(tr_centre, 9)(8);
        when x"0d" => nonram_val <= to_unsigned(tr_pos, 9)(7 downto 0);
        when x"0e" => nonram_val <= "0000000" & to_unsigned(tr_pos, 9)(8);
        when x"0f" => nonram_val <= tr_count;
        when x"10" => nonram_val <= to_unsigned(tr_left, 9)(7 downto 0);
        when x"11" => nonram_val <= "0000000" & to_unsigned(tr_left, 9)(8);
        when x"12" => nonram_val <= to_unsigned(tr_right, 9)(7 downto 0);
        when x"13" => nonram_val <= "0000000" & to_unsigned(tr_right, 9)(8);
        when x"14" => nonram_val <= "0000000" & trained_h;
        when x"16" => nonram_val <= "0000000" & ps_locked_s2;
        when x"15" => nonram_val <= '0' & to_unsigned(tr_bs, 3) & to_unsigned(tr_bl, 4);
        when x"18" => nonram_val <= cmap(0);
        when x"19" => nonram_val <= cmap(1);
        when x"1a" => nonram_val <= cmap(2);
        when x"1b" => nonram_val <= cmap(3);
        when x"1c" => nonram_val <= cmap(4);
        when x"1d" => nonram_val <= cmap(5);
        when x"1e" => nonram_val <= cmap(6);
        when x"1f" => nonram_val <= cmap(7);
        when others => nonram_val <= x"42";
      end case;


      -- Latch incoming requests (those come in on the 81MHz pixel clock)
      if read_request = '1' and write_request = '0' and write_latched = '0' and read_latched = '0' then
        report "Latching read request for $" & to_hexstring(address);
        report "BUSY: Asserting busy";
        busy         <= '1';
        read_latched <= '1';
        latched_addr <= address;
        silent_read  <= '0';
      end if;
      if read_request = '0' and write_request = '1' and write_latched = '0' and read_latched = '0' then
        report "Latching write request";
        report "BUSY: Asserting busy";
        busy          <= '1';
        write_latched <= '1';
        latched_addr  <= address;
        wdata_latched <= wdata;
        if rdata_16en = '1' then
          wdata_hi_latched <= wdata_hi;
          latched_wen_lo   <= wen_lo;
          latched_wen_hi   <= wen_hi;
        else
          wdata_hi_latched <= wdata;
          latched_wen_lo   <= address(0);
          latched_wen_hi   <= not address(0);
        end if;
      end if;

      if read_publish_strobe = '1' then
        read_publish_strobe <= '0';
        report "rdata_line = $" & to_hexstring(rdata_line);
        report "latched_addr bits = " & to_string(std_logic_vector(latched_addr(2 downto 0)));
        report "PUBLISH: rdata <= $" & to_hexstring(rdata_hi_buf) & to_hexstring(rdata_buf) & ", silent=" & std_logic'image(silent_read);
        -- When prefetching cache lines, we don't present the output.
        -- I.E., the read is "silent"
        if silent_read = '0' then
          rdata                  <= rdata_buf;
          rdata_hi               <= rdata_hi_buf;
          data_ready_toggle      <= not last_data_ready_toggle;
          last_data_ready_toggle <= not last_data_ready_toggle;
          report "BUSY: Clearing busy via read_publish_strobe";
          busy                   <= '0';
        end if;
      end if;
      if read_complete_strobe = '1' then
        read_complete_strobe <= '0';
        report "READCOMPLETE: Publishing cache line $" & to_hexstring(rdata_line);
        -- We also update the read cache line here
        for b in 0 to 7 loop
          current_cache_line(b) <= rdata_line((b*8+7) downto (b*8));
        end loop;
        current_cache_line_address(26 downto 3) <= latched_addr(26 downto 3);
        current_cache_line_valid                <= '1';
        current_cache_line_valid_int            <= '1';

        read_publish_strobe <= '1';
      end if;

      next_toggle_drive <= expansionram_current_cache_line_next_toggle;
      prev_toggle_drive <= expansionram_current_cache_line_prev_toggle;

      if read_request = '0' and write_request = '0' and write_latched = '0' and read_latched = '0' and
        (prev_toggle_drive /= prev_current_cache_line_prev_toggle) then
        -- Read previous cache line
        report "Latching read or write request for previous cache line";
        report "prev_toggle_drive = " & std_logic'image(prev_toggle_drive) & ", "
          & "prev_current_cache_line_prev_toggle = " & std_logic'image(prev_current_cache_line_prev_toggle);
        report "BUSY: Asserting busy";
        busy                                <= '1';
        read_latched                        <= '1';
        latched_addr(26 downto 3)           <= cache_line_prev_address;
        latched_addr(2 downto 0)            <= "000";
        silent_read                         <= '1';
        prev_current_cache_line_prev_toggle <= prev_toggle_drive;
      end if;

      if read_request = '0' and write_request = '0' and write_latched = '0' and read_latched = '0' and
        (next_toggle_drive /= prev_current_cache_line_next_toggle) then
        -- Read next cache line
        report "Latching read or write request for next cache line";
        report "BUSY: Asserting busy";
        busy                                <= '1';
        read_latched                        <= '1';
        latched_addr(26 downto 3)           <= cache_line_next_address;
        latched_addr(2 downto 0)            <= "000";
        silent_read                         <= '1';
        prev_current_cache_line_next_toggle <= next_toggle_drive;
      end if;

      -- Manage the 100usec SDRAM initialisation delay, if enabled
      if sdram_100us_countdown /= 0 then
        sdram_100us_countdown <= sdram_100us_countdown - 1;
      end if;
      if sdram_100us_countdown = 1 then
        report "SDRAM: Starting init sequence after 100usec delay";
        sdram_do_init <= not sdram_prepped;
        -- The init sequence (which trains at its end) is skipped at
        -- power-on while sdram_prepped starts at '1', so train here too,
        -- unless training has already run or is running.
        if sdram_prepped = '1' and tr_count = x"00" and tr_active = '0' then
          tr_req  <= '1';
          tr_mode <= "00";
        end if;
      end if;
      if enforce_100us_delay = false then
        if sdram_prepped = '0' then
          report "SDRAM: Skipping 100usec init delay";
        end if;
        sdram_do_init <= not sdram_prepped;
      end if;
      -- And the complete SDRAM initialisation sequence
      if sdram_init_phase = 0 and sdram_do_init = '1' then
        report "SDRAM: Starting SDRAM initialisation sequence";
        sdram_init_phase <= 1;
        resets <= resets + 1;
      end if;
      if sdram_prepped = '0' then
        if sdram_init_phase /= 0 then
          report "EMIT init phase " & integer'image(sdram_init_phase) & " command "
            & sdram_cmd_t'image(init_cmds(sdram_init_phase));
        end if;

        -- Clear reserved bits for mode register
        sdram_ba              <= (others => '0');
        sdram_a(12 downto 10) <= (others => '0');
        -- write burst length = 1
        sdram_a(9)            <= '1';
        -- Normal mode of operation
        sdram_a(8 downto 7)   <= (others => '0');
        -- CAS latency = 3, for 167MHz operation (what we do)
        sdram_a(6 downto 4)   <= to_unsigned(3, 3);
        -- Non-interleaved burst order
        sdram_a(3)            <= '0';
        -- Read burst length = 4 x 16 bit words = 8 bytes
        sdram_a(2 downto 0)   <= to_unsigned(2, 3);
        -- XXX DEBUG: read 8 x words so that we can check if missing bits is
        -- due to first word of burst or not.
--        sdram_a(2 downto 0)   <= to_unsigned(3, 3);

        -- Emit the sequence of commands
        -- MUST BE DONE AFTER SETTING sdram_a
        -- (so that A10 can be set for the PRECHARGE_ALL command,
        --  but stay clear for all the rest)
        sdram_emit_command(init_cmds(sdram_init_phase));

        if sdram_init_phase = 31 then
          sdram_prepped <= '1';
          busy          <= '0';
          -- Read capture training next (it sets busy itself while it runs,
          -- once the capture clock's MMCM is locked)
          tr_req        <= '1';
          tr_mode       <= "00";
          report "SDRAM: initialisation done, read capture training next";
        elsif sdram_init_phase /= 0 then
          sdram_init_phase <= sdram_init_phase + 1;
        end if;
      else
        -- SDRAM is ready
        report "SDRAMSTATE: " & sdram_state_t'image(sdram_state);
        if sdram_state /= IDLE then
          sdram_state <= sdram_state_t'succ(sdram_state);
        end if;
        case sdram_state is
          when IDLE =>
            -- (training waits, with the controller working normally, until
            -- the capture clock's MMCM is locked)
            if tr_req = '1' and ps_locked_s2 = '1' then
              -- Read capture training (or a manual phase step).  Rows are
              -- closed first; refresh is handled inside.
              tr_req      <= '0';
              tr_active   <= '1';
              busy        <= '1';
              tr_st       <= T_START;
              sdram_state <= TRAIN;
              sdram_emit_command(CMD_NOP);
            elsif refresh_due = '1' and active_row = '0' then
              report "REFRESH is DUE (and no row was open, so triggering immediately)";
              sdram_emit_command(CMD_AUTO_REFRESH);
              sdram_state <= REFRESH_1;
              report "BUSY: Asserting busy";
              busy        <= '1';
            elsif refresh_due = '1' and active_row = '1' then
              report "REFRESH is DUE (a row is open, so precharging first)";
              sdram_emit_command(CMD_PRECHARGE);
              sdram_state <= CLOSE_FOR_REFRESH;
              report "BUSY: Asserting busy";
              busy        <= '1';
            elsif read_latched = '1' or write_latched = '1' then
              if latched_addr(26) = '1' then
                report "NONRAMACCESS: Non-RAM access detected";
                if write_latched = '1' and latched_addr(7 downto 0) = x"10" then
                  -- $C000010: train again (the 8 test bytes are restored)
                  tr_req <= '1'; tr_mode <= "00";
                  write_latched <= '0';
                  sdram_emit_command(CMD_NOP);
                elsif write_latched = '1' and latched_addr(7 downto 0) = x"11" then
                  -- $C000011 / $C000012: one fine phase step later / earlier
                  tr_req <= '1'; tr_mode <= "01";
                  write_latched <= '0';
                  sdram_emit_command(CMD_NOP);
                elsif write_latched = '1' and latched_addr(7 downto 0) = x"12" then
                  tr_req <= '1'; tr_mode <= "10";
                  write_latched <= '0';
                  sdram_emit_command(CMD_NOP);
                elsif write_latched = '1' and latched_addr(7 downto 0) = x"14" then
                  -- $C000014: force the path (bit 2) and read cycle (bits
                  -- 1-0), keeping the phase, for experiments
                  trained_h <= wdata_latched(2);
                  trained_c <= wdata_latched(1 downto 0);
                  tr_ok <= '1';
                  write_latched <= '0';
                  busy <= '0';
                  sdram_emit_command(CMD_NOP);
                elsif write_latched = '1' then
                  -- Repeat SDRAM initialisation sequence whenver a non-RAM
                  -- address is written.
                  -- XXX Used to debug whether SDRAM initialisation is sometimes
                  -- failing.
                  sdram_prepped <= '0';
                  sdram_init_phase <= 0;
                  sdram_do_init <= '1';
                  write_latched <= '0';
                else
                  -- Read non-RAM address
                  sdram_state <= NON_RAM_READ;
                  sdram_emit_command(CMD_NOP);
                end if;
              else
                -- Activate the row
                if read_latched = '1' then
                  report "SDRAMREAD: Starting read from $" & to_hexstring(latched_addr);
                end if;
                if write_latched = '1' then
                  report "SDRAMWRITE: Starting write: $" & to_hexstring(latched_addr) & " <= $" & to_hexstring(wdata_latched);
                end if;
                if active_row = '0' then
                  report "ACTIVATEROW: No row open yet, so opening before read or write for row $" & to_hexstring(latched_addr)
                    & " = %" & to_string(std_logic_vector(latched_addr));
                  -- If no active row, then activate one
                  sdram_emit_command(CMD_ACTIVATE_ROW);
                  sdram_ba    <= latched_addr(25 downto 24);
                  sdram_a     <= latched_addr(23 downto 11);
                  sdram_state <= ACTIVATE_WAIT;
                elsif latched_addr(25 downto 11) /= active_row_addr(25 downto 11) then
                  report "ACTIVATEROW: Closing old row before opening new one required for read or write";
                  -- Different row activated
                  -- Precharge row, then activate the correct row
                  sdram_emit_command(CMD_PRECHARGE);
                  sdram_ba    <= latched_addr(25 downto 24);
                  sdram_a     <= latched_addr(23 downto 11);
                  sdram_state <= CLOSE_AND_SWITCH_ROW;
                else
                  -- Correct row already activated
                  report "ACTIVEROW: Correct row is already active";
                  if read_latched = '1' then
                    report "SDRAM: Issuing READ command after ROW_ACTIVATE";
                    sdram_emit_command(CMD_READ);
                    -- Select address of start of 8-byte block
                    -- Each word is 2 bytes, which takes one bit
                    -- off, and then the bottom two bits must be zero.
                    sdram_a(12)         <= '0';
                    sdram_a(11)         <= '0';
                    sdram_a(10)         <= '0';  -- Disable auto precharge
                    sdram_a(9 downto 2) <= latched_addr(10 downto 3);
                    sdram_a(1 downto 0) <= "00";
                    sdram_state         <= READ_WAIT;
                    sdram_dqml          <= '0'; sdram_dqmh <= '0';
                  end if;
                  if write_latched = '1' then
                    report "SDRAM: Issuing WRITE command after ROW_ACTIVATE";
                    sdram_state <= WRITE_1;
                    sdram_dq_out(7 downto 0)  <= wdata_latched;
                    sdram_dq_out(15 downto 8) <= wdata_hi_latched;
                    sdram_dq_oe_n <= (others => '0');
                  end if;

                end if;

                -- XXX For now we invalidate the cache line on _any_ write
                -- For the common case of DMA copy to or from slow RAM, this
                -- will be ok. Copying slow to slow will, however be bad.
                -- So to remedy that, we set a signal to check if the cache
                -- line can be re-instated. This prevents use of the cache while
                -- we are figuring out if the line is still valid.
                if write_latched = '1' then
                  current_cache_line_valid     <= '0';
                  current_cache_line_valid_int <= '0';
                  if current_cache_line_valid_int = '1' then
                    reactive_cache_line_if_safe <= '1';
                  end if;
                end if;
              end if;
            elsif (lump_go or lump_inv_go) = '1' then
              -- LUMP has the lowest priority: refresh and CPU requests
              -- are always served first.
              lump_q_pop <= '1';
              lump_go <= '0';
              lump_inv_go <= '0';
              if lump_inv_go = '1' then
                report "LUMP: Invalidating read cache";
                current_cache_line_valid     <= '0';
                current_cache_line_valid_int <= '0';
                reactive_cache_line_if_safe  <= '0';
                lump_cmd_done                <= '1';
                sdram_emit_command(CMD_NOP);
              else
                report "LUMP: Starting burst @ $" & to_hexstring(lump_q_addr);
                lump_active   <= '1';
                -- Note: busy is deliberately left alone.  CPU requests
                -- arriving now are latched as usual and served after the
                -- burst; the latching logic manages busy for them.
                lump_bank     <= lump_q_addr(25 downto 24);
                lump_row      <= lump_q_addr(23 downto 11);
                lump_col      <= lump_q_addr(10 downto 1);
                lump_phase    <= "00";
                lump_is_write <= lump_is_write_pre;
                lump_cnt      <= lump_cnt_init;
                if active_row = '0' then
                  sdram_emit_command(CMD_ACTIVATE_ROW);
                  sdram_ba    <= lump_q_addr(25 downto 24);
                  sdram_a     <= lump_q_addr(23 downto 11);
                  sdram_state <= LUMP_ACTIVATE;
                  lump_wait   <= 1;
                elsif lump_row_match = '0' then
                  sdram_emit_command(CMD_PRECHARGE);
                  sdram_state <= LUMP_PRECHARGE;
                  lump_wait   <= 3;
                else
                  -- Correct row already open
                  sdram_emit_command(CMD_NOP);
                  sdram_state <= LUMP_ACTIVATE;
                  lump_wait   <= 1;
                end if;
              end if;
            else
              sdram_emit_command(CMD_NOP);
            end if;
          when LUMP_PRECHARGE =>
            -- PRECHARGE (all banks) was issued from IDLE.  Same tRP as the
            -- CLOSE_AND_SWITCH_ROW path: ACTIVATE 4 cycles after PRECHARGE.
            sdram_state <= LUMP_PRECHARGE;
            if lump_wait /= 0 then
              lump_wait <= lump_wait - 1;
              sdram_emit_command(CMD_NOP);
            else
              sdram_emit_command(CMD_ACTIVATE_ROW);
              sdram_ba    <= lump_bank;
              sdram_a     <= lump_row;
              sdram_state <= LUMP_ACTIVATE;
              lump_wait   <= 1;
            end if;
          when LUMP_ACTIVATE =>
            -- Wait out tRCD: first READ/WRITE is issued 3 cycles after
            -- ACTIVATE, as in the CPU path.
            sdram_emit_command(CMD_NOP);
            active_row                    <= '1';
            active_row_addr(25 downto 24) <= lump_bank;
            active_row_addr(23 downto 11) <= lump_row;
            sdram_state <= LUMP_ACTIVATE;
            if lump_wait = 1 and lump_is_write = '1' then
              -- Request the first write word now: it is sampled two edges
              -- later, which is exactly when the first WRITE is emitted.
              -- The remaining requests then follow one per cycle.
              lump_wdata_req <= '1';
              -- (words - 1) further requests: lump_cnt is words - 2 here
              lump_wreq_cnt  <= lump_cnt;
            end if;
            if lump_wait /= 0 then
              lump_wait <= lump_wait - 1;
            else
              if lump_is_write = '1' then
                sdram_state <= LUMP_WRITE;
              else
                sdram_state <= LUMP_READ;
              end if;
            end if;
          when LUMP_READ =>
            -- Issue one READ (burst of 4 words) every 4 cycles.  This gives
            -- a gap-free stream of data from the open row.
            sdram_state <= LUMP_READ;
            sdram_dqml  <= '0'; sdram_dqmh <= '0';
            lump_phase  <= lump_phase + 1;
            if lump_phase = "00" then
              sdram_emit_command(CMD_READ);
              sdram_ba            <= lump_bank;
              sdram_a(12 downto 11) <= "00";
              sdram_a(10)         <= '0';  -- No auto precharge
              sdram_a(9 downto 2) <= lump_col(9 downto 2);
              sdram_a(1 downto 0) <= "00";
              lump_col(9 downto 2) <= lump_col(9 downto 2) + 1;
              lump_rd_issue       <= '1';
              read_jobs           <= read_jobs + 1;
              if lump_cnt(8) = '1' then
                sdram_state <= LUMP_READ_DRAIN;
              else
                lump_cnt <= lump_cnt - 1;
              end if;
            else
              sdram_emit_command(CMD_NOP);
            end if;
          when LUMP_READ_DRAIN =>
            -- Wait for the last read data to be captured
            sdram_emit_command(CMD_NOP);
            sdram_dqml  <= '0'; sdram_dqmh <= '0';
            sdram_state <= LUMP_READ_DRAIN;
            if lump_rd_issue = '0' and lump_rd_pipe = "000000000" then
              lump_active   <= '0';
              lump_cmd_done <= '1';
              sdram_state   <= IDLE;
            end if;
          when LUMP_WRITE =>
            -- Write burst length is 1 (mode register A9=1), so we issue one
            -- WRITE per cycle with its data, gap-free within the open row.
            sdram_state <= LUMP_WRITE;
            sdram_emit_command(CMD_WRITE);
            sdram_ba            <= lump_bank;
            sdram_a(12 downto 11) <= "00";
            sdram_a(10)         <= '0';  -- No auto precharge
            sdram_a(9 downto 0) <= lump_col;
            lump_col            <= lump_col + 1;
            sdram_dq_out        <= lump_wdata;
            sdram_dq_oe_n       <= (others => '0');
            -- DQM high = byte masked
            sdram_dqml          <= not lump_wdata_be(0);
            sdram_dqmh          <= not lump_wdata_be(1);
            write_jobs          <= write_jobs + 1;
            if lump_cnt(8) = '1' then
              sdram_state <= LUMP_WRITE_RECOVER;
              lump_wait   <= 1;
            else
              lump_cnt <= lump_cnt - 1;
            end if;
          when LUMP_WRITE_RECOVER =>
            -- tWR before anything (e.g. a refresh PRECHARGE) can follow
            sdram_emit_command(CMD_NOP);
            sdram_state <= LUMP_WRITE_RECOVER;
            if lump_wait /= 0 then
              lump_wait <= lump_wait - 1;
            else
              lump_active   <= '0';
              lump_cmd_done <= '1';
              sdram_state   <= IDLE;
            end if;
          when TRAIN =>
            sdram_state <= TRAIN;
            sdram_emit_command(CMD_NOP);
            case tr_st is
              ---------------------------------------------------------------
              -- Micro-operations
              when M_WAIT =>                  -- tr_cnt cycles, then tr_ret
                if tr_cnt <= 1 then tr_st <= tr_ret; else tr_cnt <= tr_cnt - 1; end if;
              when M_PS =>
                -- One fine phase step (PSCLK = clock162); PSDONE ~12 later
                ps_en     <= '1';
                ps_incdec <= not tr_dec;
                tr_to     <= 0;
                tr_st     <= M_PSW;
              when M_PSW =>
                if ps_done = '1' then
                  if tr_dec = '1' then
                    tr_pos <= tr_wrap(tr_pos - 1);
                  else
                    tr_pos <= tr_wrap(tr_pos + 1);
                  end if;
                  tr_st <= tr_ret;
                elsif tr_to = 127 then
                  tr_no_ps <= '1';
                  tr_st <= T_ABORT;
                else
                  tr_to <= tr_to + 1;
                end if;
              when M_STEPN =>                 -- tr_n steps (tr_ndec), then tr_ret_n
                if tr_n = 0 then
                  tr_st <= tr_ret_n;
                else
                  tr_n <= tr_n - 1;
                  tr_dec <= tr_ndec;
                  tr_ret <= M_STEPN;
                  tr_st <= M_PS;
                end if;
              when M_SEEK =>                  -- to tr_target the short way, then tr_ret_n
                tr_delta <= tr_target - tr_pos;
                tr_st <= M_SEEK2;
              when M_SEEK2 =>
                if tr_delta >= 0 then
                  if tr_delta <= TR_STEPS/2 then
                    tr_n <= tr_delta; tr_ndec <= '0';
                  else
                    tr_n <= TR_STEPS - tr_delta; tr_ndec <= '1';
                  end if;
                else
                  if tr_delta >= -TR_STEPS/2 then
                    tr_n <= -tr_delta; tr_ndec <= '1';
                  else
                    tr_n <= TR_STEPS + tr_delta; tr_ndec <= '0';
                  end if;
                end if;
                tr_st <= M_STEPN;
              when M_RWAIT =>
                -- READ was issued at edge T, and now is T+tr_k.  Keep what
                -- both paths would hand dq_x at T+3..T+9: a word seen here
                -- at T+k reaches dq_x at T+k+1, so a burst starting at
                -- word j of these 7 is read cycle 3-j.
                sdram_dqml <= '0'; sdram_dqmh <= '0';
                if tr_k >= 3 and tr_k <= 9 then
                  wa <= sdram_dq_latched & wa(111 downto 16);
                  wb <= dq_f & wb(111 downto 16);
                end if;
                if tr_k = 11 then tr_st <= tr_ret; else tr_k <= tr_k + 1; end if;
              when M_WRITE =>
                -- Four WRITEs (burst length 1), test or saved words; the
                -- row must be open.  Then tWR, then tr_ret.
                sdram_emit_command(CMD_WRITE);
                sdram_ba <= "11";
                sdram_a(12 downto 11) <= "00";
                sdram_a(10) <= '0';
                sdram_a(9 downto 0) <= to_unsigned(1020 + tr_wi, 10);
                if tr_restore = '1' then
                  sdram_dq_out <= tr_saved(tr_wi*16+15 downto tr_wi*16);
                else
                  sdram_dq_out <= TR_PATTERN(tr_wi*16+15 downto tr_wi*16);
                end if;
                sdram_dq_oe_n <= (others => '0');
                sdram_dqml <= '0'; sdram_dqmh <= '0';
                if tr_wi = 3 then
                  tr_wi <= 0;
                  tr_cnt <= 3;
                  tr_st <= M_WAIT;
                else
                  tr_wi <= tr_wi + 1;
                end if;

              ---------------------------------------------------------------
              -- One test of the current phase, then tr_ret_t: (refresh if
              -- due), open the row, READ twice, close it.  t_va/t_ca and
              -- t_vb/t_cb: clean on each path, and the read cycle, when
              -- both READs agreed.
              when T_TEST0 =>
                if refresh_due = '1' then
                  sdram_emit_command(CMD_AUTO_REFRESH);
                  refresh_due_countdown <= refresh_interval - 1;
                  tr_cnt <= 11;               -- tRFC
                  tr_ret <= T_TEST1;
                  tr_st <= M_WAIT;
                else
                  tr_st <= T_TEST1;
                end if;
              when T_TEST1 =>
                sdram_emit_command(CMD_ACTIVATE_ROW);
                sdram_ba <= "11";
                sdram_a <= (others => '1');
                tr_r <= '0';
                tr_cnt <= 2;                  -- tRCD
                tr_ret <= T_TEST2;
                tr_st <= M_WAIT;
              when T_TEST2 =>
                sdram_emit_command(CMD_READ);
                sdram_ba <= "11";
                sdram_a(12 downto 10) <= "000";
                sdram_a(9 downto 0) <= to_unsigned(1020, 10);
                sdram_dqml <= '0'; sdram_dqmh <= '0';
                tr_k <= 1;
                tr_ret <= T_TEST3;
                tr_st <= M_RWAIT;
              when T_TEST3 =>
                tj := tr_find(wa);
                if tj < 4 then tva := '1'; tca := to_unsigned(3 - tj, 2);
                else tva := '0'; tca := "00"; end if;
                tj := tr_find(wb);
                if tj < 4 then tvb := '1'; tcb := to_unsigned(3 - tj, 2);
                else tvb := '0'; tcb := "00"; end if;
                if tr_r = '0' then
                  r1_va <= tva; r1_ca <= tca; r1_vb <= tvb; r1_cb <= tcb;
                  tr_r <= '1';
                  tr_st <= T_TEST2;
                else
                  if tva = '1' and r1_va = '1' and tca = r1_ca then t_va <= '1'; else t_va <= '0'; end if;
                  if tvb = '1' and r1_vb = '1' and tcb = r1_cb then t_vb <= '1'; else t_vb <= '0'; end if;
                  t_ca <= tca;
                  t_cb <= tcb;
                  sdram_emit_command(CMD_PRECHARGE);
                  tr_cnt <= 3;                -- tRP
                  tr_ret <= tr_ret_t;
                  tr_st <= M_WAIT;
                end if;

              ---------------------------------------------------------------
              when T_START =>
                -- Close all rows (tRP).  A training run then starts with
                -- one phase step, which checks that a phase shifter answers;
                -- a manual step ($C000011/2) is just that step.
                sdram_emit_command(CMD_PRECHARGE);
                active_row <= '0';
                tr_had_ok <= tr_ok;
                tr_no_ps <= '0';
                tr_dec <= tr_mode(1);
                tr_cnt <= 3;
                tr_ret <= T_PROBED;
                tr_st <= M_WAIT;
              when T_PROBED =>
                tr_st <= M_PS;
                if tr_mode = "00" then
                  tr_ret <= T_OPENED;
                else
                  tr_ret <= T_FINISH;
                end if;
              when T_OPENED =>
                -- Positions are counted from here.  If reads are trusted
                -- (trained before), save the 8 test bytes first.
                tr_pos <= 0;
                if tr_had_ok = '1' then
                  tr_ret_t <= T_SAVED;
                  tr_st <= T_TEST0;
                else
                  tr_st <= T_SAVED;
                end if;
              when T_SAVED =>
                if tr_had_ok = '1' then
                  tj := 3 - to_integer(trained_c);
                  if trained_h = '1' then
                    tr_saved <= wb(16*tj+63 downto 16*tj);
                  else
                    tr_saved <= wa(16*tj+63 downto 16*tj);
                  end if;
                end if;
                sdram_emit_command(CMD_ACTIVATE_ROW);
                sdram_ba <= "11";
                sdram_a <= (others => '1');
                tr_restore <= '0';
                tr_wi <= 0;
                tr_cnt <= 2;
                tr_ret <= T_SAVE_READ;
                tr_st <= M_WAIT;
              when T_SAVE_READ =>
                -- (row open) write the test pattern
                tr_ret <= T_WRITTEN;
                tr_st <= M_WRITE;
              when T_WRITTEN =>
                sdram_emit_command(CMD_PRECHARGE);
                tr_p <= 0;
                tr_cnt <= 3;
                tr_ret <= T_CO_TEST;
                tr_st <= M_WAIT;

              -- 1. Coarse: 8 phases, 35 fine steps apart (back to 0 after)
              when T_CO_TEST =>
                tr_ret_t <= T_CO_REC;
                tr_st <= T_TEST0;
              when T_CO_REC =>
                cmap(tr_p) <= '0' & t_vb & t_cb & '0' & t_va & t_ca;
                tr_p <= tr_p + 1;
                tr_n <= TR_COARSE;
                tr_ndec <= '0';
                tr_ret_n <= T_CO_NEXT;
                tr_st <= M_STEPN;
              when T_CO_NEXT =>
                if tr_p = 8 then
                  tr_i <= 0; tr_run <= 0; tr_bl <= 0; tr_rs <= 0; tr_bs <= 0;
                  tr_st <= T_RUN;
                else
                  tr_st <= T_CO_TEST;
                end if;

              -- 2. Longest run of clean coarse phases, going round twice
              when T_RUN =>
                if (cmap(tr_i mod 8)(2) or cmap(tr_i mod 8)(6)) = '1' then
                  if tr_run < 8 then
                    tr_run <= tr_run + 1;
                    if tr_run = 0 then tr_rs <= tr_i mod 8; end if;
                    if tr_run + 1 > tr_bl then
                      tr_bl <= tr_run + 1;
                      if tr_run = 0 then tr_bs <= tr_i mod 8; else tr_bs <= tr_rs; end if;
                    end if;
                  end if;
                else
                  tr_run <= 0;
                end if;
                if tr_i = 15 then tr_st <= T_RUN_DONE; else tr_i <= tr_i + 1; end if;
              when T_RUN_DONE =>
                if tr_bl = 0 then
                  tr_ok <= '0'; tr_weak <= '0'; tr_width <= 0;
                  tr_st <= T_RESTORE;
                elsif tr_bl = 8 then
                  -- clean all the way round: no edges to find
                  tr_left <= 0; tr_right <= TR_STEPS - 1;
                  tr_st <= T_MID;
                else
                  tr_target <= tr_bs * TR_COARSE;
                  tr_fc <= 0;
                  tr_ret_n <= T_FL_STEP;
                  tr_st <= M_SEEK;
                end if;

              -- 3. Fine edges: step out one at a time until not clean
              when T_FL_STEP =>
                if tr_fc = TR_COARSE then
                  tr_left <= tr_pos;
                  tr_st <= T_FR_GO;
                else
                  tr_n <= 1; tr_ndec <= '1';
                  tr_ret_n <= T_FL_T;
                  tr_st <= M_STEPN;
                end if;
              when T_FL_T =>
                tr_ret_t <= T_FL_REC;
                tr_st <= T_TEST0;
              when T_FL_REC =>
                if (t_va or t_vb) = '1' then
                  tr_fc <= tr_fc + 1;
                  tr_st <= T_FL_STEP;
                else
                  tr_left <= tr_wrap(tr_pos + 1);
                  tr_st <= T_FR_GO;
                end if;
              when T_FR_GO =>
                tr_target <= ((tr_bs + tr_bl - 1) mod 8) * TR_COARSE;
                tr_fc <= 0;
                tr_ret_n <= T_FR_STEP;
                tr_st <= M_SEEK;
              when T_FR_STEP =>
                if tr_fc = TR_COARSE then
                  tr_right <= tr_pos;
                  tr_st <= T_MID;
                else
                  tr_n <= 1; tr_ndec <= '0';
                  tr_ret_n <= T_FR_T;
                  tr_st <= M_STEPN;
                end if;
              when T_FR_T =>
                tr_ret_t <= T_FR_REC;
                tr_st <= T_TEST0;
              when T_FR_REC =>
                if (t_va or t_vb) = '1' then
                  tr_fc <= tr_fc + 1;
                  tr_st <= T_FR_STEP;
                else
                  tr_right <= tr_wrap(tr_pos - 1);
                  tr_st <= T_MID;
                end if;
              when T_MID =>
                tr_delta <= tr_right - tr_left;
                tr_st <= T_MID2;
              when T_MID2 =>
                if tr_delta < 0 then
                  tr_width <= tr_delta + TR_STEPS + 1;
                else
                  tr_width <= tr_delta + 1;
                end if;
                tr_st <= T_MID3;
              when T_MID3 =>
                tr_centre <= tr_wrap(tr_left + tr_width / 2);
                if tr_width >= 4 then tr_qd <= tr_width / 4; else tr_qd <= 1; end if;
                tr_q <= 0;
                tr_st <= T_PATH_GO;

              -- 4. Path: the centre, then a quarter-window either side
              when T_PATH_GO =>
                if tr_q = 0 then
                  tr_target <= tr_centre;
                elsif tr_q = 1 then
                  tr_target <= tr_wrap(tr_centre - tr_qd);
                else
                  tr_target <= tr_wrap(tr_centre + tr_qd);
                end if;
                tr_ret_n <= T_PATH_T;
                tr_st <= M_SEEK;
              when T_PATH_T =>
                tr_ret_t <= T_PATH_REC;
                tr_st <= T_TEST0;
              when T_PATH_REC =>
                if tr_q = 0 then
                  pa_ok <= t_va; pa_c <= t_ca;
                  pb_ok <= t_vb; pb_c <= t_cb;
                  cen_va <= t_va; cen_ca <= t_ca;
                  cen_vb <= t_vb; cen_cb <= t_cb;
                else
                  if t_va = '0' or t_ca /= pa_c then pa_ok <= '0'; end if;
                  if t_vb = '0' or t_cb /= pb_c then pb_ok <= '0'; end if;
                end if;
                if tr_q = 2 then
                  tr_st <= T_PATH_PICK;
                else
                  tr_q <= tr_q + 1;
                  tr_st <= T_PATH_GO;
                end if;
              when T_PATH_PICK =>
                tr_ok <= '1';
                if tr_width < 16 then tr_weak <= '1'; else tr_weak <= '0'; end if;
                if pa_ok = '1' then
                  trained_h <= '0'; trained_c <= pa_c;
                elsif pb_ok = '1' then
                  trained_h <= '1'; trained_c <= pb_c;
                elsif cen_va = '1' then
                  trained_h <= '0'; trained_c <= cen_ca; tr_weak <= '1';
                elsif cen_vb = '1' then
                  trained_h <= '1'; trained_c <= cen_cb; tr_weak <= '1';
                else
                  tr_ok <= '0';
                end if;
                tr_target <= tr_centre;
                tr_ret_n <= T_RESTORE;
                tr_st <= M_SEEK;

              when T_RESTORE =>
                if tr_had_ok = '1' then
                  sdram_emit_command(CMD_ACTIVATE_ROW);
                  sdram_ba <= "11";
                  sdram_a <= (others => '1');
                  tr_restore <= '1';
                  tr_wi <= 0;
                  tr_cnt <= 2;
                  tr_ret <= T_RESTORE_W;
                  tr_st <= M_WAIT;
                else
                  tr_st <= T_FINISH;
                end if;
              when T_RESTORE_W =>
                tr_ret <= T_ABORT;            -- (precharge and finish)
                tr_st <= M_WRITE;
              when T_ABORT =>
                -- Also the normal way out after a restore: close rows
                sdram_emit_command(CMD_PRECHARGE);
                tr_restore <= '0';
                tr_cnt <= 3;
                tr_ret <= T_FINISH;
                tr_st <= M_WAIT;
              when T_FINISH =>
                active_row <= '0';
                tr_active <= '0';
                if tr_mode = "00" then
                  tr_count <= tr_count + 1;
                end if;
                if read_latched = '0' and write_latched = '0'
                  and read_request = '0' and write_request = '0' then
                  busy <= '0';
                end if;
                sdram_state <= IDLE;
              when others =>
                tr_st <= T_ABORT;
            end case;
          when NON_RAM_READ =>
            read_latched              <= '0';
            report "PUBLISH: non-RAM read";
            data_ready_toggle       <= not last_data_ready_toggle;
            last_data_ready_toggle       <= not last_data_ready_toggle;
            report "BUSY: Clearing after non-ram read";
            busy <= '0';
            rdata                     <= nonram_val;
            rdata_hi                  <= nonram_val;
            sdram_state               <= IDLE;
            report "NONRAMACCESS: Presenting value $" & to_hexstring(nonram_val);
          when CLOSE_AND_SWITCH_ROW =>
            -- PRECHARGE has already been issued, so just NOP until precharge
            -- time expired
            sdram_emit_command(CMD_NOP);
          when CLOSE_AND_SWITCH_ROW_2 => sdram_emit_command(CMD_NOP);
          when CLOSE_AND_SWITCH_ROW_3 => sdram_emit_command(CMD_NOP);
          when CLOSE_AND_SWITCH_ROW_4 =>
            -- Now open the new row
            sdram_emit_command(CMD_ACTIVATE_ROW);
            sdram_ba <= latched_addr(25 downto 24);
            sdram_a  <= latched_addr(23 downto 11);
          when ACTIVATE_WAIT =>
            sdram_emit_command(CMD_NOP);
          when ACTIVATE_WAIT_1 =>
            sdram_emit_command(CMD_NOP);
            if write_latched = '1' then
              -- Setup write data early, to handle marginal timing
              -- more safely (saves us needing separate read latch clock)
              sdram_dq_out(7 downto 0)  <= wdata_latched;
              sdram_dq_out(15 downto 8) <= wdata_hi_latched;
              sdram_dq_oe_n             <= (others => '0');
              sdram_dqmh            <= latched_wen_hi;
              sdram_dqml            <= latched_wen_lo;
            end if;
          when ACTIVATE_WAIT_2 =>
            sdram_emit_command(CMD_NOP);
            active_row                    <= '1';
            active_row_addr(25 downto 11) <= latched_addr(25 downto 11);
            if read_latched = '1' then
              report "SDRAM: Issuing READ command after ROW_ACTIVATE";
              sdram_emit_command(CMD_READ);
              -- Select address of start of 8-byte block
              -- Each word is 2 bytes, which takes one bit
              -- off, and then the bottom two bits must be zero.
              sdram_a(12)         <= '0';
              sdram_a(11)         <= '0';
              sdram_a(10)         <= '0';  -- Disable auto precharge
              sdram_a(9 downto 2) <= latched_addr(10 downto 3);
              sdram_a(1 downto 0) <= "00";
              sdram_state         <= READ_WAIT;
              sdram_dqml          <= '0'; sdram_dqmh <= '0';
            end if;
            if write_latched = '1' then
              report "SDRAM: Issuing WRITE command after ROW_ACTIVATE";
              sdram_state <= WRITE_1;
            end if;
            sdram_dq_out(7 downto 0)  <= wdata_latched;
            sdram_dq_out(15 downto 8) <= wdata_hi_latched;
            sdram_dq_oe_n             <= (others => '0');
          when READ_WAIT =>
            read_jobs  <= read_jobs + 1;
            sdram_dqml <= '0'; sdram_dqmh <= '0';
            sdram_emit_command(CMD_NOP);
          when READ_WAIT_2 =>
            -- READ_1 (the first word) comes at T+7-rd_c: skip wait states
            if rd_c = "11" then
              sdram_state <= READ_0;
            end if;
            sdram_dqml <= '0'; sdram_dqmh <= '0';
            sdram_emit_command(CMD_NOP);
          when READ_WAIT_3 =>
            if rd_c = "10" then
              sdram_state <= READ_0;
            elsif rd_c = "01" then
              sdram_state <= READ_WAIT_5;
            end if;
            sdram_dqml <= '0'; sdram_dqmh <= '0';
            sdram_emit_command(CMD_NOP);
          when READ_WAIT_4 =>
            sdram_dqml <= '0'; sdram_dqmh <= '0';
            sdram_emit_command(CMD_NOP);
          when READ_WAIT_5 =>
            -- (the dq_x stage)
            sdram_dqml <= '0'; sdram_dqmh <= '0';
            sdram_emit_command(CMD_NOP);
          when READ_0 =>
            sdram_dqml <= '0'; sdram_dqmh <= '0';
            sdram_emit_command(CMD_NOP);
            -- Data is latched on opposite phase clock, so it isn't available yet
            -- but rather in the next cycle in READ_1
          when READ_1 =>
            rdata_line(15 downto 0) <= dq_x;
            sdram_dqml <= '0'; sdram_dqmh <= '0';
            sdram_emit_command(CMD_NOP);
          when READ_2 =>
            sdram_dqml <= '0'; sdram_dqmh <= '0';
            rdata_line(31 downto 16) <= dq_x;
            sdram_emit_command(CMD_NOP);
          when READ_3 =>
            sdram_emit_command(CMD_NOP);
            sdram_dqml <= '0'; sdram_dqmh <= '0';
            rdata_line(47 downto 32) <= dq_x;
          when READ_4 =>
            report "READ4: dq_x = $" & to_hexstring(dq_x);
            rdata_line(63 downto 48) <= dq_x;
            read_complete_strobe     <= '1';
            read_latched             <= '0';
            report "BUSY: Clearing after read";
            busy                     <= '0';
            sdram_state              <= IDLE;
          when WRITE_1 =>
            sdram_emit_command(CMD_WRITE);
            sdram_a(12)         <= '0';
            sdram_a(11)         <= '0';
            sdram_a(10)         <= '0';  -- Disable auto precharge
            sdram_a(9 downto 0) <= latched_addr(10 downto 1);

            sdram_dq_out(7 downto 0)  <= wdata_latched;
            sdram_dq_out(15 downto 8) <= wdata_hi_latched;
            sdram_dq_oe_n             <= (others => '0');

            -- DQM lines are high to ignore a byte, and low to accept one
            sdram_dqmh <= latched_wen_hi;
            sdram_dqml <= latched_wen_lo;

            -- Immediately complete write request if the correct row is
            -- already open
            report "BUSY: Clearing after non-ram read";
            busy          <= '0';
            write_latched <= '0';
          when WRITE_2 =>
            sdram_dq_out(7 downto 0)  <= wdata_latched;
            sdram_dq_out(15 downto 8) <= wdata_hi_latched;
            sdram_dq_oe_n             <= (others => '0');
            sdram_state           <= IDLE;
          when CLOSE_FOR_REFRESH   => sdram_emit_command(CMD_NOP);
          when CLOSE_FOR_REFRESH_2 => sdram_emit_command(CMD_NOP);
          when CLOSE_FOR_REFRESH_3 => sdram_emit_command(CMD_NOP);
          when CLOSE_FOR_REFRESH_4 => sdram_emit_command(CMD_NOP);
          when REFRESH_1 =>
            active_row            <= '0';
            refresh_due_countdown <= refresh_interval - 1;
          when REFRESH_2 => sdram_emit_command(CMD_NOP);
          when REFRESH_3 => sdram_emit_command(CMD_NOP);
          when REFRESH_4 => sdram_emit_command(CMD_NOP);
          when REFRESH_5 => sdram_emit_command(CMD_NOP);
          when REFRESH_6 => sdram_emit_command(CMD_NOP);
          when REFRESH_7 => sdram_emit_command(CMD_NOP);
          when REFRESH_8 => sdram_emit_command(CMD_NOP);
          when REFRESH_9 =>
            sdram_emit_command(CMD_NOP);
            report "BUSY: Clearing BUSY after refresh";
            busy        <= '0';
            sdram_state <= IDLE;
          when others =>
            sdram_emit_command(CMD_NOP);
        end case;
      end if;

    end if;
  end process;

end tacoma_narrows;
