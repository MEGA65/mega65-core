--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2014
--
-- *  This program is free software; you can redistribute it and/or modify
-- *  it under the terms of the GNU Lesser General Public License as
-- *  published by the Free Software Foundation; either version 3 of the
-- *  License, or (at your option) any later version.
-- *
-- *  This program is distributed in the hope that it will be useful,
-- *  but WITHOUT ANY WARRANTY; without even the implied warranty of
-- *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- *  GNU General Public License for more details.
-- *
-- *  You should have received a copy of the GNU Lesser General Public License
-- *  along with this program; if not, write to the Free Software
-- *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
-- *  02111-1307  USA.

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

entity machine is
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

         -------------------------------------------------------------------------
         -- Lines for the SDcard interface itself
         -------------------------------------------------------------------------
         cs_bo : out std_logic;
         sclk_o : out std_logic;
         mosi_o : out std_logic;
         miso_i : in  std_logic;

         ---------------------------------------------------------------------------
         -- Lines for other devices that we handle here
         ---------------------------------------------------------------------------
         aclMISO : in std_logic;
         aclMOSI : out std_logic;
         aclSS : out std_logic;
         aclSCK : out std_logic;
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

         ----------------------------------------------------------------------
         -- Flash RAM for holding config
         ----------------------------------------------------------------------
         QspiSCK : out std_logic;
         QspiDB : inout std_logic_vector(3 downto 0);
         QspiCSn : out std_logic;

         ---------------------------------------------------------------------------
         -- Interface to Slow RAM (16MB cellular RAM chip)
         ---------------------------------------------------------------------------
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
         led4 : out std_logic;
         led5 : out std_logic;
         sw : in std_logic_vector(15 downto 0);
         btn : in std_logic_vector(4 downto 0);

         UART_TXD : out std_logic;
         RsRx : in std_logic;
         
         sseg_ca : out std_logic_vector(7 downto 0);
         sseg_an : out std_logic_vector(7 downto 0)
         );
end machine;

