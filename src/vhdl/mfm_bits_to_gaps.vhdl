
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity mfm_bits_to_gaps is
  port (
    clock40mhz : in std_logic;

    cycles_per_interval : in unsigned(7 downto 0);
    write_precomp_enable : in std_logic := '0';
    
    -- Are we ready to accept something?
    ready_for_next : out std_logic := '0';
    
    -- Magnetic inversions as output
    f_write : out std_logic := '0';

    -- Input bits fo encoding
    byte_valid : in std_logic := '0';
    byte_in : in unsigned(7 downto 0);

    -- Clock bits
    -- This gets inverted before being XORd with the intended clock bits
    clock_byte_in : in unsigned(7 downto 0) := x"FF"
    
    );
end mfm_bits_to_gaps;

architecture behavioural of mfm_bits_to_gaps is

  signal last_bit : std_logic := '0';

  signal clock_bits : unsigned(7 downto 0) := x"FF";

  signal bit_queue : unsigned(7 downto 0);
  signal bits_queued : integer range 0 to 7 := 0;

  signal interval_countdown : integer range 0 to 255 := 0;
  signal transition_point : integer range 0 to 256 := 256;
  
  
begin

  process (clock40mhz) is
    variable state : unsigned(2 downto 0) := "000";
  begin
    if rising_edge(clock40mhz) then

      if interval_countdown = 0 then
        interval_countdown <= cycles_per_interval;

        if bits_queued /= 0 then
          bits_queued <= bits_queued - 1;
          
          if bit_queue(0)='1' then
            transition_point <= to_unsigned(to_integer(cycles_per_interval(7 downto 1)),9);
          else
            transition_point <= to_unsigned(256,9);
          end if;
        end if;
        
      else
        interval_countdown <= interval_countdown - 1;
      end if;       
      
      if bits_queued = 0 then
        ready_for_next <= '1';
      else
        ready_for_next <= '0';
      end if;
      
      if byte_valid='1' then
        report "latched byte $" & to_hstring(byte_in) & "(clock byte $" & to_hstring(clock_byte_in) & ") for encoding.";
        bits_queued <= 8;
        -- Get the bits to send
        bits_queued <= byte_in;
        -- Invert clock bits so that we can calculate using them.
        clock_bits <= not clock_byte_in;
        ready_for_next <= '0';
      else
        -- Else MFM encode the bit
        bits_queued <= 16;
        bit_queue(0) <= (bit_in nor last_bit) xor clock_bits;
        bit_queue(1) <= bit_in;
        last_bit <= bit_in;
      end if;
      
    end if;    
  end process;
end behavioural;

