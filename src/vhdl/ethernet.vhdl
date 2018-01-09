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
    clock200 : in std_logic;
    reset : in std_logic;
    irq : out std_logic := 'Z';
    ethernet_cs : in std_logic;

    ---------------------------------------------------------------------------
    -- IO lines to the ethernet controller
    ---------------------------------------------------------------------------
    eth_mdio : inout std_logic := '1';
    eth_mdc : out std_logic := '1';
    eth_reset : out std_logic := '1';
    eth_rxd_in : in unsigned(1 downto 0);
    eth_txd_out : out unsigned(1 downto 0) := "11";
    eth_txen_out : out std_logic := '0';
    eth_rxdv_in : in std_logic;
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

 signal eth_swap_rx : std_logic := '0';
 signal eth_rxdv : std_logic := '0';
 signal eth_rxd : unsigned(1 downto 0) := "00";
 signal eth_disable_crc_check : std_logic := '0';

 signal eth_txd : unsigned(1 downto 0) := "11";
 signal eth_txen : std_logic := '0';
 signal eth_txd_delayed : unsigned(7 downto 0) := "11111111";
 signal eth_txen_delayed : std_logic_vector(3 downto 0) := "0000";
 signal eth_txd_phase : unsigned(1 downto 0) := "00";
 signal eth_txd_phase_drive : unsigned(1 downto 0) := "00";
 
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

  -- Present TX data bits and TX en lines at variable phase to
  -- 50MHz clock
  process(clock200) is
  begin
    if rising_edge(clock200) then
      eth_txd_out <= eth_txd_delayed(7 downto 6);
      eth_txen_out <= eth_txen_delayed(3);

      eth_txd_delayed(7 downto 2) <= eth_txd_delayed(5 downto 0);
      eth_txen_delayed(3 downto 1) <= eth_txen_delayed(2 downto 0);
      case eth_txd_phase_drive is
        when "00" =>
          eth_txd_delayed(7 downto 6) <= eth_txd;
          eth_txen_delayed(3) <= eth_txen;
        when "01" =>
          eth_txd_delayed(5 downto 4) <= eth_txd;
          eth_txen_delayed(2) <= eth_txen;
        when "10" =>
          eth_txd_delayed(3 downto 2) <= eth_txd;
          eth_txen_delayed(1) <= eth_txen;
        when others =>
          eth_txd_delayed(1 downto 0) <= eth_txd;
          eth_txen_delayed(0) <= eth_txen;
      end case;
    end if;
  end process;
  
  process(clock50mhz) is
    variable frame_length : unsigned(11 downto 0);
  begin
    if rising_edge(clock50mhz) then
      eth_txd_phase_drive <= eth_txd_phase;
      
      if eth_swap_rx='1' then
        eth_rxd(1) <= eth_rxd_in(0);
        eth_rxd(0) <= eth_rxd_in(1);
      else
        eth_rxd <= eth_rxd_in;
      end if;
      eth_rxdv <= eth_rxdv_in;
      
      -- Register ethernet data lines and data valid signal
      eth_txd <= eth_txd_int;
      eth_txen <= eth_txen_int;
      
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
          eth_txen_int <= '0';

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
            eth_txen_int <= '1';
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
            eth_txd_int <= unsigned(eth_tx_crc_bits(31 downto 30));
            eth_tx_crc_bits(31 downto 2) <= eth_tx_crc_bits(29 downto 0);
            eth_tx_crc_count <= eth_tx_crc_count - 1;
          else
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
          -- RXDV is multiplexed with carrier sense on some PHYs, so we
          -- need two consecutive low readings to be sure. Otherwise we
          -- lose the last CRC, and sometimes the last byte.
          if (eth_rxdv='0') and (eth_rxdv_in='0') then
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
          rxbuffer_wdata <= to_unsigned(eth_frame_len,8);
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
          if rx_crc_valid='1' or eth_disable_crc_check='1' then
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

  begin

    if fastio_read='1' then
      report "MEMORY: Reading from fastio";

      if ethernet_cs='1' then
        report "MEMORY: Reading from ethernet register block";
        case fastio_addr(3 downto 0) is
          -- @IO:GS $D6E0 Ethernet control
          when x"0" =>
            -- @IO:GS $D6E0.7 ETH_MDIO
            fastio_rdata(7) <= eth_mdio;
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
            fastio_rdata(7) <= '0';
          when x"5" =>
            fastio_rdata(0) <= eth_swap_rx;
            fastio_rdata(1) <= eth_disable_crc_check;
            fastio_rdata(3 downto 2) <= eth_txd_phase;
            fastio_rdata(7 downto 4) <= (others => '0');
          when x"b" =>
            fastio_rdata <= eth_tx_size(7 downto 0);
          when x"c" =>
            fastio_rdata(7 downto 4) <= x"0";
            fastio_rdata(3 downto 0) <= eth_tx_size(11 downto 8);
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

      -- Update module status based on register reads
      if fastio_read='1' then
        if fastio_addr(19 downto 0) = x"DE000" then
          null;
        end if;
      end if;

      -- Assert IRQ if a frame has been received
      if eth_rx_buffer_last_used_int2 /= eth_rx_buffer_last_used_48mhz then
        report "ETHRX: Asserting IRQ";
        eth_irq_rx <= '1';
        eth_rx_buffer_last_used_48mhz <= eth_rx_buffer_last_used_int2;
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

      if fastio_write='1' then
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
        if ethernet_cs='1' then
          case fastio_addr(3 downto 0) is
            when x"0" =>
              -- @IO:GS $D6E0.0 Clear to reset ethernet PHY
              eth_reset <= fastio_wdata(0);
              eth_reset_int <= fastio_wdata(0);
              -- @IO:GS $D6E0.7 ETH_MDIO read/write
              -- @IO:GS $D6E0.6 ETH_MDIO data direction register
              if fastio_wdata(6)='1' then
                eth_mdio <= fastio_wdata(7);
              else
                eth_mdio <= 'Z';
              end if;
              -- @IO:GS $D6E0.6 ETH_MDC (write only)
              eth_mdc <= fastio_wdata(5);
              
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
            when x"5" =>
              -- @IO:GS $D6E5.2-3 Ethernet TX clock phase adjust
              eth_txd_phase <= fastio_wdata(3 downto 2);
              -- @IO:GS $D6E5.0 Swap RMII RX bit order
              eth_swap_rx <= fastio_wdata(0);
              -- @IO:GS $D6E5.1 Disable CRC check for received packets
              eth_disable_crc_check <= fastio_wdata(1);
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
