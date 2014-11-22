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
begin

  signal r0  : integer;
  signal r1  : integer;
  signal g0  : integer;
  signal g1  : integer;
  signal b0  : integer;
  signal b1  : integer;
  
  process (clk1x) is
    variable temp : integer;
  begin
    if rising_edge(clk1x) then
      r0 <= to_integer(unsigned(r_strm0))
            *to_integer(unsigned(alpha_strm));
      r1 <= to_integer(unsigned(r_strm1))
            *(1024-to_integer(unsigned(alpha_strm)));
      r_blnd <= std_logic_vector(to_unsigned((r0+r1)/1024,10));

      g0 <= to_integer(unsigned(g_strm0))
            *to_integer(unsigned(alpha_strm));
      g1 <= to_integer(unsigned(g_strm1))
            *(1024-to_integer(unsigned(alpha_strm)));
      g_blnd <= std_logic_vector(to_unsigned((g0+g1)/1024,10));
      
      b0 <= to_integer(unsigned(b_strm0))
            *to_integer(unsigned(alpha_strm));
      b1 <= to_integer(unsigned(b_strm1))
            *(1024-to_integer(unsigned(alpha_strm)));
      b_blnd <= std_logic_vector(to_unsigned((b0+b1)/1024,10));
    end if;
  end process;
end behavioural;
