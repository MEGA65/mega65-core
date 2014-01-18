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
  signal ram(0 to 7) : ram_t  := (others => x"bd");

begin  -- behavioural

  process(clka)
    variable therame : ram_t;
    variable thevalue : std_logic_vector(63 downto 0) := dina;
  begin
    if(rising_edge(Clka)) then 
      if true then
        for i in 0 to 7 loop
          if wea(i)='1' then
            report "writing $" & to_hstring(thevalue(7 downto 0))
              & " to $" & to_hstring("000"&addra&std_logic_vector(to_unsigned(i,3))) severity note;
            theram:=ram(i);
            theram(to_integer(unsigned(addra))) <= thevalue(7 downto 0);
          end if;
          thevalue(55 downto 0) := thevalue(63 downto 8);
        end loop;  -- i

        for i in 0 to 7 loop
          
        end loop;  -- i
        douta <= ram(to_integer(unsigned(addra)));
        report "reading fastram at $" & to_hstring("000"&addra&"111")
          & ", contains $" & to_hstring(ram(to_integer(unsigned(addra))))
          severity note;
      
      else
        douta <= (others => 'Z');
      end if;
    end if; 
  end process;

  process (clkb)
  begin
    if(rising_edge(Clkb)) then 
      if true then
        if web(0)='1' then
          report "writing $" & to_hstring(dinb(7 downto 0))
            & " to $" & to_hstring("000"&addrb&"000") severity note;
          ram(to_integer(unsigned(addrb)))(7 downto 0) <= dinb(7 downto 0);
        end if;
        if web(1)='1' then
          report "writing $" & to_hstring(dinb(15 downto 8))
            & " to $" & to_hstring("000"&addrb&"001") severity note;
          ram(to_integer(unsigned(addrb)))(15 downto 8) <= dinb(15 downto 8);
        end if;
        if web(2)='1' then
          report "writing $" & to_hstring(dinb(23 downto 16))
            & " to $" & to_hstring("000"&addrb&"010") severity note;
          ram(to_integer(unsigned(addrb)))(23 downto 16) <= dinb(23 downto 16);
        end if;
        if web(3)='1' then
          report "writing $" & to_hstring(dinb(31 downto 24))
            & " to $" & to_hstring("000"&addrb&"011") severity note;
          ram(to_integer(unsigned(addrb)))(31 downto 24) <= dinb(31 downto 24);
        end if;
        if web(4)='1' then
          report "writing $" & to_hstring(dinb(39 downto 32))
            & " to $" & to_hstring("000"&addrb&"100") severity note;
          ram(to_integer(unsigned(addrb)))(39 downto 32) <= dinb(39 downto 32);
        end if;
        if web(5)='1' then
          report "writing $" & to_hstring(dinb(47 downto 40))
            & " to $" & to_hstring("000"&addrb&"101") severity note;
          ram(to_integer(unsigned(addrb)))(47 downto 40) <= dinb(47 downto 40);
        end if;
        if web(6)='1' then
          report "writing $" & to_hstring(dinb(55 downto 48))
            & " to $" & to_hstring("000"&addrb&"110") severity note;
          ram(to_integer(unsigned(addrb)))(55 downto 48) <= dinb(55 downto 48);
        end if;
        if web(7)='1' then
          report "writing $" & to_hstring(dinb(63 downto 56))
            & " to $" & to_hstring("000"&addrb&"111") severity note;
          ram(to_integer(unsigned(addrb)))(63 downto 56) <= dinb(63 downto 56);
        end if;
        doutb <= ram(to_integer(unsigned(addrb)));
      else
        doutb <= (others => 'Z');
      end if;
    end if;
  end process;

end behavioural;
