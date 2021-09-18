library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;
use work.cputypes.all;

entity test_mfm is
end entity;

architecture foo of test_mfm is

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
      clock40mhz <= '0';
      clock80mhz <= '0';
      wait for 5 ns;
      clock80mhz <= '1';
      wait for 5 ns;
      clock40mhz <= '1';
      clock80mhz <= '0';
      wait for 5 ns;
      clock80mhz <= '1';
      wait for 5 ns;
    end loop;
  end process;

  
  process (clock40mhz,byte_out) is
  begin
    if rising_edge(clock40mhz) then
      cycle_count <= cycle_count + 1;

      f_rdata <= f_wdata;
      
      case cycle_count is
        when 1 =>
          -- Select real drive 0
          report "TEST: $D6A1 <- $01";
          fastio_addr <= x"D36A1";
          fastio_wdata <= x"01";
          fastio_write <= '1';
          sdcardio_cs <= '1';
          f011_cs <= '0';
        when 2 =>
          report "TEST: $D6A2 <- 23";
          -- Set data rate to 23
          fastio_addr <= x"D36A2";
          fastio_wdata <= to_unsigned(23,8);
          fastio_write <= '1';
          sdcardio_cs <= '1';
          f011_cs <= '0';
        when 3 =>
          report "TEST: $D084 <- 40 (track 40)";
          -- Track number is 0
          fastio_addr <= x"D3084";
          fastio_wdata <= to_unsigned(40,8);
          fastio_write <= '1';
          sdcardio_cs <= '0';
          f011_cs <= '1';
        when 4 =>
          report "TEST: $D085 <- 2 (2 sectors per track)";
          -- Track number is 0
          fastio_addr <= x"D3085";
          fastio_wdata <= to_unsigned(2,8);
          fastio_write <= '1';
          f011_cs <= '1';
        when 5 =>
          report "TEST: $D6AE <- $F1";
          -- Select RLL encoding, enable TIB to set data rate and encoding
          fastio_addr <= x"D36AE";
          fastio_wdata <= x"F1";
          fastio_write <= '1';
          sdcardio_cs <= '1';
          f011_cs <= '0';
        when 6 =>
          -- Format track with write precomp, sector gaps
          report "TEST: $D081 <- $A4";
          fastio_addr <= x"D3081";
          fastio_wdata <= x"A4";
          fastio_write <= '1';
          f011_cs <= '1';
        when others =>
          fastio_write <= '0';
          fastio_read <= '1';
          fastio_addr <= x"D36A7";
--          if cycle_count > 10 and fastio_rdata /= x"28" then
--            report "TRACKINFO: track_info_rate = $" & to_hstring(fastio_rdata);
--          end if;
          f011_cs <= '0';
          sdcardio_cs <= '1';
      end case;
      -- Simulate floppy index line
      case cycle_count is
        when 10 =>
          f_index <= '0';
        when 20 =>
          f_index <= '1';
        when others =>
          null;
      end case;      
      
      last_sector_found <= sector_found;
      last_sector_end <= sector_end;
      last_crc_error <= crc_error;
      if crc_error /= last_crc_error then
        report "STATUS: crc_error=" & std_logic'image(crc_error);
      end if;
      if sector_found /= last_sector_found then
        report "STATUS: sector_found=" & std_logic'image(sector_found);
      end if;
      if sector_end /= last_sector_end then
        report "STATUS: sector_end=" & std_logic'image(sector_end)
          & ", after reading " & integer'image(byte_count) & " bytes.";
      end if;
      if byte_valid='1' then
        report "Read sector byte $" & to_hstring(byte_out)
          & " (first=" & std_logic'image(first_byte)
          & ")";
        byte_count <= byte_count + 1;
      end if;
      if (sector_end or crc_error)='1' then
        report "End of sector reached: crc_error="
          & std_logic'image(crc_error);        
      end if;
    end if;
  end process;
  
end foo;
