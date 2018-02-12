use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity iomapper is
  port (Clk : in std_logic;
        clock200 : in std_logic;
        protected_hardware_in : in unsigned(7 downto 0);
        virtualised_hardware_in : in unsigned(7 downto 0);
        -- Enables for the various chip select lines
        chipselect_enables : in std_logic_vector(7 downto 0) := x"FF";

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

        buffereduart_rx : in std_logic;
        buffereduart_tx : out std_logic := '1';
        buffereduart_ringindicate : in std_logic;
        
        display_shift_out : out std_logic_vector(2 downto 0) := "000";
        shift_ready_out : out std_logic := '0';
        shift_ack_in : in std_logic;        
        mm_displayMode_out : out unsigned(1 downto 0) := "00";

        cart_access_count : in unsigned(7 downto 0);
        
        fpga_temperature : in std_logic_vector(11 downto 0);
        address : in std_logic_vector(19 downto 0);
        addr_fast : in std_logic_vector(19 downto 0);
        r : in std_logic;
        w : in std_logic;
        data_i : in std_logic_vector(7 downto 0);
        data_o : out std_logic_vector(7 downto 0);
        kickstart_rdata : out std_logic_vector(7 downto 0);
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
        fa_potx : in std_logic;
        fa_poty : in std_logic;
        fb_potx : in std_logic;
        fb_poty : in std_logic;
        
        pota_x : in unsigned(7 downto 0);
        pota_y : in unsigned(7 downto 0);
        potb_x : in unsigned(7 downto 0);
        potb_y : in unsigned(7 downto 0);

        pot_drain : in std_logic;
        pot_via_iec : buffer std_logic;
        
        mouse_debug : in unsigned(7 downto 0);
        amiga_mouse_enable_a : out std_logic;
        amiga_mouse_enable_b : out std_logic;
        amiga_mouse_assume_a : out std_logic;
        amiga_mouse_assume_b : out std_logic;
        
        ----------------------------------------------------------------------
        -- CBM floppy serial port
        ----------------------------------------------------------------------
        iec_clk_en : out std_logic := '0';
        iec_data_en : out std_logic := '0';
        iec_data_o : out std_logic := '1';
        iec_reset : out std_logic := '1';
        iec_clk_o : out std_logic := '1';
        iec_atn_o : out std_logic := '1';
        iec_data_external : in std_logic := 'Z';
        iec_clk_external : in std_logic := 'Z';

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
        
        kickstart_address : in std_logic_vector(13 downto 0);
        
        colourram_at_dc00 : in std_logic
               
        );
end iomapper;

architecture behavioral of iomapper is

  -- Enables for each of the chip select lines,
  -- used for disabling IO devices for debugging
  signal cia1cs_en : std_logic := '1';
  signal cia2cs_en : std_logic := '1';
  signal lscs_en : std_logic := '1';
  signal rscs_en : std_logic := '1';
  signal sbcs_en : std_logic := '1';
  signal c65uart_en : std_logic := '1';
  signal sdcardio_en : std_logic := '1';
  signal ethernetcs_en : std_logic := '1';

  
  signal potl_x : unsigned(7 downto 0);
  signal potl_y : unsigned(7 downto 0);
  signal potr_x : unsigned(7 downto 0);
  signal potr_y : unsigned(7 downto 0);
  
  signal kickstartcs : std_logic;

  signal reset_high : std_logic;

  signal capslock_from_keymapper : std_logic := '1';
  signal key_debug : std_logic_vector(7 downto 0);
  signal widget_disable : std_logic;
  signal ps2_disable : std_logic;
  signal joykey_disable : std_logic;
  signal joyreal_disable : std_logic;
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
  signal sectorbuffercs_fast : std_logic;
  signal sector_buffer_mapped_read : std_logic;

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

  signal c65uart_cs : std_logic := '0';
  signal sdcardio_cs : std_logic := '0';
  signal sdcardio_cs_fast : std_logic := '0';
  signal f011_cs : std_logic := '0';
  signal buffereduart_cs : std_logic := '0';
  signal cpuregs_cs : std_logic := '0';
  signal thumbnail_cs : std_logic := '0';
  signal ethernet_cs : std_logic := '0';
  
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

  signal joya_rotate : std_logic;
  signal joyb_rotate : std_logic;

  signal iec_atn_reflect : std_logic := '1';
  signal iec_clk_reflect : std_logic := '1';
  signal iec_data_reflect : std_logic := '1';
  signal iec_atn_fromcia : std_logic := '1';
  signal iec_clk_fromcia : std_logic := '1';
  signal iec_data_fromcia : std_logic := '1';

  signal suppress_key_glitches : std_logic;
  signal suppress_key_retrigger : std_logic;
  signal ascii_key_event_count : unsigned(15 downto 0) := x"0000";
  
  signal cia1_irq : std_logic;
  signal ethernet_irq : std_logic;
  signal uart_irq : std_logic;
  
