use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;
use work.version.all;

entity c65uart is
  generic ( target : mega65_target_t );
  port (
    pixelclock : in std_logic;
    cpuclock : in std_logic;
    reset : in std_logic;
    irq : out std_logic := 'Z';
    c65uart_cs : in std_logic;

    sid_mode : out unsigned(3 downto 0) := "0000";
    dc_track_rate : out unsigned(7 downto 0) := x"ff";
    dc_track_enable : out std_logic := '0';

    osk_toggle_key : in std_logic;
    joyswap_key : in std_logic;

    max10_fpga_date : in unsigned(15 downto 0);
    max10_fpga_commit : in unsigned(31 downto 0);

    kbd_datestamp : in unsigned(13 downto 0);
    kbd_commit : in unsigned(31 downto 0);

    board_major : in unsigned(3 downto 0);
    board_minor : in unsigned(3 downto 0);
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_address : in unsigned(19 downto 0);
    fastio_write : in std_logic;
    fastio_read : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0);

    disco_led_en : out std_logic := '0';
    disco_led_id : out unsigned(7 downto 0) := x"00";
    disco_led_val : out unsigned(7 downto 0) := x"00";

    uart_rx : in std_logic := '0';
    uart_tx : out std_logic;

    key_debug : in std_logic_vector(7 downto 0);
    key_left : in std_logic;
    key_up : in std_logic;

    widget_disable : out std_logic;
    ps2_disable : out std_logic;
    joykey_disable : out std_logic;
    joyreal_disable : out std_logic;
    physkey_disable : out std_logic;
    virtual_disable : out std_logic;
    joya_rotate : out std_logic := '0';
    joyb_rotate : out std_logic := '0';
    joyswap : out std_logic := '0';
    osk_debug_display : out std_logic := '0';

    -- Paddle/analog mouse inputs and debugging
    cia1portb_out : in std_logic_vector(7 downto 6);
    fa_potx : in std_logic;
    fa_poty : in std_logic;
    fb_potx : in std_logic;
    fb_poty : in std_logic;
    pot_drain : in std_logic;
    pota_x : in unsigned(7 downto 0);
    pota_y : in unsigned(7 downto 0);
    potb_x : in unsigned(7 downto 0);
    potb_y : in unsigned(7 downto 0);
    pot_via_iec : buffer std_logic := '0';
    mouse_debug : in unsigned(7 downto 0);
    amiga_mouse_enable_a : out std_logic;
    amiga_mouse_enable_b : out std_logic;
    amiga_mouse_assume_a : out std_logic;
    amiga_mouse_assume_b : out std_logic;

    porte : inout std_logic_vector(7 downto 0) := (others => '0');
    portf : inout std_logic_vector(7 downto 0) := (others => '0');
    portg : inout std_logic_vector(7 downto 0) := (others => '0');
    porth : in std_logic_vector(7 downto 0);
    porth_write_strobe : out std_logic := '0';
    porto_write_strobe : out std_logic := '0';
    matrix_disable_modifiers : buffer std_logic := '0';
    porti : in std_logic_vector(7 downto 0);
    portj_in : in std_logic_vector(7 downto 0);
    portj_out : out std_logic_vector(7 downto 0) := (others => '0');
    portk_out : out  std_logic_vector(7 downto 0) := (others => '0');
    portl_out : out  std_logic_vector(7 downto 0) := (others => '0');
    portm_out : out  std_logic_vector(7 downto 0) := (others => '0');
    portn_out : out unsigned(7 downto 0) := (others => '0');
    porto : in unsigned(7 downto 0) := (others => '0');
    portp_out : out unsigned(7 downto 0) := (others => '0');
    portq_in : in unsigned(7 downto 0);
    j21in : in std_logic_vector(11 downto 0) := (others => '1');
    j21out : inout std_logic_vector(11 downto 0) := (others => '1');
    j21ddr : inout std_logic_vector(11 downto 0) := (others => '0');

    last_reset_source : in unsigned(2 downto 0);
    reset_monitor_count : in unsigned(11 downto 0);

    accessible_key_event : in unsigned(7 downto 0);
    accessible_key_enable : buffer std_logic := '0';
    accessible_key_extradim : out std_logic := '0';

    suppress_key_glitches : out std_logic := '1';
    suppress_key_retrigger : out std_logic := '0';
    ascii_key_event_count : in unsigned(15 downto 0);

    bucky_key_buffered : in std_logic_vector(6 downto 0) := (others => '0');
    key_presenting : inout std_logic := '0';
    key_queue_flush : buffer std_logic := '1'
    );
end c65uart;

