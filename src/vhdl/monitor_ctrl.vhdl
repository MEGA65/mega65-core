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
    secure_mode_from_monitor : out std_logic := '0';
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
  
  
  signal reset_timeout : unsigned(7 downto 0) := to_unsigned(255,8);
  signal reset_processing : std_logic := 0;

  signal cpu_state_was_hold : std_logic;
  signal cpu_state_write_index_reg : unsigned(5 downto 0);
  signal cpu_state_was_hold_next : std_logic;
  signal cpu_state_write_index_next : unsigned(5 downto 0);  

  signal bit_rate_divisor_reg : unsigned(15 downto 0);

  signal tx_send : std_logic;
  signal tx_ready : std_logic;
  signal tx_data : unsigned(7 downto 0);
  signal rx_data_ack : std_logic;
  signal rx_data_ready : std_logic;
  signal rx_data : unsigned(7 downto 0);
  signal uart_char_waiting : std_logic;

  signal history_write_continuous : std_logic;
  signal monitor_watch_en : std_logic;
  signal monitor_break_en : std_logic;
  signal monitor_flag_en : std_logic;
  signal mem_trace_reg : unsigned(7 downto 0);
  signal monitor_watch_match : std_logic;
  signal monitor_break_match : std_logic;
  signal monitor_break_addr : unsigned(15 downto 0);
  signal flag_break_mask : unsigned(15 downto 0);

