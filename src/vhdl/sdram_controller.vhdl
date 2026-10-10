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
  type sdram_state_t is (REFRESH_1,
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
                         -- CPU path and shared states (#949), likewise
                         OPEN_CHK,
                         FILL_RD,
                         FILL_DRAIN,
                         FLUSH_WR,
                         LUMP_W1,
                         LUMP_W2,
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

  signal resets : unsigned(7 downto 0) := x"00";

  ---------------------------------------------------------------------------
  -- CPU path (#949): a row open in every bank, posted writes, a small line
  -- cache with prefetch, and the exported "current cache line".
  ---------------------------------------------------------------------------
  -- Address map (CPU and LUMP alike): word column = address(10 downto 1),
  -- row = address(25 downto 13), bank = address(12 downto 11) xor
  -- address(17 downto 16).  Consecutive 2 KB rows go to different banks,
  -- and the XOR also puts areas 64 KB apart (a copy's source and
  -- destination, say) in different banks, so both rows stay open.
  -- SDRAM timing, in 162 MHz cycles between commands
  constant tRAS_C : integer := 7;
  constant tRP_C  : integer := 3;
  constant tRCD_C : integer := 3;
  constant tRRD_C : integer := 2;
  constant tWR_C  : integer := 2;
  type cnt4_t is array (0 to 3) of integer range 0 to 15;
  type row4_t is array (0 to 3) of unsigned(12 downto 0);
  signal bk_open : std_logic_vector(0 to 3) := "0000";
  signal bk_row  : row4_t := (others => (others => '0'));
  -- cycles since the bank's last ACTIVATE / WRITE / PRECHARGE (saturating)
  signal bk_act, bk_wr, bk_pre : cnt4_t := (others => 15);
  signal g_act : integer range 0 to 15 := 15;   -- since any ACTIVATE
  signal all_closable : std_logic := '0';       -- PRECHARGE ALL allowed now
  -- OPEN_CHK: get o_row open in o_bank (tRCD done), then go to o_ret
  signal o_bank : unsigned(1 downto 0) := "00";
  signal o_row  : unsigned(12 downto 0) := (others => '0');
  signal o_ret  : sdram_state_t := IDLE;

  -- Line cache: NL lines of 8 bytes, round-robin replacement.  Written
  -- through by CPU writes (and by posted writes when a line arrives), so a
  -- valid line is always current.
  constant NL : integer := 8;
  type ltag_t  is array (0 to NL - 1) of unsigned(26 downto 3);
  type ldata_t is array (0 to NL - 1) of unsigned(63 downto 0);
  signal c_tag  : ltag_t := (others => (others => '1'));
  signal c_val  : std_logic_vector(0 to NL - 1) := (others => '0');
  signal c_data : ldata_t := (others => (others => '0'));
  signal c_rr   : integer range 0 to NL - 1 := 0;
  -- The line fill in progress (one READ, 4 words)
  signal fill_active : std_logic := '0';
  signal fl_tag   : unsigned(26 downto 3) := (others => '1');
  signal fl_slot  : integer range 0 to NL - 1 := 0;
  signal fl_word  : integer range 0 to 3 := 0;
  signal fl_rd_issue : std_logic := '0';
  signal fl_rd_pipe  : std_logic_vector(0 to 8) := (others => '0');

  -- Posted writes: NW line buffers with byte masks.  w_cur is the one last
  -- written; the others are written out as soon as the bus is free.
  constant NW : integer := 2;
  type wtag_t  is array (0 to NW - 1) of unsigned(26 downto 3);
  type wdata_t is array (0 to NW - 1) of unsigned(63 downto 0);
  type wmask_t is array (0 to NW - 1) of std_logic_vector(7 downto 0);
  type wage_t  is array (0 to NW - 1) of integer range 0 to 63;
  signal w_tag  : wtag_t := (others => (others => '1'));
  signal w_data : wdata_t := (others => (others => '0'));
  signal w_mask : wmask_t := (others => (others => '0'));
  signal w_age  : wage_t := (others => 0);
  signal w_cur  : integer range 0 to NW - 1 := 0;
  signal w_stall : std_logic := '0';            -- a write waits for a buffer
  -- the buffer being written out by FLUSH_WR (copied out of w_*)
  signal f_tag  : unsigned(26 downto 3) := (others => '0');
  signal f_data : unsigned(63 downto 0) := (others => '0');
  signal f_mask : std_logic_vector(7 downto 0) := (others => '0');
  signal f_word : integer range 0 to 3 := 0;

  -- CPU request handling: R_LOOK compares, R_DECIDE acts, R_WAIT waits
  -- for a line fill
  type rs_t is (R_IDLE, R_LOOK, R_DECIDE, R_WAIT);
  signal rs : rs_t := R_IDLE;
  signal lk_c : std_logic_vector(0 to NL - 1) := (others => '0');
  signal lk_w : std_logic_vector(0 to NW - 1) := (others => '0');
  signal want_fill : std_logic := '0';          -- fill the latched line
  signal last_pub : unsigned(26 downto 3) := (others => '1');

  -- The exported line (current_cache_line*), and the next/prev requests
  signal exp_addr  : unsigned(26 downto 3) := (others => '1');
  signal exp_valid : std_logic := '0';
  signal exp_data  : unsigned(63 downto 0) := (others => '0');
  signal x_look, x_use : std_logic := '0';
  signal x_addr : unsigned(26 downto 3) := (others => '1');
  signal x_hit  : std_logic_vector(0 to NL - 1) := (others => '0');
  signal x_want : std_logic := '0';             -- fill x_addr, then export it
  signal x_down : std_logic := '0';

  -- Prefetch: after the CPU reads line B (or, with cflags(1), after the
  -- exported line moves to B), make sure lines B+1..B+PF (B-1.. when the
  -- reads go down) are cached.
  constant PF : integer := 4;
  signal pf_base : unsigned(26 downto 3) := (others => '1');
  signal pf_down : std_logic := '0';
  signal pf_k    : integer range 0 to PF + 1 := PF + 1;  -- PF + 1: idle
  signal pf_cand : unsigned(26 downto 3) := (others => '1');
  signal pf_chk  : std_logic := '0';
  signal pf_chk2 : std_logic := '0';
  signal pf_present : std_logic := '0';
  signal pf_want : std_logic := '0';
  signal pf_line : unsigned(26 downto 3) := (others => '1');
  -- $C000015 (write) / $C000017 (read): bit 0 prefetch after CPU reads,
  -- bit 1 also prefetch past the exported line when the CPU moves it on
  -- (the early next-line fetch; off by default until the CPU side is known
  -- to use it well)
  signal cflags : std_logic_vector(7 downto 0) := x"01";
  signal hits, misses : unsigned(15 downto 0) := (others => '0');

  -- VIC-IV line fetches (8 bytes at vic_bank:viciv_addr, delivered on
  -- pixelclock as 8 consecutive strobes).  A cached line answers at once;
  -- otherwise it is fetched into the cache like a CPU line.
  signal vic_bank  : unsigned(7 downto 0) := x"00";   -- $C000024
  signal vic_req_s : std_logic := '0';
  signal vic_last  : std_logic := '0';
  signal vic_tag   : unsigned(26 downto 3) := (others => '1');
  signal vic_look, vic_use, vic_want : std_logic := '0';
  signal vic_hit   : std_logic_vector(0 to NL - 1) := (others => '0');
  signal vic_buf   : unsigned(63 downto 0) := (others => '0');
  signal vic_ready : std_logic := '0';                 -- toggles: vic_buf full
  signal vic_ready_seen : std_logic := '0';            -- (pixelclock side)
  signal vic_next  : integer range 0 to 8 := 8;
  signal vic_count : unsigned(15 downto 0) := (others => '0');

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

  -- Training.  Test words live at the top 8 bytes of the SDRAM: with the
  -- address map below, that is bank 0, the last row, word columns
  -- 1020-1023.
  --
  -- 1. Coarse: 8 phases, 45 degrees (35 fine steps) apart.  At each, one
  --    READ (done twice, results must agree) captures 7 words around the
  --    burst from both crossing paths, and finds where the 4-word pattern
  --    sits: that gives the read cycle for each path, or "not clean".
  --    The direct path is captured from dq_x itself (held on the direct
  --    path while training), the other from dq_f, so what is measured is
  --    exactly the crossing used afterwards.
  -- 2. Window, for each path on its own: the longest run of coarse phases
  --    where that path is clean with the same read cycle.  Each path's
  --    window ends at the pads' invalid time on one side and at its own
  --    crossing point on the other (the two crossing points are half a
  --    cycle apart).  The path with the longer run is used (direct path on
  --    a tie).
  -- 3. Fine: step out from its first and last coarse phase one fine step at
  --    a time, while that path stays clean at that cycle, to find the exact
  --    edges, and take the middle.  A final test there confirms it.
  constant TR_STEPS    : integer := 280;   -- fine steps per clock162 cycle
                                           -- (VCO 810 MHz / 5, 1/56 VCO each)
  constant TR_COARSE   : integer := 35;    -- fine steps per coarse step
  constant TR_PATTERN  : unsigned(63 downto 0) := x"3CA5C35AA53C5AC3";
  constant TR_BANK     : unsigned(1 downto 0) := "00";  -- (row all ones)
  type tr_state_t is (T_START, T_PROBED, T_OPENED, T_SAVED, T_SAVE_READ,
                      T_WRITTEN, T_CO_TEST, T_CO_REC, T_CO_NEXT,
                      T_RUN, T_RUN_DONE, T_RUN_GO,
                      T_FL_STEP, T_FL_T, T_FL_REC, T_FR_GO, T_FR_STEP, T_FR_T, T_FR_REC,
                      T_MID, T_MID2, T_MID3, T_PATH_GO, T_PATH_T, T_PATH_REC,
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
  signal tr_rc, tr_bc  : unsigned(1 downto 0) := "00";  -- run's read cycle
  signal tr_h          : std_logic := '0';   -- path being scanned / chosen
  signal tr_bs0        : integer range 0 to 7 := 0;     -- path 0's best run
  signal tr_bl0        : integer range 0 to 8 := 0;
  signal tr_bc0        : unsigned(1 downto 0) := "00";
  signal tr_fc         : integer range 0 to TR_COARSE := 0;
  signal tr_left       : integer range 0 to TR_STEPS-1 := 0;
  signal tr_right      : integer range 0 to TR_STEPS-1 := 0;
  signal tr_width      : integer range 0 to TR_STEPS := 0;
  signal tr_centre     : integer range 0 to TR_STEPS-1 := 0;

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
  -- A test result is clean on path h at read cycle c
  function tr_clean(h : std_logic; va : std_logic; ca : unsigned(1 downto 0);
                    vb : std_logic; cb : unsigned(1 downto 0);
                    c : unsigned(1 downto 0)) return boolean is
  begin
    if h = '0' then return va = '1' and ca = c;
    else return vb = '1' and cb = c; end if;
  end function;
  -- The address map (see above), for whole addresses and for line tags
  function a_bank(a : unsigned(26 downto 0)) return unsigned is
  begin
    return a(12 downto 11) xor a(17 downto 16);
  end function;
  function l_bank(t : unsigned(26 downto 3)) return unsigned is
  begin
    return t(12 downto 11) xor t(17 downto 16);
  end function;
  function l_row(t : unsigned(26 downto 3)) return unsigned is
  begin
    return t(25 downto 13);
  end function;
  function byte_of(d : unsigned(63 downto 0); i : integer) return unsigned is
  begin
    return d(8 * i + 7 downto 8 * i);
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
    variable v_line   : unsigned(63 downto 0);
    variable v_fill_done : boolean;
    variable v_hit    : integer range -1 to NL - 1;
    variable v_wh     : integer range -1 to NW - 1;
    variable v_free   : integer range -1 to NW - 1;
    variable v_idx    : integer range 0 to 7;
    variable v_b      : integer range 0 to 3;
    variable v_byte   : unsigned(7 downto 0);
    variable v_hi     : unsigned(7 downto 0);
    variable v_mask   : std_logic_vector(7 downto 0);
    variable v_pf_go  : boolean;
    variable v_pf_base : unsigned(26 downto 3);
    variable v_pf_down : std_logic;

    procedure publish(b, bh : unsigned(7 downto 0)) is
    begin
      rdata <= b;
      rdata_hi <= bh;
      data_ready_toggle <= not last_data_ready_toggle;
      last_data_ready_toggle <= not last_data_ready_toggle;
      read_latched <= '0';
      rs <= R_IDLE;
    end procedure;
    -- The exported line, and the slow_devices/CPU ports for it, together
    -- (slow_devices takes its "next byte" from the line when it sees the
    -- read's data_ready_toggle, so they must change in the same cycle)
    procedure set_export(t : unsigned(26 downto 3); d : unsigned(63 downto 0)) is
    begin
      exp_addr <= t;
      exp_data <= d;
      exp_valid <= '1';
      current_cache_line_address <= t;
      for k in 0 to 7 loop
        current_cache_line(k) <= d(8 * k + 7 downto 8 * k);
      end loop;
      current_cache_line_valid <= '1';
    end procedure;
    -- Prefetch from line t on, if enabled, going the way the reads go
    procedure prefetch_from(t : unsigned(26 downto 3)) is
    begin
      if cflags(0) = '1' and t /= last_pub then
        v_pf_go := true;
        v_pf_base := t;
        v_pf_down := '0';
        if t = last_pub - 1 then v_pf_down := '1'; end if;
        last_pub <= t;
      end if;
    end procedure;

    -- Start a line fill (one READ) of line t into the next cache slot
    procedure start_fill(t : unsigned(26 downto 3)) is
    begin
      fill_active <= '1';
      fl_tag  <= t;
      fl_slot <= c_rr;
      fl_word <= 0;
      c_val(c_rr) <= '0';
      c_tag(c_rr) <= t;
      if c_rr = NL - 1 then c_rr <= 0; else c_rr <= c_rr + 1; end if;
      o_bank <= l_bank(t);
      o_row  <= l_row(t);
      o_ret  <= FILL_RD;
      sdram_state <= OPEN_CHK;
    end procedure;
    -- Start writing out posted-write buffer j (copied out, so it is free
    -- again at once)
    procedure start_flush(j : integer) is
    begin
      f_tag  <= w_tag(j);
      f_data <= w_data(j);
      f_mask <= w_mask(j);
      f_word <= 0;
      w_mask(j) <= (others => '0');
      o_bank <= l_bank(w_tag(j));
      o_row  <= l_row(w_tag(j));
      o_ret  <= FLUSH_WR;
      sdram_state <= OPEN_CHK;
    end procedure;

    -- PRECHARGE ALL allowed in this cycle (tRAS and tWR in every open bank)
    impure function closable return boolean is
    begin
      for b in 0 to 3 loop
        if bk_open(b) = '1' and (bk_act(b) < tRAS_C or bk_wr(b) < tWR_C) then
          return false;
        end if;
      end loop;
      return true;
    end function;
    impure function all_precharged return boolean is
    begin
      for b in 0 to 3 loop
        if bk_open(b) = '1' or bk_pre(b) < tRP_C then return false; end if;
      end loop;
      return true;
    end function;
    variable tva, tvb : std_logic;
    variable tca, tcb : unsigned(1 downto 0);
  begin
    if rising_edge(clock162) then

      sdram_dq_oe_n <= (others => '1');
      sdram_dqml <= '1';
      sdram_dqmh <= '1';
      -- No command unless a state below issues one (the command outputs are
      -- registers: a state that issued none used to repeat the last one,
      -- e.g. a second AUTO REFRESH in REFRESH_1)
      sdram_emit_command(CMD_NOP);

      -- LUMP: single-cycle strobes default low
      lump_q_pop       <= '0';
      lump_rdata_valid <= '0';
      lump_wdata_req   <= '0';
      lump_cmd_done    <= '0';
      lump_error       <= '0';
      lump_rd_issue    <= '0';
      fl_rd_issue      <= '0';
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
      lump_go     <= lump_q_valid and (not lump_q_op(1)) and (not lump_q_pop);
      lump_inv_go <= lump_q_valid and lump_q_op(1) and (not lump_q_pop);
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
      if tr_active = '1' then
        -- training measures the direct path through dq_x itself
        x_h  <= '0';
        rd_c <= trained_c;
      elsif tr_ok = '1' then
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

      -- Bank timers (saturating; a command below sets its timer to 1)
      for b in 0 to 3 loop
        if bk_act(b) /= 15 then bk_act(b) <= bk_act(b) + 1; end if;
        if bk_wr(b)  /= 15 then bk_wr(b)  <= bk_wr(b) + 1; end if;
        if bk_pre(b) /= 15 then bk_pre(b) <= bk_pre(b) + 1; end if;
      end loop;
      if g_act /= 15 then g_act <= g_act + 1; end if;

      -- Line fill data capture, timed exactly as for LUMP (see below)
      fl_rd_pipe(0) <= fl_rd_issue;
      fl_rd_pipe(1 to 8) <= fl_rd_pipe(0 to 7);
      v_fill_done := false;
      v_pf_go := false;
      if (rd_c = "00" and (fl_rd_pipe(5) or fl_rd_pipe(6) or fl_rd_pipe(7) or fl_rd_pipe(8)) = '1')
        or (rd_c = "01" and (fl_rd_pipe(4) or fl_rd_pipe(5) or fl_rd_pipe(6) or fl_rd_pipe(7)) = '1')
        or (rd_c = "10" and (fl_rd_pipe(3) or fl_rd_pipe(4) or fl_rd_pipe(5) or fl_rd_pipe(6)) = '1')
        or (rd_c = "11" and (fl_rd_pipe(2) or fl_rd_pipe(3) or fl_rd_pipe(4) or fl_rd_pipe(5)) = '1')
      then
        if fl_word /= 3 then
          c_data(fl_slot)(16 * fl_word + 15 downto 16 * fl_word) <= dq_x;
          fl_word <= fl_word + 1;
        else
          -- Last word: the line is complete.  Posted writes to it that are
          -- still buffered go over the top.
          v_line := c_data(fl_slot);
          v_line(63 downto 48) := dq_x;
          for j in 0 to NW - 1 loop
            if w_tag(j) = fl_tag then
              for k in 0 to 7 loop
                if w_mask(j)(k) = '1' then
                  v_line(8 * k + 7 downto 8 * k) := w_data(j)(8 * k + 7 downto 8 * k);
                end if;
              end loop;
            end if;
          end loop;
          c_data(fl_slot) <= v_line;
          c_val(fl_slot) <= '1';
          -- (and no other copy of this line)
          for i in 0 to NL - 1 loop
            if i /= fl_slot and c_tag(i) = fl_tag then c_val(i) <= '0'; end if;
          end loop;
          fl_word <= 0;
          fill_active <= '0';
          v_fill_done := true;
        end if;
      end if;

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
        when x"17" => nonram_val <= unsigned(cflags);
        when x"20" => nonram_val <= hits(7 downto 0);
        when x"21" => nonram_val <= hits(15 downto 8);
        when x"22" => nonram_val <= misses(7 downto 0);
        when x"23" => nonram_val <= misses(15 downto 8);
        when x"24" => nonram_val <= vic_bank;
        when x"25" => nonram_val <= vic_count(7 downto 0);
        when x"26" => nonram_val <= vic_count(15 downto 8);
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
        -- (look-up next cycle: not here, as address comes from the pixel
        -- clock domain and the compare would lengthen that crossing)
        if address(26) = '0' then rs <= R_LOOK; end if;
      end if;
      if read_request = '0' and write_request = '1' and write_latched = '0' and read_latched = '0' then
        report "Latching write request";
        report "BUSY: Asserting busy";
        busy          <= '1';
        write_latched <= '1';
        latched_addr  <= address;
        wdata_latched <= wdata;
        -- (look-up next cycle: not here, as address comes from the pixel
        -- clock domain and the compare would lengthen that crossing)
        if address(26) = '0' then rs <= R_LOOK; end if;

        -- The exported line stops being valid at once (until the write has
        -- been applied, if it is to that line): the CPU may read it
        -- directly within a few cycles.  (No address compare here: address
        -- comes from the pixel clock domain.)
        current_cache_line_valid <= '0';
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
            sdram_emit_command(CMD_NOP);
            v_wh := -1;                 -- (write buffer to flush, if any)
            if w_stall = '1' or lump_q_valid = '1' then
              -- urgently: a write waits for a buffer, or LUMP waits for
              -- the buffers to be empty
              for j in 0 to NW - 1 loop
                if w_mask(j) /= x"00" and (j /= w_cur or v_wh = -1) then v_wh := j; end if;
              end loop;
            end if;
            if tr_req = '1' and ps_locked_s2 = '1' then
              -- Read capture training.  It starts with a PRECHARGE ALL, so
              -- waits until that is allowed (and, with the controller
              -- working normally meanwhile, for the capture clock's MMCM).
              if closable then
                tr_req      <= '0';
                tr_active   <= '1';
                tr_st       <= T_START;
                sdram_state <= TRAIN;
              end if;
            elsif refresh_due = '1' then
              -- every bank closed (and tRP over) for the AUTO REFRESH
              if bk_open /= "0000" then
                if closable then
                  sdram_emit_command(CMD_PRECHARGE);  -- (A10 = 1: all banks)
                  for b in 0 to 3 loop
                    if bk_open(b) = '1' then bk_pre(b) <= 1; end if;
                  end loop;
                  bk_open <= "0000";
                end if;
              elsif all_precharged then
                sdram_emit_command(CMD_AUTO_REFRESH);
                sdram_state <= REFRESH_1;
              end if;
            elsif (read_latched = '1' or write_latched = '1') and latched_addr(26) = '1' then
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
              elsif write_latched = '1' and latched_addr(7 downto 0) = x"15" then
                -- $C000015: CPU path flags (see cflags)
                cflags <= std_logic_vector(wdata_latched);
                write_latched <= '0';
              elsif write_latched = '1' and latched_addr(7 downto 0) = x"24" then
                -- $C000024: VIC-IV bank (address bits 26-19 of its fetches)
                vic_bank <= wdata_latched;
                write_latched <= '0';
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
            elsif vic_want = '1' and fill_active = '0' then
              -- the VIC-IV is waiting for this line (the display can't wait)
              start_fill(vic_tag);
            elsif want_fill = '1' and fill_active = '0' then
              -- the CPU's read missed: fetch its line
              want_fill <= '0';
              start_fill(latched_addr(26 downto 3));
            elsif x_want = '1' and fill_active = '0' then
              -- the CPU moved the exported line on to one not cached
              start_fill(x_addr);
            elsif v_wh /= -1 then
              start_flush(v_wh);
            elsif (lump_go or lump_inv_go) = '1' and w_mask(0) = x"00" and w_mask(1) = x"00" then
              -- LUMP has the lowest priority: refresh, CPU requests and
              -- posted writes are always served first.
              lump_q_pop <= '1';
              lump_go <= '0';
              lump_inv_go <= '0';
              if lump_inv_go = '1' or lump_is_write_pre = '1' then
                -- the CPU's cached copies may be stale after this
                c_val <= (others => '0');
                exp_valid <= '0';
                exp_addr <= (others => '1');
                current_cache_line_valid <= '0';
                current_cache_line_address <= (others => '1');
                pf_k <= PF + 1;
                pf_chk <= '0';
                pf_chk2 <= '0';
                pf_want <= '0';
              end if;
              if lump_inv_go = '1' then
                report "LUMP: Invalidating read cache";
                lump_cmd_done <= '1';
              else
                report "LUMP: Starting burst @ $" & to_hexstring(lump_q_addr);
                lump_active   <= '1';
                lump_bank     <= a_bank(lump_q_addr);
                lump_row      <= lump_q_addr(25 downto 13);
                lump_col      <= lump_q_addr(10 downto 1);
                lump_phase    <= "00";
                lump_is_write <= lump_is_write_pre;
                lump_cnt      <= lump_cnt_init;
                o_bank <= a_bank(lump_q_addr);
                o_row  <= lump_q_addr(25 downto 13);
                if lump_is_write_pre = '1' then o_ret <= LUMP_W1; else o_ret <= LUMP_READ; end if;
                sdram_state <= OPEN_CHK;
              end if;
            else
              -- background: posted writes the CPU has moved on from, then
              -- prefetch
              for j in 0 to NW - 1 loop
                if w_mask(j) /= x"00" and v_wh = -1
                  and (j /= w_cur or w_mask(j) = x"FF" or w_age(j) >= 32) then
                  v_wh := j;
                end if;
              end loop;
              if v_wh /= -1 then
                start_flush(v_wh);
              elsif pf_want = '1' and fill_active = '0' then
                pf_want <= '0';
                start_fill(pf_line);
              end if;
            end if;

          when OPEN_CHK =>
            -- Open o_row in bank o_bank, then on to o_ret once a READ or
            -- WRITE may follow (tRCD).  A different open row there is closed
            -- first (tRAS, tWR), then tRP and tRRD before the ACTIVATE.
            sdram_state <= OPEN_CHK;
            sdram_emit_command(CMD_NOP);
            v_b := to_integer(o_bank);
            if bk_open(v_b) = '1' and bk_row(v_b) = o_row then
              if bk_act(v_b) >= tRCD_C - 1 then
                sdram_state <= o_ret;
              end if;
            elsif bk_open(v_b) = '1' then
              if bk_act(v_b) >= tRAS_C and bk_wr(v_b) >= tWR_C then
                sdram_emit_command(CMD_PRECHARGE);
                sdram_a(10) <= '0';             -- this bank only
                sdram_ba <= o_bank;
                bk_open(v_b) <= '0';
                bk_pre(v_b) <= 1;
              end if;
            elsif bk_pre(v_b) >= tRP_C and g_act >= tRRD_C then
              sdram_emit_command(CMD_ACTIVATE_ROW);
              sdram_ba <= o_bank;
              sdram_a  <= o_row;
              bk_open(v_b) <= '1';
              bk_row(v_b) <= o_row;
              bk_act(v_b) <= 1;
              g_act <= 1;
            end if;

          when FILL_RD =>
            -- One READ (burst of 4 words) for the line fill; the words are
            -- captured by the fl_rd_pipe logic above
            sdram_emit_command(CMD_READ);
            sdram_ba <= l_bank(fl_tag);
            sdram_a(12 downto 10) <= "000";     -- (A10 = 0: no auto precharge)
            sdram_a(9 downto 2) <= fl_tag(10 downto 3);
            sdram_a(1 downto 0) <= "00";
            sdram_dqml <= '0'; sdram_dqmh <= '0';
            fl_rd_issue <= '1';
            read_jobs <= read_jobs + 1;
            sdram_state <= FILL_DRAIN;
          when FILL_DRAIN =>
            sdram_emit_command(CMD_NOP);
            sdram_dqml <= '0'; sdram_dqmh <= '0';
            sdram_state <= FILL_DRAIN;
            if fl_rd_issue = '0' and fl_rd_pipe = "000000000" then
              sdram_state <= IDLE;
            end if;

          when FLUSH_WR =>
            -- Write out a posted line: one WRITE per word with any byte to
            -- write (DQM masks the others), one per cycle
            sdram_state <= FLUSH_WR;
            sdram_emit_command(CMD_NOP);
            if f_mask(2 * f_word + 1 downto 2 * f_word) /= "00" then
              sdram_emit_command(CMD_WRITE);
              sdram_ba <= l_bank(f_tag);
              sdram_a(12 downto 10) <= "000";
              sdram_a(9 downto 2) <= f_tag(10 downto 3);
              sdram_a(1 downto 0) <= to_unsigned(f_word, 2);
              sdram_dq_out <= f_data(16 * f_word + 15 downto 16 * f_word);
              sdram_dq_oe_n <= (others => '0');
              sdram_dqml <= not f_mask(2 * f_word);
              sdram_dqmh <= not f_mask(2 * f_word + 1);
              bk_wr(to_integer(l_bank(f_tag))) <= 1;
              write_jobs <= write_jobs + 1;
            end if;
            if f_word = 3 then
              sdram_state <= IDLE;
            else
              f_word <= f_word + 1;
            end if;

          when LUMP_W1 =>
            -- Request the first write word now: it is sampled two edges
            -- later, which is exactly when the first WRITE is emitted.  The
            -- remaining requests then follow one per cycle.
            sdram_emit_command(CMD_NOP);
            lump_wdata_req <= '1';
            -- (words - 1) further requests: lump_cnt is words - 2 here
            lump_wreq_cnt  <= lump_cnt;
            sdram_state <= LUMP_W2;
          when LUMP_W2 =>
            sdram_emit_command(CMD_NOP);
            sdram_state <= LUMP_WRITE;
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
            bk_wr(to_integer(lump_bank)) <= 1;
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
                -- dq_x takes at edges T+3..T+9 on each path (word i = edge
                -- T+3+i), so a burst starting at word j of these 7 is read
                -- cycle 3-j.  Path 0: dq_x itself (x_h is held at 0 while
                -- training), so one edge later; path 1: dq_f, which is what
                -- dq_x would take at the same edge.
                sdram_dqml <= '0'; sdram_dqmh <= '0';
                if tr_k >= 4 and tr_k <= 10 then
                  wa <= dq_x & wa(111 downto 16);
                end if;
                if tr_k >= 3 and tr_k <= 9 then
                  wb <= dq_f & wb(111 downto 16);
                end if;
                if tr_k = 11 then tr_st <= tr_ret; else tr_k <= tr_k + 1; end if;
              when M_WRITE =>
                -- Four WRITEs (burst length 1), test or saved words; the
                -- row must be open.  Then tWR, then tr_ret.
                sdram_emit_command(CMD_WRITE);
                sdram_ba <= TR_BANK;
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
                sdram_ba <= TR_BANK;
                sdram_a <= (others => '1');
                tr_r <= '0';
                tr_cnt <= 2;                  -- tRCD
                tr_ret <= T_TEST2;
                tr_st <= M_WAIT;
              when T_TEST2 =>
                sdram_emit_command(CMD_READ);
                sdram_ba <= TR_BANK;
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
                bk_open <= "0000";
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
                sdram_ba <= TR_BANK;
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
                  tr_h <= '0';
                  tr_st <= T_RUN;
                else
                  tr_st <= T_CO_TEST;
                end if;

              -- 2. For path tr_h, the longest run of coarse phases clean at
              --    one read cycle, going round twice
              when T_RUN =>
                if tr_h = '0' then
                  tva := cmap(tr_i mod 8)(2); tca := cmap(tr_i mod 8)(1 downto 0);
                else
                  tva := cmap(tr_i mod 8)(6); tca := cmap(tr_i mod 8)(5 downto 4);
                end if;
                if tva = '1' then
                  if tr_run = 0 or tca /= tr_rc then
                    -- a new run starts here
                    tr_run <= 1; tr_rs <= tr_i mod 8; tr_rc <= tca;
                    if tr_bl = 0 then
                      tr_bl <= 1; tr_bs <= tr_i mod 8; tr_bc <= tca;
                    end if;
                  elsif tr_run < 8 then
                    tr_run <= tr_run + 1;
                    if tr_run + 1 > tr_bl then
                      tr_bl <= tr_run + 1; tr_bs <= tr_rs; tr_bc <= tr_rc;
                    end if;
                  end if;
                else
                  tr_run <= 0;
                end if;
                if tr_i /= 15 then
                  tr_i <= tr_i + 1;
                elsif tr_h = '0' then
                  -- keep path 0's best, then the same for path 1
                  tr_bl0 <= tr_bl; tr_bs0 <= tr_bs; tr_bc0 <= tr_bc;
                  tr_i <= 0; tr_run <= 0; tr_bl <= 0; tr_rs <= 0; tr_bs <= 0;
                  tr_h <= '1';
                else
                  tr_st <= T_RUN_DONE;
                end if;
              when T_RUN_DONE =>
                -- the longer run of the two (path 0 on a tie)
                if tr_bl0 >= tr_bl then
                  tr_h <= '0'; tr_bl <= tr_bl0; tr_bs <= tr_bs0; tr_bc <= tr_bc0;
                end if;
                tr_st <= T_RUN_GO;
              when T_RUN_GO =>
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
                if tr_clean(tr_h, t_va, t_ca, t_vb, t_cb, tr_bc) then
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
                if tr_clean(tr_h, t_va, t_ca, t_vb, t_cb, tr_bc) then
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
                tr_st <= T_PATH_GO;

              -- 4. Go to the middle, and check it there
              when T_PATH_GO =>
                tr_target <= tr_centre;
                tr_ret_n <= T_PATH_T;
                tr_st <= M_SEEK;
              when T_PATH_T =>
                tr_ret_t <= T_PATH_REC;
                tr_st <= T_TEST0;
              when T_PATH_REC =>
                tr_ok <= '1';
                trained_h <= tr_h;
                trained_c <= tr_bc;
                if tr_width < 16
                  or not tr_clean(tr_h, t_va, t_ca, t_vb, t_cb, tr_bc) then
                  tr_weak <= '1';
                else
                  tr_weak <= '0';
                end if;
                tr_st <= T_RESTORE;

              when T_RESTORE =>
                if tr_had_ok = '1' then
                  sdram_emit_command(CMD_ACTIVATE_ROW);
                  sdram_ba <= TR_BANK;
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
                -- (every bank closed, and tRP over); the read path may have
                -- changed, and the test row was rewritten: drop the cache
                bk_open <= "0000";
                bk_pre <= (others => tRP_C);
                c_val <= (others => '0');
                exp_valid <= '0';
                current_cache_line_valid <= '0';
                tr_active <= '0';
                if tr_mode = "00" then
                  tr_count <= tr_count + 1;
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
          when REFRESH_1 =>
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
            sdram_state <= IDLE;
          when others =>
            sdram_emit_command(CMD_NOP);
        end case;
      end if;

      -------------------------------------------------------------------------
      -- CPU side (#949).  This runs alongside whatever the SDRAM itself is
      -- doing: reads that hit, and writes, never wait for it.
      -------------------------------------------------------------------------
      next_toggle_drive <= expansionram_current_cache_line_next_toggle;
      prev_toggle_drive <= expansionram_current_cache_line_prev_toggle;
      v_idx := to_integer(latched_addr(2 downto 0));
      for j in 0 to NW - 1 loop
        if w_age(j) /= 63 then w_age(j) <= w_age(j) + 1; end if;
      end loop;

      if sdram_prepped = '1' and tr_active = '0' then

        -- A fill has just completed: a read waiting for that line gets it
        -- now; the exported line moves to it if the CPU asked for it
        if v_fill_done then
          if rs /= R_IDLE and read_latched = '1' and fl_tag = latched_addr(26 downto 3) then
            publish(byte_of(v_line, v_idx), byte_of(v_line, (v_idx + 1) mod 8));
            set_export(fl_tag, v_line);
            prefetch_from(fl_tag);
          elsif rs = R_WAIT or rs = R_DECIDE then
            rs <= R_LOOK;               -- (look again)
          end if;
          if vic_want = '1' and fl_tag = vic_tag then
            vic_buf <= v_line;
            vic_want <= '0';
            vic_ready <= not vic_ready;
          end if;
          if x_want = '1' and fl_tag = x_addr and write_latched = '0' and write_request = '0' then
            set_export(x_addr, v_line);
            x_want <= '0';
            if cflags(1) = '1' then prefetch_from(x_addr); end if;
          end if;
        end if;

        case rs is
          when R_IDLE =>
            if (read_latched = '1' or write_latched = '1') and latched_addr(26) = '0' then
              rs <= R_LOOK;
            end if;
          when R_LOOK =>
            for i in 0 to NL - 1 loop
              if c_tag(i) = latched_addr(26 downto 3) then lk_c(i) <= '1'; else lk_c(i) <= '0'; end if;
            end loop;
            for j in 0 to NW - 1 loop
              if w_tag(j) = latched_addr(26 downto 3) then lk_w(j) <= '1'; else lk_w(j) <= '0'; end if;
            end loop;
            rs <= R_DECIDE;
          when R_DECIDE =>
            if v_fill_done then
              null;                     -- (handled above)
            elsif read_latched = '1' then
              v_wh := -1;
              v_hit := -1;
              for j in 0 to NW - 1 loop
                if lk_w(j) = '1' and w_mask(j)(v_idx) = '1' then v_wh := j; end if;
              end loop;
              for i in NL - 1 downto 0 loop
                if lk_c(i) = '1' and c_val(i) = '1' then v_hit := i; end if;
              end loop;
              if v_hit /= -1 then
                -- (a cached line already has any posted writes in it)
                hits <= hits + 1;
                publish(byte_of(c_data(v_hit), v_idx), byte_of(c_data(v_hit), (v_idx + 1) mod 8));
                set_export(latched_addr(26 downto 3), c_data(v_hit));
                prefetch_from(latched_addr(26 downto 3));
              elsif v_wh /= -1 then
                hits <= hits + 1;
                publish(byte_of(w_data(v_wh), v_idx), byte_of(w_data(v_wh), (v_idx + 1) mod 8));
              else
                misses <= misses + 1;
                if not (fill_active = '1' and fl_tag = latched_addr(26 downto 3)) then
                  want_fill <= '1';
                end if;
                rs <= R_WAIT;
              end if;
            elsif write_latched = '1' then
              -- Posted write: into the buffer already holding this line, or
              -- a free one; if neither, wait for one to be written out
              v_wh := -1;
              v_free := -1;
              for j in 0 to NW - 1 loop
                if lk_w(j) = '1' and w_mask(j) /= x"00" then v_wh := j; end if;
                if w_mask(j) = x"00" and v_free = -1 then v_free := j; end if;
              end loop;
              if v_wh = -1 and v_free /= -1 then
                v_wh := v_free;
                v_line := (others => '0');
                v_mask := (others => '0');
              elsif v_wh /= -1 then
                v_line := w_data(v_wh);
                v_mask := w_mask(v_wh);
              end if;
              if v_wh = -1 then
                w_stall <= '1';
                rs <= R_LOOK;
              else
                w_stall <= '0';
                if rdata_16en = '1' then
                  if latched_wen_lo = '1' then
                    v_line(8 * v_idx + 7 downto 8 * v_idx) := wdata_latched;
                    v_mask(v_idx) := '1';
                  end if;
                  if latched_wen_hi = '1' and v_idx /= 7 then
                    v_line(8 * v_idx + 15 downto 8 * v_idx + 8) := wdata_hi_latched;
                    v_mask(v_idx + 1) := '1';
                  end if;
                else
                  v_line(8 * v_idx + 7 downto 8 * v_idx) := wdata_latched;
                  v_mask(v_idx) := '1';
                end if;
                w_tag(v_wh)  <= latched_addr(26 downto 3);
                w_data(v_wh) <= v_line;
                w_mask(v_wh) <= v_mask;
                w_age(v_wh)  <= 0;
                w_cur <= v_wh;
                -- write through into the cached copy (also one completing
                -- right now), and the exported line
                for i in 0 to NL - 1 loop
                  if c_tag(i) = latched_addr(26 downto 3)
                    and (c_val(i) = '1' or (v_fill_done and i = fl_slot)) then
                    for k in 0 to 7 loop
                      if v_mask(k) = '1' and (k = v_idx or (rdata_16en = '1' and k = v_idx + 1)) then
                        c_data(i)(8 * k + 7 downto 8 * k) <= v_line(8 * k + 7 downto 8 * k);
                      end if;
                    end loop;
                  end if;
                end loop;
                current_cache_line_valid <= exp_valid;
                if exp_addr = latched_addr(26 downto 3) then
                  v_line := exp_data;
                  if rdata_16en = '0' or latched_wen_lo = '1' then
                    v_line(8 * v_idx + 7 downto 8 * v_idx) := wdata_latched;
                  end if;
                  if rdata_16en = '1' and latched_wen_hi = '1' and v_idx /= 7 then
                    v_line(8 * v_idx + 15 downto 8 * v_idx + 8) := wdata_hi_latched;
                  end if;
                  set_export(exp_addr, v_line);
                end if;
                write_latched <= '0';
                rs <= R_IDLE;
              end if;
            else
              rs <= R_IDLE;
            end if;
          when R_WAIT =>
            -- (a completed fill sends us back to R_LOOK, above)
            if read_latched = '0' then rs <= R_IDLE; end if;
        end case;

        -- The CPU moved on from the exported line (next/prev)
        if next_toggle_drive /= prev_current_cache_line_next_toggle then
          prev_current_cache_line_next_toggle <= next_toggle_drive;
          x_addr <= exp_addr + 1;
          x_down <= '0';
          x_look <= '1';
          x_want <= '0';
        elsif prev_toggle_drive /= prev_current_cache_line_prev_toggle then
          prev_current_cache_line_prev_toggle <= prev_toggle_drive;
          x_addr <= exp_addr - 1;
          x_down <= '1';
          x_look <= '1';
          x_want <= '0';
        elsif x_look = '1' then
          x_look <= '0';
          x_use <= '1';
          for i in 0 to NL - 1 loop
            if c_tag(i) = x_addr then x_hit(i) <= '1'; else x_hit(i) <= '0'; end if;
          end loop;
        elsif x_use = '1' then
          x_use <= '0';
          v_hit := -1;
          for i in 0 to NL - 1 loop
            if x_hit(i) = '1' and c_val(i) = '1' then v_hit := i; end if;
          end loop;
          if v_hit /= -1 and write_latched = '0' and write_request = '0' then
            set_export(x_addr, c_data(v_hit));
            if cflags(1) = '1' then prefetch_from(x_addr); end if;
          else
            x_want <= '1';              -- (fetched, then exported)
          end if;
        end if;

        -- VIC-IV fetches: a request (the toggle comes with its address,
        -- held until the 8 bytes are delivered), then the cache look-up in
        -- two steps as for next/prev, then the line or a fill
        vic_req_s <= viciv_request_toggle;
        if vic_req_s /= vic_last and vic_look = '0' and vic_use = '0' and vic_want = '0' then
          vic_last <= vic_req_s;
          vic_tag(26) <= '0';
          vic_tag(25 downto 19) <= vic_bank(6 downto 0);
          vic_tag(18 downto 3) <= viciv_addr;
          vic_look <= '1';
          vic_count <= vic_count + 1;
        elsif vic_look = '1' then
          vic_look <= '0';
          vic_use <= '1';
          for i in 0 to NL - 1 loop
            if c_tag(i) = vic_tag then vic_hit(i) <= '1'; else vic_hit(i) <= '0'; end if;
          end loop;
        elsif vic_use = '1' then
          vic_use <= '0';
          v_hit := -1;
          for i in 0 to NL - 1 loop
            if vic_hit(i) = '1' and c_val(i) = '1' then v_hit := i; end if;
          end loop;
          if v_hit /= -1 then
            -- (cached lines have the CPU's writes in them)
            vic_buf <= c_data(v_hit);
            vic_ready <= not vic_ready;
          else
            vic_want <= '1';
          end if;
        end if;

        -- Prefetch scanner: checks one candidate line at a time
        if pf_chk2 = '1' then
          pf_chk2 <= '0';
          if pf_present = '0' then
            pf_want <= '1';
            pf_line <= pf_cand;
          end if;
          if pf_k <= PF then pf_k <= pf_k + 1; end if;
        elsif pf_chk = '1' then
          pf_chk <= '0';
          pf_chk2 <= '1';
          pf_present <= '0';
          for i in 0 to NL - 1 loop
            if c_val(i) = '1' and c_tag(i) = pf_cand then pf_present <= '1'; end if;
          end loop;
          if fill_active = '1' and fl_tag = pf_cand then pf_present <= '1'; end if;
        elsif pf_k <= PF and pf_want = '0' then
          if pf_down = '1' then
            pf_cand <= pf_base - pf_k;
          else
            pf_cand <= pf_base + pf_k;
          end if;
          pf_chk <= '1';
        end if;
        -- (prefetch_from, in this cycle, overrides the above)
        if v_pf_go then
          pf_base <= v_pf_base;
          pf_down <= v_pf_down;
          pf_k <= 1;
          pf_chk <= '0';
          pf_chk2 <= '0';
          pf_want <= '0';
        end if;
      end if;

      -- slow_devices must wait while we cannot take a request.  A write is
      -- taken into a buffer within three cycles, sooner than slow_devices
      -- can bring the next request, so it only holds things up when both
      -- buffers are in use.
      if sdram_prepped = '0' or tr_active = '1'
        or read_latched = '1' or read_request = '1'
        or (latched_addr(26) = '1' and (write_latched = '1' or write_request = '1'))
        or ((write_latched = '1' or write_request = '1')
            and w_mask(0) /= x"00" and w_mask(1) /= x"00") then
        busy <= '1';
      else
        busy <= '0';
      end if;

    end if;
  end process;

  -- VIC-IV: the 8 bytes, one per pixelclock, as the HyperRAM controller does
  process (pixelclock) is
  begin
    if rising_edge(pixelclock) then
      viciv_data_strobe <= '0';
      if vic_ready /= vic_ready_seen then
        vic_ready_seen <= vic_ready;
        viciv_data_out <= vic_buf(7 downto 0);
        viciv_data_strobe <= '1';
        vic_next <= 1;
      elsif vic_next < 8 then
        viciv_data_out <= vic_buf(8 * vic_next + 7 downto 8 * vic_next);
        viciv_data_strobe <= '1';
        vic_next <= vic_next + 1;
      end if;
    end if;
  end process;

end tacoma_narrows;
