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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity vga is
  Port ( clk : in  STD_LOGIC;
         vsync : out  STD_LOGIC;
         hsync : out  STD_LOGIC;
         led0 : out std_logic;
         led1 : out std_logic;
         led2 : out std_logic;
         led3 : out std_logic;
         sw : in std_logic_vector(15 downto 0);
         btn : in std_logic_vector(4 downto 0);
         vgared : out  UNSIGNED (3 downto 0);
         vgagreen : out  UNSIGNED (3 downto 0);
         vgablue : out  UNSIGNED (3 downto 0));
end vga;

architecture Behavioral of vga is

  component pixelclock is
    port
      (-- Clock in ports
        CLK_IN1           : in     std_logic;
        -- Clock out ports
        CLK_OUT1          : out    std_logic;
        CLK_OUT2          : out    std_logic;
        CLK_OUT3          : out    std_logic;
        -- Status and control signals
        RESET             : in     std_logic;
        LOCKED            : out    std_logic
        );
  end component pixelclock;

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

  component fastram IS
    PORT (
      clka : IN STD_LOGIC;
      ena : IN STD_LOGIC;
      wea : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      addra : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
      dina : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
      douta : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
      clkb : IN STD_LOGIC;
      web : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      addrb : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
      dinb : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
      doutb : OUT STD_LOGIC_VECTOR(63 DOWNTO 0)
      );
  END component fastram;

  -- Buffer VGA signal to save some time. Similarly pipeline
  -- palette lookup.
  signal vga_buffer_red : UNSIGNED (3 downto 0);
  signal vga_buffer_green : UNSIGNED (3 downto 0);
  signal vga_buffer_blue : UNSIGNED (3 downto 0);
  signal pixel_colour : unsigned(7 downto 0);
  
  -- Video mode definition
  constant width : integer := 1600;
  constant height : integer := 1200;
  
  constant frame_width : integer := 2160;
  constant frame_h_front : integer := 64;
  constant frame_h_syncwidth : integer := 192;
  
  constant frame_height : integer := 1250;
  constant frame_v_front : integer := 1;
  constant frame_v_syncheight : integer := 3;

