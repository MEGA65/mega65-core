library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity is42s16320f_model is
  generic (
    clock_frequency : integer := 162_000_000; -- in Hz
    tREFI : real := 64.0; -- in us
    tRP : real := 8.4; -- in ns
    tRCD : real := 8.4; -- in ns
    tWR : real := 8.4; -- in ns
    tRFC : real := 66.0; -- in ns
    tRC : real := 30.9; -- in ns
    tRAS : real := 23.6; -- in ns
    tRRD : real := 2.9; -- in ns
    tCCD : real := 2.5; -- in ns
    tWTR : real := 2.5; -- in ns
    tMRD : real := 2.5; -- in ns
    tXSNR : real := 200.0; -- in ns
    tXSRD : real := 200.0; -- in ns
    tXP : real := 2.5; -- in ns
    tCKE : real := 3.75; -- in ns
    tXS : real := 200.0; -- in ns
    tXSDLL : real := 512.0; -- in ns
    tZQCS : real := 64.0; -- in us
    tZQCL : real := 128.0; -- in us
    tZQINIT : real := 512.0; -- in ns
    tMRW : real := 8.0; -- in ns
    tMOD : real := 15.0; -- in ns
    tCKESR : real := 10.0; -- in ns
    tCKSRX : real := 10.0; -- in ns
    tCKSRE : real := 10.0; -- in ns
    tCKSRT : real := 10.0 -- in ns
  );
  port (
    clk       : in  std_logic;
    reset     : in  std_logic;
    cs        : in  std_logic;
    ras       : in  std_logic;
    cas       : in  std_logic;
    we        : in  std_logic;
    ba        : in  std_logic_vector(1 downto 0);
    addr      : in  std_logic_vector(11 downto 0);
    dq        : inout std_logic_vector(15 downto 0);
    ldqm      : in  std_logic;
    udqm      : in  std_logic;
    clk_en    : in  std_logic;
    power     : in  std_logic_vector(1 downto 0)
  );
end entity is42s16320f_model;

architecture rtl of is42s16320f_model is
  type state_t is (IDLE,
                   ROW_ACTIVE,
                   READ_,
                   WRITE_,
                   READ_WITH_AUTO_PRECHARGE,
                   WRITE_WITH_AUTO_PRECHARGE,
                   PRECHARGING,
                   ROW_ACTIVATING,
                   WRITE_RECOVERING,
                   WRITE_RECOVERING_WITH_AUTO_PRECHARGE,
                   REFRESH,
                   MODE_REGISTER_ACCESSING
                   );
  signal state : state_t;
  signal row_addr : std_logic_vector(11 downto 0);
  signal col_addr : std_logic_vector(8 downto 0);
  signal data : std_logic_vector(15 downto 0);
  signal read_data_reg : std_logic_vector(15 downto 0);
 
  signal clk_period : real := (1_000_000_000.0/real(clock_frequency));
