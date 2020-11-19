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
    clock_frequency : integer;
    sample_rate : integer := 8000
    );
  port (
    cpuclock : in std_logic;

    -- I2S PCM audio interface
    i2s_clk : out std_logic := '0';
    i2s_sync : out std_logic := '0'
    );

end i2s_clock;

architecture brutalist of i2s_clock is

  -- How many I2S clock ticks per half sample rate
--  constant sampleratedivider : integer := 25000000/sample_rate;
  -- SSM2518 requires certain fixed values here, so pick the fastest one
  -- of 64 clocks per sample = 32 clocks per half-sample
  -- MCLK must be between ~2 and 6MHz for this mode, so we need to divide the 50MHz
  -- clock by 10.  The loop divides by 2 implicitly, so we need 5 cycles per
  -- clock phase.
  -- This is not accurate enough. We need to instead accumulate so that we can
  -- get to the 6.144MHz ideal I2S master clock to a high level of precision.
  -- 32-bit counter using overflow to be 6.144MHz clock, we need to add:
  -- 2^32 / (clock_frequency / 6.144MHz )
  -- each cycle.  i.e.:
  -- 2^32 x 6,144,000 / clock_frequency
  -- VHDL arithmetic is 32-bit only, which is a pain, for this.
  -- We can divide both sides by 100KHz to get:
  -- 2^32 x 61.44 / (clock_frequency / 100KHz)
  -- But we still have the problem of overflow on the left side, so lets reduce
  -- precision to 24 bits:
  -- 2^24 x 61.44 / (clock_frequency / 100KHz)
  -- = 1,030,792,151.04 / (clock_frequency / 100KHz)
  -- This results in a jittery clock, though, which is sub-optimal.
  -- Thus we should stick to a constant interval.
  -- For now we will achieve this 
  
  constant clock_frequency_100khz : integer := clock_frequency / 100000;
--  constant big_num : integer := 1030792151;
--  constant accumulator_value : integer := big_num / clock_frequency_100khz;
  -- Yields 4.86MHz, but with zero jitter
  constant accumulator_value : integer := 32768;
  
  signal accumulator : unsigned(24 downto 0) := to_unsigned(0,25);
  signal last_accumulate_bit : std_logic := '0';
  
  constant sampleratedivider : integer := 64;
  signal sample_counter : integer range 0 to (sampleratedivider - 1) := 0;

  signal i2s_clk_int : std_logic := '0';
  signal i2s_sync_int : std_logic := '0';

  
begin

  process (cpuclock) is
  begin
    if rising_edge(cpuclock) then
      accumulator <= accumulator + accumulator_value;
      if accumulator(23) /= last_accumulate_bit then
        last_accumulate_bit <= accumulator(23);

        i2s_clk <= not i2s_clk_int;
        i2s_clk_int <= not i2s_clk_int;
        
        -- Check if it is time for a new sample
        if sample_counter /= (sampleratedivider - 1) then
          sample_counter <= sample_counter + 1;
        else
          -- Time for a new sample
          sample_counter <= 0;

          i2s_sync <= not i2s_sync_int;
          i2s_sync_int <= not i2s_sync_int;
        end if;
      end if;
    end if;
  end process;
  
  
end brutalist;
