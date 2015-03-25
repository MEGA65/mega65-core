library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

--
entity slowram is
  port (address : in std_logic_vector(26 downto 0);
        datain : in std_logic_vector(7 downto 0);
        request_toggle : in std_logic;
        done_toggle : out std_logic;
        cache_address : in std_logic_vector(8 downto 0);
        we : in std_logic;
        cache_read_data : out std_logic_vector(150 downto 0)
        );
end slowram;

architecture Behavioral of slowram is
begin
  --process for read and write operation.
  PROCESS(request_toggle)
  BEGIN
    -- XXX : Slowram model does nothing but acknowledge requests
    done_toggle <= request_toggle;
  END PROCESS;

end Behavioral;
