-------------------------------------------------------------------------------
-- * Copyright (C) Paul Gardner-Stephen, Flinders University 2015
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
-------------------------------------------------------------------------------
-- * Portions COPYRIGHT (C) 2014, Digilent RO.
-- 
-- * This program is free software; distributed under the terms of BSD 3-clause
-- * license ("Revised BSD License", "New BSD License", or "Modified BSD License")
-- *
-- * Redistribution and use in source and binary forms, with or without modification,
-- * are permitted provided that the following conditions are met:
-- *
-- * 1. Redistributions of source code must retain the above copyright notice, this
-- *    list of conditions and the following disclaimer.
-- * 2. Redistributions in binary form must reproduce the above copyright notice,
-- *    this list of conditions and the following disclaimer in the documentation
-- *    and/or other materials provided with the distribution.
-- * 3. Neither the name(s) of the above-listed copyright holder(s) nor the names
-- *    of its contributors may be used to endorse or promote products derived
-- *    from this software without specific prior written permission.
-- *
-- * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
-- * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
-- * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
-- * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
-- * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
-- * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
-- * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;

entity ddrwrapper is
  port (
    -- Common
    cpuclock : in std_logic;
    clk_200MHz_i         : in    std_logic; -- 200 MHz system clock
    rst_i                : in    std_logic; -- active high system reset
    device_temp_i        : in    std_logic_vector(11 downto 0);
    ddr_state : out unsigned(7 downto 0);
    ddr_counter : out unsigned(7 downto 0);
    
    -- RAM interface
    ram_address          : in    std_logic_vector(26 downto 0);
    ram_write_data       : in    std_logic_vector(7 downto 0);
    ram_address_reflect  : out   std_logic_vector(26 downto 0);
    ram_write_reflect    : out    std_logic_vector(7 downto 0);
    ram_write_enable     : in    std_logic;
    ram_request_toggle   : in    std_logic;
    ram_done_toggle      : out   std_logic := '0';

    -- simple-dual-port cache RAM interface so that CPU doesn't have to read
    -- data cross-clock
    cache_address        : in std_logic_vector(8 downto 0);
    cache_read_data      : out std_logic_vector(150 downto 0);   
    
    -- DDR2 interface
    ddr2_addr            : out   std_logic_vector(12 downto 0);
    ddr2_ba              : out   std_logic_vector(2 downto 0);
    ddr2_ras_n           : out   std_logic;
    ddr2_cas_n           : out   std_logic;
    ddr2_we_n            : out   std_logic;
    ddr2_ck_p            : out   std_logic_vector(0 downto 0);
    ddr2_ck_n            : out   std_logic_vector(0 downto 0);
    ddr2_cke             : out   std_logic_vector(0 downto 0);
    ddr2_cs_n            : out   std_logic_vector(0 downto 0);
    ddr2_dm              : out   std_logic_vector(1 downto 0);
    ddr2_odt             : out   std_logic_vector(0 downto 0);
    ddr2_dq              : inout std_logic_vector(15 downto 0);
    ddr2_dqs_p           : inout std_logic_vector(1 downto 0);
    ddr2_dqs_n           : inout std_logic_vector(1 downto 0)
    );
end ddrwrapper;

architecture Behavioral of ddrwrapper is

