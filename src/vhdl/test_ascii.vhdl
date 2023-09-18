library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_ascii is
end entity;

architecture foo of test_ascii is

  signal clock50mhz : std_logic := '1';
  signal reset : std_logic := '1';
  signal matrix : std_logic_vector(71 downto 0) := (others => '1');
  signal ascii_key : unsigned(7 downto 0) := x"00";
  signal bucky_key : std_logic_vector(6 downto 0);
  signal key_valid : std_logic;

begin

  ascii0: entity work.matrix_to_ascii
    generic map (clock_frequency => 50000000)
    port map(
      clk => clock50mhz,
      reset_in => reset,
      ascii_key => ascii_key,
      suppress_key_glitches => '1',
      suppress_key_retrigger => '0',
      matrix_in => matrix,
      bucky_key => bucky_key,
      key_valid => key_valid
      );

  process is
  begin
    while true loop
      for j in 71 to 72 loop
        -- Lower each key in turn
        matrix <= (others => '1');
        if j /= 72 then
          report "Pulling key "
            & integer'image(j) & " down.";
          matrix(j) <= '0';
        else
          report "Releasing all keys.";
        end if;
        -- Then leave it low long enough to be meaningful
        for i in 1 to 250000 loop
          clock50mhz <= '0';
          wait for 10 ns;
          clock50mhz <= '1';
          wait for 10 ns;
        end loop;
      end loop;
    end loop;
  end process;

  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then
      if key_valid='1' then
        report "key_valid seen: ascii_key=$"
          & to_hstring(ascii_key);
      end if;
    end if;
  end process;

end foo;
