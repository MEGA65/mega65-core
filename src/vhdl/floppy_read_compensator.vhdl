
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

  type vector_t is array(0 to 15) of unsigned(15 downto 0);
  type svector_t is array(0 to 15) of signed(15 downto 0);

  -- The raw gap arrival times in T-minus domain
  signal gap_times : vector_t;

  -- The (possibly corrected) quantised gaps, so that we can
  -- work out how to apply the previous gap times as baselines
  signal recent_gaps : vector_t := (others => to_unsigned(0,16));

  signal cumulative_quant_gaps : vector_t := (others => to_unsigned(0,16));
  
  -- Then we need the raw quantised gaps and remainders for each
  signal baseline_gaps : vector_t := (others => to_unsigned(0,16));
  signal baseline_remainders : svector_t := (others => to_signed(0,16));

  
  signal average : unsigned(15 downto 0) := to_unsigned(0,16);
  signal average_remain : signed(15 downto 0) := to_signed(0,16);
  
  type state_t is (idle,
                   dividing_bucket_into_gap_quant0,
                   WaitForSums, CorrectRemainders, CalculateMeanAndCountVotes,
                   AdjustMean
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
        gap_times(0) <= gap_length_in;
        for i in 1 to 7 loop
          gap_times(i) <= gap_times(i-1) + gap_length_in;
        end loop;
        
        -- What did we quantise each of the last 8 gaps to be?
        for i in 1 to 7 loop
          recent_gaps(i) <= recent_gaps(i-1);
        end loop;
        
        -- Now we need to work out what the quantisation for the current gap is.
        -- This would be the easy way, if we had hardware immediate division
        -- and floating point:
        -- gap_quanta0 = gap_length_in / cycles_per_interval
        -- Instead we can work out the integer part using repeated subtraction,
        -- and then take a look at the remainder.
        recent_gaps(0) <= to_unsigned(0,16);
        bucket <= gap_length_in;
        state <= dividing_bucket_into_gap_quant0;

      end if;

      for i in 1 to 7 loop
        cumulative_quant_gaps(i) <= cumulative_quant_gaps(i-1) + recent_gaps(i);
      end loop;
      
      if report_recent='1' then
        report_recent <= '0';
        report "Recent gaps (uncorr): "
          & integer'image(to_integer(recent_gaps(7))) & ", "
          & integer'image(to_integer(recent_gaps(6))) & ", "
          & integer'image(to_integer(recent_gaps(5))) & ", "
          & integer'image(to_integer(recent_gaps(4))) & ", "
          & integer'image(to_integer(recent_gaps(3))) & ", "
          & integer'image(to_integer(recent_gaps(2))) & ", "
          & integer'image(to_integer(recent_gaps(1))) & ", "
          & integer'image(to_integer(recent_gaps(0)));

        report " Recent Gap Times T-: "
          & integer'image(to_integer(gap_times(7))) & ", "
          & integer'image(to_integer(gap_times(6))) & ", "
          & integer'image(to_integer(gap_times(5))) & ", "
          & integer'image(to_integer(gap_times(4))) & ", "
          & integer'image(to_integer(gap_times(3))) & ", "
          & integer'image(to_integer(gap_times(2))) & ", "
          & integer'image(to_integer(gap_times(1))) & ", "
          & integer'image(to_integer(gap_times(0)));

        report "     Cumulative gaps: "
          & integer'image(to_integer(cumulative_quant_gaps(7))) & ", "
          & integer'image(to_integer(cumulative_quant_gaps(6))) & ", "
          & integer'image(to_integer(cumulative_quant_gaps(5))) & ", "
          & integer'image(to_integer(cumulative_quant_gaps(4))) & ", "
          & integer'image(to_integer(cumulative_quant_gaps(3))) & ", "
          & integer'image(to_integer(cumulative_quant_gaps(2))) & ", "
          & integer'image(to_integer(cumulative_quant_gaps(1))) & ", "
          & integer'image(to_integer(cumulative_quant_gaps(0)));

        report "       Baseline gaps: "
          & integer'image(to_integer(baseline_gaps(7)) + to_integer(recent_gaps(0)) - to_integer(cumulative_quant_gaps(7))) & ", "
          & integer'image(to_integer(baseline_gaps(6)) + to_integer(recent_gaps(0)) - to_integer(cumulative_quant_gaps(6))) & ", "
          & integer'image(to_integer(baseline_gaps(5)) + to_integer(recent_gaps(0)) - to_integer(cumulative_quant_gaps(5))) & ", "
          & integer'image(to_integer(baseline_gaps(4)) + to_integer(recent_gaps(0)) - to_integer(cumulative_quant_gaps(4))) & ", " 
          & integer'image(to_integer(baseline_gaps(3)) + to_integer(recent_gaps(0)) - to_integer(cumulative_quant_gaps(3))) & ", "
          & integer'image(to_integer(baseline_gaps(2)) + to_integer(recent_gaps(0)) - to_integer(cumulative_quant_gaps(2))) & ", "
          & integer'image(to_integer(baseline_gaps(1)) + to_integer(recent_gaps(0)) - to_integer(cumulative_quant_gaps(1))) & ", "
          & integer'image(to_integer(baseline_gaps(0)) + to_integer(recent_gaps(0)) - to_integer(cumulative_quant_gaps(0)));
        
        report " Baseline remainders: "
          & integer'image(to_integer(baseline_remainders(7))) & ", "
          & integer'image(to_integer(baseline_remainders(6))) & ", "
          & integer'image(to_integer(baseline_remainders(5))) & ", "
          & integer'image(to_integer(baseline_remainders(4))) & ", "
          & integer'image(to_integer(baseline_remainders(3))) & ", "
          & integer'image(to_integer(baseline_remainders(2))) & ", "
          & integer'image(to_integer(baseline_remainders(1))) & ", "
          & integer'image(to_integer(baseline_remainders(0)));
        



        
        report "             Average: "
          & integer'image(to_integer(average(15 downto 3))) & ", remainder " & integer'image(to_integer(average_remain(7 downto 3)));
      end if;
      
      case state is
        when dividing_bucket_into_gap_quant0 =>
          if bucket >= cycles_per_interval then
            recent_gaps(0) <= recent_gaps(0) + 1;
            bucket <= bucket - cycles_per_interval;
          else
            -- Now its just a remainder
            report "Gap is " & integer'image(to_integer(recent_gaps(0))) & ", remainder " & integer'image(to_integer(bucket));
            if bucket > cycles_per_interval(7 downto 1) then
              report "Round gap up to next";
              recent_gaps(0) <= recent_gaps(0) + 1;              
--              gap_time_ticks0 <= recent_gaps(0) + 1;
--              gap_time_remainders0 <= signed(bucket(7 downto 0)) - signed(cycles_per_interval);
            else
--              gap_time_ticks0 <= recent_gaps(0);
--              gap_time_remainders0 <= signed(bucket(7 downto 0));
            end if;
            -- Now wait for the sums of recent gaps to propagate through
            state <= WaitForSums;
            wait_counter <= 8;
          end if;
        when WaitForSums =>

          cumulative_quant_gaps(0) <= recent_gaps(0);
          
          for i in 0 to 7 loop
            baseline_gaps(i) <= gap_times(i) / to_integer(cycles_per_interval);
            baseline_remainders(i) <= to_signed(to_integer(gap_times(i))
                                      - ( to_integer(gap_times(i)) / to_integer(cycles_per_interval) ) * to_integer(cycles_per_interval),16);
          end loop;
          
          if wait_counter=0 then
            state <= CorrectRemainders;
          else
            wait_counter <= wait_counter - 1;
          end if;
        when CorrectRemainders =>

          -- Adjust baselines for large remainders,
          -- and calculate the mean values _before_ adjusting, so that the
          -- maths is much easier
          for i in 0 to 7 loop
            if baseline_remainders(i) >= to_integer(cycles_per_interval(7 downto 1)) then
              baseline_remainders(i) <= baseline_remainders(i) - to_integer(cycles_per_interval);
              baseline_gaps(i) <= baseline_gaps(i) + 1;
            end if;
          end loop;

          state <= CalculateMeanAndCountVotes;
        when CalculateMeanAndCountVotes =>

          -- Calculating the mean needs to handle the fractional part as well
          -- This will be in 8th of cycles_per_interval, so we can correct the
          -- remainder for this.
--          average <= gap_hypo0 + gap_hypo1 + gap_hypo2 + gap_hypo3
--                     + gap_hypo4 + gap_hypo5 + gap_hypo6 + gap_hypo7;
--          average_remain <= gap_accum_remainders0 + gap_accum_remainders1 + gap_accum_remainders2 + gap_accum_remainders3
--                            + gap_accum_remainders4 + gap_accum_remainders5 + gap_accum_remainders6 + gap_accum_remainders7;
          
          state <= AdjustMean;
        when AdjustMean =>
          report_recent <= '1';
          report "adjust mean: bits = " & to_string(std_logic_vector(average(2 downto 0)));
          report "average remain before = " & integer'image(to_integer(average_remain));
          case average(2 downto 0) is
            when "001" => average_remain <= average_remain + to_integer(cycles_per_interval(7 downto 3));
            when "010" => average_remain <= average_remain + to_integer(cycles_per_interval(7 downto 2));
            when "011" => average_remain <= average_remain + to_integer(cycles_per_interval(7 downto 1))
                                         - to_integer(cycles_per_interval(7 downto 2));
            when "100" => average_remain <= average_remain + to_integer(cycles_per_interval(7 downto 1));
            when "101" => average_remain <= average_remain + to_integer(cycles_per_interval(7 downto 1))
                      + to_integer(cycles_per_interval(7 downto 3));  
            when "110" => average_remain <= average_remain + to_integer(cycles_per_interval(7 downto 1))
                      + to_integer(cycles_per_interval(7 downto 2));
            when "111" => average_remain <= average_remain + to_integer(cycles_per_interval) - to_integer(cycles_per_interval(7 downto 2));
            when others => null;
          end case;
          state <= Idle;
        when others =>
          null;
      end case;
    end if;
  end process;
end behavioural;
