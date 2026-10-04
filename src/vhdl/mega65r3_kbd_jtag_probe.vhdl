library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.VComponents.all;

entity container is
  Port (
    CLK_IN : in std_logic;

    -- Keyboard connector JTAG-like pins, driven as probe outputs.
    kb_tck : out std_logic := '0';
    kb_tdo : in std_logic;
    kb_tms : out std_logic := '0';
    kb_tdi : out std_logic := '0';
    kb_jtagen : out std_logic := '0';

    -- Ethernet PHY LED exposed in the R3 constraints.
    eth_led : out std_logic_vector(1 downto 1) := "0";

    -- General purpose motherboard LED exposed in the R3 constraints.
    led : out std_logic := '0';

    -- TE0725 USB UART status output.
    UART_TXD : out std_logic := '1'
  );
end container;

architecture Behavioral of container is

  constant probe_clock_divider : integer := 5000;
  constant loop_bit_clocks : integer := 200000;
  constant loop_match_threshold : integer := 32;
  constant jtagen_toggle_clocks : integer := 81000000;
  constant uart_status_clocks : integer := 4050000;
  constant done_blink_clocks : integer := 10125000;
  constant debug_led_short_clocks : integer := 4050000;
  constant debug_led_long_clocks : integer := 16200000;
  constant debug_led_pause_clocks : integer := 20250000;
  constant loop_pattern : std_logic_vector(0 to 15) := "1011001010010110";

  signal cpuclock : std_logic;
  signal probe_clock : std_logic := '0';
  signal probe_clock_counter : integer range 0 to probe_clock_divider - 1 := 0;
  signal loop_bit_counter : integer range 0 to loop_bit_clocks - 1 := 0;
  signal loop_bit_index : integer range 0 to 15 := 0;
  signal loop_drive : std_logic := loop_pattern(0);
  signal tdo_meta : std_logic := '0';
  signal tdo_sync : std_logic := '0';
  signal loop_match_count : integer range 0 to loop_match_threshold := 0;
  signal loopback_connected : std_logic := '0';
  signal jtagen_counter : integer range 0 to jtagen_toggle_clocks - 1 := 0;
  signal jtagen_state : std_logic := '1';
  signal uart_status_counter : integer range 0 to uart_status_clocks - 1 := 0;
  signal uart_message_pending : std_logic := '0';
  signal uart_msg_offset : integer range 0 to 3 := 0;
  signal uart_tx_send : std_logic := '0';
  signal uart_tx_ready : std_logic;
  signal uart_tx_data : unsigned(7 downto 0) := x"00";
  signal done_blink_counter : integer range 0 to done_blink_clocks - 1 := 0;
  signal done_blink_phase : std_logic := '0';
  signal fpga_done : std_logic := '0';
  signal debug_led_phase : integer range 0 to 3 := 0;
  signal debug_led_counter : integer range 0 to debug_led_pause_clocks - 1 := 0;
  signal debug_led_drive : std_logic := '0';

