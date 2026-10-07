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
--   $10      HyperRAM size in MB (base is fixed at $8000000). Reset: 8
--   $11      SDRAM base in MB (address bits 27-20). Reset: $88 with SDRAM, else 0
--   $12      SDRAM size in MB. Reset: 64 with SDRAM, else 0
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
--                            (0 F32, 1 F16, 2 Q4_0, 8 Q8_0, 30 BF16) at addr(X)
--   $10 GEMV                 Z (N1 rows) = W at addr(X) (N1 x N0, format a:
--                            Q8_0 or Q4_0 so far) . x at addr(Y) (N0 x F32).
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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;
use work.lumptypes.all;
use work.ssnail_fpu_pkg.all;
use work.ssnail_tables_pkg.all;

entity ssnail is
  generic (
    -- Board has SDRAM (R4-R6): defaults to the 72 MB map (SDRAM at $8800000)
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
      return x"88";
    else
      return x"40";
    end if;
  end function;
  signal sd_base_mb   : unsigned(7 downto 0) := sd_default(true, has_sdram);
  signal sd_size_mb   : unsigned(7 downto 0) := sd_default(false, has_sdram);
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
    C_FPU_WAIT, C_RD_DEC, C_RD_ISSUE, C_RD_WAIT, C_WR_DEC, C_WR_ISSUE, C_WR_WAIT,
    V_CHUNK, V_LDY, V_LDB, V_EL0, V_EL, V_ELST, V_ADV,
    E_K1, E_K2, E_K3, E_ACC, E_ACC2,
    T_START, T_K, T_I, T_LOOK, T_C0, T_DONE,
    R_S0, R_S1, R_S2, R_S3, R_S4, R_S5, R_S6,
    L_S0, L_S1, L_S2, L_S3, L_S4, L_S5, L_S6, L_S7,
    M_NEXT, M_S0, M_S1, M_S2,
    EF_START, EF_DONE,
    RO_CS, RO_CS2, E_R1, E_R2, E_R3, E_R4, E_R5, E_R6, AM_DONE,
    A_PRM, A_PRM2, A_RS0, A_RS1, A_RS2, A_RS3, A_GRP, A_HEAD, A_Q, A_Q2,
    A_S_T, A_S_I, A_S_I2, A_S_I3, A_S_I4, A_S_SC, A_S_SC2,
    A_E_T, A_E_1, A_E_2, A_E_3, A_E_R, A_E_R2, A_W_T, A_W_1,
    A_O_T, A_O_I, A_O_I2, A_O_I3, A_O_I4, A_WR, A_WR2, A_HNEXT,
    D_GROUP, D_FETCH, D_EMIT, D_SCALE, D_QMUL, D_STORE, D_AFTER,
    G_QFILL0, G_QFILL, G_QID, G_QID2, G_QD16, G_QDX, G_QDX2, G_QQ, G_QQR, G_QQS,
    G_ROW0, G_ROW, G_BLK, G_DOT0, G_DOT, G_SC, G_SC2, G_T, G_ACC, G_ACC2,
    G_OUT, G_OUT2, G_OUT3, G_OUT4,
    C_COPY_CALC, C_COPY_RD_DECODE, C_COPY_RD_ISSUE, C_COPY_RD_WAIT,
    C_COPY_WR_DECODE, C_COPY_WR_ISSUE, C_COPY_WR_WAIT,
    C_SYNC_ISSUE, C_SYNC_WAIT,
    C_LP_DECODE, C_LP_ISSUE, C_LP_WAIT, C_LP_INVAL, C_LP_DONE,
    C_NEXT, C_END);
  signal cstate : core_state_t := C_IDLE;
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
  -- Commands issued to each port and not yet completed (cmd_done)
  signal hr_out, sd_out : unsigned(2 downto 0) := (others => '0');
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
  signal s_mu, s_r, s_sc, s_rn : unsigned(31 downto 0) := (others => '0');
  signal mr_r, mr_rows : unsigned(31 downto 0) := (others => '0');  -- MEANROWS
  -- table lookup subroutine
  signal tab_id    : unsigned(1 downto 0) := "00";              -- 0 SiLU, 1 GELU, 2 exp
  signal tx, tval, tc0 : unsigned(31 downto 0) := (others => '0');
  -- element fetch subroutine: ef_val = F32 element at ef_addr (F16 if ef_f16)
  signal ef_addr   : unsigned(27 downto 0) := (others => '0');
  signal ef_f16    : std_logic := '0';
  signal ef_val    : unsigned(31 downto 0) := (others => '0');
  -- ROPE
  type f32x256_t is array (0 to 255) of unsigned(31 downto 0);
  signal csv, qv, outv : f32x256_t := (others => (others => '0'));
  attribute ram_style of csv, qv, outv : signal is "distributed";
  signal rope_j    : unsigned(8 downto 0) := (others => '0');
  signal rope_hd   : unsigned(8 downto 0) := (others => '0');
  signal rp_a, rp_b, rp0, x1v : unsigned(31 downto 0) := (others => '0');
  signal cs_i      : unsigned(8 downto 0) := (others => '0');
  -- ARGMAX
  signal am_best   : unsigned(31 downto 0) := (others => '0');
  signal am_idx, ve_g : unsigned(31 downto 0) := (others => '0');
  -- ATTN
  type f32x1024_t is array (0 to 1023) of unsigned(31 downto 0);
  signal sarr      : f32x1024_t := (others => (others => '0'));
  attribute ram_style of sarr : signal is "distributed";
  signal at_k, at_v, at_rowaddr, at_ea : unsigned(27 downto 0) := (others => '0');
  signal at_nh, at_nkv, at_hd, at_fmt, at_pos : unsigned(31 downto 0) := (others => '0');
  signal at_h, at_kvh, at_gc, at_group : unsigned(15 downto 0) := (others => '0');
  signal at_rowb   : unsigned(27 downto 0) := (others => '0');
  signal at_t      : unsigned(15 downto 0) := (others => '0');
  signal at_i      : unsigned(8 downto 0) := (others => '0');
  signal at_rs, at_m, at_r, at_acc, at_w : unsigned(31 downto 0) := (others => '0');
  signal at_pi     : unsigned(2 downto 0) := (others => '0');
  -- read / write subroutines
  signal rd_addr, wr_addr : unsigned(27 downto 0) := (others => '0');
  signal rd_len, wr_len   : unsigned(8 downto 0) := (others => '0');
  signal rd_sel    : unsigned(1 downto 0) := "00";
  signal mw_active : std_logic := '0';
  signal mw_k, mw_lead, mw_vend : unsigned(8 downto 0) := (others => '0');
  signal mw_idx    : unsigned(6 downto 0) := (others => '0');
  -- DEQROW
  type grp_t is array (0 to 33) of unsigned(7 downto 0);
  signal grp       : grp_t := (others => x"00");
  signal gi, gbytes : unsigned(5 downto 0) := (others => '0');
  signal d_j, epg  : unsigned(5 downto 0) := (others => '0');
  signal d_fmt     : unsigned(7 downto 0) := (others => '0');
  signal dq_scale, d_val : unsigned(31 downto 0) := (others => '0');
  signal d_have_scale : std_logic := '0';
  signal ld_valid  : std_logic := '0';
  signal ld_block  : unsigned(27 downto 8) := (others => '0');
  signal ea_z      : unsigned(27 downto 0) := (others => '0');
  signal fetch_ret : core_state_t := C_IDLE;

  -- GEMV
  type f32x32_t is array (0 to 31) of unsigned(31 downto 0);
  type qx_t is array (0 to 4095) of signed(7 downto 0);
  type dx_t is array (0 to 127) of unsigned(31 downto 0);
  signal xb        : f32x32_t := (others => (others => '0'));  -- one block of x
  signal qx        : qx_t := (others => (others => '0'));      -- quantised x
  signal dxs       : dx_t := (others => (others => '0'));      -- its scales, as F32
  attribute ram_style of qx, dxs : signal is "distributed";
  signal g_rows, g_r : unsigned(31 downto 0) := (others => '0');
  signal g_nb, gblk : unsigned(7 downto 0) := (others => '0');
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
  -- Vector engine operand buffers, indexed by address mod 256
  signal bufx, bufy, bufb : buf_t := (others => x"0000");
  signal cap_sel : unsigned(1 downto 0) := "00";   -- read data goes to: buf, bufx, bufy
  signal buf_ridx : unsigned(6 downto 0) := (others => '0');  -- drain index
  signal wdata_r  : unsigned(15 downto 0) := x"0000";

  attribute ram_style of buf : signal is "distributed";
  attribute ram_style of bufx, bufy, bufb : signal is "distributed";

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
        if idle then
          hr_size_mb <= to_unsigned(8, 8);
          sd_base_mb <= sd_default(true, has_sdram);
          sd_size_mb <= sd_default(false, has_sdram);
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
    variable hr_issue, sd_issue : std_logic;
    variable lp_inc, lp_dec : std_logic;
    variable st_al, en_al : unsigned(27 downto 0);
    variable room, vlen : unsigned(31 downto 0);
    variable a0, a1, a2 : unsigned(27 downto 0);
    variable ix, iy, iz, ib : unsigned(7 downto 0);
    variable xv, lo, hi : unsigned(31 downto 0);
    variable ti : integer range 0 to 1023;
    variable wd : unsigned(15 downto 0);
    variable q : signed(31 downto 0);
    variable qw : signed(8 downto 0);
    variable fv : unsigned(31 downto 0);
  begin
    if rising_edge(clock162) then
      hr_issue := '0';
      sd_issue := '0';
      lp_inc := '0';
      lp_dec := '0';
      fpu_start <= '0';

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
          wdata_r <= buf(to_integer(mw_idx + mw_k(6 downto 0)));
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
          if cap_sel = "01" then
            bufx(to_integer(buf_widx)) <= rdata_r;
          elsif cap_sel = "10" then
            bufy(to_integer(buf_widx)) <= rdata_r;
          elsif cap_sel = "11" then
            bufb(to_integer(buf_widx)) <= rdata_r;
          else
            buf(to_integer(buf_widx)) <= rdata_r;
          end if;
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
          if instr(127) = '1' then
            ea_z <= rf_a(to_integer(instr(123 downto 120))) + resize(instr(119 downto 96), 28);
          else
            ea_z <= instr(123 downto 96);
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
            when x"20" | x"21" | x"29" | x"23" | x"27" | x"22" | x"26" | x"28" =>
              -- Vector engine instructions.  All F32 vectors 4-byte aligned;
              -- CVT16 output 2-byte aligned.
              if ea_x(1 downto 0) /= "00"
                or ((instr(7 downto 0) = x"20" or instr(7 downto 0) = x"21" or instr(7 downto 0) = x"23"
                     or instr(7 downto 0) = x"22" or instr(7 downto 0) = x"26") and ea_y(1 downto 0) /= "00")
                or (instr(7 downto 0) = x"29" and ea_z(0) /= '0')
                or (instr(7 downto 0) /= x"29" and ea_z(1 downto 0) /= "00") then
                err <= ERR_ALIGNMENT;
                cstate <= C_END;
              elsif n0 = 0 or (instr(7 downto 0) = x"28" and opr_a = 0) then
                cstate <= C_NEXT;                       -- nothing to do
              else
                bx <= ea_x; by <= ea_y; bz <= ea_z;
                px <= ea_x; py <= ea_y; pz <= ea_z;
                v_n <= n0;
                o16 <= '0'; two_ops <= '0'; has_b <= '0'; has_out <= '1';
                ve_first <= '1';
                ve_ret <= C_NEXT;
                case instr(7 downto 0) is
                  when x"20" => ve_kind <= K_ADD; two_ops <= '1'; cstate <= V_CHUNK;
                  when x"21" => ve_kind <= K_MUL; two_ops <= '1'; cstate <= V_CHUNK;
                  when x"29" => ve_kind <= K_CVT16; o16 <= '1'; cstate <= V_CHUNK;
                  when x"23" => ve_kind <= K_SILUMUL; two_ops <= '1'; cstate <= V_CHUNK;
                  when x"27" => ve_kind <= K_GELU; cstate <= V_CHUNK;
                  when x"22" =>                     -- RMSNORM pass 1: sum of squares
                    ve_kind <= K_SUMSQ; has_out <= '0'; ve_ret <= R_S0; cstate <= V_CHUNK;
                  when x"26" =>                     -- LAYERNORM pass 1: sum
                    ve_kind <= K_SUM; has_out <= '0'; ve_ret <= L_S0; cstate <= V_CHUNK;
                  when others =>                    -- MEANROWS: row 0 copied to Z
                    mr_rows <= opr_a;
                    mr_r <= to_unsigned(1, 32);
                    ve_kind <= K_COPY; ve_ret <= M_NEXT; cstate <= V_CHUNK;
                end case;
              end if;
            when x"10" =>             -- GEMV
              d_fmt <= instr(15 downto 8);
              g_addz <= instr(16);
              g_f16 <= instr(17);
              if not (instr(15 downto 8) = 2 or instr(15 downto 8) = 8) then
                err <= ERR_FORMAT;                -- float weights: not yet
                cstate <= C_END;
              elsif n0(4 downto 0) /= 0 or n0 = 0 or n0 > 4096 or (instr(16) and instr(17)) = '1' then
                err <= ERR_OPCODE;
                cstate <= C_END;
              elsif ea_y(1 downto 0) /= "00" or (instr(17) = '1' and ea_z(0) /= '0')
                or (instr(17) = '0' and ea_z(1 downto 0) /= "00") then
                err <= ERR_ALIGNMENT;
                cstate <= C_END;
              elsif n1 = 0 then
                cstate <= C_NEXT;
              else
                g_rows <= n1;
                g_nb <= n0(12 downto 5);
                gblk <= (others => '0');
                if instr(15 downto 8) = 8 then
                  gbytes <= to_unsigned(34, 6);
                else
                  gbytes <= to_unsigned(18, 6);
                end if;
                ps <= ea_x; px <= ea_y; pz <= ea_z; ostart <= ea_z;
                ld_valid <= '0';
                cstate <= G_QFILL0;
              end if;
            when x"24" =>             -- ROPE
              if ea_x(2 downto 0) /= "000" or ea_y(1 downto 0) /= "00" then
                err <= ERR_ALIGNMENT;
                cstate <= C_END;
              elsif n0(0) /= '0' or n1(0) /= '0' or n1 = 0 or n1 > 256 then
                err <= ERR_OPCODE;
                cstate <= C_END;
              elsif n0 = 0 then
                cstate <= C_NEXT;
              else
                rope_hd <= n1(8 downto 0);
                ef_addr <= ea_y; ef_f16 <= '0';
                cs_i <= (others => '0');
                ld_valid <= '0';
                cstate <= RO_CS;
              end if;
            when x"12" =>             -- ARGMAX
              if ea_x(1 downto 0) /= "00" then
                err <= ERR_ALIGNMENT;
                cstate <= C_END;
              elsif n0 = 0 then
                cstate <= C_NEXT;
              else
                bx <= ea_x; px <= ea_x; v_n <= n0;
                o16 <= '0'; two_ops <= '0'; has_b <= '0'; has_out <= '0';
                ve_kind <= K_ARGMAX; ve_first <= '1'; ve_g <= (others => '0');
                ve_ret <= AM_DONE;
                cstate <= V_CHUNK;
              end if;
            when x"25" =>             -- ATTN: read the parameter block first
              if ea_x(1 downto 0) /= "00" or ea_y(1 downto 0) /= "00" or ea_z(1 downto 0) /= "00" then
                err <= ERR_ALIGNMENT;
                cstate <= C_END;
              else
                at_pos <= opr_a;
                at_pi <= (others => '0');
                ef_addr <= ea_x; ef_f16 <= '0';
                ld_valid <= '0';
                cstate <= A_PRM;
              end if;
            when x"11" =>             -- DEQROW
              d_fmt <= instr(15 downto 8);
              if not (instr(15 downto 8) = 0 or instr(15 downto 8) = 1 or instr(15 downto 8) = 2
                      or instr(15 downto 8) = 8 or instr(15 downto 8) = 30) then
                err <= ERR_OPCODE;
                cstate <= C_END;
              elsif ea_z(1 downto 0) /= "00" then
                err <= ERR_ALIGNMENT;
                cstate <= C_END;
              else
                v_n <= n0;
                ps <= ea_x; pz <= ea_z; ostart <= ea_z;
                ld_valid <= '0';
                cstate <= D_GROUP;
              end if;
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

        -- ------------------------------------------------------------------
        -- Subroutines: FPU operation, region read into a buffer, masked
        -- write from buf.  Callers set the parameters and the return state.
        when C_FPU_WAIT =>
          if fpu_done = '1' then
            fpu_r <= fpu_res;
            cstate <= fpu_ret;
          end if;

        when C_RD_DEC =>
          cstate <= C_RD_ISSUE;
        when C_RD_ISSUE =>
          if dec_ok = '0' then
            err <= ERR_ADDRESS;
            cstate <= C_END;
          else
            words_got <= (others => '0');
            words_expected <= resize(rd_len(8 downto 1), 8);
            buf_widx <= rd_addr(7 downto 1);
            cap_sel <= rd_sel;
            t_is_sd <= dec_is_sd;
            if dec_is_sd = '1' then
              sd_cmd_valid <= '1'; sd_cmd_op <= LUMP_OP_READ;
              sd_cmd_addr <= dec_local; sd_cmd_len <= rd_len;
              sd_issue := '1';
            else
              hr_cmd_valid <= '1'; hr_cmd_op <= LUMP_OP_READ;
              hr_cmd_addr <= dec_local; hr_cmd_len <= rd_len;
              hr_issue := '1';
            end if;
            cstate <= C_RD_WAIT;
          end if;
        when C_RD_WAIT =>
          if words_got = words_expected and rvalid_r = '0' then
            cap_sel <= "00";
            cstate <= rd_ret;
          end if;

        when C_WR_DEC =>
          cstate <= C_WR_ISSUE;
        when C_WR_ISSUE =>
          if dec_ok = '0' then
            err <= ERR_ADDRESS;
            cstate <= C_END;
          else
            mw_active <= '1';
            mw_k <= (others => '0');
            if dec_is_sd = '1' then
              sd_cmd_valid <= '1'; sd_cmd_op <= LUMP_OP_WRITE;
              sd_cmd_addr <= dec_local; sd_cmd_len <= wr_len;
              sd_issue := '1';
            else
              hr_cmd_valid <= '1'; hr_cmd_op <= LUMP_OP_WRITE;
              hr_cmd_addr <= dec_local; hr_cmd_len <= wr_len;
              hr_issue := '1';
            end if;
            cstate <= C_WR_WAIT;
          end if;
        when C_WR_WAIT =>
          if hr_out = 0 and sd_out = 0 and hr_issue = '0' then
            mw_active <= '0';
            cstate <= wr_ret;
          end if;

        -- ------------------------------------------------------------------
        -- VADD / VMUL / CVT16: chunks that cross no 256-byte boundary in X,
        -- Y or Z; read X (and Y), run each element through the FPU into buf,
        -- write Z with byte masks.
        when V_CHUNK =>
          -- A chunk of elements crossing no 256-byte boundary in any stream
          if v_n = 0 then
            cstate <= ve_ret;
          else
            room := resize((to_unsigned(256, 9) - resize(px(7 downto 0), 9)) / 4, 32);
            vlen := v_n;
            if room < vlen then vlen := room; end if;
            if two_ops = '1' then
              room := resize((to_unsigned(256, 9) - resize(py(7 downto 0), 9)) / 4, 32);
              if room < vlen then vlen := room; end if;
            end if;
            if has_b = '1' then
              room := resize((to_unsigned(256, 9) - resize(pb(7 downto 0), 9)) / 4, 32);
              if room < vlen then vlen := room; end if;
            end if;
            if has_out = '1' then
              if o16 = '1' then
                room := resize((to_unsigned(256, 9) - resize(pz(7 downto 0), 9)) / 2, 32);
              else
                room := resize((to_unsigned(256, 9) - resize(pz(7 downto 0), 9)) / 4, 32);
              end if;
              if room < vlen then vlen := room; end if;
            end if;
            v_e <= vlen(7 downto 0);
            a0 := px(27 downto 3) & "000";
            a1 := px + (vlen(25 downto 0) & "00") + 7;
            a1(2 downto 0) := "000";
            rd_addr <= a0;
            rd_len <= resize(a1 - a0, 9);
            rd_sel <= "01";
            dec_addr <= a0;
            if two_ops = '1' then
              rd_ret <= V_LDY;
            elsif has_b = '1' then
              rd_ret <= V_LDB;
            else
              rd_ret <= V_EL0;
            end if;
            cstate <= C_RD_DEC;
          end if;

        when V_LDY =>
          a0 := py(27 downto 3) & "000";
          a1 := py + (resize(v_e, 26) & "00") + 7;
          a1(2 downto 0) := "000";
          rd_addr <= a0;
          rd_len <= resize(a1 - a0, 9);
          rd_sel <= "10";
          dec_addr <= a0;
          if has_b = '1' then
            rd_ret <= V_LDB;
          else
            rd_ret <= V_EL0;
          end if;
          cstate <= C_RD_DEC;

        when V_LDB =>
          a0 := pb(27 downto 3) & "000";
          a1 := pb + (resize(v_e, 26) & "00") + 7;
          a1(2 downto 0) := "000";
          rd_addr <= a0;
          rd_len <= resize(a1 - a0, 9);
          rd_sel <= "11";
          dec_addr <= a0;
          rd_ret <= V_EL0;
          cstate <= C_RD_DEC;

        when V_EL0 =>
          v_i <= (others => '0');
          cstate <= V_EL;

        when V_EL =>
          if v_i = v_e then
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
              cstate <= C_WR_DEC;
            else
              cstate <= V_ADV;
            end if;
          else
            ix := px(7 downto 0) + (v_i(5 downto 0) & "00");
            iy := py(7 downto 0) + (v_i(5 downto 0) & "00");
            ib := pb(7 downto 0) + (v_i(5 downto 0) & "00");
            xv := bufx(to_integer(ix(7 downto 1) + 1)) & bufx(to_integer(ix(7 downto 1)));
            ex <= xv;
            ey <= bufy(to_integer(iy(7 downto 1) + 1)) & bufy(to_integer(iy(7 downto 1)));
            eb <= bufb(to_integer(ib(7 downto 1) + 1)) & bufb(to_integer(ib(7 downto 1)));
            -- first step of each element operation
            case ve_kind is
              when K_ARGMAX =>
                -- first maximum: replace only on strictly greater
                if ve_first = '1' or flt(am_best, xv) then
                  am_best <= xv;
                  am_idx <= ve_g;
                end if;
                ve_first <= '0';
                ve_g <= ve_g + 1;
                v_i <= v_i + 1;
              when K_ROPE =>
                -- pair (x0, x1) = elements i, i+1: x0 c - x1 s, x0 s + x1 c
                x1v <= bufx(to_integer(ix(7 downto 1) + 3)) & bufx(to_integer(ix(7 downto 1) + 2));
                fpu_op <= FOP_MUL; fpu_a <= xv; fpu_b <= csv(to_integer(rope_j));
                fpu_start <= '1'; fpu_ret <= E_R1; cstate <= C_FPU_WAIT;
              when K_COPY | K_SUM =>
                fpu_r <= xv;
                if ve_kind = K_SUM then cstate <= E_ACC; else cstate <= V_ELST; end if;
              when K_SILUMUL | K_GELU =>
                tx <= xv;
                if ve_kind = K_SILUMUL then tab_id <= "00"; else tab_id <= "01"; end if;
                tab_ret <= E_K1;
                cstate <= T_START;
              when others =>
                fpu_a <= xv;
                case ve_kind is
                  when K_ADD =>
                    fpu_op <= FOP_ADD;
                    fpu_b <= bufy(to_integer(iy(7 downto 1) + 1)) & bufy(to_integer(iy(7 downto 1)));
                    fpu_ret <= V_ELST;
                  when K_MUL =>
                    fpu_op <= FOP_MUL;
                    fpu_b <= bufy(to_integer(iy(7 downto 1) + 1)) & bufy(to_integer(iy(7 downto 1)));
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
                cstate <= C_FPU_WAIT;
            end case;
          end if;

        -- second and later steps of the element operations
        when E_K1 =>
          case ve_kind is
            when K_SILUMUL =>                       -- silu(x) * y
              fpu_op <= FOP_MUL; fpu_a <= tval; fpu_b <= ey; fpu_ret <= V_ELST;
              fpu_start <= '1'; cstate <= C_FPU_WAIT;
            when K_GELU =>
              fpu_r <= tval; cstate <= V_ELST;
            when K_RMSOUT =>                        -- (x * r) * g
              fpu_op <= FOP_MUL; fpu_a <= fpu_r; fpu_b <= ey; fpu_ret <= V_ELST;
              fpu_start <= '1'; cstate <= C_FPU_WAIT;
            when K_LNVAR =>                         -- d * d
              fpu_op <= FOP_MUL; fpu_a <= fpu_r; fpu_b <= fpu_r; fpu_ret <= E_ACC;
              fpu_start <= '1'; cstate <= C_FPU_WAIT;
            when others =>                          -- K_LNOUT: d * r
              fpu_op <= FOP_MUL; fpu_a <= fpu_r; fpu_b <= s_r; fpu_ret <= E_K2;
              fpu_start <= '1'; cstate <= C_FPU_WAIT;
          end case;

        when E_K2 =>                                -- K_LNOUT: (d * r) * g
          fpu_op <= FOP_MUL; fpu_a <= fpu_r; fpu_b <= ey; fpu_ret <= E_K3;
          fpu_start <= '1'; cstate <= C_FPU_WAIT;

        when E_K3 =>                                -- K_LNOUT: ... + b
          fpu_op <= FOP_ADD; fpu_a <= fpu_r; fpu_b <= eb; fpu_ret <= V_ELST;
          fpu_start <= '1'; cstate <= C_FPU_WAIT;

        when E_ACC =>
          -- sequential sum: the first value as it is, then acc = acc + v
          if ve_first = '1' then
            ve_acc <= fpu_r;
            ve_first <= '0';
            v_i <= v_i + 1;
            cstate <= V_EL;
          else
            fpu_op <= FOP_ADD; fpu_a <= ve_acc; fpu_b <= fpu_r; fpu_ret <= E_ACC2;
            fpu_start <= '1'; cstate <= C_FPU_WAIT;
          end if;

        when E_ACC2 =>
          ve_acc <= fpu_r;
          v_i <= v_i + 1;
          cstate <= V_EL;

        when V_ELST =>
          if o16 = '1' then
            iz := pz(7 downto 0) + (v_i(6 downto 0) & "0");
            buf(to_integer(iz(7 downto 1))) <= fpu_r(15 downto 0);
          else
            iz := pz(7 downto 0) + (v_i(5 downto 0) & "00");
            buf(to_integer(iz(7 downto 1))) <= fpu_r(15 downto 0);
            buf(to_integer(iz(7 downto 1) + 1)) <= fpu_r(31 downto 16);
          end if;
          v_i <= v_i + 1;
          cstate <= V_EL;

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
          cstate <= V_CHUNK;

        -- ------------------------------------------------------------------
        -- Table lookup (ssnail_hw.Table): tval = f(tx), then tab_ret.
        when T_START =>
          if tab_id = "00" then
            lo := SILU_LO; hi := SILU_HI;
          elsif tab_id = "01" then
            lo := GELU_LO; hi := GELU_HI;
          else
            lo := EXPT_LO; hi := EXPT_HI;
          end if;
          if flt(tx, lo) then
            tval <= (others => '0');                   -- below: 0
            cstate <= tab_ret;
          elsif not flt(tx, hi) then
            if tab_id = "10" then
              tval <= x"3F800000";                     -- exp above: 1
            else
              tval <= tx;                              -- silu, gelu above: x
            end if;
            cstate <= tab_ret;
          else
            fpu_op <= FOP_ADD;                         -- x - lo
            fpu_a <= tx;
            fpu_b <= (not lo(31)) & lo(30 downto 0);
            fpu_start <= '1';
            fpu_ret <= T_K;
            cstate <= C_FPU_WAIT;
          end if;

        when T_K =>
          fpu_op <= FOP_MUL;                           -- (x - lo) * k
          fpu_a <= fpu_r;
          if tab_id = "00" then fpu_b <= SILU_K;
          elsif tab_id = "01" then fpu_b <= GELU_K;
          else fpu_b <= EXPT_K; end if;
          fpu_start <= '1';
          fpu_ret <= T_I;
          cstate <= C_FPU_WAIT;

        when T_I =>
          fpu_op <= FOP_TRUNC;                         -- floor (it is >= 0)
          fpu_a <= fpu_r;
          fpu_start <= '1';
          fpu_ret <= T_LOOK;
          cstate <= C_FPU_WAIT;

        when T_LOOK =>
          if fpu_r(31) = '1' then
            ti := 0;
          elsif fpu_r > TAB_SEGMENTS - 1 then
            ti := TAB_SEGMENTS - 1;
          else
            ti := to_integer(fpu_r(15 downto 0));
          end if;
          fpu_op <= FOP_MUL;                           -- c1[i] * x
          if tab_id = "00" then
            fpu_a <= SILU_C1(ti); tc0 <= SILU_C0(ti);
          elsif tab_id = "01" then
            fpu_a <= GELU_C1(ti); tc0 <= GELU_C0(ti);
          else
            fpu_a <= EXPT_C1(ti); tc0 <= EXPT_C0(ti);
          end if;
          fpu_b <= tx;
          fpu_start <= '1';
          fpu_ret <= T_C0;
          cstate <= C_FPU_WAIT;

        when T_C0 =>
          fpu_op <= FOP_ADD;                           -- c0[i] + c1[i] * x
          fpu_a <= tc0;
          fpu_b <= fpu_r;
          fpu_start <= '1';
          fpu_ret <= T_DONE;
          cstate <= C_FPU_WAIT;

        when T_DONE =>
          tval <= fpu_r;
          cstate <= tab_ret;

        -- ------------------------------------------------------------------
        -- RMSNORM after pass 1 (ve_acc = sum of squares):
        -- rn = 1/N; m = ss * rn; r = 1 / sqrt(m + eps); then pass 2
        when R_S0 =>
          fpu_op <= FOP_I2F; fpu_a <= n0; fpu_start <= '1';
          fpu_ret <= R_S1; cstate <= C_FPU_WAIT;
        when R_S1 =>
          fpu_op <= FOP_DIV; fpu_a <= x"3F800000"; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= R_S2; cstate <= C_FPU_WAIT;
        when R_S2 =>
          fpu_op <= FOP_MUL; fpu_a <= ve_acc; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= R_S3; cstate <= C_FPU_WAIT;
        when R_S3 =>
          fpu_op <= FOP_ADD; fpu_a <= fpu_r; fpu_b <= n2; fpu_start <= '1';
          fpu_ret <= R_S4; cstate <= C_FPU_WAIT;
        when R_S4 =>
          fpu_op <= FOP_SQRT; fpu_a <= fpu_r; fpu_start <= '1';
          fpu_ret <= R_S5; cstate <= C_FPU_WAIT;
        when R_S5 =>
          fpu_op <= FOP_DIV; fpu_a <= x"3F800000"; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= R_S6; cstate <= C_FPU_WAIT;
        when R_S6 =>
          s_r <= fpu_r;
          px <= bx; py <= by; pz <= bz; v_n <= n0;
          ve_kind <= K_RMSOUT; two_ops <= '1'; has_out <= '1'; ve_ret <= C_NEXT;
          cstate <= V_CHUNK;

        -- LAYERNORM: after pass 1 (sum): rn = 1/N, mu = sum * rn, pass 2
        -- (sum of (x - mu)^2), var = that * rn, r = 1 / sqrt(var + eps),
        -- pass 3 with G at Y and B after it
        when L_S0 =>
          fpu_op <= FOP_I2F; fpu_a <= n0; fpu_start <= '1';
          fpu_ret <= L_S1; cstate <= C_FPU_WAIT;
        when L_S1 =>
          fpu_op <= FOP_DIV; fpu_a <= x"3F800000"; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= L_S2; cstate <= C_FPU_WAIT;
        when L_S2 =>
          s_rn <= fpu_r;
          fpu_op <= FOP_MUL; fpu_a <= ve_acc; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= L_S3; cstate <= C_FPU_WAIT;
        when L_S3 =>
          s_mu <= fpu_r;
          px <= bx; v_n <= n0; ve_first <= '1';
          ve_kind <= K_LNVAR; has_out <= '0'; ve_ret <= L_S4;
          cstate <= V_CHUNK;
        when L_S4 =>
          fpu_op <= FOP_MUL; fpu_a <= ve_acc; fpu_b <= s_rn; fpu_start <= '1';
          fpu_ret <= L_S5; cstate <= C_FPU_WAIT;
        when L_S5 =>
          fpu_op <= FOP_ADD; fpu_a <= fpu_r; fpu_b <= n2; fpu_start <= '1';
          fpu_ret <= L_S6; cstate <= C_FPU_WAIT;
        when L_S6 =>
          fpu_op <= FOP_SQRT; fpu_a <= fpu_r; fpu_start <= '1';
          fpu_ret <= L_S7; cstate <= C_FPU_WAIT;
        when L_S7 =>
          if ve_kind = K_LNVAR then
            -- r = 1 / sqrt(...), then pass 3
            fpu_op <= FOP_DIV; fpu_a <= x"3F800000"; fpu_b <= fpu_r; fpu_start <= '1';
            ve_kind <= K_LNOUT;
            fpu_ret <= L_S7; cstate <= C_FPU_WAIT;
          else
            s_r <= fpu_r;
            px <= bx; py <= by; pb <= by + (n0(25 downto 0) & "00"); pz <= bz; v_n <= n0;
            two_ops <= '1'; has_b <= '1'; has_out <= '1'; ve_ret <= C_NEXT;
            cstate <= V_CHUNK;
          end if;

        -- MEANROWS: Z = row 0; Z = Z + row r for r = 1 .. R-1; Z = Z * (1/R)
        when M_NEXT =>
          if mr_r = mr_rows then
            cstate <= M_S0;
          else
            px <= bx + resize(mr_r(25 downto 0) * (n0(25 downto 0) & "00"), 28);
            py <= bz; pz <= bz; v_n <= n0;
            ve_kind <= K_ADD; two_ops <= '1'; has_out <= '1'; ve_ret <= M_NEXT;
            mr_r <= mr_r + 1;
            cstate <= V_CHUNK;
          end if;
        when M_S0 =>
          fpu_op <= FOP_I2F; fpu_a <= mr_rows; fpu_start <= '1';
          fpu_ret <= M_S1; cstate <= C_FPU_WAIT;
        when M_S1 =>
          fpu_op <= FOP_DIV; fpu_a <= x"3F800000"; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= M_S2; cstate <= C_FPU_WAIT;
        when M_S2 =>
          s_sc <= fpu_r;
          px <= bz; pz <= bz; v_n <= n0;
          ve_kind <= K_SCALE; two_ops <= '0'; has_out <= '1'; ve_ret <= C_NEXT;
          cstate <= V_CHUNK;

        -- ------------------------------------------------------------------
        -- DEQROW: gather each group (one element, or one 32-element quant
        -- block) into grp through a forward-only byte fetcher, expand it to
        -- F32 into buf, and write buf out whenever Z crosses a 256-byte
        -- boundary or the row ends.
        when D_GROUP =>
          if v_n = 0 then
            if pz /= ostart then
              a0 := ostart(27 downto 3) & "000";
              a1 := pz + 7;
              a1(2 downto 0) := "000";
              wr_addr <= a0;
              wr_len <= resize(a1 - a0, 9);
              mw_lead <= resize(ostart - a0, 9);
              mw_vend <= resize(pz - a0, 9);
              mw_idx <= a0(7 downto 1);
              dec_addr <= a0;
              ostart <= pz;
              wr_ret <= C_NEXT;
              cstate <= C_WR_DEC;
            else
              cstate <= C_NEXT;
            end if;
          else
            gi <= (others => '0');
            d_j <= (others => '0');
            d_have_scale <= '0';
            fetch_ret <= D_EMIT;
            case to_integer(d_fmt) is
              when 0 => gbytes <= to_unsigned(4, 6);  epg <= to_unsigned(1, 6);
              when 1 | 30 => gbytes <= to_unsigned(2, 6); epg <= to_unsigned(1, 6);
              when 8 => gbytes <= to_unsigned(34, 6); epg <= to_unsigned(32, 6);
              when others => gbytes <= to_unsigned(18, 6); epg <= to_unsigned(32, 6);  -- Q4_0
            end case;
            cstate <= D_FETCH;
          end if;

        when D_FETCH =>
          if gi = gbytes then
            cstate <= fetch_ret;
          elsif ld_valid = '0' or ps(27 downto 8) /= ld_block then
            -- load the rest of this 256-byte block
            a0 := ps(27 downto 3) & "000";
            a1 := (ps(27 downto 8) + 1) & x"00";
            rd_addr <= a0;
            rd_len <= resize(a1 - a0, 9);
            rd_sel <= "01";
            dec_addr <= a0;
            ld_block <= ps(27 downto 8);
            ld_valid <= '1';
            rd_ret <= D_FETCH;
            cstate <= C_RD_DEC;
          else
            wd := bufx(to_integer(ps(7 downto 1)));
            if ps(0) = '0' then
              grp(to_integer(gi)) <= wd(7 downto 0);
            else
              grp(to_integer(gi)) <= wd(15 downto 8);
            end if;
            ps <= ps + 1;
            gi <= gi + 1;
          end if;

        when D_EMIT =>
          case to_integer(d_fmt) is
            when 0 =>                              -- F32: the bits as they are
              d_val <= grp(3) & grp(2) & grp(1) & grp(0);
              cstate <= D_STORE;
            when 30 =>                             -- BF16
              d_val <= grp(1) & grp(0) & x"0000";
              cstate <= D_STORE;
            when 1 =>                              -- F16
              fpu_op <= FOP_F16TOF32;
              fpu_a <= x"0000" & grp(1) & grp(0);
              fpu_start <= '1';
              fpu_ret <= D_QMUL;
              cstate <= C_FPU_WAIT;
            when others =>                         -- Q8_0 / Q4_0
              if d_have_scale = '0' then
                fpu_op <= FOP_F16TOF32;
                fpu_a <= x"0000" & grp(1) & grp(0);
                fpu_start <= '1';
                fpu_ret <= D_SCALE;
                cstate <= C_FPU_WAIT;
              else
                if d_fmt = 8 then
                  q := resize(signed(grp(2 + to_integer(d_j))), 32);
                elsif d_j < 16 then
                  q := resize(signed('0' & grp(2 + to_integer(d_j))(3 downto 0)), 32) - 8;
                else
                  q := resize(signed('0' & grp(2 + to_integer(d_j) - 16)(7 downto 4)), 32) - 8;
                end if;
                fpu_op <= FOP_I2F;
                fpu_a <= unsigned(q);
                fpu_start <= '1';
                fpu_ret <= D_QMUL;
                cstate <= C_FPU_WAIT;
              end if;
          end case;

        when D_SCALE =>
          dq_scale <= fpu_r;
          d_have_scale <= '1';
          cstate <= D_EMIT;

        when D_QMUL =>
          if d_fmt = 1 then
            d_val <= fpu_r;                        -- F16 conversion result
            cstate <= D_STORE;
          else
            fpu_op <= FOP_MUL;                     -- d * q, as F32
            fpu_a <= dq_scale;
            fpu_b <= fpu_r;
            fpu_start <= '1';
            fpu_ret <= D_AFTER;
            cstate <= C_FPU_WAIT;
          end if;

        when D_AFTER =>
          d_val <= fpu_r;
          cstate <= D_STORE;

        when D_STORE =>
          buf(to_integer(pz(7 downto 1))) <= d_val(15 downto 0);
          buf(to_integer(pz(7 downto 1) + 1)) <= d_val(31 downto 16);
          a2 := pz + 4;
          pz <= a2;
          v_n <= v_n - 1;
          d_j <= d_j + 1;
          if a2(7 downto 0) = 0 or v_n = 1 then
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
            if v_n = 1 then
              wr_ret <= C_NEXT;
            elsif d_j + 1 = epg then
              wr_ret <= D_GROUP;
            else
              wr_ret <= D_EMIT;
            end if;
            cstate <= C_WR_DEC;
          elsif d_j + 1 = epg then
            cstate <= D_GROUP;
          else
            cstate <= D_EMIT;
          end if;

        -- ------------------------------------------------------------------
        -- GEMV, phase 1: quantise x to Q8_0 (ssnail_hw.quantize_q8_0)
        when G_QFILL0 =>
          g_j <= (others => '0');
          g_amax <= (others => '0');
          cstate <= G_QFILL;

        when G_QFILL =>
          if g_j = 32 then
            fpu_op <= FOP_DIV;                         -- d = amax / 127
            fpu_a <= '0' & g_amax;
            fpu_b <= x"42FE0000";
            fpu_start <= '1';
            fpu_ret <= G_QID;
            cstate <= C_FPU_WAIT;
          elsif ld_valid = '0' or px(27 downto 8) /= ld_block then
            a0 := px(27 downto 3) & "000";
            a1 := (px(27 downto 8) + 1) & x"00";
            rd_addr <= a0;
            rd_len <= resize(a1 - a0, 9);
            rd_sel <= "01";
            dec_addr <= a0;
            ld_block <= px(27 downto 8);
            ld_valid <= '1';
            rd_ret <= G_QFILL;
            cstate <= C_RD_DEC;
          else
            fv := bufx(to_integer(px(7 downto 1) + 1)) & bufx(to_integer(px(7 downto 1)));
            xb(to_integer(g_j)) <= fv;
            -- |x| ordering = integer ordering of the low 31 bits
            if fv(30 downto 0) > g_amax then
              g_amax <= fv(30 downto 0);
            end if;
            px <= px + 4;
            g_j <= g_j + 1;
          end if;

        when G_QID =>
          g_d <= fpu_r;
          if fpu_r(30 downto 0) = 0 then
            g_id <= (others => '0');                   -- id = d ? 1/d : 0
            cstate <= G_QD16;
          else
            fpu_op <= FOP_DIV;
            fpu_a <= x"3F800000";
            fpu_b <= fpu_r;
            fpu_start <= '1';
            fpu_ret <= G_QID2;
            cstate <= C_FPU_WAIT;
          end if;

        when G_QID2 =>
          g_id <= fpu_r;
          cstate <= G_QD16;

        when G_QD16 =>
          fpu_op <= FOP_F32TOF16;                      -- the stored scale is F16
          fpu_a <= g_d;
          fpu_start <= '1';
          fpu_ret <= G_QDX;
          cstate <= C_FPU_WAIT;

        when G_QDX =>
          fpu_op <= FOP_F16TOF32;
          fpu_a <= fpu_r;
          fpu_start <= '1';
          fpu_ret <= G_QDX2;
          cstate <= C_FPU_WAIT;

        when G_QDX2 =>
          dxs(to_integer(gblk)) <= fpu_r;
          g_j <= (others => '0');
          cstate <= G_QQ;

        when G_QQ =>
          if g_j = 32 then
            gblk <= gblk + 1;
            if gblk + 1 = g_nb then
              cstate <= G_ROW0;
            else
              cstate <= G_QFILL0;
            end if;
          else
            fpu_op <= FOP_MUL;                         -- x * id
            fpu_a <= xb(to_integer(g_j));
            fpu_b <= g_id;
            fpu_start <= '1';
            fpu_ret <= G_QQR;
            cstate <= C_FPU_WAIT;
          end if;

        when G_QQR =>
          fpu_op <= FOP_ROUNDF;
          fpu_a <= fpu_r;
          fpu_start <= '1';
          fpu_ret <= G_QQS;
          cstate <= C_FPU_WAIT;

        when G_QQS =>
          qx(to_integer(gblk & g_j(4 downto 0))) <= signed(fpu_r(7 downto 0));
          g_j <= g_j + 1;
          cstate <= G_QQ;

        -- GEMV, phase 2: each row, block by block (ssnail_hw.gemv_quant)
        when G_ROW0 =>
          ld_valid <= '0';                             -- bufx now holds weights
          out_loaded <= '0';
          g_r <= (others => '0');
          cstate <= G_ROW;

        when G_ROW =>
          if g_r = g_rows then
            cstate <= C_NEXT;                          -- (last row flushed already)
          else
            gblk <= (others => '0');
            cstate <= G_BLK;
          end if;

        when G_BLK =>
          if gblk = g_nb then
            cstate <= G_OUT;
          else
            gi <= (others => '0');
            fetch_ret <= G_DOT0;
            cstate <= D_FETCH;
          end if;

        when G_DOT0 =>
          g_isum <= (others => '0');
          g_k <= (others => '0');
          cstate <= G_DOT;

        when G_DOT =>
          if g_k = 32 then
            fpu_op <= FOP_F16TOF32;                    -- d_w
            fpu_a <= x"0000" & grp(1) & grp(0);
            fpu_start <= '1';
            fpu_ret <= G_SC;
            cstate <= C_FPU_WAIT;
          else
            if d_fmt = 8 then
              qw := resize(signed(grp(2 + to_integer(g_k))), 9);
            elsif g_k < 16 then
              qw := resize(signed('0' & grp(2 + to_integer(g_k))(3 downto 0)), 9) - 8;
            else
              qw := resize(signed('0' & grp(2 + to_integer(g_k) - 16)(7 downto 4)), 9) - 8;
            end if;
            g_isum <= g_isum + resize(qw * qx(to_integer(gblk(6 downto 0) & g_k(4 downto 0))), 32);
            g_k <= g_k + 1;
          end if;

        when G_SC =>
          fpu_op <= FOP_MUL;                           -- scale = d_w * d_x
          fpu_a <= fpu_r;
          fpu_b <= dxs(to_integer(gblk));
          fpu_start <= '1';
          fpu_ret <= G_SC2;
          cstate <= C_FPU_WAIT;

        when G_SC2 =>
          g_scale <= fpu_r;
          fpu_op <= FOP_I2F;                           -- F32(isum)
          fpu_a <= unsigned(g_isum);
          fpu_start <= '1';
          fpu_ret <= G_T;
          cstate <= C_FPU_WAIT;

        when G_T =>
          fpu_op <= FOP_MUL;                           -- term = F32(isum) * scale
          fpu_a <= fpu_r;
          fpu_b <= g_scale;
          fpu_start <= '1';
          fpu_ret <= G_ACC;
          cstate <= C_FPU_WAIT;

        when G_ACC =>
          if gblk = 0 then
            g_accv <= fpu_r;                           -- first term as it is
            gblk <= gblk + 1;
            cstate <= G_BLK;
          else
            fpu_op <= FOP_ADD;                         -- acc = acc + term
            fpu_a <= g_accv;
            fpu_b <= fpu_r;
            fpu_start <= '1';
            fpu_ret <= G_ACC2;
            cstate <= C_FPU_WAIT;
          end if;

        when G_ACC2 =>
          g_accv <= fpu_r;
          gblk <= gblk + 1;
          cstate <= G_BLK;

        when G_OUT =>
          if g_addz = '1' and (out_loaded = '0' or pz(27 downto 8) /= out_block) then
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
            cstate <= C_RD_DEC;
          elsif g_addz = '1' then
            fpu_op <= FOP_ADD;                         -- y = acc + y_old
            fpu_a <= g_accv;
            fpu_b <= buf(to_integer(pz(7 downto 1) + 1)) & buf(to_integer(pz(7 downto 1)));
            fpu_start <= '1';
            fpu_ret <= G_OUT2;
            cstate <= C_FPU_WAIT;
          else
            fpu_r <= g_accv;
            cstate <= G_OUT2;
          end if;

        when G_OUT2 =>
          if g_f16 = '1' then
            fpu_op <= FOP_F32TOF16;
            fpu_a <= fpu_r;
            fpu_start <= '1';
            fpu_ret <= G_OUT3;
            cstate <= C_FPU_WAIT;
          else
            cstate <= G_OUT3;
          end if;

        when G_OUT3 =>
          g_val <= fpu_r;
          cstate <= G_OUT4;

        when G_OUT4 =>
          if g_f16 = '1' then
            buf(to_integer(pz(7 downto 1))) <= g_val(15 downto 0);
            a2 := pz + 2;
          else
            buf(to_integer(pz(7 downto 1))) <= g_val(15 downto 0);
            buf(to_integer(pz(7 downto 1) + 1)) <= g_val(31 downto 16);
            a2 := pz + 4;
          end if;
          pz <= a2;
          g_r <= g_r + 1;
          if a2(7 downto 0) = 0 or g_r + 1 = g_rows then
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
            wr_ret <= G_ROW;
            cstate <= C_WR_DEC;
          else
            cstate <= G_ROW;
          end if;

        -- ------------------------------------------------------------------
        -- Element fetch: ef_val = F32 at ef_addr (F16 converted if ef_f16),
        -- through bufx with whole-block loads.
        when EF_START =>
          if ld_valid = '0' or ef_addr(27 downto 8) /= ld_block then
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
            cstate <= C_RD_DEC;
          elsif ef_f16 = '1' then
            fpu_op <= FOP_F16TOF32;
            fpu_a <= x"0000" & bufx(to_integer(ef_addr(7 downto 1)));
            fpu_start <= '1';
            fpu_ret <= EF_DONE;
            cstate <= C_FPU_WAIT;
          else
            ef_val <= bufx(to_integer(ef_addr(7 downto 1) + 1)) & bufx(to_integer(ef_addr(7 downto 1)));
            cstate <= ef_ret;
          end if;
        when EF_DONE =>
          ef_val <= fpu_r;
          cstate <= ef_ret;

        -- ROPE: load the cos/sin row, then rotate pairs through the engine
        when RO_CS =>
          if cs_i = rope_hd then
            bx <= ea_x; px <= ea_x; pz <= ea_x; v_n <= n0;
            o16 <= '0'; two_ops <= '0'; has_b <= '0'; has_out <= '1';
            ve_kind <= K_ROPE; rope_j <= (others => '0');
            ve_ret <= C_NEXT;
            cstate <= V_CHUNK;
          else
            ef_ret <= RO_CS2;
            cstate <= EF_START;
          end if;
        when RO_CS2 =>
          csv(to_integer(cs_i)) <= ef_val;
          cs_i <= cs_i + 1;
          ef_addr <= ef_addr + 4;
          cstate <= RO_CS;

        when E_R1 =>                                -- a = x0 c; b = x1 s
          rp_a <= fpu_r;
          fpu_op <= FOP_MUL; fpu_a <= x1v; fpu_b <= csv(to_integer(rope_j) + 1);
          fpu_start <= '1'; fpu_ret <= E_R2; cstate <= C_FPU_WAIT;
        when E_R2 =>                                -- r0 = a - b
          fpu_op <= FOP_ADD; fpu_a <= rp_a; fpu_b <= (not fpu_r(31)) & fpu_r(30 downto 0);
          fpu_start <= '1'; fpu_ret <= E_R3; cstate <= C_FPU_WAIT;
        when E_R3 =>                                -- x0 s
          rp0 <= fpu_r;
          fpu_op <= FOP_MUL; fpu_a <= ex; fpu_b <= csv(to_integer(rope_j) + 1);
          fpu_start <= '1'; fpu_ret <= E_R4; cstate <= C_FPU_WAIT;
        when E_R4 =>                                -- x1 c
          rp_b <= fpu_r;
          fpu_op <= FOP_MUL; fpu_a <= x1v; fpu_b <= csv(to_integer(rope_j));
          fpu_start <= '1'; fpu_ret <= E_R5; cstate <= C_FPU_WAIT;
        when E_R5 =>                                -- r1 = x0 s + x1 c
          fpu_op <= FOP_ADD; fpu_a <= rp_b; fpu_b <= fpu_r;
          fpu_start <= '1'; fpu_ret <= E_R6; cstate <= C_FPU_WAIT;
        when E_R6 =>
          iz := pz(7 downto 0) + (v_i(5 downto 0) & "00");
          buf(to_integer(iz(7 downto 1))) <= rp0(15 downto 0);
          buf(to_integer(iz(7 downto 1) + 1)) <= rp0(31 downto 16);
          buf(to_integer(iz(7 downto 1) + 2)) <= fpu_r(15 downto 0);
          buf(to_integer(iz(7 downto 1) + 3)) <= fpu_r(31 downto 16);
          v_i <= v_i + 2;
          if rope_j + 2 = rope_hd then
            rope_j <= (others => '0');
          else
            rope_j <= rope_j + 2;
          end if;
          cstate <= V_EL;

        when AM_DONE =>
          if instr(11 downto 8) /= x"F" then
            rf_r(to_integer(instr(11 downto 8))) <= am_idx;
          end if;
          cstate <= C_NEXT;

        -- ------------------------------------------------------------------
        -- ATTN (ssnail_hw.attention_head, per head)
        when A_PRM =>                               -- read parameter word at_pi
          ef_ret <= A_PRM2;
          cstate <= EF_START;
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
            cstate <= A_RS0;
          else
            cstate <= A_PRM;
          end if;
        when A_RS0 =>
          if at_hd = 0 or at_hd > 256 or at_nkv = 0 or at_nh = 0 or at_pos >= 1024
            or at_nh(15 downto 0) < at_nkv(15 downto 0) then
            err <= ERR_OPCODE;
            cstate <= C_END;
          else
            -- K/V row = n_kv_heads * head_dim elements
            if at_fmt = 1 then
              at_rowb <= resize(at_nkv(13 downto 0) * at_hd(13 downto 0), 27) & '0';
            else
              at_rowb <= resize(at_nkv(12 downto 0) * at_hd(12 downto 0), 26) & "00";
            end if;
            fpu_op <= FOP_I2F; fpu_a <= at_hd; fpu_start <= '1';
            fpu_ret <= A_RS1; cstate <= C_FPU_WAIT;
          end if;
        when A_RS1 =>                               -- rs = 1 / sqrt(hd)
          fpu_op <= FOP_SQRT; fpu_a <= fpu_r; fpu_start <= '1';
          fpu_ret <= A_RS2; cstate <= C_FPU_WAIT;
        when A_RS2 =>
          fpu_op <= FOP_DIV; fpu_a <= x"3F800000"; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= A_RS3; cstate <= C_FPU_WAIT;
        when A_RS3 =>
          at_rs <= fpu_r;
          -- group = n_heads / n_kv_heads, by repeated subtraction
          at_group <= (others => '0');
          at_gc <= at_nh(15 downto 0);
          cstate <= A_GRP;
        when A_GRP =>
          if at_gc >= at_nkv(15 downto 0) then
            at_gc <= at_gc - at_nkv(15 downto 0);
            at_group <= at_group + 1;
          else
            at_h <= (others => '0');
            at_kvh <= (others => '0');
            at_gc <= (others => '0');
            pz <= ea_z; ostart <= ea_z;
            cstate <= A_HEAD;
          end if;

        when A_HEAD =>                              -- load q for head at_h
          if at_h = at_nh(15 downto 0) then
            cstate <= C_NEXT;
          else
            at_i <= (others => '0');
            ef_addr <= ea_y + resize(at_h * at_hd(15 downto 0) * 4, 28);
            ef_f16 <= '0';
            cstate <= A_Q;
          end if;
        when A_Q =>
          if at_i = at_hd(8 downto 0) then
            at_t <= (others => '0');
            at_rowaddr <= at_k;
            cstate <= A_S_T;
          else
            ef_ret <= A_Q2;
            cstate <= EF_START;
          end if;
        when A_Q2 =>
          qv(to_integer(at_i)) <= ef_val;
          at_i <= at_i + 1;
          ef_addr <= ef_addr + 4;
          cstate <= A_Q;

        -- scores: s_t = seq_sum(k_t * q) * rs; track the maximum
        when A_S_T =>
          if at_t = at_pos(15 downto 0) + 1 then
            at_t <= (others => '0');
            ve_first <= '1';
            cstate <= A_E_T;
          else
            at_i <= (others => '0');
            ve_first <= '1';
            if at_fmt = 1 then
              ef_addr <= at_rowaddr + resize(at_kvh * at_hd(15 downto 0) * 2, 28);
              ef_f16 <= '1';
            else
              ef_addr <= at_rowaddr + resize(at_kvh * at_hd(15 downto 0) * 4, 28);
              ef_f16 <= '0';
            end if;
            cstate <= A_S_I;
          end if;
        when A_S_I =>
          if at_i = at_hd(8 downto 0) then
            fpu_op <= FOP_MUL; fpu_a <= at_acc; fpu_b <= at_rs; fpu_start <= '1';
            fpu_ret <= A_S_SC; cstate <= C_FPU_WAIT;
          else
            ef_ret <= A_S_I2;
            cstate <= EF_START;
          end if;
        when A_S_I2 =>
          fpu_op <= FOP_MUL; fpu_a <= ef_val; fpu_b <= qv(to_integer(at_i)); fpu_start <= '1';
          fpu_ret <= A_S_I3; cstate <= C_FPU_WAIT;
        when A_S_I3 =>
          if ve_first = '1' then
            at_acc <= fpu_r; ve_first <= '0';
            cstate <= A_S_I4;
          else
            fpu_op <= FOP_ADD; fpu_a <= at_acc; fpu_b <= fpu_r; fpu_start <= '1';
            fpu_ret <= A_S_SC2; cstate <= C_FPU_WAIT;
          end if;
        when A_S_SC2 =>
          at_acc <= fpu_r;
          cstate <= A_S_I4;
        when A_S_I4 =>
          at_i <= at_i + 1;
          if at_fmt = 1 then ef_addr <= ef_addr + 2; else ef_addr <= ef_addr + 4; end if;
          cstate <= A_S_I;
        when A_S_SC =>
          sarr(to_integer(at_t(9 downto 0))) <= fpu_r;
          if at_t = 0 or flt(at_m, fpu_r) then
            at_m <= fpu_r;
          end if;
          at_t <= at_t + 1;
          at_rowaddr <= at_rowaddr + at_rowb;
          cstate <= A_S_T;

        -- e_t = EXP(s_t - m); z = seq_sum(e)
        when A_E_T =>
          if at_t = at_pos(15 downto 0) + 1 then
            fpu_op <= FOP_DIV; fpu_a <= x"3F800000"; fpu_b <= at_acc; fpu_start <= '1';
            fpu_ret <= A_E_R; cstate <= C_FPU_WAIT;
          else
            fpu_op <= FOP_ADD; fpu_a <= sarr(to_integer(at_t(9 downto 0)));
            fpu_b <= (not at_m(31)) & at_m(30 downto 0);
            fpu_start <= '1'; fpu_ret <= A_E_1; cstate <= C_FPU_WAIT;
          end if;
        when A_E_1 =>
          tx <= fpu_r; tab_id <= "10"; tab_ret <= A_E_2;
          cstate <= T_START;
        when A_E_2 =>
          sarr(to_integer(at_t(9 downto 0))) <= tval;
          if ve_first = '1' then
            at_acc <= tval; ve_first <= '0';
            at_t <= at_t + 1;
            cstate <= A_E_T;
          else
            fpu_op <= FOP_ADD; fpu_a <= at_acc; fpu_b <= tval; fpu_start <= '1';
            fpu_ret <= A_E_3; cstate <= C_FPU_WAIT;
          end if;
        when A_E_3 =>
          at_acc <= fpu_r;
          at_t <= at_t + 1;
          cstate <= A_E_T;
        when A_E_R =>                               -- r = 1 / z; w_t = e_t * r
          at_r <= fpu_r;
          at_t <= (others => '0');
          cstate <= A_W_T;
        when A_W_T =>
          if at_t = at_pos(15 downto 0) + 1 then
            at_t <= (others => '0');
            at_rowaddr <= at_v;
            cstate <= A_O_T;
          else
            fpu_op <= FOP_MUL; fpu_a <= sarr(to_integer(at_t(9 downto 0))); fpu_b <= at_r;
            fpu_start <= '1'; fpu_ret <= A_W_1; cstate <= C_FPU_WAIT;
          end if;
        when A_W_1 =>
          sarr(to_integer(at_t(9 downto 0))) <= fpu_r;
          at_t <= at_t + 1;
          cstate <= A_W_T;
        when A_E_R2 =>
          cstate <= A_W_T;

        -- out = out + w_t * v_t, sequentially over t
        when A_O_T =>
          if at_t = at_pos(15 downto 0) + 1 then
            at_i <= (others => '0');
            cstate <= A_WR;
          else
            at_i <= (others => '0');
            at_w <= sarr(to_integer(at_t(9 downto 0)));
            if at_fmt = 1 then
              ef_addr <= at_rowaddr + resize(at_kvh * at_hd(15 downto 0) * 2, 28);
              ef_f16 <= '1';
            else
              ef_addr <= at_rowaddr + resize(at_kvh * at_hd(15 downto 0) * 4, 28);
              ef_f16 <= '0';
            end if;
            cstate <= A_O_I;
          end if;
        when A_O_I =>
          if at_i = at_hd(8 downto 0) then
            at_t <= at_t + 1;
            at_rowaddr <= at_rowaddr + at_rowb;
            cstate <= A_O_T;
          else
            ef_ret <= A_O_I2;
            cstate <= EF_START;
          end if;
        when A_O_I2 =>
          fpu_op <= FOP_MUL; fpu_a <= at_w; fpu_b <= ef_val; fpu_start <= '1';
          fpu_ret <= A_O_I3; cstate <= C_FPU_WAIT;
        when A_O_I3 =>
          -- out starts at +0: the first row adds to +0, not to an old value
          if at_t = 0 then
            fpu_a <= (others => '0');
          else
            fpu_a <= outv(to_integer(at_i));
          end if;
          fpu_op <= FOP_ADD; fpu_b <= fpu_r; fpu_start <= '1';
          fpu_ret <= A_O_I4; cstate <= C_FPU_WAIT;
        when A_O_I4 =>
          outv(to_integer(at_i)) <= fpu_r;
          at_i <= at_i + 1;
          if at_fmt = 1 then ef_addr <= ef_addr + 2; else ef_addr <= ef_addr + 4; end if;
          cstate <= A_O_I;

        -- write this head's output: through buf, flushed at 256-byte
        -- boundaries and at the end of the head
        when A_WR =>
          if at_i = at_hd(8 downto 0) then
            cstate <= A_HNEXT;
          else
            buf(to_integer(pz(7 downto 1))) <= outv(to_integer(at_i))(15 downto 0);
            buf(to_integer(pz(7 downto 1) + 1)) <= outv(to_integer(at_i))(31 downto 16);
            a2 := pz + 4;
            pz <= a2;
            at_i <= at_i + 1;
            if a2(7 downto 0) = 0 or at_i + 1 = at_hd(8 downto 0) then
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
              cstate <= C_WR_DEC;
            end if;
          end if;
        when A_WR2 =>
          cstate <= A_HNEXT;
        when A_HNEXT =>
          at_h <= at_h + 1;
          if at_gc + 1 = at_group then
            at_gc <= (others => '0');
            at_kvh <= at_kvh + 1;
          else
            at_gc <= at_gc + 1;
          end if;
          cstate <= A_HEAD;

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

  fpu0 : entity work.ssnail_fpu
    port map (clock => clock162, start => fpu_start, op => fpu_op, a => fpu_a, b => fpu_b,
              done => fpu_done, result => fpu_res);

  -- Ring read port (asynchronous LUT RAM read, registered in the core).  The
  -- cpuclock side only writes blocks the core is not reading.
  ring_rd_lo <= ring_lo(to_integer(ring_rd_idx));
  ring_rd_hi <= ring_hi(to_integer(ring_rd_idx));

end shell;
