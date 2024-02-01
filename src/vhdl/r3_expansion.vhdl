library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.cputypes.all;
use work.porttypes.all;
use work.types_pkg.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity r3_expansion is
  Port ( cpuclock : STD_LOGIC;         
         clock27 : std_logic;
         clock81 : std_logic;
         clock270 : std_logic;

         fastio_write : in std_logic;
         fastio_read : in std_logic;
         fastio_addr : in unsigned(19 downto 0);
         fastio_rdata : out unsigned(7 downto 0);
         fastio_wdata : in unsigned(7 downto 0);
         
         -- PMOD connectors on the MEGA65 main board
         -- We say R3 onwards, but in theory we can work with the R2 board
         -- as well, but that has a smaller FPGA, and no cut-outs in the
         -- case for the extra ports.
         p1lo : inout std_logic_vector(3 downto 0);
         p1hi : inout std_logic_vector(3 downto 0);
         p2lo : inout std_logic_vector(3 downto 0);
         p2hi : inout std_logic_vector(3 downto 0);

         -- C1565 port
         c1565_port_i : out c1565_port_in;
         c1565_port_o : in c1565_port_out;

         -- USER port
         user_port_i : out user_port_in;
         user_port_o : in user_port_out;

         -- TAPE port
         tape_port_i : out tape_port_in;
         tape_port_o : in tape_port_out;

         -- Video and Audio feed for composite video port
         chroma_in : in unsigned(7 downto 0);
         luma_in : in unsigned(7 downto 0);
         composite_in : in unsigned(7 downto 0);
         audio_l_in : in unsigned(7 downto 0);
         audio_r_in : in unsigned(7 downto 0)
         
         );

end r3_expansion;

architecture gothic of r3_expansion is

  constant seq_0 : unsigned(7 downto 0) := "00000000";
  constant seq_1 : unsigned(7 downto 0) := "10000000";
  constant seq_2 : unsigned(7 downto 0) := "10001000";
  constant seq_3 : unsigned(7 downto 0) := "00100101";
  constant seq_4 : unsigned(7 downto 0) := "01010101";
  constant seq_5 : unsigned(7 downto 0) := "01011011";
  constant seq_6 : unsigned(7 downto 0) := "01110111";
  constant seq_7 : unsigned(7 downto 0) := "01111111";
  constant seq_8 : unsigned(7 downto 0) := "11111111";

  type source_names is (
    chroma, luma, composite,
    audio_left, audio_right,
    red, green, blue,
    red_sync, green_sync, blue_sync,
    p_b, p_r,
    unused13,unused14,unused15
    );
  
  signal channel_a_source : source_names := chroma;
  signal channel_b_source : source_names := luma;
  signal channel_c_source : source_names := composite;

  signal channel_a_source_cpu : source_names := chroma;
  signal channel_b_source_cpu : source_names := luma;
  signal channel_c_source_cpu : source_names := composite;

  signal channel_a_data : unsigned(7 downto 0);
  signal channel_b_data : unsigned(7 downto 0);
  signal channel_c_data : unsigned(7 downto 0);
  
  signal chan_a_high  : unsigned(7 downto 0) := (others => '0');
  signal chan_b_high  : unsigned(7 downto 0) := (others => '0');
  signal chan_c_high  : unsigned(7 downto 0) := (others => '0');
  signal chan_a_low  : unsigned(7 downto 0) := (others => '0');
  signal chan_b_low  : unsigned(7 downto 0) := (others => '0');
  signal chan_c_low  : unsigned(7 downto 0) := (others => '0');

  signal sub_clock : integer range 0 to 7 := 0;

  subtype unsigned2_0_t is unsigned(2 downto 0);
  subtype unsigned7_0_t is unsigned(7 downto 0);
  
  function pick_sub_clock(n : unsigned2_0_t) return unsigned7_0_t is
  begin
    case n is
      when "000" => return seq_1;
      when "001" => return seq_2;
      when "010" => return seq_3;
      when "011" => return seq_4;
      when "100" => return seq_5;
      when "101" => return seq_6;
      when "110" => return seq_7;
      when "111" => return seq_8;
      when others => return seq_0;
    end case;
  end pick_sub_clock;    

  impure function source_select(source : source_names) return unsigned7_0_t is
  begin
      case source is
        when chroma =>      return chroma_in;
        when luma =>        return luma_in;
        when composite =>   return composite_in;
        when audio_left =>  return audio_l_in;
        when audio_right => return audio_r_in;
        when others =>      return (others => '0');          
      end case;
  end source_select;          

  function source_name_lookup(source : integer) return source_names is
  begin
    case source is
      when 0 => return chroma;
      when 1 => return luma;
      when 2 => return composite;
      when 3 => return audio_left;
      when 4 => return audio_right;
      when 5 => return red;
      when 6 => return green;
      when 7 => return blue;
      when 8 => return red_sync;
      when 9 => return green_sync;
      when 10 => return blue_sync;
      when 11 => return p_b;
      when 12 => return p_r;
      when 13 => return unused13;
      when 14 => return unused14;
      when 15 => return unused15;
      when others => return unused15;
    end case;
  end source_name_lookup;
 
