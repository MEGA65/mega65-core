--------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    22:30:37 12/10/2013
-- Design Name:
-- Module Name:    container - Behavioral
-- Project Name:
-- Target Devices:
-- Tool versions:
-- Description:
--
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
--------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library UNISIM;
use UNISIM.vcomponents.all;

library STD;
use STD.textio.all;

use work.cputypes.all;
use work.types_pkg.all;

entity container is
  port (
    clk_in       : in std_logic;
    reset_button : in std_logic;

    -- Keyboard.
    porta_pins : inout std_logic_vector(7 downto 0);
    portb_pins : inout std_logic_vector(7 downto 0);

    -- Joysticks.
    fa_left  : in std_logic;
    fa_right : in std_logic;
    fa_up    : in std_logic;
    fa_down  : in std_logic;
    fa_fire  : in std_logic;
    fb_left  : in std_logic;
    fb_right : in std_logic;
    fb_up    : in std_logic;
    fb_down  : in std_logic;
    fb_fire  : in std_logic;

    -- HDMI.
    tmds_data_p : out std_logic_vector(2 downto 0);
    tmds_data_n : out std_logic_vector(2 downto 0);
    tmds_clk_p  : out std_logic;
    tmds_clk_n  : out std_logic;

    -- QSPI flash.
    qspi_db  : inout unsigned(3 downto 0);
    qspi_csn : out   std_logic;

    -- Internal SD-card.
    int_sd_reset : out std_logic;
    int_sd_clock : out std_logic;
    int_sd_mosi  : out std_logic;
    int_sd_miso  : in  std_logic;

    -- Serial monitor.
    uart_txd : out std_logic;
    rsrx     : in  std_logic;

    -- Debug LEDs.
    led : inout std_logic
  );
end container;

architecture Behavioral of container is

  signal irq                  : std_logic := '1';
  signal nmi                  : std_logic := '1';
  signal reset_out            : std_logic := '1';
  signal btncpureset          : std_logic := '1';
  signal cpuclock             : std_logic;
  signal pixelclock           : std_logic;
  signal clock27              : std_logic;
  signal clock270             : std_logic;
  signal restore_key          : std_logic := '1';
  signal sector_buffer_mapped : std_logic;
  signal fpga_temperature     : std_logic_vector(11 downto 0) := (others => '0');

  -- QSPI flash.
  signal qspi_clock  : std_logic;
  signal qspi_db_oe  : std_logic;
  signal qspi_db_out : unsigned(3 downto 0);
  signal qspi_db_in  : unsigned(3 downto 0);

  -- SYSCTL configuration register.
  signal portp       : unsigned(7 downto 0);
  signal portp_drive : unsigned(7 downto 0);

  -- Wukong keyboard portb pin reflection and carge control
  signal portb_charge_pins : std_logic;
  signal portb_pins_in : std_logic_vector(7 downto 0);

  -- Audio (PCM).
  constant clock_frequency      : integer := 40500000;
  constant target_sample_rate   : integer := 48000;
  signal audio_left             : std_logic_vector(19 downto 0);
  signal audio_right            : std_logic_vector(19 downto 0);
  signal audio_left_slow        : std_logic_vector(19 downto 0);
  signal audio_right_slow       : std_logic_vector(19 downto 0);
  signal h_audio_left           : std_logic_vector(19 downto 0);
  signal h_audio_right          : std_logic_vector(19 downto 0);
  signal audio_counter          : integer                       := 0;
  signal sample_ready_toggle    : std_logic                     := '0';
  signal audio_counter_interval : unsigned(25 downto 0)         := to_unsigned(4 * clock_frequency/target_sample_rate, 26);
  signal acr_counter            : integer range 0 to 12288      := 0;
  signal pcm_clk                : std_logic                     := '0';
  signal pcm_rst                : std_logic                     := '1';
  signal pcm_clken              : std_logic                     := '0';
  signal pcm_l                  : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(0, 16));
  signal pcm_r                  : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(0, 16));
  signal pcm_acr                : std_logic                     := '0';

  -- Video (HDMI).
  signal dvi_reset       : std_logic := '1';
  signal dvi_select      : std_logic := '0';
  signal v_hdmi_hsync    : std_logic;
  signal v_vsync         : std_logic;
  signal v_red           : unsigned(7 downto 0);
  signal v_green         : unsigned(7 downto 0);
  signal v_blue          : unsigned(7 downto 0);
  signal hdmi_dataenable : std_logic;
  signal tmds            : slv_9_0_t(0 to 2);

  -- Slow device bus.
  signal slow_access_request_toggle : std_logic;
  signal slow_access_ready_toggle   : std_logic;
  signal slow_access_write          : std_logic;
  signal slow_access_address        : unsigned(27 downto 0);
  signal slow_access_wdata          : unsigned(7 downto 0);
  signal slow_access_rdata          : unsigned(7 downto 0);

  -- CBM floppy serial port (not supported).
  signal iec_clk_en  : std_logic := 'Z';
  signal iec_data_en : std_logic := 'Z';
  signal iec_srq_en  : std_logic := 'Z';
  signal iec_data_o  : std_logic := 'Z';
  signal iec_srq_o   : std_logic := 'Z';
  signal iec_reset   : std_logic := 'Z';
  signal iec_clk_o   : std_logic := 'Z';
  signal iec_data_i  : std_logic := '1';
  signal iec_clk_i   : std_logic := '1';
  signal iec_srq_i   : std_logic := '1';
  signal iec_atn     : std_logic := 'Z';

  -- Expansion / cartridge port.
  signal cart_ba   : std_logic             := 'Z';
  signal cart_rw   : std_logic             := 'Z';
  signal cart_roml : std_logic             := 'Z';
  signal cart_romh : std_logic             := 'Z';
  signal cart_io1  : std_logic             := 'Z';
  signal cart_io2  : std_logic             := 'Z';
  signal cart_a    : unsigned(15 downto 0) := (others => 'Z');

