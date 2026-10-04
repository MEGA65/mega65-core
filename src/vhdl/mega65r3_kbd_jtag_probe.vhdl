library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity container is
  Port (
    CLK_IN : in std_logic;

    -- Keyboard connector JTAG-like pins, driven as probe outputs.
    kb_tck : out std_logic := '0';
    kb_tdo : out std_logic := '0';
    kb_tms : out std_logic := '0';
    kb_tdi : out std_logic := '0';
    kb_jtagen : out std_logic := '0'
  );
end container;

architecture Behavioral of container is

  constant probe_clock_divider : integer := 5000;
  signal cpuclock : std_logic;
  signal probe_clock : std_logic := '0';
  signal probe_clock_counter : integer range 0 to probe_clock_divider - 1 := 0;

begin

  kb_jtagen <= '1';

  tck_probe: entity work.pin_id
    port map (
      clock => probe_clock,
      pin_number => to_unsigned(1, 8),
      pin => kb_tck
    );

  tdo_probe: entity work.pin_id
    port map (
      clock => probe_clock,
      pin_number => to_unsigned(2, 8),
      pin => kb_tdo
    );

  tms_probe: entity work.pin_id
    port map (
      clock => probe_clock,
      pin_number => to_unsigned(3, 8),
      pin => kb_tms
    );

  tdi_probe: entity work.pin_id
    port map (
      clock => probe_clock,
      pin_number => to_unsigned(4, 8),
      pin => kb_tdi
    );

  process(cpuclock) is
  begin
    if rising_edge(cpuclock) then
      if probe_clock_counter = probe_clock_divider - 1 then
        probe_clock_counter <= 0;
        probe_clock <= not probe_clock;
      else
        probe_clock_counter <= probe_clock_counter + 1;
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
