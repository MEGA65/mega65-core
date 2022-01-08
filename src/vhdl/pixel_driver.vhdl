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

--library UNISIM;
--use UNISIM.vcomponents.all;


entity pixel_driver is

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

    -- ~1mhz clock for CPU and other parts, derived directly from the video clock
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
    
    -- Inform VIC-IV of new rasters and new frames
    -- Signals for VIC-IV etc to know what is happening
    hsync_uninverted : out std_logic := '0';
    vsync_uninverted : out std_logic := '0';
    y_zero : out std_logic := '0';
    x_zero : out std_logic := '0';
    inframe : out std_logic := '0';
    vga_inletterbox : out std_logic := '0';

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

  signal fullwidth_dataenable_internal : std_logic := '0';
  signal narrow_dataenable_internal : std_logic := '0';
  
  signal pal50_select_internal : std_logic := '0';
  signal pal50_select_internal_drive : std_logic := '0';

  signal vga60_select_internal : std_logic := '0';
  signal vga60_select_internal_drive : std_logic := '0';
  
  signal raster_toggle : std_logic := '0';
  signal raster_toggle_last : std_logic := '0';

  signal hsync_pal50 : std_logic := '0';
  signal hsync_pal50_uninverted : std_logic := '0';
  signal vsync_pal50 : std_logic := '0';
  signal vsync_pal50_uninverted : std_logic := '0';

  signal phi2_1mhz_pal50 : std_logic;
  signal phi2_1mhz_ntsc60 : std_logic;
  signal phi2_1mhz_vga60 : std_logic;
  signal phi2_2mhz_pal50 : std_logic;
  signal phi2_2mhz_ntsc60 : std_logic;
  signal phi2_2mhz_vga60 : std_logic;
  signal phi2_3mhz_pal50 : std_logic;
  signal phi2_3mhz_ntsc60 : std_logic;
  signal phi2_3mhz_vga60 : std_logic;
  
  signal hsync_ntsc60 : std_logic := '0';
  signal hsync_ntsc60_uninverted : std_logic := '0';
  signal vsync_ntsc60 : std_logic := '0';
  signal vsync_ntsc60_uninverted : std_logic := '0';

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

  signal plotting : std_logic := '0';
  signal plotting50 : std_logic := '0';
  signal plotting60 : std_logic := '0';
  signal plottingvga60 : std_logic := '0';

  signal test_pattern_enable120 : std_logic := '0';
  
  signal y_zero_internal : std_logic := '0';

  signal raddr : std_logic_vector(9 downto 0);
  signal waddr : std_logic_vector(9 downto 0);

  signal raddr50 : integer := 0;
  signal raddr60 : integer := 0;
  signal raddrvga60 : integer := 0;

