----------------------------------------------------------------------------------
-- Engineer:    Mike Field <hamster@snap.net.nz> 
-- Module Name: vga_hdmi - Behavioral 
-- 
-- Description: A test of the Zedboard's VGA & HDMI interface
--
-- Feel free to use this how you see fit, and fix any errors you find :-)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VComponents.all;

entity vga_hdmi is
    Port ( clk_100       : in  STD_LOGIC;
    
           vga_r         : out  STD_LOGIC_VECTOR (7 downto 0);
           vga_g         : out  STD_LOGIC_VECTOR (7 downto 0);
           vga_b         : out  STD_LOGIC_VECTOR (7 downto 0);
           vga_hs        : out  STD_LOGIC;
           vga_vs        : out  STD_LOGIC;
           
           hdmi_clk      : out  STD_LOGIC;
           hdmi_hsync    : out  STD_LOGIC;
           hdmi_vsync    : out  STD_LOGIC;
           hdmi_d        : out  STD_LOGIC_VECTOR (23 downto 0);
           hdmi_de       : out  STD_LOGIC;
           hdmi_scl      : out  STD_LOGIC;
           hdmi_sda      : inout  STD_LOGIC);
end vga_hdmi;

architecture Behavioral of vga_hdmi is
   COMPONENT vga_generator
	PORT(
		clk : IN std_logic;          
		r : OUT std_logic_vector(7 downto 0);
		g : OUT std_logic_vector(7 downto 0);
		b : OUT std_logic_vector(7 downto 0);
		de : OUT std_logic;
		vsync : OUT std_logic;
		hsync : OUT std_logic
		);
	END COMPONENT;

	COMPONENT convert_444_422
	PORT( clk      : IN std_logic;
		   r_in     : IN std_logic_vector(7 downto 0);
			g_in     : IN std_logic_vector(7 downto 0);
         b_in     : IN std_logic_vector(7 downto 0);
         hsync_in : IN std_logic;
         vsync_in : IN std_logic;
         de_in    : IN std_logic;
      
         r1_out    : OUT std_logic_vector(8 downto 0);
         g1_out    : OUT std_logic_vector(8 downto 0);
         b1_out    : OUT std_logic_vector(8 downto 0);
         r2_out    : OUT std_logic_vector(8 downto 0);
         g2_out    : OUT std_logic_vector(8 downto 0);
         b2_out    : OUT std_logic_vector(8 downto 0);
         pair_start_out: OUT std_logic;
         hsync_out : OUT std_logic;
         vsync_out : OUT std_logic;
         de_out    : OUT std_logic
		);
	END COMPONENT;

   COMPONENT colour_space_conversion
   PORT( clk       : IN std_logic;          
      
         r1_in        : IN std_logic_vector(8 downto 0);
         g1_in        : IN std_logic_vector(8 downto 0);
         b1_in        : IN std_logic_vector(8 downto 0);
         r2_in        : IN std_logic_vector(8 downto 0);
         g2_in        : IN std_logic_vector(8 downto 0);
         b2_in        : IN std_logic_vector(8 downto 0);
         pair_start_in: IN std_logic;
         de_in        : IN std_logic;
         vsync_in     : IN std_logic;
         hsync_in     : IN std_logic;
         
         y_out     : OUT std_logic_vector(7 downto 0);
         c_out     : OUT std_logic_vector(7 downto 0);
         de_out    : OUT std_logic;
         hsync_out : OUT std_logic;
         vsync_out : OUT std_logic
      );
	END COMPONENT;

   COMPONENT clamper
	PORT(
		clk : IN std_logic;
		y_in : IN std_logic_vector(7 downto 0);
		c_in : IN std_logic_vector(7 downto 0);
		de_in : IN std_logic;
		hsync_in  : IN std_logic;
		vsync_in  : IN std_logic;          
		y_out     : OUT std_logic_vector(7 downto 0);
		c_out     : OUT std_logic_vector(7 downto 0);
		de_out    : OUT std_logic;
		hsync_out : OUT std_logic;
		vsync_out : OUT std_logic
		);
	END COMPONENT;

	COMPONENT hdmi_ddr_output
	PORT(
		clk        : IN std_logic;
		clk90      : IN std_logic;
		y          : IN std_logic_vector(7 downto 0);
		c          : IN std_logic_vector(7 downto 0);
		hsync_in   : IN std_logic;
		vsync_in   : IN std_logic;
		de_in      : IN std_logic;
		hdmi_sda   : INOUT std_logic;      
		hdmi_clk   : OUT std_logic;
		hdmi_hsync : OUT std_logic;
		hdmi_vsync : OUT std_logic;
		hdmi_d     : OUT std_logic_vector(15 downto 0);
		hdmi_de    : OUT std_logic;
		hdmi_scl   : OUT std_logic
		);
	END COMPONENT;
   
   -- Clocking
   signal clk    : std_logic;
   signal clk0   : std_logic;
   signal clk90  : std_logic;
   signal clkfb  : std_logic;
   
   -- Signals from the VGA generator
   signal pattern_r      : std_logic_vector(7 downto 0);
   signal pattern_g      : std_logic_vector(7 downto 0);
   signal pattern_b      : std_logic_vector(7 downto 0);
   signal pattern_hsync  : std_logic;
   signal pattern_vsync  : std_logic;
   signal pattern_de     : std_logic;

   -- Signals from the pixel pair convertor
   signal c422_r1    : std_logic_vector(8 downto 0);
   signal c422_g1    : std_logic_vector(8 downto 0);
   signal c422_b1    : std_logic_vector(8 downto 0);
   signal c422_r2    : std_logic_vector(8 downto 0);
   signal c422_g2    : std_logic_vector(8 downto 0);
   signal c422_b2    : std_logic_vector(8 downto 0);
   signal c422_pair_start : std_logic;
   signal c422_hsync : std_logic;
   signal c422_vsync : std_logic;
   signal c422_de    : std_logic;

   -- Signals from the colour space convertor
   signal csc_y      : std_logic_vector(7 downto 0);
   signal csc_c      : std_logic_vector(7 downto 0);
   signal csc_hsync  : std_logic;
   signal csc_vsync  : std_logic;
   signal csc_de     : std_logic;

   -- signals from the output range clampler
   signal clamper_c     : std_logic_vector(7 downto 0);
   signal clamper_y     : std_logic_vector(7 downto 0);
   signal clamper_hsync : std_logic;
   signal clamper_vsync : std_logic;
   signal clamper_de    : std_logic;

