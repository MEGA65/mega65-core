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

entity pixel_driver is

  port (
    -- The various clocks we need
    cpuclock : in std_logic;
    clock81 : in std_logic;
    clock162 : in std_logic;
    clock27 : in std_logic;

    -- Inform VIC-IV of new rasters and new frames
    x_zero_out : out std_logic;
    y_zero_out : out std_logic;
    
    waddr_out : out unsigned(11 downto 0);
    rd_data_count : out std_logic_vector(9 downto 0);
    wr_data_count : out std_logic_vector(9 downto 0);
    
    -- 800x600@50Hz if pal50_select='1', else 800x600@60Hz
    pal50_select : in std_logic;
    -- 640x480@64Hz if vga60_select='1' override is enabled
    -- for monitors that can't do the HDTV modes
    vga60_select : in std_logic := '0';
    -- Shows simple test pattern if '1', else shows normal video
    test_pattern_enable : in std_logic;
    -- Invert hsync or vsync signals if '1'
    hsync_invert : in std_logic;
    vsync_invert : in std_logic;
    
    -- Incoming video, e.g., from VIC-IV and rain compositer
    -- Clocked at clock81 (aka pixelclock)
    pixel_strobe_in : in std_logic;
    pixel_x_in : in integer;
    red_i : in unsigned(7 downto 0);
    green_i : in unsigned(7 downto 0);
    blue_i : in unsigned(7 downto 0);

    -- Output video stream, clocked at correct clock for the
    -- video mode, i.e., after clock domain crossing
    red_o : out unsigned(7 downto 0);
    green_o : out unsigned(7 downto 0);
    blue_o : out unsigned(7 downto 0);
    -- hsync and vsync signals for VGA
    hsync : out std_logic;
    vsync : out std_logic;

    -- Signals for VIC-IV etc to know what is happening
    hsync_uninverted : out std_logic;
    vsync_uninverted : out std_logic;
    y_zero : out std_logic;
    x_zero : out std_logic;
    inframe : out std_logic;
    
    -- Indicate when next pixel/raster is expected
    pixel_strobe_out : out std_logic;
    
    -- Similar signals to above for the LCD panel
    -- The main difference is that we only announce pixels during the 800x480
    -- letter box that the LCD can show.
    lcd_hsync : out std_logic := '0';
    lcd_vsync : out std_logic := '0';
    lcd_display_enable : out std_logic := '1';
    lcd_pixel_strobe : out std_logic := '0';     -- in 30/40MHz clock domain to match pixels
    lcd_inletterbox : out std_logic := '0';
    lcd_inframe : out std_logic := '0'
    
    );

end pixel_driver;

