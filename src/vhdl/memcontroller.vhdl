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
    hyppo_size : integer := 16384;
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

    -- Instruction fetch transaction requests from CPU
    instruction_fetch_request_toggle : in std_logic;
    instruction_fetch_address_in : in integer;
    instruction_fetched_address_out : out integer;
    instruction_fetch_rdata : out unsigned(47 downto 0) := (others => '1');

    -- Memory transaction requests from CPU
    transaction_request_toggle : in std_logic;
    transaction_complete_toggle : out std_logic := '0';
    -- Length of request (if not instruction fetch) in bytes
    transaction_length : in integer range 0 to 6;

    transaction_address : in unsigned(27 downto 0);
    transaction_write : in std_logic;
    -- Writing can be only upto 4 bytes
    transaction_wdata : in unsigned(31 downto 0);
    -- But reading can be 6 bytes, the maxmimum length of an instruction,
    -- including prefix bytes)
    transaction_rdata : out unsigned(47 downto 0);

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

    -- Now we have the interfaces to the various memories we control
    fastio_addr : out std_logic_vector(19 downto 0) := (others => '0');
    fastio_addr_fast : out std_logic_vector(19 downto 0) := (others => '0');
    fastio_read : inout std_logic := '0';
    fastio_write : inout std_logic := '0';
    fastio_wdata : inout std_logic_vector(7 downto 0) := (others => '0');
    fastio_viciv_rdata : in std_logic_vector(7 downto 0);
    fastio_rdata : in std_logic_vector(7 downto 0);

    -- Special paths for various memories
    fastio_vic_rdata : in std_logic_vector(7 downto 0);
    fastio_colour_ram_rdata : in std_logic_vector(7 downto 0);
    colour_ram_cs : out std_logic := '0';
    charrom_write_cs : out std_logic := '0';

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
    addr : integer range 0 to (chipram_size-1);
    addr_return : integer range 0 to (chipram_size-1);
    we : std_logic;
    wdata : unsigned(7 downto 0);
    rdata : unsigned(7 downto 0);

    -- Token is used for quick collection of read results
    token : unsigned(4 downto 0);
    token_return : unsigned(4 downto 0);

    -- And similarly for instruction fetches
    is_ifetch : std_logic;
    is_ifetch_return : std_logic;
  end record;

  type fri_array is array (natural range 0 to 8) of fastram_interface;

  signal instruction_fetch_request_toggle_drive : std_logic;
  signal instruction_fetch_address_in_drive : integer;
  
  signal fastram_iface : fri_array := (others => ( addr => 0,
                                                   addr_return => 0,
                                                   we => '0',
                                                   wdata => x"00",
                                                   rdata => x"00",
                                                   is_ifetch => '0',
                                                   is_ifetch_return => '0',
                                                   token => to_unsigned(0,5),
                                                   token_return => to_unsigned(0,5)));

  constant fastram_pipeline_depth : integer := 8;

  -- 162MHz request signals
  signal fastram_write_addr : integer range 0 to (chipram_size-1) := 0;
  signal fastram_write_data : unsigned(31 downto 0) := to_unsigned(0,32);
  signal fastram_write_bytecount : integer range 0 to 6 := 0;
  signal fastram_read_addr : integer range 0 to (chipram_size-1) := 0;
  signal fastram_read_bytecount : integer range 0 to 6 := 0;
  signal fastram_background_read : std_logic := '0';

  -- 324MHz fast internal chip ram access signals
  signal fastram_write_now : std_logic := '0';
  signal fastram_next_address : integer range 0 to (chipram_size-1) := 0;
  signal fastram_next_ifetch_address : integer range 0 to (chipram_size-1) := 0;
  signal last_instruction_fetch_request_toggle : std_logic := '0';
  signal fastram_write_bytes_remaining : integer range 0 to 6 := 0;
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
  type read_tokens is array(0 to 5) of integer range 0 to 33;
  signal fastram_read_tokens : read_tokens := (others => 33);

  signal fastram_rdata_buffer : unsigned(47 downto 0) := to_unsigned(0,48);
  signal fastram_rdata : unsigned(7 downto 0) := x"00";


  ---------
  signal hyppo_iface : fri_array := (others => ( addr => 0,
                                                   addr_return => 0,
                                                   we => '0',
                                                   wdata => x"00",
                                                   rdata => x"00",
                                                   is_ifetch => '0',
                                                   is_ifetch_return => '0',
                                                   token => to_unsigned(0,5),
                                                   token_return => to_unsigned(0,5)));

  -- HYPPO RAM is much smaller, so we shouldn't need such a long pipeline for
  -- the signals to get gathered from around the die
  constant hyppo_pipeline_depth : integer := 4;

  -- 162MHz request signals
  signal hyppo_write_addr : integer range 0 to (chipram_size-1) := 0;
  signal hyppo_write_data : unsigned(31 downto 0) := to_unsigned(0,32);
  signal hyppo_write_bytecount : integer range 0 to 6 := 0;
  signal hyppo_read_addr : integer range 0 to (chipram_size-1) := 0;
  signal hyppo_read_bytecount : integer range 0 to 6 := 0;
  signal hyppo_background_read : std_logic := '0';

  -- 324MHz fast internal chip ram access signals
  signal hyppo_write_now : std_logic := '0';
  signal hyppo_next_address : integer range 0 to (chipram_size-1) := 0;
  signal hyppo_next_ifetch_address : integer range 0 to (chipram_size-1) := 0;
  signal hyppo_write_bytes_remaining : integer range 0 to 6 := 0;
  signal hyppo_write_data_vector : unsigned(31 downto 0) := to_unsigned(0,32);
  signal hyppo_write_request_toggle : std_logic := '0';
  signal last_hyppo_write_request_toggle : std_logic := '0';
  signal hyppo_read_request_toggle : std_logic := '0';
  signal last_hyppo_read_request_toggle : std_logic := '0';
  signal hyppo_read_complete_toggle : std_logic := '0';
  signal last_hyppo_read_complete_toggle : std_logic := '0';
  signal hyppo_read_now : std_logic := '0';
  signal hyppo_read_bytes_remaining : integer range 0 to 6 := 0;
  signal hyppo_read_byte_position : integer range 0 to 6 := 0;
  signal hyppo_job_end_token : integer range 0 to 32 := 32;
  signal hyppo_read_tokens : read_tokens := (others => 33);

  signal hyppo_rdata_buffer : unsigned(47 downto 0) := to_unsigned(0,48);
  signal hyppo_rdata : unsigned(7 downto 0) := x"00";

  
  -----
  
  
  signal slow_access_request_toggle_int : std_logic := '0';
  signal slowdev_access_read_position : integer range 0 to 7 := 0;
  signal slowdev_read_bytes_remaining_plus_one : integer range 0 to 7 := 0;
  signal slowdev_read_bytecount : integer range 0 to 6 := 0;
  signal slowdev_write_bytes_remaining : integer range 0 to 6 := 0;
  signal slowdev_write_bytecount : integer range 0 to 6 := 0;
  signal slowdev_rdata_buffer : unsigned(47 downto 0) := to_unsigned(0,48);
  signal slowdev_write_data_vector : unsigned(31 downto 0) := to_unsigned(0,32);
  signal slowdev_write_data_vector_new : unsigned(31 downto 0) := to_unsigned(0,32);
  signal slowdev_next_address : unsigned(27 downto 0) := to_unsigned(0,28);
  signal slowdev_next_address_new : unsigned(27 downto 0) := to_unsigned(0,28);
  signal slowdev_read_request_toggle : std_logic := '0';
  signal slowdev_write_request_toggle : std_logic := '0';
  signal last_slowdev_read_request_toggle : std_logic := '0';
  signal last_slowdev_write_request_toggle : std_logic := '0';
  signal slowdev_read_complete_toggle : std_logic := '0';
  signal last_slowdev_read_complete_toggle : std_logic := '0';
  signal slowdev_write_complete_toggle : std_logic := '0';
  signal last_slowdev_write_complete_toggle : std_logic := '0';

  signal fastio_request_toggle_int : std_logic := '0';
  signal fastio_read_position : integer range 0 to 7 := 0;
  signal fastio_read_bytes_remaining_plus_one : integer range 0 to 7 := 0;
  signal fastio_read_bytecount : integer range 0 to 6 := 0;
  signal fastio_write_bytes_remaining : integer range 0 to 6 := 0;
  signal fastio_write_bytecount : integer range 0 to 6 := 0;
  signal fastio_rdata_buffer : unsigned(47 downto 0) := to_unsigned(0,48);
  signal fastio_write_data_vector : unsigned(31 downto 0) := to_unsigned(0,32);
  signal fastio_write_data_vector_new : unsigned(31 downto 0) := to_unsigned(0,32);
  signal fastio_next_address : unsigned(19 downto 0) := to_unsigned(0,20);
  signal fastio_next_address_new : unsigned(19 downto 0) := to_unsigned(0,20);
  signal fastio_read_request_toggle : std_logic := '0';
  signal fastio_write_request_toggle : std_logic := '0';
  signal last_fastio_read_request_toggle : std_logic := '0';
  signal last_fastio_write_request_toggle : std_logic := '0';
  signal fastio_read_complete_toggle : std_logic := '0';
  signal last_fastio_read_complete_toggle : std_logic := '0';
  signal fastio_write_complete_toggle : std_logic := '0';
  signal last_fastio_write_complete_toggle : std_logic := '0';
  signal src_is_colourram : std_logic := '0';
  signal src_is_viciv : std_logic := '0';

  signal zpcache_we : std_logic := '0';
  signal zpcache_waddr : unsigned(9 downto 0 ) := to_unsigned(0,10);
  signal zpcache_raddr : unsigned(9 downto 0 ) := to_unsigned(0,10);
  signal zpcache_rdata : unsigned(35 downto 0);
  signal zpcache_wdata : unsigned(35 downto 0) := to_unsigned(0,36);

  -- Instruction fetch buffer structures
  -- First, we have the lowest layer, which runs at CPU x 8 (324MHz), and just
  -- captures some bytes, and the number of bytes stored
  signal fastram_next_instruction_store : std_logic := '0';
  signal fastram_next_instruction_address : integer range 0 to (chipram_size-1) := 0;
  signal fastram_next_instruction_address_plus_one : integer range 0 to (chipram_size-1) := 0;
  signal fastram_next_instruction_address_plus_two : integer range 0 to (chipram_size-1) := 0;
  signal fastram_next_instruction_position : integer range 0 to 6 := 6;
  signal fastram_next_instruction_position_plus_one : integer range 0 to 6 := 6;
  signal fastram_next_instruction_position_plus_two : integer range 0 to 6 := 6;
  signal fastram_next_instruction_store_position : integer range 0 to 6 := 6;
  signal ifetch_buffer324 : unsigned(47 downto 0) := to_unsigned(0,48);
  signal ifetch_buffer324_byte_count : integer range 0 to 6 := 6;
  signal ifetch_buffer324_end_address : integer range 0 to (chipram_size-1) := 0;
  signal fastram_next_instruction_loaded_toggle : std_logic := '0';
  signal last_fastram_next_instruction_loaded_toggle : std_logic := '0';
  signal fastram_next_instruction_buffer324_end_address  : integer range 0 to (chipram_size-1) := 0;
  -- Then we periodically latch that into one of several buffers in a slower clockspeed
  -- slot, so that we can present the desired instruction data to the CPU.
  -- XXX We can also consider doing some creative pre-decoding of the
  -- instruction, so that we can predict what the next instruction address will
  -- be.
  signal ifetch_buffer162 :  unsigned(47 downto 0) := to_unsigned(0,48);
  signal ifetch_buffer162_addr : integer range 0 to (chipram_size-1) := 0;
  signal ifetch_buffer162_addr_drive : integer range 0 to (chipram_size-1) := 0;
  signal latch_ifetch_buffer324 : std_logic := '0';
  -- The highlevel assembled 16-byte instruction fetch buffer
  signal ifetch_buffer : unsigned(127 downto 0) := (others => '0');
  signal ifetch_buffer_byte_count : integer range 0 to 16 := 0;
  signal ifetch_buffer_addr : integer range 0 to (chipram_size-1) := 0;

  signal instruction_fetched_address_out_drive : integer range 0 to (chipram_size-1) := 0;
  signal instruction_fetched_rdata_drive : unsigned(47 downto 0) := (others => '0');

  signal last_transaction_request_toggle : std_logic := '0';

