--------------------------------------------------------------------------------
-- fat32_engine: the hardware FAT32 engine's 8-bit MCU (MEGA65/mega65-core#766)
--
-- Runs the firmware in fat32_rom_pkg (src/fat32/engine.fs, assembled by
-- src/tools/fat32sim.py, whose docstring is the instruction reference; the
-- simulator there is the golden model, and tb_fat32_engine replays its
-- transcripts against this).  Design: docs/sdcard-native/fat32-engine.md.
--
-- The engine has no memory of its own: its tables, its sector slot ($800)
-- and the CPU's SD half ($E00) are all in the sector buffer, reached through
-- a read port (G_RD_LAT cycles from address to data) and a write port.
-- Sector reads and writes are requests to the upper SD controller, which
-- moves the data between the card (or the cache) and the buffer.
--
-- One instruction takes 2 cycles (fetch, execute); memory, shifts and the
-- microsequenced instructions (copy, fill, scmp, lfnput, fatnx, ...) take
-- longer.  The ROM is LUTs: 2K x 24 bits at most.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.fat32_rom_pkg.all;

entity fat32_engine is
  generic (
    G_RD_LAT : positive := 2           -- cycles from mem_raddr to mem_rdata
    );
  port (
    clock      : in  std_logic;
    reset      : in  std_logic;

    -- a command ($70-$7F): start for one cycle while busy = '0'
    start      : in  std_logic;
    cmd        : in  unsigned(7 downto 0);
    arg_in     : in  unsigned(31 downto 0);
    hypervisor : in  std_logic;
    busy       : out std_logic;
    status     : out unsigned(7 downto 0);   -- 0: done; else the error
    arg_out    : out unsigned(31 downto 0);  -- $D681-$D684 afterwards

    -- the sector buffer
    mem_raddr  : out unsigned(11 downto 0);
    mem_rdata  : in  unsigned(7 downto 0);
    mem_we     : out std_logic;
    mem_waddr  : out unsigned(11 downto 0);
    mem_wdata  : out unsigned(7 downto 0);

    -- sector requests: held until sec_done (one cycle)
    sec_req    : out std_logic;
    sec_write  : out std_logic;              -- '1' write to the card
    sec_cpu    : out std_logic;              -- '1' the CPU's half ($E00), else $800
    sec_slot   : out std_logic;              -- the card
    sec_lba    : out unsigned(31 downto 0);
    sec_done   : in  std_logic;
    sec_err    : in  std_logic
    );
end entity;

architecture rtl of fat32_engine is

  type t_r is array(0 to 15) of unsigned(7 downto 0);
  type t_l is array(0 to 7) of unsigned(31 downto 0);
  type t_stack is array(0 to 7) of unsigned(10 downto 0);

  type t_state is (
    S_IDLE, S_FETCH, S_EXEC,
    S_RD,                               -- a byte read, then back to rd_next
    S_LD, S_LLD,                        -- loads
    S_LST,                              -- 32/16-bit stores
    S_SHIFT,
    S_COPY_W, S_FILL,
    S_SCMP_A, S_SCMP_B,
    S_LFN_SEQ, S_LFN_LO, S_LFN_HI,
    S_SUM,
    S_SEC,
    S_FAT_RD, S_FAT_LD,
    S_FS_RD, S_FS_WAIT, S_FS_PATCH, S_FS_WR, S_FS_WWAIT
    );
  signal state   : t_state := S_IDLE;
  signal rd_next : t_state := S_IDLE;   -- where S_RD goes with the byte
  signal rd_cnt  : natural range 0 to G_RD_LAT := 0;

  signal pc   : unsigned(10 downto 0) := (others => '0');
  signal ir   : std_logic_vector(23 downto 0) := (others => '0');
  signal r    : t_r := (others => (others => '0'));
  signal l    : t_l := (others => (others => '0'));
  signal x, y : unsigned(11 downto 0) := (others => '0');
  signal zf, cf, ef : std_logic := '0';
  signal stack : t_stack := (others => (others => '0'));
  signal sp   : natural range 0 to 8 := 0;
  signal slot : std_logic := '0';

  signal cmd_r : unsigned(7 downto 0) := (others => '0');
  signal arg_r : unsigned(31 downto 0) := (others => '0');
  signal hyp_r : std_logic := '0';
  signal busy_r : std_logic := '0';
  signal status_r : unsigned(7 downto 0) := (others => '0');

  -- microsequencers
  signal ma     : unsigned(11 downto 0) := (others => '0');  -- address
  signal acc    : unsigned(31 downto 0) := (others => '0');  -- bytes read
  signal cnt    : unsigned(8 downto 0) := (others => '0');   -- bytes / steps left
  signal idx    : unsigned(8 downto 0) := (others => '0');
  signal byte   : unsigned(7 downto 0) := (others => '0');
  signal sum    : unsigned(7 downto 0) := (others => '0');
  signal lfnbase : unsigned(11 downto 0) := (others => '0');
  signal fat_k  : unsigned(7 downto 0) := (others => '0');
  signal fs_lba : unsigned(31 downto 0) := (others => '0');

  signal sec_req_r   : std_logic := '0';
  signal sec_write_r : std_logic := '0';
  signal sec_cpu_r   : std_logic := '0';
  signal sec_lba_r   : unsigned(31 downto 0) := (others => '0');
  signal we    : std_logic := '0';
  signal waddr : unsigned(11 downto 0) := (others => '0');
  signal wdata : unsigned(7 downto 0) := (others => '0');

  -- LFN character positions in an entry
  type t_pos is array(0 to 12) of natural range 0 to 31;
  constant LFN_POS : t_pos := (1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30);

  function b2l(b : boolean) return std_logic is
  begin
    if b then
      return '1';
    end if;
    return '0';
  end function;

  function upc(c : unsigned(7 downto 0)) return unsigned is
  begin
    if c >= 97 and c <= 122 then
      return c - 32;
    end if;
    return c;
  end function;

