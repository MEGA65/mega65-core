
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity sc_calc_cell is
  port (
    clock40mhz : in std_logic;

    reset_n : in std_logic;
    
    -- Are we completely idle?
    idle : out std_logic := '1';
    
    -- Are we ready to accept the next cell?
    cell_in_ready : out std_logic := '1';

    -- Progressively read in the next cell
    cell_function_in_final : in std_logic;
    cell_function_in : in unsigned(15 downto 0);
    cell_function_in_valid : in std_logic;
    cell_id_in : in unsigned(15 downto 0);

    -- Cell ID we need next
    requested_cell_id : out unsigned(15 downto 0) := to_unsigned(0,16);
    requested_cell_valid : out std_logic := '0';
    
    -- The value of a cell that we have requested
    input_value : in unsigned(31 downto 0);
    input_cell_id : in unsigned(15 downto 0);
    input_cell_valid : in std_logic;

    -- Our value when complete
    output : out unsigned(31 downto 0) := to_unsigned(0,32);
    output_cell_id : out unsigned(15 downto 0) := to_unsigned(0,16);
    output_ready : out std_logic := '0'
    
    );
end sc_calc_cell;

architecture behavioural of sc_calc_cell is

  -- signals
  signal have_cell_waiting : std_logic := '0';
  signal executing_cell_function : std_logic := '0';
  signal reading_cell_function : std_logic := '0';
  
  signal cell_exec_id : unsigned(15 downto 0) := x"FFFF";
  signal cell_exec_func : unsigned(95 downto 0) := (others => '0');
  signal cell_exec_ofs : integer range 0 to 7 := 0;
  
  signal cell_buf_id : unsigned(15 downto 0) := x"FFFF";
  signal cell_buf_func : unsigned(95 downto 0) := (others => '0');
  
begin

  -- instantiations and processes here

  process (clock40mhz) is
  begin
    if rising_edge(clock40mhz) then
      if reset_n='0' then
        -- Reset SPC state
        idle <= '1';
        cell_in_ready <= '1';
        output_ready <= '0';
        requested_cell_valid <= '0';
        requested_cell_id <= to_unsigned(0,16);

        reading_cell_function <= '1';

        executing_cell_function <= '0';
      else
        if reading_cell_function = '1' then
          -- Mark us as not able to receive another cell for execution
          cell_in_ready <= '0';
          -- Record the cell description
          if cell_function_in_valid='1' and have_cell_waiting='0' then
            cell_buf_id <= cell_id_in;
            cell_buf_func(95 downto 80) <= cell_function_in;
            cell_buf_func(79 downto 0) <= cell_buf_func(95 downto 80);

            if cell_function_in_final='1' then
              -- We now have a complete cell description, indicate that
              -- we are ready to execute it
              have_cell_waiting <= '1';              
            end if;
          end if;
          if executing_cell_function='1' then
            -- Execute the current cell
          elsif have_cell_waiting='1' then
            -- Start executing the next cell once its ready, and
            -- we have finished executing the previous cell
            cell_exec_id <= cell_buf_id;
            cell_exec_func <= cell_buf_func;
            have_cell_waiting <= '0';
            executing_cell_function <= '1';
            -- Start execution from the start of the description
            cell_exec_ofs <= 0;
          end if;
        end if;
      end if;
    end if;
  end process;
  
end behavioural;
