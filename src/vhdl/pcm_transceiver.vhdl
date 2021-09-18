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
  generic ( clock_frequency : integer );
  port (
    cpuclock : in std_logic;

    -- PCM clock and sync signals
    pcm_clk : in std_logic;
    pcm_sync : in std_logic;

    -- PCM audio interface
    pcm_out : out std_logic;
    pcm_in : in std_logic;

    -- sample to send
    tx_sample : in signed(15 downto 0);

    -- last sample received
    rx_sample : out signed(15 downto 0)

    );

end pcm_transceiver;

architecture brutalist of pcm_transceiver is

  signal bit_number : integer range 0 to 16 := 0;
  signal rxbuffer : std_logic_vector(15 downto 0) := (others => '0');
  signal txbuffer : std_logic_vector(15 downto 0) := (others => '0');

  signal rx_sync_buffer : std_logic_vector(19 downto 0) := (others => '0');
  
  signal last_clk : std_logic := '0';
  signal last_sync : std_logic := '0';

  signal rxdone : std_logic := '0';
  
begin

  process (cpuclock) is
  begin
    if rising_edge(cpuclock) then

      last_sync <= pcm_sync;
      last_clk <= pcm_clk;
      report "CLK=" & std_logic'image(pcm_clk) & ", SYNC=" & std_logic'image(pcm_sync);

      if pcm_clk='1' and last_clk='0' then

        -- The EC25AU ignores our sync pulses.
        -- Therefore we have to try to latch to the audio samples it provides.
        -- (Also for unknown reasons, it is providing audio samples at only
        -- 4KHz (3.906KHz according to the oscilloscope), instead of 8KHz.)
        -- Basically if we see the pcm_in line go low after having been high
        -- for at least 17 clock ticks, then we can assume that it is the start
        -- of a sample. This relies on bit 0 of the incoming sample being 0, which
        -- should be at least 50% of the time. The problem is if it isn't, then
        -- we will be out of step by one bit, which will result in big problems
        -- for the audio we feed it (and for the sample we are recovering).
        rx_sync_buffer(0) <= pcm_in;
        rx_sync_buffer(19 downto 1) <= rx_sync_buffer(18 downto 0);
        if (rx_sync_buffer = "11111111111111111111" and pcm_in='0') and (bit_number=0) then
          -- Time for a new sample
          txbuffer <= std_logic_vector(tx_sample);
          report "Synchronising to inferred sync clock via PCM_DIN";
          bit_number <= 15;
        end if;
      
        -- Receive next bit of input
        if bit_number /= 0 then
          bit_number <= bit_number - 1;
          -- SYNC signal indicates left/right select
          rxbuffer(15 downto 1) <= rxbuffer(14 downto 0);
          rxbuffer(0) <= pcm_in;
        else
          -- Copy received sample out
          -- Note that the PCM audio is signed, so we need to convert it to unsigned
          if rxdone='0' then
            rx_sample <= signed(rxbuffer);
            rxbuffer <= "0000000000000000";
            rxdone <= '1';
          end if;
        end if;
        
        -- Present next bit
        -- (If there are more bits than we have, we end up just shifting
        -- out zeroes, in accordance with the spec).
        pcm_out <= txbuffer(15);
        txbuffer(15 downto 1) <= txbuffer(14 downto 0);
        txbuffer(0) <= '0';
        report "TXing bit " & std_logic'image(txbuffer(0))
          & ", remaining bits = " & to_string(txbuffer)
          & ", next sample = $" & to_hstring(tx_sample);
      end if;

      -- Check if it is time for a new sample
      if (last_sync='1' and pcm_sync='0') then
        -- Time for a new sample
        -- Invert bit 15 to convert from unsigned to signed
        txbuffer <= std_logic_vector(tx_sample);
        report "Starting to send new sample with value $" & to_hstring(tx_sample);
        bit_number <= 16;
        rxdone <= '0';                  
      end if;

    end if;
  end process;
  
  
end brutalist;
