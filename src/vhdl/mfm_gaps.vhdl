
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity mfm_gaps is
  port (
    clock40mhz : in std_logic;
    f_rdata : in std_logic;

    packed_rdata : out std_logic_vector(7 downto 0);
    
    gap_valid : out std_logic := '0';
    gap_length : out unsigned(15 downto 0) := x"0000";
    gap_count : out unsigned(3 downto 0) := x"0"
    );
end mfm_gaps;

architecture behavioural of mfm_gaps is

  signal counter : integer := 0;
  signal last_rdata : std_logic := '1';
  signal last_last_rdata : std_logic := '1';

  signal recent_rdata : std_logic_vector(6 downto 0) := "0000000";
  signal recent_bits : integer range 0 to 7 := 0;
  signal recent_toggle : unsigned(1 downto 0) := "00";

  signal gap_count_internal : unsigned(3 downto 0) := x"0";
  
begin

  process (clock40mhz,f_rdata) is
  begin
    if rising_edge(clock40mhz) then
      last_rdata <= f_rdata;
      last_last_rdata <= last_rdata;

      -- Produced packed rdata samples for debugging
      if recent_bits = 6 then
        packed_rdata(5 downto 0) <= recent_rdata(5 downto 0);
        packed_rdata(7 downto 6) <= std_logic_vector(recent_toggle);
        if recent_toggle /= "11" then
          recent_toggle <= recent_toggle + 1;
        else
          recent_toggle <= "00";
        end if;
        recent_bits <= 2;
      else
        recent_bits <= recent_bits + 2;
      end if;
      recent_rdata(6 downto 2) <= recent_rdata(4 downto 0);
      recent_rdata(1) <= f_rdata;
      recent_rdata(0) <= last_rdata;
      
      if last_rdata='0' and last_last_rdata='1' then
        if true then
          -- Start of pulse
          gap_valid <= '1';
          gap_length <= to_unsigned(counter,16);
          if gap_count_internal /= x"f" then
            gap_count <= gap_count_internal + 1;
            gap_count_internal <= gap_count_internal + 1;
          else
            gap_count <= x"0";
            gap_count_internal <= x"0";
          end if;
        end if;
        counter <= 0;
--        report "GAP of " & integer'image(counter) & " cycles.";
      else
        gap_valid <= '0';
        if counter /= 65535 then
          counter <= counter + 1;
        end if;
      end if;
    end if;    
  end process;
end behavioural;

