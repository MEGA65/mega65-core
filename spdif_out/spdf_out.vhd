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
      nextSample    : IN std_logic;
      channelA      : IN std_logic;          
      Sample      : OUT std_logic_vector(19 downto 0)
      );
   END COMPONENT;


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
   signal sample_left      : std_logic_vector(19 downto 0);
   signal sample_right      : std_logic_vector(19 downto 0);
begin

   Inst_soundSource: soundSource PORT MAP(
      Clk => clk,
      nextSample => nextSample,
      channelA => channelA,
      Sample => sample_left
   );

   Inst_serialiser: serialiser PORT MAP(
      clk100M          => clk,
      auxAudioBits   => "0000",
      sample_left          => sample_left,
      sample_right          => sample_left,
      nextSample       => nextSample,
      channelA       => channelA,
      spdifOut       => spdif_out
   );

end Behavioral;