begin

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
                  frame_width => 864 - 1,        
                  frame_height => 625,        -- 312 lines x 2 fields

                  x_zero_position => 864-45,
                  
                  fullwidth_width => 800,
                  fullwidth_start => 0,

                  narrow_width => 720,
                  narrow_start => 0,

                  pipeline_delay => 0,

                  first_raster => 1+16,
                  last_raster => 576+16,

                  -- VSYNC comes 5 lines after video area, and lasts 5 raster lines
                  vsync_start => 576+16+5,
                  vsync_end   => 576+16+5+4,

                  -- Add 6 more clocks after the end of video lines before
                  -- asserting HSYNC (HDMI test 7-25)
                  hsync_start => 720+12+5,
                  hsync_end => 720+12+5+64,
                  -- Again, VGA ends up a bit to the left, so make HSYNC earlier
                  vga_hsync_start => 720,
                  vga_hsync_end => 720+64,                 
                  
                  -- Centre letterbox slice for LCD panel
                  lcd_first_raster => 1+(576-480)/2,
                  lcd_last_raster => 1+576-(576-480)/2
                  
                  )                  
    port map ( clock81 => clock81,
               clock41 => cpuclock,
               hsync => hsync_pal50,
               hsync_uninverted => hsync_pal50_uninverted,
               vsync => vsync_pal50,
               hsync_polarity => hsync_invert,
               vsync_polarity => vsync_invert,

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
               pixel_strobe => pixel_strobe_50

               );

  -- EDTV 720x480p 60Hz from:
  -- http://read.pudn.com/downloads222/doc/1046129/CEA861D.pdf
  -- (This is the mode lines that the ADV7511 should want to see)
  frame60: entity work.frame_generator
    generic map ( frame_width => 858,   -- 65 cycles x 16 pixels
                  frame_height => 526,       -- NTSC frame is 263 lines x 2 frames

                  x_zero_position => 858-46,

                  fullwidth_width => 800,
                  fullwidth_start => 0,

                  narrow_width => 720,
                  narrow_start => 0,

                  pipeline_delay => 0,
                  
                  -- Advance VSYNC 23 lines (HDMI test 7-25)
                  vsync_start => 480+1+9,
                  vsync_end => 480+1+5+9,
                  -- Delay HSYNC by 6 cycles (HDMI test 7-25)
                  hsync_start => 720+16+5,
                  hsync_end => 720+16+62+5,
                  -- ... but not for VGA, or it ends up off-centre
                  vga_hsync_start => 720+10,
                  vga_hsync_end => 720+10+62,
                  
                  first_raster => 1,
                  last_raster => 480,

                  lcd_first_raster => 1,
                  lcd_last_raster => 480
                  )                  
    port map ( clock81 => clock81,
               clock41 => cpuclock,
               hsync => hsync_ntsc60,
               hsync_uninverted => hsync_ntsc60_uninverted,
               vsync => vsync_ntsc60,
               hsync_polarity => hsync_invert,
               vsync_polarity => vsync_invert,

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

               vga_blank => vga_blank_ntsc60,
               
               -- 80MHz facing signals for VIC-IV
               x_zero => x_zero_ntsc60,
               y_zero => y_zero_ntsc60,
               pixel_strobe => pixel_strobe_60               
               
               );               

  -- ModeLine "640x480" 25.18 640 656 752 800 480 490 492 525 -HSync -VSync
  -- Ends up being 64Hz, because our dotclock is ~27MHz.  Most monitors accept
  -- it, anyway.
  -- XXX - Actually just 720x480p 60Hz NTSC repeated for now.
  frame60vga: entity work.frame_generator
    generic map ( frame_width => 858,   -- 65 cycles x 16 pixels
                  frame_height => 526,       -- NTSC frame is 263 lines x 2 frames

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
                  lcd_last_raster => 522,

                  cycles_per_raster_1mhz => 65,
                  cycles_per_raster_2mhz => 65*2,
                  cycles_per_raster_3mhz => 228 -- 65*3.5, rounded up to next integer
                  
                  )                  
    port map ( clock81 => clock81,
               clock41 => cpuclock,
               hsync => hsync_vga60,
               hsync_uninverted => hsync_vga60_uninverted,
               vsync => vsync_vga60,
               hsync_polarity => hsync_invert,
               vsync_polarity => vsync_invert,

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
               pixel_strobe => pixel_strobe_vga60               
               
               );               
  
  phi_1mhz_out <= phi2_1mhz_pal50 when pal50_select_internal='1' else
                  phi2_1mhz_vga60 when vga60_select_internal='1'
                  else phi2_1mhz_ntsc60;
  phi_2mhz_out <= phi2_2mhz_pal50 when pal50_select_internal='1' else
                  phi2_2mhz_vga60 when vga60_select_internal='1'
                  else phi2_2mhz_ntsc60;
  phi_3mhz_out <= phi2_3mhz_pal50 when pal50_select_internal='1' else
                  phi2_3mhz_vga60 when vga60_select_internal='1'
                  else phi2_3mhz_ntsc60;

  hsync <= hsync_pal50 when pal50_select_internal='1' else
           hsync_vga60 when vga60_select_internal='1'
           else hsync_ntsc60;
  vsync <= vsync_pal50 when pal50_select_internal='1' else
           vsync_vga60 when vga60_select_internal='1'
           else vsync_ntsc60;
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

  x_zero <= x_zero_pal50 when pal50_select_internal='1' else
            x_zero_vga60 when vga60_select_internal='1'
            else x_zero_ntsc60;
  y_zero <= y_zero_pal50 when pal50_select_internal='1' else
            y_zero_vga60 when vga60_select_internal='1'
            else y_zero_ntsc60;

  y_zero_internal <= y_zero_pal50 when pal50_select_internal='1' else
                     y_zero_vga60 when vga60_select_internal='1'
                     else y_zero_ntsc60;

  -- Generate output pixel strobe and signals for read-side of the FIFO
  pixel_strobe_out <= pixel_strobe_50 when pal50_select_internal='1' else
                      pixel_strobe_vga60 when vga60_select_internal='1'
                      else pixel_strobe_60;

  raddr <= std_logic_vector(to_unsigned(raddr50,10)) when pal50_select_internal='1' else
           std_logic_vector(to_unsigned(raddrvga60,10)) when vga60_select_internal='1'
           else std_logic_vector(to_unsigned(raddr60,10));
  
  plotting <= '0' when y_zero_internal='1' else
              plotting50 when pal50_select_internal='1' else
              plottingvga60 when vga60_select_internal='1'
              else plotting60;
  
  
  process (clock81,clock27) is
  begin

    if rising_edge(clock81) then

  report "PIXEL strobe = " & std_logic'image(pixel_strobe_50) & ", "
    & std_logic'image(pixel_strobe_vga60) & ", " 
    & std_logic'image(pixel_strobe_60);
  

      
      if pal50_select_internal='1' then
        report "x_zero=" & std_logic'image(x_zero_pal50)
          & ", y_zero=" & std_logic'image(y_zero_pal50);
      else
        report "x_zero = " & std_logic'image(x_zero_ntsc60)
          & ", y_zero = " & std_logic'image(y_zero_ntsc60);
      end if;       
      
    end if;        

    if rising_edge(clock27) then

      report "plotting = " & std_logic'image(plotting)
        & ", fullwidth_dataenable_internal = " & std_logic'image(fullwidth_dataenable_internal);

      pal50_select_internal_drive <= pal50_select;
      pal50_select_internal <= pal50_select_internal_drive;

      vga60_select_internal_drive <= vga60_select;
      vga60_select_internal <= vga60_select_internal_drive;

      test_pattern_enable120 <= test_pattern_enable;
      
      -- Output the pixels or else the test pattern
      if plotting='0' or fullwidth_dataenable_internal='0' then        
        red_o <= x"00";
        green_o <= x"00";
        blue_o <= x"00";
      elsif test_pattern_enable120='1' then
