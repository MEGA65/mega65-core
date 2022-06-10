--
-- Written by
--    Paul Gardner-Stephen, <paul@m-e-g-a.org>  2018-2022
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

--   0x57 = DS1307     = 8 RTC registers followed by 56 NVRAM bytes in the RTC
--
-- 8-bit read addresses:
-- 0xD1

-- @IO:GS $FFD7110-3F RTC:RTC Real-time Clock
-- @IO:GS $FFD7110 RTC:RTCSEC Real-time Clock seconds value (binary coded decimal)
-- @IO:GS $FFD7111 RTC:RTCMIN Real-time Clock minutes value (binary coded decimal)
-- @IO:GS $FFD7112 RTC:RTCHOUR Real-time Clock hours value (binary coded decimal)
-- @IO:GS $FFD7113 RTC:RTCDAY Real-time Clock day of month value (binary coded decimal)
-- @IO:GS $FFD7114 RTC:RTCMONTH Real-time Clock month value (binary coded decimal)
-- @IO:GS $FFD7115 RTC:RTCYEAR Real-time Clock year value (binary coded decimal)


-- @IO:GS $FFD7140-7F RTC:NVRAM 56-bytes of non-volatile RAM. Can be used for storing machine configuration.


use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity grove_i2c is
  generic ( clock_frequency : integer);
  port (
    clock : in std_logic;
    
    -- I2C bus
    sda : inout std_logic;
    scl : inout std_logic;

    grove_rtc_present : out std_logic := '0';
    
    -- FastIO interface
    cs : in std_logic;
    fastio_read : in std_logic;
    fastio_write : in std_logic;
    fastio_rdata : out unsigned(7 downto 0);
    fastio_wdata : in unsigned(7 downto 0);
    fastio_addr : in unsigned(19 downto 0)    
    
    );
end grove_i2c;

architecture behavioural of grove_i2c is

  signal grove_rtc_present_drive : std_logic := '0';
  
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

  signal busy_count : integer range 0 to 255 := 0;
  signal last_busy_count : integer range 0 to 255 := 0;
  signal last_busy : std_logic := '1';
  
  subtype uint8 is unsigned(7 downto 0);
  type byte_array is array (0 to 63) of uint8;
  signal bytes : byte_array := (others => x"00");

  signal write_job_pending : std_logic := '0';
  signal write_reg : unsigned(7 downto 0) := x"02";
  signal write_val : unsigned(7 downto 0) := x"99";

  signal read_i2c_addr : unsigned(7 downto 0) := x"d1";
  signal write_i2c_addr : unsigned(7 downto 0) := x"d0";
  
  signal delayed_en : integer range 0 to 65535 := 0;

  signal i2c1_swap : std_logic := '0';
  signal i2c1_debug_sda : std_logic := '0';
  signal i2c1_debug_scl : std_logic := '0';
  signal debug_status : unsigned(5 downto 0) := "000000";

