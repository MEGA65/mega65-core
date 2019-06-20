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
--         btnCpuReset : in  STD_LOGIC;
--         irq : in  STD_LOGIC;
--         nmi : in  STD_LOGIC;

         fpga_pins : out std_logic_vector(1 to 100) := (others => '1');
         
         ----------------------------------------------------------------------
         -- HyperRAM as expansion RAM
         ----------------------------------------------------------------------
         hr_d : inout unsigned(7 downto 0) := (others => '1');
         hr_rwds : inout std_logic := '1';
         hr_reset : out std_logic := '1';
         hr_clk_n : out std_logic := '1';
         hr_clk_p : out std_logic := '1';
         hr_cs0 : out std_logic := '1';
         hr_cs1 : out std_logic := '1';
         
         ----------------------------------------------------------------------
         -- Flash RAM for holding config
         ----------------------------------------------------------------------
--         QspiSCK : out std_logic := '1';
         QspiDB : inout std_logic_vector(3 downto 0) := (others => 'Z');
         QspiCSn : out std_logic := '1';
         
         ----------------------------------------------------------------------
         -- Debug interfaces on TE0725
         ----------------------------------------------------------------------
         led : inout std_logic := '1';

         ----------------------------------------------------------------------
         -- UART monitor interface
         ----------------------------------------------------------------------
         monitor_tx : out std_logic := '1';
         monitor_rx : in std_logic
         
         );
end container;

architecture Behavioral of container is
  
  component fpgatemp is
    Generic ( DELAY_CYCLES : natural := 480 ); -- 10us @ 48 Mhz
    Port ( clk : in  STD_LOGIC;
           rst : in  STD_LOGIC;
           temp : out  STD_LOGIC_VECTOR (11 downto 0));
  end component;

  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';
  signal restore_key : std_logic := '1';
  signal reset_out : std_logic := '1';
  signal cpu_game : std_logic := '1';
  signal cpu_exrom : std_logic := '1';
  
  
  signal pixelclock : std_logic;
  signal cpuclock : std_logic;
  signal clock240 : std_logic;
  signal clock120 : std_logic;
  signal clock100 : std_logic;
  signal ethclock : std_logic;
  signal clock200 : std_logic;

  signal i2s_master_clk_int : std_logic := '0';
  signal i2s_master_clk : std_logic := '0';
  signal i2s_sync : std_logic := '0';
  signal i2s_sync_int : std_logic := '0';
  signal sample : unsigned(15 downto 0) := x"0001";
  signal table_offset : integer range 0 to 255 := 0;
  signal table_dir : std_logic := '1';
  signal table_neg : std_logic := '0';
  signal divisor : integer := 0;
  constant divisor_max : integer := 40000000/(256*4)/1;  -- proceed it really slowly

  constant max_table_value: integer := 255;
  subtype table_value_type is integer range 0 to 255;

  constant max_table_index: integer := 255;
  subtype table_index_type is integer range 0 to 255;

  subtype sine_vector_type is std_logic_vector( 8 downto 0 );

