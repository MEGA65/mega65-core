--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2018
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

--------------------------------------------------------------------------------

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity buffereduart is
  port (
    clock : in std_logic;
    reset : in std_logic;
    irq : out std_logic := 'Z';
    buffereduart_cs : in std_logic;

    ---------------------------------------------------------------------------
    -- IO lines to the UARTs
    ---------------------------------------------------------------------------
    uart_rx : in std_logic_vector(7 downto 0) := (others => '1');
    uart_tx : out std_logic_vector(7 downto 0) := (others => '1');
    uart_ringindicate : in std_logic_vector(7 downto 0);    
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : in unsigned(19 downto 0);
    fastio_write : in std_logic;
    fastio_read : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0)
    );
end buffereduart;

architecture behavioural of buffereduart is

  signal master_irq_enable : std_logic := '0';
  signal master_tx_irq_enable : std_logic := '0';
  signal master_rx_irq_enable : std_logic := '0';
  
  -- Single shared buffer for all serial ports of 4KB
  -- This means 512 bytes for each UART
  -- 256 bytes TX buffer and 256 bytes RX buffer
  signal buffer_write : std_logic := '0';
  signal buffer_writeaddress : integer range 0 to 4095 := 0;
  signal buffer_readaddress : integer range 0 to 4095 := 0;
  signal buffer_wdata : unsigned(7 downto 0) := x"00"; 
  signal buffer_rdata : unsigned(7 downto 0) := x"00"; 

  type baud_divisor_t is array(0 to 7) of unsigned(23 downto 0);
  type eightbytes_t is array(0 to 7) of unsigned(7 downto 0);
  type eightcounters_t is array(0 to 7) of integer range 0 to 7;

  signal tx_inhibit : eightcounters_t := (others => 0);
  signal rx_inhibit : eightcounters_t := (others => 0);
  signal uart_bit_rate_divisor : baud_divisor_t  := (others => to_unsigned(0,24));
  signal uart_bit_rate_divisor_internal : baud_divisor_t  := (others => to_unsigned(0,24));
  signal tx_data :  eightbytes_t := (others => x"00");
  signal last_tx_byte_written : eightbytes_t := (others => x"FF");
  signal tx_ready : std_logic_vector(7 downto 0);
  signal tx_trigger : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_data : eightbytes_t;
  signal rx_data_for_reading : eightbytes_t := (others => x"FF");
  signal rx_ready : std_logic_vector(7 downto 0);
  signal rx_acknowledge : std_logic_vector(7 downto 0) := (others => '0');

  signal read_scheduled : std_logic := '0';
  signal read_target : integer range 0 to 255 := 255;

  signal tx_byte_written : std_logic := '0';
  signal rx_byte_stale : std_logic := '0';

  signal selected_uart : integer range 0 to 15 := 0;
  signal last_selected_uart : integer range 0 to 15 := 0;
  signal cycled_uart_id : integer range 0 to 7 := 0;
  
  signal uart_rx_buffer_pointer_write : eightbytes_t := (others => to_unsigned(0,8));
  signal uart_rx_buffer_pointer_read : eightbytes_t := (others => to_unsigned(0,8));
  signal uart_tx_buffer_pointer_write : eightbytes_t := (others => to_unsigned(0,8));
  signal uart_tx_buffer_pointer_read : eightbytes_t := (others => to_unsigned(0,8));

  signal loopback_mode : std_logic := '0';
  signal uart_rx_mux : std_logic_vector(7 downto 0);

  signal uart_tx_drive : std_logic_vector(7 downto 0);  

  
  -- Set when ANY IRQ condition for this UART is triggered
  signal uart_irq_status : std_logic_vector(7 downto 0) := (others => '0');
  -- Set when UART RX buffer is empty etc
  signal uart_rx_empty : std_logic_vector(7 downto 0) := (others => '1');
  signal uart_rx_highwater : std_logic_vector(7 downto 0) := (others => '0');
  signal uart_rx_full : std_logic_vector(7 downto 0) := (others => '0');
  -- And similarly for TX buffers
  signal uart_tx_empty : std_logic_vector(7 downto 0) := (others => '1');
  signal uart_tx_lowwater : std_logic_vector(7 downto 0) := (others => '0');
  signal uart_tx_full : std_logic_vector(7 downto 0) := (others => '0');
  -- Flags to enable interrupts on various conditions
  signal uart_irq_on_rx_byte : std_logic_vector(7 downto 0) := (others => '0');
  signal uart_irq_on_rx_highwater : std_logic_vector(7 downto 0) := (others => '0');
  signal uart_irq_on_tx_lowwater : std_logic_vector(7 downto 0) := (others => '0'); 
  