begin

  -- The main fast memory of the MEGA65, internal to the FPGA
  -- We pipeline the pants out of it to get (a) timing closure; and (b) get
  -- much higher throughput.
  fastram0 : entity work.shadowram port map (
    clkA      => cpuclock8x,
    addressa  => fastram_iface(fastram_pipeline_depth).addr,
    wea       => fastram_iface(fastram_pipeline_depth).we,
    dia       => fastram_iface(fastram_pipeline_depth).wdata,
    doa       => fastram_rdata,
    clkB      => chipram_clk,
    addressb  => chipram_address,
    dob       => chipram_dataout
    );

  -- The 16KB hypervisor memory.
  -- We clock this at 8x CPU speed like the main fast/chip RAM, to minimise latency
  block1: block
  begin
  hypporom : entity work.hyppo port map (
    clk     => cpuclock8x,
    address => hyppo_iface(hyppo_pipeline_depth).addr,
    address_i => hyppo_iface(hyppo_pipeline_depth).addr,
    we      => hyppo_iface(hyppo_pipeline_depth).we,
    cs      => privileged_access,
    data_o  => hyppo_rdata,
    data_i  => hyppo_iface(hyppo_pipeline_depth).wdata
    );
  end block;
  
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

      fastio_addr <= (others => '1');
      fastio_write <= '0';

      -- XXX Save one cycle by immediately initiating the first fastio read/write
      -- when accepting the job
      
      colour_ram_cs <= '0';
      if fastio_read_request_toggle /= last_fastio_read_request_toggle then
        fastio_read_bytes_remaining_plus_one <= fastio_read_bytecount + 1;
        fastio_next_address <= fastio_next_address_new;
        fastio_rdata_buffer <= to_unsigned(0,48);
        last_fastio_read_request_toggle <= fastio_read_request_toggle;
      end if;

      if fastio_write_request_toggle /= last_fastio_write_request_toggle then
        report "saw fastio write request for " & integer'image(fastio_write_bytecount) & " bytes, toggle="
          & std_logic'image(fastio_write_request_toggle)
          & ", last_toggle=" & std_logic'image(last_fastio_write_request_toggle);
        fastio_write_bytes_remaining <= fastio_write_bytecount;
        fastio_next_address <= fastio_next_address_new;
        fastio_write_data_vector <= fastio_write_data_vector_new;
        last_fastio_write_request_toggle <= fastio_write_request_toggle;
      end if;

      if (fastio_write_bytes_remaining /= 0) then
        report "fastio write happening now. Data = $" & to_hstring(fastio_write_data_vector(7 downto 0));
        -- Get ready for writing the next byte
        fastio_next_address <= fastio_next_address + 1;
        fastio_write_bytes_remaining <= fastio_write_bytes_remaining - 1;
        fastio_write_data_vector(23 downto 0) <= fastio_write_data_vector(31 downto 8);

        fastio_addr <= std_logic_vector(fastio_next_address);
        fastio_wdata <= std_logic_vector(fastio_write_data_vector(7 downto 0));
        fastio_write <= '1';

        if fastio_write_bytes_remaining = 1 then
          -- We are now writing our last byte, so we can report completion
          report "wrote last byte to slowdev";
          fastio_write_complete_toggle <= not fastio_write_complete_toggle;
        end if;
      end if;

      if fastio_read_bytes_remaining_plus_one /= 0 then
        report "fastio read happening now";
        -- XXX some fastio devices have a wait state:
        -- With this setup, we can pipeline the reads, but we still have to
        -- have that extra cycle of delay before reading the first value
        fastio_next_address <= fastio_next_address + 1;
        fastio_read_bytes_remaining_plus_one <= fastio_read_bytes_remaining_plus_one - 1;

        fastio_addr <= std_logic_vector(fastio_next_address);
        fastio_write <= '0';
        colour_ram_cs <= src_is_colourram;

        if fastio_read_bytes_remaining_plus_one = 1 then
          -- We are now scheduling reading the last byte
          fastio_read_complete_toggle <= not fastio_read_complete_toggle;
        end if;

        if fastio_read_position > 5 then
          fastio_read_position <= 0;
        else
          fastio_read_position <= fastio_read_position + 1;
          if src_is_viciv= '1' then
            fastio_rdata_buffer(fastio_read_position*8+7 downto fastio_read_position*8)
              <= unsigned(fastio_viciv_rdata);
            report "fastio VIC-IV stashing byte $" & to_hstring(fastio_viciv_rdata) & " into byte " & integer'image(fastio_read_position);
          elsif src_is_colourram='1' then
            fastio_rdata_buffer(fastio_read_position*8+7 downto fastio_read_position*8)
              <= unsigned(fastio_colour_ram_rdata);
            report "fastio VIC-IV stashing byte $" & to_hstring(fastio_colour_ram_rdata) & " into byte " & integer'image(fastio_read_position);
          else
            fastio_rdata_buffer(fastio_read_position*8+7 downto fastio_read_position*8)
              <= unsigned(fastio_rdata);
            report "fastio stashing byte $" & to_hstring(fastio_rdata) & " into byte " & integer'image(fastio_read_position);
          end if;
        end if;
      end if;

    end if;
    if rising_edge(cpuclock2x) then
      -- Slow devices is on 2x clock (81MHz) bus interface

      if slowdev_read_request_toggle /= last_slowdev_read_request_toggle then
        slowdev_read_bytes_remaining_plus_one <= slowdev_read_bytecount + 1;
        last_slowdev_read_request_toggle <= slowdev_read_request_toggle;
        slowdev_rdata_buffer <= to_unsigned(0,48);
      end if;
      if slowdev_write_request_toggle /= last_slowdev_write_request_toggle then
        report "saw slowdev write request for " & integer'image(slowdev_write_bytecount) & " bytes, toggle="
          & std_logic'image(slowdev_write_request_toggle)
          & ", last_toggle=" & std_logic'image(last_slowdev_write_request_toggle);
        slowdev_write_bytes_remaining <= slowdev_write_bytecount;
        slowdev_write_data_vector <= slowdev_write_data_vector_new;
        last_slowdev_write_request_toggle <= slowdev_write_request_toggle;
      end if;

      if (slowdev_write_bytes_remaining /= 0) and (slow_access_ready_toggle = slow_access_request_toggle_int) then
        report "slowdev write happening now";
        -- Get ready for writing the next byte
        slowdev_next_address <= slowdev_next_address + 1;
        slowdev_write_bytes_remaining <= slowdev_write_bytes_remaining - 1;
        slowdev_write_data_vector(23 downto 0) <= slowdev_write_data_vector(31 downto 8);

        slow_access_address <= slowdev_next_address;
        slow_access_wdata <= slowdev_write_data_vector(7 downto 0);
        slow_access_write <= '1';
        slow_access_request_toggle <= not slow_access_request_toggle_int;
        slow_access_request_toggle_int <= not slow_access_request_toggle_int;

        if slowdev_write_bytes_remaining = 1 then
          -- We are now writing our last byte, so we can report completion
          report "wrote last byte to slowdev";
          slowdev_write_complete_toggle <= not slowdev_write_complete_toggle;
        end if;
      end if;

      if slowdev_read_bytes_remaining_plus_one /= 0 and (slow_access_ready_toggle = slow_access_request_toggle_int) then
        report "slowdev read happening now";
        slowdev_next_address <= slowdev_next_address + 1;
        slowdev_read_bytes_remaining_plus_one <= slowdev_read_bytes_remaining_plus_one - 1;

        slow_access_address <= slowdev_next_address;
        slow_access_write <= '0';
        slow_access_request_toggle_int <= not slow_access_request_toggle_int;
        slow_access_request_toggle <= not slow_access_request_toggle_int;

        if slowdev_read_bytes_remaining_plus_one = 1 then
          -- We are now scheduling reading the last byte
          slowdev_read_complete_toggle <= not slowdev_read_complete_toggle;
        end if;

        if slowdev_access_read_position > 6 then
          slowdev_access_read_position <= 0;
        else
          slowdev_access_read_position <= slowdev_access_read_position + 1;
          slowdev_rdata_buffer(slowdev_access_read_position*8+7 downto slowdev_access_read_position*8)
            <= slow_access_rdata;
          report "slowdev stashing byte $" & to_hstring(slow_access_rdata) & " into byte " & integer'image(slowdev_access_read_position);
        end if;

      end if;

    end if;
    if rising_edge(cpuclock4x) then
      -- At 4x CPU clock (162MHz) we examine the CPU's requests, and
      -- prepare to submit them to the state machinery depending
      -- on the true memory address.  We work only using full 28-bit addresses.

      -- Give signals time to propagate from CPU to here
      instruction_fetch_request_toggle_drive <= instruction_fetch_request_toggle;
      instruction_fetch_address_in_drive <= instruction_fetch_address_in;
      
      instruction_fetched_address_out <= instruction_fetched_address_out_drive;
      instruction_fetch_rdata <= instruction_fetched_rdata_drive;

      if (transaction_request_toggle /= last_transaction_request_toggle)
      then
        -- Looks like a new request has come in.
        -- We really want to dispatch shadow RAM requests as fast as possible,
        -- so we check those immediately -- unless we have a request running in
        -- the background
        report "transaction request for $" & to_hstring(transaction_address);

        if transaction_address(27 downto 8) = bp_address then
          -- Its to ZP, so also update the ZP cache
        end if;
        
        if (to_integer(transaction_address) <= chipram_size)
          and (fastram_write_request_toggle = last_fastram_write_request_toggle)
          and (fastram_read_request_toggle = last_fastram_read_request_toggle)
        then
          -- Ok, so its fast RAM. But we need to know if it is a read or write
          -- operation, and whether it is to/from ZP or not, so that we can update
          -- the cache.
          if transaction_write = '1' then
            -- Its a write
            last_transaction_request_toggle <= transaction_request_toggle;
            report "COMPLETE: immediate return from fastram write, because they never take >1 40MHz clock cycle";
            transaction_complete_toggle <= transaction_request_toggle;

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
            fastram_background_read <= '0';
          end if;
        end if;

        -- Maybe not fast/chip RAM.

        -- Latency is still important, but not as critical as for fast RAM,
        -- so we are able to flatten logic a little here.
        -- We need to consider:
        -- FastIO @ $FFxxxxx
        -- SlowDevices @ $4000000-$7FFFFFF
        -- SlowDevices @ $8000000-$FEFFFFF
        -- Other special cases that nominally live within the FastIO range:
        --   VIC-IV registers
        --   Colour RAM
        --   VIC-IV palette memories
        --   Hypervisor RAM

        -- FastIO is @ 40.5MHz at present, while SlowDevices is clocked at cpu x2
        -- (81MHz).  Thus we have separate little state-machines for each.  These
        -- work broadly as for the fast/chip RAM case, with toggles to cross
        -- the various clock domains.

        report "not fast/chip ram request @ $" & to_hstring(transaction_address);

        -- Remember that we have accepted the job
        last_transaction_request_toggle <= transaction_request_toggle;
        
        if transaction_address(27 downto 20) = x"FF" then
          -- FastIO range
          if transaction_address(19 downto 16) = x"8" then
            -- Colour RAM
            -- (physically connected to the fastio bus: we should separate
            -- it, and use 324MHz clock on it)
            src_is_colourram <= '1';
          elsif transaction_address(19 downto 14) = "111110" then
            -- Hypervisor memory
            report "HYPPO RAM request";
            if transaction_write = '1' then
              -- Its a write
              
              last_transaction_request_toggle <= transaction_request_toggle;
              report "COMPLETE: immediate return from hyppo write, because they never take >1 40MHz clock cycle";
              transaction_complete_toggle <= transaction_request_toggle;
              
              -- Either way, request the data be written
              hyppo_write_request_toggle <= not hyppo_write_request_toggle;
              hyppo_write_addr <= to_integer(transaction_address(13 downto 0));
              hyppo_write_data <= transaction_wdata;
              hyppo_write_bytecount <= transaction_length;
            else
              -- Reading from chip/fast RAM.
              
              -- Remember that we have accepted the job
              last_transaction_request_toggle <= transaction_request_toggle;
              
              -- Schedule read
              hyppo_read_request_toggle <= not hyppo_read_request_toggle;
              hyppo_read_addr <= to_integer(transaction_address(13 downto 0));
              hyppo_read_bytecount <= transaction_length;
              hyppo_rdata_buffer <= to_unsigned(0,48);
              hyppo_background_read <= '0';
            end if;
            
          elsif transaction_address(19 downto 12) = x"fe" then
            -- Charrom write
            charrom_write_cs <= transaction_write;
          elsif ((transaction_address(19 downto 14)&"00"&transaction_address(11 downto 10)&"00") = x"d00")
            and (transaction_address(11 downto 7) /= "000001")
          then
            -- VIC-IV fastio
            report "is VIC-IV access";
            src_is_viciv <= '1';
          else
            -- General fastio access
            report "general fastio access";
            src_is_viciv <= '0';
            src_is_colourram <= '0';
          
            -- Schedule read/write via fastio bus or variant
            if transaction_write = '1' then
              report "fastio write request toggled from " & std_logic'image(fastio_write_request_toggle)
                & " to " & std_logic'image(not fastio_write_request_toggle);
              fastio_write_request_toggle <= not fastio_write_request_toggle;
            -- XXX For single byte reads, we can probably do this asynchronously.
            -- XXX Better, we can do ALL fastio writes asynch, even if multi-byte,
            -- and just have a flag to the CPU that indicates that we are still
            -- busy.  Or we implement some kind of queue.  But for now, we will
            -- just do it all synchronously.
            else
              report "fastio read request toggled";
              fastio_read_request_toggle <= not fastio_read_request_toggle;
            end if;
            fastio_next_address_new <= transaction_address(19 downto 0);
            fastio_write_data_vector_new <= transaction_wdata;
            fastio_write_bytecount <= transaction_length;
            fastio_read_bytecount <= transaction_length;
            fastio_read_position <= 7;
          end if;
        elsif transaction_address(27 downto 26) /= "00" then
          -- Slow devices range
          report "slowdev request";
          
          -- Remember that we have accepted the job
          last_transaction_request_toggle <= transaction_request_toggle;
          
          -- Schedule read or write
          slowdev_next_address_new <= transaction_address;
          if transaction_write='0' then
            report "requesting slowdev read";
            slowdev_read_request_toggle <= not slowdev_read_request_toggle;
            slowdev_read_bytecount <= transaction_length;
            -- Mark reading as not yet having a byte scheduled for reading
            slowdev_access_read_position <= 7;
          else
            report "requesting slowdev write";
            slowdev_write_request_toggle <= not slowdev_write_request_toggle;
            slowdev_write_data_vector_new <= transaction_wdata;
            slowdev_write_bytecount <= transaction_length;
          end if;
          
        end if;
      end if;

      -- Notice when the read is complete, and tell the CPU
      if fastram_read_complete_toggle /= last_fastram_read_complete_toggle then
        report "return read data to CPU";
        last_fastram_read_complete_toggle <= fastram_read_complete_toggle;
        if fastram_background_read = '0' then
          report "COMPLETE: marking complete due to fastram read";
          transaction_complete_toggle <= transaction_request_toggle;
          transaction_rdata <= fastram_rdata_buffer;
        else
          -- We have some instruction bytes, do something useful with them.
        end if;
        fastram_job_end_token <= 32;
      end if;
      if hyppo_read_complete_toggle /= last_hyppo_read_complete_toggle then
        report "return HYPPO RAM read data to CPU: $" & to_hstring(hyppo_rdata_buffer);
        last_hyppo_read_complete_toggle <= hyppo_read_complete_toggle;
        if hyppo_background_read = '0' then
          report "COMPLETE: marking complete due to hyppo read";
          transaction_complete_toggle <= transaction_request_toggle;
          transaction_rdata <= hyppo_rdata_buffer;
        else
          -- We have some instruction bytes, do something useful with them.
        end if;
        hyppo_job_end_token <= 32;
      end if;

      -- Notice when the slowdev read or write is complete, and tell the CPU
      if slowdev_read_complete_toggle /= last_slowdev_read_complete_toggle then
        report "COMPLETE: return read data from slowdev to CPU";
        last_slowdev_read_complete_toggle <= slowdev_read_complete_toggle;
        transaction_complete_toggle <= transaction_request_toggle;
        transaction_rdata <= slowdev_rdata_buffer;
      end if;
      if slowdev_write_complete_toggle /= last_slowdev_write_complete_toggle then
        report "COMPLETE: slowdev write complete";
        last_slowdev_write_complete_toggle <= slowdev_write_complete_toggle;
        transaction_complete_toggle <= transaction_request_toggle;
      end if;

      -- Notice when the fastio read or write is complete, and tell the CPU
      if fastio_read_complete_toggle /= last_fastio_read_complete_toggle then
        report "COMPLETE: return read data from fastio to CPU";
        last_fastio_read_complete_toggle <= fastio_read_complete_toggle;
        transaction_complete_toggle <= transaction_request_toggle;
        transaction_rdata <= fastio_rdata_buffer;
      end if;
      if fastio_write_complete_toggle /= last_fastio_write_complete_toggle then
        report "COMPLETE: fastio write complete";
        last_fastio_write_complete_toggle <= fastio_write_complete_toggle;
        transaction_complete_toggle <= transaction_request_toggle;
      end if;

      -- Latch instruction fetch buffer
      if last_fastram_next_instruction_loaded_toggle /= fastram_next_instruction_loaded_toggle then
        last_fastram_next_instruction_loaded_toggle <= fastram_next_instruction_loaded_toggle;
        report "ifetch latched instruction data @ $" & to_hstring(to_unsigned(ifetch_buffer162_addr,20))
          & " = $" & to_hstring(ifetch_buffer162);
      end if;
      -- Check instruction fetch buffer to see if it has content we need.
      if ifetch_buffer162_addr = instruction_fetch_address_in_drive then
        -- We have exactly the instruction we need, so present it, and reset
        -- the instruction fetch buffer
        report "ifetch has delivered the instruction we need. Storing and returning to CPU";
        instruction_fetched_address_out_drive <= ifetch_buffer162_addr;
        instruction_fetched_rdata_drive <= ifetch_buffer162;
        ifetch_buffer(47 downto 0) <= ifetch_buffer162;
        ifetch_buffer_byte_count <= 6;
        ifetch_buffer_addr <= ifetch_buffer162_addr;
      else
        -- Update the ifetch buffer.
        -- To simplify the logic, we alternate between shifting and storing
        -- newly arrived data

        report "ifetch_buffer162_addr=$" & to_hstring(to_unsigned(ifetch_buffer162_addr,20));

        -- Check if we already have the right data
        if ifetch_buffer_addr = instruction_fetch_address_in_drive and (ifetch_buffer_byte_count > 5) then
          -- We have exactly the instruction we need, so present it, and reset
          -- the instruction fetch buffer
          report "ifetch has delivered the instruction we need. Storing and returning to CPU";
          instruction_fetched_address_out_drive <= ifetch_buffer_addr;
          instruction_fetched_rdata_drive <= ifetch_buffer(47 downto 0);
          -- Check if we can store the newly read bytes
        end if;
        if ifetch_buffer162_addr = (ifetch_buffer_addr + ifetch_buffer_byte_count)
          and ifetch_buffer_byte_count <= (16 - 6) then
          ifetch_buffer((47 + ifetch_buffer_byte_count * 8) downto (ifetch_buffer_byte_count * 8))
            <= ifetch_buffer162;
          ifetch_buffer_byte_count <= ifetch_buffer_byte_count + 6;
          report "Added 6 more instruction bytes to ifetch buffer. We now have "
            & integer'image(ifetch_buffer_byte_count + 6)
            & " byte in the buffer.";
          -- Check if we should shuffle down
        elsif (ifetch_buffer_addr < instruction_fetch_address_in_drive)
          and (instruction_fetch_address_in_drive - ifetch_buffer_addr) < ifetch_buffer_byte_count
          and (instruction_fetch_address_in_drive - ifetch_buffer_addr) < 7 then
          -- Shift down
          ifetch_buffer_addr <= instruction_fetch_address_in_drive;
          case (instruction_fetch_address_in_drive - ifetch_buffer_addr) is
            when 1 => ifetch_buffer(119 downto 0) <= ifetch_buffer(127 downto 8);
                      ifetch_buffer_byte_count <= ifetch_buffer_byte_count - 1;
            when 2 => ifetch_buffer(111 downto 0) <= ifetch_buffer(127 downto 16);
                      ifetch_buffer_byte_count <= ifetch_buffer_byte_count - 2;
            when 3 => ifetch_buffer(103 downto 0) <= ifetch_buffer(127 downto 24);
                      ifetch_buffer_byte_count <= ifetch_buffer_byte_count - 3;
            when 4 => ifetch_buffer( 95 downto 0) <= ifetch_buffer(127 downto 32);
                      ifetch_buffer_byte_count <= ifetch_buffer_byte_count - 4;
            when 5 => ifetch_buffer( 87 downto 0) <= ifetch_buffer(127 downto 40);
                      ifetch_buffer_byte_count <= ifetch_buffer_byte_count - 5;
            when 6 => ifetch_buffer( 79 downto 0) <= ifetch_buffer(127 downto 48);
                      ifetch_buffer_byte_count <= ifetch_buffer_byte_count - 6;
            when others =>
              null;
          end case;
          report "Shuffling instruction fetch buffer down by "
            & integer'image(instruction_fetch_address_in_drive - ifetch_buffer_addr)
            & " bytes. Remaining bytes = "
            & integer'image(ifetch_buffer_byte_count - (instruction_fetch_address_in_drive - ifetch_buffer_addr));
        else

        end if;
      end if;

    end if;
    if rising_edge(cpuclock8x) then
      -- BRAM is on pipelined 8x clock (324MHz)
      -- This is about as fast as we can clock BRAM in these FPGAs,
      -- and requires a lot of pipelining. The end result is still about
      -- the same latency as driving it at 40MHz, but with better throughput
      -- and actually meeting timing closure

      latch_ifetch_buffer324 <= '0';
      if latch_ifetch_buffer324 = '1' then
        ifetch_buffer162 <= ifetch_buffer324;
      end if;
      fastram_next_instruction_address <= fastram_next_instruction_address;
      fastram_next_instruction_position <= fastram_next_instruction_position;
      fastram_next_instruction_address_plus_one <= fastram_next_instruction_address + 1;
      fastram_next_instruction_address_plus_two <= fastram_next_instruction_address + 2;
      if fastram_next_instruction_position < 5 then
        fastram_next_instruction_position_plus_one <= fastram_next_instruction_position + 1;
      else
        fastram_next_instruction_position_plus_one <= 0;
      end if;
      if fastram_next_instruction_position < 4 then
        fastram_next_instruction_position_plus_two <= fastram_next_instruction_position + 2;
      else
        fastram_next_instruction_position_plus_two <= fastram_next_instruction_position - 4;
      end if;

      -- Update fast RAM pipeline stages
      for i in 1 to 8 loop
        fastram_iface(i) <= fastram_iface(i-1);
      end loop;
      -- And reflect token ID through the pipeline for pickup
      fastram_iface(0).token_return <= fastram_iface(fastram_pipeline_depth).token;
      -- XXX The following is because GHDL was doing weird things with having
      -- iface(0).rdata directly attached to the fastram
      fastram_iface(1).rdata <= fastram_rdata;
      -- And also the instruction fetch info
      fastram_iface(0).is_ifetch_return <= fastram_iface(fastram_pipeline_depth).is_ifetch;
      fastram_iface(0).addr_return <= fastram_iface(fastram_pipeline_depth).addr;

      -- By default idle the fast/chip RAM interface
      fastram_iface(0).addr <= 0;
      fastram_iface(0).we <= '0';
      fastram_iface(0).wdata <= x"00";
      fastram_iface(0).is_ifetch <= '0';
      -- And keep cycling the token IDs so that we can easily collect results
      -- at the other end
      fastram_iface(0).token <= next_token;
      next_token <= next_token + 1;
      fastram_read_byte_position <= 0;

      if fastram_write_now='1' or fastram_read_now='1' then
        fastram_next_address <= fastram_next_address + 1;
      else
        -- If nothing else to do, then fetch the next byte in the instruction stream
        -- Prepare other signals for doing background instruction fetches
