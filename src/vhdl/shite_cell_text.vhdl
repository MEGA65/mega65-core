library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.shite_codec_pkg.all;

entity shite_cell_text is
  port (
    clock, reset, start, abort : in std_logic;
    kind : in unsigned(3 downto 0);
    value, cell_format : in unsigned(63 downto 0);
    text_source, scratch, destination : in unsigned(27 downto 0);
    text_length, capacity : in unsigned(15 downto 0);
    width, decimal_separator : in codec_byte;
    screen_codes, upper_case : in std_logic := '0';
    busy, done : out std_logic := '0';
    error : out codec_byte := CODEC_OK;
    result_length : out unsigned(15 downto 0) := (others => '0');
    colour : out unsigned(3 downto 0) := x"0";
    ram_valid, ram_write : out std_logic := '0';
    ram_address : out unsigned(27 downto 0) := (others => '0');
    ram_wdata : out unsigned(63 downto 0) := (others => '0');
    ram_byte_enable : out std_logic_vector(7 downto 0) := (others => '0');
    ram_ready, ram_error : in std_logic;
    ram_rdata : in unsigned(63 downto 0);
    number_start : out std_logic := '0';
    number_value : out unsigned(63 downto 0) := (others => '0');
    number_kind : out std_logic := '0';
    number_scale, number_decimal_separator : out codec_byte := (others => '0');
    number_destination : out unsigned(27 downto 0) := (others => '0');
    number_style : out unsigned(3 downto 0) := x"0";
    number_decimals, number_width : out codec_byte := (others => '0');
    number_done : in std_logic;
    number_error : in codec_byte;
    number_result_length : in unsigned(15 downto 0)
  );
end entity;

