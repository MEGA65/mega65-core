library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

--
entity charrom is
port (Clk : in std_logic;
        address : in integer range 0 to 4095;
        -- chip select, active low       
        cs : in std_logic;
        data_o : out std_logic_vector(7 downto 0);

        writeclk : in std_logic;
        -- Yes, we do have a write enable, because we allow modification of ROMs
        -- in the running machine, unless purposely disabled.  This gives us
        -- something like the WOM that the Amiga had.
        writecs : in std_logic;
        we : in std_logic;
        writeaddress : in unsigned(11 downto 0);
        data_i : in std_logic_vector(7 downto 0)
      );
end charrom;

architecture Behavioral of charrom is

-- 4K x 8bit pre-initialised RAM
-- Characters are from:
-- http://users.ices.utexas.edu/~lenharth/cs378/fall13/font8x8.h
-- Original copyright notice:
--  * 8x8 monochrome bitmap fonts for rendering
 --* Author: Daniel Hepper <daniel@hepper.net>
 --* 
 --* License: Public Domain
 --* 
 --* Based on:
 --* // Summary: font8x8.h
 --* // 8x8 monochrome bitmap fonts for rendering
 --* //
 --* // Author:
 --* //     Marcel Sondaar
 --* //     International Business Machines (public domain VGA fonts)
 --* //
 --* // License:
 --* //     Public Domain
 --* 
 --* Fetched from: http://dimensionalrift.homelinux.net/combuster/mos3/?p=viewsource&file=/modules/gfx/font8_8.asm

