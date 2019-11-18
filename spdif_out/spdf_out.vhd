----------------------------------------------------------------------------------
-- Engineer: Mike Field <hamster@sanp.net.nz>
-- 
-- Module Name:    spdf_out - Behavioral 
-- Description: 
--
-- Top level module fot the S/PDIF output module
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity spdf_out is
    Port ( clk : in  STD_LOGIC;
           spdif_out : out  STD_LOGIC);
end spdf_out;

architecture Behavioral of spdf_out is

   COMPONENT soundSource
   PORT(
      Clk          : IN std_logic;
      Sample      : OUT std_logic_vector(19 downto 0)
      );
   END COMPONENT;


   COMPONENT serialiser
   PORT(
      clk100m          : IN std_logic;
      auxAudioBits   : IN std_logic_vector(3 downto 0);
      sample_left         : IN std_logic_vector(19 downto 0);
      sample_right         : IN std_logic_vector(19 downto 0);
      spdifOut       : OUT std_logic       
      );
   END COMPONENT;

   signal sample_left      : std_logic_vector(19 downto 0);
   signal sample_right      : std_logic_vector(19 downto 0);

  signal sample_32 : std_logic_vector(31 downto 0);
  signal sample_ack : std_logic;
  signal sample_channel : std_logic;
   
begin

   Inst_soundSource: soundSource PORT MAP(
      Clk => clk,
      Sample => sample_left
   );

  spdiftx0: entity work.spdif_encoder port map (
    up_clk => clk,
    data_clk => clk,
    resetn => '1',
    conf_mode => "0101", -- 20 bit samples
    conf_ratio => std_logic_vector(to_unsigned(100000000/(44100*64),8)), -- clock divider
    conf_txdata => '1', -- sample data is valid
    conf_txen => '1', -- enable transmitter
    chstat_freq => "00", -- 44.1KHz sample rate
    chstat_gstat => '0', -- maybe user bit management bit 0 or 3?
    chstat_preem => '0', -- no preemphasis
    chstat_copy => '1', -- NOT copyright (negative meaning)
    chstat_audio => '1'. -- normal PCM audio

    sample_data => sample_32,
    sample_data_ack => sample_ack,
    channel => sample_channel,

    spdif_tx_o => spdif_out
    );

  process (clk) is
  begin
    if rising_edge(clk) then
      if sample_channel = '0' then
        sample_32(31 downto 12) <= sample_left;
      else
        sample_32(31 downto 12) <= sample_left;
      end if;
    end if;
  end process;


end Behavioral;