begin

  busy      <= busy_r;
  status    <= status_r;
  arg_out   <= arg_r;
  mem_raddr <= ma;
  mem_we    <= we;
  mem_waddr <= waddr;
  mem_wdata <= wdata;
  sec_req   <= sec_req_r;
  sec_write <= sec_write_r;
  sec_cpu   <= sec_cpu_r;
  sec_slot  <= slot;
  sec_lba   <= sec_lba_r;

  process(clock)
    variable opc  : natural range 0 to 127;
    variable ra, rb : natural range 0 to 15;
    variable la, lb : natural range 0 to 7;
    variable n8   : unsigned(7 downto 0);
    variable s13  : unsigned(31 downto 0);
    variable u13  : unsigned(31 downto 0);
    variable a11  : unsigned(10 downto 0);
    variable msel : std_logic;
    variable madr : unsigned(11 downto 0);
    variable t9   : unsigned(8 downto 0);
    variable t33  : unsigned(32 downto 0);
    variable v8   : unsigned(7 downto 0);
    variable v32  : unsigned(31 downto 0);
    variable seq  : natural range 0 to 31;

    procedure finish(code : unsigned(7 downto 0)) is
    begin
      status_r <= code;
      busy_r   <= '0';
      state    <= S_IDLE;
    end procedure;

    procedure read_byte(a : unsigned(11 downto 0); nxt : t_state) is
    begin
      ma      <= a;
      rd_cnt  <= G_RD_LAT;
      rd_next <= nxt;
      state   <= S_RD;
    end procedure;

    procedure write_byte(a : unsigned(11 downto 0); d : unsigned(7 downto 0)) is
    begin
      we    <= '1';
      waddr <= a;
      wdata <= d;
    end procedure;

    procedure sector(wr : std_logic; cpu : std_logic; lba : unsigned(31 downto 0);
                     nxt : t_state) is
    begin
      sec_req_r   <= '1';
      sec_write_r <= wr;
      sec_cpu_r   <= cpu;
      sec_lba_r   <= lba;
      state       <= nxt;
    end procedure;

  begin
    if rising_edge(clock) then
      we <= '0';

      opc  := to_integer(unsigned(ir(23 downto 17)));
      ra   := to_integer(unsigned(ir(16 downto 13)));
      rb   := to_integer(unsigned(ir(12 downto 9)));
      la   := to_integer(unsigned(ir(15 downto 13)));
      lb   := to_integer(unsigned(ir(11 downto 9)));
      n8   := unsigned(ir(7 downto 0));
      u13  := resize(unsigned(ir(12 downto 0)), 32);
      s13  := unsigned(resize(signed(ir(12 downto 0)), 32));
      a11  := unsigned(ir(10 downto 0));
      msel := ir(12);
      if msel = '0' then
        madr := x + resize(n8, 12);
      else
        madr := y + resize(n8, 12);
      end if;

      case state is

        when S_IDLE =>
          if start = '1' then
            cmd_r    <= cmd;
            arg_r    <= arg_in;
            hyp_r    <= hypervisor;
            busy_r   <= '1';
            status_r <= (others => '0');
            pc       <= (others => '0');
            sp       <= 0;
            state    <= S_FETCH;
          end if;

        when S_FETCH =>
          ir    <= FAT32_ROM(to_integer(pc));
          pc    <= pc + 1;
          state <= S_EXEC;

        when S_RD =>
          if rd_cnt = 0 then
            byte  <= mem_rdata;
            state <= rd_next;
          else
            rd_cnt <= rd_cnt - 1;
          end if;

        when S_EXEC =>
          state <= S_FETCH;
          case opc is
            -- bytes
            when OP_LDI =>
              r(ra) <= n8;
              zf <= b2l(n8 = 0);
            when OP_ADDI | OP_ADD | OP_SUBI | OP_SUB =>
              if opc = OP_ADDI or opc = OP_SUBI then
                v8 := n8;
              else
                v8 := r(rb);
              end if;
              if opc = OP_ADDI or opc = OP_ADD then
                t9 := ('0' & r(ra)) + ('0' & v8);
              else
                t9 := ('0' & r(ra)) - ('0' & v8);
              end if;
              r(ra) <= t9(7 downto 0);
              cf    <= t9(8);
              zf <= b2l(t9(7 downto 0) = 0);
            when OP_ANDI | OP_ORI | OP_XORI | OP_AND | OP_OR | OP_XOR | OP_MOV =>
              if opc = OP_ANDI or opc = OP_ORI or opc = OP_XORI then
                v8 := n8;
              else
                v8 := r(rb);
              end if;
              if opc = OP_ANDI or opc = OP_AND then
                v8 := r(ra) and v8;
              elsif opc = OP_ORI or opc = OP_OR then
                v8 := r(ra) or v8;
              elsif opc = OP_XORI or opc = OP_XOR then
                v8 := r(ra) xor v8;
              end if;
              r(ra) <= v8;
              zf <= b2l(v8 = 0);
            when OP_CMPI | OP_CMP =>
              if opc = OP_CMPI then
                v8 := n8;
              else
                v8 := r(rb);
              end if;
              zf <= b2l(r(ra) = v8);
              cf <= b2l(r(ra) < v8);
            when OP_SHL =>
              r(ra) <= r(ra)(6 downto 0) & '0';
              cf    <= r(ra)(7);
              zf <= b2l(r(ra)(6 downto 0) = 0);
            when OP_SHR =>
              r(ra) <= '0' & r(ra)(7 downto 1);
              cf    <= r(ra)(0);
              zf <= b2l(r(ra)(7 downto 1) = 0);
            when OP_INC | OP_DEC =>
              if opc = OP_INC then
                v8 := r(ra) + 1;
              else
                v8 := r(ra) - 1;
              end if;
              r(ra) <= v8;
              zf <= b2l(v8 = 0);
            when OP_LD =>
              read_byte(madr, S_LD);
            when OP_LDX =>
              read_byte(x, S_LD);
              x <= x + 1;
            when OP_ST =>
              write_byte(madr, r(ra));
            when OP_STY =>
              write_byte(y, r(ra));
              y <= y + 1;

            -- longs
            when OP_LLDI | OP_LMOV | OP_LAND | OP_LANDI | OP_LOR | OP_BTOL =>
              case opc is
                when OP_LLDI  => v32 := u13;
                when OP_LMOV  => v32 := l(lb);
                when OP_LAND  => v32 := l(la) and l(lb);
                when OP_LANDI => v32 := l(la) and u13;
                when OP_LOR   => v32 := l(la) or l(lb);
                when others   => v32 := resize(r(rb), 32);
              end case;
              l(la) <= v32;
              zf <= b2l(v32 = 0);
            when OP_LADD | OP_LADDI | OP_LSUB | OP_LSUBI =>
              if opc = OP_LADD or opc = OP_LSUB then
                v32 := l(lb);
              else
                v32 := s13;
              end if;
              if opc = OP_LADD or opc = OP_LADDI then
                t33 := ('0' & l(la)) + ('0' & v32);
              else
                t33 := ('0' & l(la)) - ('0' & v32);
              end if;
              l(la) <= t33(31 downto 0);
              cf    <= t33(32);
              zf <= b2l(t33(31 downto 0) = 0);
            when OP_LCMP | OP_LCMPI =>
              if opc = OP_LCMP then
                v32 := l(lb);
              else
                v32 := u13;
              end if;
              zf <= b2l(l(la) = v32);
              cf <= b2l(l(la) < v32);
            when OP_LZ =>
              zf <= b2l(l(la) = 0);
            when OP_LSHL | OP_LSHR | OP_LSHLR | OP_LSHRR =>
              if opc = OP_LSHL or opc = OP_LSHR then
                cnt <= resize(unsigned(ir(4 downto 0)), 9);
              else
                cnt <= resize(r(rb)(4 downto 0), 9);
              end if;
              state <= S_SHIFT;
            when OP_LLD | OP_LLDW =>
              ma  <= madr;
              acc <= (others => '0');
              idx <= (others => '0');
              if opc = OP_LLD then
                cnt <= to_unsigned(4, 9);
              else
                cnt <= to_unsigned(2, 9);
              end if;
              read_byte(madr, S_LLD);
            when OP_LST | OP_LSTW =>
              ma  <= madr;
              acc <= l(la);
              if opc = OP_LST then
                cnt <= to_unsigned(4, 9);
              else
                cnt <= to_unsigned(2, 9);
              end if;
              state <= S_LST;
            when OP_LTOB =>
              case ir(1 downto 0) is
                when "00"   => v8 := l(lb)(7 downto 0);
                when "01"   => v8 := l(lb)(15 downto 8);
                when "10"   => v8 := l(lb)(23 downto 16);
                when others => v8 := l(lb)(31 downto 24);
              end case;
              r(ra) <= v8;
              zf <= b2l(v8 = 0);

            -- pointers
            when OP_XSET  => x <= unsigned(ir(11 downto 0));
            when OP_YSET  => y <= unsigned(ir(11 downto 0));
            when OP_XADDI => x <= x + unsigned(ir(11 downto 0));
            when OP_YADDI => y <= y + unsigned(ir(11 downto 0));
            when OP_XADD  => x <= x + resize(r(ra), 12);
            when OP_YADD  => y <= y + resize(r(ra), 12);
            when OP_XL    => x <= l(la)(11 downto 0);
            when OP_YL    => y <= l(la)(11 downto 0);
            when OP_LX    => l(la) <= resize(x, 32);
            when OP_LY    => l(la) <= resize(y, 32);
            when OP_XY    => x <= y; y <= x;

            -- control
            when OP_JMP => pc <= a11;
            when OP_JZ  => if zf = '1' then pc <= a11; end if;
            when OP_JNZ => if zf = '0' then pc <= a11; end if;
            when OP_JC  => if cf = '1' then pc <= a11; end if;
            when OP_JNC => if cf = '0' then pc <= a11; end if;
            when OP_JE  => if ef = '1' then pc <= a11; end if;
            when OP_JNE => if ef = '0' then pc <= a11; end if;
            when OP_CALL =>
              if sp = 8 then
                finish(x"FD");          -- (stack overflow)
              else
                stack(sp) <= pc;
                sp <= sp + 1;
                pc <= a11;
              end if;
            when OP_RET =>
              if sp = 0 then
                finish(x"FD");
              else
                pc <= stack(sp - 1);
                sp <= sp - 1;
              end if;

            -- the card
            when OP_SLOT => slot <= r(ra)(0);
            when OP_SREAD  => sector('0', '0', l(la), S_SEC);
            when OP_SWRITE => sector('1', '0', l(la), S_SEC);
            when OP_DREAD  => sector('0', '1', l(la), S_SEC);
            when OP_DWRITE => sector('1', '1', l(la), S_SEC);
            when OP_FATNX =>
              sector('0', '0', l(6) + resize(l(la)(31 downto 7), 32), S_FAT_RD);
            when OP_FATSET =>
              fat_k  <= (others => '0');
              fs_lba <= l(6) + resize(l(la)(31 downto 7), 32);
              state  <= S_FS_RD;

            -- names, copies
            when OP_NCMP | OP_SCMP =>
              idx <= (others => '0');
              if opc = OP_NCMP then
                cnt <= '0' & n8;
              else
                cnt <= (others => '0');   -- (0: until the terminator)
              end if;
              zf <= '1';
              if not (opc = OP_NCMP and n8 = 0) then
                read_byte(x, S_SCMP_A);
              end if;
            when OP_LFNPUT =>
              read_byte(x, S_LFN_SEQ);
            when OP_LFNSUM =>
              sum <= (others => '0');
              idx <= (others => '0');
              read_byte(x, S_SUM);
            when OP_COPY =>
              if r(ra) = 0 then
                cnt <= to_unsigned(256, 9);
              else
                cnt <= '0' & r(ra);
              end if;
              read_byte(x, S_COPY_W);
            when OP_FILL =>
              if r(ra) = 0 then
                cnt <= to_unsigned(256, 9);
              else
                cnt <= '0' & r(ra);
              end if;
              state <= S_FILL;

            -- the command
            when OP_CMD    => r(ra) <= cmd_r;
            when OP_ARG    => l(la) <= arg_r;
            when OP_SETARG => arg_r <= l(la);
            when OP_HYP    => cf <= hyp_r;
            when OP_DONE   => finish(x"00");
            when OP_FAIL   => finish(n8);
            when OP_FAILR =>
              if r(ra) = 0 then
                finish(x"FF");
              else
                finish(r(ra));
              end if;
            when others =>
              finish(x"FE");            -- (no such instruction)
          end case;

        when S_LD =>
          r(ra) <= byte;
          zf <= b2l(byte = 0);
          state <= S_FETCH;

        when S_LLD =>
          -- bytes arrive low first
          case idx(1 downto 0) is
            when "00"   => acc(7 downto 0)   <= byte;
            when "01"   => acc(15 downto 8)  <= byte;
            when "10"   => acc(23 downto 16) <= byte;
            when others => acc(31 downto 24) <= byte;
          end case;
          if cnt = 1 then
            v32 := acc;
            case idx(1 downto 0) is
              when "00"   => v32(7 downto 0)   := byte;
              when "01"   => v32(15 downto 8)  := byte;
              when "10"   => v32(23 downto 16) := byte;
              when others => v32(31 downto 24) := byte;
            end case;
            l(la) <= v32;
            zf <= b2l(v32 = 0);
            state <= S_FETCH;
          else
            cnt <= cnt - 1;
            idx <= idx + 1;
            read_byte(ma + 1, S_LLD);
          end if;

        when S_LST =>
          write_byte(ma, acc(7 downto 0));
          acc <= x"00" & acc(31 downto 8);
          ma  <= ma + 1;
          cnt <= cnt - 1;
          if cnt = 1 then
            state <= S_FETCH;
          end if;

        when S_SHIFT =>
          if cnt = 0 then
            zf <= b2l(l(la) = 0);
            state <= S_FETCH;
          else
            if opc = OP_LSHL or opc = OP_LSHLR then
              l(la) <= l(la)(30 downto 0) & '0';
            else
              l(la) <= '0' & l(la)(31 downto 1);
            end if;
            cnt <= cnt - 1;
          end if;

        when S_COPY_W =>
          write_byte(y, byte);
          x   <= x + 1;
          y   <= y + 1;
          cnt <= cnt - 1;
          if cnt = 1 then
            state <= S_FETCH;
          else
            read_byte(x + 1, S_COPY_W);
          end if;

        when S_FILL =>
          write_byte(y, r(0));
          y   <= y + 1;
          cnt <= cnt - 1;
          if cnt = 1 then
            state <= S_FETCH;
          end if;

        when S_SCMP_A =>
          acc(7 downto 0) <= upc(byte);
          read_byte(y + resize(idx, 12), S_SCMP_B);

        when S_SCMP_B =>
          if acc(7 downto 0) /= upc(byte) then
            zf    <= '0';
            state <= S_FETCH;
          elsif (opc = OP_SCMP and byte = 0) or (opc = OP_NCMP and idx + 1 = cnt) then
            state <= S_FETCH;
          else
            idx <= idx + 1;
            read_byte(x + resize(idx + 1, 12), S_SCMP_A);
          end if;

        when S_LFN_SEQ =>
          seq := to_integer(byte(4 downto 0));
          if seq >= 1 and seq <= 20 then
            lfnbase <= y + to_unsigned(13 * (seq - 1), 12);
            idx     <= (others => '0');
            read_byte(x + LFN_POS(0), S_LFN_LO);
          else
            state <= S_FETCH;
          end if;

        when S_LFN_LO =>
          acc(7 downto 0) <= byte;
          read_byte(x + LFN_POS(to_integer(idx(3 downto 0))) + 1, S_LFN_HI);

        when S_LFN_HI =>
          -- 0 and $FFFF are padding (0), others above ASCII are '?'
          if byte = 0 and acc(7) = '0' then
            v8 := acc(7 downto 0);
          elsif byte = x"FF" and acc(7 downto 0) = x"FF" then
            v8 := x"00";
          else
            v8 := x"3F";
          end if;
          write_byte(lfnbase + resize(idx, 12), v8);
          if idx = 12 then
            state <= S_FETCH;
          else
            idx <= idx + 1;
            read_byte(x + LFN_POS(to_integer(idx(3 downto 0)) + 1), S_LFN_LO);
          end if;

        when S_SUM =>
          v8 := (sum(0) & sum(7 downto 1)) + byte;
          sum <= v8;
          if idx = 10 then
            r(ra) <= v8;
            state <= S_FETCH;
          else
            idx <= idx + 1;
            read_byte(x + resize(idx + 1, 12), S_SUM);
          end if;

        when S_SEC =>
          if sec_done = '1' then
            sec_req_r <= '0';
            ef        <= sec_err;
            state     <= S_FETCH;
          end if;

        -- fatnx: the FAT sector into the slot, then the entry
        when S_FAT_RD =>
          if sec_done = '1' then
            sec_req_r <= '0';
            ef        <= sec_err;
            ma        <= "100" & l(la)(6 downto 0) & "00";
            idx       <= (others => '0');
            cnt       <= to_unsigned(4, 9);
            acc       <= (others => '0');
            read_byte("100" & l(la)(6 downto 0) & "00", S_FAT_LD);
          end if;

        when S_FAT_LD =>
          v32 := acc;
          case idx(1 downto 0) is
            when "00"   => v32(7 downto 0)   := byte;
            when "01"   => v32(15 downto 8)  := byte;
            when "10"   => v32(23 downto 16) := byte;
            when others => v32(31 downto 24) := byte;
          end case;
          acc <= v32;
          if cnt = 1 then
            v32(31 downto 28) := "0000";
            l(la) <= v32;
            zf <= b2l(v32 >= x"0FFFFFF8");
            cf <= b2l(v32 = 0 or v32 = 1 or v32 = x"0FFFFFF7");
            state <= S_FETCH;
          else
            cnt <= cnt - 1;
            idx <= idx + 1;
            read_byte(ma + 1, S_FAT_LD);
            ma <= ma + 1;
          end if;

        -- fatset: each FAT's sector into the slot, the entry patched, back
        when S_FS_RD =>
          sector('0', '0', fs_lba, S_FS_WAIT);

        when S_FS_WAIT =>
          if sec_done = '1' then
            sec_req_r <= '0';
            ef        <= sec_err;
            if sec_err = '1' then
              state <= S_FETCH;
            else
              ma    <= "100" & l(la)(6 downto 0) & "00";
              acc   <= l(lb);
              cnt   <= to_unsigned(4, 9);
              read_byte("100" & l(la)(6 downto 0) & "11", S_FS_PATCH);
            end if;
          end if;

        when S_FS_PATCH =>
          -- the top 4 bits of the entry are kept
          acc(31 downto 28) <= byte(7 downto 4);
          state <= S_FS_WR;

        when S_FS_WR =>
          write_byte(ma, acc(7 downto 0));
          acc <= x"00" & acc(31 downto 8);
          ma  <= ma + 1;
          cnt <= cnt - 1;
          if cnt = 1 then
            sector('1', '0', fs_lba, S_FS_WWAIT);
          end if;

        when S_FS_WWAIT =>
          if sec_done = '1' then
            sec_req_r <= '0';
            ef        <= sec_err;
            if fat_k + 1 >= r(14) or sec_err = '1' then
              state <= S_FETCH;
            else
              fat_k  <= fat_k + 1;
              fs_lba <= fs_lba + l(5);
              state  <= S_FS_RD;
            end if;
          end if;

      end case;

      if reset = '1' then
        state     <= S_IDLE;
        busy_r    <= '0';
        sec_req_r <= '0';
        we        <= '0';
      end if;
    end if;
  end process;

end architecture;
