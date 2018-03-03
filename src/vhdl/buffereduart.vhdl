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
    clock50mhz : in std_logic;
    clock200 : in std_logic;
    reset : in std_logic;
    irq : out std_logic := 'Z';
    buffereduart_cs : in std_logic;

    ---------------------------------------------------------------------------
    -- IO lines to the UART
    ---------------------------------------------------------------------------
    uart_rx : inout std_logic := 'H';
    uart_tx : out std_logic := '1';
    -- Only the primary UART has a ring indicate input
    uart_ringindicate : in std_logic;    

    ---------------------------------------------------------------------------
    -- IO lines to the second (auxilliary) UART
    ---------------------------------------------------------------------------    
    uart2_rx : inout std_logic := 'H';
    uart2_tx : out std_logic := '1';
    
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

  signal buffer_write : std_logic := '0';
  signal buffer_writeaddress : integer := 0;
  signal buffer_readaddress : integer := 0;
  signal buffer_wdata : unsigned(7 downto 0) := x"00"; 
  signal buffer_rdata : unsigned(7 downto 0) := x"00"; 

  signal uart0_bit_rate_divisor_internal : unsigned(15 downto 0) := to_unsigned(0,16);
  signal uart2_bit_rate_divisor_internal : unsigned(15 downto 0) := to_unsigned(0,16);
  signal tx0_data : unsigned(7 downto 0) := x"00";
  signal tx2_data : unsigned(7 downto 0) := x"00";
  signal tx0_ready : std_logic;
  signal tx2_ready : std_logic;
  signal tx0_trigger : std_logic := '0';
  signal tx2_trigger : std_logic := '0';
  signal rx0_data : unsigned(7 downto 0);
  signal rx2_data : unsigned(7 downto 0);
  signal rx0_ready : std_logic;
  signal rx2_ready : std_logic;
  signal rx0_ready_wait : std_logic := '0';
  signal rx2_ready_wait : std_logic := '0';
  signal tx0_ready_wait : std_logic := '0';
  signal tx2_ready_wait : std_logic := '0';
  signal rx0_acknowledge : std_logic := '0';
  signal rx2_acknowledge : std_logic := '0';

  -- 1KB RX buffers for each UART, and 512 byte TX buffers
  constant uart0_rx_buffer_start : integer := 0;
  constant uart2_rx_buffer_start : integer := 1024;
  constant uart0_tx_buffer_start : integer := 1024+1024;
  constant uart2_tx_buffer_start : integer := 1024+1024+512;
  signal uart0_rx_buffer_pointer : unsigned(9 downto 0) := to_unsigned(0,10);
  signal uart0_rx_buffer_pointer_prev : unsigned(9 downto 0) := to_unsigned(1023,10);
  signal uart2_rx_buffer_pointer : unsigned(9 downto 0) := to_unsigned(0,10);
  signal uart2_rx_buffer_pointer_prev : unsigned(9 downto 0) := to_unsigned(1023,10);
  signal uart0_tx_buffer_pointer : unsigned(8 downto 0) := to_unsigned(0,9);
  signal uart2_tx_buffer_pointer : unsigned(8 downto 0) := to_unsigned(0,9);
  -- Duplicates of the pointers for the CPU side
  -- The RX pointers point to the last address read from, so need to be
  -- initialised to point to the end of the buffer
  signal uart0_rx_buffer_pointer_cpu : unsigned(9 downto 0) := to_unsigned(1023,10);
  signal uart2_rx_buffer_pointer_cpu : unsigned(9 downto 0) := to_unsigned(1023,10);
  signal uart0_tx_buffer_pointer_cpu : unsigned(8 downto 0) := to_unsigned(0,9);
  signal uart2_tx_buffer_pointer_cpu : unsigned(8 downto 0) := to_unsigned(0,9);
  -- (when the two are equal, the buffer is either empty or full)

  signal queued_read : std_logic := '0';
  signal queued_read_tx0 : std_logic := '0';
  signal queued_read_tx2 : std_logic := '0';
  signal queued_read_rx0 : std_logic := '0';
  signal queued_read_rx2 : std_logic := '0';

  signal queued_write : std_logic := '0';
  signal queued_wdata : unsigned(7 downto 0) := x"00";
  signal queued_address : integer := 0;

  signal uart0_rx_byte : unsigned(7 downto 0) := x"00";
  signal uart0_rx_byte_ready : std_logic := '0';
  signal uart0_irq : std_logic := '0';
  signal uart0_irq_on_rx : std_logic := '0';
  signal uart0_irq_on_rx_highwater : std_logic := '0';
  signal uart0_irq_on_tx_lowwater : std_logic := '0';
  signal uart0_rx_empty : std_logic := '1';
  signal uart0_tx_empty : std_logic := '1';
  signal uart0_rx_full : std_logic := '0';
  signal uart0_tx_full : std_logic := '0';
  signal uart0_check_full : std_logic := '0';
  signal uart0_check_empty : std_logic := '0';
  
  signal uart2_rx_byte : unsigned(7 downto 0) := x"00";
  signal uart2_rx_byte_ready : std_logic := '0';
  signal uart2_irq : std_logic := '0';
  signal uart2_irq_on_rx : std_logic := '0';
  signal uart2_irq_on_rx_highwater : std_logic := '0';
  signal uart2_irq_on_tx_lowwater : std_logic := '0';
  signal uart2_rx_empty : std_logic := '1';
  signal uart2_tx_empty : std_logic := '1';
  signal uart2_rx_full : std_logic := '0';
  signal uart2_tx_full : std_logic := '0';
  signal uart2_check_full : std_logic := '0';
  signal uart2_check_empty  : std_logic := '0';

  signal uart0_rx_mux : std_logic;
  signal uart2_rx_mux : std_logic;

  signal uart0_rx_from_uart2_tx : std_logic := '0';
  signal uart2_rx_from_uart0_tx : std_logic := '0';

  signal uart0_tx_drive : std_logic;
  signal uart2_tx_drive : std_logic;

  signal uart0_read_byte_from_buffer : std_logic := '0';
  signal uart2_read_byte_from_buffer : std_logic := '0';

  signal uart0_rx_cpu_was_last : std_logic := '0';
  signal uart2_rx_cpu_was_last : std_logic := '0';

  signal uart0_tx_dummy_data : std_logic := '0';
  signal uart0_tx_queue_dummy_data : std_logic := '0';
  signal uart0_no_tx_buffer : std_logic := '0';

  signal uart_rx_auto_advance : std_logic := '1';
  signal uart0_rx_read_advance : std_logic := '0';
  signal uart2_rx_read_advance : std_logic := '0';
  
  signal last_was_read : std_logic := '0';
  
