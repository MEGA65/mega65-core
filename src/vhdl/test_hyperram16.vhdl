library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;
use work.cputypes.all;

entity test_hyperram16 is
end entity;

architecture foo of test_hyperram16 is

  signal cpuclock : std_logic := '1';
  signal pixelclock : std_logic := '1';
  signal clock163 : std_logic := '1';
  signal clock325 : std_logic := '1';

  signal expansionram_current_cache_line_next_toggle : std_logic := '0';
  signal expansionram_read : std_logic;
  signal expansionram_write : std_logic := '0';
  signal expansionram_rdata : unsigned(15 downto 0);
  signal expansionram_wdata : unsigned(15 downto 0) := x"4242";
  signal expansionram_address : unsigned(26 downto 0) := "000000100100011010001010111";
  signal expansionram_data_ready_strobe : std_logic;
  signal expansionram_busy : std_logic;
  signal current_cache_line : cache_row_t := (others => (others => '0'));
  signal current_cache_line_address : unsigned(26 downto 3) := (others => '0');
  signal current_cache_line_valid : std_logic := '0';

  signal cycles : integer := 0;  
  
  signal slow_prefetched_address : unsigned(26 downto 0);
  signal slow_prefetched_data : unsigned(7 downto 0);
  signal slow_prefetched_request_toggle : std_logic := '0';
  
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
  
  type mem_transaction_t is record
    address : unsigned(27 downto 0);
    write_p : std_logic;
    value : unsigned(15 downto 0);     -- either to write, or expected to read
  end record mem_transaction_t;

  type mem_job_list_t is array(0 to 2047) of mem_transaction_t;

  signal start_time : integer := 0;
  signal current_time : integer := 0;
  signal dispatch_time : integer := 0;
  
  signal mem_jobs : mem_job_list_t := (
    -- Simple write and then read immediately
    (address => x"8801000", write_p => '1', value => x"1984"),
    (address => x"8801000", write_p => '0', value => x"1984"),

    -- Try to reproduce the read-strobe bug
    (address => x"8801000", write_p => '1', value => x"1984"),
    
    others => ( address => x"FFFFFFF", write_p => '0', value => x"0000")
    );

  -- Wait initially to allow hyperram to reset and set config register
  signal idle_wait : std_logic := '0';
  
  signal expect_value : std_logic := '0';
  signal expected_value : unsigned(15 downto 0) := x"0000";

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
      wdata => expansionram_wdata(7 downto 0),
      wdata_hi => expansionram_wdata(15 downto 8),
      wen_hi => '1',
      wen_lo => '1',
      read_request => expansionram_read,
      write_request => expansionram_write,
      rdata_16en => '1',
      rdata => expansionram_rdata(7 downto 0),
      rdata_hi =>  expansionram_rdata(15 downto 8),
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
  
  process(hr_cs0, hr_clk_p, hr_reset, hr_rwds, hr_d,
          hr2_cs0, hr2_clk_p, hr2_reset, hr2_rwds, hr2_d
          ) is
  begin
    if false then
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
    end if;
  end process;

  process (pixelclock) is
  begin
    if false and rising_edge(pixelclock) then
      pixel_counter <= pixel_counter + 1;
      if (pixel_counter(9 downto 0) = to_unsigned(0,10)) then
        report "VIC: Dispatching pixel data request";
        viciv_request_toggle <= pixel_counter(10);
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
  
  process (pixelclock) is
  begin

    if rising_edge(pixelclock) then

      if true then
      report "expansionram_data_ready_strobe=" & std_logic'image(expansionram_data_ready_strobe) 
        & ", expansionram_busy=" & std_logic'image(expansionram_busy)
        & ", expansionram_read=" & std_logic'image(expansionram_read)
        & ", idle_wait=" & std_logic'image(idle_wait)
        & ", expect_value=" & std_logic'image(expect_value);
      end if;
      
      if expansionram_data_ready_strobe='1' then
        if expect_value = '1' then
          if expected_value = expansionram_rdata then
            report "DISPATCHER: Read correct value $" & to_hstring(expansionram_rdata)
              & " after " & integer'image(current_time - dispatch_time) & "ns.";
          else
            report "DISPATCHER: ERROR: Expected $" & to_hstring(expected_value) & ", but saw $" & to_hstring(expansionram_rdata)
              & " after " & integer'image(current_time - dispatch_time) & "ns.";            
          end if;
          dispatch_time <= current_time;
        end if;        
        expect_value <= '0';
      end if;

      expansionram_write <= '0';
      expansionram_read <= '0';

      if expansionram_busy='1' then
        idle_wait <= '0';
      else
        if expect_value = '0' and expansionram_busy='0' then

          if expansionram_busy = '0' and idle_wait='0' then

            if mem_jobs(cycles).address = x"FFFFFFF" then
              report "DISPATCHER: Total sequence was " & integer'image(current_time - start_time) & "ns "
                & "(mean " & integer'image(1+(current_time-start_time)/cycles) & "ns ).";
              cycles <= 0;
              start_time <= current_time;          
            else
              cycles <= cycles + 1;        
            end if;

            dispatch_time <= current_time;
            
            expansionram_address <= mem_jobs(cycles).address(26 downto 0);
            expansionram_write <= mem_jobs(cycles).write_p;
            expansionram_read <= not mem_jobs(cycles).write_p;
            expansionram_wdata <= mem_jobs(cycles).value;
            -- Only wait for memory reads?
            idle_wait <= not mem_jobs(cycles).write_p;

            if (mem_jobs(cycles).write_p='0') then
              -- Let reads finish serially
              -- (In the worst case, this can take quite a while)
              report "DISPATCHER: Reading from $" & to_hstring(mem_jobs(cycles).address) & ", expecting to see $"
                & to_hstring(mem_jobs(cycles).value);
              expect_value <= '1';
              expected_value <= mem_jobs(cycles).value;
            else
              report "DISPATCHER: Writing to $" & to_hstring(mem_jobs(cycles).address) & " <- $"
                & to_hstring(mem_jobs(cycles).value);
              expect_value <= '0';
              dispatch_time <= current_time;
            end if;

            if start_time = 0 then
              start_time <= current_time;
            end if;
          end if;
        end if;
      end if;
    end if;
    
  end process;

  process is
  begin
    
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