architecture Behavioral of machine is

  component uart_monitor
    port (
      reset : in std_logic;
      clock : in std_logic;
      tx : out std_logic;
      rx : in  std_logic;
      activity : out std_logic;

      fastio_read : in std_logic;
      fastio_write : in std_logic;

      monitor_watch : out std_logic_vector(27 downto 0);
      monitor_watch_match : in std_logic;
      
      monitor_cpu_state : in unsigned(7 downto 0);
      monitor_pc : in std_logic_vector(15 downto 0);
      monitor_opcode : in std_logic_vector(7 downto 0);
      monitor_ibytes : in std_logic_vector(3 downto 0);
      monitor_arg1 : in std_logic_vector(7 downto 0);
      monitor_arg2 : in std_logic_vector(7 downto 0);
      monitor_a : in std_logic_vector(7 downto 0);
      monitor_b : in std_logic_vector(7 downto 0);
      monitor_x : in std_logic_vector(7 downto 0);
      monitor_y : in std_logic_vector(7 downto 0);
      monitor_z : in std_logic_vector(7 downto 0);
      monitor_sp : in std_logic_vector(15 downto 0);
      monitor_p : in std_logic_vector(7 downto 0);
      monitor_map_offset_low : in std_logic_vector(11 downto 0);
      monitor_map_offset_high : in std_logic_vector(11 downto 0);
      monitor_map_enables_low : in std_logic_vector(3 downto 0);
      monitor_map_enables_high : in std_logic_vector(3 downto 0);   
      monitor_interrupt_inhibit : in std_logic;


      monitor_mem_address : out std_logic_vector(27 downto 0);
      monitor_mem_rdata : in unsigned(7 downto 0);
      monitor_mem_wdata : out unsigned(7 downto 0);
      monitor_mem_read : out std_logic := '0';
      monitor_mem_write : out std_logic := '0';
      monitor_mem_setpc : out std_logic := '0';
      monitor_mem_trace_mode : out std_logic;
      monitor_mem_stage_trace_mode : out std_logic;
      monitor_mem_trace_toggle : out std_logic;
      monitor_mem_attention_request : out std_logic;
      monitor_mem_attention_granted : in std_logic
      );
  end component;

  component gs4510
    port (
      Clock : in std_logic;
      ioclock : in std_logic;
      io_wait_states : in unsigned(7 downto 0);
      reset : in std_logic;
      irq : in std_logic;
      nmi : in std_logic;
      monitor_pc : out std_logic_vector(15 downto 0);
      monitor_state : out unsigned(7 downto 0);
      monitor_watch : in std_logic_vector(27 downto 0);
      monitor_watch_match : out std_logic;
      monitor_opcode : out std_logic_vector(7 downto 0);
      monitor_ibytes : out std_logic_vector(3 downto 0);
      monitor_arg1 : out std_logic_vector(7 downto 0);
      monitor_arg2 : out std_logic_vector(7 downto 0);
      monitor_a : out std_logic_vector(7 downto 0);
      monitor_b : out std_logic_vector(7 downto 0);
      monitor_x : out std_logic_vector(7 downto 0);
      monitor_y : out std_logic_vector(7 downto 0);
      monitor_z : out std_logic_vector(7 downto 0);
      monitor_sp : out std_logic_vector(15 downto 0);
      monitor_p : out std_logic_vector(7 downto 0);
      monitor_map_offset_low : out std_logic_vector(11 downto 0);
      monitor_map_offset_high : out std_logic_vector(11 downto 0);
      monitor_map_enables_low : out std_logic_vector(3 downto 0);
      monitor_map_enables_high : out std_logic_vector(3 downto 0);
      monitor_interrupt_inhibit : out std_logic;

      ---------------------------------------------------------------------------
      -- Memory access interface used by monitor
      ---------------------------------------------------------------------------
      monitor_mem_address : in std_logic_vector(27 downto 0);
      monitor_mem_rdata : out unsigned(7 downto 0);
      monitor_mem_wdata : in unsigned(7 downto 0);
      monitor_mem_read : in std_logic;
      monitor_mem_write : in std_logic;
      monitor_mem_setpc : in std_logic;
      monitor_mem_attention_request : in std_logic;
      monitor_mem_attention_granted : out std_logic;
      monitor_mem_trace_mode : in std_logic;
      monitor_mem_stage_trace_mode : in std_logic;
      monitor_mem_trace_toggle : in std_logic;

      ---------------------------------------------------------------------------
      -- Interface to Slow RAM (16MB cellular RAM chip)
      ---------------------------------------------------------------------------
      slowram_addr : out std_logic_vector(22 downto 0);
      slowram_we : out std_logic;
      slowram_ce : out std_logic;
      slowram_oe : out std_logic;
      slowram_lb : out std_logic;
      slowram_ub : out std_logic;
      slowram_data : inout std_logic_vector(15 downto 0);

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
      fastramwaitstate : in std_logic;
      fastio_addr : inout std_logic_vector(19 downto 0);
      fastio_read : inout std_logic;
      fastio_write : inout std_logic;
      fastio_wdata : out std_logic_vector(7 downto 0);
      fastio_rdata : in std_logic_vector(7 downto 0);
      fastio_sd_rdata : in std_logic_vector(7 downto 0);
      sector_buffer_mapped : in std_logic;
      fastio_vic_rdata : in std_logic_vector(7 downto 0);
      fastio_colour_ram_rdata : in std_logic_vector(7 downto 0);
      colour_ram_cs : out std_logic;

      viciii_iomode : in std_logic_vector(1 downto 0);

      colourram_at_dc00 : in std_logic;
      rom_at_e000 : in std_logic;
      rom_at_c000 : in std_logic;
      rom_at_a000 : in std_logic;
      rom_at_8000 : in std_logic

      );
  end component;
  
  component viciv is
    Port (
      pixelclock : in  STD_LOGIC;
      cpuclock : in std_logic;
      irq : out std_logic;
      reset : in std_logic;

      led : in std_logic;
      motor : in std_logic;
      
      ----------------------------------------------------------------------
      -- VGA output
      ----------------------------------------------------------------------
      vsync : out  STD_LOGIC;
      hsync : out  STD_LOGIC;
      vgared : out  UNSIGNED (3 downto 0);
      vgagreen : out  UNSIGNED (3 downto 0);
      vgablue : out  UNSIGNED (3 downto 0);

      ---------------------------------------------------------------------------
      -- CPU Interface to FastRAM in video controller (just 128KB for now)
      ---------------------------------------------------------------------------
      fastram_we : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
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
      colour_ram_fastio_rdata : out std_logic_vector(7 downto 0);
      colour_ram_cs : in std_logic;

      viciii_iomode : out std_logic_vector(1 downto 0);

      colourram_at_dc00 : out std_logic;
      rom_at_e000 : out std_logic;
      rom_at_c000 : out std_logic;
      rom_at_a000 : out std_logic;
      rom_at_8000 : out std_logic
      );
  end component;
  
  component iomapper is
    port (Clk : in std_logic;
          pixelclk : in std_logic;
          phi0 : in std_logic;
          reset : in std_logic;
          reset_out : out std_logic;
          irq : out std_logic;
          nmi : out std_logic;
          restore_nmi : out std_logic;
          address : in std_logic_vector(19 downto 0);
          r : in std_logic;
          w : in std_logic;
          data_i : in std_logic_vector(7 downto 0);
          data_o : out std_logic_vector(7 downto 0);
          sd_data_o : out std_logic_vector(7 downto 0);
          sector_buffer_mapped : out std_logic;
          colourram_at_dc00 : in std_logic;
          viciii_iomode : in std_logic_vector(1 downto 0);

          led : out std_logic;
          motor : out std_logic;

          sw : in std_logic_vector(15 downto 0);
          btn : in std_logic_vector(4 downto 0);
          seg_led : out unsigned(31 downto 0);

          ----------------------------------------------------------------------
          -- Flash RAM for holding config
          ----------------------------------------------------------------------
          QspiSCK : out std_logic;
          QspiDB : inout std_logic_vector(3 downto 0);
          QspiCSn : out std_logic;
          
          -------------------------------------------------------------------------
          -- Lines for the SDcard interface itself
          -------------------------------------------------------------------------
          cs_bo : out std_logic;
          sclk_o : out std_logic;
          mosi_o : out std_logic;
          miso_i : in  std_logic;

          ---------------------------------------------------------------------------
          -- Lines for other devices that we handle here
          ---------------------------------------------------------------------------
          aclMISO : in std_logic;
          aclMOSI : out std_logic;
          aclSS : out std_logic;
          aclSCK : out std_logic;
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
          
          ps2data : in std_logic;
          ps2clock : in std_logic
          );
  end component;

  signal viciii_iomode : std_logic_vector(1 downto 0);

  signal led : std_logic;
  signal motor : std_logic;
  
  signal seg_led_data : unsigned(31 downto 0);

  signal reset_out : std_logic;
  -- Holds reset on for 8 cycles so that reset line entry is used on start up,
  -- instead of implicit startup state.
  signal power_on_reset : std_logic_vector(7 downto 0) := (others => '0');
  signal reset_combined : std_logic;
  
  signal io_irq : std_logic;
  signal io_nmi : std_logic;
  signal vic_irq : std_logic;
  signal combinedirq : std_logic;
  signal combinednmi : std_logic;
  signal restore_nmi : std_logic;

  signal fastio_addr : std_logic_vector(19 downto 0);
  signal fastio_read : std_logic;
  signal fastio_write : std_logic;
  signal fastio_wdata : std_logic_vector(7 downto 0);
  signal fastio_rdata : std_logic_vector(7 downto 0);
  signal fastio_sd_rdata : std_logic_vector(7 downto 0);
  signal fastio_vic_rdata : std_logic_vector(7 downto 0);
  signal colour_ram_fastio_rdata : std_logic_vector(7 downto 0);
  signal sector_buffer_mapped : std_logic;

  signal fastram_we : STD_LOGIC_VECTOR(7 DOWNTO 0);
  signal fastram_address : STD_LOGIC_VECTOR(13 DOWNTO 0);
  signal fastram_datain : STD_LOGIC_VECTOR(63 DOWNTO 0);
  signal fastram_dataout : STD_LOGIC_VECTOR(63 DOWNTO 0);
  
  signal cpuclock : std_logic := '1';
  signal ioclock : std_logic := '1';
  signal io_wait_states : unsigned(7 downto 0);
  signal clock_phase : integer range 0 to 5 := 0;

  signal rom_at_e000 : std_logic := '0';
  signal rom_at_c000 : std_logic := '0';
  signal rom_at_a000 : std_logic := '0';
  signal rom_at_8000 : std_logic := '0';

  signal colourram_at_dc00 : std_logic := '0';
  signal colour_ram_cs : std_logic := '0';

  signal monitor_pc : std_logic_vector(15 downto 0);
  signal monitor_state : unsigned(7 downto 0);
  signal monitor_watch : std_logic_vector(27 downto 0);
  signal monitor_watch_match : std_logic;
  signal monitor_mem_address : std_logic_vector(27 downto 0);
  signal monitor_mem_rdata : unsigned(7 downto 0);
  signal monitor_mem_wdata : unsigned(7 downto 0);
  signal monitor_map_offset_low : std_logic_vector(11 downto 0);
  signal monitor_map_offset_high : std_logic_vector(11 downto 0);
  signal monitor_map_enables_low : std_logic_vector(3 downto 0);
  signal monitor_map_enables_high : std_logic_vector(3 downto 0);   
  signal monitor_mem_read : std_logic;
  signal monitor_mem_write : std_logic;
  signal monitor_mem_setpc : std_logic;
  signal monitor_mem_attention_request : std_logic;
  signal monitor_mem_attention_granted : std_logic;
  signal monitor_mem_stage_trace_mode : std_logic;
  signal monitor_mem_trace_mode : std_logic;
  signal monitor_mem_trace_toggle : std_logic;
  
  signal monitor_a : std_logic_vector(7 downto 0);
  signal monitor_b : std_logic_vector(7 downto 0);
  signal monitor_interrupt_inhibit : std_logic;
  signal monitor_x : std_logic_vector(7 downto 0);
  signal monitor_y : std_logic_vector(7 downto 0);
  signal monitor_z : std_logic_vector(7 downto 0);
  signal monitor_sp : std_logic_vector(15 downto 0);
  signal monitor_p : std_logic_vector(7 downto 0);
  signal monitor_opcode : std_logic_vector(7 downto 0);
  signal monitor_ibytes : std_logic_vector(3 downto 0);
  signal monitor_arg1 : std_logic_vector(7 downto 0);
  signal monitor_arg2 : std_logic_vector(7 downto 0);
  
  signal segled_counter : unsigned(19 downto 0) := (others => '0');

  -- Clock running as close as possible to 17.734475 MHz / 18 = 985248Hz
  -- Our pixel clock is 192MHz.  195 ticks gives 984615Hz for NTSC.
  -- 188 ticks at 96MHz gives 1021276Hz, which is pretty close for PAL.
  -- Then divide by 2 again, since the loop toggles phi0.
  signal phi0 : std_logic := '0';
  constant phi0_divisor : integer := 94;
  signal phi0_counter : integer range 0 to phi0_divisor;

