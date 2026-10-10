library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;
use work.lumptypes.all;

------------------------------------------------------------------------------------------------
-- PGS 12MAR2023:
-- NOTE: The cache must remain enabled for writes to be reliable across all
-- MEGA65 board revisions.  This is because the revD HyperRAM chip found on
-- _some_ machines in _some_ batches requires 32-bit writes (but still can be
-- byte masked), for the writes to happen correctly.
-- See https://github.com/MJoergen/HyperRAM/issues/2 for more information.
------------------------------------------------------------------------------------------------


entity hyperram is
  generic ( in_simulation : in boolean := false;
            no_start_delay : in boolean := false);
  Port ( pixelclock : in STD_LOGIC; -- For slow devices bus interface is
         -- actually on pixelclock to reduce latencies
         -- Also pixelclock is the natural clock speed we apply to the HyperRAM.
         clock163 : in std_logic; -- Used for fast clock for HyperRAM
         clock325 : in std_logic; -- Used for fast clock for HyperRAM SERDES units

         -- Simple counter for number of requests received
         request_counter : out std_logic := '0';

         read_request : in std_logic;
         write_request : in std_logic;
         address : in unsigned(26 downto 0);
         wdata : in unsigned(7 downto 0);

         -- Optional 16-bit interface (for Amiga core use)
         -- (That it is optional, is why the write_en is inverted for the
         -- low-byte).
         -- 16-bit transactions MUST occur on an even numbered address, or
         -- else expect odd and horrible things to happen.
         wdata_hi : in unsigned(7 downto 0) := x"00";
         wen_hi : in std_logic := '0';
         wen_lo : in std_logic := '1';
         rdata_hi : out unsigned(7 downto 0);
         rdata_16en : in std_logic := '0';         -- set this high to be able
                                                   -- to read 16-bit values

         rdata : out unsigned(7 downto 0);

         data_ready_toggle_out : out std_logic := '0';
         busy : out std_logic := '0';

         -- Export current cache line for speeding up reads from slow_devices controller
         -- by skipping the need to hand us the request and get the response back.
         current_cache_line : out cache_row_t := (others => (others => '0'));
         current_cache_line_address : buffer unsigned(26 downto 3) := (others => '0');
         current_cache_line_valid : out std_logic := '0';
         expansionram_current_cache_line_next_toggle : in std_logic := '0';
         -- (#949: the v2 CPU path also follows prev; the tops may leave it open)
         expansionram_current_cache_line_prev_toggle : in std_logic := '0';

         -- Allow VIC-IV to request lines of data also.
         -- We then pump it out byte-by-byte when ready
         -- VIC-IV can address only 512KB at a time, so we have a banking register
         viciv_addr : in unsigned(18 downto 3) := (others => '0');
         viciv_request_toggle : in std_logic := '0';
         viciv_data_out : out unsigned(7 downto 0) := x"00";
         viciv_data_strobe : out std_logic := '0';

         hr_d : inout unsigned(7 downto 0) := (others => 'Z'); -- Data/Address
         hr_rwds : inout std_logic := 'Z'; -- RW Data strobe
         hr_reset : out std_logic := '1'; -- Active low RESET line to HyperRAM
         hr_clk_n : out std_logic := '0';
         hr_clk_p : out std_logic := '1';

         hr2_d : inout unsigned(7 downto 0) := (others => 'Z'); -- Data/Address
         hr2_rwds : inout std_logic := 'Z'; -- RW Data strobe
         hr2_reset : out std_logic := '1'; -- Active low RESET line to HyperRAM
         hr2_clk_n : out std_logic := '0';
         hr2_clk_p : out std_logic := '1';


         hr_cs0 : out std_logic := '1';
         hr_cs1 : out std_logic := '1';

         -- LUMP (Linear Uncomplicated Memory Port) for SSNAIL.
         -- Clocked by clock163.  See lump_queue.vhdl for the contract.
         -- Addresses are local to the HyperRAM (bit 23 selects the second
         -- chip, as for all other accesses).
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
         lump_idle        : out std_logic             := '1'
         );
end hyperram;

architecture gothic of hyperram is

  type state_t is (
    StartupDelay,
    ReadAbort,
    Idle,
    ReadSetup,
    WriteSetup,
    HyperRAMOutputCommand,
    HyperRAMDoWrite,
    HyperRAMOutputCommandSlow,
    StartBackgroundWrite,
    HyperRAMDoWriteSlow,
    HyperRAMFinishWriting,
    HyperRAMReadWaitSlow,
    HyperRAMReadWait,
    -- LUMP burst states (fast mode timing only)
    PortReadSetup,
    LumpReadWait,
    LumpDoWrite
    );

  -- How many clock ticks need to expire between transactions to satisfy T_RWR
  -- of hyperrram for the T_RWR 40ns delay.
  -- We can also subtract one cycle for the time it takes to pull CS low, and then
  -- two more for the clocks before the critical moment, and one more for time
  -- covered by various latencies in the system (including clock 1/2 cycle delay).
  -- This effectively gets us down to 45ns. Taking another cycle would leave us
  -- at only 38.7ns, which is a bit too short.
  -- This gives us an effective 8-byte write latency of ~132ns = ~7.5MHz.
  -- For read it is ~143ns = 6.99MHz, which might just be a whisker too slow
  -- for MiniMig.  By reading only 4 bytes instead of 8, this would allow getting
  -- back down to ~120 -- 132ns, which should be enough.
  -- Actually, all of that is a bit moot, since it seems that we just have to apply
  -- some trial and error to get it right. 1 seems right with the current settings.
  signal rwr_delay : unsigned(7 downto 0) := to_unsigned(1,8);
  signal rwr_counter : unsigned(7 downto 0) := (others => '0');
  signal rwr_waiting : std_logic := '0';

  signal current_cache_line_drive : cache_row_t := (others => (others => '0'));
  signal current_cache_line_address_drive : unsigned(26 downto 3) := (others => '0');
  signal current_cache_line_valid_drive : std_logic := '0';

  signal last_current_cache_next_toggle : std_logic := '0';

  signal state : state_t := StartupDelay;
  signal busy_internal : std_logic := '1';
  signal hr_command : unsigned(47 downto 0);

  signal hr_d_last : unsigned(7 downto 0);

  -- Used to assert CS line on BOTH hyperRAM modules at the same time
  -- when doing the initial configuration register write.
  signal first_transaction : std_logic := '1';

  -- Initial transaction is config register write
  signal config_reg_write : std_logic := '1';
  signal ram_address : unsigned(26 downto 0) :=
    "010000000000001000000000000"; -- = bottom 27 bits of x"A001000";
  signal ram_wdata : unsigned(7 downto 0) := x"00";
  signal ram_wdata_hi : unsigned(7 downto 0) := x"00";
  signal ram_wdata_enlo : std_logic := '0';
  signal ram_wdata_enhi : std_logic := '0';
  signal ram_reading : std_logic := '0';
  signal ram_reading_held : std_logic := '0';

  signal ram_reading_drive : std_logic := '0';
  signal ram_address_drive : unsigned(26 downto 0) :=
    "010000000000001000000000000"; -- = bottom 27 bits of x"A001000";
  signal ram_wdata_drive : unsigned(7 downto 0) := x"00";
  signal ram_wdata_hi_drive : unsigned(7 downto 0) := x"00";
  signal ram_wdata_enlo_drive : std_logic := '0';
  signal ram_wdata_enhi_drive : std_logic := '0';
  signal cache_row0_address_matches_ram_address : std_logic := '0';
  signal cache_row1_address_matches_ram_address : std_logic := '0';
  signal ram_address_matches_current_cache_line_address : std_logic := '0';
  signal address_matches_hyperram_access_address_block : std_logic := '0';
  signal write_collect0_address_matches_write_collect1_address_plus_1 : std_logic := '0';

  -- We want to set config register 0 to $ffe6, to enable variable latency
  -- and 3 cycles instead of 6 for latency. This speeds up writing almost 2x.
  -- But at 80MHz instead of 40MHz bus, we have to increase the latency from
  -- 3 to 4 cycles to satisfy the 40ns minimum time requirement.
  -- This also sets the drive strength to the maximum, to get cleaner faster
  -- clock transitions. This fixes checkerboard read errors at 80MHz.

  -- HyperRAM register space, CR0 (register word $800), as a controller
  -- address: bit 25 selects register space (CPU $A001000)
  constant CR0_ADDRESS : unsigned(26 downto 0) := "010" & x"001000";

  signal conf_buf0 : unsigned(7 downto 0) := x"ff";
  signal conf_buf1 : unsigned(7 downto 0) := x"f6";
  signal conf_buf0_in : unsigned(7 downto 0) := x"ff";
  signal conf_buf1_in : unsigned(7 downto 0) := x"f6";
  signal conf_buf0_set : std_logic := '0';
  signal conf_buf1_set : std_logic := '0';
  signal last_conf_buf0_set : std_logic := '0';
  signal last_conf_buf1_set : std_logic := '0';

  -- 4 is correct for the part we have in the MEGA65, after we have set the
  -- config register to minimise latency.
  signal write_latency : unsigned(7 downto 0) := to_unsigned(5,8);
  -- And the matching extra latency is 5
  signal extra_write_latency : unsigned(7 downto 0) := to_unsigned(7,8);

  -- And for the 2nd trap-door hyperram.
  -- That module from 1BitSquared uses a different brand of hyperram
  -- and seems to have different timing.
  signal write_latency2 : unsigned(7 downto 0) := to_unsigned(3,8);
  signal extra_write_latency2 : unsigned(7 downto 0) := to_unsigned(1,8);


  -- Control optimisations for hyperram access
  -- Enabling the cache MOSTLY works, but there is some cache coherency bug(s)
  -- when writing. These are currently being investigated.
  -- Issue #379 triggers one of those edge cases, so leaving disabled by default.
  -- brave programmers can enable if they dare (its mostly safe for slab DMA
  -- transfers) PGS20210504 #379
  -- On by default again (#949): the flakiness was the read publish bug
  -- (read_publish_toggle driven from two clocks), now fixed.
  signal cache_enabled : boolean := true;
  -- XXX There is a problem with block reads, where it causes the wrong byte to
  -- be returned at the start of the cached block. It instead returns the most
  -- recently WRITTEN byte.  I have no idea why as yet, so for now, we are just
  -- disabling block reads, at some performance cost.
  --                                                     PGS 20200923
  signal block_read_enable : std_logic := '0'; -- disable 32 byte read block fetching
  signal flag_prefetch : std_logic := '1';  -- enable/disable prefetch of read
                                            -- blocks
  signal enable_current_cache_line : std_logic := '1';

  -- These three must be off for reliable operation on current PCBs
  -- (#949: fast_cmd_mode now comes on by itself once the power-on CR0 write
  -- has gone out in slow mode: $BFFFFF2 reads $E1 after boot.  Writing
  -- $BFFFFF2 before then cancels that.)
  signal fast_cmd_mode : std_logic := '0';
  signal boot_fast_pending : std_logic := '1';
  signal fast_read_mode : std_logic := '0';
  signal fast_write_mode : std_logic := '0';

  -- As we move to enabling 80MHz operation, we are selectively applying
  -- fast_cmd mode.  It seems to work fine for reads, but not for writes
  -- at the moment.
  signal fast_cmd_for_write_enabled : boolean := true;

  signal read_phase_shift : std_logic := '0';
  signal write_phase_shift : std_logic := '1';

  signal countdown : integer range 0 to 63 := 0;
  signal countdown_is_zero : std_logic := '1';
  signal extra_latency : std_logic := '0';
  signal countdown_timeout : std_logic := '0';

  signal pause_phase : std_logic := '0';
  signal hr_clock : std_logic := '0';

  signal data_ready_toggle : std_logic := '0';

  signal request_toggle : std_logic := '0';
  signal request_accepted : std_logic := '0';
  signal last_request_toggle : std_logic := '0';

  signal byte_phase : unsigned(5 downto 0) := to_unsigned(0,6);
  signal write_byte_phase : std_logic := '0';

  signal hr_ddr : std_logic := '0';
  signal hr_rwds_ddr : std_logic := '0';
  signal hr_reset_int : std_logic := '1';
  signal hr_rwds_int : std_logic := '0';
  signal hr_cs0_int : std_logic := '0';
  signal hr_cs1_int : std_logic := '0';
  signal hr_clk_p_int : std_logic := '0';
  signal hr_clk_n_int : std_logic := '0';

  signal cycle_count : integer := 0;

  -- Have a tiny little cache to reduce latency
  -- 8 byte cache rows, where we indicate the validity of
  -- each byte.
  signal cache_row0_valids : std_logic_vector(0 to 7) := (others => '0');
  signal cache_row0_address : unsigned(23 downto 0) := (others => '1');
  signal cache_row0_data : cache_row_t := ( others => x"00" );

  signal cache_row1_valids : std_logic_vector(0 to 7) := (others => '0');
  signal cache_row1_address : unsigned(23 downto 0) := (others => '1');
  signal cache_row1_data : cache_row_t := ( others => x"00" );

  -- Collect writes together to hide write latency
  signal write_collect0_dispatchable : std_logic := '0';
  signal write_collect0_address : unsigned(26 downto 3) := (others => '0');
  signal write_collect0_valids : std_logic_vector(0 to 7) := (others => '0');
  signal write_collect0_data : cache_row_t := ( others => x"00" );
  signal write_collect0_toolate : std_logic := '0'; -- Set when its too late to
                                                    -- add more bytes to the write.
  signal write_collect0_flushed : std_logic := '1';

  signal write_collect1_dispatchable : std_logic := '0';
  signal write_collect1_address : unsigned(26 downto 3) := (others => '0');
  signal write_collect1_valids : std_logic_vector(0 to 7) := (others => '0');
  signal write_collect1_data : cache_row_t := ( others => x"00" );
  signal write_collect1_toolate : std_logic := '0'; -- Set when its too late to
                                                    -- add more bytes to the write.
  signal write_collect1_flushed : std_logic := '1';


  type block_t is array (0 to 3) of cache_row_t;
  signal block_data : block_t := (others => (others => x"00"));
  signal block_address : unsigned(26 downto 5);
  signal block_valid : std_logic := '0';
  signal is_block_read : boolean := false;
  signal is_prefetch : boolean := false;
  signal is_expected_to_respond : boolean := false;
  signal ram_prefetch : boolean := false;
  signal ram_normalfetch : boolean := false;

  signal current_cache_line_new_address : unsigned(26 downto 3) := (others => '0');
  signal current_cache_line_update : cache_row_t := (others => (others => '0'));
  signal current_cache_line_update_address : unsigned(26 downto 3) := (others => '0');
  signal current_cache_line_update_all : std_logic := '0';
  signal current_cache_line_update_flags : std_logic_vector(0 to 7) := (others => '0');
  signal last_current_cache_line_update_all : std_logic := '0';
  signal last_current_cache_line_update_flags : std_logic_vector(0 to 7) := (others => '0');

  signal current_cache_line_matches_block : std_logic := '0';
  signal current_cache_line_plus_1_matches_block : std_logic := '0';
  signal hyperram_access_address_matches_cache_row0 : std_logic := '0';
  signal hyperram_access_address_matches_cache_row1 : std_logic := '0';

  signal cache_row_update_toggle : std_logic := '0';
  signal last_cache_row_update_toggle : std_logic := '0';
  signal cache_row_update_address : unsigned(26 downto 3) := (others => '0');
  signal cache_row_update_byte : integer range 0 to 7 := 0;
  signal cache_row_update_value : unsigned(7 downto 0) := x"00";
  signal cache_row_update_value_hi : unsigned(7 downto 0) := x"00";
  signal cache_row_update_lo : std_logic := '0';
  signal cache_row_update_hi : std_logic := '0';

  signal last_rwds : std_logic := '0';

  signal request_counter_int : std_logic := '0';

  signal hr_rwds_high_seen : std_logic := '0';

  signal random_bits : unsigned(7 downto 0) := x"00";

  signal write_blocked : std_logic := '0';

  signal background_write : std_logic := '0';
  signal background_write_source : std_logic := '0';
  signal background_write_valids : std_logic_vector(0 to 7) := x"00";
  signal background_write_data : cache_row_t := (others => (others => '0'));
  signal background_write_count : integer range 0 to 7 := 0;
  signal background_write_next_address : unsigned(26 downto 3) := (others => '0');
  signal background_write_next_address_matches_collect0 : std_logic := '0';
  signal background_write_next_address_matches_collect1 : std_logic := '0';
  signal background_chained_write : std_logic := '0';
  signal background_write_fetch : std_logic := '0';
  signal collect1_matches_collect0_plus_1 : std_logic := '0';
  signal collect0_matches_collect1_plus_1 : std_logic := '0';
  signal matches_cache_row_update_address : std_logic := '0';
  signal cache_row_update_address_changed : std_logic := '0';
  signal block_address_matches_cache_row_update_address : std_logic := '0';
  signal cache_row0_address_matches_cache_row_update_address : std_logic := '0';
  signal cache_row1_address_matches_cache_row_update_address : std_logic := '0';
  signal byte_phase_greater_than_address_low_bits : std_logic := '0';
  signal byte_phase_greater_than_address_end_of_row : std_logic := '0';
  signal block_address_matches_address : std_logic := '0';
  signal invalidate_read_cache : std_logic := '0';

  signal write_continues : integer range 0 to 255 := 0;
  signal write_continues_max : integer range 0 to 255 := 16;

  -- If we get too many writes in short succession, we may need to queue up to
  -- two of the writes, while waiting for slow_devices to notice
  signal queued_write : std_logic := '0';
  signal queued_wen_lo : std_logic := '0';
  signal queued_wen_hi : std_logic := '0';
  signal queued_wdata : unsigned(7 downto 0) := x"00";
  signal queued_wdata_hi : unsigned(7 downto 0) := x"00";
  signal queued_waddr : unsigned(26 downto 0) := to_unsigned(0,27);
  signal queued2_write : std_logic := '0';
  signal queued2_wen_lo : std_logic := '0';
  signal queued2_wen_hi : std_logic := '0';
  signal queued2_wdata : unsigned(7 downto 0) := x"00";
  signal queued2_wdata_hi : unsigned(7 downto 0) := x"00";
  signal queued2_waddr : unsigned(26 downto 0) := to_unsigned(0,27);

  -- Delay sending of the initial configuration write command
  -- to give the HyperRAM chip time to start up
  -- Datasheet says 150usec is required, we do that, plus a bit.
  signal start_delay_counter : integer
    := 150*(1000/162)+20
    -- plus a correction factor to get initial config register write correctly
    -- aligned with the clock
    +2;
  signal start_delay_expired : std_logic := '0';

  -- phaseshift has to also start at 1 for the above to work.
  signal hr_clk_phaseshift : std_logic := '1';
  signal hr_clk_phaseshift_current : std_logic := '1';
  signal last_hr_clk_phaseshift : std_logic := '1';

  signal hr_clk_fast : std_logic := '1';
  signal hr_clk_fast_current : std_logic := '1';
  signal hr_clk : std_logic := '0';

  signal hr_clock_phase165 : unsigned(1 downto 0) := "00";
  signal hr_clock_phase : unsigned(2 downto 0) := "000";
  signal hr_clock_phase_drive : unsigned(2 downto 0) := "111";

  signal read_time_adjust : integer range 0 to 255 := 0;
  signal seven_plus_read_time_adjust : unsigned(5 downto 0) := "000000";
  signal thirtyone_plus_read_time_adjust : unsigned(5 downto 0) := "000000";
  signal hyperram_access_address_read_time_adjusted : unsigned(5 downto 0) := "000000";

  signal hyperram0_select : std_logic := '0';
  signal hyperram1_select : std_logic := '0';
  signal hyperram_access_address : unsigned(26 downto 0) := to_unsigned(0,27);

  signal read_request_held : std_logic := '0';
  signal write_request_held : std_logic := '0';
  signal mark_cache_for_prefetch : std_logic := '0';
  signal last_mark_cache_for_prefetch : std_logic := '0';
  signal mark_cache_for_prefetch162 : std_logic := '0';
  signal last_mark_cache_for_prefetch162 : std_logic := '0';

  signal viciv_last_request_toggle : std_logic := '0';
  signal viciv_bank : unsigned(7 downto 0) := x"00";
  signal viciv_data_buffer : cache_row_t := (others => x"00");
  signal viciv_buffer_toggle : std_logic := '0';
  signal last_viciv_buffer_toggle : std_logic := '0';
  signal viciv_next_byte : integer range 0 to 8 := 8;  -- (8: nothing to send)
  signal viciv_request_count : unsigned(31 downto 0) := to_unsigned(0,32);
  signal is_vic_fetch : boolean := false;
  -- The VIC-IV waits for its 8 bytes with no timeout, so a fetch that times
  -- out still hands over its (garbage) buffer
  signal vic_buffer_sent : std_logic := '0';

  -- LUMP port state
  signal lump_q_valid    : std_logic := '0';
  signal lump_q_op       : unsigned(1 downto 0) := "00";
  signal lump_q_addr     : unsigned(26 downto 0) := (others => '0');
  signal lump_q_len      : unsigned(8 downto 0) := (others => '0');
  signal lump_q_pop      : std_logic := '0';
  signal is_lump         : std_logic := '0';
  -- LUMP data phase in the slow (half-rate) mode, as the CPU path uses when
  -- fast_read_mode / fast_write_mode are clear: act on alternate cycles only
  signal lump_slow       : std_logic := '0';
  signal lump_inval_req  : std_logic := '0';
  -- Words still to transfer in the current burst, minus two.  It goes
  -- negative exactly on the last word, so the sign bit IS the "last word"
  -- flag: no compare logic on the control paths.
  signal lump_cnt        : signed(8 downto 0) := (others => '1');
  -- Pre-registered dispatch decisions and burst set-up values, so that the
  -- Idle-state decision and data muxes see only flip-flop outputs.
  signal lump_go         : std_logic := '0';  -- READ/WRITE at queue head
  signal lump_inv_go     : std_logic := '0';  -- INVALIDATE at queue head
  signal lump_bus_free   : std_logic := '0';  -- nothing else wanted the bus
  signal lump_is_read    : std_logic := '0';
  signal lump_cnt_init   : signed(8 downto 0) := (others => '1');
  signal lump_cmd_pre    : unsigned(47 downto 0) := (others => '0');
  signal lump_addr_pre   : unsigned(26 downto 3) := (others => '0');
  signal lump_byte_odd   : std_logic := '0';
  signal lump_rbuf_lo    : unsigned(7 downto 0) := x"00";
  signal lump_wbuf_hi    : unsigned(7 downto 0) := x"00";
  signal lump_wbe_hi     : std_logic := '0';
  signal lump_flushing   : std_logic := '0';
  -- LUMP debug capture (#949), read via the $B0000A0-$B0000BA debug window:
  -- the bus as LumpReadWait sees it from its first cycle, and counters.
  type lump_dbg_t is array(0 to 15) of unsigned(7 downto 0);
  signal lump_dbg_raw    : lump_dbg_t := (others => x"00");
  signal lump_dbg_rwds   : std_logic_vector(15 downto 0) := (others => '0');
  signal lump_dbg_idx    : integer range 0 to 16 := 16;
  signal lump_dbg_got    : std_logic := '0';
  signal lump_dbg_cyc    : unsigned(7 downto 0) := x"00";  -- read: cycles before the first byte
  signal lump_dbg_rw     : unsigned(7 downto 0) := x"00";  -- read: words delivered
  signal lump_dbg_wq     : unsigned(7 downto 0) := x"00";  -- write: words requested
  signal lump_dbg_wb     : unsigned(7 downto 0) := x"00";  -- write: bytes driven
  signal lump_dbg_wcyc   : unsigned(7 downto 0) := x"00";  -- write: cycles before the first byte
  signal lump_dbg_wgot   : std_logic := '0';
  signal lump_dbg_nr     : unsigned(7 downto 0) := x"00";  -- read bursts
  signal lump_dbg_nw     : unsigned(7 downto 0) := x"00";  -- write bursts
  signal viciv_data_debug : std_logic := '0';
  signal viciv_debug_priority : std_logic := '0';

  signal read_request_latch : std_logic := '0';
  signal read_request_delatch : std_logic := '0';
  signal read_request_prev : std_logic := '0';
  signal write_request_latch : std_logic := '0';
  signal write_request_prev : std_logic := '0';

  signal prefetch_when_idle : boolean := false;

  signal read_publish_toggle  : std_logic              := '0';
  signal last_read_publish_toggle : std_logic := '0';
  signal rdata_buf        : unsigned(7 downto 0);
  signal rdata_hi_buf     : unsigned(7 downto 0);
  signal read_publish_strobe2  : std_logic              := '0';
  signal rdata_buf2        : unsigned(7 downto 0);
  signal rdata_hi_buf2     : unsigned(7 downto 0);
  signal last_data_ready_toggle_out : std_logic := '0';
  signal data_ready_toggle_drive : std_logic := '0';

  -----------------------------------------------------------------------------
  -- CPU path v2 (#949): the same scheme as the SDRAM controller's CPU path.
  -- A line cache, posted writes with byte masks, prefetch, the exported line
  -- with next/prev, and VIC-IV fetches, all in the clock163 domain.  Its bus
  -- work is done as LUMP-engine bursts (fills of up to H_FILL lines, and
  -- one-line masked writes), so it shares the LUMP path's timing.  Register
  -- space ($A000000 up: CR0, the debug registers) still goes the old way.
  -----------------------------------------------------------------------------
  -- $BFFFFF7: bit 0 CPU path v2 (0: the old path; switch only while idle),
  -- bit 1 prefetch after CPU reads, bit 2 also prefetch past the exported
  -- line when the CPU moves it on (the early next-line fetch: off by default
  -- until the CPU side is known to use it well)
  signal v2_flags : std_logic_vector(7 downto 0) := x"03";
  signal v2_en    : std_logic;
  signal v2_ram   : std_logic;          -- the request on the port is v2's
  signal read_request_o, write_request_o : std_logic;  -- the old path's
  signal busy_o   : std_logic := '0';   -- the old path's busy
  signal busy_v2  : std_logic := '1';
  constant H_NL   : integer := 16;      -- cached lines (8 bytes each)
  constant H_NW   : integer := 2;       -- posted-write buffers
  constant H_FILL : integer := 4;       -- lines per fill burst
  constant H_PF   : integer := 8;       -- prefetch this many lines ahead
  type h_ltag_t  is array (0 to H_NL - 1) of unsigned(26 downto 3);
  type h_ldata_t is array (0 to H_NL - 1) of unsigned(63 downto 0);
  signal c_tag  : h_ltag_t := (others => (others => '1'));
  signal c_val  : std_logic_vector(0 to H_NL - 1) := (others => '0');
  signal c_data : h_ldata_t := (others => (others => '0'));
  signal c_rr   : integer range 0 to H_NL - 1 := 0;
  -- the fill in progress: fl_n lines from fl_tag, into slots fl_slot
  type h_slots_t is array (0 to H_FILL - 1) of integer range 0 to H_NL - 1;
  signal fill_active : std_logic := '0';
  signal fl_tag  : unsigned(26 downto 3) := (others => '1');
  signal fl_n    : integer range 0 to H_FILL := 0;
  signal fl_line : integer range 0 to H_FILL - 1 := 0;
  signal fl_word : integer range 0 to 3 := 0;
  signal fl_slot : h_slots_t := (others => 0);
  signal fl_err  : std_logic := '0';
  -- posted writes; w_fl: being written out (frozen until done)
  type h_wtag_t  is array (0 to H_NW - 1) of unsigned(26 downto 3);
  type h_wdata_t is array (0 to H_NW - 1) of unsigned(63 downto 0);
  type h_wmask_t is array (0 to H_NW - 1) of std_logic_vector(7 downto 0);
  type h_wage_t  is array (0 to H_NW - 1) of integer range 0 to 63;
  signal w_tag  : h_wtag_t := (others => (others => '1'));
  signal w_data : h_wdata_t := (others => (others => '0'));
  signal w_mask : h_wmask_t := (others => (others => '0'));
  signal w_age  : h_wage_t := (others => 0);
  signal w_fl   : std_logic_vector(0 to H_NW - 1) := (others => '0');
  signal w_cur  : integer range 0 to H_NW - 1 := 0;
  signal w_stall : std_logic := '0';
  signal f_j    : integer range 0 to H_NW - 1 := 0;
  signal f_word : integer range 0 to 3 := 0;
  -- the request being handled
  signal rd_l, wr_l : std_logic := '0';
  signal l_addr : unsigned(26 downto 0) := (others => '0');
  signal l_wdata, l_wdata_hi : unsigned(7 downto 0) := x"00";
  signal l_wen_lo, l_wen_hi : std_logic := '0';
  type h_rs_t is (R_IDLE, R_LOOK, R_DECIDE, R_WAIT);
  signal rs : h_rs_t := R_IDLE;
  signal lk_c : std_logic_vector(0 to H_NL - 1) := (others => '0');
  signal lk_w : std_logic_vector(0 to H_NW - 1) := (others => '0');
  signal want_fill : std_logic := '0';
  signal last_pub : unsigned(26 downto 3) := (others => '1');
  -- the exported line, and next/prev
  signal exp_addr  : unsigned(26 downto 3) := (others => '1');
  signal exp_valid : std_logic := '0';
  signal exp_data  : unsigned(63 downto 0) := (others => '0');
  signal x_look, x_use, x_want, x_down : std_logic := '0';
  signal x_addr : unsigned(26 downto 3) := (others => '1');
  signal x_hit  : std_logic_vector(0 to H_NL - 1) := (others => '0');
  signal next_toggle_drive, prev_toggle_drive : std_logic := '0';
  signal next_toggle_seen, prev_toggle_seen : std_logic := '0';
  -- prefetch
  signal pf_base : unsigned(26 downto 3) := (others => '1');
  signal pf_down : std_logic := '0';
  signal pf_k    : integer range 0 to H_PF + 1 := H_PF + 1;
  signal pf_cand : unsigned(26 downto 3) := (others => '1');
  signal pf_chk, pf_chk2, pf_present, pf_want : std_logic := '0';
  signal pf_line : unsigned(26 downto 3) := (others => '1');
  signal v2_hits, v2_misses : unsigned(15 downto 0) := (others => '0');
  -- VIC-IV fetches
  signal vic_tag : unsigned(26 downto 3) := (others => '1');
  signal vic_look, vic_use, vic_want : std_logic := '0';
  signal vic_hit : std_logic_vector(0 to H_NL - 1) := (others => '0');
  -- LUMP-engine jobs: cj_req waits for the Idle dispatch, cj_busy until done
  signal cj_req, cj_busy, cj_read : std_logic := '0';
  signal cj_tag : unsigned(26 downto 3) := (others => '0');
  signal cj_cnt_init : signed(8 downto 0) := (others => '1');
  signal cj_pf : std_logic := '0';           -- the job is a prefetch
  -- A LUMP burst pauses at an 8-byte boundary (after at least 16 bytes) when
  -- a CPU request needs the bus, and resumes after it: at the boot data rate
  -- a 256-byte burst takes over 3 us, and slow_devices gives up after 1.6.
  signal lump_yield   : std_logic := '0';    -- a CPU request waits (registered)
  signal lump_res     : std_logic := '0';    -- a paused LUMP command
  signal lump_res_addr : unsigned(26 downto 3) := (others => '0');
  signal lump_res_cnt : signed(8 downto 0) := (others => '1');
  signal lump_res_read : std_logic := '0';
  signal lump_pre_res : std_logic := '0';    -- the pre-computed burst resumes it
  signal lump_cur_addr : unsigned(26 downto 3) := (others => '0');
  signal lump_wg      : unsigned(1 downto 0) := "00";  -- word within 8 bytes
  signal lump_seg     : std_logic := '0';    -- 8 bytes done in this burst
  -- 8-byte groups done in this burst: it also pauses after 256 bytes, so
  -- CS is never low for more than 4 us (tCSM: the device refreshes between)
  signal lump_ng      : unsigned(4 downto 0) := (others => '0');
  signal lump_ending  : std_logic := '0';    -- write: pausing after this word
  signal lump_pre_cpu   : std_logic := '0';  -- the pre-computed burst is v2's
  signal lump_owner_cpu : std_logic := '0';  -- the burst under way is v2's
  signal v2_inval : std_logic := '0';
  -- the LUMP engine's own strobes and data (the LUMP port sees its bursts)
  signal le_rdata : unsigned(15 downto 0) := x"0000";
  signal le_rdata_valid, le_wdata_req, le_cmd_done, le_error : std_logic := '0';
  signal le_wdata : unsigned(15 downto 0);
  signal le_wdata_be : std_logic_vector(1 downto 0);
  signal cj_wdata : unsigned(15 downto 0) := x"0000";
  signal cj_wdata_be : std_logic_vector(1 downto 0) := "00";

begin

  v2_en <= v2_flags(0);
  -- RAM (not register space) requests are v2's when it is on
  v2_ram <= v2_en and not address(25);
  read_request_o  <= read_request and not v2_ram;
  write_request_o <= write_request and not v2_ram;
  busy <= busy_o or busy_v2;
  lump_rdata       <= le_rdata;
  lump_rdata_valid <= le_rdata_valid and not lump_owner_cpu;
  lump_wdata_req   <= le_wdata_req and not lump_owner_cpu;
  lump_cmd_done    <= le_cmd_done and not lump_owner_cpu;
  lump_error       <= le_error and not lump_owner_cpu;
  le_wdata    <= cj_wdata when lump_owner_cpu = '1' else lump_wdata;
  le_wdata_be <= cj_wdata_be when lump_owner_cpu = '1' else lump_wdata_be;

  lump_queue0 : entity work.lump_queue
    port map (
      clock      => clock163,
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
  process (pixelclock,clock163,clock325,hr_clk,hr_clk_phaseshift) is
    variable clock_status_vector : unsigned(4 downto 0);
    variable tempaddr : unsigned(26 downto 0);
    variable show_cache0 : boolean := false;
    variable show_cache1 : boolean := false;
    variable show_collect0 : boolean := false;
    variable show_collect1 : boolean := false;
    variable show_block : boolean := false;
    variable show_always : boolean := true;
    -- CPU path v2
    variable v2_done      : boolean;
    variable v2_done_slot : integer range 0 to H_NL - 1;
    variable v2_pf_go     : boolean;
    variable v2_pf_base   : unsigned(26 downto 3);
    variable v2_pf_down   : std_logic;
    variable v2_idx       : integer range 0 to 7;
    variable v2_line, v2_line2 : unsigned(63 downto 0);
    variable v2_tag       : unsigned(26 downto 3);
    variable v2_wh, v2_hit, v2_free : integer range -1 to H_NL;
    variable v2_frozen    : boolean;
    variable v2_mask      : std_logic_vector(7 downto 0);

    function byte_of(d : unsigned(63 downto 0); i : integer) return unsigned is
    begin
      return d(8 * i + 7 downto 8 * i);
    end function;
    -- Answer the CPU's read
    procedure v2_publish(b, bh : unsigned(7 downto 0)) is
    begin
      report "V2: read $" & to_hstring(l_addr) & " -> $" & to_hstring(b);
      rdata <= b;
      rdata_hi <= bh;
      -- (the toggle with the data, as the SDRAM controller does: the old
      -- path's extra cycle through data_ready_toggle_drive isn't needed)
      data_ready_toggle_out <= not last_data_ready_toggle_out;
      data_ready_toggle_drive <= not last_data_ready_toggle_out;
      last_data_ready_toggle_out <= not last_data_ready_toggle_out;
      rd_l <= '0';
      rs <= R_IDLE;
    end procedure;
    -- The exported line, and slow_devices' view of it
    procedure v2_set_export(t : unsigned(26 downto 3); d : unsigned(63 downto 0)) is
    begin
      exp_addr <= t;
      exp_data <= d;
      exp_valid <= '1';
      if v2_en = '1' then
        current_cache_line_address <= t;
        for k in 0 to 7 loop
          current_cache_line(k) <= d(8 * k + 7 downto 8 * k);
        end loop;
        current_cache_line_valid <= enable_current_cache_line;
      end if;
    end procedure;
    -- Prefetch from line t on, if enabled, going the way the reads go
    procedure v2_prefetch_from(t : unsigned(26 downto 3)) is
    begin
      if v2_flags(1) = '1' and t /= last_pub then
        v2_pf_go := true;
        v2_pf_base := t;
        v2_pf_down := '0';
        if t = last_pub - 1 then v2_pf_down := '1'; end if;
        last_pub <= t;
      end if;
    end procedure;
    -- Fill the lines around t (upwards from t, or ending at t if down),
    -- staying within t's 1 KB, into the next slots
    procedure v2_start_fill(t : unsigned(26 downto 3); down : std_logic) is
      variable st : unsigned(26 downto 3);
      variable n  : integer range 1 to H_FILL;
      variable o  : integer range 0 to 127;
    begin
      o := to_integer(t(9 downto 3));
      if down = '0' then
        st := t;
        if 128 - o < H_FILL then n := 128 - o; else n := H_FILL; end if;
      elsif o < H_FILL - 1 then
        st := t - o;
        n := o + 1;
      else
        st := t - (H_FILL - 1);
        n := H_FILL;
      end if;
      for k in 0 to H_FILL - 1 loop
        fl_slot(k) <= (c_rr + k) mod H_NL;
        if k < n then
          c_val((c_rr + k) mod H_NL) <= '0';
          c_tag((c_rr + k) mod H_NL) <= st + k;
        end if;
      end loop;
      c_rr <= (c_rr + n) mod H_NL;
      report "V2: fill $" & to_hstring(st & "000") & ", " & integer'image(n) & " lines";
      fill_active <= '1';
      fl_tag <= st;
      fl_n <= n;
      fl_line <= 0;
      fl_word <= 0;
      fl_err <= '0';
      cj_req <= '1';
      cj_pf <= '0';
      cj_read <= '1';
      cj_tag <= st;
      cj_cnt_init <= to_signed(4 * n - 2, 9);
    end procedure;
    -- Write out posted-write buffer j (frozen until it is done)
    procedure v2_start_flush(j : integer) is
    begin
      report "V2: flush buffer " & integer'image(j) & " $" & to_hstring(w_tag(j) & "000")
        & " mask " & to_string(w_mask(j));
      w_fl(j) <= '1';
      f_j <= j;
      f_word <= 0;
      cj_req <= '1';
      cj_pf <= '0';
      cj_read <= '0';
      cj_tag <= w_tag(j);
      cj_cnt_init <= to_signed(2, 9);
    end procedure;
  begin
    if rising_edge(pixelclock) then

      invalidate_read_cache <= '0';
      cache_row_update_address_changed <= '0';

      if read_request_o='1' then
        read_request_latch <= '1';
      end if;
      if write_request_o='1' then
        write_request_latch <= '1';
      end if;
      if read_request_delatch = '1' then
        read_request_latch <= '0';
      end if;

      -- Present the data to the VIC-IV
      if viciv_data_debug = '1' then
        viciv_data_strobe <= '1';
        viciv_data_out <= viciv_request_count(7 downto 0);
      else
        viciv_data_strobe <= '0';
      end if;
      if viciv_buffer_toggle /= last_viciv_buffer_toggle then
        report "VIC: Starting to send data";
        last_viciv_buffer_toggle <= viciv_buffer_toggle;
        viciv_data_out <= viciv_data_buffer(0);
        report "VIC: Sending byte " & integer'image(0)
          & " = $" & to_hstring(viciv_data_buffer(0));
        viciv_next_byte <= 1;
        viciv_data_strobe <= '1';
      elsif viciv_next_byte < 8 then
        report "VIC: Sending byte " & integer'image(viciv_next_byte)
          & " = $" & to_hstring(viciv_data_buffer(viciv_next_byte));
        viciv_data_out <= viciv_data_buffer(viciv_next_byte);
        viciv_next_byte <= viciv_next_byte + 1;
        viciv_data_strobe <= '1';
      end if;

      if in_simulation = true then
        write_latency2 <= to_unsigned(5,8);
        extra_write_latency2 <= to_unsigned(3,8);
      end if;

      report "read_request_o=" & std_logic'image(read_request_o)
        & ", read_request_held=" & std_logic'image(read_request_held)
        & ", write_request_held=" & std_logic'image(write_request_held)
        & ", read_request_latch=" & std_logic'image(read_request_latch)
        & ", write_request_latch=" & std_logic'image(write_request_latch)
        & ", busy_internal=" & std_logic'image(busy_internal)
        & ", write_request_o=" & std_logic'image(write_request_o)
        & ", request_toggle(last) = " & std_logic'image(request_toggle) & "(" & std_logic'image(last_request_toggle) & ")."
        & ", is_block_read=" & boolean'image(is_block_read)
        & ", address=$" & to_hstring(address);

      -- Pseudo random bits so that we can do randomised cache row replacement
      if random_bits /= to_unsigned(251,8) then
        random_bits <= random_bits + 1;
      else
        random_bits <= x"00";
      end if;

      -- Update short-circuit cache line
      -- (We don't change validity, since we don't know if it is
      -- valid or not).
      -- This has to happen IMMEDIATELY so that slow_devices doesn't
      -- accidentally read old data, while we are still scheduling the write.
      if address(26 downto 3) = current_cache_line_address(26 downto 3) then
        report "Requesting update of current_cache_line due to write. Value = $"
          & to_hstring(wdata) & ", byte offset = " & integer'image(to_integer(address(2 downto 0)));
        if wen_lo = '1' then
          current_cache_line_update(to_integer(address(2 downto 0))) <= wdata;
          current_cache_line_update_flags(to_integer(address(2 downto 0))) <=
            not current_cache_line_update_flags(to_integer(address(2 downto 0)));
          current_cache_line_update_address <= current_cache_line_address;
          end if;
        if wen_hi = '1' then
          current_cache_line_update(to_integer(address(2 downto 0))+1) <= wdata_hi;
          current_cache_line_update_flags(to_integer(address(2 downto 0))+1) <=
            not current_cache_line_update_flags(to_integer(address(2 downto 0))+1);
          current_cache_line_update_address <= current_cache_line_address;
        end if;
      end if;

      if cache_enabled then
        busy_o <= busy_internal or write_blocked or queued_write or queued2_write or (not start_delay_expired);
      else
        -- With no cache, we have to IMMEDIATELY assert busy when we see a
        -- request to avoid a race-condition with slow_devices
        busy_o <= busy_internal or write_blocked or queued_write or queued2_write
                or read_request_o or write_request_o or read_request_latch or write_request_latch
                or (not start_delay_expired);
      end if;

      -- Fast command phase from the end of the power-on CR0 write on
      if boot_fast_pending = '1' and start_delay_expired = '1' and first_transaction = '0' then
        boot_fast_pending <= '0';
        fast_cmd_mode <= '1';
      end if;

      if write_blocked = '1' and first_transaction='0' then
--        report "DISPATCH: write_blocked asserted. Waiting for existing writes to flush...";
        null;
      end if;

      -- Clear write block as soon as either write buffer clears
      if (write_collect0_dispatchable='0' and write_collect0_toolate='0' and write_collect0_flushed='0')
        or (write_collect1_dispatchable='0' and write_collect1_toolate='0' and write_collect1_flushed='0')
      then
        write_blocked <= queued_write or queued2_write;
      else
        write_blocked <= '1';
        busy_o <= '1';
      end if;

      -- Similarly as soon as we see a VIC-IV request come through we need to
      -- assert busy
      if viciv_request_toggle /= viciv_last_request_toggle then
        busy_o <= '1';
      end if;

      if read_request_o = '1' or write_request_o = '1' or read_request_latch='1' or write_request_latch='1' then
        request_counter_int <= not request_counter_int;
        request_counter <= request_counter_int;
      end if;

      if cache_row0_address = cache_row1_address and cache_row0_address /= x"ffffff" then
        report "ERROR: Cache row0 and row1 point to same address";
        show_cache0 := true;
        show_cache1 := true;
      end if;



      -- Clear write buffers once they have been flushed.
      -- We have to wipe the address and valids, so that they don't get stuck being
      -- used as stale sources for cache reading.
      if write_collect0_dispatchable = '1' and write_collect0_toolate = '1' and write_collect0_flushed = '1' then
        show_collect0 := true;
        report "WRITE: Clearing collect0";
        write_collect0_address <= (others => '1');
        write_collect0_dispatchable <= '0';
      end if;
      if write_collect1_dispatchable = '1' and write_collect1_toolate = '1' and write_collect1_flushed = '1' then
        if write_collect1_dispatchable='1' then
          show_collect1 := true;
        end if;
        report "WRITE: Clearing collect1";
        write_collect1_address <= (others => '1');
        write_collect1_dispatchable <= '0';
      end if;

      if write_collect0_dispatchable = '0' and write_collect0_toolate = '0' and write_collect0_flushed = '0' then
        if queued_write='1' then
          report "DISPATCH: Dequeuing queued write to $" & to_hstring(queued_waddr);

          -- Push it out as a normal batched write, that can collect others if they
          -- come soon enough.

          write_collect0_valids <= (others => '0');
          if queued_wen_lo='1' then
            write_collect0_valids(to_integer(queued_waddr(2 downto 0))) <= '1';
            write_collect0_data(to_integer(queued_waddr(2 downto 0))) <= queued_wdata;
          end if;
          if queued_wen_hi='1' then
            write_collect0_valids(to_integer(queued_waddr(2 downto 0))+1) <= '1';
            write_collect0_data(to_integer(queued_waddr(2 downto 0))+1) <= queued_wdata_hi;
          end if;
          write_collect0_address <= queued_waddr(26 downto 3);
          write_collect0_dispatchable <= '1';
          show_collect0 := true;

          queued_write <= '0';
        elsif queued2_write='1' then
          report "DISPATCH: Dequeuing queued write to $" & to_hstring(queued2_waddr);

          -- Push it out as a normal batched write, that can collect others if they
          -- come soon enough.

          write_collect0_valids <= (others => '0');
          if queued2_wen_lo='1' then
            write_collect0_valids(to_integer(queued2_waddr(2 downto 0))) <= '1';
            write_collect0_data(to_integer(queued2_waddr(2 downto 0))) <= queued2_wdata;
          end if;
          if queued2_wen_hi='1' then
            write_collect0_valids(to_integer(queued2_waddr(2 downto 0))+1) <= '1';
            write_collect0_data(to_integer(queued2_waddr(2 downto 0))+1) <= queued2_wdata_hi;
          end if;
          write_collect0_address <= queued2_waddr(26 downto 3);
          write_collect0_dispatchable <= '1';
          show_collect0 := true;

          queued2_write <= '0';
        end if;

      end if;
      -- Only if collect0 did not take it above in this same cycle: otherwise
      -- both collects took the one queued write, and it went out twice
      -- (only reachable when both collects are free with a write queued,
      -- e.g. the CR0 write queued by a write to $BFFFFF9).
      if write_collect1_dispatchable = '0' and write_collect1_toolate = '0' and write_collect1_flushed = '0'
        and not (write_collect0_dispatchable = '0' and write_collect0_toolate = '0' and write_collect0_flushed = '0') then
        if queued_write='1' then
          report "DISPATCH: Dequeuing queued write to $" & to_hstring(queued_waddr);

          -- Push it out as a normal batched write, that can collect others if they
          -- come soon enough.

          write_collect1_valids <= (others => '0');
          if queued_wen_lo='1' then
            write_collect1_valids(to_integer(queued_waddr(2 downto 0))) <= '1';
            write_collect1_data(to_integer(queued_waddr(2 downto 0))) <= queued_wdata;
          end if;
          if queued_wen_hi='1' then
            write_collect1_valids(to_integer(queued_waddr(2 downto 0))+1) <= '1';
            write_collect1_data(to_integer(queued_waddr(2 downto 0))+1) <= queued_wdata_hi;
          end if;
          write_collect1_address <= queued_waddr(26 downto 3);
          write_collect1_dispatchable <= '1';
          show_collect1 := true;

          queued_write <= '0';
        end if;
      end if;

      -- Ignore read requests to the current block read, as they get
      -- short-circuited in the inner state machine to save time.
      report "address = $" & to_hstring(address);
      if (read_request_o or read_request_latch)='1' and busy_internal='0'
        and ((is_block_read = false) or block_address_matches_address='0')
        -- Don't but in on the VIC-IV (but once we have submitted a request, we
        -- do have priority)
        and (viciv_last_request_toggle = viciv_request_toggle) then
        report "Making read request for $" & to_hstring(address);
        -- Begin read request

        read_request_latch <= '0';

        -- Check for cache read
        -- We check the write buffers first, as any contents that they have
        -- must take priority over everything else
        if (block_valid='1') and (block_address_matches_address='1') then
          report "flipping read_publish_toggle";
          read_publish_toggle <= not read_publish_toggle;
          rdata_buf <= block_data(to_integer(address(4 downto 3)))(to_integer(address(2 downto 0)));
          if rdata_16en='1' then
            rdata_hi_buf <= block_data(to_integer(address(4 downto 3)))(to_integer(address(2 downto 0))+1);
          end if;
          report "DISPATCH: Returning data $"
            & to_hstring(block_data(to_integer(address(4 downto 3)))(to_integer(address(2 downto 0))))
            & " from read block.";
          -- Now update current cache line to speed up subsequent reads
          current_cache_line_update <= block_data(to_integer(address(4 downto 3)));
          current_cache_line_new_address <= address(26 downto 3);
          current_cache_line_update_all <= not current_cache_line_update_all;

          if (address(4 downto 3) = "11") and (flag_prefetch='1')
          and (viciv_request_toggle = viciv_last_request_toggle) then
            -- When attempting to read from the last 8 bytes of a block read,
            -- we schedule a pre-fetch of the next 32 bytes, so that we can hide
            -- the read latency as much as possible.
            ram_reading <= '1';
            tempaddr(26 downto 5) := address(26 downto 5) + 1;
            tempaddr(4 downto 0) := "00000";
            ram_address <= tempaddr;
            request_toggle <= not request_toggle;
            ram_prefetch <= true;
            ram_normalfetch <= false;

            report "DISPATCH: Dispatching pre-fetch of $" & to_hstring(tempaddr);
            -- Mark a cache line to receive the pre-fetched data, so that we don't
            -- have to wait for it all to turn up, before being able to return
            -- the first 8 bytes
            mark_cache_for_prefetch <= not mark_cache_for_prefetch;
          end if;

        elsif cache_enabled and rdata_16en='0' and (address(26 downto 3 ) = write_collect0_address and write_collect0_valids(to_integer(address(2 downto 0))) = '1') then
          -- Write cache read-back
          report "flipping read_publish_toggle";
          read_publish_toggle <= not read_publish_toggle;
          rdata_buf <= write_collect0_data(to_integer(address(2 downto 0)));
          report "DISPATCH: Returning data $"& to_hstring(write_collect0_data(to_integer(address(2 downto 0))))&" from write collect0";
        elsif cache_enabled and rdata_16en='1' and (address(26 downto 3 ) = write_collect0_address
                                                    and write_collect0_valids(to_integer(address(2 downto 1)&"0")) = '1'
                                                    and write_collect0_valids(to_integer(address(2 downto 1)&"1")) = '1') then
          -- Write cache read-back
          report "flipping read_publish_toggle";
          read_publish_toggle <= not read_publish_toggle;
          rdata_buf <= write_collect0_data(to_integer(address(2 downto 1)&"0"));
          rdata_hi_buf <= write_collect0_data(to_integer(address(2 downto 1)&"1"));
          report "DISPATCH: Returning data $"& to_hstring(write_collect0_data(to_integer(address(2 downto 0))))&" from write collect0";
        elsif cache_enabled and rdata_16en='0' and (address(26 downto 3 ) = write_collect1_address and write_collect1_valids(to_integer(address(2 downto 0))) = '1') then
          -- Write cache read-back
          report "flipping read_publish_toggle";
          read_publish_toggle <= not read_publish_toggle;
          rdata_buf <= write_collect1_data(to_integer(address(2 downto 0)));
          report "DISPATCH: Returning data $"& to_hstring(write_collect1_data(to_integer(address(2 downto 0))))&" from write collect1";
        elsif cache_enabled and rdata_16en='1' and (address(26 downto 3 ) = write_collect1_address
                                                    and write_collect1_valids(to_integer(address(2 downto 1)&"0")) = '1'
                                                    and write_collect1_valids(to_integer(address(2 downto 1)&"1")) = '1') then
          -- Write cache read-back
          read_publish_toggle <= not read_publish_toggle;
          rdata_buf <= write_collect1_data(to_integer(address(2 downto 1)&"0"));
          rdata_hi_buf <= write_collect1_data(to_integer(address(2 downto 1)&"1"));
          report "DISPATCH: Returning data $"& to_hstring(write_collect1_data(to_integer(address(2 downto 0))))&" from write collect1";
        elsif cache_enabled and rdata_16en='0' and (address(26 downto 3 ) = cache_row0_address and cache_row0_valids(to_integer(address(2 downto 0))) = '1') then
          -- Cache reads
          read_publish_toggle <= not read_publish_toggle;
          rdata_buf <= cache_row0_data(to_integer(address(2 downto 0)));
          report "DISPATCH: Returning data $"& to_hstring(cache_row0_data(to_integer(address(2 downto 0))))&" from cache row0";
        elsif cache_enabled and rdata_16en='1' and (address(26 downto 3 ) = cache_row0_address
                                                    and cache_row0_valids(to_integer(address(2 downto 1)&"0")) = '1'
                                                    and cache_row0_valids(to_integer(address(2 downto 1)&"1")) = '1') then
          -- Cache reads
          read_publish_toggle <= not read_publish_toggle;
          rdata_buf <= cache_row0_data(to_integer(address(2 downto 1)&"0"));
          rdata_hi_buf <= cache_row0_data(to_integer(address(2 downto 1)&"1"));
          report "DISPATCH: Returning data $"& to_hstring(cache_row0_data(to_integer(address(2 downto 0))))&" from cache row0";
        elsif cache_enabled and rdata_16en='0' and (address(26 downto 3 ) = cache_row1_address and cache_row1_valids(to_integer(address(2 downto 0))) = '1') then
          -- Cache read
          report "flipping read_publish_toggle";
          read_publish_toggle <= not read_publish_toggle;
          rdata_buf <= cache_row1_data(to_integer(address(2 downto 0)));
          report "DISPATCH: Returning data $"& to_hstring(cache_row1_data(to_integer(address(2 downto 0))))&" from cache row1";
        elsif cache_enabled and rdata_16en='1' and (address(26 downto 3 ) = cache_row1_address
                                                    and cache_row1_valids(to_integer(address(2 downto 1)&"0"))='1'
                                                    and cache_row1_valids(to_integer(address(2 downto 1)&"1"))='1') then

          -- Cache read
          read_publish_toggle <= not read_publish_toggle;
          rdata_buf <= cache_row1_data(to_integer(address(2 downto 1)&"0"));
          rdata_hi_buf <= cache_row1_data(to_integer(address(2 downto 1)&"1"));
          report "DISPATCH: Returning data $"& to_hstring(cache_row1_data(to_integer(address(2 downto 0))))&" from cache row1";
        elsif address(23 downto 8) = x"00000" and address(25 downto 24) = "11" then
          -- $B0000xx for now for debugging caches etc
          case address(7 downto 0) is
            when x"00" => rdata_buf(7) <= '1';
                          rdata_buf(6 downto 3) <= (others => '0');
                          rdata_buf(2 downto 0) <= cache_row0_address(23 downto 21);
            when x"01" => rdata_buf <= cache_row0_address(20 downto 13);
            when x"02" => rdata_buf <= cache_row0_address(12 downto 5);
            when x"03" => rdata_buf(7 downto 3) <= cache_row0_address(4 downto 0);
                          rdata_buf(2 downto 0) <= "000";
            when x"04" => rdata_buf <= unsigned(cache_row0_valids);
            when x"05" => rdata_buf <= x"AA";
            when x"06" => rdata_buf <= x"AA";
            when x"07" => rdata_buf <= x"AA";
            when x"08"|x"09"|x"0a"|x"0b"|x"0c"|x"0d"|x"0e"|x"0f" =>
              rdata_buf <= cache_row0_data(to_integer(address(2 downto 0)));

            when x"10" => rdata_buf(7) <= '1';
                          rdata_buf(6 downto 3) <= (others => '0');
                          rdata_buf(2 downto 0) <= cache_row1_address(23 downto 21);
            when x"11" => rdata_buf <= cache_row1_address(20 downto 13);
            when x"12" => rdata_buf <= cache_row1_address(12 downto 5);
            when x"13" => rdata_buf(7 downto 3) <= cache_row1_address(4 downto 0);
                          rdata_buf(2 downto 0) <= "000";
            when x"14" => rdata_buf <= unsigned(cache_row1_valids);
            when x"15" => rdata_buf <= x"AA";
            when x"16" => rdata_buf <= x"AA";
            when x"17" => rdata_buf <= x"AA";
            when x"18"
              |  x"19"
              |  x"1a"
              |  x"1b"
              |  x"1c"
              |  x"1d"
              |  x"1e"
              |  x"1f" => rdata_buf <= cache_row1_data(to_integer(address(2 downto 0)));

            when x"20" => rdata_buf <= write_collect0_address(23 downto 16);
            when x"21" => rdata_buf <= write_collect0_address(15 downto 8);
            when x"22" => rdata_buf(7 downto 3) <= write_collect0_address(7 downto 3);
                          rdata_buf(2 downto 0) <= "000";
            when x"23" => rdata_buf <= x"AA";
            when x"24" => rdata_buf <= unsigned(write_collect0_valids);
            when x"25" => rdata_buf <= x"AA";
            when x"26" => rdata_buf <= x"00";
                          rdata_buf(4) <= write_collect0_dispatchable;
                          rdata_buf(1) <= write_collect0_toolate;
                          rdata_buf(0) <= write_collect0_flushed;
            when x"27" => rdata_buf <= x"AA";
            when x"28"
              |  x"29"
              |  x"2a"
              |  x"2b"
              |  x"2c"
              |  x"2d"
              |  x"2e"
              |  x"2f" => rdata_buf <= write_collect0_data(to_integer(address(2 downto 0)));

            when x"30" => rdata_buf <= write_collect1_address(23 downto 16);
            when x"31" => rdata_buf <= write_collect1_address(15 downto 8);
            when x"32" => rdata_buf(7 downto 3) <= write_collect1_address(7 downto 3);
                          rdata_buf(2 downto 0) <= "000";
            when x"33" => rdata_buf <= x"AA";
            when x"34" => rdata_buf <= unsigned(write_collect1_valids);
            when x"35" => rdata_buf <= x"AA";
            when x"36" => rdata_buf <= x"00";
                          rdata_buf(4) <= write_collect1_dispatchable;
                          rdata_buf(1) <= write_collect1_toolate;
                          rdata_buf(0) <= write_collect1_flushed;
            when x"37" => rdata_buf <= x"AA";
            when x"38"
              |  x"39"
              |  x"3a"
              |  x"3b"
              |  x"3c"
              |  x"3d"
              |  x"3e"
              |  x"3f" => rdata_buf <= write_collect1_data(to_integer(address(2 downto 0)));

            when x"40" => rdata_buf <= block_address(23 downto 16);
            when x"41" => rdata_buf <= block_address(15 downto 8);
            when x"42" => rdata_buf(7 downto 5) <= block_address(7 downto 5);
                          rdata_buf(4 downto 0) <= "00000";
            when x"43" => rdata_buf <= x"AA";
            when x"44" => rdata_buf <= x"00";
                          if (block_valid='1') then rdata_buf <= x"FF"; end if;

            when x"50"
              |  x"51"
              |  x"52"
              |  x"53"
              |  x"54"
              |  x"55"
              |  x"56"
              |  x"57" => rdata_buf <= block_data(0)(to_integer(address(2 downto 0)));
            when x"58"
              |  x"59"
              |  x"5a"
              |  x"5b"
              |  x"5c"
              |  x"5d"
              |  x"5e"
              |  x"5f" => rdata_buf <= block_data(1)(to_integer(address(2 downto 0)));


            when x"60"
              |  x"61"
              |  x"62"
              |  x"63"
              |  x"64"
              |  x"65"
              |  x"66"
              |  x"67" => rdata_buf <= block_data(2)(to_integer(address(2 downto 0)));
            when x"68"
              |  x"69"
              |  x"6a"
              |  x"6b"
              |  x"6c"
              |  x"6d"
              |  x"6e"
              |  x"6f" => rdata_buf <= block_data(3)(to_integer(address(2 downto 0)));

            when x"80" => rdata_buf <= viciv_request_count(31 downto 24);
            when x"81" => rdata_buf <= viciv_request_count(23 downto 16);
            when x"82" => rdata_buf <= viciv_request_count(15 downto 8);
            when x"83" => rdata_buf <= viciv_request_count( 7 downto 0);

            when x"90" => rdata_buf(2 downto 0) <= current_cache_line_address_drive(26 downto 24);
                          rdata_buf(7) <= '1';
                          rdata_buf(6 downto 3) <= "0000";
            when x"91" => rdata_buf <= current_cache_line_address_drive(23 downto 16);
            when x"92" => rdata_buf <= current_cache_line_address_drive(15 downto 8);
            when x"93" => rdata_buf(7 downto 3) <= current_cache_line_address_drive( 7 downto 3);
                          rdata_buf(2 downto 0) <= "000";
            when x"94" => rdata_buf <= (others => current_cache_line_valid_drive);

            when x"98"
              |  x"99"
              |  x"9a"
              |  x"9b"
              |  x"9c"
              |  x"9d"
              |  x"9e"
              |  x"9f" => rdata_buf <= current_cache_line_drive(to_integer(address(2 downto 0)));


            -- LUMP debug (#949)
            when x"a0" | x"a1" | x"a2" | x"a3" | x"a4" | x"a5" | x"a6" | x"a7"
              |  x"a8" | x"a9" | x"aa" | x"ab" | x"ac" | x"ad" | x"ae" | x"af" =>
              rdata_buf <= lump_dbg_raw(to_integer(address(3 downto 0)));
            when x"b0" => rdata_buf <= unsigned(lump_dbg_rwds(7 downto 0));
            when x"b1" => rdata_buf <= unsigned(lump_dbg_rwds(15 downto 8));
            when x"b2" => rdata_buf <= lump_dbg_cyc;
            when x"b3" => rdata_buf <= lump_dbg_rw;
            when x"b4" => rdata_buf <= lump_dbg_wq;
            when x"b5" => rdata_buf <= lump_dbg_wb;
            when x"b6" => rdata_buf <= lump_dbg_wcyc;
            when x"b7" => rdata_buf <= lump_dbg_nr;
            when x"b8" => rdata_buf <= lump_dbg_nw;
            when x"b9" => rdata_buf <= "0000" & lump_slow & fast_write_mode & fast_read_mode & fast_cmd_mode;
            when x"ba" => rdata_buf <= to_unsigned(read_time_adjust, 8);
            -- CPU path v2 (#949): read hits and misses
            when x"c0" => rdata_buf <= v2_hits(7 downto 0);
            when x"c1" => rdata_buf <= v2_hits(15 downto 8);
            when x"c2" => rdata_buf <= v2_misses(7 downto 0);
            when x"c3" => rdata_buf <= v2_misses(15 downto 8);
            when others => rdata_buf <= x"BF";
          end case;
          report "flipping read_publish_toggle";
          read_publish_toggle <= not read_publish_toggle;
          report "flipping read_publish_toggle for debug register read";
        elsif address(23 downto 4) = x"FFFFF" and address(25 downto 24) = "11" then
          -- Allow reading from dummy debug bitbash registers at $BFFFFFx
          case address(3 downto 0) is
            when x"0" =>
              rdata_buf <= to_unsigned(write_continues_max,8);
            when x"1" =>
              rdata_buf <= viciv_bank;
            when x"2" =>
              rdata_buf(0) <= fast_cmd_mode;
              rdata_buf(1) <= fast_read_mode;
              rdata_buf(2) <= fast_write_mode;
              rdata_buf(3) <= read_phase_shift;
              rdata_buf(4) <= block_read_enable;
              rdata_buf(5) <= flag_prefetch;
              rdata_buf(6) <= enable_current_cache_line;
              if cache_enabled then
                rdata_buf(7) <= '1';
              else
                rdata_buf(7) <= '0';
              end if;
            when x"3" =>
              rdata_buf <= write_latency;
            when x"4" =>
              rdata_buf <= extra_write_latency;
            when x"5" =>
              rdata_buf <= to_unsigned(read_time_adjust,8);
            when x"6" =>
              rdata_buf <= rwr_delay;
            when x"7" =>
              rdata_buf <= unsigned(v2_flags);
            when x"8" =>
              rdata_buf <= conf_buf0;
            when x"9" =>
              rdata_buf <= conf_buf1;

            when x"a" =>
              rdata_buf <= cache_row0_address(7 downto 0);
            when x"b" =>
              rdata_buf <= cache_row0_address(15 downto 8);
            when x"c" =>
              rdata_buf <= cache_row0_address(23 downto 16);

            when x"d" =>
              rdata_buf <= write_latency2;
            when x"e" =>
              rdata_buf <= extra_write_latency2;
            when x"f" =>
              rdata_buf <= x"00";
              rdata_buf(0) <= viciv_data_debug;
              rdata_buf(1) <= viciv_debug_priority;
            when others =>
              -- This seems to be what gets returned all the time
              rdata_buf <= x"42";
          end case;
          read_publish_toggle <= not read_publish_toggle;
        elsif request_accepted = request_toggle then
          -- Normal RAM read.
          report "request_toggle flipped";
          ram_reading <= '1';
          ram_address <= address;
          ram_normalfetch <= true;
          -- We just need to check if there is a pre-fetch already
          -- queued for this same address
          if address(26 downto 3) = ram_address(26 downto 3) and ram_prefetch then
            report "DISPATCH: Merging read with pre-fetch.";
          else
            report "DISPATCH: Cancelling pre-fetch to prioritise explicit read";
            ram_prefetch <= false;
          end if;
          request_toggle <= not request_toggle;
        end if;
      elsif queued_write='1' and write_collect0_dispatchable='0' and write_collect0_flushed='0'
        and write_collect0_toolate='0' then

        report "DISPATCH: Executing queued write to $" & to_hstring(queued_waddr);

        -- Push it out as a normal batched write, that can collect others if they
        -- come soon enough.

        write_collect0_valids <= (others => '0');
        if queued_wen_lo='1' then
          write_collect0_valids(to_integer(queued_waddr(2 downto 0))) <= '1';
          write_collect0_data(to_integer(queued_waddr(2 downto 0))) <= queued_wdata;
        end if;
        if queued_wen_hi='1' then
          write_collect0_valids(to_integer(queued_waddr(2 downto 0))+1) <= '1';
          write_collect0_data(to_integer(queued_waddr(2 downto 0))+1) <= queued_wdata_hi;
        end if;
        write_collect0_address <= queued_waddr(26 downto 3);
        write_collect0_dispatchable <= '1';
        show_collect0 := true;

        queued_write <= '0';

      elsif (write_request_o or write_request_latch)='1' and busy_internal='0' then
        report "Making write request: addr $" & to_hstring(address) & " <= " & to_hstring(wdata);
        -- Begin write request
        -- Latch address and data

        write_request_latch <= '0';

        if address(23 downto 4) = x"FFFFF" and address(25 downto 24) = "11" then
          -- @IO:GS $BFFFFF0 - $BFFFFFF HYRAM!DEBUG Special HyperRAM setting registers used for debugging
          case address(3 downto 0) is
            when x"0" =>
              write_continues_max <= to_integer(wdata);
            when x"1" =>
              viciv_bank <= wdata;
            when x"2" =>
              boot_fast_pending <= '0';
              fast_cmd_mode <= wdata(0);
              fast_read_mode <= wdata(1);
              fast_write_mode <= wdata(2);
              read_phase_shift <= wdata(3);
              block_read_enable <= wdata(4);
              flag_prefetch <= wdata(5);
              enable_current_cache_line <= wdata(6);
              if wdata(7)='1' then
                cache_enabled <= true;
              else
                cache_enabled <= false;
              end if;
            when x"7" =>
              -- @IO:GS $BFFFFF7 HYRAM!CPUPATH CPU path: bit 0 the v2 path (cache, posted writes), bit 1 prefetch, bit 2 early next-line prefetch
              v2_flags <= std_logic_vector(wdata);
            when x"3" =>
              write_latency <= wdata;
            when x"4" =>
              extra_write_latency <= wdata;
            when x"5" =>
              read_time_adjust <= to_integer(wdata);
            when x"6" =>
              rwr_delay <= wdata;
            when x"8" =>
              conf_buf0_in <= wdata;
              conf_buf0_set <= not conf_buf0_set;
            when x"9" =>
              -- @IO:GS $BFFFFF8 HYRAM!CR0HI HyperRAM configuration register 0, high byte (write first)
              -- @IO:GS $BFFFFF9 HYRAM!CR0LO HyperRAM configuration register 0, low byte: writing it sends $BFFFFF8/9 to the HyperRAM's CR0
              conf_buf1_in <= wdata;
              conf_buf1_set <= not conf_buf1_set;
              -- The write latencies follow CR0's initial latency (bits 7-4:
              -- $E = 3, $F = 4, $0 = 5, $1 = 6 clocks): 2N-3 and, for the
              -- doubled latency (fixed latency, or a refresh collision),
              -- 2N-1 more, counted in byte times.  N = 4 gives the reset
              -- values, 5 and 7.  Write $BFFFFF3/4 afterwards to override.
              -- (Chip 0 only: the trapdoor HyperRAM keeps write_latency2.)
              case wdata(7 downto 4) is
                when x"E" => write_latency <= to_unsigned(3,8); extra_write_latency <= to_unsigned(5,8);
                when x"F" => write_latency <= to_unsigned(5,8); extra_write_latency <= to_unsigned(7,8);
                when x"0" => write_latency <= to_unsigned(7,8); extra_write_latency <= to_unsigned(9,8);
                when x"1" => write_latency <= to_unsigned(9,8); extra_write_latency <= to_unsigned(11,8);
                when others => null;    -- reserved codes: leave them
              end case;
              -- Send it: queue a write to register space, CR0 (word $800),
              -- exactly as a CPU write to $A001000 would.  Register writes
              -- take their 16 bits from conf_buf0/1, not from the data.
              if queued_write = '0' then
                queued_waddr <= CR0_ADDRESS;
                queued_wdata <= x"00";
                queued_wdata_hi <= x"00";
                queued_wen_lo <= '1';
                queued_wen_hi <= '0';
                queued_write <= '1';
              else
                queued2_waddr <= CR0_ADDRESS;
                queued2_wdata <= x"00";
                queued2_wdata_hi <= x"00";
                queued2_wen_lo <= '1';
                queued2_wen_hi <= '0';
                queued2_write <= '1';
              end if;
            when x"d" =>
              write_latency2 <= wdata;
            when x"e" =>
              extra_write_latency2 <= wdata;
            when x"f" =>
              viciv_data_debug <= wdata(0);
              viciv_debug_priority <= wdata(1);
            when others =>
              null;
          end case;
        else
          -- Always do cached writes, as apart from the latency before
          -- they get written out, it seems to be pretty reliable
          -- if cache_enabled = false then
          if false then
            -- Do normal  write request
            report "request_toggle flipped";
            report "DISPATCH: Accepted non-cached write";
            ram_prefetch <= false;
            ram_normalfetch <= true;
            request_toggle <= not request_toggle;
            ram_reading <= '0';
            ram_address <= address;
            ram_wdata <= wdata;
            ram_wdata_hi <= wdata_hi;
            ram_wdata_enlo <= wen_lo;
            ram_wdata_enhi <= wen_hi;
          else
            -- Collect writes together for dispatch

            -- Can we add the write to an existing collected write?
            if write_collect0_toolate = '0' and write_collect0_address = address(26 downto 3)
              and write_collect0_dispatchable = '1' and write_collect0_toolate='0'
            then
              if wen_lo='1' then
                write_collect0_valids(to_integer(address(2 downto 0))) <= '1';
                write_collect0_data(to_integer(address(2 downto 0))) <= wdata;
              end if;
              if wen_hi='1' then
                write_collect0_valids(to_integer(address(2 downto 0))+1) <= '1';
                write_collect0_data(to_integer(address(2 downto 0))+1) <= wdata_hi;
              end if;
              show_collect0 := true;
            elsif write_collect1_toolate = '0' and write_collect1_address = address(26 downto 3)
              and write_collect1_dispatchable = '1' and write_collect1_toolate='0' then
              if wen_lo='1' then
                write_collect1_valids(to_integer(address(2 downto 0))) <= '1';
                write_collect1_data(to_integer(address(2 downto 0))) <= wdata;
              end if;
              if wen_hi='1' then
                write_collect1_valids(to_integer(address(2 downto 0))+1) <= '1';
                write_collect1_data(to_integer(address(2 downto 0))+1) <= wdata_hi;
              end if;
              show_collect1 := true;
            elsif write_collect0_dispatchable = '0' and write_collect0_toolate='0' then
              write_collect0_valids <= (others => '0');
              if wen_lo='1' then
                write_collect0_valids(to_integer(address(2 downto 0))) <= '1';
                write_collect0_data(to_integer(address(2 downto 0))) <= wdata;
              end if;
              if wen_hi='1' then
                write_collect0_valids(to_integer(address(2 downto 0))+1) <= '1';
                write_collect0_data(to_integer(address(2 downto 0))+1) <= wdata_hi;
              end if;

              write_collect0_address <= address(26 downto 3);
              write_collect0_dispatchable <= '1';
              -- Block further writes if we already have one busy write buffer
              write_blocked <= '1';
              show_collect0 := true;
            elsif write_collect1_dispatchable = '0' and write_collect1_toolate='0' then
              write_collect1_valids <= (others => '0');
              if wen_lo='1' then
                write_collect1_valids(to_integer(address(2 downto 0))) <= '1';
                write_collect1_data(to_integer(address(2 downto 0))) <= wdata;
              end if;
              if wen_hi='1' then
                write_collect1_valids(to_integer(address(2 downto 0))+1) <= '1';
                write_collect1_data(to_integer(address(2 downto 0))+1) <= wdata_hi;
              end if;
              write_collect1_address <= address(26 downto 3);
              write_collect1_dispatchable <= '1';
              -- Block further writes if we already have one busy write buffer
              write_blocked <= '1';
              show_collect1 := true;
            else
              -- No write collection point that we can use, so just block until
              -- one becomes available
              report "DISPATCH: Write blocked due to busy write buffers: " &
                " addr $" & to_hstring(address) & " <= " & to_hstring(wdata);
              if queued_write='1' then
                -- Bother. We already had a queued write.
                -- So remember that one, too
                report "Stashing in queued2";
                queued2_waddr <= address;
                queued2_wdata <= wdata;
                queued2_wdata_hi <= wdata_hi;
                queued2_wen_lo <= wen_lo;
                queued2_wen_hi <= wen_hi;
                queued2_write <= '1';
              else
                report "Stashing in queued";
                queued_waddr <= address;
                queued_wdata <= wdata;
                queued_wdata_hi <= wdata_hi;
                queued_wen_lo <= wen_lo;
                queued_wen_hi <= wen_hi;
                queued_write <= '1';
              end if;

            end if;

            -- Update read cache structures when writing
            report "CACHE: Requesting update of cache due to write: $" & to_hstring(address) & " = $" & to_hstring(wdata);
            cache_row_update_address <= address(26 downto 3);
            cache_row_update_address_changed <= '1';
            cache_row_update_byte <= to_integer(address(2 downto 0));
            cache_row_update_value <= wdata;
            cache_row_update_value_hi <= wdata_hi;
            cache_row_update_lo <= wen_lo;
            cache_row_update_hi <= wen_hi;
            if cache_row_update_toggle = not last_cache_row_update_toggle then
              -- At least one other cache update is pending.  This means that
              -- we will not be able to keep the cache consistent.  The only
              -- option is to invalidate the read cache rows, data block,
              -- and current_cache_line.
              invalidate_read_cache <= '1';
            else
              cache_row_update_toggle <= not last_cache_row_update_toggle;
            end if;

          end if;
        end if;
      else
        -- Nothing new to do
      end if;

    end if;
    -- Optionally delay HR_CLK by 1/2 an 160MHz clock cycle
    -- (actually just by optionally inverting it)
    if rising_edge(clock325) then

      if show_cache0 or show_always then
        report "cache_row0_address_matches_cache_row_update_address="
          & std_logic'image(cache_row0_address_matches_cache_row_update_address)
          & ", cache_row_update_address=$" & to_hstring(cache_row_update_address&"000");
        report "CACHE cache0: address=$" & to_hstring(cache_row0_address&"000") & ", valids=" & to_string(cache_row0_valids)
          & ", data = "
          & to_hstring(cache_row0_data(0)) & " "
          & to_hstring(cache_row0_data(1)) & " "
          & to_hstring(cache_row0_data(2)) & " "
          & to_hstring(cache_row0_data(3)) & " "
          & to_hstring(cache_row0_data(4)) & " "
          & to_hstring(cache_row0_data(5)) & " "
          & to_hstring(cache_row0_data(6)) & " "
          & to_hstring(cache_row0_data(7)) & " ";
        show_cache0 := false;
      end if;

      if show_cache1 or show_always then
        report "CACHE cache1: address=$" & to_hstring(cache_row1_address&"000") & ", valids=" & to_string(cache_row1_valids)
          & ", data = "
          & to_hstring(cache_row1_data(0)) & " "
          & to_hstring(cache_row1_data(1)) & " "
          & to_hstring(cache_row1_data(2)) & " "
          & to_hstring(cache_row1_data(3)) & " "
          & to_hstring(cache_row1_data(4)) & " "
          & to_hstring(cache_row1_data(5)) & " "
          & to_hstring(cache_row1_data(6)) & " "
          & to_hstring(cache_row1_data(7)) & " ";
        show_cache1 := false;
      end if;
      if show_collect0 or show_always then
        report "CACHE write0: $" & to_hstring(write_collect0_address&"000") & ", v=" & to_string(write_collect0_valids)
          & ", d=" & std_logic'image(write_collect0_dispatchable)
          & ", late=" & std_logic'image(write_collect0_toolate)
          & ", fl=" & std_logic'image(write_collect0_flushed)
          & ", data = "
          & to_hstring(write_collect0_data(0)) & " "
          & to_hstring(write_collect0_data(1)) & " "
          & to_hstring(write_collect0_data(2)) & " "
          & to_hstring(write_collect0_data(3)) & " "
          & to_hstring(write_collect0_data(4)) & " "
          & to_hstring(write_collect0_data(5)) & " "
          & to_hstring(write_collect0_data(6)) & " "
          & to_hstring(write_collect0_data(7)) & " ";
        show_collect0 := false;
      end if;
      if show_collect1 or show_always then
        report "CACHE write1: $" & to_hstring(write_collect1_address&"000") & ", v=" & to_string(write_collect1_valids)
          & ", d=" & std_logic'image(write_collect1_dispatchable)
          & ", late=" & std_logic'image(write_collect1_toolate)
          & ", fl=" & std_logic'image(write_collect1_flushed)
          & ", data = "
          & to_hstring(write_collect1_data(0)) & " "
          & to_hstring(write_collect1_data(1)) & " "
          & to_hstring(write_collect1_data(2)) & " "
          & to_hstring(write_collect1_data(3)) & " "
          & to_hstring(write_collect1_data(4)) & " "
          & to_hstring(write_collect1_data(5)) & " "
          & to_hstring(write_collect1_data(6)) & " "
          & to_hstring(write_collect1_data(7)) & " ";
        show_collect1 := false;
      end if;
      if show_block or show_always then
        report "CACHE block0: $" & to_hstring(block_address&"00000") & ", valid=" & std_logic'image(block_valid)
          & ", byte_phase=" & integer'image(to_integer(byte_phase));
        for i in 0 to 3 loop
          report "CACHE block0 segment " & integer'image(i) & ": "
            & to_hstring(block_data(i)(0)) & " "
            & to_hstring(block_data(i)(1)) & " "
            & to_hstring(block_data(i)(2)) & " "
            & to_hstring(block_data(i)(3)) & " "
            & to_hstring(block_data(i)(4)) & " "
            & to_hstring(block_data(i)(5)) & " "
            & to_hstring(block_data(i)(6)) & " "
            & to_hstring(block_data(i)(7)) & " ";
        end loop;
        show_block := false;
      end if;


      hr_clock_phase_drive <= hr_clock_phase;
      hr_clock_phase <= hr_clock_phase + 1;
      -- Changing at the end of a phase cycle prevents us having any
      -- problematically short clock pulses when it matters.
      if hr_clock_phase_drive="110" then
        hr_clk_fast_current <= hr_clk_fast;
        hr_clk_phaseshift_current <= hr_clk_phaseshift;
        if hr_clk_fast /= hr_clk_fast_current or hr_clk_phaseshift_current /= hr_clk_phaseshift then
          report "Updating hr_clock_fast to " & std_logic'image(hr_clk_fast)
            & ", hr_clk_phaseshift to " & std_logic'image(hr_clk_phaseshift);
        end if;
      end if;

      -- Only change clock mode when safe to do so
      clock_status_vector(4) := hr_clk_fast_current;
      clock_status_vector(3) := hr_clk_phaseshift_current;
      clock_status_vector(2 downto 0) := hr_clock_phase;
      report "clock phase vector = " & to_string(std_logic_vector(clock_status_vector));
      case clock_status_vector is
        -- Slow clock rate, no phase shift
        when "00000" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';
        when "00001" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';
        when "00010" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';
        when "00011" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';
        when "00100" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';
        when "00101" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';
        when "00110" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';
        when "00111" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';

        -- Slow clock rate, with phase shift = bring forward tick by 1/2 a cycle
        when "01000" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';
        when "01001" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';
        when "01010" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';
        when "01011" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';
        when "01100" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';
        when "01101" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';
        when "01110" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';
        when "01111" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';

        -- Fast clock rate, no phase shift
        when "10000" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';
        when "10001" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';
        when "10010" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';
        when "10011" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';
        when "10100" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';
        when "10101" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';
        when "10110" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';
        when "10111" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';

        -- Fast clock rate, with phase shift
        when "11000" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';
        when "11001" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';
        when "11010" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';
        when "11011" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';
        when "11100" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';
        when "11101" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';
        when "11110" => hr_clk <= '1'; hr_clk_p <= '1'; hr_clk_n <= '0';
                        hr2_clk_p <= '1'; hr2_clk_n <= '0';
        when "11111" => hr_clk <= '0'; hr_clk_p <= '0'; hr_clk_n <= '1';
                        hr2_clk_p <= '0'; hr2_clk_n <= '1';

        when others => hr_clk <= '0';  hr_clk_p <= '0'; hr_clk_n <= '1';
                       hr2_clk_p <= '0'; hr2_clk_n <= '1';
      end case;

    end if;

    if rising_edge(clock163) then
      hr_clock_phase165 <= hr_clock_phase165 + 1;

      -- LUMP: single-cycle strobes default low
      v2_inval         <= '0';
      lump_q_pop       <= '0';
      le_rdata_valid <= '0';
      le_wdata_req   <= '0';
      le_cmd_done    <= '0';
      le_error       <= '0';
      lump_idle        <= not (lump_q_valid or is_lump or lump_inval_req or lump_q_pop or lump_res);

      -- Pre-compute everything the Idle-state LUMP dispatch needs, one cycle
      -- ahead.  The cycle after a pop, lump_q_pop='1' forces these low, and
      -- the head is updated by the time they are next computed, so the
      -- registered view is always consistent with the queue.  Branches that
      -- consume a command also clear the relevant flag explicitly.
      -- A v2 CPU-path job takes the engine before LUMP does, and LUMP waits
      -- while v2 holds posted writes (it must not read around them).
      lump_cmd_pre(46) <= '0';               -- memory, not registers
      lump_cmd_pre(45) <= '1';               -- linear
      lump_cmd_pre(44 downto 35) <= (others => '0');
      lump_cmd_pre(15 downto 3) <= (others => '0');
      lump_cmd_pre(1 downto 0) <= "00";
      if (cj_req = '1' and (cj_pf = '0' or w_stall = '1' or want_fill = '1' or vic_want = '1'))
        or request_toggle /= last_request_toggle or read_request_latch = '1'
        or (v2_en = '0' and viciv_request_toggle /= viciv_last_request_toggle)
        or write_collect0_dispatchable = '1' or write_collect1_dispatchable = '1' then
        lump_yield <= '1';
      else
        lump_yield <= '0';
      end if;
      if cj_req = '1' then
        lump_pre_cpu <= '1';
        lump_pre_res <= '0';
        lump_go      <= '1';
        lump_inv_go  <= '0';
        lump_is_read <= cj_read;
        lump_cnt_init <= cj_cnt_init;
        lump_addr_pre <= cj_tag;
        lump_cmd_pre(47) <= cj_read;
        lump_cmd_pre(34 downto 16) <= cj_tag(22 downto 4);
        lump_cmd_pre(2) <= cj_tag(3);
      elsif lump_res = '1' then
        -- resume the paused LUMP command
        lump_pre_cpu <= '0';
        lump_pre_res <= '1';
        if w_mask(0) = x"00" and w_mask(1) = x"00" and cj_busy = '0' then
          lump_go <= '1';
        else
          lump_go <= '0';
        end if;
        lump_inv_go <= '0';
        lump_is_read <= lump_res_read;
        lump_cnt_init <= lump_res_cnt;
        lump_addr_pre <= lump_res_addr;
        lump_cmd_pre(47) <= lump_res_read;
        lump_cmd_pre(34 downto 16) <= lump_res_addr(22 downto 4);
        lump_cmd_pre(2) <= lump_res_addr(3);
      else
        lump_pre_cpu <= '0';
        lump_pre_res <= '0';
        if w_mask(0) = x"00" and w_mask(1) = x"00" and cj_busy = '0' then
          lump_go <= lump_q_valid and (not lump_q_op(1)) and (not lump_q_pop);
        else
          lump_go <= '0';
        end if;
        lump_inv_go <= lump_q_valid and lump_q_op(1) and (not lump_q_pop);
        if lump_q_op = LUMP_OP_READ then
          lump_is_read <= '1';
        else
          lump_is_read <= '0';
        end if;
        lump_cnt_init <= signed(resize(lump_q_len(8 downto 1), 9)) - 2;
        lump_addr_pre <= lump_q_addr(26 downto 3);
        -- Linear burst command in memory space (address is 8-byte aligned)
        lump_cmd_pre(47) <= not lump_q_op(0);  -- READ=1 (op "00"), WRITE=0 ("01")
        lump_cmd_pre(34 downto 16) <= lump_q_addr(22 downto 4);
        lump_cmd_pre(2) <= lump_q_addr(3);
      end if;
      -- LUMP is the lowest-priority requester: only dispatch if nobody else
      -- wanted the bus last cycle.  (Something arriving in the very cycle we
      -- dispatch simply waits for one burst.)
      if request_toggle = last_request_toggle
        and viciv_request_toggle = viciv_last_request_toggle
        and (not prefetch_when_idle)
        and write_collect0_dispatchable = '0'
        and write_collect1_dispatchable = '0' then
        lump_bus_free <= '1';
      else
        lump_bus_free <= '0';
      end if;

      cycle_count <= cycle_count + 1;

      if read_request_delatch='1' and read_request_latch='0' then
        read_request_delatch <= '0';
      end if;

      hyperram_access_address_read_time_adjusted <= to_unsigned(to_integer(hyperram_access_address(2 downto 0))+read_time_adjust,6);
      seven_plus_read_time_adjust <= to_unsigned(7 + read_time_adjust,6);
      thirtyone_plus_read_time_adjust <= to_unsigned(31 + read_time_adjust,6);

      -- We run double the clock speed of the pixelclock area, so no request
      -- can come in during the extra drive cycle we use to update these values
      -- so as to improve the timing closure of the whole thing
      ram_wdata_drive <= ram_wdata;
      ram_wdata_hi_drive <= ram_wdata_hi;
      ram_address_drive <= ram_address;
      ram_reading_drive <= ram_reading;
      ram_wdata_enlo_drive <= ram_wdata_enlo;
      ram_wdata_enhi_drive <= ram_wdata_enhi;
      if ram_address(26 downto 3) = current_cache_line_address(26 downto 3) then
        ram_address_matches_current_cache_line_address <= '1';
      else
        ram_address_matches_current_cache_line_address <= '0';
      end if;
      if cache_row0_address = ram_address(26 downto 3) then
        cache_row0_address_matches_ram_address <= '1';
      else
        cache_row0_address_matches_ram_address <= '0';
      end if;
      if cache_row1_address = ram_address(26 downto 3) then
        cache_row1_address_matches_ram_address <= '1';
      else
        cache_row1_address_matches_ram_address <= '0';
      end if;
      if write_collect0_address = background_write_next_address then
        background_write_next_address_matches_collect0 <= '1';
      else
        background_write_next_address_matches_collect0 <= '0';
      end if;
      if write_collect1_address = background_write_next_address then
        background_write_next_address_matches_collect1 <= '1';
      else
        background_write_next_address_matches_collect1 <= '0';
      end if;
      if write_collect1_address = write_collect0_address + 1 then
        collect1_matches_collect0_plus_1 <= '1';
      else
        collect1_matches_collect0_plus_1 <= '0';
      end if;
      if write_collect0_address = write_collect1_address + 1 then
        collect0_matches_collect1_plus_1 <= '1';
      else
        collect0_matches_collect1_plus_1 <= '0';
      end if;


      if address(26 downto 5) = block_address then
        block_address_matches_address <= '1';
      else
        block_address_matches_address <= '0';
      end if;

      if address(26 downto 5) = hyperram_access_address(26 downto 5) then
        address_matches_hyperram_access_address_block <= '1';
      else
        address_matches_hyperram_access_address_block <= '0';
      end if;
      if read_request_o='1' or read_request_held='1' then
        read_request_prev <= '1';
      else
        read_request_prev <= '0';
      end if;
      if write_request_o='1' or write_request_held='1' then
        write_request_prev <= '1';
      else
        write_request_prev <= '0';
      end if;

      if write_collect0_address = (write_collect1_address + 1) then
        write_collect0_address_matches_write_collect1_address_plus_1 <= '1';
      else
        write_collect0_address_matches_write_collect1_address_plus_1 <= '0';
      end if;

      if to_integer(byte_phase) > to_integer(address(4 downto 0)) then
        byte_phase_greater_than_address_low_bits <= '1';
      else
        byte_phase_greater_than_address_low_bits <= '0';
      end if;
      if to_integer(byte_phase) > to_integer(address(4 downto 3)&"111") then
        byte_phase_greater_than_address_end_of_row <= '1';
      else
        byte_phase_greater_than_address_end_of_row <= '0';
      end if;


      -- Update short-circuit cache line
      -- (We don't change validity, since we don't know if it is
      -- valid or not).
      if ram_address_matches_current_cache_line_address = '1' then
        if ram_wdata_enlo_drive='1' then
          current_cache_line_drive(to_integer(hyperram_access_address(2 downto 0))) <= ram_wdata_drive;
        end if;
        if ram_wdata_enhi_drive='1' then
          current_cache_line_drive(to_integer(hyperram_access_address(2 downto 0))+1) <= ram_wdata_hi_drive;
        end if;
      end if;

      if current_cache_line_address(26 downto 5) = block_address(26 downto 5)
          and (current_cache_line_address(4 downto 3) /= "11") and (block_valid='1') then
        current_cache_line_matches_block <= '1';
      else
        current_cache_line_matches_block <= '0';
      end if;
      if (current_cache_line_address(26 downto 5) + 1) = block_address(26 downto 5)
        and (current_cache_line_address(4 downto 3) = "11") and (block_valid='1') then
          current_cache_line_plus_1_matches_block <= '1';
      else
        current_cache_line_plus_1_matches_block <= '0';
      end if;

      if cache_row0_address = hyperram_access_address(26 downto 3) then
        hyperram_access_address_matches_cache_row0 <= '1';
      else
        hyperram_access_address_matches_cache_row0 <= '0';
      end if;
      if cache_row1_address = hyperram_access_address(26 downto 3) then
        hyperram_access_address_matches_cache_row1 <= '1';
      else
        hyperram_access_address_matches_cache_row1 <= '0';
      end if;
      if cache_row0_address = cache_row_update_address then
        cache_row0_address_matches_cache_row_update_address <= '1';
      else
        cache_row0_address_matches_cache_row_update_address <= '0';
      end if;
      if cache_row1_address = cache_row_update_address then
        cache_row1_address_matches_cache_row_update_address <= '1';
      else
        cache_row1_address_matches_cache_row_update_address <= '0';
      end if;
      if block_address = cache_row_update_address(26 downto 5) then
        block_address_matches_cache_row_update_address <= '1';
      else
        block_address_matches_cache_row_update_address <= '0';
      end if;


      if enable_current_cache_line='1' and v2_en = '0' then
--        if current_cache_line /= current_cache_line_drive then
--          report "CACHE: Updating current_cache_line from drive. Now "
--            & to_hstring(current_cache_line_drive(0)) & " ...";
--        end if;
        current_cache_line <= current_cache_line_drive;
        current_cache_line_address <= current_cache_line_address_drive;
        current_cache_line_valid <= current_cache_line_valid_drive;
      end if;

      if mark_cache_for_prefetch /= last_mark_cache_for_prefetch
        or mark_cache_for_prefetch162 /= last_mark_cache_for_prefetch162 then
        last_mark_cache_for_prefetch <= mark_cache_for_prefetch;
        last_mark_cache_for_prefetch162 <= mark_cache_for_prefetch162;
        if random_bits(1)='0' then
          report "Zeroing cache_row0_valids";
          cache_row0_valids <= (others => '0');
          cache_row0_address <= ram_address(26 downto 3);
          cache_row0_address_matches_ram_address <= '1';
          show_cache0 := true;
        else
          report "Zeroing cache_row1_valids";
          cache_row1_valids <= (others => '0');
          cache_row1_address <= ram_address(26 downto 3);
          cache_row1_address_matches_ram_address <= '1';
          show_cache1 := true;
        end if;
      end if;

      data_ready_toggle_out <= data_ready_toggle_drive;
      -- read_publish_toggle is a toggle owned by the pixelclock side (cache,
      -- write-collect, block and register reads).  It used to be cleared
      -- from here as well (read_publish_toggle <= last_read_publish_toggle,
      -- with last_read_publish_toggle never written): a flip-flop driven
      -- from two clocks.  That simulates as a set/clear flag, but cannot be
      -- built as one, and on hardware every second such read was never
      -- published (the CPU then took the previous byte).  Now this side only
      -- follows it.
      if read_publish_toggle /= last_read_publish_toggle then
        last_read_publish_toggle <= read_publish_toggle;
        report "PUBLISH: rdata <= $" & to_hexstring(rdata_hi_buf) & to_hexstring(rdata_buf);

        rdata                  <= rdata_buf;
        rdata_hi               <= rdata_hi_buf;
        data_ready_toggle_drive      <= not last_data_ready_toggle_out;
        last_data_ready_toggle_out <= not last_data_ready_toggle_out;

      elsif read_publish_strobe2 = '1' then
        read_publish_strobe2 <= '0';
        report "PUBLISH: rdata <= $" & to_hexstring(rdata_hi_buf2) & to_hexstring(rdata_buf2);

        rdata                  <= rdata_buf2;
        rdata_hi               <= rdata_hi_buf2;
        data_ready_toggle_drive      <= not last_data_ready_toggle_out;
        last_data_ready_toggle_out <= not last_data_ready_toggle_out;
      end if;

      -- HyperRAM state machine
      report "State = " & state_t'image(state) & " @ Cycle " & integer'image(cycle_count)
        & ", config_reg_write=" & std_logic'image(config_reg_write);

      if conf_buf0_set /= last_conf_buf0_set then
        last_conf_buf0_set <= conf_buf0_set;
        conf_buf0 <= conf_buf0_in;
      end if;
      if conf_buf1_set /= last_conf_buf1_set then
        last_conf_buf1_set <= conf_buf1_set;
        conf_buf1 <= conf_buf1_in;
      end if;


      -- Invalidate cache if disabled
      if cache_enabled = false then
        report "Zeroing cache_row0_valids";
        cache_row0_valids <= (others => '0');
        cache_row1_valids <= (others => '0');
        current_cache_line_valid_drive <= '0';
        block_valid <= '0';
      end if;

      if current_cache_line_update_all = last_current_cache_line_update_all then
        if current_cache_line_update_address = current_cache_line_address_drive then
          for i in 0 to 7 loop
            if current_cache_line_update_flags(i) /= last_current_cache_line_update_flags(i)  then
              report "CACHE: Driving update to current_cache_line byte " & integer'image(i)
                & ", value $" & to_hstring(current_cache_line_update(i));
              last_current_cache_line_update_flags(i) <= current_cache_line_update_flags(i);
              current_cache_line_drive(i) <= current_cache_line_update(i);
            end if;
          end loop;
        else
          report "CACHE: Rejecting stale current line updates for $" & to_hstring(current_cache_line_update_address&"000");
        end if;
      else
        report "DISPATCHER: Replacing current cache line with $" & to_hstring(current_cache_line_new_address&"000");
        last_current_cache_line_update_all <= current_cache_line_update_all;
        current_cache_line_address_drive <= current_cache_line_new_address;
        current_cache_line_drive <= current_cache_line_update;
        last_current_cache_line_update_flags <= current_cache_line_update_flags;
      end if;

      -- See if slow_devices is asking for the next 8 bytes.
      -- If we have it, then pre-present it if we have it in our data block
      -- (If it isn't in the data block, then we will have presumably already
      -- started a pre-fetch when we serviced the access that created the current
      -- data value in the current cache line entry.
      -- This has to happen below the above single-byte update stuff, so that
      -- we end retain cache coherency
      if expansionram_current_cache_line_next_toggle /= last_current_cache_next_toggle then
        last_current_cache_next_toggle <= expansionram_current_cache_line_next_toggle;
        if current_cache_line_plus_1_matches_block = '1'
        then
          report "DISPATCHER: Presenting next 8 bytes to slow_devices. Was $"
            & to_hstring(current_cache_line_address&"000") & ", new is $"
            & to_hstring(current_cache_line_address(26 downto 5)&(current_cache_line_address(4 downto 3) + 1)&"000");
          current_cache_line_address_drive(26 downto 5) <= block_address;
          current_cache_line_address_drive(4 downto 3) <= "00";
          current_cache_line_drive <= block_data(0);
          current_cache_line_valid_drive <= '1';
          -- Cancel any other updates that might be scheduled for this
          last_current_cache_line_update_all <= current_cache_line_update_all;
          last_current_cache_line_update_flags <= current_cache_line_update_flags;
        end if;
        if current_cache_line_matches_block = '1'
        then
          report "DISPATCHER: Presenting next 8 bytes to slow_devices. Was $"
            & to_hstring(current_cache_line_address&"000") & ", new is $"
            & to_hstring(current_cache_line_address(26 downto 5)&(current_cache_line_address(4 downto 3) + 1)&"000")
            & ", data is:"
            & " " & to_hstring(block_data(to_integer(current_cache_line_address(4 downto 3)) + 1)(0))
            & " " & to_hstring(block_data(to_integer(current_cache_line_address(4 downto 3)) + 1)(1))
            & " " & to_hstring(block_data(to_integer(current_cache_line_address(4 downto 3)) + 1)(2))
            & " " & to_hstring(block_data(to_integer(current_cache_line_address(4 downto 3)) + 1)(3))
            & " " & to_hstring(block_data(to_integer(current_cache_line_address(4 downto 3)) + 1)(4))
            & " " & to_hstring(block_data(to_integer(current_cache_line_address(4 downto 3)) + 1)(5))
            & " " & to_hstring(block_data(to_integer(current_cache_line_address(4 downto 3)) + 1)(6))
            & " " & to_hstring(block_data(to_integer(current_cache_line_address(4 downto 3)) + 1)(7));
          current_cache_line_address_drive(4 downto 3) <= current_cache_line_address(4 downto 3) + 1;
          current_cache_line_drive <= block_data(to_integer(current_cache_line_address(4 downto 3)) + 1);
          current_cache_line_valid_drive <= '1';
          -- Cancel any other updates that might be scheduled for this
          last_current_cache_line_update_all <= current_cache_line_update_all;
          last_current_cache_line_update_flags <= current_cache_line_update_flags;

          -- If it was the last row in the block that we have just presented,
          -- it would be a really good idea to dispatch a pre-fetch right now.
          -- The trick is that we can only safely do this, if we are idle.
          if current_cache_line_address(4 downto 3) = "10" and flag_prefetch='1' then
            report "DISPATCHER: Queuing chained pre-fetch";
            prefetch_when_idle <= true;
          end if;

        end if;
      end if;

      -- Keep read request when required
      read_request_held <= read_request_o;
      write_request_held <= write_request_o;

      if start_delay_expired='0' then
        if no_start_delay then
          start_delay_counter <= 0;
        else
          start_delay_counter <= start_delay_counter - 1;
        end if;
        if start_delay_counter = 0 then
          report "HYPERRAM: Start delay expired";
          start_delay_expired <= '1';
          state <= WriteSetup;
        end if;
      end if;

--      report "CACHE: row update status: requested = " & boolean'image(cache_row_update_toggle /= last_cache_row_update_toggle)
--        & ", cache_row_update_address_changed = " & std_logic'image(cache_row_update_address_changed);

      if cache_row_update_toggle /= last_cache_row_update_toggle and cache_row_update_address_changed = '0' then
        if cache_row0_address_matches_cache_row_update_address = '1' then
          if cache_row_update_lo='1' then
            report "DISPATCH: Updating cache0 via write: $" & to_hstring((cache_row_update_address&"000")+cache_row_update_byte)
              & " gets $" & to_hstring(cache_row_update_value);
            cache_row0_valids(cache_row_update_byte) <= '1';
            cache_row0_data(cache_row_update_byte) <= cache_row_update_value;
          end if;
          if cache_row_update_hi='1' then
            report "DISPATCH: Updating cache0 via write: $" & to_hstring((cache_row_update_address&"001")+cache_row_update_byte)
              & " gets $" & to_hstring(cache_row_update_value_hi);
            cache_row0_valids(cache_row_update_byte+1) <= '1';
            cache_row0_data(cache_row_update_byte+1) <= cache_row_update_value_hi;
          end if;
          show_cache0 := true;
        end if;
        if cache_row1_address_matches_cache_row_update_address = '1' then
          if cache_row_update_lo='1' then
            report "DISPATCH: Updating cache1 via write: $" & to_hstring((cache_row_update_address&"000")+cache_row_update_byte)
              & " gets $" & to_hstring(cache_row_update_value);
            cache_row1_valids(cache_row_update_byte) <= '1';
            cache_row1_data(cache_row_update_byte) <= cache_row_update_value;
          end if;
          if cache_row_update_hi='1' then
            report "DISPATCH: Updating cache1 via write: $" & to_hstring((cache_row_update_address&"001")+cache_row_update_byte)
              & " gets $" & to_hstring(cache_row_update_value);
            cache_row1_valids(cache_row_update_byte+1) <= '1';
            cache_row1_data(cache_row_update_byte+1) <= cache_row_update_value_hi;
          end if;
          show_cache1 := true;
        end if;
        if block_address_matches_cache_row_update_address = '1' then
          if cache_row_update_lo='1' then
            report "DISPATCH: Updating block data via write: $" & to_hstring((cache_row_update_address&"000")+cache_row_update_byte)
              & " gets $" & to_hstring(cache_row_update_value);
            block_data(to_integer(cache_row_update_address(4 downto 3)))(cache_row_update_byte)
              <= cache_row_update_value;
          end if;
          if cache_row_update_hi='1' then
            report "DISPATCH: Updating block data via write: $" & to_hstring((cache_row_update_address&"001")+cache_row_update_byte)
              & " gets $" & to_hstring(cache_row_update_value_hi);
            block_data(to_integer(cache_row_update_address(4 downto 3)))(cache_row_update_byte+1)
              <= cache_row_update_value_hi;
          end if;
          show_block := true;
        end if;
      end if;

      if lump_inval_req = '1' then
        -- LUMP INVALIDATE command: everything queued before it has completed,
        -- so drop all CPU-side read caches.
        report "LUMP: Invalidating read caches";
        lump_inval_req <= '0';
        le_cmd_done <= '1';
        v2_inval <= '1';
        cache_row0_valids <= (others => '0');
        cache_row1_valids <= (others => '0');
        block_valid <= '0';
        current_cache_line_valid_drive <= '0';
      end if;

      if invalidate_read_cache='1' then
        report "CACHE: Invalidating read cache due to write congestion.";
        cache_row0_valids <= (others => '0');
        cache_row1_valids <= (others => '0');
        block_valid <= '0';
        current_cache_line_valid_drive <= '0';
        last_cache_row_update_toggle <= cache_row_update_toggle;
      end if;

      case state is
        when StartupDelay =>
          null;
        when ReadAbort =>
          -- Make sure we don't abort a read so quickly, that we allow
          -- glitching of clock line with clock phase shifting
          hr_cs0 <= '1';
          hr_cs1 <= '1';
          state <= Idle;
        when Idle =>
          report "Tristating hr_d";
          hr_d <= (others => 'Z');
          hr2_d <= (others => 'Z');

          read_request_held <= '0';
          write_request_held <= '0';

          -- LUMP INVALIDATE needs no bus cycle, so take it whenever it
          -- reaches the head of the queue.
          if lump_inv_go = '1' and lump_res = '0' then
            lump_q_pop <= '1';
            lump_inv_go <= '0';
            lump_inval_req <= '1';
          end if;

          if not cache_enabled then
            busy_internal <= '0';
          end if;

          first_transaction <= '0';
          is_block_read <= false;
          is_prefetch <= ram_prefetch;
          is_expected_to_respond <= ram_normalfetch;
          is_vic_fetch <= false;

          -- All commands need the clock offset by 1/2 cycle
          hr_clk_phaseshift <= write_phase_shift;
          hr_clk_fast <= '1';

          pause_phase <= '0';
          countdown_timeout <= '0';

          -- Clear write buffer flags when they are empty
          if write_collect0_dispatchable = '0' then
            if write_collect0_toolate = '1' then
              show_collect0 := true;
            end if;
            write_collect0_toolate <= '0';
            write_collect0_flushed <= '0';
          end if;
          if write_collect1_dispatchable = '0' then
            if write_collect1_toolate = '1' then
              show_collect1 := true;
            end if;
            write_collect1_toolate <= '0';
            write_collect1_flushed <= '0';
          end if;

          -- Mark us ready for a new job, or pick up a new job
          report
            "r_t=" & std_logic'image(request_toggle)
            & ", l_r_t=" & std_logic'image(last_request_toggle)
            & ", hr_clk=" & std_logic'image(hr_clk)
            & ", rwr_counter = " & integer'image(to_integer(rwr_counter));

          if rwr_counter /= to_unsigned(0,8) then
            rwr_counter <= rwr_counter - 1;
            hr_d <= x"bb";
            hr2_d <= x"bb";
          end if;
          if rwr_counter = to_unsigned(1,8) then
            rwr_waiting <= '0';
          end if;

          -- Phase 101 guarantees that the clock base change will happen
          -- within the comming clock cycle
          if rwr_waiting='0' and  hr_clock_phase165 = "10" then
            if lump_go = '1' and lump_bus_free = '1' then
              -- LUMP burst.  This branch is first in the chain so that its
              -- enable is just {state=Idle, rwr_waiting, phase(2), lump_go,
              -- lump_bus_free}: all flip-flops, one LUT6.  It is still the
              -- lowest priority requester, via lump_bus_free.
              -- busy_internal is deliberately left alone, so CPU requests
              -- continue to queue (and hit the caches) as usual.
              report "LUMP: Starting burst @ $" & to_hstring(lump_addr_pre & "000");
              lump_go <= '0';
              is_lump <= '1';
              lump_owner_cpu <= lump_pre_cpu;
              -- Nothing else is waiting (lump_bus_free), so the old path is
              -- free for requests during the burst, as Idle would have left
              -- it: a busy_internal left over from its last read held
              -- slow_devices off for the whole burst
              busy_internal <= '0';
              lump_cur_addr <= lump_addr_pre;
              lump_wg <= "00";
              lump_seg <= '0';
              lump_ng <= (others => '0');
              lump_ending <= '0';
              if lump_pre_cpu = '1' then
                -- a v2 CPU-path job (the LUMP queue is left alone)
                cj_req <= '0';
                cj_busy <= '1';
              elsif lump_pre_res = '1' then
                -- the rest of a paused LUMP command (already popped)
                lump_res <= '0';
                if lump_is_read = '0' then v2_inval <= '1'; end if;
              else
                lump_q_pop <= '1';
                lump_dbg_idx <= 0; lump_dbg_got <= '0'; lump_dbg_cyc <= x"00";
                lump_dbg_wgot <= '0'; lump_dbg_wcyc <= x"00";
                if lump_is_read = '1' then
                  lump_dbg_rw <= x"00"; lump_dbg_nr <= lump_dbg_nr + 1;
                else
                  lump_dbg_wq <= x"00"; lump_dbg_wb <= x"00"; lump_dbg_nw <= lump_dbg_nw + 1;
                  -- the v2 CPU path's cached copies may be stale after this
                  v2_inval <= '1';
                end if;
              end if;
              lump_cnt <= lump_cnt_init;
              lump_byte_odd <= '0';
              lump_flushing <= '0';

              is_prefetch <= false;
              is_expected_to_respond <= false;
              is_vic_fetch <= false;
              is_block_read <= false;
              background_write <= '0';
              config_reg_write <= '0';

              hr_command <= lump_cmd_pre;
              hr_reset <= '1';

              hyperram0_select <= not lump_addr_pre(23);
              hyperram1_select <= lump_addr_pre(23);
              hyperram_access_address(26 downto 3) <= lump_addr_pre;
              hyperram_access_address(2 downto 0) <= "000";

              pause_phase <= '0';
              countdown <= 6;
              countdown_is_zero <= '0';

              if lump_is_read = '1' then
                ram_reading_held <= '1';
                -- One setup cycle, as CPU reads have (ReadSetup): the command
                -- must start on the same clock163 cycle relative to the
                -- HyperRAM clock as theirs.  Going straight to the command
                -- state started it a cycle early, so every command and
                -- address byte changed on a HyperRAM clock edge (#949: LUMP
                -- reads from HyperRAM failed on hardware, but not in a
                -- zero-delay simulation).
                state <= PortReadSetup;
              else
                ram_reading_held <= '0';
                -- Same clock-phase synchronisation step as background writes
                state <= StartBackgroundWrite;
              end if;
            elsif v2_en = '0' and (viciv_request_toggle /= viciv_last_request_toggle)
              -- Only start VIC-IV fetches if we don't have a transaction
              -- already waiting to go.
              and ((request_toggle = last_request_toggle) or viciv_debug_priority='1')
              -- and, as for CPU reads, not past posted writes (#949)
              and write_collect0_dispatchable = '0'
              and write_collect1_dispatchable = '0'
            then
              report "VIC: Received data request for $" & to_hstring(viciv_addr&"000")
                & ", bank = $" & to_hstring(viciv_bank&"0000000000000000000");
              -- VIC-IV is asking for 8 bytes of data
              viciv_last_request_toggle <= viciv_request_toggle;

              viciv_request_count <= viciv_request_count + 1;

              -- Prepare command vector
              hr_command(47) <= '1'; -- READ
              hr_command(46) <= '0'; -- Memory, not register space
              hr_command(45) <= '1'; -- linear
              hr_command(44 downto 32) <= (others => '0'); -- unused upper address bits
              hr_command(15 downto 3) <= (others => '0'); -- reserved bits
              hr_command(34 downto 31) <= viciv_bank(3 downto 0);
              hr_command(30 downto 16) <= viciv_addr(18 downto 4);
              hr_command(2) <= viciv_addr(3);
              hr_command(1 downto 0) <= "00";

              -- We want
              hyperram0_select <= not viciv_bank(4);
              hyperram1_select <= viciv_bank(4);

              hyperram_access_address(26 downto 19) <= viciv_bank;
              hyperram_access_address(18 downto 3) <= viciv_addr(18 downto 3);
              hyperram_access_address(2 downto 0) <= (others => '0');

              busy_internal <= '1';
              ram_reading_held <= '1';
              is_expected_to_respond <= false;
              is_vic_fetch <= true;
              countdown <= 6;
              countdown_is_zero <= '0';
              config_reg_write <= '0';
              hr_reset <= '1'; -- active low reset
              vic_buffer_sent <= '0';
              -- One setup cycle, as CPU reads have: going straight to the
              -- command state put every command byte on a HyperRAM clock edge
              state <= PortReadSetup;
            elsif prefetch_when_idle then
              prefetch_when_idle <= false;
              report "DISPATCHER: Dispatching chained pre-fetch";
              tempaddr(26 downto 5) := current_cache_line_address(26 downto 5) + 1;
              tempaddr(4 downto 0) := "00000";
              hyperram_access_address <= tempaddr;

              -- We are reading on a 32 byte boundary, so command formation is
              -- simpler.
              hr_command(47) <= '1'; -- Read
              hr_command(45) <= '1'; -- Linear read, not wrapped
              hr_command(34 downto 17) <= tempaddr(22 downto 5);
              hr_command(16 downto 0) <= (others => '0');

              hyperram0_select <= not tempaddr(23);
              hyperram1_select <= tempaddr(23);
              hr_reset <= '1';
              pause_phase <= '0';
              is_prefetch <= true;
              ram_reading_held <= '1';
              is_expected_to_respond <= false;

              if fast_cmd_mode='1' then
                state <= HyperRAMOutputCommand;
                hr_clk_fast <= '1';
                hr_clk_phaseshift <= write_phase_shift;
              else
                state <= HyperRAMOutputCommandSlow;
                hr_clk_fast <= '0';
                hr_clk_phaseshift <= write_phase_shift;
              end if;

              countdown <= 6;
              config_reg_write <= '0';
              countdown_is_zero <= '0';

              report "DISPATCH: Dispatching pre-fetch of $" & to_hstring(tempaddr)
                & " in response to giving last row to current_cache_line";
              -- Mark a cache line to receive the pre-fetched data, so that we don't
              -- have to wait for it all to turn up, before being able to return
              -- the first 8 bytes
              mark_cache_for_prefetch162 <= not mark_cache_for_prefetch162;

            elsif (request_toggle /= last_request_toggle)
              -- Only commence reads AFTER all pending writes have flushed,
              -- to ensure cache coherence (there are corner-cases here with
              -- chained writes, block reads and other bits and pieces).
              and write_collect0_dispatchable='0'
              and write_collect1_dispatchable='0' then
              report "WAITING for job";
              ram_reading_held <= ram_reading;

              if ram_reading = '1' then
                report "Waiting to start read";
                request_accepted <= request_toggle;
                last_request_toggle <= request_toggle;
                state <= ReadSetup;
                report "Accepting job";
                busy_internal <= '1';
              else
                report "Waiting to start write";
                report "Setting state to WriteSetup. random_bits=" & to_hstring(random_bits);
                request_accepted <= request_toggle;
                last_request_toggle <= request_toggle;
                state <= WriteSetup;
                report "Accepting job";
                busy_internal <= '1';

              end if;
            elsif (write_collect0_dispatchable = '1')
              -- But only if the other collector doesn't have an address that
              -- would chain to us.
--              and ((write_collect0_address /= (write_collect1_address + 1)) or write_collect1_dispatchable='0')
              -- XXX The following slows access down noticeably through
              -- inefficient scheduling.
              and ((write_collect0_address_matches_write_collect1_address_plus_1='1') or write_collect1_dispatchable='0')
            then
              -- Do background write.
              busy_internal <= '0';
              request_accepted <= request_toggle;
              is_prefetch <= false;
              is_expected_to_respond <= false;

              report "DISPATCH: Writing out collect0 @ $" & to_hstring(write_collect0_address&"000");

              -- Mark the write buffer as being processed.
              write_collect0_flushed <= '0';
              -- And that it is not (yet) too late to add extra bytes to the write.
              write_collect0_toolate <= '0';

              background_write_next_address <= write_collect0_address;
              background_write_next_address_matches_collect0 <= '1';
              background_write <= '1';
              background_write_fetch <= '1';
              background_write_source <= '0'; -- collect 0
              report "background_write_source = 0";

              config_reg_write <= write_collect0_address(25);

              -- Prepare command vector
              hr_command(47) <= '0'; -- WRITE
              hr_command(46) <= write_collect0_address(25); -- Memory, not register space
              hr_command(45) <= '1'; -- linear
              hr_command(44 downto 35) <= (others => '0'); -- unused upper address bits
              hr_command(15 downto 3) <= (others => '0'); -- reserved bits
              hr_command(34 downto 16) <= write_collect0_address(22 downto 4);
              hr_command(2) <= write_collect0_address(3);
              hr_command(1 downto 0) <= "00";
              hr_reset <= '1'; -- active low reset

              hyperram0_select <= not write_collect0_address(23);
              hyperram1_select <= write_collect0_address(23);

              hyperram_access_address(26 downto 3) <= write_collect0_address;
              hyperram_access_address(2 downto 0) <= (others => '0');

              ram_reading_held <= '0';

              -- This is the delay before we assert CS

              -- We have to use this intermediate stage to get the clock
              -- phase right.
              state <= StartBackgroundWrite;

              if write_collect0_address(25)='1' then
                -- 48 bits of CA followed by 16 bit register value
                -- (we shift the buffered config register values out automatically)
                countdown <= 6 + 1;
              else
                countdown <= 6;
              end if;
              countdown_is_zero <= '0';

            elsif write_collect1_dispatchable = '1' then
              busy_internal <= '0';
              request_accepted <= request_toggle;

              is_prefetch <= false;
              is_expected_to_respond <= false;

              report "DISPATCH: Writing out collect1 @ $" & to_hstring(write_collect1_address&"000");

              -- Mark the write buffer as being processed.
              write_collect1_flushed <= '0';
              -- And that it is not (yet) too late to add extra bytes to the write.
              write_collect1_toolate <= '0';
              show_collect1 := true;

              config_reg_write <= write_collect1_address(25);

              background_write_next_address <= write_collect1_address;
              background_write_next_address_matches_collect1 <= '1';
              background_write <= '1';
              background_write_fetch <= '1';
              background_write_source <= '1'; -- collect 1
              report "background_write_source = 1";

              -- Prepare command vector
              hr_command(47) <= '0'; -- WRITE
              hr_command(46) <= write_collect1_address(25); -- Memory, not register space
              hr_command(45) <= '1'; -- linear
              hr_command(44 downto 35) <= (others => '0'); -- unused upper address bits
              hr_command(15 downto 3) <= (others => '0'); -- reserved bits
              hr_command(34 downto 16) <= write_collect1_address(22 downto 4);
              hr_command(2) <= write_collect1_address(3);
              hr_command(1 downto 0) <= "00";

              ram_reading_held <= '0';

              hyperram0_select <= not write_collect1_address(23);
              hyperram1_select <= write_collect1_address(23);

              hyperram_access_address(26 downto 3) <= write_collect1_address;
              hyperram_access_address(2 downto 0) <= (others => '0');

              hr_reset <= '1'; -- active low reset

              state <= StartBackgroundWrite;

              if write_collect1_address(25)='1' then
                -- 48 bits of CA followed by 16 bit register value
                -- (we shift the buffered config register values out automatically)
                countdown <= 6 + 1;
              else
                countdown <= 6;
              end if;
              countdown_is_zero <= '0';

              report "clk_queue <= '00'";

            else
              report "Clearing busy_internal";
              busy_internal <= '0';
              request_accepted <= request_toggle;
            end IF;
            -- Release CS line between transactions
            report "Releasing hyperram CS lines";
            hr_cs0 <= '1';
            hr_cs1 <= '1';
          end if;

        when StartBackgroundWrite =>
          report "in StartBackgroundWrite to synchronise with clock";
          pause_phase <= '0';
          -- Fast writes always get a fast command: switching the HyperRAM
          -- clock rate in mid-transaction costs a variable number of edges.
          -- Otherwise $BFFFFF2 bit 0 picks the command rate, for CPU and
          -- LUMP writes alike.
          if (fast_cmd_mode='1' or fast_write_mode='1')
            and fast_cmd_for_write_enabled then
            state <= HyperRAMOutputCommand;
            hr_clk_phaseshift <= write_phase_shift;
            hr_clk_fast <= '1';
          else
            state <= HyperRAMOutputCommandSlow;
            hr_clk_phaseshift <= write_phase_shift;
            hr_clk_fast <= '0';
          end if;

        when PortReadSetup =>
          -- LUMP and VIC-IV reads: exactly ReadSetup's timing and command
          -- rate choice (hr_command was loaded in Idle).
          pause_phase <= '0';
          if fast_cmd_mode='1' then
            state <= HyperRAMOutputCommand;
            hr_clk_fast <= '1';
          else
            state <= HyperRAMOutputCommandSlow;
            hr_clk_fast <= '0';
          end if;
          hr_clk_phaseshift <= write_phase_shift;
          countdown <= 6;
          countdown_is_zero <= '0';

        when ReadSetup =>
          report "Setting up to read $" & to_hstring(ram_address) & " ( address = $" & to_hstring(address) & ")";

          -- Prepare command vector
          hr_command(47) <= '1'; -- READ
          -- Map actual RAM to bottom 32MB of 64MB space (repeated 4x)
          -- and registers to upper 32MB
--            hr_command(46) <= '1'; -- Memory address space (1) / Register
          hr_command(46) <= ram_address(25); -- Memory address space (1) / Register
                                             -- address space select (0) ?
          hr_command(45) <= '1'; -- Linear access (not wrapped)
          hr_command(44 downto 37) <= (others => '0'); -- unused upper address bits
          hr_command(34 downto 16) <= ram_address(22 downto 4);
          hr_command(15 downto 3) <= (others => '0'); -- reserved bits
          if ram_address(25) = '0' then
            -- Always read on 8 byte boundaries, and read a full cache line
            hr_command(2) <= ram_address(3);
            hr_command(1 downto 0) <= "00";
          else
            -- Except that register reads are weird: They read the same 2 bytes
            -- over and over again, so we have to make it set bit 0 of the CA
            -- for the "odd" registers"
            hr_command(2 downto 1) <= "00";
            hr_command(0) <= ram_address(3);
          end if;

          hyperram0_select <= not ram_address(23);
          hyperram1_select <= ram_address(23);

          hyperram_access_address <= ram_address;

          hr_reset <= '1'; -- active low reset
          pause_phase <= '0';

          if fast_cmd_mode='1' then
            state <= HyperRAMOutputCommand;
            hr_clk_fast <= '1';
            hr_clk_phaseshift <= write_phase_shift;
          else
            state <= HyperRAMOutputCommandSlow;
            hr_clk_fast <= '0';
            hr_clk_phaseshift <= write_phase_shift;
          end if;

          countdown <= 6;
          config_reg_write <= '0';
          countdown_is_zero <= '0';

        when WriteSetup =>

          report "Preparing hr_command etc for write to $" & to_hstring(ram_address);

          if not cache_enabled then
            background_write_count <= 2;
            background_write <= '0';
          end if;

          config_reg_write <= ram_address(25);

          -- Prepare command vector
          -- As HyperRAM addresses on 16bit boundaries, we shift the address
          -- down one bit.
          hr_command(47) <= '0'; -- WRITE
          hr_command(46) <= ram_address(25); -- Memory, not register space
          hr_command(45) <= '1'; -- linear

          hr_command(44 downto 35) <= (others => '0'); -- unused upper address bits
          hr_command(15 downto 3) <= (others => '0'); -- reserved bits

          hr_command(34 downto 16) <= ram_address(22 downto 4);
          hr_command(2 downto 0) <= ram_address(3 downto 1);

          hr_reset <= '1'; -- active low reset

          hyperram0_select <= not ram_address(23);
          hyperram1_select <= ram_address(23);

          hyperram_access_address <= ram_address;

          pause_phase <= '0';

          if start_delay_expired = '1' then
            if fast_cmd_mode='1' and fast_cmd_for_write_enabled then
              state <= HyperRAMOutputCommand;
              hr_clk_fast <= '1';
              hr_clk_phaseshift <= write_phase_shift;
            else
              state <= HyperRAMOutputCommandSlow;
              hr_clk_fast <= '0';
              hr_clk_phaseshift <= write_phase_shift;
            end if;
          end if;
          if ram_address(25)='1' then
            -- 48 bits of CA followed by 16 bit register value
            -- (we shift the buffered config register values out automatically)
            countdown <= 6 + 1;
          else
            countdown <= 6;
          end if;
          countdown_is_zero <= '0';

        when HyperRAMOutputCommandSlow =>
          report "Writing command, hyperram_access_address=$" & to_hstring(hyperram_access_address);
          report "hr_command = $" & to_hstring(hr_command);
          -- Call HyperRAM to attention
          hr_cs0 <= not hyperram0_select;
          hr_cs1 <= not (hyperram1_select or first_transaction);

          hr_rwds <= 'Z';
          hr2_rwds <= 'Z';

          -- Prepare for reading block data
          is_block_read <= false;
          if (hyperram_access_address(4 downto 3) = "00") and block_read_enable='1' and (ram_reading_held='1')
            and (is_vic_fetch = false) and is_lump='0' then
            block_valid <= '0';
            block_address <= hyperram_access_address(26 downto 5);
            is_block_read <= true;
          end if;

          pause_phase <= not pause_phase;

          if pause_phase='1' then
            hr_clk_phaseshift <= write_phase_shift;

            if countdown_timeout='1' then
              -- Finished shifting out
              if ram_reading_held = '1' then
                -- Reading: We can just wait until hr_rwds has gone low, and then
                -- goes high again to indicate the first data byte
                countdown <= 63;
                countdown_is_zero <= '0';
                hr_rwds_high_seen <= '0';
                countdown_timeout <= '0';
                if is_lump='1' then
                  state <= LumpReadWait;
                  if fast_read_mode='1' then
                    lump_slow <= '0';
                    hr_clk_fast <= '1';
                  else
                    lump_slow <= '1';
                    pause_phase <= '1';
                    hr_clk_fast <= '0';
                  end if;
                elsif fast_read_mode='1' then
                  hr_clk_fast <= '1';
                  state <= HyperRAMReadWait;
                else
                  pause_phase <= '1';
                  hr_clk_fast <= '0';
                  state <= HyperRAMReadWaitSlow;
                end if;
              elsif config_reg_write='1' and ram_reading_held='0' then
                -- Config register write.
                -- These are a bit weird, as they have no latency, and all 16
                -- bits have to get written at once.  So we will have 2 buffer
                -- registers that get setup, and then ANY write to the register
                -- area will write those values, which we have done by shifting
                -- those through and sending 48+16 bits instead of the usual
                -- 48.
                if background_write='1' then
                  if background_write_source = '0' then
                    write_collect0_flushed <= '1';
                    show_collect0 := true;
                  else
                    write_collect1_flushed <= '1';
                    show_collect1 := true;
                  end if;
                end if;

                report "Finished writing config register";
                state <= HyperRAMFinishWriting;
              else
                -- Writing to memory, so count down the correct number of cycles;
                -- Initial latency is reduced by 2 cycles for the last bytes
                -- of the access command, and by 1 more to cover state
                -- machine latency
                if hyperram1_select='0' then
                  countdown <= to_integer(write_latency);
                else
                  countdown <= to_integer(write_latency2);
                end if;
                -- XXX Doesn't work if write_latency(2) is $00
                countdown_is_zero <= '0';


                -- We are not just about ready to start writing, so mark the
                -- write buffer as too late to be added to, because we will
                -- snap-shot it in a moment.
                if background_write = '1' then
                  report "WRITE: Asserting toolate signal for collect" & std_logic'image(background_write_source);
                  background_write_count <= 4 + 2;
                  -- We know we can do upto 128 bytes at least per write,
                  -- before a refresh is required. So allow 16x8 byte writes to
                  -- be chained.
                  write_continues <= write_continues_max;
                  if background_write_source = '0' then
                    write_collect0_toolate <= '1';
                    write_collect0_flushed <= '0';
                    show_collect0 := true;
                  else
                    write_collect1_toolate <= '1';
                    write_collect1_flushed <= '0';
                    show_collect1 := true;
                  end if;
                end if;
                countdown_timeout <= '0';
                if is_lump='1' then
                  le_wdata_req <= '1'; lump_dbg_wq <= lump_dbg_wq + 1;
                  state <= LumpDoWrite;
                  if fast_write_mode='1' then
                    lump_slow <= '0';
                    hr_clk_fast <= '1';
                  else
                    lump_slow <= '1';
                    hr_clk_fast <= '0';
                  end if;
                elsif fast_write_mode='1' then
                  hr_clk_fast <= '1';
                  state <= HyperRAMDoWrite;
                else
                  hr_clk_fast <= '0';
                  state <= HyperRAMDoWriteSlow;
                end if;
              end if;
            end if;

          else

            -- Toggle data while clock steady
            report "Presenting hr_command byte on hr_d = $" & to_hstring(hr_command(47 downto 40))
              & ", clock = " & std_logic'image(hr_clk)
              & ", countdown = " & integer'image(countdown);

            hr_d <= hr_command(47 downto 40);
            hr2_d <= hr_command(47 downto 40);
            hr_command(47 downto 8) <= hr_command(39 downto 0);

            -- Also shift out config register values, if required
            if config_reg_write='1' and ram_reading_held='0' then
              report "shifting in conf value $" & to_hstring(conf_buf0);
              hr_command(7 downto 0) <= conf_buf0;
              conf_buf0 <= conf_buf1;
              conf_buf1 <= conf_buf0;
            else
              hr_command(7 downto 0) <= x"00";
            end if;

            report "Writing command byte $" & to_hstring(hr_command(47 downto 40));

            if countdown = 3 and config_reg_write='1' then
              if background_write='1' then
                if background_write_source = '0' then
                  write_collect0_toolate <= '1';
                else
                  write_collect1_toolate <= '1';
                end if;
              end if;
            end if;

            if countdown = 3 and (config_reg_write='0' or ram_reading_held='1') then
              extra_latency <= hr_rwds;
              if (hr_rwds='1' and hyperram0_select='1')
                or (hr2_rwds='1' and hyperram1_select='1')
              then
                report "Applying extra latency";
              end if;
            end if;
            if countdown = 1 then
              countdown_is_zero <= '1';
            end if;
            if countdown /= 0 then
              countdown <= countdown - 1;
            else
              report "asserting countdown_timeout";
              countdown_timeout <= '1';
            end if;
          end if;
          byte_phase <= to_unsigned(0,6);
          write_byte_phase <= '0';
        when HyperRAMOutputCommand =>
          report "Writing command";
          -- Call HyperRAM to attention
          hr_cs0 <= not hyperram0_select;
          hr_cs1 <= not (hyperram1_select or first_transaction);

          hr_rwds <= 'Z';
          hr2_rwds <= 'Z';

          hr_clk_phaseshift <= write_byte_phase;

          -- Prepare for reading block data
          is_block_read <= false;
          if (hyperram_access_address(4 downto 3) = "00") and block_read_enable='1' and (ram_reading_held='1')
            and (is_vic_fetch = false) and is_lump='0' then
            block_valid <= '0';
            block_address <= hyperram_access_address(26 downto 5);
            is_block_read <= true;
          end if;

          pause_phase <= not pause_phase;

          hr_clk_phaseshift <= write_phase_shift;

          if countdown_timeout='1' then
            -- Finished shifting out
            if ram_reading_held = '1' then
              -- Reading: We can just wait until hr_rwds has gone low, and then
              -- goes high again to indicate the first data byte
              countdown <= 63;
              countdown_is_zero <= '0';
              hr_rwds_high_seen <= '0';
              countdown_timeout <= '0';
              if is_lump='1' then
                state <= LumpReadWait;
                if fast_read_mode='1' then
                  lump_slow <= '0';
                  hr_clk_fast <= '1';
                else
                  lump_slow <= '1';
                  pause_phase <= '1';
                  hr_clk_fast <= '0';
                end if;
              elsif fast_read_mode='1' then
                hr_clk_fast <= '1';
                state <= HyperRAMReadWait;
              else
                pause_phase <= '1';
                hr_clk_fast <= '0';
                state <= HyperRAMReadWaitSlow;
              end if;
            elsif config_reg_write='1' and ram_reading_held='0' then
              -- Config register write.
              -- These are a bit weird, as they have no latency, and all 16
              -- bits have to get written at once.  So we will have 2 buffer
              -- registers that get setup, and then ANY write to the register
              -- area will write those values, which we have done by shifting
              -- those through and sending 48+16 bits instead of the usual
              -- 48.
              if background_write='1' then
                if background_write_source = '0' then
                  write_collect0_flushed <= '1';
                  show_collect0 := true;
                else
                  write_collect1_flushed <= '1';
                  show_collect1 := true;
                end if;
              end if;

              report "Finished writing config register";
              state <= HyperRAMFinishWriting;
            else
              -- Writing to memory, so count down the correct number of cycles;
              -- Initial latency is reduced by 2 cycles for the last bytes
              -- of the access command, and by 1 more to cover state
              -- machine latency
              -- Fast command: this state hands off one cycle later than the slow
              -- one (an extra byte time on the bus), so one less latency
              if hyperram1_select='0' then
                countdown <= to_integer(write_latency) - 1;
              else
                countdown <= to_integer(write_latency2) - 1;
              end if;
              -- XXX Doesn't work if write_latency(2) is $00
              countdown_is_zero <= '0';


              -- We are not just about ready to start writing, so mark the
              -- write buffer as too late to be added to, because we will
              -- snap-shot it in a moment.
              if background_write = '1' then
                report "WRITE: Asserting toolate signal for collect" & std_logic'image(background_write_source);
                background_write_count <= 4 + 2;
                -- We know we can do upto 128 bytes at least per write,
                -- before a refresh is required. So allow 16x8 byte writes to
                -- be chained.
                write_continues <= write_continues_max;
                if background_write_source = '0' then
                  write_collect0_toolate <= '1';
                  write_collect0_flushed <= '0';
                  show_collect0 := true;
                else
                  write_collect1_toolate <= '1';
                  write_collect1_flushed <= '0';
                  show_collect1 := true;
                end if;
              end if;
              countdown_timeout <= '0';
              if is_lump='1' then
                -- Request the first write word now: it is sampled two
                -- edges later, which is no earlier than the first data
                -- byte (requires write latency >= 1, as for normal writes)
                le_wdata_req <= '1'; lump_dbg_wq <= lump_dbg_wq + 1;
                state <= LumpDoWrite;
                if fast_write_mode='1' then
                  lump_slow <= '0';
                  hr_clk_fast <= '1';
                else
                  lump_slow <= '1';
                  hr_clk_fast <= '0';
                end if;
              elsif fast_write_mode='1' then
                hr_clk_fast <= '1';
                state <= HyperRAMDoWrite;
              else
                hr_clk_fast <= '0';
                state <= HyperRAMDoWriteSlow;
              end if;
            end if;
          end if;

          -- In fast mode, we can't toggle data while the clock is steady
          -- as we toggle it every cycle
          report "Presenting hr_command byte on hr_d = $" & to_hstring(hr_command(47 downto 40))
            & ", clock = " & std_logic'image(hr_clk)
            & ", countdown = " & integer'image(countdown);

          hr_d <= hr_command(47 downto 40);
          hr2_d <= hr_command(47 downto 40);
          hr_command(47 downto 8) <= hr_command(39 downto 0);

          -- Also shift out config register values, if required
          if config_reg_write='1' and ram_reading_held='0' then
            report "shifting in conf value $" & to_hstring(conf_buf0);
            hr_command(7 downto 0) <= conf_buf0;
            conf_buf0 <= conf_buf1;
            conf_buf1 <= conf_buf0;
          else
            hr_command(7 downto 0) <= x"00";
          end if;

          report "Writing command byte $" & to_hstring(hr_command(47 downto 40));

          if countdown = 3 and config_reg_write='1' then
            if background_write='1' then
              if background_write_source = '0' then
                write_collect0_toolate <= '1';
              else
                write_collect1_toolate <= '1';
              end if;
            end if;
          end if;

          if countdown = 3 and (config_reg_write='0' or ram_reading_held='1') then
            extra_latency <= hr_rwds;
            if (hr_rwds='1' and hyperram0_select='1')
              or (hr2_rwds='1' and hyperram1_select='1')
            then
              report "Applying extra latency";
            end if;
          end if;
          -- Not on the hand-off cycle (countdown_timeout already set): there
          -- the hand-off above clears countdown_timeout and loads the
          -- latency countdown for the next state, and re-asserting it here
          -- (the later assignment wins) made every fast-command write
          -- finish at once, with nothing written.
          if countdown_timeout = '0' then
            if countdown = 1 then
              countdown_is_zero <= '1';
            end if;
            if countdown /= 0 then
              countdown <= countdown - 1;
            else
              report "asserting countdown_timeout";
              countdown_timeout <= '1';
            end if;
          end if;
          byte_phase <= to_unsigned(0,6);
          write_byte_phase <= '0';


        when HyperRAMDoWrite =>

          -- Update cache
          if cache_row0_address_matches_ram_address = '1' then
            if ram_wdata_enlo_drive='1' then
              cache_row0_valids(to_integer(ram_address_drive(2 downto 0))) <= '1';
              cache_row0_data(to_integer(ram_address_drive(2 downto 0))) <= ram_wdata_drive;
            end if;
            if ram_wdata_enhi_drive='1' then
              cache_row0_valids(to_integer(ram_address_drive(2 downto 0))+1) <= '1';
              cache_row0_data(to_integer(ram_address_drive(2 downto 0))+1) <= ram_wdata_hi_drive;
            end if;
            show_cache0 := true;
          elsif cache_row1_address_matches_ram_address='1' then
            if ram_wdata_enlo_drive='1' then
              cache_row1_valids(to_integer(ram_address_drive(2 downto 0))) <= '1';
              cache_row1_data(to_integer(ram_address_drive(2 downto 0))) <= ram_wdata_drive;
            end if;
            if ram_wdata_enhi_drive='1' then
              cache_row1_valids(to_integer(ram_address_drive(2 downto 0))+1) <= '1';
              cache_row1_data(to_integer(ram_address_drive(2 downto 0))+1) <= ram_wdata_hi_drive;
            end if;
            show_cache1 := true;
          else
            if random_bits(1)='0' then
              report "Zeroing cache_row0_valids";
              cache_row0_valids <= (others => '0');
              cache_row0_address <= ram_address_drive(26 downto 3);
              cache_row0_address_matches_ram_address <= '1';
              if ram_wdata_enlo_drive='1' then
                cache_row0_valids(to_integer(ram_address_drive(2 downto 0))) <= '1';
                cache_row0_data(to_integer(ram_address_drive(2 downto 0))) <= ram_wdata_drive;
              end if;
              if ram_wdata_enhi_drive='1' then
                cache_row0_valids(to_integer(ram_address_drive(2 downto 0))+1) <= '1';
                cache_row0_data(to_integer(ram_address_drive(2 downto 0))+1) <= ram_wdata_hi_drive;
              end if;
              show_cache0 := true;
            else
              report "Zeroing cache_row1_valids";
              cache_row1_valids <= (others => '0');
              cache_row1_address <= ram_address_drive(26 downto 3);
              cache_row1_address_matches_ram_address <= '1';
              if ram_wdata_enlo_drive='1' then
                cache_row1_valids(to_integer(ram_address_drive(2 downto 0))) <= '1';
                cache_row1_data(to_integer(ram_address_drive(2 downto 0))) <= ram_wdata_drive;
              end if;
              if ram_wdata_enhi_drive='1' then
                cache_row1_valids(to_integer(ram_address_drive(2 downto 0))+1) <= '1';
                cache_row1_data(to_integer(ram_address_drive(2 downto 0))+1) <= ram_wdata_hi_drive;
              end if;
              show_cache1 := true;
            end if;
          end if;

          -- Fetch takes 2 cycles, so schedule one cycle before last read
          -- and shift, so that it happens after that last shift, but
          -- before it is needed again.
          -- Here a byte goes out on every cycle, so (unlike the slow state,
          -- which has an idle cycle between bytes) the fetch must happen in
          -- the cycle of the line's LAST byte, so the next cycle can drive
          -- the new line's byte 0: request it at count 1, one byte earlier.
          -- (Requesting at count 0 made the fetch land in a byte slot: that
          -- slot went out masked, and the byte shift below overwrote the
          -- fetched line, so chained writes lost their data.)
          if background_write_count = 1 then
            if write_continues /= 0 and background_chained_write='1' then
              if background_write_fetch = '0' then
                report "WRITECONTINUE: Continuing write: Requesting fetch.";
                background_write_fetch <= '1';
              end if;
            end if;
          elsif background_write_count = 0 and background_write_fetch = '0' then
            report "WRITECONTINUE: No continuation. Terminating write.";
            countdown_timeout <= '1';
          end if;

          report "WRITE: LatencyWait state, bg_wr=" & std_logic'image(background_write)
            & ", count=" & integer'image(background_write_count)
            & ", background_write_fetch = " & std_logic'image(background_write_fetch)
            & ", background_write_valids = " & to_string(background_write_valids)
            & ", write_blocked=" & std_logic'image(write_blocked);

          -- Now snap-shot the write buffer data, and mark the slot as flushed
          if background_write = '1' and
            ( (background_write_next_address_matches_collect0 = '1')
              or (background_write_next_address_matches_collect1 = '1') )
          then
            if background_chained_write = '0' then
              report "WRITE: background_chained_write <= 1";
            end if;
            background_chained_write <= '1';
          else
            if background_chained_write = '1' then
              report "WRITE: background_chained_write <= 0";
            end if;
            background_chained_write <= '0';

            if hr_clock_phase165="11" and (background_write_valids = "00000000")
              and (read_request_o='1' or write_request_o='1' or write_blocked='1') then
              report "LatencyWait: Aborting tail of background write due to incoming job/write_blocked";
              state <= HyperRAMFinishWriting;
            end if;


          end if;

          if background_write_fetch = '1' then
            report "WRITE: Doing fetch of background write data";
            background_write_fetch <= '0';
            background_write_next_address <= background_write_next_address + 1;
            write_continues <= write_continues - 1;
            background_write_count <= 7;
            if background_write_next_address_matches_collect0 = '1' and background_write_source = '0' then
              show_collect0 := true;
              report "WRITE: background_write_data copied from write_collect0 (@ $"
                & to_hstring(write_collect0_address&"000")
                & "). Valids = " & to_string(write_collect0_valids)
                & ", next addr was $" & to_hstring(background_write_next_address&"000");

              background_write_next_address <= write_collect0_address + 1;
              background_write_next_address_matches_collect0 <= '0';
              background_write_next_address_matches_collect1 <= collect1_matches_collect0_plus_1;

              background_write_data <= write_collect0_data;
              background_write_valids <= write_collect0_valids;
              write_collect0_flushed <= '1';

            elsif background_write_next_address_matches_collect1 = '1' and background_write_source = '1' then
              show_collect1 := true;
              report "WRITE: background_write_data copied from write_collect1. Valids = " & to_string(write_collect1_valids)
                & ", next addr was $" & to_hstring(background_write_next_address&"000");
              background_write_next_address <= write_collect1_address + 1;
              background_write_next_address_matches_collect0 <= collect0_matches_collect1_plus_1;
              background_write_next_address_matches_collect1 <= '0';

              background_write_data <= write_collect1_data;
              background_write_valids <= write_collect1_valids;
              write_collect1_flushed <= '1';
            else
              report "WRITE: Write is not chained.";
              background_chained_write <= '0';
            end if;
          end if;

          hr_clk_phaseshift <= write_phase_shift;
          if countdown_timeout = '1' then
            report "Advancing to HyperRAMFinishWriting";
            state <= HyperRAMFinishWriting;
          end if;

          report "latency countdown = " & integer'image(countdown);

          -- Begin write mask pre-amble
          if ram_reading_held = '0' and countdown = 2 then
            hr_rwds <= '0';
            hr2_rwds <= '0';
            hr_d <= x"BE"; -- "before" data byte
            hr2_d <= x"BE"; -- "before" data byte
          end if;

          if countdown /= 0 then
            countdown <= countdown - 1;
          end if;
          if countdown = 1 then
            countdown_is_zero <= '1';
          end if;
          if countdown_is_zero = '1' then
            if extra_latency='1' then
              report "Waiting 6 more cycles for extra latency";
              -- If we were asked to wait for extra latency,
              -- then wait another 6 cycles.
              extra_latency <= '0';
              if hyperram0_select='1' then
                countdown <= to_integer(extra_write_latency);
              else
                countdown <= to_integer(extra_write_latency2);
              end if;
              -- XXX Assumes extra_write_latency is not zero
              countdown_is_zero <= '0';
            else
              -- Latency countdown for writing is over, we can now
              -- begin writing bytes.

              -- HyperRAM works on 16-bit fundamental transfers.
              -- This means we need to have two half-cycles, and pick which
              -- one we want to write during.
              -- If RWDS is asserted, then the write is masked, i.e., won't
              -- occur.
              -- In this first

              report "Presenting hr_d with ram_wdata or background data";
              if background_write='1' then
                report "WRITE: Writing background byte $" & to_hstring(background_write_data(0))
                  & ", valids= " & to_string(background_write_valids)
                  & ", background words left = " & integer'image(background_write_count);
                hr_d <= background_write_data(0);
                hr2_d <= background_write_data(0);

                -- Shift, unless the next line is being fetched in this same
                -- cycle (the line's last byte): then the fetch's load stands
                if background_write_fetch = '0' then
                  background_write_data(0) <= background_write_data(1);
                  background_write_data(1) <= background_write_data(2);
                  background_write_data(2) <= background_write_data(3);
                  background_write_data(3) <= background_write_data(4);
                  background_write_data(4) <= background_write_data(5);
                  background_write_data(5) <= background_write_data(6);
                  background_write_data(6) <= background_write_data(7);
                  background_write_data(7) <= x"00";
                end if;

                hr_rwds <= not background_write_valids(0);
                hr2_rwds <= not background_write_valids(0);
                if background_write_fetch = '0' then
                  background_write_valids(0 to 6) <= background_write_valids(1 to 7);
                  background_write_valids(7) <= '0';
                end if;
              else
                -- XXX Doesn't handle 16-bit writes properly. But that's
                -- okay, as they are only supported with the cache and
                -- write-collecting, anyway.
                hr_d <= ram_wdata;
                hr2_d <= ram_wdata;
                hr_rwds <= hyperram_access_address(0) xor write_byte_phase;
                hr2_rwds <= hyperram_access_address(0) xor write_byte_phase;
              end if;

              -- Finish resetting write collectors when chaining
              if write_collect0_dispatchable='0' and write_collect0_flushed='1' and write_collect0_toolate='1' then
                report "WRITECONTINUE: Resetting collect0";
                write_collect0_flushed <= '0';
                write_collect0_toolate <= '0';
                show_collect0 := true;
              end if;
              if write_collect1_dispatchable='0' and write_collect1_flushed='1' and write_collect1_toolate='1' then
                report "WRITECONTINUE: Resetting collect1";
                write_collect1_flushed <= '0';
                write_collect1_toolate <= '0';
                show_collect1 := true;
              end if;

              -- Write byte
              write_byte_phase <= '1';
              if background_write='0' then
                if write_byte_phase = '0' and hyperram_access_address(0)='1' then
                  hr_d <= x"ee"; -- even "masked" data byte
                  hr2_d <= x"ee"; -- even "masked" data byte
                elsif write_byte_phase = '1' and hyperram_access_address(0)='0' then
                  hr_d <= x"0d"; -- odd "masked" data byte
                  hr2_d <= x"0d"; -- odd "masked" data byte
                end if;
                if background_write_count /= 0 then
                  background_write_count <= background_write_count - 1;
                else
                  state <= HyperRAMFinishWriting;
                end if;
              else
                report "WRITE: Decrementing background_write_count from " & integer'image(background_write_count)
                  & ", write_continues = " & integer'image(write_continues);
                if background_write_count /= 0 then
                  background_write_count <= background_write_count - 1;
                  if background_write_count = 3 and write_continues /= 0 then
                    report "WRITECONTINUE: Checking for chained writes (" & integer'image(write_continues) & " more continues allowed)";
                    report "WRITECONTINUE: Am looking for $" & to_hstring(background_write_next_address&"000") &
                      ", options are 0:$" & to_hstring(write_collect0_address&"000") &
                      " and 1:$" & to_hstring(write_collect1_address&"000");
                    show_collect0 := true;
                    show_collect1 := true;
                    -- Get ready to commit next write block, if one is there
                    if write_continues /= 0 and write_collect0_toolate='0' and write_collect0_flushed = '0'
                      and background_write_next_address_matches_collect0='1' then
                      report "WRITECONTINUE: Marking collect0 @ $" & to_hstring(write_collect0_address&"000") & " for chained write.";
                      write_collect0_toolate <= '1';
                      background_write_source <= '0';
                      report "background_write_source = 0";
                      show_collect0 := true;
                    elsif write_continues /= 0 and write_collect1_toolate='0' and write_collect1_flushed = '0'
                      and background_write_next_address_matches_collect1='1' then
                      report "WRITECONTINUE: Marking collect1 @ $" & to_hstring(write_collect1_address&"000") & " for chained write.";
                      write_collect1_toolate <= '1';
                      background_write_source <= '1';
                      report "background_write_source = 1";
                      show_collect1 := true;
                    end if;
                  end if;
                end if;

              end if;
            end if;
          end if;
        when HyperRAMDoWriteSlow =>
          pause_phase <= not pause_phase;

          -- Update cache
          if cache_row0_address_matches_ram_address = '1' then
            if ram_wdata_enlo_drive='1' then
              cache_row0_valids(to_integer(ram_address_drive(2 downto 0))) <= '1';
              cache_row0_data(to_integer(ram_address_drive(2 downto 0))) <= ram_wdata_drive;
            end if;
            if ram_wdata_enhi_drive='1' then
              cache_row0_valids(to_integer(ram_address_drive(2 downto 0))+1) <= '1';
              cache_row0_data(to_integer(ram_address_drive(2 downto 0))+1) <= ram_wdata_hi_drive;
            end if;
            show_cache0 := true;
          elsif cache_row1_address_matches_ram_address='1' then
            if ram_wdata_enlo_drive='1' then
              cache_row1_valids(to_integer(ram_address_drive(2 downto 0))) <= '1';
              cache_row1_data(to_integer(ram_address_drive(2 downto 0))) <= ram_wdata_drive;
            end if;
            if ram_wdata_enhi_drive='1' then
              cache_row1_valids(to_integer(ram_address_drive(2 downto 0))+1) <= '1';
              cache_row1_data(to_integer(ram_address_drive(2 downto 0))+1) <= ram_wdata_hi_drive;
            end if;
            show_cache1 := true;
          else
            if random_bits(1)='0' then
              report "Zeroing cache_row0_valids";
              cache_row0_valids <= (others => '0');
              cache_row0_address <= ram_address_drive(26 downto 3);
              cache_row0_address_matches_ram_address <= '1';
              if ram_wdata_enlo_drive='1' then
                cache_row0_valids(to_integer(ram_address_drive(2 downto 0))) <= '1';
                cache_row0_data(to_integer(ram_address_drive(2 downto 0))) <= ram_wdata_drive;
              end if;
              if ram_wdata_enhi_drive='1' then
                cache_row0_valids(to_integer(ram_address_drive(2 downto 0))+1) <= '1';
                cache_row0_data(to_integer(ram_address_drive(2 downto 0))+1) <= ram_wdata_hi_drive;
              end if;
              show_cache0 := true;
            else
              report "Zeroing cache_row1_valids";
              cache_row1_valids <= (others => '0');
              cache_row1_address <= ram_address_drive(26 downto 3);
              cache_row1_address_matches_ram_address <= '1';
              if ram_wdata_enlo_drive='1' then
                cache_row1_valids(to_integer(ram_address_drive(2 downto 0))) <= '1';
                cache_row1_data(to_integer(ram_address_drive(2 downto 0))) <= ram_wdata_drive;
              end if;
              if ram_wdata_enhi_drive='1' then
                cache_row1_valids(to_integer(ram_address_drive(2 downto 0))+1) <= '1';
                cache_row1_data(to_integer(ram_address_drive(2 downto 0))+1) <= ram_wdata_hi_drive;
              end if;
              show_cache1 := true;
            end if;
          end if;

          -- Fetch takes 2 cycles, so schedule one cycle before last read
          -- and shift, so that it happens after that last shift, but
          -- before it is needed again.
          if background_write_count = 0 and pause_phase = '0' then
            -- See if we have another write collect that we can
            -- continue with
            -- XXX We suspect that chained writes might be problematic on the
            -- external hyperram for some strange reason, so disable them.
            if write_continues /= 0 and background_chained_write='1' then
              if background_write_fetch = '0' then
                report "WRITECONTINUE: Continuing write: Requesting fetch.";
                background_write_fetch <= '1';
              end if;
            else
              report "WRITECONTINUE: No continuation. Terminating write.";
              report "asserting countdown_timeout";
              countdown_timeout <= '1';
            end if;
          end if;

          report "WRITE: LatencyWait state, bg_wr=" & std_logic'image(background_write)
            & ", count=" & integer'image(background_write_count)
            & ", background_write_fetch = " & std_logic'image(background_write_fetch)
            & ", background_write_valids = " & to_string(background_write_valids)
            & ", write_blocked=" & std_logic'image(write_blocked);

          -- Now snap-shot the write buffer data, and mark the slot as flushed
          if background_write = '1' and
            ( (background_write_next_address_matches_collect0 = '1')
              or (background_write_next_address_matches_collect1 = '1') )
          then
            if background_chained_write = '0' then
              report "WRITE: background_chained_write <= 1";
            end if;
            background_chained_write <= '1';
          else
            if background_chained_write = '1' then
              report "WRITE: background_chained_write <= 0";
            end if;
            background_chained_write <= '0';

            if hr_clock_phase165="11" and (background_write_valids = "00000000")
              and (read_request_o='1' or write_request_o='1' or write_blocked='1') then
              report "LatencyWait: Aborting tail of background write due to incoming job/write_blocked";
              state <= HyperRAMFinishWriting;
            end if;


          end if;

          if background_write_fetch = '1' then
            report "WRITE: Doing fetch of background write data";
            background_write_fetch <= '0';
            background_write_next_address <= background_write_next_address + 1;
            write_continues <= write_continues - 1;
            background_write_count <= 7;
            if background_write_next_address_matches_collect0 = '1' and background_write_source = '0' then
              show_collect0 := true;
              report "WRITE: background_write_data copied from write_collect0 (@ $"
                & to_hstring(write_collect0_address&"000")
                & "). Valids = " & to_string(write_collect0_valids)
                & ", next addr was $" & to_hstring(background_write_next_address&"000");

              background_write_next_address <= write_collect0_address + 1;
              background_write_next_address_matches_collect0 <= '0';
              background_write_next_address_matches_collect1 <= collect1_matches_collect0_plus_1;

              background_write_data <= write_collect0_data;
              background_write_valids <= write_collect0_valids;
              write_collect0_flushed <= '1';

            elsif background_write_next_address_matches_collect1 = '1' and background_write_source = '1' then
              show_collect1 := true;
              report "WRITE: background_write_data copied from write_collect1. Valids = " & to_string(write_collect1_valids)
                & ", next addr was $" & to_hstring(background_write_next_address&"000");
              background_write_next_address <= write_collect1_address + 1;
              background_write_next_address_matches_collect0 <= collect0_matches_collect1_plus_1;
              background_write_next_address_matches_collect1 <= '0';

              background_write_data <= write_collect1_data;
              background_write_valids <= write_collect1_valids;
              write_collect1_flushed <= '1';
            else
              report "WRITE: Write is not chained.";
              background_chained_write <= '0';
            end if;
          end if;

          if pause_phase = '1' then
            hr_clk_phaseshift <= write_phase_shift;
            if countdown_timeout = '1' then
              report "Advancing to HyperRAMFinishWriting";
              state <= HyperRAMFinishWriting;
            end if;
          else

            report "latency countdown = " & integer'image(countdown);

            -- Begin write mask pre-amble
            if ram_reading_held = '0' and countdown = 2 then
              hr_rwds <= '0';
              hr2_rwds <= '0';
              hr_d <= x"BE"; -- "before" data byte
              hr2_d <= x"BE"; -- "before" data byte
            end if;

            if countdown /= 0 then
              countdown <= countdown - 1;
            end if;
            if countdown = 1 then
              countdown_is_zero <= '1';
            end if;
            if countdown_is_zero = '1' then
              if extra_latency='1' then
                report "Waiting 6 more cycles for extra latency";
                -- If we were asked to wait for extra latency,
                -- then wait another 6 cycles.
                extra_latency <= '0';
                if hyperram0_select='1' then
                  countdown <= to_integer(extra_write_latency);
                else
                  countdown <= to_integer(extra_write_latency2);
                end if;
                -- XXX Assumes extra_write_latency is not zero
                countdown_is_zero <= '0';
              else
                -- Latency countdown for writing is over, we can now
                -- begin writing bytes.

                -- HyperRAM works on 16-bit fundamental transfers.
                -- This means we need to have two half-cycles, and pick which
                -- one we want to write during.
                -- If RWDS is asserted, then the write is masked, i.e., won't
                -- occur.
                -- In this first

                report "Presenting hr_d with ram_wdata or background data";
                if background_write='1' then
                  report "WRITE: Writing background byte $" & to_hstring(background_write_data(0))
                    & ", valids= " & to_string(background_write_valids)
                    & ", background words left = " & integer'image(background_write_count);
                  hr_d <= background_write_data(0);
                  hr2_d <= background_write_data(0);

                  background_write_data(0) <= background_write_data(1);
                  background_write_data(1) <= background_write_data(2);
                  background_write_data(2) <= background_write_data(3);
                  background_write_data(3) <= background_write_data(4);
                  background_write_data(4) <= background_write_data(5);
                  background_write_data(5) <= background_write_data(6);
                  background_write_data(6) <= background_write_data(7);
                  background_write_data(7) <= x"00";

                  hr_rwds <= not background_write_valids(0);
                  hr2_rwds <= not background_write_valids(0);
                  background_write_valids(0 to 6) <= background_write_valids(1 to 7);
                  background_write_valids(7) <= '0';
                else
                  -- XXX Doesn't handle 16-bit writes properly. But that's
                  -- okay, as they are only supported with the cache and
                  -- write-collecting, anyway.
                  hr_d <= ram_wdata;
                  hr2_d <= ram_wdata;
                  hr_rwds <= hyperram_access_address(0) xor write_byte_phase;
                  hr2_rwds <= hyperram_access_address(0) xor write_byte_phase;
                end if;

                -- Finish resetting write collectors when chaining
                if write_collect0_dispatchable='0' and write_collect0_flushed='1' and write_collect0_toolate='1' then
                  report "WRITECONTINUE: Resetting collect0";
                  write_collect0_flushed <= '0';
                  write_collect0_toolate <= '0';
                  show_collect0 := true;
                end if;
                if write_collect1_dispatchable='0' and write_collect1_flushed='1' and write_collect1_toolate='1' then
                  report "WRITECONTINUE: Resetting collect1";
                  write_collect1_flushed <= '0';
                  write_collect1_toolate <= '0';
                  show_collect1 := true;
                end if;

                -- Write byte
                write_byte_phase <= '1';
                if background_write='0' then
                  if write_byte_phase = '0' and hyperram_access_address(0)='1' then
                    hr_d <= x"ee"; -- even "masked" data byte
                    hr2_d <= x"ee"; -- even "masked" data byte
                  elsif write_byte_phase = '1' and hyperram_access_address(0)='0' then
                    hr_d <= x"0d"; -- odd "masked" data byte
                    hr2_d <= x"0d"; -- odd "masked" data byte
                  end if;
                  if background_write_count /= 0 then
                    background_write_count <= background_write_count - 1;
                  else
                    state <= HyperRAMFinishWriting;
                  end if;
                else
                  report "WRITE: Decrementing background_write_count from " & integer'image(background_write_count)
                    & ", write_continues = " & integer'image(write_continues);
                  if background_write_count /= 0 then
                    background_write_count <= background_write_count - 1;
                    if background_write_count = 3 and write_continues /= 0 then
                      report "WRITECONTINUE: Checking for chained writes (" & integer'image(write_continues) & " more continues allowed)";
                      report "WRITECONTINUE: Am looking for $" & to_hstring(background_write_next_address&"000") &
                        ", options are 0:$" & to_hstring(write_collect0_address&"000") &
                        " and 1:$" & to_hstring(write_collect1_address&"000");
                      show_collect0 := true;
                      show_collect1 := true;
                      -- Get ready to commit next write block, if one is there
                      if write_continues /= 0 and write_collect0_toolate='0' and write_collect0_flushed = '0'
                        and background_write_next_address_matches_collect0='1' then
                        report "WRITECONTINUE: Marking collect0 @ $" & to_hstring(write_collect0_address&"000") & " for chained write.";
                        write_collect0_toolate <= '1';
                        background_write_source <= '0';
                        report "background_write_source = 0";
                        show_collect0 := true;
                      elsif write_continues /= 0 and write_collect1_toolate='0' and write_collect1_flushed = '0'
                        and background_write_next_address_matches_collect1='1' then
                        report "WRITECONTINUE: Marking collect1 @ $" & to_hstring(write_collect1_address&"000") & " for chained write.";
                        write_collect1_toolate <= '1';
                        background_write_source <= '1';
                        report "background_write_source = 1";
                        show_collect1 := true;
                      end if;
                    end if;
                  end if;

                end if;
              end if;
            end if;
          end if;
        when HyperRAMFinishWriting =>
          if is_lump = '1' then
            is_lump <= '0';
            if lump_ending = '0' then
              le_cmd_done <= '1';
            end if;
            lump_ending <= '0';
          end if;
          -- Mask writing from here on.
          hr_cs0 <= '1';
          hr_cs1 <= '1';
          hr_rwds <= 'Z';
          hr2_rwds <= 'Z';
          hr_d <= x"FA"; -- "after" data byte
          hr2_d <= x"FA"; -- "after" data byte
          hr_clk_phaseshift <= write_phase_shift;
          report "clk_queue <= '00'";
          rwr_counter <= rwr_delay;
          rwr_waiting <= '1';
          report "returning to idle";
          state <= Idle;
        when LumpReadWait =>
          -- Linear burst read for LUMP.  Like HyperRAMReadWait, but with no
          -- cache, VIC-IV or abort logic: every byte goes to lump_rdata.
          hr_rwds <= 'Z';
          hr2_rwds <= 'Z';
          hr_d <= (others => 'Z');
          hr2_d <= (others => 'Z');
          -- (debug: the bus on each of the first 16 cycles here)
          if lump_dbg_idx < 16 then
            if hyperram0_select = '1' then
              lump_dbg_raw(lump_dbg_idx) <= hr_d; lump_dbg_rwds(lump_dbg_idx) <= hr_rwds;
            else
              lump_dbg_raw(lump_dbg_idx) <= hr2_d; lump_dbg_rwds(lump_dbg_idx) <= hr2_rwds;
            end if;
            lump_dbg_idx <= lump_dbg_idx + 1;
          end if;
          if lump_dbg_got = '0' and lump_dbg_cyc /= x"FF" then
            lump_dbg_cyc <= lump_dbg_cyc + 1;
          end if;
          if lump_slow = '1' then
            pause_phase <= not pause_phase;
          end if;

          if lump_slow = '1' and pause_phase = '1' then
            null;                     -- slow mode: the off cycle
          elsif lump_flushing = '1' then
            hr_clk_phaseshift <= read_phase_shift xor hyperram1_select;
            -- The device stopped responding.  CS is already released; emit
            -- the rest of the words as garbage so the requester's word count
            -- stays consistent.
            le_rdata <= x"DDDD";
            le_rdata_valid <= '1'; lump_dbg_rw <= lump_dbg_rw + 1;
            if lump_cnt(8) = '1' then
              lump_flushing <= '0';
              is_lump <= '0';
              le_cmd_done <= '1';
              rwr_counter <= rwr_delay;
              rwr_waiting <= '1';
              hr_clk_phaseshift <= write_phase_shift;
              state <= Idle;
            else
              lump_cnt <= lump_cnt - 1;
            end if;
          else
            hr_clk_phaseshift <= read_phase_shift xor hyperram1_select;
            -- Watchdog: reloaded on every byte, so it only fires if the
            -- device stops delivering data.
            if countdown_is_zero = '0' then
              countdown <= countdown - 1;
            end if;
            if countdown = 1 then
              countdown_is_zero <= '1';
            end if;
            if countdown_is_zero = '1' then
              report "LUMP: Timed out waiting for read data";
              hr_cs0 <= '1';
              hr_cs1 <= '1';
              le_error <= '1';
              -- Flush out the remaining words.  A half-received word is
              -- simply sent as part of the flush.
              lump_byte_odd <= '0';
              lump_flushing <= '1';
            end if;

            if hyperram0_select='1' then
              last_rwds <= hr_rwds;
            else
              last_rwds <= hr2_rwds;
            end if;
            if ((hr_rwds='1') and (hyperram0_select='1'))
              or ((hr2_rwds='1') and (hyperram1_select='1'))
            then
              hr_rwds_high_seen <= '1';
            else
              hr_rwds_high_seen <= '0';
            end if;
            if countdown_is_zero = '0' and
              ((((hr_rwds='1') and (hyperram0_select='1'))
                or ((hr2_rwds='1') and (hyperram1_select='1')))
               or (hr_rwds_high_seen='1')) then
              -- Data byte has arrived
              lump_dbg_got <= '1';
              countdown <= 63;
              countdown_is_zero <= '0';
              if lump_byte_odd = '0' then
                if hyperram0_select='1' then
                  lump_rbuf_lo <= hr_d;
                else
                  lump_rbuf_lo <= hr2_d;
                end if;
                lump_byte_odd <= '1';
              else
                if hyperram0_select='1' then
                  le_rdata <= hr_d & lump_rbuf_lo;
                else
                  le_rdata <= hr2_d & lump_rbuf_lo;
                end if;
                le_rdata_valid <= '1'; lump_dbg_rw <= lump_dbg_rw + 1;
                lump_byte_odd <= '0';
                lump_wg <= lump_wg + 1;
                if lump_wg = "11" then
                  lump_cur_addr <= lump_cur_addr + 1;
                  lump_seg <= '1';
                  lump_ng <= lump_ng + 1;
                end if;
                if lump_cnt(8) = '1' then
                  report "LUMP: Read burst complete";
                  hr_cs0 <= '1';
                  hr_cs1 <= '1';
                  is_lump <= '0';
                  le_cmd_done <= '1';
                  rwr_counter <= rwr_delay;
                  rwr_waiting <= '1';
                  hr_clk_phaseshift <= write_phase_shift;
                  state <= Idle;
                elsif lump_wg = "11" and lump_owner_cpu = '0'
                  and ((lump_seg = '1' and lump_yield = '1') or lump_ng = "11111") then
                  -- pause here (an 8-byte boundary): the CPU needs the bus
                  report "LUMP: Read burst paused";
                  hr_cs0 <= '1';
                  hr_cs1 <= '1';
                  is_lump <= '0';
                  lump_res <= '1';
                  lump_res_read <= '1';
                  lump_res_addr <= lump_cur_addr + 1;
                  lump_res_cnt <= lump_cnt - 1;
                  rwr_counter <= rwr_delay;
                  rwr_waiting <= '1';
                  hr_clk_phaseshift <= write_phase_shift;
                  state <= Idle;
                else
                  lump_cnt <= lump_cnt - 1;
                end if;
              end if;
            end if;
          end if;

        when LumpDoWrite =>
          -- Linear burst write for LUMP, modelled on the non-background
          -- path of HyperRAMDoWrite.  Bursts are whole multiples of 8 bytes,
          -- which also satisfies the revD parts' 32-bit write requirement.
          hr_clk_phaseshift <= write_phase_shift;
          if lump_slow = '1' then
            pause_phase <= not pause_phase;
          end if;
          if lump_dbg_wgot = '0' and lump_dbg_wcyc /= x"FF" then
            lump_dbg_wcyc <= lump_dbg_wcyc + 1;
          end if;

          if lump_slow = '1' and pause_phase = '1' then
            -- slow mode: the off cycle.  As HyperRAMDoWriteSlow, finish only
            -- here, after the last byte has had its whole (two-cycle) slot
            if countdown_timeout = '1' then
              state <= HyperRAMFinishWriting;
            end if;
          else
          -- Write mask pre-amble
          if countdown = 2 then
            hr_rwds <= '0';
            hr2_rwds <= '0';
            hr_d <= x"BE";
            hr2_d <= x"BE";
          end if;

          if countdown /= 0 then
            countdown <= countdown - 1;
          end if;
          if countdown = 1 then
            countdown_is_zero <= '1';
          end if;
          if countdown_is_zero = '1' then
            if extra_latency='1' then
              report "LUMP: Waiting for extra write latency";
              extra_latency <= '0';
              if hyperram0_select='1' then
                countdown <= to_integer(extra_write_latency);
              else
                countdown <= to_integer(extra_write_latency2);
              end if;
              countdown_is_zero <= '0';
            else
              -- RWDS high masks the byte
              lump_dbg_wb <= lump_dbg_wb + 1; lump_dbg_wgot <= '1';
              if lump_byte_odd = '0' then
                hr_d <= le_wdata(7 downto 0);
                hr2_d <= le_wdata(7 downto 0);
                hr_rwds <= not le_wdata_be(0);
                hr2_rwds <= not le_wdata_be(0);
                lump_wbuf_hi <= le_wdata(15 downto 8);
                lump_wbe_hi <= le_wdata_be(1);
                if lump_cnt(8) = '0' and lump_wg = "11" and lump_owner_cpu = '0'
                  and ((lump_seg = '1' and lump_yield = '1') or lump_ng = "11111") then
                  -- pause after this word (an 8-byte boundary): the CPU
                  -- needs the bus.  (No request for the next word.)
                  lump_ending <= '1';
                elsif lump_cnt(8) = '0' then
                  -- Next word is sampled two edges from now, i.e., for the
                  -- next low byte.
                  le_wdata_req <= '1'; lump_dbg_wq <= lump_dbg_wq + 1;
                end if;
                lump_byte_odd <= '1';
              else
                hr_d <= lump_wbuf_hi;
                hr2_d <= lump_wbuf_hi;
                hr_rwds <= not lump_wbe_hi;
                hr2_rwds <= not lump_wbe_hi;
                lump_byte_odd <= '0';
                lump_wg <= lump_wg + 1;
                if lump_wg = "11" then
                  lump_cur_addr <= lump_cur_addr + 1;
                  lump_seg <= '1';
                  lump_ng <= lump_ng + 1;
                end if;
                if lump_ending = '1' then
                  report "LUMP: Write burst paused";
                  lump_res <= '1';
                  lump_res_read <= '0';
                  lump_res_addr <= lump_cur_addr + 1;
                  lump_res_cnt <= lump_cnt - 1;
                end if;
                if lump_cnt(8) = '1' or lump_ending = '1' then
                  if lump_slow = '1' then
                    countdown_timeout <= '1';   -- finish on the off cycle
                  else
                    state <= HyperRAMFinishWriting;
                  end if;
                else
                  lump_cnt <= lump_cnt - 1;
                end if;
              end if;
            end if;
          end if;
          end if;                     -- (slow-mode gating)

        when HyperRAMReadWait =>
          hr_rwds <= 'Z';
          hr2_rwds <= 'Z';
          report "Presenting tri-state on hr_d";
          hr_d <= (others => 'Z');
          hr2_d <= (others => 'Z');
          if countdown_is_zero = '0' then
            countdown <= countdown - 1;
          end if;
          if countdown = 1 then
            countdown_is_zero <= '1';
          end if;
          if countdown_is_zero = '1' then
            -- Timed out waiting for read -- so return anyway, rather
            -- than locking the machine hard forever.
            if is_vic_fetch then
              -- The VIC-IV waits for 8 bytes with no timeout: give it
              -- the buffer anyway (the CPU is not waiting for this read)
              if vic_buffer_sent = '0' then
                viciv_buffer_toggle <= not viciv_buffer_toggle;
              end if;
            else
              rdata_hi_buf2 <= x"DD";       -- (was rdata_hi_buf: the pixelclock side's)
              rdata_buf2 <= x"DD";
              rdata_buf2(0) <= data_ready_toggle;
              rdata_buf2(1) <= busy_internal;
              report "asserting read_publish_strobe";
              read_publish_strobe2 <= '1';
            end if;
            rwr_counter <= rwr_delay;
            rwr_waiting <= '1';
            hr_clk_phaseshift <= write_phase_shift;
            report "returning to idle";
            state <= Idle;
          end if;

          -- Abort memory pre-fetching if we are asked to do something
          if is_block_read and (not is_vic_fetch) then
            if (read_request_prev='1' or write_request_prev='1') then
              -- Okay, here is the tricky case: If the request is for data
              -- that is in this block read, we DONT want to abort the read,
              -- because starting a new request will almost always be slower.
              report "DISPATCH: new request is for $" & to_hstring(address) & ", and we are reading $" & to_hstring(hyperram_access_address) & ", read = " & std_logic'image(read_request_o);
              report "DISPATCH:"
                & " read_request_o=" & std_logic'image(read_request_o)
                & " read_request_held=" & std_logic'image(read_request_held)
                & " address_matches_hyperram_access_address_block=" & std_logic'image(address_matches_hyperram_access_address_block);

              if write_request_prev='1' and address_matches_hyperram_access_address_block='1' then
                -- XXX We are writing to a block that we are pre-fetching.
                -- The write will happen anyway.  If we already have read the
                -- byte, we can update it, else we have to abort the block, so
                -- that the write can happen first.
                if byte_phase_greater_than_address_low_bits = '0' then
                  report "DISPATCH: Aborting pre-fetch due to incoming conflicting write request";
                  state <= ReadAbort;
                end if;

              elsif read_request_prev='1' and address_matches_hyperram_access_address_block='1' then
                -- New read request from later in this block.
                -- We know that we will have the data soon.
                -- The trick is coordinating our response.
                -- If we have already read the byte, then it's relatively easy:
                -- we can just return it, and pretend nothing happened...
                -- except that the 80mhz state machine that talks to slow_devices
                -- doesn't know that we can do this.
                report "DISPATCH: Continuing with pre-fetch, because the read hits the block being read!";

                -- Return the byte as soon as we have it available
                -- We don't test request_toggle, as the outer 80MHz state
                -- machine thinks we are still busy.
                if address_matches_hyperram_access_address_block = '1' then
                  if byte_phase_greater_than_address_low_bits='1' then
                    report "DISPATCH: Supplying data from partially read data block. Value is $"
                      & to_hstring(block_data(to_integer(address(4 downto 3)))(to_integer(address(2 downto 0))))
                      & " ( from (" & integer'image(to_integer(address(4 downto 3)))
                      & ")(" & integer'image(to_integer(address(2 downto 0)));
                    report "asserting read_publish_strobe";
                    read_request_delatch <= '1';
                    read_publish_strobe2 <= '1';
                    rdata_buf2 <= block_data(to_integer(address(4 downto 3)))(to_integer(address(2 downto 0)));
                    if rdata_16en='1' then
                      rdata_hi_buf2 <= block_data(to_integer(address(4 downto 3)))(to_integer(address(2 downto 0))+1);
                    end if;
                    last_request_toggle <= request_toggle;

                    -- Also push the whole cache line equivalent to
                    -- slow_devices to help it optimise linear reads
                    report "DISPATCH: byte_phase = " & integer'image(to_integer(byte_phase))
                      & ", address=$" & to_hstring(address);
                    if byte_phase_greater_than_address_end_of_row = '1' then
                      report "DISPATCH: Pushing block line to current_cache_line";
                      current_cache_line_drive <= block_data(to_integer(address(4 downto 3)));
                      current_cache_line_address_drive(26 downto 5) <= block_address(26 downto 5);
                      current_cache_line_address_drive(4 downto 3) <= address(4 downto 3);
                      current_cache_line_valid_drive <= '1';
                    else
                      report "DISPATCH: " & integer'image(to_integer(byte_phase)) & " not > " &
                        integer'image(to_integer(address(4 downto 3)&"111"));
                    end if;
                  end if;
                end if;

              elsif read_request_prev='1' and (not is_expected_to_respond) and (not is_vic_fetch) then
                report "DISPATCH: Aborting pre-fetch due to incoming read request";
                state <= ReadAbort;
              end if;
            end if;
            -- Because we can now abort at any time, we can pretend we are
            -- not busy. We are just filling in time...
            if busy_internal = '1' then
              report "DISPATCH: Clearing busy during tail of pre-fetch";
            end if;
            busy_internal <= '0';
          end if;
          -- After we have read the first 8 bytes, we know that we are no longer
          -- required to provide any further direct output, so clear the
          -- flag, so that the above logic can terminate a pre-fetch when required.
          if byte_phase = 8 and (not is_vic_fetch) then
            report "DISPATCH: Clearing is_expected_to_respond";
            is_expected_to_respond <= false;
          end if;
          -- Clear busy flag as soon as we can, allowing for pipelining
          -- through to and from slow_devices, so that we don't waste time,
          -- but also that we avoid doing it too early and screwing things up.
          if byte_phase = 4 then
            if is_block_read and cache_enabled then
              busy_internal <= '0';
            end if;
          end if;

          hr_clk_phaseshift <= read_phase_shift xor hyperram1_select;

          if hyperram0_select='1' then
            last_rwds <= hr_rwds;
          else
            last_rwds <= hr2_rwds;
          end if;
          -- HyperRAM drives RWDS basically to follow the clock.
          -- But first valid data is when RWDS goes high, so we have to
          -- wait until we see it go high.
--              report "DISPATCH watching for data: rwds=" & std_logic'image(hr_rwds) & ", clock=" & std_logic'image(hr_clock)
--                & ", rwds seen=" & std_logic'image(hr_rwds_high_seen);

          if ((hr_rwds='1') and (hyperram0_select='1'))
            or ((hr2_rwds='1') and (hyperram1_select='1'))
          then
            hr_rwds_high_seen <= '1';
--                if hr_rwds_high_seen = '0' then
          --                report "DISPATCH saw hr_rwds go high at start of data stream";
--                end if;
          else
            hr_rwds_high_seen <= '0';
          end if;
          if (((hr_rwds='1') and (hyperram0_select='1'))
              or ((hr2_rwds='1') and (hyperram1_select='1')))
            or (hr_rwds_high_seen='1') then
            -- Data has arrived: Latch either odd or even byte
            -- as required.
                  report "DISPATCH Saw read data = $" & to_hstring(hr_d);

            -- Update cache
            if (byte_phase < 32) and is_block_read and (not is_vic_fetch) then
              report "hr_sample='1'";
              report "hr_sample='0'";
              if hyperram0_select='1' then
                block_data(to_integer(byte_phase(4 downto 3)))(to_integer(byte_phase(2 downto 0)))
                  <= hr_d;
              else
                block_data(to_integer(byte_phase(4 downto 3)))(to_integer(byte_phase(2 downto 0)))
                  <= hr2_d;
              end if;
              show_block := true;
            end if;
            if (byte_phase < 8) then
              -- Store the bytes in the cache row
              if is_vic_fetch then
                if hyperram0_select='1' then
                  viciv_data_buffer(to_integer(byte_phase)) <= hr_d;
                else
                  viciv_data_buffer(to_integer(byte_phase)) <= hr2_d;
                end if;
                -- We load the data here 2x faster than it is sent to the VIC-IV
                -- so we can start transmitting immediately, to minimise latency
                if byte_phase = 0 then
                  report "VIC: Indicating buffer readiness";
                  viciv_buffer_toggle <= not viciv_buffer_toggle;
                  vic_buffer_sent <= '1';
                end if;
              elsif hyperram_access_address_matches_cache_row0 = '1' then
                cache_row0_valids(to_integer(byte_phase)) <= '1';
                report "hr_sample='1'";
                report "hr_sample='0'";
                if hyperram0_select='1' then
                  cache_row0_data(to_integer(byte_phase)) <= hr_d;
                else
                  cache_row0_data(to_integer(byte_phase)) <= hr2_d;
                end if;
                show_cache0 := true;
              elsif hyperram_access_address_matches_cache_row1 = '1' then
                cache_row1_valids(to_integer(byte_phase)) <= '1';
                report "hr_sample='1'";
                report "hr_sample='0'";
                if hyperram0_select='1' then
                  cache_row1_data(to_integer(byte_phase)) <= hr_d;
                else
                  cache_row1_data(to_integer(byte_phase)) <= hr2_d;
                end if;
                show_cache1 := true;
              elsif random_bits(1) = '0' then
                report "Zeroing cache_row0_valids";
                cache_row0_valids <= (others => '0');
                cache_row0_address <= hyperram_access_address(26 downto 3);
                hyperram_access_address_matches_cache_row0 <= '1';
                cache_row0_valids(to_integer(byte_phase)) <= '1';
                report "hr_sample='1'";
                report "hr_sample='0'";
                if hyperram0_select='1' then
                  cache_row0_data(to_integer(byte_phase)) <= hr_d;
                else
                  cache_row0_data(to_integer(byte_phase)) <= hr2_d;
                end if;
                show_cache0 := true;
              else
                report "Zeroing cache_row1_valids";
                cache_row1_valids <= (others => '0');
                cache_row1_address <= hyperram_access_address(26 downto 3);
                hyperram_access_address_matches_cache_row1 <= '1';
                cache_row1_valids(to_integer(byte_phase)) <= '1';
                report "hr_sample='1'";
                report "hr_sample='0'";
                if hyperram0_select='1' then
                  cache_row1_data(to_integer(byte_phase)) <= hr_d;
                else
                  cache_row1_data(to_integer(byte_phase)) <= hr2_d;
                end if;
                show_cache1 := true;
              end if;
            elsif (byte_phase = 8) and is_expected_to_respond then
              -- Export the appropriate cache line to slow_devices
              if hyperram_access_address_matches_cache_row0 = '1' and cache_enabled and (not is_vic_fetch) then
                if cache_row0_valids = x"FF" then
                end if;
              elsif hyperram_access_address_matches_cache_row1 = '1' and cache_enabled and (not is_vic_fetch) then
                if cache_row1_valids = x"FF" then
                  current_cache_line_drive <= cache_row1_data;
                  current_cache_line_address_drive(26 downto 3) <= hyperram_access_address(26 downto 3);
                  current_cache_line_valid_drive <= '1';
                end if;
              end if;
            end if;

            -- Quickly return the correct byte
            if to_integer(byte_phase) = (to_integer(hyperram_access_address(2 downto 0))+0) and is_expected_to_respond
              and (not is_vic_fetch) then
              if hyperram0_select='1' then
                report "DISPATCH: Returning freshly read data = $" & to_hstring(hr_d)
                  & ", hyperram0_select="& std_logic'image(hyperram0_select)
                  & ", hyperram1_select="& std_logic'image(hyperram1_select);
                if rdata_16en='1' and byte_phase(0)='1' then
                  rdata_hi_buf2 <= hr_d;
                else
                  rdata_buf2 <= hr_d;
                end if;
              else
                report "DISPATCH: Returning freshly read data = $" & to_hstring(hr2_d)
                  & ", hyperram0_select="& std_logic'image(hyperram0_select)
                  & ", hyperram1_select="& std_logic'image(hyperram1_select);
                if rdata_16en='1' and byte_phase(0)='1' then
                  rdata_hi_buf2 <= hr2_d;
                else
                  rdata_buf2 <= hr2_d;
                end if;
              end if;
              report "hr_return='1'";
              report "hr_return='0'";
              if rdata_16en='0' or byte_phase(0)='1' then
                report "asserting read_publish_strobe";
                read_publish_strobe2 <= '1';
              end if;
            end if;
            report "byte_phase = " & integer'image(to_integer(byte_phase));
            if ((byte_phase = 7) and (is_block_read=false))
              or (byte_phase = 31) then
              rwr_counter <= rwr_delay;
              rwr_waiting <= '1';
              report "returning to idle";
              last_request_toggle <= request_toggle;
              state <= Idle;
              hr_cs0 <= '1';
              hr_cs1 <= '1';
              hr_clk_phaseshift <= write_phase_shift;
              if is_block_read then
                block_valid <= '1';
              end if;
              is_prefetch <= false;
              is_expected_to_respond <= false;
            else
              byte_phase <= byte_phase + 1;
            end if;
          end if;
        when HyperRAMReadWaitSlow =>
          hr_rwds <= 'Z';
          hr2_rwds <= 'Z';
          report "Presenting tri-state on hr_d";
          hr_d <= (others => 'Z');
          hr2_d <= (others => 'Z');

          if hyperram0_select='1' then
            hr_d_last <= hr_d;
          else
            hr_d_last <= hr2_d;
          end if;

          pause_phase <= not pause_phase;

          -- Abort memory pre-fetching if we are asked to do something
          -- XXX unless it is for data that would be pre-fetched?
          if is_block_read and (not is_expected_to_respond) and (not is_vic_fetch)  then
            if ( write_request_o='1')
              -- If a new read is on the same cache line as the last, then
              -- assume whatever read we are doing now will satisfy it
--              or (read_request_o='1' and address(26 downto 3) /= ram_address(26 downto 3))
              or (read_request_o='1')
            then
              report "DISPATCH: Aborting pre-fetch due to incoming request";
              state <= ReadAbort;
            end if;
            -- Because we can now abort at any time, we can pretend we are
            -- not busy. We are just filling in time...
            if busy_internal = '1' then
              report "DISPATCH: Clearing busy during tail of pre-fetch";
            end if;
            if cache_enabled then
              busy_internal <= '0';
            end if;
          end if;
          -- After we have read the first 8 bytes, we know that we are no longer
          -- required to provide any further direct output, so clear the
          -- flag, so that the above logic can terminate a pre-fetch when required.
          if byte_phase = 8 then
            report "DISPATCH: Clearing is_expected_to_respond";
            is_expected_to_respond <= false;
          end if;

          if pause_phase = '1' then
            null;
          else
            hr_clk_phaseshift <= read_phase_shift xor hyperram1_select;
            if countdown_is_zero = '0' then
              countdown <= countdown - 1;
            end if;
            if countdown = 1 then
              countdown_is_zero <= '1';
            end if;
            if countdown_is_zero = '1' then
              -- Timed out waiting for read -- so return anyway, rather
              -- than locking the machine hard forever.
              if is_vic_fetch then
                -- The VIC-IV waits for 8 bytes with no timeout: give it
                -- the buffer anyway (the CPU is not waiting for this read)
                if vic_buffer_sent = '0' then
                  viciv_buffer_toggle <= not viciv_buffer_toggle;
                end if;
              else
                rdata_hi_buf2 <= x"DD";     -- (was rdata_hi_buf: the pixelclock side's)
                rdata_buf2 <= x"DD";
                rdata_buf2(0) <= data_ready_toggle;
                rdata_buf2(1) <= busy_internal;
                report "asserting read_publish_strobe";
                read_publish_strobe2 <= '1';
              end if;
              rwr_counter <= rwr_delay;
              rwr_waiting <= '1';
              report "returning to idle";
              state <= Idle;
              hr_clk_phaseshift <= write_phase_shift;
            end if;

            if hyperram0_select='1' then
              last_rwds <= hr_rwds;
            else
              last_rwds <= hr2_rwds;
            end if;
            -- HyperRAM drives RWDS basically to follow the clock.
            -- But first valid data is when RWDS goes high, so we have to
            -- wait until we see it go high.
--              report "DISPATCH watching for data: rwds=" & std_logic'image(hr_rwds) & ", clock=" & std_logic'image(hr_clock)
--                & ", rwds seen=" & std_logic'image(hr_rwds_high_seen);

            if ((hr_rwds='1') and (hyperram0_select='1')) or ((hr2_rwds='1') and (hyperram1_select='1'))
            then
              hr_rwds_high_seen <= '1';
            else
              hr_rwds_high_seen <= '0';
--                if hr_rwds_high_seen = '0' then
            --                report "DISPATCH saw hr_rwds go high at start of data stream";
--                end if;
            end if;
            if (((hr_rwds='1') and (hyperram0_select='1')) or ((hr2_rwds='1') and (hyperram1_select='1')))
              or (hr_rwds_high_seen='1') then
              -- Data has arrived: Latch either odd or even byte
              -- as required.
--                  report "DISPATCH Saw read data = $" & to_hstring(hr_d);

              -- Update cache
              if (byte_phase < 32) and is_block_read and (not is_vic_fetch) then
                report "hr_sample='1'";
                report "hr_sample='0'";
                if hyperram0_select='1' then
                  block_data(to_integer(byte_phase(4 downto 3)))(to_integer(byte_phase(2 downto 0)))
                    <= hr_d;
                else
                  block_data(to_integer(byte_phase(4 downto 3)))(to_integer(byte_phase(2 downto 0)))
                    <= hr2_d;
                end if;
                show_block := true;
              end if;
              if byte_phase < 8 then
                -- Store the bytes in the cache row
                if is_vic_fetch then
                  if hyperram0_select='1' then
                    viciv_data_buffer(to_integer(byte_phase)) <= hr_d;
                  else
                    viciv_data_buffer(to_integer(byte_phase)) <= hr2_d;
                  end if;
                  -- Slow mode: the bytes arrive no faster than they are sent
                  -- to the VIC-IV (one per pixelclock), so hand the buffer
                  -- over only once it is full
                  if byte_phase = 7 then
                    report "VIC: Indicating buffer readiness";
                    viciv_buffer_toggle <= not viciv_buffer_toggle;
                    vic_buffer_sent <= '1';
                  end if;
                elsif hyperram_access_address_matches_cache_row0 = '1' then
                  cache_row0_valids(to_integer(byte_phase)) <= '1';
                  report "hr_sample='1'";
                  report "hr_sample='0'";
                  if hyperram0_select='1' then
                    cache_row0_data(to_integer(byte_phase)) <= hr_d;
                  else
                    cache_row0_data(to_integer(byte_phase)) <= hr2_d;
                  end if;
                  show_cache0 := true;
                elsif hyperram_access_address_matches_cache_row1 = '1' then
                  cache_row1_valids(to_integer(byte_phase)) <= '1';
                  report "hr_sample='1'";
                  report "hr_sample='0'";
                  if hyperram0_select='1' then
                    cache_row1_data(to_integer(byte_phase)) <= hr_d;
                  else
                    cache_row1_data(to_integer(byte_phase)) <= hr2_d;
                  end if;
                  show_cache1 := true;
                elsif random_bits(1) = '0' then
                  report "Zeroing cache_row0_valids";
                  cache_row0_valids <= (others => '0');
                  cache_row0_address <= hyperram_access_address(26 downto 3);
                  hyperram_access_address_matches_cache_row0 <= '1';
                  cache_row0_valids(to_integer(byte_phase)) <= '1';
                  report "hr_sample='1'";
                  report "hr_sample='0'";
                  if hyperram0_select='1' then
                    cache_row0_data(to_integer(byte_phase)) <= hr_d;
                  else
                    cache_row0_data(to_integer(byte_phase)) <= hr2_d;
                  end if;
                  show_cache0 := true;
                else
                  report "Zeroing cache_row1_valids";
                  cache_row1_valids <= (others => '0');
                  cache_row1_address <= hyperram_access_address(26 downto 3);
                  hyperram_access_address_matches_cache_row1 <= '1';
                  cache_row1_valids(to_integer(byte_phase)) <= '1';
                  report "hr_sample='1'";
                  report "hr_sample='0'";
                  if hyperram0_select='1' then
                    cache_row1_data(to_integer(byte_phase)) <= hr_d;
                  else
                    cache_row1_data(to_integer(byte_phase)) <= hr2_d;
                  end if;
                  show_cache1 := true;
                end if;
              else
                -- Export the appropriate cache line to slow_devices
                if hyperram_access_address_matches_cache_row0 = '1' and cache_enabled and (not is_vic_fetch) then
                  if cache_row0_valids = x"FF" then
                    current_cache_line_drive <= cache_row0_data;
                    current_cache_line_address_drive(26 downto 3) <= hyperram_access_address(26 downto 3);
                    current_cache_line_valid_drive <= '1';
                  end if;
                elsif hyperram_access_address_matches_cache_row1 = '1' and cache_enabled and (not is_vic_fetch) then
                  if cache_row1_valids = x"FF" then
                    current_cache_line_drive <= cache_row1_data;
                    current_cache_line_address_drive(26 downto 3) <= hyperram_access_address(26 downto 3);
                    current_cache_line_valid_drive <= '1';
                  end if;
                end if;
              end if;

              -- Quickly return the correct byte
              if byte_phase = hyperram_access_address_read_time_adjusted and (not is_vic_fetch) then
                if hyperram0_select='1' then
                  report "DISPATCH: Returning freshly read data = $" & to_hstring(hr_d);
                  rdata_buf2 <= hr_d;
                else
                  report "DISPATCH: Returning freshly read data = $" & to_hstring(hr2_d)
                    & ", byte_phase=" & integer'image(to_integer(byte_phase));
                  rdata_buf2 <= hr2_d;
                end if;
                report "hr_return='1'";
                report "hr_return='0'";
                if rdata_16en='0' then
                  report "asserting read_publish_strobe2 on low byte";
                  read_publish_strobe2 <= '1';
                end if;
              end if;
              if byte_phase = (hyperram_access_address_read_time_adjusted+1) and (not is_vic_fetch) and (rdata_16en='1') then
                if hyperram0_select='1' then
                  report "DISPATCH: Returning freshly read high-byte data = $" & to_hstring(hr_d);
                  rdata_hi_buf2 <= hr_d;
                else
                  report "DISPATCH: Returning freshly read data = $" & to_hstring(hr2_d)
                    & ", byte_phase=" & integer'image(to_integer(byte_phase));
                  rdata_hi_buf2 <= hr2_d;
                end if;
                report "hr_return='1'";
                report "hr_return='0'";

                report "asserting read_publish_strobe2 on high byte";
                read_publish_strobe2 <= '1';

              end if;
              report "byte_phase = " & integer'image(to_integer(byte_phase));
              if (byte_phase = seven_plus_read_time_adjust and is_block_read=false)
                or (byte_phase = thirtyone_plus_read_time_adjust and is_block_read=true)
              then
                rwr_counter <= rwr_delay;
                rwr_waiting <= '1';
                report "returning to idle";
                state <= Idle;
                hr_cs0 <= '1';
                hr_cs1 <= '1';
                hr_clk_phaseshift <= write_phase_shift;
              else
                byte_phase <= byte_phase + 1;
              end if;
            end if;
          end if;
      end case;

      -------------------------------------------------------------------------
      -- CPU path v2 (#949).  Reads that hit, and writes, never wait for the
      -- HyperRAM; misses, write-outs and prefetches are LUMP-engine bursts.
      -------------------------------------------------------------------------
      v2_done := false;
      v2_pf_go := false;
      next_toggle_drive <= expansionram_current_cache_line_next_toggle;
      prev_toggle_drive <= expansionram_current_cache_line_prev_toggle;
      v2_idx := to_integer(l_addr(2 downto 0));
      for j in 0 to H_NW - 1 loop
        if w_age(j) /= 63 then w_age(j) <= w_age(j) + 1; end if;
      end loop;

      -- Requests (from the pixelclock side; each lasts two of our cycles)
      if read_request = '1' and write_request = '0' and v2_ram = '1'
        and rd_l = '0' and wr_l = '0' then
        rd_l <= '1';
        l_addr <= address;
        busy_v2 <= '1';
        rs <= R_LOOK;
      end if;
      if read_request = '0' and write_request = '1' and v2_ram = '1'
        and rd_l = '0' and wr_l = '0' then
        wr_l <= '1';
        l_addr <= address;
        l_wdata <= wdata;
        busy_v2 <= '1';
        rs <= R_LOOK;
        if rdata_16en = '1' then
          l_wdata_hi <= wdata_hi;
          l_wen_lo <= wen_lo;
          l_wen_hi <= wen_hi;
        else
          l_wen_lo <= '1';
          l_wen_hi <= '0';
        end if;
        -- The exported line stops being valid at once, until the write has
        -- been applied (the CPU may read it directly within a few cycles)
        if v2_en = '1' then
          current_cache_line_valid <= '0';
        end if;
      end if;

      -- Fill data from the engine: word fl_word of line fl_line
      if le_error = '1' and lump_owner_cpu = '1' then fl_err <= '1'; end if;
      if le_rdata_valid = '1' and lump_owner_cpu = '1' and fill_active = '1' then
        if fl_word /= 3 then
          c_data(fl_slot(fl_line))(16 * fl_word + 15 downto 16 * fl_word) <= le_rdata;
          fl_word <= fl_word + 1;
        else
          -- the line is complete; posted writes to it go over the top
          v2_line := c_data(fl_slot(fl_line));
          v2_line(63 downto 48) := le_rdata;
          v2_tag := fl_tag + fl_line;
          for j in 0 to H_NW - 1 loop
            if w_tag(j) = v2_tag then
              for k in 0 to 7 loop
                if w_mask(j)(k) = '1' then
                  v2_line(8 * k + 7 downto 8 * k) := w_data(j)(8 * k + 7 downto 8 * k);
                end if;
              end loop;
            end if;
          end loop;
          c_data(fl_slot(fl_line)) <= v2_line;
          if fl_err = '0' and le_error = '0' then
            c_val(fl_slot(fl_line)) <= '1';
          end if;
          for i in 0 to H_NL - 1 loop
            if i /= fl_slot(fl_line) and c_tag(i) = v2_tag then c_val(i) <= '0'; end if;
          end loop;
          v2_done := true;
          report "V2: line $" & to_hstring(v2_tag & "000") & " = $" & to_hstring(v2_line);
          v2_done_slot := fl_slot(fl_line);
          fl_word <= 0;
          if fl_line = fl_n - 1 then
            fill_active <= '0';
          else
            fl_line <= fl_line + 1;
          end if;
        end if;
      end if;
      -- Write-out data for the engine (sampled two edges after its request)
      if le_wdata_req = '1' and lump_owner_cpu = '1' then
        cj_wdata <= w_data(f_j)(16 * f_word + 15 downto 16 * f_word);
        cj_wdata_be <= w_mask(f_j)(2 * f_word + 1 downto 2 * f_word);
        if f_word /= 3 then f_word <= f_word + 1; end if;
      end if;
      -- A job has finished
      if le_cmd_done = '1' and lump_owner_cpu = '1' then
        lump_owner_cpu <= '0';
        cj_busy <= '0';
        if cj_read = '0' then
          w_mask(f_j) <= (others => '0');
          w_fl(f_j) <= '0';
        end if;
        fill_active <= '0';
      end if;

      if v2_done then
        -- a read waiting for this line gets it now; the exported line moves
        -- to it if the CPU asked for it; the VIC-IV gets its line
        if rs /= R_IDLE and rd_l = '1' and v2_tag = l_addr(26 downto 3) then
          v2_publish(byte_of(v2_line, v2_idx), byte_of(v2_line, (v2_idx + 1) mod 8));
          v2_set_export(v2_tag, v2_line);
          v2_prefetch_from(v2_tag);
        elsif rs = R_WAIT or rs = R_DECIDE then
          rs <= R_LOOK;
        end if;
        if x_want = '1' and v2_tag = x_addr and wr_l = '0' and write_request = '0' then
          v2_set_export(x_addr, v2_line);
          x_want <= '0';
          if v2_flags(2) = '1' then v2_prefetch_from(x_addr); end if;
        end if;
        if vic_want = '1' and v2_tag = vic_tag then
          for k in 0 to 7 loop
            viciv_data_buffer(k) <= v2_line(8 * k + 7 downto 8 * k);
          end loop;
          viciv_buffer_toggle <= not viciv_buffer_toggle;
          vic_want <= '0';
        end if;
      end if;

      case rs is
        when R_IDLE =>
          null;
        when R_LOOK =>
          for i in 0 to H_NL - 1 loop
            if c_tag(i) = l_addr(26 downto 3) then lk_c(i) <= '1'; else lk_c(i) <= '0'; end if;
          end loop;
          for j in 0 to H_NW - 1 loop
            if w_tag(j) = l_addr(26 downto 3) then lk_w(j) <= '1'; else lk_w(j) <= '0'; end if;
          end loop;
          rs <= R_DECIDE;
        when R_DECIDE =>
          if v2_done then
            null;                       -- (handled above)
          elsif rd_l = '1' then
            v2_wh := -1;
            v2_hit := -1;
            for j in 0 to H_NW - 1 loop
              if lk_w(j) = '1' and w_mask(j)(v2_idx) = '1' then v2_wh := j; end if;
            end loop;
            for i in H_NL - 1 downto 0 loop
              if lk_c(i) = '1' and c_val(i) = '1' then v2_hit := i; end if;
            end loop;
            if v2_hit /= -1 then
              -- (a cached line already has the posted writes in it)
              v2_hits <= v2_hits + 1;
              v2_publish(byte_of(c_data(v2_hit), v2_idx), byte_of(c_data(v2_hit), (v2_idx + 1) mod 8));
              v2_set_export(l_addr(26 downto 3), c_data(v2_hit));
              v2_prefetch_from(l_addr(26 downto 3));
            elsif v2_wh /= -1 then
              v2_hits <= v2_hits + 1;
              v2_publish(byte_of(w_data(v2_wh), v2_idx), byte_of(w_data(v2_wh), (v2_idx + 1) mod 8));
            else
              v2_misses <= v2_misses + 1;
              -- (unless the fill under way brings this line)
              if not (fill_active = '1' and l_addr(26 downto 3) - fl_tag < fl_n) then
                want_fill <= '1';
              end if;
              rs <= R_WAIT;
            end if;
          elsif wr_l = '1' then
            -- Posted write: into the buffer holding this line, or a free one;
            -- wait if neither, or if this line's buffer is being written out
            v2_wh := -1;
            v2_free := -1;
            v2_frozen := false;
            for j in 0 to H_NW - 1 loop
              if lk_w(j) = '1' and w_mask(j) /= x"00" then
                if w_fl(j) = '1' then v2_frozen := true; else v2_wh := j; end if;
              end if;
              if w_mask(j) = x"00" and v2_free = -1 then v2_free := j; end if;
            end loop;
            if v2_wh = -1 and v2_free /= -1 and not v2_frozen then
              v2_wh := v2_free;
              v2_line := (others => '0');
              v2_mask := (others => '0');
            elsif v2_wh /= -1 then
              v2_line := w_data(v2_wh);
              v2_mask := w_mask(v2_wh);
            end if;
            if v2_wh = -1 or v2_frozen then
              w_stall <= '1';
              rs <= R_LOOK;
            else
              w_stall <= '0';
              if l_wen_lo = '1' then
                v2_line(8 * v2_idx + 7 downto 8 * v2_idx) := l_wdata;
                v2_mask(v2_idx) := '1';
              end if;
              if l_wen_hi = '1' and v2_idx /= 7 then
                v2_line(8 * v2_idx + 15 downto 8 * v2_idx + 8) := l_wdata_hi;
                v2_mask(v2_idx + 1) := '1';
              end if;
              report "V2: write $" & to_hstring(l_addr) & " = $" & to_hstring(l_wdata)
                & " into buffer " & integer'image(v2_wh);
              w_tag(v2_wh)  <= l_addr(26 downto 3);
              w_data(v2_wh) <= v2_line;
              w_mask(v2_wh) <= v2_mask;
              w_age(v2_wh)  <= 0;
              w_cur <= v2_wh;
              -- write through into the cached copy (also one completing now)
              for i in 0 to H_NL - 1 loop
                if c_tag(i) = l_addr(26 downto 3)
                  and (c_val(i) = '1' or (v2_done and i = v2_done_slot)) then
                  for k in 0 to 7 loop
                    if (k = v2_idx and l_wen_lo = '1') or (k = v2_idx + 1 and l_wen_hi = '1') then
                      c_data(i)(8 * k + 7 downto 8 * k) <= v2_line(8 * k + 7 downto 8 * k);
                    end if;
                  end loop;
                end if;
              end loop;
              -- and into the exported line
              if v2_en = '1' then
                current_cache_line_valid <= exp_valid and enable_current_cache_line;
              end if;
              if exp_addr = l_addr(26 downto 3) then
                v2_line2 := exp_data;
                if l_wen_lo = '1' then
                  v2_line2(8 * v2_idx + 7 downto 8 * v2_idx) := l_wdata;
                end if;
                if l_wen_hi = '1' and v2_idx /= 7 then
                  v2_line2(8 * v2_idx + 15 downto 8 * v2_idx + 8) := l_wdata_hi;
                end if;
                v2_set_export(exp_addr, v2_line2);
              end if;
              wr_l <= '0';
              rs <= R_IDLE;
            end if;
          else
            rs <= R_IDLE;
          end if;
        when R_WAIT =>
          -- (a completed fill sends us back to R_LOOK, above)
          if rd_l = '0' then rs <= R_IDLE; end if;
      end case;

      -- The CPU moved on from the exported line (next/prev)
      if next_toggle_drive /= next_toggle_seen then
        next_toggle_seen <= next_toggle_drive;
        x_addr <= exp_addr + 1;
        x_down <= '0';
        x_look <= '1';
        x_want <= '0';
      elsif prev_toggle_drive /= prev_toggle_seen then
        prev_toggle_seen <= prev_toggle_drive;
        x_addr <= exp_addr - 1;
        x_down <= '1';
        x_look <= '1';
        x_want <= '0';
      elsif x_look = '1' then
        x_look <= '0';
        x_use <= '1';
        for i in 0 to H_NL - 1 loop
          if c_tag(i) = x_addr then x_hit(i) <= '1'; else x_hit(i) <= '0'; end if;
        end loop;
      elsif x_use = '1' then
        x_use <= '0';
        v2_hit := -1;
        for i in 0 to H_NL - 1 loop
          if x_hit(i) = '1' and c_val(i) = '1' then v2_hit := i; end if;
        end loop;
        if v2_hit /= -1 and wr_l = '0' and write_request = '0' then
          v2_set_export(x_addr, c_data(v2_hit));
          if v2_flags(2) = '1' then v2_prefetch_from(x_addr); end if;
        elsif v2_en = '1' then
          x_want <= '1';                -- (fetched, then exported)
        end if;
      end if;

      -- VIC-IV fetches: the request (its address is held until the 8 bytes
      -- are delivered), the look-up in two steps, then the line or a fill
      if v2_en = '1' and viciv_request_toggle /= viciv_last_request_toggle
        and vic_look = '0' and vic_use = '0' and vic_want = '0' then
        viciv_last_request_toggle <= viciv_request_toggle;
        viciv_request_count <= viciv_request_count + 1;
        vic_tag(26 downto 19) <= viciv_bank;
        vic_tag(18 downto 3) <= viciv_addr;
        vic_look <= '1';
      elsif vic_look = '1' then
        vic_look <= '0';
        vic_use <= '1';
        for i in 0 to H_NL - 1 loop
          if c_tag(i) = vic_tag then vic_hit(i) <= '1'; else vic_hit(i) <= '0'; end if;
        end loop;
      elsif vic_use = '1' then
        vic_use <= '0';
        v2_hit := -1;
        for i in 0 to H_NL - 1 loop
          if vic_hit(i) = '1' and c_val(i) = '1' then v2_hit := i; end if;
        end loop;
        if v2_hit /= -1 then
          -- (cached lines have the CPU's writes in them)
          for k in 0 to 7 loop
            viciv_data_buffer(k) <= c_data(v2_hit)(8 * k + 7 downto 8 * k);
          end loop;
          viciv_buffer_toggle <= not viciv_buffer_toggle;
        else
          vic_want <= '1';
        end if;
      end if;

      -- Prefetch scanner: one candidate line at a time
      if pf_chk2 = '1' then
        pf_chk2 <= '0';
        if pf_present = '0' then
          pf_want <= '1';
          pf_line <= pf_cand;
        end if;
        if pf_k <= H_PF then pf_k <= pf_k + 1; end if;
      elsif pf_chk = '1' then
        pf_chk <= '0';
        pf_chk2 <= '1';
        pf_present <= '0';
        for i in 0 to H_NL - 1 loop
          if c_val(i) = '1' and c_tag(i) = pf_cand then pf_present <= '1'; end if;
        end loop;
        if fill_active = '1' and pf_cand - fl_tag < fl_n then pf_present <= '1'; end if;
      elsif pf_k <= H_PF and pf_want = '0' then
        if pf_down = '1' then
          pf_cand <= pf_base - pf_k;
        else
          pf_cand <= pf_base + pf_k;
        end if;
        pf_chk <= '1';
      end if;
      if v2_pf_go then
        pf_base <= v2_pf_base;
        pf_down <= v2_pf_down;
        pf_k <= 1;
        pf_chk <= '0';
        pf_chk2 <= '0';
        pf_want <= '0';
      end if;

      -- LUMP wrote, or invalidated: cached copies may be stale
      if v2_inval = '1' then
        c_val <= (others => '0');
        exp_valid <= '0';
        exp_addr <= (others => '1');
        if v2_en = '1' then
          current_cache_line_valid <= '0';
          current_cache_line_address <= (others => '1');
        end if;
        pf_k <= H_PF + 1;
        pf_chk <= '0';
        pf_chk2 <= '0';
        pf_want <= '0';
      end if;

      -- Jobs for the engine, when it is free: the VIC-IV's line, the CPU's
      -- line, the line the exported line moves to, then posted writes that
      -- must go (a write waiting for a buffer, or LUMP waiting), then posted
      -- writes the CPU has moved on from, then prefetch.  (Posted writes are
      -- still written out with v2 switched off.)
      if cj_req = '0' and cj_busy = '0' and first_transaction = '0'
        and start_delay_expired = '1' then
        -- urgent write-outs, then background ones
        v2_wh := -1;
        if w_stall = '1' or lump_q_valid = '1' or lump_res = '1' or v2_en = '0' then
          for j in 0 to H_NW - 1 loop
            if w_mask(j) /= x"00" and w_fl(j) = '0' and (j /= w_cur or v2_wh = -1) then
              v2_wh := j;
            end if;
          end loop;
        end if;
        v2_free := -1;
        for j in 0 to H_NW - 1 loop
          if w_mask(j) /= x"00" and w_fl(j) = '0' and v2_free = -1
            and (j /= w_cur or w_mask(j) = x"FF" or w_age(j) >= 32) then
            v2_free := j;
          end if;
        end loop;
        if vic_want = '1' and fill_active = '0' then
          v2_start_fill(vic_tag, '0');
        elsif want_fill = '1' and fill_active = '0' then
          want_fill <= '0';
          v2_start_fill(l_addr(26 downto 3), '0');
        elsif x_want = '1' and fill_active = '0' then
          v2_start_fill(x_addr, x_down);
        elsif v2_wh /= -1 then
          v2_start_flush(v2_wh);
        elsif v2_free /= -1 then
          v2_start_flush(v2_free);
        elsif pf_want = '1' and fill_active = '0' and v2_en = '1'
          and lump_q_valid = '0' and lump_res = '0' and is_lump = '0' then
          -- (LUMP goes before prefetch, and a prefetch must not hold the job
          -- slot while a LUMP burst runs: a write-out may need it)
          pf_want <= '0';
          v2_start_fill(pf_line, pf_down);
          cj_pf <= '1';
        end if;
      end if;

      -- slow_devices must wait while we cannot take a request.  A write is
      -- taken into a buffer within three cycles, sooner than slow_devices
      -- can bring the next request, so it only holds things up when both
      -- buffers are in use.
      if v2_en = '0' then
        busy_v2 <= '0';
      elsif start_delay_expired = '0' or first_transaction = '1'
        or rd_l = '1' or (read_request = '1' and v2_ram = '1')
        or (wr_l = '1' and w_stall = '1')
        or ((wr_l = '1' or (write_request = '1' and v2_ram = '1'))
            and w_mask(0) /= x"00" and w_mask(1) /= x"00") then
        busy_v2 <= '1';
      else
        busy_v2 <= '0';
      end if;
    end if;

  end process;
end gothic;