architecture rtl of shite_cell_text is
  function error_length(code : natural) return natural is
  begin
    case code is
      when 1 | 2 | 7 => return 7;
      when 3 | 4 | 5 | 8 => return 5 + boolean'pos(code = 5 or code = 8);
      when 6 => return 4;
      when 9 => return 9;
      when others => return 5;
    end case;
  end function;

  function error_byte(code, index : natural) return codec_byte is
    variable name : string(1 to 9);
  begin
    case code is
      when 1 => name := "#DIV/0!  ";
      when 2 => name := "#VALUE!  ";
      when 3 => name := "#REF!    ";
      when 4 => name := "#NUM!    ";
      when 5 => name := "#CIRC!   ";
      when 6 => name := "#N/A     ";
      when 7 => name := "#STACK!  ";
      when 8 => name := "#NAME?   ";
      when 9 => name := "#COMPILE!";
      when others => name := "#NUM!    ";
    end case;
    return to_unsigned(character'pos(name(index + 1)), 8);
  end function;

  function screen_byte(character_byte : codec_byte; capitals : boolean) return codec_byte is
  begin
    if character_byte >= 65 and character_byte <= 90 then
      if capitals then return character_byte - 64; else return character_byte; end if;
    elsif character_byte >= 97 and character_byte <= 122 then return character_byte - 96;
    elsif character_byte >= 64 and character_byte <= 95 then return character_byte - 64;
    else return character_byte; end if;
  end function;

  function ascii_byte(character_byte : codec_byte; capitals : boolean) return codec_byte is
  begin
    if character_byte >= 1 and character_byte <= 26 and not capitals then return character_byte + 96;
    elsif character_byte < 32 then return character_byte + 64;
    else return character_byte; end if;
  end function;
begin
  sequencer : process(clock)
    type state_type is (IDLE, FINISH, NUMBER_REQUEST, NUMBER_WAIT, SCAN, SCAN_BYTE,
      GROUP_COUNT, LAYOUT, OUTPUT_NEXT, CONTENT, CONTENT_BYTE, NUMERIC_CONTENT,
      NUMERIC_BYTE, OUTPUT_BYTE, MEMORY_SETUP, MEMORY_WAIT);
    variable state, memory_return : state_type := IDLE;
    variable source_base, scratch_base, output_base, memory_address, cache_address : unsigned(27 downto 0);
    variable wide_address : unsigned(28 downto 0);
    variable cache_data : unsigned(63 downto 0);
    variable cache_valid, memory_write, cancelled, numeric, hashes, negative_value,
      parenthesised, prefix, suffix, grouped, scientific, converted, capitals, raw_screen : boolean := false;
    variable format_word : unsigned(63 downto 0);
    variable decimal_mark, group_mark, memory_byte : codec_byte;
    variable field_width, used, left_padding, visible_length : natural range 0 to 255;
    variable source_size, source_index, clip_start : natural range 0 to 65535;
    variable integer_count, scan_index, groups, group_counter : natural range 0 to 512;
    variable content_length : natural range 0 to 1024;
    variable numeric_phase : natural range 0 to 5;
    variable number_hint : natural range 0 to 255;
    variable error_code : natural range 0 to 255;
    variable lane : natural range 0 to 7;
    variable alignment : natural range 0 to 3;
    variable temporary : natural range 0 to 65535;

    procedure fail(code : codec_byte) is
    begin
      error <= code; result_length <= (others => '0'); state := FINISH;
    end procedure;

    procedure read_byte(address_value : unsigned(27 downto 0); offset : natural; return_state : state_type) is
    begin
      memory_address := address_value + to_unsigned(offset, 28); memory_write := false;
      memory_return := return_state; state := MEMORY_SETUP;
    end procedure;

    procedure as_error(code : natural) is
    begin
      numeric := false; error_code := 4;
      if code >= 1 and code <= 9 then error_code := code; end if;
      source_size := error_length(error_code); state := LAYOUT;
    end procedure;
  begin
    if rising_edge(clock) then
      done <= '0'; number_start <= '0';
      if reset = '1' then state := IDLE; busy <= '0'; ram_valid <= '0'; cancelled := false;
      else
        if abort = '1' and state /= IDLE then cancelled := true; end if;
        if cancelled and state /= IDLE and state /= MEMORY_WAIT and state /= NUMBER_WAIT then fail(CODEC_ABORTED); end if;
        case state is
          when IDLE =>
            if start = '1' then
              busy <= '1'; error <= CODEC_OK; result_length <= (others => '0');
              cancelled := false; cache_valid := false; used := 0; field_width := to_integer(width);
              format_word := cell_format; decimal_mark := decimal_separator; group_mark := x"2C";
              if decimal_separator = 44 then group_mark := x"2E"; end if;
              converted := screen_codes = '1'; capitals := upper_case = '1';
              source_base := text_source; scratch_base := scratch; output_base := destination;
              source_size := to_integer(text_length); error_code := 0; hashes := false;
              numeric := kind = 3 or kind = 4 or kind = 5;
              negative_value := value(63) = '1'; if kind = 5 then negative_value := value(31) = '1'; end if;
              colour <= cell_format(51 downto 48);
              if numeric and negative_value and cell_format(26) = '1' then colour <= cell_format(55 downto 52); end if;
              parenthesised := numeric and negative_value and cell_format(25) = '1';
              prefix := numeric and cell_format(28) = '1'; suffix := numeric and cell_format(29) = '1';
              grouped := numeric and cell_format(24) = '1';
              alignment := to_integer(cell_format(5 downto 4));
              if alignment = 0 then alignment := 1; if numeric then alignment := 3; end if; end if;
              wide_address := resize(destination, 29) + resize(width, 29);
              if field_width = 0 then state := FINISH;
              elsif resize(width, 16) > capacity then fail(CODEC_CAPACITY);
              elsif wide_address > to_unsigned(16#10000000#, 29) then fail(CODEC_MEMORY);
              elsif numeric then
                wide_address := resize(scratch, 29) + 512;
                if wide_address > to_unsigned(16#10000000#, 29) then fail(CODEC_MEMORY);
                else
                  number_value <= value; number_kind <= '0';
                  if kind = 3 then number_kind <= '1';
                  elsif kind = 5 then number_value <= unsigned(resize(signed(value(31 downto 0)), 64)); end if;
                  number_scale <= cell_format(23 downto 16); number_decimal_separator <= decimal_separator;
                  number_style <= cell_format(3 downto 0); number_decimals <= cell_format(15 downto 8);
                  number_destination <= scratch; number_hint := field_width;
                  temporary := boolean'pos(prefix) + boolean'pos(suffix) + boolean'pos(parenthesised);
                  if temporary >= number_hint then hashes := true; state := LAYOUT;
                  else number_hint := number_hint - temporary; state := NUMBER_REQUEST; end if;
                end if;
              elsif kind = 0 then source_size := 0; state := LAYOUT;
              elsif kind = 6 then as_error(to_integer(value(7 downto 0)));
              elsif kind = 1 or kind = 7 then
                wide_address := resize(text_source, 29) + resize(text_length, 29);
                if wide_address > to_unsigned(16#10000000#, 29) then fail(CODEC_MEMORY); else state := LAYOUT; end if;
              else as_error(4); end if;
            end if;
          when FINISH =>
            if cancelled then error <= CODEC_ABORTED; result_length <= (others => '0'); end if;
            done <= '1'; busy <= '0'; ram_valid <= '0'; state := IDLE;
          when NUMBER_REQUEST =>
            number_width <= to_unsigned(number_hint, 8); number_start <= '1'; state := NUMBER_WAIT;
          when NUMBER_WAIT =>
            if number_done = '1' then
              cache_valid := false;
              if number_error = CODEC_CAPACITY then hashes := true; state := LAYOUT;
              elsif number_error = CODEC_NUMBER then as_error(4);
              elsif number_error /= CODEC_OK then fail(number_error);
              elsif number_result_length > 512 then fail(CODEC_CAPACITY);
              else
                source_base := scratch_base; source_size := to_integer(number_result_length);
                scan_index := 0; integer_count := 0; scientific := false; state := SCAN;
              end if;
            end if;
          when SCAN =>
            if scan_index = source_size then
              groups := 0; group_counter := integer_count; state := GROUP_COUNT;
            else read_byte(source_base, scan_index, SCAN_BYTE); end if;
          when SCAN_BYTE =>
            if memory_byte = 69 then scientific := true;
            elsif codec_digit(memory_byte) and not scientific and scan_index = integer_count + boolean'pos(negative_value) then
              integer_count := integer_count + 1;
            end if;
            scan_index := scan_index + 1; state := SCAN;
          when GROUP_COUNT =>
            if not grouped or scientific then groups := 0; group_counter := integer_count; state := LAYOUT;
            elsif group_counter > 3 then group_counter := group_counter - 3; groups := groups + 1;
            else state := LAYOUT; end if;
          when LAYOUT =>
            clip_start := 0; source_index := 0;
            if hashes then content_length := field_width;
            elsif numeric then
              content_length := source_size + groups + boolean'pos(prefix) + boolean'pos(suffix) + boolean'pos(parenthesised);
              if content_length > field_width then
                temporary := content_length - field_width;
                if format_word(3 downto 0) = 0 and number_hint > temporary then
                  number_hint := number_hint - temporary; state := NUMBER_REQUEST;
                else hashes := true; content_length := field_width; end if;
              end if;
            else
              if source_size > field_width then
                if alignment = 3 then clip_start := source_size - field_width;
                elsif alignment = 2 then clip_start := (source_size - field_width) / 2; end if;
                content_length := field_width;
              else content_length := source_size; end if;
            end if;
            if state = LAYOUT then
              visible_length := content_length; left_padding := 0;
              if alignment = 3 then left_padding := field_width - visible_length;
              elsif alignment = 2 then left_padding := (field_width - visible_length) / 2; end if;
              numeric_phase := 0; source_index := 0; state := OUTPUT_NEXT;
            end if;
          when OUTPUT_NEXT =>
            raw_screen := false;
            if used = field_width then result_length <= to_unsigned(used, 16); state := FINISH;
            elsif used < left_padding or used >= left_padding + visible_length then memory_byte := x"20"; state := OUTPUT_BYTE;
            elsif hashes then memory_byte := x"23"; state := OUTPUT_BYTE;
            elsif numeric then state := NUMERIC_CONTENT;
            else state := CONTENT; end if;
          when CONTENT =>
            if error_code /= 0 then
              memory_byte := error_byte(error_code, clip_start + source_index); source_index := source_index + 1; state := OUTPUT_BYTE;
            else read_byte(source_base, clip_start + source_index, CONTENT_BYTE); end if;
          when CONTENT_BYTE => source_index := source_index + 1; state := OUTPUT_BYTE;
          when NUMERIC_CONTENT =>
            case numeric_phase is
              when 0 =>
                numeric_phase := 1;
                if negative_value then
                  source_index := 1; memory_byte := x"2D";
                  if parenthesised then memory_byte := x"28"; end if;
                  state := OUTPUT_BYTE;
                end if;
              when 1 =>
                numeric_phase := 2;
                if prefix then memory_byte := format_word(39 downto 32); raw_screen := true; state := OUTPUT_BYTE; end if;
              when 2 =>
                if source_index = source_size then numeric_phase := 3;
                elsif grouped and not scientific and integer_count /= 0 and group_counter = 0 then
                  memory_byte := group_mark; group_counter := 3; state := OUTPUT_BYTE;
                else read_byte(source_base, source_index, NUMERIC_BYTE); end if;
              when 3 =>
                numeric_phase := 4;
                if suffix then memory_byte := format_word(47 downto 40); raw_screen := true; state := OUTPUT_BYTE; end if;
              when others => memory_byte := x"29"; numeric_phase := 5; state := OUTPUT_BYTE;
            end case;
          when NUMERIC_BYTE =>
            source_index := source_index + 1;
            if integer_count /= 0 then integer_count := integer_count - 1; if group_counter /= 0 then group_counter := group_counter - 1; end if; end if;
            state := OUTPUT_BYTE;
          when OUTPUT_BYTE =>
            if converted and not raw_screen then memory_byte := screen_byte(memory_byte, capitals);
            elsif not converted and raw_screen then memory_byte := ascii_byte(memory_byte, capitals); end if;
            memory_address := output_base + to_unsigned(used, 28); memory_write := true;
            used := used + 1; memory_return := OUTPUT_NEXT; state := MEMORY_SETUP;
          when MEMORY_SETUP =>
            lane := to_integer(memory_address(2 downto 0)); memory_address(2 downto 0) := "000";
            if not memory_write and cache_valid and cache_address = memory_address then
              memory_byte := cache_data(lane * 8 + 7 downto lane * 8); state := memory_return;
            else
              ram_valid <= '1'; ram_address <= memory_address; ram_write <= '0';
              ram_wdata <= (others => '0'); ram_byte_enable <= (others => '0');
              if memory_write then
                ram_write <= '1'; ram_wdata(lane * 8 + 7 downto lane * 8) <= memory_byte; ram_byte_enable(lane) <= '1';
              end if;
              state := MEMORY_WAIT;
            end if;
          when MEMORY_WAIT =>
            if ram_ready = '1' then
              ram_valid <= '0';
              if ram_error = '1' then fail(CODEC_MEMORY);
              else
                if not memory_write then
                  cache_valid := true; cache_address := memory_address; cache_data := ram_rdata;
                  memory_byte := ram_rdata(lane * 8 + 7 downto lane * 8);
                end if;
                state := memory_return;
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