--        report "idle cycle instruction prefetch from $" & to_hstring(to_unsigned(fastram_next_ifetch_address,20));
        fastram_iface(0).addr <= fastram_next_ifetch_address;
        fastram_iface(0).is_ifetch <= '1';
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
        report "fastram_read_now asserted";
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
        fastram_read_tokens(fastram_read_byte_position) <= to_integer(next_token);
        fastram_read_byte_position <= fastram_read_byte_position + 1;

      end if;

      -- Do we have a new write request to fastram?
      if fastram_write_request_toggle /= last_fastram_write_request_toggle then
        report "accepting fastio_write_request_toggle";
        last_fastram_write_request_toggle <= fastram_write_request_toggle;
        fastram_write_bytes_remaining <= fastram_write_bytecount;
        fastram_next_address <= fastram_write_addr;
        fastram_write_data_vector <= fastram_write_data;
        fastram_write_now <= '1';
      end if;

      -- Or read request to fastram
      if fastram_read_request_toggle /= last_fastram_read_request_toggle then
        last_fastram_read_request_toggle <= fastram_read_request_toggle;
        fastram_read_bytes_remaining <= fastram_read_bytecount;
        fastram_next_address <= fastram_read_addr;
        fastram_read_now <= '1';
        fastram_read_byte_position <= 0;
        -- Set end of job token initially to be invalid.
        -- It will get updated with the correct value when the read job is underway
        fastram_job_end_token <= 32; -- only tokens 0 -- 31 exist
      end if;
      for i in 0 to 5 loop
        if to_integer(fastram_iface(fastram_pipeline_depth).token_return) = fastram_read_tokens(i) then
          -- We have read a byte we are waiting for
          fastram_rdata_buffer(i*8 + 7 downto i*8) <= fastram_iface(fastram_pipeline_depth).rdata;
