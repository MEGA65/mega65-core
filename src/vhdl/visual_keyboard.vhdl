library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity visual_keyboard is
  port (
    pixel_x_640 : in integer;
    ycounter_in : in unsigned(11 downto 0);
    pixelclock : in std_logic;
    visual_keyboard_enable : in std_logic;
    key1 : in unsigned(7 downto 0);
    key2 : in unsigned(7 downto 0);
    key3 : in unsigned(7 downto 0);
    vgared_in : in  unsigned (7 downto 0);
    vgagreen_in : in  unsigned (7 downto 0);
    vgablue_in : in  unsigned (7 downto 0);
    vgared_out : out  unsigned (7 downto 0);
    vgagreen_out : out  unsigned (7 downto 0);
    vgablue_out : out  unsigned (7 downto 0)
    );
end visual_keyboard;

architecture behavioural of visual_keyboard is

  signal y_start : unsigned(11 downto 0) := to_unsigned(100,12);
  signal x_start : integer := 1;
  signal y_stretch : integer range 0 to 2 := 1;

  constant chars_per_row : integer := 3;

  signal y_pixel_counter : integer range 0 to 7 := 0;
  signal y_char_in_row : integer range 0 to chars_per_row := 0;
  signal y_phase : integer range 0 to 2 := 0;
  signal y_row : integer range 0 to 6 := 0;
  
  signal vk_pixel : unsigned(1 downto 0) := "00";

  signal address : integer range 0 to 4095 := 0;
  signal rdata : unsigned(7 downto 0);

  signal current_address : integer range 0 to 4095 := 0;
  signal last_row_address : integer range 0 to 4095 := 0;

  signal current_matrix_id : unsigned(7 downto 0);
  signal next_matrix_id : unsigned(7 downto 0);
  signal matrix_pos : integer;

  signal last_was_640 : std_logic := '0';
  signal active : std_logic := '0';
  
  type fetch_state_t is (
    FetchIdle,
    FetchMapRowColumn0,
    FetchMapRowColumn1,
    GotMapRowColumn1,
    FetchNextMatrix,
    GotNextMatrix
    );
  signal fetch_state : fetch_state_t := FetchIdle;
  
begin

  km0: entity work.oskmem
    port map (
      clk => pixelclock,
      address => address,
      we => '0',
      data_i => (others => '1'),
      data_o => rdata
      );
  
  process (pixelclock)
  begin
    if rising_edge(pixelclock) then

      if pixel_x_640 = 640 then
        last_was_640 <= '1';

        if last_was_640 = '0' then
          -- End of line, prepare for next
          fetch_state <= FetchMapRowColumn0;
          if ycounter_in = 0 then
            active <= '0';
          elsif ycounter_in = y_start then
            active <= '1';

            current_address <= 0;
            last_row_address <= 0;

            y_row <= 0;
            y_char_in_row <= 0;
            y_pixel_counter <= 0;
            y_phase <= 0;
          end if;
        end if;
      else
        last_was_640 <= '0';
      end if;

      if active='1' then
        case fetch_state is
          when FetchMapRowColumn0 =>
            address <= 128 + y_row*16;
            fetch_state <= FetchMapRowColumn1;
          when FetchMapRowColumn1 =>
            current_matrix_id <= rdata;
            address <= 128 + y_row*16 + 1;
            fetch_state <= GotMapRowColumn1;
          when GotMapRowColumn1 =>
            next_matrix_id <= rdata;
            matrix_pos <= 0;
            fetch_state <= FetchIdle;
          when FetchNextMatrix =>
            address <= 128 + y_row*16 + matrix_pos + 2;
            fetch_state <= GotNextMatrix;
          when GotNextMatrix =>
            current_matrix_id <= next_matrix_id;
            next_matrix_id <= rdata;
            fetch_state <= FetchIdle;
          when others =>
            null;
        end case;
      end if;
      
      if visual_keyboard_enable='1' then
        vgared_out <= vk_pixel&vgared_in(7 downto 2);
        vgagreen_out <= vk_pixel&vgagreen_in(7 downto 2);
        vgablue_out <= vk_pixel&vgablue_in(7 downto 2);
      else
        vgared_out <= vgared_in;
        vgagreen_out <= vgagreen_in;
        vgablue_out <= vgablue_in;
      end if;
    end if;
  end process;
  
end behavioural;
