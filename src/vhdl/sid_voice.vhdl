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

entity sid_voice is
  port (
    cpuclock : in std_logic;
    clk_1MHz			: in	std_logic;							-- this line drives the oscilator
    reset				: in	std_logic;							-- active high signal (i.e. registers are reset when reset=1)
    Freq_lo			: in	unsigned(7 downto 0);	-- low-byte of frequency register 
    Freq_hi			: in	unsigned(7 downto 0);	-- high-byte of frequency register 
    Pw_lo				: in	unsigned(7 downto 0);	-- low-byte of PuleWidth register
    Pw_hi				: in	unsigned(7 downto 0);	-- high-nibble of PuleWidth register
    Control			: in	unsigned(7 downto 0);	-- control register
    Att_dec			: in	unsigned(7 downto 0);	-- attack-deccay register
    Sus_Rel			: in	unsigned(7 downto 0);	-- sustain-release register
    PA_MSB_in		: in	std_logic;							-- Phase Accumulator MSB input
    PA_MSB_out		: out	std_logic;							-- Phase Accumulator MSB output
    Osc				: out	unsigned(7 downto 0);	-- Voice waveform register
    Env				: out	unsigned(7 downto 0);	-- Voice envelope register
    voice				: out	unsigned(11 downto 0)	-- Voice waveform, this is the actual audio signal
    );
end sid_voice;

architecture Behavioral of sid_voice is	
  
-------------------------------------------------------------------------------
--	Altera multiplier
--	COMPONENT lpm_mult
--	GENERIC
--	(
--		lpm_hint		: STRING;
--		lpm_representation		: STRING;
--		lpm_type		: STRING;
--		lpm_widtha		: NATURAL;
--		lpm_widthb		: NATURAL;
--		lpm_widthp		: NATURAL;
--		lpm_widths		: NATURAL
--	);
--	PORT 
--	(
--		dataa		: IN	UNSIGNED (11 DOWNTO 0);
--		datab		: IN	UNSIGNED (7 DOWNTO 0);
--		result	: OUT	UNSIGNED (19 DOWNTO 0)
--	);
--	END COMPONENT;
  
-------------------------------------------------------------------------------
  
  signal	accumulator					: unsigned(23 downto 0) := (others => '0');
  signal	accu_bit_prev				: std_logic := '0';
  signal	PA_MSB_in_prev				: std_logic := '0';
  
  -- this type of signal has only two states 0 or 1 (so no more bits are required)
  signal	pulse							: std_logic := '0';
  signal	sawtooth						: unsigned(11 downto 0) := (others => '0');
  signal	triangle						: unsigned(11 downto 0) := (others => '0');
  signal	noise							: unsigned(11 downto 0) := (others => '0');
  signal	LFSR							: unsigned(22 downto 0) := (others => '0');
  
  signal 	frequency					: unsigned(15 downto 0) := (others => '0');
  signal 	pulsewidth					: unsigned(11 downto 0) := (others => '0');
  
  -- Envelope Generator
  type		envelope_state_types is 	(idle, attack, attack_lp, decay, decay_lp, sustain, release, release_lp);
  signal 	cur_state, next_state	: envelope_state_types; 
  signal 	divider_value				: integer range 0 to 2**15 - 1 :=0;
  signal 	divider_attack				: integer range 0 to 2**15 - 1 :=0;
  signal 	divider_dec_rel			: integer range 0 to 2**15 - 1 :=0;
  signal 	divider_counter			: integer range 0 to 2**18 - 1 :=0;
  signal 	exp_table_value			: integer range 0 to 2**18 - 1 :=0;
  signal 	exp_table_active			: std_logic := '0';
  signal 	divider_rst 				: std_logic := '0';
  signal	Dec_rel						: unsigned(3 downto 0) := (others => '0');
  signal	Dec_rel_sel					: std_logic := '0';
  
  signal	env_counter					: unsigned(7 downto 0) := (others => '0');
  signal 	env_count_hold_A			: std_logic := '0';
  signal	env_count_hold_B			: std_logic := '0';
  signal	env_cnt_up					: std_logic := '0';
  signal	env_cnt_clear				: std_logic := '0';
  
  signal	signal_clamp_max			        : unsigned(11 downto 0) := (others => '0');
  signal	signal_mux_clamped			        : unsigned(11 downto 0) := (others => '0');
  signal	signal_mux_last					: unsigned(11 downto 0) := (others => '0');
  signal	signal_mux					: unsigned(11 downto 0) := (others => '0');
  signal	signal_vol					: unsigned(19 downto 0) := (others => '0');
  
  -------------------------------------------------------------------------------------
  
  -- stop the oscillator when test = '1'
  alias		test							: std_logic is Control(3);
  -- Ring Modulation was accomplished by substituting the accumulator MSB of an
  -- oscillator in the EXOR function of the triangle waveform generator with the
  -- accumulator MSB of the previous oscillator. That is why the triangle waveform
  -- must be selected to use Ring Modulation.
  alias		ringmod						: std_logic is Control(2);
  -- Hard Sync was accomplished by clearing the accumulator of an Oscillator
  -- based on the accumulator MSB of the previous oscillator.
  alias		sync							: std_logic is Control(1);
  --
  
  -- We have to latch GATE if the CPU is running at >1MHz, to make sure
  -- it doesn't get missed
  signal		gate          : std_logic;
  signal		last_gate     : std_logic;
  signal		gate_edge     : std_logic;
  signal                last_clk_1mhz : std_logic;
  
