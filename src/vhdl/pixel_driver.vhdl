--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2018
--
-- *  This program is free software; you can redistribute it and/or modify
-- *  it under the terms of the GNU Lesser General Public License as
-- *  published by the Free Software Foundation; either version 3 of the
-- *  License, or (at your option) any later version.
-- *
-- *  This program is distributed in the hope that it will be useful,
-- *  but WITHOUT ANY WARRANTY; without even the implied warranty of
-- *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- *  GNU General Public License for more details.
-- *
-- *  You should have received a copy of the GNU Lesser General Public License
-- *  along with this program; if not, write to the Free Software
-- *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
-- *  02111-1307  USA.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

library UNISIM;
use UNISIM.vcomponents.all;


entity pixel_driver is
  generic (
    initial_field : integer := 1;
    -- Use this to speed up simulation by reducing frame height
    -- reduction must be even, to avoid messing up HSYNC pulse train between
    -- odd and even fields
    debug_height_reduction : integer := 0
    );
  port (
    -- The various clocks we need
    cpuclock : in std_logic;
    clock81 : in std_logic;
    clock27 : in std_logic;

    -- 720x576@50Hz if pal50_select='1', else 720x480@60Hz NTSC (or VGA 64Hz if
    -- enabled)
    pal50_select : in std_logic;
    -- 640x480@64Hz if vga60_select='1' override is enabled, e
    -- for monitors that can't do the HDTV modes
    vga60_select : in std_logic := '0';
    -- Shows simple test pattern if '1', else shows normal video
    test_pattern_enable : in std_logic;

    -- Invert hsync or vsync signals if '1'
    hsync_invert : in std_logic;
    vsync_invert : in std_logic;
    vga_blank : out std_logic;

    interlace_mode : in std_logic := '1';
    mono_mode : in std_logic := '0';
    
    -- ~1mhz clock for CPU and other parts, derived directly from the video clock
    phi_1mhz_ntsc_out : out std_logic;
    phi_1mhz_out : out std_logic;
    phi_2mhz_out : out std_logic;
    phi_3mhz_out : out std_logic;
    
    -- Incoming video, e.g., from VIC-IV and rain compositer
    -- Clocked at clock81 (aka pixelclock)
    red_i : in unsigned(7 downto 0);
    green_i : in unsigned(7 downto 0);
    blue_i : in unsigned(7 downto 0);

    -- Output video stream, clocked at correct clock for the
    -- video mode, i.e., after clock domain crossing
    red_o : out unsigned(7 downto 0) := x"FF";
    green_o : out unsigned(7 downto 0) := x"FF";
    blue_o : out unsigned(7 downto 0) := x"FF";
    -- hsync and vsync signals for VGA
    hsync : out std_logic := '1';
    vsync : out std_logic := '1';

    -- Narrow display output, for VGA/HDMI
    red_no : out unsigned(7 downto 0) := x"FF";
    green_no : out unsigned(7 downto 0) := x"FF";
    blue_no : out unsigned(7 downto 0) := x"FF";

    -- Component video output
    luma : out unsigned(7 downto 0) := (others => '0');
    chroma : out unsigned(7 downto 0) := (others => '0');
    composite : out unsigned(7 downto 0) := (others => '0');
    
    -- Inform VIC-IV of new rasters and new frames
    -- Signals for VIC-IV etc to know what is happening
    hsync_uninverted : out std_logic := '0';
    vsync_uninverted : out std_logic := '0';
    y_zero : out std_logic := '0';
    x_zero : out std_logic := '0';
    inframe : out std_logic := '0';
    vga_inletterbox : out std_logic := '0';

    debug_forward : in std_logic := '0';
    debug_backward : in std_logic := '0';
  
    -- Indicate when next pixel/raster is expected
    pixel_strobe_out : out std_logic := '0';

    fullwidth_dataenable : out std_logic := '1';
    narrow_dataenable : out std_logic := '1';
    
    -- Similar signals to above for the LCD panel
    -- The main difference is that we only announce pixels during the 800x480
    -- letter box that the LCD can show.
    vga_hsync : out std_logic := '0';
    lcd_hsync : out std_logic := '0';
    lcd_vsync : out std_logic := '0';
    lcd_pixel_strobe : out std_logic := '0';     -- in 30/40MHz clock domain to match pixels
    lcd_inletterbox : out std_logic := '0'

    );

end pixel_driver;