begin  -- behavioural

  buffer0: entity work.ram8x4096
    port map (
    clk => clock,
    cs => '1',
    w => buffer_write,
    write_address => buffer_writeaddress,
    wdata => buffer_wdata,
    address => buffer_readaddress,
    rdata => buffer_rdata);

  uart_tx0: entity work.UART_TX_CTRL
    port map (
      send    => tx0_trigger,
      BIT_TMR_MAX => uart0_bit_rate_divisor_internal,
      clk     => clock,
      data    => std_logic_vector(tx0_data),
      ready   => tx0_ready,
      uart_tx => uart0_tx_drive);

  uart_rx0: entity work.uart_rx 
    generic map (name => "0")
    Port map ( clk => clock,
               bit_rate_divisor => uart0_bit_rate_divisor_internal,
               UART_RX => uart0_rx_mux,

               data => rx0_data,
               data_ready => rx0_ready,
               data_acknowledge => rx0_acknowledge);

  uart_tx1: entity work.UART_TX_CTRL
    port map (
      send    => tx2_trigger,
      BIT_TMR_MAX => uart2_bit_rate_divisor_internal,
      clk     => clock,
      data    => std_logic_vector(tx2_data),
      ready   => tx2_ready,
      uart_tx => uart2_tx_drive);

  uart_rx1: entity work.uart_rx
    generic map (name => "2")
    Port map ( clk => clock,
               bit_rate_divisor => uart2_bit_rate_divisor_internal,
               UART_RX => uart2_rx_mux,

               data => rx2_data,
               data_ready => rx2_ready,
               data_acknowledge => rx2_acknowledge);

  
  process (clock,fastio_addr,fastio_wdata,fastio_read,fastio_write,
           uart0_rx_from_uart2_tx,uart2_rx_from_uart0_tx,
           uart_rx,uart0_tx_drive,uart2_rx,uart0_rx_byte,uart0_irq,
           uart0_rx_byte_ready,uart0_tx_empty,uart0_rx_full,
           uart0_tx_full,uart0_irq_on_rx,uart0_irq_on_rx_highwater,
           uart0_irq_on_tx_lowwater,uart0_rx_buffer_pointer_cpu,
           uart0_rx_buffer_pointer,uart0_bit_rate_divisor_internal,
           uart2_rx_byte,uart2_irq,uart2_rx_byte_ready,uart2_tx_empty,
           uart2_tx_full,uart2_rx_full,uart2_irq_on_rx,uart2_irq_on_rx_highwater,
           uart2_irq_on_tx_lowwater,uart2_rx_buffer_pointer_cpu,
           uart2_tx_buffer_pointer_cpu,uart2_rx_buffer_pointer,
           uart2_tx_buffer_pointer,uart2_bit_rate_divisor_internal,
           uart2_tx_drive,buffereduart_cs,uart0_tx_buffer_pointer,
           uart0_tx_buffer_pointer_cpu
           ) is
    variable temp_cmd : unsigned(7 downto 0);

  begin

    -- MUX to allow connecting serial ports to outside lines, or alternatively
    -- to the opposite buffered UART (as a remote loopback diagnostic mode)
    if uart0_rx_from_uart2_tx='0' then
      uart0_rx_mux <= uart_rx;
    else
      uart0_rx_mux <= uart2_tx_drive;
    end if;
    if uart2_rx_from_uart0_tx='0' then
      uart2_rx_mux <= uart2_rx;
    else
      uart2_rx_mux <= uart0_tx_drive;
    end if;
    
    irq <= 'Z';

    -- Register reading is asynchronous to avoid wait states
    if fastio_read='1' then
      if buffereduart_cs='1' then
        case fastio_addr(3 downto 0) is
          -- Use this notation to create entries for auto-populating iomap.txt
          -- @IO:GS $D0E0 Buffered UART1 Data register (read to accept a byte, write to transmit a byte)
          -- @IO:GS $D0E1 Buffered UART1 Status register
          -- @IO:GS $D0E1.7 Buffered UART1 interrupt status
          -- @IO:GS $D0E1.6 Buffered UART1 RX buffer empty
          -- @IO:GS $D0E1.5 Buffered UART1 TX buffer empty
          -- @IO:GS $D0E1.4 Buffered UART1 RX buffer full
          -- @IO:GS $D0E1.3 Buffered UART1 TX buffer full
          -- @IO:GS $D0E1.2 Buffered UART1 enable interrupt on RX byte
          -- @IO:GS $D0E1.1 Buffered UART1 enable interrupt on RX high-water mark
          -- @IO:GS $D0E1.0 Buffered UART1 enable interrupt on TX buffer low-water mark
          -- @IO:GS $D0E6 Buffered UART2 frequency divisor (LSB)
          -- @IO:GS $D0E7 Buffered UART2 frequency divisor (MSB)

          -- @IO:GS $D0E8 Buffered UART2 Data register (read to accept a byte, write to transmit a byte)
          -- @IO:GS $D0E9 Buffered UART2 Status register
          -- @IO:GS $D0E9.7 Buffered UART2 interrupt status
          -- @IO:GS $D0E9.6 Buffered UART2 RX buffer empty
          -- @IO:GS $D0E9.5 Buffered UART2 TX buffer empty
          -- @IO:GS $D0E9.4 Buffered UART2 RX buffer full
          -- @IO:GS $D0E9.3 Buffered UART2 TX buffer full
          -- @IO:GS $D0E9.2 Buffered UART2 enable interrupt on RX byte
          -- @IO:GS $D0E9.1 Buffered UART2 enable interrupt on RX high-water mark
          -- @IO:GS $D0E9.0 Buffered UART2 enable interrupt on TX buffer low-water mark
          -- @IO:GS $D0EE Buffered UART2 frequency divisor (LSB)
          -- @IO:GS $D0EF Buffered UART2 frequency divisor (MSB)
          
          when x"0" => fastio_rdata <= uart0_rx_byte;
          when x"1" =>
            fastio_rdata(7) <= uart0_irq;
            fastio_rdata(6) <= not uart0_rx_byte_ready;
            fastio_rdata(5) <= uart0_tx_empty;
            fastio_rdata(4) <= uart0_rx_full;
            fastio_rdata(3) <= uart0_tx_full;
            fastio_rdata(2) <= uart0_irq_on_rx;
            fastio_rdata(1) <= uart0_irq_on_rx_highwater;
            fastio_rdata(0) <= uart0_irq_on_tx_lowwater;
          when x"2" => fastio_rdata <= uart0_rx_buffer_pointer_cpu(7 downto 0);
          when x"3" => fastio_rdata <= uart0_tx_buffer_pointer_cpu(7 downto 0);
          when x"4" => fastio_rdata <= uart0_rx_buffer_pointer(7 downto 0);
          when x"5" => fastio_rdata <= uart0_tx_buffer_pointer(7 downto 0);
          when x"6" => fastio_rdata <= uart0_bit_rate_divisor_internal(7 downto 0);
          when x"7" =>
            fastio_rdata <= uart0_bit_rate_divisor_internal(15 downto 8);
          when x"8" => fastio_rdata <= uart2_rx_byte;
          when x"9" =>
            fastio_rdata(7) <= uart2_irq;
            fastio_rdata(6) <= not uart2_rx_byte_ready;
            fastio_rdata(5) <= uart2_tx_empty;
            fastio_rdata(4) <= uart2_rx_full;
            fastio_rdata(3) <= uart2_tx_full;
            fastio_rdata(2) <= uart2_irq_on_rx;
            fastio_rdata(1) <= uart2_irq_on_rx_highwater;
            fastio_rdata(0) <= uart2_irq_on_tx_lowwater;
          when x"A" => fastio_rdata <= uart2_rx_buffer_pointer_cpu(7 downto 0);
          when x"B" => fastio_rdata <= uart2_tx_buffer_pointer_cpu(7 downto 0);
          when x"C" => fastio_rdata <= uart2_rx_buffer_pointer(7 downto 0);
          when x"D" => fastio_rdata <= uart2_tx_buffer_pointer(7 downto 0);
          when x"E" => fastio_rdata <= uart2_bit_rate_divisor_internal(7 downto 0);
          when x"F" =>
            fastio_rdata <= uart2_bit_rate_divisor_internal(15 downto 8);
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

      rx0_acknowledge <= '0';
      rx2_acknowledge <= '0';
      tx0_trigger <= '0';
      tx2_trigger <= '0';
      buffer_write <= '0';
          
      uart_tx <= uart0_tx_drive;
      uart2_tx <= uart2_tx_drive;

      if uart0_rx_read_advance='1' then
        uart0_rx_read_advance <= '0';

        uart0_rx_byte_ready <= '0';
        if uart0_rx_empty='1' or
          -- Buffer is either full or empty
          ((uart0_rx_buffer_pointer_prev = uart0_rx_buffer_pointer_cpu)
           -- And it is empty (because it was read from to get here)
           and (uart0_rx_cpu_was_last='1')) then
          -- Buffer is empty, so don't advance pointer
          uart0_rx_empty <= '1';
          uart0_rx_byte <= x"00";
        else
          -- Buffer is not empty, so advance
          uart0_rx_empty <= '0';
          uart0_rx_cpu_was_last <= '1';
          if uart0_rx_buffer_pointer_cpu /= "1111111111" then
            uart0_rx_buffer_pointer_cpu <= uart0_rx_buffer_pointer_cpu + 1;
          else
            uart0_rx_buffer_pointer_cpu <= to_unsigned(0,10);
          end if;
          uart0_read_byte_from_buffer <= '1';
        end if;
      end if;        
      if uart2_rx_read_advance='1' then
        uart2_rx_read_advance <= '0';
        -- After reading a byte from buffer, advance buffer pointer
        uart2_rx_byte_ready <= '0';
        report "UART2 reading from $D0E8 : uart2_rx_buffer_pointer_prev=$" & to_hstring(uart2_rx_buffer_pointer_prev)
          & ", *_cpu=$" & to_hstring(uart2_rx_buffer_pointer_cpu)
          & ", *_empty=" & std_logic'image(uart2_rx_empty)
          & ", *_cpu_was_last=" & std_logic'image(uart2_rx_cpu_was_last);
        if uart2_rx_empty='1' or
          -- Buffer is either full or empty
          ((uart2_rx_buffer_pointer_prev = uart2_rx_buffer_pointer_cpu)
           -- And it is empty (because it was read from to get here)
           and (uart2_rx_cpu_was_last='1')) then
          report "UART2: not advancing buffer, because empty";
          -- Buffer is empty, so don't advance pointer
          uart2_rx_empty <= '1';
          uart2_rx_byte <= x"00";
        else
          -- Buffer is not empty, so advance
          report "UART2: advancing pointer in non-empty buffer";
          uart2_rx_empty <= '0';
          uart2_rx_cpu_was_last <= '1';
          if uart2_rx_buffer_pointer_cpu /= "1111111111" then
            uart2_rx_buffer_pointer_cpu <= uart2_rx_buffer_pointer_cpu + 1;
          else
            uart2_rx_buffer_pointer_cpu <= to_unsigned(0,10);
          end if;
          uart2_read_byte_from_buffer <= '1';
        end if;
      end if;
      
      -- Update module status based on register reads
      if fastio_read='1' and buffereduart_cs='1' then
        -- CPU can cause successive reads to a single address
        -- that are spurious, so we require a non-access between
        -- accesses for the side effect to happen
        last_was_read <= '1';
        if last_was_read = '0' then
          case fastio_addr(3 downto 0) is
            when x"0" =>
              if uart_rx_auto_advance='1' then
                uart0_rx_read_advance <= '1';
              end if;
            when x"8" =>
              if uart_rx_auto_advance='1' then
                uart2_rx_read_advance <= '1';
              end if;
            when others =>
              null;
          end case;
        else
          last_was_read <= '0';
        end if;
      end if;
      
      if fastio_write='1' and buffereduart_cs='1' then
        case fastio_addr(3 downto 0) is
          when x"0" =>
            -- XXX For some reason the buffering doesn't work correctly
            if uart0_no_tx_buffer='1' and tx0_ready='1' then
              tx0_trigger <= '1';
              tx0_data <= fastio_wdata;
            else
              -- CPU asks for byte to be TXd, so put in buffer
              queued_write <= '1';
              if uart0_tx_queue_dummy_data='1' then
                queued_wdata <= x"99";
              else
                queued_wdata <= fastio_wdata;
              end if;
              queued_address <= uart0_tx_buffer_start
                                + to_integer(uart0_tx_buffer_pointer_cpu);
              if uart0_tx_buffer_pointer_cpu /= "111111111" then
                uart0_tx_buffer_pointer_cpu <= uart0_tx_buffer_pointer_cpu + 1;
              else
                uart0_tx_buffer_pointer_cpu <= to_unsigned(0,9);
              end if;
              uart0_check_full <= '1';
            end if;
          when x"8" =>
            -- CPU asks for byte to be TXd, so put in buffer
            queued_write <= '1';
            queued_wdata <= fastio_wdata;
            queued_address <= uart2_tx_buffer_start
                              + to_integer(uart2_tx_buffer_pointer_cpu);
            if uart2_tx_buffer_pointer_cpu /= "111111111" then
              uart2_tx_buffer_pointer_cpu <= uart2_tx_buffer_pointer_cpu + 1;
            else
              uart2_tx_buffer_pointer_cpu <= to_unsigned(0,9);
            end if;
            uart2_check_full <= '1';            
          when x"1" =>
            -- Set control values for UART0
            -- Writing always clears current IRQ status
            uart0_irq <= '0';
            uart0_irq_on_rx <= fastio_wdata(2);
            uart0_irq_on_rx_highwater <= fastio_wdata(1);
            uart0_irq_on_tx_lowwater <= fastio_wdata(0);
          when x"9" =>
            -- Set control values for UART2
            -- Writing always clears current IRQ status
            uart2_irq <= '0';
            uart2_irq_on_rx <= fastio_wdata(2);
            uart2_irq_on_rx_highwater <= fastio_wdata(1);
            uart2_irq_on_tx_lowwater <= fastio_wdata(0);
          when x"2" =>
            uart0_rx_from_uart2_tx <= fastio_wdata(0);
            uart0_tx_dummy_data <= fastio_wdata(1);
            uart0_tx_queue_dummy_data <= fastio_wdata(2);
            uart0_no_tx_buffer <= fastio_wdata(3);
            uart_rx_auto_advance <= fastio_wdata(4);
          when x"3" =>
            -- Advance RX buffer manually
            uart0_rx_read_advance <= '1';
          when x"b" =>
            -- Advance RX buffer manually
            uart2_rx_read_advance <= '1';
          when x"a" =>
            uart2_rx_from_uart0_tx <= fastio_wdata(0);
          when x"6" =>
            uart0_bit_rate_divisor_internal(7 downto 0) <= fastio_wdata;
          when x"7" =>
            uart0_bit_rate_divisor_internal(15 downto 8)
              <= fastio_wdata;
          when x"e" =>
            uart2_bit_rate_divisor_internal(7 downto 0) <= fastio_wdata;
          when x"f" =>
            uart2_bit_rate_divisor_internal(15 downto 8)
              <= fastio_wdata;
          when others =>
            null;
        end case;
      end if;

      if uart0_check_full='1' then
        report "UART0: Check full";
        if uart0_rx_buffer_pointer = uart0_rx_buffer_pointer_cpu then
          uart0_rx_full <= '1';
        else
          uart0_rx_full <= '0';          
        end if;
        uart0_check_full <= '0';
      end if;
      if uart0_check_empty='1' then
        report "UART0: Check empty";
        if uart0_tx_buffer_pointer = uart0_tx_buffer_pointer_cpu then
          uart0_tx_empty <= '1';
        else
          uart0_tx_empty <= '0';
        end if;
        uart0_check_empty <= '0';
      end if;
      if uart2_check_full='1' then
        report "UART2: Check full";
        if uart2_rx_buffer_pointer = uart2_rx_buffer_pointer_cpu then
          uart2_rx_full <= '1';
        else
          uart2_rx_full <= '0';          
        end if;
        uart2_check_full <= '0';
      end if;
      if uart2_check_empty='1' then
        report "UART2: Check empty";
        if uart2_tx_buffer_pointer = uart2_tx_buffer_pointer_cpu then
          uart2_tx_empty <= '1';
        else
          uart2_tx_empty <= '0';
        end if;
        uart2_check_empty <= '0';
      end if;
      
      -- Do synchronous actions
      if queued_write='1' then
        report "UART: Performing queued write of $" & to_hstring(queued_wdata) & " to $" & to_hstring(to_unsigned(queued_address,12));
        -- CPU queued buffer write
        buffer_wdata <= queued_wdata;
        buffer_writeaddress <= queued_address;
        buffer_Write <= '1';
        -- XXX Clearing this hear means back-to-back writes will
        -- not work.  Only a problem for DMA filling the buffer.
        queued_write <= '0';
      elsif uart0_read_byte_from_buffer='1' and queued_read='0' and uart0_rx_empty='0' then
        uart0_rx_byte <= x"00";
        report "UART0: Scheduling read of next byte from RX buffer in preparation for next CPU read"
          & " (address = $" & to_hstring(to_unsigned(uart0_rx_buffer_start
                                + to_integer(uart0_rx_buffer_pointer_cpu),12));
        queued_read <= '1';
        queued_read_rx0 <= '1';
        buffer_readaddress <= uart0_rx_buffer_start
                              + to_integer(uart0_rx_buffer_pointer_cpu);
          uart0_read_byte_from_buffer <= '0';
      elsif uart2_read_byte_from_buffer='1' and queued_read='0' and uart2_rx_empty='0' then
        uart2_rx_byte <= x"00";
        report "UART2: Scheduling read of next byte from RX buffer in preparation for next CPU read"
          & " (address = $" & to_hstring(to_unsigned(uart2_rx_buffer_start
                                + to_integer(uart2_rx_buffer_pointer_cpu),12));
        queued_read <= '1';
        queued_read_rx2 <= '1';
        buffer_readaddress <= uart2_rx_buffer_start
                              + to_integer(uart2_rx_buffer_pointer_cpu);
        uart2_read_byte_from_buffer <= '0';
      elsif rx0_ready='0' and rx0_ready_wait='1' then
        rx0_ready_wait <= '0';        
      elsif tx0_ready='0' and tx0_ready_wait='1' then
        tx0_ready_wait <= '0';        
      elsif rx0_ready='1' and rx0_ready_wait='0' and queued_write='0' then
        report "UART0: Data ready was asserted by UART RX. Byte is $" & to_hstring(rx0_data)
          & ", writing to $" & to_hstring(to_unsigned(uart0_rx_buffer_start
                               + to_integer(uart0_rx_buffer_pointer),12));
        rx0_ready_wait <= '1';
        buffer_wdata <= rx0_data;
        uart0_rx_empty <= '0';
        uart0_rx_cpu_was_last <= '0';
        uart0_check_full <= '1';
        buffer_writeaddress <= uart0_rx_buffer_start
                               + to_integer(uart0_rx_buffer_pointer);
        if uart0_rx_buffer_pointer /= "1111111111" then
          uart0_rx_buffer_pointer <= uart0_rx_buffer_pointer + 1;
        else
          uart0_rx_buffer_pointer <= to_unsigned(0,10);
        end if;
        uart0_rx_buffer_pointer_prev <= uart0_rx_buffer_pointer;
        buffer_write <= '1';
        rx0_acknowledge <= '1';        
      elsif rx2_ready='0' and rx2_ready_wait='1' then
        rx2_ready_wait <= '0';        
      elsif tx2_ready='0' and tx2_ready_wait='1' then
        tx2_ready_wait <= '0';        
      elsif rx2_ready='1' and rx2_ready_wait='0' and queued_write='0' then
        rx2_ready_wait <= '1';
        report "UART2: Data ready was asserted by UART RX. Byte is $" & to_hstring(rx2_data)
          & ", writing to $" & to_hstring(to_unsigned(uart2_rx_buffer_start
                               + to_integer(uart2_rx_buffer_pointer),12));
        buffer_wdata <= rx2_data;
        uart2_rx_empty <= '0';
        uart2_check_full <= '1';
        uart2_rx_cpu_was_last <= '0';
        buffer_writeaddress <= uart2_rx_buffer_start
                               + to_integer(uart2_rx_buffer_pointer);
        if uart2_rx_buffer_pointer /= "1111111111" then
          uart2_rx_buffer_pointer <= uart2_rx_buffer_pointer + 1;
        else
          uart2_rx_buffer_pointer <= to_unsigned(0,10);
        end if;
        uart2_rx_buffer_pointer_prev <= uart2_rx_buffer_pointer;
        report "UART2: Updating uart2_rx_buffer_pointer_prev to $"
          & to_hstring(uart2_rx_buffer_pointer);
        buffer_write <= '1';
        rx2_acknowledge <= '1';
      elsif queued_read='1' then
        report "UART: Processing queued read";
        queued_read <= '0';
        queued_read_tx0 <= '0';
        queued_read_tx2 <= '0';
        queued_read_rx0 <= '0';
        queued_read_rx2 <= '0';        
        if queued_read_tx0 = '1' then
          tx0_trigger <= '1';
          if uart0_tx_dummy_data='1' then
            tx0_data <= x"55";
          else
            tx0_data <= buffer_rdata;
          end if;
          queued_read_tx0 <= '0';
          report "UART0: Triggering transmit of $" & to_hstring(buffer_rdata);
        end if;
        if queued_read_tx2 = '1' then
          tx2_trigger <= '1';
          tx2_data <= buffer_rdata;
          queued_read_tx2 <= '0';
          report "UART2: Triggering transmit of $" & to_hstring(buffer_rdata);
        end if;
        if queued_read_rx0 = '1' then
          uart0_rx_byte_ready <= '1';
          uart0_rx_byte <= buffer_rdata;
          report "UART0: Pre-fetching next received byte to show at $D0E0 (byte is $" & to_hstring(buffer_rdata) & ")";
        end if;
        if queued_read_rx2 = '1' then
          uart2_rx_byte_ready <= '1';
          uart2_rx_byte <= buffer_rdata;
          report "UART2: Pre-fetching next received byte to show at $D0E0 (byte is $" & to_hstring(buffer_rdata) & ")";
        end if;
      elsif uart0_tx_buffer_pointer_cpu /= uart0_tx_buffer_pointer then
        -- Queue buffer read
        report "UART0: TX buffer is not empty, consider sending a byte.";
        if tx0_ready='1' and queued_read='0' and tx0_ready_wait='0' then
          report "UART0: Queuing reading of byte at $"
            & to_hstring(to_unsigned(uart0_tx_buffer_start
                                     + to_integer(uart0_tx_buffer_pointer),12))
            & " ready for TX";
          queued_read <= '1';
          queued_read_tx0 <= '1';
          tx0_ready_wait <= '1';
          buffer_readaddress <= uart0_tx_buffer_start
                                + to_integer(uart0_tx_buffer_pointer);
          if uart0_tx_buffer_pointer /= "111111111" then
            uart0_tx_buffer_pointer <= uart0_tx_buffer_pointer + 1;
          else
            uart0_tx_buffer_pointer <= to_unsigned(0,9);
          end if;
        end if;
      elsif uart2_tx_buffer_pointer_cpu /= uart2_tx_buffer_pointer then
        report "UART2: TX buffer is not empty, consider sending a byte.";
        if tx2_ready='1' and queued_read='0' and tx2_ready_wait='0' then
          report "UART2: Queuing reading of byte at $"
            & to_hstring(to_unsigned(uart2_tx_buffer_start
                                     + to_integer(uart2_tx_buffer_pointer),12))
            & " ready for TX";
          queued_read <= '1';
          queued_read_tx2 <= '1';
          tx2_ready_wait <= '1';
          buffer_readaddress <= uart2_tx_buffer_start
                                + to_integer(uart2_tx_buffer_pointer);
          if uart2_tx_buffer_pointer /= "111111111" then
            uart2_tx_buffer_pointer <= uart2_tx_buffer_pointer + 1;
          else
            uart2_tx_buffer_pointer <= to_unsigned(0,9);
          end if;
        end if;
      else
        buffer_write <= '0';
      end if;
      
    end if;
  end process;

end behavioural;
