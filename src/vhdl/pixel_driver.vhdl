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
    clock100 : in std_logic;
    clock120 : in std_logic;

    -- Inform VIC-IV of new rasters and new frames
    x_zero_out : out std_logic;
    y_zero_out : out std_logic;
    
    waddr_out : out unsigned(11 downto 0);
    wr_ack : out std_logic;
    fifo_full : out std_logic;
    rd_data_count : out std_logic_vector(9 downto 0);
    wr_data_count : out std_logic_vector(9 downto 0);
    
    -- 800x600@50Hz if pal50_select='1', else 800x600@60Hz
    pal50_select : in std_logic;
    -- Shows simple test pattern if '1', else shows normal video
    test_pattern_enable : in std_logic;
    -- Invert hsync or vsync signals if '1'
    hsync_invert : in std_logic;
    vsync_invert : in std_logic;
    
    -- Incoming video, e.g., from VIC-IV and rain compositer
    -- Clocked at clock100 (aka pixelclock)
    pixel_strobe_in : in std_logic;
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

    -- Signals for VIC-IV etc to know what is happening
    hsync_uninverted : out std_logic;
    vsync_uninverted : out std_logic;
    y_zero : out std_logic;
    x_zero : out std_logic;
    inframe : out std_logic;
    
    -- Indicate when next pixel/raster is expected
    pixel_strobe100_out : out std_logic;
    pixel_strobe120_out : out std_logic;
    
    -- Similar signals to above for the LCD panel
    -- The main difference is that we only announce pixels during the 800x480
    -- letter box that the LCD can show.
    lcd_hsync : out std_logic;
    lcd_vsync : out std_logic;
    lcd_display_enable : out std_logic;
    lcd_pixel_strobe : out std_logic;     -- in 30/40MHz clock domain to match pixels
    lcd_inframe : out std_logic
    
    );

end pixel_driver;

architecture greco_roman of pixel_driver is

  signal fifo_inuse120 : std_logic := '0';
  signal fifo_inuse120_drive : std_logic := '0';
  signal fifo_inuse100 : std_logic := '0';
  signal fifo_almost_empty100 : std_logic := '0';
  signal fifo_almost_empty120 : std_logic := '0';
  signal fifo_running : std_logic := '0';
  signal fifo_running100 : std_logic := '0';
  signal fifo_running_drive : std_logic := '0';
  signal fifo_rst : std_logic := '1';
  signal reset_counter_zero_120 : std_logic := '0';
  signal reset_counter_zero : std_logic := '0';
  signal reset_counter_zero_drive : std_logic := '0';
  signal reset_counter100 : integer range 0 to 255 := 255;
  signal fifo_empty120 : std_logic := '0';
  signal fifo_full120 : std_logic := '0';
  
  signal raster_strobe : std_logic := '0';
  signal inframe_internal : std_logic := '0';
  
  signal pal50_select_internal : std_logic := '0';
  signal pal50_select_internal_drive : std_logic := '0';
  signal pal50_select_internal100 : std_logic := '0';

  signal wr_en : std_logic := '0';
  signal waddr : integer := 0;
  signal wdata : unsigned(31 downto 0);

  signal raddr50 : integer := 0;
  signal raddr60 : integer := 0;
  signal rd_en : std_logic := '0';
  signal rdata : unsigned(31 downto 0);  
  
  signal raster_toggle : std_logic := '0';
  signal raster_toggle_last : std_logic := '0';

  signal hsync_pal50 : std_logic := '0';
  signal hsync_pal50_uninverted : std_logic := '0';
  signal vsync_pal50 : std_logic := '0';
  signal vsync_pal50_uninverted : std_logic := '0';
  
  signal hsync_ntsc60 : std_logic := '0';
  signal hsync_ntsc60_uninverted : std_logic := '0';
  signal vsync_ntsc60 : std_logic := '0';
  signal vsync_ntsc60_uninverted : std_logic := '0';

  signal lcd_vsync_pal50 : std_logic := '0';
  signal lcd_vsync_ntsc60 : std_logic := '0';
  
  signal test_pattern_red : unsigned(7 downto 0) := x"00";
  signal test_pattern_green : unsigned(7 downto 0) := x"00";
  signal test_pattern_blue : unsigned(7 downto 0) := x"00";

  signal x_zero_pal50_100 : std_logic := '0';
  signal x_zero_pal50_120 : std_logic := '0';
  signal y_zero_pal50_100 : std_logic := '0';
  signal y_zero_pal50_120 : std_logic := '0';
  signal x_zero_ntsc60_100 : std_logic := '0';
  signal x_zero_ntsc60_120 : std_logic := '0';
  signal y_zero_ntsc60_100 : std_logic := '0';
  signal y_zero_ntsc60_120 : std_logic := '0';

  signal inframe_pal50 : std_logic := '0';
  signal inframe_ntsc60 : std_logic := '0';

  signal lcd_inframe_pal50 : std_logic := '0';
  signal lcd_inframe_ntsc60 : std_logic := '0';

  signal pixel_strobe120_50 : std_logic := '0';
  signal pixel_strobe120_60 : std_logic := '0';
  
  signal pixel_strobe100_50 : std_logic := '0';
  signal pixel_strobe100_60 : std_logic := '0';
  
  signal test_pattern_red50 : unsigned(7 downto 0) := x"00";
  signal test_pattern_green50 : unsigned(7 downto 0) := x"00";
  signal test_pattern_blue50 : unsigned(7 downto 0) := x"00";
  signal test_pattern_red60 : unsigned(7 downto 0) := x"00";
  signal test_pattern_green60 : unsigned(7 downto 0) := x"00";
  signal test_pattern_blue60 : unsigned(7 downto 0) := x"00";

  signal raster_toggle50 : std_logic := '0';
  signal raster_toggle60 : std_logic := '0';
  signal raster_toggle_last50 : std_logic := '0';
  signal raster_toggle_last60 : std_logic := '0';

  signal plotting : std_logic := '0';
  signal plotting50 : std_logic := '0';
  signal plotting60 : std_logic := '0';

  signal y_zero_internal : std_logic := '0';

