library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity widget_to_matrix is
  port (
    cpuclock : in std_logic;

    pmod_clock : in std_logic;
    pmod_start_of_sequence : in std_logic;
    pmod_data_in : in std_logic_vector(3 downto 0);
    pmod_data_out : out std_logic_vector(1 downto 0) := "ZZ";

    matrix_col : out std_logic_vector(7 downto 0) := (others => '1');
    matrix_col_idx : in integer range 0 to 15;
    
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
  signal pmod_clock_debounced : std_logic := '1';
  signal pmod_clock_history : std_logic_vector(3 downto 0);
  
  signal matrix_ram_offset : integer range 0 to 15 := 0;
  signal keyram_wea : std_logic_vector(7 downto 0);
  signal keyram_dia : std_logic_vector(7 downto 0);
  signal matrix_dia : std_logic_vector(7 downto 0);
  
  signal enabled : std_logic := '0';
  
begin  -- behavioural

  widget_kmm: entity work.kb_matrix_ram
  port map (
    clkA => cpuclock,
    addressa => matrix_ram_offset,
    dia => matrix_dia,
    wea => keyram_wea,
    addressb => matrix_col_idx,
    dob => matrix_col
    );

  matrix_dia <= pmod_data_in & pmod_data_in;  -- replicate input to high and low nibbles
    
  process (cpuclock)
  variable keyram_write_enable : std_logic_vector(7 downto 0);
  variable keyram_offset : integer range 0 to 15 := 0;
  variable keyram_offset_tmp : std_logic_vector(2 downto 0);
  
  begin
    if rising_edge(cpuclock) then
      ------------------------------------------------------------------------
      -- Read from MEGA keyboard/joystick/expansion port PMOD interface
      ------------------------------------------------------------------------
      -- This interface has a clock, start-of-sequence signal and 4 data lines
      -- The data is pumped out in the correct order for us to just stash it
      -- into the matrix (or, at least it will when it is implemented ;)
      pmod_clock_history(3 downto 1) <= pmod_clock_history(2 downto 0);
      pmod_clock_history(0) <= pmod_clock;

      if pmod_clock_history="1111" then
        pmod_clock_debounced <= '1';
      end if;
      if pmod_clock_history="0000" then
        pmod_clock_debounced <= '0';
      end if;
      
      last_pmod_clock <= pmod_clock_debounced;

      -- Default is no write nothing at offset zero into the matrix ram.
      keyram_write_enable := x"00";
      keyram_offset := 0;
      keyram_dia <= pmod_data_in & pmod_data_in;
      -- Don't do anything until we see the line float high.
      -- this is for the hardware targets that lack these interfaces,
      -- as a protection against incorrect tri-stating etc.
      if pmod_data_in = "1111" then
        enabled <= '1';
      end if;      
      if pmod_clock_debounced='1' and last_pmod_clock='0' and enabled='1' then
        -- Data available
        if pmod_start_of_sequence='1' then
          -- Write first four bits, and set offset for next time
          keyram_write_enable := x"0F";
          matrix_offset <= 4;
          -- matrix(3 downto 0) <= pmod_data_in;
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
            keyram_offset := matrix_offset / 8;
            keyram_offset_tmp := std_logic_vector(to_unsigned(matrix_offset,3));
            -- set up proper write mask
            if keyram_offset_tmp(2) = '0' then
              keyram_write_enable := x"0F";
            else
              keyram_write_enable := x"F0";
            end if;              
            --matrix((matrix_offset +3) downto matrix_offset) <= pmod_data_in;
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
      matrix_ram_offset <= keyram_offset;
      keyram_wea <= keyram_write_enable;
    end if;
  end process;

end behavioural;
