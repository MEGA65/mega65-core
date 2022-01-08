--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2018
--
-- *  This program is free software; you can redistribute it and/or modify
-- *  it under the terms of the GNU Lesser General Public License as
-- *  published by the Free Software Foundation; either version 3 of the
-- *  License, or (at your option) any later version.
-- *
-- *  This program is distributed in the hope that it will be useful,
-- *  but WITHOUT ANY WARRANTY; without even the implied warranty of
-- *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- *  GNU General Public License for more details.
-- *
-- *  You should have received a copy of the GNU Lesser General Public License
-- *  along with this program; if not, write to the Free Software
-- *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
-- *  02111-1307  USA.
--


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;
use work.cputypes.all;

entity audio_complex is
  generic ( clock_frequency : integer );
  port (    
    cpuclock : in std_logic;

    -- Interface for accessing mix table via CPU
    audio_mix_reg : in unsigned(7 downto 0) := x"FF";
    audio_mix_write : in std_logic := '0';
    audio_mix_wdata : in unsigned(15 downto 0) := x"FFFF";
    audio_mix_rdata : out unsigned(15 downto 0) := x"FFFF";
    audio_loopback : out signed(15 downto 0) := x"FFFF";

    -- Volume knobs
    volume_knob1 : in unsigned(15 downto 0) := x"FFFF";
    volume_knob2 : in unsigned(15 downto 0) := x"FFFF";
    volume_knob3 : in unsigned(15 downto 0) := x"FFFF";   
    -- Which output do the knobs apply to?
    volume_knob1_target : in unsigned(3 downto 0) := "1111";
    volume_knob2_target : in unsigned(3 downto 0) := "1111";
    volume_knob3_target : in unsigned(3 downto 0) := "1111";
    
    -- The various audio busses and interfaces:

    -- OPL2/3 FM audio
    fm_left : in signed(15 downto 0);
    fm_right : in signed(15 downto 0);
    
    -- Audio in from digital SIDs
    leftsid_audio : in signed(17 downto 0);
    rightsid_audio : in signed(17 downto 0);
    frontsid_audio : in signed(17 downto 0);
    backsid_audio : in signed(17 downto 0);
    
    -- Audio in from $D6F8-B registers
    pcm_left : in signed(15 downto 0);
    pcm_right : in signed(15 downto 0);
    -- But if the CPU is providing digital audio, we use that instead
    cpu_pcm_enable : in std_logic := '0';
    cpu_pcm_bypass : in std_logic := '0';
    cpu_pcm_left : in signed(15 downto 0) := x"0000";
    cpu_pcm_right : in signed(15 downto 0) := x"0000";
    pwm_mode_select : in std_logic := '1';
    
    -- I2S PCM Audio interfaces (portable devices only)

    -- Master I2S clock (used for all i2s audio devices):
    i2s_master_clk : out std_logic := '0';
    i2s_master_sync : out std_logic := '0';
    
    -- I2S output for the speakers
    -- Expected to be an SSM2518
    -- http://www.analog.com/media/en/technical-documentation/data-sheets/ssm2518.pdf
    i2s_speaker_data_out : out std_logic := '1';
    
    -- Master PCM clock for the modems (1.8V and 8KHz instead)
    pcm_modem_clk : out std_logic := '0';
    pcm_modem_sync : out std_logic := '0';
    -- And slave PCM clock for devices that need it
    -- (there is a problem with the QC25AU refusing to accept AT+QDAI=1,1,0,4,0
    -- to set PCM to slave mode, for example)
    pcm_modem_clk_in : in std_logic;
    pcm_modem_sync_in : in std_logic;

    -- Modem 1 PCM in
    pcm_modem1_data_in : in std_logic := '0';
    -- Modem 1 PCM out
    pcm_modem1_data_out : out std_logic := '0';
    -- Modem 2 PCM in
    pcm_modem2_data_in : in std_logic := '0';
    -- Modem 2 PCM out
    pcm_modem2_data_out : out std_logic := '0';

    -- Slave I2S clock in (used for BT adapter)
    i2s_slave_clk : in std_logic := '0';
    i2s_slave_sync : in std_logic := '0';

    -- Bluetooth PCM audio interface
    pcm_bluetooth_data_in : in std_logic := '0';
    pcm_bluetooth_data_out : out std_logic := '0';    
    pcm_bluetooth_clk_in : in std_logic := '0';
    pcm_bluetooth_sync_in : in std_logic := '0';
    
    -- PWM Audio output
    -- (Nexys, MEGA65 PCB and similar boards only,
    -- some of which may have only a left or right channel)
    ampPWM_l : out std_logic;
    ampPWM_r : out std_logic;
    pcspeaker_left : out std_logic;
    pcspeaker_right : out std_logic;
    ampSD : out std_logic := '1';  -- default to amplifier on
    audio_left : out std_logic_vector(19 downto 0);
    audio_right : out std_logic_vector(19 downto 0);
    
    -- MEMs Microphone inputs
    micData0 : in std_logic; --  (microphones 0 and 1)
    micData1 : in std_logic; --  (microphones 2 and 3)
    micClk : out std_logic;
    micLRSel : out std_logic := '0';
    headphone_mic : in std_logic
    
    );

