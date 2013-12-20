library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

-- see http://vhdlguru.blogspot.com.au/2011/01/block-and-distributed-rams-on-xilinx.html
-- see http://www.xilinx.com/support/documentation/user_guides/ug383.pdf for
-- Xilinx guide on using block ram
-- The block ram is synchronous, so read/writes need to be setup and held over
-- a clock tick.  It is possible to increase the maximum clock speed by adding
-- an extra cycle of latency, which probably isn't interesting in the present case.
-- The RAM is also true dual-port, which we can use to our advantage, either by
-- having a 2nd CPU core, or by avoiding contention between core(s) and C64 bus
-- snooping activities, and/or between instruction and operand memory accesses.

-- XXX PGS - Almost certainly this is the wrong interface definition for the block
-- RAM.  See the Xilinx guide for the right formulation, including the dual
-- access ports.
entity spartan6blockram is
port (Clk : in std_logic;
        address : in std_logic_vector(15 downto 0);
        we : in std_logic;
        data_i : in std_logic_vector(7 downto 0);
        data_o : out std_logic_vector(7 downto 0)
     );
end spartan6blockram;

architecture Behavioral of spartan6blockram is

--Declaration of type and signal of a 64KB element RAM
--with each element being 8 bit wide.
type ram_t is array (0 to 65535) of std_logic_vector(7 downto 0);
signal ram : ram_t := (others => (others => '0'));

begin

--process for read and write operation.
PROCESS(Clk)
BEGIN
    if(rising_edge(Clk)) then
        if(we='1') then
          ram(to_integer(unsigned(address))) <= data_i;
        end if;
        data_o <= ram(to_integer(unsigned(address)));
    end if; 
END PROCESS;

end Behavioral;