architecture greco_roman of pixel_driver is

  signal raster_strobe : std_logic := '0';
  signal inframe_internal : std_logic := '0';
  
  signal pal50_select_internal : std_logic := '0';
  signal pal50_select_internal_drive : std_logic := '0';
  signal pal50_select_internal80 : std_logic := '0';

  signal vga60_select_internal : std_logic := '0';
  signal vga60_select_internal_drive : std_logic := '0';
  signal vga60_select_internal80 : std_logic := '0';
  
  signal raster_toggle : std_logic := '0';
  signal raster_toggle_last : std_logic := '0';

  signal hsync_pal50 : std_logic := '0';
  signal hsync_pal50_uninverted : std_logic := '0';
  signal vsync_pal50 : std_logic := '0';
  signal vsync_pal50_uninverted : std_logic := '0';
  
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
  
  signal test_pattern_red : unsigned(7 downto 0) := x"00";
  signal test_pattern_green : unsigned(7 downto 0) := x"00";
  signal test_pattern_blue : unsigned(7 downto 0) := x"00";

  signal x_zero_pal50 : std_logic := '0';
  signal y_zero_pal50 : std_logic := '0';
  signal x_zero_ntsc60 : std_logic := '0';
  signal y_zero_ntsc60 : std_logic := '0';
  signal x_zero_vga60 : std_logic := '0';
  signal y_zero_vga60 : std_logic := '0';

  signal inframe_pal50 : std_logic := '0';
  signal inframe_ntsc60 : std_logic := '0';
  signal inframe_vga60 : std_logic := '0';

  signal lcd_inframe_pal50 : std_logic := '0';
  signal lcd_inframe_ntsc60 : std_logic := '0';
  signal lcd_inframe_vga60 : std_logic := '0';

  signal lcd_inletterbox_pal50 : std_logic := '0';
  signal lcd_inletterbox_ntsc60 : std_logic := '0';
  signal lcd_inletterbox_vga60 : std_logic := '0';

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

  signal display_en80 : std_logic := '0';

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
  
  frame50: entity work.frame_generator
    generic map ( frame_width => 968,    -- 63 cycles x 16 pixels per clock
                                             -- = 1008, but then it's only 48
                                             -- frames per second.
                                             -- so what we have here is
                                             -- nominally 60.5 cycles per
                                             -- raster which is wrong. How does
                                             -- the calculation go wrong?
                                             -- Is it 27/30MHz pixel clock?
                  display_width => 800,
                  frame_height => 624,        -- 312 lines x 2 fields
                  pipeline_delay => 0,
                  display_height => 600,
                  vsync_start => 581,
                  vsync_end => 586,
                  hsync_start => 864+23+16,
                  hsync_end => 15 -- 932+23
                  )                  
    port map ( clock81 => clock81,
               clock41 => cpuclock,
               hsync => hsync_pal50,
               hsync_uninverted => hsync_pal50_uninverted,
               vsync => vsync_pal50,
               hsync_polarity => hsync_invert,
               vsync_polarity => vsync_invert,
               
               inframe => inframe_pal50,
               lcd_hsync => lcd_hsync_pal50,
               lcd_vsync => lcd_vsync_pal50,
               lcd_inframe => lcd_inframe_pal50,
               lcd_inletterbox => lcd_inletterbox_pal50,

               -- 80MHz facing signals for the VIC-IV
               x_zero => x_zero_pal50,
               y_zero => y_zero_pal50,
               pixel_strobe => pixel_strobe_50

               );

  frame60: entity work.frame_generator
    generic map ( frame_width => 854-1,   -- 65 cycles x 16 pixels
                  display_width => 800,
                  frame_height => 526,       -- NTSC frame is 263 lines x 2 frames
                  display_height => 526-4,
                  pipeline_delay => 0,
                  vsync_start => 489,
                  vsync_end => 495,
                  hsync_start => 853-62, -- 736+16-1,
                  hsync_end => 853 -- 798+16-1
                  )                  
    port map ( clock81 => clock81,
               clock41 => cpuclock,
               hsync_polarity => hsync_invert,
               vsync_polarity => vsync_invert,
               hsync_uninverted => hsync_ntsc60_uninverted,
               hsync => hsync_ntsc60,
               vsync => vsync_ntsc60,
               inframe => inframe_ntsc60,
               lcd_hsync => lcd_hsync_ntsc60,
               lcd_vsync => lcd_vsync_ntsc60,
               lcd_inframe => lcd_inframe_ntsc60,
               lcd_inletterbox => lcd_inletterbox_ntsc60,

               -- 80MHz facing signals for VIC-IV
               x_zero => x_zero_ntsc60,
               y_zero => y_zero_ntsc60,
               pixel_strobe => pixel_strobe_60               
               
               );               

  -- ModeLine "640x480" 25.18 640 656 752 800 480 490 492 525 -HSync -VSync 
  frame60vga: entity work.frame_generator
    generic map ( frame_width => 800-1,   -- 65 cycles x 16 pixels
                  display_width => 640,
                  frame_height => 526,       -- NTSC frame is 263 lines x 2 frames
                  display_height => 526-4,
                  pipeline_delay => 0,
                  vsync_start => 489,
                  vsync_end => 495,
                  hsync_start => 656,
                  hsync_end => 752
                  )                  
    port map ( clock81 => clock81,
               clock41 => cpuclock,
               hsync_polarity => hsync_invert,
               vsync_polarity => vsync_invert,
               hsync_uninverted => hsync_vga60_uninverted,
               hsync => hsync_vga60,
               vsync => vsync_vga60,
               inframe => inframe_vga60,
               lcd_hsync => lcd_hsync_vga60,
               lcd_vsync => lcd_vsync_vga60,
               lcd_inframe => lcd_inframe_vga60,
               lcd_inletterbox => lcd_inletterbox_vga60,

               -- 80MHz facing signals for VIC-IV
               x_zero => x_zero_vga60,
               y_zero => y_zero_vga60,
               pixel_strobe => pixel_strobe_vga60               
               
               );               
  
  hsync <= hsync_pal50 when pal50_select_internal='1' else
           hsync_ntsc60 when vga60_select_internal='1'
           else hsync_vga60;
  vsync <= vsync_pal50 when pal50_select_internal='1' else
           vsync_vga60 when vga60_select_internal='1'
           else vsync_ntsc60;
  lcd_hsync <= lcd_hsync_pal50 when pal50_select_internal='1' else
               lcd_hsync_vga60 when vga60_select_internal='1'
               else lcd_hsync_ntsc60;
  lcd_vsync <= lcd_vsync_pal50 when pal50_select_internal='1' else
               lcd_vsync_vga60 when vga60_select_internal='1'
               else lcd_vsync_ntsc60;
  inframe <= inframe_pal50 when pal50_select_internal='1' else
             inframe_vga60 when vga60_select_internal='1'
             else inframe_ntsc60;
  inframe_internal <= inframe_pal50 when pal50_select_internal='1' else
                      inframe_vga60 when vga60_select_internal='1'
                      else inframe_ntsc60;
  lcd_inframe <= lcd_inframe_pal50 when pal50_select_internal='1' else
                 lcd_inframe_vga60 when vga60_select_internal='1'
                 else lcd_inframe_ntsc60;
  lcd_inletterbox <= lcd_inletterbox_pal50 when pal50_select_internal='1' else
                     lcd_inletterbox_vga60 when vga60_select_internal='1'
                     else lcd_inletterbox_ntsc60;

  raster_strobe <= x_zero_pal50 when pal50_select_internal='1' else
                   x_zero_vga60 when vga60_select_internal='1'
                   else x_zero_ntsc60;
  x_zero <= x_zero_pal50 when pal50_select_internal='1' else
            x_zero_vga60 when vga60_select_internal='1'
            else x_zero_ntsc60;
  y_zero <= y_zero_pal50 when pal50_select_internal='1' else
            y_zero_vga60 when vga60_select_internal='1'
            else y_zero_ntsc60;
  y_zero_internal <= y_zero_pal50 when pal50_select_internal='1' else
                     y_zero_vga60 when vga60_select_internal='1'
                     else y_zero_ntsc60;
  pixel_strobe_out <= pixel_strobe_50 when pal50_select_internal='1' else
                      pixel_strobe_vga60 when vga60_select_internal='1'
                      else pixel_strobe_60;

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
  
  x_zero_out <= x_zero_pal50 when pal50_select_internal80='1' else
                x_zero_vga60 when vga60_select_internal80='1'
                else x_zero_ntsc60;
  y_zero_out <= y_zero_pal50 when pal50_select_internal80='1' else
                y_zero_vga60 when vga60_select_internal80='1'
                else y_zero_ntsc60;
  
  process (clock81,clock27) is
  begin

    if rising_edge(clock81) then

  if pal50_select_internal80='1' then
    report "x_zero=" & std_logic'image(x_zero_pal50)
      & ", y_zero=" & std_logic'image(y_zero_pal50);
  else
    report "x_zero = " & std_logic'image(x_zero_ntsc60)
      & ", y_zero = " & std_logic'image(y_zero_ntsc60);
  end if;       
      
      lcd_display_enable <= display_en80;
  pal50_select_internal80 <= pal50_select;
  vga60_select_internal80 <= vga60_select;
      if pal50_select_internal80 = '1' then
        display_en80 <= lcd_inframe_pal50;
      elsif vga60_select_internal80='1' then
        display_en80 <= lcd_inframe_vga60;
      else
        display_en80 <= lcd_inframe_ntsc60;
      end if;
      
    end if;        

  if rising_edge(clock27) then
      pal50_select_internal_drive <= pal50_select;
      pal50_select_internal <= pal50_select_internal_drive;

      vga60_select_internal_drive <= vga60_select;
      vga60_select_internal <= vga60_select_internal_drive;

      test_pattern_enable120 <= test_pattern_enable;
      
      -- Output the pixels or else the test pattern
      if plotting='0' or inframe_internal='0' then        
        red_o <= x"00";
        green_o <= x"00";
        blue_o <= x"00";
      elsif test_pattern_enable120='1' then
        red_o <= to_unsigned(raddr50,8);
        green_o <= to_unsigned(raddr60,8);
        blue_o <= to_unsigned(raddrvga60,8);
      else
        red_o <= red_i;
        green_o <= green_i;
        blue_o <= blue_i;
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

  end process;

end greco_roman;
