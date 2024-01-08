use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity sim_exp_board_rings is
  port (
    -- PMOD pins
    exp_clock : in std_logic;
    exp_latch : in std_logic;
    exp_wdata : in std_logic;
    exp_rdata : out std_logic;
    
    -- Tape port
    tape_write_o : out std_logic;
    tape_read_i : in std_logic;
    tape_sense_i : in std_logic;
    tape_6v_en : out std_logic;
    
    -- C1565 port
    c1565_serio_i : in std_logic;
    c1565_serio_o : out std_logic;
    c1565_serio_en_n : out std_logic;
    c1565_clk_o : out std_logic;
    c1565_ld_o : out std_logic;
    c1565_rst_o : out std_logic;
    
    -- User port
    user_d_i : in unsigned(7 downto 0);
    user_d_o : out unsigned(7 downto 0);
    user_d_en_n : out unsigned(7 downto 0);

    user_pa2_i : in std_logic;
    user_sp1_i : in std_logic;
    user_cnt2_i : in std_logic;
    user_sp2_i : in std_logic;
    user_pc2_i : in std_logic;
    user_flag2_i : in std_logic;
    user_cnt1_i : in std_logic;

    user_pa2_o : out std_logic;
    user_sp1_o : out std_logic;
    user_cnt2_o : out std_logic;
    user_sp2_o : out std_logic;
    user_pc2_o : out std_logic;
    user_flag2_o : out std_logic;
    user_cnt1_o : out std_logic;

    user_sp1_en_n : out std_logic;
    user_cnt2_en_n : out std_logic;
    user_sp2_en_n : out std_logic;
    user_cnt1_en_n : out std_logic;

    user_atn_en_n : out std_logic;

    user_reset_n_i : in std_logic;
    user_reset_n_en : out std_logic
    
);
end sim_exp_board_rings;

architecture simulation of sim_exp_board_rings is  

  signal ser_u1_u4 : std_logic;
  signal ser_u2_u5 : std_logic;
  signal ser_u4_u6 : std_logic;
  signal ser_u5_u7 : std_logic;
  signal ser_u6_u11 : std_logic;

  signal dummy_u6_q3 : std_logic;
  
begin

  -- Nothing to do: Just plumb everything together.
  
  u1: entity work.sim74LS595 port map (
    q => user_d_o,
    ser => exp_wdata,
    q_h_dash => ser_u1_u4,
    rclk => exp_latch,
    g_n => '0',
    srclr_n => '1',
    srclk => exp_clock
    );

  u2: entity work.sim74LS165 port map (
    ser => '0',
    q => user_d_i,
    q_h => ser_u2_u5,
    q_h_n => open,
    sh_ld_n => exp_latch,
    clk => exp_clock,
    clk_inhibit => '0'
    );

  u4: entity work.sim74LS595 port map (
    q(0) => user_pa2_o,
    q(1) => user_sp1_o,
    q(2) => user_cnt2_o,
    q(3) => user_sp2_o,
    q(4) => user_pc2_o,
    q(5) => user_atn_en_n,
    q(6) => user_cnt1_o,
    q(7) => user_reset_n_en,
    ser => ser_u1_u4,
    q_h_dash => ser_u4_u6,
    rclk => exp_latch,
    g_n => '0',
    srclr_n => '1',
    srclk => exp_clock    
    );

  u5: entity work.sim74LS165 port map (
    ser => ser_u2_u5,
    q(0) => user_pa2_i,
    q(1) => user_sp1_i,
    q(2) => user_cnt2_i,
    q(3) => user_sp2_i,
    q(4) => user_pc2_i,
    q(5) => user_flag2_i,
    q(6) => user_cnt1_i,
    q(7) => user_reset_n_i,
    q_h => ser_u5_u7,
    q_h_n => open,
    sh_ld_n => exp_latch,
    clk => exp_clock,
    clk_inhibit => '0'
    );

  u6: entity work.sim74LS595 port map (
    q(0) => c1565_ld_o,
    q(1) => c1565_serio_en_n,
    q(2) => c1565_rst_o,
    q(3) => dummy_u6_q3,
    q(4) => tape_write_o,
    q(5) => tape_6v_en,
    q(6) => c1565_serio_o,
    q(7) => c1565_clk_o,
    ser => ser_u4_u6,
    q_h_dash => ser_u6_u11,
    rclk => exp_latch,
    g_n => '0',
    srclr_n => '1',
    srclk => exp_clock    
    );

  u7: entity work.sim74LS165 port map (
    ser => ser_u5_u7,
    q(0) => user_cnt1_i,
    q(1) => '0',
    q(2) => '0',
    q(3) => '0',
    q(4) => tape_read_i,
    q(5) => tape_sense_i,
    q(6) => c1565_serio_i,
    q(7) => '0',
    q_h => exp_rdata,
    q_h_n => open,
    sh_ld_n => exp_latch,
    clk => exp_clock,
    clk_inhibit => '0'
    );

  u11: entity work.sim74LS595 port map (
    q => user_d_en_n,
    ser => ser_u6_u11,
    q_h_dash => open,
    rclk => exp_latch,
    g_n => '0',
    srclr_n => '1',
    srclk => exp_clock    
    );

  process (exp_latch,exp_clock) is
  begin
    if rising_edge(exp_latch) then
      report "EXP_LATCH rising edge";
    end if;
    if rising_edge(exp_clock) then
      report "EXP_CLOCK rising edge, EXP_WDATA=" & std_logic'image(EXP_WDATA);
    end if;
  end process;
  
end simulation;
