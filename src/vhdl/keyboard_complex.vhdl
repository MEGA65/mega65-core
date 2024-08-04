library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity keyboard_complex is
  port (
    cpuclock : in std_logic;
    reset_in : in std_logic;
    matrix_mode_in : in std_logic;
    matrix_disable_modifiers : in std_logic;

    viciv_frame_indicate : in std_logic;

    eth_hyperrupt : out std_logic := '0';

    -- Physical interface pins

    -- Keyboard
    porta_pins : inout  std_logic_vector(7 downto 0) := (others => 'Z');
    portb_pins : inout  std_logic_vector(7 downto 0);
    scan_mode : in std_logic_vector(1 downto 0);
    scan_rate : in unsigned(7 downto 0);
    keyboard_restore : in std_logic := '1';
    keyboard_column8_out : out std_logic := '1';
    key_left : in std_logic;
    key_up : in std_logic;
    keyboard_capslock : in std_logic;

    joya_rotate : in std_logic;
    joyb_rotate : in std_logic;

    joyswap : in std_logic;

    -- Joysticks
    joya : in std_logic_vector(4 downto 0);
    joyb : in std_logic_vector(4 downto 0);

    -- Widget board / MEGA65R2 keyboard
    widget_matrix_col_idx : out integer range 0 to 15 := 0;
    widget_matrix_col : in std_logic_vector(7 downto 0);
    widget_restore : in std_logic;
    widget_capslock : in std_logic;
    widget_joya : in std_logic_vector(4 downto 0);
    widget_joyb : in std_logic_vector(4 downto 0);

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
    -- And keys pressed on on screen keyboard
    touch_key1 : in unsigned(7 downto 0);
    touch_key2 : in unsigned(7 downto 0);

    -- Summary of currently pressed keys for the on-screen keyboard
    keydown1 : out unsigned(7 downto 0);
    keydown2 : out unsigned(7 downto 0);
    keydown3 : out unsigned(7 downto 0);
    keydown4 : out unsigned(7 downto 0);

    -- Flags to control which inputs are disabled, if any
    virtual_disable : in std_logic;
    physkey_disable : in std_logic;
    joykey_disable : in std_logic;
    joyreal_disable : in std_logic;
    widget_disable : in std_logic;
    ps2_disable : in std_logic;

    -- RESTORE when held or double-tapped does special things
    capslock_out : out std_logic := '1';
    restore_out : out std_logic := '1';
    reset_out : out std_logic := '1';
    hyper_trap_out : out std_logic := '1';

    key_valid : out std_logic := '0';
    ascii_key : out unsigned(7 downto 0) := x"00";
    petscii_key : out unsigned(7 downto 0) := x"00";
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
    suppress_key_glitches : in std_logic;
    suppress_key_retrigger : in std_logic;

    -- cia1 ports
    keyboard_column8_select_in : in std_logic;
    porta_in  : in  std_logic_vector(7 downto 0);
    portb_in  : in  std_logic_vector(7 downto 0);
    porta_out : out std_logic_vector(7 downto 0);
    portb_out : out std_logic_vector(7 downto 0);
    porta_ddr : in  std_logic_vector(7 downto 0);
    portb_ddr : in  std_logic_vector(7 downto 0)
    );

end entity keyboard_complex;

architecture behavioural of keyboard_complex is

  signal virtual_matrix_col : std_logic_vector(7 downto 0);

  signal keyboard_matrix_col : std_logic_vector(7 downto 0);
  signal keyboard_joya : std_logic_vector(4 downto 0) := (others => '1');
  signal keyboard_joyb : std_logic_vector(4 downto 0) := (others => '1');

  signal ps2_matrix_col : std_logic_vector(7 downto 0);
  signal ps2_restore : std_logic;
  signal ps2_capslock : std_logic;
  signal ps2_joya : std_logic_vector(4 downto 0);
  signal ps2_joyb : std_logic_vector(4 downto 0);

  signal kd1 : unsigned(7 downto 0);
  signal kd2 : unsigned(7 downto 0);
  signal kd3 : unsigned(7 downto 0);
  signal kd4 : unsigned(7 downto 0);
  signal kd_count : integer := 0;
  signal kd_phase : integer := 0;

  signal restore_combined : std_logic := '1';
  signal capslock_combined : std_logic := '1';

  signal matrix_col_idx : integer range 0 to 15;

  signal matrix_combined_col : std_logic_vector(7 downto 0);
  signal matrix_combined_col_idx : integer range 0 to 15;
  signal kmm_out : std_logic_vector(7 downto 0);
  signal kmm_index : integer range 0 to 15;
  signal summary_index : integer range 0 to 15;
  signal summary_out : std_logic_vector(7 downto 0);
  signal shift_key_state : std_logic;
  signal kd_state : std_logic;
  signal virtual_restore : std_logic;

