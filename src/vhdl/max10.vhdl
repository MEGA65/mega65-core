library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.cputypes.all;
use work.types_pkg.all;

library UNISIM;
use UNISIM.VComponents.all;

entity max10 is
  Port ( pixelclock : in STD_LOGIC;
         cpuclock : in std_logic;
         
         ----------------------------------------------------------------------
         -- Debug LED
         ----------------------------------------------------------------------
         led : out std_logic := '0';
         
         ----------------------------------------------------------------------
         -- Comms link to MAX10 FPGA
         ----------------------------------------------------------------------
         max10_tx : out std_logic := '1';
         max10_rx : in std_logic;
         max10_clkandsync : inout std_logic;

         ----------------------------------------------------------------------
         -- Data to/from MAX10
         ----------------------------------------------------------------------
         max10_fpga_commit : out unsigned(31 downto 0) := to_unsigned(0,32);
         max10_fpga_date : out unsigned(15 downto 0) := to_unsigned(0,16);
         reset_button : out std_logic := '1';
         dipsw : out unsigned(3 downto 0) := (others => '0');
         j21in : out unsigned(11 downto 0) := (others => '0');
         j21ddr : in std_logic_vector(11 downto 0) := (others => '0');
         j21out : in std_logic_vector(11 downto 0) := (others => '0')
         );
end max10;

architecture Behavioral of max10 is

  signal max10_out_vector : std_logic_vector(63 downto 0) := (others => '0');
  signal max10_in_vector : std_logic_vector(63 downto 0) := (others => '0');
  signal max10_counter : integer range 0 to 79 := 0;
  signal max10_clock_toggle : std_logic := '0';

  signal max10_fpga_commit_drive : unsigned(31 downto 0) := to_unsigned(0,32);
  signal max10_fpga_date_drive : unsigned(15 downto 0) := to_unsigned(0,16);
  signal reset_button_drive : std_logic := '1';
  signal dipsw_drive : unsigned(3 downto 0) := (others => '0');
  signal j21in_drive : unsigned(11 downto 0) := (others => '0');
  
  
begin

  process (pixelclock,cpuclock) is
  begin
    if rising_edge(cpuclock) then
      max10_fpga_commit <= max10_fpga_commit_drive;
      max10_fpga_date <= max10_fpga_date_drive;
      dipsw <= dipsw_drive;
      j21in <= j21in_drive;
      reset_button <= reset_button_drive;
    end if;
    
    if rising_edge(pixelclock) then
      -- We were previously using a 4-wire protocol with RX and TX lines,
      -- a sync line and clock line. But the clock was supposed to be via
      -- FPGA_DONE pin under user-control, but that didn't work.
      -- As the MAX10 clock speed is highly variable, we will provide an integrated
      -- clock + sync where we hold the clock line low for long enough for the
      -- variably clocked MAX10 to detect this, but other wise runs free at CPU
      -- clock speed.
 
      max10_clock_toggle <= not max10_clock_toggle;

      -- Tick clock during 64 data cycles, then go tri-state during the sync period
      if max10_counter < 64 then
        reset_button_drive <= max10_clock_toggle;
        led <= max10_clock_toggle;
      else
        max10_clkandsync <= 'Z';
        led <= '1';
        max10_out_vector(11 downto 0) <= j21ddr;
        max10_out_vector(23 downto 12) <= j21out;
      end if;     

      
      if max10_clock_toggle = '0' then
        -- Tick clock on low phase
        if max10_counter < 79 then
          max10_counter <= max10_counter + 1;
        else
          max10_counter <= 0;
        end if;
        
        -- Drive simple serial protocol with MAX10 FPGA
        if max10_counter = 63 then
          max10_tx <= max10_out_vector(0);
          -- Latch read values, if vector is not stuck low
          if max10_in_vector /= x"00000000" then
            max10_fpga_commit_drive <= unsigned(max10_in_vector(47 downto 16));
            max10_fpga_date_drive <= unsigned(max10_in_vector(63 downto 48));
            j21in_drive <= unsigned(max10_in_vector(11 downto 0));
            dipsw_drive(3) <= not max10_in_vector(15);
            dipsw_drive(2) <= not max10_in_vector(14);
            dipsw_drive(1) <= not max10_in_vector(13);
            dipsw_drive(0) <= not max10_in_vector(12);
            reset_button_drive <= max10_in_vector(16);
          end if;
        else
          -- XXX Backward compatibility to older MAX10 firmware to keep
          -- reset button working.
          if max10_counter = 68 and max10_clkandsync = '0' then
            reset_button_drive <= '0';
          end if;
        end if;
      else
        -- Latch data on high phase of clock
        max10_in_vector(0) <= max10_rx;
        max10_in_vector(63 downto 1) <= max10_in_vector(62 downto 0);
        max10_out_vector(11 downto 0) <= j21ddr;
        max10_out_vector(23 downto 12) <= j21out;
      end if;            
    end if;
  end process;
  
  
end behavioral;
