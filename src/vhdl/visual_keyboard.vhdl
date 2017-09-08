library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity visual_keyboard is
  port (
    pixel_x_640_in : in integer;
    pixel_y_scale_200 : in unsigned(3 downto 0);
    pixel_y_scale_400 : in unsigned(3 downto 0);
    ycounter_in : in unsigned(11 downto 0);
    y_start : in unsigned(11 downto 0);
    x_start : in unsigned(11 downto 0);
    pixelclock : in std_logic;
    visual_keyboard_enable : in std_logic;
    keyboard_at_top : in std_logic;
    alternate_keyboard : in std_logic;
    instant_at_top : in std_logic;
    key1 : in unsigned(7 downto 0);
    key2 : in unsigned(7 downto 0);
    key3 : in unsigned(7 downto 0);    
    key4 : in unsigned(7 downto 0);

    -- Touch interface
    touch1_valid : in std_logic;
    touch1_x : in unsigned(13 downto 0);
    touch1_y : in unsigned(11 downto 0);
    touch1_key : out unsigned(7 downto 0) := x"FF";
    touch2_valid : in std_logic;
    touch2_x : in unsigned(13 downto 0);
    touch2_y : in unsigned(11 downto 0);
    touch2_key : out unsigned(7 downto 0) := x"FF";
    
    vgared_in : in  unsigned (7 downto 0);
    vgagreen_in : in  unsigned (7 downto 0);
    vgablue_in : in  unsigned (7 downto 0);
    vgared_out : out  unsigned (7 downto 0);
    vgagreen_out : out  unsigned (7 downto 0);
    vgablue_out : out  unsigned (7 downto 0)
    );
end visual_keyboard;

