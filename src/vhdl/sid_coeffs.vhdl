library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sid_coeffs is
  port (
    clka   : in  std_logic;
    clkb   : in  std_logic;
    addra  : in  unsigned(11 downto 0);
    addrb  : in  unsigned(11 downto 0);
    dia    : in  unsigned(7 downto 0) := (others => '0');
    dib    : in  unsigned(7 downto 0) := (others => '0');
    douta  : out unsigned(7 downto 0) := (others => 'Z');
    doutb  : out unsigned(7 downto 0) := (others => '0');
    wea    : in  std_logic;
    web    : in  std_logic;
    ena    : in  std_logic;
    enb    : in  std_logic
    -- rsta   : in  std_logic;
    -- rstb   : in  std_logic;
    -- regcea : in  std_logic;
    -- regceb : in  std_logic
    );
end entity;

architecture beh of sid_coeffs is

  type mtype is array(natural range 0 to 4095) of unsigned(7 downto 0);

  constant coef_init : mtype := (
    x"d5", x"02", x"d5", x"02", x"d5", x"02", x"d5", x"02", x"d5", x"02", x"d5", x"02", x"d5", x"02", x"d5", x"02",
    x"d5", x"02", x"d5", x"02", x"d5", x"02", x"d5", x"02", x"d5", x"02", x"d5", x"02", x"d5", x"02", x"d5", x"02",
    x"d5", x"02", x"d8", x"02", x"d8", x"02", x"d8", x"02", x"d8", x"02", x"d8", x"02", x"d8", x"02", x"d8", x"02",
    x"d8", x"02", x"d8", x"02", x"d8", x"02", x"d8", x"02", x"d8", x"02", x"d8", x"02", x"d8", x"02", x"d8", x"02",
    x"d8", x"02", x"d8", x"02", x"db", x"02", x"db", x"02", x"db", x"02", x"db", x"02", x"db", x"02", x"db", x"02",
    x"db", x"02", x"db", x"02", x"db", x"02", x"db", x"02", x"db", x"02", x"db", x"02", x"db", x"02", x"db", x"02",
    x"db", x"02", x"df", x"02", x"df", x"02", x"df", x"02", x"df", x"02", x"df", x"02", x"df", x"02", x"df", x"02",
    x"df", x"02", x"df", x"02", x"df", x"02", x"df", x"02", x"df", x"02", x"df", x"02", x"df", x"02", x"df", x"02",
    x"e2", x"02", x"e2", x"02", x"e2", x"02", x"e2", x"02", x"e2", x"02", x"e2", x"02", x"e2", x"02", x"e2", x"02",
    x"e2", x"02", x"e2", x"02", x"e2", x"02", x"e2", x"02", x"e2", x"02", x"e5", x"02", x"e5", x"02", x"e5", x"02",
    x"e5", x"02", x"e5", x"02", x"e5", x"02", x"e5", x"02", x"e5", x"02", x"e5", x"02", x"e5", x"02", x"e5", x"02",
    x"e5", x"02", x"e8", x"02", x"e8", x"02", x"e8", x"02", x"e8", x"02", x"e8", x"02", x"e8", x"02", x"e8", x"02",
    x"e8", x"02", x"e8", x"02", x"e8", x"02", x"e8", x"02", x"ec", x"02", x"ec", x"02", x"ec", x"02", x"ec", x"02",
    x"ec", x"02", x"ec", x"02", x"ec", x"02", x"ec", x"02", x"ec", x"02", x"ec", x"02", x"ef", x"02", x"ef", x"02",
    x"ef", x"02", x"ef", x"02", x"ef", x"02", x"ef", x"02", x"ef", x"02", x"ef", x"02", x"ef", x"02", x"ef", x"02",
    x"f2", x"02", x"f2", x"02", x"f2", x"02", x"f2", x"02", x"f2", x"02", x"f2", x"02", x"f2", x"02", x"f2", x"02",
    x"f6", x"02", x"f6", x"02", x"f6", x"02", x"f6", x"02", x"f6", x"02", x"f6", x"02", x"f6", x"02", x"f6", x"02",
    x"f6", x"02", x"f9", x"02", x"f9", x"02", x"f9", x"02", x"f9", x"02", x"f9", x"02", x"f9", x"02", x"f9", x"02",
    x"f9", x"02", x"f9", x"02", x"fc", x"02", x"fc", x"02", x"fc", x"02", x"fc", x"02", x"fc", x"02", x"fc", x"02",
    x"fc", x"02", x"fc", x"02", x"fc", x"02", x"00", x"03", x"00", x"03", x"00", x"03", x"00", x"03", x"00", x"03",
    x"00", x"03", x"00", x"03", x"00", x"03", x"00", x"03", x"03", x"03", x"03", x"03", x"03", x"03", x"03", x"03",
    x"03", x"03", x"03", x"03", x"03", x"03", x"03", x"03", x"03", x"03", x"06", x"03", x"06", x"03", x"06", x"03",
    x"06", x"03", x"06", x"03", x"06", x"03", x"06", x"03", x"06", x"03", x"09", x"03", x"09", x"03", x"09", x"03",
    x"09", x"03", x"09", x"03", x"09", x"03", x"09", x"03", x"09", x"03", x"0d", x"03", x"0d", x"03", x"0d", x"03",
    x"0d", x"03", x"0d", x"03", x"0d", x"03", x"0d", x"03", x"10", x"03", x"10", x"03", x"10", x"03", x"10", x"03",
    x"10", x"03", x"10", x"03", x"10", x"03", x"13", x"03", x"13", x"03", x"13", x"03", x"13", x"03", x"13", x"03",
    x"13", x"03", x"17", x"03", x"17", x"03", x"17", x"03", x"17", x"03", x"17", x"03", x"17", x"03", x"1a", x"03",
    x"1a", x"03", x"1a", x"03", x"1a", x"03", x"1a", x"03", x"1a", x"03", x"1d", x"03", x"1d", x"03", x"1d", x"03",
    x"1d", x"03", x"1d", x"03", x"20", x"03", x"20", x"03", x"20", x"03", x"20", x"03", x"20", x"03", x"24", x"03",
    x"24", x"03", x"24", x"03", x"24", x"03", x"24", x"03", x"27", x"03", x"27", x"03", x"27", x"03", x"27", x"03",
    x"27", x"03", x"2a", x"03", x"2a", x"03", x"2a", x"03", x"2a", x"03", x"2e", x"03", x"2e", x"03", x"2e", x"03",
    x"2e", x"03", x"31", x"03", x"31", x"03", x"31", x"03", x"31", x"03", x"34", x"03", x"34", x"03", x"34", x"03",
    x"38", x"03", x"38", x"03", x"38", x"03", x"38", x"03", x"3b", x"03", x"3b", x"03", x"3b", x"03", x"3b", x"03",
    x"3e", x"03", x"3e", x"03", x"3e", x"03", x"3e", x"03", x"41", x"03", x"41", x"03", x"41", x"03", x"45", x"03",
    x"45", x"03", x"45", x"03", x"45", x"03", x"48", x"03", x"48", x"03", x"48", x"03", x"48", x"03", x"4b", x"03",
    x"4b", x"03", x"4b", x"03", x"4f", x"03", x"4f", x"03", x"4f", x"03", x"4f", x"03", x"52", x"03", x"52", x"03",
    x"52", x"03", x"55", x"03", x"55", x"03", x"55", x"03", x"55", x"03", x"58", x"03", x"58", x"03", x"58", x"03",
    x"5c", x"03", x"5c", x"03", x"5c", x"03", x"5c", x"03", x"5f", x"03", x"5f", x"03", x"5f", x"03", x"62", x"03",
    x"62", x"03", x"62", x"03", x"66", x"03", x"66", x"03", x"66", x"03", x"69", x"03", x"69", x"03", x"69", x"03",
    x"6c", x"03", x"6c", x"03", x"6c", x"03", x"70", x"03", x"70", x"03", x"70", x"03", x"73", x"03", x"73", x"03",
    x"73", x"03", x"76", x"03", x"76", x"03", x"76", x"03", x"79", x"03", x"79", x"03", x"79", x"03", x"7d", x"03",
    x"7d", x"03", x"80", x"03", x"80", x"03", x"80", x"03", x"83", x"03", x"83", x"03", x"83", x"03", x"87", x"03",
    x"87", x"03", x"8a", x"03", x"8a", x"03", x"8d", x"03", x"8d", x"03", x"8d", x"03", x"90", x"03", x"90", x"03",
    x"94", x"03", x"94", x"03", x"97", x"03", x"97", x"03", x"97", x"03", x"9a", x"03", x"9a", x"03", x"9e", x"03",
    x"9e", x"03", x"a1", x"03", x"a1", x"03", x"a4", x"03", x"a4", x"03", x"a8", x"03", x"a8", x"03", x"ab", x"03",
    x"ab", x"03", x"ae", x"03", x"ae", x"03", x"b1", x"03", x"b1", x"03", x"b5", x"03", x"b8", x"03", x"b8", x"03",
    x"bb", x"03", x"bb", x"03", x"bf", x"03", x"bf", x"03", x"c2", x"03", x"c5", x"03", x"c5", x"03", x"c8", x"03",
    x"c8", x"03", x"cc", x"03", x"cf", x"03", x"cf", x"03", x"d2", x"03", x"d6", x"03", x"d6", x"03", x"d9", x"03",
    x"dc", x"03", x"dc", x"03", x"e0", x"03", x"e0", x"03", x"e3", x"03", x"e6", x"03", x"e6", x"03", x"e9", x"03",
    x"ed", x"03", x"ed", x"03", x"f0", x"03", x"f0", x"03", x"f3", x"03", x"f7", x"03", x"f7", x"03", x"fa", x"03",
    x"fd", x"03", x"fd", x"03", x"00", x"04", x"00", x"04", x"04", x"04", x"04", x"04", x"07", x"04", x"0a", x"04",
    x"0a", x"04", x"0e", x"04", x"0e", x"04", x"11", x"04", x"14", x"04", x"14", x"04", x"18", x"04", x"18", x"04",
    x"1b", x"04", x"1e", x"04", x"1e", x"04", x"21", x"04", x"21", x"04", x"25", x"04", x"28", x"04", x"28", x"04",
    x"2b", x"04", x"2b", x"04", x"2f", x"04", x"32", x"04", x"32", x"04", x"35", x"04", x"38", x"04", x"38", x"04",
    x"3c", x"04", x"3c", x"04", x"3f", x"04", x"42", x"04", x"42", x"04", x"46", x"04", x"49", x"04", x"4c", x"04",
    x"4c", x"04", x"50", x"04", x"53", x"04", x"53", x"04", x"56", x"04", x"59", x"04", x"5d", x"04", x"5d", x"04",
    x"60", x"04", x"63", x"04", x"67", x"04", x"67", x"04", x"6a", x"04", x"6d", x"04", x"70", x"04", x"74", x"04",
    x"77", x"04", x"77", x"04", x"7a", x"04", x"7e", x"04", x"81", x"04", x"84", x"04", x"88", x"04", x"8b", x"04",
    x"8e", x"04", x"91", x"04", x"95", x"04", x"98", x"04", x"9b", x"04", x"9f", x"04", x"a2", x"04", x"a5", x"04",
    x"a8", x"04", x"ac", x"04", x"af", x"04", x"b2", x"04", x"b6", x"04", x"b9", x"04", x"c0", x"04", x"c3", x"04",
    x"c6", x"04", x"c9", x"04", x"cd", x"04", x"d3", x"04", x"d7", x"04", x"da", x"04", x"dd", x"04", x"e4", x"04",
    x"e7", x"04", x"ee", x"04", x"f1", x"04", x"f4", x"04", x"fb", x"04", x"fe", x"04", x"05", x"05", x"08", x"05",
    x"0f", x"05", x"12", x"05", x"19", x"05", x"1c", x"05", x"22", x"05", x"26", x"05", x"2c", x"05", x"33", x"05",
    x"36", x"05", x"3d", x"05", x"43", x"05", x"47", x"05", x"4d", x"05", x"54", x"05", x"5a", x"05", x"61", x"05",
    x"68", x"05", x"6b", x"05", x"71", x"05", x"78", x"05", x"7f", x"05", x"85", x"05", x"8c", x"05", x"92", x"05",
    x"99", x"05", x"9c", x"05", x"a3", x"05", x"a9", x"05", x"b0", x"05", x"b7", x"05", x"bd", x"05", x"c4", x"05",
    x"ca", x"05", x"d1", x"05", x"d8", x"05", x"de", x"05", x"e5", x"05", x"eb", x"05", x"f2", x"05", x"f9", x"05",
    x"ff", x"05", x"06", x"06", x"0c", x"06", x"13", x"06", x"19", x"06", x"20", x"06", x"27", x"06", x"2d", x"06",
    x"34", x"06", x"3a", x"06", x"41", x"06", x"48", x"06", x"4e", x"06", x"55", x"06", x"5f", x"06", x"65", x"06",
    x"6c", x"06", x"72", x"06", x"79", x"06", x"80", x"06", x"89", x"06", x"90", x"06", x"97", x"06", x"9d", x"06",
    x"a7", x"06", x"ae", x"06", x"b4", x"06", x"be", x"06", x"c5", x"06", x"cb", x"06", x"d5", x"06", x"dc", x"06",
    x"e6", x"06", x"ec", x"06", x"f6", x"06", x"fd", x"06", x"07", x"07", x"0d", x"07", x"17", x"07", x"1e", x"07",
    x"28", x"07", x"2e", x"07", x"38", x"07", x"42", x"07", x"49", x"07", x"52", x"07", x"5c", x"07", x"63", x"07",
    x"6d", x"07", x"77", x"07", x"81", x"07", x"8a", x"07", x"94", x"07", x"9b", x"07", x"a5", x"07", x"af", x"07",
    x"b9", x"07", x"c2", x"07", x"cc", x"07", x"d6", x"07", x"e0", x"07", x"ea", x"07", x"f7", x"07", x"01", x"08",
    x"0b", x"08", x"15", x"08", x"1f", x"08", x"2c", x"08", x"36", x"08", x"40", x"08", x"4d", x"08", x"57", x"08",
    x"64", x"08", x"6e", x"08", x"78", x"08", x"85", x"08", x"92", x"08", x"9c", x"08", x"a9", x"08", x"b3", x"08",
    x"c0", x"08", x"cd", x"08", x"da", x"08", x"e4", x"08", x"f1", x"08", x"ff", x"08", x"0c", x"09", x"19", x"09",
    x"26", x"09", x"33", x"09", x"41", x"09", x"4e", x"09", x"5b", x"09", x"68", x"09", x"75", x"09", x"86", x"09",
    x"93", x"09", x"a0", x"09", x"b1", x"09", x"be", x"09", x"cb", x"09", x"db", x"09", x"e9", x"09", x"f9", x"09",
    x"09", x"0a", x"17", x"0a", x"27", x"0a", x"34", x"0a", x"45", x"0a", x"55", x"0a", x"66", x"0a", x"76", x"0a",
    x"83", x"0a", x"94", x"0a", x"a4", x"0a", x"b5", x"0a", x"c5", x"0a", x"d6", x"0a", x"e6", x"0a", x"f7", x"0a",
    x"07", x"0b", x"18", x"0b", x"2b", x"0b", x"3c", x"0b", x"4c", x"0b", x"5d", x"0b", x"71", x"0b", x"81", x"0b",
    x"91", x"0b", x"a5", x"0b", x"b6", x"0b", x"c6", x"0b", x"da", x"0b", x"ea", x"0b", x"fe", x"0b", x"12", x"0c",
    x"22", x"0c", x"36", x"0c", x"47", x"0c", x"5a", x"0c", x"6e", x"0c", x"7f", x"0c", x"92", x"0c", x"a6", x"0c",
    x"ba", x"0c", x"ce", x"0c", x"e1", x"0c", x"f2", x"0c", x"06", x"0d", x"19", x"0d", x"2d", x"0d", x"41", x"0d",
    x"55", x"0d", x"69", x"0d", x"7c", x"0d", x"93", x"0d", x"a7", x"0d", x"bb", x"0d", x"cf", x"0d", x"e2", x"0d",
    x"f9", x"0d", x"0d", x"0e", x"21", x"0e", x"38", x"0e", x"4c", x"0e", x"60", x"0e", x"77", x"0e", x"8a", x"0e",
    x"a2", x"0e", x"b5", x"0e", x"cc", x"0e", x"e0", x"0e", x"f7", x"0e", x"0b", x"0f", x"22", x"0f", x"39", x"0f",
    x"4d", x"0f", x"64", x"0f", x"7b", x"0f", x"8f", x"0f", x"a6", x"0f", x"bd", x"0f", x"d4", x"0f", x"eb", x"0f",
    x"ff", x"0f", x"16", x"10", x"2d", x"10", x"44", x"10", x"5b", x"10", x"72", x"10", x"89", x"10", x"a0", x"10",
    x"b7", x"10", x"ce", x"10", x"e5", x"10", x"00", x"11", x"17", x"11", x"2e", x"11", x"45", x"11", x"5c", x"11",
    x"76", x"11", x"8d", x"11", x"a4", x"11", x"bb", x"11", x"d6", x"11", x"ed", x"11", x"04", x"12", x"1e", x"12",
    x"35", x"12", x"50", x"12", x"67", x"12", x"81", x"12", x"98", x"12", x"b2", x"12", x"ca", x"12", x"e4", x"12",
    x"fb", x"12", x"15", x"13", x"30", x"13", x"47", x"13", x"61", x"13", x"7b", x"13", x"92", x"13", x"ad", x"13",
    x"c7", x"13", x"e2", x"13", x"f9", x"13", x"13", x"14", x"2d", x"14", x"48", x"14", x"62", x"14", x"7c", x"14",
    x"97", x"14", x"ae", x"14", x"cb", x"14", x"e6", x"14", x"00", x"15", x"1e", x"15", x"38", x"15", x"56", x"15",
    x"73", x"15", x"91", x"15", x"af", x"15", x"d0", x"15", x"ed", x"15", x"0b", x"16", x"2c", x"16", x"4d", x"16",
    x"6e", x"16", x"8f", x"16", x"b0", x"16", x"d1", x"16", x"f2", x"16", x"12", x"17", x"37", x"17", x"58", x"17",
    x"7c", x"17", x"a0", x"17", x"c1", x"17", x"e5", x"17", x"0a", x"18", x"2e", x"18", x"52", x"18", x"7a", x"18",
    x"9e", x"18", x"c2", x"18", x"ea", x"18", x"0e", x"19", x"35", x"19", x"5a", x"19", x"81", x"19", x"a9", x"19",
    x"cd", x"19", x"f4", x"19", x"1c", x"1a", x"43", x"1a", x"6b", x"1a", x"93", x"1a", x"ba", x"1a", x"e2", x"1a",
    x"09", x"1b", x"34", x"1b", x"5b", x"1b", x"83", x"1b", x"ab", x"1b", x"d5", x"1b", x"fd", x"1b", x"24", x"1c",
    x"4f", x"1c", x"77", x"1c", x"a2", x"1c", x"c9", x"1c", x"f4", x"1c", x"1b", x"1d", x"46", x"1d", x"6e", x"1d",
    x"99", x"1d", x"c0", x"1d", x"eb", x"1d", x"13", x"1e", x"3d", x"1e", x"68", x"1e", x"90", x"1e", x"bb", x"1e",
    x"e5", x"1e", x"10", x"1f", x"3b", x"1f", x"66", x"1f", x"91", x"1f", x"bb", x"1f", x"e6", x"1f", x"11", x"20",
    x"3f", x"20", x"6a", x"20", x"95", x"20", x"c3", x"20", x"ee", x"20", x"1c", x"21", x"47", x"21", x"75", x"21",
    x"a3", x"21", x"ce", x"21", x"fc", x"21", x"2a", x"22", x"58", x"22", x"86", x"22", x"b1", x"22", x"df", x"22",
    x"11", x"23", x"3f", x"23", x"6d", x"23", x"9b", x"23", x"c9", x"23", x"f7", x"23", x"29", x"24", x"57", x"24",
    x"88", x"24", x"b6", x"24", x"e8", x"24", x"16", x"25", x"47", x"25", x"75", x"25", x"a7", x"25", x"d8", x"25",
    x"0a", x"26", x"3b", x"26", x"6c", x"26", x"9e", x"26", x"cf", x"26", x"01", x"27", x"32", x"27", x"64", x"27",
    x"95", x"27", x"c6", x"27", x"fb", x"27", x"2c", x"28", x"5e", x"28", x"93", x"28", x"c4", x"28", x"f9", x"28",
    x"2d", x"29", x"5f", x"29", x"94", x"29", x"c8", x"29", x"fa", x"29", x"2e", x"2a", x"63", x"2a", x"98", x"2a",
    x"cd", x"2a", x"01", x"2b", x"36", x"2b", x"6b", x"2b", x"a3", x"2b", x"d7", x"2b", x"0c", x"2c", x"41", x"2c",
    x"79", x"2c", x"ad", x"2c", x"e5", x"2c", x"1a", x"2d", x"52", x"2d", x"87", x"2d", x"bf", x"2d", x"f7", x"2d",
    x"2f", x"2e", x"64", x"2e", x"9c", x"2e", x"d4", x"2e", x"0c", x"2f", x"44", x"2f", x"7c", x"2f", x"b4", x"2f",
    x"ef", x"2f", x"27", x"30", x"5f", x"30", x"97", x"30", x"d2", x"30", x"0a", x"31", x"45", x"31", x"7d", x"31",
    x"b9", x"31", x"f1", x"31", x"2c", x"32", x"67", x"32", x"9f", x"32", x"db", x"32", x"16", x"33", x"51", x"33",
    x"8d", x"33", x"c8", x"33", x"03", x"34", x"3e", x"34", x"7a", x"34", x"b5", x"34", x"f0", x"34", x"2f", x"35",
    x"6a", x"35", x"a6", x"35", x"e4", x"35", x"1f", x"36", x"5e", x"36", x"99", x"36", x"d8", x"36", x"16", x"37",
    x"55", x"37", x"90", x"37", x"d2", x"37", x"11", x"38", x"53", x"38", x"95", x"38", x"d6", x"38", x"1c", x"39",
    x"61", x"39", x"a6", x"39", x"eb", x"39", x"34", x"3a", x"79", x"3a", x"c1", x"3a", x"0a", x"3b", x"56", x"3b",
    x"9e", x"3b", x"e6", x"3b", x"32", x"3c", x"7e", x"3c", x"c7", x"3c", x"12", x"3d", x"5e", x"3d", x"aa", x"3d",
    x"f6", x"3d", x"41", x"3e", x"8d", x"3e", x"d9", x"3e", x"25", x"3f", x"74", x"3f", x"bf", x"3f", x"0b", x"40",
    x"57", x"40", x"9f", x"40", x"eb", x"40", x"37", x"41", x"86", x"41", x"d2", x"41", x"21", x"42", x"70", x"42",
    x"bf", x"42", x"11", x"43", x"64", x"43", x"b6", x"43", x"0f", x"44", x"65", x"44", x"c1", x"44", x"1d", x"45",
    x"7d", x"45", x"df", x"45", x"50", x"46", x"c6", x"46", x"47", x"47", x"c7", x"47", x"4e", x"48", x"d2", x"48",
    x"59", x"49", x"dd", x"49", x"67", x"4a", x"f1", x"4a", x"7f", x"4b", x"10", x"4c", x"a1", x"4c", x"35", x"4d",
    x"31", x"3b", x"87", x"3b", x"dd", x"3b", x"36", x"3c", x"88", x"3c", x"da", x"3c", x"2d", x"3d", x"78", x"3d",
    x"c4", x"3d", x"09", x"3e", x"52", x"3e", x"97", x"3e", x"dc", x"3e", x"21", x"3f", x"67", x"3f", x"ac", x"3f",
    x"f1", x"3f", x"33", x"40", x"78", x"40", x"ba", x"40", x"ff", x"40", x"41", x"41", x"86", x"41", x"c8", x"41",
    x"0d", x"42", x"4f", x"42", x"94", x"42", x"d6", x"42", x"1b", x"43", x"60", x"43", x"a6", x"43", x"eb", x"43",
    x"33", x"44", x"78", x"44", x"c1", x"44", x"06", x"45", x"4f", x"45", x"97", x"45", x"df", x"45", x"2b", x"46",
    x"74", x"46", x"bc", x"46", x"05", x"47", x"50", x"47", x"99", x"47", x"e5", x"47", x"2d", x"48", x"79", x"48",
    x"c1", x"48", x"0a", x"49", x"56", x"49", x"9e", x"49", x"e7", x"49", x"2f", x"4a", x"78", x"4a", x"c0", x"4a",
    x"08", x"4b", x"51", x"4b", x"96", x"4b", x"db", x"4b", x"24", x"4c", x"69", x"4c", x"ab", x"4c", x"f0", x"4c",
    x"35", x"4d", x"77", x"4d", x"b9", x"4d", x"fb", x"4d", x"39", x"4e", x"7b", x"4e", x"ba", x"4e", x"f8", x"4e",
    x"3a", x"4f", x"79", x"4f", x"b4", x"4f", x"f3", x"4f", x"31", x"50", x"6d", x"50", x"ab", x"50", x"e7", x"50",
    x"25", x"51", x"61", x"51", x"9c", x"51", x"da", x"51", x"16", x"52", x"51", x"52", x"8c", x"52", x"cb", x"52",
    x"06", x"53", x"41", x"53", x"7d", x"53", x"bb", x"53", x"f7", x"53", x"35", x"54", x"71", x"54", x"af", x"54",
    x"ee", x"54", x"29", x"55", x"68", x"55", x"a6", x"55", x"e5", x"55", x"23", x"56", x"62", x"56", x"9d", x"56",
    x"dc", x"56", x"1a", x"57", x"59", x"57", x"98", x"57", x"d6", x"57", x"15", x"58", x"53", x"58", x"92", x"58",
    x"d1", x"58", x"0f", x"59", x"4e", x"59", x"8c", x"59", x"c8", x"59", x"06", x"5a", x"45", x"5a", x"83", x"5a",
    x"bf", x"5a", x"fd", x"5a", x"39", x"5b", x"77", x"5b", x"b2", x"5b", x"f1", x"5b", x"2c", x"5c", x"68", x"5c",
    x"a6", x"5c", x"e2", x"5c", x"1d", x"5d", x"58", x"5d", x"93", x"5d", x"cf", x"5d", x"0a", x"5e", x"45", x"5e",
    x"81", x"5e", x"bc", x"5e", x"f7", x"5e", x"32", x"5f", x"6e", x"5f", x"a9", x"5f", x"e4", x"5f", x"20", x"60",
    x"5b", x"60", x"93", x"60", x"ce", x"60", x"0a", x"61", x"45", x"61", x"80", x"61", x"bb", x"61", x"f7", x"61",
    x"2f", x"62", x"6a", x"62", x"a5", x"62", x"e1", x"62", x"1c", x"63", x"54", x"63", x"8f", x"63", x"cb", x"63",
    x"06", x"64", x"3e", x"64", x"79", x"64", x"b4", x"64", x"f0", x"64", x"28", x"65", x"63", x"65", x"9e", x"65",
    x"d6", x"65", x"12", x"66", x"4d", x"66", x"88", x"66", x"c0", x"66", x"fb", x"66", x"37", x"67", x"6f", x"67",
    x"aa", x"67", x"e5", x"67", x"21", x"68", x"59", x"68", x"94", x"68", x"cf", x"68", x"07", x"69", x"43", x"69",
    x"7e", x"69", x"b6", x"69", x"f1", x"69", x"2c", x"6a", x"68", x"6a", x"a0", x"6a", x"db", x"6a", x"16", x"6b",
    x"52", x"6b", x"8a", x"6b", x"c5", x"6b", x"00", x"6c", x"38", x"6c", x"74", x"6c", x"af", x"6c", x"ea", x"6c",
    x"25", x"6d", x"5d", x"6d", x"99", x"6d", x"d4", x"6d", x"0f", x"6e", x"4b", x"6e", x"83", x"6e", x"be", x"6e",
    x"f9", x"6e", x"34", x"6f", x"70", x"6f", x"ab", x"6f", x"e6", x"6f", x"22", x"70", x"5a", x"70", x"95", x"70",
    x"d0", x"70", x"0c", x"71", x"47", x"71", x"82", x"71", x"bd", x"71", x"f9", x"71", x"34", x"72", x"6f", x"72",
    x"ab", x"72", x"e6", x"72", x"24", x"73", x"60", x"73", x"9b", x"73", x"d6", x"73", x"12", x"74", x"4d", x"74",
    x"88", x"74", x"c7", x"74", x"02", x"75", x"3d", x"75", x"79", x"75", x"b7", x"75", x"f3", x"75", x"2e", x"76",
    x"6d", x"76", x"a8", x"76", x"e3", x"76", x"22", x"77", x"5d", x"77", x"9c", x"77", x"d7", x"77", x"15", x"78",
    x"51", x"78", x"8f", x"78", x"cb", x"78", x"09", x"79", x"48", x"79", x"83", x"79", x"c2", x"79", x"00", x"7a",
    x"3f", x"7a", x"7a", x"7a", x"b9", x"7a", x"f7", x"7a", x"36", x"7b", x"75", x"7b", x"b0", x"7b", x"ee", x"7b",
    x"2d", x"7c", x"6c", x"7c", x"aa", x"7c", x"e9", x"7c", x"27", x"7d", x"66", x"7d", x"a5", x"7d", x"e3", x"7d",
    x"22", x"7e", x"64", x"7e", x"a2", x"7e", x"e1", x"7e", x"1f", x"7f", x"5e", x"7f", x"9d", x"7f", x"de", x"7f",
    x"1d", x"80", x"5c", x"80", x"9a", x"80", x"dc", x"80", x"1b", x"81", x"59", x"81", x"9b", x"81", x"da", x"81",
    x"18", x"82", x"5a", x"82", x"99", x"82", x"db", x"82", x"19", x"83", x"5b", x"83", x"9a", x"83", x"d8", x"83",
    x"1a", x"84", x"59", x"84", x"9b", x"84", x"dd", x"84", x"1b", x"85", x"5d", x"85", x"9c", x"85", x"de", x"85",
    x"1c", x"86", x"5e", x"86", x"a0", x"86", x"de", x"86", x"20", x"87", x"5f", x"87", x"a1", x"87", x"e3", x"87",
    x"21", x"88", x"63", x"88", x"a5", x"88", x"e4", x"88", x"26", x"89", x"67", x"89", x"a9", x"89", x"e8", x"89",
    x"2a", x"8a", x"6c", x"8a", x"aa", x"8a", x"ec", x"8a", x"2e", x"8b", x"70", x"8b", x"af", x"8b", x"f0", x"8b",
    x"32", x"8c", x"74", x"8c", x"b6", x"8c", x"f5", x"8c", x"37", x"8d", x"78", x"8d", x"ba", x"8d", x"f9", x"8d",
    x"3b", x"8e", x"7d", x"8e", x"bf", x"8e", x"00", x"8f", x"3f", x"8f", x"81", x"8f", x"c3", x"8f", x"05", x"90",
    x"47", x"90", x"85", x"90", x"c7", x"90", x"09", x"91", x"4b", x"91", x"89", x"91", x"cb", x"91", x"0d", x"92",
    x"4f", x"92", x"91", x"92", x"d0", x"92", x"11", x"93", x"53", x"93", x"95", x"93", x"d4", x"93", x"16", x"94",
    x"58", x"94", x"99", x"94", x"d8", x"94", x"1a", x"95", x"5c", x"95", x"9e", x"95", x"dc", x"95", x"1e", x"96",
    x"60", x"96", x"9f", x"96", x"e0", x"96", x"22", x"97", x"61", x"97", x"a3", x"97", x"e5", x"97", x"23", x"98",
    x"65", x"98", x"a4", x"98", x"e6", x"98", x"28", x"99", x"66", x"99", x"a8", x"99", x"e7", x"99", x"28", x"9a",
    x"6a", x"9a", x"a9", x"9a", x"eb", x"9a", x"29", x"9b", x"6b", x"9b", x"ad", x"9b", x"ef", x"9b", x"31", x"9c",
    x"73", x"9c", x"b5", x"9c", x"f7", x"9c", x"39", x"9d", x"7a", x"9d", x"bc", x"9d", x"fe", x"9d", x"43", x"9e",
    x"85", x"9e", x"c7", x"9e", x"0c", x"9f", x"4e", x"9f", x"90", x"9f", x"d5", x"9f", x"17", x"a0", x"5c", x"a0",
    x"a1", x"a0", x"e3", x"a0", x"29", x"a1", x"6a", x"a1", x"b0", x"a1", x"f5", x"a1", x"37", x"a2", x"7c", x"a2",
    x"c1", x"a2", x"06", x"a3", x"48", x"a3", x"8d", x"a3", x"d2", x"a3", x"18", x"a4", x"5d", x"a4", x"9f", x"a4",
    x"e4", x"a4", x"29", x"a5", x"6e", x"a5", x"b3", x"a5", x"f9", x"a5", x"3a", x"a6", x"80", x"a6", x"c5", x"a6",
    x"0a", x"a7", x"4f", x"a7", x"94", x"a7", x"d6", x"a7", x"1b", x"a8", x"61", x"a8", x"a6", x"a8", x"e8", x"a8",
    x"2d", x"a9", x"72", x"a9", x"b4", x"a9", x"f9", x"a9", x"3e", x"aa", x"80", x"aa", x"c5", x"aa", x"07", x"ab",
    x"4c", x"ab", x"8e", x"ab", x"d3", x"ab", x"15", x"ac", x"5a", x"ac", x"9c", x"ac", x"de", x"ac", x"23", x"ad",
    x"65", x"ad", x"a7", x"ad", x"e9", x"ad", x"2b", x"ae", x"6d", x"ae", x"af", x"ae", x"f1", x"ae", x"33", x"af",
    x"74", x"af", x"b6", x"af", x"f8", x"af", x"3a", x"b0", x"79", x"b0", x"bb", x"b0", x"f9", x"b0", x"3b", x"b1",
    x"7a", x"b1", x"b8", x"b1", x"fa", x"b1", x"39", x"b2", x"77", x"b2", x"b6", x"b2", x"f4", x"b2", x"33", x"b3",
    x"72", x"b3", x"b0", x"b3", x"eb", x"b3", x"2a", x"b4", x"65", x"b4", x"a4", x"b4", x"df", x"b4", x"1b", x"b5",
    x"59", x"b5", x"94", x"b5", x"d0", x"b5", x"0b", x"b6", x"43", x"b6", x"7e", x"b6", x"ba", x"b6", x"f2", x"b6",
    x"2d", x"b7", x"65", x"b7", x"9d", x"b7", x"d8", x"b7", x"10", x"b8", x"48", x"b8", x"7d", x"b8", x"b5", x"b8",
    x"ed", x"b8", x"22", x"b9", x"5a", x"b9", x"8e", x"b9", x"c3", x"b9", x"f8", x"b9", x"2c", x"ba", x"61", x"ba",
    x"96", x"ba", x"c7", x"ba", x"fc", x"ba", x"2d", x"bb", x"5f", x"bb", x"90", x"bb", x"c5", x"bb", x"f6", x"bb",
    x"24", x"bc", x"56", x"bc", x"87", x"bc", x"b9", x"bc", x"e7", x"bc", x"18", x"bd", x"46", x"bd", x"74", x"bd",
    x"a6", x"bd", x"d4", x"bd", x"02", x"be", x"30", x"be", x"5e", x"be", x"89", x"be", x"b7", x"be", x"e5", x"be",
    x"10", x"bf", x"3e", x"bf", x"69", x"bf", x"97", x"bf", x"c2", x"bf", x"ed", x"bf", x"18", x"c0", x"43", x"c0",
    x"6d", x"c0", x"98", x"c0", x"c3", x"c0", x"ee", x"c0", x"15", x"c1", x"40", x"c1", x"6b", x"c1", x"93", x"c1",
    x"bd", x"c1", x"e5", x"c1", x"0d", x"c2", x"34", x"c2", x"5f", x"c2", x"86", x"c2", x"ae", x"c2", x"d5", x"c2",
    x"fd", x"c2", x"25", x"c3", x"4c", x"c3", x"70", x"c3", x"98", x"c3", x"bf", x"c3", x"e4", x"c3", x"0b", x"c4",
    x"2f", x"c4", x"57", x"c4", x"7b", x"c4", x"a3", x"c4", x"c7", x"c4", x"eb", x"c4", x"13", x"c5", x"37", x"c5",
    x"5b", x"c5", x"7f", x"c5", x"a4", x"c5", x"c8", x"c5", x"ec", x"c5", x"10", x"c6", x"35", x"c6", x"59", x"c6",
    x"7d", x"c6", x"a1", x"c6", x"c2", x"c6", x"e6", x"c6", x"0b", x"c7", x"2c", x"c7", x"50", x"c7", x"74", x"c7",
    x"95", x"c7", x"b9", x"c7", x"da", x"c7", x"fe", x"c7", x"1f", x"c8", x"44", x"c8", x"65", x"c8", x"85", x"c8",
    x"aa", x"c8", x"cb", x"c8", x"ef", x"c8", x"10", x"c9", x"31", x"c9", x"52", x"c9", x"76", x"c9", x"97", x"c9",
    x"b8", x"c9", x"d9", x"c9", x"fa", x"c9", x"1e", x"ca", x"3f", x"ca", x"60", x"ca", x"81", x"ca", x"a2", x"ca",
    x"c3", x"ca", x"e4", x"ca", x"05", x"cb", x"29", x"cb", x"4a", x"cb", x"6b", x"cb", x"8c", x"cb", x"ad", x"cb",
    x"ce", x"cb", x"ee", x"cb", x"0f", x"cc", x"30", x"cc", x"51", x"cc", x"72", x"cc", x"93", x"cc", x"b4", x"cc",
    x"d8", x"cc", x"f9", x"cc", x"1a", x"cd", x"3b", x"cd", x"5c", x"cd", x"7d", x"cd", x"9e", x"cd", x"bf", x"cd",
    x"e3", x"cd", x"04", x"ce", x"25", x"ce", x"46", x"ce", x"67", x"ce", x"88", x"ce", x"a9", x"ce", x"ca", x"ce",
    x"eb", x"ce", x"0c", x"cf", x"2d", x"cf", x"4e", x"cf", x"6e", x"cf", x"8f", x"cf", x"b0", x"cf", x"d1", x"cf",
    x"f2", x"cf", x"10", x"d0", x"31", x"d0", x"52", x"d0", x"73", x"d0", x"94", x"d0", x"b1", x"d0", x"d2", x"d0",
    x"f3", x"d0", x"11", x"d1", x"32", x"d1", x"53", x"d1", x"70", x"d1", x"91", x"d1", x"af", x"d1", x"d0", x"d1",
    x"ee", x"d1", x"0e", x"d2", x"2c", x"d2", x"4d", x"d2", x"6b", x"d2", x"8c", x"d2", x"a9", x"d2", x"c7", x"d2",
    x"e8", x"d2", x"06", x"d3", x"23", x"d3", x"41", x"d3", x"62", x"d3", x"7f", x"d3", x"9d", x"d3", x"bb", x"d3",
    x"d8", x"d3", x"f6", x"d3", x"14", x"d4", x"31", x"d4", x"52", x"d4", x"70", x"d4", x"8a", x"d4", x"a8", x"d4",
    x"c6", x"d4", x"e3", x"d4", x"01", x"d5", x"1f", x"d5", x"3c", x"d5", x"5a", x"d5", x"74", x"d5", x"92", x"d5",
    x"af", x"d5", x"ca", x"d5", x"e7", x"d5", x"05", x"d6", x"1f", x"d6", x"3d", x"d6", x"57", x"d6", x"75", x"d6",
    x"8f", x"d6", x"ad", x"d6", x"c7", x"d6", x"e5", x"d6", x"ff", x"d6", x"1a", x"d7", x"37", x"d7", x"52", x"d7",
    x"6c", x"d7", x"87", x"d7", x"a4", x"d7", x"bf", x"d7", x"d9", x"d7", x"f3", x"d7", x"0e", x"d8", x"28", x"d8",
    x"42", x"d8", x"5d", x"d8", x"77", x"d8", x"91", x"d8", x"ac", x"d8", x"c6", x"d8", x"dd", x"d8", x"f7", x"d8",
    x"12", x"d9", x"2c", x"d9", x"43", x"d9", x"5e", x"d9", x"78", x"d9", x"8f", x"d9", x"a9", x"d9", x"c0", x"d9",
    x"db", x"d9", x"f2", x"d9", x"0c", x"da", x"23", x"da", x"3e", x"da", x"55", x"da", x"6c", x"da", x"83", x"da",
    x"9d", x"da", x"b4", x"da", x"cb", x"da", x"e2", x"da", x"f9", x"da", x"10", x"db", x"27", x"db", x"3f", x"db",
    x"56", x"db", x"6d", x"db", x"84", x"db", x"9b", x"db", x"b2", x"db", x"c6", x"db", x"dd", x"db", x"f4", x"db",
    x"0b", x"dc", x"1f", x"dc", x"36", x"dc", x"49", x"dc", x"60", x"dc", x"74", x"dc", x"8b", x"dc", x"9f", x"dc",
    x"b3", x"dc", x"ca", x"dc", x"de", x"dc", x"f1", x"dc", x"05", x"dd", x"19", x"dd", x"2d", x"dd", x"40", x"dd",
    x"54", x"dd", x"68", x"dd", x"7c", x"dd", x"90", x"dd", x"a3", x"dd", x"b7", x"dd", x"cb", x"dd", x"db", x"dd",
    x"ef", x"dd", x"03", x"de", x"13", x"de", x"27", x"de", x"3b", x"de", x"4b", x"de", x"5f", x"de", x"70", x"de",
    x"83", x"de", x"94", x"de", x"a4", x"de", x"b8", x"de", x"c8", x"de", x"d9", x"de", x"ed", x"de", x"fd", x"de",
    x"0e", x"df", x"1e", x"df", x"2f", x"df", x"3f", x"df", x"50", x"df", x"60", x"df", x"70", x"df", x"81", x"df",
    x"91", x"df", x"a2", x"df", x"b2", x"df", x"c3", x"df", x"d3", x"df", x"e0", x"df", x"f1", x"df", x"01", x"e0",
    x"12", x"e0", x"1f", x"e0", x"30", x"e0", x"40", x"e0", x"4d", x"e0", x"5e", x"e0", x"6b", x"e0", x"7b", x"e0",
    x"88", x"e0", x"99", x"e0", x"a6", x"e0", x"b7", x"e0", x"c4", x"e0", x"d1", x"e0", x"e1", x"e0", x"ef", x"e0",
    x"fc", x"e0", x"0c", x"e1", x"19", x"e1", x"27", x"e1", x"34", x"e1", x"44", x"e1", x"51", x"e1", x"5f", x"e1",
    x"6c", x"e1", x"79", x"e1", x"86", x"e1", x"97", x"e1", x"a4", x"e1", x"b1", x"e1", x"be", x"e1", x"cb", x"e1",
    x"d8", x"e1", x"e6", x"e1", x"f3", x"e1", x"00", x"e2", x"0d", x"e2", x"17", x"e2", x"24", x"e2", x"31", x"e2",
    x"3f", x"e2", x"4c", x"e2", x"59", x"e2", x"66", x"e2", x"70", x"e2", x"7d", x"e2", x"8a", x"e2", x"98", x"e2",
    x"a1", x"e2", x"af", x"e2", x"bc", x"e2", x"c9", x"e2", x"d3", x"e2", x"e0", x"e2", x"ed", x"e2", x"f7", x"e2",
    x"04", x"e3", x"11", x"e3", x"1b", x"e3", x"28", x"e3", x"36", x"e3", x"40", x"e3", x"4d", x"e3", x"57", x"e3",
    x"64", x"e3", x"71", x"e3", x"7b", x"e3", x"88", x"e3", x"92", x"e3", x"9f", x"e3", x"a9", x"e3", x"b6", x"e3",
    x"c3", x"e3", x"cd", x"e3", x"da", x"e3", x"e4", x"e3", x"ee", x"e3", x"fb", x"e3", x"05", x"e4", x"12", x"e4",
    x"1c", x"e4", x"26", x"e4", x"30", x"e4", x"3d", x"e4", x"47", x"e4", x"51", x"e4", x"5b", x"e4", x"65", x"e4",
    x"72", x"e4", x"7c", x"e4", x"86", x"e4", x"90", x"e4", x"99", x"e4", x"a3", x"e4", x"ad", x"e4", x"b7", x"e4",
    x"c1", x"e4", x"cb", x"e4", x"d5", x"e4", x"db", x"e4", x"e5", x"e4", x"ef", x"e4", x"f9", x"e4", x"03", x"e5",
    x"0d", x"e5", x"13", x"e5", x"1d", x"e5", x"27", x"e5", x"2e", x"e5", x"38", x"e5", x"41", x"e5", x"48", x"e5",
    x"52", x"e5", x"5c", x"e5", x"62", x"e5", x"6c", x"e5", x"73", x"e5", x"7d", x"e5", x"83", x"e5", x"8d", x"e5",
    x"94", x"e5", x"9e", x"e5", x"a4", x"e5", x"ab", x"e5", x"b5", x"e5", x"bb", x"e5", x"c5", x"e5", x"cc", x"e5",
    x"d2", x"e5", x"dc", x"e5", x"e3", x"e5", x"e9", x"e5", x"f0", x"e5", x"fa", x"e5", x"01", x"e6", x"07", x"e6",
    x"0e", x"e6", x"18", x"e6", x"1e", x"e6", x"25", x"e6", x"2b", x"e6", x"32", x"e6", x"39", x"e6", x"42", x"e6",
    x"49", x"e6", x"50", x"e6", x"56", x"e6", x"5d", x"e6", x"63", x"e6", x"6a", x"e6", x"71", x"e6", x"77", x"e6",
    x"7e", x"e6", x"84", x"e6", x"8b", x"e6", x"91", x"e6", x"98", x"e6", x"9f", x"e6", x"a5", x"e6", x"ac", x"e6",
    x"b2", x"e6", x"b9", x"e6", x"c0", x"e6", x"c6", x"e6", x"cd", x"e6", x"d3", x"e6", x"da", x"e6", x"dd", x"e6",
    x"e4", x"e6", x"ea", x"e6", x"f1", x"e6", x"f8", x"e6", x"fe", x"e6", x"05", x"e7", x"08", x"e7", x"0f", x"e7",
    x"15", x"e7", x"1c", x"e7", x"22", x"e7", x"29", x"e7", x"2c", x"e7", x"33", x"e7", x"39", x"e7", x"40", x"e7",
    x"47", x"e7", x"4d", x"e7", x"51", x"e7", x"57", x"e7", x"5e", x"e7", x"64", x"e7", x"68", x"e7", x"6e", x"e7",
    x"75", x"e7", x"7b", x"e7", x"82", x"e7", x"85", x"e7", x"8c", x"e7", x"92", x"e7", x"99", x"e7", x"a0", x"e7"
    );

  shared variable coef : mtype := coef_init;
  signal douta_reg, ram_data_a : unsigned(7 downto 0) := (others => '0');
  signal doutb_reg, ram_data_b : unsigned(7 downto 0) := (others => '0');
begin
  porta: process (clka, addra, dia, ena, wea) is

  begin  -- process porta
    if rising_edge(clka) then
      if ena = '1' then
        douta <= coef(to_integer(addra));
        if wea = '1' then
          coef(to_integer(addra)) := dia;
        end if;
      end if;
    end if;
  end process porta;

  -- douta_register: process (clka) is
  -- begin  -- process douta_register
  --   if rising_edge(clka) then
  --     if regcea = '1' then
  --       douta_reg <= ram_data_a;
  --     else
  --       douta_reg <= (others => 'Z');
  --     end if;
  --   end if;
  -- end process douta_register;

  -- douta <= douta_reg;
  
  portb: process (clkb, addrb, dib, enb, web) is
    
  begin  -- process portb
    if rising_edge(clkb) then
      if enb = '1' then
        doutb <= coef(to_integer(addrb));
        if web = '1' then
          coef(to_integer(addrb)) := dib;
        end if;
      end if;
    end if;
  end process portb;
end beh;
