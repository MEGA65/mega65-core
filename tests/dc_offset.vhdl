
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_dc_offset is
  generic (runner_cfg : string);
end entity;

architecture tb of tb_dc_offset is

  signal last_output : signed(15 downto 0);
  type output_history_t is array(0 to 1000) of signed(15 downto 0);
  signal output_history : output_history_t;
  
  signal cpuclock : std_logic := '0';
  -- Track DC as fast as possible to reduce simulation time
  signal dc_track_rate : unsigned(7 downto 0) := x"01";
  signal reg_num : unsigned(7 downto 0) := x"FF";
  signal reg_write : std_logic := '0';
  signal wdata : unsigned(15 downto 0) := x"FFFF";
  signal rdata : unsigned(15 downto 0) := x"FFFF";
  signal audio_loopback : signed(15 downto 0) := x"FFFF";
  signal modem_is_pcm_master : std_logic := '0';
  signal amplifier_enable : std_logic := '0';
    
    -- Read in values from audio knobs
  signal volume_knob1 : unsigned(15 downto 0) := x"FFFF";
  signal volume_knob2 : unsigned(15 downto 0) := x"FFFF";
  signal volume_knob3 : unsigned(15 downto 0) := x"FFFF";

    -- Which output do the knobs apply to?
  signal volume_knob1_target : unsigned(3 downto 0) := "1111";
  signal volume_knob2_target : unsigned(3 downto 0) := "1111";
  signal volume_knob3_target : unsigned(3 downto 0) := "1111";
    
    -- Audio inputs
  signal sources : sample_vector_t := (others => x"0000");
    -- Audio outputs
  signal outputs : sample_vector_t := (others => x"0000");

  type sine_rate_t is array (0 to 15) of integer;
  signal sine_rate : sine_rate_t;
  signal sine_offset : sine_rate_t := (others => 0);
  signal sine_counter : sine_rate_t;
  signal saw_clip_top : std_logic := '0';
  signal saw_clip_bottom : std_logic := '0';
  signal saw_unclipped : std_logic := '0';
  
 type s7_0to31 is array (0 to 31) of signed(7 downto 0);
  signal sine_table : s7_0to31 := (
    signed(to_unsigned(128-128,8)),signed(to_unsigned(152-128,8)),
    signed(to_unsigned(176-128,8)),signed(to_unsigned(198-128,8)),
    signed(to_unsigned(217-128,8)),signed(to_unsigned(233-128,8)),
    signed(to_unsigned(245-128,8)),signed(to_unsigned(252-128,8)),
    signed(to_unsigned(255-128,8)),signed(to_unsigned(252-128,8)),
    signed(to_unsigned(245-128,8)),signed(to_unsigned(233-128,8)),
    signed(to_unsigned(217-128,8)),signed(to_unsigned(198-128,8)),
    signed(to_unsigned(176-128,8)),signed(to_unsigned(152-128,8)),
    signed(to_unsigned(128-128,8)),signed(to_unsigned(103+128,8)),
    signed(to_unsigned(79+128,8)),signed(to_unsigned(57+128,8)),
    signed(to_unsigned(38+128,8)),signed(to_unsigned(22+128,8)),
    signed(to_unsigned(10+128,8)),signed(to_unsigned(3+128,8)),
    signed(to_unsigned(1+128,8)),signed(to_unsigned(3+128,8)),
    signed(to_unsigned(10+128,8)),signed(to_unsigned(22+128,8)),
    signed(to_unsigned(38+128,8)),signed(to_unsigned(57+128,8)),
    signed(to_unsigned(79+128,8)),signed(to_unsigned(103+128,8))    
    );
  
