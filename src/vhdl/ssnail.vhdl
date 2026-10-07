-- SSNAIL: Super-Scalar Neural Arithmetic Inference Lump
--
-- SHELL VERSION.  This provides:
--   * the FastIO register interface (cpuclock domain)
--   * clock-domain crossing to the core (clock162 domain)
--   * the core sequencer: 128-bit instruction fetch from RAM, PC, STEP,
--     ABORT, error reporting, done IRQ
--   * address decoding of the linear 28-bit space onto the two LUMP ports
--   * a minimal instruction set that exercises the LUMP ports end-to-end:
--       NOP, HALT, SYNC (invalidate CPU-side caches), COPY (burst copy)
--     so the ports can be tested on real hardware before any maths exists.
--
-- Register map (base + offset).  Multi-byte values are little-endian.
--   $00      ID: $53 ('S')
--   $01      Version: $01 (shell)
--   $02      Capabilities: bit0 HyperRAM port, bit1 SDRAM port
--   $03      Control / IRQ status
--              write: bit0 GO   (load PC from job pointer and run)
--                     bit1 ABORT (stop after the current RAM transaction)
--                     bit2 SYNC CACHE (invalidate CPU-side read caches)
--                     bit3 STEP (execute one instruction at PC)
--                     bit7 write 1 to clear DONE IRQ pending
--              read:  bits 0-3 always read 0 (commands are self-clearing)
--                     bit7 DONE IRQ pending
--              => LDA/STA (or ASL/LSR) on this register acknowledges the
--                 IRQ without re-triggering any command, C64-style.
--   $04      Status (read only): bit0 busy, bit1 done (since last GO/STEP),
--                                bit2 error
--   $05      Error code (read only): 0 none, 1 illegal opcode,
--            2 address fault, 3 alignment fault, 4 RAM read error,
--            5 aborted
--   $06      IRQ enable: bit0 IRQ on job done
--   $08-$0B  Job pointer (28 bits).  Writable only while idle.
--   $0C-$0F  PC readback (28 bits)
--   $10      HyperRAM size in MB (base is fixed at $8000000). Reset: 8
--   $11      SDRAM base in MB (address bits 27-20). Reset: 0
--   $12      SDRAM size in MB. Reset: 0 (i.e. no SDRAM)
--
-- Load port: streams a model image into RAM, anywhere in the SSNAIL linear
-- space (attic RAM and SDRAM alike), without the CPU ever writing $8000000
-- itself.  The loader sets the pointer, then repeatedly: waits for READY,
-- DMAs a 512-byte SD card sector into the data register (destination held),
-- and reads the next sector.
--   $14-$16  Load pointer bits 0-23.  Writes are staged until $17 is written.
--            Reads return the live pointer (it advances with every byte).
--   $17      Write: bits 0-3 = pointer bits 24-27; this commits the new
--            pointer.  Any bytes not yet written to RAM go out first, to the
--            old pointer, so writing $17 also serves as "flush" at the end.
--            Bit 6 set also clears ERROR, when the commit takes effect
--            (use it on the first commit of a load).
--            Read:  bit 7 READY: room for another 512 bytes (and SSNAIL is not
--                   running a job, and any commit has been processed)
--                   bit 6 ERROR: data addressed outside both RAM regions
--                   (dropped); sticky until a commit with bit 6 set
--                   bits 0-3 pointer bits 24-27
--   $18      Data: each write stores one byte at the pointer and advances it.
--
-- The ring buffer is 1 KB of LUT RAM, indexed by destination address, so a
-- 512-byte sector fits even when it straddles three 256-byte blocks.  A
-- block is written to RAM as soon as the pointer moves past its end; a
-- partial block waits for more data or a commit.  Writes bypass the CPU's
-- caches, so each one is followed by an INVALIDATE on the same RAM port.
--
-- Instruction format: 16 bytes, 16-byte aligned, little-endian (ISA v1, see
-- ssnail_isa.py):  op, a, b, 0, X:u32, Y:u32, Z:u32.
-- Address operands (X/Y where an op takes an address): bit 31 clear =
-- absolute 28-bit address; bit 31 set = A[bits 27-24] + bits 23-0.
-- Registers: R0-R15 (32-bit, R15 reads 0, writes to it are ignored),
-- A0-A15 (28-bit addresses), N0-N2 (lengths, for the maths ops).
--   byte 0 = opcode
--   $00 NOP
--   $01 HALT                 job done
--   $02 SYNC                 INVALIDATE on every present LUMP port
--   $03 COPY                 bytes 4-7 source address (28 bits)
--                            bytes 8-11 destination address (28 bits)
--                            bytes 12-13 length in bytes
--                            Addresses 8-byte aligned, length a multiple of 8.
--                            Overlapping copies are undefined.
--   $07 SETN                 N0 = X, N1 = Y, N2 = Z
--   $08 LI                   R[a] = Z
--   $09 LDR                  R[a] = u32 at addr(X)   (4-byte aligned)
--   $0A STR                  u32 at addr(X) = R[a]   (4-byte aligned)
--   $0B ADDI                 R[a] = R[b] + Z (mod 2^32)
--   $0C LEA                  A[a] = addr(X) + R[b] * Z (mod 2^28)
--   $0D/$0E/$0F BEQ/BNE/BLT  if R[a] ==/!=/< R[b] (unsigned): PC = addr(X)
--   COPY's X and Y may be register-relative too.
--   anything else            illegal opcode fault
--
-- Clocking: hr_* ports are assumed to be on the same clock as clock162 (the
-- HyperRAM controller's clock163 net).  The register block and the core
-- communicate only via toggle handshakes and stable snapshots; the
-- multi-bit paths need set_max_delay / false path constraints.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;
use work.lumptypes.all;

entity ssnail is
  port (
    ---------------------------------------------------------------------------
    -- FastIO side (cpuclock domain)
    ---------------------------------------------------------------------------
    cpuclock     : in  std_logic;
    reset        : in  std_logic;       -- active low, as for other peripherals
    irq          : out std_logic := '1';  -- active low
    ssnail_cs    : in  std_logic;
    fastio_addr  : in  unsigned(19 downto 0);
    fastio_write : in  std_logic;
    fastio_read  : in  std_logic;
    fastio_wdata : in  unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0);

    ---------------------------------------------------------------------------
    -- Core side (clock162 domain)
    ---------------------------------------------------------------------------
    clock162 : in std_logic;

    -- LUMP master: HyperRAM
    hr_cmd_valid   : out std_logic := '0';
    hr_cmd_ready   : in  std_logic := '0';
    hr_cmd_op      : out unsigned(1 downto 0) := "00";
    hr_cmd_addr    : out unsigned(26 downto 0) := (others => '0');
    hr_cmd_len     : out unsigned(8 downto 0) := (others => '0');
    hr_rdata       : in  unsigned(15 downto 0) := x"0000";
    hr_rdata_valid : in  std_logic := '0';
    hr_wdata_req   : in  std_logic := '0';
    hr_wdata       : out unsigned(15 downto 0) := x"0000";
    hr_wdata_be    : out std_logic_vector(1 downto 0) := "11";
    hr_cmd_done    : in  std_logic := '0';
    hr_error       : in  std_logic := '0';

    -- LUMP master: SDRAM
    sd_cmd_valid   : out std_logic := '0';
    sd_cmd_ready   : in  std_logic := '0';
    sd_cmd_op      : out unsigned(1 downto 0) := "00";
    sd_cmd_addr    : out unsigned(26 downto 0) := (others => '0');
    sd_cmd_len     : out unsigned(8 downto 0) := (others => '0');
    sd_rdata       : in  unsigned(15 downto 0) := x"0000";
    sd_rdata_valid : in  std_logic := '0';
    sd_wdata_req   : in  std_logic := '0';
    sd_wdata       : out unsigned(15 downto 0) := x"0000";
    sd_wdata_be    : out std_logic_vector(1 downto 0) := "11";
    sd_cmd_done    : in  std_logic := '0';
    sd_error       : in  std_logic := '0'
    );
