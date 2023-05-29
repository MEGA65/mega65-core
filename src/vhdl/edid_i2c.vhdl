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
-- EDID lives on device ID 0xa0
--
-- @IO:GS $FFD7100-FF EDID:EDID E-EDID block (MEGA65 R3 and newer, only)

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity edid_i2c is
  generic ( clock_frequency : integer );
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
end edid_i2c;

architecture behavioural of edid_i2c is

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

  signal busy_count : integer range 0 to 299 := 258;
  signal last_busy_count : integer range 0 to 299 := 258;
  signal last_busy : std_logic := '1';
  
  subtype uint8 is unsigned(7 downto 0);
  type byte_array is array (0 to 255) of uint8;
  signal bytes : byte_array := (others => x"00");

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

  signal timeout_counter : integer := 0;
  signal delayed_command : std_logic := '0';
  
  constant i2c_finished_token : unsigned(15 downto 0) := x"FFFF";
  
  type reg_value_pair is ARRAY(0 TO 70) OF unsigned(15 DOWNTO 0);    
  
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
  
  process (clock,cs,fastio_read,fastio_addr,i2c1_busy,last_busy,busy_count,i2c1_error) is
  begin

    if cs='1' and fastio_read='1' then
      fastio_rdata <= (others => '0'); -- This avoids a latch
      if fastio_addr(7 downto 0) = "11111111" then
        -- Show various status flags @ $FF
        fastio_rdata(0) <= '0';
        fastio_rdata(1) <= i2c1_busy;
        fastio_rdata(2) <= last_busy;
        fastio_rdata(3) <= '0';
        fastio_rdata(4) <= '0';
        fastio_rdata(5) <= to_unsigned(busy_count,9)(8);
        fastio_rdata(6) <= i2c1_error;
        fastio_rdata(7) <= '1';
      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if; 

    if rising_edge(clock) then

      if timeout_counter < 1048576 then
        timeout_counter <= timeout_counter + 1;
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
        if (busy_count < 257) then
          report "Increment busy_count from " & integer'image(busy_count) & " to " & integer'image(busy_count +1);
          busy_count <= busy_count + 1;
        else
          report "Reset busy_count to 0 from " & integer'image(busy_count);
          busy_count <= 0;
        end if;
      end if;

      last_busy_count <= busy_count;
      if busy_count = 0 then
        i2c1_command_en <= '1';
        i2c1_address <= "1010000"; -- 0xA0/2 = I2C address of device;
        i2c1_wdata <= x"00"; -- beginning at register 0
        i2c1_rw <= '0';
        timeout_counter <= 0;
      elsif busy_count < 257 then
        -- Read the 255 bytes from the device
        i2c1_rw <= '1';
        i2c1_command_en <= '1';
        if busy_count > 1 then
          bytes(busy_count - 1 - 1 + 0) <= i2c1_rdata;
          if last_busy_count /= busy_count then 
            report "Storing value $" & to_hstring(i2c1_rdata) & " in reg $" & to_hstring(to_unsigned(busy_count - 1 -1 + 0,8));
          end if;
        end if;
        timeout_counter <= 0;
      else
        report "in others (busy_count = " & integer'image(busy_count) & ")";
        -- Make sure we can't get stuck.
        i2c1_command_en <= '0';
        last_busy <= '1';
        busy_count <= 0;
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

    end if;
  end process;
end behavioural;



