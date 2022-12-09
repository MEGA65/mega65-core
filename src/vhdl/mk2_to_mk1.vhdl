library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity mk2_to_mk1 is
  port (
    cpuclock : in std_logic;

    mk2_xil_io1 : in std_logic;
    mk2_xil_io2 : in std_logic;
    mk2_xil_io3 : out std_logic := '1';
    
    mk2_io1_in : in std_logic;
    mk2_io1 : out std_logic;
    mk2_io1_en : out std_logic;

    mk2_io2_in : in std_logic;
    mk2_io2 : out std_logic;
    mk2_io2_en : out std_logic;

    LED_R0           	: OUT std_logic := '0';
    LED_G0           	: OUT std_logic := '0';
    LED_B0           	: OUT std_logic := '0';
   
    LED_R1           	: OUT std_logic := '0';
    LED_G1           	: OUT std_logic := '0';
    LED_B1           	: OUT std_logic := '0';
    
    LED_R2           	: OUT std_logic := '0';
    LED_G2           	: OUT std_logic := '0';
    LED_B2           	: OUT std_logic := '0';
    
    LED_R3           	: OUT std_logic := '0';
    LED_G3           	: OUT std_logic := '0';
    LED_B3           	: OUT std_logic := '0';
    
    LED_SHIFT           : OUT std_logic := '0';
    LED_CAPS            : OUT std_logic := '0'    
    
    );

end entity mk2_to_mk1;

architecture behavioural of mk2_to_mk1 is

  signal output_vector : std_logic_vector(127 downto 0);

  signal i2c_counter : integer range 0 to 63 := 0;
  signal i2c_tick : std_logic := '0';
  signal i2c_state : integer := 0;
  -- Start with addr 5, so that we wrap to writing correct DDR values into addr
  -- 0 IO expander for LED control
  signal addr : unsigned(2 downto 0) := to_unsigned(5,3);

  signal i2c_bit : std_logic := '0';
  signal i2c_bit_valid : std_logic := '0';
  signal i2c_bit_num : integer range 0 to 15 := 0;

  signal current_keys : std_logic_vector(79 downto 0) := (others => '1');
  signal export_keys : std_logic_vector(79 downto 0) := (others => '1');

  -- These signals are used to cause the first write to U1 to instead set the
  -- data direection register instead of writing to the port
  signal u1_active : std_logic := '0';
  signal u1_reg6 : std_logic := '1';

  signal led0_r : std_logic := '0';
  signal led0_g : std_logic := '0';
  signal led0_b : std_logic := '0';
  signal led1_r : std_logic := '0';
  signal led1_g : std_logic := '0';
  signal led1_b : std_logic := '0';
  signal led2_r : std_logic := '0';
  signal led2_g : std_logic := '0';
  signal led2_b : std_logic := '0';
  signal led3_r : std_logic := '0';
  signal led3_g : std_logic := '0';
  signal led3_b : std_logic := '0';
  signal led_capslock : std_logic := '1';
  signal led_shiftlock : std_logic := '1';
  
  signal led_tick : std_logic := '0';
  signal led_counter : integer range 0 to 15 := 0;
  -- shiftlock active low
  signal shiftlock_toggle : std_logic := '1';
  signal kbd_gpio1 : std_logic;
  signal kbd_gpio2 : std_logic;
  signal shiftlock : std_logic := '0';

  signal sda_assert : std_logic := '0';

  signal clock_duration : integer range 0 to 248 := 0;

  signal mega65_ordered_matrix : std_logic_vector(81 downto 0) := (others => '1');
  signal serial_data_out : std_logic_vector(127 downto 0) := (others => '1');
  signal serial_data_in : std_logic_vector(127 downto 0) := (others => '0');
  signal bit_number : integer range 0 to 255 := 0;

  signal kio8_history : std_logic_vector(3 downto 0) := "0000";
  signal last_last_kio8 : std_logic := '0';
  signal last_kio8 : std_logic := '0';
  
  constant mk2_id_commit : unsigned(31 downto 0) := x"4d4b4949"; -- "MKII" to identify keyboard model
  constant mk2_id_date : unsigned(13 downto 0) := to_unsigned(0,14);

  signal counter : integer := 0;

  signal last_caps_lock : std_logic_vector(7 downto 0) := (others => '1');
  signal caps_lock_hold_time : integer range 0 to 1*512 := 0;
  signal caps_lock : std_logic := '0'; -- active high

  signal cnt_idle : unsigned(31 downto 0) := to_unsigned(0,32);
  
