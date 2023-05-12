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

--
-- 8-bit read addresses:
-- 0xD1

-- @IO:GS $FFD7400-12 RTC:EXTRTC Optional Grove DS3231 External Real-time Clock
-- @IO:GS $FFD7400 RTC:EXTRTC!SEC External Real-time Clock seconds value (binary coded decimal)
-- @IO:GS $FFD7401 RTC:EXTRTC!MIN External Real-time Clock minutes value (binary coded decimal)
-- @IO:GS $FFD7402.0-5 RTC:EXTRTC!HOUR External Real-time Clock hours value (binary coded decimal)
-- @IO:GS $FFD7402.5 RTC:EXTRTC!HOURPM External Real-time Clock PM indicator (12h mode only)
-- @IO:GS $FFD7402.6 RTC:EXTRTC!HOUR12EN External Real-time Clock 12 hour mode enabled
-- @IO:GS $FFD7403 RTC:EXTRTC!DOW External Real-time Clock day of week value 1-7 (binary coded decimal)
-- @IO:GS $FFD7404 RTC:EXTRTC!DAY External Real-time Clock day of month value (binary coded decimal)
-- @IO:GS $FFD7405.0-4 RTC:EXTRTC!MONTH External Real-time Clock month value (binary coded decimal)
-- @IO:GS $FFD7405.7 RTC:EXTRTC!CENTURY External Real-time Clock year "carry"
-- @IO:GS $FFD7406 RTC:EXTRTC!YEAR External Real-time Clock year value (binary coded decimal)
-- @IO:GS $FFD7407.0-6 RTC:EXTRTC!A1SEC External Real-time Clock alarm 1 seconds value (binary coded decimal)
-- @IO:GS $FFD7407.7 RTC:EXTRTC!A1M1 External Real-time Clock alarm 1 mask bits 1
-- @IO:GS $FFD7408.0-6 RTC:EXTRTC!A1MIN External Real-time Clock alarm 1 minutes value (binary coded decimal)
-- @IO:GS $FFD7408.7 RTC:EXTRTC!A1M2 External Real-time Clock alarm 1 mask bits 2
-- @IO:GS $FFD7409.0-5 RTC:EXTRTC!A1HOUR External Real-time Clock alarm 1 hours value (binary coded decimal)
-- @IO:GS $FFD7409.5 RTC:EXTRTC!A1HOURPM External Real-time Clock alarm 1 hours PM indicator
-- @IO:GS $FFD7409.6 RTC:EXTRTC!A1HOUR12EN External Real-time Clock alarm 1 12 hour mode enabled
-- @IO:GS $FFD7409.7 RTC:EXTRTC!A1M3 External Real-time Clock alarm 1 mask bits 3
-- @IO:GS $FFD740A.0-2 RTC:EXTRTC!A1DOW External Real-time Clock alarm 1 day of week value (binary coded decimal)
-- @IO:GS $FFD740A.0-5 RTC:EXTRTC!A1DATE External Real-time Clock alarm 1 date value (binary coded decimal)
-- @IO:GS $FFD740A.6 RTC:EXTRTC!A1DOWSEL External Real-time Clock alarm 1 select day of week match
-- @IO:GS $FFD740A.7 RTC:EXTRTC!A1M4 External Real-time Clock alarm 1 mask bits 4
-- @IO:GS $FFD740B.0-6 RTC:EXTRTC!A2MIN External Real-time Clock alarm 2 minutes value (binary coded decimal)
-- @IO:GS $FFD740B.7 RTC:EXTRTC!A2M2 External Real-time Clock alarm 2 mask bits 2
-- @IO:GS $FFD740C.0-5 RTC:EXTRTC!A2HOUR External Real-time Clock alarm 2 hours value (binary coded decimal)
-- @IO:GS $FFD740C.5 RTC:EXTRTC!A2HOURPM External Real-time Clock alarm 2 hours PM indicator
-- @IO:GS $FFD740C.6 RTC:EXTRTC!A2HOUR12EN External Real-time Clock alarm 2 12 hour mode enabled
-- @IO:GS $FFD740C.7 RTC:EXTRTC!A2M3 External Real-time Clock alarm 2 mask bits 3
-- @IO:GS $FFD740D.0-2 RTC:EXTRTC!A2DOW External Real-time Clock alarm 2 day of week value (binary coded decimal)
-- @IO:GS $FFD740D.0-5 RTC:EXTRTC!A2DATE External Real-time Clock alarm 2 date value (binary coded decimal)
-- @IO:GS $FFD740D.6 RTC:EXTRTC!A2DOWSEL External Real-time Clock alarm 2 select day of week match
-- @IO:GS $FFD740D.7 RTC:EXTRTC!A2M4 External Real-time Clock alarm 2 mask bits 4
-- @IO:GS $FFD740E RTC:EXTRTC!CTRL External Real-time Clock control
-- @IO:GS $FFD740F RTC:EXTRTC!ST External Real-time Clock control/status register
-- @IO:GS $FFD7410 RTC:EXTRTC!AGINGOFS External Real-time Clock aging offset (do not modify!)
-- @IO:GS $FFD7411 RTC:EXTRTC!TEMPMSB External Real-time Clock temperature (MSB)
-- @IO:GS $FFD7412 RTC:EXTRTC!TEMPMSB External Real-time Clock temperature (LSB)



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
    reg_out : out unsigned(7 downto 0);
    val_out : out unsigned(7 downto 0);
    
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
  signal i2c1_reg : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c1_wdata_internal : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c1_busy : std_logic := '0';
  signal i2c1_busy_last : std_logic := '0';
  signal i2c1_rw : std_logic := '0';
  signal i2c1_rw_internal : std_logic := '0';
  signal i2c1_error : std_logic := '0';  
  signal i2c1_reset : std_logic := '1';
  signal i2c1_command_en : std_logic := '0';
  signal i2c1_rd_strobe : std_logic;
  signal i2c1_count : unsigned(15 downto 0) := (others => '0');
  signal i2c1_raddr : unsigned(7 downto 0);
  signal command_en : std_logic := '0';
  signal v0 : unsigned(7 downto 0) := to_unsigned(0,8);
  signal v1 : unsigned(7 downto 0) := to_unsigned(0,8);

  signal busy_count : integer range 0 to 255 := 0;
  signal last_busy_count : integer range 0 to 255 := 0;
  signal last_busy : std_logic := '1';

  signal rx_count : integer range 0 to 255 := 0;
  
  subtype uint8 is unsigned(7 downto 0);
  type byte_array is array (0 to 63) of uint8;
  signal bytes : byte_array := (others => x"00");

  signal write_job_pending : std_logic := '0';
  signal write_reg : unsigned(7 downto 0) := x"0d"; -- HACK: don't write 99 to 02 (hour = 19) on startup, write to EXTRTCA2DAYDATE instead
  signal write_val : unsigned(7 downto 0) := x"00"; -- initialize with 00...

  signal read_i2c_addr : unsigned(7 downto 0) := x"d1";
  signal write_i2c_addr : unsigned(7 downto 0) := x"d0";
  
  signal i2c1_swap : std_logic := '0';
  signal i2c1_debug_sda : std_logic := '0';
  signal i2c1_debug_scl : std_logic := '0';
  signal debug_status : unsigned(5 downto 0) := "000000";

  signal grove_detect_counter : integer := 1;
  signal grove_detect_neg_counter : integer := 0;
  signal last_sec : unsigned(7 downto 0) := x"00";

  signal reg_drive : unsigned(7 downto 0);
  signal val_drive : unsigned(7 downto 0);
  signal rtc_drive : std_logic := '0';
  
