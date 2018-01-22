--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2014
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

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity sdcardio is
  port (
    clock : in std_logic;
    pixelclk : in std_logic;
    reset : in std_logic;
    sdcardio_cs : in std_logic;
    f011_cs : in std_logic;

    hypervisor_mode : in std_logic;
    hyper_trap_f011_read : out std_logic := '0';
    hyper_trap_f011_write : out std_logic := '0';
    
    fpga_temperature : in std_logic_vector(11 downto 0);
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : in unsigned(19 downto 0);
    fastio_write : in std_logic;
    fastio_read : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0);

    virtualise_f011 : in std_logic;
    
    colourram_at_dc00 : in std_logic;
    viciii_iomode : in std_logic_vector(1 downto 0);
    
    sectorbuffermapped : out std_logic := '0';
    sectorbuffermapped2 : out std_logic := '0';
    sectorbuffercs : in std_logic;

    last_scan_code : in std_logic_vector(12 downto 0);
    
    drive_led : out std_logic := '0';
    motor : out std_logic := '0';
    
    sw : in std_logic_vector(15 downto 0);
    btn : in std_logic_vector(4 downto 0);
    
    -------------------------------------------------------------------------
    -- Lines for the SDcard interface itself
    -------------------------------------------------------------------------
    cs_bo : out std_logic;
    sclk_o : out std_logic;
    mosi_o : out std_logic;
    miso_i : in  std_logic;

    ----------------------------------------------------------------------
    -- Floppy drive interface
    ----------------------------------------------------------------------
    f_density : out std_logic := '1';
    f_motor : out std_logic := '1';
    f_select : out std_logic := '1';
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

    -- Audio in from digital SIDs
    leftsid_audio : in unsigned(17 downto 0);
    rightsid_audio : in unsigned(17 downto 0);
    
    -- Audio output
    ampPWM : out std_logic;
    ampPWM_l : out std_logic;
    ampPWM_r : out std_logic;
    ampSD : out std_logic := '1';  -- default to amplifier on

    -- Microphone
    micData : in std_logic;
    micClk : out std_logic;
    micLRSel : out std_logic;

    -- Temperature sensor
    tmpSDA : out std_logic;
    tmpSCL : out std_logic;
    tmpInt : in std_logic;
    tmpCT : in std_logic;

    ----------------------------------------------------------------------
    -- Flash RAM for holding config
    ----------------------------------------------------------------------
    QspiSCK : out std_logic;
    QspiDB : inout std_logic_vector(3 downto 0) := "ZZZZ";
    QspiCSn : out std_logic            

    );
end sdcardio;

architecture behavioural of sdcardio is
  
  signal QspiSCKInternal : std_logic := '1';
  signal QspiCSnInternal : std_logic := '1'; 
  
  signal aclMOSIinternal : std_logic := '0';
  signal aclSSinternal : std_logic := '0';
  signal aclSCKinternal : std_logic := '0';
  signal micClkinternal : std_logic := '0';
  signal micLRSelinternal : std_logic := '0';
  signal tmpSDAinternal : std_logic := '0';
  signal tmpSCLinternal : std_logic := '0';

  -- Combined 10-bit left/right audio
  signal pwm_value_new_left : unsigned(7 downto 0) := x"00";
  signal pwm_value_new_right : unsigned(7 downto 0) := x"00";
  signal pwm_value_combined : integer range 0 to 65535 := 0;
  signal pwm_value_left : integer range 0 to 65535 := 0;
  signal pwm_value_right : integer range 0 to 65535 := 0;
  signal pwm_value_combined_hold : integer range 0 to 65535 := 0;
  signal pwm_value_left_hold : integer range 0 to 65535 := 0;
  signal pwm_value_right_hold : integer range 0 to 65535 := 0;

  signal pdm_combined_accumulator : integer range 0 to 131071 := 0;
  signal pdm_left_accumulator : integer range 0 to 131071 := 0;
  signal pdm_right_accumulator : integer range 0 to 131071 := 0;
  signal ampPWM_pdm : std_logic := '0';
  signal ampPWM_pdm_l : std_logic := '0';
  signal ampPWM_pdm_r : std_logic := '0';

  signal pwm_counter : integer range 0 to 1024 := 0;
  signal ampPWM_pwm : std_logic := '0';
  signal ampPWM_pwm_l : std_logic := '0';
  signal ampPWM_pwm_r : std_logic := '0';

  signal audio_mode : std_logic := '0';
  signal stereo_swap : std_logic := '0';
  signal force_mono : std_logic := '0';
  signal ampSD_internal : std_logic := '1';
  
  signal mic_divider : unsigned(4 downto 0) := "00000";
  signal mic_counter : unsigned(7 downto 0) := "00000000";
  signal mic_onecount : unsigned(7 downto 0) := "00000000";
  signal mic_value_left : unsigned(7 downto 0) := "00000000";
  signal mic_value_right : unsigned(7 downto 0) := "00000000";
  
  -- debounce reading from or writing to $D087 so that buffered read/write
  -- behaves itself.
  signal last_was_d087 : std_logic := '0';
  
  signal skip : integer range 0 to 2;
  signal read_data_byte : std_logic := '0';
  signal sd_doread       : std_logic := '0';
  signal sd_dowrite      : std_logic := '0';
  signal sd_data_ready : std_logic := '0';

  -- Signals to communicate with SD controller core
  signal sd_sector       : unsigned(31 downto 0) := (others => '0');

  signal sd_datatoken    : unsigned(7 downto 0);
  signal sd_rdata        : unsigned(7 downto 0);
  signal sd_wdata        : unsigned(7 downto 0) := (others => '0');
  signal sd_error        : std_logic;
  signal sd_reset        : std_logic := '1';
  signal sdhc_mode : std_logic := '0';
  signal half_speed : std_logic := '0';

  -- IO mapped register to indicate if SD card interface is busy
  signal sdio_busy : std_logic := '0';
  signal sdio_error : std_logic := '0';
  signal sdio_fsm_error : std_logic := '0';

  signal sector_buffer_mapped : std_logic := '0';
  
  type sd_state_t is (Idle,
                      ReadSector,ReadingSector,ReadingSectorAckByte,DoneReadingSector,
                      FDCReadingSector,
                      WriteSector,WritingSector,WritingSectorAckByte,
                      HyperTrapRead,HyperTrapRead2,HyperTrapWrite,
                      F011WriteSector,DoneWritingSector);
  signal sd_state : sd_state_t := Idle;

  -- Diagnostic register for determining SD/SDHC card state.
  signal last_sd_state : unsigned(7 downto 0);
  
  -- F011 FDC emulation registers and flags
  signal diskimage_sector : unsigned(31 downto 0) := x"ffffffff";
  signal diskimage2_sector : unsigned(31 downto 0) := x"ffffffff";
  signal diskimage1_enable : std_logic := '0';
  signal diskimage2_enable : std_logic := '0';
  signal diskimage_offset : unsigned(10 downto 0);
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
  signal f011_swap : std_logic := '0';

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

  signal f011_led : std_logic := '0';
  signal f011_motor : std_logic := '0';

  signal f011_reg_clock : unsigned(7 downto 0) := x"FF";
  signal f011_reg_step : unsigned(7 downto 0) := x"80"; -- 8ms steps
  signal f011_reg_pcode : unsigned(7 downto 0) := x"00";
  signal counter_16khz : integer := 0;
  constant cycles_per_16khz : integer :=  (50000000/16000);
  signal busy_countdown : unsigned(15 downto 0) := x"0000";
  
  signal audio_reflect : std_logic_vector(3 downto 0) := "0000";

  signal cycles_per_interval : unsigned(7 downto 0)
    := to_unsigned(100,8);
  signal fdc_read_invalidate : std_logic := '0';
  signal target_track : unsigned(7 downto 0) := x"00";
  signal target_sector : unsigned(7 downto 0) := x"00";
  signal target_side : unsigned(7 downto 0) := x"00";
  signal target_any : std_logic := '0';
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

  signal fdc_mfm_state : unsigned(7 downto 0);
  signal fdc_last_gap : unsigned(15 downto 0);
  signal fdc_mfm_byte : unsigned(7 downto 0);
  signal fdc_quantised_gap : unsigned(7 downto 0);
  
  signal use_real_floppy : std_logic := '0';
  signal fdc_read_request : std_logic := '0';
  signal fdc_rotation_timeout : integer range 0 to 6 := 0;
  signal last_f_index : std_logic := '1';

  signal fdc_bytes_read : unsigned(15 downto 0) := x"0000";
  signal sd_wrote_byte : std_logic := '0';
  
  signal packed_rdata : std_logic_vector(7 downto 0);

  function resolve_sector_buffer_address(f011orsd : std_logic; addr : unsigned(8 downto 0))
    return integer is
  begin
    return to_integer("11" & f011orsd & addr);
  end function;
  
