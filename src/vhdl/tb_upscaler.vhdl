-- tb_upscaler.vhdl - the upscaler behind the MEGA65's own frame generator
--
-- Runs frame_generator with pixel_driver's PAL or NTSC settings, feeds the
-- upscaler a picture whose every pixel says where it came from, and writes
-- what comes out to a text file for src/tests/upscaler/check.py (run.sh
-- there runs both):
--
--   L <frame> <y> <clocks in the line - 1> 0 <where hsync fell>
--     <pixels with data enable> <where data enable rose>
--     <first pixel with picture> <last> <R> <G> <B of pixel 640>
--     <least R> <most R> <least G> <most G of the pixels with picture>
--   V <frame> <where in its line vsync rose> <line where it fell> <where in it>
--   F <frame> <clocks in the frame> <lines in the frame>
--   P <frame> <y> <pixel> <R> <G> <B>       one line in full
-- and to the same name with .in:
--   I <input frame> <clock27 cycles in it> <its lines> <first line with pixels> <last>
-- A frame is from one rise of vsync to the next and a line from one rise of
-- hsync to the next; y and positions in a line count from those.
--
-- The picture: red is the line's number modulo 256, green 100 times that
-- number's high part and 48 more on every second four lines, blue the
-- pixel's number in the line modulo 256. Lines are counted from the start
-- of vsync, on the starts of hsync. (The 48: a line and the one four after
-- it share a raster buffer, and so differ enough for a cell read at the
-- wrong moment to show even where it counts for a few percent.)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_upscaler is
  generic (
    PAL        : boolean := true;
    INTERLACE  : boolean := false;
    -- half periods: 81 MHz is 22 units and the 720p clock 24 units when the
    -- two are 27 MHz x 3 and 27 MHz x 11/4 (74.25 MHz) exactly
    HALF81     : time := 6172848 fs;
    HALF74     : time := 6734016 fs;
    FRAMES     : integer := 6;
    ENABLE_AT  : integer := 1;      -- the input frame in which upscale_en rises
    DISABLE_AT : integer := 0;      -- and the one in which it falls again (0: never)
    SWITCH_AT  : integer := 0;      -- the input frame in which PAL becomes NTSC or back (0: never)
    HD_ONLY    : boolean := false;  -- ask with hd_en and look at the hd_ outputs: upscale_en stays off
    WHOLE_LINES : boolean := false; -- the upscaler's whole_lines input
    NARROW     : boolean := false;  -- and its narrow input
    DUMP_FRAME : integer := 4;
    DUMP_Y     : integer := 360;
    OUTFILE    : string := "upscaler.out"
    );
end entity;

architecture sim of tb_upscaler is

  signal clock81 : std_logic := '0';
  signal clock27 : std_logic := '0';
  signal clock74 : std_logic := '0';

  function to_sl(b : boolean) return std_logic is
  begin
    if b then return '1'; else return '0'; end if;
  end function;

  signal pal50 : std_logic := to_sl(PAL);
  signal interlace_sel : std_logic;

  signal vsync_p, vga_hsync_p, de_p : std_logic;
  signal vsync_n, vga_hsync_n, de_n : std_logic;
  signal vsync, vga_hsync, de : std_logic;

  signal red_in, green_in, blue_in : unsigned(7 downto 0) := x"00";
  signal upscale_en : std_logic := '0';

  -- what is looked at: the upscaler's outputs, or its hd_ ones
  signal red_out, green_out, blue_out : unsigned(7 downto 0);
  signal hsync_out, vsync_out, de_out : std_logic;
  signal m_red, m_green, m_blue : unsigned(7 downto 0);
  signal m_hsync, m_vsync, m_de : std_logic;
  signal h_red, h_green, h_blue : unsigned(7 downto 0);
  signal h_hsync, h_vsync, h_de : std_logic;
  signal en_main, en_hd : std_logic;

  -- the input, as the upscaler's writing side counts it
  signal in_line : integer := 0;
  signal in_px : integer := 0;
  signal in_frame : integer := 0;
  signal vsync_prev, hsync_prev : std_logic := '1';

