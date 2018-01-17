library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity uart_rx is
  Port ( clk : in  STD_LOGIC;
         bit_rate_divisor : in unsigned(13 downto 0);
           UART_RX : in STD_LOGIC;
           data : out  unsigned(7 downto 0);
           data_ready : out std_logic;
           data_acknowledge : in std_logic

           );
end uart_rx;

architecture behavioural of uart_rx is

-- Timer for the above
signal bit_timer : unsigned(7 downto 0) := (others => '0');

signal bit_position : natural range 0 to 15;

signal rx_data : std_logic_vector(9 downto 0);

type uart_rx_state is (Idle,WaitingForMidBit,WaitingForNextBit,WaitForRise);
signal rx_state : uart_rx_state := Idle;
signal uart_rx_debounced : std_logic_vector(3 downto 0) := (others =>'1');
signal uart_rx_bit : std_logic := '1';

type uart_buffer is array (0 to 63) of std_logic_vector(7 downto 0);

begin  -- behavioural

  process (CLK)
    -- purpose: based on last 8 samples of uart_rx, decide if the average signal is a 1 or a 0
  begin
    if rising_edge(CLK) then

      -- Accept input from keyboard if we are in matrix mode
      -- (but ignore 0xEF, the character which indicates matrix mode toggle)
      
      uart_rx_debounced <= uart_rx_debounced(2 downto 0) & uart_rx;
      if uart_rx_debounced = x"0" and uart_rx_bit = '1' then
        uart_rx_bit <= '0';
      end if;
      if uart_rx_debounced = x"F" and uart_rx_bit = '0' then
        uart_rx_bit <= '1';
      end if;
      
      -- Update bit clock
      if bit_timer<bit_rate_divisor then
        bit_timer <= bit_timer + 1;     
      else
        bit_timer <= (others => '0');
      end if;
      -- Look for start of first bit
      -- XXX Should debounce this!
      if rx_state = Idle and uart_rx_bit='0' then
        report "start receiving byte" severity note;
        -- Start receiving next byte
        bit_timer <= (others => '0');
        bit_position <= 0;
        rx_state <= WaitingForMidBit;
      end if;
        
      -- Check for data_acknowledge before potentially reasserting data_ready
      -- so that we can't miss characters
      if data_acknowledge='1' then
        report "received acknowledgement from reader" severity note;
        data_ready <= '0';
      end if;

      -- Sample bit in the middle of the frame
      if rx_state = WaitingForMidBit
        and bit_timer = '0' & bit_rate_divisor(13 downto 1) then
        report "reached mid bit point, bit = " & integer'image(bit_position) severity note;
        -- Reached mid bit
        rx_data(bit_position) <= uart_rx_bit;
        if bit_position<9 then
          -- More bits to get
          bit_position <= bit_position + 1;
          rx_state <= WaitingForNextBit;
        else
          -- This was the last bit
          report "Finished receiving byte. Value = $" & to_hstring(rx_data(8 downto 1)) severity note;
          data <= unsigned(rx_data(8 downto 1));
          data_ready <= '1';
          bit_timer <= "00000001";
          rx_state <= WaitForRise;
        end if;        
      end if;
      if bit_timer = 0 and rx_state = WaitingForNextBit then
        rx_state <= WaitingForMidBit;
      end if;
      -- Wait for most of a bit after receiving a byte before going back
      -- to idle state
      if (bit_timer = 0 or uart_rx_bit = '1') and rx_state = WaitForRise then
        rx_state <= Idle;
      end if;
    end if;
  end process;
    

end behavioural;
