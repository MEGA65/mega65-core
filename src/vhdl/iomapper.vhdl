use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity iomapper is
  port (Clk : in std_logic;
        protected_hardware_in : in unsigned(7 downto 0);
        virtualised_hardware_in : in unsigned(7 downto 0);
        cpuclock : in std_logic;
        pixelclk : in std_logic;
        uartclock : in std_logic;
        clock50mhz : in std_logic;
        phi0 : in std_logic;
        reset : in std_logic;
        reset_out : out std_logic;
        irq : out std_logic;
        nmi : out std_logic;
        capslock_key : in std_logic;
        speed_gate : out std_logic;
        speed_gate_enable : in std_logic;
        hyper_trap : out std_logic;
        matrix_mode_trap : out std_logic;
        restore_key : in std_logic;
        restore_nmi : out std_logic;
        cpu_hypervisor_mode : in std_logic;
        hyper_trap_f011_read : out std_logic;
        hyper_trap_f011_write : out std_logic;

        uart_char : out unsigned(7 downto 0);
        uart_char_valid : out std_logic := '0';
        uart_monitor_char : out unsigned(7 downto 0);
        uart_monitor_char_valid : out std_logic := '0';

        display_shift_out : out std_logic_vector(2 downto 0) := "000";
        shift_ready_out : out std_logic := '0';
        shift_ack_in : in std_logic;        
        mm_displayMode_out : out unsigned(1 downto 0) := "00";
        
        fpga_temperature : in std_logic_vector(11 downto 0);
        address : in std_logic_vector(19 downto 0);
        r : in std_logic;
        w : in std_logic;
        data_i : in std_logic_vector(7 downto 0);
        data_o : out std_logic_vector(7 downto 0);
        sd_data_o : out std_logic_vector(7 downto 0);
        sector_buffer_mapped : out std_logic;

        key_scancode : in unsigned(15 downto 0);
        key_scancode_toggle : in std_logic;

        visual_keyboard_enable : out std_logic;
        keyboard_at_top : out std_logic;
        alternate_keyboard : out std_logic;
        osk_x : out unsigned(11 downto 0) := (others => '0');
        osk_y : out unsigned(11 downto 0);
        osk_key1 : out unsigned(7 downto 0);
        osk_key2 : out unsigned(7 downto 0);
        osk_key3 : out unsigned(7 downto 0);
        osk_key4 : out unsigned(7 downto 0);

        reg_isr_out : out unsigned(7 downto 0);
        imask_ta_out : out std_logic;

        drive_led : out std_logic := '0';
        motor : out std_logic := '0';
        drive_led_out : in std_logic;

        porta_pins : inout  std_logic_vector(7 downto 0);
        portb_pins : inout  std_logic_vector(7 downto 0);
        keyboard_column8_out : out std_logic;
        key_left : in std_logic;
        key_up : in std_logic;

        fa_left : in std_logic;
        fa_right : in std_logic;
        fa_up : in std_logic;
        fa_down : in std_logic;
        fa_fire : in std_logic;
        fb_left : in std_logic;
        fb_right : in std_logic;
        fb_up : in std_logic;
        fb_down : in std_logic;
        fb_fire : in std_logic;

        ----------------------------------------------------------------------
        -- CBM floppy serial port
        ----------------------------------------------------------------------
        iec_clk_en : out std_logic := '0';
        iec_data_en : out std_logic := '0';
        iec_data_o : out std_logic := '1';
        iec_reset : out std_logic := '1';
        iec_clk_o : out std_logic := '1';
        iec_data_i : in std_logic := 'Z';
        iec_clk_i : in std_logic := 'Z';
        iec_atn : out std_logic := '1';
        
        ps2data : in std_logic;
        ps2clock : in std_logic;
        scancode_out : out std_logic_vector(12 downto 0); 												  
        pmod_clock : in std_logic;
        pmod_start_of_sequence : in std_logic;
        pmod_data_in : in std_logic_vector(3 downto 0);
        pmod_data_out : out std_logic_vector(1 downto 0);
        pmoda : inout std_logic_vector(7 downto 0);

        hdmi_scl : inout std_logic := '1';
        hdmi_sda : inout std_logic := 'Z';

        uart_rx : in std_logic;
        uart_tx : out std_logic;

        pixel_stream_in : in unsigned (7 downto 0);
        pixel_y : in unsigned (11 downto 0);
        pixel_valid : in std_logic;
        pixel_newframe : in std_logic;
        pixel_newraster : in std_logic;
        pixel_x_640 : in integer;
    
    ---------------------------------------------------------------------------
    -- IO lines to the ethernet controller
    ---------------------------------------------------------------------------
    eth_mdio : inout std_logic;
    eth_mdc : out std_logic;
    eth_reset : out std_logic;
    eth_rxd : in unsigned(1 downto 0);
    eth_txd : out unsigned(1 downto 0);
    eth_txen : out std_logic;
    eth_rxdv : in std_logic;
    eth_rxer : in std_logic;
    eth_interrupt : in std_logic;

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
        ampPWM_l : out std_logic;
        ampPWM_r : out std_logic;
        ampSD : out std_logic;

        tmpSDA : out std_logic;
        tmpSCL : out std_logic;
        tmpInt : in std_logic;
        tmpCT : in std_logic;
        
        sw : in std_logic_vector(15 downto 0);
        btn : in std_logic_vector(4 downto 0);
        seg_led : out unsigned(31 downto 0);

        viciii_iomode : in std_logic_vector(1 downto 0);
        
        colourram_at_dc00 : in std_logic;
       
        ---------------------------------------------------------------------------
        -- IO port to far call stack
        ---------------------------------------------------------------------------
        farcallstack_we : in std_logic;
        farcallstack_addr : in std_logic_vector(8 downto 0);
        farcallstack_din : in std_logic_vector(63 downto 0);
        farcallstack_dout : out std_logic_vector(63 downto 0)

        );
