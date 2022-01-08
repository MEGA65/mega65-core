
-- RLL2,7 Encoding table (one of several possible):
--
-- Input    Encoded
-- 
-- 11       1000
-- 10       0100
-- 000      100100
-- 010      000100
-- 011      001000
-- 0011     00001000
-- 0010     00100100 
--
-- Sync mark:
--
-- 100000001001
--
-- but to preserve RLL2,7 rules, we have to write:
-- 10000000100100
--
-- so that we can't end up with a 1 too soon after the sync mark,
-- and make sure that we know exactly where we are upto in decoding.
--

use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity rll27_bits_to_gaps is
  port (
    clock40mhz : in std_logic;

    enabled : in std_logic;
    
    cycles_per_interval : in unsigned(7 downto 0);
    write_precomp_enable : in std_logic := '0';
    write_precomp_magnitude : in unsigned(7 downto 0) := x"00";
    write_precomp_magnitude_b : in unsigned(7 downto 0) := x"00";
    write_precomp_delay15 : in unsigned(7 downto 0) := x"00";
    
    -- Are we ready to accept something?
    ready_for_next : out std_logic := '1';

    -- Do we have no data to write?
    no_data : out std_logic := '1';
    
    -- Magnetic inversions as output
    f_write : out std_logic := '0';

    -- Input bits fo encoding
    byte_valid : in std_logic := '0';
    byte_in : in unsigned(7 downto 0);

    -- Clock bits
    -- This gets inverted before being XORd with the intended clock bits
    clock_byte_in : in unsigned(7 downto 0) := x"FF"

    
    );
end rll27_bits_to_gaps;

architecture behavioural of rll27_bits_to_gaps is

  signal clock_bits : unsigned(7 downto 0) := x"FF";

  signal bit_queue : unsigned(15 downto 0);
  signal bits_queued : integer range 0 to 16 := 0;

  signal bit_buffer : unsigned(15 downto 0) := (others => '0');
  signal clock_buffer : unsigned(15 downto 0) := (others => '0');
  signal bits_in_buffer : integer range 0 to 16 := 0;
  
  -- Work out when to write a bit
  signal interval_countdown : integer range 0 to 255 := 0;
  signal transition_point : integer range 0 to 256 := 256;

  -- And then any adjustments for write precompensation
  signal f_write_time_adj : integer range -128 to 127 := 0;
  signal f_write_buf : std_logic_vector(8 downto 0) := "000000000";
  signal f_write_next : std_logic := '0';

  signal ingest_byte_toggle : std_logic := '0';
  signal last_ingest_byte_toggle : std_logic := '0';
  signal byte_in_buffer : std_logic := '0';
  signal byte_in_buffer_2 : std_logic := '0';
  signal next_byte : unsigned(7 downto 0) := x"00";
  signal next_byte_2 : unsigned(7 downto 0) := x"00";
  signal latched_clock_byte : unsigned(7 downto 0) := x"FF";
  signal latched_clock_byte_2 : unsigned(7 downto 0) := x"FF";
  signal clock_latch_timer : integer range 0 to 63 := 0;
  signal clock_byte_target : std_logic := '0';
  signal ready_for_next_delayed : std_logic := '0';
  signal show_bit_sequence : std_logic := '0';
  signal next_is_sync : std_logic := '0';
  
begin

  process (clock40mhz) is
    variable state : unsigned(2 downto 0) := "000";
  begin
    if rising_edge(clock40mhz) then

      transition_point <= to_integer(cycles_per_interval(7 downto 1));        
      
      if interval_countdown = 0 then
        -- Count from n-1 downto 0, so that each interval is n cycles long
        interval_countdown <= to_integer(cycles_per_interval - 1);
        f_write <= '1';
      else
        interval_countdown <= interval_countdown - 1;
      end if;

      -- Request flux reversal half way through the bit,
      -- and it stays asserted until the end of the bit, i.e., 0.5 x WCLK
      -- to match description on page 79 in Figure 7 of
      -- https://www.mouser.com/datasheet/2/268/37c78-468028.pdf

      -- Emit pulse with write precompensation
      if interval_countdown = transition_point + f_write_time_adj then
        report "Writing bit " & std_logic'image(f_write_next) &
          " at " & integer'image(transition_point) & " + " & integer'image(f_write_time_adj);
        f_write <= not f_write_next;
      end if;
        
      if interval_countdown = 0 then
