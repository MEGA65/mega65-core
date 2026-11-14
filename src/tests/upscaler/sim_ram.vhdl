-- sim_ram.vhdl - src/vhdl/upscaler_ram32x1024.vhdl without the line it
-- reports for every read (74 million a second of simulated time).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity upscaler_ram32x1024 is
  port (clka : in std_logic; ena : in std_logic; wea : in std_logic;
        addra : in std_logic_vector(9 downto 0); dina : in std_logic_vector(31 downto 0);
        clkb : in std_logic; enb : in std_logic;
        addrb : in std_logic_vector(9 downto 0); doutb : out std_logic_vector(31 downto 0));
end entity;
architecture sim of upscaler_ram32x1024 is
  type ram_t is array (0 to 1023) of std_logic_vector(31 downto 0);
  signal ram : ram_t := (others => (others => '0'));
  -- (not 'U' before the first read: every use of that would be warned of)
  signal q : std_logic_vector(31 downto 0) := (others => '0');
begin
  doutb <= q;
  process (clka) begin
    if rising_edge(clka) then
      if ena = '1' and wea = '1' then ram(to_integer(unsigned(addra))) <= dina; end if;
    end if;
  end process;
  process (clkb) begin
    if rising_edge(clkb) then
      if enb = '1' then q <= ram(to_integer(unsigned(addrb))); end if;
    end if;
  end process;
end architecture;
