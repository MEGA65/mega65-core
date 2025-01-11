library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;
        use work.all;

entity sid_coeffs_mux is
port (
	clk  : in  std_logic;
	addr0 : in  integer range 0 to 2047 := 0; 
	val0  : out unsigned(15 downto 0) := to_unsigned(0,16);
	addr1 : in  integer range 0 to 2047 := 0;
	val1  : out unsigned(15 downto 0) := to_unsigned(0,16);
	addr2 : in  integer range 0 to 2047 := 0;
	val2  : out unsigned(15 downto 0) := to_unsigned(0,16);
	addr3 : in  integer range 0 to 2047 := 0;
	val3  : out unsigned(15 downto 0) := to_unsigned(0,16);
	addr4 : in  integer range 0 to 2047 := 0;
	val4  : out unsigned(15 downto 0) := to_unsigned(0,16);
	addr5 : in  integer range 0 to 2047 := 0;
	val5  : out unsigned(15 downto 0) := to_unsigned(0,16);
	addr6 : in  integer range 0 to 2047 := 0;
	val6  : out unsigned(15 downto 0) := to_unsigned(0,16);
	addr7 : in  integer range 0 to 2047 := 0;
	val7  : out unsigned(15 downto 0) := to_unsigned(0,16);

        addr  : out unsigned(11 downto 0);
        di    : in  unsigned(7 downto 0)
);
end entity;
             
architecture mayan of sid_coeffs_mux is
  signal mux_counter : integer range 0 to 15 := 15;
  signal read_cache : unsigned(7 downto 0) := (others => '0'); 
  signal val  : unsigned(7 downto 0) := (others => '0');
begin
  
  process(clk) is
  begin
    if rising_edge(clk) then
      case mux_counter is
        when 0  => read_cache <= di; addr <= to_unsigned(addr0*2, 12);
        when 1  => val7 <= di & read_cache; addr <= to_unsigned(addr0*2+1, 12);
        when 2  => read_cache <= di; addr <= to_unsigned(addr1*2, 12);
        when 3  => val0 <= di & read_cache; addr <= to_unsigned(addr1*2+1, 12);
        when 4  => read_cache <= di; addr <= to_unsigned(addr2*2, 12);
        when 5  => val1 <= di & read_cache; addr <= to_unsigned(addr2*2+1, 12);
        when 6  => read_cache <= di; addr <= to_unsigned(addr3*2, 12);
        when 7  => val2 <= di & read_cache; addr <= to_unsigned(addr3*2+1, 12);
        when 8  => read_cache <= di; addr <= to_unsigned(addr4*2, 12);
        when 9  => val3 <= di & read_cache; addr <= to_unsigned(addr4*2+1, 12);
        when 10 => read_cache <= di; addr <= to_unsigned(addr5*2, 12);
        when 11 => val4 <= di & read_cache; addr <= to_unsigned(addr5*2+1, 12);
        when 12 => read_cache <= di; addr <= to_unsigned(addr6*2, 12);
        when 13 => val5 <= di & read_cache; addr <= to_unsigned(addr6*2+1, 12);
        when 14 => read_cache <= di; addr <= to_unsigned(addr7*2, 12);
        when 15 => val6 <= di & read_cache; addr <= to_unsigned(addr7*2+1, 12);
      end case;
      if mux_counter /= 15 then
        mux_counter <= mux_counter + 1;
      else
        mux_counter <= 0;
      end if;
    end if;
  end process;
end mayan;
