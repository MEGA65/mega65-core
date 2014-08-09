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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity viciv is
  Port (
    ----------------------------------------------------------------------
    -- dot clock
    ----------------------------------------------------------------------
    pixelclock : in  STD_LOGIC;
    ----------------------------------------------------------------------
    -- CPU clock (used for chipram and fastio interfaces)
    ----------------------------------------------------------------------
    cpuclock : in std_logic;
    ioclock : in std_logic;

    -- CPU IRQ
    irq : out std_logic;

    reset : in std_logic;

    -- Internal drive LED status for OSD
    led : in std_logic;
    motor : in std_logic;

    vicii_2mhz : out std_logic;
    viciii_fast : out std_logic;
    viciv_fast : out std_logic;     
    
    ----------------------------------------------------------------------
    -- VGA output
    ----------------------------------------------------------------------
    vsync : out  STD_LOGIC;
    hsync : out  STD_LOGIC;
    vgared : out  UNSIGNED (3 downto 0);
    vgagreen : out  UNSIGNED (3 downto 0);
    vgablue : out  UNSIGNED (3 downto 0);

    ---------------------------------------------------------------------------
    -- CPU Interface to ChipRAM in video controller (just 128KB for now)
    ---------------------------------------------------------------------------
    chipram_we : IN STD_LOGIC;
    chipram_address : IN unsigned(16 DOWNTO 0);
    chipram_datain : IN unsigned(7 DOWNTO 0);
    
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

    viciii_iomode : out std_logic_vector(1 downto 0) := "11";
    
    colourram_at_dc00 : out std_logic := '0';   
    rom_at_e000 : out std_logic;
    rom_at_c000 : out std_logic;
    rom_at_a000 : out std_logic;
    rom_at_8000 : out std_logic
    );
end viciv;

architecture Behavioral of viciv is

  component ram9x4k IS
  PORT (
    clka : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    clkb : IN STD_LOGIC;
    addrb : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
  );
  END component;

  component screen_ram_buffer IS
    PORT (
      clka : IN STD_LOGIC;
      wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
      addra : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
      dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      clkb : IN STD_LOGIC;
      addrb : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
      doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
      );
  END component;
  
  component charrom is
    port (Clk : in std_logic;
          address : in integer range 0 to 4095;
          -- Yes, we do have a write enable, because we allow modification of ROMs
          -- in the running machine, unless purposely disabled.  This gives us
          -- something like the WOM that the Amiga had.
          we : in std_logic;
          -- chip select, active high       
          cs : in std_logic;
          data_i : in std_logic_vector(7 downto 0);
          data_o : out std_logic_vector(7 downto 0)
          );
  end component charrom;

  -- 64KB internal colour RAM
  component ram8x64k IS
    PORT (
      clka : IN STD_LOGIC;
      ena : IN STD_LOGIC;
      wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
      addra : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
      dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      clkb : IN STD_LOGIC;
      web : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
      addrb : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
      dinb : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
      );
  END component;
  
  -- 128KB internal chip RAM
  component chipram8bit IS
    PORT (
      clka : IN STD_LOGIC;
      wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
      addra : IN STD_LOGIC_VECTOR(16 DOWNTO 0);
      dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      clkb : IN STD_LOGIC;
      addrb : IN STD_LOGIC_VECTOR(16 DOWNTO 0);
      doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
      );
  END component;
  
  -- 1K x 32bit ram for palette
  component ram32x1024 IS
    PORT (
      clka : IN STD_LOGIC;
      ena : IN STD_LOGIC;
      wea : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
      addra : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
      dina : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
      douta : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
      clkb : IN STD_LOGIC;
      web : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
      addrb : IN STD_LOGIC_VECTOR(9 DOWNTO 0);
      dinb : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
      doutb : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
      );
  END component;

  signal vicii_2mhz_internal : std_logic := '1';
  signal viciii_fast_internal : std_logic := '1';
  signal viciv_fast_internal : std_logic := '1';
  
  -- last value written to key register
  signal reg_key : unsigned(7 downto 0) := x"00";
  
  signal viciv_legacy_mode_registers_touched : std_logic := '0';
  signal reg_d018_screen_addr : unsigned(3 downto 0) := x"1";

  signal bump_screen_row_address : std_logic := '0';
  
  -- Drive stage for IRQ signal in attempt to allieviate timing problems.
  signal irq_drive : std_logic;
  
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
  signal vga_out_red : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_out_green : UNSIGNED (7 downto 0) := (others => '0');
  signal vga_out_blue : UNSIGNED (7 downto 0) := (others => '0');
  signal pixel_colour : unsigned(7 downto 0) := x"00";
  
  -- Video mode definition