architecture greco_roman of pixel_driver is

  signal last_debug_forward : std_logic := '0';
  signal last_debug_backward : std_logic := '0';
  signal debug_offset_u : integer := 0;
  signal debug_offset_v : integer := 0;
  signal debug_angle : integer := 0;
  signal debug_sine : integer := 0;
  signal debug_cosine : integer := 0;
  
  signal last_interlace : std_logic := '0';
  signal interlace_mode_integer : integer range 0 to 1 := 0;

  -- Set to 1 to enable gamma pre-correction of video
  signal gamma_enabled : std_logic := '0';
  
  signal fullwidth_dataenable_internal : std_logic := '0';
  signal narrow_dataenable_internal : std_logic := '0';
  
  signal pal50_select_internal : std_logic := '0';
  signal pal50_select_internal_drive : std_logic := '0';

  signal vga60_select_internal : std_logic := '0';
  signal vga60_select_internal_drive : std_logic := '0';
  
  signal raster_toggle : std_logic := '0';
  signal raster_toggle_last : std_logic := '0';

  signal cv_hsync_pal50 : std_logic := '0';
  signal hsync_pal50 : std_logic := '0';
  signal hsync_pal50_uninverted : std_logic := '0';
  signal vsync_pal50 : std_logic := '0';
  signal vsync_pal50_uninverted : std_logic := '0';
  signal cv_vsync_last : std_logic := '0';
  signal vsync_uninverted_int : std_logic := '0';

  signal phi2_1mhz_pal50 : std_logic;
  signal phi2_1mhz_ntsc60 : std_logic;
  signal phi2_1mhz_vga60 : std_logic;
  signal phi2_2mhz_pal50 : std_logic;
  signal phi2_2mhz_ntsc60 : std_logic;
  signal phi2_2mhz_vga60 : std_logic;
  signal phi2_3mhz_pal50 : std_logic;
  signal phi2_3mhz_ntsc60 : std_logic;
  signal phi2_3mhz_vga60 : std_logic;
  
  signal cv_hsync_ntsc60 : std_logic := '0';
  signal hsync_ntsc60 : std_logic := '0';
  signal hsync_ntsc60_uninverted : std_logic := '0';
  signal vsync_ntsc60 : std_logic := '0';
  signal vsync_ntsc60_uninverted : std_logic := '0';
  
  signal cv_hsync_vga60 : std_logic := '0';
  signal hsync_vga60 : std_logic := '0';
  signal hsync_vga60_uninverted : std_logic := '0';
  signal vsync_vga60 : std_logic := '0';
  signal vsync_vga60_uninverted : std_logic := '0';
  
  signal lcd_vsync_pal50 : std_logic := '0';
  signal lcd_vsync_ntsc60 : std_logic := '0';
  signal lcd_vsync_vga60 : std_logic := '0';

  signal lcd_hsync_pal50 : std_logic := '0';
  signal lcd_hsync_ntsc60 : std_logic := '0';
  signal lcd_hsync_vga60 : std_logic := '0';
  
  signal vga_hsync_pal50 : std_logic := '0';
  signal vga_hsync_ntsc60 : std_logic := '0';
  signal vga_hsync_vga60 : std_logic := '0';

  signal vga_blank_pal50 : std_logic := '0';
  signal vga_blank_ntsc60 : std_logic := '0';
  signal vga_blank_vga60 : std_logic := '0';
  
  signal test_pattern_red : unsigned(7 downto 0) := x"00";
  signal test_pattern_green : unsigned(7 downto 0) := x"00";
  signal test_pattern_blue : unsigned(7 downto 0) := x"00";

  signal x_zero_pal50 : std_logic := '0';
  signal y_zero_pal50 : std_logic := '0';
  signal x_zero_ntsc60 : std_logic := '0';
  signal y_zero_ntsc60 : std_logic := '0';
  signal x_zero_vga60 : std_logic := '0';
  signal y_zero_vga60 : std_logic := '0';

  signal fullwidth_dataenable_pal50 : std_logic := '0';
  signal fullwidth_dataenable_ntsc60 : std_logic := '0';
  signal fullwidth_dataenable_vga60 : std_logic := '0';

  signal narrow_dataenable_pal50 : std_logic := '0';
  signal narrow_dataenable_ntsc60 : std_logic := '0';
  signal narrow_dataenable_vga60 : std_logic := '0';

  signal lcd_inletterbox_pal50 : std_logic := '0';
  signal lcd_inletterbox_ntsc60 : std_logic := '0';
  signal lcd_inletterbox_vga60 : std_logic := '0';

  signal vga_inletterbox_pal50 : std_logic := '0';
  signal vga_inletterbox_ntsc60 : std_logic := '0';
  signal vga_inletterbox_vga60 : std_logic := '0';

  signal lcd_pixel_clock_50 : std_logic := '0';
  signal lcd_pixel_clock_60 : std_logic := '0';
  signal lcd_pixel_clock_vga60 : std_logic := '0';
  
  signal pixel_strobe_50 : std_logic := '0';
  signal pixel_strobe_60 : std_logic := '0';
  signal pixel_strobe_vga60 : std_logic := '0';

  signal cv_pixel_strobe : std_logic := '0';
  signal cv_pixel_strobe_50 : std_logic := '0';
  signal cv_pixel_strobe_60 : std_logic := '0';
  signal cv_pixel_strobe_vga60 : std_logic := '0';
  
  signal test_pattern_red50 : unsigned(7 downto 0) := x"00";
  signal test_pattern_green50 : unsigned(7 downto 0) := x"00";
  signal test_pattern_blue50 : unsigned(7 downto 0) := x"00";
  signal test_pattern_red60 : unsigned(7 downto 0) := x"00";
  signal test_pattern_green60 : unsigned(7 downto 0) := x"00";
  signal test_pattern_blue60 : unsigned(7 downto 0) := x"00";
  signal test_pattern_redvga60 : unsigned(7 downto 0) := x"00";
  signal test_pattern_greenvga60 : unsigned(7 downto 0) := x"00";
  signal test_pattern_bluevga60 : unsigned(7 downto 0) := x"00";

  signal raster_toggle50 : std_logic := '0';
  signal raster_toggle60 : std_logic := '0';
  signal raster_togglevga60 : std_logic := '0';
  signal raster_toggle_last50 : std_logic := '0';
  signal raster_toggle_last60 : std_logic := '0';
  signal raster_toggle_lastvga60 : std_logic := '0';

  signal test_pattern_enable120 : std_logic := '0';
  
  signal y_zero_internal : std_logic := '0';

  signal cv_sync : std_logic := '0';
  signal cv_vsync : std_logic := '0';
  constant cv_vsync_delay : integer := 3;
  signal cv_vsync_counter : integer := 0;
  signal cv_vsync_extend : integer := 0;
  signal chroma_drive : signed(15 downto 0);
  signal px_luma : unsigned(15 downto 0);
  signal luma_drive : unsigned(9 downto 0);
  signal px_u : signed(15 downto 0);
  signal px_v : signed(15 downto 0);
  signal cv_red : unsigned(7 downto 0);
  signal cv_green : unsigned(7 downto 0);
  signal cv_blue : unsigned(7 downto 0);

  -- Single raster memory buffer for generating 15KHz composite signal
  signal raddr : integer range 0 to 2047 := 0;
  signal rdata_red : unsigned(7 downto 0);
  signal rdata_green : unsigned(7 downto 0);
  signal rdata_blue : unsigned(7 downto 0);
  signal waddr : integer range 0 to 2047 := 0;
  signal wdata_red : unsigned(7 downto 0);
  signal wdata_green : unsigned(7 downto 0);
  signal wdata_blue : unsigned(7 downto 0);

  signal cv_x : integer := 0;
  signal cv_pixel_strobe_int : std_logic := '0';
  signal cv_pixel_toggle : std_logic := '0';

  signal raster15khz_oddeven : std_logic := '0';
  signal raster31khz_subpixel_counter : integer range 0 to 2 := 0;
  signal raster15khz_subpixel_counter : integer range 0 to 5 := 0;
  signal raster15khz_skip : integer range 0 to 108 := 0;
  signal raster15khz_active_raster : std_logic := '0';
  
  signal raster15khz_buf0_cs : std_logic := '1';
  signal raster15khz_buf0_we : std_logic := '0';
  signal raster15khz_waddr : integer := 0;
  signal raster15khz_waddr_inc : std_logic := '0';
  signal waddr_inc_toggle : std_logic := '0';
  signal raster15khz_raddr : integer := 0;
  signal raster15khz_wdata : unsigned(31 downto 0) := (others => '0');
  signal raster15khz_rdata : unsigned(31 downto 0);

  -- PAL/NTSC 15KHz video odd/even field selection
  signal field_is_odd : integer range 0 to 1 := initial_field;
  signal cv_hsync : std_logic := '0';
  signal cv_hsync_last : std_logic := '0';
  signal cv_field : std_logic := '0';
  signal hsync_uninverted_int : std_logic := '0';
  signal hsync_uninverted_last : std_logic := '0';
  signal vsync_xpos : integer := 0;
  signal vsync_xpos_sub : integer := 0;
  signal cv_vsync_row : integer range 0 to 10 := 0;
  signal cv_sync_hsrc : std_logic;
  signal cv_active_area : std_logic := '0';

  signal x_zero_last : std_logic := '0';
  signal y_zero_last : std_logic := '0';
  signal x_zero_int : std_logic;
  signal y_zero_int : std_logic;
  signal new_raster : std_logic := '0';
  signal new_raster_toggle : std_logic := '0';
  signal raster_number : unsigned(9 downto 0) := to_unsigned(0,10);
  signal buffering_31khz : std_logic := '0';
  signal buffer_target_31khz : std_logic := '0';

  signal time_since_last_pixel : integer range 0 to 1023 := 0;
  
  -- 15KHz video VBLANK SYNC formats
  constant vsync_xpos_max : integer := 31;
  type vblank_format_t is array(0 to 10) of std_logic_vector(vsync_xpos_max downto 0);
  -- See "Video Demystified", p294
  signal pal_odd_vblanks : vblank_format_t := (
    -- 0 = sync active, i.e., signal low
    -- Divided into 2usec, 28usec, 2usec, 2usec, 28usec, 2usec
    -- pieces, to allow easy assembly of complete rasters
    -- (actually handled as 31KHz HSYNC width x1, x14, x1, x1, x14, 1,
    -- so that the frame formats can be varied, and it will just follow suit)
    -- In fact, why don't we just make the arrays 32 bits wide, 1 bit per HSYNC
    -- width, and then life is simple.
    --  Top of field 1
    "11111111111111001111111111111101",
    "11111111111111011111111111111101",
    "11111111111111011111111111111101",
    "11111111111111000000000000000100",
    "00000000000001000000000000000100",
    "00000000000001000000000000000101",
    "11111111111111011111111111111101",        
    "11111111111111011111111111111100",
    "11111111111111011111111111111111",
    "01111111111111111111111111111111",
    "11111111111111111111111111111111"
    );
  signal pal_even_vblanks : vblank_format_t := (
    -- 0 = sync active, i.e., signal low
    -- Divided into 2usec, 28usec, 2usec, 2usec, 28usec, 2usec
    -- pieces, to allow easy assembly of complete rasters
    -- (actually handled as 31KHz HSYNC width x1, x14, x1, x1, x14, 1,
    -- so that the frame formats can be varied, and it will just follow suit)
    -- In fact, why don't we just make the arrays 32 bits wide, 1 bit per HSYNC
    -- width, and then life is simple.
    --  Top of field 1
    "11111111111111001111111111111101",
    "11111111111111011111111111111101",
    "11111111111111011111111111111101",
    "11111111111111000000000000000100",
    "00000000000001000000000000000100",
    "00000000000001000000000000000101",
    "11111111111111011111111111111101",        
    "11111111111111011111111111111101",
    "11111111111111011111111111111111",
    "01111111111111111111111111111111",
    "11111111111111111111111111111111"
    );
  signal pal_progressive_vblanks : vblank_format_t := (
    "11111111111111011111111111111101",
    "11111111111111011111111111111101",
    "11111111111111000000000000000001",
    "00000000000001000000000000000100",
    "00000000000001000000000000000101",
    "11111111111111011111111111111101",        
    "11111111111111011111111111111101",
    "11111111111111011111111111111100",
    "11111111111111111111111111111111",
    "11111111111111111111111111111111",
    "11111111111111111111111111111111"
    );

  
  -- See "Video Demystified", p272
  signal ntsc_even_vblanks : vblank_format_t := (
    -- NTSC is simpler with a 6:6:6 pattern, that just gets the last
    -- half cut off for the 2nd field

    -- Remember that HSYNC in MEGA65 notation occurs at the _end_ rather than
    -- start of a raster. This means we need to count off the rest of the
    -- raster from HSYNC to end of active area of the following raster, to get
    -- things lined up for how NTSC video thinks about it.
    -- That means inserting 14x 1 at the start.

    "11111111111111111111111111111101",
    "11111111111111011111111111111101",
    "11111111111111011111111111111101",
    "11111111111111011111111111111100",
    "00000000000001000000000000000100",
    "00000000000001000000000000000100",
    "00000000000001000000000000000100",
    "11111111111111011111111111111101",
    "11111111111111011111111111111101",
    "11111111111111011111111111111100",
    -- Last line is dummy. Only the very first bit will be used, for half
    -- a period.
    "11111111111111111111111111111111"
    );

  signal ntsc_odd_vblanks : vblank_format_t := (
    -- NTSC is simpler with a 6:6:6 pattern, that just gets the last
    -- half cut off for the 2nd field
    "11111111111111111111111111111100",
    "11111111111111011111111111111101",
    "11111111111111011111111111111101",
    "11111111111111011111111111111101",
    "11111111111111000000000000000100",
    "00000000000001000000000000000100",
    "00000000000001000000000000000100",
    "00000000000001011111111111111101",        
    "11111111111111011111111111111101",
    "11111111111111011111111111111100",
    -- Last line is dummy. Only the very first bit will be used, for half
    -- a period.
    "11111111111111111111111111111111"
    );

  constant pal_colour_phase_add_sub : unsigned(31 downto 0) := x"032E43BA";
  constant pal_colour_phase_add : unsigned(7 downto 0) := x"0e";
  constant ntsc_colour_phase_add_sub : unsigned(31 downto 0) := x"4D62D0F8";
  constant ntsc_colour_phase_add : unsigned(7 downto 0) := x"0b";

  signal pal_colour_phase : unsigned(7 downto 0) := x"00";
  signal pal_colour_phase_sub : unsigned(32 downto 0) := (others => '0');
  signal ntsc_colour_phase : unsigned(7 downto 0) := x"00";
  signal ntsc_colour_phase_sub : unsigned(32 downto 0) := (others => '0');

  -- XXX Toggle between 135 and 225 each raster line
  signal pal_phase_offset : integer range 0 to 255 := 225;
  signal pal_v_invert : integer range 0 to 128 := 0;
  signal colour_burst_mask_count : integer range 0 to 15 := 0;
  
  signal colour_burst_mask : std_logic := '1';
  signal colour_burst_en : std_logic := '0';
  signal colour_burst_start_neg : std_logic := '0';
  
  signal vblank_train_len_adjust : integer range 0 to 3 := 0;
  
