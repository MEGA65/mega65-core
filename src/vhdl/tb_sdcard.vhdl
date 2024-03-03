library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_sdcard is
  generic (runner_cfg : string);
end entity;

architecture test_arch of tb_sdcard is

  signal pixelclock : std_logic := '0';
  signal clock41 : std_logic := '0';
  signal clock162 : std_logic := '0';

  signal reset : std_logic := '0';
  
  signal fastio_addr : unsigned(19 downto 0);
  signal fastio_wdata : unsigned(7 downto 0);
  signal fastio_rdata : unsigned(7 downto 0);
  signal fastio_read : std_logic := '0';
  signal fastio_write : std_logic := '0';
  signal sdcardio_cs : std_logic := '0';
  signal sector_cs : std_logic := '0';
  signal sector_cs_fast : std_logic := '0';
  signal sd_bus_number : std_logic := '0';
  signal cs_bo : std_logic := '0';
  signal sclk_o : std_logic := '0';
  signal mosi_o : std_logic := '0';
  signal miso_i : std_logic := '0';

  signal dummy_tmpSDA : std_logic := '0';
  signal dummy_tmpSCL : std_logic := '0';
  signal dummy_i2c1SDA : std_logic := '0';
  signal dummy_i2c1SCL : std_logic := '0';
  signal dummy_touchSDA : std_logic := '0';
  signal dummy_touchSCL : std_logic := '0';

  constant sector_slot_count : integer := 1024;
  type sector_buffer_t is array(0 to 511) of unsigned(7 downto 0);
  type sector_slot_buffer_t is array(0 to (sector_slot_count-1)) of sector_buffer_t;
  type sector_list_t is array(0 to (sector_slot_count-1)) of integer;
  signal sector_slots : sector_slot_buffer_t := (others => (others => x"00"));
  signal sector_numbers : sector_list_t := (others => 999999999);
  signal sector_count : integer := 0;
  
