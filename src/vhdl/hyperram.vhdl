library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity hyperram is
  Port ( pixelclock : in STD_LOGIC; -- For slow devices bus interface is
                                    -- actually on pixelclock to reduce latencies
         clock163 : in std_logic; -- Used for fast clock for HyperRAM

         latency_1x : in Unsigned(7 downto 0);
         latency_2x : in Unsigned(7 downto 0);
         
         read_request : in std_logic;
         write_request : in std_logic;
         address : in unsigned(26 downto 0);
         wdata : in unsigned(7 downto 0);
         
         rdata : out unsigned(7 downto 0);
         data_ready_strobe : out std_logic := '0';
         busy : out std_logic := '0';

         hr_d : inout unsigned(7 downto 0) := (others => 'Z'); -- Data/Address
         hr_rwds : inout std_logic := 'Z'; -- RW Data strobe
--         hr_rsto : in std_logic; -- Unknown PIN
         hr_reset : out std_logic := '1'; -- Active low RESET line to HyperRAM
--         hr_int : in std_logic; -- Interrupt?
         hr_clk_p : out std_logic := '1';
         hr_cs0 : out std_logic := '1'
         );
end hyperram;

architecture gothic of hyperram is

  type state_t is (
    Debug,
    Idle,
    ReadSetup,
    WriteSetup,
    HyperRAMCSStrobe,
    HyperRAMOutputCommand,
    HyperRAMLatencyWait,
    HyperRAMFinishWriting,
    HyperRAMReadWait
    );
  
  signal address_latched : unsigned(26 downto 0);
  signal wdata_latched : unsigned(7 downto 0);
  
  signal hr_clock : std_logic := '0';

  signal data_ready_toggle : std_logic := '0';
  signal last_data_ready_toggle : std_logic := '0';

  signal request_toggle : std_logic := '0';
  signal last_request_toggle : std_logic := '0';

  -- Used to slow down HyperRAM enough that we can watch waveforms on the JTAG
  -- boundary scanner.
  signal slowdown_counter : integer := 0;

  signal byte_phase : std_logic := '0';
  signal byte_written : std_logic := '0';

  signal debug_mode : std_logic := '0';

  signal hr_ddr : std_logic := '0';
  signal hr_reset_int : std_logic := '0';
  signal hr_rwds_int : std_logic := '0';
  signal hr_cs0_int : std_logic := '0';
  signal hr_cs1_int : std_logic := '0';
  signal hr_clk_p_int : std_logic := '0';
  signal hr_clk_n_int : std_logic := '0';

  signal cycle_count : integer := 0;
  
begin
  process (pixelclock,clock163) is
  begin
    if rising_edge(pixelclock) then
      report "read_request=" & std_logic'image(read_request) & ", busy_internal=" & std_logic'image(busy_internal)
        & ", write_request=" & std_logic'image(write_request);

      busy <= busy_internal;

      data_ready_strobe <= '0';
      
      if read_request='1' and busy_internal='0' then
        report "Making read request";
        -- Begin read request
        -- Latch address
        ram_address <= address;
        ram_reading <= '1';

        -- Allow reading from dummy debug bitbash registers at $BFFFFFx
        if address(23 downto 4) = x"FFFFF" and address(26 downto 24) = "111" then
          case address(3 downto 0) is
            when x"0" =>
              rdata <= (others => debug_mode);
            when x"1" =>
              rdata <= hr_d;
            when x"2" =>
              rdata(0) <= hr_rwds;
              rdata(1) <= hr_reset_int;
              rdata(2) <= hr_clk_n_int;
              rdata(3) <= hr_clk_p_int;
              rdata(4) <= hr_cs0_int;
              rdata(5) <= hr_cs1_int;
              rdata(6) <= hr_ddr;
              rdata(7) <= '1';
            when others =>
              -- This seems to be what gets returned all the time
              rdata <= x"42";
          end case;
          data_ready_strobe <= '1';
          report "asserting data_ready_strobe for fake read";
        else
          request_toggle <= not request_toggle;          
        end if;        
      elsif write_request='1' and busy_internal='0' then
        report "Making write request";
        -- Begin write request
        -- Latch address and data 
        ram_address <= address;
        ram_wdata <= wdata;
        ram_reading <= '0';
        null;

        if address(23 downto 4) = x"FFFFF" and address(26 downto 24) = "111" then
          case address(3 downto 0) is
            when x"0" =>
              if wdata = x"de" then
                debug_mode <= '1';
              elsif wdata = x"1d" then
                debug_mode <= '0';
              end if;
            when x"1" =>
              if hr_ddr='1' then
                hr_d <= wdata;
              else
                hr_d <= (others => 'Z');
              end if;
            when x"2" =>
              hr_rwds_int <= wdata(0);
              hr_reset_int <= wdata(1);
              hr_clk_n_int <= wdata(2);
              hr_clk_p_int <= wdata(3);
              hr_cs0_int <= wdata(4);
              hr_cs1_int <= wdata(5);

              hr_reset <= wdata(1);
              hr_clk_n <= wdata(2);
              hr_clk_p <= wdata(3);
              hr_cs0 <= wdata(4);
              hr_cs1 <= wdata(5);

              hr_ddr <= wdata(6);
              if wdata(6)='0' then
                hr_d <= (others => '0');
              end if;
            when others =>
              null;
          end case;
          data_ready_strobe <= '1';
        else
          request_toggle <= not request_toggle;          
        end if;        
      else
        -- Nothing new to do
        if data_ready_toggle /= last_data_ready_toggle then
          last_data_ready_toggle <= data_ready_toggle;
          data_ready_strobe <= '1';
        end if;
      end if;

    end if;
    if rising_edge(clock163) then

      cycle_count <= cycle_count + 1;
      
      -- HyperRAM state machine
      report "State = " & state_t'image(state) & " @ Cycle " & integer'image(cycle_count);
      
      if (state /= Idle) and ( slowdown_counter /= 0) then
        slowdown_counter <= slowdown_counter - 1;
      else
