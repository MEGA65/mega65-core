-- file: dotclock100.vhd
-- 
-- (c) Copyright 2008 - 2011 Xilinx, Inc. All rights reserved.
-- 
-- This file contains confidential and proprietary information
-- of Xilinx, Inc. and is protected under U.S. and
-- international copyright and other intellectual property
-- laws.
-- 
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- Xilinx, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) Xilinx shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or Xilinx had been advised of the
-- possibility of the same.
-- 
-- CRITICAL APPLICATIONS
-- Xilinx products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of Xilinx products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
-- 
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
-- 
------------------------------------------------------------------------------
-- User entered comments
------------------------------------------------------------------------------
-- None
--
------------------------------------------------------------------------------
-- "Output    Output      Phase     Duty      Pk-to-Pk        Phase"
-- "Clock    Freq (MHz) (degrees) Cycle (%) Jitter (ps)  Error (ps)"
------------------------------------------------------------------------------
-- CLK_OUT1___100.000______0.000______50.0______115.831_____87.180
-- CLK_OUT2___240.000______0.000______50.0______102.086_____87.180
-- CLK_OUT3____50.000______0.000______50.0______132.683_____87.180
-- CLK_OUT4___120.000______0.000______50.0______139.033_____87.180
-- CLK_OUT5____80.000______0.000______50.0______147.931_____87.180
-- CLK_OUT6____40.000______0.000______50.0______144.570_____87.180
-- CLK_OUT7___200.000______0.000______50.0______107.567_____87.180
--
------------------------------------------------------------------------------
-- "Input Clock   Freq (MHz)    Input Jitter (UI)"
------------------------------------------------------------------------------
-- __primary_________100.000____________0.010

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity dotclock100 is
port
 (-- Clock in ports
  CLK_IN1           : in     std_logic;
  -- Clock out ports
  clock100          : out    std_logic;
  clock162          : out    std_logic;
  clock50           : out    std_logic;
  clock41          : out    std_logic;
  clock81           : out    std_logic;
  clock27           : out    std_logic;
  clock54          : out    std_logic;
  -- Status and control signals
  LOCKED            : out    std_logic
 );
end dotclock100;

architecture xilinx of dotclock100 is
  attribute CORE_GENERATION_INFO : string;
  attribute CORE_GENERATION_INFO of xilinx : architecture is "dotclock100,clk_wiz_v3_6,{component_name=dotclock100,use_phase_alignment=true,use_min_o_jitter=false,use_max_i_jitter=false,use_dyn_phase_shift=false,use_inclk_switchover=false,use_dyn_reconfig=false,feedback_source=FDBK_AUTO,primtype_sel=MMCM_ADV,num_out_clk=7,clkin1_period=10.000,clkin2_period=10.000,use_power_down=false,use_reset=true,use_locked=true,use_inclk_stopped=false,use_status=false,use_freeze=false,use_clk_valid=false,feedback_type=SINGLE,clock_mgr_type=MANUAL,manual_override=false}";
  -- Input clock buffering / unused connectors
  signal clkin1      : std_logic;
  -- Output clock buffering / unused connectors
  signal clkfbout         : std_logic;
  signal clkfbout_buf     : std_logic;
  signal clkfboutb_unused : std_logic;
  signal clkout0          : std_logic;
  signal clkout0b_unused  : std_logic;
  signal clkout1          : std_logic;
  signal clkout1b_unused  : std_logic;
  signal clkout2          : std_logic;
  signal clkout2b_unused  : std_logic;
  signal clkout3          : std_logic;
  signal clkout3b_unused  : std_logic;
  signal clkout4          : std_logic;
  signal clkout5          : std_logic;
  signal clkout6          : std_logic;
  -- Dynamic programming unused signals
  signal do_unused        : std_logic_vector(15 downto 0);
  signal drdy_unused      : std_logic;
  -- Dynamic phase shift unused signals
  signal psdone_unused    : std_logic;
  -- Unused status signals
  signal clkfbstopped_unused : std_logic;
  signal clkinstopped_unused : std_logic;
