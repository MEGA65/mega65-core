library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

--
entity kickstart is
  port (Clk : in std_logic;
        address : in std_logic_vector(12 downto 0);
        -- Yes, we do have a write enable, because we allow modification of ROMs
        -- in the running machine, unless purposely disabled.  This gives us
        -- something like the WOM that the Amiga had.
        we : in std_logic;
        -- chip select, active low       
        cs : in std_logic;
        data_i : in std_logic_vector(7 downto 0);
        data_o : out std_logic_vector(7 downto 0)
        );
end kickstart;

architecture Behavioral of kickstart is

-- 8K x 8bit pre-initialised RAM
  type ram_t is array (0 to 8191) of std_logic_vector(7 downto 0);
  signal ram : ram_t := (
  -- 0xe000
  x"BA",x"8E",x"5A",x"CF",x"A9",x"93",x"20",x"D2",
  -- 0xe008
  x"FF",x"38",x"20",x"DC",x"C6",x"78",x"20",x"AC",
  -- 0xe010
  x"C6",x"4F",x"50",x"45",x"4E",x"49",x"4E",x"47",
  -- 0xe018
  x"20",x"53",x"44",x"43",x"41",x"52",x"44",x"2E",
  -- 0xe020
  x"2E",x"2E",x"0D",x"00",x"20",x"5E",x"C5",x"B0",
  -- 0xe028
  x"03",x"4C",x"24",x"C0",x"20",x"AC",x"C6",x"4C",
  -- 0xe030
  x"4F",x"41",x"44",x"49",x"4E",x"47",x"20",x"50",
  -- 0xe038
  x"41",x"52",x"54",x"49",x"54",x"49",x"4F",x"4E",
  -- 0xe040
  x"20",x"54",x"41",x"42",x"4C",x"45",x"2E",x"2E",
  -- 0xe048
  x"2E",x"0D",x"00",x"20",x"EC",x"C5",x"AD",x"FE",
  -- 0xe050
  x"DF",x"C9",x"55",x"D3",x"DB",x"02",x"AD",x"FF",
  -- 0xe058
  x"DF",x"C9",x"AA",x"D3",x"D3",x"02",x"A0",x"00",
  -- 0xe060
  x"AB",x"C9",x"DF",x"9C",x"0B",x"CF",x"AB",x"C8",
  -- 0xe068
  x"DF",x"9C",x"0A",x"CF",x"AB",x"C7",x"DF",x"9C",
  -- 0xe070
  x"09",x"CF",x"AB",x"C6",x"DF",x"9C",x"08",x"CF",
  -- 0xe078
  x"A2",x"03",x"BD",x"08",x"CF",x"9D",x"81",x"D6",
  -- 0xe080
  x"CA",x"10",x"F7",x"20",x"77",x"C6",x"20",x"FA",
  -- 0xe088
  x"C5",x"93",x"90",x"02",x"20",x"AC",x"C6",x"4D",
  -- 0xe090
  x"4F",x"55",x"4E",x"54",x"49",x"4E",x"47",x"20",
  -- 0xe098
  x"50",x"41",x"52",x"54",x"49",x"54",x"49",x"4F",
  -- 0xe0a0
  x"4E",x"2E",x"2E",x"2E",x"0D",x"00",x"AD",x"FE",
  -- 0xe0a8
  x"DF",x"C9",x"55",x"D3",x"83",x"02",x"AD",x"FF",
  -- 0xe0b0
  x"DF",x"C9",x"AA",x"D3",x"7B",x"02",x"AD",x"11",
  -- 0xe0b8
  x"DE",x"D3",x"75",x"02",x"A2",x"03",x"BD",x"0E",
  -- 0xe0c0
  x"DE",x"9D",x"10",x"CF",x"9D",x"0C",x"CF",x"BD",
  -- 0xe0c8
  x"2C",x"DE",x"9D",x"14",x"CF",x"CA",x"10",x"EE",
  -- 0xe0d0
  x"A9",x"00",x"8D",x"12",x"CF",x"8D",x"13",x"CF",
  -- 0xe0d8
  x"8D",x"0E",x"CF",x"8D",x"0F",x"CF",x"AC",x"10",
  -- 0xe0e0
  x"DE",x"F0",x"18",x"A2",x"00",x"18",x"08",x"28",
  -- 0xe0e8
  x"BD",x"10",x"CF",x"7D",x"24",x"DE",x"9D",x"10",
  -- 0xe0f0
  x"CF",x"08",x"E8",x"E0",x"04",x"D0",x"F0",x"28",
  -- 0xe0f8
  x"88",x"D0",x"E8",x"38",x"A2",x"03",x"BD",x"20",
  -- 0xe100
  x"DE",x"FD",x"10",x"CF",x"9D",x"1C",x"CF",x"9D",
  -- 0xe108
  x"20",x"CF",x"CA",x"10",x"F1",x"AD",x"0D",x"DE",
  -- 0xe110
  x"8D",x"24",x"CF",x"A8",x"29",x"FE",x"F0",x"14",
  -- 0xe118
  x"A2",x"03",x"18",x"BD",x"20",x"CF",x"6A",x"9D",
  -- 0xe120
  x"20",x"CF",x"CA",x"10",x"F6",x"98",x"4A",x"A8",
  -- 0xe128
  x"29",x"FE",x"D0",x"EC",x"AD",x"23",x"CF",x"0D",
  -- 0xe130
  x"22",x"CF",x"F3",x"FC",x"01",x"A2",x"03",x"BD",
  -- 0xe138
  x"2C",x"DE",x"9D",x"18",x"CF",x"9D",x"4A",x"CF",
  -- 0xe140
  x"CA",x"10",x"F4",x"20",x"AC",x"C6",x"53",x"45",
  -- 0xe148
  x"41",x"52",x"43",x"48",x"49",x"4E",x"47",x"20",
  -- 0xe150
  x"44",x"49",x"52",x"45",x"43",x"54",x"4F",x"52",
  -- 0xe158
  x"59",x"2E",x"2E",x"2E",x"0D",x"00",x"A9",x"00",
  -- 0xe160
  x"8D",x"8B",x"D6",x"20",x"78",x"C3",x"20",x"87",
  -- 0xe168
  x"C3",x"93",x"B0",x"01",x"EA",x"20",x"9C",x"C3",
  -- 0xe170
  x"93",x"79",x"01",x"A2",x"00",x"AD",x"31",x"CF",
  -- 0xe178
  x"20",x"6D",x"C3",x"C9",x"44",x"D0",x"ED",x"AD",
  -- 0xe180
  x"32",x"CF",x"20",x"6D",x"C3",x"C9",x"38",x"D0",
  -- 0xe188
  x"E3",x"AD",x"33",x"CF",x"20",x"6D",x"C3",x"C9",
  -- 0xe190
  x"31",x"D0",x"D9",x"20",x"AC",x"C6",x"4D",x"4F",
  -- 0xe198
  x"55",x"4E",x"54",x"20",x"00",x"20",x"F3",x"C5",
  -- 0xe1a0
  x"A2",x"00",x"BD",x"29",x"CF",x"DA",x"20",x"D2",
  -- 0xe1a8
  x"FF",x"FA",x"E8",x"E0",x"08",x"D0",x"F3",x"20",
  -- 0xe1b0
  x"AC",x"C6",x"3F",x"20",x"00",x"20",x"F3",x"C5",
  -- 0xe1b8
  x"58",x"20",x"E4",x"FF",x"C9",x"00",x"F0",x"F9",
  -- 0xe1c0
  x"48",x"A9",x"0D",x"20",x"D2",x"FF",x"78",x"20",
  -- 0xe1c8
  x"EC",x"C5",x"68",x"C9",x"59",x"D0",x"9D",x"20",
  -- 0xe1d0
  x"EB",x"C3",x"20",x"EE",x"C4",x"20",x"77",x"C6",
  -- 0xe1d8
  x"A2",x"03",x"BD",x"81",x"D6",x"9D",x"8C",x"D6",
  -- 0xe1e0
  x"CA",x"10",x"F7",x"20",x"EB",x"C3",x"A2",x"03",
  -- 0xe1e8
  x"BD",x"4A",x"CF",x"9D",x"4F",x"CF",x"CA",x"10",
  -- 0xe1f0
  x"F7",x"A9",x"00",x"8D",x"55",x"CF",x"8D",x"56",
  -- 0xe1f8
  x"CF",x"A9",x"40",x"8D",x"53",x"CF",x"A9",x"06",
  -- 0xe200
  x"8D",x"54",x"CF",x"AB",x"24",x"CF",x"6B",x"29",
  -- 0xe208
  x"01",x"D0",x"0C",x"6B",x"4A",x"4B",x"4E",x"54",
  -- 0xe210
  x"CF",x"6E",x"53",x"CF",x"4C",x"06",x"C2",x"A2",
  -- 0xe218
  x"03",x"BD",x"4F",x"CF",x"DD",x"4A",x"CF",x"D3",
  -- 0xe220
  x"81",x"00",x"CA",x"10",x"F4",x"EE",x"55",x"CF",
  -- 0xe228
  x"D0",x"03",x"EE",x"56",x"CF",x"18",x"AD",x"4F",
  -- 0xe230
  x"CF",x"69",x"01",x"8D",x"4F",x"CF",x"AD",x"50",
  -- 0xe238
  x"CF",x"69",x"00",x"8D",x"50",x"CF",x"AD",x"51",
  -- 0xe240
  x"CF",x"69",x"00",x"8D",x"51",x"CF",x"AD",x"52",
  -- 0xe248
  x"CF",x"69",x"00",x"8D",x"52",x"CF",x"20",x"38",
  -- 0xe250
  x"C4",x"B0",x"C4",x"AD",x"53",x"CF",x"CD",x"55",
  -- 0xe258
  x"CF",x"D0",x"25",x"AD",x"54",x"CF",x"CD",x"56",
  -- 0xe260
  x"CF",x"D0",x"1D",x"A9",x"07",x"8D",x"8B",x"D6",
  -- 0xe268
  x"18",x"20",x"DC",x"C6",x"20",x"AC",x"C6",x"44",
  -- 0xe270
  x"49",x"53",x"4B",x"20",x"4D",x"4F",x"55",x"4E",
  -- 0xe278
  x"54",x"45",x"44",x"0D",x"00",x"4C",x"EF",x"C6",
  -- 0xe280
  x"20",x"AC",x"C6",x"2E",x"44",x"38",x"31",x"20",
  -- 0xe288
  x"46",x"49",x"4C",x"45",x"20",x"48",x"41",x"53",
  -- 0xe290
  x"20",x"57",x"52",x"4F",x"4E",x"47",x"20",x"4C",
  -- 0xe298
  x"45",x"4E",x"47",x"54",x"48",x"0D",x"00",x"4C",
  -- 0xe2a0
  x"EF",x"C6",x"20",x"AC",x"C6",x"54",x"48",x"41",
  -- 0xe2a8
  x"54",x"20",x"44",x"49",x"53",x"4B",x"20",x"49",
  -- 0xe2b0
  x"4D",x"41",x"47",x"45",x"20",x"49",x"53",x"20",
  -- 0xe2b8
  x"46",x"52",x"41",x"47",x"4D",x"45",x"4E",x"54",
  -- 0xe2c0
  x"45",x"44",x"2E",x"0D",x"44",x"45",x"2D",x"46",
  -- 0xe2c8
  x"52",x"41",x"47",x"20",x"44",x"49",x"53",x"4B",
  -- 0xe2d0
  x"20",x"49",x"4D",x"41",x"47",x"45",x"20",x"42",
  -- 0xe2d8
  x"45",x"46",x"4F",x"52",x"45",x"20",x"4D",x"4F",
  -- 0xe2e0
  x"55",x"4E",x"54",x"49",x"4E",x"47",x"0D",x"00",
  -- 0xe2e8
  x"4C",x"EF",x"C6",x"20",x"AC",x"C6",x"4E",x"4F",
  -- 0xe2f0
  x"20",x"4D",x"4F",x"52",x"45",x"20",x"44",x"49",
  -- 0xe2f8
  x"53",x"4B",x"20",x"49",x"4D",x"41",x"47",x"45",
  -- 0xe300
  x"53",x"2E",x"20",x"44",x"52",x"49",x"56",x"45",
  -- 0xe308
  x"20",x"4D",x"41",x"52",x"4B",x"45",x"44",x"20",
  -- 0xe310
  x"45",x"4D",x"50",x"54",x"59",x"2E",x"0D",x"00",
  -- 0xe318
  x"4C",x"EF",x"C6",x"20",x"AC",x"C6",x"53",x"44",
  -- 0xe320
  x"2D",x"43",x"41",x"52",x"44",x"20",x"45",x"52",
  -- 0xe328
  x"52",x"4F",x"52",x"0D",x"00",x"4C",x"EF",x"C6",
  -- 0xe330
  x"20",x"AC",x"C6",x"49",x"4E",x"56",x"41",x"4C",
  -- 0xe338
  x"49",x"44",x"20",x"4F",x"52",x"20",x"55",x"4E",
  -- 0xe340
  x"53",x"55",x"50",x"50",x"4F",x"52",x"54",x"45",
  -- 0xe348
  x"44",x"20",x"46",x"49",x"4C",x"45",x"20",x"53",
  -- 0xe350
  x"59",x"53",x"54",x"45",x"4D",x"2E",x"0D",x"28",
  -- 0xe358
  x"53",x"48",x"4F",x"55",x"4C",x"44",x"20",x"42",
  -- 0xe360
  x"45",x"20",x"46",x"41",x"54",x"33",x"32",x"29",
  -- 0xe368
  x"0D",x"00",x"4C",x"EF",x"C6",x"C9",x"60",x"90",
  -- 0xe370
  x"06",x"C9",x"7A",x"B0",x"02",x"29",x"5F",x"60",
  -- 0xe378
  x"A2",x"00",x"BD",x"18",x"CF",x"9D",x"25",x"CF",
  -- 0xe380
  x"E8",x"E0",x"04",x"D0",x"F5",x"38",x"60",x"A2",
  -- 0xe388
  x"00",x"BD",x"25",x"CF",x"9D",x"4A",x"CF",x"E8",
  -- 0xe390
  x"E0",x"04",x"D0",x"F5",x"A9",x"00",x"8D",x"49",
  -- 0xe398
  x"CF",x"4C",x"05",x"C4",x"AD",x"49",x"CF",x"C9",
  -- 0xe3a0
  x"10",x"90",x"0B",x"A9",x"00",x"8D",x"49",x"CF",
  -- 0xe3a8
  x"20",x"16",x"C4",x"B0",x"01",x"60",x"A0",x"00",
  -- 0xe3b0
  x"AD",x"49",x"CF",x"29",x"08",x"D0",x"1A",x"AD",
  -- 0xe3b8
  x"49",x"CF",x"0A",x"0A",x"0A",x"0A",x"0A",x"AA",
  -- 0xe3c0
  x"BD",x"00",x"DE",x"99",x"29",x"CF",x"E8",x"C8",
  -- 0xe3c8
  x"C0",x"20",x"D0",x"F4",x"EE",x"49",x"CF",x"38",
  -- 0xe3d0
  x"60",x"AD",x"49",x"CF",x"0A",x"0A",x"0A",x"0A",
  -- 0xe3d8
  x"0A",x"AA",x"BD",x"00",x"DF",x"99",x"29",x"CF",
  -- 0xe3e0
  x"E8",x"C8",x"C0",x"20",x"D0",x"F4",x"EE",x"49",
  -- 0xe3e8
  x"CF",x"38",x"60",x"AD",x"3D",x"CF",x"8D",x"4C",
  -- 0xe3f0
  x"CF",x"AD",x"3E",x"CF",x"8D",x"4D",x"CF",x"AD",
  -- 0xe3f8
  x"43",x"CF",x"8D",x"4A",x"CF",x"AD",x"44",x"CF",
  -- 0xe400
  x"8D",x"4B",x"CF",x"38",x"60",x"A9",x"00",x"8D",
  -- 0xe408
  x"4E",x"CF",x"20",x"EE",x"C4",x"B0",x"01",x"60",
  -- 0xe410
  x"20",x"77",x"C6",x"4C",x"FA",x"C5",x"20",x"43",
  -- 0xe418
  x"C6",x"EE",x"4E",x"CF",x"AD",x"4E",x"CF",x"CD",
  -- 0xe420
  x"24",x"CF",x"D0",x"11",x"A9",x"00",x"8D",x"4E",
  -- 0xe428
  x"CF",x"20",x"38",x"C4",x"B0",x"01",x"60",x"20",
  -- 0xe430
  x"EE",x"C4",x"20",x"77",x"C6",x"4C",x"FA",x"C5",
  -- 0xe438
  x"A2",x"00",x"BD",x"4A",x"CF",x"9D",x"81",x"D6",
  -- 0xe440
  x"E8",x"E0",x"04",x"D0",x"F5",x"A0",x"07",x"18",
  -- 0xe448
  x"6E",x"84",x"D6",x"6E",x"83",x"D6",x"6E",x"82",
  -- 0xe450
  x"D6",x"6E",x"81",x"D6",x"88",x"D0",x"F0",x"A2",
  -- 0xe458
  x"00",x"18",x"08",x"28",x"BD",x"81",x"D6",x"7D",
  -- 0xe460
  x"08",x"CF",x"9D",x"81",x"D6",x"08",x"E8",x"E0",
  -- 0xe468
  x"04",x"D0",x"F0",x"28",x"A2",x"00",x"18",x"08",
  -- 0xe470
  x"28",x"BD",x"81",x"D6",x"7D",x"0C",x"CF",x"9D",
  -- 0xe478
  x"81",x"D6",x"08",x"E8",x"E0",x"04",x"D0",x"F0",
  -- 0xe480
  x"28",x"20",x"77",x"C6",x"20",x"FA",x"C5",x"90",
  -- 0xe488
  x"63",x"AD",x"4A",x"CF",x"0A",x"0A",x"AA",x"A0",
  -- 0xe490
  x"00",x"AD",x"4A",x"CF",x"29",x"40",x"D0",x"0E",
  -- 0xe498
  x"BD",x"00",x"DE",x"99",x"4A",x"CF",x"E8",x"C8",
  -- 0xe4a0
  x"C0",x"04",x"D0",x"F4",x"80",x"0C",x"BD",x"00",
  -- 0xe4a8
  x"DF",x"99",x"4A",x"CF",x"E8",x"C8",x"C0",x"04",
  -- 0xe4b0
  x"D0",x"F4",x"AD",x"4D",x"CF",x"29",x"0F",x"8D",
  -- 0xe4b8
  x"4D",x"CF",x"AD",x"4D",x"CF",x"0D",x"4C",x"CF",
  -- 0xe4c0
  x"0D",x"4B",x"CF",x"0D",x"4A",x"CF",x"C9",x"00",
  -- 0xe4c8
  x"F0",x"22",x"AD",x"4D",x"CF",x"C9",x"0F",x"D0",
  -- 0xe4d0
  x"19",x"AD",x"4C",x"CF",x"C9",x"FF",x"D0",x"12",
  -- 0xe4d8
  x"AD",x"4B",x"CF",x"C9",x"FF",x"D0",x"0B",x"AD",
  -- 0xe4e0
  x"4A",x"CF",x"C9",x"FF",x"F0",x"06",x"C9",x"F7",
  -- 0xe4e8
  x"F0",x"02",x"38",x"60",x"18",x"60",x"A2",x"03",
  -- 0xe4f0
  x"BD",x"4A",x"CF",x"9D",x"81",x"D6",x"CA",x"10",
  -- 0xe4f8
  x"F7",x"A2",x"03",x"38",x"08",x"28",x"BD",x"81",
  -- 0xe500
  x"D6",x"FD",x"14",x"CF",x"9D",x"81",x"D6",x"08",
  -- 0xe508
  x"CA",x"10",x"F2",x"28",x"AD",x"24",x"CF",x"A8",
  -- 0xe510
  x"29",x"FE",x"F0",x"14",x"18",x"2E",x"81",x"D6",
  -- 0xe518
  x"2E",x"82",x"D6",x"2E",x"83",x"D6",x"2E",x"84",
  -- 0xe520
  x"D6",x"98",x"4A",x"A8",x"29",x"FE",x"D0",x"EC",
  -- 0xe528
  x"A2",x"00",x"BD",x"81",x"D6",x"E8",x"E0",x"04",
  -- 0xe530
  x"D0",x"F8",x"A2",x"00",x"18",x"08",x"28",x"BD",
  -- 0xe538
  x"81",x"D6",x"7D",x"10",x"CF",x"9D",x"81",x"D6",
  -- 0xe540
  x"08",x"E8",x"E0",x"04",x"D0",x"F0",x"28",x"A2",
  -- 0xe548
  x"00",x"18",x"08",x"28",x"BD",x"81",x"D6",x"7D",
  -- 0xe550
  x"08",x"CF",x"9D",x"81",x"D6",x"08",x"E8",x"E0",
  -- 0xe558
  x"04",x"D0",x"F0",x"28",x"38",x"60",x"A9",x"00",
  -- 0xe560
  x"8D",x"81",x"D6",x"8D",x"82",x"D6",x"8D",x"83",
  -- 0xe568
  x"D6",x"8D",x"84",x"D6",x"4C",x"FA",x"C5",x"A9",
  -- 0xe570
  x"42",x"8D",x"80",x"D6",x"A9",x"00",x"8D",x"80",
  -- 0xe578
  x"D6",x"20",x"C2",x"C5",x"20",x"D0",x"C5",x"B0",
  -- 0xe580
  x"03",x"D0",x"F9",x"60",x"A9",x"01",x"8D",x"80",
  -- 0xe588
  x"D6",x"20",x"C2",x"C5",x"20",x"D0",x"C5",x"B0",
  -- 0xe590
  x"03",x"D0",x"F9",x"60",x"20",x"AF",x"C5",x"20",
  -- 0xe598
  x"EC",x"C5",x"A9",x"02",x"8D",x"80",x"D6",x"20",
  -- 0xe5a0
  x"C2",x"C5",x"AD",x"80",x"D6",x"20",x"D0",x"C5",
  -- 0xe5a8
  x"B0",x"03",x"D0",x"F6",x"60",x"38",x"60",x"20",
  -- 0xe5b0
  x"C2",x"C5",x"EE",x"57",x"CF",x"D0",x"FB",x"EE",
  -- 0xe5b8
  x"58",x"CF",x"D0",x"F6",x"EE",x"59",x"CF",x"D0",
  -- 0xe5c0
  x"F1",x"60",x"A9",x"00",x"8D",x"57",x"CF",x"8D",
  -- 0xe5c8
  x"58",x"CF",x"A9",x"E0",x"8D",x"59",x"CF",x"60",
  -- 0xe5d0
  x"AD",x"80",x"D6",x"29",x"03",x"F0",x"13",x"EE",
  -- 0xe5d8
  x"57",x"CF",x"D0",x"0C",x"EE",x"58",x"CF",x"D0",
  -- 0xe5e0
  x"07",x"EE",x"59",x"CF",x"D0",x"02",x"A9",x"00",
  -- 0xe5e8
  x"18",x"60",x"38",x"60",x"A9",x"81",x"8D",x"80",
  -- 0xe5f0
  x"D6",x"38",x"60",x"A9",x"82",x"8D",x"80",x"D6",
  -- 0xe5f8
  x"38",x"60",x"AD",x"80",x"D6",x"29",x"01",x"D0",
  -- 0xe600
  x"40",x"4C",x"16",x"C6",x"EE",x"20",x"D0",x"A2",
  -- 0xe608
  x"F0",x"A0",x"00",x"A3",x"00",x"1B",x"D0",x"FD",
  -- 0xe610
  x"C8",x"D0",x"FA",x"E8",x"D0",x"F7",x"A9",x"02",
  -- 0xe618
  x"8D",x"80",x"D6",x"20",x"C2",x"C5",x"20",x"D0",
  -- 0xe620
  x"C5",x"B0",x"05",x"D0",x"F9",x"4C",x"3B",x"C6",
  -- 0xe628
  x"AD",x"80",x"D6",x"29",x"01",x"D0",x"EF",x"AD",
  -- 0xe630
  x"88",x"D6",x"AD",x"89",x"D6",x"C9",x"02",x"D0",
  -- 0xe638
  x"CB",x"38",x"60",x"20",x"6F",x"C5",x"4C",x"16",
  -- 0xe640
  x"C6",x"18",x"60",x"AD",x"80",x"D6",x"29",x"10",
  -- 0xe648
  x"D0",x"1A",x"AD",x"82",x"D6",x"18",x"69",x"02",
  -- 0xe650
  x"8D",x"82",x"D6",x"AD",x"83",x"D6",x"69",x"00",
  -- 0xe658
  x"8D",x"83",x"D6",x"AD",x"84",x"D6",x"69",x"00",
  -- 0xe660
  x"8D",x"84",x"D6",x"60",x"EE",x"81",x"D6",x"90",
  -- 0xe668
  x"0D",x"EE",x"82",x"D6",x"90",x"08",x"EE",x"83",
  -- 0xe670
  x"D6",x"90",x"03",x"EE",x"84",x"D6",x"60",x"AD",
  -- 0xe678
  x"80",x"D6",x"29",x"10",x"F0",x"01",x"60",x"AD",
  -- 0xe680
  x"83",x"D6",x"8D",x"84",x"D6",x"AD",x"82",x"D6",
  -- 0xe688
  x"8D",x"83",x"D6",x"AD",x"81",x"D6",x"8D",x"82",
  -- 0xe690
  x"D6",x"A9",x"00",x"8D",x"81",x"D6",x"AD",x"82",
  -- 0xe698
  x"D6",x"0A",x"8D",x"82",x"D6",x"AD",x"83",x"D6",
  -- 0xe6a0
  x"2A",x"8D",x"83",x"D6",x"AD",x"84",x"D6",x"2A",
  -- 0xe6a8
  x"8D",x"84",x"D6",x"60",x"20",x"F3",x"C5",x"58",
  -- 0xe6b0
  x"68",x"8D",x"BB",x"C6",x"68",x"8D",x"BC",x"C6",
  -- 0xe6b8
  x"A2",x"01",x"BD",x"FF",x"FF",x"F0",x"06",x"20",
  -- 0xe6c0
  x"D2",x"FF",x"E8",x"D0",x"F5",x"38",x"8A",x"6D",
  -- 0xe6c8
  x"BB",x"C6",x"8D",x"DA",x"C6",x"A9",x"00",x"6D",
  -- 0xe6d0
  x"BC",x"C6",x"8D",x"DB",x"C6",x"78",x"20",x"EC",
  -- 0xe6d8
  x"C5",x"4C",x"FF",x"FF",x"B0",x"06",x"A9",x"00",
  -- 0xe6e0
  x"8D",x"2F",x"D0",x"60",x"A9",x"47",x"8D",x"2F",
  -- 0xe6e8
  x"D0",x"A9",x"53",x"8D",x"2F",x"D0",x"60",x"20",
  -- 0xe6f0
  x"F3",x"C5",x"18",x"20",x"DC",x"C6",x"AE",x"5A",
  -- 0xe6f8
  x"CF",x"9A",x"A9",x"00",x"58",x"18",x"60",x"A9",
  -- 0xe700
  x"7F",x"8D",x"0D",x"DC",x"8D",x"0D",x"DD",x"A9",
  -- 0xe708
  x"00",x"8D",x"19",x"D0",x"38",x"20",x"25",x"F2",
  -- 0xe710
  x"20",x"E3",x"EF",x"20",x"F5",x"F0",x"20",x"0E",
  -- 0xe718
  x"F0",x"A2",x"97",x"A0",x"F2",x"20",x"55",x"F1",
  -- 0xe720
  x"EE",x"01",x"CF",x"20",x"38",x"F2",x"A2",x"0F",
  -- 0xe728
  x"A0",x"F3",x"20",x"55",x"F1",x"20",x"57",x"ED",
  -- 0xe730
  x"B0",x"03",x"4C",x"2D",x"E7",x"A2",x"AF",x"A0",
  -- 0xe738
  x"F3",x"20",x"55",x"F1",x"A9",x"3E",x"8D",x"C0",
  -- 0xe740
  x"07",x"20",x"22",x"EE",x"AD",x"FE",x"DF",x"C9",
  -- 0xe748
  x"55",x"D3",x"C9",x"03",x"AD",x"FF",x"DF",x"C9",
  -- 0xe750
  x"AA",x"D3",x"C1",x"03",x"A2",x"D7",x"A0",x"F3",
  -- 0xe758
  x"20",x"55",x"F1",x"A0",x"00",x"AB",x"C2",x"DF",
  -- 0xe760
  x"20",x"9D",x"F1",x"AB",x"C9",x"DF",x"9C",x"0B",
  -- 0xe768
  x"CF",x"20",x"9D",x"F1",x"AB",x"C8",x"DF",x"9C",
  -- 0xe770
  x"0A",x"CF",x"20",x"9D",x"F1",x"AB",x"C7",x"DF",
  -- 0xe778
  x"9C",x"09",x"CF",x"20",x"9D",x"F1",x"AB",x"C6",
  -- 0xe780
  x"DF",x"9C",x"08",x"CF",x"20",x"9D",x"F1",x"AB",
  -- 0xe788
  x"CD",x"DF",x"20",x"9D",x"F1",x"AB",x"CC",x"DF",
  -- 0xe790
  x"20",x"9D",x"F1",x"AB",x"CB",x"DF",x"20",x"9D",
  -- 0xe798
  x"F1",x"AB",x"CA",x"DF",x"20",x"9D",x"F1",x"A2",
  -- 0xe7a0
  x"03",x"BD",x"08",x"CF",x"9D",x"81",x"D6",x"CA",
  -- 0xe7a8
  x"10",x"F7",x"20",x"EC",x"EE",x"20",x"30",x"EE",
  -- 0xe7b0
  x"93",x"55",x"03",x"A9",x"3E",x"8D",x"C1",x"07",
  -- 0xe7b8
  x"AD",x"FE",x"DF",x"C9",x"55",x"D3",x"55",x"03",
  -- 0xe7c0
  x"AD",x"FF",x"DF",x"C9",x"AA",x"D3",x"4D",x"03",
  -- 0xe7c8
  x"A2",x"FF",x"A0",x"F3",x"20",x"55",x"F1",x"A0",
  -- 0xe7d0
  x"00",x"AB",x"0D",x"DE",x"20",x"9D",x"F1",x"AB",
  -- 0xe7d8
  x"0F",x"DE",x"20",x"9D",x"F1",x"AB",x"0E",x"DE",
  -- 0xe7e0
  x"20",x"9D",x"F1",x"AB",x"2F",x"DE",x"20",x"9D",
  -- 0xe7e8
  x"F1",x"AB",x"2E",x"DE",x"20",x"9D",x"F1",x"AB",
  -- 0xe7f0
  x"2D",x"DE",x"20",x"9D",x"F1",x"AB",x"2C",x"DE",
  -- 0xe7f8
  x"20",x"9D",x"F1",x"AD",x"11",x"DE",x"D3",x"14",
  -- 0xe800
  x"03",x"A2",x"03",x"BD",x"0E",x"DE",x"9D",x"10",
  -- 0xe808
  x"CF",x"9D",x"0C",x"CF",x"BD",x"2C",x"DE",x"9D",
  -- 0xe810
  x"14",x"CF",x"CA",x"10",x"EE",x"A9",x"00",x"8D",
  -- 0xe818
  x"12",x"CF",x"8D",x"13",x"CF",x"8D",x"0E",x"CF",
  -- 0xe820
  x"8D",x"0F",x"CF",x"AC",x"10",x"DE",x"F0",x"18",
  -- 0xe828
  x"A2",x"00",x"18",x"08",x"28",x"BD",x"10",x"CF",
  -- 0xe830
  x"7D",x"24",x"DE",x"9D",x"10",x"CF",x"08",x"E8",
  -- 0xe838
  x"E0",x"04",x"D0",x"F0",x"28",x"88",x"D0",x"E8",
  -- 0xe840
  x"38",x"A2",x"03",x"BD",x"20",x"DE",x"FD",x"10",
  -- 0xe848
  x"CF",x"9D",x"1C",x"CF",x"9D",x"20",x"CF",x"CA",
  -- 0xe850
  x"10",x"F1",x"AD",x"0D",x"DE",x"8D",x"24",x"CF",
  -- 0xe858
  x"A8",x"29",x"FE",x"F0",x"14",x"A2",x"03",x"18",
  -- 0xe860
  x"BD",x"20",x"CF",x"6A",x"9D",x"20",x"CF",x"CA",
  -- 0xe868
  x"10",x"F6",x"98",x"4A",x"A8",x"29",x"FE",x"D0",
  -- 0xe870
  x"EC",x"AD",x"23",x"CF",x"0D",x"22",x"CF",x"F3",
  -- 0xe878
  x"9B",x"02",x"A2",x"27",x"A0",x"F4",x"20",x"55",
  -- 0xe880
  x"F1",x"A0",x"00",x"AB",x"13",x"CF",x"20",x"9D",
  -- 0xe888
  x"F1",x"AB",x"12",x"CF",x"20",x"9D",x"F1",x"AB",
  -- 0xe890
  x"11",x"CF",x"20",x"9D",x"F1",x"AB",x"10",x"CF",
  -- 0xe898
  x"20",x"9D",x"F1",x"AB",x"1F",x"CF",x"20",x"9D",
  -- 0xe8a0
  x"F1",x"AB",x"1E",x"CF",x"20",x"9D",x"F1",x"AB",
  -- 0xe8a8
  x"1D",x"CF",x"20",x"9D",x"F1",x"AB",x"1C",x"CF",
  -- 0xe8b0
  x"20",x"9D",x"F1",x"AB",x"23",x"CF",x"20",x"9D",
  -- 0xe8b8
  x"F1",x"AB",x"22",x"CF",x"20",x"9D",x"F1",x"AB",
  -- 0xe8c0
  x"21",x"CF",x"20",x"9D",x"F1",x"AB",x"20",x"CF",
  -- 0xe8c8
  x"20",x"9D",x"F1",x"A2",x"03",x"BD",x"2C",x"DE",
  -- 0xe8d0
  x"9D",x"18",x"CF",x"9D",x"4A",x"CF",x"CA",x"10",
  -- 0xe8d8
  x"F4",x"A9",x"3E",x"8D",x"C2",x"07",x"A9",x"00",
  -- 0xe8e0
  x"8D",x"8B",x"D6",x"20",x"2C",x"EB",x"20",x"3B",
  -- 0xe8e8
  x"EB",x"93",x"1C",x"02",x"20",x"50",x"EB",x"93",
  -- 0xe8f0
  x"E6",x"00",x"A2",x"00",x"BD",x"29",x"CF",x"20",
  -- 0xe8f8
  x"21",x"EB",x"DD",x"B2",x"F6",x"D0",x"ED",x"E8",
  -- 0xe900
  x"E0",x"0B",x"D0",x"F0",x"A2",x"B7",x"A0",x"F5",
  -- 0xe908
  x"20",x"55",x"F1",x"20",x"9F",x"EB",x"20",x"BF",
  -- 0xe910
  x"EC",x"20",x"EC",x"EE",x"A2",x"03",x"BD",x"81",
  -- 0xe918
  x"D6",x"9D",x"8C",x"D6",x"CA",x"10",x"F7",x"20",
  -- 0xe920
  x"9F",x"EB",x"A2",x"03",x"BD",x"4A",x"CF",x"9D",
  -- 0xe928
  x"4F",x"CF",x"CA",x"10",x"F7",x"A9",x"00",x"8D",
  -- 0xe930
  x"55",x"CF",x"8D",x"56",x"CF",x"A9",x"40",x"8D",
  -- 0xe938
  x"53",x"CF",x"A9",x"06",x"8D",x"54",x"CF",x"AB",
  -- 0xe940
  x"24",x"CF",x"6B",x"29",x"01",x"D0",x"0C",x"6B",
  -- 0xe948
  x"4A",x"4B",x"4E",x"54",x"CF",x"6E",x"53",x"CF",
  -- 0xe950
  x"4C",x"42",x"E9",x"A2",x"03",x"BD",x"4F",x"CF",
  -- 0xe958
  x"DD",x"4A",x"CF",x"D0",x"5A",x"CA",x"10",x"F5",
  -- 0xe960
  x"EE",x"55",x"CF",x"D0",x"03",x"EE",x"56",x"CF",
  -- 0xe968
  x"18",x"AD",x"4F",x"CF",x"69",x"01",x"8D",x"4F",
  -- 0xe970
  x"CF",x"AD",x"50",x"CF",x"69",x"00",x"8D",x"50",
  -- 0xe978
  x"CF",x"AD",x"51",x"CF",x"69",x"00",x"8D",x"51",
  -- 0xe980
  x"CF",x"AD",x"52",x"CF",x"69",x"00",x"8D",x"52",
  -- 0xe988
  x"CF",x"20",x"09",x"EC",x"B0",x"C5",x"AD",x"53",
  -- 0xe990
  x"CF",x"CD",x"55",x"CF",x"D0",x"17",x"AD",x"54",
  -- 0xe998
  x"CF",x"CD",x"56",x"CF",x"D0",x"0F",x"A9",x"07",
  -- 0xe9a0
  x"8D",x"8B",x"D6",x"A2",x"2F",x"A0",x"F6",x"20",
  -- 0xe9a8
  x"55",x"F1",x"4C",x"DE",x"E9",x"A2",x"DF",x"A0",
  -- 0xe9b0
  x"F5",x"20",x"55",x"F1",x"4C",x"DE",x"E9",x"EE",
  -- 0xe9b8
  x"20",x"D0",x"A2",x"00",x"BD",x"4F",x"CF",x"9D",
  -- 0xe9c0
  x"28",x"04",x"BD",x"4A",x"CF",x"9D",x"30",x"04",
  -- 0xe9c8
  x"E8",x"E0",x"04",x"D0",x"EF",x"A2",x"07",x"A0",
  -- 0xe9d0
  x"F6",x"20",x"55",x"F1",x"4C",x"DE",x"E9",x"A2",
  -- 0xe9d8
  x"8F",x"A0",x"F5",x"20",x"55",x"F1",x"20",x"21",
  -- 0xe9e0
  x"EF",x"90",x"0A",x"A2",x"BF",x"A0",x"F2",x"20",
  -- 0xe9e8
  x"55",x"F1",x"4C",x"C2",x"F1",x"A2",x"E7",x"A0",
  -- 0xe9f0
  x"F2",x"20",x"55",x"F1",x"20",x"2C",x"EB",x"20",
  -- 0xe9f8
  x"3B",x"EB",x"93",x"0B",x"01",x"20",x"50",x"EB",
  -- 0xea00
  x"B0",x"21",x"A2",x"0B",x"BD",x"A7",x"F6",x"9D",
  -- 0xea08
  x"92",x"F6",x"CA",x"D0",x"F7",x"A2",x"7F",x"A0",
  -- 0xea10
  x"F6",x"20",x"55",x"F1",x"20",x"B5",x"ED",x"20",
  -- 0xea18
  x"B5",x"ED",x"20",x"B5",x"ED",x"20",x"B5",x"ED",
  -- 0xea20
  x"4C",x"07",x"EB",x"A2",x"00",x"BD",x"29",x"CF",
  -- 0xea28
  x"20",x"21",x"EB",x"DD",x"A7",x"F6",x"D0",x"CD",
  -- 0xea30
  x"E8",x"E0",x"0B",x"D0",x"F0",x"20",x"9F",x"EB",
  -- 0xea38
  x"A9",x"3E",x"8D",x"C3",x"07",x"A2",x"77",x"A0",
  -- 0xea40
  x"F4",x"20",x"55",x"F1",x"A0",x"00",x"AB",x"4D",
  -- 0xea48
  x"CF",x"20",x"9D",x"F1",x"AB",x"4C",x"CF",x"20",
  -- 0xea50
  x"9D",x"F1",x"AB",x"4B",x"CF",x"20",x"9D",x"F1",
  -- 0xea58
  x"AB",x"4A",x"CF",x"20",x"9D",x"F1",x"20",x"B9",
  -- 0xea60
  x"EB",x"93",x"9D",x"00",x"A2",x"C7",x"A0",x"F4",
  -- 0xea68
  x"20",x"55",x"F1",x"A9",x"00",x"8D",x"06",x"CF",
  -- 0xea70
  x"8D",x"07",x"CF",x"A9",x"80",x"A2",x"0F",x"A0",
  -- 0xea78
  x"00",x"A3",x"8F",x"5C",x"EA",x"AD",x"06",x"CF",
  -- 0xea80
  x"0A",x"85",x"FB",x"AD",x"06",x"CF",x"4A",x"4A",
  -- 0xea88
  x"4A",x"4A",x"4A",x"4A",x"4A",x"85",x"FC",x"A5",
  -- 0xea90
  x"FB",x"18",x"69",x"C0",x"85",x"FB",x"A5",x"FC",
  -- 0xea98
  x"69",x"01",x"09",x"40",x"AA",x"A5",x"FB",x"A0",
  -- 0xeaa0
  x"00",x"A3",x"8F",x"5C",x"EA",x"A2",x"00",x"BD",
  -- 0xeaa8
  x"00",x"DE",x"9D",x"00",x"40",x"BD",x"00",x"DF",
  -- 0xeab0
  x"9D",x"00",x"41",x"E8",x"D0",x"F1",x"A9",x"00",
  -- 0xeab8
  x"AA",x"A0",x"00",x"A3",x"8F",x"5C",x"EA",x"A9",
  -- 0xeac0
  x"00",x"A2",x"0F",x"A0",x"00",x"A3",x"8F",x"5C",
  -- 0xeac8
  x"EA",x"EE",x"06",x"CF",x"D0",x"03",x"EE",x"07",
  -- 0xead0
  x"CF",x"AD",x"07",x"CF",x"C9",x"02",x"F0",x"21",
  -- 0xead8
  x"EE",x"20",x"D0",x"20",x"CA",x"EB",x"B0",x"93",
  -- 0xeae0
  x"AD",x"06",x"CF",x"D0",x"14",x"AD",x"07",x"CF",
  -- 0xeae8
  x"C9",x"01",x"D0",x"0D",x"20",x"54",x"EF",x"A2",
  -- 0xeaf0
  x"BF",x"A0",x"F2",x"20",x"55",x"F1",x"4C",x"C2",
  -- 0xeaf8
  x"F1",x"A2",x"EF",x"A0",x"F4",x"20",x"55",x"F1",
  -- 0xeb00
  x"A2",x"9F",x"A0",x"F4",x"20",x"55",x"F1",x"A2",
  -- 0xeb08
  x"5F",x"A0",x"F3",x"20",x"55",x"F1",x"20",x"B5",
  -- 0xeb10
  x"ED",x"4C",x"BD",x"F6",x"A2",x"87",x"A0",x"F3",
  -- 0xeb18
  x"20",x"55",x"F1",x"20",x"B5",x"ED",x"4C",x"BD",
  -- 0xeb20
  x"F6",x"C9",x"60",x"90",x"06",x"C9",x"7A",x"B0",
  -- 0xeb28
  x"02",x"29",x"5F",x"60",x"A2",x"00",x"BD",x"18",
  -- 0xeb30
  x"CF",x"9D",x"25",x"CF",x"E8",x"E0",x"04",x"D0",
  -- 0xeb38
  x"F5",x"38",x"60",x"A2",x"00",x"BD",x"25",x"CF",
  -- 0xeb40
  x"9D",x"4A",x"CF",x"E8",x"E0",x"04",x"D0",x"F5",
  -- 0xeb48
  x"A9",x"00",x"8D",x"49",x"CF",x"4C",x"B9",x"EB",
  -- 0xeb50
  x"AD",x"49",x"CF",x"C9",x"10",x"90",x"0B",x"A9",
  -- 0xeb58
  x"00",x"8D",x"49",x"CF",x"20",x"CA",x"EB",x"B0",
  -- 0xeb60
  x"01",x"60",x"A0",x"00",x"AD",x"49",x"CF",x"29",
  -- 0xeb68
  x"08",x"D0",x"1A",x"AD",x"49",x"CF",x"0A",x"0A",
  -- 0xeb70
  x"0A",x"0A",x"0A",x"AA",x"BD",x"00",x"DE",x"99",
  -- 0xeb78
  x"29",x"CF",x"E8",x"C8",x"C0",x"20",x"D0",x"F4",
  -- 0xeb80
  x"EE",x"49",x"CF",x"38",x"60",x"AD",x"49",x"CF",
  -- 0xeb88
  x"0A",x"0A",x"0A",x"0A",x"0A",x"AA",x"BD",x"00",
  -- 0xeb90
  x"DF",x"99",x"29",x"CF",x"E8",x"C8",x"C0",x"20",
  -- 0xeb98
  x"D0",x"F4",x"EE",x"49",x"CF",x"38",x"60",x"AD",
  -- 0xeba0
  x"3D",x"CF",x"8D",x"4C",x"CF",x"AD",x"3E",x"CF",
  -- 0xeba8
  x"8D",x"4D",x"CF",x"AD",x"43",x"CF",x"8D",x"4A",
  -- 0xebb0
  x"CF",x"AD",x"44",x"CF",x"8D",x"4B",x"CF",x"38",
  -- 0xebb8
  x"60",x"A9",x"00",x"8D",x"4E",x"CF",x"20",x"BF",
  -- 0xebc0
  x"EC",x"B0",x"01",x"60",x"20",x"EC",x"EE",x"4C",
  -- 0xebc8
  x"30",x"EE",x"20",x"B8",x"EE",x"EE",x"4E",x"CF",
  -- 0xebd0
  x"AD",x"4E",x"CF",x"CD",x"24",x"CF",x"D0",x"20",
  -- 0xebd8
  x"A9",x"00",x"8D",x"4E",x"CF",x"20",x"09",x"EC",
  -- 0xebe0
  x"B0",x"01",x"60",x"20",x"BF",x"EC",x"20",x"EC",
  -- 0xebe8
  x"EE",x"08",x"AD",x"F1",x"D6",x"29",x"10",x"F0",
  -- 0xebf0
  x"06",x"20",x"31",x"ED",x"20",x"B5",x"ED",x"28",
  -- 0xebf8
  x"4C",x"30",x"EE",x"49",x"54",x"53",x"20",x"52",
  -- 0xec00
  x"49",x"47",x"48",x"54",x"20",x"48",x"45",x"52",
  -- 0xec08
  x"45",x"A2",x"00",x"BD",x"4A",x"CF",x"9D",x"81",
  -- 0xec10
  x"D6",x"E8",x"E0",x"04",x"D0",x"F5",x"A0",x"07",
  -- 0xec18
  x"18",x"6E",x"84",x"D6",x"6E",x"83",x"D6",x"6E",
  -- 0xec20
  x"82",x"D6",x"6E",x"81",x"D6",x"88",x"D0",x"F0",
  -- 0xec28
  x"A2",x"00",x"18",x"08",x"28",x"BD",x"81",x"D6",
  -- 0xec30
  x"7D",x"08",x"CF",x"9D",x"81",x"D6",x"08",x"E8",
  -- 0xec38
  x"E0",x"04",x"D0",x"F0",x"28",x"A2",x"00",x"18",
  -- 0xec40
  x"08",x"28",x"BD",x"81",x"D6",x"7D",x"0C",x"CF",
  -- 0xec48
  x"9D",x"81",x"D6",x"08",x"E8",x"E0",x"04",x"D0",
  -- 0xec50
  x"F0",x"28",x"20",x"EC",x"EE",x"20",x"30",x"EE",
  -- 0xec58
  x"90",x"63",x"AD",x"4A",x"CF",x"0A",x"0A",x"AA",
  -- 0xec60
  x"A0",x"00",x"AD",x"4A",x"CF",x"29",x"40",x"D0",
  -- 0xec68
  x"0E",x"BD",x"00",x"DE",x"99",x"4A",x"CF",x"E8",
  -- 0xec70
  x"C8",x"C0",x"04",x"D0",x"F4",x"80",x"0C",x"BD",
  -- 0xec78
  x"00",x"DF",x"99",x"4A",x"CF",x"E8",x"C8",x"C0",
  -- 0xec80
  x"04",x"D0",x"F4",x"AD",x"4D",x"CF",x"29",x"0F",
  -- 0xec88
  x"8D",x"4D",x"CF",x"AD",x"4D",x"CF",x"0D",x"4C",
  -- 0xec90
  x"CF",x"0D",x"4B",x"CF",x"0D",x"4A",x"CF",x"C9",
  -- 0xec98
  x"00",x"F0",x"22",x"AD",x"4D",x"CF",x"C9",x"0F",
  -- 0xeca0
  x"D0",x"19",x"AD",x"4C",x"CF",x"C9",x"FF",x"D0",
  -- 0xeca8
  x"12",x"AD",x"4B",x"CF",x"C9",x"FF",x"D0",x"0B",
  -- 0xecb0
  x"AD",x"4A",x"CF",x"C9",x"FF",x"F0",x"06",x"C9",
  -- 0xecb8
  x"F7",x"F0",x"02",x"38",x"60",x"18",x"60",x"A2",
  -- 0xecc0
  x"03",x"BD",x"4A",x"CF",x"9D",x"81",x"D6",x"CA",
  -- 0xecc8
  x"10",x"F7",x"A2",x"00",x"38",x"08",x"28",x"BD",
  -- 0xecd0
  x"81",x"D6",x"FD",x"14",x"CF",x"9D",x"81",x"D6",
  -- 0xecd8
  x"08",x"E8",x"E0",x"04",x"D0",x"F0",x"28",x"AD",
  -- 0xece0
  x"24",x"CF",x"A8",x"29",x"FE",x"F0",x"14",x"18",
  -- 0xece8
  x"2E",x"81",x"D6",x"2E",x"82",x"D6",x"2E",x"83",
  -- 0xecf0
  x"D6",x"2E",x"84",x"D6",x"98",x"4A",x"A8",x"29",
  -- 0xecf8
  x"FE",x"D0",x"EC",x"A2",x"00",x"BD",x"81",x"D6",
  -- 0xed00
  x"E8",x"E0",x"04",x"D0",x"F8",x"A2",x"00",x"18",
  -- 0xed08
  x"08",x"28",x"BD",x"81",x"D6",x"7D",x"10",x"CF",
  -- 0xed10
  x"9D",x"81",x"D6",x"08",x"E8",x"E0",x"04",x"D0",
  -- 0xed18
  x"F0",x"28",x"A2",x"00",x"18",x"08",x"28",x"BD",
  -- 0xed20
  x"81",x"D6",x"7D",x"08",x"CF",x"9D",x"81",x"D6",
  -- 0xed28
  x"08",x"E8",x"E0",x"04",x"D0",x"F0",x"28",x"38",
  -- 0xed30
  x"60",x"A2",x"4F",x"A0",x"F4",x"20",x"55",x"F1",
  -- 0xed38
  x"A0",x"00",x"A2",x"03",x"BD",x"4A",x"CF",x"4B",
  -- 0xed40
  x"DA",x"20",x"9D",x"F1",x"FA",x"CA",x"10",x"F4",
  -- 0xed48
  x"A2",x"03",x"BD",x"81",x"D6",x"4B",x"DA",x"20",
  -- 0xed50
  x"9D",x"F1",x"FA",x"CA",x"10",x"F4",x"60",x"20",
  -- 0xed58
  x"75",x"ED",x"B0",x"01",x"60",x"A2",x"37",x"A0",
  -- 0xed60
  x"F3",x"20",x"55",x"F1",x"A9",x"00",x"8D",x"81",
  -- 0xed68
  x"D6",x"8D",x"82",x"D6",x"8D",x"83",x"D6",x"8D",
  -- 0xed70
  x"84",x"D6",x"4C",x"30",x"EE",x"A9",x"42",x"8D",
  -- 0xed78
  x"80",x"D6",x"A9",x"00",x"8D",x"80",x"D6",x"20",
  -- 0xed80
  x"F8",x"ED",x"20",x"06",x"EE",x"B0",x"03",x"D0",
  -- 0xed88
  x"F9",x"60",x"A9",x"01",x"8D",x"80",x"D6",x"20",
  -- 0xed90
  x"F8",x"ED",x"20",x"06",x"EE",x"B0",x"03",x"D0",
  -- 0xed98
  x"F9",x"60",x"20",x"B5",x"ED",x"20",x"22",x"EE",
  -- 0xeda0
  x"A9",x"02",x"8D",x"80",x"D6",x"20",x"F8",x"ED",
  -- 0xeda8
  x"AD",x"80",x"D6",x"20",x"06",x"EE",x"B0",x"03",
  -- 0xedb0
  x"D0",x"F6",x"60",x"38",x"60",x"20",x"F8",x"ED",
  -- 0xedb8
  x"EE",x"20",x"D0",x"EE",x"20",x"D0",x"CE",x"20",
  -- 0xedc0
  x"D0",x"EE",x"20",x"D0",x"CE",x"20",x"D0",x"EE",
  -- 0xedc8
  x"20",x"D0",x"CE",x"20",x"D0",x"EE",x"20",x"D0",
  -- 0xedd0
  x"CE",x"20",x"D0",x"EE",x"20",x"D0",x"CE",x"20",
  -- 0xedd8
  x"D0",x"EE",x"20",x"D0",x"CE",x"20",x"D0",x"EE",
  -- 0xede0
  x"20",x"D0",x"CE",x"20",x"D0",x"CE",x"20",x"D0",
  -- 0xede8
  x"EE",x"00",x"03",x"D0",x"CB",x"EE",x"01",x"03",
  -- 0xedf0
  x"D0",x"C6",x"EE",x"02",x"03",x"D0",x"C1",x"60",
  -- 0xedf8
  x"A9",x"00",x"8D",x"00",x"03",x"8D",x"01",x"03",
  -- 0xee00
  x"A9",x"F7",x"8D",x"02",x"03",x"60",x"AD",x"80",
  -- 0xee08
  x"D6",x"29",x"03",x"F0",x"13",x"EE",x"00",x"03",
  -- 0xee10
  x"D0",x"0C",x"EE",x"01",x"03",x"D0",x"07",x"EE",
  -- 0xee18
  x"02",x"03",x"D0",x"02",x"A9",x"00",x"18",x"60",
  -- 0xee20
  x"38",x"60",x"A9",x"81",x"8D",x"80",x"D6",x"38",
  -- 0xee28
  x"60",x"A9",x"82",x"8D",x"80",x"D6",x"38",x"60",
  -- 0xee30
  x"AD",x"80",x"D6",x"29",x"01",x"D0",x"3D",x"4C",
  -- 0xee38
  x"49",x"EE",x"A2",x"F0",x"A0",x"00",x"A3",x"00",
  -- 0xee40
  x"1B",x"D0",x"FD",x"C8",x"D0",x"FA",x"E8",x"D0",
  -- 0xee48
  x"F7",x"A9",x"02",x"8D",x"80",x"D6",x"20",x"F8",
  -- 0xee50
  x"ED",x"20",x"06",x"EE",x"B0",x"05",x"D0",x"F9",
  -- 0xee58
  x"4C",x"6E",x"EE",x"AD",x"80",x"D6",x"29",x"01",
  -- 0xee60
  x"D0",x"EF",x"AD",x"88",x"D6",x"AD",x"89",x"D6",
  -- 0xee68
  x"C9",x"02",x"D0",x"CE",x"38",x"60",x"20",x"75",
  -- 0xee70
  x"ED",x"4C",x"49",x"EE",x"18",x"60",x"A2",x"17",
  -- 0xee78
  x"A0",x"F5",x"20",x"55",x"F1",x"A0",x"00",x"AB",
  -- 0xee80
  x"4D",x"CF",x"20",x"9D",x"F1",x"AB",x"4C",x"CF",
  -- 0xee88
  x"20",x"9D",x"F1",x"AB",x"4B",x"CF",x"20",x"9D",
  -- 0xee90
  x"F1",x"AB",x"4A",x"CF",x"4C",x"9D",x"F1",x"A2",
  -- 0xee98
  x"3F",x"A0",x"F5",x"20",x"55",x"F1",x"A0",x"00",
  -- 0xeea0
  x"AB",x"84",x"D6",x"20",x"9D",x"F1",x"AB",x"83",
  -- 0xeea8
  x"D6",x"20",x"9D",x"F1",x"AB",x"82",x"D6",x"20",
  -- 0xeeb0
  x"9D",x"F1",x"AB",x"81",x"D6",x"4C",x"9D",x"F1",
  -- 0xeeb8
  x"AD",x"80",x"D6",x"29",x"10",x"D0",x"1A",x"AD",
  -- 0xeec0
  x"82",x"D6",x"18",x"69",x"02",x"8D",x"82",x"D6",
  -- 0xeec8
  x"AD",x"83",x"D6",x"69",x"00",x"8D",x"83",x"D6",
  -- 0xeed0
  x"AD",x"84",x"D6",x"69",x"00",x"8D",x"84",x"D6",
  -- 0xeed8
  x"60",x"EE",x"81",x"D6",x"90",x"0D",x"EE",x"82",
  -- 0xeee0
  x"D6",x"90",x"08",x"EE",x"83",x"D6",x"90",x"03",
  -- 0xeee8
  x"EE",x"84",x"D6",x"60",x"AD",x"80",x"D6",x"29",
  -- 0xeef0
  x"10",x"F0",x"01",x"60",x"AD",x"83",x"D6",x"8D",
  -- 0xeef8
  x"84",x"D6",x"AD",x"82",x"D6",x"8D",x"83",x"D6",
  -- 0xef00
  x"AD",x"81",x"D6",x"8D",x"82",x"D6",x"A9",x"00",
  -- 0xef08
  x"8D",x"81",x"D6",x"AD",x"82",x"D6",x"0A",x"8D",
  -- 0xef10
  x"82",x"D6",x"AD",x"83",x"D6",x"2A",x"8D",x"83",
  -- 0xef18
  x"D6",x"AD",x"84",x"D6",x"2A",x"8D",x"84",x"D6",
  -- 0xef20
  x"60",x"AD",x"F1",x"D6",x"29",x"20",x"D0",x"2A",
  -- 0xef28
  x"AD",x"AC",x"F6",x"C9",x"20",x"D0",x"23",x"20",
  -- 0xef30
  x"7E",x"EF",x"20",x"6A",x"EF",x"AD",x"00",x"40",
  -- 0xef38
  x"CD",x"02",x"CF",x"D0",x"15",x"AD",x"01",x"40",
  -- 0xef40
  x"CD",x"03",x"CF",x"D0",x"0D",x"AD",x"02",x"40",
  -- 0xef48
  x"CD",x"04",x"CF",x"D0",x"05",x"20",x"14",x"F2",
  -- 0xef50
  x"38",x"60",x"18",x"60",x"20",x"6A",x"EF",x"AD",
  -- 0xef58
  x"02",x"CF",x"8D",x"00",x"40",x"AD",x"03",x"CF",
  -- 0xef60
  x"8D",x"01",x"40",x"AD",x"04",x"CF",x"8D",x"02",
  -- 0xef68
  x"40",x"60",x"A9",x"80",x"A2",x"0F",x"A0",x"00",
  -- 0xef70
  x"A3",x"8F",x"5C",x"A9",x"C0",x"A2",x"CF",x"A0",
  -- 0xef78
  x"00",x"A3",x"8F",x"5C",x"EA",x"60",x"A9",x"03",
  -- 0xef80
  x"8D",x"02",x"CF",x"8D",x"03",x"CF",x"8D",x"04",
  -- 0xef88
  x"CF",x"8D",x"05",x"CF",x"A9",x"08",x"8D",x"00",
  -- 0xef90
  x"CF",x"AD",x"00",x"CF",x"38",x"E9",x"01",x"4A",
  -- 0xef98
  x"4A",x"09",x"C0",x"AA",x"AD",x"00",x"CF",x"38",
  -- 0xefa0
  x"E9",x"01",x"0A",x"0A",x"0A",x"0A",x"0A",x"0A",
  -- 0xefa8
  x"A0",x"00",x"A3",x"8F",x"5C",x"EA",x"A9",x"00",
  -- 0xefb0
  x"85",x"FB",x"A9",x"40",x"85",x"FC",x"A0",x"00",
  -- 0xefb8
  x"AD",x"02",x"CF",x"18",x"71",x"FB",x"8D",x"02",
  -- 0xefc0
  x"CF",x"90",x"08",x"EE",x"03",x"CF",x"90",x"03",
  -- 0xefc8
  x"EE",x"04",x"CF",x"C8",x"D0",x"EA",x"E6",x"FC",
  -- 0xefd0
  x"A5",x"FC",x"C9",x"80",x"D0",x"E0",x"EE",x"00",
  -- 0xefd8
  x"CF",x"AD",x"00",x"CF",x"C9",x"10",x"D0",x"B1",
  -- 0xefe0
  x"4C",x"14",x"F2",x"A9",x"40",x"8D",x"30",x"D0",
  -- 0xefe8
  x"A9",x"00",x"8D",x"31",x"D0",x"8D",x"20",x"D0",
  -- 0xeff0
  x"8D",x"21",x"D0",x"8D",x"54",x"D0",x"A9",x"14",
  -- 0xeff8
  x"8D",x"18",x"D0",x"A9",x"1B",x"8D",x"11",x"D0",
  -- 0xf000
  x"A9",x"C8",x"8D",x"16",x"D0",x"A9",x"FF",x"8D",
  -- 0xf008
  x"01",x"DD",x"8D",x"00",x"DD",x"60",x"A9",x"04",
  -- 0xf010
  x"8D",x"30",x"D0",x"A9",x"FF",x"8D",x"70",x"D0",
  -- 0xf018
  x"A9",x"00",x"8D",x"00",x"D1",x"8D",x"00",x"D2",
  -- 0xf020
  x"8D",x"00",x"D3",x"A9",x"FF",x"8D",x"01",x"D1",
  -- 0xf028
  x"8D",x"01",x"D2",x"8D",x"01",x"D3",x"A9",x"BA",
  -- 0xf030
  x"8D",x"02",x"D1",x"A9",x"13",x"8D",x"02",x"D2",
  -- 0xf038
  x"A9",x"62",x"8D",x"02",x"D3",x"A9",x"66",x"8D",
  -- 0xf040
  x"03",x"D1",x"A9",x"AD",x"8D",x"03",x"D2",x"A9",
  -- 0xf048
  x"FF",x"8D",x"03",x"D3",x"A9",x"BB",x"8D",x"04",
  -- 0xf050
  x"D1",x"A9",x"F3",x"8D",x"04",x"D2",x"A9",x"8B",
  -- 0xf058
  x"8D",x"04",x"D3",x"A9",x"55",x"8D",x"05",x"D1",
  -- 0xf060
  x"A9",x"EC",x"8D",x"05",x"D2",x"A9",x"85",x"8D",
  -- 0xf068
  x"05",x"D3",x"A9",x"D1",x"8D",x"06",x"D1",x"A9",
  -- 0xf070
  x"E0",x"8D",x"06",x"D2",x"A9",x"79",x"8D",x"06",
  -- 0xf078
  x"D3",x"A9",x"AE",x"8D",x"07",x"D1",x"A9",x"5F",
  -- 0xf080
  x"8D",x"07",x"D2",x"A9",x"C7",x"8D",x"07",x"D3",
  -- 0xf088
  x"A9",x"9B",x"8D",x"08",x"D1",x"A9",x"47",x"8D",
  -- 0xf090
  x"08",x"D2",x"A9",x"81",x"8D",x"08",x"D3",x"A9",
  -- 0xf098
  x"87",x"8D",x"09",x"D1",x"A9",x"37",x"8D",x"09",
  -- 0xf0a0
  x"D2",x"A9",x"00",x"8D",x"09",x"D3",x"A9",x"DD",
  -- 0xf0a8
  x"8D",x"0A",x"D1",x"A9",x"39",x"8D",x"0A",x"D2",
  -- 0xf0b0
  x"A9",x"78",x"8D",x"0A",x"D3",x"A9",x"B5",x"8D",
  -- 0xf0b8
  x"0B",x"D1",x"8D",x"0B",x"D2",x"8D",x"0B",x"D3",
  -- 0xf0c0
  x"A9",x"B8",x"8D",x"0C",x"D1",x"8D",x"0C",x"D2",
  -- 0xf0c8
  x"8D",x"0C",x"D3",x"A9",x"0B",x"8D",x"0D",x"D1",
  -- 0xf0d0
  x"A9",x"4F",x"8D",x"0D",x"D2",x"A9",x"CA",x"8D",
  -- 0xf0d8
  x"0D",x"D3",x"A9",x"AA",x"8D",x"0E",x"D1",x"A9",
  -- 0xf0e0
  x"D9",x"8D",x"0E",x"D2",x"A9",x"FE",x"8D",x"0E",
  -- 0xf0e8
  x"D3",x"A9",x"8B",x"8D",x"0F",x"D1",x"8D",x"0F",
  -- 0xf0f0
  x"D2",x"8D",x"0F",x"D3",x"60",x"A9",x"01",x"0C",
  -- 0xf0f8
  x"30",x"D0",x"A9",x"FF",x"8D",x"02",x"D7",x"A9",
  -- 0xf100
  x"FF",x"8D",x"04",x"D7",x"8D",x"05",x"D7",x"A9",
  -- 0xf108
  x"00",x"8D",x"06",x"D7",x"A9",x"F1",x"8D",x"01",
  -- 0xf110
  x"D7",x"A9",x"26",x"8D",x"00",x"D7",x"A9",x"00",
  -- 0xf118
  x"8D",x"05",x"D7",x"A9",x"01",x"1C",x"30",x"D0",
  -- 0xf120
  x"A9",x"00",x"8D",x"01",x"CF",x"60",x"07",x"E8",
  -- 0xf128
  x"03",x"20",x"00",x"00",x"00",x"04",x"00",x"00",
  -- 0xf130
  x"00",x"07",x"D0",x"07",x"01",x"00",x"00",x"00",
  -- 0xf138
  x"D8",x"80",x"00",x"00",x"00",x"00",x"10",x"00",
  -- 0xf140
  x"E0",x"0F",x"00",x"C0",x"00",x"00",x"00",x"48",
  -- 0xf148
  x"A2",x"67",x"A0",x"F5",x"20",x"55",x"F1",x"A0",
  -- 0xf150
  x"00",x"FB",x"4C",x"9D",x"F1",x"86",x"FB",x"84",
  -- 0xf158
  x"FC",x"A9",x"00",x"85",x"FD",x"A9",x"04",x"85",
  -- 0xf160
  x"FE",x"AE",x"01",x"CF",x"E0",x"00",x"F0",x"22",
  -- 0xf168
  x"18",x"A5",x"FD",x"69",x"28",x"85",x"FD",x"A5",
  -- 0xf170
  x"FE",x"69",x"00",x"85",x"FE",x"C9",x"07",x"90",
  -- 0xf178
  x"0E",x"A5",x"FD",x"C9",x"E8",x"90",x"08",x"A9",
  -- 0xf180
  x"00",x"85",x"FD",x"A9",x"04",x"85",x"FE",x"CA",
  -- 0xf188
  x"D0",x"DA",x"A0",x"27",x"B1",x"FB",x"C9",x"40",
  -- 0xf190
  x"90",x"02",x"29",x"1F",x"91",x"FD",x"88",x"10",
  -- 0xf198
  x"F3",x"EE",x"01",x"CF",x"60",x"6B",x"4A",x"4A",
  -- 0xf1a0
  x"4A",x"4A",x"20",x"A8",x"F1",x"6B",x"29",x"0F",
  -- 0xf1a8
  x"AA",x"B1",x"FD",x"C9",x"24",x"F0",x"06",x"C8",
  -- 0xf1b0
  x"C0",x"28",x"D0",x"F5",x"60",x"8A",x"09",x"30",
  -- 0xf1b8
  x"C9",x"3A",x"90",x"02",x"E9",x"39",x"91",x"FD",
  -- 0xf1c0
  x"C8",x"60",x"AD",x"F1",x"D6",x"10",x"0C",x"A2",
  -- 0xf1c8
  x"57",x"A0",x"F6",x"20",x"55",x"F1",x"AD",x"F1",
  -- 0xf1d0
  x"D6",x"30",x"FB",x"A9",x"82",x"8D",x"80",x"D6",
  -- 0xf1d8
  x"18",x"20",x"25",x"F2",x"A2",x"00",x"BD",x"EC",
  -- 0xf1e0
  x"F1",x"9D",x"40",x"01",x"E8",x"E0",x"28",x"D0",
  -- 0xf1e8
  x"F5",x"4C",x"40",x"01",x"A2",x"00",x"8A",x"9D",
  -- 0xf1f0
  x"00",x"08",x"E8",x"D0",x"FA",x"EE",x"45",x"01",
  -- 0xf1f8
  x"AC",x"45",x"01",x"C0",x"30",x"D0",x"F0",x"A9",
  -- 0xf200
  x"00",x"A2",x"0F",x"A8",x"A3",x"0F",x"5C",x"AA",
  -- 0xf208
  x"4B",x"5C",x"EA",x"A9",x"3F",x"85",x"01",x"85",
  -- 0xf210
  x"00",x"6C",x"FC",x"FF",x"A9",x"00",x"A2",x"0F",
  -- 0xf218
  x"A0",x"00",x"A3",x"8F",x"5C",x"AA",x"A0",x"00",
  -- 0xf220
  x"A3",x"8F",x"5C",x"EA",x"60",x"B0",x"06",x"A9",
  -- 0xf228
  x"00",x"8D",x"2F",x"D0",x"60",x"A9",x"47",x"8D",
  -- 0xf230
  x"2F",x"D0",x"A9",x"53",x"8D",x"2F",x"D0",x"60",
  -- 0xf238
  x"A9",x"FF",x"8D",x"03",x"DC",x"A9",x"00",x"8D",
  -- 0xf240
  x"02",x"DC",x"A9",x"FE",x"8D",x"01",x"DC",x"A9",
  -- 0xf248
  x"20",x"AE",x"00",x"DC",x"E0",x"7F",x"D0",x"02",
  -- 0xf250
  x"A9",x"31",x"E0",x"EF",x"D0",x"02",x"A9",x"39",
  -- 0xf258
  x"E0",x"F7",x"D0",x"02",x"A9",x"37",x"E0",x"FB",
  -- 0xf260
  x"D0",x"02",x"A9",x"35",x"E0",x"FD",x"D0",x"02",
  -- 0xf268
  x"A9",x"33",x"A2",x"F7",x"8E",x"01",x"DC",x"AE",
  -- 0xf270
  x"00",x"DC",x"E0",x"7F",x"D0",x"02",x"A9",x"38",
  -- 0xf278
  x"E0",x"EF",x"D0",x"02",x"A9",x"36",x"E0",x"F7",
  -- 0xf280
  x"D0",x"02",x"A9",x"34",x"E0",x"FB",x"D0",x"02",
  -- 0xf288
  x"A9",x"32",x"E0",x"FD",x"D0",x"02",x"A9",x"30",
  -- 0xf290
  x"8D",x"AC",x"F6",x"8D",x"27",x"04",x"60",x"43",
  -- 0xf298
  x"36",x"35",x"47",x"53",x"20",x"4B",x"49",x"43",
  -- 0xf2a0
  x"4B",x"53",x"54",x"41",x"52",x"54",x"20",x"56",
  -- 0xf2a8
  x"30",x"30",x"2E",x"30",x"30",x"20",x"50",x"52",
  -- 0xf2b0
  x"45",x"2D",x"41",x"4C",x"50",x"48",x"41",x"20",
  -- 0xf2b8
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"52",
  -- 0xf2c0
  x"4F",x"4D",x"20",x"43",x"48",x"45",x"43",x"4B",
  -- 0xf2c8
  x"53",x"55",x"4D",x"20",x"4F",x"4B",x"20",x"2D",
  -- 0xf2d0
  x"20",x"42",x"4F",x"4F",x"54",x"49",x"4E",x"47",
  -- 0xf2d8
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
  -- 0xf2e0
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"52",
  -- 0xf2e8
  x"4F",x"4D",x"20",x"43",x"48",x"45",x"43",x"4B",
  -- 0xf2f0
  x"53",x"55",x"4D",x"20",x"46",x"41",x"49",x"4C",
  -- 0xf2f8
  x"20",x"2D",x"20",x"4C",x"4F",x"41",x"44",x"49",
  -- 0xf300
  x"4E",x"47",x"20",x"52",x"4F",x"4D",x"20",x"20",
  -- 0xf308
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"4C",
  -- 0xf310
  x"4F",x"4F",x"4B",x"49",x"4E",x"47",x"20",x"46",
  -- 0xf318
  x"4F",x"52",x"20",x"53",x"44",x"43",x"41",x"52",
  -- 0xf320
  x"44",x"2E",x"2E",x"2E",x"20",x"20",x"20",x"20",
  -- 0xf328
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
  -- 0xf330
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"46",
  -- 0xf338
  x"4F",x"55",x"4E",x"44",x"20",x"41",x"4E",x"44",
  -- 0xf340
  x"20",x"52",x"45",x"53",x"45",x"54",x"20",x"53",
  -- 0xf348
  x"44",x"43",x"41",x"52",x"44",x"20",x"20",x"20",
  -- 0xf350
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
  -- 0xf358
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"45",
  -- 0xf360
  x"52",x"52",x"4F",x"52",x"20",x"52",x"45",x"41",
  -- 0xf368
  x"44",x"49",x"4E",x"47",x"20",x"46",x"52",x"4F",
  -- 0xf370
  x"4D",x"20",x"53",x"44",x"20",x"43",x"41",x"52",
  -- 0xf378
  x"44",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
  -- 0xf380
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"42",
  -- 0xf388
  x"41",x"44",x"20",x"4D",x"42",x"52",x"20",x"4F",
  -- 0xf390
  x"52",x"20",x"44",x"4F",x"53",x"20",x"42",x"4F",
  -- 0xf398
  x"4F",x"54",x"20",x"53",x"45",x"43",x"54",x"4F",
  -- 0xf3a0
  x"52",x"2E",x"20",x"20",x"20",x"20",x"20",x"20",
  -- 0xf3a8
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"52",
  -- 0xf3b0
  x"45",x"41",x"44",x"20",x"50",x"41",x"52",x"54",
  -- 0xf3b8
  x"49",x"54",x"49",x"4F",x"4E",x"20",x"54",x"41",
  -- 0xf3c0
  x"42",x"4C",x"45",x"20",x"46",x"52",x"4F",x"4D",
  -- 0xf3c8
  x"20",x"53",x"44",x"43",x"41",x"52",x"44",x"20",
  -- 0xf3d0
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"50",
  -- 0xf3d8
  x"41",x"52",x"54",x"49",x"54",x"49",x"4F",x"4E",
  -- 0xf3e0
  x"20",x"31",x"28",x"24",x"24",x"29",x"20",x"40",
  -- 0xf3e8
  x"24",x"24",x"24",x"24",x"24",x"24",x"24",x"24",
  -- 0xf3f0
  x"2C",x"20",x"53",x"49",x"5A",x"45",x"20",x"24",
  -- 0xf3f8
  x"24",x"24",x"24",x"24",x"24",x"24",x"24",x"20",
  -- 0xf400
  x"46",x"53",x"20",x"53",x"50",x"43",x"3A",x"24",
  -- 0xf408
  x"24",x"20",x"52",x"53",x"56",x"53",x"45",x"43",
  -- 0xf410
  x"3A",x"24",x"24",x"24",x"24",x"20",x"52",x"53",
  -- 0xf418
  x"56",x"43",x"4C",x"55",x"53",x"3A",x"24",x"24",
  -- 0xf420
  x"24",x"24",x"24",x"24",x"24",x"24",x"20",x"20",
  -- 0xf428
  x"53",x"59",x"53",x"3A",x"24",x"24",x"24",x"24",
  -- 0xf430
  x"24",x"24",x"24",x"24",x"20",x"44",x"41",x"54",
  -- 0xf438
  x"3A",x"24",x"24",x"24",x"24",x"24",x"24",x"24",
  -- 0xf440
  x"24",x"20",x"43",x"4C",x"55",x"53",x"3A",x"24",
  -- 0xf448
  x"24",x"24",x"24",x"24",x"24",x"24",x"24",x"20",
  -- 0xf450
  x"43",x"4C",x"55",x"53",x"54",x"45",x"52",x"3A",
  -- 0xf458
  x"24",x"24",x"24",x"24",x"24",x"24",x"24",x"24",
  -- 0xf460
  x"20",x"2D",x"3E",x"20",x"53",x"45",x"43",x"54",
  -- 0xf468
  x"4F",x"52",x"3A",x"24",x"24",x"24",x"24",x"24",
  -- 0xf470
  x"24",x"24",x"24",x"20",x"20",x"20",x"20",x"46",
  -- 0xf478
  x"4F",x"55",x"4E",x"44",x"20",x"52",x"4F",x"4D",
  -- 0xf480
  x"20",x"46",x"49",x"4C",x"45",x"2E",x"20",x"53",
  -- 0xf488
  x"54",x"41",x"52",x"54",x"20",x"43",x"4C",x"55",
  -- 0xf490
  x"53",x"54",x"45",x"52",x"20",x"3D",x"20",x"24",
  -- 0xf498
  x"24",x"24",x"24",x"24",x"24",x"24",x"24",x"43",
  -- 0xf4a0
  x"4F",x"55",x"4C",x"44",x"20",x"4E",x"4F",x"54",
  -- 0xf4a8
  x"20",x"4F",x"50",x"45",x"4E",x"20",x"52",x"4F",
  -- 0xf4b0
  x"4D",x"20",x"46",x"49",x"4C",x"45",x"20",x"46",
  -- 0xf4b8
  x"4F",x"52",x"20",x"52",x"45",x"41",x"44",x"49",
  -- 0xf4c0
  x"4E",x"47",x"20",x"20",x"20",x"20",x"20",x"52",
  -- 0xf4c8
  x"45",x"41",x"44",x"49",x"4E",x"47",x"20",x"52",
  -- 0xf4d0
  x"4F",x"4D",x"20",x"46",x"49",x"4C",x"45",x"2E",
  -- 0xf4d8
  x"2E",x"2E",x"20",x"20",x"20",x"20",x"20",x"20",
  -- 0xf4e0
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
  -- 0xf4e8
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"52",
  -- 0xf4f0
  x"4F",x"4D",x"20",x"46",x"49",x"4C",x"45",x"20",
  -- 0xf4f8
  x"57",x"52",x"4F",x"4E",x"47",x"20",x"53",x"49",
  -- 0xf500
  x"5A",x"45",x"3A",x"20",x"4D",x"55",x"53",x"54",
  -- 0xf508
  x"20",x"42",x"45",x"20",x"31",x"32",x"38",x"4B",
  -- 0xf510
  x"42",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
  -- 0xf518
  x"4E",x"45",x"58",x"54",x"20",x"43",x"4C",x"55",
  -- 0xf520
  x"53",x"54",x"45",x"52",x"3D",x"24",x"24",x"24",
  -- 0xf528
  x"24",x"24",x"24",x"24",x"24",x"20",x"20",x"20",
  -- 0xf530
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
  -- 0xf538
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
  -- 0xf540
  x"4E",x"45",x"58",x"54",x"20",x"53",x"45",x"43",
  -- 0xf548
  x"54",x"4F",x"52",x"3D",x"24",x"24",x"24",x"24",
  -- 0xf550
  x"24",x"24",x"24",x"24",x"20",x"20",x"20",x"20",
  -- 0xf558
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
  -- 0xf560
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
  -- 0xf568
  x"43",x"48",x"45",x"43",x"4B",x"50",x"4F",x"49",
  -- 0xf570
  x"4E",x"54",x"20",x"24",x"24",x"20",x"24",x"24",
  -- 0xf578
  x"20",x"24",x"24",x"20",x"24",x"24",x"20",x"24",
  -- 0xf580
  x"24",x"20",x"24",x"24",x"20",x"24",x"24",x"20",
  -- 0xf588
  x"24",x"24",x"20",x"24",x"24",x"20",x"20",x"43",
  -- 0xf590
  x"41",x"4E",x"4E",x"4F",x"54",x"20",x"46",x"49",
  -- 0xf598
  x"4E",x"44",x"20",x"43",x"36",x"35",x"47",x"53",
  -- 0xf5a0
  x"2E",x"44",x"38",x"31",x"20",x"2D",x"20",x"42",
  -- 0xf5a8
  x"4F",x"4F",x"54",x"49",x"4E",x"47",x"20",x"44",
  -- 0xf5b0
  x"49",x"53",x"4B",x"4C",x"45",x"53",x"53",x"4D",
  -- 0xf5b8
  x"4F",x"55",x"4E",x"54",x"49",x"4E",x"47",x"20",
  -- 0xf5c0
  x"43",x"36",x"35",x"47",x"53",x"2E",x"44",x"38",
  -- 0xf5c8
  x"31",x"20",x"40",x"20",x"49",x"4E",x"54",x"45",
  -- 0xf5d0
  x"52",x"4E",x"41",x"4C",x"20",x"46",x"30",x"31",
  -- 0xf5d8
  x"31",x"20",x"44",x"52",x"49",x"56",x"45",x"46",
  -- 0xf5e0
  x"41",x"49",x"4C",x"3A",x"20",x"43",x"36",x"34",
  -- 0xf5e8
  x"47",x"53",x"2E",x"44",x"38",x"31",x"20",x"49",
  -- 0xf5f0
  x"53",x"20",x"4E",x"4F",x"54",x"20",x"38",x"31",
  -- 0xf5f8
  x"39",x"32",x"30",x"30",x"20",x"42",x"59",x"54",
  -- 0xf600
  x"45",x"53",x"20",x"4C",x"4F",x"4E",x"47",x"46",
  -- 0xf608
  x"41",x"49",x"4C",x"3A",x"20",x"43",x"36",x"35",
  -- 0xf610
  x"47",x"53",x"2E",x"44",x"38",x"31",x"20",x"49",
  -- 0xf618
  x"53",x"20",x"46",x"52",x"41",x"47",x"4D",x"45",
  -- 0xf620
  x"4E",x"54",x"45",x"44",x"3A",x"20",x"44",x"45",
  -- 0xf628
  x"46",x"52",x"41",x"47",x"20",x"49",x"54",x"43",
  -- 0xf630
  x"36",x"35",x"47",x"53",x"2E",x"44",x"38",x"31",
  -- 0xf638
  x"20",x"53",x"55",x"43",x"43",x"45",x"53",x"53",
  -- 0xf640
  x"46",x"55",x"4C",x"4C",x"59",x"20",x"4D",x"4F",
  -- 0xf648
  x"55",x"4E",x"54",x"45",x"44",x"20",x"20",x"20",
  -- 0xf650
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"52",
  -- 0xf658
  x"45",x"4C",x"45",x"41",x"53",x"45",x"20",x"53",
  -- 0xf660
  x"57",x"31",x"35",x"20",x"54",x"4F",x"20",x"43",
  -- 0xf668
  x"4F",x"4E",x"54",x"49",x"4E",x"55",x"45",x"20",
  -- 0xf670
  x"42",x"4F",x"4F",x"54",x"49",x"4E",x"47",x"2E",
  -- 0xf678
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"43",
  -- 0xf680
  x"4F",x"55",x"4C",x"44",x"20",x"4E",x"4F",x"54",
  -- 0xf688
  x"20",x"46",x"49",x"4E",x"44",x"20",x"52",x"4F",
  -- 0xf690
  x"4D",x"20",x"43",x"36",x"35",x"47",x"53",x"58",
  -- 0xf698
  x"58",x"58",x"52",x"4F",x"4D",x"20",x"20",x"20",
  -- 0xf6a0
  x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"43",
  -- 0xf6a8
  x"36",x"35",x"47",x"53",x"20",x"20",x"20",x"52",
  -- 0xf6b0
  x"4F",x"4D",x"43",x"36",x"35",x"47",x"53",x"20",
  -- 0xf6b8
  x"20",x"20",x"44",x"38",x"31",x"78",x"D8",x"03",
  -- 0xf6c0
  x"A9",x"00",x"8D",x"17",x"D0",x"A9",x"00",x"5B",
  -- 0xf6c8
  x"A0",x"01",x"2B",x"A2",x"FF",x"9A",x"A9",x"7F",
  -- 0xf6d0
  x"8D",x"0D",x"DC",x"8D",x"0D",x"DD",x"A9",x"00",
  -- 0xf6d8
  x"8D",x"1A",x"D0",x"4C",x"FF",x"E6",x"48",x"AD",
  -- 0xf6e0
  x"0D",x"DC",x"AD",x"0D",x"DD",x"0E",x"19",x"D0",
  -- 0xf6e8
  x"68",x"40",x"8D",x"00",x"40",x"8E",x"01",x"40",
  -- 0xf6f0
  x"8C",x"02",x"40",x"9C",x"03",x"40",x"38",x"20",
  -- 0xf6f8
  x"25",x"F2",x"20",x"E3",x"EF",x"20",x"0E",x"F0",
  -- 0xf700
  x"20",x"F5",x"F0",x"A2",x"21",x"A0",x"F7",x"20",
  -- 0xf708
  x"55",x"F1",x"A0",x"00",x"AB",x"03",x"40",x"20",
  -- 0xf710
  x"9D",x"F1",x"AB",x"01",x"40",x"20",x"9D",x"F1",
  -- 0xf718
  x"AB",x"02",x"40",x"20",x"9D",x"F1",x"4C",x"1E",
  -- 0xf720
  x"F7",x"20",x"2A",x"2A",x"2A",x"2A",x"20",x"43",
  -- 0xf728
  x"50",x"55",x"20",x"45",x"52",x"52",x"4F",x"52",
  -- 0xf730
  x"3A",x"20",x"4F",x"50",x"43",x"4F",x"44",x"45",
  -- 0xf738
  x"3D",x"24",x"24",x"20",x"50",x"43",x"3D",x"24",
  -- 0xf740
  x"24",x"24",x"24",x"20",x"2A",x"2A",x"2A",x"2A",
  -- 0xf748
  x"20",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf750
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf758
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf760
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf768
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf770
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf778
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf780
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf788
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf790
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf798
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf7a0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf7a8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf7b0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf7b8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf7c0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf7c8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf7d0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf7d8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf7e0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf7e8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf7f0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf7f8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf800
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf808
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf810
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf818
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf820
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf828
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf830
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf838
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf840
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf848
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf850
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf858
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf860
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf868
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf870
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf878
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf880
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf888
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf890
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf898
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf8a0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf8a8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf8b0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf8b8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf8c0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf8c8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf8d0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf8d8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf8e0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf8e8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf8f0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf8f8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf900
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf908
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf910
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf918
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf920
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf928
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf930
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf938
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf940
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf948
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf950
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf958
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf960
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf968
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf970
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf978
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf980
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf988
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf990
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf998
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf9a0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf9a8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf9b0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf9b8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf9c0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf9c8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf9d0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf9d8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf9e0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf9e8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf9f0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xf9f8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa00
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa08
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa10
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa18
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa20
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa28
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa30
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa38
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa40
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa48
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa50
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa58
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa60
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa68
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa70
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa78
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa80
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa88
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa90
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfa98
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfaa0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfaa8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfab0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfab8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfac0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfac8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfad0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfad8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfae0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfae8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfaf0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfaf8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb00
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb08
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb10
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb18
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb20
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb28
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb30
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb38
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb40
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb48
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb50
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb58
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb60
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb68
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb70
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb78
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb80
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb88
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb90
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfb98
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfba0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfba8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfbb0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfbb8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfbc0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfbc8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfbd0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfbd8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfbe0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfbe8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfbf0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfbf8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc00
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc08
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc10
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc18
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc20
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc28
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc30
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc38
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc40
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc48
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc50
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc58
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc60
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc68
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc70
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc78
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc80
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc88
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc90
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfc98
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfca0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfca8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfcb0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfcb8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfcc0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfcc8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfcd0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfcd8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfce0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfce8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfcf0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfcf8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd00
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd08
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd10
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd18
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd20
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd28
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd30
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd38
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd40
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd48
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd50
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd58
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd60
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd68
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd70
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd78
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd80
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd88
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd90
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfd98
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfda0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfda8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfdb0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfdb8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfdc0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfdc8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfdd0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfdd8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfde0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfde8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfdf0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfdf8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe00
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe08
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe10
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe18
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe20
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe28
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe30
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe38
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe40
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe48
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe50
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe58
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe60
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe68
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe70
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe78
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe80
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe88
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe90
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfe98
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfea0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfea8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfeb0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfeb8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfec0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfec8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfed0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfed8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfee0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfee8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfef0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfef8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff00
  x"4C",x"25",x"F2",x"4C",x"22",x"EE",x"4C",x"29",
  -- 0xff08
  x"EE",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff10
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff18
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff20
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff28
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff30
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff38
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff40
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff48
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff50
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff58
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff60
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff68
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff70
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff78
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff80
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff88
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff90
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xff98
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xffa0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xffa8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xffb0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xffb8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xffc0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xffc8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xffd0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xffd8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xffe0
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xffe8
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfff0
  x"EA",x"F6",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xfff8
  x"00",x"00",x"DE",x"F6",x"BD",x"F6",x"DE",x"F6");

begin

--process for read and write operation.
  PROCESS(Clk,cs,ram,address)
  BEGIN
    if(rising_edge(Clk)) then 
      if cs='1' then
        if(we='1') then
          ram(to_integer(unsigned(address))) <= data_i;
        end if;
        data_o <= ram(to_integer(unsigned(address)));
      end if;
    end if;
    if cs='1' then
      data_o <= ram(to_integer(unsigned(address)));
    else
      data_o <= "ZZZZZZZZ";
    end if;
  END PROCESS;

end Behavioral;
