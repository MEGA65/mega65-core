library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.cputypes.all;
use work.types_pkg.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity r3_expansion is
  Port ( cpuclock : STD_LOGIC;         
         clock27 : std_logic;
         clock81 : std_logic;

         -- PMOD connectors on the MEGA65 main board
         -- We say R3 onwards, but in theory we can work with the R2 board
         -- as well, but that has a smaller FPGA, and no cut-outs in the
         -- case for the extra ports.
         p1lo : inout std_logic_vector(3 downto 0);
         p1hi : inout std_logic_vector(3 downto 0);
         p2lo : inout std_logic_vector(3 downto 0);
         p2hi : inout std_logic_vector(3 downto 0);

         -- C1565 port XXX

         -- USER port XXX

         -- TAPE port XXX

         -- Video and Audio feed for composite video port
         red : in unsigned(7 downto 0);
         green : in unsigned(7 downto 0);
         blue : in unsigned(7 downto 0);
         hsync : in std_logic;
         vsync : in std_logic;
         pal50 : in std_logic;
         vga60 : in std_logic;

         );

end r3_expansion;

architecture gothic of r3_expansion is

begin
  
end gothic;

