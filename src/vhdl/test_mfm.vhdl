library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_mfm is
end entity;

architecture foo of test_mfm is

  type CharFile is file of character;

  signal clock50mhz : std_logic := '1';
  signal f_rdata : std_logic := '1';
  -- 2 usec bit rate for 720K disks
  signal cycles_per_interval : unsigned(7 downto 0) := to_unsigned(100,8);
  
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
                                       
begin

  decoder0: entity work.mfm_decoder port map (
    clock50mhz => clock50mhz,
    f_rdata => f_rdata,
    cycles_per_interval => cycles_per_interval,
    invalidate => '0',

    target_track => target_track,
    target_sector => target_sector,
    target_side => target_side,
    target_any => target_any,

    sector_found => sector_found,
    sector_data_gap => sector_data_gap,
    found_track => found_track,
    found_sector => found_sector,
    found_side => found_side,

    first_byte => first_byte,
    byte_valid => byte_valid,
    byte_out => byte_out,
    crc_error => crc_error,
    sector_end => sector_end
    );
  
  process is
    file trace : CharFile;
    variable c : character;
  begin
    file_open(trace,"assets/synthesised-60ns.dat",READ_MODE);
    while not endfile(trace) loop
      Read(trace,c);
--      report "Read char $" & to_hstring(to_unsigned(character'pos(c),8));      
      f_rdata <= to_unsigned(character'pos(c),8)(4);
      clock50mhz <= '0';
      wait for 10 ns;
      clock50mhz <= '1';
      wait for 10 ns;
      clock50mhz <= '0';
      wait for 10 ns;
      clock50mhz <= '1';
      wait for 10 ns;
      clock50mhz <= '0';
      wait for 10 ns;
      clock50mhz <= '1';
      wait for 10 ns;
    end loop;
  end process;

  process (clock50mhz,byte_out) is
  begin
    if rising_edge(clock50mhz) then
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
