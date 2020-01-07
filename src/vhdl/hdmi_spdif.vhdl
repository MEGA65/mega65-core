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
use ieee.numeric_std.all;

entity hdmi_spdif is
  Port ( clk : in  STD_LOGIC;
         left_in : in std_logic_vector(19 downto 0);
         right_in : in std_logic_vector(19 downto 0);
         spdif_out : out  STD_LOGIC);
end hdmi_spdif;

architecture Behavioral of hdmi_spdif is

  signal sample_32 : std_logic_vector(31 downto 0) := (others => '0');
  signal sample_ack : std_logic;
  signal sample_channel : std_logic;
  
begin

  spdiftx0: entity work.spdif_encoder port map (
    up_clk => clk,
    data_clk => clk,
    resetn => '1',
    conf_mode => "0101", -- 20 bit samples
    -- 44237 = 27.083MHz/27.000MHz * 44100
    conf_ratio => std_logic_vector(to_unsigned(100000000/(192000*64),8)), -- clock divider
    conf_txdata => '1', -- sample data is valid
    conf_txen => '1', -- enable transmitter
    chstat_freq => "11", -- 192KHz sample rate
    chstat_gstat => '0', -- maybe user bit management bit 0 or 3?
    chstat_preem => '0', -- no preemphasis
    chstat_copy => '1', -- NOT copyright (negative meaning)
    chstat_audio => '1', -- normal PCM audio

    sample_data => sample_32,
    sample_data_ack => sample_ack,
    channel => sample_channel,

    spdif_tx_o => spdif_out
    );

  process (clk) is
  begin
    if rising_edge(clk) then
      -- If we put the sample in the top 20 bits, then it is REALLY
      -- loud and distorts.  So put it 7 bits down.
      if sample_channel = '0' then
        sample_32(22 downto 3) <= left_in;
      else
        sample_32(22 downto 3) <= right_in;
      end if;
    end if;
  end process;
  

end Behavioral;
