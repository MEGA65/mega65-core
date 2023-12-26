library vunit_lib;
context vunit_lib.vunit_context;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;


entity tb_mega65kbd_to_matrix is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_mega65kbd_to_matrix is

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
  signal kio8 : std_logic := 'H'; -- clock to keyboard / I2C DATA line
  signal kio9 : std_logic := 'H'; -- data output to keyboard / I2C CLK line
  signal kio10 : std_logic; -- data input from keyboard
  signal matrix_col : std_logic_vector(7 downto 0);
  signal matrix_col_idx : integer range 0 to 15;
  signal delete_out : std_logic;
  signal return_out : std_logic;
  signal fastkey_out : std_logic;
  signal restore : std_logic;    

  signal last_kio8 : std_logic := '0';
  signal last_kio9 : std_logic := '0';
  signal kio8_changes : integer := 0;
  signal kio9_changes : integer := 0;

  signal reset : std_logic := '1';

  signal u1port0 : unsigned(7 downto 0) := (others => '1');
  signal u1port1 : unsigned(7 downto 0) := (others => '1');
  signal u1_reg : integer;
  signal u1_read : std_logic;
  signal u1_write : std_logic;
  signal u1_saw_read : unsigned(7 downto 0) := (others => '0');
  signal u1_saw_write : unsigned(7 downto 0) := (others => '0');

  signal u2port0 : unsigned(7 downto 0) := (others => '1');
  signal u2port1 : unsigned(7 downto 0) := (others => '1');
  signal u2_reg : integer;
  signal u2_read : std_logic;
  signal u2_write : std_logic;
  signal u2_saw_read : unsigned(7 downto 0) := (others => '0');
  signal u2_saw_write : unsigned(7 downto 0) := (others => '0');

  signal u3port0 : unsigned(7 downto 0) := (others => '1');
  signal u3port1 : unsigned(7 downto 0) := (others => '1');
  signal u3_reg : integer;
  signal u3_read : std_logic;
  signal u3_write : std_logic;
  signal u3_saw_read : unsigned(7 downto 0) := (others => '0');
  signal u3_saw_write : unsigned(7 downto 0) := (others => '0');

  signal u4port0 : unsigned(7 downto 0) := (others => '1');
  signal u4port1 : unsigned(7 downto 0) := (others => '1');
  signal u4_reg : integer;
  signal u4_read : std_logic;
  signal u4_write : std_logic;
  signal u4_saw_read : unsigned(7 downto 0) := (others => '0');
  signal u4_saw_write : unsigned(7 downto 0) := (others => '0');

  signal u5port0 : unsigned(7 downto 0) := (others => '1');
  signal u5port1 : unsigned(7 downto 0) := (others => '1');
  signal u5_reg : integer;
  signal u5_read : std_logic;
  signal u5_write : std_logic;
  signal u5_saw_read : unsigned(7 downto 0) := (others => '0');
  signal u5_saw_write : unsigned(7 downto 0) := (others => '0');

  signal u6port0 : unsigned(7 downto 0) := (others => '1');
  signal u6port1 : unsigned(7 downto 0) := (others => '1');
  signal u6_reg : integer;
  signal u6_read : std_logic;
  signal u6_write : std_logic;
  signal u6_saw_read : unsigned(7 downto 0) := (others => '0');
  signal u6_saw_write : unsigned(7 downto 0) := (others => '0');

  signal col_num : integer := 0;
  signal col_countdown : integer := 0;  
  
