library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity uart_rx_buffered is
  generic ( name : in string := "?");
  Port ( clk : in  STD_LOGIC;
         bit_rate_divisor : in unsigned(23 downto 0);
           UART_RX : in STD_LOGIC;
           data : out  unsigned(7 downto 0);
           data_ready : out std_logic;
           data_acknowledge : in std_logic

           );
end uart_rx_buffered;

architecture behavioural of uart_rx_buffered is

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

-- Buffer for received characters 
type uart_buffer is array (0 to 63) of std_logic_vector(7 downto 0);
signal rxbuff : uart_buffer := (others => (others => '0'));
signal rxbuff_waddr : integer range 0 to 63 := 0;
signal rxbuff_raddr : integer range 0 to 63 := 63;

signal rxbuff_full : std_logic := '0';
signal rxbuff_empty : std_logic := '1';

signal ack_pending : std_logic := '0';

begin  -- behavioural

  process (CLK)
    -- avoid simultaneous read/write of rx buffer
    variable buffer_write : std_logic := '0';
  begin
    if rising_edge(CLK) then

      report "rxbuff_full = " & std_logic'image(rxbuff_full)
        & ", "
        & "rxbuff_empty = " & std_logic'image(rxbuff_empty)
        & ", "
        & "rxbuff_raddr = " & integer'image(rxbuff_raddr)
        & ", "
        & "rxbuff_waddr = " & integer'image(rxbuff_waddr)
        ;
        
      
      buffer_write := '0';
      
      if rxbuff_waddr = rxbuff_raddr then
        rxbuff_full <= '1';
      else
        rxbuff_full <= '0';
      end if;
      if rxbuff_raddr + 1 = rxbuff_waddr then
        rxbuff_empty <= '1';
      elsif rxbuff_raddr = 63 and rxbuff_waddr = 0 then
        rxbuff_empty <= '1';
      else
        rxbuff_empty <= '0';
      end if;

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
          if rxbuff_full = '0' then
            rxbuff(rxbuff_waddr) <= rx_data(8 downto 1);
            if rxbuff_waddr = 63 then
              rxbuff_waddr <= 0;
            else
              rxbuff_waddr <= rxbuff_waddr + 1;
            end if;
            buffer_write := '1';
          end if;
          
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

      if buffer_write = '0' and ack_pending = '0' and data_acknowledge = '0' and rxbuff_empty='0' then
        -- Pull next char from the RX buffer
        if rxbuff_raddr /= 63 then
          rxbuff_raddr <= rxbuff_raddr + 1;
          data <= unsigned(rxbuff(rxbuff_raddr + 1));
        else
          rxbuff_raddr <= 0;
          data <= unsigned(rxbuff(0));
        end if;
        ack_pending <= '1';
        data_ready <= '1';
      elsif ack_pending = '1' and data_acknowledge = '1' then
        -- Check for data_acknowledge before potentially reasserting data_ready
        -- so that we can't miss characters
        report "UART"&name&": received acknowledgement from reader" severity note;
        data_ready <= '0';
        ack_pending <= '0';
      end if;      
      
    end if;
  end process;
    

end behavioural;