begin
i_vga_generator: vga_generator PORT MAP(
		clk   => clk,
		r     => pattern_r,
		g     => pattern_g,
		b     => pattern_b,
		de    => pattern_de,
		vsync => pattern_vsync,
		hsync => pattern_hsync
	);

i_convert_444_422: convert_444_422 PORT MAP(
		clk       => clk,
      
		r_in      => pattern_r,
		g_in      => pattern_g,
		b_in      => pattern_b,
		hsync_in  => pattern_hsync,
		vsync_in  => pattern_vsync,
		de_in     => pattern_de,
      
		r1_out    => c422_r1,
		g1_out    => c422_g1,
		b1_out    => c422_b1,
		r2_out    => c422_r2,
		g2_out    => c422_g2,
		b2_out    => c422_b2,
      pair_start_out => c422_pair_start,
		hsync_out => c422_hsync,
		vsync_out => c422_vsync,
		de_out    => c422_de
	);


i_csc: colour_space_conversion PORT MAP(
		clk      => clk,
		r1_in    => c422_r1,
		g1_in    => c422_g1,
		b1_in    => c422_b1,
		r2_in    => c422_r2,
		g2_in    => c422_g2,
		b2_in    => c422_b2,
      pair_start_in => c422_pair_start,
		vsync_in => c422_vsync,
		hsync_in => c422_hsync,
		de_in    => c422_de,

		y_out     => csc_y,
		c_out     => csc_c,
		hsync_out => csc_hsync,
		vsync_out => csc_vsync,
		de_out    => csc_de 
   );

------------------------------
-- bypass the range clamper - it is not needed
------------------------------
--i_clamper: clamper PORT MAP(
--		clk       => clk,
--		y_in      => csc_y,
--		c_in      => csc_c,
--		de_in     => csc_de,
--		hsync_in  => csc_hsync,
--		vsync_in  => csc_vsync,
--		y_out     => clamper_y,
--		c_out     => clamper_c,
--		de_out    => clamper_de,
--		hsync_out => clamper_hsync,
--		vsync_out => clamper_vsync
--	);
   clamper_y     <= csc_y;
	clamper_c     <= csc_c;
   clamper_de    <= csc_de;
   hdmi_de    <= csc_de;
   hdmi_hsync <= csc_hsync;
   hdmi_vsync <= csc_vsync;
   hdmi_clk <= clk;
                             

