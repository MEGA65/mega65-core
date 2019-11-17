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

entity hdmi_spdif is
  Port ( clk : in  STD_LOGIC;
         left_in : in std_logic_vector(19 downto 0);
         right_in : in std_logic_vector(19 downto 0);
         spdif_out : out  STD_LOGIC);
end hdmi_spdif;

architecture Behavioral of hdmi_spdif is

   COMPONENT serialiser
   PORT(
      clk100m          : IN std_logic;
      auxAudioBits   : IN std_logic_vector(3 downto 0);
      sample_left         : IN std_logic_vector(19 downto 0);
      sample_right         : IN std_logic_vector(19 downto 0);
      nextSample       : OUT std_logic;
      channelA        : OUT std_logic;
      spdifOut       : OUT std_logic       
      );
   END COMPONENT;

   signal nextSample   : std_logic;
   signal channelA   : std_logic;
begin

   Inst_serialiser: serialiser PORT MAP(
      clk100M          => clk,
      auxAudioBits   => "0000",
      sample_left    => left_in,
      sample_right   => right_in,
      nextSample     => nextSample,
      channelA       => channelA,
      spdifOut       => spdif_out
   );

end Behavioral;
