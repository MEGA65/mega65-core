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
    clk_200MHz_i         : in    std_logic; -- 200 MHz system clock
    rst_i                : in    std_logic; -- active high system reset
    device_temp_i        : in    std_logic_vector(11 downto 0);
    
    -- RAM interface
    ram_address          : in    std_logic_vector(26 downto 0);
    ram_read_data        : out   std_logic_vector(7 downto 0);
    ram_write_data       : in    std_logic_vector(7 downto 0);
    ram_write_enable     : in    std_logic;
    ram_request_toggle   : in    std_logic;
    ram_done_toggle      : out   std_logic := '0';
    
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
  type state_type is (stIdle, stPreset, stSendData, stSetCmdRd, stSetCmdWr,
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
  signal sreg                : std_logic_vector(1 downto 0);

  signal ram_request_toggle_internal : std_logic := '0';
  signal ram_address_internal : std_logic_vector(26 downto 0);
  signal ram_write_data_internal : std_logic_vector(7 downto 0);
  signal ram_write_enable_internal : std_logic;

  -- cache for 16 bytes we read at a time, to avoid wasting time with
  -- full requests for accesses in the same 16 bytes.
  -- (We also write to the cache when processing writes so that it stays
  -- consistent).
  -- XXX - We don't allow servicing reads from the cache while a write is
  -- in progress.
  signal last_ram_address : std_logic_vector(26 downto 0);
  signal last_ram_read_data : std_logic_vector(127 downto 0);

  
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

  attribute FSM_ENCODING              : string;
  attribute FSM_ENCODING of cState    : signal is "GRAY";

  attribute ASYNC_REG                 : string;
  attribute ASYNC_REG of sreg         : signal is "TRUE";

begin

------------------------------------------------------------------------
-- Registering the active-low reset for the MIG component
------------------------------------------------------------------------
  RSTSYNC: process(clk_200MHz_i)
  begin
    if rising_edge(clk_200MHz_i) then
      sreg <= sreg(0) & rst_i;
      rstn <= not sreg(1);
    end if;
  end process RSTSYNC;

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
      ram_address_internal <= ram_address;
      ram_write_data_internal <= ram_write_data;
      ram_request_toggle_internal <= ram_request_toggle;
      ram_write_enable_internal <= ram_write_enable;
      if mem_ui_rst = '1' then
        cState <= stIdle;
      else
        cState <= nState;
      end if;
    end if;
  end process REG_IN;

  process(mem_ui_clk)
  begin

    mem_wdf_wren <= '0';
    mem_wdf_end <= '0';
    mem_en <= '0';
    mem_cmd <= (others => '0');

    -- Note that the state machine has a 1 cycle delay to match the DDR2
    -- semantics.  This means that each state block will get executed twice,
    -- but toggling of acknowledgement lines needs to be done just once, so
    -- we do a short-circuit for the states when memory accesses end to make
    -- that happen, by assigning cState directly instead of via nState.
    cState <= nState;  -- do the delayed state assignment
    nState <= cState;  -- by default keep the current state

    case (cState) is
      when stIdle =>
        if (ram_request_toggle_internal /= last_ram_request_toggle) then
          -- A new memory request is happening.  Check if it can be serviced from
          -- the cache
          if (last_ram_address(26 downto 4) = ram_address_internal(26 downto 4))
            and (ram_write_enable_internal = '0') then
            -- Memory read request that can be serviced from the cache.
            case (ram_address_internal(3 downto 0)) is
              when "0000" =>  ram_read_data <= last_ram_read_data(7 downto 0);
              when "0001" =>  ram_read_data <= last_ram_read_data(15 downto 8);
              when "0010" =>  ram_read_data <= last_ram_read_data(23 downto 16);
              when "0011" =>  ram_read_data <= last_ram_read_data(31 downto 24);
              when "0100" =>  ram_read_data <= last_ram_read_data(39 downto 32);
              when "0101" =>  ram_read_data <= last_ram_read_data(47 downto 40);
              when "0110" =>  ram_read_data <= last_ram_read_data(55 downto 48);
              when "0111" =>  ram_read_data <= last_ram_read_data(63 downto 56);
              when "1000" =>  ram_read_data <= last_ram_read_data(71 downto 64);
              when "1001" =>  ram_read_data <= last_ram_read_data(79 downto 72);
              when "1010" =>  ram_read_data <= last_ram_read_data(87 downto 80);
              when "1011" =>  ram_read_data <= last_ram_read_data(95 downto 88);
              when "1100" =>  ram_read_data <= last_ram_read_data(103 downto 96);
              when "1101" =>  ram_read_data <= last_ram_read_data(111 downto 104);
              when "1110" =>  ram_read_data <= last_ram_read_data(119 downto 112);
              when "1111" =>  ram_read_data <= last_ram_read_data(127 downto 120);
              when others => null;
            end case;
          else
            -- This needs a new memory request, so start a new transaction, if
            -- the DDR RAM isn't busy calibrating.
            if calib_complete = '1' then
              nState <= stPreset;
            end if;
            -- Update cache line if necessary
            if (last_ram_address(26 downto 4) = ram_address_internal(26 downto 4))
              and (ram_write_enable_internal = '1') then
              -- Memory write request should update cache
              case (ram_address_internal(3 downto 0)) is
                when "0000" =>  last_ram_read_data(7 downto 0) <= ram_write_data_internal;
                when "0001" =>  last_ram_read_data(15 downto 8) <= ram_write_data_internal;
                when "0010" =>  last_ram_read_data(23 downto 16) <= ram_write_data_internal;
                when "0011" =>  last_ram_read_data(31 downto 24) <= ram_write_data_internal;
                when "0100" =>  last_ram_read_data(39 downto 32) <= ram_write_data_internal;
                when "0101" =>  last_ram_read_data(47 downto 40) <= ram_write_data_internal;
                when "0110" =>  last_ram_read_data(55 downto 48) <= ram_write_data_internal;
                when "0111" =>  last_ram_read_data(63 downto 56) <= ram_write_data_internal;
                when "1000" =>  last_ram_read_data(71 downto 64) <= ram_write_data_internal;
                when "1001" =>  last_ram_read_data(79 downto 72) <= ram_write_data_internal;
                when "1010" =>  last_ram_read_data(87 downto 80) <= ram_write_data_internal;
                when "1011" =>  last_ram_read_data(95 downto 88) <= ram_write_data_internal;
                when "1100" =>  last_ram_read_data(103 downto 96) <= ram_write_data_internal;
                when "1101" =>  last_ram_read_data(111 downto 104) <= ram_write_data_internal;
                when "1110" =>  last_ram_read_data(119 downto 112) <= ram_write_data_internal;
                when "1111" =>  last_ram_read_data(127 downto 120) <= ram_write_data_internal;
                when others => null;
              end case;
            end if;
            -- Let caller go free if writing, now that we have accepted the data
            if ram_write_enable_internal = '1' then
              ram_done_toggle <= not ram_request_toggle_internal;
            end if;
          end if;
        end if;
      when stPreset =>
        -- A memory request is ready and waiting, so start the transaction.
        -- XXX: Couldn't this be done in the state above to avoid wasting a cycle?
        if ram_write_enable = '1' then
          nState <= stSendData;
        else
          nState <= stSetCmdRd;
        end if;
        case (ram_address_internal(3 downto 0)) is
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
        mem_addr <= ram_address_internal(26 downto 4) & "0000";
        mem_wdf_data <= ram_write_data_internal & ram_write_data_internal
                        & ram_write_data_internal & ram_write_data_internal
                        & ram_write_data_internal & ram_write_data_internal
                        & ram_write_data_internal & ram_write_data_internal
                        & ram_write_data_internal & ram_write_data_internal
                        & ram_write_data_internal & ram_write_data_internal
                        & ram_write_data_internal & ram_write_data_internal
                        & ram_write_data_internal & ram_write_data_internal;
      when stSendData =>
        -- Wait until memory finishes writing
        mem_wdf_wren <= '1';
        mem_wdf_end <= '1';

        if mem_wdf_rdy = '1' then
          nState <= stSetCmdWr;
        end if;
      when stSetCmdRd =>
        -- Wait for memory to be finish the read
        mem_en <= '1';
        mem_cmd <= CMD_READ;

        if mem_rdy = '1' then
          case (ram_address_internal(3 downto 0)) is
            when "0000" =>  ram_read_data <= mem_rd_data(7 downto 0);
            when "0001" =>  ram_read_data <= mem_rd_data(15 downto 8);
            when "0010" =>  ram_read_data <= mem_rd_data(23 downto 16);
            when "0011" =>  ram_read_data <= mem_rd_data(31 downto 24);
            when "0100" =>  ram_read_data <= mem_rd_data(39 downto 32);
            when "0101" =>  ram_read_data <= mem_rd_data(47 downto 40);
            when "0110" =>  ram_read_data <= mem_rd_data(55 downto 48);
            when "0111" =>  ram_read_data <= mem_rd_data(63 downto 56);
            when "1000" =>  ram_read_data <= mem_rd_data(71 downto 64);
            when "1001" =>  ram_read_data <= mem_rd_data(79 downto 72);
            when "1010" =>  ram_read_data <= mem_rd_data(87 downto 80);
            when "1011" =>  ram_read_data <= mem_rd_data(95 downto 88);
            when "1100" =>  ram_read_data <= mem_rd_data(103 downto 96);
            when "1101" =>  ram_read_data <= mem_rd_data(111 downto 104);
            when "1110" =>  ram_read_data <= mem_rd_data(119 downto 112);
            when "1111" =>  ram_read_data <= mem_rd_data(127 downto 120);
            when others => null;
          end case;
          -- Remember the full 16 bytes read so that we can use it as a cache
          -- for subsequent reads.
          last_ram_read_data <= mem_rd_data;
          last_ram_address <= ram_address_internal;
          ram_done_toggle <= not ram_request_toggle_internal;
          cState <= stDone;
        end if;
      when stSetCmdWr =>
        mem_en <= '1';
        mem_cmd <= CMD_WRITE;
        if mem_rdy = '1' then
          cState <= stDone;
        end if;
      when stDone =>
        nState <= stIdle;
      when others =>
        nState <= stIdle;
    end case;
  end process;

end behavioral;
