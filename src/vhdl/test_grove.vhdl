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

  signal read_req : std_logic;
  signal data_to_master : std_logic_vector(7 downto 0) := x"01";
  signal data_valid : std_logic;
  signal data_from_master : std_logic_vector(7 downto 0);
  
begin

  i2c1: entity work.grove_i2c
    generic map (
      clock_frequency => 50_000_000
      )
    port map (
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

  slave1: entity work.i2c_slave
    generic map (
      SLAVE_ADDR => "1101000"
      )
    port map (
      scl => scl,
      sda => sda,
      clk => clock50mhz,
      rst => '0',
      read_req => read_req,
      data_to_master => data_to_master,
      data_valid => data_valid,
      data_from_master => data_from_master
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

      -- Provide ever changing value for dummy I2C slave
      if read_req='1' then
        data_to_master <= std_logic_vector(to_unsigned(to_integer(unsigned(data_to_master))+1,8));
      end if;
      
    end if;
  end process;

end foo;
