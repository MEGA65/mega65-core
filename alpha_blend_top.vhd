-------------------------------------------------------------------------------- 
-- Copyright (c) 2004 Xilinx, Inc. 
-- All Rights Reserved 
-------------------------------------------------------------------------------- 
--   ____  ____ 
--  /   /\/   / 
-- /___/  \  /   Vendor: Xilinx 
-- \   \   \/    Author: Reed Tidwell, Advanced Product Division, Xilinx, Inc.
--  \   \        Filename: $RCSfile: alpha_blend_top.vhd,v $
--  /   /        Date Last Modified:  $Date: 2004-12-14 10:43:39-07 $
-- /___/   /\    Date Created: October 18, 2004 
-- \   \  /  \ 
--  \___\/\___\ 
-- 
--
-- Revision History: 
-- $Log: alpha_blend_top.vhd,v $
-- Revision 1.3  2004-12-14 10:43:39-07  reedt
-- Corrected pixclk_out to clk1x for compiling with wrapper.
--
-- Revision 1.2  2004-12-06 10:11:13-07  reedt
-- Added Rounding for App note 706
--
-- Revision 1.1  2004-11-18 09:52:59-07  reedt
-- Changed clock follower, fol_clk1x, to be 2 FF stages instead of 3.
--
-- Revision 1.0  2004-11-08 12:53:21-07  reedt
-- Initial revision
--
-- Revision 1.1  2004-10-26 13:56:49-06  reedt
-- Completed blend simulation with picture files.
--
-- Revision 1.0  2004-10-19 10:55:08-06  reedt
-- Video stream blender with inputs for 2 sets of RGB & DE plus
-- an Alpha stream and alpha DE.  Simulation compile OK.
--
-- Revision 1.0  2004-10-19 10:16:14-06  reedt
-- Video stream blender with inputs for 2 sets of RGB & DE plus
-- an Alpha stream and alpha DE.  Initial checkin is before compile.
--
-- Revision 1.0  2004-09-20 17:22:32-06  reedt
-- Initial Checkin
--
-------------------------------------------------------------------------------- 
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

entity alpha_blend_top is
  port(
    clk1x:       in  std_logic;
    clk2x:       in  std_logic;
    reset:       in  std_logic;
    hsync_strm0: in  std_logic;
    vsync_strm0: in  std_logic;
    de_strm0:    in  std_logic;
    r_strm0:     in  std_logic_vector(9 downto 0);
    g_strm0:     in  std_logic_vector(9 downto 0);              
    b_strm0:     in  std_logic_vector(9 downto 0);
    de_strm1:    in  std_logic;
    r_strm1:     in  std_logic_vector(9 downto 0);
    g_strm1:     in  std_logic_vector(9 downto 0);
    b_strm1:     in  std_logic_vector(9 downto 0);
    de_alpha:    in  std_logic;
    alpha_strm:  in  std_logic_vector(9 downto 0);
 
     pixclk_out: out std_logic;
     hsync_blnd: out std_logic;
     vsync_blnd: out std_logic;
     de_blnd:    out std_logic;
     r_blnd:     out std_logic_vector(9 downto 0);
     g_blnd:     out std_logic_vector(9 downto 0);
     b_blnd:     out std_logic_vector(9 downto 0);
     dcm_locked:  out std_logic
); 
end alpha_blend_top;

architecture synth of alpha_blend_top is                 
  signal   fol_clk1x: std_logic;     -- clock follower of clk1x in clk2x domain
  signal   toggle:   std_logic;
  signal   toggle_1: std_logic;
  signal   video0_r: std_logic_vector(17 downto 0);  
  signal   video0_g: std_logic_vector(17 downto 0);
  signal   video0_b: std_logic_vector(17 downto 0);
  signal   video1_r: std_logic_vector(17 downto 0);  
  signal   video1_g: std_logic_vector(17 downto 0);
  signal   video1_b: std_logic_vector(17 downto 0);
  signal   alpha:    std_logic_vector(17 downto 0);
  signal   one_minus_alpha: std_logic_vector(17 downto 0);
  signal   blend_r:  std_logic_vector(47 downto 0);        -- outputs from DSP48
  signal   blend_g:  std_logic_vector(47 downto 0);
  signal   blend_b:  std_logic_vector(47 downto 0);
  signal   hsync_1, hsync_2, hsync_3, hsync_4: std_logic;
  signal   vsync_1, vsync_2, vsync_3, vsync_4: std_logic;
  signal   de_1, de_2, de_3, de_4:             std_logic;
  signal   round:    std_logic_vector(47 downto 0); -- Rounding constant

