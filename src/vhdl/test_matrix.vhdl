use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity test_matrix is
end test_matrix;

architecture behavioral of test_matrix is

  signal pixel_x_640 : integer := 0;
  signal native_x_640 : integer :=0;
  signal native_y_200 : integer :=0;
  signal native_y_400 : integer :=0;
  signal hsync : std_logic := '0';
  signal vsync : std_logic := '0';
  signal ycounter_in : unsigned(11 downto 0) := (others => '0');
  signal x_start : unsigned(11 downto 0) := to_unsigned(0,12);
  signal y_start : unsigned(11 downto 0) := to_unsigned(479-290,12);
  signal pixelclock : std_logic := '1';
  signal visual_keyboard_enable : std_logic := '1';
  signal key1 : unsigned(7 downto 0) := x"0f";
  signal key2 : unsigned(7 downto 0) := x"3c";
  signal key3 : unsigned(7 downto 0) := x"01";
  signal vgared_in : unsigned (7 downto 0) := x"a0";
  signal vgagreen_in : unsigned (7 downto 0) := x"a0";
  signal vgablue_in : unsigned (7 downto 0) := x"e0";
  signal vgared_out : unsigned (7 downto 0);
  signal vgagreen_out : unsigned (7 downto 0);
  signal vgablue_out : unsigned (7 downto 0);

  signal matrix_fetch_address : unsigned(11 downto 0);
  signal matrix_rdata : unsigned(7 downto 0);
  
  signal char_in : unsigned(7 downto 0) := x"00";
  signal char_valid : std_logic := '0';
  signal term_ready : std_logic;
  
begin
  kc0: entity work.matrix_rain_compositor
    port map(
      seed => to_unsigned(0,16),
      display_shift_in => "000",
      shift_ready_in => '0',
      mm_displayMode_in => "10",
      monitor_char_in => char_in,
      monitor_char_valid => char_valid,
      pixel_y_scale_200 => to_unsigned(2,4),
      pixel_y_scale_400 => to_unsigned(1,4),
      terminal_emulator_ready => term_ready,
      pixel_x_640 => pixel_x_640,
      ycounter_in => ycounter_in,
      hsync_in => hsync,
      vsync_in => vsync,
      clk => pixelclock,
      pixelclock => pixelclock,
      matrix_mode_enable => '1',
      secure_mode_flag => '1',

      matrix_fetch_address => matrix_fetch_address,
      matrix_rdata => matrix_rdata,
      
      vgared_in => vgared_in,
      vgagreen_in => vgagreen_in,
      vgablue_in => vgablue_in,
      vgared_out => vgared_out,
      vgagreen_out => vgagreen_out,
      vgablue_out => vgablue_out
    );
  
  vk0: entity work.visual_keyboard port map (
    native_x_640 => native_x_640,
    native_y_200 => native_y_200,
    native_y_400 => native_y_400,
    pixel_x_640_in => pixel_x_640,
    pixel_y_scale_200 => to_unsigned(2,4),
    pixel_y_scale_400 => to_unsigned(1,4),
    ycounter_in => ycounter_in,
    y_start => to_unsigned(0,12),
    x_start => to_unsigned(0,12),
    pixelclock => pixelclock,

    matrix_fetch_address => matrix_fetch_address,
    matrix_rdata => matrix_rdata,  

    visual_keyboard_enable => '0',
    keyboard_at_top => '0',
    alternate_keyboard => '0',
    instant_at_top => '0',
    key1 => x"00",
    key2 => x"00",
    key3 => x"00",
    key4 => x"00",
    touch1_valid => '0',
    touch1_x => to_unsigned(0,14),
    touch1_y => to_unsigned(0,12),
    touch2_valid => '0',
    touch2_x => to_unsigned(0,14),
    touch2_y => to_unsigned(0,12),

    vgared_in => vgared_out,
    vgagreen_in => vgagreen_out,
    vgablue_in => vgablue_out
    );
  
  process
    procedure type_char(char : character) is
    begin
        report "Typing  " & character'image(char);
        while term_ready = '0' loop
