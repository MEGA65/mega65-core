----------------------------------------------------------
-- MFM sector decoding
--
-- There are two structures we have to detect, each of which
-- follow 3 sync bytes.
-- 1. $FE = Sector identifier (Track,Sector,Side,Size,CRC16)
-- 2. $FB = Sector data (512 bytes, CRC16)
--
-- So the work here is relatively simple, and we can ignore
-- all the gap bytes, as they are unimportant to us, except
-- for indicating to the caller when we have reached the gap data
-- where it is safe to start re-writing the sector data.
--
-----------------------------------------------------------


use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity mfm_decoder is
  generic ( unit_id : integer);
  port (
    clock40mhz : in std_logic;

    f_rdata : in std_logic;
    invalidate : in std_logic;

    encoding_mode : in unsigned(3 downto 0);
    
    mfm_state : out unsigned(7 downto 0) := x"00";
    mfm_last_gap : out unsigned(15 downto 0) := x"0000";
    mfm_last_gap_strobe : out std_logic := '0';
    mfm_last_byte : out unsigned(7 downto 0) := x"00";
    mfm_quantised_gap : out unsigned(7 downto 0) := x"00";
    packed_rdata : out std_logic_vector(7 downto 0);
    
    cycles_per_interval : in unsigned(7 downto 0);    

    -- The track/sector/side we are being asked to find
    target_track : in unsigned(7 downto 0);
    target_sector : in unsigned(7 downto 0);
    target_side : in unsigned(7 downto 0);
    -- .. or if target_any is asserted, then find the first sector we hit
    target_any : in std_logic := '0';

    -- Report track info blocks, so that sdcardio can switch data rates automatically
    track_info_valid : out std_logic := '0';
    track_info_track : out unsigned(7 downto 0) := to_unsigned(0,8);
    track_info_rate : out unsigned(7 downto 0) := to_unsigned(0,8);
    track_info_encoding : out unsigned(7 downto 0) := to_unsigned(0,8);
    track_info_sectors : out unsigned(7 downto 0) := to_unsigned(0,8);
    
    -- Indicate when we have hit the start of the gap leading
    -- to the data area (this is so that sector writing can
    -- begin.  It does have to take account of the latency of
    -- the write stage, and also any write precompensation).
    sector_found : out std_logic := '0';
    sector_data_gap : out std_logic := '0';
    found_track : out unsigned(7 downto 0) := x"00";
    found_sector : out unsigned(7 downto 0) := x"00";
    found_side : out unsigned(7 downto 0) := x"00";

    autotune_step : out std_logic := '0';
    autotune_stepdir : out std_logic := '0';
    
    -- Bytes of the sector when reading
    first_byte : out std_logic := '0';
    byte_valid : out std_logic := '0';
    byte_out : out unsigned(7 downto 0);
    -- Mark the end of sector when finished reading, and report CRC status
    sector_end : out std_logic := '0';
    crc_error : out std_logic := '0'
    
    );
end mfm_decoder;

architecture behavioural of mfm_decoder is

  signal gap_length : unsigned(15 downto 0);
  signal gap_valid : std_logic;
  signal gap_count : unsigned(3 downto 0);
  
  signal gap_size_valid : std_logic;
  signal gap_size : unsigned(1 downto 0);
  signal qgap_count : unsigned(5 downto 0) := (others => '0');
  
  signal sync_in : std_logic;
  signal bit_in : std_logic;
  signal bit_valid : std_logic;

  signal sync_out : std_logic;
  signal byte_in : unsigned(7 downto 0);
  signal byte_valid_in : std_logic;

  signal seen_track : unsigned(7 downto 0) := x"FF";
  signal seen_sector : unsigned(7 downto 0) := x"FF";
  signal last_seen_sector : unsigned(7 downto 0) := x"FF";
  signal seen_side : unsigned(7 downto 0) := x"FF";
  signal seen_size : unsigned(7 downto 0) := x"FF";
  signal seen_valid : std_logic := '0';

  signal crc_reset : std_logic := '1';
  signal crc_feed : std_logic := '0';
  signal crc_byte : unsigned(7 downto 0);
  
  signal crc_ready : std_logic;
  signal crc_value : unsigned(15 downto 0);

  type MFMState is (
    WaitingForSync,
    TrackNumber,
    SectorNumber,
    SideNumber,
    SizeNumber,
    HeaderCRC1,
    HeaderCRC2,
    CheckCRC,
    SectorData,
    DataCRC1,
    DataCRC2,
    TrackInfo,
    TrackInfoRate,
    TrackInfoEncoding,
    TrackInfoSectorCount,
    TrackInfoCRC1,
    TrackInfoCRC2,
    TrackInfoCheckCRC
    );

  signal state : MFMSTate := WaitingForSync;
  signal sync_count : integer range 0 to 3 := 0;
  signal byte_count : integer range 0 to 4095 := 0;
  signal sector_size : integer range 0 to 4095 := 0;

  signal last_crc : unsigned(15 downto 0) := x"0000";
  signal crc_wait : std_logic_vector(3 downto 0) := x"0";

  signal mfm_bit_valid : std_logic := '0';
  signal mfm_bit_in : std_logic := '0';
  signal mfm_sync_in : std_logic := '0';
  signal mfm_byte_out : unsigned(7 downto 0) := x"00";

  signal rll_byte_out : unsigned(7 downto 0) := x"00";
  signal rll_bit_valid : std_logic := '0';
  signal rll_bit_in : std_logic := '0';
  signal rll_sync_in : std_logic := '0';
  signal rll_gap_size_valid : std_logic := '0';
  signal rll_gap_size : unsigned(2 downto 0) := "000";
  
  