begin  -- behavioural

  process (cpuclock)
    variable keyram_write_enable : std_logic_vector(7 downto 0);
    variable keyram_offset : integer range 0 to 15 := 0;
    variable keyram_offset_tmp : std_logic_vector(2 downto 0);
    variable v : unsigned(95 downto 0);
  begin
    if rising_edge(cpuclock) then

      -- Periodically re-initialise U1, so that if keyboard is hot-swapped,
      -- LEDs still work (really just to make my life easier during development)
      if counter > 0 then
        counter <= counter - 1;
      end if;

      -- Flash both leds like ambulance lights if no signal from the computer
      cnt_idle <= cnt_idle + 1;
      if cnt_idle(31 downto 25) /= "0000000" then
        output_vector(95 downto 0) <= (others => '0');

        -- For R3/R3A PCB, we have back-flow current via HDMI, which has enough
        -- voltage to cause the red LEDs to be able to light (and to power the
        -- entire Lattice CPLD in the MK-I keyboard!). To hide this, we will make
        -- ambulance mode have only blue LED flashing, because of their higher
        -- minimum voltage requirement.
        -- BUT for MK-II keyboard which is controlled via the MAX10 or another
        -- FPGA on the mainboard, this should no longer be a problem.
        if cnt_idle(24)='1' then
          -- Red flashes
          output_vector(7 downto 0) <= (others => cnt_idle(21));
          output_vector(31 downto 24) <= (others => cnt_idle(21));
          -- Blue flashes
--          output_vector(23 downto 16) <= (others => cnt_idle(21));
--          output_vector(47 downto 40) <= (others => cnt_idle(21));
        else
          -- Blue flashes
          output_vector(71 downto 64) <= (others => cnt_idle(21));
          output_vector(95 downto 88) <= (others => cnt_idle(21));
        end if;
      end if;
      
      -- Export LEDs for debugging
      LED_R0 <= led0_r; LED_G0 <= led0_g; LED_B0 <= led0_b;
      LED_R1 <= led1_r; LED_G1 <= led1_g; LED_B1 <= led1_b;
      LED_R2 <= led2_r; LED_G2 <= led2_g; LED_B2 <= led2_b;
      LED_R3 <= led3_r; LED_G3 <= led3_g; LED_B3 <= led3_b;
      LED_CAPS <= led_capslock; LED_SHIFT <= led_shiftlock;
      
      i2c_bit_valid <= '0';

      -- De-glitch signal from FPGA
      kio8_history(0) <= mk2_xil_io1;
      kio8_history(3 downto 1) <= kio8_history(2 downto 0);

      last_last_kio8 <= last_kio8;
      if kio8_history(3 downto 0) = "1111" and mk2_xil_io1='1' and last_kio8 = '0' then
        last_kio8 <= '1';
      end if;
      if kio8_history(3 downto 0) = "0000" and mk2_xil_io1='0' and last_kio8 = '1' then
        last_kio8 <= '0';
      end if;
      
      -- Watch for Xilinx protocol clock
      -- At 40MHz, we need ~4x the counter values of the MK-I CPLD clock.
      -- XXX This is almost certainly slower than it could be with 40.5MHz clock.
      -- XXX This may stop MK-I keyboards working. If so, reduce the
      -- 248 down appropriately. There may be enough slop in it, though, to
      -- work unchanged.
      if mk2_xil_io1='0' then
        clock_duration <= 0;
        if clock_duration /= 0 then
--          report "Saw half clock of duration " & integer'image(clock_duration);
        end if;
      else
        if clock_duration < 248 then
          clock_duration <= clock_duration + 1;
        end if;
        if clock_duration = 247 then
          report "Saw start of 247+ cycle long sync pulse";
        end if;
      end if;

      if clock_duration = 248 then
        serial_data_out(127 downto 46) <= mega65_ordered_matrix;
        -- We send bits in reverse order, so put date and version in backwards
        for i in 0 to 13 loop
          serial_data_out(32 + i) <= mk2_id_date(13 - i);
        end loop;
        for i in 0 to 31 loop
          serial_data_out(i) <= mk2_id_commit(24 - ((i / 8)*8) + 7 - (i mod 8));
        end loop;
        for i in 0 to 79 loop
          serial_data_out(48 + i) <= export_keys(79 - i);
        end loop;
        bit_number <= 0;
        mk2_xil_io3 <= '1';
