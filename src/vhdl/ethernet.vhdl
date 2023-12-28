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
  generic (
    num_buffers : in integer := 4
    );
  port (
    clock : in std_logic;
    clock50mhz : in std_logic;
    clock200 : in std_logic;
    reset : in std_logic;
    irq : out std_logic := '1';
    ethernet_cs : in std_logic;

    cpu_ethernet_stream : out std_logic := '0';
    eth_remote_control : in std_logic;
    eth_load_enable : in std_logic;

    ---------------------------------------------------------------------------
    -- IO lines to the ethernet controller
    ---------------------------------------------------------------------------
    eth_mdio : inout std_logic;
    eth_mdc : out std_logic;
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
    buffer_offset : in unsigned(11 downto 0);
    buffer_address : out unsigned(11 downto 0);
    buffer_rdata : in unsigned(7 downto 0);

    instruction_strobe : in std_logic;
    raster_number : in unsigned(11 downto 0);
    vicii_raster : in unsigned(11 downto 0);
    badline_toggle : in std_logic;
    debug_vector : in unsigned(63 downto 0);
    d031_write_toggle : in std_logic;
    cpu_arrest : out std_logic := '0';
    
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
    -- XXX Move to making this a valid UDP6 packet at some point.
    -- Main problem is we need to compute the checksum over the data
    -- before we can do this.  Not impossible, but will require modifying
    -- the framepacker to do this as the data is collected.
    -- It will need to do this using a seed checksum that covers the
    -- invariant header, so it shouldn't really be a big imposition.
    x"00", -- next header (0x11 = indicate UDP, 0x00 = hop-by-hop options)
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
  
  type ethernet_state is (Idle,
                          DebugRxFrameWait,DebugRxFrame,DebugRxFrameDone,
                          WaitingForPreamble,
                          ReceivingPreamble,
                          ReceivingFrame,
                          ReceivedFrame,
                          ReceivedFrameWait,
                          ReceivedFrame2,
                          ReceivedFrame2Wait,
                          PostRxDelay,
                          BadFrame,

                          IdleWait,
                          Interpacketgap,  -- $0E
                          WaitBeforeTX,    -- $0F
                          SendingPreamble,
                          SendingFrame,    -- $11
                          SendFCS,
                          SentFrame        -- $13
                          );
  signal eth_state : ethernet_state := Idle;
  signal eth_wait : integer range 0 to 20 := 0;

  -- MAC address and filtering functions
  signal eth_mac : unsigned(47 downto 0) := x"024753656565";
  signal eth_mac_shift : unsigned(39 downto 0) := (others => '0');
  signal eth_mac_filter : std_logic := '1';
  signal eth_accept_broadcast : std_logic := '1';
  signal eth_accept_multicast : std_logic := '1';
  signal frame_is_broadcast : std_logic := '0';
  signal frame_is_multicast : std_logic := '0';
  signal frame_is_for_me : std_logic := '0';
  
  signal rx_keyinput : std_logic := '0';
  signal eth_keycode_toggle_internal : std_logic := '0';
  
  signal last_buffer_moby_toggle : std_logic := '0';
  
  -- If asserted, collect raw signals for exactly one frame, then do nothing.
  signal debug_rx : std_logic := '0';
  
  -- control reset line on ethernet controller
  signal reset_50mhz : std_logic := '1';
  signal reset_50mhz_drive : std_logic := '1';
  signal eth_reset_int : std_logic := '1';
  signal eth_reset_int_50mhz : std_logic := '1';
  signal eth_reset_int_50mhz_drive : std_logic := '1';
  signal eth_soft_reset : std_logic := '1';
  signal eth_soft_reset_50mhz : std_logic := '1';
  signal eth_soft_reset_50mhz_drive : std_logic := '1';
  -- which half of frame RX buffer is visible
  signal eth_rx_buffer_moby : std_logic := '0';
  signal eth_rx_buffer_moby_int1 : std_logic := '0';
  signal eth_rx_buffer_moby_int2 : std_logic := '0';
  signal eth_rx_buffer_moby_50mhz : std_logic := '0';
  signal eth_rx_crc : unsigned(31 downto 0);
  -- ethernet receiver signals
  signal eth_rxbits : unsigned(5 downto 0);
  signal eth_bit_count : integer range 0 to 6;  
  signal eth_frame_len : integer range 0 to 2047;
  signal eth_mac_counter : integer range 0 to 7;

  signal rxbuffer_cs : std_logic_vector((num_buffers-1) downto 0) := (others => '0');
  signal rxbuffer_cs_vector : std_logic_vector((num_buffers-1) downto 0) := (others => '0');
  signal rxbuffer_end_of_packet_toggle : std_logic := '0';
  signal rxbuffer_end_of_packet_toggle_drive : std_logic := '0';
  signal last_rxbuffer_end_of_packet_toggle : std_logic := '0';
  signal rxbuffer_write_toggle : std_logic := '0';
  signal rxbuffer_write_toggle_drive : std_logic := '0';
  signal last_rxbuffer_write_toggle : std_logic := '0';
  signal rxbuffer_writeaddress : integer range 0 to 2047;

  signal rxbuffer_write : std_logic_vector((num_buffers-1) downto 0) := (others => '0');
  signal rxbuffer_writeaddress_l : integer range 0 to 2047;
  signal rxbuffer_wdata_l : unsigned(7 downto 0) := x"00";
  signal rxbuffer_write_drive : std_logic_vector((num_buffers-1) downto 0) := (others => '0');
  signal rxbuffer_writeaddress_l_drive : integer range 0 to 2047;
  signal rxbuffer_wdata_l_drive : unsigned(7 downto 0) := x"00";

  signal rxbuffer_wdata : unsigned(7 downto 0) := x"00";

  signal rxbuffer_readaddress : integer range 0 to 2047;
  signal eth_rx_buffer_inuse : unsigned((num_buffers-1) downto 0) := (others => '0');
  -- CPU RX buff ID must start one behind Ethernet side.
  -- 1. Eth side writes to buffer n, while CPU is on n-1.
  -- 2. When frame received, Eth advances to n+1, and CPU notices newly
  -- received frame that should be in n.
  -- 3. CPU tells Eth controller to show next frame buffer and ack the frame, thus
  -- incrementing from n-1 to n, allowing the CPU to see the newly received frame.
  signal rxbuff_id_cpuside : integer range 0 to (num_buffers-1) := 0;
  signal rxbuff_id_ethside : integer range 0 to (num_buffers-1) := 1;
  signal rxbuff_id_cpuside_last : integer range 0 to (num_buffers-1) := 0;
  signal rxbuff_id_ethside_last : integer range 0 to (num_buffers-1) := 1;
  signal rxbuff_id_cpuside_plus1 : integer range 0 to (num_buffers-1) := 0;
  signal eth_rx_buffers_free : integer range 0 to num_buffers := num_buffers - 1;
  
  signal eth_tx_toggle_48mhz : std_logic := '1';
  signal eth_tx_toggle : std_logic := '1';
  signal eth_tx_toggle_int2 : std_logic := '1';
  signal eth_tx_toggle_int1 : std_logic := '1';
  signal eth_tx_toggle_50mhz : std_logic := '1';
  signal tx_preamble_count : integer range 63 downto 0 := 0;
  signal tx_preamble_length : integer range 63 downto 0 := 29;
  signal eth_tx_state : ethernet_state := Idle;
  signal eth_tx_bit_count : integer range 0 to 6 := 0;
  signal eth_tx_viciv : std_logic := '0';
  signal eth_tx_dump : std_logic := '0';
  signal txbuffer_writeaddress : integer range 0 to 2047;
  signal txbuffer_readaddress : integer range 0 to 2047;
  signal txbuffer_write : std_logic := '0';
  signal txbuffer_wdata : unsigned(7 downto 0) := x"00";
  signal txbuffer_rdata : unsigned(7 downto 0) := x"00";
  signal eth_tx_bits : unsigned(7 downto 0) := x"00";
  signal eth_tx_size : unsigned(11 downto 0) := to_unsigned(98,12);
  signal eth_tx_size_padded : unsigned(11 downto 0) := to_unsigned(98,12);
  signal eth_tx_padding : std_logic := '0';
  signal eth_tx_trigger : std_logic := '0';
  signal eth_tx_trigger_drive : std_logic := '0';
  signal eth_tx_trigger_50mhz : std_logic := '0';
  signal eth_tx_trigger_50mhz_drive : std_logic := '0';
  signal eth_tx_commenced : std_logic := '0';
  signal eth_tx_complete : std_logic := '0';
  signal eth_tx_complete_drive : std_logic := '0';
  signal eth_txen_int : std_logic := '0';
  signal eth_txd_int : unsigned(1 downto 0) := "00";
  signal eth_tx_wait : integer range 0 to 50 := 0;
  
  signal eth_tx_crc_count : integer range 0 to 16 := 0;
  signal eth_tx_crc_bits : std_logic_vector(31 downto 0) := (others => '0');

  signal eth_beacon_timer_count : integer range 0 to 50000000 := 0;
  signal eth_send_beacon : std_logic := '0';
  signal update_beaconbuffer : std_logic := '0';
  signal beaconbuffer_write : std_logic := '0';
  signal beaconbuffer_waddr : integer range 0 to 67 := 0; 
  signal beaconbuffer_wdata : unsigned(7 downto 0) := x"00";
  signal beaconbuffer_rdata : unsigned(7 downto 0) := x"00";
  
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
  signal eth_irq_rx : std_logic := '1';
  signal eth_irq_tx : std_logic := '1'; 

  signal eth_videostream : std_logic := '0';
  signal eth_byte_100 : unsigned(7 downto 0) := x"bd";
  signal eth_key_debug : unsigned(7 downto 0) := x"00";
  signal eth_byte_fail : unsigned(7 downto 0) := x"00";
  signal eth_offset_fail : unsigned(7 downto 0) := x"00";

  signal eth_rxdv : std_logic := '0';
  signal eth_rxdv_last : std_logic := '0';
  signal eth_rxdv_last2 : std_logic := '0';
  signal eth_rxdv_latched : std_logic := '0';
  signal eth_rxd : unsigned(1 downto 0) := "00";
  signal eth_rxd_latched : unsigned(1 downto 0) := "00";
  signal eth_disable_crc_check : std_logic := '0';
  signal rx_phase_counter : integer range 0 to 3 := 0;
  signal eth_rx_latch_phase_drive : unsigned(1 downto 0) := to_unsigned(0,2);
  signal eth_rx_latch_phase : unsigned(1 downto 0) := to_unsigned(0,2);

  signal eth_txd : unsigned(1 downto 0) := "11";
  signal eth_txen : std_logic := '0';
  signal eth_txd_delayed : unsigned(7 downto 0) := "11111111";
  signal eth_txen_delayed : std_logic_vector(3 downto 0) := "0000";
  signal eth_txd_phase : unsigned(1 downto 0) := "01";
  signal eth_txd_phase_drive : unsigned(1 downto 0) := "00";
  signal eth_txd_out_stage : unsigned(1 downto 0) := "00";
  signal eth_txen_out_stage : std_logic := '0';

  signal eth_tx_packet_count : unsigned(5 downto 0) := "000000";
  
  signal miim_request : std_logic := '0';
  signal miim_write : std_logic := '0';
  signal miim_phyid : unsigned(4 downto 0) := to_unsigned(0,5);
  signal miim_register : unsigned(4 downto 0) := to_unsigned(0,5);
  signal miim_read_value : unsigned(15 downto 0) := to_unsigned(0,16);
  signal miim_write_value : unsigned(15 downto 0) := to_unsigned(0,16);
  signal miim_ready : std_logic := '0'; 

  -- BRAM controls for real-time CPU / bus activity dumping
  -- Interface is 64 bit write, 8-bit read.
  -- For Bus monitoring, this means we can provide:
  -- address (32 bits), write data (8 bits), read data (8 bits), read/write
  -- plus IO mode flags (4 bits packed in a byte)
  -- For CPU monitoring:
  -- PC (16 bits), last instruction (24 bits), flags (8 bits), SP low byte (8 bits)
  -- and A (8 bits)
  -- As we write 8 bytes at a time at 40MHz, but the ethernet interface only outputs
  -- 2 bits at a time at 50MHz, this means that we can only log with a duty cycle
  -- of 2*50 / 64*40 = 100 / 2560 = 1/25.6 ~= 4%.  At 1MHz the CPU runs at only
  -- 2.5% speed, so we should be able to do full real-time instruction capture,
  -- except that we need to hold the buffer unmodified while sending, or else
  -- send while filling. For now, we will do the easy path of blocking writes
  -- once the buffer is full, and until such time as it has been emptied through
  -- transmission.  We could improve this by sending it in 1KB or 2KB pieces, and
  -- effectively double-buffering it.
  signal dumpram_raddr : std_logic_vector(11 downto 0) := (others => '0');
  signal dumpram_waddr : std_logic_vector(8 downto 0) := (others => '0');
  signal dumpram_wdata : std_logic_vector(63 downto 0) := (others => '0');
  signal dumpram_rdata : std_logic_vector(7 downto 0) := (others => '0');
  signal dumpram_write : std_logic := '0';
  signal allow_2k_log_frames : std_logic := '1';
  signal activity_dump_ready_toggle : std_logic := '0';
  signal last_activity_dump_ready_toggle : std_logic := '0';
  signal activity_dump : std_logic := '0';
  signal eth_tx_idle : std_logic := '0';
  signal eth_tx_idle_cpuside : std_logic := '0';
  signal cpu_arrest_internal : std_logic := '0';

  signal last_badline_toggle : std_logic := '0'; 
  signal last_raster_toggle : std_logic := '0';
  signal raster_toggle : std_logic := '0';
  signal last_raster_number : unsigned(11 downto 0) := (others => '0');

  signal eth_rx_write_count : unsigned(7 downto 0) := x"00";

  signal eth_rx_blocked_50mhz : std_logic := '0';
  signal eth_rx_blocked : std_logic := '0';

  signal last_rx_rotate_bit : std_logic := '0';
  signal rx_rotate_count : unsigned(3 downto 0) := to_unsigned(0,4);

  signal post_rx_countdown : integer range 0 to 15 := 0;

  signal eth_debug_select : unsigned(7 downto 0) := x"00";
  signal tx_frame_count : unsigned(7 downto 0) := x"00";

  signal eth_rx_oversample : unsigned(7 downto 0) := x"00";
  signal eth_rx_oversample_drive : unsigned(7 downto 0) := x"00";

  signal eth_mode_100 : std_logic := '1';
  signal eth_dibit_strobe : std_logic := '1';
  signal eth_10mbit_strobe : std_logic_vector(9 downto 0) := "1000000000";  

  signal ack_rx_frame_toggle : std_logic := '0';
  signal last_ack_rx_frame_toggle : std_logic := '0';
  
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
  -- We will use four 2KB RX buffers.
  -- RX buffer is written from ethernet side, so use 50MHz clock.
  -- reads are fully asynchronous, so no need for a read-side clock for the CPU
  -- side.

  -- XXX: Need to have separate read and write clocks
  -- XXX: Without the _sync version, we in reality have only one clock,
  -- and so we still get cross-clock timing violations with this.
  -- We could use _sync, in which case we just need to make sure that we
  -- have the right number of waitstates in the CPU.
  rxbuffers: for i in 0 to (num_buffers-1) generate
    rxbuffer0: entity work.ram8x2048
      generic map (
        id => i
        )
      port map (
      clkw => clock50mhz,
      clkr => clock,
      cs => rxbuffer_cs(i),
      w => rxbuffer_write(i),
      write_address => rxbuffer_writeaddress_l,
      wdata => rxbuffer_wdata_l,
      address => rxbuffer_readaddress,
      rdata => fastio_rdata);
  end generate;

  txbuffer0: entity work.ram8x2048 generic map ( id => 1000 ) port map (
    clkr => clock50mhz,
    clkw => clock,
    cs => '1',
    w => txbuffer_write,
    write_address => txbuffer_writeaddress,
    wdata => txbuffer_wdata,
    address => txbuffer_readaddress,
    rdata => txbuffer_rdata);  

  beaconbuffer0: entity work.beaconram port map (
    clk => clock,
    w => beaconbuffer_write,
    write_address => beaconbuffer_waddr,
    wdata => beaconbuffer_wdata,
    address => txbuffer_readaddress,
    rdata => beaconbuffer_rdata);

  rx_CRC : entity work.CRC
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
  
  tx_CRC : entity work.CRC
    generic map ( debug => true )
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

  miim0:        entity work.ethernet_miim port map (
    clock => clock50mhz,
    eth_mdio => eth_mdio,
    eth_mdc => eth_mdc,

    miim_request => miim_request,
    miim_write => miim_write,
    miim_phyid => miim_phyid,
    miim_register => miim_register,
    miim_read_value => miim_read_value,
    miim_write_value => miim_write_value,
    miim_ready => miim_ready
    );

  -- asymmetric SDP BRAM used for high-speed data dumps out of the MEGA65.
  -- In particular, this is to give the CPU a nice way to be able to dump
  -- full instruction streams or bus activity reports via ethernet, to help
  -- debug problems that are dependent on dynamic timing, and thus only
  -- show up when the CPU is free running.
  cpulogram: entity work.asym_ram_sdp_write_wider port map (
    -- Read interface
    clkA => clock50mhz,
    addrA => dumpram_raddr,
    doA => dumpram_rdata,
    enA => '1',
    
    clkB => clock,
    enB => '1',
    weB => dumpram_write,
    addrB => dumpram_waddr,
    diB => dumpram_wdata
    );

  -- Look after CPU side of mapping of RX buffer
  process(fastio_addr,fastio_read,rxbuffer_cs_vector) is
  begin    
    rxbuffer_readaddress <= to_integer(fastio_addr(10 downto 0));
    if fastio_read='1' and (
      (fastio_addr(19 downto 11)&"000" = x"DE8")
      or (fastio_addr(19 downto 11)&"000" = x"D28")
      )
    then
      rxbuffer_cs <= rxbuffer_cs_vector;
    else
      rxbuffer_cs <= (others => '0');
    end if;
  end process;

  -- Present TX data bits and TX en lines at variable phase to
  -- 50MHz clock
  process(clock200) is
  begin
    if rising_edge(clock200) then

      -- Extra drive stage to de-glitch TX lines
      eth_txd_out <= eth_txd_out_stage;
      eth_txen_out <= eth_txen_out_stage;
      
      eth_txd_out_stage <= eth_txd_delayed(7 downto 6);
      eth_txen_out_stage <= eth_txen_delayed(3);

      if rx_phase_counter /= 3 then
        rx_phase_counter <= rx_phase_counter + 1;
      else
        rx_phase_counter <= 0;
      end if;

      if rx_phase_counter = to_integer(eth_rx_latch_phase_drive) then
        eth_rxd_latched <= eth_rxd_in;
        eth_rxdv_latched <= eth_rxdv_in;
      end if;

      -- Record over-sampled ethernet RX data for debugging
      eth_rx_oversample_drive(7 downto 6) <= eth_rxd_in;
      eth_rx_oversample_drive(5 downto 0) <= eth_rx_oversample_drive(7 downto 2);
      eth_rx_oversample <= eth_rx_oversample_drive;
      
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
        when "11" =>
          eth_txd_delayed(1 downto 0) <= eth_txd;
          eth_txen_delayed(0) <= eth_txen;
        when others =>
          eth_txd_delayed(1 downto 0) <= eth_txd;
          eth_txen_delayed(0) <= eth_txen;
      end case;
    end if;
  end process;
  
  process(clock50mhz) is
    variable frame_length : unsigned(10 downto 0);
  begin
    if rising_edge(clock50mhz) then

      if (rxbuff_id_ethside /= rxbuff_id_ethside_last)
        or (rxbuff_id_cpuside /= rxbuff_id_cpuside_last) then
        report "rxbuff_id_ethside=" & integer'image(rxbuff_id_ethside)
          & ", rxbuff_id_cpuside=" & integer'image(rxbuff_id_cpuside);

        rxbuff_id_ethside_last <= rxbuff_id_ethside;
        rxbuff_id_cpuside_last <= rxbuff_id_cpuside;
      end if;
      
      if eth_mode_100='1' then
        eth_dibit_strobe <= '1';
      else
        -- 10mbit mode: do eth actions at 1/10th rate
        eth_dibit_strobe <= eth_10mbit_strobe(0);
        eth_10mbit_strobe(8 downto 0) <= eth_10mbit_strobe(9 downto 1);
        eth_10mbit_strobe(9) <= eth_10mbit_strobe(0);
      end if;

      rxbuffer_write_toggle_drive <= rxbuffer_write_toggle;
      if (last_rxbuffer_write_toggle /= rxbuffer_write_toggle_drive) then
        last_rxbuffer_write_toggle <= rxbuffer_write_toggle;
        rxbuffer_write_drive <= (others => '0');
        if rxbuff_id_ethside /= rxbuff_id_cpuside then
          rxbuffer_write_drive(rxbuff_id_ethside) <= '1';
        end if;
        rxbuffer_wdata_l_drive <= rxbuffer_wdata;
        rxbuffer_writeaddress_l_drive <= rxbuffer_writeaddress;
        eth_rx_write_count <= eth_rx_write_count + 1;
      -- Buffer gets marked as occupied when we finish receiving the frame.
      -- so nothing to do here.
      else
        rxbuffer_write_drive <= (others => '0');
      end if;     
      rxbuffer_write <= rxbuffer_write_drive;
      rxbuffer_wdata_l <= rxbuffer_wdata_l_drive;
      rxbuffer_writeaddress_l <= rxbuffer_writeaddress_l_drive;
      
      -- Cross-domain latch the reset signals
      reset_50mhz <= reset_50mhz_drive;
      reset_50mhz_drive <= reset;
      eth_soft_reset_50mhz_drive <= eth_soft_reset;
      eth_soft_reset_50mhz <= eth_soft_reset_50mhz_drive;
      eth_reset_int_50mhz_drive <= eth_reset_int;
      eth_reset_int_50mhz <= eth_reset_int_50mhz_drive;
      
      -- Double flip-flop latch the eth_tx_trigger
      eth_tx_trigger_50mhz_drive <= eth_tx_trigger_drive;
      eth_tx_trigger_50mhz <= eth_tx_trigger_50mhz_drive;
          
      eth_txd_phase_drive <= eth_txd_phase;
      eth_rx_latch_phase_drive <= eth_rx_latch_phase;
      
      eth_rxd <= eth_rxd_latched;
      eth_rxdv <= eth_rxdv_latched;
      eth_rxdv_last <= eth_rxdv;
      eth_rxdv_last2 <= eth_rxdv_last;
      
      -- Register ethernet data lines and data valid signal
      eth_txd <= eth_txd_int;
      eth_txen <= eth_txen_int;
      
      -- We separate the RX/TX FSMs to allow true full-duplex operation.
      -- For now it is upto the user to ensure the 0.96us gap between packets.
      -- This is only 20 CPU cycles, so it is unlikely to be a problem.
      
      -- Beacon counter
      if (eth_remote_control = '1') and (eth_load_enable = '1') and (eth_send_beacon = '0') and (eth_beacon_timer_count > 0) then
        eth_beacon_timer_count <= eth_beacon_timer_count - 1;
      end if;

      -- Ethernet TX FSM
      if eth_tx_state = Idle then
        eth_tx_idle <= '1';
      else
        eth_tx_idle <= '0';
      end if;

      if eth_dibit_strobe='1' then
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
            if eth_tx_trigger_50mhz = '0' then
              eth_tx_complete <= '0';
            end if;

            -- reset beacon timer if we sent a beacon packet before
            if eth_send_beacon='1' then
              eth_send_beacon <= '0';
              eth_beacon_timer_count <= 50000000;
            end if;

            -- XXX Try having TXD be ready for preamble, to see if that
            -- fixes the weird problem with packet loss due to wrong preamble length.
            eth_txd_int <= "01";
            
            if eth_tx_trigger_50mhz = '1' then
              
              -- reset frame padding state
              eth_tx_padding <= '0';
              if to_integer(eth_tx_size)<60 then
                eth_tx_size_padded <= to_unsigned(60,12);
              else
                eth_tx_size_padded <= eth_tx_size;
              end if;
              -- begin transmission
              tx_frame_count <= tx_frame_count + 1;
              eth_tx_commenced <= '1';
              eth_tx_complete <= '0';
              -- 56 bits of preamble = 28 dibits.
              -- We add a few extra just to make sure.
              tx_preamble_count <= tx_preamble_length;
              eth_txen_int <= '1';
              eth_txd_int <= "01";
              eth_tx_state <= WaitBeforeTX;
              eth_tx_viciv <= '0';
              eth_tx_dump <= '0';
            elsif false and (activity_dump='1') and activity_dump_ready_toggle /= last_activity_dump_ready_toggle then
              -- start sending an IPv6 multicast packet containing the compressed
              -- video or CPU instruction trace.
              report "ETHERDUMP: Sending next packet ("
                & std_logic'image(activity_dump_ready_toggle) & " vs " &
                std_logic'image(last_activity_dump_ready_toggle) & ")"
                severity note;
              last_activity_dump_ready_toggle <= activity_dump_ready_toggle;
              dumpram_raddr <= (not activity_dump_ready_toggle) & "00000000000";
              eth_tx_commenced <= '1';
              eth_tx_complete <= '0';
              tx_preamble_count <= tx_preamble_length;
              eth_txen_int <= '1';
              eth_txd_int <= "01";
              eth_tx_state <= WaitBeforeTX;
              eth_tx_viciv <= '0';
              eth_tx_dump <= '1';
            elsif false and (eth_videostream='1') and (activity_dump='0') and (buffer_moby_toggle /= last_buffer_moby_toggle) then            
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
              tx_preamble_count <= tx_preamble_length;
              eth_txen_int <= '1';
              eth_txd_int <= "01";
              eth_tx_state <= WaitBeforeTX;
              eth_tx_viciv <= '1';
              eth_tx_dump <= '0';
            elsif (eth_remote_control = '1') and (eth_load_enable = '1') 
                   and (eth_send_beacon = '0') and (eth_beacon_timer_count = 0) then
              eth_send_beacon <= '1';
              -- Send beacon packet
              report "Sending beacon packet";
              eth_tx_commenced <= '1';
              eth_tx_complete <= '0';
              tx_preamble_count <= tx_preamble_length;
              eth_txen_int <= '1';
              eth_txd_int <= "01";
              eth_tx_state <= WaitBeforeTX;
              eth_tx_viciv <= '0';
              eth_tx_dump <= '0';
            end if;
          when WaitBeforeTX =>
            if eth_tx_packet_count /= "111111" then
              eth_tx_packet_count <= eth_tx_packet_count + 1;
            else
              eth_tx_packet_count <= "000000";
            end if;           
            
            txbuffer_readaddress <= 0;
            eth_tx_state <= SendingPreamble;
            report "Reseting TX CRC";
            tx_fcs_crc_load_init <= '1';
            report "TX CRC init not announcing data";
            tx_fcs_crc_d_valid <= '0';
            tx_fcs_crc_calc_en <= '0';
          when SendingPreamble =>
            if tx_preamble_count = 0 then
              eth_txd_int <= "11";
              eth_tx_state <= SendingFrame;
              eth_tx_bit_count <= 0;
              txbuffer_readaddress <= txbuffer_readaddress + 1;
              tx_fcs_crc_load_init <= '0';
              report "Releasing TX CRC init";
              tx_fcs_crc_d_valid <= '1';
              tx_fcs_crc_calc_en <= '1';
              report "TX CRC announcing input";
              if eth_tx_viciv='0' and eth_tx_dump='0' and eth_send_beacon='0' then
                eth_tx_bits <= txbuffer_rdata;
                tx_fcs_crc_data_in <= std_logic_vector(txbuffer_rdata);
                report "Feeding TX CRC $" & to_hstring(txbuffer_rdata);
              elsif eth_send_beacon='1' then
                -- sending first byte
                eth_tx_bits <= beaconbuffer_rdata;
                tx_fcs_crc_data_in <= std_logic_vector(beaconbuffer_rdata);
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
            report "TX CRC no input";
            eth_txd_int <= eth_tx_bits(1 downto 0);
            if eth_tx_bit_count = 6 then
              -- Prepare to send from next byte
              eth_tx_bit_count <= 0;
              tx_fcs_crc_d_valid <= '1';
              tx_fcs_crc_calc_en <= '1';
              report "TX CRC announcing input";
              if eth_tx_dump='1' then
                if txbuffer_readaddress < video_packet_header'length then
                  report "FRAMEPACKER: Sending packet header byte " & integer'image(txbuffer_readaddress) & " = $" & to_hstring(unsigned(video_packet_header(txbuffer_readaddress)));
                  eth_tx_bits <= unsigned(video_packet_header(txbuffer_readaddress));
                  tx_fcs_crc_data_in <= video_packet_header(txbuffer_readaddress);
                else
                  report "ETHERDUMP: Sending byte " & integer'image(txbuffer_readaddress - video_packet_header'length) & " = $" & to_hstring(dumpram_rdata) & " dumpram_raddr=$" & to_hstring(dumpram_raddr);
                  eth_tx_bits <= unsigned(dumpram_rdata);
                  tx_fcs_crc_data_in <= dumpram_rdata;
                end if;              
              elsif eth_send_beacon='1' then
                eth_tx_bits <= beaconbuffer_rdata;
                tx_fcs_crc_data_in <= std_logic_vector(beaconbuffer_rdata);
              elsif eth_tx_viciv='0' then
                if eth_tx_padding = '1' then
                  report "PADDING: writing padding byte @ "
                    & integer'image(txbuffer_readaddress) & " (and adding to CRC)";
                  tx_fcs_crc_data_in <= x"00";
                  eth_tx_bits <= x"00";
                else
                  report "ETHTX: writing actual byte $"
                    & to_hstring(txbuffer_rdata) & 
                    " @ "
                    & integer'image(txbuffer_readaddress) & " (and adding to CRC)";
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
              
              if (eth_tx_dump='1')
                and ((to_unsigned(txbuffer_readaddress,12) /=
                      (2048 + video_packet_header'length - 1)) and allow_2k_log_frames='1')
                and ((to_unsigned(txbuffer_readaddress,12) /=
                      (1024 + video_packet_header'length - 1)) and allow_2k_log_frames='0')
              then
                -- Not yet at end of CPU/BUS log dump, so advance read address
                -- pointer for dump buffer
                txbuffer_readaddress <= txbuffer_readaddress + 1;
                if txbuffer_readaddress = eth_tx_size then
                  eth_tx_padding <= '1';
                end if;
                report "ETHERDUMP: txbuffer_readaddress = $" & to_hstring(to_unsigned(txbuffer_readaddress,12));
                if (to_unsigned(txbuffer_readaddress,12) >= video_packet_header'length) then
                  dumpram_raddr(10 downto 0) <= std_logic_vector(to_unsigned(txbuffer_readaddress - video_packet_header'length,11));
                  report "ETHERDUMP: dumpram_raddr = $" & to_hstring(dumpram_raddr);
                else
                  dumpram_raddr(10 downto 0) <= std_logic_vector(to_unsigned(0,11));
                end if;
              elsif (eth_send_beacon='1') and (to_unsigned(txbuffer_readaddress,12) /= 68) then
                -- sending next byte
                txbuffer_readaddress <= txbuffer_readaddress + 1;
              elsif ((eth_tx_dump='0') and (eth_tx_viciv='0') and (eth_send_beacon='0')
                     and (to_unsigned(txbuffer_readaddress,12) /= eth_tx_size_padded))
                or
                ((eth_tx_viciv='1')
                 and ((to_unsigned(txbuffer_readaddress,12) /=
                       (2048 + video_packet_header'length - 1)) and allow_2k_log_frames='1')
                 and ((to_unsigned(txbuffer_readaddress,12) /=
                       (1024 + video_packet_header'length - 1)) and allow_2k_log_frames='0')
                 )
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
                report "TX CRC not announcing data";
                tx_fcs_crc_d_valid <= '0';
                tx_fcs_crc_calc_en <= '0';
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
              eth_txd_int(0) <= eth_tx_crc_bits(31);
              eth_txd_int(1) <= eth_tx_crc_bits(30);
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
            if eth_tx_trigger_50mhz='0' or eth_tx_viciv = '1' or eth_tx_dump='1' then
              eth_tx_commenced <= '0';
              eth_tx_state <= IdleWait;
            end if;
          when others =>
            eth_tx_state <= IdleWait;
        end case;
      end if;
      
      -- Allow resetting of the ethernet TX state machine
      if eth_reset_int_50mhz='0' or reset_50mhz='0' or eth_soft_reset_50mhz='0' then
        eth_tx_state <= Idle;
        eth_txen_int <= '0';
        eth_txd_int <= "11";        
        eth_tx_viciv <= '0';
        eth_tx_dump <= '0';
      end if;
      
      frame_length := to_unsigned(eth_frame_len,11);
      
      if eth_dibit_strobe='1' or debug_rx='1' then
        case eth_state is
          when Idle =>
            if debug_rx = '1' then
              eth_frame_len <= 0;
              eth_state <= DebugRxFrameWait;
            end if;
            rx_keyinput <= '1';
            if eth_rxdv='1' then
              -- start receiving frame
              report "CRC: Frame carrier detected";
              eth_state <= WaitingForPreamble;
              rx_fcs_crc_load_init <= '1';
              rx_fcs_crc_d_valid <= '0';
              -- Start at +2, so we have somewhere to put frame length after
              eth_frame_len <= 2;
              eth_mac_counter <= 0;
              eth_bit_count <= 0;
              -- Only decide on frame rejection at the beginning of the frame
              -- to avoid starting writing half frames to the rx buffer in
              -- case the cpu frees up a buffer in the middle of reception
              eth_rx_blocked_50mhz <= eth_rx_blocked;
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
            rxbuffer_write_toggle <= not rxbuffer_write_toggle;
            rxbuffer_wdata <= eth_rx_oversample;
--          rxbuffer_wdata(7) <= eth_rxdv;
--          rxbuffer_wdata(6) <= eth_rxer;
--          rxbuffer_wdata(5) <= eth_interrupt;
--          rxbuffer_wdata(1 downto 0) <= eth_rxd;
            if eth_frame_len /= 2047 then
              eth_frame_len <= eth_frame_len + 1;
            end if;
            if eth_frame_len = 2047 then
              eth_state <= DebugRxFrameDone;
              rxbuffer_end_of_packet_toggle <= not rxbuffer_end_of_packet_toggle;
            end if;
          when DebugRxFrameDone =>
            if debug_rx = '0' then
              eth_state <= Idle;
            end if;
          when WaitingForPreamble =>
            rx_fcs_crc_load_init <= '0';
            -- 10mbit ethernet preamble with the MEGA65 R3 board chipset
            -- suppresses the high-bit of all but the very last di-bit of the
            -- preamble. So we wait until we see the first 01.
            if eth_rxd = "01" then
              report "ETHRX: Preamble has started";
              eth_state <= ReceivingPreamble;
            end if;
            if eth_rxdv='0' then
              eth_state <= Idle;
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
            if (eth_rxdv='0') and (eth_rxdv_last='0') and (eth_rxdv_last2='0') then
              report "ETHRX: Ethernet carrier has stopped.";
              -- finished receiving frame
              -- subtract two length field bytes to
              -- obtain actual number of bytes received
              eth_frame_len <= eth_frame_len - 2;
              eth_wait <= 20;
              eth_state <= ReceivedFrameWait;
              -- Veto packet reception if no free RX buffers
              if eth_rx_blocked_50mhz = '0' then              
                -- put a marker at the end of the frame so we can see where it stops in
                -- the RX buffer.
                rxbuffer_write_toggle <= not rxbuffer_write_toggle;
                rxbuffer_wdata <= x"EA";
                rxbuffer_writeaddress <= eth_frame_len;
              end if;
            else
              -- got two more bits
--            report "ETHRX: Received bits from RMII: "
--              & to_string(std_logic_vector(eth_rxd));
              if eth_bit_count = 6 then
                -- this makes a byte
                if frame_length(10 downto 0) = "11111111000" then
                  -- frame too long -- ignore the rest
                  -- (max frame length = 2048 - 2 length bytes - 4 CRC bytes = 2042 bytes
                  null;
                else
                  report "ETHRX: eth_frame_len = " & integer'image(eth_frame_len);
                  if eth_mac_counter /= 7 then
                    eth_mac_counter <= eth_mac_counter + 1;
                  end if;
                  if eth_mac_counter = 0 then
                    report "ETHRX: First byte is $" & to_hstring(eth_rxd & eth_rxbits);
                    frame_is_multicast <= eth_rxbits(0);
                    if eth_rxbits(0) = '0' then
                      report "ETHRX: Frame is not multicast";
                    else
                      report "ETHRX: Frame is multicast";
                    end if;
                    if (eth_rxbits /= "111111") or (eth_rxd /= "11") then
                      frame_is_broadcast <= '0';
                      report "ETHRX: Frame is not broadcast (MAC byte 0 = $" & to_hstring( eth_rxd & eth_rxbits )
                        & " (should be $FF)";
                      report "ETHRX: bits = " & to_string(std_logic_vector(eth_rxd)) & to_string(std_logic_vector(eth_rxbits));
                    else
                      frame_is_broadcast <= '1';
                    end if;
                    if (eth_rxd & eth_rxbits) /= eth_mac(47 downto 40) then
                      frame_is_for_me <= '0';
                      report "ETHRX: Frame is not address to me (my MAC is "
                        & to_hstring(eth_mac(47 downto 40)) & ":"
                        & to_hstring(eth_mac(39 downto 32)) & ":"
                        & to_hstring(eth_mac(31 downto 24)) & ":"
                        & to_hstring(eth_mac(23 downto 16)) & ":"
                        & to_hstring(eth_mac(15 downto 8)) & ":"
                        & to_hstring(eth_mac(7 downto 0)) & "). But it might still be a broadcast frame.";
                    else
                      frame_is_for_me <= '1';
                    end if;
                    eth_mac_shift <= eth_mac(39 downto 0);
                  elsif eth_mac_counter < 6 then
                    report "ETHRX: subsequent MAC byte is $" & to_hstring(eth_rxd & eth_rxbits);
                    if eth_rxbits /= "111111" or eth_rxd /= "11" then
                      frame_is_broadcast <= '0';
                      if frame_is_broadcast = '1' then
                        report "ETHRX: Frame is not broadcast.";
                      end if;
                    end if;
                    if (eth_rxd & eth_rxbits) /= eth_mac_shift(39 downto 32) then
                      frame_is_for_me <= '0';
                      if frame_is_for_me = '1' then
                        report "ETHRX: Frame is not address to me ("
                          & to_hstring(eth_mac(47 downto 40)) & " :"
                          & to_hstring(eth_mac(39 downto 32)) & " :"
                          & to_hstring(eth_mac(31 downto 24)) & " :"
                          & to_hstring(eth_mac(23 downto 16)) & " :"
                          & to_hstring(eth_mac(15 downto 8)) & " :"
                          & to_hstring(eth_mac(7 downto 0)) & ").";
                      end if;
                    end if;
                    eth_mac_shift(39 downto 8) <= eth_mac_shift(31 downto 0);
                  elsif eth_mac_counter = 6 then
                    report "ETHRX: Got target MAC. Frame is:"
                      & " for_me=" & std_logic'image(frame_is_for_me)
                      & ", broadcast=" & std_logic'image(frame_is_broadcast)
                      & ", multicast=" & std_logic'image(frame_is_multicast);
                  end if;
                  eth_frame_len <= eth_frame_len + 1;

                  -- Veto packet reception if no free RX buffers
                  if eth_rx_blocked_50mhz = '0' then                  
                    rxbuffer_write_toggle <= not rxbuffer_write_toggle;
                    report "ETHRX: Received byte $" & to_hstring(eth_rxd & eth_rxbits);
                    rxbuffer_wdata <= eth_rxd & eth_rxbits;
                    rxbuffer_writeaddress <= eth_frame_len;
                  end if;

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
                  if rx_keyinput='1' and ((eth_videostream='1' and activity_dump='0') or (eth_remote_control='1')) then
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
                  -- help debug ethernet key reception by making 111th byte visible
                  -- also show whether we accepted the magic packet or not etc
                  if to_integer(frame_length(10 downto 0)) = 111 then
                    eth_byte_100 <= eth_rxd & eth_rxbits;
                    eth_key_debug(2) <= eth_remote_control;
                    eth_key_debug(1) <= rx_keyinput;
                    eth_key_debug(0) <= eth_videostream;
                    eth_key_debug(6) <= eth_keycode_toggle_internal;
                  end if;
                  if to_integer(frame_length(10 downto 0)) = 101 then
                    eth_key_debug(3) <= rx_keyinput;
                  end if;
                  if to_integer(frame_length(10 downto 0)) = 102 then
                    eth_key_debug(4) <= rx_keyinput;
                  end if;
                  if to_integer(frame_length(10 downto 0)) = 103 then
                    eth_key_debug(5) <= rx_keyinput;
                  end if;
                  if to_integer(frame_length(10 downto 0)) = 110 then
                    eth_key_debug(7) <= rx_keyinput;
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
          when ReceivedFrameWait =>
            if eth_wait /= 0 then
              eth_wait <= eth_wait - 1;
            else
              eth_state <= ReceivedFrame;
            end if;
          when ReceivedFrame =>
            rx_fcs_crc_d_valid <= '0';
            rx_fcs_crc_calc_en <= '0';

            -- Veto packet reception if no free RX buffers
            if eth_rx_blocked_50mhz = '0' then
              -- write low byte of frame length
              rxbuffer_writeaddress <= 0;
              rxbuffer_write_toggle <= not rxbuffer_write_toggle;
              rxbuffer_wdata <= to_unsigned(eth_frame_len,8);
            end if;
            report "ETHRX: writing eth_frame_len = " & integer'image(eth_frame_len);
            eth_wait <= 20;
            eth_state <= ReceivedFrame2Wait;
          when ReceivedFrame2Wait =>
            if eth_wait /= 0 then
              eth_wait <= eth_wait - 1;
            else
              eth_state <= ReceivedFrame2;
            end if;
          when ReceivedFrame2 =>
            -- write high byte of frame length + crc failure status
            -- bit 7 is high if CRC fails, else is low.
            report "ETHRX: writing packet length at " & integer'image(rxbuffer_writeaddress);
            report "ETHRX: Recording crc_valid = " & std_logic'image(rx_crc_valid) & "   (CRC = $"& to_hstring(rx_crc_reg)&")";
            -- Veto packet reception if no free RX buffers
            if eth_rx_blocked_50mhz = '0' then
              rxbuffer_write_toggle <= not rxbuffer_write_toggle;
              rxbuffer_writeaddress <= 1;
              rxbuffer_wdata(7) <= not rx_crc_valid;
              rxbuffer_wdata(6) <= frame_is_for_me;
              rxbuffer_wdata(5) <= frame_is_broadcast;
              rxbuffer_wdata(4) <= frame_is_multicast;
              rxbuffer_wdata(3) <= '0';
              rxbuffer_wdata(2 downto 0) <= frame_length(10 downto 8);
            end if;
            if rx_crc_valid='1' or eth_disable_crc_check='1' then
              -- record that we have received a frame, but only if there was no
              -- CRC error.
              report "ETHRX: Considering frame against filter criteria";
              if ((frame_is_multicast and eth_accept_multicast)='1')
                or ((frame_is_broadcast and eth_accept_broadcast)='1') 
                or (frame_is_for_me='1') or (eth_mac_filter='0') then
                report "ETHRX: Frame accepted: Toggling eth_rx_buffer_last_used_50mhz";
                eth_state <= PostRxDelay;
                post_rx_countdown <= 15;
              else
                report "ETHRX: Frame does not match filter.";
                eth_state <= Idle;
              end if;
            else
              eth_state <= Idle;            
            end if;
          when PostRxDelay =>
            -- This state makes sure we commit the packet length to the correct buffer
            -- before marking the buffer as received.
            if post_rx_countdown /= 0 then
              post_rx_countdown <= post_rx_countdown - 1;
            else
              -- Mark frame as finished, i.e., accepted
              -- Veto packet reception if no free RX buffers
              if eth_rx_blocked_50mhz = '0' then
                rxbuffer_end_of_packet_toggle <= not rxbuffer_end_of_packet_toggle;
              end if;
              eth_state <= Idle;
            end if;
          when others =>
            null;
        end case;
      end if;
    end if;
  end process;

  
  process (clock,fastio_addr,fastio_wdata,fastio_read,fastio_write,rxbuffer_write_toggle,
           rxbuffer_wdata,rxbuffer_writeaddress,ethernet_cs,
           eth_tx_idle_cpuside,eth_rx_blocked,eth_remote_control,eth_rxdv,eth_rxd,eth_reset_int,
           eth_irqenable_rx,eth_irqenable_tx,eth_irq_rx,eth_irq_tx,eth_videostream,eth_rx_buffers_free,
           eth_tx_size,eth_rx_buffer_inuse,eth_mac_filter,eth_disable_crc_check,eth_txd_phase,
           eth_accept_broadcast,eth_accept_multicast,eth_rx_latch_phase,miim_register,miim_phyid,
           miim_read_value,eth_mac,eth_offset_fail,eth_byte_100,eth_key_debug,rxbuff_id_cpuside,
           rxbuff_id_ethside,eth_debug_select,rx_rotate_count,rxbuffer_end_of_packet_toggle_drive,
           last_rxbuffer_end_of_packet_toggle,eth_tx_state,tx_frame_count
           ) is
    variable temp_cmd : unsigned(7 downto 0);
  begin

    fastio_rdata <= (others => 'Z');
    
    if fastio_read='1' then
--      report "MEMORY: Reading from fastio";

      if ethernet_cs='1' then
--        report "MEMORY: Reading from ethernet register block";
        case fastio_addr(3 downto 0) is
          -- @IO:GS ETH:$D6E0 Ethernet control
          when x"0" =>
            -- @IO:GS $D6E0.7 ETH:TXIDLE Ethernet transmit side is idle, i.e., a packet can be sent.
            fastio_rdata(7) <= eth_tx_idle_cpuside;
            -- @IO:GS $D6E0.6 ETH:RXBLKD Indicate if ethernet RX is blocked until RX buffers freed
            fastio_rdata(6) <= eth_rx_blocked;
            -- @IO:GS $D6E0.4 ETH:RCENABLED (read only) Ethernet remote control enable status
            fastio_rdata(4) <= eth_remote_control;
            -- @IO:GS $D6E0.3 ETH:DRXDV Read ethernet RX data valid (debug)
            fastio_rdata(3) <= eth_rxdv;
            -- @IO:GS $D6E0.2 ETH:DRXD Read ethernet RX bits currently on the wire
            -- @IO:GS $D6E0.1 ETH:TXRST Write 0 to hold ethernet controller transmit sub-system under reset
            fastio_rdata(2 downto 1) <= eth_rxd;
            -- @IO:GS $D6E0.0 ETH:RST Write 0 to hold ethernet controller under reset
            fastio_rdata(0) <= eth_reset_int;
          -- @IO:GS $D6E1 - Ethernet interrupt and control register
          -- (unused bits = 0 to allow expansion of number of RX buffer slots
          -- from 2 to something bigger)
          when x"1" =>
            -- @IO:GS $D6E1.7 ETH:RXQEN Enable ethernet RX IRQ
            fastio_rdata(7) <= eth_irqenable_rx;
            -- @IO:GS $D6E1.6 ETH:TXQEN Enable ethernet TX IRQ
            fastio_rdata(6) <= eth_irqenable_tx;
            -- @IO:GS $D6E1.5 ETH:RXQ Ethernet RX IRQ status
            fastio_rdata(5) <= eth_irq_rx;
            -- @IO:GS $D6E1.4 ETH:TXQ Ethernet TX IRQ status
            fastio_rdata(4) <= eth_irq_tx;
            -- @IO:GS $D6E1.3 ETH:STRM Enable streaming of CPU instruction stream or VIC-IV display on ethernet
            fastio_rdata(3) <= eth_videostream;
            -- @IO:GS $D6E1.1-2 ETH:RXBF Number of free receive buffers
            if eth_rx_buffers_free < 3 then
              fastio_rdata(2 downto 1) <= to_unsigned(eth_rx_buffers_free,2);
            else
              fastio_rdata(2 downto 1) <= "11"; -- At least 3 RX buffers free
            end if;
          -- $D6E1.0 - RESERVED
          -- @IO:GS $D6E2 ETH:TXSZLSB TX Packet size (low byte)
          when x"2" =>
            fastio_rdata <= eth_tx_size(7 downto 0);
          -- @IO:GS $D6E3 ETH:TXSZMSB TX Packet size (high byte)
          -- $D6E3.4-7 ETH:DBGRXBFLGS occupancy state of RX buffers 0 to 3 (read only) (DEBUG ONLY. DEPRECATED. WILL be replaced)
          when x"3" =>
            fastio_rdata(7 downto 4) <= eth_rx_buffer_inuse(3 downto 0);
            fastio_rdata(3 downto 0) <= eth_tx_size(11 downto 8);
          -- $D6E4 ETH:RXBUFCOUNT Returns number of ethernet RX buffers on this system (read only) 
          when x"4"  =>
            fastio_rdata <= to_unsigned(num_buffers,8);
          when x"5" =>
            -- @IO:GS $D6E5.0 ETH:NOPROM Ethernet disable promiscuous mode
            fastio_rdata(0) <= eth_mac_filter;
            -- @IO:GS $D6E5.1 ETH:NOCRC Disable CRC check for received packets
            fastio_rdata(1) <= eth_disable_crc_check;
            -- @IO:GS $D6E5.2-3 ETH:TXPH Ethernet TX clock phase adjust
            fastio_rdata(3 downto 2) <= eth_txd_phase;
            -- @IO:GS $D6E5.4 ETH:BCST Accept broadcast frames
            fastio_rdata(4) <= eth_accept_broadcast;
            -- @IO:GS $D6E5.5 ETH:MCST Accept multicast frames
            fastio_rdata(5) <= eth_accept_multicast;
            -- @IO:GS $D6E5.6-7 ETH:RXPH Ethernet RX clock phase adjust
            fastio_rdata(7 downto 6) <= eth_rx_latch_phase;
          when x"6" =>
            -- @IO:GS $D6E6.0-4 ETH:MIIMREG Ethernet MIIM register number
            -- @IO:GS $D6E6.7-5 ETH:MIIMPHY Ethernet MIIM PHY number (use 0 for Nexys4, 1 for MEGA65 r1 PCBs)
            fastio_rdata(4 downto 0) <= miim_register;
            fastio_rdata(7 downto 5) <= miim_phyid(2 downto 0);
          when x"7" =>
            -- @IO:GS $D6E7 ETH:MIIMVLSB Ethernet MIIM register value (LSB)
            fastio_rdata <= miim_read_value(7 downto 0);
          when x"8" =>
            -- @IO:GS $D6E8 ETH:MIIMVMSB Ethernet MIIM register value (MSB)
            fastio_rdata <= miim_read_value(15 downto 8);
          -- @IO:GS $D6E9 ETH:MACADDR1@MACADDRX Ethernet MAC address
          -- @IO:GS $D6EA ETH:MACADDR2 @MACADDRX
          -- @IO:GS $D6EB ETH:MACADDR3 @MACADDRX
          -- @IO:GS $D6EC ETH:MACADDR4 @MACADDRX
          -- @IO:GS $D6ED ETH:MACADDR5 @MACADDRX
          -- @IO:GS $D6EE ETH:MACADDR6 @MACADDRX
          when x"9" =>
            if eth_disable_crc_check='0' then
              fastio_rdata <= eth_mac(47 downto 40);
            else 
              fastio_rdata <= eth_offset_fail;
            end if;
          when x"A" =>
            if eth_disable_crc_check='0' then
              fastio_rdata <= eth_mac(39 downto 32);
            else
              fastio_rdata <= eth_byte_100;
            end if;
          when x"B" =>
            if eth_disable_crc_check='0' then
              fastio_rdata <= eth_mac(31 downto 24);
            else
              fastio_rdata <= eth_key_debug;
            end if;
          when x"C" =>
            -- XXX Allow debug reading of rxbuff positions
            if eth_disable_crc_check='0' then
              fastio_rdata <= eth_mac(23 downto 16);
            else
              fastio_rdata <= to_unsigned(rxbuff_id_cpuside,8);
              fastio_rdata(7) <= eth_remote_control;
            end if;
          when x"D" => fastio_rdata <= eth_mac(15 downto 8);
          when x"E" =>
            if eth_disable_crc_check='0' then
              fastio_rdata <= eth_mac(7 downto 0);
            else
              fastio_rdata <= to_unsigned(rxbuff_id_ethside,8);
            end if;
          when x"f" =>
            case eth_debug_select is
              when x"00" =>
                -- @ IO:GS $D6EF ETH:DBGRXWCOUNT DEBUG show number of writes to eth RX buffer
                fastio_rdata(1 downto 0) <= to_unsigned(rxbuff_id_cpuside,2);
                fastio_rdata(3 downto 2) <= to_unsigned(rxbuff_id_ethside,2);
                fastio_rdata(5 downto 4) <= rx_rotate_count(1 downto 0);
                fastio_rdata(7) <= rxbuffer_end_of_packet_toggle_drive;
                fastio_rdata(6) <= last_rxbuffer_end_of_packet_toggle;
              when x"01" =>
                -- @ IO:GS $D6EF ETH:DBGTXSTAT DEBUG show current ethernet TX state
                fastio_rdata <= to_unsigned(ethernet_state'pos(eth_tx_state),8);
              when x"02" =>
                -- @ IO:GS $D6EF ETH:DBGTXSTAT DEBUG show current ethernet TX state
                fastio_rdata <= tx_frame_count;
              when others =>
                fastio_rdata <= x"FF";
            end case;                
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

      if last_ack_rx_frame_toggle /= ack_rx_frame_toggle then
        last_ack_rx_frame_toggle <= ack_rx_frame_toggle;
        rx_rotate_count <= rx_rotate_count + 1;
        
        -- Give time for signals to propagate between attempts.
        -- This also helps to make sure we don't get successive write
        -- glitching, when M65 CPU sometimes writes to an address for 2
        -- cycles instead of one.
        
        -- Advance to next buffer, if there are any
        -- It is vitally important that the cpu and eth side buffers
        -- never be allowed to co-incide. Thus the extra safety straps
        -- here.
        if rxbuff_id_cpuside_plus1 = rxbuff_id_ethside then
          -- No more waiting packets: Point the CPU to the buffer just
          -- before where the ethernet side is writing to.
          if rxbuff_id_ethside /= 0 then
            rxbuff_id_cpuside <= rxbuff_id_ethside - 1;
          else
            rxbuff_id_cpuside <= num_buffers - 1;
          end if;
        else
          if rxbuff_id_cpuside /= (num_buffers-1) then
            if rxbuff_id_ethside /= (rxbuff_id_cpuside + 1) then
              rxbuff_id_cpuside <= rxbuff_id_cpuside + 1;
            end if;
          else
            if rxbuff_id_ethside /= 0 then
              rxbuff_id_cpuside <= 0;
            end if;
          end if;
        end if;

      end if;

      
      -- Compute Ethernet RX buffer CS line state for reads
      rxbuffer_cs_vector <= (others => '0');
      rxbuffer_cs_vector(rxbuff_id_cpuside) <= '1';
      
      if rxbuff_id_cpuside /= (num_buffers-1) then
        rxbuff_id_cpuside_plus1 <= rxbuff_id_cpuside + 1;
      else
        rxbuff_id_cpuside_plus1 <= 0;
      end if;

      -- Correctly compute the number of free RX buffers
      if rxbuff_id_ethside = rxbuff_id_cpuside then
        eth_rx_buffers_free <= 0;
        eth_rx_blocked <= '1';
      elsif rxbuff_id_cpuside > rxbuff_id_ethside then
        eth_rx_buffers_free <= rxbuff_id_cpuside - rxbuff_id_ethside;
        eth_rx_blocked <= '0';
      else
        eth_rx_buffers_free <= num_buffers + rxbuff_id_cpuside - rxbuff_id_ethside;
        eth_rx_blocked <= '0';
      end if;

      report integer'image(eth_rx_buffers_free) & " free RX buffers, CPU="
        & integer'image(rxbuff_id_cpuside)
        & ", ETH=" & integer'image(rxbuff_id_ethside)
        & ", CPU+1=" & integer'image(rxbuff_id_cpuside_plus1);
        
      
      if rxbuff_id_cpuside_plus1 = rxbuff_id_ethside then
        -- CPU has caught up, so there are no frames waiting, and thus we can
        -- release the RX IRQ. 
        eth_irq_rx <= '0';
      else
        -- Ethernet controller is ahead of the CPU, so assert RX IRQ
        eth_irq_rx <= '1';
      end if;
      
      -- De-glitch eth_tx_trigger before we push it to the 50MHz side
      eth_tx_trigger_drive <= eth_tx_trigger;
      
      -- Capture writes to the RX buffer from 50MHz side of clock.
      -- We process them here to avoid contention on the dual-ported
      -- memory used for the buffer, to try to fix the corruption we have been
      -- seeing.
      
      rxbuffer_end_of_packet_toggle_drive <= rxbuffer_end_of_packet_toggle;
      if (rxbuffer_end_of_packet_toggle = rxbuffer_end_of_packet_toggle_drive)
        and (last_rxbuffer_end_of_packet_toggle /= rxbuffer_end_of_packet_toggle_drive) then
        -- End of packet RX signalled
        last_rxbuffer_end_of_packet_toggle <= rxbuffer_end_of_packet_toggle;

        -- Now work out the next RX buffer to use.
        if rxbuff_id_ethside /= (num_buffers-1) then
          rxbuff_id_ethside <= rxbuff_id_ethside + 1;
        else
          rxbuff_id_ethside <= 0;
        end if;
        
      end if;

      -- Notice when we change raster lines
      if last_raster_number /= raster_number then
        last_raster_number <= raster_number;
        raster_toggle <= not raster_toggle;
      end if;
      
      eth_tx_idle_cpuside <= eth_tx_idle;

      beaconbuffer_write <= '0';

      if eth_videostream='1' and activity_dump='1' then
        report "ETHERDUMP: Logging FastIO bus activity, writing to $" & to_hstring(dumpram_waddr);
        -- Log PC and opcode to make it easier to match things up
        dumpram_wdata(23 downto 0) <= std_logic_vector(debug_vector(23 downto 0));
        -- Address and read/write signals of fastio IO bus, plus instruction strobe
        dumpram_wdata(51 downto 32) <= std_logic_vector(fastio_addr);
        dumpram_wdata(55) <= fastio_write;
        dumpram_wdata(54) <= d031_write_toggle;
        dumpram_wdata(53) <= instruction_strobe;
        dumpram_wdata(52) <= '0';  -- unused bit
        -- Whatever is being written
        dumpram_wdata(63 downto 56) <= std_logic_vector(fastio_wdata);
        
        dumpram_waddr <= std_logic_vector(to_unsigned(to_integer(unsigned(dumpram_waddr)) + 1,9));
        dumpram_write <= '1';
        -- 64bits wide = 8 bytes x 2^8 = 8*256 = 2K
        -- Some network cards etc can't handle such big packets, so allow an
        -- option to send smaller ones
        if allow_2k_log_frames='1' then
          activity_dump_ready_toggle <= dumpram_waddr(8); 
          if dumpram_waddr(7 downto 0) = "11110000" then
            -- Check if we are about to run out of buffer space
            if eth_tx_idle_cpuside = '0' then
              cpu_arrest_internal <= '1';
              report "ETHERDUMP: Arresting CPU";
            end if;
          end if;
        else
          activity_dump_ready_toggle <= dumpram_waddr(7);
          if dumpram_waddr(6 downto 0) = "1110000" then
            -- Check if we are about to run out of buffer space
            if eth_tx_idle_cpuside = '0' then
              cpu_arrest_internal <= '1';
              report "ETHERDUMP: Arresting CPU";
            end if;
          end if;
        end if;

      elsif instruction_strobe='1' and activity_dump='1' then
        report "ETHERDUMP: Instruction spotted: " & to_hstring(debug_vector) & ", writing to $" & to_hstring(dumpram_waddr);
        dumpram_wdata(63 downto 0) <= std_logic_vector(debug_vector(63 downto 0));
        -- dumpram_wdata(63) <= d031_write_toggle; -- find out which instructions
        --                                         -- are causing $D031 writes
        dumpram_waddr <= std_logic_vector(to_unsigned(to_integer(unsigned(dumpram_waddr)) + 1,9));
        dumpram_write <= '1';
        if allow_2k_log_frames='1' then
          activity_dump_ready_toggle <= dumpram_waddr(8);
          if dumpram_waddr(7 downto 0) = "11110000" then
            -- Check if we are about to run out of buffer space
            if eth_tx_idle_cpuside = '0' then
              cpu_arrest_internal <= '1';
              report "ETHERDUMP: Arresting CPU";
            end if;
          end if;          
        else
          activity_dump_ready_toggle <= dumpram_waddr(7);
          if dumpram_waddr(6 downto 0) = "1110000" then
            -- Check if we are about to run out of buffer space
            if eth_tx_idle_cpuside = '0' then
              cpu_arrest_internal <= '1';
              report "ETHERDUMP: Arresting CPU";
            end if;
          end if;
        end if;
      elsif ((raster_toggle /= last_raster_toggle) or (badline_toggle /= last_badline_toggle)) and (eth_videostream='1') then
        report "ETHERDUMP: Indicating rasterline advance";
        dumpram_wdata(23 downto 0) <= x"FFFFFF";   -- special marker for raster
                                                   -- information
        -- Are we reporting a raster line step?
        if (raster_toggle /= last_raster_toggle) then
          dumpram_wdata(63) <= '1';
        else
          dumpram_wdata(63) <= '0';
        end if;
        -- Are we reporting a badline?
        if (badline_toggle /= last_badline_toggle) then
          dumpram_wdata(62) <= '1';
        else
          dumpram_wdata(62) <= '0';
        end if;
        last_raster_toggle <= raster_toggle;
        last_badline_toggle <= badline_toggle;
        
        -- Report the VIC-IV physical raster number
        dumpram_wdata(35 downto 24) <= std_logic_vector(raster_number);
        -- Report the VIC-II raster number
        dumpram_wdata(47 downto 36) <= std_logic_vector(vicii_raster);
        -- Fill in other bits as zeroes
        dumpram_wdata(61 downto 48) <= (others => '0');

        dumpram_waddr <= std_logic_vector(to_unsigned(to_integer(unsigned(dumpram_waddr)) + 1,9));
        dumpram_write <= '1';
        if allow_2k_log_frames='1' then
          activity_dump_ready_toggle <= dumpram_waddr(8);
          if dumpram_waddr(7 downto 0) = "11110000" then
            -- Check if we are about to run out of buffer space
            if eth_tx_idle_cpuside = '0' then
              cpu_arrest_internal <= '1';
              report "ETHERDUMP: Arresting CPU";
            end if;
          end if;
        else
          activity_dump_ready_toggle <= dumpram_waddr(7);
          if dumpram_waddr(6 downto 0) = "1110000" then
            -- Check if we are about to run out of buffer space
            if eth_tx_idle_cpuside = '0' then
              cpu_arrest_internal <= '1';
              report "ETHERDUMP: Arresting CPU";
            end if;
          end if;
        end if;
      else
        dumpram_write <= '0';
      end if;
      if (cpu_arrest_internal='1') and ((eth_tx_idle_cpuside = '1') or (activity_dump='0') )then
        cpu_arrest_internal <= '0';
        report "ETHERDUMP: Resuming CPU";
      end if;
      cpu_arrest <= cpu_arrest_internal;
      
      miim_request <= '0';
      
      -- Automatically de-assert transmit trigger once the FSM has caught the signal.
      -- (but don't accidently de-assert when sending compressed video.)
      eth_tx_complete_drive <= eth_tx_complete;
      if (eth_tx_complete_drive = '1')
        and (eth_tx_viciv='0') and (eth_tx_dump='0') then
        eth_tx_trigger <= '0';
      end if;
      
      -- Bring signals accross from 50MHz side as required
      -- (pass through some flip-flops to manage meta-stability)
      eth_tx_toggle_int2 <= eth_tx_toggle_int1;
      eth_tx_toggle_int1 <= eth_tx_toggle_50mhz;

      -- Update module status based on register reads
      if fastio_read='1' then
        if fastio_addr(19 downto 0) = x"DE000" then
          null;
        end if;
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
        irq <= '1';
      end if;

      if fastio_write='0' then
        txbuffer_write <= '0';          
      else
        if (fastio_addr(19 downto 11)&"000" = x"DE8")
          or (fastio_addr(19 downto 11)&"000" = x"D28")
        then
          -- Writing to TX buffer
          -- (we don't need toclear the write lines, as noone else can write to
          -- the buffer.  The TX buffer cannot be read, as reading the same
          -- addresses reads from the RX buffer.)
          -- But we do it anyway, since we are seeing funny problems with
          -- packet corruption on TX side, where wrong data arrives, but the
          -- ethernet CRC is still fine.
          -- @IO:GS $FFDE800 - $FFDEFFF Ethernet TX buffer (write only)
          -- @IO:GS $FFDE800 - $FFDEFFF Ethernet RX buffer (read only)
          txbuffer_writeaddress <= to_integer(fastio_addr(10 downto 0));
          txbuffer_write <= '1';
          txbuffer_wdata <= fastio_wdata;
        else
          txbuffer_write <= '0';          
        end if;
        if ethernet_cs='1' then
          case fastio_addr(3 downto 0) is
            when x"0" =>
              -- @IO:GS $D6E0.0 Clear to reset ethernet PHY and state machine
              -- @IO:GS $D6E0.1 Clear to reset ethernet state machine only, but not the phy
              eth_reset <= fastio_wdata(0);
              eth_reset_int <= fastio_wdata(0);
              eth_soft_reset <= fastio_wdata(1);
              if fastio_wdata(0) = '0' or fastio_wdata(1) = '0' then
                -- Reset RX buffer state: CPU viewing buffer 0,
                -- other buffers free. Eth writing to n+1
                rxbuff_id_ethside <= 1;
                rxbuff_id_cpuside <= 0;
                eth_rx_blocked <= '0';
              end if;
              
            when x"1" =>
              -- $D6E1 100mbit ethernet irq mask
              -- $D6E1.7 100mbit ethernet enable RX IRQ
              eth_irqenable_rx <= fastio_wdata(7);
              -- $D6E1.7 100mbit ethernet enable TX done IRQ
              eth_irqenable_tx <= fastio_wdata(6);
              -- Writing here also clears any current interrupts
              report "ETHRX: Clearing IRQ";

              -- @IO:GS $D6E1.3 Enable real-time video streaming via ethernet (or fast IO bus if CPU/bus monitoring enabled)
              eth_videostream <= fastio_wdata(3);
              -- @IO:GS $D6E1.2 WRITE ONLY Enable real-time CPU/BUS monitoring via ethernet
              activity_dump <= fastio_wdata(2);
              
              -- @IO:GS $D6E1.1 WRITE ONLY Access next received ethernet frame
              last_rx_rotate_bit <= fastio_wdata(1);
              if fastio_wdata(1) = '1' and last_rx_rotate_bit = '0' then
                -- Request next RX'd packet (if any)
                ack_rx_frame_toggle <= not ack_rx_frame_toggle;

              end if;

            -- @IO:GS $D6E1.0 RESERVED
            -- @IO:GS $D6E2 Set low-order size of frame to TX
            when x"2" =>
              eth_tx_size(7 downto 0) <= fastio_wdata;
            -- @IO:GS $D6E3 Set high-order size of frame to TX
            when x"3" =>
              eth_tx_size(11 downto 8) <= fastio_wdata(3 downto 0);
            -- @IO:GS $D6E4 ETH:COMMAND Ethernet command register (write only)
            when x"4" =>
              case fastio_wdata is
                when x"00" =>
                  -- @IO:GS $00 ETHCOMMAND:STOPTX Immediately stop transmitting the current ethernet frame.  Will cause a partially sent frame to be received, most likely resulting in the loss of that frame.  
                  eth_tx_trigger <= '0';
                when x"01" =>
                  -- @IO:GS $01 ETHCOMMAND:STARTTX Transmit packet
                  eth_tx_trigger <= '1';
                  eth_irq_tx <= '0';                  
                when x"10" =>
                  eth_mode_100 <= '0';
                when x"11" =>
                  eth_mode_100 <= '1';
                when x"12" =>
                -- Reserved for gigabit mode selection
                when x"13" =>
                -- Reserved for 10-gigabit mode selection
                when x"dc" =>
                  -- @IO:GS $DC ETHCOMMAND:DEBUGCPU Select CPU debug stream via ethernet when \$D6E1.3 is set
                  cpu_ethernet_stream <= '1';
                when x"d4" =>
                  -- @IO:GS $D4 ETHCOMMAND:DEBUGVIC Select VIC-IV debug stream via ethernet when \$D6E1.3 is set
                  cpu_ethernet_stream <= '0';
                when x"de" => -- debug rx
                  -- @IO:GS $DE ETHCOMMAND:RXONLYONE Receive exactly one ethernet frame only, and keep all signals states (for debugging ethernet sub-system)
                  debug_rx <= '1';
                when x"d0" =>
                  -- @IO:GS $D0 ETHCOMMAND:RXNORMAL Disable the effects of RXONLYONE
                  debug_rx <= '0';
                when x"f1" =>
                  -- @IO:GS $F1 ETHCOMMAND:FRAME1K Select ~1KiB frames for video/cpu debug stream frames (for receivers that do not support MTUs of greater than 2KiB)
                  allow_2k_log_frames <= '0';
                when x"f2" =>
                  -- @IO:GS $F2 ETHCOMMAND:FRAME2K Select ~2KiB frames for video/cpu debug stream frames, for optimal performance.
                  allow_2k_log_frames <= '1';
                when others =>
                  null;
              end case;
            when x"5" =>
              -- @IO:GS $D6E5.0 Enable of filtering unicast frames if MAC address does not match.
              eth_mac_filter <= fastio_wdata(0);
              -- @IO:GS $D6E5.1 Disable CRC checking of broadcast ethernet frames
              eth_disable_crc_check <= fastio_wdata(1);
              -- @IO:GS $D6E5.2-3 Ethernet TX clock phase adjust
              eth_txd_phase <= fastio_wdata(3 downto 2);
              -- @IO:GS $D6E5.6-7 Ethernet RX clock phase adjust
              eth_rx_latch_phase <= fastio_wdata(7 downto 6);
              -- @IO:GS $D6E5.4 Enable accepting of broadcast ethernet frames
              -- @IO:GS $D6E5.5 Enable accepting of unicast ethernet frames
              eth_accept_broadcast <= fastio_wdata(4);
              eth_accept_multicast <= fastio_wdata(5);
            when x"6" =>
              miim_request <= '1';
              miim_write <= '0';
              miim_register <= fastio_wdata(4 downto 0);
              miim_phyid(2 downto 0) <= fastio_wdata(7 downto 5);
            when x"7" =>
              miim_write_value(7 downto 0) <= fastio_wdata;
            when x"8" =>
              miim_request <= '1';
              miim_write <= '1';
              miim_write_value(15 downto 8) <= fastio_wdata;
            when x"9" => eth_mac(47 downto 40) <= fastio_wdata;
            when x"A" => eth_mac(39 downto 32) <= fastio_wdata;
            when x"B" => eth_mac(31 downto 24) <= fastio_wdata;
            when x"C" => eth_mac(23 downto 16) <= fastio_wdata;
            when x"D" => eth_mac(15 downto 8) <= fastio_wdata;
            when x"E" => eth_mac(7 downto 0) <= fastio_wdata;
            when x"f" =>
              if fastio_wdata(7 downto 6) = "11" then
                tx_preamble_length <= to_integer(fastio_wdata(5 downto 0));
              else
                eth_debug_select <= fastio_wdata;
              end if;
            when others =>
              -- Other registers do nothing
              null;
          end case;
          if fastio_addr(3 downto 0) >= x"9" and fastio_addr(3 downto 0) <= x"E" then
            -- Update the ethernet MAC address in the beacon buffer
            -- This will automatically update the IPv6 destination address accordingly
            -- (as the IPv6 destination address is derived from the MAC address)
            -- The IPv6 UDP checksum will also be updated automatically.
            -- These updates and calculations are done in the beacon buffer during the 
            -- cycles following the last mac address update.
            -- All other bytes in the beacon buffer except the src MAC address bytes 
            -- are write-protected.
            beaconbuffer_waddr <= to_integer(fastio_addr(3 downto 0)) - 3; -- src mac address is in bytes 6 to 11 in beacon ram
            beaconbuffer_wdata <= fastio_wdata;
            beaconbuffer_write <= '1';
          end if;
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
