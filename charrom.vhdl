library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

--
entity charrom is
port (Clk : in std_logic;
        address : in integer range 0 to 4095;
        -- chip select, active low       
        cs : in std_logic;
        data_o : out std_logic_vector(7 downto 0);

        writeclk : in std_logic;
        -- Yes, we do have a write enable, because we allow modification of ROMs
        -- in the running machine, unless purposely disabled.  This gives us
        -- something like the WOM that the Amiga had.
        writecs : in std_logic;
        we : in std_logic;
        writeaddress : in unsigned(11 downto 0);
        data_i : in std_logic_vector(7 downto 0)
      );
end charrom;

architecture Behavioral of charrom is

-- 4K x 8bit pre-initialised RAM
type ram_t is array (0 to 4095) of std_logic_vector(7 downto 0);
signal ram : ram_t := (
  -- 0xe000
  x"3C",x"66",x"6E",x"6E",x"60",x"62",x"3C",x"00",
  -- 0xe008
  x"18",x"3C",x"66",x"7E",x"66",x"66",x"66",x"00",
  -- 0xe010
  x"7C",x"66",x"66",x"7C",x"66",x"66",x"7C",x"00",
  -- 0xe018
  x"3C",x"66",x"60",x"60",x"60",x"66",x"3C",x"00",
  -- 0xe020
  x"78",x"6C",x"66",x"66",x"66",x"6C",x"78",x"00",
  -- 0xe028
  x"7E",x"60",x"60",x"78",x"60",x"60",x"7E",x"00",
  -- 0xe030
  x"7E",x"60",x"60",x"78",x"60",x"60",x"60",x"00",
  -- 0xe038
  x"3C",x"66",x"60",x"6E",x"66",x"66",x"3C",x"00",
  -- 0xe040
  x"66",x"66",x"66",x"7E",x"66",x"66",x"66",x"00",
  -- 0xe048
  x"3C",x"18",x"18",x"18",x"18",x"18",x"3C",x"00",
  -- 0xe050
  x"1E",x"0C",x"0C",x"0C",x"0C",x"6C",x"38",x"00",
  -- 0xe058
  x"66",x"6C",x"78",x"70",x"78",x"6C",x"66",x"00",
  -- 0xe060
  x"60",x"60",x"60",x"60",x"60",x"60",x"7E",x"00",
  -- 0xe068
  x"63",x"77",x"7F",x"6B",x"63",x"63",x"63",x"00",
  -- 0xe070
  x"66",x"76",x"7E",x"7E",x"6E",x"66",x"66",x"00",
  -- 0xe078
  x"3C",x"66",x"66",x"66",x"66",x"66",x"3C",x"00",
  -- 0xe080
  x"7C",x"66",x"66",x"7C",x"60",x"60",x"60",x"00",
  -- 0xe088
  x"3C",x"66",x"66",x"66",x"66",x"3C",x"0E",x"00",
  -- 0xe090
  x"7C",x"66",x"66",x"7C",x"78",x"6C",x"66",x"00",
  -- 0xe098
  x"3C",x"66",x"60",x"3C",x"06",x"66",x"3C",x"00",
  -- 0xe0a0
  x"7E",x"18",x"18",x"18",x"18",x"18",x"18",x"00",
  -- 0xe0a8
  x"66",x"66",x"66",x"66",x"66",x"66",x"3C",x"00",
  -- 0xe0b0
  x"66",x"66",x"66",x"66",x"66",x"3C",x"18",x"00",
  -- 0xe0b8
  x"63",x"63",x"63",x"6B",x"7F",x"77",x"63",x"00",
  -- 0xe0c0
  x"66",x"66",x"3C",x"18",x"3C",x"66",x"66",x"00",
  -- 0xe0c8
  x"66",x"66",x"66",x"3C",x"18",x"18",x"18",x"00",
  -- 0xe0d0
  x"7E",x"06",x"0C",x"18",x"30",x"60",x"7E",x"00",
  -- 0xe0d8
  x"3C",x"30",x"30",x"30",x"30",x"30",x"3C",x"00",
  -- 0xe0e0
  x"0C",x"12",x"30",x"7C",x"30",x"62",x"FC",x"00",
  -- 0xe0e8
  x"3C",x"0C",x"0C",x"0C",x"0C",x"0C",x"3C",x"00",
  -- 0xe0f0
  x"00",x"18",x"3C",x"7E",x"18",x"18",x"18",x"18",
  -- 0xe0f8
  x"00",x"10",x"30",x"7F",x"7F",x"30",x"10",x"00",
  -- 0xe100
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xe108
  x"18",x"18",x"18",x"18",x"00",x"00",x"18",x"00",
  -- 0xe110
  x"66",x"66",x"66",x"00",x"00",x"00",x"00",x"00",
  -- 0xe118
  x"66",x"66",x"FF",x"66",x"FF",x"66",x"66",x"00",
  -- 0xe120
  x"18",x"3E",x"60",x"3C",x"06",x"7C",x"18",x"00",
  -- 0xe128
  x"62",x"66",x"0C",x"18",x"30",x"66",x"46",x"00",
  -- 0xe130
  x"3C",x"66",x"3C",x"38",x"67",x"66",x"3F",x"00",
  -- 0xe138
  x"06",x"0C",x"18",x"00",x"00",x"00",x"00",x"00",
  -- 0xe140
  x"0C",x"18",x"30",x"30",x"30",x"18",x"0C",x"00",
  -- 0xe148
  x"30",x"18",x"0C",x"0C",x"0C",x"18",x"30",x"00",
  -- 0xe150
  x"00",x"66",x"3C",x"FF",x"3C",x"66",x"00",x"00",
  -- 0xe158
  x"00",x"18",x"18",x"7E",x"18",x"18",x"00",x"00",
  -- 0xe160
  x"00",x"00",x"00",x"00",x"00",x"18",x"18",x"30",
  -- 0xe168
  x"00",x"00",x"00",x"7E",x"00",x"00",x"00",x"00",
  -- 0xe170
  x"00",x"00",x"00",x"00",x"00",x"18",x"18",x"00",
  -- 0xe178
  x"00",x"03",x"06",x"0C",x"18",x"30",x"60",x"00",
  -- 0xe180
  x"3C",x"66",x"6E",x"76",x"66",x"66",x"3C",x"00",
  -- 0xe188
  x"18",x"18",x"38",x"18",x"18",x"18",x"7E",x"00",
  -- 0xe190
  x"3C",x"66",x"06",x"0C",x"30",x"60",x"7E",x"00",
  -- 0xe198
  x"3C",x"66",x"06",x"1C",x"06",x"66",x"3C",x"00",
  -- 0xe1a0
  x"06",x"0E",x"1E",x"66",x"7F",x"06",x"06",x"00",
  -- 0xe1a8
  x"7E",x"60",x"7C",x"06",x"06",x"66",x"3C",x"00",
  -- 0xe1b0
  x"3C",x"66",x"60",x"7C",x"66",x"66",x"3C",x"00",
  -- 0xe1b8
  x"7E",x"66",x"0C",x"18",x"18",x"18",x"18",x"00",
  -- 0xe1c0
  x"3C",x"66",x"66",x"3C",x"66",x"66",x"3C",x"00",
  -- 0xe1c8
  x"3C",x"66",x"66",x"3E",x"06",x"66",x"3C",x"00",
  -- 0xe1d0
  x"00",x"00",x"18",x"00",x"00",x"18",x"00",x"00",
  -- 0xe1d8
  x"00",x"00",x"18",x"00",x"00",x"18",x"18",x"30",
  -- 0xe1e0
  x"0E",x"18",x"30",x"60",x"30",x"18",x"0E",x"00",
  -- 0xe1e8
  x"00",x"00",x"7E",x"00",x"7E",x"00",x"00",x"00",
  -- 0xe1f0
  x"70",x"18",x"0C",x"06",x"0C",x"18",x"70",x"00",
  -- 0xe1f8
  x"3C",x"66",x"06",x"0C",x"18",x"00",x"18",x"00",
  -- 0xe200
  x"00",x"00",x"00",x"FF",x"FF",x"00",x"00",x"00",
  -- 0xe208
  x"08",x"1C",x"3E",x"7F",x"7F",x"1C",x"3E",x"00",
  -- 0xe210
  x"18",x"18",x"18",x"18",x"18",x"18",x"18",x"18",
  -- 0xe218
  x"00",x"00",x"00",x"FF",x"FF",x"00",x"00",x"00",
  -- 0xe220
  x"00",x"00",x"FF",x"FF",x"00",x"00",x"00",x"00",
  -- 0xe228
  x"00",x"FF",x"FF",x"00",x"00",x"00",x"00",x"00",
  -- 0xe230
  x"00",x"00",x"00",x"00",x"FF",x"FF",x"00",x"00",
  -- 0xe238
  x"30",x"30",x"30",x"30",x"30",x"30",x"30",x"30",
  -- 0xe240
  x"0C",x"0C",x"0C",x"0C",x"0C",x"0C",x"0C",x"0C",
  -- 0xe248
  x"00",x"00",x"00",x"E0",x"F0",x"38",x"18",x"18",
  -- 0xe250
  x"18",x"18",x"1C",x"0F",x"07",x"00",x"00",x"00",
  -- 0xe258
  x"18",x"18",x"38",x"F0",x"E0",x"00",x"00",x"00",
  -- 0xe260
  x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",x"FF",x"FF",
  -- 0xe268
  x"C0",x"E0",x"70",x"38",x"1C",x"0E",x"07",x"03",
  -- 0xe270
  x"03",x"07",x"0E",x"1C",x"38",x"70",x"E0",x"C0",
  -- 0xe278
  x"FF",x"FF",x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",
  -- 0xe280
  x"FF",x"FF",x"03",x"03",x"03",x"03",x"03",x"03",
  -- 0xe288
  x"00",x"3C",x"7E",x"7E",x"7E",x"7E",x"3C",x"00",
  -- 0xe290
  x"00",x"00",x"00",x"00",x"00",x"FF",x"FF",x"00",
  -- 0xe298
  x"36",x"7F",x"7F",x"7F",x"3E",x"1C",x"08",x"00",
  -- 0xe2a0
  x"60",x"60",x"60",x"60",x"60",x"60",x"60",x"60",
  -- 0xe2a8
  x"00",x"00",x"00",x"07",x"0F",x"1C",x"18",x"18",
  -- 0xe2b0
  x"C3",x"E7",x"7E",x"3C",x"3C",x"7E",x"E7",x"C3",
  -- 0xe2b8
  x"00",x"3C",x"7E",x"66",x"66",x"7E",x"3C",x"00",
  -- 0xe2c0
  x"18",x"18",x"66",x"66",x"18",x"18",x"3C",x"00",
  -- 0xe2c8
  x"06",x"06",x"06",x"06",x"06",x"06",x"06",x"06",
  -- 0xe2d0
  x"08",x"1C",x"3E",x"7F",x"3E",x"1C",x"08",x"00",
  -- 0xe2d8
  x"18",x"18",x"18",x"FF",x"FF",x"18",x"18",x"18",
  -- 0xe2e0
  x"C0",x"C0",x"30",x"30",x"C0",x"C0",x"30",x"30",
  -- 0xe2e8
  x"18",x"18",x"18",x"18",x"18",x"18",x"18",x"18",
  -- 0xe2f0
  x"00",x"00",x"03",x"3E",x"76",x"36",x"36",x"00",
  -- 0xe2f8
  x"FF",x"7F",x"3F",x"1F",x"0F",x"07",x"03",x"01",
  -- 0xe300
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xe308
  x"F0",x"F0",x"F0",x"F0",x"F0",x"F0",x"F0",x"F0",
  -- 0xe310
  x"00",x"00",x"00",x"00",x"FF",x"FF",x"FF",x"FF",
  -- 0xe318
  x"FF",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xe320
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"FF",
  -- 0xe328
  x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",
  -- 0xe330
  x"CC",x"CC",x"33",x"33",x"CC",x"CC",x"33",x"33",
  -- 0xe338
  x"03",x"03",x"03",x"03",x"03",x"03",x"03",x"03",
  -- 0xe340
  x"00",x"00",x"00",x"00",x"CC",x"CC",x"33",x"33",
  -- 0xe348
  x"FF",x"FE",x"FC",x"F8",x"F0",x"E0",x"C0",x"80",
  -- 0xe350
  x"03",x"03",x"03",x"03",x"03",x"03",x"03",x"03",
  -- 0xe358
  x"18",x"18",x"18",x"1F",x"1F",x"18",x"18",x"18",
  -- 0xe360
  x"00",x"00",x"00",x"00",x"0F",x"0F",x"0F",x"0F",
  -- 0xe368
  x"18",x"18",x"18",x"1F",x"1F",x"00",x"00",x"00",
  -- 0xe370
  x"00",x"00",x"00",x"F8",x"F8",x"18",x"18",x"18",
  -- 0xe378
  x"00",x"00",x"00",x"00",x"00",x"00",x"FF",x"FF",
  -- 0xe380
  x"00",x"00",x"00",x"1F",x"1F",x"18",x"18",x"18",
  -- 0xe388
  x"18",x"18",x"18",x"FF",x"FF",x"00",x"00",x"00",
  -- 0xe390
  x"00",x"00",x"00",x"FF",x"FF",x"18",x"18",x"18",
  -- 0xe398
  x"18",x"18",x"18",x"F8",x"F8",x"18",x"18",x"18",
  -- 0xe3a0
  x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",
  -- 0xe3a8
  x"E0",x"E0",x"E0",x"E0",x"E0",x"E0",x"E0",x"E0",
  -- 0xe3b0
  x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",
  -- 0xe3b8
  x"FF",x"FF",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xe3c0
  x"FF",x"FF",x"FF",x"00",x"00",x"00",x"00",x"00",
  -- 0xe3c8
  x"00",x"00",x"00",x"00",x"00",x"FF",x"FF",x"FF",
  -- 0xe3d0
  x"03",x"03",x"03",x"03",x"03",x"03",x"FF",x"FF",
  -- 0xe3d8
  x"00",x"00",x"00",x"00",x"F0",x"F0",x"F0",x"F0",
  -- 0xe3e0
  x"0F",x"0F",x"0F",x"0F",x"00",x"00",x"00",x"00",
  -- 0xe3e8
  x"18",x"18",x"18",x"F8",x"F8",x"00",x"00",x"00",
  -- 0xe3f0
  x"F0",x"F0",x"F0",x"F0",x"00",x"00",x"00",x"00",
  -- 0xe3f8
  x"F0",x"F0",x"F0",x"F0",x"0F",x"0F",x"0F",x"0F",
  -- 0xe400
  x"C3",x"99",x"91",x"91",x"9F",x"99",x"C3",x"FF",
  -- 0xe408
  x"E7",x"C3",x"99",x"81",x"99",x"99",x"99",x"FF",
  -- 0xe410
  x"83",x"99",x"99",x"83",x"99",x"99",x"83",x"FF",
  -- 0xe418
  x"C3",x"99",x"9F",x"9F",x"9F",x"99",x"C3",x"FF",
  -- 0xe420
  x"87",x"93",x"99",x"99",x"99",x"93",x"87",x"FF",
  -- 0xe428
  x"81",x"9F",x"9F",x"87",x"9F",x"9F",x"81",x"FF",
  -- 0xe430
  x"81",x"9F",x"9F",x"87",x"9F",x"9F",x"9F",x"FF",
  -- 0xe438
  x"C3",x"99",x"9F",x"91",x"99",x"99",x"C3",x"FF",
  -- 0xe440
  x"99",x"99",x"99",x"81",x"99",x"99",x"99",x"FF",
  -- 0xe448
  x"C3",x"E7",x"E7",x"E7",x"E7",x"E7",x"C3",x"FF",
  -- 0xe450
  x"E1",x"F3",x"F3",x"F3",x"F3",x"93",x"C7",x"FF",
  -- 0xe458
  x"99",x"93",x"87",x"8F",x"87",x"93",x"99",x"FF",
  -- 0xe460
  x"9F",x"9F",x"9F",x"9F",x"9F",x"9F",x"81",x"FF",
  -- 0xe468
  x"9C",x"88",x"80",x"94",x"9C",x"9C",x"9C",x"FF",
  -- 0xe470
  x"99",x"89",x"81",x"81",x"91",x"99",x"99",x"FF",
  -- 0xe478
  x"C3",x"99",x"99",x"99",x"99",x"99",x"C3",x"FF",
  -- 0xe480
  x"83",x"99",x"99",x"83",x"9F",x"9F",x"9F",x"FF",
  -- 0xe488
  x"C3",x"99",x"99",x"99",x"99",x"C3",x"F1",x"FF",
  -- 0xe490
  x"83",x"99",x"99",x"83",x"87",x"93",x"99",x"FF",
  -- 0xe498
  x"C3",x"99",x"9F",x"C3",x"F9",x"99",x"C3",x"FF",
  -- 0xe4a0
  x"81",x"E7",x"E7",x"E7",x"E7",x"E7",x"E7",x"FF",
  -- 0xe4a8
  x"99",x"99",x"99",x"99",x"99",x"99",x"C3",x"FF",
  -- 0xe4b0
  x"99",x"99",x"99",x"99",x"99",x"C3",x"E7",x"FF",
  -- 0xe4b8
  x"9C",x"9C",x"9C",x"94",x"80",x"88",x"9C",x"FF",
  -- 0xe4c0
  x"99",x"99",x"C3",x"E7",x"C3",x"99",x"99",x"FF",
  -- 0xe4c8
  x"99",x"99",x"99",x"C3",x"E7",x"E7",x"E7",x"FF",
  -- 0xe4d0
  x"81",x"F9",x"F3",x"E7",x"CF",x"9F",x"81",x"FF",
  -- 0xe4d8
  x"C3",x"CF",x"CF",x"CF",x"CF",x"CF",x"C3",x"FF",
  -- 0xe4e0
  x"F3",x"ED",x"CF",x"83",x"CF",x"9D",x"03",x"FF",
  -- 0xe4e8
  x"C3",x"F3",x"F3",x"F3",x"F3",x"F3",x"C3",x"FF",
  -- 0xe4f0
  x"FF",x"E7",x"C3",x"81",x"E7",x"E7",x"E7",x"E7",
  -- 0xe4f8
  x"FF",x"EF",x"CF",x"80",x"80",x"CF",x"EF",x"FF",
  -- 0xe500
  x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xe508
  x"E7",x"E7",x"E7",x"E7",x"FF",x"FF",x"E7",x"FF",
  -- 0xe510
  x"99",x"99",x"99",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xe518
  x"99",x"99",x"00",x"99",x"00",x"99",x"99",x"FF",
  -- 0xe520
  x"E7",x"C1",x"9F",x"C3",x"F9",x"83",x"E7",x"FF",
  -- 0xe528
  x"9D",x"99",x"F3",x"E7",x"CF",x"99",x"B9",x"FF",
  -- 0xe530
  x"C3",x"99",x"C3",x"C7",x"98",x"99",x"C0",x"FF",
  -- 0xe538
  x"F9",x"F3",x"E7",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xe540
  x"F3",x"E7",x"CF",x"CF",x"CF",x"E7",x"F3",x"FF",
  -- 0xe548
  x"CF",x"E7",x"F3",x"F3",x"F3",x"E7",x"CF",x"FF",
  -- 0xe550
  x"FF",x"99",x"C3",x"00",x"C3",x"99",x"FF",x"FF",
  -- 0xe558
  x"FF",x"E7",x"E7",x"81",x"E7",x"E7",x"FF",x"FF",
  -- 0xe560
  x"FF",x"FF",x"FF",x"FF",x"FF",x"E7",x"E7",x"CF",
  -- 0xe568
  x"FF",x"FF",x"FF",x"81",x"FF",x"FF",x"FF",x"FF",
  -- 0xe570
  x"FF",x"FF",x"FF",x"FF",x"FF",x"E7",x"E7",x"FF",
  -- 0xe578
  x"FF",x"FC",x"F9",x"F3",x"E7",x"CF",x"9F",x"FF",
  -- 0xe580
  x"C3",x"99",x"91",x"89",x"99",x"99",x"C3",x"FF",
  -- 0xe588
  x"E7",x"E7",x"C7",x"E7",x"E7",x"E7",x"81",x"FF",
  -- 0xe590
  x"C3",x"99",x"F9",x"F3",x"CF",x"9F",x"81",x"FF",
  -- 0xe598
  x"C3",x"99",x"F9",x"E3",x"F9",x"99",x"C3",x"FF",
  -- 0xe5a0
  x"F9",x"F1",x"E1",x"99",x"80",x"F9",x"F9",x"FF",
  -- 0xe5a8
  x"81",x"9F",x"83",x"F9",x"F9",x"99",x"C3",x"FF",
  -- 0xe5b0
  x"C3",x"99",x"9F",x"83",x"99",x"99",x"C3",x"FF",
  -- 0xe5b8
  x"81",x"99",x"F3",x"E7",x"E7",x"E7",x"E7",x"FF",
  -- 0xe5c0
  x"C3",x"99",x"99",x"C3",x"99",x"99",x"C3",x"FF",
  -- 0xe5c8
  x"C3",x"99",x"99",x"C1",x"F9",x"99",x"C3",x"FF",
  -- 0xe5d0
  x"FF",x"FF",x"E7",x"FF",x"FF",x"E7",x"FF",x"FF",
  -- 0xe5d8
  x"FF",x"FF",x"E7",x"FF",x"FF",x"E7",x"E7",x"CF",
  -- 0xe5e0
  x"F1",x"E7",x"CF",x"9F",x"CF",x"E7",x"F1",x"FF",
  -- 0xe5e8
  x"FF",x"FF",x"81",x"FF",x"81",x"FF",x"FF",x"FF",
  -- 0xe5f0
  x"8F",x"E7",x"F3",x"F9",x"F3",x"E7",x"8F",x"FF",
  -- 0xe5f8
  x"C3",x"99",x"F9",x"F3",x"E7",x"FF",x"E7",x"FF",
  -- 0xe600
  x"FF",x"FF",x"FF",x"00",x"00",x"FF",x"FF",x"FF",
  -- 0xe608
  x"F7",x"E3",x"C1",x"80",x"80",x"E3",x"C1",x"FF",
  -- 0xe610
  x"E7",x"E7",x"E7",x"E7",x"E7",x"E7",x"E7",x"E7",
  -- 0xe618
  x"FF",x"FF",x"FF",x"00",x"00",x"FF",x"FF",x"FF",
  -- 0xe620
  x"FF",x"FF",x"00",x"00",x"FF",x"FF",x"FF",x"FF",
  -- 0xe628
  x"FF",x"00",x"00",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xe630
  x"FF",x"FF",x"FF",x"FF",x"00",x"00",x"FF",x"FF",
  -- 0xe638
  x"CF",x"CF",x"CF",x"CF",x"CF",x"CF",x"CF",x"CF",
  -- 0xe640
  x"F3",x"F3",x"F3",x"F3",x"F3",x"F3",x"F3",x"F3",
  -- 0xe648
  x"FF",x"FF",x"FF",x"1F",x"0F",x"C7",x"E7",x"E7",
  -- 0xe650
  x"E7",x"E7",x"E3",x"F0",x"F8",x"FF",x"FF",x"FF",
  -- 0xe658
  x"E7",x"E7",x"C7",x"0F",x"1F",x"FF",x"FF",x"FF",
  -- 0xe660
  x"3F",x"3F",x"3F",x"3F",x"3F",x"3F",x"00",x"00",
  -- 0xe668
  x"3F",x"1F",x"8F",x"C7",x"E3",x"F1",x"F8",x"FC",
  -- 0xe670
  x"FC",x"F8",x"F1",x"E3",x"C7",x"8F",x"1F",x"3F",
  -- 0xe678
  x"00",x"00",x"3F",x"3F",x"3F",x"3F",x"3F",x"3F",
  -- 0xe680
  x"00",x"00",x"FC",x"FC",x"FC",x"FC",x"FC",x"FC",
  -- 0xe688
  x"FF",x"C3",x"81",x"81",x"81",x"81",x"C3",x"FF",
  -- 0xe690
  x"FF",x"FF",x"FF",x"FF",x"FF",x"00",x"00",x"FF",
  -- 0xe698
  x"C9",x"80",x"80",x"80",x"C1",x"E3",x"F7",x"FF",
  -- 0xe6a0
  x"9F",x"9F",x"9F",x"9F",x"9F",x"9F",x"9F",x"9F",
  -- 0xe6a8
  x"FF",x"FF",x"FF",x"F8",x"F0",x"E3",x"E7",x"E7",
  -- 0xe6b0
  x"3C",x"18",x"81",x"C3",x"C3",x"81",x"18",x"3C",
  -- 0xe6b8
  x"FF",x"C3",x"81",x"99",x"99",x"81",x"C3",x"FF",
  -- 0xe6c0
  x"E7",x"E7",x"99",x"99",x"E7",x"E7",x"C3",x"FF",
  -- 0xe6c8
  x"F9",x"F9",x"F9",x"F9",x"F9",x"F9",x"F9",x"F9",
  -- 0xe6d0
  x"F7",x"E3",x"C1",x"80",x"C1",x"E3",x"F7",x"FF",
  -- 0xe6d8
  x"E7",x"E7",x"E7",x"00",x"00",x"E7",x"E7",x"E7",
  -- 0xe6e0
  x"3F",x"3F",x"CF",x"CF",x"3F",x"3F",x"CF",x"CF",
  -- 0xe6e8
  x"E7",x"E7",x"E7",x"E7",x"E7",x"E7",x"E7",x"E7",
  -- 0xe6f0
  x"FF",x"FF",x"FC",x"C1",x"89",x"C9",x"C9",x"FF",
  -- 0xe6f8
  x"00",x"80",x"C0",x"E0",x"F0",x"F8",x"FC",x"FE",
  -- 0xe700
  x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xe708
  x"0F",x"0F",x"0F",x"0F",x"0F",x"0F",x"0F",x"0F",
  -- 0xe710
  x"FF",x"FF",x"FF",x"FF",x"00",x"00",x"00",x"00",
  -- 0xe718
  x"00",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xe720
  x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"00",
  -- 0xe728
  x"3F",x"3F",x"3F",x"3F",x"3F",x"3F",x"3F",x"3F",
  -- 0xe730
  x"33",x"33",x"CC",x"CC",x"33",x"33",x"CC",x"CC",
  -- 0xe738
  x"FC",x"FC",x"FC",x"FC",x"FC",x"FC",x"FC",x"FC",
  -- 0xe740
  x"FF",x"FF",x"FF",x"FF",x"33",x"33",x"CC",x"CC",
  -- 0xe748
  x"00",x"01",x"03",x"07",x"0F",x"1F",x"3F",x"7F",
  -- 0xe750
  x"FC",x"FC",x"FC",x"FC",x"FC",x"FC",x"FC",x"FC",
  -- 0xe758
  x"E7",x"E7",x"E7",x"E0",x"E0",x"E7",x"E7",x"E7",
  -- 0xe760
  x"FF",x"FF",x"FF",x"FF",x"F0",x"F0",x"F0",x"F0",
  -- 0xe768
  x"E7",x"E7",x"E7",x"E0",x"E0",x"FF",x"FF",x"FF",
  -- 0xe770
  x"FF",x"FF",x"FF",x"07",x"07",x"E7",x"E7",x"E7",
  -- 0xe778
  x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"00",x"00",
  -- 0xe780
  x"FF",x"FF",x"FF",x"E0",x"E0",x"E7",x"E7",x"E7",
  -- 0xe788
  x"E7",x"E7",x"E7",x"00",x"00",x"FF",x"FF",x"FF",
  -- 0xe790
  x"FF",x"FF",x"FF",x"00",x"00",x"E7",x"E7",x"E7",
  -- 0xe798
  x"E7",x"E7",x"E7",x"07",x"07",x"E7",x"E7",x"E7",
  -- 0xe7a0
  x"3F",x"3F",x"3F",x"3F",x"3F",x"3F",x"3F",x"3F",
  -- 0xe7a8
  x"1F",x"1F",x"1F",x"1F",x"1F",x"1F",x"1F",x"1F",
  -- 0xe7b0
  x"F8",x"F8",x"F8",x"F8",x"F8",x"F8",x"F8",x"F8",
  -- 0xe7b8
  x"00",x"00",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xe7c0
  x"00",x"00",x"00",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xe7c8
  x"FF",x"FF",x"FF",x"FF",x"FF",x"00",x"00",x"00",
  -- 0xe7d0
  x"FC",x"FC",x"FC",x"FC",x"FC",x"FC",x"00",x"00",
  -- 0xe7d8
  x"FF",x"FF",x"FF",x"FF",x"0F",x"0F",x"0F",x"0F",
  -- 0xe7e0
  x"F0",x"F0",x"F0",x"F0",x"FF",x"FF",x"FF",x"FF",
  -- 0xe7e8
  x"E7",x"E7",x"E7",x"07",x"07",x"FF",x"FF",x"FF",
  -- 0xe7f0
  x"0F",x"0F",x"0F",x"0F",x"FF",x"FF",x"FF",x"FF",
  -- 0xe7f8
  x"0F",x"0F",x"0F",x"0F",x"F0",x"F0",x"F0",x"F0",
  -- 0xe800
  x"3C",x"66",x"6E",x"6E",x"60",x"62",x"3C",x"00",
  -- 0xe808
  x"00",x"00",x"3C",x"06",x"3E",x"66",x"3E",x"00",
  -- 0xe810
  x"00",x"60",x"60",x"7C",x"66",x"66",x"7C",x"00",
  -- 0xe818
  x"00",x"00",x"3C",x"60",x"60",x"60",x"3C",x"00",
  -- 0xe820
  x"00",x"06",x"06",x"3E",x"66",x"66",x"3E",x"00",
  -- 0xe828
  x"00",x"00",x"3C",x"66",x"7E",x"60",x"3C",x"00",
  -- 0xe830
  x"00",x"0E",x"18",x"3E",x"18",x"18",x"18",x"00",
  -- 0xe838
  x"00",x"00",x"3E",x"66",x"66",x"3E",x"06",x"7C",
  -- 0xe840
  x"00",x"60",x"60",x"7C",x"66",x"66",x"66",x"00",
  -- 0xe848
  x"00",x"18",x"00",x"38",x"18",x"18",x"3C",x"00",
  -- 0xe850
  x"00",x"06",x"00",x"06",x"06",x"06",x"06",x"3C",
  -- 0xe858
  x"00",x"60",x"60",x"6C",x"78",x"6C",x"66",x"00",
  -- 0xe860
  x"00",x"38",x"18",x"18",x"18",x"18",x"3C",x"00",
  -- 0xe868
  x"00",x"00",x"66",x"7F",x"7F",x"6B",x"63",x"00",
  -- 0xe870
  x"00",x"00",x"7C",x"66",x"66",x"66",x"66",x"00",
  -- 0xe878
  x"00",x"00",x"3C",x"66",x"66",x"66",x"3C",x"00",
  -- 0xe880
  x"00",x"00",x"7C",x"66",x"66",x"7C",x"60",x"60",
  -- 0xe888
  x"00",x"00",x"3E",x"66",x"66",x"3E",x"06",x"06",
  -- 0xe890
  x"00",x"00",x"7C",x"66",x"60",x"60",x"60",x"00",
  -- 0xe898
  x"00",x"00",x"3E",x"60",x"3C",x"06",x"7C",x"00",
  -- 0xe8a0
  x"00",x"18",x"7E",x"18",x"18",x"18",x"0E",x"00",
  -- 0xe8a8
  x"00",x"00",x"66",x"66",x"66",x"66",x"3E",x"00",
  -- 0xe8b0
  x"00",x"00",x"66",x"66",x"66",x"3C",x"18",x"00",
  -- 0xe8b8
  x"00",x"00",x"63",x"6B",x"7F",x"3E",x"36",x"00",
  -- 0xe8c0
  x"00",x"00",x"66",x"3C",x"18",x"3C",x"66",x"00",
  -- 0xe8c8
  x"00",x"00",x"66",x"66",x"66",x"3E",x"0C",x"78",
  -- 0xe8d0
  x"00",x"00",x"7E",x"0C",x"18",x"30",x"7E",x"00",
  -- 0xe8d8
  x"3C",x"30",x"30",x"30",x"30",x"30",x"3C",x"00",
  -- 0xe8e0
  x"0C",x"12",x"30",x"7C",x"30",x"62",x"FC",x"00",
  -- 0xe8e8
  x"3C",x"0C",x"0C",x"0C",x"0C",x"0C",x"3C",x"00",
  -- 0xe8f0
  x"00",x"18",x"3C",x"7E",x"18",x"18",x"18",x"18",
  -- 0xe8f8
  x"00",x"10",x"30",x"7F",x"7F",x"30",x"10",x"00",
  -- 0xe900
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xe908
  x"18",x"18",x"18",x"18",x"00",x"00",x"18",x"00",
  -- 0xe910
  x"66",x"66",x"66",x"00",x"00",x"00",x"00",x"00",
  -- 0xe918
  x"66",x"66",x"FF",x"66",x"FF",x"66",x"66",x"00",
  -- 0xe920
  x"18",x"3E",x"60",x"3C",x"06",x"7C",x"18",x"00",
  -- 0xe928
  x"62",x"66",x"0C",x"18",x"30",x"66",x"46",x"00",
  -- 0xe930
  x"3C",x"66",x"3C",x"38",x"67",x"66",x"3F",x"00",
  -- 0xe938
  x"06",x"0C",x"18",x"00",x"00",x"00",x"00",x"00",
  -- 0xe940
  x"0C",x"18",x"30",x"30",x"30",x"18",x"0C",x"00",
  -- 0xe948
  x"30",x"18",x"0C",x"0C",x"0C",x"18",x"30",x"00",
  -- 0xe950
  x"00",x"66",x"3C",x"FF",x"3C",x"66",x"00",x"00",
  -- 0xe958
  x"00",x"18",x"18",x"7E",x"18",x"18",x"00",x"00",
  -- 0xe960
  x"00",x"00",x"00",x"00",x"00",x"18",x"18",x"30",
  -- 0xe968
  x"00",x"00",x"00",x"7E",x"00",x"00",x"00",x"00",
  -- 0xe970
  x"00",x"00",x"00",x"00",x"00",x"18",x"18",x"00",
  -- 0xe978
  x"00",x"03",x"06",x"0C",x"18",x"30",x"60",x"00",
  -- 0xe980
  x"3C",x"66",x"6E",x"76",x"66",x"66",x"3C",x"00",
  -- 0xe988
  x"18",x"18",x"38",x"18",x"18",x"18",x"7E",x"00",
  -- 0xe990
  x"3C",x"66",x"06",x"0C",x"30",x"60",x"7E",x"00",
  -- 0xe998
  x"3C",x"66",x"06",x"1C",x"06",x"66",x"3C",x"00",
  -- 0xe9a0
  x"06",x"0E",x"1E",x"66",x"7F",x"06",x"06",x"00",
  -- 0xe9a8
  x"7E",x"60",x"7C",x"06",x"06",x"66",x"3C",x"00",
  -- 0xe9b0
  x"3C",x"66",x"60",x"7C",x"66",x"66",x"3C",x"00",
  -- 0xe9b8
  x"7E",x"66",x"0C",x"18",x"18",x"18",x"18",x"00",
  -- 0xe9c0
  x"3C",x"66",x"66",x"3C",x"66",x"66",x"3C",x"00",
  -- 0xe9c8
  x"3C",x"66",x"66",x"3E",x"06",x"66",x"3C",x"00",
  -- 0xe9d0
  x"00",x"00",x"18",x"00",x"00",x"18",x"00",x"00",
  -- 0xe9d8
  x"00",x"00",x"18",x"00",x"00",x"18",x"18",x"30",
  -- 0xe9e0
  x"0E",x"18",x"30",x"60",x"30",x"18",x"0E",x"00",
  -- 0xe9e8
  x"00",x"00",x"7E",x"00",x"7E",x"00",x"00",x"00",
  -- 0xe9f0
  x"70",x"18",x"0C",x"06",x"0C",x"18",x"70",x"00",
  -- 0xe9f8
  x"3C",x"66",x"06",x"0C",x"18",x"00",x"18",x"00",
  -- 0xea00
  x"00",x"00",x"00",x"FF",x"FF",x"00",x"00",x"00",
  -- 0xea08
  x"18",x"3C",x"66",x"7E",x"66",x"66",x"66",x"00",
  -- 0xea10
  x"7C",x"66",x"66",x"7C",x"66",x"66",x"7C",x"00",
  -- 0xea18
  x"3C",x"66",x"60",x"60",x"60",x"66",x"3C",x"00",
  -- 0xea20
  x"78",x"6C",x"66",x"66",x"66",x"6C",x"78",x"00",
  -- 0xea28
  x"7E",x"60",x"60",x"78",x"60",x"60",x"7E",x"00",
  -- 0xea30
  x"7E",x"60",x"60",x"78",x"60",x"60",x"60",x"00",
  -- 0xea38
  x"3C",x"66",x"60",x"6E",x"66",x"66",x"3C",x"00",
  -- 0xea40
  x"66",x"66",x"66",x"7E",x"66",x"66",x"66",x"00",
  -- 0xea48
  x"3C",x"18",x"18",x"18",x"18",x"18",x"3C",x"00",
  -- 0xea50
  x"1E",x"0C",x"0C",x"0C",x"0C",x"6C",x"38",x"00",
  -- 0xea58
  x"66",x"6C",x"78",x"70",x"78",x"6C",x"66",x"00",
  -- 0xea60
  x"60",x"60",x"60",x"60",x"60",x"60",x"7E",x"00",
  -- 0xea68
  x"63",x"77",x"7F",x"6B",x"63",x"63",x"63",x"00",
  -- 0xea70
  x"66",x"76",x"7E",x"7E",x"6E",x"66",x"66",x"00",
  -- 0xea78
  x"3C",x"66",x"66",x"66",x"66",x"66",x"3C",x"00",
  -- 0xea80
  x"7C",x"66",x"66",x"7C",x"60",x"60",x"60",x"00",
  -- 0xea88
  x"3C",x"66",x"66",x"66",x"66",x"3C",x"0E",x"00",
  -- 0xea90
  x"7C",x"66",x"66",x"7C",x"78",x"6C",x"66",x"00",
  -- 0xea98
  x"3C",x"66",x"60",x"3C",x"06",x"66",x"3C",x"00",
  -- 0xeaa0
  x"7E",x"18",x"18",x"18",x"18",x"18",x"18",x"00",
  -- 0xeaa8
  x"66",x"66",x"66",x"66",x"66",x"66",x"3C",x"00",
  -- 0xeab0
  x"66",x"66",x"66",x"66",x"66",x"3C",x"18",x"00",
  -- 0xeab8
  x"63",x"63",x"63",x"6B",x"7F",x"77",x"63",x"00",
  -- 0xeac0
  x"66",x"66",x"3C",x"18",x"3C",x"66",x"66",x"00",
  -- 0xeac8
  x"66",x"66",x"66",x"3C",x"18",x"18",x"18",x"00",
  -- 0xead0
  x"7E",x"06",x"0C",x"18",x"30",x"60",x"7E",x"00",
  -- 0xead8
  x"18",x"18",x"18",x"FF",x"FF",x"18",x"18",x"18",
  -- 0xeae0
  x"C0",x"C0",x"30",x"30",x"C0",x"C0",x"30",x"30",
  -- 0xeae8
  x"18",x"18",x"18",x"18",x"18",x"18",x"18",x"18",
  -- 0xeaf0
  x"33",x"33",x"CC",x"CC",x"33",x"33",x"CC",x"CC",
  -- 0xeaf8
  x"33",x"99",x"CC",x"66",x"33",x"99",x"CC",x"66",
  -- 0xeb00
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xeb08
  x"F0",x"F0",x"F0",x"F0",x"F0",x"F0",x"F0",x"F0",
  -- 0xeb10
  x"00",x"00",x"00",x"00",x"FF",x"FF",x"FF",x"FF",
  -- 0xeb18
  x"FF",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xeb20
  x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"FF",
  -- 0xeb28
  x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",
  -- 0xeb30
  x"CC",x"CC",x"33",x"33",x"CC",x"CC",x"33",x"33",
  -- 0xeb38
  x"03",x"03",x"03",x"03",x"03",x"03",x"03",x"03",
  -- 0xeb40
  x"00",x"00",x"00",x"00",x"CC",x"CC",x"33",x"33",
  -- 0xeb48
  x"CC",x"99",x"33",x"66",x"CC",x"99",x"33",x"66",
  -- 0xeb50
  x"03",x"03",x"03",x"03",x"03",x"03",x"03",x"03",
  -- 0xeb58
  x"18",x"18",x"18",x"1F",x"1F",x"18",x"18",x"18",
  -- 0xeb60
  x"00",x"00",x"00",x"00",x"0F",x"0F",x"0F",x"0F",
  -- 0xeb68
  x"18",x"18",x"18",x"1F",x"1F",x"00",x"00",x"00",
  -- 0xeb70
  x"00",x"00",x"00",x"F8",x"F8",x"18",x"18",x"18",
  -- 0xeb78
  x"00",x"00",x"00",x"00",x"00",x"00",x"FF",x"FF",
  -- 0xeb80
  x"00",x"00",x"00",x"1F",x"1F",x"18",x"18",x"18",
  -- 0xeb88
  x"18",x"18",x"18",x"FF",x"FF",x"00",x"00",x"00",
  -- 0xeb90
  x"00",x"00",x"00",x"FF",x"FF",x"18",x"18",x"18",
  -- 0xeb98
  x"18",x"18",x"18",x"F8",x"F8",x"18",x"18",x"18",
  -- 0xeba0
  x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",x"C0",
  -- 0xeba8
  x"E0",x"E0",x"E0",x"E0",x"E0",x"E0",x"E0",x"E0",
  -- 0xebb0
  x"07",x"07",x"07",x"07",x"07",x"07",x"07",x"07",
  -- 0xebb8
  x"FF",x"FF",x"00",x"00",x"00",x"00",x"00",x"00",
  -- 0xebc0
  x"FF",x"FF",x"FF",x"00",x"00",x"00",x"00",x"00",
  -- 0xebc8
  x"00",x"00",x"00",x"00",x"00",x"FF",x"FF",x"FF",
  -- 0xebd0
  x"01",x"03",x"06",x"6C",x"78",x"70",x"60",x"00",
  -- 0xebd8
  x"00",x"00",x"00",x"00",x"F0",x"F0",x"F0",x"F0",
  -- 0xebe0
  x"0F",x"0F",x"0F",x"0F",x"00",x"00",x"00",x"00",
  -- 0xebe8
  x"18",x"18",x"18",x"F8",x"F8",x"00",x"00",x"00",
  -- 0xebf0
  x"F0",x"F0",x"F0",x"F0",x"00",x"00",x"00",x"00",
  -- 0xebf8
  x"F0",x"F0",x"F0",x"F0",x"0F",x"0F",x"0F",x"0F",
  -- 0xec00
  x"C3",x"99",x"91",x"91",x"9F",x"99",x"C3",x"FF",
  -- 0xec08
  x"FF",x"FF",x"C3",x"F9",x"C1",x"99",x"C1",x"FF",
  -- 0xec10
  x"FF",x"9F",x"9F",x"83",x"99",x"99",x"83",x"FF",
  -- 0xec18
  x"FF",x"FF",x"C3",x"9F",x"9F",x"9F",x"C3",x"FF",
  -- 0xec20
  x"FF",x"F9",x"F9",x"C1",x"99",x"99",x"C1",x"FF",
  -- 0xec28
  x"FF",x"FF",x"C3",x"99",x"81",x"9F",x"C3",x"FF",
  -- 0xec30
  x"FF",x"F1",x"E7",x"C1",x"E7",x"E7",x"E7",x"FF",
  -- 0xec38
  x"FF",x"FF",x"C1",x"99",x"99",x"C1",x"F9",x"83",
  -- 0xec40
  x"FF",x"9F",x"9F",x"83",x"99",x"99",x"99",x"FF",
  -- 0xec48
  x"FF",x"E7",x"FF",x"C7",x"E7",x"E7",x"C3",x"FF",
  -- 0xec50
  x"FF",x"F9",x"FF",x"F9",x"F9",x"F9",x"F9",x"C3",
  -- 0xec58
  x"FF",x"9F",x"9F",x"93",x"87",x"93",x"99",x"FF",
  -- 0xec60
  x"FF",x"C7",x"E7",x"E7",x"E7",x"E7",x"C3",x"FF",
  -- 0xec68
  x"FF",x"FF",x"99",x"80",x"80",x"94",x"9C",x"FF",
  -- 0xec70
  x"FF",x"FF",x"83",x"99",x"99",x"99",x"99",x"FF",
  -- 0xec78
  x"FF",x"FF",x"C3",x"99",x"99",x"99",x"C3",x"FF",
  -- 0xec80
  x"FF",x"FF",x"83",x"99",x"99",x"83",x"9F",x"9F",
  -- 0xec88
  x"FF",x"FF",x"C1",x"99",x"99",x"C1",x"F9",x"F9",
  -- 0xec90
  x"FF",x"FF",x"83",x"99",x"9F",x"9F",x"9F",x"FF",
  -- 0xec98
  x"FF",x"FF",x"C1",x"9F",x"C3",x"F9",x"83",x"FF",
  -- 0xeca0
  x"FF",x"E7",x"81",x"E7",x"E7",x"E7",x"F1",x"FF",
  -- 0xeca8
  x"FF",x"FF",x"99",x"99",x"99",x"99",x"C1",x"FF",
  -- 0xecb0
  x"FF",x"FF",x"99",x"99",x"99",x"C3",x"E7",x"FF",
  -- 0xecb8
  x"FF",x"FF",x"9C",x"94",x"80",x"C1",x"C9",x"FF",
  -- 0xecc0
  x"FF",x"FF",x"99",x"C3",x"E7",x"C3",x"99",x"FF",
  -- 0xecc8
  x"FF",x"FF",x"99",x"99",x"99",x"C1",x"F3",x"87",
  -- 0xecd0
  x"FF",x"FF",x"81",x"F3",x"E7",x"CF",x"81",x"FF",
  -- 0xecd8
  x"C3",x"CF",x"CF",x"CF",x"CF",x"CF",x"C3",x"FF",
  -- 0xece0
  x"F3",x"ED",x"CF",x"83",x"CF",x"9D",x"03",x"FF",
  -- 0xece8
  x"C3",x"F3",x"F3",x"F3",x"F3",x"F3",x"C3",x"FF",
  -- 0xecf0
  x"FF",x"E7",x"C3",x"81",x"E7",x"E7",x"E7",x"E7",
  -- 0xecf8
  x"FF",x"EF",x"CF",x"80",x"80",x"CF",x"EF",x"FF",
  -- 0xed00
  x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xed08
  x"E7",x"E7",x"E7",x"E7",x"FF",x"FF",x"E7",x"FF",
  -- 0xed10
  x"99",x"99",x"99",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xed18
  x"99",x"99",x"00",x"99",x"00",x"99",x"99",x"FF",
  -- 0xed20
  x"E7",x"C1",x"9F",x"C3",x"F9",x"83",x"E7",x"FF",
  -- 0xed28
  x"9D",x"99",x"F3",x"E7",x"CF",x"99",x"B9",x"FF",
  -- 0xed30
  x"C3",x"99",x"C3",x"C7",x"98",x"99",x"C0",x"FF",
  -- 0xed38
  x"F9",x"F3",x"E7",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xed40
  x"F3",x"E7",x"CF",x"CF",x"CF",x"E7",x"F3",x"FF",
  -- 0xed48
  x"CF",x"E7",x"F3",x"F3",x"F3",x"E7",x"CF",x"FF",
  -- 0xed50
  x"FF",x"99",x"C3",x"00",x"C3",x"99",x"FF",x"FF",
  -- 0xed58
  x"FF",x"E7",x"E7",x"81",x"E7",x"E7",x"FF",x"FF",
  -- 0xed60
  x"FF",x"FF",x"FF",x"FF",x"FF",x"E7",x"E7",x"CF",
  -- 0xed68
  x"FF",x"FF",x"FF",x"81",x"FF",x"FF",x"FF",x"FF",
  -- 0xed70
  x"FF",x"FF",x"FF",x"FF",x"FF",x"E7",x"E7",x"FF",
  -- 0xed78
  x"FF",x"FC",x"F9",x"F3",x"E7",x"CF",x"9F",x"FF",
  -- 0xed80
  x"C3",x"99",x"91",x"89",x"99",x"99",x"C3",x"FF",
  -- 0xed88
  x"E7",x"E7",x"C7",x"E7",x"E7",x"E7",x"81",x"FF",
  -- 0xed90
  x"C3",x"99",x"F9",x"F3",x"CF",x"9F",x"81",x"FF",
  -- 0xed98
  x"C3",x"99",x"F9",x"E3",x"F9",x"99",x"C3",x"FF",
  -- 0xeda0
  x"F9",x"F1",x"E1",x"99",x"80",x"F9",x"F9",x"FF",
  -- 0xeda8
  x"81",x"9F",x"83",x"F9",x"F9",x"99",x"C3",x"FF",
  -- 0xedb0
  x"C3",x"99",x"9F",x"83",x"99",x"99",x"C3",x"FF",
  -- 0xedb8
  x"81",x"99",x"F3",x"E7",x"E7",x"E7",x"E7",x"FF",
  -- 0xedc0
  x"C3",x"99",x"99",x"C3",x"99",x"99",x"C3",x"FF",
  -- 0xedc8
  x"C3",x"99",x"99",x"C1",x"F9",x"99",x"C3",x"FF",
  -- 0xedd0
  x"FF",x"FF",x"E7",x"FF",x"FF",x"E7",x"FF",x"FF",
  -- 0xedd8
  x"FF",x"FF",x"E7",x"FF",x"FF",x"E7",x"E7",x"CF",
  -- 0xede0
  x"F1",x"E7",x"CF",x"9F",x"CF",x"E7",x"F1",x"FF",
  -- 0xede8
  x"FF",x"FF",x"81",x"FF",x"81",x"FF",x"FF",x"FF",
  -- 0xedf0
  x"8F",x"E7",x"F3",x"F9",x"F3",x"E7",x"8F",x"FF",
  -- 0xedf8
  x"C3",x"99",x"F9",x"F3",x"E7",x"FF",x"E7",x"FF",
  -- 0xee00
  x"FF",x"FF",x"FF",x"00",x"00",x"FF",x"FF",x"FF",
  -- 0xee08
  x"E7",x"C3",x"99",x"81",x"99",x"99",x"99",x"FF",
  -- 0xee10
  x"83",x"99",x"99",x"83",x"99",x"99",x"83",x"FF",
  -- 0xee18
  x"C3",x"99",x"9F",x"9F",x"9F",x"99",x"C3",x"FF",
  -- 0xee20
  x"87",x"93",x"99",x"99",x"99",x"93",x"87",x"FF",
  -- 0xee28
  x"81",x"9F",x"9F",x"87",x"9F",x"9F",x"81",x"FF",
  -- 0xee30
  x"81",x"9F",x"9F",x"87",x"9F",x"9F",x"9F",x"FF",
  -- 0xee38
  x"C3",x"99",x"9F",x"91",x"99",x"99",x"C3",x"FF",
  -- 0xee40
  x"99",x"99",x"99",x"81",x"99",x"99",x"99",x"FF",
  -- 0xee48
  x"C3",x"E7",x"E7",x"E7",x"E7",x"E7",x"C3",x"FF",
  -- 0xee50
  x"E1",x"F3",x"F3",x"F3",x"F3",x"93",x"C7",x"FF",
  -- 0xee58
  x"99",x"93",x"87",x"8F",x"87",x"93",x"99",x"FF",
  -- 0xee60
  x"9F",x"9F",x"9F",x"9F",x"9F",x"9F",x"81",x"FF",
  -- 0xee68
  x"9C",x"88",x"80",x"94",x"9C",x"9C",x"9C",x"FF",
  -- 0xee70
  x"99",x"89",x"81",x"81",x"91",x"99",x"99",x"FF",
  -- 0xee78
  x"C3",x"99",x"99",x"99",x"99",x"99",x"C3",x"FF",
  -- 0xee80
  x"83",x"99",x"99",x"83",x"9F",x"9F",x"9F",x"FF",
  -- 0xee88
  x"C3",x"99",x"99",x"99",x"99",x"C3",x"F1",x"FF",
  -- 0xee90
  x"83",x"99",x"99",x"83",x"87",x"93",x"99",x"FF",
  -- 0xee98
  x"C3",x"99",x"9F",x"C3",x"F9",x"99",x"C3",x"FF",
  -- 0xeea0
  x"81",x"E7",x"E7",x"E7",x"E7",x"E7",x"E7",x"FF",
  -- 0xeea8
  x"99",x"99",x"99",x"99",x"99",x"99",x"C3",x"FF",
  -- 0xeeb0
  x"99",x"99",x"99",x"99",x"99",x"C3",x"E7",x"FF",
  -- 0xeeb8
  x"9C",x"9C",x"9C",x"94",x"80",x"88",x"9C",x"FF",
  -- 0xeec0
  x"99",x"99",x"C3",x"E7",x"C3",x"99",x"99",x"FF",
  -- 0xeec8
  x"99",x"99",x"99",x"C3",x"E7",x"E7",x"E7",x"FF",
  -- 0xeed0
  x"81",x"F9",x"F3",x"E7",x"CF",x"9F",x"81",x"FF",
  -- 0xeed8
  x"E7",x"E7",x"E7",x"00",x"00",x"E7",x"E7",x"E7",
  -- 0xeee0
  x"3F",x"3F",x"CF",x"CF",x"3F",x"3F",x"CF",x"CF",
  -- 0xeee8
  x"E7",x"E7",x"E7",x"E7",x"E7",x"E7",x"E7",x"E7",
  -- 0xeef0
  x"CC",x"CC",x"33",x"33",x"CC",x"CC",x"33",x"33",
  -- 0xeef8
  x"CC",x"66",x"33",x"99",x"CC",x"66",x"33",x"99",
  -- 0xef00
  x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xef08
  x"0F",x"0F",x"0F",x"0F",x"0F",x"0F",x"0F",x"0F",
  -- 0xef10
  x"FF",x"FF",x"FF",x"FF",x"00",x"00",x"00",x"00",
  -- 0xef18
  x"00",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xef20
  x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"00",
  -- 0xef28
  x"3F",x"3F",x"3F",x"3F",x"3F",x"3F",x"3F",x"3F",
  -- 0xef30
  x"33",x"33",x"CC",x"CC",x"33",x"33",x"CC",x"CC",
  -- 0xef38
  x"FC",x"FC",x"FC",x"FC",x"FC",x"FC",x"FC",x"FC",
  -- 0xef40
  x"FF",x"FF",x"FF",x"FF",x"33",x"33",x"CC",x"CC",
  -- 0xef48
  x"33",x"66",x"CC",x"99",x"33",x"66",x"CC",x"99",
  -- 0xef50
  x"FC",x"FC",x"FC",x"FC",x"FC",x"FC",x"FC",x"FC",
  -- 0xef58
  x"E7",x"E7",x"E7",x"E0",x"E0",x"E7",x"E7",x"E7",
  -- 0xef60
  x"FF",x"FF",x"FF",x"FF",x"F0",x"F0",x"F0",x"F0",
  -- 0xef68
  x"E7",x"E7",x"E7",x"E0",x"E0",x"FF",x"FF",x"FF",
  -- 0xef70
  x"FF",x"FF",x"FF",x"07",x"07",x"E7",x"E7",x"E7",
  -- 0xef78
  x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"00",x"00",
  -- 0xef80
  x"FF",x"FF",x"FF",x"E0",x"E0",x"E7",x"E7",x"E7",
  -- 0xef88
  x"E7",x"E7",x"E7",x"00",x"00",x"FF",x"FF",x"FF",
  -- 0xef90
  x"FF",x"FF",x"FF",x"00",x"00",x"E7",x"E7",x"E7",
  -- 0xef98
  x"E7",x"E7",x"E7",x"07",x"07",x"E7",x"E7",x"E7",
  -- 0xefa0
  x"3F",x"3F",x"3F",x"3F",x"3F",x"3F",x"3F",x"3F",
  -- 0xefa8
  x"1F",x"1F",x"1F",x"1F",x"1F",x"1F",x"1F",x"1F",
  -- 0xefb0
  x"F8",x"F8",x"F8",x"F8",x"F8",x"F8",x"F8",x"F8",
  -- 0xefb8
  x"00",x"00",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xefc0
  x"00",x"00",x"00",x"FF",x"FF",x"FF",x"FF",x"FF",
  -- 0xefc8
  x"FF",x"FF",x"FF",x"FF",x"FF",x"00",x"00",x"00",
  -- 0xefd0
  x"FE",x"FC",x"F9",x"93",x"87",x"8F",x"9F",x"FF",
  -- 0xefd8
  x"FF",x"FF",x"FF",x"FF",x"0F",x"0F",x"0F",x"0F",
  -- 0xefe0
  x"F0",x"F0",x"F0",x"F0",x"FF",x"FF",x"FF",x"FF",
  -- 0xefe8
  x"E7",x"E7",x"E7",x"07",x"07",x"FF",x"FF",x"FF",
  -- 0xeff0
  x"0F",x"0F",x"0F",x"0F",x"FF",x"FF",x"FF",x"FF",
  -- 0xeff8
  x"0F",x"0F",x"0F",x"0F",x"F0",x"F0",x"F0",x"F0");

begin

--process for read and write operation.
PROCESS(Clk)
BEGIN
  --report "viciv reading charrom address $"
  --  & to_hstring(address)
  --  & " = " & integer'image(to_integer(address))
  --  & " -> $" & to_hstring(ram(to_integer(address)))
  --  severity note;
  data_o <= ram(address);          

  if(rising_edge(writeClk)) then 
    if writecs='1' then
      if(we='1') then
            ram(to_integer(writeaddress)) <= data_i;
      end if;
    end if;
  end if;
END PROCESS;

end Behavioral;
