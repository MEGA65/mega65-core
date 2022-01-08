library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;
use work.cputypes.all;

entity test_qspi is
end entity;

architecture foo of test_qspi is

  type CharFile is file of character;

  signal clock40mhz : std_logic := '1';
  signal clock80mhz : std_logic := '1';
  -- Rate for 720K DD disks
  signal cycles_per_interval : unsigned(7 downto 0) := to_unsigned(81,8);
  
    -- The track/sector/side we are being asked to find
  signal target_track : unsigned(7 downto 0) := x"00";
  signal target_sector : unsigned(7 downto 0) := x"01";
  signal target_side : unsigned(7 downto 0) := x"01";
  signal target_any : std_logic := '0';

  -- Indicate when we have hit the start of the gap leading
  -- to the data area (this is so that sector writing can
  -- begin.  It does have to take account of the latency of
  -- the write stage, and also any write precompensation).
  signal sector_found : std_logic := '0';
  signal sector_data_gap : std_logic := '0';
  signal found_track : unsigned(7 downto 0) := x"00";
  signal found_sector : unsigned(7 downto 0) := x"00";
  signal found_side : unsigned(7 downto 0) := x"00";

    -- Bytes of the sector when reading
  signal first_byte : std_logic := '0';
  signal byte_valid : std_logic := '0';
  signal byte_out : unsigned(7 downto 0);
  signal crc_error : std_logic := '0';
  signal sector_end : std_logic := '0';

  signal last_sector_end : std_logic := '0';
  signal last_sector_found : std_logic := '0';
  signal last_crc_error : std_logic := '0';

  signal byte_count : integer := 0;

  signal ready_for_next : std_logic := '0';
  signal byte_valid_in : std_logic := '0';
  signal byte_in : unsigned(7 downto 0) := x"00";
  signal clock_byte_in : unsigned(7 downto 0) := x"FF";

  signal sdcardio_cs : std_logic := '0';
  signal f011_cs : std_logic := '0';
  signal fastio_addr : unsigned(19 downto 0) := to_unsigned(0,20);
  signal fastio_addr_fast : unsigned(19 downto 0) := to_unsigned(0,20);
  signal fastio_wdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal fastio_rdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal fastio_write : std_logic := '0';
  signal fastio_read : std_logic := '0';

  signal f_rdata : std_logic := '1';
  signal f_wdata : std_logic := '1';
  signal f_track0 : std_logic := '1';
  signal f_writeprotect : std_logic := '1';
  signal f_diskchanged : std_logic := '1';
  signal f_index : std_logic := '1';

  signal cycle_count : integer := 0;

  signal sectorbuffercs : std_logic := '0';

  signal QspiDB_comb : unsigned(3 downto 0) := "1010";
  
  signal QspiDB : unsigned(3 downto 0);
  signal QspiDB_in : unsigned(3 downto 0) := "1111";
  signal qspidb_oe : std_logic;
  signal QspiCSn : std_logic;
  signal qspi_clock : std_logic;

begin

  flash0: entity work.s25fl512s
    generic map (
      TimingModel => "..............S"
      )
    port map (
        -- Data Inputs/Outputs
        SI => qspidb_comb(0),
        SO => qspidb_comb(1),
        -- Controls
        SCK => qspi_clock,
        CSNeg => qspiCSn,
        RSTNeg => '1',
        WPNeg => qspidb_comb(2),
        HOLDNeg => qspidb_comb(3)
    );

  
  fdc0: entity work.sdcardio
    generic map (
      cpu_frequency => 40500000,
      target => mega65r3 )
    port map (
    clock => clock40mhz,
    pixelclk => clock80mhz,
    reset => '1',
    sdcardio_cs => sdcardio_cs,
    f011_cs => f011_cs,

    qspidb => qspidb,
    qspidb_oe => qspidb_oe,
    qspidb_in =>qspidb_in,
    qspicsn => qspicsn,
    qspi_clock => qspi_clock,
    
    audio_mix_rdata => x"ffff",
    audio_loopback => x"ffff",
    
    hypervisor_mode => '1',
    secure_mode => '0',
    fpga_temperature => (others => '0'),
    pwm_knob => x"ffff",

    fastio_addr_fast => fastio_addr_fast,
    fastio_addr => fastio_addr,
    fastio_write => fastio_write,
    fastio_read => fastio_read,
    fastio_wdata => fastio_wdata,
    fastio_rdata_sel => fastio_rdata,

    virtualise_f011_drive0 => '0',
    virtualise_f011_drive1 => '0',
    colourram_at_dc00 => '0',
    viciii_iomode => "11",
    sectorbuffercs => sectorbuffercs,
    sectorbuffercs_fast => sectorbuffercs,
    last_scan_Code => (others => '1'),

    dipsw => (others => '1'),
    j21in => (others => '1'),
    sw => (others => '1'),
    btn => (others => '1'),
    miso_i => '1',
    f_index => f_index,
    f_track0 => f_track0,
    f_writeprotect => f_writeprotect,
    f_rdata => f_rdata,
    f_wdata => f_wdata,
    f_diskchanged => f_diskchanged,

    sd1541_request_toggle => '0',
    sd1541_enable => '0',
    sd1541_track => to_unsigned(0,6),

    aclMISO => '0',
    aclInt1 => '0',
    aclInt2 => '0',
    tmpInt => '0',
    tmpCT => '0'

    
    );
    
  process is
  begin
    while true loop
      clock40mhz <= '1';
      clock80mhz <= '1';
      wait for 6.25 ns;
      clock80mhz <= '0';
      wait for 6.25 ns;
      clock40mhz <= '0';
      clock80mhz <= '1';
      wait for 6.25 ns;
      clock80mhz <= '0';
      wait for 6.25 ns;
    end loop;
  end process;

  process (qspi_clock) is
  begin
    report "qspi_clock = " & std_logic'image(qspi_clock);
  end process;  
  
  process (clock40mhz,byte_out) is
    procedure POKE(addr : in unsigned(19 downto 0); val : in unsigned(7 downto 0)) is
    begin
      fastio_addr <= addr;
      fastio_wdata <= val;
      fastio_write <= '1';
      if addr(19 downto 8) = x"d36" then
        sdcardio_cs <= '1';
      else
        sdcardio_cs <= '0';
      end if;
      if addr(19 downto 8) = x"d08" then
        f011_cs <= '1';
      else
        f011_cs <= '0';
      end if;
      if addr(19 downto 12) = x"d6" then
        sectorbuffercs <= '1';
      else
        sectorbuffercs <= '0';
      end if;
      report "POKE $" & to_hstring(addr) & ",$" & to_hstring(val);
    end POKE;      
  begin

    if qspidb_oe='0' then
      qspidb_comb <= "ZZZZ";
      report "TRI: Tristating. Reading " & to_string(std_logic_vector(qspidb_comb));
    else
      qspidb_comb <= qspidb;
      report "TRI: Exporting " & to_string(std_logic_vector(qspidb));
    end if;
    qspidb_in <= qspidb_comb;
    
    if rising_edge(clock40mhz) then
      cycle_count <= cycle_count + 1;

      f_rdata <= f_wdata;
      
      case cycle_count is

        -- Disable free-running clock
        when 1 => POKE(x"d36cd",x"00");

                  -- Read CFI block
