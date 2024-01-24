use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

-- library UNISIM;
-- use UNISIM.vcomponents.all;


entity reconfig is
  port (
    clock : in std_logic;
    reg_num : in unsigned(4 downto 0) := "01001";
    trigger_reconfigure : in std_logic;
    reconfigure_address : in unsigned(31 downto 0) := x"00000000";
    boot_address : out unsigned(31 downto 0) := x"FFFFFFFF"
    );
end reconfig;

architecture dummy of reconfig is

begin
  
end dummy;
