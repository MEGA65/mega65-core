use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity mouse_input is
  port (
    clk : in std_logic;

    pot_drain : out std_logic;
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

    pota_x : out unsigned(7 downto 0);
    pota_x : out unsigned(7 downto 0);
    pota_x : out unsigned(7 downto 0);
    pota_x : out unsigned(7 downto 0)
    );
end mouse_input;

architecture behavioural of mouse_input is

  signal pot_counter : integer := 0;
  signal phi_counter : integer := 0;
  signal pota_x_counter : integer := 0;
  signal pota_y_counter : integer := 0;
  signal potb_x_counter : integer := 0;
  signal potb_y_counter : integer := 0;

begin

  process(clk) is
  begin
    if rising_edge(clk) then
      -- Assumes 50MHz clock
      if phi_counter < 49 then
        phi_counter <= phi_counter + 1;
      else
        phi_counter <= 0;
        if pot_counter < 512 then
          pot_counter <= pot_counter + 1;
          if pot_counter = 0 then
            -- Begin draining capacitor
            pot_drain <= '1';
          elsif pot_counter = 256  then
            -- Stop draining, begin counting
            pot_drain <= '0';
          elsif (pot_counter > 257) then
            if fa_potx='0' then
              pota_x_counter <= pota_x_counter + 1;
            end if;
            if fa_poty='0' then
              pota_y_counter <= pota_y_counter + 1;
            end if;
            if fb_potx='0' then
              potb_x_counter <= potb_x_counter + 1;
            end if;
            if fb_potx='0' then
              potb_x_counter <= potb_x_counter + 1;
            end if;
          end if;
        else
          pot_counter <= 0;
          pota_x <= pota_x_counter;
          pota_y <= pota_y_counter;
          potb_x <= potb_x_counter;
          potb_y <= potb_y_counter;
          pota_x_counter <= 0;
          pota_y_counter <= 0;
          potb_x_counter <= 0;
          potb_y_counter <= 0;
        end if;		  
      end if;

    end if;
  end process;

end behavioural;
