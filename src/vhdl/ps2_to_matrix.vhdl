library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity ps2_to_matrix is
  port (
    cpuclock : in std_logic;
    reset_in : in std_logic;

    -- PS/2 keyboard also provides emulated joysticks and RESTORE key
    restore_out : out std_logic := '1';
    capslock_out : out std_logic := '0';
    
    matrix_col : out std_logic_vector(7 downto 0) := (others => '1');
    matrix_col_idx : in integer range 0 to 15;
    
    joya : out std_logic_vector(4 downto 0) := (others => '1');
    joyb : out std_logic_vector(4 downto 0) := (others => '1');

    -- And also the last PS/2 key scan code in case someone wants it
    last_scan_code : out std_logic_vector(12 downto 0) := (others => '0');
    
    -- PS2 keyboard interface
    ps2clock  : in  std_logic;
    ps2data   : in  std_logic;
    
    -- ethernet keyboard input interface for remote head mode
    eth_keycode_toggle : in std_logic;
    eth_keycode : in unsigned(15 downto 0);
    eth_hyperrupt_out : out std_logic := '0'
    );

end entity ps2_to_matrix;

architecture behavioural of ps2_to_matrix is

  type ps2_state is (Idle,StartBit,Bit0,Bit1,Bit2,Bit3,Bit4,Bit5,Bit6,Bit7,
                     ParityBit,StopBit);
  signal ps2state : ps2_state := Idle;

  signal scan_code : unsigned(7 downto 0) := x"FF";
  signal parity : std_logic := '0';

  -- PS2 clock rate is as low as 10KHz.  Allow double that for a timeout
  -- 192MHz/5KHz = 192000/5 = 38400 cycles
  -- 48MHz/5khz = 48000/5 = 9600 cycles
  constant ps2timeout : integer := 9600;
  signal ps2timer : integer range 0 to ps2timeout := 0;

  signal ps2clock_samples : std_logic_vector(7 downto 0) := (others => '1');
  signal ps2clock_debounced : std_logic := '0';

  signal ps2data_samples : std_logic_vector(7 downto 0) := (others => '1');
  signal ps2data_debounced : std_logic := '0';

  signal ps2clock_prev : std_logic := '0';

  signal extended : std_logic := '0';
  signal break : std_logic := '0';

  signal cursor_left : std_logic := '1';
  signal cursor_up : std_logic := '1';
  signal cursor_right : std_logic := '1';
  signal cursor_down : std_logic := '1';
  signal right_shift : std_logic := '1';
  signal ps2 : std_logic := '0';
  
  -- PS2 joystick keys
  signal joy1 : std_logic_vector(7 downto 0) := (others =>'1');
  signal joy2 : std_logic_vector(7 downto 0) := (others =>'1');
  signal joylock : std_logic := '0';

  signal ps2_capslock : std_logic := '0';
  
  signal fiftyhz_counter : unsigned(28 downto 0) := (others => '0');

  signal eth_keycode_toggle_last : std_logic := '0';
  signal ethernet_keyevent : std_logic := '0';

  -- keyboard matrix ram inputs
  signal keyram_address : integer range 0 to 15;
  signal keyram_di : std_logic_vector(7 downto 0);
  signal keyram_wea : std_logic_vector(7 downto 0);
  
  -- cursor update state machine
  signal cursor_update_state : integer range 0 to 2 := 0;

  signal hyper_trap_toggle : std_logic := '0';
  
begin  -- behavioural

  ps2kmm: entity work.kb_matrix_ram
  port map (
    clkA => cpuclock,
    addressa => keyram_address,
    dia => keyram_di,
    wea => keyram_wea,
    addressb => matrix_col_idx,
    dob => matrix_col
    );
  