--        slowdown_counter <= 100;
        slowdown_counter <= 0;
        
        case state is
          when Debug =>
            if debug_mode='0' then
              state <= Idle;
            end if;

            hr_rwds <= hr_rwds_int;
            hr_reset <= hr_reset_int;
            
          when Idle =>
            -- Mark us ready for a new job, or pick up a new job
            if debug_mode='1' then
              state <= Debug;
            end if;
            if request_toggle /= last_request_toggle then
              last_request_toggle <= request_toggle;
              if ram_reading = '1' then
                state <= ReadSetup;
              else
                report "Setting state to WriteSetup";
                state <= WriteSetup;
              end if;
              busy_internal <= '1';
              report "Accepting job";
            else
              report "Clearing busy_internal";
              busy_internal <= '0';
            end IF;
            -- Release CS line between transactions
            hr_cs0 <= '1';
            hr_cs1 <= '1';

            -- Clock must be low when idle, so that it is in correct phase
            -- when CS0 is pulled low to trigger a transaction
            hr_clk_p <= '0';
            
            -- Put recogniseable patter on data lines for debugging
            report "setting hr_d to $A5";
            hr_d <= x"A5";
          when ReadSetup =>
            -- Prepare command vector
            hr_command(47) <= '1'; -- READ
            -- Map actual RAM to bottom 32MB of 64MB space (repeated 4x)
            -- and registers to upper 32MB
