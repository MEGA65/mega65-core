
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

    gap_valid : out std_logic := '0';
    gap_length : out unsigned(15 downto 0)
    );
end mfm_gaps;

architecture behavioural of mfm_gaps is

  signal counter : integer := 0;
  signal last_rdata : std_logic := '0';

begin

  process (clock50mhz,f_rdata) is
  begin
    if rising_edge(clock50mhz) then
      last_rdata <= f_rdata;
      if f_rdata='0' and last_rdata='1' then
        -- Start of pulse
        gap_valid <= '1';
        gap_length <= to_unsigned(counter,16);
        counter <= 0;
      else
        gap_valid <= '0';
        if counter /= 65535 then
          counter <= counter + 1;
        end if;
      end if;
    end if;    
  end process;
end behavioural;

