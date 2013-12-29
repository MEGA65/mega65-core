library ieee;
USE ieee.std_logic_1164.ALL;
use work.all;

entity cpu_test is
  
end cpu_test;

architecture behavior of cpu_test is
signal clock : std_logic := '0';
signal reset : std_logic := '0';
signal irq : std_logic := '1';
signal nmi : std_logic := '1';
signal monitor_pc : std_logic_vector(15 downto 0);

component container
    Port ( CLK_IN : STD_LOGIC;
           reset : in  STD_LOGIC;
           irq : in  STD_LOGIC;
           nmi : in  STD_LOGIC;
           monitor_pc : out STD_LOGIC_VECTOR(15 downto 0)
           );
end component;

begin  -- behavior
  CPU0: component container port map (clock,reset,irq,nmi,monitor_pc);      
  process
  begin  -- process tb
    for i in 1 to 10 loop
      clock <= '1';
      report "clock=1 (reset)" severity note;
      wait for 10 ns;
      clock <= '0';
      report "clock=0 (reset)" severity note;
      wait for 10 ns;      
    end loop;  -- i
    reset <= '1';
    report "reset released" severity note;
    for i in 1 to 1000 loop
      clock <= '1';
      report "clock=1 (run)" severity note;
      wait for 10 ns;
      clock <= '0';
      report "clock=0 (run)" severity note;
      wait for 10 ns;      
    end loop;  -- i
    assert false report "End of simulation" severity failure;
  end process;
end behavior;

