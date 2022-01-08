
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity rll27_quantise_gaps is
  port (
    clock40mhz : in std_logic;

    cycles_per_interval : in unsigned(7 downto 0);
  
    gap_valid_in : in std_logic := '0';
    gap_length_in : in unsigned(15 downto 0) := (others => '0');
    
    gap_valid_out : out std_logic := '0';
    gap_size_out : out unsigned(2 downto 0)
    );
end rll27_quantise_gaps;

architecture behavioural of rll27_quantise_gaps is

  signal threshold_2_high : unsigned(15 downto 0) := to_unsigned(0,16);
  signal threshold_3_high : unsigned(15 downto 0) := to_unsigned(0,16);
  signal threshold_4_high : unsigned(15 downto 0) := to_unsigned(0,16);
  signal threshold_5_high : unsigned(15 downto 0) := to_unsigned(0,16);
  signal threshold_6_high : unsigned(15 downto 0) := to_unsigned(0,16);
  signal threshold_7_high : unsigned(15 downto 0) := to_unsigned(0,16);
  
begin

  process (clock40mhz) is
  begin
    if rising_edge(clock40mhz) then
      -- Calculate thresholds for 2 through 7 gap intervals
      -- NOTE: The cycles per interval is effectively double the supplied value,
      -- so $D6A2 needs to be set to 1/2 the expected value
      threshold_2_high <= to_unsigned(to_integer(cycles_per_interval&'0') + to_integer(cycles_per_interval) + to_integer(cycles_per_interval(7 downto 1)),16);
      threshold_3_high <= to_unsigned(to_integer(cycles_per_interval&"00") +  to_integer(cycles_per_interval(7 downto 1)),16);
      threshold_4_high <= to_unsigned(to_integer(cycles_per_interval&"00") + to_integer(cycles_per_interval) + to_integer(cycles_per_interval(7 downto 1)),16);
      threshold_5_high <= to_unsigned(to_integer(cycles_per_interval&"00") + to_integer(cycles_per_interval&'0') + to_integer(cycles_per_interval(7 downto 1)),16);
      threshold_6_high <= to_unsigned(to_integer(cycles_per_interval&"00") + to_integer(cycles_per_interval&'0') + to_integer(cycles_per_interval) + to_integer(cycles_per_interval(7 downto 1)),16);
      threshold_7_high <= to_unsigned(to_integer(cycles_per_interval&"000") + to_integer(cycles_per_interval(7 downto 1)),16);

      -- See which category the incoming gap fits
      if gap_valid_in='1' and true then
        report "Quantising gap of " & integer'image(to_integer(gap_length_in))
          & " (thresholds = "
          & integer'image(to_integer(threshold_2_high)) & ", "
          & integer'image(to_integer(threshold_3_high)) & ", "
          & integer'image(to_integer(threshold_4_high)) & ", "
          & integer'image(to_integer(threshold_5_high)) & ", "
          & integer'image(to_integer(threshold_6_high)) & ", "
          & integer'image(to_integer(threshold_7_high)) & ").";
      end if;
      if gap_length_in <= threshold_2_high then
        gap_size_out <= "010"; -- 2 intervals
      elsif gap_length_in <= threshold_3_high then
        gap_size_out <= "011"; -- 3 intervals
      elsif gap_length_in <= threshold_4_high then
        gap_size_out <= "100"; -- 4 intervals
      elsif gap_length_in <= threshold_5_high then
        gap_size_out <= "101"; -- 5 intervals
      elsif gap_length_in <= threshold_6_high then
        gap_size_out <= "110"; -- 6 intervals
      elsif gap_length_in <= threshold_7_high then
        gap_size_out <= "111"; -- 7 intervals
      else
        gap_size_out <= "111"; -- invalid gap (too long)
      end if;

      gap_valid_out <= gap_valid_in;
      
      -- XXX to better handle phase-errors, consider substracting deviation of
      -- previous pulse position from next gap length
      
    end if;    
  end process;
end behavioural;

