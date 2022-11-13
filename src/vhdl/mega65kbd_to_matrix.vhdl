library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity mega65kbd_to_matrix is
  port (
    cpuclock : in std_logic;

    flopmotor : in std_logic;
    flopled0 : in std_logic;
    flopled2 : in std_logic;
    flopledsd : in std_logic;
    powerled : in std_logic;    

    keyboard_type : out unsigned(3 downto 0);
    kbd_datestamp : out unsigned(13 downto 0) := to_unsigned(0,14);
    kbd_commit : out unsigned(31 downto 0) := to_unsigned(0,32);
    
    disco_led_id : in unsigned(7 downto 0) := x"00";
    disco_led_val : in unsigned(7 downto 0) := x"00";
    disco_led_en : in std_logic := '0';
    
    kio8 : inout std_logic := 'Z'; -- clock to keyboard / I2C DATA line
    kio9 : out std_logic; -- data output to keyboard / I2C CLK line
    kio10 : in std_logic; -- data input from keyboard

    matrix_col : out std_logic_vector(7 downto 0) := (others => '1');
    matrix_col_idx : in integer range 0 to 8;

    delete_out : out std_logic;
    return_out : out std_logic;
    fastkey_out : out std_logic;
    
    -- RESTORE and capslock are active low
    restore : out std_logic := '1';
    capslock_out : out std_logic := '1';

    -- LEFT and UP cursor keys are active HIGH
    leftkey : out std_logic := '0';
    upkey : out std_logic := '0'
    
    );

end entity mega65kbd_to_matrix;

architecture behavioural of mega65kbd_to_matrix is

  signal matrix_ram_offset : integer range 0 to 15 := 0;
  signal keyram_wea : std_logic_vector(7 downto 0);
  signal matrix_dia : std_logic_vector(7 downto 0);
  
  signal enabled : std_logic := '0';

  signal clock_divider : integer range 0 to 255 := 0;
  signal kbd_clock : std_logic := '0';
  signal phase : integer range 0 to 255 := 0;
  signal sync_pulse : std_logic := '0';

  signal counter : unsigned(26 downto 0) := to_unsigned(0,27);
  
  signal output_vector : std_logic_vector(127 downto 0);
  signal disco_vector : std_logic_vector(95 downto 0);

  signal deletekey : std_logic := '1';
  signal returnkey : std_logic := '1';
  signal fastkey : std_logic := '1';

  -- Initially assume MK-II keyboard, as this will be immediately
  -- invalidated if it turns out to be a MK-I keyboard, as KIO10
  -- will not be held low initially.
  signal keyboard_model : integer range 1 to 2 := 2;
  signal model2_timeout : integer range 0 to 1000000 := 0;

  signal i2c_counter : integer range 0 to 50 := 0;
  signal i2c_tick : std_logic := '0';
  signal i2c_state : integer := 0;
  signal addr : unsigned(2 downto 0) := to_unsigned(0,3);

  signal i2c_bit : std_logic := '0';
  signal i2c_bit_valid : std_logic := '0';
  signal i2c_bit_num : integer range 0 to 15 := 0;

  signal current_keys : std_logic_vector(79 downto 0) := (others => '1');
  signal export_keys : std_logic_vector(79 downto 0) := (others => '1');
  signal done_writing_matrix : std_logic := '1';
  signal next_matrix_ram_write : integer range 9 downto 0 := 0;

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
  signal led_capslock : std_logic := '0';
  signal led_shiftlock : std_logic := '0';
  
