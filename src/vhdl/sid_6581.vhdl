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
    cpuclock				: in  std_logic;		-- main clock signal
    reset				: in  std_logic;		-- high active signal (reset when reset = '1')
    cs					: in  std_logic;		-- "chip select", when this signal is '1' this model can be accessed
    we					: in std_logic;		-- when '1' this model can be written to, otherwise access is considered as read
    
    mode : in std_logic; -- 0=6581, 1=8580
    
    addr				: in  unsigned(4 downto 0);	-- address lines
    di					: in  unsigned(7 downto 0);	-- data in (to chip)
    do					: out unsigned(7 downto 0);	-- data out	(from chip)
    pot_x				: in  unsigned(7 downto 0);	-- paddle input-X
    pot_y				: in  unsigned(7 downto 0);	-- paddle input-Y
    audio_data		: out unsigned(17 downto 0) := to_unsigned(0,18);
    signed_audio		: out signed(17 downto 0) := to_signed(0,18);
    
    filter_table_addr : out integer range 0 to 2047 := 0;
    filter_table_val : in unsigned(15 downto 0)
    );
end sid6581;

architecture Behavioral of sid6581 is
  
  signal reset_drive : std_logic;
  
  signal clk_1MHz_en : std_logic := '1';
  
  
  signal Voice_1_Freq_lo	: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_1_Freq_hi	: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_1_Pw_lo		: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_1_Pw_hi		: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_1_Control	: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_1_Att_dec	: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_1_Sus_Rel	: unsigned(7 downto 0)	:= (others => '0');
  
  signal Voice_2_Freq_lo	: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_2_Freq_hi	: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_2_Pw_lo		: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_2_Pw_hi		: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_2_Control	: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_2_Att_dec	: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_2_Sus_Rel	: unsigned(7 downto 0)	:= (others => '0');
  
  signal Voice_3_Freq_lo	: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_3_Freq_hi	: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_3_Pw_lo		: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_3_Pw_hi		: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_3_Control	: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_3_Att_dec	: unsigned(7 downto 0)	:= (others => '0');
  signal Voice_3_Sus_Rel	: unsigned(7 downto 0)	:= (others => '0');
  
  signal Filter_Fc_lo		: unsigned(7 downto 0)	:= (others => '0');
  signal Filter_Fc_hi		: unsigned(7 downto 0)	:= (others => '0');
  signal Filter_Res_Filt	: unsigned(7 downto 0)	:= (others => '0');
  signal Filter_Mode_Vol	: unsigned(7 downto 0)	:= (others => '0');
  
  signal Misc_Osc3_Random	: unsigned(7 downto 0)	:= (others => '0');
  signal Misc_Osc3_Random_6581	: unsigned(7 downto 0)	:= (others => '0');
  signal Misc_Osc3_Random_8580	: unsigned(7 downto 0);
  signal Misc_Env3			: unsigned(7 downto 0)	:= (others => '0');
  signal Misc_Env3_6581			: unsigned(7 downto 0)	:= (others => '0');
  signal Misc_Env3_8580			: unsigned(7 downto 0);
  
  signal do_buf				: unsigned(7 downto 0)	:= (others => '0');
  
  signal voice_1				: unsigned(11 downto 0);
  signal voice_2				: unsigned(11 downto 0);
  signal voice_3				: unsigned(11 downto 0);
  
  signal voice_1_8580			: unsigned(11 downto 0);
  signal voice_2_8580			: unsigned(11 downto 0);
  signal voice_3_8580			: unsigned(11 downto 0);
  
  signal divide_0			: unsigned(31 downto 0)	:= (others => '0');
  signal voice_1_PA_MSB	: std_logic;
  signal voice_2_PA_MSB	: std_logic;
  signal voice_3_PA_MSB	: std_logic;
  
  signal voice_1_PA_MSB_8580	: std_logic;
  signal voice_2_PA_MSB_8580	: std_logic;
  signal voice_3_PA_MSB_8580	: std_logic;
  
  -- 8580 waveform lookup table (shared among the three voices)
  signal sid_table_state : integer range 0 to 15 := 0;
  signal f_sawtooth : unsigned(11 downto 0);
  signal f_triangle : unsigned(11 downto 0);
  signal f_ps_out : unsigned(7 downto 0);
  signal f_p_t_out : unsigned(7 downto 0);
  signal f_pst_out : unsigned(7 downto 0);
  signal f_st_out : unsigned(7 downto 0);
  signal voice_1_sawtooth_8580 : unsigned(11 downto 0);
  signal voice_1_triangle_8580 : unsigned(11 downto 0);
  signal voice_1_st_out_8580 : unsigned(7 downto 0);
  signal voice_1_p_t_out_8580 : unsigned(7 downto 0);
  signal voice_1_ps_out_8580 : unsigned(7 downto 0);
  signal voice_1_pst_out_8580 : unsigned(7 downto 0);
  signal voice_2_sawtooth_8580 : unsigned(11 downto 0);
  signal voice_2_triangle_8580 : unsigned(11 downto 0);
  signal voice_2_st_out_8580 : unsigned(7 downto 0);
  signal voice_2_p_t_out_8580 : unsigned(7 downto 0);
  signal voice_2_ps_out_8580 : unsigned(7 downto 0);
  signal voice_2_pst_out_8580 : unsigned(7 downto 0);
  signal voice_3_sawtooth_8580 : unsigned(11 downto 0);
  signal voice_3_triangle_8580 : unsigned(11 downto 0);
  signal voice_3_st_out_8580 : unsigned(7 downto 0);
  signal voice_3_p_t_out_8580 : unsigned(7 downto 0);
  signal voice_3_ps_out_8580 : unsigned(7 downto 0);
  signal voice_3_pst_out_8580 : unsigned(7 downto 0);
  
  
  signal voice1_signed		: signed(12 downto 0) := to_signed(0,13);
  signal voice2_signed		: signed(12 downto 0) := to_signed(0,13);
  signal voice3_signed		: signed(12 downto 0) := to_signed(0,13);
  
  -- filter
  constant ext_in_signed	: signed(12 downto 0) := to_signed(0,13);
  signal filtered_audio	: signed(18 downto 0) := to_signed(0,19);
  signal tick_q1, tick_q2	: std_logic;
  signal input_valid		: std_logic := '0';
  signal unsigned_audio	: unsigned(17 downto 0);
  signal unsigned_filt		: unsigned(18 downto 0);
  signal ff1					: std_logic := '1';
  
  signal last_clk_1mhz : std_logic := '0';
  
