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
--   $02      Capabilities: bit0 HyperRAM port, bit1 SDRAM present
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
--            5 aborted, 6 unsupported format
--   $06      IRQ enable: bit0 IRQ on job done
--   $08-$0B  Job pointer (28 bits).  Writable only while idle.
--   $0C-$0F  PC readback (28 bits)
--   $10      HyperRAM size in MB. Reset: 8
--   $11      SDRAM base in MB (address bits 27-20). Reset: $80 with SDRAM, else 0
--   $12      SDRAM size in MB. Reset: 64 with SDRAM, else 0
--   $13      HyperRAM base in MB. Reset: $C0 with SDRAM, else $80
--            (the region registers return to these on reset, when idle)
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
--   $11 DEQROW               Z (N0 x F32) = dequantise N0 elements of format a
--                            (0 F32, 1 F16, 2 Q4_0, 8 Q8_0, 30 BF16, 39 MXFP4,
--                            10-14 Q2_K..Q6_K: N0 a multiple of 256) at addr(X)
--   $10 GEMV                 Z (N1 rows) = W at addr(X) (N1 x N0, format a:
--                            Q8_0, Q4_0, MXFP4, Q2_K..Q6_K (N0 a multiple
--                            of 256) so far) . x at addr(Y)
--                            (N0 x F32).
--                            x is quantised to Q8_0 first, as llama.cpp.
--                            b bit 0: add to the existing Z (F32);
--                            b bit 1: write Z as F16.  N0 a multiple of 32,
--                            at most 4096.
--   $20 VADD / $21 VMUL      Z = X + Y / X * Y   (N0 x F32)
--   $22 RMSNORM              Z = X * rsqrt(mean(X^2) + eps) * Y   (eps = N2 bits)
--   $23 SILUMUL              Z = silu(X) * Y      (silu from a table)
--   $26 LAYERNORM            Z = (X - mean) * rsqrt(var + eps) * G + B; G at
--                            addr(Y), B just after it (addr(Y) + 4 N0)
--   $27 GELU                 Z = gelu(X)          (table)
--   $28 MEANROWS             Z = mean of R[a] rows of N0 F32 at addr(X)
--   $24 ROPE                 rotate pairs of the N0 F32 at addr(X) in place,
--                            using N1 (head dim) cos/sin values at addr(Y);
--                            X 8-byte aligned, N0 and N1 even, N1 <= 256
--   $12 ARGMAX               R[a] = index of the first maximum of N0 F32 at addr(X)
--   $25 ATTN                 attention of q at addr(Y) over K/V rows 0..R[a];
--                            result at addr(Z); addr(X) = parameter block
--                            (K cache, V cache, heads, KV heads, head dim,
--                            KV format 0 F32 / 1 F16); <= 1024 positions,
--                            head dim <= 256
--   (arithmetic order exactly as ssnail_hw.py in the SSNAIL tools)
--   $29 CVT16                Z (N0 x F16) = X (N0 x F32)
--   F32 operands are 4-byte aligned, F16 2-byte; arithmetic is IEEE, round
--   to nearest even, bit-exact with the emulator's hardware numerics.
--   COPY's X and Y may be register-relative too.
--   anything else            illegal opcode fault
--
-- Clocking: hr_* ports are assumed to be on the same clock as clock162 (the
-- HyperRAM controller's clock163 net).  The register block and the core
-- communicate only via toggle handshakes and stable snapshots; the
-- multi-bit paths need set_max_delay / false path constraints.

-- ---------------------------------------------------------------------------
-- SSNAIL burst-output scratchpad.
-- Four 32 x 16-bit LUTRAM banks, interleaved by word address modulo four.
-- A write packet contains 1, 2 or 4 consecutive words. Because they are
-- consecutive, at most one word reaches each bank on any clock edge.
-- The reader is asynchronous, so the existing LUMP request -> wdata_r
-- timing is unchanged. The banks are write-first only after a clock edge;
-- same-edge read/write follows the original signal-array semantics.
-- Data bits are deliberately opaque: future quantized/packed formats can
-- use the same scratchpad once the upstream packer constructs 16-bit words.
-- ---------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ssnail_output_buffer is
  port (
    clk       : in  std_logic;
    wr_en     : in  std_logic;
    wr_base   : in  unsigned(6 downto 0);
    wr_mask   : in  std_logic_vector(3 downto 0); -- word 0..3 enabled
    wr_data   : in  unsigned(63 downto 0);        -- low word at wr_base
    rd_addr   : in  unsigned(6 downto 0);
    rd_data   : out unsigned(15 downto 0)
  );
end ssnail_output_buffer;

architecture banked of ssnail_output_buffer is
  type bank_t is array (0 to 31) of unsigned(15 downto 0);
  signal bank0, bank1, bank2, bank3 : bank_t := (others => (others => '0'));
  attribute ram_style : string;
  attribute ram_style of bank0, bank1, bank2, bank3 : signal is "distributed";
begin
  -- Four independent asynchronous read ports, one per physical bank;
  -- the final 4:1 mux selects the requested word. This is only *one*
  -- logical read port and uses no extra cycle on the existing LUMP path.
  with rd_addr(1 downto 0) select rd_data <=
    bank0(to_integer(rd_addr(6 downto 2))) when "00",
    bank1(to_integer(rd_addr(6 downto 2))) when "01",
    bank2(to_integer(rd_addr(6 downto 2))) when "10",
    bank3(to_integer(rd_addr(6 downto 2))) when others;

  process(clk) is
    variable lane : unsigned(1 downto 0);
    variable addr : unsigned(6 downto 0);
  begin
    if rising_edge(clk) then
      -- Each assignment below is the sole write port for that bank.
      -- lane = (bank_number - wr_base[1:0]) modulo 4; arithmetic on
      -- the seven-bit address wraps exactly as the old buf indexing did.
      lane := to_unsigned(0, 2) - wr_base(1 downto 0);
      addr := wr_base + resize(lane, 7);
      if wr_en = '1' and wr_mask(to_integer(lane)) = '1' then
        bank0(to_integer(addr(6 downto 2))) <=
          wr_data(16 * to_integer(lane) + 15 downto 16 * to_integer(lane));
      end if;

      lane := to_unsigned(1, 2) - wr_base(1 downto 0);
      addr := wr_base + resize(lane, 7);
      if wr_en = '1' and wr_mask(to_integer(lane)) = '1' then
        bank1(to_integer(addr(6 downto 2))) <=
          wr_data(16 * to_integer(lane) + 15 downto 16 * to_integer(lane));
      end if;

      lane := to_unsigned(2, 2) - wr_base(1 downto 0);
      addr := wr_base + resize(lane, 7);
      if wr_en = '1' and wr_mask(to_integer(lane)) = '1' then
        bank2(to_integer(addr(6 downto 2))) <=
          wr_data(16 * to_integer(lane) + 15 downto 16 * to_integer(lane));
      end if;

      lane := to_unsigned(3, 2) - wr_base(1 downto 0);
      addr := wr_base + resize(lane, 7);
      if wr_en = '1' and wr_mask(to_integer(lane)) = '1' then
        bank3(to_integer(addr(6 downto 2))) <=
          wr_data(16 * to_integer(lane) + 15 downto 16 * to_integer(lane));
      end if;
    end if;
  end process;
end banked;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;
use work.lumptypes.all;
use work.ssnail_fpu_pkg.all;
use work.ssnail_tables_pkg.all;

entity ssnail is
  generic (
    -- Board has SDRAM (R4-R6).  SSNAIL's map then defaults to SDRAM first:
    -- SDRAM $8000000-$BFFFFFF, HyperRAM $C000000-$C7FFFFF.  Without SDRAM:
    -- HyperRAM $8000000-$87FFFFF.  Either way a <= 8 MB image is at
    -- $8000000, so the same image works on every board.
    has_sdram : boolean := false
    );
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
  constant ERR_FORMAT    : unsigned(7 downto 0) := x"06";   -- format not supported (yet)

  -- Vector engine element operations
  constant K_ADD     : unsigned(3 downto 0) := x"0";   -- z = x + y
  constant K_MUL     : unsigned(3 downto 0) := x"1";   -- z = x * y
  constant K_CVT16   : unsigned(3 downto 0) := x"2";   -- z = f16(x)
  constant K_COPY    : unsigned(3 downto 0) := x"3";   -- z = x
  constant K_SCALE   : unsigned(3 downto 0) := x"4";   -- z = x * s_sc
  constant K_SUMSQ   : unsigned(3 downto 0) := x"5";   -- acc += x * x
  constant K_SUM     : unsigned(3 downto 0) := x"6";   -- acc += x
  constant K_LNVAR   : unsigned(3 downto 0) := x"7";   -- acc += (x - mu)^2
  constant K_RMSOUT  : unsigned(3 downto 0) := x"8";   -- z = (x * r) * y
  constant K_LNOUT   : unsigned(3 downto 0) := x"9";   -- z = (((x - mu) * r) * y) + b
  constant K_SILUMUL : unsigned(3 downto 0) := x"A";   -- z = silu(x) * y
  constant K_GELU    : unsigned(3 downto 0) := x"B";   -- z = gelu(x)
  constant K_ROPE    : unsigned(3 downto 0) := x"C";   -- rotate pairs, in place
  constant K_ARGMAX  : unsigned(3 downto 0) := x"D";   -- index of the first maximum

  -- F16 -> F32, exact (finite inputs; GEMV block scales)
  function f16_to_f32(h : unsigned(15 downto 0)) return unsigned is
    variable m : unsigned(9 downto 0);
    variable e : integer range -32 to 255;
  begin
    if h(14 downto 0) = 0 then
      return h(15) & "000" & x"0000000";
    elsif h(14 downto 10) = 0 then
      m := h(9 downto 0);
      e := 127 - 15 + 1;
      for i in 1 to 10 loop                         -- normalise a subnormal
        if m(9) = '0' then
          m := m(8 downto 0) & '0';
          e := e - 1;
        else
          exit;
        end if;
      end loop;
      -- now the leading 1 is m(9); drop it
      return h(15) & to_unsigned(e - 1, 8) & m(8 downto 0) & '0' & "0000000000000";
    else
      return h(15) & to_unsigned(to_integer(h(14 downto 10)) - 15 + 127, 8)
        & h(9 downto 0) & "0000000000000";
    end if;
  end function;

  -- signed integer (|v| < 2^24) -> F32, exact (GEMV block sums)
  function i_to_f32(v : signed(31 downto 0)) return unsigned is
    variable a : unsigned(31 downto 0);
    variable p : integer range 0 to 31;
  begin
    if v = 0 then
      return x"00000000";
    end if;
    if v < 0 then a := unsigned(-v); else a := unsigned(v); end if;
    p := 0;
    for i in 0 to 23 loop
      if a(i) = '1' then p := i; end if;
    end loop;
    a := shift_left(a, 23 - p);
    if v < 0 then
      return '1' & to_unsigned(127 + p, 8) & a(22 downto 0);
    else
      return '0' & to_unsigned(127 + p, 8) & a(22 downto 0);
    end if;
  end function;

  -- IEEE F32 a < b, for ordinary (non-NaN) values
  function flt(a, b : unsigned(31 downto 0)) return boolean is
  begin
    if a(30 downto 0) = 0 and b(30 downto 0) = 0 then
      return false;                                    -- -0 = +0
    elsif a(31) /= b(31) then
      return a(31) = '1';
    elsif a(31) = '0' then
      return a(30 downto 0) < b(30 downto 0);
    else
      return a(30 downto 0) > b(30 downto 0);
    end if;
  end function;

  ---------------------------------------------------------------------------
  -- cpuclock domain
  ---------------------------------------------------------------------------
  signal job_ptr      : unsigned(27 downto 0) := (others => '0');
  signal hr_size_mb   : unsigned(7 downto 0) := to_unsigned(8, 8);
  function sd_default(base : boolean; present : boolean) return unsigned is
  begin
    if not present then
      return x"00";
    elsif base then
      return x"80";
    else
      return x"40";
    end if;
  end function;
  function hr_default(present : boolean) return unsigned is
  begin
    if present then return x"C0"; else return x"80"; end if;
  end function;
  signal hr_base_mb   : unsigned(7 downto 0) := hr_default(has_sdram);
  signal sd_base_mb   : unsigned(7 downto 0) := sd_default(true, has_sdram);
  signal sd_size_mb   : unsigned(7 downto 0) := sd_default(false, has_sdram);
  signal irq_en_done  : std_logic := '0';
  signal irq_pend_done : std_logic := '0';

  attribute ram_style : string;

  -- Load port, cpuclock side
  signal lp_ptr       : unsigned(27 downto 0) := (others => '0');  -- live pointer
  signal lp_stage     : unsigned(23 downto 0) := (others => '0');  -- staged bits 0-23
  -- Data byte hand-off to the core, which writes the ring: the byte, its
  -- ring address, and whether it completes a 256-byte block.  Held until
  -- the next data byte (at least four clock162 cycles later).
  signal lp_wr_tgl    : std_logic := '0';
  signal lp_wr_addr   : unsigned(9 downto 0) := (others => '0');
  signal lp_wr_data   : unsigned(7 downto 0) := x"00";
  signal lp_wr_blk    : std_logic := '0';
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
  -- The ring is written and read only on clock162: no LUT RAM path
  -- crosses clock domains.
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
  signal c_hr_base : unsigned(7 downto 0) := x"80";

  type core_state_t is (
    C_IDLE,
    C_FETCH_SETUP, C_FETCH_DECODE, C_FETCH_ISSUE, C_FETCH_WAIT, C_RESOLVE, C_DECODE, C_DEC2,
    C_LEA_MUL, C_MEM_DECODE, C_MEM_ISSUE, C_MEM_WAIT,
    C_FPU_WAIT, C_RD_DEC, C_RD_ISSUE, C_RD_WAIT, C_WR_DEC, C_WR_ISSUE, C_WR_WAIT,
    V_CHUNK, V_CHUNK_MIN1, V_CHUNK_MIN2, V_CHUNK_ADDR, V_LDY, V_LDB, V_EL0, V_EL, V_ELST, V_ADV,
    E_K1, E_K2, E_K3, E_ACC, E_ACC2,
    T_START, T_K, T_I, T_LOOK, T_ROM2, T_COEFF, T_C0, T_DONE,
    R_S0, R_S1, R_S2, R_S3, R_S4, R_S5, R_S6,
    L_S0, L_S1, L_S2, L_S3, L_S4, L_S5, L_S6, L_S7,
    M_NEXT, M_S0, M_S1, M_S2,
    EF_START, EF_DONE,
    RO_CS, RO_CS2, E_R1, E_R2, E_R3, E_R4, E_R5, E_R6, AM_DONE,
    A_PRM, A_PRM2, A_CHK, A_RS0, A_RS1, A_RS2, A_RS3, A_GRP, A_HEAD, A_Q, A_Q2,
    A_SPAN, A_SPAN2, A_STR0, A_STR, A_SE, A_S_T, A_S_W, A_S_SC,
    A_E_T, A_E_W, A_E_P, A_E_3, A_E_R,
    A_O_F, A_O_F1, A_O_F2, A_O_W, A_WR, A_WR2, A_HNEXT,
    D_GROUP, D_FETCH0, D_FETCH, D_EMIT, D_EMIT_W, D_SCALE, D_QMUL, D_STORE, D_AFTER,
    D_KH0, D_KH1, D_KH, D_KDEC, D_KD, D_KDM, D_KA1, D_KA2, D_KB1, D_KB2,
    D_KQ, D_KQ2, D_KQ3, D_KMUL, D_KSUB,
    G_QFILL0, G_QFILL, G_QAM, G_KAM2, G_QID, G_QID2, G_QD16, G_QDX, G_QDX2, G_QQ, G_QQW,
    G_SET, G_KAM, G_KX,
    G_ROW0, G_ROW_MUL, G_ROW_ADDR, G2_D1, G2_D2, G2_D2W, G2_D3, G2_WAIT, G2_T1, G2_T2, G2_T3, G2_END,
    G2_KS,
    G_OUT, G_OUT2, G_OUT3, G_OUT4,
    C_COPY_CALC, C_COPY_RD_DECODE, C_COPY_RD_ISSUE, C_COPY_RD_WAIT,
    C_COPY_WR_DECODE, C_COPY_WR_ISSUE, C_COPY_WR_WAIT,
    C_SYNC_ISSUE, C_SYNC_WAIT,
    C_LP_DECODE, C_LP_ISSUE, C_LP_WAIT, C_LP_INVAL, C_LP_DONE,
    C_NEXT, C_END);
  signal cstate : core_state_t := C_IDLE;
  -- Registered decodes of cstate, set with it (go): V_EL0, E_R6, and the
  -- states that read the next element's operands ahead (pre_x etc.), so
  -- the operand read addresses are not behind a decode of cstate
  signal cs_el0, cs_r6, cs_pf : boolean := false;
  signal rd_ret, wr_ret, fpu_ret, ve_ret, tab_ret, ef_ret : core_state_t := C_IDLE;

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
  signal words_done : boolean := true;       -- words_got = words_expected
  -- Commands issued to each port and not yet completed (cmd_done)
  signal hr_out, sd_out : unsigned(2 downto 0) := (others => '0');
  signal out_z : boolean := true;             -- hr_out = 0 and sd_out = 0
  -- Watchdog on the waits for memory: an instruction fetch, or a SYNC,
  -- that sees no read data / completions for 65536 cycles (400 us) ends
  -- the job with ERR_READ instead of hanging.  wd_fired and the last
  -- fetch's word count are readable at $FFD7507 for debugging.
  signal wd_cnt     : unsigned(15 downto 0) := (others => '0');
  signal wd_fired   : std_logic := '0';
  signal dbg_words  : unsigned(3 downto 0) := (others => '0');
  -- Stand-alone SYNC CACHE requested from the CPU (not part of a job)
  signal cpu_sync : std_logic := '0';

  -- FP unit
  signal fpu_start, fpu_done : std_logic := '0';
  signal fpu_op : unsigned(3 downto 0) := "0000";
  signal fpu_a, fpu_b, fpu_res, fpu_r : unsigned(31 downto 0) := (others => '0');

  -- Vector engine
  signal v_n       : unsigned(31 downto 0) := (others => '0');  -- elements left
  signal px, py, pz, ps, ostart : unsigned(27 downto 0) := (others => '0');
  signal v_e, v_i  : unsigned(7 downto 0) := (others => '0');   -- chunk size, index
  -- Vector chunk limits are computed independently before the minimum tree.
  -- 0xFF is the neutral limit for a disabled operand; every real boundary
  -- limit is <= 128.  These registers isolate the full-width v_n test and
  -- address-boundary calculations from the chunk-size minimum network.
  signal vc_rem_q, vc_x_q, vc_y_q, vc_b_q, vc_z_q : unsigned(7 downto 0) := (others => '0');
  signal vc_left_q, vc_right_q : unsigned(7 downto 0) := (others => '0');
  signal o16       : std_logic := '0';                          -- F16 output
  signal two_ops   : std_logic := '0';                          -- Y input stream
  signal has_b     : std_logic := '0';                          -- B input stream
  signal has_out   : std_logic := '0';                          -- writes Z
  signal ve_kind   : unsigned(3 downto 0) := (others => '0');   -- element operation
  signal pb        : unsigned(27 downto 0) := (others => '0');
  signal bx, by, bz : unsigned(27 downto 0) := (others => '0'); -- instruction bases
  signal ve_acc    : unsigned(31 downto 0) := (others => '0');  -- pass accumulator
  signal ve_first  : std_logic := '0';
  signal ex, ey, eb, ev : unsigned(31 downto 0) := (others => '0');  -- element values
  -- Operands of element v_i, read by whichever state enters V_EL (pf_go):
  -- X, the next X (ROPE), Y and B; and v_i's byte offsets into the buffers
  -- Table lookup range checks of tx, made where tx is set: tx < lo, and
  -- not (tx < hi)
  signal tx_below, tx_above : boolean := false;
  signal pre_x, pre_x1, pre_y, pre_b : unsigned(31 downto 0) := (others => '0');
  signal vix, viy, vib : unsigned(7 downto 0) := (others => '0');
  -- Their word addresses plus 0..7, kept with them, so the read-ahead's RAM
  -- addresses are a choice between registers (no adder in front of the RAM)
  type w7x8_t is array (0 to 7) of unsigned(6 downto 0);
  constant W7_INIT : w7x8_t := ("0000000", "0000001", "0000010", "0000011",
                                "0000100", "0000101", "0000110", "0000111");
  signal vxw, vyw, vbw : w7x8_t := W7_INIT;
  signal v_done : boolean := false;             -- v_i = v_e (chunk finished)
  -- v_n = 0 and v_n = 1, set wherever v_n is
  signal v_n_z : boolean := true;
  signal v_n_one : boolean := false;
  signal s_mu, s_r, s_sc, s_rn : unsigned(31 downto 0) := (others => '0');
  signal mr_r, mr_rows : unsigned(31 downto 0) := (others => '0');  -- MEANROWS
  signal mr_src_row : unsigned(27 downto 0) := (others => '0'); -- address for current MEANROWS row
  -- table lookup subroutine
  -- Three functions x 256 segments x {C0,C1}.  A single synchronous ROM
  -- replaces six independent asynchronous 32-bit coefficient multiplexers.
  type coeff_rom_t is array (0 to 767) of unsigned(63 downto 0);
  function init_coeff_rom return coeff_rom_t is
    variable r : coeff_rom_t;
  begin
    for i in 0 to TAB_SEGMENTS - 1 loop
      r(i)       := SILU_C0(i) & SILU_C1(i);
      r(256 + i) := GELU_C0(i) & GELU_C1(i);
      r(512 + i) := EXPT_C0(i) & EXPT_C1(i);
    end loop;
    return r;
  end function;
  signal coeff_rom : coeff_rom_t := init_coeff_rom;
  attribute rom_style : string;
  attribute rom_style of coeff_rom : signal is "block";
  signal coeff_word : unsigned(63 downto 0) := (others => '0');
  -- coeff_word, registered (the BRAM's output register): the ROM's
  -- clock-to-out is not on the fpu_a mux
  signal coeff_q : unsigned(63 downto 0) := (others => '0');
  signal tab_id    : unsigned(1 downto 0) := "00";              -- 0 SiLU, 1 GELU, 2 exp
  signal tx, tval, tc0 : unsigned(31 downto 0) := (others => '0');
  -- element fetch subroutine: ef_val = F32 element at ef_addr (F16 if ef_f16)
  signal ef_addr   : unsigned(27 downto 0) := (others => '0');
  signal ef_f16    : std_logic := '0';
  signal ef_val    : unsigned(31 downto 0) := (others => '0');
  -- ROPE
  type f32x256_t is array (0 to 255) of unsigned(31 downto 0);
  signal csv, outv : f32x256_t := (others => (others => '0'));
  attribute ram_style of csv, outv : signal is "distributed";
  signal rope_j    : unsigned(8 downto 0) := (others => '0');
  signal rope_hd   : unsigned(8 downto 0) := (others => '0');
  signal rp_a, rp_b, rp0, x1v : unsigned(31 downto 0) := (others => '0');
  signal cs_i      : unsigned(8 downto 0) := (others => '0');
  -- ARGMAX
  signal am_best   : unsigned(31 downto 0) := (others => '0');
  signal am_idx, ve_g : unsigned(31 downto 0) := (others => '0');
  -- ARGMAX compare stage: the element read in V_EL, compared on the next edge
  signal am_x_q, am_g_q : unsigned(31 downto 0) := (others => '0');
  signal am_v_q, am_first_q : std_logic := '0';
  -- ATTN
  type f32x1024_t is array (0 to 1023) of unsigned(31 downto 0);
  signal sarr      : f32x1024_t := (others => (others => '0'));
  attribute ram_style of sarr : signal is "distributed";
  signal sarr0     : unsigned(31 downto 0) := (others => '0');  -- copy of sarr(0)
  signal at_k, at_v, at_rowaddr, at_ea : unsigned(27 downto 0) := (others => '0');
  signal at_nh, at_nkv, at_hd, at_fmt, at_pos : unsigned(31 downto 0) := (others => '0');
  -- EF_START needs the block at ef_addr loaded: recomputed every cycle,
  -- which is enough because ef_addr, ld_block and ld_valid are never
  -- written in the state just before EF_START (asserted there)
  signal ef_miss : boolean := true;
  signal ps_miss : boolean := true;
  -- DEQROW: d_j + 1 = epg (the group's last element), kept with d_j
  signal d_jl    : boolean := false;
  -- cstate = G2_T3, set by go()
  signal cs_t3   : boolean := false;
  -- gi = gbytes in D_FETCH: set in D_FETCH0 and as gi steps
  signal gi_end  : boolean := false;
  signal at_bad  : boolean := false;    -- the parameter block is invalid (A_CHK)
  signal at_hend : boolean := false;    -- at_h = at_nh: every head done
  signal at_ge   : boolean := false;    -- at_gc >= at_nkv (A_GRP)
  signal at_h, at_kvh, at_gc, at_group : unsigned(15 downto 0) := (others => '0');
  signal at_rowb   : unsigned(27 downto 0) := (others => '0');
  signal at_qhead_addr : unsigned(27 downto 0) := (others => '0'); -- Q head start
  signal at_kv_stride : unsigned(27 downto 0) := (others => '0'); -- bytes per KV head
  signal at_kv_offset : unsigned(27 downto 0) := (others => '0'); -- current KV head offset
  signal at_t      : unsigned(15 downto 0) := (others => '0');
  -- Reloaded by the states that write at_t: at_t = at_pos + 1 (the last position is
  -- done), and sarr(at_t), read ahead so the FPU operands come from a register
  signal at_tend   : boolean := false;
  signal at_iend   : boolean := false;    -- at_i = at_hd, set alongside at_i
  signal at_sv     : unsigned(31 downto 0) := (others => '0');
  signal at_pos1   : unsigned(15 downto 0) := (others => '0');   -- at_pos + 1
  signal at_i      : unsigned(8 downto 0) := (others => '0');
  signal at_rs, at_m, at_r, at_acc, at_w : unsigned(31 downto 0) := (others => '0');
  signal at_pi     : unsigned(2 downto 0) := (others => '0');
  -- streaming K / V: at_pos * at_rowb (A_SPAN, by shift and add), and it
  -- plus a head's segment; the pass (0 K: scores, 1 V: output)
  signal at_span, at_spl, at_ma : unsigned(27 downto 0) := (others => '0');
  signal at_sm     : unsigned(9 downto 0) := (others => '0');
  signal at_vp     : std_logic := '0';
  -- read / write subroutines
  signal rd_addr, wr_addr : unsigned(27 downto 0) := (others => '0');
  signal rd_len, wr_len   : unsigned(8 downto 0) := (others => '0');
  signal rd_sel    : unsigned(1 downto 0) := "00";
  signal mw_active : std_logic := '0';
  signal mw_k, mw_lead, mw_vend : unsigned(8 downto 0) := (others => '0');
  signal mw_idx    : unsigned(6 downto 0) := (others => '0');
  -- DEQROW
  type grp_t is array (0 to 33) of unsigned(7 downto 0);

  -- GEMV weight block unpacking: the one place that knows the block
  -- formats.  A block as the assembler leaves it (grpf; Q8_0 is
  -- grpf(0 to 33), Q4_0 grpf(16 to 33), MXFP4 grpf(17 to 33)) becomes 32
  -- signed weights and its F32 scale; the MAC lanes see only that.  (New
  -- formats: here, the block length (gbytes) and the matrix size in G_ROW0.)
  type qw32_t is array (0 to 31) of signed(8 downto 0);
  -- IQ4_NL / IQ4_XS: the value a 4-bit index stands for (kvalues_iq4nl)
  function iq4v(n : unsigned(3 downto 0)) return signed is
    type t_t is array (0 to 15) of integer;
    constant t : t_t := (-127, -104, -83, -65, -49, -35, -22, -10, 1, 13, 25, 38, 53, 69, 89, 113);
  begin
    return to_signed(t(to_integer(n)), 9);
  end function;
  -- MXFP4 element: E2M1, doubled (ggml's kvalues_mxfp4)
  function e2m1x2(n : unsigned(3 downto 0)) return signed is
    variable v : integer;
  begin
    case to_integer(n(2 downto 0)) is
      when 0 => v := 0;  when 1 => v := 1;  when 2 => v := 2;  when 3 => v := 3;
      when 4 => v := 4;  when 5 => v := 6;  when 6 => v := 8;  when others => v := 12;
    end case;
    if n(3) = '1' then v := -v; end if;
    return to_signed(v, 9);
  end function;
  -- MXFP4 scale: E8M0, halved (ggml_e8m0_to_fp32_half), as F32 bits
  function e8m0_half(e : unsigned(7 downto 0)) return unsigned is
  begin
    if e = 0 then
      return x"00200000";
    elsif e = 1 then
      return x"00400000";
    else
      return '0' & (e - 1) & "00000000000000000000000";
    end if;
  end function;
  -- Q5_0's value: (high bit, nibble) - 16
  function q5v(hb : std_logic; nib : unsigned(3 downto 0)) return signed is
    variable u : unsigned(4 downto 0);
  begin
    u := hb & nib;
    return resize(signed('0' & u), 9) - 16;
  end function;
  function unpack_w(g : grp_t; fmt : unsigned(7 downto 0)) return qw32_t is
    variable w : qw32_t;
  begin
    for j in 0 to 31 loop
      if fmt = 8 then                                -- Q8_0: d, then 32 x int8
        w(j) := resize(signed(g(2 + j)), 9);
      elsif fmt = 20 then                            -- IQ4_NL: as Q4_0, through
        if j < 16 then                               -- kvalues_iq4nl
          w(j) := iq4v(g(18 + j)(3 downto 0));
        else
          w(j) := iq4v(g(18 + j - 16)(7 downto 4));
        end if;
      elsif fmt = 39 then                            -- MXFP4: e, then 16 bytes,
        if j < 16 then                               -- low nibbles first
          w(j) := e2m1x2(g(18 + j)(3 downto 0));
        else
          w(j) := e2m1x2(g(18 + j - 16)(7 downto 4));
        end if;
      elsif fmt = 6 and j < 16 then                  -- Q5_0: d, 4 bytes of high
        w(j) := q5v(g(14 + j / 8)(j mod 8), g(18 + j)(3 downto 0));  -- bits, then
      elsif fmt = 6 then                             -- Q4_0's nibbles
        w(j) := q5v(g(14 + j / 8)(j mod 8), g(18 + j - 16)(7 downto 4));
      elsif j < 16 then                              -- Q4_0: d, then 16 bytes,
        w(j) := resize(signed('0' & g(18 + j)(3 downto 0)), 9) - 8;  -- low
      else                                           -- nibbles first
        w(j) := resize(signed('0' & g(18 + j - 16)(7 downto 4)), 9) - 8;
      end if;
    end loop;
    return w;
  end function;
  function unpack_s(g : grp_t; fmt : unsigned(7 downto 0)) return unsigned is
  begin
    if fmt = 8 then
      return f16_to_f32(g(1) & g(0));
    elsif fmt = 39 then
      return e8m0_half(g(17));
    elsif fmt = 6 then
      return f16_to_f32(g(13) & g(12));
    else
      return f16_to_f32(g(17) & g(16));
    end if;
  end function;

  -- ---------------------------------------------------------------------
  -- K-quants (Q2_K .. Q6_K, ggml types 10 .. 14): 256-weight super-blocks
  -- (ssnail_hw.gemv_kquant).  The assembler writes a super-block's bytes
  -- into a double-buffered word RAM (kq_sb*, byte lanes); a header unit
  -- decodes its scales, mins, d and dmin; the K reader gives the lanes 4
  -- quants a cycle from it, one pass of 32 per 32-block of x.
  -- the codebook formats: IQ2_XXS, IQ2_XS, IQ3_XXS, IQ3_S, IQ2_S (GEMV
  -- only: their weights come through the IQ front end, not the K reader)
  function fmt_iq(fmt : unsigned(7 downto 0)) return boolean is
  begin
    return (fmt >= 16 and fmt <= 18) or fmt = 21 or fmt = 22;
  end function;
  -- the 256-weight super-block formats: Q2_K .. Q6_K, IQ4_XS, TQ2_0, and
  -- the codebook ones
  function fmt_k(fmt : unsigned(7 downto 0)) return boolean is
  begin
    return (fmt >= 10 and fmt <= 14) or fmt = 23 or fmt = 35 or fmt_iq(fmt);
  end function;
  -- the 32-weight block formats GEMV takes: Q4_0, Q5_0, Q8_0, IQ4_NL, MXFP4
  function fmt_q(fmt : unsigned(7 downto 0)) return boolean is
  begin
    return fmt = 2 or fmt = 6 or fmt = 8 or fmt = 20 or fmt = 39;
  end function;
  function kq_bytes(fmt : unsigned(7 downto 0)) return integer is
  begin
    case to_integer(fmt) is
      when 10 => return 84;  when 11 => return 110; when 12 => return 144;
      when 13 => return 176; when 23 => return 136; when 35 => return 66;
      when 16 => return 66;  when 17 => return 74;  when 22 => return 82;
      when 18 => return 98;  when 21 => return 110;
      when others => return 210;
    end case;
  end function;
  -- word (4 bytes) i of the header copy: scales, mins, d, dmin
  function kq_hword(fmt : unsigned(7 downto 0); i : integer) return integer is
  begin
    case to_integer(fmt) is
      when 10 => if i = 4 then return 20; else return i; end if;   -- scales; d, dmin at 80
      when 11 => return 24 + i;                                    -- scales at 96; d at 108
      when 12 | 13 | 23 => return i;                               -- d, dmin, scales at 0
      when 35 => if i = 4 then return 16; else return 0; end if;  -- d at 64
      -- the codebook formats are written 2 bytes in (kq_wo), so d is in
      -- word 0 (bytes 2, 3) and the rest word-aligned; d is word 2 here
      when 16 | 18 => return 0;                                    -- scales per pass
      when 17 => if i < 2 then return 17 + i; else return 0; end if; -- scales at 66
      when 22 => if i < 2 then return 19 + i; else return 0; end if; -- scales at 74
      when 21 => if i = 0 then return 27; else return 0; end if;     -- scales at 106
      when others => return 48 + i;                                -- scales at 192; d at 208
    end case;
  end function;
  type kq_hb_t is array (0 to 19) of unsigned(7 downto 0);
  type kq_sc16_t is array (0 to 15) of signed(7 downto 0);
  type kq_m16_t is array (0 to 15) of unsigned(5 downto 0);
  -- integer scale of each 16-weight group (as gguf-py's dequantisers)
  function kq_scales(fmt : unsigned(7 downto 0); hb : kq_hb_t) return kq_sc16_t is
    variable sc : kq_sc16_t;
    variable v : unsigned(7 downto 0);
    variable j : integer;
  begin
    for g in 0 to 15 loop
      case to_integer(fmt) is
        when 10 => sc(g) := signed(resize(hb(g)(3 downto 0), 8));
        when 11 =>
          v := shift_right(hb(g mod 8), 4 * (g / 8)) and x"0F";
          v := v or shift_left(shift_right(hb(8 + g mod 4), 2 * (g / 4)) and x"03", 4);
          sc(g) := signed(v) - 32;
        when 12 | 13 =>
          j := g / 2;
          if j < 4 then
            v := hb(4 + j) and x"3F";
          else
            v := (hb(12 + j - 4) and x"0F") or (shift_right(hb(4 + j - 4), 2) and x"30");
          end if;
          sc(g) := signed(v);
        when 23 =>                                         -- IQ4_XS: per 32, less 32
          j := g / 2;
          v := shift_right(hb(4 + j / 2), 4 * (j mod 2)) and x"0F";
          v := v or shift_left(resize(shift_right(hb(3) & hb(2), 2 * j)(1 downto 0), 8), 4);
          sc(g) := signed(v) - 32;
        when 35 => sc(g) := to_signed(1, 8);               -- TQ2_0: d alone
        when 17 | 22 =>                                    -- IQ2_XS, IQ2_S: 2s + 1
          v := shift_right(hb(g / 2), 4 * (g mod 2)) and x"0F";   -- per 16
          sc(g) := signed(v(6 downto 0) & '1');
        when 21 =>                                         -- IQ3_S: per 32
          v := shift_right(hb(g / 4), 4 * ((g / 2) mod 2)) and x"0F";
          sc(g) := signed(v(6 downto 0) & '1');
        when 16 | 18 => sc(g) := to_signed(1, 8);          -- (the IQ front end's)
        when others => sc(g) := signed(hb(g));
      end case;
    end loop;
    return sc;
  end function;
  function kq_mins(fmt : unsigned(7 downto 0); hb : kq_hb_t) return kq_m16_t is
    variable m : kq_m16_t;
    variable v : unsigned(7 downto 0);
    variable j : integer;
  begin
    for g in 0 to 15 loop
      v := x"00";
      if fmt = 10 then
        v := x"0" & hb(g)(7 downto 4);
      elsif fmt = 12 or fmt = 13 then
        j := g / 2;
        if j < 4 then
          v := hb(8 + j) and x"3F";
        else
          v := shift_right(hb(12 + j - 4), 4) or (shift_right(hb(8 + j - 4), 2) and x"30");
        end if;
      end if;
      m(g) := v(5 downto 0);
    end loop;
    return m;
  end function;
  function kq_d(fmt : unsigned(7 downto 0); hb : kq_hb_t) return unsigned is
  begin
    case to_integer(fmt) is
      when 10 => return hb(17) & hb(16);
      when 11 => return hb(13) & hb(12);
      when 12 | 13 | 23 => return hb(1) & hb(0);
      when 16 | 17 | 18 | 21 | 22 => return hb(11) & hb(10);
      when others => return hb(17) & hb(16);
    end case;
  end function;
  -- the codebook formats' d is F32(d) / 8 (IQ2) or / 4 (IQ3_XXS), exactly:
  -- an exponent less 3 or 2 (F32(F16) is normal with a biased exponent of
  -- at least 103, or zero)
  function kq_dscale(v : unsigned(31 downto 0); sh : unsigned(1 downto 0)) return unsigned is
    variable r : unsigned(31 downto 0);
  begin
    r := v;
    if v(30 downto 23) /= 0 then
      r(30 downto 23) := v(30 downto 23) - sh;
    end if;
    return r;
  end function;
  function kq_dmin(fmt : unsigned(7 downto 0); hb : kq_hb_t) return unsigned is
  begin
    if fmt = 10 then return hb(19) & hb(18); else return hb(3) & hb(2); end if;
  end function;
  -- IQ front end, pass p: its first index word, its sign / scale word and
  -- its high-bits word (words of the half; the blocks start at byte 2)
  function iq_iwf(fmt : unsigned(7 downto 0); p : unsigned(2 downto 0)) return unsigned is
  begin
    if fmt = 22 then return resize(p, 6) + 1; else return (p & '0') + to_unsigned(1, 6); end if;
  end function;
  function iq_aw(fmt : unsigned(7 downto 0); p : unsigned(2 downto 0)) return unsigned is
  begin
    case to_integer(fmt) is
      when 16 => return (p & '0') + to_unsigned(2, 6);         -- IQ2_XXS: after the indices
      when 22 => return resize(p, 6) + 9;                      -- IQ2_S: signs
      when 18 => return resize(p, 6) + 17;                     -- IQ3_XXS: signs, scale
      when 21 => return resize(p, 6) + 19;                     -- IQ3_S: signs
      when others => return to_unsigned(0, 6);
    end case;
  end function;
  function iq_bw(p : unsigned(2 downto 0)) return unsigned is
  begin
    return to_unsigned(17, 6) + resize(p(2 downto 2), 6);      -- qh (IQ2_S, IQ3_S)
  end function;
  -- the K reader, for pass p (32 weights): word base of the low bits and
  -- their shift and mask, of the high bits (if any), their width, and the
  -- fixed offset: q = (lo | hi << wl) - off  (Q3_K: ql - 4 (1 - h))
  type kq_rd_t is record
    la, ha : unsigned(5 downto 0);
    sl, sh : unsigned(2 downto 0);
    ml : unsigned(3 downto 0);
    mh : unsigned(1 downto 0);
    wl : unsigned(2 downto 0);
    off : unsigned(5 downto 0);
    wr : std_logic;      -- 4 words, low nibbles, then the same 4, high (IQ4_XS)
    tb : std_logic;      -- q = iq4v(lo)
  end record;
  function kq_rd(fmt : unsigned(7 downto 0); p : integer) return kq_rd_t is
    variable c : kq_rd_t;
  begin
    c.ha := (others => '0'); c.sh := "000"; c.mh := "00"; c.off := (others => '0');
    c.wr := '0'; c.tb := '0';
    case to_integer(fmt) is
      when 23 =>                                           -- IQ4_XS
        c.la := to_unsigned(2 + 4 * p, 6); c.sl := "000";
        c.ml := x"F"; c.wl := to_unsigned(4, 3); c.wr := '1'; c.tb := '1';
      when 35 =>                                           -- TQ2_0
        c.la := to_unsigned(8 * (p / 4), 6); c.sl := to_unsigned(2 * (p mod 4), 3);
        c.ml := x"3"; c.wl := to_unsigned(2, 3); c.off := to_unsigned(1, 6);
      when 10 =>                                           -- Q2_K
        c.la := to_unsigned(4 + 8 * (p / 4), 6); c.sl := to_unsigned(2 * (p mod 4), 3);
        c.ml := x"3"; c.wl := to_unsigned(2, 3);
      when 11 =>                                           -- Q3_K
        c.la := to_unsigned(8 + 8 * (p / 4), 6); c.sl := to_unsigned(2 * (p mod 4), 3);
        c.ml := x"3"; c.wl := to_unsigned(2, 3);
        c.ha := to_unsigned(0, 6); c.sh := to_unsigned(p, 3); c.mh := "01";
        c.off := to_unsigned(4, 6);
      when 12 =>                                           -- Q4_K
        c.la := to_unsigned(4 + 8 * (p / 2), 6); c.sl := to_unsigned(4 * (p mod 2), 3);
        c.ml := x"F"; c.wl := to_unsigned(4, 3);
      when 13 =>                                           -- Q5_K
        c.la := to_unsigned(12 + 8 * (p / 2), 6); c.sl := to_unsigned(4 * (p mod 2), 3);
        c.ml := x"F"; c.wl := to_unsigned(4, 3);
        c.ha := to_unsigned(4, 6); c.sh := to_unsigned(p, 3); c.mh := "01";
      when others =>                                       -- Q6_K
        c.la := to_unsigned(16 * (p / 4) + 8 * (p mod 2), 6);
        c.sl := to_unsigned(4 * ((p mod 4) / 2), 3);
        c.ml := x"F"; c.wl := to_unsigned(4, 3);
        c.ha := to_unsigned(32 + 8 * (p / 4), 6); c.sh := to_unsigned(2 * (p mod 4), 3);
        c.mh := "11"; c.off := to_unsigned(32, 6);
    end case;
    return c;
  end function;
  -- one quant from byte lanes bl (low bits) and bh (high bits)
  function kq_q(bl, bh : unsigned(7 downto 0); c : kq_rd_t) return signed is
    variable lo, hi : unsigned(7 downto 0);
    variable v : integer;
  begin
    lo := shift_right(bl, to_integer(c.sl)) and ("0000" & c.ml);
    hi := shift_right(bh, to_integer(c.sh)) and ("000000" & c.mh);
    if c.tb = '1' then
      return iq4v(lo(3 downto 0));
    end if;
    v := to_integer(lo) + to_integer(shift_left(hi, to_integer(c.wl))) - to_integer(c.off);
    return to_signed(v, 9);
  end function;

  signal grp       : grp_t := (others => x"00");
  signal gi, gbytes : unsigned(7 downto 0) := (others => '0');
  signal d_j, epg  : unsigned(8 downto 0) := (others => '0');
  -- DEQROW of a K-quant super-block (fetched into kq_sb, half 0): A = d * sc
  -- of the 16-group (and B = dmin * m), then each q * A (- B)
  signal dk        : std_logic := '0';
  signal kq_gs     : std_logic := '0';               -- the group's A, B are in
  signal kd32, kdm32, kq_ga32, kq_gb32 : unsigned(31 downto 0) := (others => '0');
  signal d_fmt     : unsigned(7 downto 0) := (others => '0');
  -- DEQROW's d_fmt, decoded once a row (D_GROUP) for D_EMIT
  subtype dk_t is unsigned(2 downto 0);
  constant DK_F32 : dk_t := "000"; constant DK_F16 : dk_t := "001";
  constant DK_BF16 : dk_t := "010"; constant DK_MX : dk_t := "011";
  constant DK_Q : dk_t := "100"; constant DK_K : dk_t := "101";
  signal d_kind    : dk_t := DK_F32;
  function deq_kind(fmt : unsigned(7 downto 0)) return dk_t is
  begin
    if fmt_k(fmt) then return DK_K; end if;
    case to_integer(fmt) is
      when 0 => return DK_F32;
      when 1 => return DK_F16;
      when 30 => return DK_BF16;
      when 39 => return DK_MX;
      when others => return DK_Q;
    end case;
  end function;
  signal dq_scale, d_val : unsigned(31 downto 0) := (others => '0');
  signal d_have_scale : std_logic := '0';
  signal ld_valid  : std_logic := '0';
  signal ld_block  : unsigned(27 downto 8) := (others => '0');
  signal ea_z      : unsigned(27 downto 0) := (others => '0');
  signal fetch_ret : core_state_t := C_IDLE;
  -- C_DECODE's choice of next state, taken in C_DEC2: one cycle per
  -- instruction keeps the opcode decode off cstate's next-state logic
  signal dec_next : core_state_t := C_IDLE;
  -- Q8_0 / Q4_0 element d_j of grp, as a signed integer: recomputed every
  -- cycle; grp and d_j are never written in the state just before D_EMIT
  -- (D_STORE goes through D_EMIT_W), asserted there
  signal d_qv : signed(31 downto 0) := (others => '0');
  -- DEQROW output written since ostart (pz /= ostart), set with every write
  -- of pz or ostart on the way to D_GROUP
  signal d_unflushed : boolean := false;
  -- GEMV accumulate: the old output block is loaded (out_loaded = '1' and
  -- pz(27:8) = out_block) and the old value at pz, recomputed every cycle:
  -- none of them changes in the state just before G_OUT (asserted there)
  signal g_have_old : boolean := false;
  -- GEMV quantise: px's 256-byte block is loaded (ld_valid and ld_block),
  -- set in G_QFILL0 and kept up to date by G_QFILL
  signal qf_hit : boolean := false;
  -- FSM branch conditions, registered (each asserted where it is used):
  -- gblk + 1 = g_nb and tl_blk + 1 = g_nb (recomputed every cycle);
  -- mr_r = mr_rows (likewise); at_i + 1 = at_hd (set by state, as at_iend);
  -- and tests of an FPU result, made as fpu_r is loaded from it
  signal g_qlast, tl_last, mr_end, at_inx : boolean := false;
  signal fr_neg, fr_big, fr_z, fr_mlt : boolean := false;
  -- G_QFILL's element, folded into g_amax the cycle after it is read
  signal qf_v   : unsigned(30 downto 0) := (others => '0');
  signal qf_vld : boolean := false;
  signal g_oldv : unsigned(31 downto 0) := (others => '0');

  -- GEMV
  type f32x32_t is array (0 to 31) of unsigned(31 downto 0);
  type qx_t is array (0 to 4095) of signed(7 downto 0);
  type dx_t is array (0 to 127) of unsigned(31 downto 0);
  signal xb        : f32x32_t := (others => (others => '0'));  -- one block of x
  -- quantised x, 4 elements wide: element e is in qxk(e mod 4)(e / 4), so the
  -- 4 MAC lanes read 4 consecutive elements per cycle
  type qx4_t is array (0 to 1023) of signed(7 downto 0);
  signal qx0, qx1, qx2, qx3 : qx4_t := (others => (others => '0'));
  signal dxs       : dx_t := (others => (others => '0'));      -- its scales, as F32
  attribute ram_style of qx0, qx1, qx2, qx3, dxs : signal is "distributed";

  -- GEMV v2 row phase: stream reader -> word FIFO -> block assembler
  -- (fill registers) -> 4 MAC lanes (compute registers) -> tail on the main
  -- FSM, all running concurrently.
  signal g2        : std_logic := '0';
  signal hr_valid_i, sd_valid_i : std_logic := '0';   -- the cmd_valid outputs
  type wf_t is array (0 to 255) of unsigned(15 downto 0);
  signal wf        : wf_t := (others => (others => '0'));
  attribute ram_style of wf : signal is "distributed";
  signal wf_w, wf_r : unsigned(8 downto 0) := (others => '0');
  -- wf_w - wf_r = 0, = 1, kept exact from each cycle's arrival and pop:
  -- the assembler's pop is not behind a 9-bit compare
  signal wf_z      : boolean := true;
  signal wf_o      : boolean := false;
  signal sr_next, sr_end, str_base : unsigned(27 downto 0) := (others => '0');
  -- strided streams (ATTN's K / V): sr_segs more segments after this one,
  -- each sr_stride on (sr_segst: this one's start); sr_lend: the last byte's
  -- end (the region check); sr_seg_q: the burst in stage B ends the segment
  signal sr_stride, sr_segst, sr_lend, sr_nst_q, sr_nend_q : unsigned(27 downto 0) := (others => '0');
  signal sr_segs   : unsigned(9 downto 0) := (others => '0');
  signal sr_seg_q  : boolean := false;
  signal str_local : unsigned(26 downto 0) := (others => '0');
  signal str_is_sd : std_logic := '0';
  -- Stream reader burst precompute, two register stages from sr_next.
  -- Stage A: remaining bytes, room to the 256-byte boundary, boundary
  -- address, offset into the stream.  Stage B: burst end/length and the
  -- LUMP address.  sr_ok2 is cleared whenever sr_next moves (or g2 = '0')
  -- and set again two edges later, once stage B reflects the new sr_next.
  signal sr_rem_q, sr_bnd_q, sr_off_q, sr_a1_q : unsigned(27 downto 0) := (others => '0');
  signal sr_room_q, sr_len_q : unsigned(8 downto 0) := (others => '0');
  signal sr_addr_q : unsigned(26 downto 0) := (others => '0');
  signal sr_more_q, sr_ok1, sr_ok2 : std_logic := '0';
  -- FIFO words held or requested, a cycle old: an arriving word moves one
  -- from sr_inflight to the FIFO (no change), the assembler only lowers it,
  -- and an issue blocks the next two cycles (sr_ok2), so it never
  -- understates the space in use when it is acted on
  signal sr_used_q : unsigned(9 downto 0) := (others => '0');
  -- the burst in sr_len_q fits: sr_used_q + words <= 256, made in stage B
  -- with sr_len_q from sr_used_q: after an issue it includes it two edges
  -- later, when sr_ok2 lets the next one through
  signal sr_fit_q : boolean := false;
  -- cstate was C_RD_DEC/ISSUE or C_WR_DEC/ISSUE last cycle: covers every
  -- cycle the main FSM may issue (its ISSUE states follow their DEC ones)
  signal fsm_iss_q : boolean := false;
  signal sr_inflight : unsigned(8 downto 0) := (others => '0');   -- words requested, not arrived
  -- read routing tags: 1 = stream FIFO, 0 = the usual capture path
  type rq_tag_t is array (0 to 3) of std_logic;
  type rq_cnt_t is array (0 to 3) of unsigned(7 downto 0);
  signal rq_tag    : rq_tag_t := (others => '0');
  signal rq_cnt    : rq_cnt_t := (others => (others => '0'));
  signal rq_w, rq_r : unsigned(2 downto 0) := (others => '0');
  -- assembler
  signal grpf      : grp_t := (others => x"00");
  -- unpack stage: an unpacked block waiting for the lanes (ub_full), and
  -- the one the lanes are working through
  signal ub_w, mc_wb : qw32_t := (others => (others => '0'));
  signal ub_d      : unsigned(31 downto 0) := (others => '0');   -- its scale, F32
  signal ub_full   : std_logic := '0';
  signal as_rem    : unsigned(7 downto 0) := (others => '0');   -- bytes left in this block
  signal g_bl      : unsigned(7 downto 0) := (others => '0');   -- block length, bytes
  signal as_any    : std_logic := '0';                          -- as_blocks /= 0
  -- as_flags(as_skip, as_rem): skip >= 1, 2, 3; skip + rem >= 2, 3;
  -- rem = 1, 2, 3.  All the assembler's step needs, as registers
  signal as_f      : std_logic_vector(7 downto 0) := (others => '0');
  signal as_skip   : unsigned(2 downto 0) := (others => '0');
  signal as_full   : std_logic := '0';
  signal pb_v      : std_logic := '0';
  signal pb_b      : unsigned(7 downto 0) := x"00";
  signal as_blocks : unsigned(31 downto 0) := (others => '0');   -- blocks still to assemble
  -- MAC lanes
  signal mc_busy, mc_done : std_logic := '0';
  signal mc_drain : std_logic := '0'; -- last MAC issued; pipeline not empty
  signal mc_c      : unsigned(3 downto 0) := (others => '0');
  signal mc_blk    : unsigned(7 downto 0) := (others => '0');    -- block within the row
  -- Lane overlap: a block (or K pass) starts as soon as stage 0 is free,
  -- not once the last one is through stages 1-3 and taken by the tail.
  -- The start side has its own block / pass / half (mc_sblk, kq_sp,
  -- kq_srh); finished sums (and K's first 16, and the legacy scale) go
  -- through a 2-entry queue to the tail, which keeps mc_blk, kq_p, kq_rh.
  -- mc_nq: blocks started and not yet taken (at most 2: the queue's size)
  signal mc_sblk   : unsigned(7 downto 0) := (others => '0');
  signal kq_sp     : unsigned(2 downto 0) := (others => '0');
  signal kq_srh    : std_logic := '0';
  signal mc_nq     : unsigned(1 downto 0) := "00";
  type q2_t is array (0 to 1) of signed(31 downto 0);
  type u2_t is array (0 to 1) of unsigned(31 downto 0);
  signal mq_sum, mq_lo : q2_t := (others => (others => '0'));
  signal mq_sc     : u2_t := (others => (others => '0'));
  signal mq_v, mq_scok : std_logic_vector(0 to 1) := "00";
  signal mq_w, mq_r, mq_ss, fpu3_slot : std_logic := '0';      -- (write, read, scale slots)
  signal fpu3_busy : std_logic := '0';
  signal mc_first0, mc_first1, mc_first2, mc_first3 : std_logic := '0';
  -- qx read address (mc_blk & mc_c) for each bank, kept as separate
  -- registers so each sits by its bank (one copy fanned out to all four
  -- banks' LUT RAM was a 3 ns route)
  type mc_xa_t is array (0 to 3) of unsigned(9 downto 0);
  signal mc_xa     : mc_xa_t := (others => (others => '0'));
  attribute dont_touch : string;
  attribute dont_touch of mc_xa : signal is "true";
  -- (fpu0's operands stay flip-flops: absorbed into its multiplier's DSP
  -- input registers, their wide source mux met the DSP's longer setup)
  attribute dont_touch of fpu_a, fpu_b : signal is "true";
  -- g2 enables most of the GEMV pipeline: let synthesis replicate it
  attribute max_fanout : integer;
  attribute max_fanout of g2 : signal is 50;
  signal mc_isum   : signed(31 downto 0) := (others => '0');
  -- mc_isum -> F32, three register stages (same result as i_to_f32).
  -- A finished block's sum, scale and index are captured into stage 1,
  -- which frees the lanes for the next block at once; the term is
  -- launched on fpu2 from stage 3.  One block in flight (i2f_busy).
  signal i2f_abs_q, i2f_abs2_q : unsigned(23 downto 0) := (others => '0');
  signal i2f_neg_q, i2f_neg2_q, i2f_zero_q, i2f_zero2_q : std_logic := '0';
  signal i2f_p_q   : unsigned(4 downto 0) := (others => '0');
  signal i2f_res_q : unsigned(31 downto 0) := (others => '0');
  signal i2f_scale : unsigned(31 downto 0) := (others => '0');
  signal i2f_blk   : unsigned(7 downto 0) := (others => '0');
  signal i2f_busy, i2f_ok1, i2f_ok2, i2f_ok3 : std_logic := '0';
  -- Four-lane GEMV MAC, registered after memory selection, multiplication,
  -- pair summation and final lane summation.  One group enters per 163 MHz
  -- cycle; mc_done is asserted only AFTER the final accumulation commits.
  type mc_w4_t is array (0 to 3) of signed(8 downto 0);
  type mc_x4_t is array (0 to 3) of signed(7 downto 0);
  type mc_p4_t is array (0 to 3) of signed(16 downto 0);
  type mc_p2_t is array (0 to 1) of signed(17 downto 0);
  signal mc_w_q : mc_w4_t := (others => (others => '0'));
  signal mc_x_q : mc_x4_t := (others => (others => '0'));
  signal mc_p_q : mc_p4_t := (others => (others => '0'));
  -- in DSP48s (with mc_w_q / mc_x_q as their input registers), not LUTs
  attribute use_dsp : string;
  attribute use_dsp of mc_p_q : signal is "yes";
  signal mc_pair_q : mc_p2_t := (others => (others => '0'));
  signal mc_sum_q : signed(18 downto 0) := (others => '0');
  signal mc_v0, mc_v1, mc_v2, mc_v3 : std_logic := '0';
  signal mc_last0, mc_last1, mc_last2, mc_last3 : std_logic := '0';
  signal mc_scale_ok : std_logic := '0';
  signal mc_scale  : unsigned(31 downto 0) := (others => '0');
  -- (K-quants) the lanes' element group of mc_c = 3 ends the first 16
  signal mc_mid0, mc_mid1, mc_mid2, mc_mid3 : std_logic := '0';

  -- K-quant GEMV (see kq_bytes)
  signal kq_on     : std_logic := '0';               -- this GEMV is a K-quant one
  signal kq_min    : std_logic := '0';               -- ... with mins (Q2_K, Q4_K, Q5_K)
  signal kq_nsb    : unsigned(7 downto 0) := (others => '0');   -- super-blocks per row
  -- x: amax over 256 (pass 0), then quantise (pass 1); 16-element sums
  signal kq_pass   : std_logic := '0';
  signal kq_sub    : unsigned(2 downto 0) := (others => '0');
  signal kq_amax   : unsigned(30 downto 0) := (others => '0');
  type kq_bs_t is array (0 to 255) of signed(11 downto 0);
  signal kq_bs     : kq_bs_t := (others => (others => '0'));
  signal kq_bacc   : signed(11 downto 0) := (others => '0');
  -- x quantiser: a block's 32 elements, a cycle each, x * id through the
  -- float lane's multiplier (free in the x phase: xq_on routes it), then
  -- roundf (|x * id| <= 127 for finite x: floor(|v| + 0.5) in fixed point;
  -- NaN gives 0, as the FPU's ROUNDF), into qx and the 16-sums (kq_bs).
  -- xq_busy: issuing, or results still to come
  signal xq_on, xq_iss : std_logic := '0';
  signal xq_j      : unsigned(5 downto 0) := (others => '0');
  signal xq_id     : unsigned(31 downto 0) := (others => '0');
  signal xq_blk    : unsigned(7 downto 0) := (others => '0');
  -- the float lane's multiplier when the x quantiser or the softmax
  -- engine has it (xq_on, sx_on)
  signal mx_v      : std_logic := '0';
  signal mx_a, mx_b : unsigned(31 downto 0) := (others => '0');
  signal mx_t      : unsigned(9 downto 0) := (others => '0');
  -- ATTN's softmax engine (sx_on): e_t = EXP(s_t - m) for every t, the
  -- table engine's arithmetic (T_START .. T_DONE) on the lane's multiplier
  -- and the combine adder, an element every 8 cycles: (s - m), (+16), (*16),
  -- the segment, c1 * x, c0 + that.  Each unit sees an element's operations
  -- at distinct cycles mod 8 (asserted).  e_t goes to sarr and, for the
  -- core's sequential sum on fpu0, to sx_fifo; at most 16 unsummed
  signal sx_on     : std_logic := '0';
  signal sx_ph     : unsigned(2 downto 0) := (others => '0');
  signal sx_icnt, sx_wcnt : unsigned(15 downto 0) := (others => '0');
  signal sx_nm, sx_s : unsigned(31 downto 0) := (others => '0');
  type f32x8_t is array (0 to 7) of unsigned(31 downto 0);
  signal sx_d, sx_c0 : f32x8_t := (others => (others => '0'));
  signal sx_ti     : unsigned(7 downto 0) := (others => '0');
  signal sx_v1, sx_v2, sx_v3 : std_logic := '0';
  signal sx_t1, sx_t2, sx_t3 : unsigned(4 downto 0) := (others => '0');
  signal sx_rw, sx_cq : unsigned(63 downto 0) := (others => '0');
  type f32x16_t is array (0 to 15) of unsigned(31 downto 0);
  signal sx_fifo   : f32x16_t := (others => (others => '0'));
  attribute ram_style of sx_fifo : signal is "distributed";
  signal xq_pend   : unsigned(5 downto 0) := (others => '0');
  signal xq_busy   : boolean := false;
  signal xr_v1, xr_v2 : std_logic := '0';
  signal xr_j1, xr_j2 : unsigned(4 downto 0) := (others => '0');
  signal xr_s1, xr_z1 : std_logic := '0';
  signal xr_fix    : unsigned(31 downto 0) := (others => '0');
  signal xr_q      : signed(7 downto 0) := (others => '0');
  signal fm_v, fm_vin : std_logic := '0';
  signal fm_a, fm_b : unsigned(31 downto 0) := (others => '0');
  signal fm_tag    : unsigned(9 downto 0) := (others => '0');
  -- super-block buffer: byte lane l of word w (half h) at kq_sbl(h & w)
  type kq_sb_t is array (0 to 127) of unsigned(7 downto 0);
  signal kq_sb0, kq_sb1, kq_sb2, kq_sb3 : kq_sb_t := (others => (others => '0'));
  attribute ram_style of kq_bs, kq_sb0, kq_sb1, kq_sb2, kq_sb3 : signal is "distributed";
  signal kq_wh     : std_logic := '0';               -- half being written
  signal kq_wp     : unsigned(7 downto 0) := (others => '0');   -- its next byte
  signal kq_full   : std_logic_vector(0 to 1) := "00";          -- half holds a super-block
  signal kq_fset   : std_logic := '0';                           -- (kq_full(kq_fseth) next)
  signal kq_fseth  : std_logic := '0';
  type kw_a_t is array (0 to 3) of unsigned(6 downto 0);
  type kw_d_t is array (0 to 3) of unsigned(7 downto 0);
  signal kw_we_q   : std_logic_vector(0 to 3) := "0000";         -- kq_sb's registered writes
  signal kw_a_q    : kw_a_t := (others => (others => '0'));
  signal kw_d_q    : kw_d_t := (others => (others => '0'));
  -- header unit: reads 5 words of a full half, decodes, S2, d*dx, dmin*dx
  type kq_hs_t is (KH_IDLE, KH_RD, KH_DEC, KH_DEC1, KH_DEC2, KH_S2, KH_A, KH_B, KH_BW);
  signal kq_hs     : kq_hs_t := KH_IDLE;
  signal kq_hh     : std_logic := '0';               -- half it works on
  signal kq_hi     : unsigned(4 downto 0) := (others => '0');
  signal kq_hb     : kq_hb_t := (others => x"00");
  signal kq_hok    : std_logic_vector(0 to 1) := "00";          -- half's header done
  signal kq_hsb    : unsigned(7 downto 0) := (others => '0');   -- its super-block in the row
  signal kq_s2acc  : signed(31 downto 0) := (others => '0');
  type kq_sc2_t is array (0 to 1) of kq_sc16_t;
  type kq_m2_t is array (0 to 1) of kq_m16_t;
  type kq_w2_t is array (0 to 1) of unsigned(31 downto 0);
  type kq_i2_t is array (0 to 1) of signed(31 downto 0);
  signal kq_sc     : kq_sc2_t := (others => (others => (others => '0')));
  signal kq_m      : kq_m2_t := (others => (others => (others => '0')));
  signal kq_a, kq_b : kq_w2_t := (others => (others => '0'));  -- d*dx, dmin*dx
  signal kq_s2     : kq_i2_t := (others => (others => '0'));
  signal kq_dmin16 : unsigned(15 downto 0) := (others => '0');
  -- K reader and passes
  signal kq_rh     : std_logic := '0';               -- half the lanes read
  signal kq_kr     : std_logic := '0';               -- the K reader feeds the lanes
  signal kq_wo     : unsigned(7 downto 0) := (others => '0');   -- a block's first byte
  signal kq_dsh    : unsigned(1 downto 0) := "00";   -- d / 2^kq_dsh (kq_dscale)
  signal kq_d32    : unsigned(31 downto 0) := (others => '0');
  -- IQ front end (the codebook formats): a pass's 32 weights decoded into
  -- iq_buf ahead of the lanes, which take it as they take an unpacked
  -- block; the K tail does the rest.  Per pass: its sign / scale word (iq_a)
  -- and high-index-bits word (iq_b) through the K reader's ports, then its
  -- index words streamed, one 4-weight step a cycle: S1 the codebook
  -- address and 4 signs, S2 the ROM read, S3 its output register, S4 the
  -- 4 values with their signs into iq_buf
  type iq_st_t is (IQ_IDLE, IQ_A1, IQ_A2, IQ_RUN);
  signal iq_st     : iq_st_t := IQ_IDLE;
  signal iq_on     : std_logic := '0';
  signal iq3       : std_logic := '0';               -- IQ3: 4 values an index
  signal iq_xxs    : std_logic := '0';               -- scale in iq_a (IQ2_XXS, IQ3_XXS)
  signal iq_ks     : std_logic := '0';               -- 7 sign bits + parity (not IQ2_S, IQ3_S)
  signal iq_2w     : std_logic := '0';               -- two index words a pass
  signal iq_u16    : std_logic := '0';               -- IQ2_XS: 9-bit index, 7 signs in 16
  signal iq_hb     : std_logic := '0';               -- index high bits in iq_b (IQ2_S, IQ3_S)
  signal iq_base   : unsigned(1 downto 0) := "00";   -- codebook: 0, 1 (512) or 2 (1024)
  signal iq_h      : std_logic := '0';               -- half the front end reads
  signal iq_p      : unsigned(2 downto 0) := (others => '0');   -- its pass
  signal iq_t      : unsigned(2 downto 0) := (others => '0');   -- step in S1
  signal iq_iw     : unsigned(5 downto 0) := (others => '0');   -- first index word
  signal iq_a      : unsigned(31 downto 0) := (others => '0');
  signal iq_q8     : unsigned(7 downto 0) := (others => '0');   -- the pass's qh byte
  signal iq_v1, iq_v2, iq_v3 : std_logic := '0';
  signal iq_t1, iq_t2, iq_t3 : unsigned(2 downto 0) := (others => '0');
  signal iq_sg1, iq_sg2, iq_sg3 : std_logic_vector(3 downto 0) := (others => '0');
  signal iq_hf1, iq_hf2, iq_hf3 : std_logic := '0';  -- IQ2: values 4 .. 7 of the 8
  signal iq_ra2    : unsigned(10 downto 0) := (others => '0');
  signal iq_ra3    : unsigned(9 downto 0) := (others => '0');
  signal iq2_rom   : iq2_grid_t := IQ2_GRID;
  signal iq3_rom   : iq3_grid_t := IQ3_GRID;
  attribute rom_style of iq2_rom, iq3_rom : signal is "block";
  signal iq2_w, iq2_q : unsigned(15 downto 0) := (others => '0');
  signal iq3_w, iq3_q : unsigned(11 downto 0) := (others => '0');
  signal iq_buf    : qw32_t := (others => (others => '0'));
  signal iq_full   : std_logic := '0';
  signal kq_p      : unsigned(2 downto 0) := (others => '0');   -- pass (32 weights)
  signal kq_dq     : signed(8 downto 0) := (others => '0');  -- (DEQROW's q)
  signal kq_rd_q   : kq_rd_t := (la => (others => '0'), ha => (others => '0'),
                                 sl => "000", sh => "000", ml => x"0", mh => "00",
                                 wl => "000", off => (others => '0'), wr => '0', tb => '0');
  signal kq_la, kq_ha : unsigned(6 downto 0) := (others => '0');  -- half & word
  -- integer tail: S1 = sum of sc * (16-weight sums), per super-block
  signal kq_lo     : signed(31 downto 0) := (others => '0');   -- the pass's first 16
  signal kq_c1, kq_c2, kq_c1last, kq_c2last : std_logic := '0';   -- (pass of S1)
  signal kq_tlo, kq_thi : signed(31 downto 0) := (others => '0');
  signal kq_sclo, kq_schi : signed(7 downto 0) := (others => '0');
  signal kq_plo, kq_phi : signed(31 downto 0) := (others => '0');
  signal kq_s1     : signed(31 downto 0) := (others => '0');
  signal kq_c1h, kq_c2h : std_logic := '0';                    -- (the half)
  -- per super-block: F32(S1), F32(S2) (RNE), then t1 = S1f * a, t2 = S2f * b
  type kq_fs_t is (KF_IDLE, KF_C1, KF_M1, KF_C2, KF_M2, KF_OUT);
  signal kq_fs     : kq_fs_t := KF_IDLE;
  signal kq_fh     : std_logic := '0';
  signal kq_fs1, kq_fs2 : signed(31 downto 0) := (others => '0');
  signal kq_fi     : signed(31 downto 0) := (others => '0');   -- converter input
  signal kq_fgo, kq_fok : std_logic := '0';
  signal kq_fk     : unsigned(3 downto 0) := (others => '0');
  signal kq_fabs, kq_fm : unsigned(31 downto 0) := (others => '0');
  signal kq_fneg, kq_fz : std_logic := '0';
  signal kq_fp     : unsigned(4 downto 0) := (others => '0');
  signal kq_fres   : unsigned(31 downto 0) := (others => '0');
  signal kq_t1, kq_t2 : unsigned(31 downto 0) := (others => '0');
  signal kq_fsb    : unsigned(7 downto 0) := (others => '0');   -- term's super-block
  signal kq_fa, kq_fb : unsigned(31 downto 0) := (others => '0');
  signal kq_ga     : std_logic := '0';               -- header: d*dx is in
  -- header word list (kq_hword), set per GEMV; kq_hwl shifts through it
  type kq_hw_t is array (0 to 4) of unsigned(5 downto 0);
  signal kq_hwc, kq_hwl : kq_hw_t := (others => (others => '0'));
  signal kq_d16    : unsigned(15 downto 0) := (others => '0');
  -- the header word kq_hwl(0) of half kq_hh, registered (one read port for
  -- the GEMV header unit and DEQROW)
  signal kq_hrd    : unsigned(31 downto 0) := (others => '0');
  -- S2 pipeline: m and the x sum, their product
  signal kq_s2m    : unsigned(5 downto 0) := (others => '0');
  signal kq_s2b    : signed(11 downto 0) := (others => '0');
  signal kq_s2p    : signed(18 downto 0) := (others => '0');
  signal kq_s2v, kq_s2pv : std_logic := '0';
  -- reader: the pass's parameters (kq_rd of kq_p, a cycle behind it: kq_pchg
  -- says kq_p moved last cycle), the words read a cycle ahead of the lanes
  signal kq_rdn    : kq_rd_t := (la => (others => '0'), ha => (others => '0'),
                                 sl => "000", sh => "000", ml => x"0", mh => "00",
                                 wl => "000", off => (others => '0'), wr => '0', tb => '0');
  signal kq_pchg, kq_pre : std_logic := '0';
  signal kq_lb     : unsigned(5 downto 0) := (others => '0');   -- (wrap: the pass's base,
  signal kq_lc     : unsigned(1 downto 0) := (others => '0');   -- and the word in it)
  signal kq_wl_q, kq_wh_q : unsigned(31 downto 0) := (others => '0');
  -- S1: the two products' sum, then the accumulation
  signal kq_c3, kq_c3last, kq_c3h : std_logic := '0';
  signal kq_pp     : signed(31 downto 0) := (others => '0');
  -- term stage (second FP unit): term = F32(isum) * scale
  signal tm_busy   : std_logic := '0';
  signal tm_blk    : unsigned(7 downto 0) := (others => '0');
  signal f2_term   : std_logic := '0';      -- (unused)
  signal th_v      : std_logic := '0';      -- finished term waiting for the tail
  signal th_val    : unsigned(31 downto 0) := (others => '0');
  signal th_blk    : unsigned(7 downto 0) := (others => '0');
  -- tail input (main FSM: the accumulate)
  signal tl_full   : std_logic := '0';
  signal tl_term   : unsigned(31 downto 0) := (others => '0');
  signal tl_blk    : unsigned(7 downto 0) := (others => '0');
  -- K-quants: the super-block's second term (dmin part), subtracted from
  -- tl_term by the tail first (kq_min); tl_sub: done for this tl_term
  signal tl_term2  : unsigned(31 downto 0) := (others => '0');
  signal tl_sub    : boolean := false;
  signal g_nbt     : unsigned(7 downto 0) := (others => '0');  -- tail terms per row
  -- second FP unit: each block's term; third: the next block's scale
  signal fpu2_start, fpu2_done : std_logic := '0';
  signal fpu2_a, fpu2_b, fpu2_res : unsigned(31 downto 0) := (others => '0');
  signal fpu3_start, fpu3_done : std_logic := '0';
  signal fpu3_a, fpu3_b, fpu3_res : unsigned(31 downto 0) := (others => '0');
  -- Two products from a single 8-bit serial multiplier: the existing
  -- code intentionally uses only 20 low bits for byte-span calculation,
  -- but all 32 bits for the streamed block count.  Keep BOTH semantics.
  signal g_mul_nb : unsigned(7 downto 0) := (others => '0');
  signal g_mul_a32, g_mul_p32 : unsigned(31 downto 0) := (others => '0');
  signal g_mul_a28, g_mul_p28 : unsigned(27 downto 0) := (others => '0');
  signal g_rows, g_r : unsigned(31 downto 0) := (others => '0');
  signal g_end, g_last : boolean := false;     -- g_r = g_rows, g_r + 1 = g_rows
  signal g_nb, gblk : unsigned(7 downto 0) := (others => '0');
  -- Float GEMV (F32, F16, BF16 weights): the float lane (ssnail_hw.dot8).
  -- A weight a cycle from the word FIFO (F32: one per two words), times
  -- x (xf, F32, filled with the quantised copy's pass) through the
  -- pipelined multiplier, product i into partial sum i mod 8 (fl_p)
  -- through the pipelined adder, whose latency (8) brings each partial
  -- back just as its next product comes (fa_r bypassed into it); at a
  -- row's end, the partials combined by the same adder, and the row's sum
  -- to the tail as the row's only term
  signal fl_on, fl_f32, fl_bf : std_logic := '0';
  -- ... and ATTN's output pass (fl_ax): out[d] = out[d] + w_t * v_t[d]
  -- through the same units (row t's w_t from fl_wq, one row ahead, by the
  -- FSM), sequential over t for each d: the same d comes back a row later
  signal fl_ax     : std_logic := '0';
  signal fl_n      : unsigned(12 downto 0) := (others => '0');   -- row length
  signal fl_cz     : boolean := true;                            -- fl_c = 0
  signal fl_first  : std_logic := '0';                           -- row 0 (out starts at +0)
  signal fl_short  : boolean := false;                           -- rows too short to follow
  signal fl_wq, fl_ws, fl_b1, fl_b2 : unsigned(31 downto 0) := (others => '0');
  signal fl_wv     : std_logic := '0';
  signal fl_bm     : unsigned(31 downto 0) := (others => '0');   -- the multiplier's b
  signal ov_ra     : unsigned(7 downto 0) := (others => '0');    -- outv's read address
  signal g2_ret    : core_state_t := G2_WAIT;                    -- after G2_D3
  type xf_t is array (0 to 4095) of unsigned(31 downto 0);
  signal xf : xf_t := (others => (others => '0'));
  attribute ram_style of xf : signal is "block";
  type fl_st_t is (FL_RUN, FL_ROWEND, FL_AXW, FL_DRAIN, FL_WAITC, FL_DONE);
  -- the combine unit (its own adder): a finished row's bank of partials,
  -- once its last sums are in (18 cycles), to ((p0 + p1) + (p2 + p3)) +
  -- ((p4 + p5) + (p6 + p7)), the bank back to -0, the sum to the tail; the
  -- lane meanwhile adds the next row into the other bank (fl_bk)
  type cb_st_t is (CB_IDLE, CB_WAIT, CB_P, CB_W1, CB_Q, CB_W2, CB_S, CB_W3, CB_OUT);
  signal cb_st     : cb_st_t := CB_IDLE;
  signal cb_bk, fl_bk : std_logic := '0';
  signal cb_cnt    : unsigned(4 downto 0) := (others => '0');
  signal fc_rv     : std_logic := '0';
  signal fc_r      : unsigned(31 downto 0) := (others => '0');
  signal fc_rtag   : unsigned(6 downto 0) := (others => '0');
  signal fl_st     : fl_st_t := FL_DONE;
  signal fl_skip   : unsigned(1 downto 0) := "00";               -- words before the matrix
  signal fl_c      : unsigned(12 downto 0) := (others => '0');   -- column
  signal fl_cl     : boolean := false;                           -- fl_c + 1 = n0
  signal fl_k      : unsigned(2 downto 0) := (others => '0');   -- partial
  signal fl_tg1, fl_tg2 : unsigned(9 downto 0) := (others => '0');   -- (GEMV: the partial; ATTN: row 0, d)
  signal fl_rr     : unsigned(31 downto 0) := (others => '0');   -- rows still to issue
  signal fl_rl     : boolean := false;                           -- fl_rr = 1
  signal fl_lo     : unsigned(15 downto 0) := (others => '0');
  signal fl_hv     : std_logic := '0';
  signal fl_v1, fl_v2 : std_logic := '0';
  signal fl_raw1   : unsigned(31 downto 0) := (others => '0');
  signal fl_xa     : unsigned(11 downto 0) := (others => '0');
  signal fl_w2, xf_q : unsigned(31 downto 0) := (others => '0');
  signal fl_cnt    : unsigned(4 downto 0) := (others => '0');
  type f16x_t is array (0 to 15) of unsigned(31 downto 0);
  signal fl_p      : f16x_t := (others => x"80000000");          -- 2 banks of 8
  type f4_t is array (0 to 3) of unsigned(31 downto 0);
  signal fl_q      : f4_t := (others => (others => '0'));
  signal fl_s0, fl_s1, fl_res : unsigned(31 downto 0) := (others => '0');
  signal fm_rv, fa_v, fa_rv, cb_v : std_logic := '0';
  signal fm_r, fa_a, fa_b, fa_r, cb_a, cb_b : unsigned(31 downto 0) := (others => '0');
  signal fm_rtag   : unsigned(9 downto 0) := (others => '0');
  signal fa_tag, fa_rtag : unsigned(9 downto 0) := (others => '0');
  signal cb_tag    : unsigned(6 downto 0) := (others => '0');
  signal g_j, g_k  : unsigned(5 downto 0) := (others => '0');
  signal g_amax    : unsigned(30 downto 0) := (others => '0');
  signal g_d, g_id, g_scale, g_accv, g_val : unsigned(31 downto 0) := (others => '0');
  signal g_isum    : signed(31 downto 0) := (others => '0');
  signal g_addz, g_f16 : std_logic := '0';
  signal out_loaded : std_logic := '0';
  signal out_block : unsigned(27 downto 8) := (others => '0');

  -- Register files and resolved operands
  type rfile32_t is array (0 to 15) of unsigned(31 downto 0);
  type rfile28_t is array (0 to 15) of unsigned(27 downto 0);
  signal rf_r : rfile32_t := (others => (others => '0'));
  signal rf_a : rfile28_t := (others => (others => '0'));
  signal n0, n1, n2 : unsigned(31 downto 0) := (others => '0');
  signal ea_x, ea_y : unsigned(27 downto 0) := (others => '0');
  signal opr_a, opr_b : unsigned(31 downto 0) := (others => '0');  -- R[a], R[b]
  -- Decode conditions, registered.  n0 and n1 change only in SETN, long
  -- before the next C_DECODE, so their flags simply follow them; the
  -- operand compares are made in C_RESOLVE, alongside opr_a and opr_b.
  signal n0_z, n0_one, n0_big, n1_z, n1_big : boolean := false;
  signal opr_a_z, opr_eq, opr_lt : boolean := false;
  signal br_taken  : std_logic := '0';
  -- LEA: iterative multiply R[b] * Z
  signal mul_acc   : unsigned(27 downto 0) := (others => '0');
  signal mul_m     : unsigned(27 downto 0) := (others => '0');
  signal mul_z     : unsigned(31 downto 0) := (others => '0');
  signal mul_zz    : boolean := true;                            -- mul_z = 0
  -- LDR / STR
  signal mem_is_store : std_logic := '0';
  signal str_active   : std_logic := '0';
  signal str_k        : unsigned(1 downto 0) := "00";

  -- COPY state
  signal cp_src, cp_dst : unsigned(27 downto 0) := (others => '0');
  signal cp_remaining   : unsigned(15 downto 0) := (others => '0');
  signal cp_zero        : boolean := true;    -- cp_remaining = 0
  signal cp_chunk       : unsigned(8 downto 0) := (others => '0');

  -- Load port, core side
  signal lp_wr_s1, lp_wr_s2, lp_wr_last : std_logic := '0';
  signal lp_blk_done  : std_logic := '0';   -- the ring now holds a whole new block
  signal lp_wr_idle   : boolean;            -- no data byte on its way into the ring
  signal lp_cmt_s1, lp_cmt_s2, lp_cmt_last : std_logic := '0';
  signal lp_pending   : unsigned(2 downto 0) := (others => '0');  -- complete blocks waiting
  signal lp_drain     : unsigned(27 downto 0) := (others => '0'); -- next address to write
  -- lp_drain = lp_cmt_end: set with every write of lp_drain, and
  -- recomputed every cycle for lp_cmt_end (written on the cpuclock side,
  -- and used only once its commit toggle has been synchronised)
  signal lp_at_cmt : boolean := true;
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

  -- Input burst buffer: one writer (read-response port), unlike the old
  -- buf which combined read responses and multiword arithmetic writes.
  type buf_t is array (0 to 127) of unsigned(15 downto 0);
  signal buf_in : buf_t := (others => x"0000");
  signal buf_widx : unsigned(6 downto 0) := (others => '0');  -- fill index
  -- Vector engine operand buffers, indexed by address mod 256
  signal bufx, bufy, bufb : buf_t := (others => x"0000");
  signal cap_sel : unsigned(1 downto 0) := "00";   -- read data goes to: buf_in, bufx, bufy, bufb
  -- capture stage: one word on its way into buf_in / bufx / bufy / bufb
  signal cap_we, cap_cnt : std_logic := '0';
  signal cap_d   : unsigned(15 downto 0) := x"0000";
  signal cap_idx : unsigned(6 downto 0) := (others => '0');
  signal cap_dst : unsigned(1 downto 0) := "00";
  type ld_w_t is array (0 to 3) of unsigned(15 downto 0);
  signal ld_w : ld_w_t := (others => x"0000");      -- words 0-3 of a load (LDR)
  signal buf_ridx : unsigned(6 downto 0) := (others => '0');  -- drain index
  signal wdata_r  : unsigned(15 downto 0) := x"0000";

  -- Output burst write packet. One transaction per core clock, with 1/2/4
  -- consecutive 16-bit words. The output buffer has one physical write
  -- per bank, and no writes from the read-response path.
  signal ob_wr_en   : std_logic := '0';
  signal ob_wr_base : unsigned(6 downto 0) := (others => '0');
  signal ob_wr_mask : std_logic_vector(3 downto 0) := (others => '0');
  signal ob_wr_data : unsigned(63 downto 0) := (others => '0');
  -- the packer's outputs, before the register stage
  signal ob_c_en   : std_logic;
  signal ob_c_base : unsigned(6 downto 0);
  signal ob_c_mask : std_logic_vector(3 downto 0);
  signal ob_c_data : unsigned(63 downto 0);
  signal ob_rd_addr : unsigned(6 downto 0);
  signal ob_rd_data : unsigned(15 downto 0);

  attribute ram_style of buf_in : signal is "distributed";
  attribute ram_style of bufx, bufy, bufb : signal is "distributed";

  attribute async_reg : string;
  attribute async_reg of go_s1, go_s2, abort_s1, abort_s2 : signal is "true";
  attribute async_reg of sync_s1, sync_s2, step_s1, step_s2 : signal is "true";
  attribute async_reg of pub_tgl_s1, pub_tgl_s2 : signal is "true";
  attribute async_reg of lp_wr_s1, lp_wr_s2, lp_cmt_s1, lp_cmt_s2 : signal is "true";
  attribute async_reg of lp_ack_s1, lp_ack_s2, lp_cack_s1, lp_cack_s2 : signal is "true";
  attribute async_reg of lp_err_s1, lp_err_s2 : signal is "true";

  -- as_flags for each possible (skipped, shifted-in) count of a cycle, and
  -- for each skipped count when the block completes
  type asf_t is array (0 to 3, 0 to 3) of std_logic_vector(7 downto 0);
  type asf4_t is array (0 to 3) of std_logic_vector(7 downto 0);

  -- Block assembler thresholds for as_skip = sk, as_rem = rm (see as_f)
  function as_flags(sk, rm : integer) return std_logic_vector is
    variable f : std_logic_vector(7 downto 0) := (others => '0');
  begin
    if sk >= 1 then f(0) := '1'; end if;
    if sk >= 2 then f(1) := '1'; end if;
    if sk >= 3 then f(2) := '1'; end if;
    if sk + rm >= 2 then f(3) := '1'; end if;
    if sk + rm >= 3 then f(4) := '1'; end if;
    if rm = 1 then f(5) := '1'; end if;
    if rm = 2 then f(6) := '1'; end if;
    if rm = 3 then f(7) := '1'; end if;
    return f;
  end function;

  -- as_flags(skip - si, rem - wi) without arithmetic on the path: rge(t)
  -- is rem >= t and req(t) is rem = t (constant compares of rem), so each
  -- flag is a pick of one of them by skip
  function as_flags_t(skip : unsigned(2 downto 0); si, wi : integer;
                      rge, req : std_logic_vector(0 to 15)) return std_logic_vector is
    variable f : std_logic_vector(7 downto 0) := (others => '0');
    variable sk, t : integer;
  begin
    for sv in 0 to 7 loop
      if to_integer(skip) = sv then
        sk := sv - si;
        if sk >= 1 then f(0) := '1'; end if;
        if sk >= 2 then f(1) := '1'; end if;
        if sk >= 3 then f(2) := '1'; end if;
        t := 2 - sk + wi;                   -- sk + rem - wi >= 2
        if t <= 0 then f(3) := '1'; else f(3) := rge(t); end if;
        t := 3 - sk + wi;                   -- sk + rem - wi >= 3
        if t <= 0 then f(4) := '1'; else f(4) := rge(t); end if;
        f(5) := req(1 + wi);
        f(6) := req(2 + wi);
        f(7) := req(3 + wi);
      end if;
    end loop;
    return f;
  end function;

  function min9(a, b : unsigned(8 downto 0)) return unsigned is
  begin
    if a < b then return a; else return b; end if;
  end function;

begin

  output_buffer0 : entity work.ssnail_output_buffer
    port map (
      clk     => clock162,
      wr_en   => ob_wr_en,
      wr_base => ob_wr_base,
      wr_mask => ob_wr_mask,
      wr_data => ob_wr_data,
      rd_addr => ob_rd_addr,
      rd_data => ob_rd_data
    );

  -- Shared write arbitration/packing for all arithmetic output producers.
  -- Each cstate writes at most four *consecutive* halfwords. There is no
  -- loss of write-response data: that uses buf_in, a different physical RAM.
  -- The packed write is registered, so it reaches the buffer one edge after
  -- its cstate.  The buffer is only read by the burst writer, which starts
  -- several states after the last store (C_WR_DEC, C_WR_ISSUE, then the
  -- LUMP data request), so nothing reads a halfword in the cycle it lands.
  process (cstate, o16, pz, v_i, fpu_r, d_val, g_val, g_f16,
           rp0, outv, at_i, at_iend, ov_ra) is
    variable byte_index : unsigned(7 downto 0);
  begin
    ob_c_en   <= '0';
    ob_c_base <= (others => '0');
    ob_c_mask <= (others => '0');
    ob_c_data <= (others => '0');
    byte_index := (others => '0');
    case cstate is
      when V_ELST =>
        if o16 = '1' then
          byte_index := pz(7 downto 0) + (v_i(6 downto 0) & "0");
          ob_c_base <= byte_index(7 downto 1);
          ob_c_mask <= "0001";
        else
          byte_index := pz(7 downto 0) + (v_i(5 downto 0) & "00");
          ob_c_base <= byte_index(7 downto 1);
          ob_c_mask <= "0011";
        end if;
        ob_c_data(31 downto 0) <= fpu_r;
        ob_c_en <= '1';
      when D_STORE =>
        ob_c_base <= pz(7 downto 1);
        ob_c_mask <= "0011";
        ob_c_data(31 downto 0) <= d_val;
        ob_c_en <= '1';
      when G_OUT4 =>
        ob_c_base <= pz(7 downto 1);
        if g_f16 = '1' then
          ob_c_mask <= "0001";
        else
          ob_c_mask <= "0011";
        end if;
        ob_c_data(31 downto 0) <= g_val;
        ob_c_en <= '1';
      when E_R6 =>
        byte_index := pz(7 downto 0) + (v_i(5 downto 0) & "00");
        ob_c_base <= byte_index(7 downto 1);
        ob_c_mask <= "1111";
        ob_c_data <= fpu_r & rp0;
        ob_c_en <= '1';
      when A_WR =>
        if not at_iend then                -- at_i /= at_hd
          ob_c_base <= pz(7 downto 1);
          ob_c_mask <= "0011";
          ob_c_data(31 downto 0) <= outv(to_integer(ov_ra));   -- (ov_ra = at_i here)
          ob_c_en <= '1';
        end if;
      when others => null;
    end case;
  end process;

  process (clock162) is
  begin
    if rising_edge(clock162) then
      ob_wr_en   <= ob_c_en;
      ob_wr_base <= ob_c_base;
      ob_wr_mask <= ob_c_mask;
      ob_wr_data <= ob_c_data;
    end if;
  end process;

  -- Output burst read address is exactly the former buf expression.
  ob_rd_addr <= mw_idx + mw_k(6 downto 0);

  ---------------------------------------------------------------------------
  -- FastIO register reads (asynchronous, as in buffereduart, to avoid wait
  -- states)
  ---------------------------------------------------------------------------
  process (fastio_read, ssnail_cs, fastio_addr, job_ptr, cpu_pc, cpu_busy,
           cpu_done, cpu_err, start_pending, irq_pend_done, irq_en_done,
           hr_size_mb, sd_base_mb, sd_size_mb, hr_base_mb, lp_ptr, lp_ready, lp_err_s2,
           wd_fired, sd_out, dbg_words,
           instr) is
  begin
    if fastio_read = '1' and ssnail_cs = '1' then
      case fastio_addr(4 downto 0) is
        when "00000" => fastio_rdata <= SSNAIL_ID;
        when "00001" => fastio_rdata <= SSNAIL_VERSION;
        when "00010" =>
          if has_sdram then fastio_rdata <= x"03"; else fastio_rdata <= x"01"; end if;
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
        when "00111" =>
          -- debug: 7 = watchdog ended the last job, 6-4 = SDRAM commands
          -- outstanding, 3-0 = words the last instruction fetch received
          fastio_rdata <= wd_fired & sd_out & dbg_words;
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
        when "10011" => fastio_rdata <= hr_base_mb;
        when "10100" => fastio_rdata <= lp_ptr(7 downto 0);
        when "10101" => fastio_rdata <= lp_ptr(15 downto 8);
        when "10110" => fastio_rdata <= lp_ptr(23 downto 16);
        when "10111" =>
          fastio_rdata <= lp_ready & lp_err_s2 & "00" & lp_ptr(27 downto 24);
        -- Debug: the first 8 bytes of the last instruction fetched, as
        -- SSNAIL saw them (kept after a HALT or an error).  Read only.
        when "11000" => fastio_rdata <= instr(7 downto 0);
        when "11001" => fastio_rdata <= instr(15 downto 8);
        when "11010" => fastio_rdata <= instr(23 downto 16);
        when "11011" => fastio_rdata <= instr(31 downto 24);
        when "11100" => fastio_rdata <= instr(39 downto 32);
        when "11101" => fastio_rdata <= instr(47 downto 40);
        when "11110" => fastio_rdata <= instr(55 downto 48);
        when "11111" => fastio_rdata <= instr(63 downto 56);
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
          when "10011" => if idle then hr_base_mb <= fastio_wdata; end if;
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
            -- Data byte: the core puts it in the ring at its destination
            -- address (and, if it completes a 256-byte block, takes the block)
            lp_wr_addr <= lp_ptr(9 downto 0);
            lp_wr_data <= fastio_wdata;
            lp_wr_tgl <= not lp_wr_tgl;
            lp_ptr <= lp_ptr + 1;
            if lp_ptr(7 downto 0) = x"FF" then
              lp_wr_blk <= '1';
              lp_out <= lp_out + 1;
            else
              lp_wr_blk <= '0';
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
        if idle then
          hr_size_mb <= to_unsigned(8, 8);
          sd_base_mb <= sd_default(true, has_sdram);
          sd_size_mb <= sd_default(false, has_sdram);
          hr_base_mb <= hr_default(has_sdram);
        end if;
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
    variable span9 : unsigned(8 downto 0);
    variable hr_issue, sd_issue : std_logic;
    variable lp_inc, lp_dec : std_logic;
    variable st_al, en_al : unsigned(27 downto 0);
    variable room, vlen : unsigned(31 downto 0);
    variable vlen8, room8 : unsigned(7 downto 0);
    variable a0, a1, a2 : unsigned(27 downto 0);
    variable pf_go : boolean;                   -- read the operands at pf_x/y/b
    variable pf_x, pf_y, pf_b : unsigned(7 downto 0);
    variable pf_i : unsigned(7 downto 0);       -- ... and the v_i that goes with them
    variable pf_ok : boolean;
    variable pa_x, pa_y, pa_b : w7x8_t;         -- read-ahead word addresses (0..3 used)
    variable vck_x, vck_y : unsigned(7 downto 0);  -- (simulation checks only)
    variable xv, lo, hi : unsigned(31 downto 0);
    variable ra, rb : unsigned(31 downto 0);     -- R[a], R[b] in C_RESOLVE
    variable ti : integer range 0 to 1023;
    variable wd : unsigned(15 downto 0);
    variable q : signed(31 downto 0);
    variable qw : signed(8 downto 0);
    variable qwv : signed(8 downto 0);
    variable qxv : signed(7 downto 0);
    variable lsum : signed(31 downto 0);
    variable jj, nav, sk : integer range 0 to 63;
    variable as_c, as_s, as_w : integer range 0 to 3;
    variable asf_c : asf_t;
    variable asf_full : asf4_t;
    variable rge, req : std_logic_vector(0 to 15);
    variable avb : grp_t;
    variable popw : boolean;
    variable wf_arr, wf_pop : boolean;
    variable nh, ns : unsigned(2 downto 0);
    variable wv : unsigned(15 downto 0);
    variable rq_push : boolean;
    variable rq_push_tag : std_logic;
    variable rq_push_cnt : unsigned(7 downto 0);
    variable sr_inflight_inc : unsigned(8 downto 0);
    variable sr_inflight_dec, tl_full_clr : std_logic;
    variable tl_free : boolean;
    variable fv : unsigned(31 downto 0);
    variable i2f_p : integer range 0 to 23;
    variable i2f_m : unsigned(23 downto 0);
    variable v28 : unsigned(27 downto 0);
    variable kb_pos : unsigned(8 downto 0);
    variable kb_ln : integer range 0 to 3;
    variable kb_wd : unsigned(6 downto 0);
    variable kwl, kwh : unsigned(31 downto 0);
    variable kf_r : unsigned(24 downto 0);
    variable kf_p : integer range 0 to 31;
    variable kc : kq_rd_t;
    variable ib : unsigned(7 downto 0);
    variable iu : unsigned(15 downto 0);
    variable s7 : unsigned(6 downto 0);
    variable s8 : unsigned(7 downto 0);
    variable iv : unsigned(5 downto 0);
    variable ic2 : unsigned(1 downto 0);
    variable ic3 : unsigned(2 downto 0);
    variable row_end : boolean;
    variable xe : integer range -127 to 128;
    variable xfx : unsigned(31 downto 0);
    variable lane_start, lane_take : boolean;
    variable acc32, qs32 : signed(31 downto 0);
    variable xw_we : boolean;
    variable xw_a : unsigned(11 downto 0);
    variable xw_d : unsigned(31 downto 0);
    -- sarr's one write port: A_S_SC or the softmax engine
    variable sw_we : boolean;
    variable sw_a : unsigned(9 downto 0);
    variable sw_d : unsigned(31 downto 0);
    variable sa : unsigned(9 downto 0);
    variable nb, nm : integer range 0 to 3;
    variable sxf : unsigned(1 downto 0);
    variable sxe : integer range 0 to 255;
    variable sxr : unsigned(31 downto 0);
    -- kq_sb's one write port per byte lane: the assembler (GEMV) or D_FETCH
    variable kw_we : std_logic_vector(0 to 3);
    variable kw_a : kw_a_t;
    variable kw_d : kw_d_t;
    variable wb : unsigned(7 downto 0);
    -- the next state, with its registered decodes
    procedure go(s : core_state_t) is
    begin
      cstate <= s;
      cs_el0 <= s = V_EL0;
      cs_r6 <= s = E_R6;
      cs_pf <= s = V_EL0 or s = V_EL or s = V_ELST or s = E_ACC or s = E_ACC2
               or s = E_R6;
      cs_t3 <= s = G2_T3;
    end procedure;
  begin
    if rising_edge(clock162) then
      assert cs_el0 = (cstate = V_EL0) and cs_r6 = (cstate = E_R6)
        and cs_pf = (cstate = V_EL0 or cstate = V_EL or cstate = V_ELST
                     or cstate = E_ACC or cstate = E_ACC2 or cstate = E_R6)
        report "SSNAIL: stale cs_el0 / cs_r6 / cs_pf" severity failure;
      assert cs_t3 = (cstate = G2_T3) report "SSNAIL: stale cs_t3" severity failure;
      assert out_z = (hr_out = 0 and sd_out = 0) report "SSNAIL: stale out_z" severity failure;
      wf_arr := false;
      wf_pop := false;
      kw_we := "0000";
      lane_start := false; lane_take := false;
      xw_we := false; xw_a := (others => '0'); xw_d := (others => '0');
      sw_we := false; sw_a := (others => '0'); sw_d := (others => '0');
      kq_fset <= '0';
      kw_a := (others => (others => '0'));
      kw_d := (others => (others => '0'));
      hr_issue := '0';
      pf_go := false;
      pf_x := vix; pf_y := viy; pf_b := vib;
      pf_i := v_i;
      sd_issue := '0';
      lp_inc := '0';
      lp_dec := '0';
      fpu_start <= '0';
      fpu2_start <= '0';
      fpu3_start <= '0';
      rq_push := false;
      rq_push_tag := '0';
      rq_push_cnt := (others => '0');
      sr_inflight_inc := (others => '0');
      sr_inflight_dec := '0';
      -- (G2_T3 frees the tail: from its registered decode, not cstate's)
      if cs_t3 then tl_full_clr := '1'; else tl_full_clr := '0'; end if;

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
        if mw_active = '1' then
          -- Vector output: word k of the burst, bytes enabled only within
          -- [lead, vend) relative to the burst start
          wdata_r <= ob_rd_data;
          if mw_k & '0' >= mw_lead and mw_k & '0' < mw_vend then
            wbe_r(0) <= '1';
          else
            wbe_r(0) <= '0';
          end if;
          if mw_k & '1' >= mw_lead and mw_k & '1' < mw_vend then
            wbe_r(1) <= '1';
          else
            wbe_r(1) <= '0';
          end if;
          mw_k <= mw_k + 1;
        elsif str_active = '1' then
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
          wdata_r  <= buf_in(to_integer(buf_ridx));
          wbe_r    <= "11";
          buf_ridx <= buf_ridx + 1;
        end if;
      end if;

      -- Load port: blocks completed in the ring, and commits
      lp_cmt_s1 <= lp_cmt_tgl; lp_cmt_s2 <= lp_cmt_s1;
      if lp_blk_done = '1' then
        lp_inc := '1';
      end if;

      -- Address decode of dec_addr, one cycle after it is set.
      -- HyperRAM: [$8000000, $8000000 + hr_size MB)
      -- SDRAM:    [sd_base MB, sd_base + sd_size MB)
      mb := dec_addr(27 downto 20);
      if mb >= c_hr_base and resize(mb, 9) < resize(c_hr_base, 9) + resize(c_hr_size, 9) then
        dec_ok    <= '1';
        dec_is_sd <= '0';
        dec_local <= resize(mb - c_hr_base, 7) & dec_addr(19 downto 0);
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

      -- Store incoming read data (capture stage registers: see below)
      cap_we <= '0';
      cap_cnt <= '0';
      cap_d <= rdata_r;
      cap_idx <= buf_widx;
      cap_dst <= cap_sel;
      if rvalid_r = '1' and g2 = '1' and rq_tag(to_integer(rq_r(1 downto 0))) = '1' then
        -- GEMV weight stream: into the word FIFO
        wf(to_integer(wf_w(7 downto 0))) <= rdata_r;
        wf_w <= wf_w + 1;
        wf_arr := true;
        sr_inflight_dec := '1';
        if rq_cnt(to_integer(rq_r(1 downto 0))) = 1 then
          rq_r <= rq_r + 1;
        else
          rq_cnt(to_integer(rq_r(1 downto 0))) <= rq_cnt(to_integer(rq_r(1 downto 0))) - 1;
        end if;
      elsif rvalid_r = '1' then
        if g2 = '1' then
          -- a non-stream read during GEMV (old outputs): count it off its tag
          if rq_cnt(to_integer(rq_r(1 downto 0))) = 1 then
            rq_r <= rq_r + 1;
          else
            rq_cnt(to_integer(rq_r(1 downto 0))) <= rq_cnt(to_integer(rq_r(1 downto 0))) - 1;
          end if;
        end if;
        if cstate = C_FETCH_WAIT then
          instr <= rdata_r & instr(127 downto 16);
        else
          cap_we <= '1';
          buf_widx <= buf_widx + 1;
        end if;
        cap_cnt <= '1';
      end if;
      -- Capture stage: the word reaches its buffer (and words_got counts
      -- it) one edge after rdata_r, so the buffers need not sit next to
      -- the read-data register.  Waits on words_got therefore still see
      -- every word written before they finish.
      if cap_we = '1' then
        if cap_dst = "01" then
          bufx(to_integer(cap_idx)) <= cap_d;
        elsif cap_dst = "10" then
          bufy(to_integer(cap_idx)) <= cap_d;
        elsif cap_dst = "11" then
          bufb(to_integer(cap_idx)) <= cap_d;
        else
          buf_in(to_integer(cap_idx)) <= cap_d;
          -- the first four words also go to ld_w, for LDR: buf_in then
          -- has only addressed reads and stays in LUT RAM
          if cap_idx(6 downto 2) = 0 then
            ld_w(to_integer(cap_idx(1 downto 0))) <= cap_d;
          end if;
        end if;
      end if;
      if cap_cnt = '1' then
        words_got <= words_got + 1;
        words_done <= words_got + 1 = words_expected;
      end if;
      if rerror_r = '1' and busy = '1' then
        err <= ERR_READ;
      end if;

      -- words_done, v_n_z and v_n_one are kept exact on every write
      assert words_done = (words_got = words_expected) report "SSNAIL: stale words_done" severity failure;
      assert v_n_z = (v_n = 0) and v_n_one = (v_n = 1) report "SSNAIL: stale v_n flags" severity failure;

      coeff_q <= coeff_word;

      -- DEQROW quantised element (see d_qv)
      if d_fmt = 8 then
        d_qv <= resize(signed(grp(2 + to_integer(d_j(4 downto 0)))), 32);
      elsif d_fmt = 39 then
        if d_j(4) = '0' then
          d_qv <= resize(e2m1x2(grp(1 + to_integer(d_j(3 downto 0)))(3 downto 0)), 32);
        else
          d_qv <= resize(e2m1x2(grp(1 + to_integer(d_j(3 downto 0)))(7 downto 4)), 32);
        end if;
      elsif d_fmt = 20 then
        if d_j(4) = '0' then
          d_qv <= resize(iq4v(grp(2 + to_integer(d_j(3 downto 0)))(3 downto 0)), 32);
        else
          d_qv <= resize(iq4v(grp(2 + to_integer(d_j(3 downto 0)))(7 downto 4)), 32);
        end if;
      elsif d_fmt = 6 then                          -- Q5_0: high bit, nibble
        if d_j(4) = '0' then
          d_qv <= resize(q5v(grp(2 + to_integer(d_j(4 downto 3)))(to_integer(d_j(2 downto 0))),
                              grp(6 + to_integer(d_j(3 downto 0)))(3 downto 0)), 32);
        else
          d_qv <= resize(q5v(grp(2 + to_integer(d_j(4 downto 3)))(to_integer(d_j(2 downto 0))),
                              grp(6 + to_integer(d_j(3 downto 0)))(7 downto 4)), 32);
        end if;
      elsif d_j(4) = '0' then
        d_qv <= resize(signed('0' & grp(2 + to_integer(d_j(3 downto 0)))(3 downto 0)), 32) - 8;
      else
        d_qv <= resize(signed('0' & grp(2 + to_integer(d_j(3 downto 0)))(7 downto 4)), 32) - 8;
      end if;

      lp_at_cmt <= lp_drain = lp_cmt_end;           -- (overridden where lp_drain is set)

      g_have_old <= out_loaded = '1' and pz(27 downto 8) = out_block;
      g_oldv <= buf_in(to_integer(pz(7 downto 1) + 1)) & buf_in(to_integer(pz(7 downto 1)));

      fsm_iss_q <= cstate = C_RD_DEC or cstate = C_RD_ISSUE
                   or cstate = C_WR_DEC or cstate = C_WR_ISSUE;

      -- SETN operand checks for C_DECODE (see n0_z)
      n0_z <= n0 = 0;
      ef_miss <= ld_valid = '0' or ef_addr(27 downto 8) /= ld_block;
      -- D_FETCH's: exact there, as ps and ld_block only change in D_FETCH's
      -- hit path (ps + 1, which leaves the block only through D_FETCH0) or
      -- before D_FETCH0
      ps_miss <= ld_valid = '0' or ps(27 downto 8) /= ld_block;
      n0_one <= n0 = 1;
      n0_big <= n0 > 4096;
      n1_z <= n1 = 0;
      n1_big <= n1 > 256;

      -- ARGMAX: first maximum, so replace only on strictly greater.  The
      -- result is read in AM_DONE, several states after the last element.
      am_v_q <= '0';
      if am_v_q = '1' then
        if am_first_q = '1' or flt(am_best, am_x_q) then
          am_best <= am_x_q;
          am_idx <= am_g_q;
        end if;
      end if;

      g_qlast <= gblk + 1 = g_nb;
      tl_last <= tl_blk + 1 = g_nbt;
      mr_end  <= mr_r = mr_rows;

      -- GEMV quantise |x| maximum, a cycle behind the reads (G_QFILL)
      qf_vld <= false;
      if qf_vld and qf_v > g_amax then
        g_amax <= qf_v;
      end if;

      -- Command acceptance: drop valid on the edge where ready is seen
      if hr_cmd_ready = '1' then hr_valid_i <= '0'; end if;
      if sd_cmd_ready = '1' then sd_valid_i <= '0'; end if;

      case cstate is
        when C_IDLE =>
          busy <= '0';
          -- Load port work comes first.  A chunk is [lp_drain, lp_end): a
          -- whole remaining block, or for a commit, whatever is left.
          if lp_pending /= 0
            or (lp_cmt_s2 /= lp_cmt_last and lp_wr_idle) then
            if lp_pending /= 0 then
              lp_end <= (lp_drain(27 downto 8) + 1) & x"00";
              en_al := (lp_drain(27 downto 8) + 1) & x"00";
              lp_is_commit <= '0';
            else
              lp_end <= lp_cmt_end;
              en_al := lp_cmt_end;
              lp_is_commit <= '1';
              if lp_cmt_clr = '1' and lp_at_cmt then      -- lp_drain = lp_cmt_end
                lp_error <= '0';
              end if;
            end if;
            assert lp_pending /= 0 or lp_at_cmt = (lp_drain = lp_cmt_end)
              report "SSNAIL: stale lp_at_cmt" severity failure;
            if lp_pending = 0 and lp_at_cmt then                -- lp_drain = lp_cmt_end
              -- Nothing (more) to flush: the commit takes effect
              lp_drain <= lp_cmt_new;
              lp_at_cmt <= lp_cmt_new = lp_cmt_end;
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
              c_hr_size <= hr_size_mb; c_hr_base <= hr_base_mb;
              c_sd_base <= sd_base_mb;
              c_sd_size <= sd_size_mb;
              go(C_LP_DECODE);
            end if;
          elsif go_s2 /= go_last or step_s2 /= step_last then
            c_hr_size <= hr_size_mb; c_hr_base <= hr_base_mb;
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
            wd_fired <= '0';
            abort_req <= '0';
            go(C_FETCH_SETUP);
          elsif sync_s2 /= sync_last then
            sync_last <= sync_s2;
            c_hr_size <= hr_size_mb; c_hr_base <= hr_base_mb;
            c_sd_size <= sd_size_mb;
            busy <= '1';
            cpu_sync <= '1';
            go(C_SYNC_ISSUE);
          end if;

        when C_FETCH_SETUP =>
          dec_addr <= pc;
          go(C_FETCH_DECODE);

        when C_FETCH_DECODE =>
          go(C_FETCH_ISSUE);     -- decode of pc completes now

        when C_FETCH_ISSUE =>
          if abort_req = '1' then
            err <= ERR_ABORTED;
            go(C_END);
          elsif pc(3 downto 0) /= "0000" then
            err <= ERR_ALIGNMENT;
            go(C_END);
          elsif dec_ok = '0' then
            err <= ERR_ADDRESS;
            go(C_END);
          else
            words_got <= (others => '0');
            words_expected <= to_unsigned(8, 8);
            words_done <= false;
            t_is_sd <= dec_is_sd;
            if dec_is_sd = '1' then
              sd_valid_i <= '1'; sd_cmd_op <= LUMP_OP_READ;
              sd_cmd_addr <= dec_local; sd_cmd_len <= to_unsigned(16, 9);
              sd_issue := '1';
            else
              hr_valid_i <= '1'; hr_cmd_op <= LUMP_OP_READ;
              hr_cmd_addr <= dec_local; hr_cmd_len <= to_unsigned(16, 9);
              hr_issue := '1';
            end if;
            go(C_FETCH_WAIT);
          end if;

        when C_FETCH_WAIT =>
          dbg_words <= words_got(3 downto 0);
          if words_done and rvalid_r = '0' then
            wd_cnt <= (others => '0');
            go(C_RESOLVE);
          elsif rvalid_r = '1' then
            wd_cnt <= (others => '0');
          elsif wd_cnt = x"FFFF" then
            wd_cnt <= (others => '0');
            wd_fired <= '1';
            err <= ERR_READ;
            go(C_END);
          else
            wd_cnt <= wd_cnt + 1;
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
          if instr(127) = '1' then
            ea_z <= rf_a(to_integer(instr(123 downto 120))) + resize(instr(119 downto 96), 28);
          else
            ea_z <= instr(123 downto 96);
          end if;
          if instr(11 downto 8) = x"F" then
            ra := (others => '0');
          else
            ra := rf_r(to_integer(instr(11 downto 8)));
          end if;
          if instr(19 downto 16) = x"F" then
            rb := (others => '0');
          else
            rb := rf_r(to_integer(instr(19 downto 16)));
          end if;
          opr_a <= ra;
          opr_b <= rb;
          opr_a_z <= ra = 0;
          opr_eq <= ra = rb;
          opr_lt <= ra < rb;
          go(C_DECODE);

        when C_DECODE =>
          go(C_DEC2);
          dec_next <= C_DECODE;                     -- (as if cstate were unchanged)
          -- MEANROWS set-up, for every instruction (only MEANROWS uses them),
          -- so the opcode and fault checks do not gate it
          mr_rows <= opr_a;
          mr_r <= to_unsigned(1, 32);
          mr_src_row <= ea_x;
          assert n0_z = (n0 = 0) and n0_big = (n0 > 4096) and n0_one = (n0 = 1)
            and n1_z = (n1 = 0) and n1_big = (n1 > 256)
            report "SSNAIL: stale n0/n1 flags" severity failure;
          assert opr_a_z = (opr_a = 0) and opr_eq = (opr_a = opr_b) and opr_lt = (opr_a < opr_b)
            report "SSNAIL: stale operand flags" severity failure;
          if err /= ERR_NONE then
            dec_next <= C_END;
          else
          case instr(7 downto 0) is
            when x"00" =>             -- NOP
              dec_next <= C_NEXT;
            when x"01" =>             -- HALT
              dec_next <= C_END;
            when x"02" =>             -- SYNC
              dec_next <= C_SYNC_ISSUE;
            when x"03" =>             -- COPY
              cp_src <= ea_x;
              cp_dst <= ea_y;
              cp_remaining <= instr(111 downto 96);
              cp_zero <= instr(111 downto 96) = 0;
              if ea_x(2 downto 0) /= "000" or ea_y(2 downto 0) /= "000"
                or instr(98 downto 96) /= "000" then
                err <= ERR_ALIGNMENT;
                dec_next <= C_END;
              else
                dec_next <= C_COPY_CALC;
              end if;
            when x"07" =>             -- SETN
              n0 <= instr(63 downto 32);
              n1 <= instr(95 downto 64);
              n2 <= instr(127 downto 96);
              dec_next <= C_NEXT;
            when x"08" =>             -- LI
              if instr(11 downto 8) /= x"F" then
                rf_r(to_integer(instr(11 downto 8))) <= instr(127 downto 96);
              end if;
              dec_next <= C_NEXT;
            when x"0B" =>             -- ADDI
              if instr(11 downto 8) /= x"F" then
                rf_r(to_integer(instr(11 downto 8))) <= opr_b + instr(127 downto 96);
              end if;
              dec_next <= C_NEXT;
            when x"0C" =>             -- LEA: A[a] = addr(X) + R[b] * Z
              mul_acc <= ea_x;
              mul_m <= opr_b(27 downto 0);
              mul_z <= instr(127 downto 96);
              mul_zz <= instr(127 downto 96) = 0;
              dec_next <= C_LEA_MUL;
            when x"0D" | x"0E" | x"0F" =>   -- BEQ / BNE / BLT
              if (instr(7 downto 0) = x"0D" and opr_eq)          -- R[a] = R[b]
                or (instr(7 downto 0) = x"0E" and not opr_eq)
                or (instr(7 downto 0) = x"0F" and opr_lt) then   -- R[a] < R[b]
                br_taken <= '1';
              end if;
              dec_next <= C_NEXT;
            when x"20" | x"21" | x"29" | x"23" | x"27" | x"22" | x"26" | x"28" =>
              -- Vector engine instructions.  All F32 vectors 4-byte aligned;
              -- CVT16 output 2-byte aligned.
              -- (the element operation from the opcode alone, and the
              -- working registers: only the V_ states read them, so the
              -- checks below need not gate them)
              bx <= ea_x; by <= ea_y; bz <= ea_z;
              px <= ea_x; py <= ea_y; pz <= ea_z;
              v_n <= n0; v_n_z <= n0_z; v_n_one <= n0_one;
              case instr(7 downto 0) is
                when x"20" => ve_kind <= K_ADD;
                when x"21" => ve_kind <= K_MUL;
                when x"29" => ve_kind <= K_CVT16;
                when x"23" => ve_kind <= K_SILUMUL;
                when x"27" => ve_kind <= K_GELU;
                when x"22" => ve_kind <= K_SUMSQ;
                when x"26" => ve_kind <= K_SUM;
                when others => ve_kind <= K_COPY;
              end case;
              if ea_x(1 downto 0) /= "00"
                or ((instr(7 downto 0) = x"20" or instr(7 downto 0) = x"21" or instr(7 downto 0) = x"23"
                     or instr(7 downto 0) = x"22" or instr(7 downto 0) = x"26") and ea_y(1 downto 0) /= "00")
                or (instr(7 downto 0) = x"29" and ea_z(0) /= '0')
                or (instr(7 downto 0) /= x"29" and ea_z(1 downto 0) /= "00") then
                err <= ERR_ALIGNMENT;
                dec_next <= C_END;
              elsif n0_z or (instr(7 downto 0) = x"28" and opr_a_z) then
                dec_next <= C_NEXT;                       -- nothing to do
              else
                o16 <= '0'; two_ops <= '0'; has_b <= '0'; has_out <= '1';
                ve_first <= '1';
                ve_ret <= C_NEXT;
                case instr(7 downto 0) is           -- (ve_kind: below)
                  when x"20" => two_ops <= '1'; dec_next <= V_CHUNK;
                  when x"21" => two_ops <= '1'; dec_next <= V_CHUNK;
                  when x"29" => o16 <= '1'; dec_next <= V_CHUNK;
                  when x"23" => two_ops <= '1'; dec_next <= V_CHUNK;
                  when x"27" => dec_next <= V_CHUNK;
                  when x"22" =>                     -- RMSNORM pass 1: sum of squares
                    has_out <= '0'; ve_ret <= R_S0; dec_next <= V_CHUNK;
                  when x"26" =>                     -- LAYERNORM pass 1: sum
                    has_out <= '0'; ve_ret <= L_S0; dec_next <= V_CHUNK;
                  when others =>                    -- MEANROWS: row 0 copied to Z
                    -- (mr_rows, mr_r, mr_src_row: set above)
                    ve_ret <= M_NEXT; dec_next <= V_CHUNK;
                end case;
              end if;
            when x"10" =>             -- GEMV
              d_fmt <= instr(15 downto 8);
              g_addz <= instr(16);
              g_f16 <= instr(17);
              -- (its working registers whatever the checks find: only a
              -- GEMV that goes ahead reads them)
              g_rows <= n1;
              g_nb <= n0(12 downto 5);
              gblk <= (others => '0');
              ps <= ea_x; px <= ea_y; pz <= ea_z; ostart <= ea_z;
              if not (fmt_q(instr(15 downto 8)) or fmt_k(instr(15 downto 8))
                      or instr(15 downto 8) = 0 or instr(15 downto 8) = 1 or instr(15 downto 8) = 30) then
                err <= ERR_FORMAT;
                dec_next <= C_END;
              elsif n0(4 downto 0) /= 0 or n0_z or n0_big or (instr(16) and instr(17)) = '1'
                or (fmt_k(instr(15 downto 8)) and n0(7 downto 0) /= 0) then
                err <= ERR_OPCODE;
                dec_next <= C_END;
              elsif ea_y(1 downto 0) /= "00" or (instr(17) = '1' and ea_z(0) /= '0')
                or (instr(17) = '0' and ea_z(1 downto 0) /= "00")
                or (instr(15 downto 8) = 0 and ea_x(1 downto 0) /= "00")      -- (F32 weights)
                or ((instr(15 downto 8) = 1 or instr(15 downto 8) = 30) and ea_x(0) /= '0') then
                err <= ERR_ALIGNMENT;
                dec_next <= C_END;
              elsif n1_z then
                dec_next <= C_NEXT;
              else
                ld_valid <= '0';
                dec_next <= G_SET;
              end if;
            when x"24" =>             -- ROPE
              if ea_x(2 downto 0) /= "000" or ea_y(1 downto 0) /= "00" then
                err <= ERR_ALIGNMENT;
                dec_next <= C_END;
              elsif n0(0) /= '0' or n1(0) /= '0' or n1_z or n1_big then
                err <= ERR_OPCODE;
                dec_next <= C_END;
              elsif n0_z then
                dec_next <= C_NEXT;
              else
                rope_hd <= n1(8 downto 0);
                ef_addr <= ea_y; ef_f16 <= '0';
                cs_i <= (others => '0');
                ld_valid <= '0';
                dec_next <= RO_CS;
              end if;
            when x"12" =>             -- ARGMAX
              if ea_x(1 downto 0) /= "00" then
                err <= ERR_ALIGNMENT;
                dec_next <= C_END;
              elsif n0_z then
                dec_next <= C_NEXT;
              else
                bx <= ea_x; px <= ea_x; v_n <= n0; v_n_z <= n0_z; v_n_one <= n0_one;
                o16 <= '0'; two_ops <= '0'; has_b <= '0'; has_out <= '0';
                ve_kind <= K_ARGMAX; ve_first <= '1'; ve_g <= (others => '0');
                ve_ret <= AM_DONE;
                dec_next <= V_CHUNK;
              end if;
            when x"25" =>             -- ATTN: read the parameter block first
              if ea_x(1 downto 0) /= "00" or ea_y(1 downto 0) /= "00" or ea_z(1 downto 0) /= "00" then
                err <= ERR_ALIGNMENT;
                dec_next <= C_END;
              else
                at_pos <= opr_a;
                at_pi <= (others => '0');
                ef_addr <= ea_x; ef_f16 <= '0';
                ld_valid <= '0';
                dec_next <= A_PRM;
              end if;
            when x"11" =>             -- DEQROW
              d_fmt <= instr(15 downto 8);
              if not (instr(15 downto 8) = 0 or instr(15 downto 8) = 1 or instr(15 downto 8) = 2
                      or instr(15 downto 8) = 8 or instr(15 downto 8) = 30
                      or fmt_q(instr(15 downto 8)) or fmt_k(instr(15 downto 8)))
                or fmt_iq(instr(15 downto 8))                -- (GEMV only)
                or (fmt_k(instr(15 downto 8)) and n0(7 downto 0) /= 0) then
                err <= ERR_OPCODE;
                dec_next <= C_END;
              elsif ea_z(1 downto 0) /= "00" then
                err <= ERR_ALIGNMENT;
                dec_next <= C_END;
              else
                v_n <= n0; v_n_z <= n0_z; v_n_one <= n0_one;
                ps <= ea_x; pz <= ea_z; ostart <= ea_z; d_unflushed <= false;
                ld_valid <= '0';
                dec_next <= D_GROUP;
              end if;
            when x"09" | x"0A" =>     -- LDR / STR
              if ea_x(1 downto 0) /= "00" then
                err <= ERR_ALIGNMENT;
                dec_next <= C_END;
              else
                if instr(7 downto 0) = x"0A" then
                  mem_is_store <= '1';
                else
                  mem_is_store <= '0';
                end if;
                dec_addr <= ea_x(27 downto 3) & "000";
                dec_next <= C_MEM_DECODE;
              end if;
            when others =>
              err <= ERR_OPCODE;
              dec_next <= C_END;
          end case;
          end if;

        when C_DEC2 =>
          go(dec_next);

        when C_LEA_MUL =>
          -- Shift-and-add, one bit of Z per cycle (LEA is rare)
          assert mul_zz = (mul_z = 0) report "SSNAIL: stale mul_zz" severity failure;
          if mul_zz then
            rf_a(to_integer(instr(11 downto 8))) <= mul_acc;
            go(C_NEXT);
          else
            if mul_z(0) = '1' then
              mul_acc <= mul_acc + mul_m;
            end if;
            mul_m <= mul_m(26 downto 0) & '0';
            mul_z <= '0' & mul_z(31 downto 1);
            mul_zz <= mul_z(31 downto 1) = 0;
          end if;

        when C_MEM_DECODE =>
          go(C_MEM_ISSUE);        -- decode of the 8-byte group

        when C_MEM_ISSUE =>
          if dec_ok = '0' then
            err <= ERR_ADDRESS;
            go(C_END);
          else
            t_is_sd <= dec_is_sd;
            words_got <= (others => '0');
            words_expected <= to_unsigned(4, 8);
            words_done <= false;
            buf_widx <= (others => '0');
            if mem_is_store = '1' then
              str_active <= '1';
              str_k <= "00";
            end if;
            if dec_is_sd = '1' then
              sd_valid_i <= '1'; sd_cmd_addr <= dec_local; sd_cmd_len <= to_unsigned(8, 9);
              if mem_is_store = '1' then sd_cmd_op <= LUMP_OP_WRITE; else sd_cmd_op <= LUMP_OP_READ; end if;
              sd_issue := '1';
            else
              hr_valid_i <= '1'; hr_cmd_addr <= dec_local; hr_cmd_len <= to_unsigned(8, 9);
              if mem_is_store = '1' then hr_cmd_op <= LUMP_OP_WRITE; else hr_cmd_op <= LUMP_OP_READ; end if;
              hr_issue := '1';
            end if;
            go(C_MEM_WAIT);
          end if;

        when C_MEM_WAIT =>
          if mem_is_store = '1' then
            if out_z and hr_issue = '0' then
              str_active <= '0';
              go(C_NEXT);
            end if;
          elsif words_done and rvalid_r = '0' then
            if instr(11 downto 8) /= x"F" then
              if ea_x(2) = '0' then
                rf_r(to_integer(instr(11 downto 8))) <= ld_w(1) & ld_w(0);
              else
                rf_r(to_integer(instr(11 downto 8))) <= ld_w(3) & ld_w(2);
              end if;
            end if;
            go(C_NEXT);
          end if;

        when C_COPY_CALC =>
          assert cp_zero = (cp_remaining = 0) report "SSNAIL: stale cp_zero" severity failure;
          -- Largest chunk that crosses neither a 256-byte boundary at the
          -- source or destination, nor the end of the copy.
          if abort_req = '1' then
            err <= ERR_ABORTED;
            go(C_END);
          elsif err /= ERR_NONE then
            go(C_END);
          elsif cp_zero then
            go(C_NEXT);
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
            go(C_COPY_RD_DECODE);
          end if;

        when C_COPY_RD_DECODE =>
          go(C_COPY_RD_ISSUE);   -- decode of cp_src completes now

        when C_COPY_RD_ISSUE =>
          if dec_ok = '0' then
            err <= ERR_ADDRESS;
            go(C_END);
          else
            words_got <= (others => '0');
            words_expected <= resize(cp_chunk(8 downto 1), 8);
            words_done <= cp_chunk(8 downto 1) = 0;
            buf_widx <= (others => '0');
            t_is_sd <= dec_is_sd;
            if dec_is_sd = '1' then
              sd_valid_i <= '1'; sd_cmd_op <= LUMP_OP_READ;
              sd_cmd_addr <= dec_local; sd_cmd_len <= cp_chunk;
              sd_issue := '1';
            else
              hr_valid_i <= '1'; hr_cmd_op <= LUMP_OP_READ;
              hr_cmd_addr <= dec_local; hr_cmd_len <= cp_chunk;
              hr_issue := '1';
            end if;
            go(C_COPY_RD_WAIT);
          end if;

        when C_COPY_RD_WAIT =>
          -- Note: cp_chunk = 256 gives words_expected = 128, which fits.
          if words_done and rvalid_r = '0' then
            dec_addr <= cp_dst;
            go(C_COPY_WR_DECODE);
          end if;

        when C_COPY_WR_DECODE =>
          go(C_COPY_WR_ISSUE);

        when C_COPY_WR_ISSUE =>
          if dec_ok = '0' then
            err <= ERR_ADDRESS;
            go(C_END);
          else
            buf_ridx <= (others => '0');
            t_is_sd <= dec_is_sd;
            if dec_is_sd = '1' then
              sd_valid_i <= '1'; sd_cmd_op <= LUMP_OP_WRITE;
              sd_cmd_addr <= dec_local; sd_cmd_len <= cp_chunk;
              sd_issue := '1';
            else
              hr_valid_i <= '1'; hr_cmd_op <= LUMP_OP_WRITE;
              hr_cmd_addr <= dec_local; hr_cmd_len <= cp_chunk;
              hr_issue := '1';
            end if;
            go(C_COPY_WR_WAIT);
          end if;

        when C_COPY_WR_WAIT =>
          -- Wait until everything issued (including the write) has
          -- completed, so the buffer can be reused.  Counting completions,
          -- rather than watching for one cmd_done pulse, makes this immune
          -- to the late cmd_done of the preceding read.
          if out_z and hr_issue = '0' then
            cp_src <= cp_src + resize(cp_chunk, 28);
            cp_dst <= cp_dst + resize(cp_chunk, 28);
            cp_remaining <= cp_remaining - resize(cp_chunk, 16);
            cp_zero <= cp_remaining = resize(cp_chunk, 16);
            go(C_COPY_CALC);
          end if;

        when C_SYNC_ISSUE =>
          if c_hr_size /= 0 then
            hr_valid_i <= '1'; hr_cmd_op <= LUMP_OP_INVALIDATE;
            hr_cmd_addr <= (others => '0'); hr_cmd_len <= (others => '0');
            hr_issue := '1';
          end if;
          if c_sd_size /= 0 then
            sd_valid_i <= '1'; sd_cmd_op <= LUMP_OP_INVALIDATE;
            sd_cmd_addr <= (others => '0'); sd_cmd_len <= (others => '0');
            sd_issue := '1';
          end if;
          go(C_SYNC_WAIT);

        when C_SYNC_WAIT =>
          -- All earlier commands (e.g. COPY writes) complete before the
          -- invalidates, because each port's queue is in order.
          if out_z then
            wd_cnt <= (others => '0');
            if cpu_sync = '1' then
              cpu_sync <= '0';
              go(C_IDLE);
            else
              go(C_NEXT);
            end if;
          elsif wd_cnt = x"FFFF" then
            wd_cnt <= (others => '0');
            wd_fired <= '1';
            cpu_sync <= '0';
            err <= ERR_READ;
            go(C_END);
          else
            wd_cnt <= wd_cnt + 1;
          end if;

        when C_LP_DECODE =>
          go(C_LP_ISSUE);          -- decode of the chunk address now

        when C_LP_ISSUE =>
          if dec_ok = '0' then
            lp_error <= '1';             -- outside both regions: drop it
            go(C_LP_DONE);
          else
            lp_active <= '1';
            t_is_sd <= dec_is_sd;
            if dec_is_sd = '1' then
              sd_valid_i <= '1'; sd_cmd_op <= LUMP_OP_WRITE;
              sd_cmd_addr <= dec_local; sd_cmd_len <= cp_chunk;
              sd_issue := '1';
            else
              hr_valid_i <= '1'; hr_cmd_op <= LUMP_OP_WRITE;
              hr_cmd_addr <= dec_local; hr_cmd_len <= cp_chunk;
              hr_issue := '1';
            end if;
            go(C_LP_WAIT);
          end if;

        when C_LP_WAIT =>
          if out_z and hr_issue = '0' then
            lp_active <= '0';
            -- The write bypassed the CPU's caches on that port
            if t_is_sd = '1' then
              sd_valid_i <= '1'; sd_cmd_op <= LUMP_OP_INVALIDATE;
              sd_cmd_addr <= (others => '0'); sd_cmd_len <= (others => '0');
              sd_issue := '1';
            else
              hr_valid_i <= '1'; hr_cmd_op <= LUMP_OP_INVALIDATE;
              hr_cmd_addr <= (others => '0'); hr_cmd_len <= (others => '0');
              hr_issue := '1';
            end if;
            go(C_LP_INVAL);
          end if;

        when C_LP_INVAL =>
          if out_z then
            go(C_LP_DONE);
          end if;

        when C_LP_DONE =>
          lp_drain <= lp_end;
          lp_at_cmt <= lp_end = lp_cmt_end;
          if lp_is_commit = '0' then
            lp_dec := '1';
            lp_ack_tgl <= not lp_ack_tgl;
          end if;
          go(C_IDLE);

        -- ------------------------------------------------------------------
        -- Subroutines: FPU operation, region read into a buffer, masked
        -- write from buf.  Callers set the parameters and the return state.
        when C_FPU_WAIT =>
          if fpu_done = '1' then
            fpu_r <= fpu_res;
            fr_neg <= fpu_res(31) = '1';
            fr_big <= fpu_res > TAB_SEGMENTS - 1;
            fr_z   <= fpu_res(30 downto 0) = 0;
            fr_mlt <= flt(at_m, fpu_res);
            go(fpu_ret);
          end if;

        when C_RD_DEC =>
          go(C_RD_ISSUE);
        when C_RD_ISSUE =>
          if (hr_valid_i or sd_valid_i) = '1' then
            null;                                   -- channel busy (GEMV stream)
          elsif dec_ok = '0' then
            err <= ERR_ADDRESS;
            go(C_END);
          else
            words_got <= (others => '0');
            words_expected <= resize(rd_len(8 downto 1), 8);
            words_done <= rd_len(8 downto 1) = 0;
            buf_widx <= rd_addr(7 downto 1);
            cap_sel <= rd_sel;
            if g2 = '1' then
              rq_push := true;
              rq_push_tag := '0';
              rq_push_cnt := resize(rd_len(8 downto 1), 8);
            end if;
            t_is_sd <= dec_is_sd;
            if dec_is_sd = '1' then
              sd_valid_i <= '1'; sd_cmd_op <= LUMP_OP_READ;
              sd_cmd_addr <= dec_local; sd_cmd_len <= rd_len;
              sd_issue := '1';
            else
              hr_valid_i <= '1'; hr_cmd_op <= LUMP_OP_READ;
              hr_cmd_addr <= dec_local; hr_cmd_len <= rd_len;
              hr_issue := '1';
            end if;
            go(C_RD_WAIT);
          end if;
        when C_RD_WAIT =>
          if words_done and rvalid_r = '0' then
            cap_sel <= "00";
            go(rd_ret);
          end if;

        when C_WR_DEC =>
          go(C_WR_ISSUE);
        when C_WR_ISSUE =>
          if (hr_valid_i or sd_valid_i) = '1' then
            null;                                   -- channel busy (GEMV stream)
          elsif dec_ok = '0' then
            err <= ERR_ADDRESS;
            go(C_END);
          else
            mw_active <= '1';
            mw_k <= (others => '0');
            if dec_is_sd = '1' then
              sd_valid_i <= '1'; sd_cmd_op <= LUMP_OP_WRITE;
              sd_cmd_addr <= dec_local; sd_cmd_len <= wr_len;
              sd_issue := '1';
            else
              hr_valid_i <= '1'; hr_cmd_op <= LUMP_OP_WRITE;
              hr_cmd_addr <= dec_local; hr_cmd_len <= wr_len;
              hr_issue := '1';
            end if;
            go(C_WR_WAIT);
          end if;
        when C_WR_WAIT =>
          if out_z and hr_issue = '0' then
            mw_active <= '0';
            go(wr_ret);
          end if;

        -- ------------------------------------------------------------------
        -- VADD / VMUL / CVT16: chunks that cross no 256-byte boundary in X,
        -- Y or Z; read X (and Y), run each element through the FPU into buf,
        -- write Z with byte masks.
        when V_CHUNK =>
          -- First stage: independently register each 256-byte boundary limit,
          -- and saturate the full-width element count.  No chained minimum
          -- comparisons on this clock edge.
          if v_n_z then                                 -- v_n = 0
            go(ve_ret);
          else
            if v_n(31 downto 8) = 0 then
              vc_rem_q <= v_n(7 downto 0);
            else
              vc_rem_q <= x"FF";
            end if;
            vc_x_q <= resize((to_unsigned(256, 9) - resize(px(7 downto 0), 9)) / 4, 8);
            if two_ops = '1' then
              vc_y_q <= resize((to_unsigned(256, 9) - resize(py(7 downto 0), 9)) / 4, 8);
            else
              vc_y_q <= x"FF";
            end if;
            if has_b = '1' then
              vc_b_q <= resize((to_unsigned(256, 9) - resize(pb(7 downto 0), 9)) / 4, 8);
            else
              vc_b_q <= x"FF";
            end if;
            if has_out = '1' then
              if o16 = '1' then
                vc_z_q <= resize((to_unsigned(256, 9) - resize(pz(7 downto 0), 9)) / 2, 8);
              else
                vc_z_q <= resize((to_unsigned(256, 9) - resize(pz(7 downto 0), 9)) / 4, 8);
              end if;
            else
              vc_z_q <= x"FF";
            end if;
            go(V_CHUNK_MIN1);
          end if;

        when V_CHUNK_MIN1 =>
          -- Second stage: two independent 8-bit minimum comparisons.
          if vc_rem_q < vc_x_q then
            vc_left_q <= vc_rem_q;
          else
            vc_left_q <= vc_x_q;
          end if;
          if vc_y_q < vc_b_q then
            vc_right_q <= vc_y_q;
          else
            vc_right_q <= vc_b_q;
          end if;
          go(V_CHUNK_MIN2);

        when V_CHUNK_MIN2 =>
          -- Third stage: select the remaining minimum, including Z.
          -- Keeping the same strict-less-than preference as the original
          -- comparison chain preserves numeric behavior for equal limits.
          if vc_left_q < vc_right_q then
            vlen8 := vc_left_q;
          else
            vlen8 := vc_right_q;
          end if;
          if vc_z_q < vlen8 then vlen8 := vc_z_q; end if;
          v_e <= vlen8;
          go(V_CHUNK_ADDR);

        when V_CHUNK_ADDR =>
          a0 := px(27 downto 3) & "000";
          -- Original expression, modulo 2**9:
          -- align8(px + 4*v_e + 7) - align8(px).
          -- Only px(2:0) and v_e(6:0) influence these nine bits.
          span9 := resize(px(2 downto 0), 9)
                 + (v_e(6 downto 0) & "00") + 7;
          rd_addr <= a0;
          rd_len <= span9(8 downto 3) & "000";
          rd_sel <= "01";
            dec_addr <= a0;
            if two_ops = '1' then
              rd_ret <= V_LDY;
            elsif has_b = '1' then
              rd_ret <= V_LDB;
            else
              rd_ret <= V_EL0;
            end if;
            go(C_RD_DEC);

        when V_LDY =>
          a0 := py(27 downto 3) & "000";
          span9 := resize(py(2 downto 0), 9)
                 + (v_e(6 downto 0) & "00") + 7;
          rd_addr <= a0;
          rd_len <= span9(8 downto 3) & "000";
          rd_sel <= "10";
          dec_addr <= a0;
          if has_b = '1' then
            rd_ret <= V_LDB;
          else
            rd_ret <= V_EL0;
          end if;
          go(C_RD_DEC);

        when V_LDB =>
          a0 := pb(27 downto 3) & "000";
          span9 := resize(pb(2 downto 0), 9)
                 + (v_e(6 downto 0) & "00") + 7;
          rd_addr <= a0;
          rd_len <= span9(8 downto 3) & "000";
          rd_sel <= "11";
          dec_addr <= a0;
          rd_ret <= V_EL0;
          go(C_RD_DEC);

        when V_EL0 =>
          v_i <= (others => '0');
          pf_go := true;
          pf_i := (others => '0');
          pf_x := px(7 downto 0); pf_y := py(7 downto 0); pf_b := pb(7 downto 0);
          go(V_EL);

        when V_EL =>
          assert v_done = (v_i = v_e) report "SSNAIL: stale v_done" severity failure;
          if v_done then                                -- v_i = v_e
            if has_out = '1' then
              a0 := pz(27 downto 3) & "000";
              if o16 = '1' then
                a2 := pz + (resize(v_e, 27) & "0");
              else
                a2 := pz + (resize(v_e, 26) & "00");
              end if;
              a1 := a2 + 7;
              a1(2 downto 0) := "000";
              wr_addr <= a0;
              wr_len <= resize(a1 - a0, 9);
              mw_lead <= resize(pz - a0, 9);
              mw_vend <= resize(a2 - a0, 9);
              mw_idx <= a0(7 downto 1);
              dec_addr <= a0;
              wr_ret <= V_ADV;
              go(C_WR_DEC);
            else
              go(V_ADV);
            end if;
          else
            -- operands already read (pre_*) by the state that came here
            vck_x := px(7 downto 0) + (v_i(5 downto 0) & "00");
            vck_y := py(7 downto 0) + (v_i(5 downto 0) & "00");
            assert pre_x = bufx(to_integer(vck_x(7 downto 1) + 1)) & bufx(to_integer(vck_x(7 downto 1)))
              and (two_ops = '0' or pre_y = bufy(to_integer(vck_y(7 downto 1) + 1)) & bufy(to_integer(vck_y(7 downto 1))))
              report "SSNAIL: stale V_EL operands" severity failure;
            xv := pre_x;
            ex <= pre_x;
            ey <= pre_y;
            eb <= pre_b;
            -- first step of each element operation
            case ve_kind is
              when K_ARGMAX =>
                -- compared with am_best on the next edge (see before the case)
                am_x_q <= xv;
                am_g_q <= ve_g;
                am_first_q <= ve_first;
                am_v_q <= '1';
                ve_first <= '0';
                ve_g <= ve_g + 1;
                v_i <= v_i + 1;
                pf_go := true;
                pf_x := vix + 4; pf_y := viy + 4; pf_b := vib + 4; pf_i := v_i + 1;
              when K_ROPE =>
                -- pair (x0, x1) = elements i, i+1: x0 c - x1 s, x0 s + x1 c
                x1v <= pre_x1;
                fpu_op <= FOP_MUL; fpu_a <= xv; fpu_b <= csv(to_integer(rope_j));
                fpu_start <= '1'; fpu_ret <= E_R1; go(C_FPU_WAIT);
              when K_COPY | K_SUM =>
                fpu_r <= xv;
                if ve_kind = K_SUM then go(E_ACC); else go(V_ELST); end if;
              when K_SILUMUL | K_GELU =>
                tx <= xv;
                if ve_kind = K_SILUMUL then
                  tab_id <= "00";
                  tx_below <= flt(xv, SILU_LO); tx_above <= not flt(xv, SILU_HI);
                else
                  tab_id <= "01";
                  tx_below <= flt(xv, GELU_LO); tx_above <= not flt(xv, GELU_HI);
                end if;
                tab_ret <= E_K1;
                go(T_START);
              when others =>
                fpu_a <= xv;
                case ve_kind is
                  when K_ADD =>
                    fpu_op <= FOP_ADD;
                    fpu_b <= pre_y;
                    fpu_ret <= V_ELST;
                  when K_MUL =>
                    fpu_op <= FOP_MUL;
                    fpu_b <= pre_y;
                    fpu_ret <= V_ELST;
                  when K_CVT16 =>
                    fpu_op <= FOP_F32TOF16;
                    fpu_ret <= V_ELST;
                  when K_SCALE =>
                    fpu_op <= FOP_MUL; fpu_b <= s_sc; fpu_ret <= V_ELST;
                  when K_SUMSQ =>
                    fpu_op <= FOP_MUL; fpu_b <= xv; fpu_ret <= E_ACC;
                  when K_RMSOUT =>
                    fpu_op <= FOP_MUL; fpu_b <= s_r; fpu_ret <= E_K1;
                  when others =>                    -- K_LNVAR, K_LNOUT: d = x - mu
                    fpu_op <= FOP_ADD; fpu_b <= (not s_mu(31)) & s_mu(30 downto 0);
                    fpu_ret <= E_K1;
                end case;
                fpu_start <= '1';
                go(C_FPU_WAIT);
            end case;
          end if;

        -- second and later steps of the element operations
        when E_K1 =>
          case ve_kind is
            when K_SILUMUL =>                       -- silu(x) * y
              fpu_op <= FOP_MUL; fpu_a <= tval; fpu_b <= ey; fpu_ret <= V_ELST;
              fpu_start <= '1'; go(C_FPU_WAIT);
            when K_GELU =>
              fpu_r <= tval; go(V_ELST);
            when K_RMSOUT =>                        -- (x * r) * g
              fpu_op <= FOP_MUL; fpu_a <= fpu_r; fpu_b <= ey; fpu_ret <= V_ELST;
              fpu_start <= '1'; go(C_FPU_WAIT);
            when K_LNVAR =>                         -- d * d
              fpu_op <= FOP_MUL; fpu_a <= fpu_r; fpu_b <= fpu_r; fpu_ret <= E_ACC;
              fpu_start <= '1'; go(C_FPU_WAIT);
            when others =>                          -- K_LNOUT: d * r
              fpu_op <= FOP_MUL; fpu_a <= fpu_r; fpu_b <= s_r; fpu_ret <= E_K2;
              fpu_start <= '1'; go(C_FPU_WAIT);
          end case;

        when E_K2 =>                                -- K_LNOUT: (d * r) * g
          fpu_op <= FOP_MUL; fpu_a <= fpu_r; fpu_b <= ey; fpu_ret <= E_K3;
          fpu_start <= '1'; go(C_FPU_WAIT);

        when E_K3 =>                                -- K_LNOUT: ... + b
          fpu_op <= FOP_ADD; fpu_a <= fpu_r; fpu_b <= eb; fpu_ret <= V_ELST;
          fpu_start <= '1'; go(C_FPU_WAIT);

        when E_ACC =>
          -- sequential sum: the first value as it is, then acc = acc + v
          if ve_first = '1' then
            ve_acc <= fpu_r;
            ve_first <= '0';
            v_i <= v_i + 1;
            pf_go := true;
            pf_x := vix + 4; pf_y := viy + 4; pf_b := vib + 4; pf_i := v_i + 1;
            go(V_EL);
          else
            fpu_op <= FOP_ADD; fpu_a <= ve_acc; fpu_b <= fpu_r; fpu_ret <= E_ACC2;
            fpu_start <= '1'; go(C_FPU_WAIT);
          end if;

        when E_ACC2 =>
          ve_acc <= fpu_r;
          v_i <= v_i + 1;
          pf_go := true;
          pf_x := vix + 4; pf_y := viy + 4; pf_b := vib + 4; pf_i := v_i + 1;
          go(V_EL);

        when V_ELST =>
          v_i <= v_i + 1;
          pf_go := true;
          pf_x := vix + 4; pf_y := viy + 4; pf_b := vib + 4; pf_i := v_i + 1;
          go(V_EL);

        when V_ADV =>
          px <= px + (resize(v_e, 26) & "00");
          py <= py + (resize(v_e, 26) & "00");
          pb <= pb + (resize(v_e, 26) & "00");
          if o16 = '1' then
            pz <= pz + (resize(v_e, 27) & "0");
          else
            pz <= pz + (resize(v_e, 26) & "00");
          end if;
          v_n <= v_n - resize(v_e, 32);
          v_n_z <= v_n = resize(v_e, 32);
          v_n_one <= v_n = resize(v_e, 32) + 1;
          go(V_CHUNK);

        -- ------------------------------------------------------------------
        -- Table lookup (ssnail_hw.Table): tval = f(tx), then tab_ret.
        when T_START =>
          assert tx_below = flt(tx, SILU_LO) or tab_id /= "00" report "SSNAIL: stale tx_below" severity failure;
          assert tx_above = not flt(tx, SILU_HI) or tab_id /= "00" report "SSNAIL: stale tx_above" severity failure;
          assert tx_below = flt(tx, GELU_LO) or tab_id /= "01" report "SSNAIL: stale tx_below" severity failure;
          assert tx_above = not flt(tx, GELU_HI) or tab_id /= "01" report "SSNAIL: stale tx_above" severity failure;
          assert tx_below = flt(tx, EXPT_LO) or tab_id(1) /= '1' report "SSNAIL: stale tx_below" severity failure;
          assert tx_above = not flt(tx, EXPT_HI) or tab_id(1) /= '1' report "SSNAIL: stale tx_above" severity failure;
          if tab_id = "00" then
            lo := SILU_LO; hi := SILU_HI;
          elsif tab_id = "01" then
            lo := GELU_LO; hi := GELU_HI;
          else
            lo := EXPT_LO; hi := EXPT_HI;
          end if;
          if tx_below then                             -- flt(tx, lo)
            tval <= (others => '0');                   -- below: 0
            go(tab_ret);
          elsif tx_above then                          -- not flt(tx, hi)
            if tab_id = "10" then
              tval <= x"3F800000";                     -- exp above: 1
            else
              tval <= tx;                              -- silu, gelu above: x
            end if;
            go(tab_ret);
          else
            fpu_op <= FOP_ADD;                         -- x - lo
            fpu_a <= tx;
            fpu_b <= (not lo(31)) & lo(30 downto 0);
            fpu_start <= '1';
            fpu_ret <= T_K;
            go(C_FPU_WAIT);
          end if;

        when T_K =>
          fpu_op <= FOP_MUL;                           -- (x - lo) * k
          fpu_a <= fpu_r;
          if tab_id = "00" then fpu_b <= SILU_K;
          elsif tab_id = "01" then fpu_b <= GELU_K;
          else fpu_b <= EXPT_K; end if;
          fpu_start <= '1';
          fpu_ret <= T_I;
          go(C_FPU_WAIT);

        when T_I =>
          fpu_op <= FOP_TRUNC;                         -- floor (it is >= 0)
          fpu_a <= fpu_r;
          fpu_start <= '1';
          fpu_ret <= T_LOOK;
          go(C_FPU_WAIT);

        when T_LOOK =>
          assert fr_neg = (fpu_r(31) = '1') and fr_big = (fpu_r > TAB_SEGMENTS - 1)
            report "SSNAIL: stale fr_neg/fr_big" severity failure;
          if fr_neg then
            ti := 0;
          elsif fr_big then
            ti := TAB_SEGMENTS - 1;
          else
            ti := to_integer(fpu_r(15 downto 0));
          end if;
          -- One synchronous ROM read.  Note that tab_id="11" historically
          -- chose EXPT as well, so preserve that fallback explicitly.
          -- Compute the banked ROM address *before* the clocked read,
          -- ensuring Vivado sees only one physical read port.
          if tab_id = "01" then
            ti := ti + 256;
          elsif tab_id /= "00" then
            ti := ti + 512;
          end if;
          coeff_word <= coeff_rom(ti);
          go(T_ROM2);

        when T_ROM2 =>
          go(T_COEFF);                    -- (coeff_word -> coeff_q)

        when T_COEFF =>
          -- The ROM word read in T_LOOK, through its output register
          fpu_op <= FOP_MUL;
          fpu_a <= coeff_q(31 downto 0);
          tc0 <= coeff_q(63 downto 32);
          fpu_b <= tx;
          fpu_start <= '1';
          fpu_ret <= T_C0;
          go(C_FPU_WAIT);

        when T_C0 =>
          fpu_op <= FOP_ADD;                           -- c0[i] + c1[i] * x
          fpu_a <= tc0;
          fpu_b <= fpu_r;
          fpu_start <= '1';
          fpu_ret <= T_DONE;
          go(C_FPU_WAIT);

        when T_DONE =>
          tval <= fpu_r;
          go(tab_ret);

        -- ------------------------------------------------------------------
        -- RMSNORM after pass 1 (ve_acc = sum of squares):
        -- rn = 1/N; m = ss * rn; r = 1 / sqrt(m + eps); then pass 2
        when R_S0 =>
          fpu_op <= FOP_I2F; fpu_a <= n0; fpu_start <= '1';
          fpu_ret <= R_S1; go(C_FPU_WAIT);
        when R_S1 =>
          fpu_op <= FOP_DIV; fpu_a <= x"3F800000"; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= R_S2; go(C_FPU_WAIT);
        when R_S2 =>
          fpu_op <= FOP_MUL; fpu_a <= ve_acc; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= R_S3; go(C_FPU_WAIT);
        when R_S3 =>
          fpu_op <= FOP_ADD; fpu_a <= fpu_r; fpu_b <= n2; fpu_start <= '1';
          fpu_ret <= R_S4; go(C_FPU_WAIT);
        when R_S4 =>
          fpu_op <= FOP_SQRT; fpu_a <= fpu_r; fpu_start <= '1';
          fpu_ret <= R_S5; go(C_FPU_WAIT);
        when R_S5 =>
          fpu_op <= FOP_DIV; fpu_a <= x"3F800000"; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= R_S6; go(C_FPU_WAIT);
        when R_S6 =>
          s_r <= fpu_r;
          px <= bx; py <= by; pz <= bz; v_n <= n0; v_n_z <= n0_z; v_n_one <= n0_one;
          ve_kind <= K_RMSOUT; two_ops <= '1'; has_out <= '1'; ve_ret <= C_NEXT;
          go(V_CHUNK);

        -- LAYERNORM: after pass 1 (sum): rn = 1/N, mu = sum * rn, pass 2
        -- (sum of (x - mu)^2), var = that * rn, r = 1 / sqrt(var + eps),
        -- pass 3 with G at Y and B after it
        when L_S0 =>
          fpu_op <= FOP_I2F; fpu_a <= n0; fpu_start <= '1';
          fpu_ret <= L_S1; go(C_FPU_WAIT);
        when L_S1 =>
          fpu_op <= FOP_DIV; fpu_a <= x"3F800000"; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= L_S2; go(C_FPU_WAIT);
        when L_S2 =>
          s_rn <= fpu_r;
          fpu_op <= FOP_MUL; fpu_a <= ve_acc; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= L_S3; go(C_FPU_WAIT);
        when L_S3 =>
          s_mu <= fpu_r;
          px <= bx; v_n <= n0; v_n_z <= n0_z; v_n_one <= n0_one; ve_first <= '1';
          ve_kind <= K_LNVAR; has_out <= '0'; ve_ret <= L_S4;
          go(V_CHUNK);
        when L_S4 =>
          fpu_op <= FOP_MUL; fpu_a <= ve_acc; fpu_b <= s_rn; fpu_start <= '1';
          fpu_ret <= L_S5; go(C_FPU_WAIT);
        when L_S5 =>
          fpu_op <= FOP_ADD; fpu_a <= fpu_r; fpu_b <= n2; fpu_start <= '1';
          fpu_ret <= L_S6; go(C_FPU_WAIT);
        when L_S6 =>
          fpu_op <= FOP_SQRT; fpu_a <= fpu_r; fpu_start <= '1';
          fpu_ret <= L_S7; go(C_FPU_WAIT);
        when L_S7 =>
          if ve_kind = K_LNVAR then
            -- r = 1 / sqrt(...), then pass 3
            fpu_op <= FOP_DIV; fpu_a <= x"3F800000"; fpu_b <= fpu_r; fpu_start <= '1';
            ve_kind <= K_LNOUT;
            fpu_ret <= L_S7; go(C_FPU_WAIT);
          else
            s_r <= fpu_r;
            px <= bx; py <= by; pb <= by + (n0(25 downto 0) & "00"); pz <= bz; v_n <= n0; v_n_z <= n0_z; v_n_one <= n0_one;
            two_ops <= '1'; has_b <= '1'; has_out <= '1'; ve_ret <= C_NEXT;
            go(V_CHUNK);
          end if;

        -- MEANROWS: Z = row 0; Z = Z + row r for r = 1 .. R-1; Z = Z * (1/R)
        when M_NEXT =>
          assert mr_end = (mr_r = mr_rows) report "SSNAIL: stale mr_end" severity failure;
          if mr_end then
            go(M_S0);
          else
            -- Induction: before row r, mr_src_row = bx + (r-1)*4*n0 (mod 2^28).
            -- Thus the addition below is exactly the old bx + r*4*n0.
            px <= mr_src_row + (n0(25 downto 0) & "00");
            mr_src_row <= mr_src_row + (n0(25 downto 0) & "00");
            py <= bz; pz <= bz; v_n <= n0; v_n_z <= n0_z; v_n_one <= n0_one;
            ve_kind <= K_ADD; two_ops <= '1'; has_out <= '1'; ve_ret <= M_NEXT;
            mr_r <= mr_r + 1;
            go(V_CHUNK);
          end if;
        when M_S0 =>
          fpu_op <= FOP_I2F; fpu_a <= mr_rows; fpu_start <= '1';
          fpu_ret <= M_S1; go(C_FPU_WAIT);
        when M_S1 =>
          fpu_op <= FOP_DIV; fpu_a <= x"3F800000"; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= M_S2; go(C_FPU_WAIT);
        when M_S2 =>
          s_sc <= fpu_r;
          px <= bz; pz <= bz; v_n <= n0; v_n_z <= n0_z; v_n_one <= n0_one;
          ve_kind <= K_SCALE; two_ops <= '0'; has_out <= '1'; ve_ret <= C_NEXT;
          go(V_CHUNK);

        -- ------------------------------------------------------------------
        -- DEQROW: gather each group (one element, or one 32-element quant
        -- block) into grp through a forward-only byte fetcher, expand it to
        -- F32 into buf, and write buf out whenever Z crosses a 256-byte
        -- boundary or the row ends.
        when D_GROUP =>
          if v_n_z then                                 -- v_n = 0
            assert d_unflushed = (pz /= ostart) report "SSNAIL: stale d_unflushed" severity failure;
          if d_unflushed then                         -- pz /= ostart
              a0 := ostart(27 downto 3) & "000";
              a1 := pz + 7;
              a1(2 downto 0) := "000";
              wr_addr <= a0;
              wr_len <= resize(a1 - a0, 9);
              mw_lead <= resize(ostart - a0, 9);
              mw_vend <= resize(pz - a0, 9);
              mw_idx <= a0(7 downto 1);
              dec_addr <= a0;
              ostart <= pz; d_unflushed <= false;
              wr_ret <= C_NEXT;
              go(C_WR_DEC);
            else
              go(C_NEXT);
            end if;
          else
            gi <= (others => '0');
            d_j <= (others => '0');
            d_jl <= fmt_k(d_fmt) = false and (d_fmt = 0 or d_fmt = 1 or d_fmt = 30);  -- (epg = 1)
            d_have_scale <= '0';
            kq_gs <= '0';
            fetch_ret <= D_EMIT;
            dk <= '0';
            case to_integer(d_fmt) is
              when 0 => gbytes <= to_unsigned(4, 8);  epg <= to_unsigned(1, 9);
              when 1 | 30 => gbytes <= to_unsigned(2, 8); epg <= to_unsigned(1, 9);
              when 8 => gbytes <= to_unsigned(34, 8); epg <= to_unsigned(32, 9);
              when 39 => gbytes <= to_unsigned(17, 8); epg <= to_unsigned(32, 9);  -- MXFP4
              when 6 => gbytes <= to_unsigned(22, 8); epg <= to_unsigned(32, 9);   -- Q5_0
              when others => gbytes <= to_unsigned(18, 8); epg <= to_unsigned(32, 9);  -- Q4_0, IQ4_NL
            end case;
            d_kind <= deq_kind(d_fmt);
            if fmt_k(d_fmt) then                                                  -- K-quants
              gbytes <= to_unsigned(kq_bytes(d_fmt), 8); epg <= to_unsigned(256, 9);
              dk <= '1';
              fetch_ret <= D_KH0;
            end if;
            if d_fmt = 10 or d_fmt = 12 or d_fmt = 13 then
              kq_min <= '1';
            else
              kq_min <= '0';
            end if;
            for i in 0 to 4 loop
              kq_hwc(i) <= to_unsigned(kq_hword(d_fmt, i), 6);
            end loop;
            go(D_FETCH0);
          end if;

        -- (one cycle for ps_miss to catch up with ps and ld_block)
        when D_FETCH0 =>
          gi_end <= gi = gbytes;
          go(D_FETCH);
        when D_FETCH =>
          assert ps_miss = (ld_valid = '0' or ps(27 downto 8) /= ld_block)
            report "SSNAIL: ps_miss" severity failure;
          assert gi_end = (gi = gbytes) report "SSNAIL: stale gi_end" severity failure;
          if gi_end then
            go(fetch_ret);
          elsif ps_miss then
            -- load the rest of this 256-byte block
            a0 := ps(27 downto 3) & "000";
            a1 := (ps(27 downto 8) + 1) & x"00";
            rd_addr <= a0;
            rd_len <= resize(a1 - a0, 9);
            rd_sel <= "01";
            dec_addr <= a0;
            ld_block <= ps(27 downto 8);
            ld_valid <= '1';
            rd_ret <= D_FETCH0;
            go(C_RD_DEC);
          else
            wd := bufx(to_integer(ps(7 downto 1)));
            if ps(0) = '0' then
              wb := wd(7 downto 0);
            else
              wb := wd(15 downto 8);
            end if;
            if dk = '1' then
              -- (K-quant super-block: byte gi of half 0 of kq_sb)
              kw_we(to_integer(gi(1 downto 0))) := '1';
              kw_a(to_integer(gi(1 downto 0))) := '0' & gi(7 downto 2);
              kw_d(to_integer(gi(1 downto 0))) := wb;
            else
              grp(to_integer(gi(5 downto 0))) <= wb;
            end if;
            ps <= ps + 1;
            gi <= gi + 1;
            gi_end <= gi + 1 = gbytes;
            if ps(7 downto 0) = x"FF" then
              go(D_FETCH0);                            -- (into the next block)
            end if;
          end if;

        -- K-quant DEQROW: the header (as the GEMV header unit: words
        -- kq_hwc through the registered header read kq_hrd), d and dmin
        when D_KH0 =>
          kq_hh <= '0';
          kq_hwl <= kq_hwc;
          kq_hi <= (others => '0');
          go(D_KH1);
        when D_KH1 =>
          kq_hwl(0 to 3) <= kq_hwl(1 to 4);            -- (kq_hrd: word 0 next)
          go(D_KH);
        when D_KH =>
          kq_hb(0 to 15) <= kq_hb(4 to 19);
          kq_hb(16) <= kq_hrd(7 downto 0);
          kq_hb(17) <= kq_hrd(15 downto 8);
          kq_hb(18) <= kq_hrd(23 downto 16);
          kq_hb(19) <= kq_hrd(31 downto 24);
          kq_hwl(0 to 3) <= kq_hwl(1 to 4);
          kq_hi <= kq_hi + 1;
          if kq_hi = 4 then
            go(D_KDEC);
          end if;
        when D_KDEC =>
          kq_sc(0) <= kq_scales(d_fmt, kq_hb);
          kq_m(0) <= kq_mins(d_fmt, kq_hb);
          kq_d16 <= kq_d(d_fmt, kq_hb);
          kq_dmin16 <= kq_dmin(d_fmt, kq_hb);
          go(D_KD);
        when D_KD =>
          fpu_op <= FOP_F16TOF32;
          fpu_a <= x"0000" & kq_d16;
          fpu_start <= '1';
          fpu_ret <= D_KDM;
          go(C_FPU_WAIT);
        when D_KDM =>
          kd32 <= fpu_r;
          fpu_op <= FOP_F16TOF32;
          fpu_a <= x"0000" & kq_dmin16;
          fpu_start <= '1';
          fpu_ret <= D_EMIT;
          go(C_FPU_WAIT);
        -- the 16-group's A = d * sc, B = dmin * m (exact)
        when D_KA1 =>
          fpu_op <= FOP_MUL;
          fpu_a <= kd32;
          fpu_b <= fpu_r;
          fpu_start <= '1';
          fpu_ret <= D_KA2;
          go(C_FPU_WAIT);
        when D_KA2 =>
          kq_ga32 <= fpu_r;
          if kq_min = '1' then
            fpu_op <= FOP_I2F;
            fpu_a <= resize(kq_m(0)(to_integer(d_j(7 downto 4))), 32);
            fpu_start <= '1';
            fpu_ret <= D_KB1;
            go(C_FPU_WAIT);
          else
            kq_gs <= '1';
            go(D_EMIT);
          end if;
        when D_KB1 =>
          fpu_op <= FOP_MUL;
          fpu_a <= kdm32;
          fpu_b <= fpu_r;
          fpu_start <= '1';
          fpu_ret <= D_KB2;
          go(C_FPU_WAIT);
        when D_KB2 =>
          kq_gb32 <= fpu_r;
          kq_gs <= '1';
          go(D_EMIT);
        -- element d_j: its words through the K reader's registered reads
        when D_KQ =>
          go(D_KQ2);
        when D_KQ2 =>
          kq_dq <= kq_q(kq_wl_q(8 * to_integer(d_j(1 downto 0)) + 7 downto 8 * to_integer(d_j(1 downto 0))),
                        kq_wh_q(8 * to_integer(d_j(1 downto 0)) + 7 downto 8 * to_integer(d_j(1 downto 0))),
                        kq_rd_q);
          go(D_KQ3);
        when D_KQ3 =>
          fpu_op <= FOP_I2F;
          fpu_a <= unsigned(resize(kq_dq, 32));
          fpu_start <= '1';
          fpu_ret <= D_KMUL;
          go(C_FPU_WAIT);
        when D_KMUL =>
          fpu_op <= FOP_MUL;                           -- q * A
          fpu_a <= kq_ga32;
          fpu_b <= fpu_r;
          fpu_start <= '1';
          if kq_min = '1' then
            fpu_ret <= D_KSUB;
          else
            fpu_ret <= D_AFTER;
          end if;
          go(C_FPU_WAIT);
        when D_KSUB =>
          fpu_op <= FOP_ADD;                           -- q * A - B
          fpu_a <= fpu_r;
          fpu_b <= (not kq_gb32(31)) & kq_gb32(30 downto 0);
          fpu_start <= '1';
          fpu_ret <= D_AFTER;
          go(C_FPU_WAIT);

        when D_EMIT =>
          assert d_kind = deq_kind(d_fmt) report "SSNAIL: stale d_kind" severity failure;
          if d_kind = DK_K then
            if kq_gs = '0' then
              if d_j = 0 then
                kdm32 <= fpu_r;                        -- (from D_KDM)
              end if;
              fpu_op <= FOP_I2F;                       -- F32(sc) of the group
              fpu_a <= unsigned(resize(kq_sc(0)(to_integer(d_j(7 downto 4))), 32));
              fpu_start <= '1';
              fpu_ret <= D_KA1;
              go(C_FPU_WAIT);
            else
              kc := kq_rd(d_fmt, to_integer(d_j(7 downto 5)));
              if kc.wr = '1' and d_j(4) = '1' then
                kc.sl := kc.sl + 4;                    -- (IQ4_XS: the high nibbles)
              end if;
              kq_rd_q <= kc;
              if kq_rd(d_fmt, to_integer(d_j(7 downto 5))).wr = '1' then
                kq_la <= '0' & (kq_rd(d_fmt, to_integer(d_j(7 downto 5))).la + d_j(3 downto 2));
              else
                kq_la <= '0' & (kq_rd(d_fmt, to_integer(d_j(7 downto 5))).la + d_j(4 downto 2));
              end if;
              kq_ha <= '0' & (kq_rd(d_fmt, to_integer(d_j(7 downto 5))).ha + d_j(4 downto 2));
              go(D_KQ);
            end if;
          end if;
          case d_kind is
            when DK_F32 =>                         -- F32: the bits as they are
              d_val <= grp(3) & grp(2) & grp(1) & grp(0);
              go(D_STORE);
            when DK_BF16 =>
              d_val <= grp(1) & grp(0) & x"0000";
              go(D_STORE);
            when DK_F16 =>
              fpu_op <= FOP_F16TOF32;
              fpu_a <= x"0000" & grp(1) & grp(0);
              fpu_start <= '1';
              fpu_ret <= D_QMUL;
              go(C_FPU_WAIT);
            when DK_K =>
              null;                                -- (K-quants: above)
            when others =>                         -- Q8_0 / Q4_0 / Q5_0 / IQ4_NL / MXFP4
              if d_have_scale = '0' and d_kind = DK_MX then
                dq_scale <= e8m0_half(grp(0));     -- (a power of two: no FPU)
                d_have_scale <= '1';
              elsif d_have_scale = '0' then
                fpu_op <= FOP_F16TOF32;
                fpu_a <= x"0000" & grp(1) & grp(0);
                fpu_start <= '1';
                fpu_ret <= D_SCALE;
                go(C_FPU_WAIT);
              else
                if d_fmt = 8 then
                  q := resize(signed(grp(2 + to_integer(d_j(4 downto 0)))), 32);
                elsif d_fmt = 39 and d_j < 16 then
                  q := resize(e2m1x2(grp(1 + to_integer(d_j(3 downto 0)))(3 downto 0)), 32);
                elsif d_fmt = 39 then
                  q := resize(e2m1x2(grp(1 + to_integer(d_j(3 downto 0)))(7 downto 4)), 32);
                elsif d_fmt = 6 and d_j < 16 then
                  q := resize(q5v(grp(2 + to_integer(d_j(4 downto 3)))(to_integer(d_j(2 downto 0))),
                              grp(6 + to_integer(d_j(3 downto 0)))(3 downto 0)), 32);
                elsif d_fmt = 6 then
                  q := resize(q5v(grp(2 + to_integer(d_j(4 downto 3)))(to_integer(d_j(2 downto 0))),
                              grp(6 + to_integer(d_j(3 downto 0)))(7 downto 4)), 32);
                elsif d_fmt = 20 and d_j < 16 then
                  q := resize(iq4v(grp(2 + to_integer(d_j(3 downto 0)))(3 downto 0)), 32);
                elsif d_fmt = 20 then
                  q := resize(iq4v(grp(2 + to_integer(d_j(3 downto 0)))(7 downto 4)), 32);
                elsif d_j < 16 then
                  q := resize(signed('0' & grp(2 + to_integer(d_j(3 downto 0)))(3 downto 0)), 32) - 8;
                else
                  q := resize(signed('0' & grp(2 + to_integer(d_j(3 downto 0)))(7 downto 4)), 32) - 8;
                end if;
                assert d_qv = q report "SSNAIL: stale d_qv" severity failure;
                fpu_op <= FOP_I2F;
                fpu_a <= unsigned(d_qv);
                fpu_start <= '1';
                fpu_ret <= D_QMUL;
                go(C_FPU_WAIT);
              end if;
          end case;

        when D_SCALE =>
          dq_scale <= fpu_r;
          d_have_scale <= '1';
          go(D_EMIT);

        when D_QMUL =>
          if d_kind = DK_F16 then
            d_val <= fpu_r;                        -- F16 conversion result
            go(D_STORE);
          else
            fpu_op <= FOP_MUL;                     -- d * q, as F32
            fpu_a <= dq_scale;
            fpu_b <= fpu_r;
            fpu_start <= '1';
            fpu_ret <= D_AFTER;
            go(C_FPU_WAIT);
          end if;

        when D_AFTER =>
          d_val <= fpu_r;
          go(D_STORE);

        when D_STORE =>
          a2 := pz + 4;
          pz <= a2;
          v_n <= v_n - 1;
          v_n_z <= v_n_one;
          v_n_one <= v_n = 2;
          d_j <= d_j + 1;
          d_jl <= d_j + 2 = epg;
          assert d_jl = (d_j + 1 = epg) report "SSNAIL: stale d_jl" severity failure;
          if d_j(3 downto 0) = 15 then
            kq_gs <= '0';                             -- (K: a new 16-group)
          end if;
          -- (a2 = pz + 4 ends a 256-byte block: tested on pz, without the carry)
          if pz(7 downto 0) = 252 or v_n_one then      -- v_n = 1
            -- flush the output written since ostart
            a0 := ostart(27 downto 3) & "000";
            a1 := a2 + 7;
            a1(2 downto 0) := "000";
            wr_addr <= a0;
            wr_len <= resize(a1 - a0, 9);
            mw_lead <= resize(ostart - a0, 9);
            mw_vend <= resize(a2 - a0, 9);
            mw_idx <= a0(7 downto 1);
            dec_addr <= a0;
            ostart <= a2;
            d_unflushed <= false;
            if v_n_one then
              wr_ret <= C_NEXT;
            elsif d_jl then
              wr_ret <= D_GROUP;
            else
              wr_ret <= D_EMIT;
            end if;
            go(C_WR_DEC);
          elsif d_jl then
            d_unflushed <= a2 /= ostart;
            go(D_GROUP);
          else
            d_unflushed <= a2 /= ostart;
            go(D_EMIT_W);                     -- (d_qv follows d_j)
          end if;

        when D_EMIT_W =>
          go(D_EMIT);

        -- ------------------------------------------------------------------
        -- GEMV, phase 1: quantise x to Q8_0 (ssnail_hw.quantize_q8_0)
        -- GEMV set-up from the format (d_fmt): block length (the
        -- assembler's), the tail's terms per row (super-blocks, for
        -- K-quants), and the K-quant state
        when G_SET =>
          if fmt_k(d_fmt) then
            kq_on <= '1';
            g_bl <= to_unsigned(kq_bytes(d_fmt), 8);
            g_nbt <= "000" & g_nb(7 downto 3);
          else
            kq_on <= '0';
            if d_fmt = 8 then
              g_bl <= to_unsigned(34, 8);
            elsif d_fmt = 39 then
              g_bl <= to_unsigned(17, 8);
            elsif d_fmt = 6 then
              g_bl <= to_unsigned(22, 8);
            else
              g_bl <= to_unsigned(18, 8);
            end if;
            g_nbt <= g_nb;
          end if;
          if d_fmt = 10 or d_fmt = 12 or d_fmt = 13 then
            kq_min <= '1';
          else
            kq_min <= '0';
          end if;
          kq_nsb <= "000" & g_nb(7 downto 3);
          for i in 0 to 4 loop
            kq_hwc(i) <= to_unsigned(kq_hword(d_fmt, i), 6);
          end loop;
          -- float weights: the float lane, one tail term a row
          fl_on <= '0'; fl_f32 <= '0'; fl_bf <= '0'; fl_ax <= '0';
          xq_on <= '1';
          fl_n <= n0(12 downto 0); fl_short <= false;
          if d_fmt = 0 or d_fmt = 1 or d_fmt = 30 then
            fl_on <= '1'; xq_on <= '0';
            g_nbt <= to_unsigned(1, 8);
            if d_fmt = 0 then
              fl_f32 <= '1'; g_bl <= to_unsigned(128, 8);
            else
              g_bl <= to_unsigned(64, 8);
            end if;
            if d_fmt = 30 then fl_bf <= '1'; end if;
          end if;
          -- the codebook formats (IQ front end)
          kq_kr <= '0'; iq_on <= '0'; kq_wo <= (others => '0'); kq_dsh <= "00";
          if fmt_iq(d_fmt) then
            iq_on <= '1';
            kq_wo <= to_unsigned(2, 8);
            if d_fmt = 18 then kq_dsh <= "10"; elsif d_fmt /= 21 then kq_dsh <= "11"; end if;
          elsif fmt_k(d_fmt) then
            kq_kr <= '1';
          end if;
          if d_fmt = 18 or d_fmt = 21 then iq3 <= '1'; else iq3 <= '0'; end if;
          if d_fmt = 16 or d_fmt = 18 then iq_xxs <= '1'; else iq_xxs <= '0'; end if;
          if d_fmt = 16 or d_fmt = 17 or d_fmt = 18 then iq_ks <= '1'; else iq_ks <= '0'; end if;
          if d_fmt = 17 or d_fmt = 18 or d_fmt = 21 then iq_2w <= '1'; else iq_2w <= '0'; end if;
          if d_fmt = 17 then iq_u16 <= '1'; else iq_u16 <= '0'; end if;
          if d_fmt = 21 or d_fmt = 22 then iq_hb <= '1'; else iq_hb <= '0'; end if;
          case to_integer(d_fmt) is
            when 17 | 21 => iq_base <= "01";
            when 22 => iq_base <= "10";
            when others => iq_base <= "00";
          end case;
          kq_pass <= '0'; kq_sub <= (others => '0'); kq_amax <= (others => '0');
          go(G_QFILL0);

        when G_QFILL0 =>
          assert not qf_vld report "SSNAIL: g_amax update pending" severity failure;
          g_j <= (others => '0');
          g_amax <= (others => '0');
          qf_hit <= ld_valid = '1' and px(27 downto 8) = ld_block;
          go(G_QFILL);

        when G_QFILL =>
          assert qf_hit = (ld_valid = '1' and px(27 downto 8) = ld_block)
            report "SSNAIL: stale qf_hit" severity failure;
          if g_j = 32 and fl_on = '1' then             -- (float: x as it is)
            gblk <= gblk + 1;
            assert g_qlast = (gblk + 1 = g_nb) report "SSNAIL: stale g_qlast" severity failure;
            if g_qlast then
              go(G_ROW0);
            else
              go(G_QFILL0);
            end if;
          elsif g_j = 32 and kq_on = '1' and kq_pass = '0' then
            go(G_KAM);                                 -- (K: amax over 256 first)
          elsif g_j = 32 and kq_on = '1' then
            g_j <= (others => '0');                    -- (K: d and id known)
            go(G_QQ);
          elsif g_j = 32 then
            go(G_QAM);                                 -- (the last element's qf_v
                                                       -- lands in g_amax now)
          elsif not qf_hit then                       -- px's block is not loaded
            a0 := px(27 downto 3) & "000";
            a1 := (px(27 downto 8) + 1) & x"00";
            rd_addr <= a0;
            rd_len <= resize(a1 - a0, 9);
            rd_sel <= "01";
            dec_addr <= a0;
            ld_block <= px(27 downto 8);
            ld_valid <= '1';
            qf_hit <= true;
            rd_ret <= G_QFILL;
            go(C_RD_DEC);
          else
            fv := bufx(to_integer(px(7 downto 1) + 1)) & bufx(to_integer(px(7 downto 1)));
            xb(to_integer(g_j)) <= fv;
            xw_we := true; xw_a := gblk(6 downto 0) & g_j(4 downto 0); xw_d := fv;
            -- |x| ordering = integer ordering of the low 31 bits
            qf_v <= fv(30 downto 0);
            qf_vld <= true;
            px <= px + 4;
            qf_hit <= px(7 downto 0) < 252;             -- px + 4 in the same block
            g_j <= g_j + 1;
          end if;

        when G_QAM =>
          assert not qf_vld report "SSNAIL: g_amax update pending" severity failure;
          fpu_op <= FOP_DIV;                           -- d = amax / 127
          fpu_a <= '0' & g_amax;
          fpu_b <= x"42FE0000";
          fpu_start <= '1';
          fpu_ret <= G_QID;
          go(C_FPU_WAIT);

        -- K-quants: the amax of 32 more elements (g_amax is complete now);
        -- after 256, d = amax / 127 as for Q8_0
        when G_KAM =>
          assert not qf_vld report "SSNAIL: g_amax update pending" severity failure;
          if g_amax > kq_amax then
            kq_amax <= g_amax;
          end if;
          kq_sub <= kq_sub + 1;
          if kq_sub = 7 then
            go(G_KAM2);                                -- (kq_amax complete next)
          else
            go(G_QFILL0);
          end if;

        when G_KAM2 =>
          fpu_op <= FOP_DIV;
          fpu_a <= '0' & kq_amax;
          fpu_b <= x"42FE0000";
          fpu_start <= '1';
          fpu_ret <= G_QID;
          go(C_FPU_WAIT);

        -- K-quants: the super-block's scale is F32 (not rounded to F16);
        -- read its 256 elements again, to quantise them
        when G_KX =>
          dxs(to_integer(gblk(7 downto 3))) <= g_d;
          px <= px - 1024;
          kq_pass <= '1';
          go(G_QFILL0);

        when G_QID =>
          g_d <= fpu_r;
          assert fr_z = (fpu_r(30 downto 0) = 0) report "SSNAIL: stale fr_z" severity failure;
          if fr_z and kq_on = '1' then
            g_id <= (others => '0');
            go(G_KX);
          elsif fr_z then
            g_id <= (others => '0');                   -- id = d ? 1/d : 0
            go(G_QD16);
          else
            fpu_op <= FOP_DIV;
            fpu_a <= x"3F800000";
            fpu_b <= fpu_r;
            fpu_start <= '1';
            fpu_ret <= G_QID2;
            go(C_FPU_WAIT);
          end if;

        when G_QID2 =>
          g_id <= fpu_r;
          if kq_on = '1' then
            go(G_KX);
          else
            go(G_QD16);
          end if;

        when G_QD16 =>
          fpu_op <= FOP_F32TOF16;                      -- the stored scale is F16
          fpu_a <= g_d;
          fpu_start <= '1';
          fpu_ret <= G_QDX;
          go(C_FPU_WAIT);

        when G_QDX =>
          fpu_op <= FOP_F16TOF32;
          fpu_a <= fpu_r;
          fpu_start <= '1';
          fpu_ret <= G_QDX2;
          go(C_FPU_WAIT);

        when G_QDX2 =>
          dxs(to_integer(gblk)) <= fpu_r;
          g_j <= (others => '0');
          go(G_QQ);

        -- the block's 32 elements quantised by the x quantiser (xq_*): x * id
        -- on the float lane's multiplier, roundf, into qx (and the 16-sums)
        when G_QQ =>
          if not xq_busy then                          -- (the last block stored)
            xq_iss <= '1';
            xq_j <= (others => '0');
            xq_id <= g_id;
            xq_blk <= gblk;
            go(G_QQW);
          end if;
        when G_QQW =>                                  -- (xb free once issued)
          if xq_iss = '0' then
            gblk <= gblk + 1;
            if kq_on = '1' then
              kq_sub <= kq_sub + 1;
              if kq_sub = 7 then                       -- super-block done
                kq_pass <= '0';
                kq_amax <= (others => '0');
              end if;
            end if;
            assert g_qlast = (gblk + 1 = g_nb) report "SSNAIL: stale g_qlast" severity failure;
            if g_qlast then
              go(G_ROW0);
            else
              go(G_QFILL0);
            end if;
          end if;

        -- GEMV, phase 2: each row, block by block (ssnail_hw.gemv_quant)
        when G_ROW0 =>
          -- Row phase.  Decode the region of the first and last weight
          -- bytes once: the stream needs the matrix in a single region.
          -- (First, the x quantiser's last results in.)
          if xq_busy then
            null;
          else
          xq_on <= '0';
          ld_valid <= '0';
          out_loaded <= '0';
          g_r <= (others => '0');
          g_end <= g_rows = 0; g_last <= g_rows = 1;
          gblk <= (others => '0');
          a0 := ps(27 downto 3) & "000";
          str_base <= a0;
          sr_next <= a0;
          sr_segst <= a0;
          sr_segs <= (others => '0');
          g2_ret <= G2_WAIT;
          -- Setup a small serial multiplier.  Full 32-bit rows are needed
          -- for as_blocks; only low 20 bits were used for byte-span above.
          if kq_on = '1' then
            g_mul_nb <= kq_nsb;                       -- super-blocks per row
          else
            g_mul_nb <= g_nb;
          end if;
          g_mul_a32 <= g_rows;
          g_mul_p32 <= (others => '0');
          g_mul_p28 <= (others => '0');
          -- (block bytes) * rows20, from registers
          g_mul_a28 <= resize(g_rows(19 downto 0) * g_bl, 28);
          go(G_ROW_MUL);
          end if;
        when G_ROW_MUL =>
          -- Add a shifted multiplicand for each set bit of blocks/row.
          -- Arithmetic is modulo 2^32 and 2^28, as in the old resize().
          if g_mul_nb(0) = '1' then
            g_mul_p32 <= g_mul_p32 + g_mul_a32;
            g_mul_p28 <= g_mul_p28 + g_mul_a28;
          end if;
          g_mul_a32 <= g_mul_a32(30 downto 0) & '0';
          g_mul_a28 <= g_mul_a28(26 downto 0) & '0';
          g_mul_nb <= '0' & g_mul_nb(7 downto 1);
          if g_mul_nb(7 downto 1) = 0 then
            -- Final partial product is registered at this edge.  Consume
            -- it in the following state, not in this same cycle.
            go(G_ROW_ADDR);
          end if;
        when G_ROW_ADDR =>
          a0 := ps(27 downto 3) & "000";
          a2 := ps + g_mul_p28;
          a1 := a2 + 7;
          a1(2 downto 0) := "000";
          sr_end <= a1;
          sr_lend <= a1;
          dec_addr <= a0;
          go(G2_D1);
        when G2_D1 =>
          go(G2_D2);                          -- decode of the start
        when G2_D2 =>
          if dec_ok = '0' then
            err <= ERR_ADDRESS;
            go(C_END);
          else
            str_local <= dec_local;
            str_is_sd <= dec_is_sd;
            dec_addr <= sr_lend - 8;                -- and of the last group
            go(G2_D2W);
          end if;
        when G2_D2W =>
          go(G2_D3);                          -- its decode
        when G2_D3 =>
          if dec_ok = '0' or dec_is_sd /= str_is_sd then
            err <= ERR_ADDRESS;                     -- straddles two regions
            go(C_END);
          else
            -- start the pipeline
            g2 <= '1';
            wf_w <= (others => '0'); wf_r <= (others => '0');
            wf_z <= true; wf_o <= false;
            sr_inflight <= (others => '0');
            rq_w <= (others => '0'); rq_r <= (others => '0');
            -- (as_flags depends on a block length only through >= 4)
            as_rem <= g_bl;
            as_f <= as_flags(to_integer(ps(2 downto 0)), 34);
            as_skip <= ps(2 downto 0);
            as_full <= '0'; pb_v <= '0'; ub_full <= '0';
            kq_wh <= '0'; kq_wp <= kq_wo; kq_full <= "00"; kq_fset <= '0';
            iq_st <= IQ_IDLE; iq_h <= '0'; iq_p <= (others => '0'); iq_full <= '0';
            iq_v1 <= '0'; iq_v2 <= '0'; iq_v3 <= '0';
            kq_hs <= KH_IDLE; kq_hh <= '0'; kq_hok <= "00"; kq_hsb <= (others => '0');
            kq_hwl <= kq_hwc;
            kq_rh <= '0'; kq_p <= (others => '0');
            kq_c1 <= '0'; kq_c2 <= '0'; kq_c3 <= '0'; kq_s1 <= (others => '0');
            kq_pre <= '0';
            kq_fs <= KF_IDLE; kq_fgo <= '0'; kq_fsb <= (others => '0');
            tl_sub <= false;
            as_blocks <= g_mul_p32;
            if g_mul_p32 /= 0 and fl_on = '0' then as_any <= '1'; else as_any <= '0'; end if;
            if fl_on = '1' then fl_st <= FL_RUN; else fl_st <= FL_DONE; end if;
            fl_skip <= ps(2 downto 1);
            fl_c <= (others => '0'); fl_cl <= false; fl_k <= (others => '0'); fl_hv <= '0';
            fl_cz <= true; fl_first <= '1'; fl_bk <= '0'; cb_st <= CB_IDLE;
            fl_rr <= g_rows; fl_rl <= g_rows = 1;
            mc_busy <= '0'; mc_done <= '0'; mc_blk <= (others => '0');
            mc_scale_ok <= '0';
            mc_sblk <= (others => '0'); kq_sp <= (others => '0'); kq_srh <= '0';
            mc_nq <= "00"; mq_v <= "00"; mq_scok <= "00";
            mq_w <= '0'; mq_r <= '0'; mq_ss <= '0'; fpu3_busy <= '0';
            tm_busy <= '0'; f2_term <= '0'; th_v <= '0';
            tl_full <= '0';
            g_r <= (others => '0');
            g_end <= g_rows = 0; g_last <= g_rows = 1;
            go(g2_ret);
          end if;

        when G2_WAIT =>
          -- the stream reader may issue here (see below); the tail takes the
          -- next finished block
          assert g_end = (g_r = g_rows) report "SSNAIL: stale g_end" severity failure;
          if g_end then                               -- g_r = g_rows
            go(G2_END);
          elsif tl_full = '1' and kq_min = '1' and kq_on = '1' and not tl_sub then
            fpu_op <= FOP_ADD;                    -- K-quants: t = t1 - t2 first
            fpu_a <= tl_term;
            fpu_b <= (not tl_term2(31)) & tl_term2(30 downto 0);
            fpu_start <= '1';
            fpu_ret <= G2_KS;
            go(C_FPU_WAIT);
          elsif tl_full = '1' then
            if tl_blk = 0 then
              g_accv <= tl_term;                    -- the first term as it is
              go(G2_T3);
            else
              fpu_op <= FOP_ADD;                    -- acc = acc + term
              fpu_a <= g_accv;
              fpu_b <= tl_term;
              fpu_start <= '1';
              fpu_ret <= G2_T2;
              go(C_FPU_WAIT);
            end if;
          end if;
        when G2_T1 =>
          go(G2_WAIT);
        when G2_KS =>
          tl_term <= fpu_r;
          tl_sub <= true;
          go(G2_WAIT);
        when G2_T2 =>
          g_accv <= fpu_r;
          go(G2_T3);
        when G2_T3 =>                         -- (tl_full_clr: cs_t3)
          tl_sub <= false;
          assert tl_last = (tl_blk + 1 = g_nbt) report "SSNAIL: stale tl_last" severity failure;
          if tl_last then
            go(G_OUT);                        -- row done: output it
          else
            go(G2_WAIT);
          end if;
        when G2_END =>
          -- all rows out: let any trailing stream reads land, then stop
          if rq_w = rq_r and sr_inflight = 0 and out_z then
            g2 <= '0';
            go(C_NEXT);
          end if;

        when G_OUT =>
          assert g_have_old = (out_loaded = '1' and pz(27 downto 8) = out_block)
            report "SSNAIL: stale g_have_old" severity failure;
          assert not g_have_old or g_addz = '0'
            or g_oldv = buf_in(to_integer(pz(7 downto 1) + 1)) & buf_in(to_integer(pz(7 downto 1)))
            report "SSNAIL: stale g_oldv" severity failure;
          if g_addz = '1' and not g_have_old then
            -- bring in the existing outputs of this 256-byte block
            a0 := pz(27 downto 3) & "000";
            a1 := (pz(27 downto 8) + 1) & x"00";
            rd_addr <= a0;
            rd_len <= resize(a1 - a0, 9);
            rd_sel <= "00";
            dec_addr <= a0;
            out_block <= pz(27 downto 8);
            out_loaded <= '1';
            rd_ret <= G_OUT;
            go(C_RD_DEC);
          elsif g_addz = '1' then
            fpu_op <= FOP_ADD;                         -- y = acc + y_old
            fpu_a <= g_accv;
            fpu_b <= g_oldv;
            fpu_start <= '1';
            fpu_ret <= G_OUT2;
            go(C_FPU_WAIT);
          else
            fpu_r <= g_accv;
            go(G_OUT2);
          end if;

        when G_OUT2 =>
          if g_f16 = '1' then
            fpu_op <= FOP_F32TOF16;
            fpu_a <= fpu_r;
            fpu_start <= '1';
            fpu_ret <= G_OUT3;
            go(C_FPU_WAIT);
          else
            go(G_OUT3);
          end if;

        when G_OUT3 =>
          g_val <= fpu_r;
          go(G_OUT4);

        when G_OUT4 =>
          if g_f16 = '1' then
            a2 := pz + 2;
          else
            a2 := pz + 4;
          end if;
          pz <= a2;
          g_r <= g_r + 1;
          assert g_last = (g_r + 1 = g_rows) report "SSNAIL: stale g_last" severity failure;
          g_end <= g_last;
          g_last <= g_r + 2 = g_rows;
          -- (a2 ends a 256-byte block: tested on pz, without the carry)
          if (g_f16 = '1' and pz(7 downto 0) = 254) or (g_f16 = '0' and pz(7 downto 0) = 252)
            or g_last then                            -- g_r + 1 = g_rows
            a0 := ostart(27 downto 3) & "000";
            a1 := a2 + 7;
            a1(2 downto 0) := "000";
            wr_addr <= a0;
            wr_len <= resize(a1 - a0, 9);
            mw_lead <= resize(ostart - a0, 9);
            mw_vend <= resize(a2 - a0, 9);
            mw_idx <= a0(7 downto 1);
            dec_addr <= a0;
            ostart <= a2;
            wr_ret <= G2_WAIT;
            go(C_WR_DEC);
          else
            go(G2_WAIT);
          end if;

        -- ------------------------------------------------------------------
        -- Element fetch: ef_val = F32 at ef_addr (F16 converted if ef_f16),
        -- through bufx with whole-block loads.
        when EF_START =>
          assert ef_miss = (ld_valid = '0' or ef_addr(27 downto 8) /= ld_block)
            report "SSNAIL: stale ef_miss" severity failure;
          if ef_miss then
            -- the whole block: unlike the streaming fetchers, accesses here
            -- can go backwards within a block (parameter block, then q)
            a0 := ef_addr(27 downto 8) & x"00";
            a1 := (ef_addr(27 downto 8) + 1) & x"00";
            rd_addr <= a0;
            rd_len <= resize(a1 - a0, 9);
            rd_sel <= "01";
            dec_addr <= a0;
            ld_block <= ef_addr(27 downto 8);
            ld_valid <= '1';
            rd_ret <= EF_START;
            go(C_RD_DEC);
          elsif ef_f16 = '1' then
            fpu_op <= FOP_F16TOF32;
            fpu_a <= x"0000" & bufx(to_integer(ef_addr(7 downto 1)));
            fpu_start <= '1';
            fpu_ret <= EF_DONE;
            go(C_FPU_WAIT);
          else
            ef_val <= bufx(to_integer(ef_addr(7 downto 1) + 1)) & bufx(to_integer(ef_addr(7 downto 1)));
            go(ef_ret);
          end if;
        when EF_DONE =>
          ef_val <= fpu_r;
          go(ef_ret);

        -- ROPE: load the cos/sin row, then rotate pairs through the engine
        when RO_CS =>
          if cs_i = rope_hd then
            bx <= ea_x; px <= ea_x; pz <= ea_x; v_n <= n0; v_n_z <= n0_z; v_n_one <= n0_one;
            o16 <= '0'; two_ops <= '0'; has_b <= '0'; has_out <= '1';
            ve_kind <= K_ROPE; rope_j <= (others => '0');
            ve_ret <= C_NEXT;
            go(V_CHUNK);
          else
            ef_ret <= RO_CS2;
            go(EF_START);
          end if;
        when RO_CS2 =>
          csv(to_integer(cs_i)) <= ef_val;
          cs_i <= cs_i + 1;
          ef_addr <= ef_addr + 4;
          go(RO_CS);

        when E_R1 =>                                -- a = x0 c; b = x1 s
          rp_a <= fpu_r;
          fpu_op <= FOP_MUL; fpu_a <= x1v; fpu_b <= csv(to_integer(rope_j) + 1);
          fpu_start <= '1'; fpu_ret <= E_R2; go(C_FPU_WAIT);
        when E_R2 =>                                -- r0 = a - b
          fpu_op <= FOP_ADD; fpu_a <= rp_a; fpu_b <= (not fpu_r(31)) & fpu_r(30 downto 0);
          fpu_start <= '1'; fpu_ret <= E_R3; go(C_FPU_WAIT);
        when E_R3 =>                                -- x0 s
          rp0 <= fpu_r;
          fpu_op <= FOP_MUL; fpu_a <= ex; fpu_b <= csv(to_integer(rope_j) + 1);
          fpu_start <= '1'; fpu_ret <= E_R4; go(C_FPU_WAIT);
        when E_R4 =>                                -- x1 c
          rp_b <= fpu_r;
          fpu_op <= FOP_MUL; fpu_a <= x1v; fpu_b <= csv(to_integer(rope_j));
          fpu_start <= '1'; fpu_ret <= E_R5; go(C_FPU_WAIT);
        when E_R5 =>                                -- r1 = x0 s + x1 c
          fpu_op <= FOP_ADD; fpu_a <= rp_b; fpu_b <= fpu_r;
          fpu_start <= '1'; fpu_ret <= E_R6; go(C_FPU_WAIT);
        when E_R6 =>
          v_i <= v_i + 2;
          pf_go := true;
          pf_x := vix + 8; pf_y := viy + 8; pf_b := vib + 8; pf_i := v_i + 2;
          if rope_j + 2 = rope_hd then
            rope_j <= (others => '0');
          else
            rope_j <= rope_j + 2;
          end if;
          go(V_EL);

        when AM_DONE =>
          if instr(11 downto 8) /= x"F" then
            rf_r(to_integer(instr(11 downto 8))) <= am_idx;
          end if;
          go(C_NEXT);

        -- ------------------------------------------------------------------
        -- ATTN (ssnail_hw.attention_head, per head)
        when A_PRM =>                               -- read parameter word at_pi
          ef_ret <= A_PRM2;
          go(EF_START);
        when A_PRM2 =>
          case to_integer(at_pi) is
            when 0 => at_k <= ef_val(27 downto 0);
            when 1 => at_v <= ef_val(27 downto 0);
            when 2 => at_nh <= ef_val;
            when 3 => at_nkv <= ef_val;
            when 4 => at_hd <= ef_val;
            when others => at_fmt <= ef_val;
          end case;
          ef_addr <= ef_addr + 4;
          at_pi <= at_pi + 1;
          if at_pi = 5 then
            go(A_CHK);
          else
            go(A_PRM);
          end if;
        when A_CHK =>                               -- check the parameters
          -- (K / V are streamed: 8-aligned, and a head's row 8-byte sized)
          at_bad <= at_hd = 0 or at_hd > 256 or at_nkv = 0 or at_nh = 0 or at_pos >= 1024
                    or at_nh(15 downto 0) < at_nkv(15 downto 0)
                    or at_k(2 downto 0) /= 0 or at_v(2 downto 0) /= 0
                    or (at_fmt = 1 and at_hd(1 downto 0) /= 0) or at_hd(0) /= '0';
          go(A_RS0);
        when A_RS0 =>
          if at_bad then
            err <= ERR_OPCODE;
            go(C_END);
          else
            -- K/V row = n_kv_heads * head_dim elements
            if at_fmt = 1 then
              at_rowb <= resize(at_nkv(13 downto 0) * at_hd(13 downto 0), 27) & '0';
              at_kv_stride <= at_hd(26 downto 0) & '0';
            else
              at_rowb <= resize(at_nkv(12 downto 0) * at_hd(12 downto 0), 26) & "00";
              at_kv_stride <= at_hd(25 downto 0) & "00";
            end if;
            fpu_op <= FOP_I2F; fpu_a <= at_hd; fpu_start <= '1';
            fpu_ret <= A_RS1; go(C_FPU_WAIT);
          end if;
        when A_RS1 =>                               -- rs = 1 / sqrt(hd)
          fpu_op <= FOP_SQRT; fpu_a <= fpu_r; fpu_start <= '1';
          fpu_ret <= A_RS2; go(C_FPU_WAIT);
        when A_RS2 =>
          fpu_op <= FOP_DIV; fpu_a <= x"3F800000"; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= A_RS3; go(C_FPU_WAIT);
        when A_RS3 =>
          at_rs <= fpu_r;
          -- group = n_heads / n_kv_heads, by repeated subtraction
          at_group <= (others => '0');
          at_gc <= at_nh(15 downto 0);
          at_ge <= at_nh(15 downto 0) >= at_nkv(15 downto 0);
          at_span <= (others => '0');
          at_sm <= at_pos(9 downto 0);
          at_ma <= at_rowb;
          go(A_SPAN);
        when A_SPAN =>                              -- at_span = at_pos * at_rowb
          if at_sm(0) = '1' then
            at_span <= at_span + at_ma;
          end if;
          at_ma <= at_ma(26 downto 0) & '0';
          at_sm <= '0' & at_sm(9 downto 1);
          if at_sm(9 downto 1) = 0 then
            go(A_SPAN2);
          end if;
        when A_SPAN2 =>
          at_spl <= at_span + at_kv_stride;         -- (to a head's last byte)
          go(A_GRP);
        when A_GRP =>
          assert at_ge = (at_gc >= at_nkv(15 downto 0)) report "SSNAIL: stale at_ge" severity failure;
          if at_ge then                             -- at_gc >= at_nkv
            at_gc <= at_gc - at_nkv(15 downto 0);
            at_ge <= at_gc - at_nkv(15 downto 0) >= at_nkv(15 downto 0);
            at_group <= at_group + 1;
          else
            at_h <= (others => '0');
            at_hend <= at_nh(15 downto 0) = 0;
            at_kvh <= (others => '0');
            at_kv_offset <= (others => '0');
            at_qhead_addr <= ea_y;
            at_gc <= (others => '0');
            pz <= ea_z; ostart <= ea_z;
            go(A_HEAD);
          end if;

        when A_HEAD =>                              -- load q for head at_h
          assert at_hend = (at_h = at_nh(15 downto 0)) report "SSNAIL: stale at_hend" severity failure;
          if at_hend then                           -- at_h = at_nh
            go(C_NEXT);
          else
            at_i <= (others => '0');
            -- at_qhead_addr = ea_y + at_h*at_hd*4 (mod 2^28).
            ef_addr <= at_qhead_addr;
            ef_f16 <= '0';
            go(A_Q);
          end if;
        when A_Q =>
          assert at_iend = (at_i = at_hd(8 downto 0)) report "SSNAIL: stale at_iend" severity failure;
          if at_iend then                           -- at_i = at_hd
            at_t <= (others => '0');
            at_vp <= '0';
            go(A_STR0);                             -- stream K
          else
            ef_ret <= A_Q2;
            go(EF_START);
          end if;
        when A_Q2 =>
          xw_we := true; xw_a := "000" & at_i; xw_d := ef_val;   -- (q: the float lane's x)
          at_i <= at_i + 1;
          ef_addr <= ef_addr + 4;
          go(A_Q);

        -- K or V of this head as one strided stream (rows at_rowb apart, a
        -- head's row each) into the float lane: K's rows dotted with q
        -- (scores), or V's rows times w_t into outv (the output pass)
        when A_STR0 =>
          if at_vp = '1' then
            at_ea <= at_v + at_kv_offset;
          else
            at_ea <= at_k + at_kv_offset;
          end if;
          go(A_STR);
        when A_STR =>
          ps <= at_ea;
          str_base <= at_ea; sr_next <= at_ea; sr_segst <= at_ea;
          sr_end <= at_ea + at_kv_stride;
          sr_lend <= at_ea + at_spl;
          sr_stride <= at_rowb;
          sr_segs <= at_pos(9 downto 0);
          dec_addr <= at_ea;
          g_rows <= resize(at_pos1, 32);
          kq_on <= '0'; kq_kr <= '0'; iq_on <= '0'; xq_on <= '0';
          fl_on <= '1'; fl_ax <= at_vp; fl_bf <= '0';
          if at_fmt = 1 then fl_f32 <= '0'; else fl_f32 <= '1'; end if;
          fl_n <= resize(at_hd(8 downto 0), 13);
          fl_short <= at_hd(8 downto 0) < 12;
          fl_wv <= '0';
          if at_vp = '1' then g2_ret <= A_O_F; else g2_ret <= A_S_T; end if;
          go(G2_D1);
        -- the stream's last reads in and the lane done: stop the pipeline
        when A_SE =>
          if rq_w = rq_r and sr_inflight = 0 and out_z and fl_st = FL_DONE then
            g2 <= '0';
            fl_ax <= '0';
            if at_vp = '1' then
              at_i <= (others => '0');
              go(A_O_W);
            else
              go(A_E_T);
            end if;
          end if;

        -- scores: s_t = dot8(k_t, q) * rs, from the lane; track the maximum
        when A_S_T =>
          assert at_tend = (at_t = at_pos(15 downto 0) + 1) report "SSNAIL: stale at_tend" severity failure;
          if at_tend then                           -- at_t = at_pos + 1
            at_t <= (others => '0');
            ve_first <= '1';
            go(A_SE);
          else
            go(A_S_W);
          end if;
        when A_S_W =>
          if tl_full = '1' then
            tl_full_clr := '1';
            fpu_op <= FOP_MUL; fpu_a <= tl_term; fpu_b <= at_rs; fpu_start <= '1';
            fpu_ret <= A_S_SC; go(C_FPU_WAIT);
          end if;
        when A_S_SC =>
          sw_we := true; sw_a := at_t(9 downto 0); sw_d := fpu_r;
          if at_t(9 downto 0) = 0 then sarr0 <= fpu_r; end if;
          assert fr_mlt = flt(at_m, fpu_r) report "SSNAIL: stale fr_mlt" severity failure;
          if at_t = 0 or fr_mlt then
            at_m <= fpu_r;
          end if;
          at_t <= at_t + 1;
          go(A_S_T);

        -- e_t = EXP(s_t - m), by the softmax engine; z = seq_sum(e), here
        when A_E_T =>
          sx_on <= '1';
          sx_nm <= (not at_m(31)) & at_m(30 downto 0);
          ve_first <= '1';
          go(A_E_W);
        when A_E_W =>
          assert at_tend = (at_t = at_pos(15 downto 0) + 1) report "SSNAIL: stale at_tend" severity failure;
          if at_tend then                           -- at_t = at_pos + 1
            fpu_op <= FOP_DIV; fpu_a <= x"3F800000"; fpu_b <= at_acc; fpu_start <= '1';
            fpu_ret <= A_E_R; go(C_FPU_WAIT);
          elsif sx_wcnt /= at_t then
            go(A_E_P);
          end if;
        when A_E_P =>
          at_t <= at_t + 1;
          if ve_first = '1' then
            at_acc <= sx_fifo(to_integer(at_t(3 downto 0))); ve_first <= '0';
            go(A_E_W);
          else
            fpu_op <= FOP_ADD; fpu_a <= at_acc; fpu_b <= sx_fifo(to_integer(at_t(3 downto 0)));
            fpu_start <= '1'; fpu_ret <= A_E_3; go(C_FPU_WAIT);
          end if;
        when A_E_3 =>
          at_acc <= fpu_r;
          go(A_E_W);
        when A_E_R =>                               -- r = 1 / z; then V
          at_r <= fpu_r;
          sx_on <= '0';
          at_t <= (others => '0');
          at_vp <= '1';
          go(A_STR0);

        -- out = out + w_t * v_t, sequentially over t, in the lane: w_t =
        -- e_t * r to it a row ahead (fl_wq while fl_wv)
        when A_O_F =>
          assert at_tend = (at_t = at_pos(15 downto 0) + 1) report "SSNAIL: stale at_tend" severity failure;
          if at_tend then                           -- every w_t given
            go(A_SE);
          elsif fl_wv = '0' then
            go(A_O_F1);
          end if;
        when A_O_F1 =>
          assert at_sv = sarr(to_integer(at_t(9 downto 0))) report "SSNAIL: stale at_sv" severity failure;
          fpu_op <= FOP_MUL; fpu_a <= at_sv; fpu_b <= at_r;
          fpu_start <= '1'; fpu_ret <= A_O_F2; go(C_FPU_WAIT);
        when A_O_F2 =>
          fl_wq <= fpu_r;
          fl_wv <= '1';
          at_t <= at_t + 1;
          go(A_O_F);
        when A_O_W =>
          go(A_WR);

        -- write this head's output: through buf, flushed at 256-byte
        -- boundaries and at the end of the head
        when A_WR =>
          assert at_iend = (at_i = at_hd(8 downto 0)) report "SSNAIL: stale at_iend" severity failure;
          if at_iend then                           -- at_i = at_hd
            go(A_HNEXT);
          else
            a2 := pz + 4;
            pz <= a2;
            at_i <= at_i + 1;
            -- (a2 = pz + 4 ends a 256-byte block: tested on pz, without the carry)
            assert at_inx = (at_i + 1 = at_hd(8 downto 0)) report "SSNAIL: stale at_inx" severity failure;
            if pz(7 downto 0) = 252 or at_inx then
              a0 := ostart(27 downto 3) & "000";
              a1 := a2 + 7;
              a1(2 downto 0) := "000";
              wr_addr <= a0;
              wr_len <= resize(a1 - a0, 9);
              mw_lead <= resize(ostart - a0, 9);
              mw_vend <= resize(a2 - a0, 9);
              mw_idx <= a0(7 downto 1);
              dec_addr <= a0;
              ostart <= a2;
              wr_ret <= A_WR;
              go(C_WR_DEC);
            end if;
          end if;
        when A_WR2 =>
          go(A_HNEXT);
        when A_HNEXT =>
          at_h <= at_h + 1;
          at_hend <= at_h + 1 = at_nh(15 downto 0);
          at_qhead_addr <= at_qhead_addr + (at_hd(25 downto 0) & "00");
          if at_gc + 1 = at_group then
            at_gc <= (others => '0');
            at_kvh <= at_kvh + 1;
            at_kv_offset <= at_kv_offset + at_kv_stride;
          else
            at_gc <= at_gc + 1;
          end if;
          go(A_HEAD);

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
            go(C_IDLE);
          else
            go(C_FETCH_SETUP);
          end if;

        when C_END =>
          -- Job finished (HALT, fault or abort).  PC stays on the
          -- instruction concerned.
          done <= '1';
          done_tgl <= not done_tgl;
          go(C_IDLE);
      end case;

      -- ATTN position state (see at_tend): sarr is written at the old at_t
      -- only, so the read at the new one sees the value it will hold
      at_pos1 <= at_pos(15 downto 0) + 1;
      -- These read-aheads are addressed by the state alone (never by the
      -- branch taken in it), so no condition reaches a RAM address.  Every
      -- state that resets or advances the counter reloads them as if it
      -- had; when a branch does not, the counter's next writer reloads them
      -- before any use (asserted at each use).
      case cstate is
        when A_HEAD | A_S_T | A_O_W =>                 -- at_i <= 0
          at_iend <= at_hd(8 downto 0) = 0;
          at_inx  <= at_hd(8 downto 0) = 1;
        when A_Q2 | A_WR =>                            -- at_i <= at_i + 1
          at_iend <= at_i + 1 = at_hd(8 downto 0);
          at_inx  <= at_i + 2 = at_hd(8 downto 0);
        when others => null;
      end case;
      -- sarr is read only at at_t + 1 (a second, constant-index read would
      -- turn the LUT RAM into 32k flip-flops); sarr(0) comes from sarr0
      sa := sx_icnt(9 downto 0);
      case cstate is
        when A_Q | A_S_T | A_E_R =>                    -- at_t <= 0
          at_tend <= at_pos1 = 0;
          at_sv <= sarr0;
        when A_S_SC | A_O_F2 =>                        -- at_t <= at_t + 1
          -- (A_S_SC writes sarr at at_t, not at at_t + 1)
          assert sx_on = '0' report "SSNAIL: sarr read address clash" severity failure;
          sa := at_t(9 downto 0) + 1;
          at_tend <= at_t + 1 = at_pos1;
          at_sv <= sarr(to_integer(sa));
        when A_E_P =>                                  -- at_t <= at_t + 1 (no read)
          at_tend <= at_t + 1 = at_pos1;
        when others => null;
      end case;

      -- Element operands for V_EL (see pre_x): element v_i's X (and the next
      -- X, for ROPE), Y and B, and v_i = v_e, likewise by state
      for n in 0 to 7 loop
        assert vxw(n) = vix(7 downto 1) + n and vyw(n) = viy(7 downto 1) + n
          and vbw(n) = vib(7 downto 1) + n
          report "SSNAIL: stale vxw/vyw/vbw" severity failure;
      end loop;
      if pf_go then
        vix <= pf_x; viy <= pf_y; vib <= pf_b;
        for n in 0 to 7 loop
          vxw(n) <= pf_x(7 downto 1) + n;
          vyw(n) <= pf_y(7 downto 1) + n;
          vbw(n) <= pf_b(7 downto 1) + n;
        end loop;
      end if;
      -- Word addresses of the four X halves, two Y and two B halves
      -- (by the registered decodes of cstate: see cs_pf)
      pf_ok := cs_pf;
      if cs_el0 then                                   -- v_i <= 0
        for k in 0 to 3 loop
          pa_x(k) := px(7 downto 1) + k;
          pa_y(k) := py(7 downto 1) + k;
          pa_b(k) := pb(7 downto 1) + k;
        end loop;
        pf_i := (others => '0');
      elsif cs_r6 then                                 -- v_i <= v_i + 2
        for k in 0 to 3 loop
          pa_x(k) := vxw(4 + k); pa_y(k) := vyw(4 + k); pa_b(k) := vbw(4 + k);
        end loop;
        pf_i := v_i + 2;
      else                     -- V_EL, V_ELST, E_ACC, E_ACC2: v_i <= v_i + 1
        for k in 0 to 3 loop
          pa_x(k) := vxw(2 + k); pa_y(k) := vyw(2 + k); pa_b(k) := vbw(2 + k);
        end loop;
        pf_i := v_i + 1;
      end if;
      if pf_ok then
        v_done <= pf_i = v_e;
        pre_x  <= bufx(to_integer(pa_x(1))) & bufx(to_integer(pa_x(0)));
        pre_x1 <= bufx(to_integer(pa_x(3))) & bufx(to_integer(pa_x(2)));
        pre_y  <= bufy(to_integer(pa_y(1))) & bufy(to_integer(pa_y(0)));
        pre_b  <= bufb(to_integer(pa_b(1))) & bufb(to_integer(pa_b(0)));
      end if;

      -- ======================================================================
      -- GEMV v2 pipeline (runs alongside the main FSM while g2 = '1')
      if g2 = '1' then
        -- Stream reader: issue the next burst (to the next 256-byte
        -- boundary) whenever the FIFO has room, except in the two states
        -- where the main FSM issues commands itself.
        -- Burst precompute, stage A.  sr_next <= sr_end always holds (it
        -- starts 8-aligned below the row start and only ever advances to
        -- min(boundary, sr_end)), so min(boundary, sr_end) - sr_next is
        -- min(room, rem).
        sr_rem_q  <= sr_end - sr_next;
        sr_room_q <= to_unsigned(256, 9) - resize(sr_next(7 downto 0), 9);
        sr_bnd_q  <= (sr_next(27 downto 8) + 1) & x"00";
        sr_off_q  <= sr_next - str_base;
        sr_nst_q  <= sr_segst + sr_stride;
        sr_nend_q <= sr_end + sr_stride;
        sr_ok1 <= '1';
        -- Stage B: burst end, length in bytes, LUMP address.  Ties take the
        -- boundary, as the original a1 > sr_end test did.
        sr_seg_q <= sr_rem_q(27 downto 9) = 0 and sr_rem_q(8 downto 0) <= sr_room_q;
        if sr_rem_q(27 downto 9) = 0 and sr_rem_q(8 downto 0) < sr_room_q then
          sr_a1_q  <= sr_end;
          sr_len_q <= sr_rem_q(8 downto 0);
          sr_fit_q <= sr_used_q + resize(sr_rem_q(8 downto 1), 10) <= 256;
        else
          sr_a1_q  <= sr_bnd_q;
          sr_len_q <= sr_room_q;
          sr_fit_q <= sr_used_q + resize(sr_room_q(8 downto 1), 10) <= 256;
        end if;
        sr_addr_q <= str_local + sr_off_q(26 downto 0);
        if sr_rem_q /= 0 then sr_more_q <= '1'; else sr_more_q <= '0'; end if;
        sr_ok2 <= sr_ok1;
        sr_used_q <= resize(wf_w - wf_r, 10) + resize(sr_inflight, 10);

        assert fsm_iss_q or (cstate /= C_RD_ISSUE and cstate /= C_WR_ISSUE)
          report "SSNAIL: fsm_iss_q misses an issue state" severity failure;
        if not fsm_iss_q
          and sr_ok2 = '1' and sr_more_q = '1'
          and hr_valid_i = '0' and sd_valid_i = '0'
          and rq_w - rq_r < 3 then
          if sr_fit_q then                       -- sr_used_q + words <= 256
            assert resize(wf_w - wf_r, 10) + resize(sr_inflight, 10) + resize(sr_len_q(8 downto 1), 10) <= 256
              report "SSNAIL: stream burst overfills the FIFO" severity failure;
            if str_is_sd = '1' then
              sd_valid_i <= '1'; sd_cmd_op <= LUMP_OP_READ;
              sd_cmd_addr <= sr_addr_q; sd_cmd_len <= sr_len_q;
              sd_issue := '1';
            else
              hr_valid_i <= '1'; hr_cmd_op <= LUMP_OP_READ;
              hr_cmd_addr <= sr_addr_q; hr_cmd_len <= sr_len_q;
              hr_issue := '1';
            end if;
            rq_push := true;
            rq_push_tag := '1';
            rq_push_cnt := resize(sr_len_q(8 downto 1), 8);
            sr_inflight_inc := resize(sr_len_q(8 downto 1), 9);
            if sr_seg_q and sr_segs /= 0 then       -- on to the next segment
              sr_next <= sr_nst_q;
              sr_segst <= sr_nst_q;
              sr_end <= sr_nend_q;
              sr_segs <= sr_segs - 1;
            else
              sr_next <= sr_a1_q;
            end if;
            -- stage B must be recomputed from the new sr_next
            sr_ok1 <= '0';
            sr_ok2 <= '0';
          end if;
        end if;

        -- Block assembler: up to 2 bytes per cycle from the FIFO (and one
        -- pending byte); skip the leading bytes of the first, 8-aligned,
        -- burst.  grpf is a shift register: the c bytes consumed this cycle
        -- are the first s skipped ones, then w bytes shifted in at the top
        -- (grpf(33) is the newest).  A finished Q8_0 block (34 bytes) is
        -- grpf(0 to 33), a Q4_0 block (18 bytes) grpf(16 to 33).
        if as_full = '0' and as_any = '1' then
          assert as_f = as_flags(to_integer(as_skip), to_integer(as_rem))
            report "SSNAIL: stale as_f" severity failure;
          sk := to_integer(as_skip);
          -- the next as_f for every outcome, from registers only; the
          -- outcome just picks one
          for t in 0 to 15 loop
            if as_rem >= t then rge(t) := '1'; else rge(t) := '0'; end if;
            if as_rem = t then req(t) := '1'; else req(t) := '0'; end if;
          end loop;
          for si in 0 to 3 loop
            for wi in 0 to 3 loop
              asf_c(si, wi) := as_flags_t(as_skip, si, wi, rge, req);
              assert asf_c(si, wi) = as_flags(sk - si, to_integer(as_rem) - wi)
                report "SSNAIL: as_flags_t mismatch" severity failure;
            end loop;
            asf_full(si) := as_flags(sk - si, 34);   -- (any block length >= 4)
          end loop;
          -- c = min(available, skip + rem) bytes taken, s = min(skip, c)
          -- skipped, w = c - s shifted in; from the thresholds in as_f
          nav := 0;
          if pb_v = '1' then
            avb(0) := pb_b; nav := 1;
          end if;
          popw := false;
          assert wf_z = (wf_w = wf_r) and wf_o = (wf_w - wf_r = 1)
            report "SSNAIL: stale wf_z / wf_o" severity failure;
          if not wf_z and (pb_v = '0' or as_f(3) = '1') then   -- need > nav
            wv := wf(to_integer(wf_r(7 downto 0)));
            avb(nav) := wv(7 downto 0);
            avb(nav + 1) := wv(15 downto 8);
            nav := nav + 2;
            popw := true;
          end if;
          if nav = 3 and as_f(4) = '1' then
            as_c := 3;
          elsif nav >= 2 and as_f(3) = '1' then
            as_c := 2;
          elsif nav >= 1 then
            as_c := 1;
          else
            as_c := 0;
          end if;
          if as_c = 3 and as_f(2) = '1' then
            as_s := 3;
          elsif as_c >= 2 and as_f(1) = '1' then
            as_s := 2;
          elsif as_c >= 1 and as_f(0) = '1' then
            as_s := 1;
          else
            as_s := 0;
          end if;
          as_w := as_c - as_s;
          case as_w is
            when 1 =>
              grpf(0 to 32) <= grpf(1 to 33);
              grpf(33) <= avb(as_s);
            when 2 =>
              grpf(0 to 31) <= grpf(2 to 33);
              grpf(32) <= avb(as_s);
              grpf(33) <= avb(as_s + 1);
            when 3 =>                               -- (then as_s = 0)
              grpf(0 to 30) <= grpf(3 to 33);
              grpf(31) <= avb(0);
              grpf(32) <= avb(1);
              grpf(33) <= avb(2);
            when others =>
              null;
          end case;
          -- K-quants: the bytes go into the super-block buffer instead (one
          -- write per byte lane: the w <= 3 bytes are in different lanes)
          if kq_on = '1' then
            for l in 0 to 3 loop
              kb_ln := (l - to_integer(kq_wp(1 downto 0))) mod 4;
              kb_pos := ('0' & kq_wp) + kb_ln;
              kb_wd := kq_wh & kb_pos(7 downto 2);
              if kb_ln < as_w then
                kw_we(l) := '1';
                kw_a(l) := kb_wd;
                kw_d(l) := avb(as_s + kb_ln);
              end if;
            end loop;
          end if;
          if popw then wf_r <= wf_r + 1; wf_pop := true; end if;
          if as_c < nav then
            pb_v <= '1'; pb_b <= avb(nav - 1);       -- at most one left over
          else
            pb_v <= '0';
          end if;
          as_skip <= to_unsigned(sk - as_s, 3);
          if (as_w = 1 and as_f(5) = '1') or (as_w = 2 and as_f(6) = '1')
            or (as_w = 3 and as_f(7) = '1') then    -- as_rem = as_w: block full
            as_full <= '1';
            as_rem <= g_bl;
            as_f <= asf_full(as_s);
            kq_wp <= kq_wo;
            if kq_on = '1' then
              -- the super-block is in its half; on to the other one (as_full
              -- holds the assembler until that is free)
              -- (marked full a cycle later, with its last byte written)
              kq_fset <= '1';
              kq_fseth <= kq_wh;
              kq_wh <= not kq_wh;
              as_blocks <= as_blocks - 1;
              if as_blocks = 1 then as_any <= '0'; end if;
            end if;
          else
            as_rem <= as_rem - as_w;
            as_f <= asf_c(as_s, as_w);
            kq_wp <= kq_wp + as_w;
          end if;
        end if;
        if kq_on = '1' and as_full = '1' and kq_full(to_integer(unsigned'("" & kq_wh))) = '0' then
          as_full <= '0';
        end if;
        -- Float lane: a weight from the FIFO (see fl_st)
        fl_v1 <= '0';
        row_end := false;
        if fl_on = '1' and fl_st = FL_RUN and not wf_z
          and (fl_ax = '0' or not fl_cz or fl_wv = '1') then   -- (a row's w_t in)
          wv := wf(to_integer(wf_r(7 downto 0)));
          wf_r <= wf_r + 1;
          wf_pop := true;
          if fl_skip /= 0 then
            fl_skip <= fl_skip - 1;                    -- (before the matrix)
          elsif fl_f32 = '1' and fl_hv = '0' then
            fl_lo <= wv;                               -- (F32: the low half)
            fl_hv <= '1';
          else
            fl_hv <= '0';
            fl_v1 <= '1';
            if fl_f32 = '1' then fl_raw1 <= wv & fl_lo; else fl_raw1 <= x"0000" & wv; end if;
            fl_xa <= fl_c(11 downto 0);
            if fl_ax = '1' then
              fl_tg1 <= fl_first & fl_c(8 downto 0);
            else
              fl_tg1 <= "000000" & fl_bk & fl_k;
            end if;
            if fl_cz then                              -- (ATTN: this row's w_t)
              fl_b1 <= fl_wq; fl_ws <= fl_wq;
              if fl_ax = '1' then fl_wv <= '0'; end if;
            else
              fl_b1 <= fl_ws;
            end if;
            fl_cz <= false;
            fl_k <= fl_k + 1;
            fl_c <= fl_c + 1;
            assert fl_cl = (fl_c + 1 = fl_n) report "SSNAIL: stale fl_cl" severity failure;
            fl_cl <= fl_c + 2 = fl_n;
            if fl_cl and fl_ax = '1' and not fl_rl then
              -- (output pass: straight on to the next row; a short one
              -- waits for its first element's sum to come back)
              fl_c <= (others => '0'); fl_cz <= true; fl_cl <= fl_n = 1;
              fl_first <= '0';
              fl_rr <= fl_rr - 1; fl_rl <= fl_rr = 2;
              if fl_short then
                fl_cnt <= (others => '0');
                fl_st <= FL_AXW;
              end if;
            elsif fl_cl and fl_ax = '1' then           -- (the last row: drain)
              fl_cnt <= (others => '0');
              fl_st <= FL_DRAIN;
            elsif fl_cl then                           -- the row's last weight
              row_end := true;
            end if;
          end if;
        end if;
        -- (GEMV, scores) a row's end: its bank to the combine unit once that
        -- is free, then the next row, in the other bank
        if fl_st = FL_ROWEND then
          row_end := true;
        end if;
        if row_end then
          if cb_st = CB_IDLE then
            cb_st <= CB_WAIT; cb_bk <= fl_bk; cb_cnt <= (others => '0');
            if fl_rl then
              fl_st <= FL_WAITC;
            else
              fl_st <= FL_RUN;
              fl_c <= (others => '0'); fl_cz <= true; fl_cl <= fl_n = 1;
              fl_k <= (others => '0'); fl_bk <= not fl_bk;
              fl_rr <= fl_rr - 1; fl_rl <= fl_rr = 2;
            end if;
          else
            fl_st <= FL_ROWEND;
          end if;
        end if;
        if fl_st = FL_WAITC and cb_st = CB_IDLE then
          fl_st <= FL_DONE;
        end if;
        -- ... as F32, with its x
        fl_v2 <= fl_v1;
        fl_tg2 <= fl_tg1;
        fl_b2 <= fl_b1;
        if fl_f32 = '1' then
          fl_w2 <= fl_raw1;
        elsif fl_bf = '1' then
          fl_w2 <= fl_raw1(15 downto 0) & x"0000";
        else
          fl_w2 <= f16_to_f32(fl_raw1(15 downto 0));
        end if;
        -- the adders' results: partial sums (or ATTN's out); the combination
        if fa_rv = '1' and fl_ax = '1' then
          outv(to_integer(fa_rtag(7 downto 0))) <= fa_r;
        elsif fa_rv = '1' then
          fl_p(to_integer(fa_rtag(3 downto 0))) <= fa_r;
        end if;
        if fc_rv = '1' and sx_on = '0' then
          case to_integer(fc_rtag) is
            when 0 to 3 => fl_q(to_integer(fc_rtag(1 downto 0))) <= fc_r;
            when 4 => fl_s0 <= fc_r;
            when 5 => fl_s1 <= fc_r;
            when others => fl_res <= fc_r;
          end case;
        end if;
        cb_v <= '0';
        case fl_st is
          when FL_DRAIN =>                             -- (output pass: all in outv)
            fl_cnt <= fl_cnt + 1;
            if fl_cnt = 18 then
              fl_st <= FL_DONE;
            end if;
          when FL_AXW =>
            fl_cnt <= fl_cnt + 1;
            if fl_cnt = 10 then
              fl_st <= FL_RUN;
            end if;
          when others =>
            null;
        end case;
        case cb_st is
          when CB_WAIT =>
            cb_cnt <= cb_cnt + 1;
            if cb_cnt = 18 then
              cb_cnt <= (others => '0');
              cb_st <= CB_P;
            end if;
          when CB_P =>
            cb_v <= '1';
            cb_a <= fl_p(to_integer(cb_bk & cb_cnt(1 downto 0) & '0'));
            cb_b <= fl_p(to_integer(cb_bk & cb_cnt(1 downto 0) & '1'));
            cb_tag <= "00000" & cb_cnt(1 downto 0);
            fl_p(to_integer(cb_bk & cb_cnt(1 downto 0) & '0')) <= x"80000000";
            fl_p(to_integer(cb_bk & cb_cnt(1 downto 0) & '1')) <= x"80000000";
            cb_cnt <= cb_cnt + 1;
            if cb_cnt = 3 then
              cb_st <= CB_W1;
            end if;
          when CB_W1 =>                                -- (p6 + p7 in last)
            if fc_rv = '1' and fc_rtag = 3 then
              cb_cnt <= (others => '0');
              cb_st <= CB_Q;
            end if;
          when CB_Q =>
            cb_v <= '1';
            if cb_cnt(0) = '0' then
              cb_a <= fl_q(0); cb_b <= fl_q(1); cb_tag <= to_unsigned(4, 7);
            else
              cb_a <= fl_q(2); cb_b <= fl_q(3); cb_tag <= to_unsigned(5, 7);
              cb_st <= CB_W2;
            end if;
            cb_cnt <= cb_cnt + 1;
          when CB_W2 =>
            if fc_rv = '1' and fc_rtag = 5 then
              cb_st <= CB_S;
            end if;
          when CB_S =>
            cb_v <= '1';
            cb_a <= fl_s0; cb_b <= fl_s1; cb_tag <= to_unsigned(6, 7);
            cb_st <= CB_W3;
          when CB_W3 =>
            if fc_rv = '1' and fc_rtag = 6 then
              cb_st <= CB_OUT;                         -- (fl_res next cycle)
            end if;
          when others =>                               -- CB_IDLE, CB_OUT (below)
            null;
        end case;

        -- FIFO occupancy flags for the next cycle
        if wf_arr and not wf_pop then
          wf_z <= false; wf_o <= wf_z;
        elsif wf_pop and not wf_arr then
          wf_z <= wf_o; wf_o <= wf_w - wf_r = 2;
        end if;

        -- Unpack: a full block becomes 32 weights and an F32 scale, and the
        -- assembler is free again at once (as it was when the lanes took the
        -- block directly)
        if as_full = '1' and ub_full = '0' and kq_on = '0' then
          ub_w <= unpack_w(grpf, d_fmt);
          ub_d <= unpack_s(grpf, d_fmt);
          ub_full <= '1';
          as_full <= '0';
          as_blocks <= as_blocks - 1;
          if as_blocks = 1 then as_any <= '0'; end if;
        end if;

        -- K-quants: the header unit, on a full half not yet decoded: 5 words
        -- of it, then scales / mins / d / dmin, S2 = sum of m * (x sums),
        -- and d * dx, dmin * dx on the third FP unit
        if kq_on = '1' then
          kq_s2v <= '0';
          case kq_hs is
            when KH_IDLE =>
              -- (kq_hrd has word kq_hwc(0) of the half now: the list moves
              -- on a cycle ahead of the words)
              if kq_full(to_integer(unsigned'("" & kq_hh))) = '1'
                and kq_hok(to_integer(unsigned'("" & kq_hh))) = '0' then
                kq_hi <= (others => '0');
                kq_hwl(0 to 3) <= kq_hwl(1 to 4);
                kq_hs <= KH_RD;
              end if;
            when KH_RD =>
              -- word kq_hwl(0) of the half (read last cycle: kq_hrd),
              -- shifted in at the top of kq_hb
              kq_hb(0 to 15) <= kq_hb(4 to 19);
              kq_hb(16) <= kq_hrd(7 downto 0);
              kq_hb(17) <= kq_hrd(15 downto 8);
              kq_hb(18) <= kq_hrd(23 downto 16);
              kq_hb(19) <= kq_hrd(31 downto 24);
              kq_hwl(0 to 3) <= kq_hwl(1 to 4);
              if kq_hi = 4 then
                kq_hs <= KH_DEC;
              else
                kq_hi <= kq_hi + 1;
              end if;
            when KH_DEC =>
              kq_sc(to_integer(unsigned'("" & kq_hh))) <= kq_scales(d_fmt, kq_hb);
              kq_m(to_integer(unsigned'("" & kq_hh))) <= kq_mins(d_fmt, kq_hb);
              kq_d16 <= kq_d(d_fmt, kq_hb);
              kq_dmin16 <= kq_dmin(d_fmt, kq_hb);
              kq_hs <= KH_DEC1;
            when KH_DEC1 =>
              kq_d32 <= f16_to_f32(kq_d16);
              kq_hs <= KH_DEC2;
            when KH_DEC2 =>
              fpu3_a <= kq_dscale(kq_d32, kq_dsh);
              fpu3_b <= dxs(to_integer(kq_hsb(3 downto 0)));
              fpu3_start <= '1';
              kq_ga <= '0';
              kq_hi <= (others => '0');
              kq_s2acc <= (others => '0');
              kq_hs <= KH_S2;
            when KH_S2 =>
              -- S2 = sum of m * (x sums): issue 16, then 3 to drain
              if kq_hi < 16 then
                kq_s2m <= kq_m(to_integer(unsigned'("" & kq_hh)))(to_integer(kq_hi(3 downto 0)));
                kq_s2b <= kq_bs(to_integer(kq_hsb(3 downto 0) & kq_hi(3 downto 0)));
                kq_s2v <= '1';
              end if;
              kq_hi <= kq_hi + 1;
              if kq_hi = 18 then
                kq_hs <= KH_A;
              end if;
            when KH_A =>
              kq_s2(to_integer(unsigned'("" & kq_hh))) <= kq_s2acc;
              if kq_ga = '1' or fpu3_done = '1' then
                if kq_min = '1' then
                  fpu3_a <= f16_to_f32(kq_dmin16);
                  fpu3_b <= dxs(to_integer(kq_hsb(3 downto 0)));
                  fpu3_start <= '1';
                  kq_hs <= KH_B;
                else
                  kq_hs <= KH_BW;
                end if;
              end if;
            when KH_B =>
              if fpu3_done = '1' then
                kq_b(to_integer(unsigned'("" & kq_hh))) <= fpu3_res;
                kq_hs <= KH_BW;
              end if;
            when others =>                                  -- KH_BW
              kq_hwl <= kq_hwc;                     -- (kq_hrd: word 0 in KH_IDLE)
              kq_hok(to_integer(unsigned'("" & kq_hh))) <= '1';
              kq_hh <= not kq_hh;
              if kq_hsb + 1 = kq_nsb then
                kq_hsb <= (others => '0');
              else
                kq_hsb <= kq_hsb + 1;
              end if;
              kq_hs <= KH_IDLE;
          end case;
          kq_s2pv <= kq_s2v;
          if kq_s2v = '1' then
            kq_s2p <= signed('0' & kq_s2m) * kq_s2b;
          end if;
          if kq_s2pv = '1' then
            kq_s2acc <= kq_s2acc + resize(kq_s2p, 32);
          end if;
          if (kq_hs = KH_S2 or kq_hs = KH_A) and fpu3_done = '1' then
            kq_a(to_integer(unsigned'("" & kq_hh))) <= fpu3_res;
            kq_ga <= '1';
          end if;
        end if;

        -- K-quants: a pass (32 weights) of a decoded half to the lanes; the
        -- last pass must find the per-super-block FP sequence free
        -- (the words are read a cycle ahead of the lanes: kq_pre reads the
        -- first, then mc_busy)
        kq_rdn <= kq_rd(d_fmt, to_integer(kq_sp));
        kq_pchg <= '0';
        kq_pre <= '0';
        if kq_pre = '1' then
          mc_busy <= '1';
        end if;
        if (kq_pre = '1' or mc_busy = '1') and kq_kr = '1' then
          if kq_rd_q.wr = '1' then                      -- (4 words, twice)
            kq_lc <= kq_lc + 1;
            kq_la(5 downto 0) <= kq_lb + (kq_lc + 1);
          else
            kq_la(5 downto 0) <= kq_la(5 downto 0) + 1;
          end if;
          kq_ha(5 downto 0) <= kq_ha(5 downto 0) + 1;
        end if;
        if kq_kr = '1' and kq_full(to_integer(unsigned'("" & kq_srh))) = '1'
          and kq_hok(to_integer(unsigned'("" & kq_srh))) = '1' and kq_pchg = '0' and kq_pre = '0'
          and mc_busy = '0' and mc_nq /= 2 then
          kq_rd_q <= kq_rdn;
          kq_la <= kq_srh & kq_rdn.la;
          kq_lb <= kq_rdn.la;
          kq_lc <= "00";
          kq_ha <= kq_srh & kq_rdn.ha;
          kq_pre <= '1';
          mc_c <= (others => '0');
          for k in 0 to 3 loop
            mc_xa(k) <= mc_sblk(6 downto 0) & "000";
          end loop;
          lane_start := true;
          kq_sp <= kq_sp + 1;
          kq_pchg <= '1';                               -- (kq_rdn follows kq_sp)
          if kq_sp = 7 then kq_srh <= not kq_srh; end if;
        end if;

        -- IQ front end (see iq_st).  A pass starts once the last one is in
        -- the lanes (iq_full clear, nothing in S1 .. S4)
        iq_v1 <= '0';
        if iq_on = '1' then
          case iq_st is
            when IQ_IDLE =>
              if kq_full(to_integer(unsigned'("" & iq_h))) = '1'
                and kq_hok(to_integer(unsigned'("" & iq_h))) = '1'
                and iq_full = '0' and iq_v1 = '0' and iq_v2 = '0' and iq_v3 = '0' then
                kq_la <= iq_h & iq_aw(d_fmt, iq_p);
                kq_ha <= iq_h & iq_bw(iq_p);
                iq_iw <= iq_iwf(d_fmt, iq_p);
                iq_st <= IQ_A1;
              end if;
            when IQ_A1 =>
              kq_la <= iq_h & iq_iw;                   -- step 0's index word
              iq_st <= IQ_A2;
            when IQ_A2 =>
              iq_a <= kq_wl_q;
              iq_q8 <= kq_wh_q(8 * to_integer(iq_p(1 downto 0)) + 7 downto 8 * to_integer(iq_p(1 downto 0)));
              if iq_xxs = '1' then                     -- 2s + 1 for both 16s
                kq_sc(to_integer(unsigned'("" & iq_h)))(to_integer(iq_p & '0'))
                  <= signed("000" & kq_wl_q(31 downto 28) & '1');
                kq_sc(to_integer(unsigned'("" & iq_h)))(to_integer(iq_p & '1'))
                  <= signed("000" & kq_wl_q(31 downto 28) & '1');
              end if;
              kq_la <= iq_h & iq_iw;                   -- step 1's
              iq_t <= (others => '0');
              iq_st <= IQ_RUN;
            when IQ_RUN =>
              -- S1, step iq_t: its index word is kq_wl_q
              iq_v1 <= '1';
              iq_t1 <= iq_t;
              iq_hf1 <= iq_t(0);
              if iq3 = '1' then
                ib := kq_wl_q(8 * to_integer(iq_t(1 downto 0)) + 7 downto 8 * to_integer(iq_t(1 downto 0)));
              else
                ib := kq_wl_q(8 * to_integer(iq_t(2 downto 1)) + 7 downto 8 * to_integer(iq_t(2 downto 1)));
              end if;
              iu := kq_wl_q(16 * to_integer(iq_t(1 downto 1)) + 15 downto 16 * to_integer(iq_t(1 downto 1)));
              case iq_base is
                when "01" => iq_ra2 <= "01" & iu(8 downto 0);                  -- IQ2_XS
                when "10" => iq_ra2 <= '1' & (shift_right(iq_q8, 2 * to_integer(iq_t(2 downto 1)))(1 downto 0)) & ib;
                when others => iq_ra2 <= "000" & ib;                           -- IQ2_XXS
              end case;
              if iq_base = "01" then                                           -- IQ3_S
                iq_ra3 <= '1' & iq_q8(to_integer(iq_t)) & ib;
              else
                iq_ra3 <= "00" & ib;                                           -- IQ3_XXS
              end if;
              if iq_u16 = '1' then
                s7 := iu(15 downto 9);
              else
                s7 := shift_right(iq_a, 7 * to_integer(iq_t(2 downto 1)))(6 downto 0);
              end if;
              if iq_ks = '1' then                      -- the eighth: their parity
                s8 := (s7(0) xor s7(1) xor s7(2) xor s7(3) xor s7(4) xor s7(5) xor s7(6)) & s7;
              else
                s8 := iq_a(8 * to_integer(iq_t(2 downto 1)) + 7 downto 8 * to_integer(iq_t(2 downto 1)));
              end if;
              if iq_t(0) = '1' then
                iq_sg1 <= std_logic_vector(s8(7 downto 4));
              else
                iq_sg1 <= std_logic_vector(s8(3 downto 0));
              end if;
              -- the read for step iq_t + 2
              if iq_2w = '1' and iq_t >= 2 then
                kq_la <= iq_h & (iq_iw + 1);
              else
                kq_la <= iq_h & iq_iw;
              end if;
              iq_t <= iq_t + 1;
              if iq_t = 7 then
                iq_p <= iq_p + 1;
                if iq_p = 7 then iq_h <= not iq_h; end if;
                iq_st <= IQ_IDLE;
              end if;
          end case;
        end if;
        -- S2: the codebook ROMs; S3: their output registers
        iq_v2 <= iq_v1; iq_t2 <= iq_t1; iq_sg2 <= iq_sg1; iq_hf2 <= iq_hf1;
        iq2_w <= iq2_rom(to_integer(iq_ra2));
        iq3_w <= iq3_rom(to_integer(iq_ra3));
        iq_v3 <= iq_v2; iq_t3 <= iq_t2; iq_sg3 <= iq_sg2; iq_hf3 <= iq_hf2;
        iq2_q <= iq2_w;
        iq3_q <= iq3_w;
        -- S4: 4 values with their signs
        if iq_v3 = '1' then
          for k in 0 to 3 loop
            if iq3 = '0' then
              if iq_hf3 = '1' then
                ic2 := iq2_q(8 + 2 * k + 1 downto 8 + 2 * k);
              else
                ic2 := iq2_q(2 * k + 1 downto 2 * k);
              end if;
              case ic2 is
                when "00" => iv := to_unsigned(8, 6);
                when "01" => iv := to_unsigned(25, 6);
                when others => iv := to_unsigned(43, 6);
              end case;
            elsif iq_base = "01" then                -- IQ3_S: 2k + 1
              iv := "00" & iq3_q(3 * k + 2 downto 3 * k) & '1';
            else                                     -- IQ3_XXS
              ic3 := iq3_q(3 * k + 2 downto 3 * k);
              case ic3 is
                when "000" => iv := to_unsigned(4, 6);
                when "001" => iv := to_unsigned(12, 6);
                when "010" => iv := to_unsigned(20, 6);
                when "011" => iv := to_unsigned(28, 6);
                when "100" => iv := to_unsigned(36, 6);
                when "101" => iv := to_unsigned(44, 6);
                when "110" => iv := to_unsigned(52, 6);
                when others => iv := to_unsigned(62, 6);
              end case;
            end if;
            if iq_sg3(k) = '1' then
              iq_buf(4 * to_integer(iq_t3) + k) <= -signed(resize(iv, 9));
            else
              iq_buf(4 * to_integer(iq_t3) + k) <= signed(resize(iv, 9));
            end if;
          end loop;
          if iq_t3 = 7 then
            iq_full <= '1';
          end if;
        end if;
        -- ... and its passes go to the lanes when they are free
        if iq_full = '1' and mc_busy = '0' and mc_nq /= 2 and iq_on = '1' then
          mc_wb <= iq_buf;
          iq_full <= '0';
          mc_busy <= '1';
          mc_c <= (others => '0');
          for k in 0 to 3 loop
            mc_xa(k) <= mc_sblk(6 downto 0) & "000";
          end loop;
          lane_start := true;
        end if;

        -- Swap: an unpacked block goes to the lanes when they are free
        if ub_full = '1' and mc_busy = '0' and mc_nq /= 2 and fpu3_busy = '0' and kq_on = '0' then
          mc_wb <= ub_w;
          -- scale = d_w * d_x on the third FP unit, while the lanes work
          -- (into the block's queue entry)
          fpu3_a <= ub_d;
          ub_full <= '0';
          mc_busy <= '1';
          mc_c <= (others => '0');
          for k in 0 to 3 loop
            mc_xa(k) <= mc_sblk(6 downto 0) & "000";
          end loop;
          fpu3_b <= dxs(to_integer(mc_sblk));
          fpu3_start <= '1';
          fpu3_busy <= '1';
          fpu3_slot <= mq_ss;
          mq_ss <= not mq_ss;
          lane_start := true;
        end if;
        -- a start: the next block for the start side
        if lane_start then
          if mc_sblk + 1 = g_nb then
            mc_sblk <= (others => '0');
          else
            mc_sblk <= mc_sblk + 1;
          end if;
        end if;

        -- Stage 0: read/select operands.  Do not put the four multiplies
        -- and carry-chain accumulation on the RAM/address selection path.
        mc_v0 <= mc_busy;
        mc_last0 <= '0';
        mc_mid0 <= '0';
        mc_first0 <= '0';
        if mc_busy = '1' and mc_c = 0 then
          mc_first0 <= '1';                            -- (stage 3 starts a new sum)
        end if;
        if mc_busy = '1' and mc_c = 3 then
          mc_mid0 <= '1';
        end if;
        if mc_busy = '1' then
          kwl := kq_wl_q;
          kwh := kq_wh_q;
          for k in 0 to 3 loop
            jj := to_integer(mc_c) * 4 + k;
            if kq_kr = '1' then
              kc := kq_rd_q;
              if kc.wr = '1' and mc_c(2) = '1' then
                kc.sl := kc.sl + 4;                     -- (the second 16: high nibbles)
              end if;
              qwv := kq_q(kwl(8 * k + 7 downto 8 * k), kwh(8 * k + 7 downto 8 * k), kc);
            else
              qwv := mc_wb(jj);
            end if;
            case k is
              when 0 => qxv := qx0(to_integer(mc_xa(0)));
              when 1 => qxv := qx1(to_integer(mc_xa(1)));
              when 2 => qxv := qx2(to_integer(mc_xa(2)));
              when others => qxv := qx3(to_integer(mc_xa(3)));
            end case;
            mc_w_q(k) <= qwv;
            mc_x_q(k) <= qxv;
          end loop;
          if mc_c = 7 then
            mc_busy <= '0';
            mc_drain <= '1';
            mc_last0 <= '1';
          end if;
          mc_c <= mc_c + 1;
          for k in 0 to 3 loop
            assert mc_xa(k)(2 downto 0) = mc_c(2 downto 0)
              report "SSNAIL: stale mc_xa" severity failure;
            mc_xa(k)(2 downto 0) <= mc_xa(k)(2 downto 0) + 1;
          end loop;
        end if;

        -- Stages 1..3: parallel products, two pair sums, final group sum.
        -- 9x8 products fit signed(16 downto 0); the 4-product sum fits 19
        -- bits.  Accumulation stays 32-bit and wraps exactly as previously.
        mc_v1 <= mc_v0;
        mc_last1 <= mc_last0;
        mc_mid1 <= mc_mid0;
        mc_first1 <= mc_first0;
        if mc_v0 = '1' then
          for k in 0 to 3 loop
            mc_p_q(k) <= mc_w_q(k) * mc_x_q(k);
          end loop;
        end if;
        mc_v2 <= mc_v1;
        mc_last2 <= mc_last1;
        mc_mid2 <= mc_mid1;
        mc_first2 <= mc_first1;
        if mc_v1 = '1' then
          mc_pair_q(0) <= resize(mc_p_q(0), 18) + resize(mc_p_q(1), 18);
          mc_pair_q(1) <= resize(mc_p_q(2), 18) + resize(mc_p_q(3), 18);
        end if;
        mc_v3 <= mc_v2;
        mc_last3 <= mc_last2;
        mc_mid3 <= mc_mid2;
        mc_first3 <= mc_first2;
        if mc_v2 = '1' then
          mc_sum_q <= resize(mc_pair_q(0), 19) + resize(mc_pair_q(1), 19);
        end if;
        -- (a block's first group starts its sum; its last one goes to the
        -- queue, with K's first 16)
        if mc_first3 = '1' then
          acc32 := (others => '0');
        else
          acc32 := mc_isum;
        end if;
        if mc_v3 = '1' and kq_on = '1' and mc_mid3 = '1' then
          kq_lo <= acc32 + resize(mc_sum_q, 32);       -- (K: the first 16)
          mc_isum <= (others => '0');
        elsif mc_v3 = '1' then
          mc_isum <= acc32 + resize(mc_sum_q, 32);
          if mc_last3 = '1' then
            mq_sum(to_integer(unsigned'("" & mq_w))) <= acc32 + resize(mc_sum_q, 32);
            mq_lo(to_integer(unsigned'("" & mq_w))) <= kq_lo;
            mq_v(to_integer(unsigned'("" & mq_w))) <= '1';
            mq_w <= not mq_w;
            mc_drain <= '0';
          end if;
        end if;
        -- the second FP unit: scale for each block started (legacy), into
        -- its queue entry
        if fpu3_done = '1' then
          fpu3_busy <= '0';
          if kq_on = '0' then
            mq_sc(to_integer(unsigned'("" & fpu3_slot))) <= fpu3_res;
            mq_scok(to_integer(unsigned'("" & fpu3_slot))) <= '1';
          end if;
        end if;
        if tl_full_clr = '1' then
          tl_full <= '0';
        end if;
        -- mc_isum -> F32 (i_to_f32, |v| < 2^24), pipelined.  Stage 1
        -- captures a finished block (sign, zero, magnitude: only the low 24
        -- bits of |v| reach the result) with its scale and index, and frees
        -- the lanes; stages 2 and 3 follow from the held stage 1.
        i2f_ok1 <= '0';
        -- K-quants: a finished pass's two 16-weight sums go to the integer
        -- tail with their scales (the last pass of a super-block only once
        -- the FP sequence is free: it takes S1 two edges later)
        kq_c1 <= '0';
        kq_c1last <= '0';
        if kq_on = '1' and mq_v(to_integer(unsigned'("" & mq_r))) = '1'
          and (kq_p /= 7 or (kq_fs = KF_IDLE and kq_c1last = '0' and kq_c2last = '0'
                             and kq_c3last = '0')) then
          kq_tlo <= mq_lo(to_integer(unsigned'("" & mq_r)));
          kq_thi <= mq_sum(to_integer(unsigned'("" & mq_r)));
          lane_take := true;
          kq_sclo <= kq_sc(to_integer(unsigned'("" & kq_rh)))(to_integer(kq_p & '0'));
          kq_schi <= kq_sc(to_integer(unsigned'("" & kq_rh)))(to_integer(kq_p & '1'));
          kq_c1 <= '1';
          kq_c1h <= kq_rh;
          if kq_p = 7 then kq_c1last <= '1'; end if;
          if mc_blk + 1 = g_nb then
            mc_blk <= (others => '0');
          else
            mc_blk <= mc_blk + 1;
          end if;
          kq_p <= kq_p + 1;
          if kq_p = 7 then                              -- the half is used up
            kq_full(to_integer(unsigned'("" & kq_rh))) <= '0';
            kq_hok(to_integer(unsigned'("" & kq_rh))) <= '0';
            kq_rh <= not kq_rh;
          end if;
        end if;
        kq_c2 <= kq_c1;
        kq_c2h <= kq_c1h;
        if kq_c1 = '1' then
          kq_plo <= resize(resize(kq_tlo, 18) * kq_sclo, 32);   -- (|sum16| < 2^17)
          kq_phi <= resize(resize(kq_thi, 18) * kq_schi, 32);
          kq_c2last <= kq_c1last;
        else
          kq_c2last <= '0';
        end if;
        kq_c3 <= kq_c2;
        kq_c3h <= kq_c2h;
        kq_c3last <= kq_c2last and kq_c2;
        if kq_c2 = '1' then
          kq_pp <= kq_plo + kq_phi;
        end if;
        kq_fgo <= '0';
        if kq_c3 = '1' then
          if kq_c3last = '1' then
            -- S1 complete: F32(S1) * (d * dx), F32(S2) * (dmin * dx)
            kq_s1 <= (others => '0');
            kq_fi <= kq_s1 + kq_pp;
            kq_fgo <= '1';
            kq_fs2 <= kq_s2(to_integer(unsigned'("" & kq_c3h)));
            kq_fa <= kq_a(to_integer(unsigned'("" & kq_c3h)));
            kq_fb <= kq_b(to_integer(unsigned'("" & kq_c3h)));
            kq_fs <= KF_C1;
          else
            kq_s1 <= kq_s1 + kq_pp;
          end if;
        end if;
        -- signed 32-bit -> F32, round to nearest even: |v|, its leading one,
        -- normalised (leading one at bit 31), rounded
        kq_fk <= kq_fk(2 downto 0) & kq_fgo;
        kq_fok <= '0';
        if kq_fgo = '1' then
          kq_fneg <= kq_fi(31);
          if kq_fi = 0 then kq_fz <= '1'; else kq_fz <= '0'; end if;
          if kq_fi(31) = '1' then
            kq_fabs <= unsigned(-kq_fi);
          else
            kq_fabs <= unsigned(kq_fi);
          end if;
        end if;
        kf_p := 0;
        for i in 0 to 31 loop
          if kq_fabs(i) = '1' then kf_p := i; end if;
        end loop;
        kq_fp <= to_unsigned(kf_p, 5);
        kq_fm <= shift_left(kq_fabs, 31 - to_integer(kq_fp));
        if kq_fk(2) = '1' then
          kf_r := ('0' & kq_fm(31 downto 8)) + 0;
          if kq_fm(7) = '1' and (kq_fm(6 downto 0) /= 0 or kq_fm(8) = '1') then
            kf_r := ('0' & kq_fm(31 downto 8)) + 1;
          end if;
          if kq_fz = '1' then
            kq_fres <= x"00000000";
          elsif kf_r(24) = '1' then                     -- rounded up to 2^(p+1)
            kq_fres <= kq_fneg & to_unsigned(128 + to_integer(kq_fp), 8) & kf_r(23 downto 1);
          else
            kq_fres <= kq_fneg & to_unsigned(127 + to_integer(kq_fp), 8) & kf_r(22 downto 0);
          end if;
          kq_fok <= '1';
        end if;
        case kq_fs is
          when KF_C1 =>
            if kq_fok = '1' then
              fpu2_a <= kq_fres; fpu2_b <= kq_fa; fpu2_start <= '1';
              kq_fs <= KF_M1;
            end if;
          when KF_M1 =>
            if fpu2_done = '1' then
              kq_t1 <= fpu2_res;
              kq_t2 <= (others => '0');
              if kq_min = '1' then
                kq_fi <= kq_fs2;
                kq_fgo <= '1';
                kq_fs <= KF_C2;
              else
                kq_fs <= KF_OUT;
              end if;
            end if;
          when KF_C2 =>
            if kq_fok = '1' then
              fpu2_a <= kq_fres; fpu2_b <= kq_fb; fpu2_start <= '1';
              kq_fs <= KF_M2;
            end if;
          when KF_M2 =>
            if fpu2_done = '1' then
              kq_t2 <= fpu2_res;
              kq_fs <= KF_OUT;
            end if;
          when others => null;                          -- (KF_OUT: below)
        end case;
        if mq_v(to_integer(unsigned'("" & mq_r))) = '1' and mq_scok(to_integer(unsigned'("" & mq_r))) = '1'
          and i2f_busy = '0' and kq_on = '0' then
          qs32 := mq_sum(to_integer(unsigned'("" & mq_r)));
          i2f_neg_q  <= qs32(31);
          if qs32 = 0 then i2f_zero_q <= '1'; else i2f_zero_q <= '0'; end if;
          if qs32(31) = '1' then
            i2f_abs_q <= unsigned(-qs32(23 downto 0));
          else
            i2f_abs_q <= unsigned(qs32(23 downto 0));
          end if;
          i2f_scale <= mq_sc(to_integer(unsigned'("" & mq_r)));
          i2f_blk <= mc_blk;
          i2f_busy <= '1';
          i2f_ok1 <= '1';
          mq_scok(to_integer(unsigned'("" & mq_r))) <= '0';
          lane_take := true;
          if mc_blk + 1 = g_nb then
            mc_blk <= (others => '0');
          else
            mc_blk <= mc_blk + 1;
          end if;
        end if;
        -- (the queue entry taken, by the K tail or the F32 conversion)
        if lane_take then
          mq_v(to_integer(unsigned'("" & mq_r))) <= '0';
          mq_r <= not mq_r;
        end if;
        if lane_start and not lane_take then
          mc_nq <= mc_nq + 1;
        elsif lane_take and not lane_start then
          mc_nq <= mc_nq - 1;
        end if;
        -- Stage 2: position of the leading one
        i2f_p := 0;
        for i in 0 to 23 loop
          if i2f_abs_q(i) = '1' then i2f_p := i; end if;
        end loop;
        i2f_p_q <= to_unsigned(i2f_p, 5);
        i2f_abs2_q <= i2f_abs_q;
        i2f_neg2_q <= i2f_neg_q;
        i2f_zero2_q <= i2f_zero_q;
        -- Stage 3: normalise and pack
        if i2f_zero2_q = '1' then
          i2f_res_q <= x"00000000";
        else
          i2f_m := shift_left(i2f_abs2_q, 23 - to_integer(i2f_p_q));
          i2f_res_q <= i2f_neg2_q & to_unsigned(127 + to_integer(i2f_p_q), 8)
                       & i2f_m(22 downto 0);
        end if;
        i2f_ok2 <= i2f_ok1;
        if i2f_ok2 = '1' then i2f_ok3 <= '1'; end if;
        -- finished terms go to the tail, or wait in th_* while it is busy
        tl_free := tl_full = '0' or tl_full_clr = '1';
        if kq_fs = KF_OUT and tl_free then
          tl_full <= '1'; tl_term <= kq_t1; tl_term2 <= kq_t2; tl_blk <= kq_fsb;
          if kq_fsb + 1 = kq_nsb then
            kq_fsb <= (others => '0');
          else
            kq_fsb <= kq_fsb + 1;
          end if;
          kq_fs <= KF_IDLE;
          tl_free := false;
        end if;
        -- (float lane: the row's sum, once the adder has it)
        if cb_st = CB_OUT and tl_free then
          tl_full <= '1'; tl_term <= fl_res; tl_blk <= (others => '0');
          tl_free := false;
          cb_st <= CB_IDLE;
        end if;
        if th_v = '1' and tl_free then
          tl_full <= '1'; tl_term <= th_val; tl_blk <= th_blk;
          th_v <= '0';
          tl_free := false;
        end if;
        if fpu2_done = '1' and kq_on = '0' then
          if tl_free then
            tl_full <= '1'; tl_term <= fpu2_res; tl_blk <= tm_blk;
          else
            th_v <= '1'; th_val <= fpu2_res; th_blk <= tm_blk;
          end if;
          tm_busy <= '0';
        elsif i2f_ok3 = '1' and tm_busy = '0' and th_v = '0' then
          fpu2_a <= i2f_res_q;
          fpu2_b <= i2f_scale;
          fpu2_start <= '1';
          f2_term <= '1';
          tm_busy <= '1';
          tm_blk <= i2f_blk;
          i2f_busy <= '0';
          i2f_ok3 <= '0';
        end if;
      else
        sr_ok1 <= '0'; sr_ok2 <= '0';
        i2f_busy <= '0'; i2f_ok1 <= '0'; i2f_ok2 <= '0'; i2f_ok3 <= '0';
        mc_drain <= '0';
        mc_v0 <= '0'; mc_v1 <= '0'; mc_v2 <= '0'; mc_v3 <= '0';
        mc_last0 <= '0'; mc_last1 <= '0'; mc_last2 <= '0'; mc_last3 <= '0';
      end if;

      -- read-tag queue and in-flight count bookkeeping
      if rq_push then
        rq_tag(to_integer(rq_w(1 downto 0))) <= rq_push_tag;
        rq_cnt(to_integer(rq_w(1 downto 0))) <= rq_push_cnt;
        rq_w <= rq_w + 1;
      end if;
      if sr_inflight_dec = '1' then
        sr_inflight <= sr_inflight + sr_inflight_inc - 1;
      else
        sr_inflight <= sr_inflight + sr_inflight_inc;
      end if;

      -- Complete blocks waiting to be written
      if lp_inc = '1' and lp_dec = '0' then
        lp_pending <= lp_pending + 1;
      elsif lp_inc = '0' and lp_dec = '1' then
        lp_pending <= lp_pending - 1;
      end if;

      -- kq_sb: its write port per byte lane (the writes registered first,
      -- so neither the FIFO read and byte steering nor the GEMV / DEQROW
      -- choice is in front of the RAM; a super-block's half is marked full
      -- with its last write), and its three registered read ports (the K
      -- reader's two, the header's)
      kw_we_q <= kw_we; kw_a_q <= kw_a; kw_d_q <= kw_d;
      -- x quantiser (see xq_on): issue, then roundf, then store
      mx_v <= '0';
      if xq_iss = '1' then
        mx_a <= xb(to_integer(xq_j(4 downto 0)));
        mx_b <= xq_id;
        mx_v <= '1';
        mx_t <= "00000" & xq_j(4 downto 0);
        xq_j <= xq_j + 1;
        if xq_j = 31 then
          xq_iss <= '0';
        end if;
      end if;
      xr_v1 <= fm_rv and xq_on;
      xr_j1 <= fm_rtag(4 downto 0);
      xr_s1 <= fm_r(31);
      xe := to_integer(fm_r(30 downto 23)) - 127;      -- (unbiased)
      if fm_r(30 downto 23) = x"FF" or xe < -1 then
        xr_fix <= (others => '0');                     -- NaN, |v| < 0.5: 0
      elsif xe > 6 then
        xr_fix <= x"7F000000";                         -- (not for finite x)
      else                                             -- |v| * 2^24
        xr_fix <= shift_left(resize(unsigned('1' & fm_r(22 downto 0)), 32), xe + 1);
      end if;
      xr_v2 <= xr_v1;
      xr_j2 <= xr_j1;
      xfx := xr_fix + x"00800000";                      -- + 0.5, then the integer part
      if xr_s1 = '1' then
        xr_q <= -signed(xfx(31 downto 24));
      else
        xr_q <= signed(xfx(31 downto 24));
      end if;
      if xr_v2 = '1' then
        case to_integer(xr_j2(1 downto 0)) is
          when 0 => qx0(to_integer(xq_blk & xr_j2(4 downto 2))) <= xr_q;
          when 1 => qx1(to_integer(xq_blk & xr_j2(4 downto 2))) <= xr_q;
          when 2 => qx2(to_integer(xq_blk & xr_j2(4 downto 2))) <= xr_q;
          when others => qx3(to_integer(xq_blk & xr_j2(4 downto 2))) <= xr_q;
        end case;
        -- the sum of each 16 (K-quants' mins)
        if xr_j2(3 downto 0) = 0 then
          kq_bacc <= resize(xr_q, 12);
        else
          kq_bacc <= kq_bacc + resize(xr_q, 12);
        end if;
        if xr_j2(3 downto 0) = 15 then
          kq_bs(to_integer(xq_blk(6 downto 0) & xr_j2(4))) <= kq_bacc + resize(xr_q, 12);
        end if;
      end if;
      if (xq_iss = '1') and not (xr_v2 = '1') then
        xq_pend <= xq_pend + 1;
      elsif xr_v2 = '1' and not (xq_iss = '1') then
        xq_pend <= xq_pend - 1;
      end if;
      xq_busy <= xq_iss = '1' or xq_pend > 1 or (xq_pend = 1 and xr_v2 = '0');

      -- softmax engine (see sx_on).  sarr's one read address is at_t + 1
      -- in the states that read it ahead (never while sx_on), else sx_icnt
      sx_s <= sarr(to_integer(sa));
      sx_v1 <= '0'; sx_v2 <= sx_v1; sx_v3 <= sx_v2;
      sx_t2 <= sx_t1; sx_t3 <= sx_t2;
      sx_rw <= coeff_rom(to_integer("10" & sx_ti));   -- (EXP: from 512)
      sx_cq <= sx_rw;
      if sx_on = '1' then
        sx_ph <= sx_ph + 1;
        nb := 0; nm := 0;
        cb_v <= '0'; mx_v <= '0';                    -- (the lane's are idle)
        -- s_t - m (the element read last cycle)
        if sx_ph = 0 and sx_icnt /= at_pos1 and sx_icnt - at_t < 16 then
          cb_v <= '1'; cb_a <= sx_s; cb_b <= sx_nm;
          cb_tag <= "0100" & sx_icnt(2 downto 0);
          sx_icnt <= sx_icnt + 1;
          nb := nb + 1;
        end if;
        -- d: below EXPT_LO, e = 0; not below EXPT_HI, e = 1 (carried in the
        -- tag); else d + 16
        if fc_rv = '1' and fc_rtag(6 downto 5) = "01" then
          sx_d(to_integer(fc_rtag(2 downto 0))) <= fc_r;
          if flt(fc_r, EXPT_LO) then
            sxf := "01";
          elsif not flt(fc_r, EXPT_HI) then
            sxf := "10";
          else
            sxf := "00";
          end if;
          cb_v <= '1'; cb_a <= fc_r; cb_b <= (not EXPT_LO(31)) & EXPT_LO(30 downto 0);
          cb_tag <= "10" & sxf & fc_rtag(2 downto 0);
          nb := nb + 1;
        end if;
        -- (d - lo) * k
        if fc_rv = '1' and fc_rtag(6 downto 5) = "10" then
          mx_v <= '1'; mx_a <= fc_r; mx_b <= EXPT_K;
          mx_t <= "00001" & fc_rtag(4 downto 0);
          nm := nm + 1;
        end if;
        -- the segment: floor of that (>= 0 unless d was below), at most
        -- TAB_SEGMENTS - 1, as FOP_TRUNC and T_LOOK; then the ROM, registered
        if fm_rv = '1' and fm_rtag(5) = '1' then
          sxe := to_integer(fm_r(30 downto 23));
          if fm_r(31) = '1' or sxe < 127 then
            sx_ti <= (others => '0');
          elsif sxe >= 135 then
            sx_ti <= to_unsigned(TAB_SEGMENTS - 1, 8);
          else
            sx_ti <= resize(shift_right(unsigned('1' & fm_r(22 downto 16)), 134 - sxe), 8);
          end if;
          sx_v1 <= '1'; sx_t1 <= fm_rtag(4 downto 0);
        end if;
        -- c1 * x
        if sx_v3 = '1' then
          mx_v <= '1'; mx_a <= sx_cq(31 downto 0);
          mx_b <= sx_d(to_integer(sx_t3(2 downto 0)));
          sx_c0(to_integer(sx_t3(2 downto 0))) <= sx_cq(63 downto 32);
          mx_t <= "00010" & sx_t3;
          nm := nm + 1;
        end if;
        -- c0 + that
        if fm_rv = '1' and fm_rtag(6) = '1' then
          cb_v <= '1'; cb_a <= sx_c0(to_integer(fm_rtag(2 downto 0))); cb_b <= fm_r;
          cb_tag <= "11" & fm_rtag(4 downto 0);
          nb := nb + 1;
        end if;
        -- e_t, in order
        if fc_rv = '1' and fc_rtag(6 downto 5) = "11" then
          if fc_rtag(4 downto 3) = "01" then
            sxr := (others => '0');
          elsif fc_rtag(4 downto 3) = "10" then
            sxr := x"3F800000";
          else
            sxr := fc_r;
          end if;
          sw_we := true; sw_a := sx_wcnt(9 downto 0); sw_d := sxr;
          if sx_wcnt(9 downto 0) = 0 then sarr0 <= sxr; end if;
          sx_fifo(to_integer(sx_wcnt(3 downto 0))) <= sxr;
          sx_wcnt <= sx_wcnt + 1;
        end if;
        assert nb <= 1 and nm <= 1 report "SSNAIL: softmax engine unit clash nb=" & integer'image(nb) & " nm=" & integer'image(nm) & " ph=" & integer'image(to_integer(sx_ph)) & " fcrv=" & std_logic'image(fc_rv) & " tag=" & integer'image(to_integer(fc_rtag)) & " fmrv=" & std_logic'image(fm_rv) & " fmtag=" & integer'image(to_integer(fm_rtag)) & " v3=" & std_logic'image(sx_v3) severity failure;
      else
        sx_ph <= (others => '0');
        sx_icnt <= (others => '0');
        sx_wcnt <= (others => '0');
      end if;

      -- xf: one write port (the x fill, ATTN's q) and one registered read
      -- (the float lane): a block RAM
      if xw_we then xf(to_integer(xw_a)) <= xw_d; end if;
      if sw_we then sarr(to_integer(sw_a)) <= sw_d; end if;
      xf_q <= xf(to_integer(fl_xa));
      if kw_we_q(0) = '1' then kq_sb0(to_integer(kw_a_q(0))) <= kw_d_q(0); end if;
      if kw_we_q(1) = '1' then kq_sb1(to_integer(kw_a_q(1))) <= kw_d_q(1); end if;
      if kw_we_q(2) = '1' then kq_sb2(to_integer(kw_a_q(2))) <= kw_d_q(2); end if;
      if kw_we_q(3) = '1' then kq_sb3(to_integer(kw_a_q(3))) <= kw_d_q(3); end if;
      if kq_fset = '1' then
        kq_full(to_integer(unsigned'("" & kq_fseth))) <= '1';
      end if;
      kq_wl_q <= kq_sb3(to_integer(kq_la)) & kq_sb2(to_integer(kq_la))
                 & kq_sb1(to_integer(kq_la)) & kq_sb0(to_integer(kq_la));
      kq_wh_q <= kq_sb3(to_integer(kq_ha)) & kq_sb2(to_integer(kq_ha))
                 & kq_sb1(to_integer(kq_ha)) & kq_sb0(to_integer(kq_ha));
      kb_wd := kq_hh & kq_hwl(0);
      kq_hrd <= kq_sb3(to_integer(kb_wd)) & kq_sb2(to_integer(kb_wd))
                & kq_sb1(to_integer(kb_wd)) & kq_sb0(to_integer(kb_wd));

      -- Outstanding command counters (and out_z, from their next values)
      nh := hr_out;
      if hr_issue = '1' and hr_cmd_done = '0' then
        nh := hr_out + 1;
      elsif hr_issue = '0' and hr_cmd_done = '1' and hr_out /= 0 then
        nh := hr_out - 1;
      end if;
      ns := sd_out;
      if sd_issue = '1' and sd_cmd_done = '0' then
        ns := sd_out + 1;
      elsif sd_issue = '0' and sd_cmd_done = '1' and sd_out /= 0 then
        ns := sd_out - 1;
      end if;
      hr_out <= nh;
      sd_out <= ns;
      out_z <= nh = 0 and ns = 0;

    end if;
  end process;

  hr_cmd_valid <= hr_valid_i;
  sd_cmd_valid <= sd_valid_i;
  hr_wdata    <= wdata_r;
  sd_wdata    <= wdata_r;
  hr_wdata_be <= wbe_r;
  sd_wdata_be <= wbe_r;

  fpu1 : entity work.ssnail_fpu
    port map (clock => clock162, start => fpu2_start, op => FOP_MUL, a => fpu2_a, b => fpu2_b,
              done => fpu2_done, result => fpu2_res);

  fpu2 : entity work.ssnail_fpu
    port map (clock => clock162, start => fpu3_start, op => FOP_MUL, a => fpu3_a, b => fpu3_b,
              done => fpu3_done, result => fpu3_res);

  -- the float lane's pipelined units; the adder takes a product (with its
  -- partial, or the adder's own result for it this cycle) or a combination
  fl_bm <= fl_b2 when fl_ax = '1' else xf_q;
  -- (the x quantiser has the multiplier in the x phase, the softmax engine in ATTN's)
  fm_vin <= mx_v when xq_on = '1' or sx_on = '1' else fl_v2;
  fm_a <= mx_a when xq_on = '1' or sx_on = '1' else fl_w2;
  fm_b <= mx_b when xq_on = '1' or sx_on = '1' else fl_bm;
  fm_tag <= mx_t when xq_on = '1' or sx_on = '1' else fl_tg2;
  fmul_l : entity work.ssnail_fmul_p generic map (TAGW => 10)
    port map (clock => clock162, v => fm_vin, a => fm_a, b => fm_b, tag => fm_tag,
              rv => fm_rv, r => fm_r, rtag => fm_rtag);
  -- (output pass: out[d], read at the product's d; +0 for row 0)
  ov_ra <= fm_rtag(7 downto 0) when fl_ax = '1' else at_i(7 downto 0);
  fa_v <= fm_rv and not (xq_on or sx_on);
  fa_a <= x"00000000" when fl_ax = '1' and fm_rtag(9) = '1'
          else outv(to_integer(ov_ra)) when fl_ax = '1'
          else fa_r when fa_rv = '1' and fa_rtag = fm_rtag
          else fl_p(to_integer(fm_rtag(3 downto 0)));
  fa_b <= fm_r;
  fa_tag <= fm_rtag;
  fadd_c : entity work.ssnail_fadd_p generic map (TAGW => 7)
    port map (clock => clock162, v => cb_v, a => cb_a, b => cb_b, tag => cb_tag,
              rv => fc_rv, r => fc_r, rtag => fc_rtag);
  fadd_l : entity work.ssnail_fadd_p generic map (TAGW => 10)
    port map (clock => clock162, v => fa_v, a => fa_a, b => fa_b, tag => fa_tag,
              rv => fa_rv, r => fa_r, rtag => fa_rtag);

  fpu0 : entity work.ssnail_fpu
    port map (clock => clock162, start => fpu_start, op => fpu_op, a => fpu_a, b => fpu_b,
              done => fpu_done, result => fpu_res);

  -- Ring write port.  Each data byte from the cpuclock side arrives with a
  -- toggle; the byte and its address were registered on the same cpuclock
  -- edge and stay put for at least four clock162 cycles, longer than the
  -- synchroniser takes.  A completed block is announced (lp_blk_done) only
  -- after its last byte has been written, and a commit is taken only once
  -- every earlier byte has been written (lp_wr_idle): a commit is always at
  -- least one cpuclock cycle behind the last byte, so its toggle arrives later.
  process (clock162) is
  begin
    if rising_edge(clock162) then
      lp_wr_s1 <= lp_wr_tgl; lp_wr_s2 <= lp_wr_s1;
      lp_blk_done <= '0';
      if lp_wr_s2 /= lp_wr_last then
        lp_wr_last <= lp_wr_s2;
        if lp_wr_addr(0) = '0' then
          ring_lo(to_integer(lp_wr_addr(9 downto 1))) <= lp_wr_data;
        else
          ring_hi(to_integer(lp_wr_addr(9 downto 1))) <= lp_wr_data;
        end if;
        lp_blk_done <= lp_wr_blk;
      end if;
    end if;
  end process;
  lp_wr_idle <= lp_wr_s1 = lp_wr_last and lp_wr_s2 = lp_wr_last and lp_blk_done = '0';

  -- Ring read port (asynchronous LUT RAM read, registered in the core).  The
  -- core only reads bytes that have been written (see above).
  ring_rd_lo <= ring_lo(to_integer(ring_rd_idx));
  ring_rd_hi <= ring_hi(to_integer(ring_rd_idx));


end shell;
