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

entity frame_generator is
  generic (
    frame_width : integer;
    frame_height : integer;

    x_zero_position : integer := 0;

    fullwidth_start : integer;
    fullwidth_width : integer;

    narrow_start : integer;
    narrow_width : integer;

    pipeline_delay : integer;
    viciv_pipeline_depth : integer := 4;
    cycles_per_raster_1mhz : integer := 63;
    cycles_per_raster_2mhz : integer := 63 * 2;
    cycles_per_raster_3mhz : integer := 221; -- 63*3.5, rounded up to next integer;
    
    vsync_start : integer;
    vsync_end : integer;
    hsync_start : integer;
    hsync_end : integer;

    vga_hsync_start : integer;
    vga_hsync_end : integer;
    
    first_raster : integer;
    last_raster : integer;

    lcd_first_raster : integer;
    lcd_last_raster : integer
    
    );
  port (
    -- Single 81MHz clock : divide by 2 for ~41MHz CPU and 27MHz
    -- video pixel clock
    clock81 : in std_logic;
    -- CPU clock is used for exporting the PHI2 clock
    clock41 : in std_logic;

    interlace_enable : in std_logic := '0';
    
    -- CPU clock oriented signal that strobes for each CPU tick
    phi2_1mhz_out : out std_logic;  
    phi2_2mhz_out : out std_logic;  
    phi2_3mhz_out : out std_logic;  
    
    hsync_polarity : in std_logic;
    vsync_polarity : in std_logic;
    field_is_odd : in integer range 0 to 1 := 0;    

    -- Video output oriented signals
    cv_hsync : out std_logic := '0';
    hsync : out std_logic := '0';
    hsync_uninverted : out std_logic := '0';
    vsync : out std_logic := '0';
    vsync_uninverted : out std_logic := '0';

    lcd_hsync : out std_logic := '0';
    lcd_vsync : out std_logic := '1';

    lcd_inletterbox : out std_logic := '0';
    vga_inletterbox : out std_logic := '0';
    vga_hsync : out std_logic := '0';

    vga_blank : out std_logic := '0';
    
    -- For video outputs that are wider
    -- (Typically the 800x480 LCD panel on the MEGAphone)
    fullwidth_dataenable : out std_logic := '0';
    
    -- For video outputs that are narrower.
    -- Typically anything other than the LCD panel of the MEGAphone 
    narrow_dataenable : out std_logic := '0';
    
    red_o : out unsigned(7 downto 0) := x"00";
    green_o : out unsigned(7 downto 0) := x"00";
    blue_o : out unsigned(7 downto 0) := x"00";

    nred_o : out unsigned(7 downto 0) := x"00";
    ngreen_o : out unsigned(7 downto 0) := x"00";
    nblue_o : out unsigned(7 downto 0) := x"00";
    
    -- ~80MHz oriented signals for VIC-IV
    pixel_strobe : out std_logic := '0';
    cv_pixel_strobe : out std_logic := '0';
    x_zero : out std_logic := '0';
    y_zero : out std_logic := '0'    
    
    );

end frame_generator;