-------------------------------------------------------------------------------
  
begin
  
  sid_tables0: entity work.sid_tables
    port map (
      clock => cpuclock,
      sawtooth => f_sawtooth,
      triangle => f_triangle,
      st_out => f_st_out,
      p_t_out => f_p_t_out,
      ps_out => f_ps_out,
      pst_out => f_pst_out
      );      
  
  sid_voice_1: entity work.sid_voice
    port map(
      cpuclock => cpuclock,
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
      cpuclock => cpuclock,
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
      cpuclock => cpuclock,
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
      Osc					=> Misc_Osc3_Random_6581,
      Env					=> Misc_Env3_6581,
      voice					=> voice_3
      );
  
  sid_voice_8580_1: entity work.sid_voice_8580
    port map(
      cpuclock => cpuclock,
      clock                           => clk_1Mhz,
      ce_1m				=> clk_1MHz_en,
      reset					=> reset_drive,
      Freq_lo				=> Voice_1_Freq_lo,
      Freq_hi				=> Voice_1_Freq_hi,
      Pw_lo					=> Voice_1_Pw_lo,
      Pw_hi					=> Voice_1_Pw_hi,
      Control				=> Voice_1_Control,
      Att_dec				=> Voice_1_Att_dec,
      Sus_Rel				=> Voice_1_Sus_Rel,
      osc_MSB_in			=> voice_3_PA_MSB_8580,
      osc_MSB_out			=> voice_1_PA_MSB_8580,
      sawtooth                        => voice_1_sawtooth_8580,
      triangle                        => voice_1_triangle_8580,
      st_out                          => voice_1_st_out_8580,
      p_t_out                         => voice_1_p_t_out_8580,
      ps_out                         => voice_1_ps_out_8580,
      pst_out                         => voice_1_pst_out_8580,
--		Osc					=> open,
--		Env					=> open,
      signal_out					=> voice_1_8580
      );
  
  sid_voice_8580_2: entity work.sid_voice_8580
    port map(
      cpuclock => cpuclock,
      clock                           => clk_1Mhz,
      ce_1m				=> clk_1MHz_en,
      reset					=> reset_drive,
      Freq_lo				=> Voice_2_Freq_lo,
      Freq_hi				=> Voice_2_Freq_hi,
      Pw_lo					=> Voice_2_Pw_lo,
      Pw_hi					=> Voice_2_Pw_hi,
      Control				=> Voice_2_Control,
      Att_dec				=> Voice_2_Att_dec,
      Sus_Rel				=> Voice_2_Sus_Rel,
      osc_MSB_in			=> voice_1_PA_MSB_8580,
      osc_MSB_out			=> voice_2_PA_MSB_8580,
      sawtooth                        => voice_2_sawtooth_8580,
      triangle                        => voice_2_triangle_8580,
      st_out                          => voice_2_st_out_8580,
      p_t_out                         => voice_2_p_t_out_8580,
      ps_out                         => voice_2_ps_out_8580,
      pst_out                         => voice_2_pst_out_8580,
--		Osc					=> open,
--		Env					=> open,
      signal_out					=> voice_2_8580
      );
  
  sid_voice_8580_3: entity work.sid_voice_8580
    port map(
      cpuclock => cpuclock,
      clock                           => clk_1Mhz,
      ce_1m				=> clk_1MHz_en,
      reset					=> reset_drive,
      Freq_lo				=> Voice_3_Freq_lo,
      Freq_hi				=> Voice_3_Freq_hi,
      Pw_lo					=> Voice_3_Pw_lo,
      Pw_hi					=> Voice_3_Pw_hi,
      Control				=> Voice_3_Control,
      Att_dec				=> Voice_3_Att_dec,
      Sus_Rel				=> Voice_3_Sus_Rel,
      osc_MSB_in			=> voice_2_PA_MSB_8580,
      osc_MSB_out			=> voice_3_PA_MSB_8580,
      sawtooth                        => voice_3_sawtooth_8580,
      triangle                        => voice_3_triangle_8580,
      st_out                          => voice_3_st_out_8580,
      p_t_out                         => voice_3_p_t_out_8580,
      ps_out                         => voice_3_ps_out_8580,
      pst_out                         => voice_3_pst_out_8580,
      Osc_out					=> Misc_Osc3_Random_8580,
      Env_out					=> Misc_Env3_8580,
      signal_out					=> voice_3_8580
      );
  
  
  
