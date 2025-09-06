library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_dump16_uart is
  generic (
    CLK_HZ      : integer := 40_500_000;   -- cpuclock
    UART_BAUD   : integer := 2_000_000;    -- ~2.025 Mbps actual @ 40.5 MHz
    I2C_BUS_HZ  : integer := 400_000;      -- I2C bus speed
    SLAVE_ADDR7 : std_logic_vector(6 downto 0) := "0100000"  -- 0x20
  );
  port (
    clk       : in  std_logic;
    reset_n   : in  std_logic;
    sda       : inout std_logic;
    scl       : inout std_logic;
    uart_txd  : out std_logic
  );
end entity;

architecture rtl of i2c_dump16_uart is
  -- ===== UART =====
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

  -- ===== I2C master (Digi-Key) =====
  component i2c_master
    generic (
      input_clk : integer := 40_500_000;
      bus_clk   : integer := 400_000
    );
    port (
      clk       : in     std_logic;
      reset_n   : in     std_logic;
      ena       : in     std_logic;
      addr      : in     std_logic_vector(6 downto 0);
      rw        : in     std_logic;
      data_wr   : in     std_logic_vector(7 downto 0);
      busy      : out    std_logic;
      data_rd   : out    std_logic_vector(7 downto 0);
      ack_error : buffer std_logic;
      sda       : inout  std_logic;
      scl       : inout  std_logic;
      latch_toggle : out std_logic;
      swap      : in std_logic := '0';
      debug_scl : in std_logic := '0';
      debug_sda : in std_logic := '0'
    );
  end component;

  signal i2c_ena        : std_logic := '0';
  signal i2c_addr       : std_logic_vector(6 downto 0) := SLAVE_ADDR7;
  signal i2c_rw         : std_logic := '0';
  signal i2c_data_wr    : std_logic_vector(7 downto 0) := (others => '0');
  signal i2c_busy       : std_logic;
  signal i2c_data_rd    : std_logic_vector(7 downto 0);
  signal i2c_ack_error  : std_logic;
  signal i2c_latch_tog  : std_logic;

  -- ===== storage & FSM =====
  type byte_array_t is array (0 to 15) of std_logic_vector(7 downto 0);
  signal regs : byte_array_t := (others => (others => '0'));

  type txmode_t is (TXM_HEX, TXM_ERR);

  type state_t is (
    ST_BANNER,
    -- repeated-START sequence:
    ST_PTR_START_HOLD, ST_PTR_WAIT_BUSY_HI, ST_PTR_SWITCH_TO_READ,
    ST_RD_WAIT_BYTE, ST_RD_LAST_WAIT,
    -- UART sequencer (strict handshake):
    ST_TX_GET, ST_TX_WAIT_RDY, ST_TX_PULSE, ST_TX_WAIT_BUSY, ST_TX_WAIT_DONE,
    ST_IDLE_GAP
  );
  signal st : state_t := ST_BANNER;

  signal rd_index     : integer range 0 to 16 := 0;
  signal tx_index     : integer range 0 to 17 := 0;    -- 0..15 (+done)
  signal tx_phase     : integer range 0 to 3 := 0;     -- 0=hi,1=lo,2=sep/CR,3=LF
  signal tx_mode      : txmode_t := TXM_ERR;
  signal tx_char      : unsigned(7 downto 0) := x"00";
  signal lt_prev      : std_logic := '0';
  signal busy_prev    : std_logic := '0';

  -- timeouts & gaps
  constant TIMEOUT_WR  : integer := CLK_HZ / 200;     -- ~5 ms
  constant TIMEOUT_RD  : integer := CLK_HZ / 200;     -- ~5 ms
  signal   to_cnt      : integer range 0 to TIMEOUT_RD := 0;

  constant GAP_CYCLES  : integer := CLK_HZ / 50_000;  -- ~20 us
  signal   gap_cnt     : integer range 0 to GAP_CYCLES := 0;

  -- hex helpers
  function hex_hi(b : std_logic_vector(7 downto 0)) return unsigned is
  begin
    case to_integer(unsigned(b(7 downto 4))) is
      when 0  => return x"30"; when 1  => return x"31"; when 2  => return x"32"; when 3  => return x"33";
      when 4  => return x"34"; when 5  => return x"35"; when 6  => return x"36"; when 7  => return x"37";
      when 8  => return x"38"; when 9  => return x"39"; when 10 => return x"41"; when 11 => return x"42";
      when 12 => return x"43"; when 13 => return x"44"; when 14 => return x"45"; when others => return x"46";
    end case;
  end;
  function hex_lo(b : std_logic_vector(7 downto 0)) return unsigned is
  begin
    case to_integer(unsigned(b(3 downto 0))) is
      when 0  => return x"30"; when 1  => return x"31"; when 2  => return x"32"; when 3  => return x"33";
      when 4  => return x"34"; when 5  => return x"35"; when 6  => return x"36"; when 7  => return x"37";
      when 8  => return x"38"; when 9  => return x"39"; when 10 => return x"41"; when 11 => return x"42";
      when 12 => return x"43"; when 13 => return x"44"; when 14 => return x"45"; when others => return x"46";
    end case;
  end;

