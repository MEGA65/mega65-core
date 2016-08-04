----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    16:39:30 03/12/2016 
-- Design Name: 
-- Module Name:    fpgatemp - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity fpgatemp is
	 Generic ( DELAY_CYCLES : natural := 480 ); -- 10us @ 48 Mhz
    Port ( clk : in  STD_LOGIC;
           rst : in  STD_LOGIC;
           temp : out  STD_LOGIC_VECTOR (11 downto 0));
end fpgatemp;

architecture Behavioral of fpgatemp is

signal den_in, drdy_out : std_logic;
signal do_out : std_logic_vector(15 downto 0);
signal delay_cnt : natural range 0 to DELAY_CYCLES := DELAY_CYCLES;

begin

-----------------
-- XADC primitive
-----------------
-- Single channel
-- Continuous mode
-- DCLK freq: 48Mhz (/4)
-- Enable DRP
-- Disable all status pins
-- Disable all control pins
-- Channel averaging: 16
-- ADC calibration: both
-- Supply sensor calibration: none
-- Disable all alarms
-- Selected channel: Temperature
 XADC_INST : XADC
     generic map(
        INIT_40 => X"1000", -- config reg 0
        INIT_41 => X"3f3f", -- config reg 1
        INIT_42 => X"0400", -- config reg 2
        INIT_48 => X"0100", -- Sequencer channel selection
        INIT_49 => X"0000", -- Sequencer channel selection
        INIT_4A => X"0000", -- Sequencer Average selection
        INIT_4B => X"0000", -- Sequencer Average selection
        INIT_4C => X"0000", -- Sequencer Bipolar selection
        INIT_4D => X"0000", -- Sequencer Bipolar selection
        INIT_4E => X"0000", -- Sequencer Acq time selection
        INIT_4F => X"0000", -- Sequencer Acq time selection
        INIT_50 => X"b5ed", -- Temp alarm trigger
        INIT_51 => X"57e4", -- Vccint upper alarm limit
        INIT_52 => X"a147", -- Vccaux upper alarm limit
        INIT_53 => X"ca33",  -- Temp alarm OT upper
        INIT_54 => X"a93a", -- Temp alarm reset
        INIT_55 => X"52c6", -- Vccint lower alarm limit
        INIT_56 => X"9555", -- Vccaux lower alarm limit
        INIT_57 => X"ae4e",  -- Temp alarm OT reset
        INIT_58 => X"5999",  -- Vbram upper alarm limit
        INIT_5C => X"5111",  -- Vbram lower alarm limit
        SIM_DEVICE => "7SERIES"
        )

port map (
        CONVST              => '0',
        CONVSTCLK           => '0',
        DADDR(6 downto 0)   => "0000000",
        DCLK                => clk,
        DEN                 => den_in,
        DI(15 downto 0)     => x"0000",
        DWE                 => '0',
        RESET               => '0',
        VAUXN(15 downto 0)  => x"0000",
        VAUXP(15 downto 0)  => x"0000",
        ALM                 => open,
        BUSY                => open,
        CHANNEL             => open,
        DO(15 downto 0)     => do_out,
        DRDY                => drdy_out,
        EOC                 => open,
        EOS                 => open,
        JTAGBUSY            => open,
        JTAGLOCKED          => open,
        JTAGMODIFIED        => open,
        OT                  => open,
     
        MUXADDR             => open,
        VN                  => '0',
        VP                  => '0'
         );

process (clk)
begin
	if Rising_Edge(clk) then
		-- Capture at 10us rate
		if (rst = '1') then
			den_in <= '0';
			delay_cnt <= DELAY_CYCLES;
		elsif (delay_cnt = 0) then
			den_in <= '1';
			delay_cnt <= DELAY_CYCLES;
		else
			den_in <= '0';
			delay_cnt <= delay_cnt - 1;
		end if;
		-- Output temperature
		if (drdy_out = '1') then
			temp <= do_out(15 downto 4);
		end if;
	end if;
end process;

end Behavioral;