begin
  
  gen_pin1:
  for i in 1 to 70 generate
      pin1: entity work.pin_id
        port map (
          clock => pixelclock,
          pin_number => to_unsigned(i,8),
          pin => fpga_pins(i)
          );
  end generate gen_pin1;
  gen_pin2:
  for i in 75 to 100 generate
      pin2: entity work.pin_id
        port map (
          clock => pixelclock,
          pin_number => to_unsigned(i,8),
          pin => fpga_pins(i)
          );
  end generate gen_pin2;

  i2sclock2: entity work.i2s_clock
    generic map (
      -- Modems and some other peripherals only need 8KHz,
      sample_rate => 44100
      )
    port map (
      clock50mhz => ethclock,
      i2s_clk => i2s_master_clk_int,
      i2s_sync => i2s_sync_int);
  
  -- I2S master for stereo speakers
  i2s4: entity work.i2s_transceiver port map (
    clock50mhz => ethclock,
    i2s_clk => i2s_master_clk_int,
    i2s_sync => i2s_sync_int,
    pcm_out => fpga_pins(71),
    pcm_in => '0',
    tx_sample_left => sample,
    tx_sample_right => sample
    );

  fpga_pins(74) <= i2s_master_clk;
  fpga_pins(72) <= i2s_sync;
  
  dotclock1: entity work.dotclock100
    port map ( clk_in1 => CLK_IN,
               clock80 => pixelclock, -- 80MHz
               clock40 => cpuclock, -- 40MHz
               clock50 => ethclock,
               clock200 => clock200,
               clock100 => clock100,
               clock120 => clock120,
               clock240 => clock240
               );

  -- Update sample value
  process(ethclock)
    function get_table_value (table_index: table_index_type) return table_value_type is
      variable table_value: table_value_type;
    begin
      case table_index is
        when 0 =>
          table_value := 1;
        when 1 =>
          table_value := 2;
        when 2 =>
          table_value := 4;
        when 3 =>
          table_value := 5;
        when 4 =>
          table_value := 7;
        when 5 =>
          table_value := 9;
        when 6 =>
          table_value := 10;
        when 7 =>
          table_value := 12;
        when 8 =>
          table_value := 13;
        when 9 =>
          table_value := 15;
        when 10 =>
          table_value := 16;
        when 11 =>
          table_value := 18;
        when 12 =>
          table_value := 20;
        when 13 =>
          table_value := 21;
        when 14 =>
          table_value := 23;
        when 15 =>
          table_value := 24;
        when 16 =>
          table_value := 26;
        when 17 =>
          table_value := 27;
        when 18 =>
          table_value := 29;
        when 19 =>
          table_value := 30;
        when 20 =>
          table_value := 32;
        when 21 =>
          table_value := 34;
        when 22 =>
          table_value := 35;
        when 23 =>
          table_value := 37;
        when 24 =>
          table_value := 38;
        when 25 =>
          table_value := 40;
        when 26 =>
          table_value := 41;
        when 27 =>
          table_value := 43;
        when 28 =>
          table_value := 44;
        when 29 =>
          table_value := 46;
        when 30 =>
          table_value := 47;
        when 31 =>
          table_value := 49;
        when 32 =>
          table_value := 51;
        when 33 =>
          table_value := 52;
        when 34 =>
          table_value := 54;
        when 35 =>
          table_value := 55;
        when 36 =>
          table_value := 57;
        when 37 =>
          table_value := 58;
        when 38 =>
          table_value := 60;
        when 39 =>
          table_value := 61;
        when 40 =>
          table_value := 63;
        when 41 =>
          table_value := 64;
        when 42 =>
          table_value := 66;
        when 43 =>
          table_value := 67;
        when 44 =>
          table_value := 69;
        when 45 =>
          table_value := 70;
        when 46 =>
          table_value := 72;
        when 47 =>
          table_value := 73;
        when 48 =>
          table_value := 75;
        when 49 =>
          table_value := 76;
        when 50 =>
          table_value := 78;
        when 51 =>
          table_value := 79;
        when 52 =>
          table_value := 81;
        when 53 =>
          table_value := 82;
        when 54 =>
          table_value := 84;
        when 55 =>
          table_value := 85;
        when 56 =>
          table_value := 87;
        when 57 =>
          table_value := 88;
        when 58 =>
          table_value := 90;
        when 59 =>
          table_value := 91;
        when 60 =>
          table_value := 93;
        when 61 =>
          table_value := 94;
        when 62 =>
          table_value := 95;
        when 63 =>
          table_value := 97;
        when 64 =>
          table_value := 98;
        when 65 =>
          table_value := 100;
        when 66 =>
          table_value := 101;
        when 67 =>
          table_value := 103;
        when 68 =>
          table_value := 104;
        when 69 =>
          table_value := 105;
        when 70 =>
          table_value := 107;
        when 71 =>
          table_value := 108;
        when 72 =>
          table_value := 110;
        when 73 =>
          table_value := 111;
        when 74 =>
          table_value := 113;
        when 75 =>
          table_value := 114;
        when 76 =>
          table_value := 115;
        when 77 =>
          table_value := 117;
        when 78 =>
          table_value := 118;
        when 79 =>
          table_value := 120;
        when 80 =>
          table_value := 121;
        when 81 =>
          table_value := 122;
        when 82 =>
          table_value := 124;
        when 83 =>
          table_value := 125;
        when 84 =>
          table_value := 126;
        when 85 =>
          table_value := 128;
        when 86 =>
          table_value := 129;
        when 87 =>
          table_value := 130;
        when 88 =>
          table_value := 132;
        when 89 =>
          table_value := 133;
        when 90 =>
          table_value := 134;
        when 91 =>
          table_value := 136;
        when 92 =>
          table_value := 137;
        when 93 =>
          table_value := 138;
        when 94 =>
          table_value := 140;
        when 95 =>
          table_value := 141;
        when 96 =>
          table_value := 142;
        when 97 =>
          table_value := 144;
        when 98 =>
          table_value := 145;
        when 99 =>
          table_value := 146;
        when 100 =>
          table_value := 147;
        when 101 =>
          table_value := 149;
        when 102 =>
          table_value := 150;
        when 103 =>
          table_value := 151;
        when 104 =>
          table_value := 153;
        when 105 =>
          table_value := 154;
        when 106 =>
          table_value := 155;
        when 107 =>
          table_value := 156;
        when 108 =>
          table_value := 158;
        when 109 =>
          table_value := 159;
        when 110 =>
          table_value := 160;
        when 111 =>
          table_value := 161;
        when 112 =>
          table_value := 162;
        when 113 =>
          table_value := 164;
        when 114 =>
          table_value := 165;
        when 115 =>
          table_value := 166;
        when 116 =>
          table_value := 167;
        when 117 =>
          table_value := 168;
        when 118 =>
          table_value := 170;
        when 119 =>
          table_value := 171;
        when 120 =>
          table_value := 172;
        when 121 =>
          table_value := 173;
        when 122 =>
          table_value := 174;
        when 123 =>
          table_value := 175;
        when 124 =>
          table_value := 176;
        when 125 =>
          table_value := 178;
        when 126 =>
          table_value := 179;
        when 127 =>
          table_value := 180;
        when 128 =>
          table_value := 181;
        when 129 =>
          table_value := 182;
        when 130 =>
          table_value := 183;
        when 131 =>
          table_value := 184;
        when 132 =>
          table_value := 185;
        when 133 =>
          table_value := 186;
        when 134 =>
          table_value := 187;
        when 135 =>
          table_value := 188;
        when 136 =>
          table_value := 189;
        when 137 =>
          table_value := 191;
        when 138 =>
          table_value := 192;
        when 139 =>
          table_value := 193;
        when 140 =>
          table_value := 194;
        when 141 =>
          table_value := 195;
        when 142 =>
          table_value := 196;
        when 143 =>
          table_value := 197;
        when 144 =>
          table_value := 198;
        when 145 =>
          table_value := 199;
        when 146 =>
          table_value := 200;
        when 147 =>
          table_value := 201;
        when 148 =>
          table_value := 202;
        when 149 =>
          table_value := 202;
        when 150 =>
          table_value := 203;
        when 151 =>
          table_value := 204;
        when 152 =>
          table_value := 205;
        when 153 =>
          table_value := 206;
        when 154 =>
          table_value := 207;
        when 155 =>
          table_value := 208;
        when 156 =>
          table_value := 209;
        when 157 =>
          table_value := 210;
        when 158 =>
          table_value := 211;
        when 159 =>
          table_value := 212;
        when 160 =>
          table_value := 212;
        when 161 =>
          table_value := 213;
        when 162 =>
          table_value := 214;
        when 163 =>
          table_value := 215;
        when 164 =>
          table_value := 216;
        when 165 =>
          table_value := 217;
        when 166 =>
          table_value := 218;
        when 167 =>
          table_value := 218;
        when 168 =>
          table_value := 219;
        when 169 =>
          table_value := 220;
        when 170 =>
          table_value := 221;
        when 171 =>
          table_value := 221;
        when 172 =>
          table_value := 222;
        when 173 =>
          table_value := 223;
        when 174 =>
          table_value := 224;
        when 175 =>
          table_value := 225;
        when 176 =>
          table_value := 225;
        when 177 =>
          table_value := 226;
        when 178 =>
          table_value := 227;
        when 179 =>
          table_value := 227;
        when 180 =>
          table_value := 228;
        when 181 =>
          table_value := 229;
        when 182 =>
          table_value := 230;
        when 183 =>
          table_value := 230;
        when 184 =>
          table_value := 231;
        when 185 =>
          table_value := 232;
        when 186 =>
          table_value := 232;
        when 187 =>
          table_value := 233;
        when 188 =>
          table_value := 233;
        when 189 =>
          table_value := 234;
        when 190 =>
          table_value := 235;
        when 191 =>
          table_value := 235;
        when 192 =>
          table_value := 236;
        when 193 =>
          table_value := 236;
        when 194 =>
          table_value := 237;
        when 195 =>
          table_value := 238;
        when 196 =>
          table_value := 238;
        when 197 =>
          table_value := 239;
        when 198 =>
          table_value := 239;
        when 199 =>
          table_value := 240;
        when 200 =>
          table_value := 240;
        when 201 =>
          table_value := 241;
        when 202 =>
          table_value := 241;
        when 203 =>
          table_value := 242;
        when 204 =>
          table_value := 242;
        when 205 =>
          table_value := 243;
        when 206 =>
          table_value := 243;
        when 207 =>
          table_value := 244;
        when 208 =>
          table_value := 244;
        when 209 =>
          table_value := 245;
        when 210 =>
          table_value := 245;
        when 211 =>
          table_value := 246;
        when 212 =>
          table_value := 246;
        when 213 =>
          table_value := 246;
        when 214 =>
          table_value := 247;
        when 215 =>
          table_value := 247;
        when 216 =>
          table_value := 248;
        when 217 =>
          table_value := 248;
        when 218 =>
          table_value := 248;
        when 219 =>
          table_value := 249;
        when 220 =>
          table_value := 249;
        when 221 =>
          table_value := 249;
        when 222 =>
          table_value := 250;
        when 223 =>
          table_value := 250;
        when 224 =>
          table_value := 250;
        when 225 =>
          table_value := 251;
        when 226 =>
          table_value := 251;
        when 227 =>
          table_value := 251;
        when 228 =>
          table_value := 251;
        when 229 =>
          table_value := 252;
        when 230 =>
          table_value := 252;
        when 231 =>
          table_value := 252;
        when 232 =>
          table_value := 252;
        when 233 =>
          table_value := 253;
        when 234 =>
          table_value := 253;
        when 235 =>
          table_value := 253;
        when 236 =>
          table_value := 253;
        when 237 =>
          table_value := 253;
        when 238 =>
          table_value := 254;
        when 239 =>
          table_value := 254;
        when 240 =>
          table_value := 254;
        when 241 =>
          table_value := 254;
        when 242 =>
          table_value := 254;
        when 243 =>
          table_value := 254;
        when 244 =>
          table_value := 254;
        when 245 =>
          table_value := 254;
        when 246 =>
          table_value := 255;
        when 247 =>
          table_value := 255;
        when 248 =>
          table_value := 255;
        when 249 =>
          table_value := 255;
        when 250 =>
          table_value := 255;
        when 251 =>
          table_value := 255;
        when 252 =>
          table_value := 255;
        when 253 =>
          table_value := 255;
        when 254 =>
          table_value := 255;
        when 255 =>
          table_value := 255;
      end case;
      return table_value;
    end;
    
  begin
    if rising_edge(ethclock) then
      i2s_master_clk <= i2s_master_clk_int;
      i2s_sync <= i2s_sync_int;      
      
      if divisor /= 0 then
        divisor <= divisor - 1;
      else
        divisor <= divisor_max;
        if table_dir='1' then
          if table_offset /= 255 then
            table_offset <= table_offset + 1;
          else
            table_dir <= '0';
          end if;
        else
          if table_offset /= 0 then
            table_offset <= table_offset - 1;
          else
            table_dir <= '1';
            table_neg <= not table_neg;
            led <= not led;
          end if;
        end if;
      end if;
      if sample = x"fFFF" then
        sample <= x"0000";
      else
        sample <= sample(14 downto 0)&'1';
      end if;
--      sample <= to_unsigned(get_table_value(table_offset)*256,16);
    end if;
  end process;
  
  
end Behavioral;
