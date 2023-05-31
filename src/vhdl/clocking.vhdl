library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use IEEE.numeric_std.ALL;

library unisim;
use unisim.vcomponents.all;

entity clocking is
   port (
      -- Clock in ports
      clk_in     : in  std_logic;
      
      -- Clock out ports
      clock27    : out std_logic;
      clock41    : out std_logic;
      clock50    : out std_logic;
      clock74p22 : out std_logic;
      clock81p   : out std_logic;
      clock163   : out std_logic;
      clock163m  : out std_logic;
      clock200   : out std_logic;
      clock270   : out std_logic;
      clock325   : out std_logic
   );
end entity;


architecture RTL of clocking is

  signal clk_fb     : std_logic := '0';
  signal clk_fb_sdram       : std_logic := '0';
  signal clk_fb_adjust0     : std_logic := '0';
  signal clk_fb_adjust1     : std_logic := '0';
  signal clk_fb_adjust2     : std_logic := '0';
  signal clk_fb_eth : std_logic := '0';
  signal clock69mhz : std_logic := '0';
  signal u_clock69mhz : std_logic := '0';
  signal u_clock74p22mhz : std_logic := '0';
  signal clock124mhz : std_logic := '0';
  signal u_clock124mhz : std_logic := '0';
  signal clock9969mhz : std_logic := '0'; 
  signal u_clock9969mhz : std_logic := '0'; 

  signal u_clock27 : std_logic := '0';
  signal u_clock41 : std_logic := '0';
  signal u_clock50 : std_logic := '0';
  signal u_clock81p : std_logic := '0';
  signal u_clock163 : std_logic := '0';
  signal u_clock163m : std_logic := '0';
  signal u_clock200 : std_logic := '0';
  signal u_clock270 : std_logic := '0';
  signal u_clock325 : std_logic := '0';
  
