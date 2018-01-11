
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity mfm_gaps is
  port (
    clock50mhz : in std_logic;
    f_rdata : in std_logic;

    packed_rdata : out std_logic_vector(7 downto 0);
    
    gap_valid : out std_logic := '0';
    gap_length : out unsigned(15 downto 0)
    );
end mfm_gaps;

architecture behavioural of mfm_gaps is

  signal counter : integer := 0;
  signal last_rdata : std_logic := '0';

  signal recent_rdata : std_logic_vector(6 downto 0) := "0000000";
  signal recent_bits : integer range 0 to 7 := 0;
  signal recent_toggle : std_logic := '0';
  
begin

  process (clock50mhz,f_rdata) is
  begin
    if rising_edge(clock50mhz) then
      last_rdata <= f_rdata;

      -- Produced packed rdata samples for debugging
      if recent_bits = 6 then
        packed_rdata(5 downto 0) <= recent_rdata;
        packed_rdata(6) <= '0';
        packed_rdata(7) <= recent_toggle;
        recent_toggle <= not recent_toggle;
        recent_bits <= 2;
      else
        recent_bits <= recent_bits + 2;
      end if;
      recent_rdata(6 downto 2) <= recent_rdata(4 downto 0);
      recent_rdata(1) <= f_rdata;
      recent_rdata(0) <= last_rdata;
      
      if f_rdata='0' then
        if counter /= 0 then
          -- Start of pulse
          gap_valid <= '1';
          gap_length <= to_unsigned(counter,16);
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

