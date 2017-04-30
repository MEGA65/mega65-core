use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY fake_expansion_port IS
  PORT (
    cart_ctrl_dir : in std_logic;
    cart_haddr_dir : in std_logic;
    cart_laddr_dir : in std_logic;
    cart_data_dir : in std_logic;

    cart_phi2 : in std_logic;
    cart_dotclock : in std_logic;
    cart_reset : in std_logic;

    cart_nmi : out std_logic;
    cart_irq : out std_logic;
    cart_dma : out std_logic;
    
    cart_exrom : inout std_logic := 'Z';
    cart_ba : inout std_logic := 'Z';
    cart_rw : inout std_logic := 'Z';
    cart_roml : inout std_logic := 'Z';
    cart_romh : inout std_logic := 'Z';
    cart_io1 : inout std_logic := 'Z';
    cart_game : inout std_logic := 'Z';
    cart_io2 : inout std_logic := 'Z';
    
    cart_d : inout unsigned(7 downto 0) := (others => 'Z');
    cart_a : inout unsigned(15 downto 0) := (others => 'Z')
);
end fake_expansion_port;

architecture behavioural of fake_expansion_port is

  type tiny_rom is array(0 to 15) of unsigned(7 downto 0);
  constant fake_rom_value : tiny_rom := (
    -- Reset and NMI entry vectors point to little program
    0 => x"09", 1 => x"80", 2 => x"09", 3 => x"80",
    -- C64 Cartridge ROM signature
    4 => x"C3", 5 => x"C2", 6 => x"CD", 7 => x"38", 8 => x"30",
    -- Little program
    9 => x"ee", 10 => x"20", 11 => x"d0",    -- 8009 INC $D020
    12 => x"4c", 13 => x"09", 14 => x"80",   -- 800C JMP $8009
    15 => x"00"
    );
  
  signal bus_exrom : std_logic := 'Z';
  signal bus_ba : std_logic := 'Z';
  signal bus_rw : std_logic := 'Z';
  signal bus_roml : std_logic := 'Z';
  signal bus_romh : std_logic := 'Z';
  signal bus_io1 : std_logic := 'Z';
  signal bus_game : std_logic := 'Z';
  signal bus_io2 : std_logic := 'Z';

  signal bus_a : unsigned(15 downto 0) := (others => 'Z');
  signal bus_d : unsigned(7 downto 0) := (others => 'Z');
  signal bus_d_drive : unsigned(7 downto 0) := (others => 'Z');
begin

  -- Generate bus signals
  process (cart_dotclock)
  begin
    -- XXX We shouldn't need to clock gate this, but have it behave simply as
    -- combinatorial logic.  But GHDL gets in an infinite loop here if we don't.    
    if rising_edge(cart_dotclock) then
      report "Saw dotclock toggle";
--      if cart_data_dir='0' then cart_d <= bus_d; end if;
      if cart_haddr_dir='0' then
        cart_a(15 downto 8) <= bus_a(15 downto 8);
      else
        bus_a(15 downto 8) <= cart_a(15 downto 8);
      end if;
      if cart_laddr_dir='0' then
        cart_a(7 downto 0) <= bus_a(7 downto 0);
      else
        bus_a(7 downto 0) <= cart_a(7 downto 0);
      end if;

      report "Reading control signals from cartridge pins, rw="
      & std_logic'image(cart_rw);
      bus_exrom <= cart_exrom;
      bus_ba <= cart_ba;
      bus_rw <= cart_rw;
      bus_roml <= cart_roml;
      bus_romh <= cart_romh;
      bus_io1 <= cart_io1;
      bus_game <= cart_game;
      bus_io2 <= cart_io2;      
    

      if bus_rw='1' and ((bus_roml='0') or (bus_io1='0') or (bus_roml='0')) then
        -- Expansion port latches values on clock edges.
        -- Therefore we cannot provide the data too fast
        cart_d <= bus_d_drive;
        report "Driving cartridge port data bus with $" & to_hstring(bus_d_drive);
      else
        report "Tristating cartridge port data bus rw=" & std_logic'image(bus_rw);
        cart_d <= (others => 'Z');
      end if;
    end if;
  end process;

  process (cart_dotclock)
  begin
    if rising_edge(cart_dotclock) then
      -- Map in a pretend C64 cartridge at $8000-$9FFF
      bus_d_drive
        <= fake_rom_value(to_integer(unsigned(bus_a(3 downto 0))));
    end if;
  end process;
  
  
end behavioural;
