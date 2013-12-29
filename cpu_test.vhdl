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

begin  -- behavior
  CPU0: entity container port map (clock,reset,irq,nmi,monitor_pc);      
  process
  begin  -- process tb
    for i in 1 to 10 loop
      clock <= '1';
      report "clock=1" severity note;
      wait for 10 ns;
      clock <= '0';
      report "clock=0" severity note;
      wait for 10 ns;      
    end loop;  -- i
    reset <= '1';
    report "reset released" severity note;
    for i in 1 to 1000000 loop
      clock <= '1';
      report "clock=1" severity note;
      wait for 10 ns;
      clock <= '0';
      report "clock=0" severity note;
      wait for 10 ns;      
    end loop;  -- i
    
  end process;
end behavior;