begin  -- behavioural

  widget_kmm: entity work.kb_matrix_ram
    port map (
      clkA => cpuclock,
      addressa => matrix_ram_offset,
      dia => matrix_dia,
      wea => keyram_wea,
      addressb => matrix_col_idx,
      dob => matrix_col
      );

  process (cpuclock)
    variable keyram_write_enable : std_logic_vector(7 downto 0);
    variable keyram_offset : integer range 0 to 15 := 0;
    variable keyram_offset_tmp : std_logic_vector(2 downto 0);
    
  begin
    if rising_edge(cpuclock) then

      i2c_bit_valid <= '0';
      
      -- Generate ~400KHz I2C clock
      -- We use 2 or 3 ticks per clock, so 40.5MHz/(400KHz*2) = 50.652
      if i2c_counter < 50 then
        i2c_counter <= i2c_counter + 1;
        i2c_tick <= '0';
      else
        i2c_counter <= 0;
        i2c_tick <= '1';
      end if;
      
      -- Auto-detect keyboard model (including allowing for hot-swap)
      -- MK-II keyboard grounds KIO10, so if that stays low for a long
      -- time, then we can assume that it's a MK-II keyboard. But if it
      -- ever goes high, then it must be a MK-I
      keyboard_type <= to_unsigned(keyboard_model,4);
      if kio10 = '1' then
        keyboard_model <= 1;
        model2_timeout <= 1000000;
      elsif model2_timeout = 0 then
        keyboard_model <= 2;
        if keyboard_model = 1 then
          -- Set commit to "MKII" if its a MK-II
          kbd_commit <= x"49494b4d";
          kbd_datestamp <= to_unsigned(0,14);
        end if;
      else
        model2_timeout <= model2_timeout - 1;
      end if;
      
      if keyboard_model = 1 then
        ------------------------------------------------------------------------
        -- Read from MEGA65 MK-I keyboard 
        ------------------------------------------------------------------------
        -- Process is to run a clock at a modest rate, and periodically send
        -- a sync pulse, and clock in the key states, while clocking out the
        -- LED states.
        
        delete_out <= deletekey;
        return_out <= returnkey;
        fastkey_out <= fastkey;
        
        -- Counter is for working out drive LED blink phase
        counter <= counter + 1;
        
        -- Default is no write nothing at offset zero into the matrix ram.
        keyram_write_enable := x"00";
        keyram_offset := 0;
        
        if clock_divider /= 64 then
          clock_divider <= clock_divider + 1;
        else
          clock_divider <= 0;
          
          kbd_clock <= not kbd_clock;
          kio8 <= kbd_clock or sync_pulse;
          
          if kbd_clock='1' and phase < 128 then
            keyram_offset := phase/8;
            
            -- Receive keys with dedicated lines
            if phase = 72 then
              capslock_out <= kio10;
            end if;
            if phase = 73 then
              upkey <= not kio10;
            end if;
            if phase = 74 then
              leftkey <= not kio10;
            end if;
            if phase = 75 then
              restore <= kio10;
            end if;
            if phase = 76 then
              deletekey <= kio10;
            end if;
            if phase = 77 then
              returnkey <= kio10;
            end if;
            if phase = 78 then
              fastkey <= kio10;
            end if;
            -- Also extract keyboard CPLD firmware information
            if phase >= 82 and phase <= (82+13) then
              kbd_datestamp(phase - 82) <= kio10;
            end if;
            if phase >= 96 and phase <= (96+31) then
              kbd_commit(phase - 96) <= kio10;
            end if;
            
            -- Work around the data arriving 2 cycles late from the keyboard controller
            if phase = 0 then
              matrix_dia <= (others => deletekey);
            elsif phase = 1 then
              matrix_dia <= (others => returnkey);
            else
              matrix_dia <= (others => kio10); -- present byte of input bits to
                                               -- ram for writing
            end if;
            
            
            report "Writing received bit " & std_logic'image(kio10) & " to bit position " & integer'image(phase);
            
            case (phase mod 8) is
              when 0 => keyram_write_enable := x"01";
              when 1 => keyram_write_enable := x"02";
              when 2 => keyram_write_enable := x"04";
              when 3 => keyram_write_enable := x"08";
              when 4 => keyram_write_enable := x"10";
              when 5 => keyram_write_enable := x"20";
              when 6 => keyram_write_enable := x"40";
              when 7 => keyram_write_enable := x"80";
              when others => null;
            end case;
          end if;        
          matrix_ram_offset <= keyram_offset;
          keyram_wea <= keyram_write_enable;
          
          if kbd_clock='0' then
            report "phase = " & integer'image(phase) & ", sync=" & std_logic'image(sync_pulse);
            if phase /= 140 then
              phase <= phase + 1;
            else
              phase <= 0;
            end if;
            if phase = 127 then
              -- Reset to start
              sync_pulse <= '1';
              if disco_led_en = '1' then
                -- Allow simple RGB control of the LEDs
                if disco_led_id < 12 then
                  disco_vector(7+to_integer(disco_led_id)*8 downto to_integer(disco_led_id)*8) <= std_logic_vector(disco_led_val);
                end if;
                output_vector(127 downto 96) <= (others => '0');
                output_vector(95 downto 0) <= disco_vector;
              else
                output_vector <= (others => '0');
                if flopmotor='1' then
                  output_vector(23 downto 0) <= x"00FF00";
                  output_vector(47 downto 24) <= x"00FF00";
                elsif (flopled0='1' and counter(24)='1') then
                  output_vector(23 downto 0) <= x"0000FF";
                  output_vector(47 downto 24) <= x"0000FF";
                elsif (flopled2='1' and counter(24)='1') then
                  output_vector(23 downto 0) <= x"00FFFF";
                  output_vector(47 downto 24) <= x"00FFFF";
                elsif (flopledsd='1' and counter(24)='1') then
                  output_vector(23 downto 0) <= x"00FF00";
                  output_vector(47 downto 24) <= x"00FF00";
                end if;
                if powerled='1' then
                  output_vector(71 downto 48) <= x"00FF00";
                  output_vector(95 downto 72) <= x"00FF00";
                end if;
              end if;
            elsif phase = 140 then
              sync_pulse <= '0';
            elsif phase < 127 then
              -- Output next bit
              kio9 <= output_vector(127);
              output_vector(127 downto 1) <= output_vector(126 downto 0);
              output_vector(0) <= '0';
              
            end if;
          end if;
        end if;
      elsif keyboard_model = 2 then
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
        -- KIO8 = SDA, KIO9 = SCL
        
        -- Stash the bits into the key matrix
        -- MK-II keyboard PCB schematics have the key assignments there.
        if i2c_bit_valid='1' then
          case addr is
            when "011" => -- U2
              case i2c_bit_num is
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
                when 8 => current_keys(41) <= i2c_bit;-- P
                when 9 => current_keys(38) <= i2c_bit;-- O
                when 10 => current_keys(33) <= i2c_bit;-- I
                when 11 => current_keys(30) <= i2c_bit;-- U
                when 12 => current_keys(40) <= i2c_bit;-- PLUS
                when 13 => current_keys(35) <= i2c_bit;-- ZERO
                when 14 => current_keys(6) <= i2c_bit;-- F5
                when 15 => current_keys(3) <= i2c_bit;-- F7
                when others => null;
              end case;
            when others => null;
          end case;
        end if;
        
        if next_matrix_ram_write /= 0 then
          next_matrix_ram_write <= next_matrix_ram_write - 1;
        else
          done_writing_matrix <= '1';
        end if;
        if done_writing_matrix /= '1' then
          matrix_dia <= export_keys((8*next_matrix_ram_write)+7 downto (8*next_matrix_ram_write)+0);
          matrix_ram_offset <= next_matrix_ram_write;
          keyram_wea <= (others => '1');
        else
          keyram_wea <= (others => '0');
        end if;
        
        if i2c_state = 0 then
          if to_integer(addr) < 5 then
            addr <= addr + 1;
            report "Reading I2C IO expander " & integer'image(to_integer(addr)+ 1);
            i2c_state <= 100;
          else
            addr <= "000";
            report "Writing to I2C IO expander " & integer'image(0);
            -- We have read all IO expanders, so update exported key states
            export_keys <= current_keys;
            current_keys <= (others => '1');
            -- This requires writing to each column of the matrix RAM
            next_matrix_ram_write <= 9;
            done_writing_matrix <= '0';
            -- Update LEDs
            i2c_state <= 500;
          end if;
        end if;
        
        if i2c_tick='1' and i2c_state /= 0 then
          i2c_state <= i2c_state + 1;
        end if;
        case i2c_state is
          when 0 => null;

          -- State 500 = write to output ports of IO expander
          -- Start condition
          when 500 => kio8 <= '1'; kio9 <= '1';
          when 501 => kio8 <= '0'; kio9 <= '1';
          -- Send address 0100xxx
          when 502 => kio8 <= '0'; kio9 <= '0';
          when 503 => kio8 <= '0'; kio9 <= '1';
          when 504 => kio8 <= '1'; kio9 <= '0';
          when 505 => kio8 <= '1'; kio9 <= '1';
          when 506 => kio8 <= '0'; kio9 <= '0';
          when 507 => kio8 <= '0'; kio9 <= '1';
          when 508 => kio8 <= '0'; kio9 <= '0';
          when 509 => kio8 <= '0'; kio9 <= '1';
          when 510 => kio8 <= '0'; kio9 <= '0';
          when 511 => kio8 <= addr(2); kio9 <= '0';
          when 512 => kio8 <= addr(2); kio9 <= '1';
          when 513 => kio8 <= addr(2); kio9 <= '0';
          when 514 => kio8 <= addr(1); kio9 <= '0';
          when 515 => kio8 <= addr(1); kio9 <= '1';
          when 516 => kio8 <= addr(1); kio9 <= '0';
          when 517 => kio8 <= addr(0); kio9 <= '0';
          when 518 => kio8 <= addr(0); kio9 <= '1';
          when 519 => kio8 <= addr(1); kio9 <= '0';
          when 520 => kio8 <= '0'; kio9 <= '0';       -- select write
          when 521 => kio8 <= '0'; kio9 <= '1';
          -- ACK bit
          when 522 => kio8 <= '0'; kio9 <= '0';
          when 523 => kio8 <= 'Z'; kio9 <= '0';
          when 524 => kio8 <= 'Z'; kio9 <= '1';

          -- Write to set address to read from
          -- Send $02 to indicate read will be of register 2
          when 525 => kio8 <= '0'; kio9 <= '0';
          when 526 => kio8 <= '0'; kio9 <= '1';                          
          when 527 => kio8 <= '0'; kio9 <= '0';
          when 528 => kio8 <= '0'; kio9 <= '1';
          when 529 => kio8 <= '0'; kio9 <= '0';
          when 530 => kio8 <= '0'; kio9 <= '1';
          when 531 => kio8 <= '0'; kio9 <= '0';
          when 532 => kio8 <= '0'; kio9 <= '1';
          when 533 => kio8 <= '0'; kio9 <= '0';
          when 534 => kio8 <= '0'; kio9 <= '1';
          when 535 => kio8 <= u1_reg6; kio9 <= '0';
          when 536 => kio8 <= u1_reg6; kio9 <= '1';
          when 537 => kio8 <= '1'; kio9 <= '0';
          when 538 => kio8 <= '1'; kio9 <= '1';
          when 539 => kio8 <= '0'; kio9 <= '0';
          when 540 => kio8 <= '0'; kio9 <= '1';
          -- Send ACK bit during write
          when 541 => kio8 <= '0'; kio9 <= '0';
          when 542 => kio8 <= '0'; kio9 <= '1';
          when 543 => kio8 <= '0'; kio9 <= '0';
                      
          -- Write output port values in 2 bytes
          when 544 => kio8 <= led_shiftlock and u1_active; kio9 <= '0';
          when 545 => kio8 <= led_shiftlock and u1_active; kio9 <= '1';                          
          when 546 => kio8 <= led1_b and u1_active; kio9 <= '0';
          when 547 => kio8 <= led1_b and u1_active; kio9 <= '1';
          when 548 => kio8 <= led1_g and u1_active; kio9 <= '0';
          when 549 => kio8 <= led1_g and u1_active; kio9 <= '1';
          when 550 => kio8 <= led1_r and u1_active; kio9 <= '0';
          when 551 => kio8 <= led1_r and u1_active; kio9 <= '1';
          when 552 => kio8 <= led_capslock and u1_active; kio9 <= '0';
          when 553 => kio8 <= led_capslock and u1_active; kio9 <= '1';
          when 554 => kio8 <= led0_b and u1_active; kio9 <= '0';
          when 555 => kio8 <= led0_b and u1_active; kio9 <= '1';
          when 556 => kio8 <= led0_g and u1_active; kio9 <= '0';
          when 557 => kio8 <= led0_g and u1_active; kio9 <= '1';
          when 558 => kio8 <= led0_r and u1_active; kio9 <= '0';
          when 559 => kio8 <= led0_r and u1_active; kio9 <= '1';
          -- Send ACK bit during write
          when 560 => kio8 <= '0'; kio9 <= '0';
          when 561 => kio8 <= '0'; kio9 <= '1';
          when 562 => kio8 <= '0'; kio9 <= '0';


          when 563 => kio8 <= '0'; kio9 <= '0';
          when 564 => kio8 <= '0'; kio9 <= '1';                          
          when 565 => kio8 <= led3_b and u1_active; kio9 <= '0';
          when 566 => kio8 <= led3_b and u1_active; kio9 <= '1';
          when 567 => kio8 <= led3_g and u1_active; kio9 <= '0';
          when 568 => kio8 <= led3_g and u1_active; kio9 <= '1';
          when 569 => kio8 <= led3_r and u1_active; kio9 <= '0';
          when 570 => kio8 <= led3_r and u1_active; kio9 <= '1';
          when 571 => kio8 <= '0'; kio9 <= '0';
          when 572 => kio8 <= '0'; kio9 <= '1';
          when 573 => kio8 <= led2_b and u1_active; kio9 <= '0';
          when 574 => kio8 <= led2_b and u1_active; kio9 <= '1';
          when 575 => kio8 <= led2_g and u1_active; kio9 <= '0';
          when 576 => kio8 <= led2_g and u1_active; kio9 <= '1';
          when 577 => kio8 <= led2_r and u1_active; kio9 <= '0';
          when 578 => kio8 <= led2_r and u1_active; kio9 <= '1';
          -- Send ACK bit during write
          when 579 => kio8 <= '0'; kio9 <= '0';
          when 580 => kio8 <= '0'; kio9 <= '1';
          when 581 => kio8 <= '0'; kio9 <= '0';
                      
          -- Send STOP at end of read
          when 582 => kio8 <= '1'; kio9 <= '0'; -- don't ack last byte read
          when 583 => kio8 <= '0'; kio9 <= '0';
          when 584 => kio8 <= '0'; kio9 <= '1';
          when 585 => kio8 <= '1'; kio9 <= '1';
                      i2c_state <= 0;
                      if u1_reg6='1' then
                        u1_reg6 <= '0';
                        u1_active <= '1';
                      end if;
                    
          -- State 100 = read inputs from an IO expander
          -- Start condition
          when 100 => kio8 <= '1'; kio9 <= '1';
          when 101 => kio8 <= '0'; kio9 <= '1';
          -- Send address 0100xxx
          when 102 => kio8 <= '0'; kio9 <= '0';
          when 103 => kio8 <= '0'; kio9 <= '1';
          when 104 => kio8 <= '1'; kio9 <= '0';
          when 105 => kio8 <= '1'; kio9 <= '1';
          when 106 => kio8 <= '0'; kio9 <= '0';
          when 107 => kio8 <= '0'; kio9 <= '1';
          when 108 => kio8 <= '0'; kio9 <= '0';
          when 109 => kio8 <= '0'; kio9 <= '1';
                      
          -- Write to set address to read from
          when 110=> kio8 <= '0'; kio9 <= '0';
          when 111 => kio8 <= addr(2); kio9 <= '0';
          when 112 => kio8 <= addr(2); kio9 <= '1';
          when 113 => kio8 <= addr(2); kio9 <= '0';
          when 114 => kio8 <= addr(1); kio9 <= '0';
          when 115 => kio8 <= addr(1); kio9 <= '1';
          when 116 => kio8 <= addr(1); kio9 <= '0';
          when 117 => kio8 <= addr(0); kio9 <= '0';
          when 118 => kio8 <= addr(0); kio9 <= '1';
          when 119 => kio8 <= addr(1); kio9 <= '0';
          when 120 => kio8 <= '0'; kio9 <= '0';       -- select write
          when 121 => kio8 <= '0'; kio9 <= '1';
          -- ACK bit
          when 122 => kio8 <= '0'; kio9 <= '0';
          when 123 => kio8 <= 'Z'; kio9 <= '0';
          when 124 => kio8 <= 'Z'; kio9 <= '1';
                      
          -- Send $00 to indicate read will be of register 0
          when 125 => kio8 <= '0'; kio9 <= '0';
          when 126 => kio8 <= '0'; kio9 <= '1';                          
          when 127 => kio8 <= '0'; kio9 <= '0';
          when 128 => kio8 <= '0'; kio9 <= '1';
          when 129 => kio8 <= '0'; kio9 <= '0';
          when 130 => kio8 <= '0'; kio9 <= '1';
          when 131 => kio8 <= '0'; kio9 <= '0';
          when 132 => kio8 <= '0'; kio9 <= '1';
          when 133 => kio8 <= '0'; kio9 <= '0';
          when 134 => kio8 <= '0'; kio9 <= '1';
          when 135 => kio8 <= '0'; kio9 <= '0';
          when 136 => kio8 <= '0'; kio9 <= '1';
          when 137 => kio8 <= '0'; kio9 <= '0';
          when 138 => kio8 <= '0'; kio9 <= '1';
          when 139 => kio8 <= '0'; kio9 <= '0';
          when 140 => kio8 <= '0'; kio9 <= '1';
          -- Send ACK bit during write
          when 141 => kio8 <= '0'; kio9 <= '0';
          when 142 => kio8 <= '0'; kio9 <= '1';
          when 143 => kio8 <= '0'; kio9 <= '0';
                      
          -- Send repeated start
          when 144 => kio8 <= 'Z'; kio9 <= '1';
          when 145 => kio8 <= '0'; kio9 <= '1';
                      
          -- Send address 0100xxx
          when 146 => kio8 <= '0'; kio9 <= '0';
          when 147 => kio8 <= '0'; kio9 <= '1';
          when 148 => kio8 <= '1'; kio9 <= '0';
          when 149 => kio8 <= '1'; kio9 <= '1';
          when 150 => kio8 <= '0'; kio9 <= '0';
          when 151 => kio8 <= '0'; kio9 <= '1';
          when 152 => kio8 <= '0'; kio9 <= '0';
          when 153 => kio8 <= '0'; kio9 <= '1';
          -- 
          when 154 => kio8 <= '0'; kio9 <= '0';
          when 155 => kio8 <= addr(2); kio9 <= '0';
          when 156 => kio8 <= addr(2); kio9 <= '1';
          when 157 => kio8 <= addr(2); kio9 <= '0';
          when 158 => kio8 <= addr(1); kio9 <= '0';
          when 159 => kio8 <= addr(1); kio9 <= '1';
          when 160 => kio8 <= addr(1); kio9 <= '0';
          when 161 => kio8 <= addr(0); kio9 <= '0';
          when 162 => kio8 <= addr(0); kio9 <= '1';
          when 163 => kio8 <= addr(1); kio9 <= '0';
          when 164 => kio8 <= '1'; kio9 <= '0';      -- select read
          when 165 => kio8 <= '1'; kio9 <= '1';
          -- ACK bit
          when 166 => kio8 <= '0'; kio9 <= '0';
          when 167 => kio8 <= 'Z'; kio9 <= '0';
          when 168 => kio8 <= 'Z'; kio9 <= '1';
                      
          -- Read 2 bytes of data
          when 169 => kio8 <= 'Z'; kio9 <= '0';
          when 170 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 7;
          when 171 => kio8 <= 'Z'; kio9 <= '0';
          when 172 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 6;
          when 173 => kio8 <= 'Z'; kio9 <= '0';
          when 174 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 5;
          when 175 => kio8 <= 'Z'; kio9 <= '0';
          when 176 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 4;
          when 177 => kio8 <= 'Z'; kio9 <= '0';
          when 178 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 3;
          when 179 => kio8 <= 'Z'; kio9 <= '0';
          when 180 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 2;
          when 181 => kio8 <= 'Z'; kio9 <= '0';
          when 182 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 1;
          when 183 => kio8 <= 'Z'; kio9 <= '0';
          when 184 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 0;
          when 185 => kio8 <= '0'; kio9 <= '0';   -- ack byte read
          when 186 => kio8 <= '0'; kio9 <= '1';
                      
          when 187 => kio8 <= 'Z'; kio9 <= '0';
          when 188 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 15;
          when 189 => kio8 <= 'Z'; kio9 <= '0';
          when 190 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 14;
          when 191 => kio8 <= 'Z'; kio9 <= '0';
          when 192 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 13;
          when 193 => kio8 <= 'Z'; kio9 <= '0';
          when 194 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 12;
          when 195 => kio8 <= 'Z'; kio9 <= '0';
          when 196 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 11;
          when 197 => kio8 <= 'Z'; kio9 <= '0';
          when 198 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 10;
          when 199 => kio8 <= 'Z'; kio9 <= '0';
          when 200 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 9;
          when 201 => kio8 <= 'Z'; kio9 <= '0';
          when 202 => i2c_bit <= kio8; kio9 <= '1'; i2c_bit_valid <= '1'; i2c_bit_num <= 8;
          when 203 => kio8 <= '1'; kio9 <= '0'; -- don't ack last byte read
          when 204 => kio8 <= '1'; kio9 <= '1';
                      
          -- Send STOP at end of read
          when 205 => kio8 <= '1'; kio9 <= '0'; -- don't ack last byte read
          when 206 => kio8 <= '0'; kio9 <= '0';
          when 207 => kio8 <= '0'; kio9 <= '1';
          when 208 => kio8 <= '1'; kio9 <= '1';
                      i2c_state <= 0;
          when others => null;
        end case;
      end if;
    end if;
  end process;
  
end behavioural;