i_hdmi_ddr_output: hdmi_ddr_output PORT MAP(
		clk        => clk,
		clk90      => clk90,
		y          => clamper_y,
		c          => clamper_c,
		hsync_in   => clamper_hsync,
		vsync_in   => clamper_vsync,
		de_in      => clamper_de,
--		hdmi_clk   => hdmi_clk,
--		hdmi_hsync => hdmi_hsync,
--		hdmi_vsync => hdmi_vsync,
--		hdmi_d     => hdmi_d,
--		hdmi_de    => hdmi_de,
		hdmi_scl   => hdmi_scl,
		hdmi_sda   => hdmi_sda
	);
   
   -- Generate a 27MHz pixel clock and one with 90 degree phase shift from the 100MHz system clock.
   PLLE2_BASE_inst : PLLE2_BASE
   generic map (
      BANDWIDTH => "OPTIMIZED",  -- OPTIMIZED, HIGH, LOW
      CLKFBOUT_MULT  => 14,       -- Multiply value for all CLKOUT, (2-64)
      CLKFBOUT_PHASE => 0.0,     -- Phase offset in degrees of CLKFB, (-360.000-360.000).
      CLKIN1_PERIOD  => 10.0,    -- Input clock period in ns to ps resolution (i.e. 33.333 is 30 MHz).
      -- CLKOUT0_DIVIDE - CLKOUT5_DIVIDE: Divide amount for each CLKOUT (1-128)
      CLKOUT0_DIVIDE => 14,
      CLKOUT1_DIVIDE => 52,
      CLKOUT2_DIVIDE => 52,
      CLKOUT3_DIVIDE => 1,
      CLKOUT4_DIVIDE => 1,
      CLKOUT5_DIVIDE => 1,
      -- CLKOUT0_DUTY_CYCLE - CLKOUT5_DUTY_CYCLE: Duty cycle for each CLKOUT (0.001-0.999).
      CLKOUT0_DUTY_CYCLE => 0.5,
      CLKOUT1_DUTY_CYCLE => 0.5,
      CLKOUT2_DUTY_CYCLE => 0.5,
      CLKOUT3_DUTY_CYCLE => 0.5,
      CLKOUT4_DUTY_CYCLE => 0.5,
      CLKOUT5_DUTY_CYCLE => 0.5,
      -- CLKOUT0_PHASE - CLKOUT5_PHASE: Phase offset for each CLKOUT (-360.000-360.000).
      CLKOUT0_PHASE => 0.0,
      CLKOUT1_PHASE => 0.0,
      CLKOUT2_PHASE => 135.0,
      CLKOUT3_PHASE => 0.0,
      CLKOUT4_PHASE => 0.0,
      CLKOUT5_PHASE => 0.0,
      DIVCLK_DIVIDE => 1,        -- Master division value, (1-56)
      REF_JITTER1 => 0.0,        -- Reference input jitter in UI, (0.000-0.999).
      STARTUP_WAIT => "FALSE"    -- Delay DONE until PLL Locks, ("TRUE"/"FALSE")
   )
   port map (
      -- Clock Outputs: 1-bit (each) output: User configurable clock outputs
      CLKOUT0  => clk0,
      CLKOUT1  => clk,
      CLKOUT2  => clk90,
      CLKOUT3  => open,
      CLKOUT4  => open,
      CLKOUT5  => open,
      CLKFBOUT => clkfb,   -- 1-bit output: Feedback clock
      LOCKED   => open,    -- 1-bit output: LOCK
      CLKIN1   => clk_100, -- 1-bit input: Input clock
      PWRDWN   => '0',     -- 1-bit input: Power-down
      RST      => '0',     -- 1-bit input: Reset
      CLKFBIN  => clkfb    -- 1-bit input: Feedback clock
   );
clk_proc: process(clK)
   begin
      if rising_edge(clk) then
         vga_r  <= pattern_r(7 downto 0);
         vga_g  <= pattern_g(7 downto 0);
         vga_b  <= pattern_b(7 downto 0);

         hdmi_d(7 downto 0)  <= pattern_r;
         hdmi_d(15 downto 8)  <= pattern_g;
         hdmi_d(23 downto 16)  <= pattern_b;
                              
         vga_hs <= pattern_hsync;
         vga_vs <= pattern_vsync;
      end if;
   end process;
end Behavioral;

