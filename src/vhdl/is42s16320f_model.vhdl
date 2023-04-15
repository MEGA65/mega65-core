-- Assumes speed grade -6

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
    addr      : in  std_logic_vector(12 downto 0);
    dq        : inout std_logic_vector(15 downto 0);
    ldqm      : in  std_logic;
    udqm      : in  std_logic;
    clk_en    : in  std_logic;

    -- This is a port rather than a generic, so that we can change it during
    -- the execution of tests
    enforce_100usec_init : in boolean := true; -- Require 100usec delay on power
                                               -- on before init?
    
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
  signal bank : std_logic(1 downto 0);
  signal row_addr : std_logic_vector(12 downto 0);
  signal col_addr : std_logic_vector(8 downto 0);
  signal data : std_logic_vector(15 downto 0);
  signal read_data_reg : std_logic_vector(15 downto 0);
 
  signal clk_period : real := (1_000_000_000.0/real(clock_frequency));

  constant cycles_100usec = clock_frequency / 10.0;
  signal cycles_elapsed : integer := 0;
  
  type init_state_t is (WAIT_FOR_NOP_01,
                        WAIT_FOR_PRECHARGE_02,
                        WAIT_FOR_AUTOREFRESH_03,
                        WAIT_FOR_NOP_04,
                        WAIT_FOR_AUTOREFRESH_05,
                        WAIT_FOR_NOP_06,
                        WAIT_FOR_AUTOREFRESH_07,
                        WAIT_FOR_MODE_PROG_08,
                        WAIT_FOR_NOP_09,
                        INIT_COMPLETE
                        );
                        
  signal init_state : init_state_t := WAIT_FOR_NOP_01;

  signal delay_cnt : integer := 0;

  signal cas_latency : integer := 3;
  signal burst_length : integer := 1;
  signal terminating_read : std_logic := '0';  
    
  procedure update_mode_register(bits : in std_logic_vector(12 downto 0)) is
  begin
    case bits(2 downto 0) is
      when "000" => burst_length <= 1;
      when "000" => burst_length <= 2;
      when "000" => burst_length <= 4;
      when "000" => burst_length <= 8;
      when "000" => assert failure report "Illegal burst length selected";
      when "000" => assert failure report "Illegal burst length selected";
      when "000" => assert failure report "Illegal burst length selected";
      when "111" => burst_length <= 512;  -- full page
    end case;
    interleaved_mode <= bits(3);
    if bits(3)='1' then
      assert failure report "interleaved mode not supported";
    end if;
    case bits(6 downto 4) is
      when "000" => assert failure report "Illegal CAS recovery selected";
      when "001" => assert failure report "Illegal CAS recovery selected";
      when "010" => cas_latency <= 2;
                    -- Assumes speed grade -5 or better
                    if clock_frequency > 100_000_000 then
                      assert failure report "CAS=2 requires clock frequency not exceeding 100MHz";
                    end if;
      when "011" => cas_latency <= 3;                    
                    -- Assumes speed grade -6 or better
                    if clock_frequency > 167_000_000 then
                      assert failure report "CAS=3 requires clock frequency not exceeding 167MHz";
                    end if;
      when "100" => assert failure report "Illegal CAS recovery selected";
      when "100" => assert failure report "Illegal CAS recovery selected";
      when "100" => assert failure report "Illegal CAS recovery selected";
      when "100" => assert failure report "Illegal CAS recovery selected";
    end case;
    if bits(8 downto 7) /= "00" then
      assert failure "Illegal operating mode selected";
    end if;
    -- Disable burst flag: Just make burst length = 1
    if bits(9)='1' then
      burst_length <= 1;
    end if;
    if bits(12 downto 10) /= "000" then
      assert failure "A10--A12 must be zero when setting operating mode register";
    end if;
  end procedure;

  procedure do_bank_and_row_select is
  begin
    bank <= ba;
    row_addr <= addr;
    delay_cnt <= integer((tRCD / clk_period) + 0.5);    
    if init_state /= INIT_COMPLETE then
      assert failure report "Attempted to activate a row before initialisation sequence complete";
    end if;
  end procedure;

  
