use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity test_osk is
end test_osk;

architecture behavioral of test_osk is

  signal frames : integer := 0;
  signal xcounter : integer := 0;
  signal ycounter_in : integer := 0;
  signal x_start : unsigned(11 downto 0) := to_unsigned(10,12);
  signal y_start : unsigned(11 downto 0) := to_unsigned(479-290,12);
  signal visual_keyboard_enable : std_logic := '0';
  signal keyboard_at_top : std_logic := '1';
  signal alternate_keyboard : std_logic := '0';
  signal instant_at_top : std_logic := '0';
  signal key1 : unsigned(7 downto 0) := x"FF";
  signal key2 : unsigned(7 downto 0) := x"FF";
  signal key3 : unsigned(7 downto 0) := x"FF";
  signal key4 : unsigned(7 downto 0) := x"FF";
  signal touch1_valid : std_logic := '1';
  signal touch1_x : unsigned(13 downto 0) := to_unsigned(200,14);
  signal touch1_y : unsigned(11 downto 0) := to_unsigned(400,12);
  signal touch1_key : unsigned(7 downto 0) := (others => '1');
  signal touch2_valid : std_logic := '1';
  signal touch2_x : unsigned(13 downto 0) := to_unsigned(100,14);
  signal touch2_y : unsigned(11 downto 0) := to_unsigned(40,12);
  signal touch2_key : unsigned(7 downto 0) := (others => '1');
  
  signal vgared_in : unsigned (7 downto 0) := x"00";
  signal vgagreen_in : unsigned (7 downto 0) := x"FF";
  signal vgablue_in : unsigned (7 downto 0) := x"00";
  signal vgared_osk : unsigned (7 downto 0);
  signal vgagreen_osk : unsigned (7 downto 0);
  signal vgablue_osk : unsigned (7 downto 0);
  signal vgared_out : unsigned (7 downto 0);
  signal vgagreen_out : unsigned (7 downto 0);
  signal vgablue_out : unsigned (7 downto 0);

  signal lcd_display_enable : std_logic := '0';
  signal lcd_in_letterbox : std_logic := '0';
  signal lcd_in_frame : std_logic := '0';
  signal vga_in_frame : std_logic := '0';
  signal external_pixel_strobe : std_logic := '0';
  
  signal pixelclock : std_logic := '1';
  signal clock120 : std_logic := '0';
  signal clock240 : std_logic := '0';
  signal pal50_select : std_logic := '0';
  signal test_pattern_enable : std_logic := '0';
  signal external_frame_x_zero : std_logic := '0';
  signal external_frame_y_zero : std_logic := '0';
  signal last_external_frame_x_zero : std_logic := '0';
  signal last_external_frame_y_zero : std_logic := '0';

  signal hsync : std_logic := '0';
  signal vsync : std_logic := '0';
  signal lcd_hsync : std_logic := '0';
  signal lcd_vsync : std_logic := '0';

  signal pixel_strobe_viciv : std_logic := '0';

  signal i : integer := 0;
  