begin  -- behavioural

  --**********************************************************************
  -- SD card controller module.
  --**********************************************************************
  
  sd0: entity work.sd_controller 
    port map (
      cs => cs_bo,
      mosi => mosi_o,
      miso => miso_i,
      sclk => sclk_o,

      last_state => last_sd_state,
      
      sector_number => std_logic_vector(sd_sector),
      sdhc_mode => sdhc_mode,
      half_speed => half_speed,
      rd =>  sd_doread,
      wr =>  sd_dowrite,
      dm_in => '1',	-- data mode, 0 = write continuously, 1 = write single block
      reset => sd_reset,
      data_ready => sd_data_ready,
      din => std_logic_vector(sd_wdata),
      unsigned(dout) => sd_rdata,
      clk => clock	-- twice the SPI clk.  XXX Cannot exceed 50MHz
      );

  -- CPU direct-readable sector buffer, so that it can be memory mapped
  sb_memorymapped0: entity work.ram8x4096
    port map (
      clk => clock,

      -- CPU side read access
      cs => sectorbuffercs,
      address => sector_buffer_fastio_address,
      rdata => fastio_rdata,

      -- Write side controlled by SD-card side.
      -- (CPU side effects writes by asking SD-card side to write)
      w => f011_buffer_write,
      write_address => to_integer(f011_buffer_write_address),
      wdata => f011_buffer_wdata
      );
  
  -- Locally readable copy of the same data, so that we can read it when writing
  -- to SD card or floppy drive
  sb_workcopy: entity work.ram8x4096
    port map (
      clk => clock,

      cs => '1',
      address => to_integer(f011_buffer_read_address),
      rdata => f011_buffer_rdata,

      -- Write side controlled by SD-card side.
      -- (CPU side effects writes by asking SD-card side to write)
      w => f011_buffer_write,
      write_address => to_integer(f011_buffer_write_address),
      wdata => f011_buffer_wdata
      );

  -- Reader for real floppy drive
  mfm0: entity work.mfm_decoder port map (
    clock50mhz => clock,
    f_rdata => f_rdata,
    packed_rdata => packed_rdata,
    cycles_per_interval => cycles_per_interval,
    invalidate => fdc_read_invalidate,

    mfm_state => fdc_mfm_state,
    mfm_last_gap => fdc_last_gap,
    mfm_last_byte => fdc_mfm_byte,
    mfm_quantised_gap => fdc_quantised_gap,
    
    target_track => target_track,
    target_sector => target_sector,
    target_side => target_side,
    target_any => target_any,

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
  
  
  
  -- XXX also implement F011 floppy controller emulation.
  process (clock,fastio_addr,fastio_wdata,sector_buffer_mapped,sdio_busy,
           sd_reset,fastio_read,sd_sector,fastio_write,
           f011_track,f011_sector,f011_side,sdio_fsm_error,sdio_error,
           sd_state,f011_irqenable,f011_ds,f011_cmd,f011_busy,f011_crc,
           f011_track0,f011_rsector_found,f011_over_index,
           sdhc_mode,half_speed,sd_datatoken, sd_rdata,
           diskimage1_enable,f011_disk1_present,
           f011_disk1_write_protected,diskimage2_enable,f011_disk2_present,
           f011_disk2_write_protected,diskimage_sector,sw,btn,aclmiso,
           aclmosiinternal,aclssinternal,aclSCKinternal,aclint1,aclint2,
           tmpsdainternal,tmpsclinternal,tmpint,tmpct,tmpint,last_scan_code,
           pwm_value_new_left,mic_value_left,mic_value_right,qspidb,
           qspicsninternal,QspiSCKInternal,
           sectorbuffercs,f011_cs,f011_led,f011_head_side,f011_drq,
           f011_lost,f011_wsector_found,f011_write_gate,f011_irq,
           f011_buffer_rdata,f011_reg_clock,f011_reg_step,f011_reg_pcode,
           last_sd_state,f011_buffer_disk_address,f011_buffer_cpu_address,
           f011_flag_eq,sdcardio_cs,colourram_at_dc00,viciii_iomode,
           f_index,f_track0,f_writeprotect,f_rdata,f_diskchanged,
           use_real_floppy,target_any,fdc_first_byte,fdc_sector_end,
           fdc_sector_data_gap,fdc_sector_found,fdc_byte_valid,
           fdc_read_request,cycles_per_interval,found_track,
           found_sector,found_side,fdc_byte_out,fdc_mfm_state,
           fdc_mfm_byte,fdc_last_gap,packed_rdata,fdc_quantised_gap,
           fdc_bytes_read,fpga_temperature,ampsd_internal,audio_reflect,
           stereo_swap,force_mono,audio_mode,rightsid_audio,leftsid_audio           
           ) is
    variable temp_cmd : unsigned(7 downto 0);
  begin

    -- ==================================================================
    -- here is a combinational process (ie: not clocked)
    -- ==================================================================

    if hypervisor_mode='0' then
      sector_buffer_fastio_address <= resolve_sector_buffer_address(f011sd_buffer_select,fastio_addr(8 downto 0));
    else
      sector_buffer_fastio_address <= to_integer(fastio_addr(11 downto 0));
    end if;
    
    if fastio_read='1' and sectorbuffercs='0' then

      if f011_cs='1' and sdcardio_cs='0' then
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
            
          when "01000" =>
            -- CLOCK   |  C7   |  C6   |  C5   |  C4   |  C3   |  C2   |  C1   |  C0   | 8 RW
            fastio_rdata <= f011_reg_clock;
            
          when "01001" =>
            -- @IO:65 $D089 - F011 FDC step time (x62.5 micro seconds)
            -- STEP    |  S7   |  S6   |  S5   |  S4   |  S3   |  S2   |  S1   |  S0   | 9 RW
            fastio_rdata <= f011_reg_step;
            
          when "01010" =>
            -- P CODE  |  P7   |  P6   |  P5   |  P4   |  P3   |  P2   |  P1   |  P0   | A R
            fastio_rdata <= f011_reg_pcode;
          when "11011" => -- @IO:GS $D09B - Most recent SD card command sent
            fastio_rdata <= last_sd_state;
          when "11100" => -- @IO:GS $D09C - FDC-side buffer pointer low bits (DEBUG)
            fastio_rdata <= f011_buffer_disk_address(7 downto 0);
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

      elsif sdcardio_cs='1' and f011_cs='0' then
        -- microSD controller registers
        report "reading SDCARD registers" severity note;
        case fastio_addr(7 downto 0) is
          -- @IO:GS $D680.0 - SD controller BUSY flag
          -- @IO:GS $D680.1 - SD controller BUSY flag
          -- @IO:GS $D680.2 - SD controller RESET flag
          -- @IO:GS $D680.3 - SD controller sector buffer mapped flag
          -- @IO:GS $D680.4 - SD controller SDHC mode flag
          -- @IO:GS $D680.5 - SD controller SDIO FSM ERROR flag
          -- @IO:GS $D680.6 - SD controller SDIO error flag
          -- @IO:GS $D680.7 - SD controller half speed flag
          when x"80" =>
            -- status / command register
            -- error status in bit 6 so that V flag can be used for check
            report "reading $D680 SDCARD status register" severity note;
            fastio_rdata(7) <= half_speed;
            fastio_rdata(6) <= sdio_error;
            fastio_rdata(5) <= sdio_fsm_error;
            fastio_rdata(4) <= sdhc_mode;
            fastio_rdata(3) <= sector_buffer_mapped;
            fastio_rdata(2) <= sd_reset;
            fastio_rdata(1) <= sdio_busy;  -- SD-status, is busy if asserted ??
            fastio_rdata(0) <= sdio_busy;  -- why map to two bits?

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
          -- @IO:GS $D689.7 - Memory mapped sector buffer select: 1=SD-Card, 0=F011/FDC
          when x"89" =>
            fastio_rdata(0) <= f011_buffer_disk_address(8);
            fastio_rdata(1) <= f011_flag_eq and f011_drq;
            fastio_rdata(6 downto 2) <= (others => '0');
            fastio_rdata(7) <= f011sd_buffer_select;
          when x"8a" =>
            -- @IO:GS $D68A - DEBUG check signals that can inhibit sector buffer mapping
            fastio_rdata(0) <= colourram_at_dc00;
            fastio_rdata(1) <= viciii_iomode(1);
            
          when x"8b" =>
            -- BG the description seems in conflict with the assignment in the write section (below)
            -- @IO:GS $D68B - Diskimage control flags
            fastio_rdata(0) <= diskimage1_enable;
            fastio_rdata(1) <= f011_disk1_present;
            fastio_rdata(2) <= not f011_disk1_write_protected;
            fastio_rdata(3) <= diskimage2_enable;
            fastio_rdata(4) <= f011_disk2_present;
            fastio_rdata(5) <= not f011_disk2_write_protected;
          when x"8c" =>
            -- @IO:GS $D68C - Diskimage sector number (bits 0-7)
            fastio_rdata <= diskimage_sector(7 downto 0);
          when x"8d" =>
            -- @IO:GS $D68D - Diskimage sector number (bits 8-15)
            fastio_rdata <= diskimage_sector(15 downto 8);
          when x"8e" =>
            -- @IO:GS $D68E - Diskimage sector number (bits 16-23)
            fastio_rdata <= diskimage_sector(23 downto 16);
          when x"8f" =>
            -- @IO:GS $D68F - Diskimage sector number (bits 24-31)
            fastio_rdata <= diskimage_sector(31 downto 24);


          when x"a0" =>
            -- @IO:GS $D6A0 - DEBUG FDC read status lines
            fastio_rdata(7) <= f_index;
            fastio_rdata(6) <= f_track0;
            fastio_rdata(5) <= f_writeprotect;
            fastio_rdata(4) <= f_rdata;
            fastio_rdata(3) <= f_diskchanged;
            fastio_rdata(2 downto 0) <= (others => '1');
          when x"a1" =>
            -- @IO:GS $D6A1.0 - Use real floppy drive instead of SD card
            fastio_rdata(0) <= use_real_floppy;
            -- @IO:GS $D6A1.1 - Match any sector on a real floppy read/write
            fastio_rdata(1) <= target_any;
            -- @IO:GS $D6A1.2-6 - FDC debug status flags
            fastio_rdata(2) <= fdc_first_byte;
            fastio_rdata(3) <= fdc_sector_end;
            fastio_rdata(4) <= fdc_crc_error;
            fastio_rdata(5) <= fdc_sector_found;
            fastio_rdata(6) <= fdc_byte_valid;
            fastio_rdata(7) <= fdc_read_request;
          when x"a2" =>
            -- @IO:GS $D6A2 - FDC clock cycles per MFM data bit
            fastio_rdata <= cycles_per_interval;
          when x"a3" =>
            -- @IO:GS $D6A3 - FDC track number of last matching sector header
            fastio_rdata <= found_track;
          when x"a4" =>
            -- @IO:GS $D6A4 - FDC sector number of last matching sector header
            fastio_rdata <= found_sector;
          when x"a5" =>
            -- @IO:GS $D6A5 - FDC side number of last matching sector header
            fastio_rdata <= found_side;
          when x"a6" =>
            -- @IO:GS $D6A6 - DEBUG FDC decoded MFM byte
            fastio_rdata <= fdc_byte_out;
          when x"a7" =>
            -- @IO:GS $D6A7 - DEBUG FDC decoded MFM state
            fastio_rdata <= fdc_mfm_state;
          when x"a8" =>
            -- @IO:GS $D6A8 - DEBUG FDC last decoded MFM byte
            fastio_rdata <= fdc_mfm_byte;
          when x"a9" =>
            -- @IO:GS $D6A9 - DEBUG FDC last gap interval (LSB)
            fastio_rdata <= fdc_last_gap(7 downto 0);
          when x"aa" =>
            -- @IO:GS $D6AA - DEBUG FDC last gap interval (MSB)
            fastio_rdata <= fdc_last_gap(15 downto 8);
          when x"ab" =>
            -- @IO:GS $D6AB - DEBUG FDC last 7 rdata bits (packed by mfm_gaps)
            fastio_rdata <= unsigned(packed_rdata);
          when x"ac" =>
            -- @IO:GS $D6AC - DEBUG FDC last quantised gap
            fastio_rdata <= unsigned(fdc_quantised_gap);
          when x"ad" =>
            -- @IO:GS $D6AD - DEBUG FDC bytes read counter (LSB)
            fastio_rdata <= unsigned(fdc_bytes_read(7 downto 0));
          when x"ae" =>
            -- @IO:GS $D6AE - DEBUG FDC bytes read counter (MSB)
            fastio_rdata <= unsigned(fdc_bytes_read(15 downto 8));
          when x"ec" =>
            -- @IO:GS $D6EC - DEBUG duplicate of FPGA switches 0-7
            fastio_rdata(7 downto 0) <= unsigned(sw(7 downto 0));
          when x"ed" =>
            -- @IO:GS $D6ED - DEBUG duplicate of FPGA switches 8-15
            fastio_rdata(7 downto 0) <= unsigned(sw(15 downto 8));
          when x"EE" =>
            -- @IO:GS $D6EE - Temperature sensor (lower byte)
            fastio_rdata <= unsigned("0000"&fpga_temperature(3 downto 0));
          when x"EF" =>
            -- @IO:GS $D6EF - Temperature sensor (upper byte)
            fastio_rdata <= unsigned(fpga_temperature(11 downto 4));
          when x"F2" =>
            -- @IO:GS $D6F2 - Read FPGA five-way buttons
            fastio_rdata(7 downto 5) <= "000";
            fastio_rdata(4 downto 0) <= unsigned(btn(4 downto 0));
          when x"F3" =>
            -- @IO:GS $D6F3 Accelerometer inputs
            fastio_rdata(0) <= aclMISO;
            fastio_rdata(1) <= aclMOSIinternal;
            fastio_rdata(2) <= aclSSinternal;
            fastio_rdata(3) <= aclSCKinternal;
            fastio_rdata(4) <= '0';
            fastio_rdata(5) <= aclInt1;
            fastio_rdata(6) <= aclInt2;
            fastio_rdata(7) <= aclInt1 or aclInt2;
          when x"F5" =>
            -- @IO:GS $D6F5 Bit-bashed temperature sensor
            fastio_rdata(0) <= tmpSDAinternal;
            fastio_rdata(1) <= tmpSCLinternal;
            fastio_rdata(4 downto 2) <= "000";
            fastio_rdata(5) <= tmpInt;
            fastio_rdata(6) <= tmpCT;
            fastio_rdata(7) <= tmpInt or tmpCT;
            fastio_rdata(7 downto 0) <= unsigned(fpga_temperature(11 downto 4));
          when x"F6" =>
            -- @IO:GS $D6F6 - Keyboard scan code reader (lower byte)
            fastio_rdata <= unsigned(last_scan_code(7 downto 0));
          when x"F7" =>
            -- @IO:GS $D6F7 - Keyboard scan code reader (upper nybl)
            fastio_rdata <= unsigned("000"&last_scan_code(12 downto 8));
          when x"F8" =>
            -- PWM output
            fastio_rdata <= pwm_value_new_left;
          when x"F9" =>
            -- Debug interface to see what audio output is doing
            fastio_rdata(0) <= ampSD_internal;
            fastio_rdata(4 downto 1) <= unsigned(audio_reflect);
            fastio_rdata(5) <= stereo_swap;
            fastio_rdata(6) <= force_mono;
            fastio_rdata(7) <= audio_mode;
          when x"FA" =>
            -- PWM output
            fastio_rdata <= pwm_value_new_left;
          when x"FB" =>
            -- @IO:GS $D6FB - microphone input (left)
            fastio_rdata <= mic_value_left;
          when x"FC" =>
            -- @IO:GS $D6F7 - microphone input (right)
            fastio_rdata <= mic_value_right;
          when x"FD" =>
            -- Right SID audio (high) for debugging
            fastio_rdata <= rightsid_audio(17 downto 10);
          when x"FE" =>
            -- Right SID audio (low) for debugging            
            fastio_rdata <= rightsid_audio(9 downto 2);
          when x"FF" =>
            -- Flash interface
            fastio_rdata(3 downto 0) <= unsigned(QspiDB);
            fastio_rdata(5 downto 4) <= "00";
            fastio_rdata(6) <= QspiCSnInternal;
            fastio_rdata(7) <= QspiSCKInternal;
          when others =>
            fastio_rdata <= (others => 'Z');
        end case;
      else
        -- Otherwise tristate output
        fastio_rdata <= (others => 'Z');
      end if;
    end if;

    -- ==================================================================
    -- ==================================================================
    
    if rising_edge(clock) then

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
        f011_buffer_read_address <= "110"&f011_buffer_cpu_address;
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
          -- Stepping pulses should be short, so we clear it here
          f_step <= '1';
        end if;
      end if;
            
      -- Generate combined audio from stereo sids plus 2 8-bit digital channels
      -- (4x14 bit values = 16 bit level)
      pwm_value_combined <= to_integer(leftsid_audio(17 downto 4))
                            + to_integer(rightsid_audio(17 downto 4))
                            + to_integer("00"&pwm_value_new_left & "0000")
                            + to_integer("00"&pwm_value_new_right & "0000");
      -- 2x15 bit values = 16 bit levels
      pwm_value_left <= to_integer(leftsid_audio(17 downto 3))
                        + to_integer("00"&pwm_value_new_left &"00000");
      pwm_value_right <= to_integer(rightsid_audio(17 downto 3))
                         + to_integer("00"&pwm_value_new_right&"00000");

      
      -- Implement 10-bit digital combined audio output
      audio_reflect(0) <= not audio_reflect(0);
      -- We have three versions of audio output:
      -- 1. Delta-Sigma (aka PDM), which should be most accurate, but requires
      -- good low-pass output filters
      -- 2. PWM, similar to what we used to use.
      -- 3. Balanced PWM, where the pulse is centered in the time domain,
      -- which apparently is "better". I have a wooden ear, so can't tell.

      if audio_mode = '0' then
        ampPWM <= ampPWM_pdm;
        if force_mono = '1' then
          -- Play combined audio through both left and right channels
          ampPWM_l <= ampPWM_pdm;
          ampPWM_r <= ampPWM_pdm;
        elsif stereo_swap='0' then
          -- Don't swap stereo channels
          ampPWM_l <= ampPWM_pdm_l;
          ampPWM_r <= ampPWM_pdm_r;
        else
          -- Swap stereo channels
          ampPWM_r <= ampPWM_pdm_l;
          ampPWM_l <= ampPWM_pdm_r;
        end if;
      else
        ampPWM <= ampPWM_pwm;
        if force_mono = '1' then
          -- Play combined audio through both left and right channels
          ampPWM_l <= ampPWM_pwm;
          ampPWM_r <= ampPWM_pwm;
        elsif stereo_swap='0' then
          -- Don't swap stereo channels
          ampPWM_l <= ampPWM_pwm_l;
          ampPWM_r <= ampPWM_pwm_r;
        else
          -- Swap stereo channels
          ampPWM_r <= ampPWM_pwm_l;
          ampPWM_l <= ampPWM_pwm_r;
        end if;
      end if;
      -- 40000 is to reduce range
      if pdm_combined_accumulator < 65536 +40000 then
        pdm_combined_accumulator <= pdm_combined_accumulator + pwm_value_combined;
        ampPWM_pdm <= '0';
        audio_reflect(1) <= '0';
      else
        pdm_combined_accumulator <= pdm_combined_accumulator + pwm_value_combined - 65536 - 40000;
        ampPWM_pdm <= '1';
        audio_reflect(1) <= '1';
      end if;
      if pdm_left_accumulator < 65536 then
        pdm_left_accumulator <= pdm_left_accumulator + pwm_value_left;
        ampPWM_pdm_l <= '0';
        audio_reflect(2) <= '0';
      else
        pdm_left_accumulator <= pdm_left_accumulator + pwm_value_left - 65536;
        ampPWM_pdm_l <= '1';
        audio_reflect(2) <= '1';
      end if;
      if pdm_right_accumulator < 65536 then
        pdm_right_accumulator <= pdm_right_accumulator + pwm_value_right;
        ampPWM_pdm_r <= '0';
        audio_reflect(3) <= '0';
      else
        pdm_right_accumulator <= pdm_right_accumulator + pwm_value_right - 65536;
        ampPWM_pdm_r <= '1';
        audio_reflect(3) <= '1';
      end if;

      -- Normal PWM
      if pwm_counter < 1024 then
        pwm_counter <= pwm_counter + 1;
        if to_integer(to_unsigned(pwm_value_combined_hold,16)(15 downto 6)) = pwm_counter then
          ampPwm_pwm <= '0';
        end if;
        if to_integer(to_unsigned(pwm_value_left_hold,16)(15 downto 6)) = pwm_counter then
          ampPwm_pwm_l <= '0';
        end if;
        if to_integer(to_unsigned(pwm_value_right_hold,16)(15 downto 6)) = pwm_counter then
          ampPwm_pwm_r <= '0';
        end if;
      else
        pwm_counter <= 0;
        pwm_value_combined_hold <= pwm_value_combined;
        pwm_value_left_hold <= pwm_value_left;
        pwm_value_right_hold <= pwm_value_right;
        if to_integer(to_unsigned(pwm_value_combined,16)(15 downto 6)) = 0 then
          ampPWM_pwm <= '0';
        else
          ampPWM_pwm <= '1';
        end if;
        if to_integer(to_unsigned(pwm_value_left,16)(15 downto 6)) = 0 then
          ampPWM_pwm_l <= '0';
        else
          ampPWM_pwm_l <= '1';
        end if;
        if to_integer(to_unsigned(pwm_value_right,16)(15 downto 6)) = 0 then
          ampPWM_pwm_r <= '0';
        else
          ampPWM_pwm_r <= '1';
        end if;
      end if;


      -- microphone sampling process
      -- max frequency is 3MHz. 48MHz/16 ~= 3MHz
      if mic_divider < 16 then
        if mic_divider < 8 then
          micCLK <= '1';
        else
          micCLK <= '0';
        end if;
        mic_divider <= mic_divider + 1;
      else
        mic_divider <= (others => '0');
        if mic_counter < 127 then
          if micData='1' then
            mic_onecount <= mic_onecount + 1;
          end if;
          mic_counter <= mic_counter + 1;
        else
          -- finished sampling, update output
          if micLRSelinternal='0' then
            mic_value_left(7 downto 0) <= mic_onecount;
          else
            mic_value_right(7 downto 0) <= mic_onecount;
          end if;
          mic_onecount <= (others => '0');
          mic_counter <= (others => '0');
          micLRSel <= not micLRSelinternal;
          micLRSelinternal <= not micLRSelinternal;
        end if;
      end if;

      if use_real_floppy='1' then
        -- PC drives use a combined RDY and DISKCHANGE signal.
        -- You can only clear the DISKCHANGE and re-assert RDY
        -- by stepping the disk (thus the ticking of 
        f011_disk_present <= '1';
        f011_write_protected <= not f_writeprotect;
      elsif f011_ds=x"000" then
        f011_write_protected <= f011_disk1_write_protected;
        f011_disk_present <= f011_disk1_present;
      elsif f011_ds=x"001" then
        f011_write_protected <= f011_disk2_write_protected;      
        f011_disk_present <= f011_disk2_present;
      end if;
      
      if use_real_floppy='1' then
        -- When using the real drive, use correct index and track 0 sensors
        f011_track0 <= not f_track0;
        f011_over_index <= not f_index;
        f011_disk_changed <= not f_diskchanged;
      else
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
      diskimage_offset(10 downto 0) <=
        to_unsigned(
          to_integer(f011_track(6 downto 0) & "0000")
          +to_integer("00" & f011_track(6 downto 0) & "00")
          +to_integer("000" & physical_sector),11);
      -- and don't let it point beyond the end of the disk
      if (f011_track >= 80) or (physical_sector > 20) then
        -- point to last sector if disk instead
        diskimage_offset <= to_unsigned(1599,11);
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
          case fastio_addr(4 downto 0) is

            when "00000" =>
              -- @IO:C65 $D080 - F011 FDC control
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
              drive_led <= fastio_wdata(6);
              f011_motor <= fastio_wdata(5);
              motor <= fastio_wdata(5);

              f_motor <= not fastio_wdata(5); -- start motor on real drive
              f_select <= not fastio_wdata(5);
              f_side1 <= not fastio_wdata(3);
              
              f011_swap <= fastio_wdata(4);
              if fastio_wdata(4) /= f011_swap then
                -- switch halves of buffer if swap bit changes
                f011_buffer_cpu_address(8) <= not f011_buffer_cpu_address(8);
                sb_cpu_read_request <= '1';
              end if;
              f011_head_side(0) <= fastio_wdata(3);
              f011_ds <= fastio_wdata(2 downto 0);
              if use_real_floppy='0' then
                if fastio_wdata(2 downto 0) /= f011_ds then
                  f011_disk_changed <= '0';
                end if;
              end if;

            when "00001" =>           -- $D081
              -- @IO:C65 $D081 - F011 FDC command
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

                when x"40" | x"44" =>         -- read sector
                  -- calculate sector number.
                  -- physical sector on disk = track * $14 + sector on track
                  -- then add to disk image start sector for the selected
                  -- drive.
                  -- put sector number into sd_sector, and then trigger read.
                  -- If no disk image is enabled, then report an error.

                  -- Start reading into start of pointer
                  f011_buffer_disk_address <= (others => '0');
                  
                  if use_real_floppy='1' and f011_ds="000" then
                    report "Using real floppy drive, asserting fdc_read_request";
                    -- Real floppy drive request
                    fdc_read_request <= '1';
                    -- Read must complete within 6 rotations
                    fdc_rotation_timeout <= 6;                      
                    
                    -- Mark F011 as busy with FDC job
                    f011_busy <= '1';
                    -- Clear request not found flag (gets set by timeout if required)
                    f011_rnf <= '0';
                    
                    sd_state <= FDCReadingSector;
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
                      if sdhc_mode='1' then
                        sd_sector <= diskimage_sector + diskimage_offset;
                      else
                        sd_sector(31 downto 9) <= diskimage_sector(31 downto 9) +
                                                  diskimage_offset;     
                      end if;
                    end if;
                    if virtualise_f011='1' then
                      -- Hypervisor virtualised
                      sd_state <= HyperTrapRead;
                      sd_sector(10 downto 0) <= diskimage_offset;
                      sd_sector(31 downto 11) <= (others => '0');
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
                  
                  if f011_ds="000" and ((diskimage1_enable or use_real_floppy)='0'
                                        or f011_disk1_present='0'
                                        or f011_disk1_write_protected='1') then
                    f011_rnf <= '1';
                    report "Drive 0 selected, but not mounted.";
                  elsif f011_ds="001" and (diskimage2_enable='0'
                                           or f011_disk2_present='0'
                                           or f011_disk2_write_protected='1') then
                    f011_rnf <= '1';
                    report "Drive 1 selected, but not mounted.";
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
                    if sdhc_mode='1' then
                      sd_sector <= diskimage_sector + diskimage_offset;
                    else
                      sd_sector(31 downto 9) <= diskimage_sector(31 downto 9) +
                                                diskimage_offset;     
                    end if;
                    -- XXX Writing with real floppy causes a hypervisor trap
                    -- instead of writing to disk.
                    if virtualise_f011='0' and use_real_floppy='0' then
                      sd_state <= F011WriteSector;
                    else
                      sd_state <= HyperTrapWrite;
                      sd_sector(10 downto 0) <= diskimage_offset;
                      sd_sector(31 downto 11) <= (others => '0');
                    end if;
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                    report "Commencing FDC buffered write.";
                  end if;

                when x"10" =>         -- head step out, or no step
                  f011_head_track <= f011_head_track - 1;
                  f_step <= '0';
                  f_stepdir <= '1';
                  f_select <= '0';
                  f_wgate <= '1';
                  f011_busy <= '1';
                  busy_countdown(15 downto 8) <= (others => '0');
                  busy_countdown(7 downto 0) <= f011_reg_step; 
                when x"14" =>
                  -- be busy for one step interval, without
                  -- actually stepping
                  f011_busy <= '1';
                  f_select <= '0';
                  busy_countdown(15 downto 8) <= (others => '0');
                  busy_countdown(7 downto 0) <= f011_reg_step; 
                when x"18" =>         -- head step in
                  f_step <= '0';
                  f_stepdir <= '0';
                  f_select <= '0';
                  f_wgate <= '1';
                  f011_head_track <= f011_head_track + 1;
                  f011_busy <= '1';
                  busy_countdown(15 downto 8) <= (others => '0');
                  busy_countdown(7 downto 0) <= f011_reg_step; 
                when x"20" =>         -- wait for motor spin up time (1sec)
                  f011_busy <= '1';
                  f011_rnf <= '1';    -- Set according to the specifications
                  busy_countdown <= to_unsigned(16000,16); -- 1 sec spin up time
                when x"00" =>         -- cancel running command (not implemented)
                  f_wgate <= '0';
                  report "Clearing fdc_read_request due to $00 command";
                  fdc_read_request <= '0';
                  fdc_bytes_read <= (others => '0');
                  f011_busy <= '0';
                  sd_state <= Idle;
                when others =>        -- illegal command
                  null;
              end case;

            when "00100" =>
              -- @IO:C65 $D084 - F011 FDC track
              f011_track <= fastio_wdata;

            when "00101" =>
              -- @IO:C65 $D085 - F011 FDC sector
              f011_sector <= fastio_wdata;

            when "00110" =>
              -- @IO:C65 $D086 - F011 FDC side
              f011_side <= fastio_wdata;

            when "00111" =>
              -- @IO:C65 $D087 - F011 FDC data register (read/write)
              if last_was_d087='0' then
                report "$D087 write : trigger sector buffer write of $" & to_hstring(fastio_wdata);
                sb_cpu_write_request <= '1';
                sb_cpu_wdata <= fastio_wdata;
                f011_drq <= '0';                         
              end if;
              last_was_d087<='1';
              f011_eq_inhibit <= '0';

            when "01000" =>
              f011_reg_clock <= fastio_wdata;
            when "01001" =>
              f011_reg_step <= fastio_wdata;
            when "01010" =>
              -- P Code: Read only
              null;
              
            when others => null;

          end case;
          -- ================================================================== END
          -- the section above was for the F011
          -- ==================================================================


        elsif sdcardio_cs='1' then
          -- ================================================================== START
          -- the section below is for the SDcard
          -- ==================================================================

          -- microSD controller registers
          case fastio_addr(7 downto 0) is

            -- @IO:GS $D680 - SD controller status/command
            when x"80" =>
              -- status / command register
              case fastio_wdata is
                when x"00" =>
                  -- Reset SD card
                  sd_reset <= '1';
                  sd_state <= Idle;
                  sdio_error <= '0';
                  sdio_fsm_error <= '0';
                  -- Remember to tell SDHC card if we support high capacity
                  sd_sector <= (30 => sdhc_mode, others => '0');

                when x"10" =>
                  -- Reset SD card with flags specified
                  sd_reset <= '1';
                  sd_state <= Idle;
                  sdio_error <= '0';
                  sdio_fsm_error <= '0';

                when x"01" =>
                  -- End reset
                  sd_reset <= '0';
                  sd_state <= Idle;
                  sdio_error <= '0';
                  sdio_fsm_error <= '0';

                when x"11" =>
                  -- End reset
                  sd_reset <= '0';
                  sd_state <= Idle;
                  sdio_error <= '0';
                  sdio_fsm_error <= '0';

                when x"02" =>
                  -- Read sector
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
                  if sdio_busy='1' then
                    report "SDWRITE: sdio_busy is set, not writing";
                    sdio_error <= '1';
                    sdio_fsm_error <= '1';
                  else
                    report "SDWRITE: Commencing write";
                    sd_state <= WriteSector;
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';

                    sd_wrote_byte <= '0';
                    f011_buffer_read_address <= "111"&"000000000";
                    sd_buffer_offset <= (others => '0');
                  end if;

                when x"40" => sdhc_mode <= '0';
                when x"41" => sdhc_mode <= '1';
                when x"42" => half_speed <= '0';
                when x"43" => half_speed <= '1';

                when x"81" => sector_buffer_mapped<='1';
                              sdio_error <= '0';
                              sdio_fsm_error <= '0';

                when x"82" => sector_buffer_mapped<='0';
                              sdio_error <= '0';
                              sdio_fsm_error <= '0';

                when others =>
                  sdio_error <= '1';
              end case;

            when x"81" =>
              -- @IO:GS $D681-$D684 - SD controller SD sector address
              sd_sector(7 downto 0) <= fastio_wdata;
            when x"82" => sd_sector(15 downto 8) <= fastio_wdata;
            when x"83" => sd_sector(23 downto 16) <= fastio_wdata;
            when x"84" => sd_sector(31 downto 24) <= fastio_wdata;
            when x"89" => f011sd_buffer_select <= fastio_wdata(7);

                          -- ================================================================== END
                          -- the section above was for the SDcard
                          -- ==================================================================

                          -- ================================================================== START
                          -- the section below is for OTHER I/O
                          -- ==================================================================

            -- @IO:GS $D68B - F011 emulation control register
            when x"8b" =>
              -- @IO:GS $D68B.5 - F011 disk 2 write protect
              f011_disk2_write_protected <= not fastio_wdata(5);
              -- @IO:GS $D68B.4 - F011 disk 2 present
              f011_disk2_present <= fastio_wdata(4);
              -- @IO:GS $D68B.3 - F011 disk 2 disk image enable
              diskimage2_enable <= fastio_wdata(3);
              
              -- @IO:GS $D68B.2 - F011 disk 1 write protect
              f011_write_protected <= not fastio_wdata(2);                
              -- @IO:GS $D68B.1 - F011 disk 1 present
              f011_disk1_present <= fastio_wdata(1);
              -- @IO:GS $D68B.0 - F011 disk 1 disk image enable
              diskimage1_enable <= fastio_wdata(0);
              report "writing $" & to_hstring(fastio_wdata) & " to FDC control";

            -- @IO:GS $D68C-$D68F - F011 disk 1 disk image address on SD card
            when x"8c" => diskimage_sector(7 downto 0) <= fastio_wdata;
            when x"8d" => diskimage_sector(15 downto 8) <= fastio_wdata;
            when x"8e" => diskimage_sector(23 downto 16) <= fastio_wdata;
            when x"8f" => diskimage_sector(31 downto 24) <= fastio_wdata;

            -- @IO:GS $D690-$D693 - F011 disk 2 disk image address on SD card
            when x"90" => diskimage2_sector(7 downto 0) <= fastio_wdata;
            when x"91" => diskimage2_sector(15 downto 8) <= fastio_wdata;
            when x"92" => diskimage2_sector(23 downto 16) <= fastio_wdata;
            when x"93" => diskimage2_sector(31 downto 24) <= fastio_wdata;

            when x"a0" =>
              -- @IO:GS $D6A0 - 3.5" FDC control line debug access
              f_density <= fastio_wdata(7);
              f_motor <= fastio_wdata(6);
              f_select <= fastio_wdata(5);
              f_stepdir <= fastio_wdata(4);
              f_step <= fastio_wdata(3);
              f_wdata <= fastio_wdata(2);
              f_wgate <= fastio_wdata(1);
              f_side1 <= fastio_wdata(0);
            when x"a1" =>
              use_real_floppy <= fastio_wdata(0);
              target_any <= fastio_wdata(1);
            when x"a2" =>
              cycles_per_interval <= fastio_wdata;
              -- @IO:GS $D6F3 - Accelerometer bit-bashing port
            when x"af" =>
              -- @IO:GS $D6AF - Directly set F011 flags (intended for virtual F011 mode) WRITE ONLY
              -- @IO:GS $D6AF.0 - f011_rsector_found
              -- @IO:GS $D6AF.1 - f011_wsector_found
              -- @IO:GS $D6AF.2 - f011_eq_inhibit
              -- @IO:GS $D6AF.3 - f011_rnf
              -- @IO:GS $D6AF.4 - f011_drq
              -- @IO:GS $D6AF.5 - f011_lost
              f011_rsector_found <= fastio_wdata(0);
              f011_wsector_found <= fastio_wdata(1);
              f011_eq_inhibit <= fastio_wdata(2);
              f011_rnf <= fastio_wdata(3);
              f011_drq <= fastio_wdata(4);
              f011_lost <= fastio_wdata(5);
            when x"F3" =>
              -- Accelerometer
              aclMOSI         <= fastio_wdata(1);
              aclMOSIinternal <= fastio_wdata(1);
              aclSS           <= fastio_wdata(2);
              aclSSinternal   <= fastio_wdata(2);
              aclSCK          <= fastio_wdata(3);
              aclSCKinternal  <= fastio_wdata(3);

            -- @IO:GS $D6F5 - Temperature sensor
            when x"F5" =>
              tmpSDAinternal <= fastio_wdata(0);
              tmpSDA         <= fastio_wdata(0);
              tmpSCLinternal <= fastio_wdata(1);
              tmpSCL         <= fastio_wdata(1);

            -- @IO:GS $D6F8 - 8-bit digital audio out (left)
            when x"F8" =>
              -- 8-bit digital audio out
              pwm_value_new_left <= fastio_wdata;

            when x"F9" =>
              -- @IO:GS $D6F9.0 - Enable audio amplifier
              -- @IO:GS $D6F9.1-4 - Raw PCM/PDM audio debug interface WILL BE REMOVED
              -- @IO:GS $D6F9.5 - Swap stereo channels
              -- @IO:GS $D6F9.6 - Play mono audio through both channels
              -- @IO:GS $D6F9.7 - Select PDM or PWM audio output mode
              -- enable/disable audio amplifiers
              ampSD <= fastio_wdata(0);
              ampSD_internal <= fastio_wdata(0);
              stereo_swap <= fastio_wdata(5);
              force_mono <= fastio_wdata(6);
              audio_mode <= fastio_wdata(7);

            when x"FA" =>
              -- @IO:GS $D6FA - 8-bit digital audio out (left)
              -- 8-bit digital audio out
              pwm_value_new_right <= fastio_wdata;

            when x"FF" =>
              -- @IO:GS $D6FF - Flash bit-bashing port
              -- Flash interface
              if fastio_wdata(0)='0' then
                QspiDB(0) <= '0';
              else
                QspiDB(0) <= 'Z';
              end if;
              if fastio_wdata(1)='0' then
                QspiDB(1) <= '0';
              else
                QspiDB(1) <= 'Z';
              end if;
              if fastio_wdata(2)='0' then
                QspiDB(2) <= '0';
              else
                QspiDB(2) <= 'Z';
              end if;
              if fastio_wdata(3)='0' then
                QspiDB(3) <= '0';
              else
                QspiDB(3) <= 'Z';
              end if;

              -- XXX We should protect CS so that we can prevent use of the flash
              -- if we want.  As it is a malicious program could reprogram or
              -- mess up the configuration flash.
              QspiCSn <= fastio_wdata(6);
              QspiCSnInternal <= fastio_wdata(6);
              QspiSCK <= fastio_wdata(7);
              QspiSCKInternal <= fastio_wdata(7);
            when others => null;

                           -- ================================================================== END
                           -- the section above was for OTHER I/O
                           -- ==================================================================

          end case;

        end if; --     if (fastio_addr(19 downto ...

      end if; --    if fastio_write='1' then

      case sd_state is
        
        when Idle =>
          sdio_busy <= '0';
          hyper_trap_f011_read <= '0';
          hyper_trap_f011_write <= '0';

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
            skip <= 2;
            read_data_byte <= '0';
          else
            sd_doread <= '0';
          end if;

        when ReadingSector =>
          if sd_data_ready='1' then
            sd_doread <= '0';
            -- A byte is ready to read, so store it
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
              if skip=2 then
                sd_datatoken <= unsigned(sd_rdata);
              end if;
              skip <= skip - 1;
            end if;
            sd_state <= ReadingSectorAckByte;
          end if;

        when ReadingSectorAckByte =>
          -- Wait until controller acknowledges that we have acked it
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

        when FDCReadingSector =>
          if fdc_read_request='1' then
            -- We have an FDC request in progress.
--        report "fdc_read_request asserted, checking for activity";
            last_f_index <= f_index;
            if (f_index='0' and last_f_index='1') and (fdc_sector_found='0') then
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
                -- Failed to read sector
                f011_crc <= '1';
                report "Clearing fdc_read_request due to crc error";
                fdc_read_request <= '0';
                fdc_bytes_read(0) <= '1';
                f011_busy <= '0';
                sd_state <= Idle;
              end if;
              -- Clear read request only at the end of the sector we are looking for
              if fdc_sector_end='1' and f011_rsector_found='1' then
                report "Clearing fdc_read_request due end of target sector";
                fdc_read_request <= '0';
                fdc_bytes_read(1) <= '1';
                f011_busy <= '0';
                sd_state <= Idle;
              end if;
            end if;
          end if;          
          
        when F011WriteSector =>
          -- Sit out the wait state for reading the next sector buffer byte
          -- as we copy the F011 sector buffer to the primary SD card sector buffer.
          report "Starting to write sector from unified FDC/SD buffer.";
          f011_buffer_cpu_address <= (others => '0');
          sb_cpu_read_request <= '1';
          f011_buffer_read_address <= "110"&f011_buffer_disk_address;
          f011_buffer_disk_pointer_advance <= '1';
          -- Abort CPU buffer read if in progess, since we are reading the buffer
          sb_cpu_reading <= '0';
          
          sd_state <= WriteSector;
        when WriteSector =>
          -- Begin writing a sector into the buffer
          if sdio_busy='0' then
            report "SDWRITE: Busy flag clear; writing value $" & to_hstring(f011_buffer_rdata);
            sd_dowrite <= '1';
            sdio_busy <= '1';
            skip <= 0;
            sd_wrote_byte <= '0';
            sd_state <= WritingSector;
            sd_wdata <= f011_buffer_rdata;
          else
            report "SDWRITE: Waiting for busy flag to clear...";
            sd_dowrite <= '0';
          end if;

        when WritingSector =>
          if sd_data_ready='1' then
            sd_dowrite <= '0';
            sd_wdata <= f011_buffer_rdata;
            
            report "SDWRITE: skip = " & integer'image(skip)
              & ", sd_buffer_offset=$" & to_hstring(sd_buffer_offset)
              & ", sd_wrote_byte=" & std_logic'image(sd_wrote_byte);
            if skip = 0 then
              -- Byte has been accepted, write next one
              sd_state <= WritingSectorAckByte;

              f011_buffer_disk_pointer_advance <= '1';
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
            if sd_buffer_offset = "000000000" and sd_wrote_byte='1' then
              -- Whole sector written when we have written 512 bytes
              sd_state <= DoneWritingSector;
            else
              -- Still more bytes to read.
              sd_state <= WritingSector;

              -- Get next byte ready
              if f011_sector_fetch='1' then
                f011_buffer_read_address <= "110"&f011_buffer_disk_address;
              else
                f011_buffer_read_address <= "111"&sd_buffer_offset;
              end if;
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
      end case;    

    end if;
  end process;

end behavioural;

