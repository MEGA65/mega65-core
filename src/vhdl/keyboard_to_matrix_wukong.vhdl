use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity keyboard_to_matrix is
    port (
        clk                  : in    std_logic;
        porta_pins           : inout std_logic_vector(7 downto 0) := (others => 'Z');
        portb_pins           : in std_logic_vector(7 downto 0);
        portb_charge_pins    : out   std_logic := '0';
        keyboard_column8_out : out   std_logic := '1';
        key_left             : in    std_logic;
        key_up               : in    std_logic;
        scan_mode            : in    std_logic_vector(1 downto 0);
        scan_rate            : in    unsigned(7 downto 0);
        -- Virtualised keyboard matrix
        matrix_col           : out   std_logic_vector(7 downto 0) := (others => '1');
        matrix_col_idx       : in    integer range 0 to 8
    );

end keyboard_to_matrix;

architecture behavioral of keyboard_to_matrix is
    -- Scan slow enough for the keyboard (rate is set via scan_rate)
    -- Actual scan rate = CPU clock / scan_rate.
    signal scan_phase : integer range 0 to 15        := 0;
    signal keyram_wea : std_logic_vector(7 downto 0) := (others => '0');
    signal matrix_dia : std_logic_vector(7 downto 0) := (others => '1');
begin
  
    kb_kmm: entity work.kb_matrix_ram
        port map (
            clkA => clk,
            addressa => scan_phase,
            dia => matrix_dia,
            wea => keyram_wea,
            addressb => matrix_col_idx,
            dob => matrix_col
        );

    process (clk)
        variable counter    : integer range 0 to 255       := 0;
        variable state      : integer range 0 to 15        := 0;
        variable column     : integer range 0 to 7         := 0;
        variable portb_debounced  : std_logic_vector(7 downto 0) := (others => '1');
    begin
        if rising_edge(clk) then

            -- Debounce portb pins
            portb_debounced := portb_debounced and portb_pins;

            keyram_wea <= (others => '0');
            matrix_dia <= (others => '1');
            scan_phase <= 0;

            -- Scan physical keyboard
            -- For the Wukong board, this is done by first charging both the
            -- porta and portb pins high, and then stopping charging the portb
            -- pins, so that when a porta pin is pulled low, it can be reflected
            -- on the appropriate portb pin(s) corresponding to where keys have
            -- been pressed.
            if counter = 0 then

                if state = 0 then
                    -- Tristate porta pins
                    porta_pins <= (others => 'Z');
                    counter := 32;
                    state := 1;

                elsif state = 1 then
                    -- Charge pins on portb to go high
                    portb_charge_pins <= '1';
                    counter := 32;
                    state := 2;

                elsif state = 2 then
                    -- Stop charging pins on portb
                    portb_charge_pins <= '0';
                    counter := 32;
                    state := 3;

                elsif state = 3 then
                    -- Drive all porta pins high
                    porta_pins <= (others => '1');
                    counter := 32;
                    state := 4;

                elsif state = 4 then
                    -- Wait until input clear.
                    if portb_pins = "11111111" then
                        state := 5;
                    end if;

                elsif state = 5 then
                    -- Activate column.
                    case column is
                        when 0 => porta_pins <= "11111110";
                        when 1 => porta_pins <= "11111101";
                        when 2 => porta_pins <= "11111011";
                        when 3 => porta_pins <= "11110111";
                        when 4 => porta_pins <= "11101111";
                        when 5 => porta_pins <= "11011111";
                        when 6 => porta_pins <= "10111111";
                        when 7 => porta_pins <= "01111111";
                    end case;
                    counter := 192;
                    state := 6;
                    portb_debounced := (others => '1');

                elsif state = 6 then

                    matrix_dia <= portb_debounced;
                    keyram_wea <= (others => '1');
                    scan_phase <= column;

                    if column = 7 then
                        column := 0;
                    else
                        column := column + 1;
                    end if;

                    counter := 255;
                    state := 0;
                end if;
            else
                -- Keep counting down to next scan event
                counter := counter - 1;
            end if;
        end if;
    end process;
end behavioral;
