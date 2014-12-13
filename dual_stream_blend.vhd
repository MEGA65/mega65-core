--------------------------------------------------------------------------------
-- Copyright (c) 2004 Xilinx, Inc. 
-- All Rights Reserved 
--------------------------------------------------------------------------------
--   ____  ____ 
--  /   /\/   / 
-- /___/  \  /   Vendor: Xilinx 
-- \   \   \/    Author: Reed Tidwell, Advanced Product Division, Xilinx, Inc.
--  \   \        Filename: $RCSfile: dual_stream_blend.vhd,v $
--  /   /        Date Last Modified:  $Date: 2004-12-06 10:11:13-07 $
-- /___/   /\    Date Created: August 18, 2004 
-- \   \  /  \ 
--  \___\/\___\ 
-- 
--
-- Revision History: 
-- $Log: dual_stream_blend.vhd,v $
-- Revision 1.2  2004-12-06 10:11:13-07  reedt
-- Added Rounding for App note 706
--
-- Revision 1.1  2004-11-09 16:40:52-07  reedt
-- Removed align register.  Added 2nd internal delay in DSP.  Added clock follower.  Debugged VHDL and Verilog versions.
--
-- Revision 1.0  2004-11-08 12:53:21-07  reedt
-- Initial revision
--
-- Revision 1.1  2004-10-26 13:56:49-06  reedt
-- Completed blend simulation with picture files.
--
-- Revision 1.0  2004-09-20 17:22:32-06  reedt
-- Initial Checkin
--
------------------------------------------------------------------------------- 
--
--     XILINX IS PROVIDING THIS DESIGN, CODE, OR INFORMATION "AS IS"
--     SOLELY FOR USE IN DEVELOPING PROGRAMS AND SOLUTIONS FOR
--     XILINX DEVICES.  BY PROVIDING THIS DESIGN, CODE, OR INFORMATION
--     AS ONE POSSIBLE IMPLEMENTATION OF THIS FEATURE, APPLICATION
--     OR STANDARD, XILINX IS MAKING NO REPRESENTATION THAT THIS
--     IMPLEMENTATION IS FREE FROM ANY CLAIMS OF INFRINGEMENT,
--     AND YOU ARE RESPONSIBLE FOR OBTAINING ANY RIGHTS YOU MAY REQUIRE
--     FOR YOUR IMPLEMENTATION.  XILINX EXPRESSLY DISCLAIMS ANY
--     WARRANTY WHATSOEVER WITH RESPECT TO THE ADEQUACY OF THE
--     IMPLEMENTATION, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OR
--     REPRESENTATIONS THAT THIS IMPLEMENTATION IS FREE FROM CLAIMS OF
--     INFRINGEMENT, IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
--     FOR A PARTICULAR PURPOSE.
--
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.numeric_std.all;
library unisim;
use unisim.vcomponents.all;

entity  dual_stream_blend  is
  port(
    clk1x:           in  std_logic;   -- Input and output rate clock
    clk2x:           in  std_logic;   -- Frequency doubled clock for DSP 
    reset:           in  std_logic;  
    fol_clk1x:       in  std_logic;   -- clock follower of clk1x
    video0:          in  std_logic_vector(17 downto 0); -- Data Stream 0 A value
    video1:          in  std_logic_vector(17 downto 0); -- Data Stream 1 A value
    alpha:           in  std_logic_vector(17 downto 0); -- Data Stream 0 B value
    one_minus_alpha: in  std_logic_vector(17 downto 0); -- Data Stream 1 B value
    round:           in  std_logic_vector(47 downto 0); -- Rounding constant
-- output  port
    blend:            out  std_logic_vector(47 downto 0) -- Blended data stream
);
end dual_stream_blend;