end entity;

architecture elizabethan of audio_complex is
  -- These values seem to work about right.
  -- Ideally we should be able to make the divider_max more like 10, which
  -- should get 2 extra bits of audio resolution. To do that we need to shift
  -- the filter cut-off down by a factor of 4 as well.
  signal mic_divider_max : unsigned(7 downto 0) := to_unsigned(8,8);
  signal mic_sample_trigger : unsigned(7 downto 0) := to_unsigned(3,8);

  signal leftsid_audio_combined : signed(17 downto 0);
  signal rightsid_audio_combined : signed(17 downto 0);

  
  signal mic_do_sample_left : std_logic := '0';
  signal mic_do_sample_right : std_logic := '0';
  signal mic_divider : unsigned(7 downto 0) := "00000000";
  signal headphone_mic_left : signed(15 downto 0) := to_signed(0,16);
  signal mems_mic0_left : signed(15 downto 0) := to_signed(0,16);
  signal mems_mic0_right : signed(15 downto 0) := to_signed(0,16);
  signal mems_mic1_left : signed(15 downto 0) := to_signed(0,16);
  signal mems_mic1_right : signed(15 downto 0) := to_signed(0,16);
  signal micclkinternal : std_logic := '0';
  
  signal modem1_in : signed(15 downto 0) := x"0000";
  signal modem2_in : signed(15 downto 0) := x"0000";
  signal modem1_out : signed(15 downto 0) := x"0000";
  signal modem2_out : signed(15 downto 0) := x"0000";
  signal headphones_1_in : signed(15 downto 0) := x"0000";
  signal headphones_2_in : signed(15 downto 0) := x"0000";
  signal headphones_left_out : signed(15 downto 0) := x"0000";
  signal headphones_right_out : signed(15 downto 0) := x"0000";
  signal bt_left_in : signed(15 downto 0) := x"0000";
  signal bt_right_in : signed(15 downto 0) := x"0000";
  signal bt_left_out : signed(15 downto 0) := x"0000";
  signal bt_right_out : signed(15 downto 0) := x"0000";
  signal spkr_left : signed(15 downto 0) := x"0000";
  signal spkr_right : signed(15 downto 0) := x"0000";

  signal pcspeaker_l_in : signed(15 downto 0) := x"0000";
  signal pcspeaker_r_in : signed(15 downto 0) := x"0000";
  
  -- Dummy signals for soaking up dummy audio mixer outputs
  signal dummy0 : signed(15 downto 0) := x"0000";
  signal dummy1 : signed(15 downto 0) := x"0000";
  signal dummy2 : signed(15 downto 0) := x"0000";
  signal dummy3 : signed(15 downto 0) := x"0000";
  signal dummy4 : signed(15 downto 0) := x"0000";
  signal dummy5 : signed(15 downto 0) := x"0000";
  signal dummy6 : signed(15 downto 0) := x"0000";
  signal dummy7 : signed(15 downto 0) := x"0000";

  signal i2s_master_clk_int : std_logic := '0';
  signal i2s_master_sync_int : std_logic := '0';

  signal modem_is_pcm_master : std_logic := '0';
  signal pcm_modem_clk_int : std_logic := '0';
  signal pcm_modem_sync_int : std_logic := '0';
  signal pcm_modem_clk_gen : std_logic := '0';
  signal pcm_modem_sync_gen : std_logic := '0';

  -- Use PWM instead of PDM for digital output to speakers
  -- on boards using 1-wire DAC
  signal pwm_mode : std_logic := '1';

  signal pcm_selected_left : signed(15 downto 0) := x"0000";
  signal pcm_selected_right : signed(15 downto 0) := x"0000";
  
  signal ampPWM_l_in : signed(15 downto 0);
  signal ampPWM_r_in : signed(15 downto 0);
  
