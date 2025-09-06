library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity megar5_i2c_uart_trace is
  generic (
    CLK_HZ    : integer := 40_500_000;   -- cpuclock
    UART_BAUD : integer := 2_000_000     -- ~2.025 Mbps @ 40.5 MHz
  );
  port (
    clk       : in  std_logic;
    reset_n   : in  std_logic := '1';

    -- I2C bus (board nets)
    sda       : inout std_logic;
    scl       : inout std_logic;

    -- UART out
    uart_txd  : out std_logic
  );
end entity;

architecture rtl of megar5_i2c_uart_trace is
  ---------------------------------------------------------------------------
  -- UART
  ---------------------------------------------------------------------------
  constant UART_TICKS_PER_BIT : integer := (CLK_HZ + (UART_BAUD/2)) / UART_BAUD;
  constant UART_BIT_TMR_MAX   : unsigned(23 downto 0) := to_unsigned(UART_TICKS_PER_BIT - 1, 24);

  component UART_TX_CTRL
    port (
      SEND        : in  std_logic;
      BIT_TMR_MAX : in  unsigned(23 downto 0);
      DATA        : in  unsigned(7 downto 0);
      CLK         : in  std_logic;
      READY       : out std_logic;
      UART_TX     : out std_logic
    );
  end component;

  signal tx_send   : std_logic := '0';
  signal tx_ready  : std_logic;
  signal tx_data   : unsigned(7 downto 0) := (others => '0');

  ---------------------------------------------------------------------------
  -- Your board I²C block
  ---------------------------------------------------------------------------
  component mega65r5_board_i2c
    generic ( clock_frequency : integer );
    port (
      clock        : in  std_logic;
      ear_watering_mode : in std_logic := '0';
      sda          : inout std_logic;
      scl          : inout std_logic;
      dipsw_read   : out std_logic_vector(7 downto 0);
      board_major  : out unsigned(3 downto 0);
      board_minor  : out unsigned(3 downto 0)
    );
  end component;

  signal dipsw_read   : std_logic_vector(7 downto 0);
  signal board_major  : unsigned(3 downto 0);
  signal board_minor  : unsigned(3 downto 0);

  -- snapshots to print alongside trace captured at STOP
  signal snap0        : unsigned(7 downto 0) := (others => '0');  -- {minor,major}
  signal snap1        : unsigned(7 downto 0) := (others => '0');  -- dipsw_read

  ---------------------------------------------------------------------------
  -- I²C line sampler (START/STOP + SDA-at-each-SCL↑)
  ---------------------------------------------------------------------------
  constant MAX_BITS : integer := 256;  -- per transaction; adjust if needed

  signal sda_sync, scl_sync   : std_logic := '1';
  signal sda_d,   scl_d       : std_logic := '1';   -- 1-cycle delayed
  signal sda_dd,  scl_dd      : std_logic := '1';   -- 2-cycle for edge clean

  signal in_xact    : std_logic := '0';
  signal cur_bits   : std_logic_vector(MAX_BITS-1 downto 0) := (others => '0');
  signal cur_len    : integer range 0 to MAX_BITS := 0;

  signal last_bits  : std_logic_vector(MAX_BITS-1 downto 0) := (others => '0');
  signal last_len   : integer range 0 to MAX_BITS := 0;
  signal trace_ready: std_logic := '0';

  -- helpers
  function hex_nib(n : unsigned(3 downto 0)) return unsigned is
  begin
    case to_integer(n) is
      when 0  => return x"30"; when 1  => return x"31"; when 2  => return x"32"; when 3  => return x"33";
      when 4  => return x"34"; when 5  => return x"35"; when 6  => return x"36"; when 7  => return x"37";
      when 8  => return x"38"; when 9  => return x"39"; when 10 => return x"41"; when 11 => return x"42";
      when 12 => return x"43"; when 13 => return x"44"; when 14 => return x"45"; when others => return x"46";
    end case;
  end;

  ---------------------------------------------------------------------------
  -- TX FSM (prints: "AA BB <bits>\r\n")
  ---------------------------------------------------------------------------
  type state_t is (ST_IDLE, ST_TX_GET, ST_TX_WAIT_RDY, ST_TX_PULSE, ST_TX_WAIT_BUSY, ST_TX_WAIT_DONE);
  signal st       : state_t := ST_IDLE;
  signal tx_idx   : integer range 0 to MAX_BITS+5 := 0;  -- 2 bytes + space + bits + CR + LF
  signal tx_phase : integer range 0 to 1 := 0;           -- 0=hi nib, 1=lo nib
  signal tx_char  : unsigned(7 downto 0) := x"00";

