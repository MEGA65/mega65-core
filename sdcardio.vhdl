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

    fpga_temperature : in std_logic_vector(11 downto 0);
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : in unsigned(19 downto 0);
    fastio_write : in std_logic;
    fastio_read : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0);

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
  
  component sd_controller is
    port (
        cs : out std_logic;
        mosi : out std_logic;
        miso : in std_logic;
        sclk : out std_logic;

        sector_number : in std_logic_vector(31 downto 0);  -- sector number requested
        sdhc_mode : in std_logic;
        half_speed : in std_logic;
        rd : in std_logic;
        wr : in std_logic;
        dm_in : in std_logic;   -- data mode, 0 = write continuously, 1 = write single block
        reset : in std_logic;
        data_ready : out std_logic;     -- 1= data written, or data accepted,
                                        -- 0= wait for data, or pre-load data
                                        -- for writing
        din : in std_logic_vector(7 downto 0);
        dout : out std_logic_vector(7 downto 0);
        clk : in std_logic      -- twice the SPI clk
        );
  end component;

  component ram8x512 IS
  PORT (
    clk : IN STD_LOGIC;
    cs : IN STD_LOGIC;
    w : IN std_logic;
    write_address : IN integer range 0 to 511;
    wdata : IN unsigned(7 DOWNTO 0);
    address : IN integer range 0 to 511;
    rdata : OUT unsigned(7 DOWNTO 0)
    );
  END component;

  signal QspiSCKInternal : std_logic := '1';
  signal QspiCSnInternal : std_logic := '1'; 
  
  signal aclMOSIinternal : std_logic := '0';
  signal aclSSinternal : std_logic := '0';
  signal aclSCKinternal : std_logic := '0';
  signal micClkinternal : std_logic := '0';
  signal micLRSelinternal : std_logic := '0';
  signal tmpSDAinternal : std_logic := '0';
  signal tmpSCLinternal : std_logic := '0';

  signal pwm_value_new_left : unsigned(7 downto 0) := x"00";
  signal pwm_value_new_right : unsigned(7 downto 0) := x"00";
  signal pwm_value_combined : unsigned(9 downto 0) := "0000000000";
  signal pwm_value : unsigned(9 downto 0) := "0000000000";
  signal pwm_phase : unsigned(9 downto 0) := "0000000000";

  signal mic_divider : unsigned(4 downto 0) := "00000";
  signal mic_counter : unsigned(7 downto 0) := "00000000";
  signal mic_onecount : unsigned(7 downto 0) := "00000000";
  signal mic_value_left : unsigned(7 downto 0) := "00000000";
  signal mic_value_right : unsigned(7 downto 0) := "00000000";
  
  -- debounce reading from or writing to $D087 so that buffered read/write
  -- behaves itself.
  signal last_was_d087 : std_logic := '0';
  
  signal skip : integer range 0 to 2;
  signal read_bytes : std_logic;
  signal sd_doread       : std_logic := '0';
  signal sd_dowrite      : std_logic := '0';
  signal data_ready : std_logic := '0';

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
  
  -- Signals for sector buffers (both SD and CPU side)
  signal sb_w : std_logic := '0';
  signal sb_wdata : unsigned(7 downto 0);
  -- Counter for reading/writing sector
  signal sector_offset : unsigned(9 downto 0);
  signal sb_writeaddress : integer range 0 to 511 := 0;
  
  type sd_state_t is (Idle,
                      ReadSector,ReadingSector,ReadingSectorAckByte,DoneReadingSector,
                      WriteSector,WritingSector,WritingSectorAckByte,
                      F011WriteSector,F011WriteSectorCopying,
                      DoneWritingSector);
  signal sd_state : sd_state_t := Idle;

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
  signal f011_sector_fetch : std_logic := '0';

  signal f011_buffer_address : unsigned(8 downto 0) := (others => '0');
  signal f011_buffer_next_read : unsigned(8 downto 0) := (others => '0');
  signal f011_buffer_wdata : unsigned(7 downto 0);
  signal f011_buffer_rdata : unsigned(7 downto 0);
  signal f011_flag_eq : std_logic := '1';
  signal f011_swap : std_logic := '0';
  signal f011_rdata : unsigned(7 downto 0);
  signal f011_buffer_write : std_logic := '0';
  signal f011_wdata : unsigned(7 downto 0);

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

