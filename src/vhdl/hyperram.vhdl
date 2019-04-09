library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;


-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity hyperram is
  Port ( cpuclock : in STD_LOGIC; -- For slow devices bus interface
         clock240 : in std_logic; -- Used for fast clock for HyperRAM

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
         hr_clk_n : out std_logic := '0';
         hr_clk_p : out std_logic := '1';
         hr_cs0 : out std_logic := '1';
         hr_cs1 : out std_logic := '1'
         );
end hyperram;

architecture gothic of hyperram is

  type state_t is (
    Idle,
    ReadSetup,
    WriteSetup,
    HyperRAMCSStrobe,
    HyperRAMOutputCommand,
    HyperRAMLatencyWait,
    HyperRAMFinishWriting,
    HyperRAMReadWait
    );
  
  signal state : state_t := Idle;
  signal busy_internal : std_logic := '0';
  signal hr_command : unsigned(47 downto 0);
  signal ram_address : unsigned(26 downto 0);
  signal ram_wdata : unsigned(7 downto 0);
  signal ram_reading : std_logic := '1';
  
  signal countdown : integer := 0;
  signal extra_latency : std_logic := '0';

  signal next_is_data : std_logic := '1';
  signal hr_clock : std_logic := '0';

  signal data_ready_toggle : std_logic := '0';
  signal last_data_ready_toggle : std_logic := '0';

  signal request_toggle : std_logic := '0';
  signal last_request_toggle : std_logic := '0';
  
begin
  process (cpuclock,clock240) is
  begin
    if rising_edge(cpuclock) then
      report "read_request=" & std_logic'image(read_request) & ", busy_internal=" & std_logic'image(busy_internal);

      busy <= busy_internal;
      
      data_ready_strobe <= '0';
      if read_request='1' and busy_internal='0' then
        -- Begin read request
        request_toggle <= not request_toggle;
        -- Latch address
        ram_address <= address;
        ram_reading <= '1';
        null;
      elsif write_request='1' and busy_internal='0' then
        -- Begin write request
        request_toggle <= not request_toggle;
        -- Latch address and data 
        ram_address <= address;
        ram_wdata <= wdata;
        ram_reading <= '0';
        null;
      else
        -- Nothing new to do
        if data_ready_toggle /= last_data_ready_toggle then
          last_data_ready_toggle <= data_ready_toggle;
          data_ready_strobe <= '1';
        end if;
      end if;
    end if;

    if rising_edge(clock240) then
      -- HyperRAM state machine
      report "State = " & state_t'image(state);
      case state is
        when Idle =>
          -- Mark us ready for a new job, or pick up a new job
          if request_toggle /= last_request_toggle then
            last_request_toggle <= request_toggle;
            if ram_reading = '1' then
              state <= ReadSetup;
            else
              state <= WriteSetup;
            end if;
            busy_internal <= '1';
            report "Accepting job";
          else
            report "Clearing busy_internal";
            busy_internal <= '0';
          end IF;
        when ReadSetup =>
          -- Prepare command vector
          hr_command(47) <= '1'; -- READ
          hr_command(46) <= '0'; -- Memory address space
          hr_command(45) <= '1'; -- Linear access (not wrapped)
          hr_command(44 downto 37) <= (others => '0'); -- unused upper address bits
          hr_command(36 downto 16) <= ram_address(23 downto 3);
          hr_command(15 downto 3) <= (others => '0'); -- reserved bits
          hr_command(2 downto 0) <= ram_address(2 downto 0);

          -- Call HyperRAM to attention (Each 8MB half has a separate CS line,
          -- so we gate them on address line 23 = 8MB point)
          hr_cs0 <= ram_address(23);
          hr_cs1 <= not ram_address(23);
          hr_clk_n <= '0';
          hr_clk_p <= '1';
          hr_reset <= '1'; -- active low reset
          countdown <= 6;

          state <= HyperRAMCSStrobe;
          
        when WriteSetup =>
          -- Prepare command vector
          hr_command(47) <= '0'; -- WRITE
          hr_command(46) <= '0'; -- Memory address space
          hr_command(45) <= '1'; -- Linear access (not wrapped)
          hr_command(44 downto 37) <= (others => '0'); -- unused upper address bits
          hr_command(36 downto 16) <= ram_address(23 downto 3);
          hr_command(15 downto 3) <= (others => '0'); -- reserved bits
          hr_command(2 downto 0) <= ram_address(2 downto 0);

          -- Call HyperRAM to attention
          hr_cs0 <= ram_address(23);
          hr_cs1 <= not ram_address(23);
          hr_clk_n <= '0';
          hr_clk_p <= '1';
          hr_clock <= '1';
          hr_reset <= '1'; -- active low reset
          countdown <= 6;

          state <= HyperRAMCSStrobe;

        when HyperRAMCSStrobe =>
          if countdown = 3 then
            -- Release CS line
            hr_cs0 <= '1';
            hr_cs1 <= '1';
          end if;
          if countdown /= 0 then
            countdown <= countdown - 1;
          else
            state <= HyperRAMOutputCommand;
            countdown <= 6; -- 48 bits = 6 x 8 bits
          end if;

        when HyperRAMOutputCommand =>
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
                -- Initial latency is reduced by 3 cycles for the last bytes
                -- of the access command
                countdown <= 6 - 3;
                state <= HyperRAMLatencyWait;
              end if;
            end if;
          end if;
        when HyperRAMLatencyWait =>
          hr_rwds <= 'Z';
          next_is_data <= not next_is_data;
          if next_is_data = '0' then
            -- Toggle clock while data steady
            hr_clk_n <= not hr_clock;
            hr_clk_p <= hr_clock;
            hr_clock <= not hr_clock;
          else
            if countdown /= 0 then
              countdown <= countdown - 1;
            else
              if extra_latency='1' then
                -- If we were asked to wait for extra latency,
                -- then wait another 6 cycles.
                extra_latency <= '0';
                countdown <= 6;
              else
                -- Latency countdown for writing is over, we can now
                -- begin writing bytes.
                -- XXX It is possible we will have mis-timed this by a cycle or
                -- two, in which case, we will write to the wrong address.
                -- If it is too high an address, then we are late.
                -- If it is not written at all, then we are too early.

                -- Write byte
                hr_rwds <= '1';
                hr_d <= ram_wdata;
                state <= HyperRAMFinishWriting;
              end if;
            end if;
          end if;
        when HyperRAMFinishWriting =>
          -- Last cycle was data, so next cycle is clock.

          -- Indicate no more bytes to write
          hr_rwds <= '0';

          -- Toggle clock
          hr_clk_n <= not hr_clock;
          hr_clk_p <= hr_clock;
          hr_clock <= not hr_clock;

          -- Go back to waiting
          state <= Idle;
        when HyperRAMReadWait =>
          hr_rwds <= 'Z';
          if countdown = 0 then
            -- Timed out waiting for read -- so return anyway, rather
            -- than locking the machine hard forever.
            rdata <= x"DE";
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
              -- Data has arrived
              rdata <= hr_d;
              data_ready_toggle <= not data_ready_toggle;
              state <= Idle;
            end if;
          end if;
        when others =>
          state <= Idle;
      end case;      
    end if;

  end process;
end gothic;


