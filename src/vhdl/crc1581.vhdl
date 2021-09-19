use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity crc1581 is
  generic (
    id : integer := 0
    );
  port (
    clock40mhz : in std_logic;

    crc_byte : in unsigned(7 downto 0);
    crc_feed : in std_logic;
    crc_reset : in std_logic;

    crc_ready : out std_logic := '1';
    crc_value : out unsigned(15 downto 0) := x"FFFF"
    );

end entity;

architecture foo of crc1581 is
  constant crc_init : unsigned(15 downto 0) := x"FFFF";
  signal value : unsigned(15 downto 0) := crc_init;
  signal ready : std_logic := '1';

  signal bits_left : integer range 0 to 8 := 0;
  signal byte : unsigned(7 downto 0) := x"00";

  signal last_crc_reset : std_logic := '0';

  signal byte_buffered : std_logic := '0';
  signal buffered_byte : unsigned(7 downto 0) := x"00";

begin
  process (clock40mhz) is
    variable last_crc : unsigned(15 downto 0) := x"0000";
  begin
    
    if rising_edge(clock40mhz) then
      crc_ready <= ready;
      crc_value <= value;
      if ready='1' and (last_crc /= value) then
        report "CRC" & integer'image(id) & " value is $" & to_hstring(value);
        last_crc := value;
      end if;

      if crc_feed='1' then
        report "CRC" & integer'image(id) & " buffering byte $" & to_hstring(crc_byte);
        byte_buffered <= '1';
        buffered_byte <= crc_byte;
      end if;
      
      last_crc_reset <= crc_reset;
      if crc_reset='1'  and last_crc_reset='0' then
        report "CRC" & integer'image(id) & " reset asserted";
      end if;
      
      if crc_reset = '1' then
        value <= crc_init;
        ready <= '1';
        -- Clear buffered byte, unless one is being fed to us simultaneously
        byte_buffered <= crc_feed;
--        report "CRC" & integer'image(id) & " reset";
      elsif bits_left /= 0 then
        ready <= '0';
        
        -- CRC function from C65 specifications document:
        --        ;
        --; CRC a bit. Assuming bit to CRC in carry, and cumulative CRC
        --;            value in CRC (lsb) and CRC+1 (msb).
        --
        --       CRCBIT   ROR
        --                EOR CRC+1       ; MSB contains INBIT
        --                PHP
        --                ASL CRC
        --                ROL CRC+1       ; shift CRC word
        --                PLP
        --                BPL RTS
        --                LDA CRC         ; toggle bits 0, 5, and 12 if INBIT is 1.
        --                EOR #$21
        --                STA CRC
        --                LDA CRC+1
        --                EOR #$10
        --                STA CRC+1
        --       RTS      RTS

        value(15 downto 1) <= value(14 downto 0);
        value(12) <= value(11) xor (byte(7) xor value(15));
        value(5) <= value(4) xor (byte(7) xor value(15));
        value(0) <= (byte(7) xor value(15));

        byte(7 downto 1) <= byte(6 downto 0);

        report "CRC" & integer'image(id) & " feeding bit "
          & std_logic'image(byte(7))
          &" bits_left=" & integer'image(bits_left);
        
        bits_left <= bits_left - 1;
      else

        if byte_buffered='1' then
          bits_left <= 8;
          byte <= buffered_byte;
          ready <= '0';
          report "CRC" & integer'image(id) & " fed with $" & to_hstring(crc_byte);
          byte_buffered <= '0';
        else
          ready <= '1';          
        end if;
      end if;
    end if;
  end process;
end foo;
