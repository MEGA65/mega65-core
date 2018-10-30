--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2018
--
-- *  This program is free software; you can redistribute it and/or modify
-- *  it under the terms of the GNU Lesser General Public License as
-- *  published by the Free Software Foundation; either version 3 of the
-- *  License, or (at your option) any later version.
-- *
-- *  This program is distributed in the hope that it will be useful,
-- *  but WITHOUT ANY WARRANTY; without even the implied warranty of
-- *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- *  GNU General Public License for more details.
-- *
-- *  You should have received a copy of the GNU Lesser General Public License
-- *  along with this program; if not, write to the Free Software
-- *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
-- *  02111-1307  USA.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity pixel_fifo is

  port (
    almost_empty : out std_logic := '1';  -- goes low when there is enough in the
                                        -- fifo
    dout : out unsigned(23 downto 0) := x"000000"; -- pixel out
    empty : out std_logic := '1';
    full : out std_logic := '0';
    din : in unsigned(23 downto 0);
    rd_clk : in std_logic;
    wr_clk : in std_logic;
    rd_en : in std_logic;
    wr_en : in std_logic;
    data_valid : out std_logic;
    rd_data_count : out std_logic_vector(9 downto 0) := (others => '0');
    wr_data_count : out std_logic_vector(9 downto 0) := (others => '0')
    );
end pixel_fifo;

architecture neolithic of pixel_fifo is

  type pixel_buffer_t is array(0 to 15) of unsigned(23 downto 0);
  signal pixel_buffer : pixel_buffer_t := (others => (others => '0'));
  
  signal next_write : integer range 0 to 15 := 0;
  signal next_read : integer range 0 to 15 := 0;
  signal available : integer range 0 to 15 := 0;
  signal full_internal : std_logic := '0';
  signal empty_internal : std_logic := '1';
  signal almost_empty_internal : std_logic := '1';

  signal write_toggle : std_logic := '0';
  signal last_write_toggle : std_logic := '0';
  
begin

  process (wr_clk) is
  begin
    if rising_edge(wr_clk) then
      if wr_en='1' then
        report "Saw write to fifo of $" & to_hstring(din);        
        pixel_buffer(next_write) <= din;
        if next_write /= 15 then
          next_write <= next_write + 1;
        else
          next_write <= 0;
        end if;
        write_toggle <= not write_toggle;
      end if;        
    end if;
  end process;

  process (rd_clk) is
  begin
    if rising_edge(rd_clk) then
      -- Record on the read side if we have new data in the buffer
      if write_toggle /= last_write_toggle then
        report "Saw write to fifo.";
        last_write_toggle <= write_toggle;
        if available = 0 and rd_en='1' then
          -- FIFO was empty, and a read was requested, to push it directly to
          -- the output
          report "Reading new value immediately";
          report "Item is $" & to_hstring(pixel_buffer(next_read));
          dout <= pixel_buffer(next_read);
          almost_empty_internal <= '1';
          empty_internal <= '1';
          data_valid <= '1';
          if next_read /= 15 then
            next_read <= next_read + 1;
          else
            next_read <= 0;
          end if;                  
        elsif available /= 15 then
          report "Stashing write for reading later";
          report "Item is $" & to_hstring(pixel_buffer(next_read));
          available <= available + 1;
          if available > 2 then
            almost_empty_internal <= '0';
          else
            almost_empty_internal <= '1';
          end if;          
        else
          report "FIFO over filled.";
          full_internal <= '1';
        end if;
      elsif available /= 0 and rd_en='1' then
        report "Reading an item from the FIFO, " & integer'image(available) & " items available.";
        report "Item is $" & to_hstring(pixel_buffer(next_read));
        dout <= pixel_buffer(next_read);
        data_valid <= '1';
        available <= available - 1;
        if available = 1 then
          empty_internal <= '1';
        end if;
        if next_read /= 15 then
          next_read <= next_read + 1;
        else
          next_read <= 0;
        end if;
      elsif rd_en='1' then
        report "Reading from FIFO while empty";
        dout <= x"000000";
        data_valid <= '0';
        empty_internal <= '1';
        almost_empty_internal <= '1';
        full_internal <= '0';
      end if;
    end if;
  end process;
  
end neolithic;
