library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.victypes.all;
use work.all;

entity monitor_ctrl is
  port (
    clk : in std_logic;
    reset : in std_logic;
    reset_out : out std_logic;
    write_sig : in std_logic;
    read_sig : in std_logic;
    address : in unsigned(4 downto 0);
    di : in unsigned(7 downto 0);
    do : out unsigned(7 downto 0);
    history_write_index : out unsigned(9 downto 0);
    history_write : out std_logic;
    history_read_index : out unsigned(9 downto 0);

    -- CPU Memory interface
    request_monitor_halt : in std_logic;
    mem_address : out unsigned(27 downto 0);
    mem_rdata : in unsigned(7 downto 0);
    mem_wdata : out unsigned(7 downto 0);
    mem_attention_request : out std_logic;
    mem_attention_granted : in std_logic;
    mem_read : out std_logic;
    mem_write : out std_logic;
    set_pc : out std_logic;

    -- CPU state recording control
    cpu_state_write : out std_logic;
    cpu_state : in unsigned(7 downto 0);
    cpu_state_write_index : out unsigned(3 downto 0);

    -- CPU trace interface
    monitor_mem_trace_mode : out std_logic;
    monitor_mem_trace_toggle : out std_logic;
    monitor_irq_inhibit : out std_logic;

    -- For controlling access to secure mode
    secure_mode_from_cpu : in std_logic;
    secure_mode_from_monitor : out std_logic;
    clear_matrix_mode_toggle : out std_logic;

    -- Watch interface
    monitor_watch : output unsigned(27 downto 0);
    monitor_watch_match : std_logic;
    monitor_p : in unsigned(7 downto 0);
    monitor_pc : in unsigned(15 downto 0);

    -- Monitor char input/output
    monitor_char_out : out unsigned(7 downto 0);
    monitor_char_valid : out std_logic;
    terminal_emulator_ready : in std_logic;
    terminal_emulator_ack : in std_logic;
    monitor_char_in : in unsigned(7 downto 0);
    monitor_char_toggle : in std_logic;
    monitor_char_busy : out std_logic;
/    
    uart_char : in unsigned(7 downto 0);
    uart_char_valid : in std_logic;

    bit_rate_divisor : out unsigned(15 downto 0);
    rx : in std_logic;
    tx : out std_logic;
    activity : out std_logic

    );
end monitor_ctrl;

architecture edwardian of monitor_ctrl is

  constant MON_READ_IDX_LO : unsigned(4 downto 0) := to_unsigned(0,5);
  constant MON_READ_IDX_HI : unsigned(4 downto 0) := to_unsigned(1,5);
  constant MON_WRITE_IDX_LO : unsigned(4 downto 0) := to_unsigned(2,5);
  constant MON_WRITE_IDX_HI : unsigned(4 downto 0) := to_unsigned(3,5);
  constant MON_TRACE_CTRL : unsigned(4 downto 0) := to_unsigned(4,5);
  constant MON_TRACE_STEP : unsigned(4 downto 0) := to_unsigned(5,5);
  constant MON_FLAG_MASK0 : unsigned(4 downto 0) := to_unsigned(6,5);
  constant MON_FLAG_MASK1 : unsigned(4 downto 0) := to_unsigned(7,5);
  constant MON_UART_RX : unsigned(4 downto 0) := to_unsigned(8,5);
  constant MON_UART_TX : unsigned(4 downto 0) := to_unsigned(8,5);
  constant MON_KEYBOARD_RX : unsigned(4 downto 0) := to_unsigned(9,5);
  constant MON_UART_STATUS : unsigned(4 downto 0) := to_unsigned(10,5);
  constant MON_RESET_TIMEOUT : unsigned(4 downto 0) := to_unsigned(11,5);
  constant MON_UART_BITRATE_LO : unsigned(4 downto 0) := to_unsigned(12,5);
  constant MON_UART_BITRATE_HI : unsigned(4 downto 0) := to_unsigned(13,5);
  constant MON_BREAK_ADDR0 : unsigned(4 downto 0) := to_unsigned(14,5);
  constant MON_BREAK_ADDR1 : unsigned(4 downto 0) := to_unsigned(15,5);
  constant MON_MEM_ADDR0 : unsigned(4 downto 0) := to_unsigned(16,5);
  constant MON_MEM_ADDR1 : unsigned(4 downto 0) := to_unsigned(17,5);
  constant MON_MEM_ADDR2 : unsigned(4 downto 0) := to_unsigned(18,5);
  constant MON_MEM_ADDR3 : unsigned(4 downto 0) := to_unsigned(19,5);
  constant MON_MEM_READ : unsigned(4 downto 0) := to_unsigned(20,5);
  constant MON_MEM_WRITE : unsigned(4 downto 0) := to_unsigned(21,5);
  constant MON_MEM_STATUS : unsigned(4 downto 0) := to_unsigned(22,5);
  constant MON_MEM_INC : unsigned(4 downto 0) := to_unsigned(23,5);
  constant MON_WATCH_ADDR0 : unsigned(4 downto 0) := to_unsigned(24,5);
  constant MON_WATCH_ADDR1 : unsigned(4 downto 0) := to_unsigned(25,5);
  constant MON_WATCH_ADDR2 : unsigned(4 downto 0) := to_unsigned(26,5);
  constant MON_WATCH_ADDR3 : unsigned(4 downto 0) := to_unsigned(27,5);
  constant MON_STATE_CNT : unsigned(4 downto 0) := to_unsigned(28,5);
  constant MON_PROT_HARDWARE : unsigned(4 downto 0) := to_unsigned(29,5);
  constant MON_CHAR_INOUT : unsigned(4 downto 0) := to_unsigned(30,5);
  constant MON_CHAR_STATUS : unsigned(4 downto 0) := to_unsigned(31,5);
  
  
  -- signals

begin
  if rising_edge(clk) then
  end if;
  
end edwardian;
