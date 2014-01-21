use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity iomapper is
  port (Clk : in std_logic;
        reset : in std_logic;
        irq : out std_logic;
        nmi : out std_logic;
        address : in std_logic_vector(19 downto 0);
        r : in std_logic;
        w : in std_logic;
        data_i : in std_logic_vector(7 downto 0);
        data_o : out std_logic_vector(7 downto 0);

        ps2data : in std_logic;
        ps2clock : in std_logic;
        last_scan_code : out unsigned(11 downto 0);
        
        colourram_at_dc00 : in std_logic
        );
end iomapper;

architecture behavioral of iomapper is
  component kernel65 is
    port (
      Clk : in std_logic;
      address : in std_logic_vector(12 downto 0);
      we : in std_logic;
      cs : in std_logic;
      data_i : in std_logic_vector(7 downto 0);
      data_o : out std_logic_vector(7 downto 0));
  end component;
  component kernel64 is
    port (
      Clk : in std_logic;
      address : in std_logic_vector(12 downto 0);
      we : in std_logic;
      cs : in std_logic;
      data_i : in std_logic_vector(7 downto 0);
      data_o : out std_logic_vector(7 downto 0));
  end component;
  component basic64 is
    port (
      Clk : in std_logic;
      address : in std_logic_vector(12 downto 0);
      we : in std_logic;
      cs : in std_logic;
      data_i : in std_logic_vector(7 downto 0);
      data_o : out std_logic_vector(7 downto 0));
  end component;
  component cia6526 is
    port (
      cpuclock : in std_logic;
      todclock : in std_logic;
      reset : in std_logic;
      irq : out std_logic := '1';

      ---------------------------------------------------------------------------
      -- fast IO port (clocked at core clock). 1MB address space
      ---------------------------------------------------------------------------
      cs : in std_logic;
      fastio_addr : in unsigned(3 downto 0);
      fastio_write : in std_logic;
      fastio_wdata : in unsigned(7 downto 0);
      fastio_rdata : out unsigned(7 downto 0);

      portaout : out std_logic_vector(7 downto 0);
      portain : in std_logic_vector(7 downto 0);
      
      portbout : out std_logic_vector(7 downto 0);
      portbin : in std_logic_vector(7 downto 0);

      flagin : in std_logic;

      pcout : out std_logic;

      spout : out std_logic;
      spin : in std_logic;

      countout : out std_logic;
      countin : in std_logic);
  end component;
  component keymapper is    
    port (
      clk : in std_logic;
      
      -- PS2 keyboard interface
      ps2clock  : in  std_logic;
      ps2data   : in  std_logic;
      -- CIA ports
      porta_in  : in  std_logic_vector(7 downto 0);
      porta_out : out std_logic_vector(7 downto 0);
      portb_in  : in  std_logic_vector(7 downto 0);
      portb_out : out std_logic_vector(7 downto 0);

      last_scan_code : out unsigned(11 downto 0);

      ---------------------------------------------------------------------------
      -- Fastio interface to recent keyboard scan codes
      ---------------------------------------------------------------------------    
      fastio_address : in std_logic_vector(19 downto 0);
      fastio_write : in std_logic;
      fastio_wdata : in std_logic_vector(7 downto 0);
      fastio_rdata : out std_logic_vector(7 downto 0)

      );
  end component;


  signal kernel65cs : std_logic;
  signal kernel64cs : std_logic;
  signal basic64cs : std_logic;

  signal clock50hz : std_logic := '1';
  constant divisor50hz : integer := 640000; -- 64MHz/50Hz/2;
  signal counter50hz : integer := 0;
  
  signal cia1cs : std_logic;
  signal cia2cs : std_logic;

  signal cia1porta_out : std_logic_vector(7 downto 0);
  signal cia1porta_in : std_logic_vector(7 downto 0);
  signal cia1portb_out : std_logic_vector(7 downto 0);
  signal cia1portb_in : std_logic_vector(7 downto 0);
  
