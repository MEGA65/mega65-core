use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity keyboard_virtualiser is
  port (Clk : in std_logic;
        porta_pins : inout  std_logic_vector(7 downto 0) := (others => 'Z');
        portb_pins : inout  std_logic_vector(7 downto 0) := (others => 'Z');
        keyboard_column8_out : out std_logic := '1';
        key_left : in std_logic;
        key_up : in std_logic;

        -- Flag to redirect output to UART instead of virtualised keyboard
        -- matrix 
        matrix_mode : in std_logic;
        
        -- Virtualised keyboard matrix
        porta_to_cia : out std_logic_vector(7 downto 0) := (others => 'Z');
        portb_to_cia : out std_logic_vector(7 downto 0) := (others => 'Z');
        porta_from_cia : in std_logic_vector(7 downto 0);
        portb_from_cia : in std_logic_vector(7 downto 0);
        porta_ddr : in std_logic_vector(7 downto 0);
        portb_ddr : in std_logic_vector(7 downto 0);
        column8_from_cia : in std_logic;

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

end keyboard_virtualiser;

architecture behavioral of iomapper is
  -- Scan a row 100K/sec, so that the scanning is slow enough
  -- for the keyboard and joystick electronics
  constant count_down := 50000000/100000;
  signal counter : integer := count_down;
  
  -- Scanned state of the keyboard and joysticks
  signal joya : std_logic_vector(7 downto 0) := (others => '1');
  signal joyb : std_logic_vector(7 downto 0) := (others => '1');
  signal matrix : std_logic_vector(71 downto 0) := (others => 'Z');

  type key_matrix_t is array(0 to 71) of unsigned(7 downto 0);
  signal matrix_normal : key_matix_t := (
    0 => x"14", -- INS/DEL
    1 => x"00", -- RET/
    2 => x"1d", -- HORZ/CRSR
    3 => x"f8", -- F8/F7
    4 => x"f2", -- F2/F1
    5 => x"f4", -- F4/F3
    6 => x"f6", -- F6/F5
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
    40 => x"2b", -- /+
    41 => x"70", -- P/p
    42 => x"6c", -- L/l
    43 => x"2d", -- /-
    44 => x"2e", -- >/.
    45 => x"3a", -- [/:
    46 => x"40", -- /@
    47 => x"2c", -- </,
    48 => x"00", -- ï¿½/
    49 => x"00", -- */
    50 => x"3b", -- ]/;
    51 => x"13", -- CLR/HOM
    52 => x"00", -- RIGHT/SHIFT
    53 => x"3d", -- }/=
    54 => x"00", -- ï¿½/^
    55 => x"2f", -- ?//
    56 => x"31", -- !/1
    57 => x"5f", -- ~/_
    58 => x"00", -- CTRL/
    59 => x"32", -- "/2
    60 => x"20", -- SPACE/BAR
    61 => x"00", -- C=/
    62 => x"71", -- Q/q
    63 => x"03", -- RUN/STOP
    64 => x"00", -- NO/SCRL
    65 => x"09", -- TAB/
    66 => x"00", -- ALT/
    67 => x"00", -- HELP/
    68 => x"fa", -- F10/F9
    69 => x"fc", -- F12/F11
    70 => x"fe", -- F14/F13
    71 => x"1b", -- ESC/

    others => x"00"
    );

  signal matrix_shift : key_matix_t := (
    0 => x"94", -- INS/DEL
    1 => x"00", -- RET/
    2 => x"9d", -- HORZ/CRSR
    3 => x"f7", -- F8/F7
    4 => x"f1", -- F2/F1
    5 => x"f3", -- F4/F3
    6 => x"f5", -- F6/F5
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
    40 => x"00", -- /+
    41 => x"50", -- P/p
    42 => x"4c", -- L/l
    43 => x"00", -- /-
    44 => x"3e", -- >/.
    45 => x"5b", -- [/:
    46 => x"00", -- /@
    47 => x"3c", -- </,
    48 => x"00", -- ï¿½/
    49 => x"2a", -- */
    50 => x"5d", -- ]/;
    51 => x"93", -- CLR/HOM
    52 => x"00", -- RIGHT/SHIFT
    53 => x"7d", -- }/=
    54 => x"00", -- ï¿½/^
    55 => x"3f", -- ?//
    56 => x"21", -- !/1
    57 => x"7e", -- ~/_
    58 => x"00", -- CTRL/
    59 => x"22", -- "/2
    60 => x"20", -- SPACE/BAR
    61 => x"00", -- C=/
    62 => x"51", -- Q/q
    63 => x"a3", -- RUN/STOP
    64 => x"00", -- NO/SCRL
    65 => x"0f", -- TAB/
    66 => x"00", -- ALT/
    67 => x"00", -- HELP/
    68 => x"f9", -- F10/F9
    69 => x"fb", -- F12/F11
    70 => x"fd", -- F14/F13
    71 => x"1b", -- ESC/

    others => x"00"
    );

  signal matrix_control : key_matix_t := (
    0 => x"94", -- INS/DEL
    1 => x"00", -- RET/
    2 => x"9d", -- HORZ/CRSR
    3 => x"f8", -- F8/F7
    4 => x"f2", -- F2/F1
    5 => x"f4", -- F4/F3
    6 => x"f6", -- F6/F5
    7 => x"91", -- VERT/CRSR
    8 => x"9f", -- #/Ÿ
    9 => x"17", -- W/
    10 => x"01", -- A/
    11 => x"9c", -- $/œ
    12 => x"1a", -- Z/
    13 => x"13", -- S/
    14 => x"05", -- E/
    15 => x"00", -- LEFT/SHIFT
    16 => x"1e", -- %/
    17 => x"12", -- R/
    18 => x"04", -- D/
    19 => x"1f", -- &/
    20 => x"03", -- C/
    21 => x"06", -- F/
    22 => x"14", -- T/
    23 => x"18", -- X/
    24 => x"9e", -- '/ž
    25 => x"19", -- Y/
    26 => x"07", -- G/
    27 => x"81", -- {/
    28 => x"02", -- B/
    29 => x"08", -- H/
    30 => x"15", -- U/
    31 => x"16", -- V/
    32 => x"95", -- )/•
    33 => x"09", -- I/	
    34 => x"0a", -- J/

    35 => x"00", -- {/
    36 => x"0d", -- M/
    37 => x"0b", -- K/
    38 => x"0f", -- O/
    39 => x"0e", -- N/
    40 => x"2b", -- /+
    41 => x"10", -- P/
    42 => x"0c", -- L/
    43 => x"2d", -- /-
    44 => x"2e", -- >/.
    45 => x"3a", -- [/:
    46 => x"40", -- /@
    47 => x"2c", -- </,
    48 => x"00", -- ï¿½/
    49 => x"00", -- */
    50 => x"3b", -- ]/;
    51 => x"93", -- CLR/HOM
    52 => x"00", -- RIGHT/SHIFT
    53 => x"3d", -- }/=
    54 => x"00", -- ï¿½/^
    55 => x"2f", -- ?//
    56 => x"05", -- !/
    57 => x"5f", -- ~/_
    58 => x"00", -- CTRL/
    59 => x"1c", -- "/
    60 => x"20", -- SPACE/BAR
    61 => x"00", -- C=/
    62 => x"11", -- Q/
    63 => x"a3", -- RUN/STOP
    64 => x"00", -- NO/SCRL
    65 => x"0f", -- TAB/
    66 => x"00", -- ALT/
    67 => x"00", -- HELP/
    68 => x"fa", -- F10/F9
    69 => x"fc", -- F12/F11
    70 => x"fe", -- F14/F13
    71 => x"1b", -- ESC/

    others => x"00"
    );

  signal matrix_cbm : key_matrix_t := (
    0 => x"94", -- INS/DEL
    1 => x"00", -- RET/
    2 => x"9d", -- HORZ/CRSR
    3 => x"f8", -- F8/F7
    4 => x"f2", -- F2/F1
    5 => x"f4", -- F4/F3
    6 => x"f6", -- F6/F5
    7 => x"91", -- VERT/CRSR
    8 => x"97", -- #/—
    9 => x"d7", -- W/×
    10 => x"c1", -- A/Á
    11 => x"98", -- $/˜
    12 => x"da", -- Z/Ú
    13 => x"d3", -- S/Ó
    14 => x"c5", -- E/Å
    15 => x"00", -- LEFT/SHIFT
    16 => x"9a", -- %/š
    17 => x"d2", -- R/Ò
    18 => x"c4", -- D/Ä
    19 => x"9b", -- &/›
    20 => x"c3", -- C/Ã
    21 => x"c6", -- F/Æ
    22 => x"d4", -- T/Ô
    23 => x"d8", -- X/Ø
    24 => x"9c", -- '/œ
    25 => x"d9", -- Y/Ù
    26 => x"c7", -- G/Ç
    27 => x"00", -- {/
    28 => x"c2", -- B/Â
    29 => x"c8", -- H/È
    30 => x"d5", -- U/Õ
    31 => x"d6", -- V/Ö
    32 => x"00", -- )/
    33 => x"c9", -- I/É
    34 => x"ca", -- J/Ê
    35 => x"81", -- {/
    36 => x"cd", -- M/Í
    37 => x"cb", -- K/Ë
    38 => x"cf", -- O/Ï
    39 => x"ce", -- N/Î
    40 => x"2b", -- /+
    41 => x"d0", -- P/Ð
    42 => x"cc", -- L/Ì
    43 => x"2d", -- /-
    44 => x"2e", -- >/.
    45 => x"3a", -- [/:
    46 => x"40", -- /@
    47 => x"2c", -- </,
    48 => x"00", -- ï¿½/
    49 => x"00", -- */
    50 => x"3b", -- ]/;
    51 => x"93", -- CLR/HOM
    52 => x"00", -- RIGHT/SHIFT
    53 => x"3d", -- }/=
    54 => x"00", -- ï¿½/^
    55 => x"2f", -- ?//
    56 => x"95", -- !/•
    57 => x"5f", -- ~/_
    58 => x"00", -- CTRL/
    59 => x"96", -- "/–
    60 => x"20", -- SPACE/BAR
    61 => x"00", -- C=/
    62 => x"d1", -- Q/Ñ
    63 => x"a3", -- RUN/STOP
    64 => x"00", -- NO/SCRL
    65 => x"ef", -- TAB/
    66 => x"00", -- ALT/
    67 => x"00", -- HELP/
    68 => x"fa", -- F10/F9
    69 => x"fc", -- F12/F11
    70 => x"fe", -- F14/F13
    71 => x"1b", -- ESC/

    others => x"00"
    );

  
