use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity memcontroller is
  generic(
    chipram_1mb : std_logic := '0';
    cpufrequency : integer := 40;
    chipram_size : integer := 393216;
    target : mega65_target_t := mega65r2);
  port (
    -- Clocks used to drive interface to CPU and memories
    cpuclock : std_logic;
    cpuclock2x : std_logic;
    cpuclock4x : std_logic;
    cpuclock8x : std_logic;

    -- Allows us to know if hypervisor memory is mapped or not
    privileged_access : in std_logic;

    -- We need to know which CPU personality we are, so that we know
    -- how many instruction bytes to fetch
    cpuis6502 : in std_logic;

    -- Is the request a ZP access? If so, then we use or update the
    -- ZP cache for this request.  As the CPU also indicates the number of
    -- bytes, this allows ZP pointer fetches, both 16-bit and 32-bit, to be
    -- served quickly from the ZP cache. ZP cache is clocked at CPU x4, so
    -- total latency for a 16-bit ZP pointer fetch should be ~3 CPU cycles, the
    -- same as now, and a 32-bit ZP pointer fetch should be ~3-4 CPU cycles.
    -- If we made the ZP cache store 16-bit values, we can probably trim 1
    -- cycle of these, but that's a much lower priority.  Initial goal is to
    -- implement the controller, and not have it any slower than at present, at
    -- least for most use-cases.
    is_zp_access : in std_logic;
    
    -- We need to know the ZP/BP address, so that we know if we need to update
    -- the cache based on a normal write, too.
    bp_address : in unsigned(27 downto 8);
    
    -- Memory transaction requests from CPU
    transaction_request_toggle : in std_logic;
    transaction_complete_toggle : out std_logic := '0';
    -- Is the request an instruction fetch or not?
    transaction_is_instruction_fetch : in std_logic;
    -- Length of request (if not instruction fetch) in bytes
    transaction_length : in integer range 0 to 3;

    transaction_address : in unsigned(27 downto 0);
    transaction_write : in std_logic;
    -- Writing can be only upto 4 bytes
    transaction_wdata : in unsigned(31 downto 0);
    -- But reading can be 6 bytes, the maxmimum length of an instruction,
    -- including prefix bytes)
    transaction_rdata : out unsigned(47 downto 0); 

    -- Now we have the interfaces to the various memories we control
    fastio_addr : out std_logic_vector(19 downto 0) := (others => '0');
    fastio_addr_fast : out std_logic_vector(19 downto 0) := (others => '0');
    fastio_read : inout std_logic := '0';
    fastio_write : inout std_logic := '0';
    fastio_wdata : inout std_logic_vector(7 downto 0) := (others => '0');
    fastio_rdata : in std_logic_vector(7 downto 0);

    -- Special paths for various memories
    fastio_vic_rdata : in std_logic_vector(7 downto 0);
    fastio_colour_ram_rdata : in std_logic_vector(7 downto 0);
    colour_ram_cs : out std_logic := '0';
    charrom_write_cs : out std_logic := '0';
        
    -- HYPPO hypervisor RAM interface
    hyppo_rdata : in std_logic_vector(7 downto 0);
    hyppo_address_out : out std_logic_vector(13 downto 0) := (others => '0');

    ---------------------------------------------------------------------------
    -- Slow device access 4GB address space
    ---------------------------------------------------------------------------
    slow_access_request_toggle : out std_logic := '0';
    slow_access_ready_toggle : in std_logic;

    slow_access_address : out unsigned(27 downto 0) := (others => '1');
    slow_access_write : out std_logic := '0';
    slow_access_wdata : out unsigned(7 downto 0) := x"00";
    slow_access_rdata : in unsigned(7 downto 0);

    -- Fast read interface for slow devices linear reading
    -- (only hyperram)
    slow_prefetched_request_toggle : inout std_logic := '0';
    slow_prefetched_data : in unsigned(7 downto 0) := x"00";
    slow_prefetched_address : in unsigned(26 downto 0) := (others => '1');

    ---------------------------------------------------------------------------
    -- VIC-IV interface to fast/chip RAM
    ---------------------------------------------------------------------------
    chipram_clk : IN std_logic := '0';
    chipram_address : IN unsigned(19 DOWNTO 0) := to_unsigned(0,20);
    chipram_dataout : OUT unsigned(7 DOWNTO 0)
    
    
    );
end entity memcontroller;

