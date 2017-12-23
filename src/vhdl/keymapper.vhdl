library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity keymapper is
  port (
    ioclock : in std_logic;
    reset_in : in std_logic;
    matrix_mode_in : std_logic;
    
    -- Which inputs shall we incorporate
    virtual_disable : in std_logic;
    matrix_virtual : in std_logic_vector(71 downto 0);
    
    physkey_disable : in std_logic;
    matrix_physkey : in std_logic_vector(71 downto 0);
    capslock_physkey : in std_logic;
    restore_physkey : in std_logic;

    joy_disable : in std_logic;
    joya_physkey : in std_logic_vector(4 downto 0);
    joyb_physkey : in std_logic_vector(4 downto 0);

    widget_disable : in std_logic;
    matrix_widget : in std_logic_vector(71 downto 0);
    joya_widget : in std_logic_vector(4 downto 0);
    joyb_widget : in std_logic_vector(4 downto 0);
    capslock_widget : in std_logic;
    restore_widget : in std_logic;

    ps2_disable : in std_logic;
    matrix_ps2 : in std_logic_vector(71 downto 0);
    joya_ps2 : in std_logic_vector(4 downto 0);
    joyb_ps2 : in std_logic_vector(4 downto 0);
    capslock_ps2 : in std_logic;
    restore_ps2 : in std_logic;

    matrix_combined : out std_logic_vector(71 downto 0) := (others => '1');
    
    -- RESTORE when held or double-tapped does special things
    restore_out : out std_logic := '1';
    reset_out : out std_logic := '1';
    hyper_trap_out : out std_logic := '1';
    
    -- USE ASC/DIN / CAPS LOCK key to control CPU speed instead of CAPS LOCK function
    speed_gate : out std_logic := '1';
    speed_gate_enable : in std_logic := '1';
    
    -- appears as bit0 of $D607 (see C65 keyboard scan routine at $E406)
    capslock_out : out std_logic := '1';

    -- Registers for debugging
    key_debug_out : out std_logic_vector(7 downto 0);
    hyper_trap_count : out unsigned(7 downto 0) := x"00";
    restore_up_count : out unsigned(7 downto 0) := x"00";
    restore_down_count : out unsigned(7 downto 0) := x"00";
    
    -- CIA1 ports
    porta_in  : in  std_logic_vector(7 downto 0);
    portb_in  : in  std_logic_vector(7 downto 0);
    porta_out : out std_logic_vector(7 downto 0);
    portb_out : out std_logic_vector(7 downto 0);
    porta_ddr : in  std_logic_vector(7 downto 0);
    portb_ddr : in  std_logic_vector(7 downto 0);

    pota_x : out unsigned(7 downto 0) := x"ff";
    pota_y : out unsigned(7 downto 0) := x"ff";
    potb_x : out unsigned(7 downto 0) := x"ff";    
    potb_y : out unsigned(7 downto 0) := x"ff";
    
    -- read from bit1 of $D607 (see C65 keyboard scan routine at $E406)?
    keyboard_column8_select_in : in std_logic

    );

end entity keymapper;

architecture behavioural of keymapper is

  signal matrix_offset : integer range 0 to 255 := 252;
  
  signal hyper_trap_count_internal : unsigned(7 downto 0) := x"00";  

  -- Allow inverting of capslock sense, so that we always boot with it off.
  signal capslock_xor : std_logic := '0';
  
  signal matrix : std_logic_vector(71 downto 0) := (others =>'1');

  -- PS2 keyboard emulated joystick
  signal joya : std_logic_vector(7 downto 0) := (others =>'1');
  signal joyb : std_logic_vector(7 downto 0) := (others =>'1');
  
  signal restore_state : std_logic := '1';
  signal last_restore_state : std_logic := '1';
  signal restore_down_ticks : unsigned(15 downto 0) := (others => '0');  
  signal restore_up_ticks : unsigned(15 downto 0) := (others => '0');  
  signal fiftyhz_counter : unsigned(28 downto 0) := (others => '0');
  signal reset_drive : std_logic := '1';

  signal eth_keycode_toggle_last : std_logic := '0';
  signal ethernet_keyevent : std_logic := '0';

  signal key_num : integer range 0 to 71 := 0;
  signal hyper_trap : std_logic := '1';

  signal porta_pins : std_logic_vector(7 downto 0);
  signal portb_pins : std_logic_vector(7 downto 0);
  
