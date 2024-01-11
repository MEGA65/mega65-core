library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;
use work.porttypes.all;

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
  signal tape_i : tape_port_in;
  signal tape_o : tape_port_out;
  
  -- C1565 port
  signal c1565_i : c1565_port_in;
  signal c1565_o : c1565_port_out;
  
  -- User port
  signal user_i : user_port_in;
  signal user_o : user_port_out;

  -- Signals visible on the expansion board
  
  -- Tape port
  signal s_tape_i : tape_port_in;
  signal s_tape_o : tape_port_out;
  
  -- C1565 port
  signal s_c1565_i : c1565_port_in;
  signal s_c1565_o : c1565_port_out;

  -- User port
  signal s_user_i : user_port_in;
  signal s_user_o : user_port_out;

  -- Remembered / expected signal values
  
  -- Tape port
  signal r_tape_o : tape_port_out;
  signal r_tape_i : tape_port_in;
  
  -- C1565 port
  signal r_c1565_i : c1565_port_in;
  signal r_c1565_o : c1565_port_out;

  -- User port
  signal r_user_i : user_port_in;
  signal r_user_o : user_port_out;
  
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
    tape_o => tape_o,
    tape_i => tape_i,
    
    -- C1565 port
    c1565_i => c1565_i,
    c1565_o => c1565_o,
    
    -- User port
    user_i => user_i,
    user_o => user_o
    
    );
  
  sim_expansion_board0: entity work.sim_exp_board_rings port map (
    -- PMOD pins
    exp_clock => exp_clock,
    exp_latch => exp_latch,
    exp_wdata => exp_wdata,
    exp_rdata => exp_rdata,


    -- Simulated ports have opposite direction sense 
    
    -- Tape port
    tape_o => s_tape_o,
    tape_i => s_tape_i,
    
    -- C1565 port
    c1565_i => s_c1565_i,
    c1565_o => s_c1565_o,
    
    -- User port
    user_i => s_user_i,
    user_o => s_user_o

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
      -- 2 ticks per clock41 tick.
      -- 5 clock41 ticks per half-clock of EXP_CLOCK
      -- 2 half-ticks of EXP_CLOCK per full tick of EXP_CLOCK
      -- 32 ticks of EXP_CLOCK for one ring cycle
      -- 2 ring cycles, to be sure
      -- Then add 10 cycles extra, just to be totally sure.
      for i in 1 to 2*5*2*32*2 + 1000 loop
        clock_tick;
      end loop;
    end procedure;

    procedure remember_current_signals is
    begin
      -- Tape port
      r_tape_o.write <= tape_o.write;
      r_tape_i.read <= tape_i.read;
      r_tape_i.sense <= tape_i.sense;
      r_tape_o.motor_en <= tape_o.motor_en;
  
      -- C1565 port
      r_c1565_i <= c1565_i;
      r_c1565_o <= s_c1565_o;

      -- User port
      r_user_i <= user_i;
      r_user_o <= user_o;
      
    end procedure;

    function to_str(signal vec: std_logic_vector) return string is
      variable result: string(1 to vec'length);
    begin
      for i in vec'range loop
        case vec(vec'length-1-i) is
          when 'U' => result(i) := 'U';
          when 'X' => result(i) := 'X';
          when '0' => result(i) := '0';
          when '1' => result(i) := '1';
          when 'Z' => result(i) := 'Z';
          when 'W' => result(i) := 'W';
          when 'L' => result(i) := 'L';
          when 'H' => result(i) := 'H';
          when '-' => result(i) := '-';
          when others => result(i) := '?';
        end case;
      end loop;
      return result;
    end to_str;

    
    procedure compare_with_remembered_signals is
      variable errors : integer := 0;
    begin
      if s_tape_o.write /= r_tape_o.write then
        report "tape_o.write on expansion board value incorrect: Saw " & std_logic'image(s_tape_o.write) & ", but expected " & std_logic'image(r_tape_o.write);
        errors := errors + 1;
      end if;
      if tape_i.read /= r_tape_i.read then
        report "tape_i.read on expansion board value incorrect: Saw " & std_logic'image(tape_i.read) & ", but expected " & std_logic'image(r_tape_i.read);
        errors := errors + 1;
      end if;
      if tape_i.sense /= r_tape_i.sense then
        report "tape_i.sense on expansion board value incorrect: Saw " & std_logic'image(tape_i.sense) & ", but expected " & std_logic'image(r_tape_i.sense);
        errors := errors + 1;
      end if;
      if s_tape_o.motor_en /= r_tape_o.motor_en then
        report "tape_o.motor_en on expansion board value incorrect: Saw " & std_logic'image(s_tape_o.motor_en) & ", but expected " & std_logic'image(r_tape_o.motor_en);
        errors := errors + 1;
      end if;
      if c1565_i.serio /= r_c1565_i.serio then
        report "c1565_i.serio on expansion board value incorrect: Saw " & std_logic'image(c1565_i.serio) & ", but expected " & std_logic'image(r_c1565_i.serio);
        errors := errors + 1;
      end if;
      if s_c1565_o.serio /= r_c1565_o.serio then
        report "c1565_o.serio on expansion board value incorrect: Saw " & std_logic'image(s_c1565_o.serio) & ", but expected " & std_logic'image(r_c1565_o.serio);
        errors := errors + 1;
      end if;
      if s_c1565_o.serio_en_n /= r_c1565_o.serio_en_n then
        report "c1565_o.serio_en_n on expansion board value incorrect: Saw " & std_logic'image(s_c1565_o.serio_en_n) & ", but expected " & std_logic'image(r_c1565_o.serio_en_n);
        errors := errors + 1;
      end if;
      if s_c1565_o.clk /= r_c1565_o.clk then
        report "c1565_o.clk on expansion board value incorrect: Saw " & std_logic'image(s_c1565_o.clk) & ", but expected " & std_logic'image(r_c1565_o.clk);
        errors := errors + 1;
      end if;
      if s_c1565_o.ld /= r_c1565_o.ld then
        report "c1565_o.ld on expansion board value incorrect: Saw " & std_logic'image(s_c1565_o.ld) & ", but expected " & std_logic'image(r_c1565_o.ld);
        errors := errors + 1;
      end if;
      if s_c1565_o.rst /= r_c1565_o.rst then
        report "c1565_o.rst on expansion board value incorrect: Saw " & std_logic'image(s_c1565_o.rst) & ", but expected " & std_logic'image(r_c1565_o.rst);
        errors := errors + 1;
      end if;
      for i in 0 to 7 loop
        if user_i.d(i) /= r_user_i.d(i) then
          report "user_i.d("&integer'image(i)&") on expansion board value incorrect: Saw " & to_string(user_i.d(i)) & ", but expected " & to_string(r_user_i.d(i));
          errors := errors + 1;
        end if;
      end loop;
      for i in 0 to 7 loop
        if s_user_o.d(i) /= r_user_o.d(i) then
          report "user_o.d("&integer'image(i)&") on expansion board value incorrect: Saw " & to_string(s_user_o.d(i)) & ", but expected " & to_string(r_user_o.d(i));
          errors := errors + 1;
        end if;
      end loop;
      for i in 0 to 7 loop
        if s_user_o.d_en_n(i) /= r_user_o.d_en_n(i) then
          report "user_o.d_en_n("&integer'image(i)&") on expansion board value incorrect: Saw " & to_string(s_user_o.d_en_n(i)) & ", but expected " & to_string(r_user_o.d_en_n(i));
          errors := errors + 1;
        end if;
      end loop;
      if user_i.pa2 /= r_user_i.pa2 then
        report "user_i.pa2 on expansion board value incorrect: Saw " & std_logic'image(user_i.pa2) & ", but expected " & std_logic'image(r_user_i.pa2);
        errors := errors + 1;
      end if;
      if user_i.sp1 /= r_user_i.sp1 then
        report "user_i.sp1 on expansion board value incorrect: Saw " & std_logic'image(user_i.sp1) & ", but expected " & std_logic'image(r_user_i.sp1);
        errors := errors + 1;
      end if;
      if user_i.cnt2 /= r_user_i.cnt2 then
        report "user_i.cnt2 on expansion board value incorrect: Saw " & std_logic'image(user_i.cnt2) & ", but expected " & std_logic'image(r_user_i.cnt2);
        errors := errors + 1;
      end if;
      if user_i.sp2 /= r_user_i.sp2 then
        report "user_i.sp2 on expansion board value incorrect: Saw " & std_logic'image(user_i.sp2) & ", but expected " & std_logic'image(r_user_i.sp2);
        errors := errors + 1;
      end if;
      if user_i.pc2 /= r_user_i.pc2 then
        report "user_i.pc2 on expansion board value incorrect: Saw " & std_logic'image(user_i.pc2) & ", but expected " & std_logic'image(r_user_i.pc2);
        errors := errors + 1;
      end if;
      if user_i.flag2 /= r_user_i.flag2 then
        report "user_i.flag2 on expansion board value incorrect: Saw " & std_logic'image(user_i.flag2) & ", but expected " & std_logic'image(r_user_i.flag2);
        errors := errors + 1;
      end if;
      if user_i.cnt1 /= r_user_i.cnt1 then
        report "user_i.cnt1 on expansion board value incorrect: Saw " & std_logic'image(user_i.cnt1) & ", but expected " & std_logic'image(r_user_i.cnt1);
        errors := errors + 1;
      end if;
      if s_user_o.pa2 /= r_user_o.pa2 then
        report "user_o.pa2 on expansion board value incorrect: Saw " & std_logic'image(s_user_o.pa2) & ", but expected " & std_logic'image(r_user_o.pa2);
        errors := errors + 1;
      end if;
      if s_user_o.sp1 /= r_user_o.sp1 then
        report "user_o.sp1 on expansion board value incorrect: Saw " & std_logic'image(s_user_o.sp1) & ", but expected " & std_logic'image(r_user_o.sp1);
        errors := errors + 1;
      end if;
      if s_user_o.cnt2 /= r_user_o.cnt2 then
        report "user_o.cnt2 on expansion board value incorrect: Saw " & std_logic'image(s_user_o.cnt2) & ", but expected " & std_logic'image(r_user_o.cnt2);
        errors := errors + 1;
      end if;
      if s_user_o.sp2 /= r_user_o.sp2 then
        report "user_o.sp2 on expansion board value incorrect: Saw " & std_logic'image(s_user_o.sp2) & ", but expected " & std_logic'image(r_user_o.sp2);
        errors := errors + 1;
      end if;
      if s_user_o.pc2 /= r_user_o.pc2 then
        report "user_o.pc2 on expansion board value incorrect: Saw " & std_logic'image(s_user_o.pc2) & ", but expected " & std_logic'image(r_user_o.pc2);
        errors := errors + 1;
      end if;
      if s_user_o.cnt1 /= r_user_o.cnt1 then
        report "user_o.cnt1 on expansion board value incorrect: Saw " & std_logic'image(s_user_o.cnt1) & ", but expected " & std_logic'image(r_user_o.cnt1);
        errors := errors + 1;
      end if;
      if user_i.reset_n /= r_user_i.reset_n then
        report "user_i.reset_n on expansion board value incorrect: Saw " & std_logic'image(user_i.reset_n) & ", but expected " & std_logic'image(r_user_i.reset_n);
        errors := errors + 1;
      end if;

      if s_user_o.atn_en_n /= r_user_o.atn_en_n then
        report "user_o.atn_en_n on expansion board value incorrect: Saw " & std_logic'image(s_user_o.atn_en_n) & ", but expected " & std_logic'image(r_user_o.atn_en_n);
        errors := errors + 1;
      end if;

      if s_user_o.reset_n /= r_user_o.reset_n then
        report "user_o.reset_n on expansion board value incorrect: Saw " & std_logic'image(s_user_o.reset_n) & ", but expected " & std_logic'image(r_user_o.reset_n);
        errors := errors + 1;
      end if;

      if errors /= 0 then
        assert false report integer'image(errors) & " signals did not have the expected value.";
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
        for i in 1 to 2*5*2*32*2 + 1000 loop
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

      elsif run("TAPE_WRITE is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_tape_o.write <= '0'; tape_o.write <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_tape_o.write <= '1'; tape_o.write <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("DATA outputs are correctly conveyed") then

        for i in 0 to 7 loop
          wait_for_ring_cycle;

          remember_current_signals;
          r_user_o.d(i) <= '0'; user_o.d(i) <= '0';
          wait_for_ring_cycle;
          compare_with_remembered_signals;
        
          remember_current_signals;
          r_user_o.d(i) <= '1'; user_o.d(i) <= '1';
          wait_for_ring_cycle;
          compare_with_remembered_signals;
        end loop;
        
      elsif run("DATA output enables are correctly conveyed") then
        wait_for_ring_cycle;

        for i in 0 to 7 loop
          report "TEST: Pull data output enable " & integer'image(i) & " low.";
          
          remember_current_signals;
          r_user_o.d_en_n(i) <= '0'; user_o.d_en_n(i) <= '0';
          wait_for_ring_cycle;
          compare_with_remembered_signals;
        
          report "TEST: Set data output enable " & integer'image(i) & " high";

          remember_current_signals;
          r_user_o.d_en_n(i) <= '1'; user_o.d_en_n(i) <= '1';
          wait_for_ring_cycle;
          compare_with_remembered_signals;
        end loop;
      elsif run("tape_o.motor_en is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_tape_o.motor_en <= '0'; tape_o.motor_en <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_tape_o.motor_en <= '1'; tape_o.motor_en <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("c1565_o.serio is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_c1565_o.serio <= '0'; c1565_o.serio <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_c1565_o.serio <= '1'; c1565_o.serio <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("c1565_o.serio_en_n is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_c1565_o.serio_en_n <= '0'; c1565_o.serio_en_n <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_c1565_o.serio_en_n <= '1'; c1565_o.serio_en_n <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("c1565_o.clk is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_c1565_o.clk <= '0'; c1565_o.clk <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_c1565_o.clk <= '1'; c1565_o.clk <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("c1565_o.ld is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_c1565_o.ld <= '0'; c1565_o.ld <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_c1565_o.ld <= '1'; c1565_o.ld <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("c1565_o.rst is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_c1565_o.rst <= '0'; c1565_o.rst <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_c1565_o.rst <= '1'; c1565_o.rst <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_o.pa2 is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_o.pa2 <= '0'; user_o.pa2 <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_o.pa2 <= '1'; user_o.pa2 <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_o.sp1 is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_o.sp1 <= '0'; user_o.sp1 <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_o.sp1 <= '1'; user_o.sp1 <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_o.cnt2 is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_o.cnt2 <= '0'; user_o.cnt2 <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_o.cnt2 <= '1'; user_o.cnt2 <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_o.sp2 is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_o.sp2 <= '0'; user_o.sp2 <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_o.sp2 <= '1'; user_o.sp2 <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_o.pc2 is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_o.pc2 <= '0'; user_o.pc2 <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_o.pc2 <= '1'; user_o.pc2 <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_o.cnt1 is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_o.cnt1 <= '0'; user_o.cnt1 <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_o.cnt1 <= '1'; user_o.cnt1 <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_o.atn_en_n is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_o.atn_en_n <= '0'; user_o.atn_en_n <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_o.atn_en_n <= '1'; user_o.atn_en_n <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_o.reset_n is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_o.reset_n <= '0'; user_o.reset_n <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_o.reset_n <= '1'; user_o.reset_n <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        

      elsif run("tape_i.read is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_tape_i.read <= '0'; s_tape_i.read <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_tape_i.read <= '1'; s_tape_i.read <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("tape_i.sense is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_tape_i.sense <= '0'; s_tape_i.sense <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_tape_i.sense <= '1'; s_tape_i.sense <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("c1565_serio_i is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_c1565_i.serio <= '0'; s_c1565_i.serio <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_c1565_i.serio <= '1'; s_c1565_i.serio <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_i.d is correctly conveyed") then

        for i in 0 to 7 loop
          wait_for_ring_cycle;

          remember_current_signals;
          r_user_i.d(i) <= '0'; s_user_i.d(i) <= '0';
          wait_for_ring_cycle;
          compare_with_remembered_signals;
        
          remember_current_signals;
          r_user_i.d(i) <= '1'; s_user_i.d(i) <= '1';
          wait_for_ring_cycle;
          compare_with_remembered_signals;
        end loop;
        
      elsif run("user_i.pa2 is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_i.pa2 <= '0'; s_user_i.pa2 <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_i.pa2 <= '1'; s_user_i.pa2 <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_i.sp1 is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_i.sp1 <= '0'; s_user_i.sp1 <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_i.sp1 <= '1'; s_user_i.sp1 <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_i.cnt2 is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_i.cnt2 <= '0'; s_user_i.cnt2 <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_i.cnt2 <= '1'; s_user_i.cnt2 <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_i.sp2 is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_i.sp2 <= '0'; s_user_i.sp2 <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_i.sp2 <= '1'; s_user_i.sp2 <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_i.pc2 is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_i.pc2 <= '0'; s_user_i.pc2 <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_i.pc2 <= '1'; s_user_i.pc2 <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_i.flag2 is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_i.flag2 <= '0'; s_user_i.flag2 <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_i.flag2 <= '1'; s_user_i.flag2 <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_i.cnt1 is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_i.cnt1 <= '0'; s_user_i.cnt1 <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_i.cnt1 <= '1'; s_user_i.cnt1 <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
      elsif run("user_i.reset_n is correctly conveyed") then
        wait_for_ring_cycle;

        remember_current_signals;
        r_user_i.reset_n <= '0'; s_user_i.reset_n <= '0';
        wait_for_ring_cycle;
        compare_with_remembered_signals;
        
        remember_current_signals;
        r_user_i.reset_n <= '1'; s_user_i.reset_n <= '1';
        wait_for_ring_cycle;
        compare_with_remembered_signals;        
                                        
      end if;
    end loop;
    test_runner_cleanup(runner);
  end process;

end architecture;
