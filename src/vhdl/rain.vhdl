library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;

-- TODO list for new matrix mode controller:
--
-- XXX Based on matrix mode and secure mode flags, we should copy
-- appropriate banner text into place.
-- 1. Matrix mode -- simple welcome message with commit ID and
--    basic help.
-- 2. Secure mode entry -- display info about call, hash of memory
--    and total size of memory to investigate, plus hot key list.
-- 3. Secure mode exit -- similar to above, but amount of XFER mem
--    that is being handed back.
--
-- XXX Add automatic parsing of hex and display of ASCII bytes to
-- right of hex dump, to save serial monitor having to do it for
-- us, and having trouble with special characters. Or should we have
-- and escape code that allows a literal to be displayed, and then
-- just have serial monitor use that?

entity matrix_rain_compositor is
  
  port (
    -- CPU clock (typically 50MHz)
    clk : in std_logic; 

    pal_mode : in std_logic;
    
    -- Whether matrix mode should be displayed or not
    matrix_mode_enable : in std_logic;

    -- Green matrix mode or lava secure mode
    secure_mode_flag : in std_logic;
    
    -- Character output produced by serial monitor
    monitor_char_in : in unsigned(7 downto 0);
    monitor_char_valid : in std_logic;
    terminal_emulator_ready : out std_logic := '1';
    terminal_emulator_ack : out std_logic := '1';
    
    -- Pixel clock and scale factors according to video mode
    pixelclock  : in  std_logic;
    pixel_y_scale_200 : in unsigned(3 downto 0);
    pixel_y_scale_400 : in unsigned(3 downto 0);
    -- Physical raster line number
    ycounter_in : in unsigned(11 downto 0);
    ycounter_out : out unsigned(11 downto 0) := (others => '0');
    -- Scaled horizontal position (for virtual 640H
    -- operation, regardless of physical video mode)
    xcounter_in : in integer range 0 to 4095;
    xcounter_out : out integer;
    lcd_in_letterbox : in std_logic;

    -- Info about what the visual keyboard is doing
    osk_ystart : in unsigned(11 downto 0);
    visual_keyboard_enable : in std_logic;
    keyboard_at_top : in std_logic;
    
    -- Remote memory access interface to visual keyboard for
    -- character set.
    matrix_fetch_address : out unsigned(11 downto 0) := x"000";
    matrix_rdata : in unsigned(7 downto 0);
    
    -- Seed for matrix rain randomisation
    seed   : in  unsigned(15 downto 0);

    -- Video feed to be composited over
    external_frame_x_zero : in std_logic;
    external_frame_y_zero : in std_logic;
    vgared_in : in unsigned(7 downto 0);
    vgagreen_in : in unsigned(7 downto 0);
    vgablue_in : in unsigned(7 downto 0);

    -- Composited output video feed
    vgared_out : out unsigned(7 downto 0);
    vgagreen_out : out unsigned(7 downto 0);
    vgablue_out : out unsigned(7 downto 0)    
    
    );

end matrix_rain_compositor;

