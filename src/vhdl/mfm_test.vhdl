library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use STD.textio.all;
use work.all;
use work.debugtools.all;
use work.cputypes.all;

entity mfm_test is
  
end mfm_test;

architecture behavior of mfm_test is

  type CharFile is file of character;

  signal cpuclock : std_logic := '1';
  signal pixelclock : std_logic := '1';
  signal clock163 : std_logic := '1';
  signal clock325 : std_logic := '1';

  signal ready_for_next : std_logic := '0';
  signal f_write : std_logic := '0';
  signal byte_valid : std_logic := '0';
  signal byte_in : unsigned(7 downto 0) := x"A1";
  signal clock_byte_in : unsigned(7 downto 0) := x"FB";

  signal f_rdata : std_logic;

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
  signal byte_out_valid : std_logic := '0';
  signal byte_out : unsigned(7 downto 0);
  signal crc_error : std_logic := '0';
  signal sector_end : std_logic := '0';

  signal last_sector_end : std_logic := '0';
  signal last_sector_found : std_logic := '0';
  signal last_crc_error : std_logic := '0';
  
  -- The track/sector/side we are being asked to find
  signal target_track : unsigned(7 downto 0) := x"28";
  signal target_sector : unsigned(7 downto 0) := x"01";
  signal target_side : unsigned(7 downto 0) := x"01";
  signal target_any : std_logic := '0';

  signal byte_count : integer := 0;
  
  type byte_array_t is array (0 to 65536) of unsigned(15 downto 0);

  -- Disk data consists of bytes of data and clock data.
  -- Normal bytes have clock = $FF
  -- Sync bytes are $A1 with clock byte = $FB
  signal mfm_data : byte_array_t := (
    -- Following the C65 manual instructions for disk format

    -- 12 x gap 3* 
    x"0000",x"0000",x"0000",x"0000",x"0000",x"0000",x"0000",x"0000",x"0000",x"0000",x"0000",x"0000",
    -- 3x A1/FB mark
    x"A1FB",x"A1FB",x"A1FB",
    -- Header mark
    x"FEFF",
    x"28FF", -- Track number
    x"01FF", -- Side number (inverted on 1581)
    x"01FF", -- Sector number
    x"02FF", -- Sectors = 512 bytes long
    -- CRC bytes (see src/tools/c1581-crc.c for generation)
    x"4FFF",x"D2FF",
    -- Gap 2 (23 x $4E)
    x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",
    x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",
    x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",
    -- Gap 2 (12 x $00)
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    -- 3x A1/FB mark
    x"A1FB",x"A1FB",x"A1FB",
    -- Data mark
    x"FBFF",
    -- Sector data
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",

    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",

    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",

    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",
    x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",x"00FF",

    -- CRC bytes
    x"00FF",x"00FF",
    
    -- Gap 3 (24 x $4E)
    x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",
    x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",
    x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",x"4EFF",
    
    others => x"0000"
    );

  signal byte_counter : integer := 0;

  signal last_ready_for_next : std_logic := '0';

  signal crc_byte : unsigned(7 downto 0);
  signal crc_feed : std_logic := '0';
  signal crc_reset : std_logic := '1';
  signal crc_ready : std_logic;
  signal crc_value : unsigned(15 downto 0) := to_unsigned(42,16);  

  signal clock_byte_next : unsigned(7 downto 0) := x"FF";
  
begin

  process is
    file trace : CharFile;
    variable c : character;
  begin
    while true loop
      file_open(trace,"assets/synthesised-60ns.dat",READ_MODE);
      while not endfile(trace) loop
        Read(trace,c);
