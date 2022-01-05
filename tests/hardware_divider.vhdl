
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_example is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_example is

  type test_vector is record
    n : unsigned(31 downto 0);
    d : unsigned(31 downto 0);
    q_expected : unsigned(63 downto 0);
  end record;

  type test_vectors is array(0 to 999) of test_vector;

  
  signal clock : std_logic := '0';
  signal div_n : unsigned(31 downto 0);
  signal div_d : unsigned(31 downto 0);
  signal div_q : unsigned(63 downto 0);
  signal div_start_over : std_logic := '0';  
  signal div_busy : std_logic := '0';  
  
  signal v : test_vectors := (
    0 => (n=>x"00000001",d=>x"00000040",q_expected=>x"0000000004000000"),
    1 => (n=>x"00000001",d=>x"00000100",q_expected=>x"0000000001000000"),
    2 => (n=>x"80000000",d=>x"C0000000",q_expected=>x"00000000AAAAAAAA"),
    --2 => (n=>x"00000001",d=>x"00000064",q_expected=>x"00000000028f5c28"),
    others => (n=>to_unsigned(0,32), d=>to_unsigned(0,32), q_expected=>to_unsigned(0,64)));
  
begin

  fd0: entity work.fast_divide
    port map (
      clock => clock,
      n => div_n,
      d => div_d,
      q => div_q,
      start_over => div_start_over,
      busy => div_busy
      );

  
  main : process
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      if run("Divider passes collected test values") then

        for i in 0 to 999 loop
          if v(i).n /= to_unsigned(0,32) or v(i).d /= to_unsigned(0,32) or v(i).q_expected /= to_unsigned(0,64) then
            div_n <= v(i).n;
            div_d <= v(i).d;
            div_start_over <= '1';
            for tick in 1 to 16 loop
              clock <= '0'; wait for 10 ns;
              clock <= '1'; wait for 10 ns;
              div_start_over <= '0';
            end loop;
            if div_busy='1' then
              assert false report "Divider still busy after 5 clocks";
            end if;
            if div_q /= v(i).q_expected then
              assert false report "Test vector #" & integer'image(i) & " FAIL: " &
                "Dividing $" & to_hstring(v(i).n) & " / $" & to_hstring(v(i).d)
                & " yielded $" & to_hstring(div_q(63 downto 32)) & "." & to_hstring(div_q(31 downto 0))
                & " instead of correct result $" & to_hstring(v(i).q_expected(63 downto 32))
                & "." & to_hstring(v(i).q_expected(31 downto 0));
            else
              report "Test vector #" & integer'image(i) & " SUCCESS: Dividing $" & to_hstring(v(i).n) & " / $" & to_hstring(v(i).d)
                & " yielded $" & to_hstring(div_q(63 downto 32)) & "." & to_hstring(div_q(31 downto 0));
            end if;
          end if;
        end loop;
        
        report "No errors detected";

      end if;
    end loop;
    
    test_runner_cleanup(runner); -- Simulation ends here
  end process;
end architecture;

  