--        report "RLL bit " & std_logic'image(bit_queue(15));
        f_write_buf(0) <= bit_queue(15);
        f_write_buf(8 downto 1) <= f_write_buf(7 downto 0);

        -- Get next bit ready for writing 
        f_write_next <= f_write_buf(4);

        if write_precomp_enable='0' then
          -- No write precompensation, so emit bit at the right time.
          f_write_time_adj <= 0;
          report "WPRECOMP: Disabled";
        else
          report "f_write_buf = " & to_string(f_write_buf);
          case f_write_buf is
            -- XXX Implement RLL-compatible write-precomp
            -- Pulse timing is more important in RLL than MFM, because
            -- we have gaps of 2 -- 7 time units, but we run at 1.5x MFM
            -- data rate, which means those gaps are only 2/3 of those
            -- nominal widths, and we thus have to be able to discriminate
            -- between deltas of 2/3 of an MFM time-step.
            when "010010000" =>
              -- short pulse before, long one after : pulse will be pushed
              -- early, so write it a bit late
              if enabled='1' then
                report "WPRECOMP: Late(b)";
              end if;
              f_write_time_adj <= to_integer(write_precomp_magnitude_b);
            when "100010000" =>
              -- medium pulse before, long one after : pulse will be pushed
              -- early, so write it a bit late
              if enabled='1' then
                report "WPRECOMP: Late";
              end if;
              f_write_time_adj <= to_integer(write_precomp_magnitude) + to_integer(write_precomp_delay15);
            when "000010000" =>
              -- equal length pulses either side
              f_write_time_adj <= 0;
              if enabled='1' then
                report "WPRECOMP: Equal";
              end if;
            when "010010010" =>
              -- equal length pulses either side
              f_write_time_adj <= 0;
              if enabled='1' then
                report "WPRECOMP: Equal";
              end if;
            when "100010010" =>
              -- Medium pulse before, short one after : pulse will be pushed late,
              -- so write it a bit early
              if enabled='1' then
                report "WPRECOMP: Early";
              end if;
              f_write_time_adj <= to_integer(write_precomp_delay15) - to_integer(write_precomp_magnitude);
            when "000010010" =>
              -- Long pulse before, short one after
              -- 
              f_write_time_adj <= - to_integer(write_precomp_magnitude_b);
              if enabled='1' then
                report "WPRECOMP: Early(b)";
              end if;
            when "010010001" =>
              -- Short pulse before, medium after
              f_write_time_adj <= to_integer(write_precomp_magnitude);
              if enabled='1' then
                report "WPRECOMP: Late";
              end if;
            when "100010001" =>
              -- equal length pulses either side
              f_write_time_adj <=  to_integer(write_precomp_delay15);
              if enabled='1' then
                report "WPRECOMP: Equal";
              end if;
            when "000010001" =>
              -- Long pulse before, medium after
              f_write_time_adj <= - to_integer(write_precomp_magnitude);
              if enabled='1' then
                report "WPRECOMP: Early";
              end if;
            when others =>
              -- All other combinations are invalid for RLL encoding, so do no
              -- write precompensation
              f_write_time_adj <= 0;                
              report "WPRECOMP: OTHERS";
          end case;
        end if;
        
        bit_queue(15 downto 1) <= bit_queue(14 downto 0);
        if bits_queued /= 0 then
          report "RLLFLOPPY: Decrement bits_queued to " & integer'image(bits_queued - 1);
          bits_queued <= bits_queued - 1;
        end if;

      end if;

      if show_bit_sequence='1' then
        report "RLL bit sequence: " & to_string(std_logic_vector(bit_queue))
          & "  (" & integer'image(bits_queued) & " bits queued)";
        show_bit_sequence <= '0';
      end if;
                  
      -- XXX C65 DOS source indicates that clock byte should be
      -- written AFTER data byte has been written.
      -- C65 Specifications guide is, however, silent on this, and
      -- the Track Writes section shows a procedure where it would
      -- seem that either can come first.
      -- This is all a problem for us, as we currently latch the clock
      -- when a data byte is written in the logic below.  Probably we
      -- should instead latch only the data byte, and combine the clock
      -- bits only when we are about to get ready to send it.
      -- We get around this by buffering one byte, thus the delayed write to
      -- the clock gets used for the byte just written when it gets output
      -- after the current byte

      -- XXX Another problem is that we should wait for the next index
      -- pulse before starting to write. Currently we just start writing.

      if bits_queued = 0 and byte_in_buffer='0' then
        no_data <= '1';
