library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use work.all;
use work.debugtools.all;

entity alpha_blend_top is
  port(
    clk1x:       in  std_logic;
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

    alpha_delay : in unsigned(3 downto 0);
    
     pixclk_out: out std_logic := '1';
     hsync_blnd: out std_logic := '1';
     vsync_blnd: out std_logic := '1';
     de_blnd:    out std_logic := '1';
     r_blnd:     out std_logic_vector(9 downto 0) := (others => '0');
     g_blnd:     out std_logic_vector(9 downto 0) := (others => '0');
     b_blnd:     out std_logic_vector(9 downto 0) := (others => '0');
     dcm_locked:  out std_logic := '1'
); 
end alpha_blend_top;

architecture behavioural of alpha_blend_top is
  signal r0  : integer := 0;
  signal r1  : integer := 0;
  signal g0  : integer := 0;
  signal g1  : integer := 0;
  signal b0  : integer := 0;
  signal b1  : integer := 0;
  signal r0drive  : integer := 0;
  signal r1drive  : integer := 0;
  signal g0drive  : integer := 0;
  signal g1drive  : integer := 0;
  signal b0drive  : integer := 0;
  signal b1drive  : integer := 0;
  signal alpha_strm_drive: unsigned(10 downto 0) := (others => '0');
  signal oneminusalpha : integer := 0;

  signal alpha_delayed : unsigned(10 downto 0) := (others => '0');
  signal oneminusalpha_delayed : integer := 0;
  signal alpha_delayed1 : unsigned(10 downto 0) := (others => '0');
  signal oneminusalpha_delayed1 : integer := 0;
  signal alpha_delayed2 : unsigned(10 downto 0) := (others => '0');
  signal oneminusalpha_delayed2 : integer := 0;
  signal alpha_delayed3 : unsigned(10 downto 0) := (others => '0');
  signal oneminusalpha_delayed3 : integer := 0;
  signal alpha_delayed4 : unsigned(10 downto 0) := (others => '0');
  signal oneminusalpha_delayed4 : integer := 0;
  signal alpha_delayed5 : unsigned(10 downto 0) := (others => '0');
  signal oneminusalpha_delayed5 : integer := 0;
  
  
begin
  
  process (clk1x) is
    variable temp : unsigned(19 downto 0);
  begin
    if rising_edge(clk1x) then

      -- Keep alpha values as-is, as we sign-extend the lowest bit into the bottom
      -- two bits, so full brightness will be $3FF/$400 = 99.9%, which is fine,
      -- and will avoid the wrap-around from stark white to black that we are seeing.
      alpha_strm_drive <= unsigned("0"&alpha_strm);
      oneminusalpha <= (1024-safe_to_integer(unsigned(alpha_strm)));

      alpha_delayed1 <= alpha_strm_drive;
      oneminusalpha_delayed1 <= oneminusalpha;

      alpha_delayed2 <= alpha_delayed1;
      oneminusalpha_delayed2 <= oneminusalpha_delayed1;

      alpha_delayed3 <= alpha_delayed2;
      oneminusalpha_delayed3 <= oneminusalpha_delayed2;

      alpha_delayed4 <= alpha_delayed3;
      oneminusalpha_delayed4 <= oneminusalpha_delayed3;

      alpha_delayed5 <= alpha_delayed4;
      oneminusalpha_delayed5 <= oneminusalpha_delayed4;
      
      case alpha_delay is
        when x"1" =>
          alpha_delayed <= alpha_delayed1;
          oneminusalpha_delayed <= oneminusalpha_delayed1;
        when x"2" =>
          alpha_delayed <= alpha_delayed2;
          oneminusalpha_delayed <= oneminusalpha_delayed2;
        when x"3" =>
          alpha_delayed <= alpha_delayed3;
          oneminusalpha_delayed <= oneminusalpha_delayed3;
        when x"4" =>
          alpha_delayed <= alpha_delayed4;
          oneminusalpha_delayed <= oneminusalpha_delayed4;
        when x"5" =>
          alpha_delayed <= alpha_delayed5;
          oneminusalpha_delayed <= oneminusalpha_delayed5;
        when others =>
          alpha_delayed <= alpha_strm_drive;
          oneminusalpha_delayed <= oneminusalpha;
      end case;                    
      
      r0 <= safe_to_integer(unsigned(r_strm0))
            *safe_to_integer(alpha_delayed);
      r1 <= safe_to_integer(unsigned(r_strm1))*oneminusalpha_delayed;
      r0drive <= r0;
      r1drive <= r1;
      temp := to_unsigned(r0drive+r1drive,20);
      r_blnd <= std_logic_vector(temp(19 downto 10));

      g0 <= safe_to_integer(unsigned(g_strm0))
            *safe_to_integer(alpha_delayed);
      g1 <= safe_to_integer(unsigned(g_strm1))*oneminusalpha_delayed;
      g0drive <= g0;
      g1drive <= g1;
      temp := to_unsigned(g0drive+g1drive,20);
      g_blnd <= std_logic_vector(temp(19 downto 10));
      
      b0 <= safe_to_integer(unsigned(b_strm0))
            *safe_to_integer(alpha_delayed);
      b1 <= safe_to_integer(unsigned(b_strm1))*oneminusalpha_delayed;
      b0drive <= b0;
      b1drive <= b1;
      temp := to_unsigned(b0drive+b1drive,20);
      b_blnd <= std_logic_vector(temp(19 downto 10));
    end if;
  end process;
end behavioural;
