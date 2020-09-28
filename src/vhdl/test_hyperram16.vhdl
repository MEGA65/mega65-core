library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;
use work.cputypes.all;

entity test_hyperram16 is
end entity;

architecture foo of test_hyperram16 is

  signal cpuclock : std_logic := '1';
  signal pixelclock : std_logic := '1';
  signal clock163 : std_logic := '1';
  signal clock325 : std_logic := '1';

  signal expansionram_current_cache_line_next_toggle : std_logic := '0';
  signal expansionram_read : std_logic;
  signal expansionram_write : std_logic := '0';
  signal expansionram_rdata : unsigned(15 downto 0);
  signal expansionram_wdata : unsigned(15 downto 0) := x"4242";
  signal expansionram_address : unsigned(26 downto 0) := "000000100100011010001010111";
  signal expansionram_data_ready_strobe : std_logic;
  signal expansionram_busy : std_logic;
  signal current_cache_line : cache_row_t := (others => (others => '0'));
  signal current_cache_line_address : unsigned(26 downto 3) := (others => '0');
  signal current_cache_line_valid : std_logic := '0';

  signal cycles : integer := 0;  
  
  signal slow_prefetched_address : unsigned(26 downto 0);
  signal slow_prefetched_data : unsigned(7 downto 0);
  signal slow_prefetched_request_toggle : std_logic := '0';
  
  signal hr_d : unsigned(7 downto 0) := (others => '0');
  signal hr_rwds : std_logic := '0';
  signal hr_reset : std_logic := '1';
  signal hr_clk_n : std_logic := '0';
  signal hr_clk_p : std_logic := '0';
  signal hr_cs0 : std_logic := '0';

  signal hr2_d : unsigned(7 downto 0) := (others => '0');
  signal hr2_rwds : std_logic := '0';
  signal hr2_reset : std_logic := '1';
  signal hr2_clk_n : std_logic := '0';
  signal hr2_clk_p : std_logic := '0';
  signal hr2_cs0 : std_logic := '0';
  
  type mem_transaction_t is record
    address : unsigned(27 downto 0);
    write_p : std_logic;
    value : unsigned(15 downto 0);     -- either to write, or expected to read
  end record mem_transaction_t;

  type mem_job_list_t is array(0 to 4095) of mem_transaction_t;

  signal start_time : integer := 0;
  signal current_time : integer := 0;
  signal dispatch_time : integer := 0;
  
  signal mem_jobs : mem_job_list_t := (

    (address => x"a000000", write_p => '0', value => x"0C83"),
    (address => x"a000002", write_p => '0', value => x"0C83"),
    (address => x"a000004", write_p => '0', value => x"0C83"),
    (address => x"a000006", write_p => '0', value => x"0C83"),

    
    -- Simple write and then read immediately
    (address => x"8801000", write_p => '1', value => x"1984"),
    (address => x"8801000", write_p => '0', value => x"1984"),

    -- Try to reproduce the read-strobe bug
    (address => x"8801000", write_p => '1', value => x"1984"),
    (address => x"8801000", write_p => '1', value => x"1984"),

    (address => x"8802000", write_p => '1', value => x"1241"),
    (address => x"8802002", write_p => '1', value => x"2342"),
    (address => x"8802004", write_p => '1', value => x"3433"),
    (address => x"8802006", write_p => '1', value => x"4534"),
    (address => x"8802008", write_p => '1', value => x"5625"),
    (address => x"8802010", write_p => '1', value => x"6726"),
    (address => x"8802012", write_p => '1', value => x"7817"),
    (address => x"8802014", write_p => '1', value => x"8918"),
    
    (address => x"8802000", write_p => '0', value => x"1241"),
    (address => x"8802002", write_p => '0', value => x"2342"),
    (address => x"8802004", write_p => '0', value => x"3433"),
    (address => x"8802006", write_p => '0', value => x"4534"),
    (address => x"8802008", write_p => '0', value => x"5625"),
    (address => x"8802010", write_p => '0', value => x"6726"),
    (address => x"8802012", write_p => '0', value => x"7817"),
    (address => x"8802014", write_p => '0', value => x"8918"),
    
    -- Issue #280, let's write then read a few pages of data, and see if we get
    -- the wrong results at the start of each page.
    -- sy2002 wrote at word $333333 onwards = real address $8666666 for us
    (address => x"8000000", write_p => '1', value => x"1234"),
    (address => x"8000000", write_p => '1', value => x"5678"),
    (address => x"8000000", write_p => '1', value => x"9abc"),
    (address => x"867C000", write_p => '1', value => x"0000"),
    (address => x"867C002", write_p => '1', value => x"0001"),
    (address => x"867C004", write_p => '1', value => x"0002"),
    (address => x"867C006", write_p => '1', value => x"0003"),
    (address => x"867C008", write_p => '1', value => x"0004"),
    (address => x"867C00A", write_p => '1', value => x"0005"),
    (address => x"867C00C", write_p => '1', value => x"0006"),
    (address => x"867C00E", write_p => '1', value => x"0007"),
    (address => x"867C010", write_p => '1', value => x"0008"),
    (address => x"867C012", write_p => '1', value => x"0009"),
    (address => x"867C014", write_p => '1', value => x"000a"),
    (address => x"867C016", write_p => '1', value => x"000b"),
    (address => x"867C018", write_p => '1', value => x"000c"),
    (address => x"867C01A", write_p => '1', value => x"000d"),
    (address => x"867C01C", write_p => '1', value => x"000e"),
    (address => x"867C01E", write_p => '1', value => x"000f"),
    (address => x"867C020", write_p => '1', value => x"0010"),
    (address => x"867C022", write_p => '1', value => x"0011"),
    (address => x"867C024", write_p => '1', value => x"0012"),
    (address => x"867C026", write_p => '1', value => x"0013"),
    (address => x"867C028", write_p => '1', value => x"0014"),
    (address => x"867C02A", write_p => '1', value => x"0015"),
    (address => x"867C02C", write_p => '1', value => x"0016"),
    (address => x"867C02E", write_p => '1', value => x"0017"),
    (address => x"867C030", write_p => '1', value => x"0018"),
    (address => x"867C032", write_p => '1', value => x"0019"),
    (address => x"867C034", write_p => '1', value => x"001a"),
    (address => x"867C036", write_p => '1', value => x"001b"),
    (address => x"867C038", write_p => '1', value => x"001c"),
    (address => x"867C03A", write_p => '1', value => x"001d"),
    (address => x"867C03C", write_p => '1', value => x"001e"),
    (address => x"867C03E", write_p => '1', value => x"001f"),
    (address => x"867C040", write_p => '1', value => x"0020"),
    (address => x"867C042", write_p => '1', value => x"0021"),
    (address => x"867C044", write_p => '1', value => x"0022"),
    (address => x"867C046", write_p => '1', value => x"0023"),
    (address => x"867C048", write_p => '1', value => x"0024"),
    (address => x"867C04A", write_p => '1', value => x"0025"),
    (address => x"867C04C", write_p => '1', value => x"0026"),
    (address => x"867C04E", write_p => '1', value => x"0027"),
    (address => x"867C050", write_p => '1', value => x"0028"),
    (address => x"867C052", write_p => '1', value => x"0029"),
    (address => x"867C054", write_p => '1', value => x"002a"),
    (address => x"867C056", write_p => '1', value => x"002b"),
    (address => x"867C058", write_p => '1', value => x"002c"),
    (address => x"867C05A", write_p => '1', value => x"002d"),
    (address => x"867C05C", write_p => '1', value => x"002e"),
    (address => x"867C05E", write_p => '1', value => x"002f"),
    (address => x"867C060", write_p => '1', value => x"0030"),
    (address => x"867C062", write_p => '1', value => x"0031"),
    (address => x"867C064", write_p => '1', value => x"0032"),
    (address => x"867C066", write_p => '1', value => x"0033"),
    (address => x"867C068", write_p => '1', value => x"0034"),
    (address => x"867C06A", write_p => '1', value => x"0035"),
    (address => x"867C06C", write_p => '1', value => x"0036"),
    (address => x"867C06E", write_p => '1', value => x"0037"),
    (address => x"867C070", write_p => '1', value => x"0038"),
    (address => x"867C072", write_p => '1', value => x"0039"),
    (address => x"867C074", write_p => '1', value => x"003a"),
    (address => x"867C076", write_p => '1', value => x"003b"),
    (address => x"867C078", write_p => '1', value => x"003c"),
    (address => x"867C07A", write_p => '1', value => x"003d"),
    (address => x"867C07C", write_p => '1', value => x"003e"),
    (address => x"867C07E", write_p => '1', value => x"003f"),
    (address => x"867C080", write_p => '1', value => x"0040"),
    (address => x"867C082", write_p => '1', value => x"0041"),
    (address => x"867C084", write_p => '1', value => x"0042"),
    (address => x"867C086", write_p => '1', value => x"0043"),
    (address => x"867C088", write_p => '1', value => x"0044"),
    (address => x"867C08A", write_p => '1', value => x"0045"),
    (address => x"867C08C", write_p => '1', value => x"0046"),
    (address => x"867C08E", write_p => '1', value => x"0047"),
    (address => x"867C090", write_p => '1', value => x"0048"),
    (address => x"867C092", write_p => '1', value => x"0049"),
    (address => x"867C094", write_p => '1', value => x"004a"),
    (address => x"867C096", write_p => '1', value => x"004b"),
    (address => x"867C098", write_p => '1', value => x"004c"),
    (address => x"867C09A", write_p => '1', value => x"004d"),
    (address => x"867C09C", write_p => '1', value => x"004e"),
    (address => x"867C09E", write_p => '1', value => x"004f"),
    (address => x"867C0A0", write_p => '1', value => x"0050"),
    (address => x"867C0A2", write_p => '1', value => x"0051"),
    (address => x"867C0A4", write_p => '1', value => x"0052"),
    (address => x"867C0A6", write_p => '1', value => x"0053"),
    (address => x"867C0A8", write_p => '1', value => x"0054"),
    (address => x"867C0AA", write_p => '1', value => x"0055"),
    (address => x"867C0AC", write_p => '1', value => x"0056"),
    (address => x"867C0AE", write_p => '1', value => x"0057"),
    (address => x"867C0B0", write_p => '1', value => x"0058"),
    (address => x"867C0B2", write_p => '1', value => x"0059"),
    (address => x"867C0B4", write_p => '1', value => x"005a"),
    (address => x"867C0B6", write_p => '1', value => x"005b"),
    (address => x"867C0B8", write_p => '1', value => x"005c"),
    (address => x"867C0BA", write_p => '1', value => x"005d"),
    (address => x"867C0BC", write_p => '1', value => x"005e"),
    (address => x"867C0BE", write_p => '1', value => x"005f"),
    (address => x"867C0C0", write_p => '1', value => x"0060"),
    (address => x"867C0C2", write_p => '1', value => x"0061"),
    (address => x"867C0C4", write_p => '1', value => x"0062"),
    (address => x"867C0C6", write_p => '1', value => x"0063"),
    (address => x"867C0C8", write_p => '1', value => x"0064"),
    (address => x"867C0CA", write_p => '1', value => x"0065"),
    (address => x"867C0CC", write_p => '1', value => x"0066"),
    (address => x"867C0CE", write_p => '1', value => x"0067"),
    (address => x"867C0D0", write_p => '1', value => x"0068"),
    (address => x"867C0D2", write_p => '1', value => x"0069"),
    (address => x"867C0D4", write_p => '1', value => x"006a"),
    (address => x"867C0D6", write_p => '1', value => x"006b"),
    (address => x"867C0D8", write_p => '1', value => x"006c"),
    (address => x"867C0DA", write_p => '1', value => x"006d"),
    (address => x"867C0DC", write_p => '1', value => x"006e"),
    (address => x"867C0DE", write_p => '1', value => x"006f"),
    (address => x"867C0E0", write_p => '1', value => x"0070"),
    (address => x"867C0E2", write_p => '1', value => x"0071"),
    (address => x"867C0E4", write_p => '1', value => x"0072"),
    (address => x"867C0E6", write_p => '1', value => x"0073"),
    (address => x"867C0E8", write_p => '1', value => x"0074"),
    (address => x"867C0EA", write_p => '1', value => x"0075"),
    (address => x"867C0EC", write_p => '1', value => x"0076"),
    (address => x"867C0EE", write_p => '1', value => x"0077"),
    (address => x"867C0F0", write_p => '1', value => x"0078"),
    (address => x"867C0F2", write_p => '1', value => x"0079"),
    (address => x"867C0F4", write_p => '1', value => x"007a"),
    (address => x"867C0F6", write_p => '1', value => x"007b"),
    (address => x"867C0F8", write_p => '1', value => x"007c"),
    (address => x"867C0FA", write_p => '1', value => x"007d"),
    (address => x"867C0FC", write_p => '1', value => x"007e"),
    (address => x"867C0FE", write_p => '1', value => x"007f"),
    (address => x"867C100", write_p => '1', value => x"0080"),
    (address => x"867C102", write_p => '1', value => x"0081"),
    (address => x"867C104", write_p => '1', value => x"0082"),
    (address => x"867C106", write_p => '1', value => x"0083"),
    (address => x"867C108", write_p => '1', value => x"0084"),
    (address => x"867C10A", write_p => '1', value => x"0085"),
    (address => x"867C10C", write_p => '1', value => x"0086"),
    (address => x"867C10E", write_p => '1', value => x"0087"),
    (address => x"867C110", write_p => '1', value => x"0088"),
    (address => x"867C112", write_p => '1', value => x"0089"),
    (address => x"867C114", write_p => '1', value => x"008a"),
    (address => x"867C116", write_p => '1', value => x"008b"),
    (address => x"867C118", write_p => '1', value => x"008c"),
    (address => x"867C11A", write_p => '1', value => x"008d"),
    (address => x"867C11C", write_p => '1', value => x"008e"),
    (address => x"867C11E", write_p => '1', value => x"008f"),
    (address => x"867C120", write_p => '1', value => x"0090"),
    (address => x"867C122", write_p => '1', value => x"0091"),
    (address => x"867C124", write_p => '1', value => x"0092"),
    (address => x"867C126", write_p => '1', value => x"0093"),
    (address => x"867C128", write_p => '1', value => x"0094"),
    (address => x"867C12A", write_p => '1', value => x"0095"),
    (address => x"867C12C", write_p => '1', value => x"0096"),
    (address => x"867C12E", write_p => '1', value => x"0097"),
    (address => x"867C130", write_p => '1', value => x"0098"),
    (address => x"867C132", write_p => '1', value => x"0099"),
    (address => x"867C134", write_p => '1', value => x"009a"),
    (address => x"867C136", write_p => '1', value => x"009b"),
    (address => x"867C138", write_p => '1', value => x"009c"),
    (address => x"867C13A", write_p => '1', value => x"009d"),
    (address => x"867C13C", write_p => '1', value => x"009e"),
    (address => x"867C13E", write_p => '1', value => x"009f"),
    (address => x"867C140", write_p => '1', value => x"00a0"),
    (address => x"867C142", write_p => '1', value => x"00a1"),
    (address => x"867C144", write_p => '1', value => x"00a2"),
    (address => x"867C146", write_p => '1', value => x"00a3"),
    (address => x"867C148", write_p => '1', value => x"00a4"),
    (address => x"867C14A", write_p => '1', value => x"00a5"),
    (address => x"867C14C", write_p => '1', value => x"00a6"),
    (address => x"867C14E", write_p => '1', value => x"00a7"),
    (address => x"867C150", write_p => '1', value => x"00a8"),
    (address => x"867C152", write_p => '1', value => x"00a9"),
    (address => x"867C154", write_p => '1', value => x"00aa"),
    (address => x"867C156", write_p => '1', value => x"00ab"),
    (address => x"867C158", write_p => '1', value => x"00ac"),
    (address => x"867C15A", write_p => '1', value => x"00ad"),
    (address => x"867C15C", write_p => '1', value => x"00ae"),
    (address => x"867C15E", write_p => '1', value => x"00af"),
    (address => x"867C160", write_p => '1', value => x"00b0"),
    (address => x"867C162", write_p => '1', value => x"00b1"),
    (address => x"867C164", write_p => '1', value => x"00b2"),
    (address => x"867C166", write_p => '1', value => x"00b3"),
    (address => x"867C168", write_p => '1', value => x"00b4"),
    (address => x"867C16A", write_p => '1', value => x"00b5"),
    (address => x"867C16C", write_p => '1', value => x"00b6"),
    (address => x"867C16E", write_p => '1', value => x"00b7"),
    (address => x"867C170", write_p => '1', value => x"00b8"),
    (address => x"867C172", write_p => '1', value => x"00b9"),
    (address => x"867C174", write_p => '1', value => x"00ba"),
    (address => x"867C176", write_p => '1', value => x"00bb"),
    (address => x"867C178", write_p => '1', value => x"00bc"),
    (address => x"867C17A", write_p => '1', value => x"00bd"),
    (address => x"867C17C", write_p => '1', value => x"00be"),
    (address => x"867C17E", write_p => '1', value => x"00bf"),
    (address => x"867C180", write_p => '1', value => x"00c0"),
    (address => x"867C182", write_p => '1', value => x"00c1"),
    (address => x"867C184", write_p => '1', value => x"00c2"),
    (address => x"867C186", write_p => '1', value => x"00c3"),
    (address => x"867C188", write_p => '1', value => x"00c4"),
    (address => x"867C18A", write_p => '1', value => x"00c5"),
    (address => x"867C18C", write_p => '1', value => x"00c6"),
    (address => x"867C18E", write_p => '1', value => x"00c7"),
    (address => x"867C190", write_p => '1', value => x"00c8"),
    (address => x"867C192", write_p => '1', value => x"00c9"),
    (address => x"867C194", write_p => '1', value => x"00ca"),
    (address => x"867C196", write_p => '1', value => x"00cb"),
    (address => x"867C198", write_p => '1', value => x"00cc"),
    (address => x"867C19A", write_p => '1', value => x"00cd"),
    (address => x"867C19C", write_p => '1', value => x"00ce"),
    (address => x"867C19E", write_p => '1', value => x"00cf"),
    (address => x"867C1A0", write_p => '1', value => x"00d0"),
    (address => x"867C1A2", write_p => '1', value => x"00d1"),
    (address => x"867C1A4", write_p => '1', value => x"00d2"),
    (address => x"867C1A6", write_p => '1', value => x"00d3"),
    (address => x"867C1A8", write_p => '1', value => x"00d4"),
    (address => x"867C1AA", write_p => '1', value => x"00d5"),
    (address => x"867C1AC", write_p => '1', value => x"00d6"),
    (address => x"867C1AE", write_p => '1', value => x"00d7"),
    (address => x"867C1B0", write_p => '1', value => x"00d8"),
    (address => x"867C1B2", write_p => '1', value => x"00d9"),
    (address => x"867C1B4", write_p => '1', value => x"00da"),
    (address => x"867C1B6", write_p => '1', value => x"00db"),
    (address => x"867C1B8", write_p => '1', value => x"00dc"),
    (address => x"867C1BA", write_p => '1', value => x"00dd"),
    (address => x"867C1BC", write_p => '1', value => x"00de"),
    (address => x"867C1BE", write_p => '1', value => x"00df"),
    (address => x"867C1C0", write_p => '1', value => x"00e0"),
    (address => x"867C1C2", write_p => '1', value => x"00e1"),
    (address => x"867C1C4", write_p => '1', value => x"00e2"),
    (address => x"867C1C6", write_p => '1', value => x"00e3"),
    (address => x"867C1C8", write_p => '1', value => x"00e4"),
    (address => x"867C1CA", write_p => '1', value => x"00e5"),
    (address => x"867C1CC", write_p => '1', value => x"00e6"),
    (address => x"867C1CE", write_p => '1', value => x"00e7"),
    (address => x"867C1D0", write_p => '1', value => x"00e8"),
    (address => x"867C1D2", write_p => '1', value => x"00e9"),
    (address => x"867C1D4", write_p => '1', value => x"00ea"),
    (address => x"867C1D6", write_p => '1', value => x"00eb"),
    (address => x"867C1D8", write_p => '1', value => x"00ec"),
    (address => x"867C1DA", write_p => '1', value => x"00ed"),
    (address => x"867C1DC", write_p => '1', value => x"00ee"),
    (address => x"867C1DE", write_p => '1', value => x"00ef"),
    (address => x"867C1E0", write_p => '1', value => x"00f0"),
    (address => x"867C1E2", write_p => '1', value => x"00f1"),
    (address => x"867C1E4", write_p => '1', value => x"00f2"),
    (address => x"867C1E6", write_p => '1', value => x"00f3"),
    (address => x"867C1E8", write_p => '1', value => x"00f4"),
    (address => x"867C1EA", write_p => '1', value => x"00f5"),
    (address => x"867C1EC", write_p => '1', value => x"00f6"),
    (address => x"867C1EE", write_p => '1', value => x"00f7"),
    (address => x"867C1F0", write_p => '1', value => x"00f8"),
    (address => x"867C1F2", write_p => '1', value => x"00f9"),
    (address => x"867C1F4", write_p => '1', value => x"00fa"),
    (address => x"867C1F6", write_p => '1', value => x"00fb"),
    (address => x"867C1F8", write_p => '1', value => x"00fc"),
    (address => x"867C1FA", write_p => '1', value => x"00fd"),
    (address => x"867C1FC", write_p => '1', value => x"00fe"),
    (address => x"867C1FE", write_p => '1', value => x"00ff"),
    (address => x"867C200", write_p => '1', value => x"0100"),
    
    (address => x"867C000", write_p => '0', value => x"0000"),
    (address => x"867C002", write_p => '0', value => x"0001"),
    (address => x"867C004", write_p => '0', value => x"0002"),
    (address => x"867C006", write_p => '0', value => x"0003"),
    (address => x"867C008", write_p => '0', value => x"0004"),
    (address => x"867C00A", write_p => '0', value => x"0005"),
    (address => x"867C00C", write_p => '0', value => x"0006"),
    (address => x"867C00E", write_p => '0', value => x"0007"),
    (address => x"867C010", write_p => '0', value => x"0008"),
    (address => x"867C012", write_p => '0', value => x"0009"),
    (address => x"867C014", write_p => '0', value => x"000a"),
    (address => x"867C016", write_p => '0', value => x"000b"),
    (address => x"867C018", write_p => '0', value => x"000c"),
    (address => x"867C01A", write_p => '0', value => x"000d"),
    (address => x"867C01C", write_p => '0', value => x"000e"),
    (address => x"867C01E", write_p => '0', value => x"000f"),
    (address => x"867C020", write_p => '0', value => x"0010"),
    (address => x"867C022", write_p => '0', value => x"0011"),
    (address => x"867C024", write_p => '0', value => x"0012"),
    (address => x"867C026", write_p => '0', value => x"0013"),
    (address => x"867C028", write_p => '0', value => x"0014"),
    (address => x"867C02A", write_p => '0', value => x"0015"),
    (address => x"867C02C", write_p => '0', value => x"0016"),
    (address => x"867C02E", write_p => '0', value => x"0017"),
    (address => x"867C030", write_p => '0', value => x"0018"),
    (address => x"867C032", write_p => '0', value => x"0019"),
    (address => x"867C034", write_p => '0', value => x"001a"),
    (address => x"867C036", write_p => '0', value => x"001b"),
    (address => x"867C038", write_p => '0', value => x"001c"),
    (address => x"867C03A", write_p => '0', value => x"001d"),
    (address => x"867C03C", write_p => '0', value => x"001e"),
    (address => x"867C03E", write_p => '0', value => x"001f"),
    (address => x"867C040", write_p => '0', value => x"0020"),
    (address => x"867C042", write_p => '0', value => x"0021"),
    (address => x"867C044", write_p => '0', value => x"0022"),
    (address => x"867C046", write_p => '0', value => x"0023"),
    (address => x"867C048", write_p => '0', value => x"0024"),
    (address => x"867C04A", write_p => '0', value => x"0025"),
    (address => x"867C04C", write_p => '0', value => x"0026"),
    (address => x"867C04E", write_p => '0', value => x"0027"),
    (address => x"867C050", write_p => '0', value => x"0028"),
    (address => x"867C052", write_p => '0', value => x"0029"),
    (address => x"867C054", write_p => '0', value => x"002a"),
    (address => x"867C056", write_p => '0', value => x"002b"),
    (address => x"867C058", write_p => '0', value => x"002c"),
    (address => x"867C05A", write_p => '0', value => x"002d"),
    (address => x"867C05C", write_p => '0', value => x"002e"),
    (address => x"867C05E", write_p => '0', value => x"002f"),
    (address => x"867C060", write_p => '0', value => x"0030"),
    (address => x"867C062", write_p => '0', value => x"0031"),
    (address => x"867C064", write_p => '0', value => x"0032"),
    (address => x"867C066", write_p => '0', value => x"0033"),
    (address => x"867C068", write_p => '0', value => x"0034"),
    (address => x"867C06A", write_p => '0', value => x"0035"),
    (address => x"867C06C", write_p => '0', value => x"0036"),
    (address => x"867C06E", write_p => '0', value => x"0037"),
    (address => x"867C070", write_p => '0', value => x"0038"),
    (address => x"867C072", write_p => '0', value => x"0039"),
    (address => x"867C074", write_p => '0', value => x"003a"),
    (address => x"867C076", write_p => '0', value => x"003b"),
    (address => x"867C078", write_p => '0', value => x"003c"),
    (address => x"867C07A", write_p => '0', value => x"003d"),
    (address => x"867C07C", write_p => '0', value => x"003e"),
    (address => x"867C07E", write_p => '0', value => x"003f"),
    (address => x"867C080", write_p => '0', value => x"0040"),
    (address => x"867C082", write_p => '0', value => x"0041"),
    (address => x"867C084", write_p => '0', value => x"0042"),
    (address => x"867C086", write_p => '0', value => x"0043"),
    (address => x"867C088", write_p => '0', value => x"0044"),
    (address => x"867C08A", write_p => '0', value => x"0045"),
    (address => x"867C08C", write_p => '0', value => x"0046"),
    (address => x"867C08E", write_p => '0', value => x"0047"),
    (address => x"867C090", write_p => '0', value => x"0048"),
    (address => x"867C092", write_p => '0', value => x"0049"),
    (address => x"867C094", write_p => '0', value => x"004a"),
    (address => x"867C096", write_p => '0', value => x"004b"),
    (address => x"867C098", write_p => '0', value => x"004c"),
    (address => x"867C09A", write_p => '0', value => x"004d"),
    (address => x"867C09C", write_p => '0', value => x"004e"),
    (address => x"867C09E", write_p => '0', value => x"004f"),
    (address => x"867C0A0", write_p => '0', value => x"0050"),
    (address => x"867C0A2", write_p => '0', value => x"0051"),
    (address => x"867C0A4", write_p => '0', value => x"0052"),
    (address => x"867C0A6", write_p => '0', value => x"0053"),
    (address => x"867C0A8", write_p => '0', value => x"0054"),
    (address => x"867C0AA", write_p => '0', value => x"0055"),
    (address => x"867C0AC", write_p => '0', value => x"0056"),
    (address => x"867C0AE", write_p => '0', value => x"0057"),
    (address => x"867C0B0", write_p => '0', value => x"0058"),
    (address => x"867C0B2", write_p => '0', value => x"0059"),
    (address => x"867C0B4", write_p => '0', value => x"005a"),
    (address => x"867C0B6", write_p => '0', value => x"005b"),
    (address => x"867C0B8", write_p => '0', value => x"005c"),
    (address => x"867C0BA", write_p => '0', value => x"005d"),
    (address => x"867C0BC", write_p => '0', value => x"005e"),
    (address => x"867C0BE", write_p => '0', value => x"005f"),
    (address => x"867C0C0", write_p => '0', value => x"0060"),
    (address => x"867C0C2", write_p => '0', value => x"0061"),
    (address => x"867C0C4", write_p => '0', value => x"0062"),
    (address => x"867C0C6", write_p => '0', value => x"0063"),
    (address => x"867C0C8", write_p => '0', value => x"0064"),
    (address => x"867C0CA", write_p => '0', value => x"0065"),
    (address => x"867C0CC", write_p => '0', value => x"0066"),
    (address => x"867C0CE", write_p => '0', value => x"0067"),
    (address => x"867C0D0", write_p => '0', value => x"0068"),
    (address => x"867C0D2", write_p => '0', value => x"0069"),
    (address => x"867C0D4", write_p => '0', value => x"006a"),
    (address => x"867C0D6", write_p => '0', value => x"006b"),
    (address => x"867C0D8", write_p => '0', value => x"006c"),
    (address => x"867C0DA", write_p => '0', value => x"006d"),
    (address => x"867C0DC", write_p => '0', value => x"006e"),
    (address => x"867C0DE", write_p => '0', value => x"006f"),
    (address => x"867C0E0", write_p => '0', value => x"0070"),
    (address => x"867C0E2", write_p => '0', value => x"0071"),
    (address => x"867C0E4", write_p => '0', value => x"0072"),
    (address => x"867C0E6", write_p => '0', value => x"0073"),
    (address => x"867C0E8", write_p => '0', value => x"0074"),
    (address => x"867C0EA", write_p => '0', value => x"0075"),
    (address => x"867C0EC", write_p => '0', value => x"0076"),
    (address => x"867C0EE", write_p => '0', value => x"0077"),
    (address => x"867C0F0", write_p => '0', value => x"0078"),
    (address => x"867C0F2", write_p => '0', value => x"0079"),
    (address => x"867C0F4", write_p => '0', value => x"007a"),
    (address => x"867C0F6", write_p => '0', value => x"007b"),
    (address => x"867C0F8", write_p => '0', value => x"007c"),
    (address => x"867C0FA", write_p => '0', value => x"007d"),
    (address => x"867C0FC", write_p => '0', value => x"007e"),
    (address => x"867C0FE", write_p => '0', value => x"007f"),
    (address => x"867C100", write_p => '0', value => x"0080"),
    (address => x"867C102", write_p => '0', value => x"0081"),
    (address => x"867C104", write_p => '0', value => x"0082"),
    (address => x"867C106", write_p => '0', value => x"0083"),
    (address => x"867C108", write_p => '0', value => x"0084"),
    (address => x"867C10A", write_p => '0', value => x"0085"),
    (address => x"867C10C", write_p => '0', value => x"0086"),
    (address => x"867C10E", write_p => '0', value => x"0087"),
    (address => x"867C110", write_p => '0', value => x"0088"),
    (address => x"867C112", write_p => '0', value => x"0089"),
    (address => x"867C114", write_p => '0', value => x"008a"),
    (address => x"867C116", write_p => '0', value => x"008b"),
    (address => x"867C118", write_p => '0', value => x"008c"),
    (address => x"867C11A", write_p => '0', value => x"008d"),
    (address => x"867C11C", write_p => '0', value => x"008e"),
    (address => x"867C11E", write_p => '0', value => x"008f"),
    (address => x"867C120", write_p => '0', value => x"0090"),
    (address => x"867C122", write_p => '0', value => x"0091"),
    (address => x"867C124", write_p => '0', value => x"0092"),
    (address => x"867C126", write_p => '0', value => x"0093"),
    (address => x"867C128", write_p => '0', value => x"0094"),
    (address => x"867C12A", write_p => '0', value => x"0095"),
    (address => x"867C12C", write_p => '0', value => x"0096"),
    (address => x"867C12E", write_p => '0', value => x"0097"),
    (address => x"867C130", write_p => '0', value => x"0098"),
    (address => x"867C132", write_p => '0', value => x"0099"),
    (address => x"867C134", write_p => '0', value => x"009a"),
    (address => x"867C136", write_p => '0', value => x"009b"),
    (address => x"867C138", write_p => '0', value => x"009c"),
    (address => x"867C13A", write_p => '0', value => x"009d"),
    (address => x"867C13C", write_p => '0', value => x"009e"),
    (address => x"867C13E", write_p => '0', value => x"009f"),
    (address => x"867C140", write_p => '0', value => x"00a0"),
    (address => x"867C142", write_p => '0', value => x"00a1"),
    (address => x"867C144", write_p => '0', value => x"00a2"),
    (address => x"867C146", write_p => '0', value => x"00a3"),
    (address => x"867C148", write_p => '0', value => x"00a4"),
    (address => x"867C14A", write_p => '0', value => x"00a5"),
    (address => x"867C14C", write_p => '0', value => x"00a6"),
    (address => x"867C14E", write_p => '0', value => x"00a7"),
    (address => x"867C150", write_p => '0', value => x"00a8"),
    (address => x"867C152", write_p => '0', value => x"00a9"),
    (address => x"867C154", write_p => '0', value => x"00aa"),
    (address => x"867C156", write_p => '0', value => x"00ab"),
    (address => x"867C158", write_p => '0', value => x"00ac"),
    (address => x"867C15A", write_p => '0', value => x"00ad"),
    (address => x"867C15C", write_p => '0', value => x"00ae"),
    (address => x"867C15E", write_p => '0', value => x"00af"),
    (address => x"867C160", write_p => '0', value => x"00b0"),
    (address => x"867C162", write_p => '0', value => x"00b1"),
    (address => x"867C164", write_p => '0', value => x"00b2"),
    (address => x"867C166", write_p => '0', value => x"00b3"),
    (address => x"867C168", write_p => '0', value => x"00b4"),
    (address => x"867C16A", write_p => '0', value => x"00b5"),
    (address => x"867C16C", write_p => '0', value => x"00b6"),
    (address => x"867C16E", write_p => '0', value => x"00b7"),
    (address => x"867C170", write_p => '0', value => x"00b8"),
    (address => x"867C172", write_p => '0', value => x"00b9"),
    (address => x"867C174", write_p => '0', value => x"00ba"),
    (address => x"867C176", write_p => '0', value => x"00bb"),
    (address => x"867C178", write_p => '0', value => x"00bc"),
    (address => x"867C17A", write_p => '0', value => x"00bd"),
    (address => x"867C17C", write_p => '0', value => x"00be"),
    (address => x"867C17E", write_p => '0', value => x"00bf"),
    (address => x"867C180", write_p => '0', value => x"00c0"),
    (address => x"867C182", write_p => '0', value => x"00c1"),
    (address => x"867C184", write_p => '0', value => x"00c2"),
    (address => x"867C186", write_p => '0', value => x"00c3"),
    (address => x"867C188", write_p => '0', value => x"00c4"),
    (address => x"867C18A", write_p => '0', value => x"00c5"),
    (address => x"867C18C", write_p => '0', value => x"00c6"),
    (address => x"867C18E", write_p => '0', value => x"00c7"),
    (address => x"867C190", write_p => '0', value => x"00c8"),
    (address => x"867C192", write_p => '0', value => x"00c9"),
    (address => x"867C194", write_p => '0', value => x"00ca"),
    (address => x"867C196", write_p => '0', value => x"00cb"),
    (address => x"867C198", write_p => '0', value => x"00cc"),
    (address => x"867C19A", write_p => '0', value => x"00cd"),
    (address => x"867C19C", write_p => '0', value => x"00ce"),
    (address => x"867C19E", write_p => '0', value => x"00cf"),
    (address => x"867C1A0", write_p => '0', value => x"00d0"),
    (address => x"867C1A2", write_p => '0', value => x"00d1"),
    (address => x"867C1A4", write_p => '0', value => x"00d2"),
    (address => x"867C1A6", write_p => '0', value => x"00d3"),
    (address => x"867C1A8", write_p => '0', value => x"00d4"),
    (address => x"867C1AA", write_p => '0', value => x"00d5"),
    (address => x"867C1AC", write_p => '0', value => x"00d6"),
    (address => x"867C1AE", write_p => '0', value => x"00d7"),
    (address => x"867C1B0", write_p => '0', value => x"00d8"),
    (address => x"867C1B2", write_p => '0', value => x"00d9"),
    (address => x"867C1B4", write_p => '0', value => x"00da"),
    (address => x"867C1B6", write_p => '0', value => x"00db"),
    (address => x"867C1B8", write_p => '0', value => x"00dc"),
    (address => x"867C1BA", write_p => '0', value => x"00dd"),
    (address => x"867C1BC", write_p => '0', value => x"00de"),
    (address => x"867C1BE", write_p => '0', value => x"00df"),
    (address => x"867C1C0", write_p => '0', value => x"00e0"),
    (address => x"867C1C2", write_p => '0', value => x"00e1"),
    (address => x"867C1C4", write_p => '0', value => x"00e2"),
    (address => x"867C1C6", write_p => '0', value => x"00e3"),
    (address => x"867C1C8", write_p => '0', value => x"00e4"),
    (address => x"867C1CA", write_p => '0', value => x"00e5"),
    (address => x"867C1CC", write_p => '0', value => x"00e6"),
    (address => x"867C1CE", write_p => '0', value => x"00e7"),
    (address => x"867C1D0", write_p => '0', value => x"00e8"),
    (address => x"867C1D2", write_p => '0', value => x"00e9"),
    (address => x"867C1D4", write_p => '0', value => x"00ea"),
    (address => x"867C1D6", write_p => '0', value => x"00eb"),
    (address => x"867C1D8", write_p => '0', value => x"00ec"),
    (address => x"867C1DA", write_p => '0', value => x"00ed"),
    (address => x"867C1DC", write_p => '0', value => x"00ee"),
    (address => x"867C1DE", write_p => '0', value => x"00ef"),
    (address => x"867C1E0", write_p => '0', value => x"00f0"),
    (address => x"867C1E2", write_p => '0', value => x"00f1"),
    (address => x"867C1E4", write_p => '0', value => x"00f2"),
    (address => x"867C1E6", write_p => '0', value => x"00f3"),
    (address => x"867C1E8", write_p => '0', value => x"00f4"),
    (address => x"867C1EA", write_p => '0', value => x"00f5"),
    (address => x"867C1EC", write_p => '0', value => x"00f6"),
    (address => x"867C1EE", write_p => '0', value => x"00f7"),
    (address => x"867C1F0", write_p => '0', value => x"00f8"),
    (address => x"867C1F2", write_p => '0', value => x"00f9"),
    (address => x"867C1F4", write_p => '0', value => x"00fa"),
    (address => x"867C1F6", write_p => '0', value => x"00fb"),
    (address => x"867C1F8", write_p => '0', value => x"00fc"),
    (address => x"867C1FA", write_p => '0', value => x"00fd"),
    (address => x"867C1FC", write_p => '0', value => x"00fe"),
    (address => x"867C1FE", write_p => '0', value => x"00ff"),
    (address => x"867C200", write_p => '0', value => x"0100"),
    
    
    others => ( address => x"FFFFFFF", write_p => '0', value => x"0000")
    );

  -- Wait initially to allow hyperram to reset and set config register
  signal idle_wait : std_logic := '0';
  
  signal expect_value : std_logic := '0';
  signal expected_value : unsigned(15 downto 0) := x"0000";

  signal viciv_addr : unsigned(18 downto 3) := (others => '0');
  signal viciv_request_toggle : std_logic := '0';
  signal viciv_data : unsigned(7 downto 0) := x"00";
  signal viciv_data_strobe : std_logic := '0';
  signal pixel_counter : unsigned(31 downto 0) := to_unsigned(0,32);
  
