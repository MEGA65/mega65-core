
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use ieee.math_real.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_example is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_example is

  type test_vector is record
    n : natural;
    d : natural;
  end record;

  type test_vectors is array(natural range <>) of test_vector;


  signal clock : std_logic := '0';
  signal div_n : unsigned(31 downto 0);
  signal div_d : unsigned(31 downto 0);
  signal div_q : unsigned(63 downto 0);
  signal div_start_over : std_logic := '0';
  signal div_busy : std_logic := '0';

  signal diff_one_count : natural := 0;

  constant v : test_vectors := (
    (5211, 193),
    (28560,10),
    (1, 64),
    (1, 256),
    (1, 100),
    (25704, 9)
  );

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

    pure function get_expected_result(n : natural; d : natural) return unsigned is
      variable quot_real : real;
      variable frac_real : real;
      variable res_slv : unsigned(63 downto 0);
    begin
      quot_real := real(n) / real(d);
      res_slv(63 downto 32) := to_unsigned(integer(floor(quot_real)), 32);
      frac_real := quot_real - floor(quot_real);
      if frac_real < 0.5 then
        res_slv(31 downto 0) := to_unsigned(integer(frac_real * 2.0**32), 32);
      else
        res_slv(31 downto 0) := "1" & to_unsigned(integer((frac_real-0.5) * 2.0**32), 31);
      end if;
      return res_slv;
    end function get_expected_result;

    procedure verify(n : natural; d : natural) is
      variable res_slv : unsigned(63 downto 0);
      variable diff : unsigned(63 downto 0) := (others => '0');
    begin
      report "Testing " & to_string(n) & "/" & to_string(d);
      res_slv := get_expected_result(n, d);
      report "Expecting " & to_hstring(res_slv(63 downto 32)) & "." & to_hstring(res_slv(31 downto 0));

      div_n <= to_unsigned(n, 32);
      div_d <= to_unsigned(d, 32);
      div_start_over <= '1';
      for tick in 1 to 16 loop
        clock <= '0'; wait for 10 ns;
        clock <= '1'; wait for 10 ns;
        div_start_over <= '0';
      end loop;
      assert div_busy='0'
        report "Divider still busy after 16 clocks";
      if div_q > res_slv then
        diff := div_q - res_slv;
      end if;
      if div_q < res_slv then
        diff := res_slv - div_q;
      end if;
      assert diff = 0 or diff = 1
        report "Wrong result: Got:" & to_hstring(div_q) & ", expected:" & to_hstring(res_slv);
      if diff = 1 then
        diff_one_count <= diff_one_count + 1;
        report "diff encountered";
      end if;

    end procedure verify;

  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      if run("Divider passes collected test values") then
        for n in 1 to 100 loop
          verify(n, 7);
          verify(n, 8);
          verify(n, 9);
        end loop;

        for d in 1 to 100 loop
          verify(7, d);
          verify(8, d);
          verify(9, d);
        end loop;

        for i in 0 to v'length-1 loop
          verify(v(i).n, v(i).d);
        end loop;

        assert diff_one_count = 0
          report to_string(diff_one_count) & " rounding errors detected";
        report "No errors detected";
      end if;
    end loop;

    test_runner_cleanup(runner); -- Simulation ends here
  end process;

end architecture;