begin

  -- Audio Mixer to combine everything
  mix0: entity work.audio_mixer port map (
    cpuclock => cpuclock,
    dc_track_rate => dc_track_rate,
    reg_num => reg_num,
    reg_write => reg_write,    
    wdata => wdata,
    rdata => rdata,
    audio_loopback => audio_loopback,
    modem_is_pcm_master => modem_is_pcm_master,
    amplifier_enable => amplifier_enable,

    volume_knob1 => volume_knob1,
    volume_knob2 => volume_knob2,
    volume_knob3 => volume_knob3,    

    volume_knob1_target => volume_knob1_target,
    volume_knob2_target => volume_knob2_target,
    volume_knob3_target => volume_knob3_target,

    sources => sources,
    outputs => outputs
    );     
  
  main : process

    procedure write_reg(r : unsigned(7 downto 0); v : unsigned(15 downto 0)) is
    begin
      reg_write <= '1';
      reg_num <= r;
      wdata <= v;
      cpuclock <= '0'; wait for 12.5 ns;
      cpuclock <= '1'; wait for 12.5 ns;
    end procedure;
    
    procedure setup_mixer is
    begin
      for i in 0 to 255 loop
        write_reg(to_unsigned(i,8),x"ffff");
      end loop;
      report "MIXER READY";
    end procedure;  
      
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      if run("Silence in = silence out") then
        -- Setup mixer with all coefficients maximum
        setup_mixer; 
        -- Sources are signed, so $0000 = the mid point in output voltage
        -- Make sure all zeroes in gives all zeroes out
        sources <= (others => x"0000");
        for i in 1 to 1000 loop
          cpuclock <= '0'; wait for 12.5 ns; cpuclock <= '1'; wait for 12.5 ns;
        end loop;
        if outputs(0) /= x"0000" then
          assert false report "Silence in should yield silence out, but output=$" & to_hstring(outputs(0));
        end if;
      elsif run("DC+ in = DC+ out initially") then
        -- Now put a fixed value on a source, and make sure that we get it back
        -- out (minus volume multiplication loss)
        setup_mixer; 
        sources <= (others => x"0000");
        -- Positive DC
        sources(0) <= x"4000";
        -- Time to get updated
        for i in 1 to 1000 loop
          cpuclock <= '0'; wait for 12.5 ns; cpuclock <= '1'; wait for 12.5 ns;
        end loop;
        if outputs(0) >= x"4000" or outputs(0) <= x"3f00" then
          assert false report "Expected $3FFE from single input of $4000 (-1 for input volume and -1 for master volume multiplications), but saw $" & to_hstring(outputs(0));
        end if;

      elsif run("DC- in = DC- out initially") then
        -- Now put a fixed value on a source, and make sure that we get it back
        -- out (minus volume multiplication loss)
        setup_mixer; 
        sources <= (others => x"0000");
        -- Negative DC
        sources(0) <= x"B000";
        -- Time to get updated
        for i in 1 to 1000 loop
          cpuclock <= '0'; wait for 12.5 ns; cpuclock <= '1'; wait for 12.5 ns;
        end loop;
        if outputs(0) < x"b000" or outputs(0) >= x"b100" then
          assert false report "Expected $B000 from single input of $B000 (multiplication rounds work in favour of -ve values), but saw $" & to_hstring(outputs(0));
        end if;
      elsif run("DC+ offset is progressively reduced") then
        setup_mixer; 
        sources <= (others => x"0000");
        -- Positive DC
        sources(0) <= x"3000";
        -- Time to get updated
        last_output <= x"3000";
        for j in 1 to 100 loop
          for i in 1 to 1000 loop
            cpuclock <= '0'; wait for 12.5 ns; cpuclock <= '1'; wait for 12.5 ns;
          end loop;
          if outputs(0) > last_output or outputs(0) = last_output then
            assert false report "Expected output in iteration " & integer'image(j) &
              " to have reduced from $" & to_hstring(last_output) & ", but saw $" & to_hstring(outputs(0));
          end if;
          last_output <= outputs(0);
          output_history(j) <= outputs(0);
        end loop;
        report "Output 0 +DC offset reduced over time:";
        for j in 1 to 100 loop
          report "   Iteration #" & integer'image(j) & " = $" & to_hstring(output_history(j));
        end loop;
      elsif run("DC- offset is progressively increased") then
        setup_mixer; 
        sources <= (others => x"0000");
        -- Positive DC
        sources(0) <= x"E000";
        -- Time to get updated
        last_output <= x"E000";
        for j in 1 to 100 loop
          for i in 1 to 1000 loop
            cpuclock <= '0'; wait for 12.5 ns; cpuclock <= '1'; wait for 12.5 ns;
          end loop;
          if outputs(0) < last_output or outputs(0) = last_output then
            assert false report "Expected output in iteration " & integer'image(j) &
              " to have increased from $" & to_hstring(last_output) & ", but saw $" & to_hstring(outputs(0));
          end if;
          last_output <= outputs(0);
          output_history(j) <= outputs(0);
        end loop;
        report "Output 0 -DC offset increased over time:";
        for j in 1 to 100 loop
          report "   Iteration #" & integer'image(j) & " = $" & to_hstring(output_history(j));
        end loop;
      elsif run("DC+ offset doesn't cross zero") then
        setup_mixer; 
         sources <= (others => x"0000");
        -- Positive DC
        sources(0) <= x"00A0";
        -- Time to get updated
        last_output <= x"00A0";
        for j in 1 to 100 loop
          for i in 1 to 1000 loop
            cpuclock <= '0'; wait for 12.5 ns; cpuclock <= '1'; wait for 12.5 ns;
          end loop;
          if (outputs(0) > last_output or outputs(0) = last_output) and outputs(0) /= x"0000" then
            assert false report "Expected output in iteration " & integer'image(j) &
              " to have decreased from $" & to_hstring(last_output) & ", but saw $" & to_hstring(outputs(0));
          end if;
          last_output <= outputs(0);
          output_history(j) <= outputs(0);
        end loop;
        report "Output 0 +DC offset decreased over time:";
        for j in 1 to 100 loop
          report "   Iteration #" & integer'image(j) & " = $" & to_hstring(output_history(j));
        end loop;
        if outputs(0) /= x"0000" then
          assert false report "Expected +DC output to reach and stabilise at zero.";
        end if;
      elsif run("DC- offset doesn't cross zero") then
        setup_mixer; 
        sources <= (others => x"0000");
        -- Negative DC
        sources(0) <= x"FF80";
        -- Time to get updated
        last_output <= x"FF80";
        for j in 1 to 100 loop
          for i in 1 to 1000 loop
            cpuclock <= '0'; wait for 12.5 ns; cpuclock <= '1'; wait for 12.5 ns;
          end loop;
          if (outputs(0) < last_output or outputs(0) = last_output) and outputs(0) /= x"0000" then
            assert false report "Expected output in iteration " & integer'image(j) &
              " to have increased from $" & to_hstring(last_output) & ", but saw $" & to_hstring(outputs(0));
          end if;
          last_output <= outputs(0);
          output_history(j) <= outputs(0);
        end loop;
        report "Output 0 -DC offset increased over time:";
        for j in 1 to 100 loop
          report "   Iteration #" & integer'image(j) & " = $" & to_hstring(output_history(j));
        end loop;
        if outputs(0) /= x"0000" then
          assert false report "Expected -DC output to reach and stabilise at zero.";
        end if;
      elsif run("Large positive DC offsets get clamped until in range") then
        setup_mixer; 
        sources <= (others => x"0000");
        -- Will add up to $8020, which is >$7FFF, and thus must be clamped to
        -- $7FFF initially, until DC offset tracking brings it back in range.
        sources(0) <= x"4000";
        sources(1) <= x"4020";
        -- Time to get updated
        last_output <= x"7FFF";
        for j in 1 to 100 loop
          for i in 1 to 1000 loop
            cpuclock <= '0'; wait for 12.5 ns; cpuclock <= '1'; wait for 12.5 ns;
          end loop;
          if (outputs(0) > last_output) and outputs(0) /= x"0000" then
            assert false report "Expected output in iteration " & integer'image(j) &
              " to be same or decrease from $" & to_hstring(last_output) & ", but saw $" & to_hstring(outputs(0));
          end if;
          last_output <= outputs(0);
          output_history(j) <= outputs(0);
        end loop;
        if outputs(0) = x"7fff" then
          assert false report "Large positive DC offset failed to be reigned in";
        end if;
        report "Output 0 large positive DC was initially clamped, then reduced";
        for j in 1 to 100 loop
          report "   Iteration #" & integer'image(j) & " = $" & to_hstring(output_history(j));
        end loop;
      elsif run("Large negative DC offsets get clamped until in range") then
        setup_mixer; 
        sources <= (others => x"0000");
        -- Will add up to $F7FE0, which is < $F7F80, and thus must be clamped to
        -- $0000 initially, until DC offset tracking brings it back in range.
        sources(0) <= x"C000";
        sources(1) <= x"BFE0";
        -- Time to get updated
        last_output <= x"8000";
        for j in 1 to 100 loop
          for i in 1 to 1000 loop
            cpuclock <= '0'; wait for 12.5 ns; cpuclock <= '1'; wait for 12.5 ns;
          end loop;
          report "Iteration #" & integer'image(j) & " = $" & to_hstring(outputs(0));
          if (outputs(0) < last_output) and outputs(0) /= x"8000" then
            assert false report "Expected output in iteration " & integer'image(j) &
              " to be same or increase from $" & to_hstring(last_output) & ", but saw $" & to_hstring(outputs(0));
          end if;
          last_output <= outputs(0);
          output_history(j) <= outputs(0);
        end loop;
        if outputs(0) = x"8000" then
          assert false report "Large negative DC offset failed to be reigned in";
        end if;
        report "Output 0 large negative DC was initially clamped, then reduced";
        for j in 1 to 100 loop
          report "   Iteration #" & integer'image(j) & " = $" & to_hstring(output_history(j));
        end loop;
        
      elsif run("Full range sine waves clip") then
        setup_mixer; 
        sources <= (others => x"0000");
        -- All sine curves at same rate initially.
        -- This means that they will constructively interfere,
        -- resulting in a signal that regularly clips.
        sine_rate <= (others => 0 );
        for j in 1 to 10 loop
          for i in 1 to 1000 loop
            cpuclock <= '0'; wait for 12.5 ns; cpuclock <= '1'; wait for 12.5 ns;
            -- Update sine curves at various rates
            for s in 0 to 15 loop
              if sine_counter(s) /= sine_rate(s) then
                sine_counter(s) <= sine_counter(s) + 1;
              else
                sine_counter(s) <= 0;
                if sine_offset(s) /= 31 then
                  sine_offset(s) <= sine_offset(s) + 1;
                else
                  sine_offset(s) <= 0;
                end if;
              end if;
              sources(s)(15 downto 8) <= sine_table(sine_offset(s));
              sources(s)(7 downto 0) <= (others => '0');
            end loop;
          end loop;
          if outputs(0) = x"7fff" then
            saw_clip_top <= '1';
          elsif outputs(0) = x"8000" then
            saw_clip_bottom <= '1';
          elsif outputs(0)(15 downto 12) = x"f" then
            -- Saw a value $Fxxx, that was not clipped
            saw_unclipped <= '1';
          end if;
          last_output <= outputs(0);
          output_history(j) <= outputs(0);
        end loop;
        if saw_clip_top='0' then
          assert false report "Did not see multiple full-amplitude sine waves clip at upper limit";
        end if;
        if saw_clip_bottom='0' then
          assert false report "Did not see multiple full-amplitude sine waves clip at upper limit";
        end if;
        if saw_unclipped='0' then
          assert false report "Did not see multiple full-amplitude sine waves produce unclipped values";
        end if;

        report "Output 0 large positive DC was initially clamped, then reduced";
        for j in 1 to 100 loop
          report "   Iteration #" & integer'image(j) & " = $" & to_hstring(output_history(j));
        end loop;
      end if;
    end loop;    
    test_runner_cleanup(runner); -- Simulation ends here
  end process;
end architecture;

  
