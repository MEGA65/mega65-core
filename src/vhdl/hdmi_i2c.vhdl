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

    -- HDMI interrupt to trigger automatic reset
    hdmi_int : in std_logic;
  
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
  signal write_addr : unsigned(7 downto 0) := x"7A";
  signal write_reg : unsigned(7 downto 0) := x"02";
  signal write_val : unsigned(7 downto 0) := x"99";

  signal delayed_en : integer range 0 to 255 := 0;
  signal last_hdmi_int : std_logic := '1';
  signal hdmi_int_latch : std_logic := '0';
  signal hdmi_reset_phase : integer := 0;
  
  ----------------------------------------------------------------------------------
  -- From:
  ----------------------------------------------------------------------------------
  -- Engineer:    Mike Field <hamster@snap.net.nz>
  -- 
  -- Module Name: i2c_sender h- Behavioral 
  --
  -- Description: Send register writes over an I2C-like interface
  --
  -- Feel free to use this how you see fit, and fix any errors you find :-)
  ----------------------------------------------------------------------------------

  
  signal   divider           : unsigned(8 downto 0)  := (others => '0'); 
  -- this value gives nearly 200ms cycles before the first register is written
  signal   initial_pause     : unsigned(7 downto 0) := (others => '0');
  signal   finished          : std_logic := '0';
  signal   address           : std_logic_vector(7 downto 0)  := (others => '0');
  signal   clk_first_quarter : std_logic_vector(28 downto 0) := (others => '1');
  signal   clk_last_quarter  : std_logic_vector(28 downto 0) := (others => '1');
  signal   busy_sr           : std_logic_vector(28 downto 0) := (others => '1');
  signal   data_sr           : std_logic_vector(28 downto 0) := (others => '1');
  signal   tristate_sr       : std_logic_vector(28 downto 0) := (others => '0');
  signal   reg_value         : std_logic_vector(15 downto 0)  := (others => '0');
  signal   i2c_wr_addr       : std_logic_vector(7 downto 0)  := x"7A";

  constant i2c_finished_token : unsigned(15 downto 0) := x"FFFF";
  
  type reg_value_pair is ARRAY(0 TO 70) OF unsigned(15 DOWNTO 0);    
  
  signal reg_value_pairs : reg_value_pair := (
    x"FE7A", -- talk to device $7A
    -------------------
    -- Powerup please!
    -------------------
    x"4110", 
    ---------------------------------------
    -- These valuse must be set as follows
    ---------------------------------------
    x"9803", x"9AE0", x"9C30", x"9D61", x"A2A4", x"A3A4", x"E0D0", x"5512", x"F900",
    
    ---------------
    -- Input mode
    ---------------
    x"3C21", -- PAL 576p 4:3 aspect ratio video mode
    x"1500", -- Simple RGB video (was $06 = YCbCr 422, DDR, External sync)
    x"4810", -- Left justified data (D23 downto 8)
    -- according to documenation, style 2 should be x"1637" but it isn't. ARGH!
--            x"1637", -- 444 output, 8 bit style 2, 1st half on rising edge - YCrCb clipping
    x"1630", -- more boring pixel format
    x"1700", -- input aspect ratio 4:3, external DE 
    x"5619", -- ouput aspect ratio 4:3, 
    x"D03C", -- auto sync data - must be set for DDR modes. No DDR clock delay
    ---------------
    -- Output mode
    ---------------
    x"AF02", -- HDMI mode
    x"4c04", -- Deep colour off (HDMI only?)     - not needed
    x"40C0", -- Turn on main HDMI data packets

    ---------------
    -- Audio setup
    ---------------
    
    x"0A9D",  -- SPDIF audio format, manual CTS
--    x"0A1D",  -- SPDIF audio format, auto CTS
    x"0B8E",  -- SPDIF audio TX enable, extract MCLK from SPDIF audio
    -- stream, i.e no separate MCLK
    x"0C00",  -- Use sampling rate encoded in the SPDIF stream instead
    -- of specifying the rate.
    x"7301",  -- stereo
    x"7600",  -- clear channel allocations

    -- Audio CTS and N values
    -- See p93 SS4.4.2 of https://www.analog.com/media/en/technical-documentation/user-guides/ADV7511_Programming_Guide.pdf
    -- 27MHz pixel clock, 44.1KHz audio rate using Table 81:
    -- N=6272 ($1880), CTS=30000 ($7530)
    -- Clock is 27.083MHz, so CTS needs to be 30092 ($758C)
    -- (or we increase sample rate to 27.083/27*44100 = 44237 samples / second.)
    -- Big-endian byte order?
    x"0100",x"0218",x"0380",
    x"0700",x"0875",x"0930",
    
--            -- Set HDMI device name
--            x"1F80",x"4478", -- Allow setting HDMI packet memory
--            x"FE70", -- begin talking to device ID 70
--            x"0083",x"0101",x"0219",
--            -- @M.E.G.A. + NUL
--            x"0340",x"044D",x"052E",x"0645",x"072E",x"0847",x"092E",x"0A41",
--            x"0B2E",x"0C00",
--            -- MEGA65 Computer + NUL
--            x"0D4D",x"0E45",x"0F47",x"1041",x"1136",x"1235",x"1320",x"1443",
--            x"156f",x"166d",x"1770",x"1875",x"1974",x"1a65",x"1b72",x"1c00",
--            x"1d00",x"1e00",x"1f00",x"2000",
--            x"FE7A",
    x"1F00",x"4479", -- Hand packet memory back to HDMI controller

    -- Extra space filled with FFFFs to signify end of data
    others => i2c_finished_token
    );

  
