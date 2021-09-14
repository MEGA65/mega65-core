
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity rll27_gaps_to_bits is
  port (
    clock40mhz : in std_logic;

    -- Quantised gaps as input
    gap_valid : in std_logic := '0';
    gap_size : in unsigned(2 downto 0);

    -- Output bits as we decode them
    bit_valid : out std_logic := '0';
    bit_out : out std_logic := '0';

    -- Indicate when we have detected a sync byte
    sync_out : out std_logic := '0'
    
    );
end rll27_gaps_to_bits;

architecture behavioural of rll27_gaps_to_bits is

  signal last_bit : std_logic := '0';

  signal check_sync : std_logic := '0';
  
  -- Used for detecting sync bytes
  signal recent_gaps : unsigned(5 downto 0) := (others => '0');
  -- Sync byte is gaps of 7 2 X = 111 010
  constant sync_gaps : unsigned(5 downto 0) := "111010";

  signal gap_bits_remaining : integer range 0 to 8 := 0;
  signal q_bits : std_logic_vector(15 downto 0) := (others => '0');
  signal last_q_bits : std_logic_vector(15 downto 0) := (others => '0');
  signal q_bit_count : integer range 0 to 16 := 0;
  
  signal bit_queue : std_logic_vector(5 downto 0) := "000000";
  signal bits_queued : integer range 0 to 6 := 0;

  signal last_gap_valid : std_logic := '0';

  signal skip_bits : integer range 0 to 2 := 0;
  
begin

  process (clock40mhz) is
  begin
    if rising_edge(clock40mhz) then
      last_gap_valid <= gap_valid;
      if gap_valid = '1' and last_gap_valid='0' then
        report "RLLDECODE: Interval of %" & to_string(std_logic_vector(gap_size))
          & " (" & integer'image(to_integer(gap_size)) & ")";
        
        -- Detect sync byte
        recent_gaps(5 downto 3) <= recent_gaps(2 downto 0);
        recent_gaps(2 downto 0) <= gap_size;
        check_sync <= '1';

        -- Process gap to produce bits
        gap_bits_remaining <= to_integer(gap_size) + 1;
      else
        check_sync <= '0';

        -- Turn gap back into a bit sequence queued for decoding
        if gap_bits_remaining > 0 then
          gap_bits_remaining <= gap_bits_remaining - 1;
        end if;
        if gap_bits_remaining > 1 then
          if skip_bits > 0 then
            skip_bits <= skip_bits - 1;
          else 
            q_bits(q_bit_count) <= '0';
            q_bit_count <= q_bit_count + 1;
          end if;
        elsif gap_bits_remaining = 1 then
          if skip_bits > 0 then
            skip_bits <= skip_bits - 1;
          else 
            q_bits(q_bit_count) <= '1';
            q_bit_count <= q_bit_count + 1;
          end if;
        end if;
        
      end if;

      if q_bits /= last_q_bits then
        report "q_bits = " & to_string(q_bits) & ", (" & integer'image(q_bit_count) & " queued.)";
        last_q_bits <= q_bits;
      end if;

      if gap_bits_remaining = 0 then
        -- Decode RLL prefixes
        -- NOTE: Bit order is reversed because q_bits is high downto low
        if (q_bit_count>3) and q_bits(3 downto 0) = "0001" then
          report "RLLDECODE: Emitting bits '11'";
          bit_queue(1 downto 0) <= "11";
          bits_queued <= 2;
          q_bit_count <= q_bit_count - 4;
          q_bits(11 downto 0) <= q_bits(15 downto 4);
        elsif (q_bit_count>3) and q_bits(3 downto 0) = "0010" then
          report "RLLDECODE: Emitting bits '10'";
          bit_queue(1 downto 0) <= "01";
          bits_queued <= 2;
          q_bit_count <= q_bit_count - 4;
          q_bits(11 downto 0) <= q_bits(15 downto 4);
        elsif (q_bit_count>5) and q_bits(5 downto 0) = "001001" then
          report "RLLDECODE: Emitting bits '000'";
          bit_queue(2 downto 0) <= "000";
          bits_queued <= 3;
          q_bit_count <= q_bit_count - 6;
          q_bits(9 downto 0) <= q_bits(15 downto 6);
        elsif (q_bit_count>5) and q_bits(5 downto 0) = "001000" then
          report "RLLDECODE: Emitting bits '010'";
          bit_queue(2 downto 0) <= "010";
          bits_queued <= 3;
          q_bit_count <= q_bit_count - 6;
          q_bits(9 downto 0) <= q_bits(15 downto 6);
        elsif (q_bit_count>5) and q_bits(5 downto 0) = "000100" then
          report "RLLDECODE: Emitting bits '011'";
          bit_queue(2 downto 0) <= "110";
          bits_queued <= 3;
          q_bit_count <= q_bit_count - 6;
          q_bits(9 downto 0) <= q_bits(15 downto 6);
        elsif (q_bit_count>7) and q_bits(7 downto 0) = "00010000" then
          report "RLLDECODE: Emitting bits '0011'";
          bit_queue(3 downto 0) <= "1100";
          bits_queued <= 4;
          q_bit_count <= q_bit_count - 8;
          q_bits(7 downto 0) <= q_bits(15 downto 8);
        elsif (q_bit_count>7) and q_bits(7 downto 0) = "00100100" then
          report "RLLDECODE: Emitting bits '0010'";
          bit_queue(3 downto 0) <= "0100";
          bits_queued <= 4;
          q_bit_count <= q_bit_count - 8;
          q_bits(7 downto 0) <= q_bits(15 downto 8);
        end if;
      end if;
      
      -- Output bits or sync
      if (check_sync='1') and (recent_gaps = sync_gaps) then
        -- Output sync mark
        report "RLLDECODE: Sync Mark spotted";
        sync_out <= '1';
        bits_queued <= 0;
        bit_valid <= '0';
        last_bit <= '1';  -- because sync marks are $A1
        -- Then skip the two trailing 0s that follow the sync mark
        skip_bits <= 2;
        q_bit_count <= 0;
        gap_bits_remaining <= 0;
      elsif bits_queued /= 0 then
        -- Output queued bit
        bit_valid <= '1';
        bit_out <= bit_queue(0);
        last_bit <= bit_queue(0);
        bit_queue(4 downto 0) <= bit_queue(5 downto 1);
        bits_queued <= bits_queued -1;
      else
        sync_out <= '0';
        bit_valid <= '0';
      end if;
      
    end if;    
  end process;
end behavioural;

