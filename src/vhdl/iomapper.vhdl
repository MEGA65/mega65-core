use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;
use work.cputypes.all;

entity iomapper is
  generic ( target : mega65_target_t;
            cpu_frequency : integer;
            num_eth_rx_buffers : integer := 4
             );
  port (cpuclock : in std_logic;
        clock200mhz : in std_logic;
        clock50mhz : in std_logic;
        phi0_1mhz : in std_logic;
        pixelclk : in std_logic;
        uartclock : in std_logic;

        dipsw_read : out std_logic_vector(7 downto 0);
        board_major : out unsigned(3 downto 0);
        board_minor : out unsigned(3 downto 0);
        
        floppy_last_gap : out unsigned(7 downto 0) := x"00";
        floppy_gap_strobe : out std_logic := '0';

        dd00_bits : out unsigned(1 downto 0) := "11";
        cpu_slow : in std_logic;

        accessible_row : out integer range 0 to 255 := 255;
        accessible_key : out unsigned(6 downto 0) := to_unsigned(127,7);
        dim_shift : out std_logic := '0';

        protected_hardware_in : in unsigned(7 downto 0);
        virtualised_hardware_in : in unsigned(7 downto 0);
        pal_mode : in std_logic;
        -- Enables for the various chip select lines
        chipselect_enables : in std_logic_vector(7 downto 0) := x"FF";

        cpuspeed : in unsigned(7 downto 0);
        reset : in std_logic;
        reset_out : out std_logic;
        irq : out std_logic;
        nmi : out std_logic;
        capslock_key : in std_logic;
        speed_gate : out std_logic;
        speed_gate_enable : in std_logic;
        hyper_trap : out std_logic;
        matrix_mode_trap : out std_logic;
        eth_load_enable : out std_logic;
        restore_key : in std_logic;
        osk_toggle_key : in std_logic;
        joyswap_key : in std_logic;
        restore_nmi : out std_logic;
        cpu_hypervisor_mode : in std_logic;
        hyper_trap_f011_read : out std_logic;
        hyper_trap_f011_write : out std_logic;
        hyper_trap_count : out unsigned(7 downto 0);
        viciv_frame_indicate : in std_logic;
        eth_hyperrupt : out std_logic;

        hw_errata_level : out unsigned(7 downto 0);
        hw_errata_enable_toggle : in std_logic := '0';
        hw_errata_disable_toggle : in std_logic := '0';

        max10_fpga_date : in unsigned(15 downto 0);
        max10_fpga_commit : in unsigned(31 downto 0);

        kbd_datestamp : in unsigned(13 downto 0);
        kbd_commit : in unsigned(31 downto 0);

        joy3 : in std_logic_vector(4 downto 0);
        joy4 : in std_logic_vector(4 downto 0);

        j21in : in std_logic_vector(11 downto 0);
        j21out : inout std_logic_vector(11 downto 0);
        j21ddr : out std_logic_vector(11 downto 0) := (others => '0');

        uart_char : out unsigned(7 downto 0);
        uart_char_valid : out std_logic := '0';
        uart_monitor_char : out unsigned(7 downto 0);
        uart_monitor_char_valid : out std_logic := '0';

        buffereduart_rx : in std_logic_vector(7 downto 0) := (others => '1');
        buffereduart_tx : out std_logic_vector(7 downto 0) := (others => '1');
        buffereduart_ringindicate : in std_logic_vector(7 downto 0);

        fm_left : in signed(15 downto 0) := x"0000";
        fm_right : in signed(15 downto 0) := x"0000";

        cpu_pcm_left : in signed(15 downto 0) := x"FFFF";
        cpu_pcm_right : in signed(15 downto 0) := x"FFFF";
        cpu_pcm_enable : in std_logic := '0';
        cpu_pcm_bypass : in std_logic := '0';
        pwm_mode_select : in std_logic := '1';

        disco_led_id : out unsigned(7 downto 0) := x"00";
        disco_led_val : out unsigned(7 downto 0) := x"00";
        disco_led_en : out std_logic := '0';

        cart_access_count : in unsigned(7 downto 0);

        fpga_temperature : in std_logic_vector(11 downto 0);
        address : in std_logic_vector(19 downto 0);
        addr_fast : in std_logic_vector(19 downto 0);
        r : in std_logic;
        w : in std_logic;
        data_i : in std_logic_vector(7 downto 0);
        data_o : out std_logic_vector(7 downto 0) := (others => 'Z');
        hyppo_rdata : out std_logic_vector(7 downto 0);
        sector_buffer_mapped : out std_logic;

        charrom_cs : out std_logic;

        key_scancode : in unsigned(15 downto 0);
        key_scancode_toggle : in std_logic;

        visual_keyboard_enable : out std_logic;
        osk_debug_display : out std_logic;
        zoom_en_osk : inout std_logic;
        zoom_en_always : inout std_logic;
        keyboard_at_top : out std_logic;
        alternate_keyboard : out std_logic;
        osk_key1 : out unsigned(7 downto 0);
        osk_key2 : out unsigned(7 downto 0);
        osk_key3 : out unsigned(7 downto 0);
        osk_key4 : out unsigned(7 downto 0);

        touch_key1 : in unsigned(7 downto 0);
        touch_key2 : in unsigned(7 downto 0);

        reg_isr_out : out unsigned(7 downto 0);
        imask_ta_out : out std_logic;

        drive_led0 : out std_logic := '0';
        drive_led2 : out std_logic := '0';
        drive_ledsd : out std_logic := '0';
        motor : out std_logic := '0';
        porto_out : out unsigned(7 downto 0) := x"ff";
        portp_out : out unsigned(7 downto 0);

        last_reset_source : in unsigned(2 downto 0);
        reset_monitor_count : in unsigned(11 downto 0);

        porta_pins : inout  std_logic_vector(7 downto 0) := (others => 'Z');
        portb_pins : inout  std_logic_vector(7 downto 0);
        keyboard_column8_out : out std_logic;
        key_left : in std_logic;
        key_up : in std_logic;

        fa_left_drain_n : out std_logic;
        fa_right_drain_n : out std_logic;
        fa_down_drain_n : out std_logic;
        fa_up_drain_n : out std_logic;
        fa_fire_drain_n : out std_logic;

        fb_left_drain_n : out std_logic;
        fb_right_drain_n : out std_logic;
        fb_down_drain_n : out std_logic;
        fb_up_drain_n : out std_logic;
        fb_fire_drain_n : out std_logic;

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

        rightsid_audio_out : out signed(17 downto 0);

        mouse_debug : in unsigned(7 downto 0);
        amiga_mouse_enable_a : out std_logic;
        amiga_mouse_enable_b : out std_logic;
        amiga_mouse_assume_a : out std_logic;
        amiga_mouse_assume_b : out std_logic;

        i2c_joya_fire : out std_logic;
        i2c_joya_up : out std_logic := '0';
        i2c_joya_down : out std_logic := '0';
        i2c_joya_left : out std_logic := '0';
        i2c_joya_right : out std_logic := '0';
        i2c_joyb_fire : out std_logic := '0';
        i2c_joyb_up : out std_logic := '0';
        i2c_joyb_down : out std_logic := '0';
        i2c_joyb_left : out std_logic := '0';
        i2c_joyb_right : out std_logic := '0';
        i2c_button2 : out std_logic := '0';
        i2c_button3 : out std_logic := '0';
        i2c_button4 : out std_logic := '0';
        i2c_black2 : out std_logic := '0';
        i2c_black3 : out std_logic := '0';
        i2c_black4 : out std_logic := '0';

         ----------------------------------------------------------------------
         -- Flash RAM for holding FPGA config
         ----------------------------------------------------------------------
         QspiDB : out unsigned(3 downto 0);
         QspiDB_in : in unsigned(3 downto 0);
         qspidb_oe : out std_logic;
         QspiCSn : out std_logic;
         qspi_clock : out std_logic;

         ----------------------------------------------------------------------
        -- CBM floppy serial port
        ----------------------------------------------------------------------
        iec_clk_en : out std_logic := '0';
        iec_data_en : out std_logic := '0';
        iec_data_o : out std_logic := '1';
        iec_reset : out std_logic := '1';
        iec_clk_o : out std_logic := '1';
        iec_atn_o : out std_logic := '1';
        iec_srq_o : out std_logic := '1';
        iec_srq_en : out std_logic := '0';
        iec_srq_external : in std_logic := 'Z';
        iec_data_external : in std_logic := 'Z';
        iec_clk_external : in std_logic := 'Z';

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
         f_rdata_loopback : out std_logic;


        ps2data : in std_logic;
        ps2clock : in std_logic;
        scancode_out : out std_logic_vector(12 downto 0);
        -- Widget board / MEGA65R2 keyboard
        widget_matrix_col_idx : out integer range 0 to 15 := 0;
        widget_matrix_col : in std_logic_vector(7 downto 0);
        widget_restore : in std_logic;
        widget_capslock : in std_logic;
        widget_joya : in std_logic_vector(4 downto 0);
        widget_joyb : in std_logic_vector(4 downto 0);


        pmoda : inout std_logic_vector(7 downto 0);

        hdmi_int : in std_logic;
        hdmi_scl : inout std_logic;
        hdmi_sda : inout std_logic;
        hpd_a : inout std_logic;

        uart_rx : in std_logic := '0';
        uart_tx : out std_logic;

        raster_number : in unsigned(11 downto 0);
        vicii_raster : in unsigned(11 downto 0);
        badline_toggle : in std_logic;
        pixel_stream_in : in unsigned (7 downto 0);
        pixel_red_in : in unsigned (7 downto 0);
        pixel_green_in : in unsigned (7 downto 0);
        pixel_blue_in : in unsigned (7 downto 0);
        pixel_y : in unsigned (11 downto 0);
        pixel_valid : in std_logic;
        pixel_newframe : in std_logic;
        pixel_newraster : in std_logic;

        monitor_instruction_strobe : in std_logic;
        monitor_pc : in unsigned(15 downto 0);
        monitor_opcode : in unsigned(7 downto 0);
        monitor_arg1 : in unsigned(7 downto 0);
        monitor_arg2 : in unsigned(7 downto 0);
        monitor_a : in unsigned(7 downto 0);
        monitor_b : in unsigned(7 downto 0);
        monitor_x : in unsigned(7 downto 0);
        monitor_y : in unsigned(7 downto 0);
        monitor_z : in unsigned(7 downto 0);
        monitor_sp : in unsigned(15 downto 0);
        monitor_p : in unsigned(7 downto 0);
        d031_write_toggle : in std_logic;

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

    ethernet_cpu_arrest : out std_logic;

    -------------------------------------------------------------------------
    -- Lines for the SDcard interface itself
    -------------------------------------------------------------------------
    cs_bo : out std_logic;
    sclk_o : out std_logic;
    mosi_o : out std_logic;
    miso_i : in  std_logic;
    cs2_bo : out std_logic;
    sclk2_o : out std_logic;
    mosi2_o : out std_logic;
    miso2_i : in  std_logic;

    ---------------------------------------------------------------------------
    -- Lines for other devices that we handle here
    ---------------------------------------------------------------------------
    aclMISO : in std_logic;
    aclMOSI : out std_logic := '0';
    aclSS : out std_logic := '0';
    aclSCK : out std_logic := '0';
    aclInt1 : in std_logic;
    aclInt2 : in std_logic;

    -- MEMs microphones
    micData0 : in std_logic;
    micData1 : in std_logic;
    micClk : out std_logic := '0';
    micLRSel : out std_logic := '0';
    headphone_mic : in std_logic;

    -- PDM audio output for headphones/line-out
    ampPWM_l : out std_logic := '0';
    ampPWM_r : out std_logic := '0';
    pcspeaker_left : out std_logic := '0';
    ampSD : out std_logic := '0';
    audio_left : out std_logic_vector(19 downto 0) := (others => '0');
    audio_right : out std_logic_vector(19 downto 0) := (others => '0');

    -- I2S audio channels
    i2s_master_clk : out std_logic := '0';
    i2s_master_sync : out std_logic := '0';
    i2s_slave_clk : in std_logic := '0';
    i2s_slave_sync : in std_logic := '0';
    pcm_modem_clk : out std_logic := '0';
    pcm_modem_sync_in : in std_logic := '0';
    pcm_modem_clk_in : in std_logic := '0';
    pcm_modem_sync : out std_logic := '0';
    i2s_speaker_data_out : out std_logic := '0';
    pcm_modem1_data_in : in std_logic := '0';
    pcm_modem2_data_in : in std_logic := '0';
    pcm_modem1_data_out : out std_logic := '0';
    pcm_modem2_data_out : out std_logic := '0';
    pcm_bluetooth_data_in : in std_logic := '0';
    pcm_bluetooth_data_out : out std_logic := '0';
    pcm_bluetooth_clk_in : in std_logic := '0';
    pcm_bluetooth_sync_in : in std_logic := '0';

    tmpSDA : inout std_logic := '0';
    tmpSCL : inout std_logic := '0';
    tmpInt : in std_logic;
    tmpCT : in std_logic;

    i2c1SDA : inout std_logic := '0';
    i2c1SCL : inout std_logic := '0';    
    
    grove_sda : inout std_logic;
    grove_scl : inout std_logic;

    board_sda : inout std_logic;
    board_scl : inout std_logic;

    lcdpwm : out std_logic := '0';
    touchSDA : inout std_logic;
    touchSCL : inout std_logic;

    dipsw_hi : in std_logic_vector(7 downto 5) := (others => '0');
    dipsw : in std_logic_vector(4 downto 0);
    sw : in std_logic_vector(15 downto 0);
    btn : in std_logic_vector(4 downto 0);
    seg_led : out unsigned(31 downto 0) := (others => '0');

    -- Touch interface
    touch1_valid : out std_logic;
    touch1_x : out unsigned(13 downto 0) := (others => '0');
    touch1_y : out unsigned(11 downto 0) := (others => '0');
    touch2_valid : out std_logic;
    touch2_x : out unsigned(13 downto 0) := (others => '0');
    touch2_y : out unsigned(11 downto 0) := (others => '0');

    viciii_iomode : in std_logic_vector(1 downto 0);

    hyppo_address : in std_logic_vector(13 downto 0);

    colourram_at_dc00 : in std_logic

    );