begin

  interlace_sel <= '1' when INTERLACE else '0';

  clock81 <= not clock81 after HALF81;
  clock74 <= not clock74 after HALF74;

  -- 27 MHz, its edges on every third of the 81 MHz clock's
  process (clock81) is
    variable n : integer := 0;
  begin
    if rising_edge(clock81) then
      if n = 0 then clock27 <= '1'; end if;
      if n = 1 then clock27 <= '0'; end if;
      if n = 2 then n := 0; else n := n + 1; end if;
    end if;
  end process;

  -- pixel_driver's frame50
  frame50: entity work.frame_generator
    generic map (
      frame_width => 864, frame_height => 625,
      x_zero_position => 864-45,
      fullwidth_width => 800, fullwidth_start => 0,
      narrow_width => 720, narrow_start => 0,
      pipeline_delay => 0,
      first_raster => 1+16, last_raster => 576+16,
      vsync_start => 576+16+5, vsync_end => 576+16+5+4,
      hsync_start => 720+12+5, hsync_end => 720+12+5+64,
      vga_hsync_start => 720, vga_hsync_end => 720+64,
      lcd_first_raster => 1+(576-480)/2, lcd_last_raster => 1+576-(576-480)/2
      )
    port map (
      clock81 => clock81, clock41 => '0',
      hsync_polarity => '1', vsync_polarity => '0',
      interlace_enable => interlace_sel,
      vsync => vsync_p, vga_hsync => vga_hsync_p, narrow_dataenable => de_p
      );

  -- pixel_driver's frame60
  frame60: entity work.frame_generator
    generic map (
      frame_width => 858, frame_height => 526,
      fullwidth_start => 0, fullwidth_width => 800,
      narrow_start => 0, narrow_width => 720,
      pipeline_delay => 0,
      vsync_start => 480+1+9, vsync_end => 480+1+5+9,
      hsync_start => 720+16+5, hsync_end => 720+16+62+5,
      vga_hsync_start => 720+10, vga_hsync_end => 720+10+62,
      first_raster => 1, last_raster => 480,
      lcd_first_raster => 1, lcd_last_raster => 480,
      cycles_per_raster_1mhz => 65, cycles_per_raster_2mhz => 65*2,
      cycles_per_raster_3mhz => 228
      )
    port map (
      clock81 => clock81, clock41 => '0',
      hsync_polarity => '1', vsync_polarity => '0',
      interlace_enable => interlace_sel,
      vsync => vsync_n, vga_hsync => vga_hsync_n, narrow_dataenable => de_n
      );

  vsync <= vsync_p when pal50 = '1' else vsync_n;
  vga_hsync <= vga_hsync_p when pal50 = '1' else vga_hsync_n;
  de <= de_p when pal50 = '1' else de_n;

  -- the picture
  process (clock27) is
    file f : text;
    variable l : line;
    variable cycles : integer := 0;
    variable first_line, last_line : integer := -1;
    variable ln : integer := 0;       -- lines since vsync began
    variable pl : integer := 0;       -- the line the pixels now coming belong to
    variable px : integer := 0;       -- pixels of it so far
    variable de_prev : std_logic := '0';
  begin
    if rising_edge(clock27) then
      cycles := cycles + 1;
      vsync_prev <= vsync;
      hsync_prev <= vga_hsync;
      if vga_hsync = '0' and hsync_prev = '1' then
        ln := ln + 1;
      end if;
      if vsync = '0' and vsync_prev = '1' then
        if in_frame > 0 then
          write(l, string'("I ")); write(l, in_frame); write(l, ' ');
          write(l, cycles); write(l, ' '); write(l, ln); write(l, ' ');
          write(l, first_line); write(l, ' '); write(l, last_line);
          file_open(f, OUTFILE & ".in", append_mode);
          writeline(f, l);
          file_close(f);
        end if;
        cycles := 0;
        first_line := -1;
        ln := 0;
        in_frame <= in_frame + 1;
        if in_frame + 1 >= ENABLE_AT and (DISABLE_AT = 0 or in_frame + 1 < DISABLE_AT) then
          upscale_en <= '1';
        else
          upscale_en <= '0';
        end if;
        if SWITCH_AT /= 0 and in_frame + 1 = SWITCH_AT then
          pal50 <= not pal50;
        end if;
      end if;
      -- (the pixel that is on the wires with a clock's data enable is the one
      -- set at the clock before: so the next one is set here)
      if de = '1' then
        if de_prev = '0' then
          pl := ln;
          px := 0;
          if first_line < 0 then first_line := ln; end if;
          last_line := ln;
        end if;
        px := px + 1;
      elsif de_prev = '1' then
        px := 0;
      end if;
      de_prev := de;
      in_line <= ln;
      in_px <= px;
      if de = '1' then
        red_in <= to_unsigned(pl mod 256, 8);
        green_in <= to_unsigned((pl / 256) * 100 + ((pl / 4) mod 2) * 48, 8);
      else
        -- (what the next line's first pixel will be: it is set a clock early)
        red_in <= to_unsigned(ln mod 256, 8);
        green_in <= to_unsigned((ln / 256) * 100 + ((ln / 4) mod 2) * 48, 8);
      end if;
      blue_in <= to_unsigned(px mod 256, 8);
    end if;
  end process;

  dut: entity work.upscaler
    port map (
      clock27 => clock27,
      clock74p22 => clock74,
      hold_image => '0',
      ntsc_inc_coarse => '0', ntsc_dec_coarse => '0',
      ntsc_inc_fine => '0', ntsc_dec_fine => '0',
      pal50_select => pal50,
      upscale_en => en_main,
      vlock_en => '1',
      pixelvalid_in => de,
      red_in => red_in, green_in => green_in, blue_in => blue_in,
      hsync_in => vga_hsync, vsync_in => vsync,
      pixelvalid_out => m_de,
      red_out => m_red, green_out => m_green, blue_out => m_blue,
      hsync_out => m_hsync, vsync_out => m_vsync,
      hd_en => en_hd,
      whole_lines => to_sl(WHOLE_LINES),
      narrow => to_sl(NARROW),
      hd_pixelvalid => h_de,
      hd_red => h_red, hd_green => h_green, hd_blue => h_blue,
      hd_hsync => h_hsync, hd_vsync => h_vsync
      );

  en_main <= upscale_en when not HD_ONLY else '0';
  en_hd <= upscale_en when HD_ONLY else '0';
  red_out <= h_red when HD_ONLY else m_red;
  green_out <= h_green when HD_ONLY else m_green;
  blue_out <= h_blue when HD_ONLY else m_blue;
  hsync_out <= h_hsync when HD_ONLY else m_hsync;
  vsync_out <= h_vsync when HD_ONLY else m_vsync;
  de_out <= h_de when HD_ONLY else m_de;

  -- what comes out, by the 720p clock
  process (clock74) is
    file f : text;
    variable l : line;
    variable started : boolean := false;
    variable frame : integer := 0;
    variable y : integer := 0;
    variable x : integer := 0;                 -- clocks since hsync rose
    variable hs_prev, vs_prev, de_prev : std_logic := '0';
    variable hs_fall, de_rise, de_count : integer := -1;
    variable first_pic, last_pic : integer := -1;
    variable cr, cg, cb : integer := 0;
    variable rmin, rmax, gmin, gmax : integer := 0;
    variable vs_rise_x, vs_fall_x : integer := -1;
    variable frame_clocks : integer := 0;
    variable vs_rise, vs_fall : integer := -1;
    variable seen_en : boolean := false;
  begin
    if rising_edge(clock74) then
      if not started then
        file_open(f, OUTFILE, write_mode);
        started := true;
      end if;
      if upscale_en = '1' and hsync_out = '1' and vsync_out = '1' then
        seen_en := true;
      end if;
      if seen_en then
        frame_clocks := frame_clocks + 1;
        -- a line is from one rise of hsync to the next
        if hsync_out = '1' and hs_prev = '0' then
          if frame > 0 then
            write(l, string'("L ")); write(l, frame); write(l, ' '); write(l, y);
            write(l, ' '); write(l, x); write(l, string'(" 0 ")); write(l, hs_fall);
            write(l, ' '); write(l, de_count); write(l, ' '); write(l, de_rise);
            write(l, ' '); write(l, first_pic); write(l, ' '); write(l, last_pic);
            write(l, ' '); write(l, cr); write(l, ' '); write(l, cg);
            write(l, ' '); write(l, cb);
            write(l, ' '); write(l, rmin); write(l, ' '); write(l, rmax);
            write(l, ' '); write(l, gmin); write(l, ' '); write(l, gmax);
            writeline(f, l);
          end if;
          x := 0;
          y := y + 1;
          hs_fall := -1; de_rise := -1; de_count := 0;
          first_pic := -1; last_pic := -1;
          cr := 0; cg := 0; cb := 0;
          rmin := 255; rmax := 0; gmin := 255; gmax := 0;
        else
          x := x + 1;
        end if;
        if hsync_out = '0' and hs_prev = '1' then hs_fall := x; end if;
        if de_out = '1' then
          if de_prev = '0' then de_rise := x; end if;
          if red_out /= 0 or green_out /= 0 or blue_out /= 0 then
            if first_pic < 0 then first_pic := de_count; end if;
            last_pic := de_count;
            if to_integer(red_out) < rmin then rmin := to_integer(red_out); end if;
            if to_integer(red_out) > rmax then rmax := to_integer(red_out); end if;
            if to_integer(green_out) < gmin then gmin := to_integer(green_out); end if;
            if to_integer(green_out) > gmax then gmax := to_integer(green_out); end if;
          end if;
          if de_count = 640 then
            cr := to_integer(red_out); cg := to_integer(green_out);
            cb := to_integer(blue_out);
          end if;
          if frame = DUMP_FRAME and y = DUMP_Y then
            write(l, string'("P ")); write(l, frame); write(l, ' '); write(l, y);
            write(l, ' '); write(l, de_count); write(l, ' ');
            write(l, to_integer(red_out)); write(l, ' ');
            write(l, to_integer(green_out)); write(l, ' ');
            write(l, to_integer(blue_out));
            writeline(f, l);
          end if;
          de_count := de_count + 1;
        end if;
        -- a frame is from one rise of vsync to the next; y counts lines from
        -- there
        if vsync_out = '1' and vs_prev = '0' then
          if frame > 0 then
            write(l, string'("V ")); write(l, frame); write(l, ' ');
            write(l, vs_rise_x); write(l, ' '); write(l, vs_fall);
            write(l, ' '); write(l, vs_fall_x);
            writeline(f, l);
            write(l, string'("F ")); write(l, frame); write(l, ' ');
            write(l, frame_clocks); write(l, ' '); write(l, y);
            writeline(f, l);
          end if;
          frame := frame + 1;
          frame_clocks := 0;
          y := 0;
          vs_rise := 0;
          vs_rise_x := x;
          if frame > FRAMES then
            file_close(f);
            report "done";
            stop;
          end if;
        end if;
        if vsync_out = '0' and vs_prev = '1' then vs_fall := y; vs_fall_x := x; end if;
      end if;
      hs_prev := hsync_out;
      vs_prev := vsync_out;
      de_prev := de_out;
    end if;
  end process;

end architecture;
