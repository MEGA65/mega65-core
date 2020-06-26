----------------------------------------------------------------------------------
-- Engineer: Mike Field <hamster@snap.net.nz>
-- 
-- Description: dvid_test 
--  Top level design for testing my DVI-D interface
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
Library UNISIM;
use UNISIM.vcomponents.all;

entity dvid_test is
  Port ( clk_in  : in  STD_LOGIC;
         led : out std_logic_vector(7 downto 0);
         dip_sw : in std_logic_vector(7 downto 0);
         p13 : inout std_logic_vector(39 downto 0) := (others => 'Z');
         data_p    : out  STD_LOGIC_VECTOR(2 downto 0);
         data_n    : out  STD_LOGIC_VECTOR(2 downto 0);
         clk_p          : out    std_logic;
         clk_n          : out    std_logic;
         reset : in std_logic;
         left : in std_logic;
         sample_rdata : in std_logic_vector(15 downto 0);
         clock27 : out std_logic
       );
         
end dvid_test;

architecture Behavioral of dvid_test is

   signal clock27_int    : std_logic := '0';
   signal clock41    : std_logic := '0';
   signal clock50    : std_logic := '0';
   signal clock81    : std_logic := '0';
   signal clock100   : std_logic := '0';
   signal clock135p  : std_logic := '0';
   signal clock135n  : std_logic := '0';
   signal clock162   : std_logic := '0';
   signal clock324   : std_logic := '0';

   signal red     : std_logic_vector(7 downto 0) := (others => '0');
   signal green   : std_logic_vector(7 downto 0) := (others => '0');
   signal blue    : std_logic_vector(7 downto 0) := (others => '0');
   signal hsync   : std_logic := '0';
   signal vsync   : std_logic := '0';
   signal blank   : std_logic := '0';
   signal red_s   : std_logic_vector(0 downto 0);
   signal green_s : std_logic_vector(0 downto 0);
   signal blue_s  : std_logic_vector(0 downto 0);
   signal clock_s : std_logic_vector(0 downto 0);

   signal audio_l : std_logic_vector(15 downto 0) := x"0000";
   signal audio_r : std_logic_vector(15 downto 0) := x"0000";

   signal counter : integer := 0;

   signal audio_counter : integer := 0;
   signal sine_repeat : integer := 0;
   signal audio_address : integer := 0;
   signal audio_data : std_logic_vector(7 downto 0) := x"00";
   signal sample_rdata_drive : std_logic_vector(15 downto 0) := x"0000";
   
   signal sample_ready : boolean := false;

   constant clock_frequency : integer := 27000000;
   constant target_sample_rate : integer := 48000;
   constant sine_table_length : integer := 36;
   signal sine_repeat_interval : unsigned(23 downto 0) := to_unsigned((target_sample_rate/sine_table_length)/200,24);
   signal audio_counter_interval : unsigned(23 downto 0) := to_unsigned(clock_frequency/target_sample_rate,24);
   signal sample_mask : std_logic_vector(7 downto 0) := x"80";
   
   type sine_t is array (0 to 8) of unsigned(7 downto 0);
   signal sine_table : sine_t := (
     0 => to_unsigned(0,8),
     1 => to_unsigned(22,8),
     2 => to_unsigned(43,8),
     3 => to_unsigned(64,8),
     4 => to_unsigned(82,8),
     5 => to_unsigned(98,8),
     6 => to_unsigned(110,8),
     7 => to_unsigned(120,8),
     8 => to_unsigned(126,8)
     );

   type hex_t is array ( 0 to 15) of unsigned(7 downto 0);
   signal hex_table : hex_t := (
     0 => x"30",  1 => x"31",  2 => x"32",   3 => x"33",
     4 => x"34",  5 => x"35",  6 => x"36",   7 => x"37",
     8 => x"38",  9 => x"39", 10 => x"41",  11 => x"42",
     12 => x"43", 13 => x"44", 14 => x"45",  15 => x"46"
     );
   
   signal uart_tx_ready : std_logic := '0';
   signal uart_tx_byte : unsigned(7 downto 0) := x"00";
   signal uart_trigger : std_logic := '0';
   signal report_phase : integer := 0;
   
begin
   
   
clocking_inst : entity work.clocking50mhz port map (
      clk_in   => clk_in,
      -- Clock out ports
      clock27 => clock27_int,
      clock41 => clock41,
      clock50 => clock50,
      clock81p => clock81,
      clock100 => clock100,
      clock135p => clock135p,
      clock135n => clock135n,
      clock162 => clock162,
      clock324 => clock324
    );

Inst_dvid: entity work.dvid PORT MAP(
      clk       => clock135p,
      clk_n     => clock135n, 
      clk_pixel => clock27_int,
      clk_pixel_en => true,
      
      red_p     => red,
      green_p   => green,
      blue_p    => blue,
      blank     => blank,
      hsync     => hsync,
      vsync     => vsync,

      EnhancedMode => true,
      IsProgressive => true,
      IsPAL => true,
      Is30kHz => true,
      Limited_Range => true,
      Widescreen => false,

      HDMI_audio_L => audio_L,
      HDMI_audio_R => audio_R,
      HDMI_LeftEnable => sample_ready,
      HDMI_RightEnable => sample_ready,
      
      -- outputs to TMDS drivers
      red_s     => red_s,
      green_s   => green_s,
      blue_s    => blue_s,
      clock_s   => clock_s
   );
   