end ssnail;

architecture shell of ssnail is

  constant SSNAIL_ID      : unsigned(7 downto 0) := x"53";
  constant SSNAIL_VERSION : unsigned(7 downto 0) := x"01";

  constant ERR_NONE      : unsigned(7 downto 0) := x"00";
  constant ERR_OPCODE    : unsigned(7 downto 0) := x"01";
  constant ERR_ADDRESS   : unsigned(7 downto 0) := x"02";
  constant ERR_ALIGNMENT : unsigned(7 downto 0) := x"03";
  constant ERR_READ      : unsigned(7 downto 0) := x"04";
  constant ERR_ABORTED   : unsigned(7 downto 0) := x"05";

  ---------------------------------------------------------------------------
  -- cpuclock domain
  ---------------------------------------------------------------------------
  signal job_ptr      : unsigned(27 downto 0) := (others => '0');
  signal hr_size_mb   : unsigned(7 downto 0) := to_unsigned(8, 8);
  signal sd_base_mb   : unsigned(7 downto 0) := (others => '0');
  signal sd_size_mb   : unsigned(7 downto 0) := (others => '0');
  signal irq_en_done  : std_logic := '0';
  signal irq_pend_done : std_logic := '0';

  attribute ram_style : string;

  -- Load port, cpuclock side
  signal lp_ptr       : unsigned(27 downto 0) := (others => '0');  -- live pointer
  signal lp_stage     : unsigned(23 downto 0) := (others => '0');  -- staged bits 0-23
  signal lp_blk_tgl   : std_logic := '0';   -- flips when the pointer leaves a block
  signal lp_cmt_tgl   : std_logic := '0';   -- flips on commit
  signal lp_cmt_end   : unsigned(27 downto 0) := (others => '0');  -- flush up to here
  signal lp_cmt_new   : unsigned(27 downto 0) := (others => '0');  -- then continue here
  signal lp_out       : unsigned(2 downto 0) := (others => '0');   -- blocks not yet acked
  signal lp_cmt_pend  : std_logic := '0';
  signal lp_cmt_clr   : std_logic := '0';   -- this commit clears ERROR
  signal lp_ack_s1, lp_ack_s2, lp_ack_last : std_logic := '0';
  signal lp_cack_s1, lp_cack_s2 : std_logic := '0';
  signal lp_err_s1, lp_err_s2 : std_logic := '0';
  signal lp_ready     : std_logic := '0';
  type ring_t is array (0 to 511) of unsigned(7 downto 0);
  signal ring_lo, ring_hi : ring_t := (others => x"00");   -- even / odd addresses
  attribute ram_style of ring_lo, ring_hi : signal is "distributed";

  -- Command toggles (cpu -> core)
  signal go_tgl, abort_tgl, sync_tgl, step_tgl : std_logic := '0';
  -- GO/STEP written but not yet acknowledged by the core: report busy
  signal start_pending : std_logic := '0';
  signal start_tgl     : std_logic := '0';  -- flips on every GO or STEP

  -- Snapshot copied from the core
  signal pub_tgl_s1, pub_tgl_s2, pub_tgl_last : std_logic := '0';
  signal cpu_pc      : unsigned(27 downto 0) := (others => '0');
  signal cpu_busy    : std_logic := '0';
  signal cpu_done    : std_logic := '0';
  signal cpu_err     : unsigned(7 downto 0) := (others => '0');
  signal cpu_start_ack : std_logic := '0';
  signal cpu_done_tgl, cpu_done_tgl_last : std_logic := '0';

  ---------------------------------------------------------------------------
  -- clock162 domain
  ---------------------------------------------------------------------------
  -- Synchronisers for the command toggles
  signal go_s1, go_s2, go_last       : std_logic := '0';
  signal abort_s1, abort_s2, abort_last : std_logic := '0';
  signal sync_s1, sync_s2, sync_last : std_logic := '0';
  signal step_s1, step_s2, step_last : std_logic := '0';

  -- Configuration, captured from the cpu domain when a command arrives
  -- (it is only written while idle, so it is stable by then)
  signal c_hr_size, c_sd_base, c_sd_size : unsigned(7 downto 0) := (others => '0');

  type core_state_t is (
    C_IDLE,
    C_FETCH_SETUP, C_FETCH_DECODE, C_FETCH_ISSUE, C_FETCH_WAIT, C_RESOLVE, C_DECODE,
    C_LEA_MUL, C_MEM_DECODE, C_MEM_ISSUE, C_MEM_WAIT,
    C_COPY_CALC, C_COPY_RD_DECODE, C_COPY_RD_ISSUE, C_COPY_RD_WAIT,
    C_COPY_WR_DECODE, C_COPY_WR_ISSUE, C_COPY_WR_WAIT,
    C_SYNC_ISSUE, C_SYNC_WAIT,
    C_LP_DECODE, C_LP_ISSUE, C_LP_WAIT, C_LP_INVAL, C_LP_DONE,
    C_NEXT, C_END);
  signal cstate : core_state_t := C_IDLE;

  signal pc        : unsigned(27 downto 0) := (others => '0');
  signal instr     : unsigned(127 downto 0) := (others => '0');
  signal busy      : std_logic := '0';
  signal done      : std_logic := '0';
  signal err       : unsigned(7 downto 0) := (others => '0');
  signal stepping  : std_logic := '0';
  signal abort_req : std_logic := '0';
  signal start_ack : std_logic := '0';
  signal done_tgl  : std_logic := '0';

  -- Snapshot published to the cpu domain
  signal pub_tgl    : std_logic := '0';
  signal pub_pc     : unsigned(27 downto 0) := (others => '0');
  signal pub_busy   : std_logic := '0';
  signal pub_done   : std_logic := '0';
  signal pub_err    : unsigned(7 downto 0) := (others => '0');
  signal pub_start_ack : std_logic := '0';
  signal pub_done_tgl : std_logic := '0';
  signal pub_timer  : unsigned(5 downto 0) := (others => '0');

  -- Address decode results
  signal dec_addr   : unsigned(27 downto 0) := (others => '0');
  signal dec_local  : unsigned(26 downto 0) := (others => '0');
  signal dec_is_sd  : std_logic := '0';
  signal dec_ok     : std_logic := '0';

  -- Current transaction
  signal t_is_sd    : std_logic := '0';  -- which port
  signal words_expected : unsigned(7 downto 0) := (others => '0');
  signal words_got  : unsigned(7 downto 0) := (others => '0');
  -- Commands issued to each port and not yet completed (cmd_done)
  signal hr_out, sd_out : unsigned(2 downto 0) := (others => '0');
  -- Stand-alone SYNC CACHE requested from the CPU (not part of a job)
  signal cpu_sync : std_logic := '0';

  -- Register files and resolved operands
  type rfile32_t is array (0 to 15) of unsigned(31 downto 0);
  type rfile28_t is array (0 to 15) of unsigned(27 downto 0);
  signal rf_r : rfile32_t := (others => (others => '0'));
  signal rf_a : rfile28_t := (others => (others => '0'));
  signal n0, n1, n2 : unsigned(31 downto 0) := (others => '0');
  signal ea_x, ea_y : unsigned(27 downto 0) := (others => '0');
  signal opr_a, opr_b : unsigned(31 downto 0) := (others => '0');  -- R[a], R[b]
  signal br_taken  : std_logic := '0';
  -- LEA: iterative multiply R[b] * Z
  signal mul_acc   : unsigned(27 downto 0) := (others => '0');
  signal mul_m     : unsigned(27 downto 0) := (others => '0');
  signal mul_z     : unsigned(31 downto 0) := (others => '0');
  -- LDR / STR
  signal mem_is_store : std_logic := '0';
  signal str_active   : std_logic := '0';
  signal str_k        : unsigned(1 downto 0) := "00";

  -- COPY state
  signal cp_src, cp_dst : unsigned(27 downto 0) := (others => '0');
  signal cp_remaining   : unsigned(15 downto 0) := (others => '0');
  signal cp_chunk       : unsigned(8 downto 0) := (others => '0');

  -- Load port, core side
  signal lp_blk_s1, lp_blk_s2, lp_blk_last : std_logic := '0';
  signal lp_cmt_s1, lp_cmt_s2, lp_cmt_last : std_logic := '0';
  signal lp_pending   : unsigned(2 downto 0) := (others => '0');  -- complete blocks waiting
  signal lp_drain     : unsigned(27 downto 0) := (others => '0'); -- next address to write
  signal lp_end       : unsigned(27 downto 0) := (others => '0'); -- end of current chunk
  signal lp_is_commit : std_logic := '0';
  signal lp_ack_tgl, lp_cack_tgl : std_logic := '0';
  signal lp_error     : std_logic := '0';
  signal lp_active    : std_logic := '0';    -- write data comes from the ring
  signal lp_w         : unsigned(27 downto 0) := (others => '0'); -- next word address
  signal lp_lead      : unsigned(8 downto 0) := (others => '0');  -- offsets within the chunk
  signal lp_vend      : unsigned(8 downto 0) := (others => '0');
  signal lp_k         : unsigned(8 downto 0) := (others => '0');
  signal wbe_r        : std_logic_vector(1 downto 0) := "11";
  signal ring_rd_idx  : unsigned(8 downto 0) := (others => '0');
  signal ring_rd_lo, ring_rd_hi : unsigned(7 downto 0);

  -- Return path pipeline stage (the one-stage port mux)
  signal rvalid_r : std_logic := '0';
  signal rdata_r  : unsigned(15 downto 0) := x"0000";
  signal rerror_r : std_logic := '0';

  -- 256-byte burst buffer in LUT RAM
  type buf_t is array (0 to 127) of unsigned(15 downto 0);
  signal buf : buf_t := (others => x"0000");
  signal buf_widx : unsigned(6 downto 0) := (others => '0');  -- fill index
  signal buf_ridx : unsigned(6 downto 0) := (others => '0');  -- drain index
  signal wdata_r  : unsigned(15 downto 0) := x"0000";

  attribute ram_style of buf : signal is "distributed";

  attribute async_reg : string;
  attribute async_reg of go_s1, go_s2, abort_s1, abort_s2 : signal is "true";
  attribute async_reg of sync_s1, sync_s2, step_s1, step_s2 : signal is "true";
  attribute async_reg of pub_tgl_s1, pub_tgl_s2 : signal is "true";
  attribute async_reg of lp_blk_s1, lp_blk_s2, lp_cmt_s1, lp_cmt_s2 : signal is "true";
  attribute async_reg of lp_ack_s1, lp_ack_s2, lp_cack_s1, lp_cack_s2 : signal is "true";
  attribute async_reg of lp_err_s1, lp_err_s2 : signal is "true";

  function min9(a, b : unsigned(8 downto 0)) return unsigned is
  begin
    if a < b then return a; else return b; end if;
  end function;

