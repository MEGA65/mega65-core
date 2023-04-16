library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

------------------------------------------------------------------------------------------------
-- PGS 12MAR2023:
-- NOTE: The cache must remain enabled for writes to be reliable across all
-- MEGA65 board revisions.  This is because the revD HyperRAM chip found on
-- _some_ machines in _some_ batches requires 32-bit writes (but still can be
-- byte masked), for the writes to happen correctly.
-- See https://github.com/MJoergen/HyperRAM/issues/2 for more information.
------------------------------------------------------------------------------------------------


entity sdram_controller is
  generic ( in_simulation : in boolean := false);
  Port ( pixelclock : in STD_LOGIC; -- For slow devices bus interface is
         -- actually on pixelclock to reduce latencies
         -- Also pixelclock is the natural clock speed we apply to the HyperRAM.
         clock162 : in std_logic; -- Used for fast clock for HyperRAM

         -- Option to ignore 100usec initialisation sequence for SDRAM (to
         -- speed up simulation)
         enforce_100us_delay : in boolean := true;
         
         -- Simple counter for number of requests received
         request_counter : out std_logic := '0';
         
         read_request : in std_logic;
         write_request : in std_logic;
         address : in unsigned(26 downto 0);
         wdata : in unsigned(7 downto 0);

         -- Optional 16-bit interface (for Amiga core use)
         -- (That it is optional, is why the write_en is inverted for the
         -- low-byte).
         -- 16-bit transactions MUST occur on an even numbered address, or
         -- else expect odd and horrible things to happen.
         wdata_hi : in unsigned(7 downto 0) := x"00";
         wen_hi : in std_logic := '0';            
         wen_lo : in std_logic := '1';
         rdata_hi : out unsigned(7 downto 0);
         rdata_16en : in std_logic := '0';         -- set this high to be able
                                                   -- to read 16-bit values
         
         rdata : out unsigned(7 downto 0);
         
         data_ready_strobe : out std_logic := '0';

         -- Starts busy until SDRAM is initialised
         busy : out std_logic := '1';

         -- Export current cache line for speeding up reads from slow_devices controller
         -- by skipping the need to hand us the request and get the response back.
         current_cache_line : out cache_row_t := (others => (others => '0'));
         current_cache_line_address : inout unsigned(26 downto 3) := (others => '0');
         current_cache_line_valid : out std_logic := '0';
         expansionram_current_cache_line_next_toggle : in std_logic := '0';

         -- Allow VIC-IV to request lines of data also.
         -- We then pump it out byte-by-byte when ready
         -- VIC-IV can address only 512KB at a time, so we have a banking register
         viciv_addr : in unsigned(18 downto 3) := (others => '0');
         viciv_request_toggle : in std_logic := '0';
         viciv_data_out : out unsigned(7 downto 0) := x"00";
         viciv_data_strobe : out std_logic := '0';

         -- SDRAM interface (e.g. AS4C16M16SA-6TCN, IS42S16400F, etc.)
         sdram_a     : out unsigned(12 downto 0);
         sdram_ba    : out unsigned(1 downto 0);
         sdram_dq    : inout unsigned(15 downto 0);
         sdram_cke   : out std_logic := '1';
         sdram_cs_n  : out std_logic := '0';
         sdram_ras_n : out std_logic;
         sdram_cas_n : out std_logic;
         sdram_we_n  : out std_logic;
         sdram_dqml  : out std_logic;
         sdram_dqmh  : out std_logic
         
         );
end sdram_controller;

architecture tacoma_narrows of sdram_controller is

  -- The SDRAM requires a 100us setup time
  signal sdram_prepped : std_logic := '0';  
  signal sdram_100us_countdown : integer := 16_200;
  signal sdram_do_init : std_logic := '0';
  signal sdram_init_phase : integer range 0 to 63 := 0;

  type sdram_cmd_t is (CMD_NOP, CMD_SET_MODE_REG,
                       CMD_PRECHARGE,
                       CMD_AUTO_REFRESH,
                       CMD_ACTIVATE_ROW,
                       CMD_READ,
                       CMD_WRITE,
                       CMD_STOP
                       );

  -- Initialisation sequence required for SDRAM according to
  -- the "INITIALIZE AND LOAD MODE REGISTER" section of the
  -- datasheet.
  type sdram_init_t is array (0 to 31) of sdram_cmd_t;
  signal init_cmds : sdram_init_t := (
    2 => CMD_PRECHARGE,
    6 => CMD_AUTO_REFRESH,
    16 => CMD_AUTO_REFRESH,
    26 => CMD_SET_MODE_REG,
    others => CMD_NOP);
  