begin

  controller0: entity work.exp_board_ring_ctrl port map (

    -- Master clock
    clock41 => cpuclock,

    -- Management interface (not connected for now)
    cs => '0',
--    fastio_rdata => fastio_rdata,
    fastio_wdata => to_unsigned(0,8),
    fastio_addr => to_unsigned(0,20),
    fastio_write => '0',

    -- PMOD pins
    exp_clock => p1lo(1),
    exp_latch => p1lo(0),
    exp_wdata => p1lo(2),
    exp_rdata => p1lo(3),
    
    -- Tape port
    tape_o => tape_port_o,
    tape_i => tape_port_i,
    
    -- C1565 port
    c1565_i => c1565_port_i,
    c1565_o => c1565_port_o,
    
    -- User port
    user_i => user_port_i,
    user_o => user_port_o
    
    );

  
  process (clock270,clock81,clock27) is
  begin

    if fastio_addr(19 downto 4) = x"D800" and fastio_read = '1' then
      case fastio_addr(3 downto 0) is
        when x"0" => fastio_rdata <= to_unsigned(source_names'pos(channel_a_source_cpu),8);
        when x"1" => fastio_rdata <= to_unsigned(source_names'pos(channel_b_source_cpu),8);
        when x"2" => fastio_rdata <= to_unsigned(source_names'pos(channel_c_source_cpu),8);
        when others => fastio_rdata <= (others => 'Z');
      end case;
    else
      fastio_rdata <= (others => 'Z');
    end if;
    
    
    if rising_edge(cpuclock) then
      -- @IO:GS $FFD8000 ANALOGAV:CHANASEL Select source for analog output channel A
      -- @IO:GS $FFD8001 ANALOGAV:CHANASEL Select source for analog output channel A
      -- @IO:GS $FFD8002 ANALOGAV:CHANASEL Select source for analog output channel A
      if fastio_addr(19 downto 4) = x"D800" and fastio_write='1' then
        case fastio_addr(3 downto 0) is
          when x"0" => channel_a_source_cpu <= source_name_lookup(to_integer(fastio_wdata));
          when x"1" => channel_b_source_cpu <= source_name_lookup(to_integer(fastio_wdata));
          when x"2" => channel_c_source_cpu <= source_name_lookup(to_integer(fastio_wdata));
          when others => null;
        end case;
      end if;
    end if;
    
    if rising_edge(clock27) then

      channel_a_source <= channel_a_source_cpu;
      channel_b_source <= channel_b_source_cpu;
      channel_b_source <= channel_c_source_cpu;

      channel_a_data <= source_select(channel_a_source);
      channel_b_data <= source_select(channel_b_source);
      channel_c_data <= source_select(channel_c_source);

      -- Toggle bottom bit of DAC really fast to simulate higher
      -- resolution than the 4 bits we have.
      -- With appropriate filtering of the resulting signal,
      -- this should gain us 2 extra bits of resolution
      chan_a_high <= pick_sub_clock(channel_a_data(7 downto 5)); chan_a_low <= pick_sub_clock(channel_a_data(4 downto 2));
      chan_b_high <= pick_sub_clock(channel_b_data(7 downto 5)); chan_b_low <= pick_sub_clock(channel_b_data(4 downto 2));
      chan_c_high <= pick_sub_clock(channel_c_data(7 downto 5)); chan_c_low <= pick_sub_clock(channel_c_data(4 downto 2));
      
    end if;
    
    if rising_edge(clock270) then
      -- Bit order on PMODs is reversed
      -- We want at least 8 bits of total resolution,
      -- so we do PWM on lowest bit (and later on all
      -- bits, with 4x or 8x step between resistors, instead
      -- of just 2x).
      p2lo(2 downto 1) <= (others => '0');
      p2hi(2 downto 1) <= (others => '0');
      p1hi(2 downto 1) <= (others => '0');
      p2lo(0) <= chan_a_high(sub_clock);
      p2hi(0) <= chan_b_high(sub_clock);
      p1hi(0) <= chan_c_high(sub_clock);
      p2lo(3) <= chan_a_low(sub_clock);
      p2hi(3) <= chan_b_low(sub_clock);
      p1hi(3) <= chan_c_low(sub_clock);

      if sub_clock /= 7 then
        sub_clock <= sub_clock + 1;
      else
        sub_clock <= 0;
      end if;
      
    end if;
  end process;
  
end gothic;

