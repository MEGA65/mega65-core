library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.victypes.all;


entity uart_monitor is
    port (
      reset : in std_logic;
      reset_out : out std_logic := '1';
      monitor_hyper_trap : out std_logic := '1';
      clock : in std_logic;
      tx : out std_logic := '1';
      rx : in  std_logic;
      bit_rate_divisor : out unsigned(15 downto 0) := to_unsigned(10,16); 
      activity : out std_logic := '0';

      protected_hardware_in : in unsigned(7 downto 0);
      uart_char : in unsigned(7 downto 0);
      uart_char_valid : in std_logic;
      secure_mode_from_cpu : in std_logic;
      secure_mode_from_monitor : out std_logic := '0';
      clear_matrix_mode_toggle : out std_logic := '0';

      monitor_char_out : out unsigned(7 downto 0);
      monitor_char_valid : out std_logic;
      terminal_emulator_ready : in std_logic;
      terminal_emulator_ack : in std_logic;
  
      key_scancode : out unsigned(15 downto 0) := x"0000";
      key_scancode_toggle : out std_logic := '0';

      force_single_step : in std_logic;
  
      fastio_read : in std_logic;
      fastio_write : in std_logic;
  
      monitor_proceed : in std_logic;
      monitor_waitstates : in unsigned(7 downto 0);
      monitor_request_reflected : in std_logic;
      monitor_pc : in unsigned(15 downto 0);
      monitor_cpu_state : in unsigned(15 downto 0);
      monitor_hypervisor_mode : in std_logic;
      monitor_instruction : in unsigned(7 downto 0);
      monitor_watch : out unsigned(27 downto 0) := x"7FFFFFF";
      monitor_watch_match : in std_logic;
      monitor_opcode : in unsigned(7 downto 0);
      monitor_ibytes : in unsigned(3 downto 0);
      monitor_arg1 : in unsigned(7 downto 0);
      monitor_arg2 : in unsigned(7 downto 0);
      monitor_memory_access_address : in unsigned(31 downto 0);
      monitor_roms : in unsigned(7 downto 0);
      
      monitor_a : in unsigned(7 downto 0);
      monitor_x : in unsigned(7 downto 0);
      monitor_y : in unsigned(7 downto 0);
      monitor_z : in unsigned(7 downto 0);
      monitor_b : in unsigned(7 downto 0);
      monitor_sp : in unsigned(15 downto 0);
      monitor_p : in unsigned(7 downto 0);
      monitor_map_offset_low : in unsigned(11 downto 0);
      monitor_map_offset_high : in unsigned(11 downto 0);
      monitor_map_enables_low : in unsigned(3 downto 0);
      monitor_map_enables_high : in unsigned(3 downto 0);
      monitor_interrupt_inhibit : in std_logic;

      monitor_char : in unsigned(7 downto 0);
      monitor_char_toggle : in std_logic;
      monitor_char_busy : out std_logic := '0';
      
      monitor_mem_address : out unsigned(27 downto 0) := x"0000000";
      monitor_mem_rdata : in unsigned(7 downto 0);
      monitor_mem_wdata : out unsigned(7 downto 0) := x"00";
      monitor_mem_attention_request : out std_logic := '0';
      monitor_mem_attention_granted : in std_logic;
      monitor_mem_read : out std_logic := '0';
      monitor_mem_write : out std_logic := '0';
      monitor_mem_setpc : out std_logic := '0';
      monitor_irq_inhibit : out std_logic := '0';
      monitor_mem_stage_trace_mode : out std_logic := '0';
      monitor_mem_trace_mode : out std_logic := '0';
      monitor_mem_trace_toggle : out std_logic := '0'
      );
end uart_monitor;

architecture dummy of uart_monitor is
begin
  process (clock) is
  begin
    if rising_edge(clock) then
      report "tick";
    end if;
  end process;
end dummy;
