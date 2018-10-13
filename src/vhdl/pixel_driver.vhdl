--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2018
--
-- *  This program is free software; you can redistribute it and/or modify
-- *  it under the terms of the GNU Lesser General Public License as
-- *  published by the Free Software Foundation; either version 3 of the
-- *  License, or (at your option) any later version.
-- *
-- *  This program is distributed in the hope that it will be useful,
-- *  but WITHOUT ANY WARRANTY; without even the implied warranty of
-- *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- *  GNU General Public License for more details.
-- *
-- *  You should have received a copy of the GNU Lesser General Public License
-- *  along with this program; if not, write to the Free Software
-- *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
-- *  02111-1307  USA.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity pixel_driver is

  port (
    pixelclock_select : in std_logic_vector(7 downto 0);

    clock200 : in std_logic;
    clock100 : in std_logic;
    clock50 : in std_logic;
    clock40 : in std_logic;
    clock33 : in std_logic;
    clock30 : in std_logic;

    red_i : in unsigned(7 downto 0);
    green_i : in unsigned(7 downto 0);
    blue_i : in unsigned(7 downto 0);

    red_o : out unsigned(7 downto 0);
    green_o : out unsigned(7 downto 0);
    blue_o : out unsigned(7 downto 0);

    raster_strobe : in std_logic;
    hsync_i : in std_logic;
    hsync_o : out std_logic;
    vsync_i : in std_logic;
    vsync_o : out std_logic;

    lcd_hsync_i : in std_logic;
    lcd_hsync_o : out std_logic;
    lcd_vsync_i : in std_logic;
    lcd_vsync_o : out std_logic;

    lcd_display_enable_i : in std_logic;
    lcd_display_enable_o : out std_logic;
    lcd_pixel_strobe_i : in std_logic;
    lcd_pixel_strobe_o : out std_logic;
    
    viciv_outofframe_i : in std_logic;
    viciv_outofframe_o : out std_logic

    );

end pixel_driver;

architecture greco_roman of pixel_driver is

  signal clock_select : std_logic_vector(7 downto 0) := x"00";

  signal waddr : integer := 0;
  signal raddr : integer := 0;
  
  signal raster_toggle : std_logic := '0';
  signal raster_toggle_last : std_logic := '0';

  signal rdata : unsigned(31 downto 0);
  signal wdata : unsigned(31 downto 0);

  signal tick30 : std_logic := '0';
  signal tick33 : std_logic := '0';
  signal tick40 : std_logic := '0';
  signal tick50 : std_logic := '0';
  signal last_tick30 : std_logic := '0';
  signal last_tick33 : std_logic := '0';
  signal last_tick40 : std_logic := '0';
  signal last_tick50 : std_logic := '0';

begin

  -- The only real job here is to select the output clock based
  -- on the input clock.  Thus the bulk of the logic is actually
  -- timing-domain crossing logic.
  -- If we are lucky, it can in fact be implemented just as a
  -- bunch of latches and muxes.

  -- We write pixels as they arrive directly into the raster buffer,
  -- and similarly read them out.
  rasterbuffer0: entity work.ram32x1024_sync
    port map (
      clk => clock100,
      cs => '1',
      w => lcd_pixel_strobe_i,
      write_address => waddr,
      wdata => wdata,
      address => raddr,
      rdata => rdata);
  
  process (lcd_pixel_strobe_i,red_i,green_i,blue_i,clock50,clock100,clock_select,clock30,clock33,clock40) is
    variable waddr_unsigned : unsigned(11 downto 0) := to_unsigned(0,12);
  begin

    -- XXX DEBUG - disabled for now: see XXX below for test pattern injection
