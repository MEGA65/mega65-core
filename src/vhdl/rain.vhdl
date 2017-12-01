library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;

entity matrix_rain_compositor is
  
  port (
    -- CPU clock (typically 50MHz)
    clk : in std_logic; 
    
    -- Cursor key communication for moving 
    display_shift_in : in std_logic_vector(2 downto 0);
    shift_ready_in : in std_logic;
    shift_ack_out : out std_logic;

    -- Whether matrix mode should be displayed or not
    matrix_mode_enable : in std_logic;

    -- Green matrix mode or lava secure mode
    secure_mode_flag : in std_logic;
    
    -- Matrix mode resolution selection:
    -- For 800x480, these are:
    -- 00 = 80x50
    -- 01 = 80x25
    -- 10 = 40x25
    mm_displayMode_in : in unsigned(1 downto 0);

    -- Character output produced by serial monitor
    monitor_char_in : in unsigned(7 downto 0);
    monitor_char_valid : in std_logic;
    terminal_emulator_ready : out std_logic := '1';
    
    -- Pixel clock and scale factors according to video mode
    pixelclock  : in  std_logic;
    pixel_y_scale_200 : in unsigned(3 downto 0);
    pixel_y_scale_400 : in unsigned(3 downto 0);
    -- Physical raster line number
    ycounter_in : in unsigned(11 downto 0);
    ycounter_out : out unsigned(11 downto 0);
    -- Scaled horizontal position (for virtual 640H
    -- operation, regardless of physical video mode)
    pixel_x_640 : in integer;
    pixel_x_640_out : out integer;
    
    -- Remote memory access interface to visual keyboard for
    -- character set.
    matrix_fetch_address : out unsigned(11 downto 0) := x"000";
    matrix_rdata : in unsigned(7 downto 0);
    
    -- Seed for matrix rain randomisation
    seed   : in  unsigned(15 downto 0);

    -- Video feed to be composited over
    hsync_in : in std_logic;
    vsync_in : in std_logic;
    vgared_in : in unsigned(7 downto 0);
    vgagreen_in : in unsigned(7 downto 0);
    vgablue_in : in unsigned(7 downto 0);

    -- Composited output video feed
    hsync_out : out std_logic;
    vsync_out : out std_logic;
    vgared_out : out unsigned(7 downto 0);
    vgagreen_out : out unsigned(7 downto 0);
    vgablue_out : out unsigned(7 downto 0)    
    
    );

end matrix_rain_compositor;

architecture rtl of matrix_rain_compositor is
  constant debug_x : integer := 9999 + 56;

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
  -- te_screen_height * te_line_length must be <2048
  -- Screen RAM sits at end of 4KB BRAM.
  -- We have one extra header line that can be set using only
  -- special writing sequences.  It persists 
  constant te_screen_height : integer := 40;
  constant te_y_max : integer := te_screen_height - 1;
  constant te_line_length : integer := 50;
  constant te_x_max : integer := te_line_length - 1;
  constant te_screen_start : integer
    := 4096 - te_screen_height * te_line_length;
  constant te_header_start : integer
    := te_screen_start - te_line_length;
  -- Cursor starts at top of normal screen
  signal te_cursor_address : integer := te_screen_start;

  signal erase_terminal_memory : std_logic := '0';
  signal scroll_terminal_up : std_logic := '0';
  signal erase_address : integer := 0;
  signal scroll_phase : std_logic := '0';
  
  signal state : unsigned(15 downto 0) := (others => '1');
  type feed_t is (Normal,Rain,Matrix);
  signal feed : feed_t := Normal;
  signal frame_number : integer range 0 to 127 := 100;
  signal lfsr_advance_counter : integer range 0 to 31 := 0;
  signal last_hsync : std_logic := '1';
  signal last_vsync : std_logic := '1';
  signal last_pixel_x_640 : integer := 0;
  
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
  
  signal vgared_matrix : unsigned(7 downto 0) := x"00";
  signal vgagreen_matrix : unsigned(7 downto 0) := x"00";
  signal vgablue_matrix : unsigned(7 downto 0) := x"00";

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

  signal glyph_bit_count : integer range 0 to 8 := 0;
  signal glyph_bits : std_logic_vector(7 downto 0) := x"FF";
  signal next_glyph_bits : std_logic_vector(7 downto 0) := x"FF";
  signal glyph_pixel : std_logic := '0';
  signal xflip : std_logic := '0';

  signal char_bit_count : integer range 0 to 8 := 0;
  signal char_bits : std_logic_vector(7 downto 0) := x"FF";
  signal next_char_bits : std_logic_vector(7 downto 0) := x"FF";
  signal matrix_fetch_screendata : std_logic := '0';
  signal matrix_fetch_chardata : std_logic := '0';
  signal matrix_fetch_glyphdata : std_logic := '0';

  signal fetch_next_char : std_logic := '0';
  signal char_screen_address : unsigned(11 downto 0) := to_unsigned(1,12);
  signal line_screen_address : unsigned(11 downto 0) := to_unsigned(1,12);
  signal char_ycounter : unsigned(11 downto 0) := to_unsigned(0,12);
  
