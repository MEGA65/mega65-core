use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity virtual_to_matrix is
  port (Clk : in std_logic;        

        key1 : in unsigned(7 downto 0);
        key2 : in unsigned(7 downto 0);
        key3 : in unsigned(7 downto 0);
        
        -- Virtualised keyboard matrix
        matrix : out std_logic_vector(71 downto 0) := (others => '1')
        );

end virtual_to_matrix;

architecture behavioral of virtual_to_matrix is

  signal scan_phase : integer range 0 to 71 := 0;

  -- Scanned state of the keyboard and joysticks
  signal matrix_internal : std_logic_vector(71 downto 0) := (others => '1');

  signal key1_drive : unsigned(7 downto 0);
  signal key2_drive : unsigned(7 downto 0);
  signal key3_drive : unsigned(7 downto 0);
  
begin
  process (clk)

  begin
    if rising_edge(clk) then

      -- Present virtualised keyboard
      matrix <= matrix_internal;

      key1_drive <= key1;
      key2_drive <= key2;
      key3_drive <= key3;
      
      if (key1_drive = to_unsigned(scan_phase,8))
        or (key2_drive = to_unsigned(scan_phase,8))
        or (key3_drive = to_unsigned(scan_phase,8))
      then
        matrix_internal(scan_phase) <= '0';
      else
        matrix_internal(scan_phase) <= '1';
      end if;
      
    end if;
  end process;
end behavioral;


    