architecture behavioural of c65uart is

  -- Work out what fraction of a 7.09375MHz tick we cover every pixel clock.
  -- This is used to allow us to match C65 UART speeds.
  -- 7.09375 / 81 / 16 * 1048576 = 5739;
  -- Note that these ticks are in 1/16ths of the desired baud rate.
  -- This limits our maximum usable baud rate to something like 81MHz/16 = ~5MHz
  -- But I am not totally convinced that I have all the calculations right
  -- here. Will need to check what actually comes out the port at particular claimed
  -- speeds to be sure.
  constant baud_subcounter_step : integer := 5739;
  signal baud_subcounter : integer range 0 to (1048576 + baud_subcounter_step);
  -- If 1, then use approximated 7.09375MHz clock, if 0 use 81MHz clock
  signal clock709375 : std_logic := '1';

  -- Work out 7.09375ishMHz clock ticks;
  signal tick709375 : std_logic := '0';

  signal real_hardware : std_logic := '1';

  -- Then merge this with 81MHz clock to have a single clock source used for
  -- generating half-ticks at the requested baud rate
  signal fine_tick : std_logic := '0';

  -- Count how many fine ticks per half-baud
  signal reg_tick_countdown : unsigned(15 downto 0) := (others => '0');

  -- From that work out the baud ticks
  signal baud_tick : std_logic := '1';

  -- Filtered UART RX line
  signal filtered_rx : std_logic := '1';
  signal rx_samples : std_logic_vector(15 downto 0);

  signal target_id : unsigned(7 downto 0) := x"FF";

  -- Transmit buffer for current byte
  -- (Note the UART can also have a byte buffered in reg_data_tx, to allow
  -- back-to-back char sending)
  signal tx_buffer : std_logic_vector(7 downto 0);
  signal tx_in_progress : std_logic := '0';
  signal tx_bits_to_send : integer range 0 to 8;
  signal tx_stop_bit_sent : std_logic := '0';
  signal tx_parity_bit_sent : std_logic := '0';
  signal tx_space_bit_sent : std_logic := '0';

  -- Similarly track incoming bytes
  signal rx_buffer : std_logic_vector(7 downto 0);
  signal rx_in_progress : std_logic := '0';
  signal rx_bits_remaining : integer range 0 to 8;
  signal rx_stop_bit_got : std_logic := '0';
  signal rx_clear_flags : std_logic := '0';

  -- Actual C65 UART registers
  signal reg_status0_rx_full : std_logic := '0';
  signal reg_status1_rx_overrun : std_logic := '0';
  signal reg_status2_rx_parity_error : std_logic := '0';
  signal reg_status3_rx_framing_error : std_logic := '0';
  signal reg_status4_rx_idle_mode : std_logic := '0';  -- XXX not implemented
  signal reg_status5_tx_eot : std_logic := '0';
  signal reg_status6_tx_empty : std_logic := '1';
  signal reg_status7_xmit_on : std_logic := '0';

  signal reg_data_tx_toggle : std_logic := '0';
  signal reg_data_tx_toggle_prev : std_logic := '0';

  signal reg_status0_rx_full_drive : std_logic := '0';
  signal reg_status1_rx_overrun_drive : std_logic := '0';
  signal reg_status2_rx_parity_error_drive : std_logic := '0';
  signal reg_status3_rx_framing_error_drive : std_logic := '0';
  signal reg_status4_rx_idle_mode_drive : std_logic := '0';  -- XXX not implemented
  signal reg_status5_tx_eot_drive : std_logic := '0';
  signal reg_status6_tx_empty_drive : std_logic;
  signal reg_status7_xmit_on_drive : std_logic := '0';

  signal reg_ctrl0_parity_even : std_logic := '0';
  signal reg_ctrl1_parity_enable : std_logic := '0';
  signal reg_ctrl23_char_length_deduct : unsigned(1 downto 0) := "00";
  signal reg_ctrl45_sync_mode_flags : std_logic_vector(1 downto 0) := "00"; -- XXX not implemented
  signal reg_ctrl6_rx_enable : std_logic := '1';
  signal reg_ctrl7_tx_enable : std_logic := '1';

  signal reg_divisor : unsigned(15 downto 0) := (others => '0');
  signal reg_intmask : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_intflag : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_data_tx : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_data_rx : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_data_rx_drive : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_data_rx_driver : std_logic_vector(7 downto 0) := (others => '0');

  -- C65 extra 2-bit port for keyboard column 8 and capslock key state.
  signal reg_porte_out : std_logic_vector(7 downto 0) := "00000011";
  signal reg_porte_ddr : std_logic_vector(7 downto 0) := "00000010";
  signal reg_porte_read : unsigned(7 downto 0) := (others => '0');
  -- Used for HDMI SPI control interface and SD SPI bitbashing debug interface)
  -- Bits 0 and 1 are invert sense for left and up keys
  signal reg_portg_out : std_logic_vector(7 downto 0) := "00000000";
  signal reg_portg_ddr : std_logic_vector(7 downto 0) := "00111111";
  signal reg_portg_read : unsigned(7 downto 0) := (others => '0');

  -- MEGA65 PMOD register for debugging and fiddling
  signal reg_portf_out : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_portf_ddr : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_portf_read : unsigned(7 downto 0) := (others => '0');

  signal portj_internal : std_logic_vector(7 downto 0) := x"FF";

  signal widget_enable_internal : std_logic := '1';
  signal ps2_enable_internal : std_logic := '1';
  signal joykey_enable_internal : std_logic := '1';
  signal joyreal_enable_internal : std_logic := '1';
  signal physkey_enable_internal : std_logic := '1';
  signal virtual_enable_internal : std_logic := '1';

  -- XXX for debugging, make OSK visible from startup
  signal portk_internal : std_logic_vector(7 downto 0) := x"7F"; -- visual
                                                                 -- keyboard
                                                                 -- off by default

  signal portl_internal : std_logic_vector(7 downto 0) := x"7F";
  signal portm_internal : std_logic_vector(7 downto 0) := x"7F";
  signal portn_internal : std_logic_vector(7 downto 0) := x"FF";

  -- Bit 1 = disable DVI audio
  -- Bit 7 = invert samples
  -- Bit 4 = LED on mainboard
  -- Bit 2 = visualise audio samples
  -- Bit 3 = select 48KHz instead of 44.1KHz audio sample rate
  signal portp_internal : std_logic_vector(7 downto 0) := x"01"; -- 48KHz, with
                                                                 -- digital audio

  signal joyswap_internal : std_logic := '0';
  signal joya_rotate_internal : std_logic := '0';
  signal joyb_rotate_internal : std_logic := '0';
  signal amiga_mouse_enable_a_internal : std_logic := '0';
  signal amiga_mouse_enable_b_internal : std_logic := '0';
  signal amiga_mouse_assume_a_internal : std_logic := '0';
  signal amiga_mouse_assume_b_internal : std_logic := '0';

  signal last_osk_toggle_key : std_logic := '1';
  signal osk_toggle_counter : integer range 0 to 20000000 := 0;
  signal last_joyswap_key : std_logic := '1';
  signal joyswap_countdown : integer range 0 to 1023 := 0;

  signal disco_led_en_int : std_logic := '0';
  signal disco_led_id_int : unsigned(7 downto 0) := x"00";
  signal disco_led_val_int : unsigned(7 downto 0) := x"00";

  signal sid_mode_int : unsigned(3 downto 0) := "0000";
  signal dc_track_rate_int : unsigned(7 downto 0) := x"ff";
  signal dc_track_enable_int : std_logic := '0';

  signal accessible_key_extradim_int : std_logic := '0';

  
