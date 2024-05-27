--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2021
--
-- *  This program is free software; you can redistribute it and/or modify
-- *  it under the terms of the GNU Lesser General Public License as
-- *  published by the Free Software Foundation; either version 3 of the
-- *  License, or (at your option) any later version.
-- *
-- *  This program is distributed in the hope that it will be useful,
-- *  but WITHOUT ANY WARRANTY; without even the implied warranty of
-- *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- *  GNU General Public License for more details.
-- *
-- *  You should have received a copy of the GNU Lesser General Public License
-- *  along with this program; if not, write to the Free Software
-- *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
-- *  02111-1307  USA.


-- The sector buffers are a bit of a pain, because they do require access from
-- both the SD controller and the CPU side of things.
-- When reading from SD card, the SD controller needs to be able to write to
-- the buffer.
-- When writing to the SD card, the SD controller needs to be able to read from
-- the buffer.
-- The CPU can, in principle at least, read or write the buffer any time.
--
-- What might be a nice solution is to give the SD controller an exclusive
-- single-port buffer.  The CPU can also have an exclusive single port buffer.
-- All that then remains is for synchronisation between the two.  When the CPU
-- writes to its buffer, it can also signal the SD controller that there is a
-- value to be written.  If the SD controller is busy, then the write will be
-- missed, but that is an acceptable semantic, I think.  Then, when the SD
-- controller reads a byte, it needs to pass it to the CPU-side to be written
-- to the buffer there.  This is the only tricky bit, because it means that we
-- cannot have the address lines on the CPU side tied to fastio_addr, or at
-- least not when the SD controller is busy.  It should be fairly easy to mux
-- this accross using the SD controller busy flag.  Same can probably be done
-- for the buffer access. In fact, if we just do this muxing, we can get away
-- with a one single-port buffer that gets shared between the two sides based
-- on whether the SD controller is using it or not.

--library UNISIM;
--use UNISIM.vcomponents.all;

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity sdcardio is
  generic (
    target : mega65_target_t;
    cpu_frequency : integer
    );
  port (
    clock : in std_logic;
    pixelclk : in std_logic;
    reset : in std_logic;
    sdcardio_cs : in std_logic;
    f011_cs : in std_logic;

    -- Direct export of floppy gap timing info
    floppy_last_gap : out unsigned(7 downto 0) := x"00";
    floppy_gap_strobe : out std_logic := '0';

    hw_errata_level : out unsigned(7 downto 0) := x"00";
    hw_errata_disable_toggle : in std_logic;
    hw_errata_enable_toggle : in std_logic;

    -- Interface for accessing mix table via CPU
    audio_mix_reg : out unsigned(7 downto 0) := x"FF";
    audio_mix_write : out std_logic := '0';
    audio_mix_wdata : out unsigned(15 downto 0) := x"FFFF";
    audio_mix_rdata : in unsigned(15 downto 0) := x"FFFF";
    audio_loopback : in signed(15 downto 0) := x"FFFF";
    -- PCM digital audio output (to give to the mixer)
    pcm_left : buffer signed(15 downto 0) := x"0000";
    pcm_right : buffer signed(15 downto 0) := x"0000";

    hypervisor_mode : in std_logic;
    hyper_trap_f011_read : out std_logic := '0';
    hyper_trap_f011_write : out std_logic := '0';
    secure_mode : in std_logic := '0';

    fpga_temperature : in std_logic_vector(11 downto 0);

    pwm_knob : in unsigned(15 downto 0);
    volume_knob1_target : buffer unsigned(3 downto 0) := x"F";
    volume_knob2_target : buffer unsigned(3 downto 0) := x"F";
    volume_knob3_target : buffer unsigned(3 downto 0) := x"F";

    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : in unsigned(19 downto 0);
    fastio_addr_fast : in unsigned(19 downto 0);  -- The "quick" version that arrives one clock earlier
    fastio_write : in std_logic;
    fastio_read : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata_sel : out unsigned(7 downto 0);

    virtualise_f011_drive0 : in std_logic;
    virtualise_f011_drive1 : in std_logic;

    colourram_at_dc00 : in std_logic;
    viciii_iomode : in std_logic_vector(1 downto 0);

    sectorbuffermapped : out std_logic := '0';
    sectorbuffermapped2 : out std_logic := '0';
    sectorbuffercs : in std_logic;
    sectorbuffercs_fast : in std_logic;

    last_scan_code : in std_logic_vector(12 downto 0);

    drive_led0 : out std_logic := '0';
    drive_led2 : out std_logic := '0';
    drive_ledsd : out std_logic := '0';
    motor : out std_logic := '0';

    dipsw_hi : in std_logic_vector(7 downto 5);
    dipsw : in std_logic_vector(4 downto 0);
    j21in : in std_logic_vector(11 downto 0);
    sw : in std_logic_vector(15 downto 0);
    btn : in std_logic_vector(4 downto 0);

    -------------------------------------------------------------------------
    -- Lines for the SDcard interface itself
    -------------------------------------------------------------------------
    sd_interface_select : out std_logic := '0';
    cs_bo : out std_logic;
    sclk_o : out std_logic;
    mosi_o : out std_logic;
    miso_i : in  std_logic;

    ----------------------------------------------------------------------
    -- Floppy drive interface
    ----------------------------------------------------------------------
    f_density : out std_logic := '1';
    f_motora : out std_logic := '1';
    f_selecta : out std_logic := '1';
    f_motorb : out std_logic := '1';
    f_selectb : out std_logic := '1';
    f_stepdir : out std_logic := '1';
    f_step : out std_logic := '1';
    f_wdata : out std_logic := '1';
    f_wgate : out std_logic := '1';
    f_side1 : out std_logic := '1';
    f_index : in std_logic;
    f_track0 : in std_logic;
    f_writeprotect : in std_logic;
    f_rdata : in std_logic;
    f_diskchanged : in std_logic;
    f_rdata_loopback : out std_logic := '0';

    sd1541_data : out unsigned(7 downto 0) := x"FF";
    sd1541_ready_toggle : out std_logic := '0';
    sd1541_request_toggle : in std_logic;
    sd1541_enable : in std_logic;
    sd1541_track : in unsigned(5 downto 0);


    ---------------------------------------------------------------------------
    -- Lines for other devices that we handle here
    ---------------------------------------------------------------------------
    -- Accelerometer
    aclMISO : in std_logic;
    aclMOSI : out std_logic;
    aclSS : out std_logic;
    aclSCK : out std_logic;
    aclInt1 : in std_logic;
    aclInt2 : in std_logic;

    -- Temperature sensor / I2C bus 0
    tmpSDA : inout std_logic;
    tmpSCL : inout std_logic;
    tmpInt : in std_logic;
    tmpCT : in std_logic;

    -- I2C bus 1
    i2c1SDA : inout std_logic;
    i2c1SCL : inout std_logic;

    -- PWM brightness control for LCD panel
    lcdpwm : out std_logic;

    -- Touch pad I2C bus
    touchSDA : inout std_logic;
    touchSCL : inout std_logic;
    -- Touch interface
    touch1_valid : out std_logic := '0';
    touch1_x : out unsigned(13 downto 0) := (others => '0');
    touch1_y : out unsigned(11 downto 0) := (others => '0');
    touch2_valid : out std_logic := '0';
    touch2_x : out unsigned(13 downto 0) := (others => '0');
    touch2_y : out unsigned(11 downto 0) := (others => '0');


    ----------------------------------------------------------------------
    -- Flash RAM for holding config
    ----------------------------------------------------------------------
    QspiDB : out unsigned(3 downto 0) := "1111";
    QspiDB_in : in unsigned(3 downto 0);
    qspidb_oe : out std_logic := '0';
    QspiCSn : out std_logic := '1';
    qspi_clock : out std_logic := '1'

    );
end sdcardio;

architecture behavioural of sdcardio is

  signal f_rdata_drive : std_logic := '0';

  signal f_rdata_loopback_int : std_logic := '0';

  signal saved_fdc_encoding_mode : unsigned(3 downto 0) := x"0";
  signal fdc_encoding_mode : unsigned(3 downto 0) := x"0";
  signal f_wdata_raw : std_logic := '0';
  signal fw_no_data_raw : std_logic := '0';
  signal fw_ready_for_next_raw : std_logic := '0';
  signal f_wdata_mfm : std_logic := '0';
  signal fw_no_data_mfm : std_logic := '0';
  signal fw_ready_for_next_mfm : std_logic := '0';
  signal f_wdata_rll : std_logic := '0';
  signal fw_no_data_rll : std_logic := '0';
  signal fw_ready_for_next_rll : std_logic := '0';
  signal f_wdata_int : std_logic := '0';
  signal f_wdata_last : std_logic := '0';
  signal f_wdata_interval : integer range 0 to 255 := 255;
  signal f_wdata_minimum : integer range 0 to 255 := 255;

  signal mfm_encoding : std_logic := '0';
  signal rll27_encoding : std_logic := '0';
  signal raw_encoding : std_logic := '0';

  signal sd_interface_select_internal : std_logic := '0';

  signal read_on_idle : std_logic := '0';

  signal audio_mix_reg_int : unsigned(7 downto 0) := x"FF";

  signal aclMOSIinternal : std_logic := '0';
  signal aclSSinternal : std_logic := '0';
  signal aclSCKinternal : std_logic := '0';
  signal micClkinternal : std_logic := '0';
