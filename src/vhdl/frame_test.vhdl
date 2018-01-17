library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use work.all;
use work.debugtools.all;

entity frame_test is
  
end frame_test;

architecture behavior of frame_test is

  signal pixelclock : std_logic := '0';
  signal cpuclock : std_logic := '0';
  signal ioclock : std_logic := '0';
  
begin

  video_frame0: entity work.video_frame
    port map (
      pixelclock => pixelclock,
      cpuclock => cpuclock,

      frame_width => to_unsigned(100,12),
      display_width => to_unsigned(90,12),
      frame_height => to_unsigned(100,12),
      display_height => to_unsigned(90,12)
      );
  
  process
  begin  -- process tb
    report "beginning simulation" severity note;

    for i in 1 to 2000000 loop
      pixelclock <= '0'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '0'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '0'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;     
      pixelclock <= '0'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;
    end loop;  -- i
    assert false report "End of simulation" severity failure;
  end process;
  
end behavior;

