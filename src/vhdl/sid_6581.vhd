-------------------------------------------------------------------------------
--
--                                 SID 6581
--
--     A fully functional SID chip implementation in VHDL
--
-------------------------------------------------------------------------------
--	to do:	- filter
--				- smaller implementation, use multiplexed channels
--
--
-- "The Filter was a classic multi-mode (state variable) VCF design. There was
-- no way to create a variable transconductance amplifier in our NMOS process,
-- so I simply used FETs as voltage-controlled resistors to control the cutoff
-- frequency. An 11-bit D/A converter generates the control voltage for the
-- FETs (it's actually a 12-bit D/A, but the LSB had no audible affect so I
-- disconnected it!)."
-- "Filter resonance was controlled by a 4-bit weighted resistor ladder. Each
-- bit would turn on one of the weighted resistors and allow a portion of the
-- output to feed back to the input. The state-variable design provided
-- simultaneous low-pass, band-pass and high-pass outputs. Analog switches
-- selected which combination of outputs were sent to the final amplifier (a
-- notch filter was created by enabling both the high and low-pass outputs
-- simultaneously)."
-- "The filter is the worst part of SID because I could not create high-gain
-- op-amps in NMOS, which were essential to a resonant filter. In addition,
-- the resistance of the FETs varied considerably with processing, so different
-- lots of SID chips had different cutoff frequency characteristics. I knew it
-- wouldn't work very well, but it was better than nothing and I didn't have
-- time to make it better."
--
-------------------------------------------------------------------------------
--
-- CREDITS According to Alvaro Lopes <alvieboy@alvie.com>
-- 
-- Credits for SID implementation go to Jan Derogee, who did the VHDL implementation,
-- and to Robert Yannes, who did the original SID chip.
-- 
-- License for the VHDL code, unless otherwise stated is (according to an email from Jan):
-- 
--	"everyone may use it, when changes are made make them public 
--         for the benefit of all, keeping it open source" 
--
--
-- https://en.wikipedia.org/wiki/Robert_Yannes
--
-- Alvaro is also the author of the SID filter module, which he has released under the BSD license:
--
-- (C) Alvaro Lopes <alvieboy@alvie.com>
-- 
--   The FreeBSD license
-- 
--   Redistribution and use in source and binary forms, with or without
--   modification, are permitted provided that the following conditions
--   are met:
-- 
--   1. Redistributions of source code must retain the above copyright
--      notice, this list of conditions and the following disclaimer.
--   2. Redistributions in binary form must reproduce the above
--      copyright notice, this list of conditions and the following
--      disclaimer in the documentation and/or other materials
--      provided with the distribution.
-- 
--   THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY
--   EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
--   THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
--   PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
--   ZPUINO PROJECT OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
--   INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
--   (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
--   OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
--   HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
--   STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
--   ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
--   ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

-------------------------------------------------------------------------------

entity sid6581 is
	port (
		clk_1MHz			: in  std_logic;		-- main SID clock signal
		clk32				: in  std_logic;		-- main clock signal
		reset				: in  std_logic;		-- high active signal (reset when reset = '1')
		cs					: in  std_logic;		-- "chip select", when this signal is '1' this model can be accessed
		we					: in std_logic;		-- when '1' this model can be written to, otherwise access is considered as read

		addr				: in  unsigned(4 downto 0);	-- address lines
		di					: in  unsigned(7 downto 0);	-- data in (to chip)
		do					: out unsigned(7 downto 0);	-- data out	(from chip)
		pot_x				: in  unsigned(7 downto 0);	-- paddle input-X
		pot_y				: in  unsigned(7 downto 0);	-- paddle input-Y
		audio_data		: out unsigned(17 downto 0)
	);
end sid6581;

architecture Behavioral of sid6581 is

  signal reset_drive : std_logic;
  
	signal Voice_1_Freq_lo	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_1_Freq_hi	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_1_Pw_lo		: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_1_Pw_hi		: unsigned(3 downto 0)	:= (others => '0');
	signal Voice_1_Control	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_1_Att_dec	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_1_Sus_Rel	: unsigned(7 downto 0)	:= (others => '0');

	signal Voice_2_Freq_lo	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_2_Freq_hi	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_2_Pw_lo		: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_2_Pw_hi		: unsigned(3 downto 0)	:= (others => '0');
	signal Voice_2_Control	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_2_Att_dec	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_2_Sus_Rel	: unsigned(7 downto 0)	:= (others => '0');

	signal Voice_3_Freq_lo	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_3_Freq_hi	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_3_Pw_lo		: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_3_Pw_hi		: unsigned(3 downto 0)	:= (others => '0');
	signal Voice_3_Control	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_3_Att_dec	: unsigned(7 downto 0)	:= (others => '0');
	signal Voice_3_Sus_Rel	: unsigned(7 downto 0)	:= (others => '0');

	signal Filter_Fc_lo		: unsigned(7 downto 0)	:= (others => '0');
	signal Filter_Fc_hi		: unsigned(7 downto 0)	:= (others => '0');
	signal Filter_Res_Filt	: unsigned(7 downto 0)	:= (others => '0');
	signal Filter_Mode_Vol	: unsigned(7 downto 0)	:= (others => '0');

	signal Misc_Osc3_Random	: unsigned(7 downto 0)	:= (others => '0');
	signal Misc_Env3			: unsigned(7 downto 0)	:= (others => '0');

	signal do_buf				: unsigned(7 downto 0)	:= (others => '0');

	signal voice_1				: unsigned(11 downto 0)	:= (others => '0');
	signal voice_2				: unsigned(11 downto 0)	:= (others => '0');
	signal voice_3				: unsigned(11 downto 0)	:= (others => '0');

	signal divide_0			: unsigned(31 downto 0)	:= (others => '0');
	signal voice_1_PA_MSB	: std_logic := '0';
	signal voice_2_PA_MSB	: std_logic := '0';
	signal voice_3_PA_MSB	: std_logic := '0';

	signal voice1_signed		: signed(12 downto 0);
	signal voice2_signed		: signed(12 downto 0);
	signal voice3_signed		: signed(12 downto 0);

	-- filter
	constant ext_in_signed	: signed(12 downto 0) := to_signed(0,13);
	signal filtered_audio	: signed(18 downto 0);
	signal tick_q1, tick_q2	: std_logic;
	signal input_valid		: std_logic;
	signal unsigned_audio	: unsigned(17 downto 0);
	signal unsigned_filt		: unsigned(18 downto 0);
	signal ff1					: std_logic;

-------------------------------------------------------------------------------

begin

	
	sid_voice_1: entity work.sid_voice
	port map(
		clk_1MHz				=> clk_1MHz,
		reset					=> reset_drive,
		Freq_lo				=> Voice_1_Freq_lo,
		Freq_hi				=> Voice_1_Freq_hi,
		Pw_lo					=> Voice_1_Pw_lo,
		Pw_hi					=> Voice_1_Pw_hi,
		Control				=> Voice_1_Control,
		Att_dec				=> Voice_1_Att_dec,
		Sus_Rel				=> Voice_1_Sus_Rel,
		PA_MSB_in			=> voice_3_PA_MSB,
		PA_MSB_out			=> voice_1_PA_MSB,
--		Osc					=> open,
--		Env					=> open,
		voice					=> voice_1
	);

	sid_voice_2: entity work.sid_voice
	port map(
		clk_1MHz				=> clk_1MHz,
		reset					=> reset_drive,
		Freq_lo				=> Voice_2_Freq_lo,
		Freq_hi				=> Voice_2_Freq_hi,
		Pw_lo					=> Voice_2_Pw_lo,
		Pw_hi					=> Voice_2_Pw_hi,
		Control				=> Voice_2_Control,
		Att_dec				=> Voice_2_Att_dec,
		Sus_Rel				=> Voice_2_Sus_Rel,
		PA_MSB_in			=> voice_1_PA_MSB,
		PA_MSB_out			=> voice_2_PA_MSB,
--		Osc					=> open,
--		Env					=> open,
		voice					=> voice_2
	);

	sid_voice_3: entity work.sid_voice
	port map(
		clk_1MHz				=> clk_1MHz,
		reset					=> reset_drive,
		Freq_lo				=> Voice_3_Freq_lo,
		Freq_hi				=> Voice_3_Freq_hi,
		Pw_lo					=> Voice_3_Pw_lo,
		Pw_hi					=> Voice_3_Pw_hi,
		Control				=> Voice_3_Control,
		Att_dec				=> Voice_3_Att_dec,
		Sus_Rel				=> Voice_3_Sus_Rel,
		PA_MSB_in			=> voice_2_PA_MSB,
		PA_MSB_out			=> voice_3_PA_MSB,
		Osc					=> Misc_Osc3_Random,
		Env					=> Misc_Env3,
		voice					=> voice_3
	);

-------------------------------------------------------------------------------------

-- SID filters

        process (do_buf,cs)
        begin
          -- Tristate data lines
          if cs='1' then
            -- Read from SID-register
            -------------------------
            case addr is
              -------------------------------------- Misc
              when "11001" => do <= pot_x;
              when "11010" => do <= pot_Y;
              when "11011" => do <= Misc_Osc3_Random;
              when "11100" => do <= Misc_Env3;
              --------------------------------------
              when others => do <= x"FF";
            end case;		
          else
            do <= (others => 'Z');
          end if;
        end process;

        
	process (clk_1MHz,reset)
	begin
		if reset_drive='1' then
			ff1<='0';
		else
			if rising_edge(clk_1MHz) then
				ff1<=not ff1;
			end if;
		end if;
	end process;

	process(clk32)
	begin
          if rising_edge(clk32) then
            reset_drive <= reset;
            tick_q1 <= ff1;
            tick_q2 <= tick_q1;
          end if;
	end process;

	input_valid <= '1' when tick_q1 /=tick_q2 else '0';

	voice1_signed <= signed("0" & voice_1) - 2048;
	voice2_signed <= signed("0" & voice_2) - 2048;
	voice3_signed <= signed("0" & voice_3) - 2048;

	filters: entity work.sid_filters 
	port map (
		clk			=> clk32,
		rst			=> reset_drive,
		-- SID registers.
		Fc_lo			=> Filter_Fc_lo,
		Fc_hi			=> Filter_Fc_hi,
		Res_Filt		=> Filter_Res_Filt,
		Mode_Vol		=> Filter_Mode_Vol,
		-- Voices - resampled to 13 bit
		voice1		=> voice1_signed,
		voice2		=> voice2_signed,
		voice3		=> voice3_signed,
		--
		input_valid => input_valid,
		ext_in		=> ext_in_signed,

		sound			=> filtered_audio,
		valid			=> open
	);

	unsigned_filt 	<= unsigned(filtered_audio + "1000000000000000000");
	unsigned_audio	<= unsigned_filt(18 downto 1);
	audio_data		<= unsigned_audio;

-- Register decoding
	register_decoder:process(clk32)
	begin
		if rising_edge(clk32) then
			if (reset_drive = '1') then
				--------------------------------------- Voice-1
				Voice_1_Freq_lo	<= (others => '0');
				Voice_1_Freq_hi	<= (others => '0');
				Voice_1_Pw_lo		<= (others => '0');
				Voice_1_Pw_hi		<= (others => '0');
				Voice_1_Control	<= (others => '0');
				Voice_1_Att_dec	<= (others => '0');
				Voice_1_Sus_Rel	<= (others => '0');
				--------------------------------------- Voice-2
				Voice_2_Freq_lo	<= (others => '0');
				Voice_2_Freq_hi	<= (others => '0');
				Voice_2_Pw_lo		<= (others => '0');
				Voice_2_Pw_hi		<= (others => '0');
				Voice_2_Control	<= (others => '0');
				Voice_2_Att_dec	<= (others => '0');
				Voice_2_Sus_Rel	<= (others => '0');
				--------------------------------------- Voice-3
				Voice_3_Freq_lo	<= (others => '0');
				Voice_3_Freq_hi	<= (others => '0');
				Voice_3_Pw_lo		<= (others => '0');
				Voice_3_Pw_hi		<= (others => '0');
				Voice_3_Control	<= (others => '0');
				Voice_3_Att_dec	<= (others => '0');
				Voice_3_Sus_Rel	<= (others => '0');
				--------------------------------------- Filter & volume
				Filter_Fc_lo		<= (others => '0');
				Filter_Fc_hi		<= (others => '0');
				Filter_Res_Filt	<= (others => '0');
				Filter_Mode_Vol	<= (others => '0');
			else
				Voice_1_Freq_lo	<= Voice_1_Freq_lo;
				Voice_1_Freq_hi	<= Voice_1_Freq_hi;
				Voice_1_Pw_lo		<= Voice_1_Pw_lo;
				Voice_1_Pw_hi		<= Voice_1_Pw_hi;
				Voice_1_Control	<= Voice_1_Control;
				Voice_1_Att_dec	<= Voice_1_Att_dec;
				Voice_1_Sus_Rel	<= Voice_1_Sus_Rel;
				Voice_2_Freq_lo	<= Voice_2_Freq_lo;
				Voice_2_Freq_hi	<= Voice_2_Freq_hi;
				Voice_2_Pw_lo		<= Voice_2_Pw_lo;
				Voice_2_Pw_hi		<= Voice_2_Pw_hi;
				Voice_2_Control	<= Voice_2_Control;
				Voice_2_Att_dec	<= Voice_2_Att_dec;
				Voice_2_Sus_Rel	<= Voice_2_Sus_Rel;
				Voice_3_Freq_lo	<= Voice_3_Freq_lo;
				Voice_3_Freq_hi	<= Voice_3_Freq_hi;
				Voice_3_Pw_lo		<= Voice_3_Pw_lo;
				Voice_3_Pw_hi		<= Voice_3_Pw_hi;
				Voice_3_Control	<= Voice_3_Control;
				Voice_3_Att_dec	<= Voice_3_Att_dec;
				Voice_3_Sus_Rel	<= Voice_3_Sus_Rel;
				Filter_Fc_lo		<= Filter_Fc_lo;
				Filter_Fc_hi		<= Filter_Fc_hi;
				Filter_Res_Filt	<= Filter_Res_Filt;
				Filter_Mode_Vol	<= Filter_Mode_Vol;
				do_buf 				<= (others => '0');

				if (cs='1') then
					if (we='1') then	-- Write to SID-register
								------------------------
						case addr is
							-------------------------------------- Voice-1	
                                                        when "00000" =>	Voice_1_Freq_lo	<= di;
							when "00001" =>	Voice_1_Freq_hi	<= di;
							when "00010" =>	Voice_1_Pw_lo		<= di;
							when "00011" =>	Voice_1_Pw_hi		<= di(3 downto 0);
							when "00100" =>	Voice_1_Control	<= di;
							when "00101" =>	Voice_1_Att_dec	<= di;
							when "00110" =>	Voice_1_Sus_Rel	<= di;
							--------------------------------------- Voice-2
							when "00111" =>	Voice_2_Freq_lo	<= di;
							when "01000" =>	Voice_2_Freq_hi	<= di;
							when "01001" =>	Voice_2_Pw_lo		<= di;
							when "01010" =>	Voice_2_Pw_hi		<= di(3 downto 0);
							when "01011" =>	Voice_2_Control	<= di;
							when "01100" =>	Voice_2_Att_dec	<= di;
							when "01101" =>	Voice_2_Sus_Rel	<= di;
							--------------------------------------- Voice-3
							when "01110" =>	Voice_3_Freq_lo	<= di;
							when "01111" =>	Voice_3_Freq_hi	<= di;
							when "10000" =>	Voice_3_Pw_lo		<= di;
							when "10001" =>	Voice_3_Pw_hi		<= di(3 downto 0);
							when "10010" =>	Voice_3_Control	<= di;
							when "10011" =>	Voice_3_Att_dec	<= di;
							when "10100" =>	Voice_3_Sus_Rel	<= di;
							--------------------------------------- Filter & volume
                                                        when "10101" =>	Filter_Fc_lo		<= di;
							when "10110" =>	Filter_Fc_hi		<= di;
							when "10111" =>	Filter_Res_Filt	<= di;
							when "11000" =>	Filter_Mode_Vol	<= di;
							--------------------------------------
							when others	=>	null;
						end case;
					end if;
				end if;
			end if;
		end if;
	end process;

end Behavioral;