-- Composite pixels have to be 5 1/3 cycles wide at 81MHz to fit the 720H into
  -- the time of 640 x 13.5MHz pixels. We do this by alternating between 5 and
  -- 6 cycles duration
  -- We cycle through the first 3 values in this array. The 4th value is used
  -- to time constant-width pixels during the back porch of the HSYNC.
  -- XXX Later add support for using constant width pixels always, if the user
  -- prefers higher resolution, at the cost of no side borders.
  signal pixel_num : integer range 0 to 3 := 0;
  type px_timing_t is array (0 to 3) of integer;
  signal pixel_widths : px_timing_t := ( 4, 4, 5, 5);
  
  -- Use 32 element look-up table for producing sine curve
  -- for colour signal.  We can only produce ~20 samples per
  -- cycle of the colour burst frequency, as limited by our 81MHz
  -- output rate.  However, because we keep track of the colour
  -- burst phase with higher accuracy, and because the colour burst
  -- phase is used to encode colour on PAL and NTSC (but not SECAM)
  -- we need to be able to reproduce quite fine phases.
  -- Thus we will use a 256 entry 
  type s7_0to255 is array (0 to 255) of integer range -128 to 127;  
  signal sine_table : s7_0to255 := (
    0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,
    48,51,54,57,59,62,65,67,70,73,75,78,80,82,85,87,
    89,91,94,96,98,100,102,103,105,107,108,110,112,113,114,116,
    117,118,119,120,121,122,123,123,124,125,125,126,126,126,126,126,
    127,126,126,126,126,126,125,125,124,123,123,122,121,120,119,118,
    117,116,114,113,112,110,108,107,105,103,102,100,98,96,94,91,
    89,87,85,82,80,78,75,73,70,67,65,62,59,57,54,51,
    48,45,42,39,36,33,30,27,24,21,18,15,12,9,6,3,
    0,-3,-6,-9,-12,-15,-18,-21,-24,-27,-30,-33,-36,-39,-42,-45,
    -48,-51,-54,-57,-59,-62,-65,-67,-70,-73,-75,-78,-80,-82,-85,-87,
    -89,-91,-94,-96,-98,-100,-101,-103,-105,-107,-108,-110,-111,-113,-114,-116,
    -117,-118,-119,-120,-121,-122,-123,-123,-124,-125,-125,-126,-126,-126,-126,-126,
    -127,-126,-126,-126,-126,-126,-125,-125,-124,-123,-123,-122,-121,-120,-119,-118,
    -117,-116,-114,-113,-112,-110,-108,-107,-105,-103,-102,-100,-98,-96,-94,-91,
    -89,-87,-85,-82,-80,-78,-75,-73,-70,-67,-65,-62,-59,-57,-54,-51,
    -48,-45,-42,-39,-36,-33,-30,-27,-24,-21,-18,-15,-12,-9,-6,-3
    );
  
  type gamma_table is array (0 to 255) of unsigned(7 downto 0);
  -- Generated using:
  --  for(int i=0;i<256;i++) {
  --  float f=i*1.0/256;
  --  if (f<0.018)
  --    printf("x\"%02x\"",(int)(i*4.5));
  --  else {
  --    float v=1.099*powf(f,0.45)-0.099;
  --    int vv=v*256;
  --    printf("x\"%02x\"",vv);
  --  }
  --  if (i!=255) printf(",");
  --  if ((i&0x0f)==0x0f) printf("\n");
  --  
  --  }
  
  signal ntsc_gamma : gamma_table := (
    x"00",x"04",x"09",x"0d",x"12",x"16",x"1a",x"1e",x"21",x"25",x"28",x"2a",x"2d",x"30",x"32",x"35",
    x"37",x"39",x"3b",x"3d",x"3f",x"41",x"43",x"45",x"47",x"49",x"4b",x"4c",x"4e",x"50",x"51",x"53",
    x"55",x"56",x"58",x"59",x"5b",x"5c",x"5d",x"5f",x"60",x"62",x"63",x"64",x"66",x"67",x"68",x"69",
    x"6b",x"6c",x"6d",x"6e",x"6f",x"71",x"72",x"73",x"74",x"75",x"76",x"78",x"79",x"7a",x"7b",x"7c",
    x"7d",x"7e",x"7f",x"80",x"81",x"82",x"83",x"84",x"85",x"86",x"87",x"88",x"89",x"8a",x"8b",x"8c",
    x"8d",x"8e",x"8f",x"90",x"91",x"91",x"92",x"93",x"94",x"95",x"96",x"97",x"98",x"99",x"99",x"9a",
    x"9b",x"9c",x"9d",x"9e",x"9e",x"9f",x"a0",x"a1",x"a2",x"a3",x"a3",x"a4",x"a5",x"a6",x"a7",x"a7",
    x"a8",x"a9",x"aa",x"aa",x"ab",x"ac",x"ad",x"ad",x"ae",x"af",x"b0",x"b0",x"b1",x"b2",x"b3",x"b3",
    x"b4",x"b5",x"b6",x"b6",x"b7",x"b8",x"b8",x"b9",x"ba",x"bb",x"bb",x"bc",x"bd",x"bd",x"be",x"bf",
    x"bf",x"c0",x"c1",x"c1",x"c2",x"c3",x"c3",x"c4",x"c5",x"c5",x"c6",x"c7",x"c7",x"c8",x"c9",x"c9",
    x"ca",x"cb",x"cb",x"cc",x"cc",x"cd",x"ce",x"ce",x"cf",x"d0",x"d0",x"d1",x"d1",x"d2",x"d3",x"d3",
    x"d4",x"d4",x"d5",x"d6",x"d6",x"d7",x"d7",x"d8",x"d9",x"d9",x"da",x"da",x"db",x"dc",x"dc",x"dd",
    x"dd",x"de",x"de",x"df",x"e0",x"e0",x"e1",x"e1",x"e2",x"e2",x"e3",x"e4",x"e4",x"e5",x"e5",x"e6",
    x"e6",x"e7",x"e8",x"e8",x"e9",x"e9",x"ea",x"ea",x"eb",x"eb",x"ec",x"ec",x"ed",x"ed",x"ee",x"ef",
    x"ef",x"f0",x"f0",x"f1",x"f1",x"f2",x"f2",x"f3",x"f3",x"f4",x"f4",x"f5",x"f5",x"f6",x"f6",x"f7",
    x"f7",x"f8",x"f8",x"f9",x"f9",x"fa",x"fb",x"fb",x"fc",x"fc",x"fd",x"fd",x"fe",x"fe",x"ff",x"ff"
    );
  
  signal phi_1mhz_int : std_logic;
  signal phi_2mhz_int : std_logic;
  signal phi_3mhz_int : std_logic;

  signal phi_1mhz_ubuf : std_logic;
  signal phi_2mhz_ubuf : std_logic;
  signal phi_3mhz_ubuf : std_logic;

