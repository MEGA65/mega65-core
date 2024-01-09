use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity sim74LS165 is
  generic ( unit : integer);
  port (
    q : in std_logic_vector(7 downto 0);
    ser : in std_logic;
    sh_ld_n : in std_logic;       -- latch sr into register
    clk : in std_logic;      -- shift register clock
    clk_inhibit : in std_logic;      --  clock inhibit
    q_h : out std_logic;  -- cascade output
    q_h_n : out std_logic  -- cascade output
    );
end sim74LS165;

architecture simulated of sim74LS165 is

  signal sr : std_logic_vector(7 downto 0);
  signal last_sh_ld_n : std_logic := '0';

  
  function to_str(signal vec: std_logic_vector) return string is
      variable result: string(0 to (vec'length-1));
    begin
      for i in vec'range loop
        case vec(vec'length-1-i) is
          when 'U' => result(i) := 'U';
          when 'X' => result(i) := 'X';
          when '0' => result(i) := '0';
          when '1' => result(i) := '1';
          when 'Z' => result(i) := 'Z';
          when 'W' => result(i) := 'W';
          when 'L' => result(i) := 'L';
          when 'H' => result(i) := 'H';
          when '-' => result(i) := '-';
          when others => result(i) := '?';
        end case;
      end loop;
      return result;
    end to_str;  
  
begin

  process (clk, q, ser, sh_ld_n, clk_inhibit) is
  begin
    if rising_edge(clk) and clk_inhibit='0' then
      -- Reset register contents
      last_sh_ld_n <= sh_ld_n;
      if sh_ld_n = '0' then
        sr <= q;
        if last_sh_ld_n = '1' then
          report "U" & integer'image(unit) & ": Loading SR with " & to_str(q);
        end if;
      else 
        -- Advance bits through shift register.
--      report "U" & integer'image(unit) & ": Shifting";
        sr(0) <= ser;
        sr(7 downto 1) <= sr(6 downto 0);
        q_h <= sr(7);
        q_h_n <= not sr(7);
      end if;      
    end if;
  end process;
end simulated;
    
