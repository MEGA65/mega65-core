use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity keyboard_to_matrix is
  generic (scan_frequency : integer := 100000;
           clock_frequency : integer);
  port (Clk : in std_logic;        
        porta_pins : inout  std_logic_vector(7 downto 0) := (others => 'Z');
        portb_pins : inout  std_logic_vector(7 downto 0) := (others => 'Z');
        keyboard_column8_out : out std_logic := '1';
        key_left : in std_logic;
        key_up : in std_logic;

        -- Virtualised keyboard matrix
        matrix : out std_logic_vector(71 downto 0) := (others => '1');
        joya : out std_logic_vector(7 downto 0);
        joyb : out std_logic_vector(7 downto 0)
        );

end keyboard_to_matrix;

architecture behavioral of keyboard_to_matrix is
  -- Scan a row 100K/sec, so that the scanning is slow enough
  -- for the keyboard and joystick electronics
  constant count_down : integer := clock_frequency/scan_frequency;
  signal counter : integer := count_down;

  signal scan_phase : integer range 0 to 10 := 10; -- reset entry phase

  -- Scanned state of the keyboard and joysticks
  signal joya_internal : std_logic_vector(7 downto 0) := (others => '1');
  signal joyb_internal : std_logic_vector(7 downto 0) := (others => '1');
  signal matrix_internal : std_logic_vector(71 downto 0) := (others => '1');

begin
  process (clk)

  begin
    if rising_edge(clk) then

      -- Present virtualised keyboard
      matrix <= matrix_internal;     
      if key_left = '0' then
        matrix(2) <= '0'; -- cursor right
        matrix(52) <= '0'; -- right shift
      end if;
      if key_up='0' then
        matrix(7) <= '0'; -- cursor down
        matrix(52) <= '0'; -- right shift
      end if;
      joya <= joya_internal;
      joyb <= joyb_internal;
      
      -- Scan physical keyboard
--      report "scan_phase = " & integer'image(scan_phase)
--        & ", portb_pins = " & to_string(portb_pins)
--        & ", porta_pins = " & to_string(porta_pins);
      if counter=0 then
        counter <= count_down;
        -- Read the appropriate matrix row or joysticks state
--        report "matrix = " & to_string(matrix);
        if scan_phase < 9 then
          scan_phase <= scan_phase + 1;
        else
          scan_phase <= 0;
        end if;
        case scan_phase is
          when 0 =>
            -- Read Joysticks, prepare to read column 0
            joya <= porta_pins; joyb <= portb_pins;
            porta_pins <= ( 0 => '0', others => 'Z');
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 1 =>
            -- Read column 0, prepare column 1
            if (to_UX01(joya_internal(4 downto 0)) = "11111")
              and (to_UX01(joyb_internal(4 downto 0)) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix_internal(7 downto 0) <= portb_pins(7 downto 0);
            end if;
            porta_pins <= ( 1 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 2 =>
            -- Read column 1, prepare column 2
            if (to_UX01(joya_internal(4 downto 0)) = "11111")
              and (to_UX01(joyb_internal(4 downto 0)) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix_internal(15 downto 8) <= portb_pins(7 downto 0);
            end if;
            porta_pins <= ( 2 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 3 =>
            -- Read column 2, prepare column 3
            if (to_UX01(joya_internal(4 downto 0)) = "11111")
              and (to_UX01(joyb_internal(4 downto 0)) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix_internal(23 downto 16) <= portb_pins(7 downto 0);
            end if;
            porta_pins <= ( 3 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 4 =>
            -- Read column 3, prepare column 4
            if (to_UX01(joya_internal(4 downto 0)) = "11111")
              and (to_UX01(joyb_internal(4 downto 0)) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix_internal(31 downto 24) <= portb_pins(7 downto 0);
            end if;
            porta_pins <= ( 4 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 5 =>
            -- Read column 4, prepare column 5
            if (to_UX01(joya_internal(4 downto 0)) = "11111")
              and (to_UX01(joyb_internal(4 downto 0)) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix_internal(39 downto 32) <= portb_pins(7 downto 0);
            end if;
            porta_pins <= ( 5 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 6 =>
            -- Read column 5, prepare column 6
            if (to_UX01(joya_internal(4 downto 0)) = "11111")
              and (to_UX01(joyb_internal(4 downto 0)) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix_internal(47 downto 40) <= portb_pins(7 downto 0);
            end if;
            porta_pins <= ( 6 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 7 =>
            -- Read column 6, prepare column 7
            if (to_UX01(joya_internal(4 downto 0)) = "11111")
              and (to_UX01(joyb_internal(4 downto 0)) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix_internal(55 downto 48) <= portb_pins(7 downto 0);
            end if;
            porta_pins <= ( 7 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 8 =>
            -- Read column 7, prepare column 8
            if (to_UX01(joya_internal(4 downto 0)) = "11111")
              and (to_UX01(joyb_internal(4 downto 0)) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix_internal(63 downto 56) <= portb_pins(7 downto 0);
            end if;
            porta_pins <= (others => 'Z');
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '0';
          when 9 =>
            -- Read column 8, prepare joysticks
            if (to_UX01(joya_internal(4 downto 0)) = "11111")
              and (to_UX01(joyb_internal(4 downto 0)) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix_internal(71 downto 64) <= portb_pins(7 downto 0);
            end if;
            porta_pins <= (others => 'Z');
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 10 =>
            -- Get ready for scanning joysticks first on boot
            porta_pins <= (others => 'Z');
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
        end case;
      else
        counter <= counter - 1;
      end if;
    end if;
  end process;
end behavioral;


    