--        report "Preparing serial_data_out with ordered matrix = " & to_string(mega65_ordered_matrix);
      else
        if last_last_KIO8 = '0' and last_KIO8 = '1' then
--          report "CLK from Xilinx rose";
         -- Latch data on rising edge
          if bit_number /= 255 then
            bit_number <= bit_number + 1;
          end if;
          serial_data_in(127 downto 1) <= serial_data_in(126 downto 0);
          serial_data_in(0) <= mk2_xil_io2;
          if bit_number = 127 then
            -- We have 128 bits of data, so latch the whole thing
            for i in 0 to 94 loop
              output_vector(i) <= serial_data_in(94-i);
            end loop;
            output_vector(95) <= mk2_xil_io2;
            v(95 downto 1) := unsigned(serial_data_in(94 downto 0));
            v(0) := mk2_xil_io2;
            report "Setting output_vector to $" & string'(to_hstring(unsigned'(v)));
            cnt_idle <= to_unsigned(0,32);
          end if;

          -- And push matrix data out
          -- (And at the same time dealing with our funny time delay problem
          -- which is why we read from element 79, but have 81 in the loop.)
          serial_data_out(127 downto 1) <= serial_data_out(126 downto 0);
          serial_data_out(0) <= serial_data_out(127);
          mk2_xil_io3 <= serial_data_out(125);
        end if;
      end if;

      
      
      -- Generate ~400KHz I2C clock
      -- We use 2 or 3 ticks per clock, so 50MHz/(400KHz*2) = 63
      if i2c_counter < 63 then
        i2c_counter <= i2c_counter + 1;
        i2c_tick <= '0';
      else
        i2c_counter <= 0;
        i2c_tick <= '1';
      end if;
      
      -- This keyboard uses I2C to talk to 6 I2C IO expanders
      -- Each key on the keyboard is connected to a separate line,
      -- so we just need to read the input ports of them, and build
      -- the matrix data from that, and then export it.
      -- For the LEDs, we just have to write to the correct I2C registers
      -- to set those to output, and to write the appropriate values.
      
      -- The main trade-offs of the MK-II keyboard is no "ambulance
      -- lights" mode, and that the scanning will be at ~1KHz, rather than
      -- the ~100KHz of the MK-I. But 1ms latency should be ok. It will likely
      -- reduce the amount of PWM we can do on the LEDs for different brightness
      -- levels.
      
      -- We use a state machine for the simple I2C reads
      -- mk2_io1 = SDA, mk2_io2 = SCL

      if sda_assert='1' then
        sda_assert <= '0';
        mk2_io1 <= '0'; mk2_io1_en <= '1';
      end if;
      
      if led_tick='1' then
        report "LED tick, led_counter = " & integer'image(led_counter) & ", output_vector=$" & to_hstring(output_vector);
        if led_counter < 15 then
          led_counter <= led_counter + 1;
        else
          led_counter <= 0;
        end if;
        report "LED reds = " & std_logic'image(led0_r) & std_logic'image(led1_r) & std_logic'image(led2_r) & std_logic'image(led3_r);
        led0_r <= '1'; led0_g <= '1'; led0_b <= '1';
        led1_r <= '1'; led1_g <= '1'; led1_b <= '1';
        led2_r <= '1'; led2_g <= '1'; led2_b <= '1';
        led3_r <= '1'; led3_g <= '1'; led3_b <= '1';
        if to_integer(unsigned(output_vector(7 downto 4))) > led_counter then led3_r <= '0'; report "red0"; end if;
        if to_integer(unsigned(output_vector(15 downto 12))) > led_counter then led3_b <= '0'; report "green0"; end if;
        if to_integer(unsigned(output_vector(23 downto 20))) > led_counter then led3_g <= '0'; report "blue0"; end if;
        if to_integer(unsigned(output_vector(31 downto 24))) > led_counter then led2_r <= '0'; report "red1"; end if;
        if to_integer(unsigned(output_vector(39 downto 36))) > led_counter then led2_b <= '0'; report "green1"; end if;
        if to_integer(unsigned(output_vector(47 downto 44))) > led_counter then led2_g <= '0'; report "blue1"; end if;
        if to_integer(unsigned(output_vector(55 downto 52))) > led_counter then led1_b <= '0'; report "red2"; end if;
        if to_integer(unsigned(output_vector(63 downto 60))) > led_counter then led1_r <= '0'; report "green2"; end if;
        if to_integer(unsigned(output_vector(71 downto 68))) > led_counter then led1_g <= '0'; report "blue2"; end if;
        if to_integer(unsigned(output_vector(79 downto 76))) > led_counter then led0_b <= '0'; report "red3"; end if;
        if to_integer(unsigned(output_vector(87 downto 84))) > led_counter then led0_r <= '0'; report "green3"; end if;
        if to_integer(unsigned(output_vector(95 downto 92))) > led_counter then led0_g <= '0'; report "blue3"; end if;

        led_shiftlock <= shiftlock_toggle;
        led_capslock <= not caps_lock;
      end if;

      -- Stash the bits into the key matrix
      -- MK-II keyboard PCB schematics have the key assignments there.
      if i2c_bit_valid='1' then
