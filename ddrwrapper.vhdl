-------------------------------------------------------------------------------
-- temporary component getting rid of the bulk of the:
-- ddrcontroller user state machine,
-- ddrcontroller MIG core,
-- ddrcontroller dual port ram,
--
-- replacing with simple feedback of signals
-- and removing external interface to DDR chip
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;

entity ddrwrapper is
  port (
    -- Common
    cpuclock      : in std_logic;
    clk_200MHz_i  : in    std_logic; -- 200 MHz system clock
    rst_i         : in    std_logic; -- active high system reset
    device_temp_i : in    std_logic_vector(11 downto 0);
    ddr_state     : out unsigned(7 downto 0);
    ddr_counter   : out unsigned(7 downto 0);
    
    -- RAM interface
    ram_address          : in    std_logic_vector(26 downto 0);
    ram_write_data       : in    std_logic_vector(7 downto 0);
    ram_address_reflect  : out   std_logic_vector(26 downto 0);
    ram_write_reflect    : out    std_logic_vector(7 downto 0);
    ram_write_enable     : in    std_logic;
    ram_request_toggle   : in    std_logic;
    ram_done_toggle      : out   std_logic := '0';

    -- simple-dual-port cache RAM interface so that CPU doesn't have to read
    -- data cross-clock
    cache_address        : in std_logic_vector(8 downto 0);
    cache_read_data      : out std_logic_vector(150 downto 0)
    
    );
end ddrwrapper;

architecture Behavioral of ddrwrapper is


  
begin



------------------------------------------------------------------------
-- Outputs become a combination of inputs
------------------------------------------------------------------------
  process(cpuclock)
  begin
    if rising_edge(cpuclock) then
		-- return the temp as the DDR_*
	   ddr_state   <= unsigned(device_temp_i(7  downto 0));
		ddr_counter <= unsigned(device_temp_i(11 downto 4));
		-- return the ins as outs
		ram_address_reflect <= ram_address;
		ram_write_reflect   <= ram_write_data;
		-- just combine these
      ram_done_toggle <= ram_write_enable or ram_request_toggle;
		-- need to fill the 0..150 bits with something
		cache_read_data <= cache_address & cache_address & -- +9 +9 = 18
		                   cache_address & cache_address & -- +9 +9 = 36
		                   cache_address & cache_address & -- +9 +9 = 54
		                   cache_address & cache_address & -- +9 +9 = 72
		                   cache_address & cache_address & -- +9 +9 = 90
		                   cache_address & cache_address & -- +9 +9 = 108
		                   cache_address & cache_address & -- +9 +9 = 126
		                   cache_address & cache_address & -- +9 +9 = 144
		                   cache_address(6 downto 0);        -- +7    = 151
    end if;
  end process;

end behavioral;
