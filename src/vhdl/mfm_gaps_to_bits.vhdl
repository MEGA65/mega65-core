
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity mfm_gaps_to_bits is
  port (
    clock40mhz : in std_logic;

    -- Quantised gaps as input
    gap_valid : in std_logic := '0';
    gap_size : in unsigned(1 downto 0);

    -- Output bits as we decode them
    bit_valid : out std_logic := '0';
    bit_out : out std_logic := '0';

    -- Indicate when we have detected a sync byte
    sync_out : out std_logic := '0'
    
    );
end mfm_gaps_to_bits;

architecture behavioural of mfm_gaps_to_bits is

  signal last_bit : std_logic := '0';

  signal check_sync : std_logic := '0';
  
  -- Used for detecting sync bytes
  signal recent_gaps : unsigned(7 downto 0) := (others => '0');
  -- Sync byte is gaps of 2.0,1.5,2.0,1.5 = 10 01 10 01 as quantised gaps
  constant sync_gaps : unsigned(7 downto 0) := "10011001";

  signal bit_queue : std_logic_vector(1 downto 0) := "00";
  signal bits_queued : integer range 0 to 2 := 0;

  signal last_gap_valid : std_logic := '0';
  
begin

  process (clock40mhz) is
    variable state : unsigned(2 downto 0) := "000";
  begin
    if rising_edge(clock40mhz) then
      last_gap_valid <= gap_valid;
      if gap_valid = '1' and last_gap_valid='0' then
--        report "Interval of %" & to_string(std_logic_vector(gap_size));
        
        -- Detect sync byte
        recent_gaps(7 downto 2) <= recent_gaps(5 downto 0);
        recent_gaps(1 downto 0) <= gap_size;
        check_sync <= '1';

        -- Process gap to produce bits
        state(2) := last_bit;
        state(1 downto 0) := gap_size;
        case state is
          when "000" =>
            -- Last was 0, length = 1.0, output 0
            bit_queue <= "00";
            bits_queued <= 1;
          when "100" =>
            -- Last was 1, length = 1.0, output 1
            bit_queue <= "11";
            bits_queued <= 1;
          when "001" =>
            -- Last was 0, length = 1.5, output 1
            bit_queue <= "11";
            bits_queued <= 1;
          when "101" =>
            -- Last was 1, length = 1.5, output 00
            bit_queue <= "00";
            bits_queued <= 2;
          when "010" =>
            -- Last was 0, length = 2.0, output 01
            bit_queue <= "01";
            bits_queued <= 2;
          when "110" =>
            -- Last was 1, length = 2.0, output 01
            bit_queue <= "01";
            bits_queued <= 2;
          when others =>
            bits_queued <= 0;
        end case;        
      else
        check_sync <= '0';
      end if;

      -- Output bits or sync
      if (check_sync='1') and (recent_gaps = sync_gaps) then
        -- Output sync mark
        sync_out <= '1';
        bits_queued <= 0;
        bit_valid <= '0';
        last_bit <= '1';  -- because sync marks are $A1
      elsif bits_queued /= 0 then
        -- Output queued bit
        bit_valid <= '1';
        bit_out <= bit_queue(1);
        last_bit <= bit_queue(1);
        bit_queue(1) <= bit_queue(0);
        bits_queued <= bits_queued -1;
      else
        sync_out <= '0';
        bit_valid <= '0';
      end if;
      
    end if;    
  end process;
end behavioural;

