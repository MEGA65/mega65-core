-------------------------------------------------------------------------------
--
--                                 SID 6581 (voice)
--
--     This piece of VHDL code describes a single SID voice (sound channel)
--
-------------------------------------------------------------------------------
-- to do:	- better resolution of result signal voice, this is now only 10bits,
-- but it could be 20 !! Problem, it does not fit the PWM-dac
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-------------------------------------------------------------------------------
--
-- Delta-Sigma DAC
--
-- Refer to Xilinx Application Note XAPP154.
--
-- This DAC requires an external RC low-pass filter:
--
--   dac_o 0---XXXXX---+---0 analog audio
--              3k3    |
--                    === 4n7
--                     |
--                    GND
--
-------------------------------------------------------------------------------
--Implementation Digital to Analog converter
entity pwm_sddac is
  generic (
    msbi_g : integer := 9
  );
  port (
    clk_i   : in  std_logic;
    reset   : in  std_logic;
    dac_i   : in  std_logic_vector(msbi_g downto 0);
    dac_o   : out std_logic
  );
end pwm_sddac;

architecture rtl of pwm_sddac is
  signal sig_in : unsigned(msbi_g+2 downto 0) := (others => '0');

begin
  seq: process (clk_i, reset)
  begin
    if reset = '1' then
      sig_in <= to_unsigned(2**(msbi_g+1), sig_in'length);
      dac_o  <= '0';
    elsif rising_edge(clk_i) then
      sig_in <= sig_in + unsigned(sig_in(msbi_g+2) & sig_in(msbi_g+2) & dac_i);
      dac_o  <= sig_in(msbi_g+2);
    end if;
  end process seq;
end rtl;

-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity pwm_sdadc is
	port (
		clk			: in		std_logic;	-- main clock signal (the higher the better)
		reset		: in		std_logic;	--
		ADC_out	: out		std_logic_vector(7 downto 0);		-- binary input of signal to be converted
		ADC_in	: inout	std_logic		-- "analog" paddle input pin
	);
end pwm_sdadc;

-- Dummy implementation (no real A/D conversion performed)
architecture rtl of pwm_sdadc is
begin
	process (clk, ADC_in)
	begin
		if ADC_in = '1' then
			ADC_out <= (others => '1');
		else
			ADC_out <= (others => '0');
		end if;
	end process;
end rtl;
