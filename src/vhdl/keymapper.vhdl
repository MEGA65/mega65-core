library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity keymapper is
  port (
    cpuclock : in std_logic;
    reset_in : in std_logic;

    viciv_frame_indicate : in std_logic;
    
    matrix_mode_in : in std_logic; -- Is the system displaying matrix mode (not
                                   -- to be confused with the keyboard matrix).    
    joya_rotate : in std_logic;
    joyb_rotate : in std_logic;
    joyswap : in std_logic;
    
    -- Which inputs shall we incorporate
    virtual_disable : in std_logic;
    matrix_col_virtual : in std_logic_vector(7 downto 0);
    
    physkey_disable : in std_logic;
    matrix_col_physkey : in std_logic_vector(7 downto 0);
    capslock_physkey : in std_logic;
    restore_physkey : in std_logic;
    restore_virtual : in std_logic;

    joykey_disable : in std_logic;
    joya_physkey : in std_logic_vector(4 downto 0);
    joyb_physkey : in std_logic_vector(4 downto 0);

    joyreal_disable : in std_logic;
    joya_real : in std_logic_vector(4 downto 0);
    joyb_real : in std_logic_vector(4 downto 0);
    
    widget_disable : in std_logic;
    matrix_col_widget : in std_logic_vector(7 downto 0);
    
    joya_widget : in std_logic_vector(4 downto 0);
    joyb_widget : in std_logic_vector(4 downto 0);
    capslock_widget : in std_logic;
    restore_widget : in std_logic;

    ps2_disable : in std_logic;
    matrix_col_ps2 : in std_logic_vector(7 downto 0);
    joya_ps2 : in std_logic_vector(4 downto 0);
    joyb_ps2 : in std_logic_vector(4 downto 0);
    capslock_ps2 : in std_logic;
    restore_ps2 : in std_logic;

    -- This is the keyboard matrix column we are currently sourcing from all KB input modules.
    matrix_col_idx : out integer range 0 to 15;
    
    -- (more or less) continuously scanning combined matrix output that other blocks can either
    -- make use of directly or snoop into local copies.
    matrix_combined_col : out std_logic_vector(7 downto 0);
    matrix_combined_col_idx : out integer range 0 to 15;
    
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

    -- read from bit1 of $D607 (see C65 keyboard scan routine at $E406)?
    keyboard_column8_select_in : in std_logic

    );

end entity keymapper;

architecture behavioural of keymapper is

  signal matrix_offset : integer range 0 to 255 := 252;

  signal last_viciv_frame_indicate : std_logic := '0';
  
  signal hyper_trap_count_internal : unsigned(7 downto 0) := x"00";  

  -- Allow inverting of capslock sense, so that we always boot with it off.
  signal capslock_xor : std_logic := '0';
  
  -- new compact LUT based keyboard matrix
  type matrix_array_t is array(0 to 15) of std_logic_vector(7 downto 0);

  --signal matrix_array : matrix_array_t;
  signal m_col_idx : integer range 0 to 15 := 0;
  signal km_input : std_logic_vector(7 downto 0);
  
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
  signal hyper_trap_on_frame_sync : std_logic := '0';

  signal porta_pins : std_logic_vector(7 downto 0);
  signal portb_pins : std_logic_vector(7 downto 0);

  -- The current column we're scanning from the matrix and the matrix ram output
  signal scan_idx : integer range 0 to 15 := 9;
  signal scan_col : std_logic_vector(7 downto 0); 

  -- These hold the intermediate values as we sweep.
  signal portb_value_scan : std_logic_vector(7 downto 0);
  signal porta_value_scan : std_logic_vector(7 downto 0);
  
  -- Re-assemble the keyboard matrix, and de-glitch it.
  signal matrix0 : std_logic_vector(71 downto 0);
  signal matrix1 : std_logic_vector(71 downto 0);
  signal matrix : std_logic_vector(71 downto 0);
  
    component kb_matrix_ram is
    port (ClkA : in std_logic;
          addressa : in integer range 0 to 15;
          wea : in std_logic;
          dia : in unsigned(7 downto 0);
          addressb : in integer range 0 to 15;
          dob : out unsigned(7 downto 0)
          );
  end component;
  
