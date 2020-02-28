
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity ICAPE2 is
    generic(
      DEVICE_ID : std_logic_vector(27 downto 0) := X"3651093";    -- Specifies the pre-programmed
      -- Device ID value to be used for
      -- simulation purposes.
      ICAP_WIDTH : string := "X32";        -- Specifies the input and output
      -- data width.
      SIM_CFG_FILE_NAME : string := "NONE" -- Specifies the Raw Bitstream (RBT)
      -- file to be parsed by the
      -- simulation model.
      );
    port (
      O : out std_logic_vector(31 downto 0) := x"FFFFFF9B";
      CLK : in std_logic;
      CSIB : in std_logic;
      I : in std_logic_vector(31 downto 0);
      rdwrb : in std_logic
      );
end ICAPE2;

architecture fake of ICAPE2 is
begin
  process (CLK) is
    variable rev : std_logic_vector(31 downto 0);
  begin
      for chunk in 0 to (32/8)-1 loop
        for j in 0 to 7 loop
          rev(8*chunk+j)
            := I(8*chunk+(7-j));
        end loop;
      end loop;
      
      report "ICAPE2:"
        & " CS=" & std_logic'image(CSIB)
        & " RDWRB=" & std_logic'image(RDWRB)
        & " IN=$" & to_hstring(I)
        & " (reversed = $"        
        & to_hstring(rev)
        & ").";
  end process;  
    
end fake;
