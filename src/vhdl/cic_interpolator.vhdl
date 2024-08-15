library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cic_interpolator is
    port(
        clk           : in std_logic;
        reset_n       : in std_logic;
        sample_in     : in signed(15 downto 0);  -- 16-bit signed input sample
        sample_valid  : in std_logic;  -- Input sample valid strobe
        output_sample : out signed(15 downto 0);  -- 16-bit signed output sample
        output_valid  : out std_logic  -- Output sample valid strobe
    );
end cic_interpolator;

architecture Behavioral of cic_interpolator is

    -- Internal signals for integrators and combs
    signal integrator1, integrator2, integrator3: integer range -32768 to 32767;
    signal comb1, comb2, comb3: integer range -32768 to 32767;

    -- Intermediate state for combs and interpolation
    signal integrator1_state, integrator2_state, integrator3_state: integer range -32768 to 32767 := 0;
    signal comb1_state, comb2_state, comb3_state: integer range -32768 to 32767 := 0;

    -- Counter for zero-stuffing interpolation
    signal interpolation_counter: integer := 0;

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                -- Reset all internal states
                integrator1_state <= 0;
                integrator2_state <= 0;
                integrator3_state <= 0;
                comb1_state <= 0;
                comb2_state <= 0;
                comb3_state <= 0;
                interpolation_counter <= 0;
                output_valid <= '0';
                output_sample <= (others => '0');
            else
                -- Handle incoming samples and interpolation
                if sample_valid = '1' or interpolation_counter /= 0 then
                    if interpolation_counter = 0 then
                        -- Use actual input sample
                        integrator1 <= to_integer(sample_in);
                    else
                        -- Zero-stuffing
                        integrator1 <= 0;
                    end if;

                    -- Integrator stages
                    integrator1_state <= integrator1_state + integrator1;
                    integrator2_state <= integrator2_state + integrator1_state;
                    integrator3_state <= integrator3_state + integrator2_state;

                    -- Comb stages
                    if interpolation_counter = 0 then
                        -- Output the result after all comb stages
                        comb1 <= integrator3_state - comb1_state;
                        comb1_state <= integrator3_state;

                        comb2 <= comb1 - comb2_state;
                        comb2_state <= comb1;

                        comb3 <= comb2 - comb3_state;
                        comb3_state <= comb2;

                        -- Output the final result
                        output_sample <= to_signed(comb3, 16);
                        output_valid <= '1';

                        -- Update interpolation counter
                        interpolation_counter <= interpolation_counter + 1;
                    else
                        -- Output zero-stuffed samples
                        comb1_state <= integrator3_state;

                        comb2_state <= comb1;

                        comb3_state <= comb2;

                        -- Output the zero-stuffed result
                        output_sample <= std_logic_vector(to_signed(comb3, 16));
                        output_valid <= '1';

                        -- Increment the counter or reset if done
                        if interpolation_counter = 3 then
                            interpolation_counter <= 0;
                        else
                            interpolation_counter <= interpolation_counter + 1;
                        end if;
                    end if;
                else
                    output_valid <= '0';
                end if;
            end if;
        end if;
    end process;

end Behavioral;
