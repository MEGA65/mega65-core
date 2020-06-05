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
	val7  : out unsigned(15 downto 0) := to_unsigned(0,16)
);
end entity;
             
architecture mayan of sid_coeffs_mux is
  signal mux_counter : integer range 0 to 7 := 0;
  signal addr : integer range 0 to 2047 := 0;
  signal val  : unsigned(15 downto 0) := to_unsigned(0,16);

begin

  block1: block
  begin
    coeffs: entity work.sid_coeffs port map (
      clk   => clk,
      addr  => addr,
      val   => val
      );
  end block;
    

  process(clk) is
  begin
    if rising_edge(clk) then
      case mux_counter is
        when 0 => val0 <= val; addr <= addr2;
        when 1 => val1 <= val; addr <= addr3;
        when 2 => val2 <= val; addr <= addr4;
        when 3 => val3 <= val; addr <= addr5;
        when 4 => val4 <= val; addr <= addr6;
        when 5 => val5 <= val; addr <= addr7;
        when 6 => val6 <= val; addr <= addr0;
        when 7 => val7 <= val; addr <= addr1;
      end case;
      if mux_counter /= 7 then
        mux_counter <= mux_counter + 1;
      else
        mux_counter <= 0;
      end if;
    end if;
  end process;
end mayan;
