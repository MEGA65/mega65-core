library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use work.shite_codec_pkg.all;

entity tb_shite_number_text is
end entity;

architecture test of tb_shite_number_text is
  signal clock : std_logic := '0';
  signal finished : boolean := false;
  signal reset, start, format, negative, display, abort, busy, done : std_logic := '0';
  signal source, destination : unsigned(27 downto 0) := (others => '0');
  signal input_length, capacity, error_position, result_length : unsigned(15 downto 0) := (others => '0');
  signal value, result_value : unsigned(63 downto 0) := (others => '0');
  signal kind, result_kind : std_logic := '0';
  signal scale, decimal_separator, display_decimals, display_width, error, result_scale : codec_byte := (others => '0');
  signal display_style : unsigned(3 downto 0) := x"0";
  signal ram_valid, ram_write, ram_ready, ram_error : std_logic := '0';
  signal ram_address : unsigned(27 downto 0);
  signal ram_wdata, ram_rdata : unsigned(63 downto 0) := (others => '0');
  signal ram_byte_enable : std_logic_vector(7 downto 0);
begin
  clock <= not clock after 5 ns when not finished;

  converter : entity work.shite_number_text
    port map (clock => clock, reset => reset, start => start, format => format,
      negative => negative, source => source, destination => destination,
      input_length => input_length, capacity => capacity, value => value, kind => kind,
      scale => scale, decimal_separator => decimal_separator, display => display,
      display_style => display_style, display_decimals => display_decimals,
      display_width => display_width, abort => abort, busy => busy, done => done,
      error => error, error_position => error_position, result_length => result_length,
      result_value => result_value, result_kind => result_kind, result_scale => result_scale,
      ram_valid => ram_valid, ram_write => ram_write, ram_address => ram_address,
      ram_wdata => ram_wdata, ram_byte_enable => ram_byte_enable,
      ram_ready => ram_ready, ram_error => ram_error, ram_rdata => ram_rdata);

  main : process
    type memory_type is array (0 to 65535) of codec_byte;
    variable memory, expected : memory_type;
    file jobs : text open read_mode is "number_jobs.txt";
    variable input_line : line;
    variable byte_vector : std_logic_vector(7 downto 0);
    variable word_vector : std_logic_vector(63 downto 0);
    variable job_count, job_index, cycles, total_cycles : natural := 0;
    variable mode, sign_value, kind_value, scale_value, decimal_value, style_value,
      decimals_value, width_value, source_offset, output_offset, capacity_value,
      input_size, expected_error, expected_kind, expected_scale, expected_length,
      abort_after, memory_fault : natural;
    variable expected_position : integer;
    variable expected_value : unsigned(63 downto 0);
    variable pending : boolean := false;
    variable pending_address, delay : natural;
    variable pending_write : std_logic;
    variable pending_data : unsigned(63 downto 0);
    variable pending_enable : std_logic_vector(7 downto 0);

    procedure tick is
    begin
      wait until falling_edge(clock);
      ram_ready <= '0'; ram_error <= '0';
      if pending then
        assert ram_valid = '1' and to_integer(ram_address) = pending_address and
          ram_write = pending_write and ram_wdata = pending_data and ram_byte_enable = pending_enable
          report "RAM request changed while pending" severity failure;
        if delay /= 0 then delay := delay - 1;
        else
          pending := false; ram_ready <= '1';
          if memory_fault = 1 then ram_error <= '1';
          else
            for lane in 0 to 7 loop
              if pending_write = '1' and pending_enable(lane) = '1' then
                assert pending_address + lane >= output_offset and pending_address + lane < output_offset + capacity_value
                  report "write outside capacity" severity failure;
                memory((pending_address + lane) mod 65536) := pending_data(lane * 8 + 7 downto lane * 8);
              end if;
              ram_rdata(lane * 8 + 7 downto lane * 8) <= memory((pending_address + lane) mod 65536);
            end loop;
          end if;
        end if;
      elsif ram_valid = '1' then
        assert ram_address(2 downto 0) = 0 report "unaligned RAM request" severity failure;
        pending := true; pending_address := to_integer(ram_address); pending_write := ram_write;
        pending_data := ram_wdata; pending_enable := ram_byte_enable; delay := cycles mod 5;
      end if;
      if abort_after /= 0 and cycles >= abort_after then abort <= '1'; end if;
      wait until rising_edge(clock); wait for 1 ns;
      cycles := cycles + 1; total_cycles := total_cycles + 1;
    end procedure;
  begin
    reset <= '1'; abort_after := 0; memory_fault := 0; tick; tick; reset <= '0';
    readline(jobs, input_line); read(input_line, job_count);
    for job_number in 0 to job_count - 1 loop
      job_index := job_number; cycles := 0; abort <= '0'; pending := false;
      memory := (others => x"A5");
      readline(jobs, input_line);
      read(input_line, mode); read(input_line, sign_value); read(input_line, kind_value);
      read(input_line, scale_value); read(input_line, decimal_value); read(input_line, style_value);
      read(input_line, decimals_value); read(input_line, width_value);
      read(input_line, source_offset); read(input_line, output_offset); read(input_line, capacity_value);
      read(input_line, input_size); hread(input_line, word_vector); value <= unsigned(word_vector);
      read(input_line, expected_error); read(input_line, expected_position);
      read(input_line, expected_kind); read(input_line, expected_scale);
      hread(input_line, word_vector); expected_value := unsigned(word_vector);
      read(input_line, expected_length); read(input_line, abort_after); read(input_line, memory_fault);
      readline(jobs, input_line);
      for offset in 0 to input_size - 1 loop
        hread(input_line, byte_vector); memory((source_offset + offset) mod 65536) := unsigned(byte_vector);
      end loop;
      readline(jobs, input_line);
      for offset in 0 to expected_length - 1 loop hread(input_line, byte_vector); expected(offset) := unsigned(byte_vector); end loop;
      source <= to_unsigned(source_offset, 28); destination <= to_unsigned(output_offset, 28);
      input_length <= to_unsigned(input_size, 16); capacity <= to_unsigned(capacity_value, 16);
      format <= '0'; display <= '0'; if mode /= 0 then format <= '1'; end if; if mode = 2 then display <= '1'; end if;
      negative <= '0'; if sign_value /= 0 then negative <= '1'; end if;
      kind <= '0'; if kind_value /= 0 then kind <= '1'; end if;
      scale <= to_unsigned(scale_value, 8); decimal_separator <= to_unsigned(decimal_value, 8);
      display_style <= to_unsigned(style_value, 4); display_decimals <= to_unsigned(decimals_value, 8);
      display_width <= to_unsigned(width_value, 8);
      start <= '1'; tick; start <= '0';
      while done /= '1' loop
        tick;
        assert cycles < 15000000 report "number timeout, job " & integer'image(job_index) severity failure;
      end loop;
      assert not pending and ram_valid = '0' and busy = '0' report "unfinished service" severity failure;
      assert to_integer(error) = expected_error report "error mismatch, job " & integer'image(job_index) &
        ", got " & integer'image(to_integer(error)) & ", expected " & integer'image(expected_error) severity failure;
      if expected_position >= 0 then
        assert to_integer(error_position) = expected_position report "position mismatch, job " & integer'image(job_index) severity failure;
      end if;
      if expected_error = 0 then
        if mode = 0 then
          assert result_value = expected_value report "value mismatch, job " & integer'image(job_index) &
            ", got " & to_hstring(result_value) & ", expected " & to_hstring(expected_value) severity failure;
          assert (result_kind = '1') = (expected_kind = 1) and to_integer(result_scale) = expected_scale
            report "kind/scale mismatch, job " & integer'image(job_index) severity failure;
        else
          assert to_integer(result_length) = expected_length report "length mismatch, job " & integer'image(job_index) &
            ", got " & integer'image(to_integer(result_length)) & ", expected " & integer'image(expected_length) severity failure;
          for offset in 0 to expected_length - 1 loop
            assert memory((output_offset + offset) mod 65536) = expected(offset)
              report "text mismatch, job " & integer'image(job_index) & ", byte " & integer'image(offset) &
                ", got " & integer'image(to_integer(memory((output_offset + offset) mod 65536))) &
                ", expected " & integer'image(to_integer(expected(offset))) severity failure;
          end loop;
        end if;
      else assert result_length = 0 report "failed result length" severity failure; end if;
      assert memory((output_offset - 1) mod 65536) = x"A5" and
        memory((output_offset + capacity_value) mod 65536) = x"A5" report "output guard damaged" severity failure;
      abort <= '0'; abort_after := 0; tick;
    end loop;
    report "ALL NUMBER TESTS PASSED: " & integer'image(job_count) & ", cycles " & integer'image(total_cycles);
    finished <= true; wait;
  end process;
end architecture;