------------------------------------------------------------------------
-- Component Declarations
------------------------------------------------------------------------

  component ram151x512
  PORT (
    clka : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(150 DOWNTO 0);
    clkb : IN STD_LOGIC;
    addrb : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(150 DOWNTO 0)
    );
  END component;
  
  component ddr
    port (
      -- Inouts
      ddr2_dq              : inout std_logic_vector(15 downto 0);
      ddr2_dqs_p           : inout std_logic_vector(1 downto 0);
      ddr2_dqs_n           : inout std_logic_vector(1 downto 0);
      -- Outputs
      ddr2_addr            : out   std_logic_vector(12 downto 0);
      ddr2_ba              : out   std_logic_vector(2 downto 0);
      ddr2_ras_n           : out   std_logic;
      ddr2_cas_n           : out   std_logic;
      ddr2_we_n            : out   std_logic;
      ddr2_ck_p            : out   std_logic_vector(0 downto 0);
      ddr2_ck_n            : out   std_logic_vector(0 downto 0);
      ddr2_cke             : out   std_logic_vector(0 downto 0);
      ddr2_cs_n            : out   std_logic_vector(0 downto 0);
      ddr2_dm              : out   std_logic_vector(1 downto 0);
      ddr2_odt             : out   std_logic_vector(0 downto 0);
      -- Inputs
      sys_clk_i            : in    std_logic;
      sys_rst              : in    std_logic;
      -- user interface signals
      app_addr             : in    std_logic_vector(26 downto 0);
      app_cmd              : in    std_logic_vector(2 downto 0);
      app_en               : in    std_logic;
      app_wdf_data         : in    std_logic_vector(127 downto 0);
      app_wdf_end          : in    std_logic;
      app_wdf_mask         : in    std_logic_vector(15 downto 0);
      app_wdf_wren         : in    std_logic;
      app_rd_data          : out   std_logic_vector(127 downto 0);
      app_rd_data_end      : out   std_logic;
      app_rd_data_valid    : out   std_logic;
      app_rdy              : out   std_logic;
      app_wdf_rdy          : out   std_logic;
      app_sr_req           : in    std_logic;
      app_sr_active        : out   std_logic;
      app_ref_req          : in    std_logic;
      app_ref_ack          : out   std_logic;
      app_zq_req           : in    std_logic;
      app_zq_ack           : out   std_logic;
      ui_clk               : out   std_logic;
      ui_clk_sync_rst      : out   std_logic;
      device_temp_i        : in    std_logic_vector(11 downto 0);
      init_calib_complete  : out   std_logic);
  end component;

------------------------------------------------------------------------
-- Local Type Declarations
------------------------------------------------------------------------
-- FSM
  type state_type is (stIdle,
                      stNormaliseRequest,stNormalisePreset, stNormaliseSetCmdRd, 
                      stRequest,stPreset, stSendData, stSetCmdRd, stSetCmdWr,
                      stRecentWriteRead,
                      stDone);

------------------------------------------------------------------------
-- Constant Declarations
------------------------------------------------------------------------
-- ddr commands
  constant CMD_WRITE         : std_logic_vector(2 downto 0) := "000";
  constant CMD_READ          : std_logic_vector(2 downto 0) := "001";

------------------------------------------------------------------------
-- Signal Declarations
------------------------------------------------------------------------
-- state machine
  signal cState, nState      : state_type; 

-- global signals
  signal mem_ui_clk          : std_logic;
  signal mem_ui_rst          : std_logic;
  signal rst                 : std_logic;
  signal rstn                : std_logic;
  signal sreg                : std_logic_vector(6 downto 0);

  signal ram_request_toggle_2 : std_logic := '0';
  signal ram_request_toggle_internal : std_logic := '0';
  signal last_ram_request_toggle : std_logic := '0';
  signal ram_address_held : std_logic_vector(26 downto 0);
  signal ram_address_internal : std_logic_vector(26 downto 0);
  signal ram_address_reflect_drive : std_logic_vector(26 downto 0);
  signal ram_write_data_internal : std_logic_vector(7 downto 0);
  signal ram_write_data_held : std_logic_vector(7 downto 0);
  signal ram_write_reflect_drive : std_logic_vector(7 downto 0);
  signal ram_write_enable_internal : std_logic;
  signal ram_write_enable_held : std_logic;

  signal cache_write_enable : std_logic := '0';
  signal cache_write_address : std_logic_vector(8 downto 0) := (others => '0');
  signal cache_write_data : std_logic_vector(150 downto 0);
  signal cache_read_data_drive : std_logic_vector(150 downto 0);

  signal recent_write_0 : std_logic_vector(31 downto 0);
  signal recent_write_1 : std_logic_vector(31 downto 0);
  signal recent_write_2 : std_logic_vector(31 downto 0);
  signal recent_write_3 : std_logic_vector(31 downto 0);
  
  signal ram_done_toggle_localclock : std_logic := '0';
  signal ram_read_data_localclock : std_logic_vector(7 downto 0);
  signal debug_counter_localclock : unsigned(7 downto 0) := x"00";
  signal ddr_state_localclock : unsigned(7 downto 0) := x"00";

  signal ddr_timeout : unsigned(7 downto 0);
  
  -- cache for 16 bytes we read at a time, to avoid wasting time with
  -- full requests for accesses in the same 16 bytes.
  -- (We also write to the cache when processing writes so that it stays
  -- consistent).
  -- XXX - We don't allow servicing reads from the cache while a write is
  -- in progress.
  signal last_ram_read_data_localclock : std_logic_vector(127 downto 0);

  
