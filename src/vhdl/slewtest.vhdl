----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    22:30:37 12/10/2013 
-- Design Name: 
-- Module Name:    container - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;

library unisim;
use unisim.vcomponents.all;


-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity container is
  Port ( CLK_IN : STD_LOGIC;         
         btnCpuReset : in  STD_LOGIC;
         
         ----------------------------------------------------------------------
         -- PMODs for LCD screen and associated things during testing
         ----------------------------------------------------------------------
         jalo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jahi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jblo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jbhi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jclo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jchi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jdlo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jdhi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jxadc : inout std_logic_vector(7 downto 0) := (others => 'Z');
         
         ----------------------------------------------------------------------
         -- Debug interfaces on Nexys4 board
         ----------------------------------------------------------------------
         led : out std_logic_vector(15 downto 0) := (others => '1');
         sw : in std_logic_vector(15 downto 0);
         btn : in std_logic_vector(4 downto 0);

         UART_TXD : out std_logic := '1';
         RsRx : in std_logic
         
         );
end container;

architecture Behavioral of container is

  signal pixelclock : std_logic;
  signal cpuclock : std_logic;
  signal clock240 : std_logic;
  signal clock120 : std_logic;
  signal ethclock : std_logic;
  signal clock200 : std_logic;
  signal clock30 : std_logic;
  signal clock30in : std_logic := '0';
  signal clock30count : integer range 0 to 2 := 0;
  
  signal pal50_select : std_logic;

begin
  
  dotclock1: entity work.dotclock100
    port map ( clk_in1 => CLK_IN,
               clock80 => pixelclock, -- 80MHz
               clock40 => cpuclock, -- 40MHz
               clock50 => ethclock,
               clock200 => clock200,
               clock120 => clock120,
               clock240 => clock240
               );

  -- Expose clock on pins with different settings
  jblo(1) <= not clock30 when pal50_select='1' else not cpuclock;
  jblo(2) <= not clock30 when pal50_select='1' else not cpuclock;
  jblo(3) <= not clock30 when pal50_select='1' else not cpuclock;
  jblo(4) <= not clock30 when pal50_select='1' else not cpuclock;
  jalo(1) <= not clock30in when pal50_select='1' else not cpuclock;
  jalo(2) <= not clock30in when pal50_select='1' else not cpuclock;
  jalo(3) <= not clock30in when pal50_select='1' else not cpuclock;
  jalo(4) <= not clock30in when pal50_select='1' else not cpuclock;
  pal50_select <= btnCpuReset;
  

  -- Create BUFG'd 30MHz clock for LCD panel
  --------------------------------------
  clkin30_buf : IBUFG
  port map
   (O => clock30,
    I => clock30in);
  
  process (clock240)
  begin
    if rising_edge(clock240) then
      if (clock30count /= 2 ) then
        clock30count <= clock30count + 1;
      else
        clock30in <= not clock30in;
        clock30count <= 0;
      end if;
    end if;
  end process;
  
end Behavioral;
