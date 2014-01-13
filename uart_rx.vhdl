library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity uart_rx is
    Port ( clk : in  STD_LOGIC;
           UART_RX : in STD_LOGIC;
           data : out  STD_LOGIC_VECTOR (7 downto 0);
           data_ready : out std_logic;
           data_acknowledge : in std_logic
           );
end uart_rx;

architecture behavioural of uart_rx is

-- 64MHz/2/230400 -1 = 138 clock ticks per bit
constant bit_rate_divisor : unsigned(13 downto 0) := "00000010001010";
-- Timer for the above
signal bit_timer : unsigned(13 downto 0) := (others => '0');

signal bit_position : natural;

signal rx_data : std_logic_vector(9 downto 0);

type uart_rx_state is (Idle,WaitingForMidBit,WaitingForNextBit,WaitForRise);
signal rx_state : uart_rx_state := Idle;

begin  -- behavioural

  process (CLK)
  begin
    if rising_edge(CLK) then
      -- Update bit clock
      if bit_timer<bit_rate_divisor then
        bit_timer <= bit_timer + 1;
      else
        bit_timer <= (others => '0');
      end if;
      -- Look for start of first bit
      -- XXX Should debounce this!
      if rx_state = Idle and UART_RX = '0' then
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
        rx_data(bit_position) <= UART_RX;
        if bit_position<9 then
          -- More bits to get
          bit_position <= bit_position + 1;
          rx_state <= WaitingForNextBit;
        else
          -- This was the last bit
          report "Finished receiving byte. Value = $" & to_hstring(rx_data(8 downto 1)) severity note;
          data <= rx_data(8 downto 1);
          data_ready <= '1';
          bit_timer <= "00000000000001";
          rx_state <= WaitForRise;
        end if;        
      end if;
      if bit_timer = 0 and rx_state = WaitingForNextBit then
        rx_state <= WaitingForMidBit;
      end if;
      -- Wait for most of a bit after receiving a byte before going back
      -- to idle state
      if bit_timer = 0 and rx_state = WaitForRise then
        rx_state <= Idle;
      end if;
    end if;
  end process;
    

end behavioural;
