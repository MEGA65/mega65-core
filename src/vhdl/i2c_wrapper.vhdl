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
    fastio_write : in std_logic;
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
  signal last_busy : std_logic := '1';
  
  subtype uint8 is unsigned(7 downto 0);
  type byte_array is array (0 to 127) of uint8;
  signal bytes : byte_array := (others => x"00");

  signal write_job_pending : std_logic := '0';
  signal write_addr : unsigned(7 downto 0);
  signal write_reg : unsigned(7 downto 0);
  signal write_val : unsigned(7 downto 0);
  
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
  
  process (clock,cs,fastio_read,fastio_addr) is
  begin

    if cs='1' and fastio_read='1' then
      if fastio_addr(7) = '0' then
        report "reading buffered I2C data";
        fastio_rdata <= bytes(to_integer(fastio_addr(6 downto 0)));
      elsif fastio_addr(7 downto 0) = "11111111" then
        -- Show busy status for writing
        fastio_rdata <= (others => write_job_pending);
      else
        -- Else for debug show busy count
        fastio_rdata <= to_unsigned(busy_count,8);
      end if;
    else
      report "tristating";
      fastio_rdata <= (others => 'Z');
    end if; 

    if rising_edge(clock) then

      -- Write to registers as required
      if cs='1' and fastio_write='1' then
        case to_integer(fastio_addr(7 downto 0)) is
          when 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 =>
            write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 0,8);
            write_addr <= x"72";
            write_job_pending <= '1';
          when 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 =>
            write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 8,8);
            write_addr <= x"74";            
            write_job_pending <= '1';
          when 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 =>
            write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 16,8);
            write_addr <= x"76";
            write_job_pending <= '1';
          when 24 | 25 | 26 | 27 | 28 | 29 | 30 | 31 | 32 | 33 | 34 | 35 | 36 | 37 | 38 | 39 | 40 | 41 | 42 =>
            write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 24,8);
            write_addr <= x"A2";
            write_job_pending <= '1';
          when 64 | 65 | 66 | 67 | 68 | 69 | 70 | 71 | 72 | 73 | 74 | 75 | 76 | 77 | 78 | 79 | 80 | 81 | 82 | 83 | 84 | 85 | 86 | 87 | 88 | 89 | 90 | 91 | 92 | 93 | 94 | 95 | 96 | 97 | 98 | 99 | 100 | 101 | 102 | 103 | 104 | 105 | 106 | 107 | 108 | 109 | 110 | 111 | 112 | 113 | 114 | 115 | 116 | 117 | 118 | 119 | 120 | 121 | 122 | 123 | 124 | 125 | 126 | 127 =>
            write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 64, 8);
            write_addr <= x"32";
            write_job_pending <= '1';            
          when others =>
        end case;
        write_val <= fastio_wdata;
      end if;
      
      i2c1_reset <= '1';

      -- State machine for reading registers from the various
      -- devices.
      last_busy <= i2c1_busy;
      if i2c1_busy='1' and last_busy='0' then

        -- Sequence through the list of transactions endlessly
        if (busy_count < 135) or (write_job_pending='1' and busy_count < (135+3)) then
          busy_count <= busy_count + 1;
        else
          busy_count <= 0;
        end if;
      end if;
        
      case busy_count is
        when 0 =>
          -- Begin IO expander 0 read sequence
          i2c1_command_en <= '1';
          i2c1_address <= "0111001"; -- 0x72/2 = I2C address of expander
          i2c1_wdata <= x"00"; -- begin reading from register 0
          i2c1_rw <= '0';
        when 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9  =>
          -- Read the 8 bytes of inputs from the IO expander
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 1 then
            bytes(busy_count - 1 - 1) <= i2c1_rdata;
          end if;
        when 10 =>
          -- Begin IO expander 1 read sequence
          i2c1_command_en <= '1';
          i2c1_address <= "0111010"; -- 0x74/2 = I2C address of expander
          i2c1_wdata <= x"00"; -- begin reading from register 0
          i2c1_rw <= '0';
        when 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19  =>
          -- Read the 8 bytes of inputs from the IO expander
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 11 then
            bytes(busy_count - 11 - 1 + 8) <= i2c1_rdata;
          end if;
        when 20 =>
          -- Begin IO expander 2 read sequence
          i2c1_command_en <= '1';
          i2c1_address <= "0111011"; -- 0x76/2 = I2C address of expander
          i2c1_wdata <= x"00"; -- begin reading from register 0
          i2c1_rw <= '0';
        when 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29  =>
          -- Read the two bytes of inputs from the IO expander
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 21 then
            bytes(busy_count - 21 - 1  + 16) <= i2c1_rdata;
          end if;
        when 30 =>
          -- Begin RTC read sequence
          i2c1_command_en <= '1';
          i2c1_address <= "1010001"; -- 0xA2/2 = I2C address of RTC
          i2c1_wdata <= x"00"; -- begin reading from register 0
          i2c1_rw <= '0';
        when 31 | 32 | 33 | 34 | 35 | 36 | 37 | 38 | 39 | 40 | 41 | 42 | 43 | 44 | 45 | 46 | 47 | 48 | 49 =>
          -- Read the 19 bytes of inputs from the IO expander
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 31 then
            bytes(busy_count - 31 - 1 + 24) <= i2c1_rdata;
          end if;
        when 50 =>
          -- Begin SSM2518 amplifier read sequence of 19 registers
          i2c1_command_en <= '1';
          i2c1_address <= "0110100"; -- 0x68/2 = I2C address of amplifier
          i2c1_wdata <= x"00"; -- begin reading from register 0
          i2c1_rw <= '0';
        when 51 | 52 | 53 | 54 | 55 | 56 | 57 | 58 | 59 | 60 | 61 | 62 | 63 | 64 | 65 | 66 | 67 | 68 | 69 | 70 =>
          -- Read the 16 bytes of inputs from the IO expander
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 51 then
            bytes(busy_count - 51 - 1 + 40) <= i2c1_rdata;
          end if;
        when 71 =>
          -- Begin LIS3DH accelerometer read sequence of 64 registers
          i2c1_command_en <= '1';
          i2c1_address <= "0011001"; -- 0x32/2 = I2C address of accelerometer
          i2c1_wdata <= x"00"; -- begin reading from register 0
          i2c1_rw <= '0';
        when 72 | 73 | 74 | 75 | 76 | 77 | 78 | 79 | 80 | 81 | 82 | 83 | 84 | 85 | 86 | 87 | 88 | 89 | 90 | 91 | 92 | 93 | 94 | 95 | 96 | 97 | 98 | 99 | 100 | 101 | 102 | 103 | 104 | 105 | 106 | 107 | 108 | 109 | 110 | 111 | 112 | 113 | 114 | 115 | 116 | 117 | 118 | 119 | 120 | 121 | 122 | 123 | 124 | 125 | 126 | 127 | 128 | 129 | 130 | 131 | 132 | 133 | 134 | 135 =>
          -- Read the 16 bytes of inputs from the IO expander
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 72 then
            bytes(busy_count - 72 - 1 + 64) <= i2c1_rdata;
          end if;
        when 136 =>
          -- Write to a register, if a request is pending:
          -- First, write the address and register number.
          i2c1_rw <= '0';
          i2c1_command_en <= '1';
          i2c1_address <= write_addr(7 downto 1);
          i2c1_wdata <= write_reg;
        when 137 =>
          -- Second, write the actual value into the register
          i2c1_rw <= '0';
          i2c1_command_en <= '1';
          i2c1_wdata <= write_val;
          write_job_pending <= '0';
        when others =>
          -- Make sure we can't get stuck.
          i2c1_command_en <= '0';
          busy_count <= 0;
          last_busy <= '1';
      end case;
      
    end if;
  end process;
end behavioural;



