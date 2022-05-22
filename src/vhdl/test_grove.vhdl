library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_grove is
end entity;

architecture foo of test_grove is

  signal clock50mhz : std_logic := '1';

  signal sda : std_logic := '1';
  signal scl : std_logic := '1';
  signal sda_last : std_logic := '1';
  signal scl_last : std_logic := '1';

begin

  i2c1: entity work.mega65r2_i2c port map (
    clock => clock50mhz,
    cs => '1',
    
    sda => sda,
    scl => scl,
    
    fastio_addr => to_unsigned(16+16,20),
    fastio_write => '0',
    fastio_read => '0',
    fastio_wdata => x"00"
--    std_logic_vector(fastio_rdata) => data_o
    
    );
  
  
  process is
  begin
    clock50mhz <= '0';  
    wait for 10 ns;   
    clock50mhz <= '1';        
    wait for 10 ns;
      
    clock50mhz <= '0';
    wait for 10 ns;
    clock50mhz <= '1';
    wait for 10 ns;
      
  end process;

  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then
      sda_last <= sda;
      scl_last <= scl;
      if sda /= sda_last or scl /= scl_last then
        report "SDA=" & std_logic'image(sda) &
          ", SCL=" & std_logic'image(scl);
      end if;  
    end if;
  end process;

end foo;
