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

        drive_one : in std_logic;
        passive_high : in std_logic;
        
        -- Virtualised keyboard matrix
        matrix : out std_logic_vector(71 downto 0) := (others => '1')
        );

end keyboard_to_matrix;

architecture behavioral of keyboard_to_matrix is
  -- Scan a row 100K/sec, so that the scanning is slow enough
  -- for the keyboard 
  constant count_down : integer := clock_frequency/scan_frequency;
  signal counter : integer := count_down;

  signal scan_phase : integer range 0 to 8 := 0; -- reset entry phase

  -- Scanned state of the keyboard
  signal matrix_internal : std_logic_vector(71 downto 0) := (others => '1');

begin
  process (clk)
    variable next_phase : integer range 0 to 8;
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
      
      -- Scan physical keyboard
--      report "scan_phase = " & integer'image(scan_phase)
--        & ", portb_pins = " & to_string(portb_pins)
--        & ", porta_pins = " & to_string(porta_pins);
      if counter=0 then
        counter <= count_down;
        -- Read the appropriate matrix row or joysticks state
--        report "matrix = " & to_string(matrix);
        if scan_phase < 8 then
          scan_phase <= scan_phase + 1;
        else
          scan_phase <= 0;
        end if;

        -- Scan the keyboard
        portb_pins <= (others => passive_high);
        matrix_internal((scan_phase*8)+ 7 downto (scan_phase*8)) <= portb_pins(7 downto 0);

        -- Select lines for next column
        if scan_phase < 8 then
          next_phase := scan_phase + 1;
        else
          next_phase := 0;
        end if;
        for i in 0 to 7 loop
          if next_phase = i then
            porta_pins(i) <= '0';
          else
            porta_pins(i) <= drive_one;
          end if;
        end loop;
        if next_phase = 8 then
          porta_pins <= (others => drive_one);
          keyboard_column8_out <= '0';
        else
          keyboard_column8_out <= '1';
        end if;
      else
        -- Keep counting down to next scan event
        counter <= counter - 1;
      end if;
    end if;
  end process;
end behavioral;


    
