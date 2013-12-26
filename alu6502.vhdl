library IEEE;
use IEEE.std_logic_1164.all;

entity ALU6502 is
  port (
    -- select operation to perform
    AAND : in std_logic;
    AOR : in std_logic;
    AXOR : in std_logic;
    ASL : in std_logic;
    ARL : in std_logic;
    ASR : in std_logic;
    ARR : in std_logic;
    AADD : in std_logic;
    ASUB : in std_logic;

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
  
end entity ALU6502;

-- this is the architecture
architecture RTL of ALU6502 is
begin
  process
    variable temp : std_logic_vector(8 downto 0);
  begin

    -- BCD 4 bit adders for ADC instruction
    signal bcd1cin : out std_logic;
    signal bcd1i1 : out unsigned(3 downto 0);
    signal bcd1i2 : out unsigned(3 downto 0);
    signal bcd1cout : in std_logic;
    signal bcd1o : in unsigned(3 downto 0);
    signal bcd2cin : out std_logic;
    signal bcd2i1 : out unsigned(3 downto 0);
    signal bcd2i2 : out unsigned(3 downto 0);
    signal bcd2cout : in std_logic;
    signal bcd2o : in unsigned(3 downto 0);
    
    bcd1 : entity bcdadder      
      port map (
        cin => bcd1cin,
        i1 => bcd1in1,
        i2 => bcd1in2,
        cout => bcd1cout,
        o => bcd1o
        );
    bcd2 : entity bcdadder      
      port map (
        cin => bcd2cin,
        i1 => bcd2in1,
        i2 => bcd2in2,
        cout => bcd2cout,
        o => bcd2o
        );
    
    if AAND = '1' then
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
    elsif AOR = '1' then
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
    elsif AXOR = '1' then
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
    elsif AASL = '1' then
      O(7 downto 1) <= I2(6 downto 0);
      O(0) <= '0';
      OC <= I2(7);
      OZ <= I2(6) or I2(5) or I2(4) or I2(3) or I2(2) or I2(1) or I2(0);
      ONEG <= I2(6);
      OV <= IV;
    elsif AARL = '1' then
      O(7 downto 1) <= I2(6 downto 0);
      O(0) <= IC;
      OC <= I2(7);
      OZ <= I2(6) or I2(5) or I2(4) or I2(3) or I2(2) or I2(1) or I2(0) or IC;
      ONEG <= I2(6);
      OV <= IV;
    elsif AASR = '1' then
      O(6 downto 0) <= I2(7 downto 1);
      O(7) <= '0';
      OC <= I2(0);
      OZ <= I2(7) or I2(6) or I2(5) or I2(4) or I2(3) or I2(2) or I2(1);
      ONEG <= INEG;
      OV <= IV;
    elsif AARR = '1' then
      O(6 downto 0) <= I2(7 downto 1);
      O(7) <= IC;
      OC <= I2(0);
      OZ <= I2(7) or I2(6) or I2(5) or I2(4) or I2(3) or I2(2) or I2(1);
      ONEG <= IC;
      OV <= IV;
    elsif AADD = '1' then
      if ID = '0' then
        -- binary mode: simple binary addition with carry in and out
        if IC = '0' then
          temp := std_logic_vector(unsigned(I1) + unsigned(I2));
        else
          temp := std_logic_vector(unsigned(I1) + unsigned(I2)+1);
        end if;
        O <= temp;
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
        -- XXX use two four bit BCD adders
      end if;
    end if;
  end process;
end architecture RTL;