-- purpose: read from ps2 keyboard interface
  keyread: process (cpuclock, ps2data,ps2clock)
    variable full_scan_code : std_logic_vector(11 downto 0);
    variable km_index : integer range 0 to 127;
    variable km_update : std_logic;
    variable km_value : std_logic;
    variable km_index_col : unsigned(2 downto 0);

  begin  -- process keyread
    if rising_edge(cpuclock) then      

      eth_hyperrupt_out <= '0';
      
      joya <= joy1(4 downto 0);
      joyb <= joy2(4 downto 0);
      
      capslock_out <= ps2_capslock;

      km_update := '0'; -- by default don't update anything
      km_index := 127; -- unused index
      
      -------------------------------------------------------------------------
      -- Generate timer for keyscan timeout
      -------------------------------------------------------------------------
      if ps2timer < ps2timeout then
        ps2timer <= ps2timer + 1;
      end if;
      if ps2timer >= ps2timeout then
        -- Reset ps2 keyboard timer
        ps2timer <= 0;
        ps2state <= Idle;
      end if;

      ------------------------------------------------------------------------
      -- Read from PS/2 keyboard/mouse interface
      ------------------------------------------------------------------------
      
      ps2clock_samples <= ps2clock_samples(6 downto 0) & ps2clock;
      if ps2clock_samples = "11111111" then
        ps2clock_debounced <= '1';
      end if;
      if ps2clock_samples = "00000000" then
        ps2clock_debounced <= '0';
      end if;

      ps2data_samples <= ps2data_samples(6 downto 0) & ps2data;
      if ps2data_samples = "11111111" then
        ps2data_debounced <= '1';
      end if; 
      if ps2data_samples = "00000000" then
        ps2data_debounced <= '0';
      end if;
      
      ps2clock_prev <= ps2clock_debounced;

      -- Allow injection of PS/2 scan codes via ethernet or other side channel
      last_scan_code(10) <= eth_keycode_toggle;
      if eth_keycode_toggle /= eth_keycode_toggle_last then
        eth_keycode_toggle_last <= eth_keycode_toggle;
        if eth_keycode(15 downto 0) = x"8000" then
          -- Trigger ethernet hyperrupt
          eth_hyperrupt_out <= '1';
          last_scan_code(11) <= hyper_trap_toggle;
          hyper_trap_toggle <= not hyper_trap_toggle;
        else
          -- It's really a key, so process it
          scan_code <= eth_keycode(7 downto 0);
          break <= eth_keycode(12);
          extended <= eth_keycode(8);        
        
          -- now rig status so that next cycle the key event will be processed
          ps2state <= Bit7;
          ethernet_keyevent <= '1';
        end if;
      elsif (ps2clock_debounced = '0' and ps2clock_prev = '1')
        or (ethernet_keyevent = '1') then
        ethernet_keyevent <= '0';
        ps2timer <= 0;
        case ps2state is
          when Idle => ps2state <= StartBit; scan_code <= x"FF"; parity <= '0';
          -- Check for keyboard input via ethernet
          when StartBit => ps2state <= Bit0; scan_code(0) <= ps2data_debounced;
                           parity <= parity xor ps2data_debounced;
          when Bit0 => ps2state <= Bit1; scan_code(1) <= ps2data_debounced;
                       parity <= parity xor ps2data_debounced;
          when Bit1 => ps2state <= Bit2; scan_code(2) <= ps2data_debounced;
                       parity <= parity xor ps2data_debounced;
          when Bit2 => ps2state <= Bit3; scan_code(3) <= ps2data_debounced;
                       parity <= parity xor ps2data_debounced;
          when Bit3 => ps2state <= Bit4; scan_code(4) <= ps2data_debounced;
                       parity <= parity xor ps2data_debounced;
          when Bit4 => ps2state <= Bit5; scan_code(5) <= ps2data_debounced;
                       parity <= parity xor ps2data_debounced;
          when Bit5 => ps2state <= Bit6; scan_code(6) <= ps2data_debounced;
                       parity <= parity xor ps2data_debounced;
          when Bit6 => ps2state <= Bit7; scan_code(7) <= ps2data_debounced;
                       parity <= parity xor ps2data_debounced;
          when Bit7 => ps2state <= parityBit;
                       -- if parity = ps2data then 
                       -- Valid PS2 symbol

                       -- XXX Make a little FSM to set bit 8 on E0 xx sequences
                       -- so that we can have a 9-bit number to look up.
                       -- XXX also work out when a key goes down versus up by F0
                       -- byte.
                       if scan_code = x"F0"  then
                         -- break code
                         break <= '1';
                       elsif scan_code = x"E0" then
                         extended <= '1';
                       else
                         full_scan_code := "000" & extended & std_logic_vector(scan_code);
                         break <= '0';
                         extended <= '0';

                         report "PS2KEYBOARD: processing scan code $" & to_hstring("000"&break&"000"&extended&std_logic_vector(scan_code));
                         
                         -- keyboard scancodes for the more normal keys from a keyboard I have here
                         -- (will replace these with the keyrah obtained ones)
                         --                                      $DC01 bits
                         --               0   1   2   3   4   5   6   7
                         -- $DC00 values  
                         -- Bit#0 $FE     1E0 5A  174 83  05  04  03  72
                         -- Bit#1 $FD     26  1D  1C  25  1A  1B  24  12
                         -- Bit#2 $FB     2E  2D  23  36  21  2B  2C  22
                         -- Bit#3 $F7     3D  35  34  3E  32  33  3C  2A
                         -- Bit#4 $EF     46  43  3B  45  3A  42  44  31
                         -- Bit#5 $DF     55  4D  4B  4E  49  54  5B  41
                         -- Bit#6 $BF     52  5D  4C  16C 59  169 75  4A
                         -- Bit#7 $7F     16  6B  14  1E  29  11  15  76
                         -- RESTORE - 0E (`/~ key)

                         -- Let the CPU read the most recent scan code for
                         -- debugging keyboard layout.
                         last_scan_code(12) <= break;
                         last_scan_code(8 downto 0) <= full_scan_code(8 downto 0);

                         case full_scan_code is
                           when x"058" =>
                             -- caps lock key: toggle caps lock state on release
                             if break='1' then
                               ps2_capslock <= not ps2_capslock;
                             end if;
                           when x"17D" => restore_out <= break;                             
                           -- Joysticks
                           when x"07d" =>  -- JOY1 LEFT
                             joy1(0) <= break;
                           when x"07a" =>  -- JOY1 RIGHT
                             joy1(1) <= break;
                           when x"06c" =>  -- JOY1 UP
                             joy1(2) <= break;
                           when x"069" =>  -- JOY1 DOWN
                             joy1(3) <= break;
                           when x"070" =>  -- JOY1 FIRE
                             joy1(4) <= break;
                           when x"073" =>  -- JOY2 FIRE
                             joy2(4) <= break;
                             
                           -- DELETE, RETURN, RIGHT, F7, F1, F3, F5, down
                           when x"066" => km_index := 0;
                           when x"05A" => km_index := 1;
                           when x"074" | x"174" =>
                             if joylock='0' then
                               cursor_right <= break; ps2 <= '1';
                             else
                               joy2(3) <= break;  -- JOY2 DOWN
                             end if;
                           when x"083" => km_index := 3;
                           when x"005" => km_index := 4;
                           when x"004" => km_index := 5;
                           when x"003" => km_index := 6;
                           -- Some keyboards use code 205 = $CD for cursor down
                           when x"072" | x"0CD" | x"172" =>
                             if joylock='0' then
                               cursor_down <= break; ps2 <= '1';
                             else
                               joy2(1) <= break;  -- keyrah / PS2
                                                  -- duplicate scan
                                                  -- code for down
                                                  -- key and joy2 right?
                             end if;
                           when x"075" | x"0C8" | x"175" => -- JOY2 UP
                             if joylock='1' then
                               joy2(0) <= break;
                             else
                               cursor_up <= break; ps2 <= '1';
                             end if;
                           when x"06B" | x"0CB" | x"16B" => -- JOY2 LEFT
                             if joylock='1' then
                               joy2(2) <= break;
                             else
                               cursor_left <= break; ps2 <= '1';
                             end if;
                           -- 3, W, A, 4, Z, S, E, left-SHIFT
                           when x"026" => km_index := 8; -- 3
                           when x"01D" => -- W
                             if joylock='0' then
                               km_index := 9;
                             else
                               joy1(0) <= break;
                             end if;
                           when x"01C" => -- A
                             if joylock='0' then
                               km_index := 10;
                             else
                               joy1(2) <= break;
                             end if;
                           when x"025" => km_index := 11; -- 4
                           when x"01A" => km_index := 12; -- Z
                           when x"01B" =>
                             if joylock='0' then  -- S
                               km_index := 13;
                             else
                               joy1(1) <= break;
                             end if;
                           when x"024" => km_index := 14; -- E
                           when x"012" => -- Left shift
                             if joylock='0' then
                               km_index := 15;
                             else
                               joy1(4) <= break;
                             end if;
                           -- 5, R, D, 6, C, F, T, X
                           when x"02E" => km_index := 16; -- 5
                           when x"02D" => km_index := 17; -- R 
                           when x"023" => -- D
                             if joylock='0' then
                               km_index := 18;
                             else
                               joy1(3) <= break;
                             end if;
                           when x"036" => km_index := 19;
                           when x"021" => km_index := 20;
                           when x"02B" => km_index := 21;
                           when x"02C" => km_index := 22;
                           when x"022" => km_index := 23;

                           -- 7, Y, G, 8, B, H, U, V
                           when x"03D" => km_index := 24;
                           when x"035" => km_index := 25;
                           when x"034" => km_index := 26;
                           when x"03E" => km_index := 27;
                           when x"032" => km_index := 28;
                           when x"033" => km_index := 29;
                           when x"03C" => km_index := 30;
                           when x"02A" => km_index := 31;

                           -- 9, I, J, 0, M, K, O, N
                           when x"046" => km_index := 32;
                           when x"043" => km_index := 33;
                           when x"03B" => km_index := 34;
                           when x"045" => km_index := 35;
                           when x"03A" => km_index := 36;
                           when x"042" => km_index := 37;
                           when x"044" => km_index := 38;
                           when x"031" => km_index := 39;

                           -- +, P, L, -, ., :, @, COMMA
                           when x"04E" => km_index := 40;
                           when x"04D" => km_index := 41;
                           when x"04B" => km_index := 42;
                           when x"055" => km_index := 43;
                           when x"049" => km_index := 44;
                           when x"04C" => km_index := 45;
                           when x"054" => km_index := 46;
                           when x"041" => km_index := 47;

                           -- POUND, *, ;, HOME, right SHIFT, =, UP-ARROW, /
                           when x"170" => km_index := 48;
                           when x"05B" => km_index := 49;
                           when x"052" => km_index := 50;
                           when x"16C" => km_index := 51;
                           when x"059" | x"159" => right_shift <= break; ps2 <= '1';
                           when x"05D" => km_index := 53;
                           when x"171" => km_index := 54;
                           when x"04A" => km_index := 55;

                           -- 1, LEFT-ARROW, CTRL, 2, SPACE, C=, Q, RUN/STOP
                           when x"016" => km_index := 56;
                           when x"00E" => km_index := 57;
                           when x"014" => km_index := 58; -- CTRL
                           when x"01E" => km_index := 59;
                           when x"029" =>
                             -- SPACE (or fire when using joylock mode)
                             if joylock = '0' then
                               km_index := 60;
                             else
                               joy2(4) <= break;
                             end if;                             
                           when x"11F" => km_index := 61; -- META/WIN for C=
                           when x"127" => km_index := 61; -- META/WIN for C=
                           when x"015" => km_index := 62;
                           when x"076" => km_index := 63;

                           -- Column 8:
                           when x"07E" => km_index := 64; -- NO SCRL
                           when x"00D" => km_index := 65; -- TAB
                           when x"011" => km_index := 66; -- ALT
                           when x"111" => km_index := 66; -- ALTGr
                           when x"077" =>
                             --HELP (Pause) and joylock (number lock key)
                             km_index := 67;
                             if break='1' then
                               joylock <= not joylock;
                             end if;
                           when x"001" => km_index := 68; -- F9/10
                           when x"078" => km_index := 69; -- F11/F12
                           when x"007" => km_index := 70; --F13/F14 (F12)
                           when x"112" => km_index := 71; -- ESC (PrtScr)
                                          
                           when others => null;
                         end case;
                         
                         -- set update to 1 if we pressed a valid key.
                         if km_index /= 127 then
                           km_update := '1';
                         end if;
                         km_value := break;
                         
                       end if;
                       
          when ParityBit =>  ps2state <= Idle;  -- was StopBit.  See if
                                                -- changing this fixed munching
                                                -- of first bit of back-to-back bytes.

          when StopBit => ps2state <= Idle;
          when others => ps2state <= Idle;
        end case;
      else -- run cursor update state machine during otherwise unused cycles.
        -- Cursor left and up are down and right + right shift,
        -- so combine these appropriately
        if cursor_update_state = 0 then
          km_index := 7;
          km_value := cursor_down and cursor_up;
          km_update := '1';
          cursor_update_state <= 1;
        elsif cursor_update_state = 1 then
          km_index := 2;
          km_value := cursor_left and cursor_right;
          km_update := '1';
          cursor_update_state <= 2;
        else
          km_index := 52;
          km_value := right_shift and cursor_up and cursor_left;
          km_update := '1';
          cursor_update_state <= 0;
        end if;
      end if;

    end if;

    -- update keyboard matrix memory
    if km_update = '1' then
      km_index_col := to_unsigned(km_index,7)(2 downto 0);
      case km_index_col is
        when "000" => keyram_wea <= "00000001";
        when "001" => keyram_wea <= "00000010";
        when "010" => keyram_wea <= "00000100";
        when "011" => keyram_wea <= "00001000";
        when "100" => keyram_wea <= "00010000";
        when "101" => keyram_wea <= "00100000";
        when "110" => keyram_wea <= "01000000";
        when "111" => keyram_wea <= "10000000";
        when others => keyram_wea <= x"00";
      end case;
    else
      keyram_wea <= x"00";
    end if;

    keyram_address <= 0; -- This avoids a latch
    if to_integer(to_unsigned(km_index,7)(6 downto 3)) < 9 then
      keyram_address <= to_integer(to_unsigned(km_index,7)(6 downto 3));
    end if;
    keyram_di <= (7 downto 0 => km_value); -- replicate value bit across byte

  end process keyread;

end behavioural;