--          report "Waiting for terminal emulator to be ready.";
          wait for 10 ns;
        end loop;    
        char_in <= to_unsigned(character'pos(char),8);
        char_valid <= '1';
        while term_ready = '1' loop
          wait for 10 ns;
        end loop;
        char_valid <= '0';
        wait for 40 ns;
    end procedure;      
    procedure type_text(text : string) is
    begin
      for i in text'range loop
        type_char(text(i));
      end loop;
    end procedure;
  begin
    wait for 1 us;
    -- Enter header
    type_char(character'val(14));
    -- Clear terminal screen, including header
    type_char(character'val(147));
    -- Exit header, and continue writing
    type_char(character'val(128+14));
    type_text("line 0" & lf & cr);
    type_text("1" & lf & cr);
    type_text(" 2" & lf & cr);
    type_text("  3" & lf & cr);
    type_text("   4" & lf & cr);
    type_text("    5" & lf & cr);
    type_text("     6" & lf & cr);
    type_text("      7" & lf & cr);
    type_text("       8" & lf & cr);
    type_text("        9" & lf & cr);
    type_text("line 10" & lf & cr);
    type_text("1" & lf & cr);
    type_text("2" & lf & cr);
    type_text("3" & lf & cr);
    type_text("4" & lf & cr);
    type_text("5" & lf & cr);
    type_text("6" & lf & cr);
    type_text("7" & lf & cr);
    type_text("8" & lf & cr);
    type_text("9" & lf & cr);
    type_text("line 20" & lf & cr);
    type_text("1" & lf & cr);
    type_text("2" & lf & cr);
    type_text("3" & lf & cr);
    type_text("4" & lf & cr);
    type_text("5" & lf & cr);
    type_text("6" & lf & cr);
    type_text("7" & lf & cr);
    type_text("8" & lf & cr);
    type_text("9" & lf & cr);
    type_text("line 30" & lf & cr);
    type_text("1" & lf & cr);
    type_text("2" & lf & cr);
    type_text("3" & lf & cr);
    type_text("4" & lf & cr);
    type_text("5" & lf & cr);
    type_text("6" & lf & cr);
    type_text("A very long line that should cause problems if we don't handle the end of lines correctly" & lf & cr);
    type_text("7" & lf & cr);
    type_text("8" & lf & cr);
    type_text("9" & lf & cr);
    -- Back in header again and write some stuff there
    type_char(character'val(14));
    type_text("in the header" & lf & cr
              & "  header 2" & lf & cr
              & "  header 3" & lf & cr
              & "  header 4" & lf & cr
              & "  header 5" & lf & cr
              & character'val(128+14));

    wait for 2 sec;
  end process;

  process
  begin    
    for i in 1 to 40000000 loop
      pixelclock <= '1';
      wait for 10 ns;
      pixelclock <= '0';
      wait for 10 ns;
      pixelclock <= '1';
      wait for 10 ns;
      pixelclock <= '0';
      wait for 10 ns;
      pixelclock <= '1';
      wait for 10 ns;
      pixelclock <= '0';
      wait for 10 ns;
      if pixel_x_640 < 810 then
        pixel_x_640 <= pixel_x_640 + 1;
        if pixel_x_640 = 800 then
          hsync <= '1';
        end if;
      else
        pixel_x_640 <= 0;
        hsync <= '0';
        if ycounter_in < 485 then
          ycounter_in <= ycounter_in + 1;
          if ycounter_in = 479 then
            vsync <= '1';
          end if;
        else
          ycounter_in <= to_unsigned(0,12);
          vsync <= '0';
        end if;
      end if;
      report "PIXEL:" & integer'image(pixel_x_640)
        & ":" & integer'image(to_integer(ycounter_in))
        & ":" & to_hstring(vgared_out)
        & ":" & to_hstring(vgagreen_out)
        & ":" & to_hstring(vgablue_out);
    end loop;  -- i
    assert false report "End of simulation" severity note;
  end process;

end behavioral;