begin
  U_TX : UART_TX_CTRL
    port map (
      SEND        => tx_send,
      BIT_TMR_MAX => UART_BIT_TMR_MAX,
      DATA        => tx_data,
      CLK         => clk,
      READY       => tx_ready,
      UART_TX     => uart_txd
    );

  U_I2C : i2c_master
    generic map (
      input_clk => CLK_HZ,
      bus_clk   => I2C_BUS_HZ
    )
    port map (
      clk         => clk,
      reset_n     => reset_n,
      ena         => i2c_ena,
      addr        => i2c_addr,
      rw          => i2c_rw,
      data_wr     => i2c_data_wr,
      busy        => i2c_busy,
      data_rd     => i2c_data_rd,
      ack_error   => i2c_ack_error,
      sda         => sda,
      scl         => scl,
      latch_toggle=> i2c_latch_tog,
      swap        => '0', debug_scl => '0', debug_sda => '0'
    );

  process(clk)
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        st <= ST_BANNER;
        tx_send <= '0'; tx_data <= (others => '0'); tx_char <= x"00";
        i2c_ena <= '0'; i2c_rw <= '0'; i2c_data_wr <= (others => '0');
        rd_index <= 0; tx_index <= 0; tx_phase <= 0; tx_mode <= TXM_ERR;
        lt_prev <= '0'; busy_prev <= '0'; to_cnt <= 0; gap_cnt <= 0;
      else
        tx_send  <= '0';                 -- default
        lt_prev  <= i2c_latch_tog;
        busy_prev<= i2c_busy;

        case st is
          --------------------------------------------------------------------
          -- Banner "I2C 0x20\r\n" to prove UART path
          when ST_BANNER =>
            case tx_index is
              when 0  => tx_char <= x"49"; st <= ST_TX_WAIT_RDY;  -- I
              when 1  => tx_char <= x"32"; st <= ST_TX_WAIT_RDY;  -- 2
              when 2  => tx_char <= x"43"; st <= ST_TX_WAIT_RDY;  -- C
              when 3  => tx_char <= x"20"; st <= ST_TX_WAIT_RDY;
              when 4  => tx_char <= x"30"; st <= ST_TX_WAIT_RDY;
              when 5  => tx_char <= x"78"; st <= ST_TX_WAIT_RDY;
              when 6  => tx_char <= x"32"; st <= ST_TX_WAIT_RDY;
              when 7  => tx_char <= x"30"; st <= ST_TX_WAIT_RDY;
              when 8  => tx_char <= x"0D"; st <= ST_TX_WAIT_RDY;
              when 9  => tx_char <= x"0A"; st <= ST_TX_WAIT_RDY;
              when others =>
                tx_index <= 0; to_cnt <= 0; st <= ST_PTR_START_HOLD;
            end case;

          -- === Repeated-START sequence ===
          -- 1) Assert ena and write pointer 0, hold ena high
          when ST_PTR_START_HOLD =>
            i2c_addr    <= SLAVE_ADDR7;
            i2c_rw      <= '0';
            i2c_data_wr <= (others => '0');
            i2c_ena     <= '1';           -- keep high to allow repeated START
            to_cnt      <= 0;
            st          <= ST_PTR_WAIT_BUSY_HI;

          -- 2) Wait for busy to go high (transaction really started)
          when ST_PTR_WAIT_BUSY_HI =>
            if i2c_busy = '1' then
              -- immediately request read; master will issue REPEATED START
              i2c_rw <= '1';
              rd_index <= 0;
              to_cnt <= 0;
              st <= ST_PTR_SWITCH_TO_READ;
            elsif to_cnt >= TIMEOUT_WR then
              i2c_ena <= '0'; tx_mode <= TXM_ERR; tx_index <= 0; st <= ST_TX_GET;
            else
              to_cnt <= to_cnt + 1;
            end if;

          -- 3) Now the master will finish the write byte, see ena still high with rw=1,
          --    and generate a repeated START + address+read. Start collecting bytes.
          when ST_PTR_SWITCH_TO_READ =>
            -- wait for first byte indication (latch_toggle change)
            if i2c_latch_tog /= lt_prev then
              regs(0) <= i2c_data_rd; rd_index <= 1; to_cnt <= 0;
              st <= ST_RD_WAIT_BYTE;
            elsif (i2c_busy = '0' and i2c_ack_error = '1') or (to_cnt >= TIMEOUT_WR) then
              i2c_ena <= '0'; tx_mode <= TXM_ERR; tx_index <= 0; st <= ST_TX_GET;
            else
              to_cnt <= to_cnt + 1;
            end if;

          -- 4) Stream remaining bytes (keep ena high until last byte queued)
          when ST_RD_WAIT_BYTE =>
            if i2c_latch_tog /= lt_prev then
              regs(rd_index) <= i2c_data_rd;
              if rd_index = 15 then
                i2c_ena <= '0';          -- NACK next and STOP
                to_cnt <= 0;
                st <= ST_RD_LAST_WAIT;
              else
                rd_index <= rd_index + 1;
              end if;
            elsif (i2c_busy = '0' and i2c_ack_error = '1') or (to_cnt >= TIMEOUT_RD) then
              i2c_ena <= '0'; tx_mode <= TXM_ERR; tx_index <= 0; st <= ST_TX_GET;
            else
              to_cnt <= to_cnt + 1;
            end if;

          -- 5) Wait for STOP
          when ST_RD_LAST_WAIT =>
            if i2c_busy = '0' then
              tx_mode  <= TXM_HEX; tx_index <= 0; tx_phase <= 0; st <= ST_TX_GET;
            elsif to_cnt >= TIMEOUT_RD then
              tx_mode <= TXM_ERR; tx_index <= 0; st <= ST_TX_GET;
            else
              to_cnt <= to_cnt + 1;
            end if;

          --------------------------------------------------------------------
          -- Character generator (no UART side-effects here)
          when ST_TX_GET =>
            if tx_mode = TXM_ERR then
              -- "NACK\r\n"
              case tx_index is
                when 0  => tx_char <= x"4E"; st <= ST_TX_WAIT_RDY;  -- N
                when 1  => tx_char <= x"41"; st <= ST_TX_WAIT_RDY;  -- A
                when 2  => tx_char <= x"43"; st <= ST_TX_WAIT_RDY;  -- C
                when 3  => tx_char <= x"4B"; st <= ST_TX_WAIT_RDY;  -- K
                when 4  => tx_char <= x"0D"; st <= ST_TX_WAIT_RDY;
                when 5  => tx_char <= x"0A"; st <= ST_TX_WAIT_RDY;
                when others => tx_index <= 0; st <= ST_IDLE_GAP;
              end case;
            else
              -- Hex line: XX XX ... CR LF
              if tx_index <= 15 then
                case tx_phase is
                  when 0 => tx_char <= hex_hi(regs(tx_index)); st <= ST_TX_WAIT_RDY;
                  when 1 => tx_char <= hex_lo(regs(tx_index)); st <= ST_TX_WAIT_RDY;
                  when 2 =>
                    if tx_index = 15 then tx_char <= x"0D"; else tx_char <= x"20"; end if;
                    st <= ST_TX_WAIT_RDY;
                  when others => tx_char <= x"0A"; st <= ST_TX_WAIT_RDY;  -- 3 = LF
                end case;
              else
                st <= ST_IDLE_GAP;
              end if;
            end if;

          -- ===== strict UART handshake =====
          when ST_TX_WAIT_RDY =>
            if tx_ready = '1' then st <= ST_TX_PULSE; end if;

          when ST_TX_PULSE =>
            tx_data <= tx_char; tx_send <= '1'; st <= ST_TX_WAIT_BUSY;

          when ST_TX_WAIT_BUSY =>
            if tx_ready = '0' then st <= ST_TX_WAIT_DONE; end if;

          when ST_TX_WAIT_DONE =>
            if tx_ready = '1' then
              if tx_mode = TXM_ERR then
                if tx_index < 6 then tx_index <= tx_index + 1; end if;
                st <= ST_TX_GET;
              else
                if tx_index <= 15 then
                  case tx_phase is
                    when 0 => tx_phase <= 1;
                    when 1 => tx_phase <= 2;
                    when 2 =>
                      if tx_index = 15 then tx_phase <= 3;
                      else tx_index <= tx_index + 1; tx_phase <= 0;
                      end if;
                    when others => tx_index <= 16; tx_phase <= 0;
                  end case;
                  st <= ST_TX_GET;
                else
                  st <= ST_IDLE_GAP;
                end if;
              end if;
            end if;

          when ST_IDLE_GAP =>
            if gap_cnt = 0 then
              gap_cnt <= GAP_CYCLES;
            elsif gap_cnt = 1 then
              gap_cnt <= 0;  st <= ST_PTR_START_HOLD;  -- loop
            else
              gap_cnt <= gap_cnt - 1;
            end if;

          when others => st <= ST_BANNER;
        end case;
      end if;
    end if;
  end process;

end architecture;
