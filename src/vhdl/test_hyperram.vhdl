library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_hyperram is
end entity;

architecture foo of test_hyperram is

  signal cpuclock : std_logic := '1';
  signal clock240 : std_logic := '1';

  signal expansionram_read : std_logic := '0';
  signal expansionram_write : std_logic := '0';
  signal expansionram_rdata : unsigned(7 downto 0);
  signal expansionram_wdata : unsigned(7 downto 0) := x"42";
  signal expansionram_address : unsigned(26 downto 0) := "000000100100011010001010111";
  signal expansionram_data_ready_strobe : std_logic;
  signal expansionram_busy : std_logic;

  signal hr_d : unsigned(7 downto 0) := (others => '0');
  signal hr_rwds : std_logic := '0';
  signal hr_reset : std_logic := '1';
  signal hr_clk_n : std_logic := '0';
  signal hr_clk_p : std_logic := '0';
  signal hr_cs0 : std_logic := '0';

  signal cycles : integer := 0;

  signal expecting_byte : std_logic := '0';
  signal expected_byte : unsigned(7 downto 0);
  
begin

  reconfig1: entity work.reconfig
    port map ( clock => clock163,
               trigger_reconfigure => '0',
               reconfigure_address => (others => '0'));
  
  hyperram0: entity work.hyperram
    port map (
      cpuclock => cpuclock,
      clock240 => clock240,
      address => expansionram_address,
      wdata => expansionram_wdata,
      read_request => expansionram_read,
      write_request => expansionram_write,
      rdata => expansionram_rdata,
      data_ready_strobe => expansionram_data_ready_strobe,
      busy => expansionram_busy,
      hr_d => hr_d,
      hr_rwds => hr_rwds,
      hr_reset => hr_reset,
      hr_clk_n => hr_clk_n,
      hr_clk_p => hr_clk_p,
      hr_cs0 => hr_cs0
      );

  fakehyper0: entity work.fakehyperram
    port map (
      hr_d => hr_d,
      hr_rwds => hr_rwds,
      hr_reset => hr_reset,
      hr_clk_n => hr_clk_n,
      hr_clk_p => hr_clk_p,
      hr_cs0 => hr_cs0
      );
    
  
  process(hr_cs0, hr_clk_p, hr_reset, hr_rwds, hr_d) is
  begin
    report
      "hr_cs0 = " & std_logic'image(hr_cs0) & ", " &
      "hr_clk_p = " & std_logic'image(hr_clk_p) & ", " &
      "hr_reset = " & std_logic'image(hr_reset) & ", " &
      "hr_rwds = " & std_logic'image(hr_rwds) & ", " &
      "hr_d = " & to_hstring(hr_d) & ", " &
      ".";
  end process;
  
  
  -- 240MHz fast clock and 40MHz cpu clock
  process is
  begin

    report "expansionram_data_ready_strobe=" & std_logic'image(expansionram_data_ready_strobe) 
      & ", expansionram_busy=" & std_logic'image(expansionram_busy);

    if expansionram_busy = '0' then
      cycles <= cycles + 1;
      case cycles is
        when 1 =>
          report "DISPATCH: Write to $123456";
          expansionram_write <= '1';
          expansionram_read <= '0';
          expansionram_wdata <= x"42";
          expansionram_address(23 downto 0) <= x"123456";          
        when 10 =>
          report "DISPATCH: Read from $123456";
          expansionram_write <= '0';
          expansionram_read <= '1';
          expansionram_address(23 downto 0) <= x"123456";
          expected_byte <= x"42";
          expecting_byte <= '1';
        when others =>
      end case;
    else
      expansionram_read <= '0';
      expansionram_write <= '0';
    end if;

    if expansionram_data_ready_strobe = '1' and expecting_byte='1' then
      report "Expected byte $" & to_hstring(expected_byte) & ", and received $" & to_hstring(expansionram_rdata);
      expecting_byte <= '0';
    end if;
    
    cpuclock <= '0';
    clock240 <= '0';
    wait for 2 ns;
    clock240 <= '1';
    wait for 2 ns;
    clock240 <= '0';
    wait for 2 ns;
    clock240 <= '1';
    wait for 2 ns;
    clock240 <= '0';
    wait for 2 ns;
    clock240 <= '1';
    wait for 2 ns;

    cpuclock <= '1';
    clock240 <= '0';
    wait for 2 ns;
    clock240 <= '1';
    wait for 2 ns;
    clock240 <= '0';
    wait for 2 ns;
    clock240 <= '1';
    wait for 2 ns;
    clock240 <= '0';
    wait for 2 ns;
    clock240 <= '1';
    wait for 2 ns;

--    report "40MHz CPU clock cycle finished";
    
  end process;


end foo;
