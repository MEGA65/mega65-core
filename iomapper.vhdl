use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity iomapper is
  port (Clk : in std_logic;
        pixelclk : in std_logic;
        uartclock : in std_logic;
        phi0 : in std_logic;
        reset : in std_logic;
        reset_out : out std_logic;
        irq : out std_logic;
        nmi : out std_logic;
        restore_nmi : out std_logic;
        address : in std_logic_vector(19 downto 0);
        r : in std_logic;
        w : in std_logic;
        data_i : in std_logic_vector(7 downto 0);
        data_o : out std_logic_vector(7 downto 0);
        sd_data_o : out std_logic_vector(7 downto 0);
        sector_buffer_mapped : out std_logic;

        led : out std_logic := '0';
        motor : out std_logic := '0';

        ps2data : in std_logic;
        ps2clock : in std_logic;

        ----------------------------------------------------------------------
        -- Flash RAM for holding config
        ----------------------------------------------------------------------
        QspiSCK : out std_logic;
        QspiDB : inout std_logic_vector(3 downto 0);
        QspiCSn : out std_logic;        

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
        aclMISO : in std_logic;
        aclMOSI : out std_logic;
        aclSS : out std_logic;
        aclSCK : out std_logic;
        aclInt1 : in std_logic;
        aclInt2 : in std_logic;
    
        micData : in std_logic;
        micClk : out std_logic;
        micLRSel : out std_logic;

        ampPWM : out std_logic;
        ampSD : out std_logic;

        tmpSDA : out std_logic;
        tmpSCL : out std_logic;
        tmpInt : in std_logic;
        tmpCT : in std_logic;
        
        sw : in std_logic_vector(15 downto 0);
        btn : in std_logic_vector(4 downto 0);
        seg_led : out unsigned(31 downto 0);

        viciii_iomode : in std_logic_vector(1 downto 0);
        
        colourram_at_dc00 : in std_logic
        );
end iomapper;

architecture behavioral of iomapper is
  component kickstart is
    port (
      Clk : in std_logic;
      address : in std_logic_vector(12 downto 0);
      we : in std_logic;
      cs : in std_logic;
      data_i : in std_logic_vector(7 downto 0);
      data_o : out std_logic_vector(7 downto 0));
  end component;

  component sid6581 is
    port (
      clk_1MHz			: in  std_logic;		-- main SID clock signal
      clk32				: in  std_logic;		-- main clock signal
      reset				: in  std_logic;		-- high active signal (reset when reset = '1')
      cs					: in  std_logic;		-- "chip select", when this signal is '1' this model can be accessed
      we					: in std_logic;		-- when '1' this model can be written to, otherwise access is considered as read
      
      addr				: in  unsigned(4 downto 0);	-- address lines
      di					: in  unsigned(7 downto 0);	-- data in (to chip)
      do					: out unsigned(7 downto 0);	-- data out	(from chip)
      pot_x				: in  unsigned(7 downto 0);	-- paddle input-X
      pot_y				: in  unsigned(7 downto 0);	-- paddle input-Y
      audio_data		: out unsigned(17 downto 0)
      );
  end component;

  
  component sdcardio is
    port (
      clock : in std_logic;
      pixelclk : in std_logic;
      reset : in std_logic;

      ---------------------------------------------------------------------------
      -- fast IO port (clocked at core clock). 1MB address space
      ---------------------------------------------------------------------------
      fastio_addr : in unsigned(19 downto 0);
      fastio_read : in std_logic;
      fastio_write : in std_logic;
      fastio_wdata : in unsigned(7 downto 0);
      fastio_rdata : out unsigned(7 downto 0);
      fastio_sd_rdata : out unsigned(7 downto 0);

      -- If colour RAM is mapped at $DC00-$DFFF, then don't map sector buffer
      colourram_at_dc00 : in std_logic;
      viciii_iomode : in std_logic_vector(1 downto 0);
      
      sectorbuffermapped : out std_logic;
      sectorbuffermapped2 : out std_logic;
      sectorbuffercs : in std_logic;
      
      led : out std_logic := '0';
      motor : out std_logic := '0';

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

      -- Microphone
      micData : in std_logic;
      micClk : out std_logic;
      micLRSel : out std_logic;

      -- Audio in from digital SIDs
      leftsid_audio : in unsigned(17 downto 0);
      rightsid_audio : in unsigned(17 downto 0);

      -- Audio output
      ampPWM : out std_logic;
      ampSD : out std_logic;

      -- Temperature sensor
      tmpSDA : out std_logic;
      tmpSCL : out std_logic;
      tmpInt : in std_logic;
      tmpCT : in std_logic;

      ----------------------------------------------------------------------
      -- Flash RAM for holding config
      ----------------------------------------------------------------------
      QspiSCK : out std_logic;
      QspiDB : inout std_logic_vector(3 downto 0);
      QspiCSn : out std_logic;
      
      last_scan_code : in std_logic_vector(12 downto 0);
      
      -------------------------------------------------------------------------
      -- And general switch inputs on the FPGA board (good as place as any here)
      -------------------------------------------------------------------------
      sw : in std_logic_vector(15 downto 0);
      btn : in std_logic_vector(4 downto 0)

      );
  end component;
  
  component cia6526 is
    port (
      cpuclock : in std_logic;
      phi0 : in std_logic;
      todclock : in std_logic;
      reset : in std_logic;
      irq : out std_logic := '1';

      seg_led : out unsigned(31 downto 0);

      ---------------------------------------------------------------------------
      -- fast IO port (clocked at core clock). 1MB address space
      ---------------------------------------------------------------------------
      cs : in std_logic;
      fastio_addr : in unsigned(7 downto 0);
      fastio_write : in std_logic;
      fastio_wdata : in unsigned(7 downto 0);
      fastio_rdata : out unsigned(7 downto 0);

      portaout : out std_logic_vector(7 downto 0);
      portain : in std_logic_vector(7 downto 0);
      
      portbout : out std_logic_vector(7 downto 0);
      portbin : in std_logic_vector(7 downto 0);

      flagin : in std_logic;

      pcout : out std_logic;

      spout : out std_logic;
      spin : in std_logic;

      countout : out std_logic;
      countin : in std_logic);
  end component;
  component keymapper is    
    port (
      ioclk : in std_logic;

      nmi : out std_logic;
      reset : out std_logic;
      
      last_scan_code : out std_logic_vector(12 downto 0);

      -- PS2 keyboard interface
      ps2clock  : in  std_logic;
      ps2data   : in  std_logic;
      -- CIA ports
      porta_in  : in  std_logic_vector(7 downto 0);
      porta_out : out std_logic_vector(7 downto 0);
      portb_out : out std_logic_vector(7 downto 0)
      );
  end component;


  signal kickstartcs : std_logic;

  signal clock50hz : std_logic := '1';
  constant divisor50hz : integer := 640000; -- 64MHz/50Hz/2;
  signal counter50hz : integer := 0;
  
  signal cia1cs : std_logic;
  signal cia2cs : std_logic;

  signal sectorbuffercs : std_logic;
  signal sector_buffer_mapped_read : std_logic;

  signal last_scan_code : std_logic_vector(12 downto 0);
  
  signal cia1porta_out : std_logic_vector(7 downto 0);
  signal cia1porta_in : std_logic_vector(7 downto 0);
  signal cia1portb_out : std_logic_vector(7 downto 0);
  signal cia1portb_in : std_logic_vector(7 downto 0);

  signal leftsid_cs : std_logic;
  signal leftsid_audio : unsigned(17 downto 0);
  signal rightsid_cs : std_logic;
  signal rightsid_audio : unsigned(17 downto 0);
  
