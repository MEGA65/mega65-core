library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity uart_rx is
  generic ( name : in string := "?");
  Port ( clk : in  STD_LOGIC;
         bit_rate_divisor : in unsigned(23 downto 0);
           UART_RX : in STD_LOGIC;
           data : out  unsigned(7 downto 0);
           data_ready : out std_logic;
           data_acknowledge : in std_logic

           );
end uart_rx;

architecture behavioural of uart_rx is

-- Timer for the above
signal bit_timer : unsigned(23 downto 0) := (others => '0');

signal bit_position : natural range 0 to 15 := 0;

signal rx_data : std_logic_vector(9 downto 0);

type uart_rx_state is (Idle,WaitingForMidBit,WaitingForNextBit,WaitForRise);
signal rx_state : uart_rx_state := Idle;
signal uart_rx_debounced : std_logic_vector(3 downto 0) := (others =>'1');
signal uart_rx_bit : std_logic := '1';

signal data_ready_internal : std_logic := '0';

signal rx_gone_high : std_logic := '0';

type uart_buffer is array (0 to 63) of std_logic_vector(7 downto 0);

begin  -- behavioural

  process (CLK)
    -- purpose: based on last 8 samples of uart_rx, decide if the average signal is a 1 or a 0
  begin
    if rising_edge(CLK) then
    
      if false then
      if rx_state /= Idle then
        report "UART" & name &": rx_state = " & uart_rx_state'image(rx_state)
          & ", bit_timer=$" & to_hstring(bit_timer)
          & ", bit_position="
          & integer'image(bit_position)
          & ", bit_rate_divisor=$" & to_hstring(bit_rate_divisor);
      end if;
      end if;
      
      uart_rx_debounced <= uart_rx_debounced(2 downto 0) & uart_rx;
      if uart_rx_debounced = x"0" and uart_rx_bit = '1' then
        uart_rx_bit <= '0';
      end if;
      if uart_rx_debounced = x"F" and uart_rx_bit = '0' then
        uart_rx_bit <= '1';
      end if;

      if uart_rx_debounced = x"F" then
        rx_gone_high <= '1';
      end if;
      
      -- Update bit clock
      if to_integer(bit_timer)<to_integer(bit_rate_divisor) then
        bit_timer <= bit_timer + 1;
      else
        bit_timer <= (others => '0');
      end if;
      -- Look for start of first bit
      -- XXX Should debounce this!
      if rx_state = Idle and uart_rx_bit='0' and rx_gone_high = '1' then
        report "UART"&name&": start receiving byte (divider = $"
          & to_hstring(bit_rate_divisor) & ")" severity note;
        -- Start receiving next byte
--        report "UART"&name&": zeroing bit_timer";
        bit_timer <= (others => '0');
        bit_position <= 0;
        rx_state <= WaitingForMidBit;
      end if;
        
      -- Check for data_acknowledge before potentially reasserting data_ready
      -- so that we can't miss characters
      if data_acknowledge='1' and data_ready_internal='1' then
        report "UART"&name&": received acknowledgement from reader" severity note;
        data_ready <= '0';
        data_ready_internal <= '0';
      end if;

      -- Sample bit in the middle of the frame
      if rx_state = WaitingForMidBit
        and bit_timer = '0' & bit_rate_divisor(23 downto 1) then
--        report "UART"&name&": reached mid bit point, bit = " & integer'image(bit_position) severity note;
        -- Reached mid bit
        rx_data(bit_position) <= uart_rx_bit;
        if bit_position<9 then
          -- More bits to get
          bit_position <= bit_position + 1;
          rx_state <= WaitingForNextBit;
        else
          -- This was the last bit
          report "UART"&name&": Finished receiving byte. Value = $" & to_hstring(rx_data(8 downto 1)) severity note;
          data <= unsigned(rx_data(8 downto 1));
          data_ready <= '1';
          data_ready_internal <= '1';
          bit_timer <= to_unsigned(1,24);
          rx_state <= WaitForRise;
        end if;        
      end if;
      if bit_timer = 0 and rx_state = WaitingForNextBit then
        rx_state <= WaitingForMidBit;
      end if;
      -- Wait for most of a bit after receiving a byte before going back
      -- to idle state
      if (bit_timer = 0 or uart_rx_bit = '1') and rx_state = WaitForRise then
--        report "UART"&name&": Cancelling reception in WaitForRise";
        rx_state <= Idle;
        -- Don't keep receiving $00 if UART_RX stays low.
        rx_gone_high <= '0';
      end if;
    end if;
  end process;
    

end behavioural;
