--------------------------------------------------------------------------
-- Simple I2C controller that supports re-start and other things
-- that we rely on for the MEGA65 I2C device wrappers.
--
--------------------------------------------------------------------------

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity i2c_controller is
  generic ( clock_frequency : integer := 40_500_000;
            bus_clk : integer := 400_000);
  port (
    clock : in std_logic;
    
    -- I2C bus
    sda : inout std_logic := '1';
    scl : inout std_logic := '1';

    rw : in std_logic;
    addr : in unsigned(7 downto 1);
    reg_addr : in unsigned(7 downto 0);
    data_wr : in unsigned(7 downto 0);

    data_rd : out unsigned(7 downto 0) := x"00";
    rd_addr : out unsigned(7 downto 0) := x"00";
    rd_strobe : out std_logic := '0';
    rd_count : in unsigned(15 downto 0);

    req : in std_logic;
    busy : out std_logic := '1'
    
    );
end i2c_controller;

architecture hopeful of i2c_controller is

  signal a_signal : std_logic := '0';

  constant clocks_per_quarter_tick : integer := clock_frequency / (bus_clk * 4);
  signal tick_countdown : integer := 0;
  signal tick_strobe : std_logic := '0';

  signal i2c_bits : integer := (9*4);
  signal i2c_byte : unsigned(7 downto 0) := x"00";
  signal i2c_ack_bit : std_logic := '0';
  signal i2c_byte_in : unsigned(7 downto 0) := x"00";
  signal i2c_byte_direction : std_logic := '0'; -- 1 = output

  signal i2c_rw : std_logic;
  signal i2c_addr : unsigned(7 downto 1);
  signal i2c_reg : unsigned(7 downto 0);
  signal i2c_wdata : unsigned(7 downto 0);
  signal i2c_read_count : integer := 0;
  signal rd_addr_next : unsigned(7 downto 0) := x"00";

  type state_t is (Idle,
                   Start,
                   WriteSendRegNum,
                   WriteSendData,
                   Stop,
                   Stop2,
                   Stop3,
                   Stop4,
                   Stop5,
                   SwitchToRead,
                   SwitchToRead2,
                   SwitchToRead3,
                   SwitchToRead4,
                   ReadLoop
                   );
  signal state : state_t := Idle;
  
begin

  process(clock) is
    variable clock_phase : unsigned(1 downto 0);
  begin
    if rising_edge(clock) then

      rd_strobe <= '0';
      
      if tick_countdown /= 0 then
        tick_countdown <= tick_countdown - 1;
        tick_strobe <= '0';
      else
        tick_countdown <= clocks_per_quarter_tick;
        tick_strobe <= '1';
      end if;
      
      if tick_strobe='1' then
        if i2c_bits < (9*4) then
          -- If we are sending or receiving an I2C byte
          i2c_bits <= i2c_bits + 1;
          clock_phase := to_unsigned(i2c_bits,2);
          case clock_phase is
            when "00" =>
              if i2c_byte_direction='1' then
                -- Write
                if i2c_bits < (8*4) then
                  if i2c_byte(7)='1' then
                    sda <= 'Z';
                  else
                    sda <= '0';
                  end if;
                else
                  sda <= 'Z';
                end if;
                i2c_byte(7 downto 1) <= i2c_byte(6 downto 0);
                i2c_byte(0) <= '0';
              else
                -- Read
                if i2c_bits < (8*4) or (i2c_read_count = 0) then
                  sda <= 'Z';
                else
                  -- Start sending ACK of read
                  sda <= '0';
                end if;
              end if;
            when "01" =>   scl <= 'Z';
            when "10" =>
              -- Allow clock stretching: check if SCL stays low after we have
              -- released it
              if scl = '0' then
                i2c_bits <= i2c_bits;
              end if;
            when "11" =>
              scl <= '0';
              if i2c_byte_direction='0' then
                if i2c_bits < (8*4) then
                  i2c_byte(0) <= sda;
                  i2c_byte(7 downto 1) <= i2c_byte(6 downto 0);
                else
                  i2c_ack_bit <= sda;
                  rd_strobe <= '1';
                  data_rd <= i2c_byte;
                  rd_addr <= rd_addr_next;
                  rd_addr_next <= rd_addr_next + 1;
                end if;
              end if;
            when others => null;
          end case;          
        else
          -- Not sending or receiving an I2C byte, so work out what to do next
          case state is
            when Idle =>
              if req='1' then 
                busy <= '1';
                -- Latch job details
                i2c_addr <= addr;
                i2c_rw <= rw;
                i2c_reg <= reg_addr;
                i2c_wdata <= data_wr;
                rd_addr_next <= x"00";
                i2c_read_count <= to_integer(rd_count);
                state <= Start;
                sda <= '0';
                scl <= 'Z';
              end if;
            when Start =>
              scl <= '0';
              -- Start sending device address
              i2c_bits <= 0;
              i2c_byte_direction <= '1';
              i2c_byte(7 downto 1) <= i2c_addr;
              i2c_byte(0) <= '0';
              state <= WriteSendRegNum;
            when WriteSendRegNum =>
              i2c_byte <= i2c_reg;
              i2c_bits <= 0;
              if i2c_rw = '0' then
                state <= WriteSendData;
              else
                state <= SwitchToRead;
              end if;
            when WriteSendData =>
              i2c_byte <= i2c_wdata;
              i2c_bits <= 0;
              state <= Stop;
            when Stop =>
              report "STOP initiated";
              scl <= '0';
              sda <= '0';
              state <= Stop2;
            when Stop2 =>
              report "STOP2";
              scl <= 'Z';
              state <= Stop3;
            when Stop3 =>
              report "STOP3";
              sda <= 'Z';
              state <= Stop4;
            when Stop4 =>
              report "STOP4";
              state <= Stop5;
            when Stop5 =>
              report "STOP5";
              busy <= '0';
              state <= Idle;
            when SwitchToRead =>
              -- Begin restart
              scl <= 'Z';
              state <= SwitchToRead2;
            when SwitchToRead2 =>
              sda <= 'Z';
              state <= SwitchToRead3;
            when SwitchToRead3 =>
              sda <= '0';
              state <= SwitchToRead4;
            when SwitchToRead4 =>
              scl <= '0';
              -- Re-start has been issued, so now
              -- we send the address with R/W bit set to read
              i2c_bits <= 0;
              i2c_byte_direction <= '1';
              i2c_byte(7 downto 1) <= i2c_addr;
              i2c_byte(0) <= '1';
              state <= ReadLoop;
            when ReadLoop =>
              i2c_bits <= 0;
              i2c_byte_direction <= '0';
              if i2c_read_count > 0 then
                i2c_read_count <= i2c_read_count - 1;
                state <= ReadLoop;
              else
                report "stopping read";
                state <= Stop;
              end if;
          end case;
        end if;
      end if;
    end if;
  end process;
end hopeful;

