library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;
use work.cputypes.all;

entity test_memcontroller is
end entity;

architecture foo of test_memcontroller is

  signal cpuclock : std_logic := '1';
  signal pixelclock : std_logic := '1';
  signal clock163 : std_logic := '1';
  signal clock325 : std_logic := '1';
  
  signal cycles : integer := 0;

  signal expecting_byte : std_logic := '0';
  signal expected_byte : unsigned(7 downto 0);

  type mem_transaction_t is record
    address : unsigned(27 downto 0);
    write_p : std_logic;
    ifetch : std_logic;                -- set if instruction fetch
    value : unsigned(47 downto 0);     -- either to write, or expected to read    
    bytes : integer range 0 to 6;      -- number of bytes transferred
  end record mem_transaction_t;

  type mem_job_list_t is array(0 to 2047) of mem_transaction_t;

  signal start_time : integer := 0;
  signal current_time : integer := 0;
  signal dispatch_time : integer := 0;
  
  signal mem_jobs : mem_job_list_t := (
    -- Simple write and then read immediately
    (address => x"0000400", ifetch => '0', write_p => '1', bytes => 1, value => x"000000000091"),
    (address => x"0000400", ifetch => '0', write_p => '0', bytes => 1, value => x"000000000091"),

    -- Now lets try some multi-byte reads and writes
    (address => x"0000401", ifetch => '0', write_p => '1', bytes => 4, value => x"000012345678"),
    (address => x"0000405", ifetch => '0', write_p => '1', bytes => 4, value => x"000090abcdef"),
    (address => x"0000401", ifetch => '0', write_p => '0', bytes => 4, value => x"000012345678"),
    (address => x"0000405", ifetch => '0', write_p => '0', bytes => 4, value => x"000090abcdef"),

    -- And now try some simple slow device bus accesses
    (address => x"7FEFFFF", ifetch => '0', write_p => '1', bytes => 1, value => x"000000000001"),
    (address => x"7FEFFFF", ifetch => '0', write_p => '0', bytes => 1, value => x"000000000001"),
    (address => x"7FEFFFF", ifetch => '0', write_p => '1', bytes => 1, value => x"000000000000"),
    (address => x"7FEFFFF", ifetch => '0', write_p => '0', bytes => 1, value => x"000000000000"),

    -- Simple write and then read via fastio to a dummy CIA
    (address => x"ffd0d02", ifetch => '0', write_p => '1', bytes => 1, value => x"0000000000C1"),
    (address => x"ffd0d02", ifetch => '0', write_p => '0', bytes => 1, value => x"0000000000C1"),
    
    others => ( address => x"FFFFFFF", ifetch => '0', write_p => '0', bytes => 1, value => x"000000000000")
    );

  -- Don't wait before starting
  -- XXX HyperRAM not ready for first ~1000 cycles
  signal idle_wait : integer := 1;
  
  signal expect_value : std_logic := '0';
  signal expected_value : unsigned(47 downto 0) := to_unsigned(0,48);

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
  signal slow_prefetched_request_toggle : std_logic := '0';
  signal slow_access_request_toggle : std_logic := '0';
  signal slow_access_ready_toggle : std_logic;
  signal last_slow_access_ready_toggle : std_logic;
  signal slow_access_write : std_logic := '0';
  signal slow_access_address : unsigned(27 downto 0);
  signal slow_access_wdata : unsigned(7 downto 0);
  signal slow_access_rdata : unsigned(7 downto 0);  

  signal fastio_addr : std_logic_vector(19 downto 0) := (others => '0');
  signal fastio_addr_fast : std_logic_vector(19 downto 0);
  signal fastio_read : std_logic;
  signal fastio_write : std_logic;
  signal fastio_wdata : std_logic_vector(7 downto 0);
  signal fastio_rdata : std_logic_vector(7 downto 0);
  signal fastio_vic_rdata : std_logic_vector(7 downto 0);
  signal fastio_colour_ram_rdata : std_logic_vector(7 downto 0);

  signal hyppo_rdata : std_logic_vector(7 downto 0);
  signal hyppo_address_out : std_logic_vector(13 downto 0);

  signal colour_ram_cs : std_logic;
  signal charrom_write_cs : std_logic;

  signal cia1_cs : std_logic := '0';  
  
  signal transaction_request_toggle : std_logic := '0';
  signal transaction_complete_toggle : std_logic := '0';
  signal last_transaction_complete_toggle : std_logic := '0';
  signal transaction_is_instruction_fetch : std_logic := '0';
  signal transaction_length : integer range 0 to 6 := 0;
  signal transaction_address : unsigned(27 downto 0) := to_unsigned(0,28);
  signal transaction_write : std_logic := '0';
  signal transaction_wdata : unsigned(31 downto 0) := to_unsigned(0,32);
  signal transaction_rdata : unsigned(47 downto 0) := to_unsigned(0,48);
  
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

