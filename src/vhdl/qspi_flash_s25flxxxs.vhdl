use work.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.debugtools.all;
use work.cputypes.all;

-- New QSPI flash controller.
--
-- Register map (fastio):
--   $D6C1 RO Status (bit 0 = error; bit 1 = initialization error; bit 2 = internal fault)
--            Poll $D680 bit 0 for busy.
--   $D6C2 RO Flash size in MB
--   $D6C3 RO Supported erase block sizes bitmask (bit 6 = 256K, bit 4 = 64K,
--                                                 bit 0 = 4K)
--
-- Actions (dispatched from sdcardio via action_strobe + action_byte):
--   $60  Initialize (auto-detects flash, enables quad mode)
--   $61  Read    (spi_address_in -> block_address, 512 bytes)
--   $62  Verify  (spi_address_in -> block_address, 512 bytes)
--   $63  Program (spi_address_in -> block_address, 512 bytes; hypervisor only)
--   $64  Erase 4K block   (spi_address_in -> block_address; hypervisor only)
--   $65  Erase 8K block   (RESERVED)
--   $66  Erase 16K block  (RESERVED)
--   $67  Erase 32K block  (RESERVED)
--   $68  Erase 64K block  (spi_address_in -> block_address; hypervisor only)
--   $69  Erase 128K block (RESERVED)
--   $6A  Erase 256K block (spi_address_in -> block_address; hypervisor only)
--
-- The sector buffer slot for QSPI is $A00-$BFF ("101" & offset[8:0]).

entity qspi_flash is
  port (
    clock           : in  std_logic;
    reset           : in  std_logic;  -- active low

    hypervisor_mode : in  std_logic;
    dipsw2          : in  std_logic;

    -- Action interface: sdcardio pulses action_strobe for one cycle when a
    -- QSPI action byte is written to $D680.  spi_address_in carries sd_sector
    -- at that moment.
    action_byte     : in  unsigned(7 downto 0);
    action_strobe   : in  std_logic;
    spi_address_in  : in  unsigned(31 downto 0);

    -- Status
    busy            : out std_logic;

    -- Sector buffer interface.
    -- buf_raddr drives f011_buffer_read_address in sdcardio (combinational).
    -- buf_write / buf_waddr / buf_wdata are registered; sdcardio applies them
    -- to f011_buffer_write* at the end of its clocked process.
    buf_rdata       : in  unsigned(7 downto 0);
    buf_raddr       : out unsigned(8 downto 0);
    buf_waddr       : out unsigned(11 downto 0);
    buf_wdata       : out unsigned(7 downto 0);
    buf_write       : out std_logic;

    -- Fastio registers: $D6C1, $D6C2, $D6C3
    fastio_cs       : in  std_logic;
    fastio_addr     : in  unsigned(7 downto 0);
    fastio_write    : in  std_logic;
    fastio_wdata    : in  unsigned(7 downto 0);
    fastio_rdata    : out unsigned(7 downto 0);

    -- Physical QSPI pins
    qspi_db         : out unsigned(3 downto 0);
    qspi_db_in      : in  unsigned(3 downto 0);
    qspi_db_oe      : out std_logic;
    qspi_csn        : out std_logic;
    qspi_clock      : out std_logic
  );
end qspi_flash;

