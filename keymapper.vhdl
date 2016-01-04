library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity keymapper is
  
  port (
    pixelclk : in std_logic;

    cpu_hypervisor_mode : in std_logic;
    drive_led_out : in std_logic;

    last_scan_code : out std_logic_vector(12 downto 0);

    nmi : out std_logic := 'Z';
    reset : out std_logic := 'Z';
    hyper_trap : out std_logic := '1';
    hyper_trap_count : out unsigned(7 downto 0) := x"00";

    -- USE ASC/DIN / CAPS LOCK key to control CPU speed instead of CAPS LOCK function
    speed_gate : out std_logic := '1';
    speed_gate_enable : in std_logic := '1';
    
    -- appears as bit0 of $D607 (see C65 keyboard scan routine at $E406)
    capslock_out : out std_logic := '1';
    
    -- PS2 keyboard interface
    ps2clock  : in  std_logic;
    ps2data   : in  std_logic;
    -- CIA ports
    porta_in  : in  std_logic_vector(7 downto 0);
    portb_in  : in  std_logic_vector(7 downto 0);
    porta_out : out std_logic_vector(7 downto 0);
    portb_out : out std_logic_vector(7 downto 0);

    pota_x : out unsigned(7 downto 0) := x"ff";
    pota_y : out unsigned(7 downto 0) := x"ff";
    potb_x : out unsigned(7 downto 0) := x"ff";    
    potb_y : out unsigned(7 downto 0) := x"ff";
    
    -- read from bit1 of $D607 (see C65 keyboard scan routine at $E406)?
    keyboard_column8_select_in : in std_logic;

    pmod_clock : in std_logic;
    pmod_start_of_sequence : in std_logic;
    pmod_data_in : in std_logic_vector(3 downto 0);
    pmod_data_out : out std_logic_vector(1 downto 0) := "ZZ";
    
    -- ethernet keyboard input interface for remote head mode
    eth_keycode_toggle : in std_logic;
    eth_keycode : in unsigned(15 downto 0)
    );

end entity keymapper;

architecture behavioural of keymapper is

  type ps2_state is (Idle,StartBit,Bit0,Bit1,Bit2,Bit3,Bit4,Bit5,Bit6,Bit7,
                     ParityBit,StopBit);
  signal ps2state : ps2_state := Idle;

  signal resetbutton_state : std_logic := 'Z';
  signal matrix_offset : integer range 0 to 255 := 252;
  signal last_pmod_clock : std_logic := '1';
  
  signal scan_code : unsigned(7 downto 0) := x"FF";
  signal parity : std_logic := '0';

  -- PS2 clock rate is as low as 10KHz.  Allow double that for a timeout
  -- 192MHz/5KHz = 192000/5 = 38400 cycles
  -- 48MHz/5khz = 48000/5 = 9600 cycles
  constant ps2timeout : integer := 9600;
  signal ps2timer : integer range 0 to ps2timeout := 0;

  signal hyper_trap_count_internal : unsigned(7 downto 0) := x"00";
  
  signal ps2clock_samples : std_logic_vector(7 downto 0) := (others => '1');
  signal ps2clock_debounced : std_logic := '0';

  signal ps2data_samples : std_logic_vector(7 downto 0) := (others => '1');
  signal ps2data_debounced : std_logic := '0';

  signal ps2clock_prev : std_logic := '0';

  signal recent_scan_code_list_index : unsigned(7 downto 0) := x"01";

  signal extended : std_logic := '0';
  signal break : std_logic := '0';

  signal matrix : std_logic_vector(71 downto 0) := (others =>'1');
  signal joy1 : std_logic_vector(4 downto 0) := (others =>'1');
  signal joy2 : std_logic_vector(4 downto 0) := (others =>'1');

  signal restore_state : std_logic := '1';
  signal restore_event : std_logic := '0';
  signal restore_down_ticks : unsigned(7 downto 0) := (others => '0');  
  signal restore_up_ticks : unsigned(7 downto 0) := (others => '0');  
  signal fiftyhz_counter : unsigned(7 downto 0) := (others => '0');
  signal reset_drive : std_logic;

  signal eth_keycode_toggle_last : std_logic := '0';
  signal ethernet_keyevent : std_logic := '0';
  