--        when 401 => POKE(x"d3680",x"6b");
        when 402 => POKE(x"d3020",x"00");
                  
        -- Enable Quad mode
        when  801 => POKE(x"d3680",x"66"); -- Write enable
        when  802 => POKE(x"d0000",x"00"); -- stop writing to reg
        when  901 => POKE(x"d3683",x"02"); -- Write to SR1/CR1
        when  902 => POKE(x"d3684",x"00");
        when  903 => POKE(x"d3680",x"69");
        when  904 => POKE(x"d0000",x"00");

        -- Put some data in the write buffer
        when 1001 => POKE(x"d6e00",x"12");
        when 1002 => POKE(x"d6e01",x"34");
        when 1003 => POKE(x"d6e02",x"56");
        when 1004 => POKE(x"d6e03",x"78");
        when 1005 => POKE(x"d6e04",x"9a");

        when 1006 => POKE(x"d6ff0",x"f0");
        when 1007 => POKE(x"d6ff1",x"f1");
        when 1008 => POKE(x"d6ff2",x"f2");
        when 1009 => POKE(x"d6ff3",x"f3");
        when 1010 => POKE(x"d6ff4",x"f4");
        when 1011 => POKE(x"d6ff5",x"f5");
        when 1012 => POKE(x"d6ff6",x"f6");
        when 1013 => POKE(x"d6ff7",x"f7");
        when 1014 => POKE(x"d6ff8",x"48");
        when 1015 => POKE(x"d6ff9",x"49");
        when 1016 => POKE(x"d6ffa",x"4a");
        when 1017 => POKE(x"d6ffb",x"4b");
        when 1018 => POKE(x"d6ffc",x"4c");
        when 1019 => POKE(x"d6ffd",x"4d");
        when 1020 => POKE(x"d6ffe",x"4e");
        when 1021 => POKE(x"d6fff",x"4f");
        when 1022 => POKE(x"d3020",x"00");

                     
        when 1100 => POKE(x"d3680",x"5f"); -- select reduced dummy cycles
                     
        -- Write to address $00000000
        when 1206 => POKE(x"d3681",x"00");
        when 1207 => POKE(x"d3682",x"00");
        when 1208 => POKE(x"d3683",x"00");
        when 1209 => POKE(x"d3684",x"00");

                     -- Enable writing
        when 1211 => POKE(x"d3680",x"66"); -- Write enable
        when 1212 => POKE(x"d0000",x"00"); -- stop writing to reg

                     -- Do page write
        when 1300 => POKE(x"d3680",x"54"); -- $53 = sector read, $54 = program 512
                                        -- bytes, $58 = erase page, $59 = erase
                                        -- 4KB page, $66 = write enable, $55 =
                                        -- program 256 bytes, $6c = program 16 bytes
        when 1301 => POKE(x"d0000",x"00"); -- stop writing to reg

                     -- Verify written page
        when 5001 => POKE(x"d3680",x"56"); -- Read page back
        when 5002 => POKE(x"d0000",x"00"); -- stop writing to reg
                     -- Check bytes differ (= verify fail in this case) flag in
                     -- bit 6 of $D689
--        when 9001 => PEEK(x"d3689",x"00");
        when 9002 => POKE(x"d0000",x"00"); -- stop writing to reg
          
                     
        when others => null;
      end case;

    end if;
  end process;
  
end foo;