begin


  -- Input buffering
  --------------------------------------
  clkin1_buf : IBUFG
  port map
   (O => clkin1,
    I => CLK_IN1);


  -- Clocking primitive
  --------------------------------------
  -- Instantiation of the MMCM primitive
  --    * Unused inputs are tied off
  --    * Unused outputs are labeled unused
  mmcm_adv_inst : MMCM_ADV
  generic map
   (BANDWIDTH            => "OPTIMIZED",
    CLKOUT4_CASCADE      => FALSE,
    CLOCK_HOLD           => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,
    -- Create 650MHz clock from 6.5x100MHz/1
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 6.500,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,
    -- CLKOUT0 = CLK_OUT1 = clock100 = 650MHz/6.5
    CLKOUT0_DIVIDE_F     => 6.500,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE,
    -- CLKOUT1 = CLK_OUT2 = clock162 ~= 650MHz/4
    CLKOUT1_DIVIDE       => 4,
    CLKOUT1_PHASE        => 0.000,
    CLKOUT1_DUTY_CYCLE   => 0.500,
    CLKOUT1_USE_FINE_PS  => FALSE,
    -- CLKOUT2 = CLK_OUT3 = clock50 = 650MHz/13
    CLKOUT2_DIVIDE       => 13,
    CLKOUT2_PHASE        => 0.000,
    CLKOUT2_DUTY_CYCLE   => 0.500,
    CLKOUT2_USE_FINE_PS  => FALSE,
    -- CLKOUT3 = CLK_OUT4 = clock41 = 650MHz/16
    CLKOUT3_DIVIDE       => 16,
    CLKOUT3_PHASE        => 0.000,
    CLKOUT3_DUTY_CYCLE   => 0.500,
    CLKOUT3_USE_FINE_PS  => FALSE,
    -- CLKOUT4 = CLK_OUT5 = clock81 - 650MHz/8
    CLKOUT4_DIVIDE       => 8,
    CLKOUT4_PHASE        => 0.000,
    CLKOUT4_DUTY_CYCLE   => 0.500,
    CLKOUT4_USE_FINE_PS  => FALSE,
    -- CLKOUT5 = CLK_OUT6 = clock200 - 650MHz/24
    CLKOUT5_DIVIDE       => 24,
    CLKOUT5_PHASE        => 0.000,
    CLKOUT5_DUTY_CYCLE   => 0.500,
    CLKOUT5_USE_FINE_PS  => FALSE,
    -- CLKOUT6 = CLK_OUT7 = clock54 - 650MHZ/12
    CLKOUT6_DIVIDE       => 12,
    CLKOUT6_PHASE        => 0.000,
    CLKOUT6_DUTY_CYCLE   => 0.500,
    CLKOUT6_USE_FINE_PS  => FALSE,
    CLKIN1_PERIOD        => 10.000,
    REF_JITTER1          => 0.010)
  port map
    -- Output clocks
   (CLKFBOUT            => clkfbout,
    CLKFBOUTB           => clkfboutb_unused,
    CLKOUT0             => clkout0,
    CLKOUT0B            => clkout0b_unused,
    CLKOUT1             => clkout1,
    CLKOUT1B            => clkout1b_unused,
    CLKOUT2             => clkout2,
    CLKOUT2B            => clkout2b_unused,
    CLKOUT3             => clkout3,
    CLKOUT3B            => clkout3b_unused,
    CLKOUT4             => clkout4,
    CLKOUT5             => clkout5,
    CLKOUT6             => clkout6,
    -- Input clock control
    CLKFBIN             => clkfbout_buf,
    CLKIN1              => clkin1,
    CLKIN2              => '0',
    -- Tied to always select the primary input clock
    CLKINSEL            => '1',
    -- Ports for dynamic reconfiguration
    DADDR               => (others => '0'),
    DCLK                => '0',
    DEN                 => '0',
    DI                  => (others => '0'),
    DO                  => do_unused,
    DRDY                => drdy_unused,
    DWE                 => '0',
    -- Ports for dynamic phase shift
    PSCLK               => '0',
    PSEN                => '0',
    PSINCDEC            => '0',
    PSDONE              => psdone_unused,
    -- Other control and status signals
    LOCKED              => LOCKED,
    CLKINSTOPPED        => clkinstopped_unused,
    CLKFBSTOPPED        => clkfbstopped_unused,
    PWRDWN              => '0',
    RST                 => '0');

  -- Output buffering
  -------------------------------------
  clkf_buf : BUFG
  port map
   (O => clkfbout_buf,
    I => clkfbout);


  clkout1_buf : BUFG
  port map
   (O   => clock100,
    I   => clkout0);



  clkout2_buf : BUFG
  port map
   (O   => clock162,
    I   => clkout1);

  clkout3_buf : BUFG
  port map
   (O   => clock50,
    I   => clkout2);

  clkout4_buf : BUFG
  port map
   (O   => clock41,
    I   => clkout3);

  clkout5_buf : BUFG
  port map
   (O   => clock81,
    I   => clkout4);

  clkout6_buf : BUFG
  port map
   (O   => clock27,
    I   => clkout5);

  clkout7_buf : BUFG
  port map
   (O   => clock54,
    I   => clkout6);

end xilinx;
