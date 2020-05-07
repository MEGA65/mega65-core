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

  signal expansionram_current_cache_line_next_toggle : std_logic := '0';
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

  signal slow_prefetched_address : unsigned(26 downto 0);
  signal slow_prefetched_data : unsigned(7 downto 0);
  signal slow_prefetched_request_toggle : std_logic;
  
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

  type mem_job_list_t is array(0 to 199) of mem_transaction_t;

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

    (address => x"8800800", write_p => '0', value => x"00"),
    (address => x"8800801", write_p => '0', value => x"FF"),
    (address => x"8800802", write_p => '0', value => x"FF"),
    (address => x"8800803", write_p => '0', value => x"FF"),
    (address => x"8800804", write_p => '0', value => x"FF"),
    (address => x"8800805", write_p => '0', value => x"FF"),
    (address => x"8800806", write_p => '0', value => x"FF"),
    (address => x"8800807", write_p => '0', value => x"FF"),
    (address => x"8800808", write_p => '0', value => x"48"),
    (address => x"8800809", write_p => '0', value => x"FF"),
    (address => x"880080A", write_p => '0', value => x"FF"),
    (address => x"880080B", write_p => '0', value => x"FF"),
    (address => x"880080C", write_p => '0', value => x"FF"),
    (address => x"880080D", write_p => '0', value => x"FF"),
    (address => x"880080E", write_p => '0', value => x"FF"),
    (address => x"880080F", write_p => '0', value => x"FF"),
    (address => x"8800810", write_p => '0', value => x"10"),
    (address => x"8800811", write_p => '0', value => x"FF"),
    (address => x"8800812", write_p => '0', value => x"FF"),
    (address => x"8800813", write_p => '0', value => x"FF"),
    (address => x"8800814", write_p => '0', value => x"FF"),
    (address => x"8800815", write_p => '0', value => x"FF"),
    (address => x"8800816", write_p => '0', value => x"FF"),
    (address => x"8800817", write_p => '0', value => x"FF"),
    (address => x"8800818", write_p => '0', value => x"18"),
    (address => x"8800819", write_p => '0', value => x"FF"),
    (address => x"880081A", write_p => '0', value => x"FF"),
    (address => x"880081B", write_p => '0', value => x"FF"),
    (address => x"880081C", write_p => '0', value => x"FF"),
    (address => x"880081D", write_p => '0', value => x"FF"),
    (address => x"880081E", write_p => '0', value => x"FF"),
    (address => x"880081F", write_p => '0', value => x"FF"),
    (address => x"8800820", write_p => '0', value => x"20"),
    (address => x"8800821", write_p => '0', value => x"FF"),
    (address => x"8800822", write_p => '0', value => x"FF"),
    (address => x"8800823", write_p => '0', value => x"FF"),
    (address => x"8800824", write_p => '0', value => x"FF"),
    (address => x"8800825", write_p => '0', value => x"FF"),
    (address => x"8800826", write_p => '0', value => x"FF"),
    (address => x"8800827", write_p => '0', value => x"FF"),
    (address => x"8800828", write_p => '0', value => x"28"),
    (address => x"8800829", write_p => '0', value => x"FF"),
    (address => x"880082A", write_p => '0', value => x"FF"),
    (address => x"880082B", write_p => '0', value => x"FF"),
    (address => x"880082C", write_p => '0', value => x"FF"),
    (address => x"880082D", write_p => '0', value => x"FF"),
    (address => x"880082E", write_p => '0', value => x"FF"),
    (address => x"880082F", write_p => '0', value => x"FF"),
    (address => x"8800830", write_p => '0', value => x"30"),
    (address => x"8800831", write_p => '0', value => x"FF"),
    (address => x"8800832", write_p => '0', value => x"FF"),
    (address => x"8800833", write_p => '0', value => x"FF"),
    (address => x"8800834", write_p => '0', value => x"FF"),
    (address => x"8800835", write_p => '0', value => x"FF"),
    (address => x"8800836", write_p => '0', value => x"FF"),
    (address => x"8800837", write_p => '0', value => x"FF"),
    (address => x"8800838", write_p => '0', value => x"38"),
    (address => x"8800839", write_p => '0', value => x"FF"),
    (address => x"880083A", write_p => '0', value => x"FF"),
    (address => x"880083B", write_p => '0', value => x"FF"),
    (address => x"880083C", write_p => '0', value => x"FF"),
    (address => x"880083D", write_p => '0', value => x"FF"),
    (address => x"880083E", write_p => '0', value => x"FF"),
    (address => x"880083F", write_p => '0', value => x"FF"),
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

    -- Write a linear block of 16
    (address => x"8040000", write_p => '1', value => x"e0"),
    (address => x"8040001", write_p => '1', value => x"e1"),
    (address => x"8040002", write_p => '1', value => x"e2"),
    (address => x"8040003", write_p => '1', value => x"e3"),
    (address => x"8040004", write_p => '1', value => x"e4"),
    (address => x"8040005", write_p => '1', value => x"e5"),
    (address => x"8040006", write_p => '1', value => x"e6"),
    (address => x"8040007", write_p => '1', value => x"e7"),
    (address => x"8040008", write_p => '1', value => x"e8"),
    (address => x"8040009", write_p => '1', value => x"e9"),
    (address => x"804000a", write_p => '1', value => x"ea"),
    (address => x"804000b", write_p => '1', value => x"eb"),
    (address => x"804000c", write_p => '1', value => x"ec"),
    (address => x"804000d", write_p => '1', value => x"ed"),
    (address => x"804000e", write_p => '1', value => x"ee"),
    (address => x"804000f", write_p => '1', value => x"ef"),
    
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
    
    -- Write over an 8-byte boundary to try to figure out the
    -- external hyperram bug
    (address => x"8800085", write_p => '1', value => x"85"),
    (address => x"8800086", write_p => '1', value => x"86"),
    (address => x"8800087", write_p => '1', value => x"87"),
    (address => x"8800088", write_p => '1', value => x"88"),
    (address => x"8800089", write_p => '1', value => x"89"),
    (address => x"880008a", write_p => '1', value => x"8a"),
    (address => x"880008b", write_p => '1', value => x"8b"),

    (address => x"8800085", write_p => '0', value => x"85"),
    (address => x"8800086", write_p => '0', value => x"86"),
    (address => x"8800087", write_p => '0', value => x"87"),
    (address => x"8800088", write_p => '0', value => x"88"),
    (address => x"8800089", write_p => '0', value => x"89"),
    (address => x"880008a", write_p => '0', value => x"8a"),
    (address => x"880008b", write_p => '0', value => x"8b"),

    -- Read a linear block of 16
    (address => x"8040000", write_p => '0', value => x"e0"),
    (address => x"8040001", write_p => '0', value => x"e1"),
    (address => x"8040002", write_p => '0', value => x"e2"),
    (address => x"8040003", write_p => '0', value => x"e3"),
    (address => x"8040004", write_p => '0', value => x"e4"),
    (address => x"8040005", write_p => '0', value => x"e5"),
    (address => x"8040006", write_p => '0', value => x"e6"),
    (address => x"8040007", write_p => '0', value => x"e7"),
    (address => x"8040008", write_p => '0', value => x"e8"),
    (address => x"8040009", write_p => '0', value => x"e9"),
    (address => x"804000a", write_p => '0', value => x"ea"),
    (address => x"804000b", write_p => '0', value => x"eb"),
    (address => x"804000c", write_p => '0', value => x"ec"),
    (address => x"804000d", write_p => '0', value => x"ed"),
    (address => x"804000e", write_p => '0', value => x"ee"),
    (address => x"804000f", write_p => '0', value => x"ef"),

    
    others => ( address => x"FFFFFFF", write_p => '0', value => x"00")
    );

  -- Wait initially to allow hyperram to reset and set config register
  signal idle_wait : integer := 1000;
  
  signal expect_value : std_logic := '0';
  signal expected_value : unsigned(7 downto 0) := x"00";

  signal viciv_addr : unsigned(18 downto 3) := (others => '0');
  signal viciv_request_toggle : std_logic := '0';
  signal viciv_data : unsigned(7 downto 0) := x"00";
  signal viciv_data_strobe : std_logic := '0';
  signal pixel_counter : unsigned(31 downto 0) := to_unsigned(0,32);
  
