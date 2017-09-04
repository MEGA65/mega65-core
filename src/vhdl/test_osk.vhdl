use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity test_osk is
end test_osk;

architecture behavioral of test_osk is

  signal pixel_x_640 : integer := 0;
  signal frames : integer := 0;
  signal ycounter_in : unsigned(11 downto 0) := (others => '0');
  signal x_start : unsigned(11 downto 0) := to_unsigned(0,12);
  signal y_start : unsigned(11 downto 0) := to_unsigned(479-290,12);
  signal pixelclock : std_logic := '1';
  signal visual_keyboard_enable : std_logic := '0';
  signal keyboard_at_top : std_logic := '0';
  signal alternate_keyboard : std_logic := '1';
  signal key1 : unsigned(7 downto 0) := x"53";
  signal key2 : unsigned(7 downto 0) := x"52";
  signal key3 : unsigned(7 downto 0) := x"51";
  signal key4 : unsigned(7 downto 0) := x"50";
  signal touch1_valid : std_logic := '1';
  signal touch1_x : unsigned(13 downto 0) := to_unsigned(200,14);
  signal touch1_y : unsigned(11 downto 0) := to_unsigned(400,12);
  signal touch2_valid : std_logic := '1';
  signal touch2_x : unsigned(13 downto 0) := to_unsigned(100,14);
  signal touch2_y : unsigned(11 downto 0) := to_unsigned(40,12);
  
  signal vgared_in : unsigned (7 downto 0) := x"00";
  signal vgagreen_in : unsigned (7 downto 0) := x"FF";
  signal vgablue_in : unsigned (7 downto 0) := x"00";
  signal vgared_out : unsigned (7 downto 0);
  signal vgagreen_out : unsigned (7 downto 0);
  signal vgablue_out : unsigned (7 downto 0);
  
begin
  kc0: entity work.visual_keyboard
    port map(
      pixel_x_640_in => pixel_x_640,
      pixel_y_scale_200 => to_unsigned(2,4),
      pixel_y_scale_400 => to_unsigned(1,4),
      x_start => x_start,
      y_start => y_start,
      ycounter_in => ycounter_in,
      pixelclock => pixelclock,
      visual_keyboard_enable => visual_keyboard_enable,
      keyboard_at_top => keyboard_at_top,
      alternate_keyboard => alternate_keyboard,
      key1 => key1,
      key2 => key2,
      key3 => key3,
      key4 => key4,
      touch1_valid => touch1_valid,
      touch1_x => touch1_x,
      touch1_y => touch1_y,
      touch2_valid => touch2_valid,
      touch2_x => touch2_x,
      touch2_y => touch2_y,
      vgared_in => vgared_in,
      vgagreen_in => vgagreen_in,
      vgablue_in => vgablue_in,
      vgared_out => vgared_out,
      vgagreen_out => vgagreen_out,
      vgablue_out => vgablue_out
    );

  process
  begin
    for i in 1 to 200000000 loop
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
      else
        pixel_x_640 <= 0;
        if ycounter_in < 480 then
          ycounter_in <= ycounter_in + 1;
        else
          ycounter_in <= to_unsigned(0,12);
          if frames = 1 then
            visual_keyboard_enable <= '1';
          end if;
          frames <= frames + 1;
          if frames = 24 then
            keyboard_at_top <= '1';
          end if;
          if frames = 55 then
            keyboard_at_top <= '0';
          end if;
          if frames = 90 then
            visual_keyboard_enable <= '0';
          end if;
        end if;
      end if;
      report "PIXEL:" & integer'image(pixel_x_640)
        & ":" & integer'image(to_integer(ycounter_in))
        & ":" & to_hstring(vgared_out)
        & ":" & to_hstring(vgagreen_out)
        & ":" & to_hstring(vgablue_out);
    end loop;  -- i
    assert false report "End of simulation" severity note;
  end process;

end behavioral;
