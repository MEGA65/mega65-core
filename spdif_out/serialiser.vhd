----------------------------------------------------------------------------------
-- Modified by PGS (paul@m-e-g-a.org)
-- Added parity-based inversion of pre-amble words
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
   signal last_parity : std_logic := '0';

   constant subcode          : STD_LOGIC := '0'; -- Remeember to change process sensitibity list
   constant channelStatus   : STD_LOGIC := '0'; -- Remeember to change process sensitibity list
   constant validity       : STD_LOGIC := '0'; -- Remeember to change process sensitibity list

begin
   Inst_Timebase: Timebase PORT MAP(
      clk => clk100M,
      bitclock => bitclock,
      loadSerialiser => loadSerialiser
   );

   process (subFrameCount)
   begin
     if subframeCount = "00000000" then
       if last_parity = '0' then
         preamble <= "00111001"; -- M preamble
       else
         preamble <= "11000110"; -- M preamble inverted
       end if;
      else
        -- This is a cute little hack from Mike that makes each group of frames
        -- consist of only two samples.
        if subframeCount(0) = '1' then
          if last_parity='0' then
            preamble <= "11001001"; -- Y preamble
          else
            preamble <= "00110110"; -- Y preamble inverted
          end if;
        else
          if last_parity='0' then
            preamble <= "01101001"; -- Z preamble
          else
            preamble <= "10010110"; -- Z preamble inverted
          end if;
        end if;
      end if;
   end process;
   
   process(bits, clk100M, bitclock, loadSerialiser, preamble, auxAudioBits, sample_left, sample_right, parity_left, parity_right)
   begin
      if clk100M'event and clk100M = '1' then
        sample2_left      <= sample_left(19 downto 4) & "0000";
        sample2_right      <= sample_right(19 downto 4) & "0000";
        spdifOut    <= current;
   
        parity_left <= auxAudioBits(3) xor auxAudioBits(2) xor auxAudioBits(1) xor auxAudioBits(0) xor
             sample_left(19)      xor sample_left(18)      xor sample_left(17)      xor sample_left(16)      xor
             sample_left(15)      xor sample_left(14)      xor sample_left(13)      xor sample_left(12)      xor
             sample_left(11)      xor sample_left(10)      xor sample_left(9)       xor sample_left(8)       xor
             sample_left(7)       xor sample_left(6)       xor sample_left(5)       xor sample_left(4)       xor
             sample_left(3)       xor sample_left(2)       xor sample_left(1)       xor sample_left(0)       xor 
             subcode         xor validity        xor channelStatus   xor '0';
        parity_right <= auxAudioBits(3) xor auxAudioBits(2) xor auxAudioBits(1) xor auxAudioBits(0) xor
             sample_right(19)      xor sample_right(18)      xor sample_right(17)      xor sample_right(16)      xor
             sample_right(15)      xor sample_right(14)      xor sample_right(13)      xor sample_right(12)      xor
             sample_right(11)      xor sample_right(10)      xor sample_right(9)       xor sample_right(8)       xor
             sample_right(7)       xor sample_right(6)       xor sample_right(5)       xor sample_right(4)       xor
             sample_right(3)       xor sample_right(2)       xor sample_right(1)       xor sample_right(0)       xor 
             subcode         xor validity        xor channelStatus   xor '0';
   

        if loadSerialiser = '1' then
          -- Alternate between left and right samples
           if subframeCount(0) = '0' then
             bits <= parity_left    & "1" & channelStatus    & "1" & subcode         & "1" & validity         & "1" & 
               sample2_left(19)      & "1" & sample2_left(18)      & "1" & sample2_left(17)      & "1" & sample2_left(16)      & "1" &
               sample2_left(15)      & "1" & sample2_left(14)      & "1" & sample2_left(13)      & "1" & sample2_left(12)      & "1" & 
               sample2_left(11)      & "1" & sample2_left(10)      & "1" & sample2_left( 9)      & "1" & sample2_left( 8)      & "1" & 
               sample2_left( 7)      & "1" & sample2_left( 6)      & "1" & sample2_left( 5)      & "1" & sample2_left( 4)      & "1" & 
               sample2_left( 3)      & "1" & sample2_left( 2)      & "1" & sample2_left( 1)      & "1" & sample2_left( 0)      & "1" & 
               auxAudioBits(3)& "1" & auxAudioBits(2) & "1" & auxAudioBits(1) & "1" & auxAudioBits(0) & "1" & 
                     preamble;
--             last_parity <= parity_left;
           else
            bits <= parity_right    & "1" & channelStatus    & "1" & subcode         & "1" & validity         & "1" & 
               sample2_right(19)      & "1" & sample2_right(18)      & "1" & sample2_right(17)      & "1" & sample2_right(16)      & "1" &
               sample2_right(15)      & "1" & sample2_right(14)      & "1" & sample2_right(13)      & "1" & sample2_right(12)      & "1" & 
               sample2_right(11)      & "1" & sample2_right(10)      & "1" & sample2_right( 9)      & "1" & sample2_right( 8)      & "1" & 
               sample2_right( 7)      & "1" & sample2_right( 6)      & "1" & sample2_right( 5)      & "1" & sample2_right( 4)      & "1" & 
               sample2_right( 3)      & "1" & sample2_right( 2)      & "1" & sample2_right( 1)      & "1" & sample2_right( 0)      & "1" & 
               auxAudioBits(3)& "1" & auxAudioBits(2) & "1" & auxAudioBits(1) & "1" & auxAudioBits(0) & "1" & 
               preamble;
--             last_parity <= parity_right;
            end if;

            -- There are 192 sub-frmes consisting of the left/right pairs,
            -- i.e., 96 left and 96 right samples.
            if subframeCount = (192-1) then
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