begin

--  reconfig1: entity work.reconfig
--    port map ( clock => clock163,
--               trigger_reconfigure => '0',
--               reconfigure_address => (others => '0'));
  
  hyperram0: entity work.hyperram
    generic map ( in_simulation => true )
    port map (
      pixelclock => pixelclock,
      clock163 => clock163,
      clock325 => clock325,
      address => expansionram_address,
      wdata => expansionram_wdata(7 downto 0),
      wdata_hi => expansionram_wdata(15 downto 8),
      wen_hi => '1',
      wen_lo => '1',
      read_request => expansionram_read,
      write_request => expansionram_write,
      rdata_16en => '1',
      rdata => expansionram_rdata(7 downto 0),
      rdata_hi =>  expansionram_rdata(15 downto 8),
      data_ready_strobe => expansionram_data_ready_strobe,
      busy => expansionram_busy,

      current_cache_line => current_cache_line,
      current_cache_line_address => current_cache_line_address,
      current_cache_line_valid => current_cache_line_valid,
      expansionram_current_cache_line_next_toggle  => expansionram_current_cache_line_next_toggle,

      viciv_addr => viciv_addr,
      viciv_request_toggle => viciv_request_toggle,
      viciv_data_out => viciv_data,
      viciv_data_strobe => viciv_data_strobe,
      
      hr_d => hr_d,
      hr_rwds => hr_rwds,
      hr_reset => hr_reset,
      hr_clk_n => hr_clk_n,
      hr_clk_p => hr_clk_p,
      hr_cs0 => hr_cs0,

      hr2_d => hr2_d,
      hr2_rwds => hr2_rwds,
      hr2_reset => hr2_reset,
      hr2_clk_n => hr2_clk_n,
      hr2_clk_p => hr2_clk_p,
      hr_cs1 => hr2_cs0
      
      );

  fakehyper0: entity work.s27kl0641
    generic map (
      id => "$8000000",
      tdevice_vcs => 5 ns,
      timingmodel => "S27KL0641DABHI000"
      )
    port map (
      DQ7 => hr_d(7),
      DQ6 => hr_d(6),
      DQ5 => hr_d(5),
      DQ4 => hr_d(4),
      DQ3 => hr_d(3),
      DQ2 => hr_d(2),
      DQ1 => hr_d(1),
      DQ0 => hr_d(0),

      CSNeg => hr_cs0,
      CK => hr_clk_p,
      RESETneg => hr_reset,
      RWDS => hr_rwds
      );
  

  fakehyper1: entity work.s27kl0641
    generic map (
      id => "$8800000",
      tdevice_vcs => 5 ns,
      timingmodel => "S27KL0641DABHI000"
      )
    port map (
      DQ7 => hr2_d(7),
      DQ6 => hr2_d(6),
      DQ5 => hr2_d(5),
      DQ4 => hr2_d(4),
      DQ3 => hr2_d(3),
      DQ2 => hr2_d(2),
      DQ1 => hr2_d(1),
      DQ0 => hr2_d(0),

      CSNeg => hr2_cs0,
      CK => hr2_clk_p,
      RESETneg => hr2_reset,
      RWDS => hr2_rwds
      );
  
  process(hr_cs0, hr_clk_p, hr_reset, hr_rwds, hr_d,
          hr2_cs0, hr2_clk_p, hr2_reset, hr2_rwds, hr2_d
          ) is
  begin
    if true then
      report
        "hr_cs0 = " & std_logic'image(hr_cs0) & ", " &
        "hr_clk_p = " & std_logic'image(hr_clk_p) & ", " &
        "hr_reset = " & std_logic'image(hr_reset) & ", " &
        "hr_rwds = " & std_logic'image(hr_rwds) & ", " &
        "hr_d = " & std_logic'image(hr_d(0))
        & std_logic'image(hr_d(1))
        & std_logic'image(hr_d(2))
        & std_logic'image(hr_d(3))
        & std_logic'image(hr_d(4))
        & std_logic'image(hr_d(5))
        & std_logic'image(hr_d(6))
        & std_logic'image(hr_d(7))
        & ".";
      report
        "hr2_cs0 = " & std_logic'image(hr2_cs0) & ", " &
        "hr2_clk_p = " & std_logic'image(hr2_clk_p) & ", " &
        "hr2_reset = " & std_logic'image(hr2_reset) & ", " &
        "hr2_rwds = " & std_logic'image(hr2_rwds) & ", " &
        "hr2_d = " & std_logic'image(hr2_d(0))
        & std_logic'image(hr2_d(1))
        & std_logic'image(hr2_d(2))
        & std_logic'image(hr2_d(3))
        & std_logic'image(hr2_d(4))
        & std_logic'image(hr2_d(5))
        & std_logic'image(hr2_d(6))
        & std_logic'image(hr2_d(7))
        & ".";
    end if;
  end process;

  process (pixelclock) is
  begin
    if false and rising_edge(pixelclock) then
      pixel_counter <= pixel_counter + 1;
      if (pixel_counter(9 downto 0) = to_unsigned(0,10)) then
        report "VIC: Dispatching pixel data request";
        viciv_request_toggle <= pixel_counter(10);
        viciv_addr <= pixel_counter(23 downto 8);
      end if;
      if viciv_data_strobe='1' then
        report "VIC: Received byte $" & to_hstring(viciv_data);
      end if;
    end if;
  end process;
  
  
  process (clock325) is
  begin
    if rising_edge(clock325) then
      current_time <= current_time + 3;
    end if;
  end process;
  
  process (pixelclock) is
  begin

    if rising_edge(pixelclock) then

      if true then
        report "expansionram_data_ready_strobe=" & std_logic'image(expansionram_data_ready_strobe) 
          & ", expansionram_busy=" & std_logic'image(expansionram_busy)
          & ", expansionram_read=" & std_logic'image(expansionram_read)
          & ", idle_wait=" & std_logic'image(idle_wait)
          & ", expect_value=" & std_logic'image(expect_value);
      end if;
      
      if expansionram_data_ready_strobe='1' then
        if expect_value = '1' then
          if expected_value = expansionram_rdata then
            report "DISPATCHER: Read correct value $" & to_hstring(expansionram_rdata)
              & " after " & integer'image(current_time - dispatch_time) & "ns.";
          else
            report "DISPATCHER: ERROR: Expected $" & to_hstring(expected_value) & ", but saw $" & to_hstring(expansionram_rdata)
              & " after " & integer'image(current_time - dispatch_time) & "ns.";            
          end if;
          dispatch_time <= current_time;
        end if;        
        expect_value <= '0';
        idle_wait <= '0';
      end if;

      expansionram_write <= '0';
      expansionram_read <= '0';

      if expansionram_busy='1' then
        idle_wait <= '0';
      else
        if expect_value = '0' and expansionram_busy='0' then

          if expansionram_busy = '0' and idle_wait='0' then

            if mem_jobs(cycles).address = x"FFFFFFF" then
              report "DISPATCHER: Total sequence was " & integer'image(current_time - start_time) & "ns "
                & "(mean " & integer'image(1+(current_time-start_time)/cycles) & "ns ).";
              cycles <= 0;
              start_time <= current_time;          
            else
              cycles <= cycles + 1;        
            end if;

            dispatch_time <= current_time;
            
            expansionram_address <= mem_jobs(cycles).address(26 downto 0);
            expansionram_write <= mem_jobs(cycles).write_p;
            expansionram_read <= not mem_jobs(cycles).write_p;
            expansionram_wdata <= mem_jobs(cycles).value;
            -- Only wait for memory reads?
            idle_wait <= not mem_jobs(cycles).write_p;

            if (mem_jobs(cycles).write_p='0') then
              -- Let reads finish serially
              -- (In the worst case, this can take quite a while)
              report "DISPATCHER: Reading from $" & to_hstring(mem_jobs(cycles).address) & ", expecting to see $"
                & to_hstring(mem_jobs(cycles).value);
              expect_value <= '1';
              expected_value <= mem_jobs(cycles).value;
            else
              report "DISPATCHER: Writing to $" & to_hstring(mem_jobs(cycles).address) & " <- $"
                & to_hstring(mem_jobs(cycles).value);
              expect_value <= '0';
              dispatch_time <= current_time;
            end if;

            if start_time = 0 then
              start_time <= current_time;
            end if;
          end if;
        end if;
      end if;
    end if;
    
  end process;

  process is
  begin
    
    clock325 <= '0';
    pixelclock <= '0';
    cpuclock <= '0';
    clock163 <= '0';

    report "tick";
    
    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;
    
    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    pixelclock <= '1';
    clock163 <= '0';

    report "tick";   
    
    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    pixelclock <= '0';
    cpuclock <= '1';
    clock163 <= '0';

    report "tick";    

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    pixelclock <= '1';
    clock163 <= '0';

    report "tick";
    
    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

--    report "40MHz CPU clock cycle finished";
    
  end process;


end foo;
