library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

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
         hr_cs1 : out std_logic := '1'
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
    HyperRAMReadWait
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
  signal cache_enabled : boolean := false;
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
  signal fast_cmd_mode : std_logic := '0';
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
  signal viciv_next_byte : integer range 0 to 8 := 0;
  signal viciv_request_count : unsigned(31 downto 0) := to_unsigned(0,32);
  signal is_vic_fetch : boolean := false;
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

begin
  process (pixelclock,clock163,clock325,hr_clk,hr_clk_phaseshift) is
    variable clock_status_vector : unsigned(4 downto 0);
    variable tempaddr : unsigned(26 downto 0);
    variable show_cache0 : boolean := false;
    variable show_cache1 : boolean := false;
    variable show_collect0 : boolean := false;
    variable show_collect1 : boolean := false;
    variable show_block : boolean := false;
    variable show_always : boolean := true;
  begin
    if rising_edge(pixelclock) then

      invalidate_read_cache <= '0';
      cache_row_update_address_changed <= '0';

      if read_request='1' then
        read_request_latch <= '1';
      end if;
      if write_request='1' then
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

      report "read_request=" & std_logic'image(read_request)
        & ", read_request_held=" & std_logic'image(read_request_held)
        & ", write_request_held=" & std_logic'image(write_request_held)
        & ", read_request_latch=" & std_logic'image(read_request_latch)
        & ", write_request_latch=" & std_logic'image(write_request_latch)
        & ", busy_internal=" & std_logic'image(busy_internal)
        & ", write_request=" & std_logic'image(write_request)
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
        busy <= busy_internal or write_blocked or queued_write or queued2_write or (not start_delay_expired);
      else
        -- With no cache, we have to IMMEDIATELY assert busy when we see a
        -- request to avoid a race-condition with slow_devices
        busy <= busy_internal or write_blocked or queued_write or queued2_write
                or read_request or write_request or read_request_latch or write_request_latch
                or (not start_delay_expired);
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
        busy <= '1';
      end if;

      -- Similarly as soon as we see a VIC-IV request come through we need to
      -- assert busy
      if viciv_request_toggle /= viciv_last_request_toggle then
        busy <= '1';
      end if;

      if read_request = '1' or write_request = '1' or read_request_latch='1' or write_request_latch='1' then
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
      if write_collect1_dispatchable = '0' and write_collect1_toolate = '0' and write_collect1_flushed = '0' then
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
      if (read_request or read_request_latch)='1' and busy_internal='0'
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
              rdata_buf <= unsigned(cache_row0_valids);
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

      elsif (write_request or write_request_latch)='1' and busy_internal='0' then
        report "Making write request: addr $" & to_hstring(address) & " <= " & to_hstring(wdata);
        -- Begin write request
        -- Latch address and data

        write_request_latch <= '0';

        if address(23 downto 4) = x"FFFFF" and address(25 downto 24) = "11" then
          case address(3 downto 0) is
            when x"0" =>
              write_continues_max <= to_integer(wdata);
            when x"1" =>
              viciv_bank <= wdata;
            when x"2" =>
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
              conf_buf1_in <= wdata;
              conf_buf1_set <= not conf_buf1_set;
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
      if read_request='1' or read_request_held='1' then
        read_request_prev <= '1';
      else
        read_request_prev <= '0';
      end if;
      if write_request='1' or write_request_held='1' then
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


      if enable_current_cache_line='1' then
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
      if read_publish_toggle /= last_read_publish_toggle then
        read_publish_toggle <= last_read_publish_toggle;
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
      read_request_held <= read_request;
      write_request_held <= write_request;

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
            if (viciv_request_toggle /= viciv_last_request_toggle)
              -- Only start VIC-IV fetches if we don't have a transaction
              -- already waiting to go.
              and ((request_toggle = last_request_toggle) or viciv_debug_priority='1')
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
          if fast_cmd_mode='1' and fast_cmd_for_write_enabled then
            state <= HyperRAMOutputCommand;
            hr_clk_phaseshift <= write_phase_shift;
            hr_clk_fast <= '1';
          else
            state <= HyperRAMOutputCommandSlow;
            hr_clk_phaseshift <= write_phase_shift;
            hr_clk_fast <= '0';
          end if;

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
            and (is_vic_fetch = false) then
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
                if fast_read_mode='1' then
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
                if fast_write_mode='1' then
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
            and (is_vic_fetch = false) then
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
              if fast_read_mode='1' then
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
              if fast_write_mode='1' then
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
          if countdown = 1 then
            countdown_is_zero <= '1';
          end if;
          if countdown /= 0 then
            countdown <= countdown - 1;
          else
            report "asserting countdown_timeout";
            countdown_timeout <= '1';
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
          if background_write_count = 0 then
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
              and (read_request='1' or write_request='1' or write_blocked='1') then
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
              and (read_request='1' or write_request='1' or write_blocked='1') then
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
            rdata_hi_buf <= x"DD";
            rdata_buf2 <= x"DD";
            rdata_buf2(0) <= data_ready_toggle;
            rdata_buf2(1) <= busy_internal;
            report "asserting read_publish_strobe";
            read_publish_strobe2 <= '1';
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
              report "DISPATCH: new request is for $" & to_hstring(address) & ", and we are reading $" & to_hstring(hyperram_access_address) & ", read = " & std_logic'image(read_request);
              report "DISPATCH:"
                & " read_request=" & std_logic'image(read_request)
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
            if ( write_request='1')
              -- If a new read is on the same cache line as the last, then
              -- assume whatever read we are doing now will satisfy it
--              or (read_request='1' and address(26 downto 3) /= ram_address(26 downto 3))
              or (read_request='1')
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
              rdata_hi_buf <= x"DD";
              rdata_buf2 <= x"DD";
              rdata_buf2(0) <= data_ready_toggle;
              rdata_buf2(1) <= busy_internal;
              report "asserting read_publish_strobe";
              read_publish_strobe2 <= '1';
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
                  -- We load the data here 2x faster than it is sent to the VIC-IV
                  -- so we can start transmitting immediately, to minimise latency
                  if byte_phase = 0 then
                    report "VIC: Indicating buffer readiness";
                    viciv_buffer_toggle <= not viciv_buffer_toggle;
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
    end if;

  end process;
end gothic;

