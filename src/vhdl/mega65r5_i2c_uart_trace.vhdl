library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity megar5_i2c_uart_trace is
  generic (
    CLK_HZ    : integer := 40_500_000;
    UART_BAUD : integer := 2_000_000
  );
  port (
    clk       : in  std_logic;
    reset_n   : in  std_logic := '1';

    -- I2C bus (forwarded into board block)
    sda       : inout std_logic;
    scl       : inout std_logic;

    -- UART TX
    uart_txd  : out std_logic
  );
end entity;

architecture rtl of megar5_i2c_uart_trace is
  -----------------------------------------------------------------------------
  -- UART
  -----------------------------------------------------------------------------
  constant UART_TICKS_PER_BIT : integer := (CLK_HZ + (UART_BAUD/2)) / UART_BAUD;
  constant UART_BIT_TMR_MAX   : unsigned(23 downto 0)
                             := to_unsigned(UART_TICKS_PER_BIT - 1, 24);

  component UART_TX_CTRL is
    port (
      SEND        : in  std_logic;
      BIT_TMR_MAX : in  unsigned(23 downto 0);
      DATA        : in  unsigned(7 downto 0);
      CLK         : in  std_logic;
      READY       : out std_logic;
      UART_TX     : out std_logic
    );
  end component;

  signal tx_send  : std_logic := '0';
  signal tx_ready : std_logic;
  signal tx_data  : unsigned(7 downto 0) := (others => '0');

  -----------------------------------------------------------------------------
  -- Board I2C with logger taps (your edited block)
  -----------------------------------------------------------------------------
  component mega65r5_board_i2c is
    generic ( clock_frequency : integer );
    port (
      clock             : in  std_logic;
      ear_watering_mode : in  std_logic := '0';
      sda               : inout std_logic;
      scl               : inout std_logic;

      -- logger taps
      scl_log           : out unsigned(7 downto 0);
      sda_log           : out unsigned(7 downto 0);
      log_strobe        : out std_logic;
      log_reset_strobe  : out std_logic;

      -- status bytes
      dipsw_read        : out std_logic_vector(7 downto 0);
      board_major       : out unsigned(3 downto 0);
      board_minor       : out unsigned(3 downto 0)
    );
  end component;

  signal dipsw_read          : std_logic_vector(7 downto 0);
  signal board_major         : unsigned(3 downto 0);
  signal board_minor         : unsigned(3 downto 0);

  signal scl_log_b           : unsigned(7 downto 0);
  signal sda_log_b           : unsigned(7 downto 0);
  signal log_strobe_b        : std_logic;
  signal log_reset_strobe_b  : std_logic;

  -----------------------------------------------------------------------------
  -- Capture buffer for BOTH lines (sole writer: CAPTURE_P)
  -----------------------------------------------------------------------------
  constant LOG_MAX : integer := 2048;  -- entries (each has SCL+SDA chars)
  type byte_arr_t is array (0 to LOG_MAX-1) of unsigned(7 downto 0);

  signal cap_scl : byte_arr_t;
  signal cap_sda : byte_arr_t;
  signal wr_idx  : integer range 0 to LOG_MAX := 0;

  signal capture_en      : std_logic := '1';  -- ONLY CAPTURE_P writes this
  signal armed_for_next  : std_logic := '0';  -- wait until next reset to re-enable

  -- CAPTURE_P -> TX_P
  signal new_log_toggle : std_logic := '0';
  signal new_log_prev   : std_logic := '0';

  -- TX_P -> CAPTURE_P
  signal tx_done_toggle : std_logic := '0';
  signal tx_done_prev   : std_logic := '0';

  signal send_len       : integer range 0 to LOG_MAX := 0;  -- number of entries
  signal snap0          : unsigned(7 downto 0) := (others => '0'); -- {minor,major}
  signal snap1          : unsigned(7 downto 0) := (others => '0'); -- dipsw

  -----------------------------------------------------------------------------
  -- TX FSM (sole writer of st/tx_idx/tx_char/tx_send/tx_data/tx_done_toggle)
  -----------------------------------------------------------------------------
  type tx_state_t is (TX_IDLE, TX_LOAD, TX_WAIT_RDY, TX_PULSE, TX_WAIT_BUSY, TX_WAIT_DONE);
  signal st       : tx_state_t := TX_IDLE;
  -- Total chars: 2(hex AA) + 1(space) + 2(hex BB) + 1(space) + 2*send_len + CR + LF
  signal tx_idx   : integer range 0 to (2*LOG_MAX + 8) := 0;
  signal tx_char  : unsigned(7 downto 0) := x"00";

  -- hex helper
  function hex_nib(n : unsigned(3 downto 0)) return unsigned is
  begin
    case to_integer(n) is
      when 0  => return x"30"; when 1  => return x"31"; when 2  => return x"32"; when 3  => return x"33";
      when 4  => return x"34"; when 5  => return x"35"; when 6  => return x"36"; when 7  => return x"37";
      when 8  => return x"38"; when 9  => return x"39"; when 10 => return x"41"; when 11 => return x"42";
      when 12 => return x"43"; when 13 => return x"44"; when 14 => return x"45"; when others => return x"46";
    end case;
  end;

