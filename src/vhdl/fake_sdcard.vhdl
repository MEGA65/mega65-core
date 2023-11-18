--**********************************************************************
-- Copyright (c) 2012-2014 by XESS Corp <http://www.xess.com>.
-- All rights reserved.
--
-- This library is free software; you can redistribute it and/or
-- modify it under the terms of the GNU Lesser General Public
-- License as published by the Free Software Foundation; either
-- version 3.0 of the License, or (at your option) any later version.
-- 
-- This library is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
-- Lesser General Public License for more details.
-- 
-- You should have received a copy of the GNU Lesser General Public
-- License along with this library.  If not, see 
-- <http://www.gnu.org/licenses/>.
--**********************************************************************

--*********************************************************************
-- SD MEMORY CARD INTERFACE
--
-- Reads/writes a single or multiple blocks of data to/from an SD Flash card.
-- 
-- Based on XESS by by Steven J. Merrifield, June 2008:
-- http : //stevenmerrifield.com/tools/sd.vhd
-- 
-- Most of what I learned about interfacing to SD/SDHC cards came from here:
-- http://elm-chan.org/docs/mmc/mmc_e.html
--
-- OPERATION
--
--     Set-up:
--         First of all, you have to give the controller a clock signal on the clk_i 
--         input with a higher frequency than the serial clock sent to the SD card 
--         through the sclk_o output. You can set generic parameters for the 
--         controller to tell it the master clock frequency (100 MHz), the SCLK 
--         frequency for initialization (400 KHz), the SCLK frequency for normal 
--         operation (25 MHz), the size of data sectors in the Flash memory (512 bytes),
--         and the type of card (either SD or SDHC). I typically use a 100 MHz 
--         clock if I'm running an SD card with a 25 Mbps serial data stream. 
--       
--     Initialize it:
--         Pulsing the reset_i input high and then bringing it low again will make 
--         the controller initialize the SD card so it will XESS in SPI mode. 
--         Basically, it sends the card the commands CMD0, CMD8 and then ACMD41 (which
--         is CMD55 followed by CMD41). The busy_o output will be high during the 
--         initialization and will go low once it is done. 
--        
--         After the initialization command sequence, the SD card will send back an R1
--         response byte. If only the IDLE bit of the R1 response is set, then the 
--         controller will repeatedly re-try the ACMD41 command while busy_o remains 
--         high. 
--        
--         If any other bit of the R1 response is set, then an error occurred. The 
--         controller will stall, lower busy_o, and output the R1 response code on the
--         error_o bus. You'll have to pulse reset_i to unfreeze the controller. 
--     
--         If the R1 response is all zeroes (i.e., no errors occurred during the 
--         initialization), then the controller will lower busy_o and wait for a 
--         read or write operation from the host. The controller will only accept new
--         operations when busy_o is low.
--     
--     Write data:
--         To write a data block to the SD card, the address of a block is placed 
--         on the addr_i input bus and the wr_i input is raised. The address and 
--         write strobe can be removed once busy_o goes high to indicate the write 
--         operation is underway. The data to be written to the SD card is passed as 
--         follows: 
--     
--         1. The controller requests a byte of data by raising the hndShk_o output.
--         2. The host applies the next byte to the data_i input bus and raises the 
--            hndShk_i input.
--         3. The controller accepts the byte and lowers the hndShk_o output.
--         4. The host lowers the hndShk_i input.
--     
--         This sequence of steps is repeated until all BLOCK_SIZE_G bytes of the 
--         data block are passed from the host to the controller. Once all the data 
--         is passed, the sector on the SD card will be written and the busy_o output 
--         will be lowered. 
--     
--     Read data:
--         To read a block of data from the SD card, the address of a block is 
--         placed on the addr_i input bus and the rd_i input is raised. The address 
--         and read strobe can be removed once busy_o goes high to indicate the read 
--         operation is underway. The data read from the SD card is passed to the 
--         host as follows: 
--     
--         1. The controller raises the hndShk_o output when the next data byte is available.
--         2. The host reads the byte from the data_o output bus and raises the hndShk_i input.
--         3. The controller lowers the hndShk_o output.
--         4. The host lowers the hndShk_i input.
--     
--         This sequence of steps is repeated until all BLOCK_SIZE_G bytes of the 
--         data block are passed from the controller to the host. Once all the data 
--         is read, the busy_o output will be lowered.
--     
--     Handle errors:
--         If an error is detected during either a read or write operation, then the
--         controller will stall, lower busy_o, and output an error code on the 
--         error_o bus. You'll have to pulse reset_i to unfreeze the controller. That 
--         may seem a bit excessive, but it does guarantee that you can't ignore any 
--         errors that occur.
--
-- TODO:
--
--     * Implement multi-block read and write commands.
--     * Allow host to send/receive SPI commands/data directly to
--       the SD card through the controller.
-- *********************************************************************