begin

  assert ( (debug_height_reduction mod 2) = 0) report "debug_height_reduction must be even";
  assert (debug_height_reduction <= 500) report "debug_height_reduction must be somewhat less than the shortest frame height";
  
  -- Here we generate the frames and the pixel strobe references for everything
  -- that needs to produce pixels, and then buffer the pixels that arrive at pixelclock
  -- in a buffer, and then emit the pixels at the appropriate clock rate
  -- for the video mode.  Video mode selection is via a simple PAL/NTSC input.

  -- We are trying to use the 720x560 / 720x480 PAL / NTSC HDMI TV modes, since
  -- they are supported by HDMI, and should match the frame cycle timing of the
  -- C64 properly.
  -- They also use a common 27MHz pixel clock, which makes our life simpler
  
  -- EDTV 720x576p 50Hz from:
  -- http://read.pudn.com/downloads222/doc/1046129/CEA861D.pdf
  -- (This is the mode lines that the ADV7511 should want to see)
  frame50: entity work.frame_generator 
    generic map (

                  -- XXX To match C64 timing, we have to very slightly trim the
                  -- raster lines.  This reduces our CPU 1MHz frequency error
                  -- from -486 Hz to +139 Hz
--       frame_width => 864 - 1,
      -- The frame_width trim is now handled in the frame generator:
      -- In fake progressive mode, there is 624 rather than 625 rasters, which
      -- are 864 wide. In interlace mode to keep timing when we add the single
      -- extra raster, we trim the frame width by one tick
      frame_width => 864,
      
                  frame_height => 625 - debug_height_reduction,        -- 312.5 lines x 2 fields

                  x_zero_position => 864-45,
                  
                  fullwidth_width => 800,
                  fullwidth_start => 0,

                  narrow_width => 720,
                  narrow_start => 0,

                  pipeline_delay => 0,

                  first_raster => 1+16,
                  last_raster => 576+16 - debug_height_reduction,

                  -- VSYNC comes 5 lines after video area, and lasts 5 raster lines
                  vsync_start => 576+16+5 - debug_height_reduction,
                  vsync_end   => 576+16+5+4 - debug_height_reduction,

                  -- Add 6 more clocks after the end of video lines before
                  -- asserting HSYNC (HDMI test 7-25)
                  hsync_start => 720+12+5,
                  hsync_end => 720+12+5+64,
                  -- Again, VGA ends up a bit to the left, so make HSYNC earlier
                  vga_hsync_start => 720,
                  vga_hsync_end => 720+64,                 
                  
                  -- Centre letterbox slice for LCD panel
                  lcd_first_raster => 1+(576-480)/2 - debug_height_reduction,
                  lcd_last_raster => 1+576-(576-480)/2 - debug_height_reduction
                  
                  )                  
    port map ( clock81 => clock81,
               clock41 => cpuclock,
               hsync => hsync_pal50,
               hsync_uninverted => hsync_pal50_uninverted,
               vsync_uninverted => vsync_pal50_uninverted,
               vsync => vsync_pal50,
               hsync_polarity => hsync_invert,
               vsync_polarity => vsync_invert,

               field_is_odd => field_is_odd,

               interlace_enable => interlace_mode,
               
               cv_hsync => cv_hsync_pal50,
               
               phi2_1mhz_out => phi2_1mhz_pal50,
               phi2_2mhz_out => phi2_2mhz_pal50,
               phi2_3mhz_out => phi2_3mhz_pal50,
               
               vga_hsync => vga_hsync_pal50,
               lcd_hsync => lcd_hsync_pal50,
               lcd_vsync => lcd_vsync_pal50,
               fullwidth_dataenable => fullwidth_dataenable_pal50,
               narrow_dataenable => narrow_dataenable_pal50,
               lcd_inletterbox => lcd_inletterbox_pal50,
               vga_inletterbox => vga_inletterbox_pal50,

               vga_blank => vga_blank_pal50,

               red_o => test_pattern_red50,
               green_o => test_pattern_green50,
               blue_o => test_pattern_blue50,
               
               -- 80MHz facing signals for the VIC-IV
               x_zero => x_zero_pal50,
               y_zero => y_zero_pal50,
               pixel_strobe => pixel_strobe_50,
               cv_pixel_strobe => cv_pixel_strobe_50

               );

  -- EDTV 720x480p 60Hz from:
  -- http://read.pudn.com/downloads222/doc/1046129/CEA861D.pdf
  -- (This is the mode lines that the ADV7511 should want to see)
  frame60: entity work.frame_generator
    generic map ( frame_width => 858,   -- 65 cycles x 16 pixels
                  frame_height => 526 - debug_height_reduction,       -- NTSC frame is 263 lines x 2 frames

                  x_zero_position => 858-46,

                  fullwidth_width => 800,
                  fullwidth_start => 0,

                  narrow_width => 720,
                  narrow_start => 0,

                  pipeline_delay => 0,
                  
                  -- Advance VSYNC 23 lines (HDMI test 7-25)
                  vsync_start => 480+1+9 - debug_height_reduction,
                  vsync_end => 480+1+5+9 - debug_height_reduction,
                  -- Delay HSYNC by 6 cycles (HDMI test 7-25)
                  hsync_start => 720+16+5,
                  hsync_end => 720+16+62+5,
                  -- ... but not for VGA, or it ends up off-centre
                  vga_hsync_start => 720+10,
                  vga_hsync_end => 720+10+62,
                  
                  first_raster => 1,
                  last_raster => 480 - debug_height_reduction,

                  lcd_first_raster => 1,
                  lcd_last_raster => 480 - debug_height_reduction
                  )                  
    port map ( clock81 => clock81,
               clock41 => cpuclock,
               hsync => hsync_ntsc60,
               hsync_uninverted => hsync_ntsc60_uninverted,
               vsync_uninverted => vsync_ntsc60_uninverted,
               vsync => vsync_ntsc60,
               hsync_polarity => hsync_invert,
               vsync_polarity => vsync_invert,

               cv_hsync => cv_hsync_ntsc60,
               field_is_odd => field_is_odd,
               interlace_enable => interlace_mode,
               
               phi2_1mhz_out => phi2_1mhz_ntsc60,
               phi2_2mhz_out => phi2_2mhz_ntsc60,
               phi2_3mhz_out => phi2_3mhz_ntsc60,

               vga_hsync => vga_hsync_ntsc60,
               lcd_hsync => lcd_hsync_ntsc60,
               lcd_vsync => lcd_vsync_ntsc60,
               fullwidth_dataenable => fullwidth_dataenable_ntsc60,
               narrow_dataenable => narrow_dataenable_ntsc60,
               lcd_inletterbox => lcd_inletterbox_ntsc60,
               vga_inletterbox => vga_inletterbox_ntsc60,

               red_o => test_pattern_red60,
               green_o => test_pattern_green60,
               blue_o => test_pattern_blue60,

               vga_blank => vga_blank_ntsc60,
               
               -- 80MHz facing signals for VIC-IV
               x_zero => x_zero_ntsc60,
               y_zero => y_zero_ntsc60,
               pixel_strobe => pixel_strobe_60,
               cv_pixel_strobe => cv_pixel_strobe_60
               
               );               

  -- ModeLine "640x480" 25.18 640 656 752 800 480 490 492 525 -HSync -VSync
  -- Ends up being 64Hz, because our dotclock is ~27MHz.  Most monitors accept
  -- it, anyway.
  -- XXX - Actually just 720x480p 60Hz NTSC repeated for now.
  frame60vga: entity work.frame_generator
    generic map ( frame_width => 858,   -- 65 cycles x 16 pixels
                  frame_height => 526 - debug_height_reduction,       -- NTSC frame is 263 lines x 2 frames

                  fullwidth_start => 16+62+60,
                  fullwidth_width => 800,
                  
                  narrow_start => 16+62+60,
                  narrow_width => 720,

                  pipeline_delay => 0,
                  
                  vsync_start => 6,
                  vsync_end => 6+6,

                  hsync_start => 16,
                  hsync_end => 16+62,

                  vga_hsync_start => 858-1-(64-16)-62,
                  vga_hsync_end => 858-1-(64-16),
                  
                  first_raster => 42,
                  last_raster => 522,

                  lcd_first_raster => 42,
                  lcd_last_raster => 522 - debug_height_reduction,

                  cycles_per_raster_1mhz => 65,
                  cycles_per_raster_2mhz => 65*2,
                  cycles_per_raster_3mhz => 228 -- 65*3.5, rounded up to next integer
                  
                  )                  
    port map ( clock81 => clock81,
               clock41 => cpuclock,
               hsync => hsync_vga60,
               hsync_uninverted => hsync_vga60_uninverted,
               vsync_uninverted => vsync_vga60_uninverted,
               vsync => vsync_vga60,
               hsync_polarity => hsync_invert,
               vsync_polarity => vsync_invert,

               cv_hsync => cv_hsync_vga60,
               field_is_odd => field_is_odd,
               interlace_enable => interlace_mode,

               phi2_1mhz_out => phi2_1mhz_vga60,
               phi2_2mhz_out => phi2_2mhz_vga60,
               phi2_3mhz_out => phi2_3mhz_vga60,
               
               vga_hsync => vga_hsync_vga60,
               lcd_hsync => lcd_hsync_vga60,
               lcd_vsync => lcd_vsync_vga60,
               fullwidth_dataenable => fullwidth_dataenable_vga60,
               narrow_dataenable => narrow_dataenable_vga60,
               lcd_inletterbox => lcd_inletterbox_vga60,
               vga_inletterbox => vga_inletterbox_vga60,

               vga_blank => vga_blank_vga60,
               
               -- 80MHz facing signals for VIC-IV
               x_zero => x_zero_vga60,
               y_zero => y_zero_vga60,
               pixel_strobe => pixel_strobe_vga60,
               cv_pixel_strobe => cv_pixel_strobe_vga60               
               
               );               

  -- We have two raster buffers for 31KHz to 15KHz video
  -- down-conversion.  One is being read from while the other
  -- is being populated.  We choose either odd or even rasters
  -- to put in the buffer, based on which PAL/NTSC interlace
  -- field we are in at any point in time.
  raster15khz_buf0: entity work.ram32x1024_sync
    port map (
      clk => clock81,
      cs => raster15khz_buf0_cs,
      w => raster15khz_buf0_we,
      write_address => raster15khz_waddr,
      wdata => raster15khz_wdata,
      rdata => raster15khz_rdata,
      address => raster15khz_raddr
     );

  phi_1mhz_ntsc_out <= phi2_1mhz_ntsc60;
  phi_1mhz_int <= phi2_1mhz_pal50 when pal50_select_internal='1' else
                  phi2_1mhz_vga60 when vga60_select_internal='1'
                  else phi2_1mhz_ntsc60;
  phi_2mhz_int <= phi2_2mhz_pal50 when pal50_select_internal='1' else
                  phi2_2mhz_vga60 when vga60_select_internal='1'
                  else phi2_2mhz_ntsc60;
  phi_3mhz_int <= phi2_3mhz_pal50 when pal50_select_internal='1' else
                  phi2_3mhz_vga60 when vga60_select_internal='1'
                  else phi2_3mhz_ntsc60;
  process (cpuclock)
  begin
     if rising_edge(cpuclock) then
        phi_1mhz_ubuf <= phi_1mhz_int;
        phi_2mhz_ubuf <= phi_2mhz_int;
        phi_3mhz_ubuf <= phi_3mhz_int;
     end if;
  end process;

  BUFG_1: unisim.vcomponents.bufg port map (I => phi_1mhz_ubuf, O => phi_1mhz_out);
  BUFG_2: unisim.vcomponents.bufg port map (I => phi_2mhz_ubuf, O => phi_2mhz_out);
  BUFG_3: unisim.vcomponents.bufg port map (I => phi_3mhz_ubuf, O => phi_3mhz_out);

  cv_hsync <= cv_hsync_pal50 when pal50_select_internal='1' else
              cv_hsync_vga60 when vga60_select_internal='1'
              else cv_hsync_ntsc60;
  
  hsync <= hsync_pal50 when pal50_select_internal='1' else
           hsync_vga60 when vga60_select_internal='1'
           else hsync_ntsc60;
  vsync <= vsync_pal50 when pal50_select_internal='1' else
           vsync_vga60 when vga60_select_internal='1'
           else vsync_ntsc60;

  vsync_uninverted_int <= vsync_pal50_uninverted when pal50_select_internal='1' else
                          vsync_vga60_uninverted when vga60_select_internal='1'
                          else vsync_ntsc60_uninverted;
  
  hsync_uninverted <= hsync_pal50_uninverted when pal50_select_internal='1' else
           hsync_vga60_uninverted when vga60_select_internal='1'
           else hsync_ntsc60_uninverted;
  hsync_uninverted_int <= hsync_pal50_uninverted when pal50_select_internal='1' else
           hsync_vga60_uninverted when vga60_select_internal='1'
           else hsync_ntsc60_uninverted;

  vga_hsync <= vga_hsync_pal50 when pal50_select_internal='1' else
               vga_hsync_vga60 when vga60_select_internal='1'
               else vga_hsync_ntsc60;
  lcd_hsync <= lcd_hsync_pal50 when pal50_select_internal='1' else
               lcd_hsync_vga60 when vga60_select_internal='1'
               else lcd_hsync_ntsc60;
  lcd_vsync <= lcd_vsync_pal50 when pal50_select_internal='1' else
               lcd_vsync_vga60 when vga60_select_internal='1'
               else lcd_vsync_ntsc60;

  vga_blank <=       vga_blank_pal50 when pal50_select_internal='1' else
                     vga_blank_vga60 when vga60_select_internal='1'
                     else vga_blank_ntsc60;
  
  fullwidth_dataenable <= fullwidth_dataenable_pal50 when pal50_select_internal='1' else
                 fullwidth_dataenable_vga60 when vga60_select_internal='1'
                 else fullwidth_dataenable_ntsc60;
  fullwidth_dataenable_internal <= fullwidth_dataenable_pal50 when pal50_select_internal='1' else
                 fullwidth_dataenable_vga60 when vga60_select_internal='1'
                 else fullwidth_dataenable_ntsc60;
  narrow_dataenable <= narrow_dataenable_pal50 when pal50_select_internal='1' else
                 narrow_dataenable_vga60 when vga60_select_internal='1'
                 else narrow_dataenable_ntsc60;
  narrow_dataenable_internal <= narrow_dataenable_pal50 when pal50_select_internal='1' else
                 narrow_dataenable_vga60 when vga60_select_internal='1'
                 else narrow_dataenable_ntsc60;

  lcd_inletterbox <= lcd_inletterbox_pal50 when pal50_select_internal='1' else
                     lcd_inletterbox_vga60 when vga60_select_internal='1'
                     else lcd_inletterbox_ntsc60;
  vga_inletterbox <= vga_inletterbox_pal50 when pal50_select_internal='1' else
                     vga_inletterbox_vga60 when vga60_select_internal='1'
                     else vga_inletterbox_ntsc60;

  x_zero <= x_zero_int;
  x_zero_int <= x_zero_pal50 when pal50_select_internal='1' else
                x_zero_vga60 when vga60_select_internal='1'
                else x_zero_ntsc60;
  y_zero <= y_zero_int;
  y_zero_int <= y_zero_pal50 when pal50_select_internal='1' else
                y_zero_vga60 when vga60_select_internal='1'
                else y_zero_ntsc60;

  y_zero_internal <= y_zero_pal50 when pal50_select_internal='1' else
                     y_zero_vga60 when vga60_select_internal='1'
                     else y_zero_ntsc60;

  -- Generate output pixel strobe and signals for read-side of the FIFO
  pixel_strobe_out <= pixel_strobe_50 when pal50_select_internal='1' else
                      pixel_strobe_vga60 when vga60_select_internal='1'
                      else pixel_strobe_60;

  -- Generate internal 15KHz pixel strobe
  cv_pixel_strobe <= cv_pixel_strobe_50 when pal50_select_internal='1' else
                      cv_pixel_strobe_vga60 when vga60_select_internal='1'
                      else cv_pixel_strobe_60;

  -- Generate test pattern image
  test_pattern_red <= test_pattern_red50 when pal50_select_internal='1' else
                      test_pattern_redvga60 when vga60_select_internal='1'
                      else test_pattern_red60;
  test_pattern_green <= test_pattern_green50 when pal50_select_internal='1' else
                      test_pattern_greenvga60 when vga60_select_internal='1'
                      else test_pattern_green60;
  test_pattern_blue <= test_pattern_blue50 when pal50_select_internal='1' else
                      test_pattern_bluevga60 when vga60_select_internal='1'
                      else test_pattern_blue60;
  
  process (clock81,clock27) is
    variable colour_phase_sine : integer;
    variable colour_phase_cosine : integer;
  begin

    if rising_edge(clock81) then

      if interlace_mode='1' then
        interlace_mode_integer <= 1;
      else
        interlace_mode_integer <= 0;
      end if;
      
      if debug_forward /= last_debug_forward then
        last_debug_forward <= debug_forward;
        if mono_mode='0' then
          if debug_offset_v < (256-32) then
            debug_offset_v <= debug_offset_v + 32;
          end if;
        else
          if debug_offset_u < (256-32) then
            debug_offset_u <= debug_offset_u + 32;
          end if;
        end if;
      elsif debug_backward /= last_debug_backward then
        last_debug_backward <= debug_backward;
        if mono_mode='0' then
          if debug_offset_v > 0 then
            debug_offset_v <= debug_offset_v - 32;
          end if;
        else
          if debug_offset_u > 0 then
            debug_offset_u <= debug_offset_u - 32;
          end if;
        end if;
      end if;
      
      -- Generate PAL and NTSC colour carrier phase
      pal_colour_phase <= pal_colour_phase + pal_colour_phase_add + to_integer(pal_colour_phase_sub(32 downto 32));
      pal_colour_phase_sub <= ("0"&pal_colour_phase_sub(31 downto 0)) + ("0"&pal_colour_phase_add_sub);
      ntsc_colour_phase <= ntsc_colour_phase + ntsc_colour_phase_add + to_integer(ntsc_colour_phase_sub(32 downto 32));
      ntsc_colour_phase_sub <= ("0"&ntsc_colour_phase_sub(31 downto 0)) + ("0"&ntsc_colour_phase_add_sub);
      
      if pal50_select_internal='0' then
        if field_is_odd=0 then
          vblank_train_len_adjust <= 3;
        else
          vblank_train_len_adjust <= 3;
        end if;
      else
        if interlace_mode='1' then
          if field_is_odd=0 then
            vblank_train_len_adjust <= 1;
          else
            vblank_train_len_adjust <= 1;
          end if;
        else
          vblank_train_len_adjust <= 0;
        end if;
      end if;
      
