use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity cia6526 is
  generic (    
    unit : in unsigned(3 downto 0) := x"0"
    );
  port (
    cpuclock : in std_logic;
    phi0_1mhz : in std_logic;
    todclock : in std_logic;
    reset : in std_logic;
    irq : out std_logic := 'H';

    -- If 1, then delay writes to PORTA (ie., IEC serial bus)
    -- by 4 1MHz clock cycles, so that it is as though it were
    -- written at the end of an STA $nnnn instruction
    cpu_slow : in std_logic;
    
    hypervisor_mode : in std_logic;
    
    seg_led : out unsigned(31 downto 0) := (others => '0');

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
    portaddr : out std_logic_vector(7 downto 0);
    
    portbout : out std_logic_vector(7 downto 0);
    portbin : in std_logic_vector(7 downto 0);
    portbddr : out std_logic_vector(7 downto 0);

    flagin : in std_logic;

    pcout : out std_logic;

    spout : out std_logic;
    spin : in std_logic;
    sp_ddr : out std_logic := '0';

    countout : out std_logic;
    countin : in std_logic);
end cia6526;

architecture behavioural of cia6526 is

  -- Keep track if we have a pending write to port A waiting
  signal reg_porta_pending : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_porta_pending_timer : integer range 0 to 4 := 0;
  signal last_phi0_1mhz : std_logic := '0';
  signal dd00_delay : std_logic := '0';
  signal portain_delay0 : unsigned(7 downto 0) := (others => '0');
  signal portain_delay1 : unsigned(7 downto 0) := (others => '0');
  signal portain_delay2 : unsigned(7 downto 0) := (others => '0');
  signal portain_delayed : unsigned(7 downto 0) := (others => '0');
  
  signal reg_porta_out : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_portb_out : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_porta_ddr : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_portb_ddr : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_porta_read : unsigned(7 downto 0) := (others => '0');
  signal reg_portb_read : unsigned(7 downto 0) := (others => '0');

  signal reg_timera : unsigned(15 downto 0) := x"0001";
  signal reg_timera_latch : unsigned(15 downto 0) := x"0001";
  signal reg_timerb : unsigned(15 downto 0) := x"0000";
  signal reg_timerb_latch : unsigned(15 downto 0) := x"0000";

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
  signal reg_50hz : std_logic := '0';
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
  signal strobe_pc : std_logic := '0';
  signal imask_flag : std_logic := '0';
  signal imask_serialport : std_logic := '0';
  signal imask_alarm : std_logic := '0';
  signal imask_tb : std_logic := '0';
  signal imask_ta : std_logic := '1';

  signal reg_serialport_direction : std_logic := '0';
  signal reg_read_sdr : std_logic_vector(7 downto 0) := x"FF";

  signal reg_sdr_data : std_logic_vector(7 downto 0) := x"00";
  signal sdr_bits_remaining : integer := 0;
  signal sdr_bit_alternate : std_logic := '0';

  signal prev_countin : std_logic := '0';

  signal prev_todclock : std_logic := '0';

  signal clear_isr : std_logic := '0';  -- flag to clear ISR after reading
  signal clear_isr_count : unsigned(4 downto 0) := "00000";
  signal clear_isr_bits : unsigned(7 downto 0) := x"00";
  
  signal todcounter : integer := 0;

  

