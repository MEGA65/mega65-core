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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;
use work.cputypes.all;

entity pcm_to_pdm is
  port (    
    cpuclock : in std_logic;

    pcm_left : in signed(15 downto 0) := x"0000";
    pcm_right : in signed(15 downto 0) := x"0000";

    pdm_left : out std_logic := '0';
    pdm_right : out std_logic := '0';

    audio_mode : in std_logic := '0'
    );
end pcm_to_pdm;

architecture nordic of pcm_to_pdm is
  
  signal pcm_value_left : integer range 0 to 65535 := 0;
  signal pcm_value_right : integer range 0 to 65535 := 0;
  signal pcm_value_left_hold : integer range 0 to 65535 := 0;
  signal pcm_value_right_hold : integer range 0 to 65535 := 0;

  signal pdm_left_accumulator : integer range 0 to 131071 := 0;
  signal pdm_right_accumulator : integer range 0 to 131071 := 0;
  signal ampPWM_pdm_l : std_logic := '0';
  signal ampPWM_pdm_r : std_logic := '0';

  signal pwm_counter : integer range 0 to 1024 := 0;
  signal ampPWM_pwm_l : std_logic := '0';
  signal ampPWM_pwm_r : std_logic := '0';

  signal audio_reflect : std_logic_vector(3 downto 0) := "0000";

begin

  process (cpuclock) is
  begin
    if rising_edge(cpuclock) then

      -- Convert signed samples to unsigned
      pcm_value_left <= safe_to_integer(unsigned(pcm_left) + 32768);
      pcm_value_right <= safe_to_integer(unsigned(pcm_right) + 32768);
      
      -- Update debug indication of what the audio interface is doing
      audio_reflect(0) <= not audio_reflect(0);      

      -- Implement 10-bit digital audio output

      -- We have three versions of audio output:
      -- 1. Delta-Sigma (aka PDM), which should be most accurate, but requires
      -- good low-pass output filters
      -- 2. PWM, similar to what we used to use.
      -- 3. Balanced PWM, where the pulse is centered in the time domain,
      -- which apparently is "better". I have a wooden ear, so can't tell.
            
      if audio_mode = '0' then
        -- Pulse Density Modulation
        pdm_left <= ampPWM_pdm_l;
        pdm_right <= ampPWM_pdm_r;
      else
        -- Pulse Width Modulation
        pdm_left <= ampPWM_pwm_l;
        pdm_right <= ampPWM_pwm_r;
      end if;

      -- Pulse Density Modulation
      if pdm_left_accumulator < 65536 then
        pdm_left_accumulator <= pdm_left_accumulator + pcm_value_left;
        ampPWM_pdm_l <= '0';
        audio_reflect(2) <= '0';
      else
        pdm_left_accumulator <= pdm_left_accumulator + pcm_value_left - 65536;
        ampPWM_pdm_l <= '1';
        audio_reflect(2) <= '1';
      end if;
      if pdm_right_accumulator < 65536 then
        pdm_right_accumulator <= pdm_right_accumulator + pcm_value_right;
        ampPWM_pdm_r <= '0';
        audio_reflect(3) <= '0';
      else
        pdm_right_accumulator <= pdm_right_accumulator + pcm_value_right - 65536;
        ampPWM_pdm_r <= '1';
        audio_reflect(3) <= '1';
      end if;

      -- Normal Pulse Width Modulation
      if pwm_counter < 1024 then
        pwm_counter <= pwm_counter + 1;
        if safe_to_integer(to_unsigned(pcm_value_left_hold,16)(15 downto 6)) = pwm_counter then
          ampPwm_pwm_l <= '0';
        end if;
        if safe_to_integer(to_unsigned(pcm_value_right_hold,16)(15 downto 6)) = pwm_counter then
          ampPwm_pwm_r <= '0';
        end if;
      else
        pwm_counter <= 0;
        pcm_value_left_hold <= pcm_value_left;
        pcm_value_right_hold <= pcm_value_right;
        if safe_to_integer(to_unsigned(pcm_value_left,16)(15 downto 6)) = 0 then
          ampPWM_pwm_l <= '0';
        else
          ampPWM_pwm_l <= '1';
        end if;
        if safe_to_integer(to_unsigned(pcm_value_right,16)(15 downto 6)) = 0 then
          ampPWM_pwm_r <= '0';
        else
          ampPWM_pwm_r <= '1';
        end if;
      end if;

      
    end if;
  end process;
  
end nordic;
