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
--   $D6C2 RO Flash size in MB
--   $D6C3 RO Erase block size (bit 4 = 64K, bit 3 = 32K, bit 0 = 4K)
--   $D6CC RO Status (bit 4 = block mismatch, bit 3 = internal fault,
--                    bit 2 = initialization error, bit 1 = operation error,
--                    bit 0 = busy)
--   $D6CD RW Size low byte (bits 7:0 of transfer size in bytes)
--   $D6CE RW Size high byte (bits 1:0, for values up to 512)
--
-- Actions (dispatched from sdcardio via action_strobe + action_byte):
--   $50  Initialize (auto-detects flash, enables quad mode)
--   $51  Read    (spi_address_in -> block_address, size from $D6CD/$D6CE)
--   $52  Program (spi_address_in -> block_address, size from $D6CD/$D6CE; hypervisor only)
--   $53  Verify  (spi_address_in -> block_address, size from $D6CD/$D6CE)
--   $54  Erase 4K sector  (spi_address_in -> block_address; hypervisor only)
--   $55  Erase 32K block  (spi_address_in -> block_address; hypervisor only)
--   $56  Erase 64K page   (spi_address_in -> block_address; hypervisor only)
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

    -- Fastio registers: $D6C2, $D6C3, $D6CC, $D6CD, $D6CE
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
    FLASH_RESET,
    FLASH_RESET_STEP_0,
    FLASH_RESET_STEP_1,
    FLASH_RESET_STEP_2,
    DELAY,
    READ_STATUS,
    READ_STATUS_STEP_0,
    READ_STATUS_REGISTER_1,
    STATUS_REGISTER_1_READ,
    READ_STATUS_REGISTER_2,
    STATUS_REGISTER_2_READ,
    READ_CONFIGURATION_REGISTER_1,
    CONFIGURATION_REGISTER_1_READ,
    READ_CONFIGURATION_REGISTER_2,
    CONFIGURATION_REGISTER_2_READ,
    READ_CONFIGURATION_REGISTER_3,
    CONFIGURATION_REGISTER_3_READ,
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
    REJECTED
  );

  signal dev_state : dev_state_t := UNINITIALIZED;

  type qspi_buffer_t is array(0 to 4) of unsigned(7 downto 0);

  signal qspi_rx_buffer : qspi_buffer_t;
  signal qspi_tx_buffer : qspi_buffer_t;

  type transaction_type_t is (
    TRANSACTION_X1,
    TRANSACTION_READ_X4,
    TRANSACTION_WRITE_X4
  );

  signal transaction_type : transaction_type_t := TRANSACTION_X1;

  signal post_rejected_state         : dev_state_t := UNINITIALIZED;
  signal post_read_status_state      : dev_state_t;
  signal post_clear_status_state     : dev_state_t;
  signal post_await_status_state     : dev_state_t;
  signal post_enable_quad_mode_state : dev_state_t;
  signal post_write_enable_state     : dev_state_t;
  signal post_read_id_state          : dev_state_t;
  signal post_read_sr1_state         : dev_state_t;
  signal post_read_sr2_state         : dev_state_t;
  signal post_read_cr1_state         : dev_state_t;
  signal post_read_cr2_state         : dev_state_t;
  signal post_read_cr3_state         : dev_state_t;
  signal post_transaction_state      : dev_state_t;
  signal post_idle_clocks_state      : dev_state_t;
  signal post_delay_state            : dev_state_t;

  signal read_x1_num_bytes  : integer range 0 to 5;
  signal read_x4_num_bytes  : integer range 0 to 512;
  signal write_x1_num_bytes : integer range 0 to 5;
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
  signal sr2 : unsigned(7 downto 0);
  signal cr1 : unsigned(7 downto 0);
  signal cr2 : unsigned(7 downto 0);
  signal cr3 : unsigned(7 downto 0);

  type flash_id_t is array(0 to 2) of unsigned(7 downto 0);
  signal flash_id             : flash_id_t;
  signal flash_size           : integer range 0 to 255;
  signal flash_latency_cycles : integer range 0 to 15;

  -- Erase block size in multiples of 4K (bit 4 = 64K, bit 3 = 32K, bit 0 = 4K).
  signal flash_erase_block_size : unsigned(7 downto 0);
  signal flash_erase_command    : unsigned(7 downto 0);

  signal block_size        : unsigned(15 downto 0);
  signal block_address     : unsigned(31 downto 0);
  signal block_address_int : unsigned(31 downto 0);
  signal block_mismatch    : std_logic := '0';

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
           dev_busy, dev_error, block_mismatch, dev_state,
           flash_size, flash_erase_block_size, block_size) is
  begin
    fastio_rdata <= (others => 'Z');
    if fastio_cs = '1' and fastio_write = '0' then
      case fastio_addr is
        when x"C2" =>
          -- @IO:GS $D6C2 QSPI:FLASHSIZE Flash size in MB (read only)
          fastio_rdata <= to_unsigned(flash_size, 8);
        when x"C3" =>
          -- @IO:GS $D6C3 QSPI:ERASEBLK Erase block size (bit 4=64K, bit 3=32K, bit 0=4K)
          fastio_rdata <= flash_erase_block_size;
        when x"CC" =>
          -- @IO:GS $D6CC QSPI:STATUS QSPI status (bit 4=block mismatch, bit 3=fault, bit 2=init error, bit 1=op error, bit 0=busy)
          fastio_rdata    <= (others => '0');
          fastio_rdata(4) <= block_mismatch;
          if dev_state = INTERNAL_ERROR then
            fastio_rdata(3) <= '1';
          end if;
          if dev_state = UNINITIALIZED then
            fastio_rdata(2) <= '1';
          end if;
          fastio_rdata(1) <= dev_error;
          fastio_rdata(0) <= dev_busy;
        when x"CD" =>
          -- @IO:GS $D6CD QSPI:SIZEL Transfer size low byte
          fastio_rdata <= block_size(7 downto 0);
        when x"CE" =>
          -- @IO:GS $D6CE QSPI:SIZEH Transfer size high (bits 1:0, max 512 bytes)
          fastio_rdata             <= (others => '0');
          fastio_rdata(1 downto 0) <= block_size(9 downto 8);
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
        block_size <= to_unsigned(512, 16);
        block_mismatch <= '0';
        dev_error <= '0';
        dev_write <= '0';
        dev_read_to_mem <= '0';
        flash_erase_block_size <= x"10";
        qspi_csn_int   <= '1';
        qspi_clock_int <= '1';
        qspi_db_oe_int <= '0';
      else
        dev_write <= '0';

        -- Fastio register writes ($D6CD/$D6CE: transfer size)
        if fastio_cs = '1' and fastio_write = '1' then
          case fastio_addr is
            when x"CD" =>
              block_size(7 downto 0) <= fastio_wdata;
            when x"CE" =>
              block_size(9 downto 8) <= fastio_wdata(1 downto 0);
            when others =>
              null;
          end case;
        end if;

        -- Action dispatch from $D680 in sdcardio
        if action_strobe = '1' and dev_busy = '0' then
          if dev_state = UNINITIALIZED then
            -- Only initialize ($50) is accepted when uninitialized
            if action_byte = x"50" then
              dev_error <= '0';
              dev_state <= FLASH_RESET;
            else
              post_rejected_state <= UNINITIALIZED;
              dev_state           <= REJECTED;
            end if;
          elsif dev_state = IDLE then
            dev_error <= '0';
            case action_byte is
              when x"50" =>  -- Initialize
                dev_state <= FLASH_RESET;
              when x"51" =>  -- Read
                block_address <= spi_address_in;
                dev_state     <= FLASH_READ;
              when x"52" =>  -- Program (hypervisor only)
                if hypervisor_mode = '1' or dipsw2 = '1' then
                  block_address <= spi_address_in;
                  dev_state     <= FLASH_PROGRAM;
                else
                  post_rejected_state <= IDLE;
                  dev_state           <= REJECTED;
                end if;
              when x"53" =>  -- Verify
                block_address <= spi_address_in;
                dev_state     <= FLASH_VERIFY;
              when x"54" =>  -- Erase 4K (hypervisor only)
                if hypervisor_mode = '1' or dipsw2 = '1' then
                  block_address          <= spi_address_in;
                  flash_erase_block_size <= x"01";
                  dev_state              <= FLASH_ERASE;
                else
                  post_rejected_state <= IDLE;
                  dev_state           <= REJECTED;
                end if;
              when x"55" =>  -- Erase 32K (hypervisor only)
                if hypervisor_mode = '1' or dipsw2 = '1' then
                  block_address          <= spi_address_in;
                  flash_erase_block_size <= x"08";
                  dev_state              <= FLASH_ERASE;
                else
                  post_rejected_state <= IDLE;
                  dev_state           <= REJECTED;
                end if;
              when x"56" =>  -- Erase 64K (hypervisor only)
                if hypervisor_mode = '1' or dipsw2 = '1' then
                  block_address          <= spi_address_in;
                  flash_erase_block_size <= x"10";
                  dev_state              <= FLASH_ERASE;
                else
                  post_rejected_state <= IDLE;
                  dev_state           <= REJECTED;
                end if;
              when others =>
                post_rejected_state <= IDLE;
                dev_state           <= REJECTED;
            end case;
          else
            -- Strobe while busy — shouldn't happen
            dev_error <= '1';
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

            if block_size(9) = '1' then
              read_x4_num_bytes <= 512;
            else
              read_x4_num_bytes <= to_integer(block_size);
            end if;

            qspi_tx_buffer(0) <= x"6c";
            qspi_tx_buffer(1) <= block_address(31 downto 24);
            qspi_tx_buffer(2) <= block_address(23 downto 16);
            qspi_tx_buffer(3) <= block_address(15 downto 8);
            qspi_tx_buffer(4) <= block_address(7 downto 0);
            write_x1_num_bytes <= 5;
            --read_x4_num_bytes <= to_integer(block_size(8 downto 0));
            transaction_type <= TRANSACTION_READ_X4;
            post_transaction_state <= IDLE;
            dev_state <= TRANSACTION;

          when FLASH_PROGRAM =>

            if block_size = x"0000" then
              dev_state <= IDLE;
            else
              post_write_enable_state <= FLASH_PROGRAM_STEP_0;
              post_clear_status_state <= WRITE_ENABLE;
              dev_state <= CLEAR_STATUS;
            end if;

          when FLASH_PROGRAM_STEP_0 =>

            if block_size(9 downto 8) /= "00" then
              write_x4_num_bytes <= 256;
            else
              write_x4_num_bytes <= to_integer(block_size(7 downto 0));
            end if;

            block_address_int <= block_address + x"100";

            qspi_tx_buffer(0) <= x"34";
            qspi_tx_buffer(1) <= block_address(31 downto 24);
            qspi_tx_buffer(2) <= block_address(23 downto 16);
            qspi_tx_buffer(3) <= block_address(15 downto 8);
            qspi_tx_buffer(4) <= block_address(7 downto 0);
            write_x1_num_bytes <= 5;
            qspi_read_addr <= 0;
            transaction_type <= TRANSACTION_WRITE_X4;
            post_transaction_state <= FLASH_PROGRAM_STEP_1;
            dev_state <= TRANSACTION;

          when FLASH_PROGRAM_STEP_1 =>

            if block_size(9 downto 8) /= "00" and block_size /= x"0100" then
              post_await_status_state <= FLASH_PROGRAM_STEP_2;
            else
              post_await_status_state <= IDLE;
            end if;
            dev_state <= AWAIT_STATUS;

          when FLASH_PROGRAM_STEP_2 =>

            post_write_enable_state <= FLASH_PROGRAM_STEP_3;
            post_clear_status_state <= WRITE_ENABLE;
            dev_state <= CLEAR_STATUS;

          when FLASH_PROGRAM_STEP_3 =>

            if block_size(9) = '1' then
              write_x4_num_bytes <= 256;
            else
              write_x4_num_bytes <= to_integer(block_size(7 downto 0));
            end if;

            qspi_tx_buffer(0) <= x"34";
            qspi_tx_buffer(1) <= block_address_int(31 downto 24);
            qspi_tx_buffer(2) <= block_address_int(23 downto 16);
            qspi_tx_buffer(3) <= block_address_int(15 downto 8);
            qspi_tx_buffer(4) <= block_address_int(7 downto 0);
            write_x1_num_bytes <= 5;
            --write_x4_num_bytes <= to_integer(block_size(7 downto 0));
            qspi_read_addr <= 256;
            transaction_type <= TRANSACTION_WRITE_X4;
            post_transaction_state <= FLASH_PROGRAM_STEP_4;
            dev_state <= TRANSACTION;

          when FLASH_PROGRAM_STEP_4 =>

            post_await_status_state <= IDLE;
            dev_state <= AWAIT_STATUS;

          when FLASH_ERASE =>

            post_write_enable_state <= FLASH_ERASE_STEP_0;
            post_clear_status_state <= WRITE_ENABLE;
            dev_state <= CLEAR_STATUS;

            if flash_erase_block_size(4) = '1' then
                -- 64K
                flash_erase_command <= x"dc";
            elsif flash_erase_block_size(3) = '1' then
                -- 32K
                flash_erase_command <= x"53";
            elsif flash_erase_block_size(0) = '1' then
                -- 4K
                flash_erase_command <= x"21";
            else
                dev_error <= '1';
                dev_state <= IDLE;
            end if;

          when FLASH_ERASE_STEP_0 =>

            qspi_tx_buffer(0) <= flash_erase_command;
            qspi_tx_buffer(1) <= block_address(31 downto 24);
            qspi_tx_buffer(2) <= block_address(23 downto 16);
            qspi_tx_buffer(3) <= block_address(15 downto 8);
            qspi_tx_buffer(4) <= block_address(7 downto 0);
            write_x1_num_bytes <= 5;
            read_x1_num_bytes <= 0;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= FLASH_ERASE_STEP_1;
            dev_state <= TRANSACTION;

          when FLASH_ERASE_STEP_1 =>

            post_await_status_state <= IDLE;
            dev_state <= AWAIT_STATUS;

          when FLASH_RESET =>

            qspi_idle_clock_count <= 255;
            post_idle_clocks_state <= FLASH_RESET_STEP_0;
            dev_state <= IDLE_CLOCKS;

          when FLASH_RESET_STEP_0 =>

            qspi_tx_buffer(0) <= x"66";
            write_x1_num_bytes <= 1;
            read_x1_num_bytes <= 0;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= FLASH_RESET_STEP_1;
            dev_state <= TRANSACTION;

          when FLASH_RESET_STEP_1 =>

            qspi_tx_buffer(0) <= x"99";
            write_x1_num_bytes <= 1;
            read_x1_num_bytes <= 0;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= FLASH_RESET_STEP_2;
            dev_state <= TRANSACTION;

          when FLASH_RESET_STEP_2 =>

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

            post_read_cr3_state <= INITIALIZE_STEP_2;
            dev_state <= READ_CONFIGURATION_REGISTER_3;

          when INITIALIZE_STEP_2 =>

            if flash_id(0) /= x"01" or flash_id(1) /= x"60" then
              dev_state <= UNINITIALIZED;
            elsif flash_id(2) /= x"18" and flash_id(2) /= x"19" then
              dev_state <= UNINITIALIZED;
            else
              if flash_id(2) = x"18" then
                flash_size <= 16;
              else
                flash_size <= 32;
              end if;

              flash_latency_cycles <= to_integer(cr3(3 downto 0));

              if cr1(1) = '0' then
                post_enable_quad_mode_state <= INITIALIZE_STEP_3;
                dev_state <= ENABLE_QUAD_MODE;
              else
                dev_state <= IDLE;
              end if;
            end if;

          when INITIALIZE_STEP_3 =>

            post_read_cr1_state <= INITIALIZE_STEP_4;
            dev_state <= READ_CONFIGURATION_REGISTER_1;

          when INITIALIZE_STEP_4 =>

            if cr1(1) = '0' then
              dev_state <= UNINITIALIZED;
            else
              dev_state <= IDLE;
            end if;

          when READ_ID =>

            qspi_tx_buffer(0) <= x"9f";
            write_x1_num_bytes <= 1;
            read_x1_num_bytes <= 3;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= ID_READ;
            dev_state <= TRANSACTION;

          when ID_READ =>

            flash_id(0) <= qspi_rx_buffer(0);
            flash_id(1) <= qspi_rx_buffer(1);
            flash_id(2) <= qspi_rx_buffer(2);
            dev_state <= post_read_id_state;

          when ENABLE_QUAD_MODE =>

            post_read_sr1_state <= ENABLE_QUAD_MODE_STEP_0;
            dev_state <= READ_STATUS_REGISTER_1;

          when ENABLE_QUAD_MODE_STEP_0 =>

            post_read_cr1_state <= ENABLE_QUAD_MODE_STEP_1;
            dev_state <= READ_CONFIGURATION_REGISTER_1;

          when ENABLE_QUAD_MODE_STEP_1 =>

            -- Volatile write enable.
            qspi_tx_buffer(0) <= x"50";
            write_x1_num_bytes <= 1;
            read_x1_num_bytes <= 0;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= ENABLE_QUAD_MODE_STEP_2;
            dev_state <= TRANSACTION;

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

          when READ_STATUS_REGISTER_2 =>

            qspi_tx_buffer(0) <= x"07";
            write_x1_num_bytes <= 1;
            read_x1_num_bytes <= 1;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= STATUS_REGISTER_2_READ;
            dev_state <= TRANSACTION;

          when STATUS_REGISTER_2_READ =>

            sr2 <= qspi_rx_buffer(0);
            dev_state <= post_read_sr2_state;

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

          when READ_CONFIGURATION_REGISTER_2 =>

            qspi_tx_buffer(0) <= x"15";
            write_x1_num_bytes <= 1;
            read_x1_num_bytes <= 1;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= CONFIGURATION_REGISTER_2_READ;
            dev_state <= TRANSACTION;

          when CONFIGURATION_REGISTER_2_READ =>

            cr2 <= qspi_rx_buffer(0);
            dev_state <= post_read_cr2_state;

          when READ_CONFIGURATION_REGISTER_3 =>

            qspi_tx_buffer(0) <= x"33";
            write_x1_num_bytes <= 1;
            read_x1_num_bytes <= 1;
            transaction_type <= TRANSACTION_X1;
            post_transaction_state <= CONFIGURATION_REGISTER_3_READ;
            dev_state <= TRANSACTION;

          when CONFIGURATION_REGISTER_3_READ =>

            cr3 <= qspi_rx_buffer(0);
            dev_state <= post_read_cr3_state;

          when READ_STATUS =>

            post_read_sr1_state <= READ_STATUS_STEP_0;
            dev_state <= READ_STATUS_REGISTER_1;

          when READ_STATUS_STEP_0 =>

            post_read_sr2_state <= post_read_status_state;
            dev_state <= READ_STATUS_REGISTER_2;

          when CLEAR_STATUS =>

            -- Read status register(s)
            post_read_status_state <= CLEAR_STATUS_STEP_0;
            dev_state <= READ_STATUS;

          when CLEAR_STATUS_STEP_0 =>

            -- As long as error occurred or write in progress: clear status
            if sr1(0) = '1' or sr2(5) = '1' or sr2(6) = '1' then
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

            -- Read status register(s)
            post_read_status_state <= CLEAR_STATUS_STEP_2;
            dev_state <= READ_STATUS;

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

            -- Read status register(s)
            post_read_status_state <= AWAIT_STATUS_STEP_0;
            dev_state <= READ_STATUS;

          when AWAIT_STATUS_STEP_0 =>

            -- Wait until no write in progress and write disabled.
            if sr1(0) = '1' or sr1(1) = '1' then
              -- If an error occurred, clear status and set operation error flag.
              if sr2(5) = '1' or sr2(6) = '1' then
                dev_error <= '1';
                post_clear_status_state <= IDLE;
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
            block_mismatch <= '0';
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
                dev_state <= INTERNAL_ERROR;
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
            -- Compare both nibbles of the buffer byte against the flash nibbles:
            --   high nibble from flash was captured in qspi_nibble during STEP_1,
            --   low  nibble from flash is the current qspi_db_in.
            if dev_rdata(7 downto 4) /= qspi_nibble then
              block_mismatch <= '1';
            end if;
            if dev_rdata(3 downto 0) /= qspi_db_in then
              block_mismatch <= '1';
            end if;

            qspi_clock_int <= '1';
            qspi_byte_counter <= qspi_byte_counter + 1;
            dev_state <= TRANSACTION_READ_QUAD;

          when INTERNAL_ERROR =>
            null;

          when REJECTED =>
            dev_error <= '1';
            dev_state <= post_rejected_state;

          when others =>
            dev_state <= INTERNAL_ERROR;

        end case;
      end if;
    end if;
  end process;

end behavioural;