begin         
  kernel65rom : kernel65 port map (
    clk     => clk,
    address => address(12 downto 0),
    we      => w,
    cs      => kernel65cs,
    data_i  => data_i,
    data_o  => data_o);

  kernel64rom : kernel64 port map (
    clk     => clk,
    address => address(12 downto 0),
    we      => w,
    cs      => kernel64cs,
    data_i  => data_i,
    data_o  => data_o);

  basic64rom : basic64 port map (
    clk     => clk,
    address => address(12 downto 0),
    we      => w,
    cs      => basic64cs,
    data_i  => data_i,
    data_o  => data_o);

  cia1: cia6526 port map (
    cpuclock => clk,
    todclock => clock50hz,
    reset => reset,
    irq => irq,
    cs => cia1cs,
    fastio_addr => unsigned(address(3 downto 0)),
    fastio_write => w,
    std_logic_vector(fastio_rdata) => data_o,
    fastio_wdata => unsigned(data_i),

    portaout => cia1porta_out,
    portbout => cia1portb_out,
    portain => cia1porta_in,
    portbin => cia1portb_in,
    flagin => '1',
    spin => '1',
    countin => '1'
    );

  cia2: cia6526 port map (
    cpuclock => clk,
    todclock => clock50hz,
    reset => reset,
    irq => nmi,
    cs => cia2cs,
    fastio_addr => unsigned(address(3 downto 0)),
    fastio_write => w,
    std_logic_vector(fastio_rdata) => data_o,
    fastio_wdata => unsigned(data_i),

    -- CIA ports not connected by default
    portbin => x"20",
    portain => x"65",
    flagin => '1',
    spin => '1',
    countin => '1'
    );

  keymapper0 : keymapper port map (
    clk            => clk,
    ps2clock       => ps2clock,
    ps2data        => ps2data,
    porta_in       => cia1porta_out,
    porta_out      => cia1porta_in,
    portb_in       => cia1portb_out,
    portb_out      => cia1portb_in,
--    last_scan_code => last_scan_code,

    fastio_address => address,
    fastio_write => w,
    fastio_wdata => x"FF",
    std_logic_vector(fastio_rdata) => data_o
    );
  
  process (r,w,address)
  begin  -- process
    last_scan_code(7 downto 0) <= unsigned(cia1portb_in);
    last_scan_code(11 downto 8) <= unsigned(cia1porta_out(3 downto 0));
    
    if (r or w) = '1' then
      if address(19 downto 13)&'0' = x"FE" then
        kernel65cs<= '1';
      else
        kernel65cs <='0';
      end if;
      if address(19 downto 13)&'0' = x"EE" then
        kernel64cs<= '1';
      else
        kernel64cs <='0';
      end if;
      if address(19 downto 13)&'0' = x"EA" then
        basic64cs<= '1';
      else
        basic64cs <='0';
      end if;

      -- Now map the CIAs.

      -- Generate 50Hz signal for TOD clock
      -- (Note that we are a bit conflicted here, as our video mode is PALx4,
      --  but at 50Hz.  We will make our CIAs take 50Hz like in most PAL countries
      -- so that we don't confuse things too much.  We will probably add a 50Hz
      -- raster interrupt filter to help music and games play at the right rate.)
      if counter50hz<divisor50hz then
        counter50hz <= counter50hz + 1;
      else
        clock50hz <= not clock50hz;
        counter50hz <= 0;
      end if;
      
      -- These are a bit fun, because they only get mapped if colour RAM isn't
      -- being mapped in $DC00-$DFFF using the C65 2K colour ram register
      cia1cs <='0';
      cia2cs <='0';
      if colourram_at_dc00='0' then
        case address(19 downto 8) is
          when x"D0C" => cia1cs <='1';
          when x"D1C" => cia1cs <='1';
          when x"D2C" => cia1cs <='1';
          when x"D3C" => cia1cs <='1';
          when x"D0D" => cia2cs <='1';
          when x"D1D" => cia2cs <='1';
          when x"D2D" => cia2cs <='1';
          when x"D3D" => cia2cs <='1';
          when others => null;
        end case;
      end if;
    else
      cia1cs <= '0';
      cia2cs <= '0';
      kernel65cs <= '0';
      kernel64cs <= '0';
      basic64cs <= '0';
    end if;
  end process;

end behavioral;
