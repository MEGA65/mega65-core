use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity cia6526 is
  port (
    cpuclock : in std_logic;
    phi0 : in std_logic;
    todclock : in std_logic;
    reset : in std_logic;
    irq : out std_logic := 'Z';

    seg_led : out unsigned(31 downto 0);

    reg_isr_out : out unsigned(7 downto 0);
    imask_ta_out : out std_logic;
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    cs : in std_logic;
    fastio_address : in unsigned(7 downto 0);
    fastio_write : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0);

    portaout : out std_logic_vector(7 downto 0);
    portain : in std_logic_vector(7 downto 0);
    
    portbout : out std_logic_vector(7 downto 0);
    portbin : in std_logic_vector(7 downto 0);

    flagin : in std_logic;

    pcout : out std_logic;

    spout : out std_logic;
    spin : in std_logic;

    countout : out std_logic;
    countin : in std_logic);
end cia6526;

architecture behavioural of cia6526 is

  signal reg_porta_out : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_portb_out : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_porta_ddr : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_portb_ddr : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_porta_read : unsigned(7 downto 0) := (others => '0');
  signal reg_portb_read : unsigned(7 downto 0) := (others => '0');

  signal reg_timera : unsigned(15 downto 0) := x"0001";
  signal reg_timera_latch : unsigned(15 downto 0) := x"0001";
  signal reg_timerb : unsigned(15 downto 0);
  signal reg_timerb_latch : unsigned(15 downto 0);

  signal reg_timera_tick_source : std_logic := '0'; 
  signal reg_timera_oneshot : std_logic := '0';
  signal reg_timera_toggle_or_pulse : std_logic := '0';
  signal reg_timera_pb6_out : std_logic := '0';
  signal reg_timera_start : std_logic := '1';
  signal reg_timera_has_ticked : std_logic := '0';
  signal reg_timera_underflow : std_logic := '0';

  signal reg_timerb_tick_source : std_logic_vector(1 downto 0) := "00";
  signal reg_timerb_oneshot : std_logic := '0';
  signal reg_timerb_toggle_or_pulse : std_logic := '0';
  signal reg_timerb_pb7_out : std_logic := '0';
  signal reg_timerb_start : std_logic := '0';
  signal reg_timerb_has_ticked : std_logic := '0';

  -- TOD Alarm
  signal reg_tod_alarm_edit : std_logic := '0';
  signal reg_alarm_ampm : std_logic := '0';
  signal reg_alarm_hours : unsigned(6 downto 0) := (others => '0');
  signal reg_alarm_mins : unsigned(7 downto 0) := (others => '0');
  signal reg_alarm_secs : unsigned(7 downto 0) := (others => '0');
  signal reg_alarm_dsecs : unsigned(7 downto 0) := (others => '0');

  -- BCD time of day clock
  signal reg_60hz : std_logic := '0';
  signal tod_running : std_logic := '1';
  signal reg_tod_ampm : std_logic := '0';
  signal reg_tod_hours : unsigned(6 downto 0) := (others => '0');
  signal reg_tod_mins : unsigned(7 downto 0) := (others => '0');
  signal reg_tod_secs : unsigned(7 downto 0) := (others => '0');
  signal reg_tod_dsecs : unsigned(7 downto 0) := (others => '0');
  -- Latched copies of the TOD clock for reading
  signal read_tod_latched : std_logic := '0';
  signal read_tod_ampm : std_logic := '0';
  signal read_tod_hours : unsigned(6 downto 0) := (others => '0');
  signal read_tod_mins : unsigned(7 downto 0) := (others => '0');
  signal read_tod_secs : unsigned(7 downto 0) := (others => '0');
  signal read_tod_dsecs : unsigned(7 downto 0) := (others => '0');
  -- Latched copies of the TOD clock for writing
  signal write_tod_latched : std_logic := '0';
  signal write_tod_ampm : std_logic := '0';
  signal write_tod_hours : unsigned(6 downto 0) := (others => '0');
  signal write_tod_mins : unsigned(7 downto 0) := (others => '0');
  signal write_tod_secs : unsigned(7 downto 0) := (others => '0');
  signal write_tod_dsecs : unsigned(7 downto 0) := (others => '0');


  signal last_flag : std_logic := '0';
  signal reg_isr : unsigned(7 downto 0) := x"00";
  signal strobe_pc : std_logic;
  signal imask_flag : std_logic := '0';
  signal imask_serialport : std_logic := '0';
  signal imask_alarm : std_logic := '0';
  signal imask_tb : std_logic := '0';
  signal imask_ta : std_logic := '1';

  signal reg_serialport_direction : std_logic := '0';
  signal reg_sdr : std_logic_vector(7 downto 0);
  signal reg_sdr_data : std_logic_vector(7 downto 0);
  signal reg_read_sdr : std_logic_vector(7 downto 0) := x"FF";
  signal sdr_loaded : std_logic := '0';

  signal prev_phi0 : std_logic;
  signal prev_countin : std_logic;

  signal clear_isr : std_logic := '0';  -- flag to clear ISR after reading
  signal clear_isr_count : unsigned(4 downto 0) := "00000";

