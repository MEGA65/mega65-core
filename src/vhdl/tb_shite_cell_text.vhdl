library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.shite_codec_pkg.all;

entity tb_shite_cell_text is
end entity;

architecture test of tb_shite_cell_text is
  signal clock : std_logic := '0';
  signal finished : boolean := false;
  signal reset, start, abort, busy, done, screen_codes, upper_case : std_logic := '0';
  signal kind : unsigned(3 downto 0) := x"0";
  signal value, cell_format : unsigned(63 downto 0) := (others => '0');
  signal text_length, capacity, result_length : unsigned(15 downto 0) := (others => '0');
  signal width : codec_byte := x"00";
  signal decimal_separator : codec_byte := x"2E";
  signal error : codec_byte;
  signal colour : unsigned(3 downto 0);
  signal cell_valid, cell_write, number_valid, number_write, ram_ready, ram_error : std_logic := '0';
  signal cell_address, number_address : unsigned(27 downto 0);
  signal cell_wdata, number_wdata, ram_rdata : unsigned(63 downto 0) := (others => '0');
  signal cell_enable, number_enable : std_logic_vector(7 downto 0);
  signal cell_ready, number_ready, numeric_owner, number_start, number_done : std_logic := '0';
  signal number_value : unsigned(63 downto 0);
  signal number_kind : std_logic;
  signal number_scale, number_decimal, number_decimals, number_width, number_error : codec_byte;
  signal number_destination : unsigned(27 downto 0);
  signal number_style : unsigned(3 downto 0);
  signal number_length : unsigned(15 downto 0);