begin  -- behavioural
  
  process(cpuclock,fastio_address,fastio_write,flagin,cs,portain,portbin,
          reg_porta_ddr,reg_portb_ddr,reg_porta_out,reg_portb_out,
          reg_timera,reg_timerb,read_tod_latched,read_tod_dsecs,
          reg_tod_secs,reg_tod_mins,reg_tod_hours,reg_tod_ampm,reg_read_sdr,
          reg_isr,reg_50hz,reg_serialport_direction,
          reg_timera_tick_source,reg_timera_oneshot,
          reg_timera_toggle_or_pulse,reg_tod_alarm_edit,
          reg_timerb_tick_source,reg_timerb_oneshot,
          reg_timerb_toggle_or_pulse,reg_timerb_pb7_out,
          reg_timerb_start,
          reg_porta_read,reg_portb_read,
          reg_tod_secs,reg_tod_mins,reg_tod_dsecs,
          read_tod_secs,read_tod_mins,read_tod_dsecs,read_tod_hours,
          reg_timera_pb6_out,reg_timera_start,
          hypervisor_mode,reg_timera_latch,reg_timerb_latch,imask_flag,
          imask_serialport,imask_alarm,imask_ta,imask_tb,reg_alarm_dsecs,
          reg_alarm_secs,reg_alarm_mins,reg_alarm_hours,reg_alarm_ampm          
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
        if hypervisor_mode='1' then
          register_number(4) := fastio_address(4);
        else
          register_number(4) := '0';
        end if;
        register_number(3 downto 0) := fastio_address(3 downto 0);

        -- Reading of registers
        if fastio_write='1' then
          -- Tri-state read lines if writing
          fastio_rdata <= (others => 'Z');
        else
          case register_number is
            -- @IO:C64 $DC00 CIA1:PORTA Port A 
            -- @IO:C64 $DC01 CIA1:PORTB Port B
            -- @IO:C64 $DC02 CIA1:DDRA Port A DDR
            -- @IO:C64 $DC03 CIA1:DDRB Port B DDR
            -- @IO:C64 $DD00 CIA2:PORTA Port A 
            -- @IO:C64 $DD01 CIA2:PORTB Port B
            -- @IO:C64 $DD02 CIA2:DDRA Port A DDR
            -- @IO:C64 $DD03 CIA2:DDRB Port B DDR
            when x"00" => fastio_rdata <= unsigned(reg_porta_read); -- reg_porta_read;
            when x"01" => fastio_rdata <= unsigned(reg_portb_read); -- reg_portb_read;
            when x"02" => fastio_rdata <= unsigned(reg_porta_ddr);
            when x"03" => fastio_rdata <= unsigned(reg_portb_ddr);
                          
            -- @IO:C64 $DC04 CIA1:TIMERA Timer A counter (16 bit)
            -- @IO:C64 $DC05 CIA1:TIMERA Timer A counter (16 bit)
            -- @IO:C64 $DC06 CIA1:TIMERB Timer B counter (16 bit)
            -- @IO:C64 $DC07 CIA1:TIMERB Timer B counter (16 bit)
            -- @IO:C64 $DD04 CIA2:TIMERA Timer A counter (16 bit)
            -- @IO:C64 $DD05 CIA2:TIMERA Timer A counter (16 bit)
            -- @IO:C64 $DD06 CIA2:TIMERB Timer B counter (16 bit)
            -- @IO:C64 $DD07 CIA2:TIMERB Timer B counter (16 bit)
            when x"04" => fastio_rdata <= reg_timera(7 downto 0);
            when x"05" => fastio_rdata <= reg_timera(15 downto 8);
            when x"06" => fastio_rdata <= reg_timerb(7 downto 0);
            when x"07" => fastio_rdata <= reg_timerb(15 downto 8);
            when x"08" =>
              -- @IO:C64 $DC08.0-3 CIA1:TODJIF TOD tenths of seconds
              -- @IO:C64 $DD08.0-3 CIA2:TODJIF TOD tenths of seconds
              if read_tod_latched='1' then
                fastio_rdata <= read_tod_dsecs;
              else
                fastio_rdata <= reg_tod_dsecs;
              end if;
            when x"09" =>   
              -- @IO:C64 $DC09.0-5 CIA1:TODSEC TOD seconds
              -- @IO:C64 $DD09.0-5 CIA2:TODSEC TOD seconds
              if read_tod_latched='1' then
                fastio_rdata <= read_tod_secs;
              else
                fastio_rdata <= reg_tod_secs;
              end if;
            when x"0a" =>   
              -- @IO:C64 $DC0A.0-5 CIA1:TODMIN TOD minutes
              if read_tod_latched='1' then
                fastio_rdata <= read_tod_mins;
              else
                fastio_rdata <= reg_tod_mins;
              end if;
            when x"0b" =>
              -- @IO:C64 $DC0B.7 CIA1:TOD!AMPM TOD PM flag
              -- @IO:C64 $DC0B.0-4 CIA1:TODHOUR TOD hours
              -- @IO:C64 $DD0B.7 CIA2:TOD!AMPM TOD PM flag
              -- @IO:C64 $DD0B.0-4 CIA2:TODHOUR TOD hours
              fastio_rdata <= reg_tod_ampm & reg_tod_hours;
            when x"0c" =>
              -- @IO:C64 $DC0C CIA1:SDR shift register data register(writing starts sending)
              -- @IO:C64 $DD0C CIA2:SDR shift register data register(writing starts sending)
              fastio_rdata <= unsigned(reg_read_sdr);
            when x"0d" =>
              -- @IO:C64 $DC0D.0 CIA1:TA Timer A underflow
              -- @IO:C64 $DC0D.1 CIA1:TB Timer B underflow
              -- @IO:C64 $DC0D.2 CIA1:ALRM TOD alarm
              -- @IO:C64 $DC0D.3 CIA1:SP shift register full/empty
              -- @IO:C64 $DC0D.4 CIA1:FLG FLAG edge detected
              -- @IO:C64 $DC0D.5-6 CIA1:ISRCLR Placeholder - Reading clears events
              -- @IO:C64 $DC0D.7 CIA1:IR Interrupt flag
              -- @IO:C64 $DD0D.0 CIA2:TA Timer A underflow
              -- @IO:C64 $DD0D.1 CIA2:TB Timer B underflow
              -- @IO:C64 $DD0D.2 CIA2:ALRM TOD alarm
              -- @IO:C64 $DD0D.3 CIA2:SP shift register full/empty
              -- @IO:C64 $DD0D.4 CIA2:FLG FLAG edge detected
              -- @IO:C64 $DD0D.5-6 CIA2:ISRCLR Placeholder - Reading clears events
              -- @IO:C64 $DD0D.7 CIA2:IR Interrupt flag
              fastio_rdata <= reg_isr;
            when x"0e" =>
              -- @IO:C64 $DC0E.0 CIA1:STRTA Timer A start
              -- @IO:C64 $DC0E.1 CIA1:PBONA Timer A PB6 out
              -- @IO:C64 $DC0E.2 CIA1:OMODA Timer A toggle or pulse
              -- @IO:C64 $DC0E.3 CIA1:RMODA Timer A one-shot mode
              -- @IO:C64 $DC0E.5 CIA1:IMODA Timer A tick source
              -- @IO:C64 $DC0E.6 CIA1:SPMOD Serial port direction
              -- @IO:C64 $DC0E.7 CIA1:TOD50 50/60Hz select for TOD clock
              -- @IO:C64 $DD0E.0 CIA2:STRTA Timer A start
              -- @IO:C64 $DD0E.1 CIA2:PBONA Timer A PB6 out
              -- @IO:C64 $DD0E.2 CIA2:OMODA Timer A toggle or pulse
              -- @IO:C64 $DD0E.3 CIA2:RMODA Timer A one-shot mode
              -- @IO:C64 $DD0E.5 CIA2:IMODA Timer A tick source
              -- @IO:C64 $DD0E.6 CIA2:SPMOD Serial port direction
              -- @IO:C64 $DD0E.7 CIA2:TOD50 50/60Hz select for TOD clock
              fastio_rdata <= reg_50hz
                              & reg_serialport_direction
                              & reg_timera_tick_source
                              & '0'
                              & reg_timera_oneshot
                              & reg_timera_toggle_or_pulse
                              & reg_timera_pb6_out
                              & reg_timera_start;
              
            when x"0f" =>
              -- @IO:C64 $DC0F.0 CIA1:STRTB Timer B start
              -- @IO:C64 $DC0F.1 CIA1:PBONB Timer B PB7 out
              -- @IO:C64 $DC0F.2 CIA1:OMODB Timer B toggle or pulse
              -- @IO:C64 $DC0F.3 CIA1:RMODB Timer B one-shot mode
              -- @IO:C64 $DC0F.4 CIA1:LOAD Strobe input to force-load timers
              -- @IO:C64 $DC0F.5-6 CIA1:IMODB Timer B tick source
              -- @IO:C64 $DC0F.7 CIA1:TODEDIT TOD alarm edit
              -- @IO:C64 $DD0F.0 CIA2:STRTB Timer B start
              -- @IO:C64 $DD0F.1 CIA2:PBONB Timer B PB7 out
              -- @IO:C64 $DD0F.2 CIA2:OMODB Timer B toggle or pulse
              -- @IO:C64 $DD0F.3 CIA2:RMODB Timer B one-shot mode
              -- @IO:C64 $DD0F.4 CIA2:LOAD Strobe input to force-load timers
              -- @IO:C64 $DD0F.5-6 CIA2:IMODB Timer B tick source
              -- @IO:C64 $DD0F.7 CIA2:TODEDIT TOD alarm edit
              fastio_rdata <= unsigned(reg_tod_alarm_edit
                                       & reg_timerb_tick_source
                                       & '0'  -- strobe always reads as 0
                                       & reg_timerb_oneshot
                                       & reg_timerb_toggle_or_pulse
                                       & reg_timerb_pb7_out
                                       & reg_timerb_start);

            when x"10" => fastio_rdata <= reg_timera_latch(7 downto 0);
            when x"11" => fastio_rdata <= reg_timera_latch(15 downto 8);

            when x"13" => fastio_rdata <= reg_timerb_latch(15 downto 8);
            when x"14" => fastio_rdata <= reg_timera(7 downto 0);
            when x"15" => fastio_rdata <= reg_timera(15 downto 8);
            when x"16" => fastio_rdata <= reg_timerb(7 downto 0);
            when x"17" => fastio_rdata <= reg_timerb(15 downto 8);

            when x"18" => fastio_rdata(3 downto 0) <= reg_tod_dsecs(3 downto 0);
                          -- Also the flags needed to exactly restore the CIA settings
                          fastio_rdata(7) <= imask_flag;
                          fastio_rdata(6) <= imask_serialport;
                          fastio_rdata(5) <= imask_alarm;
                          fastio_rdata(4) <= imask_tb;
            when x"19" => fastio_rdata(6 downto 0) <= reg_tod_secs(6 downto 0);
                          -- Also the flags needed to exactly restore the CIA settings
                          fastio_rdata(7) <= imask_ta;
            when x"1a" => fastio_rdata <= reg_tod_mins;
            when x"1b" => fastio_rdata <= reg_tod_ampm & reg_tod_hours;
            when x"1c" => fastio_rdata <= reg_alarm_dsecs;
            when x"1d" => fastio_rdata <= reg_alarm_secs;
            when x"1e" => fastio_rdata <= reg_alarm_mins;
            when x"1f" => fastio_rdata <= reg_alarm_ampm & reg_alarm_hours;
                          
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

  variable register_number : unsigned(7 downto 0);
  begin
    if rising_edge(cpuclock) then

      -- Check for time-delayed writes to IEC port
      last_phi0_1mhz <= phi0_1mhz;
      if phi0_1mhz='0' and last_phi0_1mhz='1' then
        if reg_porta_pending_timer /= 0 then
          reg_porta_pending_timer <= reg_porta_pending_timer - 1;
        end if;
        if reg_porta_pending_timer = 1 then
          reg_porta_out <= reg_porta_pending;
        end if;
        -- Three cycle delay on read, also
        portain_delay0 <= unsigned(portain);
        portain_delay1 <= portain_delay0;
        portain_delay2 <= portain_delay1;
      end if;
      if dd00_delay = '0' then
        portain_delayed <= unsigned(portain);
      else
        portain_delayed(2 downto 0) <= unsigned(portain(2 downto 0));
        portain_delayed(5 downto 3) <= portain_delay2(5 downto 3);
        portain_delayed(7 downto 6) <= unsigned(portain(7 downto 6));
      end if;
      
      sp_ddr <= reg_serialport_direction;
      
      if reset='0' then
        -- Clear interrupt flags on reset
        imask_flag <= '0';
        imask_serialport <= '0';
        imask_alarm <= '0';
        imask_tb <= '0';
        imask_ta <= '0';
      end if;

      portbddr <= reg_portb_ddr;
      
      register_number(7 downto 5) := "000";
      if hypervisor_mode='1' then
        register_number(4) := fastio_address(4);
      else
        register_number(4) := '0';
      end if;
      register_number(3 downto 0) := fastio_address(3 downto 0);

      reg_isr_out(7) <= reg_isr(7);
      reg_isr_out(0) <= reg_isr(0);
      reg_isr_out(1) <= clear_isr;
      reg_isr_out(6 downto 2) <= clear_isr_count;
      
      imask_ta_out <= imask_ta;
      
      -- XXX We clear ISR one cycle after the register is read so that
      -- if fastio has a one cycle wait state, the isr can still be read on
      -- the second cycle.
      -- This can create a race condition, if any new events happen while waiting
      -- for it to clear.  So we only clear the bits that were set last time.
      -- We don't clear this bit if in the hypervisor, so that its state can be
      -- properly preserved when freezing/unfreezing.
      if clear_isr='1' then
        for i in 0 to 7 loop
          if clear_isr_bits(i)='1' then
            reg_isr(i) <= '0';
          end if;
        end loop;
        clear_isr <= '0';
        if reg_isr /= x"00" then
          report "CIA" & to_hstring(unit) & " clearing reg_isr (was $" & to_hstring(reg_isr) & ", bits to clear = $"
            & to_hstring(clear_isr_bits) & ")";
        end if;
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
        reg_isr(7)<='0'; irq<='1';
      end if;
      
      prev_todclock <= todclock;
      if todclock='0' and prev_todclock='1' and hypervisor_mode='0' then
        if (todcounter >= (5 - 1) and reg_50hz='1')
          or (todcounter = (6 - 1) and reg_50hz='0')
        then
          todcounter <= 0;
          if( reg_tod_dsecs(3 downto 0) = 9) then
            reg_tod_dsecs(3 downto 0) <= "0000";
            if( reg_tod_secs(3 downto 0) = 9) then
              reg_tod_secs(3 downto 0) <= "0000";
              if( reg_tod_secs(7 downto 4) = 5) then
                reg_tod_secs(7 downto 4) <= "0000";
                if( reg_tod_mins(3 downto 0) = 9) then
                  reg_tod_mins(3 downto 0) <= "0000";
                  if( reg_tod_mins(7 downto 4) = 5) then
                    reg_tod_mins(7 downto 4) <= "0000";
                    if( reg_tod_hours(6 downto 4) = 1) then
                      if( reg_tod_hours(3 downto 0) = 1) then
                        reg_tod_hours(3 downto 0) <= "0000";
                        reg_tod_hours(6 downto 4) <= "000";
                        if(reg_tod_ampm = '1') then
                          reg_tod_ampm <= '0';
		        else
		          reg_tod_ampm <= '1';
		        end if;
		      else
                        reg_tod_hours(3 downto 0) <= reg_tod_hours(3 downto 0) + 1;
		      end if;
                    else
                      if( reg_tod_hours(3 downto 0) = 9) then
                        reg_tod_hours(3 downto 0) <= "0000";
                        reg_tod_hours(6 downto 4) <= reg_tod_hours(6 downto 4) + 1;
                      else
                        reg_tod_hours(3 downto 0) <= reg_tod_hours(3 downto 0) + 1;
                      end if;
                    end if;
                  else
                    reg_tod_mins(7 downto 4) <= reg_tod_mins(7 downto 4) + 1;
		  end if;
                else
                  reg_tod_mins(3 downto 0) <= reg_tod_mins(3 downto 0) + 1;
                end if;
              else
                reg_tod_secs(7 downto 4) <= reg_tod_secs(7 downto 4) + 1;
              end if;
            else
              reg_tod_secs(3 downto 0) <= reg_tod_secs(3 downto 0) + 1;
            end if;
          else
            reg_tod_dsecs(3 downto 0) <= reg_tod_dsecs(3 downto 0) + 1;
          end if;
        else
          if hypervisor_mode='0' then
            todcounter <= todcounter + 1;
          end if;
        end if;
      end if;

      -- Look for timera and timerb tick events
      prev_countin <= countin;
      reg_timera_underflow <= '0';
--      report "CIA reg_timera_start=" & std_logic'image(reg_timera_start) & ", phi0=" & std_logic'image(phi0_1mhz);
      if reg_timera_start='1' and hypervisor_mode='0' then
        if reg_timera = x"FFFF" and reg_timera_has_ticked='1' then
          -- underflow
          report "CIA" & to_hstring(unit) & " timera underflow (reg_serialport_direction="
            & std_logic'image(reg_serialport_direction) & ", sdr_bits_remaining = "
            & integer'image(sdr_bits_remaining) & ", sdr_bit_alternate="
            & std_logic'image(sdr_bit_alternate);
          reg_isr(0) <= '1';
          reg_timera_underflow <= '1';
          if reg_timera_oneshot='0' then
            reg_timera <= reg_timera_latch;
          else
            reg_timera_start <= '0';
          end if;
          reg_timera_has_ticked <= '0';

          if reg_serialport_direction='1' and sdr_bits_remaining /= 0 then
            -- Output next bit of serial shift register
            -- This should happen at only 1/2 the phi clock, so we need to
            -- shift out only every other time we get here.
            -- When empty, we assert the serial port interrupt bit
            sdr_bit_alternate <= not sdr_bit_alternate;
            -- data is shifted out on negative edge of countout
            -- pin.
            countout <= sdr_bit_alternate;
            if sdr_bit_alternate='0' then
              spout <= reg_sdr_data(0);
              reg_sdr_data(6 downto 0) <= reg_sdr_data(7 downto 1);
              reg_sdr_data(7) <= '0';
              report "Shifting out bit, " & integer'image(sdr_bits_remaining-1) & " to go.";
              
              sdr_bits_remaining <= sdr_bits_remaining - 1;
              if sdr_bits_remaining = 1 then
                -- Shifted out last bit, so set bit in the ISR to
                -- indicate this
                reg_isr(3) <= '1';
                report "Asserting shift register ISR flag";
              end if;
            end if;
          end if;
        end if;
        case reg_timera_tick_source is
          when '0' =>
            -- phi2 pulses
            if phi0_1mhz ='1' then
              report "CIA" & to_hstring(unit) &  " timera ticked down to $" & to_hstring(reg_timera);
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
      if reg_timerb_start='1' and hypervisor_mode='0' then
        report "CIA" & to_hstring(unit) & " timerb running. reg_timerb = $" & to_hstring(reg_timerb);
        if reg_timerb = x"FFFF" and reg_timerb_has_ticked='1' then
          -- underflow
          report "CIA" & to_hstring(unit) & " timerb underflow";
          reg_isr(1) <= '1';
          if reg_timerb_oneshot='0' then
            report "CIA" & to_hstring(unit) & " timerb set from latch";
            reg_timerb <= reg_timerb_latch;
          else
            report "CIA" & to_hstring(unit) & " setting reg_timerb_start to " & std_logic'image(fastio_wdata(0));
            reg_timerb_start <= '0';
          end if;
          reg_timerb_has_ticked <= '0';
        end if;
        case reg_timerb_tick_source is
          when "00" => -- phi2 pulses
            if phi0_1mhz ='1' then
              if reg_timerb /= x"0000" then
                report "CIA" & to_hstring(unit) & " timerb ticking down to $" & to_hstring(to_unsigned(to_integer(reg_timerb) - 1,16))
                  & " from $" & to_hstring(reg_timerb);
                reg_timerb <= to_unsigned(to_integer(reg_timerb) - 1,16);
              else
                report "CIA" & to_hstring(unit) & " timerb ticking down to -1"
                  & " from $" & to_hstring(reg_timerb);
                reg_timerb <= (others => '1');
              end if;
              reg_timerb_has_ticked <= '1';
            end if;                
          when "01" => -- CNT transitions
            -- positive CNT transitions
            if reg_timera_underflow='1' or reg_timerb_tick_source(1)='0' then
              if countin='1' and prev_countin='0' then
                report "CIA" & to_hstring(unit) & " timerb ticking down to $" & to_hstring(reg_timerb);
                reg_timerb <= reg_timerb - 1;
                reg_timerb_has_ticked <= '1';
              end if;
            end if; 
          when "10" => -- Timer A underflows
            if reg_timera_underflow='1' then
              report "CIA" & to_hstring(unit) & " timerb ticking down to $" & to_hstring(reg_timerb);
              reg_timerb <= reg_timerb - 1;
              reg_timerb_has_ticked <= '1';
            end if;
          when "11" => -- Timer A underflows, but only while CNT is high
            if reg_timera_underflow='1' and countin='1' then
              report "CIA" & to_hstring(unit) & " timerb ticking down to $" & to_hstring(reg_timerb);
              reg_timerb <= reg_timerb - 1;
              reg_timerb_has_ticked <= '1';
            end if;
          when others => null;
        end case;
      end if;
      
      -- Calculate read value for porta and portb
      
      reg_porta_read <= ddr_pick(reg_porta_ddr,std_logic_vector(portain_delayed),reg_porta_out);        
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
        register_number(7 downto 5) := "000";
        if hypervisor_mode='1' then
          register_number(4) := fastio_address(4);
        else
          register_number(4) := '0';
        end if;
        register_number(3 downto 0) := fastio_address(3 downto 0);
        case register_number is
          when x"01" =>
            -- Reading or writing port B strobes PC high for 1 cycle
            pcout <= '1';
            strobe_pc <= '1';
          when x"08" => read_tod_latched <='0';
          when x"0b" =>
            read_tod_latched <='1';
            read_tod_mins <= reg_tod_mins;
            read_tod_secs <= reg_tod_secs;
            read_tod_dsecs <= reg_tod_dsecs;
          when x"0d" =>
            -- Reading ICR/ISR clears all interrupts
            clear_isr <= '1';
            clear_isr_bits <= reg_isr;
            clear_isr_count <= clear_isr_count + 1;
          when others => null;
        end case;
      end if;

      portbout <= reg_portb_out or (not reg_portb_ddr);
      portaddr <= reg_porta_ddr;
      portaout <= reg_porta_out or (not reg_porta_ddr);
      
      -- Check for register writing
      if fastio_write='1' and cs='1' then
        --report "writing $" & to_hstring(fastio_wdata)
        --  & " to CIA register $" & to_hstring(register_number) severity note;
        register_number(7 downto 5) := "000";
        if hypervisor_mode='1' then
          register_number(4) := fastio_address(4);
        else
          register_number(4) := '0';
        end if;
        register_number(3 downto 0) := fastio_address(3 downto 0);
        case register_number is
          when x"00" =>
            -- $DD00 writes are for IEC serial port.
            -- We delay the writes to the correct cycle of the instruction
            -- But only for the IEC output lines
            reg_porta_out(2 downto 0) <= std_logic_vector(fastio_wdata(2 downto 0));
            reg_porta_out(7 downto 6) <= std_logic_vector(fastio_wdata(7 downto 6));
            if cpu_slow='0' or unit=x"1" or dd00_delay='0' then
              reg_porta_out<=std_logic_vector(fastio_wdata);
            else
              if reg_porta_pending_timer /= 0 then
                reg_porta_out <= reg_porta_pending;
              end if;
              reg_porta_pending <= std_logic_vector(fastio_wdata);
              reg_porta_pending_timer <= 4;
            end if;           
          when x"01" =>  
            
            reg_portb_out<=std_logic_vector(fastio_wdata);
          when x"02" => reg_porta_ddr<=std_logic_vector(fastio_wdata);
          when x"03" => reg_portb_ddr<=std_logic_vector(fastio_wdata);
          when x"04" => reg_timera_latch(7 downto 0) <= fastio_wdata;
          when x"05" => reg_timera_latch(15 downto 8) <= fastio_wdata;
                       if reg_timera_start='0' then
                         -- load timer value now (CIA datasheet, page 6)
                         reg_timera <= fastio_wdata & reg_timera_latch(7 downto 0);
                       end if;
          when x"06" => reg_timerb_latch(7 downto 0) <= fastio_wdata;
          when x"07" => reg_timerb_latch(15 downto 8) <= fastio_wdata;
                       if reg_timerb_start='0' then
                         -- load timer value now (CIA datasheet, page 6)
                         reg_timerb <= fastio_wdata & reg_timerb_latch(7 downto 0);
                         report "timerb high byte set via $Dx07";
                       end if;
          when x"08" =>
            if reg_tod_alarm_edit ='0' then
              reg_tod_dsecs <= fastio_wdata; tod_running<='1';
            else
              reg_alarm_dsecs <= fastio_wdata;
            end if;
          when x"09" => 
            if reg_tod_alarm_edit ='0' then
              reg_tod_secs <= fastio_wdata;
            else
              reg_alarm_secs <= fastio_wdata;
            end if;
          when x"0a" => 
            if reg_tod_alarm_edit ='0' then
              reg_tod_mins <= fastio_wdata;
            else
              reg_alarm_mins <= fastio_wdata;
            end if;
          when x"0b" => 
            if reg_tod_alarm_edit ='0' then
              tod_running <= '0';
              reg_tod_hours <= fastio_wdata(6 downto 0);
              reg_tod_ampm <= fastio_wdata(7);
            else
              reg_alarm_hours <= fastio_wdata(6 downto 0);
              reg_alarm_ampm <= fastio_wdata(7);
            end if;
          when x"0c" =>
            -- Begin shifting data in or out on shift register
            report "CIA" & to_hstring(unit) & " Loading shift register";
            reg_sdr_data <= std_logic_vector(fastio_wdata);
            sdr_bits_remaining <= 8;
            sdr_bit_alternate <= '1';
          when x"0d" =>
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
          when x"0e" =>
            reg_50hz <= fastio_wdata(7);
            reg_serialport_direction <= fastio_wdata(6);
            report "CIA" & to_hstring(unit) & " reg_serialport_direction = " & std_logic'image(fastio_wdata(6));
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
          when x"0f" =>
            reg_tod_alarm_edit <= std_logic(fastio_wdata(7));
            reg_timerb_tick_source <= std_logic_vector(fastio_wdata(6 downto 5));
            if fastio_wdata(4)='1' then
              -- Force loading of timer B now from latch
              reg_timerb <= reg_timerb_latch;
              reg_timerb_has_ticked <= '0';
              report "loading reg_timerb=$" & to_hstring(reg_timerb_latch);
            end if;
            reg_timerb_oneshot <= std_logic(fastio_wdata(3));
            reg_timerb_toggle_or_pulse <= std_logic(fastio_wdata(2));
            reg_timerb_pb7_out <= std_logic(fastio_wdata(1));
            reg_timerb_start <= std_logic(fastio_wdata(0));
            report "setting reg_timerb_start to " & std_logic'image(fastio_wdata(0));

            -- To make freezing easier, CIAs decode 32 registers when in
            -- freezing mode.  This allows us to directly read and set some internal
            -- state, that would otherwise be a real pain to handle.

            -- To make freezing easier, CIAs decode 32 registers when in
            -- freezing mode.  This allows us to directly read and set some internal
            -- state, that would otherwise be a real pain to handle.
            -- @IO:GS $DC10 CIA1:TALATCH Timer A latch value (16 bit)
            -- @IO:GS $DC11 CIA1:TALATCH Timer A latch value (16 bit)
            -- @IO:GS $DC12 CIA1:TALATCH Timer B latch value (16 bit)
            -- @IO:GS $DC13 CIA1:TALATCH Timer B latch value (16 bit)
            -- @IO:GS $DC14 CIA1:TALATCH Timer A current value (16 bit)
            -- @IO:GS $DC15 CIA1:TALATCH Timer A current value (16 bit)
            -- @IO:GS $DC16 CIA1:TALATCH Timer B current value (16 bit)
            -- @IO:GS $DC17 CIA1:TALATCH Timer B current value (16 bit)
            -- @IO:GS $DC18.0-3 CIA1:TOD!JIF TOD 10ths of seconds value
            -- @IO:GS $DC18.4 CIA1:IMTB Interrupt mask for Timer B
            -- @IO:GS $DC18.5 CIA1:IM!ALRM Interrupt mask for TOD alarm
            -- @IO:GS $DC18.6 CIA1:IMSP Interrupt mask for shift register (serial port)
            -- @IO:GS $DC18.7 CIA1:IMFLG Interrupt mask for FLAG line
            -- @IO:GS $DC19 CIA1:TODSEC TOD Alarm seconds value
            -- @IO:GS $DC1A CIA1:TODMIN TOD Alarm minutes value
            -- @IO:GS $DC1B.0-6 CIA1:TOD!HOUR TOD hours value
            -- @IO:GS $DC1B.7 CIA1:TOD!AMPM TOD AM/PM flag
            -- @IO:GS $DC1C.0-6 CIA1:ALRMJIF TOD Alarm 10ths of seconds value (actually all 8 bits)
            -- @IO:GS $DC1C.7 CIA1:DD00!DELAY Enable delaying writes to $DD00 by 3 cycles to match real 6502 timing
            -- @IO:GS $DC1D CIA1:ALRMSEC TOD Alarm seconds value
            -- @IO:GS $DC1E CIA1:ALRMMIN TOD Alarm minutes value
            -- @IO:GS $DC1F.0-6 CIA1:ALRM!HOUR TOD Alarm hours value
            -- @IO:GS $DC1F.7 CIA1:ALRM!AMPM TOD Alarm AM/PM flag

            -- @IO:GS $DD10 CIA2:TALATCH Timer A latch value (16 bit)
            -- @IO:GS $DD11 CIA2:TALATCH Timer A latch value (16 bit)
            -- @IO:GS $DD12 CIA2:TALATCH Timer B latch value (16 bit)
            -- @IO:GS $DD13 CIA2:TALATCH Timer B latch value (16 bit)
            -- @IO:GS $DD14 CIA2:TALATCH Timer A current value (16 bit)
            -- @IO:GS $DD15 CIA2:TALATCH Timer A current value (16 bit)
            -- @IO:GS $DD16 CIA2:TALATCH Timer B current value (16 bit)
            -- @IO:GS $DD17 CIA2:TALATCH Timer B current value (16 bit)
            -- @IO:GS $DD18.0-3 CIA2:TOD!JIF TOD 10ths of seconds value
            -- @IO:GS $DD18.4 CIA2:IMTB Interrupt mask for Timer B
            -- @IO:GS $DD18.5 CIA2:IM!ALRM Interrupt mask for TOD alarm
            -- @IO:GS $DD18.6 CIA2:IMSP Interrupt mask for shift register (serial port)
            -- @IO:GS $DD18.7 CIA2:IMFLG Interrupt mask for FLAG line
            -- @IO:GS $DD19 CIA2:TODSEC TOD Alarm seconds value
            -- @IO:GS $DD1A CIA2:TODMIN TOD Alarm minutes value
            -- @IO:GS $DD1B.0-6 CIA2:TOD!HOUR TOD hours value
            -- @IO:GS $DD1B.7 CIA2:TOD!AMPM TOD AM/PM flag
            -- @IO:GS $DD1C.0-6 CIA2:ALRMJIF TOD Alarm 10ths of seconds value (actually all 8 bits)
            -- @IO:GS $DD1C.7 CIA2:DD00!DELAY Enable delaying writes to $DD00 by 3 cycles to match real 6502 timing
            -- @IO:GS $DD1D CIA2:ALRMSEC TOD Alarm seconds value
            -- @IO:GS $DD1E CIA2:ALRMMIN TOD Alarm minutes value
            -- @IO:GS $DD1F.0-6 CIA2:ALRM!HOUR TOD Alarm hours value
            -- @IO:GS $DD1F.7 CIA2:ALRM!AMPM TOD Alarm AM/PM flag
            
          when x"10" => reg_timera_latch(7 downto 0) <= fastio_wdata;
          when x"11" => reg_timera_latch(15 downto 8) <= fastio_wdata;
          when x"12" => reg_timerb_latch(7 downto 0) <= fastio_wdata;
          when x"13" => reg_timerb_latch(15 downto 8) <= fastio_wdata;
          when x"14" => reg_timera(7 downto 0) <= fastio_wdata;
          when x"15" => reg_timera(15 downto 8) <= fastio_wdata;
          when x"16" => reg_timerb(7 downto 0) <= fastio_wdata;
          when x"17" => reg_timerb(15 downto 8) <= fastio_wdata;
          when x"18" => reg_tod_dsecs(3 downto 0) <= fastio_wdata(3 downto 0);
                        imask_flag <= fastio_wdata(7);
                        imask_serialport <= fastio_wdata(6);
                        imask_alarm <= fastio_wdata(5);
                        imask_tb <= fastio_wdata(4);
          when x"19" => reg_tod_secs(6 downto 0) <= fastio_wdata(6 downto 0);
                        imask_ta <= fastio_wdata(7);
          when x"1a" => reg_tod_mins <= fastio_wdata;
          when x"1b" => reg_tod_hours <= fastio_wdata(6 downto 0);
                        reg_tod_ampm <= fastio_wdata(7);
          when x"1c" => reg_alarm_dsecs <= fastio_wdata;
                        dd00_delay <= fastio_wdata(7);
          when x"1d" => reg_alarm_secs <= fastio_wdata;
          when x"1e" => reg_alarm_mins <= fastio_wdata;
          when x"1f" => reg_alarm_hours <= fastio_wdata(6 downto 0);
                        reg_alarm_ampm <= fastio_wdata(7);
          when others => null;
        end case;
      end if;
    end if;
  end process;

end behavioural;
