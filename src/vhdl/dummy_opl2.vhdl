use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity opl2 is

  port (
    clk : in std_logic;
    reset : in std_logic;
    opl2_we : in std_logic;
    opl2_data : in unsigned(7 downto 0);
    opl2_adr : in unsigned(7 downto 0);
    kon : out std_logic_vector(8 downto 0);
    channel_a : out signed(15 downto 0);
    channel_b : out signed(15 downto 0);
    sample_clk : out std_logic;
    sample_clk_128 : out std_logic
    );
end opl2;

architecture cardboard_facade of opl2 is
begin
  
end cardboard_facade;
