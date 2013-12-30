library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use work.all;

entity cpu_test is
  
end cpu_test;

architecture behavior of cpu_test is
  signal clock : std_logic := '0';
  signal reset : std_logic := '0';
  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';
  signal monitor_pc : std_logic_vector(15 downto 0);
  signal monitor_opcode : std_logic_vector(7 downto 0);
  signal monitor_a : std_logic_vector(7 downto 0);
  signal monitor_x : std_logic_vector(7 downto 0);
  signal monitor_y : std_logic_vector(7 downto 0);
  signal monitor_sp : std_logic_vector(7 downto 0);
  signal monitor_p : std_logic_vector(7 downto 0);
  
  component cpu6502
    port (   clock : in STD_LOGIC;
             reset : in  STD_LOGIC;
             irq : in  STD_LOGIC;
             nmi : in  STD_LOGIC;
             monitor_pc : out STD_LOGIC_VECTOR(15 downto 0);
             monitor_opcode : out std_logic_vector(7 downto 0);
             monitor_a : out std_logic_vector(7 downto 0);
             monitor_x : out std_logic_vector(7 downto 0);
             monitor_y : out std_logic_vector(7 downto 0);
             monitor_sp : out std_logic_vector(7 downto 0);
             monitor_p : out std_logic_vector(7 downto 0);

             -- fast IO port (clocked at core clock)
             fastio_addr : out std_logic_vector(19 downto 0);
             fastio_read : out std_logic;
             fastio_write : out std_logic;
             fastio_wdata : out std_logic_vector(7 downto 0);
             fastio_rdata : in std_logic_vector(7 downto 0)
             );      
  end component;
  
  component iomapper is
    port (Clk : in std_logic;
          address : in std_logic_vector(19 downto 0);
          r : in std_logic;
          w : in std_logic;
          data_i : in std_logic_vector(7 downto 0);
          data_o : out std_logic_vector(7 downto 0)
          );
  end component;
  
  signal fastio_addr : std_logic_vector(19 downto 0);
  signal fastio_read : std_logic;
  signal fastio_write : std_logic;
  signal fastio_wdata : std_logic_vector(7 downto 0);
  signal fastio_rdata : std_logic_vector(7 downto 0);
  
begin
  cpu0: cpu6502 port map(clock => clock,reset =>reset,irq => irq,
                         nmi => nmi,monitor_pc => monitor_pc,
                         monitor_opcode => monitor_opcode,
                         monitor_a => monitor_a,
                         monitor_x => monitor_x,
                         monitor_y => monitor_y,
                         monitor_sp => monitor_sp,
                         monitor_p => monitor_p,
                         fastio_addr => fastio_addr,
                         fastio_read => fastio_read,
                         fastio_write => fastio_write,
                         fastio_wdata => fastio_wdata,
                         fastio_rdata => fastio_rdata);
  iomapper0: iomapper port map (
    clk => clock, address => fastio_addr, r => fastio_read, w => fastio_write,
    data_i => fastio_wdata, data_o => fastio_rdata);

  process
    function to_string(sv: Std_Logic_Vector) return string is
      use Std.TextIO.all;
      variable bv: bit_vector(sv'range) := to_bitvector(sv);
      variable lp: line;
    begin
      write(lp, bv);
      return lp.all;
    end;
  begin  -- process tb
    for i in 1 to 10 loop
      clock <= '1';
      report "clock=1 (reset)" severity note;
      wait for 10 ns;
      clock <= '0';
      report "clock=0 (reset)" severity note;
      wait for 10 ns;      
    end loop;  -- i
    reset <= '1';
    report "reset released" severity note;
    for i in 1 to 1000 loop
      clock <= '1';
      report "clock=1, pc=" & to_string(monitor_pc) severity note;
      report "op=" & to_string(monitor_opcode)
        & ", sp=" & to_string(monitor_sp)
        & ", a=" & to_string(monitor_sp)
        severity note;

      wait for 10 ns;
      clock <= '0';
      -- report "clock=0 (run)" severity note;
      wait for 10 ns;      
    end loop;  -- i
    assert false report "End of simulation" severity failure;
  end process;
end behavior;

