use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY slow_devices IS
  generic (
    has_quad_flash : std_logic := '0';
    has_psram : std_logic := '0';
    has_hyperram : std_logic := '0';
    has_c64_cartridge_port : std_logic := '0';
    has_fakecartridge : std_logic := '0'
    );
  PORT (
    ------------------------------------------------------------------------
    -- CPU side interface
    ------------------------------------------------------------------------
    pixelclock : in std_logic;
    cpuclock : in std_logic;

    slow_access_request_toggle : in std_logic;
    slow_access_ready_toggle : out std_logic := '0';

    slow_access_address : in unsigned(31 downto 0);
    slow_access_wdata : in unsigned(7 downto 0);
    slow_access_rdata : out unsigned(7 downto 0);

    ------------------------------------------------------------------------
    -- PSRAM (Nexys4 "slowram")
    ------------------------------------------------------------------------

    ------------------------------------------------------------------------
    -- HyperRAM (M65 PCB r2 onwards)
    ------------------------------------------------------------------------

    ----------------------------------------------------------------------
    -- Flash RAM for holding FPGA config
    ----------------------------------------------------------------------
    QspiSCK : out std_logic;
    QspiDB : inout std_logic_vector(3 downto 0);
    QspiCSn : out std_logic;
    
    ------------------------------------------------------------------------
    -- C64-compatible cartridge/expansion port
    ------------------------------------------------------------------------
    cart_ctrl_dir : out std_logic;
    cart_haddr_dir : out std_logic;
    cart_laddr_dir : out std_logic;
    cart_data_dir : out std_logic;

    cart_phi2 : out std_logic;
    cart_dotclock : out std_logic;
    cart_reset : out std_logic;

    cart_nmi : in std_logic;
    cart_irq : in std_logic;
    cart_dma : in std_logic;
    
    cart_exrom : inout std_logic;
    cart_ba : inout std_logic;
    cart_rw : inout std_logic;
    cart_roml : inout std_logic;
    cart_romh : inout std_logic;
    cart_io1 : inout std_logic;
    cart_game : inout std_logic;
    cart_io2 : inout std_logic;
    
    cart_d : inout unsigned(7 downto 0);
    cart_a : inout unsigned(15 downto 0)
    );
end slow_devices;
  
architecture behavioural of slow_devices is

  signal cart_access_request : std_logic := '0';
  signal cart_access_read : std_logic;
  signal cart_access_address : unsigned(15 downto 0);
  signal cart_access_wdata : unsigned(7 downto 0);
  signal cart_access_accept_strobe : std_logic;

  
begin
  cartport0: entity work.expansion_port_controller
    generic map ( pixelclock_frequency => 150
                  )
    port map (
    cpuclock => cpuclock,
    pixelclock => pixelclock,

    cart_access_request => cart_access_request,
    cart_access_read => cart_access_read,
    cart_access_address => cart_access_address,
    cart_access_wdata => cart_access_wdata,
    cart_access_accept_strobe => cart_access_accept_strobe,
    
    cart_ctrl_dir => cart_ctrl_dir,
    cart_haddr_dir => cart_haddr_dir,
    cart_laddr_dir => cart_laddr_dir,
    cart_data_dir => cart_data_dir,
    cart_phi2 => cart_phi2,
    cart_dotclock => cart_dotclock,
    cart_reset => cart_reset,
      
    cart_nmi => cart_nmi,
    cart_irq => cart_irq,
    cart_dma => cart_dma,
    
    cart_exrom => cart_exrom,
    cart_ba => cart_ba,
    cart_rw => cart_rw,
    cart_roml => cart_roml,
    cart_romh => cart_romh,
    cart_io1 => cart_io1,
    cart_game => cart_game,
    cart_io2 => cart_io2,
    
    cart_d => cart_d,
    cart_a => cart_a
    );

  generate_fake_cartridge:
  if has_fakecartridge='1' generate
    
  end generate;
  
  process (pixelclock) is
  begin
  end process;
  
end behavioural;
