use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity sim74LS595 is
  generic ( unit : integer := 999);
  port (
    q : out std_logic_vector(7 downto 0);
    ser : in std_logic;
    g_n : in std_logic;       -- Gate, i.e., oe_n
    rclk : in std_logic;       -- latch sr into register
    srclk : in std_logic;      -- shift register clock
    srclr_n : in std_logic;   -- clear shift register
    q_h_dash : out std_logic  -- cascade output
    );
end sim74LS595;

architecture simulated of sim74LS595 is

  signal sr : std_logic_vector(7 downto 0);
  signal q_int : std_logic_vector(7 downto 0);

  function to_str(signal vec: std_logic_vector) return string is
      variable result: string(0 to (vec'length-1));
    begin
      for i in vec'range loop
        case vec(i) is
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

  process (rclk, srclr_n, srclk, g_n, ser) is
  begin
    if rising_edge(srclk) then
      -- report "SRCLK ticked, latching bit " & std_logic'image(ser) ;      
      -- Advance bits through shift register.
      sr(0) <= ser;
      sr(7 downto 1) <= sr(6 downto 0);

      -- Reset register contents
      if srclr_n = '0' then
        sr <= (others => '0');
      end if;      
    end if;

    -- Allow for cascading
    if falling_edge(srclk) then
      q_h_dash <= sr(7);
    end if;

    if g_n='0' then
      q <= q_int;
    else
      q <= (others => 'Z');
    end if;
            
    if rising_edge(rclk) then
      if g_n='0' then
        report "U" & integer'image(unit) & ": RCLK rose: Latching and presenting data " & to_str(sr);
        q <= sr;
      else
        report "U" & integer'image(unit) & ": RCLK rose: Latching data " & to_str(sr);
      end if;
      q_int <= sr;
    end if;

  end process;
end simulated;
    
