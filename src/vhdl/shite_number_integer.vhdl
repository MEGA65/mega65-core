library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.shite_number_pkg.all;

entity shite_number_integer is
  port (
    clock, reset, start : in std_logic;
    operation : in number_operation;
    first, second, third : in unsigned(1 downto 0);
    value : in unsigned(63 downto 0);
    factor : in unsigned(3 downto 0);
    addend : in unsigned(7 downto 0);
    byte_index : in unsigned(8 downto 0);
    done, overflow : out std_logic := '0';
    comparison : out integer range -1 to 1 := 0;
    result : out unsigned(63 downto 0) := (others => '0');
    length : out natural range 0 to 512 := 0;
    remainder : out unsigned(7 downto 0) := (others => '0')
  );
end entity;

architecture rtl of shite_number_integer is
  type memory_type is array (0 to 2047) of unsigned(7 downto 0);
  signal memory : memory_type;
  signal address : natural range 0 to 2047 := 0;
  signal read_data, write_data : unsigned(7 downto 0) := (others => '0');
  signal write_enable : std_logic := '0';
begin
  storage : process(clock)
  begin
    if rising_edge(clock) then
      read_data <= memory(address);
      if write_enable = '1' then memory(address) <= write_data; end if;
    end if;
  end process;

  sequencer : process(clock)
    type state_type is (IDLE, PREPARE, READ_FIRST, WAIT_FIRST, HAVE_FIRST,
      WAIT_SECOND, HAVE_SECOND, WAIT_THIRD, HAVE_THIRD, EXECUTE, DIVIDE_BIT,
      WRITE_BYTE, ADVANCE, FINISH);
    type lengths_type is array (0 to 3) of natural range 0 to 512;
    variable sizes : lengths_type := (others => 0);
    variable state : state_type := IDLE;
    variable command : number_operation := BIG_LOAD;
    variable first_slot, second_slot, third_slot : natural range 0 to 3 := 0;
    variable index, count, new_size : natural range 0 to 512 := 0;
    variable descending : boolean := false;
    variable first_byte, second_byte, third_byte, output_byte : unsigned(7 downto 0);
    variable multiplier : unsigned(3 downto 0);
    variable carry : unsigned(11 downto 0);
    variable total : unsigned(11 downto 0);
    variable division_remainder : unsigned(4 downto 0);
    variable quotient : unsigned(7 downto 0);
    variable bits_left : natural range 0 to 8;
    variable compare_result : integer range -1 to 1;
    variable input_word, output_word : unsigned(63 downto 0);
    variable failed : std_logic;
  begin
    if rising_edge(clock) then
      done <= '0'; write_enable <= '0';
      if reset = '1' then
        state := IDLE; sizes := (others => 0); overflow <= '0';
      else
        case state is
          when IDLE =>
            if start = '1' then
              command := operation; first_slot := to_integer(first);
              second_slot := to_integer(second); third_slot := to_integer(third);
              multiplier := factor; carry := resize(addend, 12); input_word := value;
              output_word := (others => '0'); compare_result := 0; failed := '0';
              division_remainder := (others => '0'); new_size := 0; index := 0;
              descending := false; state := PREPARE;
              case operation is
                when BIG_LOAD => count := 8;
                when BIG_COPY => count := sizes(second_slot);
                when BIG_MULTIPLY =>
                  count := sizes(first_slot);
                  if count < 512 then count := count + 1; end if;
                when BIG_COMPARE | BIG_SUBTRACT | BIG_SUM_COMPARE =>
                  count := sizes(first_slot);
                  if sizes(second_slot) > count then count := sizes(second_slot); end if;
                  if operation = BIG_SUM_COMPARE and sizes(third_slot) > count then count := sizes(third_slot); end if;
                  if operation /= BIG_SUM_COMPARE then carry := (others => '0'); end if;
                when BIG_DIVIDE10 | BIG_DIVIDE2 =>
                  count := sizes(first_slot); descending := true;
                  carry := (others => '0');
                  if count /= 0 then index := count - 1; end if;
                when BIG_GET => count := 8;
                when BIG_READ_BYTE | BIG_WRITE_BYTE =>
                  index := to_integer(byte_index); count := index + 1;
              end case;
            end if;
          when PREPARE =>
            if count = 0 then state := FINISH; else state := READ_FIRST; end if;
          when READ_FIRST =>
            address <= first_slot * 512 + index; state := WAIT_FIRST;
          when WAIT_FIRST => state := HAVE_FIRST;
          when HAVE_FIRST =>
            first_byte := (others => '0');
            if index < sizes(first_slot) or command = BIG_READ_BYTE then first_byte := read_data; end if;
            if command = BIG_COPY or command = BIG_COMPARE or command = BIG_SUBTRACT or command = BIG_SUM_COMPARE then
              address <= second_slot * 512 + index; state := WAIT_SECOND;
            else state := EXECUTE; end if;
          when WAIT_SECOND => state := HAVE_SECOND;
          when HAVE_SECOND =>
            second_byte := (others => '0');
            if index < sizes(second_slot) then second_byte := read_data; end if;
            if command = BIG_SUM_COMPARE then
              address <= third_slot * 512 + index; state := WAIT_THIRD;
            else state := EXECUTE; end if;
          when WAIT_THIRD => state := HAVE_THIRD;
          when HAVE_THIRD =>
            third_byte := (others => '0');
            if index < sizes(third_slot) then third_byte := read_data; end if;
            state := EXECUTE;
          when EXECUTE =>
            state := WRITE_BYTE;
            case command is
              when BIG_LOAD => output_byte := input_word(7 downto 0); input_word := shift_right(input_word, 8);
              when BIG_COPY => output_byte := second_byte;
              when BIG_MULTIPLY =>
                case to_integer(multiplier) is
                  when 1 => total := resize(first_byte, 12);
                  when 2 => total := shift_left(resize(first_byte, 12), 1);
                  when 5 => total := shift_left(resize(first_byte, 12), 2) + resize(first_byte, 12);
                  when others => total := shift_left(resize(first_byte, 12), 3) + shift_left(resize(first_byte, 12), 1);
                end case;
                total := total + carry; output_byte := total(7 downto 0); carry := shift_right(total, 8);
              when BIG_SUBTRACT =>
                total := resize(first_byte, 12) - resize(second_byte, 12) - carry;
                output_byte := total(7 downto 0); carry := (others => '0'); carry(0) := total(11);
              when BIG_COMPARE =>
                if first_byte < second_byte then compare_result := -1;
                elsif first_byte > second_byte then compare_result := 1; end if;
                state := ADVANCE;
              when BIG_SUM_COMPARE =>
                total := resize(first_byte, 12) + resize(second_byte, 12) + carry;
                carry := shift_right(total, 8);
                if total(7 downto 0) < third_byte then compare_result := -1;
                elsif total(7 downto 0) > third_byte then compare_result := 1; end if;
                state := ADVANCE;
              when BIG_DIVIDE2 =>
                output_byte := first_byte; output_byte := shift_right(output_byte, 1); output_byte(7) := carry(0);
                carry := (others => '0'); carry(0) := first_byte(0);
              when BIG_DIVIDE10 =>
                quotient := (others => '0'); bits_left := 8; state := DIVIDE_BIT;
              when BIG_GET =>
                output_word := shift_right(output_word, 8); output_word(63 downto 56) := first_byte; state := ADVANCE;
              when BIG_READ_BYTE => output_word := resize(first_byte, 64); state := FINISH;
              when BIG_WRITE_BYTE => output_byte := carry(7 downto 0);
            end case;
          when DIVIDE_BIT =>
            division_remainder := shift_left(division_remainder, 1); division_remainder(0) := first_byte(7);
            first_byte := shift_left(first_byte, 1); quotient := shift_left(quotient, 1);
            if division_remainder >= 10 then division_remainder := division_remainder - 10; quotient(0) := '1'; end if;
            bits_left := bits_left - 1;
            if bits_left = 0 then output_byte := quotient; state := WRITE_BYTE; end if;
          when WRITE_BYTE =>
            address <= first_slot * 512 + index; write_data <= output_byte; write_enable <= '1';
            if output_byte /= 0 and index + 1 > new_size then new_size := index + 1; end if;
            state := ADVANCE;
          when ADVANCE =>
            if descending then
              if index = 0 then state := FINISH; else index := index - 1; state := READ_FIRST; end if;
            elsif index + 1 = count then state := FINISH;
            else index := index + 1; state := READ_FIRST; end if;
          when FINISH =>
            case command is
              when BIG_LOAD | BIG_COPY | BIG_SUBTRACT | BIG_MULTIPLY | BIG_DIVIDE10 | BIG_DIVIDE2 => sizes(first_slot) := new_size;
              when others => null;
            end case;
            if command = BIG_SUBTRACT and carry /= 0 then failed := '1'; end if;
            if command = BIG_MULTIPLY and carry /= 0 then failed := '1'; end if;
            if command = BIG_SUM_COMPARE and carry /= 0 then compare_result := 1; end if;
            done <= '1'; overflow <= failed; comparison <= compare_result;
            length <= sizes(first_slot); result <= output_word;
            if command = BIG_DIVIDE2 then remainder <= resize(carry, 8);
            else remainder <= resize(division_remainder, 8); end if;
            state := IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