begin
  -----------------------------------------------------------------------------
  -- Instances
  -----------------------------------------------------------------------------
  U_TX : UART_TX_CTRL
    port map (
      SEND        => tx_send,
      BIT_TMR_MAX => UART_BIT_TMR_MAX,
      DATA        => tx_data,
      CLK         => clk,
      READY       => tx_ready,
      UART_TX     => uart_txd
    );

  U_I2C : mega65r5_board_i2c
    generic map ( clock_frequency => CLK_HZ )
    port map (
      clock             => clk,
      ear_watering_mode => '0',
      sda               => sda,
      scl               => scl,

      scl_log           => scl_log_b,
      sda_log           => sda_log_b,
      log_strobe        => log_strobe_b,
      log_reset_strobe  => log_reset_strobe_b,

      dipsw_read        => dipsw_read,
      board_major       => board_major,
      board_minor       => board_minor
    );

  -----------------------------------------------------------------------------
  -- CAPTURE_P  (sole writer of capture_en / armed_for_next / buffers / toggle)
  -----------------------------------------------------------------------------
  CAPTURE_P : process(clk)
    variable reset_prev : std_logic := '0';
    variable reset_rise : boolean;
  begin
    if rising_edge(clk) then
      reset_rise := (reset_prev = '0' and log_reset_strobe_b = '1');
      reset_prev := log_reset_strobe_b;

      -- TX finished? do NOT immediately re-enable capture; just arm for next reset
      if tx_done_toggle /= tx_done_prev then
        tx_done_prev   <= tx_done_toggle;
        armed_for_next <= '1';
      end if;

      if reset_n = '0' then
        capture_en     <= '1';
        armed_for_next <= '0';
        wr_idx         <= 0;
        new_log_toggle <= '0';
        new_log_prev   <= '0';
        tx_done_prev   <= tx_done_toggle;

      else
        -- Re-enable capture ONLY at the next reset strobe after TX completion
        if (armed_for_next = '1') and reset_rise then
          capture_en     <= '1';
          armed_for_next <= '0';
          wr_idx         <= 0;
        end if;

        -- Store BOTH chars on each logger strobe, while enabled
        if (capture_en = '1') and (log_strobe_b = '1') then
          if wr_idx < LOG_MAX then
            cap_scl(wr_idx) <= scl_log_b;
            cap_sda(wr_idx) <= sda_log_b;
            wr_idx          <= wr_idx + 1;
          end if;
        end if;

        -- At the start of NEXT I2C cycle (reset_rise)…
        if reset_rise and (capture_en = '1') then
          if wr_idx > 0 then
            -- …freeze what we just captured and kick TX
            capture_en     <= '0';
            send_len       <= wr_idx;
            snap0          <= board_minor & board_major;
            snap1          <= unsigned(dipsw_read);
            new_log_toggle <= not new_log_toggle;  -- single writer
            -- DO NOT re-enable now; TX_P will toggle tx_done, and we
            -- will wait for *the following* reset_rise to re-enable.
          else
            -- empty capture (no logger events): just keep capture_on
            wr_idx <= 0;
          end if;
        end if;
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- TX_P  (sole writer of st/tx_idx/tx_char/tx_send/tx_data/tx_done_toggle)
  -----------------------------------------------------------------------------