begin

  block1: block
  begin
  kickstartrom : entity work.kickstart port map (
    clk     => clk,
    address => kickstart_address,
    address_i => address(13 downto 0),
    we      => w,
    cs      => kickstartcs,
    data_o  => kickstart_rdata,
    data_i  => data_i
    );
  end block;
  
  -- IRQ line is wire-anded together as if it had a pullup.
  irq <= cia1_irq and ethernet_irq and uart_irq;
  
  block2: block
  begin
  framepacker0: entity work.framepacker port map (
    ioclock => clk,
    pixelclock => pixelclk,
    hypervisor_mode => cpu_hypervisor_mode,
    thumbnail_cs => thumbnail_cs,

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
      generic map ( unit => x"1")
      port map (
    cpuclock => clk,
    phi0 => phi0,
    todclock => clock50hz,
    reset => reset,
    irq => cia1_irq,
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
      generic map ( unit => x"2")
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
    portain(3) => iec_atn_reflect, -- IEC serial ATN
    -- We reflect the output values for CLK and DATA straight back in,
    -- as they are needed to be visible for the DOS routines to work.
    portain(4) => iec_clk_reflect,
    portain(5) => iec_data_reflect,
    portain(6) => iec_clk_external,
    portain(7) => iec_data_external,
    portaout(2 downto 0) => dummy(2 downto 0),
    portaout(3) => iec_atn_fromcia,
    portaout(4) => iec_clk_fromcia,
    portaout(5) => iec_data_fromcia,
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
      c65uart_cs => c65uart_cs,
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
      joykey_disable => joykey_disable,
      joyreal_disable => joyreal_disable,
      virtual_disable => virtual_disable,
      physkey_disable => physkey_disable,
      suppress_key_glitches => suppress_key_glitches,
      suppress_key_retrigger => suppress_key_retrigger,
      ascii_key_event_count(13 downto 0) => ascii_key_event_count(13 downto 0),
      ascii_key_event_count(15) => ascii_key_next,
      ascii_key_event_count(14) => reset_high,
      key_left => key_left,
      key_up => key_up,
      uart_rx => uart_rx,
      uart_tx => uart_tx,
      portf => pmoda,
      porth => std_logic_vector(ascii_key_buffered),
      porth_write_strobe => ascii_key_next,
      porti => std_logic_vector(bucky_key(7 downto 0)),
      portj_out => matrix_segment_num,
      portj_in => std_logic_vector(matrix_segment_out),
      portk_out(6 downto 0) => virtual_key1(6 downto 0),
      portk_out(7) => visual_keyboard_enable,
      portl_out(6 downto 0) => virtual_key2(6 downto 0),
      portl_out(7) => keyboard_at_top,
      portm_out(6 downto 0) => virtual_key3(6 downto 0),
      portm_out(7) => alternate_keyboard,
      portn_out => keyboard_scan_rate,
      porto_out => osk_x(7 downto 0),
      portp_out => osk_y(11 downto 4),
      joya_rotate => joya_rotate,
      joyb_rotate => joyb_rotate,
      mouse_debug => mouse_debug,
      amiga_mouse_enable_a => amiga_mouse_enable_a,
      amiga_mouse_enable_b => amiga_mouse_enable_b,
      amiga_mouse_assume_a => amiga_mouse_assume_a,
      amiga_mouse_assume_b => amiga_mouse_assume_b,
      pot_via_iec => pot_via_iec,
      pot_drain => pot_drain,
      cia1portb_out => cia1portb_out(7 downto 6),
      fa_potx => fa_potx,
      fa_poty => fa_poty,
      fb_potx => fb_potx,
      fb_poty => fb_poty,
      pota_x => pota_x,
      pota_y => pota_y,
      potb_x => potb_x,
      potb_y => potb_y
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
      suppress_key_glitches => suppress_key_glitches,
      suppress_key_retrigger => suppress_key_retrigger,

      scan_mode => keyboard_scan_mode,
      scan_rate => keyboard_scan_rate,
      
    widget_disable => widget_disable,
    ps2_disable => ps2_disable,
    joyreal_disable => joyreal_disable,
    joykey_disable => joykey_disable,
    physkey_disable => physkey_disable,
    virtual_disable => virtual_disable,

      joya_rotate => joya_rotate,
      joyb_rotate => joyb_rotate,
      
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
    pot_x => potl_x,
    pot_y => potl_y,
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
    pot_x => potr_x,
    pot_y => potr_y,
    audio_data => rightsid_audio);
  end block;

  ethernet0 : entity work.ethernet port map (
    clock50mhz => clock50mhz,
    clock200 => clock200,
    clock => clk,
    reset => reset,
    irq => ethernet_irq,
    ethernet_cs => ethernet_cs,

    ---------------------------------------------------------------------------
    -- IO lines to the ethernet controller
    ---------------------------------------------------------------------------
    eth_mdio => eth_mdio,
    eth_mdc => eth_mdc,
    eth_reset => eth_reset,
    eth_rxd_in => eth_rxd,
    eth_txd_out => eth_txd,
    eth_txen_out => eth_txen,
    eth_rxdv_in => eth_rxdv,
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
    std_logic_vector(fastio_rdata) => data_o,
    fastio_wdata => unsigned(data_i)
    );
  
  buffered_uart0 : entity work.buffereduart port map (
    clock50mhz => clock50mhz,
    clock200 => clock200,
    clock => clk,
    reset => reset,
    irq => uart_irq,
    buffereduart_cs => buffereduart_cs,

    ---------------------------------------------------------------------------
    -- IO lines to the buffered UART
    ---------------------------------------------------------------------------
    uart_rx => buffereduart_rx,
    uart_tx => buffereduart_tx,
    uart_ringindicate => buffereduart_ringindicate,

    fastio_addr => unsigned(address),
    fastio_write => w,
    fastio_read => r,
    std_logic_vector(fastio_rdata) => data_o,
    fastio_wdata => unsigned(data_i)
    );

  sdcard0 : entity work.sdcardio port map (
    pixelclk => pixelclk,
    clock => clk,
    reset => reset,
    sdcardio_cs => sdcardio_cs,
    f011_cs => f011_cs,
    hypervisor_mode => cpu_hypervisor_mode,
    hyper_trap_f011_read => hyper_trap_f011_read,
    hyper_trap_f011_write => hyper_trap_f011_write,
    virtualise_f011 => virtualised_hardware_in(0),

    fpga_temperature => fpga_temperature,

    fastio_addr => unsigned(address),
    fastio_addr_fast => unsigned(addr_fast),
    fastio_write => w,
    fastio_read => r,
    fastio_wdata => unsigned(data_i),
    std_logic_vector(fastio_rdata_sel) => data_o,
    colourram_at_dc00 => colourram_at_dc00,
    viciii_iomode => viciii_iomode,
    sectorbuffermapped => sector_buffer_mapped,
    sectorbuffermapped2 => sector_buffer_mapped_read,
    sectorbuffercs => sectorbuffercs,
    sectorbuffercs_fast => sectorbuffercs_fast,

    drive_led => drive_led,
    motor => motor,

    f_density => f_density,
    f_motor => f_motor,
    f_select => f_select,
    f_stepdir => f_stepdir,
    f_step => f_step,
    f_wdata => f_wdata,
    f_wgate => f_wgate,
    f_side1 => f_side1,
    f_index => f_index,
    f_track0 => f_track0,
    f_writeprotect => f_writeprotect,
    f_rdata => f_rdata,
    f_diskchanged => f_diskchanged,
    
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

  process(reset)
  begin
    reset_high <= not reset;
    iec_reset <= reset;    
  end process;

  -- Allow taking over of SD interface for bitbashing and debugging
  cs_bo <= cs_bo_sd when sd_bitbash='0' else sd_bitbash_cs_bo;
  sclk_o <= sclk_o_sd when sd_bitbash='0' else sd_bitbash_sclk_o;
  mosi_o <= mosi_o_sd when sd_bitbash='0' else sd_bitbash_mosi_o;
  
  scancode_out<=last_scan_code;
  process(clk,sbcs_en,lscs_en,c65uart_en,ethernetcs_en,sdcardio_en,
          cia1cs_en,cia2cs_en)
  begin
    if rising_edge(clk) then

      cia1cs_en <= chipselect_enables(0);
      cia2cs_en <= chipselect_enables(1);
      lscs_en <= chipselect_enables(2);
      rscs_en <= chipselect_enables(2);
      ethernetcs_en <= chipselect_enables(3);
      -- (4)
      sbcs_en <= chipselect_enables(5);
      c65uart_en <= chipselect_enables(6);
      sdcardio_en <= chipselect_enables(7);

      -- Switch POTs between the two SIDs, based on the CIA port A upper
      -- bits.
      case cia1portb_out(7 downto 6) is
        when "01" =>
          potl_x <= pota_x;
          potl_y <= pota_y;
          potr_x <= potb_x;
          potr_y <= potb_y;
        when others =>
          potr_x <= pota_x;
          potr_y <= pota_y;
          potl_x <= potb_x;
          potl_y <= potb_y;
      end case;
      
      -- Reflect CIA lines for IEC bus driverse so that they
      -- can be read by the CIA
      if iec_clk_reflect /= iec_clk_fromcia then
        report "MAP: copying iec_clk_fromcia = "
          & std_logic'image(iec_clk_fromcia)
          & " to iec_clk_reflect.";
      end if;
      if iec_data_reflect /= iec_data_fromcia then
        report "MAP: copying iec_data_fromcia = "
          & std_logic'image(iec_data_fromcia)
          & " to iec_data_reflect.";
      end if;
      if iec_atn_reflect /= iec_atn_fromcia then
        report "MAP: copying iec_atn_fromcia = "
          & std_logic'image(iec_atn_fromcia)
          & " to iec_atn_reflect.";
      end if;
      iec_clk_reflect <= iec_clk_fromcia;
      iec_data_reflect <= iec_data_fromcia;
      iec_atn_reflect <= iec_atn_fromcia;
      iec_clk_o <= iec_clk_fromcia;
      iec_data_o <= iec_data_fromcia;
      iec_atn_o <= iec_atn_fromcia;
      
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
      if reset_high = '1' then
        ascii_key_presenting <= '0';
        ascii_key_buffered <= x"00";
        ascii_key_buffer_count <= 0;
      elsif ascii_key_next = '1' then
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
        if ascii_key_event_count /= x"FFFF" then
          ascii_key_event_count <= ascii_key_event_count + 1;
        else
          ascii_key_event_count <= x"0000";
        end if;
      end if;
      
    end if;
  end process;
  
  process (r,w,address,cia1portb_in,cia1porta_out,colourram_at_dc00,
           sector_buffer_mapped_read)
    variable temp : unsigned(19 downto 0);
  begin  -- process

--    data_o <= (others => 'H');
    
      -- @IO:GS $FFF8000-$FFFBFFF 16KB Kickstart/hypervisor ROM
      -- @IO:GS $FFF8000-$FFF80FC Hypervisor entry point when $D640-$D67F is written
      -- @IO:GS $FFF8100 Hypervisor entry point on reset (trap $40)
      -- @IO:GS $FFF8104 Hypervisor entry point on page fault (trap $41)
      -- @IO:GS $FFF8108 Hypervisor entry point on RESTORE long-press (trap $42)
      -- @IO:GS $FFF810C Hypervisor entry point on C=-TAB / ALT-TAB (trap $43)
      -- @IO:GS $FFF8110 Hypervisor entry point on FDC read (when virtualised) (trap $44)
      -- @IO:GS $FFF8114 Hypervisor entry point on FDC write (when virtualised) (trap $45)
      
      if address(19 downto 14)&"00" = x"F8" then
        kickstartcs <= cpu_hypervisor_mode;
      else
        kickstartcs <='0';
      end if;

      -- sdcard sector buffer: only mapped if no colour ram @ $DC00, and if
      -- the sectorbuffer mapping flag is set
      sectorbuffercs <= '0';
      sectorbuffercs_fast <= '0';
      report "fastio address = $" & to_hstring(address) severity note;
      
      if address(19 downto 16) = x"D"
        and address(15 downto 14) = "00"
        and address(11 downto 9)&'0' = x"E"
        and sector_buffer_mapped_read = '1' and colourram_at_dc00 = '0' then
        sectorbuffercs <= sbcs_en;
        report "selecting SD card sector buffer" severity note;
      end if;
      -- Also map SD card sector buffer at $FFD6000 - $FFD61FF regardless of
      -- VIC-IV IO mode and mapping of colour RAM
      -- @ IO:GS $FFD6E00-FFF - SD card direct access sector buffer
      -- @ IO:GS $FFD6C00-DFF - F011 floppy controller sector buffer
      if address(19 downto 12) = x"D6" then
        sectorbuffercs <= sbcs_en;
      end if;

      -- Same thing as above, but for the addr_fast bus, which is usually one clock ahead.
      if addr_fast(19 downto 16) = x"D"
        and addr_fast(15 downto 14) = "00"
        and addr_fast(11 downto 9)&'0' = x"E"
        and sector_buffer_mapped_read = '1' and colourram_at_dc00 = '0' then
        sectorbuffercs_fast <= sbcs_en;
        report "selecting SD card sector buffer" severity note;
      end if;
      -- Also map SD card sector buffer at $FFD6000 - $FFD61FF regardless of
      -- VIC-IV IO mode and mapping of colour RAM
      -- @ IO:GS $FFD6E00-FFF - SD card direct access sector buffer
      -- @ IO:GS $FFD6C00-DFF - F011 floppy controller sector buffer
      if addr_fast(19 downto 12) = x"D6" then
        sectorbuffercs_fast <= sbcs_en;
      end if;

      -- Now map the SIDs
      -- @IO:C64 $D440-$D47F = left SID
      -- @IO:C64 $D400-$D43F = right SID
      -- @IO:C64 $D480-$D4FF = repeated images of SIDs
      -- Presumably repeated through to $D5FF.  But we will repeat to $D4FF only
      -- so that we can use $D500-$D5FF for other stuff.
      case address(19 downto 8) is
        when x"D04" => leftsid_cs <= address(6) and lscs_en; rightsid_cs <= not address(6) and rscs_en;
        when x"D14" => leftsid_cs <= address(6) and lscs_en; rightsid_cs <= not address(6) and rscs_en;
        when x"D24" => leftsid_cs <= address(6) and lscs_en; rightsid_cs <= not address(6) and rscs_en;
        when x"D34" => leftsid_cs <= address(6) and lscs_en; rightsid_cs <= not address(6) and rscs_en;
        -- Some C64 dual-sid programs expect the 2nd sid to be at $D500, so
        -- we will make the SIDs visible at $D500 in c64 io context, and switched
        -- sides.
        when x"D05" => leftsid_cs <= not address(6) and lscs_en; rightsid_cs <= address(6) and rscs_en;
        when others => leftsid_cs <= '0'; rightsid_cs <= '0';
      end case;

      -- $D500 - $D5FF is not currently used.  Probably use some for FPU.
      
      -- $D600 - $D62F is reserved for C65 serial UART emulation for C65
      -- compatibility (C65 UART actually only has 7 registers).
      -- 6551 is not currently implemented, so this is just unmapped for now,
      -- except for any read values required to allow the C65 ROM to function.
      temp(15 downto 2) := unsigned(address(19 downto 6));
      temp(1 downto 0) := "00";
      if address(7 downto 4) /= x"3" then
        case temp(15 downto 0) is
          when x"D160" => c65uart_cs <= c65uart_en;
          when x"D260" => c65uart_cs <= c65uart_en;
          when x"D360" => c65uart_cs <= c65uart_en;
          when others => c65uart_cs <= '0';
        end case;
      else
        c65uart_cs <= '0';
        -- $D630-$D63F is thumbnail generator
        if address(19 downto 8) = x"D363" then
          thumbnail_cs <= c65uart_en;
        else
          thumbnail_cs <= '0';
        end if;
      end if;
      if address(19 downto 4) = x"D36E" then
        ethernet_cs <= ethernetcs_en;
      else
        ethernet_cs <= '0';
      end if;

      -- Hypervisor control (only visible from hypervisor mode) $D640 - $D67F
      -- The hypervisor is a CPU provided function.
      
      -- SD controller and miscellaneous hardware (microphone, accelerometer etc)
      -- uses $D680 - $D6FF
      temp(15 downto 3) := unsigned(address(19 downto 7));
      temp(2 downto 0) := "000";
      case temp(15 downto 0) is
        when x"D168" => sdcardio_cs <= sdcardio_en;
        when x"D268" => sdcardio_cs <= sdcardio_en;
        when x"D368" => sdcardio_cs <= sdcardio_en;
        when others => sdcardio_cs <= '0';
      end case;

      temp(15 downto 3) := unsigned(addr_fast(19 downto 7));
      temp(2 downto 0) := "000";
      case temp(15 downto 0) is
        when x"D168" => sdcardio_cs_fast <= sdcardio_en;
        when x"D268" => sdcardio_cs_fast <= sdcardio_en;
        when x"D368" => sdcardio_cs_fast <= sdcardio_en;
        when others => sdcardio_cs_fast <= '0';
      end case;

      -- F011 emulation registers
      temp(15 downto 1) := unsigned(address(19 downto 5));
      temp(0) := '0';
      case temp(15 downto 0) is
        when x"D108" => f011_cs <= sdcardio_en;
        when x"D208" => f011_cs <= sdcardio_en;
        when x"D308" => f011_cs <= sdcardio_en;
        when others => f011_cs <= '0';
      end case;

      -- Buffered UART registers at $D0Ex
      temp(15 downto 0) := unsigned(address(19 downto 4));
      case temp(15 downto 0) is
        when x"D10E" => buffereduart_cs <= sdcardio_en;
        when x"D20E" => buffereduart_cs <= sdcardio_en;
        when x"D30E" => buffereduart_cs <= sdcardio_en;
        when others => buffereduart_cs <= '0';
      end case;
            
      -- CPU uses $FFD{0,1,2,3}700 for DMAgic and other CPU-hosted IO registers.
      -- XXX is resolved in CPU
--      case address(19 downto 8) is
--        when x"D17" => cpuregs_cs <= '1';
--        when x"D27" => cpuregs_cs <= '1';
--        when x"D37" => cpuregs_cs <= '1';
--        when others => cpuregs_cs <= '0';
--      end case;
      
      -- Now map the CIAs.

      -- These are a bit fun, because they only get mapped if colour RAM isn't
      -- being mapped in $DC00-$DFFF using the C65 2K colour ram register
      cia1cs <='0';
      cia2cs <='0';
      if colourram_at_dc00='0' then
        case address(19 downto 8) is
          when x"D0C" => cia1cs <=cia1cs_en;
          when x"D1C" => cia1cs <=cia1cs_en;
          when x"D2C" => cia1cs <=cia1cs_en;
          when x"D3C" => cia1cs <=cia1cs_en;
          when x"D0D" => cia2cs <=cia2cs_en;
          when x"D1D" => cia2cs <=cia2cs_en;
          when x"D2D" => cia2cs <=cia2cs_en;
          when x"D3D" => cia2cs <=cia2cs_en;
          when others => null;
        end case;
      end if;

    report "CS lines: "
      & to_string(cia1cs&cia2cs&kickstartcs&sectorbuffercs&leftsid_cs&rightsid_cs&c65uart_cs&sdcardio_cs&thumbnail_cs);
  end process;

end behavioral;
