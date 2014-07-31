--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2014
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

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.PCK_CRC32_D8.all;
  
entity ethernet is
  port (
    clock : in std_logic;
    clock50mhz : in std_logic;
    reset : in std_logic;

    ---------------------------------------------------------------------------
    -- IO lines to the ethernet controller
    ---------------------------------------------------------------------------
    eth_mdio : inout std_logic := '1';
    eth_mdc : out std_logic := '1';
    eth_reset : out std_logic := '1';
    eth_rxd : in unsigned(1 downto 0);
    eth_txd : out unsigned(1 downto 0) := "11";
    eth_txen : out std_logic := '0';
    eth_rxdv : in std_logic;
    eth_rxer : in std_logic;
    eth_interrupt : in std_logic;
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : in unsigned(19 downto 0);
    fastio_write : in std_logic;
    fastio_read : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0)
    );
end ethernet;

architecture behavioural of ethernet is

  component ram8x4096 IS
    PORT (
      clk : IN STD_LOGIC;
      cs : IN STD_LOGIC;
      w : IN std_logic;
      write_address : IN integer range 0 to 4095;
      wdata : IN unsigned(7 DOWNTO 0);
      address : IN integer range 0 to 4095;
      rdata : OUT unsigned(7 DOWNTO 0)
      );
  END component;

  type ethernet_state is (Idle,
                          WaitingForPreamble,
                          ReceivingPreamble,
                          ReceivingFrame,
                          ReceivedFrame,
                          ReceivedFrame2,
                          ReceivedFrameCRC1,
                          ReceivedFrameCRC2,
                          ReceivedFrameCRC3,
                          ReceivedFrameCRC4,
                          BadFrame,

                          WaitBeforeTX,
                          SendingPreamble,
                          SendingFrame,
                          SentFrame
                          );
  signal eth_state : ethernet_state := Idle;
  
  -- control reset line on ethernet controller
  signal eth_reset_int : std_logic := '1';
  -- which half of frame RX buffer is visible
  signal eth_rx_buffer_moby : std_logic := '0';
  -- which half of frame buffer had the most recent frame delivery
  signal eth_rx_buffer_last_used : std_logic := '1';
  signal eth_rx_buffer_last_used_int2 : std_logic := '1';
  signal eth_rx_buffer_last_used_int1 : std_logic := '1';
  signal eth_rx_buffer_last_used_50mhz : std_logic := '1';
  signal eth_rx_crc : unsigned(31 downto 0);
  -- ethernet receiver signals
  signal eth_rxbits : unsigned(5 downto 0);
  signal eth_bit_count : integer range 0 to 6;  
  signal eth_frame_len : integer range 0 to 4095;
  
  signal rxbuffer_cs : std_logic;
  signal rxbuffer_write : std_logic;
  signal rxbuffer_writeaddress : integer range 0 to 4095;
  signal rxbuffer_readaddress : integer range 0 to 4095;
  signal rxbuffer_wdata : unsigned(7 downto 0);

  signal tx_preamble_count : integer range 31 downto 0;
  signal eth_tx_state : ethernet_state := Idle;
  signal eth_tx_bit_count : integer range 0 to 6;
  signal txbuffer_writeaddress : integer range 0 to 4095;
  signal txbuffer_readaddress : integer range 0 to 4095;
  signal txbuffer_write : std_logic := '0';
  signal txbuffer_wdata : unsigned(7 downto 0);
  signal txbuffer_rdata : unsigned(7 downto 0);
  signal eth_tx_bits : unsigned(7 downto 0);
  signal eth_tx_size : unsigned(11 downto 0) := to_unsigned(0,12);
  signal eth_tx_trigger : std_logic := '0';
  signal eth_tx_commenced : std_logic := '0';
  signal eth_tx_complete : std_logic := '0';
  signal eth_txen_int : std_logic;
  signal eth_txd_int : unsigned(1 downto 0) := "00";
  
