library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity visual_keyboard is
  port (
    pixelclock : in std_logic;

    ycounter_in : in integer range 0 to 2047;
    xcounter_in : in integer range 0 to 4095;
    
    lcd_display_enable : in std_logic; -- is pixel in frame?
    pixel_strobe_in : in std_logic;
    vgared_in : in  unsigned (7 downto 0);
    vgagreen_in : in  unsigned (7 downto 0);
    vgablue_in : in  unsigned (7 downto 0);

    pixel_strobe_out : out std_logic;
    vgared_out : out  unsigned (7 downto 0);
    vgagreen_out : out  unsigned (7 downto 0);
    vgablue_out : out  unsigned (7 downto 0);

    -- Accessibility key press display
    selected_row : in integer range 0 to 255 := 255; 
    accessible_key : in unsigned(6 downto 0) := to_unsigned(127,7);
    dim_shift : in std_logic := '0'; -- allow background to be shifted much
                                     -- dimmer for accessible keyboard
    
    -- Configuration of display
    osk_debug_display : in std_logic := '0';
    visual_keyboard_enable : in std_logic := '0';
    keyboard_at_top : in std_logic;
    alternate_keyboard : in std_logic;
    instant_at_top : in std_logic;
    -- Flags to enable zoomed display of what is under (the first)
    -- touch point.
    zoom_en_osk : in std_logic := '1';
    zoom_en_always : in std_logic := '1';

    -- Current Y position of the OSK
    osk_ystart : out unsigned(11 downto 0) := (others => '1');
    
    
    -- Synthetic key presses to display
    key1 : in unsigned(7 downto 0);
    key2 : in unsigned(7 downto 0);
    key3 : in unsigned(7 downto 0);    
    key4 : in unsigned(7 downto 0);

    -- memory access interface for matrix mode to read charrom
    matrix_fetch_address : in unsigned(11 downto 0);
    matrix_rdata : out unsigned(7 downto 0);
    
    -- Touch interface
    touch1_valid : in std_logic;
    touch1_x : in unsigned(13 downto 0);
    touch1_y : in unsigned(11 downto 0);
    touch1_key : out unsigned(7 downto 0) := x"FF";
    touch2_valid : in std_logic;
    touch2_x : in unsigned(13 downto 0);
    touch2_y : in unsigned(11 downto 0);
    touch2_key : out unsigned(7 downto 0) := x"FF"

    
    );
end visual_keyboard;

