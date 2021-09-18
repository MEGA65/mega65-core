library ieee;
use Std.TextIO.all;
use ieee.STD_LOGIC_1164.all;
use ieee.numeric_std.all;

package victypes is

  type sprite_vector_eight is array(0 to 7) of unsigned(7 downto 0);
  
  subtype spritebytenumber is integer range 0 to 319;
  subtype spritenumber is integer range 0 to 15;
  subtype spritedatabytenumber is integer range 0 to 65535;
  
  subtype xposition is integer range 0 to 4095;
  subtype yposition is integer range 0 to 4095;

  type spritebaseaddresses is array (0 to 7) of unsigned(19 downto 0);
  
  function to_xposition(x : unsigned) return xposition;
  function to_yposition(x : unsigned) return yposition;
  function to_spritebytenumber(x : unsigned) return spritebytenumber;

end package;

package body victypes is
  
  function to_xposition (x : unsigned) return xposition is
    variable o : xposition;    
  begin  
    o := to_integer(unsigned(x));
    return o;
  end to_xposition;

  function to_yposition (x : unsigned) return yposition is
    variable o : yposition;    
  begin  
    o := to_integer(unsigned(x));
    return o;
  end to_yposition;

  function to_spritebytenumber (x : unsigned) return spritebytenumber is
    variable o : spritebytenumber;    
  begin  
    o := to_integer(unsigned(x));
    return o;
  end to_spritebytenumber;

end victypes;
