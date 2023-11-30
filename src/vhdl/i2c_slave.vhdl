--MIT License
--
--Copyright (c) 2014-2016 Peter Samarin
--
--Permission is hereby granted, free of charge, to any person obtaining a copy
--of this software and associated documentation files (the "Software"), to deal
--in the Software without restriction, including without limitation the rights
--to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--copies of the Software, and to permit persons to whom the Software is
--furnished to do so, subject to the following conditions:
--
--The above copyright notice and this permission notice shall be included in all
--copies or substantial portions of the Software.
--
--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--SOFTWARE.

------------------------------------------------------------
-- File      : I2C_slave.vhd
------------------------------------------------------------
-- Author    : Peter Samarin <peter.samarin@gmail.com>
------------------------------------------------------------
-- Copyright (c) 2016 Peter Samarin
------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;

------------------------------------------------------------
entity I2C_slave is
  generic (
    SLAVE_ADDR : std_logic_vector(6 downto 0));
  port (
    scl              : inout std_logic;
    sda              : inout std_logic;
    clk              : in    std_logic;
    rst              : in    std_logic;
    -- User interface
    read_req         : out   std_logic;
    data_to_master   : in    std_logic_vector(7 downto 0);
    data_valid       : out   std_logic;
    data_from_master : out   std_logic_vector(7 downto 0));
end entity I2C_slave;
------------------------------------------------------------
architecture arch of I2C_slave is
  -- this assumes that system's clock is much faster than SCL
  constant DEBOUNCING_WAIT_CYCLES : integer   := 4;
  
  type state_t is (idle, get_address_and_cmd,
                   answer_ack_start, write,
                   read, read_ack_start,
                   read_ack_got_rising, read_stop);
  -- I2C state management
  signal state_reg          : state_t              := idle;
  signal last_state_reg          : state_t              := idle;
  signal cmd_reg            : std_logic            := '0';
  signal bits_processed_reg : integer range 0 to 8 := 0;
  signal continue_reg       : std_logic            := '0';

  signal scl_reg                  : std_logic := '1';
  signal sda_reg                  : std_logic := '1';
  signal scl_debounced            : std_logic := '1';
  signal sda_debounced            : std_logic := '1';
  

  -- Helpers to figure out next state
  signal start_reg       : std_logic := '0';
  signal stop_reg        : std_logic := '0';
  signal scl_rising_reg  : std_logic := '0';
  signal scl_falling_reg : std_logic := '0';

  -- Address and data received from master
  signal addr_reg             : std_logic_vector(6 downto 0) := (others => '0');
  signal data_reg             : std_logic_vector(6 downto 0) := (others => '0');
  signal data_from_master_reg : std_logic_vector(7 downto 0) := (others => '0');

  signal scl_prev_reg : std_logic := '1';
  -- Slave writes on scl
  signal scl_wen_reg  : std_logic := '0';
  signal scl_o_reg    : std_logic := '0';
  signal sda_prev_reg : std_logic := '1';
  -- Slave writes on sda
  signal sda_wen_reg  : std_logic := '0';
  signal sda_o_reg    : std_logic := '0';

  -- User interface
  signal data_valid_reg     : std_logic                    := '0';
  signal read_req_reg       : std_logic                    := '0';
  signal data_to_master_reg : std_logic_vector(7 downto 0) := (others => '0');
begin

  -- debounce SCL and SDA
  SCL_debounce : entity work.debounce
    generic map (
      WAIT_CYCLES => DEBOUNCING_WAIT_CYCLES)
    port map (
      clk        => clk,
      signal_in  => scl_reg,
      signal_out => scl_debounced);

  -- it might not make sense to debounce SDA, since master
  -- and slave can both write to it...
  SDA_debounce : entity work.debounce
    generic map (
      WAIT_CYCLES => DEBOUNCING_WAIT_CYCLES)
    port map (
      clk        => clk,
      signal_in  => sda_reg,
      signal_out => sda_debounced);

  process (clk) is
  begin
    if rising_edge(clk) then
      -- save SCL in registers that are used for debouncing
      scl_reg <= scl;
      sda_reg <= sda;

      -- Delay debounced SCL and SDA by 1 clock cycle
      scl_prev_reg   <= scl_debounced;
      sda_prev_reg   <= sda_debounced;
      -- Detect rising and falling SCL
      scl_rising_reg <= '0';
      if scl_prev_reg = '0' and scl_debounced = '1' then
        scl_rising_reg <= '1';
      end if;
      scl_falling_reg <= '0';
      if scl_prev_reg = '1' and scl_debounced = '0' then
        scl_falling_reg <= '1';
      end if;

      -- Detect I2C START condition
      start_reg <= '0';
      stop_reg  <= '0';
      if scl_debounced = '1' and scl_prev_reg = '1' and
        sda_prev_reg = '1' and sda_debounced = '0' then
        start_reg <= '1';
        stop_reg  <= '0';
        report "START detected";
      end if;

      -- Detect I2C STOP condition
      if scl_prev_reg = '1' and scl_debounced = '1' and
        sda_prev_reg = '0' and sda_debounced = '1' then
        start_reg <= '0';
        stop_reg  <= '1';
        report "STOP detected";
      end if;

    end if;
  end process;

  ----------------------------------------------------------
  -- I2C state machine
  ----------------------------------------------------------
  process (clk) is
  begin
    if rising_edge(clk) then
      -- Default assignments
      sda_o_reg      <= '0';
      sda_wen_reg    <= '0';
      -- User interface
      data_valid_reg <= '0';
      read_req_reg   <= '0';