begin

  process (clk, reset)
    variable cmd : std_logic_vector(3 downto 0) := "0000";
  begin

    -- SDRAM command is formed from these four signals
    -- See COMMAND TRUTH TABLE from data sheet for more info
    cmd(3) := ras;
    cmd(2) := cas;
    cmd(1) := we;
    cmd(0) := addr(10);
    
    if (reset = '1') then
      state <= IDLE;
      clk_en_prev <= clk_en;
      dq <= (others => 'Z');
      terminating_read <= '0';
    elsif rising_edge(clk) then
      clk_en_prev <= clk_en;
      dq <= (others => 'Z');
      terminating_read <= '0';

      -- XXX Does col_addr increment while clock is suspended or not?      
      if col_addr /= "1111111111" then
        col_addr <= col_addr + 1;
      else
        col_addr <= "0000000000";
      end if;
      -- Simulate CAS latency pipeline
      cas_pipeline(0) <= ram_array(to_integer(unsigned(row_addr & col_addr)));
      cas_pipeline(1) <= cas_pipeline(0);
      cas_pipeline(2) <= cas_pipeline(1);
      cas_pipeline(3) <= cas_pipeline(2);

      -- Export read data whenever xDQM are low
      -- (or only during reads, and when changing from read to something else?)
      if udqm='0' then
        dq(15 downto 8) <= cas_pipeline(cas_latency);
      end if;
      if ldqm='0' then
        dq(7 downto 0) <= cas_pipeline(cas_latency);
      end if;
      
      if state = READ_ or state = READ_WITH_AUTO_PRECHARGE then
        if delay_cnt /= 0 then
          -- wait for CAS delay to expire before presenting data
          delay_cnt <= delay_cnt - 1;
        end if;
      end if;
      if burst_remaining = 1 then
        -- End of burst
        burst_remaining <= 0;
        case state is
          when READ_ => state <= ROW_ACTIVE;
          when WRITE_ <= state <= WRITE_RECOVERING;
          when READ_WITH_AUTO_PRECHARGE => state <= PRECHARGING;
          when WRITE_WITH_AUTO_PRECHARGE => state <= WRITE_RECOVERING_WITH_AUTO_PRECHARGE;
          when others => null;
        end case;
      else
        burst_remaining <= burst_remaining - 1;
      end if;
      if terminating_read='1' then
        if state = READ_ then
          state <= ROW_ACTIVE;
        else
          state <= PRECHARGING;
        end if;
      end if;                      
      
      if (delay_cnt > 0) then
        delay_cnt <= delay_cnt - 1;
      end if;
      
      if enforce_100usec_init then
        if cycles_elapsed < cycles_100usec then
          cycles_elapsed <= cycles_elapsed + 1;
        else
          elapsed_100usec <= '1';
        end if;
      else
        elapsed_100usec <= '1';
      end if;
      
      -- Enforce initialisation sequence
      if clk_en_prev='1' then

        case cmd is
          when "0000" => -- Mode Register Set (MRS)
            if init_state = WAIT_FOR_MODE_PROG_08 then
              init_state <= WAIT_FOR_NOP_09;
            end if;
          when "0001" => -- UNDEFINED
          when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
            if clk_en='0' then
              -- Self-Refresh                  
            else
              -- CBR Auto-Refresh
              if init_state = WAIT_FOR_AUTOREFRESH_05 then
                init_state <= WAIT_FOR_MODE_PROG_06;
              end if;                
              if init_state = WAIT_FOR_AUTOREFRESH_07 then
                init_state <= WAIT_FOR_MODE_PROG_08;
              end if;
            end if;
          when "0100" => -- Precharge select bank            
          when "0101" => -- Precharge all banks
            if init_state = WAIT_FOR_PRECHARGE_02 and elapsed_100usec='1' then
              init_state <= WAIT_FOR_AUTOREFRESH_03;
            end if;
          when "0110" | "0111" => -- Bank + row activate
          when "1000" => -- Write
          when "1001" => -- Write with auto-precharge
          when "1010" => -- Read
          when "1011" => -- Read with auto-precharge
          when "1100" | "1101" => -- Burst stop
          when "1110" | "1111" => -- No-Operation (NOP)
            if init_state = WAIT_FOR_NOP_01 then
              init_state <= WAIT_FOR_PRECHARGE_02;
            end if;
            if init_state = WAIT_FOR_NOP_04 then
              init_state <= WAIT_FOR_PRECHARGE_05;
            end if;
            if init_state = WAIT_FOR_NOP_06 then
              init_state <= WAIT_FOR_PRECHARGE_07;
            end if;
            if init_state = WAIT_FOR_NOP_09 then
              init_state <= INIT_COMPLETE;
            end if;
            
          when others => null;
        end case;
      end if;
      
      
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
            if clk_en_prev='0' then
              -- CLK_EN at T-1 was low, so suspend any read or write in progress,
              -- but make no other changes
            else
              -- CLK_EN at T-1 was high, so proceed
              case state is
                when IDLE =>
                  case cmd is
                    when "0000" | "0001" => -- Mode Register Set (MRS)
                      update_mode_register(addr);
                    when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                      if clk_en='0' then
                        -- Self-Refresh                  
                        else
                      -- CBR Auto-Refresh
                      end if;                
                    when "0100" => -- Precharge select bank
                    when "0101" => -- Precharge all banks
                    when "0110" | "0111" => -- Bank+row activate
                      -- Select bank and row, and cause wait for tRCD before ready
                      do_bank_and_row_select();
                      state <= ROW_ACTIVE;
                    when "1000" => -- Write
                    when "1001" => -- Write with auto-precharge
                    when "1010" => -- Read
                    when "1011" => -- Read with auto-precharge
                    when "1100" | "1101" => -- Burst stop
                    when "1110" | "1111" => -- No-Operation (NOP)
                    when others => null;
                  end case;
                when ROW_ACTIVE =>
                  case cmd is
                    when "0000" | "0001" => -- Mode Register Set (MRS)
                      update_mode_register(addr);
                    when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                      if clk_en='0' then
                        -- Self-Refresh                  
                        else
                      -- CBR Auto-Refresh
                      end if;                
                    when "0100" => -- Precharge select bank
                    when "0101" => -- Precharge all banks
                    when "0110" | "0111" => -- Bank + row activate
                      assert failure report "Attempted to activate row from " & state_t'image(state) & " state";
                    when "1000" => -- Write
                      if delay_cnt /= 0 then
                        assert failure report "Attempted to write before tRCD had elapsed following ROW_ACTIVATE command";
                      end if;
                      col_addr <= addr(8 downto 0);
                      burst_remaining <= burst_length + cas_latency - 1;
                      state <= WRITE_;
                    when "1001" => -- Write with auto-precharge
                      if delay_cnt /= 0 then
                        assert failure report "Attempted to write before tRCD had elapsed following ROW_ACTIVATE command";
                      end if;
                      col_addr <= addr(8 downto 0);
                      burst_remaining <= burst_length + cas_latency - 1;
                      state <= WRITE_WITH_AUTO_PRECHARGE;
                    when "1010" => -- Read
                      if delay_cnt /= 0 then
                        assert failure report "Attempted to read before tRCD had elapsed following ROW_ACTIVATE command";
                      end if;
                      delay_cnt <= cas_latency - 1;
                      col_addr <= addr(8 downto 0);
                      burst_remaining <= burst_length + cas_latency - 1;
                      state <= READ_;
                    when "1011" => -- Read with auto-precharge
                      if delay_cnt /= 0 then
                        assert failure report "Attempted to read before tRCD had elapsed following ROW_ACTIVATE command";
                      end if;
                      delay_cnt <= cas_latency - 1;
                      col_addr <= addr(8 downto 0);
                      burst_remaining <= burst_length + cas_latency - 1;
                      state <= READ_WITH_AUTO_PRECHARGE;
                    when "1100" | "1101" => -- Burst stop
                      assert failure report "Burst stop requested in state " & state_t'image(state);
                    when "1110" | "1111" => -- No-Operation (NOP)
                    when others => null;
                  end case;
                when READ_ =>
                  case cmd is
                    when "0000" | "0001" => -- Mode Register Set (MRS)
                      assert failure report "Attempted to access mode register during READ";
                    when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                      assert failure report "Attempted to trigger refresh during READ";
                    when "0100" => -- Precharge select bank
                      -- Terminate burst, begin precharging                      
                    when "0101" => -- Precharge all banks
                      -- Terminate burst, begin precharging
                    when "0110" | "0111" => -- Bank + row activate
                      -- Terminate burst, begin selecting new row
                      do_bank_and_row_select();                      
                    when "1000" => -- Write
                      -- Terminate burst, begin write
                      col_addr <= addr(8 downto 0);
                      burst_remaining <= burst_length + cas_latency - 1;
                      state <= WRITE_;
                    when "1001" => -- Write with auto-precharge
                      -- Terminate burst, begin write
                      col_addr <= addr(8 downto 0);
                      burst_remaining <= burst_length + cas_latency - 1;
                      state <= WRITE_WITH_AUTO_PRECHARGE;
                    when "1010" => -- Read
                      -- Terminate burst, begin new read
                      col_addr <= addr(8 downto 0);
                      burst_remaining <= burst_length + cas_latency - 1;
                      state <= READ_;
                    when "1011" => -- Read with auto-precharge
                      -- Terminate burst, begin new read
                      col_addr <= addr(8 downto 0);
                      burst_remaining <= burst_length + cas_latency - 1;
                      state <= READ_WITH_AUTO_PRECHARGE;
                    when "1100" | "1101" => -- Burst stop
                      -- Terminate burst, return to ROW_ACTIVE state
                      -- But still output one more word if cas_latency = 3
                      if cas_latency /= 3 then
                        state <= ROW_ACTIVE;
                      else
                        terminating_read <= '1';
                      end if;
                      delay_cnt <= 0;
                    when "1110" | "1111" => -- No-Operation (NOP)
                    when others => null;
                  end case;
                when WRITE_ =>
                  case cmd is
                    when "0000" | "0001" => -- Mode Register Set (MRS)
                      update_mode_register(addr);
                    when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                      if clk_en='0' then
                        -- Self-Refresh                  
                        else
                      -- CBR Auto-Refresh
                      end if;                
                    when "0100" => -- Precharge select bank
                    when "0101" => -- Precharge all banks
                    when "0110" | "0111" => -- Bank + row activate
                      assert failure report "Attempted to activate row from " & state_t'image(state) & " state";
                    when "1000" => -- Write
                    when "1001" => -- Write with auto-precharge
                    when "1010" => -- Read
                    when "1011" => -- Read with auto-precharge
                    when "1100" | "1101" => -- Burst stop
                    when "1110" | "1111" => -- No-Operation (NOP)
                    when others => null;
                  end case;
                when READ_WITH_AUTO_PRECHARGE =>
                  case cmd is
                    when "0000" | "0001" => -- Mode Register Set (MRS)
                      update_mode_register(addr);
                    when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                      if clk_en='0' then
                        -- Self-Refresh                  
                        else
                      -- CBR Auto-Refresh
                      end if;                
                    when "0100" => -- Precharge select bank
                    when "0101" => -- Precharge all banks
                    when "0110" | "0111" => -- Bank + row activate
                      assert failure report "Attempted to activate row from " & state_t'image(state) & " state";
                    when "1000" => -- Write
                    when "1001" => -- Write with auto-precharge
                    when "1010" => -- Read
                      -- Terminate burst, begin new read
                      col_addr <= addr(8 downto 0);
                      burst_remaining <= burst_length + cas_latency;
                      state <= READ_;
                    when "1011" => -- Read with auto-precharge
                      -- Terminate burst, begin new read
                      col_addr <= addr(8 downto 0);
                      burst_remaining <= burst_length + cas_latency;
                      state <= READ_WITH_AUTO_PRECHARGE;
                    when "1100" | "1101" => -- Burst stop
                      -- Terminate burst, return to ROW_ACTIVE state
                      state <= ROW_ACTIVE;
                      delay_cnt <= 0;
                    when others => null;
                  end case;
                when WRITE_WITH_AUTO_PRECHARGE =>
                  case cmd is
                    when "0000" | "0001" => -- Mode Register Set (MRS)
                      update_mode_register(addr);
                    when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                      if clk_en='0' then
                        -- Self-Refresh                  
                        else
                      -- CBR Auto-Refresh
                      end if;                
                    when "0100" => -- Precharge select bank
                    when "0101" => -- Precharge all banks
                    when "0110" | "0111" => -- Bank + row activate
                      assert failure report "Attempted to activate row from " & state_t'image(state) & " state";
                    when "1000" => -- Write
                    when "1001" => -- Write with auto-precharge
                    when "1010" => -- Read
                    when "1011" => -- Read with auto-precharge
                    when "1100" | "1101" => -- Burst stop
                    when "1110" | "1111" => -- No-Operation (NOP)
                    when others => null;
                  end case;
                when PRECHARGING =>
                  case cmd is
                    when "0000" => -- Mode Register Set (MRS)
                      update_mode_register(addr);
                    when "0001" => -- UNDEFINED
                    when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                      if clk_en='0' then
                        -- Self-Refresh                  
                        else
                      -- CBR Auto-Refresh
                      end if;                
                    when "0100" => -- Precharge select bank
                    when "0101" => -- Precharge all banks
                    when "0110" | "0111" => -- Bank + row activate
                      assert failure report "Attempted to activate row from " & state_t'image(state) & " state";
                    when "1000" => -- Write
                    when "1001" => -- Write with auto-precharge
                    when "1010" => -- Read
                    when "1011" => -- Read with auto-precharge
                    when "1100" | "1101" => -- Burst stop
                    when "1110" | "1111" => -- No-Operation (NOP)
                    when others => null;
                  end case;
                when ROW_ACTIVATING =>
                  case cmd is
                    when "0000" => -- Mode Register Set (MRS)
                      update_mode_register(addr);
                    when "0001" => -- UNDEFINED
                    when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                      if clk_en='0' then
                        -- Self-Refresh                  
                        else
                      -- CBR Auto-Refresh
                      end if;                
                    when "0100" => -- Precharge select bank
                    when "0101" => -- Precharge all banks
                    when "0110" | "0111" => -- Bank + row activate
                      assert failure report "Attempted to activate row from " & state_t'image(state) & " state";
                    when "1000" => -- Write
                    when "1001" => -- Write with auto-precharge
                    when "1010" => -- Read
                    when "1011" => -- Read with auto-precharge
                    when "1100" | "1101" => -- Burst stop
                    when "1110" | "1111" => -- No-Operation (NOP)
                    when others => null;
                  end case;
                when WRITE_RECOVERING =>
                  case cmd is
                    when "0000" => -- Mode Register Set (MRS)
                      update_mode_register(addr);
                    when "0001" => -- UNDEFINED
                    when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                      if clk_en='0' then
                        -- Self-Refresh                  
                        else
                      -- CBR Auto-Refresh
                      end if;                
                    when "0100" => -- Precharge select bank
                    when "0101" => -- Precharge all banks
                    when "0110" | "0111" => -- Bank + row activate
                      assert failure report "Attempted to activate row from " & state_t'image(state) & " state";
                    when "1000" => -- Write
                    when "1001" => -- Write with auto-precharge
                    when "1010" => -- Read
                    when "1011" => -- Read with auto-precharge
                    when "1100" | "1101" => -- Burst stop
                    when "1110" | "1111" => -- No-Operation (NOP)
                    when others => null;
                  end case;
                when WRITE_RECOVERING_WITH_PRECHARGE =>
                  case cmd is
                    when "0000" => -- Mode Register Set (MRS)
                      update_mode_register(addr);
                    when "0001" => -- UNDEFINED
                    when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                      if clk_en='0' then
                        -- Self-Refresh                  
                        else
                      -- CBR Auto-Refresh
                      end if;                
                    when "0100" => -- Precharge select bank
                    when "0101" => -- Precharge all banks
                    when "0110" | "0111" => -- Bank + row activate
                      assert failure report "Attempted to activate row from " & state_t'image(state) & " state";
                    when "1000" => -- Write
                    when "1001" => -- Write with auto-precharge
                    when "1010" => -- Read
                    when "1011" => -- Read with auto-precharge
                    when "1100" | "1101" => -- Burst stop
                    when "1110" | "1111" => -- No-Operation (NOP)
                    when others => null;
                  end case;
                when REFRESH =>
                  case cmd is
                    when "0000" => -- Mode Register Set (MRS)
                      update_mode_register(addr);
                    when "0001" => -- UNDEFINED
                    when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                      if clk_en='0' then
                        -- Self-Refresh                  
                        else
                      -- CBR Auto-Refresh
                      end if;                
                    when "0100" => -- Precharge select bank
                    when "0101" => -- Precharge all banks
                    when "0110" | "0111" => -- Bank + row activate
                      assert failure report "Attempted to activate row from " & state_t'image(state) & " state";
                    when "1000" => -- Write
                    when "1001" => -- Write with auto-precharge
                    when "1010" => -- Read
                    when "1011" => -- Read with auto-precharge
                    when "1100" | "1101" => -- Burst stop
                    when "1110" | "1111" => -- No-Operation (NOP)
                    when others => null;
                  end case;
                when MODE_REGISTER_ACCESS =>
                  case cmd is
                    when "0000" => -- Mode Register Set (MRS)
                      update_mode_register(addr);
                    when "0001" => -- UNDEFINED
                    when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                      if clk_en='0' then
                        -- Self-Refresh                  
                        else
                      -- CBR Auto-Refresh
                      end if;                
                    when "0100" => -- Precharge select bank
                    when "0101" => -- Precharge all banks
                    when "0110" | "0111" => -- Bank + row activate
                      assert failure report "Attempted to activate row from " & state_t'image(state) & " state";
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

  end process;

end architecture rtl;
