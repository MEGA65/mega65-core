-- The three XPM clock-domain crossings vga_to_hdmi.vhdl uses, as plain logic.
library ieee;
use ieee.std_logic_1164.all;
package vcomponents is
  component xpm_cdc_array_single is
    generic (DEST_SYNC_FF : integer := 4; INIT_SYNC_FF : integer := 0;
             SIM_ASSERT_CHK : integer := 0; SRC_INPUT_REG : integer := 1; WIDTH : integer := 2);
    port (src_in : in std_logic_vector(WIDTH-1 downto 0); src_clk : in std_logic := '0';
          dest_clk : in std_logic; dest_out : out std_logic_vector(WIDTH-1 downto 0));
  end component;
  component xpm_cdc_pulse is
    generic (DEST_SYNC_FF : integer := 4; INIT_SYNC_FF : integer := 0; REG_OUTPUT : integer := 0;
             RST_USED : integer := 1; SIM_ASSERT_CHK : integer := 0);
    port (src_rst : in std_logic := '0'; src_clk : in std_logic; src_pulse : in std_logic;
          dest_rst : in std_logic := '0'; dest_clk : in std_logic; dest_pulse : out std_logic);
  end component;
  component xpm_cdc_handshake is
    generic (DEST_EXT_HSK : integer := 1; DEST_SYNC_FF : integer := 4; INIT_SYNC_FF : integer := 0;
             SIM_ASSERT_CHK : integer := 0; SRC_SYNC_FF : integer := 4; WIDTH : integer := 1);
    port (src_clk : in std_logic; src_in : in std_logic_vector(WIDTH-1 downto 0);
          src_send : in std_logic; src_rcv : out std_logic;
          dest_clk : in std_logic; dest_req : out std_logic; dest_ack : in std_logic := '0';
          dest_out : out std_logic_vector(WIDTH-1 downto 0));
  end component;
end package;

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

library ieee;
use ieee.std_logic_1164.all;
entity xpm_cdc_pulse is
  generic (DEST_SYNC_FF : integer := 4; INIT_SYNC_FF : integer := 0; REG_OUTPUT : integer := 0;
           RST_USED : integer := 1; SIM_ASSERT_CHK : integer := 0);
  port (src_rst : in std_logic := '0'; src_clk : in std_logic; src_pulse : in std_logic;
        dest_rst : in std_logic := '0'; dest_clk : in std_logic; dest_pulse : out std_logic);
end entity;
architecture sim of xpm_cdc_pulse is
  signal tog, last : std_logic := '0';
  signal sync : std_logic_vector(DEST_SYNC_FF downto 0) := (others => '0');
begin
  process (src_clk) begin
    if rising_edge(src_clk) then
      last <= src_pulse;
      if src_pulse = '1' and last = '0' then tog <= not tog; end if;
    end if;
  end process;
  process (dest_clk) begin
    if rising_edge(dest_clk) then
      sync <= sync(DEST_SYNC_FF-1 downto 0) & tog;
    end if;
  end process;
  dest_pulse <= sync(DEST_SYNC_FF) xor sync(DEST_SYNC_FF-1);
end architecture;

library ieee;
use ieee.std_logic_1164.all;
entity xpm_cdc_handshake is
  generic (DEST_EXT_HSK : integer := 1; DEST_SYNC_FF : integer := 4; INIT_SYNC_FF : integer := 0;
           SIM_ASSERT_CHK : integer := 0; SRC_SYNC_FF : integer := 4; WIDTH : integer := 1);
  port (src_clk : in std_logic; src_in : in std_logic_vector(WIDTH-1 downto 0);
        src_send : in std_logic; src_rcv : out std_logic;
        dest_clk : in std_logic; dest_req : out std_logic; dest_ack : in std_logic := '0';
        dest_out : out std_logic_vector(WIDTH-1 downto 0));
end entity;
-- With DEST_EXT_HSK = 0 (all this design uses): dest_req is high for one
-- dest_clk cycle with the data; src_rcv follows src_send back.
architecture sim of xpm_cdc_handshake is
  signal held : std_logic_vector(WIDTH-1 downto 0) := (others => '0');
  signal send_r : std_logic := '0';
  signal dsync : std_logic_vector(DEST_SYNC_FF downto 0) := (others => '0');
  signal ssync : std_logic_vector(SRC_SYNC_FF-1 downto 0) := (others => '0');
begin
  process (src_clk) begin
    if rising_edge(src_clk) then
      send_r <= src_send;
      if src_send = '1' and send_r = '0' then held <= src_in; end if;
      ssync <= ssync(SRC_SYNC_FF-2 downto 0) & dsync(DEST_SYNC_FF-1);
    end if;
  end process;
  src_rcv <= ssync(SRC_SYNC_FF-1);
  process (dest_clk) begin
    if rising_edge(dest_clk) then
      dsync <= dsync(DEST_SYNC_FF-1 downto 0) & send_r;
      dest_req <= '0';
      if dsync(DEST_SYNC_FF-1) = '1' and dsync(DEST_SYNC_FF) = '0' then
        dest_out <= held; dest_req <= '1';
      end if;
    end if;
  end process;
end architecture;
