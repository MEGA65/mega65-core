
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity floppy_read_compensate is
  port (
    clock40mhz : in std_logic;

    correction_enable : in std_logic;
    
    cycles_per_interval : in unsigned(7 downto 0);
  
    gap_valid_in : in std_logic := '0';
    gap_length_in : in unsigned(15 downto 0) := (others => '0');
    
    gap_valid_out : out std_logic := '0';
    gap_length_out : out unsigned(15 downto 0) := (others => '0')

    );
end floppy_read_compensate;

architecture behavioural of floppy_read_compensate is  

  signal gap_time_0 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_time_1 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_time_2 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_time_3 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_time_4 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_time_5 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_time_6 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_time_7 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_quanta_0 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_quanta_1 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_quanta_2 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_quanta_3 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_quanta_4 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_quanta_5 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_quanta_6 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_quanta_7 : unsigned(15 downto 0) := to_unsigned(0,16);  

  type state_t is (idle,
                   dividing_bucket_into_gap_quant0
                   );
  signal state : state_t := idle;

  signal bucket : unsigned(15 downto 0) := to_unsigned(0,16);

begin

  process (clock40mhz) is
  begin
    if rising_edge(clock40mhz) then
      if correction_enable='0' then
        -- Simple pass through mode if disabled
        gap_length_out <= gap_length_in;
        gap_valid_out <= gap_valid_in;
      else
        
      end if;

      if gap_valid_in='1' then

        -- How long ago were the last 8 gaps?
        gap_time_0 <= gap_length_in;
        gap_time_1 <= gap_time_0 + gap_length_in;
        gap_time_2 <= gap_time_1 + gap_length_in;
        gap_time_3 <= gap_time_2 + gap_length_in;
        gap_time_4 <= gap_time_3 + gap_length_in;
        gap_time_5 <= gap_time_4 + gap_length_in;
        gap_time_6 <= gap_time_5 + gap_length_in;
        gap_time_7 <= gap_time_6 + gap_length_in;
        
        -- What did we wantise each of the last 8 gaps to be?
        gap_quanta_7 <= gap_quanta_6;
        gap_quanta_6 <= gap_quanta_5;
        gap_quanta_5 <= gap_quanta_4;
        gap_quanta_4 <= gap_quanta_3;
        gap_quanta_3 <= gap_quanta_2;
        gap_quanta_2 <= gap_quanta_1;
        gap_quanta_1 <= gap_quanta_0;

        -- Now we need to work out what the quantisation for the current gap is.
        -- This would be the easy way, if we had hardware immediate division
        -- and floating point:
        -- gap_quanta0 = gap_length_in / cycles_per_interval
        -- Instead we can work out the integer part using repeated subtraction,
        -- and then take a look at the remainder.
        gap_quanta_0 <= to_unsigned(0,16);
        bucket <= gap_length_in;
        state <= dividing_bucket_into_gap_quant0;

      end if;
      
      case state is
        when dividing_bucket_into_gap_quant0 =>
          if bucket >= cycles_per_interval then
            gap_quanta_0 <= gap_quanta_0 + 1;
            bucket <= bucket - cycles_per_interval;
          else
            -- Now its just a remainder
            report "The remainder is " & integer'image(to_integer(bucket));
            state <= Idle;
          end if;
          null;
        when others =>
          null;
      end case;
    end if;
  end process;
end behavioural;
