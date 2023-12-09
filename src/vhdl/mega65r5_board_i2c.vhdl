--
-- Written by
--    Paul Gardner-Stephen, Flinders University <paul.gardner-stephen@flinders.edu.au>  2018-2020
--    Paul Gardner-Stephen, 2023
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

--   0x34 = SSM2518          = Audio amplifier for internal speakers
--   0x54 = 24LC128-I/ST     = 16KB FLASH
--                           Uses 16-bit addressing.  We might have to have a
--                           banking regsiter for this.
--   0x50 = 24AA025E48T-I/OT = 2Kbit serial EEPROM + UUID for ethernet MAC?
--                             (lower 128 bytes read/write, upper 128 bytes random values and read-only)
--                             (last 8 bytes are UUID64, which can be used to derive a 48bit unique MAC address)
--                             We use it only to map these last 8 bytes.
--                           Registers $F8 - $FF
--   0x51 = RV-3032-C7 = RTC
--                           Registers $00 - $2F
--
--   0x40 = IO Expander for board revision and dip-switchinfo
--   0x61 = DC-DC converter
--   0x67 = DC-DC converter
--
-- 8-bit read addresses:
-- 0xA9, 0xA1, 0xDF, 0xAF

-- @IO:GS $FFD7100-07 UUID:UUID64 64-bit UUID. Can be used to seed ethernet MAC address
-- @IO:GS $FFD7110-3F RTC:RTC Real-time Clock
-- @IO:GS $FFD7110 RTC:RTCSEC Real-time Clock seconds value (binary coded decimal)
-- @IO:GS $FFD7111 RTC:RTCMIN Real-time Clock minutes value (binary coded decimal)
-- @IO:GS $FFD7112 RTC:RTC!HOUR Real-time Clock hours value (binary coded decimal)
-- @IO:GS $FFD7112.0-5 RTC:RTC!HOUR Real-time Clock hours value (binary coded decimal)
-- @IO:GS $FFD7112.5 RTC:RTC!HOURPM Real-time Clock PM indicator (12h mode only)
-- @IO:GS $FFD7112.7 RTC:RTC!HOUR24EN Real-time Clock 24 hour mode enabled
-- @IO:GS $FFD7113 RTC:RTCDAY Real-time Clock day of month value (binary coded decimal)
-- @IO:GS $FFD7114 RTC:RTCMONTH Real-time Clock month value (binary coded decimal)
-- @IO:GS $FFD7115 RTC:RTCYEAR Real-time Clock year value (binary coded decimal)
-- @IO:GS $FFD7116 RTC:RTCDOW Real-time Clock day of week value 0-6 (binary coded decimal)


-- @IO:GS $FFD7140-7F RTC:NVRAM 64-bytes of non-volatile RAM. Can be used for storing machine configuration.


use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity mega65r5_board_i2c is
  generic ( clock_frequency : integer);
  port (
    clock : in std_logic;

    ear_watering_mode : in std_logic := '0';
    
    -- I2C bus
    sda : inout std_logic;
    scl : inout std_logic;

    dipsw_read : out std_logic_vector(7 downto 0);
    board_major : out unsigned(3 downto 0);
    board_minor : out unsigned(3 downto 0)    

    );
end mega65r5_board_i2c;

