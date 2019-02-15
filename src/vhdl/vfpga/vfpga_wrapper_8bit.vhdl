
architecture Behavioral of VFPGA_WRAPPER is

	signal CLK_I_u          : std_ulogic := '0';
	signal RST_I_u          : std_ulogic := '0';
	signal SLAVE_CYC_I_u    : std_ulogic := '0';
	signal SLAVE_STB_I_u    : std_ulogic := '0';
	signal SLAVE_WE_I_u     : std_ulogic := '0';
	signal SLAVE_SEL_I_u    : std_ulogic_vector(3 downto 0) := (others => '0');  
	signal SLAVE_ADR_I_u    : std_ulogic_vector(7 downto 0) := (others => '0'); 
	signal SLAVE_DAT_I_u    : std_ulogic_vector(31 downto 0) := (others => '0'); 
	signal SLAVE_DAT_O_u    : std_ulogic_vector(31 downto 0) := (others => '0'); 
	signal SLAVE_ACK_O_u    : std_ulogic := '0';
	signal MASTER_CYC_O_u   : std_ulogic := '0';
    signal MASTER_STB_O_u   : std_ulogic := '0';
    signal MASTER_WE_O_u    : std_ulogic := '0';
    signal MASTER_SEL_O_u   : std_ulogic_vector(3 downto 0) := (others => '0');
    signal MASTER_ADR_O_u   : std_ulogic_vector(29 downto 0) := (others => '0');
    signal MASTER_DAT_O_u   : std_ulogic_vector(31 downto 0) := (others => '0');
    signal MASTER_DAT_I_u   : std_ulogic_vector(31 downto 0) := (others => '0');
    signal MASTER_ACK_I_u   : std_ulogic := '0';
	signal INTERRUPT_u      : std_ulogic := '0';
                                   
	signal clk_app                 : std_ulogic := '0';
	signal vFPGA_snap_save         : std_ulogic := '0';
	signal vFPGA_snap_restore      : std_ulogic := '0';
	signal vFPGA_snap_in           : std_ulogic_vector(31 downto 0) := (others => '0');
	signal vFPGA_snap_out          : std_ulogic_vector(31 downto 0) := (others => '0');
	signal vFPGA_snap_shift        : std_ulogic := '0';
	signal vFPGA_config_in         : std_ulogic_vector(31 downto 0) := (others => '0');
	signal vFPGA_config_valid      : std_ulogic := '0';
	signal vFPGA_inputs            : std_ulogic_vector(55 downto 0) := (others => '0');
	signal vFPGA_outputs           : std_ulogic_vector(55 downto 0) := (others => '0');
	signal clk_done_IE             : std_logic := '0';

	signal reg_rst_app             : std_ulogic := '0';
	signal reg_clk_div             : std_ulogic_vector(9 downto 0) := (others => '0');
	signal reg_clk_cycle_counter   : std_ulogic_vector(23 downto 0) := (others => '0');

	signal clk_cycle_counter_valid : std_ulogic := '0';

	signal clk_cycle_counter_remainder : std_ulogic_vector(23 downto 0) := (others => '0');
	signal clk_cycle_counter_done  : std_ulogic := '0';

	signal global_interrupt        : std_ulogic := '0';
	signal global_interrupt_IE     : std_ulogic := '0';

	signal write_config            : std_ulogic := '0';
	signal old_write_config        : std_ulogic := '0';

	signal write_snap_in           : std_ulogic := '0';
	signal read_snap_out           : std_ulogic := '0';
	signal old_write_snap_in       : std_ulogic := '0';
	signal old_read_snap_out       : std_ulogic := '0';

	signal write_snap_save         : std_ulogic := '0';
	signal write_snap_restore      : std_ulogic := '0';
	signal old_write_snap_save     : std_ulogic := '0';
	signal old_write_snap_restore  : std_ulogic := '0';

	signal write_clkcnt            : std_ulogic := '0';
	signal old_write_clkcnt        : std_ulogic := '0';

