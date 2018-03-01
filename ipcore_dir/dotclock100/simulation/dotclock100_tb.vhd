-- file: dotclock100_tb.vhd
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
-- Clocking wizard demonstration testbench
------------------------------------------------------------------------------
-- This demonstration testbench instantiates the example design for the 
--   clocking wizard. Input clocks are toggled, which cause the clocking
--   network to lock and the counters to increment.
------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;

library std;
use std.textio.all;

library work;
use work.all;

entity dotclock100_tb is
end dotclock100_tb;

architecture test of dotclock100_tb is

  -- Clock to Q delay of 100 ps
  constant TCQ               : time := 100 ps;
  -- timescale is 1ps
  constant ONE_NS      : time := 1 ns;
  -- how many cycles to run
  constant COUNT_PHASE : integer := 1024 + 1;


  -- we'll be using the period in many locations
  constant PER1        : time := 10.000 ns;


  -- Declare the input clock signals
  signal CLK_IN1       : std_logic := '1';
  -- The high bits of the sampling counters
  signal COUNT         : std_logic_vector(7 downto 1);
  -- Status and control signals
  signal RESET         : std_logic := '0';
  signal LOCKED        : std_logic;
  signal COUNTER_RESET : std_logic := '0';
--  signal defined to stop mti simulation without severity failure in the report
  signal end_of_sim : std_logic := '0';
  signal CLK_OUT : std_logic_vector(7 downto 1);
--Freq Check using the M & D values setting and actual Frequency generated
  signal period1 : time := 0 ps;
constant  ref_period1_clkin1 : time := (10.000*1*12.000/12.000)*1000 ps;
   signal prev_rise1 : time := 0 ps;
  signal period2 : time := 0 ps;
constant  ref_period2_clkin1 : time := (10.000*1*6/12.000)*1000 ps;
   signal prev_rise2 : time := 0 ps;
  signal period3 : time := 0 ps;
constant  ref_period3_clkin1 : time := (10.000*1*24/12.000)*1000 ps;
   signal prev_rise3 : time := 0 ps;
  signal period4 : time := 0 ps;
constant  ref_period4_clkin1 : time := (10.000*1*30/12.000)*1000 ps;
   signal prev_rise4 : time := 0 ps;
  signal period5 : time := 0 ps;
constant  ref_period5_clkin1 : time := (10.000*1*40/12.000)*1000 ps;
   signal prev_rise5 : time := 0 ps;
  signal period6 : time := 0 ps;
constant  ref_period6_clkin1 : time := (10.000*1*36/12.000)*1000 ps;
   signal prev_rise6 : time := 0 ps;
  signal period7 : time := 0 ps;
constant  ref_period7_clkin1 : time := (10.000*1*8/12.000)*1000 ps;
   signal prev_rise7 : time := 0 ps;

component dotclock100_exdes
generic (
  TCQ               : in time := 100 ps);
port
 (-- Clock in ports
  CLK_IN1           : in  std_logic;
  -- Reset that only drives logic in example design
  COUNTER_RESET     : in  std_logic;
  CLK_OUT           : out std_logic_vector(7 downto 1) ;
  -- High bits of counters driven by clocks
  COUNT             : out std_logic_vector(7 downto 1);
  -- Status and control signals
  RESET             : in  std_logic;
  LOCKED            : out std_logic
 );
end component;

