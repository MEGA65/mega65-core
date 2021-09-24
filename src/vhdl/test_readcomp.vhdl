library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;
use work.cputypes.all;

entity test_readcomp is
end entity;

architecture foo of test_readcomp is

  type CharFile is file of character;

  signal clock40mhz : std_logic := '1';
  signal clock80mhz : std_logic := '1';
  -- 81 = DD, 40 = HD, 20 = ED
  signal cycles_per_interval : unsigned(7 downto 0) := to_unsigned(81,8);
  
  signal cycle_count : integer := 0;

  signal gap_valid_in : std_logic := '0';
  signal gap_length_in : unsigned(15 downto 0) := (others => '0');
    
  signal gap_valid_out : std_logic := '0';
  signal gap_length_out : unsigned(15 downto 0) := (others => '0');

  signal gap_num : integer := 0;
  type gaps_t is array(0 to 10000) of integer;
  signal gap_lengths : gaps_t := (others => 0);
  
  
begin

  comp0: entity work.floppy_read_compensate port map (
    clock40mhz => clock40mhz,
    correction_enable => '1',
    cycles_per_interval => cycles_per_interval,
    gap_valid_in => gap_valid_in,
    gap_length_in => gap_length_in,
    gap_valid_out => gap_valid_out,
    gap_length_out => gap_length_out
    );
  
  process is
  begin
    while true loop
      clock40mhz <= '0';
      clock80mhz <= '0';
      wait for 5 ns;
      clock80mhz <= '1';
      wait for 5 ns;
      clock40mhz <= '1';
      clock80mhz <= '0';
      wait for 5 ns;
      clock80mhz <= '1';
      wait for 5 ns;
    end loop;
  end process;

  
  process (clock40mhz) is
  begin
    if rising_edge(clock40mhz) then
      cycle_count <= cycle_count + 1;
 
      if cycle_count = 15 then
        cycle_count <= 0;
        gap_valid_in <= '1';
        gap_length_in <= to_unsigned(gap_lengths(gap_num),16);
        gap_num <= gap_num + 1;
      else
        cycle_count <= cycle_count + 1;
      end if;
      
    end if;
  end process;
  
end foo;