--  signal micLRSelinternal : std_logic := '0';
  signal tmpSDAinternal : std_logic := '0';
  signal tmpSCLinternal : std_logic := '0';

  -- debounce reading from or writing to $D087 so that buffered read/write
  -- behaves itself.
  signal last_was_d087 : std_logic := '0';

  signal fastio_rdata_ram : unsigned(7 downto 0);
  signal fastio_rdata : unsigned(7 downto 0);

  signal skip                  : integer range 0 to 2;
  signal read_data_byte        : std_logic := '0';
  signal sd_doread             : std_logic := '0';
  signal sd_dowrite            : std_logic := '0';
  signal sd_write_multi        : std_logic := '0';
  signal sd_write_multi_first  : std_logic := '0';
  signal sd_write_multi_last   : std_logic := '0';
  signal sd_data_ready         : std_logic := '0';
  signal sd_handshake          : std_logic := '0';
  signal sd_handshake_internal : std_logic := '0';

  -- Signals to communicate with SD controller core
  signal sd_sector       : unsigned(31 downto 0) := (others => '0');

  signal sd_datatoken    : unsigned(7 downto 0) := (others => '0');
  signal sd_rdata        : unsigned(7 downto 0);
  signal sd_wdata        : unsigned(7 downto 0) := (others => '0');
  signal sd_error        : std_logic;
  signal sd_reset        : std_logic := '1';
  signal sdhc_mode : std_logic := '1';

  signal sd_fill_mode    : std_logic := '0';
  signal sd_fill_value   : unsigned(7 downto 0) := (others => '0');

  -- IO mapped register to indicate if SD card interface is busy
  signal sdio_busy : std_logic := '0';
  signal sdcard_busy : std_logic := '0';
  signal sdio_error : std_logic := '0';
  signal sdio_fsm_error : std_logic := '0';

  signal sector_buffer_mapped : std_logic := '0';

  type sd_state_t is (Idle,                           -- 0x00
                      ReadSector,                     -- 0x01
                      ReadingSector,                  -- 0x02
                      ReadingSectorAckByte,           -- 0x03
                      DoneReadingSector,              -- 0x04
                      FDCReadingSectorWait,           -- 0x05
                      FDCReadingSector,               -- 0x06
                      WriteSector,                    -- 0x07
                      WritingSector,                  -- 0x08
                      WritingSectorAckByte,           -- 0x09
                      HyperTrapRead,                  -- 0x0A
                      HyperTrapRead2,                 -- 0x0B
                      HyperTrapWrite,                 -- 0x0C
                      F011WriteSector,                -- 0x0D
                      DoneWritingSector,              -- 0x0E

                      FDCFormatTrackSyncWait,         -- 0x0F
                      FDCFormatTrack,                 -- 0x10
                      F011WriteSectorRealDriveWait,   -- 0x11
                      F011WriteSectorRealDrive,       -- 0x12
                      FDCAutoFormatTrackSyncWait,     -- 0x13
                      FDCAutoFormatTrack,              -- 0x14

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
  signal sd_state : sd_state_t := Idle;
  signal last_sd_state_t : sd_state_t := HyperTrapRead;
  signal last_f011_drq : std_logic := '0';

  signal qspi_clock_int : std_logic := '1';
  signal qspi_clock_run : std_logic := '1';
  signal qspi_csn_int : std_logic := '1';
  signal qspi_bits : unsigned(3 downto 0) := "0000";
  signal qspi_bytes_differ : std_logic := '0';
  signal qspi_byte_value : unsigned(7 downto 0) := x"00";
  signal qspi_bit_counter : integer range 0 to 7 := 0;
  signal qspidb_tristate : std_logic := '1';
  signal qspi_read_sector_phase : integer range 0 to 128 := 0;
  signal qspi_action_state : sd_state_t := Idle;
  signal qspi_command_len : integer range 84 to 100 := 98;
  signal spi_address : unsigned(31 downto 0) := (others => '0');
  signal qspi_release_cs_on_completion : std_logic := '0';
  signal qspi_release_cs_on_completion_enable : std_logic := '1';
  signal qspi_verify_mode : std_logic := '0';
  signal spi_flash_cmd_byte : unsigned(7 downto 0) := x"ec";
  signal spi_flash_cmd_only : std_logic := '0';
  signal spi_flash_16bits : std_logic := '0';
  signal spi_no_dummy_cycles : std_logic := '0';

  -- Diagnostic register for determining SD/SDHC card state.
  signal last_sd_state : unsigned(7 downto 0);
  signal last_sd_rxbyte : unsigned(7 downto 0);
  signal last_sd_error : std_logic_vector(15 downto 0);
  signal sd_clear_error : std_logic := '0';

  -- F011 FDC emulation registers and flags
  signal diskimage_sector : unsigned(31 downto 0) := x"ffffffff";
  signal diskimage2_sector : unsigned(31 downto 0) := x"ffffffff";
  signal diskimage1_enable : std_logic := '0';
  signal diskimage2_enable : std_logic := '0';
  signal diskimage1_offset : unsigned(16 downto 0);
  signal diskimage2_offset : unsigned(16 downto 0);
  signal f011_track : unsigned(7 downto 0) := x"01";
  signal f011_sector : unsigned(7 downto 0) := x"00";
  signal physical_sector : unsigned(7 downto 0) := x"00";
  signal f011_side : unsigned(7 downto 0) := x"00";
  signal f011_head_side : unsigned(7 downto 0) := x"00";
  signal f011_sector_fetch : std_logic := '0';

  signal sb_cpu_read_request : std_logic := '0';
  signal sb_cpu_write_request : std_logic := '0';
  signal sb_cpu_reading : std_logic := '0';
  signal sb_cpu_writing : std_logic := '0';
  signal sb_cpu_rdata : unsigned(7 downto 0) := x"00";
  signal sb_cpu_wdata : unsigned(7 downto 0) := x"00";

  signal sector_buffer_fastio_address : integer := 0;

  signal f011_buffer_disk_pointer_advance : std_logic := '0';
  signal f011_buffer_cpu_pointer_advance : std_logic := '0';
  signal f011_buffer_disk_address : unsigned(8 downto 0) := (others => '0');
  signal f011_buffer_cpu_address : unsigned(8 downto 0) := (others => '0');
  signal last_f011_buffer_disk_address : unsigned(8 downto 0) := (others => '1');
  signal last_f011_buffer_cpu_address : unsigned(8 downto 0) := (others => '1');
  signal sd_buffer_offset : unsigned(8 downto 0) := (others => '0');

  -- Toggles whether the memory mapped sector buffer is the F011 (0) or
  -- SD-card (1) sector buffer.
  signal f011sd_buffer_select : std_logic := '1';

  signal f011_buffer_read_address : unsigned(11 downto 0) := (others => '0');
  signal f011_buffer_write_address : unsigned(11 downto 0) := (others => '0');
  signal f011_buffer_wdata : unsigned(7 downto 0);
  signal f011_buffer_rdata : unsigned(7 downto 0);
  signal f011_buffer_write : std_logic := '0';
  signal f011_flag_eq : std_logic := '1';
  signal f011_swap : std_logic := '0'; -- swap buffer halves, C65 style
  signal f011_swap_drives : std_logic := '0'; -- swap drive 0 and drive 1

  signal f011_eq_inhibit : std_logic := '0';

  signal f011_irqenable : std_logic := '0';

  signal f011_cmd : unsigned(7 downto 0) := x"00";
  signal f011_busy : std_logic := '0';
  signal f011_lost : std_logic := '0';
  signal f011_irq : std_logic := '0';
  signal f011_rnf : std_logic := '0';
  signal f011_crc : std_logic := '0';
  signal f011_drq : std_logic := '0';
  signal f011_ds : unsigned(2 downto 0) := "000";
  signal f011_track0 : std_logic := '0';
  signal f011_head_track : unsigned(6 downto 0) := "0000000";
  signal f011_disk_present : std_logic := '0';
  signal f011_disk1_present : std_logic := '0';
  signal f011_disk2_present : std_logic := '0';
  signal f011_over_index : std_logic := '0';
  signal f011_disk_changed : std_logic := '0';

  signal f011_rsector_found : std_logic := '0';
  signal f011_wsector_found : std_logic := '0';
  signal f011_write_gate : std_logic := '0';
  signal f011_write_protected : std_logic := '0';
  signal f011_disk1_write_protected : std_logic := '0';
  signal f011_disk2_write_protected : std_logic := '0';
  signal f011_mega_disk : std_logic := '0';
  signal f011_mega_disk2 : std_logic := '0';
  signal f011_d64_disk : std_logic := '0';
  signal f011_d64_disk2 : std_logic := '0';

  signal f011_led : std_logic := '0';
  signal f011_motor : std_logic := '0';

  -- Signals for controlling writing to floppies
  signal last_fw_ready_for_next : std_logic := '0';
  signal fw_ready_for_next : std_logic := '0';
  signal fw_byte_valid : std_logic := '0';
  signal fw_byte_in : unsigned(7 downto 0);
  signal f011_write_precomp : std_logic := '0';

  signal f011_reg_clock : unsigned(7 downto 0) := x"FF";

  signal f011_reg_step : unsigned(7 downto 0) := x"80"; -- 8ms steps
  signal f011_reg_pcode : unsigned(7 downto 0) := x"00";
  signal counter_16khz : integer := 0;
  constant cycles_per_16khz : integer :=  (cpu_frequency/16000);
  signal busy_countdown : unsigned(15 downto 0) := x"0000";

  signal cycles_per_interval : unsigned(7 downto 0)
    := to_unsigned(cpu_frequency/500000,8);
  signal cycles_per_interval_from_track_info : unsigned(7 downto 0)
    := to_unsigned(cpu_frequency/500000,8);
  -- When using variable recording rates (like 1541 recording zones)
  -- we modify the user-supplied datarate based on track number.
  signal cycles_per_interval_actual : unsigned(7 downto 0)
    := to_unsigned(cpu_frequency/500000,8);
  signal write_precomp_magnitude : unsigned(7 downto 0) := to_unsigned(4,8);
  signal write_precomp_magnitude_b : unsigned(7 downto 0) := to_unsigned(8,8);
  signal write_precomp_delay15 : unsigned(7 downto 0) := to_unsigned(0,8);

  signal saved_cycles_per_interval : unsigned(7 downto 0)
    := to_unsigned(cpu_frequency/500000,8);

  signal fdc_read_invalidate : std_logic := '0';
  signal target_track : unsigned(7 downto 0) := x"00";
  signal target_sector : unsigned(7 downto 0) := x"00";
  signal target_side : unsigned(7 downto 0) := x"00";
  signal target_any : std_logic := '0';

  -- Signals back from single rate FDC reader
  signal found_track : unsigned(7 downto 0) := x"00";
  signal found_sector : unsigned(7 downto 0) := x"00";
  signal found_side : unsigned(7 downto 0) := x"00";
  signal fdc_first_byte : std_logic := '0';
  signal fdc_byte_valid : std_logic := '0';
  signal fdc_byte_out : unsigned(7 downto 0);
  signal fdc_crc_error : std_logic := '0';
  signal fdc_sector_end : std_logic := '0';
  signal fdc_sector_data_gap : std_logic := '0';
  signal fdc_sector_found : std_logic := '0';
  signal last_fdc_sector_found : std_logic := '0';

  -- Debug info from single rate MFM reader
  signal fdc_mfm_state : unsigned(7 downto 0);
  signal fdc_last_gap : unsigned(15 downto 0);
  signal fdc_last_gap_strobe : std_logic := '0';
  signal fdc_mfm_byte : unsigned(7 downto 0);
  signal fdc_quantised_gap : unsigned(7 downto 0);

  -- Signals back from double-rate MFM reader
  -- i.e., the reader normally used for reading HD data
  signal found_track_2x : unsigned(7 downto 0) := x"00";
  signal found_sector_2x : unsigned(7 downto 0) := x"00";
  signal found_side_2x : unsigned(7 downto 0) := x"00";
  signal fdc_first_byte_2x : std_logic := '0';
  signal fdc_byte_valid_2x : std_logic := '0';
  signal fdc_byte_out_2x : unsigned(7 downto 0);
  signal fdc_crc_error_2x : std_logic := '0';
  signal fdc_sector_end_2x : std_logic := '0';
  signal fdc_sector_data_gap_2x : std_logic := '0';
  signal fdc_sector_found_2x : std_logic := '0';
  signal last_fdc_sector_found_2x : std_logic := '0';
  signal fdc_2x_select : std_logic := '0';
  signal auto_fdc_2x_select : std_logic := '1';
  signal fdc_variable_data_rate : std_logic := '1';

  signal last_found_track : unsigned(7 downto 0) := x"00";
  signal last_found_sector : unsigned(7 downto 0) := x"00";
  signal last_found_side : unsigned(7 downto 0) := x"00";

  signal last_found_track_2x : unsigned(7 downto 0) := x"00";
  signal last_found_sector_2x : unsigned(7 downto 0) := x"00";
  signal last_found_side_2x : unsigned(7 downto 0) := x"00";

  signal use_real_floppy0 : std_logic := '0';
  signal use_real_floppy2 : std_logic := '1';
  signal silent_sdcard : std_logic := '0';
  signal fdc_read_request : std_logic := '0';
  signal fdc_rotation_timeout : integer range 0 to 10 := 0;
  signal rotation_count : integer range 0 to 15 := 0;
  signal index_wait_timeout : integer := 0;
  signal fdc_rotation_timeout_reserve_counter : integer range 0 to 100000000 := 0;

  signal fdc_bytes_read : unsigned(15 downto 0) := x"0000";
  signal sd_wrote_byte : std_logic := '0';

  -- Disable track auto-tuner for ~0.5 seconds after any write action
  -- (Actually the auto-tuner is now effectively defunct, as the bug that caused
  -- us to implement it has now been fixed).
  signal fdc_writing : std_logic := '0';
  signal fdc_writing_cooldown : integer range 0 to 20250000 := 0;

  -- fdc_sector_operation flag is set whenever we are doing an action
  -- where auto-stepping to the correct track is safe and helpful.
  -- This is not the case for track format, for example.
  signal fdc_sector_operation : std_logic := '0';
  signal autotune_enable : std_logic := '1';
  signal autotune_step : std_logic := '1';
  signal last_autotune_step : std_logic := '1';
  signal autotune_stepdir : std_logic := '1';

  signal autotune2x_step : std_logic := '1';
  signal last_autotune2x_step : std_logic := '1';
  signal autotune2x_stepdir : std_logic := '1';


  -- Used to keep track of where we are upto in a sector write
  signal fdc_write_byte_number : integer range 0 to 1023 := 0;


  signal packed_rdata : std_logic_vector(7 downto 0);

  signal i2c_bus_id : unsigned(7 downto 0) := x"00";

  signal i2c0_address : unsigned(6 downto 0) := to_unsigned(0,7);
  signal i2c0_address_internal : unsigned(6 downto 0) := to_unsigned(0,7);
  signal i2c0_rdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c0_wdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c0_wdata_internal : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c0_busy : std_logic := '0';
  signal i2c0_busy_last : std_logic := '0';
  signal i2c0_rw : std_logic := '0';
  signal i2c0_rw_internal : std_logic := '0';
  signal i2c0_error : std_logic := '0';
  signal i2c0_reset : std_logic := '1';
  signal i2c0_reset_internal : std_logic := '1';
  signal i2c0_command_en : std_logic := '0';
  signal i2c0_command_en_internal : std_logic := '0';
  signal i2c0_stacked_command : std_logic := '0';

  signal i2c1_address : unsigned(6 downto 0) := to_unsigned(0,7);
  signal i2c1_address_internal : unsigned(6 downto 0) := to_unsigned(0,7);
  signal i2c1_rdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c1_wdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c1_wdata_internal : unsigned(7 downto 0) := to_unsigned(0,8);
  signal i2c1_busy : std_logic := '0';
  signal i2c1_busy_last : std_logic := '0';
  signal i2c1_rw : std_logic := '0';
  signal i2c1_rw_internal : std_logic := '0';
  signal i2c1_error : std_logic := '0';
  signal i2c1_reset : std_logic := '1';
  signal i2c1_reset_internal : std_logic := '1';
  signal i2c1_command_en : std_logic := '0';
  signal i2c1_command_en_internal : std_logic := '0';
  signal i2c1_swap : std_logic := '0';
  signal i2c1_debug_scl : std_logic := '0';
  signal i2c1_debug_sda : std_logic := '0';
  signal i2c1_stacked_command : std_logic := '0';

  signal touch_enabled : std_logic := '1';
  signal touch_enabled_internal : std_logic := '1';
  signal touch_flip_x : std_logic := '1';
  signal touch_flip_x_internal : std_logic := '1';
  signal touch_flip_y : std_logic := '0';
  signal touch_flip_y_internal : std_logic := '0';

  -- Approximate touch screen calibration values based on the test panel
  -- XXX Doesn't take account of the non-linearity in movement we see on some
  -- areas of the screen.
  signal touch_scale_x : unsigned(15 downto 0 ) := to_unsigned(1024,16);
  signal touch_scale_x_internal : unsigned(15 downto 0 ) := to_unsigned(1024,16);
  signal touch_scale_y : unsigned(15 downto 0 ) := to_unsigned(1024,16);
  signal touch_scale_y_internal : unsigned(15 downto 0 ) := to_unsigned(1024,16);
  signal touch_delta_x : unsigned(15 downto 0 ) := to_unsigned(768,16);
  signal touch_delta_x_internal : unsigned(15 downto 0 ) := to_unsigned(768,16);
  signal touch_delta_y : unsigned(15 downto 0 ) := to_unsigned(2048,16);
  signal touch_delta_y_internal : unsigned(15 downto 0 ) := to_unsigned(2048,16);

  signal touch1_active : std_logic := '0';
  signal touch1_status : std_logic_vector(1 downto 0) := "11";
  signal touch_x1 : unsigned(9 downto 0) := to_unsigned(0,10);
  signal touch_y1 : unsigned(9 downto 0) := to_unsigned(0,10);
  signal touch2_active : std_logic := '0';
  signal touch2_status : std_logic_vector(1 downto 0) := "11";
  signal touch_x2 : unsigned(9 downto 0) := to_unsigned(0,10);
  signal touch_y2 : unsigned(9 downto 0) := to_unsigned(0,10);
  signal scan_count : unsigned(7 downto 0) := x"00";
  signal b0 : unsigned(7 downto 0) := x"00";
  signal b1 : unsigned(7 downto 0) := x"00";
  signal b2 : unsigned(7 downto 0) := x"00";
  signal b3 : unsigned(7 downto 0) := x"00";
  signal b4 : unsigned(7 downto 0) := x"00";
  signal b5 : unsigned(7 downto 0) := x"00";
  signal touch_byte : unsigned(7 downto 0) := x"00";
  signal touch_byte_num : unsigned(7 downto 0) := x"00";

  signal lcd_pwm_divider : integer range 0 to 255 := 0;
  signal lcd_pwm_counter : integer range 0 to 255 := 0;
  -- Start with panel at full brightness
  signal lcdpwm_value : unsigned(7 downto 0) := x"ff";

  signal gesture_event_id : unsigned(3 downto 0) := x"0";
  signal gesture_event : unsigned(3 downto 0) := x"0";

  signal pwm_knob_en : std_logic := '0';

  signal reconfigure_address : unsigned(31 downto 0) := x"00000000";
  signal reconfigure_address_int : unsigned(31 downto 0) := x"00000000";
  signal trigger_reconfigure : std_logic := '0';

  signal flash_boot_address : unsigned(31 downto 0) := x"FFFFFFFF";

  signal icape2_reg : unsigned(4 downto 0) := "10110";

  signal latched_disk_change_event : std_logic := '0';

  -- Used to prevent accidental writes to sectors
  signal write_sector_gate_open : std_logic := '0';
  signal write_sector0_gate_open : std_logic := '0';
  signal write_sector_gate_timeout : integer range 0 to 65535 := 0;

  signal debug_track_format_sync_wait_counter : unsigned(7 downto 0) := to_unsigned(0,8);
  signal debug_track_format_counter : unsigned(7 downto 0) := to_unsigned(0,8);

  signal last_fw_no_data : std_logic := '1';
  signal fw_no_data : std_logic := '0';
  signal f_index_history : std_logic_vector(7 downto 0) := (others => '1');
  signal last_f_index : std_logic := '0';
  signal f_index_rising_edge : std_logic := '0';
  signal step_countdown : integer range 0 to 511 := 0;

  signal crc_reset : std_logic := '1';
  signal crc_feed : std_logic := '0';
  signal crc_byte : unsigned(7 downto 0);
  signal crc_ready : std_logic;
  signal crc_value : unsigned(15 downto 0);

  signal unsigned_zero : unsigned(0 downto 0) := (others => '0');

  signal format_state : integer range 0 to 1023 := 0;
  signal format_no_gaps : std_logic := '0';
  signal format_sector_number : integer range 0 to 255 := 0;

  -- Track info data from track info block
  signal dd_track_info_valid : std_logic := '0';
  signal dd_track_info_rate : unsigned(7 downto 0) := to_unsigned(40,8);
  signal dd_track_info_track : unsigned(7 downto 0) := to_unsigned(255,8);
  signal dd_track_info_encoding : unsigned(7 downto 0) := x"00";
  signal dd_track_info_sectors : unsigned(7 downto 0) := x"00";
  signal hd_track_info_valid : std_logic := '0';
  signal hd_track_info_rate : unsigned(7 downto 0) := to_unsigned(40,8);
  signal hd_track_info_track : unsigned(7 downto 0) := to_unsigned(255,8);
  signal hd_track_info_encoding : unsigned(7 downto 0) := x"00";
  signal hd_track_info_sectors : unsigned(7 downto 0) := x"00";

  signal track_info_rate : unsigned(7 downto 0) := to_unsigned(40,8);
  signal track_info_track : unsigned(7 downto 0) := to_unsigned(255,8);
  signal track_info_encoding : unsigned(7 downto 0) := x"00";
  signal track_info_sectors : unsigned(7 downto 0) := x"00";
  signal use_tib_info : std_logic := '1';

  signal crc_force_delay_counter : integer range 0 to 12 := 0;
  signal crc_force_delay : std_logic := '0';

  signal hw_errata_level_int : unsigned(7 downto 0) := x"00";
  signal hw_errata_enable_toggle_last : std_logic := '0';
  signal hw_errata_disable_toggle_last : std_logic := '0';

  function resolve_sector_buffer_address(f011orsd : std_logic; addr : unsigned(8 downto 0))
    return integer is
  begin
    return to_integer("11" & f011orsd & addr);
  end function;

begin  -- behavioural

--**********************************************************************
  -- SD card controller module.
  --**********************************************************************

  -- Used to allow MEGA65 to instruct FPGA to start a different bitstream #153
  reconfig:
  if target /= simulation generate
    reconfig1:
    entity work.reconfig
      port map ( clock => clock,
                 reg_num => icape2_reg,
                 trigger_reconfigure => trigger_reconfigure,
                 reconfigure_address => reconfigure_address,
                 boot_address => flash_boot_address);
  end generate;

  touch0: entity work.touch
    generic map ( clock_frequency => cpu_frequency)
    port map (
      clock50mhz => clock,
      sda => touchSDA,
      scl => touchSCL,
      touch_enabled => touch_enabled,

      gesture_event_id => gesture_event_id,
      gesture_event => gesture_event,

      x_invert => touch_flip_x,
      y_invert => touch_flip_y,
      x_mult   => touch_scale_x,
      y_mult   => touch_scale_y,
      x_delta  => touch_delta_x,
      y_delta  => touch_delta_y,

      scan_count => scan_count,
      touch_byte => touch_byte,
      touch_byte_num => touch_byte_num,
      b0 => b0,
      b1 => b1,
      b2 => b2,
      b3 => b3,
      b4 => b4,
      b5 => b5,

      touch1_active => touch1_active,
      touch1_status => touch1_status,
      x1 => touch_x1,
      y1 => touch_y1,
      touch2_active => touch2_active,
      touch2_status => touch2_status,
      x2 => touch_x2,
      y2 => touch_y2
      );

  i2c0: entity work.i2c_master
    generic map ( input_clk => cpu_frequency )
    port map (
      clk => clock,
      reset_n => i2c0_reset,
      ena => i2c0_command_en,
      addr => std_logic_vector(i2c0_address),
      rw => i2c0_rw,
      data_wr => std_logic_vector(i2c0_wdata),
      busy => i2c0_busy,
      unsigned(data_rd) => i2c0_rdata,
      ack_error => i2c0_error,
      sda => tmpSDA,
      scl => tmpSCL
      );

  i2c1: entity work.i2c_master
    generic map ( input_clk => cpu_frequency )
    port map (
      clk => clock,
      reset_n => i2c1_reset,
      ena => i2c1_command_en,
      addr => std_logic_vector(i2c1_address),
      rw => i2c1_rw,
      data_wr => std_logic_vector(i2c1_wdata),
      busy => i2c1_busy,
      unsigned(data_rd) => i2c1_rdata,
      ack_error => i2c1_error,
      sda => i2c1SDA,
      scl => i2c1SCL,
      swap => i2c1_swap,
      debug_sda => i2c1_debug_sda,
      debug_scl => i2c1_debug_scl
      );

  sd0: entity work.sdcardctrl
    port map (
      cs_bo => cs_bo,
      mosi_o => mosi_o,
      miso_i => miso_i,
      sclk_o => sclk_o,

      last_state_o => last_sd_state,
      last_sd_rxbyte => last_sd_rxbyte,
      error_o => last_sd_error,
      clear_error => sd_clear_error,

      busy_o => sdcard_busy,

      addr_i => std_logic_vector(sd_sector),
      sdhc_i => sdhc_mode,
      rd_i =>  sd_doread,
      wr_i =>  sd_dowrite,
      write_multi => sd_write_multi,
      write_multi_first => sd_write_multi_first,
      write_multi_last => sd_write_multi_last,
      reset_i => sd_reset,
      hndshk_o => sd_data_ready,
      hndshk_i => sd_handshake,
      data_i => std_logic_vector(sd_wdata),
      unsigned(data_o) => sd_rdata,
      clk_i => clock	-- 50 MHz. If not 100MHz, use generic map to set
      );

  -- CPU direct-readable sector buffer, so that it can be memory mapped
  sb_memorymapped0: entity work.ram8x4096_sync
    generic map (
      unit => x"0"
      )
    port map (
      clkr => clock,
      clkw => clock,

      -- CPU side read access
      cs => '1',
--      cs => sectorbuffercs,
      address => sector_buffer_fastio_address,
      rdata => fastio_rdata_ram,

      -- Write side controlled by SD-card side.
      -- (CPU side effects writes by asking SD-card side to write)
      w => f011_buffer_write,
      write_address => to_integer(f011_buffer_write_address),
      wdata => f011_buffer_wdata
      );

  -- Locally readable copy of the same data, so that we can read it when writing
  -- to SD card or floppy drive
  sb_workcopy: entity work.ram8x4096_sync
    generic map (
      unit => x"1"
      )
    port map (
      clkr => clock,
      clkw => clock,

      cs => '1',
      address => to_integer(f011_buffer_read_address),
      rdata => f011_buffer_rdata,

      -- Write side controlled by SD-card side.
      -- (CPU side effects writes by asking SD-card side to write)
      w => f011_buffer_write,
      write_address => to_integer(f011_buffer_write_address),
      wdata => f011_buffer_wdata
      );

  rawencoder0: entity work.raw_bits_to_gaps port map (
    clock40mhz => clock,
    enabled => raw_encoding,
    cycles_per_interval => cycles_per_interval_actual,
    write_precomp_enable => f011_write_precomp,
    write_precomp_magnitude => write_precomp_magnitude,
    write_precomp_magnitude_b => write_precomp_magnitude_b,
    write_precomp_delay15 => write_precomp_delay15,
    ready_for_next => fw_ready_for_next_raw,
    no_data => fw_no_data_raw,
    f_write => f_wdata_raw,
    byte_valid => fw_byte_valid,
    byte_in => fw_byte_in,
    clock_byte_in => f011_reg_clock
    );

  mfmencoder0: entity work.mfm_bits_to_gaps port map (
    clock40mhz => clock,
    enabled => mfm_encoding,
    cycles_per_interval => cycles_per_interval_actual,
    write_precomp_enable => f011_write_precomp,
    write_precomp_magnitude => write_precomp_magnitude,
    write_precomp_magnitude_b => write_precomp_magnitude_b,
    write_precomp_delay15 => write_precomp_delay15,
    ready_for_next => fw_ready_for_next_mfm,
    no_data => fw_no_data_mfm,
    f_write => f_wdata_mfm,
    byte_valid => fw_byte_valid,
    byte_in => fw_byte_in,
    clock_byte_in => f011_reg_clock
    );

  rllencoder0: entity work.rll27_bits_to_gaps port map (
    clock40mhz => clock,
    enabled => rll27_encoding,
    cycles_per_interval => cycles_per_interval_actual,
    write_precomp_enable => f011_write_precomp,
    write_precomp_magnitude => write_precomp_magnitude,
    write_precomp_magnitude_b => write_precomp_magnitude_b,
    write_precomp_delay15 => write_precomp_delay15,
    ready_for_next => fw_ready_for_next_rll,
    no_data => fw_no_data_rll,
    f_write => f_wdata_rll,
    byte_valid => fw_byte_valid,
    byte_in => fw_byte_in,
    clock_byte_in => f011_reg_clock
    );

  crc0: entity work.crc1581
    generic map ( id => 1 )
    port map (
    clock40mhz => clock,
    crc_byte => crc_byte,
    crc_feed => crc_feed,
    crc_reset => crc_reset,

    crc_ready => crc_ready,
    crc_value => crc_value
    );

  -- Reader for real floppy drive: single rate
  -- Track info blocks are written in either DD or HD speed.
  -- so we have fixed decoders for both.  The DD speed one also
  -- serves as the DD speed decoder.
  mfm0: entity work.mfm_decoder generic map ( unit_id => 2 )
    port map (
    clock40mhz => clock,
    f_rdata => f_rdata_drive,
    encoding_mode => x"0", -- Always MFM for single-rate decoder
    cycles_per_interval => to_unsigned(81,8),
    invalidate => fdc_read_invalidate,
    packed_rdata => packed_rdata,

    mfm_state => fdc_mfm_state,
    mfm_last_gap => fdc_last_gap,
    mfm_last_gap_strobe => fdc_last_gap_strobe,
    mfm_last_byte => fdc_mfm_byte,
    mfm_quantised_gap => fdc_quantised_gap,

    autotune_step => autotune_step,
    autotune_stepdir => autotune_stepdir,

    target_track => target_track,
    target_sector => target_sector,
    target_side => target_side,
    target_any => target_any,

    track_info_track => dd_track_info_track,
    track_info_rate => dd_track_info_rate,
    track_info_encoding => dd_track_info_encoding,
    track_info_sectors => dd_track_info_sectors,
    track_info_valid => dd_track_info_valid,

    sector_data_gap => fdc_sector_data_gap,
    sector_found => fdc_sector_found,
    found_track => found_track,
    found_sector => found_sector,
    found_side => found_side,

    first_byte => fdc_first_byte,
    byte_valid => fdc_byte_valid,
    byte_out => fdc_byte_out,
    crc_error => fdc_crc_error,
    sector_end => fdc_sector_end
    );

  mfmhdonly: entity work.mfm_decoder generic map ( unit_id => 2 )
    port map (
    clock40mhz => clock,
    f_rdata => f_rdata_drive,
    encoding_mode => x"0", -- Always MFM for HD-rate TIB decoder
    cycles_per_interval => to_unsigned(40,8),
    invalidate => fdc_read_invalidate,

    target_track => target_track,
    target_sector => target_sector,
    target_side => target_side,
    target_any => target_any,

    track_info_track => hd_track_info_track,
    track_info_rate => hd_track_info_rate,
    track_info_encoding => hd_track_info_encoding,
    track_info_sectors => hd_track_info_sectors,
    track_info_valid => hd_track_info_valid

    );


  -- Variable-rate MFM decoder, used so that we can easily
  -- detect and use HD and HD+ formatted disks, without having to
  -- have a program figure it out.
  -- Also, we ALWAYS enable variable recording rate for the
  -- HD decoder, as we are only going to make HD disks with
  -- it enabled.  We set the variable encoding rate based
  -- on what we read from the track info block.
  mfm_fast: entity work.mfm_decoder generic map ( unit_id => 3)
    port map (
    clock40mhz => clock,
    f_rdata => f_rdata_drive,
    encoding_mode => fdc_encoding_mode,
    cycles_per_interval => cycles_per_interval_actual,
    invalidate => fdc_read_invalidate,

    -- No MFM debug data from the 2x decoder
--    packed_rdata => packed_rdata,
--    mfm_state => fdc_mfm_state,
--    mfm_last_gap => fdc_last_gap,
--    mfm_last_byte => fdc_mfm_byte,
--    mfm_quantised_gap => fdc_quantised_gap,

    autotune_step => autotune2x_step,
    autotune_stepdir => autotune2x_stepdir,

    target_track => target_track,
    target_sector => target_sector,
    target_side => target_side,
    target_any => target_any,

    sector_data_gap => fdc_sector_data_gap_2x,
    sector_found => fdc_sector_found_2x,
    found_track => found_track_2x,
    found_sector => found_sector_2x,
    found_side => found_side_2x,

    first_byte => fdc_first_byte_2x,
    byte_valid => fdc_byte_valid_2x,
    byte_out => fdc_byte_out_2x,
    crc_error => fdc_crc_error_2x,
    sector_end => fdc_sector_end_2x
    );

  qspi_clock <= qspi_clock_int;
  process (qspi_clock_int) is
  begin
    report "qspi_clock <= " & std_logic'image(qspi_clock_int);
  end process;

  -- XXX also implement F011 floppy controller emulation.
  process (clock,fastio_addr,fastio_wdata,sector_buffer_mapped,sdio_busy,
           sd_reset,fastio_read,sd_sector,fastio_write,
           f011_track,f011_sector,f011_side,sdio_fsm_error,sdio_error,
           sd_state,f011_irqenable,f011_ds,f011_cmd,f011_busy,f011_crc,
           f011_track0,f011_rsector_found,f011_over_index,
           sdhc_mode,sd_datatoken, sd_rdata,
           diskimage1_enable,f011_disk1_present,
           f011_disk1_write_protected,diskimage2_enable,f011_disk2_present,
           f011_disk2_write_protected,diskimage_sector,diskimage2_sector,sw,btn,aclmiso,
           aclmosiinternal,aclssinternal,aclSCKinternal,aclint1,aclint2,
           tmpsdainternal,tmpsclinternal,tmpint,tmpct,tmpint,last_scan_code,
           pcm_left,
           sectorbuffercs,f011_cs,f011_led,f011_head_side,f011_drq,
           f011_lost,f011_wsector_found,f011_write_gate,f011_irq,
           f011_buffer_rdata,f011_reg_clock,f011_reg_step,f011_reg_pcode,
           last_sd_state,f011_buffer_disk_address,f011_buffer_cpu_address,
           f011_flag_eq,sdcardio_cs,colourram_at_dc00,viciii_iomode,
           f_index,f_track0,f_writeprotect,f_rdata,f_rdata_drive,f_diskchanged,
           use_real_floppy0,use_real_floppy2,target_any,fdc_first_byte,fdc_sector_end,
           fdc_sector_data_gap,fdc_sector_found,fdc_byte_valid,
           fdc_read_request,cycles_per_interval,found_track,
           found_sector,found_side,fdc_byte_out,fdc_mfm_state,
           fdc_mfm_byte,fdc_last_gap,packed_rdata,fdc_quantised_gap,
           fdc_bytes_read,fpga_temperature,
           fdc_encoding_mode,
           f_wdata_rll,fw_no_data_rll,fw_ready_for_next_rll,
           f_wdata_mfm,fw_no_data_mfm,fw_ready_for_next_mfm,
           f_wdata_raw,fw_no_data_raw,fw_ready_for_next_raw,
           hypervisor_mode,f011sd_buffer_select,fastio_addr_fast,secure_mode,
           f011_motor,f011_swap,f011_rnf,f011_write_protected,f011_disk_present,
           f011_disk_changed,sb_cpu_rdata,last_sd_rxbyte,f011_eq_inhibit,
           sd_interface_select_internal,sdcard_busy,sd_handshake,sd_data_ready,
           f011_swap_drives,qspi_bytes_differ,virtualise_f011_drive0,
           virtualise_f011_drive1,f011_d64_disk,f011_d64_disk2,f011_mega_disk,
           f011_mega_disk2,fdc_write_byte_number,autotune_enable,j21in,dipsw,dipsw_hi,
           latched_disk_change_event,fdc_sector_found_2x,fdc_sector_end_2x,
           silent_sdcard,fdc_crc_error,fdc_2x_select,found_track_2x,
           found_sector_2x,found_side_2x,track_info_track,track_info_rate,
           track_info_encoding,track_info_sectors,volume_knob3_target,
           pwm_knob_en,volume_knob1_target,volume_knob2_target,
           auto_fdc_2x_select,fdc_variable_data_rate,use_tib_info,
           touch1_active,touch2_active,touch1_status,touch2_status,
           touch_flip_x_internal,touch_flip_y_internal,touch_scale_x_internal,
           touch_scale_y_internal,touch_delta_x_internal,touch_delta_y_internal,
           touch_x1,touch_y1,touch_x2,touch_y2,touch_enabled_internal,
           touch_byte,gesture_event,gesture_event_id,flash_boot_address,
           reconfigure_address_int,qspidb_tristate,qspi_csn_int,qspi_clock_int,
           QspiDB_in,qspi_clock_run,f_wdata_minimum,i2c_bus_id,i2c0_reset_internal,
           i2c0_command_en_internal,i2c0_rw_internal,i2c0_busy,i2c0_error,
           i2c1_reset_internal,i2c1_command_en_internal,i2c1_rw_internal,i2c1_busy,
           i2c1_error,i2c0_address_internal,i2c1_address_internal,i2c0_wdata_internal,
           i2c1_wdata_internal,i2c0_rdata,i2c1_rdata,debug_track_format_counter,
           debug_track_format_sync_wait_counter,last_sd_error,lcdpwm_value,
           audio_mix_reg_int,audio_mix_rdata,pcm_right,audio_loopback,
           sectorbuffercs_fast,fastio_rdata,fastio_rdata_ram,f011_sector_fetch,
           sd_buffer_offset
           ) is
    variable temp_cmd : unsigned(7 downto 0);
  begin

    -- ==================================================================
    -- here is a combinational process (ie: not clocked)
    -- ==================================================================

    if hypervisor_mode='0' then
      sector_buffer_fastio_address <= resolve_sector_buffer_address(f011sd_buffer_select,fastio_addr_fast(8 downto 0));
    else
      sector_buffer_fastio_address <= to_integer(fastio_addr_fast(11 downto 0));
    end if;

    fastio_rdata <= (others => 'Z');

    if fastio_read='1' and sectorbuffercs='0' then

      if f011_cs='1' and sdcardio_cs='0' and secure_mode='0' then
        -- F011 FDC emulation registers
--        report "Preparing to read F011 emulation register @ $" & to_hstring(fastio_addr);

        case fastio_addr(4 downto 0) is
          when "00000" =>
            -- CONTROL |  IRQ  |  LED  | MOTOR | SWAP  | SIDE  |  DS2  |  DS1  |  DS0  | 0 RW
            --IRQ     When set, enables interrupts to occur,  when reset clears and
            --        disables interrupts.
            --LED     These  two  bits  control  the  state  of  the  MOTOR and LED
            --MOTOR   outputs. When both are clear, both MOTOR and LED outputs will
            --        be off. When MOTOR is set, both MOTOR and LED Outputs will be
            --        on. When LED is set, the LED will "blink".
            --SWAP    swaps upper and lower halves of the data buffer
            --        as seen by the CPU.
            --SIDE    when set, sets the SIDE output to 0, otherwise 1.
            --DS2-DS0 these three bits select a drive (drive 0 thru drive 7).  When
            --        DS0-DS2  are  low  and  the LOCAL input is true (low) the DR0
            --        output will go true (low).
            fastio_rdata <=
              f011_irqenable & f011_led & f011_motor & f011_swap &
              f011_head_side(0) & f011_ds;
          when "00001" =>
            -- COMMAND | WRITE | READ  | FREE  | STEP  |  DIR  | ALGO  |  ALT  | NOBUF | 1 RW
            --WRITE   must be set to perform write operations.
            --READ    must be set for all read operations.
            --FREE    allows free-format read or write vs formatted
            --STEP    write to 1 to cause a head stepping pulse.
            --DIR     sets head stepping direction
            --ALGO    selects read and write algorithm. 0=FC read, 1=DPLL read,
            --        0=normal write, 1=precompensated write.

            --ALT     selects alternate DPLL read recovery method. The ALG0 bit
            --        must be set for ALT to work.
            --NOBUF   clears the buffer read/write pointers
            fastio_rdata <= f011_cmd;

          when "00010" =>             -- READ $D082
            -- @IO:C65 $D082 - F011 FDC Status A port (read only)
            -- @IO:C65 $D082.7 FDC:BUSY F011 FDC busy flag (command is being executed) (read only)
            -- @IO:C65 $D082.6 FDC:DRQ F011 FDC DRQ flag (one or more bytes of data are ready) (read only)
            -- @IO:C65 $D082.5 FDC:EQ F011 FDC CPU and disk pointers to sector buffer are equal, indicating that the sector buffer is either full or empty. (read only)
            -- @IO:C65 $D082.4 FDC:RNF F011 FDC Request Not Found (RNF), i.e., a sector read or write operation did not find the requested sector (read only)
            -- @IO:C65 $D082.3 FDC:CRC F011 FDC CRC check failure flag (read only)
            -- @IO:C65 $D082.2 FDC:LOST F011 LOST flag (data was lost during transfer, i.e., CPU did not read data fast enough) (read only)
            -- @IO:C65 $D082.1 FDC:PROT F011 Disk write protect flag (read only)
            -- @IO:C65 $D082.0 FDC:TK0 F011 Head is over track 0 flag (read only)
            -- STAT A  | BUSY  |  DRQ  |  EQ   |  RNF  |  CRC  | LOST  | PROT  |  TKQ  | 2 R
            --BUSY    command is being executed
            --DRQ     disk interface has transferred a byte
            --EQ      buffer CPU/Disk pointers are equal
            --RNF     sector not found during formatted write or read
            --CRC     CRC check failed
            --LOST    data was lost during transfer
            --PROT    disk is write protected
            --TK0     head is positioned over track zero
            fastio_rdata <= f011_busy & f011_drq & f011_flag_eq & f011_rnf
                            & f011_crc & f011_lost & f011_write_protected
                            & f011_track0;

          when "00011" =>             -- READ $D083
            -- @IO:C65 $D083 - F011 FDC Status B port (read only)
            -- STAT B  | RDREQ | WTREQ |  RUN  | NGATE | DSKIN | INDEX |  IRQ  | DSKCHG| 3 R
            -- @IO:C65 $D083.7 FDC:RDREQ F011 Read Request flag, i.e., the requested sector was found during a read operation (read only)
            -- @IO:C65 $D083.6 FDC:WTREQ F011 Write Request flag, i.e., the requested sector was found during a write operation (read only)
            -- @IO:C65 $D083.5 FDC:RUN F011 Successive match.  A synonym of RDREQ on the 45IO47 (read only)
            -- @IO:C65 $D083.4 FDC:WGATE F011 write gate flag. Indicates that the drive is currently writing to media.  Bad things may happen if a write transaction is aborted (read only)
            -- @IO:C65 $D083.3 FDC:DISKIN F011 Disk sense (read only)
            -- @IO:C65 $D083.2 FDC:INDEX F011 Index hole sense (read only)
            -- @IO:C65 $D083.1 FDC:IRQ The floppy controller has generated an interrupt (read only). Note that interrupts are not currently implemented on the 45GS27.
            -- @IO:C65 $D083.0 FDC:DSKCHG F011 disk change sense (read only)
            -- RDREQ   sector found during formatted read
            -- WTREQ   sector found during formatted write
            -- RUN     indicates successive matches during find operation
            --         (that so far, the found sector matches the requested sector)
            -- WGATE   write gate is on
            -- DSKIN   indicates that a disk is inserted in the drive
            -- INDEX   disk index is currently over sensor
            -- IRQ     an interrupt has occurred
            -- DSKCHG  the DSKIN line has changed
            --         this is cleared by deselecting drive
            fastio_rdata <= f011_rsector_found & f011_wsector_found &
                            f011_rsector_found & f011_write_gate & f011_disk_present &
                            f011_over_index & f011_irq & f011_disk_changed;

          when "00100" =>
            -- TRACK   |  T7   |  T6   |  T5   |  T4   |  T3   |  T2   |  T1   |  T0   | 4 RW
            fastio_rdata <= f011_track;

          when "00101" =>
            -- SECTOR  |  S7   |  S6   |  S5   |  S4   |  S3   |  S2   |  S1   |  S0   | 5 RW
            fastio_rdata <= f011_sector;

          when "00110" =>
            -- SIDE    |  S7   |  S6   |  S5   |  S4   |  S3   |  S2   |  S1   |  S0   | 6 RW
            fastio_rdata <= f011_side;

          when "00111" =>  -- $D087
            -- DATA    |  D7   |  D6   |  D5   |  D4   |  D3   |  D2   |  D1   |  D0   | 7 RW
            fastio_rdata <= sb_cpu_rdata;

          when "01000" => -- $D088
            -- CLOCK   |  C7   |  C6   |  C5   |  C4   |  C3   |  C2   |  C1   |  C0   | 8 RW
            fastio_rdata <= f011_reg_clock;

          when "01001" => -- $D089
            -- @IO:65 $D089 - F011 FDC step time (x62.5 micro seconds)
            -- STEP    |  S7   |  S6   |  S5   |  S4   |  S3   |  S2   |  S1   |  S0   | 9 RW
            fastio_rdata <= f011_reg_step;

          when "01010" => -- $D08A
            -- P CODE  |  P7   |  P6   |  P5   |  P4   |  P3   |  P2   |  P1   |  P0   | A R
            fastio_rdata <= f011_reg_pcode;
          when "01111" => -- @IO:GS $D08F - Set/get MISCIO:HWERRATA MEGA65 hardware errata level
            fastio_rdata <= hw_errata_level_int;
          when "11011" => -- @IO:GS $D09B - FSM state of low-level SD controller (DEBUG)
            fastio_rdata <= last_sd_state;
          when "11100" => -- @IO:GS $D09C - Last byte low-level SD controller read from card (DEBUG)
            fastio_rdata <= last_sd_rxbyte;
          when "11101" => -- @IO:GS $D09D - FDC-side buffer pointer high bit (DEBUG)
            fastio_rdata(0) <= f011_buffer_disk_address(8);
            fastio_rdata(7 downto 1) <= (others => '0');
          when "11110" => -- @IO:GS $D09E - CPU-side buffer pointer low bits (DEBUG)
            fastio_rdata <= f011_buffer_cpu_address(7 downto 0);
          when "11111" =>
            -- @IO:GS $D09F.0 - CPU-side buffer pointer high bit (DEBUG)
            -- @IO:GS $D09F.1 - EQ flag (DEBUG)
            -- @IO:GS $D09F.2 - EQ flag inhibit state (DEBUG)
            fastio_rdata(0) <= f011_buffer_cpu_address(8);
            fastio_rdata(1) <= f011_flag_eq;
            fastio_rdata(2) <= f011_eq_inhibit;
            fastio_rdata(7 downto 3) <= (others => '0');

          when others =>
            fastio_rdata <= (others => 'Z');
        end case;

        -- ==================================================================

      -- XXX Simplify this by putting all secure accessible things in one place?
      elsif (sdcardio_cs='1' and f011_cs='0')
        and (secure_mode='0' or fastio_addr(7 downto 4) = x"B" or fastio_addr(7 downto 4) = x"F") then
        -- microSD controller registers
--        report "reading SDCARD register $" & to_hstring(fastio_addr(7 downto 0)) severity note;
        case fastio_addr(7 downto 0) is
          -- @IO:GS $D680.0 - SD controller BUSY flag
          -- @IO:GS $D680.1 - SD controller BUSY flag
          -- @IO:GS $D680.2 - SD controller RESET flag
          -- @IO:GS $D680.3 - SD controller sector buffer mapped flag
          -- @IO:GS $D680.4 - SD controller SDHC mode flag
          -- @IO:GS $D680.5 - SD controller SDIO FSM ERROR flag
          -- @IO:GS $D680.6 - SD controller SDIO error flag
          -- @IO:GS $D680.7 - SD controller primary / secondary SD card
          when x"80" =>
            -- status / command register
            -- error status in bit 6 so that V flag can be used for check
            report "reading $D680 SDCARD status register" severity note;
            fastio_rdata(7) <= sd_interface_select_internal;
            fastio_rdata(6) <= sdio_error;
            fastio_rdata(5) <= sdio_fsm_error;
            fastio_rdata(4) <= sdhc_mode;
            fastio_rdata(3) <= sector_buffer_mapped;
            fastio_rdata(2) <= sd_reset;
            fastio_rdata(1) <= sdcard_busy;  -- Whether the SD card thinks it is busy
            fastio_rdata(0) <= sdio_busy;  -- Whether we think we are busy

          when x"81" => fastio_rdata <= sd_sector(7 downto 0); -- SD-control, LSByte of address
          when x"82" => fastio_rdata <= sd_sector(15 downto 8); -- SD-control
          when x"83" => fastio_rdata <= sd_sector(23 downto 16); -- SD-controll
          when x"84" => fastio_rdata <= sd_sector(31 downto 24); -- SD-control, MSByte of address

          -- @IO:GS $D685 - DEBUG Show current state ID of SD card interface
          when x"85" => fastio_rdata <= to_unsigned(sd_state_t'pos(sd_state),8);
          -- @IO:GS $D686 - DEBUG SD card data token
          when x"86" => fastio_rdata <= sd_datatoken;
          -- @IO:GS $D687 - DEBUG SD card most recent byte read
          when x"87" => fastio_rdata <= unsigned(sd_rdata);
          -- @IO:GS $D688 - Low-byte of F011 buffer pointer (disk side) (read only)
          when x"88" => fastio_rdata <= f011_buffer_disk_address(7 downto 0);
          -- @IO:GS $D689.0 - High bit of F011 buffer pointer (disk side) (read only)
          -- @IO:GS $D689.1 - Sector read from SD/F011/FDC, but not yet read by CPU (i.e., EQ and DRQ)
          -- @IO:GS $D689.2 - (read only, debug) sd_handshake signal.
          -- @IO:GS $D689.3 - (read only, debug) sd_data_ready signal.
          -- @IO:GS $D689.4 - RESERVED
          -- @IO:GS $D689.5 - F011 swap drive 0 / 1
          -- @IO:GS $D689.6 - QSPI bytes not all identical during last read
          -- @IO:GS $D689.7 - Memory mapped sector buffer select: 1=SD-Card, 0=F011/FDC
          when x"89" =>
            fastio_rdata(0) <= f011_buffer_disk_address(8);
            fastio_rdata(1) <= f011_flag_eq and f011_drq;
            fastio_rdata(2) <= sd_handshake;
            fastio_rdata(3) <= sd_data_ready;
            fastio_rdata(4) <= '0';
            fastio_rdata(5) <= f011_swap_drives;
            fastio_rdata(6) <= qspi_bytes_differ;
            fastio_rdata(7) <= f011sd_buffer_select;
          when x"8a" =>
            -- @IO:GS $D68A - DEBUG check signals that can inhibit sector buffer mapping
            -- @IO:GS $D68A.0 SD:CDC00 (read only) Set if colour RAM at $DC00
            -- @IO:GS $D68A.1 SD:VICIII (read only) Set if VIC-IV or ethernet IO bank visible
            -- @IO:GS $D68A.2 SD:VFDC0 (read only) Set if drive 0 is virtualised (sectors delivered via serial monitor interface)
            -- @IO:GS $D68A.3 SD:VFDC1 (read only) Set if drive 1 is virtualised (sectors delivered via serial monitor interface)
            fastio_rdata(0) <= colourram_at_dc00;
            fastio_rdata(1) <= viciii_iomode(1);
            fastio_rdata(2) <= virtualise_f011_drive0;
            fastio_rdata(3) <= virtualise_f011_drive1;

            fastio_rdata(6) <= f011_d64_disk;
            fastio_rdata(7) <= f011_d64_disk2;

          when x"8b" =>
            -- BG the description seems in conflict with the assignment in the write section (below)
            -- @IO:GS $D68B - Diskimage control flags
            fastio_rdata(0) <= diskimage1_enable;
            fastio_rdata(1) <= f011_disk1_present;
            fastio_rdata(2) <= not f011_disk1_write_protected;
            fastio_rdata(3) <= diskimage2_enable;
            fastio_rdata(4) <= f011_disk2_present;
            fastio_rdata(5) <= not f011_disk2_write_protected;
            -- @IO:GS $D68B.6 F011:MDISK0 Enable D65 ``MEGA Disk'' for F011 emulated drive 0
            -- @IO:GS $D68B.7 F011:MDISK0 Enable D65 ``MEGA Disk'' for F011 emulated drive 1
            fastio_rdata(6) <= f011_mega_disk;
            fastio_rdata(7) <= f011_mega_disk2;
          when x"8c" =>
            -- @IO:GS $D68C F011:DISKADDR0 Diskimage sector number (bits 0-7)
            fastio_rdata <= diskimage_sector(7 downto 0);
          when x"8d" =>
            -- @IO:GS $D68D F011:DISKADDR1 Diskimage sector number (bits 8-15)
            fastio_rdata <= diskimage_sector(15 downto 8);
          when x"8e" =>
            -- @IO:GS $D68E F011:DISKADDR2 Diskimage sector number (bits 16-23)
            fastio_rdata <= diskimage_sector(23 downto 16);
          when x"8f" =>
            -- @IO:GS $D68F F011:DISKADDR3 Diskimage sector number (bits 24-31)
            fastio_rdata <= diskimage_sector(31 downto 24);

          when x"90" =>
            -- @IO:GS $D690 F011:DISK2ADDR0 Diskimage 2 sector number (bits 0-7)
            fastio_rdata <= diskimage2_sector(7 downto 0);
          when x"91" =>
            -- @IO:GS $D691 F011:DISK2ADDR1 Diskimage 2 sector number (bits 8-15)
            fastio_rdata <= diskimage2_sector(15 downto 8);
          when x"92" =>
            -- @IO:GS $D692 F011:DISK2ADDR2 Diskimage 2 sector number (bits 16-23)
            fastio_rdata <= diskimage2_sector(23 downto 16);
          when x"93" =>
            -- @IO:GS $D693 F011:DISK2ADDR3 Diskimage 2 sector number (bits 24-31)
            fastio_rdata <= diskimage2_sector(31 downto 24);
          when x"94" =>
            fastio_rdata <= to_unsigned(fdc_write_byte_number,10)(7 downto 0);
          when x"95" =>
            fastio_rdata <= "000000"&(to_unsigned(fdc_write_byte_number,10)(9 downto 8));
          when x"96" =>
            -- @IO:GS $D696 F011:AUTOTUNE Enable automatic track seeking for sector reads and writes
            fastio_rdata(6 downto 0) <= "0000000";
            fastio_rdata(7) <= autotune_enable;
          when x"9b" =>
            -- @IO:GS $D69B DEBUG:J21INL Status of M65 R3 J21 pins
            fastio_rdata(7 downto 0) <= unsigned(j21in(7 downto 0));
          when x"9c" =>
            -- @IO:GS $D69C DEBUG:J21INH Status of M65 R3 J21 pins
            fastio_rdata(3 downto 0) <= unsigned(j21in(11 downto 8));
            fastio_rdata(7 downto 4) <= "0000";
          when x"9d" =>
            -- @IO:GS $D69D.0-4 DEBUG:DIPSW Status of M65 R3/R3A/R4 DIP switches
            -- @IO:GS $D69D.5-7 DEBUG:DIPSWHI Status of M65 R5 DIP switches
            fastio_rdata(4 downto 0) <= unsigned(dipsw);
            fastio_rdata(7 downto 5) <= unsigned(dipsw_hi);
          when x"9e" =>
            -- @IO:GS $D69E DEBUG:SWSTATUS Status of switches 0 to 7
            fastio_rdata(7 downto 0) <= unsigned(sw(7 downto 0));
          when x"9f" =>
            -- @IO:GS $D69F DEBUG:SWSTATUS Status of switches 8 to 15
            fastio_rdata(7 downto 0) <= unsigned(sw(15 downto 8));
          when x"a0" =>
            -- @IO:GS $D6A0 - DEBUG FDC read status lines
            fastio_rdata(7) <= f_index;
            fastio_rdata(6) <= f_track0;
            fastio_rdata(5) <= f_writeprotect;
            fastio_rdata(4) <= f_rdata;
            fastio_rdata(3) <= f_diskchanged;
            fastio_rdata(2) <= latched_disk_change_event;
            fastio_rdata(1) <= fdc_sector_found_2x;
            fastio_rdata(0) <= fdc_sector_end_2x;
          when x"a1" =>
            -- @IO:GS $D6A1.0 F011:DRV0EN Use real floppy drive instead of SD card for 1st floppy drive
            fastio_rdata(0) <= use_real_floppy0;
            -- @IO:GS $D6A1.2 F011:DRV2EN Use real floppy drive instead of SD card for 2nd floppy drive
            fastio_rdata(2) <= use_real_floppy2;
            -- @IO:GS $D6A1.1 - Match any sector on a real floppy read/write
            fastio_rdata(1) <= target_any;
            fastio_rdata(3) <= silent_sdcard;
            -- @IO:GS $D6A1.4-7 F011:STATUS FDC debug status flags
            fastio_rdata(4) <= fdc_crc_error;
            fastio_rdata(5) <= fdc_sector_found;
            fastio_rdata(6) <= fdc_byte_valid;
            fastio_rdata(7) <= fdc_read_request;
          when x"a2" =>
            -- @IO:GS $D6A2 - FDC clock cycles per MFM data bit
            fastio_rdata <= cycles_per_interval;
          when x"a3" =>
            -- @IO:GS $D6A3 - FDC track number of last matching sector header
            if fdc_2x_select='1' then
              fastio_rdata <= found_track_2x;
            else
              fastio_rdata <= found_track;
            end if;
          when x"a4" =>
            -- @IO:GS $D6A4 - FDC sector number of last matching sector header
            if fdc_2x_select='1' then
              fastio_rdata <= found_sector_2x;
            else
              fastio_rdata <= found_sector;
            end if;
          when x"a5" =>
            -- @IO:GS $D6A5 - FDC side number of last matching sector header
            if fdc_2x_select='1' then
              fastio_rdata <= found_side_2x;
            else
              fastio_rdata <= found_side;
            end if;
          when x"a6" =>
            -- @IO:GS $D6A6 - SD:TITRACK Track number from track info block (or $FF if not yet received)
            fastio_rdata <= track_info_track;
          when x"a7" =>
            -- @IO:GS $D6A7 - SD:TIRATE Track data rate from track info block
            fastio_rdata <= track_info_rate;
          when x"a8" =>
            -- @IO:GS $D6A8 - SD:TIENCODING Track encoding from track info block ($x1 = RLL2,7, $x0 = MFM, $4x = track-at-once, $0x = individually writable sectors)
            fastio_rdata <= track_info_encoding;
          when x"a9" =>
            -- @IO:GS $D6A9 - SD:TISECTORS Number of sectors from track info block
            fastio_rdata <= unsigned(track_info_sectors);
          when x"aa" =>
            -- @IO:GS $D6AA - DEBUG FDC last gap interval (LSB)
            fastio_rdata <= fdc_last_gap(7 downto 0);
          when x"ab" =>
            -- @IO:GS $D6AB - DEBUG FDC last gap interval (MSB)
            fastio_rdata <= fdc_last_gap(15 downto 8);
          when x"ac" =>
            -- @IO:GS $D6AC.0-3 MISCIO:WHEEL3TARGET Select audio channel volume to be set by thumb wheel #3
            -- @IO:GS $D6AC.7 MISCIO:WHEELBRIGHTEN Enable control of LCD panel brightness via thumb wheel
            -- @IO:GS $D6AC.4-6 - PHONE:RESERVED
            fastio_rdata(3 downto 0) <= volume_knob3_target;
            fastio_rdata(6 downto 4) <= "000";
            fastio_rdata(7) <= pwm_knob_en;
          when x"ad" =>
            -- @IO:GS $D6AD.0-3 - PHONE:Volume knob 1 audio target
            -- @IO:GS $D6AD.4-7 - PHONE:Volume knob 2 audio target
            fastio_rdata(3 downto 0) <= volume_knob1_target;
            fastio_rdata(7 downto 4) <= volume_knob2_target;
          when x"ae" =>
            fastio_rdata(3 downto 0) <= unsigned(fdc_encoding_mode);
            fastio_rdata(4) <= auto_fdc_2x_select;
            fastio_rdata(5) <= fdc_variable_data_rate;
            fastio_rdata(6) <= fdc_2x_select;
            fastio_rdata(7) <= use_tib_info;
          when x"af" =>
            -- @IO:GS $D6AF - DEBUG FDC last quantised gap READ ONLY
            fastio_rdata <= unsigned(fdc_quantised_gap);
          when x"B0" =>
            -- @IO:GS $D6B0 - Touch pad control / status
            -- @IO:GS $D6B0.0 TOUCH:EV1 Touch event 1 is valid
            -- @IO:GS $D6B0.1 TOUCH:EV2 Touch event 2 is valid
            -- @IO:GS $D6B0.2-3 TOUCH:UPDN1 Touch event 1 up/down state
            -- @IO:GS $D6B0.5-4 TOUCH:UPDN2 Touch event 2 up/down state
            -- @IO:GS $D6B0.6 TOUCH:XINV Invert horizontal axis
            -- @IO:GS $D6B0.7 TOUCH:YINV Invert vertical axis
            fastio_rdata(0) <= touch1_active;
            fastio_rdata(1) <= touch2_active;
            fastio_rdata(3 downto 2) <= unsigned(touch1_status);
            fastio_rdata(5 downto 4) <= unsigned(touch2_status);
            fastio_rdata(6) <= touch_flip_x_internal;
            fastio_rdata(7) <= touch_flip_y_internal;
          when x"B1" =>
            -- @IO:GS $D6B1 TOUCH:CALXSCALELSB Touch pad X scaling LSB
            fastio_rdata <= touch_scale_x_internal(7 downto 0);
          when x"B2" =>
            -- @IO:GS $D6B2 TOUCH:CALXSCALEMSB Touch pad X scaling MSB
            fastio_rdata <= touch_scale_x_internal(15 downto 8);
          when x"B3" =>
            -- @IO:GS $D6B3 TOUCH:CALYSCALELSB Touch pad Y scaling LSB
            fastio_rdata <= touch_scale_y_internal(7 downto 0);
          when x"B4" =>
            -- @IO:GS $D6B4 TOUCH:CALYSCALEMSB Touch pad Y scaling MSB
            fastio_rdata <= touch_scale_y_internal(15 downto 8);
          when x"B5" =>
            -- @IO:GS $D6B5 TOUCH:CALXDELTALSB Touch pad X delta LSB
            fastio_rdata <= touch_delta_x_internal(7 downto 0);
          when x"B6" =>
            -- @IO:GS $D6B6 TOUGH:CALXDELTAMSB Touch pad X delta MSB
            fastio_rdata <= touch_delta_x_internal(15 downto 8);
          when x"B7" =>
            -- @IO:GS $D6B7 TOUCH:CALYDELTALSB Touch pad Y delta LSB
            fastio_rdata <= touch_delta_y_internal(7 downto 0);
          when x"B8" =>
            -- @IO:GS $D6B8 TOUCH:CALYDELTAMSB Touch pad Y delta MSB
            fastio_rdata <= touch_delta_y_internal(15 downto 8);
          when x"B9" =>
            -- @IO:GS $D6B9 TOUCH:TOUCH1XLSB Touch pad touch #1 X LSB
            fastio_rdata <= touch_x1(7 downto 0);
          when x"BA" =>
            -- @IO:GS $D6BA TOUCH:TOUCH1YLSB Touch pad touch #1 Y LSB
            fastio_rdata <= touch_y1(7 downto 0);
          when x"BB" =>
            -- @IO:GS $D6BB.0-1 TOUCH:TOUCH1XMSB Touch pad touch \#1 X MSBs
            -- @IO:GS $D6BB.5-4 TOUCH:TOUCH1YMSB Touch pad touch \#1 Y MSBs
            fastio_rdata(1 downto 0) <= touch_x1(9 downto 8);
            fastio_rdata(5 downto 4) <= touch_y1(9 downto 8);
          when x"BC" =>
            -- @IO:GS $D6BC TOUCH:TOUCH2XLSB Touch pad touch \#2 X LSB
            fastio_rdata <= touch_x2(7 downto 0);
          when x"BD" =>
            -- @IO:GS $D6BD TOUCH:TOUCH2YLSB Touch pad touch \#2 Y LSB
            fastio_rdata <= touch_y2(7 downto 0);
          when x"BE" =>
            -- @IO:GS $D6BE.0-1 TOUCH:TOUCH2XMSB Touch pad touch \#2 X MSBs
            -- @IO:GS $D6BE.5-4 TOUCH:TOUCH2YMSB Touch pad touch \#2 Y MSBs
            fastio_rdata(1 downto 0) <= touch_x2(9 downto 8);
            fastio_rdata(5 downto 4) <= touch_y2(9 downto 8);
          when x"BF" =>
            fastio_rdata(7) <= touch_enabled_internal;
            -- XXX DEBUG temporary
            fastio_rdata(6 downto 0) <= touch_byte(6 downto 0);
          when x"C0" =>
            -- @IO:GS $D6C0.0-3 TOUCH:GESTUREDIR Touch pad gesture directions (left,right,up,down)
            -- @IO:GS $D6C0.7-4 TOUCH:GESTUREID Touch pad gesture ID
            fastio_rdata(3 downto 0) <= gesture_event;
            fastio_rdata(7 downto 4) <= gesture_event_id;
          -- @IO:GS $D6C8-B - Address currently loaded bitstream was fetched from flash memory.
          when x"C4" =>
            -- @IO:GS $D6C4 FPGA:REGVAL Value of selected ICAPE2 register (least significant byte)
            -- @IO:GS $D6C5 FPGA:REGVAL Value of selected ICAPE2 register
            -- @IO:GS $D6C6 FPGA:REGVAL Value of selected ICAPE2 register
            -- @IO:GS $D6C7 FPGA:REGVAL Value of selected ICAPE2 register (most significant byte)
            fastio_rdata <= flash_boot_address(7 downto 0);
          when x"C5" =>
            fastio_rdata <= flash_boot_address(15 downto 8);
          when x"C6" =>
            fastio_rdata <= flash_boot_address(23 downto 16);
          when x"C7" =>
            fastio_rdata <= flash_boot_address(31 downto 24);
          when x"C8" =>
            fastio_rdata <= reconfigure_address_int(7 downto 0);
          when x"C9" =>
            fastio_rdata <= reconfigure_address_int(15 downto 8);
          when x"CA" =>
            fastio_rdata <= reconfigure_address_int(23 downto 16);
          when x"CB" =>
            fastio_rdata <= reconfigure_address_int(31 downto 24);
          when x"CC" =>
            fastio_rdata(7) <= qspidb_tristate;
            fastio_rdata(6) <= qspi_csn_int;
            fastio_rdata(5) <= qspi_clock_int;
            fastio_rdata(4) <= '0';
            fastio_rdata(3 downto 0) <= qspidb_in;
          when x"CD" =>
            fastio_rdata(0) <= qspi_clock_run;
            fastio_rdata(1) <= qspi_clock_int;
            fastio_rdata(7 downto 2) <= (others => '0');
          when x"CE" =>
            fastio_rdata <= to_unsigned(f_wdata_minimum,8);
          when x"D0" =>
            -- @IO:GS $D6D0 MISC:I2CBUSSELECT I2C bus select (bus 0 = temp sensor on Nexys4 boardS)
            fastio_rdata <= i2c_bus_id;
          when x"D1" =>
            fastio_rdata <= (others => '0');
            if i2c_bus_id = x"00" then
              fastio_rdata(0) <= i2c0_reset_internal;
              fastio_rdata(1) <= i2c0_command_en_internal;
              fastio_rdata(2) <= i2c0_rw_internal;
              fastio_rdata(6) <= i2c0_busy;
              fastio_rdata(7) <= i2c0_error;
            elsif i2c_bus_id = x"01" then
              fastio_rdata(0) <= i2c1_reset_internal;
              fastio_rdata(1) <= i2c1_command_en_internal;
              fastio_rdata(2) <= i2c1_rw_internal;
              fastio_rdata(6) <= i2c1_busy;
              fastio_rdata(7) <= i2c1_error;
            end if;
          when x"D2" =>
            fastio_rdata <= (others => '0');
            if i2c_bus_id = x"00" then
              fastio_rdata(7 downto 1) <= i2c0_address_internal;
            elsif i2c_bus_id = x"01" then
              fastio_rdata(7 downto 1) <= i2c1_address_internal;
            end if;
          when x"D3" =>
            fastio_rdata <= (others => '0');
            if i2c_bus_id = x"00" then
              fastio_rdata <= i2c0_wdata_internal;
            elsif i2c_bus_id = x"01" then
              fastio_rdata <= i2c1_wdata_internal;
            end if;
          when x"D4" =>
            fastio_rdata <= (others => '0');
            if i2c_bus_id = x"00" then
              fastio_rdata <= i2c0_rdata;
            elsif i2c_bus_id = x"01" then
              fastio_rdata <= i2c1_rdata;
            end if;
          when x"D5" =>
            fastio_rdata <= debug_track_format_counter;
          when x"D6" =>
            fastio_rdata <= debug_track_format_sync_wait_counter;
          when x"da" =>
            -- @IO:GS $D6DA MISC:SDDEBUGERRLSB DEBUG SD card last error code LSB
            fastio_rdata(7 downto 0) <= unsigned(last_sd_error(7 downto 0));
          when x"db" =>
            -- @IO:GS $D6DB MISC:SDDEBUGERRMSB DEBUG SD card last error code MSB
            fastio_rdata(7 downto 0) <= unsigned(last_sd_error(15 downto 8));
          when x"DE" =>
            -- @IO:GS $D6DE FPGA:FPGATEMPLSB FPGA die temperature sensor (lower nybl)
            fastio_rdata <= unsigned("0000"&fpga_temperature(3 downto 0));
          when x"DF" =>
            -- @IO:GS $D6DF FPGA:FPGATEMPMSB FPGA die temperature sensor (upper byte)
            fastio_rdata <= unsigned(fpga_temperature(11 downto 4));
          -- XXX $D6Ex is decoded by ethernet controller, so don't use those
            -- registers here!
          when x"F0" =>
            -- @IO:GS $D6F0 MISC:LCDBRIGHTNESS LCD panel brightness control
            fastio_rdata <= lcdpwm_value;
          when x"F2" =>
            -- @IO:GS $D6F2 MISC:FPGABUTTONS Read FPGA five-way buttons
            fastio_rdata(7 downto 5) <= "000";
            fastio_rdata(4 downto 0) <= unsigned(btn(4 downto 0));
          when x"F3" =>
            -- @IO:GS $D6F3 MISC:ACCELBITBASH Accelerometer bit-bash interface
            fastio_rdata(0) <= aclMISO;
            fastio_rdata(1) <= aclMOSIinternal;
            fastio_rdata(2) <= aclSSinternal;
            fastio_rdata(3) <= aclSCKinternal;
            fastio_rdata(4) <= '0';
            fastio_rdata(5) <= aclInt1;
            fastio_rdata(6) <= aclInt2;
            fastio_rdata(7) <= aclInt1 or aclInt2;
          when x"F4" =>
            -- @IO:GS $D6F4 AUDIO:MIXREGSEL Audio Mixer register select
            fastio_rdata <= audio_mix_reg_int;
          when x"F5" =>
            -- @IO:GS $D6F5 AUDIO:MIXREGDATA Audio Mixer register read port
            if audio_mix_reg_int(0)='1' then
              fastio_rdata <= audio_mix_rdata(15 downto 8);
            else
              fastio_rdata <= audio_mix_rdata(7 downto 0);
            end if;
          when x"F6" =>
            -- @IO:GS $D6F6 MISC:PS2KEYSCANLSB Keyboard scan code reader (lower byte)
            fastio_rdata <= unsigned(last_scan_code(7 downto 0));
          when x"F7" =>
            -- @IO:GS $D6F7 MISC:PS2KEYSCANMSB Keyboard scan code reader (upper nybl)
            fastio_rdata <= unsigned("000"&last_scan_code(12 downto 8));
          when x"F8" =>
            -- @IO:GS $D6F8 AUDIO:DIGILEFTLSB Digital audio, left channel, LSB
            fastio_rdata <= unsigned(pcm_left(7 downto 0));
          when x"F9" =>
            -- @IO:GS $D6F9 AUDIO:DIGILEFTMSB Digital audio, left channel, MSB
            fastio_rdata <= unsigned(pcm_left(15 downto 8));
          when x"FA" =>
            -- @IO:GS $D6FA AUDIO:DIGIRIGHTLSB Digital audio, left channel, LSB
            fastio_rdata <= unsigned(pcm_right(7 downto 0));
          when x"FB" =>
            -- @IO:GS $D6FB AUDIO:DIGIRIGHTMSB Digital audio, left channel, MSB
            fastio_rdata <= unsigned(pcm_right(15 downto 8));
          when x"FC" =>
            -- @IO:GS $D6FC AUDIO:READBACKLSB audio read-back LSB (source selected by $D6F4)
            fastio_rdata <= unsigned(audio_loopback(7 downto 0));
          when x"FD" =>
            -- @IO:GS $D6FD AUDIO:READBACKMSB audio read-back MSB (source selected by $D6F4)
            fastio_rdata <= unsigned(audio_loopback(15 downto 8));
          when others =>
            fastio_rdata <= (others => '0');
        end case;
      else
        -- Otherwise tristate output
        fastio_rdata <= (others => 'Z');
      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if;

    -- output select
    if (f011_cs='1' or sdcardio_cs='1' or sectorbuffercs='1' or sectorbuffercs_fast='1') and secure_mode='0' and fastio_read='1' then
--      report "Exporting value to fastio_read";
      if fastio_read='1' and sectorbuffercs='0' then
        fastio_rdata_sel <= fastio_rdata;
--        report "fastio_rdata(_sel) <= $" & to_hstring(fastio_rdata) & "(from register read)";
      elsif sectorbuffercs='1' then
--        report "fastio_rdata(_sel) <= $" & to_hstring(fastio_rdata_ram) & " (from BRAM)";
        fastio_rdata_sel <= fastio_rdata_ram;
      else
--        report "tri-stating fastio_read(_sel)";
        fastio_rdata_sel <= (others => 'Z');
      end if;
    else
--        report "tri-stating fastio_read(_sel)";
      fastio_rdata_sel <= (others => 'Z');
    end if;

    -- ==================================================================
    -- ==================================================================


    case sd_state is
      when WriteSector|WritingSector|WritingSectorAckByte|QSPI_write_phase1|QSPI_qwrite_16|QSPI_qwrite_512|qspi_qwrite_256|QSPI_qwrite_phase4|QSPI_read_phase3 =>
        report "QSPI: Possible f011 buffer fetch";
        if f011_sector_fetch='1' then
          f011_buffer_read_address <= "110"&f011_buffer_disk_address;
        else
          f011_buffer_read_address <= "111"&sd_buffer_offset;
          report "QSPI: reading from 111&sd_buffer_offset = $" & to_hstring("111"&sd_buffer_offset);
        end if;
      when F011WriteSectorRealDriveWait|F011WriteSectorRealDrive =>
        f011_buffer_read_address <= "110"&f011_buffer_disk_address;
      when others =>
        f011_buffer_read_address <= "110"&f011_buffer_cpu_address;
    end case;

    if rising_edge(clock) then

      if hw_errata_enable_toggle /= hw_errata_enable_toggle_last then
        hw_errata_enable_toggle_last <= hw_errata_enable_toggle;
        hw_errata_level_int <= x"ff";
        hw_errata_level <= x"ff";
      end if;

      if hw_errata_disable_toggle /= hw_errata_disable_toggle_last then
        hw_errata_disable_toggle_last <= hw_errata_disable_toggle;
        hw_errata_level_int <= x"00";
        hw_errata_level <= x"00";
      end if;

      if hw_errata_enable_toggle /= hw_errata_enable_toggle_last then
        hw_errata_enable_toggle_last <= hw_errata_enable_toggle;
        hw_errata_level_int <= x"ff";
        hw_errata_level <= x"ff";
      end if;
      
      if hw_errata_disable_toggle /= hw_errata_disable_toggle_last then
        hw_errata_disable_toggle_last <= hw_errata_disable_toggle;
        hw_errata_level_int <= x"00";
        hw_errata_level <= x"00";
      end if;

      -- Buffer RDATA line
      f_rdata_drive <= f_rdata;

      -- Select RLL or MFM writer for floppy drive
      -- (do this under a clock to avoid glitching on WDATA and WGATE)
      f_wdata_last <= f_wdata_int;
      if f_wdata_int = '0' and f_wdata_last='1' then
        -- Negative edge on F_WDATA.
        -- Count how many cycles since the last one,
        -- and if less than the minimum seen so far, update
        -- the minimum. This is to help track down a bug with apparently
        -- glitched F_WDATA output where we seem to be inserting one (or
        -- it seems more typically two) magnetic inversions in a gap
        -- from time to time.
        if f_wdata_interval < f_wdata_minimum then
          f_wdata_minimum <= f_wdata_interval;
        end if;
        f_wdata_interval <= 0;
      else
        -- Count cycles between F_WDATA negative edges.
        if f_wdata_interval < 255 then
          f_wdata_interval <= f_wdata_interval + 1;
        end if;
      end if;

      if fdc_encoding_mode= x"1" then
        -- RLL27
        f_wdata <= f_wdata_rll;
        f_wdata_int <= f_wdata_rll;
        fw_no_data <= fw_no_data_rll;
        fw_ready_for_next <= fw_ready_for_next_rll;
        rll27_encoding <= '1';
        mfm_encoding <= '0';
        raw_encoding <= '0';
      elsif fdc_encoding_mode=x"0" then
        f_wdata <= f_wdata_mfm;
        f_wdata_int <= f_wdata_mfm;
        fw_no_data <= fw_no_data_mfm;
        fw_ready_for_next <= fw_ready_for_next_mfm;
        mfm_encoding <= '1';
        rll27_encoding <= '0';
        raw_encoding <= '0';
      elsif fdc_encoding_mode=x"F" then
        f_wdata <= f_wdata_raw;
        f_wdata_int <= f_wdata_raw;
        fw_no_data <= fw_no_data_raw;
        fw_ready_for_next <= fw_ready_for_next_raw;
        mfm_encoding <= '0';
        rll27_encoding <= '0';
        raw_encoding <= '1';
      else
        mfm_encoding <= '0';
        rll27_encoding <= '0';
        raw_encoding <= '0';
        f_wdata <= '1';
        f_wdata_int <= '1';
      end if;

      -- Export last floppy gap info so that we can have a magic DMA mode to
      -- read raw flux from the floppy at 25ns resolution
      if fdc_last_gap(15 downto 8) /= x"00" then
        floppy_last_gap <= x"ff";
      else
        floppy_last_gap <= fdc_last_gap(7 downto 0);
      end if;
      floppy_gap_strobe <= fdc_last_gap_strobe;

      -- Allow blocking readiness of CRC result to allow CRC internal
      -- pipeline to take effect (because crc_ready flag doesn't clear
      -- until a couple of cycles after a new byte has been fed into it).
      if crc_force_delay_counter /= 0 then
        crc_force_delay_counter <= 0;
      end if;
      if crc_force_delay_counter < 2 then
        crc_force_delay <= '0';
      end if;

      -- Automatically select whether to show last DD or HD sector
      if auto_fdc_2x_select='1' then
        if found_track /= last_found_track or found_sector /= last_found_sector or found_side /= last_found_side then
          fdc_2x_select <= '0';
          last_found_track <= found_track;
          last_found_sector <= found_sector;
          last_found_side <= found_side;
        end if;
        if found_track_2x /= last_found_track_2x or found_sector_2x /= last_found_sector_2x or found_side_2x /= last_found_side_2x then
          fdc_2x_select <= '1';
          last_found_track_2x <= found_track_2x;
          last_found_sector_2x <= found_sector_2x;
          last_found_side_2x <= found_side_2x;
        end if;
      end if;

      if dd_track_info_valid='1' then
        report "TRACKINFO: Saw track_info_valid";
        track_info_track <= dd_track_info_track;
        track_info_rate <= dd_track_info_rate;
        track_info_encoding <= dd_track_info_encoding;
        track_info_sectors <= dd_track_info_sectors;
        if use_tib_info='1' then
          cycles_per_interval_from_track_info <= dd_track_info_rate;
          fdc_encoding_mode <= dd_track_info_encoding(3 downto 0);
          report "TRACKINFO: Setting encoding to $" & to_hstring(dd_track_info_encoding(3 downto 0)) & " from track info block.";
        end if;
      end if;

      if hd_track_info_valid='1' then
        report "TRACKINFO: Saw track_info_valid";
        track_info_track <= hd_track_info_track;
        track_info_rate <= hd_track_info_rate;
        track_info_encoding <= hd_track_info_encoding;
        track_info_sectors <= hd_track_info_sectors;
        if use_tib_info='1' then
          cycles_per_interval_from_track_info <= hd_track_info_rate;
          fdc_encoding_mode <= hd_track_info_encoding(3 downto 0);
          report "TRACKINFO: Setting encoding to $" & to_hstring(hd_track_info_encoding(3 downto 0)) & " from track info block.";
        end if;
      end if;

      -- If using variable data rate, then set rate based on
      -- current selected rate, modified for track number
      if fdc_variable_data_rate='0' then
        cycles_per_interval_actual <= cycles_per_interval;
      else
        cycles_per_interval_actual <= cycles_per_interval_from_track_info;
      end if;


      if reset='0' then
        -- Return to DD data rate on reset
        cycles_per_interval <= x"51";
        -- Also re-enable C65 bug compatibility
        hw_errata_level_int <= x"00";
        hw_errata_level <= x"00";
      end if;

      last_fw_ready_for_next <= fw_ready_for_next;
      last_fdc_sector_found <= fdc_sector_found;
      last_fdc_sector_found_2x <= fdc_sector_found_2x;

      if fdc_writing_cooldown /= 0 then
        fdc_writing <= '1';
        fdc_writing_cooldown <= fdc_writing_cooldown - 1;
      else
        fdc_writing <= '0';
      end if;

      -- Maintain de-bounced index hole sensor reading
      f_index_history(6 downto 0) <= f_index_history(7 downto 1);
      f_index_history(7) <= f_index;
      f_index_rising_edge <= '0';
      if f_index_history = x"00" then
        last_f_index <= '0';
      else
        last_f_index <= '1';
        if last_f_index='0' then
          f_index_rising_edge <= '1';
        end if;
      end if;

      fw_byte_valid <= '0';

      if write_sector_gate_timeout /= 0 then
        write_sector_gate_timeout <= write_sector_gate_timeout - 1;
      else
        write_sector0_gate_open <= '0';
        write_sector_gate_open <= '0';
      end if;

      -- Enable QSPI clock if in hypervisor mode, or 3rd dipswitch is enabled
      if qspi_clock_run = '1' and (hypervisor_mode='1' or dipsw(2)='1') then
        qspi_clock_int <= not qspi_clock_int;
      end if;

--      report "sectorbuffercs = " & std_logic'image(sectorbuffercs) & ", sectorbuffercs_fast=" & std_logic'image(sectorbuffercs_fast)
--        & ", fastio_rdata_ram=$" & to_hstring(fastio_rdata_ram) & ", sector buffer raddr=$" & to_hstring(to_unsigned(sector_buffer_fastio_address,12));

      audio_mix_write <= '0';

      -- Drive LCD panel PWM brightness control
      -- Pulse train should be ~1KHz
      -- But that makes acoustic noise from some component, which sounds nasty
      -- due to the square wave. So we will instead try ~250KHz
      -- Nope, high speed doesn't work. So we have to find some way to fix the
      -- 1KHz squarewave audio squeal

      -- Allow volume knob 3 to control LCD panel brightness
      if pwm_knob_en='1' then
        lcdpwm_value <= pwm_knob(14 downto 7);
      end if;

      if lcd_pwm_divider /= 127 then
        lcd_pwm_divider <= lcd_pwm_divider + 1;
      else
        lcd_pwm_divider <= 0;
        -- PWM line is always high if maximum value selected
        if lcd_pwm_counter >= to_integer(lcdpwm_value) and lcdpwm_value /= x"FF" then
          lcdpwm <= '0';
        else
          lcdpwm <= '1';
        end if;
        -- Allow tri-stating of LCD PWM brightness
        if lcdpwm_value = x"00" then
          lcdpwm <= 'Z';
        end if;
        if lcd_pwm_counter = 255 then
          lcd_pwm_counter <= 0;
        else
          lcd_pwm_counter <= lcd_pwm_counter + 1;
        end if;
      end if;

      -- Pass current touch events to the on-screen keyboard
      touch1_valid <= touch1_active;
      touch1_x(13 downto 10) <= (others => '0');
      touch1_y(11 downto 10) <= (others => '0');
      touch1_x(9 downto 0) <= touch_x1(9 downto 0);
      touch1_y(9 downto 0) <= touch_y1(9 downto 0);
      touch2_valid <= touch2_active;
      touch2_x(13 downto 10) <= (others => '0');
      touch2_y(11 downto 10) <= (others => '0');
      touch2_x(9 downto 0) <= touch_x2(9 downto 0);
      touch2_y(9 downto 0) <= touch_y2(9 downto 0);

      -- Reset I2C command enable as soon as busy flag asserts
      i2c0_busy_last <= i2c0_busy;
      i2c1_busy_last <= i2c1_busy;
      if (i2c0_busy = '1' and i2c0_busy_last='0')
        or (i2c0_busy = '1' and i2c0_busy_last='0' and i2c0_stacked_command ='1' ) then
        i2c0_command_en <= '0';
        i2c0_command_en_internal <= '0';
        i2c0_stacked_command <= '0';
      end if;
      if (i2c1_busy = '1' and i2c1_busy_last='0')
        or (i2c1_busy = '1' and i2c1_busy_last='0' and i2c1_stacked_command ='1' ) then
        i2c1_command_en <= '0';
        i2c1_command_en_internal <= '0';
        i2c1_stacked_command <= '0';
      end if;

      target_track <= f011_track;
      target_sector <= f011_sector;
      target_side <= f011_side;

      -- Advance sector buffer pointers
      f011_buffer_disk_pointer_advance <= '0';
      if f011_buffer_disk_pointer_advance = '1' then
        if f011_buffer_disk_address /= "111111111" then
          f011_buffer_disk_address <= f011_buffer_disk_address + 1;
        else
          f011_buffer_disk_address <= (others => '0');
        end if;
      end if;
      f011_buffer_cpu_pointer_advance <= '0';
      if f011_buffer_cpu_pointer_advance = '1' then
        sb_cpu_read_request <= '1';
        if f011_buffer_cpu_address /= "111111111" then
          f011_buffer_cpu_address <= f011_buffer_cpu_address + 1;
        else
          f011_buffer_cpu_address <= (others => '0');
        end if;
      end if;

      -- Make CPU write request if required
      if sb_cpu_write_request='1' then
        report "CPU writing $" & to_hstring(sb_cpu_wdata) & " to sector buffer @ $" & to_hstring(f011_buffer_cpu_address);
        f011_buffer_write_address <= "110"&f011_buffer_cpu_address;
        f011_buffer_wdata <= sb_cpu_wdata;
        f011_buffer_write <= '1';
        f011_buffer_cpu_pointer_advance <= '1';
        sb_cpu_write_request <= '0';
      else
        f011_buffer_write <= '0';
      end if;
      -- Prepare for CPU read request via $D087 if required
      if sb_cpu_read_request='1' and sb_cpu_reading='0' then
        report "CPU read pre-fetch from sector buffer @ $" & to_hstring(f011_buffer_cpu_address);
        sb_cpu_reading <= '1';
      else
        sb_cpu_reading <= '0';
      end if;
      if sb_cpu_reading = '1' then
        sb_cpu_rdata <= f011_buffer_rdata;
        report "CPU sector buffer data pre-fetch = $" & to_hstring(f011_buffer_rdata);
        sb_cpu_reading <= '0';
      end if;

      -- Advance f011 buffer position when reading from data register
      last_was_d087 <= '0';
      if fastio_read='1' then
        if (fastio_addr(19 downto 0) = x"D1087"
            or fastio_addr(19 downto 0) = x"D3087") then
          if last_was_d087='0' then
            report "$D087 access : advancing CPU sector buffer pointer";
            f011_buffer_cpu_pointer_advance <= '1';
            sb_cpu_read_request <= '1';
            f011_drq <= '0';
          end if;
          last_was_d087 <= '1';
          f011_eq_inhibit <= '0';
        end if;
      end if;
      -- EQ flag is asserted when buffer address matches where we are upto
      -- reading or writing.  On complete reads this should correspond to the
      -- start of the buffer.
      last_f011_buffer_disk_address <= f011_buffer_disk_address;
      last_f011_buffer_cpu_address <= f011_buffer_cpu_address;
      if (f011_buffer_disk_address /= last_f011_buffer_disk_address) or
        (f011_buffer_cpu_address /= last_f011_buffer_cpu_address) then
        report "f011_buffer_disk_address = $" & to_hstring(f011_buffer_disk_address)
          & ", f011_buffer_cpu_address = $" & to_hstring(f011_buffer_cpu_address);
      end if;
      if f011_buffer_disk_address = f011_buffer_cpu_address then
        if f011_flag_eq='0' then
          report "Asserting f011_flag_eq";
        end if;
        f011_flag_eq <= not f011_eq_inhibit;
      else
        if f011_flag_eq='1' then
          report "Clearing f011_flag_eq";
        end if;
        f011_flag_eq <= '0';
      end if;


      -- Check 16KHz timer to see if we need to do anything
      if counter_16khz /= cycles_per_16khz then
        counter_16khz <= counter_16khz + 1;
      else
        counter_16khz <= 0;

        if busy_countdown = x"0000" then
          null;
        elsif busy_countdown = x"0001" then
          busy_countdown <= x"0000";
          f011_busy <= '0';
        else
          busy_countdown <= busy_countdown - 1;
        end if;
      end if;

      if step_countdown /= 0 then
        step_countdown <= step_countdown - 1;
      end if;
      if step_countdown = 1 then
        -- Stepping pulses should be short, so we clear it here
        f_step <= '1';
      end if;

      -- If MFM decoder thinks we are on the wrong track, and the
      -- auto-tuner is enabled, then step in the right direction.
      -- The timing of the steps is based on how often a sector goes past the head.
      -- 10 sectors per track x 300 rpm = 60 sectors per second = ~18msec per
      -- sector. This is more than slow enough for safe stepping, we don't need
      -- to do any other timing interlock
      if autotune_enable = '1' and fdc_sector_operation='1' then
        if autotune_step='1' and last_autotune_step='0' then
          f_step <= '0';
          step_countdown <= 500;
          -- reset track info when stepping
          track_info_track <= x"FF";
          track_info_rate <= x"51";
          track_info_encoding <= x"00";
          track_info_sectors <= x"00";
          f_stepdir <= autotune_stepdir;
        elsif autotune_step='0' and last_autotune_step='1' then
          f_step <= '1';
        end if;
        if autotune2x_step='1' and last_autotune2x_step='0' then
          f_step <= '0';
          -- reset track info when stepping
          track_info_track <= x"FF";
          track_info_rate <= x"51";
          track_info_encoding <= x"00";
          track_info_sectors <= x"00";
          step_countdown <= 500;
          f_stepdir <= autotune2x_stepdir;
        elsif autotune2x_step='0' and last_autotune2x_step='1' then
          f_step <= '1';
        end if;
      end if;
      last_autotune_step <= autotune_step;
      last_autotune2x_step <= autotune2x_step;


      if use_real_floppy0='1' and virtualise_f011_drive0='0' and f011_ds = "000" then
        -- PC drives use a combined RDY and DISKCHANGE signal.
        -- You can only clear the DISKCHANGE and re-assert RDY
        -- by stepping the disk (thus the ticking of
        f011_disk_present <= '1';
        f011_write_protected <= not f_writeprotect;
      elsif use_real_floppy2='1' and virtualise_f011_drive1='0' and f011_ds = "001" then
        -- PC drives use a combined RDY and DISKCHANGE signal.
        -- You can only clear the DISKCHANGE and re-assert RDY
        -- by stepping the disk (thus the ticking of
        f011_disk_present <= '1';
        f011_write_protected <= not f_writeprotect;
      elsif f011_ds="000" then
        f011_write_protected <= f011_disk1_write_protected;
        f011_disk_present <= f011_disk1_present;
      elsif f011_ds="001" then
        f011_write_protected <= f011_disk2_write_protected;
        f011_disk_present <= f011_disk2_present;
      end if;

      if use_real_floppy0='1' and f011_ds="000" then
        -- When using the real drive, use correct index and track 0 sensors
        f011_track0 <= not f_track0;
        f011_over_index <= not f_index;
        f011_disk_changed <= (not f_diskchanged) or latched_disk_change_event;
      elsif use_real_floppy2='1' and f011_ds="001" then
        -- When using the real drive, use correct index and track 0 sensors
        f011_track0 <= not f_track0;
        f011_over_index <= not f_index;
        f011_disk_changed <= (not f_diskchanged) or latched_disk_change_event;
      else
        f011_disk_changed <= latched_disk_change_event;
        if f011_head_track="0000000" then
          f011_track0 <= '1';
        else
          f011_track0 <= '0';
        end if;
      end if;

      -- the read invalidate line is a strobe set by seeking the
      -- heads.
      -- XXX It should remain invalidated until seek completes
      -- however.
      fdc_read_invalidate <= '0';

      -- update diskimage offset
      -- add 1/2 track amount for sectors on the rear
      -- and subtract one since sectors are relative to 1, not 0
      if f011_side=x"00" then
        physical_sector <= f011_sector - 1;  -- 0 minus 1
      else
        physical_sector <= f011_sector + 9;  -- +10 minus 1
      end if;
      if f011_mega_disk='0' and f011_d64_disk='0' then
        diskimage1_offset <=
          to_unsigned(
            to_integer(f011_track(6 downto 0) & "0000")        -- track x 16
            +to_integer("00" & f011_track(6 downto 0) & "00")  -- track x 4  =
                                                               -- track x 20
            +to_integer("000" & physical_sector),17);
        -- and don't let it point beyond the end of the disk
        if (f011_track >= 80) or (physical_sector > 20) then
          -- point to first sector if disk instead
          diskimage1_offset <= to_unsigned(0,17);
        end if;
      elsif f011_mega_disk='0' and f011_d64_disk='1' then
        -- 1541 disk image
        -- CBDOS ROM is responsible for implementing the 1541 geometry.
        -- We just present 1581-like geometry, but truncated to 683 x 256
        -- byte sectors = 342 (rounded up to the whole sector, which must
        -- be present due to the use of 4KB clusters).
        diskimage1_offset <=
          to_unsigned(
            to_integer(f011_track(6 downto 0) & "0000")        -- track x 16
            +to_integer("00" & f011_track(6 downto 0) & "00")  -- track x 4  =
                                                               -- track x 20
            +to_integer("000" & physical_sector),17);
        -- and don't let it point beyond the end of the disk
        if ((f011_track >= 18) or (physical_sector > 20))
          or (f011_track = 17 and physical_sector > 1) then
          -- point to first sector if disk instead
           diskimage1_offset <= to_unsigned(0,17);
         end if;
      elsif f011_mega_disk='1' and f011_d64_disk='1' then
        -- XXX 1571 disk image
        -- 1541 disk image
        -- CBDOS ROM is responsible for implementing the 1541 geometry.
        -- We just present 1581-like geometry, but truncated to 683 x 2 x 256
        -- byte sectors = 683
        diskimage1_offset <=
          to_unsigned(
            to_integer(f011_track(6 downto 0) & "0000")        -- track x 16
            +to_integer("00" & f011_track(6 downto 0) & "00")  -- track x 4  =
                                                               -- track x 20
            +to_integer("000" & physical_sector),17);
        -- and don't let it point beyond the end of the disk
        if ((f011_track >= 18) or (physical_sector > 20))
          or (f011_track = 34 and physical_sector > 2) then
          -- point to last sector if disk instead
          diskimage1_offset <= to_unsigned(0,17);
        end if;
      else
        -- MEGA65 HD disks support 85 tracks and 64 sectors per track
        diskimage1_offset <=
          to_unsigned(
            to_integer(f011_track(6 downto 0) & "0000000")        -- track x (64x2)
            +to_integer("000" & physical_sector),17);
        -- and don't let it point beyond the end of the disk
        if (f011_track >= 84) or (physical_sector > 63) then
          -- point to last sector if disk instead
          diskimage1_offset <= to_unsigned(0,17);
        end if;
      end if;

      if f011_mega_disk2='0' and f011_d64_disk2='0' then
        diskimage2_offset <=
          to_unsigned(
            to_integer(f011_track(6 downto 0) & "0000")
            +to_integer("00" & f011_track(6 downto 0) & "00")
            +to_integer("000" & physical_sector),17);
        -- and don't let it point beyond the end of the disk
        if (f011_track >= 80) or (physical_sector > 20) then
          -- point to last sector if disk instead
          diskimage2_offset <= to_unsigned(0,17);
        end if;
      elsif f011_mega_disk2='0' and f011_d64_disk2='1' then
        -- 1541 disk image
        -- CBDOS ROM is responsible for implementing the 1541 geometry.
        -- We just present 1581-like geometry, but truncated to 683 x 256
        -- byte sectors = 342 (rounded up to the whole sector, which must
        -- be present due to the use of 4KB clusters).
        diskimage2_offset <=
          to_unsigned(
            to_integer(f011_track(6 downto 0) & "0000")        -- track x 16
            +to_integer("00" & f011_track(6 downto 0) & "00")  -- track x 4  =
                                                               -- track x 20
            +to_integer("000" & physical_sector),17);
        -- and don't let it point beyond the end of the disk
        if ((f011_track >= 18) or (physical_sector > 20))
          or (f011_track = 17 and physical_sector > 1) then
          -- point to last sector if disk instead
          diskimage2_offset <= to_unsigned(0,17);
        end if;
      elsif f011_mega_disk2='1' and f011_d64_disk2='1' then
        -- 1571 disk image
        -- CBDOS ROM is responsible for implementing the 1571 geometry.
        -- We just present 1581-like geometry, but truncated to 683 x 2 x 256
        -- byte sectors = 683 x 512 byte sectors (exactly)
        diskimage2_offset <=
          to_unsigned(
            to_integer(f011_track(6 downto 0) & "0000")        -- track x 16
            +to_integer("00" & f011_track(6 downto 0) & "00")  -- track x 4  =
                                                               -- track x 20
            +to_integer("000" & physical_sector),17);
        -- and don't let it point beyond the end of the disk
        if ((f011_track >= 35) or (physical_sector > 20))
          or (f011_track = 34 and physical_sector > 2) then
          -- point to last sector if disk instead
          diskimage2_offset <= to_unsigned(0,17);
        end if;
      else
        -- MEGA65 HD disks support 85 tracks and 64 sectors per track
        diskimage2_offset <=
          to_unsigned(
            to_integer(f011_track(6 downto 0) & "0000000")        -- track x (64x2)
            +to_integer("000" & physical_sector),17);
        -- and don't let it point beyond the end of the disk
        if (f011_track >= 84) or (physical_sector > 63) then
          -- point to last sector if disk instead
          diskimage2_offset <= to_unsigned(0,17);
        end if;
      end if;

      -- De-map sector buffer if VIC-IV maps colour RAM at $DC00
--      report "colourram_at_dc00 = " &
-- std_logic'image(colourram_at_dc00) & ", sector_buffer_mapped = " & std_logic'image(sector_buffer_mapped) severity note;
      if colourram_at_dc00='1' or viciii_iomode(1)='0' then
--        report "unmapping sector buffer due to mapping of colour ram/D02F mode select" severity note;
        sector_buffer_mapped <= '0';
        sectorbuffermapped <= '0';
        sectorbuffermapped2 <= '0';
      else
        sectorbuffermapped <= sector_buffer_mapped;
        sectorbuffermapped2 <= sector_buffer_mapped;
      end if;

      if fastio_write='1' then
        if f011_cs='1' then
          -- ================================================================== START
          -- the section below is for the F011
          -- ==================================================================

          -- F011 FDC emulation registers
          report "SDCARDIO: Writing to F011 regs";
          case fastio_addr(4 downto 0) is

            when "00000" =>
              -- @IO:C65 $D080 - F011 FDC control
              -- @IO:C65 $D080.7 FDC:IRQ When set, enables interrupts to occur. Clearing clears any pending interrupt and disables interrupts until set again.
              -- @IO:C65 $D080.6 FDC:LED Drive LED blinks when set
              -- @IO:C65 $D080.5 FDC:MOTOR Activates drive motor and LED (unless LED signal is also set, causing the drive LED to blink)
              -- @IO:C65 $D080.4 FDC:SWAP Swap upper and lower halves of data buffer (i.e. invert bit 8 of the sector buffer)
              -- @IO:C65 $D080.3 FDC:SIDE Directly controls the SIDE signal to the floppy drive, i.e., selecting which side of the media is active.
              -- @IO:C65 $D080.0-2 FDC:DS Drive select (0 to 7). Internal drive is 0. Second floppy drive on internal cable is 1. Other values reserved for C1565 external drive interface.

              -- CONTROL |  IRQ  |  LED  | MOTOR | SWAP  | SIDE  |  DS2  |  DS1  |  DS0  | 0 RW
              --IRQ     When set, enables interrupts to occur,  when reset clears and
              --        disables interrupts.
              --LED     These  two  bits  control  the  state  of  the  MOTOR and LED
              --MOTOR   outputs. When both are clear, both MOTOR and LED outputs will
              --        be off. When MOTOR is set, both MOTOR and LED Outputs will be
              --        on. When LED is set, the LED will "blink".
              --SWAP    swaps upper and lower halves of the data buffer
              --        as seen by the CPU.
              --SIDE    when set, sets the SIDE output to 0, otherwise 1.
              --DS2-DS0 these three bits select a drive (drive 0 thru drive 7).  When
              --        DS0-DS2  are  low  and  the LOCAL input is true (low) the DR0
              --        output will go true (low).
              f011_irqenable <= fastio_wdata(7);
              f011_led <= fastio_wdata(6);
              if fastio_wdata(2 downto 1) = "00" then
                if (fastio_wdata(0) xor f011_swap_drives) = '0' then
                  if use_real_floppy0='1' then
                    drive_led0 <= fastio_wdata(6);
                    drive_ledsd <= '0';
                  else
                    drive_led0 <= '0';
                    drive_ledsd <= fastio_wdata(6);
                  end if;
                  drive_led2 <= '0';
                else
                  drive_led0 <= '0';
                  if use_real_floppy2='1' then
                    drive_ledsd <= '0';
                    drive_led2 <= fastio_wdata(6);
                  else
                    drive_ledsd <= fastio_wdata(6);
                    drive_led2 <= '0';
                  end if;
                end if;
              end if;
              f011_motor <= fastio_wdata(5);
              motor <= fastio_wdata(5);

              if f011_ds /= fastio_wdata(2 downto 0) then
                -- When switching drive, clear write gate
                f_wgate <= '1';
              end if;

              f_motora <= '1'; f_selecta <= '1'; f_motorb <= '1'; f_selectb <= '1';
              if fastio_wdata(2 downto 1) = "00" then
                if (fastio_wdata(0) xor f011_swap_drives) = '0' then
                  if use_real_floppy0='1' or silent_sdcard='0' then
                    f_motora <= not fastio_wdata(5); -- start motor on real drive
                    f_selecta <= not fastio_wdata(5);
                  else
                    f_motora <= '1';
                    f_selecta <= '1';
                  end if;
                else
                  if use_real_floppy2='1' or silent_sdcard='0' then
                    f_motorb <= not fastio_wdata(5); -- start motor on real drive
                    f_selectb <= not fastio_wdata(5);
                  else
                    f_motorb <= '1';
                    f_selectb <= '1';
                  end if;
                end if;
              end if;

              -- De-selecting drive cancelled disk change event
              if fastio_wdata(5)='0' then
                latched_disk_change_event <= '0';
              end if;
              f_side1 <= not fastio_wdata(3);

              f011_swap <= fastio_wdata(4);
              if fastio_wdata(4) /= f011_swap then
                -- switch halves of buffer if swap bit changes
                f011_buffer_cpu_address(8) <= not f011_buffer_cpu_address(8);
                sb_cpu_read_request <= '1';
              end if;
              f011_head_side(0) <= fastio_wdata(3);
              f011_ds <= fastio_wdata(2 downto 0);
              if not ((use_real_floppy0='1' and fastio_wdata(2 downto 0)="000")
                      or (use_real_floppy2='1' and fastio_wdata(2 downto 0)="001"))  then
                if (fastio_wdata(2 downto 0) /= f011_ds) then
                  f011_disk_changed <= '0';
                end if;
              end if;

            when "00001" =>           -- $D081
              -- @IO:C65 $D081 FDC:COMMAND F011 FDC command register
              -- COMMAND | WRITE | READ  | FREE  | STEP  |  DIR  | ALGO  |  ALT  | NOBUF | 1 RW
              -- @IO:C65 $D081.7 FDC:WRCMD Command is a write operation if set
              -- @IO:C65 $D081.6 FDC:RDCMD Command is a read operation if set
              -- @IO:C65 $D081.5 FDC:FREE Command is a free-format (low level) operation
              -- @IO:C65 $D081.4 FDC:STEP Writing 1 causes the head to step in the indicated direction
              -- @IO:C65 $D081.3 FDC:DIR Sets the stepping direction (inward vs
              -- outward)
              -- @IO:C65 $D081.2 FDC:ALGO Selects reading and writing algorithm (currently ignored).
              -- @IO:C65 $D081.1 FDC:ALT Selects alternate DPLL read recovery method (not implemented)
              -- @IO:C65 $D081.0 FDC:NOBUF Reset the sector buffer read/write pointers

              --WRITE   must be set to perform write operations.
              --READ    must be set for all read operations.
              --FREE    allows free-format read or write vs formatted
              --STEP    write to 1 to cause a head stepping pulse.
              --DIR     sets head stepping direction
              --ALGO    selects read and write algorithm. 0=FC read, 1=DPLL read,
              --        0=normal write, 1=precompensated write.

              --ALT     selects alternate DPLL read recovery method. The ALG0 bit
              --        must be set for ALT to work.
              --NOBUF   clears the buffer read/write pointers

              --  Legal commands are...
              --
              -- hexcode notes   macro   function
              -- ------- -----   -----   --------
              -- 40    1,4,5   RDS     Read Sector
              -- 80    1,2     WTS     Write Sector
              -- 60    1,4,5   RDT     Read Track
              -- A0    1,2     WTT     Write Track (format)
              -- 10    3       STOUT   Head Step Out
              -- 14    3       TIME    Time 1 head step interval (no pulse)
              -- 18    3       STIN    Head Step In
              -- 20    3       SPIN    Wait for motor spin-up
              -- 00    3       CAN     Cancel any command in progress
              -- 01            CLB     Clear the buffer pointers
              --
              -- Notes:    1. Add 1 for nonbuffered operation
              --           2. Add 4 for write precompensation
              --           3. Add 1 to clear buffer pointers
              --           4. Add 4 for DPLL recovery instead of FC recovery
              --           5. Add 6 for Alternate DPLL recovery
              f011_cmd <= fastio_wdata;
              f011_write_precomp <= fastio_wdata(2);
              f011_busy <= '0';
              f011_lost <= '0';
              f011_irq  <= '0';
              f011_rnf  <= '0';
              f011_crc  <= '0';
              f011_rsector_found <= '0';
              f011_wsector_found <= '0';
              if fastio_wdata(0) = '1' then
                -- reset buffer (but take SWAP into account)
                f011_buffer_cpu_address(7 downto 0) <= (others => '0');
                f011_buffer_cpu_address(8) <= f011_swap;
                sb_cpu_read_request <= '1';
              end if;

              temp_cmd := fastio_wdata(7 downto 2) & "00";
              report "F011 command $" & to_hstring(temp_cmd) & " issued.";
              case temp_cmd is

                when x"A0" | x"A4" | x"A8" | x"AC" =>
                  -- Format a track.
                  -- This can either be buffered, i.e., completely automatically,
                  -- or unbuffered, the way the old C65 ROMs expect.
                  --
                  -- Buffered formatting is more or less essential at the
                  -- higher data-rates, unless you want to write fairly optimised
                  -- assembly code to do unbuffered formatting, e.g., if you want
                  -- to master tracks with specific content, rather than have empty
                  -- sectors written for you.

                  f_wgate <= '1';
                  f011_busy <= '1';

                  -- $A4 = enable write precomp
                  -- $A8 = no gaps, i.e., Amiga-style track-at-once
                  -- $A0 = with inter-sector gaps, i.e., 1581 / PC 1.44MB style
                  -- that can be written to using DOS
                  format_no_gaps <= temp_cmd(3);

                  -- Only allow formatting when real drive is used
                  if (use_real_floppy0='1' and virtualise_f011_drive0='0' and f011_ds="000") or
                    (use_real_floppy2='1' and virtualise_f011_drive1='0' and f011_ds="001") then
                    report "FLOPPY: Real drive selected, so starting track format";
                    if fastio_wdata(0)='0' then
                      sd_state <= FDCAutoFormatTrackSyncWait;
                    else
                      -- Clear the LOST and DRQ flags at the beginning.
                      f011_lost <= '0';
                      f011_drq <= '0';

                      sd_state <= FDCFormatTrackSyncWait;
                    end if;
                  else
                    report "FLOPPY: Ignoring track format, due to using D81 image";
                  end if;

                when x"40" | x"44" =>         -- read sector
                  -- calculate sector number.
                  -- physical sector on disk = track * $14 + sector on track
                  -- then add to disk image start sector for the selected
                  -- drive.
                  -- put sector number into sd_sector, and then trigger read.
                  -- If no disk image is enabled, then report an error.

                  -- Start reading into start of pointer
                  f011_buffer_disk_address <= (others => '0');

                  if (use_real_floppy0='1' and virtualise_f011_drive0='0' and f011_ds="000") or
                     (use_real_floppy2='1' and virtualise_f011_drive1='0' and f011_ds="001") then
                    report "Using real floppy drive, asserting fdc_read_request";
                    -- Real floppy drive request
                    fdc_read_request <= '1';
                    -- Allow use of auto-stepping to correct track
                    fdc_sector_operation <= '1';
                    -- Read must complete within 10 rotations
                    -- (Was 6, but if we need to auto-seek from one end of the
                    -- disk to the other, it can take a little longer than 1.2
                    -- sec)
                    fdc_rotation_timeout <= 10;
                    -- If no physical drive, we won't get SYNC pulses, so
                    -- should have an absolute timeout of 2 seconds
                    fdc_rotation_timeout_reserve_counter <= 100000000;

                    -- Mark F011 as busy with FDC job
                    f011_busy <= '1';
                    -- Clear request not found flag (gets set by timeout if required)
                    f011_rnf <= '0';

                    -- Allow 250ms per rotation (they should be ~200ms)
                    index_wait_timeout <= cpu_frequency / 4;

                    sd_state <= FDCReadingSectorWait;
                  else
                    if f011_ds="000" and (f011_disk1_present='0' or diskimage1_enable='0') then
                      f011_rnf <= '1';
                      report "Drive 0 selected, but not mounted.";
                    elsif f011_ds="001" and (f011_disk2_present='0' or diskimage2_enable='0') then
                      f011_rnf <= '1';
                      report "Drive 1 selected, but not mounted.";
                    elsif f011_ds(2 downto 1) /= x"00" then
                      -- only 2 drives supported for now
                      f011_rnf <= '1';
                      report "Drive 2-7 selected, but not supported.";
                    else
                      report "Drive 0 or 1 selected and active.";
                      f011_sector_fetch <= '1';
                      f011_busy <= '1';
                      -- We use the SD-card buffer offset to count the bytes read
                      sd_buffer_offset <= (others => '0');
                      if f011_ds="000" then
                        sd_sector <= diskimage_sector + diskimage1_offset;
                      else
                        sd_sector <= diskimage2_sector + diskimage2_offset;
                      end if;
                    end if;
                    if (virtualise_f011_drive0='1' and f011_ds="000")
                      or (virtualise_f011_drive1='1' and f011_ds="001")
                    then
                      -- Hypervisor virtualised
                      sd_state <= HyperTrapRead;
                      if f011_ds="000" then
                        sd_sector(16 downto 0) <= diskimage1_offset;
                      elsif f011_ds="001" then
                        sd_sector(16 downto 0) <= diskimage2_offset;
                      else
                        sd_sector(16 downto 0) <= (others => '0');
                      end if;
                      sd_sector(31 downto 17) <= (others => '0');
                    else
                      -- SD card
                      sd_state <= ReadSector;
                    end if;
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                  end if;

                when x"80" | x"84" =>         -- write sector
                  -- Copy sector from F011 buffer to SD buffer, and then
                  -- pretend the SD card registers were used to trigger a write.
                  -- The F011 can in theory do unbuffered sector writes, but
                  -- we don't support them.  The C65 ROM does buffered
                  -- writes, anyway, so it isn't a problem.
                  -- The only place where unbuffered writes is required, is for
                  -- formatting disks. We will support unbuffered writes for
                  -- the real floppy drive only, i.e., not for SD card, where
                  -- it is meaningless.

                  f011_buffer_cpu_address(7 downto 0) <= (others => '0');
                  f011_buffer_cpu_address(8) <= f011_swap;
                  sb_cpu_read_request <= '1';
                  f011_buffer_disk_address <= (others => '0');

                  if f011_ds="000" and ((diskimage1_enable or use_real_floppy0)='0'
                                        or (f011_disk1_present or use_real_floppy0) ='0'
                                        or (f011_disk1_present ='1' and use_real_floppy0 = '0' and f011_disk1_write_protected='1'))
                                        then
                    f011_rnf <= '1';
                    report "Drive 0 selected, but not mounted.";
                  elsif f011_ds="001" and ((diskimage2_enable or use_real_floppy2)='0'
                                        or (f011_disk2_present or use_real_floppy2) ='0'
                                        or (f011_disk2_present ='1' and use_real_floppy2 = '0' and f011_disk2_write_protected='1'))
                                        then
                    f011_rnf <= '1';
                    report "Drive 1 selected, but not mounted.";
                  elsif virtualise_f011_drive0='0' and f011_ds="000" and use_real_floppy0='1' then
                    -- Access to real first floppy drive
                    sd_state <= F011WriteSectorRealDriveWait;
                    -- Allow use of auto-stepping to correct track
                    fdc_sector_operation <= '1';
                    -- Setup timeouts etc
                    fdc_rotation_timeout <= 10;
                    fdc_rotation_timeout_reserve_counter <= 100000000;
                    f011_busy <= '1';
                    f011_rnf <= '0';
                    f011_crc <= '0';
                    index_wait_timeout <= cpu_frequency / 4;
                  elsif virtualise_f011_drive1='0' and f011_ds="001" and use_real_floppy2='1' then
                    -- Access to real second floppy drive
                    sd_state <= F011WriteSectorRealDriveWait;
                    -- Allow use of auto-stepping to correct track
                    fdc_sector_operation <= '1';
                    -- Setup timeouts etc
                    fdc_rotation_timeout <= 10;
                    fdc_rotation_timeout_reserve_counter <= 100000000;
                    f011_busy <= '1';
                    f011_rnf <= '0';
                    f011_crc <= '0';
                    index_wait_timeout <= cpu_frequency / 4;
                  elsif f011_ds(2 downto 1) /= x"00" then
                    -- only 2 drives supported for now
                    f011_rnf <= '1';
                    report "Drive 2-7 selected, but not mounted.";
                  else
                    report "Drive 0 or 1 selected, and image present.";
                    f011_sector_fetch <= '1';
                    f011_busy <= '1';
                    -- We use the SD-card buffer offset to count the bytes written
                    sd_buffer_offset <= (others => '0');
                    -- XXX Doesn't trigger an error for bad track/sector:
                    -- just writes to sector 1599 of the disk image!
                    if f011_ds="000" then
                      sd_sector <= diskimage_sector + diskimage1_offset;
                    elsif f011_ds="001" then
                      sd_sector <= diskimage2_sector + diskimage2_offset;
                    else
                      sd_sector <= (others => '1');
                    end if;

                    -- Check for writing to disk image vs virtualisation
                    if ((virtualise_f011_drive0='0' and f011_ds="000") or (virtualise_f011_drive1='0' and f011_ds="001"))
                        and
                      ((use_real_floppy0='0' and f011_ds="000") or (use_real_floppy2='0' and f011_ds="001")) then
                      f011_busy <= '1';
                      f011_crc <= '0';
                      f011_rnf <= '0';
                      sd_state <= F011WriteSector;
                    elsif (use_real_floppy0='0' or f011_ds/="000") and (use_real_floppy2='0' or f011_ds/="001") then
                      sd_state <= HyperTrapWrite;
                      if f011_ds="000" then
                        sd_sector(16 downto 0) <= diskimage1_offset;
                      elsif f011_ds="001" then
                        sd_sector(16 downto 0) <= diskimage2_offset;
                      else
                        sd_sector(16 downto 0) <= (others => '0');
                      end if;
                      sd_sector(31 downto 17) <= (others => '0');
                    end if;
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                    report "Commencing FDC buffered write.";
                  end if;
                when x"10" =>         -- head step out, or no step
                  f011_head_track <= f011_head_track - 1;
                  f_step <= '0';
                  f_stepdir <= '1';
                  step_countdown <= 500;

                  -- reset track info when stepping
                  track_info_track <= x"FF";
                  track_info_rate <= x"51";
                  track_info_encoding <= x"00";
                  track_info_sectors <= x"00";

                  f_selecta <= '1'; f_selectb <= '1';
                  if f011_ds(2 downto 1) = "00" then
                    if (f011_ds(0) xor f011_swap_drives) = '0' and 
                       (use_real_floppy0='1' or silent_sdcard='0') then
                      f_selecta <= '0';
                    elsif (f011_ds(0) xor f011_swap_drives) = '1' and 
                          (use_real_floppy2='1' or silent_sdcard='0') then
                      f_selectb <= '0';
                    end if;
                  end if;

                  f_wgate <= '1';
                  f011_busy <= '1';
                  busy_countdown(15 downto 8) <= (others => '0');
                  busy_countdown(7 downto 0) <= f011_reg_step;
                when x"14" =>
                  -- be busy for one step interval, without
                  -- actually stepping
                  f011_busy <= '1';

                  f_selecta <= '1'; f_selectb <= '1';
                  if f011_ds(2 downto 1) = "00" then
                    if (f011_ds(0) xor f011_swap_drives) = '0' and
                       (use_real_floppy0='1' or silent_sdcard='0') then
                      f_selecta <= '0';
                    elsif (f011_ds(0) xor f011_swap_drives) = '1' and 
                          (use_real_floppy2='1' or silent_sdcard='0') then
                      f_selectb <= '0';
                    end if;
                  end if;


                  busy_countdown(15 downto 8) <= (others => '0');
                  busy_countdown(7 downto 0) <= f011_reg_step;
                when x"18" =>         -- head step in
                  f_step <= '0';
                  f_stepdir <= '0';
                  step_countdown <= 500;

                  -- reset track info when stepping
                  track_info_track <= x"FF";
                  track_info_rate <= x"51";
                  track_info_encoding <= x"00";
                  track_info_sectors <= x"00";

                  f_selecta <= '1'; f_selectb <= '1';
                  if f011_ds(2 downto 1) = "00" then
                    if (f011_ds(0) xor f011_swap_drives) = '0' and
                       (use_real_floppy0='1' or silent_sdcard='0') then
                      f_selecta <= '0';
                    elsif (f011_ds(0) xor f011_swap_drives) = '1' and 
                          (use_real_floppy2='1' or silent_sdcard='0') then
                      f_selectb <= '0';
                    end if;
                  end if;


                  f_wgate <= '1';
                  f011_head_track <= f011_head_track + 1;
                  f011_busy <= '1';
                  busy_countdown(15 downto 8) <= (others => '0');
                  busy_countdown(7 downto 0) <= f011_reg_step;
                when x"20" =>         -- wait for motor spin up time (1sec)
                  f011_busy <= '1';
                  f011_rnf <= '1';    -- Set according to the specifications
                  busy_countdown <= to_unsigned(16000,16); -- 1 sec spin up time
                when x"D0" =>
                  f_rdata_loopback <= '0';
                  f_rdata_loopback_int <= '0';
                when x"D1" =>
                  f_rdata_loopback <= '1';
                  f_rdata_loopback_int <= '1';
                when x"00" =>         -- cancel running command (not implemented)
                  f_wgate <= '1';
                  report "Clearing fdc_read_request due to $00 command";
                  fdc_read_request <= '0';
                  fdc_bytes_read <= (others => '0');
                  f011_busy <= '0';
                  sd_state <= Idle;
                when others =>        -- illegal command
                  null;
              end case;

            when "00100" =>
              -- @IO:C65 $D084 FDC:TRACK F011 FDC track selection register
              f011_track <= fastio_wdata;
              report "D084: Setting f011_track to $" & to_hstring(f011_track);
            when "00101" =>
              -- @IO:C65 $D085 FDC:SECTOR F011 FDC sector selection register
              f011_sector <= fastio_wdata;

            when "00110" =>
              -- @IO:C65 $D086 FDC:SIDE F011 FDC side selection register
              f011_side <= fastio_wdata;

            when "00111" =>
              -- @IO:C65 $D087 FDC:DATA F011 FDC data register (read/write) for accessing the floppy controller's 512 byte sector buffer
              if last_was_d087='0' then
                report "FLOP: $D087 write : trigger sector buffer write of $" & to_hstring(fastio_wdata);
                sb_cpu_write_request <= '1';
                sb_cpu_wdata <= fastio_wdata;
                f011_drq <= '0';
              end if;
              last_was_d087<='1';
              f011_eq_inhibit <= '0';

              report "FLOP: (format track) Writing byte $" & to_hstring(sb_cpu_wdata) & " to MFM write engine.";
              fw_byte_in <= fastio_wdata;
              fw_byte_valid <= '1';

            when "01000" =>
              -- @IO:C65 $D088 FDC:CLOCK Set or read the clock pattern to be used when writing address and data marks. Should normally be left $FF
              f011_reg_clock <= fastio_wdata;
            when "01001" =>
              -- @IO:C65 $D089 FDC:STEP Set or read the track stepping rate in 62.5 microsecond steps (normally 128, i.e., 8 milliseconds).
              f011_reg_step <= fastio_wdata;
            when "01010" =>
              -- @IO:C65 $D08A FDC:PCODE (Read only) returns the protection code of the most recently read sector. Was intended for rudimentary copy protection. Not implemented.
              null;
            when "01111" =>
              hw_errata_level <= fastio_wdata;
              hw_errata_level_int <= fastio_wdata;
            when others => null;

          end case;
          -- ================================================================== END
          -- the section above was for the F011
          -- ==================================================================


        elsif sdcardio_cs='1'
          and (secure_mode='0' or fastio_addr(7 downto 4) = x"B" or fastio_addr(7 downto 4) = x"F") then

          -- ================================================================== START
          -- the section below is for the SDcard
          -- ==================================================================

          report "SDCARDIO: Writing to SDCARDIO regs";

          -- microSD controller registers
          case fastio_addr(7 downto 0) is
            -- @IO:GS $D680 SD:CMDANDSTAT SD controller status/command
            when x"80" =>
              -- status / command register
              case fastio_wdata is
                when x"00" =>
                  -- Reset SD card
                  sd_reset <= '1';
                  sd_state <= Idle;
                  sd_handshake <= '1';
                  sd_handshake_internal <= '1';
                  sd_doread <= '0';
                  sd_dowrite <= '0';
                  sd_write_multi <= '0';
                  sd_write_multi_first <= '0';
                  sd_write_multi_last <= '0';
                  sdio_error <= '0';
                  sdio_fsm_error <= '0';
                  -- Don't reset sector number on reset
--                  sd_sector <= (others => '0');
                  sdio_busy <= '0';

                when x"10" =>
                  -- Reset SD card with flags specified
                  sd_reset <= '1';
                  sd_state <= Idle;
                  sdio_error <= '0';
                  sdio_fsm_error <= '0';
                  sd_doread <= '0';
                  sd_dowrite <= '0';
                  sd_write_multi <= '0';
                  sd_write_multi_first <= '0';
                  sd_write_multi_last <= '0';
                  sdio_busy <= '0';

                  read_on_idle <= '0';

                when x"01" =>
                  -- End reset
                  sd_reset <= '0';
                  sd_state <= Idle;
                  sd_handshake <= '0';
                  sd_handshake_internal <= '0';
                  sdio_error <= '0';
                  sdio_fsm_error <= '0';

                  -- Queue an automatic read for as soon as the SD card
                  -- goes idle. This is to work around a bug we have seen where
                  -- if you don't request a read from the SD card soon enough after
                  -- reset, then no read will ever succeed.
                  read_on_idle <= '0';

                when x"0c" =>
                  -- Request flush of write cache on SD card
                  if sdio_busy='0' then
                    sd_doread <= '1';
                    sd_dowrite <= '1';
                    sd_handshake <= '0';
                    sd_handshake_internal <= '0';
                  else
                    sd_doread <= '0';
                    sd_dowrite <= '0';
                  end if;

                  -- XXX DEBUG provision for finding out why SD card
                  -- gets jammed.
                when x"0e" =>
                  sd_handshake <= '0';
                  sd_handshake_internal <= '0';
                when x"0f" =>
                  sd_handshake <= '1';
                  sd_handshake_internal <= '1';

                when x"11" =>
                  -- End reset
                  sd_reset <= '0';
                  sd_state <= Idle;
                  sdio_error <= '0';
                  sdio_fsm_error <= '0';

                when x"02" =>
                  -- Read sector
                  sd_write_multi <= '0';
                  sd_write_multi_first <= '0';
                  sd_write_multi_last <= '0';
                  if sdio_busy='1' then
                    sdio_error <= '1';
                    sdio_fsm_error <= '1';
                  else
                    sd_state <= ReadSector;
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                    -- Put into SD card buffer, not F011 buffer
                    f011_sector_fetch <= '0';
                    sd_buffer_offset <= (others => '0');
                  end if;

                when x"03" =>
                  -- Write sector
                  if (write_sector_gate_open='1' and sd_sector /= to_unsigned(0,32))
                    or (write_sector0_gate_open='1' and sd_sector = to_unsigned(0,32))
                  then
                    write_sector0_gate_open <= '0';
                    write_sector_gate_open <= '0';
                    sd_write_multi <= '0';
                    sd_write_multi_first <= '0';
                    sd_write_multi_last <= '0';
                    if sdio_busy='1' then
                      report "SDWRITE: sdio_busy is set, not writing";
                      sdio_error <= '1';
                      sdio_fsm_error <= '1';
                    else
                      report "SDWRITE: Commencing write";
                      sd_state <= WriteSector;
                      sdio_error <= '0';
                      sdio_fsm_error <= '0';
                      f011_sector_fetch <= '0';

                      sd_wrote_byte <= '0';
                      sd_buffer_offset <= (others => '0');
                    end if;
                  else
                    report "SDWRITE: Attempt to write a sector without opening the gate";
                    sdio_error <= '1';
                    sdio_fsm_error <= '1';
                  end if;
                when x"04" =>
                  -- Multi-sector write: first sector
                  if (write_sector_gate_open='1' and sd_sector /= to_unsigned(0,32))
                    or (write_sector0_gate_open='1' and sd_sector = to_unsigned(0,32))
                  then
                    sd_write_multi <= '1';
                    sd_write_multi_first <= '1';
                    sd_write_multi_last <= '0';
                    if sdio_busy='1' then
                      report "SDWRITE: sdio_busy is set, not writing";
                      sdio_error <= '1';
                      sdio_fsm_error <= '1';
                    else
                      report "SDWRITE: Commencing write";
                      sd_state <= WriteSector;
                      sdio_error <= '0';
                      sdio_fsm_error <= '0';
                      f011_sector_fetch <= '0';

                      sd_wrote_byte <= '0';
                      sd_buffer_offset <= (others => '0');
                    end if;
                  end if;
                when x"05" =>
                  if (write_sector_gate_open='1' and sd_sector /= to_unsigned(0,32))
                    or (write_sector0_gate_open='1' and sd_sector = to_unsigned(0,32))
                  then
                    -- Multi-sector write: neither first nor last sector
                    sd_write_multi <= '1';
                    sd_write_multi_first <= '0';
                    sd_write_multi_last <= '0';
                    if sdio_busy='1' then
                      report "SDWRITE: sdio_busy is set, not writing";
                      sdio_error <= '1';
                      sdio_fsm_error <= '1';
                    else
                      report "SDWRITE: Commencing write";
                      sd_state <= WriteSector;
                      sdio_error <= '0';
                      sdio_fsm_error <= '0';
                      f011_sector_fetch <= '0';

                      sd_wrote_byte <= '0';
                      sd_buffer_offset <= (others => '0');
                    end if;
                  end if;
                when x"06" =>
                  if (write_sector_gate_open='1' and sd_sector /= to_unsigned(0,32))
                    or (write_sector0_gate_open='1' and sd_sector = to_unsigned(0,32))
                  then
                    -- Multi-sector write: final sector
                    sd_write_multi <= '1';
                    sd_write_multi_first <= '0';
                    sd_write_multi_last <= '1';
                    if sdio_busy='1' then
                      report "SDWRITE: sdio_busy is set, not writing";
                      sdio_error <= '1';
                      sdio_fsm_error <= '1';
                    else
                      report "SDWRITE: Commencing write";
                      sd_state <= WriteSector;
                      sdio_error <= '0';
                      sdio_fsm_error <= '0';
                      f011_sector_fetch <= '0';

                      sd_wrote_byte <= '0';
                      sd_buffer_offset <= (others => '0');
                    end if;
                  end if;
                when x"40" => sdhc_mode <= '0';
                when x"41" => sdhc_mode <= '1';

                when x"45" => sd_clear_error <= '1';
                when x"44" => sd_clear_error <= '0';
                when x"4D" =>
                  write_sector0_gate_open <= '1';
                  write_sector_gate_timeout <= 40000; -- about 1ms
                when x"57" =>
                  write_sector_gate_open <= '1';
                  write_sector_gate_timeout <= 40000; -- about 1ms
                when x"50" => -- P - Write 256 bytes to QSPI flash in 1-bit mode
                  if hypervisor_mode='1' or dipsw(2)='1' then
                    sd_state <= qspi_write_256;
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                    sdio_busy <= '1';
                  else
                    -- Permission denied
                    sdio_error <= '1';
                  end if;
                when x"51" => -- Q - Write 512 bytes to QSPI flash in 1-bit mode
                  if hypervisor_mode='1' or dipsw(2)='1' then
                    sd_state <= qspi_write_512;
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                    sdio_busy <= '1';
                  else
                    -- Permission denied
                    sdio_error <= '1';
                  end if;
                when x"52" => -- R - Read 512 bytes from QSPI flash in 4-bit mode
                  report "QSPI: Read request";
                  if hypervisor_mode='1' or dipsw(2)='1' then
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                    sdio_busy <= '1';
                    sd_state <= qspi_read_512;
                  else
                    -- Permission denied
                    sdio_error <= '1';
                  end if;
                when x"53" =>
                  -- S - Read a 512 byte region from QSPI flash, handling
                  -- all aspects of the transaction.  Sector address is taken
                  -- from $D681-$D684 address.
                  -- This command is non-dangerous, so allow it even from userland
                  report "QSPI: Dispatching command";
                  sdio_error <= '0';
                  sdio_fsm_error <= '0';
                  sdio_busy <= '1';
                  sd_state <= qspi_send_command;
                  spi_address <= sd_sector;
                  qspi_read_sector_phase <= 0;
                  qspi_action_state <= qspi_read_512;
                  qspi_verify_mode <= '0';
                  spi_flash_cmd_byte <= x"6c";
                when x"54" =>
                  -- T - Write a 512 byte region to QSPI flash, handling
                  -- all aspects of the transaction.  Sector address is taken
                  -- from $D681-$D684 address.
                  if hypervisor_mode='1' or dipsw(2)='1' then
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                    sdio_busy <= '1';
                    sd_state <= qspi_send_command;
                    spi_address <= sd_sector;
                    qspi_read_sector_phase <= 0;
                    spi_no_dummy_cycles <= '1';
                    qspi_action_state <= qspi_qwrite_512;
                    spi_flash_cmd_byte <= x"34";
                    qspi_release_cs_on_completion <= qspi_release_cs_on_completion_enable;
                    f011_sector_fetch <= '0';
                    -- Write whole SD card buffer to QSPI
                    sd_buffer_offset <= to_unsigned(0,9);
                  else
                    -- Permission denied
                    sdio_error <= '1';
                  end if;
                when x"55" =>
                  -- U - Write a 256 byte region to QSPI flash, handling
                  -- all aspects of the transaction.  Sector address is taken
                  -- from $D681-$D684 address.
                  if hypervisor_mode='1' or dipsw(2)='1' then
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                    sdio_busy <= '1';
                    sd_state <= qspi_send_command;
                    spi_address <= sd_sector;
                    qspi_read_sector_phase <= 0;
                    qspi_action_state <= qspi_qwrite_256;
                    spi_flash_cmd_byte <= x"34";
                    spi_no_dummy_cycles <= '1';
                    qspi_release_cs_on_completion <= qspi_release_cs_on_completion_enable;
                    f011_sector_fetch <= '0';
                    -- Write last 256 bytes of SD card buffer to QSPI
                    sd_buffer_offset <= to_unsigned(256,9);
                  else
                    -- Permission denied
                    sdio_error <= '1';
                  end if;
                when x"56" =>
                  -- V - Verify a 512 byte region from QSPI flash, handling
                  -- all aspects of the transaction.  Sector address is taken
                  -- from $D681-$D684 address.
                  -- This command is non-dangerous, so allow it even from userland
                  report "QSPI: Dispatching verify command";
                  sdio_error <= '0';
                  sdio_fsm_error <= '0';
                  sdio_busy <= '1';
                  sd_state <= qspi_send_command;
                  spi_address <= sd_sector;
                  qspi_read_sector_phase <= 0;
                  qspi_action_state <= qspi_read_512;
                  qspi_verify_mode <= '1';
                  spi_flash_cmd_byte <= x"6c";
                  spi_no_dummy_cycles <= '0';
                when x"58" =>
                  -- X - Erase page: Send command and address, then return
                  -- to idle immediately.
                  if hypervisor_mode='1' or dipsw(2)='1' then
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                    sdio_busy <= '1';
                    sd_state <= qspi_send_command;
                    spi_address <= sd_sector;
                    qspi_read_sector_phase <= 0;
                    qspi_action_state <= QSPI_Release_CS;
                    spi_flash_cmd_byte <= x"dc";
                    f011_sector_fetch <= '0';
                  else
                    -- Permission denied
                    sdio_error <= '1';
                  end if;
                when x"59" =>
                  -- Y - Erase small page: Send command and address, then return
                  -- to idle immediately.
                  if hypervisor_mode='1' or dipsw(2)='1' then
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                    sdio_busy <= '1';
                    sd_state <= qspi_send_command;
                    spi_address <= sd_sector;
                    qspi_read_sector_phase <= 0;
                    qspi_action_state <= QSPI_Release_CS;
                    spi_flash_cmd_byte <= x"21";
                    f011_sector_fetch <= '0';
                  else
                    -- Permission denied
                    sdio_error <= '1';
                  end if;
                when x"5a" => qspi_command_len <= 90;
                when x"5b" => qspi_command_len <= 92;
                when x"5c" => qspi_command_len <= 94;
                when x"5d" => qspi_command_len <= 96;
                when x"5e" => qspi_command_len <= 98;
                when x"5f" => qspi_command_len <= 100;
                when x"66" =>
                  -- SPI Flash write enable
                  -- to idle immediately.
                  if hypervisor_mode='1' or dipsw(2)='1' then
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                    sdio_busy <= '1';
                    sd_state <= qspi_send_command;
                    qspi_read_sector_phase <= 0;
                    qspi_action_state <= QSPI_Release_CS;
                    spi_flash_cmd_byte <= x"06";
                    spi_flash_cmd_only <= '1';
                    f011_sector_fetch <= '0';
                    report "QSPI: Starting bare command";
                  else
                    -- Permission denied
                    sdio_error <= '1';
                  end if;
                when x"67" =>
                  qspi_release_cs_on_completion_enable <= '0';
                when x"68" =>
                  qspi_release_cs_on_completion_enable <= '1';
                when x"69" =>
                  -- Set CR1
                  -- to idle immediately.
                  if hypervisor_mode='1' or dipsw(2)='1' then
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                    sdio_busy <= '1';
                    sd_state <= qspi_send_command;
                    spi_address <= sd_sector;
                    qspi_read_sector_phase <= 0;
                    qspi_action_state <= QSPI_Release_CS;
                    spi_flash_cmd_byte <= x"01";
                    spi_flash_16bits <= '1';
                    f011_sector_fetch <= '0';
                    report "QSPI: Starting bare command";
                  else
                    -- Permission denied
                    sdio_error <= '1';
                  end if;
                when x"6a" =>
                  -- SPI Clear status register. Allowed from user land
                  sdio_error <= '0';
                  sdio_fsm_error <= '0';
                  sdio_busy <= '1';
                  sd_state <= qspi_send_command;
                  qspi_read_sector_phase <= 0;
                  qspi_action_state <= QSPI_Release_CS;
                  spi_flash_cmd_byte <= x"30";
                  spi_flash_cmd_only <= '1';
                  f011_sector_fetch <= '0';
                  report "QSPI: Starting bare command";
                when x"6b" =>
                  -- Read CFI data block
                  -- This command is non-dangerous, so allow it even from userland
                  report "QSPI: Dispatching command";
                  sdio_error <= '0';
                  sdio_fsm_error <= '0';
                  sdio_busy <= '1';
                  sd_state <= qspi_send_command;
                  spi_address <= x"00000000";
                  qspi_read_sector_phase <= 0;
                  qspi_action_state <= spi_read_512;
                  spi_flash_cmd_byte <= x"9f";
                  spi_flash_cmd_only <= '1';
                  spi_no_dummy_cycles <= '1';
                when x"6c" =>
                  -- Write a 16 byte region to QSPI flash, handling
                  -- all aspects of the transaction.  Sector address is taken
                  -- from $D681-$D684 address. This is meant for debugging.
                  if hypervisor_mode='1' or dipsw(2)='1' then
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                    sdio_busy <= '1';
                    sd_state <= qspi_send_command;
                    spi_address <= sd_sector;
                    qspi_read_sector_phase <= 0;
                    qspi_action_state <= qspi_qwrite_16;
                    spi_flash_cmd_byte <= x"34";
                    spi_no_dummy_cycles <= '1';
                    qspi_release_cs_on_completion <= qspi_release_cs_on_completion_enable;
                    f011_sector_fetch <= '0';
                    -- Write last 16 bytes of SD card buffer to QSPI
                    sd_buffer_offset <= to_unsigned(256+240,9);
                  else
                    -- Permission denied
                    sdio_error <= '1';
                  end if;
                  -- Allow setting the number of dummy cycles

                when x"81" => sector_buffer_mapped<='1';
                              sdio_error <= '0';
                              sdio_fsm_error <= '0';

                when x"82" => sector_buffer_mapped<='0';
                              sdio_error <= '0';
                              sdio_fsm_error <= '0';
                -- sd_fill_mode allows us to fill sector writes
                -- with a common value instead of using data from
                -- the sector buffer.
                when x"83" => sd_fill_mode <= '1';
                when x"84" => sd_fill_mode <= '0';

                -- Switch between the two SD cards by writing $C0 or $C1 to $D680
                -- i.e. "[C]ard 0" or "[C]ard 1"
                when x"C0" => sd_interface_select <= '0';
                              sd_interface_select_internal <= '0';
                when x"C1" => sd_interface_select <= '1';
                              sd_interface_select_internal <= '1';

                when others =>
                  sdio_error <= '1';
              end case;

            when x"81" =>
              -- @IO:GS $D681-$D684 - SD controller SD sector address
              -- @IO:GS $D681 SD:SECTOR0 SD controller SD sector address (LSB)
              -- @IO:GS $D682 SD:SECTOR1 SD controller SD sector address (2nd byte)
              -- @IO:GS $D683 SD:SECTOR2 SD controller SD sector address (3rd byte)
              -- @IO:GS $D684 SD:SECTOR3 SD controller SD sector address (MSB)
              sd_sector(7 downto 0) <= fastio_wdata;
            when x"82" => sd_sector(15 downto 8) <= fastio_wdata;
            when x"83" => sd_sector(23 downto 16) <= fastio_wdata;
            when x"84" => sd_sector(31 downto 24) <= fastio_wdata;
            when x"86" =>
              -- @IO:GS $D686 SD:FILLVAL WRITE ONLY set fill byte for use in fill mode, instead of SD buffer data
              sd_fill_value <= fastio_wdata;
            when x"89" =>
              -- @ IO:GS $D689.0 SD:BUFBIT8 (read only) reads bit 8 of the sector buffer pointer
              -- @ IO:GS $D689.1 SD:BUFFFULL (read only) if set, indicates that the sector buffer is full and has not yet been read
              -- @ IO:GS $D689.2 SD:HNDSHK Set/read SD card sd_handshake signal
              -- @ IO:GS $D689.3 SD:DRDY SD Card Data Ready indication
              -- @ IO:GS $D689.4 SD:RESERVED Reserved
              -- @ IO:GS $D689.5 SD:FDCSWAP Set to swap floppy drive 0 (the internal drive) and drive 1 (the drive on the 2nd position on the internal floppy cable).
              -- @ IO:GS $D689.7 SD:BUFFSEL Set to switch sector buffer to view SD card direct access, clear for access to the F011 FDC sector buffer.
              sd_handshake <= fastio_wdata(2);
              sd_handshake_internal <= fastio_wdata(2);
              f011_swap_drives <= fastio_wdata(5);
              f011sd_buffer_select <= fastio_wdata(7);

              -- ================================================================== END
              -- the section above was for the SDcard
              -- ==================================================================

              -- ================================================================== START
              -- the section below is for OTHER I/O
              -- ==================================================================

            when x"8a" =>
              -- @IO:GS $D68A.7 SDFDC:D1D64 F011 drive 1 disk image is D64 image if set (otherwise 800KiB 1581 or D65 image)
              -- @IO:GS $D68A.6 SDFDC:D0D64 F011 drive 0 disk image is D64 mega image if set (otherwise 800KiB 1581 or D65 image)
              if hypervisor_mode='1' then
                f011_d64_disk <= fastio_wdata(6);
                f011_d64_disk2 <= fastio_wdata(7);
              end if;
            -- @IO:GS $D68B - F011 emulation control register
            when x"8b" =>
              if hypervisor_mode='1' then
                f011_mega_disk <= fastio_wdata(6);
                f011_mega_disk2 <= fastio_wdata(7);
                f011_disk2_write_protected <= not fastio_wdata(5);
                -- GI: I note that the vhdl refers to them as disk1 and disk2, whereas our documentation prefers to call them
                --     drive0 and drive1. So I will adjust the comments here to suit our documentation.
                -- @IO:GS $D68B.2 - F011 drive 0 write protect
                f011_disk1_write_protected <= not fastio_wdata(2);
                -- @IO:GS $D68B.1 - F011 drive 0 present
                f011_disk1_present <= fastio_wdata(1);
                f011_disk2_present <= fastio_wdata(4);
              end if;
              -- @IO:GS $D68B.7 SDFDC:D1MD F011 drive 1 disk image is D65 image if set (otherwise 800KiB 1581 image)
              -- @IO:GS $D68B.6 SDFDC:D0MD F011 drive 0 disk image is D65 image if set (otherwise 800KiB 1581 image)
              -- @IO:GS $D68B.5 SDFDC:D1WP Write enable F011 drive 1
              -- @IO:GS $D68B.4 SDFDC:D1P F011 drive 1 media present
              -- @IO:GS $D68B.3 SDFDC:D1IMG F011 drive 1 use disk image if set, otherwise use real floppy drive.
              -- @IO:GS $D68B.2 SDFDC:D0WP Write enable F011 drive 0
              -- @IO:GS $D68B.1 SDFDC:D0P F011 drive 0 media present
              -- @IO:GS $D68B.0 SDFDC:D0IMG F011 drive 0 use disk image if set, otherwise use real floppy drive.
              diskimage2_enable <= fastio_wdata(3);

              -- @IO:GS $D68B.0 - F011 drive 0 disk image enable
              diskimage1_enable <= fastio_wdata(0);
              report "writing $" & to_hstring(fastio_wdata) & " to FDC control";

            -- @IO:GS $D68C-$D68F - F011 drive 0 disk image address on SD card
            -- @IO:GS $D68C SDFDC:D0STARTSEC0 F011 drive 0 disk image address on SD card (LSB)
            -- @IO:GS $D68D SDFDC:D0STARTSEC1 F011 drive 0 disk image address on SD card (2nd byte)
            -- @IO:GS $D68E SDFDC:D0STARTSEC2 F011 drive 0 disk image address on SD card (3rd byte)
            -- @IO:GS $D68F SDFDC:D0STARTSEC3 F011 drive 0 disk image address on SD card (MSB)
            when x"8c" =>
              if hypervisor_mode='1' then
                diskimage_sector(7 downto 0) <= fastio_wdata;
              end if;
            when x"8d" =>
              if hypervisor_mode='1' then
                diskimage_sector(15 downto 8) <= fastio_wdata;
              end if;
            when x"8e" =>
              if hypervisor_mode='1' then
                diskimage_sector(23 downto 16) <= fastio_wdata;
              end if;
            when x"8f" =>
              if hypervisor_mode='1' then
                diskimage_sector(31 downto 24) <= fastio_wdata;
              end if;

            -- @IO:GS $D690-$D693 - F011 drive 1 disk image address on SD card
            -- @IO:GS $D690 SDFDC:D1STARTSEC0 F011 drive 1 disk image address on SD card (LSB)
            -- @IO:GS $D691 SDFDC:D1STARTSEC1 F011 drive 1 disk image address on SD card (2nd byte)
            -- @IO:GS $D692 SDFDC:D1STARTSEC2 F011 drive 1 disk image address on SD card (3rd byte)
            -- @IO:GS $D693 SDFDC:D1STARTSEC3 F011 drive 1 disk image address on SD card (MSB)
            when x"90" =>
              if hypervisor_mode='1' then
                diskimage2_sector(7 downto 0) <= fastio_wdata;
              end if;
            when x"91" =>
              if hypervisor_mode='1' then
                diskimage2_sector(15 downto 8) <= fastio_wdata;
              end if;
            when x"92" =>
              if hypervisor_mode='1' then
                diskimage2_sector(23 downto 16) <= fastio_wdata;
              end if;
            when x"93" =>
              if hypervisor_mode='1' then
                diskimage2_sector(31 downto 24) <= fastio_wdata;
              end if;
            when x"96" =>
              autotune_enable <= fastio_wdata(7);

            when x"a0" =>
              -- @IO:GS $D6A0 - 3.5" FDC control line debug access
              -- @IO:GS $D6A0.7 FDC:DENSITY Control floppy drive density select line
              -- @IO:GS $D6A0.6 FDC:DBGMOTORA Control floppy drive MOTOR line
              -- @IO:GS $D6A0.5 FDC:DBGMOTORA Control floppy drive SELECT line
              -- @IO:GS $D6A0.4 FDC:DBGDIR Control floppy drive STEPDIR line
              -- @IO:GS $D6A0.3 FDC:DBGDIR Control floppy drive STEP line
              -- @IO:GS $D6A0.2 FDC:DBGWDATA Control floppy drive WDATA line
              -- @IO:GS $D6A0.1 FDC:DBGWGATE Control floppy drive WGATE line
              -- @IO:GS $D6A0.0 FDC:DBGWGATE Control floppy drive SIDE1 line
              f_density <= fastio_wdata(7);

              f_motora <= '1'; f_motorb <= '1';
              f_selecta <= '1'; f_selectb <= '1';
              if f011_ds(2 downto 1) = "00" then
                if (f011_ds(0) xor f011_swap_drives) = '0' then
                  f_selecta <= fastio_wdata(5);
                  f_motora <= fastio_wdata(6);
                else
                  f_selectb <= fastio_wdata(5);
                  f_motorb <= fastio_wdata(6);
                end if;
              end if;

              f_stepdir <= fastio_wdata(4);
              f_step <= fastio_wdata(3);
              step_countdown <= 500;
--              f_wdata <= fastio_wdata(2);
              f_wgate <= fastio_wdata(1);
              f_side1 <= fastio_wdata(0);
            when x"a1" =>
              -- Setting F011 drives to use SD card is a privileged operation,
              -- so that you can't take advantage of stale contents of the
              -- sector number to get direct access to the SD card that way.
              -- @IO:GS $D6A1.0 SDFDC:USEREAL0 Use real floppy drive for drive 0 if set (read-only, except for from hypervisor)
              -- @IO:GS $D6A1.2 SDFDC:USEREAL1 Use real floppy drive for drive 1 if set (read-only, except for from hypervisor)
              -- @IO:GS $D6A1.1 SDFDC:TARGANY Read next sector under head if set, ignoring the requested side, track and sector number.
              if fastio_wdata(0)='1' or hypervisor_mode='1' or use_real_floppy0=fastio_wdata(0) then
                use_real_floppy0 <= fastio_wdata(0);
              end if;
              if fastio_wdata(2)='1' or hypervisor_mode='1' or use_real_floppy2=fastio_wdata(2) then
                use_real_floppy2 <= fastio_wdata(2);
              end if;
              target_any <= fastio_wdata(1);
              -- @IO:GS $D6A1.3 SDFDC:SILENT Disable floppy spinning and tracking for SD card operations.
              silent_sdcard <= fastio_wdata(3);
              -- Setting flag to use real floppy or not causes disk change event
              latched_disk_change_event <= '1';
            when x"a2" =>
              -- @IO:GS $D6A2 FDC:DATARATE Set number of bus cycles per floppy magnetic interval (decrease to increase data rate)
              cycles_per_interval <= fastio_wdata;
            when x"a3" =>
              if hypervisor_mode='0' then
                write_precomp_magnitude <= fastio_wdata;
              end if;
            when x"a4" =>
              if hypervisor_mode='0' then
                write_precomp_magnitude_b <= fastio_wdata;
              end if;
            when x"a5" =>
              if hypervisor_mode='0' then
                write_precomp_delay15 <= fastio_wdata;
              end if;
            when x"ac" =>
              volume_knob3_target <= unsigned(fastio_wdata(3 downto 0));
              pwm_knob_en <= fastio_wdata(7);
            when x"ad" =>
              -- @IO:GS $D6AD.0-3 MISCIO:WHEEL1TARGET Select audio channel volume to be set by thumb wheel #1
              -- @IO:GS $D6AD.4-7 MISCIO:WHEEL2TARGET Select audio channel volume to be set by thumb wheel #2
              volume_knob1_target <= unsigned(fastio_wdata(3 downto 0));
              volume_knob2_target <= unsigned(fastio_wdata(7 downto 4));
            when x"ae" =>
              -- @IO:GS $D6AE.0-3 SD:FDC!ENC Select floppy encoding (0=MFM, 1=RLL2,7, F=Raw encoding)
              -- @IO:GS $D6AE.4 SD:AUTO!2XSEL Automatically select DD or HD decoder for last sector display
              -- @IO:GS $D6AE.5 SD:FDC!VARSPD Enable automatic variable speed selection for floppy controller using Track Information Blocks on MEGA65 HD floppies
              -- @IO:GS $D6AE.6 SD:FDC!2XSEL Select HD decoder for last sector display
              -- @IO:GS $D6AE.7 SD:FDC!TIBEN Enable use of Track Info Block settings
              fdc_encoding_mode <= fastio_wdata(3 downto 0);
              auto_fdc_2x_select <= fastio_wdata(4);
              fdc_variable_data_rate <= fastio_wdata(5);
              fdc_2x_select <= fastio_wdata(6);
              use_tib_info <= fastio_wdata(7);
            when x"af" =>
              -- @IO:GS $D6AF - Directly set F011 flags (intended for virtual F011 mode) WRITE ONLY
              -- @IO:GS $D6AF.0 SD:VR!FOUND Manually set f011_rsector_found signal (indented for virtual F011 mode only)
              -- @IO:GS $D6AF.1 SD:VW!FOUND Manually set f011_wsector_found signal (indented for virtual F011 mode only)
              -- @IO:GS $D6AF.2 SD:VEQ!INH Manually set f011_eq_inhibit signal (indented for virtual F011 mode only)
              -- @IO:GS $D6AF.3 SD:VRNF Manually set f011_rnf signal (indented for virtual F011 mode only)
              -- @IO:GS $D6AF.4 SD:VDRQ Manually set f011_drq signal (indented for virtual F011 mode only)
              -- @IO:GS $D6AF.5 SD:VLOST Manually set f011_lost signal (indented for virtual F011 mode only)
              f011_rsector_found <= fastio_wdata(0);
              f011_wsector_found <= fastio_wdata(1);
              f011_eq_inhibit <= fastio_wdata(2);
              f011_rnf <= fastio_wdata(3);
              f011_drq <= fastio_wdata(4);
              f011_lost <= fastio_wdata(5);
            when x"B0" =>
              -- @IO:GS $D6B0.6 MISCIO:TCHFLX Flip X axis of touch interface if set
              -- @IO:GS $D6B0.7 MISCIO:TCHFLX Flip Y axis of touch interface if set
              touch_flip_x <= fastio_wdata(6);
              touch_flip_x_internal <= fastio_wdata(6);
              touch_flip_y <= fastio_wdata(7);
              touch_flip_y_internal <= fastio_wdata(7);
            when x"B1" =>
              -- @IO:GS $D6B1 MISCIO:TCHXSCALE Set X scale value for touch interface (LSB)
              touch_scale_x(7 downto 0) <= fastio_wdata;
              touch_scale_x_internal(7 downto 0) <= fastio_wdata;
            when x"B2" =>
              -- @IO:GS $D6B2 MISCIO:TCHXSCALE Set X scale value for touch interface (MSB)
              touch_scale_x_internal(15 downto 8) <= fastio_wdata;
              touch_scale_x(15 downto 8) <= fastio_wdata;
            when x"B3" =>
              -- @IO:GS $D6B3 MISCIO:TCHYSCALE Set Y scale value for touch interface (LSB)
              touch_scale_y(7 downto 0) <= fastio_wdata;
              touch_scale_y_internal(7 downto 0) <= fastio_wdata;
            when x"B4" =>
              -- @IO:GS $D6B4 MISCIO:TCHYSCALE Set Y scale value for touch interface (MSB)
              touch_scale_y(15 downto 8) <= fastio_wdata;
              touch_scale_y_internal(15 downto 8) <= fastio_wdata;
            when x"B5" =>
              -- @IO:GS $D6B5 MISCIO:TCHXDELTA Set X delta value for touch interface (LSB)
              touch_delta_x(7 downto 0) <= fastio_wdata;
              touch_delta_x_internal(7 downto 0) <= fastio_wdata;
            when x"B6" =>
              -- @IO:GS $D6BB MISCIO:TCHXDELTA Set X delta value for touch interface (MSB)
              touch_delta_x(15 downto 8) <= fastio_wdata;
              touch_delta_x_internal(15 downto 8) <= fastio_wdata;
            when x"B7" =>
              -- @IO:GS $D6B7 MISCIO:TCHYDELTA Set Y delta value for touch interface (LSB)
              touch_delta_y(7 downto 0) <= fastio_wdata;
              touch_delta_y_internal(7 downto 0) <= fastio_wdata;
            when x"B8" =>
              -- @IO:GS $D6B8 MISCIO:TCHYDELTA Set Y delta value for touch interface (MSB)
              touch_delta_y(15 downto 8) <= fastio_wdata;
              touch_delta_y_internal(15 downto 8) <= fastio_wdata;
            when x"BF" =>
              -- @IO:GS $D6BF.7 MISCIO:TCHI2CEN Enable/disable touch panel I2C communications
              touch_enabled <= fastio_wdata(7);
              touch_enabled_internal <= fastio_wdata(7);
              -- @IO:GS $D6BF.0-6 MISCIO:TCHBYTENUM Select byte number for touch panel communications instrumentation
              touch_byte_num(6 downto 0) <= fastio_wdata(6 downto 0);
            when x"C4" =>
              -- @IO:GS $D6C4 FPGA:REGNUM Select ICAPE2 FPGA configuration register for reading WRITE ONLY
              icape2_reg <= fastio_wdata(4 downto 0);
            when x"C8" =>
              -- @IO:GS $D6C8 FPGA:BOOTADDR0 Address of bitstream in boot flash for reconfiguration (least significant byte)
              -- @IO:GS $D6C9 FPGA:BOOTADDR1 Address of bitstream in boot flash for reconfiguration
              -- @IO:GS $D6CA FPGA:BOOTADDR2 Address of bitstream in boot flash for reconfiguration
              -- @IO:GS $D6CB FPGA:BOOTADDR3 Address of bitstream in boot flash for reconfiguration (most significant byte)
              reconfigure_address(7 downto 0) <= fastio_wdata;
              reconfigure_address_int(7 downto 0) <= fastio_wdata;
            when x"C9" =>
              reconfigure_address(15 downto 8) <= fastio_wdata;
              reconfigure_address_int(15 downto 8) <= fastio_wdata;
            when x"CA" =>
              reconfigure_address(23 downto 16) <= fastio_wdata;
              reconfigure_address_int(23 downto 16) <= fastio_wdata;
            when x"CB" =>
              reconfigure_address(31 downto 24) <= fastio_wdata;
              reconfigure_address_int(31 downto 24) <= fastio_wdata;
            when x"CC" =>
              -- @IO:GS $D6CC.7 QSPI:TRI Tristate DB0-3
              -- @IO:GS $D6CC.6 QSPI:CSN Active-low chip-select for QSPI flash
              -- @IO:GS $D6CC.5 QSPI:CLOCK Clock output line for QSPI flash
              -- @IO:GS $D6CC.4 QSPI:RESERVED (set to 0)
              -- @IO:GS $D6CC.0-3 QSPI:DB Data bits for QSPI flash interface (read/write)

              if hypervisor_mode='1' or dipsw(2)='1' then
                qspicsn <= fastio_wdata(6);
                qspi_csn_int <= fastio_wdata(6);
--                qspi_clock_int <= fastio_wdata(5);
                qspidb <= fastio_wdata(3 downto 0);
                qspidb_tristate <= fastio_wdata(7);
                qspidb_oe <= not fastio_wdata(7);
              end if;
            when x"CD" =>
              -- XXX This register was added, because without it the QSPI clock
              -- could not be controlled. No idea why, as with it here, it is
              -- possible to control it via $D6CC :/
              -- @IO:GS $D6CD.0 QSPI:CLOCKRUN Set to cause QSPI clock to free run at CPU clock frequency.
              -- @IO:GS $D6CD.1 QSPI:CLOCK Alternate address for direct manipulation of QSPI CLOCK
              if hypervisor_mode='1' or dipsw(2)='1' then
                qspi_clock_run <= fastio_wdata(0);
                qspi_clock_int <= fastio_wdata(1);
              end if;
            when x"CE" =>
              if hypervisor_mode='1' or dipsw(2)='1' then
                qspicsn <= fastio_wdata(6);
                qspi_csn_int <= fastio_wdata(6);
                qspi_clock_int <= fastio_wdata(5);
                qspidb <= fastio_wdata(3 downto 0);
                qspidb_tristate <= fastio_wdata(7);
                qspidb_oe <= not fastio_wdata(7);
              end if;
            when x"CF" =>
              -- @IO:GS $D6CF FPGA:RECONFTRIG Write $42 to Trigger FPGA reconfiguration to switch to alternate bitstream.
              if fastio_wdata = x"42" then
                trigger_reconfigure <= '1';
              end if;
              -- Or write any other value to reset floppy write gap debug value
              f_wdata_minimum <= 255;
            when x"D0" =>
              -- @IO:GS $D6D0 MISCIO:I2CBUSSEL Select I2C bus number (I2C busses vary between MEGA65 and MEGAphone variants)
              i2c_bus_id <= fastio_wdata;
            when x"D1" =>
              -- @IO:GS $D6D1 - I2C control/status
              -- @IO:GS $D6D1.0 MISCIO:I2CRST I2C reset
              -- @IO:GS $D6D1.1 MISCIO:I2CL I2C command latch write strobe (write 1 to trigger command)
              -- @IO:GS $D6D1.2 MISCIO:I2CRW I2C Select read (1) or write (0)
              -- @IO:GS $D6D1.5 MISCIO:I2CSW I2C bus 1 swap SDA/SCL pins
              -- @IO:GS $D6D1.6 MISCIO:I2CBSY I2C busy flag
              -- @IO:GS $D6D1.7 MISCIO:I2CERR I2C ack error
              if i2c_bus_id = x"00" then
                i2c0_reset <= fastio_wdata(0);
                i2c0_reset_internal <= fastio_wdata(0);
                i2c0_command_en <= fastio_wdata(1);
                if (fastio_wdata(1) and i2c0_busy) = '1' then
                  i2c0_stacked_command <= '1';
                end if;
                i2c0_command_en_internal <= fastio_wdata(1);
                i2c0_rw <= fastio_wdata(2);
                i2c0_rw_internal <= fastio_wdata(2);
              elsif i2c_bus_id = x"01" then
                i2c1_reset <= fastio_wdata(0);
                i2c1_reset_internal <= fastio_wdata(0);
                i2c1_command_en <= fastio_wdata(1);
                if (fastio_wdata(1) and i2c1_busy) = '1' then
                  i2c1_stacked_command <= '1';
                end if;
                i2c1_command_en_internal <= fastio_wdata(1);
                i2c1_rw <= fastio_wdata(2);
                i2c1_rw_internal <= fastio_wdata(2);

                i2c1_swap <= fastio_wdata(5);
                i2c1_debug_scl <= fastio_wdata(6);
                i2c1_debug_sda <= fastio_wdata(7);
              end if;
            when x"D2" =>
              -- @IO:GS $D6D2.7-1 MISCIO:I2CADDR I2C address
              if i2c_bus_id = x"00" then
                i2c0_address <= fastio_wdata(7 downto 1);
                i2c0_address_internal <= fastio_wdata(7 downto 1);
              elsif i2c_bus_id = x"01" then
                i2c1_address <= fastio_wdata(7 downto 1);
                i2c1_address_internal <= fastio_wdata(7 downto 1);
              end if;
            when x"D3" =>
              -- @IO:GS $D6D3 MISCIO:I2CWDATA I2C data write register
              if i2c_bus_id = x"00" then
                i2c0_wdata <= fastio_wdata;
                i2c0_wdata_internal <= fastio_wdata;
              elsif i2c_bus_id = x"01" then
                i2c1_wdata <= fastio_wdata;
                i2c1_wdata_internal <= fastio_wdata;
              end if;
            when x"D4" =>
              -- @IO:GS $D6D4 MISCIO:I2CRDATA I2C data read register
              null;
            when x"F0" =>
              -- @IO:GS $D6F0 MISCIO:LCDBRIGHT LCD panel brightness control
              lcdpwm_value <= fastio_wdata;
            -- @IO:GS $D6F3 MISCIO:ACCELBASH Accelerometer bit-bashing port (debug only)
            when x"F3" =>
              -- Accelerometer
              aclMOSI         <= fastio_wdata(1);
              aclMOSIinternal <= fastio_wdata(1);
              aclSS           <= fastio_wdata(2);
              aclSSinternal   <= fastio_wdata(2);
              aclSCK          <= fastio_wdata(3);
              aclSCKinternal  <= fastio_wdata(3);
            when x"F4" =>
              -- @IO:GS $D6F4 AUDIOMIX:REGSEL Audio Mixer register select
              audio_mix_reg <= fastio_wdata(7 downto 0);
              audio_mix_reg_int <= fastio_wdata(7 downto 0);
            when x"F5" =>
              -- @IO:GS $D6F5 AUDIOMIX:REGWDATA Audio Mixer register write port
              -- Write to audio mixer register.
              -- Minor complication is that the registers are 16-bits wide in
              -- the audio mixer, so we have to write to the correct half of
              -- the register, and then trigger the write.  But we should also
              -- copy the other half from the read version of the register, so
              -- that it doesn't get stomped with some old data.
              -- This does mean that after you set the selection register, you
              -- have to wait at least 17 clock cycles before trying to read or
              -- write, so that the data has time to settle.
              if audio_mix_reg_int(0)='1' then
                report "Writing upper half of audio mixer coefficient";
                audio_mix_wdata(15 downto 8) <= fastio_wdata;
                audio_mix_wdata(7 downto 0) <= audio_mix_rdata(7 downto 0);
              else
                report "Writing lower half of audio mixer coefficient";
                audio_mix_wdata(7 downto 0) <= fastio_wdata;
                audio_mix_wdata(15 downto 8) <= audio_mix_rdata(15 downto 8);
              end if;
              audio_mix_write <= '1';

            -- @IO:GS $D6F8 AUDIO:DIGILLSB 16-bit digital audio out (left LSB)
            -- @IO:GS $D6F9 AUDIO:DIGILMSB 16-bit digital audio out (left MSB)
            -- @IO:GS $D6FA AUDIO:DIGIRLSB 16-bit digital audio out (right LSB)
            -- @IO:GS $D6FB AUDIO:DIGIRMSB 16-bit digital audio out (right MSB)
            when x"F8" =>
              -- 16-bit digital audio out
              pcm_left(7 downto 0) <= signed(fastio_wdata);
            when x"F9" =>
              -- 16-bit digital audio out
              pcm_left(15 downto 8) <= signed(fastio_wdata);
            when x"FA" =>
              -- 16-bit digital audio out
              pcm_right(7 downto 0) <= signed(fastio_wdata);
            when x"FB" =>
              -- 16-bit digital audio out
              pcm_right(15 downto 8) <= signed(fastio_wdata);
            when others => null;

                           -- ================================================================== END
                           -- the section above was for OTHER I/O
                           -- ==================================================================

          end case;

        end if; --     if (fastio_addr(19 downto ...

      end if; --    if fastio_write='1' then

      if last_sd_error /= x"0000" then
        sdio_error <= '1';
        sdio_busy <= '0';
        sd_state <= Idle;
      end if;

      last_sd_state_t <= sd_state;
      last_f011_drq <= f011_drq;
      if sd_state /= last_sd_state_t or f011_drq /= last_f011_drq then
        report "FLOP: sd_state=" & sd_state_t'image(sd_state) & ", f011_drq=" & std_logic'image(f011_drq);
      end if;

      case sd_state is

        when Idle =>
          sdio_busy <= '0';
          hyper_trap_f011_read <= '0';
          hyper_trap_f011_write <= '0';
          f_wgate <= '1';
          if qspi_release_cs_on_completion='1' then
            qspi_release_cs_on_completion <= '0';
            qspicsn <= '1';
          end if;

          if sectorbuffercs='1' and fastio_write='1' then
            -- Writing via memory mapped sector buffer

            if hypervisor_mode='0' then
              f011_buffer_write_address <=
                "11"&f011sd_buffer_select&fastio_addr(8 downto 0);
            else
              f011_buffer_write_address <=
                fastio_addr(11 downto 0);
            end if;
            f011_buffer_wdata <= fastio_wdata;
            f011_buffer_write <= '1';

            report "QSPI: Writing $" & to_hstring(fastio_wdata) & " into sector buffer @ $"
              & to_hstring(fastio_addr(11 downto 0));

          end if;

          -- Automatically read a sector when reset is released and the card is
          -- ready.  This is to work around a bug we have seen where the SD card
          -- low-level controller locks up on the first read attempt, unless it
          -- happens VERY soon after reset completes.
          if read_on_idle='1' and sdio_busy='0' and sdcard_busy='0' then
            read_on_idle <= '0';

            sd_state <= ReadSector;
            sdio_error <= '0';
            sdio_fsm_error <= '0';
            -- Put into SD card buffer, not F011 buffer
            f011_sector_fetch <= '0';
            sd_buffer_offset <= (others => '0');
          end if;

        -- Trap to hypervisor when accessing SD card if virtualised.
        -- Wait until hypervisor kicks in before releasing request.
        when HyperTrapRead =>
          if hypervisor_mode='1' then
            sd_state <= HyperTrapRead2;
            hyper_trap_f011_read <= '0';
          else
            hyper_trap_f011_read <= '1';
          end if;

        when HyperTrapRead2 =>

          if hypervisor_mode='0' then
            -- Hypervisor done, init transfer of data to f011 buffer
            sd_state <= DoneReadingSector;
            read_data_byte <= '0';
          end if;

        when HyperTrapWrite =>
          hyper_trap_f011_write <= '1';
          if hypervisor_mode='1' then
            sd_state <= Idle;
          end if;

        when ReadSector =>
          -- Begin reading a sector into the buffer
          if sdio_busy='0' then
            sd_doread <= '1';
            sd_state <= ReadingSector;
            sdio_busy <= '1';
            -- skip <= 2;
            -- New sdcard.vhdl removes the tokens for us.
            skip <= 0;
            read_data_byte <= '0';
            sd_handshake <= '0';
            sd_handshake_internal <= '0';
          else
            sd_doread <= '0';
          end if;

        when ReadingSector =>
          if sd_data_ready='1' then
            sd_doread <= '0';
            -- A byte is ready to read, so store it
            sd_handshake <= '1';
            sd_handshake_internal <= '1';
            if skip=0 then
              read_data_byte <= '1';
              if f011_sector_fetch='1' then
                f011_rsector_found <= '1';
                if f011_drq='1' then f011_lost <= '1'; end if;
                f011_drq <= '1';
                -- Update F011 sector buffer
                f011_buffer_disk_pointer_advance <= '1';

                -- Write to sector buffer
                f011_buffer_write_address <= "110"&f011_buffer_disk_address;
                f011_buffer_wdata <= unsigned(sd_rdata);
                f011_buffer_write <= '1';

                -- Defer any CPU write request, since we are writing
                sb_cpu_write_request <= sb_cpu_write_request;

                -- Because the SD card interface is so fast, the entire sector
                -- can become read, before the C65 DOS tries to read the first
                -- byte. This means the EQ flag is set when DOS thinks it means
                -- buffer empty, instead of buffer full.
                f011_eq_inhibit <= '1';
              else
                -- SD-card direct access
                -- Write to SD-card half of sector buffer
                f011_buffer_write_address <= "111"&sd_buffer_offset;
                f011_buffer_wdata <= unsigned(sd_rdata);
                f011_buffer_write <= '1';
              end if;

              -- Advance pointer in SD-card buffer (this is
              -- separate from the F011 buffer pointers, but is used for SD and
              -- F011 requests, so that we know when we have read 512 bytes)
              sd_buffer_offset <= sd_buffer_offset + 1;

            else
              skip <= skip - 1;
            end if;
            sd_state <= ReadingSectorAckByte;
          else
            sd_handshake <= '0';
            sd_handshake_internal <= '0';
          end if;

        when ReadingSectorAckByte =>
          -- Wait until controller acknowledges that we have acked it
          sd_handshake <= '0';
          sd_handshake_internal <= '0';
          if sd_data_ready='0' then
            if f011_sector_fetch = '1' then
              if
                -- We have read at least one byte, and ...
                (read_data_byte='1')
                -- the buffer pointer is back to the start of the sector, and ...
                and (sd_buffer_offset="000000000")
                then
                -- sector offset has reached 512, so we must have
                -- read the whole sector.
                -- Update F011 FDC emulation status registers
                f011_sector_fetch <= '0';
                f011_busy <= '0';
                sd_state <= DoneReadingSector;
              else
                -- Still more bytes to read.
                sd_state <= ReadingSector;
              end if;
            else
              -- SD-card direct access job
              if (sd_buffer_offset = "000000000") and (read_data_byte='1') then
                -- Finished reading SD-card sectory
                sd_state <= DoneReadingSector;
              else
                -- Else keep on reading
                sd_state <= ReadingSector;
              end if;
            end if;
          end if;

        when FDCFormatTrackSyncWait =>
          -- Wait for negative edge on f_sync line

          fdc_writing_cooldown <= 20250000;

          if f_index_history(7) /= f_index_history(0) then
            report "FLOPPY: Format Track Sync wait: f_index=" & std_logic'image(f_index)
              & ", f_index_history=" & to_string(f_index_history);
          end if;

          debug_track_format_sync_wait_counter <= debug_track_format_sync_wait_counter + 1;

          if f_index_rising_edge='1' then
            sd_state <= FDCFormatTrack;
            f_wgate <= '0';

            -- Grab the first byte
            if f011_drq='1' then
              f011_lost <= '1';
            end if;
            -- Indicate we need another byte now
            f011_drq <='1';

          end if;
        when FDCFormatTrack =>
          -- Close write gate and finish formatting when we hit the next
          -- negative edge on the INDEX hole sensor of the floppy.

          fdc_writing_cooldown <= 20250000;

          if fw_ready_for_next /= last_fw_ready_for_next then
            report "FLOPPY: Format Track Active: fw_ready_for_next = " & std_logic'image(fw_ready_for_next)
              & ", last_fw_ready_for_next=" & std_logic'image(last_fw_ready_for_next);
          end if;

          debug_track_format_counter <= debug_track_format_counter + 1;

          if f_index_rising_edge='1' then
            report "FLOPPY: end of track due to index hole";
            f_wgate <= '1';
            f011_busy <= '0';
            sd_state <= Idle;
          end if;

          last_fw_no_data <= fw_no_data;
          if fw_no_data='1' and last_fw_no_data = '0' then
            report "FLOPPY: Format asserting byte lost";
            f011_lost <= '1';
          end if;

          if fw_ready_for_next = '1' and last_fw_ready_for_next='0' then
            -- Grab the next byte
            -- Indicate we need another byte now
            report "FLOPPY: Format requesting next byte";
            f011_drq <= '1';

          end if;

        when FDCAutoFormatTrackSyncWait =>
          -- Wait for negative edge on f_sync line

          fdc_writing_cooldown <= 20250000;

          if f_index_history(7) /= f_index_history(0) then
            report "FLOPPY: Format Track Sync wait: f_index=" & std_logic'image(f_index)
              & ", f_index_history=" & to_string(f_index_history);
          end if;

          debug_track_format_sync_wait_counter <= debug_track_format_sync_wait_counter + 1;

          if f_index_rising_edge='1' then
            sd_state <= FDCAutoFormatTrack;

            -- Start writing
            f_wgate <= '0';

            -- feed first gap byte
            fw_byte_in <= x"00";
            f011_reg_clock <= x"ff";
            fw_byte_valid <= '1';

            -- Set auto-format FSM state
            format_state <= 0;
            format_sector_number <= 0;

            -- Write track lead-in gaps at DD speed and using MFM to give
            -- head enough time to switch to write.
            -- We then also write the track info block at
            -- DD speed, before switching to the higher speed
            -- BUT if the speed indicates a HD disk, we write the TIB at HD
            -- rate, because DD rate is too slow for the drive electronics when
            -- in HD mode.
            saved_cycles_per_interval <= cycles_per_interval;
            saved_fdc_encoding_mode <= fdc_encoding_mode;
            fdc_encoding_mode <= x"0"; -- MFM for Track Info Blocks
            if cycles_per_interval < 60 then
              cycles_per_interval <= to_unsigned(40,8);
            else
              cycles_per_interval <= to_unsigned(81,8);
            end if;

          end if;

        when FDCAutoFormatTrack =>

          crc_feed <= '0';

          if f_index_rising_edge='1' then
            -- Abort format as soon as we reach the end of the track.
            -- i.e., write as many sectors as will fit, but no more.
            f_wgate <= '1';
            f011_busy <= '0';
            sd_state <= Idle;
            fdc_sector_operation <= '0';
          end if;

          if crc_ready='0' or crc_force_delay = '1' then
            last_fw_ready_for_next <= last_fw_ready_for_next;
            report "CRC1WAIT: crc_force_delay=" & std_logic'image(crc_force_delay)
              & ", counter=" & integer'image(crc_force_delay_counter) & ", ready=" & std_logic'image(crc_ready);
          elsif fw_ready_for_next='1' and last_fw_ready_for_next='0' then
            format_state <= format_state + 1;
            report "format_state = " & integer'image(format_state);
            case format_state is
              when 0 to 12 =>
                -- Start of track gaps
                fw_byte_in <= x"00";
                f011_reg_clock <= x"ff";
                fw_byte_valid <= '1';
                crc_reset <= '1';
                crc_feed <= '0';
                if format_state = 12 then
                  -- Jump to state for writing track info block
                  format_state <= 1000;
                end if;
              when 13 to 15 =>
                -- Write sector header sync bytes
                fw_byte_in <= x"A1";
                f011_reg_clock <= x"FB";
                fw_byte_valid <= '1';
                crc_reset <= '0';
                crc_byte <= x"a1";
                crc_feed <= '1';
                if format_state = 13 then
                  -- Advance sector number
                  format_sector_number <= format_sector_number + 1;
                end if;
              when 16 =>
                -- Sector header: Start mark
                fw_byte_in <= x"FE";
                f011_reg_clock <= x"FF";
                fw_byte_valid <= '1';
                crc_byte <= x"fe";
                crc_feed <= '1';
              when 17 =>
                -- Sector header: Track number
                fw_byte_in <= f011_track;
                fw_byte_valid <= '1';
                crc_byte <= f011_track;
                crc_feed <= '1';
              when 18 =>
                -- Sector header: Side
                fw_byte_in <= f011_side;
                fw_byte_valid <= '1';
                crc_byte <= f011_side;
                crc_feed <= '1';
              when 19 =>
                -- Sector header: Sector number
                fw_byte_in <= to_unsigned(format_sector_number,8);
                fw_byte_valid <= '1';
                crc_byte <= to_unsigned(format_sector_number,8);
                crc_feed <= '1';
              when 20 =>
                -- Sector header: Sector size (2^(7+n), so 2=512)
                fw_byte_in <= x"02";
                f011_reg_clock <= x"FF";
                fw_byte_valid <= '1';
                crc_byte <= x"02";
                crc_feed <= '1';
                -- Force wait so that CRC has time to start updating, and thus
                -- crc_ready to go low, so that we don't try to read it immediately
                -- before it has started.
                crc_force_delay_counter <= 8 + 4;
                crc_force_delay <= '1';
              when 21 =>
                -- Sector header: First CRC byte
                report "SECTORHEADER: Writing CRC byte 1 $" & to_hstring(crc_value(15 downto 8));
                fw_byte_in <= crc_value(15 downto 8);
                fw_byte_valid <= '1';
                crc_feed <= '0';
              when 22 =>
                -- Sector header: Second CRC byte
                report "SECTORHEADER: Writing CRC byte 2 $" & to_hstring(crc_value(7 downto 0));
                fw_byte_in <= crc_value(7 downto 0);
                fw_byte_valid <= '1';
                if format_no_gaps='1' then
                  format_state <= 58;
                  crc_reset <= '1';
                  crc_feed <= '0';
                end if;
              when 23 to 45 =>
                -- Write $4E gap bytes
                fw_byte_in <= x"4E";
                f011_reg_clock <= x"FF";
                fw_byte_valid <= '1';
              when 46 to 46 + 11 =>
                -- Write $00 gap bytes
                fw_byte_in <= x"00";
                f011_reg_clock <= x"ff";
                fw_byte_valid <= '1';
                crc_reset <= '1';
                crc_feed <= '0';
              when 58 to 58 + 2 =>
                -- $A1 sync bytes
                fw_byte_in <= x"A1";
                f011_reg_clock <= x"FB";
                fw_byte_valid <= '1';
                crc_reset <= '0';
                crc_byte <= x"A1";
                crc_feed <= '1';
              when 61 =>
                -- Start of data block mark
                fw_byte_in <= x"FB";
                f011_reg_clock <= x"FF";
                fw_byte_valid <= '1';
                crc_byte <= x"FB";
                crc_feed <= '1';
              when 62 to 62 + 511 =>
                -- 512 data bytes
                if f011_track /= x"27" then
                  -- sequenced data on other tracks to make more even
                  -- histograms for debugging write precomp
                  fw_byte_in <= to_unsigned(format_state,8);
                  crc_byte <= to_unsigned(format_state,8);
                else
                  -- Empty sectors on track 39 for directory
                  fw_byte_in <= to_unsigned(0,8);
                  crc_byte <= to_unsigned(0,8);
                end if;
                fw_byte_valid <= '1';
                crc_feed <= '1';
                if format_state = 62 + 511 then
                  -- Force wait so that CRC has time to start updating, and thus
                  -- crc_ready to go low, so that we don't try to read it immediately
                  -- before it has started.
                  crc_force_delay_counter <= 8 + 4;
                  crc_force_delay <= '1';
                end if;
              when 574 =>
                -- First CRC byte
                fw_byte_in <= crc_value(15 downto 8);
                fw_byte_valid <= '1';
                crc_feed <= '0';
              when 575 =>
                -- Second CRC byte
                fw_byte_in <= crc_value(7 downto 0);
                fw_byte_valid <= '1';
                if format_no_gaps='1' then
                  format_state <= 599;
                end if;
              when 576 to 576 + 22 =>
                -- $4E gap bytes following sector
                fw_byte_in <= x"4E";
                f011_reg_clock <= x"FF";
                fw_byte_valid <= '1';
              when 599 =>
                -- Final $4E gap byte, and start next sector
                fw_byte_in <= x"4E";
                f011_reg_clock <= x"FF";
                fw_byte_valid <= '1';
                -- Move to next sector
                format_state <= 13;
                crc_reset <= '1';
                crc_feed <= '0';

              when 1000 to 1002 =>
                -- Write Track Info Block sync bytes
                fw_byte_in <= x"A1";
                f011_reg_clock <= x"FB";
                fw_byte_valid <= '1';
                crc_reset <= '0';
                crc_byte <= x"a1";
                crc_feed <= '1';
              when 1003 =>
                -- Track info: Header marker
                f011_reg_clock <= x"FF";
                fw_byte_in <= x"65";
                fw_byte_valid <= '1';
                crc_byte <= x"65";
                crc_feed <= '1';
              when 1004 =>
                -- Track info: Track number
                fw_byte_in <= f011_track;
                fw_byte_valid <= '1';
                crc_byte <= f011_track;
                crc_feed <= '1';
              when 1005 =>
                -- Track Info: Data rate
                fw_byte_in <= saved_cycles_per_interval;
                fw_byte_valid <= '1';
                crc_byte <= saved_cycles_per_interval;
                crc_feed <= '1';
              when 1006 =>
                -- Track Info: Encoding: bits0-3: 0=MFM, 1=RLL2,7. Others reserved
                -- bit6 = track-at-once(1)/normal sectors with gaps that can be
                -- written to individually(0)
                -- Other bits reserved
                report "TRACKINFO: setting encoding byte to $x" & to_hstring(saved_fdc_encoding_mode);

                if format_no_gaps = '1' then
                  fw_byte_in(7 downto 4) <= x"0";
                  crc_byte(7 downto 4) <= x"0";
                else
                  fw_byte_in(7 downto 4) <= x"4";
                  crc_byte(7 downto 4) <= x"4";
                end if;
                fw_byte_in(3 downto 0) <= saved_fdc_encoding_mode;
                crc_byte(3 downto 0) <= saved_fdc_encoding_mode;
                fw_byte_valid <= '1';
                crc_feed <= '1';
              when 1007 =>
                -- Track Info: Sector count (read from $D085)
                fw_byte_in <= f011_sector;
                fw_byte_valid <= '1';
                crc_byte <= f011_sector;
                crc_feed <= '1';
              when 1008 =>
                -- Track Info: First CRC byte
                crc_feed <= '0';
                fw_byte_in <= crc_value(15 downto 8);
                fw_byte_valid <= '1';
              when 1009 =>
                -- Track Info: Second CRC byte
                fw_byte_in <= crc_value(7 downto 0);
                fw_byte_valid <= '1';
                crc_reset <= '1';
                crc_feed <= '0';
              when 1010 | 1011 | 1012 | 1013 =>
                -- Alow the CRC bytes to flush out before we change speed
                fw_byte_in <= x"00";
                fw_byte_valid <= '1';

              when 1014 =>
                -- Now switch to actual speed and lead into first sector
                format_state <= 598;
                cycles_per_interval <= saved_cycles_per_interval;
                fdc_encoding_mode <= saved_fdc_encoding_mode;

              when others =>
                null;
            end case;

          end if;

        when F011WriteSectorRealDriveWait =>
          -- Wait until the target sector header is found, or
          -- six index pulses have passed

          -- Wait until we get a fresh event of hitting the sector we
          -- are looking for.
          if fdc_sector_found='1' and last_fdc_sector_found='0' then
            -- Indicate that we still have the gap and sync mark bytes etc to write
            fdc_write_byte_number <= 0;
            -- And immediately open the write gate
            f_wgate <= '0';

            -- Ask for sector buffer to get ready to feed us bytes, beginning
            -- at the start of the sector buffer
            f011_buffer_disk_address <= (others => '0');
            f011_buffer_disk_pointer_advance <= '0';
            sb_cpu_read_request <= '0';
            sb_cpu_reading <= '0';

            -- And now start feeding bytes
            sd_state <= F011WriteSectorRealDrive;
          end if;

          if fdc_rotation_timeout_reserve_counter /= 0 then
            fdc_rotation_timeout_reserve_counter <= fdc_rotation_timeout_reserve_counter - 1;
          else
            -- Out of time: fail job
            report "Cancelling real sector write due to timeout";
            f011_rnf <= '1';
            fdc_read_request <= '0';
            fdc_bytes_read(4) <= '1';
            f011_busy <= '0';
            sd_state <= Idle;
            fdc_sector_operation <= '0';
          end if;

        when F011WriteSectorRealDrive =>

          -- Write the various bytes of the sector, including the sync marks etc

          -- Note that it is not possible to read from the sector buffer while
          -- doing a write, as the FDC requires the memory bandwidth of the
          -- sector buffer.
          -- (We could work around this by buffering the bytes from the buffer
          -- as we go, but let's keep things simple for now.)
          sb_cpu_read_request <= '0';

          crc_feed <= '0';

          -- Check for edge on fw_ready_for_next, except for first byte, which
          -- we write immediately, because fw_ready_for_next will have been stuck
          -- asserted since the last write or format command
          if crc_ready='0' or crc_force_delay='1' then
            last_fw_ready_for_next <= last_fw_ready_for_next;
            report "CRC1WAIT";
          elsif fw_ready_for_next = '1' and (last_fw_ready_for_next='0' or fdc_write_byte_number=0) then
            fdc_write_byte_number <= fdc_write_byte_number + 1;
            case fdc_write_byte_number is
              when 0 to 22 =>
                -- Write gap $4E bytes
                f011_reg_clock <= x"FF";
                fw_byte_in <= x"4E";
                fw_byte_valid <= '1';
              when 23 to 23 + 11 =>
                -- Write gap $00 bytes
                f011_reg_clock <= x"FF";
                fw_byte_in <= x"00";
                fw_byte_valid <= '1';
                crc_reset <= '1';
              when 23 + 12 to 23 + 14 =>
                -- Write $A1/$FB sync bytes
                f011_reg_clock <= x"FB";
                fw_byte_in <= x"A1";
                fw_byte_valid <= '1';
                crc_byte <= x"a1";
                crc_feed <= '1';
                crc_reset <= '0';
              when 23 + 15 =>
                -- Write $FB/$FF sector start byte
                f011_reg_clock <= x"FF";
                fw_byte_in <= x"FB";
                fw_byte_valid <= '1';
                crc_byte <= x"fb";
                crc_feed <= '1';
                crc_reset <= '0';
              when 23 + 16 to 23 + 16 + 511 =>
                -- Write data bytes
                f011_reg_clock <= x"FF";
                fw_byte_in <= f011_buffer_rdata;
                crc_byte <= f011_buffer_rdata;
                crc_feed <= '1';
                fw_byte_valid <= '1';
                f011_buffer_disk_pointer_advance <= '1';
                -- Force wait so that CRC has time to start updating, and thus
                -- crc_ready to go low, so that we don't try to read it immediately
                -- before it has started.
                crc_force_delay_counter <= 8 + 4;
                crc_force_delay <= '1';
              when 23 + 16 + 512 =>
                -- First CRC byte
                f011_reg_clock <= x"FF";
                fw_byte_in <= crc_value(15 downto 8);
                fw_byte_valid <= '1';
              when 23 + 16 + 512 + 1 =>
                -- Second CRC byte
                f011_reg_clock <= x"FF";
                fw_byte_in <= crc_value(7 downto 0);
                fw_byte_valid <= '1';
              when 23 + 16 + 512 + 2 to 23 + 16 + 512 + 2 + 5 =>
                -- Gap 3 $4E bytes
                -- (Really only to make sure MFM writer has flushed last
                -- CRC byte before we disable f_wgate, as that takes effect
                -- immediately, so we only write a few, rather than the full 24)
                f011_reg_clock <= x"FF";
                fw_byte_in <= x"4E";
                fw_byte_valid <= '1';
              when others =>
                -- Finished writing sector
                f_wgate <= '1';
                f011_busy <= '0';
                sd_state <= Idle;
                fdc_sector_operation <= '0';
            end case;
          end if;

        when FDCReadingSectorWait =>
          -- Wait until we are NOT over the requested sector,
          -- so that we don't accidentally read only the tail
          -- end of the sector.
          if fdc_sector_found = '0' and fdc_sector_found_2x='0' then
            sd_state <= FDCReadingSector;
          end if;
        when FDCReadingSector =>
          if fdc_read_request='1' then
            -- We have an FDC request in progress.

            if fdc_rotation_timeout_reserve_counter /= 0 then
              fdc_rotation_timeout_reserve_counter <= fdc_rotation_timeout_reserve_counter - 1;
            else
              -- Out of time: fail job
              report "Clearing fdc_read_request due to timeout";
              f011_rnf <= '1';
              fdc_read_request <= '0';
              fdc_bytes_read(4) <= '1';
              f011_busy <= '0';
              sd_state <= Idle;
              fdc_sector_operation <= '0';
            end if;

--        report "fdc_read_request asserted, checking for activity";
            if index_wait_timeout /= 0 then
              index_wait_timeout <= index_wait_timeout -1;
            end if;
            if (f_index_rising_edge='1') or index_wait_timeout=0 then
              rotation_count <= rotation_count + 1;
              -- Allow 250ms per rotation (they should be ~200ms)
              index_wait_timeout <= cpu_frequency / 4;
            end if;
            if ((f_index_rising_edge='1') and (fdc_sector_found='0') and (fdc_sector_found_2x='0')) or index_wait_timeout=0 then
              -- Index hole is here. Decrement rotation counter,
              -- and timeout with RNF set if we reach zero.
              if fdc_rotation_timeout /= 0 then
                fdc_rotation_timeout <= fdc_rotation_timeout - 1;
              else
                -- Out of time: fail job
                report "Clearing fdc_read_request due to timeout";
                f011_rnf <= '1';
                fdc_read_request <= '0';
                fdc_bytes_read(4) <= '1';
                f011_busy <= '0';
                sd_state <= Idle;
                fdc_sector_operation <= '0';
              end if;
            end if;
            if (fdc_sector_found='1') or (fdc_sector_end='1') then
--              report "fdc_sector_found or fdc_sector_end = 1";
              if fdc_sector_found='1' then
                if f011_rsector_found = '0' then
                  report "asserting f011_rsector_found";
                end if;
                f011_rsector_found <= '1';
              end if;
              if fdc_sector_end='1' then
                report "fdc_sector_end=1";
                if f011_rsector_found = '0' then
                  report "reseting f011_rsector_found";
                end if;
                f011_rsector_found <= '0';
              end if;
              if fdc_byte_valid = '1' and (fdc_sector_found or f011_rsector_found)='1' then
                -- DEBUG: Note how many bytes we have received from the floppy
                report "fdc_byte valid asserted, storing byte @ $" & to_hstring(f011_buffer_disk_address);
                if to_integer(fdc_bytes_read(12 downto 0)) /= 8191 then
                  fdc_bytes_read(12 downto 0) <= to_unsigned(to_integer(fdc_bytes_read(12 downto 0)) + 1,13);
                else
                  fdc_bytes_read(12 downto 0) <= (others => '0');
                end if;

                -- Record byte into sector bufferr
                if f011_drq='1' then f011_lost <= '1'; end if;
                f011_drq <= '1';
                f011_buffer_disk_pointer_advance <= '1';
                -- Write to F011 sector buffer
                f011_buffer_write_address <= "110"&f011_buffer_disk_address;
                f011_buffer_wdata <= unsigned(fdc_byte_out);
                f011_buffer_write <= '1';
                -- Defer any CPU write request, since we are writing
                sb_cpu_write_request <= sb_cpu_write_request;
              end if;
              if fdc_crc_error='1' then
                -- Failed to read sector due to CRC error
                -- So set CRC flag:
                f011_crc <= '1';

                -- But don't abort reading, just retry
                -- (The existing timeout mechanism will catch us eventually)
                sd_state <= FDCReadingSectorWait;
              elsif fdc_sector_end='1' and f011_rsector_found='1' then
                -- Clear read request only at the end of the sector we are looking for
                report "Clearing fdc_read_request due end of target sector";
                f011_crc <= '0';
                fdc_read_request <= '0';
                fdc_bytes_read(1) <= '1';
                f011_busy <= '0';
                sd_state <= Idle;
                fdc_sector_operation <= '0';
              end if;
            end if;
          end if;

          if (fdc_sector_found_2x='1') or (fdc_sector_end_2x='1') then
              report "2x fdc_sector_found or fdc_sector_end = 1";
              if fdc_sector_found_2x='1' then
                if f011_rsector_found = '0' then
                  report "asserting f011_rsector_found";
                end if;
                f011_rsector_found <= '1';
              end if;
              if fdc_sector_end_2x='1' then
                report "fdc_sector_end=1";
                if f011_rsector_found = '0' then
                  report "reseting f011_rsector_found";
                end if;
                f011_rsector_found <= '0';
              end if;
              if fdc_byte_valid_2x = '1' and (fdc_sector_found_2x or f011_rsector_found)='1' then
                -- DEBUG: Note how many bytes we have received from the floppy
                report "fdc_byte valid asserted, storing byte @ $" & to_hstring(f011_buffer_disk_address);
                if to_integer(fdc_bytes_read(12 downto 0)) /= 8191 then
                  fdc_bytes_read(12 downto 0) <= to_unsigned(to_integer(fdc_bytes_read(12 downto 0)) + 1,13);
                else
                  fdc_bytes_read(12 downto 0) <= (others => '0');
                end if;

                -- Record byte into sector bufferr
                if f011_drq='1' then f011_lost <= '1'; end if;
                f011_drq <= '1';
                f011_buffer_disk_pointer_advance <= '1';
                -- Write to F011 sector buffer
                f011_buffer_write_address <= "110"&f011_buffer_disk_address;
                f011_buffer_wdata <= unsigned(fdc_byte_out_2x);
                f011_buffer_write <= '1';
                -- Defer any CPU write request, since we are writing
                sb_cpu_write_request <= sb_cpu_write_request;
              end if;
              if fdc_crc_error_2x='1' then
                -- Failed to read sector due to CRC error
                -- So set CRC flag:
                f011_crc <= '1';

                -- But don't abort reading, just retry
                -- (The existing timeout mechanism will catch us eventually)
                sd_state <= FDCReadingSectorWait;
              elsif fdc_sector_end_2x='1' and f011_rsector_found='1' then
                -- Clear read request only at the end of the sector we are looking for
                report "Clearing fdc_read_request due end of target sector";
                f011_crc <= '0';
                fdc_read_request <= '0';
                fdc_bytes_read(1) <= '1';
                f011_busy <= '0';
                sd_state <= Idle;
                fdc_sector_operation <= '0';
              end if;
            end if;


        when F011WriteSector =>
          -- Sit out the wait state for reading the next sector buffer byte
          -- as we copy the F011 sector buffer to the primary SD card sector buffer.
          report "Starting to write sector from unified FDC/SD buffer.";
          f011_buffer_cpu_address <= (others => '0');
          sb_cpu_read_request <= '1';
--          f011_buffer_disk_pointer_advance <= '1';
          -- Abort CPU buffer read if in progess, since we are reading the buffer
          sb_cpu_reading <= '0';

          sd_handshake <= '0';
          sd_handshake_internal <= '0';

          sd_state <= WriteSector;
        when WriteSector =>
          -- Begin writing a sector into the buffer
          if sdio_busy='0' and sdcard_busy='0' then
            report "SDWRITE: Busy flag clear; writing value $" & to_hstring(f011_buffer_rdata);
            sd_dowrite <= '1';
            sdio_busy <= '1';
            skip <= 0;
            sd_wrote_byte <= '0';
            sd_state <= WritingSector;
          else
            report "SDWRITE: Waiting for busy flag to clear...";
            sd_dowrite <= '0';
          end if;

        when WritingSector =>
          if sd_data_ready='1' then
            sd_dowrite <= '0';
            if sd_fill_mode='1' then
              sd_wdata <= sd_fill_value;
            else
              sd_wdata <= f011_buffer_rdata;
            end if;
            sd_handshake <= '1';
            sd_handshake_internal <= '1';

            report "SDWRITE: skip = " & integer'image(skip)
              & ", sd_buffer_offset=$" & to_hstring(sd_buffer_offset)
              & ", sd_wrote_byte=" & std_logic'image(sd_wrote_byte)
              & ", sd_wdata=$" & to_hstring(f011_buffer_rdata);
            if skip = 0 then
              -- Byte has been accepted, write next one
              sd_state <= WritingSectorAckByte;

--              f011_buffer_disk_pointer_advance <= '1';
              sd_buffer_offset <= sd_buffer_offset + 1;

              sd_wrote_byte <= '1';
            else
              skip <= skip - 1;
              sd_state <= WritingSectorAckByte;
            end if;
          end if;

        when WritingSectorAckByte =>
          -- Wait until controller acknowledges that we have acked it
          if sd_data_ready='0' then
            sd_handshake <= '0';
            sd_handshake_internal <= '0';
            if sd_buffer_offset = "000000000" and sd_wrote_byte='1' then
              -- Whole sector written when we have written 512 bytes
              sd_state <= DoneWritingSector;
            else
              -- Still more bytes to read.
              sd_state <= WritingSector;

              f011_buffer_disk_pointer_advance <= '1';
              -- Abort CPU buffer read if in progess, since we are reading the buffer
              sb_cpu_reading <= '0';
            end if;
          end if;

        when DoneReadingSector =>
          sdio_busy <= '0';
          f011_busy <= '0';
          sd_state <= Idle;

        when DoneWritingSector =>
          sdio_busy <= '0';
          sd_state <= Idle;
          if f011_busy='1' then
            f011_busy <= '0';
            f011_wsector_found <= '1';
          end if;

        when QSPI_send_command =>
          report "QSPI: send command phase" & integer'image(qspi_read_sector_phase)
            & ", cmd_only=" & std_logic'image(spi_flash_cmd_only);
          if qspi_read_sector_phase < 3 or (qspi_read_sector_phase mod 2 = 0) then
            qspi_clock_int <= '1';
          else
            qspi_clock_int <= '0';
          end if;
          -- Go through QSPI command setup and address TX.
          -- Allow extra cycles after changing clock, because
          -- there is 1 cycle latency on clock output
          if qspi_read_sector_phase < qspi_command_len then
            qspi_read_sector_phase <= qspi_read_sector_phase + 1;
          else
            report "QSPI: Preserving clock while switching to action state at phase " & integer'image(qspi_read_sector_phase);
            sd_state <= qspi_action_state;
            qspi_clock_int <= qspi_clock_int;
          end if;
          if qspi_read_sector_phase > 2 and qspi_read_sector_phase < (2 + 8*2) then
            qspidb(0) <= spi_flash_cmd_byte(7);
          end if;
          if qspi_read_sector_phase > 18 and qspi_read_sector_phase < (18 + 32*2) then
            qspidb(0) <= spi_address(31);
          end if;
          if qspi_read_sector_phase = 20 and spi_flash_cmd_only='1' then
            spi_flash_cmd_only <= '0';
            report "QSPI: Exiting early due to cmd_only flag";
            qspi_clock_int <= qspi_clock_int;
            if qspi_action_state = QSPI_Release_CS then
              report "QSPI: Pulling clock low while exiting to action state";
              qspi_clock_int <= '0';
            end if;
            sd_state <= qspi_action_state;
          end if;
          if qspi_read_sector_phase = (20+16*2) and spi_flash_16bits='1' then
            report "QSPI: Exiting early due to flash_16bits flag";
            if qspi_action_state = QSPI_Release_CS then
              qspi_clock_int <= '0';
              spi_flash_16bits <= '0';
            end if;
            sd_state <= qspi_action_state;
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
              if qspi_action_state = qspi_qwrite_512 or qspi_action_state = qspi_qwrite_256 or qspi_action_state = qspi_qwrite_16 then
                sd_state <= qspi_action_state;
              end if;
            when 84 =>
              -- No dummy cycles for sector erase operations,
              -- and CS must be released while clock low IMMEDIATELY
              -- after writing the 32nd address bit
              if qspi_action_state = QSPI_Release_CS or spi_no_dummy_cycles='1' then
                qspi_clock_int <= '0';
                report "QSPI: pulling clock low while switching to action state";

                spi_no_dummy_cycles <= '0';
                sd_state <= qspi_action_state;
              end if;
            when others =>
              null;
          end case;
          case qspi_read_sector_phase is
                            -- Release CS to ensure new transaction
            when 0 | 1   => qspicsn <= '1';
                            -- Bring chip to attention
            when 2       => qspicsn <= '0';
                            -- Send QSPI command
            when 3 | 4   => qspidb_oe <= '1'; qspidb_tristate <= '0';
                            qspidb(3 downto 1) <= "111";
                            -- Address of data to read
            when others => null;
          end case;

        when QSPI_Release_CS =>
          qspi_clock_int <= '0';
          qspicsn <= '1';
          sd_state <= Idle;
        when SPI_read_512 =>
          -- Tristate SI and SO
          report "QSPI: in SPI_read_512";
          qspidb_tristate <= '1';
          qspidb_oe <= '0';
          sd_buffer_offset <= to_unsigned(0,9);
          sd_state <= SPI_read_phase1;
          -- Keep track if read bytes are identical or not
          -- (used for speeding up erasure checking of flash)
          qspi_bytes_differ <= '0';
        when QSPI_read_512 =>
          -- Tristate SI and SO
          qspidb_tristate <= '1';
          qspidb_oe <= '0';
          sd_buffer_offset <= to_unsigned(0,9);
          sd_state <= QSPI_read_phase1;
          -- Keep track if read bytes are identical or not
          -- (used for speeding up erasure checking of flash)
          qspi_bytes_differ <= '0';
        when QSPI_read_phase1 =>
          qspi_clock_int <= '0';
          sd_state <= QSPI_read_phase2;
        when QSPI_read_phase2 =>
          qspi_clock_int <= '1';
          sd_state <= QSPI_read_phase3;
        when QSPI_read_phase3 =>
          qspi_bits <= qspidb_in;
          qspi_clock_int <= '0';
          sd_state <= QSPI_read_phase4;
        when QSPI_read_phase4 =>
          report "QSPI read $"
            & to_hstring(qspi_bits) & to_hstring(qspidb_in) &
            " into f011 buffer @ $" & to_hstring(sd_buffer_offset);
          if qspi_verify_mode='0' then
            f011_buffer_write_address <= "111"&sd_buffer_offset;
            f011_buffer_wdata(3 downto 0) <= qspidb_in;
            f011_buffer_wdata(7 downto 4) <= qspi_bits;
            f011_buffer_write <= '1';

            if sd_buffer_offset = 0 then
              qspi_byte_value(3 downto 0) <= qspidb_in;
              qspi_byte_value(7 downto 4) <= qspi_bits;
            else
              if qspi_byte_value(3 downto 0) /= qspidb_in then
                qspi_bytes_differ <= '1';
              elsif qspi_byte_value(7 downto 4) /= qspi_bits then
                qspi_bytes_differ <= '1';
              end if;
            end if;
          else
            -- Compare byte with previously read byte and set bytes_differ flag
            -- if different
            report "QSPI: Verifying: read $" & to_hstring(qspi_bits) & to_hstring(qspidb_in)
              & " vs expected $" & to_hstring(f011_buffer_rdata);
            report "QSPI: qspi_command_len="& integer'image(qspi_command_len);
            if (f011_buffer_rdata(3 downto 0) /= qspidb_in)
              or (f011_buffer_rdata(7 downto 4) /= qspi_bits) then
              qspi_bytes_differ <= '1';
            end if;
          end if;
          if sd_buffer_offset /= 511 then
            sd_buffer_offset <= sd_buffer_offset + 1;
            sd_state <= QSPI_read_phase1;
          else
            sd_state <= Idle;
            sdio_busy <= '0';
          end if;
          qspi_clock_int <= '1';
        when QSPI_qwrite_512 =>
          sdio_busy <= '1';
          sdio_error <= '0';
          qspidb_tristate <= '0';
          qspidb_oe <= '1';
          qspi_clock_int <= '1';
          sd_state <= QSPI_qwrite_phase1;
        when QSPI_write_512 =>
          sdio_busy <= '1';
          sdio_error <= '0';
          qspidb_tristate <= '0';
          qspidb_oe <= '1';
          qspi_clock_int <= '1';
          sd_buffer_offset <= to_unsigned(0,9);
          sd_state <= QSPI_write_phase1;
        when QSPI_qwrite_256 =>
          sdio_busy <= '1';
          sdio_error <= '0';
          qspidb_tristate <= '0';
          qspidb_oe <= '1';
          qspi_clock_int <= '1';
          sd_state <= QSPI_qwrite_phase1;
        when QSPI_qwrite_16 =>
          sdio_busy <= '1';
          sdio_error <= '0';
          qspidb_tristate <= '0';
          qspidb_oe <= '1';
          qspi_clock_int <= '1';
          sd_state <= QSPI_qwrite_phase1;
        when QSPI_write_256 =>
          sdio_busy <= '1';
          sdio_error <= '0';
          qspidb_tristate <= '0';
          qspidb_oe <= '1';
          qspi_clock_int <= '1';
          -- Write 2nd half of SD card buffer to QSPI
          sd_buffer_offset <= to_unsigned(256,9);
          sd_state <= QSPI_write_phase1;

        when QSPI_qwrite_phase1 =>
          report "QSPI: QUAD TX $" & to_hstring(f011_buffer_rdata) & " @ $" & to_hstring(sd_buffer_offset);
          sd_state <= QSPI_qwrite_phase2;
          qspidb <= f011_buffer_rdata(7 downto 4);
          qspi_bits <= f011_buffer_rdata(3 downto 0);
          qspi_clock_int <= '0';
        when QSPI_qwrite_phase2 =>
          sd_state <= QSPI_qwrite_phase3;
          qspi_clock_int <= '1';
        when QSPI_qwrite_phase3 =>
          sd_state <= QSPI_qwrite_phase4;
          qspidb <= qspi_bits;
          qspi_clock_int <= '0';
          report "QSPI: Bump sd_buffer_offset from $" & to_hstring(sd_buffer_offset);
          if sd_buffer_offset /= 511 then
            sd_buffer_offset <= sd_buffer_offset + 1;
          else
            sd_buffer_offset <= to_unsigned(0,9);
          end if;
        when QSPI_qwrite_phase4 =>
          qspi_clock_int <= '1';
          if sd_buffer_offset /= 0 then
            sd_state <= QSPI_qwrite_phase1;
          else
            sd_state <= Idle;
            sdio_busy <= '0';
          end if;

        when QSPI_write_phase1 =>
          qspi_bit_counter <= 0;
          sd_state <= QSPI_write_phase2;
        when QSPI_write_phase2 =>
          if qspi_bit_counter = 0 then
            report "QSPI: Sending byte $" & to_hstring(f011_buffer_rdata);
            qspi_byte_value <= f011_buffer_rdata;
          end if;
          qspi_clock_int <= '0';
          sd_state <= QSPI_write_phase3;
        when QSPI_write_phase3 =>
          qspidb_tristate <= '0';
          qspidb_oe <= '1';
          qspidb(3 downto 1) <= "111";
          qspidb(0) <= qspi_byte_value(7);
          report "QSPI: Writing bit " & std_logic'image(std_logic(qspi_byte_value(7)));
          qspi_byte_value(7 downto 1) <= qspi_byte_value(6 downto 0);
          sd_state <= QSPI_write_phase4;
        when QSPI_write_phase4 =>
          qspi_clock_int <= '1';
          if qspi_bit_counter = 7 then
            if sd_buffer_offset /= 511 then
              sd_buffer_offset <= sd_buffer_offset + 1;
              sd_state <= QSPI_write_phase1;
            else
              sd_state <= Idle;
              sdio_busy <= '0';
            end if;
          else
            qspi_bit_counter <= qspi_bit_counter + 1;
            sd_state <= QSPI_write_phase2;
          end if;

        when SPI_read_phase1 =>
          qspi_bit_counter <= 0;
          sd_state <= SPI_read_phase2;
          qspidb_tristate <= '1';
          qspidb_oe <= '0';
        when SPI_read_phase2 =>
          qspi_clock_int <= '0';
          sd_state <= SPI_read_phase3;
        when SPI_read_phase3 =>
          qspi_byte_value(0) <= qspidb_in(1);
          report "QSPI: Reading bit " & std_logic'image(std_logic(qspidb_in(1)));
          qspi_byte_value(7 downto 1) <= qspi_byte_value(6 downto 0);
          sd_state <= SPI_read_phase4;
        when SPI_read_phase4 =>
          qspi_clock_int <= '1';
          if qspi_bit_counter = 7 then
            report "QSPI: SPI read byte $" & to_hstring(qspi_byte_value);
            f011_buffer_write_address <= "111"&sd_buffer_offset;
            f011_buffer_wdata <= qspi_byte_value;
            f011_buffer_write <= '1';

            if sd_buffer_offset /= 511 then
              sd_buffer_offset <= sd_buffer_offset + 1;
              sd_state <= SPI_read_phase1;
            else
              sd_state <= Idle;
              sdio_busy <= '0';
              qspicsn <= '1';
            end if;
          else
            qspi_bit_counter <= qspi_bit_counter + 1;
            sd_state <= SPI_read_phase2;
          end if;


        when QSPI4_write_512 =>
          sdio_busy <= '1';
          sdio_error <= '0';
          qspidb_tristate <= '1';
          qspidb_oe <= '0';
          sd_buffer_offset <= to_unsigned(0,9);
          sd_state <= QSPI4_write_phase1;
        when QSPI4_write_256 =>
          sdio_busy <= '1';
          sdio_error <= '0';
          qspidb_tristate <= '1';
          qspidb_oe <= '0';
          -- Write 2nd half of SD card buffer to QSPI
          sd_buffer_offset <= to_unsigned(256,9);
          sd_state <= QSPI4_write_phase1;
        when QSPI4_write_phase1 =>
          qspi_bit_counter <= 0;
          sd_state <= QSPI4_write_phase2;
        when QSPI4_write_phase2 =>
          if qspi_bit_counter = 0 then
            report "QSPI4: Sending byte $" & to_hstring(f011_buffer_rdata);
            qspi_byte_value <= f011_buffer_rdata;
          end if;
          -- XXX INCOMPLETE!
          sd_state <= Idle;
      end case;

    end if;
  end process;

end behavioural;