-- ddr user interface signals
  signal mem_addr            : std_logic_vector(26 downto 0); -- address for current request
  signal mem_cmd             : std_logic_vector(2 downto 0); -- command for current request
  signal mem_en              : std_logic; -- active-high strobe for 'cmd' and 'addr'
  signal mem_rdy             : std_logic;
  signal mem_wdf_rdy         : std_logic; -- write data FIFO is ready to receive data (wdf_rdy = 1 & wdf_wren = 1)
  signal mem_wdf_data        : std_logic_vector(127 downto 0);
  signal mem_wdf_end         : std_logic; -- active-high last 'wdf_data'
  signal mem_wdf_mask        : std_logic_vector(15 downto 0);
  signal mem_wdf_wren        : std_logic;
  signal mem_rd_data         : std_logic_vector(127 downto 0);
  signal mem_rd_data_end     : std_logic; -- active-high last 'rd_data'
  signal mem_rd_data_valid   : std_logic; -- active-high 'rd_data' valid
  signal calib_complete      : std_logic; -- active-high calibration complete

  signal debug_mode : std_logic := '0';
  
  attribute FSM_ENCODING              : string;
  attribute FSM_ENCODING of cState    : signal is "GRAY";

  attribute ASYNC_REG                 : string;
  attribute ASYNC_REG of sreg         : signal is "TRUE";

begin

------------------------------------------------------------------------
-- Declare cache RAM
------------------------------------------------------------------------
  cacheram0: ram151x512
    port map (
      clka => mem_ui_clk,
      wea(0) => cache_write_enable,
      addra => cache_write_address,
      dina => cache_write_data,
      clkb => cpuclock,
      addrb => cache_address,
      doutb => cache_read_data_drive);
  
------------------------------------------------------------------------
-- Registering the active-low reset for the MIG component
------------------------------------------------------------------------
  RSTSYNC: process(clk_200MHz_i)
  begin
    if rising_edge(clk_200MHz_i) then      
      sreg <= sreg(5 downto 0) & (not rst_i);
      rstn <= sreg(6);
    end if;
  end process RSTSYNC;

------------------------------------------------------------------------
-- Register output signals to CPU clock
------------------------------------------------------------------------
  process(cpuclock)
  begin
    if rising_edge(cpuclock) then
      -- Delay done toggle to next CPU clock cycle so that the data lines
      -- are definitely there first.
      ram_done_toggle <= ram_done_toggle_localclock;
      ddr_counter <= debug_counter_localclock;
      ddr_state <= ddr_state_localclock;
      cache_read_data <= cache_read_data_drive;
    end if;
  end process;
  

