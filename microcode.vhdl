library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

--
entity microcode is
  port (Clk : in std_logic;
        address : in std_logic_vector(10 downto 0);
        data_o : out std_logic_vector(63 downto 0)
        );
end microcode;

architecture Behavioral of microcode is

  constant mcStoreArg1 : integer := 0;
  constant mcReadFromPC : integer := 1;
  constant mcReadZPfast : integer := 2;
  constant mcReadZP : integer := 3;
  constant mcReadAbs : integer := 4;
  constant mcIncPC : integer := 5;
  constant mcIncInA : integer := 6;
  constant mcIncInX : integer := 7;
  constant mcIncInY : integer := 8;
  constant mcIncInZ : integer := 9;
  constant mcIncInSPH : integer := 10;
  constant mcIncInSPL : integer := 11;
  constant mcIncOutA : integer := 12;
  constant mcIncOutX : integer := 13;
  constant mcIncOutY : integer := 14;
  constant mcIncOutZ : integer := 15;
  constant mcIncOutT : integer := 16;
  constant mcIncOutSPH : integer := 17;
  constant mcIncOutSPL : integer := 18;
  constant mcIncInc : integer := 19;
  constant mcIncDec : integer := 20;
  constant mcIncShiftLeft : integer := 21;
  constant mcIncShiftRight : integer := 22;
  constant mcIncZeroIn : integer := 23;
  constant mcIncCarryIn : integer := 24;
  constant mcIncSetNZ : integer := 25;
  constant mcMap : integer := 26;
  constant mcInstructionFetch : integer := 27;
  constant mcInstructionDecode : integer := 28;
  constant mcSetFlagI : integer := 29;
  constant mcWriteP : integer := 30;
  constant mcWritePCL : integer := 31;
  constant mcWritePCH : integer := 32;
  constant mcWriteABS : integer := 33;
  constant mcWriteZP : integer := 34;
  constant mcWriteStack : integer := 35;
  constant mcWriteMem : integer := 36;
  constant mcDecSP : integer := 37;
  constant mcIncSP : integer := 38;
  constant mcBreakFlag : integer := 39;  
  constant mcVectorIRQ : integer := 40;
  constant mcVectorNMI : integer := 41;
  constant mcLoadVector : integer := 42;
  constant mcIncInT : integer := 43;
  constant mcStoreArg2 : integer := 44;
  constant mcDeclareArg1 : integer := 45;
  constant mcDeclareArg2 : integer := 46;
  constant mcIncInMem : integer := 47;
  constant mcIncOutMem : integer := 48;
  constant mcIncAnd : integer := 49;
  constant mcIncIor : integer := 50;
  constant mcIncEor : integer := 51;
  constant mcAluOutA : integer := 52;
  constant mcAluCarryOut : integer := 53;
  
  type ram_t is array (0 to 4095) of std_logic_vector(63 downto 0);
  signal ram : ram_t := (
    -- BRK $00 : Push PCL, PCH, P(with B set). Set I. Jump to IRQ vector
    16#00#*8+0 => (mcIncPc => '1', mcSetFlagI => '1',
                   mcWriteMem => '1', mcWritePCL => '1',
                   mcWriteStack => '1', mcDecSP => '1',
                   others => '0'),
    16#00#*8+1 => (mcWriteMem => '1', mcWritePCH => '1',
                   mcWriteStack => '1', mcDecSP => '1',
                   others => '0'),
    16#00#*8+2 => (mcWriteMem => '1', mcWriteP => '1', mcBreakFlag => '1',
                   mcWriteStack => '1', mcDecSP => '1',                
                   mcVectorIRQ => '1', mcLoadVector => '1',
                   others => '0'),
    others => ( mcInstructionFetch => '1', others => '0'));

begin

--process for read and write operation.
  PROCESS(Clk,address)
  BEGIN
    if(rising_edge(Clk)) then 
      data_o <= ram(to_integer(unsigned(address)));
    end if;
  END PROCESS;

end Behavioral;