--          report "stashing byte $" & to_hstring(fastram_iface(fastram_pipeline_depth).rdata) & " into byte " & integer'image(i);
        end if;
      end loop;
      if to_integer(fastram_iface(fastram_pipeline_depth).token_return) = fastram_job_end_token then
        -- This was the last byte we needed to read, so we can tell the slower
        -- interface to collect and present the result back to the CPU
        fastram_read_complete_toggle <= not fastram_read_complete_toggle;
        report "end of fastram read request reached";
      end if;

      -- Is this byte the next byte of the instruction stream that we need?
--      report "addr_return=$" & to_hstring(to_unsigned(fastram_iface(fastram_pipeline_depth).addr_return,20))
--        & ", fastram_next_instruction_address=$" & to_hstring(to_unsigned(fastram_next_instruction_address,20));

      if fastram_iface(fastram_pipeline_depth).addr_return = fastram_next_instruction_address then
--        report "We just read the next instruction stream byte we need";
--        report "addr+1 = $" & to_hstring(to_unsigned(fastram_next_instruction_address_plus_one,20));
--        report "position+1 = " & integer'image(fastram_next_instruction_position_plus_one);
        if fastram_next_instruction_store = '1' then
          fastram_next_instruction_address <= fastram_next_instruction_address_plus_two;
          fastram_next_instruction_position <= fastram_next_instruction_position_plus_two;
        else
          fastram_next_instruction_address <= fastram_next_instruction_address_plus_one;
          fastram_next_instruction_position <= fastram_next_instruction_position_plus_one;
        end if;
        if fastram_next_instruction_store_position = 5 then
          fastram_next_instruction_loaded_toggle <= not fastram_next_instruction_loaded_toggle;
          latch_ifetch_buffer324 <= '1';
          -- Adjust address for length of the fetch buffer
          ifetch_buffer162_addr <= ifetch_buffer162_addr_drive - 5;
        end if;

        -- Note when we have filled the low-level instruction fetch buffer
        if fastram_next_instruction_store_position < 6 then
          fastram_next_instruction_store <= '1';
        else
          fastram_next_instruction_store <= '0';
        end if;
      else
        fastram_next_instruction_store <= '0';
      end if;
      fastram_next_instruction_store_position <= fastram_next_instruction_position;
      if fastram_next_instruction_store='1' then
        report "Storing byte $" & to_hstring(fastram_iface(fastram_pipeline_depth).rdata)
          & " into ifetch_buffer324(" & integer'image(fastram_next_instruction_store_position) & ").";
        ifetch_buffer324(47 downto 40) <= fastram_iface(fastram_pipeline_depth).rdata;
        ifetch_buffer324(39 downto 0) <= ifetch_buffer324(47 downto 8);
        ifetch_buffer324_byte_count <= fastram_next_instruction_store_position;
        ifetch_buffer162_addr_drive <= fastram_iface(fastram_pipeline_depth).addr_return;
      else
        ifetch_buffer324 <= ifetch_buffer324;
      end if;

      -- Begin fetching next instruction if requested.
      -- We assume that if waiting for an instruction that no other memory accesses
      -- are going on, and thus that we can have shallower logic for the next_ifetch_address
      -- logic, by just having it always increment. This could come unstuck if
      -- a write is still happening in the background, in which case we should
      -- check if that is happening.
      if instruction_fetch_request_toggle_drive /= last_instruction_fetch_request_toggle then
        last_instruction_fetch_request_toggle <= instruction_fetch_request_toggle_drive;
        report "instruction_fetch_address_in_drive = " & integer'image(instruction_fetch_address_in_drive);
        fastram_next_ifetch_address <= instruction_fetch_address_in_drive;
        fastram_next_instruction_address <= instruction_fetch_address_in_drive;
        fastram_next_instruction_position <= 0;
      else
        if fastram_read_now='0' and fastram_write_now='0' then
          -- Advance address is nothing else is happening
          fastram_next_ifetch_address <= fastram_next_ifetch_address + 1;
        else
          fastram_next_ifetch_address <= fastram_next_ifetch_address;
        end if;
      end if;


      ------------------------------------------------------------------------------------------
      -- HYPPO RAM state machine
      ------------------------------------------------------------------------------------------
      
      -- Update fast RAM pipeline stages
      for i in 1 to 8 loop
        hyppo_iface(i) <= hyppo_iface(i-1);
      end loop;
      -- And reflect token ID through the pipeline for pickup
      hyppo_iface(0).token_return <= hyppo_iface(hyppo_pipeline_depth).token;
      -- XXX The following is because GHDL was doing weird things with having
      -- iface(0).rdata directly attached to the fastram
      hyppo_iface(1).rdata <= hyppo_rdata;
      -- And also the instruction fetch info
      hyppo_iface(0).is_ifetch_return <= hyppo_iface(hyppo_pipeline_depth).is_ifetch;
      hyppo_iface(0).addr_return <= hyppo_iface(hyppo_pipeline_depth).addr;

      -- By default idle the fast/chip RAM interface
      hyppo_iface(0).addr <= 0;
      hyppo_iface(0).we <= '0';
      hyppo_iface(0).wdata <= x"00";
      hyppo_iface(0).is_ifetch <= '0';
      -- And keep cycling the token IDs so that we can easily collect results
      -- at the other end
      hyppo_iface(0).token <= next_token;
      hyppo_read_byte_position <= 0;

      if hyppo_write_now='1' or hyppo_read_now='1' then
        hyppo_next_address <= hyppo_next_address + 1;
      else
        -- If nothing else to do, then fetch the next byte in the instruction stream
        -- Prepare other signals for doing background instruction fetches