begin  

  rdata <= (others => 'Z');

  process(clock162,pixelclock) is
    procedure sdram_emit_command(cmd : sdram_cmd_t) is
    begin
      case cmd is
        when CMD_SET_MODE_REG =>
          sdram_ras_n <= '0';
          sdram_cas_n <= '0';
          sdram_we_n <= '0';
        when CMD_PRECHARGE =>
          sdram_ras_n <= '0';
          sdram_cas_n <= '1';
          sdram_we_n <= '0';
          sdram_a(10) <= '1';
        when CMD_AUTO_REFRESH =>
          sdram_ras_n <= '0';
          sdram_cas_n <= '0';
          sdram_we_n <= '1';
        when CMD_ACTIVATE_ROW =>
          -- sdram_ba=BANK and sdram_a=ROW
          sdram_ras_n <= '0';
          sdram_cas_n <= '1';
          sdram_we_n <= '1';
        when CMD_READ =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '0';
          sdram_we_n <= '1';
        when CMD_WRITE =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '0';
          sdram_we_n <= '0';
        when CMD_STOP =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '1';
          sdram_we_n <= '0';
        when CMD_NOP =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '1';
          sdram_we_n <= '1';
        when others =>
          sdram_ras_n <= '1';
          sdram_cas_n <= '1';
          sdram_we_n <= '1';
      end case;
    end procedure;
    
  begin
    if rising_edge(clock162) then

      if read_request='1' or write_request='1' then
        busy <= '1';
      end if;
      
      -- Manage the 100usec SDRAM initialisation delay, if enabled
      if sdram_100us_countdown /= 0 then
        sdram_100us_countdown <= sdram_100us_countdown - 1;
      end if;
      if sdram_100us_countdown = 1 then
        report "SDRAM: Starting init sequence after 100usec delay";
        sdram_do_init <= not sdram_prepped;
      end if;
      if enforce_100us_delay = false then
        report "SDRAM: Skipping 100usec init delay";
        sdram_do_init <= not sdram_prepped;
      end if;
      -- And the complete SDRAM initialisation sequence
      if sdram_init_phase = 0 and sdram_do_init='1' then
        report "SDRAM: Starting SDRAM initialisation sequence";
        sdram_init_phase <= 1;
      end if;
      if sdram_prepped='0' then
        if sdram_init_phase /= 0 then
          report "EMIT init phase " & integer'image(sdram_init_phase) & " command "
            & sdram_cmd_t'image(init_cmds(sdram_init_phase));
        end if;

        -- Clear reserved bits for mode register
        sdram_ba <= (others => '0');
        sdram_a(12 downto 10) <= (others => '0');
        -- write burst length = 1
        sdram_a(9) <= '1';
        -- Normal mode of operation
        sdram_a(8 downto 7) <= (others => '0');
        -- CAS latency = 3, for 167MHz operation
        sdram_a(6 downto 4) <= to_unsigned(3,3);
        -- Non-interleaved burst order
        sdram_a(3) <= '0';
        -- Read burst length = 8
        sdram_a(2 downto 0) <= to_unsigned(3,3);        

        -- Emit the sequence of commands
        -- MUST BE DONE AFTER SETTING sdram_a
        -- (so that A10 can be set for the PRECHARGE_ALL command,
        --  but stay clear for all the rest)
        sdram_emit_command(init_cmds(sdram_init_phase));
        
        if sdram_init_phase = 31 then
          sdram_prepped <= '1';
          busy <= '0';
          report "SDRAM: Clearing BUSY at end of initialisation sequence";
        elsif sdram_init_phase /= 0 then
          sdram_init_phase <= sdram_init_phase + 1;
        end if;
      else
      end if;
      
    end if;
  end process;
  
end tacoma_narrows;
