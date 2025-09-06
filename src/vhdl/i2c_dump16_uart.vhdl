library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity megar5_i2c_uart_report is
  generic (
    CLK_HZ    : integer := 40_500_000;   -- cpuclock
    UART_BAUD : integer := 2_000_000     -- ~2.025 Mbps actual @ 40.5 MHz
  );
  port (
    clk       : in  std_logic;
    reset_n   : in  std_logic := '1';

    -- I2C lines (use the same board nets)
    sda       : inout std_logic;
    scl       : inout std_logic;

    -- UART out
    uart_txd  : out std_logic
  );
end entity;

architecture rtl of megar5_i2c_uart_report is
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
  -- Your board I2C block (unchanged behavior)
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

  -- Snapshots to print
  signal byte0_now    : unsigned(7 downto 0); -- {minor,major}
  signal byte1_now    : unsigned(7 downto 0); -- dipsw_read
  signal byte0_last   : unsigned(7 downto 0) := (others => '0');
  signal byte1_last   : unsigned(7 downto 0) := (others => '0');

  -- Emit policy: on change OR every ~100 ms
  constant HEARTBEAT_TICKS : integer := CLK_HZ / 10;
  signal   hb_cnt           : integer range 0 to HEARTBEAT_TICKS := 0;
  signal   emit_req         : std_logic := '0';

  -- TX state
  type state_t is (ST_IDLE, ST_TX_GET, ST_TX_WAIT_RDY, ST_TX_PULSE, ST_TX_WAIT_BUSY, ST_TX_WAIT_DONE, ST_GAP);
  signal st         : state_t := ST_IDLE;
  signal tx_index   : integer range 0 to 5 := 0;   -- 0..4 => 2 bytes + space + CR + LF
  signal tx_phase   : integer range 0 to 1 := 0;   -- 0=hi nib, 1=lo nib
  signal tx_char    : unsigned(7 downto 0) := x"00";
  signal snap0      : unsigned(7 downto 0) := (others => '0');
  signal snap1      : unsigned(7 downto 0) := (others => '0');

  -- hex helpers
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
      clock        => clk,
      ear_watering_mode => '0',
      sda          => sda,
      scl          => scl,
      dipsw_read   => dipsw_read,
      board_major  => board_major,
      board_minor  => board_minor
    );

  -- current bytes derived from the board reader
  byte0_now <= board_minor & board_major;                    -- first byte read at 0x20
  byte1_now <= unsigned(dipsw_read);                         -- second byte read at 0x20

  ---------------------------------------------------------------------------
  -- Reporter
  ---------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        st <= ST_IDLE;
        tx_send <= '0';
        tx_data <= (others => '0');
        tx_char <= x"00";
        tx_index <= 0; tx_phase <= 0;
        byte0_last <= (others => '0');
        byte1_last <= (others => '0');
        snap0 <= (others => '0'); snap1 <= (others => '0');
        hb_cnt <= 0; emit_req <= '0';
      else
        tx_send <= '0';            -- default

        -- Change-or-time-based emit request
        emit_req <= '0';
        if (byte0_now /= byte0_last) or (byte1_now /= byte1_last) then
          emit_req <= '1';
          byte0_last <= byte0_now;
          byte1_last <= byte1_now;
        elsif hb_cnt >= HEARTBEAT_TICKS then
          emit_req <= '1';
          hb_cnt <= 0;
        else
          hb_cnt <= hb_cnt + 1;
        end if;

        case st is
          when ST_IDLE =>
            if emit_req = '1' then
              -- Snapshot and start line: "AA BB\r\n"
              snap0 <= byte0_now;
              snap1 <= byte1_now;
              tx_index <= 0;
              tx_phase <= 0;
              st <= ST_TX_GET;
            end if;

          -- choose next character (no UART side effects here)
          when ST_TX_GET =>
            case tx_index is
              when 0 =>  -- snap0 high nibble / low nibble
                if tx_phase = 0 then tx_char <= hex_nib(snap0(7 downto 4));  st <= ST_TX_WAIT_RDY;
                else                  tx_char <= hex_nib(snap0(3 downto 0));  st <= ST_TX_WAIT_RDY;
                end if;
              when 1 =>  -- space
                tx_char <= x"20"; st <= ST_TX_WAIT_RDY;
              when 2 =>  -- snap1 high nibble / low nibble
                if tx_phase = 0 then tx_char <= hex_nib(snap1(7 downto 4));  st <= ST_TX_WAIT_RDY;
                else                  tx_char <= hex_nib(snap1(3 downto 0));  st <= ST_TX_WAIT_RDY;
                end if;
              when 3 =>  -- CR
                tx_char <= x"0D"; st <= ST_TX_WAIT_RDY;
              when 4 =>  -- LF
                tx_char <= x"0A"; st <= ST_TX_WAIT_RDY;
              when others =>
                st <= ST_GAP;
            end case;

          -- strict UART handshake
          when ST_TX_WAIT_RDY =>
            if tx_ready = '1' then
              st <= ST_TX_PULSE;
            end if;

          when ST_TX_PULSE =>
            tx_data <= tx_char;
            tx_send <= '1';              -- one-cycle pulse
            st <= ST_TX_WAIT_BUSY;

          when ST_TX_WAIT_BUSY =>
            if tx_ready = '0' then
              st <= ST_TX_WAIT_DONE;
            end if;

          when ST_TX_WAIT_DONE =>
            if tx_ready = '1' then
              -- advance indices
              case tx_index is
                when 0 =>
                  if tx_phase = 0 then tx_phase <= 1; else tx_phase <= 0; tx_index <= 1; end if;
                when 1 =>
                  tx_index <= 2; tx_phase <= 0;
                when 2 =>
                  if tx_phase = 0 then tx_phase <= 1; else tx_phase <= 0; tx_index <= 3; end if;
                when 3 =>
                  tx_index <= 4;
                when 4 =>
                  tx_index <= 5;
                when others =>
                  null;
              end case;
              if tx_index = 5 then
                st <= ST_GAP;
              else
                st <= ST_TX_GET;
              end if;
            end if;

          when ST_GAP =>
            -- tiny pause to avoid immediately re-emitting in the same cycle
            st <= ST_IDLE;

          when others =>
            st <= ST_IDLE;
        end case;
      end if;
    end if;
  end process;

end architecture;
