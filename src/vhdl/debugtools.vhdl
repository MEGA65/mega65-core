library ieee;
use Std.TextIO.all;
use ieee.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

package debugtools is

    function to_string(sv: Std_Logic_Vector) return string;
    function to_hstring(sv: Std_Logic_Vector) return string;
    function to_hstring(sv: unsigned) return string;
    function to_hstring(sv: signed) return string;
    function to_hexstring(sv: Std_Logic_Vector) return string;
    function to_hexstring(sv: unsigned) return string;
    function to_hexstring(sv: signed) return string;
    function safe_to_integer(sv : unsigned) return integer;
    procedure HWRITE(L:inout LINE; VALUE:in BIT_VECTOR;
    JUSTIFIED:in SIDE := RIGHT; FIELD:in WIDTH := 0);

end debugtools;

package body debugtools is

      procedure HWRITE(L:inout LINE; VALUE:in BIT_VECTOR;
    JUSTIFIED:in SIDE := RIGHT; FIELD:in WIDTH := 0) is      
      variable quad: bit_vector(0 to 3);
      constant ne:   integer := (value'length+3)/4;
      constant displaybits: integer := ne*4;
      constant inputbits: integer := value'length;
      constant emptybits: integer := displaybits - inputbits;
      variable bv:   bit_vector(0 to value'length+4) := (others => '0');
      variable s:    string(1 to ne);
    begin

      bv(emptybits to (emptybits+value'length-1)) := value;
    
      for i in 0 to ne-1 loop
        quad := bv(4*i to 4*i+3);
        case quad is
          when x"0" => s(i+1) := '0';
          when x"1" => s(i+1) := '1';
          when x"2" => s(i+1) := '2';
          when x"3" => s(i+1) := '3';
          when x"4" => s(i+1) := '4';
          when x"5" => s(i+1) := '5';
          when x"6" => s(i+1) := '6';
          when x"7" => s(i+1) := '7';
          when x"8" => s(i+1) := '8';
          when x"9" => s(i+1) := '9';
          when x"A" => s(i+1) := 'A';
          when x"B" => s(i+1) := 'B';
          when x"C" => s(i+1) := 'C';
          when x"D" => s(i+1) := 'D';
          when x"E" => s(i+1) := 'E';
          when x"F" => s(i+1) := 'F';
        end case;
      end loop;
      write(L, s, JUSTIFIED, FIELD);
    end HWRITE; 
    
    function to_string(sv: Std_Logic_Vector) return string is
      use Std.TextIO.all;
      
      variable bv: bit_vector(sv'range) := to_bitvector(sv);
      variable lp: line;
    begin
      write(lp, bv);
      return lp.all;
    end;

    function to_hstring(sv: Std_Logic_Vector) return string is
      use Std.TextIO.all;
      
      variable bv: bit_vector(sv'range) := to_bitvector(sv);
      variable lp: line;
    begin
      hwrite(lp, bv);
      return lp.all;
    end;

    function to_hstring(sv: unsigned) return string is
      use Std.TextIO.all;
      
    begin
      return to_hstring(std_logic_vector(sv));
    end;

    function to_hstring(sv: signed) return string is
      use Std.TextIO.all;
      
    begin
      return to_hstring(std_logic_vector(sv));
    end;
      
    function to_hexstring(sv: Std_Logic_Vector) return string is
      use Std.TextIO.all;
      
      variable bv: bit_vector(sv'range) := to_bitvector(sv);
      variable lp: line;
    begin
      hwrite(lp, bv);
      return lp.all;
    end;

    function to_hexstring(sv: unsigned) return string is
      use Std.TextIO.all;
      
    begin
      return to_hexstring(std_logic_vector(sv));
    end;

    function to_hexstring(sv: signed) return string is
      use Std.TextIO.all;
      
    begin
      return to_hexstring(std_logic_vector(sv));
    end;
      


      function safe_to_integer(sv : unsigned) return integer is
        variable v : integer := 0;
        variable p : integer := 0;
      begin
        for i in sv'low to sv'high loop
          if sv(i)='1' then
            v := v + (2**p);
          elsif sv(i) /= '0' then
            report "Bit #" & integer'image(i) & " of %" & to_string(std_logic_vector(sv)) & " is not 1 or 0, but " & std_logic'image(sv(i)) & ".";
          end if;
          p := p + 1;
        end loop;
        return v;
      end;
      
end debugtools;
