-- Assumes speed grade -6

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity is42s16320f_model is
  generic (
    clock_frequency : integer := 162_000_000; -- in Hz
    tXSR : real := 70.0; -- in ns
    tRAS : real := 42.0; -- in ns
    tRP : real := 18.0; -- in ns
    tRCD : real := 18.0 -- in ns
  );
  port (
    clk       : in  std_logic;
    reset     : in  std_logic;
    cs        : in  std_logic;
    ras       : in  std_logic;
    cas       : in  std_logic;
    we        : in  std_logic;
    ba        : in  unsigned(1 downto 0);
    addr      : in  unsigned(12 downto 0);
    dq        : inout unsigned(15 downto 0);
    ldqm      : in  std_logic;
    udqm      : in  std_logic;
    clk_en    : in  std_logic;

    -- This is a port rather than a generic, so that we can change it during
    -- the execution of tests
    enforce_100usec_init : in boolean := true -- Require 100usec delay on power
                                               -- on before init?
    
  );
end entity is42s16320f_model;

architecture rtl of is42s16320f_model is
  type ram_t  is array(0 to 32*1024*1024) of unsigned(15 downto 0);
  signal ram_array : ram_t := (others => (others => '0'));

  type state_t is (IDLE,
                   ROW_ACTIVE,
                   READ_PLAIN,
                   WRITE_PLAIN,
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
  signal bank : unsigned(1 downto 0);
  signal row_addr : unsigned(12 downto 0);
  signal col_addr : unsigned(8 downto 0);
  signal data : unsigned(15 downto 0);
 
  signal clk_period : real := (1_000_000_000.0/real(clock_frequency));

  constant cycles_100usec : integer := integer(real(clock_frequency) / 10.0);
  signal cycles_elapsed : integer := 0;
  signal elapsed_100usec : std_logic := '0';
  
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
  signal burst_remaining : integer := 0;
  signal cas_read : std_logic_vector(3 downto 0) := (others => '0');
  type cas_pipe_t is array (0 to 3) of unsigned(15 downto 0);
  signal cas_pipeline : cas_pipe_t;
  signal write_queue_data : cas_pipe_t;
  type masks_pipe_t is array (0 to 3) of unsigned(1 downto 0);
  signal write_queue_masks : masks_pipe_t;
  type addr_pipe_t is array (0 to 3) of unsigned(22 downto 0);
  signal write_queue_addr : addr_pipe_t;
  
  signal clk_en_prev : std_logic := '1';
  
begin

  process (clk, reset)
    variable cmd : std_logic_vector(3 downto 0) := "0000";

  procedure update_mode_register(bits : in unsigned(12 downto 0)) is
  begin
    case bits(2 downto 0) is
      when "000" => burst_length <= 1;
      when "001" => burst_length <= 2;
      when "010" => burst_length <= 4;
      when "011" => burst_length <= 8;
      when "100" => assert false report "Illegal burst length selected";
      when "101" => assert false report "Illegal burst length selected";
      when "110" => assert false report "Illegal burst length selected";
      when "111" => burst_length <= 512;  -- full page
      when others => assert false report "Non-resolved value in burst length field";
    end case;
    if bits(3)='1' then
      assert false report "interleaved mode not supported";
    end if;
    case bits(6 downto 4) is
      when "000" => assert false report "Illegal CAS recovery selected";
      when "001" => assert false report "Illegal CAS recovery selected";
      when "010" => cas_latency <= 2;
                    -- Assumes speed grade -5 or better
                    if clock_frequency > 100_000_000 then
                      assert false report "CAS=2 requires clock frequency not exceeding 100MHz";
                    end if;
      when "011" => cas_latency <= 3;                    
                    -- Assumes speed grade -6 or better
                    if clock_frequency > 167_000_000 then
                      assert false report "CAS=3 requires clock frequency not exceeding 167MHz";
                    end if;
      when "100" => assert false report "Illegal CAS recovery selected";
      when "101" => assert false report "Illegal CAS recovery selected";
      when "110" => assert false report "Illegal CAS recovery selected";
      when "111" => assert false report "Illegal CAS recovery selected";
      when others => assert false report "Non-resolved value in CAS recovery field";
    end case;
    if bits(8 downto 7) /= "00" then
      assert false report "Illegal operating mode selected";
    end if;
    -- Disable burst flag: Just make burst length = 1
    if bits(9)='1' then
      burst_length <= 1;
    end if;
    if bits(12 downto 10) /= "000" then
      assert false report "A10--A12 must be zero when setting operating mode register";
    end if;
  end procedure;

  procedure do_bank_and_row_select is
  begin
    bank <= ba;
    row_addr <= addr;
    delay_cnt <= integer((tRCD / clk_period) + 0.5);    
    if init_state /= INIT_COMPLETE then
      assert false report "Attempted to activate a row before initialisation sequence complete";
    end if;
  end procedure;

  procedure do_write is
  begin
    write_queue_masks(0) <= udqm & ldqm;
    write_queue_data(0) <= dq;
    write_queue_addr(0) <= row_addr & col_addr;
  end procedure;  

  procedure do_write_start is
  begin
    burst_remaining <= burst_length - 1;
    write_queue_masks(0) <= udqm & ldqm;
    write_queue_data(0) <= dq;
    write_queue_addr(0) <= row_addr & addr(8 downto 0);
    col_addr <= addr(8 downto 0);
  end procedure;
  

    
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
    elsif rising_edge(clk) then
      clk_en_prev <= clk_en;
      dq <= (others => 'Z');

      -- XXX Does col_addr increment while clock is suspended or not?      
      if col_addr /= "1111111111" then
        col_addr <= col_addr + 1;
      else
        col_addr <= (others => '0');
      end if;
      -- Simulate CAS latency pipeline
      cas_pipeline(0) <= ram_array(to_integer(row_addr & col_addr));
      cas_pipeline(1) <= cas_pipeline(0);
      cas_pipeline(2) <= cas_pipeline(1);
      cas_pipeline(3) <= cas_pipeline(2);
      cas_read(0) <= '0';
      cas_read(1) <= cas_read(0);
      cas_read(2) <= cas_read(1);
      cas_read(3) <= cas_read(2);

      write_queue_data(0) <= (others => '0');
      write_queue_data(1) <= write_queue_data(0);
      write_queue_data(2) <= write_queue_data(1);
      write_queue_data(3) <= write_queue_data(2);
      write_queue_masks(0) <= (others => '1');
      write_queue_masks(1) <= write_queue_masks(0);
      write_queue_masks(2) <= write_queue_masks(1);
      write_queue_masks(3) <= write_queue_masks(2);
      if write_queue_masks(3)(0)='0' then
        ram_array(to_integer(row_addr & col_addr))(7 downto 0) <= write_queue_data(0)(7 downto 0);
      end if;
      if write_queue_masks(3)(1)='0' then
        ram_array(to_integer(row_addr & col_addr))(15 downto 8) <= write_queue_data(0)(15 downto 8);
      end if;
      
      -- Export read data whenever xDQM are low EXCEPT when we might be
      -- asked to do a WRITE, as we need to avoid bus contention with that
      -- case, as the xDQM bits are used to indicate which byte(s) should
      -- be written.
      if cas_read(cas_latency-1)='1' then
        if udqm='0' then
          dq(15 downto 8) <= cas_pipeline(cas_latency - 1)(15 downto 8);
        end if;
        if ldqm='0' then
          dq(7 downto 0) <= cas_pipeline(cas_latency - 1)(7 downto 0);
        end if;
      end if;
      
      if delay_cnt /= 0 then
        delay_cnt <= delay_cnt - 1;
      end if;
      
      if burst_remaining = 1 then
        -- End of burst
        burst_remaining <= 0;
        case state is
          when READ_PLAIN => state <= ROW_ACTIVE;
          when WRITE_PLAIN => state <= WRITE_RECOVERING;
          when READ_WITH_AUTO_PRECHARGE => state <= PRECHARGING;
          when WRITE_WITH_AUTO_PRECHARGE => state <= WRITE_RECOVERING_WITH_AUTO_PRECHARGE;
          when others => null;
        end case;
      else
        burst_remaining <= burst_remaining - 1;
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
                init_state <= WAIT_FOR_NOP_06;
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
              init_state <= WAIT_FOR_AUTOREFRESH_05;
            end if;
            if init_state = WAIT_FOR_NOP_06 then
              init_state <= WAIT_FOR_AUTOREFRESH_07;
            end if;
            if init_state = WAIT_FOR_NOP_09 then
              init_state <= INIT_COMPLETE;
            end if;
            
          when others => null;
        end case;
      end if;
      
      
      if (cs = '1') then
        -- CS is inactive. DSEL command
        -- NOTE that depending on existing state, bursts may continue
        case state is
          when IDLE =>
          -- Nothing to do
          when ROW_ACTIVE =>
          -- Nothing to do. Switch to IDLE ???
          when READ_PLAIN =>
          -- Continue read burst to end
          when WRITE_PLAIN =>
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
          when WRITE_RECOVERING_WITH_AUTO_PRECHARGE =>
          -- Enter PRECHARGING after tDPL
          when REFRESH =>
          -- Enter IDLE after tRC
          when MODE_REGISTER_ACCESSING =>
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
                  delay_cnt <= integer(((tRAS + tXSR) / clk_period) + 0.5);    
                when "0100" => -- Precharge select bank
                  assert false report "Illegal request to move from state " & state_t'image(state) & " via command " & to_string(cmd);
                when "0101" => -- Precharge all banks
                  assert false report "Illegal request to move from state " & state_t'image(state) & " via command " & to_string(cmd);
                when "0110" | "0111" => -- Bank+row activate
                  -- Select bank and row, and cause wait for tRCD before ready
                  do_bank_and_row_select;
                  state <= ROW_ACTIVE;
                when "1000" => -- Write
                  assert false report "Illegal request to move from state " & state_t'image(state) & " via command " & to_string(cmd);
                when "1001" => -- Write with auto-precharge
                  assert false report "Illegal request to move from state " & state_t'image(state) & " via command " & to_string(cmd);
                when "1010" => -- Read
                  assert false report "Illegal request to move from state " & state_t'image(state) & " via command " & to_string(cmd);
                when "1011" => -- Read with auto-precharge
                  assert false report "Illegal request to move from state " & state_t'image(state) & " via command " & to_string(cmd);
                when "1100" | "1101" => -- Burst stop
                  assert false report "Illegal request to move from state " & state_t'image(state) & " via command " & to_string(cmd);
                when "1110" | "1111" => -- No-Operation (NOP)
                  null;
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
                  assert false report "Attempted to trigger refresh from " & state_t'image(state) & " state";
                when "0100" => -- Precharge select bank
                  delay_cnt <= cas_latency;
                when "0101" => -- Precharge all banks
                  delay_cnt <= cas_latency;
                when "0110" | "0111" => -- Bank + row activate
                  assert false report "Attempted to activate row from " & state_t'image(state) & " state";
                when "1000" => -- Write
                  if delay_cnt /= 0 then
                    assert false report "Attempted to write before tRCD had elapsed following " & state_t'image(state) & " command";
                  end if;
                  do_write_start;
                  if burst_length > 1 then
                    state <= WRITE_PLAIN;
                  end if;
                when "1001" => -- Write with auto-precharge
                  if delay_cnt /= 0 then
                    assert false report "Attempted to write with precharge before tRCD had elapsed following " & state_t'image(state) & " command";
                  end if;
                  do_write_start;
                  if burst_length > 1 then
                    state <= WRITE_WITH_AUTO_PRECHARGE;
                  else
                    state <= PRECHARGING;
                  end if;
                when "1010" => -- Read
                  if delay_cnt /= 0 then
                    assert false report "Attempted to read before tRCD had elapsed following " & state_t'image(state) & " command";
                  end if;
                  delay_cnt <= cas_latency - 1;
                  col_addr <= addr(8 downto 0);
                  burst_remaining <= burst_length + cas_latency - 1;
                  state <= READ_PLAIN;
                when "1011" => -- Read with auto-precharge
                  if delay_cnt /= 0 then
                    assert false report "Attempted to read before tRCD had elapsed following ROW_ACTIVE command";
                  end if;
                  delay_cnt <= cas_latency - 1;
                  col_addr <= addr(8 downto 0);
                  burst_remaining <= burst_length + cas_latency - 1;
                  state <= READ_WITH_AUTO_PRECHARGE;
                when "1100" | "1101" => -- Burst stop
                  assert false report "Burst stop requested in state " & state_t'image(state);
                when "1110" | "1111" => -- No-Operation (NOP)
                  null;
                when others => null;
              end case;
            when READ_PLAIN =>
              cas_read(0) <= '1';
              case cmd is
                when "0000" | "0001" => -- Mode Register Set (MRS)
                  assert false report "Attempted to access mode register during READ";
                when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                  assert false report "Attempted to trigger refresh during READ";
                when "0100" => -- Precharge select bank
                  -- Terminate burst, begin precharging                      
                  delay_cnt <= cas_latency;
                  state <= ROW_ACTIVE;
                when "0101" => -- Precharge all banks
                  -- Terminate burst, begin precharging
                  delay_cnt <= cas_latency;
                  state <= ROW_ACTIVE;
                when "0110" | "0111" => -- Bank + row activate
                  -- Terminate burst, begin selecting new row
                  do_bank_and_row_select;                      
                when "1000" => -- Write
                  -- Terminate burst, begin write
                  do_write_start;
                  if burst_length > 1 then
                    state <= WRITE_PLAIN;
                  end if;
                when "1001" => -- Write with auto-precharge
                  -- Terminate burst, begin write
                  do_write_start;
                  if burst_length > 1 then
                    state <= WRITE_WITH_AUTO_PRECHARGE;
                  end if;
                when "1010" => -- Read
                  -- Terminate burst, begin new read
                  col_addr <= addr(8 downto 0);
                  burst_remaining <= burst_length + cas_latency - 1;
                  state <= READ_PLAIN;
                when "1011" => -- Read with auto-precharge
                  -- Terminate burst, begin new read
                  col_addr <= addr(8 downto 0);
                  burst_remaining <= burst_length + cas_latency - 1;
                  state <= READ_WITH_AUTO_PRECHARGE;
                when "1100" | "1101" => -- Burst stop
                  -- Terminate burst, return to ROW_ACTIVE state
                  state <= ROW_ACTIVE;
                  delay_cnt <= 0;
                when "1110" | "1111" => -- No-Operation (NOP)
                  null;
                when others => null;
              end case;
            when WRITE_PLAIN =>
              case cmd is
                when "0000" | "0001" => -- Mode Register Set (MRS)
                  update_mode_register(addr);
                when "0010" | "0011" => -- Self-Refresh ONLY IF CKE has just gone low
                  assert false report "Attempted to trigger refresh during READ";
                when "0100" => -- Precharge select bank
                when "0101" => -- Precharge all banks
                when "0110" | "0111" => -- Bank + row activate
                  assert false report "Attempted to activate row from " & state_t'image(state) & " state";
                when "1000" => -- Write
                  if delay_cnt /= 0 then
                    assert false report "Attempted to write before tRCD had elapsed following ROW_ACTIVE command";
                  end if;
                  do_write_start;
                  if burst_length > 1 then
                    state <= WRITE_PLAIN;
                  end if;
                when "1001" => -- Write with auto-precharge
                  if delay_cnt /= 0 then
                    assert false report "Attempted to write before tRCD had elapsed following ROW_ACTIVE command";
                  end if;
                  do_write_start;
                  if burst_length > 1 then
                    state <= WRITE_WITH_AUTO_PRECHARGE;
                  else
                    state <= PRECHARGING;
                  end if;
                when "1010" => -- Read
                  if delay_cnt /= 0 then
                    assert false report "Attempted to read before tRCD had elapsed following ROW_ACTIVE command";
                  end if;
                  delay_cnt <= cas_latency - 1;
                  col_addr <= addr(8 downto 0);
                  burst_remaining <= burst_length + cas_latency - 1;
                  state <= READ_PLAIN;
                when "1011" => -- Read with auto-precharge
                  if delay_cnt /= 0 then
                    assert false report "Attempted to read before tRCD had elapsed following ROW_ACTIVE command";
                  end if;
                  delay_cnt <= cas_latency - 1;
                  col_addr <= addr(8 downto 0);
                  burst_remaining <= burst_length + cas_latency - 1;
                  state <= READ_WITH_AUTO_PRECHARGE;
                when "1100" | "1101" => -- Burst stop
                  state <= ROW_ACTIVE;
                when "1110" | "1111" => -- No-Operation (NOP)
                  do_write;
                when others => null;
              end case;
            when READ_WITH_AUTO_PRECHARGE =>
              cas_read(0) <= '1';
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
                  assert false report "Attempted to activate row from " & state_t'image(state) & " state";
                when "1000" => -- Write
                when "1001" => -- Write with auto-precharge
                when "1010" => -- Read
                  -- Terminate burst, begin new read
                  col_addr <= addr(8 downto 0);
                  burst_remaining <= burst_length + cas_latency;
                  state <= READ_PLAIN;
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
                  assert false report "Attempted to activate row from " & state_t'image(state) & " state";
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
                  assert false report "Attempted to activate row from " & state_t'image(state) & " state";
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
                  assert false report "Attempted to activate row from " & state_t'image(state) & " state";
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
                  assert false report "Attempted to activate row from " & state_t'image(state) & " state";
                when "1000" => -- Write
                when "1001" => -- Write with auto-precharge
                when "1010" => -- Read
                when "1011" => -- Read with auto-precharge
                when "1100" | "1101" => -- Burst stop
                when "1110" | "1111" => -- No-Operation (NOP)
                when others => null;
              end case;
            when WRITE_RECOVERING_WITH_AUTO_PRECHARGE =>
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
                  assert false report "Attempted to activate row from " & state_t'image(state) & " state";
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
                  assert false report "Attempted to activate row from " & state_t'image(state) & " state";
                when "1000" => -- Write
                when "1001" => -- Write with auto-precharge
                when "1010" => -- Read
                when "1011" => -- Read with auto-precharge
                when "1100" | "1101" => -- Burst stop
                when "1110" | "1111" => -- No-Operation (NOP)
                when others => null;
              end case;
            when MODE_REGISTER_ACCESSING =>
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
                  assert false report "Attempted to activate row from " & state_t'image(state) & " state";
                when "1000" => -- Write
                when "1001" => -- Write with auto-precharge
                when "1010" => -- Read
                when "1011" => -- Read with auto-precharge
                when "1100" | "1101" => -- Burst stop
                when "1110" | "1111" => -- No-Operation (NOP)
                when others => null;
              end case;
          end case;
        end if;
      end if;

    end if;

end process;

end architecture rtl;