begin  -- behavioural

  km_input <=
                "11111111"
                and (matrix_col_physkey or (7 downto 0 => physkey_disable))
                and (matrix_col_widget or (7 downto 0 => widget_disable))
                and (matrix_col_virtual or (7 downto 0 => virtual_disable))
                and (matrix_col_ps2 or (7 downto 0 => ps2_disable));
  
  -- small 9x8 distributed RAM used to store keyboard matrix state.  Its done this way
  -- to ensure we get the semantics correct for this to be done with LUTs and not 72 flip flops.
  kmm: entity work.kb_matrix_ram
  port map (
    clkA => cpuclock,
    addressa => m_col_idx,
    dia => km_input,
    wea => x"FF",
    addressb => scan_idx,
    dob => scan_col
    );

  matrix_col_idx <= m_col_idx;

  -- Let other blocks snoop combined matrix output as we scan through it.
  scanexport: process(cpuclock)
  begin
    if rising_edge(cpuclock) then
      if scan_idx < 9 then
        matrix_combined_col <= scan_col;
        matrix_combined_col_idx <= scan_idx;
      end if;
    end if;
  end process;
  
  keyread: process (cpuclock)
    variable portb_value : std_logic_vector(7 downto 0);
    variable porta_value : std_logic_vector(7 downto 0);
    variable scan_col_out : std_logic;
    variable n2 : integer;
  begin  -- process keyread
    if rising_edge(cpuclock) then      
      reset_out <= reset_drive;
      hyper_trap_out <= hyper_trap;

      -- Update keyboard matrix as combination of the various inputs
      if key_num < 71 then
        key_num <= key_num + 1;
      else
        key_num <= 0;
      end if;

      if m_col_idx < 8 then
        m_col_idx <= m_col_idx + 1;
      else
        m_col_idx <= 0;
      end if;
      
      -- And joysticks (with optional 180 degree rotation for swapping between
      -- left and right handed operation of sticks with only a single button
      -- on the base.      
      for n in 0 to 3 loop
        if joya_rotate = '1' then
          if n = 0 then
            n2 := 1;
          elsif n = 1 then
            n2 := 0;
          elsif n = 2 then
            n2 := 3;
          elsif n = 3 then
            n2 := 2;
          end if;
        else
          n2 := n;
        end if;
        if joyswap='0' then
          joya(n) <= '1' and (joya_physkey(n2) or joykey_disable)
                     and (joya_widget(n2) or widget_disable)
                     and (joya_real(n2) or joyreal_disable)
                     and (joya_ps2(n2) or ps2_disable);
        else
          joyb(n) <= '1' and (joya_physkey(n2) or joykey_disable)
                     and (joya_widget(n2) or widget_disable)
                     and (joya_real(n2) or joyreal_disable)
                     and (joya_ps2(n2) or ps2_disable);
        end if;
        if joyb_rotate = '1' then
          if n = 0 then
            n2 := 1;
          elsif n = 1 then
            n2 := 0;
          elsif n = 2 then
            n2 := 3;
          elsif n = 3 then
            n2 := 2;
          end if;
        else
          n2 := n;
        end if;
        if joyswap='0' then
          joyb(n) <= '1' and (joyb_physkey(n2) or joykey_disable)
                     and (joyb_widget(n2) or widget_disable)
                     and (joyb_real(n2) or joyreal_disable)
                     and (joyb_ps2(n2) or ps2_disable);
        else
          joya(n) <= '1' and (joyb_physkey(n2) or joykey_disable)
                     and (joyb_widget(n2) or widget_disable)
                     and (joyb_real(n2) or joyreal_disable)
                     and (joyb_ps2(n2) or ps2_disable);
        end if;
      end loop;
      if joyswap='0' then
        joya(4) <= '1' and (joya_physkey(4) or joykey_disable)
                   and (joya_widget(4) or widget_disable)
                   and (joya_real(4) or joyreal_disable)
                   and (joya_ps2(4) or ps2_disable);
        joyb(4) <= '1' and (joyb_physkey(4) or joykey_disable)
                   and (joyb_widget(4) or widget_disable)
                   and (joyb_real(4) or joyreal_disable)
                   and (joyb_ps2(4) or ps2_disable);
      else
        joyb(4) <= '1' and (joya_physkey(4) or joykey_disable)
                   and (joya_widget(4) or widget_disable)
                   and (joya_real(4) or joyreal_disable)
                   and (joya_ps2(4) or ps2_disable);
        joya(4) <= '1' and (joyb_physkey(4) or joykey_disable)
                   and (joyb_widget(4) or widget_disable)
                   and (joyb_real(4) or joyreal_disable)
                   and (joyb_ps2(4) or ps2_disable);
      end if;

      
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

      restore_state <= (restore_ps2 or ps2_disable)
                       and (restore_physkey or physkey_disable)
                       and (restore_virtual or virtual_disable)
                       and (restore_widget or widget_disable);
      
      if fiftyhz_counter /= ( 50000000 / 50 ) then
        fiftyhz_counter <= fiftyhz_counter + 1;
      else
        fiftyhz_counter <= (others => '0');        
        
        last_restore_state <= restore_state;

        -- 0= restore down (pressed), 1 = restore up (not-pressed)
        if restore_state='0' and last_restore_state='1' then
          -- Restore has just been pressed, do nothing special.
          -- (Events happen on rising edge)
        elsif restore_state='1' and last_restore_state='0' then
          -- Restore has just been released
          if restore_down_ticks < 8 then
            -- <0.25 seconds = quick tap = trigger NMI
            restore_out <= '0';
          elsif restore_down_ticks < 128 then
            -- 0.25 - ~ 4 second hold = trigger hypervisor trap
            hyper_trap_on_frame_sync <= '1';
--          elsif restore_down_ticks < 128 then
            -- Long hold = do RESET instead of NMI
            -- But holding it down for >4 seconds does nothing,
            -- incase someone holds it by mistake, and wants to abort doing a reset.
--            reset_drive <= '0';
--            report "asserting reset via RESTORE key";
          end if;
        else
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

      -- Trigger RESTORE long press trap always at same point in the frame,
      -- so that we can unfreeze with relative timing properly maintained.
      last_viciv_frame_indicate <= viciv_frame_indicate;
      if hyper_trap_on_frame_sync = '1' and last_viciv_frame_indicate='0' and viciv_frame_indicate='1' then
        hyper_trap_on_frame_sync <= '0';
        hyper_trap <= '0';
        hyper_trap_count <= hyper_trap_count_internal + 1;
        hyper_trap_count_internal <= hyper_trap_count_internal + 1;
      else
        hyper_trap <= '1';          
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
      -- Bit#4 $EF      9      I      J      0      M      K      O      N
      -- Bit#5 $DF	    +      P      L      minus  .      :      @      ,
      -- Bit#6 $BF      pound  *      ;      Home   rshift =      ^      slash
      -- Bit#7 $7F      1      _      CTRL   2      Space  C=     Q      Run/Stop
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
      -- Bit#4 $EF      46     43     3B     45     3A     42     44     31
      -- Bit#5 $DF      55     4D     4B     4E     49     54     5B     41
      -- Bit#6 $BF      52     5D     4C     E0 6C  59     E0 69  75     4A
      -- Bit#7 $7F      16     6B     14     1E     29     11     15     76
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
      
      scan_col_out := (scan_col(0) and scan_col(1) and scan_col(2) and scan_col(3) and
                       scan_col(4) and scan_col(5) and scan_col(6) and scan_col(7));

      case scan_idx is
        when 0 => matrix0(7 downto 0) <= scan_col;
        when 1 => matrix0(15 downto 8) <= scan_col;
        when 2 => matrix0(23 downto 16) <= scan_col;
        when 3 => matrix0(31 downto 24) <= scan_col;
        when 4 => matrix0(39 downto 32) <= scan_col;
        when 5 => matrix0(47 downto 40) <= scan_col;
        when 6 => matrix0(55 downto 48) <= scan_col;
        when 7 => matrix0(63 downto 56) <= scan_col;
        when 8 => matrix0(71 downto 64) <= scan_col;
        when 9 =>
          -- De-glitch matrix of read keys, to avoid
          -- race-conditions from entering keys into the
          -- distributed RAM and reading them out again
          matrix1 <= matrix0;
          if matrix1 = matrix0 then
            matrix <= matrix0;
          end if;
        when others => null;
      end case;

      portb_value := x"FF";
      for i in 0 to 7 loop
        if porta_in(i)='0' then
          for j in 0 to 7 loop
            portb_value(j) := portb_value(j) and (matrix((i*8)+j) or matrix_mode_in);
          end loop;  -- j
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
--          report "porta_value = "
--            & to_string(porta_value) & " as not being keyboard scanned.";
        end if;        
      end loop;    
      
      if scan_idx < 9 then
        -- each bit N of port b is the logical and of all bits across row N in columns where porta_in(N) is 0.
        -- each bit N of port a is the logical and of all bits across col N in rows where portb_in(N) is 0.
        scan_idx <= scan_idx + 1;
      else
        scan_idx <= 0;
      end if;
            
      -- Update physical pins to reflect what the CIA is asking for
      for b in 0 to 7 loop
        if porta_ddr(b)='1' then
          -- Pin is output
--          report "porta copying porta_in(" & integer'image(b) & ") due to ddr=1. Copied value = " & std_logic'image(porta_in(b));
          porta_pins(b) <= porta_in(b);
        else
          -- Pin is input, i.e., tri-stated
--          report "porta tristating porta_in(" & integer'image(b) & ") due to ddr=0.";
          porta_pins(b) <= '1'; -- was 'Z'
        end if;
--        report "porta_pins = " & to_string(porta_pins);
        if portb_ddr(b)='1' then
          -- Pin is output
          portb_pins(b) <= portb_in(b);
        else
          -- Pin is input, i.e., tri-stated
          portb_pins(b) <= 'H';
        end if;
      end loop;

      -- Reading the CIAs requires us to take into account our modeled port
      -- values for the keyboard matrix, combined with the actual values coming
      -- in on the pins.  If DDR='1', then we don't want to read the pin, but if
      -- DDR='0', and if the pin is '0', then it should pull low.
      -- If we are displaying matrix mode, then we freeze the CIA port values,
      -- so that a running program can't probe the keyboard lines.
      if matrix_mode_in='0' then
        for b in 0 to 7 loop
          if (porta_ddr(b) = '0') and (porta_pins(b) = '0') then
            -- CIA should read bit as low
            porta_out(b) <= '0';
--            report "porta_out(" & integer'image(b) & ") = 0, due to ddr=0 and drive=0";
          else
            porta_out(b) <= porta_value(b) and joyb(b);
--            report "porta_out(" & integer'image(b) & ") = " &
--              std_logic'image(porta_value(b)) & " & "
--              & std_logic'image(joyb(b))
--              & ", due to ddr=0 and drive=0";
          end if;
          if (portb_ddr(b) = '0') and (portb_pins(b) = '0') then
            -- CIA should read bit as low
            portb_out(b) <= '0';
          else
            portb_out(b) <= portb_value(b) and joya(b);
          end if;
        end loop;
      end if;
    end if;

  end process keyread;

end behavioural;
