library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity fakehyperram is
  Port ( 
         hr_d : inout unsigned(7 downto 0) := (others => 'Z'); -- Data/Address
         hr_rwds : inout std_logic := 'Z'; -- RW Data strobe
         hr_reset : in std_logic := '1'; -- Active low RESET line to HyperRAM
         hr_clk_n : in std_logic := '0';
         hr_clk_p : in std_logic := '1';
         hr_cs0 : in std_logic := '1';
         hr_cs1 : in std_logic := '1'
         );
end fakehyperram;

architecture gothic of fakehyperram is

  signal command : std_logic_vector(47 downto 0);
  signal command_clocks_remaining : integer := 0;
  signal last_cs0 : std_logic := '1';
  signal read_write : std_logic := '1';
  
begin

  process (hr_clk_p,hr_clk_n,hr_cs0) is
  begin
    if rising_edge(hr_clk_p) or falling_edge(hr_clk_p) or falling_edge(hr_cs0) then
      report "hr_clk_p = " & std_logic'image(hr_clk_p);

      last_cs0 <= hr_cs0;
      -- New transactions MUST start with CLK low according to the datasheet.
      if hr_cs0 = '0' and last_cs0 = '1' and hr_clk_p='0' then
        report "Starting new transaction";

        -- Memory asserts or clears RWDS during CA transfer.
        -- We will indicate latency x1 for now
        hr_rwds <= '0';

        report "Received CA byte $" & to_hstring(hr_d);
        
        command(7 downto 0) <= std_logic_vector(hr_d);
        command_clocks_remaining <= 6;
      elsif command_clocks_remaining > 1 then
        report "Received CA byte $" & to_hstring(hr_d);
        
        command(7 downto 0) <= std_logic_vector(hr_d);
        command(47 downto 8) <= command(39 downto 0);
        command_clocks_remaining <= command_clocks_remaining - 1;
      elsif command_clocks_remaining = 1 then
        -- Finished CA clock in
        report "CA is $" & to_hstring(command);
        if command(47)='1' then
          report "  job is READ";
        else
          report "  job is WRITE";
        end if;
        if command(46)='1' then
          report "  job is REGISTER";
        else
          report "  job is MEMORY";
        end if;
        if command(45)='1' then
          report "  job is LINEAR BURST";
        else
          report "  job is WRAPPED BURST";
        end if;
        report "  address is $" & to_hstring(command(44 downto 16)&command(2 downto 0));
        command_clocks_remaining <= 0;
      end if;
                  
    end if;
  end process;
end gothic;