begin

  uart_tx0: entity work.tx_ctrl port map (
    send => tx_send,
    bit_tmr_max => bit_rate_divisor_reg,
    data => tx_data,
    clk => clk,
    ready => tx_ready,
    uart_tx => tx
    );
  end entity;

  uart_rx0 : entity work.rx_ctrl(
    clk => clk,
    bit_rate_divisor => bit_rate_divisor_reg,
    uart_rx => rx,
    data => rx_data,
    data_ready => rx_data_ready,
    data_acknowledge => rx_data_ack
    );
  end entity;
    
  monitor_di <= di;
  reset_out <= '0' when reset_timeout/=0 else '1';
  
  cpu_state_write_index <= cpu_state_write_index_next;

  monitor_mem_trace_mode <= mem_trace_reg(0);
  monitor_flag_en <= mem_trace_reg(1);
  history_write <= mem_trace_reg(2);
  history_write_continuous <= mem_trace_reg(3);
  monitor_irq_inhibit <= mem_trace_reg(4);
  monitor_hyper_trap <= '1';
  monitor_watch_en <= mem_trace_reg(6);
  monitor_break_en <= mem_trace_reg(7);
  
  -- This is done as a separate combinatorial chunk because I need to be able to
  -- update the value of cpu_state_write and cpu_state_write_index (output) during
  -- the current clock cycle so the state write doesn't lag the CPU by a clock cycle.
  if reset='1' then
    cpu_state_write <= '0';
    cpu_state_was_hold_next <= '0';
    cpu_state_write_index_next <= '0';

  else
    cpu_state_write <= '0';
    cpu_state_write_index_next <= cpu_state_write_index_reg;
    if cpu_state != x"10" then
      cpu_state_was_hold_next <= '0';
      if cpu_state_was_hold='1' then
        cpu_state_write <= '1';
        cpu_state_write_index_next <= '0';
      else
        if cpu_state_write_index_reg < 16 then
          cpu_state_write <= '1';
          cpu_state_write_index_next <= cpu_state_write_index_reg+1;
        end if;
      end if;
    else
      cpu_state_was_hold_next <= '1';
    end if;
  end if;

  bit_rate_divisor <= bit_rate_divisor_reg;
  
  if rising_edge(clk) then
    if request_monitor_halt='1' then
      mem_trace_reg(0) <= '1'; -- force CPU into single-step mode
      mem_trace_reg(4) <= '1'; -- disable IRQs
    end if;

    if reset='1' and reset_processing='0' then
      reset_processing <= '1';
      reset_timeout <= to_unsigned(255,8);
    elsif address= MON_RESET_TIMEOUT and write_sig='1' then
      reset_timeout <= di;
    elsif reset_timeout /= 0 and reset_processing='1' then
      reset_timeout <= reset_timeout - 1;
    elsif reset='0' then
      -- Don't clear reset_processing flop until reset has been deasserted
      -- externally for at least one cycle
      reset_processing <= '0';
    end if;
    
    cpu_state_write_index_reg <= cpu_state_write_index_next;
    cpu_state_was_hold <= cpu_state_was_hold_next;

    if reset='1' then
      -- PGS 20181111 - 2Mbps has problems with intermittant lost characters
      -- with the shift to 40MHz cpu clock.  Oddly, 4Mbps works just fine.
      -- So we will use that.
      -- PGS 20181111 - Ah, the problem is that we need to reduce the count by one.
      -- With the reduced clock speed, the error in timing was increased to the point
      -- where it began causing problems.
      bit_rate_divisor_reg <= (40000000/2000000) - 1;
    elsif write_sig='1' then
      case address is
        when MON_UART_BITRATE_LO => bit_rate_divisor_reg(7 downto 0) <= di;
        when MON_UART_BITRATE_HI => bit_rate_divisor_reg(15 downto 8) <= di;
        when others => null;
      end case;
    end if;
  
    if reset = '1' then
      tx_data <= x"FF";
      tx_send <= '0';
    else
    // tx_send is automatically set to 1 for one clock cycle whenever 
    // UART TX data register is written to.
    if address == MON_UART_TX && write_sig = '1' then
      tx_data <= di;
      tx_send <= '1';
    else
      tx_send <= '0';
    end if;
            
    if uart_char_valid = '1' then
      uart_char_waiting <= '1';
    end if;
    if address = MON_UART_RX and read_sig = '1' then
      rx_data_ack <= '1';
      activity <= not activity;
    end if;

    if address = MON_KEYBOARD_RX and read_sig = '1' then
     uart_char_waiting <= '0';     
     activity <=  not activity;    -- Flip activity output on each KEYBOARD RX CPU read
    elsif rx_data_ready='0' then -- Don't reset rx_data_ack until rx_data_ready is dropped by the UART.
      rx_data_ack <= '0';
    end if;

    if reset='1' then
      history_read_index <= to_unsigned(0,10);
    elsif write_sig='1' then
      case address is
        when MON_READ_IDX_LO => history_read_index(7 downto 0) <= di;
        when MON_READ_IDX_HI => history_read_index(15 downto 8) <= di;
        when others => null;
      end case;
    end if;

    if reset='1' then
      history_write_index <= '0';
      mem_trace_reg  <= '0';
      monitor_watch_matched <= '0';
      monitor_break_matched <= '0';
    elsif write_sig = '1' then
      when address is
        case MON_WRITE_IDX_LO =>
          history_write_index(7 downto 0) <= di; mem_trace_reg(2) <= '0';
        case MON_WRITE_IDX_HI =>
          history_write_index(15 downto 8) <= di; mem_trace_reg(2) <= '0';
        case MON_UART_STATUS =>
          -- cancel matrix mode if we write to $900A
          clear_matrix_mode_toggle <= not clear_matrix_mode_toggle;
        case MON_STATE_CNT =>
          secure_mode_from_monitor <= di(7);
        case MON_TRACE_CTRL =>
          mem_trace_reg <= di;
          if di(6)='1' then
            monitor_watch_matched <= '0';
          end if;
          if di(7)='1' then
            monitor_break_matched <= '0';
          end if;
        case MON_TRACE_STEP =>
          monitor_mem_trace_toggle <= d(0);
        case MON_FLAG_MASK0 =>
          flag_break_mask(7 downto 0) <= di;
        case MON_FLAG_MASK1 =>
          flag_break_mask(15 downto 8) <= di;
      end case;
    elsif monitor_watch_match = '1' and monitor_watch_en = '1' then
      mem_trace_reg(0) <= '1'; -- Auto set trace mode on watch address match
      monitor_watch_matched <= '1';
    elsif monitor_break_addr = monitor_pc and monitor_break_en = '1' then
      mem_trace_reg(0) <= '1'; -- Auto set trace mode on break address match
      monitor_break_matched <= '1';
    elsif (((monitor_p and flag_break_mask(15 downto 0)) /= x"00")
           or (((not monitor_p) and flag_break_mask(15 downto 0)) /= x"00"))
          and monitor_flag_en = '1' then
      mem_trace_reg(0) <= '1'; -- Auto set trace mode on break address match
      monitor_break_matched <= '1';
    elsif history_write = '1' then
      -- record history continuously until full.   The last slot is reserved for capturing current state.
      if history_write_index < 1022 then
        history_write_index <= history_write_index + 1;
      elsif history_write_continuous='1' then
        history_write_index <= 0; // Wrap around to 0
      else
        mem_trace_reg(2) <= 0; -- Disable writes (and auto increment)
      end if;
    end if;
    
  end if;
  
end edwardian;