begin  -- behavioural

-- purpose: read from ps2 keyboard interface
  keyread: process (pixelclk, ps2data,ps2clock)
    variable full_scan_code : std_logic_vector(11 downto 0);
    variable portb_value : std_logic_vector(7 downto 0);
    variable porta_value : std_logic_vector(7 downto 0);
  begin  -- process keyread
    if rising_edge(pixelclk) then      
      reset <= reset_drive;
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

        -- Use this 10KHz loop to divide down to 50 hz to work out how many
        -- 50Hz ticks the restore key has been down.  If restore is not down,
        -- then reset the count to zero.
        -- Complementary to this, we also need to know how long RESTORE has
        -- been UP, so that we can send the hypervisor trap/freeze signal when
        -- RESTORE has been double-tapped.

        -- Double-tap restore is detected by DOWN-UP-DOWN signature.
        -- We note how long the UP is, and if it is within our acceptable
        -- timeframe, then we consider a double-tap to have occurred.
        hyper_trap_count <= restore_up_ticks;
        if restore_state='0' then
          if (restore_up_ticks>=1 and restore_up_ticks<18) then
            -- Trap to hypervisor when restore is double-tapped
            -- with the second tap occurring after not more than 12/50ths
            -- (~240ms)
            hyper_trap <= '0';
