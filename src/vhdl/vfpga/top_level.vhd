-- Theotime Bollengier --


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity top_level is
    port ( CLKX                : in  std_logic;
		   RST_BTN             : in  std_logic;
		   -- SPI ------------------------------------------------
		   SCLK                : in  std_logic;
		   CS                  : in  std_logic;
		   MOSI                : in  std_logic;
		   MISO                : out std_logic;
		   -- IO -------------------------------------------------
		   VFPGA_CLK           : out std_logic;
		   VFPGA_INPUTS        : in  std_logic_vector(55 downto 0);
		   VFPGA_OUTPUTS       : out std_logic_vector(55 downto 0));
end top_level;


architecture Behavioral of top_level is

	signal clk        : std_logic;
	signal rst        : std_logic;

	signal M_CYCSTB_O : std_logic;
	signal M_WE_O     : std_logic;
	signal M_SEL_O    : std_logic_vector(3 downto 0);
	signal M_ADR_O    : std_logic_vector(7 downto 0);
	signal M_DAT_O    : std_logic_vector(31 downto 0);
	signal M_DAT_I    : std_logic_vector(31 downto 0);
	signal M_ACK_I    : std_logic;

begin

	clk <= CLKX;
	rst <= RST_BTN;


	SPI_TO_WISHBONE_0: entity work.spi_to_wishbone
	port map ( CLK_I    => clk,
		       RST_I    => rst,
		       CYCSTB_O => M_CYCSTB_O,
		       WE_O     => M_WE_O,
		       SEL_O    => M_SEL_O,
		       ADR_O    => M_ADR_O,
		       DAT_O    => M_DAT_O,
		       DAT_I    => M_DAT_I,
		       ACK_I    => M_ACK_I,
		       SCLK     => SCLK,
		       CS       => CS,
		       MOSI     => MOSI,
		       MISO     => MISO);


	VFPGA_0: entity work.VFPGA_WRAPPER
	port map ( CLK_I          => clk,
			   RST_I          => rst,
			   SLAVE_CYC_I    => M_CYCSTB_O,
			   SLAVE_STB_I    => M_CYCSTB_O,
			   SLAVE_WE_I     => M_WE_O,
			   SLAVE_SEL_I    => M_SEL_O,
			   SLAVE_ADR_I    => M_ADR_O,
			   SLAVE_DAT_I    => M_DAT_O,
			   SLAVE_DAT_O    => M_DAT_I,
			   SLAVE_ACK_O    => M_ACK_I,
			   VFPGA_CLK      => VFPGA_CLK,
			   INPUTS         => VFPGA_INPUTS,
		       OUTPUTS        => VFPGA_OUTPUTS);

end Behavioral;

