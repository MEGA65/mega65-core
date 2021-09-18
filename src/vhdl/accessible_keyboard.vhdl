library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity accessible_keyboard is
  port (
    pixelclock : in std_logic;
    cpuclock : in std_logic;

    -- The button, active low
    the_button : in std_logic;
    
    -- pixel clock
    accessible_row : out integer range 0 to 255 := 255;
    accessible_key : out unsigned(6 downto 0) := to_unsigned(127,7);

    -- cpuclock
    accessible_key_event : out unsigned(7 downto 0) := x"7f";
    accessible_key_enable : in std_logic    
    
    );
end accessible_keyboard;

architecture behavioural of accessible_keyboard is

  signal osk_active : std_logic := '0';
  
  -- Hold key as pressed for a while so the user can see what would be pressesd
  constant key_hold_time : integer := 10000000;
  signal key_up_countdown : integer := 0;
  
  signal button_counter : integer := 0;
  
  signal accessible_col : integer range 0 to 255 := 0;
  signal accessible_row_drive : integer range 0 to 255 := 255;
  signal accessible_key_drive : unsigned(6 downto 0) := to_unsigned(127,7);
  signal selected_row : integer range 0 to 255 := 255;
  
  -- 1/3 second between advancing to the next phase of the cylce
  constant cycle_interval : integer := 40500000 / 3;

  signal cycle_counter : integer := 0;

  -- Are we selecting a row or a key in a row?
  signal selecting_row : std_logic := '1';

  type key_row_t is array (0 to 15) of integer range 0 to 127;
  type key_array_t is array(1 to 6) of key_row_t;

  -- Each row of keys that we cycle through should have at least one null value
  -- i.e., a 127, which corresponds to no key. So if the user has selected the
  -- wrong key row, they can click when no key is being pressed, and it will
  -- revert to cycling through the rows.
  signal key_rows : key_array_t :=
    ( 1 => ( 63, 127, 71, 66, 64, 127, 4, 5, 6, 3, 127, 68, 69, 70, 67, 127 ),
      2 => ( 57, 56, 59, 8, 11, 16, 19, 24, 27, 32, 35, 40, 43, 48, 51, 0 ),
      -- RESTORE has pseudo key 81 = $51
      3 => ( 65, 62, 9, 14, 17, 22, 25, 30, 33, 38, 41, 46, 49, 54, 81, 127 ),
      4 => ( 58, 15, 10, 13, 18, 21, 26, 29, 34, 37, 42, 45, 50, 53, 1, 127 ),
      -- cursor up has pseudo key 82 = $52
      5 => ( 61, 15, 12, 23, 20, 31, 28, 39, 36, 47, 44, 55, 52, 82, 127, 127 ),
      -- We repeat SPACE and cursor keys 3 times, so we still have some no-key
      -- slots for recovering from accidental row selection
      6 => ( 60, 83, 7, 2, 60, 83, 7, 2, 60, 83, 7, 2, 127, 127, 127, 127 )
      );
  
begin

  process (cpuclock,pixelclock) is
  begin
    if rising_edge(cpuclock) then
      if the_button='1' then
        button_counter <= 0;
      else
        -- Release keys after shot press
        if key_up_countdown /= 0 then
          key_up_countdown <= key_up_countdown - 1;
          if key_up_countdown = 1 then
            accessible_key_event(7) <= '1';
          end if;
        end if;
        
        -- Get debounced button status
        if button_counter = 100 and osk_active='1' then
          if selecting_row = '1' then            
            case accessible_row_drive is
              -- RETURN
              when 7 => accessible_key_event <= to_unsigned(1,8);
                        key_up_countdown <= key_hold_time;
              -- (right) SHIFT
              when 8 => accessible_key_event <= to_unsigned(52,8);
                        key_up_countdown <= key_hold_time;
              -- SPACE
              when 9 => accessible_key_event <= to_unsigned(60,8);
                        key_up_countdown <= key_hold_time;
              when others =>
                -- Else no key highlighted
--                accessible_key_event <= to_unsigned(127,8);
                -- Begin scanning columns of this row
                selecting_row <= '0';
                accessible_col <= 0;
                selected_row <= 1 + accessible_row_drive;
                -- Don't keep showing the row
                accessible_row_drive <= 255;
            end case;          
          else
            selecting_row <= '1';
            if accessible_row_drive < 7 then 
              accessible_key_event <= to_unsigned(key_rows(selected_row)(accessible_col),8);
              key_up_countdown <= key_hold_time;
            else
            end if;
          end if;
        end if;
        button_counter <= button_counter + 1;
        if button_counter = 81000000 then
          -- Toggle OSK          
          button_counter <= 0;

          if osk_active = '1' then
            osk_active <= '0';
            accessible_key_event <= x"FE"; -- Turn OSK off
          else
            osk_active <= '1';
            accessible_key_event <= x"FD"; -- Turn OSK on
          end if;
        end if;
      end if;
      if cycle_counter < cycle_interval then
        cycle_counter <= cycle_counter + 1;
      else
        cycle_counter <= 0;
        if selecting_row = '1' then
          -- Cycling through rows
          -- 6 real rows, plus SPACE, RETURN and SHIFT = 9 rows
          accessible_row_drive <= accessible_row_drive + 1;
          case accessible_row_drive+1 is
            -- RETURN
            when 7 => accessible_key_drive <= to_unsigned(1,7);
            -- (right) SHIFT
            when 8 => accessible_key_drive <= to_unsigned(52,7);
            -- SPACE
            when 9 => accessible_key_drive <= to_unsigned(60,7);
            when others =>
              -- Else no key highlighted
              accessible_key_drive <= to_unsigned(127,7);
          end case;          

          -- Loop around at the end
          if accessible_row_drive = 9 then
            accessible_row_drive <= 1;
          end if;
        else
          -- Cycling through keys in a row
          if accessible_col < 15 then
            accessible_col <= accessible_col + 1;
          else
            accessible_col <= 0;
          end if;
          if accessible_row_drive < 7 then
          case accessible_row_drive+1 is
            -- SPACE
            when 7 => accessible_key_drive <= to_unsigned(60,7);
            -- RETURN
            when 8 => accessible_key_drive <= to_unsigned(1,7);
            -- (left) SHIFT
            when 9 => accessible_key_drive <= to_unsigned(15,7);
            when others =>
              accessible_key_drive <= to_unsigned(key_rows(selected_row)(accessible_col),7);
          end case;          
          end if;
        end if;
      end if;
      if accessible_key_enable='0' then
        accessible_key_event <= x"7F";
      end if;
    end if;
    if rising_edge(pixelclock) then
      accessible_row <= accessible_row_drive;
      accessible_key <= accessible_key_drive;
    end if;
    
  end process;

end behavioural;
