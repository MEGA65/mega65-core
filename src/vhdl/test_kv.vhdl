use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity test_kv is
end test_kv;

architecture behavioral of test_kv is

  signal porta_pins : std_logic_vector(7 downto 0) := (others => 'Z');
  signal portb_pins : std_logic_vector(7 downto 0) := (others => 'Z');
  signal keyboard_column8_out : std_logic := '1';
  signal key_left : std_logic := '1';
  signal key_up : std_logic := '1';

  -- UART key stream
  signal ascii_key : unsigned(7 downto 0) := (others => '0');
  -- Bucky key list:
  -- 0 = left shift
  -- 1 = right shift
  -- 2 = control
  -- 3 = C=
  -- 4 = ALT
  -- 5 = NO SCROLL
  -- 6 = ASC/DIN/CAPS LOCK (XXX - Has a separate line. Not currently monitored)
  signal bucky_key : std_logic_vector(6 downto 0) := (others  => '0');
  signal key_valid : std_logic := '0';

  signal pixelclock : std_logic := '0';
  signal cpuclock : std_logic := '0';
  signal ioclock : std_logic := '0';

  signal matrix_mode : std_logic := '0';

  signal keyboard_matrix : std_logic_vector(71 downto 0) := (others => '1');

  signal reset_in : std_logic := '1';
    -- Joysticks
  signal joya : std_logic_vector(4 downto 0) := "11111";
  signal joyb : std_logic_vector(4 downto 0) := "11111";
    -- Widget board
  signal pmod_clock : std_logic := '1';
  signal pmod_start_of_sequence : std_logic := '0';
  signal pmod_data_in : std_logic_vector(3 downto 0);
  signal pmod_data_out : std_logic_vector(1 downto 0) := "ZZ";
    -- PS/2 keyboard
  signal ps2clock  :  std_logic := '1';
  signal ps2data   :  std_logic := '1';
    -- ethernet keyboard input interface for remote head mode
  signal eth_keycode_toggle : std_logic := '0';
  signal eth_keycode : unsigned(15 downto 0) := x"1234";

    -- Flags to control which inputs are disabled, if any
  signal physkey_disable : std_logic := '0';
  signal joy_disable : std_logic := '0';
  signal widget_disable : std_logic := '0';
  signal ps2_disable : std_logic := '0';

    -- RESTORE when held or double-tapped does special things
  signal capslock_out : std_logic := '1';
  signal restore_out : std_logic := '1';
  signal reset_out : std_logic := '1';
  signal hyper_trap_out : std_logic := '1';

    -- USE ASC/DIN / CAPS LOCK key to control CPU speed instead of CAPS LOCK function
  signal speed_gate : std_logic := '1';
  signal speed_gate_enable : std_logic := '1';

    -- Registers for debugging
  signal key_debug_out : std_logic_vector(7 downto 0);
  signal hyper_trap_count : unsigned(7 downto 0) := x"00";
  signal restore_up_count : unsigned(7 downto 0) := x"00";
  signal restore_down_count : unsigned(7 downto 0) := x"00";

    -- cia1 ports
  signal keyboard_column8_select_in : std_logic;
  signal porta_in  :  std_logic_vector(7 downto 0);
  signal portb_in  :  std_logic_vector(7 downto 0);
  signal porta_out : std_logic_vector(7 downto 0);
  signal portb_out : std_logic_vector(7 downto 0);
  signal porta_ddr :  std_logic_vector(7 downto 0);
  signal portb_ddr :  std_logic_vector(7 downto 0);

  signal pota_x : unsigned(7 downto 0) := x"ff";
  signal pota_y : unsigned(7 downto 0) := x"ff";
  signal potb_x : unsigned(7 downto 0) := x"ff";
  signal potb_y : unsigned(7 downto 0) := x"ff";

