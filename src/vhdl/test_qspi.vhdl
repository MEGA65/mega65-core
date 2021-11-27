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

  signal QspiDB : unsigned(3 downto 0);
  signal QspiDB_in : unsigned(3 downto 0) := "1111";
  signal qspidb_oe : std_logic;
  signal QspiCSn : std_logic;
  signal qspi_clock : std_logic;

begin

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
    
    hypervisor_mode => '0',
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
    sectorbuffercs => '0',
    sectorbuffercs_fast => '0',
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

  
  process (clock40mhz,byte_out) is
    procedure POKE(addr : in unsigned(19 downto 0); val : in unsigned(7 downto 0)) is
    begin
      fastio_addr <= addr;
      fastio_wdata <= val;
      fastio_write <= '1';
      sdcardio_cs <= '1';
      f011_cs <= '0';
    end POKE;      
  begin
    if rising_edge(clock40mhz) then
      cycle_count <= cycle_count + 1;

      f_rdata <= f_wdata;
      
      case cycle_count is
        when 1 => POKE(x"d6e00",x"12");
        when 2 => POKE(x"d6e00",x"34");
        when 3 => POKE(x"d6e00",x"56");
        when 4 => POKE(x"d6e00",x"78");
        when 5 => POKE(x"d6e00",x"9a");
                  
        when 6 => POKE(x"d3681",x"03");
        when 7 => POKE(x"d3682",x"00");
        when 8 => POKE(x"d3683",x"00");
        when 9 => POKE(x"d3684",x"80");
        when 10 => POKE(x"d3680",x"5c"); -- select reduced dummy cycles
        when 11 => POKE(x"d3680",x"54"); -- $53 = sector read, $54 = program 512
                                        -- bytes
        when 12 => POKE(x"d3020",x"00");
        when others => null;
      end case;

    end if;
  end process;
  
end foo;
