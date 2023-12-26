--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2014
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
----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    19:11:30 01/02/2014
-- Design Name:
-- Module Name:    vga - Behavioral
-- Project Name:
-- Target Devices:
-- Tool versions:
-- Description:
--
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.victypes.all;
use work.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity viciv is
  generic (
    chipram_size : integer := 393216;
    hyper_installed : boolean := false
    );
  Port (
    all_pause : in std_logic;

    hypervisor_mode : in std_logic;

    hw_errata_level : in unsigned(7 downto 0);
    hw_errata_enable_toggle : inout std_logic := '0';
    hw_errata_disable_toggle : inout std_logic := '0';

    xcounter_out : out integer range 0 to 4095 := 0;
    ycounter_out : out integer range 0 to 2047 := 0;
    ----------------------------------------------------------------------
    -- dot clock
    ----------------------------------------------------------------------
    pixelclock : in  STD_LOGIC;
    ----------------------------------------------------------------------
    -- CPU clock (used for chipram and fastio interfaces)
    ----------------------------------------------------------------------
    cpuclock : in std_logic;

    -- CPU IRQ
    irq : out std_logic;

    reset : in std_logic;

    dd00_bits : in unsigned(1 downto 0);

    upscale_enable : out std_logic := '0';

    -- Touch event to simulate light pen
    touch_x : in unsigned(13 downto 0);
    touch_y : in unsigned(11 downto 0);
    touch_active : in std_logic := '0';

    -- Internal drive LED status for OSD
    led : in std_logic;
    motor : in std_logic;

    -- Actual drive LED (including blink status) for keyboard
    -- (the F011 does this on a real C65)
    drive_led_out : out std_logic;

    vicii_2mhz : out std_logic;
    viciii_fast : out std_logic;
    viciv_fast : out std_logic;

    viciv_frame_indicate : out std_logic := '0';

    interlace_mode : out std_logic := '0';
    mono_mode : out std_logic := '0';

    -- Used to tell the CPU when to steal cycles to simulate badlines
    badline_toggle : out std_logic := '0';
    vicii_raster_out : out unsigned(11 downto 0) := to_unsigned(0,12);

    d031_written : out std_logic;
    xray_mode : in std_logic;
    test_pattern_enable : buffer std_logic := '0';

    dat_even : out std_logic;
    dat_offset : out unsigned(15 downto 0);
    dat_bitplane_bank : out unsigned(2 downto 0) := "000";
    dat_bitplane_addresses : out sprite_vector_eight;

    -- Used to synchronise our frame with an external frame generator
    -- (Used to provide stable frame generation for LCD displays, as well
    -- as to support a genlock input).
    external_frame_x_zero : in std_logic;
    external_frame_y_zero : in std_logic := '0';
    -- Similarly, we get told when we should be presenting a new pixel, so
    -- that we don't have to figure out all the fiddly timing ourselves
    external_pixel_strobe_in : in std_logic := '0';

    ----------------------------------------------------------------------
    -- VGA output
    ----------------------------------------------------------------------
    vsync_polarity : out  STD_LOGIC := '0';
    hsync_polarity : out  STD_LOGIC := '0';
    pal50_select : out std_logic := '0';
    vga60_select : out std_logic := '0';

    lcd_pixel_strobe : out std_logic;
    vga_in_frame : in std_logic;
    vgared : out  UNSIGNED (7 downto 0);
    vgagreen : out  UNSIGNED (7 downto 0);
    vgablue : out  UNSIGNED (7 downto 0);
    viciv_outofframe : out std_logic := '0';

    pixel_stream_out : out unsigned (7 downto 0);
    pixel_red_out : out unsigned (7 downto 0);
    pixel_green_out : out unsigned (7 downto 0);
    pixel_blue_out : out unsigned (7 downto 0);
    pixel_y : out unsigned (11 downto 0) := (others => '0');
    pixel_x_out : out integer := 0;
    pixel_strobe_out : out std_logic;
    pixel_newframe : out std_logic;
    pixel_frame_toggle : buffer std_logic;
    pixel_newraster : out std_logic;
    -- Pixel x counter scaled to count to about 640
    pixel_x_640 : out integer := 0;
    -- And as above, but with the 800 pixel resolution.
    pixel_x_800 : out integer := 0;
    -- And pixel X counter scaled to actual video mode (typically 800)
    -- (and corrected for video pipeline depth)
    -- This one holds at zero until the first VIC-II/III sprite position in the
    -- left border.
    native_x_640 : out integer := 0;
    native_y_200 : out integer := 0;
    native_y_400 : out integer := 0;
    -- Scale for 200 and 400px high modes (used by compositors)
    pixel_y_scale_400 : out unsigned(3 downto 0) := (others => '0');
    pixel_y_scale_200 : out unsigned(3 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- CPU Interface to ChipRAM in video controller (allow upto 1MB)
    ---------------------------------------------------------------------------
    --chipram_we : IN STD_LOGIC;
    chipram_address : OUT unsigned(19 DOWNTO 0);
    chipram_datain : IN unsigned(7 DOWNTO 0);

    ---------------------------------------------------------------------------
    -- Direct interface to HyperRAM for fetching 256 colour glyph data etc
    ---------------------------------------------------------------------------
    hyper_addr : out unsigned(18 downto 3) := (others => '0');
    hyper_request_toggle : out std_logic := '0';
    hyper_data_in : in unsigned(7 downto 0) := x"00";
    hyper_data_strobe_in : in std_logic := '0';

    -----------------------------------------------------------------------------
    -- FastIO interface for accessing video registers
    -----------------------------------------------------------------------------
    fastio_addr : in std_logic_vector(19 downto 0);
    fastio_read : in std_logic;
    fastio_write : in std_logic;
    fastio_wdata : in std_logic_vector(7 downto 0);
    fastio_rdata : out std_logic_vector(7 downto 0);
    colour_ram_fastio_rdata : out std_logic_vector(7 downto 0);
    colour_ram_cs : in std_logic;
    charrom_fastio_rdata : out std_logic_vector(7 downto 0);
    charrom_cs : in std_logic;

    viciii_iomode : out std_logic_vector(1 downto 0) := "11";

    iomode_set : in std_logic_vector(1 downto 0);
    iomode_set_toggle : in std_logic;

    colourram_at_dc00 : out std_logic := '0';
    rom_at_e000 : out std_logic;
    rom_at_c000 : out std_logic;
    rom_at_a000 : out std_logic;
    rom_at_8000 : out std_logic
    );
end viciv;

architecture Behavioral of viciv is

  signal reset_drive : std_logic := '0';

  signal bitplane_bank_select : unsigned(2 downto 0) := "000";

  signal iomode_set_toggle_last : std_logic := '0';

  signal before_y_chargen_start : std_logic := '1';
  signal justbefore_y_chargen_start : std_logic := '0';
  signal stop_chargen_raster_counter : unsigned(7 downto 0) := x"00";
  signal stop_chargen_delay : unsigned(7 downto 0) := to_unsigned(3,8);

  signal vicii_2mhz_internal : std_logic := '1';
  signal viciii_fast_internal : std_logic := '1';
  signal viciv_fast_internal : std_logic := '1';
  signal viciv_bitplane_chargen_on : std_logic := '0';

  signal reg_xcounter_delay : integer range 0 to 31 := 4;
  signal xcounter_pipeline_delayed : integer := 0;
  signal external_pixel_strobe_log : std_logic_vector(31 downto 0) := (others => '0');
  signal sprite_h640_delayed : std_logic := '0';
  signal sprite_v400s_delayed : std_logic_vector(7 downto 0) := x"00";
  signal reg_h640_delayed : std_logic := '0';
  signal reg_h1280_delayed : std_logic := '0';
  signal external_frame_x_zero_latched : std_logic := '0';
  signal last_external_frame_x_zero_latched : std_logic := '0';
  signal last_external_frame_y_zero : std_logic := '0';

  -- last value written to key register
  signal reg_key : unsigned(7 downto 0) := x"00";

  signal last_dd00_bits : unsigned(1 downto 0) := "11";
  signal vicii_hot_regs_enable : std_logic := '1';
  signal viciv_legacy_mode_registers_touched : std_logic := '0';
  signal viciv_single_side_border_width_touched : std_logic := '0';
  signal reg_d018_screen_addr : unsigned(3 downto 0) := x"1";

  signal bump_screen_row_address : std_logic := '0';

  -- Drive stage for IRQ signal in attempt to allieviate timing problems.
  signal irq_drive : std_logic := '1';

  -- Buffer VGA signal to save some time. Similarly pipeline
  -- palette lookup.
  signal vga_buffer_red : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_buffer_green : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_buffer_blue : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_buffer2_red : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_buffer2_green : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_buffer2_blue : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_buffer3_red : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_buffer3_green : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_buffer3_blue : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_buffer4_red : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_buffer4_green : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_buffer4_blue : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_buffer5_red : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_buffer5_green : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_buffer5_blue : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_filtered_red : UNSIGNED (9 downto 0) := (others => '0');
  signal vga_filtered_green : UNSIGNED (9 downto 0) := (others => '0');
  signal vga_filtered_blue : UNSIGNED (9 downto 0) := (others => '0');
  signal vga_palin_red : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_palin_green : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_palin_blue : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_palout_red : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_palout_green : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_palout_blue : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_out_red : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_out_green : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_out_blue : UNSIGNED (7 downto 0) := (others => '0');
  signal pixel_colour : unsigned(7 downto 0) := x"00";
  signal pixel_alpha : unsigned(7 downto 0) := x"00";

  -- Select which of the four video modes to use at any point in time.
  signal vicii_ntsc : std_logic := '1';
  signal vga60_select_internal : std_logic := '0';

  -- Video mode definition
  -- NOTE: These get overwritten by $D06F PAL/NTSC flags
  -- The values here are simply those that apply on power up.
  -- NOTE: frame_h_front is deprecated due to the pixel_driver now?
  -- In any case, it seems to cause the trimming of frame_h_front pixels
  constant frame_h_front : unsigned(7 downto 0) := to_unsigned(0,8);
  -- 800x480 @ 50Hz for 100MHz pixelclock
  signal single_side_border : unsigned(13 downto 0) := to_unsigned(80,14);
  constant display_width : unsigned(11 downto 0) := to_unsigned(800,12);
  -- We double-buffer the rendering of chargen raster data, so that we can begin
  -- the fetch early.  We just need to allow a few pixels after xcount=0 to let
  -- things get started.
  -- (Sprite fetching should happen as soon as the border begins, so that we have
  -- maximum time to do the fetch.)
  constant display_fetch_start : unsigned(11 downto 0) := to_unsigned(719,12);
  constant display_height_pal : unsigned(11 downto 0) := to_unsigned(623-20,12);
  constant display_height_ntsc : unsigned(11 downto 0) := to_unsigned(526-20,12);
  signal display_height : unsigned(11 downto 0);
  signal raster_buffer_half_toggle : std_logic := '0';
  signal vicii_ycounter_scale_minus_zero : unsigned(3 downto 0) := to_unsigned(2-1,4);
  signal chargen_x_scale : unsigned(7 downto 0) := to_unsigned(120,8);
  signal sprite_first_x : unsigned(13 downto 0) := to_unsigned(31,14);
  signal sprite_y_adjust : unsigned(7 downto 0) := to_unsigned(0,8);
  signal sprite_x_counting : std_logic := '0';
  signal sprite_x_scale_toggle : std_logic := '0';
  -- Each character pixel will be (n+1) pixels high
  signal chargen_y_scale : unsigned(7 downto 0) := x"01";  -- x"04"
  -- smooth scrolling position in natural pixels.
  -- Set in the same way as the border
  signal x_chargen_start : unsigned(13 downto 0) := to_unsigned(safe_to_integer(frame_h_front),14);

  -- PAL/NTSC raster layout
  signal vicii_first_raster : unsigned(8 downto 0) := to_unsigned(0,9);
  constant ntsc_max_raster : unsigned(8 downto 0) := to_unsigned(262,9);
  constant pal_max_raster : unsigned(8 downto 0) := to_unsigned(312,9);
  signal vicii_max_raster : unsigned(8 downto 0) := pal_max_raster;
  -- Setting this value positive causes the chargen and screen to move down the
  -- screen relative to the VIC-II raster counter.
  constant raster_correction : integer := 3;

  -- Calculated dynamically
  signal x_end_of_raster : unsigned(13 downto 0) := to_unsigned(0,14);
  signal vicii_ycounter_scale : unsigned(3 downto 0) := to_unsigned(0,4);

  constant frame_v_front : integer := 1;

  -- Frame generator counters
  -- DEBUG: Start frame at a point that will soon trigger a badline
  signal xcounter : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_last : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_delayed : unsigned(13 downto 0) := to_unsigned(0,14);

  -- Pipeline delay for export of xcounter
  signal xcounter_17 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_16 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_15 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_14 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_13 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_12 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_11 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_10 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_9 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_8 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_7 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_6 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_5 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_4 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_3 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_2 : unsigned(13 downto 0) := to_unsigned(0,14);
  signal xcounter_1 : unsigned(13 downto 0) := to_unsigned(0,14);

  signal ycounter_last : unsigned(13 downto 0) := to_unsigned(0,14);
  signal ycounter_export_countdown : integer range 0 to 31 := 0;

  signal xcounter_drive : unsigned(13 downto 0) := (others => '0');
  signal ycounter : unsigned(11 downto 0) := to_unsigned(625,12);
  signal ycounter_drive : unsigned(11 downto 0) := (others => '0');
  signal last_ycounter : unsigned(11 downto 0) := to_unsigned(625,12);
  -- Virtual raster number for VIC-II
  -- (On powerup set to a PAL only raster so that ROM doesn't need to wait a
  -- whole frame.  This is really just to make testing through simulation quicker
  -- since a whole frame takes ~20 minutes to simulate).
  signal vicii_ycounter : unsigned(8 downto 0) := to_unsigned(0,9);
  signal vicii_ycounter_continuous : unsigned(8 downto 0) := to_unsigned(0,9);
  signal vicii_ycounter_driver : unsigned(8 downto 0) := to_unsigned(0,9);
  signal vicii_ycounter_minus_one : unsigned(8 downto 0) := to_unsigned(0,9);
  signal vicii_sprite_ycounter : unsigned(8 downto 0) := to_unsigned(0,9);

  signal vicii_ycounter_v400 : unsigned(9 downto 0) := to_unsigned(0,10);
  signal last_vicii_ycounter : unsigned(8 downto 0) := to_unsigned(0,9);
  signal vicii_ycounter_phase : unsigned(3 downto 0) := (others => '0');
  signal vicii_ycounter_max_phase : unsigned(3 downto 0) := (others => '0');
  signal vicii_ycounter_phase_v400 : unsigned(3 downto 0) := (others => '0');
  signal vicii_ycounter_max_phase_v400 : unsigned(3 downto 0) := (others => '0');
  -- Is the VIC-II virtual raster number the active one for interrupts, or
  -- are we comparing to physical rasters?  This is decided by which register
  -- gets written to last.
  signal vicii_is_raster_source : std_logic := '1';

  signal vicii_xcounter_320 : unsigned(8 downto 0) := (others => '0');
  signal vicii_xcounter_640 : unsigned(9 downto 0) := (others => '0');
  signal last_vicii_xcounter_640 : unsigned(9 downto 0) := (others => '0');

  -- Actual pixel positions in the frame
  signal displayy : unsigned(11 downto 0) := to_unsigned(0,12);

  -- Mark if we are in the top line of display
  -- (used for overlaying drive LED on first row of pixels)
  signal displayline0 : std_logic := '1';
  signal displaycolumn0 : std_logic := '1';

  -- Asserted if in the displayed part of vertical frame
  -- DEBUG: Power up with in frame to make simulation in ghdl much quicker.
  signal vert_in_frame : std_logic := '1';

  -- Used for counting down cycles while waiting for RAM to respond
  signal delay : std_logic_vector(1 downto 0) := "00";

  -- Interface to buffer for screen ram (converts 64 bits wide to 8 bits
  -- wide for us)
  signal screen_ram_buffer_write  : std_logic := '0';
  signal screen_ram_buffer_read_address : unsigned(8 downto 0) := to_unsigned(0,9);
  signal screen_ram_buffer_write_address : unsigned(8 downto 0) := to_unsigned(0,9);
  signal screen_ram_buffer_din : unsigned(7 downto 0) := x"00";
  signal screen_ram_buffer_dout : unsigned(7 downto 0) := x"00";

  -- Internal registers used to keep track of the screen ram for the current row
  signal screen_row_address : unsigned(19 downto 0) := to_unsigned(0,20);
  signal screen_row_current_address : unsigned(19 downto 0) := to_unsigned(0,20);

  signal full_colour_fetch_count : integer range 0 to 8 := 0;
  signal full_colour_data : unsigned(63 downto 0) := (others => '0');
  signal paint_full_colour_data : unsigned(63 downto 0) := (others => '0');
  signal paint_alternate_palette : std_logic := '0';

  -- chipram access management registers
  signal next_ramaddress : unsigned(19 downto 0) := to_unsigned(0,20);
  signal next_ramaccess_is_screen_row_fetch : std_logic := '0';
  signal this_ramaccess_is_screen_row_fetch : std_logic := '0';
  signal last_ramaccess_is_screen_row_fetch : std_logic := '0';
  signal final_ramaccess_is_screen_row_fetch : std_logic := '0';
  signal next_ramaccess_is_glyph_data_fetch : std_logic := '0';
  signal this_ramaccess_is_glyph_data_fetch : std_logic := '0';
  signal last_ramaccess_is_glyph_data_fetch : std_logic := '0';
  signal final_ramaccess_is_glyph_data_fetch : std_logic := '0';
  signal next_ramaccess_is_sprite_data_fetch : std_logic := '0';
  signal this_ramaccess_is_sprite_data_fetch : std_logic := '0';
  signal last_ramaccess_is_sprite_data_fetch : std_logic := '0';
  signal final_ramaccess_is_sprite_data_fetch : std_logic := '0';
  signal this_ramaccess_screen_row_buffer_address : unsigned(8 downto 0) := to_unsigned(0,9);
  signal next_ramaccess_screen_row_buffer_address : unsigned(8 downto 0) := to_unsigned(0,9);
  signal last_ramaccess_screen_row_buffer_address : unsigned(8 downto 0) := to_unsigned(0,9);
  signal final_ramaccess_screen_row_buffer_address : unsigned(8 downto 0) := to_unsigned(0,9);
  signal next_screen_row_fetch_address : unsigned(19 downto 0) := to_unsigned(0,20);
  signal this_screen_row_fetch_address : unsigned(19 downto 0) := to_unsigned(0,20);
  signal last_screen_row_fetch_address : unsigned(19 downto 0) := to_unsigned(0,20);
  signal final_screen_row_fetch_address : unsigned(19 downto 0) := to_unsigned(0,20);
  signal final_ramdata : unsigned(7 downto 0) := to_unsigned(0,8);

  signal vgared_driver : unsigned(7 downto 0) := x"00";
  signal vgablue_driver : unsigned(7 downto 0) := x"00";
  signal vgagreen_driver  : unsigned(7 downto 0) := x"00";

  signal ycounter_driver : unsigned(11 downto 0) := to_unsigned(625,12);

  -- Internal registers for drawing a single raster of character data to the
  -- raster buffer.
  signal character_number : unsigned(10 downto 0) := to_unsigned(0,11);
  type vic_chargen_fsm is (Idle,
                           FetchScreenRamLine,
                           FetchScreenRamLine2,
                           FetchScreenRamNext,
                           FetchFirstCharacter,
                           FetchNextCharacter,
                           FetchCharHighByte,
                           FetchTextCell,
                           FetchTextCellColourAndSource,
                           FetchBitmapCell,
                           FetchBitmapData,
                           PaintFullColourFetch,
                           PaintFullColourHyperRAMFetch,
                           PaintMemWait,
                           PaintMemWait2,
                           PaintMemWait3,
                           PaintDispatch,
                           EndOfChargen,
                           SpritePointerFetch,
                           SpritePointerFetch2,
                           SpritePointerCompute1,
                           SpritePointerCompute,
                           SpritePointerComputeMSB,
                           SpriteDataFetch,
                           SpriteDataFetch2);
  signal raster_fetch_state : vic_chargen_fsm := Idle;
  type vic_paint_fsm is (Idle,
                         PaintFullColour,Paint4bitColourPixels,PaintFullColourPixels,PaintFullColourDone,
                         PaintMono,PaintMonoDrive,PaintMonoBits,
                         PaintMultiColour,PaintMultiColourDrive,
                         PaintMultiColourBits,PaintMultiColourHold);
  signal paint_fsm_state : vic_paint_fsm := Idle;
  signal paint_ready : std_logic := '0';
  signal paint_from_charrom : std_logic := '0';
  signal paint_flip_horizontal : std_logic := '0';
  signal paint_foreground : unsigned(7 downto 0) := to_unsigned(0,8);
  signal paint_background : unsigned(7 downto 0) := to_unsigned(0,8);
  signal paint_mc1 : unsigned(7 downto 0) := to_unsigned(0,8);
  signal paint_mc2 : unsigned(7 downto 0) := to_unsigned(0,8);
  signal paint_buffer_hflip_chardata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal paint_buffer_noflip_chardata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal paint_buffer_hflip_ramdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal paint_buffer_noflip_ramdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal paint_buffer : unsigned(7 downto 0) := to_unsigned(0,8);
  signal paint_bits_remaining : integer range 0 to 16 := 0;
  signal paint_chardata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal paint_ramdata : unsigned(7 downto 0) := to_unsigned(0,8);

  signal horizontal_filter : std_logic := '1';
  signal pal_simulate : std_logic := '0';
  signal shadow_mask_enable : std_logic := '0';
  signal upscale_enable_int : std_logic := '0';

  signal debug_x : unsigned(13 downto 0) := "11111111111110";
  signal debug_y : unsigned(11 downto 0) := "111111111110";
  signal debug_pixel_red : unsigned(7 downto 0) := to_unsigned(0,8);
  signal debug_pixel_green : unsigned(7 downto 0) := to_unsigned(0,8);
  signal debug_pixel_blue : unsigned(7 downto 0) := to_unsigned(0,8);
  signal debug_channel_select : std_logic_vector(1 downto 0) := "00";
  signal debug_screen_ram_buffer_address : unsigned(8 downto 0) := to_unsigned(0,9);
  signal debug_raster_buffer_read_address : unsigned(7 downto 0) := to_unsigned(0,8);
  signal debug_raster_buffer_write_address : unsigned(7 downto 0) := to_unsigned(0,8);
  signal debug_cycles_to_next_card : unsigned(7 downto 0) := to_unsigned(0,8);
  signal debug_raster_fetch_state : vic_chargen_fsm := Idle;
  signal debug_paint_fsm_state : vic_paint_fsm := Idle;
  signal debug_chargen_active : std_logic := '0';
  signal debug_chargen_active_soon : std_logic := '0';
  signal debug_character_data_from_rom : std_logic := '0';
  signal debug_charaddress : unsigned(11 downto 0) := to_unsigned(0,12);
  signal debug_charrow : std_logic_vector(7 downto 0) := x"00";

  signal debug_screen_ram_buffer_address_drive : unsigned(8 downto 0) := to_unsigned(0,9);
  signal debug_cycles_to_next_card_drive : unsigned(7 downto 0) := to_unsigned(0,8);
  signal debug_raster_fetch_state_drive : vic_chargen_fsm := Idle;
  signal debug_paint_fsm_state_drive : vic_paint_fsm := Idle;
  signal debug_chargen_active_drive : std_logic := '0';
  signal debug_chargen_active_soon_drive : std_logic := '0';
  signal debug_character_data_from_rom_drive : std_logic := '0';
  signal debug_charaddress_drive : unsigned(11 downto 0) := to_unsigned(0,12);
  signal debug_charrow_drive : std_logic_vector(7 downto 0)  := x"00";
  signal debug_raster_buffer_read_address_drive : unsigned(7 downto 0) := to_unsigned(0,8);
  signal debug_raster_buffer_write_address_drive : unsigned(7 downto 0) := to_unsigned(0,8);

  signal debug_screen_ram_buffer_address_drive2 : unsigned(8 downto 0) := to_unsigned(0,9);
  signal debug_raster_buffer_read_address_drive2 : unsigned(7 downto 0) := to_unsigned(0,8);
  signal debug_raster_buffer_write_address_drive2 : unsigned(7 downto 0) := to_unsigned(0,8);
  signal debug_raster_fetch_state_drive2 : vic_chargen_fsm := Idle;
  signal debug_paint_fsm_state_drive2 : vic_paint_fsm := Idle;
  signal debug_chargen_active_drive2 : std_logic := '0';
  signal debug_chargen_active_soon_drive2 : std_logic := '0';
  signal debug_character_data_from_rom_drive2 : std_logic := '0';
  signal debug_charaddress_drive2 : unsigned(11 downto 0) := to_unsigned(0,12);
  signal debug_charrow_drive2 : std_logic_vector(7 downto 0) := x"00";

  -----------------------------------------------------------------------------
  -- Video controller registers
  -----------------------------------------------------------------------------

  -- New control registers

  -- These next two can be used to make a screen which is a huge playfield with
  -- just a portion visible at any point in time.
  -- Number added to card number for each row of characters, i.e., how many bytes
  -- should we skip as we advance each row.
  signal virtual_row_width : unsigned(15 downto 0) := to_unsigned(40,16);
  -- And display_row_width is how many characters to display on each row
  signal display_row_width : unsigned(9 downto 0) := to_unsigned(40,10);
  signal display_row_width_minus1 : unsigned(9 downto 0) := to_unsigned(40,10);
  signal display_row_count : unsigned(7 downto 0) := to_unsigned(25-1,8);
  signal display_row_number : unsigned(7 downto 0) := to_unsigned(25,8);

  signal end_of_row_16 : std_logic := '0';
  signal end_of_row : std_logic := '0';
  signal chargen_x_scale_drive : unsigned(7 downto 0) := to_unsigned(0,8);
  signal x_chargen_start_minus1 : unsigned(13 downto 0) := to_unsigned(0,14);

  -- DEBUG: Start character generator in first raster on power up to make ghdl
  -- simulation much quicker
  signal y_chargen_start : unsigned(11 downto 0) := to_unsigned(1,12);  -- 0
  signal y_chargen_start_minus_one : unsigned(11 downto 0) := to_unsigned(0,12);  --
                                                                                  --auto-calculated signal
  -- Charset is 16bit (2 bytes per char) when this mode is enabled.
  signal sixteenbit_charset : std_logic := '1';
  -- Characters >255 are full-colour blocks when enabled.
  signal fullcolour_extendedchars : std_logic := '1';
  -- Characters <256 are full-colour blocks when enabled
  signal fullcolour_8bitchars : std_logic := '1';
  -- Optionally fetch full-colour chars from HyperRAM
  signal glyphs_from_hyperram : std_logic := '0';

  -- VIC-II style Mode control bits (correspond to bits in $D016 etc)
  -- -- Text/graphics mode select
  signal text_mode : std_logic := '1';
  -- -- Basic multicolour mode bit
  signal multicolour_mode : std_logic := '0';
  -- -- Enable 256 colours in multicolour text mode
  signal fullcolour_mcm : std_logic := '0';
  -- -- Extended background colour mode (reduces charset to 64 entries)
  signal extended_background_mode : std_logic := '0';

  -- Border dimensions
  -- DEBUG: No top or left borders on power up to make ghdl simulation of frame
  -- drawing much quicker.
  signal border_x_left : unsigned(13 downto 0) := to_unsigned(0,14);
  signal border_x_right : unsigned(13 downto 0) := to_unsigned(2000,14);
  signal border_y_top : unsigned(11 downto 0) := to_unsigned(1,12);
  signal border_y_bottom : unsigned(11 downto 0) := to_unsigned(600,12);
  signal blank : std_logic := '0';
  -- intermediate calculations for whether we are in the border to improve timing.
  signal vertical_border : std_logic := '1';

  -- Colour registers ($D020 - $D024)
  signal screen_colour : unsigned(7 downto 0) := x"08";  -- orange
  signal border_colour : unsigned(7 downto 0) := x"04";  -- green
  signal multi1_colour : unsigned(7 downto 0) := x"01";  -- multi-colour mode #1
  signal multi2_colour : unsigned(7 downto 0) := x"02";  -- multi-colour mode #2
  signal multi3_colour : unsigned(7 downto 0) := x"03";  -- multi-colour mode #3
  -- XXX move reading of sprite registers to vicii_sprites module
  signal sprite_multi0_colour : unsigned(7 downto 0) := x"04";
  signal sprite_multi1_colour : unsigned(7 downto 0) := x"05";
  signal sprite_x : sprite_vector_eight := (others => x"02");
  signal sprite_y : sprite_vector_eight := (others => x"02");
  signal sprite_colours : sprite_vector_eight := (others => x"00");

  -- VIC-III bitplane registers
  signal bitplane_mode : std_logic := '0';
  signal bitplane_enables : std_logic_vector(7 downto 0) := "00000000";
  signal bitplane_complements : std_logic_vector(7 downto 0) := "00000000";
  signal bitplane_sixteen_colour_mode_flags : std_logic_vector(7 downto 0) := "00000000";
  signal bitplanes_x_start : unsigned(7 downto 0) := to_unsigned(0,8);
  signal bitplanes_y_start : unsigned(7 downto 0) := to_unsigned(0,8);
  signal bitplanes_x_start_drive : unsigned(7 downto 0) := to_unsigned(0,8);
  signal bitplanes_y_start_drive : unsigned(7 downto 0) := to_unsigned(0,8);
  signal dat_x : unsigned(6 downto 0) := to_unsigned(0,7);
  signal dat_y : unsigned(8 downto 0) := to_unsigned(0,9);
  signal dat_bitplane_offset : unsigned(15 downto 0) := x"0000";
  signal bitplane_addresses : sprite_vector_eight;
  signal max_sprite_fetch_byte_number : integer range 0 to 399 := 0;

  -- Extended sprite features
  signal sprite_extended_height_enables : std_logic_vector(7 downto 0) := "00000000";
  signal sprite_extended_height_size : unsigned(7 downto 0) := to_unsigned(21,8);
  signal sprite_extended_width_enables : std_logic_vector(7 downto 0) := "00000000";
  signal sprite_horizontal_tile_enables : std_logic_vector(7 downto 0) := "00000000";
  signal sprite_bitplane_enables : std_logic_vector(7 downto 0) := "00000000";
  signal sprite_alpha_blend_enables : std_logic_vector(7 downto 0) := "00000000";
  signal sprite_alpha_blend_value : unsigned(7 downto 0) := x"80";
  signal sprite_sixteen_colour_enables : std_logic_vector(7 downto 0) := "00000000";

  -- VIC-II sprites are in a separate module as a chain.  To avoid the need to
  -- route to all sprites from the main VIC-IV section, they are arranged as a
  -- chain.  However, the VIC-IV must perform the memory accesses for the
  -- VIC-II sprites.  Thus we have a bus that passes through each of these
  -- sprites delivering the data they need.  We also have a separate bus that
  -- delivers the current row number for each sprite so that the VIC-IV knows
  -- which bytes of memory to deliver to the sprites.  This arrangement allows
  -- for normal VIC-II semantics for the sprites, including priority order etc.
  -- The only difference we intend to implement here is to have a register that
  -- allows the number of rows in each sprite to be varied from the usual 21,
  -- since there is no reason to maintain this fairly artificial limit.  Even
  -- in the VIC-II the only logic cost would have been the extra register (or
  -- register per sprite).
  --
  -- C65 VIC-III bitplanes will be implemented using the same sprite data pipeline
  -- so that no further stress is placed on the VIC-IV memory access logic,
  -- which is already rather strained at the 192MHz pixel clock.
  signal sprite_data_offset_rx : integer range 0 to 65535;
  signal sprite_number_counter : integer range 0 to 15 := 0;
  signal sprite_number_for_data_tx : integer range 0 to 15 := 0;
  signal sprite_number_for_data_rx : integer range 0 to 15;
  type sprite_data_offset_8 is array(0 to 15) of integer range 0 to 65535;
  signal sprite_data_offsets : sprite_data_offset_8;
  -- Similarly we need to deliver the bytes of data to the VIC-II sprite chain
  signal sprite_datavalid : std_logic;
  signal sprite_bytenumber : spritebytenumber := 0;
  signal sprite_spritenumber : spritenumber := 0;
  signal sprite_data_byte : unsigned(7 downto 0) := to_unsigned(0,7+1);
  -- The sprite chain also has the opportunity to modify the pixel colour being
  -- drawn so that the sprites can be overlayed on the display.
  signal pixel_is_foreground : std_logic;
  signal pixel_is_background : std_logic;
  signal pixel_is_foreground_in : std_logic;
  signal pixel_is_background_in : std_logic;
  signal composite_bg_red : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal composite_bg_green : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal composite_bg_blue : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal composite_red : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal composite_green : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal composite_blue : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal composited_red : std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(0,9+1));
  signal composited_green : std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(0,9+1));
  signal composited_blue : std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(0,9+1));
  signal compositer_enable : std_logic := '1';
  signal is_background_in : std_logic;
  signal pixel_is_background_out : std_logic;
  signal pixel_is_foreground_out : std_logic;
  signal chargen_pixel_colour : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal chargen_alpha_value : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal postsprite_pixel_colour : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal postsprite_alpha_value : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal postsprite_sprite_number : integer range 0 to 7;
  signal postsprite_alternate_palette : std_logic := '0';
  signal postsprite_alternate_palette_delayed : std_logic := '0';
  signal alpha_blend_alpha : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal pixel_is_sprite : std_logic;

  signal sprite_fetch_drive : std_logic := '0';
  signal sprite_fetch_sprite_number : integer range 0 to 31 := 0;
  signal sprite_fetch_byte_number : integer range 0 to 319 := 0;
  signal sprite_fetch_sprite_number_drive : integer range 0 to 31 := 0;
  signal sprite_fetch_byte_number_drive : integer range 0 to 319 := 0;
  signal sprite_pointer_address : unsigned(19 downto 0) := to_unsigned(0,20);
  signal sprite_data_address : unsigned(19 downto 0) := to_unsigned(0,20);
  signal sprite_data_addresses : spritebaseaddresses := (others => to_unsigned(0,20));
  signal sprite_h640_msbs : std_logic_vector(7 downto 0) := x"00";

  -- Compatibility registers
  signal twentyfourlines : std_logic := '0';
  signal thirtyeightcolumns : std_logic := '0';
  signal vicii_raster_compare : unsigned(10 downto 0) := to_unsigned(256,11);
  signal viciv_rasterx_compare : unsigned(13 downto 0) := to_unsigned(8191,14);
  signal vicii_raster_compare_plus_one : unsigned(10 downto 0) := to_unsigned(256,11);
  signal vicii_x_smoothscroll : unsigned(2 downto 0) := to_unsigned(0,2+1);
  signal vicii_y_smoothscroll : unsigned(2 downto 0) := to_unsigned(0,2+1);
  -- NOTE: these are here for reading. the actual used VIC-II sprite
  -- registers are defined in vicii_sprites.vhdl
  signal vicii_sprite_enables : std_logic_vector(7 downto 0) := x"FF";
  signal vicii_sprite_xmsbs : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0,7+1));
  signal vicii_sprite_x_expand : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0,7+1));
  signal vicii_sprite_y_expand : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0,7+1));
  signal vicii_sprite_priority_bits : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0,7+1));
  signal vicii_sprite_multicolour_bits : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0,7+1));

  -- Here are the signals received from the sprites, which get ored onto
  -- the following signals.
  signal vicii_sprite_sprite_collision_map : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0,7+1));
  signal vicii_sprite_bitmap_collision_map : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0,7+1));

  -- HEre is what gets read from the VIC-II register (and then zeroed in the process)
  -- and which also get checked for interrupt generation
  signal vicii_sprite_sprite_collisions : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0,7+1));
  signal vicii_sprite_bitmap_collisions : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0,7+1));

  signal viciii_extended_attributes : std_logic := '1';
  signal irq_lightpen : std_logic := '0';
  signal irq_collisionspritesprite : std_logic := '0';
  signal irq_collisionspritebitmap : std_logic := '0';
  signal irq_raster : std_logic := '0';
  signal irq_rasterx : std_logic := '0';
  signal irq_extras_enable : std_logic := '0';
  signal ack_lightpen : std_logic := '0';
  signal ack_collisionspritesprite : std_logic := '0';
  signal ack_collisionspritebitmap : std_logic := '0';
  signal ack_raster : std_logic := '0';
  signal ack_rasterx : std_logic := '0';
  signal mask_lightpen : std_logic := '0';
  signal mask_collisionspritesprite : std_logic := '0';
  signal mask_collisionspritebitmap : std_logic := '0';
  signal mask_raster : std_logic := '0';
  signal mask_rasterx : std_logic := '0';
  signal clear_collisionspritebitmap : std_logic := '0';
  signal clear_collisionspritebitmap_1 : std_logic := '0';
  signal clear_collisionspritesprite : std_logic := '0';
  signal clear_collisionspritesprite_1 : std_logic := '0';

  signal lightpen_x_latch : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal lightpen_y_latch : unsigned(7 downto 0) := to_unsigned(0,7+1);

  -- Used for hardware character blinking ala C65
  signal viciii_blink_phase : std_logic := '0';
  -- 60 frames = 1 second, and means no tearing.
  signal viciii_blink_phase_counter : integer range 0 to 30 := 0;

  -- And faster version for blinking drive led
  signal drive_blink_phase : std_logic := '0';
  signal drive_blink_phase_counter : integer range 0 to 15 := 0;


  -- NOTE: The following registers require 64-bit alignment. Default addresses
  -- are fairly arbitrary.
  -- Colour RAM offset (we just use some normal RAM for colour RAM, since in the
  -- worst case we can need >32KB of it.  Must correspond to a ChipRAM address,
  -- so the MSBs are irrelevant.
  signal colour_ram_base : unsigned(15 downto 0) := x"0000";
  -- Screen RAM offset ( @ $1000 on boot for debug purposes)
  signal screen_ram_base : unsigned(27 downto 0) := x"0000400";
  -- Pointer to the VIC-II compatibility sprite source vector, usually
  -- screen+$3F8 in 40 column mode, or +$7F8 in VIC-III 80 column mode
  signal vicii_sprite_pointer_address : unsigned(27 downto 0) := x"00013F8";

  -- Character set address.
  -- Size of character set depends on resolution of characters, and whether
  -- full-colour characters are enabled.
  signal character_set_address : unsigned(27 downto 0) := x"0000000";
  signal character_data_from_rom : std_logic := '1';
  -----------------------------------------------------------------------------

  -- Character generator state. Also used for graphics modes, since graphics
  -- modes on the C64 are all card-based, anyway.
  signal card_number : unsigned(15 downto 0) := x"0000";
  signal card_number_drive : unsigned(15 downto 0) := x"0000";
  signal card_number_is_extended : std_logic;  -- set if card_number > $00FF
  signal first_card_of_row : unsigned(15 downto 0) := to_unsigned(0,15+1);
  -- DEBUG: Set previous first card of row to all high so that a badline gets
  -- triggered on the first raster being drawn.
  -- Also used so that last pixel row in bitmap char cards doesn't show data
  -- from the next char card down the screen.
  signal prev_first_card_of_row : unsigned(15 downto 0) := (others => '1');
  -- coordinates after applying the above scaling factors
  signal chargen_x : unsigned(2 downto 0) := (others => '0');
  signal chargen_y : unsigned(2 downto 0) := (others => '0');
  signal chargen_y_next : unsigned(2 downto 0) := (others => '0');
  signal chargen_y_hold : unsigned(2 downto 0) := (others => '0');
  -- fractional pixel position for scaling
  signal chargen_y_sub : unsigned(4 downto 0) := to_unsigned(0,4+1);
  -- Allow double vertical resolution of chars in V200 mode
  -- by multiplexing between normal and shifted charset
  signal charrow_repeated : std_logic := '0';
  signal reg_char_y16 : std_logic := '0';

  -- Common bitmap and character drawing info
  signal glyph_data_address : unsigned(19 downto 0) := to_unsigned(0,20);

  -- For holding pre-calculated expressions to flatten logic
  signal bitmap_glyph_data_address : unsigned(19 downto 0) := to_unsigned(0,20);


  -- Bitmap drawing info
  signal bitmap_colour_foreground : unsigned(7 downto 0) := x"00";
  signal bitmap_colour_background : unsigned(7 downto 0) := x"00";

  -- Character drawing info
  signal background_colour_select : unsigned(1 downto 0) := "00";
  signal glyph_number : unsigned(12 downto 0) := to_unsigned(0,13);
  signal glyph_y_offset : integer range 0 to 7 := 0;
  signal glyph_colour_drive : unsigned(7 downto 0) := x"00";
  signal glyph_colour_drive2 : unsigned(7 downto 0) := x"00";
  signal glyph_colour : unsigned(7 downto 0) := x"00";
  signal glyph_attributes : unsigned(3 downto 0) := "0000";
  signal glyph_visible_drive : std_logic := '0';
  signal glyph_visible : std_logic := '0';
  signal glyph_bold : std_logic := '0';
  signal glyph_bold_drive : std_logic := '0';
  signal glyph_underline_drive : std_logic := '0';
  signal glyph_underline : std_logic := '0';
  signal glyph_reverse : std_logic := '0';
  signal glyph_reverse_drive : std_logic := '0';
  signal glyph_full_colour : std_logic := '0';
  signal glyph_4bit : std_logic := '0';
  signal glyph_flip_horizontal : std_logic := '0';
  signal glyph_flip_vertical : std_logic := '0';
  signal glyph_goto : std_logic := '0';
  signal glyph_width_deduct : unsigned(3 downto 0) := to_unsigned(0,3+1);
  signal glyph_width : integer range 0 to 16;
  signal paint_glyph_width : integer range 0 to 16;
  signal paint_glyph_4bit : std_logic := '0';
  signal glyph_blink : std_logic := '0';
  signal glyph_blink_drive : std_logic := '0';
  signal paint_blink : std_logic := '0';
  signal glyph_with_alpha : std_logic := '0';
  signal paint_with_alpha : std_logic := '0';
  signal glyph_trim_top : integer range 0 to 7;
  signal glyph_trim_bottom : integer range 0 to 7;
  signal glyph_paint_background : std_logic := '1';
  signal glyph_alternate_palette_invert : std_logic := '0';
  signal glyph_bold_and_reverse : std_logic := '0';
  signal force_chars_foreground : std_logic := '1';
  signal force_chars_background : std_logic := '0';
  signal last_hyper_request_toggle : std_logic := '0';

  signal short_line : std_logic := '0';
  signal short_line_length : integer range 0 to 512;
  signal screen_ram_is_ff : std_logic := '0';
  signal screen_ram_high_is_ff : std_logic := '0';
  signal row_advance : integer range 0 to 512;

  signal card_of_row : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal chargen_active : std_logic := '0';
  signal chargen_active_drive : std_logic := '0';
  signal chargen_active_soon : std_logic := '0';
  signal chargen_active_soon_drive : std_logic := '0';

  -- Delayed versions of signals to allow character fetching pipeline
  signal chargen_x_t1 : unsigned(2 downto 0) := (others => '0');
  signal chargen_x_t2 : unsigned(2 downto 0) := (others => '0');
  signal chargen_x_t3 : unsigned(2 downto 0) := (others => '0');
  signal card_number_t1 : unsigned(7 downto 0) := (others => '0');
  signal card_number_t2 : unsigned(7 downto 0) := (others => '0');
  signal card_number_t3 : unsigned(7 downto 0) := (others => '0');
  signal cards_differ : std_logic := '0';
  signal indisplay_t1 : std_logic := '0';
  signal indisplay_t2 : std_logic := '0';
  signal indisplay_t3 : std_logic := '0';
  signal cycles_to_next_card : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal cycles_to_next_card_drive : unsigned(7 downto 0) := to_unsigned(0,7+1);

  -- Interface to character generator rom
  signal charaddress : integer range 0 to 4095;
  signal chardata : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0,7+1));
  signal chardata_drive : unsigned(7 downto 0) := to_unsigned(0,7+1);
  -- buffer of read data to improve timing
  signal charrow : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0,7+1));
  signal charrow_t1 : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0,7+1));
  signal charrow_t2 : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(0,7+1));

  -- C65 style 2K colour RAM
  signal colourram_at_dc00_internal : std_logic := '0';
  -- C65 ROM mapping
  signal reg_rom_e000 : std_logic := '0';
  signal reg_rom_c000 : std_logic := '0';
  signal reg_rom_a000 : std_logic := '0';
  signal reg_rom_8000 : std_logic := '0';
  signal reg_c65_charset : std_logic := '0';
  signal reg_palrom : std_logic := '0';

  signal reg_h640 : std_logic := '0';
  signal reg_h1280 : std_logic := '0';
  signal reg_v400 : std_logic := '0';
  signal reg_mono : std_logic := '0';
  signal reg_interlace : std_logic := '0';
  signal sprite_h640 : std_logic := '1';
  signal sprite_v400s : std_logic_vector(7 downto 0) := x"00";
  signal sprite_v400_msbs : std_logic_vector(7 downto 0) := x"00";
  signal sprite_v400_super_msbs : std_logic_vector(7 downto 0) := x"00";

  type rgb is
  record
    red   : unsigned(7 downto 0);
    green : unsigned(7 downto 0);
    blue  : unsigned(7 downto 0);
  end record;

  -- Border generation signals
  -- (see video registers section for the registers that define the border size)
  signal inborder : std_logic := '0';
  signal pixel_alt_palette : std_logic := '0';
  signal postsprite_inborder : std_logic := '0';
  signal inborder_drive : std_logic := '0';
  signal xfrontporch : std_logic := '0';
  signal xfrontporch_drive : std_logic := '0';
  signal xbackporch : std_logic := '0';
  signal xbackporch_edge : std_logic := '0';

  signal last_ramaddress : unsigned(19 downto 0) := to_unsigned(0,19+1);
  signal ramaddress : unsigned(19 downto 0) := to_unsigned(0,19+1);
  signal ramdata : unsigned(7 downto 0) := to_unsigned(0,7+1);
  signal ramdata_drive : unsigned(7 downto 0) := to_unsigned(0,7+1);

  -- Precalculated mono/multicolour pixel bits
  signal multicolour_bits : std_logic_vector(1 downto 0) := (others => '0');
  signal monobit : std_logic := '0';

  -- Raster buffer
  -- Read address is in 128th of pixels
  signal raster_buffer_read_address : unsigned(10 downto 0) := to_unsigned(0,10+1);
  signal raster_buffer_read_address_sub : unsigned(9 downto 0) := to_unsigned(0,9+1);
  signal raster_buffer_read_address_next : unsigned(10 downto 0) := to_unsigned(0,10+1);
  signal raster_buffer_read_address_sub_next : unsigned(9 downto 0) := to_unsigned(0,9+1);
  signal raster_buffer_read_data : unsigned(17 downto 0) := to_unsigned(0,17+1);
  signal raster_buffer_write_address : unsigned(10 downto 0) := to_unsigned(0,10+1);
  signal raster_buffer_write_data : unsigned(17 downto 0) := to_unsigned(0,17+1);
  signal raster_buffer_write : std_logic := '0';

  signal raster_buffer_max_write_address : unsigned(9 downto 0) := to_unsigned(0,9+1);
  signal raster_buffer_max_write_address_hold : unsigned(9 downto 0) := to_unsigned(0,9+1);
  signal raster_buffer_max_write_address_prev : unsigned(9 downto 0) := to_unsigned(0,9+1);

  signal no_raster_buffer_delay : std_logic := '1';
  signal raster_buffer_double_line : std_logic := '0';

  -- Colour RAM access for video controller
  signal colourramaddress : unsigned(15 downto 0) := to_unsigned(0,15+1);
  signal colourramdata : unsigned(7 downto 0) := to_unsigned(0,7+1);
  -- ... and for CPU
  signal colour_ram_fastio_address : unsigned(15 downto 0) := to_unsigned(0,15+1);

  -- Palette RAM access via fastio port
  signal palette_we : std_logic_vector(3 downto 0) := (others => '0');
  signal palette_fastio_address : std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(0,9+1));
  signal palette_fastio_rdata : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(0,31+1));

  -- Palette RAM access for video controller
  -- -- colour lookup for primary pixel pipeline
  signal palette_address : std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(0,9+1));
  signal palette_rdata : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(0,31+1));
  -- -- colour lookup for anti-aliased font foreground colour
  signal alias_palette_address : std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(0,9+1));
  signal alias_palette_rdata : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(0,31+1));
  -- -- colour lookup for alpha blending of visible sprite over
  --    character generator
  signal sprite_alias_palette_address : std_logic_vector(9 downto 0) := std_logic_vector(to_unsigned(0,9+1));
  signal sprite_alias_palette_rdata : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(0,31+1));

  -- Palette bank selection registers
  signal palette_bank_fastio : std_logic_vector(1 downto 0) := "11";
  signal palette_bank_chargen : std_logic_vector(1 downto 0) := "11";
  signal palette_bank_chargen_alt : std_logic_vector(1 downto 0) := "11";
  signal palette_bank_sprites : std_logic_vector(1 downto 0) := "11";

  signal vsync_polarity_internal : std_logic := '0';
  signal hsync_polarity_internal : std_logic := '0';

  -- Mode line calculations
  signal text_height_200 : integer := 0;
  signal text_height_400 : integer := 0;

  signal text_height : integer;
  signal chargen_y_scale_200 : unsigned(7 downto 0) := (others => '0');
  signal chargen_y_scale_400 : unsigned(7 downto 0) := (others => '0');
  signal chargen_y_pixels : integer := 0;
  -- Initialise the top border height to be > 6 to avoid boundary violations
  -- during start up in simulation
  signal top_borders_height_200 : unsigned(11 downto 0) := to_unsigned(16,12);
  signal top_borders_height_400 : unsigned(11 downto 0) := to_unsigned(16,12);
  signal single_top_border_200 : unsigned(11 downto 0) := to_unsigned(16,12);
  signal single_top_border_400 : unsigned(11 downto 0) := to_unsigned(16,12);

  signal viciv_flyback : std_logic := '0';

  signal pixel_newframe_internal : std_logic := '0';

  -- Signals for managing the state of the programmable screen RAM lists
  -- We have a simple call-stack scheme, where GOTO tokens and GOSUB tokens
  -- can cause redirection of the screen RAM stream being read. This happens
  -- during the badline fetch, i.e., once per character row.
  type screenline_return_stack_t is  array (0 to 3) of unsigned(19 downto 0);
  signal screenline_return_stack : screenline_return_stack_t;
  signal screenline_return_stack_count : integer range 0 to 3 := 0;
  -- We also allow shoving characters up or down, so that by displaying
  -- a set of screen characters (possibly via a GOSUB token), they can be
  -- displayed at any vertical offset, as well as horizontal offset via the
  -- GOTOX tokens.
  -- The draw_mask combined with the Y fine address offset mechanism allows
  -- shifting a character up or down, and then masking off the parts that would
  -- come from the previous or next character
  signal screenline_draw_mask : unsigned(7 downto 0) := (others => '1');
  signal screenline_draw_mask_drive : unsigned(7 downto 0) := (others => '1');
  signal draw_mask_blank : std_logic := '0';

  -- For accumulating the last token
  signal screen_line_last_token : unsigned(15 downto 0) := x"0000";
  -- Count down used to extracting read 16-bit character tokens from the
  -- badline data stream (corrects for pipeline delay, and only every other
  -- byte completing a 16-bit token).
  signal badlineprog_countdown : integer := 0;
  -- Count down used when branching in a badline program to flush the memory
  -- fetch pipeline.
  signal badlineprog_inhibit_screen_row_buffer_write_counter : integer := 0;
  -- Indicates if the next 16 bit screen token will be a GOTO/GOSUB token
  signal next_token_is_goto : std_logic := '0';

  signal reg_alpha_delay : unsigned(3 downto 0) := x"1";

  signal is_fetch_start : std_logic := '0';
  signal last_was_fetch_start : std_logic := '0';

  signal d031_writes : unsigned(7 downto 0) := x"00";
  signal d031_written_internal : std_logic := '0';

  signal badline_toggle_internal : std_logic := '0';
  signal enable_raster_delay : std_logic := '1';
  signal pixels_since_last_char : unsigned(2 downto 0) := "000";

  signal render_activity : std_logic_vector(2 downto 0) := "000";
  signal show_render_activity : std_logic := '0';

  signal hyper_data : unsigned(7 downto 0) := x"00";
  signal hyper_addr_drive : unsigned(18 downto 3) := x"0000";
  signal hyper_data_strobe : std_logic := '0';
  signal hyper_request_toggle_drive : std_logic := '0';
  signal hyper_request_toggle_drive2 : std_logic := '0';
  signal hyper_request_toggle_drive3 : std_logic := '0';
  signal hyper_data_counter : unsigned(31 downto 0) := to_unsigned(0,32);

  signal sprite_continuous_pointer_monitoring : std_logic := '1';

  -- Set to 0 to disable bug compatibility D016 positioning
  signal prev_hw_errata_level : unsigned(7 downto 0) := to_unsigned(0,8);
  signal bug_compat_mode : std_logic := '1';
  signal prev_bug_compat_mode : std_logic := '1';
  signal bug_compat_vic_iii_d016_delta : integer := 2;
  signal bug_compat_char_attr : std_logic := '1';

