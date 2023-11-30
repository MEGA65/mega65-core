library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_r5_i2c is
  generic (runner_cfg : string);
end entity;

architecture test_arch of tb_r5_i2c is

  signal clock41 : std_logic := '0';

  signal ear_watering_mode : std_logic := '0';
  signal sda : std_logic;
  signal scl : std_logic;
  signal dipsw_read : std_logic_vector(7 downto 0);
  signal board_major : unsigned(3 downto 0);
  signal board_minor : unsigned(3 downto 0);

  signal port0 : unsigned(7 downto 0) := x"00";
  signal port1 : unsigned(7 downto 0) := x"50";
  
begin

  pca0: entity work.pca9555
    generic map ( clock_frequency => 40_500_000,
                  address => b"1100001"
                  )
    port map ( clock => clock41,
               reset => '0',
               scl => scl,
               sda => sda,
               port0 => port0,
               port1 => port1);
  
  unit0: entity work.mega65r5_board_i2c
    generic map (clock_frequency => 40_500_000 )
    port map ( clock => clock41,
               ear_watering_mode => ear_watering_mode,
               sda => sda,
               scl => scl,

               dipsw_read => dipsw_read,
               board_major => board_major,
               board_minor => board_minor
               );
  
  main : process

    variable v : unsigned(15 downto 0);

    procedure clock_tick is
    begin
      clock41 <= not clock41;
      wait for 12 ns;

    end procedure;

  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      if run("I2C runs") then
        for i in 1 to 100000 loop
          clock_tick;
        end loop;

      end if;
    end loop;
    test_runner_cleanup(runner);
  end process;

end architecture;
