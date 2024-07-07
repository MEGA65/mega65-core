use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity sim74LS595 is
  port (
    q : out unsigned(7 downto 0);
    ser : in std_logic;
    g_n : in std_logic;       -- Gate, i.e., oe_n
    rck : in std_logic;       -- latch sr into register
    srck : in std_logic;      -- shift register clock
    srclr_n : in std_logic;   -- clear shift register
    q_h_dash : out std_logic  -- cascade output
    );
end sim74LS595;

architecture simulated of sim74LS595 is

  signal sr : unsigned(7 downto 0);
  signal q_int : unsigned(7 downto 0);
  
begin

  process (rclk, srclr_n, srck, g_n, ser) is
    if rising_edge(srclk) then
      -- Advance bits through shift register.
      sr(0) <= ser;
      sr(7 downto 1) <= sr(6 downto 0);

      -- Reset register contents
      if srclr_n = '0' then
        sr <= (others '0');
      end if;      
    end if;

    -- Allow for cascading
    if falling_edge(srclk) then
      q_h_dash <= sr(6);
    end if;

    if rising_edge(rclk) then
      q_int <= sr;
    end if;

    if g_n='0' then
      q <= q_int;
    else
      q <= (others => 'Z');
    end if;
    
  end process;
end simulated;
    
