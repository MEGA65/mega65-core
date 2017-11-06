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
    
    -- Matrix mode resolution selection:
    -- For 800x480, these are:
    -- 00 = 80x50
    -- 01 = 80x25
    -- 10 = 40x25
    mm_displayMode_in : in unsigned(1 downto 0);

    -- Character input from virtualised keyboard
    monitor_char_in : in unsigned(7 downto 0);
    monitor_char_valid : in std_logic;
    terminal_emulator_ready : out std_logic;
    
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
  signal state : unsigned(15 downto 0) := (others => '1');
  type feed_t is (Normal,Rain,Matrix);
  signal feed : feed_t := Normal;
  signal frame_number : integer range 0 to 127 := 0;
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
  signal drop_distance_to_end_drive2 : unsigned(7 downto 0) := x"00";
  signal drop_distance_to_start_drive2 : unsigned(7 downto 0) := x"00";
  
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
  signal glyph_pixel : std_logic := '0';

  
begin  -- rtl

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
      
      if pixel_x_640 /= last_pixel_x_640 then
        drop_start_plus_row <= drop_start_plus_row_drive;
        drop_start_plus_end_plus_row <= drop_start_plus_end_plus_row_drive;
        drop_start <= drop_start_drive;
        drop_end <= drop_end_drive;
        drop_distance_to_start <= drop_distance_to_start_drive;
        drop_distance_to_end <= drop_distance_to_end_drive;
        drop_distance_to_start_drive <= drop_distance_to_start_drive2;
        drop_distance_to_end_drive <= drop_distance_to_end_drive2;
        glyph_pixel <= glyph_bits(0);
        
        if hsync_in = '1' then
          glyph_bit_count <= 0;
        elsif glyph_bit_count < 2 then
          -- Request next glyph
          --
          -- Update start/end of drop
          drop_start_drive <= to_integer(next_start(4 downto 0));
          drop_end_drive <= to_integer(next_end(4 downto 0));
          drop_distance_to_end_drive2 <= to_unsigned(129 + drop_row - (frame_number - to_integer(next_start(4 downto 0)))
                                                                - to_integer(next_end(4 downto 0)),8);  
          drop_distance_to_start_drive2 <= to_unsigned(129 + drop_row - (frame_number - to_integer(next_start(4 downto 0))),8);
          
          -- Work out where drops stop and start
          -- Add 1, so that a start of 0 doesn't appear until 2nd
          -- frame, so that there is no drip heads hanging around
          -- at the top of frame after rain has retracted (it never
          -- actually disappears, just retracts, as the rain actually
          -- forms a transition between normal and matrix mode displays).
          drop_start_plus_row_drive <= to_integer(next_start(4 downto 0)) + drop_row + 1;
          drop_start_plus_end_plus_row_drive
            <= to_integer(next_start(4 downto 0)) + to_integer(next_end(4 downto 0)) + drop_row + 1;
          
--          report "new drop start,end = "
--            & integer'image(to_integer(next_start(4 downto 0))) & ","
--            & integer'image(to_integer(next_end(4 downto 0)));
          glyph_bit_count <= 8;
        else
          -- Shift bits down for rain chargen
          glyph_bits(6 downto 0) <= glyph_bits(7 downto 1);
          -- XXX for now keep filling with 1s for testing
          glyph_bits(7) <= '1';

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
      case feed is
        when Normal =>
          -- Normal display, so show pixels from input video stream
          vgared_out <= vgared_in;
          vgagreen_out <= vgagreen_in;
          vgablue_out <= vgablue_in;
        when Matrix =>
          -- Matrix mode, so display the matrix mode text mode that we
          -- generate here.
          vgared_out <= vgared_matrix;
          vgagreen_out <= vgagreen_matrix;
          vgablue_out <= vgablue_matrix;
        when Rain =>
          -- Matrix rain drop, so display a random character in green on
          -- black.
          if glyph_pixel='1' then
            -- XXX make head of column whiter
            -- XXX make brightness decrease with position
--            report "distance_to_start = $" & to_hstring(drop_distance_to_start);
            case drop_distance_to_start(6 downto 0) is
              when "0000000" =>
                vgared_out <= x"FF";
                vgagreen_out <= x"FF";
                vgablue_out <= x"FF";
              when "1111111" =>
                vgared_out <= x"C0";
                vgagreen_out <= x"F0";
                vgablue_out <= x"C0";
              when others =>
                vgared_out <= (others => '0');
                vgagreen_out(7 downto 2) <= drop_distance_to_end(5 downto 0);
                vgagreen_out(1 downto 0) <= (others => '1');
                vgablue_out <= (others => '0');
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
        lfsr_reset(1 downto 0) <= "11";
        lfsr_advance_counter <= 31;
        lfsr_advance(1 downto 0) <= "11";        
      end if;
      if last_vsync = '1' and vsync_in = '0' then
        -- Vertical flyback = start of next frame
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
        -- Reset LFSRs
        if seed(15 downto 0) /= "00000000000000" then
          lfsr_seed0(15 downto 2) <= seed(15 downto 2);
        else
          lfsr_seed0(15 downto 2) <= (others => '1');
        end if;
        lfsr_seed1(15 downto 2) <= seed(15 downto 2);
        lfsr_seed2(15 downto 2) <= seed(15 downto 2);
        lfsr_seed3(15 downto 2) <= seed(15 downto 2);
        lfsr_seed0(1 downto 0) <= "00";
        lfsr_seed1(1 downto 0) <= "01";
        lfsr_seed2(1 downto 0) <= "10";
        lfsr_seed3(1 downto 0) <= "11";
        lfsr_reset(1 downto 0) <= "11";
        lfsr_advance(1 downto 0) <= "11";
        lfsr_advance_counter <= 31;
      else
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
    end if;
  end process;

end rtl;
