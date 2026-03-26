use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.debugtools.all;
use work.cputypes.all;

-- Extracted QSPI flash state machine from sdcardio.vhdl.
--
-- This entity owns:
--   $D6CC  QSPI bit-bang: tristate, CSN, clock, DB[3:0]
--   $D6CD  QSPI clock run / clock
--   $D6CE  Alias for $D6CC (bit-bang duplicate)
--
-- Actions are dispatched from sdcardio via action_strobe + action_byte
-- (decoded from the $D680 register).  The action byte values are the same as
-- in the original sdcardio implementation ($50–$6C range).
--
-- The sector buffer slot for QSPI is $A00–$BFF ("101" & offset[8:0]).

entity qspi_flash is
  port (
    clock           : in  std_logic;
    reset           : in  std_logic;

    hypervisor_mode : in  std_logic;
    dipsw2          : in  std_logic;

    -- Action interface: sdcardio pulses action_strobe for one cycle when a
    -- QSPI action byte is written to $D680.  spi_address_in carries sd_sector
    -- at that moment.
    action_byte     : in  unsigned(7 downto 0);
    action_strobe   : in  std_logic;
    spi_address_in  : in  unsigned(31 downto 0);

    -- Status outputs
    busy            : out std_logic;
    bytes_differ    : out std_logic;

    -- Sector buffer interface.
    -- buf_raddr drives f011_buffer_read_address in sdcardio (combinational).
    -- buf_write / buf_waddr / buf_wdata are registered; sdcardio applies them
    -- to f011_buffer_write* at the end of its clocked process.
    buf_rdata       : in  unsigned(7 downto 0);
    buf_raddr       : out unsigned(8 downto 0);
    buf_waddr       : out unsigned(11 downto 0);
    buf_wdata       : out unsigned(7 downto 0);
    buf_write       : out std_logic;

    -- Fastio registers: $D6CC, $D6CD, $D6CE
    fastio_cs       : in  std_logic;
    fastio_addr     : in  unsigned(7 downto 0);
    fastio_write    : in  std_logic;
    fastio_wdata    : in  unsigned(7 downto 0);
    fastio_rdata    : out unsigned(7 downto 0);

    -- Physical QSPI pins
    qspi_db         : out unsigned(3 downto 0) := "1111";
    qspi_db_in      : in  unsigned(3 downto 0);
    qspi_db_oe      : out std_logic := '0';
    qspi_csn        : out std_logic := '1';
    qspi_clock      : out std_logic := '1'
  );
end qspi_flash;

architecture behavioural of qspi_flash is

  type qspi_state_t is (
    Idle,
    QSPI_Send_Command,
    QSPI_Release_CS,
    QSPI_write_256,
    QSPI_write_512,
    QSPI_qwrite_16,
    QSPI_qwrite_256,
    QSPI_qwrite_512,
    QSPI_write_phase1,
    QSPI_write_phase2,
    QSPI_write_phase3,
    QSPI_write_phase4,
    QSPI_qwrite_phase1,
    QSPI_qwrite_phase2,
    QSPI_qwrite_phase3,
    QSPI_qwrite_phase4,
    QSPI4_write_256,
    QSPI4_write_512,
    QSPI4_write_phase1,
    QSPI4_write_phase2,
    QSPI_read_512,
    QSPI_read_phase1,
    QSPI_read_phase2,
    QSPI_read_phase3,
    QSPI_read_phase4,
    SPI_read_512,
    SPI_read_phase1,
    SPI_read_phase2,
    SPI_read_phase3,
    SPI_read_phase4
  );

  signal qspi_state : qspi_state_t := Idle;

  signal qspi_clock_int   : std_logic := '1';
  signal qspi_clock_run   : std_logic := '1';
  signal qspi_csn_int     : std_logic := '1';
  signal qspi_bits        : unsigned(3 downto 0) := "0000";
  signal qspi_bytes_differ_int : std_logic := '0';
  signal qspi_byte_value  : unsigned(7 downto 0) := x"00";
  signal qspi_bit_counter : integer range 0 to 7 := 0;
  signal qspidb_tristate  : std_logic := '1';
  signal qspi_read_sector_phase : integer range 0 to 128 := 0;
  signal qspi_action_state : qspi_state_t := Idle;
  signal qspi_command_len : integer range 84 to 100 := 98;
  signal spi_address      : unsigned(31 downto 0) := (others => '0');
  signal qspi_release_cs_on_completion        : std_logic := '0';
  signal qspi_release_cs_on_completion_enable : std_logic := '1';
  signal qspi_verify_mode   : std_logic := '0';
  signal spi_flash_cmd_byte : unsigned(7 downto 0) := x"ec";
  signal spi_flash_cmd_only : std_logic := '0';
  signal spi_flash_16bits   : std_logic := '0';
  signal spi_no_dummy_cycles : std_logic := '0';

  -- Internal buffer offset (equivalent to sd_buffer_offset in sdcardio,
  -- but private to this entity so it doesn't alias the SD card's copy).
  signal buf_offset : unsigned(8 downto 0) := (others => '0');

  -- Registered buffer write outputs
  signal buf_write_int : std_logic := '0';
  signal buf_waddr_int : unsigned(11 downto 0) := (others => '0');
  signal buf_wdata_int : unsigned(7 downto 0) := (others => '0');