begin

  gaps0: entity work.mfm_gaps port map (
    clock40mhz => clock40mhz,

    packed_rdata => packed_rdata,
    
    f_rdata => f_rdata,
    gap_length => gap_length,    
    gap_valid => gap_valid,
    gap_count => gap_count
    );

  quantise0: entity work.mfm_quantise_gaps port map (
    clock40mhz => clock40mhz,

    cycles_per_interval => cycles_per_interval,

    gap_valid_in => gap_valid,
    gap_length_in => gap_length,

    gap_valid_out => gap_size_valid,
    gap_size_out => gap_size
    );

  bits0: entity work.mfm_gaps_to_bits port map (
    clock40mhz => clock40mhz,

    gap_valid => gap_size_valid,
    gap_size => gap_size,

    bit_valid => mfm_bit_valid,
    bit_out => mfm_bit_in,
    sync_out => mfm_sync_in
    );

  rllquantise0: entity work.rll27_quantise_gaps port map (
    clock40mhz => clock40mhz,

    cycles_per_interval => cycles_per_interval,

    gap_valid_in => gap_valid,
    gap_length_in => gap_length,

    gap_valid_out => rll_gap_size_valid,
    gap_size_out => rll_gap_size
    );

  rllbits0: entity work.rll27_gaps_to_bits port map (
    clock40mhz => clock40mhz,

    gap_valid => rll_gap_size_valid,
    gap_size => rll_gap_size,

    bit_valid => rll_bit_valid,
    bit_out => rll_bit_in,
    sync_out => rll_sync_in
    );
  
  bytes0: entity work.mfm_bits_to_bytes port map (
    clock40mhz => clock40mhz,

    sync_in => sync_in,
    bit_in => bit_in,
    bit_valid => bit_valid,

    sync_out => sync_out,
    byte_out => byte_in,
    byte_valid => byte_valid_in    
    );

  crc0: entity work.crc1581 generic map ( id => unit_id )
    port map (
    clock40mhz => clock40mhz,
    crc_byte => crc_byte,
    crc_feed => crc_feed,
    crc_reset => crc_reset,
    
    crc_ready => crc_ready,
    crc_value => crc_value
    );
  
  process (clock40mhz,f_rdata,
           encoding_mode,
           rll_bit_valid,rll_bit_in,rll_sync_in,rll_byte_out,
           mfm_bit_valid,mfm_bit_in,mfm_sync_in,mfm_byte_out) is
  begin

    case encoding_mode is
      when x"1" =>
        bit_valid <= rll_bit_valid;
        bit_in <= rll_bit_in;
        sync_in <= rll_sync_in;
        byte_out <= rll_byte_out;
      when others =>
        bit_valid <= mfm_bit_valid;
        bit_in <= mfm_bit_in;
        sync_in <= mfm_sync_in;
        byte_out <= mfm_byte_out;
    end case;
    
    if rising_edge(clock40mhz) then

      track_info_valid <= '0';
      
      -- We clear this every cycle, so it will only pulse for a very short time
      -- (25ns).  Is this too short for a floppy drive to notice?
      autotune_step <= '0';
      
      mfm_last_byte <= byte_in;
      mfm_state <= to_unsigned(MFMState'pos(state),8);
      mfm_last_gap(11 downto 0) <= gap_length(11 downto 0);
      mfm_last_gap(15 downto 12) <= gap_count;
      mfm_last_gap_strobe <= gap_valid;
      if gap_size_valid='1' then
        mfm_quantised_gap(7) <= sync_in;
        mfm_quantised_gap(6) <= mfm_sync_in;
        mfm_quantised_gap(5) <= rll_sync_in;
        mfm_quantised_gap(4 downto 2) <= qgap_count(2 downto 0);
        mfm_quantised_gap(1 downto 0) <= gap_size;
        if qgap_count /= "111111" then
          qgap_count <= qgap_count + 1;
        else
          qgap_count <= "000000";
        end if;
      end if;
      
      -- Update expected size of sector
      case seen_size is
        when x"00" => sector_size <= 128-1;
        when x"01" => sector_size <= 256-1;
        when x"02" => sector_size <= 512-1;
        when x"03" => sector_size <= 1024-1;
        when x"04" => sector_size <= 2048-1;
        when others => sector_size <= 512-1;
      end case;

      crc_wait(3 downto 1) <= crc_wait(2 downto 0);
      crc_wait(0) <= '0';
      if (state = CheckCRC) and (crc_ready='1') and (crc_wait="0000") then
        last_crc <= crc_value;

        -- set crc_error and clear seen_valid if CRC /= 0
        if crc_value /= x"0000" then
--          report "HEADER: crc_value = $" & to_hstring(crc_value) & ", asserting crc_error";
          seen_valid <= '0';
          crc_error <= '1';
        else
--          report "HEADER: CRC good.";
          crc_error <= '0';
          if byte_count /= 0 then
            sector_end <= '1';
            sector_found <= '0';
          else
            if (target_any='1')
              or (
                (to_integer(target_track) = to_integer(seen_track))
                and (to_integer(target_sector) = to_integer(seen_sector))) then
                  -- Don't check side?
--                and (to_integer(target_side) = to_integer(seen_side))) then
              if (last_crc = x"0000") then