begin
  kc0: entity work.keyboard_complex
    port map(
    ioclock => cpuclock,
    reset_in => reset_in,

    matrix_mode_in => '0',

    scan_mode => "01",
    scan_rate => x"01",

    matrix_segment_num => x"00",

    -- Physical interface pins
    virtual_disable => '0',
    key1 => x"FF",
    key2 => x"FF",
    key3 => x"FF",

    -- Keyboard
    porta_pins => porta_pins,
    portb_pins => portb_pins,
    keyboard_column8_out => keyboard_column8_out,
    keyboard_capslock => '0',
    key_left => key_left,
    key_up => key_up,
    -- Joysticks
    joya => joya,
    joyb => joyb,
    -- Widget board
    pmod_clock => pmod_clock,
    pmod_start_of_sequence => pmod_start_of_sequence,
    pmod_data_in => pmod_data_in,
    pmod_data_out => pmod_data_out,
    -- PS/2 keyboard
    ps2clock  => ps2clock ,
    ps2data   => ps2data  ,
    -- ethernet keyboard input interface for remote head mode
    eth_keycode_toggle => eth_keycode_toggle,
    eth_keycode => eth_keycode,

    -- Flags to control which inputs are disabled, if any
    physkey_disable => physkey_disable,
    joy_disable => joy_disable,
    widget_disable => widget_disable,
    ps2_disable => ps2_disable,

    -- RESTORE when held or double-tapped does special things
    capslock_out => capslock_out,
    restore_out => restore_out,
    reset_out => reset_out,
    hyper_trap_out => hyper_trap_out,

    -- USE ASC/DIN / CAPS LOCK key to control CPU speed instead of CAPS LOCK function
    speed_gate => speed_gate,
    speed_gate_enable => speed_gate_enable,

    -- Registers for debugging
    key_debug_out => key_debug_out,
    hyper_trap_count => hyper_trap_count,
    restore_up_count => restore_up_count,
    restore_down_count => restore_down_count,

    -- cia1 ports
    keyboard_column8_select_in => keyboard_column8_select_in,
    porta_in  => porta_in ,
    portb_in  => portb_in ,
    porta_out => porta_out,
    portb_out => portb_out,
    porta_ddr => porta_ddr,
    portb_ddr => portb_ddr,

    pota_x => pota_x,
    pota_y => pota_y,
    potb_x => potb_x,
    potb_y => potb_y

    );

  process
  begin
    for i in 1 to 2000000 loop
      pixelclock <= '0'; cpuclock <= '0'; ioclock <= '0';
      wait for 10 ns;
      pixelclock <= '0'; cpuclock <= '1'; ioclock <= '1';
      wait for 10 ns;
    end loop;  -- i
    assert false report "End of simulation" severity note;
  end process;

  -- Monitor keyboard activity
  process (cpuclock)
  begin
    if rising_edge(cpuclock) then
      if key_valid='1' then
        report "bucky vector = " & to_string(bucky_key)
          & " ASCII code = 0x" & to_hstring(ascii_key);
      end if;
      null;
    end if;
  end process;

  -- Induce some fake keyboard activity
  process
    function char2matrix(c : character) return integer is
    begin
      case c is
        when cr => return 36;
        when ' ' => return 60;
        when '!' => return 56;
        when '"' => return 59;
        when '#' => return 8;
        when '$' => return 11;
        when '%' => return 16;
        when '&' => return 19;
