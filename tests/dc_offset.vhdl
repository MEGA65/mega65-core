
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

  signal cpuclock : std_logic := '0';
  signal dc_track_rate : unsigned(7 downto 0) := x"ff";
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
  begin
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      if run("Divider passes collected test values") then
        assert false report "not implemented";
        
      end if;
    end loop;
    
    test_runner_cleanup(runner); -- Simulation ends here
  end process;
end architecture;

  
