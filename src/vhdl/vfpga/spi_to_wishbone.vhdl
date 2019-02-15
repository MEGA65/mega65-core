-- Theotime Bollengier --

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity spi_to_wishbone is
	port ( CLK_I    : in  std_logic;
		   RST_I    : in  std_logic;
		   --------------------------------------------
		   CYCSTB_O : out std_logic;
		   WE_O     : out std_logic;
		   SEL_O    : out std_logic_vector(3 downto 0);
		   ADR_O    : out std_logic_vector(7 downto 0);
		   DAT_O    : out std_logic_vector(31 downto 0);
		   DAT_I    : in  std_logic_vector(31 downto 0);
		   ACK_I    : in  std_logic;
		   --------------------------------------------
		   SCLK     : in  std_logic;
		   CS       : in  std_logic;
		   MOSI     : in  std_logic;
		   MISO     : out std_logic);
end spi_to_wishbone;


architecture Behavioral of spi_to_wishbone is

	signal tx       : std_logic_vector(7 downto 0);
	signal rx       : std_logic_vector(7 downto 0);
	signal rx_valid : std_logic;

	signal addr     : std_logic_vector(7 downto 0);
	signal data_w   : std_logic_vector(31 downto 0);
	signal data_r   : std_logic_vector(31 downto 0);
	signal read     : std_logic;
	signal write    : std_logic;

	signal nrd_wr   : std_logic;

	type state_t is (get_opcode_s,
                     trap_s,
				     get_addr0_s,
				     rx_wr0_s,
				     rx_wr1_s,
				     rx_wr2_s,
				     rx_wr3_s,
				     inc_waddr_s,
				     tx_rd0_s,
				     tx_rd1_s,
				     tx_rd2_s,
				     tx_rd3_s);
	signal state    : state_t := get_opcode_s;

begin

	SPI_RXTX_0: entity work.spi_rxtx
	port map ( clk      => CLK_I,
			   rst      => RST_I,
			   SCLK     => SCLK,
			   CS       => CS,
			   MOSI     => MOSI,
			   MISO     => MISO,
			   TX_byte  => tx,
			   RX_byte  => rx,
			   RX_valid => rx_valid);


	WISHBONE_FSM_0: entity work.wishbone_master_fsm
	port map ( CLK_I    => CLK_I,
			   RST_I    => RST_I,
			   CYCSTB_O => CYCSTB_O,
			   WE_O     => WE_O,
			   SEL_O    => SEL_O,
			   ADR_O    => ADR_O,
			   DAT_O    => DAT_O,
			   DAT_I    => DAT_I,
			   ACK_I    => ACK_I,
			   addr     => addr,
			   data_w   => data_w,
			   data_r   => data_r,
			   read     => read,
			   write    => write);


	process (CLK_I)
	begin
		if rising_edge(CLK_I) then
			if RST_I = '1' or CS = '1' then
				tx     <= (others => '0');
				addr   <= (others => '0');
				data_w <= (others => '0');
				read   <= '0';
				write  <= '0';
				state  <= get_opcode_s;
			else
				case state is

					when get_opcode_s =>
						if rx_valid = '1' then
							if rx = x"69" then
								nrd_wr <= '0';
								state <= get_addr0_s;
							elsif rx = x"96" then
								nrd_wr <= '1';
								state <= get_addr0_s;
							else
								state <= trap_s;
							end if;
						end if;

					when trap_s =>
						null;

					when get_addr0_s =>
						if rx_valid = '1' then
							addr <= rx;
							if nrd_wr = '0' then
								read <= '1';
								state <= tx_rd0_s;
							else
								state <= rx_wr0_s;
							end if;
						end if;

					when rx_wr0_s =>
						if rx_valid = '1' then
							data_w(7 downto 0) <= rx;
							state <= rx_wr1_s;
						end if;

					when rx_wr1_s =>
						if rx_valid = '1' then
							data_w(15 downto 8) <= rx;
							state <= rx_wr2_s;
						end if;

					when rx_wr2_s =>
						if rx_valid = '1' then
							data_w(23 downto 16) <= rx;
							state <= rx_wr3_s;
						end if;

					when rx_wr3_s =>
						if rx_valid = '1' then
							data_w(31 downto 24) <= rx;
							write <= '1';
							state <= inc_waddr_s;
						end if;

					when inc_waddr_s =>
						write <= '0';
						-- Do not increment address when writting config or snapshot --
						if addr /= "00001100" and addr /= "00001101" then
							addr <= std_logic_vector(unsigned(addr) + 1);
						end if;
						state <= rx_wr0_s;

					when tx_rd0_s =>
						read <= '0';
						if rx_valid = '1' then
							tx <= data_r(7 downto 0);
							state <= tx_rd1_s;
						end if;

					when tx_rd1_s =>
						if rx_valid = '1' then
							tx <= data_r(15 downto 8);
							state <= tx_rd2_s;
						end if;

					when tx_rd2_s =>
						if rx_valid = '1' then
							tx <= data_r(23 downto 16);
							state <= tx_rd3_s;
						end if;

					when tx_rd3_s =>
						if rx_valid = '1' then
							tx <= data_r(31 downto 24);
							-- Do not increment address when reading snapshot --
							if addr /= "00001110" then
								addr <= std_logic_vector(unsigned(addr) + 1);
							end if;
							read <= '1';
							state <= tx_rd0_s;
						end if;

					when others =>
						state <= get_opcode_s;

				end case;
			end if;
		end if;
	end process;

end Behavioral;

