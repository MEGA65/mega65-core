use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity reconfig is
  port (
    clock : in std_logic;
    trigger_reconfigure : in std_logic
    );
end reconfig;

architecture behavioural of reconfig is

  signal icape_out : unsigned(31 downto 0);
  signal icape_in : unsigned(31 downto 0);
  signal cs : std_logic := '0'; -- interface active when high
  signal rw : std_logic := '1'; -- Read or _Write

  type reg_value_pair is ARRAY(0 TO 7) OF unsigned(31 DOWNTO 0);    
  
  signal bitstream_values : reg_value_pair := (
    x"FFFFFFFF", -- Dummy word
    x"AA995566", -- Sync word 
    x"20000000", -- Type 1 NOOP
    x"30020001", -- Type 1 write to WBSTAR
    x"00000000", -- Warm-boot start address
    x"30008001", -- Type 1 write words to CMD
    x"0000000F", -- IPROG word
    x"20000000" -- Type 1 NOOP
    );

  signal counter : integer range 0 to 99 := 99;
  
begin

  icape: entity work.icape2
    generic map (
      )
    port map (
      O => icape_out,
      CLK => clock,
      CSIB => cs,
      I => icape_in,
      rdwrb => rw
      );
  
  process (clock) is
  begin

    if rising_edge(clock) then
      if counter < 8 then
        cs <= '1';
        rw <= '1';
        counter <= counter + 1;
        icape_in <= std_logic_vector(bitstream_values);
      else
        cs <= '0';
        if trigger_reconfigure = '1' then
          counter <= 0;
        end if;
      end if;
            
    end if;
  end process;

end behavioural;