--        report "RLL: No data!";
      else
        no_data <= '0';
      end if;

      if clock_latch_timer = 1 then
        if clock_byte_target='0' then
          latched_clock_byte <= clock_byte_in;
          report "latching clock byte $" & to_hstring(clock_byte_in);
        else
          latched_clock_byte_2 <= clock_byte_in;
          report "latching clock byte 2 $" & to_hstring(clock_byte_in);
        end if;
--        if latched_clock_byte /= clock_byte_in then
--          report "latching clock byte $" & to_hstring(clock_byte_in);
--        end if;
      end if;
      if clock_latch_timer /= 0 then
        clock_latch_timer <= clock_latch_timer - 1;
      end if;

      -- Make sure we don't miss the byte_valid flag
      if byte_valid='1' then
        ingest_byte_toggle <= not ingest_byte_toggle;
      end if;
      
      if next_byte = x"a1" and latched_clock_byte = x"fb" then
        next_is_sync <= '1';
      else
        next_is_sync <= '0';
      end if;
      
--     report "LOOPrll: Here";
      if bits_queued = 0 and (bits_in_buffer >= 8 or next_is_sync='1') then
        report "RLLFLOPPY: emitting bits from buffer: " & to_string(std_logic_vector(bit_buffer)) & "/" & to_string(std_logic_vector(clock_buffer))
          & ", " & integer'image(bits_in_buffer) & " bits in buffer, next_sync=" & std_logic'image(next_is_sync); 

        if bit_buffer(15 downto 8) = x"a1" and clock_buffer(15 downto 8) = x"fb" and (bits_in_buffer=8 or bits_in_buffer = 16) then
          report "RLL: Emitting sync mark";
          -- Write sync mark
          bit_queue(15 downto 2) <= "10000000100100";
          bits_queued <= 14;
          bit_buffer(15 downto 8) <= bit_buffer(7 downto 0);
          clock_buffer(15 downto 8) <= clock_buffer(7 downto 0);
          if bits_in_buffer > 8 then
            bits_in_buffer <= bits_in_buffer - 8;
          else
            bits_in_buffer <= 0;
          end if;
        elsif bit_buffer(15 downto 14) = "11" then
          bit_queue(15 downto 12) <= "1000";
          bits_queued <= 4;
          bit_buffer(15 downto 2) <= bit_buffer(13 downto 0);
          clock_buffer(15 downto 2) <= clock_buffer(13 downto 0);
          if bits_in_buffer > 2 then
            bits_in_buffer <= bits_in_buffer - 2;
          else
            bits_in_buffer <= 0;
          end if;
        elsif bit_buffer(15 downto 14) = "10" then
          bit_queue(15 downto 12) <= "0100";
          bits_queued <= 4;
          bit_buffer(15 downto 2) <= bit_buffer(13 downto 0);
          clock_buffer(15 downto 2) <= clock_buffer(13 downto 0);
          if bits_in_buffer > 2 then
            bits_in_buffer <= bits_in_buffer - 2;
          else
            bits_in_buffer <= 0;
          end if;
        elsif bit_buffer(15 downto 13) = "000" then
          bit_queue(15 downto 10) <= "100100";
          bits_queued <= 6;
          bit_buffer(15 downto 3) <= bit_buffer(12 downto 0);
          clock_buffer(15 downto 3) <= clock_buffer(12 downto 0);
          if bits_in_buffer > 3 then
            bits_in_buffer <= bits_in_buffer - 3;
          else
            bits_in_buffer <= 0;
          end if;
        elsif bit_buffer(15 downto 13) = "010" then
          bit_queue(15 downto 10) <= "000100";
          bits_queued <= 6;
          bit_buffer(15 downto 3) <= bit_buffer(12 downto 0);
          clock_buffer(15 downto 3) <= clock_buffer(12 downto 0);
          if bits_in_buffer > 3 then
            bits_in_buffer <= bits_in_buffer - 3;
          else
            bits_in_buffer <= 0;
          end if;
        elsif bit_buffer(15 downto 13) = "011" then
          bit_queue(15 downto 10) <= "001000";
          bits_queued <= 6;
          bit_buffer(15 downto 3) <= bit_buffer(12 downto 0);
          clock_buffer(15 downto 3) <= clock_buffer(12 downto 0);
          if bits_in_buffer > 3 then
            bits_in_buffer <= bits_in_buffer - 3;
          else
            bits_in_buffer <= 0;
          end if;            
        elsif bit_buffer(15 downto 12) = "0011" then
          bit_queue(15 downto 8) <= "00001000";
          bits_queued <= 8;
          bit_buffer(15 downto 4) <= bit_buffer(11 downto 0);
          clock_buffer(15 downto 4) <= clock_buffer(11 downto 0);
          if bits_in_buffer > 4 then
            bits_in_buffer <= bits_in_buffer - 4;
          else
            bits_in_buffer <= 0;
          end if;          
        elsif bit_buffer(15 downto 12) = "0010" then
          bit_queue(15 downto 8) <= "00100100";
          bits_queued <= 8;
          bit_buffer(15 downto 4) <= bit_buffer(11 downto 0);
          clock_buffer(15 downto 4) <= clock_buffer(11 downto 0);
          if bits_in_buffer > 4 then
            bits_in_buffer <= bits_in_buffer - 4;
          else
            bits_in_buffer <= 0;
          end if;            
        end if;
        
        show_bit_sequence <= '1';
      elsif byte_in_buffer = '1' and (next_is_sync='0' or bits_in_buffer=0) then