begin

  i2c1: entity work.i2c_controller
    generic map (
      clock_frequency => clock_frequency,
      -- The DS1307 only works at 100KHz ! No 400KHz mode supported !
      bus_clk => 100_000
      )
    port map (
      clock => clock,
      req => i2c1_command_en,
      addr => i2c1_address,
      rw => i2c1_rw,
      reg_addr => i2c1_reg,
      data_wr => i2c1_wdata,
      busy => i2c1_busy,
      data_rd => i2c1_rdata,
      rd_strobe => i2c1_rd_strobe,
      rd_addr => i2c1_raddr,
      rd_count => i2c1_count,
      
      sda => sda,
      scl => scl
      ); 
  
  process (clock,cs,fastio_read,fastio_addr,grove_detect_neg_counter,
           grove_detect_counter,grove_rtc_present_drive,write_i2c_addr,
           read_i2c_addr) is
  begin

    if cs='1' and fastio_read='1' then
      if fastio_addr(7 downto 6) = "00" then
        report "reading buffered I2C data";
        fastio_rdata <= bytes(to_integer(fastio_addr(5 downto 0)));
      elsif fastio_addr(7 downto 0) = x"fd" then
        fastio_rdata(6 downto 4) <= to_unsigned(grove_detect_neg_counter,3);
        fastio_rdata(3 downto 0) <= to_unsigned(grove_detect_counter,4);
        fastio_rdata(7) <= grove_rtc_present_drive;
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

      reg_out <= reg_drive;
      val_out <= val_drive;
      grove_rtc_present <= grove_rtc_present_drive;
      
      i2c1_command_en <= command_en;
      if i2c1_busy = '1' and last_busy = '0' then
        report "Command latched.";
        command_en <= '0';
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
      -- Update external RTC when internal RTC is written to
      if fastio_addr(19 downto 4) = x"d711" and fastio_write='1' then
        case fastio_addr(3 downto 0) is
          when x"0" => -- RTC seconds
            write_reg <= x"00"; write_job_pending <= '1'; write_val <= fastio_wdata;
          when x"1" => -- RTC minute
            write_reg <= x"01"; write_job_pending <= '1'; write_val <= fastio_wdata;
          when x"2" => -- RTC hour
            write_reg <= x"02"; write_job_pending <= '1';
            write_val(5 downto 0) <= fastio_wdata(5 downto 0);
            write_val(6) <= not fastio_wdata(7); -- on DS3231 this is 12/^24 (high for 12h mode)
            write_val(7) <= '0';
          when x"3" => -- RTC day of month
            write_reg <= x"04"; write_job_pending <= '1'; write_val <= fastio_wdata;
          when x"4" => -- RTC month
            write_reg <= x"05"; write_job_pending <= '1'; write_val <= fastio_wdata;
          when x"5" => -- RTC year
            write_reg <= x"06"; write_job_pending <= '1'; write_val <= fastio_wdata;
          when x"6" => -- RTC day of week
            write_reg <= x"03"; write_job_pending <= '1';
            write_val <= fastio_wdata + to_unsigned(1,8);
            write_val(7 downto 3) <= (others => '0');
          when others =>
            null;
        end case;
      end if;
        
      -- State machine for reading registers from the various
      -- devices.

      if i2c1_rd_strobe='1' then
        reg_drive <= i2c1_raddr;
        val_drive <= i2c1_rdata;
        report "i2c1_raddr = $" & to_hstring(i2c1_raddr);
        if i2c1_raddr < 64 then
          bytes(to_integer(i2c1_raddr)) <= i2c1_rdata;
        end if;
        if (i2c1_raddr = x"13") or (i2c1_raddr = x"26") or (i2c1_raddr = x"39") then
          report "GROVEDETECT: Checking values";
          last_sec <= i2c1_rdata;
          if (last_sec = i2c1_rdata) and (i2c1_rdata /= x"ff") then
            -- We see repeating registers every $12 regs, and its not all 1s
            -- which would indicate no connected device.
            -- We interpret this as evidence that we have a DS3231 RTC
            -- connected to the grove connector
            report "     +++";
            if grove_detect_counter /= 15 then
              grove_detect_counter <= grove_detect_counter + 1;
            else
              grove_rtc_present_drive <= '1';
            end if;
            if grove_detect_neg_counter /= 0 then
              grove_detect_neg_counter <= grove_detect_neg_counter - 1;
            end if;
          else
            -- ... anything else suggests not
            report "     ---";
            if grove_detect_counter /= 0 then
              grove_detect_counter <= grove_detect_counter - 1;
            else
              grove_rtc_present_drive <= '0';
            end if;
            if grove_detect_neg_counter /= 7 then
              grove_detect_neg_counter <= grove_detect_neg_counter + 1;
              report "neg ++";
            end if;
          end if;
        end if;
        rx_count <= rx_count + 1;
      end if;
      
      last_busy <= i2c1_busy;
      if i2c1_busy='1' and last_busy='0' then

        -- Clear command between operations, so that we don't write to any
        -- registers when selecting the regiser to read.
        i2c1_rw <= '0';
        command_en <= '0';                  
        
        -- Sequence through the list of transactions endlessly
        if (busy_count < 1) or ((write_job_pending='1') and (busy_count = 1)) then
          busy_count <= busy_count + 1;
          report "busy_count = " & integer'image(busy_count + 1);
        else
          busy_count <= 0;
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
          -- report "Read RTC registers";
          -- Send write address and register 0
          command_en <= '1';
          i2c1_address <= write_i2c_addr(7 downto 1);
          i2c1_reg <= x"00";
          i2c1_count <= to_unsigned(64,16);
          i2c1_rw <= '1';
        when 1 =>
          command_en <= '1';
          i2c1_address <= write_i2c_addr(7 downto 1);
          i2c1_reg <= write_reg;
          i2c1_wdata <= write_val;
          i2c1_count <= to_unsigned(1,16);
          i2c1_rw <= '0';
        when others =>
          -- Make sure we can't get stuck.
          command_en <= '0';
          busy_count <= 0;
          last_busy <= '1';
          write_job_pending <= '0';
      end case;

    end if;
  end process;
end behavioural;



