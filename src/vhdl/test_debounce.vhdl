library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity test_debounce is
  generic (intervening_keys : boolean := true);
end entity;

architecture testbench of test_debounce is
  constant clock_period : time := 10 ns;

  type matrix_columns_t is array (0 to 15) of std_logic_vector(7 downto 0);

  signal clk : std_logic := '0';
  signal matrix_columns : matrix_columns_t := (others => x"FF");
  signal matrix_col_idx : integer range 0 to 15 := 0;
  signal matrix_col : std_logic_vector(7 downto 0);
  signal ascii_key : unsigned(7 downto 0);
  signal petscii_key : unsigned(7 downto 0);
  signal bucky_key : std_logic_vector(6 downto 0);
  signal key_valid : std_logic;

  signal a_count : natural := 0;
  signal o_count : natural := 0;
  signal p_count : natural := 0;
  signal q_count : natural := 0;
begin
  clk <= not clk after clock_period / 2;
  matrix_col <= matrix_columns(matrix_col_idx);

  -- matrix_to_ascii snoops an externally scanned matrix, so emulate the
  -- keymapper by continuously presenting all sixteen columns.
  scan_matrix_columns: process(clk)
  begin
    if rising_edge(clk) then
      if matrix_col_idx = 15 then
        matrix_col_idx <= 0;
      else
        matrix_col_idx <= matrix_col_idx + 1;
      end if;
    end if;
  end process;

  dut: entity work.matrix_to_ascii
    generic map (
      -- Scan rapidly compared with the debounce timeout so that each complete
      -- scenario occurs inside one debounce interval.
      scan_frequency => 2500000,
      clock_frequency => 1800000000
      )
    port map (
      clk => clk,
      reset_in => '0',
      matrix_mode_in => '0',
      matrix_disable_modifiers => '0',
      matrix_col => matrix_col,
      matrix_col_idx => matrix_col_idx,
      suppress_key_glitches => '1',
      suppress_key_retrigger => '0',
      key_up => '0',
      key_left => '0',
      key_caps => '1',
      ascii_key => ascii_key,
      petscii_key => petscii_key,
      bucky_key => bucky_key,
      key_valid => key_valid
      );

  count_keys: process(clk)
  begin
    if rising_edge(clk) and key_valid = '1' then
      case ascii_key is
        when x"61" => a_count <= a_count + 1;
        when x"6F" => o_count <= o_count + 1;
        when x"70" => p_count <= p_count + 1;
        when x"71" => q_count <= q_count + 1;
        when others => null;
      end case;
    end if;
  end process;

  stimulus: process
    procedure set_key(
      constant key_number : in natural;
      constant pressed : in boolean) is
      variable column_value : std_logic_vector(7 downto 0);
    begin
      column_value := matrix_columns(key_number / 8);
      if pressed then
        column_value(key_number mod 8) := '0';
      else
        column_value(key_number mod 8) := '1';
      end if;
      matrix_columns(key_number / 8) <= column_value;
    end procedure;

    procedure wait_clocks(constant count : in natural) is
    begin
      for i in 1 to count loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    procedure tap_key(constant key_number : in natural) is
    begin
      set_key(key_number, true);
      wait_clocks(1200);
      set_key(key_number, false);
      wait_clocks(1200);
    end procedure;

    procedure wait_for_key_valid is
    begin
      -- key_valid is deliberately delayed by 1023 key-scan steps.
      wait_clocks(15000);
    end procedure;
  begin
    -- Allow the three internal matrix RAMs to be populated and scanned.
    wait_clocks(2000);

    tap_key(10); -- A
    wait_for_key_valid;

    if intervening_keys then
      -- L and D exercise the buggy history bookkeeping; O is observably
      -- published between the two A events.
      tap_key(42); -- L
      tap_key(38); -- O
      wait_for_key_valid;
      tap_key(18); -- D
    end if;

    tap_key(10); -- A re-strike
    wait_for_key_valid;

    if intervening_keys then
      assert a_count = 1
        report "non-consecutive A re-strike was not debounced; A count="
          & integer'image(a_count)
        severity error;
      assert o_count = 1
        report "no intervening key was published; O count="
          & integer'image(o_count)
        severity error;
    else
      assert a_count = 1
        report "consecutive A re-strike was not debounced; A count="
          & integer'image(a_count)
        severity error;
    end if;

    -- A rejected re-press must not inherit the automatic-repeat timer from
    -- the original accepted press. This models actively tapping a key during
    -- its debounce interval, then happening to hold it when the stale timer
    -- would otherwise expire.
    set_key(62, true); -- Q
    wait_clocks(1200);
    set_key(62, false);
    -- The debounce matrix RAM needs two visits to publish a release.
    wait_clocks(2000);
    set_key(62, true);
    -- The pre-queue implementation delays the accepted event by 1,023 scan
    -- steps. Wait long enough to observe that one event as well as any stale
    -- automatic repeat inherited by the rejected re-press.
    wait_clocks(10000);
    assert q_count = 1
      report "debounced re-press inherited a stale automatic-repeat timer"
      severity error;
    set_key(62, false);
    wait_clocks(1200);

    -- Hold a previously unused key until automatic repeat starts, verifying
    -- that the repeat lifecycle still works after the debounce changes.
    set_key(41, true); -- P
    wait_clocks(15000);
    assert p_count > 1
      report "automatic repeat did not publish another P event"
      severity error;
    set_key(41, false);
    report "matrix_to_ascii debounce test passed" severity note;
    wait;
  end process;
end architecture;
