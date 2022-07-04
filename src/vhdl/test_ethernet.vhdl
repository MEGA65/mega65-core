library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_ethernet is
end entity;

architecture foo of test_ethernet is

  signal clock50mhz : std_logic := '1';
  signal clock200 : in std_logic;
  signal reset : in std_logic;
  signal irq : out std_logic := '1';
  signal ethernet_cs : in std_logic;

  signal cpu_ethernet_stream : out std_logic := '0';
    
    ---------------------------------------------------------------------------
    -- IO lines to the ethernet controller
    ---------------------------------------------------------------------------
  signal eth_mdio : std_logic := 'Z';
  signal eth_mdc : std_logic;
  signal eth_reset : std_logic;
  signal eth_rxd_in : unsigned(1 downto 0) := "00";
  signal eth_txd_out : unsigned(1 downto 0);
  signal eth_txen_out : std_logic;
  signal eth_rxdv_in : std_logic := '0';
  signal eth_rxer : std_logic := '0';
  signal eth_interrupt : std_logic := '0';
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
  signal fastio_addr : unsigned(19 downto 0) := (others => '0');
  signal fastio_write : std_logic := '0';
  signal fastio_read : std_logic := '0';
  signal fastio_wdata : unsigned(7 downto 0) := x"42";
  signal fastio_rdata : unsigned(7 downto 0);

    ---------------------------------------------------------------------------
    -- compressed video stream from the VIC-IV frame packer for autonomous dispatch
    ---------------------------------------------------------------------------    
  signal buffer_moby_toggle :  std_logic := '0';
  signal buffer_offset : unsigned(11 downto 0) := to_unsigned(0,12);
  signal buffer_address : unsigned(11 downto 0);
  signal buffer_rdata : unsigned(7 downto 0) := x"42";

  signal instruction_strobe : std_logic := '0';
  signal raster_number : unsigned(11 downto 0) := (others => '0');
  signal vicii_raster : unsigned(11 downto 0) := (others => '0');
  signal badline_toggle : std_logic := '0';
  signal debug_vector : unsigned(63 downto 0) := (others => '0');
  signal d031_write_toggle : std_logic := '0';
  signal cpu_arrest : std_logic;    

begin

    eth0: entity work.ethernet 
      generic map (
        num_buffers => 4
        )
    port map (
    clock => clock50mhz,
    clock50mhz => clock50mhz,
    clock200 => clock200,
    reset => reset,
    irq => irq,
    ethernet_cs => cs,

    ---------------------------------------------------------------------------
    -- IO lines to the ethernet controller
    ---------------------------------------------------------------------------
    eth_mdio => eth_mdio,
    eth_rxd_in => eth_rxd_in,
    eth_rxdv_in => eth_rxdv_in,
    eth_rxer => eth_rxer,
    eth_interrupt => eth_interrupt,
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr => fastio_addr,
    fastio_write => fastio_write,
    fastio_read => fastio_read,
    fastio_wdata => fastio_wdata,
    fastio_rdata => fastio_rdata,

    ---------------------------------------------------------------------------
    -- compressed video stream from the VIC-IV frame packer for autonomous dispatch
    ---------------------------------------------------------------------------    
    buffer_moby_toggle => '0',
    buffer_offset => (others => '0'),
    buffer_rdata => x"00",

    instruction_strobe => '0',
    raster_number => to_unsigned(0,12),
    vicii_raster => to_unsigned(0,12),
    badline_toggle => '0',
    debug_vector => (others => '0'),
    d031_write_toggle => '

    );

    process is
      for i in 1 to 10000000 loop
        clock200mhz <= '0';
        clock50mhz <= '0';
        wait for 2.5ns;
        clock200mhz <= '1';
        clock50mhz <= '0';
        wait for 2.5ns;
        clock200mhz <= '0';
        clock50mhz <= '0';
        wait for 2.5ns;
        clock200mhz <= '1';
        clock50mhz <= '0';
        wait for 2.5ns;
        clock200mhz <= '0';
        clock50mhz <= '1';
        wait for 2.5ns;
        clock200mhz <= '1';
        clock50mhz <= '1';
        wait for 2.5ns;
        clock200mhz <= '0';
        clock50mhz <= '1';
        wait for 2.5ns;
        clock200mhz <= '1';
        clock50mhz <= '1';
        wait for 2.5ns;
      end loop;
    end process;

end foo;
