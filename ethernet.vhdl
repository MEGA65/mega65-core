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
                          ReceivingPacket,
                          ReceivedPacket,ReceivedPacket2
                          );
  signal eth_state : ethernet_state := Idle;
  
  -- control reset line on ethernet controller
  signal eth_reset_int : std_logic := '1';
  -- which half of packet RX buffer is visible
  signal eth_rx_buffer_moby : std_logic := '0';
  -- which half of packet buffer had the most recent packet delivery
  signal eth_rx_buffer_last_used : std_logic := '1';
  signal eth_rx_buffer_last_used_int2 : std_logic := '1';
  signal eth_rx_buffer_last_used_int1 : std_logic := '1';
  signal eth_rx_buffer_last_used_50mhz : std_logic := '1';
  -- ethernet receiver signals
  signal eth_rxbits : unsigned(5 downto 0);
  signal eth_bit_count : integer range 0 to 6;  
  signal eth_packet_len : integer range 0 to 4095;
  
  signal rxbuffer_cs : std_logic;
  signal rxbuffer_write : std_logic;
  signal rxbuffer_writeaddress : integer range 0 to 4095;
  signal rxbuffer_readaddress : integer range 0 to 4095;
  signal rxbuffer_wdata : unsigned(7 downto 0);

begin  -- behavioural

  -- Ethernet RMII side clocked at 50MHz
  
  -- See http://ww1.microchip.com/downloads/en/DeviceDoc/8720a.pdf
  
  -- We begin receiving a packet when RX_DV goes high.  Data arrives 2 bits at
  -- a time.  We will manually form this into bytes, and then stuff into RX buffer.
  -- Frame is completely received when RX_DV goes low, or RXER is asserted, in
  -- which case any partially received packet should be discarded.
  -- We will use a 4KB RX buffer split into two 2KB halves, so that the most
  -- recent packet can be read out by the CPU while another packet is being received.
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

  -- Look after CPU side of mapping of RX buffer
  process(eth_rx_buffer_moby,fastio_addr,fastio_read) is
  begin
    rxbuffer_readaddress <= to_integer(eth_rx_buffer_moby&fastio_addr(10 downto 0));
    if fastio_read='1' and fastio_addr(19 downto 12) = x"DE0"
      and fastio_addr(11)='1' then
      rxbuffer_cs <= '1';
    else
      rxbuffer_cs <= '0';
    end if;
  end process;
  
  process(clock50mhz) is
    variable packet_length : unsigned(11 downto 0);
  begin
    if rising_edge(clock50mhz) then
      packet_length := to_unsigned(eth_packet_len,12);
      case eth_state is
        when Idle =>
          rxbuffer_write <= '0';
          if eth_rxdv='1' then
            -- start receiving packet
            eth_state <= ReceivingPacket;
            if eth_rx_buffer_last_used_50mhz='0' then
              -- last packet was in bottom half, so write to top half ...
              eth_packet_len <= 2048;
            else
              -- ... and vice-versa
              eth_packet_len <= 0;
            end if;
            eth_bit_count <= 2;
            eth_rxbits(1 downto 0) <= eth_rxd;
          end if;
        when ReceivingPacket =>
          if eth_rxdv='0' then
            -- finished receiving packet
            eth_state <= ReceivedPacket;
          else
            -- got two more bits
            if eth_bit_count = 6 then
              -- this makes a byte
              if packet_length(10 downto 0) = "11111111101" then
                -- packet too long -- ignore the rest
                -- (max packet length = 2048 - 2 length bytes = 2046 bytes
                null;
              else
                eth_packet_len <= eth_packet_len + 1;
                rxbuffer_wdata <= eth_rxbits & eth_rxd;
                rxbuffer_writeaddress <= eth_packet_len;
              end if;
              eth_bit_count <= 0;
            else
              -- shift bits into partial received byte
              eth_bit_count <= eth_bit_count + 2;
              eth_rxbits <= eth_rxbits(3 downto 0) & eth_rxd;
            end if;
          end if;
        when ReceivedPacket =>
          -- write low byte of packet length
          if eth_rx_buffer_last_used_50mhz='0' then
            rxbuffer_writeaddress <= 2046;
          else
            rxbuffer_writeaddress <= 4094;
          end if;
          rxbuffer_wdata <= packet_length(7 downto 0);
          eth_state <= ReceivedPacket2;
        when ReceivedPacket2 =>
          -- write low byte of packet length
          if eth_rx_buffer_last_used_50mhz='0' then
            rxbuffer_writeaddress <= 2047;
          else
            rxbuffer_writeaddress <= 4095;
          end if;
          rxbuffer_wdata(7 downto 3) <= "00000";
          rxbuffer_wdata(2 downto 0) <= packet_length(10 downto 8);
          -- record that we have received a packet
          eth_rx_buffer_last_used_50mhz <= not eth_rx_buffer_last_used_50mhz;
          -- ready to receive another packet
          eth_state <= Idle;
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
            fastio_rdata(7 downto 1) <= (others => 'Z');
            fastio_rdata(0) <= eth_reset_int;
          -- $DE041 - control which half of RX buffer is visible
          -- (unused bits = 0 to allow expansion of number of RX buffer slots
          -- from 2 to something bigger)
          when x"41" =>
            fastio_rdata(7 downto 1) <= (others => '0');
            fastio_rdata(0) <= eth_rx_buffer_moby;
          -- $DE042 - indicate which half of RX buffer most recently
          -- received a packet.  Value is provided by 50MHz side, so has a few
          -- cycles delay.
          when x"42" =>
          
          when others => fastio_rdata <= (others => 'Z'); end case; else
          fastio_rdata <= (others => 'Z'); end if; else fastio_rdata <=
          (others => 'Z'); end if;

    
    if rising_edge(clock) then

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
          -- controller that the packet buffer is okay to overwrite.
        end if;
      end if;

      -- Write to registers
      if fastio_write='1' then
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
              when x"42" => -- which half of RX buffer has most recent packet
                null;
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