begin  -- behavioural

  process(pixelclock,cpuclock,fastio_address,fastio_write,fastio_read,
          c65uart_cs,reg_data_rx_drive,reg_status0_rx_full_drive,
          reg_status1_rx_overrun_drive,reg_status2_rx_parity_error_drive,
          reg_status3_rx_framing_error_drive,reg_status4_rx_idle_mode_drive,
          reg_status5_tx_eot_drive,reg_status6_tx_empty_drive,
          reg_status7_xmit_on_drive,reg_ctrl0_parity_even,
          reg_ctrl1_parity_enable,reg_ctrl23_char_length_deduct,
          reg_ctrl45_sync_mode_flags,reg_ctrl6_rx_enable,reg_ctrl7_tx_enable,
          reg_divisor,reg_intmask,reg_intflag,reg_porte_read,reg_porte_ddr,
          clock709375,bucky_key_buffered,key_presenting,reg_portf_read,reg_portf_ddr,
          reg_portg_read,reg_portg_ddr,
          key_left,key_up,real_hardware,accessible_key_extradim_int,
          accessible_key_enable,key_queue_flush,porth,porti,matrix_disable_modifiers,
          widget_enable_internal,ps2_enable_internal,physkey_enable_internal,
          virtual_enable_internal,joykey_enable_internal,joyswap_internal,
          joya_rotate_internal,joyb_rotate_internal,
          portj_in,portj_internal,portk_internal,portl_internal,portm_internal,
          portn_internal,porto,portp_internal,mouse_debug,portq_in,
          disco_led_en_int,disco_led_id_int,disco_led_val_int,
          pota_x,pota_y,potb_x,potb_y,pot_via_iec,pot_drain,cia1portb_out,
          fa_potx,fa_poty,fb_potx,fb_poty,j21in,j21ddr,target_id,
          kbd_datestamp,kbd_commit,max10_fpga_date,max10_fpga_commit,sid_mode_int,
          dc_track_enable_int,last_reset_source,dc_track_rate_int,reset_monitor_count) is
    -- purpose: use DDR to show either input or output bits
    function ddr_pick (
      ddr                            : in std_logic_vector(7 downto 0);
      i                              : in std_logic_vector(7 downto 0);
      o                              : in std_logic_vector(7 downto 0))
    return unsigned is
    variable result : unsigned(7 downto 0);
  begin  -- ddr_pick
    --report "determining read value for CIA port." &
    --  "  DDR=$" & to_hstring(ddr) &
    --  ", out_value=$" & to_hstring(o) &
    --  ", in_value=$" & to_hstring(i) severity note;
    result := unsigned(i);
    for b in 0 to 7 loop
      if ddr(b)='1' and i(b)='1' then
        result(b) := std_ulogic(o(b));
      end if;
    end loop;  -- b
    return result;
  end ddr_pick;

    variable register_number : unsigned(7 downto 0);
  begin

    register_number(7 downto 6) := "00";
    register_number(5 downto 0) := fastio_address(5 downto 0);

    -- Determine model number
    case target is
      -- $00-$1F = MEGA65 desktop versions
      -- Note: MEGA65 R5 onwards read straps from an I2C IO expander to get
      -- the board major and minor versions, so we don't ID beyond R4 here.
      -- Search for mega65r5 in this file to find that other logic.
      when mega65r1 => target_id <= x"01";
      when mega65r2 => target_id <= x"02";
      when mega65r3 => target_id <= x"03";
      when mega65r4 => target_id <= x"04";
                       
      -- $20-$3F = MEGAphone/handheld versions
      when megaphoner1 => target_id <= x"21";
      when megaphoner4 => target_id <= x"22";
      -- $40-$5F = Nexys4 / Nexys4 DDR
      when nexys4 => target_id <= x"40";
      when nexys4ddr => target_id <= x"41";
      when nexys4ddr_widget => target_id <= x"42";
      -- $60-$7F = QMTech Artic / Kintex boards
      when qmtecha100t => target_id <= x"60";
      when qmtecha200t => target_id <= x"61";
      when qmtechk325t => target_id <= x"62";
      -- Misc other targets, that don't have common properties
      when wukong => target_id <= x"FD";
      when simulation => target_id <= x"FE";

      when others => target_id <= x"FF";
    end case;

    if rising_edge(cpuclock) then

      accessible_key_extradim <= accessible_key_extradim_int;
      
      sid_mode <= sid_mode_int;
      dc_track_rate <= dc_track_rate_int;
      dc_track_enable <= dc_track_enable_int;

      if target = simulation then
        real_hardware <= '0';
      else
        real_hardware <= '1';
      end if;

      if accessible_key_enable = '1' then
        if accessible_key_event = x"FE" then
          -- Turn OSK off
          portk_internal(7) <= '0';
        elsif accessible_key_event = x"FD" then
          -- Turn OSK on
          portk_internal(7) <= '1';
          portl_internal(7) <= '1'; -- And put at top of screen for now
        elsif accessible_key_event(6 downto 0) < to_unsigned(100,7) then
          -- Key up or down event from accessibile keyboard system
          if accessible_key_event(7)='1' then
            -- Key down
            if portk_internal(6 downto 0) /= std_logic_vector(accessible_key_event(6 downto 0))
              and portl_internal(6 downto 0) /= std_logic_vector(accessible_key_event(6 downto 0))
              and portm_internal(6 downto 0) /= std_logic_vector(accessible_key_event(6 downto 0)) then
              -- This key is not currently pressed
              if portk_internal(6 downto 0) = "1111111" then
                portk_internal(6 downto 0) <= std_logic_vector(accessible_key_event(6 downto 0));
              elsif portl_internal(6 downto 0) = "1111111" then
                portl_internal(6 downto 0) <= std_logic_vector(accessible_key_event(6 downto 0));
              elsif portm_internal(6 downto 0) = "1111111" then
                portm_internal(6 downto 0) <= std_logic_vector(accessible_key_event(6 downto 0));
              end if;
            end if;
          else
            -- Key released
            if portk_internal(6 downto 0) = std_logic_vector(accessible_key_event(6 downto 0)) then
              portk_internal(6 downto 0) <= "1111111";
            end if;
            if portl_internal(6 downto 0) = std_logic_vector(accessible_key_event(6 downto 0)) then
              portl_internal(6 downto 0) <= "1111111";
            end if;
            if portm_internal(6 downto 0) = std_logic_vector(accessible_key_event(6 downto 0)) then
              portm_internal(6 downto 0) <= "1111111";
            end if;
          end if;
        end if;
      end if;

      -- Monitor OSK toggle key input for MEGAphone, and cycle through the
      -- various OSK states (off, bottom and top position).
      last_osk_toggle_key <= osk_toggle_key;
      -- We have a countdown to effectively de-bounce the key
      if osk_toggle_counter /= 0 then
        osk_toggle_counter <= osk_toggle_counter - 1;
      end if;
      if osk_toggle_key='0' and last_osk_toggle_key='1' and osk_toggle_counter = 0 then
        -- Only allow one event per 1/4 second
        osk_toggle_counter <= 10000000;
        -- Toggle between off, bottom and top position for visual keyboard
        if portk_internal(7) = '0' then
          portk_internal(7) <= '1';
        elsif portl_internal(7) = '0' then
          portl_internal(7) <= '1';
        else
          portk_internal(7) <= '0';
          portl_internal(7) <= '0';
        end if;
      end if;

      reg_data_rx_drive <= reg_data_rx;

      widget_disable <= not widget_enable_internal;
      ps2_disable <= not ps2_enable_internal;
      joykey_disable <= not joykey_enable_internal;
      joyreal_disable <= not joyreal_enable_internal;
      physkey_disable <= not physkey_enable_internal;
      virtual_disable <= not virtual_enable_internal;

      portk_out <= portk_internal;
      portl_out <= portl_internal;
      portm_out <= portm_internal;
      portn_out <= unsigned(portn_internal);
      portp_out <= unsigned(portp_internal);

      rx_clear_flags <= '0';
      if (fastio_address(19 downto 16) = x"D")
        and (fastio_address(11 downto 5) = "0110000") then
        if fastio_read='1' and register_number = x"0" then
          rx_clear_flags <= '1';
        end if;
      end if;

      -- Swap joysticks 1 & 2 when requested.
      -- XXX For now, this is only wired up for the MEGAphone, but it would
      -- be nice to have some bit that controls it on the normal machine as well.
      last_joyswap_key <= joyswap_key;
      -- We have a countdown to effectively de-bounce the key
      if joyswap_key='0' and last_joyswap_key='1' and joyswap_countdown = 0 then
        joyswap_internal <= not joyswap_internal;
        joyswap <= not joyswap_internal;
        joyswap_countdown <= 1023;
      else
        if joyswap_countdown /= 0 then
          joyswap_countdown <= joyswap_countdown - 1;
        end if;
      end if;

      -- Make copies of registers from pixelclock domain
      reg_status0_rx_full_drive <= reg_status0_rx_full;
      reg_status1_rx_overrun_drive <= reg_status1_rx_overrun;
      reg_status2_rx_parity_error_drive <= reg_status2_rx_parity_error;
      reg_status3_rx_framing_error_drive <= reg_status3_rx_framing_error;
      reg_status4_rx_idle_mode_drive <= reg_status4_rx_idle_mode;
      reg_status5_tx_eot_drive <= reg_status5_tx_eot;
      reg_status6_tx_empty_drive <= reg_status6_tx_empty;
      reg_status7_xmit_on_drive <= reg_status7_xmit_on;

      porth_write_strobe <= '0';
      porto_write_strobe <= '0';
      key_queue_flush <= '1';

      -- Calculate read value for various ports
      reg_porte_read <= ddr_pick(reg_porte_ddr,porte,reg_porte_out);
      reg_portf_read <= ddr_pick(reg_portf_ddr,portf,reg_portf_out);
      reg_portg_read <= ddr_pick(reg_portg_ddr,portg,reg_portg_out);

      -- Support proper tri-stating on port F and port G which connects to FPGA board PMOD
      -- connector.
      for bit in 1 to 7 loop
        -- Bit 0 of porte is the capslock key, which is input only
        if reg_porte_ddr(bit)='1' then
          porte(bit) <= reg_porte_out(bit) or (not reg_porte_ddr(bit));
        else
          porte(bit) <= 'Z';
        end if;
      end loop;
      for bit in 0 to 7 loop
        if reg_portf_ddr(bit)='1' then
          portf(bit) <= reg_portf_out(bit) or (not reg_portf_ddr(bit));
        else
          portf(bit) <= 'Z';
        end if;
        if reg_portg_ddr(bit)='1' then
          portg(bit) <= reg_portg_out(bit) or (not reg_portg_ddr(bit));
        else
          portg(bit) <= 'Z';
        end if;
      end loop;

      -- Check for register writing
      if (fastio_write='1') and (c65uart_cs='1') then
        case register_number is
          when x"00" =>
            reg_data_tx <= std_logic_vector(fastio_wdata);
            reg_status5_tx_eot <= '0';
            reg_data_tx_toggle <= not reg_data_tx_toggle;
          when x"01" => null;
          when x"02" =>
            reg_ctrl0_parity_even <= fastio_wdata(0);
            reg_ctrl1_parity_enable <= fastio_wdata(1);
            reg_ctrl23_char_length_deduct  <= fastio_wdata(3 downto 2);
            reg_ctrl45_sync_mode_flags <= std_logic_vector(fastio_wdata(5 downto 4));
            reg_ctrl6_rx_enable <= fastio_wdata(6);
            reg_ctrl7_tx_enable <= fastio_wdata(7);
          when x"03" => reg_divisor(7 downto 0) <= fastio_wdata;
          when x"04" => reg_divisor(15 downto 8) <= fastio_wdata;
          when x"05" => reg_intmask <= std_logic_vector(fastio_wdata);
          when x"06" =>
            -- reg_intflag
            -- This register is not used in the C65 ROM, so we don't know how it
            -- should behave.  What is clear, is that there is some other mechanism
            -- besides reading this register that actually clears the IRQ.
            -- Perhaps just reading the data register is enough to clear an RX
            -- IRQ?  What about TX ready IRQ? It seems like writing a character
            -- or disabling the transmitter should clear it.
          when x"07" => reg_porte_out<=std_logic_vector(fastio_wdata(7 downto 0));
          when x"08" => reg_porte_ddr<=std_logic_vector(fastio_wdata(7 downto 0));

          when x"09" =>
            clock709375 <= fastio_wdata(0);
          when x"0a" =>
            key_queue_flush <= fastio_wdata(7);
          when x"0b" => reg_portf_out <= std_logic_vector(fastio_wdata);
          when x"0c" => reg_portf_ddr <= std_logic_vector(fastio_wdata);
          when x"0d" => reg_portg_out <= std_logic_vector(fastio_wdata);
          when x"0e" => reg_portg_ddr <= std_logic_vector(fastio_wdata);
          when x"0f" =>
            accessible_key_enable <= fastio_wdata(7);
            accessible_key_extradim_int <= fastio_wdata(6);
          when x"10" => porth_write_strobe <= '1';
          when x"11" =>
            -- bucky keys readonly
            -- @IO:GS $D611.0 WRITE ONLY Connect POT lines to IEC port (for r1 PCB only)
            pot_via_iec <= fastio_wdata(0);
            -- @IO:GS $D611.1 WRITE ONLY enable real joystick ports (for r2 PCB only)
            joyreal_enable_internal <= fastio_wdata(1);
            matrix_disable_modifiers <= fastio_wdata(7);
          when x"12" =>
            widget_enable_internal <= std_logic(fastio_wdata(0));
            ps2_enable_internal <= std_logic(fastio_wdata(1));
            physkey_enable_internal <= std_logic(fastio_wdata(2));
            virtual_enable_internal <= std_logic(fastio_wdata(3));
            -- joykey_enable_internal <= std_logic(fastio_wdata(4));
            osk_debug_display <= fastio_wdata(4);
            joyswap <= fastio_wdata(5);
            joyswap_internal <= std_logic(fastio_wdata(5));
            joya_rotate <= fastio_wdata(6);
            joya_rotate_internal <= fastio_wdata(6);
            joyb_rotate <= fastio_wdata(7);
            joyb_rotate_internal <= fastio_wdata(7);
          when x"14" => portj_out <= std_logic_vector(fastio_wdata);
                        portj_internal <= std_logic_vector(fastio_wdata);
          when x"15" =>
            portk_internal <= std_logic_vector(fastio_wdata);
          when x"16" =>
            portl_internal <= std_logic_vector(fastio_wdata);
          when x"17" =>
            portm_internal <= std_logic_vector(fastio_wdata);
          when x"18" =>
            portn_internal <= std_logic_vector(fastio_wdata);
          when x"19" =>
            porto_write_strobe <= '1';
          when x"1A" =>
            portp_internal <= std_logic_vector(fastio_wdata);
          when x"1b" =>
            -- @IO:GS $D61B.0 WRITEONLY enable/disable Amiga mouse support (1351 emulation) on jostick 1
            amiga_mouse_enable_a_internal <= fastio_wdata(0);
            amiga_mouse_enable_a <= fastio_wdata(0);
            -- @IO:GS $D61B.1 WRITEONLY enable/disable Amiga mouse support (1351 emulation) on jostick 2
            amiga_mouse_enable_b_internal <= fastio_wdata(1);
            amiga_mouse_enable_b <= fastio_wdata(1);
            -- @IO:GS $D61B.2 WRITEONLY assume amiga mouse on jostick 1 if enabled
            amiga_mouse_assume_a_internal <= fastio_wdata(2);
            amiga_mouse_assume_a <= fastio_wdata(2);
            -- @IO:GS $D61B.3 WRITEONLY assume amiga mouse on jostick 2 if enabled
            amiga_mouse_assume_b_internal <= fastio_wdata(3);
            amiga_mouse_assume_b <= fastio_wdata(3);
            -- @IO:GS $D61B.6 WRITEONLY DEBUG disable ASCII key retrigger suppression
            suppress_key_retrigger <= not fastio_wdata(6);
            -- @IO:GS $D61B.7 WRITEONLY DEBUG disable ASCII key glitch suppression
            suppress_key_glitches <= not fastio_wdata(7);
          when x"1d" =>
            disco_led_en_int <= fastio_wdata(7);
            disco_led_en <= fastio_wdata(7);
            disco_led_id_int(6 downto 0) <= fastio_wdata(6 downto 0);
            disco_led_id(6 downto 0) <= fastio_wdata(6 downto 0);
            disco_led_id(7) <= '0';
            -- Latch intensity level only when setting the register to write to.
            disco_led_val <= disco_led_val_int;
          when x"1e" =>
            disco_led_val_int <= fastio_wdata;
          when x"25" => j21out(7 downto 0) <= std_logic_vector(fastio_wdata);
          when x"26" => j21out(11 downto 8) <= std_logic_vector(fastio_wdata(3 downto 0));
          when x"27" => j21ddr(7 downto 0) <= std_logic_vector(fastio_wdata);
          when x"28" => j21ddr(11 downto 8) <= std_logic_vector(fastio_wdata(3 downto 0));
          when x"3C" => sid_mode_int <= fastio_wdata(3 downto 0);
                        dc_track_enable_int <= fastio_wdata(4);
          when x"3D" => dc_track_rate <= fastio_wdata(7 downto 0);
          when others => null;
        end case;
      end if;
    end if;

    -- make sure this doesn't infer a latch
    fastio_rdata <= (others => 'Z');

    -- Reading of registers
    if (fastio_read='1') and (c65uart_cs='1') then
      report "Reading C65 UART controller register";
      case register_number is
        when x"00" =>
          -- @IO:C65 $D600 UART:DATA UART data register (read or write)
          fastio_rdata <= unsigned(reg_data_rx_drive);
        when x"01" =>
          -- @IO:C65 $D601 C65 UART status register
          -- @IO:C65 $D601.0 UART:RXRDY UART RX byte ready flag (clear by reading \$D600)
          -- @IO:C65 $D601.1 UART:RXOVRRUN UART RX overrun flag (clear by reading \$D600)
          -- @IO:C65 $D601.2 UART:PTYERR UART RX parity error flag (clear by reading \$D600)
          -- @IO:C65 $D601.3 UART:FRMERR UART RX framing error flag (clear by reading \$D600)
          fastio_rdata(0) <= reg_status0_rx_full_drive;
          fastio_rdata(1) <= reg_status1_rx_overrun_drive;
          fastio_rdata(2) <= reg_status2_rx_parity_error_drive;
          fastio_rdata(3) <= reg_status3_rx_framing_error_drive;
          fastio_rdata(4) <= reg_status4_rx_idle_mode_drive;
          fastio_rdata(5) <= reg_status5_tx_eot_drive;
          fastio_rdata(6) <= reg_status6_tx_empty_drive;
          fastio_rdata(7) <= reg_status7_xmit_on_drive;
        when x"02" =>
          -- @IO:C65 $D602 C65 UART control register
          -- @IO:C65 $D602.0 UART:PTYEVEN UART Parity: 1=even, 0=odd
          -- @IO:C65 $D602.1 UART:PTYEN UART Parity enable: 1=enabled
          -- @IO:C65 $D602.2-3 UART:CHARSZ UART character size: 00=8, 01=7, 10=6, 11=5 bits per byte
          -- @IO:C65 $D602.4-5 UART:SYNCMOD UART synchronisation mode flags (00=RX \& TX both async, 01=RX sync, TX async, 1x=TX sync, RX async (unused on the MEGA65)
          -- @IO:C65 $D602.6 UART:RXEN UART enable receive
          -- @IO:C65 $D602.7 UART:TXEN UART enable transmit
          fastio_rdata(0) <= reg_ctrl0_parity_even;
          fastio_rdata(1) <= reg_ctrl1_parity_enable;
          fastio_rdata(3 downto 2) <= reg_ctrl23_char_length_deduct;
          fastio_rdata(5 downto 4) <= unsigned(reg_ctrl45_sync_mode_flags);
          fastio_rdata(6) <= reg_ctrl6_rx_enable;
          fastio_rdata(7) <= reg_ctrl7_tx_enable;
        when x"03" =>
          -- @IO:C65 $D603 UART:DIVISOR UART baud rate divisor (16 bit). Baud rate = 7.09375MHz / DIVISOR, unless MEGA65 fast UART mode is enabled, in which case baud rate = 80MHz / DIVISOR
          fastio_rdata <= reg_divisor(7 downto 0);
        when x"04" =>
          -- @IO:C65 $D604 UART:DIVISOR UART baud rate divisor (16 bit). Baud rate = 7.09375MHz / DIVISOR, unless MEGA65 fast UART mode is enabled, in which case baud rate = 80MHz / DIVISOR
          fastio_rdata <= reg_divisor(15 downto 8);
        when x"05" =>
          -- @IO:C65 $D605.7 UART:IMTXIRQ UART interrupt mask: IRQ on TX (not yet implemented on the MEGA65)
          -- @IO:C65 $D605.6 UART:IMRXIRQ UART interrupt mask: IRQ on RX (not yet implemented on the MEGA65)
          -- @IO:C65 $D605.5 UART:IMTXNMI UART interrupt mask: NMI on TX (not yet implemented on the MEGA65)
          -- @IO:C65 $D605.4 UART:IMRXNMI UART interrupt mask: NMI on RX (not yet implemented on the MEGA65)
          fastio_rdata <= unsigned(reg_intmask);
        when x"06" =>
          -- @IO:C65 $D606 C65 UART interrupt flag register
          -- @IO:C65 $D606.7 UART:IFTXIRQ UART interrupt flag: IRQ on TX (not yet implemented on the MEGA65)
          -- @IO:C65 $D606.6 UART:IFRXIRQ UART interrupt flag: IRQ on RX (not yet implemented on the MEGA65)
          -- @IO:C65 $D606.5 UART:IFTXNMI UART interrupt flag: NMI on TX (not yet implemented on the MEGA65)
          -- @IO:C65 $D606.4 UART:IFRXNMI UART interrupt flag: NMI on RX (not yet implemented on the MEGA65)
          fastio_rdata <= unsigned(reg_intflag);
        when x"07" =>
          -- @IO:C65 $D607 C65 UART 2-bit port data register (used for C65 keyboard)
          -- @IO:GS $D607.1 UART:KEYCOL8 C65 keyboard column 8 select
          -- @IO:GS $D607.0 UART:CAPLOCK C65 capslock key sense
          fastio_rdata(7 downto 0) <= reg_porte_read;
        when x"08" =>
          -- @IO:C65 $D608 C65 UART data direction register (used for C65 keyboard)
          -- @IO:GS $D608.0-1 UART:PORTEDDR C65 keyboard extra lines Data Direction Register (DDR)
          fastio_rdata(7 downto 0) <= unsigned(reg_porte_ddr);
        when x"09" =>
          -- @IO:GS $D609 MEGA65 extended UART control register
          -- @IO:GS $D609.0 UARTMISC:UFAST C65 UART BAUD clock source: 1 = 7.09375MHz, 0 = 80MHz (VIC-IV pixel clock)
          -- @IO:GS $D609.7 FSERIAL:DMODE Fast IEC serial (not yet implemented)
          -- @IO:GS $D609.6 FSERIAL:FSDIR Direction register for DMODE (not yet implemented)
          fastio_rdata(0) <= clock709375;
        when x"0a" =>
          -- @IO:GS $D60A.7 UARTMISC:KEYQUEUE 1 = Typing event queue is non-empty. Write 0 to this bit to flush queue.
          -- @IO:GS $D60A.6 UARTMISC:MODKEYCAPS CAPS LOCK key state at top of typing event queue. 1 = held during event.
          -- @IO:GS $D60A.5 UARTMISC:MODKEYSCRL NOSCRL key state at top of typing event queue. 1 = held during event.
          -- @IO:GS $D60A.4 UARTMISC:MODKEYALT ALT key state at top of typing event queue. 1 = held during event.
          -- @IO:GS $D60A.3 UARTMISC:MODKEYMEGA MEGA/C= key state at top of typing event queue. 1 = held during event.
          -- @IO:GS $D60A.2 UARTMISC:MODKEYCTRL CTRL key state at top of typing event queue. 1 = held during event.
          -- @IO:GS $D60A.1 UARTMISC:MODKEYRSHFT Right shift key state at top of typing event queue. 1 = held during event.
          -- @IO:GS $D60A.0 UARTMISC:MODKEYLSHFT Left shift key state at top of typing event queue. 1 = held during event.
          fastio_rdata(7) <= key_presenting;
          fastio_rdata(6 downto 0) <= unsigned(bucky_key_buffered(6 downto 0));
        when x"0b" =>
          -- @IO:GS $D60B.7 UARTMISC:OSKZEN Display hardware zoom of region under first touch point for on-screen keyboard
          -- @IO:GS $D60B.6 UARTMISC:OSKZON Display hardware zoom of region under first touch point always
          -- @IO:GS $D60B.5-0 UARTMISC:PORTF PMOD port A on FPGA board (data) (Nexys4 boards only)
          fastio_rdata(7 downto 0) <= unsigned(reg_portf_read);
        when x"0c" =>
          -- @IO:GS $D60C.0-5 UARTMISC:PORTFDDR PMOD port A on FPGA board (DDR)
          -- @IO:GS $D60C.6-7 UARTMISC:PORTFDDR On Screen Keyboard (OSK) Zoom Control Data Direction Register (DDR). Must be set to output to control these features.
          fastio_rdata(7 downto 0) <= unsigned(reg_portf_ddr);
        when x"0d" =>
          -- @IO:GS $D60D Bit bashing port
          -- @IO:GS $D60D.7 UARTMISC:HDSCL HDMI I2C control interface SCL clock
          -- @IO:GS $D60D.6 UARTMISC:HDSDA HDMI I2C control interface SDA data line
          -- @IO:GS $D60D.5 UARTMISC:SDBSH Enable SD card bitbash mode
          -- @IO:GS $D60D.4 UARTMISC:SDCS SD card CS_BO
          -- @IO:GS $D60D.3 UARTMISC:SDCLK SD card SCLK
          -- @IO:GS $D60D.2 UARTMISC:SDDATA SD card MOSI/MISO
          -- @IO:GS $D60D.1 UARTMISC:RST41 Internal 1541 drive reset (1=reset, 0=operate)
          -- @IO:GS $D60D.0 UARTMISC:CONN41 Internal 1541 drive connect (1=connect internal 1541 drive to IEC bus)
          fastio_rdata(7 downto 0) <= reg_portg_read;
        when x"0e" =>
          -- @IO:GS $D60E UARTMISC:BASHDDR Data Direction Register (DDR) for \$D60D bit bashing port.
          fastio_rdata(7 downto 0) <= unsigned(reg_portg_ddr);
        when x"0f" =>
          -- @IO:GS $D60F.0 UARTMISC:KEYLEFT Directly read C65 Cursor left key
          -- @IO:GS $D60F.1 UARTMISC:KEYUP Directly read C65 Cursor up key
          -- @IO:GS $D60F.7 UARTMISC:ACCESSKEY Enable accessible keyboard input via joystick port 2 fire button
          -- @IO:GS $D60F.6 UARTMISC:OSKDIM Light or heavy dimming of background material behind on-screen keyboard
          -- @IO:GS $D60F.5 UARTMISC:REALHW Set to 1 if the MEGA65 is running on real hardware, set to 0 if emulated (Xemu) or simulated (ghdl)
          fastio_rdata(0) <= key_left;
          fastio_rdata(1) <= key_up;
          fastio_rdata(5) <= real_hardware;
          fastio_rdata(6) <= accessible_key_extradim_int;
          fastio_rdata(7) <= accessible_key_enable;
        when x"10" =>
          -- @IO:GS $D610 UARTMISC:ASCIIKEY Top of typing event queue as ASCII. Write to clear event ready for next.
          fastio_rdata(7 downto 0) <= unsigned(porth);
        when x"11" =>
          -- @IO:GS $D611 Modifier key state.
          -- @IO:GS $D611.7 UARTMISC:MDISABLE Disable modifiers.
          -- @IO:GS $D611.6 UARTMISC:MCAPS CAPS LOCK key state (immediate; read only).
          -- @IO:GS $D611.5 UARTMISC:MSCRL NOSCRL key state (immediate; read only).
          -- @IO:GS $D611.4 UARTMISC:MALT ALT key state (immediate; read only).
          -- @IO:GS $D611.3 UARTMISC:MMEGA MEGA/C= key state (immediate; read only).
          -- @IO:GS $D611.2 UARTMISC:MCTRL CTRL key state (immediate; read only).
          -- @IO:GS $D611.1 UARTMISC:MRSHFT Right shift key state (immediate; read only).
          -- @IO:GS $D611.0 UARTMISC:MLSHFT Left shift key state (immediate; read only).
          fastio_rdata(6 downto 0) <= unsigned(porti(6 downto 0));
          fastio_rdata(7) <= matrix_disable_modifiers;
        when x"12" =>
          -- @   IO:GS $D612.0 UARTMISC:WGTKEY Enable widget board keyboard/joystick input
          fastio_rdata(0) <= widget_enable_internal;
          -- @   IO:GS $D612.1 UARTMISC:PS2KEY Enable ps2 keyboard/joystick input
          fastio_rdata(1) <= ps2_enable_internal;
          -- @   IO:GS $D612.2 UARTMISC:PHYKEY Enable physical keyboard input
          fastio_rdata(2) <= physkey_enable_internal;
          -- @   IO:GS $D612.3 UARTMISC:VRTKEY Enable virtual/snythetic keyboard input
          fastio_rdata(3) <= virtual_enable_internal;
          -- @   IO:GS $D612.4 UARTMISC:PS2JOY Enable PS/2 / USB keyboard simulated joystick input
          fastio_rdata(4) <= joykey_enable_internal;
          -- @IO:GS $D612.4 UARTMISC:OSKDEBUG Debug OSK overlay (WRITE ONLY)
          -- @IO:GS $D612.5 UARTMISC:JOYSWAP Exchange joystick ports 1 \& 2
          fastio_rdata(5) <= joyswap_internal;
          -- @IO:GS $D612.6 UARTMISC:LJOYA Rotate inputs of joystick A by 180 degrees (for left handed use)
          fastio_rdata(6) <= joya_rotate_internal;
          -- @IO:GS $D612.7 UARTMISC:LJOYB Rotate inputs of joystick B by 180 degrees (for left handed use)
          fastio_rdata(7) <= joyb_rotate_internal;
        when x"13" =>
          -- @IO:GS $D613 DEBUG:CRTACSCNT Count of cartridge port memory accesses (read only)
          fastio_rdata <= unsigned(portj_in);
        when x"14" =>
          -- @IO:GS $D614 DEBUG:KEYMATRIXPEEK 8-bit segment of combined keyboard matrix (READ)
          fastio_rdata <= unsigned(portj_internal);
        when x"15" =>
          -- @IO:GS $D615.0-6 UARTMISC:VIRTKEY1 Set to \$7F for no key down, else specify virtual key press.
          -- @IO:GS $D615.7 UARTMISC:OSKEN Enable display of on-screen keyboard composited overlay
          fastio_rdata <= unsigned(portk_internal);
        when x"16" =>
          -- @IO:GS $D616.0-6 UARTMISC:VIRTKEY2 Set to \$7F for no key down, else specify 2nd virtual key press.
          -- @IO:GS $D616.7 UARTMISC:OSKALT Display alternate on-screen keyboard layout (typically dial pad for MEGA65 telephone)
          fastio_rdata <= unsigned(portl_internal);
        when x"17" =>
          -- @IO:GS $D617.0-6 UARTMISC:VIRTKEY3 Set to \$7F for no key down, else specify 3nd virtual key press.
          -- @IO:GS $D617.7 UARTMISC:OSKTOP 1=Display on-screen keyboard at top, 0=Disply on-screen keyboard at bottom of screen.
          fastio_rdata <= unsigned(portm_internal);
        when x"18" =>
          -- @IO:GS $D618 UARTMISC:KSCNRATE Physical keyboard scan rate (\$00=50MHz, \$FF=~200KHz)
          fastio_rdata <= unsigned(portn_internal);
        when x"19" =>
          -- @IO:GS $D619 UARTMISC:PETSCIIKEY Top of typing event queue as PETSCII. Write to clear event ready for next.
          fastio_rdata <= unsigned(porto);
        when x"1a" =>
          -- @IO:GS $D61A UARTMISC:SYSCTL System control flags (target specific)

          fastio_rdata <= unsigned(portp_internal);
        when x"1b" =>
          -- @IO:GS $D61B DEBUG:AMIMOUSDETECT READ 1351/amiga mouse auto detection DEBUG
          fastio_rdata <= mouse_debug;
        when x"1c" =>
          -- @IO:GS $D61C DEBUG:1541PCLSB internal 1541 PC LSB
          fastio_rdata(7 downto 0) <= unsigned(portq_in);
        when x"1d" =>
          -- @IO:GS $D61D.7 UARTMISC:KEYLED!ENA Keyboard LED control enable
          -- @IO:GS $D61D.0-6 UARTMISC:KEYLED!REG Keyboard LED register select (R,G,B channels x 4 = 0 to 11)
          -- @IO:GS $D61E UARTMISC:KEYLED!VAL Keyboard LED register value (write only)
          fastio_rdata(7) <= disco_led_en_int;
          fastio_rdata(6 downto 0) <= disco_led_id_int(6 downto 0);
        when x"1e" =>
          fastio_rdata(7 downto 0) <= disco_led_val_int;
        when x"1F" =>
          -- @IO:GS $D61F DEBUG:BUCKYCOPY DUPLICATE Modifier key state (hardware accelerated keyboard scanner).
          fastio_rdata(7 downto 0) <= unsigned(porti);
          -- @IO:GS $D620 UARTMISC:POTAX Read Port A paddle X, without having to fiddle with SID/CIA settings.
          -- @IO:GS $D621 UARTMISC:POTAY Read Port A paddle Y, without having to fiddle with SID/CIA settings.
          -- @IO:GS $D622 UARTMISC:POTBX Read Port B paddle X, without having to fiddle with SID/CIA settings.
          -- @IO:GS $D623 UARTMISC:POTBY Read Port B paddle Y, without having to fiddle with SID/CIA settings.
        when x"20" => fastio_rdata <= pota_x;
        when x"21" => fastio_rdata <= pota_y;
        when x"22" => fastio_rdata <= potb_x;
        when x"23" => fastio_rdata <= potb_y;
        when x"24" =>
          -- @IO:GS $D624 DEBUG:POTDEBUG READ ONLY flags for paddles. See c65uart.vhdl for more information.
          -- @IO:GS $D624.0 Paddles connected via IEC port (rev1 PCB debug)
          -- @IO:GS $D624.1 pot_drain signal
          -- @IO:GS $D624.3-2 CIA porta bits 7-6 for POT multiplexor
          -- @IO:GS $D624.4 fa_potx line
          -- @IO:GS $D624.5 fa_poty line
          -- @IO:GS $D624.6 fb_potx line
          -- @IO:GS $D624.7 fb_poty line
          fastio_rdata(0) <= pot_via_iec;
          fastio_rdata(1) <= pot_drain;
          fastio_rdata(3 downto 2) <= unsigned(cia1portb_out(7 downto 6));
          fastio_rdata(4) <= fa_potx;
          fastio_rdata(5) <= fa_poty;
          fastio_rdata(6) <= fb_potx;
          fastio_rdata(7) <= fb_poty;
        -- @IO:GS $D625 UARTMISC:J21L J21 pins 1 -- 6, 9 -- 10 input/output values
        -- @IO:GS $D626 UARTMISC:J21H J21 pins 11 -- 14 input/output values
        -- @IO:GS $D627 UARTMISC:J21LDDR J21 pins 1 -- 6, 9 -- 10 data direction register
        -- @IO:GS $D628.0-3 UARTMISC:J21HDDR J21 pins 11 -- 14 data direction register
        -- @IO:GS $D628.4-7 UARTMISC:BOARDMINOR Read PCB minor revision (R5+ only, else reads zeroes)
        when x"25" => fastio_rdata <= unsigned(j21in(7 downto 0));
        when x"26" => fastio_rdata(3 downto 0) <= (unsigned(j21in(11 downto 8)));
                      fastio_rdata(7 downto 4) <= "0000";
        when x"27" => fastio_rdata <= unsigned(j21ddr(7 downto 0));
        when x"28" => fastio_rdata(3 downto 0) <= (unsigned(j21ddr(11 downto 8)));
                      fastio_rdata(7 downto 4) <= board_minor;
        when x"29" =>
          -- @IO:GS $D629 UARTMISC:M65MODEL MEGA65 model ID. Can be used to determine the model of MEGA65 a programme is running on, e.g., to enable touch controls on MEGAphone.
          case target is
            when mega65r5 | mega65r6 | mega65r7 | mega65r8 | mega65r9 | mega65r10
              | mega65r11 | mega65r12 | mega65r13 | mega65r14 =>
              fastio_rdata(7 downto 4) <= x"0";
              fastio_rdata(3 downto 0) <= board_major;
            when others =>
              fastio_rdata <= target_id;
          end case;

        -- @IO:GS $D62A KBD:FWDATEL LSB of keyboard firmware date stamp (days since 1 Jan 2020)
        -- @IO:GS $D62B KBD:FWDATEH MSB of keyboard firmware date stamp (days since 1 Jan 2020)
        when x"2a" => fastio_rdata <= kbd_datestamp(7 downto 0);
        when x"2b" => fastio_rdata(5 downto 0) <= kbd_datestamp(13 downto 8);
                      fastio_rdata(7 downto 6) <= "00";
        -- @IO:GS $D62C KBD:FWGIT0 LSB of keyboard firmware git commit
        -- @IO:GS $D62D KBD:FWGIT0 2nd byte of keyboard firmware git commit
        -- @IO:GS $D62E KBD:FWGIT0 3rd byte of keyboard firmware git commit
        -- @IO:GS $D62F KBD:FWGIT0 MSB of keyboard firmware git commit
        when x"2c" => fastio_rdata <= kbd_commit(7 downto 0);
        when x"2d" => fastio_rdata <= kbd_commit(15 downto 8);
        when x"2e" => fastio_rdata <= kbd_commit(23 downto 16);
        when x"2f" => fastio_rdata <= kbd_commit(31 downto 24);
        -- @IO:GS $D630 FPGA:FWDATEL LSB of MEGA65 FPGA design date stamp (days since 1 Jan 2020)
        -- @IO:GS $D631 FPGA:FWDATEH MSB of MEGA65 FPGA design date stamp (days since 1 Jan 2020)
        when x"30" => fastio_rdata <= fpga_datestamp(7 downto 0);
        when x"31" => fastio_rdata <= fpga_datestamp(15 downto 8);
        -- @IO:GS $D632 FPGA:FWGIT0 LSB of MEGA65 FPGA design git commit
        -- @IO:GS $D633 FPGA:FWGIT0 2nd byte of MEGA65 FPGA design git commit
        -- @IO:GS $D634 FPGA:FWGIT0 3rd byte of MEGA65 FPGA design git commit
        -- @IO:GS $D635 FPGA:FWGIT0 MSB of MEGA65 FPGA design git commit
        when x"32" => fastio_rdata <= fpga_commit(7 downto 0);
        when x"33" => fastio_rdata <= fpga_commit(15 downto 8);
        when x"34" => fastio_rdata <= fpga_commit(23 downto 16);
        when x"35" => fastio_rdata <= fpga_commit(31 downto 24);
        -- @IO:GS $D636 AUXFPGA:FWDATEL LSB of Auxilliary (MAX10) FPGA design date stamp (days since 1 Jan 2020)
        -- @IO:GS $D637 AUXFPGA:MFWDATEH MSB of Auxilliary (MAX10) FPGA design date stamp (days since 1 Jan 2020)
        when x"36" => fastio_rdata <= max10_fpga_date(7 downto 0);
        when x"37" => fastio_rdata <= max10_fpga_date(15 downto 8);
        -- @IO:GS $D638 AUXFPGA:FWGIT0 LSB of Auxilliary (MAX10) FPGA design git commit
        -- @IO:GS $D639 AUXFPGA:FWGIT0 2nd byte of Auxilliary (MAX10) FPGA design git commit
        -- @IO:GS $D63A AUXFPGA:FWGIT0 3rd byte of Auxilliary (MAX10) FPGA design git commit
        -- @IO:GS $D63B AUXFPGA:FWGIT0 MSB of Auxilliary (MAX10) FPGA design git commit
        when x"38" => fastio_rdata <= max10_fpga_commit(7 downto 0);
        when x"39" => fastio_rdata <= max10_fpga_commit(15 downto 8);
        when x"3A" => fastio_rdata <= max10_fpga_commit(23 downto 16);
        when x"3B" => fastio_rdata <= max10_fpga_commit(31 downto 24);
        -- @IO:GS $D63C.0-3 SID:SIDMODE Select SID mode: 0=6581, 1=8580
        -- @IO:GS $D63C.4 AUDIOMIX:DCTRKEN Enable DC offset subtraction in audio mixer
        -- @IO:GS $D63C.5-7 DEBUG:RESETSRC Source of last CPU reset
        when x"3c" => fastio_rdata(3 downto 0) <= sid_mode_int;
                      fastio_rdata(4) <= dc_track_enable_int;
                      fastio_rdata(7 downto 5) <= last_reset_source;
        -- @IO:GS $D63D AUDIOMIX:DCTIME Audio mixer DC-estimation time step. Lower values = faster updating of DC estimation, at the cost of making low-frequencies quieter.
        when x"3d" => fastio_rdata <= dc_track_rate_int;
        when x"3e" => fastio_rdata <= reset_monitor_count(7 downto 0);
        when x"3f" => fastio_rdata(3 downto 0) <= reset_monitor_count(11 downto 8);
                      fastio_rdata(7 downto 4) <= x"0";

        when others =>
          report "Reading untied register, result = Z";
          fastio_rdata <= (others => 'Z');
      end case;
    else
      fastio_rdata <= (others => 'Z');
    end if;

    if rising_edge(pixelclock) then

      if rx_clear_flags='1' then
        -- Clear byte read flag
        reg_status0_rx_full <= '0';
        -- Clear RX over-run flag
        reg_status1_rx_overrun <= '0';
        -- Clear RX parity error flag
        reg_status2_rx_parity_error <= '0';
        -- Clear RX framing error flag
        reg_status3_rx_framing_error <= '0';
      end if;

      if (baud_subcounter + baud_subcounter_step < 1048576) then
        baud_subcounter <= baud_subcounter + baud_subcounter_step;
        tick709375 <= '0';
      else
        baud_subcounter <= baud_subcounter + baud_subcounter_step - 1048576;

        -- One baud divisor tick has elapsed.
        -- Based on TX and RX modes, take the appropriate action.
        -- Each tick here is 1/2 a bit.
        tick709375 <= '1';
      end if;
      if tick709375='1' or clock709375='0' then
        -- Depending on whether we are running from the 7.09375MHz
        -- clock or the 81MHz pixel clock, see if we are at a baud tick
        -- (81MHz clock is used for baud rates above 57.6K.)
        fine_tick <= '1';
      else
        fine_tick <= '0';
      end if;
      if fine_tick='1' then
        if reg_tick_countdown > 0 then
          reg_tick_countdown <= reg_tick_countdown - 1;
          baud_tick <= '0';
        else
          reg_tick_countdown <= reg_divisor;
          baud_tick <= '1';
        end if;
      end if;

      -- Keep track of last 16 samples, and update RX value accordingly.
      -- We require consensus to switch between 0 and 1
      rx_samples(15 downto 1) <= rx_samples(14 downto 0);
      rx_samples(0) <= uart_rx;
      if rx_samples = "1111111111111111" then
        filtered_rx <= '1';
      end if;
      if rx_samples = "0000000000000000" then
        filtered_rx <= '0';
      end if;

      if baud_tick = '0' then
        -- Cross-domain accept next byte to TX from CPU clock side
        if reg_data_tx_toggle /= reg_data_tx_toggle_prev then
          reg_data_tx_toggle_prev <= reg_data_tx_toggle;
          reg_status6_tx_empty <= '0';
        end if;
      else
        -- Here we have a clock tick that is 7.09375MHz/reg_divisor
        -- (or 81MHz/reg_divisor if clock709375 is not asserted).
        -- So we now have a clock which is the target baud rate.
        -- XXX We should adjust our timing position to try to match the phase
        -- of the sender, but we aren't doing that right now. Instead, we will
        -- use the simple consensus filtered RX signal, and just read it.

        -- Progress TX state machine
        uart_tx <= '1';
        if tx_in_progress = '0' and reg_status6_tx_empty='0' and reg_ctrl7_tx_enable='1' then
          -- Sent stop bit
          uart_tx <= '0';
          tx_in_progress <= '1';
          tx_bits_to_send <= 8 - to_integer(reg_ctrl23_char_length_deduct);
          tx_buffer <= reg_data_tx;
          reg_status6_tx_empty <= '1';
        end if;
        if tx_in_progress='1' then
          if tx_bits_to_send > 0 then
            uart_tx <= tx_buffer(0);
            tx_buffer(6 downto 0) <= tx_buffer(7 downto 1);
            tx_bits_to_send <= tx_bits_to_send - 1;
          else
            -- Stop bit
            -- XXX We don't support parity
            uart_tx <= '0';
            tx_stop_bit_sent <= '1';
          end if;
          if tx_stop_bit_sent = '1' then
            tx_in_progress <= '0';
            tx_stop_bit_sent <= '0';
          end if;
        end if;

        -- Progress RX state machine
        if rx_in_progress='0' then
          -- Not yet receiving a byte, so see if we see something interesting
          if filtered_rx='0' and reg_ctrl6_rx_enable='1' then
            -- Start bit
            rx_buffer <= (others => '1');
            rx_in_progress <= '1';
            rx_bits_remaining <= 8 - to_integer(reg_ctrl23_char_length_deduct);
          end if;
        else
          -- Receiving data, parity and/or stop bit
          if rx_bits_remaining > 0 then
            -- Receive next bit
            rx_buffer(6 downto 0) <= rx_buffer(7 downto 1);
            rx_buffer(7) <= filtered_rx;
            rx_bits_remaining <= rx_bits_remaining - 1;
          else
            -- Receive stop bit (or parity when we support it)
            rx_in_progress <= '0';
            -- Stop bit:
            if filtered_rx='0' then
              -- Received byte
              reg_status0_rx_full <= '1';
              if reg_status0_rx_full = '1' then
              end if;
              -- Allow short bytes
              case reg_ctrl23_char_length_deduct is
                when "01" => reg_data_rx_driver(6 downto 0) <= rx_buffer(7 downto 1);
                             reg_data_rx_driver(7) <= '1';
                when "10" => reg_data_rx_driver(5 downto 0) <= rx_buffer(7 downto 2);
                             reg_data_rx_driver(7 downto 6) <= (others => '1');
                when "11" => reg_data_rx_driver(4 downto 0) <= rx_buffer(7 downto 3);
                             reg_data_rx_driver(7 downto 5) <= (others => '1');
                when others => reg_data_rx_driver <= rx_buffer;
              end case;
              -- XXX Work out parity and set state for reading it.
            else
              -- Framing error
              reg_status3_rx_framing_error <= '1';
              -- Make bad data visible, purely for debug purposes
              reg_data_rx_driver <= rx_buffer;
            end if;
            -- XXX Assert IRQ and/or NMI according to RX interrupt masks
          end if;
        end if;
      end if;
    end if;
  end process;

end behavioural;
