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
    reset : in std_logic;
    cpu_exrom : out std_logic;
    cpu_game : out std_logic;
    sector_buffer_mapped : in std_logic;

    slow_access_request_toggle : in std_logic;
    slow_access_ready_toggle : out std_logic := '0';
    slow_access_write : in std_logic;
    slow_access_address : in unsigned(27 downto 0);
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
    QspiSCK : out std_logic := '1';
    QspiDB : inout std_logic_vector(3 downto 0) := (others => 'Z');
    QspiCSn : out std_logic := '1';
    
    ------------------------------------------------------------------------
    -- C64-compatible cartridge/expansion port
    ------------------------------------------------------------------------
    cart_ctrl_dir : out std_logic;
    cart_haddr_dir : out std_logic;
    cart_laddr_dir : out std_logic;
    cart_data_dir : out std_logic;

    cart_phi2 : out std_logic := 'Z';
    cart_dotclock : out std_logic := 'Z';
    cart_reset : out std_logic := 'Z';

    cart_nmi : in std_logic;
    cart_irq : in std_logic;
    cart_dma : in std_logic;
    
    cart_exrom : inout std_logic := 'Z';
    cart_ba : inout std_logic := 'Z';
    cart_rw : inout std_logic := 'Z';
    cart_roml : inout std_logic := 'Z';
    cart_romh : inout std_logic := 'Z';
    cart_io1 : inout std_logic := 'Z';
    cart_game : inout std_logic := 'Z';
    cart_io2 : inout std_logic := 'Z';
    
    cart_d_in : in unsigned(7 downto 0);
    cart_d : out unsigned(7 downto 0);
    cart_a : inout unsigned(15 downto 0)
    );
end slow_devices;
  
architecture behavioural of slow_devices is

  signal cart_access_request : std_logic := '0';
  signal cart_access_read : std_logic := '1';
  signal cart_access_address : unsigned(31 downto 0) := (others => '1');
  signal cart_access_rdata : unsigned(7 downto 0);
  signal cart_access_wdata : unsigned(7 downto 0) := (others => '1');
  signal cart_access_accept_strobe : std_logic;
  signal cart_access_read_strobe : std_logic;

  signal slow_access_last_request_toggle : std_logic := '1';

  type slow_state is (
    Idle,
    ExpansionRAMRequest,
    CartridgePortRequest,
    CartridgePortAcceptWait
    );

  signal state : slow_state := Idle;
  
