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

entity mega65r4_i2c is
  generic ( clock_frequency : integer);
  port (
    clock : in std_logic;

    -- I2C bus
    sda : inout std_logic;
    scl : inout std_logic;

    grove_rtc_present : in std_logic;
    reg_in : in unsigned(7 downto 0);
    val_in : in unsigned(7 downto 0);

    -- FastIO interface
    cs : in std_logic;
    fastio_read : in std_logic;
    fastio_write : in std_logic;
    fastio_rdata : out unsigned(7 downto 0);
    fastio_wdata : in unsigned(7 downto 0);
    fastio_addr : in unsigned(19 downto 0)

    );
end mega65r4_i2c;

architecture behavioural of mega65r4_i2c is

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
  signal i2c1_command_en : std_logic := '0';
  signal command_en : std_logic := '0';
  signal v0 : unsigned(7 downto 0) := to_unsigned(0,8);
  signal v1 : unsigned(7 downto 0) := to_unsigned(0,8);

  signal busy_count : integer range 0 to 255 := 150;
  signal last_busy_count : integer range 0 to 255 := 150;
  signal last_busy : std_logic := '1';

  subtype uint8 is unsigned(7 downto 0);
  type byte_array is array (0 to 255) of uint8;
  signal bytes : byte_array := (others => x"bd");

  signal write_job_pending : std_logic := '0';
  signal write_addr : unsigned(7 downto 0) := x"48";
  signal write_reg : unsigned(7 downto 0) := x"02";
  signal write_val : unsigned(7 downto 0) := x"99";

  signal delayed_en : integer range 0 to 65535 := 0;

  signal i2c1_swap : std_logic := '0';
  signal i2c1_debug_sda : std_logic := '0';
  signal i2c1_debug_scl : std_logic := '0';
  signal debug_status : unsigned(5 downto 0) := "000000";

  type rtc_vals is array (0 to 7) of uint8;
  signal rtc_prev1 : rtc_vals := (others => x"00");
  signal rtc_prev2 : rtc_vals := (others => x"00");

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
      sda => sda,
      scl => scl,
      swap => i2c1_swap,
      debug_sda => i2c1_debug_sda,
      debug_scl => i2c1_debug_scl
      );

  process (clock,cs,fastio_read,fastio_addr) is
  begin

    if cs='1' and fastio_read='1' then
--      if fastio_addr(7) = '0' then
        report "reading buffered I2C data";
        fastio_rdata <= bytes(to_integer(fastio_addr(7 downto 0)));
--      elsif fastio_addr(7 downto 0) = "11111111" then
--        -- Show busy status for writing
--        fastio_rdata <= (others => write_job_pending);
--      elsif fastio_addr(7 downto 0) = "11111110" then
--        -- Show error status from I2C
--        fastio_rdata <= (others => i2c1_error);
--      elsif fastio_addr(7 downto 0) = "11111101" then
--        -- Show error status from I2C
--        fastio_rdata(7 downto 6) <= "10";
--        fastio_rdata(5 downto 0) <= debug_status;
--      else
--        -- Else for debug show busy count
--        fastio_rdata <= to_unsigned(busy_count,8);
--      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if;

    if rising_edge(clock) then

      -- If an external RTC is connected, use that in place of
      -- the internal one.
      -- The grove_i2c will sniff the bus for writes to the
      -- addresses here, making it R/W.
      if grove_rtc_present='1' then
        case reg_in is
          -- Convert between register layout of the two
          when x"00" => bytes(16 + 0) <= val_in;
          when x"01" => bytes(16 + 1) <= val_in;
          when x"02" => bytes(16 + 2)(5 downto 0) <= val_in(5 downto 0);
                        bytes(16 + 2)(6) <= '0';
                        bytes(16 + 2)(7) <= not val_in(6);
          when x"03" => bytes(16 + 6) <= val_in - to_unsigned(1,8);
                        bytes(16 + 6)(7 downto 3) <= (others => '0');
          when x"04" => bytes(16 + 3) <= val_in;
          when x"05" => bytes(16 + 4) <= val_in;
          when x"06" => bytes(16 + 5) <= val_in;
          when others => null;
        end case;
      end if;


      -- Must come first, so state machines below can set delayed_en
      if delayed_en /= 0 then
        report "Waiting for delay to expire: " & integer'image(delayed_en);
        delayed_en <= delayed_en - 1;
        if delayed_en = 1024 then
          i2c1_command_en <= '0';
        end if;
      else
