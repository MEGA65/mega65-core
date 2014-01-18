use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY ram64x16k IS
  PORT (
    clka : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(13 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    douta : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    clkb : IN STD_LOGIC;
    web : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    addrb : IN STD_LOGIC_VECTOR(13 DOWNTO 0);
    dinb : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(63 DOWNTO 0)
    );
END ram64x16k;

architecture behavioural of ram64x16k is

  type ram_t is array (0 to 65535) of std_logic_vector(7 downto 0);
  type allram_t is array (0 to 7) of ram_t;
  signal ram : allram_t;

begin  -- behavioural

  process(clka)
    variable theram : ram_t;
    variable thevalue : std_logic_vector(63 downto 0);
  begin
    if(rising_edge(Clka)) then 
      if true then
        thevalue := dina;
        for i in 0 to 7 loop
          if wea(i)='1' then
            report "writing $" & to_hstring(thevalue(7 downto 0))
              & " to $" & to_hstring("000"&addra&std_logic_vector(to_unsigned(i,3))) severity note;
            ram(i)(to_integer(unsigned(addra))) <= thevalue(7 downto 0);
          end if;
          thevalue(55 downto 0) := thevalue(63 downto 8);
        end loop;  -- i

        for i in 0 to 7 loop
          theram:=ram(i);          
          thevalue(55 downto 0) := thevalue(63 downto 8);
          thevalue(63 downto 56) := theram(to_integer(unsigned(addra)));
        end loop;  -- i
        douta <= thevalue;
        report "reading fastram at $" & to_hstring("000"&addra&"000")
          & ", contains $" & to_hstring(thevalue)
          severity note;
      
      else
        douta <= (others => 'Z');
      end if;
    end if; 
  end process;

  --process (clkb)
  --  variable theram : ram_t;
  --  variable thevalue : std_logic_vector(63 downto 0);
  --begin
  --  if(rising_edge(Clkb)) then 
  --    if true then
  --      thevalue := dina;
  --      for i in 0 to 7 loop
  --        if web(i)='1' then
  --          report "writing $" & to_hstring(thevalue(7 downto 0))
  --            & " to $" & to_hstring("000"&addrb&std_logic_vector(to_unsigned(i,3))) severity note;
  --          ram(i)(to_integer(unsigned(addrb))) <= thevalue(7 downto 0);
  --        end if;
  --        thevalue(55 downto 0) := thevalue(63 downto 8);
  --      end loop;  -- i

  --      for i in 0 to 7 loop
  --        theram:=ram(i);          
  --        thevalue(55 downto 0) := thevalue(63 downto 8);
  --        thevalue(63 downto 56) := theram(to_integer(unsigned(addrb)));
  --      end loop;  -- i
  --      douta <= thevalue;
  --      report "reading fastram at $" & to_hstring("000"&addra&"000")
  --        & ", contains $" & to_hstring(thevalue)
  --        severity note;
  --    else
  --      doutb <= (others => 'Z');
  --    end if;
  --  end if;
  --end process;

end behavioural;