begin

  -- Input clock generation
  --------------------------------------
  process begin
    CLK_IN1 <= not CLK_IN1; wait for (PER1/2);
  end process;

  -- Test sequence
  process 

    procedure simtimeprint is
      variable outline : line;
    begin
      write(outline, string'("## SYSTEM_CYCLE_COUNTER "));
      write(outline, NOW/PER1);
      write(outline, string'(" ns"));
      writeline(output,outline);
    end simtimeprint;

    procedure simfreqprint (period : time; clk_num : integer) is
       variable outputline : LINE;
       variable str1 : string(1 to 16);
       variable str2 : integer;
       variable str3 : string(1 to 2);
       variable str4 : integer;
       variable str5 : string(1 to 4);
    begin
       str1 := "Freq of CLK_OUT(";
       str2 :=  clk_num;
       str3 :=  ") ";
       str4 :=  1000000 ps/period ;
       str5 :=  " MHz" ;
       write(outputline, str1 );
       write(outputline, str2);
       write(outputline, str3);
       write(outputline, str4);
       write(outputline, str5);
       writeline(output, outputline);
    end simfreqprint;

  begin
    RESET      <= '1';
    wait for (PER1*6);
    RESET      <= '0';
    wait until LOCKED = '1';
    COUNTER_RESET <= '1';
    wait for (PER1*20);
    COUNTER_RESET <= '0';
    wait for (PER1*COUNT_PHASE);
    simfreqprint(period1, 1);
    assert (((period1 - ref_period1_clkin1) >= -100 ps) and ((period1 - ref_period1_clkin1) <= 100 ps)) report "ERROR: Freq of CLK_OUT(1) is not correct"  severity note;
    simfreqprint(period2, 2);
    assert (((period2 - ref_period2_clkin1) >= -100 ps) and ((period2 - ref_period2_clkin1) <= 100 ps)) report "ERROR: Freq of CLK_OUT(2) is not correct"  severity note;
    simfreqprint(period3, 3);
    assert (((period3 - ref_period3_clkin1) >= -100 ps) and ((period3 - ref_period3_clkin1) <= 100 ps)) report "ERROR: Freq of CLK_OUT(3) is not correct"  severity note;
    simfreqprint(period4, 4);
    assert (((period4 - ref_period4_clkin1) >= -100 ps) and ((period4 - ref_period4_clkin1) <= 100 ps)) report "ERROR: Freq of CLK_OUT(4) is not correct"  severity note;
    simfreqprint(period5, 5);
    assert (((period5 - ref_period5_clkin1) >= -100 ps) and ((period5 - ref_period5_clkin1) <= 100 ps)) report "ERROR: Freq of CLK_OUT(5) is not correct"  severity note;
    simfreqprint(period6, 6);
    assert (((period6 - ref_period6_clkin1) >= -100 ps) and ((period6 - ref_period6_clkin1) <= 100 ps)) report "ERROR: Freq of CLK_OUT(6) is not correct"  severity note;
    simfreqprint(period7, 7);
    assert (((period7 - ref_period7_clkin1) >= -100 ps) and ((period7 - ref_period7_clkin1) <= 100 ps)) report "ERROR: Freq of CLK_OUT(7) is not correct"  severity note;


    simtimeprint;
    end_of_sim <= '1';
    wait for 1 ps;
    report "Simulation Stopped." severity failure;
    wait;
  end process;

  -- Instantiation of the example design containing the clock
  --    network and sampling counters
  -----------------------------------------------------------
  dut : dotclock100_exdes
  generic map (
    TCQ                => TCQ)
  port map
   (-- Clock in ports
    CLK_IN1            => CLK_IN1,
    -- Reset for logic in example design
    COUNTER_RESET      => COUNTER_RESET,
    CLK_OUT            => CLK_OUT,
    -- High bits of the counters
    COUNT              => COUNT,
    -- Status and control signals
    RESET              => RESET,
    LOCKED             => LOCKED);

-- Freq Check 
   process(CLK_OUT(1))
   begin
   if (CLK_OUT(1)'event and CLK_OUT(1) = '1') then
     if (prev_rise1 /= 0 ps) then
       period1 <= NOW - prev_rise1;
     end if;
     prev_rise1 <= NOW; 
   end if;
   end process;
   process(CLK_OUT(2))
   begin
   if (CLK_OUT(2)'event and CLK_OUT(2) = '1') then
     if (prev_rise2 /= 0 ps) then
       period2 <= NOW - prev_rise2;
     end if;
     prev_rise2 <= NOW; 
   end if;
   end process;
   process(CLK_OUT(3))
   begin
   if (CLK_OUT(3)'event and CLK_OUT(3) = '1') then
     if (prev_rise3 /= 0 ps) then
       period3 <= NOW - prev_rise3;
     end if;
     prev_rise3 <= NOW; 
   end if;
   end process;
   process(CLK_OUT(4))
   begin
   if (CLK_OUT(4)'event and CLK_OUT(4) = '1') then
     if (prev_rise4 /= 0 ps) then
       period4 <= NOW - prev_rise4;
     end if;
     prev_rise4 <= NOW; 
   end if;
   end process;
   process(CLK_OUT(5))
   begin
   if (CLK_OUT(5)'event and CLK_OUT(5) = '1') then
     if (prev_rise5 /= 0 ps) then
       period5 <= NOW - prev_rise5;
     end if;
     prev_rise5 <= NOW; 
   end if;
   end process;
   process(CLK_OUT(6))
   begin
   if (CLK_OUT(6)'event and CLK_OUT(6) = '1') then
     if (prev_rise6 /= 0 ps) then
       period6 <= NOW - prev_rise6;
     end if;
     prev_rise6 <= NOW; 
   end if;
   end process;
   process(CLK_OUT(7))
   begin
   if (CLK_OUT(7)'event and CLK_OUT(7) = '1') then
     if (prev_rise7 /= 0 ps) then
       period7 <= NOW - prev_rise7;
     end if;
     prev_rise7 <= NOW; 
   end if;
   end process;

end test;
