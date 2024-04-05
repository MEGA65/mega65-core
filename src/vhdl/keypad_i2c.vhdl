--
-- Written by
--    Paul Gardner-Stephen, Flinders University <paul.gardner-stephen@flinders.edu.au>  2018-2020
--    Paul Gardner-Stephen, 2023-2024
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
--
-- PCA9555/PCA9535 use address 0100xxx = $20 - $27 in 7-bit notation
--
-- This means the 8-bit addresses for reading are the odd addresses in the
-- range $41-$4F.


-- @IO:GS $FFD7500-07 I2C:EXPR0
-- @IO:GS $FFD7508-0F I2C:EXPR1
-- @IO:GS $FFD7510-17 I2C:EXPR2
-- @IO:GS $FFD7518-1F I2C:EXPR3
-- @IO:GS $FFD7520-27 I2C:EXPR4
-- @IO:GS $FFD7528-2F I2C:EXPR5
-- @IO:GS $FFD7530-37 I2C:EXPR6
-- @IO:GS $FFD7538-3F I2C:EXPR7
-- @IO:GS $FFD7500 I2C:EXP0IN0
-- @IO:GS $FFD7501 I2C:EXP0IN1
-- @IO:GS $FFD7502 I2C:EXP0OUT0
-- @IO:GS $FFD7503 I2C:EXP0OUT1
-- @IO:GS $FFD7504 I2C:EXP0INVERT0
-- @IO:GS $FFD7505 I2C:EXP0INVERT1
-- @IO:GS $FFD7506 I2C:EXP0CONF0
-- @IO:GS $FFD7507 I2C:EXP0CONF1

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity keypad_i2c is
  generic ( clock_frequency : integer);
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
end keypad_i2c;

