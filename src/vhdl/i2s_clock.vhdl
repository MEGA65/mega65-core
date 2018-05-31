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

entity i2s_clock is
  generic (
    sample_rate : integer := 8000
    );
  port (
    clock50mhz : in std_logic;

    -- I2S PCM audio interface
    i2s_clk : out std_logic := '0';
    i2s_sync : out std_logic := '0'
    );

end i2s_clock;

architecture brutalist of i2s_clock is

  -- How many clock ticks per half I2S clock tick
  constant clockdivider : integer := 25000000/2000000;
  signal pcmclock_counter : integer range 0 to (clockdivider - 1) := 0;

  -- How many I2S clock ticks per half sample rate
  constant sampleratedivider : integer := 1000000/sample_rate;
  signal eightkhz_counter : integer range 0 to (sampleratedivider - 1) := 0;

  signal i2s_clk_int : std_logic := '0';
  signal i2s_sync_int : std_logic := '0';
  
begin

  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then
      if pcmclock_counter /= (clockdivider - 1) then
        pcmclock_counter <= pcmclock_counter + 1;
      else
        pcmclock_counter <= 0;

        i2s_clk <= not i2s_clk_int;
        i2s_clk_int <= not i2s_clk_int;
        
        -- Check if it is time for a new sample
        if eightkhz_counter /= (sampleratedivider - 1) then
          eightkhz_counter <= eightkhz_counter + 1;
        else
          -- Time for a new sample
          eightkhz_counter <= 0;

          i2s_sync <= not i2s_sync_int;
          i2s_sync_int <= not i2s_sync_int;

        end if;
      end if;
    end if;
  end process;
  
  
end brutalist;
