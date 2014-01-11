use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;

entity simple6502 is
  port (
    Clock : in std_logic;
    reset : in std_logic;
    irq : in std_logic;
    nmi : in std_logic;
    monitor_pc : out std_logic_vector(15 downto 0);
    monitor_opcode : out std_logic_vector(7 downto 0);
    monitor_a : out std_logic_vector(7 downto 0);
    monitor_x : out std_logic_vector(7 downto 0);
    monitor_y : out std_logic_vector(7 downto 0);
    monitor_sp : out std_logic_vector(7 downto 0);
    monitor_p : out std_logic_vector(7 downto 0);
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : out std_logic_vector(19 downto 0);
    fastio_read : out std_logic;
    fastio_write : out std_logic;
    fastio_wdata : out std_logic_vector(7 downto 0);
    fastio_rdata : in std_logic_vector(7 downto 0)
    );
end entity simple6502;

architecture Behavioural of simple6502 is
  signal reg_a : unsigned(7 downto 0);
  signal reg_x : unsigned(7 downto 0);
  signal reg_y : unsigned(7 downto 0);
  signal reg_sp : unsigned(7 downto 0);
  signal reg_pc : unsigned(15 downto 0) := (others => '0');
begin
  process(clock)
  begin
    if rising_edge(clock) then
      reg_pc <= reg_pc + 1;     
    end if;
  end process;
end Behavioural;