architecture rtl of matrix_rain_compositor is
  constant debug_x : integer := 9999 + 56;

  signal last_external_frame_x_zero : std_logic := '0';
  signal last_external_frame_y_zero : std_logic := '0';
  
  signal screenram_we : std_logic := '0';
  signal screenram_addr : integer range 0 to 4095 := 0;
  signal screenram_wdata : unsigned(7 downto 0) := x"FF";
  signal screenram_rdata : unsigned(7 downto 0);  

  -- Terminal emulator state
  -- Cursor position and blink status
  signal te_cursor_x : integer range 0 to 127 := 0;
  signal te_cursor_y : integer range 0 to 127 := 0;
  signal te_blink_state : std_logic := '1';
  signal te_blink_counter : integer range 0 to 50 := 0;
  signal te_in_header : std_logic := '0';
  -- te_screen_height * te_line_length must be <2048
  -- Screen RAM sits at end of 4KB BRAM.
  -- We have two extra header line that can be set using only
  -- special writing sequences.  It persists, even when screen
  -- is cleared.
  constant te_header_line_count : integer := 5;
  constant te_screen_height : integer := 30 - te_header_line_count;
  constant te_y_max : integer := te_screen_height - 1;
  constant te_line_length : integer := 50;
  constant te_x_max : integer := te_line_length - 1;
  constant te_screen_start : integer
    := 4096 - te_screen_height * te_line_length;
  constant te_header_start : integer
    := te_screen_start - te_line_length * te_header_line_count;
  -- Cursor starts at top of normal screen
  signal te_cursor_address : integer := te_screen_start;
  signal monitor_char_primed : std_logic := '0';
  signal terminal_emulator_fast : std_logic := '1';
  
  signal erase_terminal_memory : std_logic := '0';
  signal scroll_terminal_up : std_logic := '0';
  signal erase_address : integer := 0;
  signal scroll_read : std_logic := '0';
  signal scroll_write_ready : std_logic := '0';
  signal scroll_byte : unsigned(7 downto 0) := x"00";
  
  signal state : unsigned(15 downto 0) := (others => '1');
  type feed_t is (Normal,Rain,Matrix);
  signal feed : feed_t := Normal;
  signal frame_number : integer range 0 to 127 := 70;
  signal lfsr_advance_counter : integer range 0 to 31 := 0;
  signal last_letterbox : std_logic := '1';
  signal last_xcounter_in : integer := 0;
  signal last_xcounter_t1 : integer := 0;
  signal last_xcounter_t2 : integer := 0;
  
  signal drop_start : integer range 0 to 63 := 1;
  signal drop_end : integer range 0 to 63 := 1;
  signal drop_start_drive : integer range 0 to 63 := 1;
  signal drop_end_drive : integer range 0 to 63 := 1;
  signal drop_row : integer range 0 to 63 := 1;
  
  signal drop_start_plus_row_drive : integer range 0 to 127 := 0;
  signal drop_start_plus_end_plus_row_drive
    : integer range 0 to 255 := 0;
  signal drop_start_plus_row : integer range 0 to 127 := 0;
  signal drop_start_plus_end_plus_row
    : integer range 0 to 255 := 0;
  signal drop_distance_to_end : unsigned(7 downto 0) := x"00";
  signal drop_distance_to_start : unsigned(7 downto 0) := x"00";
  signal drop_distance_to_end_drive : unsigned(7 downto 0) := x"00";
  signal drop_distance_to_start_drive : unsigned(7 downto 0) := x"00";
  signal drop_distance_to_end_drive2 : unsigned(8 downto 0) := "000000000";
  signal drop_distance_to_start_drive2 : unsigned(8 downto 0) := "000000000";
  
  signal lfsr_reset : std_logic_vector(3 downto 0) := "0000";
  signal lfsr_out : std_logic_vector(3 downto 0) := "0000";
  signal lfsr_advance : std_logic_vector(3 downto 0) := "0000";
  signal lfsr_seed0 : unsigned(15 downto 0) := x"0000";
  signal lfsr_seed1 : unsigned(15 downto 0) := x"0000";
  signal lfsr_seed2 : unsigned(15 downto 0) := x"0000";
  signal lfsr_seed3 : unsigned(15 downto 0) := x"0000";
  
  signal next_glyph : unsigned(15 downto 0) := (others => '0');
  signal next_start : unsigned(7 downto 0) := x"00";
  signal next_end : unsigned(7 downto 0) := x"00";

  signal glyph_bit_count : integer range 0 to 16 := 0;
  signal glyph_bits : std_logic_vector(7 downto 0) := x"FF";
  signal next_glyph_bits : std_logic_vector(7 downto 0) := x"FF";
  signal glyph_pixel : std_logic := '0';
  signal xflip : std_logic := '0';

  signal char_bit_count : integer range 0 to 16 := 0;
  signal char_bits : std_logic_vector(7 downto 0) := x"FF";
  signal char_bit_stretch : std_logic := '0';
  signal next_char_bits : std_logic_vector(7 downto 0) := x"FF";
  signal matrix_fetch_screendata : std_logic := '0';
  signal matrix_fetch_chardata : std_logic := '0';
  signal matrix_fetch_glyphdata : std_logic := '0';

  signal fetch_next_char : std_logic := '0';
  signal char_screen_address : unsigned(11 downto 0) := to_unsigned(te_screen_start,12);
  signal line_screen_address : unsigned(11 downto 0) := to_unsigned(te_screen_start,12);
  signal char_ycounter : unsigned(11 downto 0) := to_unsigned(0,12);
  signal row_counter : integer := 0;
  signal column_counter : integer := 0;
  signal column_visible : std_logic := '0';
  signal colourify_data : std_logic := '0';
  signal alternate_colour : std_logic := '0';
  signal alternate_row : std_logic := '0';  
  signal next_is_cursor : std_logic := '0';
  signal is_cursor : std_logic := '0';  

  signal invert_next_frame : std_logic := '0';
  signal invert_frame : std_logic := '0';

  signal skip_rows : unsigned(4 downto 0) := to_unsigned(0,5);
  signal skip_rasters : unsigned(3 downto 0) := to_unsigned(0,4);
  signal skip_bytes : integer := 0;
  signal osk_rasters_used: unsigned(11 downto 0) := to_unsigned(0,12);
  signal last_y_used : unsigned(11 downto 0) := to_unsigned(0,12);
  
begin  -- rtl

  -- This will stay high until monitor_char_valid is dropped.
  terminal_emulator_ack <= not monitor_char_primed;
  
  screenram0:   entity work.termmem port map (
    clk => pixelclock,
    we => screenram_we,
    data_i => screenram_wdata,
    address => screenram_addr,
    data_o => screenram_rdata
    );
  
  lfsr0: entity work.lfsr16 port map (
    name => "lfsr0",
    clock => pixelclock,
    reset => lfsr_reset(0),
    seed => lfsr_seed0,
    step => lfsr_advance(0),
    output => lfsr_out(0));
  lfsr1: entity work.lfsr16 port map (
    name => "lfsr1",
    clock => pixelclock,
    reset => lfsr_reset(1),
    seed => lfsr_seed1,
    step => lfsr_advance(1),
    output => lfsr_out(1));
  lfsr2: entity work.lfsr16 port map (
    name => "lfsr2",
    clock => pixelclock,
    reset => lfsr_reset(2),
    seed => lfsr_seed2,
    step => lfsr_advance(2),
    output => lfsr_out(2));
  lfsr3: entity work.lfsr16 port map (
    name => "lfsr3",
    clock => pixelclock,
    reset => lfsr_reset(3),
    seed => lfsr_seed0,
    step => lfsr_advance(3),
    output => lfsr_out(3));
  
  process(pixelclock)
    variable screenram_busy : std_logic := '0';
    variable yoffset : integer := 0;
  begin
    if rising_edge(pixelclock) then

      xcounter_out <= xcounter_in;
      
      screenram_busy := '0';

      -- Work out how many rows of text, and how many pixels in the remainder
      -- of a row are covered by the on screen keyboard, and push the terminal
      -- display up that many pixels.
      -- XXX Not sure why we need the fudge factor here, but we do.
      osk_rasters_used <= last_y_used - osk_ystart - 61;
      if osk_rasters_used(11)='0' and osk_ystart(11)='0' and visual_keyboard_enable='1' and keyboard_at_top='0' then
        -- We have to skip a minimum of one row, else it will never advance
        skip_rows <= 1 + osk_rasters_used(8 downto 4);
        skip_bytes <= (to_integer(skip_rows)) * te_line_length;
        skip_rasters <= osk_rasters_used(3 downto 0);
      else
        -- Just do the normal skip of 1 to advance to the next row normally.
        -- Well, that's true if we are in PAL, and have enough raster lines.
        -- If we are in NTSC, then we have to trim two lines from the bottom.
        if pal_mode='0' then
          skip_rows <= to_unsigned(1+2,5); -- NTSC skip 2 lines
        else
          skip_rows <= to_unsigned(1,5); -- PAL show all lines
        end if;
        skip_rasters <= to_unsigned(0,4);
        skip_bytes <= te_line_length;
      end if;
      
      last_letterbox <= lcd_in_letterbox;

      drop_row <= (to_integer(ycounter_in)+0)/16;

      if matrix_fetch_chardata = '1' then
        if xcounter_in >= debug_x and xcounter_in < (debug_x+10) then
          report
            "x=" & integer'image(xcounter_in) & ": " &
            "Reading char data = $" & to_hstring(screenram_rdata); 
        end if;
        next_char_bits <= std_logic_vector(screenram_rdata);
      elsif matrix_fetch_glyphdata = '1' then
        next_glyph_bits <= std_logic_vector(matrix_rdata);
      else
