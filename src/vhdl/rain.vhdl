library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
use work.all;

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
  signal drop_row : integer range 0 to 63 := 1;

  signal drop_start_plus_row : integer range 0 to 127 := 0;
  signal drop_start_plus_end_plus_row
    : integer range 0 to 255 := 0;

  signal vgared_matrix : unsigned(7 downto 0) := x"7f";
  signal vgagreen_matrix : unsigned(7 downto 0) := x"7f";
  signal vgablue_matrix : unsigned(7 downto 0) := x"7f";

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

  signal glyph_bits : std_logic_vector(7 downto 0) := x"FF";
  
begin  -- rtl

  lfsr0: entity work.lfsr16 port map (
    clock => pixelclock,
    reset => lfsr_reset(0),
    seed => lfsr_seed0,
    step => lfsr_advance(0),
    output => lfsr_out(0));
  
  process(pixelclock)
  begin
    if rising_edge(pixelclock) then
      hsync_out <= hsync_in;
      vsync_out <= vsync_in;
      last_hsync <= hsync_in;
      last_vsync <= vsync_in;

      -- Work out where drops stop and start
      -- Add 1, so that a start of 0 doesn't appear until 2nd
      -- frame, so that there is no drip heads hanging around
      -- at the top of frame after rain has retracted (it never
      -- actually disappears, just retracts, as the rain actually
      -- forms a transition between normal and matrix mode displays).
      drop_row <= to_integer(ycounter_in(10 downto 3));
      drop_start_plus_row <= drop_start + drop_row + 1;
      drop_start_plus_end_plus_row
        <= drop_start + drop_end + drop_row + 1;

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
          if glyph_bits(0)='1' then
            -- XXX make head of column whiter
            -- XXX make brightness decrease with position
            vgared_out <= (others => '0');
            vgagreen_out <= (others => '1');
            vgablue_out <= (others => '0');
          else
            vgared_out <= (others => '0');
            vgagreen_out <= (others => '0');
            vgablue_out <= (others => '0');
          end if;
      end case;
      if pixel_x_640 /= last_pixel_x_640 then
        -- Shift bits down for rain chargen
        glyph_bits(6 downto 0) <= glyph_bits(7 downto 1);
        -- XXX for now keep filling with 1s for testing
        glyph_bits(7) <= '1';
      end if;
      
      if last_hsync = '1' and hsync_in = '0' then
        -- Horizontal fly-back
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
        elsif pixel_x_640 = 639 then
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