architecture behavioural of qspi_flash is

  type dev_state_t is (
    UNINITIALIZED,
    IDLE,
    FLASH_READ,
    FLASH_VERIFY,
    FLASH_PROGRAM,
    FLASH_PROGRAM_STEP_0,
    FLASH_PROGRAM_STEP_1,
    FLASH_PROGRAM_STEP_2,
    FLASH_PROGRAM_STEP_3,
    FLASH_PROGRAM_STEP_4,
    FLASH_ERASE,
    FLASH_ERASE_STEP_0,
    FLASH_ERASE_STEP_1,
    FLASH_ERASE_STEP_2,
    FLASH_ERASE_STEP_3,
    FLASH_ERASE_STEP_4,
    FLASH_RESET,
    FLASH_RESET_STEP_0,
    FLASH_RESET_STEP_1,
    DELAY,
    READ_STATUS_REGISTER_1,
    STATUS_REGISTER_1_READ,
    READ_CONFIGURATION_REGISTER_1,
    CONFIGURATION_REGISTER_1_READ,
    ENABLE_QUAD_MODE,
    ENABLE_QUAD_MODE_STEP_0,
    ENABLE_QUAD_MODE_STEP_1,
    ENABLE_QUAD_MODE_STEP_2,
    WRITE_ENABLE,
    CLEAR_STATUS,
    CLEAR_STATUS_STEP_0,
    CLEAR_STATUS_STEP_1,
    CLEAR_STATUS_STEP_2,
    AWAIT_STATUS,
    AWAIT_STATUS_STEP_0,
    INITIALIZE,
    INITIALIZE_STEP_0,
    INITIALIZE_STEP_1,
    INITIALIZE_STEP_2,
    INITIALIZE_STEP_3,
    INITIALIZE_STEP_4,
    READ_ID,
    ID_READ,
    READ_ASP_REGISTER,
    ASP_REGISTER_READ,
    TRANSACTION,
    TRANSACTION_WRITE,
    TRANSACTION_READ,
    TRANSACTION_READ_QUAD,
    TRANSACTION_WRITE_QUAD,
    TRANSACTION_COMPLETE,
    IDLE_CLOCKS,
    IDLE_CLOCKS_STEP_0,
    WRITE_BYTE_X1_STEP_0,
    WRITE_BYTE_X1_STEP_1,
    READ_BYTE_X1_STEP_0,
    READ_BYTE_X1_STEP_1,
    WRITE_BYTE_X4_STEP_0,
    WRITE_BYTE_X4_STEP_1,
    WRITE_BYTE_X4_STEP_2,
    WRITE_BYTE_X4_STEP_3,
    READ_BYTE_X4_STEP_0,
    READ_BYTE_X4_STEP_1,
    READ_BYTE_X4_STEP_2,
    READ_BYTE_X4_STEP_3,
    INTERNAL_ERROR,
    ERROR_IDLE,
    ERROR_UNINITIALIZED,
    ERROR_INTERNAL_ERROR
  );

  signal dev_state : dev_state_t := UNINITIALIZED;

  type qspi_buffer_t is array(0 to 5) of unsigned(7 downto 0);

  signal qspi_rx_buffer : qspi_buffer_t;
  signal qspi_tx_buffer : qspi_buffer_t;

  type transaction_type_t is (
    TRANSACTION_X1,
    TRANSACTION_READ_X4,
    TRANSACTION_WRITE_X4
  );

  signal transaction_type : transaction_type_t := TRANSACTION_X1;

  signal post_clear_status_state     : dev_state_t;
  signal post_await_status_state     : dev_state_t;
  signal post_enable_quad_mode_state : dev_state_t;
  signal post_write_enable_state     : dev_state_t;
  signal post_read_id_state          : dev_state_t;
  signal post_read_asp_state         : dev_state_t;
  signal post_read_sr1_state         : dev_state_t;
  signal post_read_cr1_state         : dev_state_t;
  signal post_transaction_state      : dev_state_t;
  signal post_idle_clocks_state      : dev_state_t;
  signal post_delay_state            : dev_state_t;

  signal read_x1_num_bytes  : integer range 0 to 5;
  signal read_x4_num_bytes  : integer range 0 to 512;
  signal write_x1_num_bytes : integer range 0 to 6;
  signal write_x4_num_bytes : integer range 0 to 512;

  signal qspi_byte_counter     : integer range 0 to 512;
  signal qspi_bit_counter      : integer range 0 to 7;
  signal qspi_idle_clock_count : integer range 0 to 255;
  signal qspi_nibble           : unsigned(3 downto 0);

  signal delay_counter : integer range 0 to 4095;

  signal qspi_csn_int   : std_logic := '1';
  signal qspi_clock_int : std_logic := '1';
  signal qspi_db_oe_int : std_logic := '0';

  signal sr1 : unsigned(7 downto 0);
  signal cr1 : unsigned(7 downto 0);

  type flash_id_t is array(0 to 4) of unsigned(7 downto 0);
  signal flash_id                   : flash_id_t;
  signal flash_size                 : integer range 0 to 255;
  signal flash_latency_cycles       : integer range 0 to 15;
  signal flash_uniform_256k_sectors : std_logic := '0';
  signal flash_page_size_512        : std_logic := '0';
  signal flash_dyb_lock_boot        : std_logic := '0';

  signal flash_erase_block_size : unsigned(7 downto 0);

  signal block_address     : unsigned(31 downto 0);
  signal block_address_int : unsigned(31 downto 0);

  signal dev_write       : std_logic := '0';
  signal dev_waddr       : integer range 0 to 511;
  signal dev_raddr       : integer range 0 to 511;
  signal dev_rdata       : unsigned(7 downto 0);
  signal dev_wdata       : unsigned(7 downto 0);
  signal dev_read_to_mem : std_logic;
  signal qspi_read_addr  : integer range 0 to 512;
  signal dev_error       : std_logic;
  signal dev_busy        : std_logic;

