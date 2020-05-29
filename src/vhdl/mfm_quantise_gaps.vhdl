
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity mfm_quantise_gaps is
  port (
    clock40mhz : in std_logic;

    cycles_per_interval : in unsigned(7 downto 0);
  
    gap_valid_in : in std_logic := '0';
    gap_length_in : in unsigned(15 downto 0) := (others => '0');
    
    gap_valid_out : out std_logic := '0';
    gap_size_out : out unsigned(1 downto 0)
    );
end mfm_quantise_gaps;

architecture behavioural of mfm_quantise_gaps is

  signal threshold_10_low : unsigned(15 downto 0) := to_unsigned(0,16);
  signal threshold_10_high : unsigned(15 downto 0) := to_unsigned(0,16);
  signal threshold_15_high : unsigned(15 downto 0) := to_unsigned(0,16);
  signal threshold_20_high : unsigned(15 downto 0) := to_unsigned(0,16);
  
begin

  process (clock40mhz) is
  begin
    if rising_edge(clock40mhz) then
      -- Calculate thresholds for 1.0, 1.5 and 2.0 interval gaps
      -- NOTE: The cycles per interval is effectively double the supplied value,
      -- so $D6A2 needs to be set to 1/2 the expected value
      threshold_10_low <= to_unsigned(to_integer(cycles_per_interval(7 downto 0)),16);  -- 0.5 intervals
      threshold_10_high <= to_unsigned(to_integer(cycles_per_interval&'0') + to_integer(cycles_per_interval(7 downto 1)),16);
      threshold_15_high <= to_unsigned(to_integer(cycles_per_interval(7 downto 0)&"00") - to_integer(cycles_per_interval(7 downto 1)),16);
      threshold_20_high <= to_unsigned(to_integer(cycles_per_interval(7 downto 0)&"00") + to_integer(cycles_per_interval(7 downto 0)),16);

      -- See which category the incoming gap fits
      if gap_valid_in='1' and false then
        report "Quantising gap of " & integer'image(to_integer(gap_length_in))
          & " (thresholds = "
          & integer'image(to_integer(threshold_10_low)) & ", "
          & integer'image(to_integer(threshold_10_high)) & ", "
          & integer'image(to_integer(threshold_15_high)) & ", "
          & integer'image(to_integer(threshold_20_high)) & ").";
      end if;
      if gap_length_in < threshold_10_low then
        gap_size_out <= "11"; -- invalid gap (too short)
      elsif gap_length_in <= threshold_10_high then
        gap_size_out <= "00"; -- 1.0 intervals
      elsif gap_length_in <= threshold_15_high then
        gap_size_out <= "01"; -- 1.5 intervals
      elsif gap_length_in <= threshold_20_high then
        gap_size_out <= "10"; -- 2.0 intervals
      else
        gap_size_out <= "11"; -- invalid gap (too long)
      end if;

      gap_valid_out <= gap_valid_in;
      
      -- XXX to better handle phase-errors, consider substracting deviation of
      -- previous pulse position from next gap length
      
    end if;    
  end process;
end behavioural;