--            hr_command(46) <= '1'; -- Memory address space (1) / Register
            hr_command(46) <= not ram_address(26); -- Memory address space (1) / Register
                                               -- address space select (0) ?
            hr_command(45) <= '1'; -- Linear access (not wrapped)
            hr_command(44 downto 37) <= (others => '0'); -- unused upper address bits
            hr_command(34 downto 16) <= ram_address(22 downto 4);
            hr_command(15 downto 3) <= (others => '0'); -- reserved bits
            hr_command(2 downto 0) <= ram_address(3 downto 1);

            -- Call HyperRAM to attention (Each 8MB half has a separate CS line,
            -- so we gate them on address line 23 = 8MB point)
            hr_cs0 <= ram_address(23);
            hr_cs1 <= not ram_address(23);
            
            hr_reset <= '1'; -- active low reset
            countdown <= 6;

            state <= HyperRAMCSStrobe;
            
          when WriteSetup =>

            report "Preparing hr_command etc";
            
            -- Prepare command vector
            -- As HyperRAM addresses on 16bit boundaries, we shift the address
            -- down one bit.
            hr_command(47) <= '0'; -- WRITE
            hr_command(46) <= not ram_address(26); -- Allow access to HyperRAM
                                                   -- registers as well as memory.
            hr_command(45) <= '1'; -- Linear access (not wrapped)
            hr_command(44 downto 35) <= (others => '0'); -- unused upper address bits
            hr_command(34 downto 16) <= ram_address(22 downto 4);
            hr_command(15 downto 3) <= (others => '0'); -- reserved bits
            hr_command(2 downto 0) <= ram_address(3 downto 1);

            hr_reset <= '1'; -- active low reset
            countdown <= 6;

            state <= HyperRAMCSStrobe;

          when HyperRAMCSStrobe =>

            report "Counting down CS strobe: COMMAND = $" & to_hstring(hr_command);
            
            if countdown /= 0 then
              countdown <= countdown - 1;
            else
              state <= HyperRAMOutputCommand;
              countdown <= 6; -- 48 bits = 6 x 8 bits
            end if;

          when HyperRAMOutputCommand =>
            report "Writing command";
            -- Call HyperRAM to attention
            hr_cs0 <= ram_address(23);
            hr_cs1 <= not ram_address(23);
            
            hr_rwds <= 'Z';
            next_is_data <= not next_is_data;
            if next_is_data = '0' then
              -- Toggle clock while data steady
              hr_clk_n <= not hr_clock;
              hr_clk_p <= hr_clock;
              hr_clock <= not hr_clock;
            else
              -- Toggle data while clock steady
              hr_d <= hr_command(47 downto 40);
              hr_command(47 downto 8) <= hr_command(39 downto 0);
              report "Writing command byte $" & to_hstring(hr_command(47 downto 40));

              if countdown = 3 then
                extra_latency <= hr_rwds;
              end if;
              if countdown /= 0 then
                countdown <= countdown - 1;
              else
                -- Finished shifting out
                if ram_reading = '1' then
                  -- Reading: We can just wait until hr_rwds has gone low, and then
                  -- goes high again to indicate the first data byte
                  countdown <= 99;
                  state <= HyperRAMReadWait;
                else
                  -- Writing, so count down the correct number of cycles;
                  -- Initial latency is reduced by 2 cycles for the last bytes
                  -- of the access command, and by 1 more to cover state
                  -- machine latency
                  countdown <= 8 - 2 - 1;
                  state <= HyperRAMLatencyWait;
                end if;
              end if;
            end if;
            byte_phase <= '0';
            byte_written <= '0';
          when HyperRAMLatencyWait =>
            next_is_data <= not next_is_data;
            if next_is_data = '0' then
              -- Toggle clock while data steady
              hr_clk_n <= not hr_clock;
              hr_clk_p <= hr_clock;
              hr_clock <= not hr_clock;
            else
              report "latency countdown = " & integer'image(countdown);
              if countdown /= 0 then
                report "tri-stating RWDS";
                hr_rwds <= 'Z';
                countdown <= countdown - 1;
              else
                if extra_latency='1' then
                  -- If we were asked to wait for extra latency,
                  -- then wait another 6 cycles.
                  extra_latency <= '0';
                  countdown <= 6;
                  -- Also begin driving RWDS low when CLK low one
                  -- cycle before actually starting to write.
                  report "Pulling RWDS low ahead of writing.";
                  hr_rwds <= '0';
                else
                  -- Latency countdown for writing is over, we can now
                  -- begin writing bytes.                  

                  -- HyperRAM works on 16-bit fundamental transfers.
                  -- This means we need to have two half-cycles, and pick which
                  -- one we want to write during.
                  -- If RWDS is asserted, then the write is masked, i.e., won't
                  -- occur.
                  -- In this first 
                  
                  -- Write byte
                  if byte_phase = '0' then
                    -- Even byte
                    if ram_address(0) = '0' then
                      report "Clearing write mask for even address";
                      hr_rwds <= '0';
                      byte_written <= '1';
                    else
                      hr_rwds <= '1';
                    end if;
                  else
                    -- Odd byte
                    if ram_address(0) = '1' then
                      report "Clearing write mask for odd address";
                      hr_rwds <= '0';
                      byte_written <= '1';
                    else
                      hr_rwds <= '1';
                    end if;
                    -- We finish after (possibly) writing the odd byte
                  end if;
                  byte_phase <= '1';

                  report "setting hr_d to ram_wdata";
                  hr_d <= ram_wdata;
                end if;
              end if;
            end if;
            if byte_written = '1' and next_is_data='0' then
              report "Advancing to HyperRAMFinishWriting";
              state <= HyperRAMFinishWriting;
            end if;
          when HyperRAMFinishWriting =>
            -- Last cycle was data, so next cycle is clock.

            -- Indicate no more bytes to write
            hr_rwds <= 'Z';
            hr_cs0 <= '1';

            -- Toggle clock
            hr_clk_n <= not hr_clock;
            hr_clk_p <= hr_clock;
            hr_clock <= not hr_clock;

            -- Go back to waiting
            state <= Idle;
          when HyperRAMReadWait =>
            hr_rwds <= 'Z';
            hr_d <= (others => 'Z');                       
            if countdown = 0 then
              -- Timed out waiting for read -- so return anyway, rather
              -- than locking the machine hard forever.
              rdata <= x"DD";
              rdata(0) <= data_ready_toggle;
              rdata(1) <= busy_internal;
              data_ready_strobe <= '1';
              data_ready_toggle <= not data_ready_toggle;
              state <= Idle;
            else
              countdown <= countdown - 1;
            end if;
            next_is_data <= not next_is_data;
            if next_is_data = '0' then
              -- Toggle clock while data steady
              hr_clk_n <= not hr_clock;
              hr_clk_p <= hr_clock;
              hr_clock <= not hr_clock;
            else
              if hr_rwds = '1' then
                -- Data has arrived: Latch either odd or even byte
                -- as required.
                report "Saw read data = $" & to_hstring(hr_d);
                if byte_phase = ram_address(0) then
                  report "Latching read data = $" & to_hstring(hr_d);
                  rdata <= hr_d;
                  data_ready_toggle <= not data_ready_toggle;
                  state <= Idle;
                end if;
                byte_phase <= '1';
              end if;
            end if;
          when others =>
            state <= Idle;
        end case;      
      end if;
    end if;
    
  end process;
end gothic;