--  constant width : integer := 1600;
--  constant height : integer := 1200;
--  
--  constant frame_width : integer := 2160;
--  constant frame_h_front : integer := 64;
--  constant frame_h_syncwidth : integer := 192;
--  
--  constant frame_height : integer := 1250;
--  constant frame_v_front : integer := 1;
--  constant frame_v_syncheight : integer := 3;

  constant width : integer := 1920;
  constant height : integer := 1200;

  -- We compare to this value, thus the minus one.  Otherwise the frame will be
  -- 2593 pixels wide, which means that the CPU:VIC clock phase will not be
  -- consistent on all raster lines, and vertical rasters/splits would have a 4
  -- pixel wide saw-tooth effect.
  constant frame_width : integer := 2592-1;
  constant frame_h_front : integer := 128;
  constant frame_h_syncwidth : integer := 208;

  -- The real mode says 1242, but we need 1248 so that 1248/312 = 4,
  -- allowing VIC-II PAL raster numbers to be easily calculated.
  constant frame_height : integer := 1248;
  constant frame_v_front : integer := 1;
  constant frame_v_syncheight : integer := 3;
  
  -- Frame generator counters
  -- DEBUG: Start frame at a point that will soon trigger a badline
  signal xcounter : unsigned(11 downto 0) := to_unsigned(frame_h_front+width-50,12);
  signal xcounter_drive : unsigned(11 downto 0) := (others => '0');
  signal ycounter : unsigned(10 downto 0) := to_unsigned(frame_v_front+frame_v_syncheight,11);
  signal ycounter_drive : unsigned(10 downto 0) := (others => '0');
  -- Virtual raster number for VIC-II
  -- (On powerup set to a PAL only raster so that ROM doesn't need to wait a
  -- whole frame.  This is really just to make testing through simulation quicker
  -- since a whole frame takes ~20 minutes to simulate).
  signal vicii_ycounter : unsigned(8 downto 0) := to_unsigned(263+1,9);
  signal vicii_ycounter_phase : unsigned(2 downto 0) := (others => '0');
  signal vicii_ycounter_max_phase : unsigned(2 downto 0) := (others => '0');
  -- Is the VIC-II virtual raster number the active one for interrupts, or
  -- are we comparing to physical rasters?  This is decided by which register
  -- gets written to last.
  signal vicii_is_raster_source : std_logic := '1';
  
  -- Actual pixel positions in the frame
  signal displayx : unsigned(11 downto 0) := (others => '0');
  signal displayx_drive : unsigned(11 downto 0) := (others => '0');
  signal displayy : unsigned(11 downto 0) := (others => '0');
  signal display_active : std_logic := '0';
  -- Mark if we are in the top line of display
  -- (used for overlaying drive LED on first row of pixels)
  signal displayline0 : std_logic := '1';
  signal displaycolumn0 : std_logic := '1';

  -- Asserted if in the 1200 vetical lines of the frame
  -- DEBUG: Power up with in frame to make simulation in ghdl much quicker.
  signal vert_in_frame : std_logic := '1';

  -- Used for counting down cycles while waiting for RAM to respond
  signal delay : std_logic_vector(1 downto 0);

  -- Interface to buffer for screen ram (converts 64 bits wide to 8 bits
  -- wide for us)
  signal screen_ram_buffer_write  : std_logic := '0';
  signal screen_ram_buffer_address : unsigned(8 downto 0);
  signal screen_ram_buffer_din : unsigned(7 downto 0);
  signal screen_ram_buffer_dout : unsigned(7 downto 0);
  
  -- Internal registers used to keep track of the screen ram for the current row
  signal screen_row_address : unsigned(16 downto 0);
  signal screen_row_current_address : unsigned(16 downto 0);
  signal screen_row_fetch_address : unsigned(16 downto 0);

  -- Internal registers for drawing a single raster of character data to the
  -- raster buffer.
  signal character_number : unsigned(8 downto 0);
  type vic_chargen_fsm is (Idle,
                           FetchScreenRamLine,
                           FetchScreenRamWait,
                           FetchScreenRamWait2,
                           FetchScreenRamNext,
                           FetchFirstCharacter,
                           FetchNextCharacter,
                           FetchCharHighByte,
                           FetchTextCell,
                           FetchTextCellColourAndSource,
                           FetchBitmapCell,
                           PaintMemWait,
                           PaintMemWait2,
                           PaintMemWait3,
                           PaintDispatch,
                           EndOfChargen);
  signal raster_fetch_state : vic_chargen_fsm := Idle;
  type vic_paint_fsm is (Idle,
                         PaintFullColour,
                         PaintMono,PaintMonoBits,
                         PaintMultiColour,PaintMultiColourBits,PaintMultiColourHold);
  signal paint_fsm_state : vic_paint_fsm := Idle;
  signal paint_ready : std_logic := '0';
  signal paint_from_charrom : std_logic;
  signal paint_flip_horizontal : std_logic;
  signal paint_foreground : unsigned(7 downto 0);
  signal paint_background : unsigned(7 downto 0);
  signal paint_mc1 : unsigned(7 downto 0);
  signal paint_mc2 : unsigned(7 downto 0);
  signal paint_buffer : unsigned(7 downto 0);
  signal paint_bits_remaining : integer range 0 to 8;
  signal paint_chardata : unsigned(7 downto 0);
  signal paint_ramdata : unsigned(7 downto 0);

  signal horizontal_smear : std_logic := '1';
  
  signal debug_x : unsigned(11 downto 0) := "111111111110";
  signal debug_y : unsigned(11 downto 0) := "111111111110";
  signal debug_screen_ram_buffer_address : unsigned(8 downto 0);
  signal debug_raster_buffer_read_address : unsigned(7 downto 0);
  signal debug_raster_buffer_write_address : unsigned(7 downto 0);
  signal debug_cycles_to_next_card : unsigned(7 downto 0);
  signal debug_char_fetch_cycle : vic_chargen_fsm;
  signal debug_chargen_active : std_logic;
  signal debug_chargen_active_soon : std_logic;
  signal debug_character_data_from_rom : std_logic;
  signal debug_charaddress : unsigned(11 downto 0);
  signal debug_charrow : std_logic_vector(7 downto 0);

  signal debug_screen_ram_buffer_address_drive : unsigned(8 downto 0);
  signal debug_cycles_to_next_card_drive : unsigned(7 downto 0);
  signal debug_char_fetch_cycle_drive : vic_chargen_fsm;
  signal debug_chargen_active_drive : std_logic;
  signal debug_chargen_active_soon_drive : std_logic;
  signal debug_character_data_from_rom_drive : std_logic;
  signal debug_charaddress_drive : unsigned(11 downto 0);
  signal debug_charrow_drive : std_logic_vector(7 downto 0);
  signal debug_raster_buffer_read_address_drive : unsigned(7 downto 0);
  signal debug_raster_buffer_write_address_drive : unsigned(7 downto 0);

  signal debug_screen_ram_buffer_address_drive2 : unsigned(8 downto 0);
  signal debug_raster_buffer_read_address_drive2 : unsigned(7 downto 0);
  signal debug_raster_buffer_write_address_drive2 : unsigned(7 downto 0);
  signal debug_cycles_to_next_card_drive2 : unsigned(7 downto 0);
  signal debug_char_fetch_cycle_drive2 : vic_chargen_fsm;
  signal debug_chargen_active_drive2 : std_logic;
  signal debug_chargen_active_soon_drive2 : std_logic;
  signal debug_character_data_from_rom_drive2 : std_logic;
  signal debug_charaddress_drive2 : unsigned(11 downto 0);
  signal debug_charrow_drive2 : std_logic_vector(7 downto 0);

  -----------------------------------------------------------------------------
  -- Video controller registers
  -----------------------------------------------------------------------------

  -- New control registers
  -- Number added to card number for each row of characters, i.e., virtual
  -- character display width.
  signal virtual_row_width : unsigned(15 downto 0) := to_unsigned(40,16);
  -- Each logical pixel will be 128/n physical pixels wide
  -- 40 columns needs 24 (=$18)
  -- 80 columns needs 48 (=$30)
  signal chargen_x_scale : unsigned(7 downto 0) := x"18";  
  -- Each character pixel will be (n+1) pixels high
  signal chargen_y_scale : unsigned(7 downto 0) := x"02";  -- x"04"
  -- smooth scrolling position in natural pixels.
  -- Set in the same way as the border
  signal x_chargen_start : unsigned(11 downto 0) := to_unsigned(frame_h_front,12);
  signal x_chargen_start_minus1 : unsigned(11 downto 0);

  -- DEBUG: Start character generator in first raster on power up to make ghdl
  -- simulation much quicker
  signal y_chargen_start : unsigned(11 downto 0) := to_unsigned(0,12);  -- 0
  -- Charset is 16bit (2 bytes per char) when this mode is enabled.
  signal sixteenbit_charset : std_logic := '0';
  -- Characters >255 are full-colour blocks when enabled.
  signal fullcolour_extendedchars : std_logic := '0';
  -- Characters <256 are full-colour blocks when enabled
  signal fullcolour_8bitchars : std_logic := '0';
  
  -- VIC-II style Mode control bits (correspond to bits in $D016 etc)
  -- -- Text/graphics mode select
  signal text_mode : std_logic := '1';
  -- -- Basic multicolour mode bit
  signal multicolour_mode : std_logic := '0';
  -- -- Extended background colour mode (reduces charset to 64 entries)
  signal extended_background_mode : std_logic := '0';
  
  -- Border dimensions
  -- DEBUG: No top or left borders on power up to make ghdl simulation of frame
  -- drawing much quicker.
  signal border_x_left : unsigned(11 downto 0) := to_unsigned(0,12);
  signal border_x_right : unsigned(11 downto 0) := to_unsigned(1920-160,12);
  signal border_y_top : unsigned(11 downto 0) := to_unsigned(0,12);
  signal border_y_bottom : unsigned(11 downto 0) := to_unsigned(1200-101,12);
  signal blank : std_logic := '0';
  -- intermediate calculations for whether we are in the border to improve timing.
  signal upper_border : std_logic := '1';
  signal lower_border : std_logic := '0';

  -- Colour registers ($D020 - $D024)
  signal screen_colour : unsigned(7 downto 0) := x"08";  -- orange
  signal border_colour : unsigned(7 downto 0) := x"04";  -- green
  signal multi1_colour : unsigned(7 downto 0) := x"01";  -- multi-colour mode #1
  signal multi2_colour : unsigned(7 downto 0) := x"02";  -- multi-colour mode #2
  signal multi3_colour : unsigned(7 downto 0) := x"03";  -- multi-colour mode #3
  signal sprite_multi0_colour : unsigned(7 downto 0) := x"04";
  signal sprite_multi1_colour : unsigned(7 downto 0) := x"05";
  type sprite_vector_8 is array(0 to 7) of unsigned(7 downto 0);
  signal sprite_x : sprite_vector_8;
  signal sprite_y : sprite_vector_8;
  signal sprite_colours : sprite_vector_8;

  -- Compatibility registers
  signal twentyfourlines : std_logic := '0';
  signal thirtyeightcolumns : std_logic := '0';
  signal vicii_raster_compare : unsigned(10 downto 0);
  signal vicii_x_smoothscroll : unsigned(2 downto 0);
  signal vicii_y_smoothscroll : unsigned(2 downto 0);
  signal vicii_sprite_enables : std_logic_vector(7 downto 0);
  signal vicii_sprite_xmsbs : std_logic_vector(7 downto 0);
  signal vicii_sprite_x_expand : std_logic_vector(7 downto 0);
  signal vicii_sprite_y_expand : std_logic_vector(7 downto 0);
  signal vicii_sprite_priorty_bits : std_logic_vector(7 downto 0);
  signal vicii_sprite_multicolour_bits : std_logic_vector(7 downto 0);
  signal vicii_sprite_sprite_colissions : std_logic_vector(7 downto 0);
  signal vicii_sprite_bitmap_colissions : std_logic_vector(7 downto 0);
  signal viciii_extended_attributes : std_logic := '1';
  signal irq_colissionspritesprite : std_logic := '0';
  signal irq_colissionspritebitmap : std_logic := '0';
  signal irq_raster : std_logic := '0';
  signal ack_colissionspritesprite : std_logic := '0';
  signal ack_colissionspritebitmap : std_logic := '0';
  signal ack_raster : std_logic := '0';
  signal mask_colissionspritesprite : std_logic := '0';
  signal mask_colissionspritebitmap : std_logic := '0';
  signal mask_raster : std_logic := '0';

  -- Used for hardware character blinking ala C65
  signal viciii_blink_phase : std_logic := '0';
  -- 60 frames = 1 second, and means no tearing.
  signal viciii_blink_phase_counter : integer range 0 to 60 := 0;

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
  -- (bits 17-27 are ignored with 128KB chipram)
  signal screen_ram_base : unsigned(27 downto 0) := x"0001000";
  -- Pointer to the VIC-II compatibility sprite source vector, usually
  -- screen+$3F8 in 40 column mode, or +$7F8 in VIC-III 80 column mode
  signal vicii_sprite_pointer_address : unsigned(27 downto 0) := x"0001000";

  -- Character set address.
  -- Size of character set depends on resolution of characters, and whether
  -- full-colour characters are enabled.
  signal character_set_address : unsigned(27 downto 0) := x"0009000";
  signal character_data_from_rom : std_logic := '1';
  -----------------------------------------------------------------------------
  
  -- Character generator state. Also used for graphics modes, since graphics
  -- modes on the C64 are all card-based, anyway.
  signal card_number : unsigned(15 downto 0) := x"0000";
  signal card_number_drive : unsigned(15 downto 0) := x"0000";
  signal card_number_is_extended : std_logic;  -- set if card_number > $00FF
  signal first_card_of_row : unsigned(15 downto 0);
  -- DEBUG: Set previous first card of row to all high so that a badline gets
  -- triggered on the first raster being drawn.
  signal prev_first_card_of_row : unsigned(15 downto 0) := (others => '1');
  -- coordinates after applying the above scaling factors
  signal chargen_x : unsigned(2 downto 0) := (others => '0');
  signal chargen_y : unsigned(2 downto 0) := (others => '0');
  -- fractional pixel position for scaling
  signal chargen_y_sub : unsigned(4 downto 0);
  signal chargen_x_sub : unsigned(4 downto 0);

  -- Common bitmap and character drawing info
  signal glyph_data_address : unsigned(16 downto 0);
  
  -- Bitmap drawing info
  signal bitmap_colour_foreground : unsigned(7 downto 0);
  signal bitmap_colour_background : unsigned(7 downto 0);

  -- Character drawing info
  signal background_colour_select : unsigned(1 downto 0);
  signal glyph_number : unsigned(11 downto 0);
  signal glyph_colour : unsigned(7 downto 0);
  signal glyph_attributes : unsigned(3 downto 0);
  signal glyph_visible : std_logic;
  signal glyph_bold : std_logic;
  signal glyph_underline : std_logic;
  signal glyph_reverse : std_logic;
  signal glyph_full_colour : std_logic;
  signal glyph_flip_horizontal : std_logic;
  signal glyph_flip_vertical : std_logic;
  
  signal card_of_row : unsigned(7 downto 0);
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
  signal cards_differ : std_logic;
  signal indisplay_t1 : std_logic := '0';
  signal indisplay_t2 : std_logic := '0';
  signal indisplay_t3 : std_logic := '0';
  signal next_card_number : unsigned(15 downto 0) := (others => '0');
  signal cycles_to_next_card : unsigned(7 downto 0);
  signal cycles_to_next_card_drive : unsigned(7 downto 0);
  
  -- Interface to character generator rom
  signal charaddress : integer range 0 to 4095;
  signal chardata : std_logic_vector(7 downto 0);
  signal chardata_drive : unsigned(7 downto 0);
  -- buffer of read data to improve timing
  signal charrow : std_logic_vector(7 downto 0);
  signal charrow_t1 : std_logic_vector(7 downto 0);
  signal charrow_t2 : std_logic_vector(7 downto 0);

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
  
  type rgb is
  record
    red   : unsigned(7 downto 0);
    green : unsigned(7 downto 0);
    blue  : unsigned(7 downto 0);
  end record;
  
  -- Border generation signals
  -- (see video registers section for the registers that define the border size)
  signal inborder : std_logic;
  signal inborder_drive : std_logic;
  signal inborder_t1 : std_logic;
  signal inborder_t2 : std_logic;
  signal xfrontporch : std_logic;
  signal xfrontporch_drive : std_logic;
  signal xbackporch : std_logic;
  signal xbackporch_edge : std_logic;

  signal last_ramaddress : unsigned(16 downto 0);
  signal ramaddress : unsigned(16 downto 0);
  signal ramdata : unsigned(7 downto 0);
  signal ramdata_drive : unsigned(7 downto 0);

  -- Precalculated mono/multicolour pixel bits
  signal multicolour_bits : std_logic_vector(1 downto 0) := (others => '0');
  signal monobit : std_logic := '0';

  -- Raster buffer
  -- Read address is in 128th of pixels
  signal raster_buffer_read_address : unsigned(18 downto 0);
  signal raster_buffer_read_data : unsigned(8 downto 0);
  signal raster_buffer_write_address : unsigned(11 downto 0);
  signal raster_buffer_write_data : unsigned(8 downto 0);
  signal raster_buffer_write : std_logic;  

  -- Colour RAM access for video controller
  signal colourramaddress : unsigned(15 downto 0);
  signal colourramdata : unsigned(7 downto 0);
  -- ... and for CPU
  signal colour_ram_fastio_address : unsigned(15 downto 0);
  
  -- Palette RAM access via fastio port
  signal palette_we : std_logic_vector(3 downto 0) := (others => '0');
  signal palette_fastio_address : std_logic_vector(9 downto 0);
  signal palette_fastio_rdata : std_logic_vector(31 downto 0);

  -- Palette RAM access for video controller
  signal palette_address : std_logic_vector(9 downto 0);
  signal palette_rdata : std_logic_vector(31 downto 0);

  -- Palette bank selection registers
  signal palette_bank_fastio : std_logic_vector(1 downto 0);
  signal palette_bank_chargen : std_logic_vector(1 downto 0);
  signal palette_bank_sprites : std_logic_vector(1 downto 0);

  signal clear_hsync : std_logic := '0';
  signal set_hsync : std_logic := '0';
  signal hsync_drive : std_logic := '0';
  signal vsync_drive : std_logic := '0';

  signal new_frame : std_logic := '0';
  
