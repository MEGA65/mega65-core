--------------------------------------------------------------------------------
-- utils_pkg.vhd                                                              --
-- Utilities package.                                                         --
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

package utils_pkg is

    function ternary_slv(condition : boolean; result_true, result_false : std_logic_vector) return std_logic_vector;
    function ternary_u(condition : boolean; result_true, result_false : unsigned) return unsigned;
    function ternary_i(condition : boolean; result_true, result_false : integer) return integer;

end package utils_pkg;

package body utils_pkg is

    function ternary_slv(condition : boolean; result_true, result_false : std_logic_vector) return std_logic_vector is
    begin
        if condition then
            return result_true;
        else
            return result_false;
        end if;
    end function ternary_slv;

    function ternary_u(condition : boolean; result_true, result_false : unsigned) return unsigned is
    begin
        if condition then
            return result_true;
        else
            return result_false;
        end if;
    end function ternary_u;

    function ternary_i(condition : boolean; result_true, result_false : integer) return integer is
    begin
        if condition then
            return result_true;
        else
            return result_false;
        end if;
    end function ternary_i;

end package body utils_pkg;