begin

  process (clk, reset)
    variable delay_cnt : integer := 0;
    variable cmd : std_logic_vector(3 downto 0) := "0000";
  begin

    -- SDRAM command is formed from these four signals
    -- See COMMAND TRUTH TABLE from data sheet for more info
    cmd(3) := ras;
    cmd(2) := cas;
    cmd(1) := we;
    cmd(0) := addr(10);
    
    if (reset = '1') then
      state <= POWER_DOWN;
      clk_en_prev <= clk_en;
      dq <= (others => 'Z');
    elsif rising_edge(clk) then
      clk_en_prev <= clk_en;
      case state is
        when IDLE =>
          if (cs = '1') then
            -- CS is inactive. DSEL command
            -- NOTE that depending on existing state, bursts may continue
            case state is
              when IDLE =>
                -- Nothing to do
              when ROW_ACTIVE =>
                -- Nothing to do. Switch to IDLE ???
              when READ_ =>
                -- Continue read burst to end
              when WRITE_ =>
                -- Continue write burst to end
              when READ_WITH_AUTO_PRECHARGE =>
                -- Continue read burst to end, then precharge
              when WRITE_WITH_AUTO_PRECHARGE =>
                -- Continue write burst to end, then precharge
              when PRECHARGING =>
                -- Enter IDLE after tRP
              when ROW_ACTIVATING =>
                -- Enter BANK_ACTIVE after tRCD
              when WRITE_RECOVERING =>
                -- Enter ROW_ACTIVE after tDPL
              when WRITE_RECOVERING_WITH_PRECHARGE =>
                -- Enter PRECHARGING after tDPL
              when REFRESH =>
                -- Enter IDLE after tRC
              when MODE_REGISTER_ACCESS
                -- Enter IDLE after 2 clocks
              when others => null;                
            end case;
            
          else
            -- CS is active
            if clk_en_prev='1' then

              case state is
                when IDLE =>
                  case cmd is
                    when "0000" => -- Mode Register Set (MRS)
                    when "0001" => -- UNDEFINED
                    when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                      if clk_en='0' then
                        -- Self-Refresh                  
                        else
                      -- CBR Auto-Refresh
                      end if;                
                    when "0100" => -- Precharge select bank
                    when "0101" => -- Precharge all banks
                    when "0110" | "0111" => -- Bank activate
                    when "1000" => -- Write
                    when "1001" => -- Write with auto-precharge
                    when "1010" => -- Read
                    when "1011" => -- Read with auto-precharge
                    when "1100" | "1101" => -- Burst stop
                    when "1110" | "1111" => -- No-Operation (NOP)
                    when others => null;
                  end case;
              end if;
                
                
            if (ras = '1' and cas = '0') then
              row_addr <= addr;
              state <= ROW_ACTIVE;
              delay_cnt := integer((tRAS / clk_period) + 0.5);
            elsif (ras = '0' and cas = '1') then
              col_addr <= addr(8 downto 0);
              state <= COLUMN_ACCESS;
              if (we = '1') then
                data <= dq;
              end if;
              delay_cnt := integer((tRP /clk_period) + 0.5);
            end if;
          end if;

        when ROW_ACTIVE =>
          if (cs = '0') then
            if (cas = '1') then
              col_addr <= addr(8 downto 0);
              state <= COLUMN_ACCESS;
              if (we = '1') then
                data <= dq;
              end if;
              delay_cnt := integer((tRCD / clk_period) + 0.5);
            end if;
          else
            state <= PRECHARGE;
            delay_cnt := integer((tRFC / clk_period) + 0.5);
          end if;

        when COLUMN_ACCESS =>
          if (cs = '0') then
            if (we = '1') then
              dq <= data;
            elsif (we = '0') then
              read_data_reg <= dq;
            end if;
            state <= IDLE;
            delay_cnt := integer((tCCD / clk_period) + 0.5);
          else
            state <= PRECHARGE;
            delay_cnt := integer((tRRD / clk_period) + 0.5);
          end if;

        when WRITE_DATA =>
          if (cs = '0') then
            data <= dq;
            state <= COLUMN_ACCESS;
            delay_cnt := integer((tWTR / clk_period) + 0.5);
          else
            state <= PRECHARGE;
            delay_cnt := integer((tWR / clk_period) + 0.5);
          end if;

        when READ_DATA =>
          if (cs = '0') then
            state <= PRECHARGE;
            dq <= read_data_reg;
            delay_cnt := integer((tCCD / clk_period) + 0.5);
          else
            state <= PRECHARGE;
            delay_cnt := integer((tRCD / clk_period) + 0.5);
          end if;

        when PRECHARGE =>
          if (cs = '1') then
            state <= POWER_DOWN;
            delay_cnt := integer((tCKE / clk_period) + 0.5);
          else
            state <= IDLE;
            delay_cnt := integer((tRP / clk_period) + 0.5);
          end if;

        when POWER_DOWN =>
          if (power = "10") then
            state <= IDLE;
          else
            state <= POWER_DOWN;
          end if;
          delay_cnt := integer((tCKESR / clk_period) + 0.5);
      end case;
    end if;

    if (delay_cnt > 0) then
      delay_cnt := delay_cnt - 1;
    end if;

  end process;

end architecture rtl;