begin

  -- Concurrent outputs
  busy         <= '0' when qspi_state = Idle else '1';
  bytes_differ <= qspi_bytes_differ_int;
  buf_raddr    <= buf_offset;
  buf_write    <= buf_write_int;
  buf_waddr    <= buf_waddr_int;
  buf_wdata    <= buf_wdata_int;
  qspi_clock   <= qspi_clock_int;

  -- Combinational fastio read: $D6CC, $D6CD
  process (fastio_cs, fastio_addr, fastio_write,
           qspidb_tristate, qspi_csn_int, qspi_clock_int,
           qspi_db_in, qspi_clock_run) is
  begin
    fastio_rdata <= (others => 'Z');
    if fastio_cs = '1' and fastio_write = '0' then
      case fastio_addr is
        when x"CC" =>
          fastio_rdata(7) <= qspidb_tristate;
          fastio_rdata(6) <= qspi_csn_int;
          fastio_rdata(5) <= qspi_clock_int;
          fastio_rdata(4) <= '0';
          fastio_rdata(3 downto 0) <= qspi_db_in;
        when x"CD" =>
          fastio_rdata(0) <= qspi_clock_run;
          fastio_rdata(1) <= qspi_clock_int;
          fastio_rdata(7 downto 2) <= (others => '0');
        when others =>
          null;
      end case;
    end if;
  end process;

  process (clock) is
  begin
    if rising_edge(clock) then

      buf_write_int <= '0';

      if reset = '0' then
        qspi_state     <= Idle;
        qspi_clock_int <= '1';
        qspi_clock_run <= '1';
        qspi_csn_int   <= '1';
        qspi_db        <= "1111";
        qspi_db_oe     <= '0';
        qspi_csn       <= '1';
        qspi_bytes_differ_int <= '0';
      else

        -- Free-run the QSPI clock when enabled and in hypervisor/dipsw mode.
        -- State machine assignments below may override this.
        if qspi_clock_run = '1' and (hypervisor_mode = '1' or dipsw2 = '1') then
          qspi_clock_int <= not qspi_clock_int;
        end if;

        -- Fastio register writes ($D6CC, $D6CD, $D6CE)
        if fastio_cs = '1' and fastio_write = '1' then
          case fastio_addr is
            when x"CC" =>
              if hypervisor_mode = '1' or dipsw2 = '1' then
                qspi_csn        <= fastio_wdata(6);
                qspi_csn_int    <= fastio_wdata(6);
                qspi_db         <= fastio_wdata(3 downto 0);
                qspidb_tristate <= fastio_wdata(7);
                qspi_db_oe      <= not fastio_wdata(7);
              end if;
            when x"CD" =>
              if hypervisor_mode = '1' or dipsw2 = '1' then
                qspi_clock_run <= fastio_wdata(0);
                qspi_clock_int <= fastio_wdata(1);
              end if;
            when x"CE" =>
              if hypervisor_mode = '1' or dipsw2 = '1' then
                qspi_csn        <= fastio_wdata(6);
                qspi_csn_int    <= fastio_wdata(6);
                qspi_clock_int  <= fastio_wdata(5);
                qspi_db         <= fastio_wdata(3 downto 0);
                qspidb_tristate <= fastio_wdata(7);
                qspi_db_oe      <= not fastio_wdata(7);
              end if;
            when others =>
              null;
          end case;
        end if;

        -- Action dispatch from $D680 in sdcardio
        if action_strobe = '1' then
          case action_byte is
            when x"50" =>  -- P: Write 256 bytes in 1-bit mode
              if hypervisor_mode = '1' or dipsw2 = '1' then
                qspi_state <= QSPI_write_256;
              end if;
            when x"51" =>  -- Q: Write 512 bytes in 1-bit mode
              if hypervisor_mode = '1' or dipsw2 = '1' then
                qspi_state <= QSPI_write_512;
              end if;
            when x"52" =>  -- R: Read 512 bytes in 4-bit mode
              if hypervisor_mode = '1' or dipsw2 = '1' then
                qspi_state <= QSPI_read_512;
              end if;
            when x"53" =>  -- S: Full-transaction read 512 bytes
              spi_address             <= spi_address_in;
              qspi_read_sector_phase  <= 0;
              qspi_action_state       <= QSPI_read_512;
              qspi_verify_mode        <= '0';
              spi_flash_cmd_byte      <= x"6c";
              spi_no_dummy_cycles     <= '0';
              qspi_state              <= QSPI_Send_Command;
            when x"54" =>  -- T: Full-transaction write 512 bytes
              if hypervisor_mode = '1' or dipsw2 = '1' then
                spi_address                      <= spi_address_in;
                qspi_read_sector_phase           <= 0;
                spi_no_dummy_cycles              <= '1';
                qspi_action_state                <= QSPI_qwrite_512;
                spi_flash_cmd_byte               <= x"34";
                qspi_release_cs_on_completion    <= qspi_release_cs_on_completion_enable;
                buf_offset                       <= to_unsigned(0, 9);
                qspi_state                       <= QSPI_Send_Command;
              end if;
            when x"55" =>  -- U: Full-transaction write 256 bytes
              if hypervisor_mode = '1' or dipsw2 = '1' then
                spi_address                      <= spi_address_in;
                qspi_read_sector_phase           <= 0;
                qspi_action_state                <= QSPI_qwrite_256;
                spi_flash_cmd_byte               <= x"34";
                spi_no_dummy_cycles              <= '1';
                qspi_release_cs_on_completion    <= qspi_release_cs_on_completion_enable;
                buf_offset                       <= to_unsigned(256, 9);
                qspi_state                       <= QSPI_Send_Command;
              end if;
            when x"56" =>  -- V: Full-transaction verify 512 bytes
              spi_address             <= spi_address_in;
              qspi_read_sector_phase  <= 0;
              qspi_action_state       <= QSPI_read_512;
              qspi_verify_mode        <= '1';
              spi_flash_cmd_byte      <= x"6c";
              spi_no_dummy_cycles     <= '0';
              qspi_state              <= QSPI_Send_Command;
            when x"58" =>  -- X: Erase 64K page
              if hypervisor_mode = '1' or dipsw2 = '1' then
                spi_address            <= spi_address_in;
                qspi_read_sector_phase <= 0;
                qspi_action_state      <= QSPI_Release_CS;
                spi_flash_cmd_byte     <= x"dc";
                qspi_state             <= QSPI_Send_Command;
              end if;
            when x"59" =>  -- Y: Erase 4K small page
              if hypervisor_mode = '1' or dipsw2 = '1' then
                spi_address            <= spi_address_in;
                qspi_read_sector_phase <= 0;
                qspi_action_state      <= QSPI_Release_CS;
                spi_flash_cmd_byte     <= x"21";
                qspi_state             <= QSPI_Send_Command;
              end if;
            when x"5a" => qspi_command_len <= 90;
            when x"5b" => qspi_command_len <= 92;
            when x"5c" => qspi_command_len <= 94;
            when x"5d" => qspi_command_len <= 96;
            when x"5e" => qspi_command_len <= 98;
            when x"5f" => qspi_command_len <= 100;
            when x"66" =>  -- SPI flash write enable
              if hypervisor_mode = '1' or dipsw2 = '1' then
                qspi_read_sector_phase <= 0;
                qspi_action_state      <= QSPI_Release_CS;
                spi_flash_cmd_byte     <= x"06";
                spi_flash_cmd_only     <= '1';
                qspi_state             <= QSPI_Send_Command;
              end if;
            when x"67" =>
              qspi_release_cs_on_completion_enable <= '0';
            when x"68" =>
              qspi_release_cs_on_completion_enable <= '1';
            when x"69" =>  -- Set CR1
              if hypervisor_mode = '1' or dipsw2 = '1' then
                spi_address            <= spi_address_in;
                qspi_read_sector_phase <= 0;
                qspi_action_state      <= QSPI_Release_CS;
                spi_flash_cmd_byte     <= x"01";
                spi_flash_16bits       <= '1';
                qspi_state             <= QSPI_Send_Command;
              end if;
            when x"6a" =>  -- Clear status register
              qspi_read_sector_phase <= 0;
              qspi_action_state      <= QSPI_Release_CS;
              spi_flash_cmd_byte     <= x"30";
              spi_flash_cmd_only     <= '1';
              qspi_state             <= QSPI_Send_Command;
            when x"6b" =>  -- Read CFI data block
              spi_address            <= x"00000000";
              qspi_read_sector_phase <= 0;
              qspi_action_state      <= SPI_read_512;
              spi_flash_cmd_byte     <= x"9f";
              spi_flash_cmd_only     <= '1';
              spi_no_dummy_cycles    <= '1';
              qspi_state             <= QSPI_Send_Command;
            when x"6c" =>  -- Write 16-byte region
              if hypervisor_mode = '1' or dipsw2 = '1' then
                spi_address                   <= spi_address_in;
                qspi_read_sector_phase        <= 0;
                qspi_action_state             <= QSPI_qwrite_16;
                spi_flash_cmd_byte            <= x"34";
                spi_no_dummy_cycles           <= '1';
                qspi_release_cs_on_completion <= qspi_release_cs_on_completion_enable;
                buf_offset                    <= to_unsigned(256+240, 9);
                qspi_state                    <= QSPI_Send_Command;
              end if;
            when others =>
              null;
          end case;
        end if;

        -- State machine
        case qspi_state is

          when Idle =>
            if qspi_release_cs_on_completion = '1' then
              qspi_release_cs_on_completion <= '0';
              qspi_csn     <= '1';
              qspi_csn_int <= '1';
            end if;

          when QSPI_Send_Command =>
            report "QSPI: send command phase" & integer'image(qspi_read_sector_phase)
              & ", cmd_only=" & std_logic'image(spi_flash_cmd_only);
            if qspi_read_sector_phase < 3 or (qspi_read_sector_phase mod 2 = 0) then
              qspi_clock_int <= '1';
            else
              qspi_clock_int <= '0';
            end if;
            if qspi_read_sector_phase < qspi_command_len then
              qspi_read_sector_phase <= qspi_read_sector_phase + 1;
            else
              report "QSPI: Preserving clock while switching to action state at phase "
                & integer'image(qspi_read_sector_phase);
              qspi_state     <= qspi_action_state;
              qspi_clock_int <= qspi_clock_int;
            end if;
            if qspi_read_sector_phase > 2 and qspi_read_sector_phase < (2 + 8*2) then
              qspi_db(0) <= spi_flash_cmd_byte(7);
            end if;
            if qspi_read_sector_phase > 18 and qspi_read_sector_phase < (18 + 32*2) then
              qspi_db(0) <= spi_address(31);
            end if;
            if qspi_read_sector_phase = 20 and spi_flash_cmd_only = '1' then
              spi_flash_cmd_only <= '0';
              report "QSPI: Exiting early due to cmd_only flag";
              qspi_clock_int <= qspi_clock_int;
              if qspi_action_state = QSPI_Release_CS then
                report "QSPI: Pulling clock low while exiting to action state";
                qspi_clock_int <= '0';
              end if;
              qspi_state <= qspi_action_state;
            end if;
            if qspi_read_sector_phase = (20+16*2) and spi_flash_16bits = '1' then
              report "QSPI: Exiting early due to flash_16bits flag";
              if qspi_action_state = QSPI_Release_CS then
                qspi_clock_int   <= '0';
                spi_flash_16bits <= '0';
              end if;
              qspi_state <= qspi_action_state;
            end if;
            case qspi_read_sector_phase is
              when 4 | 6 | 8 | 10 | 12 | 14 | 16 =>
                spi_flash_cmd_byte(7 downto 1) <= spi_flash_cmd_byte(6 downto 0);
              when 20 | 22 | 24 | 26 | 28 | 30 | 32 |
                   34 | 36 | 38 | 40 | 42 | 44 | 46 | 48 |
                   50 | 52 | 54 | 56 | 58 | 60 | 62 | 64 |
                   66 | 68 | 70 | 72 | 74 | 76 | 78 | 80 | 82 =>
                spi_address(31 downto 1) <= spi_address(30 downto 0);
              when 81 =>
                if qspi_action_state = QSPI_qwrite_512 or
                   qspi_action_state = QSPI_qwrite_256 or
                   qspi_action_state = QSPI_qwrite_16 then
                  qspi_state <= qspi_action_state;
                end if;
              when 84 =>
                if qspi_action_state = QSPI_Release_CS or spi_no_dummy_cycles = '1' then
                  qspi_clock_int     <= '0';
                  report "QSPI: pulling clock low while switching to action state";
                  spi_no_dummy_cycles <= '0';
                  qspi_state         <= qspi_action_state;
                end if;
              when others =>
                null;
            end case;
            case qspi_read_sector_phase is
              when 0 | 1 => qspi_csn <= '1'; qspi_csn_int <= '1';
              when 2     => qspi_csn <= '0'; qspi_csn_int <= '0';
              when 3 | 4 => qspi_db_oe <= '1'; qspidb_tristate <= '0';
                            qspi_db(3 downto 1) <= "111";
              when others => null;
            end case;

          when QSPI_Release_CS =>
            qspi_clock_int <= '0';
            qspi_csn       <= '1';
            qspi_csn_int   <= '1';
            qspi_state     <= Idle;

          when SPI_read_512 =>
            report "QSPI: in SPI_read_512";
            qspidb_tristate <= '1';
            qspi_db_oe      <= '0';
            buf_offset      <= to_unsigned(0, 9);
            qspi_state      <= SPI_read_phase1;
            qspi_bytes_differ_int <= '0';

          when QSPI_read_512 =>
            report "QSPI: in QSPI_read_512";
            qspidb_tristate <= '1';
            qspi_db_oe      <= '0';
            buf_offset      <= to_unsigned(0, 9);
            qspi_state      <= QSPI_read_phase1;
            qspi_bytes_differ_int <= '0';

          when QSPI_read_phase1 =>
            qspi_clock_int <= '0';
            qspi_state     <= QSPI_read_phase2;

          when QSPI_read_phase2 =>
            qspi_clock_int <= '1';
            qspi_state     <= QSPI_read_phase3;

          when QSPI_read_phase3 =>
            qspi_bits      <= qspi_db_in;
            qspi_clock_int <= '0';
            qspi_state     <= QSPI_read_phase4;

          when QSPI_read_phase4 =>
            report "QSPI read $" & to_hstring(qspi_bits) & to_hstring(qspi_db_in)
              & " into sector buffer @ $" & to_hstring(buf_offset);
            if qspi_verify_mode = '0' then
              -- Write to sector buffer slot $A00-$BFF ("101" prefix)
              buf_waddr_int          <= "101" & buf_offset;
              buf_wdata_int(7 downto 4) <= qspi_bits;
              buf_wdata_int(3 downto 0) <= qspi_db_in;
              buf_write_int          <= '1';
              if buf_offset = 0 then
                qspi_byte_value(7 downto 4) <= qspi_bits;
                qspi_byte_value(3 downto 0) <= qspi_db_in;
              else
                if qspi_byte_value(3 downto 0) /= qspi_db_in then
                  qspi_bytes_differ_int <= '1';
                elsif qspi_byte_value(7 downto 4) /= qspi_bits then
                  qspi_bytes_differ_int <= '1';
                end if;
              end if;
            else
              report "QSPI: Verifying: read $" & to_hstring(qspi_bits) & to_hstring(qspi_db_in)
                & " vs expected $" & to_hstring(buf_rdata);
              if (buf_rdata(3 downto 0) /= qspi_db_in) or
                 (buf_rdata(7 downto 4) /= qspi_bits) then
                qspi_bytes_differ_int <= '1';
              end if;
            end if;
            if buf_offset /= 511 then
              buf_offset <= buf_offset + 1;
              qspi_state <= QSPI_read_phase1;
            else
              qspi_state   <= Idle;
              qspi_csn     <= '1';
              qspi_csn_int <= '1';
            end if;
            qspi_clock_int <= '1';

          when QSPI_qwrite_512 =>
            qspidb_tristate <= '0';
            qspi_db_oe      <= '1';
            qspi_clock_int  <= '1';
            qspi_state      <= QSPI_qwrite_phase1;

          when QSPI_write_512 =>
            qspidb_tristate <= '0';
            qspi_db_oe      <= '1';
            qspi_clock_int  <= '1';
            buf_offset      <= to_unsigned(0, 9);
            qspi_state      <= QSPI_write_phase1;

          when QSPI_qwrite_256 =>
            qspidb_tristate <= '0';
            qspi_db_oe      <= '1';
            qspi_clock_int  <= '1';
            qspi_state      <= QSPI_qwrite_phase1;

          when QSPI_qwrite_16 =>
            qspidb_tristate <= '0';
            qspi_db_oe      <= '1';
            qspi_clock_int  <= '1';
            qspi_state      <= QSPI_qwrite_phase1;

          when QSPI_write_256 =>
            qspidb_tristate <= '0';
            qspi_db_oe      <= '1';
            qspi_clock_int  <= '1';
            buf_offset      <= to_unsigned(256, 9);
            qspi_state      <= QSPI_write_phase1;

          when QSPI_qwrite_phase1 =>
            report "QSPI: QUAD TX $" & to_hstring(buf_rdata) & " @ $" & to_hstring(buf_offset);
            qspi_state     <= QSPI_qwrite_phase2;
            qspi_db        <= buf_rdata(7 downto 4);
            qspi_bits      <= buf_rdata(3 downto 0);
            qspi_clock_int <= '0';

          when QSPI_qwrite_phase2 =>
            qspi_state     <= QSPI_qwrite_phase3;
            qspi_clock_int <= '1';

          when QSPI_qwrite_phase3 =>
            qspi_state     <= QSPI_qwrite_phase4;
            qspi_db        <= qspi_bits;
            qspi_clock_int <= '0';
            report "QSPI: Bump buf_offset from $" & to_hstring(buf_offset);
            if buf_offset /= 511 then
              buf_offset <= buf_offset + 1;
            else
              buf_offset <= to_unsigned(0, 9);
            end if;

          when QSPI_qwrite_phase4 =>
            qspi_clock_int <= '1';
            if buf_offset /= 0 then
              qspi_state <= QSPI_qwrite_phase1;
            else
              qspi_state <= Idle;
            end if;

          when QSPI_write_phase1 =>
            qspi_bit_counter <= 0;
            qspi_state       <= QSPI_write_phase2;

          when QSPI_write_phase2 =>
            if qspi_bit_counter = 0 then
              report "QSPI: Sending byte $" & to_hstring(buf_rdata);
              qspi_byte_value <= buf_rdata;
            end if;
            qspi_clock_int <= '0';
            qspi_state     <= QSPI_write_phase3;

          when QSPI_write_phase3 =>
            qspidb_tristate              <= '0';
            qspi_db_oe                   <= '1';
            qspi_db(3 downto 1)          <= "111";
            qspi_db(0)                   <= qspi_byte_value(7);
            report "QSPI: Writing bit " & std_logic'image(std_logic(qspi_byte_value(7)));
            qspi_byte_value(7 downto 1) <= qspi_byte_value(6 downto 0);
            qspi_state                   <= QSPI_write_phase4;

          when QSPI_write_phase4 =>
            qspi_clock_int <= '1';
            if qspi_bit_counter = 7 then
              if buf_offset /= 511 then
                buf_offset <= buf_offset + 1;
                qspi_state <= QSPI_write_phase1;
              else
                qspi_state <= Idle;
              end if;
            else
              qspi_bit_counter <= qspi_bit_counter + 1;
              qspi_state       <= QSPI_write_phase2;
            end if;

          when SPI_read_phase1 =>
            qspi_bit_counter <= 0;
            qspi_state       <= SPI_read_phase2;
            qspidb_tristate  <= '1';
            qspi_db_oe       <= '0';

          when SPI_read_phase2 =>
            qspi_clock_int <= '0';
            qspi_state     <= SPI_read_phase3;

          when SPI_read_phase3 =>
            qspi_byte_value(0)          <= qspi_db_in(1);
            report "QSPI: Reading bit " & std_logic'image(std_logic(qspi_db_in(1)));
            qspi_byte_value(7 downto 1) <= qspi_byte_value(6 downto 0);
            qspi_state                   <= SPI_read_phase4;

          when SPI_read_phase4 =>
            qspi_clock_int <= '1';
            if qspi_bit_counter = 7 then
              report "QSPI: SPI read byte $" & to_hstring(qspi_byte_value);
              -- Write to sector buffer slot $A00-$BFF ("101" prefix)
              buf_waddr_int <= "101" & buf_offset;
              buf_wdata_int <= qspi_byte_value;
              buf_write_int <= '1';
              if buf_offset /= 511 then
                buf_offset <= buf_offset + 1;
                qspi_state <= SPI_read_phase1;
              else
                qspi_state   <= Idle;
                qspi_csn     <= '1';
                qspi_csn_int <= '1';
              end if;
            else
              qspi_bit_counter <= qspi_bit_counter + 1;
              qspi_state       <= SPI_read_phase2;
            end if;

          when QSPI4_write_512 =>
            qspidb_tristate <= '1';
            qspi_db_oe      <= '0';
            buf_offset      <= to_unsigned(0, 9);
            qspi_state      <= QSPI4_write_phase1;

          when QSPI4_write_256 =>
            qspidb_tristate <= '1';
            qspi_db_oe      <= '0';
            buf_offset      <= to_unsigned(256, 9);
            qspi_state      <= QSPI4_write_phase1;

          when QSPI4_write_phase1 =>
            qspi_bit_counter <= 0;
            qspi_state       <= QSPI4_write_phase2;

          when QSPI4_write_phase2 =>
            if qspi_bit_counter = 0 then
              report "QSPI4: Sending byte $" & to_hstring(buf_rdata);
              qspi_byte_value <= buf_rdata;
            end if;
            -- XXX INCOMPLETE
            qspi_state <= Idle;

        end case;

      end if;
    end if;
  end process;

end behavioural;
