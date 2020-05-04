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
  signal clock325 : std_logic := '1';

  signal expansionram_read : std_logic;
  signal expansionram_write : std_logic := '0';
  signal expansionram_rdata : unsigned(7 downto 0);
  signal expansionram_wdata : unsigned(7 downto 0) := x"42";
  signal expansionram_address : unsigned(26 downto 0) := "000000100100011010001010111";
  signal expansionram_data_ready_strobe : std_logic;
  signal expansionram_busy : std_logic;
  signal current_cache_line : cache_row_t := (others => (others => '0'));
  signal current_cache_line_address : unsigned(26 downto 3) := (others => '0');
  signal current_cache_line_valid : std_logic := '0';


  signal hr_d : unsigned(7 downto 0) := (others => '0');
  signal hr_rwds : std_logic := '0';
  signal hr_reset : std_logic := '1';
  signal hr_clk_n : std_logic := '0';
  signal hr_clk_p : std_logic := '0';
  signal hr_cs0 : std_logic := '0';

  signal hr2_d : unsigned(7 downto 0) := (others => '0');
  signal hr2_rwds : std_logic := '0';
  signal hr2_reset : std_logic := '1';
  signal hr2_clk_n : std_logic := '0';
  signal hr2_clk_p : std_logic := '0';
  signal hr2_cs0 : std_logic := '0';
  
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

  type mem_transaction_t is record
    address : unsigned(27 downto 0);
    write_p : std_logic;
    value : unsigned(7 downto 0);     -- either to write, or expected to read
  end record mem_transaction_t;

  type mem_job_list_t is array(0 to 99) of mem_transaction_t;

  signal start_time : integer := 0;
  signal current_time : integer := 0;
  signal dispatch_time : integer := 0;
  
  signal mem_jobs : mem_job_list_t := (
    (address => x"8801001", write_p => '1', value => x"91"),
    (address => x"8801001", write_p => '0', value => x"91"),
    (address => x"8800800", write_p => '1', value => x"00"),
    (address => x"8800808", write_p => '1', value => x"08"),
    (address => x"8800810", write_p => '1', value => x"10"),
    (address => x"8800818", write_p => '1', value => x"18"),
    (address => x"8800820", write_p => '1', value => x"20"),
    (address => x"8800828", write_p => '1', value => x"28"),
    (address => x"8800830", write_p => '1', value => x"30"),
    (address => x"8800838", write_p => '1', value => x"38"),
    (address => x"8800840", write_p => '1', value => x"40"),
    (address => x"8800808", write_p => '1', value => x"48"),
    (address => x"8800800", write_p => '0', value => x"00"),
    (address => x"8800800", write_p => '1', value => x"40"),
    (address => x"8800808", write_p => '0', value => x"48"),
    (address => x"8800810", write_p => '0', value => x"10"),
    (address => x"8800818", write_p => '0', value => x"18"),
    (address => x"8800820", write_p => '0', value => x"20"),
    (address => x"8800828", write_p => '0', value => x"28"),
    (address => x"8800830", write_p => '0', value => x"30"),
    (address => x"8800838", write_p => '0', value => x"38"),
    (address => x"8800840", write_p => '0', value => x"40"),


    -- Write 16 bytes, first the evens and then the odds
    (address => x"8000000", write_p => '1', value => x"30"),
    (address => x"8000002", write_p => '1', value => x"32"),
    (address => x"8000004", write_p => '1', value => x"34"),
    (address => x"8000006", write_p => '1', value => x"36"),
    (address => x"8000008", write_p => '1', value => x"38"),
    (address => x"800000a", write_p => '1', value => x"3a"),
    (address => x"800000c", write_p => '1', value => x"3c"),
    (address => x"800000e", write_p => '1', value => x"3e"),
    (address => x"8000001", write_p => '1', value => x"31"),
    (address => x"8000003", write_p => '1', value => x"33"),
    (address => x"8000005", write_p => '1', value => x"35"),
    (address => x"8000007", write_p => '1', value => x"37"),
    (address => x"8000009", write_p => '1', value => x"39"),
    (address => x"800000b", write_p => '1', value => x"3b"),
    (address => x"800000d", write_p => '1', value => x"3d"),
    (address => x"800000f", write_p => '1', value => x"3f"),

    -- Now a few random writes to stress the write buffers
    (address => x"8001009", write_p => '1', value => x"49"),
    (address => x"800200b", write_p => '1', value => x"4b"),
    (address => x"800300d", write_p => '1', value => x"4d"),
    (address => x"800400f", write_p => '1', value => x"4f"),

    -- ... and read them back
    (address => x"8001009", write_p => '0', value => x"49"),
    (address => x"800200b", write_p => '0', value => x"4b"),
    (address => x"800300d", write_p => '0', value => x"4d"),
    (address => x"800400f", write_p => '0', value => x"4f"),
    
    -- Read the first 16 bytes back
    (address => x"8000000", write_p => '0', value => x"30"),
    (address => x"8000001", write_p => '0', value => x"31"),
    (address => x"8000002", write_p => '0', value => x"32"),
    (address => x"8000003", write_p => '0', value => x"33"),
    (address => x"8000004", write_p => '0', value => x"34"),
    (address => x"8000005", write_p => '0', value => x"35"),
    (address => x"8000006", write_p => '0', value => x"36"),
    (address => x"8000007", write_p => '0', value => x"37"),
    (address => x"8000008", write_p => '0', value => x"38"),
    (address => x"8000009", write_p => '0', value => x"39"),
    (address => x"800000a", write_p => '0', value => x"3a"),
    (address => x"800000b", write_p => '0', value => x"3b"),
    (address => x"800000c", write_p => '0', value => x"3c"),
    (address => x"800000d", write_p => '0', value => x"3d"),
    (address => x"800000e", write_p => '0', value => x"3e"),
    (address => x"800000f", write_p => '0', value => x"3f"),


    
    -- Read the first 16 bytes back
    (address => x"8000000", write_p => '0', value => x"30"),
    (address => x"8000001", write_p => '0', value => x"31"),
    (address => x"8000002", write_p => '0', value => x"32"),
    (address => x"8000003", write_p => '0', value => x"33"),
    (address => x"8000004", write_p => '0', value => x"34"),
    (address => x"8000005", write_p => '0', value => x"35"),
    (address => x"8000006", write_p => '0', value => x"36"),
    (address => x"8000007", write_p => '0', value => x"37"),
    (address => x"8000008", write_p => '0', value => x"38"),
    (address => x"8000009", write_p => '0', value => x"39"),
    (address => x"800000a", write_p => '0', value => x"3a"),
    (address => x"800000b", write_p => '0', value => x"3b"),
    (address => x"800000c", write_p => '0', value => x"3c"),
    (address => x"800000d", write_p => '0', value => x"3d"),
    (address => x"800000e", write_p => '0', value => x"3e"),
    (address => x"800000f", write_p => '0', value => x"3f"),

    others => ( address => x"FFFFFFF", write_p => '0', value => x"00")
    );

  -- Wait initially to allow hyperram to reset and set config register
  signal idle_wait : integer := 1000;
  
  signal expect_value : std_logic := '0';
  signal expected_value : unsigned(7 downto 0) := x"00";
  
