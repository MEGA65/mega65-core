library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity vFPGA_clock_controller_pausable is
  port (clk               : in  std_ulogic;
        rst               : in  std_ulogic;
        pause             : in  std_ulogic;
        clk_div           : in  std_ulogic_vector(9 downto 0);  -- How much to divide the physical clock to get the virtual clock (the actual value will be one more than the one written)
        clk_cont_in       : in  std_ulogic_vector(23 downto 0); -- How many virtual clock cycles you want, 0 -> stoped, 111..1 -> never stop
        clk_cont_in_valid : in  std_ulogic;
        continue_clk_app  : in  std_ulogic;
        clk_cont_out      : out std_ulogic_vector(23 downto 0); -- The remaining clock cycles
        done              : out std_ulogic;                     -- Is set to one when the virtual clock is stoped (clk_count_out == 0)
        clk_app           : out std_ulogic);                    -- The virtual clock, active for one physical clock cycle
end vFPGA_clock_controller_pausable;


architecture Behavioral of vFPGA_clock_controller_pausable is

  signal clk_div_counter   : std_ulogic_vector(9 downto 0) := (others => '0');
  signal clk_cycle_counter : std_ulogic_vector(23 downto 0) := (others => '0');
  signal clk_div_counter_down : std_ulogic_vector(9 downto 0) := (others => '0');

begin

  -- Virtual clock is active during only one physical clock cycle --
  process (clk)
  begin
    if rising_edge(clk) then
      if clk_div_counter = "0000000000" then
        clk_app <= '1';
      else
        clk_app <= '0';
      end if;
    end if;
  end process;


  -- Divisor counter --
  clk_div_counter_down <= std_ulogic_vector(unsigned(clk_div_counter) - 1);
  process (clk)
  begin
    if rising_edge(clk) then
      if pause='0' then
        if continue_clk_app = '1' then
          if clk_div_counter = "0000000000" then
            clk_div_counter <= clk_div;
          else
            clk_div_counter <= clk_div_counter_down;
          end if;
        elsif clk_cycle_counter = x"000000" or rst = '1' or clk_div_counter = "0000000000" or clk_cont_in_valid = '1' then
          clk_div_counter <= clk_div;
        else
          clk_div_counter <= clk_div_counter_down;
        end if;
      end if;
    end if;
  end process;


  -- Cycle counter --
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        clk_cycle_counter <= x"000000";
      elsif clk_cont_in_valid = '1' then
        clk_cycle_counter <= clk_cont_in;
      elsif clk_div_counter = "0000000000" and clk_cycle_counter /= x"000000" and clk_cycle_counter /= x"ffffff" then
        clk_cycle_counter <= std_ulogic_vector(unsigned(clk_cycle_counter) - 1);
      end if;
    end if;
  end process;
  
  clk_cont_out <= clk_cycle_counter;


  -- done --
  process(clk)
  begin
    if rising_edge(clk) then
      if clk_cycle_counter = x"000000" then
        done <= '1';
      else
        done <= '0';
      end if;
    end if;
  end process;

end Behavioral;
