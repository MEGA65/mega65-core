library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
library std;
use std.textio.all;


entity testbench is
end entity;


architecture behavioral of testbench is

	constant PERIOD        : time := 10 ns;
	constant SPI_PERIOD    : time := PERIOD * 5;
	constant nVTPR         : integer := 30;

	constant SPI_READ_OPCODE  : std_logic_vector(7 downto 0) := x"69";
	constant SPI_WRITE_OPCODE : std_logic_vector(7 downto 0) := x"96";

	constant OVRL_ADDR_CR         : std_logic_vector(7 downto 0) := x"04";
	constant OVRL_ADDR_CLKDIV     : std_logic_vector(7 downto 0) := x"0a";
	constant OVRL_ADDR_CLKCNT     : std_logic_vector(7 downto 0) := x"0b";
	constant OVRL_ADDR_CONFIG     : std_logic_vector(7 downto 0) := x"0c";
	constant OVRL_ADDR_SNAPIN     : std_logic_vector(7 downto 0) := x"0d";
	constant OVRL_ADDR_SNAPOUT    : std_logic_vector(7 downto 0) := x"0e";

	constant OVRL_CR_RST          : std_logic_vector(31 downto 0) := x"00000001";
	constant OVRL_CR_SNAP_SAVE    : std_logic_vector(31 downto 0) := x"00000004";
	constant OVRL_CR_SNAP_RESTORE : std_logic_vector(31 downto 0) := x"00000008";

	signal clk             : std_logic := '0';
	signal rst             : std_logic := '1';
	signal stop_simulation : std_logic := '0';

	signal sclk            : std_logic := '0';
	signal mosi            : std_logic := '0';
	signal miso            : std_logic := '0';
	signal cs              : std_logic := '1';

	signal configuration_pushed  : std_logic := '0';
	signal snapshot_pushed       : std_logic := '0';
	signal application_started   : std_logic := '0';

	signal vfpga_inputs    : std_logic_vector(55 downto 0) := (others => '0');
	signal vfpga_outputs   : std_logic_vector(55 downto 0);

	signal vfpga_outputs_done : std_logic;
	signal vfpga_outputs_res  : std_logic_vector(31 downto 0);
	signal vfpga_clk          : std_logic;


	procedure clock_generation (signal clk             : out std_logic;
                                signal rst             : out std_logic;
								signal stop_simulation : in  std_logic) is
	begin
		clk <= '0';
		rst <= '1';
		wait for PERIOD;
		clk <= '1';
		wait for PERIOD / 2;
		clk <= '0';
		wait for PERIOD / 2;
		clk <= '1';
		wait for PERIOD / 2;
		clk <= '0';
		rst <= '0';
		wait for PERIOD / 2;
		clk <= '1';
		wait for PERIOD / 2;
		while stop_simulation = '0' loop
			clk <= '0';
			wait for PERIOD / 2;
			clk <= '1';
			wait for PERIOD / 2;
		end loop;
		wait;
	end procedure;


	procedure spi_tx (constant tx   : in  std_logic_vector(7 downto 0);
					  signal   sclk : out std_logic;
					  signal   mosi : out std_logic;
					  signal   miso : in  std_logic) is
	begin
		for cnt in 0 to 7 loop
			sclk <= '1';
			mosi <= tx(7 - cnt);
			wait for SPI_PERIOD / 2;
			sclk <= '0';
			wait for SPI_PERIOD / 2;
		end loop;
	end procedure;


	procedure spi_rx (variable rx   : out std_logic_vector(7 downto 0);
					  signal   sclk : out std_logic;
				      signal   mosi : out std_logic;
					  signal   miso : in  std_logic) is
	begin
		for cnt in 0 to 7 loop
			sclk <= '1';
			mosi <= '0';
			wait for SPI_PERIOD / 2;
			sclk <= '0';
			rx(7 - cnt) := miso;
			wait for SPI_PERIOD / 2;
		end loop;
	end procedure;


	procedure spi_txrx (signal tx   : in  std_logic_vector(7 downto 0);
	                    signal rx   : out std_logic_vector(7 downto 0);
					    signal sclk : out std_logic;
				        signal mosi : out std_logic;
					    signal miso : in  std_logic) is
	begin
		for cnt in 0 to 7 loop
			sclk <= '1';
			mosi <= tx(7 - cnt);
			wait for SPI_PERIOD / 2;
			sclk <= '0';
			rx(7 - cnt) <= miso;
			wait for SPI_PERIOD / 2;
		end loop;
	end procedure;


	procedure spi_write_register (constant reg_num : in  std_logic_vector(7 downto 0);
								  constant value   : in  std_logic_vector(31 downto 0);
							      signal   sclk    : out std_logic;
						          signal   mosi    : out std_logic;
						          signal   miso    : in  std_logic;
						          signal   cs      : out std_logic) is
	begin
		cs <= '0';
		wait for SPI_PERIOD / 2;
		spi_tx(SPI_WRITE_OPCODE, sclk, mosi, miso);
		spi_tx(reg_num, sclk, mosi, miso);
		spi_tx(value( 7 downto  0), sclk, mosi, miso);
		spi_tx(value(15 downto  8), sclk, mosi, miso);
		spi_tx(value(23 downto 16), sclk, mosi, miso);
		spi_tx(value(31 downto 24), sclk, mosi, miso);
		wait for SPI_PERIOD / 2;
		cs <= '1';
		wait for SPI_PERIOD;
	end procedure;


	procedure spi_read_register (constant reg_num : in  std_logic_vector(7 downto 0);
								 variable value   : out std_logic_vector(31 downto 0);
							     signal   sclk    : out std_logic;
						         signal   mosi    : out std_logic;
						         signal   miso    : in  std_logic;
						         signal   cs      : out std_logic) is
	begin
		cs <= '0';
		wait for SPI_PERIOD / 2;
		spi_tx(SPI_READ_OPCODE, sclk, mosi, miso);
		spi_tx(reg_num, sclk, mosi, miso);
		spi_tx(x"00", sclk, mosi, miso);
		spi_rx(value( 7 downto  0), sclk, mosi, miso);
		spi_rx(value(15 downto  8), sclk, mosi, miso);
		spi_rx(value(23 downto 16), sclk, mosi, miso);
		spi_rx(value(31 downto 24), sclk, mosi, miso);
		wait for SPI_PERIOD / 2;
		cs <= '1';
		wait for SPI_PERIOD;
	end procedure;


	procedure spi_app_reset (signal sclk : out std_logic;
                             signal mosi : out std_logic;
                             signal miso : in  std_logic;
                             signal cs   : out std_logic) is
		variable value : std_logic_vector(31 downto 0);
	begin
		spi_read_register(OVRL_ADDR_CR, value, sclk, mosi, miso, cs);
		value := value or OVRL_CR_RST;
		spi_write_register(OVRL_ADDR_CR, value, sclk, mosi, miso, cs);
	end procedure;


	procedure spi_app_unreset (signal sclk : out std_logic;
                               signal mosi : out std_logic;
                               signal miso : in  std_logic;
                               signal cs   : out std_logic) is
		variable value : std_logic_vector(31 downto 0);
	begin
		spi_read_register(OVRL_ADDR_CR, value, sclk, mosi, miso, cs);
		value := value and not(OVRL_CR_RST);
		spi_write_register(OVRL_ADDR_CR, value, sclk, mosi, miso, cs);
	end procedure;


	procedure spi_save_snapshot (signal sclk : out std_logic;
                                 signal mosi : out std_logic;
                                 signal miso : in  std_logic;
                                 signal cs   : out std_logic) is
		variable value : std_logic_vector(31 downto 0);
	begin
		spi_read_register(OVRL_ADDR_CR, value, sclk, mosi, miso, cs);
		value := value or OVRL_CR_SNAP_SAVE;
		spi_write_register(OVRL_ADDR_CR, value, sclk, mosi, miso, cs);
	end procedure;


	procedure spi_restore_snapshot (signal sclk : out std_logic;
                                    signal mosi : out std_logic;
                                    signal miso : in  std_logic;
                                    signal cs   : out std_logic) is
		variable value : std_logic_vector(31 downto 0);
	begin
		spi_read_register(OVRL_ADDR_CR, value, sclk, mosi, miso, cs);
		value := value or OVRL_CR_SNAP_RESTORE;
		spi_write_register(OVRL_ADDR_CR, value, sclk, mosi, miso, cs);
	end procedure;


	procedure spi_set_clkdiv (constant lnVTPR : integer;
							  signal   sclk   : out std_logic;
                              signal   mosi   : out std_logic;
                              signal   miso   : in  std_logic;
                              signal   cs     : out std_logic) is
	begin
		spi_write_register(OVRL_ADDR_CLKDIV, std_logic_vector(to_unsigned(lnVTPR - 1, 32)), sclk, mosi, miso, cs);
	end procedure;


	procedure spi_start_clk (signal   sclk  : out std_logic;
                             signal   mosi  : out std_logic;
                             signal   miso  : in  std_logic;
                             signal   cs    : out std_logic) is
	begin
		spi_write_register(OVRL_ADDR_CLKCNT, x"00ffffff", sclk, mosi, miso, cs);
	end procedure;


	procedure spi_stop_clk (signal   sclk  : out std_logic;
                            signal   mosi  : out std_logic;
                            signal   miso  : in  std_logic;
                            signal   cs    : out std_logic) is
	begin
		spi_write_register(OVRL_ADDR_CLKCNT, x"00000000", sclk, mosi, miso, cs);
	end procedure;


	procedure spi_configure_bitstream (constant file_name : string;
									   signal sclk : out std_logic;
                                       signal mosi : out std_logic;
                                       signal miso : in  std_logic;
                                       signal cs   : out std_logic) is
		file bitstream_file : text open read_mode is file_name;
		variable tmpline    : line;
		variable tmpword    : std_logic_vector(31 downto 0);
	begin
		cs <= '0';
		wait for SPI_PERIOD / 2;
		spi_tx(SPI_WRITE_OPCODE, sclk, mosi, miso);
		spi_tx(OVRL_ADDR_CONFIG, sclk, mosi, miso);
		while not endfile(bitstream_file) loop
			readline(bitstream_file, tmpline);
			hread(tmpline, tmpword);
			spi_tx(tmpword( 7 downto  0), sclk, mosi, miso);
			spi_tx(tmpword(15 downto  8), sclk, mosi, miso);
			spi_tx(tmpword(23 downto 16), sclk, mosi, miso);
			spi_tx(tmpword(31 downto 24), sclk, mosi, miso);
		end loop;
		wait for SPI_PERIOD / 2;
		cs <= '1';
		wait for SPI_PERIOD;
	end procedure;


	procedure spi_push_snapshot (constant file_name : string;
								 signal sclk : out std_logic;
                                 signal mosi : out std_logic;
                                 signal miso : in  std_logic;
                                 signal cs   : out std_logic) is
		file snapshot_file : text open read_mode is file_name;
		variable tmpline    : line;
		variable tmpword    : std_logic_vector(31 downto 0);
	begin
		cs <= '0';
		wait for SPI_PERIOD / 2;
		spi_tx(SPI_WRITE_OPCODE, sclk, mosi, miso);
		spi_tx(OVRL_ADDR_SNAPIN, sclk, mosi, miso);
		while not endfile(snapshot_file) loop
			readline(snapshot_file, tmpline);
			hread(tmpline, tmpword);
			spi_tx(tmpword( 7 downto  0), sclk, mosi, miso);
			spi_tx(tmpword(15 downto  8), sclk, mosi, miso);
			spi_tx(tmpword(23 downto 16), sclk, mosi, miso);
			spi_tx(tmpword(31 downto 24), sclk, mosi, miso);
		end loop;
		wait for SPI_PERIOD / 2;
		cs <= '1';
		wait for SPI_PERIOD;
	end procedure;

