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
  generic ( clock_frequency : integer );
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

  signal busy_count : integer range 0 to 299 := 150;
  signal last_busy_count : integer range 0 to 299 := 150;
  signal last_busy : std_logic := '1';
  
  subtype uint8 is unsigned(7 downto 0);
  type byte_array is array (0 to 255) of uint8;
  signal bytes : byte_array := (others => x"00");

  signal write_job_pending : std_logic := '0';
  -- Dummy write job that doesn't do anything
  signal write_addr : unsigned(7 downto 0) := x"7A";
  signal write_reg : unsigned(7 downto 0) := x"FF";
  signal write_val : unsigned(7 downto 0) := x"42";

  signal last_hdmi_int : std_logic := '1';
  -- Asserted when we have an HDMI interrupt to process (i.e goes high on -ve
  -- edge of hdmi_int)
  signal hdmi_int_latch : std_logic := '0';
  signal hdmi_reset_phase : integer := 0;
  signal hdmi_config_count : unsigned(7 downto 0) := to_unsigned(0,8);
  signal hdmi_int_count : unsigned(7 downto 0) := to_unsigned(0,8);
  signal hdmi_auto_reset : std_logic := '1';
  signal hdmi_int_reset : std_logic := '1';

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

  signal hdmi_reset_compare_byte : unsigned(7 downto 0) := x"00";
  signal hdmi_reset_count : integer := 0;
  signal timeout_counter : integer := 0;
  signal delayed_command : std_logic := '0';
  
  constant i2c_finished_token : unsigned(15 downto 0) := x"FFFF";
  
  type reg_value_pair is ARRAY(0 TO 70) OF unsigned(15 DOWNTO 0);    
  
  signal reg_value_pairs : reg_value_pair := (
    -------------------
    -- Powerup please!
    -------------------
    x"4110", 
    ---------------------------------------
    -- These values must be set as follows
    ---------------------------------------
    x"9803", x"9AE0", x"9C30", x"9D61", x"A2A4", x"A3A4", x"E0D0", x"5512", x"F900",

    -- Clear all pending interrupts, so that the HDMI_INT line can float high again,
    -- and re-trigger an interrupt again later, e.g., if the monitor is
    -- unplugged and re-plugged.
    x"96ff",
    
    ---------------
    -- Input mode
    ---------------
    x"3C11", -- PAL 576p 4:3 aspect ratio video mode
    x"1520", -- Simple RGB video (was $06 = YCbCr 422, DDR, External sync), 44.1KHz audio sample rate
    x"4810", -- Left justified data (D23 downto 8)
    -- according to documenation, style 2 should be x"1637" but it isn't. ARGH!
--            x"1637", -- 444 output, 8 bit style 2, 1st half on rising edge - YCrCb clipping
    x"1630", -- more boring pixel format
    x"1760", -- input aspect ratio 4:3, external DE, negative HSYNC/VSYNC
    x"5619", -- ouput aspect ratio 4:3, 
    x"D03C", -- auto sync data - must be set for DDR modes. No DDR clock delay
    ---------------
    -- Output mode
    ---------------
    x"AF06", -- HDMI mode
    x"4c00", -- Deep colour off, colour depth not indicated (hopefully fixes
             -- the mangled GCP problem) 
    x"4000", -- In fact, don't send GCP packets at all

    ---------------
    -- Audio setup
    ---------------
    
--    x"0A1D",  -- SPDIF audio format, auto CTS
    x"0A10",  -- SPDIF audio format, 128x sample rate, audio sample
              -- packet instead of HBR audio stream packet
    x"0B8E",  -- SPDIF audio TX enable, extract MCLK from SPDIF audio
    -- stream, i.e no separate MCLK
    x"0C00",  -- Use sampling rate encoded in the SPDIF stream instead
    -- of specifying the rate.
    x"1220",  -- Mark audio stream as PCM audio, no copyright
    x"1403",  -- Indicate 20 bits per sample    
    x"7301",  -- stereo
    x"7600",  -- clear channel allocations

    -- Audio CTS and N values
    -- See p93 SS4.4.2 of https://www.analog.com/media/en/technical-documentation/user-guides/ADV7511_Programming_Guide.pdf
    -- 27MHz pixel clock, 48KHz audio rate using Table 81:
    -- N=6144 ($1800), CTS=30000 ($7530)
    -- Clock is 27MHz exactly, so the above values should work fine
    -- Big-endian byte order.
    -- Use $6000 for 192KHz audio sample rate
    -- XXX Except somehow this is all borked up. Our N5998A shows that the
    -- sample rate was ~89KHz instead of 48KHz. Dropping the sample rate in the
    -- SPDIF sender to get 48KHz sample rate reports and average CTS of 50074
    -- instead of 30000.  Something VERY weird is going on here.
    -- (Maybe our SPDIF sender is using short or long frames, as 50074/30000 ~=
    -- 1.5 and 96/64 = 1.5? Anyway, we can try to fix it here).
    x"0100",x"0218",x"0300",  -- N   =  6144
--    x"0700",x"0875",x"0930",  -- CTS = 30000
    x"0700",x"08C3",x"099A",  -- CTS = 50074
    
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

    x"1F00", -- Hand packet memory back to HDMI controller
    x"4479", -- Set up which info frames  are included.  $79 = audio info frame
             -- on, $71 = audio info frame off.

    x"FE00",  -- get I2C register offset for reading back to 0
    
    -- Extra space filled with FFFFs to signify end of data
    others => i2c_finished_token
    );

  
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
      swap => '0',
      debug_sda => '0',
      debug_scl => '0'      
      ); 
  
  process (clock,cs,fastio_read,fastio_addr) is
  begin

    if cs='1' and fastio_read='1' then
      if fastio_addr(7 downto 0) = "11111010" then
        -- Show reset compae byte from reg $41 @ $FA
        fastio_rdata <= hdmi_reset_compare_byte;
      elsif fastio_addr(7 downto 0) = "11111011" then
        -- Show reset_phase @ $FB
        fastio_rdata <= to_unsigned(hdmi_reset_phase,8);
      elsif fastio_addr(7 downto 0) = "11111100" then
        -- Show timeout counter @ $FC
        fastio_rdata <= to_unsigned(hdmi_reset_count,8);
      elsif fastio_addr(7 downto 0) = "11111101" then
        -- Show timeout counter @ $FD
        fastio_rdata <= to_unsigned(timeout_counter,8);
      elsif fastio_addr(7 downto 1) /= "1111111" then
        report "reading buffered I2C data";
        fastio_rdata <= bytes(to_integer(fastio_addr(7 downto 0)));
      elsif fastio_addr(7 downto 0) = "11111110" then
        -- Show number of HDMI interrupts @ $FE
        fastio_rdata <= hdmi_int_count;
      else
        -- Show various status flags @ $FF
        fastio_rdata(0) <= write_job_pending;
        fastio_rdata(1) <= i2c1_busy;
        fastio_rdata(2) <= last_busy;
        fastio_rdata(3) <= hdmi_int_latch;
        fastio_rdata(4) <= hdmi_int;
        fastio_rdata(5) <= to_unsigned(busy_count,9)(8);
        fastio_rdata(6) <= i2c1_error;
        fastio_rdata(7) <= '0';
      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if; 

    if rising_edge(clock) then

      if timeout_counter < 1048576 then
        timeout_counter <= timeout_counter + 1;
      end if;
      
      -- Write to registers as required
      if cs='1' and fastio_write='1' then
        -- ADV7511 main map registers
        if fastio_addr(7 downto 0) = "11111111" then
          -- WRite @ $FF to enable/disable HDMI reset automatically when not
          -- connected to monitor
          hdmi_auto_reset <= fastio_wdata(0);
          hdmi_int_reset <= fastio_wdata(1);
        end if;
        if fastio_addr(7 downto 0) = "00000000" then
          hdmi_int_latch <= '1';
          hdmi_reset_phase <= 0;
        end if;
        write_reg <= fastio_addr(7 downto 0);
        write_addr <= x"7A";
        write_job_pending <= '1';
        write_val <= fastio_wdata;
      end if;
      
      i2c1_reset <= '1';

      -- State machine for reading registers from the various
      -- devices.
      last_busy <= i2c1_busy;
      -- XXX If previous commit doesn't fix it, then try this form to see if it
      -- avoids I2C bus lockup:
      if (i2c1_busy='1' and last_busy='0') then -- or (i2c1_busy='0' and last_busy='0') then

        if (i2c1_busy='1' and last_busy='0') then
          report "I2C is end of busy";
        end if;
        if (i2c1_busy='0' and last_busy='0') then
          report "I2C is idle";
        end if;

        -- Sequence through the list of transactions endlessly
        if (busy_count < 257) or ((write_job_pending='1' or hdmi_int_latch='1') and busy_count < 260) then
          report "Increment busy_count from " & integer'image(busy_count) & " to " & integer'image(busy_count +1);
          busy_count <= busy_count + 1;
        else
          report "Reset busy_count to 0 from " & integer'image(busy_count);
          busy_count <= 0;
          -- Start resetting again if we received an interrupt during reset
          if hdmi_int_latch = '1' and hdmi_int_reset='1' then
            hdmi_reset_phase <= 0;
          end if;
        end if;
      end if;

      last_busy_count <= busy_count;
      if busy_count = 0 then
        i2c1_command_en <= '1';
        i2c1_address <= "0111101"; -- 0x7A/2 = I2C address of device;
        i2c1_wdata <= x"00"; -- beginning at register 0
        i2c1_rw <= '0';
        timeout_counter <= 0;
      elsif busy_count < 257 then
        -- Read the 255 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '1';
        if busy_count > 1 then
          bytes(busy_count - 1 - 1 + 0) <= i2c1_rdata;
          if busy_count = (65 + 1 + 1 ) then
            hdmi_reset_compare_byte <= i2c1_rdata;
            if i2c1_rdata(6) = '1' then
              -- Check for I2C register $41 containing bit 6 ($40) asserted, to
              -- indicate that HDMI TX has shut down
              -- Detect if ADV7511 has shut down, and if so, start it back up again.
              -- (This happens whenever HDMI link is lost)
              if write_job_pending='0' and hdmi_auto_reset='1' then
                hdmi_int_latch <= '1';
                hdmi_reset_phase <= 0;
              end if;
            end if;
          end if;
          if last_busy_count /= busy_count then 
            report "Storing value $" & to_hstring(i2c1_rdata) & " in reg $" & to_hstring(to_unsigned(busy_count - 1 -1 + 0,8));
          end if;
        end if;
        -- Abort re-reading registers if we have more important work to do
        if write_job_pending='1' or hdmi_int_latch='1' then
