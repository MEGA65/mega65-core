library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use work.all;

entity cpu_test is
  
end cpu_test;

architecture behavior of cpu_test is
  signal clock : std_logic := '0';
  signal cpuclock : std_logic := '0';
  signal reset : std_logic := '0';
  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';
  signal monitor_pc : std_logic_vector(15 downto 0);
  signal monitor_opcode : std_logic_vector(7 downto 0);
  signal monitor_a : std_logic_vector(7 downto 0);
  signal monitor_x : std_logic_vector(7 downto 0);
  signal monitor_y : std_logic_vector(7 downto 0);
  signal monitor_sp : std_logic_vector(7 downto 0);
  signal monitor_p : std_logic_vector(7 downto 0);

  signal vsync : std_logic;
  signal hsync : std_logic;
  signal vgared : unsigned(3 downto 0);
  signal vgagreen : unsigned(3 downto 0);
  signal vgablue : unsigned(3 downto 0);

  signal led0 : std_logic;
  signal led1 : std_logic;
  signal led2 : std_logic;
  signal led3 : std_logic;
  signal sw : std_logic_vector(15 downto 0) := (others => '0');
  signal btn : std_logic_vector(4 downto 0) := (others => '0');
  
  component simple6502
    port (
      Clock : in std_logic;
      reset : in std_logic;
      irq : in std_logic;
      nmi : in std_logic;
      monitor_pc : out std_logic_vector(15 downto 0);
      monitor_opcode : out std_logic_vector(7 downto 0);
      monitor_a : out std_logic_vector(7 downto 0);
      monitor_x : out std_logic_vector(7 downto 0);
      monitor_y : out std_logic_vector(7 downto 0);
      monitor_sp : out std_logic_vector(7 downto 0);
      monitor_p : out std_logic_vector(7 downto 0);

      ---------------------------------------------------------------------------
      -- Interface to FastRAM in video controller (just 128KB for now)
      ---------------------------------------------------------------------------
      fastram_we : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      fastram_read : OUT STD_LOGIC;
      fastram_write : OUT STD_LOGIC;
      fastram_address : OUT STD_LOGIC_VECTOR(13 DOWNTO 0);
      fastram_datain : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
      fastram_dataout : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
      
      ---------------------------------------------------------------------------
      -- fast IO port (clocked at core clock). 1MB address space
      ---------------------------------------------------------------------------
      fastio_addr : out std_logic_vector(19 downto 0);
      fastio_read : out std_logic;
      fastio_write : out std_logic;
      fastio_wdata : out std_logic_vector(7 downto 0);
      fastio_rdata : in std_logic_vector(7 downto 0)
      );
  end component;

  component vga is
    Port (
      ----------------------------------------------------------------------
      -- 100MHz Nexys4 master clock from which we drive the dotclock
      ----------------------------------------------------------------------
      pixelclock : in  STD_LOGIC;
      cpuclock : in std_logic;

      ----------------------------------------------------------------------
      -- VGA output
      ----------------------------------------------------------------------
      vsync : out  STD_LOGIC;
      hsync : out  STD_LOGIC;
      vgared : out  UNSIGNED (3 downto 0);
      vgagreen : out  UNSIGNED (3 downto 0);
      vgablue : out  UNSIGNED (3 downto 0);

      -----------------------------------------------------------------------------
      -- Interface to 128KB fastram
      -----------------------------------------------------------------------------
      ramaddress : OUT STD_LOGIC_VECTOR(13 DOWNTO 0);
      ramdata : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
      
      -----------------------------------------------------------------------------
      -- FastIO interface for accessing video registers
      -----------------------------------------------------------------------------
      fastio_addr : in std_logic_vector(19 downto 0);
      fastio_read : in std_logic;
      fastio_write : in std_logic;
      fastio_wdata : in std_logic_vector(7 downto 0);
      fastio_rdata : out std_logic_vector(7 downto 0);

      ----------------------------------------------------------------------
      -- Debug interfaces on Nexys4 board
      ----------------------------------------------------------------------
      led0 : out std_logic;
      led1 : out std_logic;
      led2 : out std_logic;
      led3 : out std_logic;
      sw : in std_logic_vector(15 downto 0);
      btn : in std_logic_vector(4 downto 0)

      );
  end component;
  
  component cpu6502
    port (   clock : in STD_LOGIC;
             reset : in  STD_LOGIC;
             irq : in  STD_LOGIC;
             nmi : in  STD_LOGIC;
             monitor_pc : out STD_LOGIC_VECTOR(15 downto 0);
             monitor_opcode : out std_logic_vector(7 downto 0);
             monitor_a : out std_logic_vector(7 downto 0);
             monitor_x : out std_logic_vector(7 downto 0);
             monitor_y : out std_logic_vector(7 downto 0);
             monitor_sp : out std_logic_vector(7 downto 0);
             monitor_p : out std_logic_vector(7 downto 0);

             -- fast IO port (clocked at core clock)
             fastio_addr : inout std_logic_vector(19 downto 0);
             fastio_read : out std_logic;
             fastio_write : out std_logic;
             fastio_wdata : out std_logic_vector(7 downto 0);
             fastio_rdata : in std_logic_vector(7 downto 0);

             -- fastram port
             fastram_we : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
             fastram_address : OUT STD_LOGIC_VECTOR(13 DOWNTO 0);
             fastram_datain : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
             fastram_dataout : IN STD_LOGIC_VECTOR(63 DOWNTO 0)
             );      
  end component;

 component ram64x16k
    PORT (
      clka : IN STD_LOGIC;
      wea : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      addra : IN STD_LOGIC_VECTOR(13 DOWNTO 0);
      dina : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
      douta : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
      clkb : IN STD_LOGIC;
      web : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      addrb : IN STD_LOGIC_VECTOR(13 DOWNTO 0);
      dinb : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
      doutb : OUT STD_LOGIC_VECTOR(63 DOWNTO 0)
      );
  end component;
  
  component iomapper is
    port (Clk : in std_logic;
          address : in std_logic_vector(19 downto 0);
          r : in std_logic;
          w : in std_logic;
          data_i : in std_logic_vector(7 downto 0);
          data_o : out std_logic_vector(7 downto 0)
          );
  end component;
  
  signal fastio_addr : std_logic_vector(19 downto 0);
  signal fastio_read : std_logic;
  signal fastio_write : std_logic;
  signal fastio_wdata : std_logic_vector(7 downto 0);
  signal fastio_rdata : std_logic_vector(7 downto 0);

  signal fastram_we : std_logic_vector(7 downto 0);
  signal fastram_read: std_logic;
  signal fastram_write : std_logic;
  signal fastram_address : std_logic_vector(13 downto 0);
  signal fastram_dataout : std_logic_vector(63 downto 0);
  signal fastram_datain : std_logic_vector(63 downto 0);

  signal vga_fastramaddress : std_logic_vector(13 downto 0);
  signal vga_fastramdata : std_logic_vector(63 downto 0);

