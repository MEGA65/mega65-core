----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    22:30:37 12/10/2013 
-- Design Name: 
-- Module Name:    container - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;


-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity container is
  Port ( CLK_IN : STD_LOGIC;         
         btnCpuReset : in  STD_LOGIC;
--         irq : in  STD_LOGIC;
--         nmi : in  STD_LOGIC;
         
         ----------------------------------------------------------------------
         -- CIA1 ports for keyboard/joystick 
         ----------------------------------------------------------------------
--         porta_pins : inout  std_logic_vector(7 downto 0);
--         portb_pins : inout  std_logic_vector(7 downto 0);
         
         ----------------------------------------------------------------------
         -- VGA output
         ----------------------------------------------------------------------
         vsync : out STD_LOGIC;
         hsync : out  STD_LOGIC;
         vgared : buffer  UNSIGNED (3 downto 0);
         vgagreen : buffer  UNSIGNED (3 downto 0);
         vgablue : buffer  UNSIGNED (3 downto 0);

         ----------------------------------------------------------------------
         -- PS/2 keyboard interface
         ----------------------------------------------------------------------
         ps2clk : in std_logic;
         ps2data : in std_logic;

         jblo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jbhi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jalo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jahi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jdlo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jdhi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         jclo : inout std_logic_vector(4 downto 1) := (others => 'Z');
         jchi : inout std_logic_vector(10 downto 7) := (others => 'Z');
         
         ----------------------------------------------------------------------
         -- Debug interfaces on Nexys4 board
         ----------------------------------------------------------------------
         led : out std_logic_vector(15 downto 0) := (others => '1');
         sw : in std_logic_vector(15 downto 0);
         btn : in std_logic_vector(4 downto 0);

         UART_TXD : out std_logic := '1';
         RsRx : in std_logic;
         
         sseg_ca : out std_logic_vector(7 downto 0) := x"00";
         sseg_an : out std_logic_vector(7 downto 0) := x"00"
         );
end container;

architecture Behavioral of container is

  component fpgatemp is
    Generic ( DELAY_CYCLES : natural := 480 ); -- 10us @ 48 Mhz
    Port ( clk : in  STD_LOGIC;
           rst : in  STD_LOGIC;
           temp : out  STD_LOGIC_VECTOR (11 downto 0));
  end component;
  
  signal pixelclock : std_logic;
  signal cpuclock : std_logic;
  signal clock200 : std_logic;
  signal clock40 : std_logic;
  signal clock33 : std_logic;
  signal clock30 : std_logic;

  signal hsync_i : std_logic := '0';
  signal vsync_i : std_logic := '0';
  signal hsync_o : std_logic := '0';
  signal vsync_o : std_logic := '0';
  signal oof_i : std_logic := '0';
  signal oof_o : std_logic := '0';
  
  signal segled_counter : unsigned(31 downto 0) := (others => '0');

  signal lcd_clk_i : std_logic;
  signal lcd_clk_o : std_logic;
  signal lcd_hsync_i : std_logic;
  signal lcd_hsync : std_logic;
  signal lcd_vsync_i : std_logic;
  signal lcd_vsync : std_logic;
  signal lcd_de_i : std_logic;
  signal lcd_de_o : std_logic;
  signal lcd_pwm : std_logic;

  signal hsync_pal50 : std_logic;
  signal vsync_pal50 : std_logic;
  signal inframe_pal50 : std_logic;
  signal lcd_vsync_pal50 : std_logic;
  signal lcd_inframe_pal50 : std_logic;

  signal hsync_ntsc60 : std_logic;
  signal vsync_ntsc60 : std_logic;
  signal inframe_ntsc60 : std_logic;  
  signal lcd_vsync_ntsc60 : std_logic;
  signal lcd_inframe_ntsc60 : std_logic;  
  
  signal red_i : unsigned(7 downto 0);
  signal green_i : unsigned(7 downto 0);
  signal blue_i : unsigned(7 downto 0);

  signal red_n : unsigned(7 downto 0);
  signal green_n : unsigned(7 downto 0);
  signal blue_n : unsigned(7 downto 0);

  signal red_p : unsigned(7 downto 0);
  signal green_p : unsigned(7 downto 0);
  signal blue_p : unsigned(7 downto 0);
  
  signal red_o : unsigned(7 downto 0);
  signal green_o : unsigned(7 downto 0);
  signal blue_o : unsigned(7 downto 0);

  signal pwm_brightness : unsigned(7 downto 0) := x"FF";
  signal pwm_comparison : unsigned(7 downto 0) := x"FF";
  signal pwm_divisor_counter : integer := 0;
  -- 1KHz * 256 values of brightness
  constant pwm_divisor : integer := 100000000 / (1000 * 256);

  signal x_zero50 : std_logic := '0';
  signal last_x_zero50 : std_logic := '0';
  signal x_counter : integer := 0;
  signal x_counter_max : integer := 0;
  signal pix100 : std_logic_vector(2 downto 0) := "000";
  
