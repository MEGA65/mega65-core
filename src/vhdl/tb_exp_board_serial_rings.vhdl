library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

library vunit_lib;
context vunit_lib.vunit_context;

entity tb_exp_board_serial_rings is
  generic (runner_cfg : string);
end entity;

architecture test_arch of tb_exp_board_serial_rings is

  signal clock41 : std_logic := '0';
  
  signal exp_clock : std_logic := '0';
  signal exp_latch : std_logic := '0';
  signal exp_wdata : std_logic := '0';
  signal exp_rdata : std_logic;


  signal exp_tick_count : integer := 0;
  signal last_exp_clock : std_logic := '0';
  
  signal fastio_addr : unsigned(19 downto 0) := to_unsigned(0,20);
  signal fastio_rdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal fastio_wdata : unsigned(7 downto 0) := to_unsigned(0,8);
  signal fastio_write : std_logic := '0';
  signal cs : std_logic := '0';

  -- M65 internal signals
  
  -- Tape port
  signal tape_write_o : std_logic;
  signal tape_read_i :  std_logic;
  signal tape_sense_i :  std_logic;
  signal tape_6v_en : std_logic;
  
    -- C1565 port
  signal c1565_serio_i :  std_logic;
  signal c1565_serio_o : std_logic;
  signal c1565_serio_en_n : std_logic;
  signal c1565_clk_o : std_logic;
  signal c1565_ld_o : std_logic;
  signal c1565_rst_o : std_logic;
  
    -- User port
  signal user_d_i : unsigned(7 downto 0);
  signal user_d_o : unsigned(7 downto 0);
  signal user_d_en_n : unsigned(7 downto 0);
  signal user_pa2_i : std_logic;
  signal user_sp1_i : std_logic;
  signal user_cnt2_i : std_logic;
  signal user_sp2_i :  std_logic;
  signal user_pc2_i :  std_logic;
  signal user_flag2_i : std_logic;
  signal user_cnt1_i :  std_logic;
  signal user_pa2_o : std_logic;
  signal user_sp1_o : std_logic;
  signal user_cnt2_o : std_logic;
  signal user_sp2_o :  std_logic;
  signal user_pc2_o :  std_logic;
  signal user_flag2_o : std_logic;
  signal user_cnt1_o :  std_logic;
  signal user_reset_n_i : std_logic;
  signal user_sp1_en_n : std_logic;
  signal user_cnt2_en_n : std_logic;
  signal user_sp2_en_n : std_logic;
  signal user_atn_en_n : std_logic;
  signal user_cnt1_en_n : std_logic;
  signal user_reset_n_en_n : std_logic;

  -- Signals visible on the expansion board
  
  -- Tape port
  signal s_tape_write_o : std_logic;
  signal s_tape_read_i :  std_logic;
  signal s_tape_sense_i :  std_logic;
  signal s_tape_6v_en : std_logic;
  
  -- C1565 port
  signal s_c1565_serio_i :  std_logic;
  signal s_c1565_serio_o : std_logic;
  signal s_c1565_serio_en_n : std_logic;
  signal s_c1565_clk_o : std_logic;
  signal s_c1565_ld_o : std_logic;
  signal s_c1565_rst_o : std_logic;

  -- User port
  signal s_user_d_i : unsigned(7 downto 0);
  signal s_user_d_o : unsigned(7 downto 0);
  signal s_user_d_en_n : unsigned(7 downto 0);
  signal s_user_pa2_i : std_logic;
  signal s_user_sp1_i : std_logic;
  signal s_user_cnt2_i : std_logic;
  signal s_user_sp2_i :  std_logic;
  signal s_user_pc2_i :  std_logic;
  signal s_user_flag2_i : std_logic;
  signal s_user_cnt1_i :  std_logic;
  signal s_user_pa2_o : std_logic;
  signal s_user_sp1_o : std_logic;
  signal s_user_cnt2_o : std_logic;
  signal s_user_sp2_o :  std_logic;
  signal s_user_pc2_o :  std_logic;
  signal s_user_flag2_o : std_logic;
  signal s_user_cnt1_o :  std_logic;
  signal s_user_reset_n_i : std_logic;
  signal s_user_sp1_en_n : std_logic;
  signal s_user_cnt2_en_n : std_logic;
  signal s_user_sp2_en_n : std_logic;
  signal s_user_atn_en_n : std_logic;
  signal s_user_cnt1_en_n : std_logic;
  signal s_user_reset_n_en_n : std_logic;


  -- Remembered / expected signal values
  
  -- Tape port
  signal r_tape_write_o : std_logic;
  signal r_tape_read_i :  std_logic;
  signal r_tape_sense_i :  std_logic;
  signal r_tape_6v_en : std_logic;
  
  -- C1565 port
  signal r_c1565_serio_i :  std_logic;
  signal r_c1565_serio_o : std_logic;
  signal r_c1565_serio_en_n : std_logic;
  signal r_c1565_clk_o : std_logic;
  signal r_c1565_ld_o : std_logic;
  signal r_c1565_rst_o : std_logic;

  -- User port
  signal r_user_d_i : unsigned(7 downto 0);
  signal r_user_d_o : unsigned(7 downto 0);
  signal r_user_d_en_n : unsigned(7 downto 0);
  signal r_user_pa2_i : std_logic;
  signal r_user_sp1_i : std_logic;
  signal r_user_cnt2_i : std_logic;
  signal r_user_sp2_i :  std_logic;
  signal r_user_pc2_i :  std_logic;
  signal r_user_flag2_i : std_logic;
  signal r_user_cnt1_i :  std_logic;
  signal r_user_pa2_o : std_logic;
  signal r_user_sp1_o : std_logic;
  signal r_user_cnt2_o : std_logic;
  signal r_user_sp2_o :  std_logic;
  signal r_user_pc2_o :  std_logic;
  signal r_user_flag2_o : std_logic;
  signal r_user_cnt1_o :  std_logic;
  signal r_user_reset_n_i : std_logic;
  signal r_user_sp1_en_n : std_logic;
  signal r_user_cnt2_en_n : std_logic;
  signal r_user_sp2_en_n : std_logic;
  signal r_user_atn_en_n : std_logic;
  signal r_user_cnt1_en_n : std_logic;
  signal r_user_reset_n_en_n : std_logic;
  
