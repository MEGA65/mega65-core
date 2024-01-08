use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity exp_board_ring_ctrl is
  port (

    clock41 : in std_logic;

    -- FastIO interface to manage the ring controller
    cs : in std_logic;
    fastio_addr : in unsigned(19 downto 0);
    fastio_write : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0) := (others => 'Z');
    
    -- PMOD pins
    exp_clock : out std_logic;
    exp_latch : out std_logic;
    exp_wdata : out std_logic;
    exp_rdata : in std_logic;
    
    -- Tape port
    tape_write_o : in std_logic;
    tape_read_i : out std_logic;
    tape_sense_i : out std_logic;
    tape_6v_en : in std_logic;
    
    -- C1565 port
    c1565_serio_i : out std_logic;
    c1565_serio_o : in std_logic;
    c1565_serio_en_n : in std_logic;
    c1565_clk_o : in std_logic;
    c1565_ld_o : in std_logic;
    c1565_rst_o : in std_logic;
    
    -- User port
    user_d_i : out unsigned(7 downto 0);
    user_d_o : in unsigned(7 downto 0);
    user_d_en_n : in unsigned(7 downto 0);

    user_pa2_i : out std_logic;
    user_sp1_i : out std_logic;
    user_cnt2_i : out std_logic;
    user_sp2_i : out std_logic;
    user_pc2_i : out std_logic;
    user_flag2_i : out std_logic;
    user_cnt1_i : out std_logic;

    user_pa2_o : in std_logic;
    user_sp1_o : in std_logic;
    user_cnt2_o : in std_logic;
    user_sp2_o : in std_logic;
    user_pc2_o : in std_logic;
    user_flag2_o : in std_logic;
    user_cnt1_o : in std_logic;

    user_reset_n_i : out std_logic;
    user_spi1_en_n : in std_logic;
    user_cnt2_en_n : in std_logic;
    user_sp2_en_n : in std_logic;
    user_atn_en_n : in std_logic;
    user_cnt1_en_n : in std_logic;
    user_reset_n_en_n : in std_logic

);
end exp_board_ring_ctrl;

-- Three new ports for the MEGA65-kin under the sky,
-- Seven bidirection bits for the users and their port,
-- Eight data bits, doomed to be pulled low,
-- One ring for the expansion board, rev' nought,
-- In the land of Oz, where the deadly things lie,
--   One ring to rule them all, One ring to find them,
--   One rhing to bring them all, and to the tape port bind them,
--   In the land of Datasettes, where the loading hopes die.

architecture one_ring_to_bind_them of exp_board_rings is  

  signal output_vector : std_logic_vector(31 downto 0) := (others => '1');
  signal input_vector : std_logic_vector(23 downto 0) := (others => '1');

  signal sr_out : std_logic_vector(31 downto 0) := (others => '1');
  signal sr_in : std_logic_vector(23 downto 0) := (others => '1');  
  
begin

  process (clock41, cs, fastio_addr, fastio_write) is
  begin

    -- Read management registers
    if cs='1' then
      if fastio_write='0' then
        -- Reading
        case fastio_addr(3 downto 0) is
          when x"0" => fastio_rdata <= x"34";
          when x"1" => fastio_rdata <= input_vector(7 downto 0);
          when x"2" => fastio_rdata <= input_vector(15 downto 8);
          when x"3" => fastio_rdata <= input_vector(23 downto 16);
          when x"8" => fastio_rdata <= output_vector(7 downto 0);
          when x"9" => fastio_rdata <= output_vector(15 downto 8);
          when x"A" => fastio_rdata <= output_vector(23 downto 16);
          when x"B" => fastio_rdata <= output_vector(31 downto 24);
          when x"F" => fastio_rdata(7) <= plumb_signals;
                       fastio_rdata(6 downto 0) <= to_unsigned(clock_divisor,7);
          when others => null;
        end case;
      else
        fastio_rdata <= (others => 'Z');
      end if;
    else
      fastio_rdata <= (others => 'Z');
    end if;

    if rising_edge(clock41) then
      if cs='1' and fastio_write='1' then
        -- Write to management registers
        case fastio_addr(3 downto 0) is
          when x"1" => input_vector(7 downto 0) <= fastio_wdata;
          when x"2" => input_vector(15 downto 8) <= fastio_wdata;
          when x"3" => input_vector(23 downto 16) <= fastio_wdata;
          when x"8" => output_vector(7 downto 0) <= fastio_wdata;
          when x"9" => output_vector(15 downto 8) <= fastio_wdata;
          when x"A" => output_vector(23 downto 16) <= fastio_wdata;
          when x"B" => output_vector(31 downto 24) <= fastio_wdata;
          when x"F" =>
            plumb_signals <= fastio_wdata(7);
            clock_divisor <= to_integer(fastio_wdata(6 dowtno 0));
          when others => null;
        end case;
      end if;

  end process;
  
end one_ring_to_bind_them;
