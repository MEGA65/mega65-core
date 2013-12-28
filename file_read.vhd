-- from http://www.stefanvhdl.com/vhdl/html/file_read.html
library ieee;
use ieee.std_logic_1164.all;

use std.textio.all;
use work.txt_util.all;
 
 
entity FILE_READ is
  generic (
           stim_file:       string  := "sim2.dat"
          );
  port(
       CLK              : in  std_logic;
       RST              : in  std_logic;
       Y                : out std_logic_vector(7 downto 0);
       EOG              : out std_logic
      );
end FILE_READ;

 
-- I/O Dictionary
--
-- Inputs:
--
-- CLK:              new cell needed
-- RST:              reset signal, wait with reading till reset seq complete
--   
-- Outputs:
--
-- Y:                Output vector
-- EOG:              End Of Generation, all lines have been read from the file
--
   
   
architecture read_from_file of FILE_READ is
  
  
    file stimulus: TEXT open read_mode is stim_file;


begin



-- read data and control information from a file

receive_data: process

variable l: line;
variable s: string(y'range);
   
begin                                       

   EOG <= '0';
   
   -- wait for Reset to complete
   wait until RST='1';
   wait until RST='0';

   
   while not endfile(stimulus) loop

     -- read digital data from input file
     readline(stimulus, l);
     read(l, s);
     Y <= to_std_logic_vector(s);
     
     wait until CLK = '1';

   end loop;
   
   print("I@FILE_READ: reached end of "& stim_file);
   EOG <= '1';
   
   wait;

 end process receive_data;



end read_from_file;
 