--        report "No command delay: busy=" & std_logic'image(i2c1_busy) & ", last_busy=" & std_logic'image(last_busy);
        -- Activate command
        if command_en = '1' and i2c1_busy = '0' and command_en='1' then
          report "Enabling command";
        end if;
        i2c1_command_en <= command_en;
        if i2c1_busy = '1' and last_busy = '0' then
          report "Command latched.";
          command_en <= '0';
        end if;
      end if;

      -- Write to registers as required
      if cs='1' and fastio_write='1' then
        if (to_integer(fastio_addr(7 downto 0)) >= 16 and to_integer(fastio_addr(7 downto 0)) < 220) then
          -- RTC
          write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 16,8);
--          report "triggering write to I2C device $A2, register $" & to_hstring(fastio_addr(7 downto 0));
          write_addr <= x"A2";
          write_job_pending <= '1';
        elsif to_integer(fastio_addr(7 downto 0)) >= 220 and to_integer(fastio_addr(7 downto 0)) < 239 then
          -- Audio Amplifier for internal speakers
          write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 220,8);
          write_addr <= x"68";
          write_job_pending <= '1';
        elsif fastio_addr(7 downto 0) = x"F0" then
          i2c1_debug_scl <= '0';
          debug_status(0) <= '0';
        elsif fastio_addr(7 downto 0) = x"F1" then
          i2c1_debug_scl <= '1';
          debug_status(0) <= '1';
        elsif fastio_addr(7 downto 0) = x"F2" then
          i2c1_debug_sda <= '0';
          debug_status(1) <= '0';
        elsif fastio_addr(7 downto 0) = x"F3" then
          i2c1_debug_sda <= '1';
          debug_status(1) <= '1';
        elsif fastio_addr(7 downto 0) = x"F4" then
          i2c1_swap <= '0';
          debug_status(2) <= '0';
        elsif fastio_addr(7 downto 0) = x"F5" then
          i2c1_swap <= '1';
          debug_status(2) <= '1';
        elsif fastio_addr(7 downto 0) = x"FE" then
          i2c1_reset <= '0';
          debug_status(3) <= '0';
        elsif fastio_addr(7 downto 0) = x"FF" then
          i2c1_reset <= '1';
          debug_status(3) <= '1';
        end if;
        write_val <= fastio_wdata;
      end if;

      -- State machine for reading registers from the various
      -- devices.
      last_busy <= i2c1_busy;
      if i2c1_busy='1' and last_busy='0' then

        -- Sequence through the list of transactions endlessly
        if (busy_count < 244) or ((write_job_pending='1') and (busy_count < (244+4))) then
          busy_count <= busy_count + 1;
          report "busy_count = " & integer'image(busy_count + 1);
          -- Delay switch to write so we generate a stop before hand and after
          -- the write.
          if ((busy_count = (244-1)) or (busy_count = (244+1))) and (delayed_en = 0) then
            delayed_en <= 1024;
          end if;
        else
          busy_count <= 0;
          -- Make sure we really start the job a new each round
          delayed_en <= 1024;
        report "busy_count = " & integer'image(0);
        end if;
      end if;
      last_busy_count <= busy_count;

      case busy_count is
        -- The body for this case statement can be automatically generated
        -- using src/tools/i2cstatemapper.c

        --------------------------------------------------------------------
        -- Start of Auto-Generated Content
        --------------------------------------------------------------------
        when 0 =>
