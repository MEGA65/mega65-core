use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;
use work.victypes.all;

entity internal1541 is
  port (
    clock : in std_logic;
    
    -- CPU side interface to read/write both the 16KB drive "ROM" and the 2KB
    -- drive RAM.    
    fastio_read : in std_logic;
    fastio_write : in std_logic;    
    fastio_address : in unsigned(19 downto 0);
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0);
    cs_driverom : in std_logic;
    cs_driveram : in std_logic;
    
    -- Drive CPU clock strobes.
    -- This allows us to accelerate the 1541 at the same ratio as the CPU,
    -- so that fast loaders can be accelerated.
    drive_clock_cycle_strobe : in std_logic;
    -- Assert high to hold the drive CPU under reset
    drive_reset : in std_logic;
    -- Assert when the drive should be fully suspended
    -- (for freezing / resuming )
    drive_suspend : in std_logic;
    
    -- Interface to SD card data feed
    -- Here we read non-GCR bytes and turn them to GCR.
    -- We thus have a current byte, and then ask for the next when we will need
    -- it.  We also need to tell the SD controller which track we are on, so that
    -- it can feed the correct data to us.  If the SD card is not ready, then
    -- we keep feeding pretending to feed gap bytes.
    sd_data_byte : in unsigned(7 downto 0);
    sd_data_ready_toggle : in std_logic;
    sd_data_request_toggle : out std_logic := '0';
    sd_1541_enable : out std_logic := '0'; -- data flows only when enabled,
                                           -- i.e., when we think the motor is
                                           -- on
    sd_1541_track : out unsigned(5 downto 0) := to_unsigned(18,6)

    );
end entity internal1541;

architecture romanesque_revival of internal1541 is

  -- signals here
  signal address : unsigned(15 downto 0) := x"0000";
  signal rdata : unsigned(7 downto 0);
  signal wdata : unsigned(7 downto 0);
  signal ram_write_enable : std_logic := '0';
  signal nmi : std_logic := '1';
  signal irq : std_logic := '1';
  signal cpu_write : std_logic := '0';

 component cpu6502 is
    port (
      address : buffer unsigned(15 downto 0);
      address_next : out unsigned(15 downto 0);
      clk : in std_logic;
      cpu_int : out std_logic;
      cpu_state : out unsigned(7 downto 0);
      data_i : in unsigned(7 downto 0);
      data_o : out unsigned(7 downto 0);
      data_o_next : out unsigned(7 downto 0);
      irq : in std_logic;
      nmi : in std_logic;
      ready : in std_logic;
      reset : in std_logic;
      sync : buffer std_logic;
      t : out unsigned(2 downto 0);
      write : out std_logic;
      write_next : buffer std_logic
    );
  end component;

begin
  
  -- XXX Add the missing 6522 VIAs

  ram: entity work.dpram8x4096 port map (
    -- Fastio interface
    clka => clock,
    ena => cs_driveram,
    wea(0) => fastio_write,
    addra => std_logic_vector(fastio_address(11 downto 0)),
    dina => std_logic_vector(fastio_wdata),
    unsigned(douta) => fastio_rdata,

    clkb => clock,
    web(0) => ram_write_enable,
    addrb => std_logic_vector(address(11 downto 0)),
    dinb => std_logic_vector(wdata),
    unsigned(doutb) => rdata
    );

  rom: entity work.driverom port map (
    -- Fast IO interface
    clka => clock,
    csa => cs_driverom,
    addressa => to_integer(fastio_address(13 downto 0)),
    wea => fastio_write,
    dia => fastio_wdata,
    doa => fastio_rdata,

    -- CPU interface
    clkb => clock,
    addressb => to_integer(address),
    dob => rdata
    );

  cpu: component cpu6502 port map (
    clk => clock,
    reset => drive_reset,
    nmi => nmi,
    irq => irq,
    ready => drive_clock_cycle_strobe,
    write => cpu_write,
--    sync => cpu_sync,
    address => address,
    data_i => rdata,
    data_o => wdata   
    );
  
  process(clock)
  begin
  end process;

end romanesque_revival;
