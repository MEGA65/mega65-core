library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use work.all;
use work.debugtools.all;

entity cpu_test is
  
end cpu_test;

architecture behavior of cpu_test is

  signal clock : std_logic := '0';
  signal cpuclock : std_logic := '0';
  signal reset : std_logic := '0';
  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';

  signal vsync : std_logic;
  signal hsync : std_logic;
  signal vgared : unsigned(3 downto 0);
  signal vgagreen : unsigned(3 downto 0);
  signal vgablue : unsigned(3 downto 0);

  signal slowram_data : std_logic_vector(15 downto 0);
  
  signal led0 : std_logic;
  signal led1 : std_logic;
  signal led2 : std_logic;
  signal led3 : std_logic;
  signal sw : std_logic_vector(15 downto 0) := (others => '0');
  signal btn : std_logic_vector(4 downto 0) := (others => '0');

  signal UART_TXD : std_logic;
  signal RsRx : std_logic;
  
  signal sseg_ca : std_logic_vector(7 downto 0);
  signal sseg_an : std_logic_vector(7 downto 0);
  
  component machine is
    Port ( pixelclock : STD_LOGIC;         
           btnCpuReset : in  STD_LOGIC;
           irq : in  STD_LOGIC;
           nmi : in  STD_LOGIC;

           ----------------------------------------------------------------------
           -- VGA output
           ----------------------------------------------------------------------
           vsync : out  STD_LOGIC;
           hsync : out  STD_LOGIC;
           vgared : out  UNSIGNED (3 downto 0);
           vgagreen : out  UNSIGNED (3 downto 0);
           vgablue : out  UNSIGNED (3 downto 0);

           --------------------------------------------------------------------
           -- Slow RAM interface: null for now
           --------------------------------------------------------------------
           slowram_addr : out std_logic_vector(22 downto 0);
           slowram_we : out std_logic;
           slowram_ce : out std_logic;
           slowram_oe : out std_logic;
           slowram_lb : out std_logic;
           slowram_ub : out std_logic;
           slowram_data : inout std_logic_vector(15 downto 0);
           
           ----------------------------------------------------------------------
           -- PS/2 adapted USB keyboard & joystick connector.
           -- For now we will use a keyrah adapter to connect to the keyboard.
           ----------------------------------------------------------------------
           ps2data : in std_logic;
           ps2clock : in std_logic;        
           
           ----------------------------------------------------------------------
           -- Debug interfaces on Nexys4 board
           ----------------------------------------------------------------------
           led0 : out std_logic;
           led1 : out std_logic;
           led2 : out std_logic;
           led3 : out std_logic;
           sw : in std_logic_vector(15 downto 0);
           btn : in std_logic_vector(4 downto 0);

           UART_TXD : out std_logic;
           RsRx : in std_logic;
           
           sseg_ca : out std_logic_vector(7 downto 0);
           sseg_an : out std_logic_vector(7 downto 0)
           );
  end component;

begin
  core0: machine
    port map (
      pixelclock      => clock,
      btnCpuReset      => reset,
      irq => '1',
      nmi => '1',

      ps2data => '1',
      ps2clock => '1',      

      slowram_data => slowram_data,
      
      vsync           => vsync,
      hsync           => hsync,
      vgared          => vgared,
      vgagreen        => vgagreen,
      vgablue         => vgablue,
      
      led0            => led0,
      led1            => led1,
      led2            => led2,
      led3            => led3,
      sw              => sw,
      btn             => btn,

      uart_txd        => uart_txd,
      rsrx            => rsrx,

      sseg_ca         => sseg_ca,
      sseg_an         => sseg_an);
  
  process
  begin  -- process tb
    report "beginning simulation" severity note;
    slowram_data <= (others => 'Z');

    for i in 1 to 10 loop
      clock <= '1';
      wait for 2.5 ns;
      clock <= '0';
      wait for 2.5 ns;      
    end loop;  -- i
    reset <= '1';
    report "reset released" severity note;
    for i in 1 to 2000000 loop
      clock <= '1';
      cpuclock <= not cpuclock;
      wait for 2.5 ns;     
      clock <= '0';
      wait for 2.5 ns;
    end loop;  -- i
    assert false report "End of simulation" severity failure;
  end process;
end behavior;