--  constant width : integer := 1920;
--  constant height : integer := 1200;
--  
--  constant frame_width : integer := 2592;
--  constant frame_h_front : integer := 128;
--  constant frame_h_syncwidth : integer := 208;
--  
--  constant frame_height : integer := 1242;
--  constant frame_v_front : integer := 1;
--  constant frame_v_syncheight : integer := 3;

  
  -- Frame generator counters
  signal xcounter : unsigned(11 downto 0) := (others => '0');
  signal ycounter : unsigned(11 downto 0) := (others => '0');
  
  -- Actual pixel positions in the frame
  signal displayx : unsigned(11 downto 0);
  signal displayy : unsigned(11 downto 0);
  signal display_active : std_logic;

  -----------------------------------------------------------------------------
  -- FastIO interface for accessing video registers
  -----------------------------------------------------------------------------
  signal fastio_addr : std_logic_vector(19 downto 0);
  signal fastio_read : std_logic;
  signal fastio_write : std_logic;
  signal fastio_wdata : std_logic_vector(7 downto 0);
  signal fastio_rdata : std_logic_vector(7 downto 0);
  
  -----------------------------------------------------------------------------
  -- Video controller registers
  -----------------------------------------------------------------------------

  -- New control registers
  -- Number added to card number for each row of characters, i.e., virtual
  -- character display width.
  signal virtual_row_width : unsigned(15 downto 0) := to_unsigned(40,16);
  -- Each character pixel will be (n+1) pixels wide  
  signal card_x_scale : unsigned(7 downto 0) := x"04";
  -- Each character pixel will be (n+1) pixels high
  signal card_y_scale : unsigned(7 downto 0) := x"04";
  -- smooth scrolling position in natural pixels.
  -- Set in the same way as the border
  signal x_chargen_start : unsigned(11 downto 0) := to_unsigned(160,12);
  signal y_chargen_start : unsigned(11 downto 0) := to_unsigned(100,12);
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
  signal border_x_right : unsigned(11 downto 0) := to_unsigned(1600-160,12);
  signal border_y_top : unsigned(11 downto 0) := to_unsigned(100,12);
  signal border_y_bottom : unsigned(11 downto 0) := to_unsigned(1200-101,12);

  -- Colour registers ($D020 - $D024)
  signal screen_colour : unsigned(7 downto 0) := x"06";  -- dark blue centre
  signal border_colour : unsigned(7 downto 0) := x"0e";  -- light blue border
  signal multi1_colour : unsigned(7 downto 0) := x"01";  -- multi-colour mode #1
  signal multi2_colour : unsigned(7 downto 0) := x"02";  -- multi-colour mode #2
  signal multi3_colour : unsigned(7 downto 0) := x"03";  -- multi-colour mode #3

  -- NOTE: The following registers require 64-bit alignment. Default addresses
  -- are fairly arbitrary.
  -- Colour RAM offset (we just use some normal RAM for colour RAM, since in the
  -- worst case we can need >32KB of it.  Must correspond to a FastRAM address,
  -- so the MSB is irrelevant.
  signal colour_ram_base : unsigned(27 downto 0) := x"0018000";
  -- Screen RAM offset
  signal screen_ram_base : unsigned(27 downto 0) := x"0010000";
  -- Character set address.
  -- Size of character set depends on resolution of characters, and whether
  -- full-colour characters are enabled.
  signal character_set_address : unsigned(27 downto 0) := x"0020000";
  -----------------------------------------------------------------------------
  
  -- Character generator state. Also used for graphics modes, since graphics
  -- modes on the C64 are all card-based, anyway.
  signal card_number : unsigned(15 downto 0);
  signal first_card_of_row : unsigned(15 downto 0);
  -- coordinates after applying the above scaling factors
  signal card_x : unsigned(11 downto 0);
  signal card_y : unsigned(11 downto 0);
  -- fractional pixel position for scaling
  signal card_y_sub : unsigned(7 downto 0);
  signal card_x_sub : unsigned(7 downto 0);
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
  -- data for current card
  signal glyph_number : unsigned(15 downto 0);
  signal glyph_colour : unsigned(7 downto 0);
  signal glyph_pixeldata : std_logic_vector(63 downto 0);
  signal glyph_full_colour : std_logic;
  
  -- Delayed versions of signals to allow character fetching pipeline
  signal card_x_t1 : unsigned(11 downto 0);
  signal card_x_t2 : unsigned(11 downto 0);
  signal card_x_t3 : unsigned(11 downto 0);
  signal card_number_t1 : unsigned(15 downto 0);
  signal card_number_t2 : unsigned(15 downto 0);
  signal card_number_t3 : unsigned(15 downto 0);
  signal indisplay_t1 : std_logic;
  signal indisplay_t2 : std_logic;
  signal indisplay_t3 : std_logic;
  
  signal dotclock : std_logic;
  
  signal counter : unsigned(24 downto 0);
  signal slow_clock : std_logic := '0';
  
  signal reset_counter : integer := 16;
  signal reset : std_logic := '0';
  
  -- Interface to fastram: 64bits wide
  signal ramwriteenable : std_logic_vector(7 downto 0) := (others => '0');
  signal ramaddress : std_logic_vector(15 downto 0);
  signal ramdata : std_logic_vector(63 downto 0);
  
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
  type rgb_pallete is array(0 to 255) of rgb;
  signal pallete : rgb_pallete := (
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
  
begin

  pixelclock1: component pixelclock
    port map ( clk_in1 => clk,
               reset => reset,					  
                                        -- CLK_OUT2 is good for 1920x1200@60Hz, CLK_OUT3
                                        -- for 1600x1200@60Hz
                                        -- 60Hz works fine, but 50Hz is not well supported by monitors.
                                        -- so I guess we will go with an NTSC-style 60Hz display.
                                        -- For C64 mode it would be nice to have PAL or NTSC selectable.
                                        -- Perhaps consider a different video mode for that, or buffer
                                        -- the generated frames somewhere?
               clk_out3 => dotclock); 
  
  charrom1 : charrom
    port map (Clk => dotclock,
              address => charaddress,
              we => '0',  -- read
              cs => '1',  -- active
              data_i => (others => '1'),
              data_o => chardata
              );

  fastram1 : component fastram
    PORT MAP (
      -- XXX both ports require a clock.  Use this here until we pull the CPU in.
      clka => dotclock,
      ena => '0',
      wea => (others => '0'),
      addra => ( others => '0'),
      dina => (others => '0'),
      -- We use port b of the dual-port fast ram.
      -- The CPU uses port a
      clkb => dotclock,
      web => ramwriteenable,
      addrb => ramaddress,
      dinb => (others => '0'),
      doutb => ramdata
      );

  process(dotclock) is
    variable indisplay : std_logic;
    variable next_card_number : unsigned(15 downto 0);
    variable next_card_x : unsigned(11 downto 0);
    variable next_card_y : unsigned(11 downto 0);
    variable multicolour_bits : std_logic_vector(1 downto 0);
    variable card_bg_colour : unsigned(7 downto 0);
    variable card_fg_colour : unsigned(7 downto 0);
    variable long_address : unsigned(31 downto 0);
    variable next_glyph_number_temp : std_logic_vector(15 downto 0);
    variable next_glyph_colour_temp : std_logic_vector(7 downto 0);
  begin
    if rising_edge(dotclock) then

      -- Allow fiddling of scale by switching switches
      card_x_scale(3 downto 0) <= unsigned(sw(7 downto 4));
      card_y_scale(3 downto 0) <= unsigned(sw(3 downto 0));
      -- And video mode
      multicolour_mode <= sw(8);
      extended_background_mode <= sw(9);
      text_mode <= sw(10);
      sixteenbit_charset <= sw(11);
      fullcolour_8bitchars <= sw(12);
      fullcolour_extendedchars <= sw(13);
      -- And adjust screen length
      case sw(15 downto 14) is
        when "00" => virtual_row_width <= to_unsigned(32,16);
        when "01" => virtual_row_width <= to_unsigned(40,16);
        when "10" => virtual_row_width <= to_unsigned(108,16);
        when "11" => virtual_row_width <= to_unsigned(256,16);
        when others => null;
      end case;
      
      counter <= counter + 1;
      if counter = x"000000" then
        slow_clock <= not slow_clock;
        led3 <= slow_clock;
        if btn(0) = '1' then
          -- Right button: trim smooth scrolling right a pixel
          x_chargen_start <= x_chargen_start + 1;
        end if;
        if btn(1) = '1' then
          -- Down button: trim smooth scrolling down a pixel
          y_chargen_start <= y_chargen_start + 1;
        end if;
        if btn(2) = '1' then
          -- Up button: trim smooth scrolling right a pixel
          y_chargen_start <= y_chargen_start - 1;
        end if;
        if btn(3) = '1' then
          -- Left button: trim smooth scrolling right a pixel
          x_chargen_start <= x_chargen_start - 1;
        end if;
        if btn(4) = '1' then
          x_chargen_start <= to_unsigned(160,12); 
          y_chargen_start <= to_unsigned(100,12);  
        end if;
      end if;
      if xcounter>=(frame_h_front+width) and xcounter<(frame_h_front+width+frame_h_syncwidth) then
        hsync <= '0';
        led0 <= '0';
      else
        hsync <= '1';
        led0 <= '1';
      end if;
      indisplay :='1';
      if xcounter<frame_width then
        xcounter <= xcounter + 1;
      else
        xcounter <= (others => '0');
        next_card_x := (others => '0');
        card_x_sub <= (others => '0');
        if ycounter<frame_height then
          ycounter <= ycounter + 1;
        else
          -- Start of next frame
          ycounter <= (others =>'0');
          next_card_y := (others => '0');
          card_y_sub <= (others => '0');
          next_card_number := (others => '0');
          first_card_of_row <= (others => '0');
        end if;	
      end if;
      if xcounter<frame_h_front then
        displayx <= (others => '0');
        indisplay := '0';
      elsif xcounter<(frame_h_front+width) then
        if card_x_sub=card_x_scale then
          next_card_x := card_x + 1;
          card_x_sub <= (others => '0');
          if next_card_x(2 downto 0) = "000" then
            next_card_number := card_number + 1;
          end if;
        else
          card_x_sub <= card_x_sub + 1;
        end if;
        displayx <= displayx + 1;
      else
        displayx <= (others => '1');
        indisplay := '0';
      end if;			
      
      if ycounter>=(frame_v_front+height) and ycounter<(frame_v_front+height+frame_v_syncheight) then
        vsync <= '1';
        led1 <= '1';
      else
        vsync <= '0';
        led1 <= '0';
      end if;
      if xcounter = 0 then
        if ycounter<frame_v_front then
          displayy <= (others => '0');
          indisplay := '0';
          first_card_of_row <= x"0000";	
        elsif ycounter<(frame_v_front+height) then
          displayy <= displayy + 1;
          next_card_number := first_card_of_row;
          if card_y_sub=card_y_scale then
            next_card_y := card_y + 1;
            if card_y(2 downto 0) = "111" then
              -- Increment card number every "bad line"
              first_card_of_row <= first_card_of_row + virtual_row_width;
              next_card_number := first_card_of_row + virtual_row_width;
            end if;
            card_y_sub <= (others => '0');
          else
            card_y_sub <= card_y_sub + 1;
          end if;
        else
          displayy <= (others => '1');
          indisplay := '0';
        end if;
      end if;
      
      led2 <= displayy(9);
      
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
      if char_fetch_cycle=0 then
        -- Load card number
        long_address(31 downto 28) := x"0";
        long_address(27 downto 0) := screen_ram_base+card_number;
        if sixteenbit_charset='1' then
          long_address := long_address+card_number;
        end if;
        ramaddress <= std_logic_vector(long_address(18 downto 3));
        char_fetch_cycle <= 1;
      else
        char_fetch_cycle <= 0;
      end if;
      if char_fetch_cycle=1 then
        -- Store character number
        -- In text mode, the glyph order is flexible
        next_glyph_number_buffer <= ramdata;
        -- As RAM is slow to read from, we buffer it, and then extract the
        -- right byte/word next cycle, so no more work here.
        char_fetch_cycle <= 2;
      elsif char_fetch_cycle=2 then
        -- Decode next character number from 64bit vector
        -- This is a bit too complex to do in a single cycle if we also have to
        -- choose the 16bit or 8 bit version.  So this cycle we calculate the
        -- 8bit and 16bit versions.  Then next cycle we can select the correct
        -- one.
        next_glyph_number_temp(15 downto 8) := x"00";
        case card_number(2 downto 0) is
          when "000" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer(63 downto 56);
          when "001" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer(55 downto 48);
          when "010" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer(47 downto 40);
          when "011" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer(39 downto 32);
          when "100" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer(31 downto 24);
          when "101" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer(23 downto 16);
          when "110" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer(15 downto  8);
          when "111" => next_glyph_number_temp(7 downto 0) := next_glyph_number_buffer( 7 downto  0);
          when others => next_glyph_number_temp(7 downto 0) := x"00";
        end case;
        next_glyph_number8 <= unsigned(next_glyph_number_temp);
        case card_number(1 downto 0) is
          when "00" => next_glyph_number_temp := next_glyph_number_buffer(63 downto 48);        
          when "01" => next_glyph_number_temp := next_glyph_number_buffer(47 downto 32);        
          when "10" => next_glyph_number_temp := next_glyph_number_buffer(31 downto 16);        
          when "11" => next_glyph_number_temp := next_glyph_number_buffer(15 downto  0);        
          when others => next_glyph_number_temp := x"0000";
        end case;
        next_glyph_number16 <= unsigned(next_glyph_number_temp);
        char_fetch_cycle <= 3;
        ramaddress <= (others => '0');
      elsif char_fetch_cycle=3 then
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
        long_address(31 downto 28) := x"0";
        long_address(27 downto 0) := colour_ram_base+unsigned(next_glyph_number_temp);
        ramaddress <= std_logic_vector(long_address(18 downto 3));
        char_fetch_cycle <= 4;
      elsif char_fetch_cycle=4 then
        -- Store colour bytes (will decode next cycle to keep logic shallow)
        next_glyph_colour_buffer <= ramdata;
        -- Character pixels (only 8 bits used if not in full colour mode)
        if fullcolour_8bitchars='0' and fullcolour_extendedchars='0' then
          long_address := character_set_address+(next_glyph_number*8)+card_y(2 downto 0);
        elsif fullcolour_8bitchars='0' and fullcolour_extendedchars='1' then
          if next_glyph_number<256 then
            long_address := character_set_address+(next_glyph_number*8)+card_y(2 downto 0);
            next_glyph_full_colour <= '1';
          else
            long_address := character_set_address+(256*8)+((next_glyph_number-256)*64)+card_y(2 downto 0)*8;            
            next_glyph_full_colour <= '0';
          end if;
        else
          -- if fullcolour_8bitchars='1' then all chars are full-colour          
          long_address := character_set_address+(next_glyph_number*64)+card_y(2 downto 0)*8;
        end if;
        ramaddress <= std_logic_vector(long_address(18 downto 3));
        char_fetch_cycle <= 5;
      elsif char_fetch_cycle=5 then
        -- Decode colour byte
        case card_number(2 downto 0) is
          when "000" => next_glyph_colour_temp := next_glyph_number_buffer(63 downto 56);
          when "001" => next_glyph_colour_temp := next_glyph_number_buffer(55 downto 48);
          when "010" => next_glyph_colour_temp := next_glyph_number_buffer(47 downto 40);
          when "011" => next_glyph_colour_temp := next_glyph_number_buffer(39 downto 32);
          when "100" => next_glyph_colour_temp := next_glyph_number_buffer(31 downto 24);
          when "101" => next_glyph_colour_temp := next_glyph_number_buffer(23 downto 16);
          when "110" => next_glyph_colour_temp := next_glyph_number_buffer(15 downto  8);
          when "111" => next_glyph_colour_temp := next_glyph_number_buffer( 7 downto  0);
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
      else
        -- XXX Fetch full-colour sprite information
        -- (C64 compatability sprites will be fetched during horizontal sync.
        --  Because we can fetch 64bits at once, compatibility sprite fetching
        --  cannot require more than 16 cycles).
        ramaddress <= (others => '0');
      end if;
      if card_number_t3 /= card_number then
        if extended_background_mode='1' then
          -- bit 6 and 7 of character is used for colour
          charaddress(10 downto 9) <= "00";
          charaddress(8 downto 3) <= std_logic_vector(card_number(5 downto 0));
        else
          charaddress(10 downto 3) <= std_logic_vector(card_number(7 downto 0));
        end if;
        charaddress(2 downto 0) <= std_logic_vector(card_y(2 downto 0));
        charread <= '1';
      else
        charread <= '0';
      end if;

      -- Move preloaded glyph data into position when advancing to the next character
      if card_x /= next_card_x then
        glyph_pixeldata <= next_glyph_pixeldata;
        glyph_colour <= next_glyph_colour;
        glyph_number <= next_glyph_number;
        glyph_full_colour <= next_glyph_full_colour;
        -- Trigger loading data for next character, and then sprite data.
        char_fetch_cycle <= 0;
      end if;
      
      card_x <= next_card_x;
      card_y <= next_card_y;
      card_number <= next_card_number;
      
      -- Make delayed versions of card number and x position so that we have time
      -- to fetch character row data.
      card_x_t1 <= card_x;
      card_x_t2 <= card_x_t1;
      card_x_t3 <= card_x_t2;
      card_number_t1 <= card_number;
      card_number_t2 <= card_number_t1;
      card_number_t3 <= card_number_t2;
      indisplay_t1 <= indisplay;
      indisplay_t2 <= indisplay_t1;
      indisplay_t3 <= indisplay_t2;

      if displayy<=y_chargen_start then
        card_y(11 downto 8) <= (others => '0');
        card_y(7 downto 0) <= (others => '0');
        card_y_sub <= (others => '0');
      end if;
      if displayx<=x_chargen_start then
        card_x(11 downto 8) <= (others => '0');
        card_x(7 downto 0) <= (others => '0');
        card_x_sub <= (others => '0');
      end if;
      if displayx<border_x_left or displayx>border_x_right or
        displayy<border_y_top or displayy>border_y_bottom then
        inborder<='1';
      else
        inborder<='0';
      end if;
      inborder_t1 <= inborder;
      inborder_t2 <= inborder_t1;
      inborder_t3 <= inborder_t2;

      -- XXX Until we support reading colour RAM, we are using the card number
      -- as the source of the foreground colour for the card.
      card_fg_colour(7 downto 4) := "0000";
      card_fg_colour(3 downto 0) := card_number_t3(3 downto 0);

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
      
      if indisplay_t3='1' then
        if inborder_t2='1' then
          pixel_colour <= border_colour;          
        elsif multicolour_mode='1' and text_mode='1' and card_fg_colour(3)='1' then
          -- Multicolour character mode only engages for characters with bit 3
          -- of their foreground colour set.
          multicolour_bits(0) := charrow(to_integer((not card_x_t3(2 downto 1))&'0'));
          multicolour_bits(1) := charrow(to_integer((not card_x_t3(2 downto 1))&'1'));
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
        elsif charrow(to_integer(not card_x_t3(2 downto 0))) = '1' then
          -- hires/bi-colour mode
          pixel_colour(7 downto 4) <= "0000";
          pixel_colour(3 downto 0) <= glyph_colour(3 downto 0);
        else
          pixel_colour <= card_bg_colour;
        end if;
      else
        pixel_colour <= x"00";
      end if;

      -- Pixels have a two cycle pipeline to help keep timing contraints:
      
      -- 1. From pixel colour lookup RGB
      vga_buffer_red <= pallete(to_integer(pixel_colour)).red(7 downto 4);   
      vga_buffer_green <= pallete(to_integer(pixel_colour)).green(7 downto 4); 
      vga_buffer_blue <= pallete(to_integer(pixel_colour)).blue(7 downto 4);

      -- 2. From RGB, push out to pins (also draw border)
      vgared <= vga_buffer_red;
      vgagreen <= vga_buffer_green;
      vgablue <= vga_buffer_blue;
    end if;
  end process;

end Behavioral;

