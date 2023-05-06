use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity mouse_input is
  port (
    clk : in std_logic;
    phi_in_ntsc : in std_logic;

    amiga_mouse_enable_a : in std_logic;
    amiga_mouse_enable_b : in std_logic;
    amiga_mouse_assume_a : in std_logic;
    amiga_mouse_assume_b : in std_logic;
    
    pot_drain : buffer std_logic;
    fa_potx : in std_logic;
    fa_poty : in std_logic;
    fb_potx : in std_logic;
    fb_poty : in std_logic;

    fa_fire : in std_logic;
    fa_left : in std_logic;
    fa_right : in std_logic;
    fa_up : in std_logic;
    fa_down : in std_logic;

    fb_fire : in std_logic;
    fb_left : in std_logic;
    fb_right : in std_logic;
    fb_up : in std_logic;
    fb_down : in std_logic;

    -- When using an Amiga mouse, we need to override the up direction, which
    -- is right button on an Amiga mouse
    -- We also mask out the joystick movements that would be seen from the
    -- digital inputs.
    fa_left_out : out std_logic :='1';
    fa_right_out : out std_logic :='1';
    fa_up_out : out std_logic :='1';
    fa_down_out : out std_logic :='1';
    
    fb_left_out : out std_logic :='1';
    fb_right_out : out std_logic :='1';
    fb_up_out : out std_logic :='1';
    fb_down_out : out std_logic :='1';
        
    mouse_debug : out unsigned(7 downto 0);
    
    pota_x : out unsigned(7 downto 0) := x"33";
    pota_y : out unsigned(7 downto 0) := x"44";
    potb_x : out unsigned(7 downto 0) := x"55";
    potb_y : out unsigned(7 downto 0) := x"66"
    );
end mouse_input;

