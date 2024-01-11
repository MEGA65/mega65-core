use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;
use work.porttypes.all;

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
    tape_i : out tape_port_in;
    tape_o : in tape_port_out;
    
    -- C1565 port
    c1565_i : out c1565_port_in;
    c1565_o : in c1565_port_out;
    
    -- User port
    user_i : out user_port_in;
    user_o : in user_port_out

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

architecture one_ring_to_bind_them of exp_board_ring_ctrl is  

  signal output_vector : std_logic_vector(31 downto 0) := (others => '1');
  signal input_vector : std_logic_vector(23 downto 0) := (others => '1');

  signal sr_out : std_logic_vector(31 downto 0) := (others => '1');
  signal sr_in : std_logic_vector(23 downto 0) := (others => '1');  

  signal plumb_signals : std_logic := '1';
  
  -- The expansion board ring clock is generated by dividing the 40.5MHz CPU
  -- clock by some integer. Note that this counter applies to each half of the
  -- clock, so the frequency divisor is effectively 2x this figure, and the
  -- maximum ring clock rate is 20.25MHz when clock_divisor = 0.
  -- 40.5MHz / 4 = 10.125MHz per half-clock = 5MHz clock period
  -- As the ring requires 32 cycles, this means that we will have a sampling
  -- rate of ~5MHz / 32 = ~156KHz at this rate. Hopefully we can increase
  -- the frequency of the ring clock a bit more, to improve this. That said, it
  -- should be sufficient for most purposes.
  signal clock_divisor : integer := 4;  
  signal clock_counter : integer := 0;
  signal exp_clock_int : std_logic := '0';

  signal ring_phase : integer range 0 to 32 := 0;

  signal input_active : std_logic := '0';
  
  function to_str(signal vec: std_logic_vector) return string is
      variable result: string(0 to (vec'length-1));
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
  
begin

  process (clock41, cs, fastio_addr, fastio_write) is
  begin

    -- Read management registers
    if cs='1' then
      if fastio_write='0' then
        -- Reading
        case fastio_addr(3 downto 0) is
          when x"0" => fastio_rdata <= x"34";
          when x"1" => fastio_rdata <= unsigned(input_vector(7 downto 0));
          when x"2" => fastio_rdata <= unsigned(input_vector(15 downto 8));
          when x"3" => fastio_rdata <= unsigned(input_vector(23 downto 16));
          when x"8" => fastio_rdata <= unsigned(output_vector(7 downto 0));
          when x"9" => fastio_rdata <= unsigned(output_vector(15 downto 8));
          when x"A" => fastio_rdata <= unsigned(output_vector(23 downto 16));
          when x"B" => fastio_rdata <= unsigned(output_vector(31 downto 24));
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

      -- Write to management registers
      if cs='1' and fastio_write='1' then
        case fastio_addr(3 downto 0) is
          when x"1" => input_vector(7 downto 0) <= std_logic_vector(fastio_wdata);
          when x"2" => input_vector(15 downto 8) <= std_logic_vector(fastio_wdata);
          when x"3" => input_vector(23 downto 16) <= std_logic_vector(fastio_wdata);
          when x"8" => output_vector(7 downto 0) <= std_logic_vector(fastio_wdata);
          when x"9" => output_vector(15 downto 8) <= std_logic_vector(fastio_wdata);
          when x"A" => output_vector(23 downto 16) <= std_logic_vector(fastio_wdata);
          when x"B" => output_vector(31 downto 24) <= std_logic_vector(fastio_wdata);
          when x"F" =>
            plumb_signals <= fastio_wdata(7);
            clock_divisor <= to_integer(fastio_wdata(6 downto 0));
          when others => null;
        end case;
      end if;

      -- Generate serial ring clock
      if clock_counter < clock_divisor then
        clock_counter <= clock_counter + 1;
      else
        clock_counter <= 0;

        exp_clock <= not exp_clock_int;
        exp_clock_int <= not exp_clock_int;

        -- Assert EXP_LATCH for one cycle of EXP_CLOCK, every 32nd
        -- EXP_CLOCK.
        
        if exp_clock_int='0' then
          -- Rising edge of EXP_CLOCK
          sr_in(0) <= exp_rdata;
          sr_in(23 downto 1) <= sr_in(22 downto 0);
        end if;
        
        if exp_clock_int='1' then
          -- Falling edge of EXP_CLOCK

          -- Output bit
          exp_wdata <= sr_out(0);
          sr_out(30 downto 0) <= sr_out(31 downto 1);
          sr_out(31) <= sr_out(0);

          -- We need EXP_LATCH to remain high for 24 clock ticks to allow
          -- shifting of the data through the input ring of 74LS165s.
          -- We then need a positive edge to latch the output ring of
          -- 74LS595s.
          -- (remembering that ring_phase counts down not up, so 24 cycles
          -- is obtained by clearing EXP_LATCH when ring_phase = 32 - 24 = 8)
          -- Then we have to make some further minor adjustment to get it to
          -- all correctly line up with when we sample etc. So we use 9.
          if ring_phase = 9 then
            exp_latch <= '0';
            report "RING: latched input vector " & to_str(sr_in);
            input_vector <= sr_in;
          end if;
                         
          if ring_phase = 0 then
            ring_phase <= 32;
            exp_latch <= '1';

            -- Reset output vector
            sr_out <= output_vector;
            report "RING: preparing to output vector " & to_str(output_vector);
            -- Latch input shift register contents
          else
            ring_phase <= ring_phase - 1;
          end if;
        end if;
      end if;

      -- Update signals if enabled
      if plumb_signals = '1' then
        -- XXX Update output_vector from signals
        output_vector(23) <= user_o.pa2;
        output_vector(22) <= user_o.sp1;
        output_vector(21) <= user_o.cnt2;
        output_vector(20) <= user_o.sp2;
        output_vector(19) <= user_o.pc2;
        output_vector(18) <= user_o.atn_en_n;
        output_vector(17) <= user_o.cnt1;
        output_vector(16) <= user_o.reset_n;
        
        output_vector(15) <= c1565_o.ld;
        output_vector(14) <= c1565_o.serio_en_n;
        output_vector(13) <= c1565_o.rst;
        output_vector(12) <= '1'; -- not assigned
        output_vector(11) <= tape_o.wdata;
        output_vector(10) <= tape_o.motor_en;
        output_vector(9) <= c1565_o.serio;        
        output_vector(8) <= c1565_o.clk;
        
        for i in 0 to 7 loop
          output_vector(31-i) <= user_o.d(i);
          output_vector(7-i) <= user_o.d_en_n(i);
        end loop;
      end if;

      if input_vector /= "111111111111111111111111" and
        input_vector /=  "000000000000000000000000" then
        input_active <= '1';
      else
        input_active <= '0';
      end if;

      if input_active = '1' then
        for i in 0 to 7 loop
          user_i.d(i) <= input_vector(i);
        end loop;

        c1565_i.serio <= input_vector(22);
        tape_i.sense <= input_vector(21);
        tape_i.rdata <= input_vector(20);
        user_i.pa2 <= input_vector(8);
        user_i.sp1 <= input_vector(9);
        user_i.cnt2 <= input_vector(10);
        user_i.sp2 <= input_vector(11);
        user_i.pc2 <= input_vector(12);
        user_i.flag2 <= input_vector(13);
        user_i.cnt1 <= input_vector(14);
        user_i.reset_n <= input_vector(15);
      else
        user_i.d <= (others => '1');
        c1565_i.serio <= '1';
        tape_i.sense <= '1';
        tape_i.rdata <= '1';
        user_i.pa2 <= '1';
        user_i.sp1 <= '1';
        user_i.cnt2 <= '1';
        user_i.sp2 <= '1';
        user_i.pc2 <= '1';
        user_i.flag2 <= '1';
        user_i.cnt1 <= '1';
        user_i.reset_n <= '1';        
      end if;
      
    end if;
  end process;
  
end one_ring_to_bind_them;