begin  -- behavioural
  
  process(cpuclock,fastio_address,fastio_write,flagin,cs,portain,portbin,
          reg_porta_ddr,reg_portb_ddr,reg_porta_out,reg_portb_out,
          reg_timera,reg_timerb,read_tod_latched,read_tod_dsecs,
          reg_tod_secs,reg_tod_mins,reg_tod_hours,reg_tod_ampm,reg_read_sdr,
          reg_isr,reg_60hz,reg_serialport_direction,
          reg_timera_tick_source,reg_timera_oneshot,
          reg_timera_toggle_or_pulse,reg_tod_alarm_edit,
          reg_timerb_tick_source,reg_timerb_oneshot,
          reg_timerb_toggle_or_pulse,reg_timerb_pb7_out,
          reg_timerb_start,
          reg_porta_read,reg_portb_read,
          reg_tod_secs,reg_tod_mins,reg_tod_dsecs,
          read_tod_secs,read_tod_mins,read_tod_dsecs,read_tod_hours,
          reg_timera_pb6_out,reg_timera_start
          ) is
    variable register_number : unsigned(7 downto 0);
  begin
    if cs='0' then
      -- Tri-state read lines if not selected
      fastio_rdata <= (others => 'Z');
    else
--      if rising_edge(cpuclock) then
        -- XXX For debugging have 32 registers, and map
        -- reg_porta_read and portain (and same for port b)
        -- to extra registers for debugging.
        register_number(7 downto 5) := (others => '0');
        register_number(4 downto 0) := fastio_address(4 downto 0);

        -- Reading of registers
        if fastio_write='1' then
          -- Tri-state read lines if writing
          fastio_rdata <= (others => 'Z');
        else
          case register_number is
            when x"00" => fastio_rdata <= unsigned(reg_porta_read); -- reg_porta_read;
            when x"01" => fastio_rdata <= unsigned(reg_portb_read); -- reg_portb_read;
            when x"10" => fastio_rdata <= unsigned(portain); -- reg_porta_read;
            when x"11" => fastio_rdata <= unsigned(portbin); -- reg_portb_read;
            when x"02" => fastio_rdata <= unsigned(reg_porta_ddr);
            when x"03" => fastio_rdata <= unsigned(reg_portb_ddr);
            when x"04" => fastio_rdata <= reg_timera(7 downto 0);
            when x"05" => fastio_rdata <= reg_timera(15 downto 8);
            when x"06" => fastio_rdata <= reg_timerb(7 downto 0);
            when x"07" => fastio_rdata <= reg_timerb(15 downto 8);
            when x"08" =>
              if read_tod_latched='1' then
                fastio_rdata <= read_tod_dsecs;
              else
                fastio_rdata <= reg_tod_dsecs;
              end if;
            when x"09" =>   
              if read_tod_latched='1' then
                fastio_rdata <= read_tod_secs;
              else
                fastio_rdata <= reg_tod_secs;
              end if;
            when x"0a" =>   
              if read_tod_latched='1' then
                fastio_rdata <= read_tod_mins;
              else
                fastio_rdata <= reg_tod_mins;
              end if;
            when x"0b" =>   
              fastio_rdata <= reg_tod_ampm & reg_tod_hours;
            when x"0c" => fastio_rdata <= unsigned(reg_read_sdr);
            when x"0d" =>
              fastio_rdata <= reg_isr;
            when x"0e" => 
              fastio_rdata <= reg_60hz
                              & reg_serialport_direction
                              & reg_timera_tick_source
                              & '0'
                              & reg_timera_oneshot
                              & reg_timera_toggle_or_pulse
                              & reg_timera_pb6_out
                              & reg_timera_start;            
            when x"0f" =>
              fastio_rdata <= unsigned(reg_tod_alarm_edit
                                       & reg_timerb_tick_source
                                       & '0'  -- strobe always reads as 0
                                       & reg_timerb_oneshot
                                       & reg_timerb_toggle_or_pulse
                                       & reg_timerb_pb7_out
                                       & reg_timerb_start);
            when others => fastio_rdata <= (others => 'Z');
          end case;
        end if;
      end if;