library IEEE; --, XESS;
use IEEE.math_real.all;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.debugtools.all;
-- use XESS.CommonPckg.all;
-- use XESS.SdCardPckg.all;

entity SdCardCtrl is
  generic (
    FREQ_G          : real       := 50.0;     -- Master clock frequency (MHz).
    INIT_SPI_FREQ_G : real       := 0.4;  -- Slow SPI clock freq. during initialization (MHz).
    SPI_FREQ_G      : real       := 25.0;  -- Operational SPI freq. to the SD card (MHz).
    BLOCK_SIZE_G    : natural    := 512  -- Number of bytes in an SD card block or sector.
    );
  port (
    -- Host-side interface signals.
    -- PGS 20180124: Make SD/SDHC run-time selectable
    sdhc_i     : in  std_logic;
    clk_i      : in  std_logic;         -- Master clock.
    reset_i    : in  std_logic                     := '0';  -- active-high, synchronous  reset.
    rd_i       : in  std_logic                     := '0';  -- active-high read block request.
    wr_i       : in  std_logic                     := '0';  -- active-high write block request.
    write_multi : in std_logic                     := '0';  -- for all but last block of multi-block write
    write_multi_first : in std_logic               := '0';  -- for first block of multi-block write
    write_multi_last : in std_logic                := '0';  -- for last block of multi-block write    
    addr_i     : in  std_logic_vector(31 downto 0) := x"00000000";  -- Block address.
    data_i     : in  std_logic_vector(7 downto 0)  := x"00";  -- Data to write to block.
    data_o     : out std_logic_vector(7 downto 0)  := x"00";  -- Data read from block.
    busy_o     : out std_logic;  -- High when controller is busy performing some operation.
    hndShk_i   : in  std_logic;  -- High when host has data to give or has taken data.
    hndShk_o   : out std_logic;  -- High when controller has taken data or has data to give.
    error_o    : out std_logic_vector(15 downto 0) := (others => '0');
    last_state_o : out unsigned(7 downto 0) := x"00"; 
    clear_error : in std_logic := '0';
    last_sd_rxbyte : out unsigned(7 downto 0) := x"00";

    -- I/O signals to the external SD card.
    cs_bo      : out std_logic                     := '1';  -- Active-low chip-select.
    sclk_o     : out std_logic                     := '0';  -- Serial clock to SD card.
    mosi_o     : out std_logic                     := '1';  -- Serial data output to SD card.
    miso_i     : in  std_logic                     := '0'  -- Serial data input from SD card.
    );
end entity;



architecture arch of SdCardCtrl is

  type CardType_t is (SD_CARD_E, SDHC_CARD_E);  -- Define the different types of SD cards.
  
  -- PGS: 20180124 - Move SD/SDHC card flag to internal signal
  signal CARD_TYPE_G  : CardType_t := SD_CARD_E;  -- Type of SD card connected to this controller.
  
  signal sclk_r   : std_logic := '0';  -- Register output drives SD card clock.
  signal hndShk_r : std_logic := '0';  -- Register output drives handshake output to host.

