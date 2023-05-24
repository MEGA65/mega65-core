--------------------------------------------------------------------------------
-- audio_out_test_tone.vhd                                                    --
-- Simple test tone generator (fs = 48kHz).                                   --
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
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

entity audio_out_test_tone is
    generic (
        fref        : real                                  -- reference clock frequency (MHz)
    );
    port (

      -- Allow switching between these to audio sample rates
      select_44100 : in std_logic; 
      
        ref_rst     : in    std_logic;                      -- reference clock reset
        ref_clk     : in    std_logic;                      -- reference clock (100MHz)

        invert_sign : in std_logic := '0'; -- switch samples between signed and
                                           -- unsigned for I2S output

        pcm_rst     : buffer   std_logic;                      -- audio clock reset
        pcm_clk     : buffer   std_logic;                      -- audio clock (256Fs = 12.288MHz)
        pcm_clken   : buffer   std_logic;                      -- audio clock enable (Fs = 48kHz)

        i2s_data_out : out std_logic;
        i2s_bick : out std_logic;
        i2s_lrclk : out std_logic;

        audio_left_slow : in std_logic_vector(19 downto 0);
        audio_right_slow : in std_logic_vector(19 downto 0);
        sample_ready_toggle : in std_logic;
        
        pcm_l       : out   std_logic_vector(15 downto 0);  -- } synchronous to pcm_clk
        pcm_r       : out   std_logic_vector(15 downto 0)   -- } valid on pcm_clken

    );
end entity audio_out_test_tone;

architecture synth of audio_out_test_tone is

  signal last_sample_ready_toggle : std_logic := '0';
  signal sample_stable_cycles : integer := 0; 

  signal i2s_data : std_logic_vector(63 downto 0) := (others => '0');
  signal fs_counter : integer range 0 to 255 := 0;

  signal pcm_l_int : std_logic_vector(19 downto 0) := (others => '0');
  signal pcm_r_int : std_logic_vector(19 downto 0) := (others => '0');

begin

    CLOCK: entity work.audio_clock
        generic map (
            fs      => 48.0,
            ratio   => 256
        )
      port map (
        select_44100 => select_44100,
            rsti    => ref_rst,
            clki    => ref_clk,
            rsto    => pcm_rst,
            clk     => pcm_clk, -- = ~12.228 MHz
            clken   => pcm_clken -- = sample strobe
        );

    process(pcm_rst,pcm_clk)
    begin
        if pcm_rst = '1' then


        elsif rising_edge(pcm_clk) then

          -- Receive samples via slow toggle clock from CPU clock domain
          if last_sample_ready_toggle /= sample_ready_toggle then
            sample_stable_cycles <= 0;
            last_sample_ready_toggle <= sample_ready_toggle;
          else
            sample_stable_cycles <= sample_stable_cycles + 1;
            if sample_stable_cycles = 8 then
              pcm_l <= audio_left_slow(19 downto 4);
              pcm_r <= audio_right_slow(19 downto 4);
              pcm_l_int(19) <= audio_left_slow(19) xor invert_sign ;
              pcm_l_int(18 downto 0) <= audio_left_slow(18 downto 0);
              pcm_r_int(19) <= audio_right_slow(19) xor invert_sign;
              pcm_r_int(18 downto 0) <= audio_right_slow(18 downto 0);
            end if;
          end if;

          -- Generate LRCLK, BICK and SDTI for I2S sinks
          i2s_data_out <= i2s_data(63);
          if fs_counter < 128 then i2s_lrclk <= '1'; else i2s_lrclk <= '0'; end if;
          if (fs_counter mod 4) < 2 then i2s_bick <= '0'; else i2s_bick <= '1'; end if;
          if fs_counter /= 255 then
            fs_counter <= fs_counter + 1;
            if (fs_counter mod 4) = 3 then
              i2s_data(63 downto 1) <= i2s_data(62 downto 0);
            end if;
          else
            fs_counter <= 0;
            i2s_data(63 downto 44) <= pcm_l_int;
            i2s_data(31 downto 12) <= pcm_r_int;
          end if;
        end if;
    end process;
    
end architecture synth;
