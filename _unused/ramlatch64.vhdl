use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity ramlatch64 is
  port (
    fastclock : in std_logic;
    slowclock : in std_logic;
    
    address_in : in std_logic_vector(13 downto 0);
    wea_in : in std_logic_vector(7 downto 0);
    data_in : in std_logic_vector(63 downto 0);
    
    address_out : out std_logic_vector(13 downto 0);
    wea_out : out std_logic_vector(7 downto 0);
    data_out : out std_logic_vector(63 downto 0)
    );
end ramlatch64;

architecture behavioural of ramlatch64 is
  signal address_internal : std_logic_vector(13 downto 0);
  signal wea_internal : std_logic_vector(7 downto 0);
  signal data_internal : std_logic_vector(63 downto 0);
begin  -- behavioural

  -- purpose: copy address, write enable and write data lines on rising edge of slow clock
  -- type   : combinational
  -- inputs : slowclock, address_in, wea_in, data_in
  -- outputs: *_out
  
  process (slowclock, address_in, wea_in, data_in)
  begin  -- process
    if wea_internal="00000000" then
      address_out <= address_in;
    end if;
    if rising_edge(slowclock) then
      address_internal <= address_in;
      wea_internal <= wea_in;
      data_internal <= data_in;
    end if;
    if rising_edge(fastclock) then
      if wea_internal/="00000000" then
        address_out <= address_internal;
      end if;
      wea_out <= wea_internal;
      data_out <= data_internal;
    end if;
  end process;

end behavioural;

    
