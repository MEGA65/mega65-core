
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
-- 100000001001000
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

    cycles_per_interval : in unsigned(7 downto 0);
    write_precomp_enable : in std_logic := '0';
    write_precomp_magnitude : in unsigned(7 downto 0) := x"01";
    write_precomp_magnitude_b : in unsigned(7 downto 0) := x"02";
    
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

  signal last_bit0 : std_logic := '0';

  signal clock_bits : unsigned(7 downto 0) := x"FF";

  signal bit_queue : unsigned(15 downto 0);
  signal bits_queued : integer range 0 to 16 := 0;

  -- Work out when to write a bit
  signal interval_countdown : integer range 0 to 255 := 0;
  signal transition_point : integer range 0 to 256 := 256;

  -- And then any adjustments for write precompensation
  signal f_write_time_adj : integer range -128 to 127 := 0;
  signal f_write_buf : std_logic_vector(6 downto 0) := "0000000";
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
  
begin

  process (clock40mhz) is
    variable state : unsigned(2 downto 0) := "000";
  begin
    if rising_edge(clock40mhz) then

      transition_point <= to_integer(cycles_per_interval(7 downto 1));        
      
      if interval_countdown = 0 then
        interval_countdown <= to_integer(cycles_per_interval);
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
        f_write_buf(6 downto 1) <= f_write_buf(5 downto 0);

        -- Get next bit ready for writing 
        f_write_next <= f_write_buf(3);

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
            when others =>
              -- All other combinations are invalid for RLL encoding, so do no
              -- write precompensation
              f_write_time_adj <= 0;                
              report "WPRECOMP: OTHERS";
          end case;
        end if;
        
        bit_queue(15 downto 1) <= bit_queue(14 downto 0);
        if bits_queued /= 0 then
--          report "RLLFLOPPY: Decrement bits_queued to " & integer'image(bits_queued - 1);
          bits_queued <= bits_queued - 1;
        end if;

      end if;

      if show_bit_sequence='1' then
        report "RLL bit sequence: " & to_string(std_logic_vector(bit_queue));
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

      if bits_queued = 0 and byte_in_buffer='1' then
        report "RLLFLOPPY: emitting buffered byte $" & to_hstring(next_byte) & " (latched clock byte $" & to_hstring(latched_clock_byte) &") for encoding.";
        bits_queued <= 16;
        -- Get the bits to send
        -- Combined data and clock byte to produce the full vector.        
        bit_queue(15) <= (last_bit0 nor next_byte(7)) xor not latched_clock_byte(7);
        bit_queue(14) <= next_byte(7);
        bit_queue(13) <= (next_byte(7) nor next_byte(6)) xor not latched_clock_byte(6);
        bit_queue(12) <= next_byte(6);
        bit_queue(11) <= (next_byte(6) nor next_byte(5)) xor not latched_clock_byte(5);
        bit_queue(10) <= next_byte(5);
        bit_queue( 9) <= (next_byte(5) nor next_byte(4)) xor not latched_clock_byte(4);
        bit_queue( 8) <= next_byte(4);
        bit_queue( 7) <= (next_byte(4) nor next_byte(3)) xor not latched_clock_byte(3);
        bit_queue( 6) <= next_byte(3);
        bit_queue( 5) <= (next_byte(3) nor next_byte(2)) xor not latched_clock_byte(2);
        bit_queue( 4) <= next_byte(2);
        bit_queue( 3) <= (next_byte(2) nor next_byte(1)) xor not latched_clock_byte(1);
        bit_queue( 2) <= next_byte(1);
        bit_queue( 1) <= (next_byte(1) nor next_byte(0)) xor not latched_clock_byte(0);
        bit_queue( 0) <= next_byte(0);
        last_bit0 <= next_byte(0);

        show_bit_sequence <= '1';

        -- Shuffle down byte buffer, if required
        if byte_in_buffer_2 = '1' then
          next_byte <= next_byte_2;
          latched_clock_byte <= latched_clock_byte_2;
          byte_in_buffer <= '1';
          byte_in_buffer_2 <= '0';
          report "shuffling down next byte = $" & to_hstring(next_byte_2) & to_hstring(latched_clock_byte_2);
        else
          byte_in_buffer <= '0';          
        end if;
        -- Make sure ready_for_next produces an edge each time it triggers
        ready_for_next <= '0';
        ready_for_next_delayed <= '1';
        report "asserting ready_for_next";
      elsif ingest_byte_toggle /= last_ingest_byte_toggle then
        -- We have another byte to ingest, so do it now.
        last_ingest_byte_toggle <= ingest_byte_toggle;
      
        if byte_in_buffer='1' and byte_in_buffer_2 = '0' then
          -- No byte in 2nd byte buffer, so store it
          next_byte_2 <= byte_in;
          byte_in_buffer_2 <= '1';
          ready_for_next <= '0';
          clock_byte_target <= '1';
          report "clearing ready_for_next after store in next_byte_2";
        elsif byte_in_buffer = '0' then
          -- No byte in the byte buffer, so store it
          byte_in_buffer <= '1';
          next_byte <= byte_in;
          -- Make sure we produce an edge for ready_for_next
          ready_for_next <= '0';
          ready_for_next_delayed <= '1';
          clock_byte_target <= '0';
          report "asserting ready_for_next after store in next_byte (delayed)";
        end if;
        report "latching data byte $" & to_hstring(byte_in);
        -- Then set timer to latch the clock.
        -- For bug-compatibility with C65 DOS code, this should be done
        -- at least 4x 3.5MHz clock cycles after the data byte has been
        -- written, to allow the STA <data> / STX <clock> sequenc to work
        -- 40.5MHz / 3.54MHz x (4+1 cycles) = 57.2 cycles
        -- We can in fact allow a bit of margin on this, so lets go with 63
        -- cycles
        clock_latch_timer <= 63;
      elsif ready_for_next_delayed = '1' then
        ready_for_next <= '1';
        ready_for_next_delayed <= '0';
      end if;
    end if;    
  end process;
end behavioural;

