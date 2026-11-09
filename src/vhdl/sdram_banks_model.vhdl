-- sdram_banks_model: a small behavioural SDRAM (IS42S16320-like, x16) with
-- four independent banks, for benches of the LUMP-branch sdram_controller,
-- which keeps a row open in every bank. (is42s16320f_model.vhdl tracks one
-- state and one row for the whole chip and indexes its memory without the
-- bank, so it cannot follow that controller.)
--
-- Commands are sampled on the rising clock edge. MODE REGISTER sets the CAS
-- latency (A6-4), the read burst length (A2-0) and single-location writes
-- (A9). READ drives word k of its burst during the cycle after edge
-- E + CL - 1 + k (E = the READ's edge), as is42s16320f_model does, so the
-- controller samples it at E + CL + k. WRITE stores DQ under DQM. Protocol
-- errors are assertions: ACTIVATE on an open bank, READ or WRITE on a closed
-- one, REFRESH with a bank open, a write burst longer than one word.
--
-- Memory: banks x 256 rows x 1024 columns of 16 bits (the first 2 MB of the
-- address space under the controller's map); rows beyond that alias.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdram_banks_model is
  port (
    clk   : in    std_logic;
    cke   : in    std_logic;
    cs_n  : in    std_logic;
    ras_n : in    std_logic;
    cas_n : in    std_logic;
    we_n  : in    std_logic;
    ba    : in    unsigned(1 downto 0);
    a     : in    unsigned(12 downto 0);
    dqml  : in    std_logic;
    dqmh  : in    std_logic;
    dq    : inout unsigned(15 downto 0);
    init_done : out std_logic := '0'
    );
end sdram_banks_model;

architecture behavioural of sdram_banks_model is
begin

  process (clk)
    type mem_t is array (0 to 2**20 - 1) of integer range 0 to 65535;   -- (integers: 4 MB)
    variable mem : mem_t := (others => 0);
    variable w : unsigned(15 downto 0);
    type int4 is array (0 to 3) of integer;
    variable open_row : int4 := (others => -1);
    variable cl : integer := 3;
    variable bl : integer := 1;
    variable wsingle : boolean := true;
    -- read data waiting to be driven: due edge, word
    type due_t is array (0 to 31) of integer;
    type word_t is array (0 to 31) of unsigned(15 downto 0);
    variable due : due_t := (others => -1);
    variable wq : word_t;
    variable edge : integer := 0;
    variable b, col, idx : integer;
    variable cmd : std_logic_vector(2 downto 0);
    variable drive : boolean;

    impure function index(bank, row, c : integer) return integer is
    begin
      return bank * 2**18 + (row mod 256) * 2**10 + c;
    end function;
  begin
    if rising_edge(clk) then
      edge := edge + 1;
      -- read data due now leaves on DQ for this cycle
      drive := false;
      for i in 0 to 31 loop
        if due(i) = edge then
          dq <= wq(i);
          due(i) := -1;
          drive := true;
        end if;
      end loop;
      if not drive then
        dq <= (others => 'Z');
      end if;

      if cke = '1' and cs_n = '0' then
        cmd := ras_n & cas_n & we_n;
        b := to_integer(ba);
        case cmd is
          when "000" =>                       -- MODE REGISTER
            cl := to_integer(a(6 downto 4));
            case to_integer(a(2 downto 0)) is
              when 0 => bl := 1;
              when 1 => bl := 2;
              when 2 => bl := 4;
              when 3 => bl := 8;
              when others => bl := 1024;
            end case;
            wsingle := a(9) = '1';
            assert cl = 2 or cl = 3 report "SDRAM model: CAS latency " & integer'image(cl) severity error;
            init_done <= '1';
          when "011" =>                       -- ACTIVATE
            assert open_row(b) = -1
              report "SDRAM model: ACTIVATE bank " & integer'image(b) & " row "
              & integer'image(to_integer(a)) & " with row " & integer'image(open_row(b)) & " open"
              severity error;
            open_row(b) := to_integer(a);
          when "010" =>                       -- PRECHARGE
            if a(10) = '1' then
              open_row := (others => -1);
            else
              open_row(b) := -1;
            end if;
          when "001" =>                       -- AUTO REFRESH
            assert open_row = (-1, -1, -1, -1)
              report "SDRAM model: REFRESH with a bank open" severity error;
          when "100" =>                       -- WRITE
            assert open_row(b) /= -1
              report "SDRAM model: WRITE to closed bank " & integer'image(b) severity error;
            assert wsingle report "SDRAM model: write bursts not modelled" severity error;
            col := to_integer(a(9 downto 0));
            if open_row(b) /= -1 then
              idx := index(b, open_row(b), col);
              w := to_unsigned(mem(idx), 16);
              if dqml = '0' then w(7 downto 0) := dq(7 downto 0); end if;
              if dqmh = '0' then w(15 downto 8) := dq(15 downto 8); end if;
              mem(idx) := to_integer(w);
            end if;
            if a(10) = '1' then open_row(b) := -1; end if;
          when "101" =>                       -- READ
            assert open_row(b) /= -1
              report "SDRAM model: READ from closed bank " & integer'image(b) severity error;
            col := to_integer(a(9 downto 0));
            -- a new READ cuts a burst short
            for i in 0 to 31 loop
              if due(i) > edge + cl - 1 then due(i) := -1; end if;
            end loop;
            for k in 0 to bl - 1 loop
              if k < 32 and open_row(b) /= -1 then
                for i in 0 to 31 loop
                  if due(i) = -1 then
                    due(i) := edge + cl - 1 + k;
                    wq(i) := to_unsigned(mem(index(b, open_row(b), (col + k) mod 1024)), 16);
                    exit;
                  end if;
                end loop;
              end if;
            end loop;
            if a(10) = '1' then open_row(b) := -1; end if;
          when "110" =>                       -- BURST STOP
            for i in 0 to 31 loop
              if due(i) > edge then due(i) := -1; end if;
            end loop;
          when others =>                      -- NOP
            null;
        end case;
      end if;
    end if;
  end process;

end behavioural;
