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
use ieee.numeric_std.all;
use Std.TextIO.all;


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

  component dotclock is
    port
      (-- Clock in ports
        CLK_IN1           : in     std_logic;
        -- Clock out ports
        CLK_OUT1          : out    std_logic;
        CLK_OUT2          : out    std_logic;
        CLK_OUT3          : out    std_logic;
        CLK_OUT4          : out    std_logic;
        CLK_OUT5          : out    std_logic
        );
  end component;
  
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
      fastram_we : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
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
  
  component iomapper is
    port (Clk : in std_logic;
          address : in std_logic_vector(19 downto 0);
          r : in std_logic;
          w : in std_logic;
          data_i : in std_logic_vector(7 downto 0);
          data_o : out std_logic_vector(7 downto 0)
          );
  end component;
  
  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';
  
  signal fastio_addr : std_logic_vector(19 downto 0);
  signal fastio_read : std_logic;
  signal fastio_write : std_logic;
  signal fastio_wdata : std_logic_vector(7 downto 0);
  signal fastio_rdata : std_logic_vector(7 downto 0);

  signal fastram_we : STD_LOGIC_VECTOR(7 DOWNTO 0);
  signal fastram_address : STD_LOGIC_VECTOR(13 DOWNTO 0);
  signal fastram_datain : STD_LOGIC_VECTOR(63 DOWNTO 0);
  signal fastram_dataout : STD_LOGIC_VECTOR(63 DOWNTO 0);

  signal vga_fastramaddress : std_logic_vector(13 downto 0);
  signal vga_fastramdata : std_logic_vector(63 downto 0);
  
  signal cpuclock : std_logic;
  signal pixelclock : std_logic;
  signal monitor_pc : std_logic_vector(15 downto 0);
  
begin

  process(pixelclock)
  begin
     if rising_edge(pixelclock) then
        cpuclock <= not cpuclock;
     end if;
  end process;
  
  dotclock1: component dotclock
    port map ( clk_in1 => CLK_IN,
--               -- 100MHz clock for CPU
--               clk_out1 => cpuclock,
               -- CLK_OUT2 is good for 1920x1200@60Hz, CLK_OUT3___160
               -- for 1600x1200@60Hz
               -- 60Hz works fine, but 50Hz is not well supported by monitors. 
               -- so I guess we will go with an NTSC-style 60Hz display.       
               -- For C64 mode it would be nice to have PAL or NTSC selectable.                    -- Perhaps consider a different video mode for that, or buffering
               -- the generated frames somewhere?
               clk_out2 => pixelclock);   

    -- XXX For now just use 128KB FastRAM instead of 512KB which causes major routing
  -- headaches.
  fastram1 : component ram64x16k
    PORT MAP (
      clka => cpuclock,
      wea => fastram_we,
      addra => fastram_address,
      dina => fastram_datain,
      douta => fastram_dataout,
      -- video controller use port b of the dual-port fast ram.
      -- The CPU uses port a
      clkb => pixelclock,
      web => (others => '0'),
      addrb => vga_fastramaddress,
      dinb => (others => '0'),
      doutb => vga_fastramdata
      );

  
  cpu0: cpu6502 port map(clock => cpuclock,reset =>reset,irq => irq,
                         nmi => nmi,monitor_pc => monitor_pc,

                         fastio_addr => fastio_addr,
                         fastio_read => fastio_read,
                         fastio_write => fastio_write,
                         fastio_wdata => fastio_wdata,
                         fastio_rdata => fastio_rdata,

                         fastram_we => fastram_we,
                         fastram_address => fastram_address,
                         fastram_datain => fastram_datain,
                         fastram_dataout => fastram_dataout
                         fastram_dataout => (others => '0')
                         );


  
  vga0: vga
    port map (
      pixelclock      => pixelclock,
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
  
  iomapper0: iomapper port map (
    clk => cpuclock, address => fastio_addr,
    r => fastio_read, w => fastio_write,
    data_i => fastio_wdata, data_o => fastio_rdata);

end Behavioral;

