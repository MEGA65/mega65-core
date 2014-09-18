library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use work.all;
use work.debugtools.all;

entity cpu_test is
  
end cpu_test;

architecture behavior of cpu_test is

  signal pixelclock : std_logic := '0';
  signal cpuclock : std_logic := '0';
  signal ioclock : std_logic := '0';
  signal clock50mhz : std_logic := '0';
  signal reset : std_logic := '0';
  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';

  signal vsync : std_logic;
  signal hsync : std_logic;
  signal vgared : unsigned(3 downto 0);
  signal vgagreen : unsigned(3 downto 0);
  signal vgablue : unsigned(3 downto 0);

  signal slowram_oe : std_logic;
  signal slowram_data : std_logic_vector(15 downto 0);
  signal slowram_addr : std_logic_vector(22 downto 0);
  signal slowram_addr_integer : integer range 0 to 65535;
  
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

  component slowram is
  port (address : in integer range 0 to 65535;
        -- output enable, active high       
        oe : in std_logic;
        data_o : out unsigned(15 downto 0)
        );
  end component;
  
  component machine is
    Port ( pixelclock : STD_LOGIC;
           cpuclock : STD_LOGIC;
           clock50mhz : in STD_LOGIC;
           ioclock : STD_LOGIC;
           uartclock : STD_LOGIC;
           btnCpuReset : in  STD_LOGIC;
           irq : in  STD_LOGIC;
           nmi : in  STD_LOGIC;

           no_kickstart : in std_logic;
           
           ----------------------------------------------------------------------
           -- VGA output
           ----------------------------------------------------------------------
           vsync : out  STD_LOGIC;
           hsync : out  STD_LOGIC;
           vgared : out  UNSIGNED (3 downto 0);
           vgagreen : out  UNSIGNED (3 downto 0);
           vgablue : out  UNSIGNED (3 downto 0);

           ---------------------------------------------------------------------------
           -- IO lines to the ethernet controller
           ---------------------------------------------------------------------------
           eth_mdio : inout std_logic;
           eth_mdc : out std_logic;
           eth_reset : out std_logic;
           eth_rxd : in unsigned(1 downto 0);
           eth_txd : out unsigned(1 downto 0);
           eth_txen : out std_logic;
           eth_rxdv : in std_logic;
           eth_rxer : in std_logic;
           eth_interrupt : in std_logic;         
           
           -------------------------------------------------------------------------
           -- Lines for the SDcard interface itself
           -------------------------------------------------------------------------
           cs_bo : out std_logic;
           sclk_o : out std_logic;
           mosi_o : out std_logic;
           miso_i : in  std_logic;

           aclMISO : in std_logic;
           aclMOSI : out std_logic;
           aclSS : out std_logic;
           aclInt1 : in std_logic;
           aclInt2 : in std_logic;
    
           ampPWM : out std_logic;
           ampSD : out std_logic;

           micData : in std_logic;
           micClk : out std_logic;
           micLRSel : out std_logic;

           tmpSDA : out std_logic;
           tmpSCL : out std_logic;
           tmpInt : in std_logic;
           tmpCT : in std_logic;

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

  -- Sample ethernet frame to test CRC calculation
  type ram_t is array (0 to 4095) of unsigned(7 downto 0);
   signal frame : ram_t := (
     -- A real ping packet captured on the wire
     x"FF", x"FF", x"FF", x"FF", x"FF", x"FF", x"C8", x"2A", x"14", x"08",
     x"DA", x"E2", x"08", x"00", x"45", x"00", x"00", x"54", x"53", x"17",
     x"00", x"00", x"FF", x"01", x"6A", x"73", x"A9", x"FE", x"AA", x"21",
     x"A9", x"FE", x"FF", x"FF", x"08", x"00", x"DD", x"A7", x"CF", x"6E",
     x"00", x"79", x"53", x"DB", x"32", x"3C", x"00", x"00", x"D9", x"55",
     x"08", x"09", x"0A", x"0B", x"0C", x"0D", x"0E", x"0F", x"10", x"11",
     x"12", x"13", x"14", x"15", x"16", x"17", x"18", x"19", x"1A", x"1B",
     x"1C", x"1D", x"1E", x"1F", x"20", x"21", x"22", x"23", x"24", x"25",
     x"26", x"27", x"28", x"29", x"2A", x"2B", x"2C", x"2D", x"2E", x"2F",
     x"30", x"31", x"32", x"33", x"34", x"35", x"36", x"37", x"46", x"44",
     x"25", x"A6",

     
     others => x"00");

  signal eth_rxdv : std_logic := '0';
  signal eth_rxd : unsigned(1 downto 0) := "00";
  signal eth_txen : std_logic;
  signal eth_txd : unsigned(1 downto 0);
  
begin
  slowram0: slowram
    port map(address => slowram_addr_integer,
             oe => slowram_oe,
             std_logic_vector(data_o) => slowram_data
             );

  core0: machine
    port map (
      pixelclock      => pixelclock,
      cpuclock      => cpuclock,
      clock50mhz   => clock50mhz,
      ioclock      => cpuclock,
      uartclock    => ioclock,
      btnCpuReset      => reset,
      irq => '1',
      nmi => '1',

      no_kickstart => '0',
      
      ps2data => '1',
      ps2clock => '1',

      miso_i => '1',

      aclMISO => '1',
      aclInt1 => '0',
      aclInt2 => '0',
      micData => '0',
      tmpInt => '0',
      tmpCT => '0',      

      eth_txd => eth_txd,
      eth_txen => eth_txen,
      eth_rxd => eth_rxd,
      eth_rxdv => eth_rxdv,
      eth_rxer => '0',
      eth_interrupt => '0',
      
      slowram_data => slowram_data,
      slowram_addr => slowram_addr,
      slowram_oe => slowram_oe,
      
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

  process(slowram_addr)
  begin
    slowram_addr_integer <= to_integer(unsigned(slowram_addr(15 downto 0)));
  end process;
  
  process
  begin  -- process tb
    report "beginning simulation" severity note;
    slowram_data <= (others => 'Z');

    for i in 1 to 2000000 loop
      pixelclock <= '0'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '0'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '0'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;     
      pixelclock <= '0'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;     
      reset <= '1';
    end loop;  -- i
    assert false report "End of simulation" severity failure;
  end process;

  -- Deliver dummy ethernet frames
  process
  begin
    for i in 1 to 20 loop
      eth_rxdv <= '0'; eth_rxd <= "00";
      -- Wait a few cycles before feeding frame
      for j in 1 to 50 loop
        clock50mhz <= '0';
        wait for 10 ns;
        clock50mhz <= '1';
        wait for 10 ns;
      end loop;

      -- Announce RX carrier
      eth_rxdv <= '1'; eth_rxd <= "00";
      wait for 10 ns;
      clock50mhz <= '1';
      wait for 10 ns;
      clock50mhz <= '0';
      wait for 10 ns;
      clock50mhz <= '1';
      wait for 10 ns;
      -- Send preamble
      report "CRC: Starting to send preamble";
      for j in 1 to 31 loop
        eth_rxd <= "01";
        clock50mhz <= '0';
        wait for 10 ns;
        clock50mhz <= '1';
        wait for 10 ns;
      end loop;
      -- Send end of preamble
      eth_rxd <= "11";
      clock50mhz <= '0';
      wait for 10 ns;
      clock50mhz <= '1';
      wait for 10 ns;
      -- Feed bytes
      report "CRC: Starting to send frame";
      for j in 0 to 101 loop
        report "ETHRXINJECT: Injecting $" & to_hstring(frame(j));
        eth_rxd <= frame(j)(1 downto 0);
        clock50mhz <= '0';
        wait for 10 ns;
        clock50mhz <= '1';
        wait for 10 ns;
        eth_rxd <= frame(j)(3 downto 2);
        clock50mhz <= '0';
        wait for 10 ns;
        clock50mhz <= '1';
        wait for 10 ns;
        eth_rxd <= frame(j)(5 downto 4);
        clock50mhz <= '0';
        wait for 10 ns;
        clock50mhz <= '1';
        wait for 10 ns;
        eth_rxd <= frame(j)(7 downto 6);
        clock50mhz <= '0';
        wait for 10 ns;
        clock50mhz <= '1';
        wait for 10 ns;        
      end loop;
      -- Disassert carrier
      eth_rxdv <= '0';
      clock50mhz <= '0';
      wait for 10 ns;
      clock50mhz <= '1';
      wait for 10 ns;

      -- Wait a few cycles before feeding next frame
      for j in 1 to 10000 loop
        clock50mhz <= '0';
        wait for 10 ns;
        clock50mhz <= '1';
        wait for 10 ns;
      end loop;
    end loop;
  end process;

  process
    variable txbyte : unsigned(7 downto 0) := x"00";
    variable txbits : integer range 0 to 7 := 0;
  begin
    for i in 1 to 200000000 loop
      if clock50mhz='1' then
        if eth_txen='1' then
          report "ETHTX: bits " & to_string(std_logic_vector(eth_txd));
          txbyte := eth_txd & txbyte(7 downto 2);
          if txbits = 6 then
            txbits := 0;
            report "ETHTX: byte $" & to_hstring(txbyte);
          else
            txbits := txbits + 2;
          end if;
        else
          report "ETHTX: bits NO CARRIER";
        end if;
      end if;
      wait for 10 ns;
      
    end loop;
  end process;
  
end behavior;