begin

  -- Here we generate the frames and the pixel strobe references for everything
  -- that needs to produce pixels, and then buffer the pixels that arrive at pixelclock
  -- in an async FIFO, and then emit the pixels at the appropriate clock rate
  -- for the video mode.  Video mode selection is via a simple PAL/NTSC input.

  frame50: entity work.frame_generator
    generic map ( frame_width => 960*4-1,
                  clock_dividor => 4,
                  display_width => 800,
                  frame_height => 625,
                  pipeline_delay => 0,
                  display_height => 600,
                  vsync_start => 620,
                  vsync_end => 625,
                  hsync_start => 814*4,
                  hsync_end => 884*4
                  )                  
    port map ( clock120 => clock120,
               clock100 => clock100,
               hsync => hsync_pal50,
               hsync_uninverted => hsync_pal50_uninverted,
               vsync => vsync_pal50,
               hsync_polarity => hsync_invert,
               vsync_polarity => vsync_invert,
               
               inframe => inframe_pal50,               
               lcd_vsync => lcd_vsync_pal50,
               lcd_inframe => lcd_inframe_pal50,

               -- 100MHz facing signals for the VIC-IV
               x_zero_120 => x_zero_pal50_120,
               x_zero_100 => x_zero_pal50_100,
               y_zero_100 => y_zero_pal50_100,
               y_zero_120 => y_zero_pal50_120,
               pixel_strobe_120 => pixel_strobe120_50,
               pixel_strobe_100 => pixel_strobe100_50

               );

  frame60: entity work.frame_generator
    generic map ( frame_width => 1057*3-1,
                  display_width => 800,
                  clock_dividor => 3,
                  frame_height => 628,
                  display_height => 600,
                  pipeline_delay => 0,
                  vsync_start => 624,
                  vsync_end => 628,
                  hsync_start => 840*3,
                  hsync_end => 968*3
                  )                  
    port map ( clock120 => clock120,
               clock100 => clock100,
               hsync_polarity => hsync_invert,
               vsync_polarity => vsync_invert,
               hsync_uninverted => hsync_ntsc60_uninverted,
               hsync => hsync_ntsc60,
               vsync => vsync_ntsc60,
               inframe => inframe_ntsc60,
               lcd_vsync => lcd_vsync_ntsc60,
               lcd_inframe => lcd_inframe_ntsc60,

               -- 100MHz facing signals for VIC-IV
               x_zero_120 => x_zero_ntsc60_120,
               x_zero_100 => x_zero_ntsc60_100,               
               y_zero_100 => y_zero_ntsc60_100,
               y_zero_120 => y_zero_ntsc60_120,
               pixel_strobe_120 => pixel_strobe120_60,
               pixel_strobe_100 => pixel_strobe100_60
               
               
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
      PROG_EMPTY_THRESH=>5,    --DECIMAL
      PROG_FULL_THRESH=>10,     --DECIMAL
      RD_DATA_COUNT_WIDTH=>10,  --DECIMAL
      READ_DATA_WIDTH=>32,      --DECIMAL
      READ_MODE=>"std",         --String
      RELATED_CLOCKS=>0,        --DECIMAL
      USE_ADV_FEATURES=>"0707", --String
      WAKEUP_TIME=>0,           --DECIMAL
      WRITE_DATA_WIDTH=>32,     --DECIMAL
      WR_DATA_COUNT_WIDTH=>10   --DECIMAL
      )
    port map(
      almost_empty=>fifo_almost_empty120,   -- 1-bit output : AlmostEmpty : When
                                    -- asserted,this signal indicates that
                                    -- only one more read can be performed before
                                    -- the FIFO goes to empty.
      -- almost_full=>almost_full,     -- 1-bit output : AlmostFull : When asserted,
                                    -- this signal indicates that
                                    -- only one more write can be performed before
                                    -- the FIFO is full.
      -- data_valid=>data_valid,       -- 1-bit output : Read Data Valid : When
                                    -- asserted, this signal indicates
                                    -- that valid data is available on the output
                                    -- bus (dout).
      -- dbiterr=>dbiterr,             -- 1-bitoutput : Double Bit Error : Indicates
                                    -- that the ECC decoder
                                    -- detected a double-bit error and data in the
                                    -- FIFO core is corrupted.
      unsigned(dout)=>rdata,                  -- READ_DATA_WIDTH-bit output : ReadData : The
                                    -- output data bus is driven
                                    -- when reading the FIFO.
      empty=>fifo_empty120,                 -- 1-bit output : Empty Flag : When asserted,
                                    -- this signal indicates that
                                    -- the FIFO is empty. Read requests are
                                    -- ignored when the FIFO is empty,
                                    -- initiating a read while empty is not
                                    -- destructive to the FIFO.
      full=>fifo_full120,                   -- 1-bit output : Full Flag : When asserted,
                                    -- this signal indicates that the
                                    -- FIFO is full. Write requests are ignored
                                    -- when the FIFO is full,
                                    -- initiating a write when the FIFO is full is
                                    -- not destructive to the
                                    -- contents of the FIFO.
      -- overflow=>overflow,           -- 1-bit output : Overflow : This signal
                                    -- indicates that a write request
                                    -- (wren) during the prior clock cycle was
                                    -- rejected, because the FIFO is
                                    -- full. Overflowing the FIFO is not
                                    -- destructive to the contents of the
                                    -- FIFO.
      -- prog_empty=>prog_empty,       -- 1-bit output : Programmable Empty : This
                                    -- signal is asserted when the
                                    -- number of words in the FIFO is less than or
                                    -- equal to the programmable
                                    -- empty threshold value. It is de-asserted
                                    -- when the number of words in
                                    -- the FIFO exceeds the programmable empty
                                    -- threshold value.
      -- prog_full=>prog_full,         -- 1-bit output : Programmable Full : This
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
      -- rd_rst_busy=>rd_rst_busy,     -- 1-bit output : Read Reset Busy :
                                    -- Active-High indicator that the FIFO
                                    -- read domain is currently in a reset state.
      -- sbiterr=>sbiterr,             -- 1-bit output : Single Bit Error :
                                    -- Indicates that the ECC decoder
                                    -- detected and fixed a single-bit error.
      -- underflow=>underflow,         -- 1-bit output : Underflow:Indicates that the read request(rd_en)
                                    -- during the previous clock cycle was rejected because the FIFO is
                                    -- empty. Underflowing the FIFO is not destructive to the FIFO.
      wr_ack=>wr_ack,               -- 1-bit output : Write Acknowledge :This signal indicates that a write
                                    -- request (wr_en) during the prior clock
                                    -- cycle is succeeded.
      wr_data_count=>wr_data_count, -- WR_DATA_COUNT_WIDTH-bit output :
                                    -- WriteDataCount : This bus indicates`
                                    -- the number of words written into the FIFO.
      -- wr_rst_busy=>wr_rst_busy,  -- 1-bit output : WriteResetBusy:Active-Highindicatorthat the FIFO
                                    -- write domain is currently in a reset state.
      din=>std_logic_vector(wdata), -- WRITE_DATA_WIDTH-bit input : WriteData :
                                    -- The input data bus used when writing the FIFO.
      injectdbiterr=>'0',           -- 1-bit input : Double Bit Error Injection
                                    -- : Injects a double bit error if
                                    -- the ECC feature is used on block RAMs or
                                    -- UltraRAM macros.
      injectsbiterr=>'0',           -- 1-bit input : Single Bit Error Injection
                                    -- : Injects a single bit error if
                                    -- the ECC feature is used on block RAMs or
                                    -- UltraRAM macros.
      rd_clk=>clock120,             -- 1-bit input : Read clock : Used for read
                                    -- operation. rd_clk must be a
                                    -- free running clock.
      rd_en=>rd_en,                 -- 1-bit input : Read Enable : If the FIFO
                                    -- is not empty, asserting this
                                    -- signal causes data (on dout) to be read
                                    -- from the FIFO. Must be held
                                    -- active-low when rd_rst_busy is active high..
      rst=>fifo_rst,                -- 1-bit input : Reset : Must be
                                    -- synchronous to wr_clk. Must be applied
                                    -- only when wr_clk is stable and free-running.
      sleep=>'0',                   -- 1-bit input : Dynamic power saving : If
                                    -- sleep is High, the memory/fifo
                                    -- block is in power saving mode.
      wr_clk=>clock100,             -- 1-bit input : Write clock : Used for
                                    -- write operation. wr_clk must be a
                                    -- free running clock.
      wr_en=>wr_en                  -- 1-bit input : Write Enable : If the FIFO
                                    -- is not full, asserting this
                                    -- signal causes data (on din) to be
                                    -- written to the FIFO. Must be held
                                    -- active-low when rst or wr_rst_busy is
                                    -- active high..
      );

  hsync <= hsync_pal50 when pal50_select_internal='1' else hsync_ntsc60;
  vsync <= vsync_pal50 when pal50_select_internal='1' else vsync_ntsc60;
  lcd_vsync <= vsync_pal50 when pal50_select_internal='1' else lcd_vsync_ntsc60;
  inframe <= inframe_pal50 when pal50_select_internal='1' else inframe_ntsc60;
  inframe_internal <= inframe_pal50 when pal50_select_internal='1' else inframe_ntsc60;
  lcd_inframe <= lcd_inframe_pal50 when pal50_select_internal='1' else lcd_inframe_ntsc60;

  raster_strobe <= x_zero_pal50_100 when pal50_select_internal100='1' else x_zero_ntsc60_100;
  x_zero <= x_zero_pal50_100 when pal50_select_internal100='1' else x_zero_ntsc60_100;
  y_zero <= y_zero_pal50_100 when pal50_select_internal100='1' else y_zero_ntsc60_100;
  y_zero_internal <= y_zero_pal50_120 when pal50_select_internal='1' else y_zero_ntsc60_120;
  pixel_strobe100_out <= pixel_strobe100_50 when pal50_select_internal100='1' else pixel_strobe100_60;
  
  -- Generate output pixel strobe and signals for read-side of the FIFO
  pixel_strobe120_out <= pixel_strobe120_50 when pal50_select_internal='1' else pixel_strobe120_60;
  rd_en <= (fifo_running_drive and pixel_strobe120_50) when pal50_select_internal='1' else (fifo_running_drive and pixel_strobe120_60);

  plotting <= '0' when y_zero_internal='1' else
              plotting50 when pal50_select_internal='1'
              else plotting60;
  
  -- Generate test pattern data
--  test_pattern_red50 <= to_unsigned(waddr,8);
--  test_pattern_green50 <= to_unsigned(waddr,8);
--  test_pattern_blue50(7 downto 4) <= to_unsigned(waddr,4);
--  test_pattern_blue50(3 downto 0) <= (others => '0');
--  test_pattern_red60 <= to_unsigned(waddr,8);
--  test_pattern_green60 <= to_unsigned(waddr,8);
--  test_pattern_blue60 <= to_unsigned(waddr,8);

  test_pattern_red <= test_pattern_red50 when pal50_select_internal100='1' else test_pattern_red60;
  test_pattern_green <= test_pattern_green50 when pal50_select_internal100='1' else test_pattern_green60;
  test_pattern_blue <= test_pattern_blue50 when pal50_select_internal100='1' else test_pattern_blue60;
  
  wdata(7 downto 0) <= red_i  when test_pattern_enable='0' else test_pattern_red;
  wdata(15 downto 8) <= green_i  when test_pattern_enable='0' else test_pattern_green;
  wdata(23 downto 16) <= blue_i when test_pattern_enable='0' else test_pattern_blue;
  wdata(31 downto 24) <= x"00";  

  x_zero_out <= x_zero_pal50_100 when pal50_select_internal100='1' else x_zero_ntsc60_100;
  y_zero_out <= y_zero_pal50_100 when pal50_select_internal100='1' else y_zero_ntsc60_100;
  
  process (clock100,clock120) is
    variable waddr_unsigned : unsigned(11 downto 0) := to_unsigned(0,12);
  begin

    if rising_edge(clock100) then
      pal50_select_internal100 <= pal50_select;
      fifo_full <= fifo_full120;
    end if;        
    if rising_edge(clock120) then
      fifo_inuse120_drive <= fifo_inuse100;
      fifo_inuse120 <= fifo_inuse120_drive;
      pal50_select_internal_drive <= pal50_select;
      pal50_select_internal <= pal50_select_internal_drive;
    end if;

    if rising_edge(clock120) then

      -- Output the pixels or else the test pattern
      red_o <= x"00" when plotting='0' else rdata(7 downto 0);
      green_o <= x"00" when plotting='0' else rdata(15 downto 8);
      blue_o <= x"00" when plotting='0' else rdata(23 downto 16);
        
      if x_zero_pal50_120='1' or fifo_inuse120='0' or fifo_empty120='1' then
        raddr50 <= 0;
        plotting50 <= '0';
        report "raddr = ZERO";
      else
        if raddr50 < 800 then
          if fifo_almost_empty120='0' then
            plotting50 <= '1';
          end if;
        else
          plotting50 <= '0';
        end if;
        if pixel_strobe120_50 = '1' then
          if raddr50 < 1023 then
            raddr50 <= raddr50 + 1;
          end if;
        end if;
      end if;

      if x_zero_ntsc60_120='1' or fifo_inuse120='0' or fifo_empty120='1' then
        raddr60 <= 0;
        plotting60 <= '0';
        report "raddr = ZERO";
      else
        if raddr60 < 800 then
          if fifo_almost_empty120='0' then
            plotting60 <= '1';
          end if;
        else
          plotting60 <= '0';
        end if;
        if pixel_strobe120_60 = '1' then
          if raddr60 < 1023 then
            raddr60 <= raddr60 + 1;
          end if;
        end if;
      end if;
    end if;
    
    if rising_edge(clock120) then
      reset_counter_zero_120 <= reset_counter_zero_drive;
      fifo_running_drive <= fifo_running;      
      if reset_counter_zero_120 = '1' then
        fifo_running <= '1';
      else
        fifo_running <= '0';
      end if;
    end if;

    if rising_edge(clock100) then
      reset_counter_zero_drive <= reset_counter_zero;
      if reset_counter100 /= 0 then
        reset_counter100 <= reset_counter100 - 1;
        fifo_running100 <= '0';
        if reset_counter100 = 32 then
          fifo_rst <= '0';
        end if;
        reset_counter_zero <= '0';
      else
        reset_counter_zero <= '1';
        fifo_running100 <= '1';
      end if;
    end if;
    
    -- Manage writing into the raster buffer
    if rising_edge(clock100) then
      fifo_almost_empty100 <= fifo_almost_empty120;
      if pixel_strobe_in='1' then
        waddr_unsigned := to_unsigned(waddr,12);
        waddr_out <= to_unsigned(waddr,12);
--        if waddr_unsigned(0)='1' then
--          wdata(31 downto 12) <= (others => '1');
--          wdata(11 downto 0) <= waddr_unsigned;
--        else
--          wdata(31 downto 12) <= (others => '0');
--          wdata(11 downto 0) <= waddr_unsigned;
--        end if;
        if raster_strobe = '0' then
          fifo_inuse100 <= not fifo_almost_empty100;
          if waddr < 1023 then
            waddr <= waddr + 1;
          end if;
        else
          waddr <= 0;
          fifo_inuse100 <= '0';
          report "Zeroing waddr";
        end if;
        report "waddr = $" & to_hstring(to_unsigned(waddr,16));
        wr_en <= '1' and fifo_running100;
      else
        wr_en <= '0';
      end if;
    end if;
    
  end process;
  
end greco_roman;
