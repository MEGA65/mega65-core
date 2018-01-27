use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity matrix_to_ascii is
  generic (scan_frequency : integer := 1000;
           clock_frequency : integer);
  port (Clk : in std_logic;
        reset_in : in std_logic;
        matrix : in std_logic_vector(71 downto 0);

        -- UART key stream
        ascii_key : out unsigned(7 downto 0) := (others => '0');
        -- Bucky key list:
        -- 0 = left shift
        -- 1 = right shift
        -- 2 = control
        -- 3 = C=
        -- 4 = ALT
        -- 5 = NO SCROLL
        -- 6 = ASC/DIN/CAPS LOCK (XXX - Has a separate line. Not currently monitored)
        bucky_key : out std_logic_vector(6 downto 0) := (others  => '0');
        ascii_key_valid : out std_logic := '0'
        );
end entity matrix_to_ascii;
  
architecture behavioral of matrix_to_ascii is
  signal keyscan_counter : integer := 0;
  -- Multiple by 11, as there are 11 scan phases
  constant keyscan_delay : integer := clock_frequency/(72*scan_frequency);

  signal matrix_last : std_logic_vector(71 downto 0) := (others => '1');

  type key_matrix_t is array(0 to 71) of unsigned(7 downto 0);
  signal matrix_normal : key_matrix_t := (
    0 => x"14", -- INS/DEL
    1 => x"0D", -- RET/NO KEY
    2 => x"1d", -- HORZ/CRSR
    3 => x"f7", -- F8/F7
    4 => x"f1", -- F2/F1
    5 => x"f3", -- F4/F3
    6 => x"f5", -- F6/F5
    7 => x"11", -- VERT/CRSR
    8 => x"33", -- #/3
    9 => x"77", -- W/w
    10 => x"61", -- A/a
    11 => x"34", -- $/4
    12 => x"7a", -- Z/z
    13 => x"73", -- S/s
    14 => x"65", -- E/e
    15 => x"00", -- LEFT/SHIFT
    16 => x"35", -- %/5
    17 => x"72", -- R/r
    18 => x"64", -- D/d
    19 => x"36", -- &/6
    20 => x"63", -- C/c
    21 => x"66", -- F/f
    22 => x"74", -- T/t
    23 => x"78", -- X/x
    24 => x"37", -- '/7
    25 => x"79", -- Y/y
    26 => x"67", -- G/g
    27 => x"38", -- {/8
    28 => x"62", -- B/b
    29 => x"68", -- H/h
    30 => x"75", -- U/u
    31 => x"76", -- V/v
    32 => x"39", -- )/9
    33 => x"69", -- I/i
    34 => x"6a", -- J/j
    35 => x"30", -- {/0
    36 => x"6d", -- M/m
    37 => x"6b", -- K/k
    38 => x"6f", -- O/o
    39 => x"6e", -- N/n
    40 => x"2b", -- NO KEY/+
    41 => x"70", -- P/p
    42 => x"6c", -- L/l
    43 => x"2d", -- NO KEY/-
    44 => x"2e", -- >/.
    45 => x"3a", -- [/:
    46 => x"40", -- NO KEY/@
    47 => x"2c", -- </,
    48 => x"00", -- SPECIAL/UNPRINTABLE/NO KEY
    49 => x"00", -- */NO KEY
    50 => x"3b", -- ]/;
    51 => x"13", -- CLR/HOM
    52 => x"00", -- RIGHT/SHIFT
    53 => x"3d", -- }/=
    54 => x"00", -- SPECIAL/UNPRINTABLE/^
    55 => x"2f", -- ?//
    56 => x"31", -- !/1
    57 => x"5f", -- SPECIAL/UNPRINTABLE/_
    58 => x"00", -- CTRL/NO KEY
    59 => x"32", -- "/2
    60 => x"20", -- SPACE/BAR
    61 => x"00", -- C=/NO KEY
    62 => x"71", -- Q/q
    63 => x"03", -- RUN/STOP
    64 => x"00", -- NO/SCRL
    65 => x"09", -- TAB/NO KEY
    66 => x"00", -- ALT/NO KEY
    67 => x"00", -- HELP/NO KEY
    68 => x"f9", -- F10/F9
    69 => x"fb", -- F12/F11
    70 => x"fd", -- F14/F13
    71 => x"1b", -- ESC/NO KEY

    others => x"00"
    );

  signal matrix_shift : key_matrix_t := (
    0 => x"94", -- INS/DEL
    1 => x"0D", -- RET/NO KEY
    2 => x"9d", -- HORZ/CRSR
    3 => x"f8", -- F8/F7
    4 => x"f2", -- F2/F1
    5 => x"f4", -- F4/F3
    6 => x"f6", -- F6/F5
    7 => x"91", -- VERT/CRSR
    8 => x"23", -- #/3
    9 => x"57", -- W/w
    10 => x"41", -- A/a
    11 => x"24", -- $/4
    12 => x"5a", -- Z/z
    13 => x"53", -- S/s
    14 => x"45", -- E/e
    15 => x"00", -- LEFT/SHIFT
    16 => x"25", -- %/5
    17 => x"52", -- R/r
    18 => x"44", -- D/d
    19 => x"26", -- &/6
    20 => x"43", -- C/c
    21 => x"46", -- F/f
    22 => x"54", -- T/t
    23 => x"58", -- X/x
    24 => x"27", -- '/7
    25 => x"59", -- Y/y
    26 => x"47", -- G/g
    27 => x"7b", -- {/8
    28 => x"42", -- B/b
    29 => x"48", -- H/h
    30 => x"55", -- U/u
    31 => x"56", -- V/v
    32 => x"29", -- )/9
    33 => x"49", -- I/i
    34 => x"4a", -- J/j
    35 => x"7b", -- {/0
    36 => x"4d", -- M/m
    37 => x"4b", -- K/k
    38 => x"4f", -- O/o
    39 => x"4e", -- N/n
    40 => x"00", -- NO KEY/+
    41 => x"50", -- P/p
    42 => x"4c", -- L/l
    43 => x"00", -- NO KEY/-
    44 => x"3e", -- >/.
    45 => x"5b", -- [/:
    46 => x"00", -- NO KEY/@
    47 => x"3c", -- </,
    48 => x"00", -- SPECIAL/UNPRINTABLE/NO KEY
    49 => x"2a", -- */NO KEY
    50 => x"5d", -- ]/;
    51 => x"93", -- CLR/HOM
    52 => x"00", -- RIGHT/SHIFT
    53 => x"7d", -- }/=
    54 => x"00", -- SPECIAL/UNPRINTABLE/^
    55 => x"3f", -- ?//
    56 => x"21", -- !/1
    57 => x"7e", -- SPECIAL/UNPRINTABLE/_
    58 => x"00", -- CTRL/NO KEY
    59 => x"22", -- "/2
    60 => x"20", -- SPACE/BAR
    61 => x"00", -- C=/NO KEY
    62 => x"51", -- Q/q
    63 => x"a3", -- RUN/STOP
    64 => x"00", -- NO/SCRL
    65 => x"0f", -- TAB/NO KEY
    66 => x"00", -- ALT/NO KEY
    67 => x"00", -- HELP/NO KEY
    68 => x"fa", -- F10/F9
    69 => x"fc", -- F12/F11
    70 => x"fe", -- F14/F13
    71 => x"1b", -- ESC/NO KEY

    others => x"00"
    );

  signal matrix_control : key_matrix_t := (
    0 => x"94", -- INS/DEL
    1 => x"0D", -- RET/NO KEY
    2 => x"9d", -- HORZ/CRSR
    3 => x"f8", -- F8/F7
    4 => x"f2", -- F2/F1
    5 => x"f4", -- F4/F3
    6 => x"f6", -- F6/F5
    7 => x"91", -- VERT/CRSR
    8 => x"9f", -- #/SPECIAL/UNPRINTABLE
    9 => x"17", -- W/SPECIAL/UNPRINTABLE
    10 => x"01", -- A/SPECIAL/UNPRINTABLE
    11 => x"9c", -- $/SPECIAL/UNPRINTABLE
    12 => x"1a", -- Z/SPECIAL/UNPRINTABLE
    13 => x"13", -- S/SPECIAL/UNPRINTABLE
    14 => x"05", -- E/SPECIAL/UNPRINTABLE
    15 => x"00", -- LEFT/SHIFT
    16 => x"1e", -- %/SPECIAL/UNPRINTABLE
    17 => x"12", -- R/SPECIAL/UNPRINTABLE
    18 => x"04", -- D/SPECIAL/UNPRINTABLE
    19 => x"1f", -- &/SPECIAL/UNPRINTABLE
    20 => x"03", -- C/SPECIAL/UNPRINTABLE
    21 => x"06", -- F/SPECIAL/UNPRINTABLE
    22 => x"14", -- T/SPECIAL/UNPRINTABLE
    23 => x"18", -- X/SPECIAL/UNPRINTABLE
    24 => x"9e", -- '/SPECIAL/UNPRINTABLE
    25 => x"19", -- Y/SPECIAL/UNPRINTABLE
    26 => x"07", -- G/SPECIAL/UNPRINTABLE
    27 => x"81", -- {/SPECIAL/UNPRINTABLE
    28 => x"02", -- B/SPECIAL/UNPRINTABLE
    29 => x"08", -- H/SPECIAL/UNPRINTABLE
    30 => x"15", -- U/SPECIAL/UNPRINTABLE
    31 => x"16", -- V/SPECIAL/UNPRINTABLE
    32 => x"95", -- )/SPECIAL/UNPRINTABLE
    33 => x"09", -- I/SPECIAL/UNPRINTABLE
    34 => x"0a", -- J/SPECIAL/UNPRINTABLE
    35 => x"00", -- {/NO KEY
    36 => x"0d", -- M/SPECIAL/UNPRINTABLE
    37 => x"0b", -- K/SPECIAL/UNPRINTABLE
    38 => x"0f", -- O/SPECIAL/UNPRINTABLE
    39 => x"0e", -- N/SPECIAL/UNPRINTABLE
    40 => x"2b", -- NO KEY/+
    41 => x"10", -- P/SPECIAL/UNPRINTABLE
    42 => x"0c", -- L/SPECIAL/UNPRINTABLE
    43 => x"2d", -- NO KEY/-
    44 => x"2e", -- >/.
    45 => x"3a", -- [/:
    46 => x"40", -- NO KEY/@
    47 => x"2c", -- </,
    48 => x"00", -- SPECIAL/UNPRINTABLE/NO KEY
    49 => x"00", -- */NO KEY
    50 => x"3b", -- ]/;
    51 => x"93", -- CLR/HOM
    52 => x"00", -- RIGHT/SHIFT
    53 => x"3d", -- }/=
    54 => x"00", -- SPECIAL/UNPRINTABLE/^
    55 => x"2f", -- ?//
    56 => x"05", -- !/SPECIAL/UNPRINTABLE
    57 => x"5f", -- SPECIAL/UNPRINTABLE/_
    58 => x"00", -- CTRL/NO KEY
    59 => x"1c", -- "/SPECIAL/UNPRINTABLE
    60 => x"20", -- SPACE/BAR
    61 => x"00", -- C=/NO KEY
    62 => x"11", -- Q/SPECIAL/UNPRINTABLE
    63 => x"a3", -- RUN/STOP
    64 => x"00", -- NO/SCRL
    65 => x"0f", -- TAB/NO KEY
    66 => x"00", -- ALT/NO KEY
    67 => x"00", -- HELP/NO KEY
    68 => x"fa", -- F10/F9
    69 => x"fc", -- F12/F11
    70 => x"fe", -- F14/F13
    71 => x"1b", -- ESC/NO KEY

    others => x"00"
    );

  signal matrix_cbm : key_matrix_t := (
    0 => x"94", -- INS/DEL
    1 => x"0D", -- RET/NO KEY
    2 => x"ED", -- HORZ/CRSR
    3 => x"f8", -- F8/F7
    4 => x"f2", -- F2/F1
    5 => x"f4", -- F4/F3
    6 => x"f6", -- F6/F5
    7 => x"EE", -- VERT/CRSR
    8 => x"97", -- #/SPECIAL/UNPRINTABLE
    9 => x"d7", -- W/SPECIAL/UNPRINTABLE
    10 => x"c1", -- A/SPECIAL/UNPRINTABLE
    11 => x"98", -- $/SPECIAL/UNPRINTABLE
    12 => x"da", -- Z/SPECIAL/UNPRINTABLE
    13 => x"d3", -- S/SPECIAL/UNPRINTABLE
    14 => x"c5", -- E/SPECIAL/UNPRINTABLE
    15 => x"00", -- LEFT/SHIFT
    16 => x"9a", -- %/SPECIAL/UNPRINTABLE
    17 => x"d2", -- R/SPECIAL/UNPRINTABLE
    18 => x"c4", -- D/SPECIAL/UNPRINTABLE
    19 => x"9b", -- &/SPECIAL/UNPRINTABLE
    20 => x"c3", -- C/SPECIAL/UNPRINTABLE
    21 => x"c6", -- F/SPECIAL/UNPRINTABLE
    22 => x"d4", -- T/SPECIAL/UNPRINTABLE
    23 => x"d8", -- X/SPECIAL/UNPRINTABLE
    24 => x"9c", -- '/SPECIAL/UNPRINTABLE
    25 => x"d9", -- Y/SPECIAL/UNPRINTABLE
    26 => x"c7", -- G/SPECIAL/UNPRINTABLE
    27 => x"00", -- {/NO KEY
    28 => x"c2", -- B/SPECIAL/UNPRINTABLE
    29 => x"c8", -- H/SPECIAL/UNPRINTABLE
    30 => x"d5", -- U/SPECIAL/UNPRINTABLE
    31 => x"d6", -- V/SPECIAL/UNPRINTABLE
    32 => x"00", -- )/NO KEY
    33 => x"c9", -- I/SPECIAL/UNPRINTABLE
    34 => x"ca", -- J/SPECIAL/UNPRINTABLE
    35 => x"81", -- {/SPECIAL/UNPRINTABLE
    36 => x"cd", -- M/SPECIAL/UNPRINTABLE
    37 => x"cb", -- K/SPECIAL/UNPRINTABLE
    38 => x"cf", -- O/SPECIAL/UNPRINTABLE
    39 => x"ce", -- N/SPECIAL/UNPRINTABLE
    40 => x"2b", -- NO KEY/+
    41 => x"d0", -- P/SPECIAL/UNPRINTABLE
    42 => x"cc", -- L/SPECIAL/UNPRINTABLE
    43 => x"2d", -- NO KEY/-
    44 => x"2e", -- >/.
    45 => x"3a", -- [/:
    46 => x"40", -- NO KEY/@
    47 => x"2c", -- </,
    48 => x"00", -- SPECIAL/UNPRINTABLE/NO KEY
    49 => x"00", -- */NO KEY
    50 => x"3b", -- ]/;
    51 => x"93", -- CLR/HOM
    52 => x"00", -- RIGHT/SHIFT
    53 => x"3d", -- }/=
    54 => x"00", -- SPECIAL/UNPRINTABLE/^
    55 => x"2f", -- ?//
    56 => x"95", -- !/SPECIAL/UNPRINTABLE
    57 => x"ef", -- SPECIAL/UNPRINTABLE/_    C= + <- = matrix mode (for C64 keyboards)
    58 => x"00", -- CTRL/NO KEY
    59 => x"96", -- "/SPECIAL/UNPRINTABLE
    60 => x"20", -- SPACE/BAR
    61 => x"00", -- C=/NO KEY
    62 => x"d1", -- Q/SPECIAL/UNPRINTABLE
    63 => x"a3", -- RUN/STOP
    64 => x"00", -- NO/SCRL
    65 => x"ef", -- TAB/NO KEY               C= + TAB = matrix mode toggle
    66 => x"00", -- ALT/NO KEY
    67 => x"00", -- HELP/NO KEY
    68 => x"fa", -- F10/F9
    69 => x"fc", -- F12/F11
    70 => x"fe", -- F14/F13
    71 => x"1b", -- ESC/NO KEY

    others => x"00"
    );

  signal key_num : integer range 0 to 71 := 0;

  signal bucky_key_internal : std_logic_vector(6 downto 0) := (others => '0');
  signal matrix_internal : std_logic_vector(71 downto 0) := (others => '1');

  -- Automatic key repeat (just repeats ascii_key_valid strobe periodically)
  signal repeat_key : integer range 0 to 71 := 0;
  signal repeat_key_timer : integer := 0;
  constant repeat_start_timer : integer := 25000000/(scan_frequency*72); -- 0.5 sec
  constant repeat_again_timer : integer := 5000000/(scan_frequency*72); -- 0.1 sec
  
