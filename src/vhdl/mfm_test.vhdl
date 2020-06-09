library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use STD.textio.all;
use work.all;
use work.debugtools.all;
use work.cputypes.all;

entity mfm_test is
  
end mfm_test;

architecture behavior of mfm_test is

  type CharFile is file of character;

  signal cpuclock : std_logic := '1';
  signal pixelclock : std_logic := '1';
  signal clock163 : std_logic := '1';
  signal clock325 : std_logic := '1';

  signal ready_for_next : std_logic := '0';
  signal f_write : std_logic := '0';
  signal byte_valid : std_logic := '0';
  signal byte_in : unsigned(7 downto 0) := x"A1";
  signal clock_byte_in : unsigned(7 downto 0) := x"FB";

  signal f_rdata : std_logic;
  
begin

  process is
    file trace : CharFile;
    variable c : character;
  begin
    while true loop
      file_open(trace,"assets/synthesised-60ns.dat",READ_MODE);
      while not endfile(trace) loop
        Read(trace,c);
        f_rdata <= std_logic(to_unsigned(character'pos(c),8)(4));
        wait for 6 ns;
      end loop;
      file_close(trace);
    end loop;
  end process;

  mfmenc0:
    entity work.mfm_bits_to_gaps port map (
      clock40mhz => cpuclock,
      cycles_per_interval => to_unsigned(80,0),
      write_precomp_enable => '1',
      ready_for_next => ready_for_next,
      f_write => f_write,
      byte_valid => byte_valid,
      byte_in => byte_in,
      clock_byte_in => clock_byte_in
    );

  process (cpuclock)
  begin
    if rising_edge(cpuclock) then
      if ready_for_next = '1' then
        byte_valid <= '1';
      else
        byte_valid <= '0';
      end if;
    end if;
  end process;
  
  
  process
  begin  -- process tb

    for i in 1 to 2000000 loop
      cpuclock <= '0';
      wait for 12500 ps;
      cpuclock <= '1';
      wait for 12500 ps;      
    end loop;
    
  end process;
  
  
  process
  begin  -- process tb
    report "beginning simulation" severity note;

    wait for 3 ns;
    
    for i in 1 to 2000000 loop

      clock325 <= '0';
      pixelclock <= '0';
      cpuclock <= '0';
      clock163 <= '0';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      clock163 <= '1';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      pixelclock <= '1';
      clock163 <= '0';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      clock163 <= '1';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      pixelclock <= '0';
      cpuclock <= '1';
      clock163 <= '0';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      clock163 <= '1';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      pixelclock <= '1';
      clock163 <= '0';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      clock163 <= '1';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
    end loop;  -- i
    assert false report "End of simulation" severity failure;
  end process;
    
end behavior;