begin  -- behavioural

  buffer0: entity work.ram8x4096
    port map (
    clkr => clock,
    clkw => clock,
    cs => '1',
    w => buffer_write,
    write_address => buffer_writeaddress,
    wdata => buffer_wdata,
    address => buffer_readaddress,
    rdata => buffer_rdata);

  uarts: 
  for i in 0 to 7 generate
    tx: entity work.UART_TX_CTRL
      port map (
        send    => tx_trigger(i),
        BIT_TMR_MAX => uart_bit_rate_divisor(i),
        clk     => clock,
        data    => tx_data(i),
        ready   => tx_ready(i),
        uart_tx => uart_tx_drive(i));

    rx: entity work.uart_rx 
      generic map (name => integer'image(i))
      Port map ( clk => clock,
                 bit_rate_divisor => uart_bit_rate_divisor(i),
                 UART_RX => uart_rx_mux(i),

                 data => rx_data(i),
                 data_ready => rx_ready(i),
                 data_acknowledge => rx_acknowledge(i));
    end generate uarts;

  
  process (clock,fastio_addr,fastio_wdata,fastio_read,fastio_write,
           loopback_mode,uart_tx_drive,uart_rx,buffereduart_cs,selected_uart,
           master_irq_enable,master_tx_irq_enable,master_rx_irq_enable,
           uart_irq_status,uart_rx_empty,uart_tx_empty,uart_rx_full,
           uart_tx_full,uart_irq_on_rx_byte,uart_irq_on_rx_highwater,
           uart_irq_on_tx_lowwater,uart_rx_buffer_pointer_write,
           uart_rx_buffer_pointer_read,uart_tx_buffer_pointer_write,
           uart_tx_buffer_pointer_read
           ) is
    variable temp_cmd : unsigned(7 downto 0);

  begin

    -- MUX to allow connecting serial ports to outside lines, or alternatively
    -- to the opposite buffered UART (as a remote loopback diagnostic mode)
    if loopback_mode='1' then
      for i in 0 to 7 loop
        uart_rx_mux(i) <= uart_tx_drive(7-i);
      end loop;
    else
      uart_rx_mux <= uart_rx;
    end if;
    
    irq <= '1';

    -- Register reading is asynchronous to avoid wait states
    if fastio_read='1' then
      if buffereduart_cs='1' then
        case fastio_addr(3 downto 0) is
          -- Use this notation to create entries for auto-populating iomap.txt
          -- @IO:GS $D0E0.0-3 Select active UART for other registers
          -- @IO:GS $D0E0.7 Buffered UART master IRQ enable
          -- @IO:GS $D0E0.6 Buffered UART master TX queue low-water IRQ enable
          -- @IO:GS $D0E0.5 Buffered UART master RX buffer high-water IRQ enable
          -- @IO:GS $D0E0.4 Enable loopback mode
          when x"0" =>
            fastio_rdata(3 downto 0) <= to_unsigned(selected_uart,4);
            fastio_rdata(7) <= master_irq_enable;
            fastio_rdata(6) <= master_tx_irq_enable;
            fastio_rdata(5) <= master_rx_irq_enable;
            fastio_rdata(4) <= loopback_mode;
          when x"1" =>
            -- @IO:GS $D0E1 Buffered UART Status register / interrupt select register
            -- @IO:GS $D0E1.7 Buffered UART interrupt status
            -- @IO:GS $D0E1.6 Buffered UART RX buffer empty
            -- @IO:GS $D0E1.5 Buffered UART TX buffer empty
            -- @IO:GS $D0E1.4 Buffered UART RX buffer full
            -- @IO:GS $D0E1.3 Buffered UART TX buffer full
            -- @IO:GS $D0E1.2 Buffered UART enable interrupt on RX byte
            -- @IO:GS $D0E1.1 Buffered UART enable interrupt on RX high-water mark
            -- @IO:GS $D0E1.0 Buffered UART enable interrupt on TX buffer low-water mark
            if selected_uart<8 then
              fastio_rdata(7) <= uart_irq_status(selected_uart);
              fastio_rdata(6) <= uart_rx_empty(selected_uart);
              fastio_rdata(5) <= uart_tx_empty(selected_uart);
              fastio_rdata(4) <= uart_rx_full(selected_uart);
              fastio_rdata(3) <= uart_tx_full(selected_uart);
              fastio_rdata(2) <= uart_irq_on_rx_byte(selected_uart);
              fastio_rdata(1) <= uart_irq_on_rx_highwater(selected_uart);
              fastio_rdata(0) <= uart_irq_on_tx_lowwater(selected_uart);
            else
              fastio_rdata <= x"FF";
            end if;
          when x"2" =>
            -- @IO:GS $D0E2 Buffered UART Read register (write to ACK receipt of byte)
            if selected_uart < 8 then
              fastio_rdata <= rx_data_for_reading(selected_uart);
            else
              fastio_rdata <= x"FF";
            end if;
          when x"3" =>
            -- @IO:GS $D0E3 Buffered UART Write register (write to send byte)
            if selected_uart < 8 then
              fastio_rdata <= last_tx_byte_written(selected_uart);
            else
              fastio_rdata <= x"FF";
            end if;
          when x"4" =>
            -- @IO:GS $D0E4 Buffered UART bit rate divisor LSB
            if selected_uart < 8 then
              fastio_rdata <= uart_bit_rate_divisor_internal(selected_uart)(7 downto 0);
            else
              fastio_rdata <= x"FF";
            end if;
          when x"5" =>
            -- @IO:GS $D0E5 Buffered UART bit rate divisor middle byte
            if selected_uart < 8 then
              fastio_rdata <= uart_bit_rate_divisor_internal(selected_uart)(15 downto 8);
            else
              fastio_rdata <= x"FF";
            end if;
          when x"6" =>
            -- @IO:GS $D0E6 Buffered UART bit rate divisor MSB
            if selected_uart < 8 then
              fastio_rdata <= uart_bit_rate_divisor_internal(selected_uart)(23 downto 16);
            else
              fastio_rdata <= x"FF";
            end if;
          when x"c" =>
            if selected_uart < 8 then
              fastio_rdata <= uart_rx_buffer_pointer_write(selected_uart);
            else
              fastio_rdata <= x"FF";
            end if;
          when x"d" =>
            if selected_uart < 8 then
              fastio_rdata <= uart_rx_buffer_pointer_read(selected_uart);
            else
              fastio_rdata <= x"FF";
            end if;
          when x"e" =>
            if selected_uart < 8 then
              fastio_rdata <= uart_tx_buffer_pointer_write(selected_uart);
            else
              fastio_rdata <= x"FF";
            end if;
          when x"f" =>
            if selected_uart < 8 then
              fastio_rdata <= uart_tx_buffer_pointer_read(selected_uart);
            else
              fastio_rdata <= x"FF";
            end if;
          when others =>
            fastio_rdata <= (others => 'Z');
        end case;
      else
        fastio_rdata <= (others => 'Z');
      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if;

    if rising_edge(clock) then

      read_scheduled <= '0';
      read_target <= 255;
      tx_byte_written <= '0';          
      buffer_write <= '0';
      rx_acknowledge <= (others => '0');
      tx_trigger <= (others => '0');
      
--      report "selected_uart=" & integer'image(selected_uart);
    
      -- Update status flags
      for i in 0 to 7 loop
        -- Decrement TX inhibit counters.
        -- These are used to handle the fact that tx_empty and tx_ready take a
        -- couple of cycles to update.
        if tx_inhibit(cycled_uart_id) /= 0 then
          tx_inhibit(cycled_uart_id) <= tx_inhibit(cycled_uart_id) - 1;
        end if;
        -- A similar situation applies to the RX path with acknowledging and
        -- waiting for rx_ready to clear
        if rx_inhibit(cycled_uart_id) /= 0 then
          rx_inhibit(cycled_uart_id) <= rx_inhibit(cycled_uart_id) - 1;
        end if;

        -- RX buffer empty?
        if false then -- i = 0 or i = 7 then
          report "uart_rx_buffer_pointers("& integer'image(i)&"): w=$" & to_hstring(uart_rx_buffer_pointer_write(i))
            &", r=$" & to_hstring(uart_rx_buffer_pointer_read(i)) & ", rx_empty=" & std_logic'image(uart_rx_empty(i))
            & ", rx_full=" & std_logic'image(uart_rx_full(i))
            & ", rx_highwater=" & std_logic'image(uart_rx_highwater(i));
          report "uart_tx_buffer_pointers("& integer'image(i)&"): w=$" & to_hstring(uart_tx_buffer_pointer_write(i))
            &", r=$" & to_hstring(uart_tx_buffer_pointer_read(i)) & ", tx_empty=" & std_logic'image(uart_tx_empty(i))
            & ", tx_full=" & std_logic'image(uart_tx_full(i))
            & ", tx_lowwater=" & std_logic'image(uart_tx_lowwater(i));
            
        end if;
        
        if uart_rx_buffer_pointer_write(i) = uart_rx_buffer_pointer_read(i) then
          uart_rx_empty(i) <= '1';
          if uart_rx_empty(i) = '0' then
            report "RXBUFFER: Marking UART#" & integer'image(i) & " empty.";
          end if;
        else
          uart_rx_empty(i) <= '0';
          if uart_rx_empty(i) = '1' then
            report "RXBUFFER: Marking UART#" & integer'image(i) & " not empty.";
          end if;
        end if;
        -- Or full?
        if (to_integer(uart_rx_buffer_pointer_write(i) + 1) = to_integer(uart_rx_buffer_pointer_read(i)))
          or (uart_rx_buffer_pointer_write(i) = x"FF" and uart_rx_buffer_pointer_read(i) = x"00")
        then
          uart_rx_full(i) <= '1';
        else
          uart_rx_full(i) <= '0';
        end if;
        -- Has the RX buffer reached the high-water mark?
        if uart_rx_buffer_pointer_write(i) >= uart_rx_buffer_pointer_read(i) then
          -- Write point comes after read point, so simple subtraction
          if (uart_rx_buffer_pointer_write(i) - uart_rx_buffer_pointer_read(i)) < 224 then
            uart_rx_highwater(i) <= '0';
          else
            uart_rx_highwater(i) <= '1';            
          end if;
        else
          if ((256 - uart_rx_buffer_pointer_read(i)) + uart_rx_buffer_pointer_write(i)) < 224 then
            -- Write point comes before read, so it must have wrapped
            uart_rx_highwater(i) <= '0';
          else
            uart_rx_highwater(i) <= '1';            
          end if;
        end if;

        -- Now similarly for the TX buffers
        if uart_tx_Buffer_pointer_read(i) = uart_tx_buffer_pointer_write(i) then
          uart_tx_empty(i) <= '1';
        else
          uart_tx_empty(i) <= '0';
        end if;
        -- Or full?
        if (to_integer(uart_tx_buffer_pointer_write(i) + 1) = to_integer(uart_tx_buffer_pointer_read(i)))
          or (uart_tx_buffer_pointer_write(i) = x"FF" and uart_tx_buffer_pointer_read(i) = x"00")
        then
          uart_tx_full(i) <= '1';
        else
          uart_tx_full(i) <= '0';
        end if;
        -- Has the TX buffer reached the low-water mark?
        if to_integer(uart_tx_buffer_pointer_write(i)) >= to_integer(uart_tx_buffer_pointer_read(i)) then
          -- Write point comes after read point, so simple subtraction
          if (to_integer(uart_tx_buffer_pointer_write(i)) - to_integer(uart_tx_buffer_pointer_read(i))) < 32 then
            uart_tx_lowwater(i) <= '1';
          else
            uart_tx_lowwater(i) <= '0';            
          end if;
        else
          if ((256 - to_integer(uart_tx_buffer_pointer_read(i))) + to_integer(uart_tx_buffer_pointer_write(i))) < 32 then
            -- Write point comes before read, so it must have wrapped
            uart_tx_lowwater(i) <= '1';
          else
            uart_tx_lowwater(i) <= '0';            
          end if;
        end if;
      end loop;
      
      uart_tx <= uart_tx_drive;
            
      if fastio_write='1' and buffereduart_cs='1' then
        case fastio_addr(3 downto 0) is
          when x"0" =>
            selected_uart <= to_integer(fastio_wdata(3 downto 0));
            master_irq_enable <= fastio_wdata(7);
            master_tx_irq_enable <= fastio_wdata(6);
            master_rx_irq_enable <= fastio_wdata(5);
            loopback_mode <= fastio_wdata(4);
          when x"1" =>
            if selected_uart < 8 then
              uart_irq_on_rx_byte(selected_uart) <= fastio_wdata(2);
              uart_irq_on_rx_highwater(selected_uart) <= fastio_wdata(1);
              uart_irq_on_tx_lowwater(selected_uart) <= fastio_wdata(0);
            end if;
          when x"2" =>
            -- Advance UART RX read point
            if selected_uart < 8 then
              if uart_rx_empty(selected_uart)='0' then
                -- Advance buffer position
                report "RXBUFFER: Asserting rx_byte_stale due to write to $D0E2";
                uart_rx_buffer_pointer_read(selected_uart) <= uart_rx_buffer_pointer_read(selected_uart) + 1;
                rx_byte_stale <= '1';
              end if;
            end if;
          when x"3" =>
            -- Write byte to UART TX queue
            if selected_uart < 8 then
              -- Remember the byte we wrote.
              last_tx_byte_written(selected_uart) <= fastio_wdata;
              tx_byte_written <= '1';
              report "Received byte $" & to_hstring(fastio_wdata) & " for queueing for transmit via uart #" & integer'image(selected_uart);
            end if;
          when x"4" =>
            if selected_uart < 8 then
              uart_bit_rate_divisor_internal(selected_uart)(7 downto 0) <= fastio_wdata;
              uart_bit_rate_divisor(selected_uart)(7 downto 0) <= fastio_wdata;
            end if;            
          when x"5" =>
            if selected_uart < 8 then
              uart_bit_rate_divisor_internal(selected_uart)(15 downto 8) <= fastio_wdata;
              uart_bit_rate_divisor(selected_uart)(15 downto 8) <= fastio_wdata;
            end if;            
          when x"6" =>
            if selected_uart < 8 then
              uart_bit_rate_divisor_internal(selected_uart)(23 downto 16) <= fastio_wdata;
              uart_bit_rate_divisor(selected_uart)(23 downto 16) <= fastio_wdata;
            end if;
          when others =>
            null;
        end case;
      end if;

      -- Highest priority is reading next byte when acknowledging or
      -- switching which UART we are looking at
      last_selected_uart <= selected_uart;
      if last_selected_uart /= selected_uart then
        rx_byte_stale <= '1';
        report "RXBUFFER: asserting rx_byte_stale due to UART selection";
      end if;
--      report "Considering buffer memory transactions.";
      if tx_byte_written = '1' then
        report "TXBUFFER: Committing byte $" & to_hstring(last_tx_byte_written(selected_uart)) & " to TX queue for uart #" & integer'image(selected_uart);
        read_scheduled <= '0';
        -- Schedule writing byte into TX buffer.
        tx_byte_written <= '0';
        if selected_uart < 8 then
          -- Write to TX buffer, but only if not full
          if uart_tx_full(selected_uart) = '0' then
            buffer_writeaddress <= (512*selected_uart) + 256 + to_integer(uart_tx_buffer_pointer_write(selected_uart));
            buffer_wdata <= last_tx_byte_written(selected_uart);
            buffer_write <= '1';
            uart_tx_buffer_pointer_write(selected_uart) <= uart_tx_buffer_pointer_write(selected_uart) + 1;
          end if;
        end if;
        read_scheduled <= '0';
      elsif rx_byte_stale = '1' then
        report "rx_byte_stale was asserted.";
        rx_byte_stale <= '0';
        if selected_uart < 8 then
          if uart_rx_empty(selected_uart) = '0' then
            report "RXBUFFER: reading from non-empty buffer @ $" &
              to_hstring(to_unsigned((512*selected_uart) + 0 + to_integer(uart_rx_buffer_pointer_read(selected_uart)),12));
            read_scheduled <= '1';
            read_target <= 0 + selected_uart;
          else
            report "RXBUFFER: buffer is empty. nothing to read";
            read_scheduled <= '0';
            read_target <= 255;
          end if;
          buffer_readaddress <= (512*selected_uart) + 0 + to_integer(uart_rx_buffer_pointer_read(selected_uart));
        end if;
      else
        -- Neither a buffer read nor buffer write is scheduled, so we can check
        -- for arriving or departing bytes in the actual UARTs
        if tx_ready(cycled_uart_id)='1' and uart_tx_empty(cycled_uart_id)='0' and tx_inhibit(cycled_uart_id)=0 then
          -- We should send the next byte
          read_scheduled <= '1';
          read_target <= 16 + cycled_uart_id;
          buffer_readaddress <= (512*cycled_uart_id) + 256 + to_integer(uart_tx_buffer_pointer_read(cycled_uart_id));
          report "TXBUFFER: Increment read position from $" & to_hstring(uart_tx_buffer_pointer_read(cycled_uart_id));
          uart_tx_buffer_pointer_read(cycled_uart_id) <= uart_tx_buffer_pointer_read(cycled_uart_id) + 1;
          tx_inhibit(cycled_uart_id) <= 7;
        elsif rx_ready(cycled_uart_id)='1' and uart_rx_full(cycled_uart_id)='0' and rx_inhibit(cycled_uart_id) = 0 then
          report "RXBUFFER: Received a byte from UART#" & integer'image(cycled_uart_id)
            & ", byte=$" & to_hstring(rx_data(cycled_uart_id));
          rx_acknowledge(cycled_uart_id) <= '1';
          buffer_writeaddress <= (512*cycled_uart_id) + 0 + to_integer(uart_rx_buffer_pointer_write(cycled_uart_id));
          buffer_wdata <= rx_data(cycled_uart_id);
          buffer_write <= '1';
          uart_rx_buffer_pointer_write(cycled_uart_id) <= uart_rx_buffer_pointer_write(cycled_uart_id) + 1;
          if uart_rx_empty(cycled_uart_id) = '1' then
            -- We are receiving a byte, and our RX buffer
            -- is empty, so we should present this byte to the CPU immediately
            rx_data_for_reading(cycled_uart_id) <= rx_data(cycled_uart_id);
          end if;
          rx_inhibit(cycled_uart_id) <= 7;
        else
          -- Nothing to do for this UART, so get ready to consider the next
          if cycled_uart_id /= 7 then
            cycled_uart_id <= cycled_uart_id + 1;
          else
            cycled_uart_id <= 0;
          end if;
        end if;
      end if;

      -- Now process freshly read data
      if read_scheduled = '1' then
        if read_target < 8 then
          -- Read to refresh received data to present to CPU
          rx_data_for_reading(selected_uart) <= buffer_rdata;
          report "RXBUFFER: Read back value $" & to_hstring(buffer_rdata) & " for presenting as current value";
        elsif read_target >= 16 and read_target < 24 then
          -- Read TX buffer to TX a byte
          report "TXBUFFER: Read back value $" & to_hstring(buffer_rdata) & " for immediate dispatch.";
          tx_trigger(read_target - 16) <= '1';
          tx_data(read_target - 16) <= buffer_rdata;
        end if;
      end if;

      if reset = '0' then
        -- Clear all buffers on reset
        uart_rx_empty <= (others => '1');
        uart_rx_full <= (others => '0');
        uart_tx_empty <= (others => '1');
        uart_tx_full <= (others => '0');

        uart_rx_buffer_pointer_write <= (others => to_unsigned(0,8));
        uart_rx_buffer_pointer_read <= (others => to_unsigned(0,8));
        uart_tx_buffer_pointer_write <= (others => to_unsigned(0,8));
        uart_tx_buffer_pointer_read <= (others => to_unsigned(0,8));

        tx_inhibit <= (others => 0);
        rx_inhibit <= (others => 0);
        
      end if;
      
    end if;
  end process;

end behavioural;