architecture synth of dual_stream_blend is 
signal vid0_in :     std_logic_vector(17 downto 0);  -- Registers for inputs
signal vid1_in :     std_logic_vector(17 downto 0);
signal alpha_in :    std_logic_vector(17 downto 0);
signal one_minus_in :std_logic_vector(17 downto 0);
signal blend_pass :  std_logic;           -- Mux select for DSP 48 Z mux
signal dsp0A :        std_logic_vector(17 downto 0);     -- DSP48 A input 
signal dsp0B :        std_logic_vector(17 downto 0);     -- DSP48 B input
signal dsp1A :        std_logic_vector(17 downto 0);     -- DSP48 A input 
signal dsp1B :        std_logic_vector(17 downto 0);     -- DSP48 B input
signal dsp0P :        std_logic_vector(47 downto 0);     -- DSP48 output
signal dsp1P :        std_logic_vector(47 downto 0);     -- DSP48 output
signal opmode0 :      std_logic_vector(6 downto 0);      -- OPMODE input to DSP48
signal opmode1 :      std_logic_vector(6 downto 0);      -- OPMODE input to DSP48
signal zero:         std_logic;   -- logic levels for connecting to DSP48
signal one:          std_logic;   -- verilog model for Modelsim simulation
signal zero_2:       std_logic_vector(1 downto 0);
signal zero_18:      std_logic_vector(17 downto 0);
signal zero_48:      std_logic_vector(47 downto 0);
begin  
  zero <= '0';
  one  <= '1';
  zero_2 <= "00";
  zero_18 <= "00" & x"0000";  
  zero_48 <= x"000000000000" ;
  -- define input muxes
  dsp0A <= vid0_in;
  dsp0B <= alpha_in;
  dsp1A <= vid1_in;
  dsp1B <= one_minus_in;

  opmode0 <=   '0' &  '1' & (not '0')  & "0101";
  opmode1 <=   '0' &  '1' & (not '1')  & "0101";
  
  -- define clk1x registers
  process (clk1x, reset) begin
    if   reset = '1' then
      vid0_in <=  (others => '0');
      vid1_in <=  (others => '0');
      alpha_in <= (others => '0');
      one_minus_in <= (others => '0');
      blend <= (others => '0');  
    elsif  clk1x'event and clk1x = '1' then  
      vid0_in <= video0;
      vid1_in <= video1;
      alpha_in <= alpha;
      one_minus_in <= one_minus_alpha;
      blend <= dspP;
    end if;   -- not reset
  end process;
  
  --  implement synchronous control signals
  process  (clk2x, reset) begin
    if reset = '1' then
      mux_sel <=  '0';
      blend_pass <= '0';
    elsif clk2x'event and clk2x = '1' then -- not reset
      mux_sel <=    fol_clk1x;
      blend_pass <=   fol_clk1x;
    end if; -- not reset
  end process;
  -- instance DSP 48 
  alpha_blend0 : DSP48
    generic map (
      AREG => 2,
      BREG => 2,
      CREG => 0,
      CARRYINREG => 0,
      MREG => 1,
      PREG => 1,
      OPMODEREG => 1,
      SUBTRACTREG => 0,
      CARRYINSELREG => 0,
      B_INPUT => "DIRECT",
      LEGACY_MODE =>  "MULT18X18S" 
    )
    port map(
      A                 => dsp0A,           -- Input A to Multiplier
      B                 => dsp0B,           -- Input B to Multiplier
      C                 => round,          -- Input C to Adder, round to 17 buts
      BCIN              => zero_18,          
      PCIN              => zero_48,       
      OPMODE            => opmode0,  
      SUBTRACT          => zero,    
      CARRYIN           => zero,     
      CARRYINSEL        => zero_2, 
      CLK               => clk2x,        
      CEA               => one,         
      CEB               => one,         
      CEC               => one,         
      CEP               => one,         
      CEM               => one,         
      CECTRL            => one,      
      CECARRYIN         => one,   
	  CECINSUB          => one,    
      RSTA              => reset,       
      RSTB              => reset,       
      RSTC              => reset,       
      RSTP              => reset,       
      RSTM              => reset,       
      RSTCTRL           => reset,    
      RSTCARRYIN        => reset, 
      BCOUT             => open, 
      P                 => dsp0P,           
      PCOUT             => open 
  );
  alpha_blend1 : DSP48
    generic map (
      AREG => 2,
      BREG => 2,
      CREG => 0,
      CARRYINREG => 0,
      MREG => 1,
      PREG => 1,
      OPMODEREG => 1,
      SUBTRACTREG => 0,
      CARRYINSELREG => 0,
      B_INPUT => "DIRECT",
      LEGACY_MODE =>  "MULT18X18S" 
    )
    port map(
      A                 => dsp1A,           -- Input A to Multiplier
      B                 => dsp1B,           -- Input B to Multiplier
      C                 => round,          -- Input C to Adder, round to 17 buts
      BCIN              => zero_18,          
      PCIN              => zero_48,       
      OPMODE            => opmode1,  
      SUBTRACT          => zero,    
      CARRYIN           => zero,     
      CARRYINSEL        => zero_2, 
      CLK               => clk2x,        
      CEA               => one,         
      CEB               => one,         
      CEC               => one,         
      CEP               => one,         
      CEM               => one,         
      CECTRL            => one,      
      CECARRYIN         => one,   
	  CECINSUB          => one,    
      RSTA              => reset,       
      RSTB              => reset,       
      RSTC              => reset,       
      RSTP              => reset,       
      RSTM              => reset,       
      RSTCTRL           => reset,    
      RSTCARRYIN        => reset, 
      BCOUT             => open, 
      P                 => dsp1P,           
      PCOUT             => open 
  );
end synth;	
