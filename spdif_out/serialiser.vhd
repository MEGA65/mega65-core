----------------------------------------------------------------------------------
-- Engineer: Mike Field <hamster@snap.net.nz>
-- 
-- Module Name:    serialiser - Behavioral 
-- Description: 
--
-- Converts a sample to S/PDIF format and send it out on the wire
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity serialiser is
    Port ( clk100M         : in  STD_LOGIC;
           auxAudioBits    : in  STD_LOGIC_VECTOR (3 downto 0);
           sample_left     : in  STD_LOGIC_VECTOR (19 downto 0);
           sample_right    : in  STD_LOGIC_VECTOR (19 downto 0);
           nextSample      : out STD_LOGIC;
           channelA        : out STD_LOGIC;
           spdifOut        : out STD_LOGIC);
end serialiser;

architecture Behavioral of serialiser is
   COMPONENT Timebase
   PORT(
      clk             : IN std_logic;          
      bitclock       : OUT std_logic;
      loadSerialiser : OUT std_logic
      );
   END COMPONENT;

   signal bitclock   : std_logic;
   signal loadSerialiser : std_logic;

   signal bits          : std_logic_vector(63 downto 0) := (others => '0');
   signal current       : std_logic := '0';
   signal preamble      : STD_LOGIC_VECTOR (7 downto 0);
   signal sample2_left  : STD_LOGIC_VECTOR (19 downto 0);
   signal sample2_right : STD_LOGIC_VECTOR (19 downto 0);
   signal subframeCount : STD_LOGIC_VECTOR (7 downto 0) := "00000000";
   signal parity_left   : STD_LOGIC;         
   signal parity_right  : STD_LOGIC;         

   constant subcode          : STD_LOGIC := '0'; -- Remeember to change process sensitibity list
   constant channelStatus   : STD_LOGIC := '0'; -- Remeember to change process sensitibity list
   constant validity       : STD_LOGIC := '0'; -- Remeember to change process sensitibity list

begin
   Inst_Timebase: Timebase PORT MAP(
      clk => clk100M,
      bitclock => bitclock,
      loadSerialiser => loadSerialiser
   );

   sample2_left      <= sample_left(19 downto 4) & "0000";
   sample2_right      <= sample_right(19 downto 4) & "0000";
   spdifOut    <= current;
   nextSample  <= loadSerialiser;
   channelA    <= subFrameCount(0);
   
   parity_left <= auxAudioBits(3) xor auxAudioBits(2) xor auxAudioBits(1) xor auxAudioBits(0) xor
             sample2_left(19)      xor sample2_left(18)      xor sample2_left(17)      xor sample2_left(16)      xor
             sample2_left(15)      xor sample2_left(14)      xor sample2_left(13)      xor sample2_left(12)      xor
             sample2_left(11)      xor sample2_left(10)      xor sample2_left(9)       xor sample2_left(8)       xor
             sample2_left(7)       xor sample2_left(6)       xor sample2_left(5)       xor sample2_left(4)       xor
             sample2_left(3)       xor sample2_left(2)       xor sample2_left(1)       xor sample2_left(0)       xor 
             subcode         xor validity        xor channelStatus   xor '0';
   parity_right <= auxAudioBits(3) xor auxAudioBits(2) xor auxAudioBits(1) xor auxAudioBits(0) xor
             sample2_right(19)      xor sample2_right(18)      xor sample2_right(17)      xor sample2_right(16)      xor
             sample2_right(15)      xor sample2_right(14)      xor sample2_right(13)      xor sample2_right(12)      xor
             sample2_right(11)      xor sample2_right(10)      xor sample2_right(9)       xor sample2_right(8)       xor
             sample2_right(7)       xor sample2_right(6)       xor sample2_right(5)       xor sample2_right(4)       xor
             sample2_right(3)       xor sample2_right(2)       xor sample2_right(1)       xor sample2_right(0)       xor 
             subcode         xor validity        xor channelStatus   xor '0';
   
   process (subFrameCount)
   begin
      if subframeCount = "00000000" then
         preamble <= "00111001"; -- M preamble
      else
        -- This is a cute little hack from Mike that makes each group of frames
        -- consist of only two samples.
         if subframeCount(0) = 0 then
            preamble <= "11001001"; -- Y preamble
         else
            preamble <= "01101001"; -- Z preamble
         end if;
      end if;
   end process;
   
   process(bits, clk100M, bitclock, loadSerialiser, preamble, auxAudioBits, sample, parity)
   begin
      if clk100M'event and clk100M = '1' then
        if loadSerialiser = '1' then
          -- Alternate between left and right samples
           if subframeCount(0) = 0 then
             bits <= parity_left    & "1" & channelStatus    & "1" & subcode         & "1" & validity         & "1" & 
               sample2_left(19)      & "1" & sample2_left(18)      & "1" & sample2_left(17)      & "1" & sample2_left(16)      & "1" &
               sample2_left(15)      & "1" & sample2_left(14)      & "1" & sample2_left(13)      & "1" & sample2_left(12)      & "1" & 
               sample2_left(11)      & "1" & sample2_left(10)      & "1" & sample2_left( 9)      & "1" & sample2_left( 8)      & "1" & 
               sample2_left( 7)      & "1" & sample2_left( 6)      & "1" & sample2_left( 5)      & "1" & sample2_left( 4)      & "1" & 
               sample2_left( 3)      & "1" & sample2_left( 2)      & "1" & sample2_left( 1)      & "1" & sample2_left( 0)      & "1" & 
               auxAudioBits(3)& "1" & auxAudioBits(2) & "1" & auxAudioBits(1) & "1" & auxAudioBits(0) & "1" & 
                     preamble;
           else
            bits <= parity_right    & "1" & channelStatus    & "1" & subcode         & "1" & validity         & "1" & 
               sample2_right(19)      & "1" & sample2_right(18)      & "1" & sample2_right(17)      & "1" & sample2_right(16)      & "1" &
               sample2_right(15)      & "1" & sample2_right(14)      & "1" & sample2_right(13)      & "1" & sample2_right(12)      & "1" & 
               sample2_right(11)      & "1" & sample2_right(10)      & "1" & sample2_right( 9)      & "1" & sample2_right( 8)      & "1" & 
               sample2_right( 7)      & "1" & sample2_right( 6)      & "1" & sample2_right( 5)      & "1" & sample2_right( 4)      & "1" & 
               sample2_right( 3)      & "1" & sample2_right( 2)      & "1" & sample2_right( 1)      & "1" & sample2_right( 0)      & "1" & 
               auxAudioBits(3)& "1" & auxAudioBits(2) & "1" & auxAudioBits(1) & "1" & auxAudioBits(0) & "1" & 
               preamble;
            end if;
            
            if subframeCount = 191 then
               subFrameCount <= (others => '0');
            else
               subFrameCount <= subFrameCount +1;
            end if;

         elsif  bitclock = '1' then
            current <= current xor bits(0) xor '0';
            bits <= "0" & bits(63 downto 1);
         end if;
      end if;
   end process;
end Behavioral;
