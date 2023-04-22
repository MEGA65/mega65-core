library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use IEEE.numeric_std.ALL;

library unisim;
use unisim.vcomponents.all;

entity upscaler is
  port (
    -- Input and output pixel clocks
    clock27 : in std_logic;
    clock74p22 : in std_logic;

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

  signal write_en : std_logic_vector(2 downto 0) := "000";
  signal write_addr : unsigned(9 downto 0);
  signal read_addr : unsigned(9 downto 0);
  type u32_array_t is array(0 to 2) of unsigned(31 downto 0);
  signal rdata : u32_array_t;

  signal red_up : unsigned(7 downto 0);
  signal green_up : unsigned(7 downto 0);
  signal blue_up : unsigned(7 downto 0);
  signal hsync_up : std_logic;
  signal vsync_up : std_logic;
  signal pixelvalid_up : std_logic;
  
  signal write_raster : integer range 0 to 2 := 0;
  signal vsync_in_prev : std_logic := '0';
  signal hsync_in_prev : std_logic := '0';


  signal coeff0 : integer range 0 to 256 := 256;
  signal coeff1 : integer range 0 to 256 := 0;
  signal coeff2 : integer range 0 to 256 := 0;

  signal x_count : integer := 0;
  signal y_count : integer := 0;
  signal pal50_int : std_logic := '1';
  signal frame_start_toggle : std_logic := '0';
  signal last_frame_start_toggle : std_logic := '0';
  
begin

  rasterbufs: for i in 0 to 2 generate
    rastbuf0: entity work.ram32x1024 port map (
      clka => clock27,
      ena => '1',
      wea(0) => write_en(i),
      wea(1) => write_en(i),
      wea(2) => write_en(i),
      wea(3) => write_en(i),
      addra => std_logic_vector(write_addr),
      dina(7 downto 0) => std_logic_vector(red_in),
      dina(15 downto 8) => std_logic_vector(green_in),
      dina(23 downto 16) => std_logic_vector(blue_in),
      dina(31 downto 24) => (others => '0'),

      clkb => clock74p22,
      web => "0000",
      addrb => std_logic_vector(read_addr),
      dinb => (others => '0'),
      unsigned(doutb) => rdata(i)
      );
  end generate;
  
  process (clock27, clock74p22) is
  begin
    if rising_edge(clock27) then
      -- Tell fast side when a new frame starts
      write_en <= (others => '0');
      vsync_in_prev <= vsync_in;
      if vsync_in='0' and vsync_in_prev='1' then
        frame_start_toggle <= not frame_start_toggle;
        write_raster <= 0;
      end if;
      if hsync_in='0' and hsync_in_prev='1' then
        write_addr <= to_unsigned(0,10);
        if write_raster /= 2 then
          write_raster <= write_raster + 1;
        else
          write_raster <= 0;
        end if;
      elsif pixelvalid_in='1' then
        write_addr <= write_addr + 1;
        write_en(write_raster) <= '1';
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
      if y_count = 725 then
        vsync_up <= '1';
      end if;
      if y_count = 730 then
        vsync_up <= '0';
        pal50_int <= pal50_select;
      end if;
      if pal50_int='1' then
        if x_count < 1980 then
          x_count <= x_count + 1;
        else
          x_count <= 0;
          if y_count < 750 then
            y_count <= y_count + 1;
          else
            y_count <= 0;
          end if;
        end if;
        if x_count = 1720 then
          hsync_up <= '1';
        end if;
        if x_count = 1760 then
          hsync_up <= '0';
        end if;
      else
        if x_count < 1650 then
          x_count <= x_count + 1;
        else
          x_count <= 0;
          if y_count < 750 then
            y_count <= y_count + 1;
          else
            y_count <= 0;
          end if;
        end if;
        if x_count = 1390 then
          hsync_up <= '1';
        end if;
        if x_count = 1430 then
          hsync_up <= '0';
        end if;
      end if;
      if x_count < 1280 then
        pixelvalid_up <= '1';
      else
        pixelvalid_up <= '0';
      end if;
      if frame_start_toggle /= last_frame_start_toggle then
        -- Sync to input frame boundaries
        last_frame_start_toggle <= frame_start_toggle;
        if vlock_en='1' then
          y_count <= 724;
        end if;
      end if;
      if x_count < 280 then
        -- Left shoulder
        red_up <= (others => pal50_int); -- XXX DEBUG
        green_up <= (others => '0');
        blue_up <= (others => '0');
        read_addr <= to_unsigned(0,10);
      elsif (x_count < 1000) and (y_count < 720) then
        -- Work out which X position we need to read from the raster buffers
        read_addr <= to_unsigned(x_count - ((1280 - 720)/2),10);
        -- Active pixel: Do mix of the rasters
        red_up <= to_unsigned(to_integer(rdata(0)(7 downto 0)) * coeff0,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata(1)(7 downto 0)) * coeff1,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata(2)(7 downto 0)) * coeff2,16)(15 downto 8);
        green_up <= to_unsigned(to_integer(rdata(0)(15 downto 8)) * coeff0,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata(1)(15 downto 8)) * coeff1,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata(2)(15 downto 8)) * coeff2,16)(15 downto 8);
        blue_up <= to_unsigned(to_integer(rdata(0)(23 downto 16)) * coeff0,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata(1)(23 downto 16)) * coeff1,16)(15 downto 8)
                  + to_unsigned(to_integer(rdata(2)(23 downto 16)) * coeff2,16)(15 downto 8);
                  
      else
        -- Right shoulder / fly back        
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
           upscale_en) is
  begin
    if upscale_en='1' then red_out <= red_up; else red_out <= red_in; end if;
    if upscale_en='1' then green_out <= green_up; else green_out <= green_in; end if;
    if upscale_en='1' then blue_out <= blue_up; else blue_out <= blue_in; end if;
    if upscale_en='1' then hsync_out <= hsync_up; else hsync_out <= hsync_in; end if;
    if upscale_en='1' then vsync_out <= vsync_up; else vsync_out <= vsync_in; end if;
    if upscale_en='1' then pixelvalid_out <= pixelvalid_up; else pixelvalid_out <= pixelvalid_in; end if;
    
  end process;
  
end hundertwasser;
  
    
    
    