architecture behavioural of keypad_i2c is

  constant max_state : integer := 127;
  
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
  signal write_count : unsigned(7 downto 0) := to_unsigned(0,8);
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

  process (clock,cs,fastio_read,fastio_addr,write_job_pending,i2c1_error,debug_status,busy_count) is
  begin

    if cs='1' and fastio_read='1' then
      if fastio_addr(7) = '0' then
        report "reading buffered I2C data addr $" & to_hexstring(fastio_addr(7 downto 0)) & " = $"
          & to_hexstring(bytes(to_integer(fastio_addr(7 downto 0))));
        fastio_rdata <= bytes(to_integer(fastio_addr(7 downto 0)));
      elsif fastio_addr(7 downto 0) = "11111111" then
        -- Show busy status for writing
        fastio_rdata <= (others => write_job_pending);
      elsif fastio_addr(7 downto 0) = "11111110" then
        -- Show error status from I2C
        fastio_rdata <= (others => i2c1_error);
      elsif fastio_addr(7 downto 0) = "11111101" then
        -- Show error status from I2C
        fastio_rdata(7 downto 6) <= "10";
        fastio_rdata(5 downto 0) <= debug_status;
      elsif fastio_addr(7 downto 0) = "11111100" then
        report "reading magic $42 register";
        fastio_rdata <= x"42";
      elsif fastio_addr(7 downto 0) = "11111011" then
        fastio_rdata <= write_count;
      else
        -- Else for debug show busy count
        fastio_rdata <= to_unsigned(busy_count,8);
      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if;

    if rising_edge(clock) then

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
        if fastio_addr(7)='0' then
          -- This is nice and easy here, because we have 8 identical I2C IO expanders
          write_reg(7 downto 3) <= (others => '0');
          write_reg(2 downto 0) <= fastio_addr(2 downto 0);
          write_addr(7 downto 4) <= "0100";
          write_addr(3 downto 1) <= fastio_addr(5 downto 3);
          write_addr(0) <= '0';
          write_val <= fastio_wdata;
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
      end if;

      -- State machine for reading registers from the various
      -- devices.
      last_busy <= i2c1_busy;
      if i2c1_busy='1' and last_busy='0' then

        -- Sequence through the list of transactions endlessly
        if (busy_count < (max_state-1)) or ((write_job_pending='1') and (busy_count < (max_state+4))) then
          busy_count <= busy_count + 1;
          report "busy_count = " & integer'image(busy_count + 1);
          -- Delay switch to write so we generate a stop before hand and after
          -- the write.
          if ((busy_count = max_state) or (busy_count = (max_state+2))) and (delayed_en = 0) then
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
          report "IO Expander #0 regs 0-1";
          i2c1_command_en <= '1';
          i2c1_address <= "0100000"; -- 0x40/2 = I2C address of device;
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
        when 1 | 2 | 3 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 1 then
            bytes(busy_count - 1 - 1 + 0) <= i2c1_rdata;
          end if;
        when 4 =>
          report "IO Expander #0 regs 2-3";
          i2c1_command_en <= '1';
          i2c1_address <= "0100000"; -- 0x40/2 = I2C address of device;
          i2c1_wdata <= x"02";
          i2c1_rw <= '0';
        when 5 | 6 | 7 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 5 then
            bytes(busy_count - 1 - 5 + 2) <= i2c1_rdata;
          end if;
        when 8 =>
          report "IO Expander #0 regs 4-5";
          i2c1_command_en <= '1';
          i2c1_address <= "0100000"; -- 0x40/2 = I2C address of device;
          i2c1_wdata <= x"04";
          i2c1_rw <= '0';
        when 9 | 10 | 11 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 9 then
            bytes(busy_count - 1 - 9 + 4) <= i2c1_rdata;
          end if;
        when 12 =>
          report "IO Expander #0 regs 6-7";
          i2c1_command_en <= '1';
          i2c1_address <= "0100000"; -- 0x40/2 = I2C address of device;
          i2c1_wdata <= x"06";
          i2c1_rw <= '0';
        when 13 | 14 | 15 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 13 then
            bytes(busy_count - 1 - 13 + 6) <= i2c1_rdata;
          end if;
        when 16 =>
          report "IO Expander #1 regs 0-1";
          i2c1_command_en <= '1';
          i2c1_address <= "0100001"; -- 0x42/2 = I2C address of device;
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
        when 17 | 18 | 19 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 17 then
            bytes(busy_count - 1 - 17 + 8) <= i2c1_rdata;
          end if;
        when 20 =>
          report "IO Expander #1 regs 2-3";
          i2c1_command_en <= '1';
          i2c1_address <= "0100001"; -- 0x42/2 = I2C address of device;
          i2c1_wdata <= x"02";
          i2c1_rw <= '0';
        when 21 | 22 | 23 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 21 then
            bytes(busy_count - 1 - 21 + 10) <= i2c1_rdata;
          end if;
        when 24 =>
          report "IO Expander #1 regs 4-5";
          i2c1_command_en <= '1';
          i2c1_address <= "0100001"; -- 0x42/2 = I2C address of device;
          i2c1_wdata <= x"04";
          i2c1_rw <= '0';
        when 25 | 26 | 27 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 25 then
            bytes(busy_count - 1 - 25 + 12) <= i2c1_rdata;
          end if;
        when 28 =>
          report "IO Expander #1 regs 6-7";
          i2c1_command_en <= '1';
          i2c1_address <= "0100001"; -- 0x42/2 = I2C address of device;
          i2c1_wdata <= x"06";
          i2c1_rw <= '0';
        when 29 | 30 | 31 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 29 then
            bytes(busy_count - 1 - 29 + 14) <= i2c1_rdata;
          end if;
        when 32 =>
          report "IO Expander #2 regs 0-1";
          i2c1_command_en <= '1';
          i2c1_address <= "0100010"; -- 0x44/2 = I2C address of device;
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
        when 33 | 34 | 35 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 33 then
            bytes(busy_count - 1 - 33 + 16) <= i2c1_rdata;
          end if;
        when 36 =>
          report "IO Expander #2 regs 2-3";
          i2c1_command_en <= '1';
          i2c1_address <= "0100010"; -- 0x44/2 = I2C address of device;
          i2c1_wdata <= x"02";
          i2c1_rw <= '0';
        when 37 | 38 | 39 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 37 then
            bytes(busy_count - 1 - 37 + 18) <= i2c1_rdata;
          end if;
        when 40 =>
          report "IO Expander #2 regs 4-5";
          i2c1_command_en <= '1';
          i2c1_address <= "0100010"; -- 0x44/2 = I2C address of device;
          i2c1_wdata <= x"04";
          i2c1_rw <= '0';
        when 41 | 42 | 43 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 41 then
            bytes(busy_count - 1 - 41 + 20) <= i2c1_rdata;
          end if;
        when 44 =>
          report "IO Expander #2 regs 6-7";
          i2c1_command_en <= '1';
          i2c1_address <= "0100010"; -- 0x44/2 = I2C address of device;
          i2c1_wdata <= x"06";
          i2c1_rw <= '0';
        when 45 | 46 | 47 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 45 then
            bytes(busy_count - 1 - 45 + 22) <= i2c1_rdata;
          end if;
        when 48 =>
          report "IO Expander #3 regs 0-1";
          i2c1_command_en <= '1';
          i2c1_address <= "0100011"; -- 0x46/2 = I2C address of device;
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
        when 49 | 50 | 51 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 49 then
            bytes(busy_count - 1 - 49 + 24) <= i2c1_rdata;
          end if;
        when 52 =>
          report "IO Expander #3 regs 2-3";
          i2c1_command_en <= '1';
          i2c1_address <= "0100011"; -- 0x46/2 = I2C address of device;
          i2c1_wdata <= x"02";
          i2c1_rw <= '0';
        when 53 | 54 | 55 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 53 then
            bytes(busy_count - 1 - 53 + 26) <= i2c1_rdata;
          end if;
        when 56 =>
          report "IO Expander #3 regs 4-5";
          i2c1_command_en <= '1';
          i2c1_address <= "0100011"; -- 0x46/2 = I2C address of device;
          i2c1_wdata <= x"04";
          i2c1_rw <= '0';
        when 57 | 58 | 59 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 57 then
            bytes(busy_count - 1 - 57 + 28) <= i2c1_rdata;
          end if;
        when 60 =>
          report "IO Expander #3 regs 6-7";
          i2c1_command_en <= '1';
          i2c1_address <= "0100011"; -- 0x46/2 = I2C address of device;
          i2c1_wdata <= x"06";
          i2c1_rw <= '0';
        when 61 | 62 | 63 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 61 then
            bytes(busy_count - 1 - 61 + 30) <= i2c1_rdata;
          end if;
        when 64 =>
          report "IO Expander #4 regs 0-1";
          i2c1_command_en <= '1';
          i2c1_address <= "0100100"; -- 0x48/2 = I2C address of device;
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
        when 65 | 66 | 67 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 65 then
            bytes(busy_count - 1 - 65 + 16) <= i2c1_rdata;
          end if;
        when 68 =>
          report "IO Expander #4 regs 2-3";
          i2c1_command_en <= '1';
          i2c1_address <= "0100100"; -- 0x48/2 = I2C address of device;
          i2c1_wdata <= x"02";
          i2c1_rw <= '0';
        when 69 | 70 | 71 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 69 then
            bytes(busy_count - 1 - 69 + 18) <= i2c1_rdata;
          end if;
        when 72 =>
          report "IO Expander #4 regs 4-5";
          i2c1_command_en <= '1';
          i2c1_address <= "0100100"; -- 0x48/2 = I2C address of device;
          i2c1_wdata <= x"04";
          i2c1_rw <= '0';
        when 73 | 74 | 75 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 73 then
            bytes(busy_count - 1 - 73 + 20) <= i2c1_rdata;
          end if;
        when 76 =>
          report "IO Expander #4 regs 6-7";
          i2c1_command_en <= '1';
          i2c1_address <= "0100100"; -- 0x48/2 = I2C address of device;
          i2c1_wdata <= x"06";
          i2c1_rw <= '0';
        when 77 | 78 | 79 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 77 then
            bytes(busy_count - 1 - 77 + 22) <= i2c1_rdata;
          end if;
        when 80 =>
          report "IO Expander #5 regs 0-1";
          i2c1_command_en <= '1';
          i2c1_address <= "0100101"; -- 0x4A/2 = I2C address of device;
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
        when 81 | 82 | 83 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 81 then
            bytes(busy_count - 1 - 81 + 40) <= i2c1_rdata;
          end if;
        when 84 =>
          report "IO Expander #5 regs 2-3";
          i2c1_command_en <= '1';
          i2c1_address <= "0100101"; -- 0x4A/2 = I2C address of device;
          i2c1_wdata <= x"02";
          i2c1_rw <= '0';
        when 85 | 86 | 87 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 85 then
            bytes(busy_count - 1 - 85 + 42) <= i2c1_rdata;
          end if;
        when 88 =>
          report "IO Expander #5 regs 4-5";
          i2c1_command_en <= '1';
          i2c1_address <= "0100101"; -- 0x4A/2 = I2C address of device;
          i2c1_wdata <= x"04";
          i2c1_rw <= '0';
        when 89 | 90 | 91 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 89 then
            bytes(busy_count - 1 - 89 + 44) <= i2c1_rdata;
          end if;
        when 92 =>
          report "IO Expander #5 regs 6-7";
          i2c1_command_en <= '1';
          i2c1_address <= "0100101"; -- 0x4A/2 = I2C address of device;
          i2c1_wdata <= x"06";
          i2c1_rw <= '0';
        when 93 | 94 | 95 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 93 then
            bytes(busy_count - 1 - 93 + 46) <= i2c1_rdata;
          end if;
        when 96 =>
          report "IO Expander #6 regs 0-1";
          i2c1_command_en <= '1';
          i2c1_address <= "0100110"; -- 0x4C/2 = I2C address of device;
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
        when 97 | 98 | 99 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 97 then
            bytes(busy_count - 1 - 97 + 48) <= i2c1_rdata;
          end if;
        when 100 =>
          report "IO Expander #6 regs 2-3";
          i2c1_command_en <= '1';
          i2c1_address <= "0100110"; -- 0x4C/2 = I2C address of device;
          i2c1_wdata <= x"02";
          i2c1_rw <= '0';
        when 101 | 102 | 103 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 101 then
            bytes(busy_count - 1 - 101 + 50) <= i2c1_rdata;
          end if;
        when 104 =>
          report "IO Expander #6 regs 4-5";
          i2c1_command_en <= '1';
          i2c1_address <= "0100110"; -- 0x4C/2 = I2C address of device;
          i2c1_wdata <= x"04";
          i2c1_rw <= '0';
        when 105 | 106 | 107 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 105 then
            bytes(busy_count - 1 - 105 + 52) <= i2c1_rdata;
          end if;
        when 108 =>
          report "IO Expander #6 regs 6-7";
          i2c1_command_en <= '1';
          i2c1_address <= "0100110"; -- 0x4C/2 = I2C address of device;
          i2c1_wdata <= x"06";
          i2c1_rw <= '0';
        when 109 | 110 | 111 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 109 then
            bytes(busy_count - 1 - 109 + 54) <= i2c1_rdata;
          end if;
        when 112 =>
          report "IO Expander #7 regs 0-1";
          i2c1_command_en <= '1';
          i2c1_address <= "0100111"; -- 0x4E/2 = I2C address of device;
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
        when 113 | 114 | 115 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 113 then
            bytes(busy_count - 1 - 113 + 56) <= i2c1_rdata;
          end if;
        when 116 =>
          report "IO Expander #7 regs 2-3";
          i2c1_command_en <= '1';
          i2c1_address <= "0100111"; -- 0x4E/2 = I2C address of device;
          i2c1_wdata <= x"02";
          i2c1_rw <= '0';
        when 117 | 118 | 119 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 117 then
            bytes(busy_count - 1 - 117 + 58) <= i2c1_rdata;
          end if;
        when 120 =>
          report "IO Expander #7 regs 4-5";
          i2c1_command_en <= '1';
          i2c1_address <= "0100111"; -- 0x4E/2 = I2C address of device;
          i2c1_wdata <= x"04";
          i2c1_rw <= '0';
        when 121 | 122 | 123 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 121 then
            bytes(busy_count - 1 - 121 + 60) <= i2c1_rdata;
          end if;
        when 124 =>
          report "IO Expander #7 regs 6-7";
          i2c1_command_en <= '1';
          i2c1_address <= "0100111"; -- 0x4E/2 = I2C address of device;
          i2c1_wdata <= x"06";
          i2c1_rw <= '0';
        when 125 | 126 | 127 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 125 then
            bytes(busy_count - 1 - 125 + 62) <= i2c1_rdata;
          end if;
        --------------------------------------------------------------------
        -- End of Auto-Generated Content
        --------------------------------------------------------------------
        when max_state+1 =>
          -- Write to a register, if a request is pending:
          -- First, write the address and register number.
          if last_busy_count /= busy_count then
            report "Writing to register $" & to_hstring(write_reg);
          end if;
          i2c1_rw <= '0';
          command_en <= '1';
          i2c1_address <= write_addr(7 downto 1);
          i2c1_wdata <= write_reg;

          write_count <= write_count + 1;
        when max_state+2 =>
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



