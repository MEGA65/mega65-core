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
   COMPONENT i2c_sender
   PORT(
      clk    : IN std_logic;
      resend : IN std_logic;    
      siod   : INOUT std_logic;      
      sioc   : OUT std_logic
   );
   END COMPONENT;

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

   signal counter : integer := 0;
   signal resend : std_logic := '1';      
            
                                      
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


-----------------------------------------------------------------------   
-- This sends the configuration register values to the HDMI transmitter
-----------------------------------------------------------------------   
i_i2c_sender: i2c_sender PORT MAP(
      clk => clk,
      resend => resend,
      sioc => hdmi_scl,
      siod => hdmi_sda
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

   hdmi_clk <= clk;
       
clk_proc: process(clK)
   begin
      if rising_edge(clk) then

         if counter < 100000000 then
           counter <= counter + 1;
           resend <= '0';
         else
           counter <= 0;
           resend <= '1';
         end if;
                                  
         vga_r  <= pattern_r(7 downto 0);
         vga_g  <= pattern_g(7 downto 0);
         vga_b  <= pattern_b(7 downto 0);

         hdmi_d(7 downto 0)  <= pattern_r;
         hdmi_d(15 downto 8)  <= pattern_g;
         hdmi_d(23 downto 16)  <= pattern_b;

         hdmi_de    <= pattern_de;
         hdmi_hsync <= pattern_hsync;
         hdmi_vsync <= pattern_vsync;
                              
         vga_hs <= pattern_hsync;
         vga_vs <= pattern_vsync;
      end if;
   end process;
end Behavioral;