architecture brutalist of frame_generator is

  -- The pixelclock signal is 3x the real pixel clock 
  constant cycles_per_pixel : integer := 3;
  -- Two physical rasters per VIC-II/III raster
  constant physical_rasters_per_vic_ii_raster : integer := 2;

  constant ticks_per_vic_ii_raster : integer := frame_width * physical_rasters_per_vic_ii_raster * cycles_per_pixel;
  
  -- Now work out how much to add to the various accumulators,
  -- so that bit(16) will toggle on each phi tick
  -- The trick here is that we have to slightly over-estimate, rather than
  -- under-estimate, so that we don't end up a cycle short on each raster.
  -- Adding 1 should do that.
  constant phi2_1mhz_delta : unsigned(16 downto 0) := to_unsigned(1+65536*cycles_per_raster_1mhz/ticks_per_vic_ii_raster,17);
  constant phi2_2mhz_delta : unsigned(16 downto 0) := to_unsigned(1+65536*cycles_per_raster_2mhz/ticks_per_vic_ii_raster,17);
  constant phi2_3mhz_delta : unsigned(16 downto 0) := to_unsigned(1+65536*cycles_per_raster_3mhz/ticks_per_vic_ii_raster,17);
  
  signal phi2_remaining_1mhz : unsigned(7 downto 0) := to_unsigned(0,8);
  signal phi2_remaining_2mhz : unsigned(7 downto 0) := to_unsigned(0,8);
  signal phi2_remaining_3mhz : unsigned(7 downto 0) := to_unsigned(0,8);
  signal phi2_accumulator_1mhz : unsigned(16 downto 0) := to_unsigned(0,17);
  signal phi2_accumulator_2mhz : unsigned(16 downto 0) := to_unsigned(0,17);
  signal phi2_accumulator_3mhz : unsigned(16 downto 0) := to_unsigned(0,17);
  signal phi2_toggle_1mhz : std_logic := '0';
  signal phi2_toggle_2mhz : std_logic := '0';
  signal phi2_toggle_3mhz : std_logic := '0';
  signal last_phi2_toggle_1mhz : std_logic := '0';  
  signal last_phi2_toggle_2mhz : std_logic := '0';  
  signal last_phi2_toggle_3mhz : std_logic := '0';  

  signal x : integer := 0;  
  signal y : integer := frame_height - 3;

  signal vsync_driver : std_logic := '0';
  signal hsync_driver : std_logic := '0';
  signal cv_hsync_driver : std_logic := '0';
  signal hsync_uninverted_driver : std_logic := '0';
  signal vsync_uninverted_driver : std_logic := '0';

  signal cv_x : integer := 0;
  signal cv_pixel_strobe_int : std_logic := '0';
  signal cv_pixel_toggle : std_logic := '0';
  
  signal narrow_dataenable_driver : std_logic := '0';
  signal fullwidth_dataenable_driver : std_logic := '0';
  
  signal pixel_toggle : std_logic := '0';
  signal last_pixel_toggle : std_logic := '0';

  signal pixel_strobe_counter : integer := 0;

  signal x_zero_driver : std_logic := '0';
  signal y_zero_driver : std_logic := '0';

  signal normal_y_active : std_logic := '0';
  signal lcd_y_active : std_logic := '0';

  signal line_odd_even : integer range 0 to 1 := 0;
  