begin

  sdcard0: entity work.sdcard_model
    port map ( clock => clock41,
               cs_bo => cs_bo,
               sclk_o => sclk_o,
               mosi_o => mosi_o,
               miso_i => miso_i
               );
  
  sdcard_controller0: entity work.sdcardio
  generic map ( target => simulation,
                cpu_frequency => 40_500_000,
                cache_size => 128 )  -- 128 sectors = 64KB
    port map ( clock => clock41,
               pixelclk => pixelclock,
               reset => reset,

               -------------------------------------------------------------------------
               -- Fastio register access interface
               -------------------------------------------------------------------------
               fastio_addr => fastio_addr,
               fastio_addr_fast => fastio_addr,
               fastio_write => fastio_write,
               fastio_read => fastio_read,
               fastio_wdata => fastio_wdata,
               fastio_rdata_sel => fastio_rdata,

               sdcardio_cs => sdcardio_cs,
               colourram_at_dc00 => '0',
               viciii_iomode => "11",
               sectorbuffercs => sector_cs,
               sectorbuffercs_fast => sector_cs_fast,
               
               -------------------------------------------------------------------------
               -- Lines for the SDcard interface itself
               -------------------------------------------------------------------------
               sd_interface_select => sd_bus_number,
               cs_bo => cs_bo,
               sclk_o => sclk_o,
               mosi_o => mosi_o,
               miso_i => miso_i,

               -------------------------------------------------------------------------
               -- Other inputs to sdcardio.vhdl that are not relevant
               -------------------------------------------------------------------------
               f011_cs => '0',
               hw_errata_disable_toggle => '0',
               hw_errata_enable_toggle => '0',
               audio_loopback => (others => '0'),
               hypervisor_mode => '0',
               secure_mode => '0',
               fpga_temperature => (others => '0'),
               pwm_knob => (others => '0'),
               virtualise_f011_drive0 => '0',
               virtualise_f011_drive1 => '0',
               last_scan_code => (others => '0'),
               dipsw_hi => (others => '0'),
               dipsw => (others => '0'),
               j21in => (others => '0'),
               sw => (others => '0'),
               btn => (others => '0'),
               f_index  => '0',
               f_track0  => '0',
               f_writeprotect  => '0',
               f_rdata  => '0',
               f_diskchanged => '0',
               sd1541_request_toggle  => '0',
               sd1541_enable  => '0',
               sd1541_track => (others => '0'),
               aclMISO  => '0',
               aclInt1  => '0',
               aclInt2  => '0',
               tmpSDA  => dummy_tmpSDA,
               tmpSCL  => dummy_tmpSCL,
               tmpInt  => '0',
               tmpCT  => '0',
               i2c1SDA  => dummy_i2c1SDA,
               i2c1SCL  => dummy_i2c1SCL,
               touchSDA  => dummy_touchSDA,
               touchSCL  => dummy_touchSCL,
               QspiDB_in => x"0"
    );


  main : process

    variable v : unsigned(15 downto 0);

    procedure clock_tick is
    begin
      clock162 <= not clock162;
      if clock162 = '1' then
        pixelclock <= not pixelclock;
        if pixelclock='1' then
          clock41 <= not clock41;
        end if;
      end if;
      wait for 6.173 ns;

    end procedure;

    procedure POKE(addr : unsigned(15 downto 0); data : unsigned(7 downto 0)) is
    begin
      sdcardio_cs <= '1';
      fastio_addr(11 downto 0) <= addr(11 downto 0);
      fastio_addr(19 downto 12) <= x"d3";
      fastio_wdata <= data;
      fastio_write <= '1';
      fastio_read <= '0';
      -- Wait one full 41MHz clock tick
      for i in 1 to 8 loop
        clock_tick;
      end loop;
      fastio_write <= '0';
      sdcardio_cs <= '0';
      
    end procedure;
    
    procedure PEEK(addr : unsigned(15 downto 0) ) is
    begin
      sdcardio_cs <= '1';
      fastio_addr(11 downto 0) <= addr(11 downto 0);
      fastio_addr(19 downto 12) <= x"d3";
      fastio_write <= '0';
      fastio_read <= '1';
      -- Wait two full 41MHz clock ticks to make sure any latency is
      -- accomodated when reading BRAMs
      for i in 1 to 8 loop
        clock_tick;
      end loop;
      fastio_read <= '0';
      sdcardio_cs <= '0';
      -- return fastio_rdata;
      
    end procedure;

    procedure sdcard_read_sector(sector : integer) is
    begin
      POKE(x"D681",to_unsigned(sector,32)(7 downto 0));
      POKE(x"D681",to_unsigned(sector,32)(15 downto 8));
      POKE(x"D681",to_unsigned(sector,32)(23 downto 16));
      POKE(x"D681",to_unsigned(sector,32)(31 downto 24));
      POKE(x"D680",x"02"); -- Read single sector
      for i in 1 to 1000 loop
        PEEK(x"D680");
        if fastio_rdata(1 downto 0) = "00" then
          report "SD card READY following READ SECTOR after " & integer'image(i) & " read cycles.";
          exit;
        end if;
      end loop;
      if fastio_rdata(1 downto 0) /= "00" then
        assert false report "SD card reported error (or had not responded) following request to read single sector " & integer'image(sector);
      end if;
    end procedure;
    
    procedure sdcard_reset_sequence is
    begin
      -- This sequence will cause sdcard.vhdl to begin its initialisation sequence.
      
      POKE(x"D680",x"00"); -- assert RESET
      POKE(x"D680",x"01"); -- release RESET
      
      for i in 1 to 100000 loop
        PEEK(x"D680");
        if fastio_rdata(1 downto 0) = "00" then
          report "SD card reported READY after " & integer'image(i) & " cycles.";
          exit;
        end if;
      end loop;
      if fastio_rdata(1 downto 0) /= "00" then
        report "SD card was not READY following reset: sdcard_busy="
          & std_logic'image(fastio_rdata(1)) & ", sdio_busy=" & std_logic'image(fastio_rdata(0));
        PEEK(x"D69B");
        assert false report "sdcard.vhdl FSM state = " & integer'image(to_integer(fastio_rdata));
      end if;
    end procedure;

    type char_file_t is file of character;
    file char_file : char_file_t;
    variable char_v : character;
    subtype byte_t is natural range 0 to 255;
    variable byte_v : byte_t;

    variable sector_number : integer := 0;
    variable byte_count : integer := 0;
    variable sector_empty : boolean := true;
    
  begin

    -- Begin by loading VFAT dummy file system
    report "VFAT: Loading VFAT file system from test-sdcard.img";
    file_open(char_file, "test-sdcard.img");
    sector_number := 0;
    sector_empty := true;
    while not endfile(char_file) loop
      read(char_file, char_v);
      byte_v := character'pos(char_v);
      sector_slots(sector_count)(byte_count) <= to_unsigned(byte_v,8);
      if byte_v /= 0 then
        sector_empty := false;
      end if;
      byte_count := byte_count + 1;
      if byte_count = 512 then
        if sector_empty = false then
          report "Sector $" & to_hexstring(to_unsigned(sector_number,32)) & " is not empty. Storing in slot " & integer'image(sector_count);
          sector_numbers(sector_count) <= sector_number;
          sector_count <= sector_count + 1;
          if (sector_count + 1) >= sector_slot_count then
            assert false report "VFAT: Too many non-zero sectors. Increase sector_slot_count";
          end if;
        end if;

        -- Get ready for reading the next sector in
        sector_number := sector_number + 1;
        byte_count := 0;
        sector_empty := true;
      end if; 
      wait for 1 ps;
    end loop;
    wait for 1 ps;
    file_close(char_file);
    report "VFAT: Finished loading VFAT file system of " & integer'image(sector_number) & " sectors (" & integer'image(sector_count) & " non empty).";
    
    test_runner_setup(runner, runner_cfg);

    while test_suite loop

      if run("SD card ready following RESET sequence") then

        sdcard_reset_sequence;
        
      elsif run("SD card can read a single sector") then

        sdcard_reset_sequence;
        sdcard_read_sector(0);
        
      end if;
    end loop;
    test_runner_cleanup(runner);
  end process;

end architecture;