begin

  dev_busy   <= '0' when dev_state = IDLE or dev_state = UNINITIALIZED or dev_state = INTERNAL_ERROR else '1';
  busy       <= dev_busy;
  dev_rdata  <= buf_rdata;
  buf_raddr  <= to_unsigned(dev_raddr, 9);
  buf_waddr  <= "101" & to_unsigned(dev_waddr, 9);
  buf_wdata  <= dev_wdata;
  buf_write  <= dev_write;
  qspi_csn   <= qspi_csn_int;
  qspi_clock <= qspi_clock_int;
  qspi_db_oe <= qspi_db_oe_int;

  -- Combinational fastio read
  process (fastio_cs, fastio_addr, fastio_write,
           dev_error, dev_state,
           flash_size, flash_uniform_256k_sectors) is
  begin
    fastio_rdata <= (others => 'Z');
    if fastio_cs = '1' and fastio_write = '0' then
      case fastio_addr is
        when x"C1" =>
          -- @IO:GS $D6C1 QSPI:STATUS QSPI status (bit 0=error, bit 1=initialization error, bit 2=internal fault)
          -- Note: busy is not reported here; poll $D680 bit 0 instead.
          fastio_rdata    <= (others => '0');
          if dev_state = INTERNAL_ERROR then
            fastio_rdata(2) <= '1';
          end if;
          if dev_state = UNINITIALIZED then
            fastio_rdata(1) <= '1';
          end if;
          fastio_rdata(0) <= dev_error;
        when x"C2" =>
          -- @IO:GS $D6C2 QSPI:FLASHSIZE Flash size in MB (read only)
          fastio_rdata <= to_unsigned(flash_size, 8);
        when x"C3" =>
          -- @IO:GS $D6C3 QSPI:ERASEBLK Erase block size (bit 6=256K, bit 4=64K, bit 0=4K)
          fastio_rdata <= (others => '0');
          if flash_uniform_256k_sectors = '1' then
            -- Uniform 256K sector architecture.
            fastio_rdata(6) <= '1';
          else
            -- Mixed 64K/4K sector architecture.
            fastio_rdata(4) <= '1';
            fastio_rdata(0) <= '1';
          end if;
        when others =>
          null;
      end case;
    end if;
  end process;

  process (clock) is
  begin

    if rising_edge(clock) then

      -- Reset.
      if reset = '0' then
        dev_state <= FLASH_RESET;
        block_address <= (others => '0');
        dev_error <= '0';
        dev_write <= '0';
        dev_read_to_mem <= '0';
        flash_erase_block_size <= x"10";
        qspi_csn_int   <= '1';
        qspi_clock_int <= '1';
        qspi_db_oe_int <= '0';
      else
        dev_write <= '0';

        -- Action dispatch from $D680 in sdcardio.
        -- Strobes while busy are silently ignored; the active operation continues.
        if action_strobe = '1' and dev_busy = '0' then
          if dev_state = UNINITIALIZED then
            -- Only initialize ($60) is accepted when uninitialized.
            if action_byte = x"60" then
              dev_error <= '0';
              dev_state <= FLASH_RESET;
            else
              dev_state <= ERROR_UNINITIALIZED;
            end if;
          elsif dev_state = IDLE then
            dev_error <= '0';
            case action_byte is
              when x"60" =>  -- Initialize
                dev_state <= FLASH_RESET;
              when x"61" =>  -- Read
                block_address <= spi_address_in;
                dev_state     <= FLASH_READ;
              when x"62" =>  -- Verify
                block_address <= spi_address_in;
                dev_state     <= FLASH_VERIFY;
              when x"63" =>  -- Program (hypervisor only)
                if hypervisor_mode = '1' or dipsw2 = '1' then
                  block_address <= spi_address_in;
                  dev_state     <= FLASH_PROGRAM;
                else
                  dev_state <= ERROR_IDLE;
                end if;
              when x"64" =>  -- Erase 4K (hypervisor only)
                if hypervisor_mode = '1' or dipsw2 = '1' then
                  block_address          <= spi_address_in;
                  flash_erase_block_size <= x"01";
                  dev_state              <= FLASH_ERASE;
                else
                  dev_state <= ERROR_IDLE;
                end if;
              when x"68" =>  -- Erase 64K (hypervisor only)
                if hypervisor_mode = '1' or dipsw2 = '1' then
                  block_address          <= spi_address_in;
                  flash_erase_block_size <= x"10";
                  dev_state              <= FLASH_ERASE;
                else
                  dev_state <= ERROR_IDLE;
                end if;
              when x"6A" =>  -- Erase 256K (hypervisor only)
                if hypervisor_mode = '1' or dipsw2 = '1' then
                  block_address          <= spi_address_in;
                  flash_erase_block_size <= x"40";
                  dev_state              <= FLASH_ERASE;
                else
                  dev_state <= ERROR_IDLE;
                end if;
              when others =>
                dev_state <= ERROR_IDLE;
            end case;
          end if;
        end if;

        case dev_state is

          when UNINITIALIZED =>
            null;

          when IDLE =>
            null;

          when FLASH_READ | FLASH_VERIFY =>

            if dev_state = FLASH_READ then
              dev_read_to_mem <= '1';
            else
              dev_read_to_mem <= '0';
            end if;

            read_x4_num_bytes <= 512;

            qspi_tx_buffer(0) <= x"6c";
            qspi_tx_buffer(1) <= block_address(31 downto 24);
            qspi_tx_buffer(2) <= block_address(23 downto 16);
            qspi_tx_buffer(3) <= block_address(15 downto 8);
            qspi_tx_buffer(4) <= block_address(7 downto 0);
            write_x1_num_bytes <= 5;
            transaction_type <= TRANSACTION_READ_X4;
            post_transaction_state <= IDLE;
            dev_state <= TRANSACTION;

          when FLASH_PROGRAM =>

            post_write_enable_state <= FLASH_PROGRAM_STEP_0;
            post_clear_status_state <= WRITE_ENABLE;
            dev_state <= CLEAR_STATUS;

          when FLASH_PROGRAM_STEP_0 =>

            qspi_tx_buffer(0) <= x"34";
            qspi_tx_buffer(1) <= block_address(31 downto 24);
            qspi_tx_buffer(2) <= block_address(23 downto 16);
            qspi_tx_buffer(3) <= block_address(15 downto 8);
            qspi_tx_buffer(4) <= block_address(7 downto 0);
            write_x1_num_bytes <= 5;
            qspi_read_addr <= 0;
            transaction_type <= TRANSACTION_WRITE_X4;
            dev_state <= TRANSACTION;

            if flash_page_size_512 = '1' then
              -- 512-byte page buffer: write all 512 bytes in a single transaction.
              write_x4_num_bytes <= 512;
              post_transaction_state <= FLASH_PROGRAM_STEP_4;
            else
              -- 256-byte page buffer: write first 256 bytes.
              write_x4_num_bytes <= 256;
              block_address_int <= block_address + x"100";
              post_transaction_state <= FLASH_PROGRAM_STEP_1;
            end if;

          when FLASH_PROGRAM_STEP_1 =>

            -- First 256-byte write done; wait, then write the remainder.
            post_await_status_state <= FLASH_PROGRAM_STEP_2;
            dev_state <= AWAIT_STATUS;

          when FLASH_PROGRAM_STEP_2 =>

            post_write_enable_state <= FLASH_PROGRAM_STEP_3;
            post_clear_status_state <= WRITE_ENABLE;
            dev_state <= CLEAR_STATUS;

          when FLASH_PROGRAM_STEP_3 =>

            write_x4_num_bytes <= 256;

            qspi_tx_buffer(0) <= x"34";
            qspi_tx_buffer(1) <= block_address_int(31 downto 24);
            qspi_tx_buffer(2) <= block_address_int(23 downto 16);
            qspi_tx_buffer(3) <= block_address_int(15 downto 8);
            qspi_tx_buffer(4) <= block_address_int(7 downto 0);
            write_x1_num_bytes <= 5;
            qspi_read_addr <= 256;
            transaction_type <= TRANSACTION_WRITE_X4;
            post_transaction_state <= FLASH_PROGRAM_STEP_4;
            dev_state <= TRANSACTION;

          when FLASH_PROGRAM_STEP_4 =>

            post_await_status_state <= IDLE;
            dev_state <= AWAIT_STATUS;

          when FLASH_ERASE =>

            -- Only 256K, 64K, and 4K erase block sizes are supported.
            if flash_erase_block_size /= x"40" and flash_erase_block_size /= x"10" and flash_erase_block_size /= x"01" then
              dev_state <= ERROR_IDLE;
            -- Unsupported erase block sizes: 256K on a mixed 64K/4K chip,
            --  non-256K on a uniform 256K chip.
            elsif (flash_erase_block_size(6) /= flash_uniform_256k_sectors) then
              dev_state <= ERROR_IDLE;
            -- DYB lock boot with 64K/4K mixed architecture: not supported.
            elsif flash_dyb_lock_boot = '1' and flash_uniform_256k_sectors = '0' then
              dev_state <= ERROR_IDLE;
            -- DYB lock boot with 256K architecture: unprotect sector first.
            elsif flash_dyb_lock_boot = '1' then
              post_write_enable_state <= FLASH_ERASE_STEP_0;
              post_clear_status_state <= WRITE_ENABLE;
              dev_state <= CLEAR_STATUS;
            else
              dev_state <= FLASH_ERASE_STEP_2;
            end if;

          when FLASH_ERASE_STEP_0 =>

            -- Write DYB to unprotect the 256K sector (0xE1 + aligned address
            -- + 0xFF).  Address is aligned to 256K boundary (bits 17:0 = 0).
            qspi_tx_buffer(0) <= x"e1";
            qspi_tx_buffer(1) <= block_address(31 downto 24);
            qspi_tx_buffer(2) <= block_address(23 downto 18) & "00";
            qspi_tx_buffer(3) <= x"00";
            qspi_tx_buffer(4) <= x"00";
            qspi_tx_buffer(5) <= x"ff";  -- protect = FALSE
            write_x1_num_bytes <= 6;
            read_x1_num_bytes <= 0;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= FLASH_ERASE_STEP_1;
            dev_state <= TRANSACTION;

          when FLASH_ERASE_STEP_1 =>

            post_await_status_state <= FLASH_ERASE_STEP_2;
            dev_state <= AWAIT_STATUS;

          when FLASH_ERASE_STEP_2 =>

            -- Clear status and enable writes before issuing the erase command.
            post_write_enable_state <= FLASH_ERASE_STEP_3;
            post_clear_status_state <= WRITE_ENABLE;
            dev_state <= CLEAR_STATUS;

          when FLASH_ERASE_STEP_3 =>

            -- 4K parameter sector erase uses 0x21; 64K and 256K both use 0xDC.
            if flash_erase_block_size(0) = '1' then
              qspi_tx_buffer(0) <= x"21";
            else
              qspi_tx_buffer(0) <= x"dc";
            end if;
            qspi_tx_buffer(1) <= block_address(31 downto 24);
            qspi_tx_buffer(2) <= block_address(23 downto 16);
            qspi_tx_buffer(3) <= block_address(15 downto 8);
            qspi_tx_buffer(4) <= block_address(7 downto 0);
            write_x1_num_bytes <= 5;
            read_x1_num_bytes <= 0;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= FLASH_ERASE_STEP_4;
            dev_state <= TRANSACTION;

          when FLASH_ERASE_STEP_4 =>

            post_await_status_state <= IDLE;
            dev_state <= AWAIT_STATUS;

          when FLASH_RESET =>

            qspi_idle_clock_count <= 255;
            post_idle_clocks_state <= FLASH_RESET_STEP_0;
            dev_state <= IDLE_CLOCKS;

          when FLASH_RESET_STEP_0 =>

            -- S25FLxxxS uses a single-byte software reset (0xF0), unlike the
            -- S25FLxxxL which requires a two-byte Reset Enable (0x66) / Reset
            -- Memory (0x99) sequence.
            qspi_tx_buffer(0) <= x"f0";
            write_x1_num_bytes <= 1;
            read_x1_num_bytes <= 0;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= FLASH_RESET_STEP_1;
            dev_state <= TRANSACTION;

          when FLASH_RESET_STEP_1 =>

            delay_counter <= 4095;
            post_delay_state <= INITIALIZE;
            dev_state <= DELAY;

          when DELAY =>

            if delay_counter = 0 then
              dev_state <= post_delay_state;
            else
              delay_counter <= delay_counter - 1;
            end if;

          when INITIALIZE =>

            post_read_id_state <= INITIALIZE_STEP_0;
            dev_state <= READ_ID;

          when INITIALIZE_STEP_0 =>

            post_read_cr1_state <= INITIALIZE_STEP_1;
            dev_state <= READ_CONFIGURATION_REGISTER_1;

          when INITIALIZE_STEP_1 =>

            -- Check manufacturer ID (Cypress/Spansion = 0x01).
            if flash_id(0) /= x"01" then
              dev_state <= ERROR_UNINITIALIZED;

            -- Check sector architecture byte (flash_id(4)):
            --   0x00 = uniform 256K sectors, 512-byte page buffer
            --   0x01 = mixed 4K/64K sectors,  256-byte page buffer
            elsif flash_id(4) /= x"00" and flash_id(4) /= x"01" then
              dev_state <= ERROR_UNINITIALIZED;

            -- Check type + density bytes for known models.
            elsif not ((flash_id(1) = x"20" and flash_id(2) = x"18") or
                       (flash_id(1) = x"02" and flash_id(2) = x"19") or
                       (flash_id(1) = x"02" and flash_id(2) = x"20")) then
              dev_state <= ERROR_UNINITIALIZED;

            else
              -- Set flash size in MB.
              if flash_id(2) = x"18" then
                flash_size <= 16;
              elsif flash_id(2) = x"19" then
                flash_size <= 32;
              else
                flash_size <= 64;
              end if;

              -- Set page buffer size from sector architecture byte.
              if flash_id(4) = x"00" then
                -- Uniform 256K sectors, 512-byte page buffer.
                flash_uniform_256k_sectors <= '1';
                flash_page_size_512 <= '1';
              else
                -- Mixed 4K/64K sectors, 256-byte page buffer.
                flash_uniform_256k_sectors <= '0';
                flash_page_size_512 <= '0';
              end if;

              -- Latency cycles from CR1[7:6]: 0 if "11" (power-on default),
              -- else 8.
              if cr1(7 downto 6) = "11" then
                flash_latency_cycles <= 0;
              else
                flash_latency_cycles <= 8;
              end if;

              -- Read ASPR to determine DYB lock boot status before proceeding.
              post_read_asp_state <= INITIALIZE_STEP_2;
              dev_state <= READ_ASP_REGISTER;
            end if;

          when INITIALIZE_STEP_2 =>

            if cr1(1) = '0' then
              post_enable_quad_mode_state <= INITIALIZE_STEP_3;
              dev_state <= ENABLE_QUAD_MODE;
            else
              dev_state <= IDLE;
            end if;

          when INITIALIZE_STEP_3 =>

            post_read_cr1_state <= INITIALIZE_STEP_4;
            dev_state <= READ_CONFIGURATION_REGISTER_1;

          when INITIALIZE_STEP_4 =>

            if cr1(1) = '0' then
              dev_state <= ERROR_UNINITIALIZED;
            else
              dev_state <= IDLE;
            end if;

          when READ_ID =>

            -- S25FLxxxS RDID returns 5 bytes (manufacturer, type, density,
            -- reserved, sector architecture).
            qspi_tx_buffer(0) <= x"9f";
            write_x1_num_bytes <= 1;
            read_x1_num_bytes <= 5;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= ID_READ;
            dev_state <= TRANSACTION;

          when ID_READ =>

            flash_id(0) <= qspi_rx_buffer(0);
            flash_id(1) <= qspi_rx_buffer(1);
            flash_id(2) <= qspi_rx_buffer(2);
            flash_id(3) <= qspi_rx_buffer(3);
            flash_id(4) <= qspi_rx_buffer(4);
            dev_state <= post_read_id_state;

          when READ_ASP_REGISTER =>

            -- ASP register (0x2B): returns 2 bytes, low byte first.
            qspi_tx_buffer(0) <= x"2b";
            write_x1_num_bytes <= 1;
            read_x1_num_bytes <= 2;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= ASP_REGISTER_READ;
            dev_state <= TRANSACTION;

          when ASP_REGISTER_READ =>

            -- ASPR[4] = 0 means DYB lock boot protection is enabled.
            flash_dyb_lock_boot <= not qspi_rx_buffer(0)(4);
            dev_state <= post_read_asp_state;

          when ENABLE_QUAD_MODE =>

            -- Read CR1 first to capture the value we'll preserve in WRR.
            post_read_cr1_state <= ENABLE_QUAD_MODE_STEP_0;
            dev_state <= READ_CONFIGURATION_REGISTER_1;

          when ENABLE_QUAD_MODE_STEP_0 =>

            -- S25FLxxxS requires clear_status + write_enable before WRR,
            -- instead of the S25FLxxxL's volatile write enable (0x50).
            post_write_enable_state <= ENABLE_QUAD_MODE_STEP_1;
            post_clear_status_state <= WRITE_ENABLE;
            dev_state <= CLEAR_STATUS;

          when ENABLE_QUAD_MODE_STEP_1 =>

            -- Read SR1 here, after clear_status + write_enable, so the value
            -- written in WRR reflects the current state (error bits cleared,
            -- protection bits preserved).
            post_read_sr1_state <= ENABLE_QUAD_MODE_STEP_2;
            dev_state <= READ_STATUS_REGISTER_1;

          when ENABLE_QUAD_MODE_STEP_2 =>

            qspi_tx_buffer(0) <= x"01";
            qspi_tx_buffer(1) <= sr1;
            qspi_tx_buffer(2) <= cr1(7 downto 2) & "1" & cr1(0);
            write_x1_num_bytes <= 3;
            read_x1_num_bytes <= 0;
            transaction_type <= TRANSACTION_X1;
            post_await_status_state <= post_enable_quad_mode_state;
            post_transaction_state <= AWAIT_STATUS;
            dev_state <= TRANSACTION;

          when WRITE_ENABLE =>

            qspi_tx_buffer(0) <= x"06";
            write_x1_num_bytes <= 1;
            read_x1_num_bytes <= 0;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= post_write_enable_state;
            dev_state <= TRANSACTION;

          when READ_STATUS_REGISTER_1 =>

            qspi_tx_buffer(0) <= x"05";
            write_x1_num_bytes <= 1;
            read_x1_num_bytes <= 1;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= STATUS_REGISTER_1_READ;
            dev_state <= TRANSACTION;

          when STATUS_REGISTER_1_READ =>

            sr1 <= qspi_rx_buffer(0);
            dev_state <= post_read_sr1_state;

          when READ_CONFIGURATION_REGISTER_1 =>

            qspi_tx_buffer(0) <= x"35";
            write_x1_num_bytes <= 1;
            read_x1_num_bytes <= 1;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= CONFIGURATION_REGISTER_1_READ;
            dev_state <= TRANSACTION;

          when CONFIGURATION_REGISTER_1_READ =>

            cr1 <= qspi_rx_buffer(0);
            dev_state <= post_read_cr1_state;

          when CLEAR_STATUS =>

            post_read_sr1_state <= CLEAR_STATUS_STEP_0;
            dev_state <= READ_STATUS_REGISTER_1;

          when CLEAR_STATUS_STEP_0 =>

            -- As long as error occurred or write in progress: clear status.
            -- S25FLxxxS: E_ERR = SR1[5], P_ERR = SR1[6] (not SR2 as in xxxL).
            if sr1(0) = '1' or sr1(5) = '1' or sr1(6) = '1' then
              qspi_tx_buffer(0) <= x"30";
              write_x1_num_bytes <= 1;
              read_x1_num_bytes <= 0;
              transaction_type <= TRANSACTION_X1;
              post_transaction_state <= CLEAR_STATUS;
              dev_state <= TRANSACTION;
            else
              dev_state <= CLEAR_STATUS_STEP_1;
            end if;

          when CLEAR_STATUS_STEP_1 =>

            post_read_sr1_state <= CLEAR_STATUS_STEP_2;
            dev_state <= READ_STATUS_REGISTER_1;

          when CLEAR_STATUS_STEP_2 =>

            -- As long as write enabled, write disable.
            if sr1(1) = '1' then
              qspi_tx_buffer(0) <= x"04";
              write_x1_num_bytes <= 1;
              read_x1_num_bytes <= 0;
              transaction_type <= TRANSACTION_X1;
              post_transaction_state <= CLEAR_STATUS_STEP_1;
              dev_state <= TRANSACTION;
            else
              dev_state <= post_clear_status_state;
            end if;

          when AWAIT_STATUS =>

            post_read_sr1_state <= AWAIT_STATUS_STEP_0;
            dev_state <= READ_STATUS_REGISTER_1;

          when AWAIT_STATUS_STEP_0 =>

            -- Wait until no write in progress and write disabled.
            if sr1(0) = '1' or sr1(1) = '1' then
              -- If an error occurred, clear status and set operation error flag.
              -- S25FLxxxS: E_ERR = SR1[5], P_ERR = SR1[6] (not SR2 as in xxxL).
              if sr1(5) = '1' or sr1(6) = '1' then
                post_clear_status_state <= ERROR_IDLE;
                dev_state <= CLEAR_STATUS;
              else
                dev_state <= AWAIT_STATUS;
              end if;
            else
              dev_state <= post_await_status_state;
            end if;

          when TRANSACTION =>

            qspi_csn_int  <= '0';
            qspi_clock_int <= '1';
            qspi_db_oe_int <= '0';

            qspi_byte_counter <= 0;
            dev_state <= TRANSACTION_WRITE;

          when TRANSACTION_WRITE =>

            qspi_db_oe_int <= '1';

            if qspi_byte_counter = write_x1_num_bytes then

              qspi_byte_counter <= 0;

              -- There are three possibilities here.
              -- 1) Read bytes to internal buffer (X1).
              -- 2) Wait latency cycles, then read bytes to shared buffer (X4).
              -- 3) Write bytes from shared buffer (X4).
              if transaction_type = TRANSACTION_X1 then
                qspi_db_oe_int <= '0';
                dev_state <= TRANSACTION_READ;

              elsif transaction_type = TRANSACTION_READ_X4 then
                qspi_db_oe_int <= '0';
                qspi_idle_clock_count <= flash_latency_cycles;
                post_idle_clocks_state <= TRANSACTION_READ_QUAD;
                dev_state <= IDLE_CLOCKS;

              elsif transaction_type = TRANSACTION_WRITE_X4 then
                dev_raddr <= qspi_read_addr;  -- pre-fetch: present address now so data is ready one cycle later
                dev_state <= TRANSACTION_WRITE_QUAD;
              else
                dev_state <= ERROR_INTERNAL_ERROR;
              end if;
            else
              --qspi_byte <= qspi_tx_buffer(qspi_byte_counter);
              qspi_bit_counter <= 7;
              dev_state <= WRITE_BYTE_X1_STEP_0;
            end if;

          when TRANSACTION_READ =>

            if qspi_byte_counter = read_x1_num_bytes then
              dev_state <= TRANSACTION_COMPLETE;
            else
              qspi_bit_counter <= 7;
              dev_state <= READ_BYTE_X1_STEP_0;
            end if;

          when TRANSACTION_READ_QUAD =>

            if qspi_byte_counter = read_x4_num_bytes then
              dev_state <= TRANSACTION_COMPLETE;
            else
              dev_state <= READ_BYTE_X4_STEP_0;
            end if;

          when TRANSACTION_WRITE_QUAD =>

            if qspi_byte_counter = write_x4_num_bytes then
              dev_state <= TRANSACTION_COMPLETE;
            else
              dev_state <= WRITE_BYTE_X4_STEP_0;
            end if;

          when TRANSACTION_COMPLETE =>

            qspi_csn_int  <= '1';
            qspi_clock_int <= '1';
            qspi_db_oe_int <= '0';

            dev_state <= post_transaction_state;

          when IDLE_CLOCKS =>

            if qspi_idle_clock_count = 0 then
              dev_state <= post_idle_clocks_state;
            else
              qspi_clock_int <= '0';
              dev_state <= IDLE_CLOCKS_STEP_0;
            end if;

          when IDLE_CLOCKS_STEP_0 =>

            qspi_clock_int <= '1';
            qspi_idle_clock_count <= qspi_idle_clock_count - 1;
            dev_state <= IDLE_CLOCKS;

          when WRITE_BYTE_X1_STEP_0 =>

            qspi_clock_int <= '0';
            qspi_db <= "111" & qspi_tx_buffer(qspi_byte_counter)(qspi_bit_counter);
            dev_state <= WRITE_BYTE_X1_STEP_1;

          when WRITE_BYTE_X1_STEP_1 =>

            qspi_clock_int <= '1';
            if qspi_bit_counter = 0 then
              qspi_byte_counter <= qspi_byte_counter + 1;
              dev_state <= TRANSACTION_WRITE;
            else
              qspi_bit_counter <= qspi_bit_counter - 1;
              dev_state <= WRITE_BYTE_X1_STEP_0;
            end if;

          when READ_BYTE_X1_STEP_0 =>

            qspi_clock_int <= '0';
            dev_state <= READ_BYTE_X1_STEP_1;

          when READ_BYTE_X1_STEP_1 =>

            qspi_rx_buffer(qspi_byte_counter)(qspi_bit_counter) <= qspi_db_in(1);
            qspi_clock_int <= '1';

            if qspi_bit_counter = 0 then
              qspi_byte_counter <= qspi_byte_counter + 1;
              dev_state <= TRANSACTION_READ;
            else
              qspi_bit_counter <= qspi_bit_counter - 1;
              dev_state <= READ_BYTE_X1_STEP_0;
            end if;

          when WRITE_BYTE_X4_STEP_0 =>

            qspi_clock_int <= '0';
            qspi_db  <= dev_rdata(7 downto 4);
            dev_state   <= WRITE_BYTE_X4_STEP_1;

          when WRITE_BYTE_X4_STEP_1 =>

            qspi_clock_int <= '1';
            dev_state <= WRITE_BYTE_X4_STEP_2;

          when WRITE_BYTE_X4_STEP_2 =>

            qspi_clock_int <= '0';
            qspi_db  <= dev_rdata(3 downto 0);
            dev_state <= WRITE_BYTE_X4_STEP_3;

          when WRITE_BYTE_X4_STEP_3 =>

            qspi_clock_int <= '1';
            qspi_byte_counter <= qspi_byte_counter + 1;
            qspi_read_addr <= qspi_read_addr + 1;
            dev_raddr <= qspi_read_addr + 1;  -- pre-fetch next byte; RHS uses old qspi_read_addr
            dev_state <= TRANSACTION_WRITE_QUAD;

          when READ_BYTE_X4_STEP_0 =>

            dev_state <= READ_BYTE_X4_STEP_1;
            qspi_clock_int <= '0';

            dev_raddr <= qspi_byte_counter;

          when READ_BYTE_X4_STEP_1 =>

            dev_state <= READ_BYTE_X4_STEP_2;
            qspi_nibble <= qspi_db_in;
            qspi_clock_int <= '1';

            -- NOTE: dev_rdata is NOT valid here yet. The RAM (ram8x4096_sync) has
            -- a 1-cycle registered output: dev_raddr was set in STEP_0 (edge T), so
            -- the RAM registers rdata at edge T+1 (this step). The updated dev_rdata
            -- will only be stable from STEP_2 onwards. The mismatch comparison is
            -- therefore deferred to STEP_3 where dev_rdata is guaranteed valid.

          when READ_BYTE_X4_STEP_2 =>

            dev_state <= READ_BYTE_X4_STEP_3;
            qspi_clock_int <= '0';

          when READ_BYTE_X4_STEP_3 =>

            if dev_read_to_mem = '1' then
              dev_waddr <= qspi_byte_counter;
              dev_wdata(7 downto 4) <= qspi_nibble;
              dev_wdata(3 downto 0) <= qspi_db_in;
              dev_write <= '1';
            end if;

            -- dev_rdata is valid here (2 cycles after dev_raddr was set in STEP_0).
            -- In verify mode, compare both nibbles of the buffer byte against the
            -- flash nibbles. On mismatch, redirect the transaction to ERROR_IDLE so
            -- the bus is closed cleanly before reporting the error.
            if dev_read_to_mem = '0' then
              if dev_rdata(7 downto 4) /= qspi_nibble or dev_rdata(3 downto 0) /= qspi_db_in then
                post_transaction_state <= ERROR_IDLE;
              end if;
            end if;

            qspi_clock_int <= '1';
            qspi_byte_counter <= qspi_byte_counter + 1;
            dev_state <= TRANSACTION_READ_QUAD;

          when INTERNAL_ERROR =>
            null;

          when ERROR_IDLE =>
            dev_error <= '1';
            dev_state <= IDLE;

          when ERROR_UNINITIALIZED =>
            dev_error <= '1';
            dev_state <= UNINITIALIZED;

          when ERROR_INTERNAL_ERROR =>
            dev_error <= '1';
            dev_state <= INTERNAL_ERROR;

          when others =>
            dev_state <= ERROR_INTERNAL_ERROR;

        end case;
      end if;
    end if;
  end process;

end behavioural;