-------------------------------------------------------------------------------------
  
-- SID filters
  
  process (do_buf,cs,addr,pot_x,pot_y,Misc_Osc3_Random,Misc_Env3)
  begin
    -- Tristate data lines
    if cs='1' then
      -- Read from SID-register
      -------------------------
      case addr is
        -- @IO:GS $D419 SID:PADDLE1 Analog/Digital Converter: Game Paddle 1 (0-255)
        -- @IO:GS $D41A SID:PADDLE2 Analog/Digital Converter Game Paddle 2 (0-255)
        -- @IO:GS $D41B SID:OSC3RNG Oscillator 3 Random Number Generator
        -- @IO:GS $D41C SID:ENV3OUT Envelope Generator 3 Output
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
  
  
  process (cpuclock,reset_drive)
  begin
    if reset_drive='1' then
      ff1<='0';
    else
      if rising_edge(cpuclock) then
        last_clk_1mhz <= clk_1mhz;
        if clk_1Mhz /= last_clk_1mhz then
          ff1<=not ff1;
        end if;
      end if;
    end if;
  end process;
  
  process(cpuclock)
  begin
    if rising_edge(cpuclock) then
      reset_drive <= reset;
      tick_q1 <= ff1;
      tick_q2 <= tick_q1;
      
      if sid_table_state /= 15 then
        sid_table_state <= sid_table_state + 1;
      else
        sid_table_state <= 0;
      end if;
      case sid_table_state is
        when 1  => f_sawtooth <= voice_1_sawtooth_8580; f_triangle <= voice_1_triangle_8580;
        when 3  => voice_1_st_out_8580 <= f_st_out;
                   voice_1_p_t_out_8580 <= f_p_t_out;
                   voice_1_ps_out_8580 <= f_ps_out;
                   voice_1_pst_out_8580 <= f_pst_out;
        when 5  => f_sawtooth <= voice_2_sawtooth_8580; f_triangle <= voice_2_triangle_8580;
        when 7  => voice_2_st_out_8580 <= f_st_out;
                   voice_2_p_t_out_8580 <= f_p_t_out;
                   voice_2_ps_out_8580 <= f_ps_out;
                   voice_2_pst_out_8580 <= f_pst_out;
        when 9  => f_sawtooth <= voice_3_sawtooth_8580; f_triangle <= voice_3_triangle_8580;
        when 11 => voice_3_st_out_8580 <= f_st_out;
                   voice_3_p_t_out_8580 <= f_p_t_out;
                   voice_3_ps_out_8580 <= f_ps_out;
                   voice_3_pst_out_8580 <= f_pst_out;
        when others => null;
      end case;
    end if;
  end process;
  
  input_valid <= '1' when tick_q1 /=tick_q2 else '0';
  
  
  voice1_signed <= signed("0" & voice_1) - 2048 when mode='0' else signed("0" & voice_1_8580) - 2048;
  voice2_signed <= signed("0" & voice_2) - 2048 when mode='0' else signed("0" & voice_2_8580) - 2048;
  voice3_signed <= signed("0" & voice_3) - 2048 when mode='0' else signed("0" & voice_3_8580) - 2048;
  
  misc_osc3_random <= misc_osc3_random_6581 when mode='0' else misc_osc3_random_8580;
  misc_env3 <= misc_env3_6581 when mode='0' else misc_env3_8580;
  
  filters: entity work.sid_filters 
    port map (
      clk			=> cpuclock,
      rst			=> reset_drive,
      mode                    => mode,
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
      valid			=> open,
      
      filter_table_addr       => filter_table_addr,
      filter_table_val        => filter_table_val
      );
  
  unsigned_filt 	<= unsigned(filtered_audio + "1000000000000000000");
  unsigned_audio	<= unsigned_filt(18 downto 1);
  audio_data		<= unsigned_audio;
  
  signed_audio	<= filtered_audio(18 downto 1);
  
