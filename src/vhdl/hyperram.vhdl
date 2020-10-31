library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity hyperram is
  generic ( in_simulation : in boolean := false);
  Port ( clock163 : in std_logic; -- Used for fast clock for HyperRAM &
                                  -- request interface
         clock325 : in std_logic; -- Used for fast clock for HyperRAM SERDES units

         read_request : in std_logic;
         write_request : in std_logic;
         transaction_byte_count : in integer range 1 to 4;
         transaction_address : in unsigned(26 downto 0);
         transaction_wdata : in unsigned(31 downto 0);
         transaction_rdata : out unsigned(31 downto 0);
         
         data_ready_strobe : out std_logic := '0';
         busy : out std_logic := '0';

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
    HyperRAMOutputCommandSlow,
    HyperRAMDoWriteSlow,
    HyperRAMFinishWriting,
    HyperRAMReadWaitSlow,
    HyperRAMExportReadData
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
  signal ram_wdata : unsigned(31 downto 0) := to_unsigned(0,32);
  signal ram_rdata : unsigned(31 downto 0) := to_unsigned(0,32);
  signal ram_reading : std_logic := '0';
  signal ram_bytes : integer range 0 to 4 := 0;

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

  -- These three must be off for reliable operation on current PCBs
  signal fast_cmd_mode : std_logic := '0';
  signal fast_read_mode : std_logic := '0';
  signal fast_write_mode : std_logic := '0';

  signal read_phase_shift : std_logic := '0';
  signal write_phase_shift : std_logic := '1';
  
  signal countdown : integer range 0 to 63 := 0;
  signal countdown_is_zero : std_logic := '1';
  signal extra_latency : std_logic := '0';
  signal countdown_timeout : std_logic := '0';

  signal pause_phase : std_logic := '0';
  signal hr_clock : std_logic := '0';

  signal data_ready_toggle : std_logic := '0';
  signal last_data_ready_toggle : std_logic := '0';

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
    
  signal last_rwds : std_logic := '0';

  signal hr_rwds_high_seen : std_logic := '0';

  signal random_bits : unsigned(7 downto 0) := x"00";

  signal write_blocked : std_logic := '0';
  
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
  
begin
  process (clock163,clock325,hr_clk,hr_clk_phaseshift) is
    variable clock_status_vector : unsigned(4 downto 0);
    variable tempaddr : unsigned(26 downto 0);
  begin
    -- Optionally delay HR_CLK by 1/2 an 160MHz clock cycle
    -- (actually just by optionally inverting it)
    if rising_edge(clock325) then
      
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
      
      if in_simulation = true then
        write_latency2 <= to_unsigned(5,8);
        extra_write_latency2 <= to_unsigned(3,8);
      end if;        
      
      -- Ignore read requests to the current block read, as they get
      -- short-circuited in the inner state machine to save time.
      report "address = $" & to_hstring(transaction_address);

      hr_clock_phase165 <= hr_clock_phase165 + 1;

      cycle_count <= cycle_count + 1;
            
      hyperram_access_address_read_time_adjusted <= to_unsigned(to_integer(hyperram_access_address(2 downto 0))+read_time_adjust,6);
      seven_plus_read_time_adjust <= to_unsigned(7 + read_time_adjust,6);
       
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

      if start_delay_expired='0' then
        start_delay_counter <= start_delay_counter - 1;
        if start_delay_counter = 0 then
          start_delay_expired <= '1';
          state <= WriteSetup;
        end if;
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
          hr_rwds <= 'Z';
          hr2_rwds <= 'Z';
          
          first_transaction <= '0';
          
          -- All commands need the clock offset by 1/2 cycle
          hr_clk_phaseshift <= write_phase_shift;
          hr_clk_fast <= '1';
          
          pause_phase <= '0';
          countdown_timeout <= '0';          
          
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

          -- Release CS line between transactions
          report "Releasing hyperram CS lines";
          hr_cs0 <= '1';
          hr_cs1 <= '1';
          busy <= '0';
          data_ready_strobe <= '0';

          -- Latch incoming address
          ram_address <= transaction_address;
          ram_bytes <= transaction_byte_count;
          ram_wdata <= transaction_wdata;
          
          -- Phase 101 guarantees that the clock base change will happen
          -- within the coming clock cycle
          if rwr_waiting='0' and  hr_clock_phase165 = "10" then
            if read_request = '1' then
              report "Waiting to start read";
              state <= ReadSetup;
              report "Accepting job";
              busy <= '1';
              ram_reading <= '1';
            elsif write_request = '1' then
              report "Waiting to start write";
              report "Setting state to WriteSetup. random_bits=" & to_hstring(random_bits);
              state <= WriteSetup;
              report "Accepting job";
              busy <= '1';
              ram_reading <= '0';
            else
              busy <= '0';
            end if;
          end if;
          
        when ReadSetup =>
          report "Setting up to read $" & to_hstring(ram_address) & " ( trans_address = $" & to_hstring(transaction_address) & ")";

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
            -- Select the correct memory word
            hr_command(2 downto 0) <= ram_address(3 downto 1);
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

          state <= HyperRAMOutputCommandSlow;
          hr_clk_fast <= '0';
          hr_clk_phaseshift <= write_phase_shift;
          
          countdown <= 6;
          config_reg_write <= '0';
          countdown_is_zero <= '0';
          
        when WriteSetup =>

          report "Preparing hr_command etc for write to $" & to_hstring(ram_address);

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
            state <= HyperRAMOutputCommandSlow;
            hr_clk_fast <= '0';
            hr_clk_phaseshift <= write_phase_shift;
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

          pause_phase <= not pause_phase;

          if pause_phase='1' then
            hr_clk_phaseshift <= write_phase_shift;

            if countdown_timeout='1' then
              -- Finished shifting out
              if ram_reading = '1' then
                -- Reading: We can just wait until hr_rwds has gone low, and then
                -- goes high again to indicate the first data byte
                countdown <= 63;
                countdown_is_zero <= '0';
                hr_rwds_high_seen <= '0';
                countdown_timeout <= '0';

                pause_phase <= '1';
                hr_clk_fast <= '0';
                state <= HyperRAMReadWaitSlow;
              elsif config_reg_write='1' and ram_reading='0' then
                -- Config register write.
                -- These are a bit weird, as they have no latency, and all 16
                -- bits have to get written at once.  So we will have 2 buffer
                -- registers that get setup, and then ANY write to the register
                -- area will write those values, which we have done by shifting
                -- those through and sending 48+16 bits instead of the usual
                -- 48.                  

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
                
                countdown_timeout <= '0';

                hr_clk_fast <= '0';
                state <= HyperRAMDoWriteSlow;
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
            if config_reg_write='1' and ram_reading='0' then
              report "shifting in conf value $" & to_hstring(conf_buf0);
              hr_command(7 downto 0) <= conf_buf0;
              conf_buf0 <= conf_buf1;
              conf_buf1 <= conf_buf0;
            else
              hr_command(7 downto 0) <= x"00";
            end if;
            
            report "Writing command byte $" & to_hstring(hr_command(47 downto 40));
            
            if countdown = 3 and (config_reg_write='0' or ram_reading='1') then
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
        when HyperRAMDoWriteSlow =>
          pause_phase <= not pause_phase;
                                                    
          if pause_phase = '1' then
            hr_clk_phaseshift <= write_phase_shift;
            if countdown_timeout = '1' then
              report "Advancing to HyperRAMFinishWriting";
              state <= HyperRAMFinishWriting;                    
            end if;
          else
                      
            report "latency countdown = " & integer'image(countdown);

            -- Begin write mask pre-amble
            if ram_reading = '0' and countdown = 2 then
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
                
                report "Presenting hr_d with ram_wdata";

                ram_wdata(23 downto 0) <= ram_wdata(31 downto 8);
                hr_d <= ram_wdata(7 downto 0);
                hr2_d <= ram_wdata(7 downto 0);
                hr_rwds <= '0';
                hr2_rwds <= '0';

                ram_bytes <= ram_bytes - 1;
                if ram_bytes = 1 then
                  state <= HyperRAMFinishWriting;
                end if;
              end if;
            end if;
          end if;
        when HyperRAMFinishWriting =>
          -- Mask writing from here on.
          hr_cs0 <= '1';
          hr_cs1 <= '1';
          hr_rwds <= '1';
          hr2_rwds <= '1';
          hr_d <= x"FA"; -- "after" data byte
          hr2_d <= x"FA"; -- "after" data byte
          hr_clk_phaseshift <= write_phase_shift;         
          report "clk_queue <= '00'";
          rwr_counter <= rwr_delay;
          rwr_waiting <= '1';
          report "returning to idle";
          state <= Idle;
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
              transaction_rdata <= x"DEADBEEF";
              report "asserting data_ready_strobe";
              data_ready_strobe <= '1';
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

              if hyperram0_select = '1' then
                ram_rdata(to_integer(byte_phase)*8+7 downto to_integer(byte_phase)*8) <= hr_d;
              else
                ram_rdata(to_integer(byte_phase)*8+7 downto to_integer(byte_phase)*8) <= hr2_d;
              end if;
              
              ram_bytes <= ram_bytes - 1;
              if ram_bytes = 1 then
                rwr_counter <= rwr_delay;
                rwr_waiting <= '1';
                report "returning to idle";
                state <= HyperRAMExportReadData;
                hr_cs0 <= '1';
                hr_cs1 <= '1';
                hr_clk_phaseshift <= write_phase_shift;
              else
                byte_phase <= byte_phase + 1;
              end if;
            end if;
          end if;
        when HyperRAMExportReadData =>
          transaction_rdata <= ram_rdata;
          data_ready_strobe <= '1';
          busy <= '0';
      end case;      
    end if;
  
  end process;
end gothic;