architecture behavioural of visual_keyboard is

  signal y_start_current : unsigned(11 downto 0) :=
    to_unsigned(0,12);
  signal x_start_current : unsigned(13 downto 0) :=
    to_unsigned(0,14);
  signal x_surplus : unsigned(13 downto 0) :=
    to_unsigned(0,14);
  signal max_x : integer := 0;
  
  signal y_stretch : integer range 0 to 15 := 1;

  constant chars_per_row : integer := 3;

  signal y_pixel_counter : integer range 0 to 7 := 0;
  signal y_char_in_row : integer range 0 to chars_per_row := 0;
  signal y_phase : integer range 0 to 16 := 0;
  signal y_row : integer range 0 to 7 := 0;
  
  signal vk_pixel : unsigned(1 downto 0) := "00";
  signal box_pixel : std_logic := '0';
  signal box_pixel_h : std_logic := '0';
  signal box_inverse : std_logic := '0';
  
  signal address : integer range 0 to 4095 := 0;
  signal rdata : unsigned(7 downto 0);

  signal current_address : integer range 0 to 4095 := 0;
  signal last_row_address : integer range 0 to 4095 := 0;

  signal current_matrix_id : unsigned(7 downto 0);
  signal next_matrix_id : unsigned(7 downto 0);
  signal matrix_pos : integer;

  signal last_was_640 : std_logic := '0';
  signal active : std_logic := '0';
  signal last_pixel_x_640 : integer := 0;
  signal key_box_counter : integer := 0;
  signal key_same_as_last : std_logic := '0';
  
  signal text_delay : integer range 0 to 4 := 0;
  signal next_char : unsigned(7 downto 0) := x"00";
  signal next_char_ready : std_logic := '0';
  signal space_repeat : integer range 0 to 127 := 0;
  signal char_data : std_logic_vector(7 downto 0);
  signal next_char_data : std_logic_vector(7 downto 0);
  signal char_pixel : std_logic := '0';
  signal char_pixels_remaining : integer range 0 to 8 := 0;
  signal first_column : std_logic := '0';

  signal pixel_x_640 : integer := 0;
  signal osk_in_position_lower : std_logic := '1';
  signal last_visual_keyboard_enable : std_logic := '0';
  signal max_y : unsigned(11 downto 0) := (others => '0');
  signal ycounter_last : unsigned(11 downto 0) := (others => '0');
  signal y_lower_start : unsigned(11 downto 0) :=
    to_unsigned(0,12);

  signal double_width : std_logic := '0';
  signal double_width_phase : std_logic := '0';
  signal double_height : std_logic := '0';
  signal double_height_phase : std_logic := '0';

  signal keyboard_text_start : unsigned(11 downto 0) := to_unsigned(2048+256,12);
  signal alt_keyboard_text_start : unsigned(11 downto 0) := to_unsigned(2048+256,12);
  signal alt_offset : integer := 0;

  signal touch1_key_internal : unsigned(7 downto 0) := (others => '1');
  signal touch2_key_internal : unsigned(7 downto 0) := (others => '1');
  
  type fetch_state_t is (
    FetchInitial,
    FetchAltStartLow,
    FetchAltStartHigh,
    FetchIdle,
    CharFetch,
    FetchCharData,
    GotCharData,
    FetchMapRowColumn0,
    FetchMapRowColumn1,
    GotMapRowColumn1,
    FetchNextMatrix,
    GotNextMatrix
    );
  signal fetch_state : fetch_state_t := FetchInitial;
  
  
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
    variable char_addr : unsigned(10 downto 0);
    variable y_gap : unsigned(11 downto 0);
  begin
    if rising_edge(pixelclock) then

      if alternate_keyboard='1' then
        double_width <= '1';
        double_height <= '1';
        keyboard_text_start <= alt_keyboard_text_start;
        alt_offset <= 7*16;
      else
        double_width <= '0';
        double_height <= '0';
        keyboard_text_start <= to_unsigned(2048+256,12);
        alt_offset <= 0;
      end if;
      
      -- Update vertical scale factor to fit video mode
      if pixel_y_scale_200 /= x"0" then
        y_stretch <= to_integer(pixel_y_scale_200) - 1;
      else
        y_stretch <= 0;
      end if;

      -- Check if current touch events correspond to any key
      if visual_keyboard_enable='1' then
        if pixel_x_640 = touch1_x and ycounter_in = touch1_y and touch1_valid='1' then
          touch1_key_internal <= current_matrix_id;
          report "touch1 key = $" & to_hstring(current_matrix_id);
        end if;
        if pixel_x_640 = touch2_x and ycounter_in = touch2_y and touch2_valid='1' then
          touch2_key_internal <= current_matrix_id;
          report "touch2 key = $" & to_hstring(current_matrix_id);
        end if;
      end if;
      
      if pixel_x_640_in < x_start_current then
        pixel_x_640 <= 640;
      else
        pixel_x_640 <= pixel_x_640_in - to_integer(x_start_current);
      end if;
      
      if pixel_x_640 = 640 then
        last_was_640 <= '1';
        space_repeat <= 0;
        char_pixels_remaining <= 0;
        first_column <= '0';
        char_pixel <= '0';
        box_pixel <= '0';
        box_pixel_h <= '0';
        box_inverse <= '0';

        if last_was_640 = '0' then
          -- End of line, prepare for next
--          report "end of line, preparing for next";
          current_matrix_id <= (others => '1');
--          report "current_matrix_id <= $FF from end of raster.";
          fetch_state <= FetchMapRowColumn0;
          if ycounter_in = y_start_current then
            active <= '1';

            -- Packed text starts at $0900 in OSKmem
            current_address <= to_integer(keyboard_text_start);
            last_row_address <= to_integer(keyboard_text_start);

            y_row <= 0;
            y_char_in_row <= 0;
            y_pixel_counter <= 0;
            y_phase <= 0;
          elsif ycounter_in = 0 then
            active <= '0';
            touch1_key <= touch1_key_internal;
            touch2_key <= touch2_key_internal;
            touch1_key_internal <= (others => '1');
            touch2_key_internal <= (others => '1');
            current_matrix_id <= (others => '1');
