--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2018
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
--
-- Take a PDM 1-bit sample train and produce 8-bit PCM audio output
-- We have to shape the noise into the high frequency domain, as well
-- as remove any DC bias from the audio source.
--
-- Inspiration taken from https://www.dsprelated.com/showthread/comp.dsp/288391-1.php

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity pdm_to_pcm is
  port (
    clock : in std_logic;
    sample_clock : in std_logic;
    sample_bit : in std_logic;
    sample_out : out unsigned(7 downto 0)
    );
end pdm_to_pcm;

architecture behavioural of pdm_to_pcm is

  subtype sample_t is integer range 0 to 65535;
  type samplearray_t is array(0 to 15) of sample_t;
    
  signal recent_bits : std_logic_vector(31 downto 0) := (others => '0');
  signal sum : sample_t := 0;

  signal recent_sums : samplearray_t :=( others => 0);
  signal rolling_sums : samplearray_t :=( others => 0);
  signal rolling_sum : sample_t := 0;
  signal rolling_sum_count : sample_t := 0;
  
  signal sample_count : integer range 0 to 15 := 0;

  signal sample_value : sample_t := 0;

  
begin
  process (clock) is
    variable ny : std_logic_vector(1 downto 0);
  begin
    if rising_edge(clock) then
      if sample_clock='1' then
        -- New sample, update everything

        -- Stage 1: Counter: gives values 0-31 for count of 1s
        recent_bits(0) <= sample_bit;
        recent_bits(31 downto 1) <= recent_bits(30 downto 0);
        ny := std_logic(recent_bits(31))&std_logic(sample_bit);
        case ny is
          when "11" =>
            -- Total stays unchanged
            null;
          when "10" =>
            -- Total reduces
            if sum /= 0 then
              sum <= sum - 1;
            end if;
          when "01" =>
            -- Total increases
            if sum /= 65535 then
              sum <= sum + 1;
            end if;
          when "00" =>
            -- Total stays unchanged, unless we want to leak DC bias away
            null;
          when others =>
            null;
        end case;

        -- Stage 2: Sum recent sums: Range is 0 - 10x31 = 310
        if sample_count /= 10 then
          sample_count <= sample_count + 1;
        else
          sample_count <= 0;
          
          for i in 15 to 1 loop
            recent_sums(i) <= recent_sums(i-1);
          end loop;            
          recent_sums(0) <= sum;
          if rolling_sum + sum > recent_sums(10) then
            rolling_sum <= rolling_sum + sum - recent_sums(10);
          else
            rolling_sum <= 0;
          end if;

          -- Stage 3: Sum those recent sums: Range is 0 to 13x10x31 = ~4K
          if rolling_sum_count /= 15 then
            rolling_sum_count <= rolling_sum_count + 1;
          else
            rolling_sum_count <= 0;
            for i in 15 to 1 loop
              rolling_sums(i) <= rolling_sums(i-1);
            end loop;
            if sample_value + rolling_sum > rolling_sums(13) then
              sample_value <= sample_value + rolling_sum - rolling_sums(13);
            else
              sample_value <= 0;
            end if;
          end if;        
        end if;

--        sample_out <= to_unsigned(sample_value,12)(11 downto 4);
        sample_out <= to_unsigned(rolling_sum,8);
--        sample_out <= to_unsigned(sum,8);
          
      end if;
    end if;
  end process;
end behavioural;


    
