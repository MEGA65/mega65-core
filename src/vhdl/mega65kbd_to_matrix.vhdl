library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity mega65kbd_to_matrix is
  port (
    ioclock : in std_logic;

    flopled : in std_logic;
    powerled : in std_logic;
    
    kio8 : out std_logic; -- clock to keyboard
    kio9 : out std_logic; -- data output to keyboard
    kio10 : in std_logic; -- data input from keyboard

    matrix_col : out std_logic_vector(7 downto 0) := (others => '1');
    matrix_col_idx : in integer range 0 to 8;
    
    restore : out std_logic := '1';
    capslock_out : out std_logic := '1'
    
    );

end entity mega65kbd_to_matrix;

architecture behavioural of mega65kbd_to_matrix is

  signal matrix_offset : integer range 0 to 255 := 252;

  signal matrix_ram_offset : integer range 0 to 15 := 0;
  signal keyram_wea : std_logic_vector(7 downto 0);
  signal keyram_dia : std_logic_vector(7 downto 0);
  signal matrix_dia : std_logic_vector(7 downto 0);
  
  signal enabled : std_logic := '0';

  signal clock_divider : integer range 0 to 255 := 0;
  signal kbd_clock : std_logic := '0';
  signal phase : integer range 0 to 255 := 0;
  signal sync_pulse : std_logic := '0';
  
  signal output_vector : std_logic_vector(127 downto 0);
  
begin  -- behavioural

  widget_kmm: entity work.kb_matrix_ram
    port map (
      clkA => ioclock,
      addressa => matrix_ram_offset,
      dia => matrix_dia,
      wea => keyram_wea,
      addressb => matrix_col_idx,
      dob => matrix_col
      );

  process (ioclock)
    variable keyram_write_enable : std_logic_vector(7 downto 0);
    variable keyram_offset : integer range 0 to 15 := 0;
    variable keyram_offset_tmp : std_logic_vector(2 downto 0);
    
  begin
    if rising_edge(ioclock) then
      ------------------------------------------------------------------------
      -- Read from MEGA65R2 keyboard
      ------------------------------------------------------------------------
      -- Process is to run a clock at a modest rate, and periodically send
      -- a sync pulse, and clock in the key states, while clocking out the
      -- LED states.
      
      -- Default is no write nothing at offset zero into the matrix ram.
      keyram_write_enable := x"00";
      keyram_offset := 0;

      if clock_divider /= 15 then
        clock_divider <= clock_divider + 1;
      else
        clock_divider <= 0;

        kbd_clock <= not kbd_clock;
        kio8 <= kbd_clock or sync_pulse;
        
        if kbd_clock='0' then
          if phase = 127 then
            -- Reset to start
            sync_pulse <= '1';
            output_vector <= (others => '0');
            if flopled='1' then
              output_vector(23 downto 0) <= x"0000FF";
              output_vector(47 downto 24) <= x"0000FF";
            end if;
            if powerled='1' then
              output_vector(71 downto 48) <= x"0000FF";
              output_vector(95 downto 72) <= x"0000FF";
            end if;
          elsif phase = 140 then
            sync_pulse <= '0';
            phase <= 0;
          else
            -- Output/input next bit
            phase <= phase + 1;

            kio9 <= output_vector(0);
            output_vector(126 downto 0) <= output_vector(127 downto 1);
            output_vector(127) <= '0';

            matrix_offset <= phase/8;
            matrix_dia <= (others => kio10); -- present byte of input bits to
                                             -- ram for writing
            
            case (phase mod 8) is
              when 0 => keyram_write_enable := x"01";
              when 1 => keyram_write_enable := x"02";
              when 2 => keyram_write_enable := x"04";
              when 3 => keyram_write_enable := x"08";
              when 4 => keyram_write_enable := x"10";
              when 5 => keyram_write_enable := x"20";
              when 6 => keyram_write_enable := x"40";
              when 7 => keyram_write_enable := x"80";
              when others => null;
            end case;
          end if;
          
          matrix_ram_offset <= keyram_offset;
          keyram_wea <= keyram_write_enable;
        end if;
      end if;
    end if;
  end process;

end behavioural;
