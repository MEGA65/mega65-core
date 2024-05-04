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

  -- Do not hold reset line asserted low
  signal reset : std_logic := '1';
  
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
  signal sector_count : integer := 1; -- slot 0 holds the dummy "all zeroes" sector

  signal flash_address : unsigned(47 downto 0);
  signal flash_address_expected : unsigned(47 downto 0);
  signal last_flash_address : unsigned(47 downto 0);
  signal flash_rdata : unsigned(7 downto 0);
  signal flash_wdata : unsigned(7 downto 0);
  signal flash_write : std_logic;
  signal last_flash_slot : integer := 0;
  
begin

  sdcard0: entity work.sdcard_model
    port map ( clock => clock41,
               cs_bo => cs_bo,
               sclk_o => sclk_o,
               mosi_o => mosi_o,
               miso_i => miso_i,

               flash_address => flash_address,
               flash_rdata => flash_rdata,
               flash_wdata => flash_wdata,
               flash_write => flash_write
               );
  
  sdcard_controller0: entity work.sdcardio
  generic map ( target => simulation,
                cpu_frequency => 40_500_000,
                sdcache_address_bits => 7 )  -- 2^7 = 128 sectors = 64KB
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
    variable target_flash_slot : integer := 0;
    variable read_duration : integer := 0;
    variable flash_slot : integer := 0;

    procedure clock_tick is
      variable slot_num : integer := 0;
      variable sector_found : boolean := false;
    begin

      -- Simulate flash memory for sdcard_model.
      if flash_address(47 downto 9) /= last_flash_address(47 downto 9) then
        report "SDCARDIMG: Selecting sector $" & to_hexstring(flash_address) & " (prev was $" & to_hexstring(last_flash_address) & ")";
        flash_slot := 0;
        for i in 1 to (sector_count-1) loop
            if safe_to_integer(flash_address(47 downto 9)) = sector_numbers(i) then
            flash_slot := i;
            report "SDCARDIMG: Sector $" & to_hexstring(flash_address(47 downto 9)) & " maps to sector slot " & integer'image(i);
            sector_found := true;
            exit;
          end if;
        end loop;
        if sector_found = false then
          report "SDCARDIMG: Sector $" & to_hexstring(flash_address(47 downto 9)) & " maps to an empty sector.";
        end if;
      end if;
      if flash_address /= last_flash_address or flash_slot /= last_flash_slot then
        if flash_write = '0' then
          report "SDCARDIMG: Reading $" & to_hexstring(sector_slots(flash_slot)(to_integer(flash_address(8 downto 0))))
            & " from (" & integer'image(flash_slot) & "," & integer'image(to_integer(flash_address(8 downto 0))) & ")";        
          flash_rdata <= sector_slots(flash_slot)(to_integer(flash_address(8 downto 0)));
        else
          report "SDCARDIMG: Writing $" & to_hexstring(flash_wdata)
            & " to (" & integer'image(flash_slot) & "," & integer'image(to_integer(flash_address(8 downto 0))) & ")";        
            report "SDCARDIMG: Full flash write address = $" & to_hexstring(flash_address);
          sector_slots(flash_slot)(to_integer(flash_address(8 downto 0))) <= flash_wdata;
        end if;
      end if;        

      last_flash_address <= flash_address;
      last_flash_slot <= flash_slot;
      
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
      fastio_addr(11 downto 0) <= addr(11 downto 0);
      fastio_addr(19 downto 12) <= x"d3";
      fastio_wdata <= data;
      fastio_write <= '1';
      fastio_read <= '0';

      sdcardio_cs <= '0';
      sector_cs <= '0';
      sector_cs_fast <= '0';
      if addr(15 downto 8) = x"de" or addr(15 downto 8) = x"df" then
        sector_cs <= '1';
        sector_cs_fast <= '1';
      else
        sdcardio_cs <= '1';
      end if;
        
      -- Wait one full 41MHz clock tick
      for i in 1 to 8 loop
        clock_tick;
      end loop;

      fastio_write <= '0';
      sdcardio_cs <= '0';
      
    end procedure;
    
    procedure PEEK(addr : unsigned(15 downto 0) ) is
    begin
      sdcardio_cs <= '0';
      sector_cs <= '0';
      sector_cs_fast <= '0';
      if addr(15 downto 8) = x"D6" then
        sdcardio_cs <= '1';
        fastio_addr(11 downto 0) <= addr(11 downto 0);
        fastio_addr(19 downto 12) <= x"d3";
      elsif addr(15 downto 8) = x"de" or addr(15 downto 8) = x"df" then
        sector_cs <= '1';
        sector_cs_fast <= '1';
        fastio_addr <= (others => '0');
        fastio_addr(8 downto 0) <= addr(8 downto 0);
      end if;
        
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

    procedure fill_sector_buffer(first_byte : unsigned(7 downto 0)) is
      variable val : unsigned(7 downto 0);
    begin
      val := first_byte;
      for i in 0 to 511 loop
        POKE(to_unsigned(56832 + i,16), val);
        if val /= x"ff" then
          val := val + 1;
        else
          val := to_unsigned(0,8);
        end if;
      end loop;
    end procedure;
        
    procedure sdcard_read_sector(sector : integer;
                                 -- Check that correct data gets read
                                 verify : boolean;
                                 -- Check that flash address indicates the
                                 -- sector was read from.
                                 verify_sector_number : boolean;
                                 -- Require that the sector read was from cache
                                 must_be_from_cache : boolean;
                                 -- Require that the sector read was NOT from cache
                                 must_not_be_from_cache : boolean;
                                 message : string) is
      variable first_offset : integer := 0;
      variable expected : string(1 to (6 + 16 * 3 - 1));
      variable actual : string(1 to (6 + 16 * 3 - 1));
    begin

      -- Fill read sector buffer with fluff, so we can tell if anything was
      -- actually read or not.
      fill_sector_buffer(x"BD");
      
      POKE(x"D681",to_unsigned(sector,32)(7 downto 0));
      POKE(x"D682",to_unsigned(sector,32)(15 downto 8));
      POKE(x"D683",to_unsigned(sector,32)(23 downto 16));
      POKE(x"D684",to_unsigned(sector,32)(31 downto 24));
      flash_address_expected(47 downto 41) <= (others => '0');
      flash_address_expected(40 downto 9) <= to_unsigned(sector+1,32);
      POKE(x"D680",x"02"); -- Read single sector
      -- Allow enough time to read the whole sector
      for i in 1 to 20000 loop
        PEEK(x"D680");
        if fastio_rdata(1 downto 0) = "00" then
          report "SD card READY following READ SECTOR after " & integer'image(i) & " read cycles.";
          read_duration := i;
          exit;
        end if;
        if i = 1000 then
          target_flash_slot := flash_slot;
        end if;
      end loop;

      -- Verify that we read the sector correctly
      if verify then
        for i in 0 to 511 loop
          PEEK(to_unsigned(56832 + i,16));  -- $DE00 + i
          if fastio_rdata /= sector_slots(target_flash_slot)(i) then
            report "Expected byte " & integer'image(i) & " of read sector (slot " &
              integer'image(target_flash_slot) & " = sector " & integer'image(sector_numbers(target_flash_slot) ) & ")" &
              " to be $" & to_hexstring(sector_slots(target_flash_slot)(i))
              & ", but saw $" & to_hexstring(fastio_rdata);
            if i > 8 then
              first_offset := i-8;
            else
              first_offset := 0;
            end if;
            expected(1 to 3) := to_hexstring(to_unsigned(first_offset,12));
            expected(4) := ':';
            expected(5) := ' ';
            actual(1 to 3) := to_hexstring(to_unsigned(first_offset,12));
            actual(4) := ':';
            actual(5) := ' ';
            for j in 0 to 15 loop
              expected(6 + j*3 to 6 + j*3 + 1) := to_hexstring(sector_slots(target_flash_slot)(j + first_offset));
              PEEK(to_unsigned(56832 + j + first_offset,16));  -- $DE00 + i
              actual(6 + j*3 to 6 + j*3 + 1) := to_hexstring(fastio_rdata);
              expected(6 + j*3+2) := ' ';
              actual(6 + j*3+2) := ' ';
            end loop;
            report "Expected to see: " & expected;
            report "   Actually saw: " & actual;
            assert false report "READSECTOR: " & message & " failed due expected vs actual sector read data mismatch.";
          end if;
        end loop;
      end if;
      
      -- Verify that flash memory read pointer has been set correctly
      PEEK(x"D680");
      if fastio_rdata(1 downto 0) /= "00" then
        assert false report "SD card did not return READY following request to read single sector " & integer'image(sector);
      end if;
      if fastio_rdata(6 downto 5) /= "00" then
        assert false report "SD card error following request to read single sector " & integer'image(sector);
      end if;
      if read_duration > 1000 then
        -- For non-cached reads, check the last flash address accessed
        if flash_address(8 downto 0) /= "000000000" then
          report "SD card flash address = $" & to_hexstring(flash_address) & ", expected to see $" & to_hexstring(flash_address_expected);
          assert false report "SD card did not read exactly 512 bytes of data. " & integer'image(to_integer(flash_address(8 downto 0)));
       end if;
      end if;
      if verify_sector_number and to_integer(flash_address(40 downto 9)) /= (sector+1) then
        assert false report "SD card did not read the correct sector (expected to see $" & to_hexstring(to_unsigned(sector + 1,32))
          & ", but saw $" & to_hexstring(flash_address(40 downto 9)) & ").";
      end if;
      if must_be_from_cache then
        if read_duration > 1000 then
          assert false report "SD card did not read the sector from the cache, but it should have";
        end if;
      end if;
      
      if must_not_be_from_cache then
        if read_duration < 5000 then
          assert false report "SD card read the sector from the cache, but it shouldn't have";
        end if;
      end if;
      
      report "READSECTOR: " & message & " succeeded.";
    end procedure;

    procedure sdcard_write_sector(sector : integer; verify_sector_number : boolean) is
    begin
      POKE(x"D681",to_unsigned(sector,32)(7 downto 0));
      POKE(x"D682",to_unsigned(sector,32)(15 downto 8));
      POKE(x"D683",to_unsigned(sector,32)(23 downto 16));
      POKE(x"D684",to_unsigned(sector,32)(31 downto 24));
      flash_address_expected(47 downto 41) <= (others => '0');
      flash_address_expected(40 downto 9) <= to_unsigned(sector+1,32);
      flash_address_expected(8 downto 0) <= (others => '1');

      POKE(x"D680",x"57"); -- open the write gate
      POKE(x"D680",x"03"); -- Write single sector

      -- Allow enough time to write the whole sector
      for i in 1 to 20000 loop
        PEEK(x"D680");
        if fastio_rdata(1 downto 0) = "00" then
          report "SD card READY following WRITE SECTOR after " & integer'image(i) & " read cycles.";
          read_duration := i;
          exit;
        end if;
        if i = 1000 then
          target_flash_slot := flash_slot;
        end if;
      end loop;
      if fastio_rdata(1 downto 0) /= "00" then
        assert false report "SD card never went ready after write";
      end if;
      
      -- Verify that flash memory address pointer has been set correctly
      PEEK(x"D680");
      if fastio_rdata(1 downto 0) /= "00" then
        assert false report "SD card did not return READY following request to write single sector " & integer'image(sector);
      end if;
      if fastio_rdata(6 downto 5) /= "00" then
        assert false report "SD card error following request to write single sector " & integer'image(sector);
      end if;
      if flash_address(8 downto 0) /= "111111111" then
        report "SD card flash address = $" & to_hexstring(flash_address) & ", expected to see $" & to_hexstring(flash_address_expected);
        assert false report "SD card did not write exactly 512 bytes of data. " & integer'image(1+to_integer(flash_address(8 downto 0)));
      end if;
      if verify_sector_number and to_integer(flash_address(40 downto 9)) /= sector then
        assert false report "SD card did not write the correct sector (expected to see $" & to_hexstring(to_unsigned(sector,32))
          & ", but saw $" & to_hexstring(flash_address(40 downto 9)) & ").";
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
--      report "SDCARDIMG: Stashing in (" & integer'image(sector_count) & "," & integer'image(byte_count) & ") <= byte $" & to_hexstring(to_unsigned(byte_v,8)) & " = #" & integer'image(byte_v);
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
        
      elsif run("SD card can read a single sector (cache off)") then

        sdcard_reset_sequence;
        POKE(x"D680",x"CD");
        sdcard_read_sector(1, true, true, false, true, "first read (sector 1)");

      elsif run("SD card can read a single sector (cache on)") then

        sdcard_reset_sequence;
        POKE(x"D680",x"CE");
        sdcard_read_sector(1, true,true, false, true, "first read (sector 1)");

      elsif run("SD card can read multiple requested sectors (cache off)") then

        sdcard_reset_sequence;
        POKE(x"D680",x"CD");
        -- Verify that reading a couple of different sectors works
        sdcard_read_sector(1, true,true, false, true, "first read (sector 1)");
        sdcard_read_sector(0, true,true, false, true, "second read (sector 0)");

      elsif run("SD card can read multiple requested sectors (cache on)") then

        sdcard_reset_sequence;
        POKE(x"D680",x"CE");
        -- Verify that reading a couple of different sectors works
        sdcard_read_sector(1, true,true, false, true, "first read (sector 1)");
        sdcard_read_sector(0, true,true, false, true, "second read (sector 0)");

      elsif run("Reading a sector places it in the cache") then
        -- XXX Test by reading sesctor twice, and confirming the second time
        -- reads much faster

        sdcard_reset_sequence;
        POKE(x"D680",x"CE");
        -- Verify that reading a couple of different sectors works
        sdcard_read_sector(1, true,true, false, true,"first read (sector 1)");
        report "Uncached read required " & integer'image(read_duration) & " cycles.";
        sdcard_read_sector(1, true,true, true, false, "second read (sector 1) from cache");

      elsif run("Reading into the cache when full causes eviction and replacement") then
        sdcard_reset_sequence;
        POKE(x"D680",x"CE");   -- enable cache

        -- Mark cache as full of sector #42
        POKE(x"D680",x"21");
        -- Wait long enough for it to take effect
        for i in 1 to 1024 loop
          clock_tick;
        end loop;

        -- Sector 42 should be present in the cache and read quickly.        
        sdcard_read_sector(42, false,false, true, false, "dummy sector 42");
        if read_duration > 1000 then
          assert false report "Second read should have been from the cache, and thus fast, but it wasn't.";
        end if;
        -- Now read a real sector, and make sure that it is fast the 2nd time.
        sdcard_read_sector(1, true,true, false, true, "Read of sector 1 while cache full");
        report "Uncached read required " & integer'image(read_duration) & " cycles.";
        sdcard_read_sector(1, true,true, true, false, "Read of sector 1 from cache after evicting a dummy sector");
        
        
      elsif run("Writing to SD card model works") then

        sdcard_reset_sequence;
        POKE(x"D680",x"CE");   -- enable cache

        -- Prepare sector buffer full of values, the first of which is $42.
        fill_sector_buffer(x"42");

        -- Write that to sector 1
        sdcard_write_sector(1,true);

        -- Check that reading sector after write works (it won't be cached yet,
        -- though)
        sdcard_read_sector(1, true,true, false, true, "Reading sector 1 from cache after writing to it");
                     
      elsif run("Write-back to SD card cache updates cache") then
        -- XXX Read, write, re-read and verify that 2nd read was from cache (fast)
        -- and reflects the updated data.

        sdcard_reset_sequence;
        POKE(x"D680",x"CE");   -- enable cache

        -- Read a sector, causing it to be cached
        sdcard_read_sector(1,true,true, false, true, "Read sector 1 to cache it");

        -- Prepare sector buffer full of values, the first of which is $42.
        fill_sector_buffer(x"42");

        -- Write that to sector 1. This should cause both the sector and the cache to be updated
        sdcard_write_sector(1,true);

        -- Check that reading sector after write works
        -- This relies on the fact that sector writes are always synchronous, so any changes to the
        -- cache and SD card will alread be committed, by the time the next read request can be made.
        sdcard_read_sector(1, true,false,true, false,"Read sector 1 from cache after writing to it");
        
      elsif run("Cache Read-Ahead") then
        -- The cache read-ahead is a work-around for slow SD cards, including for Mirage's MEGApple
        -- demo for which the industrial grade class 4 SD cards are too slow.  The extra speed is
        -- obtained by using multi-block reads, and terminating them if the next block requested is
        -- not the block currently being read or the next block that is about to be read.  The SD
        -- card cache should read-ahead one cluster's worth of blocks in all likelihood, in order
        -- to get a decent speed up.  To make the cache perform better, this probably means that we
        -- need to make data block requests load into the cache at cluster-aligned slots, and be
        -- placed in consecutive slots, so that we don't have parts of clusters ejecting parts of other
        -- clusters all the time, reducing cache effectiveness.

        -- We should also inidcate whether a read request is for a data block, in which case the 
        -- read-ahead for a whole cluster makes sense, or if it is for a file system structure, in
        -- which case it might not make sense. We also intend to partition the cache, so that half is
        -- used for file system structures and half for data, so that directory searches and seeking
        -- through files can be faster.

        -- It's an open question as to whether we should always cache a cluster's worth of sectors for
        -- file system structures.  For the file system descriptor block etc, it probably isn't helpful
        -- as those are only 2 or 3 sectors long compared with 8 sector clusters.  FAT sectors are only
        -- needed once per 128 data clusters = 512KB of data, so the benefit there is probably less.
        -- But for directories, it makes a lot of sense to do the read-ahead.  I guess I'll have soom
        -- booleans for controlling this, so that we can measure the impact of each of those decisions
        -- and change them at run-time as well.
        
        -- Let's start by partitioning the cache for file system structures vs data blocks.
        -- That's now largely in place, but not yet tested.

        -- Next we need to implement multi-sector writes.
        -- First step is making the sdcard_model be able to receive a CMD12 during a sector
        -- read and to abort the read.  At the moment sdcard_model only watches for incoming commands
        -- during the idle state.  It needs to also look during any of the block read related states
        -- as well.

        -- Then we need for sdcardio to loop through reading data sectors until all read-ahead has
        -- occurred, or a new SD card operation is requested by the user.  The data sector start times
        -- only need to be bit aligned, not byte aligned in multi-sector reads, so we just need to
        -- watch for a single 0 bit.  One very simple approach is to simply send a CMD12 before any 
        -- other command, as it will ensure that the SD card is back to the idle state. Again, we need
        -- to take care to identify when a request is made to read or write a sector that is currently
        -- being read via the look-head cache. This has to happen in sdcard.vhdl, and we then need to
        -- have a protocol to communicate this between it and sdcardio. It should be possible to base
        -- it off the multi-sector write logic.

        -- Reading two consecutive sectors should result in the 2nd sector reading faster,
        -- because the read-ahead will already be doing its thing.  

        sdcard_reset_sequence;
        POKE(x"D680",x"CE");
        -- Verify that reading a couple of different sectors works
        sdcard_read_sector(0, true,true, false, true,"first read (sector 1)");
        -- Wait long enough for read-ahead to read this 2nd sector
        for i in 1 to 20000 loop
          clock_tick;
        end loop;
        sdcard_read_sector(1, true,true, true, false, "second read (sector 1) from cache");

        
      end if;
    end loop;
    test_runner_cleanup(runner);
  end process;

end architecture;