--        report "Storing matrix bit " & integer'image(i2c_bit_num) & " = " & std_logic'image(i2c_bit)
--          & ", addr= " & to_string(std_logic_vector(addr)) & ", i2c_state = " & integer'image(i2c_state);
        case addr is
          when "011" => -- U2
            case i2c_bit_num is
              -- Confirmed port 0 maps to all correct keys
              when 0 => current_keys(67) <= i2c_bit; -- HELP
              when 1 => current_keys(70) <= i2c_bit;-- F13
              when 2 => current_keys(69) <= i2c_bit;-- F11
              when 3 => current_keys(68) <= i2c_bit;-- F9
              when 4 => current_keys(0) <= i2c_bit; -- DEL
                        -- XXX copied from MK-I keyboard behaviour. Why
                        -- does DEL map to two positions in the vector?
                        current_keys(76) <= i2c_bit;
              when 5 => current_keys(51) <= i2c_bit;-- HOME
              when 6 => current_keys(48) <= i2c_bit;-- GBP
              when 7 => current_keys(43) <= i2c_bit;-- MINUS
              -- NONE of the following work right now
              when  8 => current_keys(41) <= i2c_bit;-- P
              when  9 => current_keys(38) <= i2c_bit;-- O
              when 10 => current_keys(33) <= i2c_bit;-- I
              when 11 => current_keys(30) <= i2c_bit;-- U
              when 12 => current_keys(40) <= i2c_bit;-- PLUS
              when 13 => current_keys(35) <= i2c_bit;-- ZERO
              when 14 => current_keys(6) <= i2c_bit;-- F5
              when 15 => current_keys(3) <= i2c_bit;-- F7
              when others => null;
            end case;

          when "001" => -- U3
            case i2c_bit_num is
              -- Order was reversed for these, so swapped here
              when 7 => shiftlock <= i2c_bit;-- SHIFTLOCK
                        if i2c_bit='0' and shiftlock='1' then
                          shiftlock_toggle <= not shiftlock_toggle;
                        end if;
              when 6 => current_keys(10) <= i2c_bit;-- A
              when 5 => current_keys(13) <= i2c_bit;-- S
              when 4 => current_keys(18) <= i2c_bit;-- D
              when 3 => current_keys(65) <= i2c_bit;-- TAB
              when 2 => current_keys(62) <= i2c_bit;-- Q
              when 1 => current_keys(9) <= i2c_bit;-- W
              when 0 => -- NOT CONNECTED
              
              when 15 => current_keys(57) <= i2c_bit;-- <- / LEFT ARROW / LARR / _
              when 14 => current_keys(14) <= i2c_bit;-- E
              when 13 => current_keys(58) <= i2c_bit;-- CTRL
              when 12 => current_keys(61) <= i2c_bit;-- MEGA
              when 11 => current_keys(15) <= i2c_bit and shiftlock_toggle;-- LSHIFT
              when 10 => current_keys(12) <= i2c_bit;-- Z
              when  9 => current_keys(23) <= i2c_bit;-- X
              when  8 => current_keys(20) <= i2c_bit;-- C
              when others => null;
            end case;

          when "100" => -- U4
            report "i2c bit #" & integer'image(i2c_bit_num) & " = " & std_logic'image(i2c_bit);
            case i2c_bit_num is
              -- Order was reversed
              when 7 => current_keys(44) <= i2c_bit;-- <
              when 6 => current_keys(47) <= i2c_bit;-- >
              when 5 => current_keys(31) <= i2c_bit;-- V
              when 4 => current_keys(28) <= i2c_bit;-- B
              when 3 => current_keys(39) <= i2c_bit;-- N
              when 2 => current_keys(37) <= i2c_bit;-- K
              when 1 => current_keys(36) <= i2c_bit;-- M
              when 0 => current_keys(42) <= i2c_bit;-- L
              -- Order was reversed
              when 15 => current_keys(34) <= i2c_bit;-- J
              when 14 => current_keys(25) <= i2c_bit;-- Y
              when 13 => current_keys(29) <= i2c_bit;-- H
              when 12 => current_keys(22) <= i2c_bit;-- T
              when 11 => current_keys(26) <= i2c_bit;-- G
              when 10 => current_keys(17) <= i2c_bit;-- R
              when  9 => current_keys(21) <= i2c_bit;-- F
              when  8 => current_keys(60) <= i2c_bit;-- SPACE
                         report "SPACE is " & std_logic'image(i2c_bit);
              when others => null;
            end case;

          when "010" => -- U5
            case i2c_bit_num is
              -- Order was reversed
              when 7 => current_keys(52) <= i2c_bit;-- RSHIFT
              when 6 => current_keys(55) <= i2c_bit;-- ?
              when 5 => kbd_gpio2 <= i2c_bit;-- GPIO2
              when 4 => kbd_gpio1 <= i2c_bit;-- GPIO1
              when 3 => current_keys(74) <= i2c_bit;-- LEFT
              when 2 => current_keys(73) <= i2c_bit;-- UP
              when 1 => current_keys(7) <= i2c_bit;-- DOWN
              when 0 => current_keys(2) <= i2c_bit;-- RIGHT
              -- Reversed, but not all working
              when 15 => current_keys(45) <= i2c_bit;-- :
              when 14 => current_keys(50) <= i2c_bit;-- ;
              when 13 => current_keys(53) <= i2c_bit;-- =
              when 12 => current_keys(1) <= i2c_bit;-- RETURN
                         -- Copied from MK-I keyboard behaviour
                         current_keys(77) <= i2c_bit;
              when 11 => current_keys(46) <= i2c_bit;-- @
              when 10 => current_keys(49) <= i2c_bit;-- * 
              when  9 => current_keys(54) <= i2c_bit;-- ^
              when  8 => current_keys(75) <= i2c_bit;-- RESTORE
              when others => null;
            end case;

          when "101" => -- U6
            case i2c_bit_num is
              -- Were reversed
              when 7 => current_keys(11) <= i2c_bit;-- 4
              when 6 => current_keys(16) <= i2c_bit;-- 5
              when 5 => current_keys(19) <= i2c_bit;-- 6
              when 4 => current_keys(24) <= i2c_bit;-- 7
              when 3 => current_keys(27) <= i2c_bit;-- 8
              when 2 => current_keys(32) <= i2c_bit;-- 9
              when 1 => current_keys(5) <= i2c_bit;-- F3
              when 0 => current_keys(4) <= i2c_bit;-- F1
              -- Seemingly not working
                        -- Probably reversed, as NOSCROLL does 3
              when 15 => current_keys(64) <= i2c_bit;-- NOSCROLL
              when 14 => -- CAPS LOCK
                -- Directly expose up/down state of CAPS LOCK key for
                -- use as turbo button
                current_keys(78) <= i2c_bit;

                current_keys(72) <= not caps_lock;

                -- Toggle CAPS LOCK each time it is pressed.
                -- Toggle again, if held for a long time, so that
                -- a long-press for turbo mode, doesn't require that
                -- the user then cancel the CAPS LOCK change that pressing
                -- it caused.
                last_caps_lock(0) <= i2c_bit;
                last_caps_lock(7 downto 1) <= last_caps_lock(6 downto 0);
                if last_caps_lock = x"00" then
                  -- If caps lock is being held down for a long time for CPU speed
                  -- control, then automatically re-invert it so that the user doesn't
                  -- need to do so themselves.
                  if caps_lock_hold_time < (1*512) then
                    caps_lock_hold_time <= caps_lock_hold_time + 1;
                  end if;
                  if caps_lock_hold_time = (1*512 - 2) then
                    caps_lock <= not caps_lock;
                  end if;
                else
                  caps_lock_hold_time <= 0;
                end if;
                if (i2c_bit='0') and (last_caps_lock=x"FF") then
                  caps_lock <= not caps_lock;
                  current_keys(72) <= not caps_lock;
                end if;

              when 13 => current_keys(66) <= i2c_bit;-- ALT
              when 12 => current_keys(71) <= i2c_bit;-- ESC
              when 11 => current_keys(63) <= i2c_bit;-- RUNSTOP
              when 10 => current_keys(56) <= i2c_bit;-- 1
              when  9 => current_keys(59) <= i2c_bit;-- 2
              when  8 => current_keys( 8) <= i2c_bit;-- 3
              when others => null;
            end case;
            
          when others => null;
        end case;
      end if;
      
      led_tick <= '0';
      if i2c_state = 0 then
        if to_integer(addr) < 5 then
          addr <= addr + 1;
          report "Reading I2C IO expander " & integer'image(to_integer(addr)+ 1);
          i2c_state <= 100;
        else
          addr <= "000";
          led_tick <= '1';
          report "Writing to I2C IO expander " & integer'image(0);
          -- We have read all IO expanders, so update exported key states
          report "Updating current key vector to " & to_string(current_keys);
          export_keys <= current_keys;
          current_keys <= (others => '1');
          -- Update LEDs
          i2c_state <= 500;

          if counter = 0 then
            counter <= 40_500_000;
            u1_reg6 <= '1';
            u1_active <= '0';
          end if;
          
        end if;
      end if;
      
      if i2c_tick='1' and i2c_state /= 0 then
        i2c_state <= i2c_state + 1;

        case i2c_state is
          when 0 => null;

          -- State 500 = write to output ports of IO expander
          -- Start condition
          when 500 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 501 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          -- Send address 0100xxx
          when 502 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 503 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 504 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 505 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 506 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 507 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 508 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 509 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 510 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 511 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 512 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 513 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 514 => mk2_io1 <= '0'; mk2_io1_en <= not addr(2); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 515 => mk2_io1 <= '0'; mk2_io1_en <= not addr(2); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 516 => mk2_io1 <= '0'; mk2_io1_en <= not addr(2); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 517 => mk2_io1 <= '0'; mk2_io1_en <= not addr(1); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 518 => mk2_io1 <= '0'; mk2_io1_en <= not addr(1); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 519 => mk2_io1 <= '0'; mk2_io1_en <= not addr(1); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 520 => mk2_io1 <= '0'; mk2_io1_en <= not addr(0); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 521 => mk2_io1 <= '0'; mk2_io1_en <= not addr(0); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 522 => mk2_io1 <= '0'; mk2_io1_en <= not addr(0); mk2_io2 <= '0'; mk2_io2_en <= '1'; -- XXX delete superflous
                                                                                                    -- state
          when 523 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';       -- select write
          when 524 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          -- ACK bit
          when 525 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 526 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 527 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';

          -- Write to set address to read from
          -- Send $02 to indicate read will be of register 2
          when 528 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 529 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 530 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';                          
          when 531 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 532 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 533 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 534 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 535 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 536 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 537 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 538 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 539 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 540 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 541 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 542 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 543 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 544 => mk2_io1 <= '0'; mk2_io1_en <= not u1_reg6; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 545 => mk2_io1 <= '0'; mk2_io1_en <= not u1_reg6; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 546 => mk2_io1 <= '0'; mk2_io1_en <= not u1_reg6; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 547 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 548 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 549 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 550 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 551 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 552 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          -- Send ACK bit during write
          when 553 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 554 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 555 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
                      
          -- Write output port values in 2 bytes
          when 556 => mk2_io1 <= '0'; mk2_io1_en <= not (led_shiftlock and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 557 => mk2_io1 <= '0'; mk2_io1_en <= not (led_shiftlock and u1_active); mk2_io2 <= '1'; mk2_io2_en <= '1';                          
          when 558 => mk2_io1 <= '0'; mk2_io1_en <= not (led_shiftlock and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';                          
          when 559 => mk2_io1 <= '0'; mk2_io1_en <= not (led1_b and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 560 => mk2_io1 <= '0'; mk2_io1_en <= not (led1_b and u1_active); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 561 => mk2_io1 <= '0'; mk2_io1_en <= not (led1_b and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 562 => mk2_io1 <= '0'; mk2_io1_en <= not (led1_r and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 563 => mk2_io1 <= '0'; mk2_io1_en <= not (led1_r and u1_active); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 564 => mk2_io1 <= '0'; mk2_io1_en <= not (led1_r and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 565 => mk2_io1 <= '0'; mk2_io1_en <= not (led1_g and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 566 => mk2_io1 <= '0'; mk2_io1_en <= not (led1_g and u1_active); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 567 => mk2_io1 <= '0'; mk2_io1_en <= not (led1_g and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 568 => mk2_io1 <= '0'; mk2_io1_en <= not (led_capslock and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 569 => mk2_io1 <= '0'; mk2_io1_en <= not (led_capslock and u1_active); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 570 => mk2_io1 <= '0'; mk2_io1_en <= not (led_capslock and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 571 => mk2_io1 <= '0'; mk2_io1_en <= not (led0_b and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 572 => mk2_io1 <= '0'; mk2_io1_en <= not (led0_b and u1_active); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 573 => mk2_io1 <= '0'; mk2_io1_en <= not (led0_b and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 574 => mk2_io1 <= '0'; mk2_io1_en <= not (led0_r and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 575 => mk2_io1 <= '0'; mk2_io1_en <= not (led0_r and u1_active); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 576 => mk2_io1 <= '0'; mk2_io1_en <= not (led0_r and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 577 => mk2_io1 <= '0'; mk2_io1_en <= not (led0_g and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 578 => mk2_io1 <= '0'; mk2_io1_en <= not (led0_g and u1_active); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 579 => mk2_io1 <= '0'; mk2_io1_en <= not (led0_g and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          -- Send ACK bit during write
          when 580 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 581 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 582 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';


          when 583 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 584 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';                          
          when 585 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';                          
          when 586 => mk2_io1 <= '0'; mk2_io1_en <= not (led3_b and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 587 => mk2_io1 <= '0'; mk2_io1_en <= not (led3_b and u1_active); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 588 => mk2_io1 <= '0'; mk2_io1_en <= not (led3_b and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 589 => mk2_io1 <= '0'; mk2_io1_en <= not (led3_r and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 590 => mk2_io1 <= '0'; mk2_io1_en <= not (led3_r and u1_active); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 591 => mk2_io1 <= '0'; mk2_io1_en <= not (led3_r and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 592 => mk2_io1 <= '0'; mk2_io1_en <= not (led3_g and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 593 => mk2_io1 <= '0'; mk2_io1_en <= not (led3_g and u1_active); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 594 => mk2_io1 <= '0'; mk2_io1_en <= not (led3_g and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 595 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 596 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 597 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 598 => mk2_io1 <= '0'; mk2_io1_en <= not (led2_b and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 599 => mk2_io1 <= '0'; mk2_io1_en <= not (led2_b and u1_active); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 600 => mk2_io1 <= '0'; mk2_io1_en <= not (led2_b and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 601 => mk2_io1 <= '0'; mk2_io1_en <= not (led2_r and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 602 => mk2_io1 <= '0'; mk2_io1_en <= not (led2_r and u1_active); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 603 => mk2_io1 <= '0'; mk2_io1_en <= not (led2_r and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 604 => mk2_io1 <= '0'; mk2_io1_en <= not (led2_g and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 605 => mk2_io1 <= '0'; mk2_io1_en <= not (led2_g and u1_active); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 606 => mk2_io1 <= '0'; mk2_io1_en <= not (led2_g and u1_active); mk2_io2 <= '0'; mk2_io2_en <= '1';
          -- Send ACK bit during write
          when 607 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 608 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 609 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
                      
          -- Send STOP at end of read
          when 610 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1'; -- don't ack last byte read
          when 611 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 612 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';
                      i2c_state <= 0;
                      if u1_reg6='1' then
                        u1_reg6 <= '0';
                        u1_active <= '1';
                        report "U1 is now configured for LED outputs";
                      end if;
                      
          -- State 100 = read inputs from an IO expander
          -- Start condition
          when 100 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 101 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          -- Send address 0100xxx
          when 102 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 103 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 104 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 105 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 106 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 107 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 108 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 109 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 110 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 111 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 112 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 113 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
                      
          -- Write to set address to read from
          when 114=> mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 115 => mk2_io1 <= '0'; mk2_io1_en <= not addr(2); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 116 => mk2_io1 <= '0'; mk2_io1_en <= not addr(2); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 117 => mk2_io1 <= '0'; mk2_io1_en <= not addr(2); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 118 => mk2_io1 <= '0'; mk2_io1_en <= not addr(1); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 119 => mk2_io1 <= '0'; mk2_io1_en <= not addr(1); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 120 => mk2_io1 <= '0'; mk2_io1_en <= not addr(1); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 121 => mk2_io1 <= '0'; mk2_io1_en <= not addr(0); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 122 => mk2_io1 <= '0'; mk2_io1_en <= not addr(0); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 123 => mk2_io1 <= '0'; mk2_io1_en <= not addr(0); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 124 => mk2_io1 <= '0'; mk2_io1_en <= not addr(0); mk2_io2 <= '0'; mk2_io2_en <= '1';  -- XXX delete this
                                                                                                     -- superflous state
          when 125 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';       -- select write
          when 126 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 127 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          -- ACK bit
          when 128 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 129 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 130 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 131 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
                      
          -- Send $00 to indicate read will be of register 0
          when 132 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 133 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';                          
          when 134 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 135 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 136 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 137 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 138 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 139 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 140 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 141 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 142 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 143 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 144 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 145 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 146 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 147 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 148 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 149 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 150 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 151 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 152 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 153 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 154 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 155 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          -- Send ACK bit during write
          when 156 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 157 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 158 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
                      
          -- Send repeated start
          when 159 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 160 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 161 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
                      
          -- Send address 0100xxx
          when 162 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 163 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 164 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 165 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 166 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 167 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 168 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 169 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 170 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 171 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 172 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 173 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          -- 
          when 175 => mk2_io1 <= '0'; mk2_io1_en <= not addr(2); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 176 => mk2_io1 <= '0'; mk2_io1_en <= not addr(2); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 177 => mk2_io1 <= '0'; mk2_io1_en <= not addr(2); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 178 => mk2_io1 <= '0'; mk2_io1_en <= not addr(1); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 179 => mk2_io1 <= '0'; mk2_io1_en <= not addr(1); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 180 => mk2_io1 <= '0'; mk2_io1_en <= not addr(1); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 181 => mk2_io1 <= '0'; mk2_io1_en <= not addr(0); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 182 => mk2_io1 <= '0'; mk2_io1_en <= not addr(0); mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 183 => mk2_io1 <= '0'; mk2_io1_en <= not addr(0); mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 184 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';      -- select read
          when 185 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          -- ACK bit
          when 186 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 187 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 188 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 189 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
                      
          -- Read 2 bytes of data
          when 190 => mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 191 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 7; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 192 => mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 193 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 6; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 194 => mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 195 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 5; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 196 => mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 197 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 4; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 198 => mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 199 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 3; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 200 => mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 201 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 2; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 202 => mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 203 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 1; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 204 => mk2_io2 <= '1'; mk2_io2_en <= '1'; mk2_io1 <= '1'; mk2_io1_en <= '0';
          when 205 => mk2_io2 <= '1'; mk2_io2_en <= '1'; mk2_io1 <= '1'; mk2_io1_en <= '0';
          when 206 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 0; mk2_io2 <= '0'; mk2_io2_en <= '1';   -- ack byte read
                      -- Now we need to release SDA immediately, rather than
                      -- waiting 1 bit time, but only after we have pulled
                      -- SCL low.
                      sda_assert <= '1';
          when 207 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
                      
          when 208 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 209 => mk2_io2 <= '0'; mk2_io2_en <= '1'; mk2_io1 <= '1'; mk2_io1_en <= '0';
          when 210 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '0';
          when 211 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '0';
          when 212 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 15; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 213 => mk2_io2 <= '1'; mk2_io2_en <= '1'; 
          when 214 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 14; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 215 => mk2_io2 <= '1'; mk2_io2_en <= '1'; 
          when 216 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 13; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 217 => mk2_io2 <= '1'; mk2_io2_en <= '1'; 
          when 218 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 12; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 219 => mk2_io2 <= '1'; mk2_io2_en <= '1'; 
          when 220 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 11; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 221 => mk2_io2 <= '1'; mk2_io2_en <= '1'; 
          when 222 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 10; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 223 => mk2_io2 <= '1'; mk2_io2_en <= '1'; 
          when 224 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 9; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 225 => mk2_io2 <= '1'; mk2_io2_en <= '1'; mk2_io1 <= '1'; mk2_io1_en <= '0'; -- don't ack last byte read
          when 226 => i2c_bit <= mk2_io1_in; i2c_bit_valid <= '1'; i2c_bit_num <= 8; mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1'; 
          when 227 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';
                      
          -- Send STOP at end of read
          when 228 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '0'; mk2_io2_en <= '1'; -- don't ack last byte read
          when 229 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '0'; mk2_io2_en <= '1';
          when 230 => mk2_io1 <= '0'; mk2_io1_en <= '1'; mk2_io2 <= '1'; mk2_io2_en <= '1';
          when 231 => mk2_io1 <= '1'; mk2_io1_en <= '0'; mk2_io2 <= '1'; mk2_io2_en <= '1';
                      i2c_state <= 0;
          when others => null;
        end case;
      end if;
    end if;
  end process;
  
end behavioural;
