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
  signal key_left : std_logic;
  signal key_up : std_logic;

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
  signal ascii_key_valid : std_logic := '0';

  signal pixelclock : std_logic := '0';
  signal cpuclock : std_logic := '0';
  signal ioclock : std_logic := '0';

  signal keyboard_matrix : std_logic_vector(71 downto 0) := (others => '1');
  
begin
  kv: entity work.keyboard_to_matrix
    generic map (
      clock_frequency => 50000000,
      scan_frequency => 25000000)
    port map (
      clk => cpuclock,
      porta_pins => porta_pins,
      portb_pins => portb_pins,
      keyboard_column8_out => keyboard_column8_out,
      key_left => key_left,
      key_up => key_up,

      matrix => keyboard_matrix
      );

  m2a: entity work.matrix_to_ascii
    port map(
      clk => cpuclock,
      matrix => keyboard_matrix,
      
      ascii_key => ascii_key,
      bucky_key => bucky_key,
      ascii_key_valid => ascii_key_valid
      );

  process
  begin
    for i in 1 to 2000000 loop
      pixelclock <= '0'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '0'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '0'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;     
      pixelclock <= '0'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;
    end loop;  -- i
    assert false report "End of simulation" severity note;
  end process;

  -- Pull up resisters
  porta_pins <= (others => 'H');
  portb_pins <= (others => 'H');
  
  -- Monitor keyboard activity
  process (cpuclock)
  begin
    if rising_edge(cpuclock) then
      if ascii_key_valid='1' then
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
    procedure type_text(cycles_per_char : integer;
                        text : string) is
      variable offset : integer;
      variable shifted : boolean;
      variable a_pin : integer;
      variable b_pin : integer;
    begin
      for i in text'range loop
        offset := char2matrix(text(i));
        shifted := charisshifted(text(i));
        a_pin := offset / 8;
        b_pin := offset rem 8;
        for j in 1 to cycles_per_char loop
--          report "porta_pins = " & to_string(porta_pins)
--            & ", portb_pins = " & to_string(portb_pins);
          if porta_pins(a_pin)='0' then
            portb_pins(b_pin) <= '0';
            if (a_pin = 1) and (b_pin /= 7) then
              if shifted then
                portb_pins(7) <= '0';
              else
                portb_pins(7) <= 'Z';
              end if;
            end if;
            if (a_pin /= 1) and (b_pin /= 7) then
              portb_pins(7) <= 'Z';
            end if;
          else
            if shifted then
              if porta_pins(1)='0' then
                portb_pins(7) <= '0';
              else
                portb_pins <= (others => 'Z');
              end if;
            else
              portb_pins <= (others => 'Z');
            end if;
          end if;
          wait for 5 ns;
        end loop;
        portb_pins <= (others => 'Z');
      end loop;
    end procedure;
  begin
    type_text(1000,"The big fish");
    wait for 1000 ms;
  end process;  
  
end behavioral;