--            hyper_trap_count <= hyper_trap_count_internal + 1;
--            hyper_trap_count_internal <= hyper_trap_count_internal + 1;
          else
            hyper_trap <= '1';
          end if;
        else
          hyper_trap <= '1';
        end if;
        
        fiftyhz_counter <= fiftyhz_counter + 1;
        if fiftyhz_counter = 200 then
          fiftyhz_counter <= (others => '0');
          if restore_state='0' then
            -- Restore key is down
            if restore_down_ticks /= x"ff" then
              restore_down_ticks <= restore_down_ticks + 1;
            end if;
            restore_up_ticks <= (others => '0');
          else
            -- If restore key is not down, reset count of how long it has been
            -- down, and release NMI and reset lines in case we were asserting
            -- them.
            -- NOTE: This approach means that NMI and RESET will be asserted for
            -- between 1 cycle and 1/50th of a second. There is a possible problem
            -- with reset and NMI being asserted for less than 2 cycles, but
            -- this should be extremely rare.  We have solved this by resetting
            -- fifyhz_counter when the reset key is released.
            restore_down_ticks <= (others => '0');
            if restore_up_ticks /= x"ff" then
              restore_up_ticks <= restore_up_ticks + 1;
            end if;
            nmi <= 'Z';
            reset_drive <= resetbutton_state;
            hyper_trap <= '1';
          end if;
        end if;
      end if;

      ------------------------------------------------------------------------
      -- Read from MEGA keyboard/joystick/expansion port PMOD interface
      ------------------------------------------------------------------------
      -- This interface has a clock, start-of-sequence signal and 4 data lines
      -- The data is pumped out in the correct order for us to just stash it
      -- into the matrix (or, at least it will when it is implemented ;)
      last_pmod_clock <= pmod_clock;
      if pmod_clock='1' and last_pmod_clock='0' then
        -- Data available
        if pmod_start_of_sequence='1' then
          -- Write first four bits, and set offset for next time
          matrix_offset <= 4;
          matrix(3 downto 0) <= pmod_data_in;
          -- First two bits of output from FPGA to input PCB is the status of
          -- the two LEDs: power LED is on when CPU is not in hypervisor mode,
          -- drive LED shows F011 drive status.
          pmod_data_out(0) <= not cpu_hypervisor_mode;
          pmod_data_out(1) <= drive_led_out;
        else
          -- Clear output bits for bit positions for which we yet have no assignment
          pmod_data_out <= "00";
          
          if matrix_offset < 252 then
            matrix_offset <= matrix_offset+ 4;
          end if;
          -- Read keyboard matrix when required
          if matrix_offset < 72 then
            matrix((matrix_offset +3) downto matrix_offset) <= pmod_data_in;
          end if;
          -- Joysticks + restore + capslock + reset? (72-79, 80-87)
          if matrix_offset = 72 then
            -- joy 1 directions
            joy1(3 downto 0) <= pmod_data_in;
          end if;
          if matrix_offset = 76 then
            -- restore is active low, like all other keys
            restore_state <= pmod_data_in(3);
            if speed_gate_enable='1' then
              -- CAPS LOCK UP = force 48MHz, down = enable speed control
              speed_gate <= not pmod_data_in(2);
              capslock_out <= '1';
            else
              -- CAPS LOCK does CAPS LOCK, and speed control is enabled
              speed_gate <= '1';
              capslock_out <= pmod_data_in(2);
            end if;
            joy1(4) <= pmod_data_in(0);
            -- Check for RESTORE key being released, and adjust action
            -- based on how long it was being held down.
            if pmod_data_in(3)='1' and restore_state='0' then
              if restore_down_ticks < 25 then
                nmi <= '0';
              -- But holding it down for >2 seconds does nothing,
              -- incase someone holds it by mistake.
              elsif restore_down_ticks < 100 then
                reset_drive <= '0';
              end if;
              -- Make sure that next check for releasing NMI
              -- and reset is not for almost 1/50th of a second.
              fiftyhz_counter <= (others => '0');
            end if;
          end if;
          if matrix_offset = 80 then
            -- joy 2 directions
            joy2(3 downto 0) <= pmod_data_in;
          end if;
          if matrix_offset = 84 then
            if pmod_data_in(3)='0' then
              resetbutton_state <= '0';
            else
              resetbutton_state <= 'Z';
            end if;
            joy2(4) <= pmod_data_in(0);
          end if;
          -- Expansion port state (88-127)
          -- Reserved for extra stuff (128-255)
          -- 4x 8-bit analog paddle inputs
          if matrix_offset = 128 then
            pota_x(7 downto 4) <= unsigned(pmod_data_in);
          end if;
          if matrix_offset = 132 then
            pota_x(3 downto 0) <= unsigned(pmod_data_in);
          end if;
          if matrix_offset = 136 then
            pota_y(7 downto 4) <= unsigned(pmod_data_in);
          end if;
          if matrix_offset = 140 then
            pota_y(3 downto 0) <= unsigned(pmod_data_in);
          end if;
          if matrix_offset = 144 then
            potb_x(7 downto 4) <= unsigned(pmod_data_in);
          end if;
          if matrix_offset = 148 then
            potb_x(3 downto 0) <= unsigned(pmod_data_in);
          end if;
          if matrix_offset = 152 then
            potb_y(7 downto 4) <= unsigned(pmod_data_in);
          end if;
          if matrix_offset = 156 then
            potb_y(3 downto 0) <= unsigned(pmod_data_in);
          end if;
        end if;
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
                         last_scan_code <= break & full_scan_code;

                         case full_scan_code is
                           when x"17D" =>
                              -- Restore key shall do NMI as expected, but also
                              -- reset
                             restore_state <= break;
                             if break='1' then
                               if restore_down_ticks < 25 then
                                 nmi <= '0';
                               -- But holding it down for >2 seconds does nothing,
                               -- incase someone holds it by mistake.
                               elsif restore_down_ticks < 100 then
                                 reset_drive <= '0';
                               end if;
                               -- Make sure that next check for releasing NMI
                               -- and reset is not for almost 1/50th of a second.
                               fiftyhz_counter <= (others => '0');
                             end if;
                             
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
                           when x"075" =>  -- JOY2 LEFT
                             joy2(0) <= break;
                           when x"074" =>  -- JOY2 DOWN
                             joy2(3) <= break;
