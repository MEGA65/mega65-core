library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use IEEE.numeric_std.ALL;

library unisim;
use unisim.vcomponents.all;

entity clocking50mhz is
   port (
      -- Clock in ports
      clk_in     : in  std_logic;
      
      -- Clock out ports
      clock27    : out std_logic;
      clock41    : out std_logic;
      clock50    : out std_logic;
      clock81p   : out std_logic;
      clock81n   : out std_logic;
      clock100   : out std_logic;
      clock135p  : out std_logic;
      clock135n  : out std_logic;
      clock270   : out std_logic;
      clock162   : out std_logic;
      clock200   : out std_logic;
      clock324   : out std_logic
   );
end entity;


architecture RTL of clocking50mhz is

  signal clk_fb     : std_logic := '0';
  signal clk_fb_adjust0     : std_logic := '0';
  signal clk_fb_eth : std_logic := '0';
  signal clock10125mhz : std_logic := '0';
  
begin

  -- We want 27MHz true pixel clock and various multiples
  -- from out 50 or 100MHz input clock.
  -- We can use the MMCME2_ADV improved clock fiddling factors
  -- to easily get this.
  -- 50 MHz x 20.250 / 10 = 506.25MHz / 5 = 101.25 MHz
  -- 101.25MHz x 8 = 810MHz
  -- 324MHz = 810 / 2.5
  -- 162MHz = 810 / 5
  -- 81MHz = 810 / 10
  -- 40.5MHz = 810 / 20
  -- 27MHz = 810 / 30
  -- So we need only 2 MMCME2_ADV's to achieve this

  adjust0 : MMCME2_ADV
  generic map
   (BANDWIDTH            => "OPTIMIZED",
    CLKOUT4_CASCADE      => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    CLKIN1_PERIOD => 20.000,
    
    -- Create 506.25 MHz 
    DIVCLK_DIVIDE        => 1,
    -- For 100MHz input clock use 10.125 here instead of 20.250
    CLKFBOUT_MULT_F      => 20.250,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = CLK_OUT1 = 506.25MHz/5 = 101.25MHz = clock10125mhz
    CLKOUT0_DIVIDE_F     => 10.00,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE
    )

  port map
    -- Output clocks
   (
     CLKFBOUT            => clk_fb_adjust0,
     CLKOUT0             => clock10125mhz,
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

  mmcm_adv0 : MMCME2_ADV
  generic map
   (BANDWIDTH            => "OPTIMIZED",
    CLKOUT4_CASCADE      => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- Create 810MHz clock from 101.25MHz x 8 / 
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 8.000,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = CLK_OUT1 = clock324 = 810MHz/2.5
    CLKOUT0_DIVIDE_F     => 2.50,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE,

    -- CLKOUT1 = CLK_OUT2 = clock135 ~= 810MHz/6
    CLKOUT1_DIVIDE       => 6,
    CLKOUT1_PHASE        => 0.000,
    CLKOUT1_DUTY_CYCLE   => 0.500,
    CLKOUT1_USE_FINE_PS  => FALSE,

    -- CLKOUT2 = CLK_OUT3 = clock81 ~= 810MHz/10
    CLKOUT2_DIVIDE       => 10,
    CLKOUT2_PHASE        => 0.000,
    CLKOUT2_DUTY_CYCLE   => 0.500,
    CLKOUT2_USE_FINE_PS  => FALSE,

    -- CLKOUT3 = CLK_OUT4 = clock41 ~= 810MHz/20
    CLKOUT3_DIVIDE       => 20,
    CLKOUT3_PHASE        => 0.000,
    CLKOUT3_DUTY_CYCLE   => 0.500,
    CLKOUT3_USE_FINE_PS  => FALSE,

    -- CLKOUT4 = CLK_OUT5 = clock27 = 810MHz/30 = 27
    CLKOUT4_DIVIDE       => 30,
    CLKOUT4_PHASE        => 0.000,
    CLKOUT4_DUTY_CYCLE   => 0.500,
    CLKOUT4_USE_FINE_PS  => FALSE,
    
    -- CLKOUT5 = CLK_OUT6 = clock162 - 810MHz/5
    CLKOUT5_DIVIDE       => 5,
    CLKOUT5_PHASE        => 0.0,
    CLKOUT5_DUTY_CYCLE   => 0.500,
    CLKOUT5_USE_FINE_PS  => FALSE,

    -- CLKOUT6 = clock270 = 270MHz
    CLKOUT6_DIVIDE       => 3,
    CLKOUT6_PHASE        => 0.000,
    CLKOUT6_DUTY_CYCLE   => 0.500,
    CLKOUT6_USE_FINE_PS  => FALSE,

    REF_JITTER1          => 0.010)
  port map
    -- Output clocks
   (CLKFBOUT            => clk_fb,
    CLKOUT0             => clock324,
    CLKOUT1             => clock135p,
    CLKOUT1B            => clock135n,
    CLKOUT2             => clock81p,
    CLKOUT2B            => clock81n,
    CLKOUT3             => clock41,
    CLKOUT4             => clock27,
    CLKOUT5             => clock162,
    CLKOUT6             => clock270,
    -- Input clock control
    CLKFBIN             => clk_fb,
    CLKIN1              => clock10125mhz,
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
  
  mmcm_adv1_eth : MMCME2_ADV
  generic map
   (BANDWIDTH            => "OPTIMIZED",
    CLKOUT4_CASCADE      => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- Create 800.0MHz clock from 16.000x50MHz/1
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 16.000,
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

    -- CLKOUT2 = CLKOUT3 = clock200 = 800MHz/4
    CLKOUT2_DIVIDE       => 4,
    CLKOUT2_PHASE        => 0.000,
    CLKOUT2_DUTY_CYCLE   => 0.500,
    CLKOUT2_USE_FINE_PS  => FALSE,
    
    -- CLKOUT3 = UNUSED
    CLKOUT3_DIVIDE       => 20,
    CLKOUT3_PHASE        => 0.000,
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
    CLKOUT0             => clock100,
    CLKOUT1             => clock50,
    CLKOUT2             => clock200,
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