begin

	DUT: entity work.top_level
    port map (CLKX          => clk,
		      RST_BTN       => rst,
		      SCLK          => sclk,
		      CS            => cs,
		      MOSI          => mosi,
		      MISO          => miso,
			  VFPGA_CLK     => vfpga_clk,
		      VFPGA_INPUTS  => vfpga_inputs,
		      VFPGA_OUTPUTS => vfpga_outputs);


	clock_generation(clk, rst, stop_simulation);


	process
		variable tmpline          : line;
		variable tmpword          : std_logic_vector(31 downto 0);
		variable nb_sample_tested : integer := 0;
		variable nb_errors        : integer := 0;
		file     input_data_file  : text open read_mode is "DMA_data_in.hex";
		file     golden_data_file : text open read_mode is "DMA_data_out.hex";
	begin
		wait for PERIOD * 10.5;
		report "Configuring the overlay...";
		spi_configure_bitstream("app_bitstream.hex", sclk, mosi, miso, cs);
		report "Configuration pushed";
		configuration_pushed <= '1';
		report "Pushing initialization snapshot...";
		spi_push_snapshot("app_init_snapshot.hex", sclk, mosi, miso, cs);
		report "Initialization snapshot pushed";
		snapshot_pushed <= '1';
		report "Unresetting application registers...";
		spi_app_unreset(sclk, mosi, miso, cs);
		report "Restoring snapshot into application registers...";
		spi_restore_snapshot(sclk, mosi, miso, cs);
		report "Setting virtual clock divisor...";
		spi_set_clkdiv(nVTPR, sclk, mosi, miso, cs);
		report "Starting virtual clock...";
		spi_start_clk(sclk, mosi, miso, cs);
		application_started <= '1';

		wait until rising_edge(clk);

		while not(endfile(input_data_file)) and not(endfile(golden_data_file)) loop
			readline(input_data_file, tmpline);
			hread(tmpline, tmpword);

			wait until vfpga_clk = '1';

			vfpga_inputs <= (others => '0');
			vfpga_inputs(31 downto 0) <= tmpword;
			vfpga_inputs(32) <= '1';

			readline(golden_data_file, tmpline);
			hread(tmpline, tmpword);

			wait until vfpga_clk = '0';
			wait until vfpga_clk = '1';
			wait until vfpga_clk = '0';
			wait until vfpga_clk = '1';

			vfpga_inputs(32) <= '0';

			wait until (vfpga_clk = '1' and vfpga_outputs_done = '1');

			nb_sample_tested := nb_sample_tested + 1;
			if vfpga_outputs(31 downto 0) /= tmpword then
				nb_errors := nb_errors + 1;
				report "Sample " & integer'image(nb_sample_tested) & " FAIL" severity warning;
				--report "Sample " & integer'image(nb_sample_tested) & " FAIL (" & integer'image(vfpga_inputs(31 downto 16)) & " x " & integer'image(vfpga_inputs(15 downto 0)) & " = " & integer'image(tmpword) & " # " integer'image(vfpga_outputs(31 downto 0)) severity warning;
			else
				report "Sample " & integer'image(nb_sample_tested) & " ok";
			end if;
		end loop;

		report "Simulation ended";
		write(tmpline, integer'image(nb_errors) & " / " & integer'image(nb_sample_tested) & " errors");
		writeline(output, tmpline);
		if nb_errors = 0 then
			write(tmpline, String'("TEST PASSED"));
		else
			write(tmpline, String'("TEST FAILED"));
		end if;
		writeline(output, tmpline);
		if nb_errors /= 0 then
			report "Produced data was different from the golden model!" severity failure;
		end if;
		
		stop_simulation <= '1';
		wait;
	end process;

	vfpga_outputs_done <= vfpga_outputs(32);
	vfpga_outputs_res <= vfpga_outputs(31 downto 0);

end architecture;