--          report "memory read data = $" & to_hstring(matrix_rdata);
      end if;
      
      -- This module must draw the matrix rain, as well as the matrix mode text
      -- mode terminal interface.

      if xcounter_in >= debug_x and xcounter_in < (debug_x+10) then
        report
          "x=" & integer'image(xcounter_in) & ": " &
          "ycounter_in = " & integer'image(to_integer(ycounter_in))
          & ", char_ycounter = " & integer'image(to_integer(char_ycounter))
          & ", char_bit_count = " & integer'image(char_bit_count);
      end if;
      if fetch_next_char = '1' then
        -- Read screen data byte so we know which char to display
        matrix_fetch_glyphdata <= '0';
        matrix_fetch_screendata <= '1';
        matrix_fetch_chardata <= '0';
        fetch_next_char <= '0';

        screenram_addr <= to_integer(char_screen_address);
        if char_screen_address = te_cursor_address then
          next_is_cursor <= '1';
--          report "Found cursor @ "
--            & integer'image(te_cursor_x)
--            & "," & integer'image(te_cursor_y);
        else
          next_is_cursor <= '0';
        end if;
        screenram_we <= '0';
        screenram_busy := '1';
        if xcounter_in >= debug_x and xcounter_in < (debug_x+10) then
          report
            "x=" & integer'image(xcounter_in) & ": " &
            "Fetching character from address $"
            & to_hstring(char_screen_address);
        end if;
      elsif matrix_fetch_screendata = '1' then
        -- Got character at the relevant screen location, so we can now 
        -- calculate which byte of th charrom to read. High oder bits come
        -- from the character, low bits from the y-counter
        matrix_fetch_screendata <= '0';
        matrix_fetch_chardata <= '1';
        screenram_addr <= 0
                          +(to_integer(screenram_rdata)*8)
                          +to_integer(char_ycounter(3 downto 1));
        screenram_we <= '0';
        screenram_busy := '1';
        if xcounter_in >= debug_x and xcounter_in < (debug_x+10) then
          report
            "x=" & integer'image(xcounter_in) & ": " &
            "Reading char #$" & to_hstring(screenram_rdata);
        end if;
        if column_counter=3 then
          if screenram_rdata = x"3A" then
            -- Line begins with a colon, so colour columns differently to_hstring
            -- make it easier to pick out the columns.  Maybe also the rows,      
            -- too.
            colourify_data <= '1';
          else
            colourify_data <= '0';
          end if;
        end if;
      else
        if matrix_fetch_chardata = '1' then
          matrix_fetch_chardata <= '0';
          if xcounter_in >= debug_x and xcounter_in < (debug_x+10) then
            report
              "x=" & integer'image(xcounter_in) & ": " &
              "Reading next_char_bits = $"
              & to_hstring(screenram_rdata);
          end if;
        end if;
      end if;

      if monitor_char_valid = '0' then
        monitor_char_primed <= '1';
      end if;
      if terminal_emulator_fast = '1' then
        terminal_emulator_ready <= '1';
        terminal_emulator_fast <= '0';
        screenram_we <= '0';
      elsif monitor_char_valid = '1' and screenram_busy = '0'
        and monitor_char_primed = '1' then
        terminal_emulator_ready <= '0';
        monitor_char_primed <= '0';
        report "Terminal emulator processing character $"
          & to_hstring(monitor_char_in);
        case monitor_char_in is
          when x"13" =>
            -- Home
            te_cursor_y <= 0;
            te_cursor_x <= 0;
            te_cursor_address <= te_screen_start;
            terminal_emulator_fast <= '1';
          when x"07" =>
            -- Ignore bell character, instead of printing plus symbol
            invert_next_frame <= '1';
            terminal_emulator_fast <= '1';
