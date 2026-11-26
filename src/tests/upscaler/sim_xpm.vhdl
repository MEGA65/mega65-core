-- sim_xpm.vhdl - for simulating the upscaler without Vivado's libraries: the
-- two XPM synchronisers it uses, as plain flip-flops. Compiled into a library
-- called xpm by run.sh.
library ieee;
use ieee.std_logic_1164.all;
package vcomponents is
  component xpm_cdc_single is
    generic (DEST_SYNC_FF : integer := 4; INIT_SYNC_FF : integer := 0;
             SIM_ASSERT_CHK : integer := 0; SRC_INPUT_REG : integer := 1);
    port (src_in : in std_logic; src_clk : in std_logic := '0';
          dest_clk : in std_logic; dest_out : out std_logic);
  end component;
  component xpm_cdc_array_single is
    generic (DEST_SYNC_FF : integer := 4; INIT_SYNC_FF : integer := 0;
             SIM_ASSERT_CHK : integer := 0; SRC_INPUT_REG : integer := 1; WIDTH : integer := 2);
    port (src_in : in std_logic_vector(WIDTH-1 downto 0); src_clk : in std_logic := '0';
          dest_clk : in std_logic; dest_out : out std_logic_vector(WIDTH-1 downto 0));
  end component;
end package;

library ieee;
use ieee.std_logic_1164.all;
entity xpm_cdc_single is
  generic (DEST_SYNC_FF : integer := 4; INIT_SYNC_FF : integer := 0;
           SIM_ASSERT_CHK : integer := 0; SRC_INPUT_REG : integer := 1);
  port (src_in : in std_logic; src_clk : in std_logic := '0';
        dest_clk : in std_logic; dest_out : out std_logic);
end entity;
architecture sim of xpm_cdc_single is
  signal src_r : std_logic := '0';
  signal sync : std_logic_vector(DEST_SYNC_FF-1 downto 0) := (others => '0');
begin
  process (src_clk) begin
    if rising_edge(src_clk) then src_r <= src_in; end if;
  end process;
  process (dest_clk) begin
    if rising_edge(dest_clk) then
      sync <= sync(DEST_SYNC_FF-2 downto 0) & src_r;
    end if;
  end process;
  dest_out <= sync(DEST_SYNC_FF-1);
end architecture;

library ieee;
use ieee.std_logic_1164.all;
entity xpm_cdc_array_single is
  generic (DEST_SYNC_FF : integer := 4; INIT_SYNC_FF : integer := 0;
           SIM_ASSERT_CHK : integer := 0; SRC_INPUT_REG : integer := 1; WIDTH : integer := 2);
  port (src_in : in std_logic_vector(WIDTH-1 downto 0); src_clk : in std_logic := '0';
        dest_clk : in std_logic; dest_out : out std_logic_vector(WIDTH-1 downto 0));
end entity;
architecture sim of xpm_cdc_array_single is
  type sync_t is array (0 to DEST_SYNC_FF-1) of std_logic_vector(WIDTH-1 downto 0);
  signal sync : sync_t := (others => (others => '0'));
begin
  process (dest_clk) begin
    if rising_edge(dest_clk) then
      sync(0) <= src_in;
      for i in 1 to DEST_SYNC_FF-1 loop sync(i) <= sync(i-1); end loop;
    end if;
  end process;
  dest_out <= sync(DEST_SYNC_FF-1);
end architecture;
