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
    clock163 : in std_logic;
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
  signal latency_clocks_remaining : integer := 0;
  signal in_transfer : std_logic := '0';
  signal last_cs0 : std_logic := '1';
  signal read_write : std_logic := '1';

  signal ram_address : unsigned(23 downto 0);
  type ram_t is array (0 to 7) of unsigned(7 downto 0);
  shared variable ram : ram_t := (
    others => x"BD"
    );

  signal last_hr_clk_p : std_logic := '0';
  signal last_hr_cs0 : std_logic := '0';
  
begin

  process (hr_clk_p,hr_clk_n,hr_cs0) is
  begin
    if rising_edge(clock163) then
    if hr_clk_p /= last_hr_clk_p or hr_cs0 /= last_hr_cs0 then
      last_hr_clk_p <= hr_clk_p;
      last_hr_cs0 <= hr_cs0;
      report "hr_clk_p = " & std_logic'image(hr_clk_p);

      last_cs0 <= hr_cs0;
      if hr_cs0 = '1' and in_transfer='0' then
        hr_d <= (others => 'Z');
      end if;
      
      -- New transactions MUST start with CLK low according to the datasheet.
      if hr_cs0 = '0' and last_cs0 = '1' and hr_clk_p='0' then
        report "Starting new transaction";

        -- Memory asserts or clears RWDS during CA transfer.
        -- We will indicate latency x1 for now
        hr_rwds <= '0';

        report "Received first CA byte %" & to_string(std_logic_vector(hr_d));
        
        command(7 downto 0) <= std_logic_vector(hr_d);
        command_clocks_remaining <= 6;
      elsif command_clocks_remaining > 1 then
        report "Received subsequent CA byte %" & to_string(std_logic_vector(hr_d));
        
        command(7 downto 0) <= std_logic_vector(hr_d);
        command(47 downto 8) <= command(39 downto 0);
        command_clocks_remaining <= command_clocks_remaining - 1;
      elsif command_clocks_remaining = 1 then
        -- Finished CA clock in
        hr_rwds <= 'Z';
        report "CA is $" & to_hstring(command);
        if command(47)='1' then
          report "  job is READ";
        else
          report "  job is WRITE";
        end if;
        read_write <= command(47);
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
        report "  word address is $" & to_hstring(command(44 downto 16)&command(2 downto 0)&"0");
        ram_address(23 downto 4) <= unsigned(command(35 downto 16));
        ram_address(3 downto 1) <= unsigned(command(2 downto 0));
        ram_address(0) <= '0';
        command_clocks_remaining <= 0;
        -- 8 clocks minus the two clocks for the last two bytes of CA, that
        -- don't contain ROW/COL lookup info = 6
        -- Then take one off, so that we are actually acting when first data comes
        latency_clocks_remaining <= 6 - 1;
      elsif latency_clocks_remaining /= 0 then
        latency_clocks_remaining <= latency_clocks_remaining - 1;
        report "Waiting for initial latency to expire: " & integer'image(latency_clocks_remaining);
        if latency_clocks_remaining = 1 then
          in_transfer <= '1';
        end if;
      else
        if in_transfer='1' then
          if read_write = '1' then
            report "Fake Hyperram Reading $" & to_hstring(ram(to_integer(ram_address(2 downto 0)))) & " from @ $" & to_hstring(ram_address);
            hr_d <= ram(to_integer(ram_address(2 downto 0)));
            if ram_address(0) = '0' then
              hr_rwds <= '1';
            else
              hr_rwds <= '0';
            end if;
          else
            if hr_rwds='0' then
              report "Writing data: value=$" & to_hstring(hr_d) & " @ $" & to_hstring(ram_address);
              ram(to_integer(ram_address(2 downto 0))) := hr_d;
            else
              report "Masking write: value=$" & to_hstring(hr_d) & " @ $" & to_hstring(ram_address);
            end if;
          end if;
          ram_address <= ram_address + 1;
        end if;
      end if; 
      -- Cancel transaction when CS goes high
      if hr_cs0 = '1' then
        in_transfer <= '0';
      end if;
      
    end if;
    end if;
  end process;
end gothic;
