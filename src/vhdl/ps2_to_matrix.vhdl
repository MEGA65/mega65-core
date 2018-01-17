library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity ps2_to_matrix is
  port (
    ioclock : in std_logic;
    reset_in : in std_logic;

    -- PS/2 keyboard also provides emulated joysticks and RESTORE key
    restore_out : out std_logic := '1';
    capslock_out : out std_logic := '1';
    matrix : out std_logic_vector(71 downto 0) := (others => '1');
    joya : out std_logic_vector(4 downto 0) := (others => '1');
    joyb : out std_logic_vector(4 downto 0) := (others => '1');

    -- And also the last PS/2 key scan code in case someone wants it
    last_scan_code : out std_logic_vector(12 downto 0);
    
    -- PS2 keyboard interface
    ps2clock  : in  std_logic;
    ps2data   : in  std_logic;
    
    -- ethernet keyboard input interface for remote head mode
    eth_keycode_toggle : in std_logic;
    eth_keycode : in unsigned(15 downto 0)
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

  signal matrix_internal : std_logic_vector(71 downto 0) := (others =>'1');
  
  -- PS2 joystick keys
  signal joy1 : std_logic_vector(7 downto 0) := (others =>'1');
  signal joy2 : std_logic_vector(7 downto 0) := (others =>'1');
  signal joylock : std_logic := '0';

  signal ps2_capslock : std_logic := '1';
  
  signal fiftyhz_counter : unsigned(28 downto 0) := (others => '0');

  signal eth_keycode_toggle_last : std_logic := '0';
  signal ethernet_keyevent : std_logic := '0';

begin  -- behavioural

-- purpose: read from ps2 keyboard interface
  keyread: process (ioclock, ps2data,ps2clock)
    variable full_scan_code : std_logic_vector(11 downto 0);
  begin  -- process keyread
    if rising_edge(ioclock) then      

      joya <= joy1(4 downto 0);
      joyb <= joy2(4 downto 0);
      
      capslock_out <= ps2_capslock;

      matrix <= matrix_internal;

      -- Cursor left and up are down and right + right shift,
      -- so combine these appropriately
      matrix(7) <= cursor_down and cursor_up;
      matrix(2) <= cursor_left and cursor_right;
      matrix(52) <= right_shift and cursor_up and cursor_left;
      
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
      if eth_keycode_toggle /= eth_keycode_toggle_last then
        scan_code <= eth_keycode(7 downto 0);
        break <= eth_keycode(12);
        extended <= eth_keycode(8);        
        eth_keycode_toggle_last <= eth_keycode_toggle;
        
        -- now rig status so that next cycle the key event will be processed
        ps2state <= Bit7;
        ethernet_keyevent <= '1';        
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
                         last_scan_code(11 downto 9) <= "000";
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
                           when x"074" =>  -- JOY2 DOWN
                             joy2(3) <= break;
--                           when x"072" =>  -- JOY2 RIGHT
--                             joy2(3) <= break;
                           when x"073" =>  -- JOY2 FIRE
                             joy2(4) <= break;
                             
                           -- DELETE, RETURN, RIGHT, F7, F1, F3, F5, down
                           when x"066" => matrix_internal(0) <= break;
                           when x"05A" => matrix_internal(1) <= break;
                           when x"174" =>
                             if joylock='0' then
                               cursor_right <= break; ps2 <= '1';
                             else
                               joy2(3) <= break;
                             end if;
                           when x"083" => matrix_internal(3) <= break;
                           when x"005" => matrix_internal(4) <= break;
                           when x"004" => matrix_internal(5) <= break;
                           when x"003" => matrix_internal(6) <= break;
                           when x"072" =>
                             if joylock='0' then
                               cursor_down <= break; ps2 <= '1';
                             else
                               joy2(1) <= break;  -- keyrah / PS2
                                                  -- duplicate scan
                                                  -- code for down
                                                  -- key and joy2 right?
                             end if;
                           when x"075" => -- JOY2 LEFT
                             if joylock='1' then
                               joy2(0) <= break;
                             else
                               cursor_up <= break; ps2 <= '1';
                             end if;
                           when x"06B" => -- JOY2 UP
                             if joylock='1' then
                               joy2(2) <= break;
                             else
                               cursor_left <= break; ps2 <= '1';
                             end if;
                           -- 3, W, A, 4, Z, S, E, left-SHIFT
                           when x"026" => matrix_internal(8) <= break; -- 3
                           when x"01D" => -- W
                             if joylock='0' then
                               matrix_internal(9) <= break;
                             else
                               joy1(0) <= break;
                             end if;
                           when x"01C" => -- A
                             if joylock='0' then
                               matrix_internal(10) <= break;
                             else
                               joy1(2) <= break;
                             end if;
                           when x"025" => matrix_internal(11) <= break; -- 4
                           when x"01A" => matrix_internal(12) <= break; -- Z
                           when x"01B" =>
                             if joylock='0' then  -- S
                               matrix_internal(13) <= break;
                             else
                               joy1(1) <= break;
                             end if;
                           when x"024" => matrix_internal(14) <= break; -- E
                           when x"012" => -- Left shift
                             if joylock='0' then
                               matrix_internal(15) <= break;
                             else
                               joy1(4) <= break;
                             end if;
                           -- 5, R, D, 6, C, F, T, X
                           when x"02E" => matrix_internal(16) <= break; -- 5
                           when x"02D" => matrix_internal(17) <= break; -- R 
                           when x"023" => -- D
                             if joylock='0' then
                               matrix_internal(18) <= break;
                             else
                               joy1(3) <= break;
                             end if;
                           when x"036" => matrix_internal(19) <= break;
                           when x"021" => matrix_internal(20) <= break;
                           when x"02B" => matrix_internal(21) <= break;
                           when x"02C" => matrix_internal(22) <= break;
                           when x"022" => matrix_internal(23) <= break;

                           -- 7, Y, G, 8, B, H, U, V
                           when x"03D" => matrix_internal(24) <= break;
                           when x"035" => matrix_internal(25) <= break;
                           when x"034" => matrix_internal(26) <= break;
                           when x"03E" => matrix_internal(27) <= break;
                           when x"032" => matrix_internal(28) <= break;
                           when x"033" => matrix_internal(29) <= break;
                           when x"03C" => matrix_internal(30) <= break;
                           when x"02A" => matrix_internal(31) <= break;

                           -- 9, I, J, 0, M, K, O, N
                           when x"046" => matrix_internal(32) <= break;
                           when x"043" => matrix_internal(33) <= break;
                           when x"03B" => matrix_internal(34) <= break;
                           when x"045" => matrix_internal(35) <= break;
                           when x"03A" => matrix_internal(36) <= break;
                           when x"042" => matrix_internal(37) <= break;
                           when x"044" => matrix_internal(38) <= break;
                           when x"031" => matrix_internal(39) <= break;

                           -- +, P, L, -, ., :, @, COMMA
                           when x"04E" => matrix_internal(40) <= break;
                           when x"04D" => matrix_internal(41) <= break;
                           when x"04B" => matrix_internal(42) <= break;
                           when x"055" => matrix_internal(43) <= break;
                           when x"049" => matrix_internal(44) <= break;
                           when x"04C" => matrix_internal(45) <= break;
                           when x"054" => matrix_internal(46) <= break;
                           when x"041" => matrix_internal(47) <= break;

                           -- POUND, *, ;, HOME, right SHIFT, =, UP-ARROW, /
                           when x"170" => matrix_internal(48) <= break;
                           when x"05B" => matrix_internal(49) <= break;
                           when x"052" => matrix_internal(50) <= break;
                           when x"16C" => matrix_internal(51) <= break;
                           when x"059" => right_shift <= break; ps2 <= '1';
                           when x"05D" => matrix_internal(53) <= break;
                           when x"171" => matrix_internal(54) <= break;
                           when x"04A" => matrix_internal(55) <= break;

                           -- 1, LEFT-ARROW, CTRL, 2, SPACE, C=, Q, RUN/STOP
                           when x"016" => matrix_internal(56) <= break;
                           when x"00E" => matrix_internal(57) <= break;
                           when x"014" => matrix_internal(58) <= break; -- CTRL
                           when x"01E" => matrix_internal(59) <= break;
                           when x"029" =>
                             -- SPACE (or fire when using joylock mode)
                             if joylock = '0' then
                               matrix_internal(60) <= break;
                             else
                               joy2(4) <= break;
                             end if;                             
                           when x"11F" => matrix_internal(61) <= break; -- META/WIN for C=
                           when x"127" => matrix_internal(61) <= break; -- META/WIN for C=
                           when x"015" => matrix_internal(62) <= break;
                           when x"076" => matrix_internal(63) <= break;

                           -- Column 8:
                           when x"07E" => matrix_internal(64) <= break; -- NO SCRL
                           when x"00D" => matrix_internal(65) <= break; -- TAB
                           when x"011" => matrix_internal(66) <= break; -- ALT
                           when x"111" => matrix_internal(66) <= break; -- ALTGr
                           when x"077" =>
                             --HELP (Pause) and joylock (number lock key)
                             matrix_internal(67) <= break;
                             if break='1' then
                               joylock <= not joylock;
                             end if;
                           when x"001" => matrix_internal(68) <= break; -- F9/10
                           when x"078" => matrix_internal(69) <= break; -- F11/F12
                           when x"007" => matrix_internal(70) <= break; --F13/F14 (F12)
                           when x"112" => matrix_internal(71) <= break; -- ESC (PrtScr)
                                          
                           when others => null;
                         end case;
                       end if;
                       
          when ParityBit =>  ps2state <= Idle;  -- was StopBit.  See if
                                                -- changing this fixed munching
                                                -- of first bit of back-to-back bytes.

          when StopBit => ps2state <= Idle;
          when others => ps2state <= Idle;
        end case;        
      end if;
      
    end if;
  end process keyread;

end behavioural;