-------------------------------------------------------------------------------------
  
begin
  
  -- output the Phase accumulator's MSB for sync and ringmod purposes
  PA_MSB_out					<= accumulator(23);
  -- output the upper 8-bits of the waveform.
  -- Useful for random numbers (noise must be selected)
  Osc							<= signal_mux(11 downto 4);
  -- output the envelope register, for special sound effects when connecting this
  -- signal to the input of other channels/voices
  Env							<= env_counter;
  -- use the register value to fill the variable
  frequency	<= Freq_hi & Freq_lo;
  -- use the register value to fill the variable
  pulsewidth 	<= Pw_hi(3 downto 0) & Pw_lo;
  --
  voice							<= signal_vol(19 downto 8);
  
  -- Phase accumulator :
  -- "As I recall, the Oscillator is a 24-bit phase-accumulating design of which
  -- the lower 16-bits are programmable for pitch control. The output of the
  -- accumulator goes directly to a D/A converter through a waveform selector.
  -- Normally, the output of a phase-accumulating oscillator would be used as an
  -- address into memory which contained a wavetable, but SID had to be entirely
  -- self-contained and there was no room at all for a wavetable on the chip."
  -- "Hard Sync was accomplished by clearing the accumulator of an Oscillator
  -- based on the accumulator MSB of the previous oscillator."
  PhaseAcc:process(cpuclock)
  begin
    
    if rising_edge(cpuclock) then
      -- Catch short edges of gate when CPU >1MHz
      gate <= Control(0);
      last_gate <= gate;
      if gate='1' and last_gate='0' then
        gate_edge <= '1';
      end if;
      
      last_clk_1mhz <= clk_1mhz;
      if clk_1Mhz='1' and last_clk_1mhz='0' then
        
        PA_MSB_in_prev <= PA_MSB_in;
        -- the reset and test signal can stop the oscillator,
        -- stopping the oscillator is very useful when you want to play "samples"
        if ((reset = '1') or (test = '1') or ((sync = '1') and (PA_MSB_in_prev /= PA_MSB_in) and (PA_MSB_in = '0'))) then
          accumulator <= (others => '0');
        else
          -- accumulate the new phase (i.o.w. increment env_counter with the freq. value)
          accumulator <= accumulator + ("0" & frequency);
        end if;
        
        -----------------------------------------------------------------------------------------------------------------
        -- Waveform generators
        -----------------------------------------------------------------------------------------------------------------
        
        -- Sawtooth waveform :
        -- "The Sawtooth waveform was created by sending the upper 12-bits of the
        -- accumulator to the 12-bit Waveform D/A."
        sawtooth	<= accumulator(23 downto 12);
        
        --Pulse waveform :
        -- "The Pulse waveform was created by sending the upper 12-bits of the
        -- accumulator to a 12-bit digital comparator. The output of the comparator was
        -- either a one or a zero. This single output was then sent to all 12 bits of
        -- the Waveform D/A. "
        if ((accumulator(23 downto 12)) >= pulsewidth) then
          pulse <= '1';
        else
          pulse <= '0';
        end if;
        
	--Triangle waveform :
	-- "The Triangle waveform was created by using the MSB of the accumulator to
	-- invert the remaining upper 11 accumulator bits using EXOR gates. These 11
	-- bits were then left-shifted (throwing away the MSB) and sent to the Waveform
	-- D/A (so the resolution of the triangle waveform was half that of the sawtooth,
	-- but the amplitude and frequency were the same). "
	-- "Ring Modulation was accomplished by substituting the accumulator MSB of an
	-- oscillator in the EXOR function of the triangle waveform generator with the
	-- accumulator MSB of the previous oscillator. That is why the triangle waveform
	-- must be selected to use Ring Modulation."
        if ringmod = '0' then	
          -- no ringmodulation
          triangle(11)<= accumulator(23) xor accumulator(22);
          triangle(10)<= accumulator(23) xor accumulator(21);
          triangle(9)	<= accumulator(23) xor accumulator(20);
          triangle(8)	<= accumulator(23) xor accumulator(19);
          triangle(7)	<= accumulator(23) xor accumulator(18);
          triangle(6)	<= accumulator(23) xor accumulator(17);
          triangle(5)	<= accumulator(23) xor accumulator(16);
          triangle(4)	<= accumulator(23) xor accumulator(15);
          triangle(3)	<= accumulator(23) xor accumulator(14);
          triangle(2)	<= accumulator(23) xor accumulator(13);
          triangle(1)	<= accumulator(23) xor accumulator(12);
          triangle(0)	<= accumulator(23) xor accumulator(11);
        else
          -- ringmodulation by the other voice (previous voice)
          triangle(11)<= PA_MSB_in xor accumulator(22);
          triangle(10)<= PA_MSB_in xor accumulator(21);
          triangle(9)	<= PA_MSB_in xor accumulator(20);
          triangle(8)	<= PA_MSB_in xor accumulator(19);
          triangle(7)	<= PA_MSB_in xor accumulator(18);
          triangle(6)	<= PA_MSB_in xor accumulator(17);
          triangle(5)	<= PA_MSB_in xor accumulator(16);
          triangle(4)	<= PA_MSB_in xor accumulator(15);
          triangle(3)	<= PA_MSB_in xor accumulator(14);
          triangle(2)	<= PA_MSB_in xor accumulator(13);
          triangle(1)	<= PA_MSB_in xor accumulator(12);
          triangle(0)	<= PA_MSB_in xor accumulator(11);
        end if;
        
        --Noise (23-bit Linear Feedback Shift Register, max combinations = 8388607) :
        -- "The Noise waveform was created using a 23-bit pseudo-random sequence
        -- generator (i.e., a shift register with specific outputs fed back to the input
        -- through combinatorial logic). The shift register was clocked by one of the
        -- intermediate bits of the accumulator to keep the frequency content of the
        -- noise waveform relatively the same as the pitched waveforms.
        -- The upper 12-bits of the shift register were sent to the Waveform D/A."
        noise	<= LFSR(22 downto 11);
        -- the test signal can stop the oscillator,
        -- stopping the oscillator is very useful when you want to play "samples"
        if ((reset = '1') or (test = '1')) or LFSR = "00000000000000000000000" then
          accu_bit_prev		<= '0';
          -- the "seed" value (the value that eventually determines the output
          -- pattern) may never be '0' otherwise the generator "locks up"
          LFSR	<= "00000000000000000000001";
        else
          accu_bit_prev	<= accumulator(19);
          -- when not equal to ...
          if	(accu_bit_prev /= accumulator(19)) then
            LFSR(22 downto 1)	<= LFSR(21 downto 0);
            LFSR(0) 					<= LFSR(17) xor LFSR(22);  -- see Xilinx XAPP052 for maximal LFSR taps
          else
            LFSR	 						<= LFSR;
          end if;
        end if;
        
        -- Waveform Output selector (MUX):
        -- "Since all of the waveforms were just digital bits, the Waveform Selector
        -- consisted of multiplexers that selected which waveform bits would be sent
        -- to the Waveform D/A. The multiplexers were single transistors and did not
        -- provide a "lock-out", allowing combinations of the waveforms to be selected.
        -- The combination was actually a logical ANDing of the bits of each waveform,
        -- which produced unpredictable results, so I didn't encourage this, especially
        -- since it could lock up the pseudo-random sequence generator by filling it
        -- with zeroes."
        signal_mux(11) <= (triangle(11) and Control(4)) or (sawtooth(11) and Control(5)) or (pulse and Control(6)) or (noise(11) and Control(7));
        signal_mux(10) <= (triangle(10) and Control(4)) or (sawtooth(10) and Control(5)) or (pulse and Control(6)) or (noise(10) and Control(7));
        signal_mux(9)  <= (triangle(9)  and Control(4)) or (sawtooth(9)  and Control(5)) or (pulse and Control(6)) or (noise(9)  and Control(7));
        signal_mux(8)  <= (triangle(8)  and Control(4)) or (sawtooth(8)  and Control(5)) or (pulse and Control(6)) or (noise(8)  and Control(7));
        signal_mux(7)  <= (triangle(7)  and Control(4)) or (sawtooth(7)  and Control(5)) or (pulse and Control(6)) or (noise(7)  and Control(7));
        signal_mux(6)  <= (triangle(6)  and Control(4)) or (sawtooth(6)  and Control(5)) or (pulse and Control(6)) or (noise(6)  and Control(7));
        signal_mux(5)  <= (triangle(5)  and Control(4)) or (sawtooth(5)  and Control(5)) or (pulse and Control(6)) or (noise(5)  and Control(7));
        signal_mux(4)  <= (triangle(4)  and Control(4)) or (sawtooth(4)  and Control(5)) or (pulse and Control(6)) or (noise(4)  and Control(7));
        signal_mux(3)  <= (triangle(3)  and Control(4)) or (sawtooth(3)  and Control(5)) or (pulse and Control(6)) or (noise(3)  and Control(7));
        signal_mux(2)  <= (triangle(2)  and Control(4)) or (sawtooth(2)  and Control(5)) or (pulse and Control(6)) or (noise(2)  and Control(7));
        signal_mux(1)  <= (triangle(1)  and Control(4)) or (sawtooth(1)  and Control(5)) or (pulse and Control(6)) or (noise(1)  and Control(7));
        signal_mux(0)  <= (triangle(0)  and Control(4)) or (sawtooth(0)  and Control(5)) or (pulse and Control(6)) or (noise(0)  and Control(7));
        
        -----------------------------------------------------------------------------------------------------------------
        -- Waveform envelope (volume) control
        -----------------------------------------------------------------------------------------------------------------
        -- Waveform envelope (volume) control :
        -- "The output of the Waveform D/A (which was an analog voltage at this point)
        -- was fed into the reference input of an 8-bit multiplying D/A, creating a DCA
        -- (digitally-controlled-amplifier). The digital control word which modulated
        -- the amplitude of the waveform came from the Envelope Generator."
        -- "The 8-bit output of the Envelope Generator was then sent to the Multiplying
        -- D/A converter to modulate the amplitude of the selected Oscillator Waveform
        -- (to be technically accurate, actually the waveform was modulating the output
        -- of the Envelope Generator, but the result is the same)."
        
        -- Calculate a clamped maximum value for the channel based on
        -- a 4ms rise time, and instant clamp to zero when a voice is
        -- disabled. This is to stop voices coming in too fast and making
        -- an audible click.  Not really sure how the same effect occurs
        -- in a real SID. Maybe the D/A being analog has a slow response
        -- as well?  PGS 20181119
        if Control(7 downto 4) /= "0000" then
          -- Channel has a waveform, so slowly increase clamp value
          if signal_clamp_max /= "111111111111" then
            signal_clamp_max <= signal_clamp_max + 1;
          end if;
          -- If the value is less than the clamp, let it through, or
          -- else clamp it.
          if signal_mux < signal_clamp_max then
            signal_mux_clamped <= signal_mux;
            signal_mux_last <= signal_mux;
          else
            signal_mux_clamped <= signal_clamp_max;
            signal_mux_last <= signal_clamp_max;
          end if;
        else
          -- If channel is turned off, then sink clamp value,
          -- and decay over 4ms the last value we produced
          if signal_mux_last /= "000000000000" then
            signal_mux_last <= signal_mux_last - 1;
          end if;
          signal_clamp_max <= signal_mux_last;
          signal_mux_clamped <= signal_mux_last;
        end if;
        
        --calculate the resulting volume (due to the envelope generator) of the
        --voice, signal_mux(12bit) * env_counter(8bit), so the result will
        --require 20 bits !!
        signal_vol	<= signal_mux_clamped * env_counter;
        
        -----------------------------------------------------------------------------------------------------------------
        -- Envelope Generator
        -----------------------------------------------------------------------------------------------------------------
        -- Envelope generator :
        -- "The Envelope Generator was simply an 8-bit up/down counter which, when
        -- triggered by the Gate bit, counted from 0 to 255 at the Attack rate, from
        -- 255 down to the programmed Sustain value at the Decay rate, remained at the
        -- Sustain value until the Gate bit was cleared then counted down from the
        -- Sustain value to 0 at the Release rate."
        --
        --		      /\
        --		     /  \ 
        --		    / |  \________
        --		   /  |   |       \
        --		  /   |   |       |\
        --		 /    |   |       | \
        --		attack|dec|sustain|rel
        
        -- this process controls the state machine "current-state"-value
        cur_state <= next_state;
        
        env_cnt_clear	 		<='0';		-- use this statement unless stated otherwise
        env_cnt_up				<='1';		-- use this statement unless stated otherwise
        env_count_hold_B	<='1';		-- use this statement unless stated otherwise
        divider_rst 			<='0';		-- use this statement unless stated otherwise
        divider_value 		<= 0;			-- use this statement unless stated otherwise
        exp_table_active 	<='0';		-- use this statement unless stated otherwise
        case cur_state is
          
          -- IDLE
          when idle =>
            env_cnt_clear 		<= '1';		-- clear envelope env_counter
            divider_rst 			<= '1';
            Dec_rel_sel				<= '0';		-- select decay as input for decay/release table
            if gate_edge = '1' or gate='1' then
              next_state			<= attack;
              gate_edge <= '0';
            else
              next_state 			<= idle;
            end if;
            
          when attack =>
            env_cnt_clear			<= '1';			-- clear envelope env_counter
            divider_rst 			<= '1';
            divider_value 		<= divider_attack;
            next_state 				<= attack_lp;
            Dec_rel_sel				<= '0';			-- select decay as input for decay/release table
            
          when attack_lp =>
            env_count_hold_B 	<= '0';		-- enable envelope env_counter
            env_cnt_up 				<= '1';		-- envelope env_counter must count up (increment)
            divider_value 		<= divider_attack;
            Dec_rel_sel				<= '0';		-- select decay as input for decay/release table
            if env_counter = "11111111" then
              next_state			<= decay;
            else
              if gate = '0' and gate_edge='0' then
                next_state		<= release;
              else
                next_state		<= attack_lp;
              end if;
            end if;
            
          when decay =>
            divider_rst 			<= '1';
            exp_table_active 	<= '1';		-- activate exponential look-up table
            env_cnt_up	 			<= '0';		-- envelope env_counter must count down (decrement)
            divider_value 		<= divider_dec_rel;
            next_state 				<= decay_lp;
            Dec_rel_sel				<= '0';		-- select decay as input for decay/release table
            
          when decay_lp =>
            exp_table_active 	<= '1';		-- activate exponential look-up table
            env_count_hold_B 	<= '0';		-- enable envelope env_counter
            env_cnt_up 				<= '0';		-- envelope env_counter must count down (decrement)
            divider_value 		<= divider_dec_rel;
            Dec_rel_sel				<= '0';		-- select decay as input for decay/release table
            if (env_counter(7 downto 4) = Sus_Rel(7 downto 4)) then
              next_state 			<= sustain;
            else
              if gate = '0' and gate_edge='0' then
                next_state		<= release;
              else
                next_state		<= decay_lp;
              end if;
            end if;
            
          -- "A digital comparator was used for the Sustain function. The upper
          -- four bits of the Up/Down counter were compared to the programmed
          -- Sustain value and would stop the clock to the Envelope Generator when
          -- the counter counted down to the Sustain value. This created 16 linearly
          -- spaced sustain levels without havingto go through a look-up table
          -- translation between the 4-bit register value and the 8-bit Envelope
          -- Generator output. It also meant that sustain levels were adjustable
          -- in steps of 16. Again, more register bits would have provided higher
          -- resolution."
          -- "When the Gate bit was cleared, the clock would again be enabled,
          -- allowing the counter to count down to zero. Like an analog envelope
          -- generator, the SID Envelope Generator would track the Sustain level
          -- if it was changed to a lower value during the Sustain portion of the
          -- envelope, however, it would not count UP if the Sustain level were set
          -- higher." Instead it would count down to '0'.
          when sustain =>
            divider_value 		<= 0;
            Dec_rel_sel				<='1';			-- select release as input for decay/release table
            if gate = '0' and gate_edge='0' then	
              next_state 			<= release;
            else
              if (env_counter(7 downto 4) = Sus_Rel(7 downto 4)) then
                next_state 		<= sustain;
              else
                next_state 		<= decay;
              end if;
            end  if;
            
          when release =>
            divider_rst 			<= '1';
            exp_table_active 	<= '1';		-- activate exponential look-up table
            env_cnt_up	 			<= '0';		-- envelope env_counter must count down (decrement)
            divider_value 		<= divider_dec_rel;
            Dec_rel_sel				<= '1';		-- select release as input for decay/release table
            next_state 				<= release_lp;
            
          when release_lp =>
            exp_table_active 	<= '1';		-- activate exponential look-up table
            env_count_hold_B 	<= '0';		-- enable envelope env_counter
            env_cnt_up	 			<= '0';		-- envelope env_counter must count down (decrement)
            divider_value 		<= divider_dec_rel;
            Dec_rel_sel				<= '1';		-- select release as input for decay/release table
            if env_counter = "00000000" then
              next_state 			<= idle;
            else
              if gate = '1' or gate_edge='1' then
                next_state 		<= idle;
              else
                next_state		<= release_lp;
              end if;
            end if;
            
          when others =>
            divider_value 	<= 0;
            Dec_rel_sel			<= '0';		-- select decay as input for decay/release table
            next_state			<= idle;	
        end case;
        
        -- this controls the envelope (in other words, the volume control)
        -- 8 bit up/down env_counter
        if ((env_count_hold_A = '1') or (env_count_hold_B = '1'))then
          env_counter <= env_counter;			
        else
          if (env_cnt_up = '1') then
            if env_counter /= "11111111" then
              env_counter <= env_counter + 1;
            end if;
          else
            if env_counter /= "00000000" then
              env_counter <= env_counter - 1;
            end if;
          end if;
        end if;
        
        -----------------------------------------------------------------------------------------------------------------
        -- Divider
        -----------------------------------------------------------------------------------------------------------------
        -- "A programmable frequency divider was used to set the various rates
        -- (unfortunately I don't remember how many bits the divider was, either 12
        -- or 16 bits). A small look-up table translated the 16 register-programmable
        -- values to the appropriate number to load into the frequency divider.
        -- Depending on what state the Envelope Generator was in (i.e. ADS or R), the
        -- appropriate register would be selected and that number would be translated
        -- and loaded into the divider. Obviously it would have been better to have
        -- individual bit control of the divider which would have provided great
        -- resolution for each rate, however I did not have enough silicon area for a
        -- lot of register bits. Using this approach, I was able to cram a wide range
        -- of rates into 4 bits, allowing the ADSR to be defined in two bytes instead
        -- of eight. The actual numbers in the look-up table were arrived at
        -- subjectively by setting up typical patches on a Sequential Circuits Pro-1
        -- and measuring the envelope times by ear (which is why the available rates
        -- seem strange)!"
        if (divider_counter = 0) then
          env_count_hold_A 	<= '0';
          if (exp_table_active = '1') then
            divider_counter	<= exp_table_value;
          else
            divider_counter	<= divider_value;
          end if;
        else
          env_count_hold_A	<= '1';					
          divider_counter	<= divider_counter - 1;
        end if;
        
        -- Piese-wise linear approximation of an exponential :
        -- "In order to more closely model the exponential decay of sounds, another
        -- look-up table on the output of the Envelope Generator would sequentially
        -- divide the clock to the Envelope Generator by two at specific counts in the
        -- Decay and Release cycles. This created a piece-wise linear approximation of
        -- an exponential. I was particularly happy how well this worked considering
        -- the simplicity of the circuitry. The Attack, however, was linear, but this
        -- sounded fine."
        -- The clock is divided by two at specific values of the envelope generator to
        -- create an exponential.  
        case to_integer(env_counter) is
          when   0 to  51 =>	exp_table_value <= divider_value * 16;
          when  52 to 101 =>	exp_table_value <= divider_value * 8;
          when 102 to 152 =>	exp_table_value <= divider_value * 4;
          when 153 to 203 =>	exp_table_value <= divider_value * 2;
          when 204 to 255 =>	exp_table_value <= divider_value;
          when others			=>	exp_table_value <= divider_value;
        end case;
        
        -- Attack Lookup table :
        -- It takes 255 clock cycles from zero to peak value. Therefore the divider
        -- equals (attack rate / clockcycletime of 1MHz clock) / 254; 
        case Att_dec(7 downto 4) is
          when "0000"	=>	divider_attack <= 8;			--attack rate: (   2mS / 1uS per clockcycle) /254 steps
          when "0001" =>	divider_attack <= 31;			--attack rate: (   8mS / 1uS per clockcycle) /254 steps
          when "0010" =>	divider_attack <= 63;			--attack rate: (  16mS / 1uS per clockcycle) /254 steps
          when "0011" =>	divider_attack <= 94;			--attack rate: (  24mS / 1uS per clockcycle) /254 steps
          when "0100" =>	divider_attack <= 150;		--attack rate: (  38mS / 1uS per clockcycle) /254 steps
          when "0101" =>	divider_attack <= 220;		--attack rate: (  56mS / 1uS per clockcycle) /254 steps
          when "0110" =>	divider_attack <= 268;		--attack rate: (  68mS / 1uS per clockcycle) /254 steps
          when "0111" =>	divider_attack <= 315;		--attack rate: (  80mS / 1uS per clockcycle) /254 steps
          when "1000" =>	divider_attack <= 394;		--attack rate: ( 100mS / 1uS per clockcycle) /254 steps
          when "1001" =>	divider_attack <= 984;		--attack rate: ( 250mS / 1uS per clockcycle) /254 steps
          when "1010" =>	divider_attack <= 1968;		--attack rate: ( 500mS / 1uS per clockcycle) /254 steps
          when "1011" =>	divider_attack <= 3150;		--attack rate: ( 800mS / 1uS per clockcycle) /254 steps
          when "1100" =>	divider_attack <= 3937;		--attack rate: (1000mS / 1uS per clockcycle) /254 steps
          when "1101" =>	divider_attack <= 11811;	--attack rate: (3000mS / 1uS per clockcycle) /254 steps
          when "1110" =>	divider_attack <= 19685;	--attack rate: (5000mS / 1uS per clockcycle) /254 steps
          when "1111" =>	divider_attack <= 31496;	--attack rate: (8000mS / 1uS per clockcycle) /254 steps
          when others =>	divider_attack <= 0;			--
        end case;
        
        -- Decay Lookup table :
        -- It takes 32 * 51 = 1632 clock cycles to fall from peak level to zero. 
        -- Release Lookup table :
        -- It takes 32 * 51 = 1632 clock cycles to fall from peak level to zero. 
        case Dec_rel is
          when "0000" =>	divider_dec_rel <= 3;			--release rate: (    6mS / 1uS per clockcycle) / 1632
          when "0001" =>	divider_dec_rel <= 15;		--release rate: (   24mS / 1uS per clockcycle) / 1632
          when "0010" =>	divider_dec_rel <= 29;		--release rate: (   48mS / 1uS per clockcycle) / 1632
          when "0011" =>	divider_dec_rel <= 44;		--release rate: (   72mS / 1uS per clockcycle) / 1632
          when "0100" =>	divider_dec_rel <= 70;		--release rate: (  114mS / 1uS per clockcycle) / 1632
          when "0101" =>	divider_dec_rel <= 103;		--release rate: (  168mS / 1uS per clockcycle) / 1632
          when "0110" =>	divider_dec_rel <= 125;		--release rate: (  204mS / 1uS per clockcycle) / 1632
          when "0111" =>	divider_dec_rel <= 147;		--release rate: (  240mS / 1uS per clockcycle) / 1632
          when "1000" =>	divider_dec_rel <= 184;		--release rate: (  300mS / 1uS per clockcycle) / 1632
          when "1001" =>	divider_dec_rel <= 459;		--release rate: (  750mS / 1uS per clockcycle) / 1632
          when "1010" =>	divider_dec_rel <= 919;		--release rate: ( 1500mS / 1uS per clockcycle) / 1632
          when "1011" =>	divider_dec_rel <= 1471;	--release rate: ( 2400mS / 1uS per clockcycle) / 1632
          when "1100" =>	divider_dec_rel <= 1838;	--release rate: ( 3000mS / 1uS per clockcycle) / 1632
          when "1101" =>	divider_dec_rel <= 5515;	--release rate: ( 9000mS / 1uS per clockcycle) / 1632
          when "1110" =>	divider_dec_rel <= 9191;	--release rate: (15000mS / 1uS per clockcycle) / 1632
          when "1111" =>	divider_dec_rel <= 14706;	--release rate: (24000mS / 1uS per clockcycle) / 1632
          when others =>	divider_dec_rel <= 0;			--
        end case;              
        
      end if;
      
      -- Reset and various other functions happen at full clock speed, so
      -- that they don't get missed
      if reset='1' then
        cur_state <= idle;
        next_state 				<= idle;
        env_cnt_clear			<='1';
        env_cnt_up				<='1';
        env_count_hold_B	<='1';
        divider_rst 			<='1';
        divider_value 		<= 0;
        divider_attack <= 0;
        divider_dec_rel <= 0;
        exp_table_active 	<='0';
        exp_table_value	<= 0;
        Dec_rel_sel				<='0';		-- select decay as input for decay/release table
      end if;
      if ((reset = '1') or (env_cnt_clear = '1')) then
        env_counter <= (others => '0');
      end if;
      if ((reset = '1') or (divider_rst = '1')) then
        env_count_hold_A <= '1';			
        divider_counter	<= 0;
      end if;
      if (Dec_rel_sel = '0') then
        Dec_rel	<= Att_dec(3 downto 0);
      else
        Dec_rel	<= Sus_rel(3 downto 0);
      end if;
      
    end if;
  end process;
  
end Behavioral;
