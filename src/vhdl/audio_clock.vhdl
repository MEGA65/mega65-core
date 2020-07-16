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
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity audio_clock is
    generic (
        fs      : real;     -- sampling (clken) frequency (kHz)
        ratio   : integer   -- clk to fs frequency ratio
    );
    port (

        rsti    : in    std_logic;          -- reset in
        clki    : in    std_logic;          -- reference clock in
        rsto    : out   std_logic;          -- reset out (from MMCM lock status)
        clk     : inout   std_logic;          -- audio clock out (fs * ratio)
        clken   : out   std_logic           -- audio clock enable out (fs)

    );
end entity audio_clock;

architecture synth of audio_clock is

    signal locked   : std_logic;     -- MMCM lock status
    signal clk_u    : std_logic;     -- unbuffered output clock
    signal clko_fb  : std_logic;     -- unbuffered feedback clock
    signal clki_fb  : std_logic;    -- feedback clock
    signal count    : integer range 0 to ratio-1;

    -- Assume input clock is 50MHz
    constant mmcm_vco_mul   : real      := 96.0;  -- 50MHz x 96 = 4.8GHz
    constant mmcm_vco_div   : integer   := 5;     -- 4.8GHz / 5 = 960 MHz
    constant mmcm_o_div     : real      := 78.125; -- 960 MHz / 78.125 =
                                                      -- 12.288 MHz

    ----------------------------------------------------------------------

begin

    process(locked,clk)
    begin
        if locked = '0' then
            count <= 0;
            clken <= '0';
        elsif rising_edge(clk) then
            clken <= '0';
            if count = ratio-1 then
                count <= 0;
                clken <= '1';
            else
                count <= count + 1;
            end if;
        end if;
    end process;

    MMCM: mmcme2_adv
    generic map(
        bandwidth               => "OPTIMIZED",
        clkfbout_mult_f         => 24.0, -- 50x24 = 1200 mhz
        clkfbout_phase          => 0.0,
        clkfbout_use_fine_ps    => false,
        divclk_divide           => 1,    -- keep 1200MHz
        clkin1_period           => 20.0,
        clkin2_period           => 0.0,
        clkout0_divide_f        => 97.625, -- 1200 / 97.625MHz = 12.291933MHz.
                                           -- Error = 3.933 KHz
        clkout0_duty_cycle      => 0.5,
        clkout0_phase           => 0.0,
        clkout0_use_fine_ps     => false,
        clkout1_divide          => 1,
        clkout1_duty_cycle      => 0.5,
        clkout1_phase           => 0.0,
        clkout1_use_fine_ps     => false,
        clkout2_divide          => 1,
        clkout2_duty_cycle      => 0.5,
        clkout2_phase           => 0.0,
        clkout2_use_fine_ps     => false,
        clkout3_divide          => 1,
        clkout3_duty_cycle      => 0.5,
        clkout3_phase           => 0.0,
        clkout3_use_fine_ps     => false,
        clkout4_cascade         => false,
        clkout4_divide          => 1,
        clkout4_duty_cycle      => 0.5,
        clkout4_phase           => 0.0,
        clkout4_use_fine_ps     => false,
        clkout5_divide          => 1,
        clkout5_duty_cycle      => 0.5,
        clkout5_phase           => 0.0,
        clkout5_use_fine_ps     => false,
        clkout6_divide          => 1,
        clkout6_duty_cycle      => 0.5,
        clkout6_phase           => 0.0,
        clkout6_use_fine_ps     => false,
        compensation            => "ZHOLD",
        is_clkinsel_inverted    => '0',
        is_psen_inverted        => '0',
        is_psincdec_inverted    => '0',
        is_pwrdwn_inverted      => '0',
        is_rst_inverted         => '0',
        ref_jitter1             => 0.01,
        ref_jitter2             => 0.01,
        ss_en                   => "FALSE",
        ss_mode                 => "CENTER_HIGH",
        ss_mod_period           => 10000,
        startup_wait            => false
    )
    port map (
        pwrdwn          => '0',
        rst             => rsti,
        locked          => locked,
        clkin1          => clki,
        clkin2          => '0',
        clkinsel        => '1',
        clkinstopped    => open,
        clkfbin         => clki_fb,
        clkfbout        => clko_fb,
        clkfboutb       => open,
        clkfbstopped    => open,
        clkout0         => clk_u,
        clkout0b        => open,
        clkout1         => open,
        clkout1b        => open,
        clkout2         => open,
        clkout2b        => open,
        clkout3         => open,
        clkout3b        => open,
        clkout4         => open,
        clkout5         => open,
        clkout6         => open,
        dclk            => '0',
        daddr           => (others => '0'),
        den             => '0',
        dwe             => '0',
        di              => (others => '0'),
        do              => open,
        drdy            => open,
        psclk           => '0',
        psdone          => open,
        psen            => '0',
        psincdec        => '0'
    );

    BUFG_O: unisim.vcomponents.bufg
        port map (
            I   => clk_u,
            O   => clk
        );

    BUFG_F: unisim.vcomponents.bufg
        port map (
            I   => clko_fb,
            O   => clki_fb
        );

    rsto <= not locked;

end architecture synth;