--  report "PIXEL strobe = " & std_logic'image(pixel_strobe_50) & ", "
--    & std_logic'image(pixel_strobe_vga60) & ", " 
--    & std_logic'image(pixel_strobe_60);

      y_zero_last <= y_zero_int;
      if y_zero_int = '1' and y_zero_last='0' then
        report "Start of frame detected. field_is_odd was " & integer'image(field_is_odd);
        -- Start of new frame -- toggle field_is_odd
        -- Interlace mode controls if we always show the same field or alternate
        -- XXX mono_mode for debug currently selects which of those two fields
        -- will be shown in non-interlace mode
        if mono_mode='0' then
          if field_is_odd = 1 and interlace_mode='1' then
            report "Setting field_is_odd to 0";
            field_is_odd <= 0;
          else
            report "Setting field_is_odd to 1";
            field_is_odd <= 1;
          end if;
        else
          if field_is_odd = 0 and interlace_mode='1' then
            report "Setting field_is_odd to 1";
            field_is_odd <= 1;
          else
            report "Setting field_is_odd to 0";
            field_is_odd <= 0;
          end if;
        end if;
        raster_number <= to_unsigned(0,10);
      end if;
      new_raster <= '0';
      x_zero_last <= x_zero_int;
      if x_zero_int = '1' and x_zero_last='0' then
