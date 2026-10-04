-- LUMP: Linear Uncomplicated Memory Port
--
-- Shared definitions and the small in-order command queue used by the
-- LUMP ports on the HyperRAM and SDRAM controllers.
--
-- Port contract (summary -- see ssnail-architecture.md for the full text):
--
--   * All LUMP signals live in the RAM controller's fast clock domain
--     (clock163 / clock162).
--   * Commands: READ, WRITE, INVALIDATE.  Executed strictly in order.
--     A command is accepted on a rising edge where cmd_valid='1' and
--     cmd_ready='1'.
--   * addr is a byte address local to the RAM (bit 0 = first byte of the
--     RAM), and must be 8-byte aligned.  len is in bytes, a multiple of 8,
--     from 8 to LUMP_MAX_BURST.  A burst must not cross a LUMP_MAX_BURST
--     aligned boundary.  The controllers do not check any of this.
--   * READ: the port asserts rdata_valid for exactly len/2 cycles (not
--     necessarily consecutive) with 16-bit words.  Low byte = lower address.
--     There is NO backpressure: the requester must only issue a READ when
--     it can accept the whole burst.
--   * WRITE: the port pulses wdata_req once per 16-bit word.  The source
--     must register the next word (and its byte enables) on the first
--     rising edge at which it sees wdata_req='1', and hold it until the
--     next request.  I.e., if the port asserts wdata_req as a result of
--     rising edge E, it samples wdata/wdata_be from rising edge E+2.
--     The source must therefore have the whole burst buffered before
--     issuing a WRITE.  wdata_be(0) enables the low byte, (1) the high byte.
--   * INVALIDATE: invalidates the controller's CPU-side read caches.
--     Because the queue is in order, it takes effect only after every
--     earlier WRITE has completed.
--   * cmd_done pulses for one cycle as each command completes.
--   * error pulses if a READ timed out at the device.  The port still
--     delivers the full number of (garbage) words, so the requester's
--     word counting stays consistent.
--   * idle is '1' when the queue is empty and nothing is in flight.  It is
--     registered, so only trust it from the 3rd cycle after the last
--     accepted command.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package lumptypes is
  constant LUMP_OP_READ       : unsigned(1 downto 0) := "00";
  constant LUMP_OP_WRITE      : unsigned(1 downto 0) := "01";
  constant LUMP_OP_INVALIDATE : unsigned(1 downto 0) := "10";
  -- Maximum burst in bytes.  Bursts must not cross a boundary of this size.
  -- 256 keeps HyperRAM comfortably within tCSM, and guarantees that SDRAM
  -- bursts never cross a (2KB) row.
  constant LUMP_MAX_BURST     : integer := 256;
end package;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lumptypes.all;

-- Two-entry, in-order command queue.  Head is presented from registers, so
-- the RAM controller sees no combinational path back to the requester.
-- pop is sampled on the rising edge; a controller that drives pop from a
-- register must not act on the head again in the cycle after it popped.
entity lump_queue is
  port (
    clock      : in  std_logic;

    in_valid   : in  std_logic;
    in_ready   : out std_logic;
    in_op      : in  unsigned(1 downto 0);
    in_addr    : in  unsigned(26 downto 0);
    in_len     : in  unsigned(8 downto 0);

    head_valid : out std_logic;
    head_op    : out unsigned(1 downto 0);
    head_addr  : out unsigned(26 downto 0);
    head_len   : out unsigned(8 downto 0);
    pop        : in  std_logic
    );
end lump_queue;

architecture simple of lump_queue is
  signal v0, v1   : std_logic := '0';
  signal op0, op1 : unsigned(1 downto 0) := "00";
  signal a0, a1   : unsigned(26 downto 0) := (others => '0');
  signal l0, l1   : unsigned(8 downto 0) := (others => '0');
begin

  in_ready   <= not v1;
  head_valid <= v0;
  head_op    <= op0;
  head_addr  <= a0;
  head_len   <= l0;

  process (clock) is
    variable push : boolean;
  begin
    if rising_edge(clock) then
      push := in_valid = '1' and v1 = '0';
      if pop = '1' and v0 = '1' then
        if v1 = '1' then
          -- Shift second entry to head (no push possible: we were full)
          op0 <= op1; a0 <= a1; l0 <= l1;
          v1  <= '0';
        elsif push then
          op0 <= in_op; a0 <= in_addr; l0 <= in_len;
        else
          v0 <= '0';
        end if;
      elsif push then
        if v0 = '0' then
          op0 <= in_op; a0 <= in_addr; l0 <= in_len;
          v0  <= '1';
        else
          op1 <= in_op; a1 <= in_addr; l1 <= in_len;
          v1  <= '1';
        end if;
      end if;
    end if;
  end process;

end simple;
