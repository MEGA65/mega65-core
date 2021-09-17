
use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
  
entity raw_bits_to_gaps is
  port (
    clock40mhz : in std_logic;

    enabled : in std_logic := '0';
    
    cycles_per_interval : in unsigned(7 downto 0);
    write_precomp_enable : in std_logic := '0';
    write_precomp_magnitude : in unsigned(7 downto 0) := x"01";
    write_precomp_magnitude_b : in unsigned(7 downto 0) := x"02";
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
end raw_bits_to_gaps;

architecture behavioural of raw_bits_to_gaps is

  signal last_bit0 : std_logic := '0';

  signal clock_bits : unsigned(7 downto 0) := x"FF";

  signal bit_queue : unsigned(15 downto 0);
  signal bits_queued : integer range 0 to 16 := 0;

  -- Work out when to write a bit
  signal interval_countdown : integer range 0 to 255 := 0;
  signal transition_point : integer range 0 to 256 := 256;

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

  -- http://www.bitsavers.org/pdf/teac/FD-05HF-8830.pdf
  -- 0.2 to 1.1usec pulse width for WDATA.
  -- @40.5MHz each cycle is 0.025used, so we need
  -- about 10 cycles
  signal f_write_countdown : integer range 0 to 10 := 0;
  
begin

  process (clock40mhz) is
    variable state : unsigned(2 downto 0) := "000";
  begin
    if rising_edge(clock40mhz) then

      if f_write_countdown = 0 then
        f_write <= '1';
      else
        f_write <= '0';
        f_write_countdown <= f_write_countdown - 1;
      end if;
      
      if interval_countdown /= 0 then
        interval_countdown <= interval_countdown - 1;
      else
        f_write_countdown <= 10;        
      end if;

      -- Make sure we don't miss the byte_valid flag
      if byte_valid='1' then
        ingest_byte_toggle <= not ingest_byte_toggle;
      end if;

      if interval_countdown = 0 and byte_in_buffer='1' then
        interval_countdown <= to_integer(next_byte);

        -- Shuffle down byte buffer, if required
        if byte_in_buffer_2 = '1' then
          next_byte <= next_byte_2;
          latched_clock_byte <= latched_clock_byte_2;
          byte_in_buffer <= '1';
          byte_in_buffer_2 <= '0';
          if enabled='1' then
            report "shuffling down next byte = $" & to_hstring(next_byte_2) & to_hstring(latched_clock_byte_2);
          end if;
        else
          byte_in_buffer <= '0';          
        end if;
        -- Make sure ready_for_next produces an edge each time it triggers
        ready_for_next <= '0';
        ready_for_next_delayed <= '1';
        if enabled='1' then
          report "asserting ready_for_next";
        end if;
      elsif ingest_byte_toggle /= last_ingest_byte_toggle then
        -- We have another byte to ingest, so do it now.
        last_ingest_byte_toggle <= ingest_byte_toggle;
      
        if byte_in_buffer='1' and byte_in_buffer_2 = '0' then
          -- No byte in 2nd byte buffer, so store it
          next_byte_2 <= byte_in;
          byte_in_buffer_2 <= '1';
          ready_for_next <= '0';
          clock_byte_target <= '1';
          if enabled='1' then
            report "clearing ready_for_next after store in next_byte_2";
          end if;
        elsif byte_in_buffer = '0' then
          -- No byte in the byte buffer, so store it
          byte_in_buffer <= '1';
          next_byte <= byte_in;
          -- Make sure we produce an edge for ready_for_next
          ready_for_next <= '0';
          ready_for_next_delayed <= '1';
          clock_byte_target <= '0';
          if enabled='1' then
            report "asserting ready_for_next after store in next_byte (delayed)";
          end if;
        end if;
        if enabled='1' then
          report "latching data byte $" & to_hstring(byte_in);
        end if;
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