--        report "idle cycle instruction prefetch from $" & to_hstring(to_unsigned(hyppo_next_ifetch_address,20));
        hyppo_iface(0).addr <= hyppo_next_ifetch_address;
        hyppo_iface(0).is_ifetch <= '1';
      end if;

      -- If we are writing to hyppo ram, write out the queued bytes
      if hyppo_write_now='1' then
        hyppo_iface(0).addr <= hyppo_next_address;
        hyppo_iface(0).we <= '1';
        hyppo_iface(0).wdata <= hyppo_write_data_vector(7 downto 0);

        -- Get ready for writing the next byte
        hyppo_write_bytes_remaining <= hyppo_write_bytes_remaining - 1;
        if hyppo_write_bytes_remaining = 1 then
          hyppo_write_now <= '0';
        else
          hyppo_write_now <= '1';
        end if;
        hyppo_write_data_vector(23 downto 0) <= hyppo_write_data_vector(31 downto 8);
      end if;

      if hyppo_read_now='1' then
        report "hyppo_read_now asserted";
        hyppo_iface(0).addr <= hyppo_next_address;
        hyppo_read_bytes_remaining <= hyppo_read_bytes_remaining - 1;
        if hyppo_read_bytes_remaining = 1 then
          hyppo_read_now <= '0';
          -- Note which token will mark the end of the read job
          hyppo_job_end_token <= to_integer(next_token);
        else
          hyppo_read_now <= '1';
        end if;
        -- Note the token ID and where it needs to go
        hyppo_read_tokens(hyppo_read_byte_position) <= to_integer(next_token);
        hyppo_read_byte_position <= hyppo_read_byte_position + 1;

      end if;

      -- Do we have a new write request to hyppo?
      if hyppo_write_request_toggle /= last_hyppo_write_request_toggle then
        report "accepting fastio_write_request_toggle";
        last_hyppo_write_request_toggle <= hyppo_write_request_toggle;
        hyppo_write_bytes_remaining <= hyppo_write_bytecount;
        hyppo_next_address <= hyppo_write_addr;
        hyppo_write_data_vector <= hyppo_write_data;
        hyppo_write_now <= '1';
      end if;

      -- Or read request to hyppo
      if hyppo_read_request_toggle /= last_hyppo_read_request_toggle then
        last_hyppo_read_request_toggle <= hyppo_read_request_toggle;
        hyppo_read_bytes_remaining <= hyppo_read_bytecount;
        hyppo_next_address <= hyppo_read_addr;
        hyppo_read_now <= '1';
        hyppo_read_byte_position <= 0;
        -- Set end of job token initially to be invalid.
        -- It will get updated with the correct value when the read job is underway
        hyppo_job_end_token <= 32; -- only tokens 0 -- 31 exist
      end if;
      for i in 0 to 5 loop
        if to_integer(hyppo_iface(hyppo_pipeline_depth).token_return) = hyppo_read_tokens(i) then
          -- We have read a byte we are waiting for
          hyppo_rdata_buffer(i*8 + 7 downto i*8) <= hyppo_iface(hyppo_pipeline_depth).rdata;
         report "stashing hyppo byte $" & to_hstring(hyppo_iface(hyppo_pipeline_depth).rdata) & " into byte " & integer'image(i);
        end if;
      end loop;
      if to_integer(hyppo_iface(hyppo_pipeline_depth).token_return) = hyppo_job_end_token then
        -- This was the last byte we needed to read, so we can tell the slower
        -- interface to collect and present the result back to the CPU
        hyppo_read_complete_toggle <= not hyppo_read_complete_toggle;
        report "end of hyppo read request reached";
      end if;
      
    end if;

  end process;




end edwardian;
