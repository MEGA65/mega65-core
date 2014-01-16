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
  component kernel64 is
    port (
      Clk : in std_logic;
      address : in std_logic_vector(12 downto 0);
      we : in std_logic;
      cs : in std_logic;
      data_i : in std_logic_vector(7 downto 0);
      data_o : out std_logic_vector(7 downto 0));
  end component;
  component basic64 is
    port (
      Clk : in std_logic;
      address : in std_logic_vector(12 downto 0);
      we : in std_logic;
      cs : in std_logic;
      data_i : in std_logic_vector(7 downto 0);
      data_o : out std_logic_vector(7 downto 0));
  end component;

  signal kernel65cs : std_logic;
  signal kernel64cs : std_logic;
  signal basic64cs : std_logic;
begin         
  kernel65rom : kernel65 port map (
    clk     => clk,
    address => address(12 downto 0),
    we      => w,
    cs      => kernel65cs,
    data_i  => data_i,
    data_o  => data_o);

  kernel64rom : kernel64 port map (
    clk     => clk,
    address => address(12 downto 0),
    we      => w,
    cs      => kernel64cs,
    data_i  => data_i,
    data_o  => data_o);

  basic64rom : basic64 port map (
    clk     => clk,
    address => address(12 downto 0),
    we      => w,
    cs      => basic64cs,
    data_i  => data_i,
    data_o  => data_o);

  process (r,w,address)
  begin  -- process
    if (r or w) = '1' then
      if address(19 downto 13)&'0' = x"FE" then
        kernel65cs<= '1';
      else
        kernel65cs <='0';
      end if;
      if address(19 downto 13)&'0' = x"EE" then
        kernel64cs<= '1';
      else
        kernel64cs <='0';
      end if;
      if address(19 downto 13)&'0' = x"EA" then
        basic64cs<= '1';
      else
        basic64cs <='0';
      end if;
    else
      kernel65cs <= '0';
      kernel64cs <= '0';
      basic64cs <= '0';
    end if;
  end process;

end behavioral;
