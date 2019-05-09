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

  signal delayed_en : std_logic := '0';
  
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
            -- RTC
            write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 24,8);
            write_addr <= x"A2";
            write_job_pending <= '1';
          when 48 | 49 | 50 | 51 | 52 | 53 | 54 | 55 | 56 | 57 | 58 | 59 | 60 | 61 | 62 | 63 =>
            -- Amplifier
            write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 32,8);
            write_addr <= x"68";
            write_job_pending <= '1';            
          when 64 | 65 | 66 | 67 | 68 | 69 | 70 | 71 | 72 | 73 | 74 | 75 | 76 | 77 | 78 | 79 | 80 | 81 | 82 | 83 | 84 | 85 | 86 | 87 | 88 | 89 | 90 | 91 | 92 | 93 | 94 | 95 | 96 | 97 | 98 | 99 | 100 | 101 | 102 | 103 | 104 | 105 | 106 | 107 | 108 | 109 | 110 | 111 | 112 | 113 | 114 | 115 | 116 | 117 | 118 | 119 | 120 | 121 | 122 | 123 | 124 | 125 | 126 | 127 =>
            -- Accelerometer
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
        if (busy_count < 153) or (write_job_pending='1' and busy_count < (153+3)) then
          busy_count <= busy_count + 1;
        else
          busy_count <= 0;
        end if;
      end if;

      -- XXX Annoying problem with the IO expanders is that to select
      -- a register for reading, you have to send a STOP before trying to
      -- read from the new address.  The problem is that our state-machine
      -- here requires back-to-back commands.  Solution is to add a delayed
      -- command_en line, that gets checked and copied to i2c1_command_en
      -- when busy is low.
      if i2c1_busy = '0' and delayed_en='1' then
        delayed_en <= '0';
        i2c1_command_en <= delayed_en;
      end if;
      
      case busy_count is
        -- The body for this case statement can be automatically generated
        -- using src/tools/i2cstatemapper.c

        --------------------------------------------------------------------
        -- Start of Auto-Generated Content
        --------------------------------------------------------------------        
        when 0 =>
        report "IO Expander #0 regs 0-1";
        i2c1_command_en <= '1';
        i2c1_address <= "0111001"; -- 0x72/2 = I2C address of device;
        i2c1_wdata <= x"00";
        i2c1_rw <= '0';
        when 1 | 2 | 3 =>
        -- Read the 2 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '0';
        delayed_en <= '1';
        if busy_count > 1 then
          bytes(busy_count - 1 - 1 + 0) <= i2c1_rdata;
        end if;
        report "IO Expander #0 regs 2-3";
        when 4 =>
        i2c1_command_en <= '1';
        i2c1_address <= "0111001"; -- 0x72/2 = I2C address of device;
        i2c1_wdata <= x"02";
        i2c1_rw <= '0';
        when 5 | 6 | 7 =>
        -- Read the 2 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '0';
        delayed_en <= '1';
        if busy_count > 5 then
          bytes(busy_count - 1 - 5 + 2) <= i2c1_rdata;
        end if;
        report "IO Expander #0 regs 4-5";
        when 8 =>
        i2c1_command_en <= '1';
        i2c1_address <= "0111001"; -- 0x72/2 = I2C address of device;
        i2c1_wdata <= x"04";
        i2c1_rw <= '0';
        when 9 | 10 | 11 =>
        -- Read the 2 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '0';
        delayed_en <= '1';
        if busy_count > 9 then
          bytes(busy_count - 1 - 9 + 4) <= i2c1_rdata;
        end if;
        report "IO Expander #0 regs 6-7";
        when 12 =>
        i2c1_command_en <= '1';
        i2c1_address <= "0111001"; -- 0x72/2 = I2C address of device;
        i2c1_wdata <= x"06";
        i2c1_rw <= '0';
        when 13 | 14 | 15 =>
        -- Read the 2 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '0';
        delayed_en <= '1';
        if busy_count > 13 then
          bytes(busy_count - 1 - 13 + 6) <= i2c1_rdata;
        end if;
        report "IO Expander #1 regs 0-1";
        when 16 =>
        i2c1_command_en <= '1';
        i2c1_address <= "0111010"; -- 0x74/2 = I2C address of device;
        i2c1_wdata <= x"00";
        i2c1_rw <= '0';
        when 17 | 18 | 19 =>
        -- Read the 2 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '0';
        delayed_en <= '1';
        if busy_count > 17 then
          bytes(busy_count - 1 - 17 + 8) <= i2c1_rdata;
        end if;
        report "IO Expander #1 regs 2-3";
        when 20 =>
        i2c1_command_en <= '1';
        i2c1_address <= "0111010"; -- 0x74/2 = I2C address of device;
        i2c1_wdata <= x"02";
        i2c1_rw <= '0';
        when 21 | 22 | 23 =>
        -- Read the 2 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '0';
        delayed_en <= '1';
        if busy_count > 21 then
          bytes(busy_count - 1 - 21 + 10) <= i2c1_rdata;
        end if;
        report "IO Expander #1 regs 4-5";
        when 24 =>
        i2c1_command_en <= '1';
        i2c1_address <= "0111010"; -- 0x74/2 = I2C address of device;
        i2c1_wdata <= x"04";
        i2c1_rw <= '0';
        when 25 | 26 | 27 =>
        -- Read the 2 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '0';
        delayed_en <= '1';
        if busy_count > 25 then
          bytes(busy_count - 1 - 25 + 12) <= i2c1_rdata;
        end if;
        report "IO Expander #1 regs 6-7";
        when 28 =>
        i2c1_command_en <= '0';
        delayed_en <= '1';
        i2c1_address <= "0111010"; -- 0x74/2 = I2C address of device;
        i2c1_wdata <= x"06";
        i2c1_rw <= '0';
        when 29 | 30 | 31 =>
        -- Read the 2 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '1';
        if busy_count > 29 then
          bytes(busy_count - 1 - 29 + 14) <= i2c1_rdata;
        end if;
        report "IO Expander #2 regs 0-1";
        when 32 =>
        i2c1_command_en <= '0';
        delayed_en <= '1';
        i2c1_address <= "0111011"; -- 0x76/2 = I2C address of device;
        i2c1_wdata <= x"00";
        i2c1_rw <= '0';
        when 33 | 34 | 35 =>
        -- Read the 2 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '1';
        if busy_count > 33 then
          bytes(busy_count - 1 - 33 + 16) <= i2c1_rdata;
        end if;
        report "IO Expander #2 regs 2-3";
        when 36 =>
        i2c1_command_en <= '0';
        delayed_en <= '1';
        i2c1_address <= "0111011"; -- 0x76/2 = I2C address of device;
        i2c1_wdata <= x"02";
        i2c1_rw <= '0';
        when 37 | 38 | 39 =>
        -- Read the 2 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '1';
        if busy_count > 37 then
          bytes(busy_count - 1 - 37 + 18) <= i2c1_rdata;
        end if;
        report "IO Expander #2 regs 4-5";
        when 40 =>
        i2c1_command_en <= '0';
        delayed_en <= '1';
        i2c1_address <= "0111011"; -- 0x76/2 = I2C address of device;
        i2c1_wdata <= x"04";
        i2c1_rw <= '0';
        when 41 | 42 | 43 =>
        -- Read the 2 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '1';
        if busy_count > 41 then
          bytes(busy_count - 1 - 41 + 20) <= i2c1_rdata;
        end if;
        report "IO Expander #2 regs 6-7";
        when 44 =>
        i2c1_command_en <= '0';
        delayed_en <= '1';
        i2c1_address <= "0111011"; -- 0x76/2 = I2C address of device;
        i2c1_wdata <= x"06";
        i2c1_rw <= '0';
        when 45 | 46 | 47 =>
        -- Read the 2 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '1';
        if busy_count > 45 then
          bytes(busy_count - 1 - 45 + 22) <= i2c1_rdata;
        end if;
        report "Real Time clock regs 0 -- 18";
        when 48 =>
        i2c1_command_en <= '1';
        i2c1_address <= "1010001"; -- 0xA2/2 = I2C address of device;
        i2c1_wdata <= x"00";
        i2c1_rw <= '0';
        when 49 | 50 | 51 | 52 | 53 | 54 | 55 | 56 | 57 | 58 | 59 | 60 | 61 | 62 | 63 | 64 | 65 | 66 | 67 | 68 =>
        -- Read the 19 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '1';
        if busy_count > 49 then
          bytes(busy_count - 1 - 49 + 24) <= i2c1_rdata;
        end if;
        report "Audio amplifier regs 0 - 15";
        when 69 =>
        i2c1_command_en <= '1';
        i2c1_address <= "0110100"; -- 0x68/2 = I2C address of device;
        i2c1_wdata <= x"00";
        i2c1_rw <= '0';
        when 70 | 71 | 72 | 73 | 74 | 75 | 76 | 77 | 78 | 79 | 80 | 81 | 82 | 83 | 84 | 85 | 86 =>
        -- Read the 16 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '1';
        if busy_count > 70 then
          bytes(busy_count - 1 - 70 + 48) <= i2c1_rdata;
        end if;
        report "Acclerometer regs 0 - 63";
        when 87 =>
        i2c1_command_en <= '1';
        i2c1_address <= "0011001"; -- 0x32/2 = I2C address of device;
        i2c1_wdata <= x"80"; -- Auto-increment register number
        i2c1_rw <= '0';
        when 88 | 89 | 90 | 91 | 92 | 93 | 94 | 95 | 96 | 97 | 98 | 99 | 100 | 101 | 102 | 103 | 104 | 105 | 106 | 107 | 108 | 109 | 110 | 111 | 112 | 113 | 114 | 115 | 116 | 117 | 118 | 119 | 120 | 121 | 122 | 123 | 124 | 125 | 126 | 127 | 128 | 129 | 130 | 131 | 132 | 133 | 134 | 135 | 136 | 137 | 138 | 139 | 140 | 141 | 142 | 143 | 144 | 145 | 146 | 147 | 148 | 149 | 150 | 151 | 152 =>
        -- Read the 64 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '1';
        if busy_count > 88 then
          bytes(busy_count - 1 - 88 + 64) <= i2c1_rdata;
        end if;
        --------------------------------------------------------------------
        -- End of Auto-Generated Content
        --------------------------------------------------------------------        
        when 153 =>
        -- Write to a register, if a request is pending:
        -- First, write the address and register number.
        i2c1_rw <= '0';
        i2c1_command_en <= '1';
        i2c1_address <= write_addr(7 downto 1);
        i2c1_wdata <= write_reg;
        when 154 =>
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



