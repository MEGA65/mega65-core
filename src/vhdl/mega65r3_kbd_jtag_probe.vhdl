library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity container is
  Port (
    CLK_IN : in std_logic;

    -- Keyboard connector JTAG-like pins, driven as probe outputs.
    kb_tck : out std_logic := '0';
    kb_tdo : in std_logic;
    kb_tms : out std_logic := '0';
    kb_tdi : out std_logic := '0';
    kb_jtagen : out std_logic := '0';

    -- Direct mainboard LEDs.
    led_g : out std_logic := '0';
    led_r : out std_logic := '0'
  );
end container;

architecture Behavioral of container is

  constant probe_clock_divider : integer := 5000;
  constant loop_bit_clocks : integer := 200000;
  constant loop_match_threshold : integer := 32;
  constant led_blink_clocks : integer := 10125000;
  constant jtagen_toggle_clocks : integer := 81000000;
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
  signal led_blink_counter : integer range 0 to led_blink_clocks - 1 := 0;
  signal led_phase : std_logic := '0';
  signal jtagen_counter : integer range 0 to jtagen_toggle_clocks - 1 := 0;
  signal jtagen_state : std_logic := '1';

begin

  kb_jtagen <= jtagen_state;
  kb_tdi <= loop_drive;

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

  process(cpuclock) is
    variable next_bit_index : integer range 0 to 15;
  begin
    if rising_edge(cpuclock) then
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

      if led_blink_counter = led_blink_clocks - 1 then
        led_blink_counter <= 0;
        led_phase <= not led_phase;
      else
        led_blink_counter <= led_blink_counter + 1;
      end if;

      if jtagen_counter = jtagen_toggle_clocks - 1 then
        jtagen_counter <= 0;
        jtagen_state <= not jtagen_state;
      else
        jtagen_counter <= jtagen_counter + 1;
      end if;

      if loopback_connected = '1' then
        led_g <= led_phase;
        led_r <= not led_phase;
      else
        led_g <= '0';
        led_r <= '0';
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