begin

  -- PCM master clock interface for modems
  pcmclock0: entity work.pcm_clock 
    generic map (
      -- Modems and some other peripherals only use 8KHz
      clock_frequency => clock_frequency,
      sample_rate => 8000
      )
    port map (
      cpuclock => cpuclock,
      pcm_clk => pcm_modem_clk_gen,
      pcm_sync => pcm_modem_sync_gen);

  -- PCM interfaces to modems
  pcm0: entity work.pcm_transceiver
    generic map ( clock_frequency => clock_frequency)
    port map (
    cpuclock => cpuclock,
    pcm_clk => pcm_modem_clk_int,
    pcm_sync => pcm_modem_sync_int,
    pcm_out => pcm_modem1_data_out,
    pcm_in => pcm_modem1_data_in,
    tx_sample => modem1_out,
    rx_sample => modem1_in
    );
  pcm1: entity work.pcm_transceiver
    generic map ( clock_frequency => clock_frequency)
    port map (
    cpuclock => cpuclock,
    pcm_clk => pcm_modem_clk_int,
    pcm_sync => pcm_modem_sync_int,
    pcm_out => pcm_modem2_data_out,
    pcm_in => pcm_modem2_data_in,
    tx_sample => modem2_out,
    rx_sample => modem2_in
    );
    
  -- PCM master interface to RN52SRC Bluetooth
  i2s2: entity work.i2s_transceiver
    generic map ( clock_frequency => clock_frequency
                  )
    port map (
    cpuclock => cpuclock,
    i2s_clk => pcm_bluetooth_clk_in,
    i2s_sync => pcm_bluetooth_sync_in,
    pcm_out => pcm_bluetooth_data_out,
    pcm_in => pcm_bluetooth_data_in,
    tx_sample_left => bt_left_out,
    tx_sample_right => bt_right_out,
    rx_sample_left => bt_left_in,
    rx_sample_right => bt_right_in
    );

    

  i2sclock2: entity work.i2s_clock
    generic map (
      -- Modems and some other peripherals only need 8KHz,
      clock_frequency => clock_frequency,
      sample_rate => 44100
      )
    port map (
    cpuclock => cpuclock,
    i2s_clk => i2s_master_clk_int,
    i2s_sync => i2s_master_sync_int);
  
  -- I2S master for stereo speakers
  i2s4: entity work.i2s_transceiver
    generic map ( clock_frequency => clock_frequency)
    port map (
    cpuclock => cpuclock,
    i2s_clk => i2s_master_clk_int,
    i2s_sync => i2s_master_sync_int,
    pcm_out => i2s_speaker_data_out,
    pcm_in => '0',
    tx_sample_left => spkr_left,
    tx_sample_right => spkr_right
--    tx_sample_left => x"1234",
--    tx_sample_right => x"5678"
--    rx_sample_left =>
--    rx_sample_right =>
    );
    
  -- PDM input for MEMS microphone(s)
  mic0l: entity work.pdm_to_pcm
    port map (
      clock => cpuclock,
      sample_clock => mic_do_sample_left,
      sample_bit => micData0,
      sample_out => mems_mic0_left);

  mic0r: entity work.pdm_to_pcm
    port map (
      clock => cpuclock,
      sample_clock => mic_do_sample_right,
      sample_bit => micData0,
      sample_out => mems_mic0_right);

  mic1l: entity work.pdm_to_pcm
    port map (
      clock => cpuclock,
      sample_clock => mic_do_sample_left,
      sample_bit => micData1,
      sample_out => mems_mic1_left);

  mic1r: entity work.pdm_to_pcm
    port map (
      clock => cpuclock,
      sample_clock => mic_do_sample_right,
      sample_bit => micData1,
      sample_out => mems_mic1_right);

  michead: entity work.pdm_to_pcm
    port map (
      clock => cpuclock,
      sample_clock => mic_do_sample_left,
      sample_bit => headphone_mic,
      sample_out => headphone_mic_left);
  
  -- PWM/PDM digital audio output for Nexys4 series boards
  -- and on the MEGA65 PCB.
  pwm0: entity work.pcm_to_pdm
    port map (
      cpuclock => cpuclock,
      pcm_left => ampPWM_l_in,
      pcm_right => ampPWM_r_in,

      pdm_left => ampPWM_l,
      pdm_right => ampPWM_r,

      audio_mode => pwm_mode
      );
  
  -- PWM/PDM digital audio output for Nexys4 series boards
  -- and on the MEGA65 PCB.
  pwm1: entity work.pcm_to_pdm
    port map (
      cpuclock => cpuclock,
      pcm_left => pcspeaker_l_in,      
      pcm_right => pcspeaker_r_in,

      pdm_left => pcspeaker_left,
      pdm_right => pcspeaker_right,

      audio_mode => pwm_mode
      );
  
  -- Audio Mixer to combine everything
  mix0: entity work.audio_mixer port map (
    cpuclock => cpuclock,
    reg_num => audio_mix_reg,
    reg_write => audio_mix_write,
    wdata => audio_mix_wdata,
    rdata => audio_mix_rdata,
    audio_loopback => audio_loopback,
    modem_is_pcm_master => modem_is_pcm_master,
    amplifier_enable => ampSD,

    volume_knob1 => volume_knob1,
    volume_knob2 => volume_knob2,
    volume_knob3 => volume_knob3,    

    volume_knob1_target => volume_knob1_target,
    volume_knob2_target => volume_knob2_target,
    volume_knob3_target => volume_knob3_target,
    
    -- SID outputs
    sources(0) => leftsid_audio_combined(17 downto 2),
    sources(1) => rightsid_audio_combined(17 downto 2),
    -- Two mono I2S from communications modules
    sources(2) => modem1_in,
    sources(3) => modem2_in,
    -- Stereo I2S inputs from BT module
    sources(4) => bt_left_in,
    sources(5) => bt_right_in,
    -- Two mono interfaces from headphones
    -- (second might end up being FM radio in)
    sources(6) => headphones_1_in,
    sources(7) => headphones_2_in,
    -- Digital audio 16-bit registers ($D6F8-B)
    sources(8) => pcm_selected_left,
    sources(9) => pcm_selected_right,
    -- MEMs microphones 0 - 3
    sources(10) => mems_mic0_left,
    sources(11) => mems_mic0_right,
    sources(12) => mems_mic1_left,
    sources(13) => mems_mic1_right,
    sources(14) => headphone_mic_left, -- headphone jack input on megaphone
    sources(15) => fm_right, -- #15 can't be used, as shadowed by master volume
                             -- (gain is controlled by source 14)

    -- Audio outputs for on-board speakers, line-out etc
    outputs(0) => spkr_left,      -- also used for HDMI out on M65R2
    outputs(1) => spkr_right,     -- also used for HDMI out on M65R2
    outputs(2) => modem1_out,
    outputs(3) => modem2_out,
    outputs(4) => bt_left_out,    -- also drives internal speaker on M65R2
    outputs(5) => bt_right_out,
    outputs(6) => headphones_left_out,  -- drives headphone jack on M65R2
    outputs(7) => headphones_right_out, -- drives headphone jack on M65R2
    -- The other 8 outputs are in fact dummy place-holders.
    -- We do not expect to have more than 8 audio outputs
    outputs(8) => dummy0,
    outputs(9) => dummy1,
    outputs(10) => dummy2,
    outputs(11) => dummy3,
    outputs(12) => dummy4,
    outputs(13) => dummy5,
    outputs(14) => dummy6,
    outputs(15) => dummy7
    );   

  pcm_selected_left <= pcm_left when cpu_pcm_enable='0' else cpu_pcm_left;
  pcm_selected_right <= pcm_right when cpu_pcm_enable='0' else cpu_pcm_right;
  
  process (cpuclock) is
  begin    
    
    if rising_edge(cpuclock) then

      pwm_mode <= pwm_mode_select;
      
      report "pcm_selected_left = $" & to_hstring(pcm_selected_left)
        & ", right = $" & to_hstring(pcm_selected_right);
      
      -- Export raw speaker audio for HDMI etc output
      audio_left(19 downto 4) <= std_logic_vector(spkr_left);
      audio_left(3 downto 0) <= "0000";
      audio_right(19 downto 4) <= std_logic_vector(spkr_right);
      audio_right(3 downto 0) <= "0000";
      
      -- Combine the pairs of SIDs      
      leftsid_audio_combined <=  leftsid_audio + frontsid_audio;
      rightsid_audio_combined <= rightsid_audio + backsid_audio;

      if cpu_pcm_bypass='0' then
        ampPWM_l_in <= headphones_left_out;
        ampPWM_r_in <= headphones_right_out;
        -- Duplicate of bt_left_out as PWM, for driving MEGA65 R2 on-board speaker
        pcspeaker_l_in <= bt_left_out;
        pcspeaker_r_in <= bt_right_out;
      else
        ampPWM_l_in <= cpu_pcm_left;
        ampPWM_r_in <= cpu_pcm_right;
        pcspeaker_l_in <= cpu_pcm_left;
        pcspeaker_r_in <= cpu_pcm_right;
      end if;

      
      -- Propagate I2S and PCM clocks
      if modem_is_pcm_master='0' then
        -- Use internally generated clock
        pcm_modem_clk <= pcm_modem_clk_gen;
        pcm_modem_sync <= pcm_modem_sync_gen;
        pcm_modem_clk_int <= pcm_modem_clk_gen;
        pcm_modem_sync_int <= pcm_modem_sync_gen;
      else
        -- Use clock supplied by cellular modem
        -- (The EC25AUs currently refuse to go into PCM slave mode.
        -- Most Annoying, as this means we need duplicate PCM_CLK and
        -- PCM_SYNC lines.)
        -- XXX - Need to make separate copies for the two modems
        -- inputs.  Else only one will work in master mode.
        pcm_modem_clk <= pcm_modem_clk_in;
        pcm_modem_sync <= pcm_modem_sync_in;
        pcm_modem_clk_int <= pcm_modem_clk_in;
        pcm_modem_sync_int <= pcm_modem_sync_in;
      end if;
      
      i2s_master_clk <= i2s_master_clk_int;
      i2s_master_sync <= i2s_master_sync_int;
      
      -- With the new audio mixer, we map the left and right speaker channels
      -- to the on-board line-out/headphone jack of the Nexys 4 series boards.
      -- Apart from that, it is really simple, because the mixing of the audio
      -- sources is done entirely in the audio mixer.
      
      -- microphone sampling process
      -- max frequency is 3MHz, optimal is about 2.5MHz according to
      -- https://pdfs.semanticscholar.org/a3f4/9749f4d3508f58c5ca4693f8bae9c403fc85.pdf
      if mic_divider = mic_sample_trigger then
        mic_do_sample_left <= micclkinternal;
        mic_do_sample_right <= not micclkinternal;
      else
        mic_do_sample_left <= '0';
        mic_do_sample_right <= '0';
      end if;
      if mic_divider < mic_divider_max then
        mic_divider <= mic_divider + 1;
      else
        -- XXX Debug that we are correctly plumbed to pin U4
        -- i2s_speaker_data_out <= micclkinternal;

        
        micCLK <= not micclkinternal;
        micclkinternal <= not micclkinternal;
        mic_divider <= to_unsigned(0,8);
      end if;


    end if;
  end process;
  
end elizabethan;
