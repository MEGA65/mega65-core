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

    eth_load_enable : in std_logic;
    
    keyboard_type : out unsigned(3 downto 0) := to_unsigned(2,4); -- MK-II Keyboard is the current thing
    kbd_datestamp : out unsigned(13 downto 0) := to_unsigned(0,14);
    kbd_commit : out unsigned(31 downto 0) := to_unsigned(0,32);
    
    disco_led_id : in unsigned(7 downto 0) := x"00";
    disco_led_val : in unsigned(7 downto 0) := x"00";
    disco_led_en : in std_logic := '0';
    
    kio8 : out std_logic; -- clock to keyboard / I2C DATA line
    kio9 : out std_logic; -- data output to keyboard / I2C CLK line
    kio10 : in std_logic; -- data input from keyboard

    kbd_bitbash_mode : in std_logic := '0';
    kbd_bitbash_scl : in std_logic := '0';
    kbd_bitbash_sda : in std_logic := '0';
    kbd_bitbash_sdadrive : in std_logic := '0';
    
    matrix_col : out std_logic_vector(7 downto 0) := (others => '1');
    matrix_col_idx : in integer range 0 to 15;

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
  signal led_tick : std_logic := '0';
  signal led_counter : integer range 0 to 15 := 0;
  -- shiftlock active low
  signal shiftlock_toggle : std_logic := '1';
  signal kbd_gpio1 : std_logic;
  signal kbd_gpio2 : std_logic;
  signal shiftlock : std_logic := '0';

  signal sda_assert : std_logic := '0';
  
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
      
      delete_out <= deletekey;
      return_out <= returnkey;
      fastkey_out <= fastkey;

      ------------------------------------------------------------------------
      -- Read from MEGA65 MK-I keyboard 
      ------------------------------------------------------------------------
      -- Process is to run a clock at a modest rate, and periodically send
      -- a sync pulse, and clock in the key states, while clocking out the
      -- LED states.
      
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
                if eth_load_enable='1' and counter(23)='1' then
                  output_vector(71 downto 48) <= x"00FFFF";
                  output_vector(95 downto 72) <= x"00FFFF";
                else
                  output_vector(71 downto 48) <= x"00FF00";
                  output_vector(95 downto 72) <= x"00FF00";
                end if;
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
    end if;
  end process;
  
end behavioural;
