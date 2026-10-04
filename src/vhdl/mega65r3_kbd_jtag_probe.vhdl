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

  constant probe_slot_clocks : integer := 200000;
  signal cpuclock : std_logic;
  signal probe_pins : std_logic_vector(1 to 82);
  signal probe_pin_number : integer range 1 to 4 := 1;
  signal probe_slot_counter : integer range 0 to probe_slot_clocks := 0;

begin

  kb_jtagen <= '1';

  probe0: entity work.pinprober
    port map (
      Clk => cpuclock,
      pins => probe_pins,
      pin_number => probe_pin_number
    );

  kb_tck <= probe_pins(1) when probe_pin_number = 1 else '0';
  kb_tdo <= probe_pins(2) when probe_pin_number = 2 else '0';
  kb_tms <= probe_pins(3) when probe_pin_number = 3 else '0';
  kb_tdi <= probe_pins(4) when probe_pin_number = 4 else '0';

  process(cpuclock) is
  begin
    if rising_edge(cpuclock) then
      if probe_slot_counter = probe_slot_clocks then
        probe_slot_counter <= 0;
        if probe_pin_number = 4 then
          probe_pin_number <= 1;
        else
          probe_pin_number <= probe_pin_number + 1;
        end if;
      else
        probe_slot_counter <= probe_slot_counter + 1;
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
