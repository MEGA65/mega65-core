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

-- Portions derived from:
--------------------------------------------------------------------------------
-- ETHERNET RECEIVE
-- Receives data from the ethernet PHY device.
--           
-- @author         Peter A Bennett
-- @copyright      (c) 2012 Peter A Bennett
-- @version        $Rev: 2 $
-- @lastrevision   $Date: 2012-03-11 15:19:25 +0000 (Sun, 11 Mar 2012) $
-- @license        LGPL      
-- @email          pab850@googlemail.com
-- @contact        www.bytebash.com
--
--------------------------------------------------------------------------------

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
    irq : out std_logic := 'Z';

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
    fastio_rdata : out unsigned(7 downto 0);

    ---------------------------------------------------------------------------
    -- compressed video stream from the VIC-IV frame packer for autonomous dispatch
    ---------------------------------------------------------------------------    
    buffer_moby_toggle : in std_logic;
    buffer_address : out unsigned(11 downto 0);
    buffer_rdata : in unsigned(7 downto 0);

    ---------------------------------------------------------------------------
    -- keyboard event capture via ethernet
    ---------------------------------------------------------------------------    
    eth_keycode_toggle : out std_logic;
    eth_keycode : out unsigned(15 downto 0)

    );
end ethernet;

architecture behavioural of ethernet is

 TYPE byte_array_10 IS ARRAY (0 to 9) OF unsigned(7 downto 0);
 constant keyinput_magic : byte_array_10 := (
   -- Magic 10 byte sequence which if it appears at offset 100 in an ethernet
   -- frame, and remote head is enabled, then pretend read a keyboard scan code
   -- to pass to the PS2 keyboard input logic to simulate a key press/release
   -- event.
   x"65",x"47",x"53", -- 65 G S
   x"4b",x"45",x"59", -- KEY
   x"43",x"4f",x"44",x"45" -- CODE
   );
  
 TYPE byte_array_86 IS ARRAY (1 to 85) OF std_logic_vector(7 downto 0);
 CONSTANT video_packet_header : byte_array_86 := (
   -- Ethernet header
   x"ff",x"ff",x"ff",x"ff",x"ff", -- ethernet destination (first byte
                                  -- gets sent elsewhere)
   x"00",x"00",x"00",x"00",x"00",x"00", -- ethernet source
   x"86",x"dd",  -- ethernet type: IPv6
   -- IPv6 header
   x"60", -- version and traffic class high nybl
   x"00",x"00",x"00", -- traffic class low nybl and flow label
   x"08",x"00",  -- payload length (2048 bytes)
   x"00", -- next header (blank for now)
   x"01", -- hop limit: local
   -- ipv6 source address
   x"fe",x"80",x"00",x"00",x"00",x"00",x"00",x"00",
   x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
   x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
   x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
   -- ipv6 destination address
   x"ff",x"10",x"00",x"00",x"00",x"00",x"00",x"00",
   x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
   x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
   x"00",x"00",x"65",x"65",x"65",x"65",x"65",x"65"
   );
  
 component CRC is
    Port 
    (  
      CLOCK               :   in  std_logic;
      RESET               :   in  std_logic;
      DATA                :   in  std_logic_vector(7 downto 0);
      LOAD_INIT           :   in  std_logic;
      CALC                :   in  std_logic;
      D_VALID             :   in  std_logic;
      CRC                 :   out std_logic_vector(7 downto 0);
      CRC_REG             :   out std_logic_vector(31 downto 0);
      CRC_VALID           :   out std_logic
    );
  end component CRC;
  
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
                          DebugRxFrameWait,DebugRxFrame,DebugRxFrameDone,
                          SkippingFrame,
                          WaitingForPreamble,
                          ReceivingPreamble,
                          ReceivingFrame,
                          ReceivedFrame,
                          ReceivedFrame2,
                          BadFrame,

                          IdleWait,
                          Interpacketgap,
                          WaitBeforeTX,
                          SendingPreamble,
                          SendingFrame,
                          SendFCS,
                          SentFrame
                          );
  signal eth_state : ethernet_state := Idle;

  signal eth_mac : unsigned(47 downto 0) := x"024753656565";

  type cs8900aTXstate is (Idle,CommandSet,Buffering);
  signal rrnet_tx_state : cs8900aTXstate := Idle;
  signal rrnet_reading_bus_status : std_logic;
  signal rrnet_debug : unsigned(7 downto 0) := x"00";
  signal rrnet_tx_toggle : std_logic := '0';
  signal rrnet_enable : std_logic := '0';
  signal rrnet_dup_read : std_logic := '0';
  signal rrnet_buffer_write_pending : std_logic := '0';
  signal rrnet_buffer_odd_written : std_logic := '0';
  signal rrnet_buffer_even_written : std_logic := '0';
  signal rrnet_buffer_addr_bump : std_logic := '0';
  signal rrnet_buffer_data : unsigned(7 downto 0) := x"00";
  signal rrnet_buffer_odd : std_logic := '0';
  signal rrnet_notice_data_read : std_logic := '0';
  signal rrnet_addr : unsigned(15 downto 0) := (others => '0');
  signal rrnet_data : unsigned(15 downto 0) := (others => '0');
  signal rrnet_eeprom_data : unsigned(15 downto 0) := (others => '0');
  signal rrnet_readaddress : integer range 0 to 4095 := 0;
  signal rrnet_txbuffer_addr : unsigned(15 downto 0) := (others => '0');
  signal rrnet_advance_buffer : std_logic := '0';
  signal rrnet_buffer_rdata : unsigned(7 downto 0);
  signal rrnet_data_odd : unsigned(7 downto 0);
  signal rrnet_data_even : unsigned(7 downto 0);
  signal rrnet_read_odd : std_logic := '0';
  signal rrnet_read_even : std_logic := '0';
 
  signal rx_keyinput : std_logic := '0';
  signal eth_keycode_toggle_internal : std_logic := '0';
 
  signal last_buffer_moby_toggle : std_logic := '0';
 
  -- If asserted, collect raw signals for exactly one frame, then do nothing.
  signal debug_rx : std_logic := '0';
 
  -- control reset line on ethernet controller
  signal eth_reset_int : std_logic := '1';
  -- which half of frame RX buffer is visible
  signal eth_rx_buffer_moby : std_logic := '0';
  signal eth_rx_buffer_moby_int1 : std_logic := '0';
  signal eth_rx_buffer_moby_int2 : std_logic := '0';
  signal eth_rx_buffer_moby_50mhz : std_logic := '0';
  -- which half of frame buffer had the most recent frame delivery
  signal eth_rx_buffer_last_used_48mhz : std_logic := '1';
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

  signal eth_tx_toggle_48mhz : std_logic := '1';
  signal eth_tx_toggle : std_logic := '1';
  signal eth_tx_toggle_int2 : std_logic := '1';
  signal eth_tx_toggle_int1 : std_logic := '1';
  signal eth_tx_toggle_50mhz : std_logic := '1';
  signal tx_preamble_count : integer range 31 downto 0;
  signal eth_tx_state : ethernet_state := Idle;
  signal eth_tx_bit_count : integer range 0 to 6;
  signal eth_tx_viciv : std_logic := '0';
  signal txbuffer_writeaddress : integer range 0 to 4095;
  signal txbuffer_readaddress : integer range 0 to 4095;
  signal txbuffer_write : std_logic := '0';
  signal txbuffer_wdata : unsigned(7 downto 0);
  signal txbuffer_rdata : unsigned(7 downto 0);
  signal eth_tx_bits : unsigned(7 downto 0);
  signal eth_tx_size : unsigned(11 downto 0) := to_unsigned(98,12);
  signal eth_tx_size_padded : unsigned(11 downto 0) := to_unsigned(98,12);
  signal eth_tx_padding : std_logic := '0';
  signal eth_tx_trigger : std_logic := '0';
  signal eth_tx_commenced : std_logic := '0';
  signal eth_tx_complete : std_logic := '0';
  signal eth_txen_int : std_logic;
  signal eth_txd_int : unsigned(1 downto 0) := "00";
  signal eth_tx_wait : integer range 0 to 50;
 
  signal eth_tx_crc_count : integer range 0 to 16;
  signal eth_tx_crc_bits : std_logic_vector(31 downto 0) := (others => '0');
 
 -- CRC
  signal  rx_fcs_crc_data_in       : std_logic_vector(7 downto 0)  := (others => '0');
  signal  rx_fcs_crc_load_init     : std_logic := '0';
  signal  rx_fcs_crc_calc_en       : std_logic := '0';
  signal  rx_fcs_crc_d_valid       : std_logic := '0';
  signal  rx_crc_valid             : std_logic := '0';
  signal  rx_crc_reg               : std_logic_vector(31 downto 0) := (others => '0');
  signal  tx_fcs_crc_data_in       : std_logic_vector(7 downto 0)  := (others => '0');
  signal  tx_fcs_crc_load_init     : std_logic := '0';
  signal  tx_fcs_crc_calc_en       : std_logic := '0';
  signal  tx_fcs_crc_d_valid       : std_logic := '0';
  signal  tx_crc_valid             : std_logic := '0';
  signal  tx_crc_reg               : std_logic_vector(31 downto 0) := (others => '0');

 -- IRQ flag handling stuff
 signal eth_irqenable_rx : std_logic := '0';
 signal eth_irqenable_tx : std_logic := '0';
 signal eth_irq_rx : std_logic := '0';
 signal eth_irq_tx : std_logic := '0'; 

 signal eth_videostream : std_logic := '0';
 signal eth_byte_100 : unsigned(7 downto 0) := x"bd";
 signal eth_key_debug : unsigned(7 downto 0) := x"00";
 signal eth_byte_fail : unsigned(7 downto 0) := x"00";
 signal eth_offset_fail : unsigned(7 downto 0) := x"00";
 
 -- Reverse the input vector.
 function reversed(slv: std_logic_vector) return std_logic_vector is
   variable result: std_logic_vector(slv'reverse_range);
 begin
   for i in slv'range loop
     result(i) := slv(i);
   end loop;
   return result;
 end reversed;
 
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

  rrnet_rxbuffer: ram8x4096 port map (
    clk => clock50mhz,
    cs => '1',
    w => rxbuffer_write,
    write_address => rxbuffer_writeaddress,
    wdata => rxbuffer_wdata,
    address => rrnet_readaddress,
    rdata => rrnet_buffer_rdata);
  
  txbuffer0: ram8x4096 port map (
    clk => clock50mhz,
    cs => '1',
    w => txbuffer_write,
    write_address => txbuffer_writeaddress,
    wdata => txbuffer_wdata,
    address => txbuffer_readaddress,
    rdata => txbuffer_rdata);  

  rx_CRC : CRC
    port map(
      CLOCK           => clock50mhz,
      RESET           => '0',
      DATA            => rx_fcs_crc_data_in,
      LOAD_INIT       => rx_fcs_crc_load_init,
      CALC            => rx_fcs_crc_calc_en,
      D_VALID         => rx_fcs_crc_d_valid,
      CRC             => open,
      CRC_REG         => rx_crc_reg,
      CRC_VALID       => rx_crc_valid
      );
  
  tx_CRC : CRC
    port map(
      CLOCK           => clock50mhz,
      RESET           => '0',
      DATA            => tx_fcs_crc_data_in,
      LOAD_INIT       => tx_fcs_crc_load_init,
      CALC            => tx_fcs_crc_calc_en,
      D_VALID         => tx_fcs_crc_d_valid,
      CRC             => open,
      CRC_REG         => tx_crc_reg,
      CRC_VALID       => tx_crc_valid
      );
  
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
      -- For now it is upto the user to ensure the 0.96us gap between packets.
      -- This is only 20 CPU cycles, so it is unlikely to be a problem.

      -- Let 50MHz side know which buffer the CPU is looking at.
      eth_rx_buffer_moby_int1 <= eth_rx_buffer_moby;
      eth_rx_buffer_moby_int2 <= eth_rx_buffer_moby_int1;
      eth_rx_buffer_moby_50mhz <= eth_rx_buffer_moby_int2;
      
      -- Ethernet TX FSM
      case eth_tx_state is
        when IdleWait =>
          -- Wait for 0.96usec before allowing transmission of next frame.
          -- We are operating on the 50MHz ethernet clock, so 96usec =
          -- 0.96 * 50 = 48 cycles.  We will wait 50 just to be sure.

          -- make sure we release the transceiver.
          eth_txen <= '0';

          eth_tx_wait <= 50;
          eth_tx_state <= InterPacketGap;
        when InterPacketGap =>
          -- Count down the inter-packet gap
          if eth_tx_wait = 0 then
            eth_tx_state <= Idle;
            eth_tx_complete <= '0';
          else
            eth_tx_wait <= eth_tx_wait - 1;
          end if;
        when Idle =>
          if eth_tx_trigger = '1' then
            -- reset frame padding state
            eth_tx_padding <= '0';
            if to_integer(eth_tx_size)<60 then
              eth_tx_size_padded <= to_unsigned(60,12);
            else
              eth_tx_size_padded <= eth_tx_size;
            end if;
            -- begin transmission
            eth_tx_commenced <= '1';
            eth_tx_complete <= '0';
            tx_preamble_count <= 29;
            eth_txen <= '1';
            eth_txen_int <= '1';
            eth_txd <= "01";
            eth_txd_int <= "01";
            eth_tx_state <= WaitBeforeTX;
            eth_tx_viciv <= '0';
          elsif (eth_videostream='1') and (buffer_moby_toggle /= last_buffer_moby_toggle) then            
            -- start sending an IPv6 multicast packet containing the compressed
            -- video.
            report "FRAMEPACKER: Sending next packet ("
              & std_logic'image(buffer_moby_toggle) & " vs " &
              std_logic'image(last_buffer_moby_toggle) & ")"
              severity note;
            last_buffer_moby_toggle <= buffer_moby_toggle;
            buffer_address <= (not buffer_moby_toggle) & "00000000000";
            eth_tx_commenced <= '1';
            eth_tx_complete <= '0';
            tx_preamble_count <= 29;
            eth_txen <= '1';
            eth_txen_int <= '1';
            eth_txd <= "01";
            eth_txd_int <= "01";
            eth_tx_state <= WaitBeforeTX;
            eth_tx_viciv <= '1';
          end if;
        when WaitBeforeTX =>
          txbuffer_readaddress <= 0;
          eth_tx_state <= SendingPreamble;
          tx_fcs_crc_load_init <= '1';
        when SendingPreamble =>
          if tx_preamble_count = 0 then
            eth_txd <= "11";
            eth_txd_int <= "11";
            eth_tx_state <= SendingFrame;
            eth_tx_bit_count <= 0;
            txbuffer_readaddress <= txbuffer_readaddress + 1;
            tx_fcs_crc_load_init <= '0';
            tx_fcs_crc_d_valid <= '1';
            tx_fcs_crc_calc_en <= '1';
            if eth_tx_viciv='0' then
              eth_tx_bits <= txbuffer_rdata;
              tx_fcs_crc_data_in <= std_logic_vector(txbuffer_rdata);
            else
              eth_tx_bits <= x"ff";
              tx_fcs_crc_data_in <= x"ff";
            end if;
          else
            eth_txd <= "01";
            eth_txd_int <= "01";
            tx_preamble_count <= tx_preamble_count - 1;
          end if;
        -- when SendingVicIVVideoPacketHeader =>
        --   send (mostly) constant ethernet + IPv6 header
        --   Then send 2,048 bytes of data.
        --   eth_tx_state <= SendingFrame
        when SendingFrame =>
          tx_fcs_crc_d_valid <= '0';
          tx_fcs_crc_calc_en <= '0';
          eth_txd <= eth_tx_bits(1 downto 0);
          eth_txd_int <= eth_tx_bits(1 downto 0);
          if eth_tx_bit_count = 6 then
            -- Prepare to send from next byte
            eth_tx_bit_count <= 0;
            tx_fcs_crc_d_valid <= '1';
            tx_fcs_crc_calc_en <= '1';
            if eth_tx_viciv='0' then
              if eth_tx_padding = '1' then
               report "PADDING: writing padding byte @ "
                 & integer'image(txbuffer_readaddress);
                tx_fcs_crc_data_in <= x"00";
                eth_tx_bits <= x"00";
              else
                report "PADDING: writing actual byte $"
                  & to_hstring(txbuffer_rdata) & 
                  " @ "
                  & integer'image(txbuffer_readaddress);
                eth_tx_bits <= txbuffer_rdata;
                tx_fcs_crc_data_in <= std_logic_vector(txbuffer_rdata);
              end if;
            else
              if txbuffer_readaddress < video_packet_header'length then
                report "FRAMEPACKER: Sending packet header byte " & integer'image(txbuffer_readaddress) & " = $" & to_hstring(unsigned(video_packet_header(txbuffer_readaddress)));
                eth_tx_bits <= unsigned(video_packet_header(txbuffer_readaddress));
                tx_fcs_crc_data_in <= video_packet_header(txbuffer_readaddress);
              else
                report "FRAMEPACKER: Sending compressed video byte " & integer'image(txbuffer_readaddress - video_packet_header'length) & " = $" & to_hstring(buffer_rdata);
                eth_tx_bits <= buffer_rdata;
                tx_fcs_crc_data_in <= std_logic_vector(buffer_rdata);
              end if;
            end if;

            if ((eth_tx_viciv='0')
                and (to_unsigned(txbuffer_readaddress,12) /= eth_tx_size_padded))
              or
              ((eth_tx_viciv='1')
                and (to_unsigned(txbuffer_readaddress,12) /=
                     (2048 + video_packet_header'length - 1)))
            then
              txbuffer_readaddress <= txbuffer_readaddress + 1;
              if txbuffer_readaddress = eth_tx_size then
                eth_tx_padding <= '1';
              end if;
              -- For VIC-IV compressed video frames work out address.
              -- We have an 86 byte packet header
              if txbuffer_readaddress >= video_packet_header'length then
                if last_buffer_moby_toggle = '1' then
                  -- Reading from upper half
                  buffer_address <= to_unsigned(txbuffer_readaddress
                                                - video_packet_header'length,12);
                else
                  -- Reading from lower half
                  buffer_address <= to_unsigned(txbuffer_readaddress + 2048
                                                - video_packet_header'length,12);
                end if;
              else
                buffer_address <= to_unsigned(0,12);
              end if;
            else
              -- Now send TX FCS, value will be in tx_crc_reg, send
              -- high-order bytes first (but low-order bits first).
              -- This requires some bit munging.
              eth_tx_state <= SendFCS;
              eth_tx_crc_bits <= not (tx_crc_reg(31 downto 24)
                                      & tx_crc_reg(23 downto 16)
                                      & tx_crc_reg(15 downto 8)
                                      & tx_crc_reg(7 downto 0));
              report "ETHTX: CRC = $" & to_hstring(tx_crc_reg);
              eth_tx_crc_count <= 16;
            end if;
          else
            -- Prepare to send next 2 bits next cycle
            eth_tx_bit_count <= eth_tx_bit_count + 2;
            eth_tx_bits <= "00" & eth_tx_bits(7 downto 2);
          end if;
        when SendFCS =>
          report "ETHTX: writing FCS";
          if eth_tx_crc_count /= 0 then
            eth_txd(0) <= eth_tx_crc_bits(31);
            eth_txd(1) <= eth_tx_crc_bits(30);
            eth_txd_int <= unsigned(eth_tx_crc_bits(31 downto 30));
            eth_tx_crc_bits(31 downto 2) <= eth_tx_crc_bits(29 downto 0);
            eth_tx_crc_count <= eth_tx_crc_count - 1;
          else
            eth_txen <= '0';
            eth_txen_int <= '0';
            eth_tx_state <= SentFrame;
            eth_tx_toggle_50mhz <= not eth_tx_toggle_50mhz;
          end if;
        when SentFrame =>
          -- Wait for eth_tx_trigger to go low, unless it is
          -- a VIC-IV video frame, in which case immediately clear.
          eth_tx_complete <= '1';
          if eth_tx_trigger='0' or eth_tx_viciv = '1' then
            eth_tx_commenced <= '0';
            eth_tx_state <= IdleWait;
          end if;
        when others =>
          eth_tx_state <= IdleWait;
      end case;
    
      -- Ethernet RX FSM
      frame_length := to_unsigned(eth_frame_len,12);
      case eth_state is
        when Idle =>
          if debug_rx = '1' then
            eth_frame_len <= 0;
            eth_state <= DebugRxFrameWait;
          end if;
          rx_keyinput <= '1';
          rxbuffer_write <= '0';
          if eth_rxdv='1' then
            -- start receiving frame
            report "CRC: Frame carrier detected";
            eth_state <= WaitingForPreamble;
            rx_fcs_crc_load_init <= '1';
            rx_fcs_crc_d_valid <= '0';
            -- Work out where to put received frame.
            -- In all cases, leave 2 bytes to put the frame length first.
            if eth_rx_buffer_last_used_50mhz='0' then
              -- last frame was in bottom half, so write to top half ...
              eth_frame_len <= 2050;
            else
              -- ... and vice-versa
              eth_frame_len <= 2;
            end if;
            eth_bit_count <= 0;
            -- Veto packet reception if the CPU is watching the buffer we were
            -- going to write to.
            if eth_rx_buffer_last_used_50mhz /= eth_rx_buffer_moby_50mhz then
              eth_state <= SkippingFrame;
            end if;
          end if;
        when SkippingFrame =>
          -- Wait until RX frame stops 
          if eth_rxdv='0' then
             eth_state <= Idle;
          end if;
        when DebugRxFrameWait =>
          if debug_rx = '0' then
            eth_state <= Idle;
          end if;
          if eth_rxdv='1' then
            eth_state <= DebugRxFrame;
          end if;
        when DebugRxFrame =>
          rxbuffer_writeaddress <= eth_frame_len;
          rxbuffer_write <= '1';
          rxbuffer_wdata <= x"00";
          rxbuffer_wdata(7) <= eth_rxdv;
          rxbuffer_wdata(6) <= eth_rxer;
          rxbuffer_wdata(5) <= eth_interrupt;
          rxbuffer_wdata(1 downto 0) <= eth_rxd;
          eth_frame_len <= eth_frame_len + 1;
          if eth_frame_len = 2047 then
            eth_state <= DebugRxFrameDone;
          end if;
        when DebugRxFrameDone =>
          if debug_rx = '0' then
            eth_state <= Idle;
          end if;
        when WaitingForPreamble =>
          rx_fcs_crc_load_init <= '0';
          if eth_rxd = "01" then
            report "ETHRX: Preamble has started";
            eth_state <= ReceivingPreamble;
          end if;
        when ReceivingPreamble =>
          case eth_rxd is
            when "01" =>
              -- valid preamble bits, keep on going
              null;
            when "11" =>
              -- end of preamble
              report "ETHRX: Found end of preamble, expecting data to follow";
              eth_state <= ReceivingFrame;
            when others =>
              report "CRC: Rejecting frame due to junk in preamble";
              eth_state <= BadFrame;
          end case;
        when BadFrame =>
          -- Skip to end of a bad frame
          if eth_rxdv='0' then eth_state <= Idle; end if;
        when ReceivingFrame =>
          rx_fcs_crc_d_valid <= '0';
          rx_fcs_crc_calc_en <= '0';
          if eth_rxdv='0' then
            report "ETHRX: Ethernet carrier has stopped.";
            -- finished receiving frame
            -- subtract two length field bytes to
            -- obtain actual number of bytes received
            eth_frame_len <= eth_frame_len - 2;
            eth_state <= ReceivedFrame;
            -- put a marker at the end of the frame so we can see where it stops in
            -- the RX buffer.
            rxbuffer_write <= '1';
            rxbuffer_wdata <= x"BD";
            rxbuffer_writeaddress <= eth_frame_len;
          else
            -- got two more bits
            report "ETHRX: Received bits from RMII: "
              & to_string(std_logic_vector(eth_rxd));
            if eth_bit_count = 6 then
              -- this makes a byte
              if frame_length(10 downto 0) = "11111111000" then
                -- frame too long -- ignore the rest
                -- (max frame length = 2048 - 2 length bytes - 4 CRC bytes = 2042 bytes
                null;
              else
                eth_frame_len <= eth_frame_len + 1;
                rxbuffer_write <= '1';
                report "ETHRX: Received byte $" & to_hstring(eth_rxd & eth_rxbits);
                rxbuffer_wdata <= eth_rxd & eth_rxbits;
                rxbuffer_writeaddress <= eth_frame_len;

                -- Look for magic keyboard input frames
                report "PS2KEYBOARD: packet offset " & integer'image(to_integer(frame_length(10 downto 0)));
                if to_integer(frame_length(10 downto 0))>=100
                  and to_integer(frame_length(10 downto 0))<110 then
                  if keyinput_magic(to_integer(frame_length(10 downto 0))-100) /= eth_rxd & eth_rxbits then
                    rx_keyinput <= '0';
                    eth_byte_fail(7 downto 6) <= eth_rxd;
                    eth_byte_fail(5 downto 0) <= eth_rxbits;
                    eth_offset_fail <= frame_length(7 downto 0);
                    report "PS2KEYBOARD: packet verification check failed at offset " & integer'image(to_integer(frame_length(10 downto 0)));
                    report "PS2KEYBOARD: expected $" &
                       to_hstring(keyinput_magic(to_integer(frame_length(10 downto 0))-100))
                    &", but saw $" & to_hstring(eth_rxd & eth_rxbits);
                  end if;
                end if;
                if rx_keyinput='1' and eth_videostream='1' then
                  if to_integer(frame_length(10 downto 0)) = 110 then
                    eth_keycode(7 downto 0) <= eth_rxd & eth_rxbits;
                  end if;
                  if to_integer(frame_length(10 downto 0)) = 111 then
                    eth_keycode(15 downto 8) <= eth_rxd & eth_rxbits;
                    eth_keycode_toggle <= not eth_keycode_toggle_internal;
                    eth_keycode_toggle_internal <= not eth_keycode_toggle_internal;
                    report "PS2KEYBOARD: read keyboard scan code from ethernet";
                  end if;
                else
                  if to_integer(frame_length(10 downto 0)) = 110 then
                    report "PS2KEYBOARD: rx_keyinput=" & std_logic'image(rx_keyinput)
                      &", eth_videostream=" & std_logic'image(eth_videostream);
                  end if;
                end if;
                -- help debug ethernet key reception by making 100th byte visible
                if to_integer(frame_length(10 downto 0)) = 100 then
                  eth_byte_100 <= eth_rxd & eth_rxbits;
                  eth_key_debug(1) <= rx_keyinput;
                  eth_key_debug(0) <= eth_videostream;
                end if;
                
                -- update CRC calculation
                rx_fcs_crc_data_in <= std_logic_vector(eth_rxd) & std_logic_vector(eth_rxbits);
                rx_fcs_crc_d_valid <= '1';
                rx_fcs_crc_calc_en <= '1';
              end if;
              eth_bit_count <= 0;
            else
              -- shift bits into partial received byte
              eth_bit_count <= eth_bit_count + 2;
              eth_rxbits <= eth_rxd & eth_rxbits(5 downto 2);
            end if;
          end if;
        when ReceivedFrame =>
          rx_fcs_crc_d_valid <= '0';
          rx_fcs_crc_calc_en <= '0';
          -- write low byte of frame length
          if eth_rx_buffer_last_used_50mhz='0' then
            rxbuffer_writeaddress <= 2048;
          else
            rxbuffer_writeaddress <= 0;
          end if;
          rxbuffer_write <= '1';
          rxbuffer_wdata <= frame_length(7 downto 0);
          report "ETHRX: writing frame_length(7 downto 0) = $" & to_hstring(frame_length);
          eth_state <= ReceivedFrame2;
        when ReceivedFrame2 =>
          -- write high byte of frame length + crc failure status
          -- bit 7 is high if CRC fails, else is low.
          report "ETHRX: writing packet length at " & integer'image(rxbuffer_writeaddress);
          report "ETHRX: Recording crc_valid = " & std_logic'image(rx_crc_valid) & "   (CRC = $"& to_hstring(rx_crc_reg)&")";
          rxbuffer_writeaddress <= rxbuffer_writeaddress + 1;
          rxbuffer_wdata(7) <= not rx_crc_valid;
          rxbuffer_wdata(6 downto 3) <= "0000";
          rxbuffer_wdata(2 downto 0) <= frame_length(10 downto 8);
          if rx_crc_valid='1' then
            -- record that we have received a frame, but only if there was no
            -- CRC error.
            report "ETHRX: Toggling eth_rx_buffer_last_used_50mhz";
            eth_rx_buffer_last_used_50mhz <= not eth_rx_buffer_last_used_50mhz;
          end if;
          -- ready to receive another frame
          eth_state <= Idle;
        when others =>
          null;
      end case;
    end if;
  end process;
  
  process (clock,fastio_addr,fastio_wdata,fastio_read,fastio_write
           ) is
    variable temp_cmd : unsigned(7 downto 0);

    procedure rrnet_txcmd_set is
    begin
      -- According to the cs8900a data sheet:
      -- When the TX CMD has been set, we just clear the buffer pointers ready
      -- to receive the frame.  The user must then set the tx length, and then
      -- read from the bus status register before transmission is primed.
      -- Once primed, the bytes must then be written.  As soon as enough bytes
      -- are written, the frame will then start to be sent.

      -- We will implement this as clearing things when the tx cmd is seen, not
      -- buffer bytes until the bus status has been read, and then only transmit
      -- the frame once the right number of bytes have been buffered.  We will
      -- use the existing ethernet TX buffer.
      
      rrnet_txbuffer_addr <= (others => '0');
      rrnet_tx_state <= CommandSet;
      report "ETHBUFFERING: State moving to CommandSet";
    end procedure;
    
  begin

    if fastio_read='1' then
      report "MEMORY: Reading from fastio";

      -- RR-NET emulation
      if fastio_addr = x"D0E02" and rrnet_enable='1' then
        fastio_rdata <= rrnet_addr(7 downto 0);        
      elsif fastio_addr = x"D0E03" and rrnet_enable='1' then
        fastio_rdata <= rrnet_addr(15 downto 8);
      elsif rrnet_enable='1' and fastio_addr=x"D0E04" then
        -- @IO:GS RR-NET emulation: cs_packet_data low
        fastio_rdata <= rrnet_data(7 downto 0);
        if rrnet_reading_bus_status = '1' then
          if rrnet_tx_state = CommandSet then
            report "ETHBUFFERING: Switching from CommandSet to Buffering";
            rrnet_tx_state <= Buffering;
          end if;
        end if;
      elsif rrnet_enable='1' and fastio_addr=x"D0E05" then
        -- @IO:GS RR-NET emulation: cs_packet_data high
        report "MEMORY: Reading RR-NET reg high = $" & to_hstring(rrnet_data(15 downto 8));
        fastio_rdata <= rrnet_data(15 downto 8);
        if rrnet_reading_bus_status = '1' then
          if rrnet_tx_state = CommandSet then
            report "ETHBUFFERING: Switching from CommandSet to Buffering";
            rrnet_tx_state <= Buffering;
          end if;
        end if;
      elsif rrnet_enable='1' and fastio_addr=x"D0E08" then
        -- cs_rxtx_data low
        fastio_rdata <= rrnet_data_even;
      elsif rrnet_enable='1' and fastio_addr=x"D0E09" then
        -- cs_rxtx_data high
        fastio_rdata <= rrnet_data_odd;
      elsif rrnet_enable='1' and fastio_addr=x"D0E0C" then
        -- cs_tx_cmd low
      elsif rrnet_enable='1' and fastio_addr=x"D0E0D" then
        -- cs_tx_cmd high
      elsif rrnet_enable='1' and fastio_addr=x"D0E0E" then
        -- cs_tx_len low
      elsif rrnet_enable='1' and fastio_addr=x"D0E0F" then
        -- cs_tx_len high
        
      elsif (fastio_addr(19 downto 4) = x"D36E") then
        report "MEMORY: Reading from ethernet register block";
        case fastio_addr(3 downto 0) is
          -- @IO:GS $D6E0 Ethernet control
          when x"0" =>
            fastio_rdata(7 downto 5) <= to_unsigned(cs8900aTXstate'pos(rrnet_tx_state),3);
          -- @IO:GS $D6E0.4 Allow remote keyboard input via magic ethernet frames
            fastio_rdata(4) <= eth_keycode_toggle_internal;
          -- @IO:GS $D6E0.3 Read ethernet RX data valid
            fastio_rdata(3) <= eth_rxdv;
          -- @IO:GS $D6E0.1-2 Read ethernet TX bits currently on the wire
            fastio_rdata(2 downto 1) <= eth_rxd;
            fastio_rdata(0) <= eth_reset_int;
          -- @IO:GS $D6E1 - Ethernet interrupt and control register
          -- (unused bits = 0 to allow expansion of number of RX buffer slots
          -- from 2 to something bigger)
          when x"1" =>
            -- @IO:GS $D6E1.7 - Enable ethernet RX IRQ
            fastio_rdata(7) <= eth_irqenable_rx;
            -- @IO:GS $D6E1.6 - Enable ethernet TX IRQ
            fastio_rdata(6) <= eth_irqenable_tx;
            -- @IO:GS $D6E1.5 - Ethernet RX IRQ status
            fastio_rdata(5) <= eth_irq_rx;
            -- @IO:GS $D6E1.4 - Ethernet TX IRQ status
            fastio_rdata(4) <= eth_irq_tx;
            -- $D6E1.3 - Enable streaming of VIC-IV display on ethernet
            fastio_rdata(3) <= eth_videostream;
            -- @IO:GS $D6E1.2 - Indicate which RX buffer was most recently used
            fastio_rdata(2) <= eth_rx_buffer_last_used_48mhz;            
            -- @IO:GS $D6E1.1 - Set which RX buffer is memory mapped
            fastio_rdata(1) <= eth_rx_buffer_moby;
            -- $D6E1.0 - Clear to hold ethernet adapter in reset.
            fastio_rdata(0) <= eth_reset_int;
          -- @IO:GS $D6E2 - TX Packet size (low byte)
          when x"2" =>
            fastio_rdata <= eth_tx_size(7 downto 0);
            -- @IO:GS $D6E3 - TX Packet size (high byte)
          when x"3" =>
            fastio_rdata(7 downto 4) <= "0000";
            fastio_rdata(3 downto 0) <= eth_tx_size(11 downto 8);
          -- $D6E4 - Status of frame transmitter (DEBUG ONLY)
          when x"4"  =>
            fastio_rdata(0) <= eth_tx_trigger;
            fastio_rdata(1) <= eth_tx_commenced;
            fastio_rdata(2) <= eth_tx_complete;
            fastio_rdata(3) <= eth_txen_int;
            fastio_rdata(5 downto 4) <= eth_txd_int(1 downto 0);
            fastio_rdata(6) <= eth_tx_viciv;
            fastio_rdata(7) <= rrnet_tx_toggle;
          when x"b" =>
            fastio_rdata <= eth_tx_size(7 downto 0);
          when x"c" =>
            fastio_rdata(7 downto 4) <= x"0";
            fastio_rdata(3 downto 0) <= eth_tx_size(11 downto 8);
          when x"d" =>
            fastio_rdata <= rrnet_debug(7 downto 0);
          when x"e" =>
            fastio_rdata <= rrnet_txbuffer_addr(7 downto 0);
          when x"f" =>
            fastio_rdata <= to_unsigned(ethernet_state'pos(eth_tx_state),8);
          when others =>
            fastio_rdata <= (others => 'Z');
        end case;
      elsif (fastio_addr(19 downto 8) = x"DE0") then
        case fastio_addr(7 downto 0) is
          -- Registers $00 - $3F map to ethernet MDIO registers
          when others => fastio_rdata <= (others => 'Z');
        end case;
      else
        fastio_rdata <= (others => 'Z');
      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if;

    -- RR-NET emulation read registers.
    -- XXX These have a 1 - 2 cycle delay before the values are available for
    -- reading after the address has been set because of the way that these are
    -- set here.  However, it does simplify things quite a bit.
    -- The main implication is that you can't DMA read from the data port,
    -- which hopefully noone ever bothers to do.  Fast ethernet reception
    -- should be using the native ethernet interface.

    -- set cs_packet_data based on cs_packet_page
    if rising_edge(clock) then
--      report "ETHRX: RR-NET: rrnet_addr = $" & to_hstring(rrnet_addr);
      rrnet_reading_bus_status <= '0';
      case rrnet_addr is
        when x"0000" =>
          -- Detect register: magic value that udpslave looks for
          rrnet_data <= x"630e";
        when x"0042" =>
          -- EEPROM Data Register
          -- 64net/2 RR-NET uses this as a scratch pad
          rrnet_data <= rrnet_eeprom_data;
        when x"0124" =>
          -- RX status
          -- otherwise, set register based on current state
--          report "ETHRX: Presenting RR-NET RX status register. Last value = $" & to_hstring(rrnet_data);
          rrnet_data <= x"0000";
          -- bit8 = received a packet
          rrnet_data(8) <=  eth_irq_rx;
          -- bit10 = received a unicast
          rrnet_data(10) <= eth_irq_rx;  -- lie and say always unicast if we
                                         -- have a packet
          -- bit11 = received a broadcast
          -- bit12 = CRC error
          -- bit13 = runt
          -- bit14 = jumbo frame            
        when x"0138" =>
          -- bus status: bit8 = ready for transmission
          rrnet_data <= x"0000";
          report "RR-NET: Reading bus status. rrnet_tx_state = "
            & cs8900aTXstate'image(rrnet_tx_state);
          if eth_tx_state = Idle then
            rrnet_data(8) <=  '1';
            -- allow buffering of bytes
            rrnet_reading_bus_status <= '1';
          end if;
        when others =>
          rrnet_data <= x"ffff";
      end case;

    end if;
    
    if rising_edge(clock) then

      -- Automatically de-assert transmit trigger once the FSM has caught the signal.
      -- (but don't accidently de-assert when sending compressed video.)
      if (eth_tx_complete = '1')
        and (eth_tx_viciv='0') then
        eth_tx_trigger <= '0';
      end if;
      
      -- Bring signals accross from 50MHz side as required
      -- (pass through some flip-flops to manage meta-stability)
      eth_rx_buffer_last_used_int2 <= eth_rx_buffer_last_used_int1;
      eth_rx_buffer_last_used_int1 <= eth_rx_buffer_last_used_50mhz;      
      eth_tx_toggle_int2 <= eth_tx_toggle_int1;
      eth_tx_toggle_int1 <= eth_tx_toggle_50mhz;

      -- Set RR-NET RX buffer pointer when we notice a packet has been received.
      if eth_rx_buffer_last_used_int2 /= eth_rx_buffer_last_used_48mhz then
        report "ETHRX: Resetting RR-NET read address.";
        if eth_rx_buffer_moby='1' then
          rrnet_readaddress <= 2048;
        else
          rrnet_readaddress <= 0;
        end if;
      end if;
      
      -- Update module status based on register reads
      if fastio_read='1' then
        if fastio_addr(19 downto 0) = x"DE000" then
          null;
        end if;
      end if;

      -- Assert IRQ if a frame has been received
      if eth_rx_buffer_last_used_int2 /= eth_rx_buffer_last_used_48mhz then
        report "ETHRX: Asserting IRQ (also affects RR-NET)";
        eth_irq_rx <= '1';
        eth_rx_buffer_last_used_48mhz <= eth_rx_buffer_last_used_int2;
        -- Tell RR-NET to start fetching first two bytes of buffer data
        rrnet_read_odd <= '0';
        rrnet_read_even <= '0';
        -- RR-NET packet status bytes
        rrnet_data_even <= x"33";
        rrnet_data_odd <= x"44";
        report "ETHRX: RR-NET Preloading status bytes";
      else
        report "ETHRX: int2="&std_logic'image(eth_rx_buffer_last_used_int2)
          & ", 48mhz=" &std_logic'image(eth_rx_buffer_last_used_48mhz);
      end if;
      -- Assert IRQ if a frame has been transmitted
      if eth_tx_toggle_48mhz /= eth_tx_toggle_int2 then
        report "ETHTX: Asserting IRQ";
        eth_irq_tx <= '1';
        eth_tx_toggle_48mhz <= eth_tx_toggle_int2;
      end if;
      
      -- Assert IRQ if there is a packet waiting, and the interrupt mask is set.
      if (eth_irqenable_rx='1' and eth_irq_rx='1')
        or (eth_irqenable_tx='1' and eth_irq_tx='1') then
        irq <= '0';
      else
        irq <= 'Z';
      end if;

      if rrnet_buffer_write_pending = '1' and rrnet_tx_state = Buffering then
        -- Put byte into ethernet TX buffer
        if rrnet_buffer_odd='0' then
          txbuffer_writeaddress <= to_integer(rrnet_txbuffer_addr(10 downto 0));
          report "ETHBUFFER: Writing byte $" & to_hstring(rrnet_buffer_data) & " to buffer offset $"
            & to_hstring(to_unsigned(to_integer(rrnet_txbuffer_addr(10 downto 0))+0,12));
        else
          txbuffer_writeaddress <= to_integer(rrnet_txbuffer_addr(10 downto 0)) + 1;
          report "ETHBUFFER: Writing byte $" & to_hstring(rrnet_buffer_data) & " to buffer offset $"
          & to_hstring(to_unsigned(to_integer(rrnet_txbuffer_addr(10 downto 0))+1,12));
        end if;
        txbuffer_write <= '1';                
        txbuffer_wdata <= rrnet_buffer_data;
        rrnet_buffer_write_pending <= '0';
      end if;      
      if rrnet_buffer_addr_bump = '1' then
        report "ETHBUFFERING: RR-NET bumping buffer pointer from "
          & integer'image(to_integer(rrnet_txbuffer_addr));
        if (to_integer(eth_tx_size)
            = (to_integer(rrnet_txbuffer_addr(10 downto 0))+2))
           and rrnet_tx_state <= Buffering then
          -- we have buffered all the bytes for this frame - so initiate
          -- transmission.
          rrnet_debug <= x"ed";
          eth_tx_trigger <= '1';
          rrnet_tx_state <= Idle;
          rrnet_tx_toggle <= not rrnet_tx_toggle;
          report "ETHBUFFERING: RR-NET: Dispatching frame: Toggling rrnet_tx_toggle: was "
            & std_logic'image(rrnet_tx_toggle);
        else
          report "ETHBUFFERING: RR-NET: "
            &integer'image(to_integer(eth_tx_size))
            &" != "
            &integer'image(to_integer(rrnet_txbuffer_addr(10 downto 0))+2);
        end if;
        rrnet_txbuffer_addr <= rrnet_txbuffer_addr + 2;
        rrnet_buffer_addr_bump <= '0';
      end if;

      rrnet_dup_read <= '0';
      if fastio_read='1' and rrnet_enable='1' and
          (fastio_addr=x"D0E08" or fastio_addr=x"D0E09") then
        report "ETHRX: RR-NET read flags:"
          & " even=" & std_logic'image(rrnet_read_even)
          & ", odd=" & std_logic'image(rrnet_read_odd)
          & ", even_byte=$" & to_hstring(rrnet_data_even)
          & ", odd_byte=$" & to_hstring(rrnet_data_odd);
        rrnet_dup_read <= '1';
        if fastio_addr = x"D0E08" and (rrnet_dup_read='0') then
          if rrnet_read_odd='0' then
            report "ETHRX: RR-NET read even byte";
            rrnet_read_even <= '1';
          else
            report "ETHRX: RR-NET read word - advancing buffer pointer, even data will be $" & to_hstring(rrnet_buffer_rdata)
              & " from " & integer'image(rrnet_readaddress);
            rrnet_read_odd <= '0';
            rrnet_read_even <= '0';
            rrnet_advance_buffer <= '1';
            rrnet_data_even <= rrnet_buffer_rdata;
            if rrnet_readaddress < 4095 then
              rrnet_readaddress <= rrnet_readaddress + 1;
            else
              rrnet_readaddress <= 0;
            end if;
          end if;
        elsif fastio_addr = x"D0E09" and (rrnet_dup_read='0') then
          if rrnet_read_even='0' then
            report "ETHRX: RR-NET read odd byte";
            rrnet_read_odd <= '1';
          else
            report "ETHRX: RR-NET read word - advancing buffer pointer, even data will be $" & to_hstring(rrnet_buffer_rdata)
              & " from " & integer'image(rrnet_readaddress);
            rrnet_read_odd <= '0';
            rrnet_read_even <= '0';
            rrnet_advance_buffer <= '1';
            rrnet_data_even <= rrnet_buffer_rdata;
            if rrnet_readaddress < 4095 then
              rrnet_readaddress <= rrnet_readaddress + 1;
            else
              rrnet_readaddress <= 0;
            end if;
          end if;
        end if;
        if rrnet_advance_buffer = '1' then
          report "ETHRX: Bumping RR-NET read address to " & integer'image(rrnet_readaddress) & " + 1, odd data will be $" & to_hstring(rrnet_buffer_rdata);
          rrnet_data_odd <= rrnet_buffer_rdata;
          rrnet_advance_buffer <= '0';
          if rrnet_readaddress < 4095 then
            rrnet_readaddress <= rrnet_readaddress + 1;
          else
            rrnet_readaddress <= 0;
          end if;
        end if;

        -- Also clear the ethernet IRQ flag once we start reading the packet.
        -- This doesn't exactly match how the RR-NET really works, but it is
        -- close enough for now.
        report "ETHRX: Clearing IRQ";
        eth_irq_rx <= '0';
      end if;
      
      -- Write to registers
      if fastio_write='1' then
        -- RR-NET emulation
        if fastio_addr = x"D0E01" then
          -- @IO:C64 $DE01.0 Enable RR-NET emulated clock port ethernet interface
          -- bit 0 enables clock port according to
          -- http://ar.c64.org/wiki/Inside_Replay.txt
          rrnet_enable <= fastio_wdata(0);
        end if;
        if fastio_addr = x"D0E02" and rrnet_enable='1' then
          -- @IO:C64 $DE02 RRNET register select register (low)
          rrnet_addr(7 downto 0) <= fastio_wdata;
        end if;
        if fastio_addr = x"D0E03" and rrnet_enable='1' then
          -- @IO:C64 $DE03 RRNET register select register (low)
          rrnet_addr(15 downto 8) <= fastio_wdata;
        end if;
        if rrnet_enable='1' and rrnet_addr = x"0042" then
          if fastio_addr = x"D0E04" then
            rrnet_eeprom_data(7 downto 0) <= fastio_wdata;
          end if;
          if fastio_addr = x"D0E05" then
            rrnet_eeprom_data(15 downto 8) <= fastio_wdata;
          end if;
        end if;
        if fastio_addr = x"D0E06" and rrnet_enable='1' then
          -- @IO:C64 $DE06 write to even numbered RR-NET register
          case rrnet_addr is
            when x"0144" =>
              -- TX transmit command (also on dedicated $DE0C)
              -- $C9 = transmit when entire frame buffered, and don't retransmit
              -- if something goes wrong.
              -- Transmission is not actually started until
              rrnet_debug <= x"44";
              rrnet_txcmd_set;            
            when x"0146" =>
              -- TX len (low byte) (also on dedicated $DE0E)
              eth_tx_size(7 downto 0) <= fastio_wdata;
            -- MAC address            
            when x"0158" => eth_mac(47 downto 40) <= fastio_wdata;
            when x"015A" => eth_mac(31 downto 24) <= fastio_wdata;
            when x"015C" => eth_mac(15 downto 8) <= fastio_wdata;
            when others => null;
          end case;
        end if;
        if fastio_addr = x"D0E07" and rrnet_enable='1' then
          -- @IO:C64 $DE06 write to odd numbered RR-NET register
          case rrnet_addr is
            -- TX len (low byte) (also on dedicated $DE0F)
            when x"0147" => eth_tx_size(10 downto 8) <= fastio_wdata(2 downto 0);
            -- MAC address
            when x"0159" => eth_mac(39 downto 32) <= fastio_wdata;
            when x"015B" => eth_mac(23 downto 16) <= fastio_wdata;
            when x"015D" => eth_mac(7 downto 0) <= fastio_wdata;
            when others => null;
          end case;
        end if;
        -- @IO:C64 $DE08 RR-NET buffer port (even byte)
        if fastio_addr = x"D0E08" and rrnet_enable='1' then
          if rrnet_tx_state = Buffering then
            -- write even numbered address
            rrnet_buffer_even_written <= not rrnet_buffer_odd_written;
            rrnet_buffer_addr_bump <= rrnet_buffer_odd_written;
            if rrnet_buffer_odd_written = '1' then
              report "ETHBUFFERING: Buffering RR-NET TX byte and bumping pointer.";
              rrnet_buffer_odd_written <= '0';
            end if;
            
            rrnet_buffer_write_pending <= '1';
            rrnet_buffer_data <= fastio_wdata;
            rrnet_buffer_odd <= fastio_addr(0);
          end if;
        end if;
        -- @IO:C64 $DE09 RR-NET buffer port (even byte)
        if fastio_addr = x"D0E09" and rrnet_enable='1' then
          -- write odd numbered address and advance offset
          -- XXX why do writes to odd addresses advance the pointer,
          -- but is it the even address that does it for reads? Or have
          -- I totally misunderstood something?
          if rrnet_tx_state = Buffering then
            rrnet_buffer_odd_written <= not rrnet_buffer_even_written;
            rrnet_buffer_addr_bump <= rrnet_buffer_even_written;
            if rrnet_buffer_even_written = '1' then
              report "ETHBUFFERING: Buffering RR-NET TX byte and bumping pointer.";
              rrnet_buffer_even_written <= '0';
            end if;
            
            rrnet_buffer_write_pending <= '1';
            rrnet_buffer_data <= fastio_wdata;
            rrnet_buffer_odd <= fastio_addr(0);
          end if;
        end if;
        if fastio_addr = x"D0E0C" and rrnet_enable='1' then
          -- @IO:C64 $DE0C RRNET tx_cmd register (low)
          rrnet_debug <= x"0C";
          rrnet_txcmd_set;
        end if;
        if fastio_addr = x"D0E0D" and rrnet_enable='1' then
          -- @IO:C64 $DE0C RRNET tx_cmd register (high)
        end if;
        if fastio_addr = x"D0E0E" and rrnet_enable='1' then
          -- @IO:C64 $DE0E Set RR-NET TX packet size
          eth_tx_size(7 downto 0) <= fastio_wdata;
        end if;
        if fastio_addr = x"D0E0F" and rrnet_enable='1' then
          -- @IO:C64 $DE0F Set RR-NET TX packet size
          eth_tx_size(10 downto 8) <= fastio_wdata(2 downto 0);
        end if;
        if fastio_addr = x"D0E10" and rrnet_enable='1' then
          rrnet_debug <= fastio_wdata;
        end if;
        if fastio_addr(19 downto 10)&"00" = x"DE8" then
          -- Writing to TX buffer
          -- (we don't need toclear the write lines, as noone else can write to
          -- the buffer.  The TX buffer cannot be read, as reading the same
          -- addresses reads from the RX buffer.)
          -- @IO:GS $FFDE800 - $FFDEFFF Ethernet TX buffer (write only)
          -- @IO:GS $FFDE800 - $FFDEFFF Ethernet RX buffer (read only)
          txbuffer_writeaddress <= to_integer(fastio_addr(10 downto 0));
          txbuffer_write <= '1';
          txbuffer_wdata <= fastio_wdata;
        end if;
        if (fastio_addr(19 downto 4) = x"D36E") then
          case fastio_addr(3 downto 0) is
            when x"0" =>
              -- @IO:GS $D6E0.0 Clear to reset ethernet PHY
              eth_reset <= fastio_wdata(0);
              eth_reset_int <= fastio_wdata(0);
            when x"1" =>
              -- $D6E1 100mbit ethernet irq mask
              -- $D6E1.7 100mbit ethernet enable RX IRQ
              eth_irqenable_rx <= fastio_wdata(7);
              -- $D6E1.7 100mbit ethernet enable TX done IRQ
              eth_irqenable_tx <= fastio_wdata(6);
              -- Writing here also clears any current interrupts
              report "ETHRX: Clearing IRQ";
              eth_irq_rx <= '0';
              eth_irq_tx <= '0';

              -- @IO:GS $D6E1.3 Enable real-time video streaming via ethernet
              eth_videostream <= fastio_wdata(3);

              -- @IO:GS $D6E1.1 - Set which RX buffer is memory mapped
              eth_rx_buffer_moby <= fastio_wdata(1);

              -- @IO:GS $D6E1.0 reset ethernet PHY
              eth_reset <= fastio_wdata(0);
              eth_reset_int <= fastio_wdata(0);
            -- @IO:GS $D6E2 Set low-order size of frame to TX
            when x"2" =>
              eth_tx_size(7 downto 0) <= fastio_wdata;
            -- @IO:GS $D6E3 Set high-order size of frame to TX
            when x"3" =>
              eth_tx_size(11 downto 8) <= fastio_wdata(3 downto 0);
            -- @IO:GS $D6E4 Ethernet command
            when x"4" =>
              case fastio_wdata is
                when x"00" =>
                  -- @IO:GS $D6E4 = $00 = Clear ethernet TX trigger (debug)
                  eth_tx_trigger <= '0';
                when x"01" =>
                  -- @IO:GS $D6E4 = $01 = Transmit packet
                  eth_tx_trigger <= '1';
                when x"de" => -- debug rx
                  -- Receive exactly one frame, and keep all signals states
                  debug_rx <= '1';
                when x"d0" => -- disable rx debug
                  debug_rx <= '0';
                when others =>
                  null;
              end case;
            when others =>
              -- Other registers do nothing
              null;
          end case;
        end if;
        if fastio_addr(19 downto 8) = x"DE0" then
          if fastio_addr(7 downto 6) = "00" then
            -- Writing to ethernet controller MD registers
          else
            -- Other registers
          end if;
        end if;
      end if;

      -- Do synchronous actions
      
    end if;
  end process;

end behavioural;