begin
  cartport0: entity work.expansion_port_controller
    generic map ( pixelclock_frequency => 150
                  )
    port map (
    cpuclock => cpuclock,
    pixelclock => pixelclock,
    reset => reset,
    cpu_game => cpu_game,
    cpu_exrom => cpu_exrom,
    sector_buffer_mapped => sector_buffer_mapped,

    cart_access_request => cart_access_request,
    cart_access_read => cart_access_read,
    cart_access_address => cart_access_address,
    cart_access_rdata => cart_access_rdata,
    cart_access_wdata => cart_access_wdata,
    cart_access_accept_strobe => cart_access_accept_strobe,
    cart_access_read_strobe => cart_access_read_strobe,
    
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
    cart_d_in => cart_d_in,
    cart_a => cart_a
    );

  generate_fake_cartridge:
  if has_fakecartridge='1' generate
    
  end generate;
  
  process (pixelclock) is
  begin
    if rising_edge(pixelclock) then

      case state is
        when Idle =>    
          if slow_access_last_request_toggle /= slow_access_request_toggle then
            report "Access request for $" & to_hstring(slow_access_address) & ", toggle=" & std_logic'image(slow_access_request_toggle);
            -- XXX do job, and acknowledge when done.

            -- CPU maps expansion port access to $7FF0000-$7FFFFFF for
          -- C64-compatible addressing.  In particular, I/O areas 1 and 2 map
          -- to $7FFDE00-$7FFDFFF, and external SIDs, when enabled, are expected
          -- at $7FFD400-$7FFD4FF.  The I/O expansion areas use the normal
          -- I/O1&2 select signals.
          -- $4000000-$7EFFFFF (= 63MB) is mapped by default to MEGAcart content.
          -- $8000000-$FEFFFFF (=126MB) is mapped by default to expansion RAM.
          --
          -- For the external SIDs, we don't have that
          -- luxury. We would like the external SID cartridge to be safe to use
          -- in a real C64, so we probably shouldn't just have the external
          -- SIDs listen to $D400-$D4FF without some kind of signalling.  However,
          -- if we just present $D4xx and have I/O1 or I/O2 asserted, then normal
          -- I/O expansion cartridges will map whatever their I/O is there, instead
          -- of being selective.  That's not a big problem, provided that we
          -- have a way to definitively detect the SID cartridge. This could be
          -- done by trying to read some other I/O to confirm that the SIDs are
          -- only visible at $D4xx, and not $DExx.
          --
          -- All we have to do is direct access requests based on whether they
          -- are handled by the cartridge/expansion port, or by on-board
          -- expansion RAM of some sort.
          if slow_access_address(27)='1' then
            -- $8000000-$FFFFFFF = expansion RAM
            state <= ExpansionRAMRequest;
          elsif slow_access_address(26)='1' then
            -- $4000000-$7FFFFFF = cartridge port
            report "Preparing to access from C64 cartridge port";
            state <= CartridgePortRequest;
          else
            -- Unmapped address space: Content = "Unmapped"
            case to_integer(slow_access_address(2 downto 0)) is
              when 0 => slow_access_rdata <= x"55";
              when 1 => slow_access_rdata <= x"6e";
              when 2 => slow_access_rdata <= x"6d";
              when 3 => slow_access_rdata <= x"61";
              when 4 => slow_access_rdata <= x"70";
              when 5 => slow_access_rdata <= x"70";
              when 6 => slow_access_rdata <= x"65";
              when 7 => slow_access_rdata <= x"64";
              when others => slow_access_rdata <= x"55";
            end case;
            state <= Idle;
            slow_access_ready_toggle <= slow_access_request_toggle;
          end if;        
        end if;
          
        -- Note toggle state
        slow_access_last_request_toggle <= slow_access_request_toggle;
      when ExpansionRAMRequest =>
        -- XXX Currently not implemented.
        -- Unmapped address space: Content = "ExtraRAM"
        case to_integer(slow_access_address(2 downto 0)) is
          when 0 => slow_access_rdata <= x"45";
          when 1 => slow_access_rdata <= x"78";
          when 2 => slow_access_rdata <= x"74";
          when 3 => slow_access_rdata <= x"72";
          when 4 => slow_access_rdata <= x"61";
          when 5 => slow_access_rdata <= x"52";
          when 6 => slow_access_rdata <= x"41";
          when 7 => slow_access_rdata <= x"4D";
          when others => slow_access_rdata <= x"45";
        end case;
        state <= Idle;
        slow_access_ready_toggle <= slow_access_request_toggle;
      when CartridgePortRequest =>
          report "Starting cartridge port access request, w="
            & std_logic'image(slow_access_write);
        cart_access_request <= '1';
        cart_access_read <= not slow_access_write;
        cart_access_address(27 downto 0) <= slow_access_address;
        cart_access_address(31 downto 28) <= (others => '0');
        cart_access_wdata <= slow_access_wdata;
        if cart_access_accept_strobe = '1' then
          cart_access_request <= '0';
          if slow_access_write = '1' then
            report "C64 cartridge port write dispatched asynchronously.";
            slow_access_ready_toggle <= slow_access_request_toggle;
            state <= Idle;
          else
            state <= CartridgePortAcceptWait;
            report "C64 cartridge port read commenced.";
          end if;
        else
          state <= CartridgePortRequest;
        end if;
      when CartridgePortAcceptWait =>        
        if cart_access_read_strobe = '1' then
          cart_access_request <= '0';
          report "C64 cartridge port access complete"; 
          slow_access_rdata <= cart_access_rdata;
          slow_access_ready_toggle <= slow_access_request_toggle;
          state <= Idle;
        end if;
      end case;
    end if;
  end process;
  
end behavioural;