architecture behavioural of visual_keyboard is

  signal last_y_start_current : unsigned(11 downto 0) :=
    to_unsigned(999,12);
  signal y_start_current : unsigned(11 downto 0) :=
    to_unsigned(1,12);
  constant x_start_current : unsigned(13 downto 0) :=
    to_unsigned(80-32,14); -- -32 is to compensate for VIC-IV pipeline depth

  signal y_start_current_upabit : unsigned(11 downto 0) :=
    to_unsigned(0,12);
  
  signal y_stretch : integer range 0 to 15 := 1;

  constant chars_per_row : integer := 3;

  signal y_pixel_counter : integer range 0 to 7 := 0;
  signal y_char_in_row : integer range 0 to chars_per_row := 0;
  signal y_phase : integer range 0 to 16 := 0;
  signal y_row : integer range 0 to 7 := 0;
  
  signal vk_pixel : unsigned(1 downto 0) := "00";
  signal box_pixel : std_logic := '0';
  signal box_pixel_delay : std_logic := '0';
  signal box_pixel_h : std_logic := '0';
  signal box_inverse : std_logic := '0';
  signal box_inverse_delay : std_logic := '0';
  
  signal address : integer range 0 to 4095 := 0;
  signal rdata : unsigned(7 downto 0) := x"00";

  signal current_address : integer range 0 to 4095 := 0;
  signal last_row_address : integer range 0 to 4095 := 0;

  signal current_matrix_id : unsigned(7 downto 0) := x"7F";
  signal next_matrix_id : unsigned(7 downto 0) := x"7F";
  signal matrix_pos : integer := 0;
  signal matrix_fetching : std_logic := '0';

  signal last_was_800 : std_logic := '0';
  signal active : std_logic := '0';
  signal last_ycounter_in : integer := 0;
  signal xcounter : integer := 0;
  signal key_box_counter : integer := 1;
  signal key_same_as_last : std_logic := '0';
  
  signal text_delay : integer range 0 to 4 := 0;
  signal next_char : unsigned(7 downto 0) := x"00";
  signal next_char_ready : std_logic := '0';
  signal space_repeat : integer range 0 to 127 := 0;
  signal char_data : std_logic_vector(7 downto 0);
  signal next_char_data : std_logic_vector(7 downto 0);
  signal char_pixel : std_logic := '0';
  signal char_pixel_delay : std_logic := '0';
  signal char_pixels_remaining : integer range 0 to 8 := 0;
  signal end_of_line : std_logic := '0';
  signal char_column : integer := 0;
  
  signal osk_in_position_lower : std_logic := '0';
  signal last_visual_keyboard_enable : std_logic := '0';
  signal max_y : integer := 600;
  signal ycounter_last : integer := 0;
  signal y_lower_start : unsigned(11 downto 0) :=
    to_unsigned(0,12);

  signal double_width : std_logic := '0';
  signal double_width_phase : std_logic := '0';
  signal double_height : std_logic := '0';
  signal double_height_phase : std_logic := '0';

  signal keyboard_text_start : unsigned(11 downto 0) := to_unsigned(2048+256,12);
  signal alt_keyboard_text_start : unsigned(11 downto 0) := to_unsigned(2048+256,12);
  signal alt_offset : integer := 0;

  signal current_bucky : unsigned(7 downto 0) := x"FF";
  
  signal touch1_key_internal : unsigned(7 downto 0) := (others => '1');
  signal touch1_key_last : unsigned(7 downto 0) := (others => '1');
  signal touch1_hold_timeout : integer range 0 to 127 := 0;
  signal touch1_press_delay : integer range 0 to 127 := 0;
  signal touch1_dont_hold : std_logic := '0';
  signal touch1_set : std_logic := '0';
  
  signal touch2_key_internal : unsigned(7 downto 0) := (others => '1');
  signal touch2_key_last : unsigned(7 downto 0) := (others => '1');
  signal touch2_hold_timeout : integer range 0 to 127 := 0;
  signal touch2_press_delay : integer range 0 to 127 := 0;
  signal touch2_dont_hold : std_logic := '0';
  signal touch2_set : std_logic := '0';

  -- Is the key really down, not just maybe down?
  signal key_real : std_logic := '0';

  -- Interface for showing zoomed version of where a touch is
  -- occurring.
  signal zoom_raddr : integer := 0;
  signal zoom_waddr : integer := 0;
  signal zoom_we : std_logic := '0';
  signal zoom_wdata : unsigned(31 downto 0) := to_unsigned(0,32);
  signal zoom_rdata : unsigned(31 downto 0) := to_unsigned(0,32);
  -- And where it should appear
  signal zoom_display_x : integer := 0;
  signal zoom_display_y : integer := 0;
  signal zoom_display_enable : std_logic := '0';
  -- And the origin of the area we are copying to display zoomed
  signal zoom_origin_x : integer := 0;
  signal zoom_origin_y : integer := 0;
  -- And variables for controlling the recording
  signal zoom_record_en : std_logic := '0';
  signal zoom_record_y : unsigned(4 downto 0) := to_unsigned(0,5);
  signal zoom_record_x : unsigned(4 downto 0) := to_unsigned(0,5);
  signal zoom_recording : integer range 0 to 32 := 0;
  signal zoom_play_y : unsigned(5 downto 0) := to_unsigned(0,6);
  signal zoom_play_x : unsigned(5 downto 0) := to_unsigned(0,6);
  signal zoom_playback_en : std_logic := '0';
  signal zoom_playback_enx : std_logic := '0';
  signal zoom_playback_pixel : std_logic := '0';
  signal zoom_border_pixel : std_logic := '0';
  signal zoom_border_colour : unsigned(7 downto 0) := x"00";
  
  -- Keep OSK in region that fits on 800x480 LCD panel
  -- XXX Tie in to use lcd_inletterbox signal from pixel_driver instead of
  -- computing it here?
  constant y_start_minimum : integer := (600-480)/2 + 19 ;
  constant y_end_maximum : integer := 600 + 19 + 19 - y_start_minimum;
  
  type fetch_state_t is (
    FetchInitial,
    FetchAltStartLow,
    FetchAltStartHigh,
    FetchIdle,
    MatrixFetch,
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

  -- Which row or key to show for accessible keyboard input
  signal row_selected : std_logic := '0';
  signal col_selected : std_logic := '0';
  signal dim_shift_drive : std_logic := '0';
  
begin

  km0: entity work.oskmem
    port map (
      clk => pixelclock,
      address => address,
      we => '0',
      data_i => (others => '1'),
      data_o => rdata
      );

  -- 4KB BRAM for saving 32x32 pixel region 
  zoom0: entity work.ram32x1024_sync
    port map (
      clk => pixelclock,
      cs => '1',
      address => zoom_raddr,
      write_address => zoom_waddr,
      w => zoom_we,
      wdata => zoom_wdata,
      rdata => zoom_rdata
      );
  
  process (pixelclock)
    variable char_addr : unsigned(10 downto 0);
    variable y_gap : unsigned(11 downto 0);
  begin
    if rising_edge(pixelclock) then

      dim_shift_drive <= dim_shift;
      
      last_y_start_current <= y_start_current;
      if y_start_current /= last_y_start_current then
        report "y_start_current = " & integer'image(to_integer(y_start_current));
      end if;
      
      pixel_strobe_out <= pixel_strobe_in;

      xcounter <= xcounter_in;
--      if last_ycounter_in /= ycounter_in then
--        xcounter <= 0;
--      else
--        if pixel_strobe_in = '1' then
--          report "pixel_strobe seen";
--          xcounter <= xcounter + 1;
--        end if;
--      end if;
      
      -- Export the current position of the OSK, so that we can move things around
      -- to match it. In particular, we adjust the serial monitor interface, so
      -- that it doesn't overlap with the keyboard.  Also, we make the memory walking
      -- commands in the monitor show fewer lines at a time, so that you still
      -- get one screen full at a time.
      if visual_keyboard_enable='1' then
        osk_ystart <= y_start_current;
      else
        osk_ystart <= (others => '1');
      end if;
      
      last_ycounter_in <= ycounter_in;
      
      if alternate_keyboard='1' then
        -- Dial-pad / alert notification
        double_width <= '1';
        double_height <= '1';
        keyboard_text_start <= alt_keyboard_text_start;
        alt_offset <= 7*16;
      else
        -- Normal keyboard
        double_width <= '0';
        double_height <= '0';
        keyboard_text_start <= to_unsigned(2048+256,12);
        alt_offset <= 0;
      end if;
      
      -- Work out where to display the zoom, and whether to show it.
      -- We can control if we want it to always appear, only for the visual
      -- keyboard (default), or never.
      if (touch1_key_last /= x"FF"  and zoom_en_osk='1')
        or (touch1_valid='1' and zoom_en_always='1') then
        zoom_display_enable <= '1';
      else
        zoom_display_enable <= '0';
      end if;
      if to_integer(touch1_x) > 31 then
        zoom_display_x <= to_integer(touch1_x) - 32;
      else
        zoom_display_x <= 0;
      end if;
      if to_integer(touch1_x) > 15 then
        zoom_origin_x <= to_integer(touch1_x) - 16;
      else
        zoom_origin_x <= 0;
      end if;
      if to_integer(touch1_y) > 15 then
        zoom_origin_y <= to_integer(touch1_y) - 16;
      else
        zoom_origin_y <= 0;
      end if;
      if to_integer(touch1_y) < (60 + 32 + (32*2)) then
        -- Position zoomed display below touch point if touch point
        -- is right near the top of the display.
        zoom_display_y <= to_integer(touch1_y) + 32;
      else
        -- Position zoomed display above touch point
        zoom_display_y <= to_integer(touch1_y) - (32*2) - 32;
      end if;

      -- Work out when to record for zoom display
      if xcounter = zoom_origin_x then
        zoom_recording <= 32;
        zoom_record_x <= to_unsigned(0,5);
      end if;
      if (ycounter_in = zoom_origin_y) then
        zoom_record_en <= '1';
        zoom_record_y <= to_unsigned(0,5);
      end if;
      if last_ycounter_in /= ycounter_in then
        if zoom_record_y /= "11111" then
          zoom_record_y <= zoom_record_y + 1;
        else
          zoom_record_en <= '0';
        end if;
      end if;
      -- And record it
      if zoom_record_en = '1' and zoom_recording /= 0 then
        zoom_waddr <= to_integer(zoom_record_y&zoom_record_x);
        if visual_keyboard_enable='1' and active='1' then
          -- Record pixel with visual keyboard overlain
          zoom_wdata(15 downto 8) <= vk_pixel(1)&vgagreen_in(7 downto 1);
          if key_real='0' then
            zoom_wdata(7 downto 0) <= vk_pixel(1)&vgared_in(7 downto 1);
            zoom_wdata(23 downto 16) <= vk_pixel(1)&vgablue_in(7 downto 1);
          else
            zoom_wdata(7 downto 0) <= '0'&vgared_in(7 downto 1);
            zoom_wdata(23 downto 16) <= '0'&vgablue_in(7 downto 1);
          end if;
        else
          -- Record normal screen pixel
          zoom_wdata(7 downto 0) <= vgared_in;
          zoom_wdata(15 downto 8) <= vgagreen_in;
          zoom_wdata(23 downto 16) <= vgablue_in;
        end if;
        zoom_we <= '1';
        if pixel_strobe_in='1' then
          zoom_recording <= zoom_recording - 1;
          zoom_record_x <= zoom_record_x + 1;
        end if;
      else
        zoom_we <= '0';
      end if;

      -- And similarly for playing back the zoomed display
      if xcounter = zoom_display_x then
        zoom_play_x <= "000000";
        zoom_playback_enx <= '1';
      end if;
      if ycounter_in = zoom_display_y then
        zoom_playback_en <= '1';
        zoom_play_y <= "000000";
      end if;
      if (last_ycounter_in /= ycounter_in) and zoom_playback_en='1' then
        if zoom_play_y = "111111" then
          zoom_playback_en <= '0';
        else
          zoom_play_y <= zoom_play_y + 1;
        end if;
      end if;
      -- And play it it
      if zoom_playback_en = '1' and zoom_playback_enx='1' then
        zoom_playback_pixel <= '1';
        if zoom_play_x = "111111" or zoom_play_x="000000"
          or zoom_play_y = "111111" or zoom_play_y="000000" then
          zoom_border_pixel <= '1';
          zoom_border_colour <= x"00";
        elsif zoom_play_x = "111110" or zoom_play_x="000001"
          or zoom_play_y = "111110" or zoom_play_y="000001" then
          zoom_border_pixel <= '1';
          zoom_border_colour <= x"FF";
        else
          zoom_border_pixel <= '0';
        end if;
        zoom_raddr <= to_integer(zoom_play_y(5 downto 1)&zoom_play_x(5 downto 1));
        if pixel_strobe_in='1' then
          if zoom_play_x /="111111" then
            zoom_play_x <= zoom_play_x + 1;
          else
            zoom_playback_enx <= '0';
          end if;
        end if;
      else
        zoom_playback_pixel <= '0';
        zoom_border_pixel <= '0';
      end if;

      -- Highlighting of rows for accessibility mode
      if active = '1' and y_row = selected_row then
        row_selected <= '1';
      else
        row_selected <= '0';
      end if;
      
      -- Check if current touch events correspond to any key
      if visual_keyboard_enable='1' then
        if xcounter = touch1_x and ycounter_in = touch1_y and touch1_valid='1' then
          touch1_key_internal <= current_matrix_id;
--          report "touch1 key = $" & to_hstring(current_matrix_id);
        end if;
        if xcounter = touch2_x and ycounter_in = touch2_y and touch2_valid='1' then
          touch2_key_internal <= current_matrix_id;
--          report "touch2 key = $" & to_hstring(current_matrix_id);
        end if;
      end if;
      
      if xcounter = 0 then
        last_was_800 <= '1';
        space_repeat <= 0;
        char_pixels_remaining <= 0;
        char_pixel <= '0';
        box_pixel <= '0';
        box_pixel_h <= '0';
        box_inverse <= '0';
        end_of_line <= '0';
        char_column <= 0;

        if last_was_800 = '0' then
          -- End of line, prepare for next
          current_matrix_id <= (others => '1');
--          report "column0: fetch_state = " & fetch_state_t'image(fetch_state);
          fetch_state <= FetchMapRowColumn0;

          if ycounter_in = y_start_current then
            active <= '1';
            report "Asserting active";
            
            -- Packed text starts at $0900 in OSKmem
            current_address <= to_integer(keyboard_text_start);
            last_row_address <= to_integer(keyboard_text_start);

            y_row <= 0;
            y_char_in_row <= 0;
            y_pixel_counter <= 0;
            y_phase <= 0;
          elsif ycounter_in = 0 then
            report "Clearing active";
            active <= '0';
            current_matrix_id <= (others => '1');            
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
              double_height_phase <= '0';
              if y_row = 6 then
                -- We draw only the top line for row 6 to cap
                -- off row 5
                report "Clearing active";
                active <= '0';
                -- We have reached the bottom of the OSD, so check if it fits
                -- entirely on screen or not.
                if ycounter_in <= y_end_maximum then
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
                    report "Clearing active";
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
        last_was_800 <= '0';
      end if;

      -- XXX Disable clipping for now while debugging X positioning
      if char_column = 81 then
        end_of_line <= '1';
      end if;
    
      if pixel_strobe_in='1' and active='1' and (xcounter /= 0) and (xcounter >= x_start_current) then

        report "Rendering OSK pixel";
        
        -- Calculate character pixel
        char_pixel <= char_data(7);
        if char_pixels_remaining /= 0 then
          if double_width='0' or double_width_phase='1' then
            char_data(7 downto 1) <= char_data(6 downto 0);
            char_data(0) <= '0';
            char_pixels_remaining <= char_pixels_remaining - 1;
            double_width_phase <= '0';
          report "char_pixels_remaining = " & integer'image(char_pixels_remaining);
          else
            if double_width='1' then
              double_width_phase <= '1';
            end if;
          end if;
        else
          if text_delay=0 then
            -- Add extra blank pixel between chars to space things out a bit more
            -- to take up more of the 800 pixel wide display
            -- This still allows us to have 88 characters wide.
            char_pixels_remaining <= 7 + 1;
            char_data <= next_char_data;
          else
            char_pixels_remaining <= 3;
            char_data(7 downto 4) <= next_char_data(3 downto 0);
          end if;
          char_column <= char_column + 1;
          text_delay <= 0;
          next_char_ready <= '0';
          
          if next_char_data /= x"00" then
            report "clearing next_char_ready, char_data=$" & to_hstring(next_char_data);
          else
            report "clearing next_char_ready";
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
          key_real <= '1';
        else
          key_real <= '0';
        end if;

        if accessible_key = current_matrix_id(6 downto 0) then
          col_selected <= '1';
        else
          col_selected <= '0';
        end if;
        
        if (key1(6 downto 0) = current_matrix_id(6 downto 0))
          or (key2(6 downto 0) = current_matrix_id(6 downto 0))
          or (key3(6 downto 0) = current_matrix_id(6 downto 0))
          or (key4(6 downto 0) = current_matrix_id(6 downto 0))
          or (touch1_key_last(6 downto 0) = current_matrix_id(6 downto 0))
          or (touch2_key_last(6 downto 0) = current_matrix_id(6 downto 0))
        then
--          if current_matrix_id(6 downto 0) /= "1111111" then
--            report "Key $"& to_hstring(current_matrix_id(6 downto 0))  &" down";
--          end if;
          if (y_pixel_counter /= 1 or y_char_in_row /= 0)
            and (y_pixel_counter /= 7 or y_char_in_row /=2)
            and (key_box_counter /= 2
                 or (current_matrix_id(6 downto 0)
                     = next_matrix_id(6 downto 0)))
            and (key_box_counter /= 7*9+4) -- wide keys begin earlier 
            and (key_box_counter /= (5*9)
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
            if xcounter /= 0 then
              box_pixel <= not end_of_line;
            else
              box_pixel <= '0';
            end if;
          end if;
          if next_matrix_id(7) = '1' then
            -- Next key is 1.5 times width, so set counter accordingly
            key_box_counter <= 7*9+4;
            text_delay <= 4;
          else
            -- Next key is normal width
            key_box_counter <= 5*9;
          end if;
          -- Pre-fetch the next key matrix id
          fetch_state <= FetchNextMatrix;
        else
          box_pixel <= '0';
          if double_width='0' or double_width_phase='0' then
            if key_box_counter /= 0 then
              key_box_counter <= key_box_counter - 1;
            end if;
          end if;
        end if;
            
        -- Horizontal lines:
        -- These are a bit trickier, because we need to know the key above and
        -- below to do this completely cleanly.
        -- We do this by having two blank key types: 7F = no line above,
        -- 7E = with line above
        if (y_char_in_row = 0)  and (y_pixel_counter = 0) then
          if (current_matrix_id(6 downto 0) /= x"7f") then
--            report "box_pixel set x = " & integer'image(pixel_x_relative);
            box_pixel_h <= not end_of_line;
          else
--          report "box_pixel not set: x = " & integer'image(pixel_x_relative)
--                 & ", y = " & integer'image(to_integer(ycounter_in))
--                 & ", current_matrix_id=$" & to_hstring(current_matrix_id);
            box_pixel_h <= '0';
          end if;
        else
          box_pixel_h <= '0';
        end if;
      end if;
      -- Fudge factor to fix uneven line lengths caused by 1.5 width characters
      if (y_char_in_row = 0)  and (y_pixel_counter = 0) and xcounter > (688 + x_start_current) and xcounter < (721 + x_start_current) then
        box_pixel_h <= '1';
      end if;
      if xcounter = (720 + x_start_current) and y_row < 4 then
        box_pixel <= '1';
      end if;
      -- Draw left edge of keyboard as required (all rows except SPACE bar row)
      -- Also down the right hand side.
      if (xcounter=(x_start_current-1) and y_row < 5 and active='1' and alternate_keyboard='0') then
        box_pixel <= '1';
      end if;

      if fetch_state /= FetchIdle and fetch_state /= MatrixFetch then
--        report "fetch_state = " & fetch_state_t'image(fetch_state);
      end if;
      matrix_fetching <= '0';
      if matrix_fetching = '1' then
        matrix_rdata <= rdata;
      end if;
      case fetch_state is
        when FetchInitial =>
          address <= 4093;
          fetch_state <= FetchAltStartLow;
        when FetchAltStartLow =>
          address <= 4094;
          alt_keyboard_text_start(7 downto 0) <= rdata;
          fetch_state <= FetchAltStartHigh;
--          report "Alt fetch lo = $" & to_hstring(rdata);
        when FetchAltStartHigh =>
          alt_keyboard_text_start(11 downto 8) <= rdata(3 downto 0);
          fetch_state <= FetchIdle;
--          report "Alt fetch hi = $" & to_hstring(rdata);
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
          else
            -- Otherwise, if nothing else to do, service any
            -- requests from the Matrix Mode compositor
            -- (it uses our character set memory)
            address <= to_integer(matrix_fetch_address);
            matrix_fetching <= '1';
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
            key_box_counter <= 7*9+4;
            text_delay <= 4;
          else
            key_box_counter <= 5*9;
          end if;
          matrix_pos <= 0;
          fetch_state <= FetchIdle;
        when FetchNextMatrix =>
          if (matrix_pos < 16) and (y_row < 30) then
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
      -- horizontal lines draw one pixel late, so delay vertical bars and other
      -- elements, so that it all lines up nicely.
      box_pixel_delay <= box_pixel;
      box_inverse_delay <= box_inverse;
      char_pixel_delay <= char_pixel;
      if active='1' then
        vk_pixel(1) <= box_pixel_delay or box_pixel_h or (box_inverse_delay xor char_pixel_delay);
        vk_pixel(0) <= box_pixel_delay or box_pixel_h or (box_inverse_delay xor char_pixel_delay);
      else
        vk_pixel <= "00";
      end if;

      if touch1_y = ycounter_in and touch1_x = xcounter then
--        report "touch1 @ " & integer'image(to_integer(touch1_x))
--          & "," & integer'image(to_integer(touch1_y));
        vgared_out <= x"00";
        vgagreen_out <= x"00";
        vgablue_out <= x"00";
      elsif touch2_y = ycounter_in and touch2_x = xcounter then
--        report "touch2 @ " & integer'image(to_integer(touch2_x))
--          & "," & integer'image(to_integer(touch2_y));
        vgared_out <= x"FF";
        vgagreen_out <= x"FF";
        vgablue_out <= x"FF";
      elsif zoom_playback_pixel='1' and zoom_display_enable='1' then
        if zoom_border_pixel='1' then
          -- Show 
          vgared_out <= zoom_border_colour;
          vgagreen_out <= zoom_border_colour;
          vgablue_out <= zoom_border_colour;
        else
          vgared_out <= zoom_rdata(7 downto 0);
          vgagreen_out <= zoom_rdata(15 downto 8);
          vgablue_out <= zoom_rdata(23 downto 16);
        end if;
      elsif visual_keyboard_enable='1' and active='1' then
--        report "Painting OSK pixel " & std_logic'image(vk_pixel(1)) & ", char_pixel = " & std_logic'image(char_pixel);
        if dim_shift_drive='0' then
          -- Background dimmed 2x
          if row_selected='1' or col_selected='1' then
            -- Key is also selected for accessible input
            vgablue_out <= vk_pixel(1)&vgablue_in(7 downto 1);
            if key_real='0' then
              vgared_out <= vk_pixel(1)&vgared_in(7 downto 1);
              vgagreen_out <= vk_pixel(1)&vgagreen_in(7 downto 1);
            else
              vgared_out <= '0'&vgared_in(7 downto 1);
              vgagreen_out <= '0'&vgared_in(7 downto 1);
            end if;
          else
            -- Key is NOT selected for accessible input
            vgagreen_out <= vk_pixel(1)&vgagreen_in(7 downto 1);
            if key_real='0' then
              vgared_out <= vk_pixel(1)&vgared_in(7 downto 1);
              vgablue_out <= vk_pixel(1)&vgablue_in(7 downto 1);
            else
              vgared_out <= '0'&vgared_in(7 downto 1);
              vgablue_out <= '0'&vgablue_in(7 downto 1);
            end if;
          end if;            
        else
          -- Background dimmed 4x
          if row_selected='1' or col_selected='1' then
            -- Key is also selected for accessible input
            vgablue_out <= vk_pixel&vgagreen_in(7 downto 2);
            if key_real='0' then
              vgared_out <= vk_pixel&vgared_in(7 downto 2);
              vgagreen_out <= vk_pixel&vgablue_in(7 downto 2);
            else
              vgared_out <= "00"&vgared_in(7 downto 2);
              vgagreen_out <= "00"&vgablue_in(7 downto 2);
            end if;
          else
            -- Key is NOT selected for accessible input
            vgagreen_out <= vk_pixel&vgagreen_in(7 downto 2);
            if key_real='0' then
              vgared_out <= vk_pixel&vgared_in(7 downto 2);
              vgablue_out <= vk_pixel&vgablue_in(7 downto 2);
            else
              vgared_out <= "00"&vgared_in(7 downto 2);
              vgablue_out <= "00"&vgablue_in(7 downto 2);
            end if;
          end if;
        end if;
      elsif osk_debug_display='0' then
        vgared_out <= vgared_in;
        vgagreen_out <= vgagreen_in;
        vgablue_out <= vgablue_in;
      else
        -- y_start_current looks okay, too
        vgared_out(7) <= active;
        vgared_out(6 downto 0) <= y_start_current(11 downto 5);

        -- We see no hint of the xcounter progressing, however.
        vgagreen_out(7 downto 0) <= to_unsigned(xcounter,8);

        -- Is it due to a lack of lcd_display_enable signal?
        -- We seem to not get any lcd_display_enable signal
        vgablue_out(7) <= lcd_display_enable;
        -- Y counter seems fine
        vgablue_out(6 downto 0) <= to_unsigned(ycounter_in,7);
      end if;

      -- Work out next position up, and clip at y_start_minimum if required.
      if y_start_current - y_start_current(11 downto 3) - 2 > y_start_minimum then
        y_start_current_upabit <= y_start_current - y_start_current(11 downto 3) - 2;
      else
        y_start_current_upabit <= to_unsigned(y_start_minimum,12);
      end if;

--      report "ycounter_in = " & integer'image(ycounter_in)
--        & ", y_start_current = " & integer'image(to_integer(y_start_current))
--        & ", y_lower_start = " & integer'image(to_integer(y_lower_start))
--        & ", y_start_minimum = " & integer'image(y_start_minimum)
--        & ", xcounter = " & integer'image(xcounter);
        
      ycounter_last <= ycounter_in;
      if ycounter_in = 0 and ycounter_last /= 0 then

        report "XXX Top of frame";
        
        max_y <= ycounter_last;
        box_pixel_h <= '0';
        box_pixel <= '0';
        text_delay <= 0;
        key_box_counter <= 0;
        double_width <= '0';
        double_width_phase <= '0';

        touch1_key_last <= touch1_key_internal;
        touch2_key_last <= touch2_key_internal;
        
        if touch1_key_last /= x"FF" and touch1_key_internal = x"FF" and touch1_dont_hold='0' then
          -- Touch released over a key. Issue event for this key
          case to_integer(touch1_key_last) is
            when 15|52|58|61|66|64 =>
              -- It's a bucky key, so make this the current set bucky key,
              -- or cancel it if it already was the current bucky.
              if current_bucky = touch1_key_last then
                current_bucky <= x"FF";
                if touch1_set = '0' then
                  touch1_key <= x"FF";
                end if;
                if touch2_set = '0' then
                  touch2_key <= x"FF";
                end if;
              else
                current_bucky <= touch1_key_last;
                if touch1_set = '0' then
                  touch1_key <= touch1_key_last;
                end if;
                if touch2_set = '0' then
                  touch2_key <= touch1_key_last;
                end if;
              end if;
            when others =>
              touch1_set <= '1';
              touch1_key <= touch1_key_last;
              touch1_hold_timeout <= 5;
          end case;
        elsif touch1_key_internal = x"FF" and touch1_key_last = x"FF" and touch1_hold_timeout = 0 then
          -- Timeout holding of a key after it has been pressed (only if no
          -- active or just ended touch in play)
          touch1_key <= current_bucky;
          touch1_set <= '0';
          touch1_dont_hold <= '0';
        elsif touch1_key_internal = x"FF" and touch1_hold_timeout > 0 then
          -- Decrement key release timeout if non-zero
          touch1_hold_timeout <= touch1_hold_timeout - 1;
        elsif touch1_key_last /= touch1_key_internal and touch1_key_internal /= x"FF" then
          -- We have moved from one key to another, so reset press delay
          touch1_press_delay <= 40;
          -- And mark previous key as no longer set
          touch1_key <= current_bucky;
          touch1_set <= '0';
        elsif touch1_key_last = touch1_key_internal and touch1_key_internal /= x"FF" then
          if touch1_press_delay /= 0 then
            touch1_press_delay <= touch1_press_delay - 1;
          else
            -- Same key held for more than 40 frames, so now press it.
            touch1_set <= '1';
            touch1_key <= touch1_key_internal;
            -- But don't set hold timeout for this key, since it is already
            -- being pressed, and should be release immediately on release
            touch1_dont_hold <= '1';
            touch1_hold_timeout <= 0;
          end if;
        end if;

        if touch2_key_last /= x"FF" and touch2_key_internal = x"FF" and touch2_dont_hold='0' then
          -- Touch released over a key. Issue event for this key
          -- XXX Toggle bucky keys rather than holding them.
          -- (and toggle should be on key-down, not key up)
          case to_integer(touch2_key_last) is
            when 15|52|58|61|66|64 =>
              -- Bucky key: Replace current buckey key with this, or
              -- cancel if it already was the current bucky.
              if current_bucky = touch2_key_last then
                current_bucky <= x"FF";
                if touch1_set = '0' then
                  touch1_key <= x"FF";
                end if;
                if touch2_set = '0' then
                  touch2_key <= x"FF";
                end if;
              else
                current_bucky <= touch2_key_last;
                if touch1_set = '0' then
                  touch1_key <= touch1_key_last;
                end if;
                if touch2_set = '0' then
                  touch2_key <= touch1_key_last;
                end if;
              end if;
            when others =>
              touch2_key <= touch2_key_last;
              touch2_hold_timeout <= 5;
          end case;
        elsif touch2_key_internal = x"FF" and touch2_key_last = x"FF" and touch2_hold_timeout = 0 then
          -- Timeout holding of a key after it has been pressed
          touch2_key <= current_bucky;
          touch2_set <= '0';
          touch2_dont_hold <= '0';
        elsif touch2_key_internal = x"FF" and touch2_hold_timeout > 0 then
          -- Decrement key release timeout if non-zero
          touch2_hold_timeout <= touch2_hold_timeout - 1;
        elsif touch2_key_last /= touch2_key_internal and touch2_key_internal /= x"FF" then
          -- We have moved from one key to another, so reset press delay
          touch2_press_delay <= 40;
        elsif touch2_key_last = touch2_key_internal and touch2_key_internal /= x"FF" then
          if touch2_press_delay /= 0 then
            touch2_press_delay <= touch2_press_delay - 1;
          else
            -- Same key held for more than 40 frames, so now press it.
            touch2_set <= '1';
            touch2_key <= touch1_key_internal;
            -- But don't set hold timeout for this key, since it is already
            -- being pressed, and should be release immediately on release
            touch2_dont_hold <= '1';
            touch2_hold_timeout <= 0;
          end if;
        end if;
        
        touch1_key_internal <= (others => '1');
        touch2_key_internal <= (others => '1');
        
--        report "setting max_y to "
--          & integer'image(ycounter_last);
        -- Move visual keyboard up one a bit each frame
        -- visual keyboard disabled, so push it back off the bottom
        -- of the screen

--        report "osk_in_position_lower = " & std_logic'image(osk_in_position_lower) &
--          ", visual_keyboard_enable = " & std_logic'image(visual_keyboard_enable) &
--          ", keyboard_at_top = " & std_logic'image(keyboard_at_top) &
--          ", last_visual_keyboard_enable = " & std_logic'image(last_visual_keyboard_enable);
        
        if visual_keyboard_enable = '0' then
          if max_y /= 0 then
--            report "Visual keyboard disabled -- pushing to bottom of screen. y_start_current reset";
            if ycounter_last > max_y then
              y_start_current <= to_unsigned(ycounter_last,12);
              y_lower_start <= to_unsigned(ycounter_last,12);
            else
              y_start_current <= to_unsigned(max_y,12);
              y_lower_start <= to_unsigned(0,12);
            end if;
          else
--            report "Visual keyboard disabled: guessing end of screen. y_start_current = all 1s";
            y_start_current <= (others => '1');
          end if;
        elsif keyboard_at_top='1' then
          -- Keyboard at the top: If it were down low, bring it up 1/8th of
          -- the remaining distance, plus one pixel.  Thus we follow a Xeno's Paradox
          -- like curve to spring the keyboard to the top
          if y_start_current > (y_start_minimum+3) and instant_at_top='0' then
            report "Xeno-walking keyboard to top a bit. new y_start_current = "
              & integer'image(to_integer(y_start_current_upabit));
            y_start_current <= y_start_current_upabit;
          else
            report "Jumping keyboard to y_start_minimum. y_start_current = " & integer'image(y_start_minimum);
            y_start_current <= to_unsigned(y_start_minimum,12);
          end if;
          -- OSK is no longer in the correct position for at the bottom of the
          -- screen
          osk_in_position_lower <= '0';
        elsif osk_in_position_lower = '0'
          and visual_keyboard_enable='1'
          and last_visual_keyboard_enable='1' then
          report "y_lower_start = " & integer'image(to_integer(y_lower_start));
          if y_start_current > y_lower_start and y_start_current > y_start_minimum then
            report "Sliding visual keyboard up a bit from y_start_current = " & integer'image(to_integer(y_start_current));
            -- We slide in with linear speed fairly quickly, as this is the
            -- default position for the OSK, so we want a non-annoying entrance
            -- animation.
            y_start_current(11 downto 3)
              <= y_start_current(11 downto 3)
              - 2;
          else
            report "Xeno-Walking visual keyboard y_start_current back down a bit";
            -- When sliding from top to bottom, this is always returning after
            -- the OSK has been moved to the top for some reason.
            -- Thus we want to mirror the motion that we used to move from
            -- bottom to top (a 1/8th + 2 pixel Xeno step function)
            if y_start_current < y_start_minimum then
              report "y_start_current <= y_start_minimum";
              y_start_current <= to_unsigned(y_start_minimum,12);
            elsif y_start_current < y_lower_start then
              y_gap := y_lower_start - y_start_current;
              y_start_current <= y_start_current + y_gap(11 downto 3) + 2;
            else
              report "y_start_current <= y_lower_start";
              y_start_current <= y_lower_start;
              osk_in_position_lower <= '1';
            end if;            
          end if;
          if y_start_current > y_end_maximum then
            report "Resetting visual keyboard y_start_current to bottom edge (y_end_maximum)";
            y_start_current <= to_unsigned(y_end_maximum,12);
          end if;
        end if;
      end if;
      if visual_keyboard_enable='1'
        and last_visual_keyboard_enable='0' then
        -- Visual keyboard has just been enabled, so start it
        -- off the bottom of the screen, and allow it to
        -- move up over several frames
        osk_in_position_lower <= '0';
        if ycounter_last > max_y then
          y_start_current <= to_unsigned(ycounter_last,12);
          report "Setting visual keyboard y_start_current to ycounter_last as it has just been enabled (="
            & integer'image(ycounter_last) & ")";
        else
          y_start_current <= to_unsigned(max_y,12);
          report "Setting visual keyboard y_start_current to max_y as it has just been enabled (="
            & integer'image(max_y) & ")";
        end if;
      end if;
      last_visual_keyboard_enable <= visual_keyboard_enable;

    end if;
  end process;
  
end behavioural;