begin

  -- Xilinx primitibe to allow direct control of the clock signal connected to
  -- the QSPI flash chip used for configuration of the FPGA.
  STARTUPE2_inst : STARTUPE2
    generic map(
      PROG_USR      => "FALSE", -- Activate program event security feature. Requires encrypted bitstreams.
      SIM_CCLK_FREQ => 10.0     -- Set the Configuration Clock Frequency(ns) for simulation.
    )
    port map(
      --CFGCLK    => CFGCLK,     -- 1-bit output: Configuration main clock output
      --CFGMCLK   => CFGMCLK,    -- 1-bit output: Configuration internal oscillator clock output
      --EOS       => EOS,        -- 1-bit output: Active high output signal indicating the End Of Startup.
      --PREQ      => PREQ,       -- 1-bit output: PROGRAM request to fabric output
      CLK       => '0',        -- 1-bit input: User start-up clock input
      GSR       => '0',        -- 1-bit input: Global Set/Reset input (GSR cannot be used for the port name)
      GTS       => '0',        -- 1-bit input: Global 3-state input (GTS cannot be used for the port name)
      KEYCLEARB => '0',        -- 1-bit input: Clear AES Decrypter Key input from Battery-Backed RAM (BBRAM)
      PACK      => '0',        -- 1-bit input: PROGRAM acknowledge input
      USRCCLKO  => qspi_clock, -- 1-bit input: User CCLK input
      USRCCLKTS => '0',        -- 1-bit input: User CCLK 3-state enable input
      USRDONEO  => '1',        -- 1-bit input: User DONE pin output control
      USRDONETS => '1'         -- 1-bit input: User DONE 3-state enable output DISABLE
    );

  -- Clocks.
  clocks : entity work.clocking50mhz
    port map(
      clk_in   => clk_in,
      clock27  => clock27,    --   27   MHz
      clock41  => cpuclock,   --   40.5 MHz
      clock81p => pixelclock, --   81   MHz
      clock270 => clock270    --  270   MHz
    );

  -- Measure FPGA die temperature.
  fpgatemp0 : entity work.fpgatemp
    generic map(DELAY_CYCLES => 480)
    port map(
      rst  => '0',
      clk  => cpuclock,
      temp => fpga_temperature);

  -- Convert 20-bit audio @ 12.288 MHz to 16-bit audio @ 12.288 MHz.
  AUDIO_TONE : entity work.audio_out_test_tone
    generic map(
      -- You have to update audio_clock if you change this
      fref => 50.0
    )
    port map(
      select_44100        => '0',
      ref_rst             => dvi_reset,
      ref_clk             => clk_in,
      pcm_rst             => pcm_rst,
      pcm_clk             => pcm_clk,
      pcm_clken           => pcm_clken,
      audio_left_slow     => audio_left_slow,
      audio_right_slow    => audio_right_slow,
      sample_ready_toggle => sample_ready_toggle,
      pcm_l               => pcm_l,
      pcm_r               => pcm_r
    );

  -- Video (VGA) + audio (PCM) to HDMI converter.
  hdmi0 : entity work.vga_to_hdmi
    port map(
      select_44100 => '0',
      -- Disable HDMI-style audio if one (from portp bit 1)
      dvi     => dvi_select,
      vic     => std_logic_vector(to_unsigned(17, 8)), -- CEA/CTA VIC 17=576p50 PAL, 2 = 480p60 NTSC
      aspect  => "01",                                 -- 01=4:3, 10=16:9
      pix_rep => '0',                                  -- no pixel repetition
      vs_pol  => '1',                                  -- 1=active high
      hs_pol  => '1',

      vga_rst => dvi_reset,       -- active high reset
      vga_clk => clock27,         -- VGA pixel clock
      vga_vs  => v_vsync,         -- active high vsync
      vga_hs  => v_hdmi_hsync,    -- active high hsync
      vga_de  => hdmi_dataenable, -- pixel enable
      vga_r   => std_logic_vector(v_red),
      vga_g   => std_logic_vector(v_green),
      vga_b   => std_logic_vector(v_blue),

      -- Feed in audio
      pcm_rst   => pcm_rst,   -- active high audio reset
      pcm_clk   => pcm_clk,   -- audio clock at fs
      pcm_clken => pcm_clken, -- audio clock enable
      pcm_l     => pcm_l,
      pcm_r     => pcm_r,
      pcm_acr   => pcm_acr,                                  -- 1KHz
      pcm_n     => std_logic_vector(to_unsigned(6144, 20)),  -- ACR N value
      pcm_cts   => std_logic_vector(to_unsigned(27000, 20)), -- ACR CTS value

      tmds => tmds
    );

  -- High-speed serializer for HDMI clock.
  HDMI_CLK : entity work.serialiser_10to1_selectio
    port map(
      clk_x10 => clock270,
      d       => "0000011111",
      out_p   => tmds_clk_p,
      out_n   => tmds_clk_n
    );

  -- High-speed serializers for HDMI data.
  GEN_HDMI_DATA : for i in 0 to 2 generate
  begin
    HDMI_DATA : entity work.serialiser_10to1_selectio
      port map(
        clk_x10 => clock270,
        d       => tmds(i),
        out_p   => tmds_data_p(i),
        out_n   => tmds_data_n(i)
      );
  end generate GEN_HDMI_DATA;

  -- Slow device manager.
  slow_devices0 : entity work.slow_devices
    generic map(
      target => wukong
    )
    port map(
      cpuclock             => cpuclock,
      pixelclock           => pixelclock,
      reset                => reset_out,
      sector_buffer_mapped => sector_buffer_mapped,

      -- Slow device bus.
      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle   => slow_access_ready_toggle,
      slow_access_write          => slow_access_write,
      slow_access_address        => slow_access_address,
      slow_access_wdata          => slow_access_wdata,
      slow_access_rdata          => slow_access_rdata,

      -- Expansion RAM interface (upto 127MB)
      expansionram_data_ready_toggle => '1',
      expansionram_busy              => '1',

      -- Expansion / cartridge port.
      cart_nmi   => 'Z',
      cart_irq   => 'Z',
      cart_dma   => 'Z',
      cart_exrom => 'Z',
      cart_ba    => cart_ba,
      cart_rw    => cart_rw,
      cart_roml  => cart_roml,
      cart_romh  => cart_romh,
      cart_io1   => cart_io1,
      cart_game  => 'Z',
      cart_io2   => cart_io2,
      cart_d_in  => (others => 'Z'),
      cart_a     => cart_a
    );

  -- MEGA65 main component.
  machine0 : entity work.machine
    generic map(
      cpu_frequency   => 40500000,
      target          => wukong,
      hyper_installed => false
    )
    port map(
      pixelclock           => pixelclock,
      cpuclock             => cpuclock,
      uartclock            => cpuclock,
      clock162             => '0',
      clock200             => '0',
      clock27              => clock27,
      clock50mhz           => '0',
      no_hyppo             => '0',
      kbd_datestamp        => (others => '0'),
      kbd_commit           => (others => '0'),
      btncpureset          => btncpureset,
      reset_out            => reset_out,
      irq                  => irq,
      nmi                  => nmi,
      restore_key          => restore_key,
      cpu_exrom            => '1',
      cpu_game             => '1',
      sector_buffer_mapped => sector_buffer_mapped,
      fpga_temperature     => fpga_temperature,

      -- QSPI flash.
      qspi_clock => qspi_clock,
      qspicsn    => qspi_csn,
      qspidb     => qspi_db_out,
      qspidb_in  => qspi_db_in,
      qspidb_oe  => qspi_db_oe,

      -- Audio.
      audio_left  => audio_left,
      audio_right => audio_right,

      -- Video.
      vsync           => v_vsync,
      hdmi_hsync      => v_hdmi_hsync,
      vgared          => v_red,
      vgagreen        => v_green,
      vgablue         => v_blue,
      hdmi_dataenable => hdmi_dataenable,

      -- Slow device bus.
      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle   => slow_access_ready_toggle,
      slow_access_address        => slow_access_address,
      slow_access_write          => slow_access_write,
      slow_access_wdata          => slow_access_wdata,
      slow_access_rdata          => slow_access_rdata,

      -- CIA1 ports (physical keyboard and joysticks).
      porta_pins    => porta_pins,
      portb_pins    => portb_pins_in,
      portb_charge_pins => portb_charge_pins,
      caps_lock_key => '1',
      keyleft       => '0',
      keyup         => '0',
      fa_fire       => fa_fire ,
      fa_up         => fa_up   ,
      fa_left       => fa_left ,
      fa_down       => fa_down ,
      fa_right      => fa_right,
      fb_fire       => fb_fire ,
      fb_up         => fb_up   ,
      fb_left       => fb_left ,
      fb_down       => fb_down ,
      fb_right      => fb_right,
      fa_potx       => '0',
      fa_poty       => '0',
      fb_potx       => '0',
      fb_poty       => '0',

      -- Internal SD card (bus #1).
      cs_bo  => int_sd_reset,
      sclk_o => int_sd_clock,
      mosi_o => int_sd_mosi,
      miso_i => int_sd_miso,

      -- Serial monitor.
      UART_TXD => uart_txd,
      RsRx     => rsrx,

      -- SYSCTL configuration register.
      portp_out => portp,

      -- Switches and buttons.
      sw    => (others => '0'),
      dipsw => (others => '0'),
      btn   => (others => '1'),

      --------------------------------------------------------------------------
      -- Unsupported components and peripherals.
      --------------------------------------------------------------------------

      -- CBM floppy serial port (not supported).
      iec_data_external => '1',
      iec_clk_external  => '1',
      iec_srq_external  => '1',
      iec_bus_active    => '0',

      -- External SD card (bus #0, priority) (not supported).
      miso2_i => '1',

      -- Floppy drive interface (not supported).
      f_index        => '1',
      f_track0       => '1',
      f_writeprotect => '1',
      f_rdata        => '1',
      f_diskchanged  => '1',

      -- Ethernet controller (not supported).
      eth_rxd       => "00",
      eth_rxer      => '0',
      eth_rxdv      => '0',
      eth_interrupt => '0',

      -- Accelerometer (not supported).
      aclMISO => '1',
      aclInt1 => '1',
      aclInt2 => '1',

      -- Temperature sensor / I2C bus #0 (not supported).
      tmpint => '1',
      tmpct  => '1',

      -- Microphones (not supported).
      micData0 => '1',
      micData1 => '1',

      -- Buffered UART (not supported).
      buffereduart_ringindicate => (others => '0'),

      -- PS/2 keyboard (not supported).
      ps2data  => '1',
      ps2clock => '1',

      -- Widget board / MEGA65R2 keyboard (not supported).
      widget_matrix_col => (others => '1'),
      widget_restore    => '1',
      widget_capslock   => '1',
      widget_joya       => (others => '1'),
      widget_joyb       => (others => '1')
    );

  -- Generate a 1 KHz ACR pulse train from 12.288 MHz.
  process (pcm_clk) is
  begin
    if rising_edge(pcm_clk) then
      if acr_counter /= (12288 - 1) then
        acr_counter <= acr_counter + 1;
        pcm_acr     <= '0';
      else
        pcm_acr     <= '1';
        acr_counter <= 0;
      end if;
    end if;
  end process;

  process (portb_pins, portb_charge_pins) is
  begin
    if portb_charge_pins = '1' then
      portb_pins <= (others => '1');
    else
      portb_pins <= (others => 'Z');
    end if;
    portb_pins_in <= portb_pins;
  end process;

  -- Various processing steps synchronized to the CPU clock.
  process (cpuclock) is
  begin
    -- Drive most ports, to relax timing
    if rising_edge(cpuclock) then
      -- @IO:GS $D61A.7 SYSCTL:AUDINV Invert digital video audio sample values
      -- @IO:GS $D61A.4 SYSCTL:LED Control LED next to U1 on mother board
      -- @IO:GS $D61A.3 SYSCTL:AUD48K Select 48KHz or 44.1KHz digital video audio sample rate
      -- @IO:GS $D61A.2 SYSCTL:AUDDBG Visualise audio samples (DEBUG)
      -- @IO:GS $D61A.1 SYSCTL:DVI Control digital video as DVI (disables audio)
      -- @IO:GS $D61A.0 SYSCTL:AUDMUTE Mute digital video audio (MEGA65 R2 only)
      portp_drive <= portp;
      dvi_select  <= portp_drive(1);

      -- The reset_button signal is active low, btncpureset is active low.
      btncpureset <= reset_button;

      -- Provide and clear single reset impulse to digital video output modules.
      if reset_button = '1' then
        dvi_reset <= '0';
      end if;

      -- We need to pass audio to 12.288 MHz clock domain. Easiest way is to
      -- hold samples constant for 16 ticks, and have a slow toggle. At 40.5MHz
      -- and 48KHz sample rate, we have a ratio of 843.75 Thus we need to
      -- calculate the remainder, so that we can get the sample rate EXACTLY
      -- 48KHz. Otherwise we end up using 844, which gives a sample rate of
      -- 40.5MHz / 844 = 47.986KHz, which might just be enough to throw some
      -- monitors out, since it means that the CTS / N rates will be wrong.
      -- (Or am I just chasing my tail, because this is only used to set the
      -- rate at which we LATCH the samples?)
      if audio_counter < to_integer(audio_counter_interval) then
        audio_counter <= audio_counter + 4;
      else
        audio_counter       <= audio_counter - to_integer(audio_counter_interval);
        sample_ready_toggle <= not sample_ready_toggle;
        audio_left_slow     <= h_audio_left;
        audio_right_slow    <= h_audio_right;
      end if;
    end if;
  end process;

  -- Handle data direction on the QSPI flash data pins.
  qspi_db    <= qspi_db_out when qspi_db_oe = '1' else "ZZZZ";
  qspi_db_in <= qspi_db;

  -- Invert audio sign bit if requested.
  h_audio_right <= audio_right when portp_drive(7) = '0' else ((not audio_right(19)) & audio_right(18 downto 0));
  h_audio_left  <= audio_left  when portp_drive(7) = '0' else ((not audio_left (19)) & audio_left (18 downto 0));

  -- LED on main board (active low).
  led <= not portp_drive(4);

end Behavioral;
