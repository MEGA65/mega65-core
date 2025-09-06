library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity scart_cable_detect is
  port (
    clock_in              : in  std_logic;           -- 40.5 MHz
    reset_n               : in  std_logic;           -- active-low, synchronous

    vga12                 : inout std_logic;         -- SDA (open-drain, external PU)
    vga15                 : inout std_logic;         -- SCL (open-drain, external PU)

    scart_cable_detected  : out std_logic
  );
end entity;

architecture rtl of scart_cable_detect is
  -- Timing at 40.5 MHz
  constant CLK_HZ          : integer := 40500000;
  constant PULSE_CYCLES    : integer := CLK_HZ / 10000;   -- 100 us  ->  4050
  constant FOLLOW_CYCLES   : integer := CLK_HZ / 100000;  -- 10 us   ->   405
  constant RECOVER_CYCLES  : integer := CLK_HZ / 100000;  -- 10 us   ->   405
  constant PERIOD_CYCLES   : integer := CLK_HZ / 100;     -- 10 ms   -> 405000

  -- Open-drain drivers: drive '0' or tri-state 'Z'
  signal drv12_low, drv15_low : std_logic := '0';

  -- Read-back + sync for inouts
  signal vga12_in_a, vga15_in_a : std_logic;
  signal vga12_in,  vga15_in    : std_logic := '1';
  signal s12_d1, s12_d2, s15_d1, s15_d2 : std_logic := '1';

  -- Period timer and state machine
  type state_t is (IDLE, T15_ASSERT, T15_RELEASE, T12_ASSERT, T12_RELEASE);
  signal state      : state_t := IDLE;
  signal state_init : boolean := false;

  signal period_cnt   : integer range 0 to PERIOD_CYCLES := 0;

  -- Per-phase counters/flags
  signal pulse_cnt    : integer range 0 to PULSE_CYCLES := 0;
  signal follow_cnt   : integer range 0 to FOLLOW_CYCLES := 0;
  signal recover_cnt  : integer range 0 to RECOVER_CYCLES := 0;

  signal followed     : boolean := false;
  signal hold_failed  : boolean := false;
  signal recovered_hi : boolean := false;

  -- Probe outcome / hysteresis (2 consecutive misses to deassert)
  signal probe_ok     : boolean := false;
  signal miss_count   : integer range 0 to 2 := 2;  -- start at 2 => output low until first success
begin
  -- Open-drain outputs
  vga12 <= '0' when drv12_low = '1' else 'Z';
  vga15 <= '0' when drv15_low = '1' else 'Z';

  -- Async readbacks
  vga12_in_a <= vga12;
  vga15_in_a <= vga15;

  -- 2-FF synchronizers
  sync_inputs : process(clock_in)
  begin
    if rising_edge(clock_in) then
      s12_d1 <= vga12_in_a; s12_d2 <= s12_d1; vga12_in <= s12_d2;
      s15_d1 <= vga15_in_a; s15_d2 <= s15_d1; vga15_in <= s15_d2;
    end if;
  end process;

  -- Main FSM
  fsm : process(clock_in)
  begin
    if rising_edge(clock_in) then
      if reset_n = '0' then
        state         <= IDLE;
        state_init    <= false;
        drv12_low     <= '0';
        drv15_low     <= '0';
        period_cnt    <= 0;
        pulse_cnt     <= 0;
        follow_cnt    <= 0;
        recover_cnt   <= 0;
        followed      <= false;
        hold_failed   <= false;
        recovered_hi  <= false;
        probe_ok      <= false;
        miss_count    <= 2;
      else
        -- free-run 10 ms period counter
        if period_cnt > 0 then
          period_cnt <= period_cnt - 1;
        end if;

        case state is
          when IDLE =>
            drv12_low <= '0';
            drv15_low <= '0';
            if not state_init then
              state_init <= true;
            end if;

            -- Start new probe on 10 ms tick
            if period_cnt = 0 then
              period_cnt   <= PERIOD_CYCLES;     -- latch next 10 ms window
              probe_ok     <= true;              -- assume pass until proven otherwise
              state        <= T15_ASSERT;
              state_init   <= false;
            end if;

          when T15_ASSERT =>
            if not state_init then
              -- set up: drive vga15 low, watch vga12
              drv15_low   <= '1';
              pulse_cnt   <= PULSE_CYCLES;
              follow_cnt  <= FOLLOW_CYCLES;
              followed    <= false;
              hold_failed <= false;
              state_init  <= true;
            else
              -- check for follow within 10 us
              if (not followed) then
                if vga12_in = '0' then
                  followed <= true;
                elsif follow_cnt = 0 then
                  probe_ok <= false;  -- failed to follow in time
                else
                  follow_cnt <= follow_cnt - 1;
                end if;
              else
                -- once followed, must hold low until release
                if vga12_in = '1' then
                  hold_failed <= true;
                  probe_ok    <= false;
                end if;
              end if;

              -- end of 100 us low pulse
              if pulse_cnt = 0 then
                state       <= T15_RELEASE;
                state_init  <= false;
              else
                pulse_cnt <= pulse_cnt - 1;
              end if;
            end if;

          when T15_RELEASE =>
            if not state_init then
              drv15_low    <= '0';                 -- release (Hi-Z)
              recover_cnt  <= RECOVER_CYCLES;      -- both lines should return HIGH within 10 us
              recovered_hi <= false;
              state_init   <= true;
            else
              if (vga15_in = '1') and (vga12_in = '1') then
                recovered_hi <= true;
              end if;

              if recover_cnt = 0 then
                if not recovered_hi then
                  probe_ok <= false;               -- failed to float back high
                end if;
                state      <= T12_ASSERT;          -- now the other direction
                state_init <= false;
              else
                recover_cnt <= recover_cnt - 1;
              end if;
            end if;

          when T12_ASSERT =>
            if not state_init then
              drv12_low   <= '1';
              pulse_cnt   <= PULSE_CYCLES;
              follow_cnt  <= FOLLOW_CYCLES;
              followed    <= false;
              hold_failed <= false;
              state_init  <= true;
            else
              if (not followed) then
                if vga15_in = '0' then
                  followed <= true;
                elsif follow_cnt = 0 then
                  probe_ok <= false;
                else
                  follow_cnt <= follow_cnt - 1;
                end if;
              else
                if vga15_in = '1' then
                  hold_failed <= true;
                  probe_ok    <= false;
                end if;
              end if;

              if pulse_cnt = 0 then
                state      <= T12_RELEASE;
                state_init <= false;
              else
                pulse_cnt <= pulse_cnt - 1;
              end if;
            end if;

          when T12_RELEASE =>
            if not state_init then
              drv12_low    <= '0';
              recover_cnt  <= RECOVER_CYCLES;
              recovered_hi <= false;
              state_init   <= true;
            else
              if (vga12_in = '1') and (vga15_in = '1') then
                recovered_hi <= true;
              end if;

              if recover_cnt = 0 then
                if not recovered_hi then
                  probe_ok <= false;
                end if;

                -- finalize this probe (both directions done)
                if probe_ok = true then
                  miss_count <= 0;
                elsif miss_count < 2 then
                  miss_count <= miss_count + 1;
                end if;

                state      <= IDLE;     -- release lines for the remainder of the 10 ms window
                state_init <= false;
              else
                recover_cnt <= recover_cnt - 1;
              end if;
            end if;
        end case;
      end if;
    end if;
  end process;

  -- 2-miss hysteresis on the status output
  scart_cable_detected <= '0' when (miss_count = 2) else '1';

end architecture;
