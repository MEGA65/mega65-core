library vunit_lib;
context vunit_lib.vunit_context;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;


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

  signal last_kio8 : std_logic := '0';
  signal last_kio9 : std_logic := '0';
  signal kio8_changes : integer := 0;
  signal kio9_changes : integer := 0;
  
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

      if run("Keyboard is detected as MK-I when kio10 is high") then
        kio10 <= '1';
        for i in 1 to 10000 loop
          clock <= '0'; wait for 10 ns; clock <= '1'; wait for 10 ns;
          -- Allow a couple of cycles for initial keyboard type to be
          -- determined and propagate
          if (i > 2) and (keyboard_type /= x"1") then
            assert false report "MK-I keyboard was detected as keyboard type $" & to_hstring(keyboard_type)
              & " instead of $1";
          end if;
        end loop;
      elsif run("Keyboard is detected as MK-II when kio10 is low") then
        kio10 <= '0';
        for i in 1 to 10000 loop
          clock <= '0'; wait for 10 ns; clock <= '1'; wait for 10 ns;
          -- Allow a couple of cycles for initial keyboard type to be
          -- determined and propagate
          if (i > 2) and (keyboard_type /= x"2") then
            assert false report "MK-II keyboard was detected as keyboard type $" & to_hstring(keyboard_type)
              & " instead of $2";
          end if;
        end loop;
      elsif run("MK-II keyboard mode results in I2C traffic") then
        kio10 <= '0';
        for i in 1 to 10000 loop
          clock <= '0'; wait for 10 ns; clock <= '1'; wait for 10 ns;
          if kio8 /= last_kio8 then
            last_kio8 <= kio8;
            report "KIO8 <= " & std_logic'image(kio8);
            kio8_changes <= kio8_changes + 1;
          end if;
          if kio9 /= last_kio9 then
            last_kio9 <= kio9;
            report "KIO9 <= " & std_logic'image(kio9);
            kio9_changes <= kio9_changes + 1;
          end if;
        end loop;
        if kio8_changes < 10 then
          assert false report "KIO8 did not change at least 10 times in 10,000 cycles";
        end if;
        if kio9_changes < 10 then
          assert false report "KIO9 did not change at least 10 times in 10,000 cycles";
        end if;
      end if;
    end loop;

    test_runner_cleanup(runner);
  end process;
end architecture;