begin

--  reconfig1: entity work.reconfig
--    port map ( clock => clock163,
--               trigger_reconfigure => '0',
--               reconfigure_address => (others => '0'));
  
  hyperram0: entity work.hyperram
    port map (
      pixelclock => pixelclock,
      clock163 => clock163,
      clock325 => clock325,
      address => expansionram_address,
      wdata => expansionram_wdata,
      read_request => expansionram_read,
      write_request => expansionram_write,
      rdata => expansionram_rdata,
      data_ready_strobe => expansionram_data_ready_strobe,
      busy => expansionram_busy,

      current_cache_line => current_cache_line,
      current_cache_line_address => current_cache_line_address,
      current_cache_line_valid => current_cache_line_valid,
      
      hr_d => hr_d,
      hr_rwds => hr_rwds,
      hr_reset => hr_reset,
      hr_clk_n => hr_clk_n,
      hr_clk_p => hr_clk_p,
      hr_cs0 => hr_cs0,

      hr2_d => hr2_d,
      hr2_rwds => hr2_rwds,
      hr2_reset => hr2_reset,
      hr2_clk_n => hr2_clk_n,
      hr2_clk_p => hr2_clk_p,
      hr_cs1 => hr2_cs0
      
      );

  fakehyper0: entity work.s27kl0641
    generic map (
      id => "$8000000",
      tdevice_vcs => 5 ns,
      timingmodel => "S27KL0641DABHI000"
      )
    port map (
      DQ7 => hr_d(7),
      DQ6 => hr_d(6),
      DQ5 => hr_d(5),
      DQ4 => hr_d(4),
      DQ3 => hr_d(3),
      DQ2 => hr_d(2),
      DQ1 => hr_d(1),
      DQ0 => hr_d(0),

      CSNeg => hr_cs0,
      CK => hr_clk_p,
      RESETneg => hr_reset,
      RWDS => hr_rwds
      );
    

  fakehyper1: entity work.s27kl0641
    generic map (
      id => "$8800000",
      tdevice_vcs => 5 ns,
      timingmodel => "S27KL0641DABHI000"
      )
    port map (
      DQ7 => hr2_d(7),
      DQ6 => hr2_d(6),
      DQ5 => hr2_d(5),
      DQ4 => hr2_d(4),
      DQ3 => hr2_d(3),
      DQ2 => hr2_d(2),
      DQ1 => hr2_d(1),
      DQ0 => hr2_d(0),

      CSNeg => hr2_cs0,
      CK => hr2_clk_p,
      RESETneg => hr2_reset,
      RWDS => hr2_rwds
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

      expansionram_current_cache_line => current_cache_line,
      expansionram_current_cache_line_address => current_cache_line_address,
      expansionram_current_cache_line_valid => current_cache_line_valid,
      
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
  

  
  process(hr_cs0, hr_clk_p, hr_reset, hr_rwds, hr_d,
          hr2_cs0, hr2_clk_p, hr2_reset, hr2_rwds, hr2_d
          ) is
  begin
    report
      "hr_cs0 = " & std_logic'image(hr_cs0) & ", " &
      "hr_clk_p = " & std_logic'image(hr_clk_p) & ", " &
      "hr_reset = " & std_logic'image(hr_reset) & ", " &
      "hr_rwds = " & std_logic'image(hr_rwds) & ", " &
      "hr_d = " & std_logic'image(hr_d(0))
      & std_logic'image(hr_d(1))
      & std_logic'image(hr_d(2))
      & std_logic'image(hr_d(3))
      & std_logic'image(hr_d(4))
      & std_logic'image(hr_d(5))
      & std_logic'image(hr_d(6))
      & std_logic'image(hr_d(7))
      & ".";
    report
      "hr2_cs0 = " & std_logic'image(hr2_cs0) & ", " &
      "hr2_clk_p = " & std_logic'image(hr2_clk_p) & ", " &
      "hr2_reset = " & std_logic'image(hr2_reset) & ", " &
      "hr2_rwds = " & std_logic'image(hr2_rwds) & ", " &
      "hr2_d = " & std_logic'image(hr2_d(0))
      & std_logic'image(hr2_d(1))
      & std_logic'image(hr2_d(2))
      & std_logic'image(hr2_d(3))
      & std_logic'image(hr2_d(4))
      & std_logic'image(hr2_d(5))
      & std_logic'image(hr2_d(6))
      & std_logic'image(hr2_d(7))
      & ".";
  end process;
  
  
  process (clock325) is
  begin
    if rising_edge(clock325) then
      current_time <= current_time + 3;
    end if;
  end process;
  
  process is
  begin

    report "expansionram_data_ready_strobe=" & std_logic'image(expansionram_data_ready_strobe) 
      & ", expansionram_busy=" & std_logic'image(expansionram_busy)
      & ", expansionram_read=" & std_logic'image(expansionram_read);

    
    if slow_access_ready_toggle /= last_slow_access_ready_toggle then
      if expect_value = '1' then
        if expected_value = slow_access_rdata then
          report "DISPATCHER: Read correct value $" & to_hstring(slow_access_rdata)
            & " after " & integer'image(current_time - dispatch_time) & "ns.";
        else
          report "DISPATCHER: ERROR: Expected $" & to_hstring(expected_value) & ", but saw $" & to_hstring(slow_access_rdata);
        end if;
      end if;
      expect_value <= '0';
      last_slow_access_ready_toggle <= slow_access_ready_toggle;
    end if;

    if expansionram_busy = '0' then

      if idle_wait /= 0 then
        idle_wait <= idle_wait - 1;
      elsif expect_value = '0' and slow_access_ready_toggle = slow_access_request_toggle then

        if mem_jobs(cycles).address = x"FFFFFFF" then
          report "Total sequence was " & integer'image(current_time - start_time) & "ns.";
          cycles <= 0;
          start_time <= current_time;
        else
          cycles <= cycles + 1;        
        end if;
      
        slow_access_address <= mem_jobs(cycles).address;
        slow_access_write <= mem_jobs(cycles).write_p;
        slow_access_wdata <= mem_jobs(cycles).value;
        slow_access_request_toggle <= not slow_access_request_toggle;

        if start_time = 0 then
          start_time <= current_time;
        end if;
        dispatch_time <= current_time;
        if (mem_jobs(cycles).write_p='0') then
          -- Let reads finish serially
          -- (In the worst case, this can take quite a while)
          idle_wait <= 0;
          report "DISPATCHER: Reading from $" & to_hstring(mem_jobs(cycles).address) & ", expecting to see $"
            & to_hstring(mem_jobs(cycles).value);
          expect_value <= '1';
          expected_value <= mem_jobs(cycles).value;
        else
          -- Try to rush writes, so that writes get merged
          idle_wait <= 0;
          report "DISPATCHER: Writing to $" & to_hstring(mem_jobs(cycles).address) & " <- $"
            & to_hstring(mem_jobs(cycles).value);
          expect_value <= '0';
        end if;
      end if;
    end if;
    
    clock325 <= '0';
    pixelclock <= '0';
    cpuclock <= '0';
    clock163 <= '0';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;
    
    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    pixelclock <= '1';
    clock163 <= '0';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    pixelclock <= '0';
    cpuclock <= '1';
    clock163 <= '0';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    pixelclock <= '1';
    clock163 <= '0';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

--    report "40MHz CPU clock cycle finished";
    
  end process;


end foo;