architecture edwardian of memcontroller is

  type fastram_interface is record
    addr : integer range 0 to 1048575;
    we : std_logic;
    wdata : unsigned(7 downto 0);
    rdata : unsigned(7 downto 0);

    -- Token is used for quick collection of read results
    token : unsigned(4 downto 0);
    token_return : unsigned(4 downto 0);
  end record;

  type fri_array is array (natural range 0 to 8) of fastram_interface;
  
  signal fastram_iface : fri_array := (others => ( addr => 0,
                                                   we => '0',
                                                   wdata => x"00",
                                                   rdata => x"00",
                                                   token => to_unsigned(0,5),
                                                   token_return => to_unsigned(0,5)));

  -- 162MHz request signals
  signal fastram_write_addr : integer range 0 to 1048975 := 0;
  signal fastram_write_data : unsigned(31 downto 0) := to_unsigned(0,32);
  signal fastram_write_bytecount : integer range 0 to 3 := 0;
  signal fastram_read_addr : integer range 0 to 1048975 := 0;
  signal fastram_read_bytecount : integer range 0 to 3 := 0;
  
  -- 324MHz fast internal chip ram access signals
  signal fastram_write_now : std_logic := '0';
  signal fastram_next_address : integer range 0 to 1048975 := 0;
  signal fastram_write_bytes_remaining : integer range 0 to 3 := 0;
  signal fastram_write_data_vector : unsigned(31 downto 0) := to_unsigned(0,32);
  signal fastram_write_request_toggle : std_logic := '0';
  signal last_fastram_write_request_toggle : std_logic := '0';
  signal fastram_read_request_toggle : std_logic := '0';
  signal last_fastram_read_request_toggle : std_logic := '0';
  signal fastram_read_complete_toggle : std_logic := '0';
  signal last_fastram_read_complete_toggle : std_logic := '0';
  signal next_token : unsigned(4 downto 0) := to_unsigned(0,5);
  signal fastram_read_now : std_logic := '0';
  signal fastram_read_bytes_remaining : integer range 0 to 6 := 0;
  signal fastram_read_byte_position : integer range 0 to 6 := 0;
  signal fastram_job_end_token : integer range 0 to 32 := 32;
  type read_tokens is array(0 to 5) of unsigned(4 downto 0);
  signal fastram_read_tokens : read_tokens := (others => to_unsigned(0,5));

  signal fastram_rdata_buffer : unsigned(47 downto 0) := to_unsigned(0,48);
  
  signal zpcache_we : std_logic := '0';
  signal zpcache_waddr : unsigned(9 downto 0 ) := to_unsigned(0,10);
  signal zpcache_raddr : unsigned(9 downto 0 ) := to_unsigned(0,10);
  signal zpcache_rdata : unsigned(35 downto 0);
  signal zpcache_wdata : unsigned(35 downto 0) := to_unsigned(0,36);

  signal last_transaction_request_toggle : std_logic := '0';
  
