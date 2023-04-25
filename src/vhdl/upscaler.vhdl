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
    reg_in : in unsigned(7 downto 0) := x"00";
    hold_image : in std_logic;
    
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

  signal raster_leap_cycle : integer range 0 to 1 := 0;
  signal frame_leap_cycle : integer range 0 to 1 := 0;

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
  signal first_read_raster_ntsc : integer range 0 to 3 := 1;

  signal ntsc_coarse : unsigned(8 downto 0) := to_unsigned(285,9);
  signal ntsc_fine : unsigned(11 downto 0) := to_unsigned(3180,12);

  signal pal_coarse : unsigned(9 downto 0) := to_unsigneD(391,10);
  signal pal_fine : unsigned(7 downto 0) := to_unsigned(21,8);

  -- 2^16 x rasters in / rasters out
  -- PAL in = 625, NTSC in = 526, rasters out = 750
  -- 625/750 x 2^16 = 54613.333
  -- 526/750 x 2^16 = 45962.581
  signal raster_phase_add_pal : unsigned(15 downto 0) := to_unsigned(54613,16);
  signal raster_phase_add_ntsc : unsigned(15 downto 0) := to_unsigned(45962,16);

  constant config_width : integer := 2+2+9+12+10+8+16+16;
  signal config_vector : unsigned(config_width downto 0) := (others => '0');
  signal config_bit : std_logic := '0';
  signal config_bit_num : integer := 0;
  
  signal upscale_en_74 : std_logic;
  signal pal50_select_74 : std_logic;
  signal vlock_en_74 : std_logic;
  signal frame_start_toggle_74 : std_logic;
  signal raster_0_writing_74 : std_logic;
  signal reg_in_74 : unsigned(7 downto 0) := x"00";
  signal last_reg_in_74 : unsigned(7 downto 0) := x"00";

  signal reading_raster_0 : std_logic;
  
  signal zero : std_logic := '0';
  signal zerov : std_logic_vector(0 downto 0) := (others => '0');

  signal raster_buf_active : std_logic_vector(3 downto 0) := "0000";
  
