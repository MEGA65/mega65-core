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
    -- purpose: write to a CIA register
    procedure write_register (
      reg      : in integer;
      value    : in unsigned(7 downto 0)) is
    begin  -- write_register
      fastio_addr <= to_unsigned(reg,4);
      fastio_wdata <= value;
      fastio_write <= '1';
      cs <= '1';
      clock <= '1';
      wait for 5 ns;
      clock <= '0';
      wait for 5 ns;
    end write_register;

    -- purpose: read a CIA register
    procedure read_register (
      reg : integer) is
    begin  -- read_register
      fastio_addr <= to_unsigned(reg,4);
      fastio_wdata <= x"00";
      fastio_write <= '0';
      cs <= '1';
      clock <= '1';
      wait for 5 ns;
      clock <= '0';
      wait for 5 ns;
    end read_register;

    -- purpose: <[description]>
    procedure wait_cycles (
      i : in integer) is
    begin  -- wait_cycles
      fastio_write <= '0';
      cs <= '0';
      for j in 0 to i loop
        clock <= '1';
        wait for 5 ns;
        clock <= '0';
        wait for 5 ns;        
      end loop;  -- j
    end wait_cycles;
  begin  -- process tb
    report "beginning simulation" severity note;

    portbin <= x"AA"; 

    report "TEST1: Can read input value on port with DDR=all in." severity note;
    -- Set DDR for portb to all input
    write_register(3,x"00");
    -- Read from portb
    read_register(1);
    report "read port b from register 0 as $" & to_hstring(fastio_rdata) severity note;
    assert fastio_rdata = x"AA" report "Did not read correct value from port" severity failure;

    
    report "TEST2: Can read bits of input value and output  on port DDR with mixed bits." severity note;
    write_register(3,x"0F"); -- Set DDR for portb to output on lower nybl    
    write_register(1,x"55"); -- Set output value for portb
    -- Read from portb
    read_register(1);
    report "read port b from register 0 as $" & to_hstring(fastio_rdata) severity note;
--    Temporarily disabled while we have merging of output and input values disabled
--    assert fastio_rdata = x"A0" report "Did not read correct value from port" severity failure;

    
    report "TEST3: Can read input bits when DDR=in, even if output bits are high." severity note;
    write_register(3,x"00"); -- Set DDR for portb to all input
    write_register(1,x"FF"); -- Set output value for portb
    read_register(1); -- Read from portb
    report "read port b from register 0 as $" & to_hstring(fastio_rdata) severity note;
    assert fastio_rdata = x"AA" report "Did not read correct value from port" severity failure;

    report "TEST4: Timer A counts phi0." severity note;
    write_register(14,x"00");           -- stop timer a
    write_register(4,x"03"); write_register(5,x"00");   -- set counter for timer a
    write_register(14,x"11");           -- start timer a
    -- Check that timer value is loaded
    read_register(4);
    assert fastio_rdata = x"03" report "timera low byte should be initial value" severity failure;
    read_register(5);
    assert fastio_rdata = x"00" report "timera low byte should be initial value" severity failure;
    -- Run CIA for some cycles to let timer a tick.
    -- CIAs divide 96MHz CPU clock down to phi0, so need ~200 cycles
    wait_cycles(200);
    -- Check that timer value is loaded
    read_register(4);
    assert fastio_rdata /= x"03" report "timera should have ticked" severity failure;
    report "after 200 clock cycles timera ticked downto to $" & to_hstring(fastio_rdata) severity note;
    -- Check that ISR is clear
    read_register(13);
    report "interrupt status register is $" & to_hstring(fastio_rdata) severity note;
    assert fastio_rdata = x"00" report "ISR should be zero" severity failure;
    -- Enable timer a interrupts
    write_register(13,x"81");
    -- Check that ISR is clear
    read_register(13);
    report "interrupt status register is $" & to_hstring(fastio_rdata) severity note;
    assert fastio_rdata = x"00" report "ISR should be zero" severity failure;
    
    assert false report "Simulation completed successfully." severity failure;
  end process;
  
end behavior;
