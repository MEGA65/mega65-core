library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.shite_codec_pkg.all;

entity shite_formula_codec is
  generic (
    nesting_limit : positive := 32;
    operator_limit : positive := 64;
    value_limit : positive := 32;
    fragment_limit : positive := 128;
    table_limit : positive := 65535
  );
  port (
    clock, reset, start, decompile, abort : in std_logic;
    source, destination, names : in unsigned(27 downto 0);
    source_length, output_capacity : in unsigned(15 downto 0);
    formula_row : in unsigned(19 downto 0);
    formula_column : in unsigned(23 downto 0);
    decimal_separator, argument_separator : in codec_byte;
    busy, done : out std_logic := '0';
    error : out codec_byte := CODEC_OK;
    error_position, result_length : out unsigned(15 downto 0) := (others => '0');
    host_calls : out codec_byte := (others => '0');
    ram_valid, ram_write : out std_logic := '0';
    ram_address : out unsigned(27 downto 0) := (others => '0');
    ram_wdata : out unsigned(63 downto 0) := (others => '0');
    ram_byte_enable : out std_logic_vector(7 downto 0) := (others => '0');
    ram_ready, ram_error : in std_logic;
    ram_rdata : in unsigned(63 downto 0);
    number_start, number_format, number_negative : out std_logic := '0';
    number_source, number_destination : out unsigned(27 downto 0) := (others => '0');
    number_length, number_capacity : out unsigned(15 downto 0) := (others => '0');
    number_value : out unsigned(63 downto 0) := (others => '0');
    number_kind : out std_logic := '0';
    number_scale : out codec_byte := (others => '0');
    number_decimal_separator : out codec_byte := x"2E";
    number_done : in std_logic;
    number_error : in codec_byte;
    number_error_position, number_result_length : in unsigned(15 downto 0);
    number_result_value : in unsigned(63 downto 0);
    number_result_kind : in std_logic;
    number_result_scale : in codec_byte
  );
end entity;

architecture rtl of shite_formula_codec is
  type state_type is (
    IDLE, FINISH, MEMORY_SETUP, MEMORY_WAIT, FETCH, OUTPUT_NEXT, OUTPUT_DONE,
    PATCH_NEXT, PATCH_DONE, SHIFT_READ, SHIFT_WRITE, SHIFT_DONE,
    COPY_READ, COPY_WRITE, COPY_DONE,
    PARSE_NEXT, WORD_SCAN, WORD_END, NUMBER_SCAN, NUMBER_WAIT,
    STRING_SCAN, STRING_QUOTE, STRING_COPY, STRING_BYTE,
    HOST_SCAN, HOST_QUOTE, HOST_PREFIX, HOST_PAYLOAD, HOST_RESULT,
    LOOKUP_FIRST, LOOKUP_SECOND, LOOKUP_CHAR, LOOKUP_COMPARE,
    LOOKUP_COMPILE, LOOKUP_FORMAT,
    FLUSH_OPERATORS, PUSH_OPERATOR, SECOND_OPERATOR,
    ARGUMENT_READY, ARGUMENT_CLASSIFY, ARGUMENT_APPLY, LIST_PATCH, ARGUMENT_AFTER,
    IF_JZ_DONE, IF_JMP_DONE, IF_JZ_PATCHED, IF_DEFAULT_DONE, IF_CLOSED,
    CLOSE_FRAME, COMPILE_END, COMPILE_VALIDATE,
    EMIT_REFERENCE, EMIT_RANGE_FIRST, EMIT_RANGE_SECOND,
    DECODE_NEXT, DECODE_OPCODE, IMMEDIATE_READ, IMMEDIATE_BYTE, IMMEDIATE_DONE,
    COUNT_FIRST, COUNT_SECOND, DECODE_COUNT,
    DECODE_LITERAL, DECODE_SCALE, DECODE_SCALE_BYTE, FORMAT_NUMBER_WAIT,
    DECODE_STRING, DECODE_STRING_BYTE, DECODE_HOST_FINISH,
    DECODE_REFERENCE, REFERENCE_BYTE, REFERENCE_DONE,
    REFERENCE_COLUMN, DIVIDE_STEP, COLUMN_DIGIT, ROW_DIGIT,
    REFERENCE_COLUMN_OUT, REFERENCE_ROW, REFERENCE_ROW_OUT, REFERENCE_FINISH,
    DECODE_RECT_SECOND, DECODE_LIST_NEXT, DECODE_LIST_REF,
    DECODE_FUNCTION_COUNT, DECODE_FUNCTION,
    DECODE_JZ, DECODE_JMP_BYTE, DECODE_JMP_OFFSET, DECODE_JMP_HIGH,
    COMBINE_START, COMBINE_SEPARATOR, COMBINE_SEPARATOR_DONE,
    COMBINE_PREFIX, COMBINE_PREFIX_DONE, COMBINE_NAME_DONE,
    COMBINE_OPERATOR, COMBINE_OPERATOR_DONE, COMBINE_END,
    STACK_SAVE, STACK_SAVE_DONE, STACK_LOAD, STACK_WAIT, STACK_CAPTURE,
    FRAME_LOADED, OPERATOR_LOADED, BRANCH_LOADED,
    COMBINE_BASE_LOADED, COMBINE_READY, COMBINE_RIGHT_LOADED, COMBINE_SEPARATOR_LOADED,
    COMBINE_DEPTH_SCAN, COMBINE_DEPTH_LOADED, COMBINE_DEPTH_DONE
  );
  type byte_array is array (natural range <>) of codec_byte;
  type operator_record is record
    opcode : codec_byte;
    position : natural range 0 to 65535;
  end record;
  type parse_frame is record
    is_function : boolean;
    identifier : natural range 0 to 32767;
    position, argument_start : natural range 0 to 65535;
    operators : natural range 0 to operator_limit;
    arguments, values, list_count : natural range 0 to 32767;
    list_start, jz_slot, jump_slot : natural range 0 to 65535;
    list_active : boolean;
  end record;
  type branch_record is record
    then_end, else_start, finish : natural range 0 to 65535;
    fragments : natural range 0 to fragment_limit;
    depth : natural range 0 to value_limit;
    in_else : boolean;
  end record;
  function memory_size(required : positive) return positive is
    variable result : positive := 1;
  begin
    while result < required loop result := result * 2; end loop;
    return result;
  end;
  constant frame_base : natural := operator_limit;
  constant fragment_base : natural := frame_base + nesting_limit * 8;
  constant branch_base : natural := fragment_base + fragment_limit;
  constant stack_size : positive := memory_size(branch_base + nesting_limit * 2);
  type stack_memory_type is array (0 to stack_size - 1) of unsigned(31 downto 0);
  signal stack_memory : stack_memory_type;
  signal stack_address : natural range 0 to stack_size - 1 := 0;
  signal stack_write : std_logic := '0';
  signal stack_data, stack_result : unsigned(31 downto 0);
