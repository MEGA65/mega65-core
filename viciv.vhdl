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
    -- CPU clock (used for fastram and fastio interfaces)
    ----------------------------------------------------------------------
    cpuclock : in std_logic;

    -- CPU IRQ
    irq : out std_logic;

    reset : in std_logic;

    -- Internal drive LED status for OSD
    led : in std_logic;
    motor : in std_logic;

    ----------------------------------------------------------------------
    -- VGA output
    ----------------------------------------------------------------------
    vsync : out  STD_LOGIC;
    hsync : out  STD_LOGIC;
    vgared : out  UNSIGNED (3 downto 0);
    vgagreen : out  UNSIGNED (3 downto 0);
    vgablue : out  UNSIGNED (3 downto 0);

    ---------------------------------------------------------------------------
    -- CPU Interface to FastRAM in video controller (just 128KB for now)
    ---------------------------------------------------------------------------
    fastram_we : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    fastram_address : IN STD_LOGIC_VECTOR(13 DOWNTO 0);
    fastram_datain : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    fastram_dataout : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);      
    
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

  component screen_ram_fifo IS
    PORT (
      rst : IN STD_LOGIC;
      wr_clk : IN STD_LOGIC;
      rd_clk : IN STD_LOGIC;
      din : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
      wr_en : IN STD_LOGIC;
      rd_en : IN STD_LOGIC;
      dout : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      full : OUT STD_LOGIC;
      empty : OUT STD_LOGIC;
      rd_data_count : OUT STD_LOGIC_VECTOR(5 DOWNTO 0)
      );
  END component;
  
  component charrom is
    port (Clk : in std_logic;
          address : in std_logic_vector(11 downto 0);
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
  component ram64x16k
    PORT (
      clka : IN STD_LOGIC;
      wea : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      addra : IN STD_LOGIC_VECTOR(13 DOWNTO 0);
      dina : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
      douta : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
      clkb : IN STD_LOGIC;
      web : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      addrb : IN STD_LOGIC_VECTOR(13 DOWNTO 0);
      dinb : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
      doutb : OUT STD_LOGIC_VECTOR(63 DOWNTO 0)
      );
  end component;

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
  
  constant frame_width : integer := 2592;
  constant frame_h_front : integer := 128;
  constant frame_h_syncwidth : integer := 208;

  -- The real mode says 1242, but we need 1248 so that 1248/312 = 4,
  -- allowing VIC-II PAL raster numbers to be easily calculated.
  constant frame_height : integer := 1248;
  constant frame_v_front : integer := 1;
  constant frame_v_syncheight : integer := 3;
  
  -- Frame generator counters
  signal xcounter : unsigned(11 downto 0) := (others => '0');
  signal ycounter : unsigned(10 downto 0) := (others => '0');
  -- Virtual raster number for VIC-II
  signal vicii_ycounter : unsigned(8 downto 0) := (others => '0');
  signal vicii_ycounter_phase : unsigned(2 downto 0) := (others => '0');
  signal vicii_ycounter_max_phase : unsigned(2 downto 0) := (others => '0');
  -- Is the VIC-II virtual raster number the active one for interrupts, or
  -- are we comparing to physical rasters?  This is decided by which register
  -- gets written to last.
  signal vicii_is_raster_source : std_logic := '1';
  
  -- Actual pixel positions in the frame
  signal displayx : unsigned(11 downto 0) := (others => '0');
  signal displayy : unsigned(11 downto 0) := (others => '0');
  signal display_active : std_logic := '0';
  -- Mark if we are in the top line of display
  -- (used for overlaying drive LED on first row of pixels)
  signal displayline0 : std_logic := '1';
  signal displaycolumn0 : std_logic := '1';

  -- Asserted if in the 1200 vetical lines of the frame
  signal vert_in_frame : std_logic := '0';

  -- Used for counting down cycles while waiting for RAM to respond
  signal delay : std_logic_vector(1 downto 0);

  -- Interface to FIFO for screen ram
  signal screen_ram_fifo_fetched : integer range 0 to 64;
  signal screen_ram_fifo_write  : std_logic := '0';
  signal screen_ram_fifo_reset : std_logic := '0';
  signal screen_ram_fifo_din : unsigned(63 downto 0);
  signal screen_ram_fifo_readnext : std_logic := '0';
  signal screen_ram_fifo_dout : unsigned(7 downto 0);
  -- Internal registers used to keep track of the screen ram for the current row
  signal screen_row_address : unsigned(16 downto 0);
  signal screen_row_current_address : unsigned(16 downto 0);
  
  
  signal debug_x : unsigned(11 downto 0) := "111111111110";
  signal debug_y : unsigned(11 downto 0) := "111111111110";
  signal debug_cycles_to_next_card : unsigned(7 downto 0);
  signal debug_next_card_number : unsigned(15 downto 0);
  signal debug_char_fetch_cycle : integer range 0 to 255;
  signal debug_chargen_active : std_logic;
  signal debug_chargen_active_soon : std_logic;
  signal debug_character_data_from_rom : std_logic;
  
  -----------------------------------------------------------------------------
  -- Video controller registers
  -----------------------------------------------------------------------------

  -- New control registers
  -- Number added to card number for each row of characters, i.e., virtual
  -- character display width.
  signal virtual_row_width : unsigned(15 downto 0) := to_unsigned(40,16);
  -- Each character pixel will be (n+1) pixels wide  
  signal chargen_x_scale : unsigned(7 downto 0) := x"04";  -- x"04"
  -- Each character pixel will be (n+1) pixels high
  signal chargen_y_scale : unsigned(7 downto 0) := x"04";  -- x"04"
  -- smooth scrolling position in natural pixels.
  -- Set in the same way as the border
  signal x_chargen_start : unsigned(11 downto 0) := to_unsigned(0,12);  -- 160
  signal x_chargen_start_pipeline : unsigned(11 downto 0);
  signal x_chargen_start_display : unsigned(11 downto 0);
  signal x_chargen_start_minus1 : unsigned(11 downto 0);
  signal x_chargen_start_minus2 : unsigned(11 downto 0);
  signal x_chargen_start_minus9 : unsigned(11 downto 0);
  signal x_chargen_start_minus17 : unsigned(11 downto 0);

  signal y_chargen_start : unsigned(11 downto 0) := to_unsigned(0,12);  -- 100
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
  signal border_x_left : unsigned(11 downto 0) := to_unsigned(0,12);  -- 160
  signal border_x_right : unsigned(11 downto 0) := to_unsigned(1920-160,12);
  signal border_y_top : unsigned(11 downto 0) := to_unsigned(0,12);  -- 100
  signal border_y_bottom : unsigned(11 downto 0) := to_unsigned(1200-101,12);
  signal blank : std_logic := '0';

  -- Colour registers ($D020 - $D024)
  signal screen_colour : unsigned(7 downto 0) := x"00";  -- black
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
  -- worst case we can need >32KB of it.  Must correspond to a FastRAM address,
  -- so the MSBs are irrelevant.
  signal colour_ram_base : unsigned(15 downto 0) := x"0000";
  -- Screen RAM offset
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
  signal card_number_is_extended : std_logic;  -- set if card_number > $00FF
  signal first_card_of_row : unsigned(15 downto 0);
  -- coordinates after applying the above scaling factors
  signal chargen_x : unsigned(2 downto 0) := (others => '0');
  signal chargen_y : unsigned(2 downto 0) := (others => '0');
  -- fractional pixel position for scaling
  signal chargen_y_sub : unsigned(4 downto 0);
  signal chargen_x_sub : unsigned(4 downto 0);
  -- character data fetch FSM
  signal char_fetch_cycle : integer range 0 to 255 := 16;
  -- data for next card
  signal next_bitmap_colours  : unsigned(7 downto 0);
  signal next_next_bitmap_colours  : unsigned(7 downto 0);
  signal next_glyph_number : unsigned(15 downto 0);
  signal next_next_glyph_number : unsigned(15 downto 0);
  signal next_glyph_number8 : unsigned(7 downto 0);
  signal next_glyph_number16 : unsigned(15 downto 0);
  signal next_glyph_colour : unsigned(3 downto 0);
  signal next_glyph_attributes : unsigned(3 downto 0);
  signal next_glyph_visible : std_logic;
  signal next_glyph_bold : std_logic;
  signal next_glyph_underline : std_logic;
  signal next_glyph_reverse : std_logic;
  signal next_glyph_chardata : std_logic_vector(63 downto 0);
  signal next_glyph_pixeldata : std_logic_vector(63 downto 0);
  signal next_glyph_number_buffer : std_logic_vector(63 downto 0);
  signal next_glyph_colour_buffer : std_logic_vector(7 downto 0);
  signal next_glyph_colour_buffer_temp : std_logic_vector(7 downto 0);
  signal next_glyph_full_colour : std_logic;
  signal next_chargen_x : unsigned(2 downto 0) := (others => '0');
  signal next_card_number_is_extended : std_logic;  -- set if card_number > $00FF
  signal chargen_active : std_logic := '0';
  signal chargen_active_soon : std_logic := '0';

  -- data for current card
  signal bitmap_colours  : unsigned(7 downto 0);
  signal glyph_number : unsigned(15 downto 0);
  signal glyph_colour : unsigned(3 downto 0);
  signal glyph_colour_t1 : unsigned(3 downto 0);
  signal glyph_colour_t2 : unsigned(3 downto 0);
  signal glyph_colour_t3 : unsigned(3 downto 0);
  signal glyph_bold : std_logic;
  signal glyph_underline : std_logic;
  signal glyph_reverse : std_logic;
  signal glyph_pixeldata : std_logic_vector(63 downto 0);
  signal glyph_full_colour : std_logic;
  
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
  
  -- Interface to character generator rom
  signal charaddress : std_logic_vector(11 downto 0);
  signal debug_charaddress : std_logic_vector(11 downto 0);
  signal chardata : std_logic_vector(7 downto 0);
  -- buffer of read data to improve timing
  signal charrow : std_logic_vector(7 downto 0);
  signal charrow_t1 : std_logic_vector(7 downto 0);
  signal charrow_t2 : std_logic_vector(7 downto 0);
  signal debug_charrow : std_logic_vector(7 downto 0);

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
  signal inborder_t1 : std_logic;
  signal inborder_t2 : std_logic;
  signal xfrontporch : std_logic;
  signal xbackporch : std_logic;

  signal last_ramaddress : std_logic_vector(13 downto 0);
  signal ramaddress : std_logic_vector(13 downto 0);
  signal ramdata : std_logic_vector(63 downto 0);

  -- Precalculated mono/multicolour pixel bits
  signal multicolour_bits : std_logic_vector(1 downto 0) := (others => '0');
  signal monobit : std_logic := '0';
  
  -- Colour RAM access for video controller
  signal colourramaddress : std_logic_vector(15 downto 0);
  signal colourramdata : std_logic_vector(7 downto 0);
  -- ... and for CPU
  signal colour_ram_fastio_address : std_logic_vector(15 downto 0);
  
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
  
begin

  fifo1: component screen_ram_fifo
    port map (
      rst    => screen_ram_fifo_reset,
      wr_clk => pixelclock,
      rd_clk => pixelclock,
      din    => std_logic_vector(screen_ram_fifo_din),
      unsigned(dout)   => screen_ram_fifo_dout,
      wr_en  => screen_ram_fifo_write,
      rd_en  => screen_ram_fifo_readnext);
  
  fastram1 : component ram64x16k
    PORT MAP (
      -- CPU side port
      clka => cpuclock,
      wea => fastram_we,
      addra => fastram_address,
      dina => fastram_datain,
      douta => fastram_dataout,
      -- video controller use port b of the dual-port fast ram.
      -- The CPU uses port a
      clkb => pixelclock,
      web => (others => '0'),
      addrb => ramaddress,
      dinb => (others => '0'),
      doutb => ramdata
      );

  colourram1 : component ram8x64k
    PORT MAP (
      clka => cpuclock,
      ena => colour_ram_cs,
      wea(0) => fastio_write,
      addra => colour_ram_fastio_address,
      dina => fastio_wdata,
      douta => colour_ram_fastio_rdata,
      -- video controller use port b of the dual-port colour ram.
      -- The CPU uses port a via the fastio interface
      clkb => pixelclock,
      web => (others => '0'),
      addrb => colourramaddress,
      dinb => (others => '0'),
      doutb => colourramdata
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

  process(cpuclock,fastio_addr,fastio_read,
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
          fullcolour_extendedchars,sixteenbit_charset,char_fetch_cycle,
          cycles_to_next_card,xfrontporch,xbackporch,chargen_active,inborder,
          irq_drive,vicii_sprite_x_expand,sprite_multi0_colour,
          sprite_multi1_colour,sprite_colours,colourram_at_dc00_internal,
          viciii_extended_attributes,virtual_row_width,chargen_x_scale,
          chargen_y_scale,xcounter,chargen_active_soon,card_number,
          colour_ram_base,vicii_sprite_pointer_address,palette_bank_fastio,
          x_chargen_start_minus17,debug_next_card_number,debug_cycles_to_next_card,
          debug_chargen_active,debug_char_fetch_cycle,debug_charaddress,
          debug_charrow,palette_fastio_rdata,palette_bank_chargen,
          debug_chargen_active_soon,palette_bank_sprites) is

    procedure viciv_interpret_legacy_mode_registers is
    begin
      if reg_h640='0' and reg_h1280='0' then
        -- 40 column mode (5x pixels, standard side borders)
        x_chargen_start
          <= to_unsigned(160+4+(to_integer(vicii_x_smoothscroll)*5),12);
        -- set horizontal borders based on 40/38 columns
        if thirtyeightcolumns='0' then
          border_x_left <= to_unsigned(160,12);
          border_x_right <= to_unsigned(1920-160,12);
        else  
          border_x_left <= to_unsigned(160+(7*5),12);
          border_x_right <= to_unsigned(1920-160-(9*5),12);
        end if;
        chargen_x_scale <= x"04";
        virtual_row_width <= to_unsigned(40,16);
      elsif reg_h640='1' and reg_h1280='0' then
        -- 80 column mode (3x pixels, no side border)
        x_chargen_start
          <= to_unsigned(0+(to_integer(vicii_x_smoothscroll)*3),12);
        -- set horizontal borders based on 40/38 columns
        if thirtyeightcolumns='0' then
          border_x_left <= to_unsigned(0,12);
          border_x_right <= to_unsigned(1920-0,12);
        else  
          border_x_left <= to_unsigned(0+(7*3),12);
          border_x_right <= to_unsigned(1920-(9*3),12);
        end if;
        chargen_x_scale <= x"02";
        virtual_row_width <= to_unsigned(80,16);
      elsif reg_h640='0' and reg_h1280='1' then        
        -- 160 column mode (natural pixels, fat side borders)
        x_chargen_start
          <= to_unsigned(320+4
                         +(to_integer(vicii_x_smoothscroll)*1),12);
        -- set horizontal borders based on 40/38 columns
        if thirtyeightcolumns='0' then
          border_x_left <= to_unsigned(320,12);
          border_x_right <= to_unsigned(1920-320,12);
        else  
          border_x_left <= to_unsigned(320+(7*1),12);
          border_x_right <= to_unsigned(1920-320-(9*1),12);
        end if;
        chargen_x_scale <= x"00";
        virtual_row_width <= to_unsigned(160,16);
      else
        -- 240 column mode (natural pixels, no side border)
        x_chargen_start
          <= to_unsigned(0+to_integer(vicii_x_smoothscroll)*3,12);
        -- set horizontal borders based on 40/38 columns
        if thirtyeightcolumns='0' then
          border_x_left <= to_unsigned(0,12);
          border_x_right <= to_unsigned(1920-0,12);
        else  
          border_x_left <= to_unsigned(0+(7*3),12);
          border_x_right <= to_unsigned(1920-(9*3),12);
        end if;
        virtual_row_width <= to_unsigned(240,16);
        chargen_x_scale <= x"00";
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
          colour_ram_fastio_address <= "000000" & fastio_addr(9 downto 0);
        elsif register_page>=12 and register_page<=15 then
                                        -- colour ram read $DC00 - $DFFF
          colour_ram_fastio_address <= "000001" & fastio_addr(9 downto 0);
        else
          colour_ram_fastio_address <= (others => '0');
        end if;
      elsif register_bank(7 downto 4)=x"8" then
                                        -- colour RAM all 64KB
        colour_ram_fastio_address <= fastio_addr(15 downto 0);
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
          fastio_rdata <= std_logic_vector(displayx(11 downto 4));
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
          -- XXX Can emulate VIC-III H640, V400 and H1280 by adjusting x and y scale
          -- registers
          fastio_rdata <=
            reg_h640                           -- H640
            & "1"                         -- FAST
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
          fastio_rdata <= std_logic_vector(xcounter(7 downto 0));
        elsif register_number=81 then
          fastio_rdata(7 downto 4) <= x"0";
          fastio_rdata(3 downto 0) <= std_logic_vector(xcounter(11 downto 8));
        elsif register_number=82 then
          fastio_rdata <= std_logic_vector(ycounter(7 downto 0));
        elsif register_number=83 then
          fastio_rdata(7 downto 3) <= "00000";
          fastio_rdata(2 downto 0) <= std_logic_vector(ycounter(10 downto 8));
        elsif register_number=84 then
                                        -- $D054 (53332) - New mode control register
          fastio_rdata(7 downto 3) <= (others => '1');
          fastio_rdata(2) <= fullcolour_extendedchars;
          fastio_rdata(1) <= fullcolour_8bitchars;
          fastio_rdata(0) <= sixteenbit_charset;
        elsif register_number=85 then
          fastio_rdata <= std_logic_vector(to_unsigned(char_fetch_cycle,8));
        elsif register_number=86 then
          fastio_rdata <= std_logic_vector(cycles_to_next_card);
        elsif register_number=87 then
          fastio_rdata(7) <= xfrontporch;
          fastio_rdata(6) <= xbackporch;
          fastio_rdata(5) <= chargen_active;
          fastio_rdata(4) <= inborder;
          fastio_rdata(3) <= chargen_active_soon;
          fastio_rdata(2 downto 0) <= "111";
        elsif register_number=88 then
          fastio_rdata <= std_logic_vector(card_number(7 downto 0));
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
        elsif register_number=112 then
          fastio_rdata <= palette_bank_fastio & palette_bank_chargen & palette_bank_sprites & "11";
        elsif register_number=113 then
          fastio_rdata <= std_logic_vector(x_chargen_start_minus17(7 downto 0));
        elsif register_number=114 then
          fastio_rdata <= "0000"&std_logic_vector(x_chargen_start_minus17(11 downto 8));
        elsif register_number=115 then
          fastio_rdata <= std_logic_vector(debug_next_card_number(7 downto 0));
        elsif register_number=116 then
          fastio_rdata <= std_logic_vector(debug_next_card_number(15 downto 8));
        elsif register_number=117 then
          fastio_rdata <= std_logic_vector(debug_cycles_to_next_card(7 downto 0));
        elsif register_number=118 then
          fastio_rdata <= "00000" & debug_character_data_from_rom & debug_chargen_active & debug_chargen_active_soon;
        elsif register_number=124 then
          fastio_rdata <= std_logic_vector(to_unsigned(debug_char_fetch_cycle,8));
        elsif register_number=125 then
          fastio_rdata <= debug_charaddress(7 downto 0);
        elsif register_number=126 then
          fastio_rdata <= "0000" & debug_charaddress(11 downto 8);
        elsif register_number=127 then
          fastio_rdata <= debug_charrow;
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
    
    if rising_edge(cpuclock) then

      report "drive led = " & std_logic'image(led)
        & ", drive motor= " & std_logic'image(motor) severity note;

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
          charaddress(11) <= fastio_wdata(1);
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
            multi1_colour <= unsigned(fastio_wdata);
          else
            multi1_colour <= unsigned("0000"&fastio_wdata(3 downto 0));
          end if;
        elsif register_number=35 then
          if (register_bank=x"D0" or register_bank=x"D2") then
            multi2_colour <= unsigned(fastio_wdata);
          else
            multi2_colour <= unsigned("0000"&fastio_wdata(3 downto 0));
          end if;
        elsif register_number=36 then
          if (register_bank=x"D0" or register_bank=x"D2") then
            multi3_colour <= unsigned(fastio_wdata);
          else
            multi3_colour <= unsigned("0000"&fastio_wdata(3 downto 0));
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
          -- C65 VIC-III Control A Register $D030
          -- H640
          reg_h640 <= fastio_wdata(7);
          -- FAST
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
    variable next_chargen_y : unsigned(2 downto 0) := (others => '0');
    variable card_bg_colour : unsigned(7 downto 0) := (others => '0');
    variable card_fg_colour : unsigned(7 downto 0) := (others => '0');
    variable long_address : unsigned(31 downto 0) := (others => '0');
    variable next_glyph_number_temp : std_logic_vector(15 downto 0) := (others => '0');
    variable next_glyph_colour_temp : std_logic_vector(7 downto 0) := (others => '0');
  begin    
    if rising_edge(pixelclock) then
      
      -- Acknowledge IRQs after reading $D019
      irq_raster <= irq_raster and (not ack_raster);
      irq_colissionspritebitmap <= irq_colissionspritebitmap and (not ack_colissionspritebitmap);
      irq_colissionspritesprite <= irq_colissionspritesprite and (not ack_colissionspritesprite);
      -- Set IRQ line status to CPU
      irq_drive <= not ((irq_raster and mask_raster)
                        or (irq_colissionspritebitmap and mask_colissionspritebitmap)
                        or (irq_colissionspritesprite and mask_colissionspritesprite));
      irq <= irq_drive;
      
      if (ycounter>100) and (xcounter>250) and (xcounter<350) then
        report
          "VGA"
          & " ycounter= " & integer'image(to_integer(ycounter))
          & ", xcounter= " & integer'image(to_integer(xcounter))
          & " displayx= " & integer'image(to_integer(displayx))
          & ", displayy= " & integer'image(to_integer(displayy))
          & ", cycles_to_next_card= " & integer'image(to_integer(cycles_to_next_card))
          & ", char_fetch_cycle= " & integer'image(char_fetch_cycle)
          severity note;        
      end if;
      
      if xcounter>=(frame_h_front+width) and xcounter<(frame_h_front+width+frame_h_syncwidth) then
        hsync <= '0';
      else
        hsync <= '1';
      end if;
      indisplay :='1';
      if xcounter<frame_width then
        xcounter <= xcounter + 1;
      else
        -- End of raster reached.
        -- Bump raster number and start next raster.
        xcounter <= (others => '0');
        next_chargen_x <= (others => '0');
        chargen_x_sub <= (others => '0');
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
          next_chargen_y := (others => '0');
          chargen_y_sub <= (others => '0');
          next_card_number <= (others => '0');
          first_card_of_row <= (others => '0');

          -- In top border VIC-II rasters are 2 physical rasters high
          vicii_ycounter <= (others =>'0');
          vicii_ycounter_phase <= (others => '0');
          vicii_ycounter_max_phase <= to_unsigned(1,3);  -- 0 -- 1 = 2 values         
          
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
      end if;
      if xcounter<frame_h_front then
        xfrontporch <= '1';
        displayx <= (others => '0');
      else
        xfrontporch <= '0';
      end if;
      if xcounter<(frame_h_front+width) then
        xbackporch <= '0';
      else
        xbackporch <= '1';
        displayx <= (others => '1');
      end if;

      if xfrontporch='0' and xbackporch = '0' then
        -- Increase horizonal physical pixel position
        displayx <= displayx + 1;
      end if;
      
      -- Work out if the border is active
      if displayx<border_x_left or displayx>border_x_right or
        displayy<border_y_top or displayy>border_y_bottom then
        inborder<='1';
      else
        inborder<='0';
      end if;
      inborder_t1 <= inborder;
      inborder_t2 <= inborder_t1;

      -- Work out if the next card has a character number >255
      if next_card_number(15 downto 8) /= x"00" then
        next_card_number_is_extended <= '1';
      else
        next_card_number_is_extended <= '0';
      end if;

      -- By default, copy in replacement values
      -- These assignments may be overriden further down the process.
      chargen_x <= next_chargen_x;
      chargen_y <= next_chargen_y;
      
      -- Raster control.
      -- Work out if in front porch, back porch or active part of raster.
      -- If we are in the active part of the display, work out if we have
      -- reached the start of a new character (or are about to).
      -- If so, copy in the new glyph and colour data for display.
      report "VGA: displayx=" & integer'image(to_integer(displayx)) & ", chargen_active=" & std_logic'image(chargen_active) & ", chagen_active_soon=" & std_logic'image(chargen_active_soon) & ", chargen_x=" & integer'image(to_integer(chargen_x)) & ", next_chargen_x=" & integer'image(to_integer(next_chargen_x)) severity note;
      report ", cycles_to_next_card=" & integer'image(to_integer(cycles_to_next_card))
        & ", char_fetch_cycle=" & integer'image(char_fetch_cycle)
        & ", xbackporch=" & std_logic'image(xbackporch)
        severity note;
      if xfrontporch='1' then
        indisplay := '0';
      end if;
      if (xbackporch='0') and ((chargen_active='1') or (chargen_active_soon='1')) then         -- In active part of raster
        -- Work out if we are at the end of a character
        cycles_to_next_card <= cycles_to_next_card - 1;
        if cycles_to_next_card = x"09" then
          char_fetch_cycle <= 0;
        end if;
        -- cycles_to_next_card counts down to 1, not 0.
        -- update one cycle earlier since next_card_number is a signal
        -- not a variable.

        -- We must update char_fetch_cycle before deciding if we are reaching
        -- the next card, as otherwise we stop the fetching of the next character.
        if char_fetch_cycle<8 then
          char_fetch_cycle <= char_fetch_cycle + 1;        
        end if;

        if cycles_to_next_card = 1 then
          report "VGA: Copying next_* to glyph_*" severity note;
          -- We are at the start of a character          
          if (ycounter>100) and (xcounter>250) and (xcounter<350) then
            report "VGA : Update glyph data. next_card_number=" & integer'image(to_integer(next_card_number))
              severity note;
          end if;
          
          -- Reset counter to next character to 8 cycles x (scale + 1)
          cycles_to_next_card <= (chargen_x_scale(4 downto 0)+1) & "000";
          -- Move preloaded glyph data into position when advancing to the next character          
          card_number <= next_card_number;
          card_number_is_extended <= next_card_number_is_extended;
          glyph_colour <= next_glyph_colour;

          glyph_reverse <= next_glyph_reverse;
          glyph_bold <= next_glyph_bold;
          glyph_underline <= next_glyph_underline;

          glyph_number <= next_glyph_number;
          glyph_full_colour <= next_glyph_full_colour;

          bitmap_colours <= next_bitmap_colours;
                                        -- ... and then start fetching data for the character after that
          next_card_number <= next_card_number + 1;
          if chargen_x_scale = 0 then
            char_fetch_cycle <= 0;
          end if;
          report "resetting chargen_x" severity note;
          chargen_x <= "000";
          next_chargen_x <= "000";
          chargen_x_sub <= (others => '0');
          if chargen_x_scale=0
            or chargen_x_sub = (chargen_x_scale - 1)
          then
            next_chargen_x <= "001";
          end if;
        else
          -- Update current horizontal sub-pixel and pixel position
          -- Work out if a new logical pixel starts on the next physical pixel
          -- (overrides general advance)
          if chargen_x_scale=0 then
            report "next_chargen_x inc" severity note;
            next_chargen_x <= next_chargen_x + 1;
          else
            if chargen_x_sub = (chargen_x_scale - 1) then
              report "next_chargen_x inc" severity note;
              next_chargen_x <= next_chargen_x + 1;
            end if;
            if chargen_x_sub=chargen_x_scale then
              chargen_x_sub <= (others => '0');
            else
              chargen_x_sub <= chargen_x_sub + 1;
            end if;
          end if;
        end if;
      elsif xbackporch ='1' then
        -- In back porch
        indisplay := '0';
      end if;

      -- Reset character generator position for start of frame/raster
      -- Start displaying from the correct character
      -- The -3 is to allow for the 3 cycle pixel pipeline
      x_chargen_start_minus17 <= x_chargen_start+(frame_h_front-17-3);
      x_chargen_start_minus9 <= x_chargen_start+frame_h_front-9-3;
      x_chargen_start_minus2 <= x_chargen_start+frame_h_front-2-3;
      x_chargen_start_minus1 <= x_chargen_start+frame_h_front-1-3;
      x_chargen_start_pipeline <= x_chargen_start+frame_h_front-3;
      -- Display starts once pipeline is filled, so no -3 here.
      -- The -1 is to allow for the one cycle delay of setting
      -- the chargen_active register
      x_chargen_start_display <= x_chargen_start+(frame_h_front-1);

      if xcounter=x_chargen_start_minus17 then
        report "VGA: 16 pixels before x_chargen_start. "
          & "displayx=" & integer'image(to_integer(displayx))
          & ", xchargen_start=" & integer'image(to_integer(x_chargen_start))
          & ", xchargen_start_minus17=" & integer'image(to_integer(x_chargen_start_minus17))
          severity note;
        -- Gets masked to 0 below if displayy is above y_chargen_start
        chargen_active_soon <= '1';
      end if;
      if displayx=border_x_right then
        -- Stop character generator as soon as we hit the right border
        -- so that we can switch to fetching sprite data for the next raster.
        chargen_active <= '0';
        chargen_active_soon <= '0';
        cycles_to_next_card <= (others => '1');
      end if;
      if xcounter=x_chargen_start_minus9 then
        -- Start fetching first character of the row
        -- (8 cycles is plenty of time to fetch it)       
        char_fetch_cycle <= 0;
        cycles_to_next_card <= to_unsigned(8,8);
        next_card_number <= first_card_of_row;
        card_number <= first_card_of_row;
      end if;
      if xcounter = x_chargen_start_minus2 then
        cycles_to_next_card <= "00000001";
        next_chargen_x <= (others => '0');
        chargen_x <= (others => '0');
        chargen_x_sub <= (others => '0');
        report "reset chargen_x" severity note;
      end if;
      if xcounter = x_chargen_start_minus1 then
        -- trigger next card at start of chargen row
        next_chargen_x <= (others => '0');
        chargen_x <= (others => '0');
        chargen_x_sub <= (others => '0');
        report "reset chargen_x" severity note;
      end if;
      if xcounter = x_chargen_start_display then
        -- Gets masked to 0 below if displayy is above y_chargen_start
        chargen_active <= '1';
        chargen_active_soon <= '0';
      end if;
      --if xcounter = x_chargen_start_pipeline then
      --  next_chargen_x <= (others => '0');
      --  chargen_x <= (others => '0');
      --  report "reset chargen_x" severity note;
      --end if;
      if displayy<y_chargen_start then
        chargen_y <= (others => '0');
        chargen_y_sub <= (others => '0');
        chargen_active <= '0';
        chargen_active_soon <= '0';
      end if;
      if displayy=y_chargen_start then
        chargen_y <= (others => '0');
        chargen_y_sub <= (others => '0');
      end if;
      
      if (ycounter>100) and (xcounter>250) and (xcounter<350) then
        report "VGA"
          & " next_chargen_x=" & integer'image(to_integer(next_chargen_x))
          & " chargen_x=" & integer'image(to_integer(chargen_x))
          & " chargen_x_sub=" & integer'image(to_integer(chargen_x_sub))
          & " glyph_number=" & integer'image(to_integer(glyph_number))
          severity note;
      end if;      

      if ycounter=frame_v_front then
        vert_in_frame <= '1';
      end if;
      if ycounter=(frame_v_front+height) then
        vsync <= '1';
        vert_in_frame <= '0';
      end if;
      if ycounter=(frame_v_front+height+frame_v_syncheight) then
        vsync <= '0';
      end if;

      if displayx(4)='1' then
        displaycolumn0 <= '0';
      end if;
      if xcounter = 0 then
        displaycolumn0 <= '1';
        if vert_in_frame='0' then
          displayy <= (others => '0');
          displayline0 <= '1';
          indisplay := '0';
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
            next_chargen_y := chargen_y + 1;
            if chargen_y = "111" then
              -- Increment card number every "bad line"
              first_card_of_row <= first_card_of_row + virtual_row_width;
              next_card_number <= first_card_of_row + virtual_row_width;

              bump_screen_row_address<='1';
            end if;
            chargen_y_sub <= (others => '0');
          else
            chargen_y_sub <= chargen_y_sub + 1;
          end if;
        end if;
        
        -- Regardless of what has happened, start filling the FIFO with
        -- character numbers for the character generator to use.
        -- This happens every physical raster, however, the address we fetch
        -- from only gets updated on a real "badline" (see just above where we
        -- check for chargen_y overflow).  Of course, badline is hypothetical
        -- for the VIC-IV, since all the relevant memories are dual-port.
        char_fetch_cycle <= 32;
        report "BADLINE triggered" severity note;
      end if;

      if bump_screen_row_address='1' then
        -- Compute the address for the screen row.
        screen_row_address <= screen_ram_base(16 downto 0) + first_card_of_row;
        screen_row_current_address <= screen_ram_base(16 downto 0) + first_card_of_row;
        bump_screen_row_address <= '0';
      end if;
      
      display_active <= indisplay;

      -- As soon as we begin drawing a character, start fetching the data for the
      -- next character.  Any left over cycles can be used for updating full-colour
      -- sprite data once we implement them.
      -- We need the character number, the colour byte, and the
      -- 8x8 data bits (only 8 used if character is not in full colour mode).
      case char_fetch_cycle is
        when 0 =>
          report "VGA: Fetching next_*, next_card_number=" & integer'image(to_integer(next_card_number))
            severity note;
          -- next_glyph_number has been prefetched at start of line or during
          -- the last character fetch process. Same for next_bitmap_colours.
                    
          -- Tell FIFO to start reading next character
          screen_ram_fifo_readnext <= '1';

          -- We can begin speculatively fetching bitmap data here in case we
          -- are in bitmap mode.
          -- in bitmap mode, 
          long_address(16 downto 13) := character_set_address(16 downto 13);
          long_address(12 downto 11) := "00";  -- bitmap mode display is always
                                               -- on 8KB boundary
          long_address(10 downto 0) := character_set_address(10 downto 0);
          -- shift address down 3 bits for fastram 64-bit wide interface
          long_address(13 downto 0) := long_address(16 downto 3);
          -- now add card number
          long_address(13 downto 0) := long_address(13 downto 0) + to_integer(next_card_number);

          if text_mode='1' then
            -- We know the character number since it was pre-fetched
            ramaddress <= std_logic_vector(to_unsigned(to_integer(character_set_address(16 downto 3)) + to_integer(next_glyph_number(13 downto 0)),14));
            last_ramaddress <= std_logic_vector(to_unsigned(to_integer(character_set_address(16 downto 3)) + to_integer(next_glyph_number(13 downto 0)),14));
          else
            -- Request word of memory with bitmap data in it
            ramaddress <= std_logic_vector(long_address(13 downto 0));
            last_ramaddress <= std_logic_vector(long_address(13 downto 0));
          end if;
          
          -- Load colour RAM at the same time
          long_address(15 downto 0) := colour_ram_base+next_card_number;
          colourramaddress <= std_logic_vector(long_address(15 downto 0));
        when 1 =>

          -- source bitmap data from ROM when necessary.
          -- Character set ROM is only visible in first 64KB of RAM.
          if (last_ramaddress(13)='0') and
             (last_ramaddress(11 downto 9) = "001") then
            character_data_from_rom <= '1';
            report "CHARROM: reading from ROM" severity note;
          else
            character_data_from_rom <= '0';
            report "CHARROM: reading from     RAM" severity note;
            report "last_ramaddress=%" & to_string(last_ramaddress) severity note;
          end if;

          -- If using 16-bit chars, ask for the 2nd byte, else
          -- idle FIFO output.
          if sixteenbit_charset='0' then
            screen_ram_fifo_readnext <= '0';            
          end if;

        when 2 =>

          -- We definitely don't need to schedule more reading from the FIFO
          -- for the rest of this character.
          screen_ram_fifo_readnext <= '0';            

          -- record pre-fetched character data.
          next_next_glyph_number(7 downto 0) <= screen_ram_fifo_dout;
          next_next_glyph_number(15 downto 8) <= x"00";
          next_next_bitmap_colours <= screen_ram_fifo_dout;

          -- Store colour byte (will
          -- transfer and decode next cycle to keep logic shallow)
          next_glyph_colour_buffer_temp <= colourramdata;

          -- There is nothing more we can do right now.
          ramaddress <= (others => '0');          
        when 3 =>
          -- finish driving out the colour value
          next_glyph_colour_buffer <= next_glyph_colour_buffer_temp;

          -- Read out custom character set data
          next_glyph_chardata <= ramdata;          

          -- FIFO has advanced to next screen ram character now after the 1
          -- cycle latency, so if we are using a 16bit char set, then we can
          -- grab those bits now.  We already asked the FIFO to advance the
          -- extra step, so nothing else is required just now.
          if sixteenbit_charset='1' and text_mode='1' then
            next_next_glyph_number(15 downto 8) <= screen_ram_fifo_dout;
          end if;
          
          -- Fetch character ROM byte
          if extended_background_mode='1' then
            -- bit 6 and 7 of character is used for colour
            charaddress(10 downto 9) <= "00";
            if text_mode='1' then
              charaddress(8 downto 3) <= std_logic_vector(next_glyph_number(5 downto 0));
            else
              charaddress(8 downto 3) <= std_logic_vector(next_card_number(5 downto 0));            
            end if;
          else
            if text_mode='1' then
              charaddress(10 downto 3) <= std_logic_vector(next_glyph_number(7 downto 0));
            else
              charaddress(10 downto 3) <= std_logic_vector(next_card_number(7 downto 0));
            end if;
          end if;
          charaddress(2 downto 0) <= std_logic_vector(chargen_y);

        when 4 =>
          -- Read out custom character set data
          if chargen_y(2)='1' then
            next_glyph_chardata(31 downto 0) <= next_glyph_chardata(63 downto 32);
          end if;         
          
          -- Decode colour byte
          next_glyph_colour <= unsigned(next_glyph_colour_buffer(3 downto 0));
          next_glyph_attributes <= unsigned(next_glyph_colour_buffer(7 downto 4));

          -- Nothing else to fetch yet
          ramaddress <= (others => '0');
        when 5 =>
          report "next_glyph_nunber=" & integer'image(to_integer(next_glyph_number)) severity note;

          if chargen_y(1)='1' then
            next_glyph_chardata(15 downto 0) <= next_glyph_chardata(31 downto 16);
          end if;

          -- Pre-calculate the extended character attributes
          next_glyph_visible <= '1';
          next_glyph_reverse <= '0';
          next_glyph_bold <= '0';
          next_glyph_underline <= '0';

          if viciii_extended_attributes='1' then
            if next_glyph_attributes(0)='1' then
              -- Blinking glyph
              if next_glyph_attributes(1)='1'
                or next_glyph_attributes(2)='1'
                or next_glyph_attributes(3)='1' then
                -- Blinking attributes
                if viciii_blink_phase='1' then
                  next_glyph_reverse <= next_glyph_attributes(1);
                  next_glyph_bold <= next_glyph_attributes(2);
                  if chargen_y(2 downto 0)="111" then
                    next_glyph_underline <= next_glyph_attributes(3);
                  end if;
                end if;
              else
                -- Just plain blinking character
                next_glyph_visible <= viciii_blink_phase;
              end if;
            else
              -- Non-blinking attributes
              next_glyph_visible <= '1';
              next_glyph_reverse <= next_glyph_attributes(1);
              next_glyph_bold <= next_glyph_attributes(2);
              if chargen_y(2 downto 0)="111" then
                next_glyph_underline <= next_glyph_attributes(3);
              end if;
            end if;
          end if;

          -- Character pixels (only 8 bits used if not in full colour mode)
          if fullcolour_8bitchars='0' and fullcolour_extendedchars='0' then
            long_address(16 downto 0) := character_set_address(16 downto 0)+(next_glyph_number(7 downto 0)&chargen_y);
          elsif fullcolour_8bitchars='0' and fullcolour_extendedchars='1' then
            if next_glyph_number<256 then
              long_address(16 downto 0) := character_set_address(16 downto 0)+(next_glyph_number(10 downto 0)&chargen_y);
              next_glyph_full_colour <= '0';
            else
              -- Full colour characters are direct mapped in memory on 64 byte
              -- boundaries.
              long_address(16 downto 0) :=
                next_glyph_number(10 downto 0)&chargen_y&"000";
              next_glyph_full_colour <= '1';
            end if;
          else
            -- if fullcolour_8bitchars='1' then all chars are full-colour          
            -- Full colour characters are direct mapped in memory on 64 byte
            -- boundaries.
            long_address(16 downto 0) :=
              next_glyph_number(10 downto 0)&chargen_y&"000";
            next_glyph_full_colour <= '1';
          end if;
          -- Request full colour pixel data
          ramaddress <= std_logic_vector(long_address(16 downto 3));
        when 6 =>
          if chargen_y(0)='1' then
            next_glyph_chardata(7 downto 0) <= next_glyph_chardata(15 downto 8);
          end if;

          -- Nothing to do here
          ramaddress <= (others => '0');
        when 7 =>
          -- Read character row data from ROM
          -- mono characters
          -- Apply C65/VIC-III hardware underline and blink attributes
          if next_glyph_visible='0' then
            charrow <= x"00";
            glyph_pixeldata <= (others => '0');
          elsif next_glyph_underline='1' then
            charrow <= x"FF";
            glyph_pixeldata <= (others => '1');
          elsif next_glyph_reverse='1' then
            if character_data_from_rom='1' then
              charrow <= not chardata;
            else
              charrow <= not next_glyph_chardata(7 downto 0);
            end if;
            glyph_pixeldata <= not ramdata;
          else
            if character_data_from_rom='1' then
              charrow <= chardata;
            else
              charrow <= next_glyph_chardata(7 downto 0);
            end if;
            glyph_pixeldata <= ramdata;
          end if;
          report "charrow loaded. chardata=$" & to_hstring(chardata) severity note;

          -- transfer pre-fetched glyph and bitmap data ready for use.
          next_bitmap_colours <= next_next_bitmap_colours;
          next_glyph_number <= next_next_glyph_number;
          
          -- Nothing to do here
          ramaddress <= (others => '0');
        when 16 =>
          -- Idle: can fetch full-colour sprite information
          -- (C64 compatability sprites will be fetched during horizontal sync.
          --  Because we can fetch 64bits at once, compatibility sprite fetching
          --  cannot require more than 16 cycles).
          ramaddress <= (others => '0');

        when 32 =>
          -- Fetch screen ram bytes (badline-like fetches).
          -- These happen in the horizontal front porch, and require not more
          -- than 32 cycles.
          -- Draining can be accomplished by resetting the fifo.
          screen_ram_fifo_reset <= '1';
          screen_ram_fifo_readnext <= '0';
          screen_ram_fifo_write <= '0';
          screen_ram_fifo_fetched <= 0;
          char_fetch_cycle <= 33;
          report "BADLINE preparing for fetch" severity note;
        when 33 =>
          report "BADLINE releasing FIFO reset" severity note;
          screen_ram_fifo_reset <= '0';
          char_fetch_cycle <= 34;
          delay <= "11";
        when 34 =>
          -- Schedule reading of next 8 chars
          report "BADLINE fetch loop.  delay=%" & to_string(delay) severity note;
          ramaddress <= std_logic_vector(screen_row_current_address(16 downto 3));
          screen_row_current_address <= screen_row_current_address + 8;
          
          delay <= delay(0) & "0";
          if delay = "00" then
            -- data is available
            -- we want 480 bytes, to allow for full 240 column text with 16-bit
            -- charset.  Bus is 64bits wide, so we need 480/8 = 60 fetches
            if screen_ram_fifo_fetched /= 60 then
              -- FIFO byte order is opposite-endian to what we would like, so
              -- we need to reverse the byte (but not bit) order.
              screen_ram_fifo_din <= unsigned(ramdata(7 downto 0)&ramdata(15 downto 8)&ramdata(23 downto 16)&ramdata(31 downto 24)
                                              &ramdata(39 downto 32)&ramdata(47 downto 40)&ramdata(55 downto 48)&ramdata(63 downto 56));
              screen_ram_fifo_write <= '1';
              report "BADLINE stuffing fetch " & integer'image(screen_ram_fifo_fetched) & " $" & to_hstring(ramdata) severity note;
              screen_ram_fifo_fetched <= screen_ram_fifo_fetched + 1;
            else
              screen_ram_fifo_write <= '0';
              -- Finished fetching screen data, move on to sprites
              char_fetch_cycle <= 35;
            end if;
          end if;
        when 35 =>
          -- Begin fetching the glyph number for the first character of the
          -- row, because the fetch process plus character resolution takes
          -- more than 8 cycles.  So instead, we pipeline this out further,
          -- fetching the first gylph number early, and then request the next
          -- glyph number while processing the previous one.         
          screen_ram_fifo_readnext <= '1';
          char_fetch_cycle <= 36;
        when 36 =>
          -- if using a 16 bit character set, ask for the 2nd byte, while still
          -- waiting for the first byte to arrive from the FIFO.
          if (sixteenbit_charset='1') and (text_mode='1') then
            screen_ram_fifo_readnext <= '1';
          else
            screen_ram_fifo_readnext <= '0';            
          end if;
          char_fetch_cycle <= 37;
        when 37 =>
          -- Stop asking for bytes from the FIFO, and record the first byte
          screen_ram_fifo_readnext <= '0';            
          next_glyph_number(7 downto 0) <= screen_ram_fifo_dout;
          next_bitmap_colours <= screen_ram_fifo_dout;
          char_fetch_cycle <= 38;
        when 38 =>
          -- Record the 2nd byte or zero out the top bits of the next character
          -- number.
          if (sixteenbit_charset='1') and (text_mode='1') then
            next_glyph_number(15 downto 8) <= screen_ram_fifo_dout;
          else
            next_glyph_number(15 downto 8) <= x"00";
          end if;
          -- all done.
          char_fetch_cycle <= 64;
        when 64 =>
          -- XXX Fetch VIC-II sprite information
          -- (C64 compatability sprites will be fetched during horizontal sync.
          --  Because we can fetch 64bits at once, compatibility sprite fetching
          --  cannot require more than 16 cycles).
          ramaddress <= (others => '0');
        when others => 
          -- XXX Fetch full-colour sprite information
          -- (C64 compatability sprites will be fetched during horizontal sync.
          --  Because we can fetch 64bits at once, compatibility sprite fetching
          --  cannot require more than 16 cycles).
          ramaddress <= (others => '0');
      end case;

      card_fg_colour(7 downto 4) := "0000";
      -- "Bold" as for VIC-III. Simply adds 16 to the colour
      card_fg_colour(4) := glyph_bold;
      card_fg_colour(3 downto 0) := glyph_colour_t3;
      card_bg_colour := screen_colour;
      
      if extended_background_mode='1' then
        -- XXX Until we support reading screen memory, use card number
        -- as the source of the extended background colour
        case card_number_t3(7 downto 6) is
          when "00" => card_bg_colour := screen_colour;
          when "01" => card_bg_colour := multi1_colour;
          when "10" => card_bg_colour := multi2_colour;
          when "11" => card_bg_colour := multi3_colour;
          when others => null;
        end case;
      end if;

      -- Calculate pixel bit/bits for next cycle to keep logic depth shallow
      multicolour_bits(0) <= charrow_t2(to_integer((not chargen_x_t2(2 downto 1))&'0'));
      multicolour_bits(1) <= charrow_t2(to_integer((not chargen_x_t2(2 downto 1))&'1'));
      monobit <= charrow_t2(to_integer(not chargen_x_t2(2 downto 0)));
      
      if indisplay_t3='1' then
        if inborder_t2='1' or blank='1' then
          report "VGA: no character pixel data as in the border" severity note;
          pixel_colour <= border_colour;
        elsif chargen_active='0' then
          pixel_colour <= screen_colour;
          report "VGA: no character pixel data as chargen_active=0" severity note;
        elsif (fullcolour_extendedchars='1' and text_mode='1' and card_number_is_extended='1')
          or (fullcolour_8bitchars='1' and text_mode='1') then
          -- Full colour glyph
          -- Pixels come from each 8 bits of character memory.
          pixel_colour <= unsigned(glyph_pixeldata(7 downto 0));
          if chargen_x_t1 /= chargen_x and chargen_x /= 7 then
            glyph_pixeldata(55 downto 0) <= glyph_pixeldata(63 downto 8);
          end if;
        elsif multicolour_mode='1' and text_mode='1' and card_fg_colour(3)='1' then
          -- Multicolour character mode only engages for characters with bit 3
          -- of their foreground colour set, and only allows use of first 8 colours
          -- for the foreground.
          case multicolour_bits is
            when "00" => pixel_colour <= card_bg_colour;
            when "01" => pixel_colour <= multi1_colour;
            when "10" => pixel_colour <= multi2_colour;
            when "11" => pixel_colour <= "0"&card_fg_colour(2 downto 0);
            when others => pixel_colour <= card_bg_colour;
          end case;
        elsif multicolour_mode='1' and text_mode='1' and card_fg_colour(3)='0' then
          -- Multicolour character mode only engages for characters with bit 3
          -- of their foreground colour set, so this char is mono
          case mono_bit is
            when "0" => pixel_colour <= card_bg_colour;
            when "1" => pixel_colour <= card_fg_colour;
            when others => pixel_colour <= card_bg_colour;
          end case;
        elsif multicolour_mode='1' and text_mode='0' then
          -- Multicolour bitmap mode.
          -- XXX Not yet implemented
          case multicolour_bits is
            when "00" => pixel_colour <= card_bg_colour;
            when "01" => pixel_colour <= "0000"&card_number_t3(7 downto 4);
            when "10" => pixel_colour <= "0000"&card_number_t3(3 downto 0);
            when "11" => pixel_colour <= card_fg_colour;
            when others => pixel_colour <= card_bg_colour;
          end case;
        elsif multicolour_mode='0' and text_mode='1' then
          -- normal text mode
          if monobit = '1' then
            pixel_colour(7 downto 5) <= "000";
            pixel_colour(4 downto 0) <= card_fg_colour(4 downto 0);
          else
            pixel_colour(7 downto 4) <= "0000";
            pixel_colour(3 downto 0) <= card_bg_colour(3 downto 0);
          end if;
        elsif multicolour_mode='0' then
          -- hires/bi-colour bitmap mode
          if monobit = '1' then
            pixel_colour(7 downto 5) <= "000";
            pixel_colour(4 downto 0) <= card_fg_colour(4) & bitmap_colours(7 downto 4);
          else
            pixel_colour(7 downto 4) <= "0000";
            pixel_colour(3 downto 0) <= bitmap_colours(3 downto 0);
          end if;
        else
          pixel_colour <= card_bg_colour;
        end if;
      else
        pixel_colour <= x"00";
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
      glyph_colour_t3 <= glyph_colour_t2;
      glyph_colour_t2 <= glyph_colour_t1;
      glyph_colour_t1 <= glyph_colour;

      if displayx=debug_x and displayy=debug_y then
        debug_next_card_number <= next_card_number;
        debug_cycles_to_next_card <= cycles_to_next_card;
        debug_chargen_active <= chargen_active;
        debug_chargen_active_soon <= chargen_active_soon;
        debug_char_fetch_cycle <= char_fetch_cycle;
        debug_charrow <= charrow;
        debug_charaddress <= charaddress;
        debug_character_data_from_rom <= character_data_from_rom;
      end if;     
      if displayx=debug_x or displayy=debug_y then
        -- Draw cross-hairs at debug coordinates
        pixel_colour <= x"02";
      end if;     
      
      -- Pixels have a two cycle pipeline to help keep timing contraints:

      report "PIXEL (" & integer'image(to_integer(displayx)) & "," & integer'image(to_integer(displayy)) & ") = $"
        & to_hstring(pixel_colour) severity note;
      
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
        vgared <= vga_buffer_red(3 downto 0);
        vgagreen <= vga_buffer_green(3 downto 0);
        vgablue <= vga_buffer_blue(3 downto 0);
      end if;
    end if;
  end process;

end Behavioral;