type ram_t is array (0 to 4095) of std_logic_vector(7 downto 0);
signal ram : ram_t := (
  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:         
  x"7c", x"c6", x"de", x"de", x"de", x"c0", x"78", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"30", x"78", x"cc", x"cc", x"fc", x"cc", x"cc", x"00",
  -- PIXELS:  *****  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:         
  x"7c", x"66", x"66", x"7c", x"66", x"66", x"7c", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"c0", x"66", x"3c", x"00",
  -- PIXELS:  ****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"6c", x"66", x"66", x"66", x"6c", x"78", x"00",
  -- PIXELS:  ****** 
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  ****   
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  ****** 
  -- PIXELS:         
  x"7e", x"60", x"60", x"78", x"60", x"60", x"7e", x"00",
  -- PIXELS:  ****** 
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  ****   
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:         
  x"7e", x"60", x"60", x"78", x"60", x"60", x"60", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **  *** 
  -- PIXELS:  **  ** 
  -- PIXELS:   ***** 
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"ce", x"66", x"3e", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"fc", x"cc", x"cc", x"cc", x"00",
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"30", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS:    **** 
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"1e", x"0c", x"0c", x"0c", x"cc", x"cc", x"78", x"00",
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS:  ****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:         
  x"66", x"66", x"6c", x"78", x"6c", x"66", x"66", x"00",
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  ****** 
  -- PIXELS:  ****** 
  -- PIXELS:         
  x"60", x"60", x"60", x"60", x"60", x"7e", x"7e", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: *** *** 
  -- PIXELS: ******* 
  -- PIXELS: ******* 
  -- PIXELS: ** * ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"ee", x"fe", x"fe", x"d6", x"c6", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: ***  ** 
  -- PIXELS: **** ** 
  -- PIXELS: ** **** 
  -- PIXELS: **  *** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"e6", x"f6", x"de", x"ce", x"c6", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:         
  x"38", x"6c", x"c6", x"c6", x"c6", x"6c", x"38", x"00",
  -- PIXELS:  *****  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  ***    
  -- PIXELS:         
  x"7c", x"66", x"66", x"7c", x"60", x"60", x"70", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ** ***  
  -- PIXELS:  ****   
  -- PIXELS:    ***  
  -- PIXELS:         
  x"78", x"cc", x"cc", x"cc", x"dc", x"78", x"1c", x"00",
  -- PIXELS:  *****  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:         
  x"7c", x"66", x"66", x"7c", x"6c", x"66", x"66", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: ***     
  -- PIXELS:  ***    
  -- PIXELS:    ***  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"e0", x"70", x"1c", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"fc", x"30", x"30", x"30", x"30", x"30", x"30", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"cc", x"fc", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"78", x"30", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: ** * ** 
  -- PIXELS: ******* 
  -- PIXELS: *** *** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"c6", x"d6", x"fe", x"ee", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"6c", x"38", x"38", x"6c", x"c6", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"78", x"30", x"30", x"78", x"00",
  -- PIXELS: ******* 
  -- PIXELS: **   ** 
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"c6", x"0c", x"18", x"30", x"66", x"fe", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   ****  
  -- PIXELS:   ****  
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:         
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"3c", x"3c", x"18", x"18", x"00", x"18", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"6c", x"6c", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  x"6c", x"6c", x"fe", x"6c", x"fe", x"6c", x"6c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  *****  
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:     **  
  -- PIXELS: *****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"30", x"7c", x"c0", x"78", x"0c", x"f8", x"30", x"00",
  -- PIXELS:         
  -- PIXELS: **   ** 
  -- PIXELS: **  **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **  ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"00", x"c6", x"cc", x"18", x"30", x"66", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:  *** ** 
  -- PIXELS: ** ***  
  -- PIXELS: **  **  
  -- PIXELS:  *** ** 
  -- PIXELS:         
  x"38", x"6c", x"38", x"76", x"dc", x"cc", x"76", x"00",
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"60", x"60", x"c0", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"60", x"60", x"30", x"18", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"18", x"18", x"30", x"60", x"00",
  -- PIXELS:         
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS: ********
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"66", x"3c", x"ff", x"3c", x"66", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"30", x"30", x"fc", x"30", x"30", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"fc", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:      ** 
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *       
  -- PIXELS:         
  x"06", x"0c", x"18", x"30", x"60", x"c0", x"80", x"00",
  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: **  *** 
  -- PIXELS: ** **** 
  -- PIXELS: **** ** 
  -- PIXELS: ***  ** 
  -- PIXELS:  *****  
  -- PIXELS:         
  x"7c", x"c6", x"ce", x"de", x"f6", x"e6", x"7c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ***    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:         
  x"30", x"70", x"30", x"30", x"30", x"30", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"60", x"cc", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"0c", x"cc", x"78", x"00",
  -- PIXELS:    ***  
  -- PIXELS:   ****  
  -- PIXELS:  ** **  
  -- PIXELS: **  **  
  -- PIXELS: ******* 
  -- PIXELS:     **  
  -- PIXELS:    **** 
  -- PIXELS:         
  x"1c", x"3c", x"6c", x"cc", x"fe", x"0c", x"1e", x"00",
  -- PIXELS: ******  
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"c0", x"f8", x"0c", x"0c", x"cc", x"78", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"38", x"60", x"c0", x"f8", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"fc", x"cc", x"0c", x"18", x"30", x"30", x"30", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"cc", x"78", x"cc", x"cc", x"78", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  *****  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:  ***    
  -- PIXELS:         
  x"78", x"cc", x"cc", x"7c", x"0c", x"18", x"70", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"c0", x"60", x"30", x"18", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"fc", x"00", x"00", x"fc", x"00", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"0c", x"18", x"30", x"60", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:         
  x"78", x"cc", x"0c", x"18", x"30", x"00", x"30", x"00",

  -- and repeat 7 more times
  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:         
  x"7c", x"c6", x"de", x"de", x"de", x"c0", x"78", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"30", x"78", x"cc", x"cc", x"fc", x"cc", x"cc", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS: ******  
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"66", x"66", x"fc", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"c0", x"66", x"3c", x"00",
  -- PIXELS: *****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS: *****   
  -- PIXELS:         
  x"f8", x"6c", x"66", x"66", x"66", x"6c", x"f8", x"00",
  -- PIXELS: ******* 
  -- PIXELS:  **   * 
  -- PIXELS:  ** *   
  -- PIXELS:  ****   
  -- PIXELS:  ** *   
  -- PIXELS:  **   * 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"62", x"68", x"78", x"68", x"62", x"fe", x"00",
  -- PIXELS: ******* 
  -- PIXELS:  **   * 
  -- PIXELS:  ** *   
  -- PIXELS:  ****   
  -- PIXELS:  ** *   
  -- PIXELS:  **     
  -- PIXELS: ****    
  -- PIXELS:         
  x"fe", x"62", x"68", x"78", x"68", x"60", x"f0", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **  *** 
  -- PIXELS:  **  ** 
  -- PIXELS:   ***** 
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"ce", x"66", x"3e", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"fc", x"cc", x"cc", x"cc", x"00",
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"30", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS:    **** 
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"1e", x"0c", x"0c", x"0c", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ***  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS:  ****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS: ***  ** 
  -- PIXELS:         
  x"e6", x"66", x"6c", x"78", x"6c", x"66", x"e6", x"00",
  -- PIXELS: ****    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **   * 
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"f0", x"60", x"60", x"60", x"62", x"66", x"fe", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: *** *** 
  -- PIXELS: ******* 
  -- PIXELS: ******* 
  -- PIXELS: ** * ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"ee", x"fe", x"fe", x"d6", x"c6", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: ***  ** 
  -- PIXELS: **** ** 
  -- PIXELS: ** **** 
  -- PIXELS: **  *** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"e6", x"f6", x"de", x"ce", x"c6", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:         
  x"38", x"6c", x"c6", x"c6", x"c6", x"6c", x"38", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: ****    
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"60", x"60", x"f0", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ** ***  
  -- PIXELS:  ****   
  -- PIXELS:    ***  
  -- PIXELS:         
  x"78", x"cc", x"cc", x"cc", x"dc", x"78", x"1c", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS: ***  ** 
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"6c", x"66", x"e6", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: ***     
  -- PIXELS:  ***    
  -- PIXELS:    ***  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"e0", x"70", x"1c", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: * ** *  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"b4", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"cc", x"fc", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"78", x"30", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: ** * ** 
  -- PIXELS: ******* 
  -- PIXELS: *** *** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"c6", x"d6", x"fe", x"ee", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"6c", x"38", x"38", x"6c", x"c6", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"78", x"30", x"30", x"78", x"00",
  -- PIXELS: ******* 
  -- PIXELS: **   ** 
  -- PIXELS: *   **  
  -- PIXELS:    **   
  -- PIXELS:   **  * 
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"c6", x"8c", x"18", x"32", x"66", x"fe", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   ****  
  -- PIXELS:   ****  
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:         
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"3c", x"3c", x"18", x"18", x"00", x"18", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"6c", x"6c", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  x"6c", x"6c", x"fe", x"6c", x"fe", x"6c", x"6c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  *****  
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:     **  
  -- PIXELS: *****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"30", x"7c", x"c0", x"78", x"0c", x"f8", x"30", x"00",
  -- PIXELS:         
  -- PIXELS: **   ** 
  -- PIXELS: **  **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **  ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"00", x"c6", x"cc", x"18", x"30", x"66", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:  *** ** 
  -- PIXELS: ** ***  
  -- PIXELS: **  **  
  -- PIXELS:  *** ** 
  -- PIXELS:         
  x"38", x"6c", x"38", x"76", x"dc", x"cc", x"76", x"00",
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"60", x"60", x"c0", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"60", x"60", x"30", x"18", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"18", x"18", x"30", x"60", x"00",
  -- PIXELS:         
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS: ********
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"66", x"3c", x"ff", x"3c", x"66", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"30", x"30", x"fc", x"30", x"30", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"fc", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:      ** 
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *       
  -- PIXELS:         
  x"06", x"0c", x"18", x"30", x"60", x"c0", x"80", x"00",
  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: **  *** 
  -- PIXELS: ** **** 
  -- PIXELS: **** ** 
  -- PIXELS: ***  ** 
  -- PIXELS:  *****  
  -- PIXELS:         
  x"7c", x"c6", x"ce", x"de", x"f6", x"e6", x"7c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ***    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:         
  x"30", x"70", x"30", x"30", x"30", x"30", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"60", x"cc", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"0c", x"cc", x"78", x"00",
  -- PIXELS:    ***  
  -- PIXELS:   ****  
  -- PIXELS:  ** **  
  -- PIXELS: **  **  
  -- PIXELS: ******* 
  -- PIXELS:     **  
  -- PIXELS:    **** 
  -- PIXELS:         
  x"1c", x"3c", x"6c", x"cc", x"fe", x"0c", x"1e", x"00",
  -- PIXELS: ******  
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"c0", x"f8", x"0c", x"0c", x"cc", x"78", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"38", x"60", x"c0", x"f8", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"fc", x"cc", x"0c", x"18", x"30", x"30", x"30", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"cc", x"78", x"cc", x"cc", x"78", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  *****  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:  ***    
  -- PIXELS:         
  x"78", x"cc", x"cc", x"7c", x"0c", x"18", x"70", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"c0", x"60", x"30", x"18", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"fc", x"00", x"00", x"fc", x"00", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"0c", x"18", x"30", x"60", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:         
  x"78", x"cc", x"0c", x"18", x"30", x"00", x"30", x"00",

  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:         
  x"7c", x"c6", x"de", x"de", x"de", x"c0", x"78", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"30", x"78", x"cc", x"cc", x"fc", x"cc", x"cc", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS: ******  
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"66", x"66", x"fc", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"c0", x"66", x"3c", x"00",
  -- PIXELS: *****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS: *****   
  -- PIXELS:         
  x"f8", x"6c", x"66", x"66", x"66", x"6c", x"f8", x"00",
  -- PIXELS: ******* 
  -- PIXELS:  **   * 
  -- PIXELS:  ** *   
  -- PIXELS:  ****   
  -- PIXELS:  ** *   
  -- PIXELS:  **   * 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"62", x"68", x"78", x"68", x"62", x"fe", x"00",
  -- PIXELS: ******* 
  -- PIXELS:  **   * 
  -- PIXELS:  ** *   
  -- PIXELS:  ****   
  -- PIXELS:  ** *   
  -- PIXELS:  **     
  -- PIXELS: ****    
  -- PIXELS:         
  x"fe", x"62", x"68", x"78", x"68", x"60", x"f0", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **  *** 
  -- PIXELS:  **  ** 
  -- PIXELS:   ***** 
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"ce", x"66", x"3e", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"fc", x"cc", x"cc", x"cc", x"00",
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"30", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS:    **** 
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"1e", x"0c", x"0c", x"0c", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ***  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS:  ****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS: ***  ** 
  -- PIXELS:         
  x"e6", x"66", x"6c", x"78", x"6c", x"66", x"e6", x"00",
  -- PIXELS: ****    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **   * 
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"f0", x"60", x"60", x"60", x"62", x"66", x"fe", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: *** *** 
  -- PIXELS: ******* 
  -- PIXELS: ******* 
  -- PIXELS: ** * ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"ee", x"fe", x"fe", x"d6", x"c6", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: ***  ** 
  -- PIXELS: **** ** 
  -- PIXELS: ** **** 
  -- PIXELS: **  *** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"e6", x"f6", x"de", x"ce", x"c6", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:         
  x"38", x"6c", x"c6", x"c6", x"c6", x"6c", x"38", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: ****    
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"60", x"60", x"f0", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ** ***  
  -- PIXELS:  ****   
  -- PIXELS:    ***  
  -- PIXELS:         
  x"78", x"cc", x"cc", x"cc", x"dc", x"78", x"1c", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS: ***  ** 
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"6c", x"66", x"e6", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: ***     
  -- PIXELS:  ***    
  -- PIXELS:    ***  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"e0", x"70", x"1c", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: * ** *  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"b4", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"cc", x"fc", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"78", x"30", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: ** * ** 
  -- PIXELS: ******* 
  -- PIXELS: *** *** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"c6", x"d6", x"fe", x"ee", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"6c", x"38", x"38", x"6c", x"c6", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"78", x"30", x"30", x"78", x"00",
  -- PIXELS: ******* 
  -- PIXELS: **   ** 
  -- PIXELS: *   **  
  -- PIXELS:    **   
  -- PIXELS:   **  * 
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"c6", x"8c", x"18", x"32", x"66", x"fe", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   ****  
  -- PIXELS:   ****  
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:         
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"3c", x"3c", x"18", x"18", x"00", x"18", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"6c", x"6c", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  x"6c", x"6c", x"fe", x"6c", x"fe", x"6c", x"6c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  *****  
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:     **  
  -- PIXELS: *****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"30", x"7c", x"c0", x"78", x"0c", x"f8", x"30", x"00",
  -- PIXELS:         
  -- PIXELS: **   ** 
  -- PIXELS: **  **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **  ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"00", x"c6", x"cc", x"18", x"30", x"66", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:  *** ** 
  -- PIXELS: ** ***  
  -- PIXELS: **  **  
  -- PIXELS:  *** ** 
  -- PIXELS:         
  x"38", x"6c", x"38", x"76", x"dc", x"cc", x"76", x"00",
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"60", x"60", x"c0", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"60", x"60", x"30", x"18", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"18", x"18", x"30", x"60", x"00",
  -- PIXELS:         
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS: ********
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"66", x"3c", x"ff", x"3c", x"66", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"30", x"30", x"fc", x"30", x"30", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"fc", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:      ** 
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *       
  -- PIXELS:         
  x"06", x"0c", x"18", x"30", x"60", x"c0", x"80", x"00",
  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: **  *** 
  -- PIXELS: ** **** 
  -- PIXELS: **** ** 
  -- PIXELS: ***  ** 
  -- PIXELS:  *****  
  -- PIXELS:         
  x"7c", x"c6", x"ce", x"de", x"f6", x"e6", x"7c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ***    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:         
  x"30", x"70", x"30", x"30", x"30", x"30", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"60", x"cc", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"0c", x"cc", x"78", x"00",
  -- PIXELS:    ***  
  -- PIXELS:   ****  
  -- PIXELS:  ** **  
  -- PIXELS: **  **  
  -- PIXELS: ******* 
  -- PIXELS:     **  
  -- PIXELS:    **** 
  -- PIXELS:         
  x"1c", x"3c", x"6c", x"cc", x"fe", x"0c", x"1e", x"00",
  -- PIXELS: ******  
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"c0", x"f8", x"0c", x"0c", x"cc", x"78", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"38", x"60", x"c0", x"f8", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"fc", x"cc", x"0c", x"18", x"30", x"30", x"30", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"cc", x"78", x"cc", x"cc", x"78", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  *****  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:  ***    
  -- PIXELS:         
  x"78", x"cc", x"cc", x"7c", x"0c", x"18", x"70", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"c0", x"60", x"30", x"18", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"fc", x"00", x"00", x"fc", x"00", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"0c", x"18", x"30", x"60", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:         
  x"78", x"cc", x"0c", x"18", x"30", x"00", x"30", x"00",

  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:         
  x"7c", x"c6", x"de", x"de", x"de", x"c0", x"78", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"30", x"78", x"cc", x"cc", x"fc", x"cc", x"cc", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS: ******  
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"66", x"66", x"fc", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"c0", x"66", x"3c", x"00",
  -- PIXELS: *****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS: *****   
  -- PIXELS:         
  x"f8", x"6c", x"66", x"66", x"66", x"6c", x"f8", x"00",
  -- PIXELS: ******* 
  -- PIXELS:  **   * 
  -- PIXELS:  ** *   
  -- PIXELS:  ****   
  -- PIXELS:  ** *   
  -- PIXELS:  **   * 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"62", x"68", x"78", x"68", x"62", x"fe", x"00",
  -- PIXELS: ******* 
  -- PIXELS:  **   * 
  -- PIXELS:  ** *   
  -- PIXELS:  ****   
  -- PIXELS:  ** *   
  -- PIXELS:  **     
  -- PIXELS: ****    
  -- PIXELS:         
  x"fe", x"62", x"68", x"78", x"68", x"60", x"f0", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **  *** 
  -- PIXELS:  **  ** 
  -- PIXELS:   ***** 
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"ce", x"66", x"3e", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"fc", x"cc", x"cc", x"cc", x"00",
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"30", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS:    **** 
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"1e", x"0c", x"0c", x"0c", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ***  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS:  ****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS: ***  ** 
  -- PIXELS:         
  x"e6", x"66", x"6c", x"78", x"6c", x"66", x"e6", x"00",
  -- PIXELS: ****    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **   * 
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"f0", x"60", x"60", x"60", x"62", x"66", x"fe", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: *** *** 
  -- PIXELS: ******* 
  -- PIXELS: ******* 
  -- PIXELS: ** * ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"ee", x"fe", x"fe", x"d6", x"c6", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: ***  ** 
  -- PIXELS: **** ** 
  -- PIXELS: ** **** 
  -- PIXELS: **  *** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"e6", x"f6", x"de", x"ce", x"c6", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:         
  x"38", x"6c", x"c6", x"c6", x"c6", x"6c", x"38", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: ****    
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"60", x"60", x"f0", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ** ***  
  -- PIXELS:  ****   
  -- PIXELS:    ***  
  -- PIXELS:         
  x"78", x"cc", x"cc", x"cc", x"dc", x"78", x"1c", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS: ***  ** 
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"6c", x"66", x"e6", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: ***     
  -- PIXELS:  ***    
  -- PIXELS:    ***  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"e0", x"70", x"1c", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: * ** *  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"b4", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"cc", x"fc", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"78", x"30", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: ** * ** 
  -- PIXELS: ******* 
  -- PIXELS: *** *** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"c6", x"d6", x"fe", x"ee", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"6c", x"38", x"38", x"6c", x"c6", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"78", x"30", x"30", x"78", x"00",
  -- PIXELS: ******* 
  -- PIXELS: **   ** 
  -- PIXELS: *   **  
  -- PIXELS:    **   
  -- PIXELS:   **  * 
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"c6", x"8c", x"18", x"32", x"66", x"fe", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   ****  
  -- PIXELS:   ****  
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:         
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"3c", x"3c", x"18", x"18", x"00", x"18", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"6c", x"6c", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  x"6c", x"6c", x"fe", x"6c", x"fe", x"6c", x"6c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  *****  
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:     **  
  -- PIXELS: *****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"30", x"7c", x"c0", x"78", x"0c", x"f8", x"30", x"00",
  -- PIXELS:         
  -- PIXELS: **   ** 
  -- PIXELS: **  **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **  ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"00", x"c6", x"cc", x"18", x"30", x"66", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:  *** ** 
  -- PIXELS: ** ***  
  -- PIXELS: **  **  
  -- PIXELS:  *** ** 
  -- PIXELS:         
  x"38", x"6c", x"38", x"76", x"dc", x"cc", x"76", x"00",
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"60", x"60", x"c0", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"60", x"60", x"30", x"18", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"18", x"18", x"30", x"60", x"00",
  -- PIXELS:         
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS: ********
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"66", x"3c", x"ff", x"3c", x"66", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"30", x"30", x"fc", x"30", x"30", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"fc", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:      ** 
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *       
  -- PIXELS:         
  x"06", x"0c", x"18", x"30", x"60", x"c0", x"80", x"00",
  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: **  *** 
  -- PIXELS: ** **** 
  -- PIXELS: **** ** 
  -- PIXELS: ***  ** 
  -- PIXELS:  *****  
  -- PIXELS:         
  x"7c", x"c6", x"ce", x"de", x"f6", x"e6", x"7c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ***    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:         
  x"30", x"70", x"30", x"30", x"30", x"30", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"60", x"cc", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"0c", x"cc", x"78", x"00",
  -- PIXELS:    ***  
  -- PIXELS:   ****  
  -- PIXELS:  ** **  
  -- PIXELS: **  **  
  -- PIXELS: ******* 
  -- PIXELS:     **  
  -- PIXELS:    **** 
  -- PIXELS:         
  x"1c", x"3c", x"6c", x"cc", x"fe", x"0c", x"1e", x"00",
  -- PIXELS: ******  
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"c0", x"f8", x"0c", x"0c", x"cc", x"78", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"38", x"60", x"c0", x"f8", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"fc", x"cc", x"0c", x"18", x"30", x"30", x"30", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"cc", x"78", x"cc", x"cc", x"78", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  *****  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:  ***    
  -- PIXELS:         
  x"78", x"cc", x"cc", x"7c", x"0c", x"18", x"70", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"c0", x"60", x"30", x"18", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"fc", x"00", x"00", x"fc", x"00", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"0c", x"18", x"30", x"60", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:         
  x"78", x"cc", x"0c", x"18", x"30", x"00", x"30", x"00",

  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:         
  x"7c", x"c6", x"de", x"de", x"de", x"c0", x"78", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"30", x"78", x"cc", x"cc", x"fc", x"cc", x"cc", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS: ******  
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"66", x"66", x"fc", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"c0", x"66", x"3c", x"00",
  -- PIXELS: *****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS: *****   
  -- PIXELS:         
  x"f8", x"6c", x"66", x"66", x"66", x"6c", x"f8", x"00",
  -- PIXELS: ******* 
  -- PIXELS:  **   * 
  -- PIXELS:  ** *   
  -- PIXELS:  ****   
  -- PIXELS:  ** *   
  -- PIXELS:  **   * 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"62", x"68", x"78", x"68", x"62", x"fe", x"00",
  -- PIXELS: ******* 
  -- PIXELS:  **   * 
  -- PIXELS:  ** *   
  -- PIXELS:  ****   
  -- PIXELS:  ** *   
  -- PIXELS:  **     
  -- PIXELS: ****    
  -- PIXELS:         
  x"fe", x"62", x"68", x"78", x"68", x"60", x"f0", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **  *** 
  -- PIXELS:  **  ** 
  -- PIXELS:   ***** 
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"ce", x"66", x"3e", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"fc", x"cc", x"cc", x"cc", x"00",
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"30", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS:    **** 
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"1e", x"0c", x"0c", x"0c", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ***  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS:  ****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS: ***  ** 
  -- PIXELS:         
  x"e6", x"66", x"6c", x"78", x"6c", x"66", x"e6", x"00",
  -- PIXELS: ****    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **   * 
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"f0", x"60", x"60", x"60", x"62", x"66", x"fe", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: *** *** 
  -- PIXELS: ******* 
  -- PIXELS: ******* 
  -- PIXELS: ** * ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"ee", x"fe", x"fe", x"d6", x"c6", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: ***  ** 
  -- PIXELS: **** ** 
  -- PIXELS: ** **** 
  -- PIXELS: **  *** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"e6", x"f6", x"de", x"ce", x"c6", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:         
  x"38", x"6c", x"c6", x"c6", x"c6", x"6c", x"38", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: ****    
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"60", x"60", x"f0", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ** ***  
  -- PIXELS:  ****   
  -- PIXELS:    ***  
  -- PIXELS:         
  x"78", x"cc", x"cc", x"cc", x"dc", x"78", x"1c", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS: ***  ** 
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"6c", x"66", x"e6", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: ***     
  -- PIXELS:  ***    
  -- PIXELS:    ***  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"e0", x"70", x"1c", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: * ** *  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"b4", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"cc", x"fc", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"78", x"30", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: ** * ** 
  -- PIXELS: ******* 
  -- PIXELS: *** *** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"c6", x"d6", x"fe", x"ee", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"6c", x"38", x"38", x"6c", x"c6", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"78", x"30", x"30", x"78", x"00",
  -- PIXELS: ******* 
  -- PIXELS: **   ** 
  -- PIXELS: *   **  
  -- PIXELS:    **   
  -- PIXELS:   **  * 
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"c6", x"8c", x"18", x"32", x"66", x"fe", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   ****  
  -- PIXELS:   ****  
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:         
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"3c", x"3c", x"18", x"18", x"00", x"18", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"6c", x"6c", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  x"6c", x"6c", x"fe", x"6c", x"fe", x"6c", x"6c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  *****  
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:     **  
  -- PIXELS: *****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"30", x"7c", x"c0", x"78", x"0c", x"f8", x"30", x"00",
  -- PIXELS:         
  -- PIXELS: **   ** 
  -- PIXELS: **  **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **  ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"00", x"c6", x"cc", x"18", x"30", x"66", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:  *** ** 
  -- PIXELS: ** ***  
  -- PIXELS: **  **  
  -- PIXELS:  *** ** 
  -- PIXELS:         
  x"38", x"6c", x"38", x"76", x"dc", x"cc", x"76", x"00",
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"60", x"60", x"c0", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"60", x"60", x"30", x"18", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"18", x"18", x"30", x"60", x"00",
  -- PIXELS:         
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS: ********
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"66", x"3c", x"ff", x"3c", x"66", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"30", x"30", x"fc", x"30", x"30", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"fc", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:      ** 
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *       
  -- PIXELS:         
  x"06", x"0c", x"18", x"30", x"60", x"c0", x"80", x"00",
  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: **  *** 
  -- PIXELS: ** **** 
  -- PIXELS: **** ** 
  -- PIXELS: ***  ** 
  -- PIXELS:  *****  
  -- PIXELS:         
  x"7c", x"c6", x"ce", x"de", x"f6", x"e6", x"7c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ***    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:         
  x"30", x"70", x"30", x"30", x"30", x"30", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"60", x"cc", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"0c", x"cc", x"78", x"00",
  -- PIXELS:    ***  
  -- PIXELS:   ****  
  -- PIXELS:  ** **  
  -- PIXELS: **  **  
  -- PIXELS: ******* 
  -- PIXELS:     **  
  -- PIXELS:    **** 
  -- PIXELS:         
  x"1c", x"3c", x"6c", x"cc", x"fe", x"0c", x"1e", x"00",
  -- PIXELS: ******  
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"c0", x"f8", x"0c", x"0c", x"cc", x"78", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"38", x"60", x"c0", x"f8", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"fc", x"cc", x"0c", x"18", x"30", x"30", x"30", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"cc", x"78", x"cc", x"cc", x"78", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  *****  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:  ***    
  -- PIXELS:         
  x"78", x"cc", x"cc", x"7c", x"0c", x"18", x"70", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"c0", x"60", x"30", x"18", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"fc", x"00", x"00", x"fc", x"00", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"0c", x"18", x"30", x"60", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:         
  x"78", x"cc", x"0c", x"18", x"30", x"00", x"30", x"00",

  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:         
  x"7c", x"c6", x"de", x"de", x"de", x"c0", x"78", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"30", x"78", x"cc", x"cc", x"fc", x"cc", x"cc", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS: ******  
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"66", x"66", x"fc", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"c0", x"66", x"3c", x"00",
  -- PIXELS: *****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS: *****   
  -- PIXELS:         
  x"f8", x"6c", x"66", x"66", x"66", x"6c", x"f8", x"00",
  -- PIXELS: ******* 
  -- PIXELS:  **   * 
  -- PIXELS:  ** *   
  -- PIXELS:  ****   
  -- PIXELS:  ** *   
  -- PIXELS:  **   * 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"62", x"68", x"78", x"68", x"62", x"fe", x"00",
  -- PIXELS: ******* 
  -- PIXELS:  **   * 
  -- PIXELS:  ** *   
  -- PIXELS:  ****   
  -- PIXELS:  ** *   
  -- PIXELS:  **     
  -- PIXELS: ****    
  -- PIXELS:         
  x"fe", x"62", x"68", x"78", x"68", x"60", x"f0", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **  *** 
  -- PIXELS:  **  ** 
  -- PIXELS:   ***** 
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"ce", x"66", x"3e", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"fc", x"cc", x"cc", x"cc", x"00",
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"30", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS:    **** 
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"1e", x"0c", x"0c", x"0c", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ***  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS:  ****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS: ***  ** 
  -- PIXELS:         
  x"e6", x"66", x"6c", x"78", x"6c", x"66", x"e6", x"00",
  -- PIXELS: ****    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **   * 
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"f0", x"60", x"60", x"60", x"62", x"66", x"fe", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: *** *** 
  -- PIXELS: ******* 
  -- PIXELS: ******* 
  -- PIXELS: ** * ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"ee", x"fe", x"fe", x"d6", x"c6", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: ***  ** 
  -- PIXELS: **** ** 
  -- PIXELS: ** **** 
  -- PIXELS: **  *** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"e6", x"f6", x"de", x"ce", x"c6", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:         
  x"38", x"6c", x"c6", x"c6", x"c6", x"6c", x"38", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: ****    
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"60", x"60", x"f0", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ** ***  
  -- PIXELS:  ****   
  -- PIXELS:    ***  
  -- PIXELS:         
  x"78", x"cc", x"cc", x"cc", x"dc", x"78", x"1c", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS: ***  ** 
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"6c", x"66", x"e6", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: ***     
  -- PIXELS:  ***    
  -- PIXELS:    ***  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"e0", x"70", x"1c", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: * ** *  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"b4", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"cc", x"fc", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"78", x"30", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: ** * ** 
  -- PIXELS: ******* 
  -- PIXELS: *** *** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"c6", x"d6", x"fe", x"ee", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"6c", x"38", x"38", x"6c", x"c6", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"78", x"30", x"30", x"78", x"00",
  -- PIXELS: ******* 
  -- PIXELS: **   ** 
  -- PIXELS: *   **  
  -- PIXELS:    **   
  -- PIXELS:   **  * 
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"c6", x"8c", x"18", x"32", x"66", x"fe", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   ****  
  -- PIXELS:   ****  
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:         
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"3c", x"3c", x"18", x"18", x"00", x"18", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"6c", x"6c", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  x"6c", x"6c", x"fe", x"6c", x"fe", x"6c", x"6c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  *****  
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:     **  
  -- PIXELS: *****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"30", x"7c", x"c0", x"78", x"0c", x"f8", x"30", x"00",
  -- PIXELS:         
  -- PIXELS: **   ** 
  -- PIXELS: **  **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **  ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"00", x"c6", x"cc", x"18", x"30", x"66", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:  *** ** 
  -- PIXELS: ** ***  
  -- PIXELS: **  **  
  -- PIXELS:  *** ** 
  -- PIXELS:         
  x"38", x"6c", x"38", x"76", x"dc", x"cc", x"76", x"00",
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"60", x"60", x"c0", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"60", x"60", x"30", x"18", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"18", x"18", x"30", x"60", x"00",
  -- PIXELS:         
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS: ********
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"66", x"3c", x"ff", x"3c", x"66", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"30", x"30", x"fc", x"30", x"30", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"fc", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:      ** 
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *       
  -- PIXELS:         
  x"06", x"0c", x"18", x"30", x"60", x"c0", x"80", x"00",
  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: **  *** 
  -- PIXELS: ** **** 
  -- PIXELS: **** ** 
  -- PIXELS: ***  ** 
  -- PIXELS:  *****  
  -- PIXELS:         
  x"7c", x"c6", x"ce", x"de", x"f6", x"e6", x"7c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ***    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:         
  x"30", x"70", x"30", x"30", x"30", x"30", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"60", x"cc", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"0c", x"cc", x"78", x"00",
  -- PIXELS:    ***  
  -- PIXELS:   ****  
  -- PIXELS:  ** **  
  -- PIXELS: **  **  
  -- PIXELS: ******* 
  -- PIXELS:     **  
  -- PIXELS:    **** 
  -- PIXELS:         
  x"1c", x"3c", x"6c", x"cc", x"fe", x"0c", x"1e", x"00",
  -- PIXELS: ******  
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"c0", x"f8", x"0c", x"0c", x"cc", x"78", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"38", x"60", x"c0", x"f8", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"fc", x"cc", x"0c", x"18", x"30", x"30", x"30", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"cc", x"78", x"cc", x"cc", x"78", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  *****  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:  ***    
  -- PIXELS:         
  x"78", x"cc", x"cc", x"7c", x"0c", x"18", x"70", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"c0", x"60", x"30", x"18", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"fc", x"00", x"00", x"fc", x"00", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"0c", x"18", x"30", x"60", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:         
  x"78", x"cc", x"0c", x"18", x"30", x"00", x"30", x"00",

  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:         
  x"7c", x"c6", x"de", x"de", x"de", x"c0", x"78", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"30", x"78", x"cc", x"cc", x"fc", x"cc", x"cc", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS: ******  
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"66", x"66", x"fc", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"c0", x"66", x"3c", x"00",
  -- PIXELS: *****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS: *****   
  -- PIXELS:         
  x"f8", x"6c", x"66", x"66", x"66", x"6c", x"f8", x"00",
  -- PIXELS: ******* 
  -- PIXELS:  **   * 
  -- PIXELS:  ** *   
  -- PIXELS:  ****   
  -- PIXELS:  ** *   
  -- PIXELS:  **   * 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"62", x"68", x"78", x"68", x"62", x"fe", x"00",
  -- PIXELS: ******* 
  -- PIXELS:  **   * 
  -- PIXELS:  ** *   
  -- PIXELS:  ****   
  -- PIXELS:  ** *   
  -- PIXELS:  **     
  -- PIXELS: ****    
  -- PIXELS:         
  x"fe", x"62", x"68", x"78", x"68", x"60", x"f0", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **  *** 
  -- PIXELS:  **  ** 
  -- PIXELS:   ***** 
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"ce", x"66", x"3e", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"fc", x"cc", x"cc", x"cc", x"00",
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"30", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS:    **** 
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"1e", x"0c", x"0c", x"0c", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ***  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS:  ****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS: ***  ** 
  -- PIXELS:         
  x"e6", x"66", x"6c", x"78", x"6c", x"66", x"e6", x"00",
  -- PIXELS: ****    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **   * 
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"f0", x"60", x"60", x"60", x"62", x"66", x"fe", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: *** *** 
  -- PIXELS: ******* 
  -- PIXELS: ******* 
  -- PIXELS: ** * ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"ee", x"fe", x"fe", x"d6", x"c6", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: ***  ** 
  -- PIXELS: **** ** 
  -- PIXELS: ** **** 
  -- PIXELS: **  *** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"e6", x"f6", x"de", x"ce", x"c6", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:         
  x"38", x"6c", x"c6", x"c6", x"c6", x"6c", x"38", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: ****    
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"60", x"60", x"f0", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ** ***  
  -- PIXELS:  ****   
  -- PIXELS:    ***  
  -- PIXELS:         
  x"78", x"cc", x"cc", x"cc", x"dc", x"78", x"1c", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS: ***  ** 
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"6c", x"66", x"e6", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: ***     
  -- PIXELS:  ***    
  -- PIXELS:    ***  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"e0", x"70", x"1c", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: * ** *  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"b4", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"cc", x"fc", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"78", x"30", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: ** * ** 
  -- PIXELS: ******* 
  -- PIXELS: *** *** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"c6", x"d6", x"fe", x"ee", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"6c", x"38", x"38", x"6c", x"c6", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"78", x"30", x"30", x"78", x"00",
  -- PIXELS: ******* 
  -- PIXELS: **   ** 
  -- PIXELS: *   **  
  -- PIXELS:    **   
  -- PIXELS:   **  * 
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"c6", x"8c", x"18", x"32", x"66", x"fe", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   ****  
  -- PIXELS:   ****  
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:         
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"3c", x"3c", x"18", x"18", x"00", x"18", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"6c", x"6c", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  x"6c", x"6c", x"fe", x"6c", x"fe", x"6c", x"6c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  *****  
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:     **  
  -- PIXELS: *****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"30", x"7c", x"c0", x"78", x"0c", x"f8", x"30", x"00",
  -- PIXELS:         
  -- PIXELS: **   ** 
  -- PIXELS: **  **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **  ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"00", x"c6", x"cc", x"18", x"30", x"66", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:  *** ** 
  -- PIXELS: ** ***  
  -- PIXELS: **  **  
  -- PIXELS:  *** ** 
  -- PIXELS:         
  x"38", x"6c", x"38", x"76", x"dc", x"cc", x"76", x"00",
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"60", x"60", x"c0", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"60", x"60", x"30", x"18", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"18", x"18", x"30", x"60", x"00",
  -- PIXELS:         
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS: ********
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"66", x"3c", x"ff", x"3c", x"66", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"30", x"30", x"fc", x"30", x"30", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"fc", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:      ** 
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *       
  -- PIXELS:         
  x"06", x"0c", x"18", x"30", x"60", x"c0", x"80", x"00",
  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: **  *** 
  -- PIXELS: ** **** 
  -- PIXELS: **** ** 
  -- PIXELS: ***  ** 
  -- PIXELS:  *****  
  -- PIXELS:         
  x"7c", x"c6", x"ce", x"de", x"f6", x"e6", x"7c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ***    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:         
  x"30", x"70", x"30", x"30", x"30", x"30", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"60", x"cc", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"0c", x"cc", x"78", x"00",
  -- PIXELS:    ***  
  -- PIXELS:   ****  
  -- PIXELS:  ** **  
  -- PIXELS: **  **  
  -- PIXELS: ******* 
  -- PIXELS:     **  
  -- PIXELS:    **** 
  -- PIXELS:         
  x"1c", x"3c", x"6c", x"cc", x"fe", x"0c", x"1e", x"00",
  -- PIXELS: ******  
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"c0", x"f8", x"0c", x"0c", x"cc", x"78", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"38", x"60", x"c0", x"f8", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"fc", x"cc", x"0c", x"18", x"30", x"30", x"30", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"cc", x"78", x"cc", x"cc", x"78", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  *****  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:  ***    
  -- PIXELS:         
  x"78", x"cc", x"cc", x"7c", x"0c", x"18", x"70", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"c0", x"60", x"30", x"18", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"fc", x"00", x"00", x"fc", x"00", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"0c", x"18", x"30", x"60", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:         
  x"78", x"cc", x"0c", x"18", x"30", x"00", x"30", x"00",

  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: ** **** 
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:         
  x"7c", x"c6", x"de", x"de", x"de", x"c0", x"78", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"30", x"78", x"cc", x"cc", x"fc", x"cc", x"cc", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS: ******  
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"66", x"66", x"fc", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"c0", x"66", x"3c", x"00",
  -- PIXELS: *****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS: *****   
  -- PIXELS:         
  x"f8", x"6c", x"66", x"66", x"66", x"6c", x"f8", x"00",
  -- PIXELS: ******* 
  -- PIXELS:  **   * 
  -- PIXELS:  ** *   
  -- PIXELS:  ****   
  -- PIXELS:  ** *   
  -- PIXELS:  **   * 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"62", x"68", x"78", x"68", x"62", x"fe", x"00",
  -- PIXELS: ******* 
  -- PIXELS:  **   * 
  -- PIXELS:  ** *   
  -- PIXELS:  ****   
  -- PIXELS:  ** *   
  -- PIXELS:  **     
  -- PIXELS: ****    
  -- PIXELS:         
  x"fe", x"62", x"68", x"78", x"68", x"60", x"f0", x"00",
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS: **      
  -- PIXELS: **      
  -- PIXELS: **  *** 
  -- PIXELS:  **  ** 
  -- PIXELS:   ***** 
  -- PIXELS:         
  x"3c", x"66", x"c0", x"c0", x"ce", x"66", x"3e", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"fc", x"cc", x"cc", x"cc", x"00",
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"30", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS:    **** 
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"1e", x"0c", x"0c", x"0c", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ***  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  ** **  
  -- PIXELS:  ****   
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS: ***  ** 
  -- PIXELS:         
  x"e6", x"66", x"6c", x"78", x"6c", x"66", x"e6", x"00",
  -- PIXELS: ****    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **   * 
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"f0", x"60", x"60", x"60", x"62", x"66", x"fe", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: *** *** 
  -- PIXELS: ******* 
  -- PIXELS: ******* 
  -- PIXELS: ** * ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"ee", x"fe", x"fe", x"d6", x"c6", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: ***  ** 
  -- PIXELS: **** ** 
  -- PIXELS: ** **** 
  -- PIXELS: **  *** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"e6", x"f6", x"de", x"ce", x"c6", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:         
  x"38", x"6c", x"c6", x"c6", x"c6", x"6c", x"38", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: ****    
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"60", x"60", x"f0", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ** ***  
  -- PIXELS:  ****   
  -- PIXELS:    ***  
  -- PIXELS:         
  x"78", x"cc", x"cc", x"cc", x"dc", x"78", x"1c", x"00",
  -- PIXELS: ******  
  -- PIXELS:  **  ** 
  -- PIXELS:  **  ** 
  -- PIXELS:  *****  
  -- PIXELS:  ** **  
  -- PIXELS:  **  ** 
  -- PIXELS: ***  ** 
  -- PIXELS:         
  x"fc", x"66", x"66", x"7c", x"6c", x"66", x"e6", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: ***     
  -- PIXELS:  ***    
  -- PIXELS:    ***  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"e0", x"70", x"1c", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: * ** *  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"b4", x"30", x"30", x"30", x"30", x"78", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"cc", x"fc", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"cc", x"cc", x"78", x"30", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS: ** * ** 
  -- PIXELS: ******* 
  -- PIXELS: *** *** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"c6", x"d6", x"fe", x"ee", x"c6", x"00",
  -- PIXELS: **   ** 
  -- PIXELS: **   ** 
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"c6", x"c6", x"6c", x"38", x"38", x"6c", x"c6", x"00",
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  ****   
  -- PIXELS:         
  x"cc", x"cc", x"cc", x"78", x"30", x"30", x"78", x"00",
  -- PIXELS: ******* 
  -- PIXELS: **   ** 
  -- PIXELS: *   **  
  -- PIXELS:    **   
  -- PIXELS:   **  * 
  -- PIXELS:  **  ** 
  -- PIXELS: ******* 
  -- PIXELS:         
  x"fe", x"c6", x"8c", x"18", x"32", x"66", x"fe", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   ****  
  -- PIXELS:   ****  
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:         
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"3c", x"3c", x"18", x"18", x"00", x"18", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"6c", x"6c", x"00", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS: ******* 
  -- PIXELS:  ** **  
  -- PIXELS:  ** **  
  -- PIXELS:         
  x"6c", x"6c", x"fe", x"6c", x"fe", x"6c", x"6c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  *****  
  -- PIXELS: **      
  -- PIXELS:  ****   
  -- PIXELS:     **  
  -- PIXELS: *****   
  -- PIXELS:   **    
  -- PIXELS:         
  x"30", x"7c", x"c0", x"78", x"0c", x"f8", x"30", x"00",
  -- PIXELS:         
  -- PIXELS: **   ** 
  -- PIXELS: **  **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **  ** 
  -- PIXELS: **   ** 
  -- PIXELS:         
  x"00", x"c6", x"cc", x"18", x"30", x"66", x"c6", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  ** **  
  -- PIXELS:   ***   
  -- PIXELS:  *** ** 
  -- PIXELS: ** ***  
  -- PIXELS: **  **  
  -- PIXELS:  *** ** 
  -- PIXELS:         
  x"38", x"6c", x"38", x"76", x"dc", x"cc", x"76", x"00",
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"60", x"60", x"c0", x"00", x"00", x"00", x"00", x"00",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"60", x"60", x"30", x"18", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"18", x"18", x"30", x"60", x"00",
  -- PIXELS:         
  -- PIXELS:  **  ** 
  -- PIXELS:   ****  
  -- PIXELS: ********
  -- PIXELS:   ****  
  -- PIXELS:  **  ** 
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"66", x"3c", x"ff", x"3c", x"66", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"30", x"30", x"fc", x"30", x"30", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"00", x"fc", x"00", x"00", x"00", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"00", x"00", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:      ** 
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *       
  -- PIXELS:         
  x"06", x"0c", x"18", x"30", x"60", x"c0", x"80", x"00",
  -- PIXELS:  *****  
  -- PIXELS: **   ** 
  -- PIXELS: **  *** 
  -- PIXELS: ** **** 
  -- PIXELS: **** ** 
  -- PIXELS: ***  ** 
  -- PIXELS:  *****  
  -- PIXELS:         
  x"7c", x"c6", x"ce", x"de", x"f6", x"e6", x"7c", x"00",
  -- PIXELS:   **    
  -- PIXELS:  ***    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS: ******  
  -- PIXELS:         
  x"30", x"70", x"30", x"30", x"30", x"30", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **  **  
  -- PIXELS: ******  
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"60", x"cc", x"fc", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:   ***   
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"0c", x"38", x"0c", x"cc", x"78", x"00",
  -- PIXELS:    ***  
  -- PIXELS:   ****  
  -- PIXELS:  ** **  
  -- PIXELS: **  **  
  -- PIXELS: ******* 
  -- PIXELS:     **  
  -- PIXELS:    **** 
  -- PIXELS:         
  x"1c", x"3c", x"6c", x"cc", x"fe", x"0c", x"1e", x"00",
  -- PIXELS: ******  
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS:     **  
  -- PIXELS:     **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"fc", x"c0", x"f8", x"0c", x"0c", x"cc", x"78", x"00",
  -- PIXELS:   ***   
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS: *****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"38", x"60", x"c0", x"f8", x"cc", x"cc", x"78", x"00",
  -- PIXELS: ******  
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"fc", x"cc", x"0c", x"18", x"30", x"30", x"30", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  ****   
  -- PIXELS:         
  x"78", x"cc", x"cc", x"78", x"cc", x"cc", x"78", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS: **  **  
  -- PIXELS:  *****  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:  ***    
  -- PIXELS:         
  x"78", x"cc", x"cc", x"7c", x"0c", x"18", x"70", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"00",
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:   **    
  -- PIXELS:  **     
  x"00", x"30", x"30", x"00", x"00", x"30", x"30", x"60",
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS: **      
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:         
  x"18", x"30", x"60", x"c0", x"60", x"30", x"18", x"00",
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  -- PIXELS: ******  
  -- PIXELS:         
  -- PIXELS:         
  x"00", x"00", x"fc", x"00", x"00", x"fc", x"00", x"00",
  -- PIXELS:  **     
  -- PIXELS:   **    
  -- PIXELS:    **   
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:  **     
  -- PIXELS:         
  x"60", x"30", x"18", x"0c", x"18", x"30", x"60", x"00",
  -- PIXELS:  ****   
  -- PIXELS: **  **  
  -- PIXELS:     **  
  -- PIXELS:    **   
  -- PIXELS:   **    
  -- PIXELS:         
  -- PIXELS:   **    
  -- PIXELS:         
  x"78", x"cc", x"0c", x"18", x"30", x"00", x"30", x"00",
);

begin

--process for read and write operation.
PROCESS(Clk)
BEGIN
  --report "viciv reading charrom address $"
  --  & to_hstring(address)
  --  & " = " & integer'image(to_integer(address))
  --  & " -> $" & to_hstring(ram(to_integer(address)))
  --  severity note;
  data_o <= ram(address);          

  if(rising_edge(writeClk)) then 
    if writecs='1' then
      if(we='1') then
            ram(to_integer(writeaddress)) <= data_i;
      end if;
    end if;
  end if;
END PROCESS;

end Behavioral;