--        report "Floppy read bit " & std_logic'image(std_logic(to_unsigned(character'pos(c),8)(4)));
        f_rdata <= std_logic(to_unsigned(character'pos(c),8)(4));
        wait for 60 ns;
      end loop;
      file_close(trace);
    end loop;
  end process;

  crc0: entity work.crc1581 port map (
    clock40mhz => cpuclock,
    crc_byte => crc_byte,
    crc_feed => crc_feed,
    crc_reset => crc_reset,
    
    crc_ready => crc_ready,
    crc_value => crc_value
    );
    
  
  mfmenc0:
    entity work.mfm_bits_to_gaps port map (
      clock40mhz => cpuclock,
      cycles_per_interval => to_unsigned(80,8),
      write_precomp_enable => '1',
      ready_for_next => ready_for_next,
      f_write => f_write,
      byte_valid => byte_valid,
      byte_in => byte_in,
      clock_byte_in => clock_byte_in
    );

  decoder0: entity work.mfm_decoder port map (
    clock40mhz => cpuclock,
    -- Decode data from log file
--    f_rdata => f_rdata,
    -- Decode written data
    f_rdata => f_write,
    cycles_per_interval => to_unsigned(80,8),
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
    byte_valid => byte_out_valid,
    byte_out => byte_out,
    crc_error => crc_error,
    sector_end => sector_end
    );  
  
  process (cpuclock)
  begin
    if rising_edge(cpuclock) then

      -- Encoder
      
      last_ready_for_next <= ready_for_next;
      if ready_for_next = '1' and last_ready_for_next = '0' then
        byte_valid <= '1';
        byte_in <= mfm_data(byte_counter)(15 downto 8);
        clock_byte_next <= mfm_data(byte_counter)(7 downto 0);
        report "Feeding byte #" & integer'image(byte_counter) & " into MFM encoder: $" & to_hstring(mfm_data(byte_counter));
        if byte_counter < 1024 then
          byte_counter <= byte_counter + 1;
        else
          byte_counter <= 0;
        end if;
      else
        byte_valid <= '0';
        clock_byte_in <= clock_byte_next;
        if clock_byte_next /= clock_byte_in then
          report "presenting clock byte $"& to_hstring(clock_byte_next);
        end if;
      end if;

      -- Decoder
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
      if byte_out_valid='1' then
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
    
  process
  begin  -- process tb
    report "beginning simulation" severity note;

    wait for 3 ns;
    
    for i in 1 to 2000000 loop

      clock325 <= '0';
      pixelclock <= '0';
      cpuclock <= '0';
      clock163 <= '0';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      clock163 <= '1';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      pixelclock <= '1';
      clock163 <= '0';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      clock163 <= '1';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      pixelclock <= '0';
      cpuclock <= '1';
      clock163 <= '0';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      clock163 <= '1';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      pixelclock <= '1';
      clock163 <= '0';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
      clock163 <= '1';
      
      clock325 <= '1';
      wait for 1.5 ns;
      clock325 <= '0';
      wait for 1.5 ns;
      
    end loop;  -- i
    assert false report "End of simulation" severity failure;
  end process;

  process is
  begin
    wait for 100 ns;
    crc_reset <= '1';
    wait for 100 ns;
    crc_reset <= '0';
    wait for 1000 ns;
    crc_feed <= '1';
    crc_byte <= x"a1";
    wait for 20 ns;
    crc_feed <= '0';
    wait for 1000 ns;
--    report "CRC = $" & to_hstring(crc_value);
    wait for 1000 ns;
    crc_feed <= '1';
    crc_byte <= x"a1";
    wait for 20 ns;
    crc_feed <= '0';
    wait for 1000 ns;
--    report "CRC = $" & to_hstring(crc_value);
    wait for 1000 ns;
    crc_feed <= '1';
    crc_byte <= x"a1";
    wait for 20 ns;
    crc_feed <= '0';
    wait for 1000 ns;
--    report "CRC = $" & to_hstring(crc_value);
    wait for 1000 ns;
    crc_feed <= '1';
    crc_byte <= x"FE";
    wait for 20 ns;
    crc_feed <= '0';
    wait for 1000 ns;
--    report "CRC = $" & to_hstring(crc_value);
  end process;  
  
end behavior;

