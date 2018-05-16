library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_pdm is
end entity;

architecture foo of test_pdm is

  signal clock50mhz : std_logic := '1';
  signal sample_clock : std_logic := '0';
  signal sample_bit : std_logic := '0';
  signal sample_bit_i : std_logic := '0';
  signal sample_out : unsigned(15 downto 0) := x"0000";
  
begin

  pdm0: entity work.pdm_to_pcm 
  port map (
    clock => clock50mhz,
    sample_clock => sample_clock,
    sample_bit => sample_bit,
    sample_out => sample_out
    );
  
  process is
  begin
    sample_clock <= '0';
    clock50mhz <= '0';  
    wait for 10 ns;   
    clock50mhz <= '1';        
    wait for 10 ns;
      
    sample_clock <= '1';
    clock50mhz <= '0';
    wait for 10 ns;
    clock50mhz <= '1';
    wait for 10 ns;
      
    sample_bit_i <= not sample_bit_i;
--    sample_bit <= sample_bit_i;
    sample_bit <= '1';
  end process;

end foo;