--                report "HEADER: Seen sector matches target, CRC good";
                found_track <= seen_track;
                found_sector <= seen_sector;
                found_side <= seen_side;
                -- Data gap begins now
                sector_data_gap <= '1';
                sector_found <= '1';
                seen_valid <= '1';
              end if;
            else
              -- T/S/S doesn't match
              seen_valid <= '0';
            end if;
            -- XXX Debug T/S/S mismatches
            if seen_sector /= last_seen_sector then
              report "HEADER: Updating found track,sector,side";
              last_seen_sector <= seen_sector;
            end if;
            found_track <= seen_track;
            found_sector <= seen_sector;
            found_side <= seen_side;
            if to_integer(target_track) = to_integer(seen_track) then
              found_track(7) <= '1';
              autotune_step <= '0';
            else
              autotune_step <= '1';
              if to_integer(target_track) > to_integer(seen_track) then
                autotune_stepdir <= '0';
              else
                autotune_stepdir <= '1';
              end if;
            end if;
            if to_integer(target_sector) = to_integer(seen_sector) then
              found_sector(7) <= '1';
            end if;
            if to_integer(target_side) = to_integer(seen_side) then
              found_side(7) <= '1';
            end if;

            if last_crc /= x"0000" then
              report "Seen sector does not match target";
              seen_valid <= '0';
            end if;             
          end if;
        end if;
      end if;
              
      first_byte <= '0';
      crc_feed <= '0';
      crc_reset <= '0';
      byte_valid <= '0';
      
      if sync_out='1' then

        -- Clear output flags and state whenever we hit a sync mark
        first_byte <= '0';
        sector_end <= '0';
        crc_error <= '0';
        sector_data_gap <= '0';

        byte_count <= 0;
        state <= WaitingForSync;

        if sync_count = 0 then
          crc_reset <= '1';
        end if;
        crc_feed <= '1'; crc_byte <= byte_in;

        report "sync_count = " & integer'image(sync_count);
        
        if sync_count < 3 then          
          sync_count <= sync_count + 1;
        end if;
      elsif byte_valid_in='1' then
        sync_count <= 0;
        if sync_count = 3 then
          -- First byte after a sync
          report "TRACKINFO: Post Sync byte = $" & to_hstring(byte_in);
          if byte_in = x"FE" then
            -- Sector header marker
            crc_feed <= '1'; crc_byte <= byte_in;
            seen_valid <= '0';
            state <= TrackNumber;
          elsif byte_in = x"FB" then
            -- Sector data marker
            state <= SectorData;
            crc_feed <= '1'; crc_byte <= byte_in;
            byte_count <= 0;
          elsif byte_in = x"65" then
            -- Track Format Info Marker (MEGA65 specific)
            report "TRACKINFO: Saw block marker";
            state <= TrackInfo;
            crc_feed <= '1'; crc_byte <= byte_in;
            byte_count <= 0;
          else
            state <= WaitingForSync;
          end if;
        elsif sync_count = 0 then
