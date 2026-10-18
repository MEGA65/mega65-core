library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package shite_codec_pkg is
  subtype codec_byte is unsigned(7 downto 0);
  subtype codec_reference is unsigned(47 downto 0);
  constant CODEC_OK : codec_byte := x"00";
  constant CODEC_SYNTAX : codec_byte := x"01";
  constant CODEC_NAME : codec_byte := x"02";
  constant CODEC_NUMBER : codec_byte := x"03";
  constant CODEC_BAD_REFERENCE : codec_byte := x"04";
  constant CODEC_BAD_ARITY : codec_byte := x"05";
  constant CODEC_DEPTH : codec_byte := x"06";
  constant CODEC_CAPACITY : codec_byte := x"07";
  constant CODEC_BYTECODE : codec_byte := x"08";
  constant CODEC_TABLE : codec_byte := x"09";
  constant CODEC_MEMORY : codec_byte := x"0A";
  constant CODEC_ABORTED : codec_byte := x"0B";
  function codec_upper(value : codec_byte) return codec_byte;
  function codec_letter(value : codec_byte) return boolean;
  function codec_digit(value : codec_byte) return boolean;
  function codec_space(value : codec_byte) return boolean;
  function codec_word(value : codec_byte) return boolean;
  function codec_precedence(value : codec_byte) return natural;
  function codec_arity(identifier, count : natural) return boolean;
  function codec_short(value : codec_reference) return boolean;
end package;

package body shite_codec_pkg is
  function codec_upper(value : codec_byte) return codec_byte is
  begin
    if value >= 97 and value <= 122 then return value - 32; end if;
    return value;
  end;

  function codec_letter(value : codec_byte) return boolean is
  begin
    return codec_upper(value) >= 65 and codec_upper(value) <= 90;
  end;

  function codec_digit(value : codec_byte) return boolean is
  begin
    return value >= 48 and value <= 57;
  end;

  function codec_space(value : codec_byte) return boolean is
  begin
    return value = 32 or value = 9 or value = 10 or value = 13;
  end;

  function codec_word(value : codec_byte) return boolean is
  begin
    return codec_letter(value) or codec_digit(value) or value = 95 or value = 46 or value = 36;
  end;

  function codec_precedence(value : codec_byte) return natural is
  begin
    case to_integer(value) is
      when 16#18# to 16#1D# => return 1;
      when 16#17# => return 2;
      when 16#10# | 16#11# => return 3;
      when 16#12# | 16#13# => return 4;
      when 16#14# => return 5;
      when 16#15# => return 6;
      when others => return 0;
    end case;
  end;

  function codec_arity(identifier, count : natural) return boolean is
  begin
    case identifier is
      when 0 to 6 | 39 => return true;
      when 7 | 8 | 11 | 12 | 16 | 18 to 26 | 30 | 34 to 37 => return count = 1;
      when 9 | 31 | 32 => return count >= 1 and count <= 2;
      when 10 | 13 | 27 | 29 | 38 | 41 => return count = 2;
      when 14 | 15 => return count >= 1;
      when 17 | 40 | 44 | 45 => return count >= 2 and count <= 3;
      when 28 => return count = 0;
      when 33 => return count = 3;
      when 42 | 43 => return count >= 3 and count <= 4;
      when others => return true;
    end case;
  end;

  function codec_short(value : codec_reference) return boolean is
    variable row_value : signed(19 downto 0);
    variable column_value : signed(23 downto 0);
  begin
    row_value := signed(value(43 downto 24));
    column_value := signed(value(23 downto 0));
    if value(47) = '1' then
      if unsigned(row_value) > 32767 then return false; end if;
    elsif row_value < -16384 or row_value > 16383 then return false;
    end if;
    if value(46) = '1' then return unsigned(column_value) <= 16383; end if;
    return column_value >= -8192 and column_value <= 8191;
  end;
end package body;