--    end if;
  end process;

  process(cpuclock) is
    -- purpose: use DDR to show either input or output bits
    function ddr_pick (
      ddr                            : in std_logic_vector(7 downto 0);
      i                              : in std_logic_vector(7 downto 0);
      o                              : in std_logic_vector(7 downto 0))
    return unsigned is
    variable result : unsigned(7 downto 0);     
  begin  -- ddr_pick
    --report "determining read value for CIA port." &
    --  "  DDR=$" & to_hstring(ddr) &
    --  ", out_value=$" & to_hstring(o) &
    --  ", in_value=$" & to_hstring(i) severity note;
    result := unsigned(i);
    for b in 0 to 7 loop
      if ddr(b)='1' and i(b)='1' then
        result(b) := std_ulogic(o(b));
      end if;
    end loop;  -- b
    return result;
  end ddr_pick;

  variable register_number : unsigned(3 downto 0);
  begin
    if rising_edge(cpuclock) then

      if reset='0' then
        -- Clear interrupt flags on reset
        imask_flag <= '0';
        imask_serialport <= '0';
        imask_alarm <= '0';
        imask_tb <= '0';
        imask_ta <= '0';
      end if;
      
      register_number := fastio_address(3 downto 0);

      reg_isr_out(7) <= reg_isr(7);
      reg_isr_out(0) <= reg_isr(0);
      reg_isr_out(1) <= clear_isr;
      reg_isr_out(6 downto 2) <= clear_isr_count;
      
      imask_ta_out <= imask_ta;
      
      -- XXX We clear ISR one cycle after the register is read so that
      -- if fastio has a one cycle wait state, the isr can still be read on
      -- the second cycle.
      if clear_isr='1' then
        -- lie any say serial port done to placate C65 ROM for now
        reg_isr <= x"08";
        clear_isr <= '0';
        -- report "clearing ISR" severity note;
      end if;
      
      -- Set IRQ line status
      if (imask_flag='1' and reg_isr(4)='1')
        or (imask_serialport='1' and reg_isr(3)='1')
        or (imask_alarm='1' and reg_isr(2)='1')
        or (imask_tb='1' and reg_isr(1)='1')
        or (imask_ta='1' and reg_isr(0)='1')
      then
        -- report "IRQ asserted, imask_ta=" & std_logic'image(imask_ta) severity note;
        reg_isr(7)<='1'; irq<='0';
      else
        reg_isr(7)<='0'; irq<='Z';
      end if;
      
      -- Look for timera and timerb tick events
      prev_phi0 <= phi0;
      prev_countin <= countin;
      reg_timera_underflow <= '0';