begin
  assert operator_limit <= 127 and fragment_limit <= 255 and value_limit <= 63 and
    nesting_limit <= 127 and table_limit <= 65535 severity failure;
  process (clock)
  begin
    if rising_edge(clock) then
      if stack_write = '1' then stack_memory(stack_address) <= stack_data; end if;
      stack_result <= stack_memory(stack_address);
    end if;
  end process;
  process (clock)
    variable state, memory_return, fetch_return, output_return, patch_return,
      shift_return, copy_return, lookup_return, flush_return, count_return,
      immediate_return, reference_return, emit_reference_return, divide_return,
      stack_return, frame_return, operator_return, branch_return : state_type := IDLE;
    variable stack_buffer : unsigned(159 downto 0);
    variable stack_offset : natural range 0 to stack_size - 1;
    variable stack_words, stack_index : natural range 0 to 5;
    variable input_base, output_base, name_base : unsigned(27 downto 0);
    variable origin_row : unsigned(19 downto 0);
    variable origin_column : unsigned(23 downto 0);
    variable input_size, original_size, capacity, position, used, compiled_size : natural range 0 to 65535;
    variable decimal_mark, argument_mark, character_byte, read_byte_value : codec_byte;
    variable cache_valid : boolean := false;
    variable cache_tag : unsigned(24 downto 0);
    variable cache_data : unsigned(63 downto 0);
    variable access_address : unsigned(27 downto 0);
    variable access_base : unsigned(27 downto 0);
    variable access_offset : unsigned(15 downto 0);
    variable access_word : unsigned(63 downto 0);
    variable access_enables : std_logic_vector(7 downto 0);
    variable access_write : boolean;
    variable access_byte : codec_byte;
    variable stage : byte_array(0 to 15);
    variable stage_size, stage_index : natural range 0 to 16;
    variable patch_address, shift_at, shift_index, copy_index : natural range 0 to 65535;
    variable shift_size : natural range 0 to 65535;
    variable copy_source : unsigned(27 downto 0);
    variable copy_destination : natural range 0 to 65535;
    variable copy_size : natural range 0 to 65535;
    variable top_operator : operator_record;
    variable operator_count : natural range 0 to operator_limit;
    variable top_frame : parse_frame;
    variable frame_count : natural range 0 to nesting_limit;
    variable flush_base : natural range 0 to operator_limit;
    variable pending_operator, first_operator : codec_byte;
    variable pending_position : natural range 0 to 65535;
    variable expected_operand, close_argument, pure_argument, range_pending : boolean;
    variable token_start, token_end, text_start, text_length, text_cursor : natural range 0 to 65535;
    variable word_phase : natural range 0 to 4;
    variable row_number, column_number : natural range 0 to 16777216;
    variable row_absolute, column_absolute : std_logic;
    variable reference_value, first_reference : codec_reference;
    variable number_previous : codec_byte;
    variable number_negate : boolean;
    variable host_depth : natural range 0 to nesting_limit;
    variable host_count : natural range 0 to 255;
    variable lookup_cursor, lookup_name : unsigned(27 downto 0);
    variable lookup_scanned : natural range 0 to table_limit;
    variable lookup_identifier, wanted_identifier : natural range 0 to 32767;
    variable lookup_index, lookup_length : natural range 0 to 65535;
    variable lookup_equal, lookup_by_name : boolean;
    variable lookup_character : codec_byte;
    variable validating, cancelling : boolean := false;
    variable fragment_count : natural range 0 to fragment_limit;
    variable top_branch : branch_record;
    variable branch_count : natural range 0 to nesting_limit;
    variable value_depth : natural range 0 to value_limit;
    variable opcode : codec_byte;
    variable immediate : unsigned(63 downto 0);
    variable immediate_size, immediate_index : natural range 0 to 8;
    variable count_value : natural range 0 to 32767;
    variable decoded_function : natural range 0 to 32767;
    variable decoded_remaining : natural range 0 to 32767;
    variable decoded_list : boolean;
    variable decoded_reference_bytes : natural range 0 to 6;
    variable decoded_reference_index : natural range 0 to 6;
    variable short_word : unsigned(31 downto 0);
    variable reference_column_value : unsigned(23 downto 0);
    variable reference_row_value : unsigned(19 downto 0);
    variable digits : byte_array(0 to 15);
    variable digit_count, digit_index : natural range 0 to 16;
    variable dividend, quotient : unsigned(31 downto 0);
    variable remainder_value : unsigned(5 downto 0);
    variable divisor : natural range 1 to 26;
    variable divide_bits : natural range 0 to 32;
    variable jump_else, jump_end, jump_probe : natural range 0 to 65535;
    variable combine_base, combine_count, combine_index : natural range 0 to fragment_limit;
    variable combine_start_position, combine_right_position : natural range 0 to 65535;
    variable combine_separator_position : natural range 0 to 65535;
    variable combine_depth_index : natural range 0 to fragment_limit;
    variable combine_depth : natural range 0 to 65535;
    variable combine_call : boolean;
    variable combine_opcode : codec_byte;
    variable temporary, stage_cursor, argument_bytes : natural;
    variable wide_reference : unsigned(47 downto 0);
    variable signed_value : signed(63 downto 0);
    variable wide_address : unsigned(28 downto 0);

    procedure fail(code : codec_byte; offset : natural) is
    begin
      error <= code;
      if validating then error_position <= to_unsigned(original_size, 16);
      else error_position <= to_unsigned(offset mod 65536, 16); end if;
      result_length <= (others => '0');
      state := FINISH;
    end procedure;

    procedure read_memory(address_value : unsigned(27 downto 0); return_state : state_type;
                          offset : natural := 0) is
    begin
      access_base := address_value; access_offset := to_unsigned(offset, 16);
      access_write := false; memory_return := return_state; state := MEMORY_SETUP;
    end procedure;

    procedure write_memory(offset : natural; value : codec_byte; return_state : state_type) is
    begin
      access_base := output_base; access_offset := to_unsigned(offset, 16);
      access_write := true; access_byte := value;
      memory_return := return_state; state := MEMORY_SETUP;
    end procedure;

    procedure fetch(return_state : state_type) is
    begin
      fetch_return := return_state; state := FETCH;
    end procedure;

    procedure advance(return_state : state_type) is
    begin
      if position < input_size then position := position + 1; end if;
      fetch(return_state);
    end procedure;

    procedure read_input(return_state : state_type) is
    begin
      if position >= input_size then fail(CODEC_BYTECODE, position);
      else
        read_memory(input_base + position, return_state);
        position := position + 1;
      end if;
    end procedure;

    procedure emit(length : natural; return_state : state_type) is
    begin
      stage_size := length; stage_index := 0;
      output_return := return_state; state := OUTPUT_NEXT;
    end procedure;

    procedure emit_one(value : codec_byte; return_state : state_type) is
    begin
      stage(0) := value; emit(1, return_state);
    end procedure;

    procedure append_count(value : natural; variable index : inout natural) is
    begin
      if value < 128 then stage(index) := to_unsigned(value, 8); index := index + 1;
      else
        stage(index) := to_unsigned(128 + value mod 128, 8);
        stage(index + 1) := to_unsigned(value / 128, 8); index := index + 2;
      end if;
    end procedure;

    procedure patch(offset, length : natural; return_state : state_type) is
    begin
      patch_address := offset; stage_size := length; stage_index := 0;
      patch_return := return_state; state := PATCH_NEXT;
    end procedure;

    procedure patch_jump(slot : natural; return_state : state_type) is
    begin
      temporary := used - slot - 3;
      stage(0) := to_unsigned(temporary mod 256, 8);
      stage(1) := to_unsigned(temporary / 256, 8);
      patch(slot + 1, 2, return_state);
    end procedure;

    procedure insert_space(offset, length : natural; return_state : state_type) is
    begin
      if used + length > capacity then fail(CODEC_CAPACITY, position);
      else
        shift_at := offset; shift_size := length; shift_index := used;
        shift_return := return_state; state := SHIFT_READ;
      end if;
    end procedure;

    procedure copy_bytes(address_value : unsigned(27 downto 0); offset, length : natural;
                         return_state : state_type) is
    begin
      copy_source := address_value; copy_destination := offset;
      copy_size := length; copy_index := 0; copy_return := return_state;
      if offset + length > capacity then fail(CODEC_CAPACITY, position);
      else state := COPY_READ; end if;
    end procedure;

    procedure lookup(identifier : natural; by_name : boolean; return_state : state_type) is
    begin
      wanted_identifier := identifier; lookup_by_name := by_name;
      lookup_cursor := name_base; lookup_scanned := 0;
      lookup_return := return_state;
      read_memory(lookup_cursor, LOOKUP_FIRST);
    end procedure;

    procedure next_table(return_state : state_type) is
    begin
      if lookup_scanned + 1 >= table_limit or lookup_cursor = x"FFFFFFF" then
        fail(CODEC_TABLE, token_start);
      else
        lookup_cursor := lookup_cursor + 1; lookup_scanned := lookup_scanned + 1;
        read_memory(lookup_cursor, return_state);
      end if;
    end procedure;

    procedure begin_word is
    begin
      token_start := position; word_phase := 0;
      column_number := 0; row_number := 0;
      column_absolute := '0'; row_absolute := '0'; state := WORD_SCAN;
    end procedure;

    procedure save_stack(offset, length : natural; return_state : state_type) is
    begin
      stack_offset := offset; stack_words := length; stack_index := 0;
      stack_return := return_state; state := STACK_SAVE;
    end procedure;

    procedure load_stack(offset, length : natural; return_state : state_type) is
    begin
      stack_offset := offset; stack_words := length; stack_index := 0;
      stack_return := return_state; state := STACK_LOAD;
    end procedure;

    procedure store_frame is
    begin
      stack_buffer := (others => '0');
      if top_frame.is_function then stack_buffer(0) := '1'; end if;
      stack_buffer(15 downto 1) := to_unsigned(top_frame.identifier, 15);
      stack_buffer(31 downto 16) := to_unsigned(top_frame.position, 16);
      stack_buffer(47 downto 32) := to_unsigned(top_frame.argument_start, 16);
      stack_buffer(54 downto 48) := to_unsigned(top_frame.operators, 7);
      stack_buffer(69 downto 55) := to_unsigned(top_frame.arguments, 15);
      stack_buffer(84 downto 70) := to_unsigned(top_frame.values, 15);
      stack_buffer(99 downto 85) := to_unsigned(top_frame.list_count, 15);
      stack_buffer(115 downto 100) := to_unsigned(top_frame.list_start, 16);
      stack_buffer(131 downto 116) := to_unsigned(top_frame.jz_slot, 16);
      stack_buffer(147 downto 132) := to_unsigned(top_frame.jump_slot, 16);
      if top_frame.list_active then stack_buffer(148) := '1'; end if;
    end procedure;

    procedure write_fragment(index, offset, depth : natural) is
    begin
      stack_address <= fragment_base + index;
      stack_data <= '0' & to_unsigned(depth, 15) & to_unsigned(offset, 16);
      stack_write <= '1';
    end procedure;

    procedure push_frame(is_function : boolean; identifier : natural) is
    begin
      if frame_count = nesting_limit then fail(CODEC_DEPTH, token_start);
      else
        if frame_count > 0 then store_frame; end if;
        top_frame.is_function := is_function;
        top_frame.identifier := identifier;
        top_frame.position := token_start;
        top_frame.argument_start := used;
        top_frame.operators := operator_count;
        top_frame.arguments := 0; top_frame.values := 0;
        top_frame.list_active := false; top_frame.list_count := 0;
        top_frame.list_start := 0;
        top_frame.jz_slot := 0; top_frame.jump_slot := 0;
        frame_count := frame_count + 1; expected_operand := true;
        advance(PARSE_NEXT);
        if frame_count > 1 then save_stack(frame_base + (frame_count - 2) * 8, 5, FETCH); end if;
      end if;
    end procedure;

    procedure pop_frame(return_state : state_type) is
    begin
      frame_count := frame_count - 1;
      if frame_count > 0 then
        frame_return := return_state; load_stack(frame_base + (frame_count - 1) * 8, 5, FRAME_LOADED);
      else state := return_state; end if;
    end procedure;

    procedure push_operator(value : codec_byte; offset : natural; return_state : state_type) is
    begin
      if operator_count > 0 then
        stack_buffer := (others => '0'); stack_buffer(31 downto 24) := top_operator.opcode;
        stack_buffer(15 downto 0) := to_unsigned(top_operator.position, 16);
      end if;
      top_operator.opcode := value; top_operator.position := offset;
      operator_count := operator_count + 1;
      if operator_count > 1 then save_stack(operator_count - 2, 1, return_state);
      else state := return_state; end if;
    end procedure;

    procedure pop_operator(return_state : state_type) is
    begin
      operator_count := operator_count - 1;
      if operator_count > 0 then
        operator_return := return_state; load_stack(operator_count - 1, 1, OPERATOR_LOADED);
      else state := return_state; end if;
    end procedure;

    procedure push_value is
    begin
      if value_depth = value_limit or fragment_count = fragment_limit then
        fail(CODEC_DEPTH, position);
      else
        value_depth := value_depth + 1;
        write_fragment(fragment_count, used, 0);
        fragment_count := fragment_count + 1;
      end if;
    end procedure;

    procedure read_immediate(length : natural; return_state : state_type) is
    begin
      immediate := (others => '0'); immediate_size := length; immediate_index := 0;
      immediate_return := return_state; state := IMMEDIATE_READ;
    end procedure;

    procedure read_count(return_state : state_type) is
    begin
      count_return := return_state; read_input(COUNT_FIRST);
    end procedure;

    procedure decode_reference(return_state : state_type) is
    begin
      reference_return := return_state; read_input(DECODE_REFERENCE);
    end procedure;

    procedure start_divide(value : unsigned(31 downto 0); base : positive;
                           return_state : state_type) is
    begin
      dividend := value; quotient := (others => '0'); remainder_value := (others => '0');
      divisor := base; divide_bits := 32; divide_return := return_state; state := DIVIDE_STEP;
    end procedure;
  begin
    if rising_edge(clock) then
      done <= '0'; number_start <= '0'; stack_write <= '0';
      if reset = '1' then
        state := IDLE; busy <= '0'; ram_valid <= '0';
        cache_valid := false; cancelling := false;
        error <= CODEC_OK; result_length <= (others => '0');
      else
        if abort = '1' and state /= IDLE then cancelling := true; end if;
        if cancelling and state /= MEMORY_WAIT and state /= NUMBER_WAIT and
          state /= FORMAT_NUMBER_WAIT and state /= IDLE and state /= FINISH then
          fail(CODEC_ABORTED, position);
        else
          case state is
            when STACK_SAVE =>
              stack_address <= stack_offset + stack_index;
              stack_data <= stack_buffer(stack_index * 32 + 31 downto stack_index * 32);
              stack_write <= '1'; stack_index := stack_index + 1;
              if stack_index = stack_words then state := STACK_SAVE_DONE; end if;
            when STACK_SAVE_DONE => state := stack_return;
            when STACK_LOAD => stack_address <= stack_offset + stack_index; state := STACK_WAIT;
            when STACK_WAIT => state := STACK_CAPTURE;
            when STACK_CAPTURE =>
              stack_buffer(stack_index * 32 + 31 downto stack_index * 32) := stack_result;
              stack_index := stack_index + 1;
              if stack_index = stack_words then state := stack_return; else state := STACK_LOAD; end if;
            when FRAME_LOADED =>
              top_frame.is_function := stack_buffer(0) = '1';
              top_frame.identifier := to_integer(stack_buffer(15 downto 1));
              top_frame.position := to_integer(stack_buffer(31 downto 16));
              top_frame.argument_start := to_integer(stack_buffer(47 downto 32));
              top_frame.operators := to_integer(stack_buffer(54 downto 48));
              top_frame.arguments := to_integer(stack_buffer(69 downto 55));
              top_frame.values := to_integer(stack_buffer(84 downto 70));
              top_frame.list_count := to_integer(stack_buffer(99 downto 85));
              top_frame.list_start := to_integer(stack_buffer(115 downto 100));
              top_frame.jz_slot := to_integer(stack_buffer(131 downto 116));
              top_frame.jump_slot := to_integer(stack_buffer(147 downto 132));
              top_frame.list_active := stack_buffer(148) = '1'; state := frame_return;
            when OPERATOR_LOADED =>
              top_operator.opcode := stack_buffer(31 downto 24);
              top_operator.position := to_integer(stack_buffer(15 downto 0)); state := operator_return;
            when BRANCH_LOADED =>
              top_branch.then_end := to_integer(stack_buffer(15 downto 0));
              top_branch.else_start := to_integer(stack_buffer(31 downto 16));
              top_branch.finish := to_integer(stack_buffer(47 downto 32));
              top_branch.fragments := to_integer(stack_buffer(55 downto 48));
              top_branch.depth := to_integer(stack_buffer(61 downto 56));
              top_branch.in_else := stack_buffer(62) = '1'; state := branch_return;
            when IDLE =>
              if start = '1' then
                input_base := source; output_base := destination;
                name_base := names; input_size := to_integer(source_length); original_size := input_size;
                capacity := to_integer(output_capacity); origin_row := formula_row; origin_column := formula_column;
                decimal_mark := decimal_separator; argument_mark := argument_separator;
                number_decimal_separator <= decimal_separator;
                position := 0; used := 0; compiled_size := 0; host_count := 0;
                frame_count := 0; operator_count := 0; branch_count := 0;
                fragment_count := 0; value_depth := 0; range_pending := false;
                expected_operand := true; validating := false; cancelling := false; token_start := 0;
                cache_valid := false; busy <= '1'; error <= CODEC_OK;
                error_position <= (others => '0'); result_length <= (others => '0');
                host_calls <= (others => '0');
                wide_address := resize(source, 29) + input_size;
                if wide_address > to_unsigned(16#10000000#, 29) then fail(CODEC_MEMORY, 0);
                else
                  wide_address := resize(destination, 29) + capacity;
                  if wide_address > to_unsigned(16#10000000#, 29) then fail(CODEC_MEMORY, 0);
                  elsif decimal_separator = argument_separator or codec_word(argument_separator) or
                    codec_digit(decimal_separator) then fail(CODEC_SYNTAX, 0);
                  elsif decompile = '1' then state := DECODE_NEXT;
                  else fetch(PARSE_NEXT); end if;
                end if;
              end if;
            when FINISH =>
              ram_valid <= '0'; busy <= '0'; done <= '1';
              host_calls <= to_unsigned(host_count, 8); cancelling := false; state := IDLE;
            when MEMORY_SETUP =>
              access_address := access_base + resize(access_offset, 28);
              temporary := to_integer(access_address(2 downto 0));
              if not access_write and cache_valid and cache_tag = access_address(27 downto 3) then
                read_byte_value := cache_data(temporary * 8 + 7 downto temporary * 8); state := memory_return;
              else
                ram_address <= access_address(27 downto 3) & "000";
                ram_valid <= '1'; state := MEMORY_WAIT;
                if access_write then
                  access_word := (others => '0'); access_enables := (others => '0');
                  access_word(temporary * 8 + 7 downto temporary * 8) := access_byte;
                  access_enables(temporary) := '1';
                  ram_write <= '1'; ram_wdata <= access_word; ram_byte_enable <= access_enables;
                else ram_write <= '0'; ram_byte_enable <= (others => '0'); end if;
              end if;
            when MEMORY_WAIT =>
              if ram_ready = '1' then
                ram_valid <= '0';
                if ram_error = '1' then cache_valid := false; fail(CODEC_MEMORY, position);
                else
                  temporary := to_integer(access_address(2 downto 0));
                  if access_write then
                    if cache_valid and cache_tag = access_address(27 downto 3) then
                      cache_data(temporary * 8 + 7 downto temporary * 8) := access_byte;
                    end if;
                  else
                    cache_valid := true; cache_tag := access_address(27 downto 3); cache_data := ram_rdata;
                    read_byte_value := ram_rdata(temporary * 8 + 7 downto temporary * 8);
                  end if;
                  state := memory_return;
                end if;
              end if;
            when FETCH =>
              if position = input_size then character_byte := x"00"; state := fetch_return;
              else read_memory(input_base, IMMEDIATE_DONE, position); end if;
            when IMMEDIATE_DONE =>
              if read_byte_value = 0 then fail(CODEC_SYNTAX, position);
              else character_byte := read_byte_value; state := fetch_return; end if;
            when OUTPUT_NEXT =>
              if stage_index = stage_size then state := output_return;
              elsif used >= capacity then fail(CODEC_CAPACITY, position);
              else write_memory(used, stage(stage_index), OUTPUT_DONE); end if;
            when OUTPUT_DONE => used := used + 1; stage_index := stage_index + 1; state := OUTPUT_NEXT;
            when PATCH_NEXT =>
              if stage_index = stage_size then state := patch_return;
              else write_memory(patch_address + stage_index, stage(stage_index), PATCH_DONE); end if;
            when PATCH_DONE => stage_index := stage_index + 1; state := PATCH_NEXT;
            when SHIFT_READ =>
              if shift_index = shift_at then used := used + shift_size; state := shift_return;
              else read_memory(output_base, SHIFT_WRITE, shift_index - 1); end if;
            when SHIFT_WRITE => write_memory(shift_index - 1 + shift_size, read_byte_value, SHIFT_DONE);
            when SHIFT_DONE => shift_index := shift_index - 1; state := SHIFT_READ;
            when COPY_READ =>
              if copy_index = copy_size then state := copy_return;
              else read_memory(copy_source, COPY_WRITE, copy_index); end if;
            when COPY_WRITE => write_memory(copy_destination + copy_index, read_byte_value, COPY_DONE);
            when COPY_DONE => copy_index := copy_index + 1; state := COPY_READ;
            when PARSE_NEXT =>
              if codec_space(character_byte) then advance(PARSE_NEXT);
              elsif range_pending then
                if codec_letter(character_byte) or character_byte = 36 then begin_word;
                else fail(CODEC_BAD_REFERENCE, position); end if;
              elsif expected_operand then
                if character_byte = 40 then token_start := position; push_frame(false, 0);
                elsif character_byte = 43 then advance(PARSE_NEXT);
                elsif character_byte = 45 then
                  if operator_count = operator_limit then fail(CODEC_DEPTH, position);
                  else
                    pending_position := position; advance(PARSE_NEXT);
                    push_operator(x"15", pending_position, FETCH);
                  end if;
                elsif codec_digit(character_byte) or character_byte = decimal_mark then
                  token_start := position; number_previous := x"00"; number_negate := false;
                  state := NUMBER_SCAN;
                  temporary := 0;
                  if frame_count > 0 then temporary := top_frame.operators; end if;
                  if operator_count > temporary then
                    if top_operator.opcode = x"15" then
                      pop_operator(NUMBER_SCAN); number_negate := true;
                    end if;
                  end if;
                elsif character_byte = 34 then
                  text_start := position + 1; text_length := 0; advance(STRING_SCAN);
                elsif codec_letter(character_byte) or character_byte = 36 or character_byte = 95 then begin_word;
                elsif character_byte = 41 and frame_count > 0 then
                  if top_frame.is_function and top_frame.arguments = 0 and
                    used = top_frame.argument_start and
                    operator_count = top_frame.operators then state := CLOSE_FRAME;
                  else fail(CODEC_SYNTAX, position); end if;
                else fail(CODEC_SYNTAX, position); end if;
              elsif character_byte = 0 then
                if frame_count /= 0 then fail(CODEC_SYNTAX, top_frame.position);
                else flush_base := 0; flush_return := COMPILE_END; state := FLUSH_OPERATORS; end if;
              elsif character_byte = argument_mark or character_byte = 41 then
                if frame_count = 0 then fail(CODEC_SYNTAX, position);
                else
                  close_argument := character_byte = 41;
                  if not close_argument and not top_frame.is_function then fail(CODEC_SYNTAX, position);
                  else
                    flush_base := top_frame.operators;
                    flush_return := ARGUMENT_READY; state := FLUSH_OPERATORS;
                  end if;
                end if;
              elsif character_byte = 37 then advance(PARSE_NEXT); emit_one(x"16", FETCH);
                fetch_return := PARSE_NEXT;
              else
                pending_position := position; first_operator := character_byte;
                case to_integer(character_byte) is
                  when 43 => pending_operator := x"10";
                  when 45 => pending_operator := x"11";
                  when 42 => pending_operator := x"12";
                  when 47 => pending_operator := x"13";
                  when 94 => pending_operator := x"14";
                  when 38 => pending_operator := x"17";
                  when 61 => pending_operator := x"18";
                  when 60 => pending_operator := x"1A";
                  when 62 => pending_operator := x"1C";
                  when others => pending_operator := x"00";
                end case;
                if pending_operator = 0 then fail(CODEC_SYNTAX, position);
                else advance(SECOND_OPERATOR); end if;
              end if;
            when SECOND_OPERATOR =>
              if first_operator = 60 and character_byte = 61 then pending_operator := x"1B"; advance(PUSH_OPERATOR);
              elsif first_operator = 60 and character_byte = 62 then pending_operator := x"19"; advance(PUSH_OPERATOR);
              elsif first_operator = 62 and character_byte = 61 then pending_operator := x"1D"; advance(PUSH_OPERATOR);
              else state := PUSH_OPERATOR; end if;
            when PUSH_OPERATOR =>
              flush_base := 0;
              if frame_count > 0 then flush_base := top_frame.operators; end if;
              if operator_count > flush_base then
                if codec_precedence(top_operator.opcode) > codec_precedence(pending_operator) or
                  (codec_precedence(top_operator.opcode) = codec_precedence(pending_operator)
                   and pending_operator /= x"14") then
                  emit_one(top_operator.opcode, PUSH_OPERATOR); pop_operator(OUTPUT_NEXT);
                elsif operator_count = operator_limit then fail(CODEC_DEPTH, pending_position);
                else
                  push_operator(pending_operator, pending_position, PARSE_NEXT);
                  expected_operand := true;
                end if;
              elsif operator_count = operator_limit then fail(CODEC_DEPTH, pending_position);
              else
                push_operator(pending_operator, pending_position, PARSE_NEXT);
                expected_operand := true;
              end if;
            when FLUSH_OPERATORS =>
              if operator_count = flush_base then state := flush_return;
              else emit_one(top_operator.opcode, FLUSH_OPERATORS); pop_operator(OUTPUT_NEXT); end if;
            when WORD_SCAN =>
              if codec_word(character_byte) then
                if word_phase = 0 and character_byte = 36 then column_absolute := '1'; word_phase := 1;
                elsif (word_phase = 0 or word_phase = 1) and codec_letter(character_byte) then
                  word_phase := 1;
                  temporary := to_integer(shift_left(to_unsigned(column_number, 32), 4) +
                    shift_left(to_unsigned(column_number, 32), 3) + shift_left(to_unsigned(column_number, 32), 1)) +
                    to_integer(codec_upper(character_byte)) - 64;
                  if temporary > 16777216 then word_phase := 4; else column_number := temporary; end if;
                elsif word_phase = 1 and character_byte = 36 and column_number /= 0 then
                  row_absolute := '1'; word_phase := 2;
                elsif (word_phase = 1 or word_phase = 2 or word_phase = 3) and codec_digit(character_byte) then
                  word_phase := 3;
                  temporary := to_integer(shift_left(to_unsigned(row_number, 32), 3) +
                    shift_left(to_unsigned(row_number, 32), 1)) + to_integer(character_byte) - 48;
                  if temporary > 1048576 then word_phase := 4; else row_number := temporary; end if;
                else word_phase := 4; end if;
                advance(WORD_SCAN);
              else token_end := position; state := WORD_END; end if;
            when WORD_END =>
              if codec_space(character_byte) then advance(WORD_END);
              elsif character_byte = 40 and not range_pending then lookup(0, true, LOOKUP_COMPILE);
              elsif word_phase /= 3 or column_number = 0 or row_number = 0 then fail(CODEC_BAD_REFERENCE, token_start);
              else
                reference_value := (others => '0'); reference_value(47) := row_absolute;
                reference_value(46) := column_absolute;
                reference_value(43 downto 24) := to_unsigned(row_number - 1, 20);
                reference_value(23 downto 0) := to_unsigned(column_number - 1, 24);
                if row_absolute = '0' then reference_value(43 downto 24) := reference_value(43 downto 24) - origin_row; end if;
                if column_absolute = '0' then reference_value(23 downto 0) := reference_value(23 downto 0) - origin_column; end if;
                expected_operand := false;
                if range_pending then range_pending := false; emit_one(x"08", EMIT_RANGE_FIRST);
                elsif character_byte = 58 then first_reference := reference_value; range_pending := true; advance(PARSE_NEXT);
                else emit_reference_return := PARSE_NEXT; state := EMIT_REFERENCE; end if;
              end if;
            when EMIT_RANGE_FIRST =>
              wide_reference := reference_value; reference_value := first_reference; first_reference := wide_reference;
              state := EMIT_REFERENCE; emit_reference_return := EMIT_RANGE_SECOND;
            when EMIT_RANGE_SECOND => reference_value := first_reference; emit_reference_return := PARSE_NEXT; state := EMIT_REFERENCE;
            when EMIT_REFERENCE =>
              if codec_short(reference_value) then
                short_word := (others => '0'); short_word(31) := '1';
                short_word(30) := reference_value(47); short_word(14) := reference_value(46);
                short_word(29 downto 15) := reference_value(38 downto 24);
                short_word(13 downto 0) := reference_value(13 downto 0);
                for byte_index in 0 to 3 loop stage(byte_index) := short_word(31 - byte_index * 8 downto 24 - byte_index * 8); end loop;
                stage_size := 4;
              else
                stage(0) := x"07";
                for byte_index in 0 to 5 loop stage(byte_index + 1) := reference_value(47 - byte_index * 8 downto 40 - byte_index * 8); end loop;
                stage_size := 7;
              end if;
              emit(stage_size, emit_reference_return);
            when NUMBER_SCAN =>
              if codec_digit(character_byte) or character_byte = decimal_mark or character_byte = 69 or character_byte = 101 or
                ((character_byte = 43 or character_byte = 45) and (number_previous = 69 or number_previous = 101)) then
                number_previous := character_byte; advance(NUMBER_SCAN);
              else
                number_start <= '1'; number_format <= '0';
                if number_negate then number_negative <= '1'; else number_negative <= '0'; end if;
                number_source <= input_base + token_start; number_length <= to_unsigned(position - token_start, 16);
                state := NUMBER_WAIT;
              end if;
            when NUMBER_WAIT =>
              if number_done = '1' then
                if number_error = CODEC_MEMORY or number_error = CODEC_ABORTED or number_error = CODEC_CAPACITY then
                  fail(number_error, token_start + to_integer(number_error_position));
                elsif number_error /= CODEC_OK then fail(CODEC_NUMBER, token_start + to_integer(number_error_position));
                else
                  stage_cursor := 0;
                  if number_result_kind = '1' then stage(0) := x"04"; temporary := 8;
                  else
                    signed_value := signed(number_result_value);
                    if signed_value >= -128 and signed_value <= 127 then stage(0) := x"01"; temporary := 1;
                    elsif signed_value = resize(signed(number_result_value(31 downto 0)), 64) then stage(0) := x"02"; temporary := 4;
                    else stage(0) := x"03"; temporary := 8; end if;
                  end if;
                  for byte_index in 0 to 7 loop
                    stage(byte_index + 1) := number_result_value(byte_index * 8 + 7 downto byte_index * 8);
                  end loop;
                  stage_cursor := temporary + 1;
                  if number_result_kind = '0' and number_result_scale /= 0 then
                    stage(stage_cursor) := x"06"; stage(stage_cursor + 1) := number_result_scale;
                    stage_cursor := stage_cursor + 2;
                  end if;
                  expected_operand := false; emit(stage_cursor, PARSE_NEXT);
                end if;
              end if;
            when STRING_SCAN =>
              if position = input_size then fail(CODEC_SYNTAX, text_start - 1);
              elsif character_byte = 34 then advance(STRING_QUOTE);
              elsif text_length = 32767 then fail(CODEC_CAPACITY, position);
              else text_length := text_length + 1; advance(STRING_SCAN); end if;
            when STRING_QUOTE =>
              if character_byte = 34 then
                if text_length = 32767 then fail(CODEC_CAPACITY, position);
                else text_length := text_length + 1; advance(STRING_SCAN); end if;
              else
                stage(0) := x"05"; stage_cursor := 1; append_count(text_length, stage_cursor);
                text_cursor := text_start; emit(stage_cursor, STRING_COPY);
              end if;
            when STRING_COPY =>
              if text_length = 0 then expected_operand := false; state := PARSE_NEXT;
              else read_memory(input_base, STRING_BYTE, text_cursor); end if;
            when STRING_BYTE =>
              if read_byte_value = 34 then text_cursor := text_cursor + 2; else text_cursor := text_cursor + 1; end if;
              text_length := text_length - 1; emit_one(read_byte_value, STRING_COPY);
            when LOOKUP_FIRST =>
              lookup_identifier := to_integer(read_byte_value(6 downto 0));
              if read_byte_value(7) = '1' then next_table(LOOKUP_SECOND);
              else lookup_index := 0; lookup_equal := true; lookup_name := lookup_cursor + 1; next_table(LOOKUP_CHAR); end if;
            when LOOKUP_SECOND =>
              lookup_identifier := lookup_identifier + to_integer(read_byte_value) * 128;
              lookup_index := 0; lookup_equal := true; lookup_name := lookup_cursor + 1; next_table(LOOKUP_CHAR);
            when LOOKUP_CHAR =>
              if read_byte_value = 0 then
                if lookup_index = 0 then fail(CODEC_NAME, token_start);
                elsif (lookup_by_name and lookup_equal and lookup_index = token_end - token_start) or
                  (not lookup_by_name and lookup_identifier = wanted_identifier) then
                  lookup_length := lookup_index; state := lookup_return;
                else next_table(LOOKUP_FIRST); end if;
              elsif lookup_by_name and lookup_index < token_end - token_start then
                lookup_character := read_byte_value;
                read_memory(input_base, LOOKUP_COMPARE, token_start + lookup_index);
              else lookup_index := lookup_index + 1; next_table(LOOKUP_CHAR); end if;
            when LOOKUP_COMPARE =>
              if codec_upper(read_byte_value) /= codec_upper(lookup_character) then lookup_equal := false; end if;
              lookup_index := lookup_index + 1; next_table(LOOKUP_CHAR);
            when LOOKUP_COMPILE =>
              if lookup_identifier >= 16384 then
                text_start := token_start; host_depth := 1; advance(HOST_SCAN);
              else push_frame(true, lookup_identifier); end if;
            when HOST_SCAN =>
              if position = input_size then fail(CODEC_SYNTAX, text_start);
              elsif character_byte = 34 then advance(HOST_QUOTE);
              elsif character_byte = 40 then
                if host_depth = nesting_limit then fail(CODEC_DEPTH, position);
                else host_depth := host_depth + 1; advance(HOST_SCAN); end if;
              elsif character_byte = 41 then
                host_depth := host_depth - 1;
                if host_depth = 0 then
                  text_length := position + 1 - text_start;
                  if text_length > 32767 or host_count = 255 then fail(CODEC_CAPACITY, position);
                  else
                    host_count := host_count + 1; advance(HOST_PREFIX);
                  end if;
                else advance(HOST_SCAN); end if;
              else advance(HOST_SCAN); end if;
            when HOST_QUOTE =>
              if position = input_size then fail(CODEC_SYNTAX, text_start);
              elsif character_byte = 34 then advance(HOST_SCAN);
              else advance(HOST_QUOTE); end if;
            when HOST_PREFIX =>
              stage(0) := x"09"; stage_cursor := 1; append_count(text_length, stage_cursor);
              emit(stage_cursor, HOST_PAYLOAD);
            when HOST_PAYLOAD => copy_bytes(input_base + text_start, used, text_length, HOST_RESULT);
            when HOST_RESULT =>
              used := used + text_length; stage(0) := x"CF";
              for byte_index in 1 to 5 loop stage(byte_index) := x"FF"; end loop;
              expected_operand := false; emit(6, PARSE_NEXT);
            when ARGUMENT_READY =>
              if not top_frame.is_function then state := CLOSE_FRAME;
              else
                pure_argument := false; argument_bytes := used - top_frame.argument_start;
                if top_frame.identifier <= 6 and (argument_bytes = 4 or argument_bytes = 7) then
                  read_memory(output_base, ARGUMENT_CLASSIFY, top_frame.argument_start);
                else state := ARGUMENT_APPLY; end if;
              end if;
            when ARGUMENT_CLASSIFY =>
              pure_argument := (argument_bytes = 4 and read_byte_value(7) = '1') or
                (argument_bytes = 7 and read_byte_value = x"07");
              state := ARGUMENT_APPLY;
            when ARGUMENT_APPLY =>
              if top_frame.arguments = 32767 then fail(CODEC_BAD_ARITY, position);
              else
                top_frame.arguments := top_frame.arguments + 1;
                if pure_argument then
                  if top_frame.list_active then
                    top_frame.list_count := top_frame.list_count + 1;
                    if top_frame.list_count = 128 then
                      insert_space(top_frame.list_start + 2, 1, LIST_PATCH);
                    else state := LIST_PATCH; end if;
                  else
                    top_frame.values := top_frame.values + 1;
                    top_frame.list_active := true; top_frame.list_count := 1;
                    top_frame.list_start := top_frame.argument_start;
                    insert_space(top_frame.argument_start, 2, LIST_PATCH);
                  end if;
                else
                  top_frame.list_active := false;
                  top_frame.values := top_frame.values + 1;
                  state := ARGUMENT_AFTER;
                end if;
              end if;
            when LIST_PATCH =>
              stage(0) := x"0D"; stage_cursor := 1;
              append_count(top_frame.list_count, stage_cursor);
              patch(top_frame.list_start, stage_cursor, ARGUMENT_AFTER);
            when ARGUMENT_AFTER =>
              if top_frame.identifier = 17 then
                case top_frame.arguments is
                  when 1 =>
                    if close_argument then fail(CODEC_BAD_ARITY, position);
                    else
                      top_frame.jz_slot := used;
                      stage(0) := x"0A"; stage(1) := x"00"; stage(2) := x"00"; emit(3, IF_JZ_DONE);
                    end if;
                  when 2 =>
                    top_frame.jump_slot := used;
                    stage(0) := x"0B"; stage(1) := x"00"; stage(2) := x"00"; emit(3, IF_JMP_DONE);
                  when 3 =>
                    if not close_argument then fail(CODEC_BAD_ARITY, position);
                    else patch_jump(top_frame.jump_slot, IF_CLOSED); end if;
                  when others => fail(CODEC_BAD_ARITY, position);
                end case;
              elsif close_argument then state := CLOSE_FRAME;
              else
                top_frame.argument_start := used; expected_operand := true; advance(PARSE_NEXT);
              end if;
            when IF_JZ_DONE =>
              top_frame.argument_start := used; expected_operand := true; advance(PARSE_NEXT);
            when IF_JMP_DONE => patch_jump(top_frame.jz_slot, IF_JZ_PATCHED);
            when IF_JZ_PATCHED =>
              if close_argument then stage(0) := x"01"; stage(1) := x"00"; emit(2, IF_DEFAULT_DONE);
              else top_frame.argument_start := used; expected_operand := true; advance(PARSE_NEXT); end if;
            when IF_DEFAULT_DONE => patch_jump(top_frame.jump_slot, IF_CLOSED);
            when IF_CLOSED => expected_operand := false; advance(PARSE_NEXT); pop_frame(FETCH);
            when CLOSE_FRAME =>
              if top_frame.is_function then
                if not codec_arity(top_frame.identifier, top_frame.arguments) then fail(CODEC_BAD_ARITY, position);
                else
                  stage(0) := x"0C"; stage_cursor := 1;
                  append_count(top_frame.identifier, stage_cursor);
                  append_count(top_frame.values, stage_cursor);
                  expected_operand := false;
                  advance(PARSE_NEXT); emit(stage_cursor, FETCH); fetch_return := PARSE_NEXT;
                  pop_frame(OUTPUT_NEXT);
                end if;
              else expected_operand := false; advance(PARSE_NEXT); pop_frame(FETCH); end if;
            when COMPILE_END => emit_one(x"00", COMPILE_VALIDATE);
            when COMPILE_VALIDATE =>
              compiled_size := used; input_base := output_base; input_size := used; position := 0;
              validating := true; value_depth := 0; branch_count := 0; state := DECODE_NEXT;
            when DECODE_NEXT =>
              if branch_count > 0 and position = top_branch.then_end and
                not top_branch.in_else then
                if value_depth /= top_branch.depth + 1 then fail(CODEC_BYTECODE, position);
                else
                  top_branch.in_else := true;
                  value_depth := top_branch.depth;
                  position := top_branch.else_start;
                end if;
              elsif branch_count > 0 and position = top_branch.finish and
                top_branch.in_else then
                if value_depth /= top_branch.depth + 1 then fail(CODEC_BYTECODE, position);
                else
                  combine_count := 3; combine_call := true; decoded_function := 17;
                  if fragment_count /= top_branch.fragments + 2 then fail(CODEC_BYTECODE, position);
                  else state := COMBINE_START; end if;
                  if state /= FINISH then
                    branch_count := branch_count - 1;
                    if branch_count > 0 then
                      branch_return := state; load_stack(branch_base + (branch_count - 1) * 2, 2, BRANCH_LOADED);
                    end if;
                  end if;
                end if;
              elsif branch_count > 0 and
                ((not top_branch.in_else and position > top_branch.then_end) or
                 (top_branch.in_else and position > top_branch.finish)) then
                fail(CODEC_BYTECODE, position);
              else read_input(DECODE_OPCODE); end if;
            when DECODE_OPCODE =>
              opcode := read_byte_value;
              if opcode(7) = '1' then
                reference_return := REFERENCE_DONE; decoded_reference_bytes := 3;
                decoded_reference_index := 0; short_word := resize(opcode, 32); state := REFERENCE_BYTE;
                push_value;
              else
                case to_integer(opcode) is
                  when 0 =>
                    if value_depth /= 1 or branch_count /= 0 or position /= input_size then fail(CODEC_BYTECODE, position - 1);
                    else
                      if validating then result_length <= to_unsigned(compiled_size, 16);
                      else result_length <= to_unsigned(used, 16); end if;
                      state := FINISH;
                    end if;
                  when 1 to 4 =>
                    push_value;
                    if state /= FINISH then
                      case to_integer(opcode) is
                        when 1 => temporary := 1;
                        when 2 => temporary := 4;
                        when others => temporary := 8;
                      end case;
                      read_immediate(temporary, DECODE_LITERAL);
                    end if;
                  when 5 | 9 | 13 => read_count(DECODE_COUNT);
                  when 7 =>
                    push_value;
                    if state /= FINISH then
                      reference_return := REFERENCE_DONE; decoded_reference_bytes := 6;
                      decoded_reference_index := 0; reference_value := (others => '0'); state := REFERENCE_BYTE;
                    end if;
                  when 8 =>
                    push_value;
                    if state /= FINISH then decode_reference(DECODE_RECT_SECOND); end if;
                  when 10 => read_immediate(2, DECODE_JZ);
                  when 12 => read_count(DECODE_FUNCTION_COUNT);
                  when 16 to 29 =>
                    combine_call := false; combine_opcode := opcode;
                    if opcode = x"15" or opcode = x"16" then combine_count := 1; else combine_count := 2; end if;
                    if value_depth < combine_count then fail(CODEC_BYTECODE, position - 1);
                    else
                      value_depth := value_depth - combine_count + 1;
                      state := COMBINE_START;
                    end if;
                  when others => fail(CODEC_BYTECODE, position - 1);
                end case;
              end if;
            when IMMEDIATE_READ =>
              if immediate_index = immediate_size then state := immediate_return;
              else read_input(IMMEDIATE_BYTE); end if;
            when IMMEDIATE_BYTE =>
              immediate(immediate_index * 8 + 7 downto immediate_index * 8) := read_byte_value;
              immediate_index := immediate_index + 1; state := IMMEDIATE_READ;
            when COUNT_FIRST =>
              count_value := to_integer(read_byte_value(6 downto 0));
              if read_byte_value(7) = '1' then read_input(COUNT_SECOND); else state := count_return; end if;
            when COUNT_SECOND => count_value := count_value + to_integer(read_byte_value) * 128; state := count_return;
            when DECODE_COUNT =>
              decoded_remaining := count_value;
              if opcode = x"0D" then
                decoded_list := true; push_value;
                if state /= FINISH then state := DECODE_LIST_NEXT; end if;
              elsif opcode = x"09" then
                if position + count_value + 6 > input_size then fail(CODEC_BYTECODE, position);
                else
                  push_value;
                  if state /= FINISH then
                    if validating then position := position + count_value + 6; state := DECODE_NEXT;
                    else copy_bytes(input_base + position, used, count_value, DECODE_HOST_FINISH); end if;
                  end if;
                end if;
              else
                push_value;
                if state /= FINISH then
                  if validating then
                    if position + count_value > input_size then fail(CODEC_BYTECODE, position);
                    else position := position + count_value; state := DECODE_NEXT; end if;
                  else emit_one(x"22", DECODE_STRING); end if;
                end if;
              end if;
            when DECODE_HOST_FINISH => used := used + decoded_remaining; position := position + decoded_remaining + 6; state := DECODE_NEXT;
            when DECODE_STRING =>
              if decoded_remaining = 0 then emit_one(x"22", DECODE_NEXT);
              else read_input(DECODE_STRING_BYTE); end if;
            when DECODE_STRING_BYTE =>
              decoded_remaining := decoded_remaining - 1;
              if read_byte_value = x"22" then stage(0) := x"22"; stage(1) := x"22"; emit(2, DECODE_STRING);
              else emit_one(read_byte_value, DECODE_STRING); end if;
            when DECODE_LITERAL =>
              if opcode = x"01" then immediate := unsigned(resize(signed(immediate(7 downto 0)), 64));
              elsif opcode = x"02" then immediate := unsigned(resize(signed(immediate(31 downto 0)), 64)); end if;
              if opcode /= x"04" and position < input_size then read_memory(input_base, DECODE_SCALE, position);
              else read_byte_value := x"00"; state := DECODE_SCALE; end if;
            when DECODE_SCALE =>
              number_scale <= (others => '0');
              if opcode /= x"04" and read_byte_value = x"06" then
                position := position + 1; read_input(DECODE_SCALE_BYTE);
              else state := DECODE_SCALE_BYTE; read_byte_value := x"00"; end if;
            when DECODE_SCALE_BYTE =>
              if validating then state := DECODE_NEXT;
              else
                number_scale <= read_byte_value; number_value <= immediate;
                if opcode = x"04" then number_kind <= '1'; else number_kind <= '0'; end if;
                number_format <= '1'; number_negative <= '0'; number_start <= '1';
                number_destination <= output_base + used;
                number_capacity <= to_unsigned(capacity - used, 16); state := FORMAT_NUMBER_WAIT;
              end if;
            when FORMAT_NUMBER_WAIT =>
              if number_done = '1' then
                cache_valid := false;
                if number_error = CODEC_CAPACITY or number_error = CODEC_MEMORY or number_error = CODEC_ABORTED then
                  fail(number_error, position);
                elsif number_error /= CODEC_OK then fail(CODEC_NUMBER, position);
                elsif to_integer(number_result_length) > capacity - used then fail(CODEC_CAPACITY, position);
                else used := used + to_integer(number_result_length); state := DECODE_NEXT; end if;
              end if;
            when DECODE_REFERENCE =>
              decoded_reference_index := 0;
              if read_byte_value(7) = '1' then decoded_reference_bytes := 3; short_word := resize(read_byte_value, 32);
              elsif read_byte_value = x"07" then decoded_reference_bytes := 6; reference_value := (others => '0');
              else fail(CODEC_BYTECODE, position - 1); end if;
              if state /= FINISH then state := REFERENCE_BYTE; end if;
            when REFERENCE_BYTE =>
              if decoded_reference_index = decoded_reference_bytes then state := REFERENCE_DONE;
              else read_input(REFERENCE_DONE); end if;
            when REFERENCE_DONE =>
              if decoded_reference_index < decoded_reference_bytes then
                if decoded_reference_bytes = 3 then short_word := shift_left(short_word, 8) or resize(read_byte_value, 32);
                else reference_value := shift_left(reference_value, 8) or resize(read_byte_value, 48); end if;
                decoded_reference_index := decoded_reference_index + 1; state := REFERENCE_BYTE;
              else
                if decoded_reference_bytes = 3 then
                  reference_value := (others => '0'); reference_value(47) := short_word(30); reference_value(46) := short_word(14);
                  if short_word(30) = '1' then reference_value(43 downto 24) := resize(short_word(29 downto 15), 20);
                  else reference_value(43 downto 24) := unsigned(resize(signed(short_word(29 downto 15)), 20)); end if;
                  if short_word(14) = '1' then reference_value(23 downto 0) := resize(short_word(13 downto 0), 24);
                  else reference_value(23 downto 0) := unsigned(resize(signed(short_word(13 downto 0)), 24)); end if;
                elsif reference_value(45 downto 44) /= 0 then fail(CODEC_BYTECODE, position); end if;
                if state /= FINISH then
                  if validating then state := reference_return; if reference_return = REFERENCE_DONE then state := DECODE_NEXT; end if;
                  else
                    reference_row_value := reference_value(43 downto 24);
                    reference_column_value := reference_value(23 downto 0);
                    if reference_value(47) = '0' then reference_row_value := reference_row_value + origin_row; end if;
                    if reference_value(46) = '0' then reference_column_value := reference_column_value + origin_column; end if;
                    digit_count := 0;
                    if reference_value(46) = '1' then emit_one(x"24", REFERENCE_COLUMN); else state := REFERENCE_COLUMN; end if;
                  end if;
                end if;
              end if;
            when REFERENCE_COLUMN => start_divide(resize(reference_column_value, 32), 26, COLUMN_DIGIT);
            when DIVIDE_STEP =>
              remainder_value := shift_left(remainder_value, 1); remainder_value(0) := dividend(31);
              dividend := shift_left(dividend, 1); quotient := shift_left(quotient, 1);
              if remainder_value >= divisor then remainder_value := remainder_value - divisor; quotient(0) := '1'; end if;
              divide_bits := divide_bits - 1;
              if divide_bits = 0 then state := divide_return; end if;
            when COLUMN_DIGIT =>
              digits(digit_count) := to_unsigned(65 + to_integer(remainder_value), 8); digit_count := digit_count + 1;
              if quotient = 0 then digit_index := digit_count; state := REFERENCE_COLUMN_OUT;
              else start_divide(quotient - 1, 26, COLUMN_DIGIT); end if;
            when REFERENCE_COLUMN_OUT =>
              if digit_index = 0 then digit_count := 0;
                if reference_value(47) = '1' then emit_one(x"24", REFERENCE_ROW); else state := REFERENCE_ROW; end if;
              else digit_index := digit_index - 1; emit_one(digits(digit_index), REFERENCE_COLUMN_OUT); end if;
            when REFERENCE_ROW => start_divide(resize(reference_row_value, 32) + 1, 10, ROW_DIGIT);
            when ROW_DIGIT =>
              digits(digit_count) := to_unsigned(48 + to_integer(remainder_value), 8); digit_count := digit_count + 1;
              if quotient = 0 then digit_index := digit_count; state := REFERENCE_ROW_OUT;
              else start_divide(quotient, 10, ROW_DIGIT); end if;
            when REFERENCE_ROW_OUT =>
              if digit_index = 0 then state := REFERENCE_FINISH;
              else digit_index := digit_index - 1; emit_one(digits(digit_index), REFERENCE_ROW_OUT); end if;
            when REFERENCE_FINISH =>
              if reference_return = REFERENCE_DONE then state := DECODE_NEXT; else state := reference_return; end if;
            when DECODE_RECT_SECOND =>
              if opcode = x"08" then
                opcode := x"FF";
                if validating then decode_reference(REFERENCE_DONE);
                else emit_one(x"3A", DECODE_LIST_REF); end if;
              else state := DECODE_NEXT; end if;
            when DECODE_LIST_REF =>
              if opcode = x"0D" then decode_reference(DECODE_LIST_NEXT);
              else decode_reference(REFERENCE_DONE); end if;
            when DECODE_LIST_NEXT =>
              if decoded_remaining = 0 then state := DECODE_NEXT;
              else
                decoded_remaining := decoded_remaining - 1;
                if decoded_list then decoded_list := false; decode_reference(DECODE_LIST_NEXT);
                elsif validating then decode_reference(DECODE_LIST_NEXT);
                else emit_one(argument_mark, DECODE_LIST_REF); end if;
              end if;
            when DECODE_FUNCTION_COUNT => decoded_function := count_value; read_count(DECODE_FUNCTION);
            when DECODE_FUNCTION =>
              if value_depth < count_value or not codec_arity(decoded_function, count_value) then fail(CODEC_BYTECODE, position);
              elsif value_depth - count_value = value_limit then fail(CODEC_DEPTH, position);
              else
                value_depth := value_depth - count_value + 1;
                combine_count := count_value; combine_call := true; state := COMBINE_START;
              end if;
            when DECODE_JZ =>
              temporary := position + to_integer(immediate(15 downto 0));
              if value_depth = 0 or temporary < position + 3 or temporary > input_size or branch_count = nesting_limit then
                fail(CODEC_BYTECODE, position);
              else jump_else := temporary; jump_probe := jump_else - 3; read_memory(input_base, DECODE_JMP_BYTE, jump_probe); end if;
            when DECODE_JMP_BYTE =>
              if read_byte_value /= x"0B" then fail(CODEC_BYTECODE, jump_probe);
              else read_memory(input_base, DECODE_JMP_OFFSET, jump_probe + 1); end if;
            when DECODE_JMP_OFFSET => temporary := to_integer(read_byte_value); jump_end := temporary; read_memory(input_base, DECODE_JMP_HIGH, jump_probe + 2);
            when DECODE_JMP_HIGH =>
              temporary := jump_else + jump_end + to_integer(read_byte_value) * 256;
              if temporary > input_size or temporary <= jump_else then fail(CODEC_BYTECODE, jump_probe);
              else
                jump_end := temporary;
                value_depth := value_depth - 1;
                if branch_count > 0 then
                  stack_buffer := (others => '0');
                  stack_buffer(15 downto 0) := to_unsigned(top_branch.then_end, 16);
                  stack_buffer(31 downto 16) := to_unsigned(top_branch.else_start, 16);
                  stack_buffer(47 downto 32) := to_unsigned(top_branch.finish, 16);
                  stack_buffer(55 downto 48) := to_unsigned(top_branch.fragments, 8);
                  stack_buffer(61 downto 56) := to_unsigned(top_branch.depth, 6);
                  if top_branch.in_else then stack_buffer(62) := '1'; end if;
                end if;
                top_branch.then_end := jump_probe; top_branch.else_start := jump_else;
                top_branch.finish := jump_end; top_branch.depth := value_depth;
                top_branch.fragments := fragment_count;
                top_branch.in_else := false; branch_count := branch_count + 1; state := DECODE_NEXT;
                if branch_count > 1 then save_stack(branch_base + (branch_count - 2) * 2, 2, DECODE_NEXT); end if;
              end if;
            when COMBINE_START =>
              if combine_count > fragment_count then fail(CODEC_BYTECODE, position);
              else
                combine_base := fragment_count - combine_count;
                if combine_count = 0 then
                  if fragment_count = fragment_limit then fail(CODEC_DEPTH, position);
                  else
                    write_fragment(fragment_count, used, 0); fragment_count := fragment_count + 1;
                    combine_start_position := used; combine_depth := 0; state := COMBINE_DEPTH_DONE;
                  end if;
                else
                  load_stack(fragment_base + combine_base, 1, COMBINE_BASE_LOADED);
                end if;
              end if;
            when COMBINE_BASE_LOADED =>
              combine_start_position := to_integer(stack_buffer(15 downto 0));
              combine_depth := to_integer(stack_buffer(30 downto 16));
              combine_depth_index := combine_base + 1; state := COMBINE_DEPTH_SCAN;
            when COMBINE_DEPTH_SCAN =>
              if combine_depth_index = fragment_count then state := COMBINE_DEPTH_DONE;
              else load_stack(fragment_base + combine_depth_index, 1, COMBINE_DEPTH_LOADED); end if;
            when COMBINE_DEPTH_LOADED =>
              temporary := to_integer(stack_buffer(30 downto 16));
              if temporary > combine_depth then combine_depth := temporary; end if;
              combine_depth_index := combine_depth_index + 1; state := COMBINE_DEPTH_SCAN;
            when COMBINE_DEPTH_DONE =>
              if not combine_call and combine_opcode = x"15" then combine_depth := combine_depth + 2;
              else combine_depth := combine_depth + 1; end if;
              if combine_depth > nesting_limit then fail(CODEC_DEPTH, position);
              elsif validating then
                write_fragment(combine_base, combine_start_position, combine_depth);
                fragment_count := combine_base + 1; state := DECODE_NEXT;
              else state := COMBINE_READY; end if;
            when COMBINE_READY =>
              if combine_call then
                combine_index := fragment_count - 1; lookup(decoded_function, false, LOOKUP_FORMAT);
              elsif combine_count = 2 then load_stack(fragment_base + combine_base + 1, 1, COMBINE_RIGHT_LOADED);
              else
                if combine_opcode = x"15" then temporary := 3; else temporary := 1; end if;
                insert_space(combine_start_position, temporary, COMBINE_PREFIX_DONE);
              end if;
            when COMBINE_RIGHT_LOADED =>
              combine_right_position := to_integer(stack_buffer(15 downto 0)); temporary := 1;
              if combine_opcode = x"19" or combine_opcode = x"1B" or combine_opcode = x"1D" then temporary := 2; end if;
              insert_space(combine_right_position, temporary, COMBINE_OPERATOR);
            when LOOKUP_FORMAT => state := COMBINE_SEPARATOR;
            when COMBINE_SEPARATOR =>
              if combine_index <= combine_base then insert_space(combine_start_position, lookup_length + 1, COMBINE_PREFIX);
              else load_stack(fragment_base + combine_index, 1, COMBINE_SEPARATOR_LOADED); end if;
            when COMBINE_SEPARATOR_LOADED =>
              combine_separator_position := to_integer(stack_buffer(15 downto 0));
              insert_space(combine_separator_position, 1, COMBINE_SEPARATOR_DONE);
            when COMBINE_SEPARATOR_DONE =>
              stage(0) := argument_mark; patch(combine_separator_position, 1, COMBINE_NAME_DONE);
            when COMBINE_NAME_DONE => combine_index := combine_index - 1; state := COMBINE_SEPARATOR;
            when COMBINE_PREFIX => copy_bytes(lookup_name, combine_start_position, lookup_length, COMBINE_PREFIX_DONE);
            when COMBINE_PREFIX_DONE =>
              if combine_call then stage(0) := x"28"; patch(combine_start_position + lookup_length, 1, COMBINE_END);
              else
                stage(0) := x"28";
                if combine_opcode = x"15" then
                  stage(1) := x"2D"; stage(2) := x"28"; patch(combine_start_position, 3, COMBINE_END);
                else patch(combine_start_position, 1, COMBINE_END); end if;
              end if;
            when COMBINE_OPERATOR =>
              case to_integer(combine_opcode) is
                when 16#10# => stage(0) := x"2B";
                when 16#11# => stage(0) := x"2D";
                when 16#12# => stage(0) := x"2A";
                when 16#13# => stage(0) := x"2F";
                when 16#14# => stage(0) := x"5E";
                when 16#17# => stage(0) := x"26";
                when 16#18# => stage(0) := x"3D";
                when 16#19# | 16#1A# | 16#1B# => stage(0) := x"3C";
                when others => stage(0) := x"3E";
              end case;
              temporary := 1;
              if combine_opcode = x"19" then stage(1) := x"3E"; temporary := 2;
              elsif combine_opcode = x"1B" or combine_opcode = x"1D" then stage(1) := x"3D"; temporary := 2; end if;
              patch(combine_right_position, temporary, COMBINE_OPERATOR_DONE);
            when COMBINE_OPERATOR_DONE => insert_space(combine_start_position, 1, COMBINE_PREFIX_DONE);
            when COMBINE_END =>
              fragment_count := combine_base + 1; write_fragment(combine_base, combine_start_position, combine_depth);
              if not combine_call and combine_opcode = x"16" then stage(0) := x"25"; stage(1) := x"29"; emit(2, DECODE_NEXT);
              elsif not combine_call and combine_opcode = x"15" then stage(0) := x"29"; stage(1) := x"29"; emit(2, DECODE_NEXT);
              else emit_one(x"29", DECODE_NEXT); end if;
            when others => fail(CODEC_BYTECODE, position);
          end case;
        end if;
      end if;
    end if;
  end process;
end architecture;