--        when '\'' => return 24;
        when ')' => return 32;
        when '*' => return 49;
        when '+' => return 40;
        when ',' => return 47;
        when '-' => return 43;
        when '.' => return 44;
        when '/' => return 55;
        when '0' => return 35;
        when '1' => return 56;
        when '2' => return 59;
        when '3' => return 8;
        when '4' => return 11;
        when '5' => return 16;
        when '6' => return 19;
        when '7' => return 24;
        when '8' => return 27;
        when '9' => return 32;
        when ':' => return 45;
        when ';' => return 50;
        when '<' => return 47;
        when '=' => return 53;
        when '>' => return 44;
        when '?' => return 55;
        when '@' => return 46;
        when 'A' => return 10;
        when 'B' => return 28;
        when 'C' => return 20;
        when 'D' => return 18;
        when 'E' => return 14;
        when 'F' => return 21;
        when 'G' => return 26;
        when 'H' => return 29;
        when 'I' => return 33;
        when 'J' => return 34;
        when 'K' => return 37;
        when 'L' => return 42;
        when 'M' => return 36;
        when 'N' => return 39;
        when 'O' => return 38;
        when 'P' => return 41;
        when 'Q' => return 62;
        when 'R' => return 17;
        when 'S' => return 13;
        when 'T' => return 22;
        when 'U' => return 30;
        when 'V' => return 31;
        when 'W' => return 9;
        when 'X' => return 23;
        when 'Y' => return 25;
        when 'Z' => return 12;
        when '[' => return 45;
        when ']' => return 50;
        when '_' => return 57;
        when 'a' => return 10;
        when 'b' => return 28;
        when 'c' => return 20;
        when 'd' => return 18;
        when 'e' => return 14;
        when 'f' => return 21;
        when 'g' => return 26;
        when 'h' => return 29;
        when 'i' => return 33;
        when 'j' => return 34;
        when 'k' => return 37;
        when 'l' => return 42;
        when 'm' => return 36;
        when 'n' => return 39;
        when 'o' => return 38;
        when 'p' => return 41;
        when 'q' => return 62;
        when 'r' => return 17;
        when 's' => return 13;
        when 't' => return 22;
        when 'u' => return 30;
        when 'v' => return 31;
        when 'w' => return 9;
        when 'x' => return 23;
        when 'y' => return 25;
        when 'z' => return 12;
        when '{' => return 35;
        when others => return 71;
      end case;
    end function;
    function charisshifted(c : character) return boolean is
    begin
      if c >= 'A' and c<= 'Z' then
        return true;
      end if;
      return false;
    end function;
    procedure type_char(cycles_per_char : integer;
                        char : character) is
      variable offset : integer;
      variable shifted : boolean;
      variable a_pin : integer;
      variable b_pin : integer;
    begin
        offset := char2matrix(char);
        shifted := charisshifted(char);
        a_pin := offset / 8;
        b_pin := offset rem 8;
        report "Typing  " & character'image(char);
        for j in 1 to cycles_per_char loop
--          report "porta_pins = " & to_string(porta_pins)
--            & ", portb_pins = " & to_string(portb_pins);
          if porta_pins(a_pin)='0' then
            portb_pins(b_pin) <= '0';
            if (a_pin = 1) and (b_pin /= 7) then
              if shifted then
                portb_pins(7) <= '0';
              else
                portb_pins(7) <= '1';
              end if;
            end if;
            if (a_pin /= 1) and (b_pin /= 7) then
              portb_pins(7) <= '1';
            end if;
          else
            if shifted then
              if porta_pins(1)='0' then
                portb_pins(7) <= '0';
              else
                portb_pins <= (others => '1');
              end if;
            else
              portb_pins <= (others => '1');
            end if;
          end if;
          wait for 5 ns;
        end loop;
        portb_pins <= (others => 'Z');
    end procedure;
    procedure type_text(cycles_per_char : integer;
                        text : string) is
    begin
      for i in text'range loop
        type_char(cycles_per_char,text(i));
      end loop;
    end procedure;

  begin
    report "Turning matrix mode off";
    matrix_mode <= '0';
    type_text(1000000,"The big fish");
    type_char(1000000,cr);
    wait for 1000 ms;
    report "Turning matrix mode on";
    matrix_mode <= '1';
    type_text(1000000,"The big fish");
    type_char(1000000,cr);
    wait for 1000 ms;
  end process;

end behavioral;
