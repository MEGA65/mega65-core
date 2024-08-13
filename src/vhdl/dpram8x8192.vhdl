--
-- True-Dual-Port BRAM with Byte-wide Write Enable
--  Write First mode
--
-- File: HDL_Coding_Techniques/rams/bytewrite_tdp_ram_wf.vhd
--

-- WRITE_FIRST ByteWide WriteEnable Block RAM Template

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;


entity dpram8x8192 is
  generic (
    SIZE	 : integer := 8192;
    ADDR_WIDTH : integer := 13;
    COL_WIDTH	: integer := 8;
    NB_COL		 : integer := 1 
    );
  
  port (
    clka	: in	std_logic;
    ena	 : in	std_logic;				
    wea	 : in	std_logic_vector(NB_COL-1 downto 0);
    addra : in	std_logic_vector(ADDR_WIDTH-1 downto 0);
    dina	 : in	std_logic_vector(NB_COL*COL_WIDTH-1 downto 0);
    douta	 : out std_logic_vector(NB_COL*COL_WIDTH-1 downto 0);
    clkb	: in	std_logic;
    enb	 : in	std_logic;
    web	 : in	std_logic_vector(NB_COL-1 downto 0);
    addrb : in	std_logic_vector(ADDR_WIDTH-1 downto 0);
    dinb	 : in	std_logic_vector(NB_COL*COL_WIDTH-1 downto 0);
    doutb	 : out std_logic_vector(NB_COL*COL_WIDTH-1 downto 0);

    silence_internal_drive : in std_logic := '0'    
    );
  
end dpram8x8192;

architecture behavioural of dpram8x8192 is

  type ram_type is array (0 to SIZE-1) of std_logic_vector (NB_COL*COL_WIDTH-1 downto 0);
  shared variable RAM : ram_type := (
    others => (others => '0'));

  signal last_addrb : std_logic_vector(ADDR_WIDTH-1 downto 0);
  
begin

  -------	 Port A	-------
  process (clka,ena,addra)
  begin
    if rising_edge(clka) then
      if ena = '1' then	
        for i in 0 to NB_COL-1 loop
          if wea(i) = '1' then
            RAM(to_integer(unsigned(addra((ADDR_WIDTH-1) downto 0))))((i+1)*COL_WIDTH-1 downto i*COL_WIDTH)	 := dina((i+1)*COL_WIDTH-1 downto i*COL_WIDTH);
            report "1581RAM: Back-channel write to $" & to_hexstring(unsigned(addra)) & " of $" & to_hexstring(dina);
          end if;			 
        end loop;
      end if;
    end if;
    if ena = '1' then	                  
      douta <= RAM(to_integer(unsigned(addra((ADDR_WIDTH-1) downto 0))));
    else
      douta <= (others => 'Z');
    end if;
    
  end process;

-------	 Port B	-------
  process (clkb)
  begin
    if rising_edge(clkb) then
      if enb = '1' then
        for i in 0 to NB_COL-1 loop
          if web(i) = '1' then
            RAM(to_integer(unsigned(addrb((ADDR_WIDTH-1) downto 0))))((i+1)*COL_WIDTH-1 downto i*COL_WIDTH)	 := dinb((i+1)*COL_WIDTH-1 downto i*COL_WIDTH);
            if silence_internal_drive='0' then
              report "1581RAM: Writing $" & to_hexstring(dinb) & " to address $" & to_hexstring(to_unsigned(to_integer(unsigned(addrb)),16));
            end if;
          end if;
        end loop;
        doutb <= RAM(to_integer(unsigned(addrb((ADDR_WIDTH-1) downto 0))));
      if to_integer(unsigned(addrb)) >= (3*256) and addrb /= last_addrb then
        report "1581RAM: Reading buffer address $" & to_hexstring(unsigned(addrb));
        last_addrb <= addrb;
      end if;
      end if;
    end if;
  end process;
end behavioural;