--          report "Serial EEPROM UUID";
          command_en <= '1';
          i2c1_address <= "1010000"; -- 0xA1/2 = I2C address of device;
          i2c1_wdata <= x"F8";
          i2c1_rw <= '0';
        when 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 =>
          -- Read the 8 bytes from the device
          i2c1_rw <= '1';
          command_en <= '1';
          if busy_count > 1 then
            bytes(busy_count - 1 - 1 + 0) <= i2c1_rdata;
          end if;
        when 10 =>
          report "Real Time clock regs 0 -- 2F";
          command_en <= '1';
          i2c1_address <= "1010001"; -- 0x51 = I2C address of device;
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
        when 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 | 30 | 31 | 32 | 33 | 34 | 35 | 36 | 37 | 38 | 39 | 40 | 41 | 42 | 43 | 44 | 45 | 46 | 47 | 48 | 49 | 50 | 51 | 52 | 53 | 54 | 55 | 56 | 57 | 58 | 59 =>
          -- Read the 48 bytes from the device
          i2c1_rw <= '1';
          command_en <= '1';
          -- The first 6 registers are the RTC values.
          -- To avoid glitching in I2C reading causing trouble, we
          -- double-buffer the RTC values, and only update the user-visible values
          -- if two successive reads are identical.
          if grove_rtc_present='0' then
            if busy_count = 11 then
              rtc_prev2 <= rtc_prev1;
            end if;
            if busy_count >= 13 and busy_count < (13+8) then
              rtc_prev1(busy_count-12) <= i2c1_rdata;
            elsif busy_count >= (13 + 8) then
              bytes(busy_count - 1 - 11 + 16) <= i2c1_rdata;
            end if;
            -- Remap RTC registers to match those on the R3
            -- We only rearrange the first 7 registers
            if busy_count >= 13 and busy_count < (13 + 8 ) then
              -- debounce RTC registers, except for 100ths of a second
              if (busy_count = 13) or (rtc_prev1(busy_count - 13) = rtc_prev2(busy_count - 13)) then
                case busy_count is
                  when 13 + 0 => -- Read 100ths of seconds, write to reg 7
                    bytes(16 + 7) <= rtc_prev1(busy_count - 13);
                  when 13 + 1 => -- Read seconds, write to reg 0
                    bytes(16 + 0) <= rtc_prev1(busy_count - 13);
                  when 13 + 2 => -- Read minuntes, write to reg 1
                    bytes(16 + 1) <= rtc_prev1(busy_count - 13);
                  when 13 + 3 => -- Read 24-hour clock hours, write to reg 2,
                    -- with bit 7 set
                    bytes(16 + 2)(6 downto 0) <= rtc_prev1(busy_count - 13)(6 downto 0);
                    bytes(16 + 2)(7) <= '1';
                  when 13 + 4 => -- Read weekday, write to reg 6
                    bytes(16 + 6) <= rtc_prev1(busy_count - 13);
                  when 13 + 5 => -- Read day of month, write to reg 3
                    bytes(16 + 3) <= rtc_prev1(busy_count - 13);
                  when 13 + 6 => -- Read month, write to reg 4
                    bytes(16 + 4) <= rtc_prev1(busy_count - 13);
                  when 13 + 7 => -- Read year-2000, write to reg 5
                    bytes(16 + 5) <= rtc_prev1(busy_count - 13);
                  when others => null;
                end case;
              end if;
            end if;
          end if;
        when 60 =>
          report "RTC SRAM (16 bytes)";
          command_en <= '1';
          i2c1_address <= "1010001"; -- 51 = I2C address of device;
          i2c1_wdata <= x"30"; -- Some extra registers in the $3x range, and
                               -- also 16 bytes of NVRAM starts at offset $40
                               -- plus some more bytes, for no really good reason
          i2c1_rw <= '0';
        when 61 | 62 | 63 | 64 | 65 | 66 | 67 | 68 | 69 | 70 | 71 | 72 | 73 | 74 | 75 | 76
          | 77 | 78 | 79 | 80 | 81 | 82 | 83 | 84 | 85 | 86 | 87 | 88 | 89 | 90 | 91 | 92
          | 93 | 94 | 95 | 96 | 97 | 98 | 99 | 100 | 101 | 102 | 103 | 104 | 105 | 106 | 107 | 108
          | 109 | 110 | 111 | 112 | 113 | 114 | 115 | 116 | 117 | 118 | 119 | 120 | 121 | 122 | 123 | 124
          | 125 | 126 | 127 | 128 | 129 | 130 | 131 | 132 | 133 | 134 | 135 | 136 | 137 | 138 | 139 | 140
          | 141 | 142 | 143 | 144 | 145 | 146 | 147 | 148 | 149 | 150 | 151 | 152 | 153 | 154 | 155 | 156
          | 157 | 158 | 159 | 160 | 161 | 162 | 163 | 164 | 165 | 166 | 167 | 168 | 169 | 170 | 171 | 172
          | 173 | 174 | 175 | 176 | 177 | 178 | 179 | 180 | 181 | 182 | 183 | 184 | 185 | 186 | 187 | 188
          | 189 | 190 | 191 | 192 | 193 | 194 | 195 | 196 | 197 | 198 | 199 | 200 | 201 | 202 | 203 | 204
          | 205 | 206 | 207 | 208 | 209 | 210 | 211 | 212 | 213 | 214 | 215 | 216 | 217 | 218 | 219 | 220
          | 221
          =>
          -- Read the 64 bytes from the device
          i2c1_rw <= '1';
          command_en <= '1';
          -- Make sure we send a STOP before the next command starts
          -- NOTE: This is done above in the incrementer for busy_count
          if busy_count > 61 then
            bytes(busy_count - 1 - 61 + 64) <= i2c1_rdata;
          end if;
        when 222 =>
          i2c1_command_en <= '1';
          i2c1_address <= "0011001"; -- 0x19 = I2C address of amplifier;
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
          report "Audio amplifier regs 0 - 18";
        when 223 | 224 | 225 | 226 | 227 | 228 | 229 | 230 | 231 | 232 | 233 | 234 | 235 | 236 | 237 | 238
          | 239 | 240 | 241 | 242
          | 243 =>
          -- Read the 19 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 223 and i2c1_error='0' then
            bytes(busy_count - 1 - 223 + 220) <= i2c1_rdata;
          end if;
        --------------------------------------------------------------------
        -- End of Auto-Generated Content
        --------------------------------------------------------------------
        when 244 =>
          -- Write to a register, if a request is pending:
          -- First, write the address and register number.
          if last_busy_count /= busy_count then
            report "Writing to register $" & to_hstring(write_reg);
          end if;
          i2c1_rw <= '0';
          command_en <= '1';
          i2c1_address <= write_addr(7 downto 1);
          -- If writing to RTC registers, remap them to look like the R3 RTC
          if write_addr = x"a2" then
            i2c1_wdata <= write_reg;
            case write_reg is
              when x"00" => i2c1_wdata <= x"01"; -- seconds
              when x"01" => i2c1_wdata <= x"02"; -- minutes
              when x"02" => i2c1_wdata <= x"03"; -- hours
              when x"03" => i2c1_wdata <= x"05"; -- day of month
              when x"04" => i2c1_wdata <= x"06"; -- month
              when x"05" => i2c1_wdata <= x"07"; -- year - 2000
              when x"06" => i2c1_wdata <= x"04"; -- day of week
              when others => null;
            end case;
          else
            i2c1_wdata <= write_reg;
          end if;
        when 245 =>
          -- Second, write the actual value into the register
          if last_busy_count /= busy_count then
            report "Writing value $" & to_hstring(write_val) & " to register";
          end if;
          -- Make sure we send a STOP before the next command starts
          -- NOTE: This is done above in the incrementer for busy_count
          command_en <= '1';
          i2c1_rw <= '0';
          i2c1_wdata <= write_val;
        when others =>
          if last_busy_count /= busy_count then
            report "in others";
          end if;
          -- Make sure we can't get stuck.
          command_en <= '0';
          busy_count <= 0;
          last_busy <= '1';
          write_job_pending <= '0';
      end case;

    end if;
  end process;
end behavioural;



