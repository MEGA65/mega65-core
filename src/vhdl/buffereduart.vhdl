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
    uart_rx : in std_logic;
    uart_tx : out std_logic := '1';
    -- Only the primary UART has a ring indicate input
    uart_ringindicate : in std_logic;    

    ---------------------------------------------------------------------------
    -- IO lines to the second (auxilliary) UART
    ---------------------------------------------------------------------------    
    uart2_rx : in std_logic;
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

  signal uart0_bit_rate_divisor_internal : unsigned(13 downto 0);
  signal uart2_bit_rate_divisor_internal : unsigned(13 downto 0);
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
  signal rx0_acknowledge : std_logic := '0';
  signal rx2_acknowledge : std_logic := '0';

  -- 1KB RX buffers for each UART, and 512 byte TX buffers
  constant uart0_rx_buffer_start : integer := 0;
  constant uart2_rx_buffer_start : integer := 1024;
  constant uart0_tx_buffer_start : integer := 1024+1024;
  constant uart2_tx_buffer_start : integer := 1024+1024+512;
  signal uart0_rx_buffer_pointer : unsigned(9 downto 0) := to_unsigned(0,10);
  signal uart2_rx_buffer_pointer : unsigned(9 downto 0) := to_unsigned(0,10);
  signal uart0_tx_buffer_pointer : unsigned(8 downto 0) := to_unsigned(0,9);
  signal uart2_tx_buffer_pointer : unsigned(8 downto 0) := to_unsigned(0,9);
  -- Duplicates of the pointers for the CPU side
  signal uart0_rx_buffer_pointer_cpu : unsigned(9 downto 0) := to_unsigned(0,10);
  signal uart2_rx_buffer_pointer_cpu : unsigned(9 downto 0) := to_unsigned(0,10);
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
  signal uart0_irq : std_logic := '0';
  signal uart0_irq_on_rx : std_logic := '0';
  signal uart0_irq_on_rx_highwater : std_logic := '0';
  signal uart0_irq_on_tx_lowwater : std_logic := '0';
  signal uart0_rx_empty : std_logic := '0';
  signal uart0_tx_empty : std_logic := '0';
  signal uart0_rx_full : std_logic := '0';
  signal uart0_tx_full : std_logic := '0';
  signal uart0_check_full : std_logic := '0';
  signal uart0_check_empty : std_logic := '0';
  
  signal uart2_rx_byte : unsigned(7 downto 0) := x"00";
  signal uart2_irq : std_logic := '0';
  signal uart2_irq_on_rx : std_logic := '0';
  signal uart2_irq_on_rx_highwater : std_logic := '0';
  signal uart2_irq_on_tx_lowwater : std_logic := '0';
  signal uart2_rx_empty : std_logic := '0';
  signal uart2_tx_empty : std_logic := '0';
  signal uart2_rx_full : std_logic := '0';
  signal uart2_tx_full : std_logic := '0';
  signal uart2_check_full : std_logic := '0';
  signal uart2_check_empty  : std_logic := '0';
  
