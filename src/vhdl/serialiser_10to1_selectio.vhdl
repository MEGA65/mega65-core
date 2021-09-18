--------------------------------------------------------------------------------
-- serialiser_10to1_selectio.vhd                                              --
-- 10:1 serialiser driving SelectIO differential output pair.                 --
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

entity serialiser_10to1_selectio is
    port (
        rst     : in    std_logic;                      -- reset
        clk     : in    std_logic;                      -- parallel data clcok
        clk_x5  : in    std_logic;                      -- serialiser DDR clock
        d       : in    std_logic_vector(9 downto 0);   -- input parallel data
        out_p   : out   std_logic;                      -- output serial data
        out_n   : out   std_logic                       -- "
    );
end entity serialiser_10to1_selectio;

architecture synth of serialiser_10to1_selectio is

    signal s1   : std_logic;
    signal s2   : std_logic;
    signal q    : std_logic;

begin

    -- serialiser (master)
    U_SER_M: oserdese2
        generic map (
            data_rate_oq => "DDR",      -- DDR, SDR
            data_rate_tq => "DDR",      -- DDR, BUF, SDR
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
            data_rate_tq => "DDR",      -- DDR, BUF, SDR
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
