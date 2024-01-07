use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity sim74LS165 is
  port (
    q : in unsigned(7 downto 0);
    ser : in std_logic;
    sh_ld_n : in std_logic;       -- latch sr into register
    clk : in std_logic;      -- shift register clock
    clk_inhibit : in std_logic;      --  clock inhibit
    q_h : out std_logic;  -- cascade output
    q_h_n : out std_logic  -- cascade output
    );
end sim74LS165;

architecture simulated of sim74LS165 is

  signal sr : unsigned(7 downto 0);
  
begin

  process (clk, q, ser, sh_ld_n, clk_inhibit) is
    if rising_edge(clk) and clk_inhibit='0' then
      -- Reset register contents
      if sh_ld_n = '0' then
        sr <= q;
      else 
        -- Advance bits through shift register.
        sr(0) <= ser;
        sr(7 downto 1) <= sr(6 downto 0);
        q_h <= sr(7);
        q_h_n <= not sr(7);
      end if;      
    end if;
  end process;
end simulated;
    