--        report "RASTER DETECT: number = " & integer'image(to_integer(raster_number)) & ", field_is_odd=" & integer'image(field_is_odd);
        -- Start of new raster in 31KHz domain
        -- Work out if we need to start buffering this raster.
        -- Also check if we need to flip raster buffers.
        raster_number <= raster_number + 1;
        new_raster <= '1';
        new_raster_toggle <= not new_raster_toggle;
      end if;
      if new_raster='1' then
--        report "new_raster";
        if (raster_number(0)='1' and field_is_odd=1) or
          (raster_number(0)='0' and field_is_odd=0)  then
          report "Buffering 31KHz raster #" & integer'image(to_integer(raster_number))
            & " in buf " & std_logic'image(not buffer_target_31khz);
          -- Work out which buffer to write to
          buffering_31khz <= '1';
          buffer_target_31khz <= not buffer_target_31khz;
          raster15khz_waddr <= 0;
        end if;
        
      end if;

      -- Update 15KHz composite raster buffer write and read addresses.
      -- We update the read address only every other pixel, because the data
      -- rate is half.
      if raster15khz_waddr_inc = '1' then
        raster15khz_waddr_inc <= '0';
        if raster15khz_waddr < 719 then
          raster15khz_waddr <= raster15khz_waddr + 1;
        end if;
        if raster15khz_waddr = 719 then
          -- Clear write enable lines once we have written the whole raster.
          raster15khz_buf0_we <= '0';
        end if;        
      end if;

      cv_hsync_last <= cv_hsync;
      if cv_hsync='1' then
        cv_active_area <= '0';
      end if;
      if cv_hsync='0' and cv_hsync_last='1' then
        raster15khz_subpixel_counter <= 0;
        raster15khz_raddr <= 0;
        pixel_num <= 3;

        -- Suppress colour bursts for the indicated number of raster lines
        if colour_burst_mask_count /= 0 then
          colour_burst_mask_count <= colour_burst_mask_count - 1;
          colour_burst_mask <= '0';
        else
          colour_burst_mask <= '1';
        end if;
        
        -- Implement the Phase Alternation that gives PAL its name
        -- XXX Why do we need to add 64 to get the colour spaces right?
        if pal_phase_offset = 96 then -- 96 hexadegrees = 135 degrees
          pal_phase_offset <= 160; -- 160 hexadegrees = 225 degrees
          pal_v_invert <= 128;
        else
          pal_phase_offset <= 96;
          pal_v_invert <= 0;
        end if;
        
        -- Wait 8 usec from release of composite HSYNC
        -- 8usec @ 81MHz = 648 cycles.
        -- But then we divide by 6 to get 13.5MHz pixel clock ticks
        -- 648 / 6 = 108
        -- Sanity check: 108 + 720 = 828, which is just under the full width of
        -- the raster.  If it turns out to be too late in the raster, we can easily
        -- pull it back by reducing this value.
        -- We can also use this counter to time when stop and start the colour
        -- burst.
        raster15khz_skip <= 108;
      else
        if raster15khz_subpixel_counter /= pixel_widths(pixel_num) then
          raster15khz_subpixel_counter <= raster15khz_subpixel_counter + 1;
        else
          -- Update the pixel num for determining if the pixels are 5 or 6 clocks
          -- wide. This is used to fit the 720H into 640H timing, so that we still
          -- get a front-porch after the active part of the raster.
          if pixel_num < 2 then
            pixel_num <= pixel_num + 1;
          else
            pixel_num <= 0;
          end if;
          raster15khz_subpixel_counter <= 0;
          if raster15khz_skip /= 0 then
            pixel_num <= 3;
            raster15khz_skip <= raster15khz_skip - 1;
            raster15khz_raddr <= 0;
            pixel_num <= 0;
            if raster15khz_skip = 1 then
              report "15KHZ RASTER: Start of pixel data";
              pixel_num <= 0;
              if cv_vsync='0' and cv_vsync_row=0 then
                cv_active_area <= '1';
              end if;
            end if;

            if raster15khz_skip = 80 then
              -- Begin colour burst
              colour_burst_en <= '1';
              -- DO NOT Reset colour burst phase
              -- Yes, all the documentation makes it sound like you have to,
              -- but in fact you MUST NOT, or else the PLL in the receiver
              -- will never keep track.
            end if;
            if raster15khz_skip = 16 then
              -- End colour burst
              colour_burst_en <= '0';
            end if;
          else
            -- Allow raddr to go to 720, so that we know when we are in the
            -- front porch after the active part of the raster.
            if raster15khz_raddr < 720 then
              raster15khz_raddr <= raster15khz_raddr + 1;
              if raster15khz_raddr = 718 then
                report "15KHZ RASTER: end of raster reached";
              end if;
            end if;
          end if;
        end if;
      end if;
      
      -- Update the write address into the 31KHz to 15KHz raster buffer
      -- This has to come before the code that resets raster15khz_waddr when
      -- HSYNC is active.
      if narrow_dataenable_internal = '1' then
        -- We are clocked at 81MHz, and the video stream is 27MHz, so every 3rd
        -- cycle bump the write address into the 31KHz to 15KHz raster buffer.
        -- But only write alternate rasters.
        if raster31khz_subpixel_counter /= 2 then
          raster31khz_subpixel_counter <= raster31khz_subpixel_counter + 1;
        else
          raster31khz_subpixel_counter <= 0;

--          if (raster15khz_waddr mod 72) = 71 then
--            report "PIXEL #" & integer'image(raster15khz_waddr);
--          end if;
          
          if buffering_31khz='1' then
            -- Write it to the buffer
            waddr_inc_toggle <= not waddr_inc_toggle;
            raster15khz_waddr_inc <= '1';
            raster15khz_buf0_we <= '1';
            if raster15khz_waddr = 719 then
