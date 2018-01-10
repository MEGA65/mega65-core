library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_mfm is
end entity;

architecture foo of test_mfm is

  type CharFile is file of character;
  
begin

  process is
    file trace : CharFile;
    variable c : character;
  begin
    file_open(trace,"assets/track2-40ns.dat",READ_MODE);
    while not endfile(trace) loop
      Read(trace,c);
      report "Read char $" & to_hstring(to_unsigned(character'pos(c),8));
    end loop;
  end process;
  
end foo;