------------------------------------------------------------------------
-- DDR controller instance
------------------------------------------------------------------------
  Inst_DDR: ddr
    port map (
      ddr2_dq              => ddr2_dq,
      ddr2_dqs_p           => ddr2_dqs_p,
      ddr2_dqs_n           => ddr2_dqs_n,
      ddr2_addr            => ddr2_addr,
      ddr2_ba              => ddr2_ba,
      ddr2_ras_n           => ddr2_ras_n,
      ddr2_cas_n           => ddr2_cas_n,
      ddr2_we_n            => ddr2_we_n,
      ddr2_ck_p            => ddr2_ck_p,
      ddr2_ck_n            => ddr2_ck_n,
      ddr2_cke             => ddr2_cke,
      ddr2_cs_n            => ddr2_cs_n,
      ddr2_dm              => ddr2_dm,
      ddr2_odt             => ddr2_odt,
      -- Inputs
      sys_clk_i            => clk_200MHz_i,
      -- sys_rst              => rstn_3,
      sys_rst              => rstn,
      -- user interface signals
      app_addr             => mem_addr,
      app_cmd              => mem_cmd,
      app_en               => mem_en,
      app_wdf_data         => mem_wdf_data,
      app_wdf_end          => mem_wdf_end,
      app_wdf_mask         => mem_wdf_mask,
      app_wdf_wren         => mem_wdf_wren,
      app_rd_data          => mem_rd_data,
      app_rd_data_end      => mem_rd_data_end,
      app_rd_data_valid    => mem_rd_data_valid,
      app_rdy              => mem_rdy,
      app_wdf_rdy          => mem_wdf_rdy,
      app_sr_req           => '0',
      app_sr_active        => open,
      app_ref_req          => '0',
      app_ref_ack          => open,
      app_zq_req           => '0',
      app_zq_ack           => open,
      ui_clk               => mem_ui_clk,
      ui_clk_sync_rst      => mem_ui_rst,
      device_temp_i        => device_temp_i,
      init_calib_complete  => calib_complete);