--            report "current_matrix_id <= $FF from start of frame.";
            
          elsif active='1' then
            if y_phase /= y_stretch then
              if double_height='0' or double_height_phase='1' then
                y_phase <= y_phase + 1;
                double_height_phase <= '0';
              elsif double_height='1' then
                double_height_phase <= '1';
              end if;
              current_address <= last_row_address;
            else
              y_phase <= 0;
              if y_row = 6 then
                -- We draw only the top line for row 6 to cap
                -- off row 5
                active <= '0';
                -- We have reached the bottom of the OSD, so check if it fits
                -- entirely on screen or not.
                if ycounter_in <= max_y then
                  -- Bottom of visual keyboard is on-screen,
                  if y_start_current > y_lower_start then
                    y_lower_start <= y_start_current;
                    report "Setting y_lower_start to " & integer'image(to_integer(y_start_current));
                  end if;
                else
                  osk_in_position_lower <= '0';
                end if;
              end if;
              -- Offset text to boxes by 4 pixels
              if y_pixel_counter /=3 then
                current_address <= last_row_address;
              else
                last_row_address <= current_address;
              end if;
              if y_pixel_counter /=7 then
                y_pixel_counter <= y_pixel_counter + 1;                
              else
                y_pixel_counter <= 0;
                if y_char_in_row /= 2 then
                  y_char_in_row <= y_char_in_row + 1;
                else
                  y_char_in_row <= 0;
                  if y_row /= 6 then
                    y_row <= y_row + 1;
                  else
                    active <= '0';
                  end if;
                end if;
              end if;
            end if;
            -- Last row is only one pixel high to draw lines at bottoms
            -- of keys
            
          else
            -- Not active
          end if;
        end if;
      else
        last_was_640 <= '0';
      end if;

      if pixel_x_640 /= last_pixel_x_640 and active='1' and pixel_x_640 < 640 then
        last_pixel_x_640 <= pixel_x_640;

        -- Calculate character pixel
        char_pixel <= char_data(7);
        if char_pixels_remaining /= 0 then
          if double_width='0' or double_width_phase='1' then
            char_data(7 downto 1) <= char_data(6 downto 0);
            char_data(0) <= '0';
            char_pixels_remaining <= char_pixels_remaining - 1;
            double_width_phase <= '0';
--          report "char_pixels_remaining = " & integer'image(char_pixels_remaining);
          else
            if double_width='1' then
              double_width_phase <= '1';
            end if;
          end if;
        else
          if (text_delay = 0) and (pixel_x_640 > 3) then
            char_pixels_remaining <= 7;
            char_data <= next_char_data;
          else
            char_pixels_remaining <= 3;
            char_data(7 downto 4) <= next_char_data(3 downto 0);
          end if;
          text_delay <= 0;
          next_char_ready <= '0';
          first_column <= '0';
          
          if next_char_data /= x"00" then
--            report "clearing next_char_ready, char_data=$" & to_hstring(next_char_data);
          else
