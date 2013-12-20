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
    I1  : out std_logic_vector(7 downto 0);
    I2  : out std_logic_vector(7 downto 0);

    -- output flags and value
    OC : out std_logic;
    ONEG : out std_logic;
    OV : out std_logic;
    OZ : out std_logic;
O  : out std_logic_vector(7 downto 0));
end entity ALU6502;
 
-- this is the architecture
architecture RTL of ALU6502 is
begin
  process
    begin
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
      end if;
      if AOR = '1' then
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
      end if;
      if AXOR = '1' then
        O <= I1 xor I2;
        OZ <= (I1(7) xor I2(7))
              or (I1(6) xor I2(6))
              or (I1(5) xor I2(5))
              or (I1(4) xor I2(4))
              or (I1(3) xor I2(3))
              or (I1(2) xor I2(2))
              or (I1(1) xor I2(1))
              or (I1(0) xor I2(0));
        ONEG <= I1(7) xor I2(7);
      end if;
    end process;
end architecture RTL;
