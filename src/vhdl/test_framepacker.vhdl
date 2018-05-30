library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_framepacker is
end entity;

architecture foo of test_framepacker is

  signal clock50mhz : std_logic := '1';

  signal red : unsigned(7 downto 0) := x"00";
  signal green : unsigned(7 downto 0) := x"00";
  signal blue : unsigned(7 downto 0) := x"FF";
  signal pixel_valid : std_logic := '0';
  signal pixel_newframe : std_logic := '0';
  signal pixel_newraster : std_logic := '0';

  signal x_counter : integer := 0;
  signal pixel_y : unsigned(11 downto 0) := to_unsigned(0,12);
  
begin

  block2: block
  begin
  framepacker0: entity work.framepacker port map (
    ioclock => clock50mhz,
    pixelclock => clock50mhz,
    hypervisor_mode => '0',
    thumbnail_cs => '0',

    pixel_stream_in => x"00",
    pixel_red_in => red,
    pixel_green_in => green,
    pixel_blue_in => blue,
    pixel_y => pixel_y,
    pixel_valid => pixel_valid,
    pixel_newframe => pixel_newframe,
    pixel_newraster => pixel_newraster,

    buffer_address => x"000",

    fastio_read => '0',
    fastio_addr => x"00000",
    fastio_write => '0',
    fastio_wdata => x"00"
    );
  end block;  

  process is
  begin
    x_counter <= x_counter + 1;
    if x_counter < 53 then
      red <= x"80";
      green <= x"80";
      blue <= x"FF";
    elsif x_counter < 308 then
      red <= x"00";
      green <= x"00";
      blue <= x"ff";
    elsif (x_counter < 324) and pixel_y(0)='0' then
      red <= x"80";
      green <= x"80";
      blue <= x"ff";
    elsif x_counter < 690 then
      red <= x"00";
      green <= x"00";
      blue <= x"FF";
    else
      red <= x"80";
      green <= x"80";
      blue <= x"ff";
    end if;
    if x_counter = 799 then
      x_counter <= 0;
      pixel_newraster <= '1';
      if pixel_y /= 599 then
        pixel_y <= pixel_y + 1;
        pixel_newframe <= '0';
      else
        pixel_y <= x"000";
        pixel_newframe <= '1';
      end if;
    else
      pixel_newframe <= '0';
      pixel_newraster <= '0';      
    end if;
    
    pixel_valid <= '1';
    clock50mhz <= '0';  
    wait for 10 ns;   
    clock50mhz <= '1';        
    wait for 10 ns;
      
    pixel_newframe <= '0';
    pixel_newraster <= '0';      
    pixel_valid <= '0';
    
    clock50mhz <= '0';
    wait for 10 ns;
    clock50mhz <= '1';
    wait for 10 ns;

    clock50mhz <= '0';
    wait for 10 ns;
    clock50mhz <= '1';
    wait for 10 ns;

    clock50mhz <= '0';
    wait for 10 ns;
    clock50mhz <= '1';
    wait for 10 ns;
    
  end process;

  -- Implement simulated I2C slave
  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then
    end if;
  end process;
  
end foo;
