use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity mouse_input is
  port (
    clk : in std_logic;

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
    fa_up_out : out std_logic := '1';
    fb_up_out : out std_logic := '1';
    
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
  -- In fact, we can safely always pass the joystick directions through, even
  -- if we think it is an amiga mouse.
  -- The only other catch is we have to have two consecutive pot reads to be
  -- sure it isn't an amiga mouse, in case the button is pressed during a POT
  -- sampling sequence
  signal ma_amiga_mode : std_logic := '0';
  signal mb_amiga_mode : std_logic := '0';

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
  
begin

  process(clk) is
    variable joybits : std_logic_vector(3 downto 0);
  begin
    if rising_edge(clk) then

      mouse_debug(0) <= potsa_at_edge;
      mouse_debug(1) <= ma_amiga_mode;
      mouse_debug(2) <= potsb_at_edge;
      mouse_debug(3) <= mb_amiga_mode;
      mouse_debug(5 downto 4) <= unsigned(last_fa_leftup);
      mouse_debug(7 downto 6) <= unsigned(last_fa_rightdown);
      
      -- Work out if we think we have an amiga mouse connected
      if (pota_x_internal(7 downto 2) = "111111" or pota_x_internal(7 downto 2) = "000000")
        and (pota_y_internal(7 downto 2) = "111111" or pota_y_internal(7 downto 2) = "000000") then
        potsa_at_edge <= '1';
      else
        potsa_at_edge <= '0';
        ma_amiga_mode <= '0';
      end if;
      if (potb_x_internal(7 downto 2) = "111111" or potb_x_internal(7 downto 2) = "000000")
        and (potb_y_internal(7 downto 2) = "111111" or potb_y_internal(7 downto 2) = "000000") then
        potsb_at_edge <= '1';
      else
        potsb_at_edge <= '0';
        mb_amiga_mode <= '0';
      end if;
      if (((fa_up or fa_down) = '0') or ((fa_left or fa_right) = '0'))
         and (potsa_at_edge='1') then
        ma_amiga_mode <= '1';
      end if;
      if (((fb_up or fb_down) = '0') or ((fb_left or fb_right) = '0'))
         and (potsb_at_edge='1') then
        mb_amiga_mode <= '1';
      end if;
      last_fa_leftup <= fa_left & fa_up;
      last_fa_rightdown <= fa_right & fa_down;
      last_fb_leftup <= fb_left & fb_up;
      last_fb_rightdown <= fb_right & fb_down;
      if ma_amiga_mode='1' then
        -- Map Amiga right button from POTY to UP
        fa_up_out <= pota_y_internal(7);            
        joybits := fa_right & fa_down & last_fa_rightdown;
        case joybits is
          when "1110" | "0111" | "0001" | "1000" =>
            if ma_x /= "1111111" then
              ma_x <= ma_x + 1;
            else
              ma_x <= "0000000";
            end if;
          when "0010" | "1011" | "1101" | "0100" =>
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
      end if;
      if mb_amiga_mode='1' then
        fb_up_out <= potb_y_internal(7);            
        joybits := fb_right & fb_down & last_fb_rightdown;
        case joybits is
          when "1110" | "0111" | "0001" | "1000" =>
            if mb_x /= "1111111" then
              mb_x <= mb_x + 1;
            else
              mb_x <= "0000000";
            end if;
          when "0010" | "1011" | "1101" | "0100" =>
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
      end if;

      if ma_amiga_mode='1' then
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
      if mb_amiga_mode='1' then
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

      -- Assumes 50MHz clock
      if phi_counter < 49 then
        phi_counter <= phi_counter + 1;
      else
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
