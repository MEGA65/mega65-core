-------------------------------------------------------------------------------
--
--                                 SID 6581 (voice)
--
--     This piece of VHDL code describes a single SID voice (sound channel)
--
-------------------------------------------------------------------------------
--	to do:	- better resolution of result signal voice, this is now only 12bits
--	but it could be 20 !! Problem, it does not fit the PWM-dac
-------------------------------------------------------------------------------

library IEEE;
	use IEEE.std_logic_1164.all;
	--use IEEE.std_logic_arith.all;
	--use IEEE.std_logic_unsigned.all;
	use IEEE.numeric_std.all;

-------------------------------------------------------------------------------

entity sid_voice_8580 is
  port (
    ce_1m			: in	std_logic;
    clock : in std_logic;
    cpuclock : in std_logic;
    sawtooth : in unsigned(11 downto 0);
    triangle : in unsigned(11 downto 0);
    st_out : in unsigned(7 downto 0);
    p_t_out : in unsigned(7 downto 0);
    ps_out : in unsigned(7 downto 0);
    pst_out : in unsigned(7 downto 0);
    reset			: in	std_logic;
    Freq_lo			: in	unsigned(7 downto 0);	-- low-byte of frequency register 
    Freq_hi			: in	unsigned(7 downto 0);	-- high-byte of frequency register 
    Pw_lo				: in	unsigned(7 downto 0);	-- low-byte of PuleWidth register
    Pw_hi				: in	unsigned(7 downto 0);	-- high-nibble of PuleWidth register
    Control			: in	unsigned(7 downto 0);	-- control register
    Att_dec			: in	unsigned(7 downto 0);	-- attack-deccay register
    Sus_Rel			: in	unsigned(7 downto 0);	-- sustain-release register
    osc_MSB_in		: in	std_logic;		        					-- Phase Accumulator MSB input
    osc_MSB_out		: out	std_logic;							-- Phase Accumulator MSB output
    Osc_out				: out	unsigned(7 downto 0);	-- Voice waveform register
    Env_out				: out	unsigned(7 downto 0);	-- Voice envelope register
    signal_out			: out	unsigned(11 downto 0)	-- Voice waveform, this is the actual audio signal
	);
end sid_voice_8580;

architecture vhdl_conversion_from_verilog of sid_voice_8580 is	
begin

end vhdl_conversion_from_verilog;
