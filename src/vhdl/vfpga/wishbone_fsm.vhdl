-- Theotime Bollengier --

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity wishbone_master_fsm is
	port ( CLK_I    : in  std_logic;
		   RST_I    : in  std_logic;
		   ---------------------------------------------
		   CYCSTB_O : out std_logic;
		   WE_O     : out std_logic;
		   SEL_O    : out std_logic_vector(3 downto 0);
		   ADR_O    : out std_logic_vector(7 downto 0);
		   DAT_O    : out std_logic_vector(31 downto 0);
		   DAT_I    : in  std_logic_vector(31 downto 0);
		   ACK_I    : in  std_logic;
		   ---------------------------------------------
		   addr     : in  std_logic_vector(7 downto 0);
		   data_w   : in  std_logic_vector(31 downto 0);
		   data_r   : out std_logic_vector(31 downto 0);
		   read     : in  std_logic;
		   write    : in  std_logic);
end wishbone_master_fsm;


architecture Behavioral of wishbone_master_fsm is

	type state_t is (wait_s, wait_for_ack_s);
	signal state     : state_t := wait_s;

begin

	SEL_O <= "1111";


	process (CLK_I)
	begin
		if rising_edge(CLK_I) then
			if RST_I = '1' then
				CYCSTB_O <= '0';
				WE_O <= '0';
				ADR_O <= (others => '0');
				DAT_O <= (others => '0');
				data_r <= (others => '0');
			else
				case state is

					when wait_s =>
						if read = '1' then
							WE_O <= '0';
						elsif write = '1' then
							WE_O <= '1';
						end if;
						if read = '1' or write = '1' then
							CYCSTB_O <= '1';
							ADR_O <= addr;
							DAT_O <= data_w;
							state <= wait_for_ack_s;
						end if;

					when wait_for_ack_s =>
						if ACK_I = '1' then
							CYCSTB_O <= '0';
							data_r <= DAT_I;
							state <= wait_s;
						end if;

				end case;
			end if;
		end if;
	end process;

end Behavioral;

