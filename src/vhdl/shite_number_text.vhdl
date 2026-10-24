library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.shite_codec_pkg.all;
use work.shite_number_pkg.all;

entity shite_number_text is
  port (
    clock, reset, start : in std_logic;
    format, negative : in std_logic;
    source, destination : in unsigned(27 downto 0);
    input_length, capacity : in unsigned(15 downto 0);
    value : in unsigned(63 downto 0);
    kind : in std_logic;
    scale, decimal_separator : in codec_byte;
    display : in std_logic := '0';
    display_style : in unsigned(3 downto 0) := x"0";
    display_decimals : in codec_byte := x"02";
    display_width : in codec_byte := x"FF";
    busy, done : out std_logic := '0';
    error : out codec_byte := CODEC_OK;
    error_position, result_length : out unsigned(15 downto 0) := (others => '0');
    result_value : out unsigned(63 downto 0) := (others => '0');
    result_kind : out std_logic := '0';
    result_scale : out codec_byte := (others => '0');
    abort : in std_logic := '0';
    ram_valid, ram_write : out std_logic := '0';
    ram_address : out unsigned(27 downto 0) := (others => '0');
    ram_wdata : out unsigned(63 downto 0) := (others => '0');
    ram_byte_enable : out std_logic_vector(7 downto 0) := (others => '0');
    ram_ready, ram_error : in std_logic;
    ram_rdata : in unsigned(63 downto 0)
  );
end entity;

architecture rtl of shite_number_text is
  function magnitude(input_value : integer) return natural is
  begin
    if input_value < 0 then return -input_value; else return input_value; end if;
  end function;
  signal big_start, big_done, big_overflow : std_logic := '0';
  signal big_operation : number_operation := BIG_LOAD;
  signal big_first, big_second, big_third : unsigned(1 downto 0) := (others => '0');
  signal big_value, big_result : unsigned(63 downto 0) := (others => '0');
  signal big_factor : unsigned(3 downto 0) := x"2";
  signal big_addend, big_remainder : codec_byte := (others => '0');
  signal big_index : unsigned(8 downto 0) := (others => '0');
  signal big_comparison : integer range -1 to 1 := 0;
  signal big_length : natural range 0 to 512 := 0;