--    viciv_addr => viciv_addr,
--    viciv_request_toggle => viciv_request_toggle,
--    viciv_data_out => viciv_data,
--    viciv_data_strobe => viciv_data_strobe,
      
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

  -- Add a dummy CIA so we have something on the fastio bus to access
  cia1: entity work.cia6526
    port map(
      cpuclock => cpuclock,
      phi0_1mhz => cpuclock,
      todclock => '0',
      reset => '1',
      irq => open,
      hypervisor_mode => '0',
      cs => cia1_cs,

      fastio_address => unsigned(fastio_addr(7 downto 0)),
      fastio_write => fastio_write,
      fastio_wdata => unsigned(fastio_wdata),
      std_logic_vector(fastio_rdata) => fastio_rdata,
      portain => (others => '1'),
      portbin => (others => '1'),
      flagin => '1',
      spin => '1',
      countin => '1'
      );
  
  memcontroller0: entity work.memcontroller
    generic map (
      target => mega65r3,
      chipram_1mb => '0',
      chipram_size => 393216
      )
    port map (
      cpuclock => cpuclock,
      cpuclock2x => pixelclock,
      cpuclock4x => clock163,
      cpuclock8x => clock325,
      
      privileged_access => '1',

      cpuis6502 => '0',

      is_zp_access => '0',

      bp_address => to_unsigned(0,20),

      transaction_request_toggle => transaction_request_toggle,
      transaction_complete_toggle => transaction_complete_toggle,
      transaction_is_instruction_fetch => transaction_is_instruction_fetch,
      transaction_length => transaction_length,
      transaction_address => transaction_address,
      transaction_write => transaction_write,
      transaction_wdata => transaction_wdata,
      transaction_rdata => transaction_rdata,

      fastio_addr => fastio_addr,
      fastio_addr_fast => fastio_addr_fast,
      fastio_read => fastio_read,
      fastio_write => fastio_write,
      fastio_wdata => fastio_wdata,
      fastio_viciv_rdata => fastio_vic_rdata,
      fastio_rdata => fastio_rdata,

      fastio_vic_rdata => fastio_vic_rdata,
      fastio_colour_ram_rdata => fastio_colour_ram_rdata,
      colour_ram_cs => colour_ram_cs,
      charrom_write_cs => charrom_write_cs,

      hyppo_rdata => hyppo_rdata,
      hyppo_address_out => hyppo_address_out,

      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle => slow_access_ready_toggle,
      slow_access_address => slow_access_address,
      slow_access_write => slow_access_write,
      slow_access_wdata => slow_access_wdata,
      slow_access_rdata => slow_access_rdata,

      slow_prefetched_request_toggle => slow_prefetched_request_toggle,
      slow_prefetched_data => slow_prefetched_data,
      slow_prefetched_address => slow_prefetched_address

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

  
  process (clock325) is
  begin
    -- Control chip-select line for dummy CIA
    if fastio_addr(19 downto 8) = x"D0D" then
      cia1_cs <= '1';
    else
      cia1_cs <= '0';
    end if;
    
    if rising_edge(clock325) then
      current_time <= current_time + 3;
    end if;
  end process;
  
  process is
  begin

    if transaction_complete_toggle /= last_transaction_complete_toggle then

      if expect_value = '1' then
        if expected_value = transaction_rdata then
          report "DISPATCHER: Read correct value $" & to_hstring(transaction_rdata)
            & " after " & integer'image(current_time - dispatch_time) & "ns.";
        else
          report "DISPATCHER: ERROR: Expected $" & to_hstring(expected_value) & ", but saw $" & to_hstring(transaction_rdata)
            & " after " & integer'image(current_time - dispatch_time) & "ns.";
          for i in 0 to 47 loop
            if (expected_value(i) /= transaction_rdata(i)) then
              report "BITERROR in bit " & integer'image(i)
                & ", expected " & std_logic'image(expected_value(i))
                & ", saw " & std_logic'image(transaction_rdata(i));
            end if;
          end loop;
        end if;
        dispatch_time <= current_time;
      end if;        
      -- Perform transactions immediately after one another
      idle_wait <= 0;
      expect_value <= '0';
      last_transaction_complete_toggle <= transaction_complete_toggle;
    end if;
   
    if transaction_complete_toggle = last_transaction_complete_toggle then

      if idle_wait /= 0 then
        idle_wait <= idle_wait - 1;
      elsif expect_value = '0' then

        if mem_jobs(cycles).address = x"FFFFFFF" then
          report "DISPATCHER: Total sequence was " & integer'image(current_time - start_time) & "ns "
            & "(mean " & integer'image(1+(current_time-start_time)/cycles) & "ns ).";
          cycles <= 0;
          start_time <= current_time;          
        else
          cycles <= cycles + 1;        
        end if;

        transaction_address <= mem_jobs(cycles).address;
        transaction_write <= mem_jobs(cycles).write_p;
        transaction_wdata <= mem_jobs(cycles).value(31 downto 0);
        transaction_is_instruction_fetch <= mem_jobs(cycles).ifetch;
        transaction_length <= mem_jobs(cycles).bytes;
        transaction_request_toggle <= not transaction_request_toggle;
        
        if start_time = 0 then
          start_time <= current_time;
        end if;
        if (mem_jobs(cycles).write_p='0') then
          report "DISPATCHER: Reading from $" & to_hstring(mem_jobs(cycles).address) & ", expecting to see $"
            & to_hstring(mem_jobs(cycles).value);
          expect_value <= '1';
          expected_value <= mem_jobs(cycles).value;
          dispatch_time <= current_time;
        else
          report "DISPATCHER: Writing to $" & to_hstring(mem_jobs(cycles).address) & " <- $"
            & to_hstring(mem_jobs(cycles).value);
          expect_value <= '0';
          dispatch_time <= current_time;
        end if;

        -- Allow enough time for jobs to finish
        -- Some of the slow_devices tests can take a very long time
        idle_wait <= 1024;
        
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