begin

  rasterbuffer1: component ram9x4k
    port map (
      clka => pixelclock,
      clkb => pixelclock,
      wea(0) => raster_buffer_write,
      dina => std_logic_vector(raster_buffer_write_data),
      unsigned(doutb) => raster_buffer_read_data,
      addra => std_logic_vector(raster_buffer_write_address),
      addrb => std_logic_vector(raster_buffer_read_address(18 downto 7))
      );
  
  buffer1: component screen_ram_buffer
    port map (
      clka => pixelclock,
      clkb => pixelclock,
      dina    => std_logic_vector(screen_ram_buffer_din),
      unsigned(doutb)   => screen_ram_buffer_dout,
      wea(0)  => screen_ram_buffer_write,
      addra  => std_logic_vector(screen_ram_buffer_address(8 downto 0)),
      addrb  => std_logic_vector(screen_ram_buffer_address(8 downto 0))
      );

  chipram0: component chipram8bit
    port map (
      -- CPU side port (write)
      clka => cpuclock,
      wea(0) => chipram_we,
      addra => std_logic_vector(chipram_address),
      dina => std_logic_vector(chipram_datain),
      -- VIC-IV side port (read)
      clkb => pixelclock,
      addrb => std_logic_vector(ramaddress),
      unsigned(doutb) => ramdata
      );
  
  colourram1 : component ram8x64k
    PORT MAP (
      clka => cpuclock,
      ena => colour_ram_cs,
      wea(0) => fastio_write,
      addra => std_logic_vector(colour_ram_fastio_address),
      dina => fastio_wdata,
      douta => colour_ram_fastio_rdata,
      -- video controller use port b of the dual-port colour ram.
      -- The CPU uses port a via the fastio interface
      clkb => pixelclock,
      web => (others => '0'),
      addrb => std_logic_vector(colourramaddress),
      dinb => (others => '0'),
      unsigned(doutb) => colourramdata
      );

  paletteram: component ram32x1024
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
  
  charrom1 : charrom
    port map (Clk => pixelclock,
              address => charaddress,
              we => '0',  -- read
              cs => '1',  -- active
              data_i => (others => '1'),
              data_o => chardata
              );

  process(cpuclock,ioclock,fastio_addr,fastio_read,chardata,
          sprite_x,sprite_y,vicii_sprite_xmsbs,ycounter,extended_background_mode,
          text_mode,blank,twentyfourlines,vicii_y_smoothscroll,displayx,displayy,
          vicii_sprite_enables,multicolour_mode,thirtyeightcolumns,
          vicii_x_smoothscroll,vicii_sprite_y_expand,screen_ram_base,
          character_set_address,irq_colissionspritebitmap,irq_colissionspritesprite,
          irq_raster,mask_colissionspritebitmap,mask_colissionspritesprite,
          mask_raster,vicii_sprite_priorty_bits,vicii_sprite_multicolour_bits,
          vicii_sprite_sprite_colissions,vicii_sprite_bitmap_colissions,
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
          debug_chargen_active,debug_char_fetch_cycle,debug_charaddress,
          debug_charrow,palette_fastio_rdata,palette_bank_chargen,
          debug_chargen_active_soon,palette_bank_sprites,
          vicii_ycounter,displayx_drive,reg_rom_e000,reg_rom_c000,
          reg_rom_a000,reg_c65_charset,reg_rom_8000,reg_palrom,
          reg_h640,reg_h1280,reg_v400,xcounter_drive,ycounter_drive,
          horizontal_smear,xfrontporch_drive,chargen_active_drive,
          inborder_drive,chargen_active_soon_drive,card_number_drive) is

    procedure viciv_interpret_legacy_mode_registers is
    begin      
      if reg_h640='0' and reg_h1280='0' then
        -- 40 column mode (5x pixels, standard side borders)
        x_chargen_start
          <= to_unsigned(frame_h_front+140+3+(to_integer(vicii_x_smoothscroll)*5),12);
        -- set horizontal borders based on 40/38 columns
        if thirtyeightcolumns='0' then
          border_x_left <= to_unsigned(140,12);
          border_x_right <= to_unsigned(1920-140-1,12);
        else  
          border_x_left <= to_unsigned(140+(7*5),12);
          border_x_right <= to_unsigned(1920-140-1-(9*5),12);
        end if;
        chargen_x_scale <= x"19";
        virtual_row_width <= to_unsigned(40,16);
      elsif reg_h640='1' and reg_h1280='0' then
        -- 80 column mode (3x pixels, no side border)
        x_chargen_start
          <= to_unsigned(frame_h_front+27+(to_integer(vicii_x_smoothscroll)*3),12);
        -- set horizontal borders based on 40/38 columns
        if thirtyeightcolumns='0' then
          border_x_left <= to_unsigned(27,12);
          border_x_right <= to_unsigned(1920-27,12);
        else  
          border_x_left <= to_unsigned(27+(7*3),12);
          border_x_right <= to_unsigned(1920-27-(9*3),12);
        end if;
        chargen_x_scale <= x"2c";
        virtual_row_width <= to_unsigned(80,16);
      elsif reg_h640='0' and reg_h1280='1' then        
        -- 160 column mode (natural pixels, fat side borders)
        x_chargen_start
          <= to_unsigned(frame_h_front+320+4
                         +(to_integer(vicii_x_smoothscroll)*1),12);
        -- set horizontal borders based on 40/38 columns
        if thirtyeightcolumns='0' then
          border_x_left <= to_unsigned(320,12);
          border_x_right <= to_unsigned(1920-320,12);
        else  
          border_x_left <= to_unsigned(320+(7*1),12);
          border_x_right <= to_unsigned(1920-320-(9*1),12);
        end if;
        chargen_x_scale <= x"80";
        virtual_row_width <= to_unsigned(160,16);
      else
        -- 240 column mode (natural pixels, no side border)
        x_chargen_start
          <= to_unsigned(frame_h_front+to_integer(vicii_x_smoothscroll)*3,12);
        -- set horizontal borders based on 40/38 columns
        if thirtyeightcolumns='0' then
          border_x_left <= to_unsigned(0,12);
          border_x_right <= to_unsigned(1920-0,12);
        else  
          border_x_left <= to_unsigned(0+(7*3),12);
          border_x_right <= to_unsigned(1920-(9*3),12);
        end if;
        virtual_row_width <= to_unsigned(240,16);
        chargen_x_scale <= x"80";
      end if;
      if reg_v400='0' then
        -- set vertical borders based on twentyfourlines
        if twentyfourlines='0' then
          border_y_top <= to_unsigned(100,12);
          border_y_bottom <= to_unsigned(1200-101,12);
        else  
          border_y_top <= to_unsigned(100+(4*5),12);
          border_y_bottom <= to_unsigned(1200-101-(4*5),12);
        end if;
        -- set y_chargen_start based on twentyfourlines
        y_chargen_start <= to_unsigned((100-3*5)+to_integer(vicii_y_smoothscroll)*5,12);
        chargen_y_scale <= x"04";
      else
        -- 400px mode
        -- set vertical borders based on twentyfourlines
        if twentyfourlines='0' then
          border_y_top <= to_unsigned(0,12);
          border_y_bottom <= to_unsigned(1200-1,12);
        else  
          border_y_top <= to_unsigned(0+(4*3),12);
          border_y_bottom <= to_unsigned(1200-1-(4*3),12);
        end if;
        -- set y_chargen_start based on twentyfourlines
        y_chargen_start <= to_unsigned((0-3*3)+to_integer(vicii_y_smoothscroll)*3,12);
        chargen_y_scale <= x"02";
      end if;

      screen_ram_base(13 downto 10) <= reg_d018_screen_addr;
      screen_ram_base(9 downto 0) <= (others => '0');
      -- Sprites fetch from screen ram base + $3F8 (or +$7F8 in VIC-III 80
      -- column mode).
      -- In 80 column mode the screen base must be on a 2K boundary on the
      -- C65, which changes the interpretation of the screen_ram_base.
      -- Behaviour for 160 and 240 column modes is undefined.
      -- Note that our interpretation of V400 to double the number of text
      -- rows breaks strict C65 compatibility.
      vicii_sprite_pointer_address(13 downto 10)
        <= reg_d018_screen_addr;
      if reg_h640='1' or reg_v400='1' then
        vicii_sprite_pointer_address(10) <= '1';
      end if;
      vicii_sprite_pointer_address(9 downto 0) <= "1111111000";

      -- All VIC-II/VIC-III compatibility modes use the first part of the
      -- colour RAM.
      colour_ram_base <= (others => '0');
      
    end procedure viciv_interpret_legacy_mode_registers;
    
    variable register_bank : unsigned(7 downto 0);
    variable register_page : unsigned(3 downto 0);
    variable register_num : unsigned(7 downto 0);
    variable register_number : unsigned(11 downto 0);
  begin
    fastio_rdata <= (others => 'Z');    

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
      
      if (register_bank=x"D0" or register_bank=x"D2") and register_page<4 then
        -- First 1KB of normal C64 IO space maps to r$0 - r$3F
        register_number(5 downto 0) := unsigned(fastio_addr(5 downto 0));        
        register_number(11 downto 6) := (others => '0');
        if fastio_addr(11 downto 0) = x"030" then
          -- C128 $D030
          register_number := x"0FF"; -- = 255
        end if;
        report "IO access resolves to video register number "
          & integer'image(to_integer(register_number)) severity note;        
      elsif (register_bank = x"D1" or register_bank = x"D3") and register_page<4 then
        register_number(11 downto 10) := "00";
        register_number(9 downto 8) := register_page(1 downto 0);
        register_number(7 downto 0) := register_num;
        report "IO access resolves to video register number "
          & integer'image(to_integer(register_number)) severity note;
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
                                        --report "read from fastio detect in video controller. " &
                                        -- "register number = " & integer'image(to_integer(register_number)) &
                                        -- ", fastio_addr = " & to_hstring(fastio_addr) &
                                        -- ", register_bank = " & to_hstring(register_bank) &
                                        -- ", register_page = " & to_hstring(register_page)
                                        --  severity note;
        if register_number>=0 and register_number<8 then
                                        -- compatibility sprite coordinates
          fastio_rdata <= std_logic_vector(sprite_x(to_integer(register_num(2 downto 0))));
        elsif register_number<16 then
                                        -- compatibility sprite coordinates
          fastio_rdata <= std_logic_vector(sprite_y(to_integer(register_num(2 downto 0))));
        elsif register_number=16 then
                                        -- compatibility sprite x position MSB
          fastio_rdata <= vicii_sprite_xmsbs;
        elsif register_number=17 then             -- $D011
          fastio_rdata(7) <= vicii_ycounter(8);  -- MSB of raster
          fastio_rdata(6) <= extended_background_mode;
          fastio_rdata(5) <= not text_mode;
          fastio_rdata(4) <= not blank;
          fastio_rdata(3) <= not twentyfourlines;
          fastio_rdata(2 downto 0) <= std_logic_vector(vicii_y_smoothscroll);
        elsif register_number=18 then          -- $D012 current raster low 8 bits
          fastio_rdata <= std_logic_vector(vicii_ycounter(7 downto 0));
        elsif register_number=19 then          -- $D013 lightpen X (coarse rasterX)
          fastio_rdata <= std_logic_vector(displayx_drive(11 downto 4));
        elsif register_number=20 then          -- $D014 lightpen Y (coarse rasterY)
          fastio_rdata <= std_logic_vector(displayy(11 downto 4));
        elsif register_number=21 then          -- $D015 compatibility sprite enable
          fastio_rdata <= vicii_sprite_enables;
        elsif register_number=22 then          -- $D016
          fastio_rdata(7) <= '1';
          fastio_rdata(6) <= '1';
          fastio_rdata(5) <= '0';       -- no reset support, since no badlines
          fastio_rdata(4) <= multicolour_mode;
          fastio_rdata(3) <= not thirtyeightcolumns;
          fastio_rdata(2 downto 0) <= std_logic_vector(vicii_x_smoothscroll);
        elsif register_number=23 then          -- $D017 compatibility sprite enable
          fastio_rdata <= vicii_sprite_y_expand;
        elsif register_number=24 then          -- $D018 compatibility RAM addresses
          fastio_rdata <=
            std_logic_vector(screen_ram_base(13 downto 10))
            & std_logic_vector(character_set_address(13 downto 10));
        elsif register_number=25 then          -- $D019 compatibility IRQ bits
          fastio_rdata(7) <= not irq_drive;
          fastio_rdata(6) <= '1';       -- NC
          fastio_rdata(5) <= '1';       -- NC
          fastio_rdata(4) <= '1';       -- NC
          fastio_rdata(3) <= '0';       -- lightpen
          fastio_rdata(2) <= irq_colissionspritesprite;
          fastio_rdata(1) <= irq_colissionspritebitmap;
          fastio_rdata(0) <= irq_raster;
        elsif register_number=26 then          -- $D01A compatibility IRQ mask bits
          fastio_rdata(7) <= '1';       -- NC
          fastio_rdata(6) <= '1';       -- NC
          fastio_rdata(5) <= '1';       -- NC
          fastio_rdata(4) <= '1';       -- NC
          fastio_rdata(3) <= '1';       -- lightpen
          fastio_rdata(2) <= mask_colissionspritesprite;
          fastio_rdata(1) <= mask_colissionspritebitmap;
          fastio_rdata(0) <= mask_raster;
        elsif register_number=27 then          -- $D01B sprite background priorty
          fastio_rdata <= vicii_sprite_priorty_bits;
        elsif register_number=28 then          -- $D01C sprite multicolour
          fastio_rdata <= vicii_sprite_multicolour_bits;
        elsif register_number=29 then          -- $D01D compatibility sprite enable
          fastio_rdata <= vicii_sprite_x_expand;
        elsif register_number=30 then          -- $D01E sprite/sprite collissions
          fastio_rdata <= vicii_sprite_sprite_colissions;
        elsif register_number=31 then          -- $D01F sprite/sprite collissions
          fastio_rdata <= vicii_sprite_bitmap_colissions;
        elsif register_number=32 then
          fastio_rdata <= std_logic_vector(border_colour);
        elsif register_number=33 then
          fastio_rdata <= std_logic_vector(screen_colour);
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
          fastio_rdata <= std_logic_vector(sprite_colours(to_integer(register_number)-39));
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
            & "0"                         -- BPM
            & reg_v400                         -- V400
            & reg_h1280                         -- H1280
            & "0"                         -- MONO
            & "1";                        -- INT(erlaced?)
          
          
                                        -- Skip $D02F - $D03F to avoid real C65/C128 programs trying to
                                        -- fiddle with registers in this range.
                                        -- NEW VIDEO REGISTERS
                                        -- ($D040 - $D047 is the same as VIC-III DAT ports on C65.
                                        --  This is tolerable, since the registers most likely used to detect a
                                        --  C65 are made non-functional.
                                        --  For more C65 register info, see:
                                        -- http://www.zimmers.net/cbmpics/cbm/c65/c65manual.txt
          -- $D032 - Bitplane enable bits
          -- $D033 - Bitplane 0 address
          -- $D034 - Bitplane 1 address
          -- $D035 - Bitplane 2 address
          -- $D036 - Bitplane 3 address
          -- $D037 - Bitplane 4 address
          -- $D038 - Bitplane 5 address
          -- $D039 - Bitplane 6 address
          -- $D03A - Bitplane 7 address
          -- $D03B - Set bits to NOT bitplane contents
          -- $D03C - Bitplane X
          -- $D03D - Bitplane Y
          -- $D03E - Horizontal position (screen verniers?)
          -- $D03F - Vertical position (screen verniers?)
          -- $D040 - $D047 DAT memory ports for bitplanes 0 through 7
          
        elsif register_number=64 then
          fastio_rdata <= std_logic_vector(virtual_row_width(7 downto 0));
        elsif register_number=65 then
          fastio_rdata <= std_logic_vector(virtual_row_width(15 downto 8));
        elsif register_number=66 then
          fastio_rdata <= std_logic_vector(chargen_x_scale);
        elsif register_number=67 then
          fastio_rdata <= std_logic_vector(chargen_y_scale);
        elsif register_number=68 then
          fastio_rdata <= std_logic_vector(border_x_left(7 downto 0));
        elsif register_number=69 then
          fastio_rdata(7 downto 4) <= x"0";
          fastio_rdata(3 downto 0) <= std_logic_vector(border_x_left(11 downto 8));
        elsif register_number=70 then
          fastio_rdata <= std_logic_vector(border_x_right(7 downto 0));
        elsif register_number=71 then
          fastio_rdata(7 downto 4) <= x"0";
          fastio_rdata(3 downto 0) <= std_logic_vector(border_x_right(11 downto 8));
        elsif register_number=72 then
          fastio_rdata <= std_logic_vector(border_y_top(7 downto 0));
        elsif register_number=73 then
          fastio_rdata(7 downto 4) <= x"0";
          fastio_rdata(3 downto 0) <= std_logic_vector(border_y_top(11 downto 8));
        elsif register_number=74 then
          fastio_rdata <= std_logic_vector(border_y_bottom(7 downto 0));
        elsif register_number=75 then
          fastio_rdata(7 downto 4) <= x"0";
          fastio_rdata(3 downto 0) <= std_logic_vector(border_y_bottom(11 downto 8));
        elsif register_number=76 then
          fastio_rdata <= std_logic_vector(x_chargen_start(7 downto 0));
        elsif register_number=77 then
          fastio_rdata(7 downto 4) <= x"0";
          fastio_rdata(3 downto 0) <= std_logic_vector(x_chargen_start(11 downto 8));
        elsif register_number=78 then
          fastio_rdata <= std_logic_vector(y_chargen_start(7 downto 0));
        elsif register_number=79 then
          fastio_rdata(7 downto 4) <= x"0";
          fastio_rdata(3 downto 0) <= std_logic_vector(y_chargen_start(11 downto 8));
        elsif register_number=80 then
          fastio_rdata <= std_logic_vector(xcounter_drive(7 downto 0));
        elsif register_number=81 then
          fastio_rdata(7 downto 4) <= x"0";
          fastio_rdata(3 downto 0) <= std_logic_vector(xcounter_drive(11 downto 8));
        elsif register_number=82 then
          fastio_rdata <= std_logic_vector(ycounter_drive(7 downto 0));
        elsif register_number=83 then
          fastio_rdata(7 downto 3) <= "00000";
          fastio_rdata(2 downto 0) <= std_logic_vector(ycounter_drive(10 downto 8));
        elsif register_number=84 then
                                        -- $D054 (53332) - New mode control register
          fastio_rdata(7 downto 4) <= (others => '1');
          fastio_rdata(6) <= viciv_fast_internal;
          fastio_rdata(3) <= horizontal_smear;
          fastio_rdata(2) <= fullcolour_extendedchars;
          fastio_rdata(1) <= fullcolour_8bitchars;
          fastio_rdata(0) <= sixteenbit_charset;
        elsif register_number=85 then
          fastio_rdata <= x"FF";
        elsif register_number=86 then
          fastio_rdata <= std_logic_vector(cycles_to_next_card_drive);
        elsif register_number=87 then
          fastio_rdata(7) <= xfrontporch_drive;
          fastio_rdata(6) <= xbackporch;
          fastio_rdata(5) <= chargen_active_drive;
          fastio_rdata(4) <= inborder_drive;
          fastio_rdata(3) <= chargen_active_soon_drive;
          fastio_rdata(2 downto 0) <= "111";
        elsif register_number=88 then
          fastio_rdata <= std_logic_vector(card_number_drive(7 downto 0));
          fastio_rdata <= x"FF";
        elsif register_number=96 then
          fastio_rdata <= std_logic_vector(screen_ram_base(7 downto 0));
        elsif register_number=97 then
          fastio_rdata <= std_logic_vector(screen_ram_base(15 downto 8));
        elsif register_number=98 then
          fastio_rdata <= std_logic_vector(screen_ram_base(23 downto 16));
        elsif register_number=99 then
          fastio_rdata(7 downto 4) <= x"0";
          fastio_rdata(3 downto 0) <= std_logic_vector(screen_ram_base(27 downto 24));
        elsif register_number=100 then
          fastio_rdata <= std_logic_vector(colour_ram_base(7 downto 0));
        elsif register_number=101 then
          fastio_rdata <= std_logic_vector(colour_ram_base(15 downto 8));
        elsif register_number=102 then
          fastio_rdata <= x"00";          -- colour_ram is 64KB block, so no bits
                                          -- 16 to 23
        elsif register_number=103 then
          fastio_rdata <= x"00";          -- colour_ram is 64KB block, so no bits
                                          -- 24 to 27
        elsif register_number=104 then  -- $D068
          fastio_rdata <= std_logic_vector(character_set_address(7 downto 0));
        elsif register_number=105 then
          fastio_rdata <= std_logic_vector(character_set_address(15 downto 8));
        elsif register_number=106 then
          fastio_rdata <= std_logic_vector(character_set_address(23 downto 16));
        elsif register_number=107 then
          fastio_rdata(7 downto 4) <= x"0";
          fastio_rdata(3 downto 0) <= std_logic_vector(character_set_address(27 downto 24));
        elsif register_number=108 then
          fastio_rdata <= std_logic_vector(vicii_sprite_pointer_address(7 downto 0));
        elsif register_number=109 then
          fastio_rdata <= std_logic_vector(vicii_sprite_pointer_address(15 downto 8));
        elsif register_number=110 then
          fastio_rdata <= std_logic_vector(vicii_sprite_pointer_address(23 downto 16));
        elsif register_number=111 then
          fastio_rdata(7 downto 4) <= x"0";
          fastio_rdata(3 downto 0) <= std_logic_vector(vicii_sprite_pointer_address(27 downto 24));
        elsif register_number=112 then -- $D3070
          fastio_rdata <= palette_bank_fastio & palette_bank_chargen & palette_bank_sprites & "11";
        elsif register_number=113 then -- $D3071
          --fastio_rdata <= std_logic_vector(x_chargen_start_minus17_drive(7 downto 0));
        elsif register_number=114 then -- $D3072
          --fastio_rdata <= "0000"&std_logic_vector(x_chargen_start_minus17_drive(11 downto 8));
        elsif register_number=115 then  -- $D3073
          fastio_rdata <= std_logic_vector(debug_raster_buffer_read_address_drive2(7 downto 0));
        elsif register_number=116 then  -- $D3074
          fastio_rdata <= std_logic_vector(debug_raster_buffer_write_address_drive2(7 downto 0));
        elsif register_number=117 then  -- $D3075
          fastio_rdata <= std_logic_vector(debug_cycles_to_next_card_drive2(7 downto 0));
        elsif register_number=118 then  -- $D3076
          fastio_rdata <= "00000" & debug_character_data_from_rom_drive2 & debug_chargen_active_drive2 & debug_chargen_active_soon_drive2;
        elsif register_number=119 then  -- $D3077
          fastio_rdata <= std_logic_vector(debug_screen_ram_buffer_address_drive2(7 downto 0));
        elsif register_number=124 then
          --fastio_rdata <=
          --  std_logic_vector(to_unsigned(vic_fetch_fsm'pos(debug_char_fetch_cycle_drive2),8));
        elsif register_number=125 then
          fastio_rdata <= std_logic_vector(debug_charaddress_drive2(7 downto 0));
        elsif register_number=126 then
          fastio_rdata <= "0000"
                          & std_logic_vector(debug_charaddress_drive2(11 downto 8));
        elsif register_number=127 then
          fastio_rdata <= debug_charrow_drive2;
        elsif register_number<256 then
                                        -- Fill in unused register space
          fastio_rdata <= (others => 'Z');
                                        -- C65 style palette registers
        elsif register_number>=256 and register_number<512 then
          -- red palette
          palette_fastio_address <= palette_bank_fastio & std_logic_vector(register_number(7 downto 0));
          fastio_rdata <= palette_fastio_rdata(31 downto 24);
        elsif register_number>=512 and register_number<768 then
          -- green palette
          palette_fastio_address <= palette_bank_fastio & std_logic_vector(register_number(7 downto 0));
          fastio_rdata <= palette_fastio_rdata(23 downto 16);
        elsif register_number>=768 and register_number<1024 then
          -- blue palette
          palette_fastio_address <= palette_bank_fastio & std_logic_vector(register_number(7 downto 0));
          fastio_rdata <= palette_fastio_rdata(15 downto 8);
        else
          fastio_rdata <= "ZZZZZZZZ";
        end if;
      end if;
    end if;
    
    if rising_edge(ioclock) then

      viciv_fast <= viciv_fast_internal;
      viciii_fast <= viciii_fast_internal;
      vicii_2mhz <= vicii_2mhz_internal;
    
      if reset='1' then
        -- Allow kickstart ROM to be visible on reset.
        rom_at_e000 <= '0';

        -- Set CPU to 48MHz
        viciv_fast_internal <= '1';
        viciii_fast_internal <= '1';
        vicii_2mhz_internal <= '1';
      end if;
      
      report "drive led = " & std_logic'image(led)
        & ", drive motor= " & std_logic'image(motor) severity note;

      debug_cycles_to_next_card_drive2 <= debug_cycles_to_next_card_drive;
      debug_chargen_active_drive2 <= debug_chargen_active_drive;
      debug_chargen_active_soon_drive2 <= debug_chargen_active_soon_drive;
      debug_char_fetch_cycle_drive2 <= debug_char_fetch_cycle_drive;
      debug_charrow_drive2 <= debug_charrow_drive;
      debug_charaddress_drive2 <= debug_charaddress_drive;
      debug_character_data_from_rom_drive2 <= debug_character_data_from_rom_drive;
      debug_screen_ram_buffer_address_drive2 <= debug_screen_ram_buffer_address_drive;
      debug_raster_buffer_read_address_drive2 <= debug_raster_buffer_read_address_drive;
      debug_raster_buffer_write_address_drive2 <= debug_raster_buffer_write_address_drive;

      inborder_drive <= inborder;
      displayx_drive <= displayx;
      chargen_active_soon_drive <= chargen_active_soon;
      cycles_to_next_card_drive <= cycles_to_next_card;
      chargen_active_drive <= chargen_active;
      xcounter_drive <= xcounter;
      ycounter_drive <= ycounter;
      xfrontporch_drive <= xfrontporch;
      
      if viciv_legacy_mode_registers_touched='1' then
        viciv_interpret_legacy_mode_registers;
        viciv_legacy_mode_registers_touched <= '0';
      end if;
      
      ack_colissionspritesprite <= '0';
      ack_colissionspritebitmap <= '0';
      ack_raster <= '0';
      
      palette_we <= (others => '0');

      -- $DD00 video bank bits
      if fastio_write='1'
        -- Fastio IO addresses D{0,1,2,3}Dx0
        and (fastio_addr(19 downto 16)=x"D")
        and (fastio_addr(11 downto  8)=x"D")
        and (fastio_addr(3 downto 0) = x"0")
        and (fastio_addr(15 downto 14) = "00")
        and (colourram_at_dc00_internal = '0')
      then
        report "Caught write to $DD00" severity note;
        screen_ram_base(15) <= not fastio_wdata(1);
        screen_ram_base(14) <= not fastio_wdata(0);
        character_set_address(15) <= not fastio_wdata(1);
        character_set_address(14) <= not fastio_wdata(0);
      end if;

      -- Reading some registers clears IRQ flags
      if fastio_read='1' then
        if register_number=30 then          -- $D01E sprite/sprite collissions
          ack_colissionspritesprite <= '1';
        elsif register_number=31 then          -- $D01F sprite/sprite collissions
          ack_colissionspritebitmap <= '1';
        end if;
      end if;
      
      -- $D000 registers
      if fastio_write='1'
        and (fastio_addr(19) = '0' or fastio_addr(19) = '1') then
        if register_number>=0 and register_number<8 then
                                        -- compatibility sprite coordinates
          sprite_x(to_integer(register_num(2 downto 0))) <= unsigned(fastio_wdata);
        elsif register_number<16 then
          sprite_y(to_integer(register_num(2 downto 0))) <= unsigned(fastio_wdata);
        elsif register_number=16 then
          vicii_sprite_xmsbs <= fastio_wdata;
        elsif register_number=17 then             -- $D011
          report "D011 WRITTEN" severity note;
          vicii_raster_compare(10 downto 8) <= "00" & fastio_wdata(7);
          vicii_is_raster_source <= '1';
          extended_background_mode <= fastio_wdata(6);
          text_mode <= not fastio_wdata(5);
          blank <= not fastio_wdata(4);
          twentyfourlines <= not fastio_wdata(3);
          vicii_y_smoothscroll <= unsigned(fastio_wdata(2 downto 0));
          viciv_legacy_mode_registers_touched <= '1';
        elsif register_number=18 then          -- $D012 current raster low 8 bits
          vicii_raster_compare(7 downto 0) <= unsigned(fastio_wdata);
          vicii_is_raster_source <= '1';
        elsif register_number=19 then          -- $D013 lightpen X (coarse rasterX)
        elsif register_number=20 then          -- $D014 lightpen Y (coarse rasterY)
        elsif register_number=21 then          -- $D015 compatibility sprite enable
          vicii_sprite_enables <= fastio_wdata;
        elsif register_number=22 then          -- $D016
          multicolour_mode <= fastio_wdata(4);
          thirtyeightcolumns <= not fastio_wdata(3);
          vicii_x_smoothscroll <= unsigned(fastio_wdata(2 downto 0));
          viciv_legacy_mode_registers_touched <= '1';
        elsif register_number=23 then          -- $D017 compatibility sprite enable
          vicii_sprite_y_expand <= fastio_wdata;
        elsif register_number=24 then          -- $D018 compatibility RAM addresses
          -- Character set source address for user-generated character sets.
          character_set_address(13 downto 11) <= unsigned(fastio_wdata(3 downto 1));
          character_set_address(10 downto 0) <= (others => '0');
          -- This one is for the internal charrom in the VIC-IV.
-- XXX          charaddress(11) <= fastio_wdata(1);
          -- Bits 14 and 15 get set by writing to $DD00, as the VIC-IV sniffs
          -- that CIA register being written on the fastio bus.
          screen_ram_base(16) <= '0';
          reg_d018_screen_addr <= unsigned(fastio_wdata(7 downto 4));
          viciv_legacy_mode_registers_touched <= '1';
        elsif register_number=25 then
          -- $D019 compatibility IRQ bits
          -- Acknowledge IRQs
          -- (we need to pass this to the dotclock side to avoide multiple drivers)
          ack_colissionspritesprite <= fastio_wdata(2);
          ack_colissionspritebitmap <= fastio_wdata(1);
          ack_raster <= fastio_wdata(0);
        elsif register_number=26 then   -- $D01A compatibility IRQ mask bits
                                        -- XXX Enable/disable IRQs
          mask_colissionspritesprite <= fastio_wdata(2);
          mask_colissionspritebitmap <= fastio_wdata(1);
          mask_raster <= fastio_wdata(0);
        elsif register_number=27 then          -- $D01B sprite background priorty
          vicii_sprite_priorty_bits <= fastio_wdata;
        elsif register_number=28 then          -- $D01C sprite multicolour
          vicii_sprite_multicolour_bits <= fastio_wdata;
        elsif register_number=29 then          -- $D01D compatibility sprite enable
          vicii_sprite_x_expand <= fastio_wdata;
        elsif register_number=30 then          -- $D01E sprite/sprite collissions
          vicii_sprite_sprite_colissions <= fastio_wdata;
        elsif register_number=31 then          -- $D01F sprite/sprite collissions
          vicii_sprite_bitmap_colissions <= fastio_wdata;
        elsif register_number=32 then
          if (register_bank=x"D0" or register_bank=x"D2") then
            border_colour(3 downto 0) <= unsigned(fastio_wdata(3 downto 0));
          else
            border_colour <= unsigned(fastio_wdata);
          end if;
        elsif register_number=33 then
          if (register_bank=x"D0" or register_bank=x"D2") then
            screen_colour(3 downto 0) <= unsigned(fastio_wdata(3 downto 0));
          else
            screen_colour <= unsigned(fastio_wdata);
          end if;
        elsif register_number=34 then
          if (register_bank=x"D0" or register_bank=x"D2") then
            multi1_colour <= unsigned("0000"&fastio_wdata(3 downto 0));
          else
            multi1_colour <= unsigned(fastio_wdata);
          end if;
        elsif register_number=35 then
          if (register_bank=x"D0" or register_bank=x"D2") then
            multi2_colour <= unsigned("0000"&fastio_wdata(3 downto 0));
          else
            multi2_colour <= unsigned(fastio_wdata);
          end if;
        elsif register_number=36 then
          if (register_bank=x"D0" or register_bank=x"D2") then
            multi3_colour <= unsigned("0000"&fastio_wdata(3 downto 0));
          else
            multi3_colour <= unsigned(fastio_wdata);
          end if;
        elsif register_number=37 then
          sprite_multi0_colour <= unsigned(fastio_wdata);
        elsif register_number=38 then
          sprite_multi1_colour <= unsigned(fastio_wdata);
        elsif register_number>=39 and register_number<=46 then
          sprite_colours(to_integer(register_number)-39) <= unsigned(fastio_wdata);
                                        -- Skip $D02F - $D03F to avoid real C65/C128 programs trying to
                                        -- fiddle with registers in this range.
                                        -- NEW VIDEO REGISTERS
                                        -- ($D040 - $D047 is the same as VIC-III DAT ports on C65.
                                        --  This is tolerable, since the registers most likely used to detect a
                                        --  C65 are made non-functional.  See:
                                        -- http://www.devili.iki.fi/Computers/Commodore/C65/System_Specification/Chapter_2/page101.html
                                        -- http://www.devili.iki.fi/Computers/Commodore/C65/System_Specification/Chapter_2/page102.html
        elsif register_number=47 then
          -- C65 VIC-III KEY register for unlocking extended registers.
          viciii_iomode <= "00"; -- by default go back to VIC-II mode
          if reg_key=x"a5" then
            if fastio_wdata=x"96" then
              -- C65 VIC-III mode
              viciii_iomode <= "01";
            end if;
          elsif reg_key=x"47" then
            if fastio_wdata=x"53" then
              -- C65GS VIC-IV mode
              viciii_iomode <= "11";
            end if;
          end if;
          reg_key <= unsigned(fastio_wdata);
        elsif register_number=255 then
          -- C128 $D030 emulation (2MHz mode only)
          vicii_2mhz_internal <= fastio_wdata(0);
        elsif register_number=48 then
          -- C65 VIC-III Control A Register $D030
          -- Mapping of C65 ROM in various places
          rom_at_e000 <= fastio_wdata(7);
          reg_rom_e000 <= fastio_wdata(7);
          -- Select between C64 and C65 charset.
          reg_c65_charset <= fastio_wdata(6);
          rom_at_c000 <= fastio_wdata(5);
          reg_rom_c000 <= fastio_wdata(5);
          rom_at_a000 <= fastio_wdata(4);
          reg_rom_a000 <= fastio_wdata(4);
          rom_at_8000 <= fastio_wdata(3);
          reg_rom_8000 <= fastio_wdata(3);
          -- PALETTE ROM entries for colours 0 - 15
          reg_palrom <= fastio_wdata(2);
          -- EXT SYNC
          -- CRAM @ DC00
          colourram_at_dc00_internal<= fastio_wdata(0);
          colourram_at_dc00<= fastio_wdata(0);
        elsif register_number=49 then 
          -- C65 VIC-III Control A Register $D031
          -- H640
          reg_h640 <= fastio_wdata(7);
          -- FAST
          viciii_fast_internal <= fastio_wdata(6);
          -- ATTR (8bit colour RAM features)
          -- BPM
          -- V400
          reg_v400 <= fastio_wdata(3);
          -- H1280
          reg_h1280 <= fastio_wdata(2);
          -- MONO
          -- INT(erlaced?)
          viciii_extended_attributes <= fastio_wdata(5);
          viciv_legacy_mode_registers_touched <= '1';
        elsif register_number=64 then
          virtual_row_width(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=65 then
          virtual_row_width(15 downto 8) <= unsigned(fastio_wdata);
        elsif register_number=66 then
          chargen_x_scale <= unsigned(fastio_wdata);
        elsif register_number=67 then
          chargen_y_scale <= unsigned(fastio_wdata);
        elsif register_number=68 then
          border_x_left(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=69 then
          border_x_left(11 downto 8) <= unsigned(fastio_wdata(3 downto 0));
        elsif register_number=70 then
          border_x_right(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=71 then
          border_x_right(11 downto 8) <= unsigned(fastio_wdata(3 downto 0)); 
        elsif register_number=72 then
          border_y_top(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=73 then
          border_y_top(11 downto 8) <= unsigned(fastio_wdata(3 downto 0)); 
        elsif register_number=74 then
          border_y_bottom(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=75 then
          border_y_bottom(11 downto 8) <= unsigned(fastio_wdata(3 downto 0));
        elsif register_number=76 then
          x_chargen_start(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=77 then
          x_chargen_start(11 downto 8) <= unsigned(fastio_wdata(3 downto 0));
        elsif register_number=78 then
          y_chargen_start(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=79 then
          y_chargen_start(11 downto 8) <= unsigned(fastio_wdata(3 downto 0)); 
        elsif register_number=80 then
                                        -- xcounter
          null;
        elsif register_number=81 then
                                        -- xcounter
          null;
        elsif register_number=82 then
          -- Allow setting of fine raster for IRQ (low bits)
          vicii_raster_compare(7 downto 0) <= unsigned(fastio_wdata);
          vicii_is_raster_source <= '0';
        elsif register_number=83 then
          -- Allow setting of fine raster for IRQ (high bits)
          vicii_raster_compare(10 downto 8) <= unsigned(fastio_wdata(2 downto 0));
          vicii_is_raster_source <= '0';
        elsif register_number=84 then
                                        -- $D054 (53332) - New mode control register
          viciv_fast_internal <= fastio_wdata(6);
          horizontal_smear <= fastio_wdata(3);
          fullcolour_extendedchars <= fastio_wdata(2);
          fullcolour_8bitchars <= fastio_wdata(1);
          sixteenbit_charset <= fastio_wdata(0);
        elsif register_number=96 then
          screen_ram_base(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=97 then
          screen_ram_base(15 downto 8) <= unsigned(fastio_wdata);
        elsif register_number=98 then
          screen_ram_base(23 downto 16) <= unsigned(fastio_wdata);
        elsif register_number=99 then
          screen_ram_base(27 downto 24) <= unsigned(fastio_wdata(3 downto 0));
        elsif register_number=100 then
          colour_ram_base(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=101 then
          colour_ram_base(15 downto 8) <= unsigned(fastio_wdata);
        elsif register_number=102 then
          null;
        elsif register_number=103 then
          null;
        elsif register_number=104 then
          character_set_address(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=105 then
          character_set_address(15 downto 8) <= unsigned(fastio_wdata);
        elsif register_number=106 then
          character_set_address(23 downto 16) <= unsigned(fastio_wdata);
        elsif register_number=107 then
          character_set_address(27 downto 24) <= unsigned(fastio_wdata(3 downto 0));
        elsif register_number=108 then
          vicii_sprite_pointer_address(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=109 then
          vicii_sprite_pointer_address(15 downto 8) <= unsigned(fastio_wdata);
        elsif register_number=110 then
          vicii_sprite_pointer_address(23 downto 16) <= unsigned(fastio_wdata);
        elsif register_number=111 then
          vicii_sprite_pointer_address(27 downto 24) <= unsigned(fastio_wdata(3 downto 0));
        elsif register_number=112 then
          palette_bank_fastio <= fastio_wdata(7 downto 6);
          palette_bank_chargen <= fastio_wdata(5 downto 4);
          palette_bank_sprites <= fastio_wdata(3 downto 2);
        elsif register_number=124 then
          debug_x(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=125 then
          debug_x(11 downto 8) <= unsigned(fastio_wdata(3 downto 0));
        elsif register_number=126 then
          debug_y(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=127 then
          debug_y(11 downto 8) <= unsigned(fastio_wdata(3 downto 0));
        elsif register_number<255 then
          -- reserved register, FDC and RAM expansion controller
          null;
        elsif register_number>=256 and register_number<512 then
          -- red palette
          palette_fastio_address <= palette_bank_fastio & std_logic_vector(register_number(7 downto 0));
          palette_we(3) <= '1';
        elsif register_number>=512 and register_number<768 then
          -- green palette
          palette_fastio_address <= palette_bank_fastio & std_logic_vector(register_number(7 downto 0));
          palette_we(2) <= '1';
        elsif register_number>=768 and register_number<1024 then
          -- blue palette
          palette_fastio_address <= palette_bank_fastio & std_logic_vector(register_number(7 downto 0));
          palette_we(1) <= '1';
        else
          null;
        end if;
      end if;      
    end if;

  end process;
  
  process(pixelclock) is
    variable indisplay : std_logic := '0';
    variable card_bg_colour : unsigned(7 downto 0) := (others => '0');
    variable card_fg_colour : unsigned(7 downto 0) := (others => '0');
    variable long_address : unsigned(31 downto 0) := (others => '0');
    variable next_glyph_number_temp : std_logic_vector(11 downto 0) := (others => '0');
    variable next_glyph_colour_temp : std_logic_vector(7 downto 0) := (others => '0');
  begin    
    if rising_edge(pixelclock) then

      --chardata_drive <= unsigned(chardata);
      --paint_chardata <= chardata_drive;
      paint_chardata <= unsigned(chardata);
      ramdata_drive <= ramdata;
      paint_ramdata <= ramdata_drive;

      -- Acknowledge IRQs after reading $D019
      irq_raster <= irq_raster and (not ack_raster);
      irq_colissionspritebitmap <= irq_colissionspritebitmap and (not ack_colissionspritebitmap);
      irq_colissionspritesprite <= irq_colissionspritesprite and (not ack_colissionspritesprite);
      -- Set IRQ line status to CPU
      irq_drive <= not ((irq_raster and mask_raster)
                        or (irq_colissionspritebitmap and mask_colissionspritebitmap)
                        or (irq_colissionspritesprite and mask_colissionspritesprite));
      if irq_drive = '0' then
        irq <= '0';
      else
        irq <= 'Z';
      end if;
      
      -- Hsync has trouble meeting timing, so I have spread out the control
      -- over 3 cycles, including one pure drive cycle, which should hopefully
      -- fix it once and for all.
      if xcounter=(frame_h_front+width) then
        clear_hsync <= '1';
      else
        clear_hsync <= '0';
      end if;
      if xcounter=(frame_h_front+width+frame_h_syncwidth) then
        set_hsync <= '1';
      else
        set_hsync <= '0';
      end if;
      if clear_hsync='1' then
        hsync_drive <= '0';
      elsif set_hsync='1' then
        hsync_drive <= '1';
      end if;
      hsync <= hsync_drive;

      new_frame <= '0';
      if new_frame='1' then
        -- C65/VIC-III style 1Hz blink attribute clock
        viciii_blink_phase_counter <= viciii_blink_phase_counter + 1;
        if viciii_blink_phase_counter = 60 then
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
      if xcounter<frame_width then
        xcounter <= xcounter + 1;
      else
        -- End of raster reached.
        -- Bump raster number and start next raster.
        xcounter <= (others => '0');
        chargen_x_sub <= (others => '0');
        raster_buffer_read_address <= (others => '0');
        chargen_active <= '0';
        chargen_active_soon <= '0';        
        if ycounter<frame_height then
          ycounter <= ycounter + 1;
          if vicii_ycounter_phase = vicii_ycounter_max_phase then
            vicii_ycounter <= vicii_ycounter + 1;
            vicii_ycounter_phase <= (others => '0');
            -- Set number of physical rasters per VIC-II raster based on region
            -- of screen.
            if vicii_ycounter = 50 then
              vicii_ycounter_max_phase <= to_unsigned(4,3);
            elsif vicii_ycounter = 250 then
              vicii_ycounter_max_phase <= to_unsigned(0,3);
            elsif vicii_ycounter = 312 then
              vicii_ycounter_max_phase <= to_unsigned(1,3);
            end if;
          else
            -- In the middle of a VIC-II logical raster, so just increase phase.
            vicii_ycounter_phase <= vicii_ycounter_phase + 1;
          end if;
          
          if (vicii_is_raster_source='0') and (ycounter = vicii_raster_compare) then
            irq_raster <= '1';
          end if;
          if (vicii_is_raster_source='1') and (vicii_ycounter = vicii_raster_compare(8 downto 0)) then
            irq_raster <= '1';
          end if;
        else
          -- Start of next frame
          ycounter <= (others =>'0');
          chargen_y_sub <= (others => '0');
          next_card_number <= (others => '0');
          first_card_of_row <= (others => '0');

          -- In top border VIC-II rasters are 2 physical rasters high
          vicii_ycounter <= (others =>'0');
          vicii_ycounter_phase <= (others => '0');
          vicii_ycounter_max_phase <= to_unsigned(1,3);  -- 0 -- 1 = 2 values         
          new_frame <= '1';
        end if;	
      end if;
      if xcounter<frame_h_front then
        xfrontporch <= '1';
        displayx <= (others => '0');
      else
        xfrontporch <= '0';
      end if;
      -- Work out when the horizonal back porch starts.
      -- The edge is used to trigger drawing of the next raster into the raster
      -- buffer.
      if xcounter<(frame_h_front+width) then
        xbackporch <= '0';
        xbackporch_edge <= '0';
      else
        xbackporch <= '1';
        xbackporch_edge <= not xbackporch;
        displayx <= (others => '1');
      end if;

      if xfrontporch='0' and xbackporch = '0' then
        -- Increase horizonal physical pixel position
        displayx <= displayx + 1;
      end if;
      
      -- Work out if the border is active
      inborder_t1 <= inborder;
      inborder_t2 <= inborder_t1;
      if displayy>border_y_bottom then
        lower_border <= '1';
      else
        lower_border <= '0';
      end if;
      if displayy<border_y_top then
        upper_border <= '1';
      else
        upper_border <= '0';
      end if;
      if displayx<border_x_left or displayx>border_x_right or
        upper_border='1' or lower_border='1' then
        inborder<='1';
        -- Fix 2 pixel gap at right of text display.
        -- (presumably it was video pipeline interaction to blame)
        inborder_t1 <= '1';
        inborder_t2 <= '1';
      else
        inborder<='0';
      end if;

      if xfrontporch='1' or xbackporch='1' then
        indisplay := '0';
        report "clearing indisplay because of horizontal porch" severity note;
      end if;

      -- Stop drawing characters when we reach the end of the prepared data
      if raster_buffer_read_address(18 downto 7) > raster_buffer_write_address then
        report "stopping character generator due to buffer exhaustion"
          severity note;
        chargen_active <= '0';
        chargen_active_soon <= '0';
      end if;
      
      -- Update current horizontal sub-pixel and pixel position
      -- Work out if a new logical pixel starts on the next physical pixel
      -- (overrides general advance).
      raster_buffer_read_address <= raster_buffer_read_address + chargen_x_scale;

      report "chargen_active=" & std_logic'image(chargen_active)
        & ", xcounter = " & to_string(std_logic_vector(xcounter))
        & ", x_chargen_start = " & to_string(std_logic_vector(x_chargen_start)) severity note;
      if displayx=border_x_right then
        -- Stop character generator as soon as we hit the right border
        -- so that we can switch to fetching sprite data for the next raster.
        report "Masking chargen_active based on displayx<border_x_right" severity note;
        chargen_active <= '0';
        chargen_active_soon <= '0';
      end if;
      x_chargen_start_minus1 <= x_chargen_start - 1;
      if xcounter = x_chargen_start_minus1 then
        -- trigger next card at start of chargen row
        chargen_x <= (others => '0');
        chargen_x_sub <= (others => '0');
        report "reset chargen_x" severity note;
        -- Request first byte of pre-rendered character data
        raster_buffer_read_address <= (others => '0');
      end if;
      if xcounter = x_chargen_start then
        -- Gets masked to 0 below if displayy is above y_chargen_start
        chargen_active <= '1';
        report "Setting chargen_active based on xcounter = x_chargen_start" severity note;
        chargen_active_soon <= '0';
      end if;
      if displayy<y_chargen_start then
        chargen_y <= (others => '0');
        chargen_y_sub <= (others => '0');
        chargen_active <= '0';
        chargen_active_soon <= '0';
        -- Force badline so that moving chargen down results in fresh loading
        -- of the first line of text.
        prev_first_card_of_row <= (others => '1');
        report "Masking chargen_active based on displayy<y_chargen_start" severity note;
        
      end if;
      if displayy=y_chargen_start then
        chargen_y <= (others => '0');
        chargen_y_sub <= (others => '0');
      end if;

      if ycounter=frame_v_front then
        vert_in_frame <= '1';
      end if;
      if ycounter=(frame_v_front+height) then
        vsync_drive <= '1';
        vert_in_frame <= '0';
      end if;
      if ycounter=(frame_v_front+height+frame_v_syncheight) then
        vsync_drive <= '0';
      end if;
      vsync <= vsync_drive;

      if displayx(4)='1' then
        displaycolumn0 <= '0';
      end if;
      if xcounter = 0 then
        displaycolumn0 <= '1';
        if vert_in_frame='0' then
          displayy <= (others => '0');
          displayline0 <= '1';
          indisplay := '0';
          report "clearing indisplay because xcounter=0" severity note;
          first_card_of_row <= x"0000";
          screen_row_address <= screen_ram_base(16 downto 0);
        else
          displayy <= displayy + 1;
          if displayy(4)='1' then
            displayline0 <= '0';            
          end if;

          -- Next line of display.  Reset card number and start address of
          -- screen ram for the row of characters currently being displayed.
          -- (this gets overriden below if crossing from one character row to
          -- another.  This also gives us the hope of implementing DMA delay,
          -- since that is such a common C64 VIC-II trick.)
          next_card_number <= first_card_of_row;
          screen_row_current_address <= screen_row_address;

          -- Now check if we have tipped over from one logical pixel row to another. 
          if chargen_y_sub=chargen_y_scale then
            chargen_y <= chargen_y + 1;
            report "bumping chargen_y to " & integer'image(to_integer(chargen_y)) severity note;
            if chargen_y = "111" then
              bump_screen_row_address<='1';
            end if;
            chargen_y_sub <= (others => '0');
          else
            chargen_y_sub <= chargen_y_sub + 1;
          end if;
        end if;
      end if;

      if bump_screen_row_address='1' then
        bump_screen_row_address <= '0';

        -- Compute the address for the screen row.
        screen_row_address <= screen_ram_base(16 downto 0) + first_card_of_row;

        -- Increment card number every "bad line"
        first_card_of_row <= to_unsigned(to_integer(first_card_of_row) + to_integer(virtual_row_width),16);
        -- Similarly update the colour ram fetch address
        colourramaddress <= to_unsigned(to_integer(colour_ram_base) + to_integer(first_card_of_row),16);
      end if;
      
      display_active <= indisplay;
      
      if indisplay_t3='1' then
        if inborder_t2='1' or blank='1' then
          pixel_colour <= border_colour;
          report "VICIV: Drawing border" severity note;
        elsif chargen_active='0' then
          pixel_colour <= screen_colour;
          report "VICIV: no character pixel data as chargen_active=0" severity note;
        else
          -- Otherwise read pixel data from raster buffer
          report "VICIV: rb_read_address = $" & to_hstring(raster_buffer_read_address(18 downto 7))
            & ", data = $" & to_hstring(raster_buffer_read_data(7 downto 0)) severity note;
          pixel_colour <= raster_buffer_read_data(7 downto 0);
          -- XXX 9th bit indicates foreground for sprite collission handling
        end if;
      else
        pixel_colour <= x"00";
        report "VICIV: Outside of frame" severity note;
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
      debug_char_fetch_cycle_drive <= debug_char_fetch_cycle;
      debug_charrow_drive <= debug_charrow;
      debug_charaddress_drive <= debug_charaddress;
      debug_character_data_from_rom_drive <= debug_character_data_from_rom;
      debug_screen_ram_buffer_address_drive <= debug_screen_ram_buffer_address;
      debug_raster_buffer_read_address_drive <= debug_raster_buffer_read_address;
      debug_raster_buffer_write_address_drive <= debug_raster_buffer_write_address;

      -- Actually, we use two drive stages since the video timing is so pernickety.
      -- The 2nd drive stage is driven by the ioclock. Search for _drive2 to
      -- find it.
      
      if xcounter=debug_x and ycounter=debug_y then
        debug_cycles_to_next_card <= cycles_to_next_card;
        debug_chargen_active <= chargen_active;
        debug_chargen_active_soon <= chargen_active_soon;
--        debug_char_fetch_cycle <= char_fetch_cycle;
        debug_charrow <= charrow;
--        debug_charaddress <= charaddress;
        debug_character_data_from_rom <= character_data_from_rom;
        debug_screen_ram_buffer_address <= screen_ram_buffer_address;
        debug_raster_buffer_read_address <= raster_buffer_read_address(7 downto 0);
        debug_raster_buffer_write_address <= raster_buffer_write_address(7 downto 0);
      end if;     
      if xcounter=debug_x or ycounter=debug_y then
        -- Draw cross-hairs at debug coordinates
        pixel_colour <= x"02";
      end if;     
      
      -- Pixels have a two cycle pipeline to help keep timing contraints:

      report "PIXEL (" & integer'image(to_integer(displayx)) & "," & integer'image(to_integer(displayy)) & ") = $"
        & to_hstring(pixel_colour)
        & ", RGBA = $" &to_hstring(palette_rdata)
        severity note;
      
      -- 1. From pixel colour lookup RGB
      -- XXX Doesn't select sprite palette bank when appropriate.

      -- Use palette bank 3 for "palette ROM" colours (C64 default colours
      -- should be placed there for C65 compatibility).
      if pixel_colour(7 downto 4) = x"0" and reg_palrom='1' then
        palette_address <= "11" & std_logic_vector(pixel_colour);
      else
        palette_address <= palette_bank_chargen & std_logic_vector(pixel_colour);        
      end if;
      vga_buffer_red <= unsigned(palette_rdata(31 downto 24));
      vga_buffer_green <= unsigned(palette_rdata(23 downto 16));
      vga_buffer_blue <= unsigned(palette_rdata(15 downto 8));      
      
      vga_buffer2_red <= vga_buffer_red;
      vga_buffer2_green <= vga_buffer_green;
      vga_buffer2_blue <= vga_buffer_blue;

      vga_buffer3_red <= vga_buffer2_red;
      vga_buffer3_green <= vga_buffer2_green;
      vga_buffer3_blue <= vga_buffer2_blue;

      if horizontal_smear='0' then
        vga_out_red <= vga_buffer3_red;
        vga_out_green <= vga_buffer3_green;
        vga_out_blue <= vga_buffer3_blue;
      else
        vga_out_red <= to_unsigned(to_integer('0'&vga_buffer3_red(7 downto 1))+to_integer('0'&vga_buffer2_red(7 downto 1)),8);
        vga_out_green <= to_unsigned(to_integer('0'&vga_buffer3_green(7 downto 1))+to_integer('0'&vga_buffer2_green(7 downto 1)),8);
        vga_out_blue <= to_unsigned(to_integer('0'&vga_buffer3_blue(7 downto 1))+to_integer('0'&vga_buffer2_blue(7 downto 1)),8);
      end if;
      
      -- 2. From RGB, push out to pins (also draw border)
      -- Note that for C65 compatability the low nybl has the most significant
      -- bits.
      if (displayline0 ='1') and (displaycolumn0='1')
        and (((led='1') and (drive_blink_phase='1'))
             or (motor='1')) then
        report "drawing drive led OSD" severity note;
        vgared <= x"F";
        vgagreen <= x"0";
        vgablue <= x"0";
      else
        vgared <= vga_out_red(3 downto 0);
        vgagreen <= vga_out_green(3 downto 0);
        vgablue <= vga_out_blue(3 downto 0);
      end if;

      --------------------------------------------------------------------------
      --------------------------------------------------------------------------
      --------------------------------------------------------------------------
      -- Character/bitmap data preparation
      --------------------------------------------------------------------------
      --------------------------------------------------------------------------
      --------------------------------------------------------------------------

      if xbackporch_edge='1' then
        -- Start of filling raster buffer.
        -- We don't need to double-buffer, as we start filling from the back
        -- porch of the previous line, hundreds of cycles before the start of
        -- the next line of display.

        -- Some house keeping first:
        -- Reset write address in raster buffer
        raster_buffer_write_address <= (others => '1');
        -- Work out colour ram address
        colourramaddress <= colour_ram_base + first_card_of_row;
        -- Work out the screen ram address.  We only need to re-fetch screen
        -- RAM if first_card_of_row is different to last time.
        prev_first_card_of_row <= first_card_of_row;

        -- Set all signals for both eventuality, since none are shared between
        -- the two paths.  This helps keep the logic shallow.
        screen_row_current_address
          <= to_unsigned(to_integer(screen_ram_base(16 downto 0))
                         + to_integer(first_card_of_row),17);
        card_of_row <= (others =>'0');
        screen_ram_buffer_address <= to_unsigned(0,9);
        report "ZEROing screen_ram_buffer_address" severity note;
        -- Finally decide which way we should go
        if to_integer(first_card_of_row) /= to_integer(prev_first_card_of_row) then          
          raster_fetch_state <= FetchScreenRamLine;
          report "BADLINE @ y = " & integer'image(to_integer(displayy)) severity note;
          report "BADLINE first_card_of_row = %" & to_string(std_logic_vector(first_card_of_row)) severity note;
          report "BADLINE prev_first_card_of_row = %" & to_string(std_logic_vector(prev_first_card_of_row)) severity note;
        else
          report "noBADLINE" severity note;
          raster_fetch_state <= FetchFirstCharacter;
        end if;
      end if;

      if raster_fetch_state /= Idle or paint_fsm_state /= Idle then
        report "raster_fetch_state=" & vic_chargen_fsm'image(raster_fetch_state) & ", "
          & "paint_fsm_state=" & vic_paint_fsm'image(paint_fsm_state)
          & ", rb_w_addr=$" & to_hstring(raster_buffer_write_address) severity note;
      end if;

      case raster_fetch_state is
        when Idle => null;
        when FetchScreenRamLine =>
          if paint_ready='1' then
            paint_fsm_state <= Idle;
            raster_fetch_state <= FetchScreenRamWait;
            ramaddress <= screen_row_current_address;
            screen_row_fetch_address <= screen_row_current_address + 1;
            character_number <= (others => '0');
            screen_ram_buffer_address <= to_unsigned(0,9);
            report "ZEROing screen_ram_buffer_address" severity note;
            colourramaddress <= to_unsigned(to_integer(colour_ram_base) + to_integer(first_card_of_row),16);
            report "BADLINE, colour_ram_base=$" & to_hstring(colour_ram_base) severity note;
          end if;
        when FetchScreenRamWait =>
          -- allow for two cycle delay caused by using doubly buffered version of ramdata
          -- XXX we are wasting cycles between bytes instead of just pipelining
          -- it.
          ramaddress <= screen_row_fetch_address;
          screen_row_fetch_address <= screen_row_fetch_address + 1;
          raster_fetch_state <= FetchScreenRamWait2;
        when FetchScreenRamWait2 =>
          ramaddress <= screen_row_fetch_address;
          screen_row_fetch_address <= screen_row_fetch_address + 1;
          raster_fetch_state <= FetchScreenRamNext;
        when FetchScreenRamNext =>
          report "screen_row_fetch_address = $" & to_hstring("000"&screen_row_fetch_address) severity note;
          -- Store current byte of screen RAM
          screen_ram_buffer_write <= '1';
          screen_ram_buffer_address <= character_number;
          report "SETting screen_ram_buffer_address to $" & to_hstring("000"&character_number) severity note;
          report "for screen_r paint_ramdata=$" & to_hstring(paint_ramdata) & ", raw ramdata=$" & to_hstring(ramdata) severity note;
          screen_ram_buffer_din <= paint_ramdata;
          ramaddress <= screen_row_fetch_address;
          -- Ask for next byte of screen RAM
          screen_row_current_address <= screen_row_current_address + 1;
          screen_row_fetch_address <= screen_row_fetch_address + 1;
          character_number <= character_number + 1;
          -- See if we already have enough bytes already.
          -- virtual_row_width bytes, unless in 16bit character set mode, in which
          -- case we need twice that many bytes.
          if sixteenbit_charset='1' then
            if character_number = virtual_row_width(7 downto 0)&'0' then
              raster_fetch_state <= FetchFirstCharacter;
            else
              raster_fetch_state <= FetchScreenRamNext;
            end if;
          else
            if character_number = '0'&virtual_row_width(7 downto 0) then
              raster_fetch_state <= FetchFirstCharacter;
            else
              raster_fetch_state <= FetchScreenRamNext;
            end if;
          end if;
        when FetchFirstCharacter =>
          character_number <= (others => '0');
          card_of_row <= (others => '0');
          screen_ram_buffer_write <= '0';
          screen_ram_buffer_address <= to_unsigned(0,9);
          report "SETting screen_ram_buffer_address to 1" severity note;
          raster_fetch_state <= FetchNextCharacter;         
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
          if text_mode='1' then
            -- Read 8 or 16 bit screen RAM data for character number information
            -- (the address was put on the bus for us already).
            -- Handle extended background colour mode here if required.
            glyph_number(11 downto 8) <= x"0";
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
          screen_ram_buffer_address <= screen_ram_buffer_address + 1;
          report "INCREMENTing screen_ram_buffer_address to " & integer'image(to_integer(screen_ram_buffer_address)+1) severity note;

          -- Clear 16-bit character attributes in case we are reading 8-bits only.
          glyph_flip_horizontal <= '0';
          glyph_flip_vertical <= '0';

          if sixteenbit_charset='1' then
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
          -- Work out if character is full colour (ignored for bitmap mode but
          -- calculated outside of if test to flatten logic).
          if screen_ram_buffer_dout(3 downto 0) = "0000" then
            glyph_full_colour <= fullcolour_8bitchars;
          else
            glyph_full_colour <= fullcolour_extendedchars;
          end if;
          if text_mode='1' then
            -- We only allow 4096 characters in extended mode.
            -- The spare bits are used to provide some (hopefully useful)
            -- extended attributes. 
            glyph_number(11 downto 8) <= screen_ram_buffer_dout(3 downto 0);
            glyph_flip_horizontal <= screen_ram_buffer_dout(4);
            glyph_flip_vertical <= screen_ram_buffer_dout(5);
            raster_fetch_State <= FetchTextCell;
          else
            bitmap_colour_background <= screen_ram_buffer_dout;
            raster_fetch_state <= FetchBitmapCell;
          end if;
          screen_ram_buffer_address <= screen_ram_buffer_address + 1;
          report "INCREMENTing screen_ram_buffer_address to " & integer'image(to_integer(screen_ram_buffer_address)+1) severity note;
        when FetchTextCell =>
          report "from screen_ram we get glyph_number = $" & to_hstring(glyph_number) severity note;
          -- We now know the character number, and whether it is full-colour or
          -- normal, and whether we are flipping in either axis, and so can
          -- work out the address to fetch data from.
          if glyph_full_colour='1' then
            -- Full colour glyphs come from 64*(glyph_number) in RAM, never
            -- from character ROM.  128KB/64 = 2048 possible glyphs.
            glyph_data_address(16 downto 6) <= glyph_number(10 downto 0);
            if glyph_flip_vertical='1' then
              glyph_data_address(5 downto 3) <= not chargen_y;
            else
              glyph_data_address(5 downto 3) <= chargen_y;
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
                <= character_set_address(16 downto 0)
                + to_integer(glyph_number)*8+to_integer(chargen_y);
            else
              glyph_data_address
                <= character_set_address(16 downto 0)
                + to_integer(glyph_number)*8+7-to_integer(chargen_y);
            end if;
            -- Mark as possibly coming from ROM
            character_data_from_rom <= '1';
          end if;
          raster_fetch_state <= FetchTextCellColourAndSource;
        when FetchTextCellColourAndSource =>
          -- Finally determine whether source is from RAM or CHARROM
          if character_data_from_rom = '1' then
            if glyph_data_address(16 downto 12) = "0"&x"1"
              or glyph_data_address(16 downto 12) = "0"&x"9" then
              report "reading from rom: glyph_data_address=$" & to_hstring(glyph_data_address(15 downto 0))
                & "chargen_y=" & to_string(std_logic_vector(chargen_y)) severity note;
              character_data_from_rom <= '1';
            else
              character_data_from_rom <= '0';
            end if;
          end if;
          -- Record colour and attribute information from colour RAM
          glyph_colour(7 downto 4) <= "0000";
          glyph_colour(3 downto 0) <= colourramdata(3 downto 0);
          glyph_bold <= '0';
          glyph_underline <= '0';
          glyph_reverse <= '0';
          glyph_visible <= '1';
          if viciii_extended_attributes='1' then
            if colourramdata(4)='1' then
              -- Blinking glyph
              if colourramdata(5)='1'
                or colourramdata(6)='1'
                or colourramdata(7)='1' then
                -- Blinking attributes
                if viciii_blink_phase='1' then
                  glyph_reverse <= colourramdata(5);
                  glyph_bold <= colourramdata(6);
                  glyph_colour(4) <= colourramdata(6);
                  if chargen_y(2 downto 0)="111" then
                    glyph_underline <= colourramdata(7);
                  end if;
                end if;
              else
                -- Just plain blinking character
                glyph_visible <= viciii_blink_phase;
              end if;
            else
              -- Non-blinking attributes
              glyph_visible <= '1';
              glyph_reverse <= colourramdata(5);
              glyph_bold <= colourramdata(6);
              glyph_colour(4) <= colourramdata(6);
              if chargen_y(2 downto 0)="111" then
                glyph_underline <= colourramdata(7);
              end if;
            end if;
          end if;

          -- Ask for first byte of data so that paint can commence immediately.
          report "setting ramaddress to $" & to_hstring("000"&glyph_data_address) & " for painting." severity note;
          ramaddress <= glyph_data_address;
          -- upper bit of charrom address is set by $D018, only 258*8 = 2K
          -- range of address is controlled here by character number.
          report "setting charaddress to " & integer'image(to_integer(glyph_data_address(10 downto 0)))
            & " for painting glyph $" & to_hstring(glyph_number(11 downto 0)) severity note;
          charaddress <= to_integer(glyph_data_address(11 downto 0));

          -- Schedule next colour ram byte
          colourramaddress <= colourramaddress + 1;
          
          raster_fetch_state <= PaintMemWait;
        when PaintMemWait =>
          -- Allow for 2 cycle delay to get data in paint_ramdata
          -- In this cycle chardata and ramdata will have the requested value
          raster_fetch_state <= PaintMemWait2;
        when PaintMemWait2 =>
          raster_fetch_state <= PaintMemWait3;
        when PaintMemWait3 =>
          -- In this cycle paint_chardata and and paint_ramdata should have the
          -- requested value
          -- Abort if we have already drawn enough characters.
          character_number <= character_number + 1;
          if character_number = virtual_row_width then
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
            -- Now work out exactly how we are painting
            if glyph_full_colour='1' then
              -- Paint full-colour glyph
              paint_fsm_state <= PaintFullColour;
            else
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
              elsif multicolour_mode='1' and extended_background_mode='0' then
                -- Multicolour mode
                paint_background <= screen_colour;
                if text_mode='1' then
                  paint_mc1 <= multi1_colour;
                  paint_mc2 <= multi2_colour;
                  -- multi-colour text mode masks bit 3 of the foreground
                  -- colour to select whether the character is multi-colour or
                  -- not.
                  paint_foreground <= glyph_colour(7 downto 4)&'0'&glyph_colour(2 downto 0);
                else
                  paint_mc1 <= bitmap_colour_background;
                  paint_mc2 <= bitmap_colour_foreground;
                  paint_foreground <= glyph_colour;
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
                -- ECM - XXX - Not currently implemented.
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
            -- XXX should start drawing sprites
            raster_fetch_state <= Idle;
          end if;
        when others => null;
      end case;

      raster_buffer_write <= '0';
      case paint_fsm_state is
        when Idle =>
          if paint_ready /= '1' then
            paint_ready <= '1';
            report "asserting paint_ready" severity note;
          end if;
        when PaintMono =>
          -- Paint 8 mono bits from ramdata or chardata
          -- Paint from a buffer to meet timing, even though it means we spend
          -- 9 cycles per char to paint, instead of the ideal 8.          
          report "paint_flip_horizontal="&std_logic'image(paint_flip_horizontal)
            & ", paint_from_charrom=" & std_logic'image(paint_from_charrom) severity note;
          if raster_buffer_write_address = 0 then
            report "painting either $ " & to_hstring(paint_ramdata) & " or $" & to_hstring(paint_chardata) severity note;
            report "  painting from direct memory would have $ " & to_hstring(ramdata) & " or $" & to_hstring(chardata) severity note;
          end if;
          if paint_flip_horizontal='1' and paint_from_charrom='1' then
            report "Painting FLIPPED glyph from character rom (bits=$"&to_hstring(paint_chardata)&")" severity note;
            paint_buffer <= paint_chardata;
          elsif paint_flip_horizontal='0' and paint_from_charrom='1' then
            report "Painting glyph from character rom (bits=$"&to_hstring(paint_chardata)&")" severity note;
            paint_buffer <= paint_chardata(0)&paint_chardata(1)&paint_chardata(2)&paint_chardata(3)
                            &paint_chardata(4)&paint_chardata(5)&paint_chardata(6)&paint_chardata(7);
          elsif paint_flip_horizontal='1' and paint_from_charrom='0' then
            report "Painting FLIPPED glyph from RAM (bits=$"&to_hstring(paint_ramdata)&")" severity note;
            if paint_ramdata(0)='1' then
              raster_buffer_write_data <= '1'&paint_foreground;
            else
              raster_buffer_write_data <= '0'&paint_background;
            end if;
            -- XXX DEBUG: trying to find the source of the apparent path
            -- between chipram and pain_buffer, when it should be going via paint_ramdata
            paint_buffer <= paint_ramdata;
          elsif paint_flip_horizontal='0' and paint_from_charrom='0' then
            report "Painting glyph from RAM (bits=$"&to_hstring(paint_ramdata)&")" severity note;
            paint_buffer <= paint_ramdata(0)&paint_ramdata(1)&paint_ramdata(2)&paint_ramdata(3)
                            &paint_ramdata(4)&paint_ramdata(5)&paint_ramdata(6)&paint_ramdata(7);
          end if;
          paint_bits_remaining <= 8;
          paint_ready <= '0';
          paint_fsm_state <= PaintMonoBits;
        when PaintMonoBits =>
          if paint_bits_remaining = 8 then
            report "painting card using data $" & to_hstring(paint_buffer) severity note;
          end if;
          if paint_bits_remaining /= 0 then
            paint_buffer<= '0'&paint_buffer(7 downto 1);
            if paint_buffer(0)='1' then
              raster_buffer_write_data <= '1'&paint_foreground;
              report "Painting foreground pixel in colour $" & to_hstring(paint_foreground) severity note;
            else
              raster_buffer_write_data <= '0'&paint_background;
              report "Painting background pixel in colour $" & to_hstring(paint_background) severity note;
            end if;
            raster_buffer_write_address <= raster_buffer_write_address + 1;
            raster_buffer_write <= '1';
            report "paint_bits_remaining=" & integer'image(paint_bits_remaining) severity note;
            paint_bits_remaining <= paint_bits_remaining - 1;
          end if;
          if paint_bits_remaining = 1 then
            -- Tell character generator when we are able to become idle.
            -- (the generator tells us when to go idle)
            paint_ready <= '1';
          end if;
        when PaintMultiColour =>
          -- Paint 4 multi-colour half-nybls from ramdata or chardata
          -- Paint from a buffer to meet timing, even though it means we spend
          -- 5 cycles per char to paint, instead of the ideal 4.          
          report "paint_flip_horizontal="&std_logic'image(paint_flip_horizontal)
            & ", paint_from_charrom=" & std_logic'image(paint_from_charrom) severity note;
          if raster_buffer_write_address = 0 then
            report "painting either $ " & to_hstring(paint_ramdata) & " or $" & to_hstring(paint_chardata) severity note;
            report "  painting from direct memory would have $ " & to_hstring(ramdata) & " or $" & to_hstring(chardata) severity note;
          end if;
          if paint_flip_horizontal='1' and paint_from_charrom='1' then
            report "Painting FLIPPED glyph from character rom (bits=$"&to_hstring(paint_chardata)&")" severity note;
            paint_buffer <= paint_chardata;
          elsif paint_flip_horizontal='0' and paint_from_charrom='1' then
            report "Painting glyph from character rom (bits=$"&to_hstring(paint_chardata)&")" severity note;
            paint_buffer <= paint_chardata(1)&paint_chardata(0)&paint_chardata(3)&paint_chardata(2)
                            &paint_chardata(5)&paint_chardata(4)&paint_chardata(7)&paint_chardata(6);
          elsif paint_flip_horizontal='1' and paint_from_charrom='0' then
            report "Painting FLIPPED glyph from RAM (bits=$"&to_hstring(paint_ramdata)&")" severity note;
            if paint_ramdata(0)='1' then
              raster_buffer_write_data <= '1'&paint_foreground;
            else
              raster_buffer_write_data <= '0'&paint_background;
            end if;
            -- XXX DEBUG: trying to find the source of the apparent path
            -- between chipram and pain_buffer, when it should be going via paint_ramdata
            paint_buffer <= paint_ramdata;
          elsif paint_flip_horizontal='0' and paint_from_charrom='0' then
            report "Painting glyph from RAM (bits=$"&to_hstring(paint_ramdata)&")" severity note;
            paint_buffer <= paint_ramdata(1)&paint_ramdata(0)&paint_ramdata(3)&paint_ramdata(2)
                            &paint_ramdata(5)&paint_ramdata(4)&paint_ramdata(7)&paint_ramdata(6);
          end if;
          paint_bits_remaining <= 4;
          paint_ready <= '0';
          paint_fsm_state <= PaintMultiColourBits;
        when PaintMultiColourBits =>
          if paint_bits_remaining = 4 then
            report "painting card using data $" & to_hstring(paint_buffer) severity note;
          end if;
          if paint_bits_remaining /= 0 then
            paint_buffer<= "00"&paint_buffer(7 downto 2);
            case paint_buffer(1 downto 0) is
              when "00" =>
                raster_buffer_write_data <= '0'&paint_background;
                report "Painting background pixel in colour $" & to_hstring(paint_background) severity note;
              when "01" =>
                raster_buffer_write_data <= '1'&paint_foreground;
                report "Painting multi-colour 2 pixel in colour $" & to_hstring(paint_mc1) severity note;
              when "10" =>
                raster_buffer_write_data <= '1'&paint_foreground;
                report "Painting multi-colour 3 pixel in colour $" & to_hstring(paint_mc2) severity note;
              when "11" =>
                raster_buffer_write_data <= '1'&paint_foreground;
                report "Painting foreground pixel in colour $" & to_hstring(paint_foreground) severity note;
              when others =>
                null;
            end case;
            raster_buffer_write_address <= raster_buffer_write_address + 1;
            raster_buffer_write <= '1';
            report "paint_bits_remaining=" & integer'image(paint_bits_remaining) severity note;
            paint_bits_remaining <= paint_bits_remaining - 1;
          end if;
          -- Stretch multi-colour pixels to be double width
          if paint_bits_remaining /= 1 then
            paint_fsm_state <= PaintMultiColourHold;
          end if;
        when PaintMultiColourHold =>
          raster_buffer_write_address <= raster_buffer_write_address + 1;
          raster_buffer_write <= '1';
          if paint_bits_remaining = 1 then
            -- Tell character generator when we are able to become idle.
            -- (the generator tells us when to go idle)
            paint_ready <= '1';
          end if;
          paint_fsm_state <= PaintMultiColourBits;
        when others =>
          -- If we don't know what to do, just smile and nod and say we are
          -- ready again.
          paint_ready <= '1';
      end case;

      if raster_fetch_state /= Idle or paint_fsm_state /= Idle then
        report "raster_fetch_state=" & vic_chargen_fsm'image(raster_fetch_state) & ", "
          & "paint_fsm_state=" & vic_paint_fsm'image(paint_fsm_state)
          & ", rb_w_addr=$" & to_hstring(raster_buffer_write_address) severity note;
      end if;
      
    end if;
  end process;

end Behavioral;

