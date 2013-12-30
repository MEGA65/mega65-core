use WORK.ALL;

library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;

entity ALU6502 is
  port (
    -- select operation to perform
    AFUNC : in std_logic_vector(3 downto 0);

    -- input flags and values
    IC : in std_logic;
    ID : in std_logic;
    INEG : in std_logic;
    IV : in std_logic;
    IZ : in std_logic;
    -- Typically a register
    I1  : in std_logic_vector(7 downto 0);
    -- Typically memory
    I2  : in std_logic_vector(7 downto 0);

    -- output flags and value
    OC : out std_logic;
    ONEG : out std_logic;
    OV : out std_logic;
    OZ : out std_logic;
    O  : out std_logic_vector(7 downto 0)
  );

  -- BCD 4 bit adders for ADC instruction
  signal bcd1cin : std_logic;
  signal bcd1in1 : unsigned(3 downto 0);
  signal bcd1in2 : unsigned(3 downto 0);
  signal bcd1cout : std_logic;
  signal bcd1o : unsigned(3 downto 0);
  signal bcd2in1 : unsigned(3 downto 0);
  signal bcd2in2 : unsigned(3 downto 0);
  signal bcd2cout : std_logic;
  signal bcd2o : unsigned(3 downto 0);  

end entity ALU6502;

-- this is the architecture
architecture RTL of ALU6502 is

  component bcdadder port (
    cin  : in  std_logic;
    i1   : in  unsigned(3 downto 0);
    i2   : in  unsigned(3 downto 0);
    o   : out  unsigned(3 downto 0);
    cout : out std_logic);
  end component;