begin
  ---------------------------------------------------------------------------
  -- Instances
  ---------------------------------------------------------------------------
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
      dipsw_read        => dipsw_read,
      board_major       => board_major,
      board_minor       => board_minor
    );

  -- Synchronize lines to clk and deburr 1 cycle
  process(clk)
  begin
    if rising_edge(clk) then
      sda_d  <= sda;
      scl_d  <= scl;
      sda_dd <= sda_d;
      scl_dd <= scl_d;
      sda_sync <= sda_dd;
      scl_sync <= scl_dd;
    end if;
  end process;

  -- START/STOP detect + capture SDA on SCL rising edges
  process(clk)
    variable start_cond : boolean;
    variable stop_cond  : boolean;
    variable scl_rise   : boolean;
  begin
    if rising_edge(clk) then
      start_cond := (sda_sync = '0' and sda_d = '1' and scl_sync = '1'); -- SDA 1->0 while SCL high
      stop_cond  := (sda_sync = '1' and sda_d = '0' and scl_sync = '1'); -- SDA 0->1 while SCL high
      scl_rise   := (scl_sync = '1' and scl_d = '0');

      if reset_n = '0' then
        in_xact     <= '0';
        cur_len     <= 0;
        last_len    <= 0;
        trace_ready <= '0';
      else
        -- START -> begin new capture
        if start_cond then
          in_xact <= '1';
          cur_len <= 0;
        end if;

        -- sample SDA on SCL rising edges during transaction
        if (in_xact = '1') and scl_rise then
          if cur_len < MAX_BITS then
            cur_bits(cur_len) <= sda_sync;
            cur_len <= cur_len + 1;
          end if;
        end if;

        -- STOP -> finalize capture and snapshot bytes to print
        if stop_cond and (in_xact = '1') then
          in_xact <= '0';
          last_bits  <= cur_bits;
          last_len   <= cur_len;
          -- snapshot current “board” bytes right at STOP
          snap0 <= board_minor & board_major;
          snap1 <= unsigned(dipsw_read);
          trace_ready <= '1';
        end if;

        -- tx fsm will consume this
        if st /= ST_IDLE then
          trace_ready <= trace_ready; -- hold until FSM grabs it
        end if;
      end if;
    end if;
  end process;

  -- TX FSM: prints "AA BB " + last_bits as '1'/'0' + CRLF when trace_ready=1
  process(clk)
    -- helper for bit-to-ASCII
    function bit_ascii(b : std_logic) return unsigned is
    begin
      if b = '1' then return x"31"; else return x"30"; end if; -- '1'/'0'
    end;
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        st <= ST_IDLE;
        tx_send <= '0'; tx_data <= (others => '0'); tx_char <= x"00";
        tx_idx <= 0; tx_phase <= 0;
      else
        tx_send <= '0'; -- default

        case st is
          when ST_IDLE =>
            if trace_ready = '1' then
              -- start a new line
              tx_idx   <= 0;
              tx_phase <= 0;
              st       <= ST_TX_GET;
              -- consume the flag
              trace_ready <= '0';
            end if;

          -- choose next character
          when ST_TX_GET =>
            -- 0,1 -> snap0 hex; 2 -> space; 3,4 -> snap1 hex; 5..(5+last_len-1) -> bits; then CR, LF
            if tx_idx = 0 then
              if tx_phase = 0 then tx_char <= hex_nib(snap0(7 downto 4)); else tx_char <= hex_nib(snap0(3 downto 0)); end if;
            elsif tx_idx = 1 then
              if tx_phase = 0 then tx_char <= x"20";            -- space between bytes
              else                   tx_char <= hex_nib(snap1(7 downto 4));
              end if;
            elsif tx_idx = 2 then
              if tx_phase = 0 then tx_char <= hex_nib(snap1(3 downto 0));
              else                   tx_char <= x"20";          -- space before bit string
              end if;
            elsif (tx_idx >= 3) and (tx_idx < 3 + last_len) then
              -- map into last_bits index
              tx_char <= bit_ascii(last_bits(tx_idx - 3));
            elsif tx_idx = 3 + last_len then
              tx_char <= x"0D";                                  -- CR
            elsif tx_idx = 4 + last_len then
              tx_char <= x"0A";                                  -- LF
            else
              -- done with line
              st <= ST_IDLE;
            end if;

            if st = ST_TX_GET then
              st <= ST_TX_WAIT_RDY;
            end if;

          -- strict handshake with UART_TX_CTRL
          when ST_TX_WAIT_RDY =>
            if tx_ready = '1' then
              st <= ST_TX_PULSE;
            end if;

          when ST_TX_PULSE =>
            tx_data <= tx_char;
            tx_send <= '1';
            st <= ST_TX_WAIT_BUSY;

          when ST_TX_WAIT_BUSY =>
            if tx_ready = '0' then
              st <= ST_TX_WAIT_DONE;
            end if;

          when ST_TX_WAIT_DONE =>
            if tx_ready = '1' then
              -- advance indices
              if tx_idx = 0 then
                if tx_phase = 0 then tx_phase <= 1; else tx_phase <= 0; tx_idx <= 1; end if;
              elsif tx_idx = 1 then
                if tx_phase = 0 then tx_phase <= 1; else tx_phase <= 0; tx_idx <= 2; end if;
              elsif tx_idx = 2 then
                if tx_phase = 0 then tx_phase <= 1; else tx_phase <= 0; tx_idx <= 3; end if;
              else
                tx_idx <= tx_idx + 1;
              end if;
              st <= ST_TX_GET;
            end if;

          when others =>
            st <= ST_IDLE;
        end case;
      end if;
    end if;
  end process;

end architecture;
