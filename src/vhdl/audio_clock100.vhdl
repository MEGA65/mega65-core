--------------------------------------------------------------------------------
-- audio_clock.vhd                                                            --
-- Audio clock (e.g. 256Fs = 12.288MHz) and enable (e.g Fs = 48kHz).          --
--------------------------------------------------------------------------------
-- (C) Copyright 2020 Adam Barnes <ambarnes@gmail.com>                        --
-- This file is part of The Tyto Project. The Tyto Project is free software:  --
-- you can redistribute it and/or modify it under the terms of the GNU Lesser --
-- General Public License as published by the Free Software Foundation,       --
-- either version 3 of the License, or (at your option) any later version.    --
-- The Tyto Project is distributed in the hope that it will be useful, but    --
-- WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public     --
-- License for more details. You should have received a copy of the GNU       --
-- Lesser General Public License along with The Tyto Project. If not, see     --
-- https://www.gnu.org/licenses/.                                             --
--------------------------------------------------------------------------------

library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity audio_clock is
    generic (
      fs      : real;     -- sampling (clken) frequency (kHz)
      ratio   : integer   -- clk to fs frequency ratio
    );
    port (

      select_44100 : in std_logic;

      clock270 : in std_logic;
      
        rsto    : out   std_logic;          -- reset out (from MMCM lock status)
        clk     : inout   std_logic;          -- audio clock out (fs * ratio)
        clken   : out   std_logic           -- audio clock enable out (fs)

    );
end entity audio_clock;

architecture synth of audio_clock is

  -- 44100*256/270MHz << 23 = 350755.662506667
  -- Error rate ~1x10^-6
  constant delta_44100 : unsigned(19 downto 0) := to_unsigned(350756,20);
  -- 48000*256/270MHz << 23 = 381774.870755556
  -- Error rate = ~4x10^-7
  constant delta_48000 : unsigned(19 downto 0) := to_unsigned(381774,20);

  -- Used to detect each tick.
  signal delta_counter : unsigned(20 downto 0) := to_unsigned(0,21);
  -- Then every 8 ticks = 1x fs*ratio clock
  signal tick_counter : unsigned(3 downto 0) := to_unsigned(0,4);

  signal last_delta_counter : std_logic := '0';
  signal last_tick_counter : std_logic := '0';
  
  signal clk_u    : std_logic;     -- unbuffered output clock

  signal ratio_counter : integer := 0;
  
  ----------------------------------------------------------------------

begin
    
    BUFG_O: unisim.vcomponents.bufg
        port map (
            I   => clk_u,
            O   => clk
        );

    process(clock270)
    begin 
      if rising_edge(clock270) then
        if select_44100 = '0' then
          -- 48KHz
          delta_counter <= delta_counter + delta_48000;
        else
          -- 44.1KHz
          delta_counter <= delta_counter + delta_44100;
        end if;
        if delta_counter(20) /= last_delta_counter then
          tick_counter <= tick_counter + 1;
          last_delta_counter <= delta_counter(20);
        end if;

        -- Clock has two phases, so use one bit lower to get
        -- two transitions per time
        clk_u <= tick_counter(2);

        -- Then from that derive the sample clock
        if ratio_counter = 0 then
          clken <= '1';
        else
          clken <= '0';          
        end if;
        if tick_counter(3) /= last_tick_counter then
          last_tick_counter <= tick_counter(3);
          if ratio = 256 then
            -- Special efficient case for convenient ratio
            ratio_counter <= to_integer(to_unsigned(ratio,8)+1);
          else
            if ratio_counter < (ratio - 1) then
              ratio_counter <= ratio_counter + 1;
            else
              ratio_counter <= 0;
            end if;
          end if;
        end if;
      end if;
    end process;
      
      
end architecture synth;
