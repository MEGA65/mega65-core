library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use IEEE.numeric_std.ALL;

library unisim;
use unisim.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

entity clocking is
   port (
      -- Clock in ports
      clk_in     : in  std_logic;
      
      -- Clock out ports
      clock27    : out std_logic;
      clock41    : out std_logic;
      clock50    : out std_logic;
      clock74p22 : out std_logic;
      clock81p   : out std_logic;
      clock163   : out std_logic;
      clock163m  : out std_logic;
      clock200   : out std_logic;
      clock270   : out std_logic;
      clock325   : out std_logic;

      -- For HDMI at 720p as well as at 576p and 480p (a design that connects
      -- none of these gets none of what makes them):
      -- 720p's pixel clock, for whatever makes the 720p picture: near 74.25
      -- MHz, locked to the VIC-IV's frame by hdmi_mode and hdmi_ps_* below
      clock74p25 : out std_logic;
      -- The HDMI encoder's pixel clock and five times it for the serialisers:
      -- 27 and 135 MHz, or with hdmi_720p high clock74p25 and five times it. Hold
      -- what they clock in reset while hdmi_720p changes: the two change one
      -- after the other, neither with a short pulse.
      hdmi_720p     : in  std_logic := '0';
      clock_hdmi    : out std_logic;
      clock_hdmi_x5 : out std_logic;
      -- clock74p25's MMCM is locked
      hdmi_locked   : out std_logic;
      -- The 720p raster is the standard's to the clock (1980 or 1650 x 750),
      -- so a 720p frame is made as long as the VIC-IV's by the pixel clock.
      -- Coarsely by one of four settings (any domain: bit 1 NTSC, bit 0 the
      -- frame of 625 or 525 lines that interlace makes; see DRP_VALS), set
      -- through the MMCM's DRP (the clocks stop for the change: hdmi_locked
      -- low). Finely by the upscaler's trim (clock74p25's domain), the MMCM's
      -- fine phase shift: steps per 2^24 clocks of 270 MHz, positive = later
      -- (slower), a new value with each change of hdmi_ps_tg.
      hdmi_mode     : in  std_logic_vector(1 downto 0) := "00";
      hdmi_ps_rate  : in  signed(21 downto 0) := (others => '0');
      hdmi_ps_tg    : in  std_logic := '0'
   );
end entity;