--    wdata(7 downto 0) <= red_i;
--    wdata(15 downto 8) <= green_i;
--    wdata(23 downto 16) <= blue_i;
--    wdata(31 downto 24) <= x"00";

    red_o <= rdata(7 downto 0);
    green_o <= rdata(15 downto 8);
    blue_o <= rdata(23 downto 16);
    
    if rising_edge(clock30) then
      if clock_select(1 downto 0) = "00" then
        tick30 <= not tick30;
      end if;
    end if;

    if rising_edge(clock33) then
      if clock_select(1 downto 0) = "01" then
        tick33 <= not tick33;
      end if;
    end if;

    if rising_edge(clock40) then
      if clock_select(1 downto 0) = "10" then
        tick40 <= not tick40;
      end if;
    end if;

    if rising_edge(clock50) then
      if clock_select(1 downto 0) = "11" then
        tick50 <= not tick50;
      end if;
    end if;


    -- Make local clocked version of pixelclock_select, so that we know what we
    -- are doing.
    if rising_edge(clock50) then
      clock_select <= pixelclock_select;
      report "tick : clock_select(1 downto 0) = " & to_string(clock_select(1 downto 0));
    end if;

    -- Manage writing into the raster buffer
    if rising_edge(clock100) then
      report "tick : pixel clock";

      if raster_toggle /= raster_toggle_last then
        raster_toggle_last <= raster_toggle;
        raddr <= 0;
        report "raddr = ZERO";
      elsif (tick30 /= last_tick30)
        or (tick33 /= last_tick33)
        or (tick40 /= last_tick40)
        or (tick50 /= last_tick50) then
        if raddr < 1023 then
          raddr <= raddr + 1;
        end if;
        if tick30 /= last_tick30 then
          report "tick30 : raddr = $" & to_hstring(to_unsigned(raddr,16));
        end if;
        if tick33 /= last_tick33 then
          report "tick33 : raddr = $" & to_hstring(to_unsigned(raddr,16));
        end if;
        if tick40 /= last_tick40 then
          report "tick40 : raddr = $" & to_hstring(to_unsigned(raddr,16));
        end if;
        if tick50 /= last_tick50 then
          report "tick50 : raddr = $" & to_hstring(to_unsigned(raddr,16));
        end if;
      end if;
      last_tick30 <= tick30;
      last_tick33 <= tick33;
      last_tick40 <= tick40;
      last_tick50 <= tick50;    
    
      if lcd_pixel_strobe_i='1' then
        report "lcd_pixel_strobe";
        waddr_unsigned := to_unsigned(waddr,12);
        if waddr_unsigned(0)='1' then
          wdata <= (others => '1');
        else
          wdata <= (others => '0');
        end if;
        if raster_strobe = '0' then
          -- XXX debug show a test pattern
          if waddr < 1023 then
            waddr <= waddr + 1;
          end if;
          -- Start reading of the buffer after we have just put the 2nd byte in.
          if waddr = 1 then
            raster_toggle <= not raster_toggle;
          end if;
        else
          waddr <= 0;
          report "Zeroing waddr";
        end if;
        report "waddr = $" & to_hstring(to_unsigned(waddr,16));
      else
        report "lcd_pixel_strobe_i uninteresting " & std_logic'image(lcd_pixel_strobe_i);
      end if;
    end if;
    
    -- We also need to propagate a bunch of framing signals
    hsync_o <= hsync_i;
    vsync_o <= vsync_i;
    lcd_hsync_o <= lcd_hsync_i;
    lcd_vsync_o <= lcd_vsync_i;
    lcd_display_enable_o <= lcd_display_enable_i;
    viciv_outofframe_o <= viciv_outofframe_i;

    -- We also have to make sure that the new pixel clock is actually
    -- visible on the pixel clocking pin.
    if clock_select(7) = '1' then
      -- Replace pixel clock with a fixed one
      case clock_select(1 downto 0) is
        when "00" => lcd_pixel_strobe_o <= clock30;
        when "01" => lcd_pixel_strobe_o <= clock33;
        when "10" => lcd_pixel_strobe_o <= clock40;
        when "11" => lcd_pixel_strobe_o <= clock50;
        when others =>
          lcd_pixel_strobe_o <= clock50;
      end case;
    else
      -- Pass pixel clock unmodified
      lcd_pixel_strobe_o <= lcd_pixel_strobe_i;
    end if;

  end process;
  
end greco_roman;