begin

  i2c1: entity work.i2c_master
    generic map (
      input_clk => clock_frequency,
      -- The DS1307 only works at 100KHz ! No 400KHz mode supported !
      bus_clk => 100_000
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
      if fastio_addr(7 downto 6) = "00" then
        report "reading buffered I2C data";
        fastio_rdata <= bytes(to_integer(fastio_addr(5 downto 0)));
      elsif fastio_addr(7 downto 0) = x"fd" then
        fastio_rdata <= x"00";
        fastio_rdata(1) <= sda;
        fastio_rdata(0) <= scl;
      elsif fastio_addr(7 downto 0) = x"fe" then
        fastio_rdata <= write_i2c_addr;
      elsif fastio_addr(7 downto 0) = x"ff" then
        fastio_rdata <= read_i2c_addr;
      else
        fastio_rdata <= x"FF";
      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if;
    
    if rising_edge(clock) then

      grove_rtc_present <= grove_rtc_present_drive;
      
      -- Must come first, so state machines below can set delayed_en
      if delayed_en /= 0 then
--        report "Waiting for delay to expire: " & integer'image(delayed_en);
        delayed_en <= delayed_en - 1;
        if delayed_en = 1024 then
          i2c1_command_en <= '0';
          report "Clearing i2c1_command_en due to delayed_en=1024";
        end if;
      else
--        report "No command delay: busy=" & std_logic'image(i2c1_busy) & ", last_busy=" & std_logic'image(last_busy);
        -- Activate command
        i2c1_command_en <= command_en;
        if i2c1_busy = '1' and last_busy = '0' then
          report "Command latched.";
          command_en <= '0';
        end if;
      end if;           
      
      -- Write to registers as required
      if cs='1' and fastio_write='1' then
        if to_integer(fastio_addr(7 downto 0)) >= 0 and to_integer(fastio_addr(7 downto 0)) < 64 then
          -- RTC registers and SRAM
          write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 0,8);
          write_job_pending <= '1';
        elsif fastio_addr(7 downto 0) = x"fd" then
--          if fastio_wdata(7)='0' then
--            sda <= 'Z';
--          else
--            sda <= fastio_wdata(6);
--          end if;
--          if fastio_wdata(5)='0' then
--            scl <= 'Z';
--          else
--            scl <= fastio_wdata(4);
--          end if;
        elsif fastio_addr(7 downto 0) = x"fe" then
          write_i2c_addr <= fastio_wdata;
        elsif fastio_addr(7 downto 0) = x"ff" then
          read_i2c_addr <= fastio_wdata;
        end if;
        write_val <= fastio_wdata;
      end if;
      
      -- State machine for reading registers from the various
      -- devices.
      last_busy <= i2c1_busy;
      if i2c1_busy='1' and last_busy='0' then

        -- Clear command between operations, so that we don't write to any
        -- registers when selecting the regiser to read.
        i2c1_rw <= '0';
        command_en <= '0';                  
        
        -- Sequence through the list of transactions endlessly
        if (busy_count < 66) or ((write_job_pending='1') and (busy_count < (66+4))) then
          busy_count <= busy_count + 1;
          report "busy_count = " & integer'image(busy_count + 1);
          -- Delay switch to write so we generate a stop before hand and after
          -- the write.
          if ((busy_count = 66-1) or (busy_count = 66+1)) and (delayed_en = 0) then
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
--          report "Read RTC registers";

          -- Send write address and register 0
          command_en <= '1';
          i2c1_address <= write_i2c_addr(7 downto 1); 
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
        when 1 =>
          -- Then switch to read, reading from register 0
          command_en <= '1';
          i2c1_address <= read_i2c_addr(7 downto 1); 
          i2c1_wdata <= x"00";
          i2c1_rw <= '1';
        when
          2 |  3 |  4 |  5 |  6 |  7 |  8 |  9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
          17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 | 30 | 31 | 32 |
          33 | 34 | 35 | 36 | 37 | 38 | 39 | 40 | 41 | 42 | 43 | 44 | 45 | 46 | 47 | 48 |
          49 | 50 | 51 | 52 | 53 | 54 | 55 | 56 | 57 | 58 | 59 | 60 | 61 | 62 | 63 | 64 |
          65 =>
          i2c1_rw <= '1';
          command_en <= '1';          
          if busy_count > 1 then
            bytes(busy_count - 2) <= i2c1_rdata;
          end if;
        --------------------------------------------------------------------
        -- End of Auto-Generated Content
        --------------------------------------------------------------------        
        when 66 =>
          -- Write to a register, if a request is pending:
          -- First, write the address and register number.
          if last_busy_count /= busy_count then
            report "Writing to register $" & to_hstring(write_reg);
          end if;
          i2c1_rw <= '0';
          command_en <= '1';
          i2c1_address <= write_i2c_addr(7 downto 1);
          i2c1_wdata <= write_reg;
        when 67 =>
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