begin  -- behavioural

  keyread: process (ioclock)
    variable portb_value : std_logic_vector(7 downto 0);
    variable porta_value : std_logic_vector(7 downto 0);
  begin  -- process keyread
    if rising_edge(ioclock) then      
      reset_out <= reset_drive;
      hyper_trap_out <= hyper_trap;

      -- Update keyboard matrix as combination of the various inputs
      if key_num < 71 then
        key_num <= key_num + 1;
      else
        key_num <= 0;
      end if;

      matrix(key_num) <= '1'    
                         and (matrix_physkey(key_num) or physkey_disable)
                         and (matrix_widget(key_num) or widget_disable)
                         and (matrix_virtual(key_num) or virtual_disable)
                         and (matrix_ps2(key_num) or ps2_disable);

      -- Update unified view for export
      matrix_combined(key_num) <= matrix(key_num);

      -- And joysticks
      for n in 0 to 4 loop
        joya(n) <= '1' and (joya_physkey(n) or joy_disable)
                   and (joya_widget(n) or widget_disable)
                   and (joya_ps2(n) or ps2_disable);
        joyb(n) <= '1' and (joyb_physkey(n) or joy_disable)
                   and (joyb_widget(n) or widget_disable)
                   and (joyb_ps2(n) or ps2_disable);
      end loop;
      
      if reset_in = '0' then
        -- if caps lock down on reset, invert sense
        capslock_xor <= capslock_ps2 xor capslock_physkey xor capslock_widget xor '1';
      end if;

      -- Calculate caps lock, with each input toggling
      capslock_out <= capslock_xor
                      xor (capslock_ps2 or ps2_disable)
                      xor (capslock_physkey or physkey_disable)
                      xor (capslock_widget or widget_disable);


      -- Debug problems with restore and capslock
      key_debug_out(0) <= capslock_xor
                          xor (capslock_ps2 or ps2_disable)
                          xor (capslock_physkey or physkey_disable)
                          xor (capslock_widget or widget_disable);
      key_debug_out(1) <= capslock_widget;
      key_debug_out(2) <= capslock_ps2;
      key_debug_out(3) <= restore_state;
      key_debug_out(4) <= restore_widget;
      key_debug_out(5) <= restore_ps2;
      key_debug_out(6) <= restore_state;
      key_debug_out(7) <= last_restore_state;
      
      restore_up_count <= restore_up_ticks(7 downto 0);
      restore_down_count <= restore_down_ticks(7 downto 0);

      if fiftyhz_counter /= ( 50000000 / 50 ) then
        fiftyhz_counter <= fiftyhz_counter + 1;
      else
        fiftyhz_counter <= (others => '0');        

        restore_state <= (restore_ps2 or ps2_disable)
                         and (restore_physkey or physkey_disable)
                         and (restore_widget or widget_disable);
        
        last_restore_state <= restore_state;

        -- 0= restore down (pressed), 1 = restore up (not-pressed)
        if restore_state='0' and last_restore_state='1' then
          -- Restore has just been pressed
          if (restore_up_ticks > 1) and (restore_up_ticks < 16) then
            -- If between 50ms and 800ms, then it is a double-tap:
            -- triger a hypervisor trap
            hyper_trap <= '0';
            hyper_trap_count <= hyper_trap_count_internal + 1;
            hyper_trap_count_internal <= hyper_trap_count_internal + 1;
          end if;
        elsif restore_state='1' and last_restore_state='0' then
          -- Restore has just been released
          if restore_down_ticks < 32 then
            restore_out <= '0';
          -- But holding it down for >2 seconds does nothing,
          -- incase someone holds it by mistake.
          elsif restore_down_ticks < 128 then
            reset_drive <= '0';
            report "asserting reset via RESTORE key";
          end if;
        else
          hyper_trap <= '1';
          restore_out <= '1';
          reset_drive <= '1';
        end if;
        
        if restore_state='0' then
          -- Restore key is down
          restore_up_ticks <= (others => '0');
          if restore_down_ticks /= x"ffff" then
            restore_down_ticks <= restore_down_ticks + 1;
          end if;
        else
          -- Restore key is up
          restore_down_ticks <= (others => '0');
          if restore_up_ticks /= x"ffff" then
            restore_up_ticks <= restore_up_ticks + 1;
          end if;
        end if;
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

      -- XXX We see some reliability problems when scanning the keyboad on the
      -- M65 prototype PCB, particularly with the C= key being confused for =.
      -- This is a bit weird.  They are adjacent bits on the same column, so
      -- perhaps there is some electrical problem behind it? Or perhaps it is
      -- just that we scan it too quickly?  If it is a scanning speed problem,
      -- then we should scan the entire matrix in continuously at a slower
      -- speed,and reconstruct it in memory.  In fact, we basically need to do
      -- this anyway, so that we can use the real keyboard for input into the
      -- matrix/secure mode facility, i.e., we need to synthesise serial input
      -- characters based on the matrix state.
      
      portb_value := x"FF";
      for i in 0 to 7 loop
        if porta_in(i)='0' then
          for j in 0 to 7 loop
            portb_value(j) := portb_value(j) and (matrix((i*8)+j) or matrix_mode_in);
          end loop;  -- j
        else
          portb_value := (others => '1');
        end if;        
      end loop;
      if keyboard_column8_select_in='0' then
        for j in 0 to 7 loop
          portb_value(j) := portb_value(j) and (matrix(64+j) or matrix_mode_in);
        end loop;  -- j
      end if;

      -- We should also do it the otherway around as well

      for i in 0 to 7 loop
        if portb_in(i)='0' then
          for j in 0 to 7 loop
            porta_value(j) := porta_value(j) and (matrix((j*8)+i) or matrix_mode_in);
            report "updating porta_value(" & integer'image(j)
              & ") = " & std_logic'image(porta_value(j))
              & " & ("
              & std_logic'image(matrix((j*8)+i))
              & " | "
              & std_logic'image(matrix_mode_in)
              & ")";
          end loop;  -- j
        else
          -- keyboard not being scanned on this bit
          porta_value := (others => '1');
          report "porta_value = "
            & to_string(porta_value) & " as not being keyboard scanned.";
        end if;        
      end loop;      
      
      -- Update physical pins to reflect what the CIA is asking for
      for b in 0 to 7 loop
        if porta_ddr(b)='1' then
          -- Pin is output
          report "porta copying porta_in(" & integer'image(b) & ") due to ddr=1. Copied value = " & std_logic'image(porta_in(b));
          porta_pins(b) <= porta_in(b);
        else
          -- Pin is input, i.e., tri-stated
          report "porta tristating porta_in(" & integer'image(b) & ") due to ddr=0.";
          porta_pins(b) <= '1'; -- Tri-state emulated by having line high
        end if;
        report "porta_pins = " & to_string(porta_pins);
        if portb_ddr(b)='1' then
          -- Pin is output
          portb_pins(b) <= portb_in(b);
        else
          -- Pin is input, i.e., tri-stated
          portb_pins(b) <= 'Z';
        end if;
      end loop;

      -- Reading the CIAs requires us to take into account our modeled port
      -- values for the keyboard matrix, combined with the actual values coming
      -- in on the pins.  If DDR='1', then we don't want to read the pin, but if
      -- DDR='0', and if the pin is '0', then it should pull low.
      for b in 0 to 7 loop
        if (porta_ddr(b) = '0') and (porta_pins(b) = '0') then
          -- CIA should read bit as low
          porta_out(b) <= '0';
          report "porta_out(" & integer'image(b) & ") = 0, due to ddr=0 and drive=0";
        else
          porta_out(b) <= porta_value(b) and joya(b);
          report "porta_out(" & integer'image(b) & ") = " &
            std_logic'image(porta_value(b)) & " & "
            & std_logic'image(joya(b))
            & ", due to ddr=0 and drive=0";
        end if;
        if (portb_ddr(b) = '0') and (portb_pins(b) = '0') then
          -- CIA should read bit as low
          portb_out(b) <= '0';
        else
          portb_out(b) <= portb_value(b) and joyb(b);
        end if;
      end loop;
    end if;

  end process keyread;

end behavioural;
