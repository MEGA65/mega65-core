--
-- Written by
--    Paul Gardner-Stephen, Flinders University <paul.gardner-stephen@flinders.edu.au>  2018-2019
--
-- XXX - We are reading rubbish sometimes from the I2C devices.
-- It is being worked-around by using a de-glitch/de-bounce algorithm,
-- but we should really find out the real cause and fix it at some point.
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
--
-- I2C peripherals are (in 7-bit address notation)
--   0x54 = 24LC128-I/ST     = 16KB FLASH
--                           Uses 16-bit addressing.  We might have to have a
--                           banking regsiter for this.                   
--   0x50 = 24AA025E48T-I/OT = 2Kbit serial EEPROM + UUID for ethernet MAC?
--                             (lower 128 bytes read/write, upper 128 bytes random values and read-only)
--                             (last 8 bytes are UUID64, which can be used to derive a 48bit unique MAC address)
--                             We use it only to map these last 8 bytes.
--                           Registers $F8 - $FF
--   0x6F = ISL12020MIRZ     = RTC
--                           Registers $00 - $2F
--   0x57 = ISL12020MIRZ     = battery backed static RAM, part of the RTC
--                           Registers $00 - $7F
--                           We might have to have a banking register for this
--
-- 8-bit read addresses:
-- 0xA9, 0xA1, 0xDF, 0xAF

-- @IO:GS $FFD7100-07 UUID:UUID64 64-bit UUID. Can be used to seed ethernet MAC address
-- @IO:GS $FFD7110-3F RTC:RTC Real-time Clock
-- @IO:GS $FFD7110 RTC:RTCSEC Real-time Clock seconds value (binary coded decimal)
-- @IO:GS $FFD7111 RTC:RTCMIN Real-time Clock minutes value (binary coded decimal)
-- @IO:GS $FFD7112 RTC:RTCHOUR Real-time Clock hours value (binary coded decimal)
-- @IO:GS $FFD7113 RTC:RTCDAY Real-time Clock day of month value (binary coded decimal)
-- @IO:GS $FFD7114 RTC:RTCMONTH Real-time Clock month value (binary coded decimal)
-- @IO:GS $FFD7115 RTC:RTCYEAR Real-time Clock year value (binary coded decimal)


-- @IO:GS $FFD7140-7F RTC:NVRAM 64-bytes of non-volatile RAM. Can be used for storing machine configuration.


use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity hdmi_i2c is
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
end hdmi_i2c;

architecture behavioural of hdmi_i2c is

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
  signal v0 : unsigned(7 downto 0) := to_unsigned(0,8);
  signal v1 : unsigned(7 downto 0) := to_unsigned(0,8);

  signal busy_count : integer range 0 to 255 := 150;
  signal last_busy : std_logic := '1';
  
  subtype uint8 is unsigned(7 downto 0);
  type byte_array is array (0 to 255) of uint8;
  signal bytes : byte_array := (others => x"00");

  signal write_job_pending : std_logic := '0';
  signal write_addr : unsigned(7 downto 0) := x"48";
  signal write_reg : unsigned(7 downto 0) := x"02";
  signal write_val : unsigned(7 downto 0) := x"99";

  signal delayed_en : integer range 0 to 255 := 0;
  
begin

  i2c1: entity work.i2c_master
    generic map (
      input_clk => 40_000_000,
      bus_clk => 400_000
      )
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
        fastio_rdata <= bytes(to_integer(fastio_addr(7 downto 0)));
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
        -- ADV7511 main map registers
        write_reg <= fastio_addr(7 downto 0);
        write_addr <= x"72";
        write_job_pending <= '1';
        write_val <= fastio_wdata;
      end if;
      
      i2c1_reset <= '1';

      -- State machine for reading registers from the various
      -- devices.
      last_busy <= i2c1_busy;
      if i2c1_busy='1' and last_busy='0' then

        -- Sequence through the list of transactions endlessly
        if (busy_count < 256) or (write_job_pending='1' and busy_count < (256+4)) then
          busy_count <= busy_count + 1;
        else
          busy_count <= 0;
        end if;
      end if;

      if busy_count = 0 then
        i2c1_command_en <= '1';
        i2c1_address <= "0111001"; -- 0x72/2 = I2C address of device;
        i2c1_wdata <= x"00";
        i2c1_rw <= '0';
      elsif busy_count < 256 then
          -- Read the 8 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 1 then
            bytes(busy_count - 1 - 1 + 0) <= i2c1_rdata;
          end if;
      elsif busy_count = 256 the
          -- Write to a register, if a request is pending:
          -- First, write the address and register number.
          i2c1_rw <= '0';
          i2c1_command_en <= '1';
          i2c1_address <= write_addr(7 downto 1);
          i2c1_wdata <= write_reg;
      elsif busy_count = 257 then
          -- Second, write the actual value into the register
          i2c1_rw <= '0';
          i2c1_command_en <= '1';
          i2c1_wdata <= write_val;
      elsif busy_count = 258 then
          report "Doing dummy read";
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          i2c1_address <= (others => '1');
      else
          report "in others";
          -- Make sure we can't get stuck.
          i2c1_command_en <= '0';
          busy_count <= 0;
          last_busy <= '1';
          write_job_pending <= '0';
      end if;

      -- This has to come last, so that it overrides the clearing of
      -- i2c1_command_en above.
      if i2c1_busy = '0' then
        if delayed_en= 1 then
          report "Activating delayed command";
          i2c1_command_en <= '1';
        elsif delayed_en > 1 then
          delayed_en <= delayed_en - 1;
        end if;
      else
        if delayed_en = 1 then
          delayed_en <= 0;
        end if;
      end if;
      

      
    end if;
  end process;
end behavioural;



