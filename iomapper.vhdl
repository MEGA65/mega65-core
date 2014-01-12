use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity iomapper is
  port (Clk : in std_logic;
        address : in std_logic_vector(19 downto 0);
        r : in std_logic;
        w : in std_logic;
        data_i : in std_logic_vector(7 downto 0);
        data_o : out std_logic_vector(7 downto 0)
        );
end iomapper;

architecture behavioral of iomapper is
  component kernel65 is
    port (
      Clk : in std_logic;
      address : in std_logic_vector(12 downto 0);
      we : in std_logic;
      cs : in std_logic;
      data_i : in std_logic_vector(7 downto 0);
      data_o : out std_logic_vector(7 downto 0));
  end component;

  signal kernel65cs : std_logic;
begin         
  kernel65rom : kernel65 port map (
    clk     => clk,
    address => address(12 downto 0),
    we      => w,
    cs      => kernel65cs,
    data_i  => data_i,
    data_o  => data_o);

  process (clk)
  begin  -- process
--    if clk='1' then
--      if kernel65cs = '1' then
--        report "kernel65 selected" severity note;
--      end if;
--      report "fastio_read=" & std_logic'image(r) severity note;
--      report "fastio_write=" & std_logic'image(w) severity note;
--      report "address="& to_string(address) severity note;
--    end if;
  end process;
  kernel65cs <= ( r or w )
                and address(19)
                and address(18)
                and address(17)
                and address(16)
                and address(15)
                and address(14)
                and address(13);

end behavioral;