begin

  -- The main fast memory of the MEGA65, internal to the FPGA
  -- We pipeline the pants out of it to get (a) timing closure; and (b) get
  -- much higher throughput.
  fastram0 : entity work.shadowram port map (
    clkA      => cpuclock8x,
    addressa  => fastram_iface(8).addr,
    wea       => fastram_iface(8).we,
    dia       => fastram_iface(8).wdata,
    doa       => fastram_iface(0).rdata,
    clkB      => chipram_clk,
    addressb  => chipram_address,
    dob       => chipram_dataout
    );

  -- We don't actually use this, yet, but it is a simple ZP cache.
  -- Each line contains 20 bit upper address, and the 8-bit value
  -- stored in that location. Clocked at 4x CPU clock, so that we
  -- can fetch even an entire 32-bit ZP pointer in 1 CPU clock.
  -- By storing the upper part of the address, we avoid the need
  -- for other cache consistency checks, and BP/ZP can be moved
  -- all over the shop without concern.
  zpcache0: entity work.ram36x1k port map (
    clkl => cpuclock4x,
    clkr => cpuclock4x,
    wel(0) => zpcache_we,
    addrl => std_logic_vector(zpcache_waddr),
    addrr => std_logic_vector(zpcache_raddr),
    unsigned(doutr) => zpcache_rdata,
    dinl => std_logic_vector(zpcache_wdata)
    );    

  process(cpuclock,cpuclock2x,cpuclock4x,cpuclock8x) is
  begin
    if rising_edge(cpuclock) then
    end if;
    if rising_edge(cpuclock2x) then
      -- Slow devices is on 2x clock (81MHz) bus interface
    end if;
    if rising_edge(cpuclock4x) then
      -- At 4x CPU clock (162MHz) we examine the CPU's requests, and
      -- prepare to submit them to the state machinery depending
      -- on the true memory address.  We work only using full 28-bit addresses.

      if cpuclock='1' and transaction_request_toggle /= last_transaction_request_toggle then
        -- Looks like a new request has come in.
        -- We really want to dispatch shadow RAM requests as fast as possible,
        -- so we check those immediately
        if to_integer(transaction_address) <= chipram_size then
          -- Ok, so its fast RAM. But we need to know if it is a read or write
          -- operation, and whether it is to/from ZP or not, so that we can update
          -- the cache.
          if transaction_write = '1' then
            -- Its a write

            if transaction_address(27 downto 8) = bp_address then
              -- Its to ZP, so also update the ZP cache
            else
              -- Not to ZP, so we can just commit the write immediately
              last_transaction_request_toggle <= transaction_request_toggle;
              transaction_complete_toggle <= transaction_request_toggle;
            end if;

            -- Either way, request the data be written
            fastram_write_request_toggle <= not fastram_write_request_toggle;
            fastram_write_addr <= to_integer(transaction_address(19 downto 0));
            fastram_write_data <= transaction_wdata;
            fastram_write_bytecount <= transaction_length;
          else
            -- Reading from chip/fast RAM.

            -- Remember that we have accepted the job
            last_transaction_request_toggle <= transaction_request_toggle;

            -- Schedule read
            fastram_read_request_toggle <= not fastram_read_request_toggle;
            fastram_read_addr <= to_integer(transaction_address(19 downto 0));
            fastram_read_bytecount <= transaction_length;
            fastram_rdata_buffer <= to_unsigned(0,48);
            
          end if;
        end if;

        -- Notice when the read is complete, and tell the CPU
        if fastram_read_complete_toggle /= last_fastram_read_complete_toggle then
          last_fastram_read_complete_toggle <= fastram_read_complete_toggle;
          transaction_complete_toggle <= transaction_request_toggle;
          transaction_rdata <= fastram_rdata_buffer;
        end if;
        
      end if;      
    
    end if;
    if rising_edge(cpuclock8x) then
      -- BRAM is on pipelined 8x clock (324MHz)
      -- This is about as fast as we can clock BRAM in these FPGAs,
      -- and requires a lot of pipelining. The end result is still about
      -- the same latency as driving it at 40MHz, but with better throughput
      -- and actually meeting timing closure

      -- Update fast RAM pipeline stages
      for i in 1 to 8 loop
        fastram_iface(i) <= fastram_iface(i-1);
      end loop;
      -- And reflect token ID through the pipeline for pickup
      fastram_iface(0).token_return <= fastram_iface(8).token;

      -- By default idle the fast/chip RAM interface
      fastram_iface(0).addr <= 0;
      fastram_iface(0).we <= '0';
      fastram_iface(0).wdata <= x"00";
      -- And keep cycling the token IDs so that we can easily collect results
      -- at the other end
      fastram_iface(0).token <= next_token;
      next_token <= next_token + 1;
      fastram_read_byte_position <= 0;      

      if fastram_write_now='1' or fastram_read_now='1' then
        fastram_next_address <= fastram_next_address + 1;
      end if;
      
      -- If we are writing to fastram, write out the queued bytes
      if fastram_write_now='1' then
        fastram_iface(0).addr <= fastram_next_address;
        fastram_iface(0).we <= '1';
        fastram_iface(0).wdata <= fastram_write_data_vector(7 downto 0);

        -- Get ready for writing the next byte
        fastram_write_bytes_remaining <= fastram_write_bytes_remaining - 1;
        if fastram_write_bytes_remaining = 1 then
          fastram_write_now <= '0';
        else
          fastram_write_now <= '1';
        end if;
        fastram_write_data_vector(23 downto 0) <= fastram_write_data_vector(31 downto 8);      
      end if;      

      if fastram_read_now='1' then
        fastram_iface(0).addr <= fastram_next_address;
        fastram_read_bytes_remaining <= fastram_read_bytes_remaining - 1;
        if fastram_read_bytes_remaining = 1 then
          fastram_read_now <= '0';
          -- Note which token will mark the end of the read job
          fastram_job_end_token <= to_integer(next_token);
        else
          fastram_read_now <= '1';
        end if;
        -- Note the token ID and where it needs to go
        fastram_read_tokens(fastram_read_byte_position) <= next_token;
        fastram_read_byte_position <= fastram_read_byte_position + 1;
        
      end if;
      
      -- Do we have a new write request to fastram?
      if fastram_write_request_toggle /= last_fastram_write_request_toggle then
        last_fastram_write_request_toggle <= fastram_write_request_toggle;
        fastram_write_bytes_remaining <= fastram_write_bytecount;
        fastram_next_address <= fastram_write_addr;
        fastram_write_data_vector <= fastram_write_data;
        fastram_write_now <= '1';
      end if;

      -- Or read request to fastram
      if fastram_read_request_toggle /= last_fastram_read_request_toggle then
        last_fastram_write_request_toggle <= fastram_write_request_toggle;
        fastram_read_bytes_remaining <= fastram_read_bytecount;
        fastram_next_address <= fastram_read_addr;
        fastram_read_now <= '1';
        fastram_read_byte_position <= 0;
        -- Set end of job token initially to be invalid.
        -- It will get updated with the correct value when the read job is underway
        fastram_job_end_token <= 32; -- only tokens 0 -- 31 exist
      end if;
      for i in 0 to 5 loop
        if fastram_iface(8).token_return = fastram_read_tokens(i) then
          -- We have read a byte we are waiting for
          fastram_rdata_buffer(i*8 + 7 downto i*8) <= fastram_iface(8).rdata;
        end if;
      end loop;
      if to_integer(fastram_iface(8).token_return) = fastram_job_end_token then
        -- This was the last byte we needed to read, so we can tell the slower
        -- interface to collect and present the result back to the CPU
        fastram_read_complete_toggle <= fastram_read_request_toggle;
      end if;
      
      
    end if;
    
  end process;

    
  
  
end edwardian;