begin

  dotclock1: entity work.dotclock100
    port map ( clk_in1 => CLK_IN,
               clock100 => pixelclock, -- 100MHz
               clock50 => cpuclock, -- 50MHz
               clock40 => clock40,
               clock33 => clock33,
               clock30 => clock30,
               clock200 => clock200
               );

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
               hsync => hsync_pal50,
               vsync => vsync_pal50,
               inframe => inframe_pal50,
               x_zero => x_zero50,
               lcd_vsync => lcd_vsync_pal50,
               lcd_inframe => lcd_inframe_pal50,

               -- Get test pattern
               red_o => red_p,
               green_o => green_p,
               blue_o => blue_p
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
               hsync => hsync_ntsc60,
               vsync => vsync_ntsc60,
               inframe => inframe_ntsc60,
               lcd_vsync => lcd_vsync_ntsc60,
               lcd_inframe => lcd_inframe_ntsc60,

               -- Get test pattern
               red_o => red_n,
               green_o => green_n,
               blue_o => blue_n
               );               
  
  pixel0: entity work.pixel_driver
    port map (
      pixelclock_select => sw(7 downto 0),
      
      clock200 => clock200,
      clock100 => pixelclock,
      clock50 => cpuclock,
      clock40 => clock40,
      clock33 => clock33,
      clock30 => clock30,

      red_i => red_i,
      green_i => green_i,
      blue_i => blue_i,

      red_o => red_o,
      green_o => green_o,
      blue_o => blue_o,

      hsync_i => hsync_i,
      hsync_o => hsync_o,
      vsync_i => vsync_i,
      vsync_o => vsync_o,

      lcd_hsync_i => lcd_hsync_i,
      lcd_hsync_o => lcd_hsync,
      lcd_vsync_i => lcd_vsync_i,
      lcd_vsync_o => lcd_vsync,

      viciv_outofframe_i => oof_i,
      viciv_outofframe_o => oof_o,
      
      lcd_display_enable_i => lcd_de_i,
      lcd_display_enable_o => lcd_de_o,

      lcd_pixel_strobe_i => lcd_clk_i,
      lcd_pixel_strobe_o => lcd_clk_o

      );

  process (sw(14), pix100, red_o, green_o, blue_o) is
  begin
    if sw(14)='0' then
      vgared <= red_o(7 downto 4);
      vgagreen <= green_o(7 downto 4);
      vgablue <= blue_o(7 downto 4);
      jalo <= std_logic_vector(blue_o(7 downto 4));
      jahi <= std_logic_vector(red_o(7 downto 4));
      jblo <= std_logic_vector(green_o(7 downto 4));
    else
      for i in 0 to 3 loop
        vgared(i) <= pix100(2);
        vgagreen(i) <= pix100(2);
        vgablue(i) <= pix100(2);
        jalo <= pix100(2) &pix100(2) &pix100(2) &pix100(2);
        jahi <= pix100(2) &pix100(2) &pix100(2) &pix100(2);
        jblo <= pix100(2) &pix100(2) &pix100(2) &pix100(2);
      end loop;
    end if;
  end process;
  
  hsync <= hsync_o;
  vsync <= vsync_o;
  
  jbhi(7) <= lcd_clk_o;
  jbhi(8) <= lcd_hsync;
  jbhi(9) <= lcd_vsync;
  jbhi(10) <= lcd_de_o;
  jclo(1) <= lcd_pwm;

  process (pixelclock)
  begin
    if rising_edge (pixelclock) then
      last_x_zero50 <= x_zero50;
      if x_zero50 = '1' and last_x_zero50 = '0' then
        x_counter_max <= 1;
        x_counter <= 0;
      else
        if x_counter = x_counter_max then
          x_counter_max <= x_counter_max + 1;
          x_counter <= 0;
          pix100 <= "111";
        else
          x_counter <= x_counter + 1;
          pix100(2 downto 1) <= pix100(1 downto 0);
          pix100(0) <= '0';
        end if;
      end if;
    end if;
  end process;
  
  process (cpuclock)
  begin

    if sw(15)='1' then
      hsync_i <= hsync_pal50;
      vsync_i <= not vsync_pal50;
      lcd_hsync_i <= hsync_pal50;
      lcd_vsync_i <= not lcd_vsync_pal50;
      lcd_de_i <= lcd_inframe_pal50;
      lcd_clk_i <= clock30;
      red_i <= red_p;
      green_i <= green_p;
      blue_i <= blue_p;
    else
      hsync_i <= hsync_ntsc60;
      vsync_i <= vsync_ntsc60;
      lcd_hsync_i <= hsync_ntsc60;
      lcd_vsync_i <= lcd_vsync_ntsc60;
      lcd_de_i <= lcd_inframe_ntsc60;
      lcd_clk_i <= clock40;
      red_i <= red_n;
      green_i <= green_n;
      blue_i <= blue_n;
    end if;
    
    if rising_edge(cpuclock) then
      pwm_brightness <= unsigned(sw(12 downto 5));
      if pwm_divisor_counter < pwm_divisor then
        pwm_divisor_counter <= pwm_divisor_counter + 1;
      else
        pwm_divisor_counter <= 0;
        if pwm_comparison /= x"FF" then
          pwm_comparison <= pwm_comparison + 1;
          if pwm_comparison = pwm_brightness then
            lcd_pwm <= '0';
          end if;
        else
          pwm_comparison <= x"00";
          lcd_pwm <= '1';
        end if;
      end if;
    end if;
  end process;
      
end Behavioral;
