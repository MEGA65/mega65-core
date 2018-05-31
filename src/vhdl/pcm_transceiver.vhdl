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

entity pcm_transceiver is
  port (
    clock50mhz : in std_logic;

    -- PCM clock and sync signals
    pcm_clk : in std_logic;
    pcm_sync : in std_logic;

    -- PCM audio interface
    pcm_out : out std_logic;
    pcm_in : in std_logic;

    -- sample to send
    tx_sample : in unsigned(15 downto 0);

    -- last sample received
    rx_sample : out unsigned(15 downto 0)

    );

end pcm_transceiver;

architecture brutalist of pcm_transceiver is

  signal bit_number : integer range 0 to 16 := 0;
  signal rxbuffer : std_logic_vector(15 downto 0) := (others => '0');
  signal txbuffer : std_logic_vector(15 downto 0) := (others => '0');

  signal last_clk : std_logic := '0';
  signal last_sync : std_logic := '0';
  
begin

  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then

      last_sync <= pcm_sync;
      last_clk <= pcm_clk;

      if pcm_clk='1' and last_clk='0' then

        -- Receive next bit of input
        if bit_number /= 0 then
          bit_number <= bit_number - 1;
          -- SYNC signal indicates left/right select
          rxbuffer(15 downto 1) <= rxbuffer(14 downto 0);
          rxbuffer(0) <= pcm_in;
        end if;      
        
        -- Present next bit
        -- (If there are more bits than we have, we end up just shifting
        -- out zeroes, in accordance with the spec).
        pcm_out <= txbuffer(15);
        txbuffer(15 downto 1) <= txbuffer(14 downto 0);
        txbuffer(0) <= '0';

        -- Check if it is time for a new sample
        if (last_sync /= pcm_sync) then
          -- Time for a new sample
          txbuffer <= std_logic_vector(tx_sample);
          bit_number <= 15;
        end if;
      end if;
    end if;
  end process;
  
  
end brutalist;