begin

  process (clock41,clock81) is
  begin

    if rising_edge(clock81) then

      vga_blank <= not narrow_dataenable_driver;
      
      x_zero <= x_zero_driver;
      y_zero <= y_zero_driver;
      
      vsync <= vsync_driver;
      vsync_uninverted <= vsync_uninverted_driver;
      cv_hsync <= cv_hsync_driver;
      hsync <= hsync_driver;
      hsync_uninverted <= hsync_uninverted_driver;

      fullwidth_dataenable <= fullwidth_dataenable_driver;
      narrow_dataenable <= narrow_dataenable_driver;

      phi2_accumulator_1mhz <= "0"&phi2_accumulator_1mhz(15 downto 0) + phi2_1mhz_delta;
      phi2_accumulator_2mhz <= "0"&phi2_accumulator_2mhz(15 downto 0) + phi2_2mhz_delta;
      phi2_accumulator_3mhz <= "0"&phi2_accumulator_3mhz(15 downto 0) + phi2_3mhz_delta;
      if phi2_accumulator_1mhz(16) = '1' then
        if phi2_remaining_1mhz /= 0 then
          phi2_toggle_1mhz <= not phi2_toggle_1mhz;
          phi2_remaining_1mhz <= phi2_remaining_1mhz - 1;
        end if;
      end if;      
      if phi2_accumulator_2mhz(16) = '1' then
        if phi2_remaining_2mhz /= 0 then
          phi2_toggle_2mhz <= not phi2_toggle_2mhz;
          phi2_remaining_2mhz <= phi2_remaining_2mhz - 1;
        end if;
      end if;      
      if phi2_accumulator_3mhz(16) = '1' then
        if phi2_remaining_3mhz /= 0 then
          phi2_toggle_3mhz <= not phi2_toggle_3mhz;
          phi2_remaining_3mhz <= phi2_remaining_3mhz - 1;
        end if;
      end if;      

      -- Pixel strobe to VIC-IV can just be a 50MHz pulse
      -- train, since it all goes into a buffer.
      -- But better is to still try to follow the 27MHz driven
      -- chain.

      cv_pixel_strobe <= '0';
      cv_pixel_strobe_int <= '0';
      if cv_pixel_strobe_int='1' then
      -- In fake progressive mode, there is 624 rather than 625 rasters, which
      -- are 864 wide. In interlace mode to keep timing when we add the single
      -- extra raster, we trim the frame width by one tick
        if (interlace_enable='1') and cv_x < (frame_width-1) then
          cv_x <= cv_x + 1;
        elsif (interlace_enable='0') and cv_x < (frame_width-1-(frame_height mod 2)) then
          cv_x <= cv_x + 1;
        else
          cv_x <= 0;
        end if;

        if cv_x = hsync_start then
          cv_hsync_driver <= '1';
        end if;
        if cv_x = hsync_end then
          cv_hsync_driver <= '0';
        end if;        
      end if;

      
      if pixel_strobe_counter /= (cycles_per_pixel-1) then
        pixel_strobe <= '0';
        pixel_strobe_counter <= pixel_strobe_counter + 1;
      else
        
        pixel_strobe <= '1';     -- stays high for 1 cycle
        pixel_strobe_counter <= 0;

        -- Generate half-rate composite video pixel toggle
        cv_pixel_strobe <= cv_pixel_toggle;
        cv_pixel_strobe_int <= cv_pixel_toggle;
        cv_pixel_toggle <= not cv_pixel_toggle;
        
        if x = x_zero_position then
          x_zero_driver <= '1';
          if phi2_remaining_1mhz = to_unsigned(0,8) then
            phi2_remaining_1mhz <= to_unsigned(cycles_per_raster_1mhz,8);
          end if;
          if phi2_remaining_2mhz = to_unsigned(0,8) then
            phi2_remaining_2mhz <= to_unsigned(cycles_per_raster_2mhz,8);
          end if;
          if phi2_remaining_3mhz = to_unsigned(0,8) then
            phi2_remaining_3mhz <= to_unsigned(cycles_per_raster_3mhz,8);
          end if;
        elsif x = x_zero_position + 3 then
          x_zero_driver <= '0';
        end if;
        if x < (frame_width-1) then
          x <= x + 1;
          
        else
          x <= 0;

         -- Reset composite video counter every 2nd raster line
          -- Support interlace by switching between odd and even lines
          -- every field.
          -- Actually we don't need to know which field we are in, because
          -- the frame is an odd number of rasters in length, and thus
          -- it will naturally alternate. Only if the frame is an even number
          -- of rasters do we need this correction -- like in NTSC.  But PAL
          -- has an odd number, so we need to make a smart selection here.
          --
          -- Then to make things more exciting, the switch needs to happen at the
          -- start of VSYNC, which is not at the start of the frame.
          -- (note that this formulation adds a 1 line delay to the odd/even switch
          -- which we take account of in the y < vsync_start equation).
          --
          -- When we are lucky, it all cancels out for us to be super simple.
          if ((frame_height mod 2) = 1) and (interlace_enable='1') then
            -- eg. PAL
            line_odd_even <= field_is_odd;
          else
            -- eg. NTSC : There are no unequal length fields here.
            line_odd_even <= 0;
          end if;

          if to_integer(to_unsigned(y,1)) = line_odd_even then
            report "Reset cv_x at y=" & integer'image(y) & ", field_is_odd=" & integer'image(field_is_odd);
            cv_x <= 0;
          end if;
          
          if (y < (frame_height-1)) and interlace_enable='1' then
            y <= y + 1;
            y_zero_driver <= '0';
          elsif (y < (frame_height-1-(frame_height mod 2))) and interlace_enable='0' then
            -- Fake progressive mode requires that the frame be a whole number
            -- of composite video rasters.
            y <= y + 1;
            y_zero_driver <= '0';
          else
            y <= 0;
            y_zero_driver <= '1';
            phi2_accumulator_1mhz <= to_unsigned(0,17);
            phi2_accumulator_2mhz <= to_unsigned(0,17);
            phi2_accumulator_3mhz <= to_unsigned(0,17);
          end if;
        end if;

        -- LCD HSYNC is expected to be just before start of pixels, and is
        -- always negative
        if x = hsync_start then
          lcd_hsync <= '0';
        end if;
        if x = hsync_end then
          lcd_hsync <= '1';
        end if;
        -- HSYNC is negative by default
        -- HDMI hsync
        if x = hsync_start then
          hsync_driver <= not hsync_polarity; 
          hsync_uninverted_driver <= '1';

          -- VSYNC should switch at the same time as HSYNC
          -- VSYNC is negative by default
          if y = vsync_start then
            lcd_vsync <= '0';
            vsync_driver <= vsync_polarity;
            vsync_uninverted_driver <= '1'; 
          end if;
          if y = vsync_end+1 then
            lcd_vsync <= '1';
            vsync_driver <= not vsync_polarity;
            vsync_uninverted_driver <= '0'; 
          end if;
          
        end if;
        if x = hsync_end then
          hsync_driver <= hsync_polarity;
          hsync_uninverted_driver <= '0';
        end if;
        -- Analog VGA HSYNC needs to be somewhat earlier, to allow
        -- pseudo-flyback time
        if x = vga_hsync_start then
          vga_hsync <= not hsync_polarity;
        end if;
        if x = vga_hsync_end then
          vga_hsync <= hsync_polarity;
        end if;
       
        if x = (1 + pipeline_delay + narrow_start + viciv_pipeline_depth) and normal_y_active='1'  then
          narrow_dataenable_driver <= '1';
        end if;
        if x = (1 + pipeline_delay + narrow_start + narrow_width + viciv_pipeline_depth) then
          narrow_dataenable_driver <= '0';
        end if;

        if x = (1 + pipeline_delay + fullwidth_start + viciv_pipeline_depth) and normal_y_active='1'  then
          fullwidth_dataenable_driver <= '1';
        end if;
        if x = (1 + pipeline_delay + fullwidth_start + fullwidth_width + viciv_pipeline_depth) then
          fullwidth_dataenable_driver <= '0';
        end if;
        
        if y = first_raster then
          normal_y_active <= '1';
          vga_inletterbox <= '1';
        end if;
        if y = (last_raster+1) then
          normal_y_active <= '0';
          vga_inletterbox <= '0';
        end if;

        if y = lcd_first_raster then
          lcd_y_active <= '1';
          lcd_inletterbox <= '1';
        end if;
        if y = (lcd_last_raster+1) then
          lcd_y_active <= '0';
          lcd_inletterbox <= '0';
        end if;

        -- Colourful pattern inside frame
        if fullwidth_dataenable_driver = '1' then
          -- Inside frame, draw a test pattern
          green_o <= to_unsigned(x,8);
          red_o <= to_unsigned(y mod 256,8);
          ngreen_o <= to_unsigned(x,8);
          nred_o <= to_unsigned(y mod 256,8);
          if x>255 and x<512 then
            blue_o <= x"ff";
            nblue_o <= x"ff";
          else
            blue_o <= x"00";
            nblue_o <= x"00";
          end if;
          -- diagonal white line to confirm raster order
          if x = y then
            red_o <= x"ff";
            green_o <= x"ff";
            blue_o <= x"ff";
          end if;
          -- Vertical grey and RGB transitions for checking DAC linearity
          if x > 512 and x < 540 then
            red_o <= to_unsigned(y,8);
            green_o <= to_unsigned(y,8);
            blue_o <= to_unsigned(y,8);
          elsif x > 539 and x < 572 then
            red_o <= to_unsigned(y,8);
            green_o <= (others => '0');
            blue_o <= (others => '0');
          elsif x > 571 and x < 604 then
            red_o <= (others => '0');
            green_o <= to_unsigned(y,8);
            blue_o <= (others => '0');
          elsif x > 603 and x < 636 then
            red_o <= (others => '0');
            green_o <= (others => '0');
            blue_o <= to_unsigned(y,8);
          end if;
        end if;
        
        -- Draw white edge on frame
        if x = narrow_start + pipeline_delay or x = (narrow_start + narrow_width - 1 - 1) then
          red_o <= x"FF";
          green_o <= x"FF";
          blue_o <= x"FF";
          nred_o <= x"FF";
          ngreen_o <= x"FF";
          nblue_o <= x"FF";
        end if;
        if y = first_raster or y = last_raster-1 then
          red_o <= x"FF";
          green_o <= x"FF";
          blue_o <= x"FF";
        end if;
        -- XXX Why is HDMI first raster one later than VGA?
        if y = first_raster+40 or y = last_raster-40 then
          nred_o <= x"FF";
          ngreen_o <= x"FF";
          nblue_o <= x"FF";
        end if;
      end if;

      -- Make sure we have nothing visible during H/VSYNC pulses, so we don't
      -- mess up the VGA colours
      if fullwidth_dataenable_driver = '0' then
        red_o <= x"00";
        green_o <= x"00";
        blue_o <= x"00";        
      end if;
      if narrow_dataenable_driver = '0' then
        nred_o <= x"00";
        ngreen_o <= x"00";
        nblue_o <= x"00";
      end if;

      
    end if;

    if rising_edge(clock41) then
      last_phi2_toggle_1mhz <= phi2_toggle_1mhz;
      if phi2_toggle_1mhz /= last_phi2_toggle_1mhz then
        phi2_1mhz_out <= '1';
      else
        phi2_1mhz_out <= '0';
      end if;
      last_phi2_toggle_2mhz <= phi2_toggle_2mhz;
      if phi2_toggle_2mhz /= last_phi2_toggle_2mhz then
        phi2_2mhz_out <= '1';
      else
        phi2_2mhz_out <= '0';
      end if;
      last_phi2_toggle_3mhz <= phi2_toggle_3mhz;
      if phi2_toggle_3mhz /= last_phi2_toggle_3mhz then
        phi2_3mhz_out <= '1';
      else
        phi2_3mhz_out <= '0';
      end if;
    end if;
    
  end process;

end brutalist;