--              report "Buffered 720 pixels for the raster";
              buffering_31khz <= '0';
            end if;
          end if;
        end if;
      end if;      
      
      -- Determine width of 31KHz HSYNC pulses to use as timing aid for
      -- 15KHz short and long sync pulses
      if hsync_uninverted_int = '1' then
        -- Also reset write address for 31KHz to 15KHz pixel buffer
        raster15khz_waddr <= 0;
        if raster15khz_waddr /= 0 then
          -- Also toggle whether we are recording this raster or not.
          raster15khz_active_raster <= not raster15khz_active_raster;
        end if;
      end if;

      cv_vsync_last <= cv_vsync;
      -- Determine where we are in the VSYNC line
      -- XXX cv_vsync needs to start a couple of rasters early
      -- to allow for the pre- long sync lines
      -- PAL uses 8 rasters for the VSYNC train, while NTSC uses 9
      if (cv_vsync = '1') or ( (cv_vsync_row > 0) and (cv_vsync_row /= (7 + vblank_train_len_adjust) ) ) then
        if pal50_select_internal='1' then
          -- PAL : Lines 863 cycles long. 863 / 16 = 56.something
          -- multiply by 16, since no lower common divisor
          -- But we need to fudge things a little for some reason, so use 868
          if vsync_xpos_sub < (859*3-1) then
            vsync_xpos_sub <= vsync_xpos_sub + 16;
          else
            vsync_xpos_sub <= vsync_xpos_sub - (859*3-1);
            if vsync_xpos /= vsync_xpos_max then
              vsync_xpos <= vsync_xpos + 1;
            else
              vsync_xpos <= 0;
              if cv_vsync_row < 10 then
                cv_vsync_row <= cv_vsync_row + 1;
              end if;

              if cv_vsync_row = 1 then
                -- Set PAL V invert based on which field we are in
                if interlace_mode='0' then
                  -- For non-interlaced mode, all fields are the same
                  -- Suppress colour burst on the first raster of the frame
                  -- according to Demystifying Video 4th Ed Fig 8.18
                  colour_burst_mask_count <= 5 + 1;
                else
                  pal_phase_offset <= 160;
                  pal_v_invert <= 128;
                  colour_burst_mask_count <= 5 + 1;                  
                end if;
              end if;
              
            end if;
          end if;          
        else
          -- NTSC : lines 858 cycles long. 858 / 16 = 53.625
          -- We are clocked at 81 rather than 27MHz, so multiply
          -- by 3.
          -- Multiply by 8 to get 429
          if vsync_xpos_sub < (429*3-8) then
            vsync_xpos_sub <= vsync_xpos_sub + 8;
          else
            vsync_xpos_sub <= vsync_xpos_sub - (429*3 - 8);
            if vsync_xpos /= vsync_xpos_max then
              vsync_xpos <= vsync_xpos + 1;
            else
              vsync_xpos <= 0;
              if cv_vsync_row < 10 then
                cv_vsync_row <= cv_vsync_row + 1;
              end if;
            end if;
          end if;
        end if;
        if pal50_select_internal='1' then
          -- PAL
          if interlace_mode='0' then
              cv_sync <= not pal_progressive_vblanks(cv_vsync_row)(vsync_xpos_max - vsync_xpos);
          else
            if field_is_odd=1 then
              cv_sync <= not pal_odd_vblanks(cv_vsync_row)(vsync_xpos_max - vsync_xpos);
            else
              cv_sync <= not pal_even_vblanks(cv_vsync_row)(vsync_xpos_max - vsync_xpos);
            end if;
          end if;
        elsif vga60_select_internal='1' then
          -- XXX VGA60 -- not tested
          cv_sync <= not pal_odd_vblanks(cv_vsync_row)(vsync_xpos_max - vsync_xpos);
        else
          -- NTSC
          if field_is_odd=1 then
            cv_sync <= not ntsc_odd_vblanks(cv_vsync_row)(vsync_xpos_max - vsync_xpos);
            -- Abort last NTSC VSYNC line in odd field early, so that we get
            -- the correct signal timing
          else
            cv_sync <= not ntsc_even_vblanks(cv_vsync_row)(vsync_xpos_max - vsync_xpos);
          end if;
        end if;

        cv_sync_hsrc <= '0';        
      else
        cv_sync_hsrc <= '1';
        cv_sync <= cv_hsync;
        cv_vsync_row <= 0;
        -- End of VSYNC
        vsync_xpos <= 0;
        -- Correct phase difference of VSYNC pulse train
        if pal50_select_internal='0' then
          -- NTSC
          vsync_xpos_sub <= 288;
        else
          -- PAL
          vsync_xpos_sub <= 990;
        end if;
      end if;
      if cv_vsync = '1' and cv_vsync_last ='0' then
        -- Start of VSYNC
        cv_vsync_counter <= 0;
        -- And update whether we are in the odd or even field
        cv_field <= not cv_field;
      elsif vsync_uninverted_int = '1' then
        cv_vsync_counter <= cv_vsync_counter + 1;
      end if;
      if vsync_uninverted_int = '0' and cv_vsync_counter /= 0 then
        cv_vsync_counter <= cv_vsync_counter - 1;
      end if;
      -- Compute final composite VSYNC signal, applying a delay correction
      -- to fix the difference in propoagation of the HSYNC and VSYNC signals
      -- during 31KHz to 15KHz conversion.  The 6 cycle delay is exactly one
      -- 15KHz pixel duration.
      if cv_vsync_counter >= cv_vsync_delay then
        cv_vsync <= '1';
        -- Extend the VSYNC signal by cv_vsync_delay cycles.
        -- We need 2x that in the counter to also cover the lead-in to the
        -- count down that happens as soon as cv_vsync_counter <= cv_vsync_delay
        cv_vsync_extend <= cv_vsync_delay + cv_vsync_delay;
      elsif cv_vsync_extend /= 0 then
        cv_vsync_extend <= cv_vsync_extend - 1;
      else
        -- Clear 15KHz VSYNC, but not until cv_hsync is going (or already) low
        -- (either can be the case, depending whether we are in the odd or
        -- even field, and PAL or NTSC).
        if cv_hsync='0' then
          cv_vsync <= '0';       
        end if;
      end if;

      
      if pal50_select_internal='1' then
--        report "x_zero=" & std_logic'image(x_zero_pal50)
--          & ", y_zero=" & std_logic'image(y_zero_pal50);
      else