begin
  fastram1 : component ram64x16k
    PORT MAP (
      clka => clock,
      wea => fastram_we,
      addra => fastram_address,
      dina => fastram_datain,
      douta => fastram_dataout,
      clkb => '0',
      web => (others => '0'),
      addrb => vga_fastramaddress,
      dinb => (others => '0'),
      doutb => vga_fastramdata
      );

  vga0: vga
    port map (
      pixelclock      => clock,
      cpuclock        => cpuclock,
      
      vsync           => vsync,
      hsync           => hsync,
      vgared          => vgared,
      vgagreen        => vgagreen,
      vgablue         => vgablue,
      
      ramaddress      => vga_fastramaddress,
      ramdata         => vga_fastramdata,

      fastio_addr     => fastio_addr,
      fastio_read     => fastio_read,
      fastio_write    => fastio_write,
      fastio_wdata    => fastio_wdata,
      fastio_rdata    => fastio_rdata,
      
      led0            => led0,
      led1            => led1,
      led2            => led2,
      led3            => led3,
      sw              => sw,
      btn             => btn);
  
  --cpu0: cpu6502 port map(clock => cpuclock,reset =>reset,irq => irq,
  --                       nmi => nmi,monitor_pc => monitor_pc,
  --                       monitor_opcode => monitor_opcode,
  --                       monitor_a => monitor_a,
  --                       monitor_x => monitor_x,
  --                       monitor_y => monitor_y,
  --                       monitor_sp => monitor_sp,
  --                       monitor_p => monitor_p,
  --                       fastio_addr => fastio_addr,
  --                       fastio_read => fastio_read,
  --                       fastio_write => fastio_write,
  --                       fastio_wdata => fastio_wdata,
  --                       fastio_rdata => fastio_rdata,
  --                       fastram_we => fastram_we,
  --                       fastram_address => fastram_address,
  --                       fastram_dataout => fastram_dataout,
  --                       fastram_datain => fastram_datain);

  cpu0: simple6502 port map(
    clock => cpuclock,reset =>'1',irq => irq,
    nmi => nmi,

    fastram_we => fastram_we,
    fastram_read => fastram_read,
    fastram_write => fastram_write,
    fastram_address => fastram_address,
    fastram_datain => fastram_datain,
    fastram_dataout => fastram_dataout,
    
    fastio_addr => fastio_addr,
    fastio_read => fastio_read,
    fastio_write => fastio_write,
    fastio_wdata => fastio_wdata,
    fastio_rdata => fastio_rdata
    );
  
  iomapper0: iomapper port map (
    clk => clock, address => fastio_addr, r => fastio_read, w => fastio_write,
    data_i => fastio_wdata, data_o => fastio_rdata);

  process
    function to_string(sv: Std_Logic_Vector) return string is
      use Std.TextIO.all;
      variable bv: bit_vector(sv'range) := to_bitvector(sv);
      variable lp: line;
    begin
      write(lp, bv);
      return lp.all;
    end;
  begin  -- process tb
    for i in 1 to 10 loop
      clock <= '1';
      report "clock=1 (reset)" severity note;
      wait for 5 ns;
      clock <= '0';
      -- report "clock=0 (reset)" severity note;
      wait for 5 ns;      
    end loop;  -- i
    reset <= '1';
    report "reset released" severity note;
    for i in 1 to 200 loop
      clock <= '1';
      cpuclock <= not cpuclock;
      wait for 5 ns;     
      -- report "clock=1" severity note;
      clock <= '0';
      -- report "clock=0 (run)" severity note;
      wait for 5 ns;
    end loop;  -- i
    assert false report "End of simulation" severity failure;
  end process;
end behavior;

