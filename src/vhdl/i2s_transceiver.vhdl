--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2018
--
-- Used the following as reference:
-- https://www.sparkfun.com/datasheets/BreakoutBoards/I2SBUS.pdf
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

entity i2s_transceiver is
  generic ( clock_frequency : integer );
  port (
    cpuclock : in std_logic;

    -- I2S clock and sync signals
    i2s_clk : in std_logic;
    i2s_sync : in std_logic;

    -- PCM audio interface
    pcm_out : out std_logic := '0';
    pcm_in : in std_logic;

    -- sample to send
    tx_sample_left : in signed(15 downto 0);
    tx_sample_right : in signed(15 downto 0);

    -- last sample received
    rx_sample_left : out signed(15 downto 0) := (others => '0');
    rx_sample_right : out signed(15 downto 0) := (others => '0')

    );

end i2s_transceiver;

architecture brutalist of i2s_transceiver is

  signal bit_number : integer range 0 to 16 := 0;
  signal rxbuffer_left : std_logic_vector(15 downto 0) := (others => '0');
  signal rxbuffer_right : std_logic_vector(15 downto 0) := (others => '0');
  signal txbuffer_left : std_logic_vector(15 downto 0) := (others => '0');
  signal txbuffer_right : std_logic_vector(15 downto 0) := (others => '0');

  signal last_clk : std_logic := '0';
  signal last_sync : std_logic := '0';
  
begin

  process (cpuclock) is
  begin
    if rising_edge(cpuclock) then

      last_clk <= i2s_clk;

      if i2s_clk='1' and last_clk='0' then

        -- Receive next bit of input
        if bit_number /= 0 then
          bit_number <= bit_number - 1;
          -- SYNC signal indicates left/right select
          if last_sync='0' then
            rxbuffer_left(15 downto 1) <= rxbuffer_left(14 downto 0);
            rxbuffer_left(0) <= pcm_in;
          else
            rxbuffer_right(15 downto 1) <= rxbuffer_right(14 downto 0);
            rxbuffer_right(0) <= pcm_in;
          end if;
        end if;      
        
        -- Present next bit
        -- (If there are more bits than we have, we end up just shifting
        -- out zeroes, in accordance with the spec).
        if last_sync='0' then
          pcm_out <= txbuffer_left(15);
          txbuffer_left(15 downto 1) <= txbuffer_left(14 downto 0);
          txbuffer_left(0) <= '0';
        else
          pcm_out <= txbuffer_right(15);
          txbuffer_right(15 downto 1) <= txbuffer_right(14 downto 0);
          txbuffer_right(0) <= '0';
        end if;

        -- Check if it is time for a new sample
        last_sync <= i2s_sync;
        if (last_sync /= i2s_sync) then
          -- Time for a new sample
          txbuffer_left <= std_logic_vector(tx_sample_left);
          txbuffer_right <= std_logic_vector(tx_sample_right);
          bit_number <= 15;
        end if;
      end if;
    end if;
  end process;
  
  
end brutalist;
