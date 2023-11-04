
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;
use work.victypes.all;

entity cpu6502 is 
port (
      address : buffer unsigned(15 downto 0);
      address_next : out unsigned(15 downto 0);
      clk : in std_logic;
      cpu_int : out std_logic;
      cpu_state : out unsigned(7 downto 0);
      data_i : in unsigned(7 downto 0);
      data_o : out unsigned(7 downto 0);
      data_o_next : out unsigned(7 downto 0);
      irq : in std_logic;
      nmi : in std_logic;
      ready : in std_logic;
      reset : in std_logic;
      sync : buffer std_logic;
      t : out unsigned(2 downto 0);
      write : out std_logic;
      write_next : buffer std_logic
    );
end entity cpu6502;

architecture vapourware of cpu6502 is
begin  
end vapourware;