begin
  process(clk)
    variable key_matrix : key_matrix_t;
  begin
    if rising_edge(clk) then

--      if reset_in = '1' then
--        matrix_internal <= (others => '1');
--      end if;
      
      -- Which matrix to use, based on modifier key state
      -- C= takes precedence over SHIFT, so that we can have C= + cursor keys
      -- as unique keys
      if bucky_key_internal(3)='1' then
        key_matrix := matrix_cbm;
      elsif bucky_key_internal(0)='1' or bucky_key_internal(1)='1' then
        key_matrix := matrix_shift;
      elsif bucky_key_internal(2)='1' then
        key_matrix := matrix_control;
      else
        key_matrix := matrix_normal;
      end if;

      -- Update modifiers
      bucky_key_internal(0) <= not matrix(15);
      bucky_key_internal(1) <= not matrix(52);
      bucky_key_internal(2) <= not matrix(58);
      bucky_key_internal(3) <= not matrix(61);
      bucky_key_internal(4) <= not matrix(66);
      bucky_key_internal(5) <= not matrix(64);
      bucky_key <= bucky_key_internal;

      -- Check for key press events
      if keyscan_counter /= 0 then
        keyscan_counter <= keyscan_counter - 1;
        ascii_key_valid <= '0';
      else
        keyscan_counter <= keyscan_delay;
        matrix_internal(key_num) <= matrix(key_num);
        if to_UX01(matrix_internal(key_num)) = '1'
          and to_UX01(matrix(key_num))='0' then
          if key_matrix(key_num) /= x"00" then
            -- Key press event
            report "matrix = " & to_string(matrix);
            report "key press, ASCII code = " & to_hstring(key_matrix(key_num));
            ascii_key <= key_matrix(key_num);
            repeat_key <= key_num;
            repeat_key_timer <= repeat_start_timer;
            ascii_key_valid <= '1';
          else
            ascii_key_valid <= '0';
          end if;
        else
          if repeat_key_timer > 0 then
            repeat_key_timer <= repeat_key_timer - 1;
            ascii_key_valid <= '0';
          else
            repeat_key_timer <= repeat_again_timer;
            if matrix(repeat_key)='0' then
              ascii_key_valid <= '1';
              -- Republish the key, so that modifiers can change during repeat,
              -- e.g., to allow cursor direction changing without stopping the
              -- repeat.
              ascii_key <= key_matrix(repeat_key);
            else
              ascii_key_valid <= '0';              
            end if;
          end if;
        end if;
        
        if key_num /= 71 then
          key_num <= key_num + 1;
        else
          key_num <= 0;
        end if;
      end if;
      
    end if;
    
  end process;
end behavioral;
  


