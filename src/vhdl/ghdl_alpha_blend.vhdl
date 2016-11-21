library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use work.all;
use work.debugtools.all;

entity alpha_blend_top is
  port(
    clk1x:       in  std_logic;
    clk2x:       in  std_logic;
    reset:       in  std_logic;
    hsync_strm0: in  std_logic;
    vsync_strm0: in  std_logic;
    de_strm0:    in  std_logic;
    r_strm0:     in  std_logic_vector(9 downto 0);
    g_strm0:     in  std_logic_vector(9 downto 0);              
    b_strm0:     in  std_logic_vector(9 downto 0);
    de_strm1:    in  std_logic;
    r_strm1:     in  std_logic_vector(9 downto 0);
    g_strm1:     in  std_logic_vector(9 downto 0);
    b_strm1:     in  std_logic_vector(9 downto 0);
    de_alpha:    in  std_logic;
    alpha_strm:  in  std_logic_vector(9 downto 0);
 
     pixclk_out: out std_logic;
     hsync_blnd: out std_logic;
     vsync_blnd: out std_logic;
     de_blnd:    out std_logic;
     r_blnd:     out std_logic_vector(9 downto 0);
     g_blnd:     out std_logic_vector(9 downto 0);
     b_blnd:     out std_logic_vector(9 downto 0);
     dcm_locked:  out std_logic
); 
end alpha_blend_top;

architecture behavioural of alpha_blend_top is
  signal r0  : integer;
  signal r1  : integer;
  signal g0  : integer;
  signal g1  : integer;
  signal b0  : integer;
  signal b1  : integer;
  signal r0drive  : integer;
  signal r1drive  : integer;
  signal g0drive  : integer;
  signal g1drive  : integer;
  signal b0drive  : integer;
  signal b1drive  : integer;
  signal r_strm0_drive: std_logic_vector(9 downto 0);
  signal g_strm0_drive: std_logic_vector(9 downto 0);              
  signal b_strm0_drive: std_logic_vector(9 downto 0);
  signal r_strm1_drive: std_logic_vector(9 downto 0);
  signal g_strm1_drive: std_logic_vector(9 downto 0);              
  signal b_strm1_drive: std_logic_vector(9 downto 0);
  signal alpha_strm_drive: std_logic_vector(9 downto 0);
  signal oneminusalpha : integer;

begin
  
  process (clk1x) is
    variable temp : unsigned(19 downto 0);
  begin
    if rising_edge(clk1x) then
      r_strm0_drive <= r_strm0;
      r_strm1_drive <= r_strm1;
      g_strm0_drive <= g_strm0;
      g_strm1_drive <= g_strm1;
      b_strm0_drive <= b_strm0;
      b_strm1_drive <= b_strm1;
      alpha_strm_drive <= alpha_strm;
      oneminusalpha <= (1023-to_integer(unsigned(alpha_strm)));
      
      r0 <= to_integer(unsigned(r_strm0))
            *to_integer(unsigned(alpha_strm_drive));
      r1 <= to_integer(unsigned(r_strm1))*oneminusalpha;
      r0drive <= r0;
      r1drive <= r1;
      temp := to_unsigned(r0drive+r1drive,20);
      r_blnd <= std_logic_vector(temp(19 downto 10));

      g0 <= to_integer(unsigned(g_strm0))
            *to_integer(unsigned(alpha_strm_drive));
      g1 <= to_integer(unsigned(g_strm1))*oneminusalpha;
      g0drive <= g0;
      g1drive <= g1;
      temp := to_unsigned(g0drive+g1drive,20);
      g_blnd <= std_logic_vector(temp(19 downto 10));
      
      b0 <= to_integer(unsigned(b_strm0))
            *to_integer(unsigned(alpha_strm_drive));
      b1 <= to_integer(unsigned(b_strm1))*oneminusalpha;
      b0drive <= b0;
      b1drive <= b1;
      temp := to_unsigned(b0drive+b1drive,20);
      b_blnd <= std_logic_vector(temp(19 downto 10));
    end if;
  end process;
end behavioural;