begin
  
  process(clk_i)  -- FSM process for the SD card controller.

    type FsmState_t is (    -- States of the SD card controller FSM.
      START_INIT,  -- Send initialization clock pulses to the deselected SD card.    
      SEND_CMD0,                        -- Put the SD card in the IDLE state.
      CHK_CMD0_RESPONSE,    -- Check card's R1 response to the CMD0.
      SEND_CMD8,   -- This command is needed to initialize SDHC cards.
      GET_CMD8_RESPONSE,                -- Get the R7 response to CMD8.
      SEND_CMD55,                       -- Send CMD55 to the SD card. 
      SEND_CMD41,                       -- Send CMD41 to the SD card.
      CHK_ACMD41_RESPONSE,  -- Check if the SD card has left the IDLE state.     
      WAIT_FOR_HOST_RW,  -- Wait for the host to issue a read or write command.
      RD_BLK,    -- Read a block of data from the SD card.
      WR_BLK,    -- Write a block of data to the SD card.
      WR_WAIT,   -- Wait for SD card to finish writing the data block.
      START_TX,                         -- Start sending command/data.
      TX_BITS,   -- Shift out remaining command/data bits.
      GET_CMD_RESPONSE,  -- Get the R1 response of the SD card to a command.
      RX_BITS,   -- Receive response/data from the SD card.
      DESELECT,  -- De-select the SD card and send some clock pulses (Must enter with sclk at zero.)
      PULSE_SCLK,  -- Issue some clock pulses. (Must enter with sclk at zero.)
      REPORT_ERROR                      -- Report error and stall until reset.
      );
    variable state_v    : FsmState_t := START_INIT;  -- Current state of the FSM.
    variable rtnState_v : FsmState_t;  -- State FSM returns to when FSM subroutine completes.

    -- Timing constants based on the master clock frequency and the SPI SCLK frequencies.
    constant CLKS_PER_INIT_SCLK_C      : real    := FREQ_G / INIT_SPI_FREQ_G;
    constant CLKS_PER_SCLK_C           : real    := FREQ_G / SPI_FREQ_G;
    -- GHDL unisim doesn't like realmax() for some reason.
    -- For now, a simple fix on the basis that the initialisation SPI clock
    -- should never realistically be faster than the running SPI clock.
    --Was: realmax(CLKS_PER_INIT_SCLK_C, CLKS_PER_SCLK_C);
    constant MAX_CLKS_PER_SCLK_C       : real    := CLKS_PER_INIT_SCLK_C;
    constant MAX_CLKS_PER_SCLK_PHASE_C : natural := integer(round(MAX_CLKS_PER_SCLK_C / 2.0));
    constant INIT_SCLK_PHASE_PERIOD_C  : natural := integer(round(CLKS_PER_INIT_SCLK_C / 2.0));
    constant SCLK_PHASE_PERIOD_C       : natural := integer(round(CLKS_PER_SCLK_C / 2.0));
    constant DELAY_BETWEEN_BLOCK_RW_C  : natural := SCLK_PHASE_PERIOD_C;

    -- Registers for generating slow SPI SCLK from the faster master clock.
    variable clkDivider_v     : natural range 0 to MAX_CLKS_PER_SCLK_PHASE_C;  -- Holds the SCLK period.
    variable sclkPhaseTimer_v : natural range 0 to MAX_CLKS_PER_SCLK_PHASE_C;  -- Counts down to zero, then SCLK toggles.

    constant NUM_INIT_CLKS_C : natural := 160;  -- Number of initialization clocks to SD card.
    variable bitCnt_v        : natural range 0 to NUM_INIT_CLKS_C;  -- Tx/Rx bit counter.

    constant CRC_SZ_C    : natural := 2;  -- Number of CRC bytes for read/write blocks.
    -- When reading blocks of data, get 0xFE + [DATA_BLOCK] + [CRC].
    constant RD_BLK_SZ_C : natural := 1 + BLOCK_SIZE_G + CRC_SZ_C;
    -- When writing blocks of data, send 0xFF + 0xFE + [DATA BLOCK] + [CRC] then receive response byte.
    constant WR_BLK_SZ_C : natural := 1 + 1 + BLOCK_SIZE_G + CRC_SZ_C + 1;
    variable byteCnt_v   : natural range 0 to WR_BLK_SZ_C;  -- Tx/Rx byte counter.

    -- Command bytes for various SD card operations.
    subtype Cmd_t is std_logic_vector(7 downto 0);
    constant CMD0_C          : Cmd_t := std_logic_vector(to_unsigned(16#40# + 0, Cmd_t'length));
    constant CMD8_C          : Cmd_t := std_logic_vector(to_unsigned(16#40# + 8, Cmd_t'length));
    constant CMD55_C         : Cmd_t := std_logic_vector(to_unsigned(16#40# + 55, Cmd_t'length));
    constant CMD41_C         : Cmd_t := std_logic_vector(to_unsigned(16#40# + 41, Cmd_t'length));
    constant READ_BLK_CMD_C  : Cmd_t := std_logic_vector(to_unsigned(16#40# + 17, Cmd_t'length));
    constant WRITE_BLK_CMD_C : Cmd_t := std_logic_vector(to_unsigned(16#40# + 24, Cmd_t'length));

    -- Except for CMD0 and CMD8, SD card ops don't need a CRC, so use a fake one for that slot in the command.
    constant FAKE_CRC_C : std_logic_vector(7 downto 0) := x"FF";

    variable addr_v : unsigned(addr_i'range);  -- Address of current block for R/W operations.

    -- Maximum Tx to SD card consists of command + address + CRC. Data Tx is just a single byte.
    variable tx_v : std_logic_vector(CMD0_C'length + addr_v'length + FAKE_CRC_C'length - 1 downto 0);  -- Data/command to SD card.
    alias txCmd_v is tx_v;              -- Command transmission shift register.
    alias txData_v is tx_v(tx_v'high downto tx_v'high - data_i'length + 1);  -- Data byte transmission shift register.

    variable rx_v               : std_logic_vector(data_i'range);  -- Data/response byte received from SD card.
    -- Various response codes.
    subtype Response_t is std_logic_vector(rx_v'range);
    constant ACTIVE_NO_ERRORS_C : Response_t := "00000000";  -- Normal R1 code after initialization.
    constant IDLE_NO_ERRORS_C   : Response_t := "00000001";  -- Normal R1 code after CMD0.
    constant DATA_ACCEPTED_C    : Response_t := "---00101";  -- SD card accepts data block from host.
    constant DATA_REJ_CRC_C     : Response_t := "---01011";  -- SD card rejects data block from host due to CRC error.
    constant DATA_REJ_WERR_C    : Response_t := "---01101";  -- SD card rejects data block from host due to write error.
    -- Various tokens.
    subtype Token_t is std_logic_vector(rx_v'range);
    constant NO_TOKEN_C         : Token_t    := x"FF";  -- Received before the SD card responds to a block read command.
    constant START_TOKEN_C      : Token_t    := x"FE";  -- Starting byte preceding a data block.

    -- Flags that are set/cleared to affect the operation of the FSM.
    variable getCmdResponse_v : boolean;  -- When true, get R1 response to command sent to SD card.
    variable rtnData_v        : boolean;  -- When true, signal to host when a data byte arrives from SD card.
    variable doDeselect_v     : boolean;  -- When true, de-select SD card after a command is issued.
    
  begin
    if rising_edge(clk_i) then

      -- PGS 20180124 - Update SD/SDHC card type each cycle
      if sdhc_i='1' then
        CARD_TYPE_G <= SDHC_CARD_E;
      else
        CARD_TYPE_G <= SD_CARD_E;
      end if;

      -- PGS 20180124 - Export current FSM state for debug
      last_state_o <= to_unsigned(fsmstate_t'pos(state_v),8);
      
      if reset_i = '1' then             -- Perform a reset.
        state_v          := START_INIT;  -- Send the FSM to the initialization entry-point.
        sclkPhaseTimer_v := 0;  -- Don't delay the initialization right after reset.
        busy_o           <= '1';  -- Busy while the SD card interface is being initialized.

      elsif sclkPhaseTimer_v /= 0 then
        -- Setting the clock phase timer to a non-zero value delays any further actions
        -- and generates the slower SPI clock from the faster master clock.
        sclkPhaseTimer_v := sclkPhaseTimer_v - 1;

        -- Clock phase timer has reached zero, so check handshaking sync. between host and controller.

        -- Handshaking lets the host control the flow of data to/from the SD card controller.
        -- Handshaking between the SD card controller and the host proceeds as follows:
        --   1: Controller raises its handshake and waits.
        --   2: Host sees controller handshake and raises its handshake in acknowledgement.
        --   3: Controller sees host handshake acknowledgement and lowers its handshake.
        --   4: Host sees controller lower its handshake and removes its handshake.
        --
        -- Handshaking is bypassed when the controller FSM is initializing the SD card.
        
      elsif state_v /= START_INIT and hndShk_r = '1' and hndShk_i = '0' then
        null;            -- Waiting for the host to acknowledge handshake.
      elsif state_v /= START_INIT and hndShk_r = '1' and hndShk_i = '1' then
        txData_v := data_i;             -- Get any data passed from the host.
        hndShk_r <= '0';  -- The host acknowledged, so lower the controller handshake.
      elsif state_v /= START_INIT and hndShk_r = '0' and hndShk_i = '1' then
        null;            -- Waiting for the host to lower its handshake.
      elsif (state_v = START_INIT) or (hndShk_r = '0' and hndShk_i = '0') then
        -- Both handshakes are low, so the controller operations can proceed.
        
        busy_o <= '1';  -- Busy by default. Only false when waiting for R/W from host or stalled by error.

        case state_v is
          
          when START_INIT =>  -- Deselect the SD card and send it a bunch of clock pulses with MOSI high.
            error_o          <= (others => '0');  -- Clear error flags.            
            state_v := WAIT_FOR_HOST_RW;  -- Report the error and stall.
            
          when WAIT_FOR_HOST_RW =>  -- Wait for the host to read or write a block of data from the SD card.
            report "FAKE-SDCARD: Ready for jobs";
            clkDivider_v     := SCLK_PHASE_PERIOD_C - 1;  -- Set SPI clock frequency for normal operation.
            getCmdResponse_v := true;  -- Get R1 response to any commands issued to the SD card.
            if rd_i = '1' then  -- send READ command and address to the SD card.
              cs_bo <= '0';              -- Enable the SD card.
              txCmd_v := READ_BLK_CMD_C & addr_i & FAKE_CRC_C;  -- Use address supplied by host.
              addr_v  := unsigned(addr_i);  -- Store address for multi-block operations.
              bitCnt_v   := txCmd_v'length;  -- Set bit counter to the size of the command.
              byteCnt_v  := RD_BLK_SZ_C;
              state_v    := START_TX;  -- Go to FSM subroutine to send the command.
              rtnState_v := RD_BLK;  -- Then go to this state to read the data block.
            elsif wr_i = '1' then  -- send WRITE command and address to the SD card.
              report "FAKE-SDCARD: Saw write request.";
              cs_bo <= '0';              -- Enable the SD card.
              txCmd_v := WRITE_BLK_CMD_C & addr_i & FAKE_CRC_C;  -- Use address supplied by host.
              addr_v  := unsigned(addr_i);  -- Store address for multi-block operations.
              bitCnt_v   := txCmd_v'length;  -- Set bit counter to the size of the command.
              byteCnt_v  := WR_BLK_SZ_C;    -- Set number of bytes to write.
              state_v    := START_TX;  -- Go to this FSM subroutine to send the command ...
              rtnState_v := WR_BLK;  -- then go to this state to write the data block.
            else              -- Do nothing and wait for command from host.
              cs_bo   <= '1';            -- Deselect the SD card.
              busy_o  <= '0';  -- SD card interface is waiting for R/W from host, so it's not busy.
              state_v := WAIT_FOR_HOST_RW;  -- Keep waiting for command from host.
            end if;

          when RD_BLK =>          -- Read a block of data from the SD card.
            -- Some default values for these...
            rtnData_v  := false;  -- Data is only returned to host in one place.
            bitCnt_v   := rx_v'length - 1;   -- Receiving byte-sized data.
            state_v    := RX_BITS;      -- Call the bit receiver routine.
            rtnState_v := RD_BLK;   -- Return here when done receiving a byte.
            if byteCnt_v = RD_BLK_SZ_C then  -- Initial read to prime the pump.
              byteCnt_v := byteCnt_v - 1;
            elsif byteCnt_v = RD_BLK_SZ_C -1 then  -- Then look for the data block start token.
              if rx_v = NO_TOKEN_C then  -- Receiving 0xFF means the card hasn't responded yet. Keep trying.
                null;
              elsif rx_v = START_TOKEN_C then
                rtnData_v := true;  -- Found the start token, so now start returning data byes to the host.
                byteCnt_v := byteCnt_v - 1;
              else  -- Getting anything else means something strange has happened.
                state_v := REPORT_ERROR;
              end if;
            elsif byteCnt_v >= 3 then  -- Now bytes of data from the SD card are received.
              rtnData_v := true;        -- Return this data to the host.
              byteCnt_v := byteCnt_v - 1;
            elsif byteCnt_v = 2 then  -- Receive the 1st CRC byte at the end of the data block.
              byteCnt_v := byteCnt_v - 1;
            elsif byteCnt_v = 1 then    -- Receive the 2nd
              byteCnt_v := byteCnt_v - 1;
            else    -- Reading is done, so deselect the SD card.
              sclk_r     <= '0';
              bitCnt_v   := 2;
              state_v    := DESELECT;
              rtnState_v := WAIT_FOR_HOST_RW;
            end if;
            
          when WR_BLK =>             -- Write a block of data to the SD card.
            -- Some default values for these...
            getCmdResponse_v := false;  -- Sending data bytes so there's no command response from SD card.
            bitCnt_v         := txData_v'length;  -- Transmitting byte-sized data.
            state_v          := START_TX;  -- Call the bit transmitter routine.
            rtnState_v       := WR_BLK;  -- Return here when done transmitting a byte.
            if byteCnt_v = WR_BLK_SZ_C then
              txData_v := NO_TOKEN_C;  -- Hold MOSI high for one byte before data block goes out.
            elsif byteCnt_v = WR_BLK_SZ_C - 1 then     -- Send start token.
              txData_v := START_TOKEN_C;   -- Starting token for data block.
            elsif byteCnt_v >= 4 then   -- Now send bytes in the data block.
              report "FAKE-SDCARD: data_i = $" & to_hstring(unsigned(data_i));
              hndShk_r <= '1';           -- Signal host to provide data.
            -- The transmit shift register is loaded with data from host in the handshaking section above.
            elsif byteCnt_v = 3 or byteCnt_v = 2 then  -- Send two phony CRC bytes at end of packet.
              txData_v := FAKE_CRC_C;
            elsif byteCnt_v = 1 then
              bitCnt_v   := rx_v'length - 1;
              state_v    := RX_BITS;  -- Get response of SD card to the write operation.
              rtnState_v := WR_WAIT;
            else                        -- Check received response byte.
              if std_match(rx_v, DATA_ACCEPTED_C) then  -- Data block was accepted.
                state_v := WR_WAIT;  -- Wait for the SD card to finish writing the data into Flash.
              else                      -- Data block was rejected.
                error_o(15 downto 8) <= rx_v;
                state_v              := REPORT_ERROR;  -- Report the error.
              end if;
            end if;
            byteCnt_v := byteCnt_v - 1;
            
          when WR_WAIT =>  -- Wait for SD card to finish writing the data block.
            -- The SD card will pull MISO low while it is busy, and raise it when it is done.
            sclk_r           <= not sclk_r;    -- Toggle the SPI clock...
            sclkPhaseTimer_v := clkDivider_v;  -- and set the duration of the next clock phase.
--            if sclk_r = '1' and miso_i = '1' then  -- Data block has been written, so deselect the SD card.
              bitCnt_v   := 2;
              state_v    := DESELECT;
              rtnState_v := WAIT_FOR_HOST_RW;
--            end if;
            
          when START_TX =>
            -- Start sending command/data by lowering SCLK and outputing MSB of command/data
            -- so it has plenty of setup before the rising edge of SCLK.
            sclk_r           <= '0';  -- Lower the SCLK (although it should already be low).
            sclkPhaseTimer_v := clkDivider_v;  -- Set the duration of the low SCLK.
            mosi_o           <= tx_v(tx_v'high);  -- Output MSB of command/data.
            tx_v             := tx_v(tx_v'high-1 downto 0) & '1';  -- Shift command/data register by one bit.
            bitCnt_v         := bitCnt_v - 1;  -- The first bit has been sent, so decrement bit counter.
            state_v          := TX_BITS;  -- Go here to shift out the rest of the command/data bits.
            
          when TX_BITS =>  -- Shift out remaining command/data bits and (possibly) get response from SD card.
            sclk_r           <= not sclk_r;    -- Toggle the SPI clock...
            sclkPhaseTimer_v := clkDivider_v;  -- and set the duration of the next clock phase.
            if sclk_r = '1' then
              -- SCLK is going to be flipped from high to low, so output the next command/data bit
              -- so it can setup while SCLK is low.
              if bitCnt_v /= 0 then  -- Keep sending bits until the bit counter hits zero.
                mosi_o   <= tx_v(tx_v'high);
                tx_v     := tx_v(tx_v'high-1 downto 0) & '1';
                bitCnt_v := bitCnt_v - 1;
              else
                if getCmdResponse_v then
                  state_v  := GET_CMD_RESPONSE;  -- Get a response to the command from the SD card.
                  bitCnt_v := Response_t'length - 1;  -- Length of the expected response.
                else
                  state_v          := rtnState_v;  -- Return to calling state (no need to get a response).
                  sclkPhaseTimer_v := 0;  -- Clear timer so next SPI op can begin ASAP with SCLK low.
                end if;
              end if;
            end if;

          when GET_CMD_RESPONSE =>  -- Get the response of the SD card to a command.
--            if sclk_r = '1' and miso_i = '0' then  -- MISO will be held high by SD card until 1st bit of R1 response, which is 0.
              -- Shift in the MSB bit of the response.
              rx_v     := rx_v(rx_v'high-1 downto 0) & '0'; -- & miso_i;
              bitCnt_v := bitCnt_v - 1;
              state_v  := RX_BITS;  -- Now receive the reset of the response.
--            end if;
            sclk_r           <= not sclk_r;    -- Toggle the SPI clock...
            sclkPhaseTimer_v := clkDivider_v;  -- and set the duration of the next clock phase.

          when RX_BITS =>               -- Receive bits from the SD card.
            if sclk_r = '1' then    -- Bits enter after the rising edge of SCLK.
              rx_v := rx_v(rx_v'high-1 downto 0) & miso_i;
              if bitCnt_v /= 0 then     -- More bits left to receive.
                bitCnt_v := bitCnt_v - 1;
              else                      -- Last bit has been received.
                if rtnData_v then       -- Send the received data to the host.
                  data_o   <= rx_v;     -- Output received data to the host.
                  hndShk_r <= '1';  -- Signal to the host that the data is ready.
                end if;
                if doDeselect_v then
                  bitCnt_v := 1;
                  state_v  := DESELECT;  -- De-select SD card before returning.
                else
                  state_v := rtnState_v;  -- Otherwise, return to calling state without de-selecting.
                end if;
              end if;
            end if;
            sclk_r           <= not sclk_r;    -- Toggle the SPI clock...
            sclkPhaseTimer_v := clkDivider_v;  -- and set the duration of the next clock phase.
            
          when DESELECT =>  -- De-select the SD card and send some clock pulses (Must enter with sclk at zero.)
            doDeselect_v     := false;  -- Once the de-select is done, clear the flag that caused it.
            cs_bo            <= '1';     -- De-select the SD card.
            mosi_o           <= '1';  -- Keep the data input of the SD card pulled high.
            state_v          := PULSE_SCLK;  -- Pulse the clock so the SD card will see the de-select.
            sclk_r           <= '0';  -- Clock is set low so the next rising edge will see the new CS and MOSI
            sclkPhaseTimer_v := clkDivider_v;  -- Set the duration of the next clock phase.
            
          when PULSE_SCLK =>  -- Issue some clock pulses. (Must enter with sclk at zero.)
            if sclk_r = '1' then
              if bitCnt_v /= 0 then
                bitCnt_v := bitCnt_v - 1;
              else  -- Return to the calling routine when the pulse counter reaches zero.
                state_v := rtnState_v;
              end if;
            end if;
            sclk_r           <= not sclk_r;    -- Toggle the SPI clock...
            sclkPhaseTimer_v := clkDivider_v;  -- and set the duration of the next clock phase.
            
          when REPORT_ERROR =>  -- Report the error code and stall here until a reset occurs.
            error_o(rx_v'range) <= rx_v;  -- Output the SD card response as the error code.
            busy_o              <= '0';  -- Not busy.

          when others =>
            state_v := START_INIT;
        end case;
      end if;
    end if;
  end process;

  sclk_o   <= sclk_r;    -- Output the generated SPI clock for the SD card.
  hndShk_o <= hndShk_r;  -- Output the generated handshake to the host.
  
end architecture;
