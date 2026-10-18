library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use work.shite_codec_pkg.all;

entity tb_shite_codec is
  generic (real_numbers : boolean := false);
end entity;

architecture test of tb_shite_codec is
  signal clock : std_logic := '0';
  signal finished : boolean := false;
  signal reset, start, decompile, abort, busy, done : std_logic := '0';
  signal source, destination, names : unsigned(27 downto 0) := (others => '0');
  signal source_length, output_capacity, error_position, result_length : unsigned(15 downto 0) := (others => '0');
  signal formula_row : unsigned(19 downto 0) := (others => '0');
  signal formula_column : unsigned(23 downto 0) := (others => '0');
  signal decimal_separator : codec_byte := x"2E";
  signal argument_separator : codec_byte := x"2C";
  signal error, host_calls : codec_byte;
  signal ram_valid, ram_write, ram_ready, ram_error : std_logic := '0';
  signal ram_address : unsigned(27 downto 0);
  signal ram_wdata, ram_rdata : unsigned(63 downto 0) := (others => '0');
  signal ram_byte_enable : std_logic_vector(7 downto 0);
  signal number_start, number_format, number_negative, number_kind, number_done : std_logic := '0';
  signal number_source, number_destination : unsigned(27 downto 0);
  signal number_length, number_capacity, number_error_position, number_result_length : unsigned(15 downto 0) := (others => '0');
  signal number_value, number_result_value : unsigned(63 downto 0) := (others => '0');
  signal number_scale, number_decimal_separator, number_error, number_result_scale : codec_byte := (others => '0');
  signal number_result_kind : std_logic := '0';
  signal codec_ram_valid, codec_ram_write, converter_ram_valid, converter_ram_write : std_logic;
  signal codec_ram_address, converter_ram_address : unsigned(27 downto 0);
  signal codec_ram_wdata, converter_ram_wdata : unsigned(63 downto 0);
  signal codec_ram_byte_enable, converter_ram_byte_enable : std_logic_vector(7 downto 0);
  signal numeric_owner, converter_ready, codec_ready : std_logic := '0';
  signal fixture_done, converter_done, converter_kind : std_logic := '0';
  signal fixture_error, fixture_scale, converter_error, converter_scale : codec_byte;
  signal fixture_position, fixture_length, converter_position, converter_length : unsigned(15 downto 0);
  signal fixture_value, converter_value : unsigned(63 downto 0);
  signal fixture_kind : std_logic;