-- TX_P  (sole writer of st/tx_idx/tx_char/tx_send/tx_data/tx_done_toggle)
TX_P : process(clk)
  variable have_work : boolean;
  variable log_chars : integer;  -- 2 * send_len
  variable nst       : tx_state_t;
  variable ch        : unsigned(7 downto 0);
begin
  if rising_edge(clk) then
    if reset_n = '0' then
      st             <= TX_IDLE;
      tx_send        <= '0';
      tx_data        <= (others => '0');
      tx_char        <= x"00";
      tx_idx         <= 0;
      new_log_prev   <= new_log_toggle;
      tx_done_toggle <= '0';
    else
      -- defaults
      tx_send   <= '0';
      have_work := (new_log_toggle /= new_log_prev);
      log_chars := 2 * send_len;
      nst       := st;
      ch        := tx_char;  -- keep previous char unless we load a new one

      case st is
        when TX_IDLE =>
          if have_work then
            new_log_prev <= new_log_toggle;  -- consume event
            tx_idx       <= 0;
            nst          := TX_LOAD;
          end if;

        when TX_LOAD =>
          -- choose next char, and (only if we really loaded) go to WAIT_RDY
          if      tx_idx = 0 then ch := hex_nib(snap0(7 downto 4));           nst := TX_WAIT_RDY;
          elsif   tx_idx = 1 then ch := hex_nib(snap0(3 downto 0));           nst := TX_WAIT_RDY;
          elsif   tx_idx = 2 then ch := x"20";                                 nst := TX_WAIT_RDY;
          elsif   tx_idx = 3 then ch := hex_nib(snap1(7 downto 4));            nst := TX_WAIT_RDY;
          elsif   tx_idx = 4 then ch := hex_nib(snap1(3 downto 0));            nst := TX_WAIT_RDY;
          elsif   tx_idx = 5 then ch := x"20";                                 nst := TX_WAIT_RDY;
          elsif  (tx_idx >= 6) and (tx_idx < 6 + log_chars) then
            if ((tx_idx - 6) mod 2) = 0 then ch := cap_scl( (tx_idx - 6)/2 );
            else                              ch := cap_sda( (tx_idx - 6)/2 );
            end if;
            nst := TX_WAIT_RDY;
          elsif   tx_idx = 6 + log_chars then ch := x"0D";                     nst := TX_WAIT_RDY; -- CR
          elsif   tx_idx = 7 + log_chars then ch := x"0A";                     nst := TX_WAIT_RDY; -- LF
          else
            -- finished: tell capture block and truly go idle (no fallthrough)
            tx_done_toggle <= not tx_done_toggle;
            tx_char        <= x"00";   -- clear last char so nothing stale can be re-sent
            nst            := TX_IDLE;
          end if;

        when TX_WAIT_RDY =>
          if tx_ready = '1' then
            tx_data <= ch;
            tx_send <= '1';              -- 1-cycle pulse
            nst     := TX_WAIT_BUSY;
          end if;

        when TX_WAIT_BUSY =>
          if tx_ready = '0' then
            nst := TX_WAIT_DONE;
          end if;

        when TX_WAIT_DONE =>
          if tx_ready = '1' then
            tx_idx <= tx_idx + 1;
            nst    := TX_LOAD;
          end if;

        when others =>
          nst := TX_IDLE;
      end case;

      -- commit updates
      tx_char <= ch;
      st      <= nst;
    end if;
  end if;
end process;






end architecture;
