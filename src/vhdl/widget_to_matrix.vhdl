library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity widget_to_matrix is
  port (
    ioclock : in std_logic;
    reset_in : in std_logic;

    pmod_clock : in std_logic;
    pmod_start_of_sequence : in std_logic;
    pmod_data_in : in std_logic_vector(3 downto 0);
    pmod_data_out : out std_logic_vector(1 downto 0) := "ZZ";

    matrix : out std_logic_vector(71 downto 0) := (others => '1');
    restore : out std_logic := '1';
    capslock_out : out std_logic := '1';
    reset_out : out std_logic := '1';
    joya : out std_logic_vector(4 downto 0) := (others  => '1');
    joyb : out std_logic_vector(4 downto 0) := (others => '1')
    
    );

end entity widget_to_matrix;

architecture behavioural of widget_to_matrix is

  signal matrix_offset : integer range 0 to 255 := 252;
  signal last_pmod_clock : std_logic := '1';
  
begin  -- behavioural

  process (ioclock)
  begin
    if rising_edge(ioclock) then
      ------------------------------------------------------------------------
      -- Read from MEGA keyboard/joystick/expansion port PMOD interface
      ------------------------------------------------------------------------
      -- This interface has a clock, start-of-sequence signal and 4 data lines
      -- The data is pumped out in the correct order for us to just stash it
      -- into the matrix (or, at least it will when it is implemented ;)
      last_pmod_clock <= pmod_clock;
      if pmod_clock='1' and last_pmod_clock='0' then
        -- Data available
        if pmod_start_of_sequence='1' then
          -- Write first four bits, and set offset for next time
          matrix_offset <= 4;
          matrix(3 downto 0) <= pmod_data_in;
          -- First two bits of output from FPGA to input PCB is the status of
          -- the two LEDs: power LED is on when CPU is not in hypervisor mode,
          -- drive LED shows F011 drive status.
--          pmod_data_out(0) <= not cpu_hypervisor_mode;
--          pmod_data_out(1) <= drive_led_out;
        else
          -- Clear output bits for bit positions for which we yet have no assignment
          pmod_data_out <= "00";
          
          if matrix_offset < 252 then
            matrix_offset <= matrix_offset+ 4;
          end if;
          -- Read keyboard matrix when required
          if matrix_offset < 72 then
            matrix((matrix_offset +3) downto matrix_offset) <= pmod_data_in;
          end if;
          -- Joysticks + restore + capslock + reset? (72-79, 80-87)
          if matrix_offset = 72 then
            -- joy 1 directions
            joya(3 downto 0) <= pmod_data_in;
          end if;
          if matrix_offset = 76 then
            -- restore is active low, like all other keys
            restore <= pmod_data_in(3);
            capslock_out <= pmod_data_in(2);
            joya(4) <= pmod_data_in(0);
          end if;
          if matrix_offset = 80 then
            -- joy 2 directions
            joyb(3 downto 0) <= pmod_data_in;
          end if;
          if matrix_offset = 84 then
            reset_out <= pmod_data_in(3);
            joyb(4) <= pmod_data_in(0);
          end if;
        end if;
      end if;
    end if;
  end process;

end behavioural;
