--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2018
--
-- *  This program is free software; you can redistribute it and/or modify
-- *  it under the terms of the GNU Lesser General Public License as
-- *  published by the Free Software Foundation; either version 3 of the
-- *  License, or (at your option) any later version.
-- *
-- *  This program is distributed in the hope that it will be useful,
-- *  but WITHOUT ANY WARRANTY; without even the implied warranty of
-- *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- *  GNU General Public License for more details.
-- *
-- *  You should have received a copy of the GNU Lesser General Public License
-- *  along with this program; if not, write to the Free Software
-- *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
-- *  02111-1307  USA.

--------------------------------------------------------------------------------

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity pcm_clock is
  generic (
    clock_frequency : integer;
    sample_rate : integer := 96000
    );
  port (
    cpuclock : in std_logic;

    -- PCM audio interface
    pcm_clk : out std_logic := '0';
    pcm_sync : out std_logic := '0'
    );

end pcm_clock;

architecture brutalist of pcm_clock is

  -- Problem here is that we need a clock period of 25 cycles, which means that
  -- a half clock is 12.5 cycles, which doesn't work this way.
  -- The simple solution is to make the counter add the fractional part, and to
  -- add 2 each cycle instead of 1.
  constant pcmclock_divider : integer := clock_frequency/2000000;
  signal pcmclock_counter : integer range 0 to (pcmclock_divider + 1) := 0;

  constant samplerate_divider : integer := 2000000/sample_rate;
  signal eightkhz_counter : integer range 0 to (samplerate_divider + 1) := samplerate_divider - 2;

  signal pcm_clk_int : std_logic := '0';

  signal cycle_count : integer := 0;
  
begin

  process (cpuclock) is
  begin
    if rising_edge(cpuclock) then
      report "Cycle " & integer'image(cycle_count) & ", pcmclock_counter=" & integer'image(pcmclock_counter);
      cycle_count <= cycle_count + 1;
      
      if pcmclock_counter < (pcmclock_divider - 1) then
        pcmclock_counter <= pcmclock_counter + 2;
      else
        pcmclock_counter <= pcmclock_counter - pcmclock_divider + 2;
        if pcm_clk_int='1'  then
          report "Tick";
        else
          report "Tock";
        end if;
        
        pcm_clk <= not pcm_clk_int;
        pcm_clk_int <= not pcm_clk_int;
        
        -- Check if it is time for a new sample
        if pcm_clk_int='0' then
          if eightkhz_counter /= (samplerate_divider - 1) then
            eightkhz_counter <= eightkhz_counter + 1;
            report "PCM_SYNC clear";
            pcm_sync <= '0';
          else
            -- Time for a new sample
            eightkhz_counter <= 0;
            report "PCM_SYNC assert";            
            pcm_sync <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;
  
  
end brutalist;