--        report "SHUFFLErll: Byte in buffer: " & integer'image(bits_in_buffer) & " bits in buffer";
        if bits_in_buffer < 9 then
          report "RLLENCODE: Importing byte $" & to_hstring(next_byte) &" with " & integer'image(bits_in_buffer) & " bits already in the buffer.";
          bit_buffer((15 - bits_in_buffer) downto (8 - bits_in_buffer)) <= next_byte;
          clock_buffer((15 - bits_in_buffer) downto (8 - bits_in_buffer)) <= latched_clock_byte;
          bits_in_buffer <= bits_in_buffer + 8;

          byte_in_buffer <= byte_in_buffer_2;
          byte_in_buffer_2 <= '0';
          next_byte <= next_byte_2;
          latched_clock_byte <= latched_clock_byte_2;
          -- make sure we don't get stuck sync byte
          -- indication                                    
          next_byte_2 <= x"00"; next_is_sync <= '0';

          -- Make sure ready_for_next produces an edge each time it triggers
          ready_for_next <= '0';
          ready_for_next_delayed <= '1';
          report "asserting ready_for_next";
        end if;
        
      elsif ingest_byte_toggle /= last_ingest_byte_toggle then
        -- We have another byte to ingest, so do it now.
        report "RLL: Ingesting a byte";
      
        if byte_in_buffer='1' and byte_in_buffer_2 = '0' then
          -- No byte in 2nd byte buffer, so store it
          next_byte_2 <= byte_in;
          byte_in_buffer_2 <= '1';
          ready_for_next <= '0';
          clock_byte_target <= '1';
          report "NEXTBYTE2: clearing ready_for_next after store in next_byte_2";
          last_ingest_byte_toggle <= ingest_byte_toggle;
          report "RLL: latching data byte $" & to_hstring(byte_in);
          clock_latch_timer <= 63;          
        elsif byte_in_buffer = '0' then
          -- No byte in the byte buffer, so store it
          byte_in_buffer <= '1';
          next_byte <= byte_in;
          -- Make sure we produce an edge for ready_for_next
          ready_for_next <= '0';
          ready_for_next_delayed <= '1';
          clock_byte_target <= '0';
--          report "NEXTBYTE1: asserting ready_for_next after store in next_byte (delayed)";
          last_ingest_byte_toggle <= ingest_byte_toggle;
          report "RLL: latching data byte $" & to_hstring(byte_in);
          clock_latch_timer <= 63;          
        end if;
        -- Then set timer to latch the clock.
        -- For bug-compatibility with C65 DOS code, this should be done
        -- at least 4x 3.5MHz clock cycles after the data byte has been
        -- written, to allow the STA <data> / STX <clock> sequenc to work
        -- 40.5MHz / 3.54MHz x (4+1 cycles) = 57.2 cycles
        -- We can in fact allow a bit of margin on this, so lets go with 63
        -- cycles
      elsif ready_for_next_delayed = '1' then
--        report "RLL: ready_for_next delayed strobe";
        ready_for_next <= '1';
        ready_for_next_delayed <= '0';
      else
--        report "IDLErll: Nothing to do: "
--          & "byte_in_buffer=" & std_logic'image(byte_in_buffer)
--          & ", byte_in_buffer_2=" & std_logic'image(byte_in_buffer_2)
--          & ", bits_queued=" & integer'image(bits_queued)
--          & ", bits_in_buffer=" & integer'image(bits_in_buffer)
--          ;

        if byte_in_buffer_2='0' then
          ready_for_next <= '0';
          ready_for_next_delayed <= '1';
--          report "asserting ready_for_next";
        end if;
      end if;
    end if;    
  end process;
end behavioural;