begin

  kb_jtagen <= jtagen_state;
  kb_tdi <= loop_drive;
  fpga_done <= debug_led_drive;
  eth_led(1) <= loopback_connected and not done_blink_phase;
  led <= debug_led_drive;

  STARTUPE2_inst: STARTUPE2
    generic map (
      PROG_USR => "FALSE",
      SIM_CCLK_FREQ => 10.0
    )
    port map (
      CLK => '0',
      GSR => '0',
      GTS => '0',
      KEYCLEARB => '0',
      PACK => '0',
      USRCCLKO => '0',
      USRCCLKTS => '1',
      USRDONEO => fpga_done,
      USRDONETS => '0'
    );

  tck_probe: entity work.pin_id
    port map (
      clock => probe_clock,
      pin_number => to_unsigned(1, 8),
      pin => kb_tck
    );

  tms_probe: entity work.pin_id
    port map (
      clock => probe_clock,
      pin_number => to_unsigned(3, 8),
      pin => kb_tms
    );

  uart_tx0: entity work.UART_TX_CTRL
    port map (
      send => uart_tx_send,
      BIT_TMR_MAX => to_unsigned((40500000 / 2000000) - 1, 24),
      clk => cpuclock,
      data => uart_tx_data,
      ready => uart_tx_ready,
      uart_tx => UART_TXD
    );

  process(cpuclock) is
    variable next_bit_index : integer range 0 to 15;
    variable debug_led_limit : integer range 1 to debug_led_pause_clocks;
  begin
    if rising_edge(cpuclock) then
      uart_tx_send <= '0';

      tdo_meta <= kb_tdo;
      tdo_sync <= tdo_meta;

      if probe_clock_counter = probe_clock_divider - 1 then
        probe_clock_counter <= 0;
        probe_clock <= not probe_clock;
      else
        probe_clock_counter <= probe_clock_counter + 1;
      end if;

      if loop_bit_counter = (loop_bit_clocks / 2) then
        if tdo_sync = loop_drive then
          if loop_match_count /= loop_match_threshold then
            loop_match_count <= loop_match_count + 1;
          end if;
        else
          loop_match_count <= 0;
        end if;
      end if;

      if loop_match_count = loop_match_threshold then
        loopback_connected <= '1';
      else
        loopback_connected <= '0';
      end if;

      if loop_bit_counter = loop_bit_clocks - 1 then
        loop_bit_counter <= 0;
        if loop_bit_index = 15 then
          next_bit_index := 0;
        else
          next_bit_index := loop_bit_index + 1;
        end if;
        loop_bit_index <= next_bit_index;
        loop_drive <= loop_pattern(next_bit_index);
      else
        loop_bit_counter <= loop_bit_counter + 1;
      end if;

      if jtagen_counter = jtagen_toggle_clocks - 1 then
        jtagen_counter <= 0;
        jtagen_state <= not jtagen_state;
      else
        jtagen_counter <= jtagen_counter + 1;
      end if;

      if done_blink_counter = done_blink_clocks - 1 then
        done_blink_counter <= 0;
        done_blink_phase <= not done_blink_phase;
      else
        done_blink_counter <= done_blink_counter + 1;
      end if;

      case debug_led_phase is
        when 0 =>
          debug_led_drive <= '1';
          debug_led_limit := debug_led_short_clocks;
        when 1 =>
          debug_led_drive <= '0';
          debug_led_limit := debug_led_short_clocks;
        when 2 =>
          debug_led_drive <= '1';
          if loopback_connected = '1' then
            debug_led_limit := debug_led_short_clocks;
          else
            debug_led_limit := debug_led_long_clocks;
          end if;
        when others =>
          debug_led_drive <= '0';
          debug_led_limit := debug_led_pause_clocks;
      end case;

      if debug_led_counter = debug_led_limit - 1 then
        debug_led_counter <= 0;
        if debug_led_phase = 3 then
          debug_led_phase <= 0;
        else
          debug_led_phase <= debug_led_phase + 1;
        end if;
      else
        debug_led_counter <= debug_led_counter + 1;
      end if;

      if uart_message_pending = '0' then
        if uart_status_counter = uart_status_clocks - 1 then
          uart_status_counter <= 0;
          uart_message_pending <= '1';
          uart_msg_offset <= 0;
        else
          uart_status_counter <= uart_status_counter + 1;
        end if;
      elsif uart_tx_ready = '1' then
        uart_tx_send <= '1';
        case uart_msg_offset is
          when 0 =>
            if loopback_connected = '1' then
              uart_tx_data <= x"59"; -- Y
            else
              uart_tx_data <= x"4e"; -- N
            end if;
            uart_msg_offset <= 1;
          when 1 =>
            if jtagen_state = '1' then
              uart_tx_data <= x"31"; -- 1
            else
              uart_tx_data <= x"30"; -- 0
            end if;
            uart_msg_offset <= 2;
          when 2 =>
            uart_tx_data <= x"0d";
            uart_msg_offset <= 3;
          when others =>
            uart_tx_data <= x"0a";
            uart_message_pending <= '0';
            uart_msg_offset <= 0;
        end case;
      end if;
    end if;
  end process;

  clocks1: entity work.clocking
    port map (
      clk_in => CLK_IN,
      clock27 => open,
      clock41 => cpuclock,
      clock50 => open,
      clock74p22 => open,
      clock81p => open,
      clock163 => open,
      clock163m => open,
      clock200 => open,
      clock270 => open,
      clock325 => open
    );

end Behavioral;
