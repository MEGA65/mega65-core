library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;

entity uart_monitor is
  port (
    dotclock : in std_logic;
    tx : out std_logic;
    rx : in  std_logic);
end uart_monitor;

architecture behavioural of uart_monitor is
component UART_TX_CTRL is
  Port ( SEND : in  STD_LOGIC;
         DATA : in  STD_LOGIC_VECTOR (7 downto 0);
         CLK : in  STD_LOGIC;
         READY : out  STD_LOGIC;
         UART_TX : out  STD_LOGIC);
end component;

-- raise for one cycle when we have a byte ready to send.
-- should only be asserted when tx_ready='1'.
signal tx_trigger : std_logic := '0';
-- the byte to send.
signal tx_data : std_logic_vector(7 downto 0);
-- indicates that uart is ready to TX the next byte.
signal tx_ready : std_logic;

-- Counter for slow clock derivation (for testing at least)
signal counter : unsigned(31 downto 0) := (others => '0');
signal tx_counter : std_logic;

begin

  uart_tx: uart_tx_ctrl
    port map (
      send    => tx_trigger,
      clk     => dotclock,
      data    => tx_data,
      ready   => tx_ready,
      uart_tx => tx);

  -- purpose: test uart output
  testclock: process (dotclock)
  begin  -- process testclock
    if rising_edge(dotclock) then
      counter <= counter + 1;
      tx_counter <= std_logic(counter(27));
      if std_logic(counter(27))='1' and tx_counter='0' then
        tx_data <= "0100" & std_logic_vector(counter(31 downto 28));
        tx_trigger<='1';    
      else
        tx_trigger<='0';
      end if;
    end if;
  end process testclock;
  
end behavioural;