--          report "Skipping reading due to write job or HDMI interrupt";
--          if busy_count < (257 - 1 ) then
--            busy_count <= 257 - 1;
--          end if;
        end if;
        timeout_counter <= 0;
      elsif busy_count = 257 then
        -- Write to a register, if a request is pending:
        -- First, write the address and register number.
        if write_job_pending='1' then
          i2c1_rw <= '0';
          if last_busy_count /= 257 then
            report "Delaying register write triggered by write_job_pending";
            i2c1_command_en <= '0';
            delayed_command <= '1';
            timeout_counter <= 0;
          end if;
          i2c1_address <= write_addr(7 downto 1);
          i2c1_wdata <= write_reg;
        else
          -- If no real write job, do a dummy write to register $FF, so that we
          -- get the read-phase back to normal
          i2c1_rw <= '0';
          i2c1_command_en <= '1';
          i2c1_address <= write_addr(7 downto 1);
          i2c1_wdata <= x"FF";
          timeout_counter <= 0;
--          report "Doing dummy write to re-sync read register";
        end if;
      elsif busy_count = 258 then
        -- Second, write the actual value into the register
        i2c1_command_en <= '1';
        timeout_counter <= 0;
        i2c1_rw <= '0';
        i2c1_wdata <= write_val;
      elsif busy_count = 259 then
        if last_busy_count /= busy_count then
          report "Doing dummy read";
        end if;
        i2c1_rw <= '1';
        i2c1_command_en <= '1';
        i2c1_address <= (others => '1');
        timeout_counter <= 0;
      else
        report "in others (busy_count = " & integer'image(busy_count) & ")";
        -- Make sure we can't get stuck.
        i2c1_command_en <= '0';
        last_busy <= '1';
        write_job_pending <= '0';
        if hdmi_int_latch = '0' then
          report "Resetting busy_count after register write";
          busy_count <= 0;
        else
          -- HDMI reset in progress, so issue next register write command.
          if hdmi_reset_phase = 1 then
            hdmi_reset_count <= hdmi_reset_count + 1;
          end if;
          if reg_value_pairs(hdmi_reset_phase) /= i2c_finished_token and hdmi_reset_phase < 70 then
            report "Writing $" & to_hstring(reg_value_pairs(hdmi_reset_phase)(7 downto 0))
              & " to reg $" & to_hstring(reg_value_pairs(hdmi_reset_phase)(15 downto 8))
              & " for HDMI init sequence.";
            write_job_pending <= '1';
            write_reg <= reg_value_pairs(hdmi_reset_phase)(15 downto 8);
            write_val <= reg_value_pairs(hdmi_reset_phase)(7 downto 0);
            hdmi_reset_phase <= hdmi_reset_phase + 1;
            busy_count <= 257;
          else
            -- Discard HDMI interrupt latch now that we are done with it.
            report "Finished HDMI reset sequence: Resetting busy_count to 0.";
            hdmi_int_latch <= '0';
            busy_count <= 0;
            hdmi_reset_count <= hdmi_reset_count + 1;
          end if;
        end if;
        timeout_counter <= 0;
      end if;

      if timeout_counter > 1048575 then
        report "timeout counter tripped: Resetting busy_count";
        -- Reset i2c bus, and start over
        i2c1_reset <= '0';
        busy_count <= 0;
        timeout_counter <= 0;
      end if;

      if delayed_command = '1' then
        if timeout_counter = 10000 then
          i2c1_command_en <= '1';
          delayed_command <= '0';
          timeout_counter <= 0;
          report "Starting delayed command";
        end if;
      end if;

      -- Notice when HDMI needs to be reset
      -- Comes last, so that nothing can derail it, e.g., interrupts mid-way
      -- through initialisation.
      if hdmi_int = '0' and last_hdmi_int='1' and hdmi_int_reset='1' then
        hdmi_int_latch <= '1';
        hdmi_reset_phase <= 0;
        hdmi_int_count <= hdmi_int_count + 1;
      end if;
      last_hdmi_int <= hdmi_int;      
      
    end if;
  end process;
end behavioural;