begin         
  kickstartrom : kickstart port map (
    clk     => clk,
    address => address(12 downto 0),
    we      => w,
    cs      => kickstartcs,
    data_i  => data_i,
    data_o  => data_o);

  cia1: cia6526 port map (
    cpuclock => clk,
    phi0 => phi0,
    todclock => clock50hz,
    reset => reset,
    irq => irq,
    cs => cia1cs,
    seg_led => seg_led,
    fastio_addr => unsigned(address(7 downto 0)),
    fastio_write => w,
    std_logic_vector(fastio_rdata) => data_o,
    fastio_wdata => unsigned(data_i),

    portaout => cia1porta_out,
    portbout => cia1portb_out,
    portain => cia1porta_in,
    portbin => cia1portb_in,
    flagin => '1',
    spin => '1',
    countin => '1'
    );

  cia2: cia6526 port map (
    cpuclock => clk,
    phi0 => phi0,
    todclock => clock50hz,
    reset => reset,
    irq => nmi,
    cs => cia2cs,
    fastio_addr => unsigned(address(7 downto 0)),
    fastio_write => w,
    std_logic_vector(fastio_rdata) => data_o,
    fastio_wdata => unsigned(data_i),

    -- CIA ports not connected by default
    portbin => x"ff",
    portain => x"ff",
    flagin => '1',
    spin => '1',
    countin => '1'
    );

  keymapper0 : keymapper port map (
    ioclk       => clk,
    nmi => restore_nmi,
    reset => reset_out,
    ps2clock       => ps2clock,
    ps2data        => ps2data,
    last_scan_code => last_scan_code,
    porta_in       => cia1porta_out,
    porta_out      => cia1porta_in,
    portb_out      => cia1portb_in
    );

  leftsid: sid6581 port map (
    clk_1MHz => phi0,
    clk32 => clk,
    reset => reset,
    cs => leftsid_cs,
    we => w,
    addr => unsigned(address(4 downto 0)),
    di => unsigned(data_i),
    std_logic_vector(do) => data_o,
    pot_x => x"00",
    pot_y => x"00",
    audio_data => leftsid_audio);

  rightsid: sid6581 port map (
    clk_1MHz => phi0,
    clk32 => clk,
    reset => reset,
    cs => rightsid_cs,
    we => w,
    addr => unsigned(address(4 downto 0)),
    di => unsigned(data_i),
    std_logic_vector(do) => data_o,
    pot_x => x"00",
    pot_y => x"00",
    audio_data => rightsid_audio);

  sdcard0 : sdcardio port map (
    pixelclk => pixelclk,
    clock => clk,
    reset => reset,

    fastio_addr => unsigned(address),
    fastio_write => w,
    fastio_read => r,
    fastio_wdata => unsigned(data_i),
    std_logic_vector(fastio_rdata) => data_o,
    std_logic_vector(fastio_sd_rdata) => sd_data_o,
    colourram_at_dc00 => colourram_at_dc00,
    viciii_iomode => viciii_iomode,
    sectorbuffermapped => sector_buffer_mapped,
    sectorbuffermapped2 => sector_buffer_mapped_read,
    sectorbuffercs => sectorbuffercs,

    led => led,
    motor => motor,
    
    sw => sw,
    btn => btn,
    cs_bo => cs_bo,
    sclk_o => sclk_o,
    mosi_o => mosi_o,
    miso_i => miso_i,

    aclMISO => aclMISO,
    aclMOSI => aclMOSI,
    aclSS => aclSS,
    aclSCK => aclSCK,
    aclInt1 => aclInt1,
    aclInt2 => aclInt2,
    
    micData => micData,
    micClk => micClk,
    micLRSel => micLRSel,

    leftsid_audio => leftsid_audio,
    rightsid_audio => rightsid_audio,
    
    ampSD => ampSD,
    ampPWM => ampPWM,
    
    tmpSDA => tmpSDA,
    tmpSCL => tmpSCL,
    tmpInt => tmpInt,
    tmpCT => tmpCT,

    QspiSCK => QspiSCK,
    QspiDB => QspiDB,
    QspiCSn => QspiCSn,

    last_scan_code => last_scan_code

    );
  
  process(clk)
  begin
    if rising_edge(clk) then
      -- Generate 50Hz signal for TOD clock
      -- (Note that we are a bit conflicted here, as our video mode is PALx4,
      --  but at 60Hz.  We will make our CIAs take 50Hz like in most PAL countries
      -- so that we don't confuse things too much.  We will probably add a 50Hz
      -- raster interrupt filter to help music and games play at the right rate.)
      if counter50hz<divisor50hz then
        counter50hz <= counter50hz + 1;
      else
        clock50hz <= not clock50hz;
        counter50hz <= 0;
      end if;
    end if;
  end process;
  
  process (r,w,address,cia1portb_in,cia1porta_out,colourram_at_dc00)
  begin  -- process

    if (r or w) = '1' then
      if address(19 downto 13)&'0' = x"FE" then
        kickstartcs<= '1';
      else
        kickstartcs <='0';
      end if;

      -- sdcard sector buffer: only mapped if no colour ram @ $DC00, and if
      -- the sectorbuffer mapping flag is set
      sectorbuffercs <= '0';
      report "fastio address = $" & to_hstring(address) severity note;
      
      if address(19 downto 16) = x"D"
        and address(15 downto 14) = "00"
        and address(11 downto 9)&'0' = x"E"
        and sector_buffer_mapped_read = '1' and colourram_at_dc00 = '0' then
        sectorbuffercs <= '1';
        report "selecting SD card sector buffer" severity note;
      end if;

      -- Now map the SIDs
      -- $D440 = left SID
      -- $D400 = right SID
      -- Presumably repeated through to $D5FF.
      case address(19 downto 8) is
        when x"D04" => leftsid_cs <= address(6); rightsid_cs <= not address(6);
        when x"D05" => leftsid_cs <= address(6); rightsid_cs <= not address(6);
        when x"D14" => leftsid_cs <= address(6); rightsid_cs <= not address(6);
        when x"D15" => leftsid_cs <= address(6); rightsid_cs <= not address(6);
        when x"D24" => leftsid_cs <= address(6); rightsid_cs <= not address(6);
        when x"D25" => leftsid_cs <= address(6); rightsid_cs <= not address(6);
        when x"D34" => leftsid_cs <= address(6); rightsid_cs <= not address(6);
        when x"D35" => leftsid_cs <= address(6); rightsid_cs <= not address(6);
        when others => leftsid_cs <= '0'; rightsid_cs <= '0';
      end case;
      
      -- Now map the CIAs.

      -- These are a bit fun, because they only get mapped if colour RAM isn't
      -- being mapped in $DC00-$DFFF using the C65 2K colour ram register
      cia1cs <='0';
      cia2cs <='0';
      if colourram_at_dc00='0' and sector_buffer_mapped_read='0' then
        case address(19 downto 8) is
          when x"D0C" => cia1cs <='1';
          when x"D1C" => cia1cs <='1';
          when x"D2C" => cia1cs <='1';
          when x"D3C" => cia1cs <='1';
          when x"D0D" => cia2cs <='1';
          when x"D1D" => cia2cs <='1';
          when x"D2D" => cia2cs <='1';
          when x"D3D" => cia2cs <='1';
          when others => null;
        end case;
      end if;
    else
      cia1cs <= '0';
      cia2cs <= '0';
      kickstartcs <= '0';
      sectorbuffercs <= '0';
    end if;
  end process;

end behavioral;
