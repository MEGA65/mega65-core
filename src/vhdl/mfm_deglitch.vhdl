-- Floppy drives can sometimes emit read glitches. These take the form of
-- brief inversions of the measured magnetism, which cause pairs of closely
-- spaced RDATA pulses, one at the start and one at the end of the inversion
-- in read flux.
--
-- When detected, these can be removed by merging the gap before, during and
-- immediately following the short gap that is the symptom of the brief
-- inversion.
--
-- This module is designed to detect these with controllable threshold, and
-- to remove them from the stream of gaps.

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity mfm_deglitch is
  generic ( unit_id : integer);
  port (
    clock40mhz : in std_logic;

    cycles_per_interval : in unsigned(7 downto 0);
    
    gap_in : in unsigned(15 downto 0);
    gap_strobe_in : in std_logic := '0';

    gap_out : out unsigned(15 downto 0);
    gap_strobe_out : out std_logic := '0'
    );

end mfm_deglitch;

architecture faux_brutalist of mfm_deglitch is

  signal gap_count : integer range 0 to 3 := 0;
  signal gap_1 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_2 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_3 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal max_glitch_len : unsigned(15 downto 0) := to_unsigned(0,16);

begin

  process(clock40mhz) is

    -- Consider anything < 50% of minimum gap length as a glitch
    max_glitch_len(15 downto 7) <= (others => '0');
    max_glitch_len(6 downto 0) <= cycles_per_interval(7 downto 1);
    
    gap_strobe_out <= '0';
    if gap_strobe_in='1' then
      if gap_count < 3 then
        gap_1 <= gap_in;
        gap_2 <= gap_1;
        gap_3 <= gap_2;
        gap_count <= gap_count + 1;
      end if;
    elsif gap_count = 3 then
      if gap_2 <= max_glitch_len then
        -- middle of 3 gaps is short enough to be a glitch.
        -- Thus we expect it to be an erroneous inversion, so we
        -- need to merge it with the gaps before and after it.
        gap_out <= gap_1 + gap_2 + gap_3;
        gap_strobe_out <= '1';
        gap_count <= 0;
      else
        -- No glitchy gaps, so shift out the oldest one
        gap_2 <= gap_1;
        gap_3 <= gap_2;
        gap_out <= gap_3;
        gap_strobe_out <= '1';
        gap_count <= 2;
      end if;
    end if;    
  end process;  
  
end faux_brutalist;
    
