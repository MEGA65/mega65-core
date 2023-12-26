library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity testkey is
end entity;

architecture foo of testkey is

  signal ioclock : std_logic := '1';
  signal flopled : std_logic := '1';
  signal powerled : std_logic := '1';
  signal kio8 : std_logic := '1';
  signal kio9 : std_logic := '1';
  signal kio10 : std_logic := '1';
  signal matrix_col : std_logic_vector(7 downto 0);
  signal matrix_col_idx : integer range 0 to 15 := 0;
  signal restore : std_logic := '1';
  signal capslock_out : std_logic := '1';

  signal counter : unsigned(31 downto 0) := x"00000000";
  
begin

  kbdctl0: entity work.mega65kbd_to_matrix
    port map (
      ioclock => ioclock,

      powerled => powerled,
      flopled => flopled,
            
      kio8 => kio8,
      kio9 => kio9,
      kio10 => kio10,

     matrix_col => matrix_col,
     matrix_col_idx => matrix_col_idx,
     restore => restore

      );

  kio10 <= counter(5);
  matrix_col_idx <= to_integer(counter(10 downto 8));
  
  process is
  begin
    ioclock <= '1';
    wait for 20 ns;
    ioclock <= '0';
    wait for 20 ns;

    counter <= counter + 1;

    report "matrix_col = " & to_string(matrix_col);
  end process;

end foo;
