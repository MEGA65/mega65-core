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
         chroma : in unsigned(7 downto 0);
         luma : in unsigned(7 downto 0);
         composite : in unsigned(7 downto 0);
         audio : in unsigned(7 downto 0)
         
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

  signal chroma_high : unsigned(2 downto 0) := (others => '0');
--  signal chroma_low : unsigned(7 downto 0) := (others => '0');
  signal luma_high : unsigned(2 downto 0) := (others => '0');
--  signal luma_low : unsigned(7 downto 0) := (others => '0');
  signal composite_high : unsigned(2 downto 0) := (others => '0');
--  signal composite_low : unsigned(7 downto 0) := (others => '0');

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
    if rising_edge(clock27) then
      -- Toggle bottom bit of DAC really fast to simulate higher
      -- resolution than the 4 bits we have.
      -- With appropriate filtering of the resulting signal,
      -- this should gain us 2 extra bits of resolution
      chroma_high    <= chroma(7 downto 5);
--      chroma_low     <= pick_sub_clock(chroma(4 downto 2));
      luma_high      <= luma(7 downto 5);
--      luma_low       <= pick_sub_clock(luma(4 downto 2));
      composite_high <= composite(7 downto 5);
--      composite_low  <= pick_sub_clock(composite(4 downto 2));
    end if;
    
    if rising_edge(clock270) then
      -- Bit order on PMODs is reversed
      -- We want at least 6 bits of total resolution,
      -- so we do PWM on lowest bit (and later on all
      -- bits, with 4x or 8x step between resistors, instead
      -- of just 2x).
      p2lo <= (others => '0');
      p2hi <= (others => '0');
      p1hi <= (others => '0');
      for i in 0 to 2 loop
        p2lo(i) <= chroma_high(2 - i);
        p2hi(i) <= luma_high(2 - i);
        p1hi(i) <= composite_high(2 - i);
      end loop;

      if sub_clock /= 7 then
        sub_clock <= sub_clock + 1;
      else
        sub_clock <= 0;
      end if;
      
    end if;
  end process;
  
end gothic;