begin  -- behavioural

  buffer0: entity work.ram8x4096 port map (
    clk => clock50mhz,
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
      uart_tx => uart_tx);

  uart_rx0: entity work.uart_rx 
    Port map ( clk => clock,
               bit_rate_divisor => uart0_bit_rate_divisor_internal,
               UART_RX => uart_rx,

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
      uart_tx => uart2_tx);

  uart_rx1: entity work.uart_rx 
    Port map ( clk => clock,
               bit_rate_divisor => uart2_bit_rate_divisor_internal,
               UART_RX => uart2_rx,

               data => rx2_data,
               data_ready => rx2_ready,
               data_acknowledge => rx2_acknowledge);

  
  process (clock,fastio_addr,fastio_wdata,fastio_read,fastio_write
           ) is
    variable temp_cmd : unsigned(7 downto 0);

  begin

    irq <= 'Z';
    
    -- Register reading is asynchronous to avoid wait states
    if fastio_read='1' then
      if buffereduart_cs='1' then
        report "MEMORY: Reading from buffered UART register block";
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
            fastio_rdata(6) <= uart0_rx_empty;
            fastio_rdata(5) <= uart0_tx_empty;
            fastio_rdata(4) <= uart0_rx_full;
            fastio_rdata(3) <= uart0_tx_full;
            fastio_rdata(2) <= uart0_irq_on_rx;
            fastio_rdata(1) <= uart0_irq_on_rx_highwater;
            fastio_rdata(0) <= uart0_irq_on_tx_lowwater;
          when x"6" => fastio_rdata <= uart0_bit_rate_divisor_internal(7 downto 0);
          when x"7" =>
            fastio_rdata(5 downto 0) <= uart0_bit_rate_divisor_internal(13 downto 8);
            fastio_rdata(7 downto 6) <= "00";
          when x"8" => fastio_rdata <= uart2_rx_byte;
          when x"9" =>
            fastio_rdata(7) <= uart2_irq;
            fastio_rdata(6) <= uart2_rx_empty;
            fastio_rdata(5) <= uart2_tx_empty;
            fastio_rdata(4) <= uart2_rx_full;
            fastio_rdata(3) <= uart2_tx_full;
            fastio_rdata(2) <= uart2_irq_on_rx;
            fastio_rdata(1) <= uart2_irq_on_rx_highwater;
            fastio_rdata(0) <= uart2_irq_on_tx_lowwater;
          when x"E" => fastio_rdata <= uart2_bit_rate_divisor_internal(7 downto 0);
          when x"F" =>
            fastio_rdata(5 downto 0) <= uart2_bit_rate_divisor_internal(13 downto 8);
            fastio_rdata(7 downto 6) <= "00";
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

      -- Update module status based on register reads
      if fastio_read='1' and buffereduart_cs='1' then
        case fastio_addr(3 downto 0) is
          when x"0" =>
            -- Cause a side effect when $D0E0 is read
            null;
          when others =>
            null;
        end case;
      end if;

      if fastio_write='1' and buffereduart_cs='1' then
        case fastio_addr(3 downto 0) is
          when x"0" =>
            -- CPU asks for byte to be TXd, so put in buffer
          when x"8" =>
            -- CPU asks for byte to be TXd, so put in buffer
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
          when x"6" =>
            uart0_bit_rate_divisor_internal(7 downto 0) <= fastio_wdata;
          when x"7" =>
            uart0_bit_rate_divisor_internal(13 downto 8)
              <= fastio_wdata(5 downto 0);
          when x"e" =>
            uart2_bit_rate_divisor_internal(7 downto 0) <= fastio_wdata;
          when x"f" =>
            uart2_bit_rate_divisor_internal(13 downto 8)
              <= fastio_wdata(5 downto 0);
          when others =>
            null;
        end case;
      end if;

      if uart0_check_full='1' then
        if uart0_rx_buffer_pointer = uart0_rx_buffer_pointer_cpu then
          uart0_rx_full <= '1';
        else
          uart0_rx_full <= '0';          
        end if;
        uart0_check_full <= '0';
      end if;
      if uart0_check_empty='1' then
        if uart0_tx_buffer_pointer = uart0_tx_buffer_pointer_cpu then
          uart0_tx_empty <= '1';
        else
          uart0_tx_empty <= '0';
        end if;
        uart0_check_empty <= '0';
      end if;
      if uart2_check_full='1' then
        if uart2_rx_buffer_pointer = uart2_rx_buffer_pointer_cpu then
          uart2_rx_full <= '1';
        else
          uart2_rx_full <= '0';          
        end if;
        uart2_check_full <= '0';
      end if;
      if uart2_check_empty='1' then
        if uart2_tx_buffer_pointer = uart2_tx_buffer_pointer_cpu then
          uart2_tx_empty <= '1';
        else
          uart2_tx_empty <= '0';
        end if;
        uart2_check_empty <= '0';
      end if;
      
      -- Do synchronous actions
      rx0_acknowledge <= '0';
      rx2_acknowledge <= '0';
      tx0_trigger <= '0';
      tx2_trigger <= '0';
      buffer_write <= '0';
      if queued_write='1' then
        -- CPU queued buffer write
        buffer_wdata <= queued_wdata;
        buffer_writeaddress <= queued_address;
        buffer_Write <= '1';
        -- XXX Clearing this hear means back-to-back writes will
        -- not work.  Only a problem for DMA filling the buffer.
        queued_write <= '0';
      elsif rx0_ready='1' then
        buffer_wdata <= rx0_data;
        if uart0_rx_buffer_pointer = uart0_rx_buffer_pointer_cpu then
          -- Buffer was empty, so make this received byte visible
          uart0_rx_byte <= rx0_data;
        end if;
        uart0_check_full <= '1';
        buffer_writeaddress <= uart0_rx_buffer_start
                               + to_integer(uart0_rx_buffer_pointer);
        if uart0_rx_buffer_pointer /= "1111111111" then
          uart0_rx_buffer_pointer <= uart0_rx_buffer_pointer + 1;
        else
          uart0_rx_buffer_pointer <= to_unsigned(0,10);
        end if;
        buffer_write <= '1';
        rx0_acknowledge <= '1';        
      elsif rx2_ready='1' then
        buffer_wdata <= rx2_data;
        if uart2_rx_buffer_pointer = uart2_rx_buffer_pointer_cpu then
          -- Buffer was empty, so make this received byte visible
          uart2_rx_byte <= rx2_data;
        end if;
        uart2_check_full <= '1';
        buffer_writeaddress <= uart2_rx_buffer_start
                               + to_integer(uart2_rx_buffer_pointer);
        if uart2_rx_buffer_pointer /= "1111111111" then
          uart2_rx_buffer_pointer <= uart2_rx_buffer_pointer + 1;
        else
          uart2_rx_buffer_pointer <= to_unsigned(0,10);
        end if;
        buffer_write <= '1';
        rx2_acknowledge <= '1';
      elsif queued_read='1' then
        queued_read <= '0';
        queued_read_tx0 <= '0';
        queued_read_tx2 <= '0';
        queued_read_rx0 <= '0';
        queued_read_rx2 <= '0';        
        if queued_read_tx0 = '1' then
          tx0_trigger <= '1';
          tx0_data <= buffer_rdata;
          queued_read_tx0 <= '0';
        end if;
        if queued_read_tx2 = '1' then
          tx2_trigger <= '1';
          tx2_data <= buffer_rdata;
          queued_read_tx2 <= '0';
        end if;
        if queued_read_rx0 = '1' then
          uart0_rx_byte <= buffer_rdata;
        end if;
        if queued_read_rx2 = '1' then
          uart2_rx_byte <= buffer_rdata;
        end if;
      elsif uart0_tx_buffer_pointer_cpu /= uart0_tx_buffer_pointer then
        -- Queue buffer read
        if tx0_ready='1' then
          queued_read <= '1';
          queued_read_tx0 <= '1';
          buffer_readaddress <= uart0_tx_buffer_start
                                + to_integer(uart0_tx_buffer_pointer);
          if uart0_tx_buffer_pointer /= "111111111" then
            uart0_tx_buffer_pointer <= uart0_tx_buffer_pointer + 1;
          else
            uart0_tx_buffer_pointer <= to_unsigned(0,9);
          end if;
        elsif tx2_ready='1' then
          queued_read <= '1';
          queued_read_tx2 <= '1';
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
