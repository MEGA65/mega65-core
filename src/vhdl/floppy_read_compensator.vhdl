
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

  signal gap_time_ticks0 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_time_ticks1 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_time_ticks2 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_time_ticks3 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_time_ticks4 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_time_ticks5 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_time_ticks6 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_time_ticks7 : unsigned(15 downto 0) := to_unsigned(0,16);

  signal gap_time_remainders0 : signed(7 downto 0) := to_signed(0,8);
  signal gap_time_remainders1 : signed(7 downto 0) := to_signed(0,8);
  signal gap_time_remainders2 : signed(7 downto 0) := to_signed(0,8);
  signal gap_time_remainders3 : signed(7 downto 0) := to_signed(0,8);
  signal gap_time_remainders4 : signed(7 downto 0) := to_signed(0,8);
  signal gap_time_remainders5 : signed(7 downto 0) := to_signed(0,8);
  signal gap_time_remainders6 : signed(7 downto 0) := to_signed(0,8);
  signal gap_time_remainders7 : signed(7 downto 0) := to_signed(0,8);

  signal gap_accum_ticks0 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_accum_ticks1 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_accum_ticks2 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_accum_ticks3 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_accum_ticks4 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_accum_ticks5 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_accum_ticks6 : unsigned(15 downto 0) := to_unsigned(0,16);
  signal gap_accum_ticks7 : unsigned(15 downto 0) := to_unsigned(0,16);

  signal gap_accum_remainders0 : signed(7 downto 0) := to_signed(0,8);
  signal gap_accum_remainders1 : signed(7 downto 0) := to_signed(0,8);
  signal gap_accum_remainders2 : signed(7 downto 0) := to_signed(0,8);
  signal gap_accum_remainders3 : signed(7 downto 0) := to_signed(0,8);
  signal gap_accum_remainders4 : signed(7 downto 0) := to_signed(0,8);
  signal gap_accum_remainders5 : signed(7 downto 0) := to_signed(0,8);
  signal gap_accum_remainders6 : signed(7 downto 0) := to_signed(0,8);
  signal gap_accum_remainders7 : signed(7 downto 0) := to_signed(0,8);
  
  
  type state_t is (idle,
                   dividing_bucket_into_gap_quant0,
                   WaitForSums
                   );
  signal state : state_t := idle;

  signal bucket : unsigned(15 downto 0) := to_unsigned(0,16);
  signal report_recent : std_logic := '0';
  signal wait_counter : integer range 0 to 15 := 0;
  
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

        report "ingesting gap of length " & integer'image(to_integer(gap_length_in));
        
        -- How long ago were the last 8 gaps?
        gap_time_0 <= gap_length_in;
        gap_time_1 <= gap_time_0 + gap_length_in;
        gap_time_2 <= gap_time_1 + gap_length_in;
        gap_time_3 <= gap_time_2 + gap_length_in;
        gap_time_4 <= gap_time_3 + gap_length_in;
        gap_time_5 <= gap_time_4 + gap_length_in;
        gap_time_6 <= gap_time_5 + gap_length_in;
        gap_time_7 <= gap_time_6 + gap_length_in;
        
        -- What did we quantise each of the last 8 gaps to be?
        gap_quanta_7 <= gap_quanta_6;
        gap_quanta_6 <= gap_quanta_5;
        gap_quanta_5 <= gap_quanta_4;
        gap_quanta_4 <= gap_quanta_3;
        gap_quanta_3 <= gap_quanta_2;
        gap_quanta_2 <= gap_quanta_1;
        gap_quanta_1 <= gap_quanta_0;

        gap_time_ticks0 <= x"0000";
        gap_time_ticks1 <= gap_time_ticks0;
        gap_time_ticks2 <= gap_time_ticks1;
        gap_time_ticks3 <= gap_time_ticks2;
        gap_time_ticks4 <= gap_time_ticks3;
        gap_time_ticks5 <= gap_time_ticks4;
        gap_time_ticks6 <= gap_time_ticks5;
        gap_time_ticks7 <= gap_time_ticks6;

        gap_time_remainders0 <= x"00";
        gap_time_remainders1 <= gap_time_remainders0;
        gap_time_remainders2 <= gap_time_remainders1;
        gap_time_remainders3 <= gap_time_remainders2;
        gap_time_remainders4 <= gap_time_remainders3;
        gap_time_remainders5 <= gap_time_remainders4;
        gap_time_remainders6 <= gap_time_remainders5;
        gap_time_remainders7 <= gap_time_remainders6;
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
      
      -- Work out the summed whole and remainder parts
      -- gap_time_ticks0 and gap_time_remainders0 has been updated when
      -- this is required.
      -- First accumulated is just the actual value:
      gap_accum_ticks0 <= gap_time_ticks0;
      gap_accum_remainders0 <= gap_time_remainders0;