architecture behavioural of mega65r5_board_i2c is

  signal dipsw_int : std_logic_vector(7 downto 0) := (others => '0');
  
  signal i2c1_address : unsigned(6 downto 0) := to_unsigned(0,7);
  signal i2c1_address_internal : unsigned(6 downto 0) := to_unsigned(0,7);
  signal i2c1_rdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c1_wdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c1_wdata_internal : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c1_latch_toggle : std_logic;
  signal i2c1_busy : std_logic := '0';
  signal i2c1_busy_last : std_logic := '0';
  signal i2c1_rw : std_logic := '0';
  signal i2c1_rw_internal : std_logic := '0';
  signal i2c1_error : std_logic := '0';
  signal i2c1_reset : std_logic := '1';
  signal i2c1_command_en : std_logic := '0';
  signal command_en : std_logic := '0';
  signal command_continue : std_logic := '0';
  signal v0 : unsigned(7 downto 0) := to_unsigned(0,8);
  signal v1 : unsigned(7 downto 0) := to_unsigned(0,8);

  signal latch_count : integer range 0 to 255 := 150;
  signal last_latch_count : integer range 0 to 255 := 150;
  signal last_latch : std_logic := '1';

  subtype uint8 is unsigned(7 downto 0);
  type byte_array is array (0 to 255) of uint8;
  signal bytes : byte_array := (others => x"bd");

  signal write_job_pending : std_logic := '0';
  signal write_addr : unsigned(7 downto 0) := x"48";
  signal write_reg : unsigned(7 downto 0) := x"02";
  signal write_val : unsigned(7 downto 0) := x"99";

  signal i2c1_swap : std_logic := '0';
  signal i2c1_debug_sda : std_logic := '0';
  signal i2c1_debug_scl : std_logic := '0';
  signal debug_status : unsigned(5 downto 0) := "000000";

  signal port0 : unsigned(7 downto 0);
  signal port1 : unsigned(7 downto 0);
  
begin

  i2c1: entity work.i2c_master
    generic map (
      input_clk => clock_frequency,
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
      latch_toggle => i2c1_latch_toggle,
      sda => sda,
      scl => scl,
      swap => i2c1_swap,
      debug_sda => i2c1_debug_sda,
      debug_scl => i2c1_debug_scl
      );

  process (clock) is
  begin

    if rising_edge(clock) then

      dipsw_read <= dipsw_int;
      
      -- Activate command
      if command_en = '1' and i2c1_busy = '0' and command_en='1' then
        report "Enabling command";
      end if;
      i2c1_command_en <= command_en;

      -- State machine for reading registers from the various
      -- devices.
      last_latch <= i2c1_latch_toggle;
      if i2c1_latch_toggle /= last_latch then
        latch_count <= latch_count + 1;
      end if;
      last_latch_count <= latch_count;

      case latch_count is
        -- Enable force PWM mode for DCDC converter #1
        when 0 =>
          command_continue <= '0';
          command_en <= '1';
          i2c1_address <= "1100001"; -- 0x61 = I2C address of device;
          i2c1_wdata <= x"01";
          i2c1_rw <= '0';
        when 1 =>
          -- Continue previous transaction
          command_continue <= '1';
          command_en <= '1';
          i2c1_rw <= '0';
          -- Default settings + set bit 0 to 1 to force PWM mode or leave it 0
          -- to make your ears water from the annoying high frequency sounds
          i2c1_wdata <= x"A6";
          i2c1_wdata(0) <= not ear_watering_mode;

        -- Enable force PWM mode for DCDC converter #2
        when 2 =>
          command_continue <= '0';
          command_en <= '1';
          i2c1_address <= "1100111"; -- 0x67 = I2C address of device;
          i2c1_wdata <= x"01";
          i2c1_rw <= '0';
        when 3 =>
          command_en <= '1';
          i2c1_rw <= '0';
          -- Default settings + set bit 0 to 1 to force PWM mode or leave it 0
          -- to make your ears water from the annoying high frequency sounds
          i2c1_wdata <= x"A6";
          i2c1_wdata(0) <= not ear_watering_mode;

        -- Read DIP switches and board revision straps
        when 4 =>
          command_en <= '1';
          i2c1_address <= "1000001"; -- 0x41 = I2C address of device;
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
        when 5 =>
          command_en <= '1';
          i2c1_rw <= '1';
        when 6 =>
          port0 <= i2c1_rdata;
          command_en <= '1';
          i2c1_rw <= '1';
        when 7 =>
          port1 <= i2c1_rdata;
          
        when others =>
          command_en <= '0';
          latch_count <= 0;
          last_latch <= i2c1_latch_toggle;
          write_job_pending <= '0';
      end case;

    end if;
  end process;
end behavioural;