architecture RTL of clocking is

  signal clk_fb     : std_logic := '0';
  signal clk_fb_sdram       : std_logic := '0';
  signal clk_fb_adjust0     : std_logic := '0';
  signal clk_fb_adjust1     : std_logic := '0';
  signal clk_fb_adjust2     : std_logic := '0';
  signal clk_fb_eth : std_logic := '0';
  signal clock69mhz : std_logic := '0';
  signal u_clock69mhz : std_logic := '0';
  signal u_clock74p22mhz : std_logic := '0';
  signal clock124mhz : std_logic := '0';
  signal u_clock124mhz : std_logic := '0';
  signal clock9969mhz : std_logic := '0'; 
  signal u_clock9969mhz : std_logic := '0'; 

  signal u_clock27 : std_logic := '0';
  signal u_clock135 : std_logic := '0';
  signal clk_fb_hdmi_b : std_logic;
  signal clock74p25_i : std_logic;
  signal u_clock74p25 : std_logic := '0';
  signal u_clock371 : std_logic := '0';
  signal clk_fb_hdmi : std_logic := '0';
  signal u_clock41 : std_logic := '0';
  signal u_clock50 : std_logic := '0';
  signal u_clock81p : std_logic := '0';
  signal u_clock163 : std_logic := '0';
  signal u_clock163m : std_logic := '0';
  signal u_clock200 : std_logic := '0';
  signal u_clock270 : std_logic := '0';
  signal u_clock325 : std_logic := '0';
  signal clock270_i : std_logic;
  signal clock50_i : std_logic;
  -- The four settings, as the upscaler asks for them by the VIC-IV's frame
  -- (hdmi_mode: bit 1 NTSC, bit 0 interlace), each a little off the rate
  -- that frame needs and the fine phase shift making up the rest:
  --   00 PAL,  624 lines: 100 x 59.5   / 8 / 10 = 74.375 MHz    (+81 ppm)
  --   01 PAL,  625 lines: 100 x 37.125 / 5 / 10 = 74.25 MHz     (exact)
  --   10 NTSC, 526 lines: 100 x 59.25  / 8 / 10 = 74.0625 MHz   (+374 ppm)
  --   11 NTSC, 525 lines: 100 x 44.5   / 6 / 10 = 74.1667 MHz   (-123 ppm)
  -- The registers that differ, read, modified and written with the MMCM
  -- in reset as M2M's video_out_clock does (XAPP888's register map; the
  -- values from Xilinx's mmcm_pll_drp_func_7s_mmcm.vh, BANDWIDTH OPTIMIZED;
  -- CLKOUT0 and CLKOUT1, / 2 and / 10, stay as they are).
  type drp_entry_t is record
    addr : std_logic_vector(6 downto 0);
    keep : std_logic_vector(15 downto 0);   -- the bits not written
  end record;
  type drp_regs_t is array(0 to 9) of drp_entry_t;
  constant DRP_REGS : drp_regs_t := (
    ("0101000", x"0000"),   -- power
    ("0010011", x"8000"),   -- CLKOUT6 register 2: CLKFBOUT's fraction
    ("0010100", x"1000"),   -- CLKFBOUT register 1
    ("0010101", x"8000"),   -- CLKFBOUT register 2
    ("0010110", x"C000"),   -- DIVCLK
    ("0011000", x"FC00"),   -- lock 1
    ("0011001", x"8000"),   -- lock 2
    ("0011010", x"8000"),   -- lock 3
    ("1001110", x"66FF"),   -- filter 1
    ("1001111", x"666F"));  -- filter 2
  type drp_vals_t is array(0 to 3, 0 to 9) of std_logic_vector(15 downto 0);
  constant DRP_VALS : drp_vals_t := (
    (x"FFFF", x"3000", x"075D", x"4880", x"0104", x"00FA", x"7C01", x"7FE9", x"0800", x"1000"),
    (x"FFFF", x"2400", x"0491", x"1880", x"2083", x"00FA", x"7C01", x"7FE9", x"0900", x"1000"),
    (x"FFFF", x"2800", x"075D", x"2880", x"0104", x"00FA", x"7C01", x"7FE9", x"0800", x"1000"),
    (x"FFFF", x"1400", x"0555", x"4C00", x"00C3", x"00FA", x"7C01", x"7FE9", x"0800", x"8000"));
  signal drp_mode_s : std_logic_vector(1 downto 0);
  signal drp_mode_p : std_logic_vector(1 downto 0) := "00";
  signal drp_cur : std_logic_vector(1 downto 0) := "00";
  signal drp_rst : std_logic := '0';
  signal drp_state : integer range 0 to 4 := 0;
  signal drp_n : integer range 0 to 9 := 0;
  signal drp_addr : std_logic_vector(6 downto 0) := (others => '0');
  signal drp_di : std_logic_vector(15 downto 0) := (others => '0');
  signal drp_do : std_logic_vector(15 downto 0);
  signal drp_den : std_logic := '0';
  signal drp_dwe : std_logic := '0';
  signal drp_rdy : std_logic;

  -- the phase shifter
  signal ps_tg_last : std_logic := '0';
  signal ps_send : std_logic := '0';
  signal ps_rcv : std_logic;
  signal ps_src : std_logic_vector(21 downto 0) := (others => '0');
  signal ps_dst : std_logic_vector(21 downto 0);
  signal ps_req : std_logic;
  signal ps_mag : unsigned(23 downto 0) := (others => '0');
  signal ps_dir : std_logic := '0';
  signal ps_acc : unsigned(24 downto 0) := (others => '0');
  signal ps_pend : unsigned(1 downto 0) := "00";
  signal ps_busy : std_logic := '0';
  signal ps_en : std_logic := '0';
  signal ps_incdec : std_logic := '0';
  signal ps_done : std_logic;
  signal hdmi_locked_i : std_logic;
  signal ps_lock_s : std_logic_vector(2 downto 0) := "000";
  