begin
  clock <= not clock after 5 ns when not finished;

  codec : entity work.shite_formula_codec
    port map (
      clock => clock, reset => reset, start => start, decompile => decompile, abort => abort,
      source => source, destination => destination, names => names,
      source_length => source_length, output_capacity => output_capacity,
      formula_row => formula_row, formula_column => formula_column,
      decimal_separator => decimal_separator, argument_separator => argument_separator,
      busy => busy, done => done, error => error, error_position => error_position,
      result_length => result_length, host_calls => host_calls,
      ram_valid => codec_ram_valid, ram_write => codec_ram_write, ram_address => codec_ram_address,
      ram_wdata => codec_ram_wdata, ram_byte_enable => codec_ram_byte_enable,
      ram_ready => codec_ready, ram_error => ram_error, ram_rdata => ram_rdata,
      number_start => number_start, number_format => number_format,
      number_negative => number_negative, number_source => number_source,
      number_destination => number_destination, number_length => number_length,
      number_capacity => number_capacity, number_value => number_value,
      number_kind => number_kind, number_scale => number_scale,
      number_decimal_separator => number_decimal_separator,
      number_done => number_done, number_error => number_error,
      number_error_position => number_error_position, number_result_length => number_result_length,
      number_result_value => number_result_value, number_result_kind => number_result_kind,
      number_result_scale => number_result_scale);

  ram_valid <= converter_ram_valid when numeric_owner = '1' else codec_ram_valid;
  ram_write <= converter_ram_write when numeric_owner = '1' else codec_ram_write;
  ram_address <= converter_ram_address when numeric_owner = '1' else codec_ram_address;
  ram_wdata <= converter_ram_wdata when numeric_owner = '1' else codec_ram_wdata;
  ram_byte_enable <= converter_ram_byte_enable when numeric_owner = '1' else codec_ram_byte_enable;
  codec_ready <= ram_ready when numeric_owner = '0' else '0';
  converter_ready <= ram_ready when numeric_owner = '1' else '0';
  number_done <= converter_done when real_numbers else fixture_done;
  number_error <= converter_error when real_numbers else fixture_error;
  number_error_position <= converter_position when real_numbers else fixture_position;
  number_result_length <= converter_length when real_numbers else fixture_length;
  number_result_value <= converter_value when real_numbers else fixture_value;
  number_result_kind <= converter_kind when real_numbers else fixture_kind;
  number_result_scale <= converter_scale when real_numbers else fixture_scale;

  actual_numbers : if real_numbers generate
    converter : entity work.shite_number_text
      port map (clock => clock, reset => reset, start => number_start, format => number_format,
        negative => number_negative, source => number_source, destination => number_destination,
        input_length => number_length, capacity => number_capacity, value => number_value,
        kind => number_kind, scale => number_scale, decimal_separator => number_decimal_separator,
        busy => open, done => converter_done, error => converter_error,
        error_position => converter_position, result_length => converter_length,
        result_value => converter_value, result_kind => converter_kind, result_scale => converter_scale,
        ram_valid => converter_ram_valid, ram_write => converter_ram_write,
        ram_address => converter_ram_address, ram_wdata => converter_ram_wdata,
        ram_byte_enable => converter_ram_byte_enable, ram_ready => converter_ready,
        ram_error => ram_error, ram_rdata => ram_rdata);
    ownership : process(clock)
    begin
      if rising_edge(clock) then
        if reset = '1' then numeric_owner <= '0';
        elsif number_start = '1' then numeric_owner <= '1';
        elsif converter_done = '1' then numeric_owner <= '0'; end if;
      end if;
    end process;
  end generate;

  main : process
    type memory_type is array (0 to 65535) of codec_byte;
    type text_type is array (0 to 127) of codec_byte;
    type fixture_record is record
      kind, scale, negative, input_length, output_length : natural;
      value : unsigned(63 downto 0);
      input_text, output_text : text_type;
    end record;
    type fixture_array is array (0 to 255) of fixture_record;
    variable memory : memory_type;
    variable expected : memory_type;
    variable fixtures : fixture_array;
    file job_file : text open read_mode is "jobs.txt";
    file number_file : text open read_mode is "numbers.txt";
    variable input_line : line;
    variable byte_vector : std_logic_vector(7 downto 0);
    variable word_vector : std_logic_vector(63 downto 0);
    variable number_count, job_count, job_index, cycles : natural := 0;
    variable mode, source_offset, table_offset, output_offset, capacity, input_length,
      table_length, expected_error, expected_length, row_value, column_value,
      german, abort_after, memory_fault, expected_host_calls : natural;
    variable expected_position : integer;
    variable ram_pending, number_pending : boolean := false;
    variable ram_delay, number_delay : natural := 0;
    variable pending_address : natural;
    variable pending_write : std_logic;
    variable pending_data : unsigned(63 downto 0);
    variable pending_enable : std_logic_vector(7 downto 0);
    variable matched : boolean;
    variable fixture_index : integer;
    variable candidate_byte : codec_byte;

    procedure tick is
    begin
      wait until falling_edge(clock);
      ram_ready <= '0'; ram_error <= '0'; fixture_done <= '0';
      if ram_pending then
        if ram_delay /= 0 then ram_delay := ram_delay - 1;
        else
          ram_pending := false; ram_ready <= '1';
          if (memory_fault = 1 and pending_address = (source_offset / 8) * 8) or
            (memory_fault = 2 and numeric_owner = '1') then ram_error <= '1';
          else
            for lane in 0 to 7 loop
              if pending_write = '1' and pending_enable(lane) = '1' then
                assert pending_address + lane >= output_offset and pending_address + lane < output_offset + capacity
                  report "write outside output capacity, job " & integer'image(job_index) severity failure;
                memory((pending_address + lane) mod 65536) := pending_data(lane * 8 + 7 downto lane * 8);
              end if;
              ram_rdata(lane * 8 + 7 downto lane * 8) <= memory((pending_address + lane) mod 65536);
            end loop;
          end if;
        end if;
      elsif ram_valid = '1' then
        assert ram_address(2 downto 0) = 0 report "unaligned RAM request" severity failure;
        pending_address := to_integer(ram_address);
        pending_write := ram_write; pending_data := ram_wdata; pending_enable := ram_byte_enable;
        ram_delay := cycles mod 5; ram_pending := true;
      end if;
      if number_pending and not real_numbers then
        assert ram_valid = '0' report "codec used RAM during numeric service" severity failure;
        if number_delay /= 0 then number_delay := number_delay - 1;
        else
          number_pending := false; fixture_done <= '1'; fixture_error <= CODEC_OK;
          fixture_position <= (others => '0'); fixture_length <= (others => '0');
          fixture_index := -1;
          for candidate in 0 to number_count - 1 loop
            if number_format = '0' then
              matched := fixtures(candidate).input_length = to_integer(number_length);
              matched := matched and ((fixtures(candidate).negative = 1) = (number_negative = '1'));
              if matched then
                for text_index in 0 to fixtures(candidate).input_length - 1 loop
                  if memory((to_integer(number_source) + text_index) mod 65536) /= fixtures(candidate).input_text(text_index) then matched := false; end if;
                end loop;
              end if;
            else
              matched := fixtures(candidate).value = number_value and fixtures(candidate).scale = to_integer(number_scale);
              matched := matched and ((fixtures(candidate).kind = 1) = (number_kind = '1'));
            end if;
            if matched and fixture_index = -1 then fixture_index := candidate; end if;
          end loop;
          if fixture_index = -1 then
            assert number_format = '0' report "missing formatting fixture, job " & integer'image(job_index) severity failure;
            fixture_error <= CODEC_NUMBER;
          elsif number_format = '0' then
            fixture_value <= fixtures(fixture_index).value;
            fixture_scale <= to_unsigned(fixtures(fixture_index).scale, 8);
            if fixtures(fixture_index).kind = 1 then fixture_kind <= '1'; else fixture_kind <= '0'; end if;
          else
            fixture_length <= to_unsigned(fixtures(fixture_index).output_length, 16);
            if fixtures(fixture_index).output_length <= to_integer(number_capacity) then
              for text_index in 0 to fixtures(fixture_index).output_length - 1 loop
                candidate_byte := fixtures(fixture_index).output_text(text_index);
                if candidate_byte = 46 then candidate_byte := number_decimal_separator; end if;
                assert to_integer(number_destination) + text_index >= output_offset and
                  to_integer(number_destination) + text_index < output_offset + capacity
                  report "numeric service write outside capacity" severity failure;
                memory((to_integer(number_destination) + text_index) mod 65536) := candidate_byte;
              end loop;
            end if;
          end if;
        end if;
      elsif number_start = '1' and not real_numbers then number_pending := true; number_delay := 7;
      end if;
      cycles := cycles + 1;
      wait until rising_edge(clock);
      wait for 1 ns;
    end procedure;
  begin
    readline(number_file, input_line); read(input_line, number_count);
    assert number_count <= 256 severity failure;
    for fixture in 0 to number_count - 1 loop
      readline(number_file, input_line);
      read(input_line, fixtures(fixture).kind); read(input_line, fixtures(fixture).scale);
      read(input_line, fixtures(fixture).negative); hread(input_line, word_vector);
      fixtures(fixture).value := unsigned(word_vector);
      read(input_line, fixtures(fixture).input_length); read(input_line, fixtures(fixture).output_length);
      readline(number_file, input_line);
      for text_index in 0 to fixtures(fixture).input_length - 1 loop
        hread(input_line, byte_vector); fixtures(fixture).input_text(text_index) := unsigned(byte_vector);
      end loop;
      readline(number_file, input_line);
      for text_index in 0 to fixtures(fixture).output_length - 1 loop
        hread(input_line, byte_vector); fixtures(fixture).output_text(text_index) := unsigned(byte_vector);
      end loop;
    end loop;
    readline(job_file, input_line); read(input_line, job_count);
    memory_fault := 0; reset <= '1'; tick; tick; reset <= '0';
    for current_job in 0 to job_count - 1 loop
      job_index := current_job;
      readline(job_file, input_line);
      read(input_line, mode); read(input_line, source_offset); read(input_line, table_offset);
      read(input_line, output_offset); read(input_line, capacity); read(input_line, input_length);
      read(input_line, table_length); read(input_line, expected_error); read(input_line, expected_position);
      read(input_line, expected_length); read(input_line, row_value); read(input_line, column_value);
      read(input_line, german); read(input_line, abort_after); read(input_line, memory_fault);
      read(input_line, expected_host_calls);
      memory := (others => x"A5");
      readline(job_file, input_line);
      for byte_index in 0 to input_length - 1 loop
        hread(input_line, byte_vector); memory((source_offset + byte_index) mod 65536) := unsigned(byte_vector);
      end loop;
      readline(job_file, input_line);
      for byte_index in 0 to table_length - 1 loop
        hread(input_line, byte_vector); memory(table_offset + byte_index) := unsigned(byte_vector);
      end loop;
      readline(job_file, input_line);
      for byte_index in 0 to expected_length - 1 loop
        hread(input_line, byte_vector); expected(byte_index) := unsigned(byte_vector);
      end loop;
      source <= to_unsigned(source_offset, 28); destination <= to_unsigned(output_offset, 28);
      names <= to_unsigned(table_offset, 28); source_length <= to_unsigned(input_length, 16);
      output_capacity <= to_unsigned(capacity, 16); formula_row <= to_unsigned(row_value, 20);
      formula_column <= to_unsigned(column_value, 24);
      if mode = 1 then decompile <= '1'; else decompile <= '0'; end if;
      if german = 1 then decimal_separator <= x"2C"; argument_separator <= x"3B";
      else decimal_separator <= x"2E"; argument_separator <= x"2C"; end if;
      cycles := 0; abort <= '0'; start <= '1'; tick; start <= '0';
      while done /= '1' loop
        if abort_after /= 0 and cycles = abort_after then abort <= '1'; else abort <= '0'; end if;
        tick;
        assert cycles < 2000000 report "timeout, job " & integer'image(job_index) severity failure;
      end loop;
      assert to_integer(error) = expected_error
        report "error, job " & integer'image(job_index) & ": got " & integer'image(to_integer(error)) &
          " expected " & integer'image(expected_error) & " position " & integer'image(to_integer(error_position)) severity failure;
      if expected_position >= 0 then
        assert to_integer(error_position) = expected_position report "error position, job " & integer'image(job_index) severity failure;
      end if;
      if expected_error = 0 then
        assert to_integer(host_calls) = expected_host_calls report "host call count, job " & integer'image(job_index) severity failure;
        assert to_integer(result_length) = expected_length
          report "length, job " & integer'image(job_index) & ": got " & integer'image(to_integer(result_length)) &
            " expected " & integer'image(expected_length) severity failure;
        for byte_index in 0 to expected_length - 1 loop
          assert memory((output_offset + byte_index) mod 65536) = expected(byte_index)
            report "data, job " & integer'image(job_index) & " byte " & integer'image(byte_index) &
              ": got " & integer'image(to_integer(memory((output_offset + byte_index) mod 65536))) &
              " expected " & integer'image(to_integer(expected(byte_index))) severity failure;
        end loop;
      else
        assert result_length = 0 report "failed job published an output length" severity failure;
      end if;
      assert memory((output_offset - 1) mod 65536) = x"A5" and memory((output_offset + capacity) mod 65536) = x"A5"
        report "output guard overwritten" severity failure;
      assert not ram_pending and not number_pending report "undrained service at completion" severity failure;
      memory_fault := 0; abort <= '0'; tick;
    end loop;
    report "ALL CODEC TESTS PASSED: " & integer'image(job_count) severity note;
    finished <= true;
    wait;
  end process;
end architecture;
