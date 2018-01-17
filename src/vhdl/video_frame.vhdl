library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.victypes.all;
use work.all;

entity video_frame is
  port (
    pixelclock : in std_logic;
    cpuclock : in std_logic;
    
    xcounter : out unsigned(11 downto 0) := (others => '0');
    ycounter : out unsigned(11 downto 0) := (others => '0');

    vsync : out  STD_LOGIC := '0';
    hsync : out  STD_LOGIC := '0';

    frame_width : in unsigned(11 downto 0);  -- cycles per raster
    display_width : in unsigned(11 downto 0);  -- hsync starts here
    frame_height : in unsigned(11 downto 0); -- rasters per frame, including vsync
    display_height : in unsigned(11 downto 0) -- vsync starts here
    );
end video_frame;

architecture behavioral of video_frame is
  signal y : unsigned(11 downto 0) := (others => '0');
  signal x : unsigned(11 downto 0) := (others => '0');
  signal x_flyback : std_logic := '0';
  signal y_flyback : std_logic := '0';
begin
  process (pixelclock) is
  begin
    if rising_edge(pixelclock) then
      if x = display_width then
        x_flyback <= '1';
      end if;
      if x = frame_width then
        x <= to_unsigned(0,12);
      else
        x <= x + 1;
      end if;
      if x = to_unsigned(0,12) then
        x_flyback <= '0';
        if y = frame_height then
          y <= to_unsigned(0,12);
          y_flyback <= '0';
        else
          if y = display_height then
            y_flyback <= '1';
          end if;
          y <= y + 1;
        end if;
      end if;
      xcounter <= x;
      ycounter <= y;
      vsync <= y_flyback;
      hsync <= x_flyback;
      report "xcounter=" & integer'image(to_integer(x))
        & " ycounter=" & integer'image(to_integer(y))
        & " hsync=" & std_logic'image(x_flyback)
        & " vsync=" & std_logic'image(y_flyback);
    end if;
  end process;
end behavioral;
