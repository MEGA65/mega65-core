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
        touch_key1 : in unsigned(7 downto 0);
        touch_key2 : in unsigned(7 downto 0);
        restore_out : out std_logic := '1';
        
        -- Virtualised keyboard matrix
        matrix_col : out std_logic_vector(7 downto 0) := (others => '1');
        matrix_col_idx : in integer range 0 to 15
        
        );

end virtual_to_matrix;

architecture behavioral of virtual_to_matrix is

  signal scan_phase : integer range 0 to 71 := 0;

  signal key1_drive : unsigned(7 downto 0) := (others => '0');
  signal key2_drive : unsigned(7 downto 0) := (others => '0');
  signal key3_drive : unsigned(7 downto 0) := (others => '0');
  signal touch_key1_drive : unsigned(7 downto 0) := (others => '0');
  signal touch_key2_drive : unsigned(7 downto 0) := (others => '0');
  
  -- keyboard matrix ram inputs
  signal keyram_address : integer range 0 to 15 := 0;
  signal keyram_di : std_logic_vector(7 downto 0) := (others => '0');
  signal keyram_wea : std_logic_vector(7 downto 0) := (others => '0');

  signal restore_countdown : integer := 0;
  signal restore_latch : std_logic := '0';
  
begin

  virt_kmm: entity work.kb_matrix_ram
  port map (
    clkA => Clk,
    addressa => keyram_address,
    dia => keyram_di,
    wea => keyram_wea,
    addressb => matrix_col_idx,
    dob => matrix_col
    );
  
  process (clk)
  variable km_index : integer range 0 to 127;
  variable km_value : std_logic;
  variable km_index_col : unsigned(2 downto 0);
  
  begin
    if rising_edge(clk) then

      -- Present virtualised keyboard
      --matrix <= matrix_internal;

      key1_drive <= key1;
      key2_drive <= key2;
      key3_drive <= key3;
      touch_key1_drive <= touch_key1;
      touch_key2_drive <= touch_key2;

      -- x"52" = capital R = hold restore key down
      -- x"72" = small R = tap restore, with a timeout of 100 cycles
      if key1 = x"52" or key2 = x"52" or key3 = x"52" then
        restore_out <= '0';
      else
        if restore_countdown = 0 then
          restore_out <= '1';
        else
          restore_countdown <= restore_countdown - 1;
        end if;
      end if;
      if key1 = x"72" or key2 = x"72" or key3 = x"72" then
        if restore_latch = '0' then
          restore_latch <= '1';
          restore_out <= '0';
          restore_countdown <= 100;
        end if;
      else
        restore_latch <= '0';
      end if;
      
      if (safe_to_integer(key1_drive) = scan_phase)
        or (safe_to_integer(key2_drive) = scan_phase)
        or (safe_to_integer(key3_drive) = scan_phase)
        or (safe_to_integer(touch_key1_drive) = scan_phase)
        or (safe_to_integer(touch_key2_drive) = scan_phase)
      then
        km_value := '0';
      else
        km_value := '1';
      end if;

      km_index := scan_phase;

      if scan_phase /= 71 then
        scan_phase <= scan_phase + 1;
      else
        scan_phase <= 0;
      end if;

      km_index_col := to_unsigned(km_index,7)(2 downto 0);          
      case km_index_col is 
        when "000" => keyram_wea <= "00000001";
        when "001" => keyram_wea <= "00000010";
        when "010" => keyram_wea <= "00000100";
        when "011" => keyram_wea <= "00001000";
        when "100" => keyram_wea <= "00010000";
        when "101" => keyram_wea <= "00100000";
        when "110" => keyram_wea <= "01000000";
        when "111" => keyram_wea <= "10000000";
        when others => keyram_wea <= x"00";
      end case;
    
      keyram_address <= safe_to_integer(to_unsigned(km_index,7)(6 downto 3));
      keyram_di <= (7 downto 0 => km_value); -- replicate value bit across byte
      
    end if;
  end process;
end behavioral;


    