begin

  ---------------------------------------------------------------------------
  -- FastIO register reads (asynchronous, as in buffereduart, to avoid wait
  -- states)
  ---------------------------------------------------------------------------
  process (fastio_read, ssnail_cs, fastio_addr, job_ptr, cpu_pc, cpu_busy,
           cpu_done, cpu_err, start_pending, irq_pend_done, irq_en_done,
           hr_size_mb, sd_base_mb, sd_size_mb, lp_ptr, lp_ready, lp_err_s2) is
  begin
    if fastio_read = '1' and ssnail_cs = '1' then
      case fastio_addr(4 downto 0) is
        when "00000" => fastio_rdata <= SSNAIL_ID;
        when "00001" => fastio_rdata <= SSNAIL_VERSION;
        when "00010" => fastio_rdata <= x"03";
        when "00011" =>
          fastio_rdata <= (others => '0');
          fastio_rdata(7) <= irq_pend_done;
        when "00100" =>
          fastio_rdata <= (others => '0');
          fastio_rdata(0) <= cpu_busy or start_pending;
          fastio_rdata(1) <= cpu_done and not start_pending;
          if cpu_err /= ERR_NONE and start_pending = '0' then
            fastio_rdata(2) <= '1';
          end if;
        when "00101" =>
          if start_pending = '1' then
            fastio_rdata <= ERR_NONE;
          else
            fastio_rdata <= cpu_err;
          end if;
        when "00110" =>
          fastio_rdata <= (others => '0');
          fastio_rdata(0) <= irq_en_done;
        when "01000" => fastio_rdata <= job_ptr(7 downto 0);
        when "01001" => fastio_rdata <= job_ptr(15 downto 8);
        when "01010" => fastio_rdata <= job_ptr(23 downto 16);
        when "01011" => fastio_rdata <= "0000" & job_ptr(27 downto 24);
        when "01100" => fastio_rdata <= cpu_pc(7 downto 0);
        when "01101" => fastio_rdata <= cpu_pc(15 downto 8);
        when "01110" => fastio_rdata <= cpu_pc(23 downto 16);
        when "01111" => fastio_rdata <= "0000" & cpu_pc(27 downto 24);
        when "10000" => fastio_rdata <= hr_size_mb;
        when "10001" => fastio_rdata <= sd_base_mb;
        when "10010" => fastio_rdata <= sd_size_mb;
        when "10100" => fastio_rdata <= lp_ptr(7 downto 0);
        when "10101" => fastio_rdata <= lp_ptr(15 downto 8);
        when "10110" => fastio_rdata <= lp_ptr(23 downto 16);
        when "10111" =>
          fastio_rdata <= lp_ready & lp_err_s2 & "00" & lp_ptr(27 downto 24);
        when others  => fastio_rdata <= x"FF";
      end case;
    else
      fastio_rdata <= (others => 'Z');
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- FastIO register writes and snapshot capture (cpuclock domain)
  ---------------------------------------------------------------------------
  process (cpuclock) is
    variable idle : boolean;
  begin
    if rising_edge(cpuclock) then
      idle := cpu_busy = '0' and start_pending = '0';

      -- Capture the core's published snapshot once its toggle has been
      -- synchronised.  The core holds the snapshot stable for 64 of its
      -- cycles after flipping the toggle, far longer than this takes.
      pub_tgl_s1 <= pub_tgl;
      pub_tgl_s2 <= pub_tgl_s1;
      if pub_tgl_s2 /= pub_tgl_last then
        pub_tgl_last  <= pub_tgl_s2;
        cpu_pc        <= pub_pc;
        cpu_busy      <= pub_busy;
        cpu_done      <= pub_done;
        cpu_err       <= pub_err;
        cpu_start_ack <= pub_start_ack;
        cpu_done_tgl  <= pub_done_tgl;
      end if;
      if start_pending = '1' and cpu_start_ack = start_tgl then
        start_pending <= '0';
      end if;
      if cpu_done_tgl /= cpu_done_tgl_last then
        cpu_done_tgl_last <= cpu_done_tgl;
        irq_pend_done <= '1';
      end if;

      if fastio_write = '1' and ssnail_cs = '1' then
        case fastio_addr(4 downto 0) is
          when "00011" =>
            if fastio_wdata(7) = '1' then
              irq_pend_done <= '0';
            end if;
            if fastio_wdata(0) = '1' and idle then
              go_tgl <= not go_tgl;
              start_tgl <= not start_tgl;
              start_pending <= '1';
            elsif fastio_wdata(3) = '1' and idle then
              step_tgl <= not step_tgl;
              start_tgl <= not start_tgl;
              start_pending <= '1';
            end if;
            if fastio_wdata(1) = '1' then
              abort_tgl <= not abort_tgl;
            end if;
            if fastio_wdata(2) = '1' and idle then
              sync_tgl <= not sync_tgl;
            end if;
          when "00110" => irq_en_done <= fastio_wdata(0);
          when "01000" => if idle then job_ptr(7 downto 0) <= fastio_wdata; end if;
          when "01001" => if idle then job_ptr(15 downto 8) <= fastio_wdata; end if;
          when "01010" => if idle then job_ptr(23 downto 16) <= fastio_wdata; end if;
          when "01011" => if idle then job_ptr(27 downto 24) <= fastio_wdata(3 downto 0); end if;
          when "10000" => if idle then hr_size_mb <= fastio_wdata; end if;
          when "10001" => if idle then sd_base_mb <= fastio_wdata; end if;
          when "10010" => if idle then sd_size_mb <= fastio_wdata; end if;
          when "10100" => lp_stage(7 downto 0) <= fastio_wdata;
          when "10101" => lp_stage(15 downto 8) <= fastio_wdata;
          when "10110" => lp_stage(23 downto 16) <= fastio_wdata;
          when "10111" =>
            -- Commit: flush what's pending to the old pointer, then move
            lp_cmt_end <= lp_ptr;
            lp_cmt_new <= fastio_wdata(3 downto 0) & lp_stage;
            lp_ptr <= fastio_wdata(3 downto 0) & lp_stage;
            lp_cmt_clr <= fastio_wdata(6);
            lp_cmt_tgl <= not lp_cmt_tgl;
            lp_cmt_pend <= '1';
          when "11000" =>
            -- Data byte into the ring, at its destination address
            if lp_ptr(0) = '0' then
              ring_lo(to_integer(lp_ptr(9 downto 1))) <= fastio_wdata;
            else
              ring_hi(to_integer(lp_ptr(9 downto 1))) <= fastio_wdata;
            end if;
            lp_ptr <= lp_ptr + 1;
            if lp_ptr(7 downto 0) = x"FF" then
              -- This byte completes a 256-byte block: hand it to the core
              lp_blk_tgl <= not lp_blk_tgl;
              lp_out <= lp_out + 1;
            end if;
          when others => null;
        end case;
      end if;

      -- Load port acknowledgements from the core
      lp_ack_s1 <= lp_ack_tgl;  lp_ack_s2 <= lp_ack_s1;
      lp_cack_s1 <= lp_cack_tgl; lp_cack_s2 <= lp_cack_s1;
      lp_err_s1 <= lp_error;    lp_err_s2 <= lp_err_s1;
      if lp_ack_s2 /= lp_ack_last then
        lp_ack_last <= lp_ack_s2;
        if not (fastio_write = '1' and ssnail_cs = '1' and fastio_addr(4 downto 0) = "11000"
                and lp_ptr(7 downto 0) = x"FF") then
          lp_out <= lp_out - 1;
        else
          lp_out <= lp_out;           -- a block completed in the same cycle
        end if;
      end if;
      if lp_cack_s2 = lp_cmt_tgl then
        if not (fastio_write = '1' and ssnail_cs = '1' and fastio_addr(4 downto 0) = "10111") then
          lp_cmt_pend <= '0';
        end if;
      end if;
      -- READY: every complete block written, no commit outstanding, no job
      if lp_out = 0 and lp_cmt_pend = '0' and cpu_busy = '0' and start_pending = '0' then
        lp_ready <= '1';
      else
        lp_ready <= '0';
      end if;

      if reset = '0' then
        irq_pend_done <= '0';
        irq_en_done <= '0';
      end if;
    end if;
  end process;

  irq <= '0' when irq_pend_done = '1' and irq_en_done = '1' else '1';

  ---------------------------------------------------------------------------
  -- Core (clock162 domain)
  ---------------------------------------------------------------------------
  process (clock162) is
    variable mb : unsigned(7 downto 0);
    variable room_s, room_d, rem9 : unsigned(8 downto 0);
    variable hr_issue, sd_issue : std_logic;
    variable lp_inc, lp_dec : std_logic;
    variable st_al, en_al : unsigned(27 downto 0);
  begin
    if rising_edge(clock162) then
      hr_issue := '0';
      sd_issue := '0';
      lp_inc := '0';
      lp_dec := '0';

      -- Command toggle synchronisers
      go_s1 <= go_tgl;       go_s2 <= go_s1;
      abort_s1 <= abort_tgl; abort_s2 <= abort_s1;
      sync_s1 <= sync_tgl;   sync_s2 <= sync_s1;
      step_s1 <= step_tgl;   step_s2 <= step_s1;

      -- Return path: one register stage that also acts as the port mux.
      -- Only one port ever has reads outstanding, so OR-ing is safe.
      rvalid_r <= hr_rdata_valid or sd_rdata_valid;
      if sd_rdata_valid = '1' then
        rdata_r <= sd_rdata;
      else
        rdata_r <= hr_rdata;
      end if;
      rerror_r <= hr_error or sd_error;

      -- Write data supply, per the LUMP contract: register the next word
      -- on the first edge that sees a request.
      if (hr_wdata_req or sd_wdata_req) = '1' then
        if str_active = '1' then
          -- STR: an 8-byte burst; the register goes in words 0-1 or 2-3
          if str_k(0) = '0' then
            wdata_r <= opr_a(15 downto 0);
          else
            wdata_r <= opr_a(31 downto 16);
          end if;
          if str_k(1) = ea_x(2) then
            wbe_r <= "11";
          else
            wbe_r <= "00";
          end if;
          str_k <= str_k + 1;
        elsif lp_active = '1' then
          -- Word at lp_w: bytes at offsets 2k and 2k+1 into the chunk,
          -- enabled only between the chunk's real start and end.
          wdata_r <= ring_rd_hi & ring_rd_lo;
          if lp_k & '0' >= lp_lead and lp_k & '0' < lp_vend then
            wbe_r(0) <= '1';
          else
            wbe_r(0) <= '0';
          end if;
          if lp_k & '1' >= lp_lead and lp_k & '1' < lp_vend then
            wbe_r(1) <= '1';
          else
            wbe_r(1) <= '0';
          end if;
          lp_k <= lp_k + 1;
          ring_rd_idx <= ring_rd_idx + 1;
        else
          wdata_r  <= buf(to_integer(buf_ridx));
          wbe_r    <= "11";
          buf_ridx <= buf_ridx + 1;
        end if;
      end if;

      -- Load port toggles from the cpuclock side
      lp_blk_s1 <= lp_blk_tgl; lp_blk_s2 <= lp_blk_s1;
      lp_cmt_s1 <= lp_cmt_tgl; lp_cmt_s2 <= lp_cmt_s1;
      if lp_blk_s2 /= lp_blk_last then
        lp_blk_last <= lp_blk_s2;
        lp_inc := '1';
      end if;

      -- Address decode of dec_addr, one cycle after it is set.
      -- HyperRAM: [$8000000, $8000000 + hr_size MB)
      -- SDRAM:    [sd_base MB, sd_base + sd_size MB)
      mb := dec_addr(27 downto 20);
      if mb >= x"80" and resize(mb, 9) < to_unsigned(128, 9) + resize(c_hr_size, 9) then
        dec_ok    <= '1';
        dec_is_sd <= '0';
        dec_local <= dec_addr(26 downto 0);
      elsif mb >= c_sd_base and resize(mb, 9) < resize(c_sd_base, 9) + resize(c_sd_size, 9) then
        dec_ok    <= '1';
        dec_is_sd <= '1';
        dec_local <= resize(mb - c_sd_base, 7) & dec_addr(19 downto 0);
      else
        dec_ok    <= '0';
      end if;

      -- Publish a consistent snapshot to the cpu domain every 64 cycles
      pub_timer <= pub_timer + 1;
      if pub_timer = 0 then
        pub_pc        <= pc;
        pub_busy      <= busy;
        pub_done      <= done;
        pub_err       <= err;
        pub_start_ack <= start_ack;
        pub_done_tgl  <= done_tgl;
      elsif pub_timer = 1 then
        pub_tgl <= not pub_tgl;
      end if;

      -- ABORT is honoured between RAM transactions
      if abort_s2 /= abort_last then
        abort_last <= abort_s2;
        if busy = '1' then
          abort_req <= '1';
        end if;
      end if;

      -- Store incoming read data
      if rvalid_r = '1' then
        if cstate = C_FETCH_WAIT then
          instr <= rdata_r & instr(127 downto 16);
        else
          buf(to_integer(buf_widx)) <= rdata_r;
          buf_widx <= buf_widx + 1;
        end if;
        words_got <= words_got + 1;
      end if;
      if rerror_r = '1' and busy = '1' then
        err <= ERR_READ;
      end if;

      -- Command acceptance: drop valid on the edge where ready is seen
      if hr_cmd_ready = '1' then hr_cmd_valid <= '0'; end if;
      if sd_cmd_ready = '1' then sd_cmd_valid <= '0'; end if;

      case cstate is
        when C_IDLE =>
          busy <= '0';
          -- Load port work comes first.  A chunk is [lp_drain, lp_end): a
          -- whole remaining block, or for a commit, whatever is left.
          if lp_pending /= 0
            or (lp_cmt_s2 /= lp_cmt_last and lp_blk_s2 = lp_blk_last) then
            if lp_pending /= 0 then
              lp_end <= (lp_drain(27 downto 8) + 1) & x"00";
              en_al := (lp_drain(27 downto 8) + 1) & x"00";
              lp_is_commit <= '0';
            else
              lp_end <= lp_cmt_end;
              en_al := lp_cmt_end;
              lp_is_commit <= '1';
              if lp_cmt_clr = '1' and lp_drain = lp_cmt_end then
                lp_error <= '0';
              end if;
            end if;
            if lp_pending = 0 and lp_drain = lp_cmt_end then
              -- Nothing (more) to flush: the commit takes effect
              lp_drain <= lp_cmt_new;
              lp_cmt_last <= lp_cmt_s2;
              lp_cack_tgl <= lp_cmt_s2;
            else
              st_al := lp_drain(27 downto 3) & "000";
              en_al := en_al + 7;
              en_al(2 downto 0) := "000";
              lp_lead <= resize(lp_drain(2 downto 0), 9);
              lp_vend <= resize(en_al - st_al, 9);   -- adjusted below
              if lp_pending /= 0 then
                lp_vend <= resize(((lp_drain(27 downto 8) + 1) & x"00") - st_al, 9);
              else
                lp_vend <= resize(lp_cmt_end - st_al, 9);
              end if;
              lp_w <= st_al;
              cp_chunk <= resize(en_al - st_al, 9);
              ring_rd_idx <= st_al(9 downto 1);
              lp_k <= (others => '0');
              dec_addr <= st_al;
              c_hr_size <= hr_size_mb;
              c_sd_base <= sd_base_mb;
              c_sd_size <= sd_size_mb;
              cstate <= C_LP_DECODE;
            end if;
          elsif go_s2 /= go_last or step_s2 /= step_last then
            c_hr_size <= hr_size_mb;
            c_sd_base <= sd_base_mb;
            c_sd_size <= sd_size_mb;
            if go_s2 /= go_last then
              pc <= job_ptr;
              stepping <= '0';
            else
              stepping <= '1';
            end if;
            go_last <= go_s2;
            step_last <= step_s2;
            start_ack <= not start_ack;
            busy <= '1';
            done <= '0';
            err <= ERR_NONE;
            abort_req <= '0';
            cstate <= C_FETCH_SETUP;
          elsif sync_s2 /= sync_last then
            sync_last <= sync_s2;
            c_hr_size <= hr_size_mb;
            c_sd_size <= sd_size_mb;
            busy <= '1';
            cpu_sync <= '1';
            cstate <= C_SYNC_ISSUE;
          end if;

        when C_FETCH_SETUP =>
          dec_addr <= pc;
          cstate <= C_FETCH_DECODE;

        when C_FETCH_DECODE =>
          cstate <= C_FETCH_ISSUE;     -- decode of pc completes now

        when C_FETCH_ISSUE =>
          if abort_req = '1' then
            err <= ERR_ABORTED;
            cstate <= C_END;
          elsif pc(3 downto 0) /= "0000" then
            err <= ERR_ALIGNMENT;
            cstate <= C_END;
          elsif dec_ok = '0' then
            err <= ERR_ADDRESS;
            cstate <= C_END;
          else
            words_got <= (others => '0');
            words_expected <= to_unsigned(8, 8);
            t_is_sd <= dec_is_sd;
            if dec_is_sd = '1' then
              sd_cmd_valid <= '1'; sd_cmd_op <= LUMP_OP_READ;
              sd_cmd_addr <= dec_local; sd_cmd_len <= to_unsigned(16, 9);
              sd_issue := '1';
            else
              hr_cmd_valid <= '1'; hr_cmd_op <= LUMP_OP_READ;
              hr_cmd_addr <= dec_local; hr_cmd_len <= to_unsigned(16, 9);
              hr_issue := '1';
            end if;
            cstate <= C_FETCH_WAIT;
          end if;

        when C_FETCH_WAIT =>
          if words_got = words_expected and rvalid_r = '0' then
            cstate <= C_RESOLVE;
          end if;

        when C_RESOLVE =>
          -- Effective addresses for X and Y, and the register operands
          if instr(63) = '1' then
            ea_x <= rf_a(to_integer(instr(59 downto 56))) + resize(instr(55 downto 32), 28);
          else
            ea_x <= instr(59 downto 32);
          end if;
          if instr(95) = '1' then
            ea_y <= rf_a(to_integer(instr(91 downto 88))) + resize(instr(87 downto 64), 28);
          else
            ea_y <= instr(91 downto 64);
          end if;
          if instr(11 downto 8) = x"F" then
            opr_a <= (others => '0');
          else
            opr_a <= rf_r(to_integer(instr(11 downto 8)));
          end if;
          if instr(19 downto 16) = x"F" then
            opr_b <= (others => '0');
          else
            opr_b <= rf_r(to_integer(instr(19 downto 16)));
          end if;
          cstate <= C_DECODE;

        when C_DECODE =>
          if err /= ERR_NONE then
            cstate <= C_END;
          else
          case instr(7 downto 0) is
            when x"00" =>             -- NOP
              cstate <= C_NEXT;
            when x"01" =>             -- HALT
              cstate <= C_END;
            when x"02" =>             -- SYNC
              cstate <= C_SYNC_ISSUE;
            when x"03" =>             -- COPY
              cp_src <= ea_x;
              cp_dst <= ea_y;
              cp_remaining <= instr(111 downto 96);
              if ea_x(2 downto 0) /= "000" or ea_y(2 downto 0) /= "000"
                or instr(98 downto 96) /= "000" then
                err <= ERR_ALIGNMENT;
                cstate <= C_END;
              else
                cstate <= C_COPY_CALC;
              end if;
            when x"07" =>             -- SETN
              n0 <= instr(63 downto 32);
              n1 <= instr(95 downto 64);
              n2 <= instr(127 downto 96);
              cstate <= C_NEXT;
            when x"08" =>             -- LI
              if instr(11 downto 8) /= x"F" then
                rf_r(to_integer(instr(11 downto 8))) <= instr(127 downto 96);
              end if;
              cstate <= C_NEXT;
            when x"0B" =>             -- ADDI
              if instr(11 downto 8) /= x"F" then
                rf_r(to_integer(instr(11 downto 8))) <= opr_b + instr(127 downto 96);
              end if;
              cstate <= C_NEXT;
            when x"0C" =>             -- LEA: A[a] = addr(X) + R[b] * Z
              mul_acc <= ea_x;
              mul_m <= opr_b(27 downto 0);
              mul_z <= instr(127 downto 96);
              cstate <= C_LEA_MUL;
            when x"0D" | x"0E" | x"0F" =>   -- BEQ / BNE / BLT
              if (instr(7 downto 0) = x"0D" and opr_a = opr_b)
                or (instr(7 downto 0) = x"0E" and opr_a /= opr_b)
                or (instr(7 downto 0) = x"0F" and opr_a < opr_b) then
                br_taken <= '1';
              end if;
              cstate <= C_NEXT;
            when x"09" | x"0A" =>     -- LDR / STR
              if ea_x(1 downto 0) /= "00" then
                err <= ERR_ALIGNMENT;
                cstate <= C_END;
              else
                if instr(7 downto 0) = x"0A" then
                  mem_is_store <= '1';
                else
                  mem_is_store <= '0';
                end if;
                dec_addr <= ea_x(27 downto 3) & "000";
                cstate <= C_MEM_DECODE;
              end if;
            when others =>
              err <= ERR_OPCODE;
              cstate <= C_END;
          end case;
          end if;

        when C_LEA_MUL =>
          -- Shift-and-add, one bit of Z per cycle (LEA is rare)
          if mul_z = 0 then
            rf_a(to_integer(instr(11 downto 8))) <= mul_acc;
            cstate <= C_NEXT;
          else
            if mul_z(0) = '1' then
              mul_acc <= mul_acc + mul_m;
            end if;
            mul_m <= mul_m(26 downto 0) & '0';
            mul_z <= '0' & mul_z(31 downto 1);
          end if;

        when C_MEM_DECODE =>
          cstate <= C_MEM_ISSUE;        -- decode of the 8-byte group

        when C_MEM_ISSUE =>
          if dec_ok = '0' then
            err <= ERR_ADDRESS;
            cstate <= C_END;
          else
            t_is_sd <= dec_is_sd;
            words_got <= (others => '0');
            words_expected <= to_unsigned(4, 8);
            buf_widx <= (others => '0');
            if mem_is_store = '1' then
              str_active <= '1';
              str_k <= "00";
            end if;
            if dec_is_sd = '1' then
              sd_cmd_valid <= '1'; sd_cmd_addr <= dec_local; sd_cmd_len <= to_unsigned(8, 9);
              if mem_is_store = '1' then sd_cmd_op <= LUMP_OP_WRITE; else sd_cmd_op <= LUMP_OP_READ; end if;
              sd_issue := '1';
            else
              hr_cmd_valid <= '1'; hr_cmd_addr <= dec_local; hr_cmd_len <= to_unsigned(8, 9);
              if mem_is_store = '1' then hr_cmd_op <= LUMP_OP_WRITE; else hr_cmd_op <= LUMP_OP_READ; end if;
              hr_issue := '1';
            end if;
            cstate <= C_MEM_WAIT;
          end if;

        when C_MEM_WAIT =>
          if mem_is_store = '1' then
            if hr_out = 0 and sd_out = 0 and hr_issue = '0' then
              str_active <= '0';
              cstate <= C_NEXT;
            end if;
          elsif words_got = words_expected and rvalid_r = '0' then
            if instr(11 downto 8) /= x"F" then
              if ea_x(2) = '0' then
                rf_r(to_integer(instr(11 downto 8))) <= buf(1) & buf(0);
              else
                rf_r(to_integer(instr(11 downto 8))) <= buf(3) & buf(2);
              end if;
            end if;
            cstate <= C_NEXT;
          end if;

        when C_COPY_CALC =>
          -- Largest chunk that crosses neither a 256-byte boundary at the
          -- source or destination, nor the end of the copy.
          if abort_req = '1' then
            err <= ERR_ABORTED;
            cstate <= C_END;
          elsif err /= ERR_NONE then
            cstate <= C_END;
          elsif cp_remaining = 0 then
            cstate <= C_NEXT;
          else
            room_s := to_unsigned(256, 9) - resize(cp_src(7 downto 0), 9);
            room_d := to_unsigned(256, 9) - resize(cp_dst(7 downto 0), 9);
            if cp_remaining > 256 then
              rem9 := to_unsigned(256, 9);
            else
              rem9 := cp_remaining(8 downto 0);
            end if;
            cp_chunk <= min9(rem9, min9(room_s, room_d));
            dec_addr <= cp_src;
            cstate <= C_COPY_RD_DECODE;
          end if;

        when C_COPY_RD_DECODE =>
          cstate <= C_COPY_RD_ISSUE;   -- decode of cp_src completes now

        when C_COPY_RD_ISSUE =>
          if dec_ok = '0' then
            err <= ERR_ADDRESS;
            cstate <= C_END;
          else
            words_got <= (others => '0');
            words_expected <= resize(cp_chunk(8 downto 1), 8);
            buf_widx <= (others => '0');
            t_is_sd <= dec_is_sd;
            if dec_is_sd = '1' then
              sd_cmd_valid <= '1'; sd_cmd_op <= LUMP_OP_READ;
              sd_cmd_addr <= dec_local; sd_cmd_len <= cp_chunk;
              sd_issue := '1';
            else
              hr_cmd_valid <= '1'; hr_cmd_op <= LUMP_OP_READ;
              hr_cmd_addr <= dec_local; hr_cmd_len <= cp_chunk;
              hr_issue := '1';
            end if;
            cstate <= C_COPY_RD_WAIT;
          end if;

        when C_COPY_RD_WAIT =>
          -- Note: cp_chunk = 256 gives words_expected = 128, which fits.
          if words_got = words_expected and rvalid_r = '0' then
            dec_addr <= cp_dst;
            cstate <= C_COPY_WR_DECODE;
          end if;

        when C_COPY_WR_DECODE =>
          cstate <= C_COPY_WR_ISSUE;

        when C_COPY_WR_ISSUE =>
          if dec_ok = '0' then
            err <= ERR_ADDRESS;
            cstate <= C_END;
          else
            buf_ridx <= (others => '0');
            t_is_sd <= dec_is_sd;
            if dec_is_sd = '1' then
              sd_cmd_valid <= '1'; sd_cmd_op <= LUMP_OP_WRITE;
              sd_cmd_addr <= dec_local; sd_cmd_len <= cp_chunk;
              sd_issue := '1';
            else
              hr_cmd_valid <= '1'; hr_cmd_op <= LUMP_OP_WRITE;
              hr_cmd_addr <= dec_local; hr_cmd_len <= cp_chunk;
              hr_issue := '1';
            end if;
            cstate <= C_COPY_WR_WAIT;
          end if;

        when C_COPY_WR_WAIT =>
          -- Wait until everything issued (including the write) has
          -- completed, so the buffer can be reused.  Counting completions,
          -- rather than watching for one cmd_done pulse, makes this immune
          -- to the late cmd_done of the preceding read.
          if hr_out = 0 and sd_out = 0 and hr_issue = '0' then
            cp_src <= cp_src + resize(cp_chunk, 28);
            cp_dst <= cp_dst + resize(cp_chunk, 28);
            cp_remaining <= cp_remaining - resize(cp_chunk, 16);
            cstate <= C_COPY_CALC;
          end if;

        when C_SYNC_ISSUE =>
          if c_hr_size /= 0 then
            hr_cmd_valid <= '1'; hr_cmd_op <= LUMP_OP_INVALIDATE;
            hr_cmd_addr <= (others => '0'); hr_cmd_len <= (others => '0');
            hr_issue := '1';
          end if;
          if c_sd_size /= 0 then
            sd_cmd_valid <= '1'; sd_cmd_op <= LUMP_OP_INVALIDATE;
            sd_cmd_addr <= (others => '0'); sd_cmd_len <= (others => '0');
            sd_issue := '1';
          end if;
          cstate <= C_SYNC_WAIT;

        when C_SYNC_WAIT =>
          -- All earlier commands (e.g. COPY writes) complete before the
          -- invalidates, because each port's queue is in order.
          if hr_out = 0 and sd_out = 0 then
            if cpu_sync = '1' then
              cpu_sync <= '0';
              cstate <= C_IDLE;
            else
              cstate <= C_NEXT;
            end if;
          end if;

        when C_LP_DECODE =>
          cstate <= C_LP_ISSUE;          -- decode of the chunk address now

        when C_LP_ISSUE =>
          if dec_ok = '0' then
            lp_error <= '1';             -- outside both regions: drop it
            cstate <= C_LP_DONE;
          else
            lp_active <= '1';
            t_is_sd <= dec_is_sd;
            if dec_is_sd = '1' then
              sd_cmd_valid <= '1'; sd_cmd_op <= LUMP_OP_WRITE;
              sd_cmd_addr <= dec_local; sd_cmd_len <= cp_chunk;
              sd_issue := '1';
            else
              hr_cmd_valid <= '1'; hr_cmd_op <= LUMP_OP_WRITE;
              hr_cmd_addr <= dec_local; hr_cmd_len <= cp_chunk;
              hr_issue := '1';
            end if;
            cstate <= C_LP_WAIT;
          end if;

        when C_LP_WAIT =>
          if hr_out = 0 and sd_out = 0 and hr_issue = '0' then
            lp_active <= '0';
            -- The write bypassed the CPU's caches on that port
            if t_is_sd = '1' then
              sd_cmd_valid <= '1'; sd_cmd_op <= LUMP_OP_INVALIDATE;
              sd_cmd_addr <= (others => '0'); sd_cmd_len <= (others => '0');
              sd_issue := '1';
            else
              hr_cmd_valid <= '1'; hr_cmd_op <= LUMP_OP_INVALIDATE;
              hr_cmd_addr <= (others => '0'); hr_cmd_len <= (others => '0');
              hr_issue := '1';
            end if;
            cstate <= C_LP_INVAL;
          end if;

        when C_LP_INVAL =>
          if hr_out = 0 and sd_out = 0 then
            cstate <= C_LP_DONE;
          end if;

        when C_LP_DONE =>
          lp_drain <= lp_end;
          if lp_is_commit = '0' then
            lp_dec := '1';
            lp_ack_tgl <= not lp_ack_tgl;
          end if;
          cstate <= C_IDLE;

        when C_NEXT =>
          if br_taken = '1' then
            pc <= ea_x;
            br_taken <= '0';
          else
            pc <= pc + 16;
          end if;
          if stepping = '1' then
            -- Single step: stop with PC at the next instruction
            done <= '1';
            done_tgl <= not done_tgl;
            cstate <= C_IDLE;
          else
            cstate <= C_FETCH_SETUP;
          end if;

        when C_END =>
          -- Job finished (HALT, fault or abort).  PC stays on the
          -- instruction concerned.
          done <= '1';
          done_tgl <= not done_tgl;
          cstate <= C_IDLE;
      end case;

      -- Complete blocks waiting to be written
      if lp_inc = '1' and lp_dec = '0' then
        lp_pending <= lp_pending + 1;
      elsif lp_inc = '0' and lp_dec = '1' then
        lp_pending <= lp_pending - 1;
      end if;

      -- Outstanding command counters
      if hr_issue = '1' and hr_cmd_done = '0' then
        hr_out <= hr_out + 1;
      elsif hr_issue = '0' and hr_cmd_done = '1' and hr_out /= 0 then
        hr_out <= hr_out - 1;
      end if;
      if sd_issue = '1' and sd_cmd_done = '0' then
        sd_out <= sd_out + 1;
      elsif sd_issue = '0' and sd_cmd_done = '1' and sd_out /= 0 then
        sd_out <= sd_out - 1;
      end if;

    end if;
  end process;

  hr_wdata    <= wdata_r;
  sd_wdata    <= wdata_r;
  hr_wdata_be <= wbe_r;
  sd_wdata_be <= wbe_r;

  -- Ring read port (asynchronous LUT RAM read, registered in the core).  The
  -- cpuclock side only writes blocks the core is not reading.
  ring_rd_lo <= ring_lo(to_integer(ring_rd_idx));
  ring_rd_hi <= ring_hi(to_integer(ring_rd_idx));

end shell;
