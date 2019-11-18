----------------------------------------------------------------------------------
-- Reworked by PGS (paul@m-e-g-a.org).
-- Generate bitclock that is 128x sample rate
-- Once every 64 bitclocks, we generate a loadSerialiser signal to
-- load the next sample (either left or right)
----------------------------------------------------------------------------------
-- Engineer: Mike Field (hamster@snap.net.nz)
-- 
-- Module Name:    Timebase - Behavioral 
-- Description: Generates bit clock signals for a SPDIF output
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity Timebase is
    Port ( clk : in  STD_LOGIC;
           bitclock : out  STD_LOGIC;
			  loadSerialiser : OUT std_logic);
end Timebase;

architecture Behavioral of Timebase is

  constant sample_rate : integer := 44100;
  constant bit_rate : integer := sample_rate * 64;
  constant ticks_per_bit : integer := 100000000 / bit_rate;

  signal sample_counter : integer := 0;
  signal bit_counter : integer := 0;
  
begin
   process(clk)
   begin
      if clk'event and clk = '1' then
        if bit_counter /= ticks_per_bit then
          bit_counter <= bit_counter + 1;
          bitclock <= '0';
          loadSerialiser <= '0';
        else
          bitclock <= '1';
          bit_counter <= '0';
          if sample_counter /= 64 then
            sample_counter <= sample_counter + 1;
            loadSerialiser <= '0';
          else
            sample_counter <= 0;
            loadSerialiser <= '1';
          end if;
        end if;
      end if;
   end process;
end Behavioral;