OBUFDS_blue  : OBUFDS port map ( O  => data_p(0), OB => data_n(0), I  => blue_s(0)  );
OBUFDS_red   : OBUFDS port map ( O  => data_p(1), OB => data_n(1), I  => green_s(0) );
OBUFDS_green : OBUFDS port map ( O  => data_p(2), OB => data_n(2), I  => red_s(0)   );
OBUFDS_clock : OBUFDS port map ( O  => CLK_P, OB => CLK_N, I  => clock_s(0) );

pixeldriver0: entity work.pixel_driver port map (
  cpuclock => clock41,
  clock81 => clock81,
  clock27 => clock27_int,

  pal50_select => dip_sw(1),
  vga60_select => '0',
  test_pattern_enable => '1',
  hsync_invert => '0',
  vsync_invert => '0',

  red_i => to_unsigned(0,8),
  green_i => to_unsigned(0,8),
  blue_i => to_unsigned(0,8),

  std_logic_vector(red_o) => red,
  std_logic_vector(green_o) => green,
  std_logic_vector(blue_o) => blue,
  vga_hsync => hsync,
  vsync => vsync,
  vga_blank   => blank

  );

  tx0: entity work.UART_TX_CTRL
  port map ( SEND => uart_trigger,
             BIT_TMR_MAX => to_unsigned(clock_frequency/2000000,16),
             DATA => uart_tx_byte,
             CLK => clk_in,
             READY => uart_tx_ready,
             UART_TX => P13(0)
             );

process (clock27_int) is
begin

  clock27 <= clock27_int;
  
  if rising_edge(clock27_int) then

    if audio_address < 9 then
      audio_data <= std_logic_vector(sine_table(audio_address) + 128);
    elsif audio_address < 18 then
      audio_data <= std_logic_vector(sine_table(8 - (audio_address - 9)) + 128);
    elsif audio_address < 27 then
      audio_data <= std_logic_vector(128 - sine_table(audio_address - 18));
    elsif audio_address < 36 then
      audio_data <= std_logic_vector(128 - sine_table(8 - (audio_address - 27)));
    else
      audio_data <= x"80";
    end if;

    sample_mask <= dip_sw;
    sample_rdata_drive <= sample_rdata;
    
    uart_trigger <= '0';

    -- Strobe sample_ready at 48KHz
    if audio_counter /= to_integer(audio_counter_interval) then
      audio_counter <= audio_counter + 1;
      sample_ready <= false;
    else
      audio_counter <= 0;
      sample_ready <= true;

      audio_l <= (others => '0');
      audio_r <= (others => '0');
      led <= (others => '0');
      if dip_sw(0)='1' then
        if left='1' then
          audio_l(15 downto 8) <= sample_rdata_drive(15 downto 8); -- and sample_mask;
          audio_l(7 downto 0) <= sample_rdata_drive(7 downto 0); -- and sample_mask;
        else
          audio_r(15 downto 8) <= sample_rdata_drive(15 downto 8); -- and sample_mask;
          audio_r(7 downto 0) <= sample_rdata_drive(7 downto 0); -- and sample_mask;
        end if;
        led <= sample_rdata_drive(15 downto 8) and sample_mask;
      else
        audio_l(12 downto 5) <= audio_data; -- and sample_mask;
        audio_r(12 downto 5) <= audio_data; -- and sample_mask;
        led <= audio_data; -- and sample_mask;
      end if;

      if sine_repeat /= to_integer(sine_repeat_interval) then
        sine_repeat <= sine_repeat + 1;
      else
        sine_repeat <= 0;
        if audio_address /= 35 then
          audio_address <= audio_address + 1;          
        else
          audio_address <= 0;
        end if;
      end if;

      -- Also update display
      if report_phase /= 99 then
        report_phase <= report_phase + 1;
      else
        report_phase <= 0;
      end if;
      uart_trigger <= '1';
      case report_phase is
        when  0 => uart_tx_byte <= x"0d";

        -- Sample mask $xx
        when  1 => uart_tx_byte <= x"53";
        when  2 => uart_tx_byte <= x"61";
        when  3 => uart_tx_byte <= x"6d";
        when  4 => uart_tx_byte <= x"70";
        when  5 => uart_tx_byte <= x"6c";
        when  6 => uart_tx_byte <= x"65";
        when  7 => uart_tx_byte <= x"20";
        when  8 => uart_tx_byte <= x"6d";
        when  9 => uart_tx_byte <= x"61";
        when 10 => uart_tx_byte <= x"73";
        when 11 => uart_tx_byte <= x"6b";
        when 12 => uart_tx_byte <= x"20";
        when 13 => uart_tx_byte <= x"24";
        when 14 => uart_tx_byte <= hex_table(to_integer(unsigned(sample_mask(7 downto 4))));
        when 15 => uart_tx_byte <= hex_table(to_integer(unsigned(sample_mask(3 downto 0))));
                   
        -- 
                   
        when others => uart_tx_byte <= x"00";
      end case;
      
      
      
    end if;
    
  end if;
end process;


end Behavioral;
