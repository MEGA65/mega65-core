--------------------------------------------------------------------------------
-- sdcard_native_model: behavioural SD card for simulating sdcard_native.
-- (Simulation only.)
--
-- Native mode (1-bit CMD, 4-bit data) and SPI mode.  Commands: CMD0, 2, 3, 6
-- (switch), 7, 8, 12, 16, 17, 18, 24, 25, 55, ACMD6, ACMD41, and in SPI mode
-- also CMD58, CMD59.  Outputs change G_TODLY after the falling edge (default
-- speed, SPI) or the rising edge (high speed), and are 'X' from G_TOH to
-- G_TODLY after it, so a host that samples at the wrong time sees X.
--
-- Data: block b, byte i reads as pattern(b, i) unless written; writes are
-- kept for up to 64 blocks.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdcard_native_model is
  generic (
    G_START_SPI   : boolean := false;   -- the card is already in SPI mode
    G_HS_OK       : boolean := true;    -- supports high speed
    G_SDHC        : boolean := true;
    G_TOH         : time    := 2 ns;
    G_TODLY       : time    := 6 ns;
    G_NAC         : natural := 6;       -- clocks from the read command to the data
    G_NAC_MULTI   : natural := 2;       -- clocks between blocks of CMD18
    G_WBUSY       : natural := 40;      -- programming busy, clocks
    G_CRC_ERR_BLK : integer := -1;      -- first read of this block has a bad CRC
    G_STOP_FAILS : natural := 0;       -- first CMD12s have no response/effect
    G_STOP_ACK_FAILS : natural := 0    -- first CMD12s reply but keep streaming
    );
  port (
    clk : in    std_logic;
    cmd : inout std_logic;
    dat : inout std_logic_vector(3 downto 0)
    );
end entity;

architecture sim of sdcard_native_model is

  function pattern(b : natural; i : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned((b * 37 + i * 7 + (i / 256) * 101 + 13) mod 256, 8));
  end function;

  function crc7_bit(c : std_logic_vector(6 downto 0); b : std_logic) return std_logic_vector is
    variable r : std_logic_vector(6 downto 0);
  begin
    r := c(5 downto 0) & '0';
    if (b xor c(6)) = '1' then r := r xor "0001001"; end if;
    return r;
  end function;

  function crc16_bit(c : std_logic_vector(15 downto 0); b : std_logic) return std_logic_vector is
    variable r : std_logic_vector(15 downto 0);
  begin
    r := c(14 downto 0) & '0';
    if (b xor c(15)) = '1' then r := r xor x"1021"; end if;
    return r;
  end function;

  function crc16_byte(c : std_logic_vector(15 downto 0); b : std_logic_vector(7 downto 0)) return std_logic_vector is
    variable r : std_logic_vector(15 downto 0) := c;
  begin
    for i in 7 downto 0 loop r := crc16_bit(r, b(i)); end loop;
    return r;
  end function;

  function frame48(idx : natural; arg : std_logic_vector(31 downto 0); crc_on : boolean) return std_logic_vector is
    variable f : std_logic_vector(47 downto 0);
    variable c : std_logic_vector(6 downto 0) := (others => '0');
  begin
    f(47 downto 46) := "00";
    f(45 downto 40) := std_logic_vector(to_unsigned(idx, 6));
    f(39 downto 8)  := arg;
    for i in 47 downto 8 loop c := crc7_bit(c, f(i)); end loop;
    if crc_on then f(7 downto 1) := c; else f(7 downto 1) := "1111111"; end if;
    f(0) := '1';
    return f;
  end function;

  -- card state shared between the processes (signals: one writer each)
  signal spi_mode  : boolean := G_START_SPI;
  signal hs_mode   : boolean := false;

  -- requests cmd process -> data process (toggles)
  signal rd_go     : boolean := false;
  signal rd_blk    : natural := 0;
  signal rd_multi  : boolean := false;
  signal rd_small  : boolean := false;   -- CMD6 status
  signal sw_hs     : boolean := false;   -- the CMD6 asked for high speed
  signal stop_go   : boolean := false;
  signal wr_go     : boolean := false;
  signal wr_blk    : natural := 0;
  signal wr_multi  : boolean := false;
  signal busy_go   : boolean := false;
  signal busy_n    : natural := 0;
  signal spi_enter : boolean := false;   -- native CMD0 with CS low
  signal reset_go  : boolean := false;   -- native CMD0: back to default speed

  signal cmd_drv   : std_logic := 'Z';
  signal dat_drv   : std_logic_vector(3 downto 0) := "ZZZZ";
  signal spi_drv   : std_logic := 'Z';

  -- write memory (data process + SPI process each own one: only one mode
  -- is ever used per simulation run after the first write)
  type t_blk is array (0 to 511) of std_logic_vector(7 downto 0);
  type t_mem is array (0 to 63) of t_blk;
  type t_tags is array (0 to 63) of integer;

