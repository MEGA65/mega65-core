library ieee;
use ieee.std_logic_1164.all;
use IEEE.numeric_std.ALL;

library xpm;
use xpm.vcomponents.ALL;

entity upscaler is
  port (
    -- Input and output pixel clocks. The output clock is 720p's, 74.25 MHz
    -- or near it: its frequency is not assumed, the output is locked to the
    -- input by measurement.
    clock27 : in std_logic;
    clock74p22 : in std_logic;

    -- Change behaviour
    hold_image : in std_logic;

    -- (The lock is measured now: these eight and vlock_en do nothing, and
    -- are here for the designs that connect them.)
    ntsc_inc_coarse : in std_logic := '0';
    ntsc_dec_coarse : in std_logic := '0';
    ntsc_inc_fine : in std_logic := '0';
    ntsc_dec_fine : in std_logic := '0';

    pal_inc_coarse : in std_logic := '0';
    pal_dec_coarse : in std_logic := '0';
    pal_inc_fine : in std_logic := '0';
    pal_dec_fine : in std_logic := '0';


    -- PAL or NTSC mode
    pal50_select : in std_logic;

    -- Upscale enable/disable: the outputs below are the 720p picture, or the
    -- input as it is
    upscale_en : in std_logic;
    -- XXX DEBUG: Allow disabling VBLANK locking of output to input
    vlock_en : in std_logic := '1';

    pixelvalid_in : std_logic;
    red_in : in unsigned(7 downto 0);
    green_in : in unsigned(7 downto 0);
    blue_in : in unsigned(7 downto 0);
    hsync_in : in std_logic;
    vsync_in : in std_logic;

    pixelvalid_out : out std_logic;
    red_out : out unsigned(7 downto 0);
    green_out : out unsigned(7 downto 0);
    blue_out : out unsigned(7 downto 0);
    hsync_out : out std_logic;
    vsync_out : out std_logic;

    -- Frames of whole lines only (clock27's domain): what a frame differs by
    -- from a whole number of lines is not put into the lines before vsync,
    -- but saved up until it is a line, and a frame then has one line more
    -- (NTSC: 752 lines, 753 every fifth or sixth frame). For a display that
    -- has been told the frame rate varies, as an Adaptive-Sync one can be
    -- (vga_to_hdmi's vrr): an ASUS PA348CGV takes 720p at the MEGA65's NTSC
    -- rate of 59.83 Hz so and in no other way.
    whole_lines : in std_logic := '0';

    -- The picture narrower (clock27's domain), for a display of 21:9 that
    -- stretches a 16:9 picture over all its width: see NARROW_WIDTH below.
    narrow : in std_logic := '0';

    -- The 720p picture by itself, for something that wants it whether or not
    -- the outputs above are it (HDMI at 720p beside VGA as it is): hd_en asks
    -- for it, and hd_active is '1' while it is there, from the start of a
    -- frame on. All in clock74p22's domain, but hd_en, which is clock27's.
    hd_en : in std_logic := '0';
    hd_active : out std_logic;
    hd_pixelvalid : out std_logic;
    hd_red : out unsigned(7 downto 0);
    hd_green : out unsigned(7 downto 0);
    hd_blue : out unsigned(7 downto 0);
    hd_hsync : out std_logic;
    hd_vsync : out std_logic

    );
end entity;

architecture hundertwasser of upscaler is

  -- 720p as it goes out (CTA-861 formats 19 and 4). x_count is 0 at a line's
  -- first pixel and y_count 0 on the first line of pixels.
  --   50 Hz: 1280 1720 1760 1980, 720 725 730 750, both syncs positive
  --   60 Hz: 1280 1390 1430 1650, 720 725 730 750
  -- A frame out has to last as long as a frame in, and the MEGA65's frames
  -- are not 20 ms and 16.68 ms long: 624 lines and not 625 in PAL (without
  -- interlace), 526 and not 525 in NTSC. As in the MEGA65's own 576p and
  -- 480p, the line is the standard's all the same, 1980 or 1650 clocks, to
  -- the clock (37.5 and 45 kHz at 74.25 MHz), and it is the number of lines
  -- that gives: 749 in PAL and 752 in NTSC for the standard's 750, the
  -- difference in the front porch (vsync and the back porch are the
  -- standard's 5 and 20 lines). What a frame then still differs by, 396
  -- clocks fewer in PAL and 297 more in NTSC, is in the four lines before
  -- vsync, a quarter in each. So every line from vsync to the last one with
  -- pixels is the same: a display that checks the line frequency finds the
  -- standard's, and something that takes a line's length once and counts
  -- from there (an HDMI capture device does) finds every pixel where it
  -- expects it. With interlace on, the PAL frame is 625 lines and the output
  -- 1980 x 750 exactly.
  -- (Tried on an ASUS PA348CGV, November 2026: it shows PAL so. NTSC it
  -- shows for a second and then goes black, in this and every other
  -- arrangement of lines and syncs tried, VESA's CVT among them: the frame
  -- rate is 59.83 Hz, and it wants 60.00, which it shows. It does take 59.83
  -- Hz as frames of whole lines, their number varying, when told the rate
  -- varies: see whole_lines.)
  constant OUT_WIDTH : integer := 1280;
  constant OUT_HEIGHT : integer := 720;
  constant LINE_PAL : integer := 1980;
  constant HSYNC_ON_PAL : integer := 1720;
  constant HSYNC_OFF_PAL : integer := 1760;
  constant LINE_NTSC : integer := 1650;
  constant HSYNC_ON_NTSC : integer := 1390;
  constant HSYNC_OFF_NTSC : integer := 1430;
  -- From the end of a frame of `rows` lines. Vsync changes with hsync's
  -- leading edge, as the standard has it (the line that begins there is the
  -- one whose pixels are y_count + 1): on in line rows - 26, off in line
  -- rows - 21, which for 750 are 724 and 729. The four lines before that
  -- take up the frame's odd clocks.
  constant VSYNC_ON_BEFORE : integer := 26;
  constant VSYNC_OFF_BEFORE : integer := 21;
  constant FILL_FIRST_BEFORE : integer := 30;
  constant FILL_LAST_BEFORE : integer := 27;
  -- A line with fewer clocks still has to hold its hsync (220 clocks from
  -- its end to the line's): at most this many fewer in one
  constant FILL_MOST_FEWER : integer := 216;
  -- Frames of fewer lines than this have no front porch; more than that
  -- many is no 720p. (With 749 lines the first of the four before vsync is
  -- the last line of pixels, whose end it is that moves, after its pixels;
  -- with fewer there are fewer than four: none of them is a line that
  -- another line of pixels follows.)
  constant ROWS_MIN : integer := 746;
  constant ROWS_MAX : integer := 800;

  -- Until the input's frame has been measured: 624 x 864 and 526 x 858
  -- pixels of 27 MHz, in clocks of 74.25 MHz (x 11/4)
  constant ROWS_PAL : integer := 749;
  constant REM_PAL : integer := -396;
  constant ROWS_NTSC : integer := 752;
  constant REM_NTSC : integer := 297;

  -- The picture is as wide as a 4:3 screen would show it at the height it
  -- has here (576 lines of 624 over 749, 480 of 526 over 752): 720 pixels over 924 in
  -- PAL and 912 in NTSC, between black shoulders. H_STEP is 720 over that
  -- width, in 65536ths: what one pixel out is of the pixels in.
  constant SRC_LAST : integer := 719;
  constant PIC_WIDTH_PAL : integer := 924;
  constant PIC_LEFT_PAL : integer := (OUT_WIDTH - PIC_WIDTH_PAL) / 2;
  constant H_STEP_PAL : integer := 51067;
  constant PIC_WIDTH_NTSC : integer := 912;
  constant PIC_LEFT_NTSC : integer := (OUT_WIDTH - PIC_WIDTH_NTSC) / 2;
  constant H_STEP_NTSC : integer := 51739;
  -- For a display of 21:9 that stretches 16:9 over all its width, as some do
  -- whenever the rate varies (an ASUS PA348CGV with Adaptive-Sync on has no
  -- other way, and takes NTSC only so: see whole_lines): the picture
  -- narrower by what the display will widen it, 32/43 for 3440 x 1440, which
  -- is 688 pixels in PAL and 680 in NTSC. That is fewer pixels than the 720
  -- that come in, and the reading side reads one cell of the buffers a clock
  -- and cannot skip one. So the writing side does it: it writes 688 or 680
  -- cells a line, each the mix of the two pixels in that it lies between,
  -- and the reading side shows a cell a pixel. NARROW_STEP is what a cell is
  -- of the pixels in, less the one, in 65536ths (720/688 and 720/680).
  constant NARROW_WIDTH_PAL : integer := 688;
  constant NARROW_LEFT_PAL : integer := (OUT_WIDTH - NARROW_WIDTH_PAL) / 2;
  constant NARROW_STEP_PAL : integer := 3048;
  constant NARROW_WIDTH_NTSC : integer := 680;
  constant NARROW_LEFT_NTSC : integer := (OUT_WIDTH - NARROW_WIDTH_NTSC) / 2;
  constant NARROW_STEP_NTSC : integer := 3855;
  -- Clocks from the address of a pixel's raster buffer cell to the pixel at
  -- the output: address, RAM, the two lines chosen, their mix, the mix along
  -- the line
  constant H_PIPELINE : integer := 5;

  -- THE LOCK. The writing side counts the input's lines from the start of
  -- its vsync, and each frame finds the line it calls geo_start: the one
  -- that is to be the output's line 0, so chosen that the input's lines with
  -- pixels come out in the middle of the 720. From that line on the four
  -- raster buffers are written in turn, beginning with buffer 0, and as the
  -- line three after it begins, lock_toggle changes. The reading side is to
  -- be LOCK_X clocks into its line 0 at that moment (two thirds of a line
  -- of the input): then it reads a line and the one after it 2.3 lines
  -- behind the writing (a sixth of a line more or less by the bottom of the
  -- picture, the frame being a whole number of the output's lines only
  -- nearly). That is the middle of what works, which in simulation is from
  -- 1.5 lines behind (nearer, and it reads cells of the second line before
  -- they are written) to 3 (further, and the first line is being written
  -- again): more than half a line to spare either way, 1,300 clocks, where
  -- the lock holds to 2. (LOCK_X has to be less than the shorter line.)
  constant LOCK_X : integer := 1580;
  -- Out by more than this many clocks at a lock_toggle, the output starts
  -- again from LOCK_X. Out by less, the frame that has just begun is made
  -- that much longer or shorter, a clock here and there over its lines; by
  -- this little, nothing is done.
  constant LOCK_RESTART : integer := 4095;
  constant LOCK_DEAD : integer := 2;

  ---------------------------------------------------------------------------
  -- writing side (clock27)

  signal vsync_in_prev : std_logic := '0';
  signal hsync_in_prev : std_logic := '0';
  signal pixelvalid_in_prev : std_logic := '0';

  signal in_line : unsigned(10 downto 0) := to_unsigned(0,11);   -- lines since vsync began
  signal in_first : unsigned(10 downto 0) := to_unsigned(0,11);  -- the first with pixels
  signal in_active : unsigned(10 downto 0) := to_unsigned(0,11); -- how many have pixels

  -- The frame before, kept for the frame that is running
  signal geo_lines : unsigned(10 downto 0) := to_unsigned(624,11);
  signal geo_active : unsigned(10 downto 0) := to_unsigned(576,11);
  signal geo_start : unsigned(10 downto 0) := to_unsigned(32,11);
  signal geo_skip : unsigned(10 downto 0) := to_unsigned(11,11);  -- lines from geo_start to the first with pixels

  signal write_raster : unsigned(1 downto 0) := "00";   -- the buffer of the line being counted
  signal write_buf : unsigned(1 downto 0) := "00";      -- the buffer of the line being written
  signal write_en : std_logic_vector(3 downto 0) := "0000";
  signal write_addr : unsigned(9 downto 0) := to_unsigned(0,10);
  signal write_data : std_logic_vector(31 downto 0) := (others => '0');
  -- narrow: the pixel before this one, and where the next cell to write is,
  -- counted from that pixel (65536 and more: not before this one)
  signal in_prev : unsigned(23 downto 0) := (others => '0');
  signal narrow_acc : unsigned(16 downto 0) := to_unsigned(0,17);
  signal lock_toggle : std_logic := '0';

  ---------------------------------------------------------------------------
  -- reading side (clock74p22)

  signal upscale_en_74 : std_logic;
  signal hd_en_74 : std_logic;
  signal whole_lines_74 : std_logic;
  signal narrow_74 : std_logic;
  signal pal50_select_74 : std_logic;
  signal lock_toggle_74 : std_logic;
  signal lock_toggle_last : std_logic := '0';
  signal geo_in : std_logic_vector(32 downto 0);
  signal geo_74 : std_logic_vector(32 downto 0);

  signal upscale_en_int : std_logic := '0';     -- the outputs are the 720p picture
  signal running : std_logic := '0';            -- the 720p picture is wanted, by them or by hd_en
  signal pal50_int : std_logic := '1';

  -- the picture's place in the input's frame, as of the last lock_toggle
  signal v_lines : integer range 0 to 2047 := 624;
  signal v_skip : integer range 0 to 2047 := 11;
  signal v_active : integer range 0 to 2047 := 576;

  signal x_count : integer range 0 to 4095 := 0;
  signal y_count : integer range 0 to 1023 := 0;
  -- The frame: `rows` lines of the standard's clocks, and line_rem clocks
  -- more (or, negative, fewer) in the four lines before vsync. frame_len is
  -- the sum. They change a few clocks after a lock_toggle, which comes early
  -- in line 0: so the frame that has just begun is the one that makes up for
  -- what the lock found.
  signal rows : integer range 0 to 2047 := ROWS_PAL;
  -- The lines the picture is laid out over: `rows`, but where that goes up
  -- by one now and then (frames of whole lines only), the lesser of the two,
  -- or the picture would be a line taller at the bottom in the longer ones
  signal rows_v : integer range 0 to 2047 := ROWS_PAL;
  signal line_rem : integer range -1024 to 2047 := REM_PAL;
  signal frame_len : unsigned(21 downto 0) := to_unsigned(ROWS_PAL * LINE_PAL + REM_PAL,22);
  signal extra : integer range -1024 to 2047 := 0;  -- clocks more in the line running

  signal pos_count : unsigned(21 downto 0) := to_unsigned(0,22);      -- clocks since x_count and y_count were 0
  signal period_count : unsigned(21 downto 0) := to_unsigned(0,22);   -- clocks since the last lock_toggle
  signal period_prev : unsigned(21 downto 0) := to_unsigned(0,22);    -- between the two before it
  -- The input's frame in clocks: what two measurements in a row agreed on
  signal frame_base : unsigned(21 downto 0) := to_unsigned(ROWS_PAL * LINE_PAL + REM_PAL,22);

  -- a lock_toggle being dealt with: where the output was, how long since
  -- the one before, how far out that is
  signal lock_step : unsigned(1 downto 0) := "00";
  signal lock_pos : unsigned(21 downto 0) := to_unsigned(0,22);
  signal lock_period : unsigned(21 downto 0) := to_unsigned(0,22);
  signal lock_was_on : std_logic := '0';
  signal lock_err : integer range -4194304 to 4194303 := 0;

  -- frame length over the line's, a bit a clock
  signal div_busy : std_logic := '0';
  signal div_apply : std_logic := '0';     -- its result is still to be taken
  signal div_frame : unsigned(21 downto 0) := to_unsigned(0,22);
  signal div_rem : unsigned(22 downto 0) := to_unsigned(0,23);
  signal div_by : unsigned(22 downto 0) := to_unsigned(0,23);
  signal div_q : unsigned(11 downto 0) := to_unsigned(0,12);
  signal div_bit : integer range 0 to 11 := 0;

  -- down the frame: the input's line (from geo_start) that the output's line
  -- begins in, and how far into it, in `rows`ths
  signal src_line : integer range 0 to 2047 := 0;
  signal v_acc : integer range 0 to 1499 := 0;
  signal target_raster : unsigned(1 downto 0) := "00";
  signal raster_buf_active : std_logic_vector(3 downto 0) := "0000";
  signal coeff1 : integer range 0 to 255 := 0;     -- of the line after, in 256ths
  signal v_show : std_logic := '0';

  -- along the line
  signal h_run : std_logic := '0';
  signal h_left : integer range 0 to 2047 := 0;
  signal h_pos : unsigned(9 downto 0) := to_unsigned(0,10);    -- the input's pixel
  signal h_frac : unsigned(15 downto 0) := to_unsigned(0,16);  -- and how far past it
  signal h_new : std_logic := '0';                             -- it is not the last one's
  signal read_addr : unsigned(9 downto 0) := to_unsigned(0,10);
  type frac_array_t is array(0 to 3) of unsigned(5 downto 0);
  signal p_valid : std_logic_vector(0 to 3) := "0000";
  signal p_new : std_logic_vector(0 to 3) := "0000";
  signal p_frac : frac_array_t := (others => to_unsigned(0,6));

  type u32_array_t is array(0 to 3) of unsigned(31 downto 0);
  signal rdata : u32_array_t;
  signal rdata_a : unsigned(23 downto 0) := to_unsigned(0,24);   -- the line
  signal rdata_b : unsigned(23 downto 0) := to_unsigned(0,24);   -- the line after
  signal vmix : unsigned(23 downto 0) := to_unsigned(0,24);      -- the two mixed
  signal vmix_prev : unsigned(23 downto 0) := to_unsigned(0,24); -- the pixel before
  signal h_a : unsigned(23 downto 0) := to_unsigned(0,24);       -- the left one of the two being mixed

  signal red_up : unsigned(7 downto 0) := x"00";
  signal green_up : unsigned(7 downto 0) := x"00";
  signal blue_up : unsigned(7 downto 0) := x"00";
  signal hsync_up : std_logic := '0';
  signal vsync_up : std_logic := '0';
  signal pixelvalid_up : std_logic := '0';

  -- a x (256 - c) + b x c, in 256ths, rounded
  function mix256(a : unsigned(7 downto 0); b : unsigned(7 downto 0); c : integer range 0 to 255)
    return unsigned is
    variable s : integer range 0 to 65535;
  begin
    s := to_integer(a) * (256 - c) + to_integer(b) * c + 128;
    return to_unsigned(s / 256, 8);
  end function;

  -- a x (64 - c) + b x c, in 64ths, rounded
  function mix64(a : unsigned(7 downto 0); b : unsigned(7 downto 0); c : unsigned(5 downto 0))
    return unsigned is
    variable s : integer range 0 to 16383;
  begin
    s := to_integer(a) * (64 - to_integer(c)) + to_integer(b) * to_integer(c) + 32;
    return to_unsigned(s / 64, 8);
  end function;

begin

  cdc_pal : xpm_cdc_single
    port map (
      src_in => pal50_select,
      src_clk => clock27,
      dest_clk => clock74p22,
      dest_out => pal50_select_74
      );

  cdc_en : xpm_cdc_single
    port map (
      src_in => upscale_en,
      src_clk => clock27,
      dest_clk => clock74p22,
      dest_out => upscale_en_74
      );

  cdc_hd : xpm_cdc_single
    port map (
      src_in => hd_en,
      src_clk => clock27,
      dest_clk => clock74p22,
      dest_out => hd_en_74
      );

  cdc_whole : xpm_cdc_single
    port map (
      src_in => whole_lines,
      src_clk => clock27,
      dest_clk => clock74p22,
      dest_out => whole_lines_74
      );

  cdc_narrow : xpm_cdc_single
    port map (
      src_in => narrow,
      src_clk => clock27,
      dest_clk => clock74p22,
      dest_out => narrow_74
      );

  cdc_lock : xpm_cdc_single
    port map (
      src_in => lock_toggle,
      src_clk => clock27,
      dest_clk => clock74p22,
      dest_out => lock_toggle_74
      );

  -- These change at the start of the input's vsync and are taken at a
  -- lock_toggle, some thirty lines later
  geo_in <= std_logic_vector(geo_lines) & std_logic_vector(geo_skip) & std_logic_vector(geo_active);
  cdc_geo : xpm_cdc_array_single
    generic map (
      DEST_SYNC_FF => 2,
      SRC_INPUT_REG => 0,
      WIDTH => 33
      )
    port map (
      src_in => geo_in,
      src_clk => clock27,
      dest_clk => clock74p22,
      dest_out => geo_74
      );

  rasterbufs: for i in 0 to 3 generate
    rastbuf0: entity work.upscaler_ram32x1024 port map (
      clka => clock27,
      ena => write_en(i),
      wea => write_en(i),
      addra => std_logic_vector(write_addr),
      dina => write_data,

      clkb => clock74p22,
      enb => raster_buf_active(i),
      addrb => std_logic_vector(read_addr),
      unsigned(doutb) => rdata(i)
      );
  end generate;

  process (clock27) is
    variable start : integer range -2048 to 4095;
    variable px : unsigned(23 downto 0);
    variable nf : unsigned(5 downto 0);
  begin
    if rising_edge(clock27) then

      vsync_in_prev <= vsync_in;
      hsync_in_prev <= hsync_in;
      pixelvalid_in_prev <= pixelvalid_in;

      -- A line's pixels into the buffer that was the line's when its first
      -- pixel came, whatever hsync does meanwhile: cell 0 the first pixel
      -- (narrow: a cell is written when the pixel to its right is here, as
      -- the mix of the pixel before and that one; cell 0, the first pixel
      -- itself, with the second. A cell is more than a pixel from the one
      -- before, so there is never more than one to write, and now and then
      -- none.)
      write_en <= (others => '0');
      px := blue_in & green_in & red_in;
      in_prev <= px;
      if narrow = '0' then
        write_data(23 downto 0) <= std_logic_vector(px);
      else
        nf := narrow_acc(15 downto 10);
        write_data(7 downto 0) <= std_logic_vector(mix64(in_prev(7 downto 0), px(7 downto 0), nf));
        write_data(15 downto 8) <= std_logic_vector(mix64(in_prev(15 downto 8), px(15 downto 8), nf));
        write_data(23 downto 16) <= std_logic_vector(mix64(in_prev(23 downto 16), px(23 downto 16), nf));
      end if;
      if pixelvalid_in = '1' then
        if pixelvalid_in_prev = '0' then
          write_buf <= write_raster;
          if narrow = '0' then
            write_addr <= to_unsigned(0,10);
            write_en(to_integer(write_raster)) <= not hold_image;
          else
            write_addr <= to_unsigned(1023,10);
            narrow_acc <= to_unsigned(0,17);
          end if;
          if in_active = 0 then
            in_first <= in_line;
          end if;
          in_active <= in_active + 1;
        elsif narrow = '0' then
          if write_addr /= 1023 then
            write_addr <= write_addr + 1;
            write_en(to_integer(write_buf)) <= not hold_image;
          end if;
        elsif narrow_acc(16) = '1' then
          narrow_acc(16) <= '0';
        elsif write_addr /= 1022 then
          write_addr <= write_addr + 1;
          write_en(to_integer(write_buf)) <= not hold_image;
          if pal50_select = '1' then
            narrow_acc <= narrow_acc + NARROW_STEP_PAL;
          else
            narrow_acc <= narrow_acc + NARROW_STEP_NTSC;
          end if;
        end if;
      end if;

      if hsync_in = '0' and hsync_in_prev = '1' then
        in_line <= in_line + 1;
        if in_line + 1 = geo_start then
          write_raster <= "00";
        else
          write_raster <= write_raster + 1;
        end if;
        if in_line + 1 = geo_start + 3 then
          lock_toggle <= not lock_toggle;
        end if;
      end if;

      if vsync_in = '0' and vsync_in_prev = '1' then
        -- The frame that ends here says where the next one's picture is: its
        -- middle goes to the middle of the output, which is 0.48 of the
        -- input's frame after the output's line 0 (360 lines of some 750).
        -- (A frame of that many lines or more is not one to upscale, and one
        -- that is no frame at all comes by when the machine starts: the
        -- figures stay as they were.)
        if in_line >= 400 and in_line < ROWS_MIN and in_active <= in_line then
          geo_lines <= in_line;
          geo_active <= in_active;
          start := to_integer(in_first) + to_integer(in_active) / 2
                   - (to_integer(in_line) * 123) / 256;
          if start < 1 or in_active = 0 then
            start := 1;
          end if;
          geo_start <= to_unsigned(start,11);
          if to_integer(in_first) > start then
            geo_skip <= to_unsigned(to_integer(in_first) - start,11);
          else
            geo_skip <= to_unsigned(0,11);
          end if;
        end if;
        in_line <= to_unsigned(0,11);
        in_active <= to_unsigned(0,11);
      end if;

    end if;
  end process;

  process (clock74p22) is
    variable wanted : unsigned(21 downto 0);
    variable restart : boolean;
    variable hsum : unsigned(16 downto 0);
    variable pa : unsigned(23 downto 0);
    variable hs_on : integer range 0 to 2047;
    variable hs_off : integer range 0 to 2047;
    variable pic_left : integer range 0 to 2047;
    variable pic_width : integer range 0 to 2047;
    variable h_step : integer range 0 to 65536;
    variable last_cell : integer range 0 to 1023;
    variable line_std : integer range 0 to 2047;
    variable rows_nom : integer range 0 to 2047;
    variable rem_nom : integer range -1024 to 2047;
    variable q : integer range 0 to 2047;
    variable r : integer range 0 to 2047;
    variable up : boolean;
    variable no_fill : boolean;
    variable fill_first : integer range -64 to 2047;
    variable fill_n : integer range 1 to 4;
    variable fill_each : integer range 0 to 2047;
    variable fill_odd : integer range 0 to 3;
  begin
    if rising_edge(clock74p22) then

      if pal50_int = '1' then
        hs_on := HSYNC_ON_PAL; hs_off := HSYNC_OFF_PAL;
        pic_left := PIC_LEFT_PAL; pic_width := PIC_WIDTH_PAL; h_step := H_STEP_PAL;
        line_std := LINE_PAL; rows_nom := ROWS_PAL; rem_nom := REM_PAL;
      else
        hs_on := HSYNC_ON_NTSC; hs_off := HSYNC_OFF_NTSC;
        pic_left := PIC_LEFT_NTSC; pic_width := PIC_WIDTH_NTSC; h_step := H_STEP_NTSC;
        line_std := LINE_NTSC; rows_nom := ROWS_NTSC; rem_nom := REM_NTSC;
      end if;
      last_cell := SRC_LAST;
      if narrow_74 = '1' then
        -- the buffers' cells are the pixels out
        if pal50_int = '1' then
          pic_left := NARROW_LEFT_PAL; pic_width := NARROW_WIDTH_PAL;
        else
          pic_left := NARROW_LEFT_NTSC; pic_width := NARROW_WIDTH_NTSC;
        end if;
        h_step := 65536;
        last_cell := pic_width - 1;
      end if;

      -- The (up to) four lines before vsync that take up the frame's odd
      -- clocks: none of them a line that another line of pixels follows
      no_fill := whole_lines_74 = '1';
      fill_first := rows - FILL_FIRST_BEFORE;
      fill_n := 4;
      if fill_first < OUT_HEIGHT - 1 then
        fill_first := OUT_HEIGHT - 1;
        if rows - FILL_LAST_BEFORE - (OUT_HEIGHT - 1) + 1 >= 1 then
          fill_n := rows - FILL_LAST_BEFORE - (OUT_HEIGHT - 1) + 1;
        else
          fill_n := 1;
        end if;
      end if;

      -------------------------------------------------------------------------
      -- The frame

      pos_count <= pos_count + 1;
      if period_count /= 4194303 then
        period_count <= period_count + 1;
      end if;

      if x_count < line_std + extra - 1 then
        x_count <= x_count + 1;
      else
        x_count <= 0;
        if y_count < rows - 1 then
          y_count <= y_count + 1;
          -- (line_rem clocks over four lines: a quarter each, and what does
          -- not divide by four a clock each to the first of them)
          if no_fill then
            extra <= 0;
          elsif y_count + 1 >= fill_first and y_count + 1 < fill_first + fill_n then
            if line_rem >= 0 then
              fill_each := line_rem;
            else
              fill_each := -line_rem;
            end if;
            case fill_n is
              when 4 => fill_odd := fill_each mod 4; fill_each := fill_each / 4;
              when 3 => fill_odd := fill_each mod 3; fill_each := fill_each / 3;
              when 2 => fill_odd := fill_each mod 2; fill_each := fill_each / 2;
              when others => fill_odd := 0;
            end case;
            if fill_odd > y_count + 1 - fill_first then
              fill_each := fill_each + 1;
            end if;
            if line_rem >= 0 then
              extra <= fill_each;
            else
              extra <= -fill_each;
            end if;
          else
            extra <= 0;
          end if;
          -- The next line of the output is v_lines / rows of a line of the
          -- input further down
          if v_acc + v_lines >= rows_v then
            v_acc <= v_acc + v_lines - rows_v;
            src_line <= src_line + 1;
            target_raster <= target_raster + 1;
          else
            v_acc <= v_acc + v_lines;
          end if;
        else
          y_count <= 0;
          pos_count <= to_unsigned(0,22);
          extra <= 0;
          v_acc <= 0;
          src_line <= 0;
          target_raster <= "00";
        end if;
      end if;

      if x_count = hs_on then
        hsync_up <= '1';
        if y_count + VSYNC_ON_BEFORE = rows then
          vsync_up <= '1';
        end if;
        if y_count + VSYNC_OFF_BEFORE = rows then
          vsync_up <= '0';
        end if;
      end if;
      if x_count = hs_off then
        hsync_up <= '0';
      end if;
      if x_count < OUT_WIDTH and y_count < OUT_HEIGHT then
        pixelvalid_up <= '1';
      else
        pixelvalid_up <= '0';
      end if;

      -------------------------------------------------------------------------
      -- The lock

      -- frame length / the line's: how many lines, and how many clocks over
      if div_busy = '1' then
        if div_rem >= div_by then
          div_rem <= div_rem - div_by;
          div_q(div_bit) <= '1';
        else
          div_q(div_bit) <= '0';
        end if;
        div_by <= '0' & div_by(22 downto 1);
        if div_bit /= 0 then
          div_bit <= div_bit - 1;
        else
          div_busy <= '0';
        end if;
      end if;
      if div_busy = '0' and div_apply = '1' then
        div_apply <= '0';
        -- To the nearest line, if the lines before vsync can be that many
        -- clocks shorter; else a line fewer, and they are longer
        q := to_integer(div_q(10 downto 0));
        r := to_integer(div_rem(10 downto 0));
        up := r > line_std / 2 and (no_fill or line_std - r <= FILL_MOST_FEWER * fill_n);
        if up then
          q := q + 1;
        end if;
        if q >= ROWS_MIN and q <= ROWS_MAX then
          rows <= q;
          if not no_fill or q < rows_v or q > rows_v + 1 then
            rows_v <= q;
          end if;
          if no_fill then
            line_rem <= 0;
          elsif up then
            line_rem <= r - line_std;
          else
            line_rem <= r;
          end if;
          frame_len <= div_frame;
        else
          rows <= rows_nom;
          rows_v <= rows_nom;
          line_rem <= rem_nom;
          frame_len <= to_unsigned(rows_nom * line_std + rem_nom,22);
        end if;
      end if;

      -- A lock_toggle, taken over three clocks. In the first, what the
      -- counters say:
      lock_step <= "00";
      if lock_toggle_74 /= lock_toggle_last then
        lock_toggle_last <= lock_toggle_74;
        upscale_en_int <= upscale_en_74;
        running <= upscale_en_74 or hd_en_74;
        v_lines <= to_integer(unsigned(geo_74(32 downto 22)));
        v_skip <= to_integer(unsigned(geo_74(21 downto 11)));
        v_active <= to_integer(unsigned(geo_74(10 downto 0)));
        lock_pos <= pos_count;
        lock_period <= period_count + 1;
        period_count <= to_unsigned(0,22);
        lock_was_on <= running;
        lock_step <= "01";
      end if;

      -- In the second, what they mean
      if lock_step = "01" then
        -- The input's frame, in this clock: two measurements that agree
        period_prev <= lock_period;
        if lock_period = period_prev then
          frame_base <= lock_period;
        end if;
        -- How far the output is past where it should be (or short of it)
        if lock_pos <= ('0' & frame_len(21 downto 1)) then
          lock_err <= to_integer(lock_pos) - LOCK_X;
        else
          lock_err <= to_integer(lock_pos) - to_integer(frame_len) - LOCK_X;
        end if;
        lock_step <= "10";
      end if;

      -- In the third, what is done about it
      if lock_step = "10" then
        restart := false;
        wanted := frame_base;
        if pal50_int /= pal50_select_74 then
          -- The other standard: from its own figures
          pal50_int <= pal50_select_74;
          restart := true;
          period_prev <= to_unsigned(0,22);
          if pal50_select_74 = '1' then
            wanted := to_unsigned(ROWS_PAL * LINE_PAL + REM_PAL,22);
            rows <= ROWS_PAL;
            rows_v <= ROWS_PAL;
            line_rem <= REM_PAL;
          else
            wanted := to_unsigned(ROWS_NTSC * LINE_NTSC + REM_NTSC,22);
            rows <= ROWS_NTSC;
            rows_v <= ROWS_NTSC;
            line_rem <= REM_NTSC;
          end if;
          frame_len <= wanted;
          frame_base <= wanted;
        elsif lock_was_on = '0' or lock_err > LOCK_RESTART or lock_err < -LOCK_RESTART then
          restart := true;
        elsif lock_err > LOCK_DEAD or lock_err < -LOCK_DEAD then
          wanted := to_unsigned(to_integer(frame_base) + lock_err,22);
        end if;

        if restart then
          -- (two clocks after the lock_toggle)
          x_count <= LOCK_X + 2;
          y_count <= 0;
          pos_count <= to_unsigned(LOCK_X + 2,22);
          extra <= 0;
          v_acc <= 0;
          src_line <= 0;
          target_raster <= "00";
        end if;

        div_frame <= wanted;
        div_rem <= '0' & wanted;
        -- (by the line that is in force, or, with the other standard just
        -- chosen above, by its own)
        if pal50_int = pal50_select_74 then
          div_by <= to_unsigned(line_std * 1024,23);
        elsif pal50_select_74 = '1' then
          div_by <= to_unsigned(LINE_PAL * 1024,23);
        else
          div_by <= to_unsigned(LINE_NTSC * 1024,23);
        end if;
        div_bit <= 10;
        div_busy <= '1';
        div_apply <= '1';
      end if;

      -------------------------------------------------------------------------
      -- The picture

      -- The two raster buffers that hold the input's line and the one after
      -- it, and how much of the second
      for i in 0 to 3 loop
        if i = to_integer(target_raster) or i = to_integer(target_raster + 1) then
          raster_buf_active(i) <= '1';
        else
          raster_buf_active(i) <= '0';
        end if;
      end loop;
      if src_line >= v_skip and src_line < v_skip + v_active then
        v_show <= '1';
      else
        v_show <= '0';
      end if;
      if src_line + 1 = v_skip + v_active then
        -- (the last line with pixels has nothing after it)
        coeff1 <= 0;
      elsif (v_acc * 175) / 512 > 255 then
        coeff1 <= 255;
      else
        coeff1 <= (v_acc * 175) / 512;
      end if;

      -- Along the line: for each pixel out, the pixel in that is at or left
      -- of it, and how far past that it is. The cell asked for is the one to
      -- the right of that; the one at or left of it was asked for before,
      -- the first one a clock ahead of the line.
      p_valid(0) <= '0';
      if x_count = pic_left - H_PIPELINE then
        read_addr <= to_unsigned(0,10);
        h_pos <= to_unsigned(0,10);
        h_frac <= to_unsigned(0,16);
        h_new <= '1';
        h_left <= pic_width;
        h_run <= '1';
      elsif h_run = '1' then
        if h_pos >= last_cell then
          read_addr <= to_unsigned(last_cell,10);
        else
          read_addr <= h_pos + 1;
        end if;
        p_valid(0) <= '1';
        p_new(0) <= h_new;
        p_frac(0) <= h_frac(15 downto 10);
        hsum := ('0' & h_frac) + h_step;
        h_frac <= hsum(15 downto 0);
        h_new <= hsum(16);
        if hsum(16) = '1' then
          h_pos <= h_pos + 1;
        end if;
        if h_left = 1 then
          h_run <= '0';
        end if;
        h_left <= h_left - 1;
      end if;
      p_valid(1 to 3) <= p_valid(0 to 2);
      p_new(1 to 3) <= p_new(0 to 2);
      p_frac(1 to 3) <= p_frac(0 to 2);

      rdata_a <= rdata(to_integer(target_raster))(23 downto 0);
      rdata_b <= rdata(to_integer(target_raster + 1))(23 downto 0);

      vmix(7 downto 0) <= mix256(rdata_a(7 downto 0), rdata_b(7 downto 0), coeff1);
      vmix(15 downto 8) <= mix256(rdata_a(15 downto 8), rdata_b(15 downto 8), coeff1);
      vmix(23 downto 16) <= mix256(rdata_a(23 downto 16), rdata_b(23 downto 16), coeff1);

      vmix_prev <= vmix;
      if p_valid(3) = '1' and v_show = '1' and y_count < OUT_HEIGHT then
        if p_new(3) = '1' then
          pa := vmix_prev;
        else
          pa := h_a;
        end if;
        h_a <= pa;
        red_up <= mix64(pa(7 downto 0), vmix(7 downto 0), p_frac(3));
        green_up <= mix64(pa(15 downto 8), vmix(15 downto 8), p_frac(3));
        blue_up <= mix64(pa(23 downto 16), vmix(23 downto 16), p_frac(3));
      else
        red_up <= (others => '0');
        green_up <= (others => '0');
        blue_up <= (others => '0');
      end if;

    end if;
  end process;

  hd_active <= running;
  hd_pixelvalid <= pixelvalid_up;
  hd_red <= red_up;
  hd_green <= green_up;
  hd_blue <= blue_up;
  hd_hsync <= hsync_up;
  hd_vsync <= vsync_up;

  -- Export normal or upscaled image
  process (red_in, green_in, blue_in,
           hsync_in, vsync_in, pixelvalid_in,
           red_up, green_up, blue_up,
           hsync_up, vsync_up, pixelvalid_up,
           upscale_en_int) is
  begin
    if upscale_en_int='1' then red_out <= red_up; else red_out <= red_in; end if;
    if upscale_en_int='1' then green_out <= green_up; else green_out <= green_in; end if;
    if upscale_en_int='1' then blue_out <= blue_up; else blue_out <= blue_in; end if;
    if upscale_en_int='1' then hsync_out <= hsync_up; else hsync_out <= hsync_in; end if;
    if upscale_en_int='1' then vsync_out <= vsync_up; else vsync_out <= vsync_in; end if;
    if upscale_en_int='1' then pixelvalid_out <= pixelvalid_up; else pixelvalid_out <= pixelvalid_in; end if;

  end process;

end hundertwasser;
