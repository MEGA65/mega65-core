library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_sc is
end entity;

architecture foo of test_sc is

  signal clock40mhz : std_logic := '0';
  signal reset_n : std_logic := '0';
  signal idle : std_logic := '1';
  signal cell_in_ready : std_logic := '1';
  signal cell_function_in_final : std_logic;
  signal cell_function_in : unsigned(15 downto 0);
  signal cell_function_in_valid : std_logic;
  signal cell_id_in : unsigned(15 downto 0);
  signal requested_cell_id : unsigned(15 downto 0) := to_unsigned(0,16);
  signal requested_cell_valid : std_logic := '0';
  signal input_value : unsigned(31 downto 0);
  signal input_cell_id : unsigned(15 downto 0);
  signal input_cell_valid : std_logic;
  signal output : unsigned(31 downto 0) := to_unsigned(0,32);
  signal output_cell_id : unsigned(15 downto 0) := to_unsigned(0,16);
  signal output_ready : std_logic := '0';  
  
begin

  cell0: entity work.sc_calc_cell 
  port map (
    clock40mhz => clock40mhz,
    reset_n => reset_n,
    idle => idle,
    cell_in_ready => cell_in_ready,
    cell_function_in_final => cell_function_in_final,
    cell_function_in => cell_function_in,
    cell_function_in_valid => cell_function_in_valid,
    cell_id_in => cell_id_in,
    requested_cell_id => requested_cell_id,
    requested_cell_valid => requested_cell_valid,
    input_value => input_value,
    input_cell_id => input_cell_id,
    input_cell_valid => input_cell_valid,
    output => output,
    output_cell_id => output_cell_id,
    output_ready => output_ready
    
    );  
  
  process is
  begin
    clock40mhz <= '0';  
    wait for 10 ns;   
    clock40mhz <= '1';        
    wait for 10 ns;
      
    clock40mhz <= '0';
    wait for 10 ns;
    clock40mhz <= '1';
    wait for 10 ns;
      
  end process;

  process (clock40mhz) is
  begin
    if rising_edge(clock40mhz) then
      report "tick";
    end if;
  end process;
  
end foo;
