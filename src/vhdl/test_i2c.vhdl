library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_i2c is
end entity;

architecture foo of test_i2c is

  signal clock50mhz : std_logic := '1';

  signal hdmi_cs : std_logic := '0';
  signal hdmi_int : std_logic := '1';
  signal fastio_addr : unsigned(19 downto 0) := (others => '0');
  signal fastio_rdata : unsigned(7 downto 0) := (others => '0');
  signal fastio_wdata : unsigned(7 downto 0) := (others => '0');
  signal fastio_read : std_logic :='0';
  signal fastio_write : std_logic :='0';
  
  signal sda : std_logic := '1';
  signal scl : std_logic := '1';
  signal sda_last : std_logic := '1';
  signal scl_last : std_logic := '1';

  signal cycle_counter : integer := 0;
  
begin

  i2c1: entity work.mega65r2_i2c port map (
    clock => clock50mhz,
    cs => '1',
    
    sda => sda,
    scl => scl,
    
    fastio_addr => to_unsigned(16,20),
    fastio_write => '1',
    fastio_read => '0',
    fastio_wdata => x"42"
--    std_logic_vector(fastio_rdata) => data_o
    
    );
  
  
  process is
  begin
    clock50mhz <= '0';  
    wait for 10 ns;   
    clock50mhz <= '1';        
    wait for 10 ns;

    cycle_counter <= cycle_counter + 1;
    
  end process;

  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then


    end if;
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
