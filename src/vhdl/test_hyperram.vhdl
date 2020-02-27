library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;
use work.cputypes.all;

entity test_hyperram is
end entity;

architecture foo of test_hyperram is

  signal cpuclock : std_logic := '1';
  signal pixelclock : std_logic := '1';
  signal clock163 : std_logic := '1';

  signal expansionram_read : std_logic;
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

  signal slow_access_request_toggle : std_logic := '0';
  signal slow_access_ready_toggle : std_logic;
  signal last_slow_access_ready_toggle : std_logic;
  signal slow_access_write : std_logic := '0';
  signal slow_access_address : unsigned(27 downto 0);
  signal slow_access_wdata : unsigned(7 downto 0);
  signal slow_access_rdata : unsigned(7 downto 0);
  
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
      pixelclock => pixelclock,
      clock163 => clock163,
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
    

  slow_devices0: entity work.slow_devices
    generic map (
      target => mega65r2
      )
    port map (
      cpuclock => cpuclock,
      pixelclock => pixelclock,
      reset => '1',
--      cpu_exrom => '1',
--      cpu_game => '1',
      sector_buffer_mapped => '1',

--      irq_out => irq_out,
--      nmi_out => nmi_out,
      
--      joya => joy3,
--      joyb => joy4,

--      p1lo => p1lo,
--      p1hi => p1hi,
--      p2lo => p2lo,
--      p2hi => p2hi,
      
--      cart_busy => led,
--      cart_access_count => cart_access_count,

      expansionram_data_ready_strobe => expansionram_data_ready_strobe,
      expansionram_busy => expansionram_busy,
      expansionram_read => expansionram_read,
      expansionram_write => expansionram_write,
      expansionram_address => expansionram_address,
      expansionram_rdata => expansionram_rdata,
      expansionram_wdata => expansionram_wdata,
      cart_nmi => '1',
      cart_irq => '1',
      cart_dma => '1',
      cart_exrom => '1',
      cart_game => '1',
      cart_d_in => (others => '1'),
      
      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle => slow_access_ready_toggle,
      slow_access_write => slow_access_write,
      slow_access_address => slow_access_address,
      slow_access_wdata => slow_access_wdata,
      slow_access_rdata => slow_access_rdata

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
  
  
  process is
  begin

    report "expansionram_data_ready_strobe=" & std_logic'image(expansionram_data_ready_strobe) 
      & ", expansionram_busy=" & std_logic'image(expansionram_busy)
      & ", expansionram_read=" & std_logic'image(expansionram_read);

    if slow_access_ready_toggle /= last_slow_access_ready_toggle then
      report "Read slow device byte $" & to_hstring(slow_access_rdata);
      last_slow_access_ready_toggle <= slow_access_ready_toggle;
    end if;
    
    cycles <= cycles + 1;
    case cycles is
      when 1 =>
        report "DISPATCH: Read from $8000000";
        slow_access_request_toggle <= not slow_access_request_toggle;
        slow_access_write <= '0';
        slow_access_address <= x"8000000";
      when 10 =>
      when others =>
        null;
    end case;

    pixelclock <= '0';
    cpuclock <= '0';
    clock163 <= '0';
    wait for 2 ns;
    clock163 <= '1';
    wait for 2 ns;
    pixelclock <= '1';
    clock163 <= '0';
    wait for 2 ns;
    clock163 <= '1';
    wait for 2 ns;

    pixelclock <= '0';
    cpuclock <= '1';
    clock163 <= '0';
    wait for 2 ns;
    clock163 <= '1';
    wait for 2 ns;
    pixelclock <= '0';
    clock163 <= '0';
    wait for 2 ns;
    clock163 <= '1';
    wait for 2 ns;

--    report "40MHz CPU clock cycle finished";
    
  end process;


end foo;