begin

  -- We want 27MHz pixel clock.  From 100MHz, we will get 27.0833333 MHz
  -- But if we do the following, we can get exactly 27MHz:
  -- 4.000/5.000 x 9.000/5.000 x 9.000/13.000
  -- But that goes out of range for the intermediate frequency, so we instead use:
  -- 9.000/13.000 x 9.000/5.000 x 4.000/5.000

  adjust0 : MMCM_ADV
  generic map
   (BANDWIDTH            => "HIGH",
    CLKOUT4_CASCADE      => FALSE,
    CLOCK_HOLD           => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- Create 800 MHz 
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 9.0,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = CLK_OUT1 = 900/12.125 = 74.22MHz = clock74p22mhz
    CLKOUT0_DIVIDE_F     => 12.125,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE,

    -- CLKOUT1 = CLK_OUT1 = 900/13 = 69.23MHz = clock69mhz
    CLKOUT1_DIVIDE     => 13,
    CLKOUT1_PHASE        => 0.000,
    CLKOUT1_DUTY_CYCLE   => 0.500,
    CLKOUT1_USE_FINE_PS  => FALSE

    )

  port map
    -- Output clocks
   (
     CLKFBOUT            => clk_fb_adjust0,
     CLKOUT0             => u_clock74p22mhz,
     CLKOUT1             => u_clock69mhz,
     -- Input clock control
     CLKFBIN             => clk_fb_adjust0,
     CLKIN1              => clk_in,
     CLKIN2              => '0',
     -- Tied to always select the primary input clock
     CLKINSEL            => '1',
     -- Ports for dynamic reconfiguration
     DADDR               => (others => '0'),
     DCLK                => '0',
     DEN                 => '0',
     DI                  => (others => '0'),
     DWE                 => '0',
     -- Ports for dynamic phase shift
     PSCLK               => '0',
     PSEN                => '0',
     PSINCDEC            => '0',
     -- Other control and status signals
     PWRDWN              => '0',
     RST                 => '0');

  adjust1 : MMCM_ADV
  generic map
   (BANDWIDTH            => "HIGH",
    CLKOUT4_CASCADE      => FALSE,
    CLOCK_HOLD           => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- Create 800 MHz 
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 9.0,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = CLK_OUT1 = 69.23MHz x 9/5 = 124.61MHz = clock124mhz
    CLKOUT0_DIVIDE_F     => 5.0,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE
    )

  port map
    -- Output clocks
   (
     CLKFBOUT            => clk_fb_adjust1,
     CLKOUT0             => u_clock124mhz,
     -- Input clock control
     CLKFBIN             => clk_fb_adjust1,
     CLKIN1              => clock69mhz,
     CLKIN2              => '0',
     -- Tied to always select the primary input clock
     CLKINSEL            => '1',
     -- Ports for dynamic reconfiguration
     DADDR               => (others => '0'),
     DCLK                => '0',
     DEN                 => '0',
     DI                  => (others => '0'),
     DWE                 => '0',
     -- Ports for dynamic phase shift
     PSCLK               => '0',
     PSEN                => '0',
     PSINCDEC            => '0',
     -- Other control and status signals
     PWRDWN              => '0',
     RST                 => '0');
    

    adjust2 : MMCM_ADV
  generic map
   (BANDWIDTH            => "HIGH",
    CLKOUT4_CASCADE      => FALSE,
    CLOCK_HOLD           => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- Create 800 MHz 
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 8.0,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = CLK_OUT1 = 124MHz x 8/10 = 99.692307692MHz = clock9969mhz
    CLKOUT0_DIVIDE_F     => 10.0,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE
    )

  port map
    -- Output clocks
   (
     CLKFBOUT            => clk_fb_adjust2,
     CLKOUT0             => u_clock9969mhz,
     -- Input clock control
     CLKFBIN             => clk_fb_adjust2,
     CLKIN1              => clock124mhz,
     CLKIN2              => '0',
     -- Tied to always select the primary input clock
     CLKINSEL            => '1',
     -- Ports for dynamic reconfiguration
     DADDR               => (others => '0'),
     DCLK                => '0',
     DEN                 => '0',
     DI                  => (others => '0'),
     DWE                 => '0',
     -- Ports for dynamic phase shift
     PSCLK               => '0',
     PSEN                => '0',
     PSINCDEC            => '0',
     -- Other control and status signals
     PWRDWN              => '0',
     RST                 => '0');
    

  bufg_inter_connect69:
  bufg port map ( I => u_clock69mhz,
                  O => clock69mhz);

  bufg_inter_connect74p22:
  bufg port map ( I => u_clock74p22mhz,
                  O => clock74p22);  
  
  bufg_inter_connect124:
  bufg port map ( I => u_clock124mhz,
                  O => clock124mhz);  

  bufg_inter_connect:
  bufg port map ( I => u_clock9969mhz,
                  O => clock9969mhz);  
  
  bufg27:
  bufg port map ( I => u_clock27,
                  O => clock27);  

  bufg41:
  bufg port map ( I => u_clock41,
                  O => clock41);  
  
  bufg50:
  bufg port map ( I => u_clock50,
                  O => clock50_i);
  clock50 <= clock50_i;

  bufg81:
  bufg port map ( I => u_clock81p,
                  O => clock81p);  
  
  bufg163:
  bufg port map ( I => u_clock163,
                  O => clock163);  

  bufg163m:
  bufg port map ( I => u_clock163m,
                  O => clock163m);  

  bufg200:
  bufg port map ( I => u_clock200,
                  O => clock200);  

  bufg270:
  bufg port map ( I => u_clock270,
                  O => clock270_i);
  clock270 <= clock270_i;  
  
  bufg325:
  bufg port map ( I => u_clock325,
                  O => clock325);  

  -- 720p's clocks, from the 100 MHz input itself: a VCO near 742.5 MHz (one
  -- of four settings, through the DRP below), / 2 for the serialisers and
  -- / 10 for the pixels. The VIC-IV's frame (50.08 or 59.83 Hz) is not the
  -- standard's, and a strict display (a Dell P1917S) takes 720p only with
  -- the standard's raster, every line 1980 or 1650 clocks and 750 lines: so
  -- the pixel clock follows the VIC-IV instead, the setting near the rate
  -- and the fine phase shift making up the rest.
  mmcm_hdmi : MMCM_ADV
  generic map
   (BANDWIDTH            => "OPTIMIZED",
    CLKOUT4_CASCADE      => FALSE,
    CLOCK_HOLD           => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- 100 x 59.5 / 8 = 743.75 MHz (setting 00; the others by the DRP)
    DIVCLK_DIVIDE        => 8,
    CLKFBOUT_MULT_F      => 59.500,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = 743.75MHz/2 = 371.875MHz
    CLKOUT0_DIVIDE_F     => 2.000,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => TRUE,

    -- CLKOUT1 = 743.75MHz/10 = 74.375MHz
    CLKOUT1_DIVIDE       => 10,
    CLKOUT1_PHASE        => 0.000,
    CLKOUT1_DUTY_CYCLE   => 0.500,
    CLKOUT1_USE_FINE_PS  => TRUE,

    CLKIN1_PERIOD        => 10.000,
    REF_JITTER1          => 0.010)
  port map
   (CLKFBOUT            => clk_fb_hdmi,
    CLKOUT0             => u_clock371,
    CLKOUT1             => u_clock74p25,
    CLKFBIN             => clk_fb_hdmi_b,
    CLKIN1              => clk_in,
    CLKIN2              => '0',
    CLKINSEL            => '1',
    DADDR               => drp_addr,
    DCLK                => clock50_i,
    DEN                 => drp_den,
    DI                  => drp_di,
    DO                  => drp_do,
    DRDY                => drp_rdy,
    DWE                 => drp_dwe,
    PSCLK               => clock270_i,
    PSEN                => ps_en,
    PSINCDEC            => ps_incdec,
    PSDONE              => ps_done,
    LOCKED              => hdmi_locked_i,
    PWRDWN              => '0',
    RST                 => drp_rst);

  hdmi_locked <= hdmi_locked_i;

  -- The setting for the VIC-IV's frame: see DRP_VALS above.
  mode_cdc: xpm_cdc_array_single
    generic map (DEST_SYNC_FF => 3, SRC_INPUT_REG => 0, WIDTH => 2)
    port map (src_clk => '0', src_in => hdmi_mode, dest_clk => clock50_i, dest_out => drp_mode_s);

  -- (a mode seen the same in two clocks running: the two bits may cross a
  -- clock apart)
  process (clock50_i)
    variable e : drp_entry_t;
  begin
    if rising_edge(clock50_i) then
      drp_den <= '0';
      drp_dwe <= '0';
      drp_mode_p <= drp_mode_s;
      e := DRP_REGS(drp_n);
      case drp_state is
        when 0 =>
          if drp_mode_s = drp_mode_p and drp_mode_s /= drp_cur then
            drp_cur <= drp_mode_s;
            drp_rst <= '1';
            drp_n <= 0;
            drp_state <= 1;
          end if;
        when 1 =>
          drp_addr <= e.addr;
          drp_den <= '1';
          drp_state <= 2;
        when 2 =>
          if drp_rdy = '1' then
            drp_di <= (drp_do and e.keep) or (DRP_VALS(to_integer(unsigned(drp_cur)), drp_n) and not e.keep);
            drp_den <= '1';
            drp_dwe <= '1';
            drp_state <= 3;
          end if;
        when 3 =>
          if drp_rdy = '1' then
            if drp_n /= 9 then
              drp_n <= drp_n + 1;
              drp_state <= 1;
            else
              drp_state <= 4;
            end if;
          end if;
        when others =>
          -- (the mode may have changed again meanwhile: state 0 sees it)
          drp_rst <= '0';
          drp_state <= 0;
      end case;
    end if;
  end process;

  -- The trim. The rate crosses into 270 MHz once a frame;
  -- there a 24-bit accumulator makes |rate| steps every 2^24 clocks, each a
  -- PSEN pulse in the direction of the rate's sign, one at a time (PSDONE
  -- comes 12 clocks later), at most three waiting.
  ps_cdc: xpm_cdc_handshake
    generic map (DEST_EXT_HSK => 0, DEST_SYNC_FF => 3, SRC_SYNC_FF => 3, WIDTH => 22)
    port map (src_clk => clock74p25_i, src_in => ps_src, src_send => ps_send, src_rcv => ps_rcv,
              dest_clk => clock270_i, dest_req => ps_req, dest_out => ps_dst, dest_ack => '0');

  process (clock74p25_i)
  begin
    if rising_edge(clock74p25_i) then
      if ps_send = '0' and ps_rcv = '0' and hdmi_ps_tg /= ps_tg_last then
        ps_tg_last <= hdmi_ps_tg;
        ps_src <= std_logic_vector(hdmi_ps_rate);
        ps_send <= '1';
      elsif ps_send = '1' and ps_rcv = '1' then
        ps_send <= '0';
      end if;
    end if;
  end process;

  process (clock270_i)
    variable r : signed(21 downto 0);
    variable pend : unsigned(1 downto 0);
  begin
    if rising_edge(clock270_i) then
      ps_lock_s <= ps_lock_s(1 downto 0) & hdmi_locked_i;
      if ps_req = '1' then
        r := signed(ps_dst);
        if r < 0 then
          ps_dir <= '0';
          ps_mag <= resize(unsigned(-r),24);
        else
          ps_dir <= '1';
          ps_mag <= resize(unsigned(r),24);
        end if;
      end if;
      ps_acc <= ('0' & ps_acc(23 downto 0)) + ('0' & ps_mag);
      ps_en <= '0';
      if ps_lock_s(2) = '0' then
        ps_pend <= "00";
        ps_busy <= '0';
      else
        pend := ps_pend;
        if ps_busy = '0' and pend /= "00" and ps_en = '0' then
          ps_en <= '1';
          ps_incdec <= ps_dir;
          ps_busy <= '1';
          pend := pend - 1;
        elsif ps_done = '1' then
          ps_busy <= '0';
        end if;
        if ps_acc(24) = '1' and pend /= "11" then
          pend := pend + 1;
        end if;
        ps_pend <= pend;
      end if;
    end if;
  end process;

  bufg74p25:
  bufg port map ( I => u_clock74p25,
                  O => clock74p25_i);
  clock74p25 <= clock74p25_i;

  -- (mmcm_hdmi's feedback through a BUFG: without it a display as strict as
  -- a Dell P1917S showed no 720p at all)
  bufg_fb_hdmi:
  bufg port map ( I => clk_fb_hdmi,
                  O => clk_fb_hdmi_b);

  -- (BUFGMUX_CTRL: its select may change at any time, and it goes from one
  -- clock to the other between their pulses)
  bufgmux_hdmi:
  bufgmux_ctrl port map ( I0 => u_clock27,
                          I1 => u_clock74p25,
                          S => hdmi_720p,
                          O => clock_hdmi);

  bufgmux_hdmi_x5:
  bufgmux_ctrl port map ( I0 => u_clock135,
                          I1 => u_clock371,
                          S => hdmi_720p,
                          O => clock_hdmi_x5);
  
  mmcm_adv0 : MMCM_ADV
  generic map
   (BANDWIDTH            => "HIGH",
    CLKOUT4_CASCADE      => FALSE,
    CLOCK_HOLD           => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- Create 812.5MHz clock from 8.125x100MHz/1
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 8.125,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = clock325 = 812.5MHz/2.5
    CLKOUT0_DIVIDE_F     => 2.50,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE,

    -- CLKOUT1 = clock135 = 812.5MHz/6
    CLKOUT1_DIVIDE       => 6,
    CLKOUT1_PHASE        => 0.000,
    CLKOUT1_DUTY_CYCLE   => 0.500,
    CLKOUT1_USE_FINE_PS  => FALSE,

    -- CLKOUT2 = clock81 = 812.5MHz/10
    CLKOUT2_DIVIDE       => 10,
    CLKOUT2_PHASE        => 0.000,
    CLKOUT2_DUTY_CYCLE   => 0.500,
    CLKOUT2_USE_FINE_PS  => FALSE,

    -- CLKOUT3 = clock41 = 812.5MHz/20
    CLKOUT3_DIVIDE       => 20,
    CLKOUT3_PHASE        => 0.000,
    CLKOUT3_DUTY_CYCLE   => 0.500,
    CLKOUT3_USE_FINE_PS  => FALSE,

    -- CLKOUT4 = clock27 = 812.5MHz/30 = 27.083
    CLKOUT4_DIVIDE       => 30,
    CLKOUT4_PHASE        => 0.000,
    CLKOUT4_DUTY_CYCLE   => 0.500,
    CLKOUT4_USE_FINE_PS  => FALSE,
    
    -- CLKOUT5 = clock163 = 812.5MHz/5 = 162.5 MHz
    CLKOUT5_DIVIDE       => 5,
    CLKOUT5_PHASE        => 0.0,
    CLKOUT5_DUTY_CYCLE   => 0.500,
    CLKOUT5_USE_FINE_PS  => FALSE,

    -- CLKOUT6 = clock270 = 270MHz
    CLKOUT6_DIVIDE       => 3,
    CLKOUT6_PHASE        => 0.000,
    CLKOUT6_DUTY_CYCLE   => 0.500,
    CLKOUT6_USE_FINE_PS  => FALSE,
    
    CLKIN1_PERIOD        => 10.000,
    REF_JITTER1          => 0.010)
  port map
    -- Output clocks
   (CLKFBOUT            => clk_fb,
    CLKOUT0             => u_clock325,
    CLKOUT1             => u_clock135,
    CLKOUT2             => u_clock81p,
    CLKOUT3             => u_clock41,
    CLKOUT4             => u_clock27,
    CLKOUT5             => u_clock163,
    CLKOUT6             => u_clock270,
    -- Input clock control
    CLKFBIN             => clk_fb,
    CLKIN1              => clock9969mhz,
    CLKIN2              => '0',
    -- Tied to always select the primary input clock
    CLKINSEL            => '1',
    -- Ports for dynamic reconfiguration
    DADDR               => (others => '0'),
    DCLK                => '0',
    DEN                 => '0',
    DI                  => (others => '0'),
    DWE                 => '0',
    -- Ports for dynamic phase shift
    PSCLK               => '0',
    PSEN                => '0',
    PSINCDEC            => '0',
    -- Other control and status signals
    PWRDWN              => '0',
    RST                 => '0');
  
  mmcm_adv0sdram : MMCM_ADV
  generic map
   (BANDWIDTH            => "HIGH",
    CLKOUT4_CASCADE      => FALSE,
    CLOCK_HOLD           => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- Create 812.5MHz clock from 8.125x100MHz/1
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 8.125,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = clock325 = 812.5MHz/2.5
    CLKOUT0_DIVIDE_F     => 2.50,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE,

    -- CLKOUT1 = clock135 = 812.5MHz/6
    CLKOUT1_DIVIDE       => 6,
    CLKOUT1_PHASE        => 0.000,
    CLKOUT1_DUTY_CYCLE   => 0.500,
    CLKOUT1_USE_FINE_PS  => FALSE,

    -- CLKOUT2 = clock81 = 812.5MHz/10
    CLKOUT2_DIVIDE       => 10,
    CLKOUT2_PHASE        => 0.000,
    CLKOUT2_DUTY_CYCLE   => 0.500,
    CLKOUT2_USE_FINE_PS  => FALSE,

    -- CLKOUT3 = clock41 = 812.5MHz/20
    CLKOUT3_DIVIDE       => 20,
    CLKOUT3_PHASE        => 0.000,
    CLKOUT3_DUTY_CYCLE   => 0.500,
    CLKOUT3_USE_FINE_PS  => FALSE,

    -- CLKOUT4 = clock27 = 812.5MHz/30 = 27.083
    CLKOUT4_DIVIDE       => 30,
    CLKOUT4_PHASE        => 0.000,
    CLKOUT4_DUTY_CYCLE   => 0.500,
    CLKOUT4_USE_FINE_PS  => FALSE,
    
    -- CLKOUT5 = clock163 = 812.5MHz/5 = 162.5 MHz
    -- Phase adjusted by 180 degrees
    CLKOUT5_DIVIDE       => 5,
    CLKOUT5_PHASE        => 180.0,
    CLKOUT5_DUTY_CYCLE   => 0.500,
    CLKOUT5_USE_FINE_PS  => FALSE,

    -- CLKOUT6 = clock270 = 270MHz
    CLKOUT6_DIVIDE       => 3,
    CLKOUT6_PHASE        => 0.000,
    CLKOUT6_DUTY_CYCLE   => 0.500,
    CLKOUT6_USE_FINE_PS  => FALSE,
    
    CLKIN1_PERIOD        => 10.000,
    REF_JITTER1          => 0.010)
  port map
    -- Output clocks
   (CLKFBOUT            => clk_fb_sdram,
    CLKOUT5             => u_clock163m,
    -- Input clock control
    CLKFBIN             => clk_fb_sdram,
    CLKIN1              => clock9969mhz,
    CLKIN2              => '0',
    -- Tied to always select the primary input clock
    CLKINSEL            => '1',
    -- Ports for dynamic reconfiguration
    DADDR               => (others => '0'),
    DCLK                => '0',
    DEN                 => '0',
    DI                  => (others => '0'),
    DWE                 => '0',
    -- Ports for dynamic phase shift
    PSCLK               => '0',
    PSEN                => '0',
    PSINCDEC            => '0',
    -- Other control and status signals
    PWRDWN              => '0',
    RST                 => '0');
  


  mmcm_adv1_eth : MMCM_ADV
  generic map
   (BANDWIDTH            => "HIGH",
    CLKOUT4_CASCADE      => FALSE,
    CLOCK_HOLD           => FALSE,
    COMPENSATION         => "ZHOLD",
    STARTUP_WAIT         => FALSE,

    -- Create 800.0MHz clock from 8.000x100MHz/1
    DIVCLK_DIVIDE        => 1,
    CLKFBOUT_MULT_F      => 8.000,
    CLKFBOUT_PHASE       => 0.000,
    CLKFBOUT_USE_FINE_PS => FALSE,

    -- CLKOUT0 = CLK_OUT1 = clock100 = 800MHz/8.0
    CLKOUT0_DIVIDE_F     => 8.0,
    CLKOUT0_PHASE        => 0.000,
    CLKOUT0_DUTY_CYCLE   => 0.500,
    CLKOUT0_USE_FINE_PS  => FALSE,

    -- CLKOUT1 = CLK_OUT2 = clock50 = 800MHz/16
    CLKOUT1_DIVIDE       => 16,
    CLKOUT1_PHASE        => 0.000,
    CLKOUT1_DUTY_CYCLE   => 0.500,
    CLKOUT1_USE_FINE_PS  => FALSE,

    -- CLKOUT2 = CLK_OUT3 = clock200 = 800MHz/4
    CLKOUT2_DIVIDE       => 4,
    CLKOUT2_PHASE        => 0.000,
    CLKOUT2_DUTY_CYCLE   => 0.500,
    CLKOUT2_USE_FINE_PS  => FALSE,
    
    -- CLKOUT3 = CLK_OUT4 = clock50q = 800MHz/16 = 50MHz, and rotated 45 degrees
    CLKOUT3_DIVIDE       => 16,
    CLKOUT3_PHASE        => 45.000,
    CLKOUT3_DUTY_CYCLE   => 0.500,
    CLKOUT3_USE_FINE_PS  => FALSE,

    -- CLKOUT4 = UNUSED
    CLKOUT4_DIVIDE       => 10,
    CLKOUT4_PHASE        => 0.000,
    CLKOUT4_DUTY_CYCLE   => 0.500,
    CLKOUT4_USE_FINE_PS  => FALSE,

    -- CLKOUT5 = UNUSED
    CLKOUT5_DIVIDE       => 5,
    CLKOUT5_PHASE        => 0.0,
    CLKOUT5_DUTY_CYCLE   => 0.500,
    CLKOUT5_USE_FINE_PS  => FALSE,

    -- CLKOUT6 = UNUSED
    CLKOUT6_DIVIDE       => 5,
    CLKOUT6_PHASE        => 0.000,
    CLKOUT6_DUTY_CYCLE   => 0.500,
    CLKOUT6_USE_FINE_PS  => FALSE,
    CLKIN1_PERIOD        => 10.000,
    REF_JITTER1          => 0.010)
  port map
    -- Output clocks
    (
    CLKFBOUT            => clk_fb_eth,
    CLKOUT1             => u_clock50,
    CLKOUT2             => u_clock200,
--    CLKOUT3             => u_clock50q,
    -- Input clock control
    CLKFBIN             => clk_fb_eth,
    CLKIN1              => clk_in,
    CLKIN2              => '0',
    -- Tied to always select the primary input clock
    CLKINSEL            => '1',
    -- Ports for dynamic reconfiguration
    DADDR               => (others => '0'),
    DCLK                => '0',
    DEN                 => '0',
    DI                  => (others => '0'),
    DWE                 => '0',
    -- Ports for dynamic phase shift
    PSCLK               => '0',
    PSEN                => '0',
    PSINCDEC            => '0',
    -- Other control and status signals
    PWRDWN              => '0',
    RST                 => '0');

  

  
end rtl;
