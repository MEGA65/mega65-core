library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity keyboard_complex is
  port (
    ioclock : in std_logic;
    reset_in : in std_logic;
    matrix_mode_in : in std_logic;
    
    -- Physical interface pins

    -- Keyboard
    porta_pins : inout  std_logic_vector(7 downto 0) := (others => 'Z');
    portb_pins : inout  std_logic_vector(7 downto 0) := (others => 'Z');
    scan_mode : in std_logic_vector(1 downto 0);
    scan_rate : in unsigned(7 downto 0);
    keyboard_restore : in std_logic := '1';
    keyboard_column8_out : out std_logic := '1';
    key_left : in std_logic;
    key_up : in std_logic;
    keyboard_capslock : in std_logic;
    
    -- Joysticks
    joya : in std_logic_vector(4 downto 0);
    joyb : in std_logic_vector(4 downto 0);
    -- Widget board
    pmod_clock : in std_logic;
    pmod_start_of_sequence : in std_logic;
    pmod_data_in : in std_logic_vector(3 downto 0);
    pmod_data_out : out std_logic_vector(1 downto 0) := "ZZ";
    -- PS/2 keyboard
    ps2clock  : in  std_logic;
    ps2data   : in  std_logic;    
    -- ethernet keyboard input interface for remote head mode
    eth_keycode_toggle : in std_logic;
    eth_keycode : in unsigned(15 downto 0);

    -- Synthetic keys for the virtual keyboard
    key1 : in unsigned(7 downto 0);
    key2 : in unsigned(7 downto 0);
    key3 : in unsigned(7 downto 0);

    -- Summary of currently pressed keys for the on-screen keyboard
    keydown1 : out unsigned(7 downto 0);
    keydown2 : out unsigned(7 downto 0);
    keydown3 : out unsigned(7 downto 0);
    
    -- Flags to control which inputs are disabled, if any
    virtual_disable : in std_logic;
    physkey_disable : in std_logic;
    joy_disable : in std_logic;
    widget_disable : in std_logic;
    ps2_disable : in std_logic;

    -- RESTORE when held or double-tapped does special things
    capslock_out : out std_logic := '1';
    restore_out : out std_logic := '1';
    reset_out : out std_logic := '1';
    hyper_trap_out : out std_logic := '1';

    ascii_key : out unsigned(7 downto 0) := x"00";
    ascii_key_valid : out std_logic := '0';
    bucky_key : out std_logic_vector(6 downto 0) := "0000000"; 
      
    -- USE ASC/DIN / CAPS LOCK key to control CPU speed instead of CAPS LOCK function
    speed_gate : out std_logic := '1';
    speed_gate_enable : in std_logic := '1';
    
    -- Registers for debugging
    key_debug_out : out std_logic_vector(7 downto 0);
    hyper_trap_count : out unsigned(7 downto 0) := x"00";
    restore_up_count : out unsigned(7 downto 0) := x"00";
    restore_down_count : out unsigned(7 downto 0) := x"00";
    last_scan_code : out std_logic_vector(12 downto 0);

    matrix_segment_num : in std_logic_vector(7 downto 0);
    matrix_segment_out : out std_logic_vector(7 downto 0);

    -- cia1 ports
    keyboard_column8_select_in : in std_logic;
    porta_in  : in  std_logic_vector(7 downto 0);
    portb_in  : in  std_logic_vector(7 downto 0);
    porta_out : out std_logic_vector(7 downto 0);
    portb_out : out std_logic_vector(7 downto 0);
    porta_ddr : in  std_logic_vector(7 downto 0);
    portb_ddr : in  std_logic_vector(7 downto 0);

    pota_x : out unsigned(7 downto 0) := x"ff";
    pota_y : out unsigned(7 downto 0) := x"ff";
    potb_x : out unsigned(7 downto 0) := x"ff";    
    potb_y : out unsigned(7 downto 0) := x"ff"
    
    );

end entity keyboard_complex;

architecture behavioural of keyboard_complex is
  signal matrix_combined : std_logic_vector(71 downto 0) := (others => '1');

  signal virtual_matrix : std_logic_vector(71 downto 0);

  signal keyboard_matrix : std_logic_vector(71 downto 0);
  signal keyboard_joya : std_logic_vector(4 downto 0) := (others => '1');
  signal keyboard_joyb : std_logic_vector(4 downto 0) := (others => '1');
  
  signal widget_matrix : std_logic_vector(71 downto 0);
  signal widget_restore : std_logic;
  signal widget_capslock : std_logic;
  signal widget_joya : std_logic_vector(4 downto 0);
  signal widget_joyb : std_logic_vector(4 downto 0);

  signal ps2_matrix : std_logic_vector(71 downto 0);
  signal ps2_restore : std_logic;
  signal ps2_capslock : std_logic;
  signal ps2_joya : std_logic_vector(4 downto 0);
  signal ps2_joyb : std_logic_vector(4 downto 0);

  signal kd1 : unsigned(7 downto 0);
  signal kd2 : unsigned(7 downto 0);
  signal kd3 : unsigned(7 downto 0);
  signal kd_count : integer := 0;
  signal kd_phase : integer := 0;
    
