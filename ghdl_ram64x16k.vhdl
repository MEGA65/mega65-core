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

  type ram_t is array (0 to 65535) of std_logic_vector(63 downto 0);
  signal ram : ram_t;

begin  -- behavioural

  process(clka)
  begin
    if(rising_edge(Clka)) then 
      if true then
        if wea(0)='1' then
          ram(to_integer(unsigned(addra)))(7 downto 0) <= dina(7 downto 0);
        end if;
        if wea(1)='1' then
          ram(to_integer(unsigned(addra)))(15 downto 8) <= dina(15 downto 8);
        end if;
        if wea(2)='1' then
          ram(to_integer(unsigned(addra)))(23 downto 16) <= dina(23 downto 16);
        end if;
        if wea(3)='1' then
          ram(to_integer(unsigned(addra)))(31 downto 24) <= dina(31 downto 24);
        end if;
        if wea(4)='1' then
          ram(to_integer(unsigned(addra)))(39 downto 32) <= dina(39 downto 32);
        end if;
        if wea(5)='1' then
          ram(to_integer(unsigned(addra)))(47 downto 40) <= dina(47 downto 40);
        end if;
        if wea(6)='1' then
          ram(to_integer(unsigned(addra)))(55 downto 48) <= dina(55 downto 48);
        end if;
        if wea(7)='1' then
          ram(to_integer(unsigned(addra)))(63 downto 56) <= dina(63 downto 56);
        end if;
        douta <= ram(to_integer(unsigned(addra)));
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
          ram(to_integer(unsigned(addrb)))(7 downto 0) <= dinb(7 downto 0);
        end if;
        if web(1)='1' then
          ram(to_integer(unsigned(addrb)))(15 downto 8) <= dinb(15 downto 8);
        end if;
        if web(2)='1' then
          ram(to_integer(unsigned(addrb)))(23 downto 16) <= dinb(23 downto 16);
        end if;
        if web(3)='1' then
          ram(to_integer(unsigned(addrb)))(31 downto 24) <= dinb(31 downto 24);
        end if;
        if web(4)='1' then
          ram(to_integer(unsigned(addrb)))(39 downto 32) <= dinb(39 downto 32);
        end if;
        if web(5)='1' then
          ram(to_integer(unsigned(addrb)))(47 downto 40) <= dinb(47 downto 40);
        end if;
        if web(6)='1' then
          ram(to_integer(unsigned(addrb)))(55 downto 48) <= dinb(55 downto 48);
        end if;
        if web(7)='1' then
          ram(to_integer(unsigned(addrb)))(63 downto 56) <= dinb(63 downto 56);
        end if;
        doutb <= ram(to_integer(unsigned(addrb)));
      else
        doutb <= (others => 'Z');
      end if;
    end if;
  end process;

end behavioural;