architecture behavioural of mouse_input is

  signal pot_counter : integer := 0;
  signal phi_counter : integer := 0;
  signal pota_x_counter : integer := 0;
  signal pota_y_counter : integer := 0;
  signal potb_x_counter : integer := 0;
  signal potb_y_counter : integer := 0;

  -- Flags for whether we think we have an amiga mouse plugged in or not
  -- If UP+DOWN or LEFT+RIGHT, and pots are open or short circuit, then it is an amiga mouse
  -- If POTs are not open/short circuit, then it must not be an Amiga mouse,
  -- but could be a 1351.
  -- Then it is just a case of separating Amiga mouse from joystick. Basically
  -- if we don't see UP+DOWN/LEFT+RIGHT for a while, then we conclude it is a joystick.
  -- ... but we keep driving the POTs as though it were an amiga mouse until
  -- such time as we see the pots no longer at the edges
  -- In fact, we can safely always pass the joystick directions through, even
  -- if we think it is an amiga mouse.
  -- The only other catch is we have to have two consecutive pot reads to be
  -- sure it isn't an amiga mouse, in case the button is pressed during a POT
  -- sampling sequence
  signal ma_amiga_mode : std_logic := '0';
  signal mb_amiga_mode : std_logic := '0';
  signal ma_amiga_pots : std_logic := '0';
  signal mb_amiga_pots : std_logic := '0';
  signal ma_amiga_mode_timeout : integer := 0;
  signal mb_amiga_mode_timeout : integer := 0;
  
  -- Integrated Amiga mouse positions
  signal ma_x : unsigned(6 downto 0) := "1111111";
  signal ma_y : unsigned(6 downto 0) := "1111111";
  signal mb_x : unsigned(6 downto 0) := "1111111";
  signal mb_y : unsigned(6 downto 0) := "1111111";

  -- POT values read from physical port
  signal pota_x_internal : unsigned(7 downto 0) := x"00";
  signal pota_y_internal : unsigned(7 downto 0) := x"00";
  signal potb_x_internal : unsigned(7 downto 0) := x"00";
  signal potb_y_internal : unsigned(7 downto 0) := x"00";

  -- Are the real POT values at either extremity of value?
  -- (if so, it can't be a 1351, but might be amiga mouse)
  signal potsa_at_edge : std_logic := '0';
  signal potsb_at_edge : std_logic := '0';
  
  -- Remember quadrature positions for Amiga mouse
  signal last_fa_leftup : std_logic_vector(1 downto 0) := "11";
  signal last_fa_rightdown : std_logic_vector(1 downto 0) := "11";
  signal last_fb_leftup : std_logic_vector(1 downto 0) := "11";
  signal last_fb_rightdown : std_logic_vector(1 downto 0) := "11";
  signal last_amiga_mouse_enable_a : std_logic := '0';
  signal last_amiga_mouse_enable_b : std_logic := '0';
  
begin

  process(clk) is
    variable joybits : std_logic_vector(3 downto 0);
  begin
    if rising_edge(clk) then

      mouse_debug(0) <= potsa_at_edge;
      mouse_debug(1) <= ma_amiga_mode;
      mouse_debug(2) <= potsb_at_edge;
      mouse_debug(3) <= mb_amiga_mode;
      mouse_debug(5 downto 4) <= unsigned(last_fb_leftup);
      mouse_debug(7 downto 6) <= unsigned(last_fb_rightdown);

      last_amiga_mouse_enable_a <= amiga_mouse_enable_a;
      last_amiga_mouse_enable_b <= amiga_mouse_enable_b;
      if amiga_mouse_enable_a='1' and last_amiga_mouse_enable_a='0' then
        ma_amiga_mode <= (not (fa_left and fa_right and fa_down and fa_up)) and amiga_mouse_assume_a;
        ma_amiga_pots <= amiga_mouse_assume_a;
      end if;
      if amiga_mouse_enable_b='1' and last_amiga_mouse_enable_b='0' then
        mb_amiga_mode <= (not (fb_left and fb_right and fb_down and fb_up)) and amiga_mouse_assume_b;
        mb_amiga_pots <= amiga_mouse_assume_b;
      end if;
      
      if amiga_mouse_enable_a='0' then
        ma_amiga_mode <= '0';
        ma_amiga_pots <= '0';
        ma_amiga_mode_timeout <= 0;
      end if;
      if amiga_mouse_enable_b='0' then
        mb_amiga_mode <= '0';
        mb_amiga_pots <= '0';
        mb_amiga_mode_timeout <= 0;
      end if;
      
      -- Timeout Amiga mode interpretation of mouse after
      -- a period of all digital lines being relaxed.
      -- We don't just assume joystick immediately, because slow
      -- mouse movement can have all lines relaxed for a little while.
      -- This leaves a 1 in 16 chance of glitchy mouse/joystick
      -- interpretation if an amiga mouse is plugged in, and is moved
      -- only a single quad in either axis after having been stationary
      -- for some time.
      if ma_amiga_mode_timeout /= 0 then
        ma_amiga_mode_timeout <= ma_amiga_mode_timeout - 1;
      end if;
      if ma_amiga_mode_timeout = 1 then
        ma_amiga_mode <= '0';
      end if;
      if mb_amiga_mode_timeout /= 0 then
        mb_amiga_mode_timeout <= mb_amiga_mode_timeout - 1;
      end if;
      if mb_amiga_mode_timeout = 1 then
        mb_amiga_mode <= '0';
      end if;

      -- If all lines are high, we can't be sure it is an amiga mouse,
      -- but we don't want to cause glitchy behaviour if the mouse is moved
      -- slowly, so we have a 5 second timeout before we think it is a joystick
      -- (i.e., about the time it takes to unplug and replug a joystick/mouse.)
      -- This does mean if you are using a joystick/mouse switcher with an
      -- Amiga mouse you have to leave the joystick motionless for 5 seconds in
      -- 1 in 16 cases before it will be properly recognised by the MEGA65.
      if ((fa_up and fa_down and fa_left and fa_right) = '0') and (ma_amiga_mode='1') then
        ma_amiga_mode_timeout <= 250000000;
      end if;
      if ((fb_up and fb_down and fb_left and fb_right) = '0') and (mb_amiga_mode='1') then
        mb_amiga_mode_timeout <= 250000000;
      end if;
      
      
      -- Work out if we think we have an amiga mouse connected
      if ((pota_x_internal(7 downto 2) = "111111") or (pota_x_internal(7 downto 2) = "000000"))
        and ((pota_y_internal(7 downto 2) = "111111") or (pota_y_internal(7 downto 2) = "000000")) then
        potsa_at_edge <= '1';
      else
        potsa_at_edge <= '0';
        ma_amiga_mode <= '0';
        ma_amiga_pots <= '0';
      end if;
      if (potb_x_internal(7 downto 2) = "111111" or (potb_x_internal(7 downto 2) = "000000"))
        and (potb_y_internal(7 downto 2) = "111111" or (potb_y_internal(7 downto 2) = "000000")) then
        potsb_at_edge <= '1';
      else
        potsb_at_edge <= '0';
        mb_amiga_mode <= '0';
        mb_amiga_pots <= '0';
      end if;
      if (((fa_up or fa_down) = '0') or ((fa_left or fa_right) = '0'))
         and (potsa_at_edge='1') then
        ma_amiga_mode <= amiga_mouse_enable_a;
        ma_amiga_pots <= amiga_mouse_enable_a;
        ma_amiga_mode_timeout <= 250000000;
        if ma_amiga_pots = '0' then
          -- Copy existing pot value in to avoid mouse jumping when swapping
          -- between 1351 and amiga mouse
          ma_x(5 downto 0) <= pota_x_internal(5 downto 0);
          ma_x(6) <= not pota_x_internal(6);
          ma_y(5 downto 0) <= pota_y_internal(5 downto 0);
          ma_y(6) <= not pota_y_internal(6);
        end if;
      end if;
      if (((fb_up or fb_down) = '0') or ((fb_left or fb_right) = '0'))
         and (potsb_at_edge='1') then
        mb_amiga_mode <= amiga_mouse_enable_b;
        mb_amiga_pots <= amiga_mouse_enable_b;
        mb_amiga_mode_timeout <= 250000000;
        if mb_amiga_pots = '0' then
          -- Copy existing pot value in to avoid mouse jumping when swapping
          -- between 1351 and amiga mouse
          mb_x(5 downto 0) <= potb_x_internal(5 downto 0);
          mb_x(6) <= not potb_x_internal(6);
          mb_y(5 downto 0) <= potb_y_internal(5 downto 0);
          mb_y(6) <= not potb_y_internal(6);
        end if;
      end if;
      last_fa_leftup <= fa_left & fa_up;
      last_fa_rightdown <= fa_right & fa_down;
      last_fb_leftup <= fb_left & fb_up;
      last_fb_rightdown <= fb_right & fb_down;
      if ma_amiga_mode='1' then
        -- Map Amiga right button from POTY to UP
        fa_up_out <= pota_x_internal(7);
        fa_left_out <= '1';
        fa_right_out <= '1';
        fa_down_out <= '1';
        joybits := fa_right & fa_down & last_fa_rightdown;
        case joybits is
          when "0010" | "1011" | "1101" | "0100" =>
            if ma_x /= "1111111" then
              ma_x <= ma_x + 1;
            else
              ma_x <= "0000000";
            end if;
          when "1110" | "0111" | "0001" | "1000" =>
            if ma_x /= "0000000" then
              ma_x <= ma_x - 1;
            else
              ma_x <= "1111111";
            end if;
          when others => null;
        end case;
        joybits := fa_left & fa_up & last_fa_leftup;
        case joybits is
          when "1110" | "0111" | "0001" | "1000" =>
            if ma_y /= "1111111" then
              ma_y <= ma_y + 1;
            else
              ma_y <= "0000000";
            end if;
          when "0010" | "1011" | "1101" | "0100" =>
            if ma_y /= "0000000" then
              ma_y <= ma_y - 1;
            else
              ma_y <= "1111111";
            end if;
          when others => null;
        end case;
      else
        fa_up_out <= fa_up;
        fa_left_out <= fa_left;
        fa_right_out <= fa_right;
        fa_down_out <= fa_down;
      end if;
      if mb_amiga_mode='1' then
        fb_up_out <= potb_x_internal(7);
        fb_left_out <= '1';
        fb_right_out <= '1';
        fb_down_out <= '1';
        joybits := fb_right & fb_down & last_fb_rightdown;
        case joybits is
          when "0010" | "1011" | "1101" | "0100" =>
            if mb_x /= "1111111" then
              mb_x <= mb_x + 1;
            else
              mb_x <= "0000000";
            end if;
          when "1110" | "0111" | "0001" | "1000" =>
            if mb_x /= "0000000" then
              mb_x <= mb_x - 1;
            else
              mb_x <= "1111111";
            end if;
          when others => null;
        end case;
        joybits := fb_left & fb_up & last_fb_leftup;
        case joybits is
          when "1110" | "0111" | "0001" | "1000" =>
            if mb_y /= "1111111" then
              mb_y <= mb_y + 1;
            else
              mb_y <= "0000000";
            end if;
          when "0010" | "1011" | "1101" | "0100" =>
            if mb_y /= "0000000" then
              mb_y <= mb_y - 1;
            else
              mb_y <= "1111111";
            end if;
          when others => null;
        end case;
      else
        fb_up_out <= fb_up;
        fb_left_out <= fb_left;
        fb_right_out <= fb_right;
        fb_down_out <= fb_down;
      end if;

      if ma_amiga_pots='1' then
        pota_x(5 downto 0) <= ma_x(5 downto 0);
        pota_x(6) <= ma_x(6) xor '1';
        pota_x(7) <= ma_x(6);
        pota_y(5 downto 0) <= ma_y(5 downto 0);
        pota_y(6) <= ma_y(6) xor '1';
        pota_y(7) <= ma_y(6);
      else
        pota_x <= pota_x_internal;
        pota_y <= pota_y_internal;
      end if;
      if mb_amiga_pots='1' then
        potb_x(5 downto 0) <= mb_x(5 downto 0);
        potb_x(6) <= mb_x(6) xor '1';
        potb_x(7) <= mb_x(6);
        potb_y(5 downto 0) <= mb_y(5 downto 0);
        potb_y(6) <= mb_y(6) xor '1';
        potb_y(7) <= mb_y(6);
      else
        potb_x <= potb_x_internal;
        potb_y <= potb_y_internal;
      end if;

      -- At ~1MHz C64 bus clock
      if phi_in_ntsc='1' then
        phi_counter <= 0;
        if pot_counter < 513 then
          pot_counter <= pot_counter + 1;
          if pot_counter = 0 then
            -- Begin draining capacitor
            pot_drain <= '1';
          elsif pot_counter = 256  then
            -- Stop draining, begin counting
            pot_drain <= '0';
          elsif (pot_counter > 257) then
            if fa_potx='0' then
              if pota_x_counter /= 255 then
                pota_x_counter <= pota_x_counter + 1;
              end if;
            end if;
            if fa_poty='0' then
              if pota_y_counter /= 255 then
                pota_y_counter <= pota_y_counter + 1;
              end if;
            end if;
            if fb_potx='0' then
              if potb_x_counter /= 255 then
                potb_x_counter <= potb_x_counter + 1;
              end if;
            end if;
            if fb_poty='0' then
              if potb_y_counter /= 255 then
                potb_y_counter <= potb_y_counter + 1;
              end if;
            end if;
          end if;
        else
          pot_counter <= 0;
          pota_x_internal <= to_unsigned(pota_x_counter,8);
          pota_y_internal <= to_unsigned(pota_y_counter,8);
          potb_x_internal <= to_unsigned(potb_x_counter,8);
          potb_y_internal <= to_unsigned(potb_y_counter,8);
          pota_x_counter <= 0;
          pota_y_counter <= 0;
          potb_x_counter <= 0;
          potb_y_counter <= 0;
        end if;		  
      end if;

    end if;
  end process;

end behavioural;