end iomapper;

architecture behavioral of iomapper is

  signal sid_mode : unsigned(3 downto 0); -- 1=8580, 0=6581

  signal the_button : std_logic;
  signal i2c_joya_fire_int : std_logic := '1';

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

  signal cs_driverom : std_logic;
  signal cs_driveram : std_logic;
  signal drive_clock_cycle_strobe : std_logic := '1';
  signal drive_reset : std_logic := '1';
  signal drive_connect : std_logic := '1';
  signal sd1541_data : unsigned(7 downto 0) := (others => '0');
  signal sd1541_ready_toggle : std_logic := '0';
  signal sd1541_request_toggle : std_logic := '0';
  signal sd1541_enable : std_logic := '0';
  signal sd1541_track : unsigned(5 downto 0) := (others => '0');

  signal hyppocs : std_logic;

  signal reset_high : std_logic;

  signal combined_scancode_toggle : std_logic := '0';
  signal internal_combined_scancode_toggle : std_logic := '0';
  signal combined_scancode : unsigned(15 downto 0) := to_unsigned(0,16);
  signal last_key_scancode_toggle : std_logic := '0';
  signal last_eth_scancode_toggle : std_logic := '0';
  signal eth_scancode_toggle : std_logic := '0';
  signal eth_scancode : unsigned(15 downto 0) := to_unsigned(0,16);

  signal capslock_from_keymapper : std_logic := '1';
  signal key_debug : std_logic_vector(7 downto 0);
  signal widget_disable : std_logic;
  signal ps2_disable : std_logic;
  signal joykey_disable : std_logic;
  signal joyreal_disable : std_logic;
  signal virtual_disable : std_logic;
  signal physkey_disable : std_logic;
  signal joyswap : std_logic;

  signal restore_up_count : unsigned(7 downto 0) := x"00";
  signal restore_down_count : unsigned(7 downto 0) := x"00";

  signal vfpga_cs : std_logic;

  signal cia1cs : std_logic;
  signal cia2cs : std_logic;

  signal i2cperipherals_cs : std_logic;
  signal i2chdmi_cs : std_logic;
  signal grove_cs : std_logic;
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
  signal leftsid_audio : signed(17 downto 0);
  signal rightsid_cs : std_logic;
  signal rightsid_audio : signed(17 downto 0);
  signal frontsid_cs : std_logic;
  signal frontsid_audio : signed(17 downto 0) := to_signed(0,18);
  signal backsid_cs : std_logic;
  signal backsid_audio : signed(17 downto 0);

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
  signal buffer_offset : unsigned(11 downto 0);
  signal buffer_address : unsigned(11 downto 0);
  signal buffer_rdata : unsigned(7 downto 0);
  signal debug_vector : unsigned(63 downto 0);

  signal keyboard_column8_select : std_logic;

  signal key_valid : std_logic := '0';
  signal last_key_valid : std_logic := '0';
  signal ascii_key : unsigned(7 downto 0) := x"00";
  signal petscii_key : unsigned(7 downto 0) := x"00";
  signal bucky_key : std_logic_vector(6 downto 0) := (others => '0');
  signal key_presenting : std_logic := '0';
  signal ascii_key_buffered : unsigned(7 downto 0) := x"00";
  signal petscii_key_buffered : unsigned(7 downto 0) := x"ff";
  signal bucky_key_buffered : std_logic_vector(6 downto 0) := (others => '0');
  signal key_queue_flush : std_logic;
  type key_buffer_t is array(0 to 3) of unsigned(7 downto 0);
  type bucky_key_buffer_t is array(0 to 3) of std_logic_vector(6 downto 0);
  signal key_buffer_count : integer range 0 to 4 := 0;
  signal ascii_key_buffer : key_buffer_t;
  signal ascii_key_next : std_logic := '0';
  signal petscii_key_buffer : key_buffer_t;
  signal petscii_key_next : std_logic := '0';
  signal bucky_key_buffer : bucky_key_buffer_t;

  signal sd_bitbash : std_logic := '0';
  signal sd_interface_select : std_logic := '0';
  signal sd_bitbash_cs_bo : std_logic;
  signal sd_bitbash_sclk_o : std_logic;
  signal sd_bitbash_mosi_o : std_logic;
  signal sd_bitbash_miso_i : std_logic;
  signal cs_bo_sd : std_logic;
  signal sclk_o_sd : std_logic;
  signal mosi_o_sd : std_logic;
  signal miso_i_sd : std_logic;

  signal matrix_segment_num : std_logic_vector(7 downto 0) := (others => '0');
  signal matrix_segment_out : std_logic_vector(7 downto 0);
  signal virtual_key1 : std_logic_vector(7 downto 0);
  signal virtual_key2 : std_logic_vector(7 downto 0);
  signal virtual_key3 : std_logic_vector(7 downto 0);

  signal keyboard_scan_mode : std_logic_vector(1 downto 0) := "11";
  signal keyboard_scan_rate : unsigned(7 downto 0);

  signal ef_latch : std_logic := '0';
  signal ef_timeout : integer range 0 to 31 := 0;

  signal e0_latch : std_logic := '0';
  signal e0_timeout : integer range 0 to 31 := 0;

  signal dummy_e : std_logic_vector(7 downto 0);
  signal dummy_g : std_logic_vector(7 downto 0) := x"FF";
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

  signal audio_mix_reg : unsigned(7 downto 0) := x"FF";
  signal audio_mix_write : std_logic := '0';
  signal audio_mix_wdata : unsigned(15 downto 0) := x"FFFF";
  signal audio_mix_rdata : unsigned(15 downto 0) := x"FFFF";
  signal audio_loopback : signed(15 downto 0) := x"FFFF";
  signal pcm_left : signed(15 downto 0) := x"FFFF";
  signal pcm_right : signed(15 downto 0) := x"FFFF";

  signal cpu_ethernet_stream : std_logic;

  signal touch_key1_driver : unsigned(7 downto 0);
  signal touch_key2_driver : unsigned(7 downto 0);
  signal touch1_valid_int : std_logic := '0';

  signal userport_in : std_logic_vector(7 downto 0) := x"FF";
  signal userport_out : std_logic_vector(7 downto 0) := x"FF";

  signal sd_interface_select_internal : std_logic := '0';

  signal address_next_1541 : unsigned(15 downto 0);

  -- Used to divide 40MHz cpuclock down to get 1541 CPU clock
  signal drive_cycle_interval : integer range 0 to 40 := 40;
  signal drive_cycle_countdown : integer range 0 to 40 := 0;

  signal volume_knob1 : unsigned(15 downto 0) := (others => '0');
  signal volume_knob2 : unsigned(15 downto 0) := (others => '0');
  signal volume_knob3 : unsigned(15 downto 0) := (others => '0');
  signal volume_knob1_target : unsigned(3 downto 0);
  signal volume_knob2_target : unsigned(3 downto 0);
  signal volume_knob3_target : unsigned(3 downto 0);

  signal filter_table_addr0 : integer range 0 to 2047;
  signal filter_table_val0 : unsigned(15 downto 0);
  signal filter_table_addr1 : integer range 0 to 2047;
  signal filter_table_val1 : unsigned(15 downto 0);
  signal filter_table_addr2 : integer range 0 to 2047;
  signal filter_table_val2 : unsigned(15 downto 0);
  signal filter_table_addr3 : integer range 0 to 2047;
  signal filter_table_val3 : unsigned(15 downto 0);

  signal accessible_key_event : unsigned(7 downto 0);
  signal accessible_key_enable : std_logic;

  signal dd00_bits_out : std_logic_vector(1 downto 0);
  signal dd00_bits_ddr : std_logic_vector(1 downto 0);

  signal matrix_disable_modifiers : std_logic;

  signal grove_rtc_present : std_logic;
  signal rtc_reg : unsigned(7 downto 0);
  signal rtc_val : unsigned(7 downto 0);

  signal eth_load_enable_int : std_logic := '0';

  signal board_major_int : unsigned(3 downto 0);
  signal board_minor_int : unsigned(3 downto 0) := x"0";