begin

  reg_in_cdc: for i in 0 to 7 generate
    regcdc0: xpm_cdc_single
    port map (
        src_in => reg_in(i),
        src_clk => clock27,
        dest_clk => clock74p22,
        dest_out => reg_in_74(i)
    );
  end generate;
  
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
        if x_count < (1980-2+raster_leap_cycle) then
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
          -- Add one cycle to every 209/750 rasters = 143/512 rasters,
          -- provided we reset the ntsc_raster_counter every frame
          if vlock_en_74='1' then
            -- XXX Except it is too many cycles per frame.
            -- 142 gets us much closer, with upper rasters creeping down about
            -- 1 per 30 seconds (line draws right to left)
            -- With 143 the line draws left to right at a similar rate.
            -- So we might need to add ~1/2 pixel per frame in the frame 1141/4096
            -- to make it ~1141+2048/4096 = 3189/4096.
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
                        
            ntsc_raster_counter <= to_unsigned(0,11);
            if vlock_en_74='1' then
              -- Add one cycle for every 1,141 / 4,096 frames
              -- See above: Trying 3189/4096 instead
              ntsc_frame_counter_1141 <= ntsc_frame_counter_1141 + to_integer(ntsc_fine);
              if ntsc_frame_counter_1141(12) /= last_ntsc_frame_counter then
                frame_leap_cycle <= 1;
                last_ntsc_frame_counter <= last_ntsc_frame_counter;
              end if;
              if ntsc_frame_counter < 2619 then
                ntsc_frame_counter <= ntsc_frame_counter + 1;                
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
        red_up <= (others => raster_0_writing_74);
        green_up <= (others => reading_raster_0);
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

        -- Show config bits and currently selected config register
        if (x_count < 1280 and y_count < 720) then
          red_up <= (others => config_bit);
        end if;        
        if config_bit_num = to_integer(reg_in_74(7 downto 1)) then
          if (y_count > 95 and y_count < 101) or (y_count >107 and y_count < 115) then
            green_up <= (others => '1');
          end if;
        end if;
      end if;      

      -- Show current config in right shoulder for debugging
      config_vector(1 downto 0) <= to_unsigned(first_read_raster_pal,2);
      config_vector(3 downto 2) <= to_unsigned(first_read_raster_ntsc,2);
      config_vector(12 downto 4) <= ntsc_coarse;
      config_vector(24 downto 13) <= ntsc_fine;
      config_vector(34 downto 25) <= pal_coarse;
      config_vector(42 downto 35) <= pal_fine;
      config_vector(58 downto 43) <= raster_phase_add_ntsc;
      config_vector(74 downto 59) <= raster_phase_add_pal;
      if (y_count >100 and y_count < 108) and (x_count>1000 and x_count < (1000 + (config_width*4))) then
        -- config_bit_num advances every 2 X pixels
        config_bit_num <= to_integer(to_unsigned((x_count - 1010),12)(11 downto 1));
      else
        config_bit_num <= config_width - 1;
        config_vector(config_width - 1) <= '0';
      end if;
      config_bit <= config_vector(config_bit_num);
      
      
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

      last_reg_in_74 <= reg_in_74;
      if last_reg_in_74 = reg_in_74 then
        -- Stable value on reg_in_74 after CDC
        case reg_in_74(7 downto 2) is
          when "000001" => first_read_raster_pal <= to_integer(reg_in_74(1 downto 0));
          when "000010" => first_read_raster_ntsc <= to_integer(reg_in_74(1 downto 0));
          when "000011" => ntsc_coarse(1 downto 0) <= reg_in_74(1 downto 0);
          when "000100" => ntsc_coarse(3 downto 2) <= reg_in_74(1 downto 0);
          when "000101" => ntsc_coarse(5 downto 4) <= reg_in_74(1 downto 0);
          when "000110" => ntsc_coarse(7 downto 6) <= reg_in_74(1 downto 0);
          when "000111" => ntsc_coarse(8) <= reg_in_74(0);
          when "001000" => pal_coarse(1 downto 0) <= reg_in_74(1 downto 0);
          when "001001" => pal_coarse(3 downto 2) <= reg_in_74(1 downto 0);
          when "001010" => pal_coarse(5 downto 4) <= reg_in_74(1 downto 0);
          when "001011" => pal_coarse(7 downto 6) <= reg_in_74(1 downto 0);
          when "001100" => pal_coarse(9 downto 8) <= reg_in_74(1 downto 0);
          when "001101" => ntsc_fine(1 downto 0) <= reg_in_74(1 downto 0);
          when "001110" => ntsc_fine(3 downto 2) <= reg_in_74(1 downto 0);
          when "001111" => ntsc_fine(5 downto 4) <= reg_in_74(1 downto 0);
          when "010000" => ntsc_fine(7 downto 6) <= reg_in_74(1 downto 0);
          when "010010" => ntsc_fine(11 downto 10) <= reg_in_74(1 downto 0);
          when "010011" => pal_fine(1 downto 0) <= reg_in_74(1 downto 0);
          when "010100" => pal_fine(3 downto 2) <= reg_in_74(1 downto 0);
          when "010101" => pal_fine(5 downto 4) <= reg_in_74(1 downto 0);
          when "010110" => pal_fine(7 downto 6) <= reg_in_74(1 downto 0);
          when "011001" => raster_phase_add_pal(1 downto 0) <= reg_in_74(1 downto 0);
          when "011010" => raster_phase_add_pal(3 downto 2) <= reg_in_74(1 downto 0);
          when "011011" => raster_phase_add_pal(5 downto 4) <= reg_in_74(1 downto 0);
          when "011100" => raster_phase_add_pal(7 downto 6) <= reg_in_74(1 downto 0);
          when "011101" => raster_phase_add_pal(9 downto 8) <= reg_in_74(1 downto 0);
          when "011110" => raster_phase_add_pal(11 downto 10) <= reg_in_74(1 downto 0);
          when "011111" => raster_phase_add_pal(13 downto 12) <= reg_in_74(1 downto 0);
          when "100000" => raster_phase_add_pal(15 downto 14) <= reg_in_74(1 downto 0);
          when "100001" => raster_phase_add_ntsc(1 downto 0) <= reg_in_74(1 downto 0);
          when "100010" => raster_phase_add_ntsc(3 downto 2) <= reg_in_74(1 downto 0);
          when "100011" => raster_phase_add_ntsc(5 downto 4) <= reg_in_74(1 downto 0);
          when "100100" => raster_phase_add_ntsc(7 downto 6) <= reg_in_74(1 downto 0);
          when "100101" => raster_phase_add_ntsc(9 downto 8) <= reg_in_74(1 downto 0);
          when "100110" => raster_phase_add_ntsc(11 downto 10) <= reg_in_74(1 downto 0);
          when "100111" => raster_phase_add_ntsc(13 downto 12) <= reg_in_74(1 downto 0);
          when "101000" => raster_phase_add_ntsc(15 downto 14) <= reg_in_74(1 downto 0);
          when others => null;
        end case;
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
  
    
    
    