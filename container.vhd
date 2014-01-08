----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    22:30:37 12/10/2013 
-- Design Name: 
-- Module Name:    container - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity container is
  Port ( CLK_IN : STD_LOGIC;
         reset : in  STD_LOGIC;
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
         btn : in std_logic_vector(4 downto 0)

         );
end container;

architecture Behavioral of container is
  component cpu6502
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
      fastram_clk : OUT STD_LOGIC;
      fastram_wea : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      fastram_address : OUT STD_LOGIC_VECTOR(13 DOWNTO 0);
      fastram_datain : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
      fastram_dataout : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
      
      ---------------------------------------------------------------------------
      -- fast IO port (clocked at core clock). 1MB address space
      ---------------------------------------------------------------------------
      fastio_clk : out std_logic;
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
      clk : in  STD_LOGIC;

      ----------------------------------------------------------------------
      -- VGA output
      ----------------------------------------------------------------------
      vsync : out  STD_LOGIC;
      hsync : out  STD_LOGIC;
      vgared : out  UNSIGNED (3 downto 0);
      vgagreen : out  UNSIGNED (3 downto 0);
      vgablue : out  UNSIGNED (3 downto 0);

      -----------------------------------------------------------------------------
      -- External interface to 128KB fastram insantiated inside us
      -----------------------------------------------------------------------------
      fastram_clk : IN STD_LOGIC;
      fastram_wea : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      fastram_address : IN STD_LOGIC_VECTOR(13 DOWNTO 0);
      fastram_datain : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
      fastram_dataout : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
      
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

  
  component iomapper is
    port (Clk : in std_logic;
          address : in std_logic_vector(19 downto 0);
          r : in std_logic;
          w : in std_logic;
          data_i : in std_logic_vector(7 downto 0);
          data_o : out std_logic_vector(7 downto 0)
          );
  end component;
  
  component fpga_clock is
    port
      (-- Clock in ports
        CLK_IN1           : in     std_logic;
        -- Clock out ports
        CLK_OUT1          : out    std_logic;  -- 100MHz
        CLK_OUT2          : out    std_logic;  -- 90MHz
        CLK_OUT3          : out    std_logic;  -- 85MHz
        CLK_OUT4          : out    std_logic;  -- 80MHz
        CLK_OUT5          : out    std_logic;  -- 70MHz
        CLK_OUT6          : out    std_logic;  -- 60MHz
        CLK_OUT7          : out    std_logic;  -- 50MHz
        -- Status and control signals
        RESET             : in     std_logic;
        LOCKED            : out    std_logic
        );
  end component;

  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';
  
  signal fastio_clock : std_logic;
  signal fastio_addr : std_logic_vector(19 downto 0);
  signal fastio_read : std_logic;
  signal fastio_write : std_logic;
  signal fastio_wdata : std_logic_vector(7 downto 0);
  signal fastio_rdata : std_logic_vector(7 downto 0);

  signal fastram_clk : STD_LOGIC;
  signal fastram_wea : STD_LOGIC_VECTOR(7 DOWNTO 0);
  signal fastram_address : STD_LOGIC_VECTOR(13 DOWNTO 0);
  signal fastram_datain : STD_LOGIC_VECTOR(63 DOWNTO 0);
  signal fastram_dataout : STD_LOGIC_VECTOR(63 DOWNTO 0);
      
begin
  fast_clock: fpga_clock port map(CLK_IN1 => CLK_IN,
                                  CLK_OUT7 => clock,reset => reset);
  
  cpu0: cpu6502 port map(clock => clock,reset =>reset,irq => irq,
                         nmi => nmi,monitor_pc => monitor_pc,
                         fastio_clock => fastio_clock,
                         fastio_addr => fastio_addr,
                         fastio_read => fastio_read,
                         fastio_write => fastio_write,
                         fastio_wdata => fastio_wdata,
                         fastio_rdata => fastio_rdata,

                         fastram_clk => fastram_clk,
                         fastram_wea => fastram_wea,
                         fastram_address => fastram_address,
                         fastram_datain => fastram_datain,
                         fastram_dataout => fastram_dataout                         
                         );

  vga0: vga
      port map (
        clk             => clk,
        vsync           => vsync,
        hsync           => hsync,
        vgared          => vgared,
        vgagreen        => vgagreen,
        vgablue         => vgablue,
        fastram_clk     => fastram_clk,
        fastram_wea     => fastram_wea,
        fastram_address => fastram_address,
        fastram_datain  => fastram_datain,
        fastram_dataout => fastram_dataout,
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
  
  iomapper0: iomapper port map (
    clk => fastio_clock, address => fastio_addr,
    r => fastio_read, w => fastio_write,
    data_i => fastio_wdata, data_o => fastio_rdata);

end Behavioral;