--          report "MFM state = " & MFMState'image(state);
          case state is
            when WaitingForSync =>
              null;
            when TrackInfo =>
              -- Track info block has:
              -- Byte 0: Track number
              -- Byte 1: Track data rate
              -- Byte 2: Track encoding ($80 = RLL, $00 = MFM, lower bits reserved)
              report "TRACKINFO: Saw Track = $" & to_hstring(byte_in);
              track_info_track <= byte_in;
              crc_feed <= '1'; crc_byte <= byte_in;
              state <= TrackInfoRate;
            when TrackInfoRate =>
              report "TRACKINFO: Saw Rate = $" & to_hstring(byte_in);
              track_info_rate <= byte_in;
              crc_feed <= '1'; crc_byte <= byte_in;
              state <= TrackInfoEncoding;
            when TrackInfoEncoding =>
              report "TRACKINFO: Saw Encoding = $" & to_hstring(byte_in);
              track_info_encoding <= byte_in;
              crc_feed <= '1'; crc_byte <= byte_in;
              state <= TrackInfoSectorCount;
            when TrackInfoSectorcount =>
              report "TRACKINFO: Saw Sector Count = $" & to_hstring(byte_in);
              track_info_sectors <= byte_in;
              crc_feed <= '1'; crc_byte <= byte_in;              
              state <= TrackInfoCRC1;
            when TrackInfoCRC1 =>
              report "TRACKINFO: Saw CRC1 = $" & to_hstring(byte_in);
              state <= TrackInfoCRC2;
              crc_feed <= '1'; crc_byte <= byte_in;
            when TrackInfoCRC2 =>
              report "TRACKINFO: Saw CRC2 = $" & to_hstring(byte_in);
              crc_feed <= '1'; crc_byte <= byte_in;
              state <= TrackInfoCheckCRC;
            when TrackInfoCheckCRC =>
              
              report "TRACKINFO: CRC=$" & to_hstring(crc_value);
              crc_feed <= '0';
              if crc_value = x"0000" then
                track_info_valid <= '1';
              end if;
              state <= WaitingForSync;
            when TrackNumber =>
              seen_track <= byte_in;
              crc_feed <= '1'; crc_byte <= byte_in;
              state <= SideNumber;
            when SideNumber =>
              seen_side <= byte_in;
              crc_feed <= '1'; crc_byte <= byte_in;
              state <= SectorNumber;
            when SectorNumber =>
              seen_sector <= byte_in;
              crc_feed <= '1'; crc_byte <= byte_in;
              state <= SizeNumber;
            when SizeNumber =>
              seen_size <= byte_in;
              crc_feed <= '1'; crc_byte <= byte_in;
              state <= HeaderCRC1;
            when HeaderCRC1 =>
              state <= HeaderCRC2;
              crc_feed <= '1'; crc_byte <= byte_in;
            when HeaderCRC2 =>
              seen_valid <= '1' and (not invalidate);
              crc_feed <= '1'; crc_byte <= byte_in;
              crc_wait <= "1111";
              state <= CheckCRC;
              report "HEADER: Saw Track $" & to_hstring(seen_track)
                & ", Sector $" & to_hstring(seen_sector)
                & ", Side $" & to_hstring(seen_side)
                & ", Size $" & to_hstring(seen_size);
            when SectorData =>
              if (byte_count = 0) and (seen_valid='1') then
                first_byte <= '1';
              else
                first_byte <= '0';
              end if;
              byte_out <= byte_in;
              byte_valid <= seen_valid and byte_valid_in;
              crc_feed <= '1'; crc_byte <= byte_in;
              if byte_count < sector_size then
                byte_count <= byte_count + 1;
              else
                state <= DataCRC1;
              end if;
            when DataCRC1 =>
              crc_feed <= '1'; crc_byte <= byte_in;
              state <= DataCRC2;
            when DataCRC2 =>
              crc_feed <= '1'; crc_byte <= byte_in;
              crc_wait <= "1111";
              state <= CheckCRC;
            when CheckCRC =>
              -- CRC checking is done outside this loop
              null;
          end case;
        end if;
      end if;
      
    end if;    
  end process;
end behavioural;