end iomapper;

architecture behavioral of iomapper is

  signal pota_x : unsigned(7 downto 0);
  signal pota_y : unsigned(7 downto 0);
  signal potb_x : unsigned(7 downto 0);
  signal potb_y : unsigned(7 downto 0);
  
  signal kickstartcs : std_logic;

  signal reset_high : std_logic;

  signal capslock_from_keymapper : std_logic := '1';
  signal key_debug : std_logic_vector(7 downto 0);
  signal widget_disable : std_logic;
  signal ps2_disable : std_logic;
  signal joy_disable : std_logic;
  signal virtual_disable : std_logic;
  signal physkey_disable : std_logic;

  signal hyper_trap_count : unsigned(7 downto 0) := x"00";
  signal restore_up_count : unsigned(7 downto 0) := x"00";
  signal restore_down_count : unsigned(7 downto 0) := x"00";
  
  signal clock50hz : std_logic := '1';
  constant divisor50hz : integer := 480000; -- 48MHz/50Hz/2;
  signal counter50hz : integer := 0;
  
  signal cia1cs : std_logic;
  signal cia2cs : std_logic;

  signal sectorbuffercs : std_logic;
  signal sector_buffer_mapped_read : std_logic;

  signal farcallstackcs : std_logic;
  signal farcallstack_w : std_logic;
  signal farcallstack_wdata : std_logic_vector(63 downto 0);
  signal farcallstack_rdata : std_logic_vector(63 downto 0);
                        
  signal last_scan_code : std_logic_vector(12 downto 0);
  
  signal cia1porta_ddr : std_logic_vector(7 downto 0);
  signal cia1porta_out : std_logic_vector(7 downto 0);
  signal cia1porta_in : std_logic_vector(7 downto 0);
  signal cia1portb_ddr : std_logic_vector(7 downto 0);
  signal cia1portb_out : std_logic_vector(7 downto 0);
  signal cia1portb_in : std_logic_vector(7 downto 0);

  signal leftsid_cs : std_logic;
  signal leftsid_audio : unsigned(17 downto 0);
  signal rightsid_cs : std_logic;
  signal rightsid_audio : unsigned(17 downto 0);

  signal spare_bits : unsigned(4 downto 0);

  signal buffer_moby_toggle : std_logic;
  signal buffer_address : unsigned(11 downto 0);
  signal buffer_rdata : unsigned(7 downto 0);

  signal eth_keycode_toggle : std_logic;
  signal eth_keycode : unsigned(15 downto 0);

  signal keyboard_column8_select : std_logic;

  signal ascii_key_valid : std_logic := '0';
  signal ascii_key : unsigned(7 downto 0) := x"00";
  signal bucky_key : std_logic_vector(7 downto 0) := (others => '0');
  signal ascii_key_buffered : unsigned(7 downto 0) := x"00";
  signal ascii_key_presenting : std_logic := '0';
  type key_buffer_t is array(0 to 3) of unsigned(7 downto 0);
  signal ascii_key_buffer : key_buffer_t;
  signal ascii_key_buffer_count : integer range 0 to 3 := 0;
  signal ascii_key_next : std_logic := '0';

  signal sd_bitbash : std_logic;
  signal sd_bitbash_cs_bo : std_logic;
  signal sd_bitbash_sclk_o : std_logic;
  signal sd_bitbash_mosi_o : std_logic;
  signal sd_bitbash_miso_i : std_logic;
  signal cs_bo_sd : std_logic;
  signal sclk_o_sd : std_logic;
  signal mosi_o_sd : std_logic;  

  signal matrix_segment_num : std_logic_vector(7 downto 0) := (others => '0');
  signal matrix_segment_out : std_logic_vector(7 downto 0);
  signal virtual_key1 : std_logic_vector(7 downto 0);
  signal virtual_key2 : std_logic_vector(7 downto 0);
  signal virtual_key3 : std_logic_vector(7 downto 0);

  signal keyboard_scan_mode : std_logic_vector(1 downto 0);
  signal keyboard_scan_rate : unsigned(7 downto 0);

  signal ef_latch : std_logic := '0';
  
  signal dummy_e : std_logic_vector(7 downto 0);
  signal dummy_g : std_logic_vector(7 downto 0);
  signal dummy : std_logic_vector(10 downto 0);
  