begin
  clock <= not clock after 5 ns when not finished;
  cell_ready <= ram_ready when numeric_owner = '0' else '0';
  number_ready <= ram_ready when numeric_owner = '1' else '0';

  renderer : entity work.shite_cell_text
    port map (clock => clock, reset => reset, start => start, abort => abort,
      kind => kind, value => value, cell_format => cell_format,
      text_source => to_unsigned(259, 28), scratch => to_unsigned(8195, 28), destination => to_unsigned(16387, 28),
      text_length => text_length, capacity => capacity, width => width, decimal_separator => decimal_separator,
      screen_codes => screen_codes, upper_case => upper_case, busy => busy, done => done,
      error => error, result_length => result_length, colour => colour,
      ram_valid => cell_valid, ram_write => cell_write, ram_address => cell_address,
      ram_wdata => cell_wdata, ram_byte_enable => cell_enable, ram_ready => cell_ready,
      ram_error => ram_error, ram_rdata => ram_rdata,
      number_start => number_start, number_value => number_value, number_kind => number_kind,
      number_scale => number_scale, number_decimal_separator => number_decimal,
      number_destination => number_destination, number_style => number_style,
      number_decimals => number_decimals, number_width => number_width,
      number_done => number_done, number_error => number_error, number_result_length => number_length);

  converter : entity work.shite_number_text
    port map (clock => clock, reset => reset, start => number_start, format => '1', negative => '0',
      source => to_unsigned(0, 28), destination => number_destination,
      input_length => to_unsigned(0, 16), capacity => to_unsigned(512, 16),
      value => number_value, kind => number_kind, scale => number_scale,
      decimal_separator => number_decimal, display => '1', display_style => number_style,
      display_decimals => number_decimals, display_width => number_width, busy => open,
      done => number_done, error => number_error, result_length => number_length,
      error_position => open, result_value => open, result_kind => open, result_scale => open,
      ram_valid => number_valid, ram_write => number_write, ram_address => number_address,
      ram_wdata => number_wdata, ram_byte_enable => number_enable,
      ram_ready => number_ready, ram_error => ram_error, ram_rdata => ram_rdata);

  ownership : process(clock)
  begin
    if rising_edge(clock) then
      if reset = '1' then numeric_owner <= '0';
      elsif number_start = '1' then numeric_owner <= '1';
      elsif number_done = '1' then numeric_owner <= '0'; end if;
    end if;
  end process;

  main : process
    type memory_type is array (0 to 32767) of codec_byte;
    variable memory : memory_type;
    variable pending : boolean := false;
    variable pending_address, delay, cycles, case_number : natural := 0;
    variable pending_write : std_logic;
    variable pending_data : unsigned(63 downto 0);
    variable pending_enable : std_logic_vector(7 downto 0);
    variable output_width, available, fault, abort_after : natural := 0;

    procedure tick is
    begin
      wait until falling_edge(clock); ram_ready <= '0'; ram_error <= '0';
      if pending then
        if delay /= 0 then delay := delay - 1;
        else
          pending := false; ram_ready <= '1';
          if fault /= 0 then ram_error <= '1';
          else
            for lane in 0 to 7 loop
              if pending_write = '1' and pending_enable(lane) = '1' then
                assert (pending_address + lane >= 8195 and pending_address + lane < 8195 + 512) or
                  (pending_address + lane >= 16387 and pending_address + lane < 16387 + available)
                  report "renderer write outside buffers" severity failure;
                memory(pending_address + lane) := pending_data(lane * 8 + 7 downto lane * 8);
              end if;
              ram_rdata(lane * 8 + 7 downto lane * 8) <= memory(pending_address + lane);
            end loop;
          end if;
        end if;
      elsif numeric_owner = '1' and number_valid = '1' then
        assert cell_valid = '0' report "renderer used RAM during conversion" severity failure;
        pending := true; pending_address := to_integer(number_address); pending_write := number_write;
        pending_data := number_wdata; pending_enable := number_enable; delay := cycles mod 5;
      elsif numeric_owner = '0' and cell_valid = '1' then
        pending := true; pending_address := to_integer(cell_address); pending_write := cell_write;
        pending_data := cell_wdata; pending_enable := cell_enable; delay := cycles mod 5;
      end if;
      if abort_after /= 0 and cycles >= abort_after then abort <= '1'; end if;
      wait until rising_edge(clock); wait for 1 ns; cycles := cycles + 1;
    end procedure;

    function fmt(style : natural := 0; places : natural := 2; scale_value : natural := 0;
                 alignment : natural := 0; flags : natural := 0; prefix : natural := 0;
                 suffix : natural := 0; colours : natural := 2) return unsigned is
      variable result : unsigned(63 downto 0) := (others => '0');
    begin
      result(3 downto 0) := to_unsigned(style, 4); result(5 downto 4) := to_unsigned(alignment, 2);
      result(15 downto 8) := to_unsigned(places, 8); result(23 downto 16) := to_unsigned(scale_value, 8);
      result(31 downto 24) := to_unsigned(flags, 8); result(39 downto 32) := to_unsigned(prefix, 8);
      result(47 downto 40) := to_unsigned(suffix, 8); result(55 downto 48) := to_unsigned(colours, 8);
      return result;
    end function;

    procedure render(cell_kind : natural; cell_value, formatting : unsigned(63 downto 0);
                     input_text, expected : string; columns : natural := 0;
                     expected_colour : natural := 2; expected_error : natural := 0;
                     output_space : natural := 512; memory_fault : natural := 0;
                     abort_cycle : natural := 0) is
    begin
      case_number := case_number + 1; cycles := 0; memory := (others => x"A5");
      for index in input_text'range loop memory(259 + index - input_text'low) := to_unsigned(character'pos(input_text(index)), 8); end loop;
      output_width := expected'length; if columns /= 0 then output_width := columns; end if;
      available := output_space; fault := memory_fault; abort_after := abort_cycle;
      kind <= to_unsigned(cell_kind, 4); value <= cell_value; cell_format <= formatting;
      text_length <= to_unsigned(input_text'length, 16); width <= to_unsigned(output_width, 8);
      capacity <= to_unsigned(output_space, 16); start <= '1'; tick; start <= '0';
      while done /= '1' loop tick; assert cycles < 3000000 report "renderer timeout" severity failure; end loop;
      assert to_integer(error) = expected_error report "renderer error, case " & integer'image(case_number) severity failure;
      assert not pending and numeric_owner = '0' and busy = '0' report "renderer unfinished service" severity failure;
      if expected_error = 0 then
        assert to_integer(result_length) = expected'length report "renderer length, case " & integer'image(case_number) severity failure;
        assert to_integer(colour) = expected_colour report "renderer colour, case " & integer'image(case_number) severity failure;
        for index in expected'range loop
          assert memory(16387 + index - expected'low) = character'pos(expected(index))
            report "renderer text, case " & integer'image(case_number) & ", byte " & integer'image(index) &
              ", got " & integer'image(to_integer(memory(16387 + index - expected'low))) severity failure;
        end loop;
      else assert result_length = 0 report "renderer failed length" severity failure; end if;
      assert memory(16386) = x"A5" and memory(16387 + available) = x"A5" and
        memory(8194) = x"A5" and memory(8195 + 512) = x"A5" report "renderer guard damaged" severity failure;
      abort <= '0'; abort_after := 0; fault := 0; tick;
    end procedure;
  begin
    reset <= '1'; tick; tick; reset <= '0';
    render(0, x"0000000000000000", fmt, "", "        ");
    render(1, x"0000000000000000", fmt, "hello", "hello   ");
    render(7, x"0000000000000000", fmt(alignment => 3), "hello", "   hello");
    render(1, x"0000000000000000", fmt(alignment => 2), "hello", " hello  ");
    render(1, x"0000000000000000", fmt, "abcdefghij", "abcde");
    render(1, x"0000000000000000", fmt(alignment => 3), "abcdefghij", "fghij");
    render(1, x"0000000000000000", fmt(alignment => 2), "abcdefghij", "cdefg");
    render(1, x"0000000000000000", fmt, string'(1 to 2000 => 'x'), "xxxxx");
    render(4, x"000000000000007B", fmt, "", "     123");
    render(4, x"7FFFFFFFFFFFFFFF", fmt, "", " 9223372036854775807");
    render(5, x"00000000FFFFFF85", fmt, "", "    -123");
    render(4, x"000000000000007D", fmt(1, 1, 2), "", "   1.3");
    render(4, x"FFFFFFFFFFFFFF83", fmt(1, 1, 2), "", "  -1.3");
    render(4, x"0000000000000003", fmt(1, 2, 130), "", "    0.75");
    render(3, x"4004000000000000", fmt(4, 0), "", "   3");
    render(3, x"C004000000000000", fmt(4, 0), "", "  -3");
    render(3, x"3FC0000000000000", fmt(3, 1), "", "   12.5%");
    render(3, x"4058FF5C28F5C28F", fmt(2, 1), "", "  1.0E2");
    render(4, x"000000000001E23A", fmt(1, 2, 2, flags => 1), "", "  1,234.50");
    render(4, x"FFFFFFFFFFFE1DC6", fmt(1, 2, 2, flags => 55, prefix => 36, suffix => 33, colours => 242),
      "", " ($1,234.50!)", expected_colour => 15);
    render(4, x"000000000001E240", fmt(1, 2, 2), "", "####");
    render(3, x"7FF0000000000000", fmt, "", "   #NUM!");
    render(3, x"8000000000000000", fmt, "", "#");
    render(4, x"0000000000000001", fmt(scale_value => 19), "", "   #NUM!");
    render(6, x"0000000000000000", fmt, "", "#NUM!   ");
    for code in 1 to 9 loop
      case code is
        when 1 => render(6, to_unsigned(code, 64), fmt, "", "#DIV/0! ");
        when 2 => render(6, to_unsigned(code, 64), fmt, "", "#VALUE! ");
        when 3 => render(6, to_unsigned(code, 64), fmt, "", "#REF!   ");
        when 4 => render(6, to_unsigned(code, 64), fmt, "", "#NUM!   ");
        when 5 => render(6, to_unsigned(code, 64), fmt, "", "#CIRC!  ");
        when 6 => render(6, to_unsigned(code, 64), fmt, "", "#N/A    ");
        when 7 => render(6, to_unsigned(code, 64), fmt, "", "#STACK! ");
        when 8 => render(6, to_unsigned(code, 64), fmt, "", "#NAME?  ");
        when 9 => render(6, to_unsigned(code, 64), fmt, "", "#COMPILE");
        when others => null;
      end case;
    end loop;
    decimal_separator <= x"2C";
    render(4, x"000000000001E23A", fmt(1, 2, 2, flags => 1), "", "  1.234,50");
    decimal_separator <= x"2E";
    screen_codes <= '1'; upper_case <= '1';
    render(1, x"0000000000000000", fmt, "Abc@[]", character'val(1) & character'val(2) & character'val(3) &
      character'val(0) & character'val(27) & character'val(29));
    upper_case <= '0';
    render(1, x"0000000000000000", fmt, "Abc", "A" & character'val(2) & character'val(3));
    screen_codes <= '0';
    render(4, x"0000000000000001", fmt(4, 0, flags => 16, prefix => 1), "", " a1");
    upper_case <= '1';
    render(4, x"0000000000000001", fmt(4, 0, flags => 16, prefix => 1), "", " A1");
    render(4, x"0000000000000001", fmt, "", "");
    render(1, x"0000000000000000", fmt, "abc", "", columns => 8, expected_error => 7, output_space => 4);
    render(1, x"0000000000000000", fmt, "abc", "", columns => 8, expected_error => 10, memory_fault => 1);
    render(1, x"0000000000000000", fmt, "abc", "", columns => 8, expected_error => 11, abort_cycle => 4);
    render(3, x"3FF0000000000000", fmt(1, 2), "", "", columns => 8, expected_error => 11, abort_cycle => 20);
    report "ALL CELL TEXT TESTS PASSED: " & integer'image(case_number);
    finished <= true; wait;
  end process;
end architecture;