begin

  cmd    <= cmd_drv;
  dat    <= dat_drv;
  dat(0) <= spi_drv;

  ------------------------------------------------------------------------------
  -- native: command line
  ------------------------------------------------------------------------------
  cmd_proc : process
    variable f      : std_logic_vector(47 downto 0);
    variable c      : std_logic_vector(6 downto 0);
    variable idx    : natural;
    variable arg    : std_logic_vector(31 downto 0);
    variable app    : boolean := false;
    variable rca    : std_logic_vector(15 downto 0) := x"0000";
    variable acmd41 : natural := 0;
    variable sel    : boolean := false;
    variable cs_low : boolean;
    variable resp   : std_logic_vector(135 downto 0);
    variable rlen   : natural;
    variable rbusy  : natural;
    variable status : std_logic_vector(31 downto 0);
    variable multi_active : boolean := false;
    variable stop_attempts : natural := 0;

    procedure out_edge is
    begin
      if hs_mode then
        wait until rising_edge(clk);
      else
        wait until falling_edge(clk);
      end if;
    end procedure;

    procedure drive(v : std_logic) is
    begin
      cmd_drv <= transport 'X' after G_TOH;
      cmd_drv <= transport v after G_TODLY;
    end procedure;

  begin
    cmd_drv <= 'Z';
    loop
      wait until rising_edge(clk);
      if not spi_mode and to_X01(cmd) = '0' then
        f(47) := '0';
        for i in 46 downto 0 loop
          wait until rising_edge(clk);
          f(i) := to_X01(cmd);
        end loop;
        cs_low := to_X01(dat(3)) = '0';
        c := (others => '0');
        for i in 47 downto 8 loop c := crc7_bit(c, f(i)); end loop;
        if f(46) = '1' and f(0) = '1' and c = f(7 downto 1) then
          idx := to_integer(unsigned(f(45 downto 40)));
          arg := f(39 downto 8);
          rlen := 0; rbusy := 0;
          status := x"00000900";        -- READY_FOR_DATA, state tran
          if app then status(5) := '1'; end if;
          if app and idx = 41 then
            acmd41 := acmd41 + 1;
            resp(47 downto 0) := "00111111" & x"00FF8000" & "11111111";
            if acmd41 >= 2 then resp(39) := '1'; end if;
            if G_SDHC and arg(30) = '1' then resp(38) := '1'; end if;
            rlen := 48;
          elsif app and idx = 6 then
            resp(47 downto 0) := frame48(6, status, true); rlen := 48;
          else
            case idx is
              when 0 =>
                if cs_low then
                  spi_enter <= not spi_enter;
                end if;
                reset_go <= not reset_go;
                multi_active := false;
                sel := false; rca := x"0000"; acmd41 := 0;
              when 8 =>
                resp(47 downto 0) := frame48(8, x"000001" & arg(7 downto 0), true); rlen := 48;
              when 55 =>
                status(5) := '1';
                resp(47 downto 0) := frame48(55, status, true); rlen := 48;
              when 2 =>
                resp := (others => '1');
                resp(135 downto 128) := "00111111";
                resp(127 downto 0) := x"0353445345313630_8012345678017A01";
                rlen := 136;
              when 3 =>
                rca := x"1234";
                resp(47 downto 0) := frame48(3, rca & x"0500", true); rlen := 48;
              when 7 =>
                sel := arg(31 downto 16) = rca;
                resp(47 downto 0) := frame48(7, status, true); rlen := 48; rbusy := 6;
              when 13 =>
                if multi_active then status := x"00000A00"; end if;
                resp(47 downto 0) := frame48(idx, status, true); rlen := 48;
              when 16 =>
                resp(47 downto 0) := frame48(idx, status, true); rlen := 48;
              when 6 =>
                resp(47 downto 0) := frame48(6, status, true); rlen := 48;
                rd_small <= true;
                rd_multi <= false;
                sw_hs    <= arg(31) = '1' and arg(3 downto 0) = x"1";
                rd_go    <= not rd_go;
              when 17 | 18 =>
                multi_active := idx = 18;
                resp(47 downto 0) := frame48(idx, status, true); rlen := 48;
                if G_SDHC then
                  rd_blk <= to_integer(unsigned(arg));
                else
                  rd_blk <= to_integer(unsigned(arg(31 downto 9)));
                end if;
                rd_small <= false;
                rd_multi <= idx = 18;
                rd_go    <= not rd_go;
              when 24 | 25 =>
                resp(47 downto 0) := frame48(idx, status, true); rlen := 48;
                if G_SDHC then
                  wr_blk <= to_integer(unsigned(arg));
                else
                  wr_blk <= to_integer(unsigned(arg(31 downto 9)));
                end if;
                wr_multi <= idx = 25;
                wr_go    <= not wr_go;
              when 12 =>
                stop_attempts := stop_attempts + 1;
                if stop_attempts > G_STOP_FAILS then
                  if stop_attempts > G_STOP_ACK_FAILS then
                    stop_go <= not stop_go;
                    multi_active := false;
                  end if;
                  resp(47 downto 0) := frame48(12, status, true); rlen := 48; rbusy := 8;
                end if;
              when others =>
                null;
            end case;
          end if;
          app := (idx = 55);
          if rlen /= 0 then
            -- Ncr = 2
            out_edge; out_edge;
            for i in rlen - 1 downto 0 loop
              out_edge;
              drive(resp(i));
            end loop;
            out_edge;
            cmd_drv <= transport 'Z' after G_TOH;
            if rbusy /= 0 then
              busy_n  <= rbusy;
              busy_go <= not busy_go;
            end if;
          end if;
        else
          report "MODEL: bad command frame" severity warning;
        end if;
      end if;
    end loop;
  end process;

  ------------------------------------------------------------------------------
  -- native: data lines
  ------------------------------------------------------------------------------
  data_proc : process
    variable mem      : t_mem;
    variable tags     : t_tags := (others => -1);
    variable crc      : std_logic_vector(63 downto 0);
    variable crcrx    : std_logic_vector(63 downto 0);
    variable nib      : std_logic_vector(3 downto 0);
    variable byte     : std_logic_vector(7 downto 0);
    variable blk      : natural;
    variable nbytes   : natural;
    variable stop_ref : boolean;
    variable stopped  : boolean;
    variable err_done : boolean := false;
    variable buf      : t_blk;
    variable ok       : boolean;

    procedure out_edge is
    begin
      if hs_mode then
        wait until rising_edge(clk);
      else
        wait until falling_edge(clk);
      end if;
    end procedure;

    procedure drive(v : std_logic_vector(3 downto 0)) is
    begin
      dat_drv <= transport "XXXX" after G_TOH;
      dat_drv <= transport v after G_TODLY;
    end procedure;

    impure function read_byte(b : natural; i : natural) return std_logic_vector is
    begin
      if tags(b mod 64) = b then
        return mem(b mod 64)(i);
      else
        return pattern(b, i);
      end if;
    end function;

  begin
    dat_drv <= "ZZZZ";
    loop
      wait on rd_go, wr_go, busy_go, reset_go;

      if reset_go'event then
        hs_mode <= false;
      elsif rd_go'event then
        stop_ref := stop_go;
        stopped  := false;
        blk      := rd_blk;
        if rd_small then nbytes := 64; else nbytes := 512; end if;
        for i in 1 to G_NAC loop out_edge; end loop;
        loop
          -- one block
          out_edge; drive("0000");
          crc := (others => '0');
          for i in 0 to nbytes - 1 loop
            if rd_small then
              byte := x"00";
              if i = 16 then
                if G_HS_OK and sw_hs then byte := x"01"; else byte := x"0F"; end if;
              end if;
            else
              byte := read_byte(blk, i);
            end if;
            for h in 1 downto 0 loop
              nib := byte(4*h+3 downto 4*h);
              for l in 0 to 3 loop
                crc(16*l+15 downto 16*l) := crc16_bit(crc(16*l+15 downto 16*l), nib(l));
              end loop;
              out_edge;
              if stop_go /= stop_ref then stopped := true; exit; end if;
              drive(nib);
            end loop;
            exit when stopped;
          end loop;
          exit when stopped;
          if blk = G_CRC_ERR_BLK and not err_done and not rd_small then
            crc(0) := not crc(0);
            err_done := true;
          end if;
          for k in 15 downto 0 loop
            out_edge;
            if stop_go /= stop_ref then stopped := true; exit; end if;
            drive(crc(48+k) & crc(32+k) & crc(16+k) & crc(k));
          end loop;
          exit when stopped;
          out_edge; drive("1111");
          if not rd_multi or G_NAC_MULTI /= 0 then
            out_edge; dat_drv <= transport "ZZZZ" after G_TOH;
          end if;
          if rd_small then
            -- the switch takes effect after the status
            hs_mode <= G_HS_OK and sw_hs;
          end if;
          exit when not rd_multi;
          blk := blk + 1;
          for i in 2 to G_NAC_MULTI loop
            out_edge;
            if stop_go /= stop_ref then stopped := true; exit; end if;
          end loop;
          exit when stopped;
        end loop;
        dat_drv <= transport "ZZZZ" after G_TOH;

      elsif wr_go'event then
        stop_ref := stop_go;
        blk      := wr_blk;
        loop
          -- wait for the start bit (or CMD12)
          stopped := false;
          loop
            wait until rising_edge(clk);
            if stop_go /= stop_ref then stopped := true; exit; end if;
            exit when to_X01(dat(0)) = '0';
          end loop;
          exit when stopped;
          crc := (others => '0');
          for i in 0 to 511 loop
            for h in 1 downto 0 loop
              wait until rising_edge(clk);
              nib := to_X01(dat);
              byte(4*h+3 downto 4*h) := nib;
              for l in 0 to 3 loop
                crc(16*l+15 downto 16*l) := crc16_bit(crc(16*l+15 downto 16*l), nib(l));
              end loop;
            end loop;
            buf(i) := byte;
          end loop;
          crcrx := (others => '0');
          for k in 15 downto 0 loop
            wait until rising_edge(clk);
            for l in 0 to 3 loop
              crcrx(16*l+k) := to_X01(dat(l));
            end loop;
          end loop;
          wait until rising_edge(clk);    -- end bit
          ok := crcrx = crc and to_X01(dat) = "1111";
          if ok then
            mem(blk mod 64) := buf;
            tags(blk mod 64) := blk;
          else
            report "MODEL: write block " & integer'image(blk) & " CRC error" severity note;
          end if;
          -- CRC status two clocks after the end bit, then busy
          out_edge; out_edge;
          out_edge; drive("ZZZ0");
          if ok then
            out_edge; drive("ZZZ0");
            out_edge; drive("ZZZ1");
            out_edge; drive("ZZZ0");
          else
            out_edge; drive("ZZZ1");
            out_edge; drive("ZZZ0");
            out_edge; drive("ZZZ1");
          end if;
          out_edge; drive("ZZZ1");
          if ok then
            for i in 1 to G_WBUSY loop
              out_edge; drive("ZZZ0");
            end loop;
            out_edge; drive("ZZZ1");
          end if;
          out_edge; dat_drv <= transport "ZZZZ" after G_TOH;
          exit when not wr_multi;
          blk := blk + 1;
        end loop;
        dat_drv <= transport "ZZZZ" after G_TOH;

      else
        -- busy after an R1b
        for i in 1 to busy_n loop
          out_edge; drive("ZZZ0");
        end loop;
        out_edge; drive("ZZZ1");
        out_edge; dat_drv <= transport "ZZZZ" after G_TOH;
      end if;
    end loop;
  end process;

  ------------------------------------------------------------------------------
  -- SPI mode (MOSI = CMD, MISO = DAT0, CS = DAT3)
  ------------------------------------------------------------------------------
  spi_proc : process
    type t_q is array (0 to 4095) of std_logic_vector(7 downto 0);
    variable q        : t_q;
    variable qh, qt   : natural := 0;
    variable mem      : t_mem;
    variable tags     : t_tags := (others => -1);
    variable txb      : std_logic_vector(7 downto 0) := x"FF";
    variable rxb      : std_logic_vector(7 downto 0) := x"FF";
    variable bitn     : natural := 0;
    variable cmdb     : std_logic_vector(47 downto 0);
    variable cmdn     : natural := 0;
    variable app      : boolean := false;
    variable acmd41   : natural := 0;
    variable crc_on   : boolean := false;
    variable idx      : natural;
    variable arg      : std_logic_vector(31 downto 0);
    variable c        : std_logic_vector(6 downto 0);
    variable rd_on    : boolean := false;   -- CMD18 streaming
    variable rblk     : natural;
    variable wr_on    : boolean := false;   -- CMD24/25: waiting for a token
    variable wmulti   : boolean := false;
    variable wblk     : natural;
    variable wn       : integer := -1;      -- bytes of the data block so far
    variable wbuf     : t_blk;
    variable wcrc     : std_logic_vector(15 downto 0);
    variable wcrcrx   : std_logic_vector(15 downto 0);
    variable err_done : boolean := false;
    variable cs_on    : boolean := false;

    procedure push(v : std_logic_vector(7 downto 0)) is
    begin
      q(qt) := v;
      qt := (qt + 1) mod 4096;
    end procedure;

    procedure push_block(b : natural) is
      variable cr : std_logic_vector(15 downto 0) := (others => '0');
      variable v  : std_logic_vector(7 downto 0);
    begin
      push(x"FF"); push(x"FF"); push(x"FE");
      for i in 0 to 511 loop
        if tags(b mod 64) = b then v := mem(b mod 64)(i); else v := pattern(b, i); end if;
        push(v);
        cr := crc16_byte(cr, v);
      end loop;
      if b = G_CRC_ERR_BLK and not err_done then
        cr(0) := not cr(0);
        err_done := true;
      end if;
      push(cr(15 downto 8)); push(cr(7 downto 0));
    end procedure;

    procedure r1(v : std_logic_vector(7 downto 0)) is
    begin
      push(x"FF");
      push(v);
    end procedure;

  begin
    spi_drv <= 'Z';
    loop
      wait on clk, spi_enter, dat(3);
      if spi_enter'event then
        -- the native CMD0 that just ended had CS low: SPI mode from now on,
        -- in step with the bytes (the command ended on a byte boundary)
        spi_mode <= true;
        cs_on := true;
        bitn := 0;
        qh := 0; qt := 0;
        r1(x"01");
      elsif to_X01(dat(3)) = '1' or not spi_mode then
        spi_drv <= 'Z';
        bitn  := 0;
        cs_on := false;
      elsif not cs_on or (falling_edge(clk) and bitn < 8) then
        -- CS just went low, or a new bit
        if not cs_on then
          cs_on := true;
          bitn  := 0;
        end if;
        if bitn = 0 then
          if qh /= qt then
            txb := q(qh);
            qh := (qh + 1) mod 4096;
          else
            txb := x"FF";
          end if;
        end if;
        spi_drv <= transport 'X' after G_TOH;
        spi_drv <= transport txb(7 - bitn) after G_TODLY;
        bitn := bitn + 8;               -- marks "driven, not yet sampled"
      elsif rising_edge(clk) and bitn >= 8 then
        rxb := rxb(6 downto 0) & to_X01(cmd);
        bitn := bitn - 8 + 1;
        if bitn = 8 then
          bitn := 0;
          -- a byte arrived
          if wn >= 0 then
            -- inside a write data block
            if wn < 512 then
              wbuf(wn) := rxb;
              wcrc := crc16_byte(wcrc, rxb);
            else
              wcrcrx := wcrcrx(7 downto 0) & rxb;
            end if;
            wn := wn + 1;
            if wn = 514 then
              wn := -1;
              if wcrcrx = wcrc or not crc_on then
                mem(wblk mod 64) := wbuf;
                tags(wblk mod 64) := wblk;
                push(x"E5");               -- accepted
                for i in 1 to 4 loop push(x"00"); end loop;
                wblk := wblk + 1;
                wr_on := wmulti;
              else
                push(x"EB");               -- CRC error
                wr_on := wmulti;
              end if;
            end if;
          elsif wr_on and cmdn = 0 and (rxb = x"FE" or rxb = x"FC") then
            wn := 0;
            wcrc := (others => '0');
          elsif wr_on and cmdn = 0 and rxb = x"FD" then
            wr_on := false;
            push(x"FF");
            for i in 1 to 4 loop push(x"00"); end loop;
          elsif cmdn > 0 or rxb(7 downto 6) = "01" then
            cmdb := cmdb(39 downto 0) & rxb;
            cmdn := cmdn + 1;
            if cmdn = 6 then
              cmdn := 0;
              idx := to_integer(unsigned(cmdb(45 downto 40)));
              arg := cmdb(39 downto 8);
              c := (others => '0');
              for i in 47 downto 8 loop c := crc7_bit(c, cmdb(i)); end loop;
              if (crc_on or idx = 0 or idx = 8) and c /= cmdb(7 downto 1) then
                r1(x"09");                 -- CRC error
              elsif app and idx = 41 then
                acmd41 := acmd41 + 1;
                if acmd41 >= 2 then r1(x"00"); else r1(x"01"); end if;
              else
                case idx is
                  when 0 =>
                    rd_on := false; wr_on := false;
                    -- Reset aborts a partly sent read too. Its remaining
                    -- queued data must not precede CMD0's response during
                    -- reinitialisation after an interrupted cache fill.
                    qh := qt;
                    acmd41 := 0;
                    crc_on := false;
                    r1(x"01");
                  when 8 =>
                    r1(x"01"); push(x"00"); push(x"00"); push(x"01"); push(arg(7 downto 0));
                  when 55 =>
                    if acmd41 >= 2 then r1(x"00"); else r1(x"01"); end if;
                  when 58 =>
                    r1(x"00");
                    if G_SDHC then push(x"C0"); else push(x"80"); end if;
                    push(x"FF"); push(x"80"); push(x"00");
                  when 59 =>
                    crc_on := arg(0) = '1';
                    r1(x"00");
                  when 16 =>
                    r1(x"00");
                  when 17 | 18 =>
                    if G_SDHC then rblk := to_integer(unsigned(arg));
                    else rblk := to_integer(unsigned(arg(31 downto 9))); end if;
                    r1(x"00");
                    push_block(rblk);
                    rd_on := idx = 18;
                  when 12 =>
                    rd_on := false;
                    qh := qt;                -- drop the data
                    push(x"FF");             -- stuff byte
                    push(x"00");             -- R1
                    push(x"00"); push(x"00");  -- busy
                  when 24 | 25 =>
                    if G_SDHC then wblk := to_integer(unsigned(arg));
                    else wblk := to_integer(unsigned(arg(31 downto 9))); end if;
                    wmulti := idx = 25;
                    wr_on := true;
                    r1(x"00");
                  when others =>
                    r1(x"04");               -- illegal command
                end case;
              end if;
              app := idx = 55;
            end if;
          end if;
          -- keep a multi-block read going
          if rd_on and (qt - qh + 4096) mod 4096 < 8 then
            rblk := rblk + 1;
            push_block(rblk);
          end if;
        end if;
      end if;
    end loop;
  end process;

end architecture;
