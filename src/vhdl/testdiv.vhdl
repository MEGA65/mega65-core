library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity testdiv is
end entity;

architecture foo of testdiv is

  signal clock : std_logic := '1';

  signal counter : unsigned(31 downto 0) := x"00000000";

  signal n : unsigned(31 downto 0);
  signal d : unsigned(31 downto 0);
  signal q : unsigned(63 downto 0);

  signal start_over : std_logic := '0';
  signal busy : std_logic := '0';  
  
begin

  fd0: entity work.fast_divide
    port map (
      clock => clock,
      n => n,
      d => d,
      q => q,
      start_over => start_over,
      busy => busy
      );

  process is
  begin
    clock <= '1';
    wait for 20 ns;
    clock <= '0';
    wait for 20 ns;

    if busy = '0' then
      d <= counter;
      counter <= counter + 1;
      n <= to_unsigned(1024,32);
      start_over <= '1';

      report "quotient = $" & to_hstring(q(63 downto 32)) & "." & to_hstring(q(31 downto 0));
    else
      start_over <= '0';
    end if;

    
  end process;

end foo;