begin

  controller0: entity work.exp_board_ring_ctrl port map (

    -- Master clock
    clock41 => clock41,

    -- Management interface
    cs => cs,
    fastio_rdata => fastio_rdata,
    fastio_wdata => fastio_wdata,
    fastio_addr => fastio_addr,
    fastio_write => fastio_write,

    -- PMOD pins
    exp_clock => exp_clock,
    exp_latch => exp_latch,
    exp_wdata => exp_wdata,
    exp_rdata => exp_rdata,
    
    -- Tape port
    tape_write_o => tape_write_o,
    tape_read_i => tape_read_i,
    tape_sense_i => tape_sense_i,
    tape_6v_en => tape_6v_en,
    
    -- C1565 port
    c1565_serio_i => c1565_serio_i,
    c1565_serio_o => c1565_serio_o,
    c1565_serio_en_n => c1565_serio_en_n,
    c1565_clk_o => c1565_clk_o,
    c1565_ld_o => c1565_ld_o,
    c1565_rst_o => c1565_rst_o,
    
    -- User port
    user_d_i => user_d_i,
    user_d_o => user_d_o,
    user_d_en_n => user_d_en_n,
    user_pa2_i => user_pa2_i,
    user_sp1_i => user_sp1_i,
    user_cnt2_i => user_cnt2_i,
    user_sp2_i => user_sp2_i,
    user_pc2_i => user_pc2_i,
    user_flag2_i => user_flag2_i,
    user_cnt1_i => user_cnt1_i,
    user_reset_n_i => user_reset_n_i,
    user_sp1_en_n => user_sp1_en_n,
    user_cnt2_en_n => user_cnt2_en_n,
    user_sp2_en_n => user_sp2_en_n,
    user_atn_en_n => user_atn_en_n,
    user_cnt1_en_n => user_cnt1_en_n,
    user_reset_n_en_n => user_reset_n_en_n
    
    );
  
  sim_expansion_board0: entity work.sim_exp_board_rings port map (
    -- PMOD pins
    exp_clock => exp_clock,
    exp_latch => exp_latch,
    exp_wdata => exp_wdata,
    exp_rdata => exp_rdata,


    -- Simulated ports have opposite direction sense 
    
    -- Tape port
    tape_write_o => s_tape_write_o,
    tape_read_i => s_tape_read_i,
    tape_sense_i => s_tape_sense_i,
    tape_6v_en => s_tape_6v_en,
    
    -- C1565 port
    c1565_serio_o => s_c1565_serio_o,
    c1565_serio_i => s_c1565_serio_i,
    c1565_serio_en_n => s_c1565_serio_en_n,
    c1565_clk_o => s_c1565_clk_o,
    c1565_ld_o => s_c1565_ld_o,
    c1565_rst_o => s_c1565_rst_o,
    
    -- User port
    user_d_i => s_user_d_i,
    user_d_o => s_user_d_o,
    user_d_en_n => s_user_d_en_n,
    user_pa2_i => s_user_pa2_i,
    user_sp1_i => s_user_sp1_i,
    user_cnt2_i => s_user_cnt2_i,
    user_sp2_i => s_user_sp2_i,
    user_pc2_i => s_user_pc2_i,
    user_flag2_i => s_user_flag2_i,
    user_cnt1_i => s_user_cnt1_i,
    user_reset_n_i => s_user_reset_n_i,
    user_sp1_en_n => s_user_sp1_en_n,
    user_cnt2_en_n => s_user_cnt2_en_n,
    user_sp2_en_n => s_user_sp2_en_n,
    user_atn_en_n => s_user_atn_en_n,
    user_cnt1_en_n => s_user_cnt1_en_n,
    user_reset_n_en => s_user_reset_n_en_n
    );      
  
  main : process

    procedure clock_tick is
    begin
      clock41 <= not clock41;
      wait for 12.5 ns;
    end procedure;

    procedure wait_for_ring_cycle is
    begin
      -- Allow 2 complete cycles of the ring, to ensure that at least one full
      -- ring cycle has occurred, allowing data to propagate
      for i in 1 to 32*10*2 loop
        clock_tick;
      end loop;
    end procedure;

    procedure remember_current_signals is
    begin
    end procedure;

    procedure compare_with_remembered_signals is
    begin
      if s_tape_write_o /= r_tape_write_o then
        assert false report "TAPE_WRITTE on expansion board value incorrect: Saw " & std_logic'image(s_tape_write_o) & ", but expected " & std_logic'image(r_tape_write_o);
      end if;
      if s_tape_write_o /= r_tape_write_o then
        assert false report "tape_write_o on expansion board value incorrect: Saw " & std_logic'image(s_tape_write_o) & ", but expected " & std_logic'image(r_tape_write_o);
      end if;
      if s_tape_read_i /= r_tape_read_i then
        assert false report "tape_read_i on expansion board value incorrect: Saw " & std_logic'image(s_tape_read_i) & ", but expected " & std_logic'image(r_tape_read_i);
      end if;
      if s_tape_sense_i /= r_tape_sense_i then
        assert false report "tape_sense_i on expansion board value incorrect: Saw " & std_logic'image(s_tape_sense_i) & ", but expected " & std_logic'image(r_tape_sense_i);
      end if;
      if s_tape_6v_en /= r_tape_6v_en then
        assert false report "tape_6v_en on expansion board value incorrect: Saw " & std_logic'image(s_tape_6v_en) & ", but expected " & std_logic'image(r_tape_6v_en);
      end if;
      if s_c1565_serio_i /= r_c1565_serio_i then
        assert false report "c1565_serio_i on expansion board value incorrect: Saw " & std_logic'image(s_c1565_serio_i) & ", but expected " & std_logic'image(r_c1565_serio_i);
      end if;
      if s_c1565_serio_o /= r_c1565_serio_o then
        assert false report "c1565_serio_o on expansion board value incorrect: Saw " & std_logic'image(s_c1565_serio_o) & ", but expected " & std_logic'image(r_c1565_serio_o);
      end if;
      if s_c1565_serio_en_n /= r_c1565_serio_en_n then
        assert false report "c1565_serio_en_n on expansion board value incorrect: Saw " & std_logic'image(s_c1565_serio_en_n) & ", but expected " & std_logic'image(r_c1565_serio_en_n);
      end if;
      if s_c1565_clk_o /= r_c1565_clk_o then
        assert false report "c1565_clk_o on expansion board value incorrect: Saw " & std_logic'image(s_c1565_clk_o) & ", but expected " & std_logic'image(r_c1565_clk_o);
      end if;
      if s_c1565_ld_o /= r_c1565_ld_o then
        assert false report "c1565_ld_o on expansion board value incorrect: Saw " & std_logic'image(s_c1565_ld_o) & ", but expected " & std_logic'image(r_c1565_ld_o);
      end if;
      if s_c1565_rst_o /= r_c1565_rst_o then
        assert false report "c1565_rst_o on expansion board value incorrect: Saw " & std_logic'image(s_c1565_rst_o) & ", but expected " & std_logic'image(r_c1565_rst_o);
      end if;
      if s_user_d_i /= r_user_d_i then
        assert false report "user_d_i on expansion board value incorrect: Saw " & to_string(s_user_d_i) & ", but expected " & to_string(r_user_d_i);
      end if;
      if s_user_d_o /= r_user_d_o then
        assert false report "user_d_o on expansion board value incorrect: Saw " & to_string(s_user_d_o) & ", but expected " & to_string(r_user_d_o);
      end if;
      if s_user_d_en_n /= r_user_d_en_n then
        assert false report "user_d_en_n on expansion board value incorrect: Saw " & to_string(s_user_d_en_n) & ", but expected " & to_string(r_user_d_en_n);
      end if;
      if s_user_pa2_i /= r_user_pa2_i then
        assert false report "user_pa2_i on expansion board value incorrect: Saw " & std_logic'image(s_user_pa2_i) & ", but expected " & std_logic'image(r_user_pa2_i);
      end if;
      if s_user_sp1_i /= r_user_sp1_i then
        assert false report "user_sp1_i on expansion board value incorrect: Saw " & std_logic'image(s_user_sp1_i) & ", but expected " & std_logic'image(r_user_sp1_i);
      end if;
      if s_user_cnt2_i /= r_user_cnt2_i then
        assert false report "user_cnt2_i on expansion board value incorrect: Saw " & std_logic'image(s_user_cnt2_i) & ", but expected " & std_logic'image(r_user_cnt2_i);
      end if;
      if s_user_sp2_i /= r_user_sp2_i then
        assert false report "user_sp2_i on expansion board value incorrect: Saw " & std_logic'image(s_user_sp2_i) & ", but expected " & std_logic'image(r_user_sp2_i);
      end if;
      if s_user_pc2_i /= r_user_pc2_i then
        assert false report "user_pc2_i on expansion board value incorrect: Saw " & std_logic'image(s_user_pc2_i) & ", but expected " & std_logic'image(r_user_pc2_i);
      end if;
      if s_user_flag2_i /= r_user_flag2_i then
        assert false report "user_flag2_i on expansion board value incorrect: Saw " & std_logic'image(s_user_flag2_i) & ", but expected " & std_logic'image(r_user_flag2_i);
      end if;
      if s_user_cnt1_i /= r_user_cnt1_i then
        assert false report "user_cnt1_i on expansion board value incorrect: Saw " & std_logic'image(s_user_cnt1_i) & ", but expected " & std_logic'image(r_user_cnt1_i);
      end if;
      if s_user_pa2_o /= r_user_pa2_o then
        assert false report "user_pa2_o on expansion board value incorrect: Saw " & std_logic'image(s_user_pa2_o) & ", but expected " & std_logic'image(r_user_pa2_o);
      end if;
      if s_user_sp1_o /= r_user_sp1_o then
        assert false report "user_sp1_o on expansion board value incorrect: Saw " & std_logic'image(s_user_sp1_o) & ", but expected " & std_logic'image(r_user_sp1_o);
      end if;
      if s_user_cnt2_o /= r_user_cnt2_o then
        assert false report "user_cnt2_o on expansion board value incorrect: Saw " & std_logic'image(s_user_cnt2_o) & ", but expected " & std_logic'image(r_user_cnt2_o);
      end if;
      if s_user_sp2_o /= r_user_sp2_o then
        assert false report "user_sp2_o on expansion board value incorrect: Saw " & std_logic'image(s_user_sp2_o) & ", but expected " & std_logic'image(r_user_sp2_o);
      end if;
      if s_user_pc2_o /= r_user_pc2_o then
        assert false report "user_pc2_o on expansion board value incorrect: Saw " & std_logic'image(s_user_pc2_o) & ", but expected " & std_logic'image(r_user_pc2_o);
      end if;
      if s_user_flag2_o /= r_user_flag2_o then
        assert false report "user_flag2_o on expansion board value incorrect: Saw " & std_logic'image(s_user_flag2_o) & ", but expected " & std_logic'image(r_user_flag2_o);
      end if;
      if s_user_cnt1_o /= r_user_cnt1_o then
        assert false report "user_cnt1_o on expansion board value incorrect: Saw " & std_logic'image(s_user_cnt1_o) & ", but expected " & std_logic'image(r_user_cnt1_o);
      end if;
      if s_user_reset_n_i /= r_user_reset_n_i then
        assert false report "user_reset_n_i on expansion board value incorrect: Saw " & std_logic'image(s_user_reset_n_i) & ", but expected " & std_logic'image(r_user_reset_n_i);
      end if;
      if s_user_sp1_en_n /= r_user_sp1_en_n then
        assert false report "user_sp1_en_n on expansion board value incorrect: Saw " & std_logic'image(s_user_sp1_en_n) & ", but expected " & std_logic'image(r_user_sp1_en_n);
      end if;
      if s_user_cnt2_en_n /= r_user_cnt2_en_n then
        assert false report "user_cnt2_en_n on expansion board value incorrect: Saw " & std_logic'image(s_user_cnt2_en_n) & ", but expected " & std_logic'image(r_user_cnt2_en_n);
      end if;
      if s_user_sp2_en_n /= r_user_sp2_en_n then
        assert false report "user_sp2_en_n on expansion board value incorrect: Saw " & std_logic'image(s_user_sp2_en_n) & ", but expected " & std_logic'image(r_user_sp2_en_n);
      end if;
      if s_user_atn_en_n /= r_user_atn_en_n then
        assert false report "user_atn_en_n on expansion board value incorrect: Saw " & std_logic'image(s_user_atn_en_n) & ", but expected " & std_logic'image(r_user_atn_en_n);
      end if;
      if s_user_cnt1_en_n /= r_user_cnt1_en_n then
        assert false report "user_cnt1_en_n on expansion board value incorrect: Saw " & std_logic'image(s_user_cnt1_en_n) & ", but expected " & std_logic'image(r_user_cnt1_en_n);
      end if;
      if s_user_reset_n_en_n /= r_user_reset_n_en_n then
        assert false report "user_reset_n_en_n on expansion board value incorrect: Saw " & std_logic'image(s_user_reset_n_en_n) & ", but expected " & std_logic'image(r_user_reset_n_en_n);
      end if;
      
    end procedure;
    

  begin
    test_runner_setup(runner, runner_cfg);    
    
    while test_suite loop

      if run("EXP_CLOCK ticks") then
        for i in 1 to 1000 loop
          clock_tick;
          if exp_clock /= last_exp_clock then
            last_exp_clock <= exp_clock;
            exp_tick_count <= exp_tick_count + 1;
          end if;
        end loop;
        if exp_tick_count = 0 then
          assert false report "EXP_CLOCK did not tick";
        else
          report "Saw " & integer'image(exp_tick_count) & " edges on EXP_CLOCK";
        end if;
      elsif run("EXP_LATCH is asserted") then
        for i in 1 to 32*60 loop
          clock_tick;
          if exp_latch = '1' then
            exp_tick_count <= exp_tick_count + 1;
          end if;
        end loop;

        -- Check that EXP_LATCH gets asserted
        if exp_tick_count = 0 then
          assert false report "EXP_LATCH was never asserted";
        end if;
        report "Saw " & integer'image(exp_tick_count) & " cycles with EXP_LATCH asserted";

        -- Check that it is asserted at the correct duty-cycle = 1/32
        if exp_tick_count /= 60 then
          assert false report "Expected EXP_LATCH to be asserted 1/32 of the time, i.e., 60 cycles";
        end if;
      elsif run("TAPE_WRITE is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals; r_tape_write_o <= '0';
        tape_write_o <= '0'; wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals; r_tape_write_o <= '1';
        tape_write_o <= '1'; wait_for_ring_cycle;
        compare_with_remembered_signals;
      end if;
    end loop;
    test_runner_cleanup(runner);
  end process;

end architecture;