--      report "scl_debounced=" & std_logic'image(scl_debounced) & ", sda_debounced=" & std_logic'image(sda_debounced);

      last_state_reg <= state_reg;
      if (state_reg /= last_state_reg ) then
        report "state_reg=" & state_t'image(state_reg);
      end if;
      case state_reg is

        when idle =>
          if start_reg = '1' then
            state_reg          <= get_address_and_cmd;
            bits_processed_reg <= 0;
          end if;

        when get_address_and_cmd =>
          if scl_rising_reg = '1' then
            if bits_processed_reg < 7 then
              bits_processed_reg             <= bits_processed_reg + 1;
              addr_reg(6-bits_processed_reg) <= sda_debounced;
            elsif bits_processed_reg = 7 then
              bits_processed_reg <= bits_processed_reg + 1;
              cmd_reg            <= sda_debounced;
            end if;
          end if;

          if bits_processed_reg = 8 and scl_falling_reg = '1' then
            bits_processed_reg <= 0;
            if addr_reg = SLAVE_ADDR then  -- check req address
              report "Detected request for us";
              state_reg <= answer_ack_start;
              if cmd_reg = '1' then  -- issue read request 
                read_req_reg       <= '1';
                data_to_master_reg <= data_to_master;
              end if;
            else
              assert false
                report ("I2C: target/slave address mismatch (data is being sent to another slave).")
                severity note;
              state_reg <= idle;
            end if;
          end if;

        ----------------------------------------------------
        -- I2C acknowledge to master
        ----------------------------------------------------
        when answer_ack_start =>
          sda_wen_reg <= '1';
          sda_o_reg   <= '0';
          if scl_falling_reg = '1' then
            if cmd_reg = '0' then
              state_reg <= write;
            else
              state_reg <= read;
            end if;
          end if;

        ----------------------------------------------------
        -- WRITE
        ----------------------------------------------------
        when write =>
          if scl_rising_reg = '1' then
            bits_processed_reg <= bits_processed_reg + 1;
            if bits_processed_reg < 7 then
              data_reg(6-bits_processed_reg) <= sda_debounced;
            else
              data_from_master_reg <= data_reg & sda_debounced;              
              data_valid_reg       <= '1';
              report "received byte $" & to_hexstring(data_reg & sda_debounced);
            end if;
          end if;

          if scl_falling_reg = '1' and bits_processed_reg = 8 then
            state_reg          <= answer_ack_start;
            bits_processed_reg <= 0;
          end if;

        ----------------------------------------------------
        -- READ: send data to master
        ----------------------------------------------------
        when read =>
          sda_wen_reg <= '1';
          sda_o_reg   <= data_to_master_reg(7-bits_processed_reg);
          if scl_falling_reg = '1' then
            if bits_processed_reg < 7 then
              bits_processed_reg <= bits_processed_reg + 1;
            elsif bits_processed_reg = 7 then
              state_reg          <= read_ack_start;
              bits_processed_reg <= 0;
            end if;
          end if;

        ----------------------------------------------------
        -- I2C read master acknowledge
        ----------------------------------------------------
        when read_ack_start =>
          if scl_rising_reg = '1' then
            state_reg <= read_ack_got_rising;
            if sda_debounced = '1' then  -- nack = stop read
              continue_reg <= '0';
            else  -- ack = continue read
              continue_reg       <= '1';
              read_req_reg       <= '1';  -- request reg byte
              data_to_master_reg <= data_to_master;
            end if;
          end if;

        when read_ack_got_rising =>
          if scl_falling_reg = '1' then
            if continue_reg = '1' then
              if cmd_reg = '0' then
                state_reg <= write;
              else
                state_reg <= read;
              end if;
            else
              state_reg <= read_stop;
            end if;
          end if;

        -- Wait for START or STOP to get out of this state
        when read_stop =>
          null;

        -- Wait for START or STOP to get out of this state
        when others =>
          assert false
            report ("I2C: error: ended in an impossible state.")
            severity error;
          state_reg <= idle;
      end case;

      --------------------------------------------------------
      -- Reset counter and state on start/stop
      --------------------------------------------------------
      if start_reg = '1' then
        state_reg          <= get_address_and_cmd;
        bits_processed_reg <= 0;
      end if;

      if stop_reg = '1' then
        state_reg          <= idle;
        bits_processed_reg <= 0;
      end if;

      if rst = '1' then
        state_reg <= idle;
      end if;
    end if;
  end process;

  ----------------------------------------------------------
  -- I2C interface
  ----------------------------------------------------------
  sda <= sda_o_reg when sda_wen_reg = '1' else
         'Z';
  scl <= scl_o_reg when scl_wen_reg = '1' else
         'Z';
  ----------------------------------------------------------
  -- User interface
  ----------------------------------------------------------
  -- Master writes
  data_valid       <= data_valid_reg;
  data_from_master <= data_from_master_reg;
  -- Master reads
  read_req         <= read_req_reg;
end architecture arch;




                
