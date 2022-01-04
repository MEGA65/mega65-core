
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
        if outputs(0) <= x"b000" or outputs(0) >= x"b100" then
          assert false report "Expected $B000 from single input of $B000 (multiplication rounds work in favour of -ve values), but saw $" & to_hstring(outputs(0));
        end if;
      elsif run("DC+ offset is progressively reduced") then
        setup_mixer; 
        sources <= (others => x"0000");
        -- Positive DC
        sources(0) <= x"3000";
        -- Time to get updated
        last_output <= x"3000";
        for j in 1 to 1000 loop
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
        report "Output 0 DC offset reduced over time:";
        for j in 1 to 1000 loop
          report "   Iteration #" & integer'image(j) & " = $" & to_hstring(output_history(j));
        end loop;
      end if;
    end loop;    
    test_runner_cleanup(runner); -- Simulation ends here
  end process;
end architecture;

  