------------------------------------------------------------------------
-- Registering all inputs of the state machine to 'mem_ui_clk' domain
------------------------------------------------------------------------
  REG_IN: process(mem_ui_clk)
  begin
    if rising_edge(mem_ui_clk) then

      ddr_state_localclock <= to_unsigned(state_type'pos(nState),8);
      
      ram_address_internal <= ram_address;
      ram_write_data_internal <= ram_write_data;
      -- Reflect memory write details to CPU so that it knows when we have it right.
      ram_address_reflect_drive <= ram_address_internal;
      ram_address_reflect <= ram_address_reflect_drive;
      ram_write_reflect_drive <= ram_write_data_internal;
      ram_write_reflect <= ram_write_reflect_drive;
      -- Delay memory access request toggle by an extra cycle to ensure that
      -- the address (and possibly data) lines have settled.
      -- Our clock here is only ~6.8ns, while CPU is 20ns.  So we need at least
      -- three cycle delay to allow for signal skew from the CPU.
      ram_request_toggle_2 <= ram_request_toggle;
      ram_request_toggle_internal <= ram_request_toggle_2;
      ram_write_enable_internal <= ram_write_enable;
      if mem_ui_rst = '1' then
        cState <= stIdle;
      else
        cState <= nState;
      end if;

      mem_wdf_wren <= '0';
      mem_wdf_end <= '0';
      mem_en <= '0';
      mem_cmd <= (others => '0');

      -- Note that the state machine has a 1 cycle delay to match the DDR2
      -- semantics.  This means that each state block will get executed twice,
      -- but toggling of acknowledgement lines needs to be done just once, so
      -- we do a short-circuit for the states when memory accesses end to make
      -- that happen, by assigning cState directly instead of via nState.
      nState <= cState;  -- by default keep the current state

      case (cState) is
        when stIdle =>
          if (ram_request_toggle_internal /= last_ram_request_toggle) then
            -- Give address lines time to settle with cross-clock transfer, so
            -- we don't capture them just yet.

            -- Also, since non-linear access seems to be what upsets things,
            -- and since we get stray writes, let's do a preliminary request that
            -- is definitely a read, and on the correct line of the DDR RAM.
            -- This will hopefully mean that the DDR RAM is in the right state
            -- to handle the real access, and won't accidentally serve up the wrong
            -- data, or cause a write to the wrong place.
            nState <= stNormaliseRequest;
          end if;

        when stNormaliseRequest =>
          -- A new memory request is happening.  
          -- This needs a new memory request, so start a new transaction, if
          -- the DDR RAM isn't busy calibrating.
          if calib_complete = '1' then
            nState <= stNormalisePreset;
          end if;
          cache_write_enable <= '0';
          cache_write_address <= (others => '1');
        when stNormalisePreset =>
          nState <= stNormaliseSetCmdRd;
          mem_addr <= ram_address_held(26 downto 4) & "0000";
          mem_wdf_data <= x"99999999" & x"99999999" & x"99999999" & x"99999999";
          ddr_timeout <= x"ff";

          -- Register write enable now -- several cycles after the request has
          -- been noticed, but also several cycles before we need to act on it.
          ram_write_enable_held <= ram_write_enable_internal;

        when stNormaliseSetCmdRd =>
          -- Wait for memory to be finish the read
          mem_en <= '1';
          mem_cmd <= CMD_READ;
          mem_wdf_mask <= "1111111111111111";
          
          if (mem_rdy='1')
            and (mem_rd_data_valid = '1') and (mem_rd_data_end = '1') then
            
            nState <= stRequest;
          else
            -- Allow reads to timeout.
            if ddr_timeout = "00" then
              nState <= stDone;
            else
              ddr_timeout <= ddr_timeout - 1;
            end if;
          end if;
          
        when stRequest =>
          -- A new memory request is happening.  
          -- This needs a new memory request, so start a new transaction, if
          -- the DDR RAM isn't busy calibrating.
          if calib_complete = '1' then
            nState <= stPreset;
          end if;
          cache_write_address <= ram_address_internal(12 downto 4);
          -- Make sure that nothing odd happens if ram_address changes while we
          -- are working.
          ram_address_held <= ram_address_internal;
          ram_write_data_held <= ram_write_data_internal;
          -- Set up dummy input to cache, which is only written if necessary.
          cache_write_data(150 downto 128) <= (others => '1');
          cache_write_data(127 downto 8) <= (others => '0');
          cache_write_data(7 downto 0) <= x"57"; -- 'W' for debugging
          if (ram_write_enable_held = '1') then
            -- Invalidate cache line if writing
            cache_write_enable <= '1';
            -- Let caller go free if writing, now that we have accepted the data
            -- ram_done_toggle_localclock <= ram_request_toggle_internal;
          else
            cache_write_enable <= '0';
          end if;
        when stPreset =>
          -- A memory request is ready and waiting, so start the transaction.
          -- XXX: Couldn't this be done in the state above to avoid wasting a cycle?
          if ram_write_enable_held = '1' then
            nState <= stSendData;
          else
            -- XXX: Debug measure:
            -- Memory address $F000000 reads the four most recent write addresses
            -- instead of reading data from RAM            
            if (ram_address_held(26 downto 24) = "111")
              and (ram_address_held(23 downto 0) = x"000000") then
              nState <= stRecentWriteRead;
            else
              nState <= stSetCmdRd;
              -- debug_counter_localclock <= debug_counter_localclock + 1;
            end if;
            -- Reading $F000010 enables debug mode, and reading $F000020 disables
            -- debug mode
            if (ram_address_held(26 downto 24) = "111")
              and (ram_address_held(23 downto 0) = x"000010") then
              debug_mode <= '1';
            end if;
            if (ram_address_held(26 downto 24) = "111")
              and (ram_address_held(23 downto 0) = x"000020") then
              debug_mode <= '0';
            end if;
          end if;
          case (ram_address_held(3 downto 0)) is
            when "0000" => mem_wdf_mask <= "1111111111111110";
            when "0001" => mem_wdf_mask <= "1111111111111101";
            when "0010" => mem_wdf_mask <= "1111111111111011";
            when "0011" => mem_wdf_mask <= "1111111111110111";
            when "0100" => mem_wdf_mask <= "1111111111101111";
            when "0101" => mem_wdf_mask <= "1111111111011111";
            when "0110" => mem_wdf_mask <= "1111111110111111";
            when "0111" => mem_wdf_mask <= "1111111101111111";
            when "1000" => mem_wdf_mask <= "1111111011111111";
            when "1001" => mem_wdf_mask <= "1111110111111111";
            when "1010" => mem_wdf_mask <= "1111101111111111";
            when "1011" => mem_wdf_mask <= "1111011111111111";
            when "1100" => mem_wdf_mask <= "1110111111111111";
            when "1101" => mem_wdf_mask <= "1101111111111111";
            when "1110" => mem_wdf_mask <= "1011111111111111";
            when "1111" => mem_wdf_mask <= "0111111111111111";
            when others => null;
          end case;
          mem_addr <= ram_address_held(26 downto 4) & "0000";
          mem_wdf_data <= ram_write_data_held & ram_write_data_held
                          & ram_write_data_held & ram_write_data_held
                          & ram_write_data_held & ram_write_data_held
                          & ram_write_data_held & ram_write_data_held
                          & ram_write_data_held & ram_write_data_held
                          & ram_write_data_held & ram_write_data_held
                          & ram_write_data_held & ram_write_data_held
                          & ram_write_data_held & ram_write_data_held;
          ddr_timeout <= x"ff";
        when stSendData =>
          -- Wait until memory finishes writing
          mem_wdf_wren <= '1';
          mem_wdf_end <= '1';

          if mem_wdf_rdy = '1' then
            nState <= stSetCmdWr;
            debug_counter_localclock <= debug_counter_localclock + 1;

            recent_write_0(31 downto 8) <= ram_address_held(23 downto 0);
            recent_write_0(7 downto 0) <= ram_write_data_held;
            recent_write_3 <= recent_write_2;
            recent_write_2 <= recent_write_1;
            recent_write_1 <= recent_write_0;
          end if;
          -- Allow writes to timeout.
          if ddr_timeout = "00" then
            nState <= stSetCmdWr;
          else
            ddr_timeout <= ddr_timeout - 1;
          end if;
        when stSetCmdRd =>
          -- Wait for memory to be finish the read
          mem_en <= '1';
          mem_cmd <= CMD_READ;
          mem_wdf_mask <= "1111111111111111";

          if (mem_rdy='1')
            and (mem_rd_data_valid = '1') and (mem_rd_data_end = '1') then
            cache_write_address <= ram_address_held(12 downto 4);
            cache_write_data(150 downto 128) <= ram_address_held(26 downto 4);
            if debug_mode='0' then
              cache_write_data(127 downto 0) <= mem_rd_data;
            else
              cache_write_data(127 downto 123) <= (others => '0');
              cache_write_data(122 downto 96) <= ram_address_held(26 downto 0);
              cache_write_data(95 downto 0) <= mem_rd_data(95 downto 0);
            end if;
           cache_write_enable <= '1';
            
            -- Remember the full 16 bytes read so that we can use it as a cache
            -- for subsequent reads.
            last_ram_read_data_localclock <= mem_rd_data;
            nState <= stDone;
          else
            -- Allow reads to timeout.
            if ddr_timeout = "00" then
              nState <= stDone;
            else
              ddr_timeout <= ddr_timeout - 1;
            end if;
          end if;
        when stSetCmdWr =>
          mem_en <= '1';
          mem_cmd <= CMD_WRITE;
          if mem_rdy = '1' then
            nState <= stDone;
          end if;
          -- Allow writes to timeout.
          if ddr_timeout = "00" then
            nState <= stDone;
          else
            ddr_timeout <= ddr_timeout - 1;
          end if;
        when stRecentWriteRead =>
          cache_write_address <= ram_address_held(12 downto 4);
          cache_write_data(150 downto 128) <= ram_address_held(26 downto 4);
          cache_write_data(127 downto 96) <= recent_write_3;
          cache_write_data(95 downto 64) <= recent_write_2;
          cache_write_data(63 downto 32) <= recent_write_1;
          cache_write_data(31 downto 0) <= recent_write_0;
          cache_write_enable <= '1';
          nState <= stDone;
        when stDone =>
          -- Delay memory done announcement to give data plenty of time to settle
          mem_wdf_mask <= "1111111111111111";
          ram_done_toggle_localclock <= ram_request_toggle_internal;
          last_ram_request_toggle <= ram_request_toggle_internal;
          nState <= stIdle;
        when others =>
          mem_wdf_mask <= "1111111111111111";
          ram_done_toggle_localclock <= ram_request_toggle_internal;
          last_ram_request_toggle <= ram_request_toggle_internal;
          nState <= stIdle;
      end case;
    end if; 
  end process;

end behavioral;
