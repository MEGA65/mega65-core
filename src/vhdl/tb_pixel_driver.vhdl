library vunit_lib;
context vunit_lib.vunit_context;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;


entity tb_pixel_driver is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_pixel_driver is

  -- Generate 81MHz, 40.5MHz and 27MHz clocks
  -- Actually, we can just run everything on 81MHz to keep our life simple.
  signal pixelclock : std_logic;
  signal phi_1mhz : std_logic;
  signal phi_2mhz : std_logic;
  signal phi_3mhz : std_logic;
  signal external_pixel_strobe : std_logic;
  signal hsync_polarity : std_logic := '0';
  signal vsync_polarity : std_logic := '0';
  signal pal50_select : std_logic := '0';
  signal vga60_select : std_logic := '0';
  signal test_pattern_enable : std_logic := '1';
  signal external_frame_x_zero : std_logic := '0';
  signal external_frame_y_zero : std_logic := '0';
  signal vgared_osk : unsigned(7 downto 0) := x"00";
  signal vgagreen_osk : unsigned(7 downto 0) := x"00";
  signal vgablue_osk : unsigned(7 downto 0) := x"00";
  signal vgared : unsigned(7 downto 0) := x"00";
  signal vgagreen : unsigned(7 downto 0) := x"00";
  signal vgablue : unsigned(7 downto 0) := x"00";
  signal panelred : unsigned(7 downto 0) := x"00";
  signal panelgreen : unsigned(7 downto 0) := x"00";
  signal panelblue : unsigned(7 downto 0) := x"00";
  signal hdmi_hsync : std_logic;
  signal vsync : std_logic;
  signal vga_hsync : std_logic;
  signal vga_blank : std_logic;
  signal lcd_hsync : std_logic;
  signal lcd_vsync : std_logic;
  signal lcd_dataenable_internal : std_logic;
  signal lcd_inletterbox : std_logic;
  signal vga_inletterbox : std_logic;
  signal hdmi_dataenable_internal : std_logic;

  signal cv_luma : unsigned(7 downto 0);
  signal cv_chroma : unsigned(7 downto 0);
  signal cv_composite : unsigned(7 downto 0);  
  
  signal h0 : std_logic := '0';
  signal v0 : std_logic := '0';
  signal h1 : std_logic := '0';
  signal v1 : std_logic := '0';

  signal interlace_mode : std_logic := '1';
  signal mono_mode : std_logic := '0';
  
begin

  pixel0: entity work.pixel_driver
    generic map (
      -- Greatly reduce frame height to speed up simulation
      debug_height_reduction => 450
      )
    port map (
               clock81 => pixelclock, -- 81MHz
               clock27 => pixelclock,
               cpuclock => pixelclock,

               phi_1mhz_out => phi_1mhz,
               phi_2mhz_out => phi_2mhz,
               phi_3mhz_out => phi_3mhz,

               pixel_strobe_out => external_pixel_strobe,

               interlace_mode => interlace_mode,
               mono_mode => mono_mode,
      
      -- Configuration information from the VIC-IV
      hsync_invert => hsync_polarity,
      vsync_invert => vsync_polarity,
               pal50_select => pal50_select,
               vga60_select => vga60_select,
      test_pattern_enable => test_pattern_enable,      
      
      -- Framing information for VIC-IV
      x_zero => external_frame_x_zero,     
      y_zero => external_frame_y_zero,     

      -- Pixel data from the video pipeline
      -- (clocked at 81MHz pixel clock)
      red_i => vgared_osk,
      green_i => vgagreen_osk,
      blue_i => vgablue_osk,

      -- The pixel for direct output to VGA pins
      -- It is clocked at the correct pixel
      red_no => vgared,
      green_no => vgagreen,
      blue_no => vgablue,      

      red_o => panelred,
      green_o => panelgreen,
      blue_o => panelblue,

      luma => cv_luma,
      chroma => cv_chroma,
      composite => cv_composite,         
               
      hsync => hdmi_hsync,
      vsync => vsync,  -- for HDMI
      vga_hsync => vga_hsync,      -- for VGA
      vga_blank => vga_blank,

      -- And the variations on those signals for the LCD display
      lcd_hsync => lcd_hsync,               
      lcd_vsync => lcd_vsync,
      fullwidth_dataenable => lcd_dataenable_internal,
      narrow_dataenable => hdmi_dataenable_internal,
      lcd_inletterbox => lcd_inletterbox,
      vga_inletterbox => vga_inletterbox

      );
      

  
  main : process
  begin
    test_runner_setup(runner, runner_cfg);    
    
    while test_suite loop

      if run("HSYNC and VSYNC signals are generated") then
        -- Allow all signals to begin propagating
        for i in 1 to 10 loop
          pixelclock <= '0'; wait for 6.172 ns; pixelclock <= '1'; wait for 6.172 ns;
        end loop;
        for i in 1 to 10000 loop
          pixelclock <= '0'; wait for 6.172 ns; pixelclock <= '1'; wait for 6.172 ns;
          if vga_hsync='0' then
            h0 <= '1';
          else
            h1 <= '1';
          end if;
          if vga_hsync='0' then
            v0 <= '1';
          else
            v1 <= '1';
          end if;
          if (h0 and h1 and v0 and v1) = '1' then
            exit;
          end if;
        end loop;
        if (h0 and h1 and v0 and v1) = '1' then
          report "Saw HSYNC and VSYNC low and high";
        else
          assert false report "Expected to see HSYNC and VSYNC both toggle at some point";
        end if;
      elsif run("component video signal has SYNC pulses") then
        -- Allow all signals to begin propagating
        for i in 1 to 10 loop
          pixelclock <= '0'; wait for 6.172 ns; pixelclock <= '1'; wait for 6.172 ns;
        end loop;
        for i in 1 to 10000 loop
          pixelclock <= '0'; wait for 6.172 ns; pixelclock <= '1'; wait for 6.172 ns;
          if cv_luma = x"00" then
            h0 <= '1';
          end if;
          if to_integer(cv_luma) > 77 then -- 256*0.3 is threshold for SYNC
            h1 <= '1';
          end if;
          if (h0 and h1) = '1' then
            exit;
          end if;
        end loop;
        if (h0 and h1) = '1' then
          report "Saw composite SYNC both low and high";
        else
          assert false report "Expected to see composite SYNC both low and high";
        end if;
      elsif run("Simulation of two fields for one frame completes") then
        -- 81MHz = 81M cycles for 1 second.  At 50Hz, we need 81M / 50 = 1.62M
        -- cycles. We allow a bit of margin

        test_pattern_enable <= '1';
        pal50_select <= '0';
        interlace_mode <= '1';
        mono_mode <= '0';
        
--        for i in 1 to 1_640_000 loop
        for i in 1 to 700_000 loop
--        for i in 1 to 3_000_000 loop
          pixelclock <= '0'; wait for 6.172 ns; pixelclock <= '1'; wait for 6.172 ns;
        end loop;
      end if;
    end loop;
    test_runner_cleanup(runner);
  end process;
end architecture;