--          when x"0e" =>
--            -- Control-N - move to header area
--            te_in_header <= '1';
--            te_cursor_y <= 0;
--            te_cursor_x <= 0;
--            te_cursor_address <= te_header_start;
--            terminal_emulator_fast <= '1';
--          when x"8e" =>
--            -- Control-SHIFT-N - exit header area
--            te_in_header <= '0';
--            te_cursor_y <= 0;
--            te_cursor_x <= 0;
--            te_cursor_address <= te_screen_start;
--            terminal_emulator_fast <= '1';
          when x"93" =>
            -- Clear home
            erase_terminal_memory <= '1';
            terminal_emulator_fast <= '0';
            if te_in_header = '0' then
              erase_address
                <= 4096 - (te_screen_height) * te_line_length;
            else
              erase_address
                <= 4096 - (te_screen_height + te_header_line_count)
                * te_line_length;
            end if;
            te_cursor_y <= 0;
            te_cursor_x <= 0;
            te_cursor_address <= te_screen_start;
          when x"0a" =>
            -- Line feed
            if te_cursor_y < te_y_max then
              te_cursor_y <= te_cursor_y + 1;
              te_cursor_address <= te_cursor_address +
                                   te_line_length;
              terminal_emulator_fast <= '1';
            else
              terminal_emulator_ready <= '0';
              scroll_terminal_up <= '1';
              erase_address
                <= 4096 - (te_y_max+1) * te_line_length;
              terminal_emulator_fast <= '0';
            end if;
          when x"0d" =>
            -- Carriage return
            te_cursor_address <= te_cursor_address - te_cursor_x;
            te_cursor_x <= 0;
            terminal_emulator_fast <= '1';
          when x"11" =>
            -- C64 cursor down (can scroll)
            if te_cursor_y < te_y_max then
              te_cursor_y <= te_cursor_y + 1;
              te_cursor_address <= te_cursor_address +
                                   te_line_length;
              terminal_emulator_fast <= '1';
            else
              terminal_emulator_ready <= '0';
              scroll_terminal_up <= '1';
              erase_address
                <= 4096 - (te_y_max+1) * te_line_length;
              terminal_emulator_fast <= '0';
            end if;            
          when x"91" =>
            -- C64 cursor up (doesn't scroll)
            if te_cursor_y > 0 then
              te_cursor_y <= te_cursor_y - 1;
              te_cursor_address <= te_cursor_address -
                                   te_line_length;
            end if;
            terminal_emulator_fast <= '1';
          when x"1d" =>
            -- C64 cursor right
            if te_cursor_x < te_x_max then
              -- stay on same line
              te_cursor_x <= te_cursor_x + 1;
              te_cursor_address <= te_cursor_address + 1;
              terminal_emulator_fast <= '1';
            else
              -- advance to next line (and possibly scroll)
              te_cursor_x <= 0;
              if te_cursor_y < te_y_max then
                -- No need to scroll yet
                te_cursor_y <= te_cursor_y + 1;
                te_cursor_address <= te_cursor_address + 1;
                terminal_emulator_fast <= '1';
              else
                -- We need to scroll
                terminal_emulator_ready <= '0';
                scroll_terminal_up <= '1';
                erase_address
                  <= 4096 - (te_y_max+1) * te_line_length;
                terminal_emulator_fast <= '0';
                te_cursor_address <= te_cursor_address - te_line_length + 1;
              end if;
            end if;
          when x"08" =>
            -- Backspace (limited to same line)
            if te_cursor_x > 0 then
              -- stay on same line
              te_cursor_x <= te_cursor_x - 1;
              te_cursor_address <= te_cursor_address - 1;
            else
              -- to end of previous line
              te_cursor_x <= te_x_max;
              if te_cursor_y > 0 then
                -- if not on first line, to go previous line
                te_cursor_address <= te_cursor_address - 1;
                te_cursor_y <= te_cursor_y - 1;
              else
              -- trying to go left from home position does
              -- nothing
              end if;    
            end if;
            terminal_emulator_fast <= '1';
          when x"9d" =>
            -- C64 cursor left
            if te_cursor_x > 0 then
              -- stay on same line
              te_cursor_x <= te_cursor_x - 1;
              te_cursor_address <= te_cursor_address - 1;
            else
              -- to end of previous line
              te_cursor_x <= te_x_max;
              if te_cursor_y > 0 then
                -- if not on first line, to go previous line
                te_cursor_address <= te_cursor_address - 1;
                te_cursor_y <= te_cursor_y - 1;
              else
              -- trying to go left from home position does
              -- nothing
              end if;
            end if;
            terminal_emulator_fast <= '1';
          when others =>
            -- Simply put character into place, and advance cursor
            -- as for cursor right
            report "te_cursor_address = "
              & integer'image(te_cursor_address)
              & ", te_cursor_x = " & integer'image(te_cursor_x)
              & ", te_cursor_y = " & integer'image(te_cursor_y)
              & ", te_screen_start = "
              & integer'image(te_screen_start);
            screenram_addr <= te_cursor_address;
            screenram_wdata <= monitor_char_in;
            -- Prevent overwriting font
            if te_cursor_address >= te_header_start
              and te_cursor_address < 4096 then 
              screenram_we <= '1';
            else
              screenram_we <= '0';
            end if;
            screenram_busy := '1';
            if te_cursor_x < te_x_max then
              -- stay on same line
              te_cursor_x <= te_cursor_x + 1;
              report "increment te_cursor_address, because cursor_x < x_max";
              te_cursor_address <= te_cursor_address + 1;
              terminal_emulator_fast <= '1';
            else
              -- advance to next line (and possibly scroll)
              te_cursor_x <= 0;
              if te_cursor_y < te_y_max then
                te_cursor_y <= te_cursor_y + 1;
                report "increment te_cursor_address, because not yet at bottom of screen "
                  & "(te_cursor_y=" & integer'image(te_cursor_y)
                  & ", te_y_max=" & integer'image(te_y_max) & ")";
                te_cursor_address <= te_cursor_address + 1;
                terminal_emulator_fast <= '1';
              else
                terminal_emulator_ready <= '0';
                scroll_terminal_up <= '1';
                erase_address <= te_screen_start;
                terminal_emulator_fast <= '0';
                te_cursor_address <= te_cursor_address - te_line_length + 1;
              end if;
            end if;
        end case;
      end if;                

      
      if screenram_busy = '1' then
      -- Terminal emulator display is using memory to read something
      -- so don't try to do anything
      else
        -- Terminal emulator display generator isn't using the memory --
        -- so scroll or erase if required
        if erase_terminal_memory = '1' then
          if erase_address /= 4096 then
            erase_address <= erase_address + 1;
            screenram_addr <= erase_address;
            screenram_we <= '1';
            screenram_wdata <= x"20";
          else
            screenram_we <= '0';
            erase_terminal_memory <= '0';
            terminal_emulator_ready <= '1';
          end if;
        elsif scroll_terminal_up = '1' then
          -- Copy screen memory up one row, and erase bottom
          -- row.
          -- Only scrolling during vertical flyback
          -- to avoid visual artifacts. This could limit scroll
          -- speed to only a couple of lines per frame. Not ideal.
          -- so we won't restrict it for now.
          if erase_address /= 4096 - te_line_length then
            if scroll_write_ready = '0' and scroll_read = '0' then
              -- Read from line below
--              report "Reading from "
--                & integer'image(erase_address + te_line_length)
--                & " for scrolling.";
              screenram_addr <= erase_address + te_line_length;
              screenram_we <= '0';
              scroll_read <= '1';
            elsif scroll_write_ready = '1' then
              -- Write to current row
--              report "scrolling @ address "
--                & integer'image(erase_address)
--                & " writing $"
--                & to_hstring(scroll_byte);
              erase_address <= erase_address + 1;
              screenram_addr <= erase_address;
              screenram_we <= '1';
              screenram_wdata <= scroll_byte;
              scroll_read <= '0';
              scroll_write_ready <= '0';
            end if;
          else
            -- Use screen clear logic to create blank new line
            erase_terminal_memory <= '1';              
            scroll_terminal_up <= '0';
          end if;
        end if;
      end if;

      -- Delay display by one clock to re-synchronise with the VIC-IV video output
      last_xcounter_t2 <= last_xcounter_t1;
      last_xcounter_t1 <= last_xcounter_in;
      last_xcounter_in <= xcounter_in;
      
      last_external_frame_x_zero <= external_frame_x_zero;
      last_external_frame_y_zero <= external_frame_y_zero;

      if true then
        -- Text terminal display
        -- We need to read the current char cell to know which
        -- char to display, and then also fetch the row of char
        -- data.  A complication is that we have to deal with
        -- contention on the BRAM interface, so we ideally need to
        -- sequence the requests a little carefully.
        if external_frame_x_zero='1' and last_external_frame_x_zero = '0' and lcd_in_letterbox='1' then
          char_bit_count <= 0;
          fetch_next_char <= '1';
          column_counter <= 0;
          column_visible <= '0';
          -- reset fetch address to start of line, unless
          -- we are advancing to next line
          -- XXX doesn't yet support double-high chars
          if char_ycounter /= 15 then
            char_screen_address <= line_screen_address;
            char_ycounter <= char_ycounter + 1;
          else
            if row_counter = (te_header_line_count - 1 ) then
              -- We are now leaving the header.
              -- If we have the visual keyboard on, we need to shift things up.
              -- Basically we need to add one row for every 16 pixels above
              -- the cut-off at letterbox + te_header_line_count + te_screen_height
              row_counter <= row_counter + to_integer(skip_rows);
              char_ycounter(3 downto 0) <= skip_rasters;
              char_ycounter(11 downto 4) <= (others => '0');
              char_screen_address <= line_screen_address + skip_bytes;
              line_screen_address <= line_screen_address + skip_bytes;
            else
              -- Normal row advance
              char_ycounter <= to_unsigned(0,12);
              row_counter <= row_counter + 1;
              char_screen_address <= line_screen_address + te_line_length;
              line_screen_address <= line_screen_address + te_line_length;
            end if;
          end if;
        elsif char_bit_count = 0 then
          -- Request next character
          if xcounter_in >= debug_x and xcounter_in < (debug_x+10) then
            report
              "x=" & integer'image(xcounter_in) & ": " &
              "char_bits becomes $" & to_hstring(next_char_bits);
          end if;
          char_bits <= std_logic_vector(next_char_bits);
          is_cursor <= next_is_cursor;
          -- The offset of 3 is to position the matrix mode overlay more
          -- centrally on the screen.
          if column_counter > 2 then
            char_screen_address <= char_screen_address + 1;
          end if;
          if colourify_data='1' then
            case column_counter is
              when 13 | 14 | 17 | 18 | 21 | 22 | 25 | 26 | 29 | 30 | 33 | 34 | 37 | 38 | 41 | 42 =>
                alternate_colour <= '1';
              when others =>
                alternate_colour <= '0';
            end case;
          end if;
          if column_counter=3 then
            column_visible <= '1';
          elsif column_counter=11 then
            if next_char_bits(0)='1' then
              alternate_row <= '1';
            else
              alternate_row <= '0';
            end if;
          elsif column_counter = (3 + te_line_length) then
            column_visible <= '0';
          end if;
          fetch_next_char <= '1';
          char_bit_count <= 15;
          column_counter <= column_counter + 1;
        else
          -- rotate bits for terminal chargen every 2 640H pixels
          -- Delayed by 2 cycles to match pixel edge with real pixel edge.
          -- (Actually we need to tweak the delay for PAL and NTSC differently
          -- still for some reason?)
          if ((last_xcounter_t1 /= last_xcounter_t2) and (pal_mode='0'))
            or ((last_xcounter_t1 /= last_xcounter_in) and (pal_mode='1'))
          then
            char_bit_stretch <= not char_bit_stretch;
            if char_bit_stretch = '1' and char_bit_count /= 1 then
              char_bits(7 downto 1) <= char_bits(6 downto 0);
              char_bits(0) <= char_bits(7);
            end if;
            if char_bit_count /= 0 then
              char_bit_count <= char_bit_count - 1;
            end if;
          end if;
        end if; 

        -- Request next glyph to be read
        -- Matrix glyphs are at $0E00-$0EFF
        -- Digits are at $30 x $08 = $180-$1DF
        -- We want circa 1/10th digits, and 9/10s matrix glyphs
        -- Digits have 10, which is not a power of two, and so is a bit
        -- annoying.  We can break it down into 8 + 2 digits, however,
        -- where the 8 digits should get picked 4x more often than the other
        -- 2.
        if fetch_next_char = '1' then
        -- handled elsewhere
        elsif matrix_fetch_screendata = '1' then
          matrix_fetch_address(11) <= '0';
          -- Read byte of matrix rain glyph
          matrix_fetch_glyphdata <= '1';
          
          if next_glyph(9 downto 7) = "001" then
            -- Digits 0 - 7
            xflip <= '1';
            matrix_fetch_address(11 downto 6) <= "000110";
            matrix_fetch_address(5 downto 3) <= next_glyph(2 downto 0);
          elsif next_glyph(9 downto 5) = "00001" then
            -- Digits 8 - 9 @ char $38-$39 = 
            xflip <= '1';
            matrix_fetch_address(11 downto 5) <= "0001110";
            matrix_fetch_address(4 downto 3) <= next_glyph(1 downto 0);
          else
            -- Matrix glyph
            xflip <= '0';
            matrix_fetch_address(11 downto 8) <= x"E";
            matrix_fetch_address(7 downto 3) <= next_glyph(4 downto 0);
          end if;
          -- Position within glyph (matrix rain)
          yoffset := (to_integer(ycounter_in(3 downto 1))-1) / 2;
          if yoffset < 0 then
            yoffset := yoffset + 8;
          end if;
--          yoffset := 1;
          matrix_fetch_address(2 downto 0)
            <= to_unsigned(yoffset,3);
        end if;
        -- Copy byte read for scrolling if ready.
        -- This is because scrolling happens around the memory accesses
        -- needed to draw the display.
        if scroll_read = '1' then
--          report "Storing scroll byte $" & to_hstring(screenram_rdata);
          scroll_byte <= screenram_rdata;
          scroll_write_ready <= '1';
          scroll_read <= '0';
        end if;

        -- Matrix Rain display
        drop_start_plus_row <= drop_start_plus_row_drive;
        drop_start_plus_end_plus_row <= drop_start_plus_end_plus_row_drive;
        drop_start <= drop_start_drive;
        drop_end <= drop_end_drive;
        drop_distance_to_start <= drop_distance_to_start_drive;
        drop_distance_to_end <= drop_distance_to_end_drive;
        drop_distance_to_start_drive <= drop_distance_to_start_drive2(7 downto 0);
        drop_distance_to_end_drive <= drop_distance_to_end_drive2(7 downto 0);
        glyph_pixel <= glyph_bits(0);
        
        if external_frame_x_zero = '1' then
          glyph_bit_count <= 0;
        elsif glyph_bit_count < 2 then
          -- Request next glyph

          -- Copy out pixels from last glyph read
          if xflip='0' then
            -- horizontal flip
            for i in 0 to 7 loop
              glyph_bits(i) <= std_logic(matrix_rdata(7-i));
            end loop;
--            glyph_bits(0) <= std_logic(matrix_rdata(0));
          else
            glyph_bits <= std_logic_vector(next_glyph_bits);
          end if;

          -- Update start/end of drop
          drop_start_drive <= to_integer(next_start(4 downto 0));
          drop_end_drive <= to_integer(next_end(4 downto 0));
          drop_distance_to_end_drive2 <= to_unsigned(257 + drop_row - (frame_number - to_integer(next_start(4 downto 0)))
                                                     - to_integer(next_end(4 downto 0)),9);  
          drop_distance_to_start_drive2 <= to_unsigned(257 + drop_row - (frame_number - to_integer(next_start(4 downto 0))),9);
          
          -- Work out where drops stop and start
          -- Add 2, so that a start of 0 doesn't appear until 2nd
          -- frame, so that there is no drip heads hanging around
          -- at the top of frame after rain has retracted (it never
          -- actually disappears, just retracts, as the rain actually
          -- forms a transition between normal and matrix mode displays).
          drop_start_plus_row_drive <= to_integer(next_start(4 downto 0)) + drop_row + 2;
          drop_start_plus_end_plus_row_drive
            <= to_integer(next_start(4 downto 0)) + to_integer(next_end(4 downto 0)) + drop_row + 2;
          
--          report "new drop start,end = "
--            & integer'image(to_integer(next_start(4 downto 0))) & ","
--            & integer'image(to_integer(next_end(4 downto 0)));
          glyph_bit_count <= 16;
        else
          -- rotate bits for rain chargen
          if (xcounter_in mod 2) = 0 and char_bit_count /= 1
            and xcounter_in /= last_xcounter_in then
            glyph_bits(6 downto 0) <= glyph_bits(7 downto 1);
            glyph_bits(7) <= glyph_bits(0);
          end if;
          if xcounter_in /= last_xcounter_in 
            and xcounter_in /= last_xcounter_in then
            glyph_bit_count <= glyph_bit_count - 1;
          end if;
        end if;
      end if;
      
      -- Now based on whether we are above, in or below a rain drop,
      -- decide what to display.
      if frame_number < drop_start_plus_row then
        feed <= Normal;
      elsif frame_number > drop_start_plus_end_plus_row then
        feed <= Matrix;
      else
        feed <= Rain;
      end if;

      -- Now that we know what we want to display, actually display it.
      if xcounter_in >= debug_x and xcounter_in < (debug_x+10) then
        report
          "x=" & integer'image(xcounter_in) & ": " &
          "source = " & feed_t'image(feed);
      end if;
      case feed is
        when Normal =>
          -- Normal display, so show pixels from input video stream
          vgared_out <= vgared_in;
          vgagreen_out <= vgagreen_in;
          vgablue_out <= vgablue_in;
        when Matrix =>
          -- Matrix mode, so display the matrix mode text mode that we
          -- generate here.
          if xcounter_in >= debug_x and xcounter_in < (debug_x+10) then
            report
              "x=" & integer'image(xcounter_in) & ": " &
              "  pixel_out = " & std_logic'image(char_bits(7))
              & ", char_bits=%" & to_string(char_bits);
          end if;
          if last_letterbox = '0' then
            vgared_out <= x"00";
            vgagreen_out <= x"00";
            if external_frame_x_zero='1' then
              vgablue_out <= x"FF";
            else
              vgablue_out <= x"00";
            end if;
          elsif (row_counter = 3 or row_counter = 4) then
            if secure_mode_flag='0' or char_bits(0)='0' or column_visible='0' or te_blink_state='1' then
              -- Hide the secure compartment instructions when not in secure mode
              -- (and otherwise show as solid orange slab when in secure mode
              -- for the off-phase blink.)
              if secure_mode_flag = '0' then
                vgared_out <= (others => '0');
                vgagreen_out(6 downto 0) <= (others => '0');
                vgagreen_out(7) <= '0';
              else
                vgared_out <= (others => te_blink_state xor (char_bits(0) and column_visible));
                vgagreen_out(6 downto 0) <= (others => te_blink_state xor (char_bits(0) and column_visible));
                vgagreen_out(7) <= te_blink_state xor (char_bits(0) and column_visible);
              end if;
              vgablue_out <= x"00";
            else
              -- ACCEPT/REJECT instructions are highlight and blinking (out of
              -- phase with the cursor).
              vgared_out <= x"FF";
              vgagreen_out <= x"7F";
              vgablue_out <= x"00";
            end if;            
          elsif (row_counter >= (te_header_line_count + te_screen_height)) then
            -- Beyond the end of display, so don't display text of overlay.
            vgared_out(7 downto 6) <= "00";
            vgagreen_out(7 downto 6) <= "00";
            vgablue_out(7 downto 6) <= "00";
            vgared_out(5 downto 0) <= vgared_in(7 downto 2);
            vgagreen_out(5 downto 0) <= vgagreen_in(7 downto 2);
            vgablue_out(5 downto 0) <= vgablue_in(7 downto 2);

            -- Reset fetching to start of area, ready for next frame
            line_screen_address <= to_unsigned(te_header_start,12);
            char_screen_address <= to_unsigned(te_header_start,12);
            char_ycounter <= to_unsigned(0,12);

          elsif row_counter >= te_header_line_count then
            -- In normal text area
            if (char_bits(0) = '1') and column_visible='1' then
              if is_cursor='1' and te_blink_state='1' then
                -- Display visual beep by making background of monitor
                -- terminal area flash red.
                vgared_out(7) <= invert_frame;
                vgared_out(6) <= invert_frame;
                vgagreen_out(7 downto 6) <= "00";
                vgablue_out(7 downto 6) <= "00";
                vgared_out(5 downto 0) <= vgared_in(7 downto 2);
                vgagreen_out(5 downto 0) <= vgagreen_in(7 downto 2);
                vgablue_out(5 downto 0) <= vgablue_in(7 downto 2);
              else
                if alternate_colour='1' then
                  vgared_out(7 downto 6) <= alternate_row & alternate_row;
                  vgagreen_out(7 downto 6) <= "11";
                  vgablue_out(7 downto 6) <= "11";
                else
                  vgared_out(7 downto 6) <= "00";
                  vgagreen_out(7 downto 6) <= "11";
                  vgablue_out(7 downto 6) <= "00";
                end if;
                vgared_out(5 downto 0) <= vgared_in(7 downto 2);
                vgagreen_out(5 downto 0) <= vgagreen_in(7 downto 2);
                vgablue_out(5 downto 0) <= vgablue_in(7 downto 2);
              end if;
            else
              if is_cursor='1' and te_blink_state='1' and column_visible='1' then
                if secure_mode_flag = '0' then                
                  vgared_out <= "11111111";
                  vgagreen_out <= "11111111";
                  vgablue_out <= "00000000";
                else
                  vgared_out <= "11111111";
                  vgagreen_out <= "01111111";
                  vgablue_out <= "00000000";
                end if;
              else
                vgared_out(7) <= '0';
                vgagreen_out(7) <= '0';
                vgablue_out(7) <= '0';
                vgared_out(6 downto 0) <= vgared_in(7 downto 1);
                vgagreen_out(6 downto 0) <= vgagreen_in(7 downto 1);
                vgablue_out(6 downto 0) <= vgablue_in(7 downto 1);
              end if;
            end if;
          else
            -- In header of matrix mode
            -- Note that cursor is not visible in header area
            if char_bits(0) = '0' or (column_visible='0') then
              vgared_out <= (others => '0');
              vgagreen_out <= (others => '0');
              vgablue_out <= (others => '0');
            else
              -- Header of matrix mode terminal has background highlight
              vgared_out <= "10111111";
              vgagreen_out <= "11111111";
              vgablue_out <= "10111111";
            end if;
          end if;
        when Rain =>
          -- Matrix rain drop, so display a random character in green on
          -- black.
          if glyph_pixel='1' then
            -- XXX make head of column whiter
            -- XXX make brightness decrease with position
--            report "distance_to_start = $" & to_hstring(drop_distance_to_start);
            case drop_distance_to_start(6 downto 0) is
              when "1111111" =>
                vgared_out <= x"FF";
                vgagreen_out <= x"FF";
                vgablue_out <= x"FF";
              when "1111110" =>
                if secure_mode_flag = '0' then
                  vgared_out <= x"C0";
                  vgagreen_out <= x"F0";
                  vgablue_out <= x"C0";
                else
                  vgared_out <= x"F0";
                  vgagreen_out <= x"F0";
                  vgablue_out <= x"C0";
                end if;
              when others =>
                if secure_mode_flag = '0' then
                  vgared_out <= (others => '0');
                  vgagreen_out(7 downto 2) <= drop_distance_to_end(5 downto 0);
                  vgagreen_out(1 downto 0) <= (others => '1');
                  vgablue_out <= (others => '0');
                else
                  vgared_out <= (others => '1');
                  vgagreen_out(7 downto 2) <= drop_distance_to_end(5 downto 0);
                  vgagreen_out(1 downto 0) <= (others => '1');
                  vgablue_out <= (others => '0');
                end if;
            end case;
--            vgared_out <= (others => '1');
          else
            vgared_out <= (others => '0');
            vgagreen_out <= (others => '0');
            vgablue_out <= (others => '0');
          end if;
      end case;
      
      lfsr_reset(3 downto 0) <= "0000";
      if external_frame_x_zero='1' then
        -- Horizontal fly-back
        -- Reset LFSRs that generate the start/end values
        if seed(15 downto 0) /= "00000000000000" then
          lfsr_seed0(15 downto 2) <= seed(15 downto 2);
        else
          lfsr_seed0(15 downto 2) <= (others => '1');
        end if;
        lfsr_seed1(15 downto 2) <= seed(15 downto 2);
        lfsr_seed0(1 downto 0) <= "00";
        lfsr_seed1(1 downto 0) <= "01";
        lfsr_seed2(15 downto 2) <= to_unsigned(128+to_integer(seed(15 downto 2))+drop_row-frame_number,14);
        lfsr_seed3(15 downto 2) <= to_unsigned(128+to_integer(seed(15 downto 2))+drop_row-frame_number,14);
        lfsr_reset(3 downto 0) <= "1111";
        lfsr_advance_counter <= 15;
        lfsr_advance(1 downto 0) <= "11";        
        lfsr_advance(3 downto 0) <= "1111";        
      end if;
      if last_letterbox = '1' and lcd_in_letterbox = '0' then
        last_y_used <= ycounter_in;
      end if;
      if external_frame_y_zero = '0' and last_external_frame_y_zero = '1' then
        -- Vertical flyback = start of next frame
        report "Resetting at end of flyback";

        invert_frame <= invert_next_frame;
        invert_next_frame <= '0';
        
        if te_blink_counter < 25 then
          te_blink_counter <= te_blink_counter + 1;
        else
          te_blink_counter <= 0;
          te_blink_state <= not te_blink_state;
        end if;
        
        line_screen_address <= to_unsigned(te_header_start,12);
        char_screen_address <= to_unsigned(te_header_start,12);
        char_ycounter <= to_unsigned(0,12);
        row_counter <= 0;
        fetch_next_char <= '1';
        if matrix_mode_enable = '1' and (frame_number + 1) < 127 then
          -- Stop frame counter once transition to matrix display
          -- is complete, so that reverse transition begins
          -- immediately
          frame_number <= frame_number + 2;
          report "frame_number incrementing to "
            & integer'image(frame_number + 1);
        elsif matrix_mode_enable = '0' and frame_number > 0 then
          frame_number <= frame_number - 2;
          report "frame_number decrementing to "
            & integer'image(frame_number - 1);
        else
          report "frame_number stays "
            & integer'image(frame_number);            
        end if;
        lfsr_advance_counter <= 0;
      end if;
      if lfsr_advance_counter /= 0 then
        lfsr_advance_counter <= lfsr_advance_counter - 1;
      elsif external_frame_x_zero = '1' then
        lfsr_advance(3 downto 0) <= "0000";
      else
        -- Collect bits to form start and end of rain and glyph
        -- to show.  We collect 8 bits of data, since it is simpler,
        -- but we use only a subset of the collected bits.
        next_glyph(15 downto 2) <= next_glyph(13 downto 0);
        next_glyph(1) <= lfsr_out(3);
        next_glyph(0) <= lfsr_out(2);
        next_start(7 downto 1) <= next_start(6 downto 0);
        next_start(0) <= lfsr_out(0);
        next_end(7 downto 1) <= next_end(6 downto 0);
        next_end(0) <= lfsr_out(1);
        lfsr_advance(3 downto 0) <= "1111";
      end if;
    end if;
  end process;

end rtl;
