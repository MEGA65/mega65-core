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

    -- Buttons etc outputs
    i2c_joya_fire : out std_logic := '1';
    i2c_joya_up : out std_logic := '1';
    i2c_joya_down : out std_logic := '1';
    i2c_joya_left : out std_logic := '1';
    i2c_joya_right : out std_logic := '1';
    i2c_joyb_fire : out std_logic := '1';
    i2c_joyb_up : out std_logic := '1';
    i2c_joyb_down : out std_logic := '1';
    i2c_joyb_left : out std_logic := '1';
    i2c_joyb_right : out std_logic := '1';
    i2c_button2 : out std_logic := '1';
    i2c_button3 : out std_logic := '1';
    i2c_button4 : out std_logic := '1';
    i2c_black2 : out std_logic := '1';
    i2c_black3 : out std_logic := '1';
    i2c_black4 : out std_logic := '1';

    adc1_out : out unsigned(15 downto 0);
    adc2_out : out unsigned(15 downto 0);
    adc3_out : out unsigned(15 downto 0);
    
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
  signal v0 : unsigned(7 downto 0) := to_unsigned(0,8);
  signal v1 : unsigned(7 downto 0) := to_unsigned(0,8);

  signal busy_count : integer range 0 to 255 := 150;
  signal last_busy : std_logic := '1';
  
  subtype uint8 is unsigned(7 downto 0);
  type byte_array is array (0 to 127) of uint8;
  signal bytes : byte_array := (others => x"00");

  signal write_job_pending : std_logic := '1';
  signal write_addr : unsigned(7 downto 0) := x"48";
  signal write_reg : unsigned(7 downto 0) := x"02";
  signal write_val : unsigned(7 downto 0) := x"99";

  signal delayed_en : integer range 0 to 255 := 0;

  -- Used to de-glitch I2C IP expander inputs
  signal black3history : std_logic_vector(15 downto 0) := (others => '1');
  signal black4history : std_logic_vector(15 downto 0) := (others => '1');

  signal adc1_new : unsigned(15 downto 0) := x"8000";
  signal adc2_new : unsigned(15 downto 0) := x"8000";
  signal adc3_new : unsigned(15 downto 0) := x"8000";
  signal adc1_smooth : unsigned(15 downto 0) := x"8000";
  signal adc2_smooth : unsigned(15 downto 0) := x"8000";
  signal adc3_smooth : unsigned(15 downto 0) := x"8000";
  
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
        fastio_rdata <= bytes(to_integer(fastio_addr(6 downto 0)));
      elsif fastio_addr(7 downto 0) = x"f0" then
        -- @IO:GS $FFD70F0 TARGETMEGAPHONER1:ADC1LSB smoothed value (LSB)
        fastio_rdata <= adc1_smooth(7 downto 0);
      elsif fastio_addr(7 downto 0) = x"f1" then
        -- @IO:GS $FFD70F1 TARGETMEGAPHONER1:ADC1MSB smoothed value (MSB)
        fastio_rdata <= adc1_smooth(15 downto 8);
      elsif fastio_addr(7 downto 0) = x"f2" then
        -- @IO:GS $FFD70F2 TARGETMEGAPHONER1:ADC2LSB smoothed value (LSB)
        fastio_rdata <= adc2_smooth(7 downto 0);
      elsif fastio_addr(7 downto 0) = x"f3" then
        -- @IO:GS $FFD70F3 TARGETMEGAPHONER1:ADC2MSB smoothed value (MSB)
        fastio_rdata <= adc2_smooth(15 downto 8);
      elsif fastio_addr(7 downto 0) = x"f4" then
        -- @IO:GS $FFD70F4 TARGETMEGAPHONER1:ADC3LSB smoothed value (LSB)
        fastio_rdata <= adc3_smooth(7 downto 0);
      elsif fastio_addr(7 downto 0) = x"f5" then
        -- @IO:GS $FFD70F5 TARGETMEGAPHONER1:ADC3MSB smoothed value (MSB)
        fastio_rdata <= adc3_smooth(15 downto 8);
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

      -- Export smoothed adc values
      -- (inverted so that limited range results in zero line being max,
      -- and upper limit being near zero, instead of upper limit being
      -- near, but only near, max volume level).
      adc1_out(14 downto 0) <= not adc1_smooth(14 downto 0);
      adc2_out(14 downto 0) <= not adc2_smooth(14 downto 0);
      adc3_out(14 downto 0) <= not adc3_smooth(14 downto 0);
      adc1_out(15) <= '0';
      adc2_out(15) <= '0';
      adc3_out(15) <= '0';
      
      -- Write to registers as required
      if cs='1' and fastio_write='1' then
        case to_integer(fastio_addr(7 downto 0)) is
          when 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 =>
            -- First IO expander is the inputs for buttons etc, so doesn't need
            -- any config changes or writes, so we put it first, so that we
            -- don't have to solve the bug with writing to the first device on
            -- the list/
            write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 0,8);
            write_addr <= x"4C";
            write_job_pending <= '1';
          -- @IO:GS $FFD7000 TARGETMEGAPHONER1:IO1R0 IO Expander 1, Register 0
          -- @IO:GS $FFD7001 TARGETMEGAPHONER1:IO1R1 IO Expander 1, Register 1
          -- @IO:GS $FFD7002 TARGETMEGAPHONER1:IO1R2 IO Expander 1, Register 2
          -- @IO:GS $FFD7003 TARGETMEGAPHONER1:IO1R3 IO Expander 1, Register 3
          -- @IO:GS $FFD7004 TARGETMEGAPHONER1:IO1R4 IO Expander 1, Register 4
          -- @IO:GS $FFD7005 TARGETMEGAPHONER1:IO1R5 IO Expander 1, Register 5
          -- @IO:GS $FFD7006 TARGETMEGAPHONER1:IO1R6 IO Expander 1, Register 6
          -- @IO:GS $FFD7007 TARGETMEGAPHONER1:IO1R7 IO Expander 1, Register 7
          when 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 =>
            write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 8,8);
            write_addr <= x"4A";            
            write_job_pending <= '1';
          when 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 =>
            write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 16,8);
            write_addr <= x"48";
            write_job_pending <= '1';
          -- @IO:GS $FFD7010 TARGETMEGAPHONER1:IO1R0 IO Expander 3, Register 0
          -- @IO:GS $FFD7011 TARGETMEGAPHONER1:IO1R1 IO Expander 3, Register 1
          -- @IO:GS $FFD7012 TARGETMEGAPHONER1:IO1R2 IO Expander 3, Register 2
          -- @IO:GS $FFD7013 TARGETMEGAPHONER1:IO1R3 IO Expander 3, Register 3
          -- @IO:GS $FFD7014 TARGETMEGAPHONER1:IO1R4 IO Expander 3, Register 4
          -- @IO:GS $FFD7015 TARGETMEGAPHONER1:IO1R5 IO Expander 3, Register 5
          -- @IO:GS $FFD7016 TARGETMEGAPHONER1:IO1R6 IO Expander 3, Register 6
          -- @IO:GS $FFD7017 TARGETMEGAPHONER1:IO1R7 IO Expander 3, Register 7
          when 24 | 25 | 26 | 27 | 28 | 29 | 30 | 31 | 32 | 33 | 34 | 35 | 36 | 37 | 38 | 39 | 40 | 41 | 42 =>
            -- RTC
            write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 24,8);
            write_addr <= x"A2";
            write_job_pending <= '1';
          -- @IO:GS $FFD7018 TARGETMEGAPHONER1:RTCR0 Real-Time Clock, Register 0
          -- @IO:GS $FFD7019 TARGETMEGAPHONER1:RTCR1 Real-Time Clock, Register 1
          -- @IO:GS $FFD701A TARGETMEGAPHONER1:RTCR2 Real-Time Clock, Register 2
          -- @IO:GS $FFD701B TARGETMEGAPHONER1:RTCR3 Real-Time Clock, Register 3
          -- @IO:GS $FFD701C TARGETMEGAPHONER1:RTCR4 Real-Time Clock, Register 4
          -- @IO:GS $FFD701D TARGETMEGAPHONER1:RTCR5 Real-Time Clock, Register 5
          -- @IO:GS $FFD701E TARGETMEGAPHONER1:RTCR6 Real-Time Clock, Register 6
          -- @IO:GS $FFD701F TARGETMEGAPHONER1:RTCR7 Real-Time Clock, Register 7
          -- @IO:GS $FFD7020 TARGETMEGAPHONER1:RTCR8 Real-Time Clock, Register 8
          -- @IO:GS $FFD7021 TARGETMEGAPHONER1:RTCR9 Real-Time Clock, Register 9
          -- @IO:GS $FFD7022 TARGETMEGAPHONER1:RTCRA Real-Time Clock, Register A
          -- @IO:GS $FFD7023 TARGETMEGAPHONER1:RTCRB Real-Time Clock, Register B
          -- @IO:GS $FFD7024 TARGETMEGAPHONER1:RTCRC Real-Time Clock, Register C
          -- @IO:GS $FFD7025 TARGETMEGAPHONER1:RTCRD Real-Time Clock, Register D
          -- @IO:GS $FFD7026 TARGETMEGAPHONER1:RTCRE Real-Time Clock, Register E
          -- @IO:GS $FFD7027 TARGETMEGAPHONER1:RTCRF Real-Time Clock, Register F
          -- @IO:GS $FFD7028 TARGETMEGAPHONER1:RTCR10 Real-Time Clock, Register 10
          -- @IO:GS $FFD7029 TARGETMEGAPHONER1:RTCR11 Real-Time Clock, Register 11
          -- @IO:GS $FFD702A TARGETMEGAPHONER1:RTCR12 Real-Time Clock, Register 12
          -- @IO:GS $FFD702B TARGETMEGAPHONER1:RTCR13 Real-Time Clock, Register 13
          -- @IO:GS $FFD702C TARGETMEGAPHONER1:RTCR14 Real-Time Clock, Register 14
          -- @IO:GS $FFD702D TARGETMEGAPHONER1:RTCR15 Real-Time Clock, Register 15
          -- @IO:GS $FFD702E TARGETMEGAPHONER1:RTCR16 Real-Time Clock, Register 16
          -- @IO:GS $FFD702F TARGETMEGAPHONER1:RTCR17 Real-Time Clock, Register 17
          when 48 | 49 | 50 | 51 | 52 | 53 | 54 | 55 | 56 | 57 | 58 | 59 | 60 | 61 | 62 | 63 =>
            -- Amplifier
            write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 48,8);
            write_addr <= x"68";
            write_job_pending <= '1';            
          -- @IO:GS $FFD7030 TARGETMEGAPHONER1:AMPR0 Speaker Amplifier, Register 0
          -- @IO:GS $FFD7031 TARGETMEGAPHONER1:AMPR1 Speaker Amplifier, Register 1
          -- @IO:GS $FFD7032 TARGETMEGAPHONER1:AMPR2 Speaker Amplifier, Register 2
          -- @IO:GS $FFD7033 TARGETMEGAPHONER1:AMPR3 Speaker Amplifier, Register 3
          -- @IO:GS $FFD7034 TARGETMEGAPHONER1:AMPR4 Speaker Amplifier, Register 4
          -- @IO:GS $FFD7035 TARGETMEGAPHONER1:AMPR5 Speaker Amplifier, Register 5
          -- @IO:GS $FFD7036 TARGETMEGAPHONER1:AMPR6 Speaker Amplifier, Register 6
          -- @IO:GS $FFD7037 TARGETMEGAPHONER1:AMPR7 Speaker Amplifier, Register 7
          -- @IO:GS $FFD7038 TARGETMEGAPHONER1:AMPR8 Speaker Amplifier, Register 8
          -- @IO:GS $FFD7039 TARGETMEGAPHONER1:AMPR9 Speaker Amplifier, Register 9
          -- @IO:GS $FFD703A TARGETMEGAPHONER1:AMPRA Speaker Amplifier, Register A
          -- @IO:GS $FFD703B TARGETMEGAPHONER1:AMPRB Speaker Amplifier, Register B
          -- @IO:GS $FFD703C TARGETMEGAPHONER1:AMPRC Speaker Amplifier, Register C
          -- @IO:GS $FFD703D TARGETMEGAPHONER1:AMPRD Speaker Amplifier, Register D
          -- @IO:GS $FFD703E TARGETMEGAPHONER1:AMPRE Speaker Amplifier, Register E
          -- @IO:GS $FFD703F TARGETMEGAPHONER1:AMPRF Speaker Amplifier, Register F
          when 64 | 65 | 66 | 67 | 68 | 69 | 70 | 71 | 72 | 73 | 74 | 75 | 76 | 77 | 78 | 79 | 80 | 81 | 82 | 83 | 84 | 85 | 86 | 87 | 88 | 89 | 90 | 91 | 92 | 93 | 94 | 95 | 96 | 97 | 98 | 99 | 100 | 101 | 102 | 103 | 104 | 105 | 106 | 107 | 108 | 109 | 110 | 111 | 112 | 113 | 114 | 115 | 116 | 117 | 118 | 119 | 120 | 121 | 122 | 123 | 124 | 125 | 126 | 127 =>
            -- Accelerometer
            write_reg <= to_unsigned(to_integer(fastio_addr(7 downto 0)) - 64, 8);
            write_addr <= x"32";
            write_job_pending <= '1';            
          -- @IO:GS $FFD7040 TARGETMEGAPHONER1:ACCELR0 Accelerometer, Register 0
          -- @IO:GS $FFD7041 TARGETMEGAPHONER1:ACCELR1 Accelerometer, Register 1
          -- @IO:GS $FFD7042 TARGETMEGAPHONER1:ACCELR2 Accelerometer, Register 2
          -- @IO:GS $FFD7043 TARGETMEGAPHONER1:ACCELR3 Accelerometer, Register 3
          -- @IO:GS $FFD7044 TARGETMEGAPHONER1:ACCELR4 Accelerometer, Register 4
          -- @IO:GS $FFD7045 TARGETMEGAPHONER1:ACCELR5 Accelerometer, Register 5
          -- @IO:GS $FFD7046 TARGETMEGAPHONER1:ACCELR6 Accelerometer, Register 6
          -- @IO:GS $FFD7047 TARGETMEGAPHONER1:ACCELR7 Accelerometer, Register 7
          -- @IO:GS $FFD7048 TARGETMEGAPHONER1:ACCELR8 Accelerometer, Register 8
          -- @IO:GS $FFD7049 TARGETMEGAPHONER1:ACCELR9 Accelerometer, Register 9
          -- @IO:GS $FFD704A TARGETMEGAPHONER1:ACCELRA Accelerometer, Register A
          -- @IO:GS $FFD704B TARGETMEGAPHONER1:ACCELRB Accelerometer, Register B
          -- @IO:GS $FFD704C TARGETMEGAPHONER1:ACCELRC Accelerometer, Register C
          -- @IO:GS $FFD704D TARGETMEGAPHONER1:ACCELRD Accelerometer, Register D
          -- @IO:GS $FFD704E TARGETMEGAPHONER1:ACCELRE Accelerometer, Register E
          -- @IO:GS $FFD704F TARGETMEGAPHONER1:ACCELRF Accelerometer, Register F
          -- @IO:GS $FFD7050 TARGETMEGAPHONER1:ACCELR10 Accelerometer, Register 10
          -- @IO:GS $FFD7051 TARGETMEGAPHONER1:ACCELR11 Accelerometer, Register 11
          -- @IO:GS $FFD7052 TARGETMEGAPHONER1:ACCELR12 Accelerometer, Register 12
          -- @IO:GS $FFD7053 TARGETMEGAPHONER1:ACCELR13 Accelerometer, Register 13
          -- @IO:GS $FFD7054 TARGETMEGAPHONER1:ACCELR14 Accelerometer, Register 14
          -- @IO:GS $FFD7055 TARGETMEGAPHONER1:ACCELR15 Accelerometer, Register 15
          -- @IO:GS $FFD7056 TARGETMEGAPHONER1:ACCELR16 Accelerometer, Register 16
          -- @IO:GS $FFD7057 TARGETMEGAPHONER1:ACCELR17 Accelerometer, Register 17
          -- @IO:GS $FFD7058 TARGETMEGAPHONER1:ACCELR18 Accelerometer, Register 18
          -- @IO:GS $FFD7059 TARGETMEGAPHONER1:ACCELR19 Accelerometer, Register 19
          -- @IO:GS $FFD705A TARGETMEGAPHONER1:ACCELR1A Accelerometer, Register 1A
          -- @IO:GS $FFD705B TARGETMEGAPHONER1:ACCELR1B Accelerometer, Register 1B
          -- @IO:GS $FFD705C TARGETMEGAPHONER1:ACCELR1C Accelerometer, Register 1C
          -- @IO:GS $FFD705D TARGETMEGAPHONER1:ACCELR1D Accelerometer, Register 1D
          -- @IO:GS $FFD705E TARGETMEGAPHONER1:ACCELR1E Accelerometer, Register 1E
          -- @IO:GS $FFD705F TARGETMEGAPHONER1:ACCELR1F Accelerometer, Register 1F
          -- @IO:GS $FFD7060 TARGETMEGAPHONER1:ACCELR20 Accelerometer, Register 20
          -- @IO:GS $FFD7061 TARGETMEGAPHONER1:ACCELR21 Accelerometer, Register 21
          -- @IO:GS $FFD7062 TARGETMEGAPHONER1:ACCELR22 Accelerometer, Register 22
          -- @IO:GS $FFD7063 TARGETMEGAPHONER1:ACCELR23 Accelerometer, Register 23
          -- @IO:GS $FFD7064 TARGETMEGAPHONER1:ACCELR24 Accelerometer, Register 24
          -- @IO:GS $FFD7065 TARGETMEGAPHONER1:ACCELR25 Accelerometer, Register 25
          -- @IO:GS $FFD7066 TARGETMEGAPHONER1:ACCELR26 Accelerometer, Register 26
          -- @IO:GS $FFD7067 TARGETMEGAPHONER1:ACCELR27 Accelerometer, Register 27
          -- @IO:GS $FFD7068 TARGETMEGAPHONER1:ACCELR28 Accelerometer, Register 28
          -- @IO:GS $FFD7069 TARGETMEGAPHONER1:ACCELR29 Accelerometer, Register 29
          -- @IO:GS $FFD706A TARGETMEGAPHONER1:ACCELR2A Accelerometer, Register 2A
          -- @IO:GS $FFD706B TARGETMEGAPHONER1:ACCELR2B Accelerometer, Register 2B
          -- @IO:GS $FFD706C TARGETMEGAPHONER1:ACCELR2C Accelerometer, Register 2C
          -- @IO:GS $FFD706D TARGETMEGAPHONER1:ACCELR2D Accelerometer, Register 2D
          -- @IO:GS $FFD706E TARGETMEGAPHONER1:ACCELR2E Accelerometer, Register 2E
          -- @IO:GS $FFD706F TARGETMEGAPHONER1:ACCELR2F Accelerometer, Register 2F
          -- @IO:GS $FFD7070 TARGETMEGAPHONER1:ACCELR30 Accelerometer, Register 30
          -- @IO:GS $FFD7071 TARGETMEGAPHONER1:ACCELR31 Accelerometer, Register 31
          -- @IO:GS $FFD7072 TARGETMEGAPHONER1:ACCELR32 Accelerometer, Register 32
          -- @IO:GS $FFD7073 TARGETMEGAPHONER1:ACCELR33 Accelerometer, Register 33
          -- @IO:GS $FFD7074 TARGETMEGAPHONER1:ACCELR34 Accelerometer, Register 34
          -- @IO:GS $FFD7075 TARGETMEGAPHONER1:ACCELR35 Accelerometer, Register 35
          -- @IO:GS $FFD7076 TARGETMEGAPHONER1:ACCELR36 Accelerometer, Register 36
          -- @IO:GS $FFD7077 TARGETMEGAPHONER1:ACCELR37 Accelerometer, Register 37
          -- @IO:GS $FFD7078 TARGETMEGAPHONER1:ACCELR38 Accelerometer, Register 38
          -- @IO:GS $FFD7079 TARGETMEGAPHONER1:ACCELR39 Accelerometer, Register 39
          -- @IO:GS $FFD707A TARGETMEGAPHONER1:ACCELR3A Accelerometer, Register 3A
          -- @IO:GS $FFD707B TARGETMEGAPHONER1:ACCELR3B Accelerometer, Register 3B
          -- @IO:GS $FFD707C TARGETMEGAPHONER1:ACCELR3C Accelerometer, Register 3C
          -- @IO:GS $FFD707D TARGETMEGAPHONER1:ACCELR3D Accelerometer, Register 3D
          -- @IO:GS $FFD707E TARGETMEGAPHONER1:ACCELR3E Accelerometer, Register 3E
          -- @IO:GS $FFD707F TARGETMEGAPHONER1:ACCELR3F Accelerometer, Register 3F
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
        if (busy_count < 153) or (write_job_pending='1' and busy_count < (153+4)) then
          busy_count <= busy_count + 1;
        else
          busy_count <= 0;
        end if;
      end if;

      case busy_count is
        -- The body for this case statement can be automatically generated
        -- using src/tools/i2cstatemapper.c

        --------------------------------------------------------------------
        -- Start of Auto-Generated Content
        --------------------------------------------------------------------        
        when 0 =>
          i2c1_command_en <= '1';
          i2c1_address <= "0100110"; -- 0x4C/2 = I2C address of device;
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
        when 1 | 2 | 3 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          if delayed_en = 0 then
            report "IO Expander #0 regs 0-1";
            i2c1_command_en <= '0';
            delayed_en <= 250;
          end if;
          if busy_count > 1 and i2c1_error='0' then
            bytes(busy_count - 1 - 1 + 0) <= i2c1_rdata;
          end if;
          -- If power is off to various peripherals, then the joypad etc can end
          -- up being read as all zeroes.  In that case, we want to ignore it.
          -- Also, in general, we see situations where the joypad lines and button2 all go low
          -- for no apparent reason, and the upper two lines take any of the four
          -- possible values.  These situations should also be rejected.
          -- This should actually remove the need to otherwise de-glitch these lines,
          -- thus helpfully reducing their latency.
          if busy_count = 2 then
            if i2c1_error='0' then
              v0 <= i2c1_rdata;
            else
              v0 <= x"FF";
            end if;
          end if;
          if busy_count = 3 then
            if i2c1_error='0' then
              v1 <= i2c1_rdata;
            else
              v1 <= x"FF";
            end if;
          end if;
        when 4 =>          
          i2c1_command_en <= '1';
          i2c1_address <= "0100110"; -- 0x4C/2 = I2C address of device;
          i2c1_wdata <= x"02";
          i2c1_rw <= '0';
          
          -- There are weird problems with reading the I2C bus
          -- Basically we sometimes read the wrong register, or the wrong value
          -- on the I2C IO expanders.  For now the solution is just to use some
          -- known properties of the lines we have connected, to try to filter
          -- out the weirdnesses.

          -- This filter is to stop values of $00,$40,$80 and $C0 being
          -- interpretted as real values. We have no idea why they happen.
          if v0(5 downto 0) /= "000000" then
            i2c_joya_up <= v0(0);
            i2c_joya_left <= v0(1);
            i2c_joya_right <= v0(2);
            i2c_joya_down <= v0(3);
            i2c_joya_fire <= v0(4);
            i2c_button2 <= v0(5);
            i2c_button3 <= v0(6);
            i2c_button4 <= v0(7);
          end if;

          -- Then for the 2nd set of lines, we make sure we dont have $FF
          -- or the value of the other port showing up by mistake
          if v1(7)='0' then
            black3history(15 downto 1) <= black3history(14 downto 0);
            black3history(0) <= v1(0);
            if black3history = "1111111111111111" then
              i2c_black3 <= '1';
            end if;
            if black3history = "0000000000000000" then
              i2c_black3 <= '0';
            end if;

            black4history(15 downto 1) <= black4history(14 downto 0);
            black4history(0) <= v1(1);
            if black4history = "1111111111111111" then
              i2c_black4 <= '1';
            end if;
            if black4history = "0000000000000000" then
              i2c_black4 <= '0';
            end if;
            
            -- Black button 2 combined with interrupt
            -- input that also wakes the FPGA up.
            -- (so needs no de-bouncing)
            i2c_black2 <= v1(2);
            -- XXX joyb is on the other pins, but
            -- the port currently lacks pull-ups, so all lines
            -- are currently active.  Uncomment below when fixed.
            -- XXX also ensure correct line asignments.
            if v1(7 downto 3) /= "00000" then
              -- Only set joy port inputs if they are not all low.
              -- This should only be able to happen if the joyport is NOT
              -- powered, or otherwise only very rarely when an Amiga mouse is
              -- plugged in and the left-button pressed.
              -- (We can solve this problem by later having the joy port powered
              -- on its own rail, if joy input is required while microphone power
              -- rail is off).
              i2c_joyb_up <= v1(3);
              i2c_joyb_left <= v1(4);
              i2c_joyb_right <= v1(5);
              i2c_joyb_down <= v1(6);
              i2c_joyb_fire <= v1(7);
            else
              -- Float joystick inputs if the joy port is not currently powered
              i2c_joyb_up <= '1';
              i2c_joyb_left <= '1';
              i2c_joyb_right <= '1';
              i2c_joyb_down <= '1';
              i2c_joyb_fire <= '1';
            end if;
          end if;
          
        when 5 | 6 | 7 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          if delayed_en = 0 then
            report "IO Expander #0 regs 2-3";
            i2c1_command_en <= '0';
            delayed_en <= 250;
          end if;
          if busy_count > 5 and i2c1_error='0' then
            bytes(busy_count - 1 - 5 + 2) <= i2c1_rdata;
          end if;
          report "IO Expander #0 regs 4-5";
        when 8 =>
          i2c1_command_en <= '1';
          i2c1_address <= "0100110"; -- 0x4C/2 = I2C address of device;
          i2c1_wdata <= x"04";
          i2c1_rw <= '0';
        when 9 | 10 | 11 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          if delayed_en = 0 then
            i2c1_command_en <= '0';
            delayed_en <= 250;
          end if;
          if busy_count > 9 and i2c1_error='0' then
            bytes(busy_count - 1 - 9 + 4) <= i2c1_rdata;
          end if;
          report "IO Expander #0 regs 6-7";
        when 12 =>
          i2c1_command_en <= '1';
          i2c1_address <= "0100110"; -- 0x4C/2 = I2C address of device;
          i2c1_wdata <= x"06";
          i2c1_rw <= '0';
        when 13 | 14 | 15 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          if delayed_en = 0 then
            i2c1_command_en <= '0';
            delayed_en <= 250;
          end if;
          if busy_count > 13 and i2c1_error='0' then
            bytes(busy_count - 1 - 13 + 6) <= i2c1_rdata;
          end if;
          report "IO Expander #1 regs 0-1";
        when 16 =>
          i2c1_command_en <= '1';
          i2c1_address <= "0100101"; -- 0x4A/2 = I2C address of device;
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
        when 17 | 18 | 19 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          if delayed_en = 0 then
            i2c1_command_en <= '0';
            delayed_en <= 250;
          end if;
          if busy_count > 17 and i2c1_error='0' then
            bytes(busy_count - 1 - 17 + 8) <= i2c1_rdata;
          end if;
          report "IO Expander #1 regs 2-3";
        when 20 =>
          i2c1_command_en <= '1';
          i2c1_address <= "0100101"; -- 0x4A/2 = I2C address of device;
          i2c1_wdata <= x"02";
          i2c1_rw <= '0';
        when 21 | 22 | 23 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          if delayed_en = 0 then
            i2c1_command_en <= '0';
            delayed_en <= 250;
          end if;
          if busy_count > 21 and i2c1_error='0' then
            bytes(busy_count - 1 - 21 + 10) <= i2c1_rdata;
          end if;
          report "IO Expander #1 regs 4-5";
        when 24 =>
          i2c1_command_en <= '1';
          i2c1_address <= "0100101"; -- 0x4A/2 = I2C address of device;
          i2c1_wdata <= x"04";
          i2c1_rw <= '0';
        when 25 | 26 | 27 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          if delayed_en = 0 then
            i2c1_command_en <= '0';
            delayed_en <= 250;
          end if;
          if busy_count > 25 and i2c1_error='0' then
            bytes(busy_count - 1 - 25 + 12) <= i2c1_rdata;
          end if;
          report "IO Expander #1 regs 6-7";
        when 28 =>
          if delayed_en = 0 then
            i2c1_command_en <= '0';
            delayed_en <= 250;
          end if;
          i2c1_address <= "0100101"; -- 0x4A/2 = I2C address of device;
          i2c1_wdata <= x"06";
          i2c1_rw <= '0';
        when 29 | 30 | 31 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 29 and i2c1_error='0' then
            bytes(busy_count - 1 - 29 + 14) <= i2c1_rdata;
          end if;
          report "IO Expander #2 regs 0-1";
        when 32 =>
          if delayed_en = 0 then
            i2c1_command_en <= '0';
            delayed_en <= 250;
          end if;
          i2c1_address <= "0100100"; -- 0x48/2 = I2C address of device;
          i2c1_wdata <= x"00";
          i2c1_rw <= '0';
        when 33 | 34 | 35 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 33 and i2c1_error='0' then
            bytes(busy_count - 1 - 33 + 16) <= i2c1_rdata;
          end if;
          report "IO Expander #2 regs 2-3";
        when 36 =>
          if delayed_en = 0 then
            i2c1_command_en <= '0';
            delayed_en <= 250;
          end if;
          i2c1_address <= "0100100"; -- 0x48/2 = I2C address of device;
          i2c1_wdata <= x"02";
          i2c1_rw <= '0';
        when 37 | 38 | 39 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 37 and i2c1_error='0' then
            bytes(busy_count - 1 - 37 + 18) <= i2c1_rdata;
          end if;
          report "IO Expander #2 regs 4-5";
        when 40 =>
          if delayed_en = 0 then
            i2c1_command_en <= '0';
            delayed_en <= 250;
          end if;
          i2c1_address <= "0100100"; -- 0x48/2 = I2C address of device;
          i2c1_wdata <= x"04";
          i2c1_rw <= '0';
        when 41 | 42 | 43 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 41 and i2c1_error='0' then
            bytes(busy_count - 1 - 41 + 20) <= i2c1_rdata;
          end if;
          report "IO Expander #2 regs 6-7";
        when 44 =>
          if delayed_en = 0 then
            i2c1_command_en <= '0';
            delayed_en <= 250;
          end if;
          i2c1_address <= "0100100"; -- 0x48/2 = I2C address of device;
          i2c1_wdata <= x"06";
          i2c1_rw <= '0';
        when 45 | 46 | 47 =>
          -- Read the 2 bytes from the device
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          if busy_count > 45 and i2c1_error='0' then
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
          if busy_count > 49 and i2c1_error='0' then
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
          if busy_count > 70 and i2c1_error='0' then
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
          if busy_count > 88 and i2c1_error='0' then
            bytes(busy_count - 1 - 88 + 64) <= i2c1_rdata;
            if busy_count = 97 then
              adc1_new(7 downto 0) <= i2c1_rdata;
            end if;
            if busy_count = 98 then
              adc1_new(15 downto 8) <= i2c1_rdata;
            end if;
            if busy_count = 99 then
              adc2_new(7 downto 0) <= i2c1_rdata;
            end if;
            if busy_count = 100 then
              adc2_new(15 downto 8) <= i2c1_rdata;
            end if;
            if busy_count = 101 then
              adc3_new(7 downto 0) <= i2c1_rdata;
            end if;
            if busy_count = 102 then
              adc3_new(15 downto 8) <= i2c1_rdata;
            end if;
            -- Make sure ADC values are between $0000 - $7FFF
            if busy_count = 103 then
              -- Fix sign of ADC values
              adc1_new(15) <= not adc1_new(15);
              adc2_new(15) <= not adc2_new(15);
              adc3_new(15) <= not adc3_new(15);
            end if;
            if busy_count = 104 then
              if adc1_new(15)='1' then
                adc1_new <= x"7FFF";
              end if;
              if adc2_new(15)='1' then
                adc2_new <= x"7FFF";
              end if;
              if adc3_new(15)='1' then
                adc3_new <= x"7FFF";
              end if;
            end if;
            if busy_count = 105 then
              if adc1_new > adc1_smooth then
                if (adc1_new - adc1_smooth) > 64 then
                  adc1_smooth <= adc1_smooth + 64;
                else
                  adc1_smooth <= adc1_smooth + 1;
                end if;
              elsif adc1_new < adc1_smooth then
                if (adc1_smooth - adc1_new) > 64 then
                  adc1_smooth <= adc1_smooth - 64;
                else
                  adc1_smooth <= adc1_smooth - 1;
                end if;
              end if;
              if adc2_new > adc2_smooth then
                if (adc2_new - adc2_smooth) > 64 then
                  adc2_smooth <= adc2_smooth + 64;
                else
                  adc2_smooth <= adc2_smooth + 1;
                end if;
              elsif adc2_new < adc2_smooth then
                if (adc2_smooth - adc2_new) > 64 then
                  adc2_smooth <= adc2_smooth - 64;
                else
                  adc2_smooth <= adc2_smooth - 1;
                end if;
              end if;
              if adc3_new > adc3_smooth then
                if (adc3_new - adc3_smooth) > 64 then
                  adc3_smooth <= adc3_smooth + 64;
                else
                  adc3_smooth <= adc3_smooth + 1;
                end if;
              elsif adc3_new < adc3_smooth then
                if (adc3_smooth - adc3_new) > 64 then
                  adc3_smooth <= adc3_smooth - 64;
                else
                  adc3_smooth <= adc3_smooth - 1;
                end if;
              end if;
            end if;
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
        when 155 =>
          -- Do dummy read of some nonsence, so that the write above doesn't
          -- get carried over into the access of the first IO expander
          -- (which it was, and was naturally causing problems as a result).
          report "Doing dummy read";
          i2c1_rw <= '1';
          i2c1_command_en <= '1';
          i2c1_address <= (others => '1');
        when others =>
          report "in others";
          -- Make sure we can't get stuck.
          i2c1_command_en <= '0';
          busy_count <= 0;
          last_busy <= '1';
          write_job_pending <= '0';
      end case;

      -- XXX Annoying problem with the IO expanders is that to select
      -- a register for reading, you have to send a STOP before trying to
      -- read from the new address.  The problem is that our state-machine
      -- here requires back-to-back commands.  Solution is to add a delayed
      -- command_en line, that gets checked and copied to i2c1_command_en
      -- when busy is low.

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