-- Register decoding
  register_decoder:process(cpuclock)
  begin
    if rising_edge(cpuclock) then
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
                -- @IO:GS $D400 SID:VOICE1!FRQLO@VOICEX!FRQLO Voice X Frequency Low
                -- @IO:GS $D401 SID:VOICE1!FRQHI@VOICEX!FRQHI Voice X Frequency High
                -- @IO:GS $D402 SID:VOICE1!PWLO@VOICEX!PWLO Voice X Pulse Waveform Width Low
                -- @IO:GS $D403.0-3 SID:VOICE1!PWHI@VOICEX!PWHI Voice X Pulse Waveform Width High
                -- @IO:GS $D403.4-7 SID:VOICE1!UNSD@VOICEX!UNSD Unused
                -- @IO:GS $D404.7 SID:VOICE1!CTRLRNW@VOICEX!CTRLRNW Voice X Control Random Noise Waveform
                -- @IO:GS $D404.6 SID:VOICE1!CTRLPUL@VOICEX!CTRLPUL Voice X Pulse Waveform
                -- @IO:GS $D404.5 SID:VOICE1!CTRLSAW@VOICEX!CTRLSAW Voice X Sawtooth Waveform
                -- @IO:GS $D404.4 SID:VOICE1!CTRLTRI@VOICEX!CTRLTRI Voice X Triangle Waveform
                -- @IO:GS $D404.3 SID:VOICE1!CTRLTST@VOICEX!CTRLTST Voice X Test Bit - Disable Oscillator
                -- @IO:GS $D404.2 SID:VOICE1!CTRLRMO Voice 1 Ring Modulate Osc. 1 with Osc. 3 Output
                -- @IO:GS $D404.1 SID:VOICE1!CTRLRMF Voice 1 Synchronize Osc. 1 with Osc. 3 Frequency
                -- @IO:GS $D404.0 SID:VOICE1!CTRLGATE@VOICEX!CTRLGATE Voice X Gate Bit (1 = Start, 0 = Release)
                -- @IO:GS $D405.7-4 SID:ENV1!ATTDUR@ENVX!ATTDUR Envelope Generator X Attack Cycle Duration
                -- @IO:GS $D405.3-0 SID:ENV1!DECDUR@ENVX!DECDUR Envelope Generator X Decay Cycle Duration
                -- @IO:GS $D406.7-4 SID:ENV1!SUSDUR@ENVX!SUSDUR Envelope Generator X Sustain Cycle Duration
                -- @IO:GS $D406.3-0 SID:ENV1!RELDUR@ENVX!RELDUR Envelope Generator X Release Cycle Duration
                -- @IO:GS $D407 SID:VOICE2!FRQLO @VOICEX!FRQLO
                -- @IO:GS $D408 SID:VOICE2!FRQHI @VOICEX!FRQHI
                -- @IO:GS $D409 SID:VOICE2!PWLO @VOICEX!PWLO
                -- @IO:GS $D40A.0-3 SID:VOICE2!PWHI @VOICEX!PWHI
                -- @IO:GS $D40A.4-7 SID:VOICE2!UNSD @VOICEX!UNSD
                -- @IO:GS $D40B.7 SID:VOICE2!CTRLRNW @VOICEX!CTRLRNW
                -- @IO:GS $D40B.6 SID:VOICE2!CTRLPUL @VOICEX!CTRLPUL
                -- @IO:GS $D40B.5 SID:VOICE2!CTRLSAW @VOICEX!CTRLSAW
                -- @IO:GS $D40B.4 SID:VOICE2!CTRLTRI @VOICEX!CTRLTRI
                -- @IO:GS $D40B.3 SID:VOICE2!CTRLTST @VOICEX!CTRLTST
                -- @IO:GS $D40B.2 SID:VOICE2!CTRLRMO Voice 2 Ring Modulate Osc. 2 with Osc. 1 Output
                -- @IO:GS $D40B.1 SID:VOICE2!CTRLRMF Voice 2 Synchronize Osc. 2 with Osc. 1 Frequency
                -- @IO:GS $D40B.0 SID:VOICE2!CTRLGATE @VOICEX!CTRLGATE
                -- @IO:GS $D40C.7-4 SID:ENV2!ATTDUR @ENVX!ATTDUR
                -- @IO:GS $D40C.3-0 SID:ENV2!DECDUR @ENVX!DECDUR
                -- @IO:GS $D40D.7-4 SID:ENV2!SUSDUR @ENVX!SUSDUR
                -- @IO:GS $D40D.3-0 SID:ENV2!RELDUR @ENVX!RELDUR
                -- @IO:GS $D40E SID:VOICE3!FRQLO @VOICEX!FRQLO
                -- @IO:GS $D40F SID:VOICE3!FRQHI @VOICEX!FRQHI
                -- @IO:GS $D410 SID:VOICE3!PWLO @VOICEX!PWLO
                -- @IO:GS $D411.0-3 SID:VOICE3!PWHI @VOICEX!PWHI
                -- @IO:GS $D411.4-7 SID:VOICE3!UNSD @VOICEX!UNSD
                -- @IO:GS $D412.7 SID:VOICE3!CTRLRNW @VOICEX!CTRLRNW
                -- @IO:GS $D412.6 SID:VOICE3!CTRLPUL @VOICEX!CTRLPUL
                -- @IO:GS $D412.5 SID:VOICE3!CTRLSAW @VOICEX!CTRLSAW
                -- @IO:GS $D412.4 SID:VOICE3!CTRLTRI @VOICEX!CTRLTRI
                -- @IO:GS $D412.3 SID:VOICE3!CTRLTST @VOICEX!CTRLTST
                -- @IO:GS $D412.2 SID:VOICE3!CTRLRMO Voice 3 Ring Modulate Osc. 3 with Osc. 2 Output
                -- @IO:GS $D412.1 SID:VOICE3!CTRLRMF Voice 3 Synchronize Osc. 3 with Osc. 2 Frequency
                -- @IO:GS $D412.0 SID:VOICE3!CTRLGATE @VOICEX!CTRLGATE
                -- @IO:GS $D413.7-4 SID:ENV3!ATTDUR @ENVX!ATTDUR
                -- @IO:GS $D413.3-0 SID:ENV3!DECDUR @ENVX!DECDUR
                -- @IO:GS $D414.7-4 SID:ENV3!SUSDUR @ENVX!SUSDUR
                -- @IO:GS $D414.3-0 SID:ENV3!RELDUR @ENVX!RELDUR
                -- @IO:GS $D415 SID:FLTR!CUTFRQLO@FLTR!CUTFRQLO Filter Cutoff Frequency Low
                -- @IO:GS $D416 SID:FLTR!CUTFRQHI@FLTR!CUTFRQHI Filter Cutoff Frequency High
                -- @IO:GS $D417.7-4 SID:FLTR!RESON@FLTR!RESON Filter Resonance
                -- @IO:GS $D417.3 SID:FLTR!EXTINP@FLTR!EXTINP Filter External Input
                -- @IO:GS $D417.2 SID:FLTR!V1OUT@FLTR!VXOUT Filter Voice X Output
                -- @IO:GS $D417.1 SID:FLTR!V2OUT @FLTR!VXOUT
                -- @IO:GS $D417.0 SID:FLTR!V3OUT @FLTR!VXOUT
                -- @IO:GS $D418.7 SID:FLTR!CUTV3 Filter Cut-Off Voice 3 Output (1 = off)
                -- @IO:GS $D418.6 SID:FLTR!HIPASS Filter High-Pass Mode
                -- @IO:GS $D418.5 SID:FLTR!BDPASS Filter Band-Pass Mode
                -- @IO:GS $D418.4 SID:FLTR!LOPASS Filter Low-Pass Mode
                -- @IO:GS $D418.0-3 SID:FLTR!VOL Filter Output Volume

                                    -------------------------------------- Voice-1
              when "00000" =>	Voice_1_Freq_lo	<= di;
              when "00001" =>	Voice_1_Freq_hi	<= di;
              when "00010" =>	Voice_1_Pw_lo		<= di;
              when "00011" =>	Voice_1_Pw_hi		<= di;
              when "00100" =>	Voice_1_Control	<= di;
              when "00101" =>	Voice_1_Att_dec	<= di;
              when "00110" =>	Voice_1_Sus_Rel	<= di;
                                        --------------------------------------- Voice-2
              when "00111" =>	Voice_2_Freq_lo	<= di;
              when "01000" =>	Voice_2_Freq_hi	<= di;
              when "01001" =>	Voice_2_Pw_lo		<= di;
              when "01010" =>	Voice_2_Pw_hi		<= di;
              when "01011" =>	Voice_2_Control	<= di;
              when "01100" =>	Voice_2_Att_dec	<= di;
              when "01101" =>	Voice_2_Sus_Rel	<= di;
                                        --------------------------------------- Voice-3
              when "01110" =>	Voice_3_Freq_lo	<= di;
              when "01111" =>	Voice_3_Freq_hi	<= di;
              when "10000" =>	Voice_3_Pw_lo		<= di;
              when "10001" =>	Voice_3_Pw_hi		<= di;
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
