use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity keyboard_to_matrix is
  port (Clk : in std_logic;        
        porta_pins : inout  std_logic_vector(7 downto 0) := (others => 'Z');
        portb_pins : in  std_logic_vector(7 downto 0);
        keyboard_column8_out : out std_logic := '1';
        key_left : in std_logic;
        key_up : in std_logic;

        scan_mode : in std_logic_vector(1 downto 0);

        scan_rate : in unsigned(7 downto 0);
        
        -- Virtualised keyboard matrix
        matrix_col : out std_logic_vector(7 downto 0) := (others => '1');
        matrix_col_idx : in integer range 0 to 15
        
        );

end keyboard_to_matrix;

architecture behavioral of keyboard_to_matrix is
  -- Scan slow enough for the keyboard (rate is set via scan_rate)
  -- Actual scan rate = CPU clock / scan_rate.
  signal counter : integer := 0;

  signal scan_phase : integer range 0 to 15 := 0; -- reset entry phase

  signal enabled : std_logic := '0';

  signal key_left_last : unsigned(7 downto 0) := x"00";
  signal key_up_last : unsigned(7 downto 0) := x"00";
  
  signal keyram_wea : std_logic_vector(7 downto 0);
  signal keyram_mask : std_logic_vector(7 downto 0);
  signal matrix_dia : std_logic_vector(7 downto 0);

  signal right_shift : std_logic := '0';
begin
  
  kb_kmm: entity work.kb_matrix_ram
  port map (
    clkA => Clk,
    addressa => scan_phase,
    dia => matrix_dia,
    wea => keyram_wea,
    addressb => matrix_col_idx,
    dob => matrix_col
    );

  matrix_dia <= portb_pins(7 downto 0) and keyram_mask;
    
  process (clk)
    variable next_phase : integer range 0 to 15;
    variable scan_mask : std_logic_vector(7 downto 0);
  begin
    
    if rising_edge(clk) then

      -- Present virtualised keyboard
      -- XXX Note that the virtualised keyboard is out by one column,
      -- which we correct at the hardware by rearranging the colunms
      -- we connect. This just leaves left and up that simulate specific
      -- keys that we have to shift left one column to match
      scan_mask := x"FF";
      -- We delay asserting the UP/LEFT keys for one round, until
      -- the shift key has had time to go down.
      -- Basically the problem is if the UP or LEFT keys were getting
      -- pressed after phase 5 but before phase 8.
      if scan_phase = 8 then
        key_left_last(0) <= key_left;
        key_left_last(7 downto 1) <= key_left_last(6 downto 0);
        key_up_last(0) <= key_up;
        key_up_last(7 downto 1) <= key_up_last(6 downto 0);

        if key_left = '1' and key_left_last = x"FF" then
          -- Assert RIGHT key
          if right_shift = '1' then
            scan_mask(2) := '0';
          end if;
        end if;
        if key_up = '1' and key_up_last = x"FF" then
          -- Assert DOWN key
          if right_shift = '1' then
            scan_mask(7) := '0';
          end if;
        end if;
      elsif scan_phase = 5 then
        -- Assert shift early, and keep it asserted until after
        -- the cursor keys have had ample time to clear
        if key_left_last /= x"00" or key_up_last /= x"00" then
          -- Assert right shift
          scan_mask(52 mod 8) := '0';
          right_shift <= '1';
        else
          right_shift <= '0';
        end if;
      end if;

      keyram_mask <= scan_mask;
      
      -- Put positive charge on the keyboard pins we are going to read,
      -- to make sure they float high.  Then make them tri-state just
      -- before we read them, so that we don't have cross-driving
      -- problems that cause multiple key presses on the same row/column
      -- to lead to too many pull-ups combining to leave the input
      -- voltage too high to register a key press.
--      if counter<8 then
--        portb_pins <= (others => 'Z');
--      else
--        portb_pins <= (others => 'Z');
--      end if;
      
      keyram_wea <= x"00";
      
      -- Scan physical keyboard
      if counter=0 then
        counter <= to_integer(scan_rate);
--        report "scan_phase = " & integer'image(scan_phase)
--          & ", portb_pins = " & to_string(portb_pins)
--          & ", porta_pins = " & to_string(porta_pins);
        -- Read the appropriate matrix row or joysticks state
--        report "matrix = " & to_string(matrix_internal);

        -- Scan the keyboard
        -- Resistance of keyboard is ~175ohms internally (on shift-lock)
        -- and then there is a 100ohm resistor on both the row and column
        -- lines. 
        -- As a result, pressing a key only drags a high-impedence input
        -- line down to ~2.6v, which is not low enough to trigger a logic
        -- low.
        -- Even shorting the keyboard pins isn't enough to make the difference,
        -- as the voltage drops to only ~2v, which is still too high to be
        -- a 3.3V LVCMOS logic low.
        -- This is weird, however, as there should still be enough
        -- resistance on the interal pullup of the FPGA (>13K apparently),
        -- that we should still be able to pull the line low enough to sense.
        -- Further, pressing multiple keys on the same column results in the
        -- voltage not pulling down as low, suggesting that each row line
        -- has a pull-up on it.
        -- Driving columns low works just fine, however. What it seems like is
        -- that the row pins (portb_pins) is being driven high, instead of
        -- tristates, i.e., '1' instead of 'H' or 'Z'.

        -- We got this sorted out in ISE, but now under Vivado, we have the same
        -- problem again. (eg. right-shift + M doesn't work).  However, as we will
        -- be moving to the fancy new keyboard that will feed the matrix data
        -- directly in, rather than being scanned in the old way, it isn't such
        -- an issue, although it would still be really nice to figure it out and
        -- fix it.

        -- Don't enable if we see pins staying tied low
        if portb_pins = "11111111" then
          enabled <= '1';
        end if;

        if enabled='1' then
          keyram_wea <= x"FF";
        end if;

        -- Select lines for next column
        if scan_phase < 8 then
          next_phase := scan_phase + 1;
        else
          next_phase := 0;
        end if;
        scan_phase <= next_phase;
        report "scan_phase = " & integer'image(scan_phase)
          &  ", next_phase = " & integer'image(next_phase);
        for i in 0 to 7 loop
          if next_phase = i then
            porta_pins(i) <= '0';
          else
            porta_pins(i) <= '1';
          end if;
        end loop;
        if scan_phase = 7 then
          porta_pins <= (others => '1');
          keyboard_column8_out <= '0';
          report "probing column 8";
        else
          keyboard_column8_out <= '1';
        end if;
      else
        -- Keep counting down to next scan event
        counter <= counter - 1;
      end if;
    end if;
  end process;
end behavioral;


    