begin

  u1: entity work.pca9555
    generic map ( clock_frequency => 5e7,
                  address => "0100000"
                  )
    port map (clock => clock,
              reset => reset,
              scl => kio9,
              sda => kio8,
              port0 => u1port0,
              port1 => u1port1,
              accessed_reg => u1_reg,
              reg_write_strobe => u1_write,
              reg_read_strobe => u1_read
              );

  u2: entity work.pca9555
    generic map ( clock_frequency => 5e7,
                  address => "0100011"
                  )
    port map (clock => clock,
              reset => reset,
              scl => kio9,
              sda => kio8,
              port0 => u2port0,
              port1 => u2port1,
              accessed_reg => u2_reg,
              reg_write_strobe => u2_write,
              reg_read_strobe => u2_read
              );

  u3: entity work.pca9555
    generic map ( clock_frequency => 5e7,
                  address => "0100001"
                  )
    port map (clock => clock,
              reset => reset,
              scl => kio9,
              sda => kio8,
              port0 => u3port0,
              port1 => u3port1,
              accessed_reg => u3_reg,
              reg_write_strobe => u3_write,
              reg_read_strobe => u3_read
              );

  u4: entity work.pca9555
    generic map ( clock_frequency => 5e7,
                  address => "0100100"
                  )
    port map (clock => clock,
              reset => reset,
              scl => kio9,
              sda => kio8,
              port0 => u4port0,
              port1 => u4port1,
              accessed_reg => u4_reg,
              reg_write_strobe => u4_write,
              reg_read_strobe => u4_read
              );

  u5: entity work.pca9555
    generic map ( clock_frequency => 5e7,
                  address => "0100010"
                  )
    port map (clock => clock,
              reset => reset,
              scl => kio9,
              sda => kio8,
              port0 => u5port0,
              port1 => u5port1,
              accessed_reg => u5_reg,
              reg_write_strobe => u5_write,
              reg_read_strobe => u5_read
              );

  u6: entity work.pca9555
    generic map ( clock_frequency => 5e7,
                  address => "0100101"
                  )
    port map (clock => clock,
              reset => reset,
              scl => kio9,
              sda => kio8,
              port0 => u6port0,
              port1 => u6port1,
              accessed_reg => u6_reg,
              reg_write_strobe => u6_write,
              reg_read_strobe => u6_read
              );
  
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
      elsif run("MK-II keyboard mode reads U2-U6 ports, writes U1 ports") then
        kio10 <= '0';
        for i in 1 to 100000 loop
          if (i=3) then
            reset <= '0';
          end if;
          clock <= '0'; wait for 10 ns; clock <= '1'; wait for 10 ns;
          if u1_read='1' then
            report "Detected read of U1 register " & integer'image(u1_reg);
            u1_saw_read(u1_reg) <= '1';
          end if;
          if u1_write='1' then
            report "Detected write of U1 register " & integer'image(u1_reg);
            u1_saw_write(u1_reg) <= '1';
          end if;
          if u2_read='1' then
            report "Detected read of U2 register " & integer'image(u2_reg);
            u2_saw_read(u2_reg) <= '1';
          end if;
          if u2_write='1' then
            report "Detected write of U2 register " & integer'image(u2_reg);
            u2_saw_write(u2_reg) <= '1';
          end if;
          if u3_read='1' then
            report "Detected read of U3 register " & integer'image(u3_reg);
            u3_saw_read(u3_reg) <= '1';
          end if;
          if u3_write='1' then
            report "Detected write of U3 register " & integer'image(u3_reg);
            u3_saw_write(u3_reg) <= '1';
          end if;
          if u4_read='1' then
            report "Detected read of U4 register " & integer'image(u4_reg);
            u4_saw_read(u4_reg) <= '1';
          end if;
          if u4_write='1' then
            report "Detected write of U4 register " & integer'image(u4_reg);
            u4_saw_write(u4_reg) <= '1';
          end if;
          if u5_read='1' then
            report "Detected read of U5 register " & integer'image(u5_reg);
            u5_saw_read(u5_reg) <= '1';
          end if;
          if u5_write='1' then
            report "Detected write of U5 register " & integer'image(u5_reg);
            u5_saw_write(u5_reg) <= '1';
          end if;
          if u6_read='1' then
            report "Detected read of U6 register " & integer'image(u6_reg);
            u6_saw_read(u6_reg) <= '1';
          end if;
          if u6_write='1' then
            report "Detected write of U2 register " & integer'image(u6_reg);
            u6_saw_write(u6_reg) <= '1';
          end if;
        end loop;
        if u1_saw_read /= "00000000" then
          assert false report "Expected to see no reads on U1.  Instead saw this access pattern: " & to_string(u1_saw_read);
        else
          report "Saw U1 reads to " & to_string(u1_saw_read);
        end if;
        if u1_saw_write /= "11001100" then
          assert false report "Expected to see writes to U1 regs 6,7 and 2,3.  Instead saw this access pattern: " & to_string(u1_saw_write);
        else
          report "Saw U1 writes to " & to_string(u1_saw_write);
        end if;
        if u2_saw_read /= "00000011" then
          assert false report "Expected to see registers 0 and 1 of U2 be read.  Instead saw this access pattern: " & to_string(u2_saw_read);
        else
          report "Saw U2 reads to " & to_string(u2_saw_read);
        end if;
        if u2_saw_write /= "00000000" then
          assert false report "Expected to see no writes to U2.  Instead saw this access pattern: " & to_string(u2_saw_write);
        else
          report "Saw U2 writes to " & to_string(u2_saw_write);
        end if;
        if u3_saw_read /= "00000011" then
          assert false report "Expected to see registers 0 and 1 of U3 be read.  Instead saw this access pattern: " & to_string(u3_saw_read);
        else
          report "Saw U3 reads to " & to_string(u3_saw_read);
        end if;
        if u3_saw_write /= "00000000" then
          assert false report "Expected to see no writes to U3.  Instead saw this access pattern: " & to_string(u3_saw_write);
        else
          report "Saw U3 writes to " & to_string(u3_saw_write);
        end if;
        if u4_saw_read /= "00000011" then
          assert false report "Expected to see registers 0 and 1 of U4 be read.  Instead saw this access pattern: " & to_string(u4_saw_read);
        else
          report "Saw U4 reads to " & to_string(u4_saw_read);
        end if;
        if u4_saw_write /= "00000000" then
          assert false report "Expected to see no writes to U4.  Instead saw this access pattern: " & to_string(u4_saw_write);
        else
          report "Saw U4 writes to " & to_string(u4_saw_write);
        end if;
        if u5_saw_read /= "00000011" then
          assert false report "Expected to see registers 0 and 1 of U5 be read.  Instead saw this access pattern: " & to_string(u5_saw_read);
        else
          report "Saw U5 reads to " & to_string(u5_saw_read);
        end if;
        if u5_saw_write /= "00000000" then
          assert false report "Expected to see no writes to U5.  Instead saw this access pattern: " & to_string(u5_saw_write);
        else
          report "Saw U5 writes to " & to_string(u5_saw_write);
        end if;
        if u6_saw_read /= "00000011" then
          assert false report "Expected to see registers 0 and 1 of U6 be read.  Instead saw this access pattern: " & to_string(u6_saw_read);
        else
          report "Saw U6 reads to " & to_string(u6_saw_read);
        end if;
        if u6_saw_write /= "00000000" then
          assert false report "Expected to see no writes to U6.  Instead saw this access pattern: " & to_string(u6_saw_write);
        else
          report "Saw U6 writes to " & to_string(u6_saw_write);
        end if;
      elsif run("MK-II keyboard outputs no key presses while idle") then
        kio10 <= '0'; kio8 <= 'H'; kio9 <= 'H';
        u2port0 <= (others => 'H'); u2port1 <= (others => 'H');
        u3port0 <= (others => 'H'); u3port1 <= (others => 'H');
        u4port0 <= (others => 'H'); u4port1 <= (others => 'H');
        u5port0 <= (others => 'H'); u5port1 <= (others => 'H');
        u6port0 <= (others => 'H'); u6port1 <= (others => 'H');
        for i in 1 to 100000 loop
          if (i=3) then
            reset <= '0';
          end if;
          clock <= '0'; wait for 10 ns; clock <= '1'; wait for 10 ns;
          matrix_col_idx <= col_num;
          -- Give time for first round of reading IO expanders to complete
          if i > 75000 then
            if col_countdown /= 0 then
              col_countdown <= col_countdown - 1;
            else
              col_countdown <= 5;
              if col_num < 8 then
                col_num <= col_num + 1;
              else
                col_num <= 0;
              end if;
              if to_X01(matrix_col) /= x"ff" then
                assert false report "Matrix column " & integer'image(col_num) & " = $" & to_hstring(matrix_col) & ", but should be $ff";
              end if;
            end if;
          end if;
        end loop;
      elsif run("MK-II keyboard outputs key when pressed") then
        kio10 <= '0'; kio8 <= 'H'; kio9 <= 'H';
        u2port0 <= (others => 'H'); u2port1 <= (others => 'H');
        u3port0 <= (others => 'H'); u3port1 <= (others => 'H');
        u4port0 <= (others => 'H'); u4port1 <= (others => 'H');
        u5port0 <= (others => 'H'); u5port1 <= (others => 'H');
        u6port0 <= (others => 'H'); u6port1 <= (others => 'H');
        -- Press SPACE 
        u4port1(7) <= '0'; 
        for i in 1 to 100000 loop
          if (i=3) then
            reset <= '0';
          end if;
          clock <= '0'; wait for 10 ns; clock <= '1'; wait for 10 ns;
          matrix_col_idx <= col_num;
          -- Give time for first round of reading IO expanders to complete
          if i > 75000 then
            if col_countdown /= 0 then
              col_countdown <= col_countdown - 1;
            else
              col_countdown <= 5;
              if col_num < 8 then
                col_num <= col_num + 1;
              else
                col_num <= 0;
              end if;
              if col_num /=7 then
                if to_X01(matrix_col) /= x"ff" then
                  assert false report "Matrix column " & integer'image(col_num) & " = $" & to_hstring(matrix_col) & ", but should be $ff";
                end if;
              else
                if to_X01(matrix_col) /= "11101111" then
                  assert false report "Matrix column " & integer'image(col_num) & " = $" & to_hstring(matrix_col) & ", but should be $ef";
                end if;
              end if;                
            end if;
          end if;
        end loop;
      end if;
    end loop;
    test_runner_cleanup(runner);
  end process;
end architecture;
