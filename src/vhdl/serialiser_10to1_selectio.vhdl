--------------------------------------------------------------------------------
-- serialiser_10to1_selectio.vhd                                              --
-- 10:1 serialiser driving SelectIO differential output pair.                 --
--------------------------------------------------------------------------------
-- (C) Copyright 2022 Paul Gardner-Stephen <paul@m-e-g-a.org>                 --
-- For the MEGA65 we found some batches of FPGAs had a lot of trouble with    --
-- the OSERDES for digital video output, with flickering (confirmed on our    --
-- HDMI analyser.  Following a successful example from Antti from Trenz, we   --
-- are switching to implementing the serialiser directly, since 270MHz is     --
-- slow enough, that we can do it completely in the FPGA fabric.              --
--------------------------------------------------------------------------------
-- Based on:                                                                  --
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
        clk_x10 : in    std_logic;                      -- serialiser DDR clock
        d       : in    std_logic_vector(9 downto 0);   -- input parallel data
        out_u_p   : out   std_logic;                    -- output serial data
                                                        -- unbuffered
        out_u_n   : out   std_logic;                    -- "
        out_p   : out   std_logic;                      -- output serial data
        out_n   : out   std_logic                       -- "
    );
end entity serialiser_10to1_selectio;

architecture synth of serialiser_10to1_selectio is

  signal TMDS_mod10 : integer range 0 to 9 := 0;
  signal TMDS_shift : std_logic_vector(9 downto 0) := (others => '0');
  signal TMDS_shift_load : std_logic := '0';
  signal q : std_logic := '0';
  signal q_d : std_logic := '0';
  
begin

  process (clk_x10,d)
  begin
    if rising_edge(clk_x10) then
      if TMDS_shift_load='1' then
        TMDS_shift <= d;
      else
        TMDS_shift(8 downto 0) <= TMDS_shift(9 downto 1);
      end if;
      q_d <= TMDS_shift(0);
      q <= q_d;
      
      if TMDS_mod10 /= 9 then
        TMDS_mod10 <= TMDS_mod10 + 1;
        TMDS_shift_load <= '0';
      else
        TMDS_mod10 <= 0;
        TMDS_shift_load <= '1';
      end if;
    end if;
  end process;

  out_u_p <= q;
  out_u_n <= not q;
  
  -- differential output buffer
  U_OBUF: obufds
    port map (
      i   => q,
      o   => out_p,
      ob  => out_n
      );

end architecture synth;