--        red_o <= to_unsigned(raddr50,8);
--        green_o <= to_unsigned(raddr60,8);
--        blue_o <= to_unsigned(raddrvga60,8);
        red_o <= test_pattern_red50;
        green_o <= test_pattern_green50;
        blue_o <= test_pattern_blue50;
      else
        red_o <= red_i;
        green_o <= green_i;
        blue_o <= blue_i;
      end if;

      if plotting='0' or narrow_dataenable_internal='0' then        
        red_no <= x"00";
        green_no <= x"00";
        blue_no <= x"00";
      elsif test_pattern_enable120='1' then
--        red_no <= to_unsigned(raddr50,8);
--        green_no <= to_unsigned(raddr60,8);
--        blue_no <= to_unsigned(raddrvga60,8);
        red_no <= test_pattern_red50;
        green_no <= test_pattern_green50;
        blue_no <= test_pattern_blue50;
      else
        red_no <= red_i;
        green_no <= green_i;
        blue_no <= blue_i;
      end if;
      
      if x_zero_pal50='1' then
        raddr50 <= 0;
        plotting50 <= '0';
        report "raddr = ZERO, clearing plotting50";
      else
        if raddr50 < 800 then
          plotting50 <= '1';
        else
          report "clearing plotting50 due to end of line";
          plotting50 <= '0';
        end if;
        
        if raddr50 < 1023 then
          raddr50 <= raddr50 + 1;
        end if;
      end if;

      if x_zero_ntsc60='1' then
        raddr60 <= 0;
        plotting60 <= '0';
        report "raddr = ZERO";
      else
        if raddr60 < 800 then
          plotting60 <= '1';
        else
          plotting60 <= '0';
        end if;

        if raddr60 < 1023 then
          raddr60 <= raddr60 + 1;
        end if;
      end if;

      if x_zero_vga60='1' then
        raddrvga60 <= 0;
        plottingvga60 <= '0';
        report "raddr = ZERO";
      else
        if raddrvga60 < 800 then
          plottingvga60 <= '1';
        else
          plottingvga60 <= '0';
        end if;

        if raddrvga60 < 1023 then
          raddrvga60 <= raddrvga60 + 1;
        end if;
      end if;
    end if;

  end process;

end greco_roman;
