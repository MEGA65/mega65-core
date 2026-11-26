--------------------------------------------------------------------------------
-- serialiser_10to1_oserdes.vhdl                                              --
-- 10:1 serialiser driving SelectIO differential output pair.                 --
--------------------------------------------------------------------------------
-- This is the Tyto Project's serialiser_10to1_selectio.vhd as it is, under   --
-- another name. The MEGA65's file of that name has made the bit stream in    --
-- the FPGA's fabric since January 2022 (issue 516), which does for the 270   --
-- Mbit/s of 576p and 480p but not for the 742.5 Mbit/s of 720p. A design     --
-- that sends 720p uses this one, with OSERDESE2, for all its modes.          --
--                                                                            --
-- WHAT WENT WRONG WITH OSERDESE2 IN 2022, and what a design that uses this   --
-- must therefore do. Some R3A boards had glitching or no digital video. It   --
-- was put down to the OSERDESE2 and the FPGAs' batch, and the serialiser was --
-- changed; the glitching stayed, and in March 2022 was traced to the reset   --
-- line and the DIP switches' values, which on R3 boards come over a serial   --
-- link from the MAX10, misread on boards whose MAX10's oscillator ran slow   --
-- ("Solving the last of the digital video output glitching", c65gs.blogspot  --
-- .com, 24 March 2022; fixed in May 2022 by 82a7b0c85, 5c1409349 and         --
-- 4ea77adb9). In the design of the time that reset went, from the 40.5 MHz   --
-- clock's domain and at any moment, to every OSERDESE2's RST, to the HDMI    --
-- encoder's reset and to the audio clock's; and DIP switch 2 chose HDMI or   --
-- DVI for the encoder, read again every 2 microseconds. Each stops the       --
-- picture whatever the serialiser is (choosing HDMI and DVI in turn, fast,   --
-- gives no picture at all on an R6 with this file: tried, November 2026).    --
-- The fabric serialiser has no reset, which is what it took out of harm's    --
-- way. The MiSTer2MEGA65 cores have used OSERDESE2, this very file, on the   --
-- same boards at 742.5 Mbit/s all along.                                     --
--                                                                            --
-- So, for rst here (as UG471 and UG953 have it for OSERDESE2's RST):         --
--   * one signal for all the OSERDESE2s of the output, clock lane included   --
--   * taken away in step with clk (a flip-flop on clk drives it), and only   --
--     when clk and clk_x5 are there and steady: after the design starts,     --
--     and after anything that changes them                                   --
--   * nothing else: not the machine's reset line, not a button, nothing a    --
--     program or another chip can wiggle while a picture is going out        --
--   * clk and clk_x5 from one MMCM, each through a global buffer             --
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

library unisim;
use unisim.vcomponents.all;

entity serialiser_10to1_oserdes is
    port (
        rst     : in    std_logic;                      -- reset
        clk     : in    std_logic;                      -- parallel data clcok
        clk_x5  : in    std_logic;                      -- serialiser DDR clock
        d       : in    std_logic_vector(9 downto 0);   -- input parallel data
        out_p   : out   std_logic;                      -- output serial data
        out_n   : out   std_logic                       -- "
    );
end entity serialiser_10to1_oserdes;

architecture synth of serialiser_10to1_oserdes is

    signal s1   : std_logic;
    signal s2   : std_logic;
    signal q    : std_logic;

begin

    -- serialiser (master)
    U_SER_M: oserdese2
        generic map (
            data_rate_oq => "DDR",      -- DDR, SDR
            data_rate_tq => "SDR",      -- DDR, BUF, SDR
            data_width => 10,           -- Parallel data width (2-8,10,14)
            init_oq => '0',             -- Initial value of OQ output (1'b0,1'b1)
            init_tq => '0',             -- Initial value of TQ output (1'b0,1'b1)
            serdes_mode => "MASTER",    -- MASTER, SLAVE
            srval_oq => '0',            -- OQ output value when SR is used (1'b0,1'b1)
            srval_tq => '0',            -- TQ output value when SR is used (1'b0,1'b1)
            tbyte_ctl => "FALSE",       -- Enable tristate byte operation (FALSE, TRUE)
            tbyte_src => "FALSE",       -- Tristate byte source (FALSE, TRUE)
            tristate_width => 1         -- 3-state converter width (1,4)
        )
        port map (
            ofb         => open,        -- 1-bit output: Feedback path for data
            oq          => q,           -- 1-bit output: Data path output
            shiftout1   => open,        -- SHIFTOUT1 / SHIFTOUT2: 1-bit (each) output: Data output expansion (1-bit each)
            shiftout2   => open,
            tbyteout    => open,        -- 1-bit output: Byte group tristate
            tfb         => open,        -- 1-bit output: 3-state control
            tq          => open,        -- 1-bit output: 3-state control
            clk         => clk_x5,      -- 1-bit input: High speed clock
            clkdiv      => clk,         -- 1-bit input: Divided clock
            d1          => d(0),        -- D1 - D8: 1-bit (each) input: Parallel data inputs (1-bit each)
            d2          => d(1),
            d3          => d(2),
            d4          => d(3),
            d5          => d(4),
            d6          => d(5),
            d7          => d(6),
            d8          => d(7),
            oce         => '1',         -- 1-bit input: Output data clock enable
            rst         => rst,         -- 1-bit input: Reset
            shiftin1    => s1,          -- SHIFTIN1 / SHIFTIN2: 1-bit (each) input: Data input expansion (1-bit each)
            shiftin2    => s2,
            t1          => '0',         -- T1 - T4: 1-bit (each) input: Parallel 3-state inputs
            t2          => '0',
            t3          => '0',
            t4          => '0',
            tbytein     => '0',         -- 1-bit input: Byte group tristate
            tce         => '0'          -- 1-bit input: 3-state clock enable
        );

    -- serialiser (slave)
    U_SER_S: oserdese2
        generic map (
            data_rate_oq => "DDR",      -- DDR, SDR
            data_rate_tq => "SDR",      -- DDR, BUF, SDR
            data_width => 10,           -- Parallel data width (2-8,10,14)
            init_oq => '0',             -- Initial value of OQ output (1'b0,1'b1)
            init_tq => '0',             -- Initial value of TQ output (1'b0,1'b1)
            serdes_mode => "SLAVE",     -- MASTER, SLAVE
            srval_oq => '0',            -- OQ output value when SR is used (1'b0,1'b1)
            srval_tq => '0',            -- TQ output value when SR is used (1'b0,1'b1)
            tbyte_ctl => "FALSE",       -- Enable tristate byte operation (FALSE, TRUE)
            tbyte_src => "FALSE",       -- Tristate byte source (FALSE, TRUE)
            tristate_width => 1         -- 3-state converter width (1,4)
        )
        port map (
            ofb         => open,        -- 1-bit output: Feedback path for data
            oq          => open,        -- 1-bit output: Data path output
            shiftout1   => s1,          -- SHIFTOUT1 / SHIFTOUT2: 1-bit (each) output: Data output expansion (1-bit each)
            shiftout2   => s2,
            tbyteout    => open,        -- 1-bit output: Byte group tristate
            tfb         => open,        -- 1-bit output: 3-state control
            tq          => open,        -- 1-bit output: 3-state control
            clk         => clk_x5,      -- 1-bit input: High speed clock
            clkdiv      => clk,         -- 1-bit input: Divided clock
            d1          => '0',         -- D1 - D8: 1-bit (each) input: Parallel data inputs (1-bit each)
            d2          => '0',
            d3          => d(8),
            d4          => d(9),
            d5          => '0',
            d6          => '0',
            d7          => '0',
            d8          => '0',
            oce         => '1',         -- 1-bit input: Output data clock enable
            rst         => rst,         -- 1-bit input: Reset
            shiftin1    => '0',         -- SHIFTIN1 / SHIFTIN2: 1-bit (each) input: Data input expansion (1-bit each)
            shiftin2    => '0',
            t1          => '0',         -- T1 - T4: 1-bit (each) input: Parallel 3-state inputs
            t2          => '0',
            t3          => '0',
            t4          => '0',
            tbytein     => '0',         -- 1-bit input: Byte group tristate
            tce         => '0'          -- 1-bit input: 3-state clock enable
        );

    -- differential output buffer
    U_OBUF: obufds
        port map (
            i   => q,
            o   => out_p,
            ob  => out_n
        );

end architecture synth;