begin  -- rtl

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
  begin
    if rising_edge(pixelclock) then
      hsync_out <= hsync_in;
      vsync_out <= vsync_in;
      last_hsync <= hsync_in;
      last_vsync <= vsync_in;

      drop_row <= to_integer(ycounter_in(10 downto 3));

      if matrix_fetch_chardata = '1' then
        if pixel_x_640 >= debug_x and pixel_x_640 < (debug_x+10) then
          report
            "x=" & integer'image(pixel_x_640) & ": " &
            "Reading char data = $" & to_hstring(screenram_rdata); 
        end if;
        next_char_bits <= std_logic_vector(screenram_rdata);
      elsif matrix_fetch_glyphdata = '1' then
        next_glyph_bits <= std_logic_vector(matrix_rdata);
--          report "next glyph bits = $" & to_hstring(matrix_rdata);
      else
--          report "memory read data = $" & to_hstring(matrix_rdata);
      end if;
      
      -- This module must draw the matrix rain, as well as the matrix mode text
      -- mode terminal interface.

      if pixel_x_640 >= debug_x and pixel_x_640 < (debug_x+10) then
        report
          "x=" & integer'image(pixel_x_640) & ": " &
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

        -- XXX For now, display same char, over and over.
        screenram_addr <= 0 + to_integer(char_screen_address);
        if pixel_x_640 >= debug_x and pixel_x_640 < (debug_x+10) then
          report
            "x=" & integer'image(pixel_x_640) & ": " &
            "Fetching character from address $"
            & to_hstring(char_screen_address);
        end if;
      elsif matrix_fetch_screendata = '1' then
        -- Got character at the relevant screen location, so we can now 
        -- calculate which byte of th charrom to read. High oder bits come
        -- from the character, low bits from the y-counter
        matrix_fetch_screendata <= '0';
        matrix_fetch_chardata <= '1';
        screenram_addr <= 2048
                          +(to_integer(screenram_rdata)*8)
                          +to_integer(char_ycounter(2 downto 0));
        if pixel_x_640 >= debug_x and pixel_x_640 < (debug_x+10) then
          report
            "x=" & integer'image(pixel_x_640) & ": " &
            "Reading char #$" & to_hstring(screenram_rdata);
        end if;
      else
        if matrix_fetch_chardata = '1' then
          matrix_fetch_chardata <= '0';
          if pixel_x_640 >= debug_x and pixel_x_640 < (debug_x+10) then
            report
              "x=" & integer'image(pixel_x_640) & ": " &
              "Reading next_char_bits = $"
              & to_hstring(screenram_rdata);
          end if;
        end if;
        if monitor_char_valid = '1' then
          report "Terminal emulator processing character $"
            & to_hstring(monitor_char_in);
          case monitor_char_in is
            when x"13" =>
              -- Home
              te_cursor_y <= 0;
              te_cursor_x <= 0;
              te_cursor_address <= te_screen_start;
            when x"93" =>
              -- Clear home
              terminal_emulator_ready <= '0';
              erase_terminal_memory <= '1';
              erase_address
                <= 4096 - (te_y_max+1) * te_line_length;
              te_cursor_y <= 0;
              te_cursor_x <= 0;
              te_cursor_address <= te_screen_start;
            when x"0a" =>
              -- Line feed
              if te_cursor_y < te_y_max then
                te_cursor_y <= te_cursor_y + 1;
                te_cursor_address <= te_cursor_address +
                                     te_line_length;
              else
                terminal_emulator_ready <= '0';
                scroll_terminal_up <= '1';
                erase_address
                  <= 4096 - (te_y_max+1) * te_line_length;
              end if;
            when x"0d" =>
              -- Carriage return
              te_cursor_address <= te_cursor_address - te_cursor_x;
              te_cursor_x <= 0;
            when x"11" =>
              -- C64 cursor down (can scroll)
              if te_cursor_y < te_y_max then
                te_cursor_y <= te_cursor_y + 1;
                te_cursor_address <= te_cursor_address +
                                     te_line_length;
              else
                terminal_emulator_ready <= '0';
                scroll_terminal_up <= '1';
                erase_address
                  <= 4096 - (te_y_max+1) * te_line_length;
              end if;            
            when x"91" =>
              -- C64 cursor up (doesn't scroll)
              if te_cursor_y > 0 then
                te_cursor_y <= te_cursor_y - 1;
                te_cursor_address <= te_cursor_address -
                                     te_line_length;
              end if;
            when x"1d" =>
              -- C64 cursor right
              if te_cursor_x < te_x_max then
                -- stay on same line
                te_cursor_x <= te_cursor_x + 1;
                te_cursor_address <= te_cursor_address + 1;
              else
                -- advance to next line (and possibly scroll)
                te_cursor_x <= 0;
                if te_cursor_y < te_y_max then
                  te_cursor_y <= te_cursor_y + 1;
                  te_cursor_address <= te_cursor_address + 1;
                else
                  terminal_emulator_ready <= '0';
                  scroll_terminal_up <= '1';
                  erase_address
                    <= 4096 - (te_y_max+1) * te_line_length;
                end if;
              end if;
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
              if te_cursor_x < te_x_max then
                -- stay on same line
                te_cursor_x <= te_cursor_x + 1;
                te_cursor_address <= te_cursor_address + 1;
              else
                -- advance to next line (and possibly scroll)
                te_cursor_x <= 0;
                if te_cursor_y < te_y_max then
                  te_cursor_y <= te_cursor_y + 1;
                  te_cursor_address <= te_cursor_address + 1;
                else
                  terminal_emulator_ready <= '0';
                  scroll_terminal_up <= '1';
                  erase_address
                    <= 4096 - (te_y_max+1) * te_line_length;
                end if;
              end if;
          end case;
        end if;                
      end if;
      if pixel_x_640 /= last_pixel_x_640 then
        -- Text terminal display
        -- We need to read the current char cell to know which
        -- char to display, and then also fetch the row of char
        -- data.  A complication is that we have to deal with
        -- contention on the BRAM interface, so we ideally need to
        -- sequence the requests a little carefully.
        if hsync_in = '1' then
          char_bit_count <= 0;
          if last_hsync = '0' then
            fetch_next_char <= '1';
          end if;
          -- reset fetch address to start of line, unless
          -- we are advancing to next line
          -- XXX doesn't yet support double-high chars
          if last_hsync = '0' then
            if char_ycounter /= 7 then
              char_screen_address <= line_screen_address;
              char_ycounter <= char_ycounter + 1;
            else
              char_screen_address <= line_screen_address + te_line_length;
              line_screen_address <= line_screen_address + te_line_length;
              char_ycounter <= to_unsigned(0,12);
            end if;
          end if;
        elsif char_bit_count = 0 then
          -- Request next character
          if pixel_x_640 >= debug_x and pixel_x_640 < (debug_x+10) then
            report
              "x=" & integer'image(pixel_x_640) & ": " &
              "char_bits becomes $" & to_hstring(next_char_bits);
          end if;
          char_bits <= std_logic_vector(next_char_bits);
          char_screen_address <= char_screen_address + 1;
          fetch_next_char <= '1';
          char_bit_count <= 7;
        else
          -- rotate bits for terminal chargen
          char_bits(7 downto 1) <= char_bits(6 downto 0);
          char_bits(0) <= char_bits(7);
          char_bit_count <= char_bit_count - 1;
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
          -- Read byte of character to display
          matrix_fetch_glyphdata <= '0';
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
          -- Position within glyph
          matrix_fetch_address(2 downto 0) <= ycounter_in(2 downto 0);
        else
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
              if scroll_phase = '0' then
                -- Read from line below
                screenram_addr <= erase_address + te_line_length;
                screenram_we <= '0';
                scroll_phase <= '1';
              else
                -- Write to current row
                erase_address <= erase_address + 1;
                screenram_addr <= erase_address;
                screenram_we <= '1';
                screenram_wdata <= screenram_rdata;
                scroll_phase <= '0';
              end if;
              screenram_addr <= erase_address;
              screenram_we <= '1';
              screenram_wdata <= x"20";
            else
              -- Use screen clear logic to create blank new line
              erase_terminal_memory <= '1';              
              scroll_terminal_up <= '0';
            end if;
          end if;
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
        glyph_pixel <= glyph_bits(7);
        
        if hsync_in = '1' then
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
          glyph_bit_count <= 8;
        else
          -- rotate bits for rain chargen
          glyph_bits(6 downto 0) <= glyph_bits(7 downto 1);
          glyph_bits(7) <= glyph_bits(0);

          glyph_bit_count <= glyph_bit_count - 1;
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
      if pixel_x_640 >= debug_x and pixel_x_640 < (debug_x+10) then
        report
          "x=" & integer'image(pixel_x_640) & ": " &
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
--          vgared_out <= vgared_matrix;
--          vgagreen_out <= vgagreen_matrix;
--          vgablue_out <= vgablue_matrix;
          if pixel_x_640 >= debug_x and pixel_x_640 < (debug_x+10) then
            report
              "x=" & integer'image(pixel_x_640) & ": " &
              "  pixel_out = " & std_logic'image(char_bits(7))
              & ", char_bits=%" & to_string(char_bits);
          end if;
          if char_bits(7) = '1' then
            vgared_out <= (others => '0');
            vgagreen_out <= (others => '1');
            vgablue_out <= (others => '0');
          else
            vgared_out <= (others => '0');
            vgagreen_out <= (others => '0');
            vgablue_out <= (others => '0');
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
      if last_hsync = '0' and hsync_in = '1' then
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
      if last_vsync = '1' and vsync_in = '0' then
        -- Vertical flyback = start of next frame
        report "Resetting at end of flyback";
        line_screen_address <= to_unsigned(0,12);
        char_screen_address <= to_unsigned(0,12);
        char_ycounter <= to_unsigned(0,12);
        fetch_next_char <= '1';
        if matrix_mode_enable = '1' and frame_number < 127 then
          frame_number <= frame_number + 1;
          report "frame_number incrementing to "
            & integer'image(frame_number + 1);
        elsif matrix_mode_enable = '0' and frame_number > 0 then
          frame_number <= frame_number - 1;
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
      elsif hsync_in = '1' then
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
