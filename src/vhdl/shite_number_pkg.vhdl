library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package shite_number_pkg is
  type number_operation is (BIG_LOAD, BIG_COPY, BIG_MULTIPLY, BIG_COMPARE,
    BIG_SUBTRACT, BIG_SUM_COMPARE, BIG_DIVIDE10, BIG_DIVIDE2, BIG_GET,
    BIG_READ_BYTE, BIG_WRITE_BYTE);
end package;
