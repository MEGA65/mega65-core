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
  port (
    clock50mhz : in std_logic;

    f_rdata : in std_logic;
    invalidate : in std_logic;

    mfm_state : out unsigned(7 downto 0) := x"00";
    mfm_last_gap : out unsigned(15 downto 0) := x"0000";
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
    
    -- Indicate when we have hit the start of the gap leading
    -- to the data area (this is so that sector writing can
    -- begin.  It does have to take account of the latency of
    -- the write stage, and also any write precompensation).
    sector_found : out std_logic := '0';
    sector_data_gap : out std_logic := '0';
    found_track : out unsigned(7 downto 0) := x"00";
    found_sector : out unsigned(7 downto 0) := x"00";
    found_side : out unsigned(7 downto 0) := x"00";

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
    DataCRC2
    );

  signal state : MFMSTate := WaitingForSync;
  signal sync_count : integer range 0 to 3 := 0;
  signal byte_count : integer range 0 to 4095 := 0;
  signal sector_size : integer range 0 to 4095 := 0;

  signal last_crc : unsigned(15 downto 0) := x"0000";
  signal crc_wait : std_logic_vector(3 downto 0) := x"0";
  
begin

  gaps0: entity work.mfm_gaps port map (
    clock50mhz => clock50mhz,

    packed_rdata => packed_rdata,
    
    f_rdata => f_rdata,
    gap_length => gap_length,    
    gap_valid => gap_valid,
    gap_count => gap_count
    );

  quantise0: entity work.mfm_quantise_gaps port map (
    clock50mhz => clock50mhz,

    cycles_per_interval => cycles_per_interval,

    gap_valid_in => gap_valid,
    gap_length_in => gap_length,

    gap_valid_out => gap_size_valid,
    gap_size_out => gap_size
    );

  bits0: entity work.mfm_gaps_to_bits port map (
    clock50mhz => clock50mhz,

    gap_valid => gap_size_valid,
    gap_size => gap_size,

    bit_valid => bit_valid,
    bit_out => bit_in,
    sync_out => sync_in
    );

  bytes0: entity work.mfm_bits_to_bytes port map (
    clock50mhz => clock50mhz,

    sync_in => sync_in,
    bit_in => bit_in,
    bit_valid => bit_valid,

    sync_out => sync_out,
    byte_out => byte_in,
    byte_valid => byte_valid_in    
    );

  crc0: entity work.crc1581 port map (
    clock50mhz => clock50mhz,
    crc_byte => crc_byte,
    crc_feed => crc_feed,
    crc_reset => crc_reset,
    
    crc_ready => crc_ready,
    crc_value => crc_value
    );
  
  process (clock50mhz,f_rdata) is
  begin
    if rising_edge(clock50mhz) then

      mfm_last_byte <= byte_in;
      mfm_state <= to_unsigned(MFMState'pos(state),8);
      mfm_last_gap(11 downto 0) <= gap_length(11 downto 0);
      mfm_last_gap(15 downto 12) <= gap_count;
      mfm_quantised_gap(7) <= sync_in;
      mfm_quantised_gap(7 downto 2) <= qgap_count;
      mfm_quantised_gap(1 downto 0) <= gap_size;
      if gap_size_valid='1' then
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
          report "crc_value = $" & to_hstring(crc_value) & ", asserting crc_error";
          seen_valid <= '0';
          crc_error <= '1';
        else
          crc_error <= '0';
          if byte_count /= 0 then
            sector_end <= '1';
            sector_found <= '0';
          else
--            if last_crc = x"0000" and false then
--              report "Valid sector header for"
--                & " T:$" & to_hstring(seen_track)
--                & ", S:$" & to_hstring(seen_sector)
--                & ", D:$" & to_hstring(seen_side)
--                & ", Z:$" & to_hstring(seen_size)
--                & " (seen_valid=" & std_logic'image(seen_valid)
--                & ", sector_found="
--                & std_logic'image(sector_found)
--                & ", crc=$" & to_hstring(last_crc)
--                & ")";
--            end if;
            if (target_any='1')
              or (
                (target_track = seen_track)
                and (target_sector = seen_sector)
                and (target_side = seen_side)) then
              if (last_crc = x"0000") then
--                report "Seen sector matches target";
                found_track <= seen_track;
                found_sector <= seen_sector;
                found_side <= seen_side;
                -- Data gap begins now
                sector_data_gap <= '1';
                sector_found <= '1';
                seen_valid <= '1';
              end if;
            else
              seen_valid <= '0';
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
          if byte_in = x"FE" then
            crc_feed <= '1'; crc_byte <= byte_in;
            seen_valid <= '0';
            state <= TrackNumber;
          elsif byte_in = x"FB" then
            state <= SectorData;
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