begin

  -- We want 27MHz pixel clock.  From 100MHz, we will get 27.0833333 MHz
  -- But if we do the following, we can get exactly 27MHz:
  -- 4.000/5.000 x 9.000/5.000 x 9.000/13.000
  -- But that goes out of range for the intermediate frequency, so we instead use:
  -- 9.000/13.000 x 9.000/5.000 x 4.000/5.000

  adjust0 : MMCM_ADV
  generic map
   (BANDWIDTH            => "HIGH",
    CLKOUT4_CASCADE      => FALSE,
    CLOCK_HOLD           => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- Create 800 MHz 
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 9.0,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = CLK_OUT1 = 900/12.125 = 74.22MHz = clock74p22mhz
    CLKOUT0_DIVIDE_F     => 12.125,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE,

    -- CLKOUT1 = CLK_OUT1 = 900/13 = 69.23MHz = clock69mhz
    CLKOUT1_DIVIDE     => 13,
    CLKOUT1_PHASE        => 0.000,
    CLKOUT1_DUTY_CYCLE   => 0.500,
    CLKOUT1_USE_FINE_PS  => FALSE

    )

  port map
    -- Output clocks
   (
     CLKFBOUT            => clk_fb_adjust0,
     CLKOUT0             => u_clock74p22mhz,
     CLKOUT1             => u_clock69mhz,
     -- Input clock control
     CLKFBIN             => clk_fb_adjust0,
     CLKIN1              => clk_in,
     CLKIN2              => '0',
     -- Tied to always select the primary input clock
     CLKINSEL            => '1',
     -- Ports for dynamic reconfiguration
     DADDR               => (others => '0'),
     DCLK                => '0',
     DEN                 => '0',
     DI                  => (others => '0'),
     DWE                 => '0',
     -- Ports for dynamic phase shift
     PSCLK               => '0',
     PSEN                => '0',
     PSINCDEC            => '0',
     -- Other control and status signals
     PWRDWN              => '0',
     RST                 => '0');

  adjust1 : MMCM_ADV
  generic map
   (BANDWIDTH            => "HIGH",
    CLKOUT4_CASCADE      => FALSE,
    CLOCK_HOLD           => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- Create 800 MHz 
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 9.0,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = CLK_OUT1 = 69.23MHz x 9/5 = 124.61MHz = clock124mhz
    CLKOUT0_DIVIDE_F     => 5.0,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE
    )

  port map
    -- Output clocks
   (
     CLKFBOUT            => clk_fb_adjust1,
     CLKOUT0             => u_clock124mhz,
     -- Input clock control
     CLKFBIN             => clk_fb_adjust1,
     CLKIN1              => clock69mhz,
     CLKIN2              => '0',
     -- Tied to always select the primary input clock
     CLKINSEL            => '1',
     -- Ports for dynamic reconfiguration
     DADDR               => (others => '0'),
     DCLK                => '0',
     DEN                 => '0',
     DI                  => (others => '0'),
     DWE                 => '0',
     -- Ports for dynamic phase shift
     PSCLK               => '0',
     PSEN                => '0',
     PSINCDEC            => '0',
     -- Other control and status signals
     PWRDWN              => '0',
     RST                 => '0');
    

    adjust2 : MMCM_ADV
  generic map
   (BANDWIDTH            => "HIGH",
    CLKOUT4_CASCADE      => FALSE,
    CLOCK_HOLD           => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- Create 800 MHz 
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 8.0,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = CLK_OUT1 = 124MHz x 8/10 = 99.692307692MHz = clock9969mhz
    CLKOUT0_DIVIDE_F     => 10.0,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE
    )

  port map
    -- Output clocks
   (
     CLKFBOUT            => clk_fb_adjust2,
     CLKOUT0             => u_clock9969mhz,
     -- Input clock control
     CLKFBIN             => clk_fb_adjust2,
     CLKIN1              => clock124mhz,
     CLKIN2              => '0',
     -- Tied to always select the primary input clock
     CLKINSEL            => '1',
     -- Ports for dynamic reconfiguration
     DADDR               => (others => '0'),
     DCLK                => '0',
     DEN                 => '0',
     DI                  => (others => '0'),
     DWE                 => '0',
     -- Ports for dynamic phase shift
     PSCLK               => '0',
     PSEN                => '0',
     PSINCDEC            => '0',
     -- Other control and status signals
     PWRDWN              => '0',
     RST                 => '0');
    

  bufg_inter_connect69:
  bufg port map ( I => u_clock69mhz,
                  O => clock69mhz);

  bufg_inter_connect74p22:
  bufg port map ( I => u_clock74p22mhz,
                  O => clock74p22);  
  
  bufg_inter_connect124:
  bufg port map ( I => u_clock124mhz,
                  O => clock124mhz);  

  bufg_inter_connect:
  bufg port map ( I => u_clock9969mhz,
                  O => clock9969mhz);  
  
  bufg27:
  bufg port map ( I => u_clock27,
                  O => clock27);  

  bufg41:
  bufg port map ( I => u_clock41,
                  O => clock41);  
  
  bufg50:
  bufg port map ( I => u_clock50,
                  O => clock50);  

  bufg81:
  bufg port map ( I => u_clock81p,
                  O => clock81p);  
  
  bufg163:
  bufg port map ( I => u_clock163,
                  O => clock163);  

  bufg163m:
  bufg port map ( I => u_clock163m,
                  O => clock163m);  

  bufg200:
  bufg port map ( I => u_clock200,
                  O => clock200);  

  bufg270:
  bufg port map ( I => u_clock270,
                  O => clock270);  
  
  bufg325:
  bufg port map ( I => u_clock325,
                  O => clock325);  
  
  mmcm_adv0 : MMCM_ADV
  generic map
   (BANDWIDTH            => "HIGH",
    CLKOUT4_CASCADE      => FALSE,
    CLOCK_HOLD           => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- Create 812.5MHz clock from 8.125x100MHz/1
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 8.125,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = clock325 = 812.5MHz/2.5
    CLKOUT0_DIVIDE_F     => 2.50,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE,

    -- CLKOUT1 = clock135 = 812.5MHz/6
    CLKOUT1_DIVIDE       => 6,
    CLKOUT1_PHASE        => 0.000,
    CLKOUT1_DUTY_CYCLE   => 0.500,
    CLKOUT1_USE_FINE_PS  => FALSE,

    -- CLKOUT2 = clock81 = 812.5MHz/10
    CLKOUT2_DIVIDE       => 10,
    CLKOUT2_PHASE        => 0.000,
    CLKOUT2_DUTY_CYCLE   => 0.500,
    CLKOUT2_USE_FINE_PS  => FALSE,

    -- CLKOUT3 = clock41 = 812.5MHz/20
    CLKOUT3_DIVIDE       => 20,
    CLKOUT3_PHASE        => 0.000,
    CLKOUT3_DUTY_CYCLE   => 0.500,
    CLKOUT3_USE_FINE_PS  => FALSE,

    -- CLKOUT4 = clock27 = 812.5MHz/30 = 27.083
    CLKOUT4_DIVIDE       => 30,
    CLKOUT4_PHASE        => 0.000,
    CLKOUT4_DUTY_CYCLE   => 0.500,
    CLKOUT4_USE_FINE_PS  => FALSE,
    
    -- CLKOUT5 = clock163 = 812.5MHz/5 = 162.5 MHz
    CLKOUT5_DIVIDE       => 5,
    CLKOUT5_PHASE        => 0.0,
    CLKOUT5_DUTY_CYCLE   => 0.500,
    CLKOUT5_USE_FINE_PS  => FALSE,

    -- CLKOUT6 = clock270 = 270MHz
    CLKOUT6_DIVIDE       => 3,
    CLKOUT6_PHASE        => 0.000,
    CLKOUT6_DUTY_CYCLE   => 0.500,
    CLKOUT6_USE_FINE_PS  => FALSE,
    
    CLKIN1_PERIOD        => 10.000,
    REF_JITTER1          => 0.010)
  port map
    -- Output clocks
   (CLKFBOUT            => clk_fb,
    CLKOUT0             => u_clock325,
    CLKOUT2             => u_clock81p,
    CLKOUT3             => u_clock41,
    CLKOUT4             => u_clock27,
    CLKOUT5             => u_clock163,
    CLKOUT6             => u_clock270,
    -- Input clock control
    CLKFBIN             => clk_fb,
    CLKIN1              => clock9969mhz,
    CLKIN2              => '0',
    -- Tied to always select the primary input clock
    CLKINSEL            => '1',
    -- Ports for dynamic reconfiguration
    DADDR               => (others => '0'),
    DCLK                => '0',
    DEN                 => '0',
    DI                  => (others => '0'),
    DWE                 => '0',
    -- Ports for dynamic phase shift
    PSCLK               => '0',
    PSEN                => '0',
    PSINCDEC            => '0',
    -- Other control and status signals
    PWRDWN              => '0',
    RST                 => '0');
  
  mmcm_adv0sdram : MMCM_ADV
  generic map
   (BANDWIDTH            => "HIGH",
    CLKOUT4_CASCADE      => FALSE,
    CLOCK_HOLD           => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- Create 812.5MHz clock from 8.125x100MHz/1
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 8.125,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = clock325 = 812.5MHz/2.5
    CLKOUT0_DIVIDE_F     => 2.50,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE,

    -- CLKOUT1 = clock135 = 812.5MHz/6
    CLKOUT1_DIVIDE       => 6,
    CLKOUT1_PHASE        => 0.000,
    CLKOUT1_DUTY_CYCLE   => 0.500,
    CLKOUT1_USE_FINE_PS  => FALSE,

    -- CLKOUT2 = clock81 = 812.5MHz/10
    CLKOUT2_DIVIDE       => 10,
    CLKOUT2_PHASE        => 0.000,
    CLKOUT2_DUTY_CYCLE   => 0.500,
    CLKOUT2_USE_FINE_PS  => FALSE,

    -- CLKOUT3 = clock41 = 812.5MHz/20
    CLKOUT3_DIVIDE       => 20,
    CLKOUT3_PHASE        => 0.000,
    CLKOUT3_DUTY_CYCLE   => 0.500,
    CLKOUT3_USE_FINE_PS  => FALSE,

    -- CLKOUT4 = clock27 = 812.5MHz/30 = 27.083
    CLKOUT4_DIVIDE       => 30,
    CLKOUT4_PHASE        => 0.000,
    CLKOUT4_DUTY_CYCLE   => 0.500,
    CLKOUT4_USE_FINE_PS  => FALSE,
    
    -- CLKOUT5 = clock163 = 812.5MHz/5 = 162.5 MHz
    -- Phase adjusted by 180 degrees
    CLKOUT5_DIVIDE       => 5,
    CLKOUT5_PHASE        => 180.0,
    CLKOUT5_DUTY_CYCLE   => 0.500,
    CLKOUT5_USE_FINE_PS  => FALSE,

    -- CLKOUT6 = clock270 = 270MHz
    CLKOUT6_DIVIDE       => 3,
    CLKOUT6_PHASE        => 0.000,
    CLKOUT6_DUTY_CYCLE   => 0.500,
    CLKOUT6_USE_FINE_PS  => FALSE,
    
    CLKIN1_PERIOD        => 10.000,
    REF_JITTER1          => 0.010)
  port map
    -- Output clocks
   (CLKFBOUT            => clk_fb_sdram,
    CLKOUT5             => u_clock163m,
    -- Input clock control
    CLKFBIN             => clk_fb_sdram,
    CLKIN1              => clock9969mhz,
    CLKIN2              => '0',
    -- Tied to always select the primary input clock
    CLKINSEL            => '1',
    -- Ports for dynamic reconfiguration
    DADDR               => (others => '0'),
    DCLK                => '0',
    DEN                 => '0',
    DI                  => (others => '0'),
    DWE                 => '0',
    -- Ports for dynamic phase shift
    PSCLK               => '0',
    PSEN                => '0',
    PSINCDEC            => '0',
    -- Other control and status signals
    PWRDWN              => '0',
    RST                 => '0');
  


  mmcm_adv1_eth : MMCM_ADV
  generic map
   (BANDWIDTH            => "HIGH",
    CLKOUT4_CASCADE      => FALSE,
    CLOCK_HOLD           => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- Create 800.0MHz clock from 8.000x100MHz/1
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 8.000,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = CLK_OUT1 = clock100 = 800MHz/8.0
    CLKOUT0_DIVIDE_F     => 8.0,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE,

    -- CLKOUT1 = CLK_OUT2 = clock50 = 800MHz/16
    CLKOUT1_DIVIDE       => 16,
    CLKOUT1_PHASE        => 0.000,
    CLKOUT1_DUTY_CYCLE   => 0.500,
    CLKOUT1_USE_FINE_PS  => FALSE,

    -- CLKOUT2 = CLK_OUT3 = clock200 = 800MHz/4
    CLKOUT2_DIVIDE       => 4,
    CLKOUT2_PHASE        => 0.000,
    CLKOUT2_DUTY_CYCLE   => 0.500,
    CLKOUT2_USE_FINE_PS  => FALSE,
    
    -- CLKOUT3 = CLK_OUT4 = clock50q = 800MHz/16 = 50MHz, and rotated 45 degrees
    CLKOUT3_DIVIDE       => 16,
    CLKOUT3_PHASE        => 45.000,
    CLKOUT3_DUTY_CYCLE   => 0.500,
    CLKOUT3_USE_FINE_PS  => FALSE,

    -- CLKOUT4 = UNUSED
    CLKOUT4_DIVIDE       => 10,
    CLKOUT4_PHASE        => 0.000,
    CLKOUT4_DUTY_CYCLE   => 0.500,
    CLKOUT4_USE_FINE_PS  => FALSE,

    -- CLKOUT5 = UNUSED
    CLKOUT5_DIVIDE       => 5,
    CLKOUT5_PHASE        => 0.0,
    CLKOUT5_DUTY_CYCLE   => 0.500,
    CLKOUT5_USE_FINE_PS  => FALSE,

    -- CLKOUT6 = UNUSED
    CLKOUT6_DIVIDE       => 5,
    CLKOUT6_PHASE        => 0.000,
    CLKOUT6_DUTY_CYCLE   => 0.500,
    CLKOUT6_USE_FINE_PS  => FALSE,
    CLKIN1_PERIOD        => 10.000,
    REF_JITTER1          => 0.010)
  port map
    -- Output clocks
    (
    CLKFBOUT            => clk_fb_eth,
    CLKOUT1             => u_clock50,
    CLKOUT2             => u_clock200,
--    CLKOUT3             => u_clock50q,
    -- Input clock control
    CLKFBIN             => clk_fb_eth,
    CLKIN1              => clk_in,
    CLKIN2              => '0',
    -- Tied to always select the primary input clock
    CLKINSEL            => '1',
    -- Ports for dynamic reconfiguration
    DADDR               => (others => '0'),
    DCLK                => '0',
    DEN                 => '0',
    DI                  => (others => '0'),
    DWE                 => '0',
    -- Ports for dynamic phase shift
    PSCLK               => '0',
    PSEN                => '0',
    PSINCDEC            => '0',
    -- Other control and status signals
    PWRDWN              => '0',
    RST                 => '0');

  

  
end rtl;