--                           when x"072" =>  -- JOY2 RIGHT
--                             joy2(3) <= break;
                           when x"06b" =>  -- JOY2 UP
                             joy2(2) <= break;
                           when x"073" =>  -- JOY2 FIRE
                             joy2(4) <= break;
                                           
                           -- DELETE, RETURN, RIGHT, F7, F1, F3, F5, down
                           when x"066" => matrix(0) <= break;
                           when x"05A" => matrix(1) <= break;
                           when x"174" => matrix(2) <= break;
                           when x"083" => matrix(3) <= break;
                           when x"005" => matrix(4) <= break;
                           when x"004" => matrix(5) <= break;
                           when x"003" => matrix(6) <= break;
                           when x"072" => matrix(7) <= break;
                                          joy2(1) <= break;  -- keyrah
                                                             -- duplicate scan
                                                             -- code for down
                                                             -- key and joy2 right?

                           -- 3, W, A, 4, Z, S, E, left-SHIFT
                           when x"026" => matrix(8) <= break;
                           when x"01D" => matrix(9) <= break;
                           when x"01C" => matrix(10) <= break;
                           when x"025" => matrix(11) <= break;
                           when x"01A" => matrix(12) <= break;
                           when x"01B" => matrix(13) <= break;
                           when x"024" => matrix(14) <= break;
                           when x"012" => matrix(15) <= break;

                           -- 5, R, D, 6, C, F, T, X
                           when x"02E" => matrix(16) <= break;
                           when x"02D" => matrix(17) <= break;
                           when x"023" => matrix(18) <= break;
                           when x"036" => matrix(19) <= break;
                           when x"021" => matrix(20) <= break;
                           when x"02B" => matrix(21) <= break;
                           when x"02C" => matrix(22) <= break;
                           when x"022" => matrix(23) <= break;

                           -- 7, Y, G, 8, B, H, U, V
                           when x"03D" => matrix(24) <= break;
                           when x"035" => matrix(25) <= break;
                           when x"034" => matrix(26) <= break;
                           when x"03E" => matrix(27) <= break;
                           when x"032" => matrix(28) <= break;
                           when x"033" => matrix(29) <= break;
                           when x"03C" => matrix(30) <= break;
                           when x"02A" => matrix(31) <= break;

                           -- 9, I, J, 0, M, K, O, N
                           when x"046" => matrix(32) <= break;
                           when x"043" => matrix(33) <= break;
                           when x"03B" => matrix(34) <= break;
                           when x"045" => matrix(35) <= break;
                           when x"03A" => matrix(36) <= break;
                           when x"042" => matrix(37) <= break;
                           when x"044" => matrix(38) <= break;
                           when x"031" => matrix(39) <= break;

                           -- +, P, L, -, ., :, @, COMMA
                           when x"04E" => matrix(40) <= break;
                           when x"04D" => matrix(41) <= break;
                           when x"04B" => matrix(42) <= break;
                           when x"055" => matrix(43) <= break;
                           when x"049" => matrix(44) <= break;
                           when x"04C" => matrix(45) <= break;
                           when x"054" => matrix(46) <= break;
                           when x"041" => matrix(47) <= break;

                           -- POUND, *, ;, HOME, right SHIFT, =, UP-ARROW, /
                           when x"170" => matrix(48) <= break;
                           when x"05B" => matrix(49) <= break;
                           when x"052" => matrix(50) <= break;
                           when x"16C" => matrix(51) <= break;
                           when x"059" => matrix(52) <= break;
                           when x"05D" => matrix(53) <= break;
                           when x"171" => matrix(54) <= break;
                           when x"04A" => matrix(55) <= break;

                           -- 1, LEFT-ARROW, CTRL, 2, SPACE, C=, Q, RUN/STOP
                           when x"016" => matrix(56) <= break;
                           when x"00E" => matrix(57) <= break;
                           when x"00D" => matrix(58) <= break;
                           when x"01E" => matrix(59) <= break;
                           when x"029" => matrix(60) <= break;
                           when x"014" => matrix(61) <= break;
                           when x"015" => matrix(62) <= break;
                           when x"076" => matrix(63) <= break;
                                          
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

      -------------------------------------------------------------------------
      -- Update C64 CIA ports
      -------------------------------------------------------------------------
      -- Whenever a PS2 key goes down, clear the appropriate bit(s) in the
      -- matrix.  Whenever the corresponding key goes up, set the appropriate
      -- bit(s) again.  This matrix can then be used to emulate the matrix for
      -- interfacing with the CIAs.

      -- We will use the VICE keyboard mapping so that we are default with the
      -- keyrah2 C64 keyboard to USB adapter.

      -- C64 keyboard matrix can be found at: http://sta.c64.org/cbm64kbdlay.html
      --                                      $DC01 bits
      --                0      1      2      3      4      5      6      7
      -- $DC00 values  
      -- Bit#0 $FE      Delete Return right  F7     F1     F3     F5     down
      -- Bit#1 $FD      3      W      A      4      Z      S      E      left Shift
      -- Bit#2 $FB      5      R      D      6      C      F      T      X
      -- Bit#3 $F7      7      Y      G      8      B      H      U      V
      -- Bit#4 $EF	9      I      J      0      M      K      O      N
      -- Bit#5 $DF	+      P      L      minus  .      :      @      ,
      -- Bit#6 $BF      pound  *      ;	     Home   rshift =	  ^	 slash
      -- Bit#7 $7F	1      _      CTRL   2      Space  C=     Q      Run/Stop
      -- RESTORE - Hardwire to NMI
      
      -- Keyrah v2 claims to use default VICE matrix.  Yet to find that clearly
      -- summarised.  Will probably just exhaustively explore it with my keyrah
      -- when it arrives.

      -- keyboard scancodes for the more normal keys from a keyboard I have here
      -- (will replace these with the keyrah obtained ones)
      --                                      $DC01 bits
      --                0      1      2      3      4      5      6      7
      -- $DC00 values  
      -- Bit#0 $FE      E0 71  5A     E0 74  83     05     04     03     72
      -- Bit#1 $FD      26     1D     1C     25     1A     1B     24     12
      -- Bit#2 $FB      2E     2D     23     36     21     2B     2C     22
      -- Bit#3 $F7      3D     35     34     3E     32     33     3C     2A
      -- Bit#4 $EF	46     43     3B     45     3A     42     44     31
      -- Bit#5 $DF	55     4D     4B     4E     49     54     5B     41
      -- Bit#6 $BF      52     5D     4C     E0 6C  59     E0 69  75	 4A
      -- Bit#7 $7F	16     6B     14     1E     29     11     15     76
      -- RESTORE - 0E (`/~ key)

      -- C64 drives lines low on $DC00, and then reads $DC01
      -- This means that we read from porta_in, to compute values for portb_out
      
      portb_value := x"FF";
      for i in 0 to 7 loop
        if porta_in(i)='0' then
          for j in 0 to 7 loop
            portb_value(j) := portb_value(j) and matrix((i*8)+j);
          end loop;  -- j
        end if;        
      end loop;
      if keyboard_column8_select_in='0' then
        for j in 0 to 7 loop
          portb_value(j) := portb_value(j) and matrix(64+j);
        end loop;  -- j
      end if;

      -- We should also do it the otherway around as well
      porta_value := x"FF";
      for i in 0 to 7 loop
        if portb_in(i)='0' then
          for j in 0 to 7 loop
            porta_value(j) := porta_value(j) and matrix((j*8)+i);
          end loop;  -- j
        end if;        
      end loop;      
      
      -- Keyboard rows and joystick 1
      portb_out(7 downto 5) <= portb_value(7 downto 5);
      portb_out(4) <= portb_value(4) and joy1(4);
      portb_out(3) <= portb_value(3) and joy1(3);
      portb_out(2) <= portb_value(2) and joy1(2);
      portb_out(1) <= portb_value(1) and joy1(1);
      portb_out(0) <= portb_value(0) and joy1(0);

      -- Keyboard columns and joystick 2
      porta_out(7 downto 5) <= porta_value(7 downto 5);
      porta_out(4) <= porta_value(4) and joy2(4);
      porta_out(3) <= porta_value(3) and joy2(3);
      porta_out(2) <= porta_value(2) and joy2(2);
      porta_out(1) <= porta_value(1) and joy2(1);
      porta_out(0) <= porta_value(0) and joy2(0);
    end if;
  end process keyread;

end behavioural;
