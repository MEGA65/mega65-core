library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity sdcard_model is
  port ( clock : in std_logic;
         cs_bo : in std_logic;
         sclk_o : in std_logic;
         mosi_o : in std_logic;
         miso_i : out std_logic
         );
  
end entity;

architecture cheap_imitation of sdcard_model is  

begin
  
end cheap_imitation;