begin

  block1: block
  begin
  hypporom : entity work.hyppo port map (
    clk     => cpuclock,
    address => hyppo_address,
    address_i => address(13 downto 0),
    we      => w,
    cs      => hyppocs,
    data_o  => hyppo_rdata,
    data_i  => data_i
    );
  end block;

  access0: block
  begin
    accesskbd0: entity work.accessible_keyboard port map (
      pixelclock => pixelclk,
      cpuclock => cpuclock,

      the_button => the_button,

      accessible_row => accessible_row,
      accessible_key => accessible_key,
      accessible_key_event => accessible_key_event,
      accessible_key_enable => accessible_key_enable

      );
  end block;


  -- IRQ line is wire-anded together as if it had a pullup.
  irq <= cia1_irq and ethernet_irq and uart_irq;

  block2: block
  begin
  framepacker0: entity work.framepacker port map (
    cpuclock => cpuclock,
    pixelclock => pixelclk,
    ethclock => clock50mhz,
    pal_mode => pal_mode,
    hypervisor_mode => cpu_hypervisor_mode,
    thumbnail_cs => thumbnail_cs,

    video_or_cpu => cpu_ethernet_stream,

    -- Video stream for beaming via ethernet
    pixel_stream_in => pixel_stream_in,
    pixel_red_in => pixel_red_in,
    pixel_green_in => pixel_green_in,
    pixel_blue_in => pixel_blue_in,
    pixel_y => pixel_y,
    pixel_valid => pixel_valid,
    pixel_newframe => pixel_newframe,
    pixel_newraster => pixel_newraster,

    -- CPU status log for real-time debug
    monitor_instruction_strobe => monitor_instruction_strobe,
    monitor_pc => monitor_pc,
    monitor_opcode => monitor_opcode,
    monitor_arg1 => monitor_arg1,
    monitor_arg2 => monitor_arg2,
    monitor_a => monitor_a,
    monitor_b => monitor_b,
    monitor_x => monitor_x,
    monitor_y => monitor_y,
    monitor_z => monitor_z,
    monitor_sp => monitor_sp,
    monitor_p => monitor_p,

    buffer_moby_toggle => buffer_moby_toggle,
    buffer_offset => buffer_offset,
    buffer_address => buffer_address,
    buffer_rdata => buffer_rdata,
    debug_vector => debug_vector,

    fastio_addr => unsigned(address(19 downto 0)),
    fastio_write => w,
    std_logic_vector(fastio_rdata) => data_o,
    fastio_read => r,
    fastio_wdata => unsigned(data_i)
    );
  end block;

  -- the Internal 1541 does use up lots of precious space and
  -- this causes problems with the mega65r2 build. So we only
  -- want the 1541 and it's 6502 CPU placed if we are not
  -- building the mega65r2 target.
  -- WARNING/TODO: drive1541 will be undefined. This does
  -- currently not porduce any problems, as it is not yet used
  -- anywhere in the design! But it might if this changes...
  drive1541_mega65r3:
  if false generate
    drive1541: entity work.internal1541
      port map (
        clock => cpuclock,
        fastio_read => r,
        fastio_write => w,
        fastio_address => unsigned(address(19 downto 0)),
        fastio_wdata => unsigned(data_i),
        std_logic_vector(fastio_rdata) => data_o,
        cs_driverom => cs_driverom,
        cs_driveram => cs_driveram,
        drive_clock_cycle_strobe => drive_clock_cycle_strobe,
        drive_reset_n => drive_reset,
        drive_suspend => cpu_hypervisor_mode,

        -- Debug output of 1541 CPU next address
        address_next => address_next_1541,

        iec_atn_i => '1',
        iec_clk_i => '1',
        iec_data_i => '1',
        iec_srq_i => '1',

        sd_data_byte => sd1541_data,
        sd_data_ready_toggle => sd1541_ready_toggle,
        sd_data_request_toggle => sd1541_request_toggle,
        sd_1541_enable => sd1541_enable,
        sd_1541_track => sd1541_track
      );
  end generate drive1541_mega65r3;

  block3: block
  begin
    cia1: entity work.cia6526
      generic map ( unit => x"1")
      port map (
    cpuclock => cpuclock,
    phi0_1mhz => phi0_1mhz,
    todclock => viciv_frame_indicate,
    cpu_slow => cpu_slow,
    reset => reset,
    irq => cia1_irq,
    hypervisor_mode => cpu_hypervisor_mode,
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
    cpuclock => cpuclock,
    phi0_1mhz => phi0_1mhz,
    todclock => viciv_frame_indicate,
    cpu_slow => cpu_slow,
    reset => reset,
    irq => nmi,
    hypervisor_mode => cpu_hypervisor_mode,
    cs => cia2cs,
    fastio_address => unsigned(address(7 downto 0)),
    fastio_write => w,
    std_logic_vector(fastio_rdata) => data_o,
    fastio_wdata => unsigned(data_i),

    -- CIA port a (VIC-II bank select + IEC serial port)
    -- XXX Implement connection to internal 1541 drive if drive_connect is asserted
    portain(2 downto 0) => (others => '1'),
    portain(3) => iec_atn_reflect, -- IEC serial ATN
    -- We reflect the output values for CLK and DATA straight back in,
    -- as they are needed to be visible for the DOS routines to work.
    portain(4) => iec_clk_reflect,
    portain(5) => iec_data_reflect,
    portain(6) => iec_clk_external,
    portain(7) => iec_data_external,
    portaout(2) => dummy(2),
    portaout(1 downto 0) => dd00_bits_out,
    portaout(3) => iec_atn_fromcia,
    portaout(4) => iec_clk_fromcia,
    portaout(5) => iec_data_fromcia,
    portaout(7 downto 6) => dummy(4 downto 3),
    portaddr(3 downto 2) => dummy(8 downto 7),
    portaddr(4) => iec_clk_en,
    portaddr(5) => iec_data_en,
    portaddr(7 downto 6) => dummy(10 downto 9),
    portaddr(1 downto 0) => dd00_bits_ddr,

    -- CIA port b (user port)
    -- As the MEGA65 has no user port, we don't connect this normally
    -- Instead, we support a cartridge that emulates one of those joy3/4
    -- adapters

    portbin => userport_in,
    portbout => userport_out,
    flagin => '1',
    spin => iec_srq_external,
    spout => iec_srq_o,
    sp_ddr => iec_srq_en,
    countin => '1'
    );
  end block;

  block4b: block
  begin
    c65uart0: entity work.c65uart
      generic map ( target => target  )
      port map (
      pixelclock => pixelclk,
      cpuclock => cpuclock,
      c65uart_cs => c65uart_cs,
      sid_mode => sid_mode,
      osk_toggle_key => osk_toggle_key,
      joyswap_key => joyswap_key,
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
      portg(7) => hpd_a, -- ADV7511 hot plug detect
      portg(6) => dummy_g(6),
      portg(5) => sd_bitbash,
      portg(4) => sd_bitbash_cs_bo,
      portg(3) => sd_bitbash_sclk_o,
      portg(2) => sd_bitbash_mosi_o,
      -- @IO:GS $D60D.1 - Internal 1541 drive reset
      -- @IO:GS $D60D.0 - Internal 1541 drive connect (1= use internal 1541 instead of IEC drive connector)
      portg(1) => drive_reset,
      portg(0) => drive_connect,

      last_reset_source => last_reset_source,
      reset_monitor_count => reset_monitor_count,

      accessible_key_event => accessible_key_event,
      accessible_key_enable => accessible_key_enable,
      accessible_key_extradim => dim_shift,

      disco_led_en => disco_led_en,
      disco_led_id => disco_led_id,
      disco_led_val => disco_led_val,

      max10_fpga_date => max10_fpga_date,
      max10_fpga_commit => max10_fpga_commit,
      kbd_datestamp => kbd_datestamp,
      kbd_commit => kbd_commit,

      board_major => board_major_int,
      board_minor => board_minor_int,

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
      portf(7) => zoom_en_osk,
      portf(6) => zoom_en_always,
      portf(5 downto 0) => pmoda(5 downto 0),
      porth => std_logic_vector(ascii_key_buffered),
      porth_write_strobe => ascii_key_next,
      porto_write_strobe => petscii_key_next,
      matrix_disable_modifiers => matrix_disable_modifiers,
      porti(6 downto 0) => std_logic_vector(bucky_key(6 downto 0)),
      porti(7) => '0',
      portj_out => matrix_segment_num,
      portj_in => std_logic_vector(matrix_segment_out),
      portk_out(6 downto 0) => virtual_key1(6 downto 0),
      portk_out(7) => visual_keyboard_enable,
      portl_out(6 downto 0) => virtual_key2(6 downto 0),
      portl_out(7) => keyboard_at_top,
      portm_out(6 downto 0) => virtual_key3(6 downto 0),
      portm_out(7) => alternate_keyboard,
      portn_out => keyboard_scan_rate,
      porto => petscii_key_buffered,
      portp_out => portp_out,
      portq_in => address_next_1541(7 downto 0),
      joya_rotate => joya_rotate,
      joyb_rotate => joyb_rotate,
      osk_debug_display => osk_debug_display,
      joyswap => joyswap,
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
      potb_y => potb_y,

      bucky_key_buffered => bucky_key_buffered,
      key_presenting => key_presenting,
      key_queue_flush => key_queue_flush
      );
  end block;

  block5: block
  begin
    kc0 : entity work.keyboard_complex
      port map (
      reset_in => reset,
      matrix_mode_in => protected_hardware_in(6),
      viciv_frame_indicate => viciv_frame_indicate,
      matrix_disable_modifiers => matrix_disable_modifiers,

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

      joyswap => joyswap,

      joya_rotate => joya_rotate,
      joyb_rotate => joyb_rotate,

      cpuclock       => cpuclock,
    restore_out => restore_nmi,
    keyboard_restore => restore_key,
    keyboard_capslock => capslock_key,
    key_left => key_left,
    key_up => key_up,

    key1 => unsigned(virtual_key1),
    key2 => unsigned(virtual_key2),
    key3 => unsigned(virtual_key3),

    touch_key1 => touch_key1_driver,
    touch_key2 => touch_key2_driver,

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

    widget_matrix_col_idx => widget_matrix_col_idx,
    widget_matrix_col => widget_matrix_col,
    widget_restore => widget_restore,
    widget_capslock => widget_capslock,
    widget_joya => widget_joya,
    widget_joyb => widget_joyb,


      -- remote keyboard input via ethernet / serial monitor
      -- We combine ethernet and uart_monitor inputs together
    eth_hyperrupt => eth_hyperrupt,
    eth_keycode_toggle => combined_scancode_toggle,
    eth_keycode => combined_scancode,

    -- ASCII feed via hardware keyboard scanner
    key_valid => key_valid,
    ascii_key => ascii_key,
    petscii_key => petscii_key,
    bucky_key => bucky_key(6 downto 0)

    );
  end block;

 sidcblock: block
  begin
    sidc: entity work.sid_coeffs_mux port map (
      clk => cpuclock,
      addr0 => filter_table_addr0,
      val0 => filter_table_val0,
      addr1 => filter_table_addr1,
      val1 => filter_table_val1,
      addr2 => filter_table_addr2,
      val2 => filter_table_val2,
      addr3 => filter_table_addr3,
      val3 => filter_table_val3
      );
    end block;

  block6: block
  begin
    leftsid: entity work.sid6581 port map (
    clk_1MHz => phi0_1mhz,
    cpuclock => cpuclock,
    reset => reset_high,
    cs => leftsid_cs,
    mode => sid_mode(0),
    we => w,
    addr => unsigned(address(4 downto 0)),
    di => unsigned(data_i),
    std_logic_vector(do) => data_o,
    pot_x => potl_x,
    pot_y => potl_y,
    signed_audio => leftsid_audio,
    filter_table_addr => filter_table_addr0,
    filter_table_val => filter_table_val0
    );
  end block;

  block7: block
  begin
  rightsid: entity work.sid6581 port map (
    clk_1MHz => phi0_1mhz,
    cpuclock => cpuclock,
    reset => reset_high,
    cs => rightsid_cs,
    mode => sid_mode(1),
    we => w,
    addr => unsigned(address(4 downto 0)),
    di => unsigned(data_i),
    std_logic_vector(do) => data_o,
    pot_x => potr_x,
    pot_y => potr_y,
    signed_audio => rightsid_audio,
    filter_table_addr => filter_table_addr1,
    filter_table_val => filter_table_val1
    );
  end block;

 block6b: block
  begin
    frontsid: entity work.sid6581 port map (
    clk_1MHz => phi0_1mhz,
    cpuclock => cpuclock,
    reset => reset_high,
    cs => frontsid_cs,
    mode => sid_mode(2),
    we => w,
    addr => unsigned(address(4 downto 0)),
    di => unsigned(data_i),
    std_logic_vector(do) => data_o,
    pot_x => potl_x,
    pot_y => potl_y,
    signed_audio => frontsid_audio,
    filter_table_addr => filter_table_addr2,
    filter_table_val => filter_table_val2
    );
  end block;

  block7b: block
  begin
  backsid: entity work.sid6581 port map (
    clk_1MHz => phi0_1mhz,
    cpuclock => cpuclock,
    reset => reset_high,
    cs => backsid_cs,
    mode => sid_mode(3),
    we => w,
    addr => unsigned(address(4 downto 0)),
    di => unsigned(data_i),
    std_logic_vector(do) => data_o,
    pot_x => potr_x,
    pot_y => potr_y,
    signed_audio => backsid_audio,
    filter_table_addr => filter_table_addr3,
    filter_table_val => filter_table_val3
    );
  end block;

  vfpga:
    if false generate
      vfpga0:        entity work.vfpga_wrapper_8bit port map (
        pixel_clock => pixelclk,
        clock => cpuclock,
        cs_vfpga => vfpga_cs,
        hypervisor_mode_in => cpu_hypervisor_mode,

        fastio_address => unsigned(address(19 downto 0)),
        fastio_write => w,
        std_logic_vector(fastio_rdata) => data_o,
        fastio_read => r,
        fastio_wdata => unsigned(data_i)
        );
    end generate;


  eth0: if target /= megaphoner4 and target /= qmtecha100t and target /= qmtecha200t and target /= qmtechk325t generate
    ethernet0 : entity work.ethernet
      generic map (
        num_buffers => num_eth_rx_buffers
        )
      port map (
        clock50mhz => clock50mhz,
        clock200 => clock200mhz,
        clock => cpuclock,
        reset => reset,
        irq => ethernet_irq,
        ethernet_cs => ethernet_cs,

        cpu_ethernet_stream => cpu_ethernet_stream,

        -- 2nd dipswitch enables remote keyboard input and remote control
        -- of MEGA65 via ethernet
        eth_remote_control => dipsw(1),
        eth_load_enable => eth_load_enable_int,

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
        buffer_offset => buffer_offset,
        buffer_address => buffer_address,
        buffer_rdata => buffer_rdata,
        debug_vector => debug_vector,
        raster_number => raster_number,
        vicii_raster => vicii_raster,
        badline_toggle => badline_toggle,
        d031_write_toggle => d031_write_toggle,
        instruction_strobe => monitor_instruction_strobe,
        cpu_arrest => ethernet_cpu_arrest,

        eth_keycode_toggle => eth_scancode_toggle,
        eth_keycode => eth_scancode,

        fastio_addr => unsigned(address),
        fastio_write => w,
        fastio_read => r,
        std_logic_vector(fastio_rdata) => data_o,
        fastio_wdata => unsigned(data_i)
        );
  end generate;

  buffered_uart0 : entity work.buffereduart port map (
    clock => cpuclock,
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

  audio0: entity work.audio_complex
    generic map ( clock_frequency => cpu_frequency )
    port map (
    cpuclock => cpuclock,

    volume_knob1_target => volume_knob1_target,
    volume_knob2_target => volume_knob2_target,
    volume_knob3_target => volume_knob3_target,

    volume_knob1 => volume_knob1,
    volume_knob2 => volume_knob2,
    volume_knob3 => volume_knob3,

    audio_mix_reg => audio_mix_reg,
    audio_mix_write => audio_mix_write,
    audio_mix_wdata => audio_mix_wdata,
    audio_mix_rdata => audio_mix_rdata,
    audio_loopback => audio_loopback,

    fm_left => fm_left,
    fm_right => fm_right,

    pcm_left => pcm_left,
    pcm_right => pcm_right,
    cpu_pcm_left => cpu_pcm_left,
    cpu_pcm_right => cpu_pcm_right,
    cpu_pcm_enable => cpu_pcm_enable,
    cpu_pcm_bypass => cpu_pcm_bypass,
    pwm_mode_select => pwm_mode_select,

    -- MEMS microphone inputs (2 x strings of 2)
    micData0 => micData0,
    micData1 => micData1,
    micClk => micClk,
    micLRSel => micLRSel,
    headphone_mic => headphone_mic,

    leftsid_audio => leftsid_audio,
    rightsid_audio => rightsid_audio,
    frontsid_audio => frontsid_audio,
    backsid_audio => backsid_audio,

    -- PDM audio output for various boards
    ampSD => ampSD,
    ampPWM_l => ampPWM_l,
    ampPWM_r => ampPWM_r,
    pcspeaker_left => pcspeaker_left,
    audio_left => audio_left,
    audio_right => audio_right,

    -- I2S interfaces for various boards
    i2s_master_clk => i2s_master_clk,
    i2s_master_sync => i2s_master_sync,
    i2s_slave_clk => i2s_slave_clk,
    i2s_slave_sync => i2s_slave_sync,
    pcm_modem_clk => pcm_modem_clk,
    pcm_modem_sync => pcm_modem_sync,
    pcm_modem_clk_in => pcm_modem_clk_in,
    pcm_modem_sync_in => pcm_modem_sync_in,
    i2s_speaker_data_out => i2s_speaker_data_out,
    pcm_modem1_data_in => pcm_modem1_data_in,
    pcm_modem2_data_in => pcm_modem2_data_in,
    pcm_modem1_data_out => pcm_modem1_data_out,
    pcm_modem2_data_out => pcm_modem2_data_out,
    pcm_bluetooth_sync_in => pcm_bluetooth_sync_in,
    pcm_bluetooth_clk_in => pcm_bluetooth_clk_in,
    pcm_bluetooth_data_in => pcm_bluetooth_data_in,
    pcm_bluetooth_data_out => pcm_bluetooth_data_out

    );

  ----------------------------------------------------------------------------------
  -- Grove I2C bus. Currently only used for allowing an external RTC
  ----------------------------------------------------------------------------------
  i2c_grove:
  if target = mega65r3 or target = mega65r4 or target = mega65r5 or target = mega65r6 generate
    grove0: entity work.grove_i2c
      generic map ( clock_frequency => cpu_frequency )
      port map (
        clock => cpuclock,

        cs => grove_cs,

        sda => grove_sda,
        scl => grove_scl,

        grove_rtc_present => grove_rtc_present,
        reg_out => rtc_reg,
        val_out => rtc_val,

        fastio_addr => unsigned(address),
        fastio_write => w,
        fastio_read => r,
        fastio_wdata => unsigned(data_i),
        std_logic_vector(fastio_rdata) => data_o
    );
  end generate;

  -- XXX I2C bus of the MEGAphone R4 is currently disabled, as it is tied to
  -- the OrangeCrab as well.  We need to separate these two.
  i2cperiph_megaphone:
  if (target = megaphoner1) generate
    i2c1: entity work.i2c_wrapper
      generic map ( clock_frequency => cpu_frequency )
      port map (
      clock => cpuclock,
      cs => i2cperipherals_cs,

      sda => i2c1SDA,
      scl => i2c1SCL,

      adc1_out => volume_knob1,
      adc2_out => volume_knob2,
      adc3_out => volume_knob3,

      i2c_joya_fire => i2c_joya_fire_int,
      i2c_joya_up => i2c_joya_up,
      i2c_joya_down => i2c_joya_down,
      i2c_joya_left => i2c_joya_left,
      i2c_joya_right => i2c_joya_right,
      i2c_joyb_fire => i2c_joyb_fire,
      i2c_joyb_up => i2c_joyb_up,
      i2c_joyb_down => i2c_joyb_down,
      i2c_joyb_left => i2c_joyb_left,
      i2c_joyb_right => i2c_joyb_right,
      i2c_button2 => i2c_button2,
      i2c_button3 => i2c_button3,
      i2c_button4 => i2c_button4,
      i2c_black2 => i2c_black2,
      i2c_black3 => i2c_black3,
      i2c_black4 => i2c_black4,

      fastio_addr => unsigned(address),
      fastio_write => w,
      fastio_read => r,
      fastio_wdata => unsigned(data_i),
      std_logic_vector(fastio_rdata) => data_o

    );
  end generate i2cperiph_megaphone;

  i2cperiph_mega65r5_specific:
  if target = mega65r5 or target = mega65r6 generate
    i2c1: entity work.mega65r5_board_i2c
      generic map ( clock_frequency => cpu_frequency)
      port map (
      clock => cpuclock,

      dipsw_read => dipsw_read,
      board_major => board_major_int,
      board_minor => board_minor_int,
    
      sda => board_sda,
      scl => board_scl

      );
    i2c2: entity work.edid_i2c
      generic map ( clock_frequency => cpu_frequency)
      port map (
      clock => cpuclock,
      cs => i2chdmi_cs,

      sda => hdmi_sda,
      scl => hdmi_scl,

      fastio_addr => unsigned(address),
      fastio_write => w,
      fastio_read => r,
      fastio_wdata => unsigned(data_i),
      std_logic_vector(fastio_rdata) => data_o

    );
  end generate i2cperiph_mega65r5_specific;

  

  
  i2cperiph_mega65r4:
  if (target = mega65r4) or (target = mega65r5) or (target = mega65r6) generate
    i2c1: entity work.mega65r4_i2c
      generic map ( clock_frequency => cpu_frequency)
      port map (
      clock => cpuclock,
      cs => i2cperipherals_cs,

      grove_rtc_present => grove_rtc_present,
      reg_in => rtc_reg,
      val_in => rtc_val,

      sda => i2c1SDA,
      scl => i2c1SCL,

      fastio_addr => unsigned(address),
      fastio_write => w,
      fastio_read => r,
      fastio_wdata => unsigned(data_i),
      std_logic_vector(fastio_rdata) => data_o

      );
    i2c2: entity work.edid_i2c
      generic map ( clock_frequency => cpu_frequency)
      port map (
      clock => cpuclock,
      cs => i2chdmi_cs,

      sda => hdmi_sda,
      scl => hdmi_scl,

      fastio_addr => unsigned(address),
      fastio_write => w,
      fastio_read => r,
      fastio_wdata => unsigned(data_i),
      std_logic_vector(fastio_rdata) => data_o

    );
  end generate i2cperiph_mega65r4;

  i2cperiph_mega65r3:
  if target = mega65r3 generate
    i2c1: entity work.mega65r3_i2c
      generic map ( clock_frequency => cpu_frequency)
      port map (
      clock => cpuclock,
      cs => i2cperipherals_cs,

      grove_rtc_present => grove_rtc_present,
      reg_in => rtc_reg,
      val_in => rtc_val,

      sda => i2c1SDA,
      scl => i2c1SCL,

      fastio_addr => unsigned(address),
      fastio_write => w,
      fastio_read => r,
      fastio_wdata => unsigned(data_i),
      std_logic_vector(fastio_rdata) => data_o

      );
    i2c2: entity work.edid_i2c
      generic map ( clock_frequency => cpu_frequency)
      port map (
      clock => cpuclock,
      cs => i2chdmi_cs,

      sda => hdmi_sda,
      scl => hdmi_scl,

      fastio_addr => unsigned(address),
      fastio_write => w,
      fastio_read => r,
      fastio_wdata => unsigned(data_i),
      std_logic_vector(fastio_rdata) => data_o

    );
  end generate i2cperiph_mega65r3;

  i2cperiph_mega65r2:
  if target = mega65r2 generate
    i2c1: entity work.mega65r2_i2c
      generic map ( clock_frequency => cpu_frequency)
      port map (
      clock => cpuclock,
      cs => i2cperipherals_cs,

      sda => i2c1SDA,
      scl => i2c1SCL,

      fastio_addr => unsigned(address),
      fastio_write => w,
      fastio_read => r,
      fastio_wdata => unsigned(data_i),
      std_logic_vector(fastio_rdata) => data_o

    );
    i2c2: entity work.hdmi_i2c
      generic map ( clock_frequency => cpu_frequency)
      port map (
      clock => cpuclock,
      cs => i2chdmi_cs,

      hdmi_int => hdmi_int,

      sda => hdmi_sda,
      scl => hdmi_scl,

      fastio_addr => unsigned(address),
      fastio_write => w,
      fastio_read => r,
      fastio_wdata => unsigned(data_i),
      std_logic_vector(fastio_rdata) => data_o

    );
  end generate i2cperiph_mega65r2;


  sdcard0 : entity work.sdcardio
    generic map (
      cpu_frequency => cpu_frequency,
      target => target )
    port map (
    pixelclk => pixelclk,
    clock => cpuclock,
    reset => reset,
    sdcardio_cs => sdcardio_cs,
    f011_cs => f011_cs,
    hypervisor_mode => cpu_hypervisor_mode,
    hyper_trap_f011_read => hyper_trap_f011_read,
    hyper_trap_f011_write => hyper_trap_f011_write,
    virtualise_f011_drive0 => virtualised_hardware_in(0),
    virtualise_f011_drive1 => virtualised_hardware_in(1),
    secure_mode => protected_hardware_in(7),

    hw_errata_level => hw_errata_level,
    hw_errata_enable_toggle => hw_errata_enable_toggle,
    hw_errata_disable_toggle => hw_errata_disable_toggle,

    floppy_last_gap => floppy_last_gap,
    floppy_gap_strobe => floppy_gap_strobe,

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

    qspicsn => qspicsn,
    qspidb => qspidb,
    qspidb_in => qspidb_in,
    qspidb_oe => qspidb_oe,
    qspi_clock => qspi_clock,

    drive_led0 => drive_led0,
    drive_led2 => drive_led2,
    drive_ledsd => drive_ledsd,
    motor => motor,

    pwm_knob => volume_knob1,
    volume_knob1_target => volume_knob1_target,
    volume_knob2_target => volume_knob2_target,
    volume_knob3_target => volume_knob3_target,

    f_density => f_density,
    f_motora => f_motora,
    f_selecta => f_selecta,
    f_motorb => f_motorb,
    f_selectb => f_selectb,
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
    f_rdata_loopback => f_rdata_loopback,

    dipsw_hi => dipsw_hi,
    dipsw => dipsw,
    sw => sw,
    j21in => j21in,
    btn => btn,

    -- Internal virtual 1541 interface
    sd1541_data => sd1541_data,
    sd1541_ready_toggle => sd1541_ready_toggle,
    sd1541_request_toggle => sd1541_request_toggle,
    sd1541_enable => sd1541_enable,
    sd1541_track => sd1541_track,

    -- SD card interface
    sd_interface_select => sd_interface_select,
    cs_bo => cs_bo_sd,
    sclk_o => sclk_o_sd,
    mosi_o => mosi_o_sd,
    miso_i => miso_i_sd,

    aclMISO => aclMISO,
    aclMOSI => aclMOSI,
    aclSS => aclSS,
    aclSCK => aclSCK,
    aclInt1 => aclInt1,
    aclInt2 => aclInt2,

    tmpSDA => tmpSDA,
    tmpSCL => tmpSCL,
    tmpInt => tmpInt,
    tmpCT => tmpCT,

--    i2c1SDA => i2c1SDA,
--    i2c1SCL => i2c1SCL,

    audio_mix_reg => audio_mix_reg,
    audio_mix_write => audio_mix_write,
    audio_mix_wdata => audio_mix_wdata,
    audio_mix_rdata => audio_mix_rdata,
    audio_loopback => audio_loopback,
    pcm_left => pcm_left,
    pcm_right => pcm_right,

    lcdpwm => lcdpwm,
    touchSDA => touchSDA,
    touchSCL => touchSCL,
    touch1_valid => touch1_valid_int,
    touch1_x => touch1_x,
    touch1_y => touch1_y,
    touch2_valid => touch2_valid,
    touch2_x => touch2_x,
    touch2_y => touch2_y,

    last_scan_code => last_scan_code

    );

  process(reset)
  begin
    reset_high <= not reset;
    iec_reset <= reset;
  end process;

  -- Allow taking over of SD interface for bitbashing and debugging
  cs_bo <= cs_bo_sd when sd_bitbash='0' else sd_bitbash_cs_bo;
  cs2_bo <= cs_bo_sd when sd_bitbash='0' else sd_bitbash_cs_bo;

  scancode_out<=last_scan_code;
  process(cpuclock,sbcs_en,lscs_en,c65uart_en,ethernetcs_en,sdcardio_en,
          cia1cs_en,cia2cs_en,sd_interface_select_internal,sd_interface_select,sd_interface_select_internal,
          miso_i,sd_bitbash_mosi_o,mosi_o_sd,miso2_i,sd_bitbash,sclk_o_sd,cia1porta_out,cia1porta_ddr,
          cia1portb_out,cia1portb_ddr,cpu_hypervisor_mode,sbcs_en,
          addr_fast,lscs_en,rscs_en,c65uart_en,
          ethernetcs_en,sdcardio_en,cia1cs_en,cia2cs_en)
  begin
      -- Implement SD card switching
      sclk_o <= '1'; -- This avoids a latch
      sclk2_o <= '1'; -- This avoids a latch
      miso_i_sd <= '1'; -- This avoids a latch
      if sd_bitbash='1' then
        mosi_o <= sd_bitbash_mosi_o;
        mosi2_o <= sd_bitbash_mosi_o;
      elsif sd_interface_select_internal='0' then
        miso_i_sd <= miso_i;
        mosi_o <= mosi_o_sd;
        mosi2_o <= '1';
        if sd_bitbash='0' then
          sclk_o <= sclk_o_sd;
        else
          sclk_o <= sd_bitbash_sclk_o;
        end if;
        sclk2_o <= '1';
      else
        miso_i_sd <= miso2_i;
        mosi2_o <= mosi_o_sd;
        mosi_o <= '1';
        sclk_o <= '1';
        if sd_bitbash = '0' then
          sclk2_o <= sclk_o_sd;
        else
          sclk2_o <= sd_bitbash_sclk_o;
        end if;
      end if;


      if cia1porta_out(0)='0' and cia1porta_ddr(0)='1' then
        fb_up_drain_n <= '0';
      else
        fb_up_drain_n <= '1';
      end if;
      if cia1porta_out(1)='0' and cia1porta_ddr(1)='1' then
        fb_down_drain_n <= '0';
      else
        fb_down_drain_n <= '1';
      end if;
      if cia1porta_out(2)='0' and cia1porta_ddr(2)='1' then
        fb_left_drain_n <= '0';
      else
        fb_left_drain_n <= '1';
      end if;
      if cia1porta_out(3)='0' and cia1porta_ddr(3)='1' then
        fb_right_drain_n <= '0';
      else
        fb_right_drain_n <= '1';
      end if;
      if cia1porta_out(4)='0' and cia1porta_ddr(4)='1' then
        fb_fire_drain_n <= '0';
      else
        fb_fire_drain_n <= '1';
      end if;

      if cia1portb_out(0)='0' and cia1portb_ddr(0)='1' then
        fa_up_drain_n <= '0';
      else
        fa_up_drain_n <= '1';
      end if;
      if cia1portb_out(1)='0' and cia1portb_ddr(1)='1' then
        fa_down_drain_n <= '0';
      else
        fa_down_drain_n <= '1';
      end if;
      if cia1portb_out(2)='0' and cia1portb_ddr(2)='1' then
        fa_left_drain_n <= '0';
      else
        fa_left_drain_n <= '1';
      end if;
      if cia1portb_out(3)='0' and cia1portb_ddr(3)='1' then
        fa_right_drain_n <= '0';
      else
        fa_right_drain_n <= '1';
      end if;
      if cia1portb_out(4)='0' and cia1portb_ddr(4)='1' then
        fa_fire_drain_n <= '0';
      else
        fa_fire_drain_n <= '1';
      end if;



    if rising_edge(cpuclock) then

      board_major <= board_major_int;
      board_minor <= board_minor_int;
      
      if key_scancode_toggle /= last_key_scancode_toggle then
        last_key_scancode_toggle <= key_scancode_toggle;
        combined_scancode_toggle <= not internal_combined_scancode_toggle;
        internal_combined_scancode_toggle <= not internal_combined_scancode_toggle;
        combined_scancode <= key_scancode;
      elsif eth_scancode_toggle /= last_eth_scancode_toggle then
        last_eth_scancode_toggle <= eth_scancode_toggle;
        combined_scancode_toggle <= not internal_combined_scancode_toggle;
        internal_combined_scancode_toggle <= not internal_combined_scancode_toggle;
        combined_scancode <= eth_scancode;
      end if;

      -- Direct export of SID audio for supporting SID debugging
      rightsid_audio_out <= rightsid_audio;

      for i in 0 to 1 loop
        if dd00_bits_out(i)='1' or dd00_bits_ddr(i)='0' then
          dd00_bits(i) <= '1';
        else
          dd00_bits(i) <= '0';
        end if;
      end loop;

      the_button <= fb_fire and i2c_joya_fire_int;
      i2c_joya_fire <= i2c_joya_fire_int;

      touch1_valid <= touch1_valid_int;

      -- Generate 1541 drive clock at exactly 1MHz, 2MHz, 3.5MHz or 40MHz,
      -- depending on CPU speed setting.
      -- This allows fastloading at fast CPU speeds, without (hopefully) messing
      -- up Computer to drive CPU synchronisation.
      if cpuspeed = x"01" then
        drive_cycle_interval <= 40;
      elsif cpuspeed = x"02" then
        -- XXX Does any 2MHz code try to talk to the drive?  If so, then this should
        -- be 40.
        drive_cycle_interval <= 20;
      elsif cpuspeed = x"04" then
        -- XXX Does the C65 ROM talk to the drive at 3.5MHz? If so, then this
        -- should be 40
        drive_cycle_interval <= 10;
      elsif cpuspeed = x"40" then
        drive_cycle_interval <= 0;
      end if;
      if drive_cycle_countdown = 0 then
        drive_clock_cycle_strobe <= '1';
        drive_cycle_countdown <= drive_cycle_interval;
      else
        drive_clock_cycle_strobe <= '0';
        drive_cycle_countdown <= drive_cycle_countdown - 1;
      end if;

      report "1541 address_next = $" & to_hstring(address_next_1541);

      sd_interface_select_internal <= sd_interface_select;

      -- User port is only emulated to provide joy3 and joy4 as though a
      -- CGA/Protovision joystick adapter were connected.
      -- This is implemented by a special cartridge (since MEGA65 has no
      -- userport): Tie DMA to GND, and then use data and address pins 0 - 4
      -- for the two joysticks -- even simpler than the original!
      -- (and from a software perspective, it works exactly as the original)
      if userport_out(7)='1' then
        userport_in(3 downto 0) <= joy3(3 downto 0);
      else
        userport_in(3 downto 0) <= joy4(3 downto 0);
      end if;
      userport_in(4) <= joy3(4);
      userport_in(5) <= joy4(4);

      touch_key1_driver <= touch_key1;
      touch_key2_driver <= touch_key2;

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
      case cia1porta_out(7 downto 6) is
        when "01" =>
          potr_x <= pota_x;
          potr_y <= pota_y;
          potl_x <= potb_x;
          -- Simulate light gun with touch screen
          if touch1_valid_int='0' then
            potl_y <= potb_y;
          else
            potl_y <= x"00";
          end if;
        when others =>
          potl_x <= pota_x;
          potl_y <= pota_y;
          potr_x <= potb_x;
          potr_y <= potb_y;
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

      seg_led(12) <= eth_scancode_toggle;
      seg_led(11) <= last_scan_code(12);
      seg_led(10 downto 0) <= unsigned(last_scan_code(10 downto 0));

      -- Buffer ASCII keyboard input: Writing to the register causes
      -- the next key in the queue to be displayed.
      matrix_mode_trap <= '0';
      if key_valid='1' and ascii_key = x"E0" and  ef_latch='0' then
        eth_load_enable_int <= not eth_load_enable_int;
        eth_load_enable <= not eth_load_enable_int;
      end if;
      if key_valid='1' and ascii_key = x"EF" and  ef_latch='0' then
        -- C= + TAB
        -- This replaces the old ALT+TAB task switch combination
        matrix_mode_trap <= '1';
        ef_latch <= '1';
        -- But don't allow multiple triggerings of this too quickly
        -- (This is to work around a very weird bug where C= + TAB on PS/2
        -- keyboards at least, triggers repeatedly.  But C= + ~ (like <- on a
        -- C64 keyboard) doesn't have that problem. Maybe the PS/2 keyboard triggers
        -- the TAB key more frequently?  Anyway, we will just block repeats
        -- from occurring too quickly
        ef_timeout <= 20; -- x 1/100th of a second
      end if;
      if (key_valid='0' or ascii_key /= x"e0") and e0_latch='1' then
        if viciv_frame_indicate='1' then
          if e0_timeout /= 0 then
            e0_timeout <= e0_timeout - 1;
          else
            e0_latch <= '0';
          end if;
        end if;
      end if;

      if (key_valid='0' or ascii_key /= x"ef") and ef_latch='1' then
        if viciv_frame_indicate='1' then
          if ef_timeout /= 0 then
            ef_timeout <= ef_timeout - 1;
          else
            ef_latch <= '0';
          end if;
        end if;
      end if;

      -- UART char for monitor/matrix mode
      last_key_valid <= key_valid;
      if key_valid='1' and last_key_valid='0' and protected_hardware_in(6)='1' then
        uart_monitor_char <= ascii_key;
        uart_monitor_char_valid <= '1';
      else
        uart_monitor_char_valid <= '0';
      end if;

      -- UART char for user mode
      uart_char_valid <= '0';
      if key_valid='1' and last_key_valid='0' then
        if protected_hardware_in(6)='0' then
          -- Push char to matrix mode monitor (it will know if it is active or
          -- not)
          uart_char <= ascii_key;
          uart_char_valid <= '1';
          -- Enqueue char to keyboard buffer
          --
          -- If ascii_key = x"00" and petscii_key /= x"ff", enqueue the event,
          -- encoding ascii_key as x"ff" to disambiguate from "empty queue"
          -- state. This intentionally emits a valid but incorrect ASCII
          -- character in 13 cases where PETSCII has a character but ASCII
          -- does not for the same key number and modifiers.
          if key_presenting = '1' then
            if key_buffer_count < 4 then
              if ascii_key = x"00" then
                ascii_key_buffer(key_buffer_count) <= x"ff";
              else
                ascii_key_buffer(key_buffer_count) <= ascii_key;
              end if;
              petscii_key_buffer(key_buffer_count) <= petscii_key;
              bucky_key_buffer(key_buffer_count) <= bucky_key;
              key_buffer_count <= key_buffer_count + 1;
            end if;
          else
            if ascii_key = x"00" then
              ascii_key_buffered <= x"ff";
            else
              ascii_key_buffered <= ascii_key;
            end if;
            petscii_key_buffered <= petscii_key;
            bucky_key_buffered <= bucky_key;
            key_presenting <= '1';
          end if;

        end if;
      end if; -- key_valid

      if reset_high = '1' then
        eth_load_enable_int <= '0';
        eth_load_enable <= '0';

        key_buffer_count <= 0;
        key_presenting <= '0';
        ascii_key_buffered <= x"00";
        petscii_key_buffered <= x"ff";
        bucky_key_buffered <= "0000000";

      elsif ascii_key_next = '1' or petscii_key_next = '1' then
        -- Dequeue the keyboard buffer
        if key_buffer_count > 0 then
          key_presenting <= '1';
          ascii_key_buffered <= ascii_key_buffer(0);
          petscii_key_buffered <= petscii_key_buffer(0);
          bucky_key_buffered <= bucky_key_buffer(0);
          key_buffer_count <= key_buffer_count - 1;
          for i in 0 to 2 loop
            ascii_key_buffer(i) <= ascii_key_buffer(i+1);
            petscii_key_buffer(i) <= petscii_key_buffer(i+1);
            bucky_key_buffer(i) <= bucky_key_buffer(i+1);
          end loop;
        else
          key_presenting <= '0';
          ascii_key_buffered <= x"00";
          petscii_key_buffered <= x"ff";
          bucky_key_buffered <= "0000000";
        end if;
        if ascii_key_event_count /= x"FFFF" then
          ascii_key_event_count <= ascii_key_event_count + 1;
        else
          ascii_key_event_count <= x"0000";
        end if;

      elsif key_queue_flush = '0' then
        key_buffer_count <= 0;
        key_presenting <= '0';
        ascii_key_buffered <= x"00";
        petscii_key_buffered <= x"ff";
        bucky_key_buffered <= "0000000";
      end if;
    end if;
  end process;

  process (r,w,address,cia1portb_in,cia1porta_out,colourram_at_dc00,
           sector_buffer_mapped_read,
           cpu_hypervisor_mode,sbcs_en,addr_fast,lscs_en,
           rscs_en,c65uart_en,ethernetcs_en,sdcardio_en,
           cia1cs_en,cia2cs_en)
    variable temp : unsigned(19 downto 0);
  begin  -- process

      -- @IO:GS $FFF8000-$FFFBFFF 16KB Hyppo/hypervisor ROM
      -- @IO:GS $FFF8000-$FFF80FC Hypervisor entry point when $D640-$D67F is written
      -- @IO:GS $FFF8100 Hypervisor entry point on reset (trap $40)
      -- @IO:GS $FFF8104 Hypervisor entry point on page fault (trap $41)
      -- @IO:GS $FFF8108 Hypervisor entry point on RESTORE long-press (trap $42)
      -- @IO:GS $FFF810C Hypervisor entry point on C=-TAB / ALT-TAB (trap $43)
      -- @IO:GS $FFF8110 Hypervisor entry point on FDC read (when virtualised) (trap $44)
      -- @IO:GS $FFF8114 Hypervisor entry point on FDC write (when virtualised) (trap $45)

      if address(19 downto 14)&"00" = x"F8" then
        hyppocs <= cpu_hypervisor_mode;
      else
        hyppocs <='0';
      end if;

      -- sdcard sector buffer: only mapped if no colour ram @ $DC00, and if
      -- the sectorbuffer mapping flag is set
      sectorbuffercs <= '0';
      sectorbuffercs_fast <= '0';
      report "fastio address = $" & to_hstring(address) severity note;

      if address(19 downto 16) = x"D"
        and address(15 downto 14) = "00"
        and address(13 downto 12) /= "10"
        and address(11 downto 9)&'0' = x"E"
        and sector_buffer_mapped_read = '1' and colourram_at_dc00 = '0' then
        sectorbuffercs <= sbcs_en;
        report "selecting SD card sector buffer" severity note;
      end if;
      -- Also map SD card sector buffer at $FFD6000 - $FFD61FF regardless of
      -- VIC-IV IO mode and mapping of colour RAM
      -- @IO:GS $FFD6E00-FFF - SD card direct access sector buffer
      -- @IO:GS $FFD6C00-DFF - F011 floppy controller sector buffer
      if address(19 downto 12) = x"D6" then
        sectorbuffercs <= sbcs_en;
      end if;

      -- @IO:GS $FF7E000-$FF7EFFF SUMMARY:CHARWRITE VIC-IV CHARROM area
      charrom_cs <= '0';
      if address(19 downto 12) = x"7E" then
        charrom_cs <= '1';
      end if;

      -- @IO:GS $FFD7x00-xFF - I2C Peripherals for various targets
      i2cperipherals_cs <= '0';
      i2chdmi_cs <= '0';
      grove_cs <= '0';
      if (target = megaphoner1) or (target = megaphoner4) then
        if address(19 downto 8) = x"D70" then
          i2cperipherals_cs <= '1';
          report "i2cperipherals_cs for MEGAphone asserted";
        end if;
      end if;

      if target = mega65r2 then
        if address(19 downto 8) = x"D72" then
          i2chdmi_cs <= '1';
          report "i2chdmi_cs for MEGA65R2 asserted";
        end if;
        if address(19 downto 8) = x"D71" then
          i2cperipherals_cs <= '1';
          report "i2cperipherals_cs for MEGA65R2 asserted";
        end if;
      end if;

      if target = mega65r3 or target = mega65r4 or target = mega65r5 or target = mega65r6 then
        if address(19 downto 8) = x"D71" then
          i2cperipherals_cs <= '1';
          report "i2cperipherals_cs for MEGA65R3/R4/R5 asserted";
        end if;
        if address(19 downto 8) = x"D73" then
          i2chdmi_cs <= '1';
          report "i2chdmi_cs for MEGA65R3/R4/R5 asserted";
        end if;
        if address(19 downto 8) = x"D74" then
          grove_cs <= '1';
          report "grove_cs for MEGA65R3/R4/R5 asserted";
        end if;
      end if;

      cs_driveram <= '0';
      cs_driverom <= '0';
      if address(19 downto 16) = x"C" then
        if address(15 downto 14) = "11" then
          -- @IO:GS $FFCC000-$FFCFFFF - Internal 1541 ROM access
          cs_driverom <= '1';
        end if;
        if address(15 downto 12) = x"B" then
          -- @IO:GS $FFcB000-$FFcBFFF - Internal 1541 RAM access
          cs_driveram <= '1';
        end if;
      end if;

      -- Same thing as above, but for the addr_fast bus, which is usually one clock ahead.
      if addr_fast(19 downto 16) = x"D"
        and addr_fast(15 downto 14) = "00"
        and address(13 downto 12) /= "10"
        and addr_fast(11 downto 9)&'0' = x"E"
        and sector_buffer_mapped_read = '1' and colourram_at_dc00 = '0' then
        sectorbuffercs_fast <= sbcs_en;
        report "selecting SD card sector buffer" severity note;
      end if;
      -- Also map SD card sector buffer at $FFD6000 - $FFD6FFF regardless of
      -- VIC-IV IO mode and mapping of colour RAM
      -- @IO:GS $FFD6E00-FFF - SD card direct access sector buffer
      -- @IO:GS $FFD6C00-DFF - F011 floppy controller sector buffer
      if addr_fast(19 downto 12) = x"D6" then
        sectorbuffercs_fast <= sbcs_en;
      end if;

      -- Now map the SIDs
      -- @IO:C64 $D400-$D40F = SID#1 (internally known as 'right SID #1' or as 'rightsid')
      -- @IO:C64 $D420-$D43F = SID#2 (internally known as 'right SID #2' or as 'backsid')
      -- @IO:C64 $D440-$D45F = SID#3 (internally known as 'left SID #1' or as 'leftsid')
      -- @IO:C64 $D460-$D47F = SID#4 (internally known as 'left SID #2' or as 'backsid')
      -- @IO:C64 $D480-$D4FF = repeated images of SIDs
      -- Presumably repeated through to $D5FF.  But we will repeat to $D4FF only
      -- so that we can use $D500-$D5FF for other stuff.
      case address(19 downto 8) is
        when x"D04" | x"D14" | x"D24" | x"D34" | x"D05" =>
          leftsid_cs <= ((address(6) and not address(5)) xor address(8)) and lscs_en;
          rightsid_cs <= (((not address(6)) and not address(5)) xor address(8)) and rscs_en;
          frontsid_cs <= ((address(6) and address(5)) xor address(8)) and lscs_en;
          backsid_cs <= (((not address(6)) and address(5)) xor address(8)) and rscs_en;
        when others => leftsid_cs <= '0'; rightsid_cs <= '0'; frontsid_cs <= '0'; backsid_cs <= '0';
      end case;

      -- $D500 - $D5FF is not currently used.  Probably use some for FPU.

      -- $D600 - $D63F is reserved for C65 serial UART emulation for C65
      -- compatibility (C65 UART actually only has 7 registers).
      -- 6551 is not currently implemented, so this is just unmapped for now,
      -- except for any read values required to allow the C65 ROM to function.
      temp(15 downto 2) := unsigned(address(19 downto 6));
      temp(1 downto 0) := "00";
      if address(7 downto 6) = "00" then  -- Mask out $FFDx6[4-7]x
        case temp(15 downto 0) is
          when x"D160" => c65uart_cs <= c65uart_en;
          when x"D260" => c65uart_cs <= c65uart_en;
          when x"D360" => c65uart_cs <= c65uart_en;
          when others => c65uart_cs <= '0';
        end case;
      else
        c65uart_cs <= '0';
      end if;
      -- @IO:GS $FFD4000 THUMB:THUMB Hardware-generated thumbnail image of screen. 80x50, using 3x3x2 RGB colour cube.
      if (address(19 downto 12) = x"D4") then
        thumbnail_cs <= '1';
        report "THUMB: Asserting CS";
      else
        thumbnail_cs <= '0';
      end if;
      if (address(19 downto 4) = x"D36E") or (address(19 downto 4) = x"D26E") then
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
          when x"D0C" => cia1cs <= cia1cs_en;
          when x"D1C" => cia1cs <= cia1cs_en;
          when x"D3C" => cia1cs <= cia1cs_en;
          when x"D0D" => cia2cs <= cia2cs_en;
          when x"D1D" => cia2cs <= cia2cs_en;
          when x"D3D" => cia2cs <= cia2cs_en;
          when others => null;
        end case;
      end if;

      if address(19 downto 8) = x"DF0" then
        vfpga_cs <= '1';
      else
        vfpga_cs <= '0';
      end if;

    report "CS lines: "
      & to_string(cia1cs&cia2cs&hyppocs&sectorbuffercs&leftsid_cs&rightsid_cs&c65uart_cs&sdcardio_cs&thumbnail_cs&vfpga_cs);
  end process;

end behavioral;
