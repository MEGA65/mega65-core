library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use work.all;
use work.debugtools.all;

entity cpu_test is
  
end cpu_test;

architecture behavior of cpu_test is

  signal uart_bit_stream : std_logic_vector(0 to 29)
    := "111" & "0100000100" &
    "11111" & "0010000100" &
    "11";
  
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

  signal UART_TXD : std_logic;
  signal RsRx : std_logic;
  
  signal sseg_ca : std_logic_vector(7 downto 0);
  signal sseg_an : std_logic_vector(7 downto 0);
  
  component container is
    Port ( CLK_IN : STD_LOGIC;         
           btnCpuReset : in  STD_LOGIC;
--         irq : in  STD_LOGIC;
--         nmi : in  STD_LOGIC;

           ----------------------------------------------------------------------
           -- VGA output
           ----------------------------------------------------------------------
           vsync : out  STD_LOGIC;
           hsync : out  STD_LOGIC;
           vgared : out  UNSIGNED (3 downto 0);
           vgagreen : out  UNSIGNED (3 downto 0);
           vgablue : out  UNSIGNED (3 downto 0);

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
  core0: container
    port map (
      clk_in      => clock,
      btnCpuReset      => reset,
      
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
    for i in 1 to 10 loop
      clock <= '1';
      wait for 5 ns;
      clock <= '0';
      wait for 5 ns;      
    end loop;  -- i
    reset <= '1';
    report "reset released" severity note;
    for i in 1 to 200 loop
      clock <= '1';
      cpuclock <= not cpuclock;
      wait for 5 ns;     
      clock <= '0';
      wait for 5 ns;
    end loop;  -- i
    for j in 0 to uart_bit_stream'high loop
--      rsrx<=uart_bit_stream(j);
--      report "Writing bit to UART" severity note;
      for i in 1 to 832 loop
        clock <= '1';
        cpuclock <= not cpuclock;
        wait for 5 ns;     
        clock <= '0';
        wait for 5 ns;
      end loop;  -- i
    end loop;  -- j
    rsrx <= '1';
    for j in 0 to 1000000 loop
      for i in 1 to 832 loop
        clock <= '1';
        cpuclock <= not cpuclock;
        wait for 5 ns;     
        clock <= '0';
        wait for 5 ns;
      end loop;  -- i          
    end loop;  -- j
    assert false report "End of simulation" severity failure;
  end process;
end behavior;