--      report "CIA reg_timera_start=" & std_logic'image(reg_timera_start) & ", phi0=" & std_logic'image(phi0);
      if reg_timera_start='1' then
        if reg_timera = x"FFFF" and reg_timera_has_ticked='1' then
          -- underflow
          report "CIA timera underflow";
          reg_isr(0) <= '1';
          reg_timera_underflow <= '1';
          if reg_timera_oneshot='0' then
            reg_timera <= reg_timera_latch;
          else
            reg_timera_start <= '0';
          end if;
          reg_timera_has_ticked <= '0';
        end if;
        case reg_timera_tick_source is
          when '0' =>
            -- phi2 pulses
            if phi0='0' and prev_phi0='1' then
              report "CIA timera ticked down to $" & to_hstring(reg_timera);
              reg_timera <= reg_timera - 1;
              reg_timera_has_ticked <= '1';
            end if;
          when '1' =>
            -- positive CNT transitions
            if countin='1' and prev_countin='0' then
              reg_timera <= reg_timera - 1;
              reg_timera_has_ticked <= '1';
            end if;
          when others => null;
        end case;
      end if;
      if reg_timerb_start='1' then
        if reg_timerb = x"FFFF" and reg_timerb_has_ticked='1' then
          -- underflow
          reg_isr(1) <= '1';
          if reg_timerb_oneshot='0' then
            reg_timerb <= reg_timerb_latch;
          else
            reg_timerb_start <= '0';
          end if;
          reg_timerb_has_ticked <= '0';
        end if;
        case reg_timerb_tick_source(0) is
          when '0' =>
            -- phi2 pulses
            if reg_timera_underflow='1' or reg_timerb_tick_source(1)='0' then
              if phi0='0' and prev_phi0='1' then
                reg_timerb <= reg_timerb - 1;
                reg_timerb_has_ticked <= '0';
              end if;                
            end if;
          when '1' =>
            -- positive CNT transitions
            if reg_timera_underflow='1' or reg_timerb_tick_source(1)='0' then
              if countin='1' and prev_countin='0' then
                reg_timerb <= reg_timerb - 1;
                reg_timerb_has_ticked <= '0';
              end if;
            end if; 
          when others => null;
        end case;
      end if;
      
      -- Calculate read value for porta and portb
      reg_porta_read <= ddr_pick(reg_porta_ddr,portain,reg_porta_out);        
      reg_portb_read <= ddr_pick(reg_portb_ddr,portbin,reg_portb_out);        

      -- Check for negative edge on FLAG
      -- XXX We should latch this asynchronously instead of sampling it
      last_flag <= flagin;
      if last_flag='1' and flagin='0' then
        reg_isr(4) <='1';
      end if;

      -- Strobe PC line
      if strobe_pc='1' then
        pcout<='0';
        strobe_pc<='0';
      end if;

      -- Check for register read side effects
      if fastio_write='0' and cs='1' then
        --report "Performing side-effects of reading from CIA register $" & to_hstring(register_number) severity note;
        register_number := fastio_address(3 downto 0);
        case register_number is
          when x"1" =>
            -- Reading or writing port B strobes PC high for 1 cycle
            pcout <= '1';
            strobe_pc <= '1';
          when x"8" => read_tod_latched <='0';
          when x"b" =>
            read_tod_latched <='1';
            read_tod_mins <= reg_tod_mins;
            read_tod_secs <= reg_tod_secs;
            read_tod_dsecs <= reg_tod_dsecs;
          when x"d" =>
            -- Reading ICR/ISR clears all interrupts
            clear_isr <= '1';
            clear_isr_count <= clear_isr_count + 1;
          when others => null;
        end case;
      end if;

      portbout <= reg_portb_out or (not reg_portb_ddr);
      portaout <= reg_porta_out or (not reg_porta_ddr);
      
      -- Check for register writing
      if fastio_write='1' and cs='1' then
        --report "writing $" & to_hstring(fastio_wdata)
        --  & " to CIA register $" & to_hstring(register_number) severity note;
        register_number := fastio_address(3 downto 0);
        case register_number is
          when x"0" => 
                       reg_porta_out<=std_logic_vector(fastio_wdata);
          when x"1" =>  
            
            reg_portb_out<=std_logic_vector(fastio_wdata);
          when x"2" => reg_porta_ddr<=std_logic_vector(fastio_wdata);
          when x"3" => reg_portb_ddr<=std_logic_vector(fastio_wdata);
          when x"4" => reg_timera_latch(7 downto 0) <= fastio_wdata;
          when x"5" => reg_timera_latch(15 downto 8) <= fastio_wdata;
                       if reg_timera_start='0' then
                         -- load timer value now (CIA datasheet, page 6)
                         reg_timera <= fastio_wdata & reg_timera_latch(7 downto 0);
                       end if;
          when x"6" => reg_timerb_latch(7 downto 0) <= fastio_wdata;
          when x"7" => reg_timerb_latch(15 downto 8) <= fastio_wdata;
                       if reg_timera_start='0' then
                         -- load timer value now (CIA datasheet, page 6)
                         reg_timerb <= fastio_wdata & reg_timerb_latch(7 downto 0);
                       end if;
          when x"8" =>
            if reg_tod_alarm_edit ='0' then
              reg_tod_dsecs <= fastio_wdata; tod_running<='1';
            else
              reg_alarm_dsecs <= fastio_wdata;
            end if;
          when x"9" => 
            if reg_tod_alarm_edit ='0' then
              reg_tod_secs <= fastio_wdata;
            else
              reg_alarm_secs <= fastio_wdata;
            end if;
          when x"a" => 
            if reg_tod_alarm_edit ='0' then
              reg_tod_mins <= fastio_wdata;
            else
              reg_alarm_mins <= fastio_wdata;
            end if;
          when x"b" => 
            if reg_tod_alarm_edit ='0' then
              tod_running <= '0';
              reg_tod_hours <= fastio_wdata(6 downto 0);
              reg_tod_ampm <= fastio_wdata(7);
            else
              reg_alarm_hours <= fastio_wdata(6 downto 0);
              reg_alarm_ampm <= fastio_wdata(7);
            end if;
          when x"c" =>
            reg_sdr_data <= std_logic_vector(fastio_wdata);
            sdr_loaded <= '1';
          when x"d" =>
            if fastio_wdata(7)='1' then
              -- Set interrupt mask bits
              imask_flag <= imask_flag or fastio_wdata(4);
              imask_serialport <= imask_serialport or fastio_wdata(3);
              imask_alarm <= imask_alarm or fastio_wdata(2);
              imask_tb <= imask_tb or fastio_wdata(1);
              imask_ta <= imask_ta or fastio_wdata(0);
              --report "wrote to interrupt mask bits" severity note;
              --report "imask_ta = " & std_logic'image(imask_ta) severity note;
            else
              -- Clear interrupt mask bits if a bit is 1.
              imask_flag <= imask_flag and (not fastio_wdata(4));
              imask_serialport <= imask_serialport and (not fastio_wdata(3));
              imask_alarm <= imask_alarm and (not fastio_wdata(2));
              imask_tb <= imask_tb and (not fastio_wdata(1));
              imask_ta <= imask_ta and (not fastio_wdata(0));                 
            end if;
          when x"e" =>
            reg_60hz <= fastio_wdata(7);
            reg_serialport_direction <= fastio_wdata(6);
            reg_timera_tick_source <= fastio_wdata(5);
            if fastio_wdata(4)='1' then
              -- Force loading of timer A now from latch
              reg_timera <= reg_timera_latch;
              reg_timera_has_ticked <= '0';
            end if;
            reg_timera_oneshot <= fastio_wdata(3);
            reg_timera_toggle_or_pulse <= fastio_wdata(2);
            reg_timera_pb6_out <= fastio_wdata(1);
            reg_timera_start <= fastio_wdata(0);
          when x"f" =>
            reg_tod_alarm_edit <= std_logic(fastio_wdata(7));
            reg_timerb_tick_source <= std_logic_vector(fastio_wdata(6 downto 5));
            if fastio_wdata(4)='1' then
              -- Force loading of timer A now from latch
              reg_timerb <= reg_timerb_latch;
              reg_timerb_has_ticked <= '0';
            end if;
            reg_timerb_oneshot <= std_logic(fastio_wdata(3));
            reg_timerb_toggle_or_pulse <= std_logic(fastio_wdata(2));
            reg_timerb_pb7_out <= std_logic(fastio_wdata(1));
            reg_timerb_start <= std_logic(fastio_wdata(0));                  
          when others => null;
        end case;
      end if;
    end if;
  end process;

end behavioural;
