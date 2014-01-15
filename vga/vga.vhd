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

entity vga is
  Port (
    ----------------------------------------------------------------------
    -- dot clock
    ----------------------------------------------------------------------
    pixelclock : in  STD_LOGIC;
    ----------------------------------------------------------------------
    -- CPU clock (used for fastram and fastio interfaces)
    ----------------------------------------------------------------------
    cpuclock : in std_logic;

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
    fastram_read : IN STD_LOGIC;
    fastram_write : IN STD_LOGIC;
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
    fastio_rdata : out std_logic_vector(7 downto 0)
    );
end vga;

architecture Behavioral of vga is

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
    
  -- Buffer VGA signal to save some time. Similarly pipeline
  -- palette lookup.
  signal vga_buffer_red : UNSIGNED (3 downto 0) := (others => '0');
  signal vga_buffer_green : UNSIGNED (3 downto 0) := (others => '0');
  signal vga_buffer_blue : UNSIGNED (3 downto 0) := (others => '0');
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
  
  constant frame_height : integer := 1242;
  constant frame_v_front : integer := 1;
  constant frame_v_syncheight : integer := 3;
  
  -- Frame generator counters
  signal xcounter : unsigned(11 downto 0) := (others => '0');
  signal ycounter : unsigned(11 downto 0) := (others => '0');
  
  -- Actual pixel positions in the frame
  signal displayx : unsigned(11 downto 0) := (others => '0');
  signal displayy : unsigned(11 downto 0) := (others => '0');
  signal display_active : std_logic := '0';
  
  
  -----------------------------------------------------------------------------
  -- Video controller registers
  -----------------------------------------------------------------------------

  -- New control registers
  -- Number added to card number for each row of characters, i.e., virtual
  -- character display width.
  signal virtual_row_width : unsigned(15 downto 0) := to_unsigned(40,16);
  -- Each character pixel will be (n+1) pixels wide  
  signal chargen_x_scale : unsigned(7 downto 0) := x"04";
  -- Each character pixel will be (n+1) pixels high
  signal chargen_y_scale : unsigned(7 downto 0) := x"04";
  -- smooth scrolling position in natural pixels.
  -- Set in the same way as the border
  signal x_chargen_start : unsigned(11 downto 0) := to_unsigned(160,12);
  signal y_chargen_start : unsigned(11 downto 0) := to_unsigned(99,12);
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
  signal border_x_left : unsigned(11 downto 0) := to_unsigned(160,12);
  signal border_x_right : unsigned(11 downto 0) := to_unsigned(1920-160,12);
  signal border_y_top : unsigned(11 downto 0) := to_unsigned(100,12);
  signal border_y_bottom : unsigned(11 downto 0) := to_unsigned(1200-101,12);
  signal blank : std_logic := '0';

  -- Colour registers ($D020 - $D024)
  signal screen_colour : unsigned(7 downto 0) := x"06";  -- dark blue centre
  signal border_colour : unsigned(7 downto 0) := x"0e";  -- light blue border
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
  signal thirtyninecolumns : std_logic := '0';
  signal vicii_raster : std_logic_vector(8 downto 0);
  signal vicii_raster_compare : std_logic_vector(8 downto 0);
  signal vicii_x_smoothscroll : std_logic_vector(2 downto 0);
  signal vicii_y_smoothscroll : std_logic_vector(2 downto 0);
  signal vicii_sprite_enables : std_logic_vector(7 downto 0);
  signal vicii_sprite_xmsbs : std_logic_vector(7 downto 0);
  signal vicii_sprite_x_expand : std_logic_vector(7 downto 0);
  signal vicii_sprite_y_expand : std_logic_vector(7 downto 0);
  signal vicii_sprite_priorty_bits : std_logic_vector(7 downto 0);
  signal vicii_sprite_multicolour_bits : std_logic_vector(7 downto 0);
  signal vicii_sprite_sprite_colissions : std_logic_vector(7 downto 0);
  signal vicii_sprite_bitmap_colissions : std_logic_vector(7 downto 0);
  signal vicii_screen_address : std_logic_vector(7 downto 0);
  signal irq_asserted : std_logic := '0';
  signal irq_colissionspritesprite : std_logic := '0';
  signal irq_colissionspritebitmap : std_logic := '0';
  signal irq_raster : std_logic := '0';
  signal mask_colissionspritesprite : std_logic := '0';
  signal mask_colissionspritebitmap : std_logic := '0';
  signal mask_raster : std_logic := '0';
  
  -- NOTE: The following registers require 64-bit alignment. Default addresses
  -- are fairly arbitrary.
  -- Colour RAM offset (we just use some normal RAM for colour RAM, since in the
  -- worst case we can need >32KB of it.  Must correspond to a FastRAM address,
  -- so the MSBs are irrelevant.
  signal colour_ram_base : unsigned(27 downto 0) := x"0005000";
  -- Screen RAM offset
  signal screen_ram_base : unsigned(27 downto 0) := x"0001000";
  -- Character set address.
  -- Size of character set depends on resolution of characters, and whether
  -- full-colour characters are enabled.
  signal character_set_address : unsigned(27 downto 0) := x"0009000";
  -----------------------------------------------------------------------------
  
  -- Character generator state. Also used for graphics modes, since graphics
  -- modes on the C64 are all card-based, anyway.
  signal card_number : unsigned(15 downto 0) := x"0000";
  signal card_number_is_extended : std_logic;  -- set if card_number > $00FF
  signal first_card_of_row : unsigned(15 downto 0);
  -- coordinates after applying the above scaling factors
  signal chargen_x : unsigned(2 downto 0) := (others => '0');
  signal chargen_y : unsigned(11 downto 0) := (others => '0');
  -- fractional pixel position for scaling
  signal chargen_y_sub : unsigned(4 downto 0);
  signal chargen_x_sub : unsigned(4 downto 0);
  -- character data fetch FSM
  signal char_fetch_cycle : integer := 0;
  -- data for next card
  signal next_glyph_number : unsigned(15 downto 0);
  signal next_glyph_number8 : unsigned(15 downto 0);
  signal next_glyph_number16 : unsigned(15 downto 0);
  signal next_glyph_colour : unsigned(7 downto 0);
  signal next_glyph_pixeldata : std_logic_vector(63 downto 0);
  signal next_glyph_number_buffer : std_logic_vector(63 downto 0);
  signal next_glyph_colour_buffer : std_logic_vector(63 downto 0);
  signal next_glyph_full_colour : std_logic;
  signal next_chargen_x : unsigned(2 downto 0) := (others => '0');

  -- data for current card
  signal glyph_number : unsigned(15 downto 0);
  signal glyph_colour : unsigned(7 downto 0);
  signal glyph_pixeldata : std_logic_vector(63 downto 0);
  signal glyph_full_colour : std_logic;
  
  -- Delayed versions of signals to allow character fetching pipeline
  signal chargen_x_t1 : unsigned(2 downto 0) := (others => '0');
  signal chargen_x_t2 : unsigned(2 downto 0) := (others => '0');
  signal chargen_x_t3 : unsigned(2 downto 0) := (others => '0');
  signal card_number_t1 : unsigned(15 downto 0) := (others => '0');
  signal card_number_t2 : unsigned(15 downto 0) := (others => '0');
  signal card_number_t3 : unsigned(15 downto 0) := (others => '0');
  signal indisplay_t1 : std_logic := '0';
  signal indisplay_t2 : std_logic := '0';
  signal indisplay_t3 : std_logic := '0';
  signal next_card_number : unsigned(15 downto 0) := (others => '0');
  signal cycles_to_next_card : unsigned(7 downto 0);
  
  signal reset : std_logic := '0';
  
  -- Interface to character generator rom
  signal charaddress : std_logic_vector(11 downto 0);
  signal chardata : std_logic_vector(7 downto 0);
  -- buffer of read data to improve timing
  signal charrow : std_logic_vector(7 downto 0);
  signal charread : std_logic := '0';   -- if 1, we are reading and need to
                                        -- store the value.
  
  type rgb is
  record
    red   : unsigned(7 downto 0);
    green : unsigned(7 downto 0);
    blue  : unsigned(7 downto 0);
  end record;
  type rgb_palette is array(0 to 255) of rgb;
  signal palette : rgb_palette := (
    -- Default C64 palette from unusedino.de/ec64/technical/misc/vic656x/colors/
    -- looked too gammad, so now using the C65 values, which I know will be a bit
    -- too bold.  Compromise is to use the "PAL corrected C65 palette" proposed
    -- at
    -- http://www.lemon64.com/forum/viewtopic.php?t=38987&sid=1368bf8d473afcaba988ebb2f00f8534
    0 => ( red => x"00", green => x"00", blue => x"00"),
    1 => ( red => x"ff", green => x"ff", blue => x"ff"),
    2 => ( red => x"ab", green => x"31", blue => x"26"),
    3 => ( red => x"66", green => x"da", blue => x"ff"),
    4 => ( red => x"bb", green => x"3f", blue => x"b8"),
    5 => ( red => x"55", green => x"ce", blue => x"58"),
    6 => ( red => x"1d", green => x"0e", blue => x"97"),
    7 => ( red => x"ea", green => x"f5", blue => x"7c"),
    8 => ( red => x"b9", green => x"74", blue => x"18"),
    9 => ( red => x"78", green => x"73", blue => x"00"),
    10 => ( red => x"dd", green => x"93", blue => x"87"),
    11 => ( red => x"5b", green => x"5b", blue => x"5b"),
    12 => ( red => x"8b", green => x"8b", blue => x"8b"),
    13 => ( red => x"b0", green => x"f4", blue => x"ac"),
    14 => ( red => x"aa", green => x"9d", blue => x"ef"),
    15 => ( red => x"b8", green => x"b8", blue => x"b8"),
    others => ( red => x"00", green => x"00", blue => x"00")
    );
  
  -- Border generation signals
  -- (see video registers section for the registers that define the border size)
  signal inborder : std_logic;
  signal inborder_t1 : std_logic;
  signal inborder_t2 : std_logic;
  signal inborder_t3 : std_logic;
  signal xfrontporch : std_logic;
  signal xbackporch : std_logic;

  signal ramaddress : std_logic_vector(13 downto 0);
  signal ramdata : std_logic_vector(63 downto 0);

  -- Precalculated mono/multicolour pixel bits
  signal multicolour_bits : std_logic_vector(1 downto 0) := (others => '0');
  signal monobit : std_logic := '0';
  
begin

    -- XXX For now just use 128KB FastRAM instead of 512KB which causes major routing
  -- headaches.
  fastram1 : component ram64x16k
    PORT MAP (
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
  
  charrom1 : charrom
    port map (Clk => pixelclock,
              address => charaddress,
              we => '0',  -- read
              cs => '1',  -- active
              data_i => (others => '1'),
              data_o => chardata
              );

  process(cpuclock) is
    variable register_bank : unsigned(7 downto 0);
    variable register_page : unsigned(3 downto 0);
    variable register_num : unsigned(7 downto 0);
    variable register_number : unsigned(11 downto 0);
  begin

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
      report "IO access resolves to video register number " & integer'image(to_integer(register_number)) severity note;        
    elsif (register_bank = x"D1" or register_bank = x"D3") and register_page<4 then
      register_number(11 downto 10) := "00";
      register_number(9 downto 8) := register_page(1 downto 0);
      register_number(7 downto 0) := register_num;
      report "IO access resolves to video register number " & integer'image(to_integer(register_number)) severity note;
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
        fastio_rdata(7) <= vicii_raster(8);
        fastio_rdata(6) <= extended_background_mode;
        fastio_rdata(5) <= not text_mode;
        fastio_rdata(4) <= not blank;
        fastio_rdata(3) <= not twentyfourlines;
        fastio_rdata(2 downto 0) <= vicii_y_smoothscroll;
      elsif register_number=18 then          -- $D012 current raster low 8 bits
        fastio_rdata <= vicii_raster(7 downto 0);
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
        fastio_rdata(3) <= not thirtyninecolumns;
        fastio_rdata(2 downto 0) <= vicii_x_smoothscroll;
      elsif register_number=23 then          -- $D017 compatibility sprite enable
        fastio_rdata <= vicii_sprite_y_expand;
      elsif register_number=24 then          -- $D018 compatibility RAM addresses
        fastio_rdata <= vicii_screen_address;
      elsif register_number=25 then          -- $D019 compatibility IRQ bits
        fastio_rdata(7) <= irq_asserted;
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
        -- Skip $D02F - $D03F to avoid real C65/C128 programs trying to
        -- fiddle with registers in this range.
        -- NEW VIDEO REGISTERS
        -- ($D040 - $D047 is the same as VIC-III DAT ports on C65.
        --  This is tolerable, since the registers most likely used to detect a
        --  C65 are made non-functional.  See:
        -- http://www.devili.iki.fi/Computers/Commodore/C65/System_Specification/Chapter_2/page101.html
        -- http://www.devili.iki.fi/Computers/Commodore/C65/System_Specification/Chapter_2/page102.html
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
        fastio_rdata(7 downto 4) <= x"0";
        fastio_rdata(3 downto 0) <= std_logic_vector(ycounter(11 downto 8));
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
      elsif register_number=128 then
        fastio_rdata <= std_logic_vector(screen_ram_base(7 downto 0));
      elsif register_number=129 then
        fastio_rdata <= std_logic_vector(screen_ram_base(15 downto 8));
      elsif register_number=130 then
        fastio_rdata <= std_logic_vector(screen_ram_base(23 downto 16));
      elsif register_number=131 then
        fastio_rdata(7 downto 4) <= x"0";
        fastio_rdata(3 downto 0) <= std_logic_vector(screen_ram_base(27 downto 24));
      elsif register_number=132 then
        fastio_rdata <= std_logic_vector(colour_ram_base(7 downto 0));
      elsif register_number=133 then
        fastio_rdata <= std_logic_vector(colour_ram_base(15 downto 8));
      elsif register_number=134 then
        fastio_rdata <= std_logic_vector(colour_ram_base(23 downto 16));
      elsif register_number=135 then
        fastio_rdata(7 downto 4) <= x"0";
        fastio_rdata(3 downto 0) <= std_logic_vector(colour_ram_base(27 downto 24));
      elsif register_number=136 then
        fastio_rdata <= std_logic_vector(character_set_address(7 downto 0));
      elsif register_number=137 then
        fastio_rdata <= std_logic_vector(character_set_address(15 downto 8));
      elsif register_number=138 then
        fastio_rdata <= std_logic_vector(character_set_address(23 downto 16));
      elsif register_number=139 then
        fastio_rdata(7 downto 4) <= x"0";
        fastio_rdata(3 downto 0) <= std_logic_vector(character_set_address(27 downto 24));
      elsif register_number<256 then
        -- Fill in unused register space
        fastio_rdata <= x"ff";
        -- C65 style palette registers
      elsif register_number>=256 and register_number<512 then
        -- red palette
        fastio_rdata <= std_logic_vector(palette(to_integer(register_num)).red);
      elsif register_number>=512 and register_number<768 then
        -- green palette
        fastio_rdata <= std_logic_vector(palette(to_integer(register_num)).green);
      elsif register_number>=768 and register_number<1024 then
        -- blue palette
        fastio_rdata <= std_logic_vector(palette(to_integer(register_num)).blue);
      else
        -- report "IO request does not match a video register" severity note;
        fastio_rdata <= "ZZZZZZZZ";
      end if;
    end if;

    if rising_edge(cpuclock) then

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
          vicii_raster_compare(8) <= fastio_wdata(7);
          extended_background_mode <= fastio_wdata(6);
          text_mode <= not fastio_wdata(5);
          blank <= not fastio_wdata(4);
          twentyfourlines <= not fastio_wdata(3);
          -- set vertical borders based on twentyfourlines
          if twentyfourlines='0' then
            border_y_top <= to_unsigned(100,12);
            border_y_bottom <= to_unsigned(1200-101,12);
          else  
            border_y_top <= to_unsigned(100+(4*5),12);
            border_y_bottom <= to_unsigned(1200-101-(4*5),12);
          end if;
          vicii_y_smoothscroll <= fastio_wdata(2 downto 0);
          -- set y_chargen_start based on twentyfourlines
          y_chargen_start <= to_unsigned((99-3*5)+to_integer(unsigned(fastio_wdata(2 downto 0)))*5,12);
        elsif register_number=18 then          -- $D012 current raster low 8 bits
          vicii_raster(7 downto 0) <= fastio_wdata;
        elsif register_number=19 then          -- $D013 lightpen X (coarse rasterX)
        elsif register_number=20 then          -- $D014 lightpen Y (coarse rasterY)
        elsif register_number=21 then          -- $D015 compatibility sprite enable
          vicii_sprite_enables <= fastio_wdata;
        elsif register_number=22 then          -- $D016
          multicolour_mode <= fastio_wdata(4);
          thirtyninecolumns <= fastio_wdata(3);
          vicii_x_smoothscroll <= fastio_wdata(2 downto 0);
          -- set horizontal borders based on twentyfourlines
          if fastio_wdata(3)='0' then
            border_x_left <= to_unsigned(160,12);
            border_x_right <= to_unsigned(1920-160,12);
          else  
            border_x_left <= to_unsigned(160+(4*5),12);
            border_x_right <= to_unsigned(1920-160-(4*5),12);
          end if;
          -- set y_chargen_start based on twentyfourlines
          x_chargen_start <= to_unsigned((160-3*5)+to_integer(unsigned(fastio_wdata(2 downto 0)))*5,12);
        elsif register_number=23 then          -- $D017 compatibility sprite enable
          vicii_sprite_y_expand <= fastio_wdata;
        elsif register_number=24 then          -- $D018 compatibility RAM addresses
          vicii_screen_address <= fastio_wdata;
        elsif register_number=25 then          -- $D019 compatibility IRQ bits
          -- XXX Acknowledge IRQs
        elsif register_number=26 then          -- $D01A compatibility IRQ mask bits
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
          multi1_colour <= unsigned(fastio_wdata);
        elsif register_number=35 then
          multi2_colour <= unsigned(fastio_wdata);
        elsif register_number=36 then
          multi3_colour <= unsigned(fastio_wdata);
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
          -- ycounter
          null;
        elsif register_number=83 then
          -- ycounter
          null;
        elsif register_number=84 then
          -- $D054 (53332) - New mode control register
          fullcolour_extendedchars <= fastio_wdata(2);
          fullcolour_8bitchars <= fastio_wdata(1);
          sixteenbit_charset <= fastio_wdata(0);
        elsif register_number=128 then
          screen_ram_base(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=129 then
          screen_ram_base(15 downto 8) <= unsigned(fastio_wdata);
        elsif register_number=130 then
          screen_ram_base(23 downto 16) <= unsigned(fastio_wdata);
        elsif register_number=131 then
          screen_ram_base(27 downto 24) <= unsigned(fastio_wdata(3 downto 0));
        elsif register_number=132 then
          colour_ram_base(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=133 then
          colour_ram_base(15 downto 8) <= unsigned(fastio_wdata);
        elsif register_number=134 then
          colour_ram_base(23 downto 16) <= unsigned(fastio_wdata);
        elsif register_number=135 then
          colour_ram_base(27 downto 24) <= unsigned(fastio_wdata(3 downto 0));
        elsif register_number=136 then
          character_set_address(7 downto 0) <= unsigned(fastio_wdata);
        elsif register_number=137 then
          character_set_address(15 downto 8) <= unsigned(fastio_wdata);
        elsif register_number=138 then
          character_set_address(23 downto 16) <= unsigned(fastio_wdata);
        elsif register_number=139 then
          character_set_address(27 downto 24) <= unsigned(fastio_wdata(3 downto 0));
        elsif register_number<256 then
          -- reserved register
          null;
          -- XXX Palette registers are in a RAM, so we need to schedule the writes
          -- clocked by the pixelclock, and when we are not in frame.
          -- Downside is not being able to change the palette registers quickly.
          -- Else, we implement the palette as a lot of registers.
          -- Downside is that routing could get very bad.
          -- Else we implement the palette as dual-port RAM.  Probably the best
          -- approach.
        elsif register_number>=256 and register_number<512 then
          -- red palette
          -- palette(to_integer(register_num)).red <= unsigned(fastio_wdata);
        elsif register_number>=512 and register_number<768 then
          -- green palette
          -- palette(to_integer(register_num)).green <= unsigned(fastio_wdata);
        elsif register_number>=768 and register_number<1024 then
          -- blue palette
          -- palette(to_integer(register_num)).blue <= unsigned(fastio_wdata);
        else
          null;
        end if;
      end if;      
    end if;
    --report "fastio_rdata from video controller is "
    --  & std_logic'image(fastio_rdata(7))
    --  & std_logic'image(fastio_rdata(6))
    --  & std_logic'image(fastio_rdata(5))
    --  & std_logic'image(fastio_rdata(4))
    --  & std_logic'image(fastio_rdata(3))
    --  & std_logic'image(fastio_rdata(2))
    --  & std_logic'image(fastio_rdata(1))
    --  & std_logic'image(fastio_rdata(0))
    --  severity note;
    
  end process;
  
  process(pixelclock) is
    variable indisplay : std_logic := '0';
    variable next_chargen_y : unsigned(11 downto 0) := (others => '0');
    variable card_bg_colour : unsigned(7 downto 0) := (others => '0');
    variable card_fg_colour : unsigned(7 downto 0) := (others => '0');
    variable long_address : unsigned(31 downto 0) := (others => '0');
    variable next_glyph_number_temp : std_logic_vector(15 downto 0) := (others => '0');
    variable next_glyph_colour_temp : std_logic_vector(7 downto 0) := (others => '0');
  begin

    if rising_edge(pixelclock) then

      if xcounter>=(frame_h_front+width) and xcounter<(frame_h_front+width+frame_h_syncwidth) then
        hsync <= '0';
      else
        hsync <= '1';
      end if;
      indisplay :='1';
      if xcounter<frame_width then
        xcounter <= xcounter + 1;
      else
        xcounter <= (others => '0');
        next_chargen_x <= (others => '0');
        chargen_x_sub <= (others => '0');
        if ycounter<frame_height then
          ycounter <= ycounter + 1;
        else
          -- Start of next frame
          ycounter <= (others =>'0');
          next_chargen_y := (others => '0');
          chargen_y_sub <= (others => '0');
          next_card_number <= (others => '0');
          first_card_of_row <= (others => '0');
        end if;	
      end if;
      if xcounter<frame_h_front then
        xfrontporch <= '1';
      else
        xfrontporch <= '0';
      end if;
      if xcounter<(frame_h_front+width) then
        xbackporch <= '0';
      else
        xbackporch <= '1';
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
      inborder_t3 <= inborder_t2;

      -- Work out if the next card has a character number >255
      if next_card_number(15 downto 8) /= x"00" then
        card_number_is_extended <= '1';
      else
        card_number_is_extended <= '0';
      end if;

      -- By default, copy in replacement values
      -- These assignments may be overriden further down the process.
      chargen_x <= next_chargen_x;
      chargen_y <= next_chargen_y;
      card_number <= next_card_number;
      
      -- Reset character generator position for start of frame/raster
      if displayy<=y_chargen_start then
        chargen_y <= (others => '0');
        chargen_y_sub <= (others => '0');
      end if;
      if displayx=(x_chargen_start-8) then
        -- Start fetching first character of the row
        -- (8 cycles is plenty of time to fetch it)       
        char_fetch_cycle <= 0;
        cycles_to_next_card <= (others => '1');
      end if;
      if displayx = (x_chargen_start - 1) then
        -- trigger next card at start of chargen row
        cycles_to_next_card <= "00000010";        
        chargen_x <= (others => '0');
        chargen_x_sub <= (others => '0');
      end if;

      -- Raster control.
      -- Work out if in front porch, back porch or active part of raster.
      -- If we are in the active part of the display, work out if we have
      -- reached the start of a new character (or are about to).
      -- If so, copy in the new glyph and colour data for display.
      if xfrontporch='1' then
        displayx <= (others => '0');
        indisplay := '0';
      elsif xbackporch='0' then         -- In active part of raster
        -- Work out if we are at the end of a character
        cycles_to_next_card <= cycles_to_next_card - 1;
        -- cycles_to_next_card counts down to 1, not 0.
        -- update one cycle earlier since next_card_number is a signal
        -- not a variable.
        if cycles_to_next_card = 2 then
          -- We are one cycle before the start of a character
          next_card_number <= card_number + 1;            
        end if;
        if cycles_to_next_card = 1 then
          -- We are at the start of a character
          
          -- Reset counter to next character to 8 cycles x (scale + 1)
          cycles_to_next_card <= (chargen_x_scale(4 downto 0)+1) & "000";
          -- Move preloaded glyph data into position when advancing to the next character
          glyph_pixeldata <= next_glyph_pixeldata;
          glyph_colour <= next_glyph_colour;
          glyph_number <= next_glyph_number;
          glyph_full_colour <= next_glyph_full_colour;
          -- ... and then start fetching data for the character after that
          char_fetch_cycle <= 0;
          chargen_x <= "000";
          chargen_x_sub <= (others => '0');
          if chargen_x_scale=0
            or chargen_x_sub = (chargen_x_scale - 1)
          then
            next_chargen_x <= "001";
          end if;
        else
          -- Update current horizontal sub-pixel and pixel position
          if chargen_x_sub=chargen_x_scale then
            chargen_x_sub <= (others => '0');
          else
            chargen_x_sub <= chargen_x_sub + 1;
          end if;
          -- Work out if a new logical pixel starts on the next physical pixel
          if chargen_x_scale=0
            or chargen_x_sub = (chargen_x_scale - 1)
          then
            next_chargen_x <= chargen_x + 1;
          end if;
        end if;

        -- Increase horizonal physical pixel position
        displayx <= displayx + 1;
      else
        -- In back porch, so set displayx all high
        displayx <= (others => '1');
        indisplay := '0';
      end if;
      
      if ycounter>=(frame_v_front+height) and ycounter<(frame_v_front+height+frame_v_syncheight) then
        vsync <= '1';
      else
        vsync <= '0';
      end if;
      if xcounter = 0 then
        if ycounter<frame_v_front then
          displayy <= (others => '0');
          indisplay := '0';
          first_card_of_row <= x"0000";	
        elsif ycounter<(frame_v_front+height) then
          displayy <= displayy + 1;
          next_card_number <= first_card_of_row;
          if chargen_y_sub=chargen_y_scale then
            next_chargen_y := chargen_y + 1;
            if chargen_y(2 downto 0) = "111" then
              -- Increment card number every "bad line"
              first_card_of_row <= first_card_of_row + virtual_row_width;
              next_card_number <= first_card_of_row + virtual_row_width;
            end if;
            chargen_y_sub <= (others => '0');
          else
            chargen_y_sub <= chargen_y_sub + 1;
          end if;
        else
          displayy <= (others => '1');
          indisplay := '0';
        end if;
      end if;
      
      display_active <= indisplay;

      -- Read character row data
      if charread='1' then
        -- mono characters
        charrow <= chardata;
        -- XXX what about one byte per pixel characters?
      end if;
      
      -- As soon as we begin drawing a character, start fetching the data for the
      -- next character.  Any left over cycles can be used for updating full-colour
      -- sprite data once we implement them.
      -- We need the character number, the colour byte, and the
      -- 8x8 data bits (only 8 used if character is not in full colour mode).
      if char_fetch_cycle<16 then
        char_fetch_cycle <= char_fetch_cycle + 1;        
      end if;
      case char_fetch_cycle is
        when 0 => 
          -- Load card number
          long_address(31 downto 17) := (others => '0');
          if sixteenbit_charset='1' then
            long_address(16 downto 0) := screen_ram_base(16 downto 0)+(card_number&'0');
          else
            long_address(16 downto 0) := screen_ram_base(16 downto 0)+card_number;
          end if;
          ramaddress <= std_logic_vector(long_address(16 downto 3));
        when 1 =>
          -- FastRAM wait state
          -- XXX Can schedule a sprite fetch here.
          ramaddress <= (others => '0');
        when 2 =>
          -- Store character number
          -- In text mode, the glyph order is flexible
          next_glyph_number_buffer <= ramdata;
          -- As RAM is slow to read from, we buffer it, and then extract the
          -- right byte/word next cycle, so no more work here.

          -- XXX Can schedule a sprite fetch here.
          ramaddress <= (others => '0');
        when 3 =>
          -- Decode next character number from 64bit vector
          -- This is a bit too complex to do in a single cycle if we also have to
          -- choose the 16bit or 8 bit version.  So this cycle we calculate the
          -- 8bit and 16bit versions.  Then next cycle we can select the correct
          -- one.
          next_glyph_number_temp(15 downto 8) := x"00";
          case card_number(2 downto 0) is
            when "111" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer(63 downto 56);
            when "110" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer(55 downto 48);
            when "101" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer(47 downto 40);
            when "100" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer(39 downto 32);
            when "011" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer(31 downto 24);
            when "010" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer(23 downto 16);
            when "001" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer(15 downto  8);
            when "000" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer( 7 downto  0);
            when others => next_glyph_number_temp(7 downto 0) := x"00";
          end case;
          next_glyph_number8 <= unsigned(next_glyph_number_temp);
          case card_number(1 downto 0) is
            when "11" => next_glyph_number_temp := next_glyph_number_buffer(63 downto 48);        
            when "10" => next_glyph_number_temp := next_glyph_number_buffer(47 downto 32);        
            when "01" => next_glyph_number_temp := next_glyph_number_buffer(31 downto 16);        
            when "00" => next_glyph_number_temp := next_glyph_number_buffer(15 downto  0);        
          when others => next_glyph_number_temp := x"0000";
          end case;
          next_glyph_number16 <= unsigned(next_glyph_number_temp);

          -- XXX Can schedule a sprite fetch here.
          ramaddress <= (others => '0');
        when 4 =>
          -- Calculate the actual character number
          if sixteenbit_charset='1' then
            next_glyph_number_temp := std_logic_vector(next_glyph_number16);
          else
            next_glyph_number_temp := std_logic_vector(next_glyph_number8);
          end if;
          if text_mode='1' then
            next_glyph_number <= unsigned(next_glyph_number_temp);
          else
            next_glyph_number <= card_number;
          end if;

          -- Request colour RAM (only the relevant byte is used)
          -- 16bit charset has no effect on the colour RAM size
          long_address(31 downto 17) := (others => '0');
          long_address(16 downto 0) := colour_ram_base(16 downto 0)+unsigned(next_glyph_number_temp);
          ramaddress <= std_logic_vector(long_address(16 downto 3));
        when 5 =>
          -- Character pixels (only 8 bits used if not in full colour mode)
          if fullcolour_8bitchars='0' and fullcolour_extendedchars='0' then
            long_address(16 downto 0) := character_set_address(16 downto 0)+(next_glyph_number(7 downto 0)&chargen_y(2 downto 0));
          elsif fullcolour_8bitchars='0' and fullcolour_extendedchars='1' then
            if next_glyph_number<256 then
              long_address(16 downto 0) := character_set_address(16 downto 0)+(next_glyph_number(10 downto 0)&chargen_y(2 downto 0));
              next_glyph_full_colour <= '0';
            else
              -- Full colour characters are direct mapped in memory on 64 byte
              -- boundaries.
              long_address(16 downto 0) :=
                next_glyph_number(10 downto 0)&chargen_y(2 downto 0)&"000";
              next_glyph_full_colour <= '1';
            end if;
          else
            -- if fullcolour_8bitchars='1' then all chars are full-colour          
            -- Full colour characters are direct mapped in memory on 64 byte
            -- boundaries.
            long_address(16 downto 0) :=
              next_glyph_number(10 downto 0)&chargen_y(2 downto 0)&"000";
            next_glyph_full_colour <= '1';
          end if;
          -- Request pixel data
          ramaddress <= std_logic_vector(long_address(16 downto 3));
        when 6 =>
          -- Store colour bytes (will decode next cycle to keep logic shallow)
          next_glyph_colour_buffer <= ramdata;
          -- XXX Can schedule a sprite fetch here.
          ramaddress <= (others => '0');
        when 7 =>
          -- Decode colour byte
          case card_number(2 downto 0) is
            when "111" => next_glyph_colour_temp := next_glyph_number_buffer(63 downto 56);
            when "110" => next_glyph_colour_temp := next_glyph_number_buffer(55 downto 48);
            when "101" => next_glyph_colour_temp := next_glyph_number_buffer(47 downto 40);
            when "100" => next_glyph_colour_temp := next_glyph_number_buffer(39 downto 32);
            when "011" => next_glyph_colour_temp := next_glyph_number_buffer(31 downto 24);
            when "010" => next_glyph_colour_temp := next_glyph_number_buffer(23 downto 16);
            when "001" => next_glyph_colour_temp := next_glyph_number_buffer(15 downto  8);
            when "000" => next_glyph_colour_temp := next_glyph_number_buffer( 7 downto  0);
            when others => next_glyph_colour_temp := x"00";
          end case;
          next_glyph_colour <= unsigned(next_glyph_colour_temp);
          -- Store character pixels
          next_glyph_pixeldata <= ramdata;
          -- XXX Fetch full-colour sprite information
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

      -- When moving to the next card read the appropriate character set rom entry.
      -- Note that character set ROM has only 256 entries, so 16-bit charsets
      -- will wrap.
      -- In bitmap mode the card numbers are ordinal, whereas in textmode
      -- screen RAM picks the character.
      -- XXX Bitmap mode should not use the character ROM.  This combination is
      -- for debugging of text mode character fetching only.
      if card_number_t3 /= card_number then
        if extended_background_mode='1' then
          -- bit 6 and 7 of character is used for colour
          charaddress(10 downto 9) <= "00";
          if text_mode='1' then
            charaddress(8 downto 3) <= std_logic_vector(next_glyph_number(5 downto 0));
          else
            charaddress(8 downto 3) <= std_logic_vector(card_number(5 downto 0));            
          end if;
        else
          if text_mode='1' then
            charaddress(10 downto 3) <= std_logic_vector(next_glyph_number(7 downto 0));
          else
            charaddress(10 downto 3) <= std_logic_vector(card_number(7 downto 0));
          end if;
        end if;
        charaddress(2 downto 0) <= std_logic_vector(chargen_y(2 downto 0));
        charread <= '1';
      else
        charread <= '0';
      end if;

      -- Fetch card foreground colour from colour RAM
      card_fg_colour(7 downto 0) := glyph_colour;

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
      multicolour_bits(0) <= charrow(to_integer((not chargen_x_t2(2 downto 1))&'0'));
      multicolour_bits(1) <= charrow(to_integer((not chargen_x_t2(2 downto 1))&'1'));
      monobit <= charrow(to_integer(not chargen_x_t2(2 downto 0)));
      
      if indisplay_t3='1' then
        if inborder_t2='1' or blank='1' then
          pixel_colour <= border_colour;
        elsif (fullcolour_extendedchars='1' and text_mode='1' and card_number_is_extended='1')
          or (fullcolour_8bitchars='1' and text_mode='1') then
          -- Full colour glyph
          -- Pixels come from each 8 bits of character memory.
          pixel_colour <= unsigned(glyph_pixeldata(63 downto 56));
          if chargen_x_t1 /= chargen_x then
            glyph_pixeldata(63 downto 8) <= glyph_pixeldata(55 downto 0);
          end if;
        elsif multicolour_mode='1' and text_mode='1' and card_fg_colour(3)='1' then
          -- Multicolour character mode only engages for characters with bit 3
          -- of their foreground colour set.
          case multicolour_bits is
            when "00" => pixel_colour <= card_bg_colour;
            when "01" => pixel_colour <= multi1_colour;
            when "10" => pixel_colour <= multi2_colour;
            when "11" => pixel_colour <= card_fg_colour;
            when others => pixel_colour <= screen_colour;
          end case;
        elsif multicolour_mode='1' and text_mode='0' then
          -- Multicolour bitmap mode.
          -- XXX Not yet implemented
          pixel_colour(7 downto 4) <= "0000";
          pixel_colour(3 downto 0) <= card_number_t3(3 downto 0);
        elsif multicolour_mode='0' then
          -- hires/bi-colour mode/normal text mode
          -- XXX Still using character generator ROM for now.
          -- XXX Replace with correct byte from glyph_pixelddata
          -- once we have things settled down a bit more.
          if monobit = '1' then
            pixel_colour(7 downto 4) <= "0000";
            pixel_colour(3 downto 0) <= card_fg_colour(3 downto 0);
          else
            pixel_colour(7 downto 4) <= "0000";
            pixel_colour(3 downto 0) <= card_bg_colour(3 downto 0);
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
      card_number_t1 <= card_number;
      card_number_t2 <= card_number_t1;
      card_number_t3 <= card_number_t2;
      indisplay_t1 <= indisplay;
      indisplay_t2 <= indisplay_t1;
      indisplay_t3 <= indisplay_t2;

      -- Pixels have a two cycle pipeline to help keep timing contraints:
      
      -- 1. From pixel colour lookup RGB
      vga_buffer_red <= palette(to_integer(pixel_colour)).red(7 downto 4);   
      vga_buffer_green <= palette(to_integer(pixel_colour)).green(7 downto 4); 
      vga_buffer_blue <= palette(to_integer(pixel_colour)).blue(7 downto 4);

      -- 2. From RGB, push out to pins (also draw border)
      vgared <= vga_buffer_red;
      vgagreen <= vga_buffer_green;
      vgablue <= vga_buffer_blue;

    end if;

  end process;

end Behavioral;