--            report "clearing next_char_ready";
          end if;
        end if;

        -- We want the boxes drawn 4 character pixels lower than
        -- the text.  This is not so easy, as we need to know
        -- things from the previous or next row.
        
        -- Is this box for a key that is currently being pressed?
        -- If so, set inverse video flag for box content
        if (key1(6 downto 0) = current_matrix_id(6 downto 0))
          or (key2(6 downto 0) = current_matrix_id(6 downto 0))
          or (key3(6 downto 0) = current_matrix_id(6 downto 0))
          or (key4(6 downto 0) = current_matrix_id(6 downto 0)) then
          if (y_pixel_counter /= 1 or y_char_in_row /= 0)
            and (y_pixel_counter /= 7 or y_char_in_row /=2)
            and (key_box_counter /= 2
                 or (current_matrix_id(6 downto 0)
                     = next_matrix_id(6 downto 0)))
            and (key_box_counter /= 60) -- wide keys begin earlier
            and (key_box_counter /= 40
                 or (key_same_as_last='1') -- repeated key, like SPACE
                 or (current_matrix_id(7) = '1') -- wide key
                 )
          then
            box_inverse <= '1';
          else
            box_inverse <= '0';
          end if;
        else
          box_inverse <= '0';
        end if;
        -- Don't ever try to draw non-keys reverse
        if current_matrix_id(6 downto 5) = "11" then
          box_inverse <= '0';
        end if;
        
        -- Generate border around each key
        -- Vertical lines:
        if key_box_counter = 1 then
          -- Draw vertical bar between keys on same row
          -- Wide keys may be drawn as several consecutive keys with same
          -- matrix ID. Thus don't draw vertical bar if next key ID is the same
          -- as the current (or between 7E/7F variants of blank spaces)
          if (current_matrix_id(6 downto 0) = next_matrix_id(6 downto 0))
            or ((current_matrix_id(6 downto 1) = "111111") 
                and (next_matrix_id(6 downto 1) = "111111")) then
            null;
          else
            if pixel_x_640 < 640 then
              box_pixel <= '1';
            else
              box_pixel <= '0';
            end if;
          end if;
          if next_matrix_id(7) = '1' then
            -- Next key is 1.5 times width, so set counter accordingly
            key_box_counter <= 7*8+4;
            text_delay <= 4;
          else
            -- Next key is normal width
            key_box_counter <= 5*8;
          end if;
          -- Pre-fetch the next key matrix id
          fetch_state <= FetchNextMatrix;
        else
          -- Draw left edge of keyboard as requird (all rows except SPACE bar row)
          if pixel_x_640=0 and y_row /= 5 and active='1' and alternate_keyboard='0' then
            box_pixel <= '1';
          else
            box_pixel <= '0';
          end if;
          if double_width='0' or double_width_phase='0' then
            key_box_counter <= key_box_counter - 1;
          end if;
        end if;

        -- Horizontal lines:
        -- These are a bit trickier, because we need to know the key above and
        -- below to do this completely cleanly.
        -- We do this by having two blank key types: 7F = no line above,
        -- 7E = with line above
        if (y_char_in_row = 0)  and (y_pixel_counter = 0) then
          if (current_matrix_id(6 downto 0) /= x"7f") then
--            report "box_pixel set x = " & integer'image(pixel_x_640);
            box_pixel_h <= '1';
          else
--            report "box_pixel not set: x = " & integer'image(pixel_x_640)
--              & ", y = " & integer'image(to_integer(ycounter_in))
--              & ", current_matrix_id=$" & to_hstring(current_matrix_id);
            box_pixel_h <= '0';
          end if;
        else
          box_pixel_h <= '0';
        end if;
      end if;
        
      case fetch_state is
        when FetchInitial =>
          address <= 4093;
          fetch_state <= FetchAltStartLow;
        when FetchAltStartLow =>
          address <= 4094;
          alt_keyboard_text_start(7 downto 0) <= rdata;
          fetch_state <= FetchAltStartHigh;
          report "Alt fetch lo = $" & to_hstring(rdata);
        when FetchAltStartHigh =>
          alt_keyboard_text_start(11 downto 8) <= rdata(3 downto 0);
          fetch_state <= FetchIdle;
          report "Alt fetch hi = $" & to_hstring(rdata);
        when FetchIdle =>
          -- Get the next character to display, if we
          -- don't already have one
          if next_char_ready = '0' then
            if space_repeat /= 0 then
              space_repeat <= space_repeat - 1;
              next_char <= x"20";
              next_char_ready <= '1';
            else
              address <= current_address;
              current_address <= current_address + 1;
              fetch_state <= CharFetch;
            end if;          
          end if;
        when CharFetch =>
          if rdata(7 downto 0) = x"0a" then
            -- new line -- nothing more new this line,
            -- just fill with spaces
            next_char <= x"20";
            space_repeat <= 99;
            next_char_ready <= '1';
          elsif rdata(7 downto 4) = x"9" then
            -- RLE encoded spaces
            space_repeat <= 1+to_integer(rdata(3 downto 0));
            next_char <= x"20";
          else
            -- Natural char
            next_char <= rdata;
          end if;
          fetch_state <= FetchCharData;
        when FetchCharData =>
          char_addr(10 downto 3) := next_char;
          char_addr(2 downto 0) := to_unsigned(y_pixel_counter,3);
          char_addr(2) := not char_addr(2);
          address <= to_integer(char_addr);
          fetch_state <= GotCharData;
        when GotCharData =>
          next_char_ready <= '1';
          next_char_data <= std_logic_vector(rdata);
          fetch_state <= FetchIdle;
        when FetchMapRowColumn0 =>
          address <= 2048 + alt_offset + y_row*16;
          fetch_state <= FetchMapRowColumn1;
        when FetchMapRowColumn1 =>