begin  -- behavioural

  --**********************************************************************
  -- SD card controller module.
  --**********************************************************************
  
  sd0: sd_controller 
    port map (
	cs => cs_bo,
	mosi => mosi_o,
	miso => miso_i,
	sclk => sclk_o,

        sector_number => std_logic_vector(sd_sector),
        sdhc_mode => sdhc_mode,
        half_speed => half_speed,
	rd =>  sd_doread,
	wr =>  sd_dowrite,
	dm_in => '1',	-- data mode, 0 = write continuously, 1 = write single block
	reset => sd_reset,
        data_ready => data_ready,
	din => std_logic_vector(sd_wdata),
	unsigned(dout) => sd_rdata,
	clk => clock	-- twice the SPI clk.  XXX Cannot exceed 50MHz
        );

  sdsectorbuffer0: ram8x512
    port map (
      clk => clock,

      -- CPU side read access
      cs => sectorbuffercs,
      address => to_integer(fastio_addr(8 downto 0)),
      rdata => fastio_rdata,

      -- Write side controlled by SD-card side.
      -- (CPU side effects writes by asking SD-card side to write)
      w => sb_w,
      write_address => sb_writeaddress,
      wdata => sb_wdata
      );

  sdsectorbuffer1: ram8x512
    port map (
      clk => clock,

      -- SD-card side read access (for writing sectors to SD card)
      cs => '1',
      address => to_integer(sector_offset),
      rdata => sd_wdata,

      -- Write side controlled by SD-card side.
      -- (CPU side effects writes by asking SD-card side to write)
      w => sb_w,
      write_address => sb_writeaddress,
      wdata => sb_wdata
      );

  f011sectorbuffer: ram8x512
    port map (
      clk => clock,

      cs => '1',
      address => to_integer(f011_buffer_next_read),
      rdata => f011_buffer_rdata,

      -- Write side controlled by SD-card side.
      -- (CPU side effects writes by asking SD-card side to write)
      w => f011_buffer_write,
      write_address => to_integer(f011_buffer_address),
      wdata => f011_buffer_wdata
      );

  
  -- XXX also implement F1011 floppy controller emulation.
  process (clock,fastio_addr,fastio_wdata,sector_buffer_mapped,sdio_busy,
           sd_reset,fastio_read,sd_sector,fastio_write,
           f011_track,f011_sector,f011_side,sdio_fsm_error,sdio_error,
           sd_state,f011_irqenable,f011_ds,f011_cmd,f011_busy,f011_crc,
           f011_track0,f011_rsector_found,f011_over_index,f011_rdata,
           f011_buffer_next_read,sdhc_mode,half_speed,sd_datatoken,sd_rdata,
           sector_offset,diskimage1_enable,f011_disk1_present,
           f011_disk1_write_protected,diskimage2_enable,f011_disk2_present,
           f011_disk2_write_protected,diskimage_sector,sw,btn,aclmiso,
           aclmosiinternal,aclssinternal,aclSCKinternal,aclint1,aclint2,
           tmpsdainternal,tmpsclinternal,tmpint,tmpct,tmpint,last_scan_code,
           pwm_value_new_left,mic_value_left,mic_value_right,qspidb,
           qspicsninternal,QspiSCKInternal          
           ) is
    variable temp_cmd : unsigned(7 downto 0);
  begin

    if fastio_read='1' and sectorbuffercs='0' then
      if (fastio_addr(19 downto 5)&'0' = x"D108")
        or (fastio_addr(19 downto 5)&'0' = x"D308") then
        -- F011 FDC emulation registers
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
              f011_side(0) & f011_ds;
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
          when "00111" =>
            -- DATA    |  D7   |  D6   |  D5   |  D4   |  D3   |  D2   |  D1   |  D0   | 7 RW
            fastio_rdata <= f011_buffer_rdata;
          when "01000" =>
            -- CLOCK   |  C7   |  C6   |  C5   |  C4   |  C3   |  C2   |  C1   |  C0   | 8 RW
            fastio_rdata <= (others => 'Z');
          when "01001" =>
            -- STEP    |  S7   |  S6   |  S5   |  S4   |  S3   |  S2   |  S1   |  S0   | 9 RW
            fastio_rdata <= (others => 'Z');
          when "01010" =>
            -- P CODE  |  P7   |  P6   |  P5   |  P4   |  P3   |  P2   |  P1   |  P0   | A R
            fastio_rdata <= (others => 'Z');
            
          when "11110" => -- Extra: $D09E = read buffer pointer low bits
            fastio_rdata <= f011_buffer_next_read(7 downto 0);
          when "11111" => -- Extra: $D09F = read buffer pointer high bit
            fastio_rdata(0) <= f011_buffer_next_read(8);
            fastio_rdata(7 downto 1) <= (others => '0');
          when others =>
            fastio_rdata <= (others => 'Z');
        end case;
      elsif (fastio_addr(19 downto 8) = x"D16"
             or fastio_addr(19 downto 8) = x"D36") then
        -- microSD controller registers
        report "reading SDCARD registers" severity note;
        case fastio_addr(7 downto 0) is
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
            fastio_rdata(1) <= sdio_busy;
            fastio_rdata(0) <= sdio_busy;
          when x"81" => fastio_rdata <= sd_sector(7 downto 0);
          when x"82" => fastio_rdata <= sd_sector(15 downto 8);
          when x"83" => fastio_rdata <= sd_sector(23 downto 16);
          when x"84" => fastio_rdata <= sd_sector(31 downto 24);        
          when x"85" => fastio_rdata <= to_unsigned(sd_state_t'pos(sd_state),8);
          when x"86" => fastio_rdata <= sd_datatoken;
          when x"87" => fastio_rdata <= unsigned(sd_rdata);                        
          when x"88" => fastio_rdata <= sector_offset(7 downto 0);
          when x"89" =>
            fastio_rdata(7 downto 1) <= (others => '0');
            fastio_rdata(0) <= sector_offset(8);
            fastio_rdata(1) <= sector_offset(9);
          when x"8b" =>
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
          when x"EE" =>
            -- @IO:GS $D6EE - Temperature sensor (lower byte)
            fastio_rdata <= unsigned("0000"&fpga_temperature(3 downto 0));
          when x"EF" =>
            -- @IO:GS $D6EF - Temperature sensor (upper byte)
            fastio_rdata <= unsigned(fpga_temperature(11 downto 4));
          when x"F0" =>
            -- @IO:GS $D6F0 - Read FPGA switches 0-7
            fastio_rdata(7 downto 0) <= unsigned(sw(7 downto 0));
          when x"F1" =>
            -- @IO:GS $D6F1 - Read FPGA switches 8-15
            fastio_rdata(7 downto 0) <= unsigned(sw(15 downto 8));
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

    
    if rising_edge(clock) then

      -- Advance f011 buffer position when reading from data register
      last_was_d087 <= '0';
      if fastio_read='1' then
        if (fastio_addr(19 downto 0) = x"D1087"
            or fastio_addr(19 downto 0) = x"D3087") then
          if last_was_d087='0' then
            f011_buffer_next_read <= f011_buffer_next_read + 1;
            f011_drq <= '0';
          end if;
          last_was_d087 <= '1';
        end if;
      end if;
          
      -- Generate combined audio from stereo sids plus 2 8-bit digital channels
      pwm_value_combined <= to_unsigned(to_integer(leftsid_audio(17 downto 10))
                                        + to_integer(rightsid_audio(17 downto 10))
                                        + to_integer(pwm_value_new_left)
                                        + to_integer(pwm_value_new_right),10);
      
      -- Implement 10-bit digital audio output
      pwm_phase <= pwm_phase + 1;
      if pwm_phase = "0000000000" then
        if pwm_value = "0000000000" then
          ampPWM <= '0';
        else
          ampPWM <= '1';
        end if;
      else
        if pwm_value=pwm_phase then
          ampPWM <= '0';
        end if;
        if pwm_phase = "1111111111" then
          pwm_value <= pwm_value_combined;
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
      
      if f011_ds=x"000" then
        f011_write_protected <= f011_disk1_write_protected;
        f011_disk_present <= f011_disk1_present;
      elsif f011_ds=x"001" then
        f011_write_protected <= f011_disk2_write_protected;      
        f011_disk_present <= f011_disk2_present;
      end if;
    
      f011_buffer_write <= '0';
      -- EQ flag is asserted when buffer address matches where we are upto
      -- reading or writing.  On complete reads this should correspond to the
      -- start of the buffer.
      -- XXX This formulation isn't right, as we can't properly signal buffer
      -- full/empty status in a way that the C65 ROM understands for both read
      -- and write.  Nothing seems to work for the write routines.
      if f011_buffer_address = f011_buffer_next_read then
        -- if 1, then reading from disk infinite loops waiting for 0
        f011_flag_eq <= sw(13);
      else
        -- if 1, then something else doesn't work? 
        f011_flag_eq <= sw(12);
      end if;
      f011_buffer_write <= '0';
      if f011_head_track="0000000" then
        f011_track0 <= '1';
      else
        f011_track0 <= '0';
      end if;
      
      -- update diskimage offset
      -- add 1/2 track amount for sectors on the rear
      -- and subtract one since sectors are relative to 1, not 0
      if f011_side/=x"00" then
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
        report "unmapping sector buffer due to mapping of colour ram/D02F mode select" severity note;
        sector_buffer_mapped <= '0';
        sectorbuffermapped <= '0';
        sectorbuffermapped2 <= '0';
      else
        sectorbuffermapped <= sector_buffer_mapped;
        sectorbuffermapped2 <= sector_buffer_mapped;
      end if;
            
      if fastio_write='1' then
        if (fastio_addr(19 downto 5)&'0' = x"D108")
          or (fastio_addr(19 downto 5)&'0' = x"D308") then
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
              f011_swap <= fastio_wdata(4);
              if fastio_wdata(4) /= f011_swap then
                -- switch halves of buffer if swap bit changes
                f011_buffer_next_read(8) <= not f011_buffer_next_read(8);
              end if;
              f011_side(0) <= fastio_wdata(3);
              f011_ds <= fastio_wdata(2 downto 0);
              if fastio_wdata(2 downto 0) /= f011_ds then
                f011_disk_changed <= '0';
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
                f011_buffer_next_read(7 downto 0) <= (others => '0');
                f011_buffer_next_read(8) <= f011_swap;
              end if;
              temp_cmd := fastio_wdata(7 downto 3) & "000";
              case temp_cmd is
                when x"40" =>         -- read sector
                  -- calculate sector number.
                  -- physical sector on disk = track * $14 + sector on track
                  -- then add to disk image start sector for the selected
                  -- drive.
                  -- put sector number into sd_sector, and then trigger read.
                  -- If no disk image is enabled, then report an error.
                  if f011_ds="000" and (diskimage1_enable='0' or f011_disk1_present='0') then
                    f011_rnf <= '1';
                  elsif f011_ds="001" and (diskimage2_enable='0' or f011_disk2_present='0') then
                    f011_rnf <= '1';
                  elsif f011_ds(2 downto 1) /= x"00" then
                    -- only 2 drives supported for now
                    f011_rnf <= '1';
                  else
                    -- f011_buffer_address gets pre-incremented, so start
                    -- with it pointing to the end of the buffer first
                    f011_buffer_address(7 downto 0) <= (others => '1');
                    f011_buffer_address(8) <= '1';
                    f011_sector_fetch <= '1';
                    f011_busy <= '1';
                    if sdhc_mode='1' then
                      sd_sector <= diskimage_sector + diskimage_offset;
                    else
                      sd_sector(31 downto 9) <= diskimage_sector(31 downto 9) +
                                                diskimage_offset;     
                    end if;
                    sd_state <= ReadSector;
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                    
                    -- XXX work around specification error: always reset buffer
                    -- pointers when reading a sector
                    -- reset buffer (but take SWAP into account)
                    f011_buffer_next_read(7 downto 0) <= (others => '0');
                    f011_buffer_next_read(8) <= f011_swap;
                    
                  end if;                    
                when x"80" =>         -- write sector
                  -- Copy sector from F011 buffer to SD buffer, and then
                  -- pretend the SD card registers were used to trigger a write.
                  -- The F011 can in theory do unbuffered sector writes, but
                  -- we don't support them.  The C65 ROM does buffered
                  -- writes, anyway, so it isn't a problem.
                  if f011_ds="000" and (diskimage1_enable='0' or f011_disk1_present='0' or f011_disk1_write_protected='1') then
                    f011_rnf <= '1';
                  elsif f011_ds="001" and (diskimage2_enable='0' or f011_disk2_present='0' or f011_disk2_write_protected='1') then
                    f011_rnf <= '1';
                  elsif f011_ds(2 downto 1) /= x"00" then
                    -- only 2 drives supported for now
                    f011_rnf <= '1';
                  else
                    -- f011_buffer_address gets pre-incremented, so start
                    -- with it pointing to the end of the buffer first
                    f011_sector_fetch <= '1';
                    f011_busy <= '1';
                    -- XXX Doesn't trigger an error for bad track/sector:
                    -- just writes to sector 1599 of the disk image!
                    if sdhc_mode='1' then
                      sd_sector <= diskimage_sector + diskimage_offset;
                    else
                      sd_sector(31 downto 9) <= diskimage_sector(31 downto 9) +
                                                diskimage_offset;     
                    end if;   
                    sd_state <= F011WriteSector;
                    f011_buffer_address <= (others => '0');
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
                  end if;
                when x"10" =>         -- head step out, or no step
                  if fastio_wdata(2)='1' then
                    -- time, but don't step
                    null;
                  else
                    f011_head_track <= f011_head_track - 1;
                  end if;
                when x"18" =>         -- head step in
                  f011_head_track <= f011_head_track + 1;
                when x"20" =>         -- motor spin up
                  f011_motor <= '1';
                when x"00" =>         -- cancel running command (not implemented)
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
              -- @IO:C65 $D085 - F011 FDC data register
              -- Data register -- should probably be putting byte into the sector
              -- buffer.
              if last_was_d087='0' then
                f011_wdata <= fastio_wdata;
                f011_buffer_wdata <= fastio_wdata;
                f011_buffer_write <= '1';
                f011_buffer_next_read <= f011_buffer_next_read + 1;
                f011_drq <= '0';                                    
              end if;
              last_was_d087<='1';
            when others => null;           
          end case;
        elsif (fastio_addr(19 downto 8) = x"D16"
               or fastio_addr(19 downto 8) = x"D36") then
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
                  sd_sector <= (others => '0');
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
                  end if;
                when x"03" =>
                  -- Write sector
                  if sdio_busy='1' then
                    sdio_error <= '1';
                    sdio_fsm_error <= '1';
                  else                  
                    sd_state <= WriteSector;
                    sdio_error <= '0';
                    sdio_fsm_error <= '0';
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
            -- @IO:GS $D6F3 - Accelerometer bit-bashing port
            when x"F3" =>
              -- Accelerometer
              aclMOSI <= fastio_wdata(1);
              aclMOSIinternal <= fastio_wdata(1);
              aclSS <= fastio_wdata(2);
              aclSSinternal <= fastio_wdata(2);
              aclSCK <= fastio_wdata(3);
              aclSCKinternal <= fastio_wdata(3);
            -- @IO:GS $D6F5 - Temperature sensor
            when x"F5" =>
              tmpSDAinternal <= fastio_wdata(0);
              tmpSDA <= fastio_wdata(0);
              tmpSCLinternal <= fastio_wdata(1);
              tmpSCL <= fastio_wdata(1);
            -- @IO:GS $D6F8 - 8-bit digital audio out (left)
            when x"F8" =>
              -- 8-bit digital audio out
              pwm_value_new_left <= fastio_wdata;
            when x"F9" =>
              -- @IO:GS $D6F9.0 - Enable audio amplifier
              -- enable/disable audio amplifiers
              ampSD <= fastio_wdata(0);
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
          end case;
        end if;
      end if;
                
      sb_w <= '0';
      case sd_state is
        when Idle =>
          sdio_busy <= '0';
          -- Allow CPU to write to sector buffers if we are not talking to the
          -- SD card.
          if fastio_write='1' and sectorbuffercs='1' then
            sb_w <= '1';
            report "Writing $" & to_hstring(fastio_wdata) & " to sector buffer $" & to_hstring("000"&fastio_addr(8 downto 0)) severity note;
            sb_wdata <= unsigned(fastio_wdata);
            sb_writeaddress <= to_integer(fastio_addr(8 downto 0));
          else
            sb_w <= '0';
          end if;              
        when ReadSector =>
          -- Begin reading a sector into the buffer
          if sdio_busy='0' then
            sd_doread <= '1';
            sd_state <= ReadingSector;
            sdio_busy <= '1';
            skip <= 2;
            sector_offset <= (others => '0');
            read_bytes <= '0';
          else
            sd_doread <= '0';
          end if;
        when ReadingSector =>
          if data_ready='1' then
            sd_doread <= '0';
            -- A byte is ready to read, so store it
            -- sector_buffer(to_integer(sector_offset)) <= unsigned(sd_rdata);
            sb_w <= '1';
            sb_wdata <= unsigned(sd_rdata);
            sb_writeaddress <= to_integer(sector_offset);
            sd_state <= ReadingSectorAckByte;
            if skip=0 then
              sector_offset <= sector_offset + 1;
              read_bytes <= '1';
              if f011_sector_fetch='1' then
                f011_rsector_found <= '1';
                if f011_drq='1' then f011_lost <= '1'; end if;
                f011_drq <= '1';
                -- Update F011 sector buffer
                f011_buffer_address <= f011_buffer_address + 1;
                f011_buffer_write <= '1';
                f011_buffer_wdata <= unsigned(sd_rdata);
              end if;
            else
              skip <= skip - 1;
              if skip=2 then
                sd_datatoken <= unsigned(sd_rdata);
              end if;
            end if;
          end if;
        when ReadingSectorAckByte =>
          -- Wait until controller acknowledges that we have acked it
          if data_ready='0' then
            if (sector_offset = "1000000000") and (read_bytes='1') then
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
          end if;
        when F011WriteSector =>
          -- Sit out the wait state for reading the next sector buffer byte
          -- as we copy the F011 sector buffer to the primary SD card sector buffer.
          sb_w <= '0';
          f011_buffer_address <= f011_buffer_address;
          sd_state <= F011WriteSectorCopying;
        when F011WriteSectorCopying =>
          -- Write byte to SD sector buffer
          sector_offset <= "0"&f011_buffer_address;
          sb_wdata <= f011_rdata;
          sb_w <= '1';
          if f011_buffer_address /= "111111111" then
            -- Schedule reading of the next byte
            f011_buffer_address <= f011_buffer_address + 1;
            sd_state <= F011WriteSector;
          else
            -- Got all bytes, so proceed to writing sector.
            sd_state <= WriteSector;
          end if;          
        when WriteSector =>
          -- Begin writing a sector into the buffer
          sb_w <= '0';
          if sdio_busy='0' then
            sd_dowrite <= '1';
            sdio_busy <= '1';
            sd_state <= WritingSector;
            sector_offset <= (others => '0');
          else
            sd_dowrite <= '0';
          end if;
        when WritingSector =>
          if data_ready='1' then
            sd_dowrite <= '0';
            -- Byte has been accepted, write next one
            sd_state <= WritingSectorAckByte;
            sector_offset <= sector_offset + 1;
          end if;
        when WritingSectorAckByte =>
          -- Wait until controller acknowledges that we have acked it
          if data_ready='0' then
            if sector_offset = "1000000000" then
              -- sector offset has reached 512, so we have
              -- written the whole sector.
              sd_state <= DoneWritingSector;
            else
              -- Still more bytes to read.
              sd_state <= WritingSector;
            end if;
          end if;
        when DoneReadingSector =>
          sdio_busy <= '0';
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
