-- Theotime Bollengier --
-- POL=0
-- PHA=1
-- SPI_MODE=1
-- MSB first


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity spi_rxtx is
    port ( clk      : in  std_logic;
           rst      : in  std_logic;
		   SCLK     : in  std_logic;
		   CS       : in  std_logic;
		   MOSI     : in  std_logic;
		   MISO     : out std_logic;
           TX_byte  : in  std_logic_vector(7 downto 0);
           RX_byte  : out std_logic_vector(7 downto 0);
           RX_valid : out std_logic);
end spi_rxtx;


architecture Behavioral of spi_rxtx is

	signal sclk_r    : std_logic;
	signal sclk_rr   : std_logic;
	signal sclk_rise : std_logic;
	signal sclk_fall : std_logic;
	signal cs_r      : std_logic;
	signal mosi_r    : std_logic;
	signal tx_reg    : std_logic_vector(6 downto 0);
	signal rx_reg    : std_logic_vector(6 downto 0);
	signal counter   : std_logic_vector(2 downto 0);

	type state_t is (start_byte_s, set_s, sample_s);
	signal state     : state_t := start_byte_s;

begin

	process (clk)
	begin
		if rising_edge(clk) then
			sclk_r  <= SCLK;
			sclk_rr <= sclk_r;
			cs_r    <= CS;
			mosi_r  <= MOSI;
		end if;
	end process;

	sclk_rise <= '1' when (sclk_r = '1' and sclk_rr = '0') else '0';
	sclk_fall <= '1' when (sclk_r = '0' and sclk_rr = '1') else '0';


	process (clk)
	begin
		if rising_edge(clk) then
			if rst = '1' or cs_r = '1' then
				MISO <= '0';
				RX_byte <= (others => '0');
				RX_valid <= '0';
				state <= start_byte_s;
			else
				case state is

					when start_byte_s =>
						counter <= (others => '0');
						RX_valid <= '0';
						if sclk_rise = '1' then
							MISO <= TX_byte(7);
							tx_reg <= TX_byte(6 downto 0);
							state <= sample_s;
						end if;

					when set_s =>
						if sclk_rise = '1' then
							MISO <= tx_reg(6);
							tx_reg <= tx_reg(5 downto 0) & '0';
							state <= sample_s;
							counter <= std_logic_vector(unsigned(counter) + 1);
						end if;

					when sample_s =>
						if sclk_fall = '1' then
							rx_reg <= rx_reg(5 downto 0) & mosi_r;
							if counter = "111" then
								state <= start_byte_s;
								RX_byte <= rx_reg & mosi_r;
								RX_valid <= '1';
							else
								state <= set_s;
							end if;
						end if;

					when others =>
						state <= start_byte_s;

				end case;
			end if;
		end if;
	end process;

end Behavioral;

