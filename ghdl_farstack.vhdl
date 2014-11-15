use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY farcallstack IS
  PORT (
    -- CPU fastio port
    clka : IN STD_LOGIC;
    ena : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    -- CPU parallel push/pop port
    clkb : IN STD_LOGIC;
    web : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    dinb : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    addrb : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(63 DOWNTO 0)
    );
END farcallstack;

architecture behavioural of farcallstack is

  type ram_t is array (0 to 511) of std_logic_vector(63 downto 0);
  signal ram : ram_t;

begin  -- behavioural

  -- 8-bit port
  process(clka)
  begin
    if ena='1' then
      case to_integer(unsigned(addra(2 downto 0))) is
      when 0 => douta <= ram(to_integer(unsigned(addra(11 downto 3))))(7 downto 0);
      when 1 => douta <= ram(to_integer(unsigned(addra(11 downto 3))))(15 downto 8);
      when 2 => douta <= ram(to_integer(unsigned(addra(11 downto 3))))(23 downto 16);
      when 3 => douta <= ram(to_integer(unsigned(addra(11 downto 3))))(31 downto 24);
      when 4 => douta <= ram(to_integer(unsigned(addra(11 downto 3))))(39 downto 32);
      when 5 => douta <= ram(to_integer(unsigned(addra(11 downto 3))))(47 downto 40);
      when 6 => douta <= ram(to_integer(unsigned(addra(11 downto 3))))(55 downto 48);
      when others => douta <= ram(to_integer(unsigned(addra(11 downto 3))))(63 downto 56);
      end case;
    else
      douta <= (others => 'Z');
    end if;
    if(rising_edge(Clka)) then 
      if ena='1' then
        if(wea="1") then
          case to_integer(unsigned(addrb(2 downto 0))) is
            when 0 => ram(to_integer(unsigned(addra(11 downto 3))))(7 downto 0) <= dina;
            when 1 => ram(to_integer(unsigned(addra(11 downto 3))))(15 downto 8) <= dina;
            when 2 => ram(to_integer(unsigned(addra(11 downto 3))))(23 downto 16) <= dina;
            when 3 => ram(to_integer(unsigned(addra(11 downto 3))))(31 downto 24) <= dina;
            when 4 => ram(to_integer(unsigned(addra(11 downto 3))))(39 downto 32) <= dina;
            when 5 => ram(to_integer(unsigned(addra(11 downto 3))))(47 downto 40) <= dina;
            when 6 => ram(to_integer(unsigned(addra(11 downto 3))))(55 downto 48) <= dina;
            when others => ram(to_integer(unsigned(addra(11 downto 3))))(63 downto 56) <= dina;
          end case;
        end if;
      end if;
    end if;
  end process;

  -- 64bit port
  process (clkb,addrb,ram)
  begin
    doutb <= ram(to_integer(unsigned(addrb)));
    if(rising_edge(Clkb)) then 
      if(web="1") then
        ram(to_integer(unsigned(addrb))) <= dinb;
      end if;
    end if;
  end process;

end behavioural;
