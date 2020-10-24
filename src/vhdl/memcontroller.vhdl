use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;
use work.victypes.all;

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
  end type;

  signal fastram_iface : array 0 to 8 of fastram_interface := (others => ( addr => 0,
                                                                           we => '0',
                                                                           wdata => x"00",
                                                                           rdata => x"00",
                                                                           token => to_unsigned(0,5)));

  signal fastram_write_now : std_logic := '0';
  signal fastram_next_address : integer range 0 to 1048975 := 0;
  signal fastram_write_bytes_remaining : integer range 0 to 3 := 0;
  signal fastram_write_data_vector : unsigned(31 downto 0) := to_unsigned(0,32);
  signal fastram_write_request_toggle : std_logic := '0';
  signal last_fastram_write_request_toggle : std_logic := '0';
  
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

            if transaction_addr(27 downto 8) = bp_address then
              -- Its to ZP, so also update the ZP cache
            else
              -- Not to ZP, so we can just commit the write immediately
              last_transaction_request_toggle <= transaction_request_toggle;
              transaction_complete_toggle <= transaction_request_toggle;
            end if;

            -- Either way, request the data be written
            fastram_write_request_toggle <= not fastram_write_request_toggle;
            fastram_write_addr <= transaction_address;
            fastram_write_data <= transaction_wdata;
            fastram_write_bytecount <= transaction_length;
            
          end if;
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

      -- If we are writing to fastram, write out the queued bytes
      if fastram_write_now='1' then
        fastram_iface(0).addr <= fastram_next_address;
        fastram_iface(0).wea <= '1';
        fastram_iface(0).wdata <= fastram_write_data_vector(7 downto 0);

        -- Get ready for writing the next byte
        fastram_next_address <= fastram_next_address + 1;
        fastram_write_bytes_remaining <= fastram_write_bytes_remaining - 1;
        if fastram_write_bytes_remaining = 1 then
          fastram_write_now <= '0';
        else
          fastram_write_now <= '1';
        end if;
        fastram_write_data_vector(23 downto 0) <= fastram_write_data_vector(31 downto 8);
      else
        fastram_iface(0).wea <= '0';
      end if;      

      -- Do we have a new write request to fastram?
      if fastram_write_request_toggle /= last_fastram_write_request_toggle then
        last_fastram_write_request_toggle <= fastram_write_request_toggle;
        fastram_write_bytes_remaining <= fastram_write_bytecount;
        fastram_next_address <= fastram_write_addr;
        fastram_write_data_vector <= fastram_write_data;
        fastram_write_now <= '1';
      end if;

    end if;
    
  end process;

    
  
  
end edwardian;