begin

  v2m: entity work.virtual_to_matrix
    port map (
      clk => cpuclock,
      key1 => key1,
      key2 => key2,
      key3 => key3,
      touch_key1 => touch_key1,
      touch_key2 => touch_key2,
      restore_out => virtual_restore,

      matrix_col => virtual_matrix_col,
      matrix_col_idx => matrix_col_idx
      );

  phykbd0: entity work.keyboard_to_matrix
    port map (
      clk => cpuclock,
      porta_pins => porta_pins,
      portb_pins => portb_pins,
      keyboard_column8_out => keyboard_column8_out,
      key_left => key_left,
      key_up => key_up,

      scan_mode => scan_mode,
      scan_rate => scan_rate,

      matrix_col => keyboard_matrix_col,
      matrix_col_idx => matrix_col_idx
      );

  ps2: entity work.ps2_to_matrix port map(
    cpuclock => cpuclock,
    reset_in => reset_in,

    -- PS/2 keyboard also provides emulated joysticks and RESTORE key
    restore_out => ps2_restore,
    capslock_out => ps2_capslock,

    matrix_col => ps2_matrix_col,
    matrix_col_idx => matrix_col_idx,

    joya => ps2_joya,
    joyb => ps2_joyb,

    -- And also the last PS/2 key scan code in case someone wants it
    last_scan_code => last_scan_code,

    -- PS2 keyboard interface
    ps2clock => ps2clock,
    ps2data => ps2data,

    -- ethernet keyboard input interface for remote head mode
    eth_keycode_toggle => eth_keycode_toggle,
    eth_keycode => eth_keycode,
    -- And also ethernet triggered hypervisor trap for remote control
    eth_hyperrupt_out => eth_hyperrupt
    );

  keymapper0:   entity work.keymapper port map(
    cpuclock => cpuclock,
    reset_in => reset_in,
    matrix_mode_in => matrix_mode_in,
    viciv_frame_indicate => viciv_frame_indicate,

    -- Which inputs shall we incorporate

    joyswap => joyswap,

    joya_rotate => joya_rotate,
    joyb_rotate => joyb_rotate,

    virtual_disable => virtual_disable,
    physkey_disable => physkey_disable,
    matrix_col_physkey => keyboard_matrix_col,
    capslock_physkey => keyboard_capslock,
    restore_physkey => keyboard_restore,
    restore_virtual => virtual_restore,

    joykey_disable => joykey_disable,
    joya_physkey => keyboard_joya,
    joyb_physkey => keyboard_joyb,

    joyreal_disable => joyreal_disable,
    joya_real => joya,
    joyb_real => joyb,

    widget_disable => widget_disable,
    matrix_col_widget => widget_matrix_col,
    joya_widget => widget_joya,
    joyb_widget => widget_joyb,
    capslock_widget => widget_capslock,
    restore_widget => widget_restore,

    ps2_disable => ps2_disable,
    matrix_col_ps2 => ps2_matrix_col,
    joya_ps2 => ps2_joya,
    joyb_ps2 => ps2_joyb,
    capslock_ps2 => ps2_capslock,
    restore_ps2 => ps2_restore,

    matrix_col_virtual => virtual_matrix_col,

    matrix_col_idx => matrix_col_idx,
    matrix_combined_col => matrix_combined_col,
    matrix_combined_col_idx => matrix_combined_col_idx,

    -- RESTORE when held or double-tapped does special things
    restore_out => restore_combined,
    reset_out => reset_out,
    hyper_trap_out => hyper_trap_out,

    -- USE ASC/DIN / CAPS LOCK key to control CPU speed instead of CAPS LOCK function
    speed_gate => speed_gate,
    speed_gate_enable => speed_gate_enable,

    -- appears as bit0 of $D607 (see C65 keyboard scan routine at $E406)
    capslock_out => capslock_combined,

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

    -- read from bit1 of $D607 (see C65 keyboard scan routine at $E406)?
    keyboard_column8_select_in => keyboard_column8_select_in

    );

  ascii0: entity work.matrix_to_ascii
    generic map(
      clock_frequency => 50000000
      )
    port map(
      Clk => cpuclock,
      reset_in => reset_in,

      matrix_col => matrix_combined_col,
      matrix_col_idx => matrix_combined_col_idx,
      matrix_mode_in => matrix_mode_in,
      matrix_disable_modifiers => matrix_disable_modifiers,

      key_up => key_up,
      key_left => key_left,
      key_caps => capslock_combined,

      suppress_key_glitches => suppress_key_glitches,
      suppress_key_retrigger => suppress_key_retrigger,

      -- UART key stream
      ascii_key => ascii_key,
      petscii_key => petscii_key,
      bucky_key => bucky_key,
      key_valid => key_valid
      );

  -- copy of combined keyboard matrix for debug output
  kc_kmm_debug: entity work.kb_matrix_ram
  port map (
    clkA => cpuclock,
    addressa => matrix_combined_col_idx,
    dia => matrix_combined_col,
    wea => x"FF",
    addressb => kmm_index,
    dob => kmm_out
    );

  -- another of combined keyboard matrix for summary view
  kc_kmm_summary: entity work.kb_matrix_ram
  port map (
    clkA => cpuclock,
    addressa => matrix_combined_col_idx,
    dia => matrix_combined_col,
    wea => x"FF",
    addressb => summary_index,
    dob => summary_out
    );

  process(kd_phase,summary_out)
    variable kd_phase_vec : std_logic_vector(6 downto 0);
    variable kd_phase_index : integer range 0 to 15;
    variable kd_phase_bit : integer range 0 to 7;
  begin
    kd_phase_vec   := std_logic_vector(to_unsigned(kd_phase,7));
    kd_phase_index := to_integer(unsigned(kd_phase_vec(6 downto 3)));
    kd_phase_bit   := to_integer(unsigned(kd_phase_vec(2 downto 0)));

    kd_state       <= summary_out(kd_phase_bit);
    summary_index  <= kd_phase_index;
  end process;

  process (cpuclock,matrix_col_idx)
    variable num : integer;
  begin

    widget_matrix_col_idx <= matrix_col_idx;

    if rising_edge(cpuclock) then

      capslock_out <= capslock_combined;
      restore_out <= restore_combined;

      num := to_integer(unsigned(matrix_segment_num));
      if num < 10 then
        kmm_index <= num;
        matrix_segment_out <= kmm_out;
      else
        kmm_index <= 0;
        matrix_segment_out <= (others => '1');
      end if;

      if reset_in = '0' then
        -- $7D = no key ($7E and $7F have special meanings)
        kd1 <= x"7D";
        kd2 <= x"7D";
        kd3 <= x"7D";
        kd4 <= x"7D";
        kd_count <= 0;
        kd_phase <= 0;
      else
        -- Work out the summary of keys down for showing on the On-screen keyboard
        -- (so that the OSK shws all currently down keys)
        if kd_phase /= 72 then
          kd_phase <= kd_phase + 1;
          -- remember last known shift key state
          if kd_phase = 52 then
            shift_key_state <= kd_state;
          end if;
          if kd_phase = 2 and shift_key_state='0' then
            -- Left (or shift right)
            if (kd_state = '0') then
              if kd_count = 0 then
                kd1 <= x"53"; -- left key
              elsif kd_count = 1 then
                kd2 <= x"53"; -- left key
              elsif kd_count = 2 then
                kd3 <= x"53"; -- left key
              elsif kd_count = 3 then
                kd4 <= x"53"; -- left key
              end if;
              kd_count <= kd_count + 1;
            end if;
          elsif kd_phase = 7 and shift_key_state='0' then
            -- Up (or shift down)
            if (kd_state = '0') then
              if kd_count = 0 then
                kd1 <= x"52"; -- up key
              elsif kd_count = 1 then
                kd2 <= x"52"; -- up key
              elsif kd_count = 2 then
                kd3 <= x"52"; -- up key
              elsif kd_count = 3 then
                kd4 <= x"52"; -- up key
              end if;
              kd_count <= kd_count + 1;
            end if;
          elsif (kd_state = '0') then
            if kd_count = 0 then
              kd1 <= to_unsigned(kd_phase,8);
            elsif kd_count = 1 then
              kd2 <= to_unsigned(kd_phase,8);
            elsif kd_count = 2 then
              kd3 <= to_unsigned(kd_phase,8);
            elsif kd_count = 3 then
              kd4 <= to_unsigned(kd_phase,8);
            end if;
            kd_count <= kd_count + 1;
          end if;
        else
          kd_phase <= 0;
          keydown1 <= kd1;
          keydown2 <= kd2;
          keydown3 <= kd3;
          keydown4 <= kd4;
          -- $7D = no key ($7E and $7F have special meanings)
          kd1 <= x"7D";
          kd2 <= x"7D";
          kd3 <= x"7D";
          kd4 <= x"7D";
          kd_count <= 0;

          -- Show RESTORE and CAPSLOCK dedicated keys
          if capslock_combined = '0' then
            kd1 <= x"50";
            if restore_combined = '0' then
              kd2 <= x"51";
              kd_count <= 2;
            else
              kd_count <= 1;
            end if;
          elsif restore_combined = '0' then
            kd1 <= x"51";
            kd_count <= 1;
          end if;

        end if;
      end if;
    end if;
  end process;

end behavioural;
