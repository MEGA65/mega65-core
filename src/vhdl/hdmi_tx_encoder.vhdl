--------------------------------------------------------------------------------
-- hdmi_tx_encoder.vhd                                                        --
-- HDMI TMDS encoder channel.                                                 --
--------------------------------------------------------------------------------
-- (C) Copyright 2020 Adam Barnes <ambarnes@gmail.com>                        --
-- This file is part of The Tyto Project. The Tyto Project is free software:  --
-- you can redistribute it and/or modify it under the terms of the GNU Lesser --
-- General Public License as published by the Free Software Foundation,       --
-- either version 3 of the License, or (at your option) any later version.    --
-- The Tyto Project is distributed in the hope that it will be useful, but    --
-- WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public     --
-- License for more details. You should have received a copy of the GNU       --
-- Lesser General Public License along with The Tyto Project. If not, see     --
-- https://www.gnu.org/licenses/.                                             --
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

package hdmi_tx_encoder_pkg is

    constant ENC_DVI        : std_logic_vector(1 downto 0) := "00";
    constant ENC_GB_VIDEO   : std_logic_vector(1 downto 0) := "01";
    constant ENC_DATA       : std_logic_vector(1 downto 0) := "10";
    constant ENC_GB_DATA    : std_logic_vector(1 downto 0) := "11";

end package hdmi_tx_encoder_pkg;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.hdmi_tx_encoder_pkg.all;

entity hdmi_tx_encoder is
    generic (
        channel : integer range 0 to 2 -- affects encoding of guard bands
    );
    port (
        rst     : in    std_logic;                      -- synchronous reset
        clk     : in    std_logic;                      -- pixel clock
        de      : in    std_logic;                      -- pixel data enable
        p       : in    std_logic_vector(7 downto 0);   -- pixel data
        enc     : in    std_logic_vector(1 downto 0);   -- encoding type (non-video)
        c       : in    std_logic_vector(1 downto 0);   -- control
        d       : in    std_logic_vector(3 downto 0);   -- aux data (for data islands)
        q       : out   std_logic_vector(9 downto 0)    -- TMDS encoded output
    );
end entity hdmi_tx_encoder;

-------------------------------------------------------------------------------

architecture synth of hdmi_tx_encoder is

    -- TMDS encoding related
    signal n1p      : unsigned(3 downto 0); -- 0 to 8
    signal q_m      : std_logic_vector(8 downto 0);
    signal n0q_m    : unsigned(3 downto 0); -- 0 to 8
    signal n1q_m    : unsigned(3 downto 0); -- 0 to 8
    signal diff01_5 : signed(4 downto 0); -- -8 to +8 (even)
    signal diff10_5 : signed(4 downto 0); -- -8 to +8 (even)
    alias  diff01   : signed(3 downto 0) is diff01_5(4 downto 1); -- -4 to +4
    alias  diff10   : signed(3 downto 0) is diff10_5(4 downto 1); -- -4 to +4
    signal cnt      : signed(3 downto 0); -- -4 to +4

    -- function to count bits
    function Nv(x : std_logic_vector; v : std_logic) return integer is
    variable n : integer;
    begin
        n := 0;
        for i in 0 to x'length-1 loop
            if x(i) = v then n := n+1; end if;
        end loop;
        return n;
    end function Nv;

begin

    n1p <= to_unsigned(Nv(p,'1'),4);
    q_m(0) <= p(0);
    q_m(8 downto 1) <=
        '0' & (q_m(6 downto 0) xnor p(7 downto 1)) when n1p > x"4" or (n1p = x"4" and p(0) = '0') else
        '1' & (q_m(6 downto 0) xor p(7 downto 1));
    n0q_m <= to_unsigned(Nv(q_m(7 downto 0),'0'),4);
    n1q_m <= to_unsigned(Nv(q_m(7 downto 0),'1'),4);
    diff01_5 <= signed(resize(n0q_m,5)) - signed(resize(n1q_m,5));  -- difference between number of 1s and number of 0s
    diff10_5 <= signed(resize(n1q_m,5)) - signed(resize(n0q_m,5));  -- is always even so drop LSB from count

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                q <= "1101010100";
                cnt <= x"0";
            else
                if de = '1' then -- video
                    if (cnt = 0) or (n1q_m = n0q_m) then
                        q(9) <= not q_m(8);
                        q(8) <= q_m(8);
                        q(7 downto 0) <= q_m(7 downto 0) xor (7 downto 0 => not q_m(8));
                        if q_m(8) = '0' then
                            cnt <= cnt + diff01;
                        else
                            cnt <= cnt + diff10;
                        end if;
                    elsif (cnt > x"0" and n1q_m > n0q_m) or (cnt < x"0" and n0q_m > n1q_m) then
                        q(9) <= '1';
                        q(8) <= q_m(8);
                        q(7 downto 0) <= not q_m(7 downto 0);
                        cnt <= cnt + signed("000" & q_m(8 downto 8)) + diff01;
                    else
                        q(9) <= '0';
                        q(8) <= q_m(8);
                        q(7 downto 0) <= q_m(7 downto 0);
                        cnt <= cnt - signed("000" & not q_m(8 downto 8)) + diff10;
                    end if;
                else -- not video
                    cnt <= x"0";
                    case enc is
                        when ENC_DVI => -- control
                            case c is
                                when "00" =>    q <= "1101010100";
                                when "01" =>    q <= "0010101011";
                                when "10" =>    q <= "0101010100";
                                when "11" =>    q <= "1010101011";
                                when others =>  q <= "XXXXXXXXXX";
                            end case;
                        when ENC_GB_VIDEO => -- video guard band
                            case channel is
                                when 0 => q <= "1011001100";
                                when 1 => q <= "0100110011";
                                when 2 => q <= "1011001100";
                                when others => q <= "XXXXXXXXXX";
                            end case;
                        when ENC_DATA => -- data island contents
                            case d is
                                when "0000" => q <= "1010011100";
                                when "0001" => q <= "1001100011";
                                when "0010" => q <= "1011100100";
                                when "0011" => q <= "1011100010";
                                when "0100" => q <= "0101110001";
                                when "0101" => q <= "0100011110";
                                when "0110" => q <= "0110001110";
                                when "0111" => q <= "0100111100";
                                when "1000" => q <= "1011001100";
                                when "1001" => q <= "0100111001";
                                when "1010" => q <= "0110011100";
                                when "1011" => q <= "1011000110";
                                when "1100" => q <= "1010001110";
                                when "1101" => q <= "1001110001";
                                when "1110" => q <= "0101100011";
                                when others => q <= "1011000011";
                            end case;
                        when ENC_GB_DATA => -- data island guard band
                            case channel is
                                when 2 => q <= "0100110011";
                                when 1 => q <= "0100110011";
                                when 0 => -- special rules for channel 0...
                                    case c is
                                        when "00" => q <= "1010001110";
                                        when "01" => q <= "1001110001";
                                        when "10" => q <= "0101100011";
                                        when "11" => q <= "1011000011";
                                        when others => q <= "XXXXXXXXXX";
                                    end case;
                            end case;
                        when others =>
                            q <= "XXXXXXXXXX";
                    end case;
                end if;
            end if;
        end if;
    end process;

end architecture synth;
