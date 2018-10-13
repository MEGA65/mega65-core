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
library Xpm;
use xpm.vcomponents.all;

entity pixel_driver is

  port (
    -- The various clocks we need
    clock200 : in std_logic;
    clock100 : in std_logic;
    clock50 : in std_logic;
    clock40 : in std_logic;
    clock33 : in std_logic;
    clock30 : in std_logic;

    -- 800x600@50Hz if pal50_select='1', else 800x600@60Hz
    pal50_select : in std_logic;
    -- Shows simple test pattern if '1', else shows normal video
    test_pattern_enable : in std_logic;
    -- Invert hsync or vsync signals if '1'
    hsync_invert : in std_logic;
    vsync_invert : in std_logic;
    
    -- Incoming video, e.g., from VIC-IV and rain compositer
    -- Clocked at clock100 (aka pixelclock)
    red_i : in unsigned(7 downto 0);
    green_i : in unsigned(7 downto 0);
    blue_i : in unsigned(7 downto 0);

    -- Output video stream, clocked at correct clock for the
    -- video mode, i.e., after clock domain crossing
    red_o : out unsigned(7 downto 0);
    green_o : out unsigned(7 downto 0);
    blue_o : out unsigned(7 downto 0);
    -- hsync and vsync signals for VGA
    hsync : out std_logic;
    vsync : out std_logic;

    -- Indicate when next pixel/raster is expected
    pixel_strobe : out std_logic;
    raster_strobe : out std_logic;
    
    -- Similar signals to above for the LCD panel
    -- The main difference is that we only announce pixels during the 800x480
    -- letter box that the LCD can show.
    lcd_hsync : out std_logic;
    lcd_vsync : out std_logic;
    lcd_display_enable : out std_logic;
    lcd_pixel_strobe : out std_logic     -- in 30/40MHz clock domain to match pixels
    
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

  -- Here we generate the frames and the pixel strobe references for everything
  -- that needs to produce pixels, and then buffer the pixels that arrive at pixelclock
  -- in an async FIFO, and then emit the pixels at the appropriate clock rate
  -- for the video mode.  Video mode selection is via a simple PAL/NTSC input.

  frame50: entity work.frame_generator
    generic map ( frame_width => 960,
                  display_width => 800,
                  frame_height => 625,
                  display_height => 600,
                  vsync_start => 620,
                  vsync_end => 625,
                  hsync_start => 814,
                  hsync_end => 884
                  )                  
    port map ( clock => clock30,
               hsync => hsync_pal50_driver,
               hsync_uninverted => hsync_pal50_driver_uninverted,
               vsync => vsync_pal50_driver,
               hsync_polarity => hsync_polarity,
               vsync_polarity => vsync_polarity,
               x_zero => x_zero_pal50,
               y_zero => y_zero_pal50,
               pixel_strobe => pixel_strobe50,
               inframe => inframe_pal50,               
               lcd_vsync => lcd_vsync_pal50,
               lcd_inframe => lcd_inframe_pal50
               );

  frame60: entity work.frame_generator
    generic map ( frame_width => 1056,
                  display_width => 800,
                  frame_height => 628,
                  display_height => 600,
                  vsync_start => 624,
                  vsync_end => 628,
                  hsync_start => 840,
                  hsync_end => 968
                  )                  
    port map ( clock => clock40,
               hsync_polarity => hsync_polarity,
               vsync_polarity => vsync_polarity,
               hsync_uninverted => hsync_ntsc60_uninverted,
               hsync => hsync_ntsc60,
               vsync => vsync_ntsc60,
               x_zero => x_zero_ntsc60,
               y_zero => y_zero_ntsc60,
               pixel_strobe => pixel_strobe60,
               inframe => inframe_ntsc60,
               lcd_vsync => lcd_vsync_ntsc60,
               lcd_inframe => lcd_inframe_ntsc60,

               -- Get test pattern
               red_o => red_n_driver,
               green_o => green_n_driver,
               blue_o => blue_n_driver
               );               
  
  xpm_fifo_async_inst:  xpm_fifo_async
    generic map(
      CDC_SYNC_STAGES=>2,       --DECIMAL
      DOUT_RESET_VALUE=>"0",    --String
      ECC_MODE=>"no_ecc",       --String
      FIFO_MEMORY_TYPE=>"auto", --String
      FIFO_READ_LATENCY=>1,     --DECIMAL
      FIFO_WRITE_DEPTH=>1024,   --DECIMAL
      FULL_RESET_VALUE=>0,      --DECIMAL
      PROG_EMPTY_THRESH=>10,    --DECIMAL
      PROG_FULL_THRESH=>10,     --DECIMAL
      RD_DATA_COUNT_WIDTH=>1,   --DECIMAL
      READ_DATA_WIDTH=>32,      --DECIMAL
      READ_MODE=>"std",         --String
      RELATED_CLOCKS=>0,        --DECIMAL
      USE_ADV_FEATURES=>"0707", --String
      WAKEUP_TIME=>0,           --DECIMAL
      WRITE_DATA_WIDTH=>32,     --DECIMAL
      WR_DATA_COUNT_WIDTH=>1    --DECIMAL
      )
    port map(
      almost_empty=>almost_empty,   -- 1-bit output : AlmostEmpty : When
                                    -- asserted,this signal indicates that
                                    -- only one more read can be performed before
                                    -- the FIFO goes to empty.
      almost_full=>almost_full,     -- 1-bit output : AlmostFull : When asserted,
                                    -- this signal indicates that
                                    -- only one more write can be performed before
                                    -- the FIFO is full.
      data_valid=>data_valid,       -- 1-bit output : Read Data Valid : When
                                    -- asserted, this signal indicates
                                    -- that valid data is available on the output
                                    -- bus (dout).
      dbiterr=>dbiterr,             -- 1-bitoutput : Double Bit Error : Indicates
                                    -- that the ECC decoder
                                    -- detected a double-bit error and data in the
                                    -- FIFO core is corrupted.
      dout=>dout,                   -- READ_DATA_WIDTH-bit output : ReadData : The
                                    -- output data bus is driven
                                    -- when reading the FIFO.
      empty=>empty,                 -- 1-bit output : Empty Flag : When asserted,
                                    -- this signal indicates that
                                    -- the FIFO is empty. Read requests are
                                    -- ignored when the FIFO is empty,
                                    -- initiating a read while empty is not
                                    -- destructive to the FIFO.
      full=>full,                   -- 1-bit output : Full Flag : When asserted,
                                    -- this signal indicates that the
                                    -- FIFO is full. Write requests are ignored
                                    -- when the FIFO is full,
                                    -- initiating a write when the FIFO is full is
                                    -- not destructive to the
                                    -- contents of the FIFO.
      overflow=>overflow,           -- 1-bit output : Overflow : This signal
                                    -- indicates that a write request
                                    -- (wren) during the prior clock cycle was
                                    -- rejected, because the FIFO is
                                    -- full. Overflowing the FIFO is not
                                    -- destructive to the contents of the
                                    -- FIFO.
      prog_empty=>prog_empty,       -- 1-bit output : Programmable Empty : This
                                    -- signal is asserted when the
                                    -- number of words in the FIFO is less than or
                                    -- equal to the programmable
                                    -- empty threshold value. It is de-asserted
                                    -- when the number of words in
                                    -- the FIFO exceeds the programmable empty
                                    -- threshold value.
      prog_full=>prog_full,         -- 1-bit output : Programmable Full : This
                                    -- signal is asserted when the
                                    -- number of words in the FIFO is greater than
                                    -- or equal to the
                                    -- programmable full threshold value. It is
                                    -- de-asserted when the number
                                    -- of words in the FIFO is less than the
                                    -- programmable full threshold
                                    -- value.
      rd_data_count=>rd_data_count, -- RD_DATA_COUNT_WIDTH-bit output : Read
                                    -- Data Count : This bus indicates
                                    -- the number of words read from the FIFO.
      rd_rst_busy=>rd_rst_busy,     -- 1-bit output : Read Reset Busy :
                                    -- Active-High indicator that the FIFO
                                    -- read domain is currently in a reset state.
      sbiterr=>sbiterr,             -- 1-bit output : Single Bit Error :
                                    -- Indicates that the ECC decoder
                                    -- detected and fixed a single-bit error.
      underflow=>underflow,         -- 1-bit output : Underflow:Indicates that the read request(rd_en)
                                    -- during the previous clock cycle was rejected because the FIFO is
                                    -- empty. Underflowing the FIFO is not destructive to the FIFO.
      wr_ack=>wr_ack,               -- 1-bit output : Write Acknowledge :This signal indicates that a write
                                    -- request (wr_en) during the prior clock
                                    -- cycle is succeeded.
      wr_data_count=>wr_data_count, -- WR_DATA_COUNT_WIDTH-bit output :
                                    -- WriteDataCount : This bus indicates`
                                    -- the number of words written into the FIFO.
      wr_rst_busy=>wr_rst_busy,     -- 1-bit output : WriteResetBusy:Active-Highindicatorthat the FIFO
                                    -- write domain is currently in a reset state.
      din=>din,                     -- WRITE_DATA_WIDTH-bit input : WriteData :
                                    -- The input data bus used when writing the FIFO.
      injectdbiterr=>injectdbiterr, -- 1-bit input : Double Bit Error Injection
                                    -- : Injects a double bit error if
                                    -- the ECC feature is used on block RAMs or
                                    -- UltraRAM macros.
      injectsbiterr=>injectsbiterr, -- 1-bit input : Single Bit Error Injection
                                    -- : Injects a single bit error if
                                    -- the ECC feature is used on block RAMs or
                                    -- UltraRAM macros.
      rd_clk=>rd_clk,               -- 1-bit input : Read clock : Used for read
                                    -- operation. rd_clk must be a
                                    -- free running clock.
      rd_en=>rd_en,                 -- 1-bit input : Read Enable : If the FIFO
                                    -- is not empty, asserting this
                                    -- signal causes data (on dout) to be read
                                    -- from the FIFO. Must be held
                                    -- active-low when rd_rst_busy is active high..
      rst=>rst,                     -- 1-bit input : Reset : Must be
                                    -- synchronous to wr_clk. Must be applied
                                    -- only when wr_clk is stable and free-running.
      sleep=>sleep,                 -- 1-bit input : Dynamic power saving : If
                                    -- sleep is High, the memory/fifo
                                    -- block is in power saving mode.
      wr_clk=>wr_clk,               -- 1-bit input : Write clock : Used for
                                    -- write operation. wr_clk must be a
                                    -- free running clock.
      wr_en=>wr_en                  -- 1-bit input : Write Enable : If the FIFO
                                    -- is not full, asserting this
                                    -- signal causes data (on din) to be
                                    -- written to the FIFO. Must be held
                                    -- active-low when rst or wr_rst_busy is
                                    -- active high..
      );
      
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

    if rising_edge(lcd_pixel_strobe_i) then
      report "lcd_pixel_strobe";
      waddr_unsigned := to_unsigned(waddr,12);
      if waddr_unsigned(0)='1' then
        wdata(31 downto 12) <= (others => '1');
        wdata(11 downto 0) <= waddr_unsigned;
      else
        wdata(31 downto 12) <= (others => '0');
        wdata(11 downto 0) <= waddr_unsigned;
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
--    else
--      report "lcd_pixel_strobe_i uninteresting " & std_logic'image(lcd_pixel_strobe_i);
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
