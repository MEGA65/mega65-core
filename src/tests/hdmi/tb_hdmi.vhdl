-- tb_hdmi: vga_to_hdmi.vhdl fed with 720 x 480 at 27 MHz (or with HD, 1280 x
-- 720 at 74.25 MHz) and 48 kHz sound, its
-- TMDS characters written out for decode.py. Every clock of the first
-- FULL_FRAMES frames, after that only the lines of vertical blanking.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.types_pkg.all;

entity tb_hdmi is
  generic (FRAMES : integer := 3; FULL_FRAMES : integer := 2; VRR : boolean := false;
           HD : boolean := false; SILENT : boolean := false;
           DVI : boolean := false; OUTFILE : string := "hdmi.out");
end entity;

architecture sim of tb_hdmi is
  function sel(c : boolean; a, b : integer) return integer is
  begin
    if c then return a; else return b; end if;
  end function;
  function sel(c : boolean; a, b : time) return time is
  begin
    if c then return a; else return b; end if;
  end function;
  constant H_TOTAL : integer := sel(HD, 1650, 858); constant H_ACTIVE : integer := sel(HD, 1280, 720);
  constant H_FRONT : integer := sel(HD, 110, 16);   constant H_SYNC : integer := sel(HD, 40, 62);
  constant V_TOTAL : integer := sel(HD, 750, 525);  constant V_ACTIVE : integer := sel(HD, 720, 480);
  constant V_FRONT : integer := sel(HD, 5, 9);      constant V_SYNC : integer := sel(HD, 5, 6);
  constant HALF : time := sel(HD, 6734 ps, 18518 ps);
  constant CTS : integer := sel(HD, 74250, 27000);
  signal clk, pclk : std_logic := '0';
  signal rst : std_logic := '1';
  signal x, y, frame, n : integer := 0;
  signal hs, vs, de : std_logic := '0';
  signal r, g, b : std_logic_vector(7 downto 0) := (others => '0');
  signal clken, acr : std_logic := '0';
  signal l, rr : std_logic_vector(15 downto 0) := (others => '0');
  signal tmds : slv_9_0_t(0 to 2);
  signal done : boolean := false;
  signal vrr_sl, dvi_sl, silent_sl : std_logic;
begin
  vrr_sl <= '1' when VRR else '0';
  dvi_sl <= '1' when DVI else '0';
  silent_sl <= '1' when SILENT else '0';
  clk <= not clk after HALF when not done else '0';
  pclk <= not pclk after 40690 ps when not done else '0';
  rst <= '0' after 3 us;

  process (clk) begin
    if rising_edge(clk) then
      n <= n + 1;
      if x = H_TOTAL-1 then
        x <= 0;
        if y = V_TOTAL-1 then y <= 0; frame <= frame + 1; else y <= y + 1; end if;
      else
        x <= x + 1;
      end if;
    end if;
  end process;
  de <= '1' when x < H_ACTIVE and y < V_ACTIVE else '0';
  hs <= '1' when x >= H_ACTIVE+H_FRONT and x < H_ACTIVE+H_FRONT+H_SYNC else '0';
  vs <= '1' when y >= V_ACTIVE+V_FRONT and y < V_ACTIVE+V_FRONT+V_SYNC else '0';
  r <= std_logic_vector(to_unsigned(x mod 256, 8));
  g <= std_logic_vector(to_unsigned(y mod 256, 8));
  b <= std_logic_vector(to_unsigned((x + y) mod 256, 8));

  process (pclk)
    variable c, a : integer := 0;
  begin
    if rising_edge(pclk) then
      clken <= '0'; acr <= '0';
      if c = 255 then
        c := 0; clken <= '1';
        l <= std_logic_vector(unsigned(l) + 257);
        rr <= std_logic_vector(unsigned(rr) + 513);
      else
        c := c + 1;
      end if;
      if a = 12287 then a := 0; acr <= '1'; else a := a + 1; end if;
    end if;
  end process;

  dut: entity work.vga_to_hdmi
    port map (
      select_44100 => '0',
      dvi => dvi_sl, vic => x"03", aspect => "01", pix_rep => '0',
      vrr => vrr_sl, silent => silent_sl,
      vs_pol => '1', hs_pol => '1',
      vga_rst => rst, vga_clk => clk, vga_vs => vs, vga_hs => hs, vga_de => de,
      vga_r => r, vga_g => g, vga_b => b,
      pcm_rst => rst, pcm_clk => pclk, pcm_clken => clken, pcm_l => l, pcm_r => rr,
      pcm_acr => acr, pcm_n => std_logic_vector(to_unsigned(6144, 20)),
      pcm_cts => std_logic_vector(to_unsigned(CTS, 20)),
      tmds => tmds);

  process (clk)
    file f : text open write_mode is OUTFILE;
    variable ln : line;
  begin
    if rising_edge(clk) then
      if frame >= FRAMES then
        done <= true;
      elsif rst = '0' and (frame < FULL_FRAMES or y >= V_ACTIVE - 2) then
        write(ln, n); write(ln, ' '); write(ln, frame); write(ln, ' ');
        write(ln, y); write(ln, ' '); write(ln, x);
        for i in 0 to 2 loop
          write(ln, ' ');
          if is_x(tmds(i)) then write(ln, -1); else write(ln, to_integer(unsigned(tmds(i)))); end if;
        end loop;
        writeline(f, ln);
      end if;
    end if;
  end process;
end architecture;