begin

  ----------------------------------------------------------------------------
  -- IRQ & NMI: If either the hardware buttons on the FPGA board or an IO
  -- device via the IOmapper pull an interrupt line down, then trigger an
  -- interrupt.
  -----------------------------------------------------------------------------
  process(irq,nmi,restore_nmi,io_irq,vic_irq,io_nmi,sw,reset_out,btnCpuReset,
          power_on_reset)
  begin
    -- XXX Allow switch 0 to mask IRQs
    combinedirq <= ((irq and io_irq and vic_irq) or sw(0));
    combinednmi <= (nmi and io_nmi and restore_nmi) or sw(14);
    if sw(15)='1' then
      reset_combined <= '1';
    else
      if btnCpuReset='0' then reset_combined <= '0';
      elsif reset_out='0' then reset_combined <= '0';
      elsif power_on_reset(0)='0' then reset_combined <= '0';
      else
        reset_combined <= '1';
      end if;
    end if;
    -- report "btnCpuReset = " & std_logic'image(btnCpuReset) & ", reset_out = " & std_logic'image(reset_out) & ", sw(15) = " & std_logic'image(sw(15)) severity note;
    -- report "reset_combined = " & std_logic'image(reset_combined) severity note;
  end process;
  
  process(pixelclock)
    variable digit : std_logic_vector(3 downto 0);
  begin
    if rising_edge(pixelclock) then

      -- Run CPU at 1/2 pixel clock = 96MHz
      -- Run IO and serial monitor at 1/3 cpu clock = 32MHz
      if clock_phase = 5 then
        clock_phase <= 0;

        -- Hold reset low for a while when we first turn on
        report "power_on_reset(0) = " & std_logic'image(power_on_reset(0)) severity note;
        power_on_reset(7) <= '1';
        power_on_reset(6 downto 0) <= power_on_reset(7 downto 1);

      else
        clock_phase <= clock_phase + 1;
      end if;

      -- Determine CPU and IO clock phases.
      -- Knowing both of these, we can also know the number of CPU cycles
      -- that must be waited when accessing IO if the access is commence on a
      -- given cycle.  We need to allow one complete clock cycle after the
      -- rising edge of IOclock.
      -- This might need a bit of adjustment, but the principle should be sound.
      case clock_phase is
        when 0 => cpuclock <= '1'; ioclock<='0'; io_wait_states <= x"08";
        when 1 => cpuclock <= '0'; ioclock<='0'; io_wait_states <= x"07";
        when 2 => cpuclock <= '0'; ioclock<='0'; io_wait_states <= x"06";
        when 3 => cpuclock <= '1'; ioclock<='1'; io_wait_states <= x"0b";
        when 4 => cpuclock <= '0'; ioclock<='1'; io_wait_states <= x"0a";
        when 5 => cpuclock <= '0'; ioclock<='1'; io_wait_states <= x"09";
      end case;
      
      -- Work out phi0 frequency for CIA timers
      if phi0_counter=phi0_divisor then
        phi0 <= not phi0;
        phi0_counter <= 0;
      else
        phi0_counter <= phi0_counter + 1;
      end if;
      
      led0 <= irq;
      led1 <= nmi;
      led2 <= combinedirq;
      led3 <= combinednmi;
      led4 <= io_irq;
      led5 <= io_nmi;
      
      segled_counter <= segled_counter + 1;

      sseg_an <= (others => '1');
      sseg_an(to_integer(segled_counter(19 downto 17))) <= '0';

      if segled_counter(19 downto 17)=0 then
        digit := std_logic_vector(seg_led_data(3 downto 0));
      elsif segled_counter(19 downto 17)=1 then
        digit := std_logic_vector(seg_led_data(7 downto 4));
      elsif segled_counter(19 downto 17)=2 then
        digit := std_logic_vector(seg_led_data(11 downto 8));
      elsif segled_counter(19 downto 17)=3 then
        digit := std_logic_vector(seg_led_data(15 downto 12));
      elsif segled_counter(19 downto 17)=4 then
        digit := std_logic_vector(seg_led_data(19 downto 16));
      elsif segled_counter(19 downto 17)=5 then
        digit := std_logic_vector(seg_led_data(23 downto 20));
      elsif segled_counter(19 downto 17)=6 then
        digit := std_logic_vector(seg_led_data(27 downto 24));
      elsif segled_counter(19 downto 17)=7 then
        digit := std_logic_vector(seg_led_data(31 downto 28));
        --if segled_counter(19 downto 17)=3 then
        --  digit := monitor_pc(15 downto 12);
        --elsif segled_counter(19 downto 17)=2 then
        --  digit := monitor_pc(11 downto 8);
        --elsif segled_counter(19 downto 17)=1 then
        --  digit := monitor_pc(7 downto 4);
        --elsif segled_counter(19 downto 17)=0 then
        --  digit := monitor_pc(3 downto 0);
        --elsif segled_counter(19 downto 17)=4 then
        --  digit := monitor_state(3 downto 0);
        ----elsif segled_counter(19 downto 17)=5 then
        ----  digit := monitor_state(7 downto 4);
        --elsif segled_counter(19 downto 17)=5 then
        --  digit := std_logic_vector(last_scan_code(3 downto 0));
        --elsif segled_counter(19 downto 17)=6 then
        --  digit := std_logic_vector(last_scan_code(7 downto 4));
        --elsif segled_counter(19 downto 17)=7 then
        --  digit := std_logic_vector(last_scan_code(11 downto 8));
        --else
        digit := "UUUU";
      end if;

      -- segments are:
      -- 7 - decimal point
      -- 6 - middle
      -- 5 - upper left
      -- 4 - lower left
      -- 3 - bottom
      -- 2 - lower right
      -- 1 - upper right
      -- 0 - top
      case digit is
        when x"0" => sseg_ca <= "11000000";
        when x"1" => sseg_ca <= "11111001";
        when x"2" => sseg_ca <= "10100100";
        when x"3" => sseg_ca <= "10110000";
        when x"4" => sseg_ca <= "10011001";
        when x"5" => sseg_ca <= "10010010";
        when x"6" => sseg_ca <= "10000010";
        when x"7" => sseg_ca <= "11111000";
        when x"8" => sseg_ca <= "10000000";
        when x"9" => sseg_ca <= "10010000";
        when x"A" => sseg_ca <= "10001000";
        when x"B" => sseg_ca <= "10000011";
        when x"C" => sseg_ca <= "11000110";
        when x"D" => sseg_ca <= "10100001";
        when x"E" => sseg_ca <= "10000110";
        when x"F" => sseg_ca <= "10001110";
        when others => sseg_ca <= "10100001";
      end case; 
      
    end if;
  end process;
  
  cpu0: gs4510 port map(
    clock => cpuclock,
    ioclock => ioclock,
    io_wait_states => io_wait_states,
    reset =>reset_combined,
    irq => combinedirq,
    nmi => combinednmi,
    monitor_pc => monitor_pc,
    monitor_watch => monitor_watch,
    monitor_watch_match => monitor_watch_match,
    monitor_opcode => monitor_opcode,
    monitor_ibytes => monitor_ibytes,
    monitor_arg1 => monitor_arg1,
    monitor_arg2 => monitor_arg2,
    monitor_a => monitor_a,
    monitor_b => monitor_b,
    monitor_x => monitor_x,
    monitor_y => monitor_y,
    monitor_z => monitor_z,
    monitor_sp => monitor_sp,
    monitor_p => monitor_p,
    monitor_state => monitor_state,
    monitor_map_offset_low => monitor_map_offset_low,
    monitor_map_offset_high => monitor_map_offset_high,
    monitor_map_enables_low => monitor_map_enables_low,
    monitor_map_enables_high => monitor_map_enables_high,

    monitor_mem_address => monitor_mem_address,
    monitor_mem_rdata => monitor_mem_rdata,
    monitor_mem_wdata => monitor_mem_wdata,
    monitor_mem_read => monitor_mem_read,
    monitor_mem_write => monitor_mem_write,
    monitor_mem_setpc => monitor_mem_setpc,
    monitor_mem_attention_request => monitor_mem_attention_request,
    monitor_mem_attention_granted => monitor_mem_attention_granted,
    monitor_mem_trace_mode => monitor_mem_trace_mode,
    monitor_mem_stage_trace_mode => monitor_mem_stage_trace_mode,
    monitor_mem_trace_toggle => monitor_mem_trace_toggle,

    slowram_addr => slowram_addr,
    slowram_we => slowram_we,
    slowram_ce => slowram_ce,
    slowram_oe => slowram_oe,
    slowram_lb => slowram_lb,
    slowram_ub => slowram_ub,
    slowram_data => slowram_data,

    fastramwaitstate => sw(14),
    fastram_we => fastram_we,
    fastram_address => fastram_address,
    fastram_datain => fastram_datain,
    fastram_dataout => fastram_dataout,
    
    fastio_addr => fastio_addr,
    fastio_read => fastio_read,
    fastio_write => fastio_write,
    fastio_wdata => fastio_wdata,
    fastio_rdata => fastio_rdata,
    fastio_sd_rdata => fastio_sd_rdata,
    sector_buffer_mapped => sector_buffer_mapped,
    fastio_vic_rdata => fastio_vic_rdata,
    fastio_colour_ram_rdata => colour_ram_fastio_rdata,
    colour_ram_cs => colour_ram_cs,

    viciii_iomode => viciii_iomode,
  
    colourram_at_dc00 => colourram_at_dc00,
    rom_at_e000 => rom_at_e000,
    rom_at_c000 => rom_at_c000,
    rom_at_a000 => rom_at_a000,
    rom_at_8000 => rom_at_8000
    
    );

  viciv0: viciv
    port map (
      pixelclock      => pixelclock,
      cpuclock        => ioclock,

      irq             => vic_irq,
      reset           => reset_combined,

      led => led,
      motor => motor,
      
      vsync           => vsync,
      hsync           => hsync,
      vgared          => vgared,
      vgagreen        => vgagreen,
      vgablue         => vgablue,

      fastram_we => fastram_we,
      fastram_address => fastram_address,
      fastram_datain => fastram_datain,
      fastram_dataout => fastram_dataout,    
      colour_ram_fastio_rdata => colour_ram_fastio_rdata,
      colour_ram_cs => colour_ram_cs,

      fastio_addr     => fastio_addr,
      fastio_read     => fastio_read,
      fastio_write    => fastio_write,
      fastio_wdata    => fastio_wdata,
      fastio_rdata    => fastio_vic_rdata,

      viciii_iomode => viciii_iomode,

      colourram_at_dc00 => colourram_at_dc00,
      rom_at_e000 => rom_at_e000,
      rom_at_c000 => rom_at_c000,
      rom_at_a000 => rom_at_a000,
      rom_at_8000 => rom_at_8000      
      );
  
  iomapper0: iomapper port map (
    clk => ioclock,
    pixelclk => pixelclock,
    phi0 => phi0,
    reset => reset_combined,
    reset_out => reset_out,
    irq => io_irq, -- (but we might like to AND this with the hardware IRQ button)
    nmi => io_nmi, -- (but we might like to AND this with the hardware IRQ button)
    restore_nmi => restore_nmi,
    address => fastio_addr,
    r => fastio_read, w => fastio_write,
    data_i => fastio_wdata, data_o => fastio_rdata,
    sd_data_o => fastio_sd_rdata,
    colourram_at_dc00 => colourram_at_dc00,
    led => led,
    motor => motor,
    sw => sw,
    btn => btn,
    seg_led => seg_led_data,
    viciii_iomode => viciii_iomode,
    sector_buffer_mapped => sector_buffer_mapped,

    cs_bo => cs_bo,
    sclk_o => sclk_o,
    mosi_o => mosi_o,
    miso_i => miso_i,

    QspiSCK => QspiSCK,
    QspiDB => QspiDB,
    QspiCSn => QspiCSn,
    
    aclMISO => aclMISO,
    aclMOSI => aclMOSI,
    aclSS => aclSS,
    aclSCK => aclSCK,
    aclInt1 => aclInt1,
    aclInt2 => aclInt2,
    
    ampPWM => ampPWM,
    ampSD => ampSD,
    
    micData => micData,
    micClk => micClk,
    micLRSel => micLRSel,
    
    tmpSDA => tmpSDA,
    tmpSCL => tmpSCL,
    tmpInt => tmpInt,
    tmpCT => tmpCT,

    
    ps2data => ps2data,
    ps2clock => ps2clock
    );

  -----------------------------------------------------------------------------
  -- UART interface for monitor debugging and loading data
  -----------------------------------------------------------------------------
  monitor0 : uart_monitor port map (
    reset => reset_combined,
    clock => ioclock,
    tx       => UART_TXD,
    rx       => RsRx,

    fastio_read => fastio_read,
    fastio_write => fastio_write,
    
    monitor_pc => monitor_pc,
    monitor_cpu_state => monitor_state,
    monitor_watch => monitor_watch,
    monitor_watch_match => monitor_watch_match,
    monitor_opcode => monitor_opcode,
    monitor_ibytes => monitor_ibytes,
    monitor_arg1 => monitor_arg1,
    monitor_arg2 => monitor_arg2,
    monitor_a => monitor_a,
    monitor_b => monitor_b,
    monitor_x => monitor_x,
    monitor_y => monitor_y,
    monitor_z => monitor_z,
    monitor_sp => monitor_sp,
    monitor_p => monitor_p,
    monitor_interrupt_inhibit => monitor_interrupt_inhibit,
    monitor_map_offset_low => monitor_map_offset_low,
    monitor_map_offset_high => monitor_map_offset_high,
    monitor_map_enables_low => monitor_map_enables_low,
    monitor_map_enables_high => monitor_map_enables_high,
    
    monitor_mem_address => monitor_mem_address,
    monitor_mem_rdata => monitor_mem_rdata,
    monitor_mem_wdata => monitor_mem_wdata,
    monitor_mem_read => monitor_mem_read,
    monitor_mem_write => monitor_mem_write,
    monitor_mem_setpc => monitor_mem_setpc,
    monitor_mem_attention_request => monitor_mem_attention_request,
    monitor_mem_attention_granted => monitor_mem_attention_granted,
    monitor_mem_trace_mode => monitor_mem_trace_mode,
    monitor_mem_stage_trace_mode => monitor_mem_stage_trace_mode,
    monitor_mem_trace_toggle => monitor_mem_trace_toggle
  );
  
end Behavioral;