--          report "current_matrix_id <= $" & to_hstring(rdata)
--            & " from $"
--            & to_hstring(to_unsigned(address,12));
          current_matrix_id <= rdata;
          key_same_as_last <= '0';
          address <= 2048 + alt_offset + y_row*16 + 1;
          fetch_state <= GotMapRowColumn1;
        when GotMapRowColumn1 =>
--          report "next_matrix_id <= $" & to_hstring(rdata)
--            & " from $"
--            & to_hstring(to_unsigned(address,12));
          next_matrix_id <= rdata;
          -- Work out width of first key box of row
          if current_matrix_id(7)='1' then
            key_box_counter <= 7*8+4;
            text_delay <= 4;
          else
            key_box_counter <= 5*8;
          end if;
          matrix_pos <= 0;
          fetch_state <= FetchIdle;
        when FetchNextMatrix =>
          if matrix_pos < 16 then
            address <= 2048 + alt_offset + y_row*16 + matrix_pos + 2;
            matrix_pos <= matrix_pos + 1;
          else
            -- Else read a blank character (we know one is at location 1)
            -- (this ensures we draw the right edge of the last key on each
            -- row correctly).
            address <= 2048 + 1;            
          end if;
          fetch_state <= GotNextMatrix;
        when GotNextMatrix =>
--          report "next_matrix_id <= $" & to_hstring(rdata)
--            & " from $"
--            & to_hstring(to_unsigned(address,12));
          if current_matrix_id = next_matrix_id then
            key_same_as_last <= '1';
          else
            key_same_as_last <= '0';
          end if;
          current_matrix_id <= next_matrix_id;
