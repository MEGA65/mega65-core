library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use IEEE.numeric_std.ALL;

library xpm;
use xpm.vcomponents.ALL;

library unisim;
use unisim.vcomponents.all;

entity upscaler is
  port (
    -- Input and output pixel clocks
    clock27 : in std_logic;
    clock74p22 : in std_logic;

    -- Change behaviour
    hold_image : in std_logic;

    ntsc_inc_coarse : in std_logic;
    ntsc_dec_coarse : in std_logic;
    ntsc_inc_fine : in std_logic;
    ntsc_dec_fine : in std_logic;

    pal_inc_coarse : in std_logic := '0';
    pal_dec_coarse : in std_logic := '0';
    pal_inc_fine : in std_logic := '0';
    pal_dec_fine : in std_logic := '0';


    -- PAL or NTSC mode
    pal50_select : in std_logic;

    -- Upscale enable/disable
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
    vsync_out : out std_logic

    );
end entity;

architecture hundertwasser of upscaler is

  signal write_en : std_logic_vector(3 downto 0) := "0000";
  signal write_addr : unsigned(9 downto 0);
  type u10_array_t is array(0 to 3) of unsigned(9 downto 0);
  signal read_addr : u10_array_t;
  type u32_array_t is array(0 to 3) of unsigned(31 downto 0);
  signal rdata : u32_array_t;
  signal rdata_buf0 : unsigned(31 downto 0);
  signal rdata_buf1 : unsigned(31 downto 0);
  signal rdata_buf2 : unsigned(31 downto 0);
  signal rdata_buf3 : unsigned(31 downto 0);

  signal red_up : unsigned(7 downto 0);
  signal green_up : unsigned(7 downto 0);
  signal blue_up : unsigned(7 downto 0);
  signal hsync_up : std_logic;
  signal vsync_up : std_logic;
  signal pixelvalid_up : std_logic;

  signal write_raster : integer range 0 to 3 := 0;
  signal vsync_in_prev : std_logic := '0';
  signal hsync_in_prev : std_logic := '0';


  signal coeff0 : integer range 0 to 256 := 256;
  signal coeff1 : integer range 0 to 256 := 0;
  signal coeff2 : integer range 0 to 256 := 0;
  signal coeff3 : integer range 0 to 256 := 0;

  signal upscale_en_int : std_logic := '0';

  signal x_count : integer := 0;
  signal y_count : integer := 0;
  signal pal50_int : std_logic := '1';
  signal frame_start_toggle : std_logic := '0';
  signal last_frame_start_toggle : std_logic := '0';

  signal raster_leap_cycle : integer range 0 to 2 := 0;
  signal frame_leap_cycle : integer range 0 to 2 := 0;

  -- PAL frame synchronisation counters
  signal pal_raster_counter : unsigned(10 downto 0) := to_unsigned(0,11);
  signal last_pal_raster_counter : std_logic := '0';
  signal pal_frame_counter : unsigned(7 downto 0) := to_unsigned(0,8);
  signal pal_frame_counter_8 : unsigned(8 downto 0) := to_unsigned(0,9);
  signal last_pal_frame_counter : std_logic := '0';

  -- NTSC frame synchronisation counters
  signal ntsc_raster_counter : unsigned(10 downto 0) := to_unsigned(0,11);
  signal last_ntsc_raster_counter : std_logic := '0';
  signal ntsc_frame_counter : unsigned(11 downto 0) := to_unsigned(0,12);
  signal ntsc_frame_counter_1141 : unsigned(12 downto 0) := to_unsigned(0,13);
  signal last_ntsc_frame_counter : std_logic := '0';

  signal raster_in_toggle : std_logic := '0';
  signal last_raster_in_toggle : std_logic := '0';
  signal raster_0_writing : std_logic := '0';

  signal target_raster : integer range 0 to 3 := 0;
  signal last_raster_phase : std_logic := '0';
  signal raster_phase : unsigned(16 downto 0) := to_unsigned(0,17);

  -- Configurable parameters:
  signal first_read_raster_pal : integer range 0 to 3 := 0;
  signal first_read_raster_ntsc : integer range 0 to 3 := 0;

  signal ntsc_coarse : unsigned(9 downto 0) := to_unsigned(284,10); -- / 1024ths
  signal ntsc_fine : unsigned(11 downto 0) := to_unsigned(2623,12); --

  -- PAL FUDGE FACTORS PART 1:
  -- (See PAL FUDGE FACTORS PART 2 to explanation as to what's going on here)
  -- signal pal_coarse : unsigned(9 downto 0) := to_unsigned(391,10);
  -- We have 104.48 or so cycles per frame too many
  -- Well, reducing it by 104 got it to one excess frame 10 minutes, i.e.,
  -- 1/3000.  That means
  -- signal pal_coarse : unsigned(9 downto 0) := to_unsigned(391,10);
  -- signal pal_fine : unsigned(7 downto 0) := to_unsigned(0,8);

  -- 200 is too little.
  -- 250 too much.
  -- 225 is very slightly too much
  -- 220 is even more slightly too little
  signal pal_coarse : unsigned(9 downto 0) := to_unsigned(222       -- This is
                                                                  -- the fudge
                                                                  -- factor
                                                          ,10);
  signal pal_fine : unsigned(7 downto 0) := to_unsigned(0,8); -- And this, too

  -- 2^16 x rasters in / rasters out
  -- PAL in = 625, NTSC in = 526, rasters out = 750
  -- 625/750 x 2^16 = 54613.333
  -- 526/750 x 2^16 = 45962.581
  signal raster_phase_add_pal : unsigned(15 downto 0) := to_unsigned(54613,16);
  signal raster_phase_add_ntsc : unsigned(15 downto 0) := to_unsigned(45962,16);

  signal upscale_en_74 : std_logic;
  signal pal50_select_74 : std_logic;
  signal vlock_en_74 : std_logic;
  signal frame_start_toggle_74 : std_logic;
  signal raster_0_writing_74 : std_logic;

  signal reading_raster_0 : std_logic;

  signal zero : std_logic := '0';
  signal zerov : std_logic_vector(0 downto 0) := (others => '0');

  signal raster_buf_active : std_logic_vector(3 downto 0) := "0000";

  signal cursor_start : integer := 0;
  signal cursor_end : integer := 0;

  signal ntsc_inc_fine_74 : std_logic := '0';
  signal ntsc_dec_fine_74 : std_logic := '0';
  signal ntsc_inc_coarse_74 : std_logic := '0';
  signal ntsc_dec_coarse_74 : std_logic := '0';

  signal last_ntsc_inc_fine_74 : std_logic := '0';
  signal last_ntsc_dec_fine_74 : std_logic := '0';
  signal last_ntsc_inc_coarse_74 : std_logic := '0';
  signal last_ntsc_dec_coarse_74 : std_logic := '0';

  signal pal_inc_fine_74 : std_logic := '0';
  signal pal_dec_fine_74 : std_logic := '0';
  signal pal_inc_coarse_74 : std_logic := '0';
  signal pal_dec_coarse_74 : std_logic := '0';

  signal last_pal_inc_fine_74 : std_logic := '0';
  signal last_pal_dec_fine_74 : std_logic := '0';
  signal last_pal_inc_coarse_74 : std_logic := '0';
  signal last_pal_dec_coarse_74 : std_logic := '0';


begin

  cdcntsc0 : xpm_cdc_single
    port map (
        src_in => ntsc_inc_fine,
        src_clk => clock27,
        dest_clk => clock74p22,
        dest_out => ntsc_inc_fine_74
    );
  cdcntsc1 : xpm_cdc_single
    port map (
        src_in => ntsc_dec_fine,
        src_clk => clock27,
        dest_clk => clock74p22,
        dest_out => ntsc_dec_fine_74
    );

  cdcntsc2 : xpm_cdc_single
    port map (
        src_in => ntsc_inc_coarse,
        src_clk => clock27,
        dest_clk => clock74p22,
        dest_out => ntsc_inc_coarse_74
    );
  cdcntsc3 : xpm_cdc_single
    port map (
        src_in => ntsc_dec_coarse,
        src_clk => clock27,
        dest_clk => clock74p22,
        dest_out => ntsc_dec_coarse_74
    );

  xpm_cdc_single_inst0 : xpm_cdc_single
    port map (
        src_in => pal50_select,
        src_clk => clock27,
        dest_clk => clock74p22,
        dest_out => pal50_select_74
    );

  xpm_cdc_single_inst2 : xpm_cdc_single
    port map (
        src_in => upscale_en,
        src_clk => clock27,
        dest_clk => clock74p22,
        dest_out => upscale_en_74
    );

  xpm_cdc_single_inst1 : xpm_cdc_single
    port map (
        src_in => vlock_en,
        src_clk => clock27,
        dest_clk => clock74p22,
        dest_out => vlock_en_74
    );

  xpm_cdc_single_inst3 : xpm_cdc_single
    port map (
        src_in => frame_start_toggle,
        src_clk => clock27,
        dest_clk => clock74p22,
        dest_out => frame_start_toggle_74
    );

  xpm_cdc_single_inst4 : xpm_cdc_single
    port map (
        src_in => raster_0_writing,
        src_clk => clock27,
        dest_clk => clock74p22,
        dest_out => raster_0_writing_74
    );


  rasterbufs: for i in 0 to 3 generate
    rastbuf0: entity work.upscaler_ram32x1024 port map (
      clka => clock27,
      ena => write_en(i),
      wea => write_en(i),
      addra => std_logic_vector(write_addr),
      dina(7 downto 0) => std_logic_vector(red_in),
      dina(15 downto 8) => std_logic_vector(green_in),
      dina(23 downto 16) => std_logic_vector(blue_in),
      dina(31 downto 24) => (others => '0'),

      clkb => clock74p22,
      enb => raster_buf_active(i),
      addrb => std_logic_vector(read_addr(i)),
      unsigned(doutb) => rdata(i)
      );
  end generate;

  process (clock27, clock74p22) is
  begin
    if rising_edge(clock27) then
      -- Tell fast side when a new frame starts
      write_en <= (others => '0');
      vsync_in_prev <= vsync_in;
      hsync_in_prev <= hsync_in;
      if hsync_in='0' and hsync_in_prev='1' then
        write_addr <= to_unsigned(0,10);
        raster_in_toggle <= not raster_in_toggle;
        if write_raster /= 3 then
          write_raster <= write_raster + 1;
        else
          write_raster <= 0;
        end if;
      elsif pixelvalid_in='1' then
        write_addr <= write_addr + 1;
        write_en(write_raster) <= not hold_image;
      end if;
      if vsync_in='0' and vsync_in_prev='1' then
        frame_start_toggle <= not frame_start_toggle;
        write_raster <= 0;
        write_addr <= to_unsigned(0,10);
      end if;

      if write_raster = 0 then
        raster_0_writing <= '1';
      else
        raster_0_writing <= '0';
      end if;

    end if;

    if rising_edge(clock74p22) then
      -- Generate 720p video frame, and extract data
      -- PAL:  1280 	720 	50 Hz 	37.5 kHz 	ModeLine "1280x720" 74.25 1280 1720 1760 1980 720 725 730 750 +HSync +VSync
      --       i.e., 1980 x 750 = 1485000 clocks per frame
      -- NTSC: 1280 	720 	60 Hz 	45 kHz 	        ModeLine "1280x720" 74.25 1280 1390 1430 1650 720 725 730 750 +HSync +VSync
      --       i.e., 1650 x 750 = 1237500 clocks per frame
      -- However, as our clock is 74.2268MHz instead of 74.25MHz, we will be a
      -- few clocks short per frame.  The difference is about 464 or 387 clocks
      -- per frame depending on whether we are in PAL or NTSC.  That's about 1
      -- clock tick per 2 raster lines, but not exactly.
      -- Another approach is to just use the VSYNC synchronisation to reset the
      -- vertical counter, but not the horizontal counter. That way every 3
      -- frames or so we will skip/insert a raster. If the number of rasters from
      -- the VSYNC pulse in the output to the start of video is constant, it should
      -- look fine. We'll try that.

      if ntsc_inc_fine_74 /= last_ntsc_inc_fine_74 then
        last_ntsc_inc_fine_74 <= ntsc_inc_fine_74;
        if ntsc_fine < (4095-100) then
          ntsc_fine <= ntsc_fine + 1;
        else
          ntsc_fine <= to_unsigned(4095,12);
        end if;
      end if;
      if ntsc_dec_fine_74 /= last_ntsc_dec_fine_74 then
        last_ntsc_dec_fine_74 <= ntsc_dec_fine_74;
        if ntsc_fine > 100 then
          ntsc_fine <= ntsc_fine - 1;
        else
          ntsc_fine <= to_unsigned(0,12);
        end if;
      end if;

      if ntsc_inc_coarse_74 /= last_ntsc_inc_coarse_74 then
        last_ntsc_inc_coarse_74 <= ntsc_inc_coarse_74;
        if ntsc_coarse < 510 then
          ntsc_coarse <= ntsc_coarse + 1;
        end if;
      end if;
      if ntsc_dec_coarse_74 /= last_ntsc_dec_coarse_74 then
        last_ntsc_dec_coarse_74 <= ntsc_dec_coarse_74;
        if ntsc_coarse > 0 then
          ntsc_coarse <= ntsc_coarse - 1;
        end if;
      end if;

      if pal_inc_fine_74 /= last_pal_inc_fine_74 then
        last_pal_inc_fine_74 <= pal_inc_fine_74;
        if pal_fine < (255) then
          pal_fine <= pal_fine + 1;
        else
          pal_fine <= to_unsigned(255,8);
        end if;
      end if;
      if pal_dec_fine_74 /= last_pal_dec_fine_74 then
        last_pal_dec_fine_74 <= pal_dec_fine_74;
        if pal_fine > 0 then
          pal_fine <= pal_fine - 1;
        else
          pal_fine <= to_unsigned(0,8);
        end if;
      end if;

      if pal_inc_coarse_74 /= last_pal_inc_coarse_74 then
        last_pal_inc_coarse_74 <= pal_inc_coarse_74;
        if pal_coarse < 510 then
          pal_coarse <= pal_coarse + 1;
        end if;
      end if;
      if pal_dec_coarse_74 /= pal_dec_coarse_74 then
        pal_dec_coarse_74 <= pal_dec_coarse_74;
        if pal_coarse > 0 then
          pal_coarse <= pal_coarse - 1;
        end if;
      end if;

      rdata_buf0 <= rdata(0);
      rdata_buf1 <= rdata(1);
      rdata_buf2 <= rdata(2);
      rdata_buf3 <= rdata(3);

      if (target_raster = 0) or (target_raster = 3) then
        reading_raster_0 <= '1';
      else
        reading_raster_0 <= '0';
      end if;

      -- Work out the mixture of the raster lines required
      -- Sum of coefficients should always = 256
      case target_raster is
        when 0 =>
          raster_buf_active(0) <= '1';
          raster_buf_active(1) <= '1';
          raster_buf_active(2) <= '0';
          raster_buf_active(3) <= '0';
          coeff0 <= 256 - to_integer(raster_phase(15 downto 8));
          coeff1 <= to_integer(raster_phase(15 downto 8));
          coeff2 <= 0;
          coeff3 <= 0;
        when 1 =>
          raster_buf_active(0) <= '0';
          raster_buf_active(1) <= '1';
          raster_buf_active(2) <= '1';
          raster_buf_active(3) <= '0';
          coeff0 <= 0;
          coeff1 <= 256 - to_integer(raster_phase(15 downto 8));
          coeff2 <= to_integer(raster_phase(15 downto 8));
          coeff3 <= 0;
        when 2 =>
          raster_buf_active(0) <= '0';
          raster_buf_active(1) <= '0';
          raster_buf_active(2) <= '1';
          raster_buf_active(3) <= '1';
          coeff0 <= 0;
          coeff1 <= 0;
          coeff2 <= 256 - to_integer(raster_phase(15 downto 8));
          coeff3 <= to_integer(raster_phase(15 downto 8));
        when 3 =>
          raster_buf_active(0) <= '1';
          raster_buf_active(1) <= '0';
          raster_buf_active(2) <= '0';
          raster_buf_active(3) <= '1';
          coeff0 <= to_integer(raster_phase(15 downto 8));
          coeff1 <= 0;
          coeff2 <= 0;
          coeff3 <= 256 - to_integer(raster_phase(15 downto 8));
      end case;


      if y_count = 725 then
        vsync_up <= '1';
      end if;
      if y_count = 730 then
        vsync_up <= '0';
      end if;
      if pal50_int='1' then
        if x_count < (1980-2

                      -- PAL FUDGE FACTORS PART 2:
                      -- On MEGA65 core PAL 720p frame is almost exactly 1 576p raster line
                      -- too long (even though in hdmi_test_r4 target that uses the same
                      -- pixeldriver.vhdl frame generator this doesn't happen).  Why is a mystery.
                      -- That we need to compensate a certainty. Thus the extra fudge factor
                      -- here.
                      -- With no fudge factor, one whole frame was slipped in
                      -- ~12.5 seconds (~1 raster per frame)
                      -- With -2, one whole frame is slipped in about 33.5 seconds
                      -- (~ 0.37 rasters per frame).
                      -- That is, each -1 here is reducing the rasters per
                      -- frame by about 0.315.
                      -- Thus a fudge factor of -3 should get it as close as possible
                      -- at around (1-.945)x625 = 0.05 rasters per second, or slipping
                      -- one whole frame every ~250 seconds.
                      -- That's still not accurate
                      -- enough. But we need to measure that in practice first,
                      -- to confirm these measurements. If correct, then we can
                      -- tweak how often we add leap cycles to rasters to trim
                      -- it back to perfect alignment.
                      -- Ok, with -3, it now takes 236 seconds to slip a whole
                      -- frame.  That's a lot more slip still compared to what
                      -- we expected, but as doing the timing for the higher
                      -- speeds of frame slip is a bit tricky, that's okay.
                      -- Anyway, 236 seconds / frame = 2.65 rasters per second
                      -- = 0.0529 rasters per frame.
                      -3 -- This is the extra fudge factor

                      +raster_leap_cycle) then
          x_count <= x_count + 1;
        else
          -- Add one cycle to every 286/750 rasters = 391/1024 rasters,
          -- provided we reset the pal_raster_counter every frame
          if vlock_en_74='1' then
            pal_raster_counter <= pal_raster_counter + to_integer(pal_coarse);
            if pal_raster_counter(10) /= last_pal_raster_counter then
              raster_leap_cycle <= 1;
              last_pal_raster_counter <= pal_raster_counter(10);
            else
              raster_leap_cycle <= frame_leap_cycle;
              frame_leap_cycle <= 0;
            end if;
          else
            raster_leap_cycle <= 0;
            frame_leap_cycle <= 0;
          end if;
          x_count <= 0;
          if y_count < (750-1) then
            y_count <= y_count + 1;

            raster_phase <= raster_phase + to_integer(raster_phase_add_pal);
            if raster_phase(16) /= last_raster_phase then
              last_raster_phase <= raster_phase(16);
              if target_raster /= 3 then
                target_raster <= target_raster + 1;
              else
                target_raster <= 0;
              end if;
            end if;
          else
            y_count <= 0;

            -- Reset buffered raster selection at top of frame
            coeff0 <= 256;
            coeff1 <= 0;
            coeff2 <= 0;
            coeff3 <= 0;
            raster_phase <= to_unsigned(0,17);
            last_raster_phase <= '0';
            target_raster <= first_read_raster_pal;

            pal_raster_counter <= to_unsigned(0,11);
            if vlock_en_74='1' then
              -- Add one cycle for every 8/97 frames
              if pal_frame_counter < 96 then
                pal_frame_counter <= pal_frame_counter + 1;
                pal_frame_counter_8 <= pal_frame_counter_8 + to_integer(pal_fine);
                if pal_frame_counter_8(8) /= last_pal_frame_counter then
                  frame_leap_cycle <= 1;
                  last_pal_frame_counter <= pal_frame_counter_8(8);
                end if;
              else
                pal_frame_counter <= to_unsigned(0,8);
                pal_frame_counter_8 <= to_unsigned(0,9);
              end if;
            end if;
          end if;
        end if;
        if x_count = (1720 + raster_leap_cycle) then
          hsync_up <= '1';
        end if;
        if x_count = (1760 + raster_leap_cycle) then
          hsync_up <= '0';
        end if;
      else
        -- NTSC
        if x_count < (1654-1+raster_leap_cycle) then
          x_count <= x_count + 1;
        else
          -- Add leap cycles to fix NTSC frame VLOCK
          if vlock_en_74='1' then
            ntsc_raster_counter <= ntsc_raster_counter + to_integer(ntsc_coarse);
            if ntsc_raster_counter(10) /= last_ntsc_raster_counter then
              raster_leap_cycle <= 1;
              last_ntsc_raster_counter <= ntsc_raster_counter(10);
            else
              raster_leap_cycle <= frame_leap_cycle;
              frame_leap_cycle <= 0;
            end if;
          else
            raster_leap_cycle <= 0;
            frame_leap_cycle <= 0;
          end if;
          x_count <= 0;
          if y_count < (750-1) then
            y_count <= y_count + 1;
            raster_phase <= raster_phase + to_integer(raster_phase_add_ntsc);
            if raster_phase(16) /= last_raster_phase then
              last_raster_phase <= raster_phase(16);
              if target_raster /= 3 then
                target_raster <= target_raster + 1;
              else
                target_raster <= 0;
              end if;
            end if;
          else
            y_count <= 0;

            -- Reset buffered raster selection at top of frame
            coeff0 <= 256;
            coeff1 <= 0;
            coeff2 <= 0;
            coeff3 <= 0;
            raster_phase <= to_unsigned(0,17);
            last_raster_phase <= '0';
            target_raster <= first_read_raster_ntsc;

            -- XXX tweak NTSC VLOCK timing to have one more raster with a leap
            -- cycle, because for somereason we can't get coarse+fine adjustment
            -- to otherwise get this exactly right.
            ntsc_raster_counter <= (others => '1');
            if vlock_en_74='1' then
              -- Add one cycle for every 1,141 / 2,619 frames
              if ntsc_frame_counter < 2619 then
                ntsc_frame_counter <= ntsc_frame_counter + 1;
                ntsc_frame_counter_1141 <= ntsc_frame_counter_1141 + to_integer(ntsc_fine);
                if ntsc_frame_counter_1141(12) /= last_ntsc_frame_counter then
                  frame_leap_cycle <= 2;
                  last_ntsc_frame_counter <= ntsc_frame_counter_1141(12);
                end if;
              else
                ntsc_frame_counter <= to_unsigned(0,12);
                ntsc_frame_counter_1141 <= to_unsigned(0,13);
              end if;
            end if;
          end if;
        end if;
        if x_count = (1390) then
          hsync_up <= '1';
        end if;
        if x_count = (1430 + raster_leap_cycle) then
          hsync_up <= '0';
        end if;
      end if;
      if x_count < 1280 then
        pixelvalid_up <= '1';
      else
        pixelvalid_up <= '0';
      end if;
      if frame_start_toggle_74 /= last_frame_start_toggle then
        last_frame_start_toggle <= frame_start_toggle_74;
        upscale_en_int <= upscale_en_74;
        if upscale_en_int = '0' or pal50_int /= pal50_select_74 then
          -- Until upscaler is enabled, we keep resetting the frame start.
          -- This is so that if PAL and NTSC are switched, we don't have
          -- big problems with the synchronisation getting out of step with
          -- the input source.
          pal50_int <= pal50_select_74;
          x_count <= 0;
          -- so that VBLANK periods align
          if pal50_select_74='1' then
            y_count <= 720;
          else
            y_count <= 725;
          end if;
        end if;
      end if;
      if x_count < 280 then
        -- Left shoulder
        red_up <= (others => '0');
        green_up <= (others => '0');
        blue_up <= (others => '0');
        -- Avoid simultaneous read/write glitches on the raster buffer BRAMs
        -- by pointing only the ones we are reading from to the correct cell.
        -- Idle ones point to end of BRAM, which we don't ever write to.
        read_addr <= (others => (others => '1'));
        read_addr(target_raster) <= to_unsigned(0,10);
        read_addr((target_raster + 1) mod 4) <= to_unsigned(0,10);
      elsif (x_count < 1000) and (y_count < 720) then
        -- Work out which X position we need to read from the raster buffers
        read_addr(target_raster) <= to_unsigned(x_count - ((1280 - 720)/2),10);
        read_addr((target_raster +1) mod 4) <= to_unsigned(x_count - ((1280 - 720)/2),10);
        -- Active pixel: Do mix of the rasters
        red_up <= to_unsigned(to_integer(rdata_buf0(7 downto 0)) * coeff0,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata_buf1(7 downto 0)) * coeff1,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata_buf2(7 downto 0)) * coeff2,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata_buf3(7 downto 0)) * coeff3,16)(15 downto 8);
        green_up <= to_unsigned(to_integer(rdata_buf0(15 downto 8)) * coeff0,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata_buf1(15 downto 8)) * coeff1,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata_buf2(15 downto 8)) * coeff2,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata_buf3(15 downto 8)) * coeff3,16)(15 downto 8);
        blue_up <= to_unsigned(to_integer(rdata_buf0(23 downto 16)) * coeff0,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata_buf1(23 downto 16)) * coeff1,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata_buf2(23 downto 16)) * coeff2,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata_buf3(23 downto 16)) * coeff3,16)(15 downto 8);
      else
        -- Right shoulder / fly back
        red_up <= (others => '0');
        green_up <= (others => '0');
        blue_up <= (others => '0');

      end if;

      -- Blank above and below active area of image
      if pal50_int='1' and ((y_count < 20) or (y_count > (720 - 15))) then
        red_up <= (others => '0');
        green_up <= (others => '0');
        blue_up <= (others => '0');
      end if;
      if pal50_int='0' and ((y_count < 22) or (y_count > (720 - 22))) then
        red_up <= (others => '0');
        green_up <= (others => '0');
        blue_up <= (others => '0');
      end if;

    end if;
  end process;

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

