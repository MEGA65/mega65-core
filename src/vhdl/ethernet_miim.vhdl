-- Bit TX is load data with clock low, then set clock high

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity ethernet_miim is
  port (
    clock : in std_logic;

    -- Ethernet MIIM lines
    eth_mdio : inout std_logic;
    eth_mdc : out std_logic := '1';

    -- Access interface
    miim_request : in std_logic;
    miim_write : in std_logic;
    miim_phyid : in unsigned(4 downto 0);
    miim_register : in unsigned(4 downto 0);
    miim_read_value : out unsigned(15 downto 0);
    miim_write_value : in unsigned(15 downto 0);
    miim_ready : out std_logic
    );
end ethernet_miim;

architecture foo of ethernet_miim is

  signal busy : std_logic := '0';
  signal bit_number : integer range 0 to 68 := 0;
  signal miim_command : unsigned(68 downto 0) := (others => '1');

  signal read_value : unsigned(15 downto 0) := x"0000";

  signal miim_phase : integer range 0 to 100 := 0;
  signal miim_clock : std_logic := '0';

  signal last_miim_request : std_logic := '0';
  signal last_miim_clock : std_logic := '0';
  
begin
  process (clock) is
  begin
    if rising_edge(clock) then
      -- Update external interface
      if busy='0' then
--        report "exporting read_value";
        miim_read_value <= read_value;
        miim_ready <= '1';
      else
        miim_ready <= '0';
      end if;
      eth_mdc <= miim_clock;
      
      -- Update MIIM clock. This should be no faster than 2.5MHz
      -- so 25 cycles per tick, so invert every 13 cycles @ 50MHz
      if miim_phase = 100 then  -- about 0.5MHz
--        report "miim half tick";
        miim_clock <= not miim_clock;
        miim_phase <= 0;
      else
        miim_phase <= miim_phase + 1;
      end if;
      
      last_miim_request <= miim_request;
      last_miim_clock <= miim_clock;
      if miim_request='1' and last_miim_request='0' then
        report "Starting MIIM transaction";
        -- Generate MIIM command
        miim_command(68 downto 32) <= (others => '1'); -- preamble
        miim_command(31 downto 30) <= "01"; -- start of frame
        -- Read or rwrite
        miim_command(29) <= '1' xor miim_write;
        miim_command(28) <= '0' xor miim_write;
        -- PHY ID
        miim_command(27 downto 23) <= miim_phyid;
        -- Register
        miim_command(22 downto 18) <= miim_register;
        -- Turn around for listen / ready for write
        miim_command(17 downto 16) <= "11";
        -- Register value to write, if writing
        miim_command(15 downto 0) <= miim_write_value;

        busy <= '1';
        bit_number <= 68;
      end if;
      if busy='1' then
        if miim_clock='0' and last_miim_clock='1' then
          -- Falling clock edge on MIIM interface, so
          -- put bit on there
          if (bit_number > 15) or (miim_write='1') then
            eth_mdio <= miim_command(68);
          else
            eth_mdio <= 'Z';
          end if;
        elsif miim_clock='1' and last_miim_clock='0' then
          report "miim 2.5MHz clock tick";
          -- Rising MIIM clock, so capture read bit if
          -- necessary
          if bit_number < 16 then
            read_value(15 downto 1) <= read_value(14 downto 0);
            read_value(0) <= eth_mdio;
          end if;
          if bit_number /= 0 then
            bit_number <= bit_number - 1;
          else
            busy <= '0';
            eth_mdio <= '1';
            report "end of MIIM transaction";
          end if;
          miim_command(68 downto 1) <= miim_command(67 downto 0);
        end if;
      end if;
    end if;
  end process;
end foo;