--        report "x_zero = " & std_logic'image(x_zero_ntsc60)
--          & ", y_zero = " & std_logic'image(y_zero_ntsc60);
      end if;       
      
      -- Update component video signals
      if cv_sync = '1' then
        luma_drive <= to_unsigned(0,10);
      else
        if colour_burst_en='1' and colour_burst_mask='1' and mono_mode='0' then
          -- PAL colour burst should have amplitude 1/2 that of the sync level.
          -- Sync = 80, so burst amplitude should be about +/- 40.
          if pal50_select_internal='1' then
            luma_drive <= unsigned(signed(px_luma(15 downto 6))
                                   + sine_table(to_integer((pal_colour_phase + pal_phase_offset) mod 256)) / 2
                                   + sine_table(to_integer((pal_colour_phase + pal_phase_offset) mod 256)) / 4
                                   );
          else
            luma_drive <= unsigned(signed(px_luma(15 downto 6))
                                   + sine_table(to_integer(ntsc_colour_phase)) /2
                                   + sine_table(to_integer(pal_colour_phase)) / 4
                                   );
          end if;
        else
          -- Don't modulate colour over sync periods
          luma_drive <= px_luma(15 downto 6);
        end if;
      end if;

      -- Calculate chroma signal from px_u and px_v
      -- Multiply px_u by sine(colour phase)
      -- Multiply px_v by cosine(colour phase) = sine(colour phase + $40)
      -- We also have to adjust the phase by the fixed line phase, which is
      -- either 135 or 225 degress (96 or 160 hexadegrees).
      if pal50_select_internal='1' then
        colour_phase_sine := (to_integer(pal_colour_phase) + debug_offset_u) mod 256;
        colour_phase_cosine := (to_integer(pal_colour_phase) + 64 + pal_v_invert + debug_offset_v) mod 256;
      else
        colour_phase_sine := to_integer(ntsc_colour_phase);
        colour_phase_cosine := (to_integer(ntsc_colour_phase) + 64) mod 256;
      end if;

      debug_angle <= (colour_phase_sine - colour_phase_cosine) mod 256;
      debug_sine <= colour_phase_sine;
      debug_cosine <= colour_phase_cosine;

      if cv_active_area = '1' then
        chroma_drive <= 0
                        + to_signed(to_integer(px_u(15 downto 8)) * sine_table(colour_phase_sine),16)
                        + to_signed(to_integer(px_v(15 downto 8)) * sine_table(colour_phase_cosine),16)
                        ;
      else
        chroma_drive <= to_signed(0,16);
      end if;                           

      -- Generate final composite signals
      -- XXX Allow switching between composite and component video?
      if mono_mode='1' or cv_sync='1' then
        -- No colour info if mono, or during sync pulses
        luma <= luma_drive(9 downto 2);
      else
        luma <= unsigned(signed(luma_drive(9 downto 2)) + to_integer(chroma_drive(15 downto 8)));
      end if;
      composite <= unsigned(signed(luma_drive(9 downto 2)) + to_integer(chroma_drive(15 downto 8)));
      -- Dedicated chroma signal has full amplitude, for now at least.
      chroma <= unsigned(chroma_drive(15 downto 8));

    end if;    
    
    if rising_edge(clock27) then

      -- Calculate luma value.
      -- Y = 0.3UR + 0.59UG + 0.11UB
      -- Dynamic range for luma is 0.7 x 256 = 179.2. But as we must support
      -- 4-bit DAC output, we need to reserve the full range from 0V to 0.3V for
      -- the SYNC signal. This means that the bottom 80 values are used for that,
      -- leaving 256 - 80 = 176 for the full dynamic range.
      -- This means that we need the Y value to be in the range 0 to 175.
      --
      -- Actually, we also need to allow for headroom for colour modulation, too.
      -- And NTSC has a higher black level, which trims it further for NTSC.
      --
      -- Allowing for +37 maximum colour amplitude, this reduces our available
      -- range to 176 - 37 = 139 for PAL, and 176 - 14 (increased black level)
      -- - 37 = 125 for NTSC.
      --
      -- This means we scale the Y value by x0.543 for PAL and x0.488 for NTSC.
      -- This results in revised Y formulas of:
      --
      -- PAL:
      -- Y = 0.163R + 0.32G + 0.06B
      -- Scaled up x256, this means:
      -- Y = 42R + 82G + 15B
      -- This gets a maximum Y of exactly 139.
      --
      -- NTSC:
      -- Y = 0.146R + 0.288G + 0.05B
      -- Scaled up x256, this means:
      -- Y = 37R + 74G + 14B
      -- This gets a maximum Y of exactly 125.
      --
      -- To save hardware, we calculate these values using shifts
      --
      -- NTSC: scale by x0.488
      if pal50_select_internal='1' then
        if cv_active_area='0' then
          px_luma <= to_unsigned(80*256,16); -- sync offset
        else
          -- Black level of PAL is at the sync level, which is ~30%
          px_luma <=
            to_unsigned(80*256,16) -- sync offset
            -- 42 = 0101010
            + ("000" & cv_red&"00000") + ("00000" & cv_red&"000") + ("0000000" & cv_red & "0")
            -- 82 = 1010010
            + ("0" & cv_green&"000000") + ("0000" & cv_green&"0000") + ("0000000" & cv_green&"0")
            -- 15 = 0001111
            + ("00000" & cv_blue & "000") + ("000000" & cv_blue&"00") + ("0000000" & cv_blue&"0") + ("00000000" & cv_blue)
            ;
        end if;
      else
        if cv_active_area='0' then
          px_luma <= to_unsigned(93*256,16); -- sync offset
        else
        -- Black level of NTSC is 7.5/140 = 5.4% above sync level
        -- Thus we have to use a slightly compacted luminance range compared
        -- with PAL, to keep below the limit.
          px_luma <=
            to_unsigned(93*256,16) -- sync offset
            -- 37 = 0100101
            + ("000" & cv_red&"00000") + ("000000" & cv_red&"00") + ("00000000" & cv_red)
            -- 74 = 1001010
            + ("0" & cv_green&"000000") + ("00000" & cv_green&"000") + ("0000000" & cv_green&"0")
            -- 14 = 0001110
            + ("00000" & cv_blue & "000") + ("000000" & cv_blue&"00") + ("0000000" & cv_blue&"0")
            ;
        end if;
      end if;

      -- Then we do it all again for U and V.
      -- U and V can be positive or negative, so we need an extra bit of
      -- precision, and then just offset things, so that it stays in range
      -- 
      -- U = – 0.147R – 0.289G + 0.436B = 0.492 (B – Y)
      -- V = 0.615R – 0.515G – 0.100B = 0.877(R´ – Y)
      --
      -- We want the full-amplitude to be +/- 24.
      -- Experimentation yields a scaling factor of x100 to get this
      -- about right
      -- U = ( - 0.08R - 0.157G + 0.237B ) x 100 = - 8R - 15G + 24B
      -- V = ( 0.334R - 0.280G - 0.0543B ) x 100 = 24R - 20G - 4B
      -- 
      px_u <= to_signed(0,16)
              -- -8  R = 01000
              - to_integer(cv_red&"000")
              -- -15 G = 01111
              - to_integer(cv_green&"0000") - to_integer(cv_green) 
              -- +24 B = 11000
              + to_integer(cv_blue & "00000") + to_integer(cv_blue&"0000")
              ;
      px_v <= to_signed(0,16)
              -- +18R = 10010
              + to_integer(cv_red & "00000") + to_integer(cv_red&"0")
              -- -15G = 01111
              - to_integer(cv_green & "0000") - to_integer(cv_green)
              -- -3B  = 00011
              - to_integer(cv_blue & "0") - to_integer(cv_blue)
              ;

      -- Generate half-rate composite video pixel toggle
      cv_pixel_strobe <= cv_pixel_toggle;
      cv_pixel_toggle <= not cv_pixel_toggle;
      
      pal50_select_internal_drive <= pal50_select;
      pal50_select_internal <= pal50_select_internal_drive;

      vga60_select_internal_drive <= vga60_select;
      vga60_select_internal <= vga60_select_internal_drive;

      test_pattern_enable120 <= test_pattern_enable;
      
      -- Output the pixels or else the test pattern
      if fullwidth_dataenable_internal='0' then        
        red_o <= x"00";
        green_o <= x"00";
        blue_o <= x"00";
      elsif test_pattern_enable120='1' then
        red_o <= test_pattern_red;
        green_o <= test_pattern_green;
        blue_o <= test_pattern_blue;
      else
        red_o <= red_i;
        green_o <= green_i;
        blue_o <= blue_i;
      end if;

      if cv_sync = '0' and cv_vsync='0' then
        -- Read 15KHz composite RGB data from buffer
        -- Some monitors / TVs can't handle 720 pixel clocks worth of image,
        -- and use some of it to normalise the intensity of the raster, causing
        -- rasters that have stuff in the left few pixels to appear darker.
        -- To deal with this, we just skip the first few pixels on the raster.
        -- This is not ideal, but so long as the skipped pixels are narrower than
        -- the border, in theory it should be ok -- provided that the monitor/TV
        -- doesn't eat the left columns of text.
        if (time_since_last_pixel /= 1023) and (raster15khz_raddr > 2) and (raster15khz_raddr < 720) then
          -- Gamma correct RGB before processing
          -- PAL uses NTSC curves these days, too
          if gamma_enabled='1' then
            cv_red <= ntsc_gamma(to_integer(raster15khz_rdata(7 downto 0)));
            cv_green <= ntsc_gamma(to_integer(raster15khz_rdata(15 downto 8)));
            cv_blue <= ntsc_gamma(to_integer(raster15khz_rdata(23 downto 16)));
          else
            cv_red <= raster15khz_rdata(7 downto 0);
            cv_green <= raster15khz_rdata(15 downto 8);
            cv_blue <= raster15khz_rdata(23 downto 16);
          end if;
        else
          -- Assume we are in VBLANK
          -- XXX Teletext and closed captions go in these lines
          cv_red <= x"00";
          cv_green <= x"00";
          cv_blue <= x"00";
        end if;
      elsif cv_sync = '0' and cv_vsync='1' then
        -- Between SYNC pulses during vertical blank,
        -- relax to black level
        cv_red <= x"00";
        cv_green <= x"00";
        cv_blue <= x"00";
      else
        cv_red <= x"00";
        cv_green <= x"00";
        cv_blue <= x"00";
      end if;
      
      if narrow_dataenable_internal='0' then        
        red_no <= x"00"; 
        green_no <= x"00";
        blue_no <= x"00";

        if time_since_last_pixel < 1023 then
          time_since_last_pixel <= time_since_last_pixel + 1;
        end if;        
      elsif test_pattern_enable120='1' then
        red_no <= test_pattern_red;
        green_no <= test_pattern_green;
        blue_no <= test_pattern_blue;
        
        raster15khz_wdata(7 downto 0) <= test_pattern_red;
        raster15khz_wdata(15 downto 8) <= test_pattern_green;
        raster15khz_wdata(23 downto 16) <= test_pattern_blue;

        -- XXX DEbug colour subcarrier generation
--        raster15khz_wdata(7 downto 0) <= to_unsigned(0,8);
--        raster15khz_wdata(15 downto 8) <= to_unsigned(255,8);
--        raster15khz_wdata(23 downto 16) <= to_unsigned(0,8);
        
        
        time_since_last_pixel <= 0;
      else
        red_no <= red_i;
        green_no <= green_i;
        blue_no <= blue_i;

        -- Write 31KHz RGB data into buffer for later playback on 15KHz
        -- composite output
        raster15khz_wdata(7 downto 0) <= red_i;
        raster15khz_wdata(15 downto 8) <= green_i;
        raster15khz_wdata(23 downto 16) <= blue_i;

        time_since_last_pixel <= 0;        
      end if;

    end if;

  end process;

end greco_roman;
