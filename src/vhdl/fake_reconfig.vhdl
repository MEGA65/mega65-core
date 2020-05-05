use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;


entity reconfig is
  port (
    clock : in std_logic;
    reg_num : in unsigned(4 downto 0) := "01001";
    trigger_reconfigure : in std_logic;
    reconfigure_address : in unsigned(31 downto 0) := x"00000000";
    boot_address : out unsigned(31 downto 0) := x"FFFFFFFF"
    );
end reconfig;

architecture behavioural of reconfig is

  signal icape_out : unsigned(31 downto 0);
  signal icape_in : unsigned(31 downto 0);
  signal cs : std_logic := '1'; -- interface active when low
  signal rw : std_logic := '1'; -- Read or _Write

begin


end behavioural;