begin

	CLK_I_u        <= std_ulogic(CLK_I);
	RST_I_u        <= std_ulogic(RST_I);
	SLAVE_CYC_I_u  <= std_ulogic(SLAVE_CYC_I);
	SLAVE_STB_I_u  <= std_ulogic(SLAVE_STB_I);
	SLAVE_WE_I_u   <= std_ulogic(SLAVE_WE_I);
	SLAVE_SEL_I_u  <= std_ulogic_vector(SLAVE_SEL_I);
	SLAVE_ADR_I_u  <= std_ulogic_vector(SLAVE_ADR_I);
	SLAVE_DAT_I_u  <= std_ulogic_vector(SLAVE_DAT_I);

	SLAVE_DAT_O    <= std_logic_vector(SLAVE_DAT_O_u);
	SLAVE_ACK_O    <= std_logic(SLAVE_ACK_O_u);

	VFPGA_CLK      <= std_logic(clk_app);

	process (CLK_I_u)
	begin
		if rising_edge(CLK_I_u) then
			if RST_I_u = '1' then
				INTERRUPT_u <= '0';
				global_interrupt <= '0';
			else
				INTERRUPT_u <= global_interrupt and global_interrupt_IE;
				global_interrupt <= (clk_cycle_counter_done and clk_done_IE);
			end if;
		end if;
	end process;


	vFPGA: entity work.ARCH8X6W16N4I10K4FCI4FCO8PFI8PFO8IOPB2_wrapper
	port map ( clk          => CLK_I_u,
	           rst          => RST_I_u,
	           clk_app      => clk_app,
	           rst_app      => reg_rst_app,
	           snap_save    => vFPGA_snap_save,
	           snap_restore => vFPGA_snap_restore,
	           config_in    => vFPGA_config_in,
	           config_valid => vFPGA_config_valid,
	           snap_in      => vFPGA_snap_in,
	           snap_out     => vFPGA_snap_out,
	           snap_shift   => vFPGA_snap_shift,
	           inputs       => vFPGA_inputs,
	           outputs      => vFPGA_outputs);


	CLK_CTRL: entity work.vFPGA_clock_controler
	port map ( clk               => CLK_I_u,
	           rst               => RST_I_u,
	           clk_div           => reg_clk_div,
	           clk_cont_in       => reg_clk_cycle_counter,
	           clk_cont_in_valid => clk_cycle_counter_valid,
	           continue_clk_app  => '0',
	           clk_cont_out      => clk_cycle_counter_remainder,
		       done              => clk_cycle_counter_done,
		       clk_app           => clk_app);


	-- Read process --
	process(CLK_I_u)
	begin
		if rising_edge(CLK_I_u) then
			SLAVE_DAT_O_u <= (others => '0');
			if (RST_I_u = '0') and (SLAVE_CYC_I_u = '1') and (SLAVE_STB_I_u = '1') then
				SLAVE_DAT_O_u  <= (others => '0');
				case SLAVE_ADR_I_u is
					when "00000000" => -- PRES1
						SLAVE_DAT_O_u( 5 downto  0) <= "000111"; -- width
						SLAVE_DAT_O_u(11 downto  6) <= "000101"; -- height
						SLAVE_DAT_O_u(17 downto 12) <= "000111";  -- Logical wire cardinality (= W/2)
						SLAVE_DAT_O_u(21 downto 18) <= "0011";    -- N
						SLAVE_DAT_O_u(28 downto 22) <= "0001001";    -- I
						SLAVE_DAT_O_u(31 downto 29) <= "011";    -- K
					when "00000001" => -- PRES2
						SLAVE_DAT_O_u(22 downto  0) <= "00000000010110101101000"; -- Bitstream size in bits
						SLAVE_DAT_O_u(31 downto 23) <= "000111000"; -- Number of IO bits (= nb inputs = nb outputs)
					when "00000010" => -- PRES3
						SLAVE_DAT_O_u( 5 downto  0) <= "000000"; -- DMA word width
						SLAVE_DAT_O_u(11 downto  6) <= "000000"; -- MEM word width
						SLAVE_DAT_O_u(17 downto 12) <= "000000"; -- MEM address width
						SLAVE_DAT_O_u(18) <= '0'; -- With DMA ?
						SLAVE_DAT_O_u(19) <= '0'; -- With MEM access ?
						SLAVE_DAT_O_u(20) <= '0'; -- With interrupt pin ?
						SLAVE_DAT_O_u(31 downto 21) <= "10011001010"; -- Architecture file SHA1 11 LSB bits
					when "00000011" => -- SR
						SLAVE_DAT_O_u(5 downto  0) <= "110" & "0" & clk_cycle_counter_done & reg_rst_app;
						SLAVE_DAT_O_u(8) <= global_interrupt;
					when "00000100" => -- CR
						SLAVE_DAT_O_u(1 downto  0) <= '0' & reg_rst_app;
						SLAVE_DAT_O_u(8) <= global_interrupt_IE;
						SLAVE_DAT_O_u(12) <= clk_done_IE;
					when "00001010" => -- CLKDIV
						SLAVE_DAT_O_u(9 downto 0) <= reg_clk_div;
					when "00001011" => -- CLKCNT
						SLAVE_DAT_O_u(23 downto 0) <= clk_cycle_counter_remainder;
					when "00001100" => -- CONFIG
						SLAVE_DAT_O_u <= vFPGA_config_in;
					when "00001101" => -- SNAPIN
						SLAVE_DAT_O_u <= vFPGA_snap_in;
					when "00001110" => -- SNAPOUT
						SLAVE_DAT_O_u <= vFPGA_snap_out;
					when others =>
						null;
				end case;
			end if;
		end if;
	end process;


	-- Write control register --
	process(CLK_I_u)
	begin
		if rising_edge(CLK_I_u) then
			if RST_I_u = '1' then
				reg_rst_app <= '1';
				global_interrupt_IE <= '0';
				clk_done_IE <= '0';
			elsif (SLAVE_CYC_I_u = '1') and (SLAVE_STB_I_u = '1') and (SLAVE_WE_I_u = '1') and (SLAVE_ADR_I_u = "00000100") then
				reg_rst_app <= SLAVE_DAT_I_u(0);
				global_interrupt_IE <= SLAVE_DAT_I_u(8);
				clk_done_IE <= SLAVE_DAT_I_u(12);
			end if;
		end if;
	end process;


	-- Snap save --
	process(CLK_I_u)
	begin
		if rising_edge(CLK_I_u) then
			old_write_snap_save  <= write_snap_save;
			vFPGA_snap_save <= write_snap_save and not (old_write_snap_save);
			if RST_I_u = '1' then
				write_snap_save <= '0';
			elsif (SLAVE_CYC_I_u = '1') and (SLAVE_STB_I_u = '1') and (SLAVE_WE_I_u = '1') and (SLAVE_ADR_I_u = "00000100") and (SLAVE_SEL_I_u(0) = '1') and (SLAVE_DAT_I_u(2) = '1') then
				write_snap_save <= '1';
			else
				write_snap_save <= '0';
			end if;
		end if;
	end process;


	-- Snap restore --
	process(CLK_I_u)
	begin
		if rising_edge(CLK_I_u) then
			old_write_snap_restore <= write_snap_restore;
			vFPGA_snap_restore <= write_snap_restore and not (old_write_snap_restore);
			if RST_I_u = '1' then
				write_snap_restore <= '0';
			elsif (SLAVE_CYC_I_u = '1') and (SLAVE_STB_I_u = '1') and (SLAVE_WE_I_u = '1') and (SLAVE_ADR_I_u = "00000100") and (SLAVE_SEL_I_u(0) = '1') and (SLAVE_DAT_I_u(3) = '1') then
				write_snap_restore <= '1';
			else
				write_snap_restore <= '0';
			end if;
		end if;
	end process;


	-- Write vclk divisor --
	process(CLK_I_u)
	begin
		if rising_edge(CLK_I_u) then
			if RST_I_u = '1' then
				reg_clk_div <= (others => '1');
			elsif (SLAVE_CYC_I_u = '1') and (SLAVE_STB_I_u = '1') and (SLAVE_WE_I_u = '1') and (SLAVE_ADR_I_u = "00001010") then
				reg_clk_div <= SLAVE_DAT_I_u(9 downto 0);
			end if;
		end if;
	end process;


	-- Write vclk cycle counter --
	process(CLK_I_u)
	begin
		if rising_edge(CLK_I_u) then
			old_write_clkcnt <= write_clkcnt;
			clk_cycle_counter_valid <= write_clkcnt and not(old_write_clkcnt);
			if RST_I_u = '1' then
				reg_clk_cycle_counter <= (others => '0');
				write_clkcnt <= '0';
			elsif (SLAVE_CYC_I_u = '1') and (SLAVE_STB_I_u = '1') and (SLAVE_WE_I_u = '1') and (SLAVE_ADR_I_u = "00001011") then
				reg_clk_cycle_counter <= SLAVE_DAT_I_u(23 downto 0);
				write_clkcnt <= '1';
			else
				write_clkcnt <= '0';
			end if;
		end if;
	end process;


	-- Write vFPGA config word --
	process(CLK_I_u)
	begin
		if rising_edge(CLK_I_u) then
			old_write_config <= write_config;
			vFPGA_config_valid <= write_config and not(old_write_config);
			if RST_I_u = '1' then
				vFPGA_config_in <= (others => '0');
				write_config <= '0';
			elsif (SLAVE_CYC_I_u = '1') and (SLAVE_STB_I_u = '1') and (SLAVE_WE_I_u = '1') and (SLAVE_ADR_I_u = "00001100") then
				vFPGA_config_in <= SLAVE_DAT_I_u;
				write_config <= '1';
			else
				write_config <= '0';
			end if;
		end if;
	end process;


	-- Write vFPGA snapshot word --
	process(CLK_I_u)
	begin
		if rising_edge(CLK_I_u) then
			old_write_snap_in <= write_snap_in;
			if RST_I_u = '1' then
				vFPGA_snap_in <= (others => '0');
				write_snap_in <= '0';
			elsif (SLAVE_CYC_I_u = '1') and (SLAVE_STB_I_u = '1') and (SLAVE_WE_I_u = '1') and (SLAVE_ADR_I_u = "00001101") then
				vFPGA_snap_in <= SLAVE_DAT_I_u;
				write_snap_in <= '1';
			else
				write_snap_in <= '0';
			end if;
		end if;
	end process;


	-- Read vFPGA snapshot word --
	process(CLK_I_u)
	begin
		if rising_edge(CLK_I_u) then
			old_read_snap_out <= read_snap_out;
			if RST_I_u = '1' then
				read_snap_out <= '0';
			elsif (SLAVE_CYC_I_u = '1') and (SLAVE_STB_I_u = '1') and (SLAVE_WE_I_u = '0') and (SLAVE_ADR_I_u = "00001110") then
				read_snap_out <= '1';
			else
				read_snap_out <= '0';
			end if;
		end if;
	end process;


	-- Shift snapshot when writting snapin and after reading snapout --
	process(CLK_I_u)
	begin
		if rising_edge(CLK_I_u) then
			vFPGA_snap_shift <= (write_snap_in and not(old_write_snap_in)) or (not(read_snap_out) and old_read_snap_out);
		end if;
	end process;


	vFPGA_inputs <= std_ulogic_vector(INPUTS);
	OUTPUTS <= std_logic_vector(vFPGA_outputs);














	process(CLK_I_u)
	begin
		if rising_edge(CLK_I_u) then
			if (RST_I_u = '0') and (SLAVE_CYC_I_u = '1') and (SLAVE_STB_I_u = '1') and (SLAVE_ACK_O_u = '0') then
				SLAVE_ACK_O_u <= '1';
			else 
				SLAVE_ACK_O_u <= '0';
			end if;
		end if;
	end process;

end Behavioral;
