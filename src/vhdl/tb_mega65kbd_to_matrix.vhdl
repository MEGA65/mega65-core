library vunit_lib;
context vunit_lib.vunit_context;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;


entity tb_example_many is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_example_many is

  signal clock : std_logic;
  signal keyboard_type : unsigned(3 downto 0);
  signal kbd_datestamp : unsigned(13 downto 0) := to_unsigned(0,14);
  signal kbd_commit : unsigned(31 downto 0) := to_unsigned(0,32);  
  signal capslock_out : std_logic;
  signal leftkey : std_logic;
  signal upkey : std_logic;
  signal disco_led_id : unsigned(7 downto 0);
  signal disco_led_val : unsigned(7 downto 0);
  signal disco_led_en : std_logic;
  signal kio8 : std_logic; -- clock to keyboard / I2C DATA line
  signal kio9 : std_logic; -- data output to keyboard / I2C CLK line
  signal kio10 : std_logic; -- data input from keyboard
  signal matrix_col : std_logic_vector(7 downto 0);
  signal matrix_col_idx : integer range 0 to 8;
  signal delete_out : std_logic;
  signal return_out : std_logic;
  signal fastkey_out : std_logic;
  signal restore : std_logic;    
  
begin

  kbd0: entity work.mega65kbd_to_matrix
    port map (
      cpuclock => clock,
      flopmotor => '0',
      flopled0 => '0',
      flopled2 => '0',
      flopledsd => '0',
      powerled => '0',

      keyboard_type => keyboard_type,
      kbd_datestamp => kbd_datestamp,
      kbd_commit => kbd_commit,
    
      disco_led_id => disco_led_id,
      disco_led_val => disco_led_val,
      disco_led_en => disco_led_en,
    
      kio8 => kio8,
      kio9 => kio9,
      kio10 => kio10,

      matrix_col => matrix_col,
      matrix_col_idx => matrix_col_idx,

      delete_out => delete_out,
      return_out => return_out,
      fastkey_out => fastkey_out,
    
    -- RESTORE and capslock are active low
      restore => restore,
      capslock_out => capslock_out,

    -- LEFT and UP cursor keys are active HIGH
      leftkey => leftkey,
      upkey => upkey
    
    );
   
  main : process
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      if run("test_pass") then
        report "This will pass";

      elsif run("test_fail") then
        assert false report "It fails";

      end if;
    end loop;

    test_runner_cleanup(runner);
  end process;
end architecture;