begin
  pixel0: entity work.pixel_driver
    port map (
      clock80 => pixelclock,
      clock120 => clock120,
      clock240 => clock240,

      pixel_strobe80_out => external_pixel_strobe,
      
      -- Configuration information from the VIC-IV
      hsync_invert => '0',
      vsync_invert => '0',
      pal50_select => pal50_select,
      test_pattern_enable => test_pattern_enable,      
      
      -- Framing information for VIC-IV
      x_zero => external_frame_x_zero,     
      y_zero => external_frame_y_zero,     

      -- Pixel data from the video pipeline
      -- (clocked at 80MHz pixel clock)
      pixel_strobe_in => pixel_strobe_viciv,
      red_i => vgared_osk,
      green_i => vgagreen_osk,
      blue_i => vgablue_osk,

      -- The pixel for direct output to VGA pins
      -- It is clocked at the correct pixel
      red_o => vgared_out,
      green_o => vgagreen_out,
      blue_o => vgablue_out,      
      hsync => hsync,
      vsync => vsync,

      -- And the variations on those signals for the LCD display
      lcd_hsync => lcd_hsync,
      lcd_vsync => lcd_vsync,
      lcd_display_enable => lcd_display_enable,
      lcd_inletterbox => lcd_in_letterbox,
      inframe => vga_in_frame,
      lcd_inframe => lcd_in_frame

      );
  
  kc0: entity work.visual_keyboard
    port map(
      lcd_display_enable => lcd_display_enable,
      pixel_strobe_in => pixel_strobe_viciv,

      ycounter_in => ycounter_in,
      xcounter_in => xcounter,
      pixelclock => pixelclock,
      visual_keyboard_enable => visual_keyboard_enable,
      keyboard_at_top => keyboard_at_top,
      alternate_keyboard => alternate_keyboard,
      instant_at_top => instant_at_top,
      matrix_fetch_address => (others => '0'),
      key1 => key1,
      key2 => key2,
      key3 => key3,
      key4 => key4,
      touch1_valid => touch1_valid,
      touch1_x => touch1_x,
      touch1_y => touch1_y,
      touch1_key => touch1_key,
      touch2_valid => touch2_valid,
      touch2_x => touch2_x,
      touch2_y => touch2_y,
      touch2_key => touch2_key,
      vgared_in => vgared_in,
      vgagreen_in => vgagreen_in,
      vgablue_in => vgablue_in,
      vgared_out => vgared_osk,
      vgagreen_out => vgagreen_osk,
      vgablue_out => vgablue_osk
    );

  process (pixelclock)
  begin
    if rising_edge(pixelclock) then
      last_external_frame_y_zero <= external_frame_y_zero;
      last_external_frame_x_zero <= external_frame_x_zero;
      if external_frame_y_zero='1' and last_external_frame_y_zero='0' then
        ycounter_in <= 0;
      elsif external_frame_x_zero='1' and last_external_frame_x_zero='0' then
        xcounter <= 0;
        ycounter_in <= ycounter_in + 1;
      elsif pixel_strobe_viciv='1' then
        report "pixel strobe";
        xcounter <= xcounter + 1;
      else
        report "not a pixel";
      end if;
      
    end if;
  end process;
    
  process 
  begin
    while true loop

      pixel_strobe_viciv <= '0';

      if i = 1000 then
        visual_keyboard_enable <= '1';
      else
        i <= i + 1;
      end if;        

      -- 240MHz, 120MHz and 80MHz clocks means clocks toggle every 1, 2 and 3 iterations
      clock240 <= '1';
      clock120 <= '1';
      pixelclock <= '1';
      wait for 4 ns;
      clock240 <= '0';
      clock120 <= '1';
      pixelclock <= '1';
      wait for 4 ns;
      clock240 <= '1';
      clock120 <= '0';
      pixelclock <= '1';
      wait for 4 ns;
      clock240 <= '0';
      clock120 <= '0';
      pixelclock <= '0';
      wait for 4 ns;
      clock240 <= '1';
      clock120 <= '1';
      pixelclock <= '0';
      wait for 4 ns;
      clock240 <= '0';
      clock120 <= '1';
      pixelclock <= '0';
      wait for 4 ns;

      pixel_strobe_viciv <= '1';

      clock240 <= '1';
      clock120 <= '0';
      pixelclock <= '1';
      wait for 4 ns;
      clock240 <= '0';
      clock120 <= '0';
      pixelclock <= '1';
      wait for 4 ns;
      clock240 <= '1';
      clock120 <= '1';
      pixelclock <= '1';
      wait for 4 ns;
      clock240 <= '0';
      clock120 <= '1';
      pixelclock <= '0';
      wait for 4 ns;
      clock240 <= '1';
      clock120 <= '0';
      pixelclock <= '0';
      wait for 4 ns;
      clock240 <= '0';
      clock120 <= '0';
      pixelclock <= '0';
      wait for 4 ns;

      report "PIXEL:" & integer'image(xcounter)
        & ":" & integer'image(ycounter_in)
        & ":" & to_hstring(vgared_out)
        & ":" & to_hstring(vgagreen_out)
        & ":" & to_hstring(vgablue_out);
      key1 <= touch1_key;
      key2 <= touch2_key;
    end loop; 
    assert false report "End of simulation" severity note;
  end process;

end behavioral;