begin

    bcd1 : component bcdadder      
    port map (
      cin => bcd1cin,
      i1 => bcd1in1,
      i2 => bcd1in2,
      cout => bcd1cout,
      o => bcd1o
      );
  bcd2 : component bcdadder      
    port map (
      cin => bcd1cout,
      i1 => bcd2in1,
      i2 => bcd2in2,
      cout => bcd2cout,
      o => bcd2o
      );
  
  process(afunc,I1,I2,IC,IV,INEG,ID,IZ,bcd1cout,bcd2cout,bcd2o,bcd1o)
    variable temp : std_logic_vector(8 downto 0);
    variable i18 : std_logic_vector(8 downto 0);
    variable i28 : std_logic_vector(8 downto 0);
    variable ctemp : std_logic_vector(0 downto 0);
  begin
    -- Set inputs to BCD adders to stop latches being inferred
    bcd1cin <= '0';
    bcd1in1 <= x"0";
    bcd1in2 <= x"0";
    bcd2in1 <= x"0";
    bcd2in2 <= x"0";
    
    if afunc = "0001" then              -- AND
      O <= I1 and I2;
      OZ <= (I1(7) and I2(7))
            or (I1(6) and I2(6))
            or (I1(5) and I2(5))
            or (I1(4) and I2(4))
            or (I1(3) and I2(3))
            or (I1(2) and I2(2))
            or (I1(1) and I2(1))
            or (I1(0) and I2(0));
      ONEG <= I1(7) and I2(7);
      OC <= IC;
      OV <= IV;
    elsif afunc = "0010" then                -- OR
      O <= I1 or I2;
      OZ <= (I1(7) or I2(7))
            or (I1(6) or I2(6))
            or (I1(5) or I2(5))
            or (I1(4) or I2(4))
            or (I1(3) or I2(3))
            or (I1(2) or I2(2))
            or (I1(1) or I2(1))
            or (I1(0) or I2(0));
      ONEG <= I1(7) or I2(7);
      OC <= IC;
      OV <= IV;
    elsif afunc = "0011" then               -- XOR
      O <= I1 xor I2;
      OZ <= (I1(7) xor I2(7))
            or (I1(6) xor I2(6))
            or (I1(5) xor I2(5))
            or (I1(4) xor I2(4))
            or (I1(3) xor I2(3))
            or (I1(2) xor I2(2))
            or (I1(1) xor I2(1))
            or (I1(0) xor I2(0));
      ONEG <= I2(6);
      OC <= IC;
      OV <= IV;
    elsif afunc = "0100" then               -- shift left
      O(7 downto 1) <= I2(6 downto 0);
      O(0) <= '0';
      OC <= I2(7);
      OZ <= I2(6) or I2(5) or I2(4) or I2(3) or I2(2) or I2(1) or I2(0);
      ONEG <= I2(6);
      OV <= IV;
    elsif afunc = "0101" then               -- rotate left
      O(7 downto 1) <= I2(6 downto 0);
      O(0) <= IC;
      OC <= I2(7);
      OZ <= I2(6) or I2(5) or I2(4) or I2(3) or I2(2) or I2(1) or I2(0) or IC;
      ONEG <= I2(6);
      OV <= IV;
    elsif afunc = "0110" then               -- shift right
      O(6 downto 0) <= I2(7 downto 1);
      O(7) <= '0';
      OC <= I2(0);
      OZ <= I2(7) or I2(6) or I2(5) or I2(4) or I2(3) or I2(2) or I2(1);
      ONEG <= INEG;
      OV <= IV;
    elsif afunc = "0111" then               -- rotate right
      O(6 downto 0) <= I2(7 downto 1);
      O(7) <= IC;
      OC <= I2(0);
      OZ <= I2(7) or I2(6) or I2(5) or I2(4) or I2(3) or I2(2) or I2(1);
      ONEG <= IC;
      OV <= IV;
    elsif afunc = "1000" then               -- ADD
      if ID = '0' then
        -- binary mode: simple binary addition with carry in and out
        i18(7 downto 0) := I1;
        i18(8) := '0';
        i28(7 downto 0) := I2;
        i28(8) := '0';
        if IC = '0' then
          temp := std_logic_vector(unsigned(i18)+unsigned(i28));
        else
          temp := std_logic_vector(unsigned(i18)+unsigned(i28)+1);
        end if;
        O <= temp(7 downto 0);
        if temp(7 downto 0) = x"00" then
          OZ <= '1';
        else
          OZ <= '0';
        end if;
        OC <= temp(8);
        OV <= temp(8);
        ONEG <= temp(7);
      else
        -- decimal mode with all it's bizarreness
        -- we should ideally be bug-compatible with the 6502 here.
        -- XXX use two four bit BCD adders.  This may make the calculation
        -- of N and V differ from the real 6502 where the N & V calculations
        -- occur before the BCD fixup in the low nybl, which can cause the
        -- upper nybl to increment.  We might be able to subtract bcd1cout from
        -- the upper nybl to provide 100% accuracy with the 6502's bizarre
        -- calculation of these flags when in decimal mode.
        bcd1cin <= IC;
        bcd1in1 <= unsigned(I1(3 downto 0));
        bcd1in2 <= unsigned(I2(3 downto 0));        
        bcd2in1 <= unsigned(I1(7 downto 4));
        bcd2in2 <= unsigned(I2(7 downto 4));
        OC <= bcd2cout;
        ctemp(0) := IC;
        if unsigned(I1) + unsigned(I2) + unsigned(ctemp) = x"00" then
          OZ <= '1';
        else
          OZ <= '0';
        end if;
        ONEG <= bcd2o(3);
        OV <= bcd2cout;
        O(7 downto 4) <= std_logic_vector(bcd2o);
        O(3 downto 0) <= std_logic_vector(bcd1o);
      end if;
    elsif afunc = "1001" then               -- SUB then
        -- subtraction does not support BCD mode, so we only need binary
        -- subtraction.
        i18(7 downto 0) := I1;
        i18(8) := '0';
        i28(7 downto 0) := I2;
        i28(8) := '0';
        if IC = '0' then
          temp := std_logic_vector(unsigned(i18)-unsigned(i28)-1);
        else
          temp := std_logic_vector(unsigned(i18)-unsigned(i28));
        end if;
        O <= temp(7 downto 0);
        if temp(7 downto 0) = x"00" then
          OZ <= '1';
        else
          OZ <= '0';
        end if;
        OC <= temp(8);
        OV <= temp(8);
        ONEG <= temp(7);
    else
      OC <= IC;
      OV <= IV;
      ONEG <= INEG;
      OZ <= IZ;
      O <= x"99";
      null;
    end if;
  end process;
end architecture RTL;