begin

  v2m: entity work.virtual_to_matrix
    port map (
      clk => ioclock,
      key1 => key1,
      key2 => key2,
      key3 => key3,
      
      matrix => virtual_matrix
    );
  
  phykbd0: entity work.keyboard_to_matrix
    port map (
      clk => ioclock,
      porta_pins => porta_pins,
      portb_pins => portb_pins,
      keyboard_column8_out => keyboard_column8_out,
      key_left => key_left,
      key_up => key_up,

      scan_mode => scan_mode,
      scan_rate => scan_rate,

      matrix => keyboard_matrix
    );

  widget0: entity work.widget_to_matrix port map(
    ioclock => ioclock,
    reset_in => reset_in,

    pmod_clock => pmod_clock,
    pmod_start_of_sequence => pmod_start_of_sequence,
    pmod_data_in => pmod_data_in,
    pmod_data_out => pmod_data_out,

    matrix => widget_matrix,
    restore => widget_restore,
    capslock_out => widget_capslock,
    joya => widget_joya,
    joyb => widget_joyb
    );
  
  ps2: entity work.ps2_to_matrix port map(
    ioclock => ioclock,
    reset_in => reset_in,

    -- PS/2 keyboard also provides emulated joysticks and RESTORE key
    restore_out => ps2_restore,
    capslock_out => ps2_capslock,
    matrix => ps2_matrix,
    joya => ps2_joya,
    joyb => ps2_joyb,

    -- And also the last PS/2 key scan code in case someone wants it
    last_scan_code => last_scan_code,
    
    -- PS2 keyboard interface
    ps2clock => ps2clock,
    ps2data => ps2data,
    
    -- ethernet keyboard input interface for remote head mode
    eth_keycode_toggle => eth_keycode_toggle,
    eth_keycode => eth_keycode
    );

  keymapper0:   entity work.keymapper port map(
    ioclock => ioclock,
    reset_in => reset_in,
    matrix_mode_in => matrix_mode_in,

    -- Which inputs shall we incorporate

    virtual_disable => virtual_disable,
    physkey_disable => physkey_disable,
    matrix_physkey => keyboard_matrix,
    capslock_physkey => keyboard_capslock,
    restore_physkey => keyboard_restore,

    joy_disable => joy_disable,
    joya_physkey => keyboard_joya,
    joyb_physkey => keyboard_joyb,

    widget_disable => widget_disable,
    matrix_widget => widget_matrix,
    joya_widget => widget_joya,
    joyb_widget => widget_joyb,
    capslock_widget => widget_capslock,
    restore_widget => widget_restore,

    ps2_disable => ps2_disable,
    matrix_ps2 => ps2_matrix,
    joya_ps2 => ps2_joya,
    joyb_ps2 => ps2_joyb,
    capslock_ps2 => ps2_capslock,
    restore_ps2 => ps2_restore,

    matrix_virtual => virtual_matrix,
    
    matrix_combined => matrix_combined,
    
    -- RESTORE when held or double-tapped does special things
    restore_out => restore_out,
    reset_out => reset_out,
    hyper_trap_out => hyper_trap_out,
    
    -- USE ASC/DIN / CAPS LOCK key to control CPU speed instead of CAPS LOCK function
    speed_gate => speed_gate,
    speed_gate_enable => speed_gate_enable,
    
    -- appears as bit0 of $D607 (see C65 keyboard scan routine at $E406)
    capslock_out => capslock_out,

    -- Registers for debugging
    key_debug_out => key_debug_out,
    hyper_trap_count => hyper_trap_count,
    restore_up_count => restore_up_count,
    restore_down_count => restore_down_count,
    
    -- CIA1 ports
    porta_in  => porta_in ,
    portb_in  => portb_in ,
    porta_out => porta_out,
    portb_out => portb_out,
    porta_ddr => porta_ddr,
    portb_ddr => portb_ddr,

    pota_x => pota_x,
    pota_y => pota_y,
    potb_x => potb_x,
    potb_y => potb_y,
    
    -- read from bit1 of $D607 (see C65 keyboard scan routine at $E406)?
    keyboard_column8_select_in => keyboard_column8_select_in
    
    );

  ascii0: entity work.matrix_to_ascii
    generic map(
      clock_frequency => 50000000
      )
    port map(
    Clk => ioclock,
    matrix => matrix_combined,

    -- UART key stream
    ascii_key => ascii_key,
    bucky_key => bucky_key,
    ascii_key_valid => ascii_key_valid
    );

  process (ioclock)
    variable num : integer;
  begin
    if rising_edge(ioclock) then
      num := to_integer(unsigned(matrix_segment_num));
      if num < 10 then
        matrix_segment_out <= matrix_combined((num*8+7) downto (num*8));
      else
        matrix_segment_out <= (others => '1');
      end if;

      -- Work out the summary of keys down for showing on the On-screen keyboard
      -- (so that the OSK shws all currently down keys)
      -- XXX Dedicated keys won't show (RESTORE and CAPS LOCK)
      -- XXX Left and Up will show as RIGHT SHIFT + RIGHT/DOWN
      if kd_phase /= 72 then
        kd_phase <= kd_phase + 1;
        if (matrix_combined(kd_phase) = '0') then
          if kd_count = 0 then
            kd1 <= to_unsigned(kd_phase,8);
          elsif kd_count = 1 then
            kd2 <= to_unsigned(kd_phase,8);
          elsif kd_count = 2 then
            kd3 <= to_unsigned(kd_phase,8);
          end if;
          kd_count <= kd_count + 1;
        end if;
      else
        kd_phase <= 0;
        keydown1 <= kd1;
        keydown2 <= kd2;
        keydown3 <= kd3;
        -- $7D = no key ($7E and $7F have special meanings)
        kd1 <= x"7D";
        kd2 <= x"7D";
        kd3 <= x"7D";
        kd_count <= 0;
      end if;
      
    end if;
  end process;
  
end behavioural;