--          report "current_matrix_id <= $" & to_hstring(next_matrix_id)
--            & " from next_matrix_id";
          next_matrix_id <= rdata;
          fetch_state <= FetchIdle;
        when others =>
          null;
      end case;


      -- Draw keyboard matrix boxes
      if active='1' then
        vk_pixel(1) <= box_pixel or box_pixel_h or (box_inverse xor char_pixel);
        vk_pixel(0) <= box_pixel or box_pixel_h or (box_inverse xor char_pixel);
      else
        vk_pixel <= "00";
      end if;

      if visual_keyboard_enable='1' and active='1' then
        vgared_out <= vk_pixel(1)&vgared_in(7 downto 1);
        vgagreen_out <= vk_pixel(1)&vgagreen_in(7 downto 1);
        vgablue_out <= vk_pixel(1)&vgablue_in(7 downto 1);
      else
        vgared_out <= vgared_in;
        vgagreen_out <= vgagreen_in;
        vgablue_out <= vgablue_in;

      end if;
      if ycounter_in = 0 and ycounter_last /= 0 then
        max_y <= ycounter_last;
        max_x <= 0;
        report "setting max_y to "
          & integer'image(to_integer(ycounter_last));
        -- Move visual keyboard up one a bit each frame
        -- visual keyboard disabled, so push it back off the bottom
        -- of the screen

        report "osk_in_position_lower = " & std_logic'image(osk_in_position_lower) &
          ", visual_keyboard_enable = " & std_logic'image(visual_keyboard_enable) &
          ", keyboard_at_top = " & std_logic'image(keyboard_at_top) &
          ", last_visual_keyboard_enable = " & std_logic'image(last_visual_keyboard_enable);
        
        if visual_keyboard_enable = '0' then
          if max_y /= 0 then
            report "Visual keyboard disabled -- pushing to bottom of screen";
            if ycounter_last > max_y then
              y_start_current <= ycounter_last;
              y_lower_start <= ycounter_last;
            else
              y_start_current <= max_y;
              y_lower_start <= to_unsigned(0,12);
            end if;
          else
            report "Visual keyboard disabled: guessing end of screen";
            y_start_current <= (others => '1');
          end if;
        elsif keyboard_at_top='1' then
          -- Keyboard at the top: If it were down low, bring it up 1/8th of
          -- the remaining distance, plus one pixel.  Thus we follow a Xeno's Paradox
          -- like curve to spring the keyboard to the top
          if y_start_current > 2 and instant_at_top='0' then
            report "Xeno-walking keyboard to top a bit";            
            y_start_current <= y_start_current - y_start_current(11 downto 3) - 2;
          else
            y_start_current <= to_unsigned(0,12);
          end if;
          -- OSK is no longer in the correct position for at the bottom of the
          -- screen
          osk_in_position_lower <= '0';
        elsif osk_in_position_lower = '0'
          and visual_keyboard_enable='1'
          and last_visual_keyboard_enable='1' then
          report "y_lower_start = " & integer'image(to_integer(y_lower_start));
          if y_start_current > y_lower_start then
            report "Sliding visual keyboard up a bit";
            -- We slide in with linear speed fairly quickly, as this is the
            -- default position for the OSK, so we want a non-annoying entrance
            -- animation.
            y_start_current(11 downto 3)
              <= y_start_current(11 downto 3)
              - pixel_y_scale_200;
          else
            report "Xeno-Walking visual keyboard back down a bit";
            -- When sliding from top to bottom, this is always returning after
            -- the OSK has been moved to the top for some reason.
            -- Thus we want to mirror the motion that we used to move from
            -- bottom to top (a 1/8th + 2 pixel Xeno step function)
            if y_start_current < y_lower_start then
              y_gap := y_lower_start - y_start_current;
              y_start_current <= y_start_current + y_gap(11 downto 3) + 2;
            else
              y_start_current <= y_lower_start;
              osk_in_position_lower <= '1';
            end if;            
          end if;
          if y_start_current > max_y then
            report "Resetting visual keyboard to bottom edge";
            y_start_current <= max_y;
          end if;
        end if;
        report "y_start_current = " &
          integer'image(to_integer(y_start_current))
          & ", x_start_current = " &
          integer'image(to_integer(x_start_current))
          & ", max_x = " &
          integer'image(max_x);
      end if;
      ycounter_last <= ycounter_in;
      if visual_keyboard_enable='1'
        and last_visual_keyboard_enable='0' then
        -- Visual keyboard has just been enabled, so start it
        -- off the bottom of the screen, and allow it to
        -- move up over several frames
        osk_in_position_lower <= '0';
        if ycounter_last > max_y then
          y_start_current <= ycounter_last;
          report "Setting visual keyboard to ycounter_last as it has just been enabled (=$"
            & to_hstring(ycounter_last) & ")";
        else
          y_start_current <= max_y;
          report "Setting visual keyboard to max_y as it has just been enabled (=$"
            & to_hstring(max_y) & ")";
        end if;
      end if;
      last_visual_keyboard_enable <= visual_keyboard_enable;

      -- Work out where to place keyboard to centre it
      if pixel_x_640 > max_x then
        max_x <= pixel_x_640;
      end if;
      x_start_current(12 downto 0) <= x_surplus(13 downto 1);
      x_start_current(13) <= '0';
      if max_x >= 640 then
        x_surplus <= to_unsigned(max_x - 640,14);
      else
        x_surplus <= (others => '0');
      end if;
    end if;
  end process;
  
end behavioural;