component  dual_stream_blend  
  port(
    clk1x:           in  std_logic;   -- Input and output rate clock
    clk2x:           in  std_logic;   -- Frequency doubled clock for DSP 
    reset:           in  std_logic; 
    fol_clk1x:       in  std_logic; 
    video0:          in  std_logic_vector(17 downto 0); -- Data Stream 0 A value
    video1:          in  std_logic_vector(17 downto 0); -- Data Stream 1 A value
    alpha:           in  std_logic_vector(17 downto 0); -- Data Stream 0 B value
    one_minus_alpha: in  std_logic_vector(17 downto 0); -- Data Stream 1 B value
    round:           in  std_logic_vector(47 downto 0); -- Rounding constant
-- output  port
    blend:            out  std_logic_vector(47 downto 0) -- Blended data stream
);
end component;
component DCM_1x_2x
   port ( CLKIN_IN        : in    std_logic; 
          RST_IN          : in    std_logic; 
          CLKIN_IBUFG_OUT : out   std_logic; 
          CLK0_OUT        : out   std_logic; 
          CLK2X_OUT       : out   std_logic; 
          LOCKED_OUT      : out   std_logic);
end component;

  signal video0_r_drive : std_logic_vector(17 downto 0);
  signal video0_g_drive : std_logic_vector(17 downto 0);
  signal video0_b_drive : std_logic_vector(17 downto 0);
  signal video1_r_drive : std_logic_vector(17 downto 0);
  signal video1_g_drive : std_logic_vector(17 downto 0);
  signal video1_b_drive : std_logic_vector(17 downto 0);

begin  ------------------------------------------------------------------------
  
-- for multiplicands, repeat MSBs in the LSBs for greater range  
  video0_r <=  ('0' & r_strm0 & r_strm0(9 downto 3)); 
  video0_g <=  ('0' & g_strm0 & g_strm0(9 downto 3));
  video0_b <=  ('0' & b_strm0 & b_strm0(9 downto 3));
  video1_r <=  ('0' & r_strm1 & r_strm1(9 downto 3));  
  video1_g <=  ('0' & g_strm1 & g_strm1(9 downto 3));
  video1_b <=  ('0' & b_strm1 & b_strm1(9 downto 3));
  alpha <=   ('0' &alpha_strm & alpha_strm(9 downto 3))
                      when de_alpha = '1' else "01" & x"FFFF";
  one_minus_alpha <= ('0' & not alpha_strm & not alpha_strm(9 downto 3))
                      when de_alpha = '1' else "00" & x"0000";
  round   <= x"000000010000" ;  -- round to 17 significant bits on output 
--
-- select output bits from 48 bit accumulator
--
  r_blnd <= blend_r(33 downto 24);
  g_blnd <= blend_g(33 downto 24);
  b_blnd <= blend_b(33 downto 24);
  hsync_blnd <= hsync_4;
  vsync_blnd <= vsync_4;
  de_blnd <= de_4;
  pixclk_out <= clk1x;
  -- 
  -- delay syncs to match rgb data
  --
  process( clk1x) begin
    if clk1x'event and clk1x = '1' then
      hsync_1 <= hsync_strm0;
      hsync_2 <= hsync_1;
      hsync_3 <= hsync_2;
      hsync_4 <= hsync_3;
      vsync_1 <= vsync_strm0;
      vsync_2 <= vsync_1;
      vsync_3 <= vsync_2;
      vsync_4 <= vsync_3;
      de_1 <= de_strm0;
      de_2 <= de_1;
      de_3 <= de_2;   
      de_4 <= de_3;
      video0_r_drive <= video0_r;
      video0_g_drive <= video0_g;
      video0_b_drive <= video0_b;
      video1_r_drive <= video1_r;
      video1_g_drive <= video1_g;
      video1_b_drive <= video1_b;
    end if;  
  end process;
  -- create clock following circuit
  process( clk1x, reset) begin
    if reset = '1' then
       toggle <= '0';
    elsif clk1x'event and clk1x = '1' then
      toggle <= not toggle;    
    end if;
  end process;
  
  process (clk2x) begin
    if clk2x'event and clk2x = '1' then
      toggle_1 <= toggle;
      fol_clk1x <= not (toggle xor toggle_1);
    end if;
  end process;
 --
 -- instantiate blend units for R G and B
 --    
 red_blender : dual_stream_blend   
   port map(
     clk1x            =>  clk1x,  
     clk2x            =>  clk2x, 
     reset            =>  reset,
     fol_clk1x        =>  fol_clk1x, 
     video0           =>  video0_r_drive,         
     video1           =>  video1_r_drive,        
     alpha            =>  alpha,          
     one_minus_alpha  =>  one_minus_alpha,
     round            =>  round,
     
     blend            =>  blend_r         
   );
 green_blender : dual_stream_blend 
   port map(
     clk1x             =>  clk1x,  
     clk2x             =>  clk2x,  
     reset             =>  reset,
     fol_clk1x        =>  fol_clk1x, 
     video0            =>  video0_g_drive,         
     video1            =>  video1_g_drive,        
     alpha             =>  alpha,          
     one_minus_alpha   =>  one_minus_alpha,
     round             =>  round,
   
     blend             =>  blend_g        
   );
 blue_blender : dual_stream_blend 
   port map(
     clk1x             =>  clk1x,  
     clk2x             =>  clk2x,  
     reset             =>  reset,
     fol_clk1x         =>  fol_clk1x, 
     video0            =>  video0_b_drive,         
     video1            =>  video1_b_drive,        
     alpha             =>  alpha,          
     one_minus_alpha   =>  one_minus_alpha,
     round             =>  round,
   
     blend             =>  blend_b        
   );

end synth;	
