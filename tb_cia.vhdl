library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use work.all;
use work.debugtools.all;

entity tb_cia is
  
end tb_cia;

architecture behavior of tb_cia is

  component cia6526 is
    port (
      cpuclock : in std_logic;
      todclock : in std_logic;
      reset : in std_logic;
      irq : out std_logic := '1';

      ---------------------------------------------------------------------------
      -- fast IO port (clocked at core clock). 1MB address space
      ---------------------------------------------------------------------------
      cs : in std_logic;
      fastio_addr : in unsigned(3 downto 0);
      fastio_write : in std_logic;
      fastio_wdata : in unsigned(7 downto 0);
      fastio_rdata : out unsigned(7 downto 0);

      portaout : out std_logic_vector(7 downto 0);
      portain : in std_logic_vector(7 downto 0);
      
      portbout : out std_logic_vector(7 downto 0);
      portbin : in std_logic_vector(7 downto 0);

      flagin : in std_logic;

      pcout : out std_logic;

      spout : out std_logic;
      spin : in std_logic;

      countout : out std_logic;
      countin : in std_logic);
  end component;

  signal clock : std_logic := '0';
  signal todclock : std_logic := '1';
  signal reset : std_logic := '0';
  signal irq : std_logic;
  signal cs : std_logic;
  signal fastio_addr : unsigned(3 downto 0) := (others => '1');
  signal fastio_write : std_logic;
  signal fastio_wdata : unsigned(7 downto 0) := (others => '1');
  signal fastio_rdata :  unsigned(7 downto 0);
  signal portaout :  std_logic_vector(7 downto 0);
  signal portain : std_logic_vector(7 downto 0) := (others => '1');
  signal portbout :  std_logic_vector(7 downto 0);
  signal portbin : std_logic_vector(7 downto 0) := (others => '1');
  signal flagin : std_logic := '1';
  signal pcout :  std_logic;
  signal spout :  std_logic;
  signal spin : std_logic := '1';
  signal countout :  std_logic;
  signal countin : std_logic := '1';
  
begin
  
  cia1: cia6526 port map (
    cpuclock => clock,
    todclock => todclock,
    reset => reset,
    irq => irq,
    cs => cs,
    fastio_addr => fastio_addr,
    fastio_write => fastio_write,
    fastio_rdata => fastio_rdata,
    fastio_wdata => fastio_wdata,
    
    portaout => portaout,
    portbout => portbout,
    portain => portain,
    portbin => portbin,
    flagin => flagin,
    spin => spin,
    countin => countin
    );

    process
  begin  -- process tb
    report "beginning simulation" severity note;

    portbin <= x"AA"; 

    report "TEST1: Can read input value on port with DDR=all in." severity note;
    -- Set DDR for portb to all input
    fastio_addr <= x"3";
    fastio_wdata <= x"00";
    fastio_write <= '1';
    cs <= '1';
    clock <= '1';
    wait for 5 ns;
    clock <= '0';
    wait for 5 ns;
    -- Read from portb
    fastio_addr <= x"1";
    fastio_wdata <= x"00";
    fastio_write <= '0';
    cs <= '1';
    clock <= '1';
    wait for 5 ns;
    clock <= '0';
    wait for 5 ns;
    report "read port b from register 0 as $" & to_hstring(fastio_rdata) severity note;
    assert fastio_rdata = x"AA" report "Did not read correct value from port" severity failure;

    report "TEST2: Can read bits of input value and output  on port DDR with mixed bits." severity note;
    -- Set DDR for portb to output on lower nybl
    fastio_addr <= x"3";
    fastio_wdata <= x"0F";
    fastio_write <= '1';
    cs <= '1';
    clock <= '1';
    wait for 5 ns;
    clock <= '0';
    wait for 5 ns;
    -- Set output value for portb
    fastio_addr <= x"1";
    fastio_wdata <= x"55";
    fastio_write <= '1';
    cs <= '1';
    clock <= '1';
    wait for 5 ns;
    clock <= '0';
    wait for 5 ns;
    -- Read from portb
    fastio_addr <= x"1";
    fastio_wdata <= x"00";
    fastio_write <= '0';
    cs <= '1';
    clock <= '1';
    wait for 5 ns;
    clock <= '0';
    wait for 5 ns;
    report "read port b from register 0 as $" & to_hstring(fastio_rdata) severity note;
    assert fastio_rdata = x"A5" report "Did not read correct value from port" severity failure;

    
    assert false report "Simulation completed successfully." severity failure;
  end process;
  
end behavior;