begin

  i2c1: entity work.i2c_master
    generic map (
      input_clk => 50_000_000,
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
      if fastio_addr(7 downto 1) /= "1111111" then
        report "reading buffered I2C data";
        fastio_rdata <= bytes(to_integer(fastio_addr(7 downto 0)));
      elsif fastio_addr(7 downto 0) = "11111110" then
        -- Show busy status for writing
        fastio_rdata <= to_unsigned(busy_count,8);
      else
        -- Show busy status for writing
        fastio_rdata <= (others => write_job_pending);
      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if; 

    if rising_edge(clock) then

      -- Notice when HDMI needs to be reset
      if hdmi_int = '0' and last_hdmi_int='1' then
        hdmi_int_latch <= '1';
        hdmi_reset_phase <= 0;
      end if;
      last_hdmi_int <= hdmi_int;
      
      -- Write to registers as required
      if cs='1' and fastio_write='1' then
        -- ADV7511 main map registers
        write_reg <= fastio_addr(7 downto 0);
        write_addr <= x"7A";
        write_job_pending <= '1';
        write_val <= fastio_wdata;
      end if;
      
      i2c1_reset <= '1';

      -- State machine for reading registers from the various
      -- devices.
      last_busy <= i2c1_busy;
      if i2c1_busy='1' and last_busy='0' then

        -- Sequence through the list of transactions endlessly
        if (busy_count < 256) or ((write_job_pending='1' or hdmi_int_latch='1') and busy_count < (256+4)) then
          busy_count <= busy_count + 1;
        else
          busy_count <= 0;
        end if;
      end if;

      if busy_count = 0 then
        i2c1_command_en <= '1';
        i2c1_address <= "0111101"; -- 0x7A/2 = I2C address of device;
        i2c1_wdata <= x"00";
        i2c1_rw <= '0';
      elsif busy_count < 256 then
          -- Read the 255 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 1 then
            bytes(busy_count - 1 - 1 + 0) <= i2c1_rdata;
          end if;
          -- Abort re-reading registers if we have more important work to do
          if write_job_pending='1' or hdmi_int_latch='1' then
            busy_count <= 256;
          end if;
      elsif busy_count = 256 then
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
          last_busy <= '1';
          write_job_pending <= '0';
          if hdmi_int_latch = '0' then
            busy_count <= 0;
          else
            -- HDMI reset in progress, so issue next register write command.
            if reg_value_pairs(hdmi_reset_phase) /= i2c_finished_token and hdmi_reset_phase < 70 then
              write_reg <= reg_value_pairs(hdmi_reset_phase)(15 downto 8);
              write_val <= reg_value_pairs(hdmi_reset_phase)(7 downto 0);
              hdmi_reset_phase <= hdmi_reset_phase + 1;
            else
              hdmi_int_latch <= '0';
            end if;
          end if;
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