begin

  block1: block
  begin
  kickstartrom : entity work.kickstart port map (
    clk     => clk,
    address => address(13 downto 0),
    we      => w,
    cs      => kickstartcs,
    data_i  => data_i,
    data_o  => data_o);
  end block;

  block2: block
  begin
  framepacker0: entity work.framepacker port map (
    ioclock => clk,
    pixelclock => pixelclk,
    hypervisor_mode => cpu_hypervisor_mode,

    pixel_stream_in => pixel_stream_in,
    pixel_y => pixel_y,
    pixel_valid => pixel_valid,
    pixel_newframe => pixel_newframe,
    pixel_newraster => pixel_newraster,

    buffer_moby_toggle => buffer_moby_toggle,
    buffer_address => buffer_address,
    buffer_rdata => buffer_rdata,

    fastio_addr => unsigned(address(19 downto 0)),
    fastio_write => w,
    std_logic_vector(fastio_rdata) => data_o,
    fastio_read => r,
    fastio_wdata => unsigned(data_i)
    );
  end block;

  block3: block
  begin
    cia1: entity work.cia6526
      generic map (
        has_iec => '0'
        )
      port map (
    cpuclock => clk,
    phi0 => phi0,
    todclock => clock50hz,
    reset => reset,
    irq => irq,
    reg_isr_out => reg_isr_out,
    imask_ta_out => imask_ta_out,
    cs => cia1cs,
    fastio_address => unsigned(address(7 downto 0)),
    fastio_write => w,
    std_logic_vector(fastio_rdata) => data_o,
    fastio_wdata => unsigned(data_i),
    portaout => cia1porta_out,
    portbout => cia1portb_out,
    portain => cia1porta_in,
    portbin => cia1portb_in,
    portaddr => cia1porta_ddr,
    portbddr => cia1portb_ddr,
    flagin => '1',
    spin => '1',
    countin => '1'
    );
  end block;

  block4: block
  begin
    ciatwo: entity work.cia6526
      generic map (
        has_iec => '1'
        )
      port map (
    cpuclock => clk,
    phi0 => phi0,
    todclock => clock50hz,
    reset => reset,
    irq => nmi,
    cs => cia2cs,
    fastio_address => unsigned(address(7 downto 0)),
    fastio_write => w,
    std_logic_vector(fastio_rdata) => data_o,
    fastio_wdata => unsigned(data_i),

    -- CIA port a (VIC-II bank select + IEC serial port)
    portain(2 downto 0) => (others => '1'),   
    portain(3) => '1', -- IEC serial ATN
    portain(4) => iec_clk_i,
    portain(5) => iec_data_i,
    portain(6) => iec_clk_i,
    portain(7) => iec_data_i,
    portaout(2 downto 0) => dummy(2 downto 0),
    portaout(3) => iec_atn,
    portaout(4) => iec_clk_o,
    portaout(5) => iec_data_o,
    portaout(7 downto 6) => dummy(4 downto 3),
    portaddr(3 downto 0) => dummy(8 downto 5),
    portaddr(4) => iec_clk_en,
    portaddr(5) => iec_data_en,
    portaddr(7 downto 6) => dummy(10 downto 9),
    
    -- CIA port b (user port) not connected by default
    portbin => x"ff",
    flagin => '1',
    spin => '1',
    countin => '1'
    );
  end block;

  block4b: block
  begin
    c65uart0: entity work.c65uart port map (
      pixelclock => pixelclk,
      cpuclock => clk,
      phi0 => phi0,
      reset => reset,
--      irq => nmi,
      fastio_address => unsigned(address(19 downto 0)),
      fastio_write => w,
      fastio_read => r,
      std_logic_vector(fastio_rdata) => data_o,
      fastio_wdata => unsigned(data_i),
      -- Port E is used for extra keys on C65 keyboard:
      -- bit0 = caps lock (input only)
      -- bit1 = column 8 select (output only)
      porte(7 downto 2) => dummy_e(7 downto 2),
      porte(1) => keyboard_column8_select,
      porte(0) => capslock_from_keymapper,
      -- Port G is M65 only, and has bit-bash interfaces
      portg(7) => hdmi_sda,
      portg(6) => hdmi_scl,
      portg(5) => sd_bitbash,
      portg(4) => sd_bitbash_cs_bo,
      portg(3) => sd_bitbash_sclk_o,
      portg(2) => sd_bitbash_mosi_o,
      portg(1 downto 0) => keyboard_scan_mode,
      key_debug => key_debug,
      widget_disable => widget_disable,
      ps2_disable => ps2_disable,
      joy_disable => joy_disable,
      virtual_disable => virtual_disable,
      physkey_disable => physkey_disable,
      key_left => key_left,
      key_up => key_up,
      uart_rx => uart_rx,
      uart_tx => uart_tx,
      portf => pmoda,
      porth => std_logic_vector(ascii_key_buffered),
      porth_write_strobe => ascii_key_next,
      porti => std_logic_vector(bucky_key(7 downto 0)),
      portj_out => matrix_segment_num,
      portj_in => matrix_segment_out,
      portk_out(6 downto 0) => virtual_key1(6 downto 0),
      portk_out(7) => visual_keyboard_enable,
      portl_out(6 downto 0) => virtual_key2(6 downto 0),
      portl_out(7) => keyboard_at_top,
      portm_out(6 downto 0) => virtual_key3(6 downto 0),
      portm_out(7) => alternate_keyboard,
      portn_out => keyboard_scan_rate,
      porto_out => osk_x(7 downto 0),
      portp_out => osk_y(11 downto 4)
      );
  end block;
  
  block5: block
  begin
    kc0 : entity work.keyboard_complex
      port map (
      reset_in => reset,
      matrix_mode_in => protected_hardware_in(6),

      matrix_segment_num => matrix_segment_num,
      matrix_segment_out => matrix_segment_out,

      scan_mode => keyboard_scan_mode,
      scan_rate => keyboard_scan_rate,
      
    widget_disable => widget_disable,
    ps2_disable => ps2_disable,
    joy_disable => joy_disable,
    physkey_disable => physkey_disable,
    virtual_disable => virtual_disable,
    
    ioclock       => clk,
    restore_out => restore_nmi,
    keyboard_restore => restore_key,
    keyboard_capslock => capslock_key,
    key_left => key_left,
    key_up => key_up,

    key1 => unsigned(virtual_key1),
    key2 => unsigned(virtual_key2),
    key3 => unsigned(virtual_key3),

    keydown1 => osk_key1,
    keydown2 => osk_key2,
    keydown3 => osk_key3,
    keydown4 => osk_key4,
      
    hyper_trap_out => hyper_trap,
    hyper_trap_count => hyper_trap_count,
    restore_up_count => restore_up_count,
    restore_down_count => restore_down_count,
    reset_out => reset_out,
    ps2clock       => ps2clock,
    ps2data        => ps2data,
    last_scan_code => last_scan_code,
--    key_status     => seg_led(1 downto 0),
    porta_in       => cia1porta_out,
    portb_in       => cia1portb_out,    
    porta_out      => cia1porta_in,
    portb_out      => cia1portb_in,
    porta_ddr      => cia1porta_ddr,
    portb_ddr      => cia1portb_ddr,

    joya(4) => fa_fire,
    joya(0) => fa_up,
    joya(2) => fa_left,
    joya(1) => fa_down,
    joya(3) => fa_right,
    
    joyb(4) => fb_fire,
    joyb(0) => fb_up,
    joyb(2) => fb_left,
    joyb(1) => fb_down,
    joyb(3) => fb_right,
    
    key_debug_out => key_debug,
  
    porta_pins => porta_pins,
    portb_pins => portb_pins,

    pota_x => pota_x,
    pota_y => pota_y,
    potb_x => potb_x,
    potb_y => potb_y,
    
    speed_gate => speed_gate,
    speed_gate_enable => speed_gate_enable,

    capslock_out => capslock_from_keymapper,
    keyboard_column8_out => keyboard_column8_out,
    keyboard_column8_select_in => keyboard_column8_select,
    pmod_clock => pmod_clock,
    pmod_start_of_sequence => pmod_start_of_sequence,
    pmod_data_in => pmod_data_in,
    pmod_data_out => pmod_data_out,
    
    -- remote keyboard input via ethernet
--    eth_keycode_toggle => eth_keycode_toggle,
--    eth_keycode => eth_keycode

    -- remote 
    eth_keycode_toggle => key_scancode_toggle,
    eth_keycode => key_scancode,

    -- ASCII feed via hardware keyboard scanner
    ascii_key => ascii_key,
    ascii_key_valid => ascii_key_valid,
    bucky_key => bucky_key(6 downto 0)
    
    );
  end block;

  block6: block
  begin
  leftsid: entity work.sid6581 port map (
    clk_1MHz => phi0,
    clk32 => clk,
    reset => reset_high,
    cs => leftsid_cs,
    we => w,
    addr => unsigned(address(4 downto 0)),
    di => unsigned(data_i),
    std_logic_vector(do) => data_o,
    pot_x => pota_x,
    pot_y => pota_y,
    audio_data => leftsid_audio);
  end block;

  block7: block
  begin
  rightsid: entity work.sid6581 port map (
    clk_1MHz => phi0,
    clk32 => clk,
    reset => reset_high,
    cs => rightsid_cs,
    we => w,
    addr => unsigned(address(4 downto 0)),
    di => unsigned(data_i),
    std_logic_vector(do) => data_o,
    pot_x => potb_x,
    pot_y => potb_y,
    audio_data => rightsid_audio);
  end block;

  ethernet0 : entity work.ethernet port map (
    clock50mhz => clock50mhz,
    clock => clk,
    reset => reset,
    irq => irq,

    ---------------------------------------------------------------------------
    -- IO lines to the ethernet controller
    ---------------------------------------------------------------------------
    eth_mdio => eth_mdio,
    eth_mdc => eth_mdc,
    eth_reset => eth_reset,
    eth_rxd => eth_rxd,
    eth_txd => eth_txd,
    eth_txen => eth_txen,
    eth_rxdv => eth_rxdv,
    eth_rxer => eth_rxer,
    eth_interrupt => eth_interrupt,

    buffer_moby_toggle => buffer_moby_toggle,
    buffer_address => buffer_address,
    buffer_rdata => buffer_rdata,

    eth_keycode_toggle => eth_keycode_toggle,
    eth_keycode => eth_keycode,

    fastio_addr => unsigned(address),
    fastio_write => w,
    fastio_read => r,
    fastio_wdata => unsigned(data_i),
    std_logic_vector(fastio_rdata) => data_o
    );
  
  sdcard0 : entity work.sdcardio port map (
    pixelclk => pixelclk,
    clock => clk,
    reset => reset,
    hypervisor_mode => cpu_hypervisor_mode,
    hyper_trap_f011_read => hyper_trap_f011_read,
    hyper_trap_f011_write => hyper_trap_f011_write,
    virtualise_f011 => virtualised_hardware_in(0),

    fpga_temperature => fpga_temperature,

    fastio_addr => unsigned(address),
    fastio_write => w,
    fastio_read => r,
    fastio_wdata => unsigned(data_i),
    std_logic_vector(fastio_rdata) => data_o,
    colourram_at_dc00 => colourram_at_dc00,
    viciii_iomode => viciii_iomode,
    sectorbuffermapped => sector_buffer_mapped,
    sectorbuffermapped2 => sector_buffer_mapped_read,
    sectorbuffercs => sectorbuffercs,

    drive_led => drive_led,
    motor => motor,

    sw => sw,
    btn => btn,

    -- SD card interface
    cs_bo => cs_bo_sd,
    sclk_o => sclk_o_sd,
    mosi_o => mosi_o_sd,
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
    ampPWM_l => ampPWM_l,
    ampPWM_r => ampPWM_r,
    
    tmpSDA => tmpSDA,
    tmpSCL => tmpSCL,
    tmpInt => tmpInt,
    tmpCT => tmpCT,

    QspiSCK => QspiSCK,
    QspiDB => QspiDB,
    QspiCSn => QspiCSn,

    last_scan_code => last_scan_code

    );

  farcallstack0: entity work.farcallstack port map (
    clka => clk,
    ena => farcallstackcs,
    wea(0) => w,
    addra => address(11 downto 0),
    dina => data_i,
    douta => data_o,
    clkb => cpuclock,
    web(0) => farcallstack_w,
    addrb => farcallstack_addr,
    dinb => farcallstack_wdata,
    doutb => farcallstack_rdata
    );
  
  process(reset)
  begin
    reset_high <= not reset;
  end process;

  -- Allow taking over of SD interface for bitbashing and debugging
  cs_bo <= cs_bo_sd when sd_bitbash='0' else sd_bitbash_cs_bo;
  sclk_o <= sclk_o_sd when sd_bitbash='0' else sd_bitbash_sclk_o;
  mosi_o <= mosi_o_sd when sd_bitbash='0' else sd_bitbash_mosi_o;
  
  scancode_out<=last_scan_code;
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

      seg_led(12) <= eth_keycode_toggle;
      seg_led(11) <= last_scan_code(12);
      seg_led(10 downto 0) <= unsigned(last_scan_code(10 downto 0));

      -- Buffer ASCII keyboard input: Writing to the register causes
      -- the next key in the queue to be displayed.
      matrix_mode_trap <= '0';
      if ascii_key_valid='1' and ascii_key = x"EF" and  ef_latch='0' then
        -- C= + TAB
        -- This replaces the old ALT+TAB task switch combination
        matrix_mode_trap <= '1';
        ef_latch <= '1';
      end if;
      if ascii_key /= x"ef" then
        ef_latch <= '0';
      end if;

      -- UART char for monitor/matrix mode
      if ascii_key_valid='1' and protected_hardware_in(6)='1' then
        uart_monitor_char <= ascii_key;
        uart_monitor_char_valid <= '1';
        case ascii_key is
          -- C= + 1,2,3 to set display size
          when x"95" => mm_displayMode_out <= "00";
          when x"96" => mm_displayMode_out <= "01";
          when x"97" => mm_displayMode_out <= "10";
          -- Cursor keys to move matrix mode display
          when x"1d" => display_shift_out <= "010"; --right
                        shift_ready_out <= '1';
          when x"9d" => display_shift_out <= "100"; --left
                        shift_ready_out <= '1';
          when x"91" => display_shift_out <= "001"; --up
                        shift_ready_out <= '1';
          when x"11" => display_shift_out <= "011"; --down
                        shift_ready_out <= '1';
          when others =>  null;
        end case;
    
      else
        uart_monitor_char_valid <= '0';      
      end if;
      if shift_ack_in='1' then
        shift_ready_out <= '0';
      end if;
      
      -- UART char for user mode
      uart_char_valid <= '0';
      if ascii_key_valid='1' and protected_hardware_in(6)='0' then
        uart_char <= ascii_key;
        uart_char_valid <= '1';
        if ascii_key_presenting = '1' then
          if ascii_key_buffer_count < 4 then
            ascii_key_buffer(ascii_key_buffer_count) <= ascii_key;
            ascii_key_buffer_count <= ascii_key_buffer_count + 1;
          end if;
        else
          ascii_key_buffered <= ascii_key;
        end if;
      end if;
      if ascii_key_next = '1' then
        if ascii_key_buffer_count > 0 then
          ascii_key_presenting <= '1';
          ascii_key_buffered <= ascii_key_buffer(0);
          ascii_key_buffer_count <= ascii_key_buffer_count - 1;
          for i in 0 to 2 loop
            ascii_key_buffer(i) <= ascii_key_buffer(i+1);
          end loop;
        else
          ascii_key_presenting <= '0';
          ascii_key_buffered <= x"00";
        end if;
      end if;
      
    end if;
  end process;
  
  process (r,w,address,cia1portb_in,cia1porta_out,colourram_at_dc00,
           sector_buffer_mapped_read)
  begin  -- process

    if (r or w) = '1' then
      -- @IO:GS $FFF8000-$FFFBFFF 16KB Kickstart/hypervisor ROM
      -- @IO:GS $FFF8000-$FFF80FC Hypervisor entry point when $D640-$D67F is written
      -- @IO:GS $FFF8100 Hypervisor entry point on reset (trap $40)
      -- @IO:GS $FFF8104 Hypervisor entry point on page fault (trap $41)
      -- @IO:GS $FFF8108 Hypervisor entry point on RESTORE double-tap (trap $42)
      -- @IO:GS $FFF810C Hypervisor entry point on ALT-TAB (trap $43)
      -- @IO:GS $FFF8110 Hypervisor entry point on FDC read (when virtualised) (trap $44)
      -- @IO:GS $FFF8114 Hypervisor entry point on FDC write (when virtualised) (trap $45)
      
      if address(19 downto 14)&"00" = x"F8" then
        kickstartcs <= cpu_hypervisor_mode;
      else
        kickstartcs <='0';
      end if;

      -- @IO:GS $FFF0000-$FFF0FFF - CPU far call stack (512x8 byte entries)
      if address(19 downto 12) = x"F0" then
        farcallstackcs <= '1';
      else
        farcallstackcs <= '0';
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
      -- Also map SD card sector buffer at $FFD6000 - $FFD61FF regardless of
      -- VIC-IV IO mode and mapping of colour RAM
      if address(19 downto 8) = x"D60" or address(19 downto 8) = x"D61" then
        sectorbuffercs <= '1';
      end if;

      -- Now map the SIDs
      -- @IO:C64 $D440-$D47F = left SID
      -- @IO:C64 $D400-$D43F = right SID
      -- @IO:C64 $D480-$D4FF = repeated images of SIDs
      -- Presumably repeated through to $D5FF.  But we will repeat to $D4FF only
      -- so that we can use $D500-$D5FF for other stuff.
      case address(19 downto 8) is
        when x"D04" => leftsid_cs <= address(6); rightsid_cs <= not address(6);
        when x"D14" => leftsid_cs <= address(6); rightsid_cs <= not address(6);
        when x"D24" => leftsid_cs <= address(6); rightsid_cs <= not address(6);
        when x"D34" => leftsid_cs <= address(6); rightsid_cs <= not address(6);
        -- Some C64 dual-sid programs expect the 2nd sid to be at $D500, so
        -- we will make the SIDs visible at $D500 in c64 io context, and switched
        -- sides.
        when x"D05" => leftsid_cs <= not address(6); rightsid_cs <= address(6);
        when others => leftsid_cs <= '0'; rightsid_cs <= '0';
      end case;

      -- $D500 - $D5FF is not currently used.  Probably use some for FPU.
      
      -- $D600 - $D60F is reserved for C65 serial UART emulation for C65
      -- compatibility (C65 UART actually only has 7 registers).
      -- 6551 is not currently implemented, so this is just unmapped for now,
      -- except for any read values required to allow the C65 ROM to function.

      -- Hypervisor control (only visible from hypervisor mode) $D640 - $D67F
      -- The hypervisor is a CPU provided function.
      
      -- SD controller and miscellaneous hardware (microphone, accelerometer etc)
      -- uses $D680 - $D6FF
      
      -- CPU uses $FFD{0,1,2,3}700 for DMAgic and other CPU-hosted IO registers.
      
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
      leftsid_cs <= '0';
      rightsid_cs <= '0';
      farcallstackcs <= '0';
    end if;
  end process;

end behavioral;
