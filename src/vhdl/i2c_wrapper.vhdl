--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2018
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
--
-- Take a PDM 1-bit sample train and produce 8-bit PCM audio output
-- We have to shape the noise into the high frequency domain, as well
-- as remove any DC bias from the audio source.
--
-- Inspiration taken from https://www.dsprelated.com/showthread/comp.dsp/288391-1.php

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity i2c_wrapper is
  port (
    clock : in std_logic;
    
    -- I2C bus
    sda : inout std_logic;
    scl : inout std_logic;
    
    -- FastIO interface
    cs : in std_logic;
    fastio_read : in std_logic;
    fastio_write : out std_logic;
    fastio_rdata : out unsigned(7 downto 0);
    fastio_wdata : in unsigned(7 downto 0);
    fastio_addr : in unsigned(19 downto 0)    
    
    );
end i2c_wrapper;

architecture behavioural of i2c_wrapper is

  signal i2c1_address : unsigned(6 downto 0) := to_unsigned(0,7);
  signal i2c1_address_internal : unsigned(6 downto 0) := to_unsigned(0,7);
  signal i2c1_rdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c1_wdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c1_wdata_internal : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c1_busy : std_logic := '0';
  signal i2c1_busy_last : std_logic := '0';
  signal i2c1_rw : std_logic := '0';
  signal i2c1_rw_internal : std_logic := '0';
  signal i2c1_error : std_logic := '0';  
  signal i2c1_reset : std_logic := '1';
  signal i2c1_reset_internal : std_logic := '1';
  signal i2c1_command_en : std_logic := '0';  
  signal i2c1_command_en_internal : std_logic := '0';  

  signal busy_count : integer range 0 to 255 := 0;
  signal last_busy : std_logic := '0';
  
  subtype uint8 is unsigned(7 downto 0);
  type byte_array is array (0 to 31) of uint8;
  signal bytes : byte_array := (others => x"00");
  
begin

  i2c1: entity work.i2c_master
    port map (
      clk => clock,
      reset_n => i2c1_reset,
      ena => i2c1_command_en,
      addr => std_logic_vector(i2c1_address),
      rw => i2c1_rw,
      data_wr => std_logic_vector(i2c1_wdata),
      busy => i2c1_busy,
      unsigned(data_rd) => i2c1_rdata,
      ack_error => i2c1_error,
      sda => sda,
      scl => scl,
      swap => '0',
      debug_sda => '0',
      debug_scl => '0'      
      ); 
  
  process (clock) is
  begin
    if rising_edge(clock) then

      if cs='1' and fastio_read='1' then
        fastio_rdata <= bytes(fastio_addr(4 downto 0);
      else
        fastio_rdata <= (others => 'Z');
      end if; 

      i2c1_reset <= '1';

      -- State machine for reading registers from the various
      -- devices.
      last_busy <= i2c1_busy;
      if i2c1_busy='0' and last_busy='1' then
        if busy_count < 255 then
          busy_count <= busy_count + 1;
        else
          busy_count <= 0;
        end if;
        case busy_count is
          when 0 =>
            -- Begin IO expander 0 read sequence
            i2c1_command_en <= '1';
            i2c1_address <= "0111001"; -- 0x72/2 = I2C address of expander
            i2c1_wdata <= x"00"; -- begin reading from register 0
            i2c1_rw <= '0';
          when 1 | 2 | 3  =>
            -- Read the two bytes of inputs from the IO expander
            i2c1_rw <= '1';
            i2c1_command_en <= '1';
            if busy_count > 1 then
              bytes(busy_count - 2) <= i2c1_rdata;
            end if;
          when 4 =>
            i2c1_command_en <= '0';
          when 5 =>
            -- Begin IO expander 1 read sequence
            i2c1_command_en <= '1';
            i2c1_address <= "0111010"; -- 0x74/2 = I2C address of expander
            i2c1_wdata <= x"00"; -- begin reading from register 0
            i2c1_rw <= '0';
          when 6 | 7 | 8  =>
            -- Read the two bytes of inputs from the IO expander
            i2c1_rw <= '1';
            i2c1_command_en <= '1';
            if busy_count > 1 then
              bytes(busy_count - 7 + 2) <= i2c1_rdata;
            end if;
          when 9 =>
            i2c1_command_en <= '0';
          when 10 =>
            -- Begin IO expander 1 read sequence
            i2c1_command_en <= '1';
            i2c1_address <= "0111011"; -- 0x76/2 = I2C address of expander
            i2c1_wdata <= x"00"; -- begin reading from register 0
            i2c1_rw <= '0';
          when 11 | 12 | 13  =>
            -- Read the two bytes of inputs from the IO expander
            i2c1_rw <= '1';
            i2c1_command_en <= '1';
            if busy_count > 1 then
              bytes(busy_count - 12 + 2 + 2) <= i2c1_rdata;
            end if;
          when 14 =>
            i2c1_command_en <= '0';
        end case;
        
      end if;
      

    end if;
  end process;
end behavioural;


    