begin  -- behavioural

  -- Ethernet RMII side clocked at 50MHz
  
  -- See http://ww1.microchip.com/downloads/en/DeviceDoc/8720a.pdf
  
  -- We begin receiving a frame when RX_DV goes high.  Data arrives 2 bits at
  -- a time.  We will manually form this into bytes, and then stuff into RX buffer.
  -- Frame is completely received when RX_DV goes low, or RXER is asserted, in
  -- which case any partially received frame should be discarded.
  -- We will use a 4KB RX buffer split into two 2KB halves, so that the most
  -- recent frame can be read out by the CPU while another frame is being received.
  -- RX buffer is written from ethernet side, so use 50MHz clock.
  -- reads are fully asynchronous, so no need for a read-side clock for the CPU
  -- side.
  rxbuffer0: ram8x4096 port map (
    clk => clock50mhz,
    cs => rxbuffer_cs,
    w => rxbuffer_write,
    write_address => rxbuffer_writeaddress,
    wdata => rxbuffer_wdata,
    address => rxbuffer_readaddress,
    rdata => fastio_rdata);  

  txbuffer0: ram8x4096 port map (
    clk => clock50mhz,
    cs => '1',
    w => txbuffer_write,
    write_address => txbuffer_writeaddress,
    wdata => txbuffer_wdata,
    address => txbuffer_readaddress,
    rdata => txbuffer_rdata);  

  
  -- Look after CPU side of mapping of RX buffer
  process(eth_rx_buffer_moby,fastio_addr,fastio_read) is
  begin
    rxbuffer_readaddress <= to_integer(eth_rx_buffer_moby&fastio_addr(10 downto 0));
    if fastio_read='1' and fastio_addr(19 downto 12) = x"DE"
      and fastio_addr(11)='1' then
      rxbuffer_cs <= '1';
    else
      rxbuffer_cs <= '0';
    end if;
  end process;
  
  process(clock50mhz) is
    variable frame_length : unsigned(11 downto 0);
  begin
    if rising_edge(clock50mhz) then
      -- We separate the RX/TX FSMs to allow true full-duplex operation.
      -- For now it is upto the user to ensure the 96us gap between packets.
      -- This is only 20 CPU cycles, so it is unlikely to be a problem.
      
      -- Ethernet TX FSM
      case eth_tx_state is
        when Idle =>
          if eth_tx_trigger = '1' then
            eth_tx_commenced <= '1';
            eth_tx_complete <= '0';
            tx_preamble_count <= 31;
            eth_txen <= '1';
            eth_txen_int <= '1';
            eth_txd <= "01";
            eth_txd_int <= "01";
            eth_tx_state <= WaitBeforeTX;
          end if;
        when WaitBeforeTX =>
          txbuffer_readaddress <= 0;
          eth_tx_state <= SendingPreamble;
        when SendingPreamble =>
          if tx_preamble_count = 0 then
            eth_txd <= "11";
            eth_txd_int <= "11";
            eth_tx_state <= SendingFrame;
            eth_tx_bit_count <= 0;
            eth_tx_bits <= txbuffer_rdata;
            txbuffer_readaddress <= txbuffer_readaddress + 1;
          else
            eth_txd <= "01";
            eth_txd_int <= "01";
            tx_preamble_count <= tx_preamble_count - 1;
          end if;
        when SendingFrame =>
          eth_txd <= eth_tx_bits(1 downto 0);
          eth_txd_int <= eth_tx_bits(1 downto 0);
          if eth_tx_bit_count = 6 then
            -- Prepare to send from next byte
            eth_tx_bit_count <= 0;
            eth_tx_bits <= txbuffer_rdata;
            if to_unsigned(txbuffer_readaddress,12) /= eth_tx_size then
              txbuffer_readaddress <= txbuffer_readaddress + 1;
            else
              eth_txen <= '0';
              eth_txen_int <= '0';
              eth_tx_state <= SentFrame;
            end if;
          else
            -- Prepare to send next 2 bits next cycle
            eth_tx_bit_count <= eth_tx_bit_count + 2;
            eth_tx_bits <= "00" & eth_tx_bits(7 downto 2);
          end if;
        when SentFrame =>
          -- Wait for eth_tx_trigger to go low
          if eth_tx_trigger='0' then
            eth_tx_complete <= '1';
            eth_tx_commenced <= '0';
            eth_tx_state <= Idle;
          end if;
        when others =>
          eth_tx_state <= Idle;
      end case;
    
      -- Ethernet RX FSM
      frame_length := to_unsigned(eth_frame_len,12);
      case eth_state is
        when Idle =>
          rxbuffer_write <= '0';
          if eth_rxdv='1' then
            -- start receiving frame
            eth_state <= WaitingForPreamble;
            eth_rx_crc <= (others => '0');
            -- Work out where to put received frame.
            -- In all cases, leave 2 bytes to put the frame length first, and
            -- also 4 bytes to put the calculated CRC32.
            if eth_rx_buffer_last_used_50mhz='0' then
              -- last frame was in bottom half, so write to top half ...
              eth_frame_len <= 2054;
            else
              -- ... and vice-versa
              eth_frame_len <= 6;
            end if;
            eth_bit_count <= 0;
          end if;
        when WaitingForPreamble =>
          if eth_rxd = "01" then
            eth_state <= ReceivingPreamble;
          end if;
        when ReceivingPreamble =>
          case eth_rxd is
            when "01" =>
              -- valid preamble bits, keep on going
              null;
            when "11" =>
              -- end of preamble
              eth_state <= ReceivingFrame;
            when others =>
              eth_state <= BadFrame;
          end case;
        when BadFrame =>
          -- Skip to end of a bad frame
          if eth_rxdv='0' then eth_state <= Idle; end if;
        when ReceivingFrame =>
          if eth_rxdv='0' then
            -- finished receiving frame
            -- subtract two length field bytes and four calculated CRC bytes from write address to
            -- obtain actual number of bytes received
            eth_frame_len <= eth_frame_len - 6;
            eth_state <= ReceivedFrame;
          else
            -- got two more bits
            if eth_bit_count = 6 then
              -- this makes a byte
              if frame_length(10 downto 0) = "11111111000" then
                -- frame too long -- ignore the rest
                -- (max frame length = 2048 - 2 length bytes - 4 CRC bytes = 2042 bytes
                null;
              else
                eth_frame_len <= eth_frame_len + 1;
                rxbuffer_write <= '1';
                rxbuffer_wdata <= eth_rxd & eth_rxbits;
                -- update CRC calculation
                eth_rx_crc
                  <= unsigned(nextCRC32_D8(std_logic_vector(eth_rxd & eth_rxbits),
                                           std_logic_vector(eth_rx_crc)));
                rxbuffer_writeaddress <= eth_frame_len;
              end if;
              eth_bit_count <= 0;
            else
              -- shift bits into partial received byte
              eth_bit_count <= eth_bit_count + 2;
              eth_rxbits <= eth_rxd & eth_rxbits(5 downto 2);
            end if;
          end if;
        when ReceivedFrame =>
          -- write low byte of frame length
          if eth_rx_buffer_last_used_50mhz='0' then
            rxbuffer_writeaddress <= 0;
          else
            rxbuffer_writeaddress <= 2048;
          end if;
          rxbuffer_wdata <= frame_length(7 downto 0);
          eth_state <= ReceivedFrame2;
        when ReceivedFrame2 =>
          -- write low byte of frame length
          rxbuffer_writeaddress <= rxbuffer_writeaddress + 1;
          rxbuffer_wdata(7 downto 3) <= "00000";
          rxbuffer_wdata(2 downto 0) <= frame_length(10 downto 8);
          eth_state <= ReceivedFrameCRC1;
        when ReceivedFrameCRC1 =>
          rxbuffer_writeaddress <= rxbuffer_writeaddress + 1;
          rxbuffer_wdata <= eth_rx_crc(7 downto 0);
          eth_state <= ReceivedFrameCRC2;
        when ReceivedFrameCRC2 =>
          rxbuffer_writeaddress <= rxbuffer_writeaddress + 1;
          rxbuffer_wdata <= eth_rx_crc(15 downto 8);
          eth_state <= ReceivedFrameCRC3;
        when ReceivedFrameCRC3 =>
          rxbuffer_writeaddress <= rxbuffer_writeaddress + 1;
          rxbuffer_wdata <= eth_rx_crc(23 downto 16);
          eth_state <= ReceivedFrameCRC4;
        when ReceivedFrameCRC4 =>
          rxbuffer_writeaddress <= rxbuffer_writeaddress + 1;
          rxbuffer_wdata <= eth_rx_crc(31 downto 24);
          
          -- record that we have received a frame
          eth_rx_buffer_last_used_50mhz <= not eth_rx_buffer_last_used_50mhz;
          -- ready to receive another frame
          eth_state <= Idle;
          rxbuffer_write <= '1';
        when others =>
          null;
      end case;
    end if;
  end process;
  
  process (clock,fastio_addr,fastio_wdata,fastio_read,fastio_write
           ) is
    variable temp_cmd : unsigned(7 downto 0);
  begin

    if fastio_read='1' then
      if (fastio_addr(19 downto 8) = x"DE0") then
        case fastio_addr(7 downto 0) is
          -- Registers $00 - $3F map to ethernet MDIO registers

          -- $DE040 - controls reset pin of ethernet controller
          when x"40" =>
            fastio_rdata(7 downto 4) <= (others => 'Z');
            fastio_rdata(3) <= eth_rxdv;
            fastio_rdata(2 downto 1) <= eth_rxd;
            fastio_rdata(0) <= eth_reset_int;
          -- $DE041 - control which half of RX buffer is visible
          -- (unused bits = 0 to allow expansion of number of RX buffer slots
          -- from 2 to something bigger)
          when x"41" =>
            fastio_rdata(7 downto 1) <= (others => '0');
            fastio_rdata(0) <= eth_rx_buffer_moby;
          -- $DE042 - indicate which half of RX buffer most recently
          -- received a frame.  Value is provided by 50MHz side, so has a few
          -- cycles delay.
          when x"42" =>
            fastio_rdata(7 downto 1) <= (others => '0');
            fastio_rdata(0) <= eth_rx_buffer_last_used;
          -- TX Packet size
          when x"43" =>
            fastio_rdata <= eth_tx_size(7 downto 0);
          when x"44" =>
            fastio_rdata(7 downto 4) <= "0000";
            fastio_rdata(3 downto 0) <= eth_tx_size(11 downto 8);
          -- Status of frame transmitter
          when x"45"  =>
            fastio_rdata(0) <= eth_tx_trigger;
            fastio_rdata(1) <= eth_tx_commenced;
            fastio_rdata(2) <= eth_tx_complete;
            fastio_rdata(3) <= eth_txen_int;
            fastio_rdata(5 downto 4) <= eth_txd_int(1 downto 0);
            fastio_rdata(7 downto 6) <= (others => 'Z');
          when others => fastio_rdata <= (others => 'Z');
        end case;
      else
        fastio_rdata <= (others => 'Z');
      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if;

    
    if rising_edge(clock) then

      -- Automatically de-assert transmit trigger once the FSM has caught the signal.
      if eth_tx_commenced = '1' then
        eth_tx_trigger <= '0';
      end if;
      
      -- Bring signals accross from 50MHz side as required
      -- (pass through some flip-flops to manage meta-stability)
      eth_rx_buffer_last_used <= eth_rx_buffer_last_used_int2;
      eth_rx_buffer_last_used_int2 <= eth_rx_buffer_last_used_int1;
      eth_rx_buffer_last_used_int1 <= eth_rx_buffer_last_used_50mhz;      
      
      -- Update module status based on register reads
      if fastio_read='1' then
        if fastio_addr(19 downto 0) = x"DE000" then
          -- If the CPU is reading from this register, then in addition to
          -- reading the register contents asynchronously, do something,
          -- for example, clear an interrupt status, or tell the ethernet
          -- controller that the frame buffer is okay to overwrite.
        end if;
      end if;

      -- Write to registers
      if fastio_write='1' then
        if fastio_addr(19 downto 10)&"00" = x"DE8" then
          -- Writing to TX buffer
          -- (we don't need toclear the write lines, as noone else can write to
          -- the buffer.  The TX buffer cannot be read, as reading the same
          -- addresses reads from the RX buffer.)
          txbuffer_writeaddress <= to_integer(fastio_addr(10 downto 0));
          txbuffer_write <= '1';
          txbuffer_wdata <= fastio_wdata;
        end if;
        if fastio_addr(19 downto 8) = x"DE0" then
          if fastio_addr(7 downto 6) = "00" then
            -- Writing to ethernet controller MD registers
          else
            -- Other registers
            case fastio_addr(7 downto 0) is
              when x"40" => -- reset pin on ethernet controller
                eth_reset <= fastio_wdata(0);
                eth_reset_int <= fastio_wdata(0);
              when x"41" => -- which half of RX buffer is visible
                eth_reset <= fastio_wdata(0);
                eth_reset_int <= fastio_wdata(0);
              when x"42" => -- which half of RX buffer has most recent frame
                null;
              -- Set low-order size of frame to TX
              when x"43" =>
                eth_tx_size(7 downto 0) <= fastio_wdata;
              -- Set high-order size of frame to TX
              when x"44" =>
                eth_tx_size(11 downto 8) <= fastio_wdata(3 downto 0);
              -- Send frame in TX buffer
              when x"45" =>
                if fastio_wdata = x"01" then
                  if eth_tx_commenced='0' then
                    eth_tx_trigger <= '1';
                  end if;
                end if;
              when others =>
                -- Other registers do nothing
                null;
            end case;
          end if;
        end if;
      end if;

      -- Do synchronous actions
      
    end if;
  end process;

end behavioural;
