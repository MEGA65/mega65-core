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
-- Instruction format: 16 bytes, 16-byte aligned, little-endian.
--   byte 0 = opcode
--   $00 NOP
--   $01 HALT                 job done
--   $02 SYNC                 INVALIDATE on every present LUMP port
--   $03 COPY                 bytes 4-7 source address (28 bits)
--                            bytes 8-11 destination address (28 bits)
--                            bytes 12-13 length in bytes
--                            Addresses 8-byte aligned, length a multiple of 8.
--                            Overlapping copies are undefined.
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
    C_FETCH_SETUP, C_FETCH_DECODE, C_FETCH_ISSUE, C_FETCH_WAIT, C_DECODE,
    C_COPY_CALC, C_COPY_RD_DECODE, C_COPY_RD_ISSUE, C_COPY_RD_WAIT,
    C_COPY_WR_DECODE, C_COPY_WR_ISSUE, C_COPY_WR_WAIT,
    C_SYNC_ISSUE, C_SYNC_WAIT,
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

  -- COPY state
  signal cp_src, cp_dst : unsigned(27 downto 0) := (others => '0');
  signal cp_remaining   : unsigned(15 downto 0) := (others => '0');
  signal cp_chunk       : unsigned(8 downto 0) := (others => '0');

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

  attribute ram_style : string;
  attribute ram_style of buf : signal is "distributed";

  attribute async_reg : string;
  attribute async_reg of go_s1, go_s2, abort_s1, abort_s2 : signal is "true";
  attribute async_reg of sync_s1, sync_s2, step_s1, step_s2 : signal is "true";
  attribute async_reg of pub_tgl_s1, pub_tgl_s2 : signal is "true";

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
           hr_size_mb, sd_base_mb, sd_size_mb) is
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
          when others => null;
        end case;
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
  begin
    if rising_edge(clock162) then
      hr_issue := '0';
      sd_issue := '0';

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
        wdata_r  <= buf(to_integer(buf_ridx));
        buf_ridx <= buf_ridx + 1;
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
          if go_s2 /= go_last or step_s2 /= step_last then
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
            cstate <= C_DECODE;
          end if;

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
              cp_src <= instr(59 downto 32);
              cp_dst <= instr(91 downto 64);
              cp_remaining <= instr(111 downto 96);
              if instr(34 downto 32) /= "000" or instr(66 downto 64) /= "000"
                or instr(98 downto 96) /= "000" then
                err <= ERR_ALIGNMENT;
                cstate <= C_END;
              else
                cstate <= C_COPY_CALC;
              end if;
            when others =>
              err <= ERR_OPCODE;
              cstate <= C_END;
          end case;
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

        when C_NEXT =>
          pc <= pc + 16;
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
  hr_wdata_be <= "11";
  sd_wdata_be <= "11";

end shell;
