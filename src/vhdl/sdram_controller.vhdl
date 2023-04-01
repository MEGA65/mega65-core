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
         clock163 : in std_logic; -- Used for fast clock for HyperRAM

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
         busy : out std_logic := '0';

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

         sdram_address : out unsigned(23 downto 0);
         sdram_wdata : out std_logic_vector(15 downto 0);
         sdram_we : out std_logic;
         sdram_req : out std_logic;
         sdram_ack : out std_logic;
         sdram_valid : in std_logic;
         sdram_rdata : in std_logic_vector(15 downto 0)
         
         );
end sdram_controller;

architecture tacoma_narrows of sdram_controller is

begin  
  
end tacoma_narrows;