begin
  integers : entity work.shite_number_integer
    port map (clock => clock, reset => reset, start => big_start,
      operation => big_operation, first => big_first, second => big_second,
      third => big_third, value => big_value, factor => big_factor,
      addend => big_addend, byte_index => big_index, done => big_done,
      overflow => big_overflow, comparison => big_comparison, result => big_result,
      length => big_length, remainder => big_remainder);

  sequencer : process(clock)
    type state_type is (IDLE, FINISH, BIG_WAIT, RAM_SETUP, RAM_WAIT,
      PARSE_READ, PARSE_BYTE, PARSE_ADVANCE, PARSE_END, PARSE_INTEGER,
      PARSE_POWER, PARSE_NORMAL, PARSE_SMALL, PARSE_LARGE, PARSE_LARGE_COMPARE,
      PARSE_BITS, PARSE_BIT_COMPARE, PARSE_BIT_SUBTRACT, PARSE_ROUND,
      PARSE_ROUND_COMPARE, PARSE_PACK,
      FORMAT_BEGIN, FORMAT_INTEGER, FORMAT_FLOAT, RATIO_DENOMINATOR,
      RATIO_LOW_MARGIN, RATIO_HIGH_MARGIN, RATIO_SCALE, RATIO_SCALE_NEXT,
      RATIO_SCALE_LOW, RATIO_READY,
      NORMAL_COMPARE, NORMAL_SMALL, NORMAL_LARGE, NORMAL_LARGE_COMPARE,
      NORMAL_MULTIPLY, NORMAL_LOW, NORMAL_HIGH, NORMAL_NEXT,
      DIGIT_BEGIN, DIGIT_COMPARE, DIGIT_SUBTRACT, DIGIT_HAVE,
      SHORTEST_LOW, SHORTEST_HIGH, SHORTEST_DECIDE, SHORTEST_TIE,
      PRECISION_ROUND, PRECISION_DECIDE, ROUND_DIGITS, DIGITS_READY,
      FIXED_SCALE, FIXED_DIV_START, FIXED_DIV_NORMAL, FIXED_DIV_COMPARE,
      FIXED_DIV_BITS, FIXED_DIV_BIT_COMPARE, FIXED_DIV_SUBTRACT,
      FIXED_DIV_QUOTIENT, FIXED_DIV_ROUND, FIXED_DIV_ROUND_COMPARE,
      DECIMAL_BEGIN, DECIMAL_DIVIDE, DECIMAL_STORED, DECIMAL_NEXT,
      EMIT_BEGIN, EMIT_NEXT, EMIT_DIGIT, EMIT_DIGIT_HAVE, EMIT_WRITE,
      EMIT_EXPONENT);
    type purpose_type is (PARSING, SHORTEST, FIXED_DISPLAY, SCI_DISPLAY, GENERAL_DISPLAY);
    type digits_type is array (0 to 18) of unsigned(3 downto 0);
    variable digits, raw_digits : digits_type;   -- (raw: general's digits before rounding)
    variable raw_exponent : integer range -400 to 400;
    variable fit, fixed_part : integer range -512 to 512;
    variable state, big_return, ram_return : state_type := IDLE;
    variable purpose : purpose_type := PARSING;
    variable input_base, output_base, memory_address, cache_address : unsigned(27 downto 0);
    variable wide_address : unsigned(28 downto 0);
    variable cache_data : unsigned(63 downto 0);
    variable cache_valid, memory_write, cancelled : boolean := false;
    variable input_size, output_capacity, position, used : natural range 0 to 65535;
    variable memory_byte, character_byte, decimal_mark, scale_byte : codec_byte;
    variable lane : natural range 0 to 7;
    variable sign_bit, floating : std_logic;
    variable display_mode, percent, point_seen, exponent_seen, exponent_negative,
      exponent_digit, mantissa_digit, leading_sign, discarded_nonzero : boolean;
    variable fraction_count, significant_count : natural range 0 to 65535;
    variable retained_count : natural range 0 to 800;
    variable decimal_power : integer range -200000 to 200000;
    variable parsed_exponent : natural range 0 to 200000;
    variable binary_exponent : integer range -2048 to 2048;
    variable decimal_exponent : integer range -400 to 400;
    variable shift_count : natural range 0 to 2048;
    variable scale_slot : natural range 0 to 1;
    variable scale_factor : natural range 2 to 10;
    variable remaining_scale : natural range 0 to 2048;
    variable word_value, mantissa, packed_value : unsigned(63 downto 0);
    variable bit_count : natural range 0 to 53;
    variable inclusive, low_candidate, high_candidate, round_up : boolean;
    variable normal_direction : natural range 0 to 2;
    variable digit_value : natural range 0 to 10;
    variable digit_count : natural range 0 to 512;
    variable digit_index : integer range -400 to 800;
    variable digits_in_memory, scientific : boolean;
    variable precision : natural range 1 to 19;
    variable places : natural range 0 to 18;
    variable requested_width : natural range 0 to 255;
    variable requested_style : unsigned(3 downto 0);
    variable requested_decimals : codec_byte;
    variable decimal_position : integer range -400 to 512;
    variable fraction_digits : natural range 0 to 800;
    variable integer_digits : natural range 1 to 512;
    variable emit_phase : natural range 0 to 8;
    variable emit_index : natural range 0 to 800;
    variable exponent_magnitude : natural range 0 to 400;
    variable exponent_divisor : natural range 1 to 100;
    variable plain_length, scientific_length, total_length : natural range 0 to 2048;
    variable temporary : integer range -300000 to 300000;

    procedure fail(code : codec_byte) is
    begin
      error <= code; error_position <= to_unsigned(position, 16);
      result_length <= (others => '0'); state := FINISH;
    end procedure;

    procedure calculate(command : number_operation; first_slot, second_slot, third_slot : natural;
                        return_state : state_type) is
    begin
      big_operation <= command; big_first <= to_unsigned(first_slot, 2);
      big_second <= to_unsigned(second_slot, 2); big_third <= to_unsigned(third_slot, 2);
      big_addend <= (others => '0'); big_start <= '1'; big_return := return_state; state := BIG_WAIT;
    end procedure;

    procedure load(first_slot : natural; input_word : unsigned(63 downto 0); return_state : state_type) is
    begin
      big_value <= input_word; calculate(BIG_LOAD, first_slot, 0, 0, return_state);
    end procedure;

    procedure multiply(first_slot, multiplier, addition : natural; return_state : state_type) is
    begin
      calculate(BIG_MULTIPLY, first_slot, 0, 0, return_state);
      big_factor <= to_unsigned(multiplier, 4); big_addend <= to_unsigned(addition, 8);
    end procedure;

    procedure read_input(return_state : state_type) is
    begin
      memory_address := input_base + to_unsigned(position, 28); memory_write := false;
      ram_return := return_state; state := RAM_SETUP;
    end procedure;

    procedure write_output(return_state : state_type) is
    begin
      memory_address := output_base + to_unsigned(used, 28); memory_write := true;
      ram_return := return_state; state := RAM_SETUP; used := used + 1;
    end procedure;

    procedure finish_float is
    begin
      packed_value := (others => '0'); packed_value(63) := sign_bit;
      result_value <= packed_value; result_kind <= '1'; result_scale <= (others => '0'); state := FINISH;
    end procedure;

  begin
    if rising_edge(clock) then
      done <= '0'; big_start <= '0';
      if reset = '1' then
        state := IDLE; busy <= '0'; ram_valid <= '0'; cache_valid := false; cancelled := false;
      else
        if abort = '1' and state /= IDLE then cancelled := true; end if;
        if cancelled and state /= RAM_WAIT and state /= BIG_WAIT and state /= IDLE then fail(CODEC_ABORTED); end if;
        case state is
          when IDLE =>
            if start = '1' then
              input_base := source; output_base := destination; input_size := to_integer(input_length);
              output_capacity := to_integer(capacity); decimal_mark := decimal_separator;
              sign_bit := negative; word_value := value; floating := kind; scale_byte := scale;
              display_mode := display = '1'; requested_width := to_integer(display_width);
              requested_style := display_style; requested_decimals := display_decimals;
              percent := false; position := 0; used := 0; cancelled := false; cache_valid := false;
              error <= CODEC_OK; error_position <= (others => '0'); result_length <= (others => '0');
              result_value <= (others => '0'); result_kind <= '0'; result_scale <= (others => '0'); busy <= '1';
              wide_address := resize(destination, 29) + resize(capacity, 29);
              if wide_address > to_unsigned(16#10000000#, 29) then fail(CODEC_MEMORY);
              elsif codec_digit(decimal_separator) or decimal_separator = 0 or decimal_separator = 69 or
                decimal_separator = 101 or decimal_separator = 43 or decimal_separator = 45 then fail(CODEC_NUMBER);
              elsif format = '0' then
                wide_address := resize(source, 29) + resize(input_length, 29);
                if wide_address > to_unsigned(16#10000000#, 29) then fail(CODEC_MEMORY);
                elsif input_length = 0 then fail(CODEC_NUMBER);
                else
                  purpose := PARSING; fraction_count := 0; significant_count := 0; retained_count := 0;
                  parsed_exponent := 0; point_seen := false; exponent_seen := false;
                  exponent_negative := false; exponent_digit := false; mantissa_digit := false;
                  leading_sign := false; discarded_nonzero := false;
                  load(0, to_unsigned(0, 64), PARSE_READ);
                end if;
              else state := FORMAT_BEGIN; end if;
            end if;
          when FINISH =>
            if cancelled then error <= CODEC_ABORTED; result_length <= (others => '0'); end if;
            done <= '1'; busy <= '0'; ram_valid <= '0'; state := IDLE;
          when BIG_WAIT =>
            if big_done = '1' then
              if big_overflow = '1' then fail(CODEC_NUMBER); else state := big_return; end if;
            end if;
          when RAM_SETUP =>
            lane := to_integer(memory_address(2 downto 0));
            memory_address(2 downto 0) := "000";
            if not memory_write and cache_valid and cache_address = memory_address then
              memory_byte := cache_data(lane * 8 + 7 downto lane * 8); state := ram_return;
            else
              ram_address <= memory_address; ram_valid <= '1'; ram_write <= '0';
              ram_wdata <= (others => '0'); ram_byte_enable <= (others => '0');
              if memory_write then
                ram_write <= '1'; ram_wdata(lane * 8 + 7 downto lane * 8) <= memory_byte;
                ram_byte_enable(lane) <= '1'; cache_valid := false;
              end if;
              state := RAM_WAIT;
            end if;
          when RAM_WAIT =>
            if ram_ready = '1' then
              ram_valid <= '0';
              if ram_error = '1' then fail(CODEC_MEMORY);
              else
                if not memory_write then
                  cache_data := ram_rdata; cache_address := memory_address; cache_valid := true;
                  memory_byte := ram_rdata(lane * 8 + 7 downto lane * 8);
                end if;
                state := ram_return;
              end if;
            end if;
          when PARSE_READ =>
            if position = input_size then state := PARSE_END; else read_input(PARSE_BYTE); end if;
          when PARSE_BYTE =>
            character_byte := memory_byte; state := PARSE_ADVANCE;
            if codec_digit(character_byte) then
              temporary := to_integer(character_byte) - 48;
              if exponent_seen then
                exponent_digit := true;
                if parsed_exponent < 20000 then
                  parsed_exponent := to_integer(shift_left(to_unsigned(parsed_exponent, 18), 3) +
                    shift_left(to_unsigned(parsed_exponent, 18), 1)) + temporary;
                else parsed_exponent := 200000; end if;
              else
                mantissa_digit := true;
                if point_seen then fraction_count := fraction_count + 1; end if;
                if significant_count /= 0 or temporary /= 0 then
                  significant_count := significant_count + 1;
                  if retained_count < 800 then
                    retained_count := retained_count + 1; multiply(0, 10, temporary, PARSE_ADVANCE);
                  elsif temporary /= 0 then discarded_nonzero := true; end if;
                end if;
              end if;
            elsif (character_byte = 43 or character_byte = 45) and position = 0 then
              leading_sign := true;
              if character_byte = 45 then sign_bit := not sign_bit; end if;
            elsif character_byte = decimal_mark and not point_seen and not exponent_seen then point_seen := true;
            elsif (character_byte = 69 or character_byte = 101) and not exponent_seen and mantissa_digit then
              exponent_seen := true; leading_sign := false;
            elsif (character_byte = 43 or character_byte = 45) and exponent_seen and not leading_sign and not exponent_digit then
              leading_sign := true; exponent_negative := character_byte = 45;
            else fail(CODEC_NUMBER); end if;
          when PARSE_ADVANCE => position := position + 1; state := PARSE_READ;
          when PARSE_END =>
            if not mantissa_digit or (exponent_seen and not exponent_digit) then fail(CODEC_NUMBER);
            elsif not exponent_seen then
              if fraction_count > 18 or significant_count > 19 then fail(CODEC_NUMBER);
              else calculate(BIG_GET, 0, 0, 0, PARSE_INTEGER); end if;
            elsif significant_count = 0 then finish_float;
            else
              decimal_power := parsed_exponent;
              if exponent_negative then decimal_power := -decimal_power; end if;
              temporary := decimal_power - fraction_count + significant_count - retained_count;
              if temporary > 2000 then fail(CODEC_NUMBER);
              elsif temporary < -2000 then finish_float;
              else
                decimal_power := temporary;
                temporary := decimal_power + retained_count - 1;
                if temporary > 308 then fail(CODEC_NUMBER);
                elsif temporary < -309 then finish_float;
                else
                  remaining_scale := magnitude(decimal_power); scale_slot := 0;
                  if decimal_power < 0 then scale_slot := 1; end if;
                  load(1, to_unsigned(1, 64), PARSE_POWER);
                end if;
              end if;
            end if;
          when PARSE_INTEGER =>
            packed_value := big_result;
            if big_length > 8 or (sign_bit = '0' and packed_value(63) = '1') or
              (sign_bit = '1' and packed_value > x"8000000000000000") then fail(CODEC_NUMBER);
            else
              if sign_bit = '1' then packed_value := unsigned(-signed(packed_value)); end if;
              result_value <= packed_value; result_kind <= '0'; result_scale <= to_unsigned(fraction_count, 8); state := FINISH;
            end if;
          when PARSE_POWER =>
            if remaining_scale /= 0 then
              remaining_scale := remaining_scale - 1; multiply(scale_slot, 10, 0, PARSE_POWER);
            else binary_exponent := 0; calculate(BIG_COMPARE, 0, 1, 0, PARSE_NORMAL); end if;
          when PARSE_NORMAL =>
            if big_comparison < 0 then state := PARSE_SMALL; else state := PARSE_LARGE; end if;
          when PARSE_SMALL =>
            if big_comparison >= 0 then state := PARSE_BITS;
            else binary_exponent := binary_exponent - 1; multiply(0, 2, 0, PARSE_BIT_COMPARE); end if;
          when PARSE_BIT_COMPARE =>
            calculate(BIG_COMPARE, 0, 1, 0, PARSE_SMALL);
          when PARSE_LARGE =>
            binary_exponent := binary_exponent + 1; multiply(1, 2, 0, PARSE_LARGE_COMPARE);
          when PARSE_LARGE_COMPARE => calculate(BIG_COMPARE, 0, 1, 0, PARSE_BIT_SUBTRACT);
          when PARSE_BIT_SUBTRACT =>
            if big_comparison >= 0 then state := PARSE_LARGE;
            else binary_exponent := binary_exponent - 1; multiply(0, 2, 0, PARSE_BITS); end if;
          when PARSE_BITS =>
            if binary_exponent < -1023 then finish_float;
            elsif binary_exponent > 1023 then fail(CODEC_NUMBER);
            else
              mantissa := to_unsigned(1, 64); bit_count := 52;
              if binary_exponent = -1023 then bit_count := 51; end if;
              calculate(BIG_SUBTRACT, 0, 1, 0, PARSE_ROUND);
            end if;
          when PARSE_ROUND => multiply(0, 2, 0, PARSE_ROUND_COMPARE);
          when PARSE_ROUND_COMPARE => calculate(BIG_COMPARE, 0, 1, 0, PARSE_PACK);
          when PARSE_PACK =>
            if bit_count /= 0 then
              mantissa := shift_left(mantissa, 1); bit_count := bit_count - 1;
              if big_comparison >= 0 then
                mantissa(0) := '1'; calculate(BIG_SUBTRACT, 0, 1, 0, PARSE_ROUND);
              else state := PARSE_ROUND; end if;
            else
              if big_comparison > 0 or (big_comparison = 0 and (mantissa(0) = '1' or discarded_nonzero)) then mantissa := mantissa + 1; end if;
              if binary_exponent = -1023 then
                if mantissa(52) = '1' then binary_exponent := -1022; else finish_float; end if;
              elsif mantissa(53) = '1' then mantissa := shift_right(mantissa, 1); binary_exponent := binary_exponent + 1; end if;
              if state /= FINISH then
                if binary_exponent > 1023 then fail(CODEC_NUMBER);
                else
                  packed_value := (others => '0'); packed_value(63) := sign_bit;
                  packed_value(62 downto 52) := to_unsigned(binary_exponent + 1023, 11);
                  packed_value(51 downto 0) := mantissa(51 downto 0);
                  result_value <= packed_value; result_kind <= '1'; result_scale <= (others => '0'); state := FINISH;
                end if;
              end if;
            end if;
          when FORMAT_BEGIN =>
            sign_bit := word_value(63); digit_count := 0; digits_in_memory := false;
            scientific := false; decimal_exponent := 0; percent := false;
            if display_mode then
              if requested_decimals > 15 or requested_style > 5 then fail(CODEC_NUMBER);
              else
                places := to_integer(requested_decimals); precision := 17;
                case to_integer(requested_style) is
                  when 1 => purpose := FIXED_DISPLAY;
                  when 2 => purpose := SCI_DISPLAY; precision := places + 1;
                  when 3 => purpose := FIXED_DISPLAY; percent := true;
                  when 4 => purpose := FIXED_DISPLAY; places := 0;
                  when others => purpose := GENERAL_DISPLAY;
                end case;
                if floating = '1' then state := FORMAT_FLOAT; else state := FORMAT_INTEGER; end if;
              end if;
            elsif floating = '1' then purpose := SHORTEST; state := FORMAT_FLOAT;
            elsif scale_byte(7) = '1' or scale_byte > 18 then fail(CODEC_NUMBER);
            else
              purpose := FIXED_DISPLAY; places := to_integer(scale_byte);
              if sign_bit = '1' then word_value := unsigned(-signed(word_value)); end if;
              load(0, word_value, DECIMAL_BEGIN);
            end if;
          when FORMAT_INTEGER =>
            if purpose = GENERAL_DISPLAY then precision := 19; end if;
            if (scale_byte(7) = '1' and scale_byte(6 downto 0) > 62) or
              (scale_byte(7) = '0' and scale_byte > 18) then fail(CODEC_NUMBER);
            elsif word_value = 0 and purpose /= FIXED_DISPLAY then
              if purpose = GENERAL_DISPLAY then precision := 1; end if;
              digit_count := 1; digits(0) := x"0"; decimal_exponent := 0; state := DIGITS_READY;
            else
              if sign_bit = '1' then word_value := unsigned(-signed(word_value)); end if;
              remaining_scale := to_integer(scale_byte(6 downto 0)); scale_slot := 1;
              scale_factor := 10; if scale_byte(7) = '1' then scale_factor := 2; end if;
              load(0, word_value, RATIO_DENOMINATOR);
            end if;
          when FORMAT_FLOAT =>
            if word_value(62 downto 52) = 2047 then fail(CODEC_NUMBER);
            elsif word_value(62 downto 52) = 0 then
              if purpose = GENERAL_DISPLAY then precision := 1; end if;
              digit_count := 1; digits(0) := x"0"; decimal_exponent := 0;
              if purpose = FIXED_DISPLAY then load(0, to_unsigned(0, 64), DECIMAL_BEGIN);
              else state := DIGITS_READY; end if;
            else
              mantissa := resize(word_value(51 downto 0), 64); mantissa(52) := '1';
              binary_exponent := to_integer(word_value(62 downto 52)) - 1075;
              inclusive := mantissa(0) = '0'; scale_factor := 2;
              remaining_scale := magnitude(binary_exponent); scale_slot := 0;
              if binary_exponent < 0 then scale_slot := 1; end if;
              if purpose = SHORTEST then mantissa := shift_left(mantissa, 2); end if;
              load(0, mantissa, RATIO_DENOMINATOR);
            end if;
          when RATIO_DENOMINATOR =>
            if purpose = SHORTEST then load(1, to_unsigned(4, 64), RATIO_LOW_MARGIN);
            else load(1, to_unsigned(1, 64), RATIO_SCALE); end if;
          when RATIO_LOW_MARGIN =>
            temporary := 2;
            if word_value(51 downto 0) = 0 and word_value(62 downto 52) > 1 then temporary := 1; end if;
            load(2, to_unsigned(temporary, 64), RATIO_HIGH_MARGIN);
          when RATIO_HIGH_MARGIN => load(3, to_unsigned(2, 64), RATIO_SCALE);
          when RATIO_SCALE =>
            if remaining_scale = 0 then state := RATIO_READY;
            else remaining_scale := remaining_scale - 1; multiply(scale_slot, scale_factor, 0, RATIO_SCALE_NEXT); end if;
          when RATIO_SCALE_NEXT =>
            if purpose = SHORTEST and scale_slot = 0 then multiply(2, 2, 0, RATIO_SCALE_LOW);
            else state := RATIO_SCALE; end if;
          when RATIO_SCALE_LOW => multiply(3, 2, 0, RATIO_SCALE);
          when RATIO_READY =>
            if purpose = FIXED_DISPLAY then
              remaining_scale := places; if percent then remaining_scale := remaining_scale + 2; end if;
              state := FIXED_SCALE;
            else decimal_exponent := 0; calculate(BIG_COMPARE, 0, 1, 0, NORMAL_COMPARE); end if;
          when NORMAL_COMPARE =>
            if big_comparison < 0 then normal_direction := 0; state := NORMAL_SMALL;
            else state := NORMAL_LARGE; end if;
          when NORMAL_SMALL =>
            if big_comparison >= 0 then state := DIGIT_BEGIN;
            else decimal_exponent := decimal_exponent - 1; state := NORMAL_MULTIPLY; end if;
          when NORMAL_LARGE =>
            decimal_exponent := decimal_exponent + 1; multiply(1, 10, 0, NORMAL_LARGE_COMPARE);
          when NORMAL_LARGE_COMPARE => calculate(BIG_COMPARE, 0, 1, 0, NORMAL_NEXT);
          when NORMAL_NEXT =>
            if big_comparison >= 0 then state := NORMAL_LARGE;
            else decimal_exponent := decimal_exponent - 1; normal_direction := 1; state := NORMAL_MULTIPLY; end if;
          when NORMAL_MULTIPLY => multiply(0, 10, 0, NORMAL_LOW);
          when NORMAL_LOW =>
            if purpose = SHORTEST then multiply(2, 10, 0, NORMAL_HIGH); else state := NORMAL_HIGH; end if;
          when NORMAL_HIGH =>
            if purpose = SHORTEST then multiply(3, 10, 0, DIGIT_HAVE);
            else state := DIGIT_HAVE; end if;
          when DIGIT_HAVE =>
            if normal_direction = 0 then calculate(BIG_COMPARE, 0, 1, 0, NORMAL_SMALL);
            else state := DIGIT_BEGIN; end if;
          when DIGIT_BEGIN =>
            -- General, before the first digit: no more digits than could show in
            -- the width, plain or scientific (with the exponent now known); the
            -- precisions below it are tried from these digits, not made again
            if purpose = GENERAL_DISPLAY and digit_count = 0 then
              fit := 0;
              if decimal_exponent >= 0 then            -- plain: d..d[.d..d]
                if decimal_exponent + 1 + boolean'pos(sign_bit = '1') <= requested_width then
                  fit := requested_width - 1 - boolean'pos(sign_bit = '1');
                  if fit < decimal_exponent + 1 then fit := decimal_exponent + 1; end if;
                end if;
              else                                     -- plain: 0.0..0d..d
                fit := requested_width - 2 - boolean'pos(sign_bit = '1') + decimal_exponent + 1;
              end if;
              fixed_part := 2 + boolean'pos(sign_bit = '1') + boolean'pos(decimal_exponent < 0) +
                boolean'pos(magnitude(decimal_exponent) >= 10) + boolean'pos(magnitude(decimal_exponent) >= 100);
              if requested_width - fixed_part - 1 >= 2 then    -- scientific: d[.d..d]E[-]x
                if requested_width - fixed_part - 1 > fit then fit := requested_width - fixed_part - 1; end if;
              elsif requested_width - fixed_part >= 1 and fit < 1 then fit := 1;
              end if;
              if fit < 1 then fit := 1; end if;
              if fit < precision then precision := fit; end if;
            end if;
            digit_value := 0; calculate(BIG_COMPARE, 0, 1, 0, DIGIT_COMPARE);
          when DIGIT_COMPARE =>
            if big_comparison >= 0 then
              digit_value := digit_value + 1; calculate(BIG_SUBTRACT, 0, 1, 0, DIGIT_SUBTRACT);
            else
              if digit_count = 19 or (purpose = SHORTEST and digit_count = 17) then fail(CODEC_NUMBER);
              else
                digits(digit_count) := to_unsigned(digit_value, 4); digit_count := digit_count + 1;
                if purpose = SHORTEST then calculate(BIG_COMPARE, 0, 2, 0, SHORTEST_LOW);
                elsif digit_count = precision then multiply(0, 2, 0, PRECISION_ROUND);
                else normal_direction := 2; state := NORMAL_MULTIPLY; end if;
              end if;
            end if;
          when DIGIT_SUBTRACT => calculate(BIG_COMPARE, 0, 1, 0, DIGIT_COMPARE);
          when SHORTEST_LOW =>
            low_candidate := big_comparison < 0 or (big_comparison = 0 and inclusive);
            calculate(BIG_SUM_COMPARE, 0, 3, 1, SHORTEST_HIGH);
          when SHORTEST_HIGH =>
            high_candidate := big_comparison > 0 or (big_comparison = 0 and inclusive); state := SHORTEST_DECIDE;
          when SHORTEST_DECIDE =>
            if not low_candidate and not high_candidate then normal_direction := 2; state := NORMAL_MULTIPLY;
            elsif low_candidate and high_candidate then multiply(0, 2, 0, SHORTEST_TIE);
            else
              round_up := high_candidate; digit_index := digit_count - 1; state := ROUND_DIGITS;
            end if;
          when SHORTEST_TIE => calculate(BIG_COMPARE, 0, 1, 0, PRECISION_DECIDE);
          when PRECISION_ROUND => calculate(BIG_COMPARE, 0, 1, 0, PRECISION_DECIDE);
          when PRECISION_DECIDE =>
            raw_digits := digits; raw_exponent := decimal_exponent;
            round_up := big_comparison > 0 or (big_comparison = 0 and (purpose /= SHORTEST or digits(digit_count - 1)(0) = '1'));
            digit_index := digit_count - 1; state := ROUND_DIGITS;
          when ROUND_DIGITS =>
            if round_up then
              if digits(digit_index) = 9 then
                digits(digit_index) := x"0";
                if digit_index = 0 then
                  digits(0) := x"1"; decimal_exponent := decimal_exponent + 1; round_up := false;
                else digit_index := digit_index - 1; end if;
              else digits(digit_index) := digits(digit_index) + 1; round_up := false; end if;
            else state := DIGITS_READY; end if;
          when DIGITS_READY =>
            if purpose = SHORTEST or purpose = GENERAL_DISPLAY then
              if digit_count > 1 and digits(digit_count - 1) = 0 then digit_count := digit_count - 1;
              else
                scientific := purpose = SHORTEST;
                decimal_position := decimal_exponent + 1;
                if scientific then decimal_position := 1; end if;
                fraction_digits := 0;
                if integer(digit_count) > decimal_position then fraction_digits := digit_count - decimal_position; end if;
                if purpose = GENERAL_DISPLAY then
                  plain_length := 1;
                  if decimal_position > 0 then plain_length := decimal_position; end if;
                  if fraction_digits /= 0 then plain_length := plain_length + 1 + fraction_digits; end if;
                  if sign_bit = '1' then plain_length := plain_length + 1; end if;
                  scientific_length := digit_count + 2;
                  if digit_count > 1 then scientific_length := scientific_length + 1; end if;
                  if decimal_exponent < 0 then scientific_length := scientific_length + 1; end if;
                  if magnitude(decimal_exponent) >= 10 then scientific_length := scientific_length + 1; end if;
                  if magnitude(decimal_exponent) >= 100 then scientific_length := scientific_length + 1; end if;
                  if sign_bit = '1' then scientific_length := scientific_length + 1; end if;
                  if plain_length <= requested_width then state := EMIT_BEGIN;
                  elsif scientific_length <= requested_width then
                    scientific := true; decimal_position := 1; fraction_digits := digit_count - 1; state := EMIT_BEGIN;
                  elsif precision > 1 then           -- one digit fewer, rounded from the
                    precision := precision - 1;        -- exact digits (half away from zero:
                    digits := raw_digits;              -- up when the next is 5 or more)
                    digit_count := precision; decimal_exponent := raw_exponent;
                    round_up := raw_digits(precision) >= 5;
                    digit_index := precision - 1; state := ROUND_DIGITS;
                  else fail(CODEC_CAPACITY); end if;
                else state := EMIT_BEGIN; end if;
              end if;
            else
              scientific := true; decimal_position := 1; fraction_digits := places; state := EMIT_BEGIN;
            end if;
          when FIXED_SCALE =>
            if remaining_scale = 0 then load(2, to_unsigned(0, 64), FIXED_DIV_START);
            else remaining_scale := remaining_scale - 1; multiply(0, 10, 0, FIXED_SCALE); end if;
          when FIXED_DIV_START => shift_count := 0; calculate(BIG_COMPARE, 0, 1, 0, FIXED_DIV_NORMAL);
          when FIXED_DIV_NORMAL =>
            if big_comparison < 0 then state := FIXED_DIV_BITS;
            else shift_count := shift_count + 1; multiply(1, 2, 0, FIXED_DIV_COMPARE); end if;
          when FIXED_DIV_COMPARE => calculate(BIG_COMPARE, 0, 1, 0, FIXED_DIV_NORMAL);
          when FIXED_DIV_BITS =>
            if shift_count = 0 then multiply(0, 2, 0, FIXED_DIV_ROUND);
            else shift_count := shift_count - 1; calculate(BIG_DIVIDE2, 1, 0, 0, FIXED_DIV_BIT_COMPARE); end if;
          when FIXED_DIV_BIT_COMPARE => calculate(BIG_COMPARE, 0, 1, 0, FIXED_DIV_SUBTRACT);
          when FIXED_DIV_SUBTRACT =>
            if big_comparison >= 0 then
              digit_value := 1; calculate(BIG_SUBTRACT, 0, 1, 0, FIXED_DIV_QUOTIENT);
            else digit_value := 0; state := FIXED_DIV_QUOTIENT; end if;
          when FIXED_DIV_QUOTIENT => multiply(2, 2, digit_value, FIXED_DIV_BITS);
          when FIXED_DIV_ROUND => calculate(BIG_COMPARE, 0, 1, 0, FIXED_DIV_ROUND_COMPARE);
          when FIXED_DIV_ROUND_COMPARE =>
            temporary := 0; if big_comparison >= 0 then temporary := 1; end if;
            multiply(2, 1, temporary, DECIMAL_NEXT);
          when DECIMAL_NEXT => calculate(BIG_COPY, 0, 2, 0, DECIMAL_BEGIN);
          when DECIMAL_BEGIN =>
            digit_count := 0; digits_in_memory := true; calculate(BIG_DIVIDE10, 0, 0, 0, DECIMAL_DIVIDE);
          when DECIMAL_DIVIDE =>
            digit_value := to_integer(big_remainder); temporary := big_length;
            big_index <= to_unsigned(digit_count, 9);
            calculate(BIG_WRITE_BYTE, 1, 0, 0, DECIMAL_STORED); big_addend <= big_remainder;
          when DECIMAL_STORED =>
            digit_count := digit_count + 1;
            if temporary /= 0 then calculate(BIG_DIVIDE10, 0, 0, 0, DECIMAL_DIVIDE);
            else
              scientific := false; decimal_position := integer(digit_count) - places;
              fraction_digits := places; state := EMIT_BEGIN;
            end if;
          when EMIT_BEGIN =>
            integer_digits := 1; if decimal_position > 0 then integer_digits := decimal_position; end if;
            total_length := integer_digits;
            if sign_bit = '1' then total_length := total_length + 1; end if;
            if fraction_digits /= 0 then total_length := total_length + 1 + fraction_digits; end if;
            exponent_magnitude := magnitude(decimal_exponent); exponent_divisor := 1;
            if exponent_magnitude >= 100 then exponent_divisor := 100;
            elsif exponent_magnitude >= 10 then exponent_divisor := 10; end if;
            if scientific then
              total_length := total_length + 2;
              if decimal_exponent < 0 then total_length := total_length + 1; end if;
              if exponent_divisor >= 10 then total_length := total_length + 1; end if;
              if exponent_divisor = 100 then total_length := total_length + 1; end if;
            end if;
            if percent then total_length := total_length + 1; end if;
            if total_length > output_capacity then fail(CODEC_CAPACITY);
            else emit_phase := 0; emit_index := 0; state := EMIT_NEXT; end if;
          when EMIT_NEXT =>
            state := EMIT_WRITE;
            case emit_phase is
              when 0 =>
                emit_phase := 1;
                if sign_bit = '1' then memory_byte := x"2D"; else state := EMIT_NEXT; end if;
              when 1 =>
                if emit_index = integer_digits then emit_phase := 2; emit_index := 0; state := EMIT_NEXT;
                else
                  digit_index := emit_index; emit_index := emit_index + 1;
                  if decimal_position <= 0 then digit_index := -1; end if;
                  state := EMIT_DIGIT;
                end if;
              when 2 =>
                emit_phase := 3;
                if fraction_digits /= 0 then memory_byte := decimal_mark; else state := EMIT_NEXT; end if;
              when 3 =>
                if emit_index = fraction_digits then emit_phase := 4; state := EMIT_NEXT;
                else digit_index := decimal_position + emit_index; emit_index := emit_index + 1; state := EMIT_DIGIT; end if;
              when 4 =>
                emit_phase := 5;
                if scientific then memory_byte := x"45"; else emit_phase := 7; state := EMIT_NEXT; end if;
              when 5 =>
                emit_phase := 6;
                if decimal_exponent < 0 then memory_byte := x"2D"; else state := EMIT_NEXT; end if;
              when 6 => digit_value := 0; state := EMIT_EXPONENT;
              when 7 =>
                emit_phase := 8;
                if percent then memory_byte := x"25"; else state := EMIT_NEXT; end if;
              when others => result_length <= to_unsigned(used, 16); state := FINISH;
            end case;
          when EMIT_DIGIT =>
            if digit_index < 0 or digit_index >= integer(digit_count) then memory_byte := x"30"; state := EMIT_WRITE;
            elsif digits_in_memory then
              big_index <= to_unsigned(integer(digit_count) - digit_index - 1, 9);
              calculate(BIG_READ_BYTE, 1, 0, 0, EMIT_DIGIT_HAVE);
            else memory_byte := resize(digits(digit_index), 8) + 48; state := EMIT_WRITE; end if;
          when EMIT_DIGIT_HAVE => memory_byte := big_result(7 downto 0) + 48; state := EMIT_WRITE;
          when EMIT_WRITE => write_output(EMIT_NEXT);
          when EMIT_EXPONENT =>
            if exponent_magnitude >= exponent_divisor then
              exponent_magnitude := exponent_magnitude - exponent_divisor; digit_value := digit_value + 1;
            else
              memory_byte := to_unsigned(48 + digit_value, 8);
              if exponent_divisor = 100 then exponent_divisor := 10;
              elsif exponent_divisor = 10 then exponent_divisor := 1;
              else emit_phase := 7; end if;
              state := EMIT_WRITE;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
