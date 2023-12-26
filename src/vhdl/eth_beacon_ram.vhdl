use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

ENTITY beaconram IS
  PORT (
    clk : IN STD_LOGIC;
    w : IN std_logic;
    write_address : IN integer range 0 to 67;
    wdata : IN unsigned(7 DOWNTO 0);
    address : IN integer range 0 to 2047;
    rdata : OUT unsigned(7 DOWNTO 0)
    );
END beaconram;

architecture behavioural of beaconram is

  type ram_t is array (0 to 67) of unsigned(7 downto 0);
  signal ram : ram_t := (
    -- MAC addresses
    x"33", x"33", x"00", x"00", x"00", x"01",
    x"00", x"00", x"00", x"00", x"00", x"00",  -- will be replaced with actual MAC address
    -- Ethernet type field (IPv6)
    x"86", x"dd",
    -- IPv6 header
    x"60", x"00", x"00", x"00",
    -- IPv6 payload length
    x"00", x"0e",
    -- IPv6 next header (UDP) + hop limit
    x"11", x"ff",
    -- IPv6 source address
    x"fe", x"80", x"00", x"00", x"00", x"00", x"00", x"00",
    x"00", x"00", x"00", x"ff", x"fe", x"00", x"00", x"00",  -- will be replaced with EUI-64/MAC address
    -- IPv6 destination address
    x"ff", x"02", x"00", x"00", x"00", x"00", x"00", x"00",
    x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"01",
    -- UDP src & dest ports (4510)
    x"11", x"9e", x"11", x"9e",
    -- UDP length
    x"00", x"0e",
    -- UDP checksum
    x"d5", x"15",  -- will be replaced with correct checksum
    -- UDP payload ("mega65")
    x"6d", x"65", x"67", x"61", x"36", x"35"
    );
  signal mac_address : unsigned(47 downto 0) := (others => '0');
  signal mac_bytes_left : integer range 0 to 6 := 0;
  signal checksum : unsigned(15 downto 0) := (others => '0');
  signal chks_bytes_left : integer := 2;

begin  -- behavioural

  process(clk,ram,w,wdata,write_address,address)
    procedure recalc_chks is
      variable beacon_chks : unsigned(17 downto 0) := (others => '0');
    begin
      beacon_chks :=   unsigned'("00" & (mac_address(47 downto 32) xor to_unsigned(512,16))) -- xor X"0200"
                     + unsigned'("00" & mac_address(31 downto 16))
                     + unsigned'("00" & mac_address(15 downto 0));
  
      -- max value of beacon_chks at this point is 2fffe (3xffff)
      -- so the following addition can't overflow (max value is ffff)
      beacon_chks := ("00" & beacon_chks(15 downto 0)) + (x"0000" & beacon_chks(17 downto 16));

      beacon_chks :=   to_unsigned(54549, 18) -- this is like "00" & X"D515"
                     - beacon_chks;

      if beacon_chks(15 downto 0) = x"0000" then -- 0000=ffff in ones complement, and 0000 is not allowed in UDPv6 checksum
        beacon_chks(15 downto 0) := x"ffff";
      else
        -- apply remaining carry bit (if any)
        beacon_chks(15 downto 0) := beacon_chks(15 downto 0) - (x"000" & "000" & beacon_chks(16));
      end if;
  
      checksum <= beacon_chks(15 downto 0);
      chks_bytes_left <= 2;
    end procedure;
  begin
    if address < 68 then
      rdata <= ram(address);
    else
      rdata <= x"42";
    end if;

    if(rising_edge(clk)) then
      if w='1' then
        if write_address >= 6 and write_address <= 13 then
          ram(write_address) <= wdata;
          mac_address(47 - (write_address - 6)*8 downto 40 - (write_address - 6)*8) <= wdata;
          mac_bytes_left <= 6;
        end if;
      elsif mac_bytes_left > 0 then
        case mac_bytes_left is
          when 4 to 6 =>
            ram(31 + mac_bytes_left) <= mac_address(47 - (mac_bytes_left - 1)*8 downto 40 - (mac_bytes_left - 1)*8);
          when 2 to 3 =>
            ram(29 + mac_bytes_left) <= mac_address(47 - (mac_bytes_left - 1)*8 downto 40 - (mac_bytes_left - 1)*8);
          when 1 =>
            ram(30) <= mac_address(47 - (mac_bytes_left - 1)*8 downto 40 - (mac_bytes_left - 1)*8) xor "00000010";
            recalc_chks;
          when others =>
            mac_bytes_left <= 0;
        end case;
        mac_bytes_left <= mac_bytes_left - 1;
      elsif chks_bytes_left > 0 then
        case chks_bytes_left is
          when 2 =>
            ram(60) <= checksum(15 downto 8);
            chks_bytes_left <= chks_bytes_left - 1;
          when 1 =>
            ram(61) <= checksum(7 downto 0);
            chks_bytes_left <= chks_bytes_left - 1;
          when others =>
            chks_bytes_left <= 0;
        end case;
      end if;
    end if;    
  end process;

end behavioural;
