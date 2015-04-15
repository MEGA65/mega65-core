-- Bitplane processor for the C65GS
--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2015
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

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity bitplanes is
  port (
    pixelclock : in std_logic;
    ioclock : in std_logic;
    cpuclock : in std_logic;
    iomode : in std_logic_vector(1 downto 0);

    -- Fastio interface to allow CPU to read and set registers
    fastio_addr : in unsigned(19 downto 0);
    fastio_write : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out std_logic_vector(7 downto 0);

    -- CPU DMA interface to fetch data
    -- (Set dma_address and dma_count, then raise dma_request_set until
    -- dma_data_valid is asserted, then clear dma_request_set.
    -- dma_count_in indicates which byte in the request is being presented.
    -- dma_data_valid returns low after last byte has been supplied.
    dma_address : out unsigned(31 downto 0);
    dma_count : out unsigned(7 downto 0);
    dma_request_set : out std_logic := '0';
    dma_data_valid : in std_logic;
    dma_data_in : in unsigned(7 downto 0);
    dma_count_in : in unsigned(7 downto 0);
    
    -- XXX VIC-IV buffer interface for providing rendered raster lines of
    -- bitplane data, and for indicating when safe to update raster buffer.
    bitplanerenderbuffer_address : in unsigned(11 downto 0);
    bitplanerenderbuffer_rdata : out unsigned(8 downto 0);
    bitplanerenderbuffer_moby : out std_logic;
    viciv_flyback : in std_logic;
    -- and also what our current raster number is
    viciv_physical_raster : in unsigned(11 downto 0)
    );
end bitplanes;

--                        VIC-III MODE REGISTERS

--+-------+-------+-------+-------+-------+-------+-------+-------+ D000+
--| KEY7  | KEY6  | KEY5  | KEY4  | KEY3  | KEY2  | KEY1  | KEY0  | 2F KEY
--+-------+-------+-------+-------+-------+-------+-------+-------+
--| ROM   | CROM  | ROM   | ROM   | ROM   | PAL   | EXT   | CRAM  | 30 CONTROL A
--| @E000 | @9000 | @C000 | @A000 | @8000 |       | SYNC  | @DC00 |
--+-------+-------+-------+-------+-------+-------+-------+-------+
--| H640  | FAST  | ATTR  |  BPM  | V400  | H1280 | MONO  |  INT  | 31 CONTROL B
--+-------+-------+-------+-------+-------+-------+-------+-------+
--| BP7EN | BP6EN | BP5EN | BP4EN | BP3EN | BP2EN | BP1EN | BP0EN | 32 BP ENABS
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B0AD15 |B0AD14 |B0AD13 |       |B0AD15 |B0AD14 |B0AD13 |       | 33 BITPLANE 0
--| ODD   | ODD   | ODD   |       | EVEN  | EVEN  | EVEN  |       |    ADDRESS
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B1AD15 |B1AD14 |B1AD13 |       |B1AD15 |B1AD14 |B1AD13 |       | 34 BITPLANE 1
--| ODD   | ODD   | ODD   |       | EVEN  | EVEN  | EVEN  |       |    ADDRESS
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B2AD15 |B2AD14 |B2AD13 |       |B2AD15 |B2AD14 |B2AD13 |       | 35 BITPLANE 2
--| ODD   | ODD   | ODD   |       | EVEN  | EVEN  | EVEN  |       |    ADDRESS
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B3AD15 |B3AD14 |B3AD13 |       |B3AD15 |B3AD14 |B3AD13 |       | 36 BITPLANE 3
--| ODD   | ODD   | ODD   |       | EVEN  | EVEN  | EVEN  |       |    ADDRESS
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B4AD15 |B4AD14 |B4AD13 |       |B4AD15 |B4AD14 |B4AD13 |       | 37 BITPLANE 4
--| ODD   | ODD   | ODD   |       | EVEN  | EVEN  | EVEN  |       |    ADDRESS
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B5AD15 |B5AD14 |B5AD13 |       |B5AD15 |B5AD14 |B5AD13 |       | 38 BITPLANE 5
--| ODD   | ODD   | ODD   |       | EVEN  | EVEN  | EVEN  |       |    ADDRESS
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B6AD15 |B6AD14 |B6AD13 |       |B6AD15 |B6AD14 |B6AD13 |       | 39 BITPLANE 6
--| ODD   | ODD   | ODD   |       | EVEN  | EVEN  | EVEN  |       |    ADDRESS
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B7AD15 |B7AD14 |B7AD13 |       |B7AD15 |B7AD14 |B7AD13 |       | 3A BITPLANE 7
--| ODD   | ODD   | ODD   |       | EVEN  | EVEN  | EVEN  |       |    ADDRESS
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|BP7COMP|BP6COMP|BP5COMP|BP4COMP|BP3COMP|BP2COMP|BP1COMP|BP0COMP| 3B BP COMPS
--+-------+-------+-------+-------+-------+-------+-------+-------+
--| BPY8  | BPX6  | BPX5  | BPX4  | BPX3  | BPX2  | BPX1  | BPX0  | 3C BITPLANE X
--+-------+-------+-------+-------+-------+-------+-------+-------+
--| BPY7  | BPY6  | BPY5  | BPY4  | BPY3  | BPY2  | BPY1  | BPY0  | 3D BITPLANE Y
--+-------+-------+-------+-------+-------+-------+-------+-------+
--| HPOS7 | HPOS6 | HPOS5 | HPOS4 | HPOS3 | HPOS2 | HPOS1 | HPOS0 | 3E HORIZ POS
--+-------+-------+-------+-------+-------+-------+-------+-------+
--| VPOS7 | VPOS6 | VPOS5 | VPOS4 | VPOS3 | VPOS2 | VPOS1 | VPOS0 | 3F VERT POS
--+-------+-------+-------+-------+-------+-------+-------+-------+


--                        DAT MEMORY PORTS

--+-------+-------+-------+-------+-------+-------+-------+-------+ D000+
--|B0PIX7 |B0PIX6 |B0PIX5 |B0PIX4 |B0PIX3 |B0PIX2 |B0PIX1 |B0PIX0 | 40 BITPLANE 0
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B1PIX7 |B1PIX6 |B1PIX5 |B1PIX4 |B1PIX3 |B1PIX2 |B1PIX1 |B1PIX0 | 41 BITPLANE 1
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B2PIX7 |B2PIX6 |B2PIX5 |B2PIX4 |B2PIX3 |B2PIX2 |B2PIX1 |B2PIX0 | 42 BITPLANE 2
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B3PIX7 |B3PIX6 |B3PIX5 |B3PIX4 |B3PIX3 |B3PIX2 |B3PIX1 |B3PIX0 | 43 BITPLANE 3
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B4PIX7 |B4PIX6 |B4PIX5 |B4PIX4 |B4PIX3 |B4PIX2 |B4PIX1 |B4PIX0 | 44 BITPLANE 4
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B5PIX7 |B5PIX6 |B5PIX5 |B5PIX4 |B5PIX3 |B5PIX2 |B5PIX1 |B5PIX0 | 45 BITPLANE 5
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B6PIX7 |B6PIX6 |B6PIX5 |B6PIX4 |B6PIX3 |B6PIX2 |B6PIX1 |B6PIX0 | 46 BITPLANE 6
--+-------+-------+-------+-------+-------+-------+-------+-------+
--|B7PIX7 |B7PIX6 |B7PIX5 |B7PIX4 |B7PIX3 |B7PIX2 |B7PIX1 |B7PIX0 | 47 BITPLANE 7
--+-------+-------+-------+-------+-------+-------+-------+-------+


architecture behavioural of bitplanes is
  -- C65 compatibility bitplanes : addresses are multiples of 8KB (or 16KB in H640)
  type viciii_bitplane_addresses is array (0 to 7) of unsigned(2 downto 0);
  signal bitplane_addresses_even : viciii_bitplane_addresses;
  signal bitplane_addresses_odd : viciii_bitplane_addresses;
  signal reg_bitplane_enables : std_logic_vector(7 downto 0);
  signal reg_bitplane_complements : std_logic_vector(7 downto 0);
  signal reg_bitplane_x : unsigned(7 downto 0);
  signal reg_bitplane_y : unsigned(7 downto 0);
  signal bitplane_mode : std_logic := '0';
  
  -- C65GS new bitplanes : arbitrary addresses
  type viciv_bitplane_addresses is array(0 to 15) of unsigned(31 downto 0);
  signal viciv_bitplane_addrs : viciv_bitplane_addresses;

  signal bitplanedatabuffer_write : std_logic := '0';
  signal bitplanedatabuffer_wdata : unsigned(8 downto 0);
  signal bitplanedatabuffer_waddress : unsigned(11 downto 0);
  signal bitplanedatabuffer_address : unsigned(11 downto 0);
  signal bitplanedatabuffer_rdata : unsigned(8 downto 0);

  signal bitplanerenderbuffer_write : std_logic := '0';
  signal bitplanerenderbuffer_wdata : unsigned(8 downto 0);
  signal bitplanerenderbuffer_waddress : unsigned(11 downto 0);

  
  component ram9x4k IS
    PORT (
      clka : IN STD_LOGIC;
      wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
      addraa : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
      dina : IN STD_LOGIC_VECTOR(8 DOWNTO 0);
      clkb : IN STD_LOGIC;
      addrb : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
      doutb : OUT STD_LOGIC_VECTOR(8 DOWNTO 0)
      );
  END component;

begin

  -- 4K buffer for holding buffered bitplane data for rendering
  bitplanedatabuffer: component ram9x4k
    port map (clka => cpuclock,
              wea(0) => bitplanedatabuffer_write,
              dina => std_logic_vector(bitplanedatabuffer_wdata),
              addraa => std_logic_vector(bitplanedatabuffer_waddress),

              clkb => pixelclock,
              addrb => std_logic_vector(bitplanedatabuffer_address),
              unsigned(doutb) => bitplanedatabuffer_rdata
              );

  -- 4KB buffer for holding 2 raster lines worth of output:
  -- last drawn buffer for the VIC-IV to render from, and one that we
  -- are rendering to.  We then use hsync to know when it is safe to toggle
  -- between them, and avoid horizontal tearing
  bitplanerenderbuffer: component ram9x4k
    port map (clka => pixelclock,
              wea(0) => bitplanerenderbuffer_write,
              dina => std_logic_vector(bitplanerenderbuffer_wdata),
              addraa => std_logic_vector(bitplanerenderbuffer_waddress),

              clkb => pixelclock,
              addrb => std_logic_vector(bitplanerenderbuffer_address),
              unsigned(doutb) => bitplanerenderbuffer_rdata
              );
  
  process (ioclock) is
    variable register_number : unsigned(7 downto 0);
    variable bitplane_number : integer;
  begin
    if rising_edge(ioclock) then
      fastio_rdata <= (others => 'Z');
      if fastio_addr(19 downto 8) = x"d10"
        or fastio_addr(19 downto 8) = x"d30" then
        -- Bitplane registers appear only in VIC-III/IV IO map
        register_number := fastio_addr(7 downto 0);
        if register_number = 49 then
          -- Sniff when someone enables or disables VIC-III bitplane mode, so that
          -- we know when to stop/start fetching them.
          if fastio_write='1' then
            bitplane_mode <= fastio_wdata(4);
          end if;
        elsif register_number = 50 then
          -- @ IO:65 $D032 - VIC-III Bitplane enable bits
          if fastio_write='1' then
            reg_bitplane_enables(7 downto 0) <= std_logic_vector(fastio_wdata);
          else
            fastio_rdata <= reg_bitplane_enables(7 downto 0);
          end if;
        elsif register_number >= 51 and register_number <= 58 then
          -- @ IO:65 $D033-$D03A - VIC-III Bitplane addresses
          bitplane_number := to_integer(register_number(3 downto 0)-"001");
          if fastio_write='1' then
            bitplane_addresses_even(bitplane_number) <= fastio_wdata(7 downto 5);
            bitplane_addresses_odd(bitplane_number) <= fastio_wdata(3 downto 1);
          else
            fastio_rdata(7 downto 5) <= std_logic_vector(bitplane_addresses_even(bitplane_number));
            fastio_rdata(4) <= '0';
            fastio_rdata(3 downto 1) <= std_logic_vector(bitplane_addresses_odd(bitplane_number));
            fastio_rdata(0) <= '0';
          end if;
        elsif register_number = 59 then
          -- @ IO:65 $D03B - VIC-III Bitplane complement bits
          if fastio_write='1' then
            reg_bitplane_complements(7 downto 0) <= std_logic_vector(fastio_wdata);
          else
            fastio_rdata <= reg_bitplane_complements(7 downto 0);
          end if;
        elsif register_number = 60 then
          -- @ IO:65 $D03C - VIC-III Bitplane X (for DAT)
          if fastio_write='1' then
            reg_bitplane_x(7 downto 0) <= fastio_wdata;
          else
            fastio_rdata <= std_logic_vector(reg_bitplane_x(7 downto 0));
          end if;
        elsif register_number = 61 then
          -- @ IO:65 $D03D - VIC-III Bitplane Y (for DAT)
          if fastio_write='1' then
            reg_bitplane_y(7 downto 0) <= fastio_wdata;
          else
            fastio_rdata <= std_logic_vector(reg_bitplane_y(7 downto 0));
          end if;
        end if;
      end if;
    end if;

    -- On CPU clock, manage DMA requests

    -- On VIC-IV pixel clock, render bitplanes
    
    
  end process;
end behavioural;
