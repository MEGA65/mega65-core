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

  signal ewm0 : std_logic;
  signal ewm1 : std_logic;
  
  signal reset_high : std_logic;
  
begin

  pca0: entity work.pca9555
    generic map ( clock_frequency => 40_500_000,
                  address => b"0100000"
                  )
    port map ( clock => clock41,
               reset => reset_high,
               scl => scl,
               sda => sda,
               port0 => port0,
               port1 => port1);

  dcdc0: entity work.mp8869
    generic map ( clock_frequency => 40_500_000,
                  address => b"1100001"
                  )
    port map ( clock => clock41,
               reset => reset_high,
               scl => scl,
               sda => sda,
               ear_watering_mode => ewm0);

  dcdc1: entity work.mp8869
    generic map ( clock_frequency => 40_500_000,
                  address => b"1100111"
                  )
    port map ( clock => clock41,
               reset => reset_high,
               scl => scl,
               sda => sda,
               ear_watering_mode => ewm1);


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

  sda <= 'H';
  scl <= 'H';
  
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

        reset_high <= '1'; clock_tick;clock_tick;clock_tick;clock_tick;
        reset_high <= '0'; clock_tick;clock_tick;clock_tick;clock_tick;
        
        for i in 1 to 100000 loop
          clock_tick;
        end loop;

      elsif run("DCDC Converter Ear Watering Mode gets disabled") then

        reset_high <= '1'; clock_tick;clock_tick;clock_tick;clock_tick;
        reset_high <= '0'; clock_tick;clock_tick;clock_tick;clock_tick;

        if ewm0='0' or ewm1='0' then
          assert false report "Ear-Watering mode was not enabled on reset, but should have been";
        end if;
        
        for i in 1 to 100000 loop
          clock_tick;
          if ewm0='0' and ewm1='0' then
            exit;
          end if;
        end loop;

      elsif run("DIP-Switches and board revision gets read") then

        reset_high <= '1'; clock_tick;clock_tick;clock_tick;clock_tick;
        reset_high <= '0'; clock_tick;clock_tick;clock_tick;clock_tick;

        for i in 1 to 100000 loop
          clock_tick;

          port0 <= x"a5"; -- DIP switches
          port1 <= x"50"; -- board revision
        end loop;

        report "Read DIP switches as $" & to_hexstring(dipsw_read);
        report "Read board revision as " & to_hexstring(board_major) & "." & to_hexstring(board_minor);
        if to_X01(dipsw_read) /= x"a5" then
          for i in 0 to 7 loop
            report "DIP switch #" & integer'image(i) & " = " & std_logic'image(dipsw_read(i));
          end loop;          
          assert false report "DIP switch value not read correctly (saw $" & to_hexstring(dipsw_read) & " instead)";
        end if;
        if to_X01(board_major) /= x"5" then
          assert false report "Board major version value not read correctly";
        end if;
        if to_X01(board_minor) /= x"0" then
          assert false report "Board minor version value not read correctly";
        end if;
          
        
      end if;
    end loop;
    test_runner_cleanup(runner);
  end process;

end architecture;
