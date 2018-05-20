--MIT License
--
--Copyright (c) 2014-2016 Peter Samarin
--
--Permission is hereby granted, free of charge, to any person obtaining a copy
--of this software and associated documentation files (the "Software"), to deal
--in the Software without restriction, including without limitation the rights
--to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--copies of the Software, and to permit persons to whom the Software is
--furnished to do so, subject to the following conditions:
--
--The above copyright notice and this permission notice shall be included in all
--copies or substantial portions of the Software.
--
--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--SOFTWARE.


------------------------------------------------------------
-- File      : debounce.vhd
------------------------------------------------------------
-- Author     : Peter Samarin <peter.samarin@gmail.com>
------------------------------------------------------------
-- Copyright (c) 2016 Peter Samarin
------------------------------------------------------------
-- Description: debouncing circuit that forwards only
-- signals that have been stable for the whole duration of
-- the counter
------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
------------------------------------------------------------
entity debounce is
  generic (
    WAIT_CYCLES : integer := 5);
  port (
    signal_in  : in  std_logic;
    signal_out : out std_logic;
    clk        : in  std_logic);
end entity debounce;
------------------------------------------------------------
architecture arch of debounce is
  type state_t is (idle, check_input_stable);
  signal state_reg     : state_t                          := idle;
  signal out_reg       : std_logic                        := signal_in;
  signal signal_in_reg : std_logic;
  signal counter       : integer range 0 to WAIT_CYCLES-1 := 0;
begin

  process (clk) is
  begin
    if rising_edge(clk) then
      case state_reg is
        when idle =>
          if out_reg /= signal_in then
            signal_in_reg <= signal_in;
            state_reg     <= check_input_stable;
            counter       <= WAIT_CYCLES-1;
          end if;

        when check_input_stable =>
          if counter = 0 then
            if signal_in = signal_in_reg then
              -- PGS 20180520 - Resolve Z, H to 1
              if signal_in = '0' then
                out_reg <= '0';
              else
                out_reg <= '1';
              end if;
            end if;
            state_reg <= idle;
          else
            if signal_in /= signal_in_reg then
              state_reg <= idle;
            end if;
            counter <= counter - 1;
          end if;
      end case;
    end if;
  end process;

  -- output
  signal_out <= out_reg;

end architecture arch;