begin

--  reconfig1: entity work.reconfig
--    port map ( clock => clock163,
--               trigger_reconfigure => '0',
--               reconfigure_address => (others => '0'));
  
  hyperram0: entity work.hyperram
    generic map ( in_simulation => true )
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
      expansionram_current_cache_line_next_toggle  => expansionram_current_cache_line_next_toggle,

      viciv_addr => viciv_addr,
      viciv_request_toggle => viciv_request_toggle,
      viciv_data_out => viciv_data,
      viciv_data_strobe => viciv_data_strobe,
      
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
      expansionram_current_cache_line_next_toggle  => expansionram_current_cache_line_next_toggle,
      
      cart_nmi => '1',
      cart_irq => '1',
      cart_dma => '1',
      cart_exrom => '1',
      cart_game => '1',
      cart_d_in => (others => '1'),

      slow_prefetched_request_toggle => slow_prefetched_request_toggle,
      slow_prefetched_data => slow_prefetched_data,
      slow_prefetched_address => slow_prefetched_address,
      
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

  process (pixelclock) is
  begin
    if rising_edge(pixelclock) then
      pixel_counter <= pixel_counter + 1;
      if (pixel_counter(7 downto 0) = x"00") then
        report "VIC: Dispatching pixel data request";
        viciv_request_toggle <= pixel_counter(8);
        viciv_addr <= pixel_counter(23 downto 8);
      end if;
      if viciv_data_strobe='1' then
        report "VIC: Received byte $" & to_hstring(viciv_data);
      end if;
    end if;
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
          report "DISPATCHER: ERROR: Expected $" & to_hstring(expected_value) & ", but saw $" & to_hstring(slow_access_rdata)
            & " after " & integer'image(current_time - dispatch_time) & "ns.";            
        end if;
        dispatch_time <= current_time;
      end if;        
      expect_value <= '0';
      last_slow_access_ready_toggle <= slow_access_ready_toggle;
    end if;

    if expansionram_busy = '0' then

      if idle_wait /= 0 then
        idle_wait <= idle_wait - 1;
      elsif expect_value = '0' and slow_access_ready_toggle = slow_access_request_toggle then

        if mem_jobs(cycles).address = x"FFFFFFF" then
          report "DISPATCHER: Total sequence was " & integer'image(current_time - start_time) & "ns "
            & "(mean " & integer'image(1+(current_time-start_time)/cycles) & "ns ).";
          cycles <= 0;
          start_time <= current_time;          
        else
          cycles <= cycles + 1;        
        end if;


        report "PREFETCH: slow_prefetched_address = $" & to_hstring(slow_prefetched_address);
        if mem_jobs(cycles).address(26 downto 0) = slow_prefetched_address and mem_jobs(cycles).write_p='0' then
          slow_prefetched_request_toggle <= not slow_prefetched_request_toggle;
          report "DISPATCHER: Reading from $" & to_hstring(mem_jobs(cycles).address) & ", expecting to see $"
            & to_hstring(mem_jobs(cycles).value) & " (via slow prefetch)";
          if slow_prefetched_data = mem_jobs(cycles).value then
            report "DISPATCHER: Read correct value $" & to_hstring(slow_prefetched_data)
              & " after " & integer'image(current_time - dispatch_time) & "ns.";
          else
            report "DISPATCHER: ERROR: Expected $" & to_hstring(expected_value) & ", but saw $" & to_hstring(slow_prefetched_data)
              & " after " & integer'image(current_time - dispatch_time) & "ns.";            
          end if;            
          dispatch_time <= current_time;
        else                  
          slow_access_address <= mem_jobs(cycles).address;
          slow_access_write <= mem_jobs(cycles).write_p;
          slow_access_wdata <= mem_jobs(cycles).value;
          slow_access_request_toggle <= not slow_access_request_toggle;
          
          if start_time = 0 then
            start_time <= current_time;
          end if;
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
            dispatch_time <= current_time;
          end if;
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
