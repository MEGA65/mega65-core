--
-- True-Dual-Port BRAM with Byte-wide Write Enable
--  Write First mode
--
-- File: HDL_Coding_Techniques/rams/bytewrite_tdp_ram_wf.vhd
--

-- WRITE_FIRST ByteWide WriteEnable Block RAM Template

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity ram32x1024 is
	generic (
			SIZE	 : integer := 1024;
			ADDR_WIDTH : integer := 10;
			COL_WIDTH	: integer := 8;
			NB_COL		 : integer := 4 
			);
	
	port (
		clka	: in	std_logic;
		ena	 : in	std_logic;				
		wea	 : in	std_logic_vector(NB_COL-1 downto 0);
		addra : in	std_logic_vector(ADDR_WIDTH-1 downto 0);
		dina	 : in	std_logic_vector(NB_COL*COL_WIDTH-1 downto 0);
		douta	 : out std_logic_vector(NB_COL*COL_WIDTH-1 downto 0);
		clkb	: in	std_logic;
		-- enb	 : in	std_logic;
		web	 : in	std_logic_vector(NB_COL-1 downto 0);
		addrb : in	std_logic_vector(ADDR_WIDTH-1 downto 0);
		dinb	 : in	std_logic_vector(NB_COL*COL_WIDTH-1 downto 0);
		doutb	 : out std_logic_vector(NB_COL*COL_WIDTH-1 downto 0)
	 );
		
end ram32x1024;

architecture behavioural of ram32x1024 is

	type ram_type is array (0 to SIZE-1) of std_logic_vector (NB_COL*COL_WIDTH-1 downto 0);
	shared variable RAM : ram_type := (
		X"00000000",X"ffffff00",X"ab312600",X"66daff00",X"bb3fb800",X"55ce5800",X"1d0e9700",X"eaf57c00",
		X"b9741800",X"78730000",X"dd938700",X"5b5b5b00",X"8b8b8b00",X"b0f4ac00",X"aa9def00",X"b8b8b800",
		X"00000000",X"11111100",X"22222200",X"33333300",X"44444400",X"55555500",X"66666600",X"77777700",
		X"88888800",X"99999900",X"aaaaaa00",X"bbbbbb00",X"cccccc00",X"dddddd00",X"eeeeee00",X"ffffff00",
		X"00000000",X"00111100",X"00222200",X"00333300",X"00444400",X"00555500",X"00666600",X"00777700",
		X"00888800",X"00999900",X"00aaaa00",X"00bbbb00",X"00cccc00",X"00dddd00",X"00eeee00",X"00ffff00",
		X"00000000",X"11001100",X"22002200",X"33003300",X"44004400",X"55005500",X"66006600",X"77007700",
		X"88008800",X"99009900",X"aa00aa00",X"bb00bb00",X"cc00cc00",X"dd00dd00",X"ee00ee00",X"ff00ff00",
		X"00000000",X"11110000",X"22220000",X"33330000",X"44440000",X"55550000",X"66660000",X"77770000",
		X"88880000",X"99990000",X"aaaa0000",X"bbbb0000",X"cccc0000",X"dddd0000",X"eeee0000",X"ffff0000",
		X"00000000",X"11000000",X"22000000",X"33000000",X"44000000",X"55000000",X"66000000",X"77000000",
		X"88000000",X"99000000",X"aa000000",X"bb000000",X"cc000000",X"dd000000",X"ee000000",X"ff000000",
		X"00000000",X"00110000",X"00220000",X"00330000",X"00440000",X"00550000",X"00660000",X"00770000",
		X"00880000",X"00990000",X"00aa0000",X"00bb0000",X"00cc0000",X"00dd0000",X"00ee0000",X"00ff0000",
		X"00000000",X"00001100",X"00002200",X"00003300",X"00004400",X"00005500",X"00006600",X"00007700",
		X"00008800",X"00009900",X"0000aa00",X"0000bb00",X"0000cc00",X"0000dd00",X"0000ee00",X"0000ff00",
		X"00000000",X"ffffff00",X"ab312600",X"66daff00",X"bb3fb800",X"55ce5800",X"1d0e9700",X"eaf57c00",
		X"b9741800",X"78730000",X"dd938700",X"5b5b5b00",X"8b8b8b00",X"b0f4ac00",X"aa9def00",X"b8b8b800",
		X"00000000",X"11111100",X"22222200",X"33333300",X"44444400",X"55555500",X"66666600",X"77777700",
		X"88888800",X"99999900",X"aaaaaa00",X"bbbbbb00",X"cccccc00",X"dddddd00",X"eeeeee00",X"ffffff00",
		X"00000000",X"00111100",X"00222200",X"00333300",X"00444400",X"00555500",X"00666600",X"00777700",
		X"00888800",X"00999900",X"00aaaa00",X"00bbbb00",X"00cccc00",X"00dddd00",X"00eeee00",X"00ffff00",
		X"00000000",X"11001100",X"22002200",X"33003300",X"44004400",X"55005500",X"66006600",X"77007700",
		X"88008800",X"99009900",X"aa00aa00",X"bb00bb00",X"cc00cc00",X"dd00dd00",X"ee00ee00",X"ff00ff00",
		X"00000000",X"11110000",X"22220000",X"33330000",X"44440000",X"55550000",X"66660000",X"77770000",
		X"88880000",X"99990000",X"aaaa0000",X"bbbb0000",X"cccc0000",X"dddd0000",X"eeee0000",X"ffff0000",
		X"00000000",X"11000000",X"22000000",X"33000000",X"44000000",X"55000000",X"66000000",X"77000000",
		X"88000000",X"99000000",X"aa000000",X"bb000000",X"cc000000",X"dd000000",X"ee000000",X"ff000000",
		X"00000000",X"00110000",X"00220000",X"00330000",X"00440000",X"00550000",X"00660000",X"00770000",
		X"00880000",X"00990000",X"00aa0000",X"00bb0000",X"00cc0000",X"00dd0000",X"00ee0000",X"00ff0000",
		X"00000000",X"00001100",X"00002200",X"00003300",X"00004400",X"00005500",X"00006600",X"00007700",
		X"00008800",X"00009900",X"0000aa00",X"0000bb00",X"0000cc00",X"0000dd00",X"0000ee00",X"0000ff00",
		others => (others => '0'));

begin

	-------	 Port A	-------
	process (clka)
	begin
		if rising_edge(clka) then
			if ena = '1' then	
		 		for i in 0 to NB_COL-1 loop
					if wea(i) = '1' then
						RAM(conv_integer(addra))((i+1)*COL_WIDTH-1 downto i*COL_WIDTH)	 := dina((i+1)*COL_WIDTH-1 downto i*COL_WIDTH);
					end if;			 
				end loop;
				douta <= RAM(conv_integer(addra));				
			end if;
		end if;
		
	end process;

-------	 Port B	-------
	process (clkb)
	begin
		if rising_edge(clkb) then
			--if enb = '1' then
				for i in 0 to NB_COL-1 loop
					if web(i) = '1' then
						RAM(conv_integer(addrb))((i+1)*COL_WIDTH-1 downto i*COL_WIDTH)	 := dinb((i+1)*COL_WIDTH-1 downto i*COL_WIDTH);
					end if;			 
				end loop;
				doutb <= RAM(conv_integer(addrb));
			--end if;
		end if;
	end process;
end behavioural;
