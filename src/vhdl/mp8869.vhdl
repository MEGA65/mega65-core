-- Paul Gardner-Stephen 2023, forked from:
-- Copyright (c) 2006 Frank Buss (fb@frank-buss.de)
-- See license.txt for license
--
-- Simulated MP8869 DCDC converter to support testing
-- of setting PWM mode
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
entity mp8869 is
  generic(
    clock_frequency: natural := 1e7;
    address: unsigned(6 downto 0) := b"0000000");
  port(
    clock: in std_logic;
    reset: in std_logic;
    scl: in std_logic;
    sda: inout std_logic;
    ear_watering_mode: out std_logic);
end entity mp8869;
architecture rtl of mp8869 is
  component i2c_slave is
    generic(
      clock_frequency: natural;
      address: unsigned(6 downto 0));
    port(
      clock: in std_logic;
      reset: in std_logic;
      data_out: in unsigned(7 downto 0);
      data_in: out unsigned(7 downto 0);
      read_mode: out boolean;
      start_detected: out boolean;
      stop_detected: out boolean;
      transfer_started: out boolean;
      data_out_requested: out boolean;
      data_in_valid: out boolean;
      sda: inout std_logic;
      scl: in std_logic);
  end component i2c_slave;
  -- I2C slave signals
  signal data_out: unsigned(7 downto 0);
  signal data_in: unsigned(7 downto 0);
  signal stop_detected: boolean;
  signal transfer_started: boolean;
  signal data_out_requested: boolean;
  signal data_in_valid: boolean;
  signal read_mode : boolean;  
  
  -- MP8869 signals
  type registers_type is array (0 to 7) of unsigned(7 downto 0);
  signal registers: registers_type := (others => x"00");
  signal selected_register_index: unsigned(2 downto 0);
  type state_type is (
    idle,
    wait_for_command,
    wait_for_read_write,
    wait_for_event_released);
  signal state: state_type := idle;
begin
  i2c_slave_instance: i2c_slave
    generic map(
      clock_frequency => clock_frequency,
      address => address)
    port map(
      clock => clock,
      reset => reset,
      data_out => data_out,
      data_in => data_in,
      read_mode => read_mode,                             -- this port signal was open.
      start_detected => open,
      stop_detected => stop_detected,
      transfer_started => transfer_started,
      data_out_requested => data_out_requested,
      data_in_valid => data_in_valid,
      sda => sda,
      scl => scl);
  test_process: process(clock, reset)
  begin
    ear_watering_mode <= not registers(1)(0);
    
    if reset = '1' then
      -- See page 26 of the datasheet
      registers(0) <= x"1e"; -- VSEL
      registers(1) <= x"a6"; -- SysCntlReg1 (bit 0 of this is the one we care about)
      registers(2) <= x"c1"; -- SysCntlReg2
      registers(3) <= x"00"; -- Output current
      registers(4) <= x"00"; -- Output voltage
      registers(5) <= x"80"; -- ID1
      registers(6) <= x"01"; -- Status (bit0 = power good)
      registers(7) <= x"ff"; -- DOES NOT EXIST IN REAL PART
      state <= idle;
    else
      if rising_edge(clock) then
        -- I2C send/receive
        case state is
          when idle =>
            if transfer_started then
  ----------------------------------------------------------------------------------
    -- I am trying to implement the Stop bit between the Command Byte and (repeated)
    ----                        START condition 
    ----------------------------------------------------------------------------------  
                if read_mode and data_out_requested then
                  state <= wait_for_read_write;
  ----------------------------------------------------------------------------------
  ----------------------------------------------------------------------------------
                else
                  state <= wait_for_command;
              end if;
            end if;
          when wait_for_command =>
            if data_in_valid then
              selected_register_index <= data_in(2 downto 0) xor b"001";
              state <= wait_for_event_released;
            end if;
          when wait_for_read_write =>
            if data_in_valid then
              registers(to_integer(selected_register_index)) <= data_in;
              state <= wait_for_event_released;
            end if;
            if data_out_requested then
              data_out <= registers(to_integer(selected_register_index));
              state <= wait_for_event_released;
            end if;
          when wait_for_event_released =>
            if (data_in_valid = false) and (data_out_requested = false) then
              selected_register_index(0) <= not selected_register_index(0);
              state <= wait_for_read_write;
            end if;
        end case;
        if stop_detected then
          state <= idle;
        end if;

      end if;
    end if;
  end process;
end architecture rtl;
