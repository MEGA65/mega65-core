library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_rxbuff is
end entity;

architecture foo of test_rxbuff is

  signal clock50mhz : std_logic := '1';
  signal send : std_logic := '0';
  signal txdata : unsigned(7 downto 0) := x"30";
  signal txready : std_logic := '0';
  signal uart_rx : std_logic := '1';
  signal data : unsigned(7 downto 0) := x"00";
  signal data_ready : std_logic := '0';
  signal data_acknowledge : std_logic := '0';

  signal counter : integer := 0;
begin

  tx: entity work.UART_TX_CTRL port map (
    send => send,
    bit_tmr_max => to_unsigned(10,24),
    clk => clock50mhz,
    data => txdata,
    ready => txready,
    uart_tx => uart_rx
    );
  
  rx: entity work.uart_rx_buffered port map (
    clk => clock50mhz,
    bit_rate_divisor => to_unsigned(10,24),
    uart_rx => uart_rx,
    data => data,
    data_ready => data_ready,
    data_acknowledge => data_acknowledge
    );
  
  process is
  begin
    clock50mhz <= '0';  
    wait for 10 ns;   
    clock50mhz <= '1';        
    wait for 10 ns;
      
    clock50mhz <= '0';
    wait for 10 ns;
    clock50mhz <= '1';
    wait for 10 ns;
      
  end process;

  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then
      counter <= counter + 1;
      if counter = 10 then
        txdata <= x"30";
        send <= '1';
      else
        send <= '0';
      end if;
      
      if data_ready = '1' then
        report "read character $" & to_hstring(data) & " from uart.";
        data_acknowledge <= '1';
      end if;
      if data_ready = '0' then
        data_acknowledge <= '0';
      end if;
    end if;
  end process;
  
end foo;