begin
  process (clk)

    procedure check_ascii_key(first : integer) is
      variable key_matrix : key_matrix_t;
    begin
      if bucky_key(0)='1' or bucky_key(1)='1' then
        key_matrix := matrix_shifted;
      elsif buckey_key(2)='1' then
        keyt_matrix := matrix_control;
      elsif buckey_key(3)='1' then
        key_matrix := matrix_cbm;
      else
        key_matrix := matrix_normal;
      end if;
      for b in 0 to 7 loop
        if matrix(first + b) = '1' and portb_pins(b) = '0' then
          -- Key press event
          ascii_key <= key_matrix(first + b);
          ascii_key_valid <= '1';
        end if;
      end loop;
    end procedure;
    
    variable porta_merge : std_logic_vector(7 downto 0) := (others => 'Z');
    variable portb_merge : std_logic_vector(7 downto 0) := (others => 'Z');
  begin
    if rising_edge(clk) then

      ascii_key_valid <= '0';
      
      -- Present virtualised keyboard
      porta_merge := (others => 'Z');
      -- Apply joystick inputs
      for b in 4 downto 0 loop
        if joya(b)='0' and porta_ddr(b)='0' or porta_from_cia(b)='0' then
          porta_merge(b) := '0';
        end if;
        if joyb(b)='0' and portb_ddr(b)='0' or portb_from_cia(b)='0' then
          portb_merge(b) := '0';
        end if;
      end loop;
      -- Apply keyboard columns
      for c in 0 to 8 loop
        for r in 0 to 7 loop
          if matrix(c*8 + r)='0' then
            portb_merge(r) := '0';
          end if;
        end loop;
      end loop;
      -- Apply keyboard rows
      for r in 0 to 7 loop
        for c in 0 to 7 loop
          if matrix(c*8 + r)='0' then
            porta_merge(c) := '0';
          end if;
        end loop;
      end loop;

      -- Scan physical keyboard
      if counter=0 then
        counter <= count_down;
        -- Read the appropriate matrix row or joysticks state
        case scan_phase is
          when 0 =>
            -- Read Joysticks, prepare to read column 0
            joya <= porta_pins; joyb <= portb_pins;
            porta_pins <= ( 0 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 1 =>
            -- Read column 0, prepare column 1
            if (joya(4 downto 0) = "11111") and (joyb(4 downto 0) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix(7 downto 0) <= portb_pins(7 downto 0);
              check_ascii_key(0);
            end if;
            porta_pins <= ( 1 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 2 =>
            -- Read column 1, prepare column 2
            if (joya(4 downto 0) = "11111") and (joyb(4 downto 0) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix(15 downto 8) <= portb_pins(7 downto 0);
              check_ascii_key(8);
              -- note state of left-shift
              if portb_pins(7) = '0' then
                bucky_key(0) <= '1';
              else
                bucky_key(0) <= '0';
              end if;
            end if;
            porta_pins <= ( 2 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 3 =>
            -- Read column 2, prepare column 3
            if (joya(4 downto 0) = "11111") and (joyb(4 downto 0) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix(23 downto 16) <= portb_pins(7 downto 0);
              check_ascii_key(16);
            end if;
            porta_pins <= ( 3 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 4 =>
            -- Read column 3, prepare column 4
            if (joya(4 downto 0) = "11111") and (joyb(4 downto 0) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix(31 downto 24) <= portb_pins(7 downto 0);
              check_ascii_key(24);
            end if;
            porta_pins <= ( 4 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 5 =>
            -- Read column 4, prepare column 5
            if (joya(4 downto 0) = "11111") and (joyb(4 downto 0) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix(39 downto 32) <= portb_pins(7 downto 0);
              check_ascii_key(32);
            end if;
            porta_pins <= ( 5 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 6 =>
            -- Read column 5, prepare column 6
            if (joya(4 downto 0) = "11111") and (joyb(4 downto 0) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix(47 downto 40) <= portb_pins(7 downto 0);
              check_ascii_key(40);
              -- note state of right-shift
              if portb_pins(4) = '0' then
                bucky_key(1) <= '1';
              else
                bucky_key(1) <= '0';
              end if;
            end if;
            porta_pins <= ( 6 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 7 =>
            -- Read column 6, prepare column 7
            if (joya(4 downto 0) = "11111") and (joyb(4 downto 0) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix(55 downto 48) <= portb_pins(7 downto 0);
              check_ascii_key(48);
            end if;
            porta_pins <= ( 7 => '0', others => 'Z');            
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
          when 8 =>
            -- Read column 7, prepare column 8
            if (joya(4 downto 0) = "11111") and (joyb(4 downto 0) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix(63 downto 56) <= portb_pins(7 downto 0);
              check_ascii_key(56);
              -- note state of CTRL
              if portb_pins(2) = '0' then
                bucky_key(2) <= '1';
              else
                bucky_key(2) <= '0';
              end if;
              -- note state of C=
              if portb_pins(5) = '0' then
                bucky_key(3) <= '1';
              else
                bucky_key(3) <= '0';
              end if;
            end if;
            porta_pins <= (others => 'Z');
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '0';
          when 9 =>
            -- Read column 8, prepare joysticks
            if (joya(4 downto 0) = "11111") and (joyb(4 downto 0) = "11111") then
              -- only scan keyboard when joysticks are not interfering
              matrix(71 downto 64) <= portb_pins(7 downto 0);
              check_ascii_key(64);
              -- note state of NO SCROLL
              if portb_pins(0) = '0' then
                bucky_key(4) <= '1';
              else
                bucky_key(4) <= '0';
              end if;
              -- note state of ALT
              if portb_pins(2) = '0' then
                bucky_key(5) <= '1';
              else
                bucky_key(5) <= '0';
              end if;
            end if;
            porta_pins <= (others => 'Z');
            portb_pins <= (others => 'Z');
            keyboard_column8_out <= '1';
        end case;
      else
        counter <= counter - 1;
      end if;
    end if;
  end process;
end behavioral;


    
