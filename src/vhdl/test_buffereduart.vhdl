library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;
use work.cputypes.all;

entity test_buffereduart is
end entity;

architecture foo of test_buffereduart is

  signal cpuclock : std_logic := '1';
  
  signal cycles : integer := 0;

  type mem_transaction_t is record
    address : unsigned(15 downto 0);
    write_p : std_logic;
    value : unsigned(7 downto 0);     -- either to write, or expected to read
    delay : integer;
  end record mem_transaction_t;

  type mem_job_list_t is array(0 to 2047) of mem_transaction_t;

  signal fastio_addr : unsigned(19 downto 0) := to_unsigned(0,20);
  signal fastio_rdata : unsigned(7 downto 0);
  signal fastio_wdata : unsigned(7 downto 0) := x"00";
  signal fastio_write : std_logic := '0';
  signal fastio_read : std_logic := '0';

  signal buffereduart_cs : std_logic := '1';
  signal uart_irq : std_logic := '1';
  signal reset : std_logic := '1';

  signal buffereduart_rx : std_logic_vector(7 downto 0) := (others => '1');
  signal buffereduart_tx : std_logic_vector(7 downto 0) := (others => '1');
  signal buffereduart_ringindicate : std_logic_vector(7 downto 0) := (others => '1');
  
  signal start_time : integer := 0;
  signal current_time : integer := 0;
  signal dispatch_time : integer := 0;
  
  signal mem_jobs : mem_job_list_t := (
    -- Read $D0E0 status register and wait a while for flags to all update
    ( address => x"D0E0", write_p => '0', value => x"00", delay => 0),
    -- Read $D0E1 status register
    ( address => x"D0E1", write_p => '0', value => x"60", delay => 0),
    others => ( address => x"FFFF", write_p => '0', value => x"00", delay => 1)
    );

  signal idle_wait : integer := 0;
  
  signal expect_value : std_logic := '0';
  signal expected_value : unsigned(7 downto 0) := x"00";
  
begin

  buffered_uart0 : entity work.buffereduart port map (
    clock => cpuclock,
    reset => reset,
    irq => uart_irq,
    buffereduart_cs => buffereduart_cs,

    ---------------------------------------------------------------------------
    -- IO lines to the buffered UART
    ---------------------------------------------------------------------------
    uart_rx => buffereduart_rx,
    uart_tx => buffereduart_tx,
    uart_ringindicate => buffereduart_ringindicate,

    fastio_addr => unsigned(fastio_addr),
    fastio_write => fastio_write,
    fastio_read => fastio_read,
    fastio_rdata => fastio_rdata,
    fastio_wdata => fastio_wdata
    );

  
  process is
  begin
    -- pretend clock at 50MHz, just so the ns display is easier to read in simulation
    cpuclock <= '0';
    wait for 10 ns;
    cpuclock <= '1';
    wait for 10 ns;
  end process;
  
  
  process (cpuclock) is
  begin

    if rising_edge(cpuclock) then
    
      if idle_wait /= 0 then
        idle_wait <= idle_wait - 1;
      else
        
        if mem_jobs(cycles).address = x"FFFF" then
          expect_value <= '0';
          cycles <= 0;
          start_time <= current_time;          
        else
          cycles <= cycles + 1;        
          
          fastio_addr(15 downto 0) <= mem_jobs(cycles).address;
          fastio_addr(19 downto 16) <= x"0";
          fastio_read <= not mem_jobs(cycles).write_p;
          fastio_write <= mem_jobs(cycles).write_p;
          fastio_wdata <= mem_jobs(cycles).value;
          idle_wait <= mem_jobs(cycles).delay;
          
          if start_time = 0 then
            start_time <= current_time;
          end if;
          if (mem_jobs(cycles).write_p='0') then
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
        end if;
        
        if expect_value='1' then
          if fastio_rdata /= expected_value then
            report "DISPATCHER: ERROR: Read value $" & to_hstring(fastio_rdata) & ", expected to see $"
              & to_hstring(expected_value);
          else
            report "DISPATCHER: Read correct value $" & to_hstring(fastio_rdata);
          end if;
        end if;
        
      end if;
      
    end if;
      
  end process;
      
      
end foo;
     
