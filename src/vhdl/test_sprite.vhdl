use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;
use work.victypes.all;

entity test_sprite is
end test_sprite;

architecture behavioral of test_sprite is

  signal pixel_x_640 : integer := 0;
  signal hsync : std_logic := '0';
  signal vsync : std_logic := '0';
  signal ycounter_in : unsigned(11 downto 0) := (others => '0');
  signal x_start : unsigned(11 downto 0) := to_unsigned(0,12);
  signal y_start : unsigned(11 downto 0) := to_unsigned(479-290,12);
  signal pixelclock : std_logic := '1';
  signal vgared_in : unsigned (7 downto 0) := x"a0";
  signal vgagreen_in : unsigned (7 downto 0) := x"a0";
  signal vgablue_in : unsigned (7 downto 0) := x"e0";
  signal vgared_out : unsigned (7 downto 0) := x"FF";
  signal vgagreen_out : unsigned (7 downto 0) := x"FF";
  signal vgablue_out : unsigned (7 downto 0) := x"FF";

  signal sprite_h640 : std_logic := '0';
  signal sprite_sixteen_colour_mode : std_logic := '0';
  signal sprite_horizontal_tile_enable : std_logic := '0';
  signal sprite_bitplane_enable : std_logic := '0';
  signal sprite_extended_height_enable : std_logic := '0';
  signal sprite_extended_width_enable : std_logic := '0';
  signal sprite_extended_height_size : unsigned(7 downto 0) := x"00";  
  signal sprite_datavalid_in : std_logic := '0';
  signal sprite_bytenumber_in : spritebytenumber := 0;
  signal sprite_spritenumber_in : spritenumber := 0;
  signal sprite_data_in : unsigned(7 downto 0) := x"00";
  signal sprite_data_offset_in : spritedatabytenumber := 0;    
  signal is_foreground_in : std_logic := '0';
  signal is_background_in : std_logic := '0';
  signal x320_in : xposition := 0;
  signal x640_in : xposition := 0;
  signal y_in : yposition := 0;
  signal border_in : std_logic := '0';
  signal pixel_in : unsigned(7 downto 0) := x"00";
  signal alpha_in : unsigned(7 downto 0) := x"00";
  signal is_sprite_in : std_logic := '0';
  signal sprite_colour_in : unsigned(7 downto 0) := x"00";
  signal sprite_map_in : std_logic_vector(7 downto 0) := x"00";
  signal sprite_fg_map_in : std_logic_vector(7 downto 0) := x"00";

  signal is_foreground_out : std_logic := '0';
  signal is_background_out : std_logic := '0';
  signal x320_out : xposition := 0;
  signal x640_out : xposition := 0;
  signal y_out : yposition := 0;
  signal border_out : std_logic := '0';
  signal pixel_out : unsigned(7 downto 0) := x"00";
  signal alpha_out : unsigned(7 downto 0) := x"00";
  signal sprite_colour_out : unsigned(7 downto 0) := x"00";
  signal is_sprite_out : std_logic := '0';
  signal sprite_map_out : std_logic_vector(7 downto 0) := x"00";
  signal sprite_fg_map_out : std_logic_vector(7 downto 0) := x"00";
  
  signal sprite_enable : std_logic := '0';
  signal sprite_x : unsigned(9 downto 0) := (others => '0');
  signal sprite_y : unsigned(7 downto 0) := x"00";
  signal sprite_colour : unsigned(7 downto 0) := x"00";
  signal sprite_multi0_colour : unsigned(7 downto 0) := x"00";
  signal sprite_multi1_colour : unsigned(7 downto 0) := x"00";
  signal sprite_is_multicolour : std_logic := '0';
  signal sprite_stretch_x : std_logic := '0';
  signal sprite_stretch_y : std_logic := '0';
  signal sprite_priority : std_logic := '0';
  
begin

  sprite0: entity work.sprite 
    port map (
      pixelclock => pixelclock,
      sprite_number => 0,
      sprite_h640 => sprite_h640,
      sprite_number_for_data_in => sprite_spritenumber_in,
      
      sprite_sixteen_colour_mode => sprite_sixteen_colour_mode,
      sprite_horizontal_tile_enable => sprite_horizontal_tile_enable,
      sprite_bitplane_enable => sprite_bitplane_enable,
      sprite_extended_height_enable => sprite_extended_height_enable,
      sprite_extended_width_enable => sprite_extended_width_enable,
      sprite_extended_height_size => sprite_extended_height_size,
      sprite_datavalid_in => sprite_datavalid_in,
      sprite_bytenumber_in => sprite_bytenumber_in,
      sprite_spritenumber_in => sprite_spritenumber_in,
      sprite_data_in => sprite_data_in,
      sprite_data_offset_in => sprite_data_offset_in,
      is_foreground_in => is_foreground_in,
      is_background_in => is_background_in,
      x320_in => x320_in,
      x640_in => x640_in,
      y_in => y_in,
      border_in => border_in,
      pixel_in => pixel_in,
      alpha_in => alpha_in,
      is_sprite_in => is_sprite_in,
      sprite_colour_in => sprite_colour_in,
      sprite_map_in => sprite_map_in,
      sprite_fg_map_in => sprite_fg_map_in,

      is_foreground_out => is_foreground_out,
      is_background_out => is_background_out,
      x320_out => x320_out,
      x640_out => x640_out,
      y_out => y_out,
      border_out => border_out,
      pixel_out => pixel_out,
      alpha_out => alpha_out,
      sprite_colour_out => sprite_colour_out,
      is_sprite_out => is_sprite_out,
      sprite_map_out => sprite_map_out,
      sprite_fg_map_out => sprite_fg_map_out,
    
      sprite_enable => sprite_enable,
      sprite_x => sprite_x,
      sprite_y => sprite_y,
      sprite_colour => sprite_colour,
      sprite_multi0_colour => sprite_multi0_colour,
      sprite_multi1_colour => sprite_multi1_colour,
      sprite_is_multicolour => sprite_is_multicolour,
      sprite_stretch_x => sprite_stretch_x,
      sprite_stretch_y => sprite_stretch_y,
      sprite_priority => sprite_priority
      
      );
  
  process
  begin    
    for i in 1 to 40000000 loop
      pixelclock <= '1';
      wait for 10 ns;
      pixelclock <= '0';
      wait for 10 ns;
      pixelclock <= '1';
      wait for 10 ns;
      pixelclock <= '0';
      wait for 10 ns;
      pixelclock <= '1';
      wait for 10 ns;
      pixelclock <= '0';
      wait for 10 ns;
      if pixel_x_640 < 810 then
        pixel_x_640 <= pixel_x_640 + 1;
        if pixel_x_640 = 800 then
          hsync <= '1';
        end if;
      else
        pixel_x_640 <= 0;
        hsync <= '0';
        if ycounter_in < 485 then
          ycounter_in <= ycounter_in + 1;
          if ycounter_in = 479 then
            vsync <= '1';
          end if;
        else
          ycounter_in <= to_unsigned(0,12);
          vsync <= '0';
        end if;
      end if;

      vgared_out <= (others => pixel_out(0));
      vgagreen_out <= (others => pixel_out(1));
      vgablue_out <= (others => pixel_out(2));
      
      report "PIXEL:" & integer'image(pixel_x_640)
        & ":" & integer'image(to_integer(ycounter_in))
        & ":" & to_hstring(vgared_out)
        & ":" & to_hstring(vgagreen_out)
        & ":" & to_hstring(vgablue_out);
    end loop;  -- i
    assert false report "End of simulation" severity note;
  end process;

end behavioral;
