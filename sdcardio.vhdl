use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity sdcardio is
  port (
    clock : in std_logic;
    reset : in std_logic;

    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr : in unsigned(19 downto 0);
    fastio_write : in std_logic;
    fastio_read : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0);

    colourram_at_dc00 : in std_logic;

    -------------------------------------------------------------------------
    -- Lines for the SDcard interface itself
    -------------------------------------------------------------------------
    cs_bo : out std_logic;
    sclk_o : out std_logic;
    mosi_o : out std_logic;
    miso_i : in  std_logic
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

  signal skip : integer range 0 to 2;
  signal read_bytes : std_logic;
  signal sd_doread       : std_logic := '0';
  signal sd_dowrite      : std_logic := '0';
  signal data_ready : std_logic := '0';
  
  signal sd_sector       : std_logic_vector(31 downto 0) := (others => '0');
  signal sd_datatoken    : unsigned(7 downto 0);
  signal sd_rdata        : std_logic_vector(7 downto 0);
  signal sd_wdata        : std_logic_vector(7 downto 0) := (others => '0');
  signal sd_busy         : std_logic;   -- busy line from SD card itself
  signal sd_error        : std_logic;
  signal sd_errorcode    : std_logic_vector(15 downto 0);
  signal sd_reset        : std_logic := '1';
  signal sdhc_mode : std_logic := '0';
  
  -- IO mapped register to indicate if SD card interface is busy
  signal sdio_busy : std_logic := '0';
  signal sdio_error : std_logic := '0';
  signal sdio_fsm_error : std_logic := '0';

  -- 512 byte sector buffer
  type sector_buffer_t is array (0 to 511) of unsigned(7 downto 0);
  signal sector_buffer : sector_buffer_t;
  signal sector_buffer_mapped : std_logic := '0';

  -- Counter for reading/writing sector
  signal sector_offset : unsigned(8 downto 0);

  type sd_state_t is (Idle,
                      ReadSector,ReadingSector,ReadingSectorAckByte,DoneReadingSector,
                      WriteSector,WritingSector,WritingSectorAckByte,
                      DoneWritingSector);
  signal sd_state : sd_state_t := Idle;

  -- F011 FDC emulation registers and flags
  signal f011_track : unsigned(7 downto 0) := x"00";
  signal f011_sector : unsigned(7 downto 0) := x"00";
  signal f011_side : unsigned(7 downto 0) := x"00";
  signal f011_buffer_last_written : unsigned(8 downto 0) := (others => '0');
  signal f011_buffer_last_read : unsigned(8 downto 0) := (others => '0');
  signal f011_flag_eq : std_logic := '1';
  
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

        sector_number => sd_sector,
        sdhc_mode => sdhc_mode,
	rd =>  sd_doread,
	wr =>  sd_dowrite,
	dm_in => '1',	-- data mode, 0 = write continuously, 1 = write single block
	reset => sd_reset,
        data_ready => data_ready,
	din => sd_wdata,
	dout => sd_rdata,
	clk => clock	-- twice the SPI clk.  XXX Cannot exceed 50MHz
);

  
  -- XXX also implement F1011 floppy controller emulation.
  process (clock,fastio_addr,fastio_wdata,sector_buffer_mapped,sdio_busy,
           sd_reset,fastio_read,sd_sector,fastio_write,
           f011_track,f011_sector,f011_side,sdio_fsm_error,sdio_error,
           sd_errorcode,sd_state,sector_buffer) is
  begin

    if rising_edge(clock) then

      -- De-map sector buffer if VIC-IV maps colour RAM at $DC00
      sector_buffer_mapped <= sector_buffer_mapped and (not colourram_at_dc00);
      
      fastio_rdata <= (others => 'Z');

      if  fastio_read='0' and fastio_write='1' then
        if fastio_write='1' then
          if (fastio_addr(19 downto 5)&'0' = x"D108")
            or (fastio_addr(19 downto 5)&'0' = x"D308") then
            -- F011 FDC emulation registers
            case "000"&fastio_addr(4 downto 0) is
              when x"00" =>
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
                null;
              when x"01" =>
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
                --           fastio_rdata <= (others => 'Z');
                null;
              when x"04" => f011_track <= fastio_wdata;
              when x"05" => f011_sector <= fastio_wdata;
              when x"06" => f011_side <= fastio_wdata;
              when x"07" =>
                -- Data register -- should probably be putting byte into the sector
                -- buffer.
              when others => null;           
            end case;
          elsif (fastio_addr(19 downto 4) = x"D168"
                 or fastio_addr(19 downto 4) = x"D368") then
            -- microSD controller registers
            case fastio_addr(3 downto 0) is
              when x"0" =>
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
                  when x"41" => sdhc_mode <= '1';
                  when x"42" => sdhc_mode <= '0';
                  when x"81" => sector_buffer_mapped<='1';
                                sdio_error <= '0';
                                sdio_fsm_error <= '0';
                  when x"82" => sector_buffer_mapped<='0';
                                sdio_error <= '0';
                                sdio_fsm_error <= '0';
                  when others =>
                    sdio_error <= '1';
                end case;
              when x"1" => sd_sector(7 downto 0) <= std_logic_vector(fastio_wdata);
              when x"2" => sd_sector(15 downto 8) <= std_logic_vector(fastio_wdata);
              when x"3" => sd_sector(23 downto 16) <= std_logic_vector(fastio_wdata);
              when x"4" => sd_sector(31 downto 24) <= std_logic_vector(fastio_wdata);
              when others => null;
            end case;
          elsif (sector_buffer_mapped='1') and
            ((fastio_addr(19 downto 9)&'0' = x"D1E")
             or (fastio_addr(19 downto 9)&'0' = x"D3E")) then
            -- Map sector buffer at $DE00-$DFFF when required
            if fastio_read='0' and fastio_write='1' and sdio_busy='0' then
              sector_buffer(to_integer(fastio_addr(8 downto 0))) <= fastio_wdata;
            end if;
          end if;
        end if;
      end if;
      
      if fastio_read='1' and fastio_write='0' then
        if (fastio_addr(19 downto 5)&'0' = x"D108")
          or (fastio_addr(19 downto 5)&'0' = x"D308") then
          -- F011 FDC emulation registers
          case "000"&fastio_addr(4 downto 0) is
            when x"00" =>
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
              fastio_rdata <= (others => 'Z');
            when x"01" =>
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
              --           fastio_rdata <= (others => 'Z');
              case fastio_wdata is
                when x"01" =>
                  -- Clear buffer pointers
                  f011_buffer_last_written <= (others => '0');
                  f011_buffer_last_read <= (others => '0');
                  f011_flag_eq <= '1';
                when x"40" =>
                  -- Read sector
                  null;
                when x"80" =>
                  -- Write sector
                  null;
                when others => null;
              end case;
            when x"02" =>
              -- STAT A  | BUSY  |  DRQ  |  EQ   |  RNF  |  CRC  | LOST  | PROT  |  TKQ  | 2 R
              --BUSY    command is being executed
              --DRQ     disk interface has transferred a byte
              --EQ      buffer CPU/Disk pointers are equal
              --RNF     sector not found during formatted write or read
              --CRC     CRC check failed
              --LOST    data was lost during transfer
              --PROT    disk is write protected
              --TK0     head is positioned over track zero

              fastio_rdata <= (others => 'Z');
            when x"03" =>
              -- STAT B  | RDREQ | WTREQ |  RUN  | NGATE | DSKIN | INDEX |  IRQ  | DSKCHG| 3 R
              -- RDREQ   sector found during formatted read
              -- WTREQ   sector found during formatted write
              -- RUN     indicates successive matches during find operation
              -- WGATE   write gate is on
              -- DSKIN   indicates that a disk is inserted in the drive
              -- INDEX   disk index is currently over sensor
              -- IRQ     an interrupt has occurred
              -- DSKCHG  the DSKIN line has changed
              --         this is cleared by deselecting drive
              fastio_rdata <= (others => 'Z');
            when x"04" =>
              -- TRACK   |  T7   |  T6   |  T5   |  T4   |  T3   |  T2   |  T1   |  T0   | 4 RW
              fastio_rdata <= f011_track;
            when x"05" =>
              -- SECTOR  |  S7   |  S6   |  S5   |  S4   |  S3   |  S2   |  S1   |  S0   | 5 RW
              fastio_rdata <= f011_sector;
            when x"06" =>
              -- SIDE    |  S7   |  S6   |  S5   |  S4   |  S3   |  S2   |  S1   |  S0   | 6 RW
              fastio_rdata <= f011_side;
            when x"07" =>
              -- DATA    |  D7   |  D6   |  D5   |  D4   |  D3   |  D2   |  D1   |  D0   | 7 RW
              fastio_rdata <= (others => 'Z');
            when x"08" =>
              -- CLOCK   |  C7   |  C6   |  C5   |  C4   |  C3   |  C2   |  C1   |  C0   | 8 RW
              fastio_rdata <= (others => 'Z');
            when x"09" =>
              -- STEP    |  S7   |  S6   |  S5   |  S4   |  S3   |  S2   |  S1   |  S0   | 9 RW
              fastio_rdata <= (others => 'Z');
            when x"0a" =>
              -- P CODE  |  P7   |  P6   |  P5   |  P4   |  P3   |  P2   |  P1   |  P0   | A R
              fastio_rdata <= (others => 'Z');
            when others =>
              fastio_rdata <= (others => 'Z');
          end case;
        elsif (fastio_addr(19 downto 4) = x"D168"
               or fastio_addr(19 downto 4) = x"D368") then
          -- microSD controller registers
          case fastio_addr(3 downto 0) is
            when x"0" =>
              -- status / command register
              -- error status in bit 6 so that V flag can be used for check      
              fastio_rdata(7) <= '0';
              fastio_rdata(6) <= sdio_error;
              fastio_rdata(5) <= sdio_fsm_error;
              fastio_rdata(4) <= '0';
              fastio_rdata(3) <= sector_buffer_mapped;
              fastio_rdata(2) <= sd_reset;
              fastio_rdata(1) <= sdio_busy;
              fastio_rdata(0) <= sdio_busy;
            when x"1" => fastio_rdata <= unsigned(sd_sector(7 downto 0));
            when x"2" => fastio_rdata <= unsigned(sd_sector(15 downto 8));
            when x"3" => fastio_rdata <= unsigned(sd_sector(23 downto 16));
            when x"4" => fastio_rdata <= unsigned(sd_sector(31 downto 24));        
            when x"5" => fastio_rdata <= unsigned(sd_errorcode(7 downto 0));        
            when x"6" => fastio_rdata <= unsigned(sd_errorcode(15 downto 8));
            when x"7" => fastio_rdata <= to_unsigned(sd_state_t'pos(sd_state),8);
            when x"8" => fastio_rdata <= sd_datatoken;
            when x"9" => fastio_rdata <= unsigned(sd_rdata);                         
            when x"a" => fastio_rdata <= sector_offset(7 downto 0);
            when x"b" =>
              fastio_rdata(7 downto 1) <= (others => '0');
              fastio_rdata(0) <= sector_offset(8);
            when others => fastio_rdata <= (others => 'Z');
          end case;
        elsif (sector_buffer_mapped='1') and 
          ((fastio_addr(19 downto 9)&'0' = x"D1E")
           or (fastio_addr(19 downto 9)&'0' = x"D3E")) then
          -- Map sector buffer at $DE00-$DFFF when required
          if fastio_read='1' and fastio_write='0' and sdio_busy='0' then
            fastio_rdata <= sector_buffer(to_integer(fastio_addr(8 downto 0)));
          end if;
        else
          -- Otherwise tristate output
          fastio_rdata <= (others => 'Z');
        end if;
      end if;
      
--      if (fastio_read='0') and (fastio_write='0') then
        case sd_state is
          when Idle => sdio_busy <= '0';
          when ReadSector =>
            -- Begin reading a sector into the buffer
            if sd_busy='0' then
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
              sector_buffer(to_integer(sector_offset)) <= unsigned(sd_rdata);
              sd_state <= ReadingSectorAckByte;
              if skip=0 then
                sector_offset <= sector_offset + 1;
                read_bytes <= '1';
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
              if (sector_offset = "000000000") and (read_bytes='1') then
                -- sector offset has wrapped back to zero, so we must have
                -- read the whole sector.
                sd_state <= DoneReadingSector;
              else
                -- Still more bytes to read.
                sd_state <= ReadingSector;
              end if;
            end if;
          when WriteSector =>
            -- Begin writing a sector into the buffer
            if sd_busy='0' then
              sd_dowrite <= '1';
              sdio_busy <= '1';
              sd_state <= WritingSector;
              sector_offset <= (others => '0');
              sd_wdata <= std_logic_vector(sector_buffer(0));
            else
              sd_dowrite <= '0';
            end if;
          when WritingSector =>
            if data_ready='1' then
              sd_dowrite <= '0';
              -- Byte has been accepted, write next one
              sd_wdata <= std_logic_vector(sector_buffer(to_integer(sector_offset+1)));
              sd_state <= WritingSectorAckByte;
              sector_offset <= sector_offset + 1;
            end if;
          when WritingSectorAckByte =>
            -- Wait until controller acknowledges that we have acked it
            if data_ready='0' then
              if sector_offset = "000000000" then
                -- sector offset has wrapped back to zero, so we must have
                -- read the whole sector.
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
        end case;    
--      end if;

    end if;
  end process;

end behavioural;
