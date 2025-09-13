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

    -- I2C bus logger
    scl_log : out unsigned(7 downto 0) := x"00";
    sda_log : out unsigned(7 downto 0) := x"00";
    log_strobe : out std_logic := '0';
    log_reset_strobe : out std_logic := '0';
    
    dipsw_read : out std_logic_vector(7 downto 0);
    board_major : out unsigned(3 downto 0);
    board_minor : out unsigned(3 downto 0)
    );
end mega65r5_board_i2c;

architecture behavioural of mega65r5_board_i2c is

  signal dipsw_int : std_logic_vector(7 downto 0) := (others => '0');
  
  signal i2c1_address : unsigned(6 downto 0) := to_unsigned(0,7);
  signal i2c1_rdata   : unsigned(7 downto 0) := (others => '0');
  signal i2c1_wdata   : unsigned(7 downto 0) := (others => '0');
  signal i2c1_latch_toggle : std_logic;
  signal i2c1_busy    : std_logic := '0';
  signal i2c1_rw      : std_logic := '0';
  signal i2c1_error   : std_logic := '0';
  signal i2c1_reset   : std_logic := '1';
  signal i2c1_command_en : std_logic := '0';

  signal command_en   : std_logic := '0';
  signal command_is_last : std_logic := '0';

  signal latch_count  : integer range 0 to 255 := 150;
  signal last_latch   : std_logic := '1';
  signal wait_for_not_busy : std_logic := '1';

  signal write_job_pending : std_logic := '0';

  signal i2c1_swap    : std_logic := '0';
  signal i2c1_debug_sda : std_logic := '0';
  signal i2c1_debug_scl : std_logic := '0';
  signal debug_status : unsigned(5 downto 0) := "000000";

  signal hold_countdown : integer range 0 to 65535 := 0;
  
begin

  i2c1: entity work.i2c_master
    generic map (
      input_clk => clock_frequency,
      bus_clk   => 400_000
      )
    port map (
      clk         => clock,
      reset_n     => i2c1_reset,
      ena         => i2c1_command_en,
      addr        => std_logic_vector(i2c1_address),
      rw          => i2c1_rw,
      data_wr     => std_logic_vector(i2c1_wdata),
      busy        => i2c1_busy,
      unsigned(data_rd) => i2c1_rdata,
      ack_error   => i2c1_error,
      latch_toggle=> i2c1_latch_toggle,
      sda         => sda,
      scl         => scl,
      swap        => i2c1_swap,
      debug_sda   => i2c1_debug_sda,
      debug_scl   => i2c1_debug_scl,

      scl_log     => scl_log,
      sda_log     => sda_log,
      log_strobe  => log_strobe
      );

  process (clock)
    variable fire : boolean;
  begin
    if rising_edge(clock) then
      -- defaults each cycle
      dipsw_read        <= dipsw_int;
      i2c1_command_en   <= command_en;
      log_reset_strobe  <= '0';  -- one-shot pulse when we kick off a new sequence

      if hold_countdown /= 0 then
        hold_countdown <= hold_countdown - 1;
      else      
        -- Arm/start condition : either idle-then-start, or a byte completed
        fire := ((wait_for_not_busy='1') and (i2c1_busy='0')) or (i2c1_latch_toggle /= last_latch);
        if fire then
          -- edge bookkeeping
          last_latch <= i2c1_latch_toggle;
          wait_for_not_busy <= '0';

          -- step counter
          latch_count <= latch_count + 1;

          command_is_last <= '0';
          if command_is_last='1' then
            command_en <= '0';
            wait_for_not_busy <= '1';
          end if;
          
          case latch_count is

            -- Enable force PWM mode for DCDC converter #1
            when 0 =>
              command_en   <= '1';
              i2c1_address <= "1100001"; -- 0x61
              i2c1_wdata   <= x"01";
              i2c1_rw      <= '0';

            when 1 =>
              command_en   <= '1';
              i2c1_rw      <= '0';
              i2c1_wdata   <= x"A6";
              i2c1_wdata(0) <= not ear_watering_mode;

            -- Enable force PWM mode for DCDC converter #2
            when 2 =>
              command_en   <= '1';
              i2c1_address <= "1100111"; -- 0x67
              i2c1_wdata   <= x"01";
              i2c1_rw      <= '0';

            when 3 =>
              command_en   <= '1';
              i2c1_rw      <= '0';
              i2c1_wdata   <= x"A6";
              i2c1_wdata(0) <= not ear_watering_mode;

            -- Read DIP switches and board revision straps
            when 4 =>
              command_en   <= '1';
              command_is_last <= '1';
              i2c1_address <= "0100000"; -- 0x20
              i2c1_wdata   <= x"00";
              i2c1_rw      <= '0';            

            when 5 =>
              -- STOP after selecting register
              command_en <= '0';
              wait_for_not_busy <= '1';
              hold_countdown <= 300;
              
            when 6 =>
              command_en   <= '1';
              i2c1_rw      <= '1';
              
            when 7 =>
              command_en   <= '1';
              i2c1_address <= "0100000"; -- 0x20
              i2c1_wdata   <= x"00";
              i2c1_rw      <= '1';

            when 8 =>
              command_en   <= '1';
              i2c1_rw      <= '1';
              
            when 9 =>
              command_en   <= '1';
              i2c1_rw      <= '1';
              dipsw_int    <= std_logic_vector(i2c1_rdata);

            when 10 =>
              command_en   <= '1';
              i2c1_rw      <= '1';
              board_minor  <= i2c1_rdata(7 downto 4);
              board_major  <= i2c1_rdata(3 downto 0);

            when others =>
              command_en       <= '0';
              latch_count      <= 0;
              write_job_pending<= '0';
              wait_for_not_busy<= '1';
              latch_count      <= 0;
              log_reset_strobe <= '1';

          end case;
        end if;
      end if;
    end if;
  end process;

end behavioural;