--      report "gap_time_remainders0 = " & integer'image(to_integeR(gap_time_remainders0));
      -- Then we need to add the time of the relevant gap to the accumulated
      -- from the previous
      gap_accum_ticks1 <= gap_accum_ticks0 + gap_time_ticks1;
      gap_accum_ticks2 <= gap_accum_ticks1 + gap_time_ticks2;
      gap_accum_ticks3 <= gap_accum_ticks2 + gap_time_ticks3;
      gap_accum_ticks4 <= gap_accum_ticks3 + gap_time_ticks4;
      gap_accum_ticks5 <= gap_accum_ticks4 + gap_time_ticks5;
      gap_accum_ticks6 <= gap_accum_ticks5 + gap_time_ticks6;
      gap_accum_ticks7 <= gap_accum_ticks6 + gap_time_ticks7;
      gap_accum_remainders1 <= gap_accum_remainders0 + gap_time_remainders1;
      gap_accum_remainders2 <= gap_accum_remainders1 + gap_time_remainders2;
      gap_accum_remainders3 <= gap_accum_remainders2 + gap_time_remainders3;
      gap_accum_remainders4 <= gap_accum_remainders3 + gap_time_remainders4;
      gap_accum_remainders5 <= gap_accum_remainders4 + gap_time_remainders5;
      gap_accum_remainders6 <= gap_accum_remainders5 + gap_time_remainders6;
      gap_accum_remainders7 <= gap_accum_remainders6 + gap_time_remainders7;
        
      if report_recent='1' then
        report_recent <= '0';
        report "     Recent gaps: "
          & integer'image(to_integer(gap_quanta_7)) & ", "
          & integer'image(to_integer(gap_quanta_6)) & ", "
          & integer'image(to_integer(gap_quanta_5)) & ", "
          & integer'image(to_integer(gap_quanta_4)) & ", "
          & integer'image(to_integer(gap_quanta_3)) & ", "
          & integer'image(to_integer(gap_quanta_2)) & ", "
          & integer'image(to_integer(gap_quanta_1)) & ", "
          & integer'image(to_integer(gap_quanta_0));
        report "Recent Gap Times: "
          & integer'image(to_integer(gap_time_7)) & ", "
          & integer'image(to_integer(gap_time_6)) & ", "
          & integer'image(to_integer(gap_time_5)) & ", "
          & integer'image(to_integer(gap_time_4)) & ", "
          & integer'image(to_integer(gap_time_3)) & ", "
          & integer'image(to_integer(gap_time_2)) & ", "
          & integer'image(to_integer(gap_time_1)) & ", "
          & integer'image(to_integer(gap_time_0));
        report "         Divided: "
          & integer'image(to_integer(gap_time_ticks7)) & ", "
          & integer'image(to_integer(gap_time_ticks6)) & ", "
          & integer'image(to_integer(gap_time_ticks5)) & ", "
          & integer'image(to_integer(gap_time_ticks4)) & ", "
          & integer'image(to_integer(gap_time_ticks3)) & ", "
          & integer'image(to_integer(gap_time_ticks2)) & ", "
          & integer'image(to_integer(gap_time_ticks1)) & ", "
          & integer'image(to_integer(gap_time_ticks0));
        report "      Remainders: "
          & integer'image(to_integer(gap_time_remainders7)) & ", "
          & integer'image(to_integer(gap_time_remainders6)) & ", "
          & integer'image(to_integer(gap_time_remainders5)) & ", "
          & integer'image(to_integer(gap_time_remainders4)) & ", "
          & integer'image(to_integer(gap_time_remainders3)) & ", "
          & integer'image(to_integer(gap_time_remainders2)) & ", "
          & integer'image(to_integer(gap_time_remainders1)) & ", "
          & integer'image(to_integer(gap_time_remainders0));
        report "   Accum Divided: "
          & integer'image(to_integer(gap_accum_ticks7)) & ", "
          & integer'image(to_integer(gap_accum_ticks6)) & ", "
          & integer'image(to_integer(gap_accum_ticks5)) & ", "
          & integer'image(to_integer(gap_accum_ticks4)) & ", "
          & integer'image(to_integer(gap_accum_ticks3)) & ", "
          & integer'image(to_integer(gap_accum_ticks2)) & ", "
          & integer'image(to_integer(gap_accum_ticks1)) & ", "
          & integer'image(to_integer(gap_accum_ticks0));
        report "Accum Remainders: "
          & integer'image(to_integer(gap_accum_remainders7)) & ", "
          & integer'image(to_integer(gap_accum_remainders6)) & ", "
          & integer'image(to_integer(gap_accum_remainders5)) & ", "
          & integer'image(to_integer(gap_accum_remainders4)) & ", "
          & integer'image(to_integer(gap_accum_remainders3)) & ", "
          & integer'image(to_integer(gap_accum_remainders2)) & ", "
          & integer'image(to_integer(gap_accum_remainders1)) & ", "
          & integer'image(to_integer(gap_accum_remainders0));
      end if;
      
      case state is
        when dividing_bucket_into_gap_quant0 =>
          if bucket >= cycles_per_interval then
            gap_quanta_0 <= gap_quanta_0 + 1;
            bucket <= bucket - cycles_per_interval;
          else
            -- Now its just a remainder
            report "Gap is " & integer'image(to_integer(gap_quanta_0)) & ", remainder " & integer'image(to_integer(bucket));
            if bucket > cycles_per_interval(7 downto 1) then
              report "Round gap up to next";
              gap_quanta_0 <= gap_quanta_0 + 1;
              gap_time_ticks0 <= gap_quanta_0 + 1;
              gap_time_remainders0 <= signed(bucket(7 downto 0)) - signed(cycles_per_interval);
            else
              gap_time_ticks0 <= gap_quanta_0;
              gap_time_remainders0 <= signed(bucket(7 downto 0));
            end if;
            -- Now wait for the sums of recent gaps to propagate through
            state <= WaitForSums;
            wait_counter <= 8;
          end if;
        when WaitForSums =>
          if wait_counter=0 then
            report_recent <= '1';
            state <= Idle;
          else
            wait_counter <= wait_counter - 1;
          end if;
        when others =>
          null;
      end case;
    end if;
  end process;
end behavioural;
