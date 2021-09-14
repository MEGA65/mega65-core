
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity mfm_bits_to_bytes is
  port (
    clock40mhz : in std_logic;

    sync_in : in std_logic;
    bit_in : in std_logic;
    bit_valid : in std_logic;

    sync_out : out std_logic := '0';
    byte_out : out unsigned(7 downto 0);
    byte_valid : out std_logic := '0'
    );
end mfm_bits_to_bytes;

architecture behavioural of mfm_bits_to_bytes is

  signal partial_byte : unsigned(6 downto 0) := (others => '0');
  signal bit_count : integer range 0 to 7 := 0;

begin

  process (clock40mhz) is
  begin
    if rising_edge(clock40mhz) then
      if sync_in='1' then
        report "B2B: Sync $A1 detected";
        sync_out <= '1';
        byte_out <= x"A1";
        bit_count <= 0;
      elsif bit_valid='1' then
        if bit_count = 7 then
          -- We now have a complete byte, so output it
          byte_out(7 downto 1) <= partial_byte;
          byte_out(0) <= bit_in;
          report "B2B: MFM byte $" & to_hstring(partial_byte&bit_in);
          byte_valid <= '1';
          bit_count <= 0;
        else
          -- We have the next bit
          report "B2B: Latching bit " & std_logic'image(bit_in);
          byte_valid <= '0';
          bit_count <= bit_count + 1;
          partial_byte(6 downto 1) <= partial_byte(5 downto 0);
          partial_byte(0) <= bit_in;
        end if;
      else
        byte_valid <= '0';
        sync_out <= '0';
      end if;
    end if;    
  end process;
end behavioural;