begin

  rasterbuffer1: entity work.ram18x2k
    port map (
      clkl => pixelclock,
      clkr => pixelclock,
      wel(0) => raster_buffer_write,
      dinl => std_logic_vector(raster_buffer_write_data),
      unsigned(doutr) => raster_buffer_read_data,
      addrl => std_logic_vector(raster_buffer_write_address(10 downto 0)),
      addrr => std_logic_vector(raster_buffer_read_address_next)
      );

  buffer1: entity work.screen_ram_buffer
    port map (
      clka => pixelclock,
      clkb => pixelclock,
      dina    => std_logic_vector(screen_ram_buffer_din),
      unsigned(doutb)   => screen_ram_buffer_dout,
      wea(0)  => screen_ram_buffer_write,
      addra  => std_logic_vector(screen_ram_buffer_write_address(8 downto 0)),
      addrb  => std_logic_vector(screen_ram_buffer_read_address(8 downto 0))
      );

  colourram: block
  begin
    colourram1 : entity work.ram8x32k
      PORT MAP (
        clka => cpuclock,
        ena => colour_ram_cs,
        wea(0) => fastio_write,
--        wea => fastio_write,
        addra => std_logic_vector(colour_ram_fastio_address(14 downto 0)),
        dina => fastio_wdata,
        douta => colour_ram_fastio_rdata,
        -- video controller use port b of the dual-port colour ram.
        -- The CPU uses port a via the fastio interface
        clkb => pixelclock,
        web => (others => '0'),
--        web => '0',
        addrb => std_logic_vector(colourramaddress(14 downto 0)),
        dinb => (others => '0'),
        unsigned(doutb) => colourramdata
        );
  end block;

  -- Used for main pixel pipeline colour lookup
  paletteram0: entity work.ram32x1024
    port map (
      clka => cpuclock,
      ena => '1',
      wea => palette_we,
      addra => palette_fastio_address,
      dina(31 downto 24) => fastio_wdata,
      dina(23 downto 16) => fastio_wdata,
      dina(15 downto 8) => fastio_wdata,
      dina(7 downto 0) => fastio_wdata,
      douta => palette_fastio_rdata,
      clkb => pixelclock,
      web => (others => '0'),
      addrb => palette_address,
      dinb => (others => '0'),
      doutb => palette_rdata
      );

  -- Used for anti-aliased text colour lookup
  paletteram1: entity work.ram32x1024
    port map (
      clka => cpuclock,
      ena => '1',
      wea => palette_we,
      addra => palette_fastio_address,
      dina(31 downto 24) => fastio_wdata,
      dina(23 downto 16) => fastio_wdata,
      dina(15 downto 8) => fastio_wdata,
      dina(7 downto 0) => fastio_wdata,
      -- douta => palette_fastio_rdata,
      clkb => pixelclock,
      web => (others => '0'),
      addrb => alias_palette_address,
      dinb => (others => '0'),
      doutb => alias_palette_rdata
      );


  charrom1 : entity work.charrom
    port map (Clk => pixelclock,
              address => charaddress,
              cs => '1',  -- active
              data_o => chardata,

              cpuclk => cpuclock,
              cpucs => charrom_cs,
              cpuaddress => unsigned(fastio_addr(11 downto 0)),
              we => fastio_write,
              data_i => fastio_wdata,
              cpu_data_o => charrom_fastio_rdata
              );

  compositeblender: entity work.alpha_blend_top
    port map (clk1x => pixelclock,
              reset => '0',
              hsync_strm0 => '0',
              vsync_strm0 => '0',
              de_strm0 => '1',
              -- RGB of background colour
              r_strm1(9 downto 2) => std_logic_vector(composite_bg_red),
              r_strm1(1 downto 0) => (others => '0'),
              g_strm1(9 downto 2) => std_logic_vector(composite_bg_green),
              g_strm1(1 downto 0) => (others => '0'),
              b_strm1(9 downto 2) => std_logic_vector(composite_bg_blue),
              b_strm1(1 downto 0) => (others => '0'),
              de_strm1 => '1',
              -- XXX: replace RGB and postsprite_pixel_colour values
              -- with appropriately delayed signals
              r_strm0(9 downto 2) => std_logic_vector(composite_red),
              r_strm0(1 downto 0) => (others => '0'),
              g_strm0(9 downto 2) => std_logic_vector(composite_green),
              g_strm0(1 downto 0) => (others => '0'),
              b_strm0(9 downto 2) => std_logic_vector(composite_blue),
              b_strm0(1 downto 0) => (others => '0'),
              de_alpha => '1',
              alpha_strm(9 downto 2) => std_logic_vector(alpha_blend_alpha(7 downto 0)),
              alpha_strm(1 downto 0) => "00",

              alpha_delay => reg_alpha_delay,

              r_blnd => composited_red,
              g_blnd => composited_green,
              b_blnd => composited_blue
              );

  pal_sim0: entity work.pal_simulation
    port map(
      clock => pixelclock,
      shadow_mask_enable => shadow_mask_enable,
      red_in => vga_palin_red,
      green_in => vga_palin_green,
      blue_in => vga_palin_blue,
      red_out => vga_palout_red,
      green_out => vga_palout_green,
      blue_out => vga_palout_blue,
      x_position => xcounter,
      y_position => displayy
      );


  vicii_sprites0: entity work.vicii_sprites
    port map (pixelclock => pixelclock,
              cpuclock => cpuclock,

              sprite_h640 => sprite_h640_delayed,
              sprite_v400s => sprite_v400s_delayed,
              bitplane_h640 => reg_h640_delayed,
              bitplane_h1280 => reg_h1280_delayed,
              bitplane_mode_in => bitplane_mode,
              bitplane_enables_in => bitplane_enables,
              bitplane_complements_in => bitplane_complements,
              bitplanes_y_start => bitplanes_y_start_drive,
              bitplanes_x_start => bitplanes_x_start_drive,
              bitplane_sixteen_colour_mode_flags_in =>
              bitplane_sixteen_colour_mode_flags,

              sprite_datavalid_in => sprite_datavalid,
              sprite_bytenumber_in => sprite_bytenumber,
              sprite_spritenumber_in => sprite_spritenumber,
              sprite_data_in => sprite_data_byte,

              sprite_horizontal_tile_enables => sprite_horizontal_tile_enables,
              sprite_bitplane_enables => sprite_bitplane_enables,
              sprite_extended_width_enables => sprite_extended_width_enables,
              sprite_extended_height_enables => sprite_extended_height_enables,
              sprite_extended_height_size => sprite_extended_height_size,
              sprite_sixteen_colour_enables => sprite_sixteen_colour_enables,

              sprite_number_for_data_in => sprite_number_for_data_tx,
              sprite_data_offset_out => sprite_data_offset_rx,
              sprite_number_for_data_out => sprite_number_for_data_rx,



              is_foreground_in => pixel_is_foreground_in,
              is_background_in => pixel_is_background_in,
              -- VIC-II sprites care only about VIC-II coordinates
              -- XXX 40 and 80 column displays should have the same aspect
              -- ratio for this to really work.
              pipeline_delay => reg_xcounter_delay,
              x320_in => to_xposition(vicii_xcounter_320),
              x640_in => to_xposition(vicii_xcounter_640),
              -- x1280 mode is deprecated
              x1280_in => to_xposition(vicii_xcounter_640),
              y_in => to_yposition(vicii_sprite_ycounter),
              yfine_in => to_yposition(vicii_ycounter_v400),
              border_in => inborder_drive,
              alt_palette_in => pixel_alt_palette,
              pixel_in => chargen_pixel_colour,
              alpha_in => chargen_alpha_value,
              pixel_out => postsprite_pixel_colour,
              alpha_out => postsprite_alpha_value,
              border_out => postsprite_inborder,
              alt_palette_out => postsprite_alternate_palette,
              is_sprite_out => pixel_is_sprite,
              sprite_number_out => postsprite_sprite_number,
              is_background_out => pixel_is_background_out,
              is_foreground_out => pixel_is_foreground_out,

              -- Get sprite collision info
              sprite_fg_map_final => vicii_sprite_bitmap_collision_map,
              sprite_map_final => vicii_sprite_sprite_collision_map,

              fastio_addr => fastio_addr,
              fastio_write => fastio_write,
              fastio_wdata => fastio_wdata
              );


  chipram_address <= next_ramaddress when safe_to_integer(next_ramaddress) < chipram_size else to_unsigned(0,20);
  ramdata <= chipram_datain;

  process(cpuclock,fastio_addr,fastio_read,chardata,
          sprite_x,sprite_y,vicii_sprite_xmsbs,ycounter,extended_background_mode,
          text_mode,blank,twentyfourlines,vicii_y_smoothscroll,displayy,
          vicii_sprite_enables,multicolour_mode,thirtyeightcolumns,
          vicii_x_smoothscroll,vicii_sprite_y_expand,screen_ram_base,
          character_set_address,irq_collisionspritebitmap,irq_collisionspritesprite,
          irq_raster,mask_collisionspritebitmap,mask_collisionspritesprite,
          mask_raster,vicii_sprite_priority_bits,vicii_sprite_multicolour_bits,
          vicii_sprite_sprite_collisions,vicii_sprite_bitmap_collisions,
          border_colour,screen_colour,multi1_colour,multi2_colour,multi3_colour,
          border_x_left,border_x_right,border_y_top,border_y_bottom,
          x_chargen_start,y_chargen_start,fullcolour_8bitchars,
          fullcolour_extendedchars,sixteenbit_charset,
          cycles_to_next_card,xfrontporch,xbackporch,chargen_active,inborder,
          irq_drive,vicii_sprite_x_expand,sprite_multi0_colour,
          sprite_multi1_colour,sprite_colours,colourram_at_dc00_internal,
          viciii_extended_attributes,virtual_row_width,chargen_x_scale,
          chargen_y_scale,xcounter,chargen_active_soon,card_number,
          colour_ram_base,vicii_sprite_pointer_address,palette_bank_fastio,
          debug_cycles_to_next_card,
          debug_chargen_active,debug_raster_fetch_state,debug_charaddress,
          debug_charrow,palette_fastio_rdata,palette_bank_chargen,
          debug_chargen_active_soon,palette_bank_sprites,
          vicii_ycounter,reg_rom_e000,reg_rom_c000,
          reg_rom_a000,reg_c65_charset,reg_rom_8000,reg_palrom,
          reg_h640,reg_h1280,reg_v400,reg_interlace,xcounter_drive,ycounter_drive,
          horizontal_filter,xfrontporch_drive,chargen_active_drive,
          inborder_drive,chargen_active_soon_drive,card_number_drive,
          bitplanes_x_start,bitplanes_y_start,dat_y,dat_x,dat_bitplane_offset,
          bitplane_addresses,vicii_2mhz_internal,viciii_fast_internal,
          bitplane_mode,bitplane_enables,bitplane_addresses,bitplane_complements,
          sprite_bitplane_enables,sprite_horizontal_tile_enables,compositer_enable,
          viciv_fast_internal,pal_simulate,sprite_extended_height_enables,
          sprite_extended_height_size,sprite_extended_width_enables,
          chargen_x_scale_drive,single_side_border,
          sprite_first_x,sprite_sixteen_colour_enables,
          vicii_ntsc,vicii_first_raster,
          palette_bank_chargen_alt,bitplane_sixteen_colour_mode_flags,
          vicii_ycounter_scale_minus_zero,
          hsync_polarity_internal,vsync_polarity_internal,
          vicii_ycounter_minus_one,lightpen_x_latch,lightpen_y_latch,irq_rasterx,irq_lightpen,
          mask_rasterx,mask_lightpen,no_raster_buffer_delay,raster_buffer_double_line,
          vicii_is_raster_source,shadow_mask_enable,sprite_h640,vicii_hot_regs_enable,
          display_row_width,sprite_h640_msbs,glyphs_from_hyperram,fullcolour_mcm,
          reg_xcounter_delay,show_render_activity,test_pattern_enable,vga60_select_internal,
          sprite_y_adjust,reg_alpha_delay,sprite_alpha_blend_value,sprite_alpha_blend_enables,
          sprite_v400s,sprite_v400_msbs,sprite_v400_super_msbs,vicii_raster_compare,
          sprite_continuous_pointer_monitoring,display_row_count,bitplane_bank_select,
          hypervisor_mode,debug_channel_select,hyper_data_counter,debug_pixel_red,
          debug_pixel_green,debug_pixel_blue,debug_x,debug_y,bug_compat_mode,
          reg_mono,upscale_enable_int,enable_raster_delay,reg_char_y16
          ) is
    variable bitplane_number : integer;

    procedure viciv_calculate_modeline_dimensions is
      constant w : integer := 400; -- was 320
    begin

      -- Display is a fixed 600 pixels high, so set Y scaling appropriately
      chargen_y_scale_200 <= to_unsigned(2,8);
      chargen_y_scale_400 <= to_unsigned(1,8);
      text_height_200 <= 400;
      text_height_400 <= 400;

      -- Calculate height of top borders
      top_borders_height_200 <= to_unsigned(safe_to_integer(display_height)
                                            - text_height_200,12);
      single_top_border_200(10 downto 0) <= top_borders_height_200(11 downto 1);
      single_top_border_200(11) <= '0';
      top_borders_height_400 <= to_unsigned(safe_to_integer(display_height)
                                            - text_height_400,12);
      single_top_border_400(10 downto 0) <= top_borders_height_400(11 downto 1);
      single_top_border_400(11) <= '0';
    end procedure;
    procedure viciv_interpret_legacy_mode_registers is
    begin
      -- set x_chargen
      report "LEGACY register update";
      if reg_h640='0' then
        x_chargen_start
          <= to_unsigned(safe_to_integer(frame_h_front)
                          +safe_to_integer(single_side_border)
                          -- VIC-II smooth scrolling is based on H320/400 and real
                          -- pixels are H640/800, so add double
                          +safe_to_integer(vicii_x_smoothscroll)
                          +safe_to_integer(vicii_x_smoothscroll)
                          ,14);
      else
        x_chargen_start
          <= to_unsigned(safe_to_integer(frame_h_front)
                          +safe_to_integer(single_side_border)
                          -- VIC-II smooth scrolling is based on H320/400 and real
                          -- pixels are H640/800, so add double
                          +safe_to_integer(vicii_x_smoothscroll)
                          +safe_to_integer(vicii_x_smoothscroll)
                          -bug_compat_vic_iii_d016_delta
                          ,14);
      end if;

      if reg_h640='0' then
        -- 40 column mode
        virtual_row_width <= to_unsigned(40,16);
        display_row_width <= to_unsigned(40,10);
      elsif reg_h640='1' then
        -- 80 column mode
        virtual_row_width <= to_unsigned(80,16);
        display_row_width <= to_unsigned(80,10);
      end if;

      if reg_v400='0' then
        display_row_count <= to_unsigned(25-1,8);
        chargen_y_scale <= to_unsigned(safe_to_integer(chargen_y_scale_200)-1,8);
        -- set vertical borders based on twentyfourlines
        if twentyfourlines='0' then
          border_y_top <= to_unsigned(
            raster_correction+
            safe_to_integer(single_top_border_200)-safe_to_integer(vicii_first_raster)*2,12);
          border_y_bottom <= to_unsigned(
            raster_correction+
            safe_to_integer(single_top_border_200)-safe_to_integer(vicii_first_raster)*2+
            text_height_200,12);
        else
          border_y_top <= to_unsigned(raster_correction
                                      +safe_to_integer(single_top_border_200)
                                      -safe_to_integer(vicii_first_raster)*2
                                      +(4*2),12);
          border_y_bottom <= to_unsigned(raster_correction
                                         +safe_to_integer(single_top_border_200)
                                         -safe_to_integer(vicii_first_raster)*2
                                         +text_height_200
                                         -(4*2),12);
        end if;
        -- set y_chargen_start based on twentyfourlines
        report "XXX vicii_y_smoothscroll = " & to_string(std_logic_vector(vicii_y_smoothscroll));
        report "XXX raster_correction = " & integer'image(raster_correction);
        report "XXX single_top_border_200 = " & integer'image(safe_to_integer(single_top_border_200));
        report "XXX vicii_first_raster = " & integer'image(safe_to_integer(vicii_first_raster));
        y_chargen_start <= unsigned(to_signed(raster_correction
                                              +safe_to_integer(single_top_border_200)
                                              -safe_to_integer(vicii_first_raster)*2
                                              -(3*2)
                                              -- Display is always V400/600, so pixels
                                              -- are double height
                                              +safe_to_integer(vicii_y_smoothscroll)
                                              +safe_to_integer(vicii_y_smoothscroll)
                                              ,12));

      else
        -- V400 mode : as above, but with the different constants
        display_row_count <= to_unsigned(50-1,8);
        chargen_y_scale <= to_unsigned(safe_to_integer(chargen_y_scale_400)-1,8);
        -- set vertical borders based on twentyfourlines
        if twentyfourlines='0' then
          border_y_top <= to_unsigned(
            raster_correction+
            safe_to_integer(single_top_border_400)
            -safe_to_integer(vicii_first_raster)*2,12);
          border_y_bottom <= to_unsigned(
            raster_correction+
            safe_to_integer(single_top_border_400)-safe_to_integer(vicii_first_raster)*2+
            text_height_400,12);
        else
          border_y_top <= to_unsigned(raster_correction
                                      +safe_to_integer(single_top_border_400)
                                      -safe_to_integer(vicii_first_raster)*2
                                      +(4*2),12);
          border_y_bottom <= to_unsigned(raster_correction
                                      +safe_to_integer(single_top_border_400)
                                      -safe_to_integer(vicii_first_raster)*2
                                      +text_height_400
                                      -(4*2),12);
     end if;
        -- set y_chargen_start based on twentyfourlines
        y_chargen_start <= to_unsigned(raster_correction
                                       +safe_to_integer(single_top_border_400)
                                       -safe_to_integer(vicii_first_raster)*2
                                       -(3*2)
                                       -- Screen is always V400/600, so pixels
                                       -- are 2 physical pixels high
                                       +safe_to_integer(vicii_y_smoothscroll)
                                       +safe_to_integer(vicii_y_smoothscroll)
                                       ,12);
      end if;

      screen_ram_base(27 downto 16) <= (others => '0');
      if reg_h640='1' then
        screen_ram_base(13 downto 11) <= reg_d018_screen_addr(3 downto 1);
        screen_ram_base(10 downto 0) <= (others => '0');
      else
        screen_ram_base(13 downto 10) <= reg_d018_screen_addr;
        screen_ram_base(9 downto 0) <= (others => '0');
      end if;

      -- Sprites fetch from screen ram base + $3F8 (or +$7F8 in VIC-III 80
      -- column mode).
      -- In 80 column mode the screen base must be on a 2K boundary on the
      -- C65, which changes the interpretation of the screen_ram_base.
      -- Note that our interpretation of V400 to double the number of text
      -- rows breaks strict C65 compatibility.
      vicii_sprite_pointer_address(27 downto 16) <= (others => '0');
      -- NOTE: Bits 14 and 15 are still set only by writing to $DD00
      -- or the VIC-IV registers that modify this.
      vicii_sprite_pointer_address(13 downto 10)
        <= reg_d018_screen_addr;
      if reg_h640='1' or reg_v400='1' then
        vicii_sprite_pointer_address(10) <= '1';
      end if;
      vicii_sprite_pointer_address(9 downto 0) <= "1111111000";

      -- Apply VIC-II banks
      screen_ram_base(15 downto 14) <= not last_dd00_bits;
      vicii_sprite_pointer_address(15 downto 14) <= not last_dd00_bits;
      character_set_address(15 downto 14) <= not last_dd00_bits;
      -- NOTE: We DONT reset the character set address with a legacy write,
      -- even if HOTREG are enabled. This makes it easier to use alternate
      -- character sets, and full-colour text mode upgrading of old programmes.

      -- All VIC-II/VIC-III compatibility modes use the first part of the
      -- colour RAM.
      colour_ram_base <= (others => '0');

      -- NOTE: We DONT reset the character set address with a legacy write.
      -- This makes it easier to use alternate character sets, and full-colour
      -- text mode upgrading of old programmes.

    end procedure viciv_interpret_legacy_mode_registers;
    procedure viciv_update_side_border_dimensions is
    begin
      -- set horizontal borders based on 40/38 columns
      report "LEGACY register update";
      if thirtyeightcolumns='0' then
        if reg_h640='0' then
          border_x_left <= to_unsigned(safe_to_integer(frame_h_front)+safe_to_integer(single_side_border),14);
          border_x_right <= to_unsigned(safe_to_integer(frame_h_front)+safe_to_integer(display_width)
                                        -safe_to_integer(single_side_border),14);
        else
          border_x_left <= to_unsigned(safe_to_integer(frame_h_front)+safe_to_integer(single_side_border),14);
          border_x_right <= to_unsigned(safe_to_integer(frame_h_front)+safe_to_integer(display_width)
                                        -safe_to_integer(single_side_border),14);
        end if;
      else
        if reg_h640='0' then
          border_x_left <= to_unsigned(safe_to_integer(frame_h_front)+safe_to_integer(single_side_border)
                                       +(7*2),14);
          border_x_right <= to_unsigned(safe_to_integer(frame_h_front)+safe_to_integer(display_width)
                                        -safe_to_integer(single_side_border)
                                        -(9*2),14);
        else
          border_x_left <= to_unsigned(safe_to_integer(frame_h_front)+safe_to_integer(single_side_border)
                                       +(7*2),14);
          border_x_right <= to_unsigned(safe_to_integer(frame_h_front)+safe_to_integer(display_width)
                                        -safe_to_integer(single_side_border)
                                        -(9*2),14);
        end if;
      end if;
    end procedure viciv_update_side_border_dimensions;


    variable register_bank : unsigned(7 downto 0) := to_unsigned(0,7+1);
    variable register_page : unsigned(3 downto 0) := to_unsigned(0,3+1);
    variable register_num : unsigned(7 downto 0) := to_unsigned(0,7+1);
    variable register_number : unsigned(11 downto 0) := to_unsigned(0,11+1);
  begin
    fastio_rdata <= (others => 'Z');

    chargen_x_scale_drive <= chargen_x_scale;

    bitplanes_x_start_drive <= bitplanes_x_start;
    bitplanes_y_start_drive <= bitplanes_y_start;

    -- Calculate DAT bitplane offset
    -- XXX currently ignores V400 mode
    if reg_v400 = '0' or reg_interlace = '0' then
      if reg_h640 = '0' then
        dat_bitplane_offset <=
          ("00" & dat_y(8 downto 3) & "00000000")
          + ("0000" & dat_y(8 downto 3) & "000000")
          + ("0000000000000" & dat_y(2 downto 0))
          + ("000000" & dat_x & "000");
      else
        dat_bitplane_offset <=
          ("0" & dat_y(8 downto 3) & "000000000")
          + ("000" & dat_y(8 downto 3) & "0000000")
          + ("0000000000000" & dat_y(2 downto 0))
          + ("000000" & dat_x & "000");
      end if;
      dat_even <= '1';
    else
      -- For V400 + Interlace, we need to pick even/odd frame
      -- This must mean that the bottom bit of dat_y indicates
      -- the odd/even frame, and all the other bits of dat_y are
      -- shifted right a bit to exclude it.
      if reg_h640 = '0' then
        dat_bitplane_offset <=
          ("000" & dat_y(8 downto 4) & "00000000")
          + ("0000" & dat_y(8 downto 3) & "000000")
          + ("0000000000000" & dat_y(3 downto 1))
          + ("000000" & dat_x & "000");
      else
        dat_bitplane_offset <=
          ("00" & dat_y(8 downto 4) & "000000000")
          + ("000" & dat_y(8 downto 3) & "0000000")
          + ("0000000000000" & dat_y(3 downto 1))
          + ("000000" & dat_x & "000");
      end if;
      dat_even <= not dat_y(0);
    end if;
    -- Export this and bitplane addresses to the CPU
    dat_offset <= dat_bitplane_offset;
    dat_bitplane_addresses <= bitplane_addresses;

    if true then
      -- Calculate register number asynchronously
      register_number := x"FFF";
      if fastio_addr(19) = '0' or fastio_addr(19) = '1' then
        register_bank := unsigned(fastio_addr(19 downto 12));
        register_page := unsigned(fastio_addr(11 downto 8));
        register_num := unsigned(fastio_addr(7 downto 0));
      else
        -- Give values when inputs are bad to supress warnings cluttering output
        -- when simulating
        register_bank := x"FF";
        register_page := x"F";
        register_num := x"FF";
      end if;

      if register_bank=x"D0" and register_page<4 then
        -- First 1KB of normal C64 IO space maps to r$0 - r$3F
        register_number(5 downto 0) := unsigned(fastio_addr(5 downto 0));
        register_number(11 downto 6) := (others => '0');
        if fastio_addr(11 downto 0) = x"030" then
          -- C128 $D030
          register_number := x"0FF"; -- = 255
        elsif (fastio_addr(11 downto 4) = x"03")
          or (fastio_addr(11 downto 4) = x"07")
        then
          -- $D030-$D03F are otherwise unmapped in VIC-II mode, so that the C65
          -- VIC-III registers there cannot be messed with.
          -- So we set it to a non-existent register
          -- We also have to do the same for $D070-$D07F
          register_number := x"0FE";
        end if;
        report "IO access resolves to video register number "
          & integer'image(safe_to_integer(register_number)) severity note;
      elsif (register_bank = x"D1" or register_bank = x"D2"or register_bank = x"D3") and register_page<4 then
        register_number(11 downto 10) := "00";
        register_number(9 downto 8) := register_page(1 downto 0);
        register_number(7 downto 0) := register_num;
        report "IO access resolves to video register number "
          & integer'image(safe_to_integer(register_number)) severity note;
      end if;

      -- $D800 - $DBFF colour RAM access.
      -- This is a bit fun, because colour RAM is mapped in 3 separate places:
      --   $D800 - $DBFF in the usual IO pages.
      --   $DC00 - $DFFF in the enhanced IO pages when the correct VIC-III
      --   register is set.
      --   $FF80000-$FF8FFFF - All 64KB of colour RAM
      -- The colour RAM has to be dual-port since the video controller needs to
      -- access it as well, so all these have to be mapped on a single port.
      colour_ram_fastio_address <= (others => '1');
      if register_bank = x"D0" or register_bank = x"D1"
        or register_bank = x"D2" or register_Bank=x"D3" then
        if register_page>=8 and register_page<12 then
                                        -- colour ram read $D800 - $DBFF
          colour_ram_fastio_address <= unsigned("000000" & fastio_addr(9 downto 0));
        elsif register_page>=12 and register_page<=15 then
                                        -- colour ram read $DC00 - $DFFF
          colour_ram_fastio_address <= unsigned("000001" & fastio_addr(9 downto 0));
        else
          colour_ram_fastio_address <= (others => '0');
        end if;
      elsif register_bank(7 downto 4)=x"8" then
                                        -- colour RAM all 64KB
        colour_ram_fastio_address <= unsigned(fastio_addr(15 downto 0));
      end if;

      if fastio_read='0' then
        fastio_rdata <= (others => 'Z');
      else
                                        -- report "read from fastio detect in video controller. " &
                                        --  "register number = " & integer'image(safe_to_integer(register_number)) &
                                        --  ", fastio_addr = " & to_hstring(fastio_addr) &
                                        --  ", register_bank = " & to_hstring(register_bank) &
                                        --  ", register_page = " & to_hstring(register_page)
                                        --   severity note;
        if register_number>=0 and register_number<8 then
                                        -- compatibility sprite coordinates
          fastio_rdata <= std_logic_vector(sprite_x(safe_to_integer(register_num(2 downto 0))));
        elsif register_number<16 then
                                        -- compatibility sprite coordinates
          fastio_rdata <= std_logic_vector(sprite_y(safe_to_integer(register_num(2 downto 0))));
        elsif register_number=16 then
                                        -- compatibility sprite x position MSB
          fastio_rdata <= vicii_sprite_xmsbs;
        elsif register_number=17 then             -- $D011
          fastio_rdata(7) <= vicii_ycounter_minus_one(8);  -- MSB of raster
          fastio_rdata(6) <= extended_background_mode;
          fastio_rdata(5) <= not text_mode;
          fastio_rdata(4) <= not blank;
          fastio_rdata(3) <= not twentyfourlines;
          fastio_rdata(2 downto 0) <= std_logic_vector(vicii_y_smoothscroll);
        elsif register_number=18 then          -- $D012 current raster low 8 bits
          fastio_rdata <= std_logic_vector(vicii_ycounter_minus_one(7 downto 0));
        elsif register_number=19 then          -- $D013 lightpen X (coarse rasterX)
          fastio_rdata <= std_logic_vector(lightpen_x_latch);
        elsif register_number=20 then          -- $D014 lightpen Y (coarse rasterY)
          fastio_rdata <= std_logic_vector(lightpen_y_latch);
        elsif register_number=21 then          -- $D015 compatibility sprite enable
          fastio_rdata <= vicii_sprite_enables;
        elsif register_number=22 then          -- $D016
          fastio_rdata(7) <= '1';
          fastio_rdata(6) <= '1';
          fastio_rdata(5) <= '0';       -- no reset support, since no badlines
          fastio_rdata(4) <= multicolour_mode;
          fastio_rdata(3) <= not thirtyeightcolumns;
          fastio_rdata(2 downto 0) <= std_logic_vector(vicii_x_smoothscroll);
        elsif register_number=23 then          -- $D017 compatibility sprite Y
                                               -- expand enable
          fastio_rdata <= vicii_sprite_y_expand;
        elsif register_number=24 then          -- $D018 compatibility RAM addresses
          fastio_rdata <=
            std_logic_vector(screen_ram_base(13 downto 10))
            & std_logic_vector(character_set_address(13 downto 10));
        elsif register_number=25 then          -- $D019 compatibility IRQ bits
          fastio_rdata(7) <= not irq_drive;
          fastio_rdata(6) <= '1';       -- NC
          fastio_rdata(5) <= '1';       -- NC
          fastio_rdata(4) <= irq_rasterx;
          fastio_rdata(3) <= irq_lightpen;
          fastio_rdata(2) <= irq_collisionspritesprite;
          fastio_rdata(1) <= irq_collisionspritebitmap;
          fastio_rdata(0) <= irq_raster;
        elsif register_number=26 then          -- $D01A compatibility IRQ mask bits
          fastio_rdata(7) <= '1';       -- NC
          fastio_rdata(6) <= '1';       -- NC
          fastio_rdata(5) <= '1';       -- NC
          fastio_rdata(4) <= mask_rasterx;
          fastio_rdata(3) <= mask_lightpen;
          fastio_rdata(2) <= mask_collisionspritesprite;
          fastio_rdata(1) <= mask_collisionspritebitmap;
          fastio_rdata(0) <= mask_raster;
        elsif register_number=27 then          -- $D01B sprite background priority
          fastio_rdata <= vicii_sprite_priority_bits;
        elsif register_number=28 then          -- $D01C sprite multicolour
          fastio_rdata <= vicii_sprite_multicolour_bits;
        elsif register_number=29 then          -- $D01D compatibility sprite enable
          fastio_rdata <= vicii_sprite_x_expand;
        elsif register_number=30 then          -- $D01E sprite/sprite collissions
          fastio_rdata <= vicii_sprite_sprite_collisions;
        elsif register_number=31 then          -- $D01F sprite/foreground collissions
          fastio_rdata <= vicii_sprite_bitmap_collisions;
        elsif register_number=32 then
          fastio_rdata <= std_logic_vector(border_colour);
        elsif register_number=33 then
          -- Match C64's VIC-II behaviour of showing only the lower 4 bits of
          -- screen colour, with the upper four bits = $F when in VIC-II IO context
          fastio_rdata(3 downto 0) <= std_logic_vector(screen_colour(3 downto 0));
          if register_bank /= x"D0" then
            fastio_rdata(7 downto 4) <= std_logic_vector(screen_colour(7 downto 4));
          else
            fastio_rdata(7 downto 4) <= x"f";
          end if;
        elsif register_number=34 then
          fastio_rdata <= std_logic_vector(multi1_colour);
        elsif register_number=35 then
          fastio_rdata <= std_logic_vector(multi2_colour);
        elsif register_number=36 then
          fastio_rdata <= std_logic_vector(multi3_colour);
        elsif register_number=37 then
          fastio_rdata <= std_logic_vector(sprite_multi0_colour);
        elsif register_number=38 then
          fastio_rdata <= std_logic_vector(sprite_multi1_colour);
        elsif register_number>=39 and register_number<=46 then
          fastio_rdata <= std_logic_vector(sprite_colours(safe_to_integer(register_number)-39));
        elsif register_number=255 then
          -- C128 $D030 emulation (2MHz mode only)
          fastio_rdata(7 downto 1) <= (others => '0');
          fastio_rdata(0) <= vicii_2mhz_internal;
        elsif register_number=48 then
          -- C65 $D030 emulation
          fastio_rdata <=
            reg_rom_e000        -- ROM @ E000
            & reg_c65_charset   -- character set select (D000 vs 9000)
            & reg_rom_c000      -- ROM @ C000
            & reg_rom_a000      -- ROM @ A000
            & reg_rom_8000      -- ROM @ 8000
            & reg_palrom        -- First sixteen palette entries are fixed
            -- (fetch from palette bank 3 on VIC-IV)
            & "0"                         -- External sync
            & colourram_at_dc00_internal;  -- 2KB colour RAM
        elsif register_number=49 then
          -- Can emulate VIC-III H640, V400 and H1280 by adjusting x and y scale
          -- registers
          fastio_rdata <=
            reg_h640                           -- H640
            & viciii_fast_internal             -- FAST
            & viciii_extended_attributes  -- ATTR (8bit colour RAM features)
            & bitplane_mode                    -- BPM
            & reg_v400                         -- V400
            & reg_h1280                         -- H1280
            & reg_mono                         -- Mono mode for composite output
            & reg_interlace;                   -- INT(erlaced?)


                                        -- Skip $D02F - $D03F to avoid real C65/C128 programs trying to
                                        -- fiddle with registers in this range.
                                        --  For more C65 register info, see:
                                        -- http://www.zimmers.net/cbmpics/cbm/c65/c65manual.txt
        -- @IO:C65 $D032 - Bitplane enable bits
        elsif register_number=50 then
          fastio_rdata <= bitplane_enables;
        -- @IO:C65 $D033 - Bitplane 0 address
        -- @IO:C65 $D034 - Bitplane 1 address
        -- @IO:C65 $D035 - Bitplane 2 address
        -- @IO:C65 $D036 - Bitplane 3 address
        -- @IO:C65 $D037 - Bitplane 4 address
        -- @IO:C65 $D038 - Bitplane 5 address
        -- @IO:C65 $D039 - Bitplane 6 address
        -- @IO:C65 $D03A - Bitplane 7 address
        elsif register_number >= 51 and register_number <= 58 then
          -- @IO:C65 $D033-$D03A - VIC-III Bitplane addresses
          bitplane_number := safe_to_integer(register_number(3 downto 0)) - 3;
          fastio_rdata <= std_logic_vector(bitplane_addresses(bitplane_number));
        -- @IO:C65 $D03B - Set bits to NOT bitplane contents
        elsif register_number=59 then
          fastio_rdata <= bitplane_complements;
        -- @IO:C65 $D03C - Bitplane X
        elsif register_number=60 then
          fastio_rdata(6 downto 0) <= std_logic_vector(dat_x(6 downto 0));
          fastio_rdata(7) <= dat_y(8);
        -- @IO:C65 $D03D - Bitplane Y
        elsif register_number=61 then
          fastio_rdata <= std_logic_vector(dat_y(7 downto 0));
        -- @IO:C65 $D03E - Horizontal position (screen verniers?)
        elsif register_number=62 then
          fastio_rdata <= std_logic_vector(bitplanes_x_start);
        -- @IO:C65 $D03F - Vertical position (screen verniers?)
        elsif register_number=63 then
          fastio_rdata <= std_logic_vector(bitplanes_y_start);

        -- $D040 - $D047 DAT memory ports for bitplanes 0 through 7
        -- XXX: Deprecated old addresses for some VIC-IV features currently occupy
        -- these addresses
        elsif register_number=64 then
          -- Unimplemented VIC-III DAC
          fastio_rdata <= x"FF";
        elsif register_number=65 then
          -- Unimplemented VIC-III DAC
          fastio_rdata <= x"FF";
        elsif register_number=66 then
          -- Unimplemented VIC-III DAC
          fastio_rdata <= x"FF";
        elsif register_number=67 then
          -- Unimplemented VIC-III DAC
          fastio_rdata <= x"FF";
        elsif register_number=68 then
          -- Unimplemented VIC-III DAC
          fastio_rdata <= x"FF";
        elsif register_number=69 then
          -- Unimplemented VIC-III DAC
          fastio_rdata <= x"FF";
        elsif register_number=70 then
          -- Unimplemented VIC-III DAC
          fastio_rdata <= x"FF";
        elsif register_number=71 then
          -- Unimplemented VIC-III DAC
          fastio_rdata <= x"FF";
        elsif register_number=72 then
          fastio_rdata <= std_logic_vector(border_y_top(7 downto 0));
        elsif register_number=73 then
          fastio_rdata(7 downto 4) <= sprite_bitplane_enables(3 downto 0);
          fastio_rdata(3 downto 0) <= std_logic_vector(border_y_top(11 downto 8));
        elsif register_number=74 then
          fastio_rdata <= std_logic_vector(border_y_bottom(7 downto 0));
        elsif register_number=75 then
          fastio_rdata(7 downto 4) <= sprite_bitplane_enables(7 downto 4);
          fastio_rdata(3 downto 0) <= std_logic_vector(border_y_bottom(11 downto 8));
        elsif register_number=76 then
          fastio_rdata <= std_logic_vector(x_chargen_start(7 downto 0));
        elsif register_number=77 then
          fastio_rdata(7 downto 4) <= sprite_horizontal_tile_enables(3 downto 0);
          fastio_rdata(3 downto 0) <= std_logic_vector(x_chargen_start(11 downto 8));
        elsif register_number=78 then
          fastio_rdata <= std_logic_vector(y_chargen_start(7 downto 0));
        elsif register_number=79 then
          fastio_rdata(7 downto 4) <= sprite_horizontal_tile_enables(7 downto 4);
          fastio_rdata(3 downto 0) <= std_logic_vector(y_chargen_start(11 downto 8));
        elsif register_number=80 then
          fastio_rdata <= std_logic_vector(xcounter_drive(7 downto 0));
        elsif register_number=81 then
          fastio_rdata(7) <= no_raster_buffer_delay;
          fastio_rdata(6) <= raster_buffer_double_line;
          fastio_rdata(5 downto 0) <= std_logic_vector(xcounter_drive(13 downto 8));
        elsif register_number=82 then
          -- Read physical raster LSB
          fastio_rdata <= std_logic_vector(ycounter_drive(7 downto 0));
        elsif register_number=83 then
          -- Read physical raster MSB and raster compare source flag
          fastio_rdata(7) <= vicii_is_raster_source;
          fastio_rdata(6) <= shadow_mask_enable;
          fastio_rdata(5) <= upscale_enable_int;
          fastio_rdata(4) <= '0';
          fastio_rdata(3 downto 0) <= std_logic_vector(ycounter_drive(11 downto 8));
        elsif register_number=84 then
                                        -- $D054 (53332) - New mode control register
          fastio_rdata(7) <= compositer_enable;
          fastio_rdata(6) <= viciv_fast_internal;
          fastio_rdata(5) <= pal_simulate;
          fastio_rdata(4) <= sprite_h640;
          fastio_rdata(3) <= horizontal_filter;
          fastio_rdata(2) <= fullcolour_extendedchars;
          fastio_rdata(1) <= fullcolour_8bitchars;
          fastio_rdata(0) <= sixteenbit_charset;
        elsif register_number=85 then
          fastio_rdata <= sprite_extended_height_enables;
        elsif register_number=86 then
          fastio_rdata <= std_logic_vector(sprite_extended_height_size);
        elsif register_number=87 then
          fastio_rdata <= sprite_extended_width_enables;
        elsif register_number=88 then
          fastio_rdata <= std_logic_vector(virtual_row_width(7 downto 0));
        elsif register_number=89 then
          fastio_rdata <= std_logic_vector(virtual_row_width(15 downto 8));
        elsif register_number=90 then
          fastio_rdata <= std_logic_vector(chargen_x_scale_drive);
        elsif register_number=91 then
          fastio_rdata <= std_logic_vector(chargen_y_scale);
        elsif register_number=92 then
          fastio_rdata <= std_logic_vector(single_side_border(7 downto 0));
        elsif register_number=93 then
          fastio_rdata(7) <= vicii_hot_regs_enable;
          fastio_rdata(6) <= enable_raster_delay;
          fastio_rdata(5 downto 0) <= std_logic_vector(single_side_border(13 downto 8));
        elsif register_number=94 then
          fastio_rdata(7 downto 0)  <= std_logic_vector(display_row_width(7 downto 0));
        elsif register_number=95 then
          fastio_rdata <= std_logic_vector(sprite_h640_msbs);
        elsif register_number=96 then
          fastio_rdata <= std_logic_vector(screen_ram_base(7 downto 0));
        elsif register_number=97 then
          fastio_rdata <= std_logic_vector(screen_ram_base(15 downto 8));
        elsif register_number=98 then
          fastio_rdata <= std_logic_vector(screen_ram_base(23 downto 16));
        elsif register_number=99 then
          fastio_rdata(7) <= glyphs_from_hyperram;
          fastio_rdata(6) <= fullcolour_mcm;
          fastio_rdata(5 downto 4) <= std_logic_vector(display_row_width(9 downto 8));
          fastio_rdata(3 downto 0) <= std_logic_vector(screen_ram_base(27 downto 24));
        elsif register_number=100 then
          fastio_rdata <= std_logic_vector(colour_ram_base(7 downto 0));
        elsif register_number=101 then
          fastio_rdata <= std_logic_vector(colour_ram_base(15 downto 8));
        elsif register_number=102 then -- $D3066 xcounter_pipeline_delayed delay
          fastio_rdata(5 downto 0) <= std_logic_vector(to_unsigned(reg_xcounter_delay,6));
          fastio_rdata(6) <= show_render_activity;
          fastio_rdata(7) <= test_pattern_enable;
        elsif register_number=103 then  -- $D3067
          fastio_rdata <= std_logic_vector(sprite_first_x(7 downto 0));
        elsif register_number=104 then  -- $D068
          fastio_rdata <= std_logic_vector(character_set_address(7 downto 0));
        elsif register_number=105 then
          fastio_rdata <= std_logic_vector(character_set_address(15 downto 8));
        elsif register_number=106 then
          fastio_rdata <= std_logic_vector(character_set_address(23 downto 16));
        elsif register_number=107 then
          fastio_rdata <= std_logic_vector(sprite_sixteen_colour_enables);
        elsif register_number=108 then
          fastio_rdata <= std_logic_vector(vicii_sprite_pointer_address(7 downto 0));
        elsif register_number=109 then
          fastio_rdata <= std_logic_vector(vicii_sprite_pointer_address(15 downto 8));
        elsif register_number=110 then
          fastio_rdata <= std_logic_vector(vicii_sprite_pointer_address(23 downto 16));
        elsif register_number=111 then
          fastio_rdata(7) <= vicii_ntsc;
          fastio_rdata(6) <= vga60_select_internal;
          fastio_rdata(5 downto 0) <= std_logic_vector(vicii_first_raster(5 downto 0));
        elsif register_number=112 then -- $D3070
          fastio_rdata <= palette_bank_fastio & palette_bank_chargen & palette_bank_sprites & palette_bank_chargen_alt;
        elsif register_number=113 then -- $D3071
          fastio_rdata <= bitplane_sixteen_colour_mode_flags;
        elsif register_number=114 then -- $D3072
          fastio_rdata(7 downto 0) <= std_logic_vector(sprite_y_adjust);
        elsif register_number=115 then -- $D3073
          fastio_rdata(3 downto 0) <= std_logic_vector(reg_alpha_delay);
          fastio_rdata(7 downto 4) <= std_logic_vector(vicii_ycounter_scale_minus_zero(3 downto 0));
        elsif register_number=116 then  -- $D3074
          fastio_rdata <= sprite_alpha_blend_enables;
        elsif register_number=117 then  -- $D3075
          fastio_rdata(7 downto 0) <= std_logic_vector(sprite_alpha_blend_value);
        elsif register_number=118 then  -- $D3076 Sprite V400 enables
          fastio_rdata <= std_logic_vector(sprite_v400s);
        elsif register_number=119 then  -- $D3077 Sprite V400 Y position MSBs
	  fastio_rdata <= sprite_v400_msbs;
        elsif register_number=120 then  -- $D3078 Sprite V400 Y position super MSBs
	  fastio_rdata <= sprite_v400_super_msbs;
        elsif register_number=121 then  -- $D3079 Read raster compare LSB
          fastio_rdata <= std_logic_vector(vicii_raster_compare(7 downto 0));
        elsif register_number=122 then  -- $D307A Read raster compare MSB / raster compare source
          fastio_rdata(2 downto 0) <= std_logic_vector(vicii_raster_compare(10 downto 8));
          fastio_rdata(3) <= sprite_continuous_pointer_monitoring;
          fastio_rdata(4) <= reg_char_y16;
          fastio_rdata(5) <= not bug_compat_mode;
          fastio_rdata(6) <= '0';
	  fastio_rdata(7) <= vicii_is_raster_source;
        elsif register_number=123 then  -- $D307B
          fastio_rdata <= std_logic_vector(display_row_count(7 downto 0));
        elsif register_number=124 then  -- $D307C
          -- fastio_rdata(3 downto 0) <= x"F";
          fastio_rdata(2 downto 0) <= std_logic_vector(bitplane_bank_select);
          fastio_rdata(3) <= '0';
          fastio_rdata(4) <= hsync_polarity_internal;
          fastio_rdata(5) <= vsync_polarity_internal;
          fastio_rdata(7 downto 6) <= "11";
        elsif register_number=125 then
          -- fastio_rdata <=
          --  std_logic_vector(to_unsigned(vic_paint_fsm'pos(debug_paint_fsm_state_drive2),8));
          -- fastio_rdata <= std_logic_vector(debug_charaddress_drive2(7 downto 0));
          -- fastio_rdata <= x"FF";
          -- XXX debug: $D07D shows current single top border height
--          fastio_rdata <= std_logic_vector(single_top_border_200(7 downto 0));
          if hypervisor_mode='0' then
            case debug_channel_select is
              when "00" => fastio_rdata <= std_logic_vector(hyper_data_counter(7 downto 0));
              when "01" => fastio_rdata <= std_logic_vector(debug_pixel_red);
              when "10" => fastio_rdata <= std_logic_vector(debug_pixel_green);
              when "11" => fastio_rdata <= std_logic_vector(debug_pixel_blue);
              when others => fastio_rdata <= std_logic_vector(debug_pixel_blue);
            end case;
          else
            -- In hypervisor mode, allow read-back of the debug crosshair positions
            -- so that when we freeze and resume, it isn't put into the wrong place
            fastio_rdata <= std_logic_vector(debug_x(7 downto 0));
          end if;
        elsif register_number=126 then
          -- fastio_rdata <= "0000"
          -- & std_logic_vector(debug_charaddress_drive2(11 downto 8));
--          fastio_rdata <= x"00";
--          fastio_rdata(0) <= external_frame_x_zero_latched;
--          fastio_rdata(1) <= external_pixel_strobe_log(0);
--          fastio_rdata(2) <= vga_in_frame;
--          fastio_rdata(3) <= indisplay_t3;
          if hypervisor_mode='0' then
            fastio_rdata <= std_logic_vector(hyper_data_counter(15 downto 8));
          else
            -- In hypervisor mode, allow read-back of the debug crosshair positions
            -- so that when we freeze and resume, it isn't put into the wrong place
            fastio_rdata <= std_logic_vector(debug_y(7 downto 0));
          end if;
        elsif register_number=127 then
          if hypervisor_mode='0' then
            fastio_rdata <= std_logic_vector(hyper_data_counter(23 downto 16));
          else
            -- In hypervisor mode, allow read-back of the debug crosshair positions
            -- so that when we freeze and resume, it isn't put into the wrong place
            fastio_rdata(3 downto 0) <= std_logic_vector(debug_x(11 downto 8));
            fastio_rdata(7 downto 4) <= std_logic_vector(debug_y(11 downto 8));
          end if;
        elsif register_number<256 then
                                        -- Fill in unused register space
          fastio_rdata <= (others => 'Z');
                                        -- C65 style palette registers
        elsif register_number>=256 and register_number<512 then
          -- red palette
          report "Outputting RED palette read value $" & to_hstring(palette_fastio_rdata(31 downto 24));
          palette_fastio_address <= palette_bank_fastio & std_logic_vector(register_number(7 downto 0));
          fastio_rdata <= palette_fastio_rdata(31 downto 24);
        elsif register_number>=512 and register_number<768 then
          -- green palette
          report "Outputting GREEN palette read value $" & to_hstring(palette_fastio_rdata(23 downto 16));
          palette_fastio_address <= palette_bank_fastio & std_logic_vector(register_number(7 downto 0));
          fastio_rdata <= palette_fastio_rdata(23 downto 16);
        elsif register_number>=768 and register_number<1024 then
          -- blue palette
          report "Outputting BLUE palette read value $" & to_hstring(palette_fastio_rdata(15 downto 8));
          palette_fastio_address <= palette_bank_fastio & std_logic_vector(register_number(7 downto 0));
          fastio_rdata <= palette_fastio_rdata(15 downto 8);
        else
          fastio_rdata <= (others => 'Z');
        end if;
      end if;
    end if;

    if rising_edge(cpuclock) then

      if hw_errata_level /= prev_hw_errata_level then
        prev_hw_errata_level <= hw_errata_level;

        -- Apply variable HW errata level settings
        -- Level 1: VIC-III D016 Delta
        if to_integer(hw_errata_level) > 0 then
          bug_compat_vic_iii_d016_delta <= 0;
          bug_compat_mode <= '0';
        else
          bug_compat_vic_iii_d016_delta <= 2;
          bug_compat_mode <= '1';
        end if;
        -- Level 2: Character attribute fixes
        if to_integer(hw_errata_level) > 1 then
          bug_compat_char_attr <= '0';
        else
          bug_compat_char_attr <= '1';
        end if;
      end if;

      upscale_enable <= upscale_enable_int;

      interlace_mode <= reg_interlace;
      mono_mode <= reg_mono;

      last_dd00_bits <= dd00_bits;
      if last_dd00_bits /= dd00_bits then
        viciv_legacy_mode_registers_touched <= '1';
      end if;

      if reset='0' then
        -- Reset sprites to normal behaviour on reset
        sprite_horizontal_tile_enables <= (others => '0');
        sprite_v400_super_msbs <= (others => '0');
        sprite_alpha_blend_enables <= (others => '0');
        sprite_bitplane_enables <= (others => '0');
        sprite_extended_width_enables <= (others => '0');
        sprite_extended_height_enables <= (others => '0');
        sprite_sixteen_colour_enables <= (others => '0');
        -- And raster re-write buffer delay also
        no_raster_buffer_delay <= '1';
        raster_buffer_double_line <= '0';
        reg_char_y16 <= '0';

      end if;

      -- Drive stage for data from hyper RAM and signals out to it
      hyper_data <= hyper_data_in;
      hyper_data_strobe <= hyper_data_strobe_in;
      hyper_addr <= hyper_addr_drive;
      hyper_request_toggle_drive2 <= hyper_request_toggle_drive;
      hyper_request_toggle_drive3 <= hyper_request_toggle_drive2;
      hyper_request_toggle <= hyper_request_toggle_drive3;

      if hyper_data_strobe = '1' then
        hyper_data_counter <= hyper_data_counter + 1;
      end if;

      if vicii_ntsc='1' then
        display_height <= display_height_ntsc;
      else
        display_height <= display_height_pal;
      end if;

      vicii_raster_out(8 downto 0) <= vicii_ycounter_driver;
      vicii_raster_out(11 downto 9) <= "000";

      hsync_polarity <= hsync_polarity_internal;
      vsync_polarity <= vsync_polarity_internal;

      vicii_ycounter_driver <= vicii_ycounter;
      -- We need a delayed version of the VICII ycounter to display in $D011/$D012,
      -- as raster interrupts actually happen one raster line later than expected,
      -- to offset the fact that we have a 1 raster line delay in output of the
      -- video pipeline.
      -- That is, we trigger the interrupt when the raster is actually being DISPLAYED,
      -- and make the contents of $D012/$D011 match this.
      if enable_raster_delay='1' then
        if vicii_ycounter_driver /= 0 then
          vicii_ycounter_minus_one <= vicii_ycounter_driver - 1;
        else
          vicii_ycounter_minus_one <= vicii_max_raster;
        end if;
      else
        vicii_ycounter_minus_one <= vicii_ycounter_driver;
      end if;

      viciv_calculate_modeline_dimensions;

      -- Set IO mode when CPU tells us to.  This is done when entering/exiting
      -- hypervisor mode.
      if iomode_set_toggle /= iomode_set_toggle_last then
        iomode_set_toggle_last <= iomode_set_toggle;
        viciii_iomode <= iomode_set;
      end if;

      viciv_fast <= viciv_fast_internal;
      viciii_fast <= viciii_fast_internal;
      vicii_2mhz <= not vicii_2mhz_internal;

      reset_drive <= reset;
      if reset_drive='0' then
        -- Disable HW errata on reset.
        hw_errata_disable_toggle <= not hw_errata_disable_toggle;

        -- Allow hyppo ROM to be visible on reset.
        rom_at_e000 <= '0';

        -- Enable VIC-II/III registers to force video mode settings when touched
        vicii_hot_regs_enable <= '1';

        -- Set CPU to 48MHz
        viciv_fast_internal <= '1';
        viciii_fast_internal <= '1';
        vicii_2mhz_internal <= '0';

        -- Clear all VIC-II/III/IV interrupts on reset
        mask_collisionspritebitmap <= '0';
        mask_collisionspritesprite <= '0';
        mask_raster <= '0';

      -- Also turn sprites off on reset
--        vicii_sprite_enables <= (others => '0');
      end if;

      report "drive led = " & std_logic'image(led)
        & ", drive motor= " & std_logic'image(motor) severity note;

      debug_chargen_active_drive2 <= debug_chargen_active_drive;
      debug_chargen_active_soon_drive2 <= debug_chargen_active_soon_drive;
      debug_raster_fetch_state_drive2 <= debug_raster_fetch_state_drive;
      debug_paint_fsm_state_drive2 <= debug_paint_fsm_state_drive;
      debug_charrow_drive2 <= debug_charrow_drive;
      debug_charaddress_drive2 <= debug_charaddress_drive;
      debug_character_data_from_rom_drive2 <= debug_character_data_from_rom_drive;
      debug_screen_ram_buffer_address_drive2 <= debug_screen_ram_buffer_address_drive;
      debug_raster_buffer_read_address_drive2 <= debug_raster_buffer_read_address_drive;
      debug_raster_buffer_write_address_drive2 <= debug_raster_buffer_write_address_drive;

      inborder_drive <= inborder;
      chargen_active_soon_drive <= chargen_active_soon;
      cycles_to_next_card_drive <= cycles_to_next_card;
      chargen_active_drive <= chargen_active;
      xcounter_drive <= xcounter;
      ycounter_drive <= ycounter;
      xfrontporch_drive <= xfrontporch;

      if viciv_legacy_mode_registers_touched='1' and vicii_hot_regs_enable='1' then
        viciv_interpret_legacy_mode_registers;
        viciv_update_side_border_dimensions;
        viciv_legacy_mode_registers_touched <= '0';
      end if;
      if viciv_single_side_border_width_touched='1' then
        viciv_update_side_border_dimensions;
        viciv_single_side_border_width_touched <= '0';
      end if;

      ack_lightpen <= '0';
      ack_collisionspritesprite <= '0';
      ack_collisionspritebitmap <= '0';
      ack_raster <= '0';

      palette_we <= (others => '0');

      -- Get VIC-II sprite data offsets
      -- (this can happen on cpuclock, since it should still allow ample time
      --  to synchronise with the sprites before we fetch the data for them).
      -- Save offset delivered by chain
--      report "SPRITE: VIC-II sprite "
--        & integer'image(sprite_number_for_data_rx)
--        & " = " & integer'image(sprite_data_offset_rx);
--      sprite_data_offsets(sprite_number_for_data_rx) <= sprite_data_offset_rx;
--      -- Ask for the next one (8 sprites + 8 C65 bitplanes)
--      if sprite_number_counter = 15 then
--        sprite_number_counter <= 0;
--        sprite_number_for_data_tx <= 0;
--      else
--        sprite_number_counter <= sprite_number_counter + 1;
--        sprite_number_for_data_tx <= sprite_number_for_data_tx + 1;
--      end if;


      -- Reading some registers clears IRQ flags
      clear_collisionspritebitmap_1 <= '0';
      clear_collisionspritesprite_1 <= '0';
      if fastio_read='1' then
        if register_number=30 then
          -- @IO:C64 $D01E sprite/sprite collissions
          clear_collisionspritesprite_1 <= '1';
        elsif register_number=31 then
          -- @IO:C64 $D01F sprite/foreground collissions
          clear_collisionspritebitmap_1 <= '1';
        end if;
      end if;
      -- One cycle delay so that CPU can read these registers with 1 cycle
      -- wait-state without the collision bits disappearing before the CPU
      -- latches the value.
      clear_collisionspritebitmap <= clear_collisionspritebitmap_1;
      clear_collisionspritesprite <= clear_collisionspritesprite_1;

      -- $D000 registers
      if fastio_write='1'
        and (fastio_addr(19) = '0' or fastio_addr(19) = '1') then
        if register_number>=0 and register_number<8 then
          -- compatibility sprite coordinates
          -- @IO:C64 $D000 VIC-II:S0X@SNX sprite N horizontal position
          -- @IO:C64 $D001 VIC-II:S0Y@SNY sprite N vertical position
          -- @IO:C64 $D002 VIC-II:S1X @SNX
          -- @IO:C64 $D003 VIC-II:S1Y @SNY
          -- @IO:C64 $D004 VIC-II:S2X @SNX
          -- @IO:C64 $D005 VIC-II:S2Y @SNY
          -- @IO:C64 $D006 VIC-II:S3X @SNX
          -- @IO:C64 $D007 VIC-II:S3Y @SNY
          sprite_x(safe_to_integer(register_num(2 downto 0))) <= unsigned(fastio_wdata);
        elsif register_number<16 then
          -- @IO:C64 $D008 VIC-II:S4X @SNX
          -- @IO:C64 $D009 VIC-II:S4Y @SNY
          -- @IO:C64 $D00A VIC-II:S5X @SNX
          -- @IO:C64 $D00B VIC-II:S5Y @SNY
          -- @IO:C64 $D00C VIC-II:S6X @SNX
          -- @IO:C64 $D00D VIC-II:S6Y @SNY
          -- @IO:C64 $D00E VIC-II:S7X @SNX
          -- @IO:C64 $D00F VIC-II:S7Y @SNY
          sprite_y(safe_to_integer(register_num(2 downto 0))) <= unsigned(fastio_wdata);
        elsif register_number=16 then
          -- @IO:C64 $D010 VIC-II:SXMSB sprite horizontal position MSBs
          vicii_sprite_xmsbs <= fastio_wdata;
        elsif register_number=17 then             -- $D011
          report "D011 WRITTEN" severity note;
          -- @IO:C64 $D011 VIC-II control register
          -- @IO:C64 $D011.7 VIC-II:RC8 raster compare bit 8
          vicii_raster_compare(10 downto 8) <= "00" & fastio_wdata(7);
          vicii_is_raster_source <= '1';
          -- @IO:C64 $D011.6 VIC-II:ECM extended background mode
          extended_background_mode <= fastio_wdata(6);
          -- @IO:C64 $D011.5 VIC-II:BMM bitmap mode
          text_mode <= not fastio_wdata(5);
          -- @IO:C64 $D011.4 VIC-II:BLNK Enable display: 0 = blank the display, 1 = show the display
          blank <= not fastio_wdata(4);
          -- @IO:C64 $D011.3 VIC-II:RSEL 24/25 row select
          twentyfourlines <= not fastio_wdata(3);
          -- @IO:C64 $D011.2-0 VIC-II:YSCL 24/25 vertical smooth scroll
          vicii_y_smoothscroll <= unsigned(fastio_wdata(2 downto 0));
          viciv_legacy_mode_registers_touched <= '1';

        elsif register_number=18 then
          -- @IO:C64 $D012 VIC-II:RC raster compare bits 0 to 7
          vicii_raster_compare(7 downto 0) <= unsigned(fastio_wdata);
          vicii_is_raster_source <= '1';
        elsif register_number=19 then
        -- @IO:C64 $D013 VIC-II:LPX Coarse horizontal beam position (was lightpen X)
        elsif register_number=20 then
        -- @IO:C64 $D014 VIC-II:LPY Coarse vertical beam position (was lightpen Y)
        elsif register_number=21 then
          -- @IO:C64 $D015 VIC-II:SE sprite enable bits
          vicii_sprite_enables <= fastio_wdata;
        elsif register_number=22 then
          -- @IO:C64 $D016 VIC-II control register
          -- @IO:C64 $D016.5 VIC-II:RST Disables video output on MAX Machine(tm) VIC-II 6566.  Ignored on normal C64s and the MEGA65
          -- @IO:C64 $D016.4 VIC-II:MCM Multi-colour mode
          multicolour_mode <= fastio_wdata(4);
          -- @IO:C64 $D016.3 VIC-II:CSEL 38/40 column select
          thirtyeightcolumns <= not fastio_wdata(3);
          -- @IO:C64 $D016.2-0 VIC-II:XSCL horizontal smooth scroll
          vicii_x_smoothscroll <= unsigned(fastio_wdata(2 downto 0));
          viciv_legacy_mode_registers_touched <= '1';
        elsif register_number=23 then
          -- @IO:C64 $D017 VIC-II:SEXY sprite vertical expansion enable bits
          vicii_sprite_y_expand <= fastio_wdata;
        elsif register_number=24 then
          -- @IO:C64 $D018 VIC-II RAM addresses
          -- Character set source address for user-generated character sets.
          -- @IO:C64 $D018.3-1 VIC-II:CB character set address location ($\times$ 1KiB)
          character_set_address(13 downto 11) <= unsigned(fastio_wdata(3 downto 1));
          character_set_address(10 downto 0) <= (others => '0');
          -- Bits 14 and 15 get set by writing to $DD00, as the VIC-IV sniffs
          -- that CIA register being written on the fastio bus.
          -- Writing here also automatically clears the bank select bits for
          -- the screen RAM address, so that writing to $D018 always works as expected.
          screen_ram_base(19 downto 16) <= "0000";
          -- @IO:C64 $D018.7-4 VIC-II:VS screen address ($\times$ 1KiB)
          reg_d018_screen_addr <= unsigned(fastio_wdata(7 downto 4));
          viciv_legacy_mode_registers_touched <= '1';
        elsif register_number=25 then
          -- @IO:C64 $D019 VIC-II IRQ control
          -- Acknowledge IRQs
          -- (we need to pass this to the dotclock side to avoide multiple drivers)
          -- @IO:C64 $D019.3 VIC-II:ILP light pen indicate or acknowledge
          ack_lightpen <= fastio_wdata(3);
          -- @IO:C64 $D019.2 VIC-II:ISSC sprite:sprite collision indicate or acknowledge
          ack_collisionspritesprite <= fastio_wdata(2);
          -- @IO:C64 $D019.1 VIC-II:ISBC sprite:bitmap collision indicate or acknowledge
          ack_collisionspritebitmap <= fastio_wdata(1);
          -- @IO:C64 $D019.0 VIC-II:RIRQ raster compare indicate or acknowledge
          ack_raster <= fastio_wdata(0);
        elsif register_number=26 then
          -- @IO:C64 $D01A compatibility IRQ mask bits
          -- XXX Enable/disable IRQs
          -- @IO:C64 $D01A.2 VIC-II:MISSC mask sprite:sprite collision IRQ
          mask_collisionspritesprite <= fastio_wdata(2);
          -- @IO:C64 $D01A.1 VIC-II:MISBC mask sprite:bitmap collision IRQ
          mask_collisionspritebitmap <= fastio_wdata(1);
          -- @IO:C64 $D01A.0 VIC-II:MRIRQ mask raster IRQ
          mask_raster <= fastio_wdata(0);
        elsif register_number=27 then
          -- @IO:C64 $D01B VIC-II:BSP sprite background priority bits
          vicii_sprite_priority_bits <= fastio_wdata;
        elsif register_number=28 then
          -- @IO:C64 $D01C VIC-II:SCM sprite multicolour enable bits
          vicii_sprite_multicolour_bits <= fastio_wdata;
        elsif register_number=29 then
          -- @IO:C64 $D01D VIC-II:SEXX sprite horizontal expansion enable bits
          vicii_sprite_x_expand <= fastio_wdata;
        elsif register_number=30 then
        -- @IO:C64 $D01E VIC-II:SSC sprite/sprite collision indicate bits
        -- vicii_sprite_sprite_collisions <= fastio_wdata;
        elsif register_number=31 then
        -- @IO:C64 $D01F VIC-II:SBC sprite/foreground collision indicate bits
        -- vicii_sprite_bitmap_collisions <= fastio_wdata;
        elsif register_number=32 then
          -- @IO:C64 $D020 Border colour
          -- @IO:C64 $D020.3-0 VIC-II:BORDERCOL display border colour (16 colour)
          -- @IO:C65 $D020.7-0 VIC-III:BORDERCOL display border colour (256 colour)
          -- @IO:GS $D020.7-0 VIC-IV:BORDERCOL display border colour (256 colour)
          if register_bank=x"D0" then
            border_colour(3 downto 0) <= unsigned(fastio_wdata(3 downto 0));
          else
            border_colour <= unsigned(fastio_wdata);
          end if;
        elsif register_number=33 then
          -- @IO:C64 $D021 Screen colour
          -- @IO:C64 $D021.3-0 VIC-II:SCREENCOL screen colour (16 colour)
          -- @IO:C65 $D021.7-0 VIC-III:SCREENCOL screen colour (256 colour)
          -- @IO:GS $D021.7-0 VIC-IV:SCREENCOL screen colour (256 colour)
          if register_bank=x"D0" then
            screen_colour(3 downto 0) <= unsigned(fastio_wdata(3 downto 0));
          else
            screen_colour <= unsigned(fastio_wdata);
          end if;
        elsif register_number=34 then
          -- @IO:C64 $D022 VIC-II multi-colour 1
          -- @IO:C64 $D022.3-0 VIC-II:MC1 multi-colour 1 (16 colour)
          -- @IO:C65 $D022.7-0 VIC-III:MC1 multi-colour 1 (256 colour)
          -- @IO:GS $D022.7-0 VIC-IV:MC1 multi-colour 1 (256 colour)
          if register_bank=x"D0" then
            multi1_colour <= unsigned("0000"&fastio_wdata(3 downto 0));
          else
            multi1_colour <= unsigned(fastio_wdata);
          end if;
        elsif register_number=35 then
          -- @IO:C64 $D023 VIC-II multi-colour 2
          -- @IO:C64 $D023.3-0 VIC-II:MC2 multi-colour 2 (16 colour)
          -- @IO:C65 $D023.7-0 VIC-III:MC2 multi-colour 2 (256 colour)
          -- @IO:GS $D023.7-0 VIC-IV:MC2 multi-colour 2 (256 colour)
          if register_bank=x"D0" then
            multi2_colour <= unsigned("0000"&fastio_wdata(3 downto 0));
          else
            multi2_colour <= unsigned(fastio_wdata);
          end if;
        elsif register_number=36 then
          -- @IO:C64 $D024 VIC-II multi-colour 3
          -- @IO:C64 $D024.3-0 VIC-II:MC3 multi-colour 3 (16 colour)
          -- @IO:C65 $D024.7-0 VIC-III:MC3 multi-colour 3 (256 colour)
          -- @IO:GS $D024.7-0 VIC-IV:MC3 multi-colour 3 (256 colour)
          if register_bank=x"D0" then
            multi3_colour <= unsigned("0000"&fastio_wdata(3 downto 0));
          else
            multi3_colour <= unsigned(fastio_wdata);
          end if;
        elsif register_number=37 then
          -- @IO:C64 $D025 VIC-II:SPRMC0 Sprite multi-colour 0
          -- @IO:C65 $D025 VIC-III:SPRMC0 Sprite multi-colour 0 (8-bit for selection of any palette colour)
          -- @IO:GS $D025 VIC-IV:SPRMC0 Sprite multi-colour 0 (8-bit for selection of any palette colour)
          if register_bank=x"D0" then
            sprite_multi0_colour <= unsigned("0000"&fastio_wdata(3 downto 0));
          else
            sprite_multi0_colour <= unsigned(fastio_wdata);
          end if;
        elsif register_number=38 then
          -- @IO:C64 $D026 VIC-II:SPRMC1 Sprite multi-colour 1
          -- @IO:C65 $D026 VIC-III:SPRMC1 Sprite multi-colour 1 (8-bit for selection of any palette colour)
          -- @IO:GS $D026 VIC-IV:SPRMC1 Sprite multi-colour 1 (8-bit for selection of any palette colour)
          if register_bank=x"D0" then
            sprite_multi1_colour <= unsigned("0000"&fastio_wdata(3 downto 0));
          else
            sprite_multi1_colour <= unsigned(fastio_wdata);
          end if;
        elsif register_number>=39 and register_number<=46 then
          -- @IO:C64 $D027 VIC-II:SPR0COL@SPRNCOL sprite N colour / 16-colour sprite transparency colour (lower nybl)
          -- @IO:C64 $D028 VIC-II:SPR1COL @SPRNCOL
          -- @IO:C64 $D029 VIC-II:SPR2COL @SPRNCOL
          -- @IO:C64 $D02A VIC-II:SPR3COL @SPRNCOL
          -- @IO:C64 $D02B VIC-II:SPR4COL @SPRNCOL
          -- @IO:C64 $D02C VIC-II:SPR5COL @SPRNCOL
          -- @IO:C64 $D02D VIC-II:SPR6COL @SPRNCOL
          -- @IO:C64 $D02E VIC-II:SPR7COL @SPRNCOL
          if register_bank=x"D0" then
            sprite_colours(safe_to_integer(register_number)-39)(3 downto 0) <= unsigned(fastio_wdata(3 downto 0));
          else
            sprite_colours(safe_to_integer(register_number)-39) <= unsigned(fastio_wdata);
          end if;
        -- Skip $D02F - $D047 to avoid real C65/C128 programs trying to
        -- fiddle with registers in this range.
        -- NEW VIDEO REGISTERS
        elsif register_number=47 then
          -- @IO:C65 $D02F VIC-III KEY register for unlocking extended registers.
          -- @IO:C65 $D02F VIC-III:KEY Write $A5 then $96 to enable C65/VIC-III IO registers
          -- @IO:C65 $D02F Write anything else to return to C64/VIC-II IO map
          viciii_iomode <= "00"; -- by default go back to VIC-II mode
          if reg_key=x"a5" then
            if fastio_wdata=x"96" then
              -- C65 VIC-III mode
              viciii_iomode <= "01";
            end if;
          -- @IO:GS $D02F VIC-IV:KEY Write $47 then $53 to enable C65GS/VIC-IV IO registers
          elsif reg_key=x"47" then
            if fastio_wdata=x"53" then
              -- C65GS VIC-IV mode
              viciii_iomode <= "11";
            end if;
          -- @IO:GS $D02F VIC-IV:KEY Write $45 then $54 to map 45E100 ethernet controller buffers to $D000-$DFFF
          elsif reg_key=x"45" then
            if fastio_wdata=x"54" then
              -- C65GS Map ethernet frame buffer mode
              viciii_iomode <= "10";
            end if;
          end if;
          reg_key <= unsigned(fastio_wdata);
        elsif register_number=255 then
          -- @IO:C64 $D030 SUMMARY: C128 2MHz emulation
          -- @IO:C64 $D030.0 VIC-II:C128!FAST 2MHz select (for C128 2MHz emulation)
          vicii_2mhz_internal <= fastio_wdata(0);
        elsif register_number=48 then
          -- @IO:C65 $D030 SUMMARY:VIC-III Control Register A
          -- @IO:C65 $D030.7 VIC-III:ROME Map C65 ROM @ $E000
          rom_at_e000 <= fastio_wdata(7);
          reg_rom_e000 <= fastio_wdata(7);
          -- @IO:C65 $D030.6 VIC-III:CROM9 Select between C64 and C65 charset.
          reg_c65_charset <= fastio_wdata(6);
          -- @IO:C65 $D030.5 VIC-III:ROMC Map C65 ROM @ $C000
          rom_at_c000 <= fastio_wdata(5);
          reg_rom_c000 <= fastio_wdata(5);
          -- @IO:C65 $D030.4 VIC-III:ROMA Map C65 ROM @ $A000
          rom_at_a000 <= fastio_wdata(4);
          reg_rom_a000 <= fastio_wdata(4);
          -- @IO:C65 $D030.3 VIC-III:ROM8 Map C65 ROM @ $8000
          rom_at_8000 <= fastio_wdata(3);
          reg_rom_8000 <= fastio_wdata(3);
          -- @IO:C65 $D030.2 VIC-III:PAL Use PALETTE ROM (0) or RAM (1) entries for colours 0 - 15
          reg_palrom <= fastio_wdata(2);
          -- @IO:C65 $D030.1 VIC-III:EXTSYNC Enable external video sync (genlock input)
          -- @IO:C65 $D030.0 VIC-III:CRAM2K Map 2nd KB of colour RAM @ $DC00-$DFFF
          colourram_at_dc00_internal<= fastio_wdata(0);
          colourram_at_dc00<= fastio_wdata(0);
        elsif register_number=49 then
          if d031_writes /= x"FF" then
            d031_writes <= d031_writes + 1;
            d031_written_internal <= not d031_written_internal;
          else
            d031_writes <= x"00";
          end if;
          -- @IO:C65 $D031 SUMMARY:VIC-III Control Register B
          -- @IO:C65 $D031.7 VIC-III:H640 Enable C64 640 horizontal pixels / 80 column mode
          reg_h640 <= fastio_wdata(7);
          -- @IO:C65 $D031.6 VIC-III:FAST Enable C65 FAST mode (~3.5MHz)
          viciii_fast_internal <= fastio_wdata(6);
          -- @IO:C65 $D031.5 VIC-III:ATTR Enable extended attributes and 8 bit colour entries
          viciii_extended_attributes <= fastio_wdata(5);
          -- @IO:C65 $D031.4 VIC-III:BPM Bit-Plane Mode
          bitplane_mode <= fastio_wdata(4);
          -- @IO:C65 $D031.3 VIC-III:V400 Enable 400 vertical pixels
          reg_v400 <= fastio_wdata(3);
          -- @IO:C65 $D031.2 VIC-III:H1280 Enable 1280 horizontal pixels (not implemented)
          reg_h1280 <= fastio_wdata(2);
          -- @IO:C65 $D031.1 VIC-III:MONO Enable VIC-III MONO composite video output (colour if disabled)
          reg_mono <= fastio_wdata(1);
          -- @IO:C65 $D031.0 VIC-III:INT Enable VIC-III interlaced mode
          -- Auto-enable interlace mode when selecting V400 (unless in
          -- hypervisor, in which case we want to be able to unfreeze this
          -- register without side-effects)
          -- Note: This has been disabled again as interlace mode was breaking display on some hdmi monitors
          --       We need to come up with a configurable solution for composite once it is ready
          -- if reg_v400='0' and fastio_wdata(3)='1' and hypervisor_mode='0' then
          --   reg_interlace <= '1';
          -- else
          reg_interlace <= fastio_wdata(0);
          -- end if;
          viciv_legacy_mode_registers_touched <= '1';
        elsif register_number=50 then
          bitplane_enables <= fastio_wdata;
        -- @IO:C65 $D033.5-7 VIC-III:B0ADODD@BXADODD Bitplane X address, odd lines
        -- @IO:C65 $D033.1-3 VIC-III:B0ADEVN@BXADEVN Bitplane X address, even lines
        -- @IO:C65 $D034.5-7 VIC-III:B1ADODD @BXADODD
        -- @IO:C65 $D034.1-3 VIC-III:B1ADEVN @BXADEVN
        -- @IO:C65 $D035.5-7 VIC-III:B2ADODD @BXADODD
        -- @IO:C65 $D035.1-3 VIC-III:B2ADEVN @BXADEVN
        -- @IO:C65 $D036.5-7 VIC-III:B3ADODD @BXADODD
        -- @IO:C65 $D036.1-3 VIC-III:B3ADEVN @BXADEVN
        -- @IO:C65 $D037.5-7 VIC-III:B4ADODD @BXADODD
        -- @IO:C65 $D037.1-3 VIC-III:B4ADEVN @BXADEVN
        -- @IO:C65 $D038.5-7 VIC-III:B5ADODD @BXADODD
        -- @IO:C65 $D038.1-3 VIC-III:B5ADEVN @BXADEVN
        -- @IO:C65 $D039.5-7 VIC-III:B6ADODD @BXADODD
        -- @IO:C65 $D039.1-3 VIC-III:B6ADEVN @BXADEVN
        -- @IO:C65 $D03A.5-7 VIC-III:B7ADODD @BXADODD
         -- @IO:C65 $D03A.1-3 VIC-III:B7ADEVN @BXADEVN
        elsif register_number >= 51 and register_number <= 58 then
          -- @IO:C65 $D033-$D03A - VIC-III Bitplane addresses
          --bitplane_number := safe_to_integer(register_number(3 downto 0)) - 3;
          bitplane_addresses(safe_to_integer(register_number)-51) <= unsigned(fastio_wdata);
        -- @IO:C65 $D03B VIC-III:BPCOMP Complement bitplane flags
        elsif register_number=59 then
          bitplane_complements <= fastio_wdata;
        -- @IO:C65 $D03C VIC-III:BPX Bitplane X
        elsif register_number=60 then
          dat_x <= unsigned(fastio_wdata(6 downto 0));
          dat_y(8) <= fastio_wdata(7);
        -- @IO:C65 $D03D VIC-III:BPY Bitplane Y
        elsif register_number=61 then
          dat_y(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=64 then
        -- @IO:C65 $D03E VIC-III:HPOS Bitplane X Offset
        elsif register_number=62 then
          bitplanes_x_start <= unsigned(fastio_wdata);
        -- @IO:C65 $D03F VIC-III:VPOS Bitplane Y Offset
        elsif register_number=63 then
          bitplanes_y_start <= unsigned(fastio_wdata);
        elsif register_number=64 then
        -- @IO:C65 $D040 VIC-III:B0PIX@BNPIX Display Address Translater (DAT) Bitplane N port
        elsif register_number=65 then
        -- @IO:C65 $D041 VIC-III:B1PIX @BNPIX
        elsif register_number=66 then
        -- @IO:C65 $D042 VIC-III:B2PIX @BNPIX
        elsif register_number=67 then
        -- @IO:C65 $D043 VIC-III:B3PIX @BNPIX
        elsif register_number=68 then
        -- @IO:C65 $D044 VIC-III:B4PIX @BNPIX
        elsif register_number=69 then
        -- @IO:C65 $D045 VIC-III:B5PIX @BNPIX
        elsif register_number=70 then
        -- @IO:C65 $D046 VIC-III:B6PIX @BNPIX
        elsif register_number=71 then
        -- @IO:C65 $D047 VIC-III:B7PIX @BNPIX
        elsif register_number=72 then
          -- @IO:GS $D048 VIC-IV:TBDRPOS top border position
          border_y_top(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=73 then
          -- @IO:GS $D049.3-0 VIC-IV:TBDRPOS top border position MSB
          border_y_top(11 downto 8) <= unsigned(fastio_wdata(3 downto 0));
          -- @IO:GS $D049.7-4 VIC-IV:SPRBPMEN Sprite bitplane-modify-mode enables
          sprite_bitplane_enables(3 downto 0) <= fastio_wdata(7 downto 4);
        elsif register_number=74 then
          -- @IO:GS $D04A VIC-IV:BBDRPOS bottom border position
          border_y_bottom(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=75 then
          -- @IO:GS $D04B.3-0 VIC-IV:BBDRPOS bottom border position
          border_y_bottom(11 downto 8) <= unsigned(fastio_wdata(3 downto 0));
          -- @IO:GS $D04B.7-4 VIC-IV:SPRBPMEN Sprite bitplane-modify-mode enables
          sprite_bitplane_enables(7 downto 4) <= fastio_wdata(7 downto 4);
        elsif register_number=76 then
          -- @IO:GS $D04C VIC-IV:TEXTXPOS character generator horizontal position
          x_chargen_start(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=77 then
          -- @IO:GS $D04D.3-0 VIC-IV:TEXTXPOS character generator horizontal position
          x_chargen_start(11 downto 8) <= unsigned(fastio_wdata(3 downto 0));
          -- @IO:GS $D04D.7-4 VIC-IV:SPRTILEN Sprite horizontal tile enables.
          sprite_horizontal_tile_enables(3 downto 0) <= fastio_wdata(7 downto 4);
        elsif register_number=78 then
          -- @IO:GS $D04E VIC-IV:TEXTYPOS Character generator vertical position
          y_chargen_start(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=79 then
          -- @IO:GS $D04F.3-0 VIC-IV:TEXTYPOS Character generator vertical position
          y_chargen_start(11 downto 8) <= unsigned(fastio_wdata(3 downto 0));
          -- @IO:GS $D04F.7-4 VIC-IV:SPRTILEN Sprite 7-4 horizontal tile enables
          sprite_horizontal_tile_enables(7 downto 4) <= fastio_wdata(7 downto 4);
        elsif register_number=80 then
          -- @IO:GS $D050 VIC-IV:XPOSLSB Read horizontal raster scan position LSB
          viciv_rasterx_compare(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=81 then
          -- @IO:GS $D051.0-5 VIC-IV:XPOSMSB Read horizontal raster scan position MSB
          viciv_rasterx_compare(13 downto 8) <= unsigned(fastio_wdata(5 downto 0));
          -- @IO:GS $D051.6 VIC-IV:DBLRR When set, the Raster Rewrite Buffer is only updated every 2nd raster line, limiting resolution to V200, but allowing more cycles for Raster-Rewrite actions.
          raster_buffer_double_line <= fastio_wdata(6);
          -- @IO:GS $D051.7 VIC-IV:NORRDEL When clear, raster rewrite double buffering is used
          no_raster_buffer_delay <= fastio_wdata(7);
        elsif register_number=82 then
        -- @IO:GS $D052 VIC-IV:FNRASTERLSB Read physical raster position
        -- Allow setting of fine raster for IRQ (low bits)
        -- vicii_raster_compare(7 downto 0) <= unsigned(fastio_wdata);
--        vicii_is_raster_source <= '0';
        elsif register_number=83 then
        -- @IO:GS $D053.0-2 VIC-IV:FN!RASTER!MSB Read physical raster position
        -- @IO:GS $D053.4 VIC-IV:RESERVED Reserved
        -- @IO:GS $D053.5 VIC-IV:UPSCALE Enable integrated low-latency (130usec) 720p upscaler
        -- @IO:GS $D053.6 VIC-IV:SHDEMU Enable simulated shadow-mask (PALEMU must also be enabled)
        -- Allow setting of fine raster for IRQ (high bits)
        -- vicii_raster_compare(10 downto 8) <= unsigned(fastio_wdata(2 downto 0));
          -- @IO:GS $D053.7 VIC-IV:FNRST Read raster compare source (0=VIC-IV fine raster, 1=VIC-II raster), provides same value as set in FNRSTCMP
          shadow_mask_enable <= fastio_wdata(6);
          upscale_enable_int <= fastio_wdata(5);
        elsif register_number=84 then
          -- @IO:GS $D054 SUMMARY:VIC-IV Control register C
          -- @IO:GS $D054.7 VIC-IV:ALPHEN Alpha compositor enable
          compositer_enable <= fastio_wdata(7);
          -- @IO:GS $D054.6 VIC-IV:VFAST C65GS FAST mode (48MHz)
          viciv_fast_internal <= fastio_wdata(6);
          -- @IO:GS $D054.5 VIC-IV:PALEMU Enable PAL CRT-like scan-line emulation
          pal_simulate <= fastio_wdata(5);
          -- @IO:GS $D054.4 VIC-IV:SPR!H640 Sprite H640 enable
          sprite_h640 <= fastio_wdata(4);
          -- @IO:GS $D054.3 VIC-IV:SMTH video output horizontal smoothing enable
          horizontal_filter <= fastio_wdata(3);
          -- @IO:GS $D054.2 VIC-IV:FCLRHI enable full-colour mode for character numbers >$FF
          fullcolour_extendedchars <= fastio_wdata(2);
          -- @IO:GS $D054.1 VIC-IV:FCLRLO enable full-colour mode for character numbers <=$FF
          fullcolour_8bitchars <= fastio_wdata(1);
          -- @IO:GS $D054.0 VIC-IV:CHR16 enable 16-bit character numbers (two screen bytes per character)
          sixteenbit_charset <= fastio_wdata(0);
        elsif register_number=85 then
          -- @IO:GS $D055 VIC-IV:SPRHGTEN sprite extended height enable (one bit per sprite)
          sprite_extended_height_enables <= fastio_wdata;
        elsif register_number=86 then
          -- @IO:GS $D056 VIC-IV:SPRHGHT Sprite extended height size (sprite pixels high)
          sprite_extended_height_size <= unsigned(fastio_wdata);
        elsif register_number=87 then
          -- @IO:GS $D057 VIC-IV:SPRX64EN Sprite extended width enables (8 bytes per sprite row = 64 pixels wide for normal sprites or 16 pixels wide for 16-colour sprite mode)
          sprite_extended_width_enables <= fastio_wdata;
        elsif register_number=88 then
          -- @IO:GS $D058 VIC-IV:LINESTEPLSB number of bytes to advance between each text row (LSB)
          virtual_row_width(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=89 then
          -- @IO:GS $D059 VIC-IV:LINESTEPMSB number of bytes to advance between each text row (MSB)
          virtual_row_width(15 downto 8) <= unsigned(fastio_wdata);
        elsif register_number=90 then
          -- @IO:GS $D05A VIC-IV:CHRXSCL Horizontal hardware scale of text mode (pixel 120ths per pixel)
          chargen_x_scale <= unsigned(fastio_wdata);
        elsif register_number=91 then
          -- @IO:GS $D05B VIC-IV:CHRYSCL Vertical scaling of text mode (number of physical rasters per char text row)
          chargen_y_scale <= unsigned(fastio_wdata);
        elsif register_number=92 then
          -- @IO:GS $D05C VIC-IV:SDBDRWD!LSB Width of single side border (LSB)
          single_side_border(7 downto 0) <= unsigned(fastio_wdata);
          viciv_single_side_border_width_touched <= '1';
        elsif register_number=93 then
          -- @IO:GS $D05D.0-5 VIC-IV:SDBDRWD!MSB side border width (MSB)
          single_side_border(13 downto 8) <= unsigned(fastio_wdata(5 downto 0));
          viciv_single_side_border_width_touched <= '1';
          -- @IO:GS $D05D.6 VIC-IV:RST!DELEN Enable raster delay (delays raster counter and interrupts by one line to match output pipeline latency)
          enable_raster_delay <= fastio_wdata(6);
          -- @IO:GS $D05D.7 VIC-IV:HOTREG Enable VIC-II hot registers. When enabled, touching many VIC-II registers causes the VIC-IV to recalculate display parameters, such as border positions and sizes. Touching registers while this is disabled will trigger a change when reenabling. Setting this to 0 will clear the recalc flag, canceling the recalculation.
          vicii_hot_regs_enable <= fastio_wdata(7);
          if fastio_wdata(7) = '0' then
            viciv_legacy_mode_registers_touched <= '0';
          end if;
        elsif register_number=94 then
          -- @IO:GS $D05E VIC-IV:CHRCOUNT Number of characters to display per row (LSB)
          display_row_width(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=95 then
          -- @IO:GS $D05F VIC-IV:SPRXSMSBS Sprite H640 X Super-MSBs
          sprite_h640_msbs <= fastio_wdata;
        elsif register_number=96 then
          -- @IO:GS $D060 VIC-IV:SCRNPTRLSB screen RAM precise base address (bits 0 - 7)
          screen_ram_base(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=97 then
          -- @IO:GS $D061 VIC-IV:SCRNPTRMSB screen RAM precise base address (bits 15 - 8)
          screen_ram_base(15 downto 8) <= unsigned(fastio_wdata);
        elsif register_number=98 then
          -- @IO:GS $D062 VIC-IV:SCRNPTRBNK screen RAM precise base address (bits 23 - 16)
          screen_ram_base(23 downto 16) <= unsigned(fastio_wdata);
        elsif register_number=99 then
          -- @IO:GS $D063.0-3 VIC-IV:SCRNPTRMB screen RAM precise base address (bits 31 - 24)
          screen_ram_base(27 downto 24) <= unsigned(fastio_wdata(3 downto 0));
          -- @IO:GS $D063.4-5 VIC-IV:CHRCOUNT Number of characters to display per
          -- row (MSBs)
          display_row_width(9 downto 8) <= unsigned(fastio_wdata(5 downto 4));
          -- @IO:GS $D063.6 VIC-IV:FCOLMCM enable 256 colours in multicolour text mode
          fullcolour_mcm <= fastio_wdata(6);
          -- @IO:GS $D063.7 VIC-IV:EXGLYPH source full-colour character data from expansion RAM
          glyphs_from_hyperram <= fastio_wdata(7);
        elsif register_number=100 then
          -- @IO:GS $D064 VIC-IV:COLPTRLSB colour RAM base address (bits 0 - 7)
          colour_ram_base(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=101 then
          -- @IO:GS $D065 VIC-IV:COLPTRMSB colour RAM base address (bits 15 - 8)
          colour_ram_base(15 downto 8) <= unsigned(fastio_wdata);
        elsif register_number=102 then -- $D3066
          -- @IO:GS $D066.0-4 VIC-IV xcounter pipeline delay DEBUG WILL BE REMOVED
          -- @IO:GS $D066.6 VIC-IV render activity display enable DEBUG WILL BE REMOVED
          -- @IO:GS $D066.7 VIC-IV test pattern display enable DEBUG WILL BE REMOVED
          reg_xcounter_delay <= safe_to_integer(unsigned(fastio_wdata(4 downto 0)));
          show_render_activity <= fastio_wdata(6);
          test_pattern_enable <= fastio_wdata(7);
        elsif register_number=103 then  -- $D3067
          -- @IO:GS $D067 DEBUG:SBPDEBUG Sprite/bitplane first X DEBUG WILL BE REMOVED
          sprite_first_x(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=104 then
          -- @IO:GS $D068 VIC-IV:CHARPTRLSB Character set precise base address (bits 0 - 7)
          character_set_address(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=105 then
          -- @IO:GS $D069 VIC-IV:CHARPTRMSB Character set precise base address (bits 15 - 8)
          character_set_address(15 downto 8) <= unsigned(fastio_wdata);
        elsif register_number=106 then
          -- @IO:GS $D06A VIC-IV:CHARPTRBNK Character set precise base address (bits 23 - 16)
          character_set_address(23 downto 16) <= unsigned(fastio_wdata);
        elsif register_number=107 then
          -- @IO:GS $D06B VIC-IV:SPR16EN sprite 16-colour mode enables
          sprite_sixteen_colour_enables <= fastio_wdata;
        elsif register_number=108 then
          -- @IO:GS $D06C VIC-IV:SPRPTRADRLSB sprite pointer address (bits 7 - 0)
          vicii_sprite_pointer_address(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=109 then
          -- @IO:GS $D06D VIC-IV:SPRPTRADRMSB sprite pointer address (bits 15 - 8)
          vicii_sprite_pointer_address(15 downto 8) <= unsigned(fastio_wdata);
        elsif register_number=110 then
          -- @IO:GS $D06E.0-6 VIC-IV:SPRPTRBNK sprite pointer address (bits 23 - 16)
          -- @IO:GS $D06E.7 VIC-IV:SPR!PTR16 16-bit sprite pointer mode (allows sprites to be located on any 64 byte boundary in chip RAM)
          vicii_sprite_pointer_address(23 downto 16) <= unsigned(fastio_wdata);
        elsif register_number=111 then
          -- @IO:GS $D06F.5-0 VIC-IV:RASLINE0 first VIC-II raster line
          vicii_first_raster(5 downto 0) <= unsigned(fastio_wdata(5 downto 0));
          -- @IO:GS $D06F.6 VIC-IV:VGAHDTV Select more VGA-compatible mode if set, instead of HDMI/HDTV VIC-II cycle-exact frame timing. May help to produce a functional display on older VGA monitors.
          -- @IO:GS $D06F.7 VIC-IV:PALNTSC NTSC emulation mode (max raster = 262)
          vicii_ntsc <= fastio_wdata(7);
          pal50_select <= not fastio_wdata(7);
          vga60_select <= fastio_wdata(6);
          vga60_select_internal <= fastio_wdata(6);
          -- Make sure that matrix
          -- mode display isn't jiggly
          if fastio_wdata(7)='1' then
            reg_xcounter_delay <= 1;
            reg_alpha_delay <= x"1";
          else
            reg_xcounter_delay <= 0;
            reg_alpha_delay <= x"1";
          end if;
          report "LEGACY register update & PAL/NTSC mode select";

          -- Recompute screen and border positions
          -- But only if not in hypervisor mode, so that we don't mess up freezing
          if hypervisor_mode='0' then
            viciv_single_side_border_width_touched <= '1';
          end if;

          if vicii_ntsc /= fastio_wdata(7) or vga60_select_internal /= fastio_wdata(6) then
            case fastio_wdata(7 downto 6) is
              when "00" => -- PAL, 720x576 @ 50Hz
                sprite_y_adjust <= to_unsigned(0,8);
                vicii_ycounter_scale_minus_zero <= to_unsigned(2-1,4);
                vicii_max_raster <= pal_max_raster;
                -- VSYNC is negative for 50Hz (required for some monitors)
                hsync_polarity_internal <= '1';
                vsync_polarity_internal <= '0';
                if vicii_ntsc /= fastio_wdata(7) then
                  vicii_first_raster <= to_unsigned(0,9);
                end if;
              when "01" => -- PAL, 720x576 50Hz, NTSC max raster
                sprite_y_adjust <= to_unsigned(0,8);
                vicii_ycounter_scale_minus_zero <= to_unsigned(2-1,4);
                vicii_max_raster <= ntsc_max_raster;
                hsync_polarity_internal <= '1';
                vsync_polarity_internal <= '0';
                if vicii_ntsc /= fastio_wdata(7) then
                  vicii_first_raster <= to_unsigned(0,9);
                end if;
              when "10" => -- NTSC, 720x480 @ 60Hz
                sprite_y_adjust <= to_unsigned(24,8);
                vicii_ycounter_scale_minus_zero <= to_unsigned(2-1,4);
                vicii_max_raster <= ntsc_max_raster;
                hsync_polarity_internal <= '1';
                vsync_polarity_internal <= '0';
                if vicii_ntsc /= fastio_wdata(7) then
                  vicii_first_raster <= to_unsigned(7,9);
                end if;

              when "11" => -- NTSC 720x480 60Hz
                sprite_y_adjust <= to_unsigned(24,8);
                vicii_ycounter_scale_minus_zero <= to_unsigned(2-1,4);
                -- NTSC but with PAL max raster
                vicii_max_raster <= pal_max_raster;
                hsync_polarity_internal <= '1';
                vsync_polarity_internal <= '0';
                if vicii_ntsc /= fastio_wdata(7) then
                  vicii_first_raster <= to_unsigned(7,9);
                end if;
              when others => -- Default to NTSC 800x600 60Hz
                sprite_y_adjust <= to_unsigned(24,8);
                vicii_ycounter_scale_minus_zero <= to_unsigned(2-1,4);
                hsync_polarity_internal <= '1';
                vsync_polarity_internal <= '0';
                if vicii_ntsc /= fastio_wdata(7) then
                  vicii_first_raster <= to_unsigned(7,9);
                end if;
            end case;
          end if;
        elsif register_number=112 then
          -- @IO:GS $D070 NONE:VIC-IV palette bank selection
          -- @IO:GS $D070.7-6 VIC-IV:MAPEDPAL palette bank mapped at $D100-$D3FF
          palette_bank_fastio <= fastio_wdata(7 downto 6);
          -- @IO:GS $D070.5-4 VIC-IV:BTPALSEL bitmap/text palette bank
          palette_bank_chargen <= fastio_wdata(5 downto 4);
          -- @IO:GS $D070.3-2 VIC-IV:SPRPALSEL sprite palette bank
          palette_bank_sprites <= fastio_wdata(3 downto 2);
          -- @IO:GS $D070.1-0 VIC-IV:ABTPALSEL VIC-IV bitmap/text palette bank (alternate palette)
          palette_bank_chargen_alt <= fastio_wdata(1 downto 0);
        elsif register_number=113 then -- $D3071
          -- @IO:GS $D071 VIC-IV:BP16ENS VIC-IV 16-colour bitplane enable flags
          bitplane_sixteen_colour_mode_flags <= fastio_wdata;
        elsif register_number=114 then -- $D3072
          -- @IO:GS $D072 VIC-IV:SPRYADJ Sprite Y position adjustment
          sprite_y_adjust <= unsigned(fastio_wdata);
        elsif register_number=115 then -- $D3073
          -- @IO:GS $D073.0-3 VIC-IV:ALPHADELAY Alpha delay for compositor
          reg_alpha_Delay <= unsigned(fastio_wdata(3 downto 0));
          -- @IO:GS $D073.4-7 VIC-IV:RASTERHEIGHT physical rasters per VIC-II raster (1 to 16)
          vicii_ycounter_scale_minus_zero(3 downto 0) <= unsigned(fastio_wdata(7 downto 4));
        elsif register_number=116 then -- $D3074
          -- @IO:GS $D074 VIC-IV:SPRENALPHA Sprite alpha-blend enable
          sprite_alpha_blend_enables <= fastio_wdata;
        elsif register_number=117 then
          -- @IO:GS $D075 VIC-IV:SPRALPHAVAL Sprite alpha-blend value
          sprite_alpha_blend_value <= unsigned(fastio_wdata);
        elsif register_number=118 then
          -- @IO:GS $D076 VIC-IV:SPRENV400 Sprite V400 enables
          sprite_v400s <= fastio_wdata;
        elsif register_number=119 then  -- $D3077
          -- @IO:GS $D077 VIC-IV:SPRYMSBS Sprite V400 Y position MSBs
          sprite_v400_msbs <= fastio_wdata;
        elsif register_number=120 then  -- $D3078
          -- @IO:GS $D078 VIC-IV:SPRYSMSBS Sprite V400 Y position super MSBs
          sprite_v400_super_msbs <= fastio_wdata;
        elsif register_number=121 then  -- $D3079
          -- @IO:GS $D079 VIC-IV:RASCMP Physical raster compare value to be used if FNRSTCMP is clear
          vicii_raster_compare(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=122 then  -- $D307A
          -- @IO:GS $D07A.0-2 VIC-IV:RASCMP!MSB Raster compare value MSB
          -- @IO:GS $D07A.3 VIC-IV:SPTR!CONT Continuously monitor sprite pointer, to allow changing sprite data source while a sprite is being drawn
          -- @IO:GS $D07A.4 VIC-IV:CHARY16 Alternate char ROM bank on alternate raster lines in V200
          -- @IO:GS $D07A.5 VIC-IV:NOBUGCOMPAT Disables VIC-III / C65 Bug Compatibility Mode if set
          -- @IO:GS $D07A.6 VIC-IV:EXTIRQS Enable additional IRQ sources, e.g., raster X position.
          -- @IO:GS $D07A.7 VIC-IV:FNRST!CMP Raster compare is in physical rasters if clear, or VIC-II rasters if set
          irq_extras_enable <= fastio_wdata(6);
          reg_char_y16 <= fastio_wdata(4);
          sprite_continuous_pointer_monitoring <= fastio_wdata(3);
          vicii_raster_compare(10 downto 8) <= unsigned(fastio_wdata(2 downto 0));
          vicii_is_raster_source <= fastio_wdata(7);

          prev_bug_compat_mode <= not fastio_wdata(5);
          if fastio_wdata(5)=prev_bug_compat_mode then
            if fastio_wdata(5)='1' then
              -- Disable compatibility = enable errata
              hw_errata_enable_toggle <= not hw_errata_enable_toggle;
            else
              hw_errata_disable_toggle <= not hw_errata_disable_toggle;
            end if;
          end if;

        elsif register_number=123 then
          -- @IO:GS $D07B VIC-IV:DISP!ROWS Number of text rows to display
          display_row_count <= unsigned(fastio_wdata);
        elsif register_number=124 then
          -- @IO:GS $D07C.0-2 VIC-IV:BIT!PBANK Set which 128KB bank bitplanes
          -- are fetched from.
          bitplane_bank_select <= unsigned(fastio_wdata(2 downto 0));
          dat_bitplane_bank <= unsigned(fastio_wdata(2 downto 0));
          -- @IO:GS $D07C.3 VIC-IV:RESV @RESV
          -- @IO:GS $D07C.4 VIC-IV:HSYNCP hsync polarity
          hsync_polarity_internal <= fastio_wdata(4);
          -- @IO:GS $D07C.5 VIC-IV:VSYNCP vsync polarity
          vsync_polarity_internal <= fastio_wdata(5);
          -- @IO:GS $D07C.6-7 VIC-IV:DEBUGC VIC-IV debug pixel select red(01), green(10) or blue(11) channel visible in $D07D
          debug_channel_select <= fastio_wdata(7 downto 6);
        elsif register_number=125 then
          -- @IO:GS $D07D DEBUG:DEBUGX VIC-IV debug X position (LSB) (write only)
          -- @IO:GS $D07D DEBUG:DEBUGOUT VIC-IV debug value read-back (read only)
          debug_x(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=126 then
          -- @IO:GS $D07E DEBUG:DEBUGY VIC-IV debug Y position (LSB)
          debug_y(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=127 then
          -- @IO:GS $D07F.0-3 DEBUG:DEBUGX VIC-IV debug X position (MSB)
          -- @IO:GS $D07F.7 DEBUG:DEBUGOOF VIC-IV debug out-of-frame signal enable
          debug_x(11 downto 8) <= unsigned(fastio_wdata(3 downto 0));
          debug_x(13 downto 12) <= "00";
          -- @IO:GS $D07F.4-7 DEBUG:DEBUGY VIC-IV debug Y position (MSB)
          debug_y(11 downto 8) <= unsigned(fastio_wdata(7 downto 4));
        elsif register_number<255 then
          -- reserved register, FDC and RAM expansion controller
          null;
        elsif register_number>=256 and register_number<512 then
          -- @IO:C65 $D100-$D1FF VIC-III:PALRED red palette values (reversed nybl order)
          palette_fastio_address <= palette_bank_fastio & std_logic_vector(register_number(7 downto 0));
          palette_we(3) <= '1';
        elsif register_number>=512 and register_number<768 then
          -- @IO:C65 $D200-$D2FF VIC-III:PALGREEN green palette values (reversed nybl order)
          palette_fastio_address <= palette_bank_fastio & std_logic_vector(register_number(7 downto 0));
          palette_we(2) <= '1';
        elsif register_number>=768 and register_number<1024 then
          -- @IO:C65 $D300-$D3FF VIC-III:PALBLUE blue palette values (reversed nybl order)
          palette_fastio_address <= palette_bank_fastio & std_logic_vector(register_number(7 downto 0));
          palette_we(1) <= '1';
        else
          null;
        end if;
      end if;
    end if;

  end process;

  process(pixelclock,all_pause,reg_h640,ramaddress,this_screen_row_fetch_address,glyph_full_colour) is
    variable indisplay : std_logic := '0';
    variable card_bg_colour : unsigned(7 downto 0) := (others => '0');
    variable card_fg_colour : unsigned(7 downto 0) := (others => '0');
    variable long_address : unsigned(31 downto 0) := (others => '0');
    variable next_glyph_number_temp : std_logic_vector(12 downto 0) := (others => '0');
    variable next_glyph_colour_temp : std_logic_vector(7 downto 0) := (others => '0');
  begin
    if rising_edge(pixelclock) and all_pause='0' then

      report "ycounter = $" & to_hstring(ycounter) & ", ycounter_driver = $" & to_hstring(ycounter_driver);
      ycounter <= ycounter_driver;
      vgared <= vgared_driver;
      vgagreen <= vgagreen_driver;
      vgablue <= vgablue_driver;

      -- Capture pixel at prescribed position to support automated testing
      -- and display red cross-hairs
      if xcounter=debug_x xor ycounter=debug_y then
        -- Draw cross-hairs at debug coordinates
        vgared <= x"FF";
        vgagreen <= x"00";
        vgablue <= x"00";
      end if;
      if (xcounter=debug_x) and (ycounter=debug_y) then
        debug_pixel_red <= vgared_driver;
        debug_pixel_green <= vgagreen_driver;
        debug_pixel_blue <= vgablue_driver;
      end if;

      sprite_data_offsets(sprite_number_for_data_rx) <= sprite_data_offset_rx;
      -- Ask for the next one (8 sprites + 8 C65 bitplanes)
      if sprite_number_counter = 15 then
        sprite_number_counter <= 0;
        sprite_number_for_data_tx <= 0;
      else
        sprite_number_counter <= sprite_number_counter + 1;
        sprite_number_for_data_tx <= sprite_number_for_data_tx + 1;
      end if;

      pixel_x_640 <= safe_to_integer(xcounter);
      pixel_x_800 <= safe_to_integer(xcounter);
      pixel_y_scale_400 <= chargen_y_scale_400(3 downto 0);
      pixel_y_scale_200 <= chargen_y_scale_200(3 downto 0);

      -- But also export native X position, e.g., for touch panel interface to
      -- match up with visual keyboard

      -- XXX Why do we need these fudge factors to make everything line up?
      -- Subtract 10 for video pipeline depth?
      native_x_640 <= safe_to_integer(vicii_xcounter_640 - 10);
      -- Subtract 34 for some reason?
      native_y_200 <= safe_to_integer(vicii_ycounter - 34);
      native_y_400 <= safe_to_integer(displayy);

      --chardata_drive <= unsigned(chardata);
      --paint_chardata <= chardata_drive;
      paint_chardata <= unsigned(chardata);
      ramdata_drive <= ramdata;
      paint_ramdata <= ramdata_drive;

      sprite_fetch_drive <= '0';

      -- Acknowledge IRQs after reading $D019
      irq_raster <= irq_raster and (not ack_raster);
      irq_rasterx <= irq_rasterx and (not ack_rasterx);
      irq_lightpen <= irq_lightpen and (not ack_lightpen);
      irq_collisionspritebitmap <= irq_collisionspritebitmap and (not ack_collisionspritebitmap);
      irq_collisionspritesprite <= irq_collisionspritesprite and (not ack_collisionspritesprite);
      -- Set IRQ line status to CPU
      irq_drive <= not ((irq_raster and mask_raster)
                        or (irq_rasterx and mask_rasterx and irq_extras_enable)
                        or (irq_lightpen and mask_lightpen)
                        or (irq_collisionspritebitmap and mask_collisionspritebitmap)
                        or (irq_collisionspritesprite and mask_collisionspritesprite));

      -- Add new sprite collision bits to the bitmap
      case vicii_sprite_sprite_collision_map is
        when "00000000" | "10000000" | "01000000" | "00100000" | "00010000" |
             "00001000" | "00000100" | "00000010" | "00000001" =>
          vicii_sprite_sprite_collisions <= vicii_sprite_sprite_collisions and (vicii_sprite_sprite_collisions'range => not(clear_collisionspritesprite));
        when others =>
          -- Sprite collision, so add it to the existing map
          vicii_sprite_sprite_collisions
            <= (vicii_sprite_sprite_collisions and (vicii_sprite_sprite_collisions'range => not(clear_collisionspritesprite))) or
               (vicii_sprite_sprite_collision_map and (vicii_sprite_sprite_collision_map'range => not(postsprite_inborder)));
      end case;
      -- Sprite foreground collision is easier: always add it on.
      vicii_sprite_bitmap_collisions
        <= (vicii_sprite_bitmap_collisions and (vicii_sprite_bitmap_collisions'range => not(clear_collisionspritebitmap))) or
           (vicii_sprite_bitmap_collision_map and (vicii_sprite_bitmap_collision_map'range => not(postsprite_inborder)));

      -- Now check if we need to trigger an IRQ due to sprite collisions:
      if vicii_sprite_sprite_collisions /= "00000000" then
        irq_collisionspritesprite <= '1';
      end if;
      if vicii_sprite_bitmap_collisions /= "00000000" then
        irq_collisionspritebitmap <= '1';
      end if;

      -- Detect lightpen event (must appear above irq_lightpen assignment above)
      if touch_active='1' and xcounter_drive(11 downto 0) = touch_x and displayy = touch_y then
        irq_lightpen <= '1';
        lightpen_x_latch <= touch_x(11 downto 4);
        lightpen_y_latch <= touch_y(9 downto 2);
      end if;

      -- reset masks IRQs immediately
      if irq_drive = '0' then
        irq <= '0';
      else
        irq <= 'H';
      end if;

      -- Hsync has trouble meeting timing, so I have spread out the control
      -- over 3 cycles, including one pure drive cycle, which should hopefully
      -- fix it once and for all.
      xcounter_delayed <= xcounter;

      if pixel_newframe_internal='1' then
        -- C65/VIC-III style 1Hz blink attribute clock
        viciii_blink_phase_counter <= viciii_blink_phase_counter + 1;
        if viciii_blink_phase_counter = 30 then
          viciii_blink_phase_counter <= 0;
          viciii_blink_phase <= not viciii_blink_phase;
        end if;

        -- 4Hz 1581 drive LED blink clock
        drive_blink_phase_counter <= drive_blink_phase_counter + 1;
        if drive_blink_phase_counter = 15 then
          drive_blink_phase_counter <= 0;
          drive_blink_phase <= not drive_blink_phase;
        end if;
      end if;

      indisplay :='1';

      -- Make variably delayed xcounter signal, so that we can correct delay
      -- for pipeline depth
      external_pixel_strobe_log(0) <= external_pixel_strobe_in;
      external_pixel_strobe_log(31 downto 1) <= external_pixel_strobe_log(30 downto 0);
      if external_frame_x_zero_latched='0' and external_pixel_strobe_log(reg_xcounter_delay)='1' then
        report "PIXEL xcounter_pipeline_delayed increased";
        xcounter_pipeline_delayed <= xcounter_pipeline_delayed + 1;
      elsif external_frame_x_zero_latched='1' then
        xcounter_pipeline_delayed <= 0;
      end if;

      if external_frame_x_zero_latched='0' and external_pixel_strobe_log(0)='1' and vga_in_frame='1' then
        raster_buffer_read_address(9 downto 0) <= raster_buffer_read_address_next(9 downto 0);
        raster_buffer_read_address_sub <= raster_buffer_read_address_sub_next;
        report "PIXEL pixel strobe edge";
        xcounter <= xcounter + 1;
        -- Allow H640 sprites to begin from far-left
        if (xcounter = sprite_first_x) or (sprite_h640='1') then
          sprite_x_counting <= '1';
        end if;
        if sprite_x_counting = '1' then
          report "sprite_x_counting=1, vicii_xcounter_640 = " & to_hstring(vicii_xcounter_640);
          vicii_xcounter_640 <= vicii_xcounter_640 + 1;
          sprite_x_scale_toggle <= not sprite_x_scale_toggle;
          if sprite_x_scale_toggle = '1' then
            vicii_xcounter_320 <= vicii_xcounter_320 + 1;
          end if;
        end if;
      end if;

      if external_frame_x_zero_latched = '1' then
        -- End of raster reached.
        -- Bump raster number and start next raster.
        report "XZERO: ycounter=" & integer'image(safe_to_integer(ycounter));
        xcounter <= (others => '0');
        sprite_x_counting <= '0';
        sprite_x_scale_toggle <= '0';

        -- Make delayed stopping of chargen rendering take effect
        -- (this has to happen on the following raster, because we determine
        -- end of screen when we pre-compute the next row address)
        if last_external_frame_x_zero_latched = '0' then
          if stop_chargen_raster_counter /= 0 then
            stop_chargen_raster_counter <= stop_chargen_raster_counter - 1;
          end if;
        end if;
        if stop_chargen_raster_counter = 1 then
          before_y_chargen_start <= '1';
        end if;

        vicii_ycounter_scale <= vicii_ycounter_scale_minus_zero;
        report "LEGACY vicii_ycounter_scale = " & integer'image(safe_to_integer(vicii_ycounter_scale))
          & ", vicii_ycounter_max_phase = " & integer'image(safe_to_integer(vicii_ycounter_max_phase))
          & ", text_mode=" & std_logic'image(text_mode)
          & ", screen_ram_base=$" & to_hstring(screen_ram_base)
          & ", character_set_base=$" & to_hstring(character_set_address)
          & ", screen_ram_buffer_read_address=" & integer'image(safe_to_integer(screen_ram_buffer_read_address))
          & ", first_card_of_row=" & integer'image(safe_to_integer(first_card_of_row))
          & ", chargen_y=" & integer'image(safe_to_integer(chargen_y))
          & ", chargen_y_sub = " & integer'image(safe_to_integer(chargen_y_sub))
          ;
        vicii_xcounter_320 <= to_unsigned(0,9);
        vicii_xcounter_640 <= to_unsigned(0,10);

        chargen_active <= '0';
        chargen_active_soon <= '0';

        -- Make VIC-II triggered raster interrupts edge triggered, since one
        -- emulated VIC-II raster is ~63*48 = ~3,000 cycles, and many C64
        -- raster routines may finish in that time, and might get confused if
        -- a raster interrupt gets retriggered too soon.  This will also cause
        -- some problems for software that really expects multiple interrupts
        -- on the same raster line, but that should be really quite rare.
        -- We could allow multiple triggerings per raster when CPU is at <= 3.5MHz,
        -- and only edge trigger it when at full speed?
        -- As we have a one raster line delay in display, we delay the raster
        -- interrupt by one line also, so that it better matches what we see on
        -- a VIC-II.
        if enable_raster_delay='1' then
          vicii_raster_compare_plus_one <= vicii_raster_compare + 1;
        else
          vicii_raster_compare_plus_one <= vicii_raster_compare;
        end if;
        if (xcounter_drive = viciv_rasterx_compare) then
          irq_rasterx <= '1';
        end if;
        if (vicii_is_raster_source='1') and (vicii_ycounter = vicii_raster_compare_plus_one(8 downto 0)) and last_vicii_ycounter /= vicii_ycounter then
          irq_raster <= '1';
        end if;
        last_vicii_ycounter <= vicii_ycounter;
        -- Make VIC-IV raster interrupts edge triggered, as well, to avoid re-triggering
        -- of the raster interrupt at the end of the raster line (eg. if the raster
        -- interrupt has already been acknowledged before the raster line reaches the end).
        -- Retriggering would happen once external_frame_x_zero_latched = '1' but ycounter
        -- not yet updated (it will get updated two clock cycles later).
        if (vicii_is_raster_source='0') and (ycounter = vicii_raster_compare_plus_one) and last_ycounter /= ycounter then
          irq_raster <= '1';
        end if;
        last_ycounter <= ycounter;

        if last_external_frame_x_zero_latched='0' then
          -- ... update Y position, even during VSYNC, since frame timing is
          -- now exact.
          report "XZERO: incrementing ycounter from " & integer'image(safe_to_integer(ycounter));
          ycounter_driver <= ycounter_driver + 1;

          displaycolumn0 <= '1';
          displayy <= displayy + 1;
          if displayy(4)='1' then
            displayline0 <= '0';
          end if;

          if vicii_ycounter_phase = vicii_ycounter_max_phase then
            if safe_to_integer(vicii_ycounter) /= vicii_max_raster then
              vicii_ycounter <= vicii_ycounter + 1;
              -- Indicate fixed point on the frame
              -- (used by CPU to time entry into freeze routine for proper synchronisation.
              --  Also helps thumbnails to not have tears in them).
              if vicii_ycounter = to_unsigned(255,9) then
                viciv_frame_indicate <= '1';
              else
                viciv_frame_indicate <= '0';
              end if;
              -- We update V400 position in this case, bug also in the
              -- alternate case below
              vicii_ycounter_v400 <= vicii_ycounter_v400 + 1;
            end if;
            vicii_ycounter_continuous <= vicii_ycounter_continuous + 1;

            if vicii_ycounter_max_phase = 0 then
              -- Calculate raster number for sprites.
              if vicii_ycounter = (safe_to_integer(vicii_max_raster) + 2 - safe_to_integer(sprite_y_adjust)) then
                vicii_sprite_ycounter <= to_unsigned(0,9);
              else
                vicii_sprite_ycounter <= vicii_ycounter_continuous - 2  + safe_to_integer(sprite_y_adjust);
              end if;
            end if;

            vicii_ycounter_phase <= (others => '0');
            -- All visible rasters are now equal height
            -- (we take up the slack using vertical_flyback fast raster stepping,
            -- and allow arbitrary setting of first raster of the VGA frame).
            vicii_ycounter_max_phase <= vicii_ycounter_scale;
          else
            -- In the middle of a VIC-II logical raster, so just increase phase.
            vicii_ycounter_phase <= vicii_ycounter_phase + 1;
            -- But also bump V400 raster if required
            if safe_to_integer(vicii_ycounter_phase) =  safe_to_integer(vicii_ycounter_max_phase(3 downto 1)) then
              vicii_ycounter_v400 <= vicii_ycounter_v400 + 1;
            end if;

            -- Calculate raster number for sprites.
            -- The -2 is an adjustment factor to make the sprites line up correctly
            -- on the screen.
            -- This is done on an "off" line, so that the sprites line up properly
            if vicii_ycounter = (safe_to_integer(vicii_max_raster) + 2 - safe_to_integer(sprite_y_adjust)) then
              vicii_sprite_ycounter <= to_unsigned(0,9);
            else
              vicii_sprite_ycounter <= vicii_ycounter_continuous - 2 + safe_to_integer(sprite_y_adjust);
            end if;

          end if;
        end if;
      end if;

      -- If we got far along the last line to make it look real, and ...
      last_external_frame_y_zero <= external_frame_y_zero;
      if external_frame_y_zero = '0' and last_external_frame_y_zero='1' then
        -- Start of next frame
        report "Starting new frame. ycounter_driver <= 0";

        ycounter_driver <= (others =>'0');
        report "LEGACY: chargen_y_sub = 0, first_card_of_row = 0 due to start of frame";
        chargen_y_sub <= (others => '0');
        first_card_of_row <= (others => '0');

        displayy <= (others => '0');
        displayline0 <= '1';
        indisplay := '0';
        report "clearing indisplay because xcounter=0" severity note;
        screen_row_address <= screen_ram_base(19 downto 0);
        display_row_number <= to_unsigned(0,8);

        -- Reset VIC-II raster counter to first raster for top of frame
        -- (the preceeding rasters occur during vertical flyback, in case they
        -- have interrupts triggered on them).
        vicii_ycounter_phase <= to_unsigned(1,4);
        vicii_ycounter <= vicii_first_raster;
        vicii_ycounter_continuous <= vicii_first_raster;
        vicii_ycounter_v400 <= (others =>'0');
        vicii_ycounter_phase_v400 <= to_unsigned(1,4);

      end if;

      if xcounter<frame_h_front then
        xfrontporch <= '1';
      else
        xfrontporch <= '0';
      end if;
      if external_frame_x_zero_latched='1' then
        -- tell frame grabber about each new raster
        pixel_newraster <= '1';
      else
        pixel_newraster <= '0';
      end if;

      -- Work out when the horizonal back porch starts.
      -- The edge is used to trigger drawing of the next raster into the raster
      -- buffer.
      -- We actually want to trigger this as early as possible, so that sprite
      -- fetching doesn't run over into the next raster line.
      -- 30MHz pixel clock @ 50Hz display means we will catch up 3.3 pixels
      -- per pixel, so we can't start before (display_width - (display_width/3.3)).

      if xcounter=0 then
        report "stopping drawing at start of next raster";
        chargen_active <= '0';
        chargen_active_soon <= '0';
        raster_buffer_read_address(10) <= raster_buffer_half_toggle;
        raster_buffer_max_write_address_prev <= raster_buffer_max_write_address_hold;
        report "setting raster_buffer_max_write_address_prev to $" & to_hstring(raster_buffer_max_write_address_hold);
      end if;
      if raster_buffer_read_address_next(9 downto 0) > raster_buffer_max_write_address_prev then
        report "stopping character generator due to buffer exhaustion"
          severity note;
        chargen_active <= '0';
        chargen_active_soon <= '0';
      end if;

      -- Work out where in the current character we seem to be
      -- (and allowing for smooth scrolling etc during drawing of the frame)
      if reg_v400='1' then
        if y_chargen_start > displayy then
          pixels_since_last_char <= "000";
        else
          pixels_since_last_char <= to_unsigned(safe_to_integer(displayy) - safe_to_integer(y_chargen_start),3) + 1;
        end if;
      else
        if y_chargen_start > displayy(11 downto 1) then
          pixels_since_last_char <= "000";
        else
          pixels_since_last_char <= to_unsigned(safe_to_integer(displayy(11 downto 1)) - safe_to_integer(y_chargen_start),3)
                                    -- Magic fudge factor to get everything
                                    -- lining up correctly
                                    + to_unsigned(safe_to_integer(y_chargen_start(3 downto 1)) + 1,3);
        end if;
      end if;

      last_was_fetch_start <= is_fetch_start;
      is_fetch_start <= '0';
      if raster_buffer_double_line='0' or ycounter(0)='0' then
        if no_raster_buffer_delay='0' then
          if xcounter=(safe_to_integer(frame_h_front)+display_fetch_start) then
            is_fetch_start <= '1';
          end if;
        else
          if xcounter=(safe_to_integer(frame_h_front)+display_fetch_start) then
            is_fetch_start <= '1';
          end if;
        end if;
      end if;
      if is_fetch_start='1' and last_was_fetch_start='0' then
        -- Start of filling raster buffer.
        -- We don't need to double-buffer, as we start filling from the back
        -- porch of the previous line, hundreds of cycles before the start of
        -- the next line of display.
        report "RASTER FETCH: start of fetch in preparation for the next raster";

        report "ZEROing screen_ram_buffer_read_address" severity note;
        screen_ram_buffer_read_address <= to_unsigned(0,9);

        -- Some house keeping first:
        -- Reset write address in raster buffer
        -- Set write address to all 1's, so that it wraps to zero at the start
        raster_buffer_write_address(9 downto 0) <= (others => '1');
        -- Make sure we read and write to opposite halves of the raster buffer
        raster_buffer_write_address(10) <= raster_buffer_half_toggle xor no_raster_buffer_delay;
        raster_buffer_half_toggle <= not raster_buffer_half_toggle;
        raster_buffer_max_write_address_hold <= raster_buffer_max_write_address;
        report "setting raster_buffer_max_write_address_hold to $" & to_hstring(raster_buffer_max_write_address);

        -- Reset glyph Y offset each raster line
        glyph_y_offset <= 0;

        -- Hold chargen_y for entire fetch, so that we don't get glitching when
        -- chargen_y increases part way through resulting in characters on
        -- right of display shifting up one physical pixel.
        chargen_y_hold <= chargen_y;

        if chargen_y_hold = chargen_y then
          charrow_repeated <= '1';
        else
          charrow_repeated <= '0';
        end if;

        -- Work out colour ram address
        report "COLOURRAM: Setting colourramaddress via first_card_of_row."
          & " text_mode=" & std_logic'image(text_mode)
          & ", sixteenbit_charset=" & std_logic'image(sixteenbit_charset);
        colourramaddress <= colour_ram_base + first_card_of_row;
        -- Work out the screen ram address.  We only need to re-fetch screen
        -- RAM if first_card_of_row is different to last time.
        prev_first_card_of_row <= first_card_of_row;

        -- Set all signals for both eventuality, since none are shared between
        -- the two paths.  This helps keep the logic shallow.

        -- Delay application of screen_ram_base address changes by one raster line
        -- so match behaviour of VIC-II
        if (text_mode='0') and (sixteenbit_charset='1') then
          -- bitmap mode in sixteen bit char mode uses 2 screen RAM bytes per
          -- card, but not two bitmap bytes, so we have to increment double
          screen_row_current_address
            <= to_unsigned(safe_to_integer(screen_ram_base(19 downto 0))
                           + safe_to_integer(first_card_of_row) + safe_to_integer(first_card_of_row),20);
        else
          screen_row_current_address
            <= to_unsigned(safe_to_integer(screen_ram_base(19 downto 0))
                           + safe_to_integer(first_card_of_row),20);
        end if;
        card_of_row <= (others =>'0');
        screen_ram_buffer_write_address <= to_unsigned(0,9);
        short_line <= '0';
        report "ZEROing screen_ram_buffer_write_address" severity note;
        -- Finally decide which way we should go
        if safe_to_integer(first_card_of_row) /= safe_to_integer(prev_first_card_of_row) then
          raster_fetch_state <= FetchScreenRamLine;
          -- From Section 3.5 of http://www.zimmers.net/cbmpics/cbm/c64/vic-ii.txt
          -- (but has problems for some reason)
          if (blank = '0') and ((vertical_border='0') or justbefore_y_chargen_start='1') and (vicii_ycounter<248) and (vicii_ycounter>=40) then
            badline_toggle_internal <= not badline_toggle_internal;
            badline_toggle <= not badline_toggle_internal;
            report "BADLINE @ y = " & integer'image(safe_to_integer(displayy)) severity note;
            report "BADLINE first_card_of_row = %" & to_string(std_logic_vector(first_card_of_row)) severity note;
            report "BADLINE prev_first_card_of_row = %" & to_string(std_logic_vector(prev_first_card_of_row)) severity note;
          else
            report "BADLINE in vertical border suppressed @ y = " & integer'image(safe_to_integer(displayy)) severity note;
          end if;
        else
          report "noBADLINE" severity note;
          raster_fetch_state <= FetchFirstCharacter;
        end if;

        -- Now check if we have tipped over from one logical pixel row to another.
        chargen_y <= chargen_y_next;
        if chargen_y_sub=chargen_y_scale then
          chargen_y_next <= chargen_y_next + 1;
          if chargen_y_scale /= 0 then
            if chargen_y_next = "111" then
              report "bumping chargen_y to " & integer'image(safe_to_integer(chargen_y)) severity note;
              bump_screen_row_address<='1';
            end if;
            if pixels_since_last_char = "111" then
              chargen_y_next <= "000";
            end if;
          else
            if chargen_y_next = "111" then
              report "LEGACY: Bumping screen row address one raster early for V400";
              bump_screen_row_address<='1';
            end if;
            if pixels_since_last_char = "110" then
              chargen_y_next <= "000";
            end if;
          end if;
          if (chargen_y_scale=x"02") and (chargen_y(0)='1') then
            chargen_y_sub <= "00001";
          else
            report "LEGACY: chargen_y_sub = 0 due increment of chargen_y";
            chargen_y_sub <= (others => '0');
          end if;
        else
          report "LEGACY: chargen_y_sub incremented";
          chargen_y_sub <= chargen_y_sub + 1;
        end if;

        if bump_screen_row_address='1' then
          bump_screen_row_address <= '0';

          -- Compute the address for the screen row.
          if (text_mode='0') and (sixteenbit_charset='1') then
            -- 16bit charset mode + bitmap mode = 2 bytes screen memory per card,
            -- so that we can pick foreground and background colours from full
            -- 256-colour palette.
            screen_row_address <= screen_ram_base(19 downto 0) + first_card_of_row;
          else
            screen_row_address <= screen_ram_base(19 downto 0) + first_card_of_row;
          end if;

          if before_y_chargen_start='0' then
            -- Increment card number every "bad line"
            report "LEGACY: Advancing first_card_of_row due to end of character";
            first_card_of_row <= to_unsigned(safe_to_integer(first_card_of_row) + row_advance,16);
            display_row_number <= display_row_number + 1;
            if display_row_number = display_row_count then
              -- Stop chargen on next raster
              stop_chargen_raster_counter <= stop_chargen_delay;
            end if;
          else
            report "LEGACY: NOT advancing first_card_of_row due to end of character (before_y_chargen_start=1)";
          end if;
        end if;

      end if;

      if xcounter<(safe_to_integer(frame_h_front)+display_width) then
        xbackporch <= '0';
        xbackporch_edge <= '0';
      else
        xbackporch <= '1';
        xbackporch_edge <= not xbackporch;
      end if;

      -- Work out if the border is active
      if displayy=border_y_bottom then
        vertical_border <= '1';
      end if;
      if displayy=border_y_top then
        vertical_border <= '0';
      end if;

      if xcounter<border_x_left or xcounter>=border_x_right or
        vertical_border='1' then
        inborder<='1';
        viciv_flyback <= '1';
      else
        inborder<=blank;
        viciv_flyback <= '0';
      end if;

      if vga_in_frame = '0' then
        indisplay := '0';
        report "clearing indisplay because of horizontal porch" severity note;
      end if;

      -- Calculate vertical flyback and related signals
      if ycounter=frame_v_front then
        vert_in_frame <= '1';
      elsif ycounter=0 then
        -- Start of vertical flyback
        indisplay := '0';
        report "clearing indisplay because of vertical porch";

        vert_in_frame <= '0';
        -- Send a 1 cycle pulse at the end of each frame for
        -- streaming display module to synchronise on.
        if vert_in_frame = '1' then
          pixel_frame_toggle <= not pixel_frame_toggle;
          pixel_newframe <= '1';
          pixel_newframe_internal <= '1';
        else
          pixel_newframe <= '0';
          pixel_newframe_internal <= '0';
        end if;

      end if;

      -- Generate pixel clock based on x640 clock
      last_vicii_xcounter_640 <= vicii_xcounter_640;
      if vicii_xcounter_640 /= last_vicii_xcounter_640 then
        lcd_pixel_strobe <= indisplay;
        report "lcd_pixel_strobe = " & std_logic'image(indisplay);
      else
        lcd_pixel_strobe <= '0';
        report "lcd_pixel_strobe = 0";
      end if;

      report "chargen_active=" & std_logic'image(chargen_active)
        & ", xcounter = " & to_string(std_logic_vector(xcounter))
        & ", x_chargen_start = " & to_string(std_logic_vector(x_chargen_start)) severity note;
      if xcounter=border_x_right then
        -- Stop character generator as soon as we hit the right border
        -- so that we can switch to fetching sprite data for the next raster.
        report "Masking chargen_active based on xcounter<border_x_right" severity note;
        chargen_active <= '0';
        chargen_active_soon <= '0';
      end if;
      x_chargen_start_minus1 <= x_chargen_start - 1;
      if xcounter = x_chargen_start_minus1 then
        -- trigger next card at start of chargen row
        chargen_x <= (others => '0');
        report "reset chargen_x" severity note;
      end if;
      if xcounter = x_chargen_start then
        -- Gets masked to 0 below if displayy is above y_chargen_start
        chargen_active <= '1';
        report "Setting chargen_active based on xcounter = x_chargen_start" severity note;
        chargen_active_soon <= '0';
      end if;
      y_chargen_start_minus_one <= y_chargen_start-1;
      if displayy = (y_chargen_start_minus_one) then
        justbefore_y_chargen_start <= '1';
      else
        justbefore_y_chargen_start <= '0';
      end if;
      if displayy = "000000000000" then
        before_y_chargen_start <= '1';
      elsif displayy = y_chargen_start then
        before_y_chargen_start <= '0';
      end if;
      -- Allow y_chargen_start to be shifted down mid-frame to allow
      -- multiple character displays per screen, e.g., for fixed vs scrolling.
      if displayy < y_chargen_start_minus_one then
        before_y_chargen_start <= '1';
      end if;
      if before_y_chargen_start = '1' and justbefore_y_chargen_start='0' then
        -- We have to reset the chargen Y value pipeline.
        -- So chargen_y goes to zero, but we then need to make sure we don't
        -- accidentally double print the top line of pixels, so we pre-advance
        -- chargen_y_sub or chargen_y_next as appropriate.
        chargen_y <= "000";
        if chargen_y_scale = 0 then
          chargen_y_next <= "001";
          chargen_y_sub <= "00000";
        else
          chargen_y_next <= "000";
          chargen_y_sub <= "00001";
        end if;
        if chargen_y_sub /= 0 then
          report "LEGACY: Reseting chargen_y_sub";
        end if;
        chargen_active <= '0';
        chargen_active_soon <= '0';
        -- Force badline so that moving chargen down results in fresh loading
        -- of the first line of text.
        prev_first_card_of_row <= (others => '1');
        report "Masking chargen_active based on displayy<y_chargen_start" severity note;

      end if;

      if xcounter(5)='1' and xcounter(4)='1' then
        displaycolumn0 <= '0';
      end if;
      if xcounter = 0 then
        report "ycounter = " & integer'image(safe_to_integer(ycounter))
          & ", before_y_chargen_start = " & std_logic'image(before_y_chargen_start)
          & ", chargen_y = " & integer'image(safe_to_integer(chargen_y))
          & ", chargen_y_sub = " & integer'image(safe_to_integer(chargen_y_sub))
          & ", chargen_active = " & std_logic'image(chargen_active)
          ;

      end if;

      if short_line='1' then
        row_advance <= short_line_length;
      else
        row_advance <= safe_to_integer(virtual_row_width);
      end if;

      viciv_outofframe <= (not indisplay_t3);

--      if indisplay_t3='1' then
      if inborder='1' or (bitplane_mode='1' and viciv_bitplane_chargen_on='0') then
        pixel_colour <= border_colour;
        pixel_alpha <= x"FF";
        report "VICIV: Drawing border" severity note;
      elsif chargen_active='0' then
        pixel_colour <= screen_colour;
        report "VICIV: no character pixel data as chargen_active=0" severity note;
      else
        -- Otherwise read pixel data from raster buffer
        if raster_buffer_read_address(9 downto 0) = to_unsigned(0,10) then
          report "LEGACY: Painting pixels from raster buffer";
        end if;
        report "VICIV: raster buffer reading next from = $" & to_hstring(raster_buffer_read_address)
          & "/$" & to_hstring(raster_buffer_max_write_address_prev)
          & ", pixel_colour = $" & to_hstring(raster_buffer_read_data(7 downto 0))
          & ", pixel_alpha = $" & to_hstring(raster_buffer_read_data(16 downto 9))
          & ", pixel_is_foreground = " & std_logic'image(raster_buffer_read_data(8))
          severity note;
        pixel_colour <= raster_buffer_read_data(7 downto 0);
        pixel_alpha <= raster_buffer_read_data(16 downto 9);
        -- 18th bit indicates to use primary or alternate palette
        pixel_alt_palette <= raster_buffer_read_data(17);
        -- 9th bit indicates foreground for sprite collission handling
        pixel_is_background <= not raster_buffer_read_data(8);
        pixel_is_foreground <= raster_buffer_read_data(8);
      end if;

      -- Make delayed versions of card number and x position so that we have time
      -- to fetch character row data.
      chargen_x_t1 <= chargen_x;
      chargen_x_t2 <= chargen_x_t1;
      chargen_x_t3 <= chargen_x_t2;
      charrow_t1 <= charrow;
      charrow_t2 <= charrow_t1;
      card_number_t1 <= card_number(7 downto 0);
      card_number_t2 <= card_number_t1;
      card_number_t3 <= card_number_t2;
      indisplay_t1 <= indisplay;
      indisplay_t2 <= indisplay_t1;
      indisplay_t3 <= indisplay_t2;

      -- We use a drive stage for these lines to preserve CPU timing.
      debug_cycles_to_next_card_drive <= debug_cycles_to_next_card;
      debug_chargen_active_drive <= debug_chargen_active;
      debug_chargen_active_soon_drive <= debug_chargen_active_soon;
      debug_raster_fetch_state_drive <= debug_raster_fetch_state;
      debug_paint_fsm_state_drive <= debug_paint_fsm_state;
      debug_charrow_drive <= debug_charrow;
      debug_charaddress_drive <= debug_charaddress;
      debug_character_data_from_rom_drive <= debug_character_data_from_rom;
      debug_screen_ram_buffer_address_drive <= debug_screen_ram_buffer_address;
      debug_raster_buffer_read_address_drive <= debug_raster_buffer_read_address;
      debug_raster_buffer_write_address_drive <= debug_raster_buffer_write_address;

      -- Actually, we use two drive stages since the video timing is so pernickety.
      -- The 2nd drive stage is driven by the cpuclock. Search for _drive2 to
      -- find it.

      if xcounter=debug_x and ycounter=debug_y then
        debug_cycles_to_next_card <= cycles_to_next_card;
        debug_chargen_active <= chargen_active;
        debug_chargen_active_soon <= chargen_active_soon;
        debug_raster_fetch_state <= raster_fetch_state;
        debug_paint_fsm_state <= paint_fsm_state;
        debug_charrow <= charrow;
--        debug_charaddress <= charaddress;
        debug_character_data_from_rom <= character_data_from_rom;
        debug_screen_ram_buffer_address <= screen_ram_buffer_read_address;
        debug_raster_buffer_read_address <= raster_buffer_read_address(7 downto 0);
        debug_raster_buffer_write_address <= raster_buffer_write_address(7 downto 0);
      end if;

      -- Pixels have a two cycle pipeline to help keep timing contraints:

      report "PIXEL (" & integer'image(safe_to_integer(xcounter)) & "," & integer'image(safe_to_integer(displayy)) & ") : colour =\ $"
        & to_hstring(postsprite_pixel_colour)
        & ", RGBA = $" &to_hstring(palette_rdata)
        & ", alpha = $" & to_hstring(postsprite_alpha_value)
        & ", vga_in_frame = " & std_logic'image(vga_in_frame)
        & ", external_pixel_strobe = " & std_logic'image(external_pixel_strobe_in)
        severity note;

      -- 1. From pixel colour lookup RGB

      -- Feed pixel into sprite pipeline
      report "Feeding pixel+alpha to pipeline: pixel_colour=$" & to_hstring(pixel_colour)
        & ", pixel_alpha=$" & to_hstring(pixel_alpha);
      chargen_pixel_colour <= pixel_colour;
      chargen_alpha_value <= pixel_alpha;
      pixel_is_foreground_in <= pixel_is_foreground;
      pixel_is_background_in <= pixel_is_background;

      --report "SPRITE: pre_pixel_colour = $" & to_hstring(pixel_colour)
      --  & ", postsprite_pixel_colour = $" & to_hstring(postsprite_pixel_colour);

      -- One pixel delay required for alternate palette selection
      postsprite_alternate_palette_delayed <= postsprite_alternate_palette;

      -- Use palette bank 3 for "palette ROM" colours (C64 default colours
      -- should be placed there for C65 compatibility).
      if postsprite_pixel_colour(7 downto 4) = x"0" and reg_palrom='0' then
        -- Get pixel colour (which may be foreground or background)
        palette_address <= "11" & std_logic_vector(postsprite_pixel_colour);
        -- Get the colour of the background for doing the alpha blending
        alias_palette_address <= "11" & std_logic_vector(paint_background);
        if pixel_is_sprite='0' or sprite_alpha_blend_enables(postsprite_sprite_number)='0' then
          alpha_blend_alpha <= postsprite_alpha_value;
        else
          alpha_blend_alpha <= sprite_alpha_blend_value;
        end if;
      else
        palette_address(7 downto 0) <= std_logic_vector(postsprite_pixel_colour);
        alias_palette_address(7 downto 0) <= std_logic_vector(paint_background);
        if pixel_is_sprite='0' then
          if postsprite_alternate_palette_delayed='1' then
            palette_address(9 downto 8) <= palette_bank_chargen_alt;
            alias_palette_address(9 downto 8) <= palette_bank_chargen_alt;
          else
            palette_address(9 downto 8) <= palette_bank_chargen;
            alias_palette_address(9 downto 8) <= palette_bank_chargen_alt;
          end if;
          alpha_blend_alpha <= postsprite_alpha_value;
        else
          -- If the pixel is a sprite pixel, then apply the sprite alpha value.
          -- XXX The video pipeline currently doesn't tell us WHICH sprite the
          -- pixel belongs to, and we need to know this to be able to decide if
          -- we should alpha blend the sprite pixel to whatever is behind it.
          -- XXX We should blend to the non-sprite palette, so that sprites can
          -- have their own colours, but still fade into any background colour.
          palette_address(9 downto 8) <= palette_bank_sprites;
          alias_palette_address(9 downto 8) <= palette_bank_sprites;
          if sprite_alpha_blend_enables(postsprite_sprite_number)='0' then
            alpha_blend_alpha <= postsprite_alpha_value;
          else
            alpha_blend_alpha <= sprite_alpha_blend_value;
          end if;
        end if;
      end if;

      if xray_mode='1' then
        -- Debug mode enabled using switch 1 to show whether we think pixels
        -- are foreground, background, sprite and/or border.
        palette_address(9 downto 6) <= (others => '0');
        palette_address(5) <= postsprite_pixel_colour(0);
        palette_address(4) <= paint_background(0);
        -- background was always set due to bug with passing in foreground flag
        -- to background flag in sprite module.
        -- sprite + text = $7 (foreground, sprites and background!)
        -- text = $E (foreground and background, and not alpha sprite pixel)
        -- sprite white fg (=+$20) on blue bg (= no +$10) = $21, as expected
        if pixel_is_sprite='0' or sprite_alpha_blend_enables(postsprite_sprite_number)='0' then
          palette_address(3) <= '1';
        else
          palette_address(3) <= postsprite_inborder;
        end if;
        palette_address(2) <= pixel_is_foreground_out;
        palette_address(1) <= pixel_is_background_out;
        palette_address(0) <= pixel_is_sprite;
      end if;

      -- VIC-III palette RGB values have only the high bits in the low nybl, and
      -- the high-nybl is reserved.
      -- VIC-IV puts the low nybl in those reserved high-nybl bits
      vga_buffer_red(7 downto 4) <= unsigned(palette_rdata(27 downto 24));
      vga_buffer_red(3 downto 0) <= unsigned(palette_rdata(31 downto 28));
      vga_buffer_green(7 downto 4) <= unsigned(palette_rdata(19 downto 16));
      vga_buffer_green(3 downto 0) <= unsigned(palette_rdata(23 downto 20));
      vga_buffer_blue(7 downto 4) <= unsigned(palette_rdata(11 downto 8));
      vga_buffer_blue(3 downto 0) <= unsigned(palette_rdata(15 downto 12));

      --vga_buffer_red <= unsigned(postsprite_pixel_colour);
      --vga_buffer_green <= unsigned(postsprite_pixel_colour);
      --vga_buffer_blue <= unsigned(postsprite_pixel_colour);

      --vga_buffer_red <= unsigned(postsprite_pixel_colour);
      --vga_buffer_green <= unsigned(postsprite_pixel_colour);
      --vga_buffer_blue <= unsigned(postsprite_pixel_colour);

      -- The nybls have not been switched around for the alpha palette, so we
      -- have to do that here
      composite_bg_red(7 downto 4) <= unsigned(alias_palette_rdata(27 downto 24));
      composite_bg_red(3 downto 0) <= unsigned(alias_palette_rdata(31 downto 28));
      composite_bg_green(7 downto 4) <= unsigned(alias_palette_rdata(19 downto 16));
      composite_bg_green(3 downto 0) <= unsigned(alias_palette_rdata(23 downto 20));
      composite_bg_blue(7 downto 4) <= unsigned(alias_palette_rdata(11 downto 8));
      composite_bg_blue(3 downto 0) <= unsigned(alias_palette_rdata(15 downto 12));

      composite_red <= vga_buffer_red;
      composite_green <= vga_buffer_green;
      composite_blue <= vga_buffer_blue;

      report "Palette read address = $" & to_hstring(palette_address)
        & ", alpha palette read address = $" & to_hstring(alias_palette_address)
        & ", rdata=$" & to_hstring(palette_rdata)
        & ", alias rdata=$" & to_hstring(alias_palette_rdata);
      report "compositing background "
        & "R=$" & to_hstring(alias_palette_rdata(31 downto 24))
        & ", G=$" & to_hstring(alias_palette_rdata(23 downto 16))
        & ", B=$" & to_hstring(alias_palette_rdata(15 downto 8))
        &" with foreground "
        & "R=$" & to_hstring(vga_buffer_red)
        & ", G=$" & to_hstring(vga_buffer_green)
        & ", B=$" & to_hstring(vga_buffer_blue)
        & ", alpha=$" & to_hstring(raster_buffer_read_data(16 downto 9));

      report "alpha composited"
        & " red=$" & to_hstring(composited_red(9 downto 2))
        & ", green=$" & to_hstring(composited_green(9 downto 2))
        & ", blue=$" & to_hstring(composited_blue(9 downto 2));

      if compositer_enable='1' then
        vga_buffer2_red <= unsigned(composited_red(9 downto 2));
        vga_buffer2_green <= unsigned(composited_green(9 downto 2));
        vga_buffer2_blue <= unsigned(composited_blue(9 downto 2));
      else
        vga_buffer2_red <= vga_buffer_red;
        vga_buffer2_green <= vga_buffer_green;
        vga_buffer2_blue <= vga_buffer_blue;
      end if;

      vga_buffer3_red <= vga_buffer2_red;
      vga_buffer3_green <= vga_buffer2_green;
      vga_buffer3_blue <= vga_buffer2_blue;

      vga_buffer4_red <= vga_buffer3_red;
      vga_buffer4_green <= vga_buffer3_green;
      vga_buffer4_blue <= vga_buffer3_blue;

      vga_buffer5_red <= vga_buffer4_red;
      vga_buffer5_green <= vga_buffer4_green;
      vga_buffer5_blue <= vga_buffer4_blue;

      vga_filtered_red <= to_unsigned(safe_to_integer(vga_buffer5_red)
                                      +safe_to_integer(vga_buffer4_red)
                                      +safe_to_integer(vga_buffer3_red)
                                      +safe_to_integer(vga_buffer2_red),10);
      vga_filtered_green <= to_unsigned(safe_to_integer(vga_buffer5_green)
                                        +safe_to_integer(vga_buffer4_green)
                                        +safe_to_integer(vga_buffer3_green)
                                        +safe_to_integer(vga_buffer2_green),10);
      vga_filtered_blue <= to_unsigned(safe_to_integer(vga_buffer5_blue)
                                       +safe_to_integer(vga_buffer4_blue)
                                       +safe_to_integer(vga_buffer3_blue)
                                       +safe_to_integer(vga_buffer2_blue),10);

      if horizontal_filter='0' or reg_h1280='1' then
        vga_palin_red <= vga_buffer3_red;
        vga_palin_green <= vga_buffer3_green;
        vga_palin_blue <= vga_buffer3_blue;
      else
        vga_palin_red <= vga_filtered_red(9 downto 2);
        vga_palin_green <= vga_filtered_green(9 downto 2);
        vga_palin_blue <= vga_filtered_blue(9 downto 2);
      end if;

      if pal_simulate='1' and (reg_h1280 = '0') then
        vga_out_red <= vga_palout_red;
        vga_out_green <= vga_palout_green;
        vga_out_blue <= vga_palout_blue;
      else
        vga_out_red <= vga_palin_red;
        vga_out_green <= vga_palin_green;
        vga_out_blue <= vga_palin_blue;
      end if;

      -- Also use pixel colour to produce RLE compressed video stream for
      -- pushing over ethernet on ff10::6565:6565:6565 IPv6 transient
      -- multi-cast address or via serial console.  However we do it, we first
      -- need to compress the video as much as possible, and to do that, we need
      -- the pixel stream.

      -- Announce each raster line.  Can also be used to identify start of frame.
      if xcounter=safe_to_integer(display_width) then
        report "FRAMEPACKER: end of raster announcement";
        pixel_newraster <= '1';
        pixel_strobe_out <= '0';
        pixel_y <= displayy;
      else
        -- output pixels as packed RGB instead of palette colours
        -- (this 8bpp format is what VNC uses anyway, so there is no functional
        -- loss of colour resolution).
        pixel_stream_out(7 downto 5) <= vga_buffer3_red(7 downto 5);
        pixel_stream_out(4 downto 2) <= vga_buffer3_green(7 downto 5);
        pixel_stream_out(1 downto 0) <= vga_buffer3_blue(7 downto 6);
        -- And also output full 24bit RGB, that the new frame packer uses
        pixel_red_out <= vga_buffer3_red;
        pixel_green_out <= vga_buffer3_green;
        pixel_blue_out <= vga_buffer3_blue;
        xcounter_last <= xcounter;
        if xcounter /= xcounter_last then
          -- XXX pixel_strobe_in should be fed through the pipeline and delayed
          -- to match, so that the correct pixels get latched.
          report "pixel = " & std_logic'image(indisplay)
            & ", xcounter = " & integer'image(safe_to_integer(xcounter));
          pixel_strobe_out <= indisplay;
          pixel_x_out <= safe_to_integer(xcounter);
        else
          pixel_strobe_out <= '0';
        end if;
        pixel_newraster <= '0';
      end if;

      -- 2. From RGB, push out to pins (also draw border)
      if (displayline0 ='1') and (displaycolumn0='1')
        and (((led='1') and (drive_blink_phase='1'))
             or (motor='1')) then
        report "drawing drive led OSD" severity note;
        drive_led_out <= '1';
        vgared_driver <= x"FF";
        vgagreen_driver <= x"00";
        vgablue_driver <= x"00";
      else
        drive_led_out <= '0';
        if show_render_activity='1' then
          vgared_driver <= (others => render_activity(0));
          vgagreen_driver <= (others => render_activity(1));
          vgablue_driver <= (others => render_activity(2));
        else
          vgared_driver <= vga_out_red(7 downto 0);
          vgagreen_driver <= vga_out_green(7 downto 0);
          vgablue_driver <= vga_out_blue(7 downto 0);
        end if;
      end if;

      --------------------------------------------------------------------------
      --------------------------------------------------------------------------
      --------------------------------------------------------------------------
      -- Character/bitmap data preparation
      --------------------------------------------------------------------------
      --------------------------------------------------------------------------
      --------------------------------------------------------------------------

      -- Do chipram read based on fetch scheduled in previous cycle
      this_ramaccess_is_screen_row_fetch <= next_ramaccess_is_screen_row_fetch;
      this_ramaccess_is_glyph_data_fetch <= next_ramaccess_is_glyph_data_fetch;
      this_ramaccess_is_sprite_data_fetch <= next_ramaccess_is_sprite_data_fetch;
      this_ramaccess_screen_row_buffer_address
        <= next_ramaccess_screen_row_buffer_address;
      this_screen_row_fetch_address <= next_screen_row_fetch_address;
      last_ramaccess_is_screen_row_fetch <= this_ramaccess_is_screen_row_fetch;
      last_ramaccess_is_glyph_data_fetch <= this_ramaccess_is_glyph_data_fetch;
      last_ramaccess_is_sprite_data_fetch <= this_ramaccess_is_sprite_data_fetch;
      last_ramaccess_screen_row_buffer_address
        <= this_ramaccess_screen_row_buffer_address;
      last_screen_row_fetch_address <= this_screen_row_fetch_address;
      final_ramdata <= ramdata;
      final_ramaccess_is_screen_row_fetch <= last_ramaccess_is_screen_row_fetch;
      final_ramaccess_is_glyph_data_fetch <= last_ramaccess_is_glyph_data_fetch;
      final_ramaccess_is_sprite_data_fetch <= last_ramaccess_is_sprite_data_fetch;
      final_ramaccess_screen_row_buffer_address
        <= last_ramaccess_screen_row_buffer_address;
      final_screen_row_fetch_address <= last_screen_row_fetch_address;

      if final_ramaccess_is_screen_row_fetch='1' then
        report "buffering screen ram byte $" & to_hstring(final_ramdata) & " to address $" & to_hstring(to_unsigned(safe_to_integer(final_ramaccess_screen_row_buffer_address),16));
      end if;
      screen_ram_buffer_write <= final_ramaccess_is_screen_row_fetch;
      screen_ram_buffer_write_address <= final_ramaccess_screen_row_buffer_address;
      screen_ram_buffer_din <= final_ramdata;
      -- Collect last token for processing
      screen_line_last_token(15 downto 8) <= final_ramdata;
      screen_line_last_token(7 downto 0) <= screen_line_last_token(15 downto 8);

      if raster_fetch_state /= Idle or paint_fsm_state /= Idle then
        report "raster_fetch_state=" & vic_chargen_fsm'image(raster_fetch_state) & ", "
          & "paint_fsm_state=" & vic_paint_fsm'image(paint_fsm_state)
          & ", rb_w_addr=$" & to_hstring(raster_buffer_write_address) severity note;
      end if;

      -- Pre-calculate some expressions to flatten logic in critical path
      -- Note we use prev_first_card_of_row, so that we don't show the last pixel
      -- row from the next char card row down the screen.
      if reg_h640='1' then
        bitmap_glyph_data_address
          <= (character_set_address(19 downto 14)&"00000000000000")
          + (safe_to_integer(screen_ram_buffer_read_address)+safe_to_integer(prev_first_card_of_row))*8+safe_to_integer(chargen_y_hold);
      else
        bitmap_glyph_data_address
          <= (character_set_address(19 downto 13)&"0000000000000")
          + (safe_to_integer(screen_ram_buffer_read_address)+safe_to_integer(prev_first_card_of_row))*8+safe_to_integer(chargen_y_hold);
      end if;
      if xcounter = 0 then
        report "LEGACY: bitmap_glyph_data_address = $"
          & to_hstring(
            to_unsigned(safe_to_integer(character_set_address(19 downto 13))*8192
                        + safe_to_integer(screen_ram_buffer_read_address)
                        +safe_to_integer(first_card_of_row)*8
                        +safe_to_integer(chargen_y_hold)
                        ,17)
            );
      end if;
      display_row_width_minus1 <= display_row_width - 1;

      ramaddress <= next_ramaddress;

      report "raster_fetch_state = " & vic_chargen_fsm'image(raster_fetch_state);
      case raster_fetch_state is
        when Idle => null;
                     -- Show what we are doing in debug display mode
                     render_activity <= "000";
        when FetchScreenRamLine =>
          -- Make sure that painting is not in progress
          if paint_ready='1' then
            -- Set FSM state so that no painting occurs, and so that we
            -- continue to fetch the screen row.  Note that here we just
            -- schedule the memory reads.  The data is written elsewhere.  This
            -- helps to simplify the logic in terms of number of states in the
            -- machine, as well as for accepting the data when it has been read.
            paint_fsm_state <= Idle;
            raster_fetch_state <= FetchScreenRamLine2;
            -- Show what we are doing in debug display mode
            render_activity <= "001";

            -- Reset screen row (bad line) state
            character_number <= to_unsigned(1,11);
            end_of_row_16 <= '0'; end_of_row <= '0';
            report "COLOURRAM: Setting colourramaddress via first_card_of_row."
              & " text_mode=" & std_logic'image(text_mode)
              & ", sixteenbit_charset=" & std_logic'image(sixteenbit_charset);
            colourramaddress <= to_unsigned(safe_to_integer(colour_ram_base) + safe_to_integer(first_card_of_row),16);

            -- Now ask for the first byte.  We indicate all details of this
            -- read so that it can be committed by the receiving side of the logic.
            next_ramaccess_is_screen_row_fetch <= '1';
            next_ramaccess_is_glyph_data_fetch <= '0';
            next_ramaccess_is_sprite_data_fetch <= '0';
            next_ramaccess_screen_row_buffer_address <= to_unsigned(0,9);
            next_screen_row_fetch_address <= screen_row_current_address;

            -- Set pipeline delay countdown for investigating the 16-bit tokens
            -- to see if they indicate programmatic instructions, rather than
            -- ordinary characte data.
            badlineprog_countdown <= 5;

            report "BADLINE, colour_ram_base=$" & to_hstring(colour_ram_base) severity note;

            report "LEGACY: Badline fetch: "
              & "screen_row_current_address = $" & to_hstring(screen_row_current_address)
              ;
          end if;
        when FetchScreenRamLine2 =>
          -- Ask for the next byte.  We indicate all details of this
          -- read so that it can be committed by the receiving side of the logic.
          -- Otherwise, if we are at the end of the row, then stop.

          -- XXX check the last stored token to see if it is a GOTO, GOSUB or RETURN.
          -- If it is, rewind, and redirect accordingly.
          -- Part of the challenge here is that the bytes here are delayed by
          -- several cycles, so we have to take that into account.
          if sixteenbit_charset='1' then
            if badlineprog_countdown = 0 then
              report "BADLINEPROG: last_token=$" & to_hstring(screen_line_last_token);
              if next_token_is_goto='1' then
                -- Set screen RAM fetch to the value of this token (shifted
                -- left one bit).
                -- XXX goto tokens can only point to first 128KB of RAM.
                next_screen_row_fetch_address(19 downto 17) <= "000";
                next_screen_row_fetch_address(16 downto 1) <= screen_line_last_token;
                next_screen_row_fetch_address(0) <= '0';
                -- Flush screen row buffer fetch pipeline while waiting for
                -- branch to complete
                badlineprog_inhibit_screen_row_buffer_write_counter <= 4;
                -- Clear next token is branch flag
                next_token_is_goto <= '0';
              else
                case screen_line_last_token is
                  when x"FFFF" =>
                    -- End of line / RETURN token
                    -- If nothing on the stack, this is the last token to fetch.
                    null;
                  when x"FFFE" =>
                    -- GOTO: Next token is address to goto (shifted left one bit)
                    null;
                  when x"FFFD" =>
                    -- GOSUB: Next token is address to goto (shifted left one bit)
                    -- (Same as GOTO, except that we push the write offset to be
                    --  retrieved on return.)
                    null;
                  when others =>
                    null;
                end case;
              end if;
              -- We need two bytes before we have next token, so set count down
              badlineprog_countdown <= 1;
            else
              badlineprog_countdown <= badlineprog_countdown - 1;
            end if;
          end if;

          -- Is this the last character in the row?
          -- (Only used when screen lines have only one character?)
          if character_number = display_row_width_minus1&'1' then
            end_of_row_16 <= '1';
          else
            end_of_row_16 <= '0';
          end if;
          if character_number = '0'&display_row_width_minus1 then
            end_of_row <= '1';
          else
            end_of_row <= '0';
          end if;

          -- Work out if we need to fetch any more
          if (sixteenbit_charset='1' and end_of_row_16='1')
            or (sixteenbit_charset='0' and end_of_row='1') then
            -- All done, move to actual row fetch
            raster_fetch_state <= FetchFirstCharacter;
            next_ramaccess_is_screen_row_fetch <= '0';
            next_ramaccess_is_glyph_data_fetch <= '0';
            next_ramaccess_is_sprite_data_fetch <= '0';
          else
            -- More to fetch, so keep scheduling the reads
            if screenline_return_stack_count = 0 then
              -- Only advance fetched character counter if we are not in a
              -- GOSUB in the screen row data.
              character_number <= character_number + 1;
            end if;
            next_ramaccess_is_screen_row_fetch <= '1';
            report "Scheduling read of $" & to_hstring(next_screen_row_fetch_address)
              & " for screen row read.";
            next_ramaccess_is_glyph_data_fetch <= '0';
            next_ramaccess_is_sprite_data_fetch <= '0';
            if next_token_is_goto='0' then
              next_ramaccess_screen_row_buffer_address <= next_ramaccess_screen_row_buffer_address + 1;
              next_screen_row_fetch_address <= next_screen_row_fetch_address + 1;
            end if;
          end if;
        when FetchFirstCharacter =>
          -- Show what we are doing in debug display mode
          render_activity <= "010";

          next_ramaccess_is_screen_row_fetch <= '0';
          next_ramaccess_is_glyph_data_fetch <= '0';
          next_ramaccess_is_sprite_data_fetch <= '0';

          -- By default glyphs do paint the background when required.
          -- (This can be turned off for the rest of a line by using a tab-stop
          -- token).
          glyph_paint_background <= '1';

          -- And don't invert palettes by default
          glyph_alternate_palette_invert <= '0';

          -- By default, characters are drawn in the foreground.
          -- If force_chars_background is set, then chars are forced into the background.
          -- If force_chars_foreground is set, then chars are forced into the foreground
          -- (ignoreing if a particular colour bit would normally be required
          -- to achieve this).
          force_chars_foreground <= '1';
          force_chars_background <= '0';

          -- By default, draw all pixel rows of each character
          screenline_draw_mask <= (others => '1');
          report "DRAWMASK: Reset drawmask to $ff";

          report "ZEROing screen_ram_buffer_read_address" severity note;
          screen_ram_buffer_read_address <= to_unsigned(0,9);

          character_number <= (others => '0');
          card_of_row <= (others => '0');
          if bitplane_mode='0' or viciv_bitplane_chargen_on='1' then
            raster_fetch_state <= FetchNextCharacter;
          else
            raster_fetch_state <= EndOfCharGen;
          end if;
        when FetchNextCharacter =>
          -- Fetch next character
          -- All we can expect here is that character_number is correctly set.

          report "screen_ram byte read from buffer as $" & to_hstring(screen_ram_buffer_dout) severity note;

          -- XXX: Timing to be fixed.
          -- (Ideally we would take only 8 cycles to fetch a character so that
          -- we use as little raster time as possible, especially for true 1920
          -- pixel modes.  However, for now, the emphasis is on making it work.
          -- In particular, we should pipeline reading of the next character
          -- number and resolving relevant information about it with the fetching
          -- of the data for the current character. That would basically fix it.)

          -- Based on either the card number (for bitmap modes) or
          -- character_number (for text modes), work out the address where the
          -- data lives.

          -- Work out exactly what mode we are in so that we can be a bit more
          -- efficient in the next cycle
          if screen_ram_buffer_read_address = to_unsigned(0,9) then
            report "LEGACY: Char/bitmap data fetch: "
              & "chargen_y_hold = $" & to_hstring(chargen_y_hold)
              & ", chargen_y = $" & to_hstring(chargen_y)
              & ", chargen_y_next = $" & to_hstring(chargen_y_next)
              ;
          end if;
          if text_mode='1' then
            -- Read 8 or 16 bit screen RAM data for character number information
            -- (the address was put on the bus for us already).
            -- Handle extended background colour mode here if required.
            glyph_number(12 downto 8) <= "00000";
            glyph_number(5 downto 0) <= screen_ram_buffer_dout(5 downto 0);
            if extended_background_mode='1' then
              background_colour_select <= screen_ram_buffer_dout(7 downto 6);
            else
              background_colour_select <= "00";
              glyph_number(7 downto 6) <= screen_ram_buffer_dout(7 downto 6);
            end if;
          else
            -- Read 8 or 16 bits of colour information for bitmap modes.
            -- In 16 bit charset mode we allow 8 bits for fore and back-ground
            -- colours.
            if sixteenbit_charset='1' then
              bitmap_colour_foreground <= screen_ram_buffer_dout;
            else
              bitmap_colour_foreground <= x"0" & screen_ram_buffer_dout(7 downto 4);
              bitmap_colour_background <= x"0" & screen_ram_buffer_dout(3 downto 0);
            end if;
          end if;

          -- calculate data address for bitmap mode in case we need it
          -- bitmap area is always on an 8KB boundary
          glyph_data_address <= bitmap_glyph_data_address;
          report "bitmap srba="& integer'image(safe_to_integer(screen_ram_buffer_read_address))
            & ", fcor="& integer'image(safe_to_integer(first_card_of_row))
            severity note;

          screen_ram_buffer_read_address <= screen_ram_buffer_read_address + 1;
          report "INCREMENTing screen_ram_buffer_read_address to " & integer'image(safe_to_integer(screen_ram_buffer_read_address)+1) severity note;

          -- Clear 16-bit character attributes in case we are reading 8-bits only.
          glyph_flip_horizontal <= '0';
          glyph_flip_vertical <= '0';
          glyph_with_alpha <= '0';
          glyph_width_deduct <= to_unsigned(0,4);
          glyph_goto <= '0';
          glyph_4bit <= '0';

          screen_ram_is_ff <= '0';
          screen_ram_high_is_ff <= '0';

          if sixteenbit_charset='1' then
            if screen_ram_buffer_dout = x"ff" then
              screen_ram_is_ff <= '1';
            end if;
            raster_fetch_state <= FetchCharHighByte;
          else
            -- 8 bit character set / colour info mode
            glyph_full_colour <= fullcolour_8bitchars;
            if text_mode='1' then
              raster_fetch_state <= FetchTextCell;
            else
              raster_fetch_state <= FetchBitmapCell;
            end if;
          end if;
        when FetchCharHighByte =>

          -- In 16-bit character mode we also need to read the 2nd colour byte,
          -- which are doing now, so we need to advance colourramaddress ready
          -- to read the low colour byte of the next character.
          report "COLOURRAM: Incrementing colourramaddress";
          colourramaddress <= colourramaddress + 1;
          report "reading high colour byte";

          -- Work out if character is full colour (ignored for bitmap mode but
          -- calculated outside of if test to flatten logic).
          if screen_ram_buffer_dout(4 downto 0) = "00000" then
            glyph_full_colour <= fullcolour_8bitchars;
          else
            glyph_full_colour <= fullcolour_extendedchars;
          end if;
          if text_mode='1' then
            -- We only allow 8192 characters in extended mode.
            -- The spare bits are used to provide some (hopefully useful)
            -- extended attributes.
            glyph_number(12 downto 8) <= screen_ram_buffer_dout(4 downto 0);
            glyph_width_deduct(2 downto 0) <= screen_ram_buffer_dout(7 downto 5);
            glyph_width_deduct(3) <= '0';
            if screen_ram_buffer_dout = x"ff" then
              screen_ram_high_is_ff <= '1';
            end if;

            -- First colour RAM byte has vertical controls
            glyph_flip_vertical <= colourramdata(7);
            glyph_flip_horizontal <= colourramdata(6);
            glyph_with_alpha <= colourramdata(5);
            -- bit 4 indicates glyph number is actually a GOTO pixel number
            -- (allows over-rendering and skipping)
            glyph_goto <= colourramdata(4);

            -- Enables chars to be 16x8, with 4 bits each using
            -- full-colour painting pipeline
            glyph_4bit <= colourramdata(3);
            report "DRAWMASK: Reading glyph_4bit from bit 3 of $" & to_hstring(colourramdata);
            if colourramdata(3)='1' then
              glyph_full_colour <= '1';
            end if;
            -- Because the glyphs are 16 pixels wide, we need to have an extra
            -- bit for width trimming
            glyph_width_deduct(3) <= colourramdata(2);


            -- XXX colour ram bits 0 - 1 of byte 1 were for trimming top or bottom
            -- of rows of glyphs, but have since been reclaimed.


            raster_fetch_State <= FetchTextCell;
          else
            bitmap_colour_background <= screen_ram_buffer_dout;
            raster_fetch_state <= FetchBitmapCell;
          end if;

          -- calculate data address for bitmap mode in case we need it
          -- bitmap area is always on an 8KB boundary
          glyph_data_address <= bitmap_glyph_data_address;
          report "bitmap srba="& integer'image(safe_to_integer(screen_ram_buffer_read_address))
            & ", fcor="& integer'image(safe_to_integer(first_card_of_row))
            severity note;

          screen_ram_buffer_read_address <= screen_ram_buffer_read_address + 1;
          report "INCREMENTing screen_ram_buffer_read_address to " & integer'image(safe_to_integer(screen_ram_buffer_read_address)+1) severity note;
        when FetchBitmapCell =>
          report "LEGACY: from bitmap layout, we get glyph_data_address = $" & to_hstring("000"&glyph_data_address) severity note;
          raster_fetch_state <= FetchBitmapData;
        when FetchTextCell =>
          if screen_ram_is_ff='1' and screen_ram_high_is_ff='1' then
            -- 16-bit Character is $FFFF, which is end of line marker.
            -- So remember that this line is short, and don't add the virtual
            -- row width, and abort drawing this line.
            short_line <= '1';
            short_line_length <= safe_to_integer(screen_ram_buffer_read_address);
          end if;

          report "LEGACY: from screen_ram we get glyph_number = $" & to_hstring(to_unsigned(safe_to_integer(glyph_number),16)) severity note;
          -- We now know the character number, and whether it is full-colour or
          -- normal, and whether we are flipping in either axis, and so can
          -- work out the address to fetch data from.
          if glyph_with_alpha='1' then
            report "glyph is alpha blended";
          end if;

          -- Work out if we are drawing this line of this char
          draw_mask_blank <= not screenline_draw_mask(to_integer(chargen_y_hold));
          report "DRAWMASK: Y = " & integer'image(to_integer(chargen_y_hold))
            & ": Setting draw_mask_blank to " & std_logic'image(not screenline_draw_mask(to_integer(chargen_y_hold)))
            & ", glyph_4bit = " & std_logic'image(glyph_4bit)
            & ", screenline_draw_mask = $" & to_hstring(screenline_draw_mask);

          if glyph_full_colour='1' then
            report "glyph is full colour";
            -- Full colour glyphs come from 64*(glyph_number) in RAM, never
            -- from character ROM.  As we only have 2^16 positions, the glyphs
            -- must be in only the first 512KB of chipram.
            glyph_data_address(19) <= '0';
            if glyph_flip_vertical='1' then
              glyph_data_address(18 downto 6) <= glyph_number(12 downto 0);
              glyph_data_address(5 downto 3) <= not chargen_y_hold;
            else
              -- Allow setting an offset in the glyph address for easier
              -- free vertical positioning of RRB soft-sprites
              glyph_data_address(18 downto 3) <= (glyph_number(12 downto 0) & chargen_y_hold) + glyph_y_offset;
            end if;
            if glyph_flip_horizontal='1' then
              glyph_data_address(2 downto 0) <= "111";
            else
              glyph_data_address(2 downto 0) <= "000";
            end if;
            character_data_from_rom <= '0';
          else
            -- Normal character glyph fetched relative to character_set_address.
            -- Again, we take into account if we are flipping vertically.
            if glyph_flip_vertical='0' then
              glyph_data_address
                <= character_set_address(19 downto 0)
                + safe_to_integer(glyph_number)*8+safe_to_integer(chargen_y_hold);
            else
              glyph_data_address
                <= character_set_address(19 downto 0)
                + safe_to_integer(glyph_number)*8+7-safe_to_integer(chargen_y_hold);
            end if;
            -- Mark as possibly coming from ROM
            character_data_from_rom <= '1';
          end if;
          raster_fetch_state <= FetchTextCellColourAndSource;
        when FetchBitmapData =>
          -- Show what we are doing in debug display mode
          render_activity <= "011";

          if character_data_from_rom = '1' then
            if glyph_data_address(19 downto 12) = "0000"&x"1"
              or glyph_data_address(19 downto 12) = "0000"&x"9" then
              report "reading from rom: glyph_data_address=$" & to_hstring(glyph_data_address(15 downto 0))
                & "chargen_y_hold=" & to_string(std_logic_vector(chargen_y_hold)) severity note;
              character_data_from_rom <= '1';
            else
              character_data_from_rom <= '0';
            end if;
          end if;

          -- Schedule next colour ram byte
          report "COLOURRAM: Incrementing colourramaddress";
          colourramaddress <= colourramaddress + 1;

          if viciii_extended_attributes='1' or glyph_full_colour='1' then
            -- 8-bit colour RAM in VIC-III/IV mode for bitmap mode, or for
            -- full-colour text mode
            glyph_colour_drive <= colourramdata;
          else
            -- 16 colours only in VIC-II mode
            glyph_colour_drive(7 downto 4) <= x"0";
            glyph_colour_drive(3 downto 0) <= colourramdata(3 downto 0);
          end if;

          glyph_visible_drive <= glyph_visible;
          glyph_reverse_drive <= glyph_reverse;
          glyph_underline_drive <= glyph_underline;
          glyph_bold_drive <= glyph_bold;

          raster_fetch_state <= PaintMemWait;
        when FetchTextCellColourAndSource =>
          -- Finally determine whether source is from RAM or CHARROM
          if character_data_from_rom = '1' then
            if glyph_data_address(19 downto 12) = "0000"&x"1"
              or glyph_data_address(19 downto 12) = "0000"&x"9" then
              report "reading from rom: glyph_data_address=$" & to_hstring(glyph_data_address(15 downto 0))
                & "chargen_y=" & to_string(std_logic_vector(chargen_y_hold)) severity note;
              character_data_from_rom <= '1';
            else
              character_data_from_rom <= '0';
            end if;
          end if;
          -- Record colour and attribute information from colour RAM
          -- XXX We do this even in bitmap mode!
          if glyph_full_colour='1' and viciii_extended_attributes='0' then
            glyph_colour_drive <= colourramdata;
          else
            glyph_colour_drive(7 downto 4) <= "0000";
            glyph_colour_drive(3 downto 0) <= colourramdata(3 downto 0);
          end if;
          glyph_bold_drive <= '0';
          glyph_underline_drive <= '0';
          glyph_reverse_drive <= '0';
          glyph_visible_drive <= '1';
          glyph_blink_drive <= '0';

          report "DRAWMASK: goto=" & std_logic'image(glyph_goto);
          if glyph_goto='1' then
            -- Also hold the 2nd colour RAM byte for use as the draw mask,
            -- if its a GOTOX token with the appropriate bit set
            screenline_draw_mask_drive <= colourramdata;
            report "DRAWMASK: Loading screenline_draw_mask_drive with $" & to_hstring(colourramdata)
              & ", glyph_4bit = " & std_logic'image(glyph_4bit);
          end if;

          -- Get bold + reverse combination, even if not in VIC-III extended attribute
          -- mode, so that we can check for it in GOTOX tokens.
          glyph_bold_and_reverse <= colourramdata(5) and colourramdata(6);

          report "Reading high-byte of colour RAM (value $" & to_hstring(colourramdata)&")";
          if multicolour_mode='1' then
            -- Multicolour + full colour mode + 16-bit char mode = simple 256 colour foreground
            -- colour selection from 2nd byte of colour RAM data
            glyph_colour_drive(7 downto 4) <= colourramdata(7 downto 4);
          else
            if viciii_extended_attributes='1' then

              if bug_compat_char_attr='1' then
                -- VIC-III legacy behavior for character attributes
                if colourramdata(4)='1' then
                  -- Blinking glyph
                  glyph_blink_drive <= '1';
                  if colourramdata(5)='1'
                    or colourramdata(6)='1'
                    or colourramdata(7)='1' then
                    -- Blinking attributes
                    if viciii_blink_phase='1' then
                      glyph_reverse_drive <= colourramdata(5);
                      glyph_bold_drive <= colourramdata(6);
                      glyph_colour_drive(4) <= colourramdata(6);
                      if chargen_y_hold="111" then
                        glyph_underline_drive <= colourramdata(7);
                      end if;
                    end if;
                  else
                    -- Just plain blinking character
                    glyph_visible_drive <= viciii_blink_phase;
                  end if;
                else
                  -- Non-blinking attributes
                  glyph_visible_drive <= '1';
                  glyph_reverse_drive <= colourramdata(5);
                  glyph_bold_drive <= colourramdata(6);
                  glyph_colour_drive(4) <= colourramdata(6);
                  if chargen_y_hold="111" then
                    glyph_underline_drive <= colourramdata(7);
                  end if;
                end if;

              else  -- bug_compat_char_attr='0'
                -- VIC-IV fix for character attributes:
                -- reverse, blink, and underline to behave identically for
                -- both lower palette (non-"bold") and upper/alternate palette
                -- ("bold") characters.
                glyph_colour_drive(4) <= colourramdata(6);
                glyph_bold_drive <= colourramdata(6) and not colourramdata(5);
                if colourramdata(4)='1' then
                  -- Blinking glyph
                  glyph_blink_drive <= '1';
                  if colourramdata(5)='1'
                    or colourramdata(7)='1' then
                    -- Blinking attributes
                    if viciii_blink_phase='1' then
                      glyph_reverse_drive <= colourramdata(5);
                      if chargen_y_hold="111" then
                        glyph_underline_drive <= colourramdata(7);
                      end if;
                    end if;
                  else
                    -- Just plain blinking character
                    glyph_visible_drive <= viciii_blink_phase;
                  end if;
                else
                  -- Non-blinking attributes
                  glyph_visible_drive <= '1';
                  glyph_reverse_drive <= colourramdata(5);
                  if chargen_y_hold="111" then
                    glyph_underline_drive <= colourramdata(7);
                  end if;
                end if;
              end if;
            end if;
          end if;

          -- Schedule next colour ram byte
          report "COLOURRAM: Incrementing colourramaddress";
          colourramaddress <= colourramaddress + 1;

          raster_fetch_state <= PaintMemWait;
        when PaintMemWait =>
          -- This is the time that the 2nd colour byte will be available if we
          -- are in 16-bit text mode, so copy out the value.
          -- Allow for 2 cycle delay to get data in paint_ramdata
          -- In this cycle chardata and ramdata will have the requested value
          glyph_visible <= glyph_visible_drive;
          glyph_reverse <= glyph_reverse_drive;
          glyph_underline <= glyph_underline_drive;
          glyph_bold <= glyph_bold_drive;
          glyph_colour_drive2 <= glyph_colour_drive;
          raster_fetch_state <= PaintMemWait2;
        when PaintMemWait2 =>
          glyph_colour <= glyph_colour_drive2;
          if glyph_4bit='0' then
            glyph_width <= 8 - safe_to_integer(glyph_width_deduct(2 downto 0));
          else
            glyph_width <= 16 - safe_to_integer(glyph_width_deduct(3 downto 0));
          end if;

          if glyph_full_colour = '1' then
            if glyphs_from_hyperram='0' or (not hyper_installed) then
              -- Fetch full-colour glyph data from chip ram
              if glyph_flip_horizontal = '0' then
                glyph_data_address(2 downto 0) <= glyph_data_address(2 downto 0) + 1;
              else
                glyph_data_address(2 downto 0) <= glyph_data_address(2 downto 0) - 1;
              end if;
              full_colour_fetch_count <= 0;
              raster_fetch_state <= PaintFullColourFetch;
            else
              -- Fetch glyph data from ATTIC/CELLAR ram (hyperram)
              report "HYPERRAM: Request for $" & to_hstring(glyph_data_address(18 downto 3)&"000")
                & " dispatched.";
              full_colour_fetch_count <= 0;
              hyper_addr_drive(18 downto 3) <= glyph_data_address(18 downto 3);
              hyper_request_toggle_drive <= not last_hyper_request_toggle;
              last_hyper_request_toggle <= not last_hyper_request_toggle;
              raster_fetch_state <= PaintFullColourHyperRAMFetch;
            end if;
          else
            raster_fetch_state <= PaintMemWait3;
          end if;
        when PaintFullColourHyperRAMFetch =>
          -- Read data from dedicated hyperram interface (a bit like the VRAM
          -- that was originally planned for the Amiga Ranger chipset that was
          -- never released.
          if hyper_data_strobe='1' then
            report "VIC: Receiving hyperram byte $" & to_hstring(hyper_data)
              & ", full_colour_fetch_count = " & integer'image(full_colour_fetch_count);
            if glyph_flip_horizontal='0' then
              if glyph_visible='0' or draw_mask_blank='1' then
                full_colour_data(63 downto 56) <= "00000000";
              elsif glyph_underline='1' then
                full_colour_data(63 downto 56) <= "11111111";
              elsif glyph_reverse='1' and glyph_bold='0' then
                full_colour_data(63 downto 56) <= hyper_data xor "11111111";
              else
                full_colour_data(63 downto 56) <= hyper_data;
              end if;
              full_colour_data(55 downto 0) <= full_colour_data(63 downto 8);
            else
              if glyph_visible='0' or draw_mask_blank='1' then
                full_colour_data(7 downto 0) <= "00000000";
              elsif glyph_underline='1' then
                full_colour_data(7 downto 0) <= "11111111";
              elsif glyph_reverse='1' and glyph_bold='0' then
                full_colour_data(7 downto 0) <= hyper_data xor "11111111";
              else
                full_colour_data(7 downto 0) <= hyper_data;
              end if;
              full_colour_data(63 downto 8) <= full_colour_data(55 downto 0);
            end if;

            if full_colour_fetch_count < 7 then
              raster_fetch_state <= PaintFullColourHyperRAMFetch;
              full_colour_fetch_count <= full_colour_fetch_count + 1;
            else
              report "VIC: Received all bytes from HyperRAM. Resuming";
              raster_fetch_state <= PaintMemWait3;
            end if;

          end if;
        when PaintFullColourFetch =>
          -- Show what we are doing in debug display mode
          render_activity <= "100";

          -- Read and store the 8 bytes of data we need for a full-colour character
          report "LEGACY: glyph reading full-colour pixel value $" & to_hstring(ramdata);
          if glyph_4bit='0' or glyph_flip_horizontal='0' then
            -- Don't fly byte nybl order
            full_colour_data(63 downto 56) <= ramdata;
          else
            -- Do flip byte nybl order
            full_colour_data(63 downto 60) <= ramdata(3 downto 0);
            full_colour_data(59 downto 56) <= ramdata(7 downto 4);
          end if;
          full_colour_data(55 downto 0) <= full_colour_data(63 downto 8);
          if glyph_flip_horizontal = '0' then
            glyph_data_address(2 downto 0) <= glyph_data_address(2 downto 0) + 1;
          else
            glyph_data_address(2 downto 0) <= glyph_data_address(2 downto 0) - 1;
          end if;
          if glyph_visible='0' or draw_mask_blank='1' then
            full_colour_data(63 downto 56) <= "00000000";
          end if;
          if glyph_reverse='1' and glyph_bold='0' then
            if glyph_4bit='0' or glyph_flip_horizontal='0' then
              -- Don't flip byte nybl order
              full_colour_data(63 downto 56) <= ramdata xor "11111111";
            else
              -- Do flip byte nybl order
              full_colour_data(63 downto 60) <= ramdata(3 downto 0) xor "1111";
              full_colour_data(59 downto 56) <= ramdata(7 downto 4) xor "1111";
            end if;
          end if;
          if glyph_underline='1' then
            full_colour_data(63 downto 56) <= "11111111";
          end if;
          if full_colour_fetch_count < 7 then
            full_colour_fetch_count <= full_colour_fetch_count + 1;
            raster_fetch_state <= PaintFullColourFetch;
          else
            raster_fetch_state <= PaintMemWait3;
          end if;
        when PaintMemWait3 =>
          -- In this cycle paint_chardata and and paint_ramdata should have the
          -- requested value
          -- Abort if we have already drawn enough characters.
          character_number <= character_number + 1;
          -- We are counting the number characters, not the number of bytes, so
          -- no need multiply row width by two for 16-bit character mode
          -- if character_number = virtual_row_width_minus1(7 downto 0)&'0' then
          if character_number(10 downto 0) = display_row_width_minus1 then
            end_of_row_16 <= '1';
          else
            end_of_row_16 <= '0';
          end if;
          if character_number = '0'&display_row_width_minus1 then
            end_of_row <= '1';
          else
            end_of_row <= '0';
          end if;
          if (end_of_row = '1') or (short_line='1') then
            raster_fetch_state <= EndOfChargen;
          else
            raster_fetch_state <= PaintDispatch;
          end if;
        when PaintDispatch =>
          -- Dispatch this card for painting.

          -- Hold from dispatching if painting the previous card is not yet finished.
          if paint_ready='1' then
            paint_from_charrom <= character_data_from_rom;
            report "character rom address set to $" & to_hstring(glyph_data_address(11 downto 0)) severity note;
            -- Tell painter whether to flip horizontally or not.
            paint_flip_horizontal <= glyph_flip_horizontal;
            paint_glyph_width <= glyph_width;
            paint_blink <= glyph_blink;
            paint_glyph_4bit <= glyph_4bit;
            paint_with_alpha <= glyph_with_alpha;
            paint_alternate_palette <= glyph_reverse and glyph_bold;

            if glyph_goto='1' then

              report "DRAWMASK: PAINTING: is GOTOX";

              -- Glyph is tab-stop glyph
              -- Set screen ram buffer write address to 10 bit
              -- offset indicated by glyph number bits
              raster_buffer_write_address(9 downto 0) <= glyph_number(9 downto 0) - 1;

              if glyph_4bit='1' then
                screenline_draw_mask <= screenline_draw_mask_drive;
                report "DRAWMASK: PAINTING: Setting screenline_draw_mask to $" & to_hstring(screenline_draw_mask_drive);
              else
                screenline_draw_mask <= (others => '1');
                report "DRAWMASK: PAINTING: Ignoring drawmask. Using $ff (glyph_4bit not set)";
              end if;

              -- Allow setting of the glyph y offset in GOTO tokens
              glyph_y_offset <= to_integer(glyph_width_deduct(2 downto 0));

              -- Also note whether the glyph painting should now not paint
              -- background pixels, to allow masked over writing
              glyph_paint_background <= not glyph_flip_vertical;

              -- Allow bold + reverse on a GOTOX token to switch
              -- primary/alternate palette selection for all chars that follow
              glyph_alternate_palette_invert <= glyph_bold_and_reverse;

              -- Also allow forcing of the following characters to be
              -- background or foreground
              force_chars_foreground <= glyph_width_deduct(3);
              force_chars_background <= glyph_flip_horizontal;

            -- ... and don't paint anything, because it is just
            -- a tab stop.
            elsif glyph_full_colour='1' then
              -- Now work out exactly how we are painting
              -- Paint full-colour glyph
              report "LEGACY: Dispatching to PaintFullColour due to glyph_full_colour = 1";
              -- We set background colour to screen colour in full-colour mode
              -- for transparent pixels, and for alpha blending of anti-aliased
              -- text.  We do also support ECM mode.
              case background_colour_select is
                when "00" => paint_background <= screen_colour;
                when "01" => paint_background <= multi1_colour;
                when "10" => paint_background <= multi2_colour;
                when "11" => paint_background <= multi3_colour;
                when others => paint_background <= screen_colour;
              end case;
              -- For alpha-blended pixels, we need to make sure that we set
              -- paint_foreground from glyph_colour, which allows us to have
              -- 32 colours of anti-aliased text (using VIC-III bold attribute
              -- to provide the 5th bit), as well as the option of reversed
              -- text, which should invert the alpha-values).
              paint_foreground <= glyph_colour;
              paint_fsm_state <= PaintFullColour;
            else
              report "LEGACY: Dispatching normal due to glyph_full_colour = 0"
                & ", paint_ready=" & std_logic'image(paint_ready);
              if multicolour_mode='0' and extended_background_mode='0' then
                -- Mono mode
                if text_mode='1' then
                  paint_foreground <= glyph_colour;
                  paint_background <= screen_colour;
                else
                  paint_foreground <= bitmap_colour_foreground;
                  paint_background <= bitmap_colour_background;
                end if;
                paint_fsm_state <= PaintMono;
              elsif multicolour_mode='1' then
                -- Multicolour mode
                paint_background <= screen_colour;
                if text_mode='1' then
                  if extended_background_mode='1' then
                    -- Illegal video mode that shows all black
                    paint_background <= x"00";
                    paint_mc1 <= x"00";
                    paint_mc2 <= x"00";
                    paint_foreground <= x"00";
                  else
                    if fullcolour_mcm='1' then
                      -- multi-colour text mode with full-colour VIC III/IV feature
                      -- See #571 for more discussion on this
					  paint_foreground <= glyph_colour;
                    else
                      -- multi-colour text mode masks bit 3 of the foreground
                      -- colour to select whether the character is multi-colour or
                      -- not.
                      paint_foreground <= "00000"&glyph_colour(2 downto 0);
                    end if;
                    paint_mc1 <= multi2_colour;
                    paint_mc2 <= multi1_colour;
                  end if;
                else
                  if extended_background_mode='1' then
                    -- Illegal video mode that shows all black
                    paint_background <= x"00";
                    paint_mc1 <= x"00";
                    paint_mc2 <= x"00";
                    paint_foreground <= x"00";
                  else
                    paint_mc2 <= bitmap_colour_foreground;
                    paint_mc1 <= bitmap_colour_background;
                    paint_foreground <= glyph_colour;
                  end if;
                end if;
                if text_mode='1' and glyph_colour(3)='0' then
                  -- Multi-colour text mode only applies to colours 8-15,
                  -- so draw this glyph in mono
                  paint_fsm_state <= PaintMono;
                else
                  -- Really do low-res multi-colour
                  paint_fsm_state <= PaintMultiColour;
                end if;
              elsif extended_background_mode='1' then
                -- ECM (extended colour mode)
                if text_mode='1' then
                  paint_foreground <= glyph_colour;
                  case background_colour_select is
                    when "00" => paint_background <= screen_colour;
                    when "01" => paint_background <= multi1_colour;
                    when "10" => paint_background <= multi2_colour;
                    when "11" => paint_background <= multi3_colour;
                    when others => paint_background <= screen_colour;
                  end case;
                else
                  -- ECM + bitmap mode is illegal
                  paint_foreground <= x"00";
                  paint_background <= x"00";
                end if;
                paint_fsm_state <= PaintMono;
              end if;
            end if;
            -- Fetch next character
            raster_fetch_state <= FetchNextCharacter;
          end if;
        when EndOfChargen =>

          -- Idle the painter, and then start drawing VIC-II sprites
          if paint_ready='1' then
            paint_fsm_state <= Idle;
          end if;
          if paint_fsm_state = Idle then
            report "SPRITE: begin data fetch for raster";
            raster_fetch_state <= SpritePointerFetch;
            sprite_fetch_sprite_number <= 0;
            sprite_fetch_byte_number <= 0;
          end if;
        when SpritePointerFetch =>
          -- Show what we are doing in debug display mode
          render_activity <= "101";

          sprite_pointer_address(19 downto 17) <= "000";

          sprite_datavalid <= '0';
          if sprite_fetch_sprite_number = 16 or (sprite_fetch_sprite_number = 8 and bitplane_mode = '0') then
            -- Done fetching sprites
            raster_fetch_state <= Idle;
          elsif sprite_fetch_sprite_number < 8 then
            -- Fetch sprites
            max_sprite_fetch_byte_number <= 7;
            if vicii_sprite_pointer_address(23)='0' then
              -- Normal 8-bit sprite pointers
              sprite_pointer_address(19 downto 3) <= vicii_sprite_pointer_address(19 downto 3);
              sprite_pointer_address(2 downto 0) <=  to_unsigned(sprite_fetch_sprite_number,3);
              report "SPRITE: will fetch pointer value from $" &
                to_hstring(vicii_sprite_pointer_address(19 downto 0) + sprite_fetch_sprite_number);
            else
              -- 16-bit sprite pointers, allowing sprites to be sourced from
              -- anywhere in first 64K x 64 = 4MB of chip RAM (of which we
              -- currently have only 128KB :)
              sprite_pointer_address(19 downto 4) <= vicii_sprite_pointer_address(19 downto 4);
              sprite_pointer_address(3 downto 1) <=  to_unsigned(sprite_fetch_sprite_number,3);
              sprite_pointer_address(0) <= '0';
              report "SPRITE: will fetch pointer LSB from $" &
                to_hstring(vicii_sprite_pointer_address(19 downto 0) + sprite_fetch_sprite_number*2);
            end if;
            raster_fetch_state <= SpritePointerFetch2;
          else
            -- Fetch VIC-III bitplanes
            -- Bitplanes for odd raster lines
            -- All figures are increased by 1/3 to allow for 800 wide when required
            if (reg_h640='0' and reg_h1280='0') then
              if bitplane_sixteen_colour_mode_flags(sprite_fetch_sprite_number mod 8)='0'
              then
                -- 320px, mono bitplane = 40 bytes for 320 pixels
                max_sprite_fetch_byte_number <= 49; -- 39;
              else
                -- 320px, 16-colour bitplane = 160 bytes for 320 pixels
                max_sprite_fetch_byte_number <= 199; -- 159;
              end if;
            end if;
            if (reg_h640='1' and reg_h1280='0') then
              if bitplane_sixteen_colour_mode_flags(sprite_fetch_sprite_number mod 8)='0'
              then
                -- 320px, mono bitplane = 80 bytes for 640 pixels
                max_sprite_fetch_byte_number <= 99; -- 79;
              else
                -- 320px, 16-colour bitplane = 320 bytes for 640 pixels
                max_sprite_fetch_byte_number <= 399; -- 319;
              end if;
            end if;
            -- Don't waste time fetching bitplanes that are disabled.
            if (bitplane_enables(sprite_fetch_sprite_number mod 8)='0')
              or (bitplane_mode='0') then
              max_sprite_fetch_byte_number <= 1;
            end if;

            -- Odd bitplanes come from 2nd 64KB RAM, even bitplanes from first.
            -- But also allow shifting bitplanes higher in memory
            sprite_pointer_address(19 downto 17) <= bitplane_bank_select;
            if (sprite_fetch_sprite_number mod 2) = 0 then
              sprite_pointer_address(16) <= '0';
            else
              sprite_pointer_address(16) <= '1';
            end if;
            -- Interlacing selects which of two bitplane address register
            -- fields to use
            if (reg_v400='1') and (vicii_ycounter_v400(0)='0') then
              -- Use odd scan set
              sprite_pointer_address(15 downto 13)
                <= bitplane_addresses(sprite_fetch_sprite_number mod 8)
                (7 downto 5);
            else
              -- Use even scan set
              sprite_pointer_address(15 downto 13)
                <= bitplane_addresses(sprite_fetch_sprite_number mod 8)
                (3 downto 1);
            end if;
            -- XXX: VIC-IV should allow setting of the lower bits of the bitplane
            -- address
            sprite_pointer_address(12 downto 0) <= (others => '0');
            if bitplane_enables(sprite_fetch_sprite_number mod 8)='0' then
              -- Don't waste fetch cycles on bitplanes that are turned off
              sprite_fetch_byte_number <= 0;
              sprite_fetch_sprite_number <= sprite_fetch_sprite_number + 1;
              raster_fetch_state <= SpritePointerFetch;
            else
              --sprite_data_address <= sprite_pointer_address;
              --sprite_data_address(12 downto 0) <= to_unsigned(sprite_data_offsets(sprite_fetch_sprite_number),13);

              raster_fetch_state <= SpritePointerCompute;
            --raster_fetch_state <= SpritePointerFetch2;
            end if;
          end if;
        when SpritePointerFetch2 =>
          raster_fetch_state <= SpritePointerCompute1;
          if vicii_sprite_pointer_address(23)='1' then
            -- 16-bit sprite pointers, allowing sprites to be sourced from
            -- anywhere in first 64K x 64 = 4MB of chip RAM (of which we
            -- currently have only 384KB :)
            sprite_pointer_address(19 downto 4) <= vicii_sprite_pointer_address(19 downto 4);
            sprite_pointer_address(3 downto 1) <=  to_unsigned(sprite_fetch_sprite_number,3);
            sprite_pointer_address(0) <= '1';
            report "SPRITE: will fetch pointer MSB from $" &
              to_hstring(vicii_sprite_pointer_address(19 downto 0) + sprite_fetch_sprite_number*2);
          end if;
        when SpritePointerCompute1 =>
          -- Drive stage for ram data to improve timing closure
          raster_fetch_state <= SpritePointerCompute;
        when SpritePointerCompute =>
          -- Sprite data address is 64*pointer value, plus the 16KB bank
          -- from $DD00.  Then we need to add the data offset for this sprite.
          -- 64-pixel wide and upto 255-pixel heigh extended size sprites means
          -- we need to allow the address computation to add the sprite number
          -- from the ram data to be added to the upper bits of the
          -- sprite_data_offsets() value for the sprite
          sprite_data_address(19 downto 16) <= "0000";
          if sprite_fetch_sprite_number < 8 then
            -- But only accept the new sprite data address at the start of
            -- display of a sprite
            if sprite_continuous_pointer_monitoring='1' then
              sprite_data_address(16) <= '0';
              sprite_data_address(15) <= sprite_pointer_address(15);
              sprite_data_address(14) <= sprite_pointer_address(14);
              sprite_data_address(13 downto 0) <= (ramdata_drive&"000000") + to_unsigned(sprite_data_offsets(sprite_fetch_sprite_number),14);

              sprite_data_addresses(sprite_fetch_sprite_number)(19 downto 17) <= "000";
              sprite_data_addresses(sprite_fetch_sprite_number)(16) <= '0';
              sprite_data_addresses(sprite_fetch_sprite_number)(15) <= sprite_pointer_address(15);
              sprite_data_addresses(sprite_fetch_sprite_number)(14) <= sprite_pointer_address(14);
              sprite_data_addresses(sprite_fetch_sprite_number)(13 downto 0) <= (ramdata_drive&"000000");
            else
              if sprite_data_offsets(sprite_fetch_sprite_number) /= 0 then
                sprite_data_address <= sprite_data_addresses(sprite_fetch_sprite_number) + to_unsigned(sprite_data_offsets(sprite_fetch_sprite_number),14);
              else
                sprite_data_addresses(sprite_fetch_sprite_number)(19 downto 16) <= "0000";
                sprite_data_addresses(sprite_fetch_sprite_number)(16) <= '0';
                sprite_data_addresses(sprite_fetch_sprite_number)(15) <= sprite_pointer_address(15);
                sprite_data_addresses(sprite_fetch_sprite_number)(14) <= sprite_pointer_address(14);
                sprite_data_addresses(sprite_fetch_sprite_number)(13 downto 0) <= (ramdata_drive&"000000");

                sprite_data_address(19 downto 16) <= "0000";
                sprite_data_address(16) <= '0';
                sprite_data_address(15) <= sprite_pointer_address(15);
                sprite_data_address(14) <= sprite_pointer_address(14);
                sprite_data_address(13 downto 0) <= (ramdata_drive&"000000");
              end if;
            end if;
            -- sprite_data_address(5 downto 0) <= to_unsigned(sprite_data_offsets(sprite_fetch_sprite_number),6);
            report "SPRITE: sprite #"
              & integer'image(sprite_fetch_sprite_number)
              & " pointer value = $" & to_hstring(ramdata_drive);
          else
            -- Bitplane fetches happen here

            --sprite_data_address <= sprite_pointer_address;
            --sprite_data_address(12 downto 0) <= to_unsigned(sprite_data_offsets(sprite_fetch_sprite_number),13);
            --  sprite_data_address(16) <= '0';
            --  sprite_data_address(15) <= sprite_pointer_address(15);
            --  sprite_data_address(14) <= sprite_pointer_address(14);
            --  sprite_data_address(13 downto 0) <= (ramdata_drive&"000000") + to_unsigned(sprite_data_offsets(sprite_fetch_sprite_number),14);
            if (reg_h640='1' or reg_h1280='1') then
              sprite_data_address(19 downto 14) <= sprite_pointer_address(19 downto 14);
              sprite_data_address(13 downto 0) <= to_unsigned(sprite_data_offsets(sprite_fetch_sprite_number),14);
            else
              sprite_data_address(19 downto 13) <= sprite_pointer_address(19 downto 13);
              sprite_data_address(12 downto 0) <= to_unsigned(sprite_data_offsets(sprite_fetch_sprite_number),13);
            end if;
          end if;
          -- Get MSB if we are using 16-bit sprite pointers
          if vicii_sprite_pointer_address(23)='1' then
            raster_fetch_state <= SpritePointerComputeMSB;
          else
            raster_fetch_state <= SpriteDataFetch;
          end if;
        when SpritePointerComputeMSB =>
          -- Copy in MSB bits for sprite data address
          -- XXX It would be nice to use bit 7 to indicate to source from
          -- colour RAM, but for now we just clip to the 1MB chip RAM range
          report "SPRITE: setting upper bits of sprite data address to $" & to_hstring(ramdata_drive);
          if sprite_continuous_pointer_monitoring='1' then
            sprite_data_address <= (ramdata_drive(5 downto 0)&sprite_data_addresses(sprite_fetch_sprite_number)(13 downto 0))
                                   + to_unsigned(sprite_data_offsets(sprite_fetch_sprite_number),14);
          else
            if sprite_data_offsets(sprite_fetch_sprite_number) /= 0 then
              sprite_data_address <= sprite_data_addresses(sprite_fetch_sprite_number) + to_unsigned(sprite_data_offsets(sprite_fetch_sprite_number),14);
            else
              sprite_data_address <= sprite_data_addresses(sprite_fetch_sprite_number);
              sprite_data_address(19 downto 14) <= ramdata_drive(5 downto 0);
              sprite_data_address(13 downto 0) <= sprite_data_address(13 downto 0);
              sprite_data_addresses(sprite_fetch_sprite_number)(19 downto 14) <= ramdata_drive(5 downto 0);
              sprite_data_addresses(sprite_fetch_sprite_number)(13 downto 0) <= sprite_data_address(13 downto 0);
            end if;
          end if;
          raster_fetch_state <= SpriteDataFetch;
        when SpriteDataFetch =>
          -- Show what we are doing in debug display mode
          render_activity <= "110";

          report "SPRITE: fetching sprite #"
            & integer'image(sprite_fetch_sprite_number)
            & " data from $" & to_hstring(sprite_data_address(19 downto 0));

          if sprite_fetch_sprite_number < 8 then
            sprite_data_address(19 downto 0) <= sprite_data_address(19 downto 0) + 1;
          else
            sprite_data_address(19 downto 0) <= sprite_data_address(19 downto 0) + 8;
          end if;
          raster_fetch_state <= SpriteDataFetch2;
        when SpriteDataFetch2 =>
          report "SPRITE: fetching sprite #"
            & integer'image(sprite_fetch_sprite_number)
            & " data = $" &
            to_hstring(ramdata)
            & " from $" & to_hstring(sprite_data_address(19 downto 0))
            & " for byte number " & integer'image(sprite_fetch_byte_number);
          if sprite_fetch_sprite_number < 8 then
            sprite_data_address(19 downto 0) <= sprite_data_address(19 downto 0) + 1;
          else
            sprite_data_address(19 downto 0) <= sprite_data_address(19 downto 0) + 8;
          end if;

          -- Schedule pushing fetched sprite/bitplane byte to next cycle when
          -- the data will be available in ramdata_drive
          sprite_fetch_drive <= '1';

          sprite_fetch_byte_number_drive <= sprite_fetch_byte_number;
          sprite_fetch_sprite_number_drive <= sprite_fetch_sprite_number;

          sprite_fetch_byte_number <= sprite_fetch_byte_number + 1;


          -- XXX - always fetches 8 bytes of sprite data instead of 3, even if
          -- sprite is not set to 64 pixels wide mode. This wastes a little
          -- raster time.
          -- Bitplanes are also fetched using the sprite fetch pipeline, so we fetch
          -- more bytes for those, according to the bitplane width.
          --if ((sprite_fetch_byte_number = 7) and (sprite_fetch_sprite_number < 8))
          if (sprite_fetch_byte_number = max_sprite_fetch_byte_number)
          then
            sprite_fetch_byte_number <= 0;
            sprite_fetch_sprite_number <= sprite_fetch_sprite_number + 1;
            raster_fetch_state <= SpritePointerFetch;
          end if;
        when others => null;
      end case;

      -- Push sprite data out in a drive cycle to improve timing closure.
      if sprite_fetch_drive = '1' then
        sprite_datavalid <= '1';
        sprite_spritenumber <= sprite_fetch_sprite_number_drive;
        sprite_bytenumber <= sprite_fetch_byte_number_drive;
        sprite_data_byte <= ramdata_drive;
      end if;

      raster_buffer_write <= '0';

      -- Always write if we are using the primary or alternate palette
      raster_buffer_write_data(17) <= paint_alternate_palette xor glyph_alternate_palette_invert;

      case paint_fsm_state is
        when Idle =>
          if paint_ready /= '1' then
            paint_ready <= '1';
            report "LEGACY: asserting paint_ready" severity note;
          end if;
        when PaintFullColour =>
          -- Draw 8 pixels using a byte at a time from full_colour_data
          paint_ready <= '0';
          report "LEGACY: clearing paint_ready. full_colour_data=$" & to_hstring(full_colour_data);
          paint_full_colour_data <= full_colour_data;
          paint_bits_remaining <= paint_glyph_width - 1;
          if paint_glyph_4bit='1' then
            paint_fsm_state <= Paint4bitColourPixels;
          else
            paint_fsm_state <= PaintFullColourPixels;
          end if;
        when Paint4bitColourPixels =>
          if paint_full_colour_data(3 downto 0) = x"0" then
            -- background pixel
            raster_buffer_write_data(16 downto 9) <= x"FF";  -- solid alpha
            raster_buffer_write_data(8) <= force_chars_foreground;
            raster_buffer_write_data(7 downto 0) <= paint_background;
          else
            -- foreground pixel
            if paint_with_alpha='0' then
              report "LEGACY: full-colour glyph painting pixel $" & to_hstring(paint_full_colour_data(7 downto 0))
                & " into buffer @ $" & to_hstring(raster_buffer_write_address);
              raster_buffer_write_data(16 downto 9) <= x"FF";  -- solid alpha
              --
              raster_buffer_write_data(8) <= not force_chars_background;

              if paint_full_colour_data(3 downto 0) /= x"F" then
                -- Lower four bits of colour come from the nybl
                raster_buffer_write_data(3 downto 0) <= paint_full_colour_data(3 downto 0);
                -- Upper four from the foreground colour from screen RAM.
                -- This makes it much more useful for paralax layers etc
                raster_buffer_write_data(7 downto 4) <= paint_foreground(7 downto 4);
              else
                raster_buffer_write_data(7 downto 0) <= paint_foreground;
              end if;
            else
              -- XXX Add alternate alpha mode where alhpa value is picked by
              -- colour RAM, allowing full colour chars to be faded in and out
              -- from background?
              report "LEGACY: full-colour glyph painting alpha pixel $"
                & to_hstring(paint_foreground)
                & " with alpha value $" & to_hstring(paint_full_colour_data(3 downto 0)) & "F"
                & " : raster_buffer_write_address=$" & to_hstring(raster_buffer_write_address)
                & " ( + 1 ?)";
              -- 8-bit pixel values provide the alpha
              raster_buffer_write_data(16 downto 13) <= paint_full_colour_data(3 downto 0);
              raster_buffer_write_data(12 downto 9) <= (others => paint_full_colour_data(0));
              raster_buffer_write_data(8) <= (paint_full_colour_data(3) or force_chars_foreground) and (not force_chars_background);
              -- colour RAM colour provides the foreground
              raster_buffer_write_data(7 downto 0) <= paint_foreground;
            end if;
          end if;
          paint_full_colour_data(59 downto 0) <= paint_full_colour_data(63 downto 4);
          raster_buffer_write_address(9 downto 0) <= raster_buffer_write_address(9 downto 0) + 1;
          raster_buffer_max_write_address <= raster_buffer_write_address(9 downto 0) + 1;
          if paint_full_colour_data(3 downto 0) /= x"0" or glyph_paint_background='1' then
            raster_buffer_write <= '1';
          else
            raster_buffer_write <= '0';
          end if;
          report "LEGACY: full colour glyph paint_bits_remaining=" & integer'image(paint_bits_remaining) severity note;
          if paint_bits_remaining > 0 then
            paint_bits_remaining <= paint_bits_remaining - 1;
          else
            -- All done
            paint_fsm_state <= Idle;
          end if;
        when PaintFullColourPixels =>
          if paint_full_colour_data(7 downto 0) = x"00" then
            -- background pixel
            raster_buffer_write_data(16 downto 9) <= x"FF";  -- solid alpha
            raster_buffer_write_data(8) <= force_chars_foreground;
            raster_buffer_write_data(7 downto 0) <= paint_background;
          else
            -- foreground pixel
            if paint_with_alpha='0' then
              report "LEGACY: full-colour glyph painting pixel $" & to_hstring(paint_full_colour_data(7 downto 0))
                & " into buffer @ $" & to_hstring(raster_buffer_write_address);
              raster_buffer_write_data(16 downto 9) <= x"FF";  -- solid alpha
              raster_buffer_write_data(8) <= not force_chars_background;
              if paint_full_colour_data(7 downto 0) /= x"FF" then
                raster_buffer_write_data(7 downto 0) <= paint_full_colour_data(7 downto 0);
              else
                raster_buffer_write_data(7 downto 0) <= paint_foreground;
              end if;
            else
              -- XXX Add alternate alpha mode where alhpa value is picked by
              -- colour RAM, allowing full colour chars to be faded in and out
              -- from background?
              report "LEGACY: full-colour glyph painting alpha pixel $"
                & to_hstring(paint_foreground)
                & " with alpha value $" & to_hstring(paint_full_colour_data(7 downto 0))
                & " : raster_buffer_write_address=$" & to_hstring(raster_buffer_write_address)
                & " ( + 1 ?)";
              -- 8-bit pixel values provide the alpha
              raster_buffer_write_data(16 downto 9) <= paint_full_colour_data(7 downto 0);
              raster_buffer_write_data(8) <= (paint_full_colour_data(7) or force_chars_foreground) and (not force_chars_background);
              -- colour RAM colour provides the foreground
              raster_buffer_write_data(7 downto 0) <= paint_foreground;
            end if;
          end if;
          paint_full_colour_data(55 downto 0) <= paint_full_colour_data(63 downto 8);
          raster_buffer_write_address(9 downto 0) <= raster_buffer_write_address(9 downto 0) + 1;
          raster_buffer_max_write_address <= raster_buffer_write_address(9 downto 0) + 1;
          if glyph_paint_background='1' or paint_full_colour_data(7 downto 0) /= x"00" then
            raster_buffer_write <= '1';
          else
            raster_buffer_write <= '0';
          end if;
          report "LEGACY: full colour glyph paint_bits_remaining=" & integer'image(paint_bits_remaining) severity note;
          if paint_bits_remaining > 0 then
            paint_bits_remaining <= paint_bits_remaining - 1;
          else
            paint_fsm_state <= PaintFullColourDone;
          end if;
          if paint_bits_remaining = 0 then
            -- All done
            paint_fsm_state <= Idle;
          end if;
        when PaintFullColourDone =>
          null;
        when PaintMono =>
          -- Drive stage costs us another cycle per glyph, but seems necessary
          -- to meet timing.
          report "LEGACY: Painting mono card";
          -- Delay of paint_alternate_palette for mono is correct
          paint_alternate_palette <= glyph_reverse and glyph_bold;
          if glyph_reverse='1' and glyph_bold='0' then
            paint_buffer_hflip_chardata <= not paint_chardata;
            paint_buffer_noflip_chardata <= not (
              paint_chardata(0)&paint_chardata(1)
              &paint_chardata(2)&paint_chardata(3)
              &paint_chardata(4)&paint_chardata(5)
              &paint_chardata(6)&paint_chardata(7));
            paint_buffer_hflip_ramdata <= not paint_ramdata;
            paint_buffer_noflip_ramdata <= not (
              paint_ramdata(0)&paint_ramdata(1)
              &paint_ramdata(2)&paint_ramdata(3)
              &paint_ramdata(4)&paint_ramdata(5)
              &paint_ramdata(6)&paint_ramdata(7));
          else
            paint_buffer_hflip_chardata <= paint_chardata;
            paint_buffer_noflip_chardata <=
              paint_chardata(0)&paint_chardata(1)
              &paint_chardata(2)&paint_chardata(3)
              &paint_chardata(4)&paint_chardata(5)
              &paint_chardata(6)&paint_chardata(7);
            paint_buffer_hflip_ramdata <= paint_ramdata;
            paint_buffer_noflip_ramdata <=
              paint_ramdata(0)&paint_ramdata(1)
              &paint_ramdata(2)&paint_ramdata(3)
              &paint_ramdata(4)&paint_ramdata(5)
              &paint_ramdata(6)&paint_ramdata(7);
          end if;
          if glyph_visible='0' or draw_mask_blank='1' then
            paint_buffer_noflip_ramdata <= "00000000";
            paint_buffer_hflip_ramdata <= "00000000";
            paint_buffer_noflip_chardata <= "00000000";
            paint_buffer_hflip_chardata <= "00000000";
          end if;
          if glyph_underline='1' then
            paint_buffer_noflip_ramdata <= "11111111";
            paint_buffer_hflip_ramdata <= "11111111";
            paint_buffer_noflip_chardata <= "11111111";
            paint_buffer_hflip_chardata <= "11111111";
          end if;
          paint_fsm_state <= PaintMonoDrive;
        when PaintMonoDrive =>
          -- Paint 8 mono bits from ramdata or chardata
          -- Paint from a buffer to meet timing, even though it means we spend
          -- 9 cycles per char to paint, instead of the ideal 8.
          report "paint_flip_horizontal="&std_logic'image(paint_flip_horizontal)
            & ", paint_from_charrom=" & std_logic'image(paint_from_charrom) severity note;
          report "LEGACY: painting either $ " & to_hstring(paint_ramdata) & " or $" & to_hstring(paint_chardata) severity note;
          report "  painting from direct memory would have $ " & to_hstring(ramdata) & " or $" & to_hstring(chardata) severity note;
          if paint_flip_horizontal='1' and paint_from_charrom='1' then
            paint_buffer <= paint_buffer_hflip_chardata;
          elsif paint_flip_horizontal='0' and paint_from_charrom='1' then
            paint_buffer <= paint_buffer_noflip_chardata;
          elsif paint_flip_horizontal='1' and paint_from_charrom='0' then
            paint_buffer <= paint_buffer_hflip_ramdata;
            if paint_ramdata(0)='1' then
              raster_buffer_write_data(16 downto 9) <= x"FF";  -- solid alpha
              raster_buffer_write_data(8) <= not force_chars_background;
              raster_buffer_write_data(7 downto 0) <= paint_foreground;
            else
              raster_buffer_write_data(16 downto 9) <= x"FF";  -- solid alpha
              raster_buffer_write_data(8) <= not force_chars_foreground;
              raster_buffer_write_data(7 downto 0) <= paint_background;
            end if;
          elsif paint_flip_horizontal='0' and paint_from_charrom='0' then
            paint_buffer <= paint_buffer_noflip_ramdata;
          end if;
          paint_bits_remaining <= paint_glyph_width;
          paint_ready <= '0';
          raster_buffer_write <= '0';
          report "LEGACY: clearing paint_ready";
          paint_fsm_state <= PaintMonoBits;
        when PaintMonoBits =>
          if paint_bits_remaining = paint_glyph_width then
            report "painting card using data $" & to_hstring(paint_buffer) severity note;
          end if;
          if paint_bits_remaining /= 0 then
            report "LEGACY: Painting mono char pixel @ $" & to_hstring(raster_buffer_write_address)
              & " (" & integer'image(paint_bits_remaining) & " pixels remaining in card.)";
            paint_buffer<= '0'&paint_buffer(7 downto 1);
            raster_buffer_write_data(16 downto 9) <= x"FF";  -- solid alpha
            if paint_buffer(0)='1' then
              raster_buffer_write_data(8) <= not force_chars_background;
              raster_buffer_write_data(7 downto 0) <= paint_foreground;
              report "Painting foreground pixel in colour $" & to_hstring(paint_foreground) severity note;
            else
              raster_buffer_write_data(8) <= not force_chars_foreground;
              raster_buffer_write_data(7 downto 0) <= paint_background;
              report "Painting background pixel in colour $" & to_hstring(paint_background) severity note;
            end if;
            raster_buffer_write_address(9 downto 0) <= raster_buffer_write_address(9 downto 0) + 1;
            raster_buffer_max_write_address <= raster_buffer_write_address(9 downto 0) + 1;
            if paint_buffer(0)='1' or glyph_paint_background='1' then
              raster_buffer_write <= '1';
            else
              raster_buffer_write <= '0';
            end if;
            report "paint_bits_remaining=" & integer'image(paint_bits_remaining) severity note;
            paint_bits_remaining <= paint_bits_remaining - 1;
          end if;
          if paint_bits_remaining = 1 or paint_bits_remaining = 0 then
            paint_fsm_state <= Idle;
          end if;
        when PaintMultiColour =>
          -- Drive stage costs us another cycle per glyph, but seems necessary
          -- to meet timing.
          -- Paint_alternate_palette seems to not work in multi-colour mode
          paint_alternate_palette <= glyph_reverse and glyph_bold;
          if glyph_reverse='1' and glyph_bold='0' then
            paint_buffer_hflip_chardata <= not paint_chardata;
            paint_buffer_noflip_chardata <= not (
              paint_chardata(0)&paint_chardata(1)
              &paint_chardata(2)&paint_chardata(3)
              &paint_chardata(4)&paint_chardata(5)
              &paint_chardata(6)&paint_chardata(7));
            paint_buffer_hflip_ramdata <= not paint_ramdata;
            paint_buffer_noflip_ramdata <= not (
              paint_ramdata(0)&paint_ramdata(1)
              &paint_ramdata(2)&paint_ramdata(3)
              &paint_ramdata(4)&paint_ramdata(5)
              &paint_ramdata(6)&paint_ramdata(7));
          else
            paint_buffer_hflip_chardata <= paint_chardata;
            paint_buffer_noflip_chardata <=
              paint_chardata(0)&paint_chardata(1)
              &paint_chardata(2)&paint_chardata(3)
              &paint_chardata(4)&paint_chardata(5)
              &paint_chardata(6)&paint_chardata(7);
            paint_buffer_hflip_ramdata <= paint_ramdata;
            paint_buffer_noflip_ramdata <=
              paint_ramdata(0)&paint_ramdata(1)
              &paint_ramdata(2)&paint_ramdata(3)
              &paint_ramdata(4)&paint_ramdata(5)
              &paint_ramdata(6)&paint_ramdata(7);
          end if;
          if glyph_visible='0' or draw_mask_blank='1' then
            paint_buffer_noflip_ramdata <= "00000000";
            paint_buffer_hflip_ramdata <= "00000000";
            paint_buffer_noflip_chardata <= "00000000";
            paint_buffer_hflip_chardata <= "00000000";
          end if;
          if glyph_underline='1' then
            paint_buffer_noflip_ramdata <= "11111111";
            paint_buffer_hflip_ramdata <= "11111111";
            paint_buffer_noflip_chardata <= "11111111";
            paint_buffer_hflip_chardata <= "11111111";
          end if;

          paint_fsm_state <= PaintMultiColourDrive;
        when PaintMultiColourDrive =>
          -- Paint 4 multi-colour half-nybls from ramdata or chardata
          -- Paint from a buffer to meet timing, even though it means we spend
          -- 5 cycles per char to paint, instead of the ideal 4.
          report "paint_flip_horizontal="&std_logic'image(paint_flip_horizontal)
            & ", paint_from_charrom=" & std_logic'image(paint_from_charrom) severity note;
          if raster_buffer_write_address(9 downto 0) = 0 then
            report "painting either $ " & to_hstring(paint_ramdata) & " or $" & to_hstring(paint_chardata) severity note;
            report "  painting from direct memory would have $ " & to_hstring(ramdata) & " or $" & to_hstring(chardata) severity note;
          end if;
          if paint_flip_horizontal='1' and paint_from_charrom='1' then
            paint_buffer <= paint_buffer_hflip_chardata;
          elsif paint_flip_horizontal='0' and paint_from_charrom='1' then
            paint_buffer <= paint_buffer_noflip_chardata;
          elsif paint_flip_horizontal='1' and paint_from_charrom='0' then
            paint_buffer <= paint_buffer_hflip_ramdata;
            raster_buffer_write_data(16 downto 9) <= x"FF";  -- solid alpha
            if paint_ramdata(0)='1' then
              raster_buffer_write_data(8) <= not force_chars_background;
              raster_buffer_write_data(7 downto 0) <= paint_foreground;
            else
              raster_buffer_write_data(8) <= not force_chars_foreground;
              raster_buffer_write_data(7 downto 0) <= paint_background;
            end if;
          elsif paint_flip_horizontal='0' and paint_from_charrom='0' then
            paint_buffer <= paint_buffer_noflip_ramdata;
          end if;
          paint_bits_remaining <= (paint_glyph_width / 2);
          paint_ready <= '0';
          report "LEGACY: clearing paint_ready";
          paint_fsm_state <= PaintMultiColourBits;
        when PaintMultiColourBits =>
          if paint_bits_remaining = (paint_glyph_width / 2) then
            report "painting card using data $" & to_hstring(paint_buffer) severity note;
          end if;
          if paint_bits_remaining /= 0 then
            paint_buffer<= "00"&paint_buffer(7 downto 2);
            raster_buffer_write_data(16 downto 9) <= x"FF";  -- solid alpha
            case paint_buffer(1 downto 0) is
              when "00" =>
                raster_buffer_write_data(8) <= not force_chars_foreground;
                raster_buffer_write_data(7 downto 0) <= paint_background;
                report "Painting background pixel in colour $" & to_hstring(paint_background) severity note;
              when "01" =>
                raster_buffer_write_data(8) <= not force_chars_background;
                raster_buffer_write_data(7 downto 0) <= paint_mc1;
                report "Painting multi-colour 2 pixel in colour $" & to_hstring(paint_mc1) severity note;
              when "10" =>
                raster_buffer_write_data(8) <= not force_chars_background;
                raster_buffer_write_data(7 downto 0) <= paint_mc2;
                report "Painting multi-colour 3 pixel in colour $" & to_hstring(paint_mc2) severity note;
              when "11" =>
                raster_buffer_write_data(8) <= not force_chars_background;
                raster_buffer_write_data(7 downto 0) <= paint_foreground;
                report "Painting foreground pixel in colour $" & to_hstring(paint_foreground) severity note;
              when others =>
                null;
            end case;
            raster_buffer_write_address(9 downto 0) <= raster_buffer_write_address(9 downto 0) + 1;
            raster_buffer_max_write_address <= raster_buffer_write_address(9 downto 0) + 1;
            if paint_buffer(1 downto 0) /= "00" or glyph_paint_background='1' then
              raster_buffer_write <= '1';
            else
              raster_buffer_write <= '0';
            end if;
            report "paint_bits_remaining=" & integer'image(paint_bits_remaining) severity note;
            paint_bits_remaining <= paint_bits_remaining - 1;
          end if;
          -- Stretch multi-colour pixels to be double width
          paint_fsm_state <= PaintMultiColourHold;
        when PaintMultiColourHold =>
          raster_buffer_write_address(9 downto 0) <= raster_buffer_write_address(9 downto 0) + 1;
          raster_buffer_max_write_address <= raster_buffer_write_address(9 downto 0) + 1;
          if paint_buffer(1 downto 0) /= "00" or glyph_paint_background='1' then
            raster_buffer_write <= '1';
          else
            raster_buffer_write <= '0';
          end if;
          if paint_bits_remaining = 0 then
            paint_fsm_state <= Idle;
          else
            paint_fsm_state <= PaintMultiColourBits;
          end if;
        when others =>
          -- If we don't know what to do, just smile and nod and say we are
          -- ready again.
          paint_fsm_state <= Idle;
      end case;

      if raster_fetch_state /= Idle or paint_fsm_state /= Idle then
        report "raster_fetch_state=" & vic_chargen_fsm'image(raster_fetch_state) & ", "
          & "paint_fsm_state=" & vic_paint_fsm'image(paint_fsm_state)
          & ", rb_w_addr=$" & to_hstring(raster_buffer_write_address) severity note;
      end if;
    end if;
  end process;

  -- charaddress generation
  process(raster_fetch_state,glyph_data_address,reg_char_y16,charrow_repeated)
  begin
    if reg_char_y16 = '0' then
      charaddress <= safe_to_integer(glyph_data_address(11 downto 0));
    else
      if charrow_repeated='0' then
        charaddress <= safe_to_integer(glyph_data_address(10 downto 0));
      else
        charaddress <= 2048 + safe_to_integer(glyph_data_address(10 downto 0));
      end if;
    end if;
  --charaddress <= to_unsigned(0,12);
  --case raster_fetch_state is
  --  when FetchBitmapData =>
  --    report "setting charaddress to " & integer'image(safe_to_integer(glyph_data_address(10 downto 0)))
  --      & " for painting glyph $" & to_hstring(to_unsigned(safe_to_integer(glyph_number),16)) severity note;
  --    charaddress <= safe_to_integer(glyph_data_address(11 downto 0));
  --  when FetchTextCellColourAndSource =>
  --    -- upper bit of charrom address is set by $D018, only 258*8 = 2K
  --    -- range of address is controlled here by character number.
  --    report "setting charaddress to " & integer'image(safe_to_integer(glyph_data_address(10 downto 0)))
  --        & " for painting glyph $" & to_hstring(to_unsigned(safe_to_integer(glyph_number),16)) severity note;
  --    charaddress <= safe_to_integer(glyph_data_address(11 downto 0));
  --  when others => null;
  -- end case;
  end process;

  -- raster buffer read address/sub calculations
  -- pulled out so "next" value can be fed directly to raster buffer ram read address.
  process(raster_buffer_read_address,raster_buffer_read_address_sub,chargen_x_scale_drive,xcounter,x_chargen_start_minus1,
          reg_h640)
  begin
    raster_buffer_read_address_next <= raster_buffer_read_address;
    if xcounter = x_chargen_start_minus1 then
      -- Request first byte of pre-rendered character data
      report "raster fetch raster_buffer_read_address reset to zero at start of chargen";
      raster_buffer_read_address_next(9 downto 0) <= (others => '0');
      raster_buffer_read_address_sub_next(9 downto 0) <= (others => '0');
    else
      if reg_h640='1' then
        -- 640 wide characters use x scale directly
        if raster_buffer_read_address_sub >= 240 then
          raster_buffer_read_address_sub_next <= raster_buffer_read_address_sub - 240 + chargen_x_scale_drive;
          raster_buffer_read_address_next(9 downto 0) <= raster_buffer_read_address(9 downto 0) + 2;
        elsif raster_buffer_read_address_sub >= 120 then
          raster_buffer_read_address_sub_next <= raster_buffer_read_address_sub - 120 + chargen_x_scale_drive;
          raster_buffer_read_address_next(9 downto 0) <= raster_buffer_read_address(9 downto 0) + 1;
        else
          raster_buffer_read_address_sub_next <= raster_buffer_read_address_sub + chargen_x_scale_drive;
        end if;
      else
        -- 320 wide / 40 column text is 2x as wide, i.e., we halve the x scale
        -- factor.
        if raster_buffer_read_address_sub >= 240 then
          raster_buffer_read_address_sub_next <= raster_buffer_read_address_sub - 240 + chargen_x_scale_drive(7 downto 1);
          raster_buffer_read_address_next(9 downto 0) <= raster_buffer_read_address(9 downto 0) + 2;
        elsif raster_buffer_read_address_sub >= 120 then
          raster_buffer_read_address_sub_next <= raster_buffer_read_address_sub - 120 + chargen_x_scale_drive(7 downto 1);
          raster_buffer_read_address_next(9 downto 0) <= raster_buffer_read_address(9 downto 0) + 1;
        else
          raster_buffer_read_address_sub_next <= raster_buffer_read_address_sub + chargen_x_scale_drive(7 downto 1);
        end if;
      end if;
    end if;
  end process;

  -- ramaddress mux
  -- This is pulled out into a combinatorial section so that ramaddress changes as soon as the raster_fetch_state
  -- value changes so that it can be driven into the block ram and sampled at the next clock cycle, thus providing the
  -- expected data on the next clock as well.
  process(raster_fetch_state,this_ramaccess_is_screen_row_fetch,glyph_data_address,sprite_pointer_address,sprite_data_address,
          ramaddress,this_screen_row_fetch_address,glyph_full_colour)
  begin
    next_ramaddress <= ramaddress;

    if this_ramaccess_is_screen_row_fetch='1' then
      report "chipram fetch for screen row data from $" & to_hstring(to_unsigned(safe_to_integer(this_screen_row_fetch_address),16));
      next_ramaddress <= this_screen_row_fetch_address;
    end if;

    case raster_fetch_state is
      when FetchBitmapData =>
        -- Ask for first byte of data so that paint can commence immediately.
        report "setting ramaddress to $" & to_hstring("000"&glyph_data_address) & " for glyph painting." severity note;
        next_ramaddress <= glyph_data_address;
      when FetchTextCellColourAndSource =>
        -- Ask for first byte of data so that paint can commence immediately.
        report "setting ramaddress to $" & to_hstring("000"&glyph_data_address) & " for glyph painting." severity note;
        next_ramaddress <= glyph_data_address;
      when PaintMemWait =>
        if glyph_full_colour = '1' then
          report "setting ramaddress to $" & to_hstring(glyph_data_address) & " for full-colour glyph drawing";
          next_ramaddress <= glyph_data_address;
        end if;
      when PaintMemWait2 =>
        if glyph_full_colour = '1' then
          report "LEGACY: setting ramaddress to $" & to_hstring(glyph_data_address) & " for full-colour glyph drawing";
          next_ramaddress <= glyph_data_address;
        end if;
      when PaintFullColourFetch =>
        report "setting ramaddress to $" & to_hstring(glyph_data_address) & " for full-colour glyph drawing";
        next_ramaddress <= glyph_data_address;
      when SpritePointerFetch2 =>
        next_ramaddress <= sprite_pointer_address;
      when SpritePointerCompute1 =>
        next_ramaddress <= sprite_pointer_address;
      when SpriteDataFetch =>
        next_ramaddress <= sprite_data_address;
      when SpriteDataFetch2 =>
        next_ramaddress <= sprite_data_address;
      when others => null;
    end case;
  end process;

  process (pixelclock) is
  begin
    if rising_edge(pixelclock) then

      -- XXX Export $D031 mystery writes debug signal
      d031_written <= d031_written_internal;

      --Route out position counters for compositor
      --But delay them for the video pipeline depth.
      --1 pixel stage + 8 sprite + 8 bitplane = 17 cycles
      xcounter_out <= xcounter_pipeline_delayed;

      report "VICIV: xcounter=" & integer'image(to_integer(xcounter))
        & ", ycounter=" & integer'image(to_integer(ycounter));

      sprite_h640_delayed <= sprite_h640;
      sprite_v400s_delayed <= sprite_v400s;
      reg_h640_delayed <= reg_h640;
      reg_h1280_delayed <= reg_h1280;
      external_frame_x_zero_latched <= external_frame_x_zero;
      last_external_frame_x_zero_latched <= external_frame_x_zero_latched;

    -- ycounter we can watch for changes and count down, instead of having to have
    -- 17 copies of it
--      if ycounter /= ycounter_last then
--        ycounter_export_countdown <= 17;
--      else
--        if ycounter_export_countdown /= 0 then
--          ycounter_export_countdown <= ycounter_export_countdown - 1;
--          ycounter_out <= safe_to_integer(ycounter_last);
--          ycounter_out <= safe_to_integer(ycounter);
--        else
--        end if;
--      end if;
    end if;
  end process;

  ycounter_out <= safe_to_integer(ycounter);

end Behavioral;
