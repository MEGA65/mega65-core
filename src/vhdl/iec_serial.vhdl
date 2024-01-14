use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

-- on Pi1541 test unit:
-- ATN - purple
-- SRQ - white
-- DATA - green
-- CLK - blue

entity iec_serial is
  generic (
    cpu_frequency : integer;
    with_debug : boolean := false
    );
  port (
    reset_in : in std_logic := '1';
    clock : in std_logic;
    clock81 : in std_logic;
    irq : out std_logic := '1';

    --------------------------------------------------
    -- CBM floppy serial port
    --------------------------------------------------
    fastio_addr : in unsigned(19 downto 0);
    fastio_write : in std_logic;
    fastio_read : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0);

    debug_state : out unsigned(11 downto 0);
    debug_usec : out unsigned(7 downto 0);
    debug_msec : out unsigned(7 downto 0);
    debug_waits : out unsigned(7 downto 0);
    iec_state_reached : out unsigned(11 downto 0);

    --------------------------------------------------
    -- CBM floppy serial port
    --------------------------------------------------
    iec_reset_n : out std_logic := '1';
    iec_atn_en_n : out std_logic := '1';
    iec_clk_en_n : out std_logic := '1';
    iec_data_en_n : out std_logic := '1';
    iec_srq_en_n : out std_logic := '1';
    iec_clk_i : in std_logic;
    iec_data_i : in std_logic;
    iec_srq_i : in std_logic

    );
end iec_serial;

architecture questionable of iec_serial is

  signal iec_irq : unsigned(7 downto 0) := x"00";
  signal iec_status : unsigned(7 downto 0) := x"00";
  signal iec_data : unsigned(7 downto 0) := x"00";
  signal iec_data_out : unsigned(7 downto 0) := x"00";
  signal iec_devinfo : unsigned(7 downto 0) := x"00";

  signal iec_cmd : unsigned(7 downto 0) := x"00";
  signal iec_new_cmd : std_logic := '0';

  -- C= fast serial protocol does not send fast byte prior
  -- to ATN if a device is listening (as in that case, it
  -- would treat the byte as data)
  signal iec_dev_listening : std_logic := '0';

  signal iec_state : integer := 0;
  signal last_iec_state : integer := 0;
  signal prev_iec_state : integer := 0;
  signal iec_busy : std_logic := '0';
  signal iec_under_attention : std_logic := '0';
  signal send_eoi : std_logic := '0';
  signal eoi_detected : std_logic := '0';

  signal wait_clk_high : std_logic := '0';
  signal wait_clk_low : std_logic := '0';
  signal wait_data_high : std_logic := '0';
  signal wait_data_low : std_logic := '0';
  signal wait_srq_high : std_logic := '0';
  signal wait_srq_low : std_logic := '0';

  signal not_waiting_usec : boolean := true;
  signal not_waiting_msec : boolean := true;
  signal wait_usec : integer := 0;
  signal wait_msec : integer := 0;

  signal cycles : integer := 0;
  signal usecs : integer := 0;
  signal usec_toggle : std_logic := '0';
  signal msec_toggle : std_logic := '0';
  signal last_usec_toggle : std_logic := '0';
  signal timing_sync_toggle : std_logic := '0';
  signal last_timing_sync_toggle : std_logic := '0';

  signal last_iec_data : std_logic := 'U';
  signal last_iec_clk : std_logic := 'U';
  signal last_iec_srq : std_logic := 'U';

  signal debug_ram_write : std_logic := '0';
  signal debug_ram_waddr : integer := 0;
  signal debug_ram_waddr_int : integer := 0;
  signal debug_ram_raddr : integer := 0;
  signal debug_ram_raddr_int : integer := 0;
  signal debug_ram_wdata : unsigned(7 downto 0) := x"00";
  signal debug_ram_rdata : unsigned(7 downto 0);
  signal debug_ram_wdata2 : unsigned(7 downto 0) := x"00";
  signal debug_ram_rdata2 : unsigned(7 downto 0);
  signal debug_ram_wdata3 : unsigned(7 downto 0) := x"00";
  signal debug_ram_rdata3 : unsigned(7 downto 0);
  signal debug_ram_wdata4 : unsigned(7 downto 0) := x"00";
  signal debug_ram_rdata4 : unsigned(7 downto 0);
  signal debug_ram_wdata5 : unsigned(7 downto 0) := x"00";
  signal debug_ram_rdata5 : unsigned(7 downto 0);
  signal debug_ram_read_select : integer range 2 to 5 := 2;
  signal debug_state_counter : integer range 0 to 65535 := 0;
  signal iec_clk_o_int : std_logic := '0';
  signal iec_data_o_int : std_logic := '0';
  signal iec_srq_o_int : std_logic := '0';
  signal iec_atn_int : std_logic := '0';
  signal iec_reset_int : std_logic := '0';

  signal initial_srq_i : std_logic := '1';

  signal probe_jiffydos : std_logic := '0';
  signal jiffydos_enabled : std_logic := '1';
  signal c128fast_enabled : std_logic := '0';

  signal data_low_observed : std_logic := '0';

  signal divisor_1mhz : integer := 81 - 1;

  -- Table of IEC serial protocol timing constants
  constant c_t_r     : integer :=  200;  -- C64 PRG says >= 20 usec
  constant c_t_tk    : integer :=   40;  -- C64 PRG says >= 20 usec
  constant c_t_dc_ms : integer :=   64;  -- C64 PRG says can be infinte, we
                                         -- limit to 64 milliseconds
  constant c_t_bb    : integer :=  100;  -- C64 PRG says >= 100 usec
  constant c_t_ha_ms : integer :=   64;  -- = T_H in C64 PRG, infinite
  constant c_t_st    : integer :=   70;  -- C64 PRG says >= 20 usec
  constant c_t_vt    : integer :=   70;  -- C64 PRG says >= 20 usec
  constant c_t_al    : integer := 1000;  -- Not specified by C64 PRG
  constant c_t_ac    : integer :=   20;  -- Not specified by C64 PRG
  constant c_t_at_ms : integer :=    1;  -- C64 PRG says 1 ms
  constant c_t_h_ms  : integer :=   64;  -- C64 PRG says 64 ms
  constant c_t_ne    : integer :=   40;  -- C64 PRG says 40 usec
  constant c_t_f     : integer := 1000;  -- C64 PRG says 20 -- 1000 usec
  constant c_t_ye    : integer :=  250;  -- C64 PRG says 250
  constant c_t_ei    : integer :=   80;  -- C64 PRG says min 60
  constant c_t_ar    : integer :=   20;  -- Not specified by C64 PRG

  constant c_t_jt    : integer :=  600;  -- JiffyDOS delay after turn-around
  constant c_t_jd    : integer :=  320;  -- JiffyDOS CLK hold time for detection
  constant c_t_j0    : integer :=   37;  -- JiffyDOS RX setup time
  constant c_t_j1    : integer :=   14;  -- JiffyDOS RX start time
  constant c_t_j2    : integer :=   10;  -- JiffyDOS RX 
  constant c_t_j3    : integer :=   11;  -- JiffyDOS RX 
  constant c_t_j4    : integer :=   11;  -- JiffyDOS RX 
  constant c_t_j5    : integer :=   13;  -- JiffyDOS RX 

  constant c_t_j6    : integer :=   10;  -- JiffyDOS TX 
  constant c_t_j7    : integer :=   12;  -- JiffyDOS TX 
  constant c_t_j8    : integer :=   12;  -- JiffyDOS TX 
  constant c_t_j9    : integer :=   12;  -- JiffyDOS TX 
  constant c_t_j10   : integer :=   13;  -- JiffyDOS TX 
  constant c_t_j11   : integer :=   5;  -- JiffyDOS TX 
  constant c_t_jr    : integer :=   15;  -- JiffyDOS TX
  

  constant c_t_fs    : integer :=    5;  -- C128 does 5usec 
  constant c_t_fv    : integer :=    5;  -- C128 does 5usec 
  constant c_t_ff    : integer :=    40;  -- 

  constant c_t_pullup : integer :=   5;  -- Rise-time allowance for IEC bus lines
  
  signal t_r : integer;
  signal t_tk : integer;
  signal t_dc_ms : integer := 0;
  signal t_bb : integer;
  signal t_ha_ms : integer := 0;
  signal t_st : integer;
  signal t_vt : integer;
  signal t_al : integer;
  signal t_ac : integer;
  signal t_at_ms : integer := 0;
  signal t_h_ms : integer := 0;
  signal t_ne : integer;
  signal t_f : integer;
  signal t_ye : integer;
  signal t_ei : integer;
  signal t_ar : integer;

  signal t_at : integer;
  signal t_ha : integer;
  signal t_h : integer;
  signal t_dc : integer;

  signal t_jd    : integer :=  300;  -- JiffyDOS solicitation CLK hold time
  signal t_jt    : integer :=  600;  -- JiffyDOS delay after turn-around
  signal t_j0    : integer :=   37;  -- JiffyDOS RX setup time
  signal t_j1    : integer :=   14;  -- JiffyDOS RX start time
  signal t_j2    : integer :=   10;  -- JiffyDOS RX 
  signal t_j3    : integer :=   11;  -- JiffyDOS RX 
  signal t_j4    : integer :=   11;  -- JiffyDOS RX 
  signal t_j5    : integer :=   13;  -- JiffyDOS RX 
  signal t_j6    : integer :=   10;  -- JiffyDOS TX 
  signal t_j7    : integer :=   12;  -- JiffyDOS TX 
  signal t_j8    : integer :=   12;  -- JiffyDOS TX 
  signal t_j9    : integer :=   12;  -- JiffyDOS TX 
  signal t_j10   : integer :=   13;  -- JiffyDOS TX 
  signal t_j11   : integer :=   5;  -- JiffyDOS TX 
  signal t_jr    : integer :=   15;  -- JiffyDOS TX
  

  signal t_fs    : integer :=    5;  -- C128 does 5usec 
  signal t_fv    : integer :=    5;  -- C128 does 5usec 
  signal t_ff    : integer :=    40;  -- 

  signal t_pullup : integer :=   5;  -- Rise-time allowance for IEC bus lines
    
  signal ten_zeroes : unsigned(9 downto 0) := (others => '0');
  
  signal reset_timing_now : std_logic := '1';

  signal prev_iec_bus_state : unsigned(7 downto 0) := (others => '0');

  signal release_atn_when_done : std_logic := '0';
  
begin

  -- Note that we put RX on bit 6, so that the common case of LOADing can be a
  -- little faster, by allowing BIT $D697 / BVC *-3 to be a very tight loop
  -- for waiting for bytes.

  -- @IO:GS $D694 AUTOIEC:DATALOG0 Access integrated data logger in IEC controller
  -- @IO:GS $D695 AUTOIEC:DATALOG1 Access integrated data logger in IEC controller
  
  -- @IO:GS $D697.7 AUTOIEC:IRQFLAG Interrupt flag. Set if any IRQ event is triggered.
  -- @IO:GS $D697.6 AUTOIEC:IRQRX Set if a byte has been received from a listener.
  -- @IO:GS $D697.5 AUTOIEC:IRQRDY Set if ready to process a command
  -- @IO:GS $D697.4 AUTOIEC:IRQTO Set if a protocol timeout has occurred, e.g., device not found.
  -- @IO:GS $D697.3 AUTOIEC:IRQEN Enable interrupts if set
  -- @IO:GS $D697.2 AUTOIEC:IRQRXEN Enable RX interrupt source if set
  -- @IO:GS $D697.1 AUTOIEC:IRQRDYEN Enable TX interrupt source if set
  -- @IO:GS $D697.0 AUTOIEC:IRQTOEN Enable timeout interrupt source if set

  -- @IO:GS $D698.7 AUTOIEC:STNODEV Device not present
  -- @IO:GS $D698.6 AUTOIEC:STNOEOI End of Indicate (EOI/EOF)
  -- @IO:GS $D698.5 AUTOIEC:STSRQ State of SRQ line
  -- @IO:GS $D698.4 AUTOIEC:STVERIFY Verify error occurred
  -- @IO:GS $D698.3 AUTOIEC:STC State of CLK line
  -- @IO:GS $D698.2 AUTOIEC:STD State of DATA line
  -- @IO:GS $D698.1 AUTOIEC:STTO Timeout occurred
  -- @IO:GS $D698.0 AUTOIEC:STDDIR Data direction when timeout occurred.

  -- @IO:GS $D699 AUTOIEC:DATA Data byte read from IEC bus
  -- @IO:GS $D69A.7 AUTOIEC:PRESENT Device is present
  -- @IO:GS $D69A.5-6 AUTOIEC:PROT Device protocol support (5=C128/C65 FAST, bit 6 = JiffyDOS(tm))
  -- @IO:GS $D69A.4 AUTOIEC:DIATN Device is currently held under attention
  -- @IO:GS $D69A.0-3 AUTOIEC:DEVNUM Lower 4 bits of currently selected device number

  ram1: if with_debug generate
    debugram0: entity work.ram8x4096_sync
      port map (
        clkr => clock,
        clkw => clock,
        cs => '1',
        w => debug_ram_write,
        write_address => debug_ram_waddr,
        address => debug_ram_raddr,
        wdata => debug_ram_wdata,
        rdata => debug_ram_rdata
        );
    end generate;

  ram2: if with_debug generate
    debugram0: entity work.ram8x4096_sync
      port map (
        clkr => clock,
        clkw => clock,
        cs => '1',
        w => debug_ram_write,
        write_address => debug_ram_waddr,
        address => debug_ram_raddr,
        wdata => debug_ram_wdata2,
        rdata => debug_ram_rdata2
        );
    end generate;

  ram3: if with_debug generate
    debugram0: entity work.ram8x4096_sync
      port map (
        clkr => clock,
        clkw => clock,
        cs => '1',
        w => debug_ram_write,
        write_address => debug_ram_waddr,
        address => debug_ram_raddr,
        wdata => debug_ram_wdata3,
        rdata => debug_ram_rdata3
        );
    end generate;

  ram4: if with_debug generate
    debugram0: entity work.ram8x4096_sync
      port map (
        clkr => clock,
        clkw => clock,
        cs => '1',
        w => debug_ram_write,
        write_address => debug_ram_waddr,
        address => debug_ram_raddr,
        wdata => debug_ram_wdata4,
        rdata => debug_ram_rdata4
        );
    end generate;

  ram5: if with_debug generate
    debugram0: entity work.ram8x4096_sync
      port map (
        clkr => clock,
        clkw => clock,
        cs => '1',
        w => debug_ram_write,
        write_address => debug_ram_waddr,
        address => debug_ram_raddr,
        wdata => debug_ram_wdata5,
        rdata => debug_ram_rdata5
        );
    end generate;

    process (clock,clock81) is

      variable iec_bus_state : unsigned(7 downto 0) := (others => '0');
      
      procedure reset_timing is
      begin
        t_r <= c_t_r;
        t_tk <= c_t_tk;
        t_dc_ms <= c_t_dc_ms;
        t_bb <= c_t_bb;
        t_ha_ms <= c_t_ha_ms;
        t_st <= c_t_st;
        t_vt <= c_t_vt;
        t_al <= c_t_al;
        t_ac <= c_t_ac;
        t_at_ms <= c_t_at_ms;
        t_h_ms <= c_t_h_ms;
        t_ne <= c_t_ne;
        t_f <= c_t_f;
        t_ye <= c_t_ye;
        t_ei <= c_t_ei;
        t_ar <= c_t_ar;

        t_jt <= c_t_jt;
        t_j0 <= c_t_j0;
        t_j1 <= c_t_j1;
        t_j2 <= c_t_j2;
        t_j3 <= c_t_j3;
        t_j4 <= c_t_j4;
        t_j5 <= c_t_j5;
        t_j6 <= c_t_j6;
        t_j7 <= c_t_j7;
        t_j8 <= c_t_j8;
        t_j9 <= c_t_j9;
        t_j10 <= c_t_j10;
        t_j11 <= c_t_j11;
        t_jr <= c_t_jr;
        t_jd <= c_t_jd;
  
        t_fs <= c_t_fs;
        t_fv <= c_t_fv;
        t_ff <= c_t_ff;

        t_pullup <= c_t_pullup;
        
      end procedure;
      
    procedure d(v : std_logic) is
    begin
      if v /= last_iec_data then
        report "SIGNAL: Setting DATA to " & std_logic'image(v);
        last_iec_data <= v;
      end if;
      iec_data_en_n <= v;
      iec_data_o_int <= v;
    end procedure;
    procedure c(v : std_logic) is
    begin
      if v /= last_iec_clk then
        report "SIGNAL: Setting CLK to " & std_logic'image(v);
        last_iec_clk <= v;
      end if;
      iec_clk_en_n <= v;
      iec_clk_o_int <= v;
    end procedure;
    procedure s(v : std_logic) is
    begin
      if v/= last_iec_srq then
        report "SIGNAL: Setting SRQ to " & std_logic'image(v);
        last_iec_srq <= v;
      end if;
      iec_srq_en_n <= v;
      iec_srq_o_int <= v;
    end procedure;
    procedure a(v : std_logic) is
    begin
      report "SIGNAL: Setting ATN to " & std_logic'image(v);
      iec_atn_en_n <= v;
      iec_atn_int <= v;
    end procedure;
    procedure iec_data_out_rotate is
    begin
      -- Rotate byte being sent completely, so repeated sending
      -- of same byte is possible without having to re-write it.
      iec_data_out(6 downto 0) <= iec_data_out(7 downto 1); iec_data_out(7) <= iec_data_out(0);
    end procedure;
    procedure micro_wait(usec_count : integer) is
    begin

      report "micro_wait(" & integer'image(usec_count) & ") called in iec_state = " & integer'image(iec_state);
      
      wait_clk_high <= '0'; wait_clk_low <= '0';
      wait_data_high <= '0'; wait_data_low <= '0';
      wait_srq_high <= '0'; wait_srq_low <= '0';
      wait_msec <= 0;

      wait_usec <= usec_count;
      not_waiting_usec <= false;
      not_waiting_msec <= true;

    end procedure;
  begin

    if rising_edge(clock81) then

      if timing_sync_toggle /= last_timing_sync_toggle then
        last_timing_sync_toggle <= timing_sync_toggle;
        cycles <= 0;
        usecs <= 0;
      elsif cycles < divisor_1mhz then
        cycles <= cycles + 1;
      else
        cycles <= 0;
        usec_toggle <= not usec_toggle;
        if usecs < 999 then
          usecs <= usecs + 1;
        else
          usecs <= 0;
          msec_toggle <= not msec_toggle;
        end if;
      end if;
    end if;

    if fastio_addr(19 downto 4) = x"d369"
      and (to_integer(fastio_addr(3 downto 0))>3)
      and (to_integer(fastio_addr(3 downto 0))<11)
      and fastio_read='1' then
      case fastio_addr(3 downto 0) is
        when x"4" => -- debug read register
          if with_debug then
            fastio_rdata <= debug_ram_rdata;
            report "Reading $" & to_hexstring(debug_ram_rdata) & " from debug RAM address " & integer'image(debug_ram_raddr_int);
          else
            fastio_rdata <= (others => 'Z');
          end if;
        when x"5" => -- debug read register
          if with_debug then
            case debug_ram_read_select is
              when 2 => fastio_rdata <= debug_ram_rdata2;
              when 3 => fastio_rdata <= debug_ram_rdata3;
              when 4 => fastio_rdata <= debug_ram_rdata4;
              when 5 => fastio_rdata <= debug_ram_rdata5;
            end case;
            report "Reading $" & to_hexstring(debug_ram_rdata2) & " from debug RAM2 address " & integer'image(debug_ram_raddr_int);
          else
            fastio_rdata <= (others => 'Z');
          end if;
        when x"6" =>
          if with_debug then
            fastio_rdata <= to_unsigned(debug_ram_raddr_int,8);
          else
            fastio_rdata <= (others => 'Z');
          end if;
        when x"7" => -- Read IRQ register
          fastio_rdata <= iec_irq;
        when x"8" => -- Read from status register
          fastio_rdata <= iec_status;
        when x"9" => -- Read from data register
          fastio_rdata <= iec_data;
        when x"a" => -- Read device info
          fastio_rdata <= iec_devinfo;
        when others => fastio_rdata <= (others => 'Z');
      end case;
    else
      fastio_rdata <= (others => 'Z');
    end if;

    if rising_edge(clock) then

      -- Convert milliseconds to ~micro seconds by x1024
      t_at <= to_integer(to_unsigned(t_at_ms,8)&ten_zeroes);
      t_h <= to_integer(to_unsigned(t_h_ms,8)&ten_zeroes);
      t_ha <= to_integer(to_unsigned(t_ha_ms,8)&ten_zeroes);
      t_dc <= to_integer(to_unsigned(t_dc_ms,8)&ten_zeroes); 
      
      if iec_data_i='0' then
        data_low_observed <= '1';
      end if;
      
      if with_debug then
        iec_bus_state(0) := iec_data_i;
        iec_bus_state(1) := iec_clk_i;
        iec_bus_state(2) := iec_srq_i;
        iec_bus_state(3) := iec_data_o_int;
        iec_bus_state(4) := iec_clk_o_int;
        iec_bus_state(5) := iec_srq_o_int;
        iec_bus_state(6) := iec_atn_int;
        iec_bus_state(7) := iec_reset_int;

        debug_ram_wdata <= iec_bus_state;
        
        debug_ram_wdata2 <= to_unsigned(iec_state,8);
        debug_ram_wdata3 <= to_unsigned(iec_state,16)(15 downto 8);

        debug_ram_wdata4 <= to_unsigned(debug_state_counter,8);
        debug_ram_wdata5 <= to_unsigned(debug_state_counter,16)(15 downto 8);
        
        prev_iec_state <= iec_state;
        prev_iec_bus_state <= iec_bus_state;
        if (iec_state = prev_iec_state) and (iec_bus_state = prev_iec_bus_state) then
          debug_ram_write <= '0';
          if debug_state_counter < 65535 then
            debug_state_counter <= debug_state_counter + 1;
          end if;
        else
          if debug_ram_waddr_int < 4095 then
            debug_ram_write <= '1';
            debug_ram_waddr_int <= debug_ram_waddr_int + 1;
            debug_ram_waddr <= debug_ram_waddr_int + 1;
            debug_state_counter <= 0;
            -- report "Writing $" & to_hexstring(debug_ram_wdata) & " to debug RAM address " & integer'image(debug_ram_waddr_int + 1);
          end if;
        end if;
      end if;

      debug_state <= to_unsigned(iec_state,12);
      debug_usec <= to_unsigned(wait_usec,8);
      debug_msec <= to_unsigned(wait_msec,8);

      debug_waits(0) <= wait_clk_high;
      debug_waits(1) <= wait_clk_low;
      debug_waits(2) <= wait_data_high;
      debug_waits(3) <= wait_data_low;
      debug_waits(4) <= wait_srq_high;
      debug_waits(5) <= wait_srq_low;
      debug_waits(6) <= '0';
      debug_waits(7) <= '0';

      -- Indicate busy status
      iec_irq(5) <= not iec_busy;

      -- Allow easy reading of IEC lines
      iec_status(5) <= iec_srq_i;
      iec_status(3) <= iec_clk_i;
      iec_status(2) <= iec_data_i;

      -- Trigger IRQ if appropriate event has occurred
      if (iec_irq(6) and iec_irq(6-4)) = '1' then
        iec_irq(7) <= '1';
      end if;
      if (iec_irq(5) and iec_irq(5-4)) = '1' then
        iec_irq(7) <= '1';
      end if;
      if (iec_irq(4) and iec_irq(4-4)) = '1' then
        iec_irq(7) <= '1';
      end if;
      if (iec_irq(7) and iec_irq(7-4)) = '1' then
        irq <= '0';
      else
        irq <= '1';
      end if;

      if fastio_addr(19 downto 4) = x"d369"
        and (to_integer(fastio_addr(3 downto 0))>3)
        and (to_integer(fastio_addr(3 downto 0))<11) then
        if fastio_write='1' then
          report "IEC: REG: register write: $" & to_hexstring(fastio_wdata) & " -> reg $" & to_hexstring(fastio_addr(3 downto 0));
          case fastio_addr(3 downto 0) is
            when x"4" =>
              if with_debug then
                case fastio_wdata is
                  when x"00" => debug_ram_raddr <= 0; debug_ram_raddr_int <= 0;
                  when x"01" => if debug_ram_raddr_int < 4095 then
                                  debug_ram_raddr_int <= debug_ram_raddr_int + 1;
                                  debug_ram_raddr <= debug_ram_raddr_int + 1;
                                end if;
                  when x"02" => debug_ram_read_select <= 2;
                  when x"03" => debug_ram_read_select <= 3;
                  when x"04" => debug_ram_read_select <= 4;
                  when x"05" => debug_ram_read_select <= 5;                    
                  when others => null;
                end case;
              end if;
            when x"7" => -- Write to IRQ register
              -- Writing to IRQ bits clears the events
              iec_irq(7) <= iec_irq(7) and not fastio_wdata(7);
              iec_irq(6) <= iec_irq(6) and not fastio_wdata(6);
              iec_irq(5) <= iec_irq(5) and not fastio_wdata(5);
              iec_irq(4) <= iec_irq(4) and not fastio_wdata(4);
              iec_irq(3 downto 0) <= fastio_wdata(3 downto 0);
            when x"8" => -- Write to command register
              iec_cmd <= fastio_wdata;
              iec_new_cmd <= '1';
            when x"9" => -- Write to data register
              iec_data_out <= fastio_wdata;
            when x"a" => -- Write device info
            when others => null;
          end case;
        end if;
      end if;

      if iec_new_cmd='1' then
        report "IEC: Command Dispatch: $" & to_hexstring(iec_cmd);
        iec_new_cmd <= '0';
        case iec_cmd is

          -- Abort existing command
          when x"00" =>
            iec_state <= 0; iec_busy <= '0';
            wait_clk_high <= '0'; wait_clk_low <= '0';
            wait_data_high <= '0'; wait_data_low <= '0';
            wait_srq_high <= '0'; wait_srq_low <= '0';
            wait_usec <= 0; wait_msec <= 0;
          when x"01" => -- Reset controller state
            iec_dev_listening <= '0';
            a('1'); d('1'); c('1'); s('1');
            jiffydos_enabled <= '1';
            report "IEC: Enabling JiffyDOS solicitation via $52 RESET command";
            c128fast_enabled <= '0';

          -- Low-level / bitbashing commands
          when x"41" => -- ATN to +5V
            report "IEC: Released ATN line";
            a('1');
          when x"61" => -- ATN low to 0V
            a('0');
          when x"43" => -- CLK line +5V (bitbashing)
            c('1');
          when x"63" => -- Pull CLK line low to 0V (bitbashing)
            c('0');
          when x"44" => -- DATA line to +5V (bitbashing)
            d('1');
          when x"64" => -- Pull DATA line low to 0V (bitbashing)
            d('0');
          when x"53" => -- SRQ line to +5V (bitbashing)
            s('1');
          when x"73" => -- Pull SRQ line low to 0V (bitbashing)
            s('0');
          when x"52" => -- Drive IEC reset pin 5V
            iec_reset_n <= '1';
            iec_reset_int <= '1';
          when x"72" => -- Drive IEC reset pin 0V
            iec_reset_n <= '0';
            iec_reset_int <= '0';
            
            -- Allow enabling and disabling of JiffyDOS offering
          when x"4A" => jiffydos_enabled <= '1';
                        report "IEC: Enabling JiffyDOS solicitation";
          when x"6A" => jiffydos_enabled <= '0';
                        report "IEC: Disabling JiffyDOS solicitation";
            -- and also c128 fast serial
          when x"46" => c128fast_enabled <= '1';
          when x"66" => c128fast_enabled <= '0';
            
            -- Protocol level commands
          when x"30" => -- Request device attention (send data byte under attention)
            iec_state <= 100;
            iec_busy <= '1';

            wait_clk_high <= '0'; wait_clk_low <= '0';
            wait_data_high <= '0'; wait_data_low <= '0';
            wait_srq_high <= '0'; wait_srq_low <= '0';
            wait_usec <= 0; wait_msec <= 0;

          when x"31" => -- Send byte (without attention)
            iec_dev_listening <= '0';
            iec_state <= 400;
            iec_busy <= '1';
            send_eoi <= '0';

            wait_clk_high <= '0'; wait_clk_low <= '0';
            wait_data_high <= '0'; wait_data_low <= '0';
            wait_srq_high <= '0'; wait_srq_low <= '0';
            wait_usec <= 0; wait_msec <= 0;

          when x"32" => -- Receive byte
            report "IEC: RECEIVE BYTE COMMAND received";
            iec_dev_listening <= '0';
            iec_state <= 300;
            iec_busy <= '1';

            wait_clk_high <= '0'; wait_clk_low <= '0';
            wait_data_high <= '0'; wait_data_low <= '0';
            wait_srq_high <= '0'; wait_srq_low <= '0';
            wait_usec <= 0; wait_msec <= 0;

          when x"33" => -- Send EOI without byte
            -- XXX How do we do this? There is a way, I read about it somewhere.
            -- But can I find it now? Oh no.
          when x"34" => -- Send byte with EOI (clears ATN)
            iec_dev_listening <= '0';
            iec_state <= 400;
            iec_busy <= '1';
            send_eoi <= '1';

            wait_clk_high <= '0'; wait_clk_low <= '0';
            wait_data_high <= '0'; wait_data_low <= '0';
            wait_srq_high <= '0'; wait_srq_low <= '0';
            wait_usec <= 0; wait_msec <= 0;

          when x"35" => -- Turn around from talk to listen
            report "IEC: TURNAROUND COMMAND received";
            iec_dev_listening <= '0';
            iec_state <= 200;
            iec_busy <= '1';

            wait_clk_high <= '0'; wait_clk_low <= '0';
            wait_data_high <= '0'; wait_data_low <= '0';
            wait_srq_high <= '0'; wait_srq_low <= '0';
            wait_usec <= 0; wait_msec <= 0;

          when x"80" => reset_timing_now <= '1';
          when x"81" => t_r <= to_integer(iec_data_out);     iec_data <= to_unsigned(t_r,8);
          when x"82" => t_tk <= to_integer(iec_data_out);    iec_data <= to_unsigned(t_tk,8);
          when x"83" => t_dc_ms <= to_integer(iec_data_out); iec_data <= to_unsigned(t_dc_ms,8);
          when x"84" => t_bb <= to_integer(iec_data_out); iec_data <= to_unsigned(t_bb,8);
          when x"85" => t_ha <= to_integer(iec_data_out); iec_data <= to_unsigned(t_ha,8);
          when x"86" => t_st <= to_integer(iec_data_out); iec_data <= to_unsigned(t_st,8);
          when x"87" => t_vt <= to_integer(iec_data_out); iec_data <= to_unsigned(t_vt,8);
          when x"88" => t_al <= to_integer(iec_data_out); iec_data <= to_unsigned(t_al,8);
          when x"89" => t_ac <= to_integer(iec_data_out); iec_data <= to_unsigned(t_ac,8);
          when x"8A" => t_at_ms <= to_integer(iec_data_out); iec_data <= to_unsigned(t_at_ms,8);
          when x"8B" => t_h_ms <= to_integer(iec_data_out); iec_data <= to_unsigned(t_h_ms,8);
          when x"8C" => t_ne <= to_integer(iec_data_out); iec_data <= to_unsigned(t_ne,8);
          when x"8D" => t_f <= to_integer(iec_data_out&to_unsigned(0,2)); iec_data <= to_unsigned(t_f,10)(9 downto 2);
          when x"8E" => t_ye <= to_integer(iec_data_out); iec_data <= to_unsigned(t_ye,8);
          when x"8F" => t_ei <= to_integer(iec_data_out); iec_data <= to_unsigned(t_ei,8);
          when x"90" => t_ar <= to_integer(iec_data_out); iec_data <= to_unsigned(t_ar,8);
          when x"91" => t_jt <= to_integer(iec_data_out&to_unsigned(0,2)); iec_data <= to_unsigned(t_jt,10)(9 downto 2);
          when x"92" => t_j0 <= to_integer(iec_data_out); iec_data <= to_unsigned(t_j0,8);
          when x"93" => t_j1 <= to_integer(iec_data_out); iec_data <= to_unsigned(t_j1,8);
          when x"94" => t_j2 <= to_integer(iec_data_out); iec_data <= to_unsigned(t_j2,8);
          when x"95" => t_j3 <= to_integer(iec_data_out); iec_data <= to_unsigned(t_j3,8);
          when x"96" => t_j4 <= to_integer(iec_data_out); iec_data <= to_unsigned(t_j4,8);
          when x"97" => t_j5 <= to_integer(iec_data_out); iec_data <= to_unsigned(t_j5,8);
          when x"98" => t_j6 <= to_integer(iec_data_out); iec_data <= to_unsigned(t_j6,8);
          when x"99" => t_j7 <= to_integer(iec_data_out); iec_data <= to_unsigned(t_j7,8);
          when x"9A" => t_j8 <= to_integer(iec_data_out); iec_data <= to_unsigned(t_j8,8);
          when x"9B" => t_j9 <= to_integer(iec_data_out); iec_data <= to_unsigned(t_j9,8);
          when x"9C" => t_j10 <= to_integer(iec_data_out); iec_data <= to_unsigned(t_j10,8);
          when x"9D" => t_j11 <= to_integer(iec_data_out); iec_data <= to_unsigned(t_j11,8);
          when x"9E" => t_jr <= to_integer(iec_data_out); iec_data <= to_unsigned(t_jr,8);
          when x"9F" => t_fs <= to_integer(iec_data_out); iec_data <= to_unsigned(t_fs,8);
          when x"A0" => t_ff <= to_integer(iec_data_out); iec_data <= to_unsigned(t_ff,8);
          when x"A1" => t_pullup <= to_integer(iec_data_out); iec_data <= to_unsigned(t_pullup,8);
          when x"A2" => t_jd <= to_integer(iec_data_out&to_unsigned(0,2)); iec_data <= to_unsigned(t_jd,10)(9 downto 2);
                         
          when x"d0" =>
            -- Trigger begin collecting debug info during job
            debug_ram_waddr_int <= 0;            
                        
          when x"d1" => -- Begin generating a 1KHz pulse train on the DATA
            -- and CLK lines
            iec_dev_listening <= '0';
            iec_state <= 500;
            iec_busy <= '1';

            wait_clk_high <= '0'; wait_clk_low <= '0';
            wait_data_high <= '0'; wait_data_low <= '0';
            wait_srq_high <= '0'; wait_srq_low <= '0';
            wait_usec <= 0; wait_msec <= 0;
            
          when others => null;
        end case;
      end if;

      -- Update usec and msec denominated count-downs
      if usec_toggle /= last_usec_toggle then
        if wait_usec > 0 then
          not_waiting_usec <= false;
          report "TIME: decrementing usec counter to " & integer'image(wait_usec-1);
          wait_usec <= wait_usec - 1;
          if wait_usec = 1 then
            not_waiting_usec <= true;
            -- timeout occurred: Cancel any signal waiting
            wait_clk_high <= '0'; wait_clk_low <= '0';
            wait_data_high <= '0'; wait_data_low <= '0';
            wait_srq_high <= '0'; wait_srq_low <= '0';
          end if;
        end if;
        last_usec_toggle <= usec_toggle;
      end if;

      -- Advance state in IEC protocol transaction if the requirements are met
      if (wait_clk_high='1' and iec_clk_i='1') then
        report "WAIT: Used and clearing wait_clk_high";
        wait_clk_high <= '0';
        wait_usec <= 0; wait_msec <= 0;
      end if;
      if (wait_clk_low='1' and iec_clk_i='0') then
        report "WAIT: Used and clearing wait_clk_low";
        wait_clk_low <= '0';
        wait_usec <= 0; wait_msec <= 0;
      end if;
      if (wait_data_high='1' and iec_data_i='1') then
        report "WAIT: Used and clearing wait_data_high";
        wait_data_high <= '0';
        wait_usec <= 0; wait_msec <= 0;
      end if;
      if (wait_data_low='1' and iec_data_i='0') then
        report "WAIT: Used and clearing wait_data_low";
        wait_data_low <= '0';
        wait_usec <= 0; wait_msec <= 0;
      end if;
      if (wait_srq_high='1' and iec_srq_i='1') then
        report "WAIT: Used and clearing wait_srq_high";
        wait_srq_high <= '0';
        wait_usec <= 0; wait_msec <= 0;
      end if;
      if (wait_srq_low='1' and iec_srq_i='0') then
        report "WAIT: Used and clearing wait_srq_low";
        wait_srq_low <= '0';
        wait_usec <= 0; wait_msec <= 0;
      end if;

      if (iec_state >0)
        and (
          (wait_clk_low='0' or iec_clk_i='0')
          and (wait_clk_high='0' or iec_clk_i='1')
          and (wait_data_low='0' or iec_data_i='0')
          and (wait_data_high='0' or iec_data_i='1')
          and (wait_srq_low='0' or iec_srq_i='0')
          and (wait_srq_high='0' or iec_srq_i='1')
          and (wait_usec = 0)
          and (wait_msec = 0 )
          )
      then
        if iec_state /= last_iec_state then
          report "iec_state = " & integer'image(iec_state)
            & ", wait_msec = " & integer'image(wait_msec)
            & ", wait_usec = " & integer'image(wait_usec);
          last_iec_state <= iec_state;
        end if;
        iec_state <= iec_state + 1;

        case iec_state is
          -- IDLE state
          when 0 => null;
                    
          -- Request attention from one or more devices
          when 100 =>

            iec_under_attention <= '0';

            if iec_data_out=x"3f" or iec_data_out=x"5f" then
              release_atn_when_done <= '1';
            else
              release_atn_when_done <= '0';
            end if;
            
            -- DATA to 5V
            -- Ensure SRQ is released to 5V
            d('1'); s('1');

            -- Skip C= fast serial signal if a device is
            -- listening, so that it doesn't get mis-interpretted
            -- as data.
            -- XXX - Actually only required if the device supports
            -- C= fast serial?
            if iec_dev_listening='1' or c128fast_enabled='0' then
              iec_state <= 120;
            end if;

          -- Send data byte $FF using SRQ as clock to indicate our ability
          -- to do C= fast serial
          when 101 => s('1'); micro_wait(t_fs);
          when 102 => s('0'); micro_wait(t_fv);
          when 103 => s('1'); micro_wait(t_fs);
          when 104 => s('0'); micro_wait(t_fv);
          when 105 => s('1'); micro_wait(t_fs);
          when 106 => s('0'); micro_wait(t_fv);
          when 107 => s('1'); micro_wait(t_fs);
          when 108 => s('0'); micro_wait(t_fv);
          when 109 => s('1'); micro_wait(t_fs);
          when 110 => s('0'); micro_wait(t_fv);
          when 111 => s('1'); micro_wait(t_fs);
          when 112 => s('0'); micro_wait(t_fv);
          when 113 => s('1'); micro_wait(t_fs);
          when 114 => s('0'); micro_wait(t_fv);
          when 115 => s('1'); micro_wait(t_fs);
          when 116 => s('0'); micro_wait(t_fv);

          when 117 | 118 | 119 => null;

          when 120 =>
            -- Prepare all IEC lines:
            a('0'); -- ATN to 0V
            d('1'); -- DATA to 5V
            s('1'); -- Ensure SRQ is released to 5V

            -- Clear relevant status bits
            iec_status(7) <= '0'; -- no DEVICE NOT FOUND error (yet)
            iec_status(1) <= '0'; -- No timeout
            iec_status(0) <= '0'; -- No data direction during timeout

            -- Record the device ID being requested
            iec_devinfo(4 downto 0) <= iec_data_out(4 downto 0);
            -- Device not (yet) detected
            iec_devinfo(7) <= '0';

            -- And reset the device protocol capability flag if we are sending
            -- a TALK or LISTEN
            case iec_data_out(7 downto 5) is
              when "010" | "001" =>
                iec_devinfo(6 downto 5) <= "00";
                probe_jiffydos <= jiffydos_enabled;
              when others =>
                probe_jiffydos <= '0';
            end case;
            
            -- Wait a little while before asserting CLK
            micro_wait(t_ac);

          when 121 =>
            c('0'); -- CLK to 0V
            -- Wait before releasing CLK after ATN has been responded to
            micro_wait(t_at);

          when 122 =>
            c('1');  -- Release CLK to 5V
            if prev_iec_state /= iec_state then
              report "IEC: Checking if DATA went low (device responded to ATN)";
            end if;
            if iec_data_i = '0' then
              iec_state <= iec_state + 2; -- Proceed with ATN send
              wait_msec <= 0;
            else
              -- ATN response timed out, proceed to DEVICE NOT PRESENT in next state
              null;
            end if;
          when 123 =>
            -- Timeout has occurred: DEVICE NOT PRESENT
            -- (actually it means that there are no devices at all)
            report "IEC: Attention timeout: No devices on bus";
            iec_state_reached <= to_unsigned(iec_state,12);
            iec_state <= 0;
            iec_devinfo <= x"00";
            iec_status(7) <= '1'; -- DEVICE NOT PRESENT
            iec_status(1) <= '1'; -- TIMEOUT OCCURRED ...
            iec_status(0) <= '1'; -- ... WHILE WE WERE TALKING

            -- Release all IEC lines
            a('1');
            c('1');

            iec_busy <= '0';

          when 124 =>
            -- At least one device has responded
            report "IEC: At least one device responded by pulling DATA low.";

            -- Now wait upto 64ms for listener ready for data
            -- This period is actually unconstrained in the protcol,
            -- but we place a limit on it for now.
            -- However, as soon as data goes high, we have to wait 40 usec,
            -- and then continue. If we wait <40 usec the drive will miss
            -- the pulse, and think it has to wait for another pulse on CLK.
            -- If we wait >200usec, then it will think it is EOI.
            micro_wait(t_ha);
            wait_data_high <= '1';

          when 125 =>
            if iec_data_i='0' then
              report "IEC: TIMEDOUT waiting for DATA to go high";
              iec_state <= iec_state + 2;
            else
              report "IEC: Saw DATA go high: Advancing";
              micro_wait(t_ne);
            end if;

          when 126 =>
            -- Listener ready for data
            iec_state <= iec_state + 2;
            wait_msec <= 0;
            c('1'); -- CLK to 5V

          when 127 =>
            -- Timeout on listener ready for data

            -- Timeout has occurred: DEVICE NOT PRESENT
            -- (which is not strictly true, it's that device
            -- did not respond in time)
            iec_state_reached <= to_unsigned(iec_state,12);
            iec_state <= 0;
            iec_busy <= '0';
            iec_devinfo <= x"00";
            iec_status(7) <= '1'; -- DEVICE NOT PRESENT
            iec_status(1) <= '1'; -- TIMEOUT OCCURRED ...
            iec_status(0) <= '1'; -- ... WHILE WE WERE TALKING

            -- Release all IEC lines
            a('1');
            c('1');

          when 128 =>
            -- Okay, all listeners are ready for the data byte.
            -- So send it using the slow protocol.
            -- After sending 8th bit, we do the JiffyDOS(tm) check
            -- by delaying, and waiting to see if the data line
            -- is pulled low by a device, indicating that it speaks
            -- the JiffyDOS protocol.  More on that when we get to it.

            -- Send the first 7 bits
            report "IEC: Sending data byte $" & to_hexstring(iec_data_out) & "  under ATN";
            null;
          when 129 => c('0'); d(iec_data_out(0)); micro_wait(t_st);
          when 130 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_vt);
                      report "IEC: Sent bit 0 = " & std_logic'image(iec_data_out(0));                      
          when 131 => c('0'); d(iec_data_out(0)); micro_wait(t_st);
          when 132 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_vt);
                      report "IEC: Sent bit 1 = " & std_logic'image(iec_data_out(0));
          when 133 => c('0'); d(iec_data_out(0)); micro_wait(t_st);
          when 134 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_vt);
                      report "IEC: Sent bit 2 = " & std_logic'image(iec_data_out(0));
          when 135 => c('0'); d(iec_data_out(0)); micro_wait(t_st);
          when 136 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_vt);
                      report "IEC: Sent bit 3 = " & std_logic'image(iec_data_out(0));
          when 137 => c('0'); d(iec_data_out(0)); micro_wait(t_st);
          when 138 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_vt);
                      report "IEC: Sent bit 4 = " & std_logic'image(iec_data_out(0));
          when 139 => c('0'); d(iec_data_out(0)); micro_wait(t_st);
          when 140 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_vt);
                      report "IEC: Sent bit 5 = " & std_logic'image(iec_data_out(0));
          when 141 => c('0'); d(iec_data_out(0)); micro_wait(t_st);
          when 142 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_vt);
                      report "IEC: Sent bit 6 = " & std_logic'image(iec_data_out(0));
          when 143 => c('0'); d(iec_data_out(0)); micro_wait(t_st);                      
          when 144 =>
            -- To do the JiffyDOS detection, we need to make sure the DATA line
            -- has gone high before we start looking for it to go low.
            -- But we need to not release the DATA line too early, so that a normal
            -- 1541 will not capture this as a 1 bit. In theory, the 35 usec
            -- delay from the previous state should ensure this.
            -- Except that it doesn't.  So we make it a bit longer.
            if probe_jiffydos='1' then
              d('1');
            end if;
            micro_wait(t_pullup);
          when 145 =>
            if probe_jiffydos='1' then
              -- Release DATA, and wait for at least 300usec, to see if data
              -- goes low.  If yes, device supports JiffyDOS.
              d('1'); data_low_observed <= '0'; micro_wait(t_jd);
            else
              iec_state <= iec_state + 2;
              micro_wait(t_vt);
            end if;
          when 146 =>
            
            d(iec_data_out(0)); 
            if data_low_observed = '1' then
              if iec_devinfo(6) = '0' then
                report "IEC: Device supports JiffyDOS(tm) protocol. Waiting for DATA to release again.";
              end if;
              -- Record JiffyDOS capability
              iec_devinfo(6) <= '1';
              -- Wait for DATA to be released again
              wait_usec <= 0; wait_data_high <= '1';              
            else
              report "IEC: Device did not indicate support for JiffyDOS(tm) protocol (this is normal, depending on command issued).";
            end if;
          when 147=> c('1'); micro_wait(t_vt);
                      report "IEC: Sent bit 7 = " & std_logic'image(iec_data_out(0));
          -- Now we have sent 7 bits, release data, keeping clock at 0V, and
          -- check for DATA being pulled low
          when 148 => c('0'); d('1');
          when 149 =>
            -- Allow device 1000usec = 1ms to acknowledge byte by
            -- pulling data low
                      micro_wait(t_f);
                      wait_data_low <= '1';
                      report "IEC: Waiting for device to acknowledge byte";
          when 150 =>
            if iec_data_i='0' then
              report "IEC: Device acknowledged receipt of byte";
              iec_state <= iec_state + 2;
              wait_msec <= 0;
            else
              report "IEC: Timedout waiting for device to acknowledge receipt of byte";
            end if;
          when 151 =>
            -- Timeout detected acknowledging byte

            -- Timeout has occurred: DEVICE NOT PRESENT
            -- (which is not strictly true, it's that device
            -- did not respond in time)
            report "IEC: DEVICE NOT PRESENT: Device failed to acknowledge byte";
            iec_state_reached <= to_unsigned(iec_state,12);
            iec_state <= 0;
            iec_devinfo <= x"00";
            iec_status(7) <= '1'; -- DEVICE NOT PRESENT
            iec_status(1) <= '1'; -- TIMEOUT OCCURRED ...
            iec_status(0) <= '1'; -- ... WHILE WE WERE TALKING

            iec_busy <= '0';

          when 152 => micro_wait(t_bb);
          when 153 =>
            -- Successfully sent byte
            report "IEC: Successfully completed sending byte under attention";
            iec_devinfo(7) <= '1';
            iec_busy <= '0';

            iec_dev_listening <= '1';

            iec_state_reached <= to_unsigned(iec_state,12);
            iec_state <= 0;

            if release_atn_when_done='1' then
              a('1');
            end if;
            
            -- TURNAROUND FROM TALKER TO LISTENER
            -- Wait 20 usec, release ATN, wait 20usec
            -- Computer pulls DATA low and releases CLK.
            -- Device then pulls CLK low and releases DATA.

          when 200 => micro_wait(t_r);
          when 201 => a('1'); micro_wait(t_tk);
          when 202 => d('0'); c('1'); micro_wait(t_pullup);   -- Wait only long enough
                                                       -- to ensure CLK has had
                                                       -- time to rise.
          when 203 => micro_wait(t_dc); wait_clk_low <= '1'; -- T(DC) limit (in
                                                           -- milli seconds)
          when 204 => if iec_clk_i='1' then
                        -- Timeout
                        report "IEC: TURNAROUND TIMEOUT: Device failed to turn-aruond to talker wihtin 64ms";
                        iec_state_reached <= to_unsigned(iec_state,12);
                        iec_state <= 0;
                        iec_devinfo <= x"00";
                        iec_status(1) <= '1'; -- TIMEOUT OCCURRED ...
                        iec_status(0) <= '1'; -- ... WHILE WE WERE TALKING
                        
                        iec_busy <= '0';
                        
                        -- Release all IEC lines
                        a('1');
                        d('1');
                      end if;
          when 205 =>
            if iec_clk_i = '0' then
              report "IEC: TURNAROUND complete";
              iec_state <= iec_state + 1;
            else
            end if;
          when 206 =>
            -- We need to give the JiffyDOS routine time to get itself
            -- organised before telling it we are ready to receive a byte
            -- I can't find accurate documentation on the time required
            -- for this, but based on the documentation from Gideon, it looks
            -- like about 55usec can be required. But in practice, it seems
            -- more is required.
            -- This only needed for the first byte received after turn-around.
            -- After that, the CLK line should be a safe indicator, as this seems
            -- to only be an issue that the CLK line is released early following
            -- turn-around. Is this true?

            -- Some experimentation reveals that we need longer.
            -- 525 usec is too short.
            -- 540 usec seems to work
            -- 600 usec is plenty
            micro_wait(t_jt);
            
          when 207 =>

            -- Device is present
            iec_devinfo(7) <= '1';
            iec_busy <= '0';

            -- Device is now talking
            iec_dev_listening <= '0';

            -- We are no longer under attention
            iec_under_attention <= '0';
            iec_devinfo(4) <= '1';

            iec_state_reached <= to_unsigned(iec_state,12);
            iec_state <= 0;


          -- RECEIVE BYTE FROM THE IEC BUS
          when 300 => wait_clk_high <= '1';                        
                      -- Watch for negative transition on SRQ to indicate C128
                      -- fast protocol.  But note that in C64 mode, SRQ is held
                      -- low by default ROM initialisation of our CIAs (which might
                      -- themselves be faulty). Anyway, the solution is to watch
                      -- for a negative-going transition, rather than a
                      -- negative level.
                      initial_srq_i <= iec_srq_i;
                      if iec_devinfo(6)='1' then
                        -- Assume drive will talk JiffyDOS protocol
                        iec_state <= 380;
                      end if;
          when 301 => d('1');
                      eoi_detected <= '0';
                      micro_wait(t_ye);
                      wait_clk_low <= '1';
          when 302 => if iec_clk_i='1' then
                        report "Acknowledging EOI";
                        eoi_detected <= '1';
                        d('0');
                        micro_wait(t_ei);
                      end if;
          when 303 => d('1'); wait_clk_low <= '1'; 
          when 304 =>
            -- Get ready to receive first bit
            -- If CLK goes high first, it's slow protocol.
            -- But if SRQ goes low first, it's fast protocol
            iec_state <= iec_state;
            if iec_srq_i='0' and initial_srq_i='1' then 
              report "IEC: Detected byte being transmitted using C128 FAST serial protocol";
              if c128fast_enabled='1' then              
                iec_state <= 350; -- FAST
                iec_devinfo(5) <= '1'; -- Device using FAST protocol
              else
                report "IEC: WARNING: Ignoring C128 FAST serial byte";
                report "              bus will likely lock-up now.";
              end if;
            end if;
            if iec_clk_i='1' then
              -- Slow protocol, and it's the first bit
              iec_data(7) <= iec_data_i;
              iec_data(6 downto 0) <= iec_data(7 downto 1);

              iec_state <= iec_state + 1;
            end if;
          when 305 => wait_clk_low <= '1';
          when 306 => wait_clk_high <= '1';
          when 307 => iec_data(7) <= iec_data_i;
                      iec_data(6 downto 0) <= iec_data(7 downto 1);
                      wait_clk_low <= '1';
          when 308 => wait_clk_high <= '1';
          when 309 => iec_data(7) <= iec_data_i;
                      iec_data(6 downto 0) <= iec_data(7 downto 1);
                      wait_clk_low <= '1';
          when 310 => wait_clk_high <= '1';
          when 311 => iec_data(7) <= iec_data_i;
                      iec_data(6 downto 0) <= iec_data(7 downto 1);
                      wait_clk_low <= '1';
          when 312 => wait_clk_high <= '1';
          when 313 => iec_data(7) <= iec_data_i;
                      iec_data(6 downto 0) <= iec_data(7 downto 1);
                      wait_clk_low <= '1';
          when 314 => wait_clk_high <= '1';
          when 315 => iec_data(7) <= iec_data_i;
                      iec_data(6 downto 0) <= iec_data(7 downto 1);
                      wait_clk_low <= '1';
          when 316 => wait_clk_high <= '1';
          when 317 => iec_data(7) <= iec_data_i;
                      iec_data(6 downto 0) <= iec_data(7 downto 1);
                      wait_clk_low <= '1';
          when 318 => wait_clk_high <= '1';
          when 319 => iec_data(7) <= iec_data_i;
                      iec_data(6 downto 0) <= iec_data(7 downto 1);
                      wait_clk_low <= '1';
          when 320 =>
            d('0');
            report "IEC: Successfully completed receiving SLOW byte = $" & to_hexstring(iec_data) & ", EOI=" & std_logic'image(eoi_detected);
            iec_devinfo(7) <= '1';
            iec_status(6) <= eoi_detected;

            iec_busy <= '0';

            iec_dev_listening <= '0';

            -- And we are still under attention
            iec_under_attention <= '0';

            iec_state_reached <= to_unsigned(iec_state,12);
            iec_state <= 0;

            -- Receiving using fast protocol
          when 350 => wait_srq_high <= '1';
          when 351 => wait_srq_low <= '1'; iec_data(6) <= iec_data_i; iec_data(7 downto 1) <= iec_data(6 downto 0);
          when 352 => wait_srq_high <= '1';
          when 353 => wait_srq_low <= '1'; iec_data(6) <= iec_data_i; iec_data(7 downto 1) <= iec_data(6 downto 0);
          when 354 => wait_srq_high <= '1';
          when 355 => wait_srq_low <= '1'; iec_data(6) <= iec_data_i; iec_data(7 downto 1) <= iec_data(6 downto 0);
          when 356 => wait_srq_high <= '1';
          when 357 => wait_srq_low <= '1'; iec_data(6) <= iec_data_i; iec_data(7 downto 1) <= iec_data(6 downto 0);
          when 358 => wait_srq_high <= '1';
          when 359 => wait_srq_low <= '1'; iec_data(6) <= iec_data_i; iec_data(7 downto 1) <= iec_data(6 downto 0);
          when 360 => wait_srq_high <= '1';
          when 361 => wait_srq_low <= '1'; iec_data(6) <= iec_data_i; iec_data(7 downto 1) <= iec_data(6 downto 0);
          when 362 => wait_srq_high <= '1';
          when 363 => wait_srq_low <= '1'; iec_data(6) <= iec_data_i; iec_data(7 downto 1) <= iec_data(6 downto 0);
          when 364 => wait_srq_high <= '1';
          when 365 => wait_srq_low <= '1'; iec_data(6) <= iec_data_i; iec_data(7 downto 1) <= iec_data(6 downto 0);
          when 366 => wait_srq_high <= '1';
          when 367 =>
            -- Acknowledge receipt of byte.
            -- Then wait a little while to make sure the sender has time to
            -- notice our ACK, before we might release DATA to say we are ready
            -- for the next byte.
            -- XXX Not sure how long this wait needs to be.
            d('0'); micro_wait(t_ff);
          when 368 =>
            report "IEC: Successfully completed receiving FAST byte = $" & to_hexstring(iec_data);
            iec_devinfo(7) <= '1';
            iec_busy <= '0';

            iec_dev_listening <= '0';

            -- And we are still under attention
            iec_under_attention <= '0';

            iec_state_reached <= to_unsigned(iec_state,12);
            iec_state <= 0;

          when 380 => 
            report "IEC: Receiving byte using JiffyDOS(tm) protocol";
            -- Allow JiffyDOS time to setup the byte
            -- From when JiffyDOS releases CLK to when it is _actually_
            -- ready is ~37 usec. So we must not release DATA until at
            -- least that long.
            -- Ideally we could count how long CLK had already been released,
            -- to save a little more time per byte.
            micro_wait(t_j0);

            -- The semantics of micro_wait() means that the state will run
            -- repeatedly until the time as expired. Thus it will sample at
            -- the _end_ rather than the _start_ of the period. We avoid this
            -- by separating sampling states from delay states.
          when 381 => d('1'); micro_wait(t_j1);
          when 382 => iec_data(1) <= iec_data_i; iec_data(0) <= iec_clk_i;
                      report "IEC: Sampling first 2 JiffyDOS bits";
          when 383 => micro_wait(t_j2);
          when 384 => iec_data(3) <= iec_data_i; iec_data(2) <= iec_clk_i;
                      report "IEC: Sampling second 2 JiffyDOS bits";
          when 385 => micro_wait(t_j3);
          when 386 => iec_data(5) <= iec_data_i; iec_data(4) <= iec_clk_i;
                      report "IEC: Sampling third 2 JiffyDOS bits";
          when 387 => micro_wait(t_j4);
          when 388 => iec_data(7) <= iec_data_i; iec_data(6) <= iec_clk_i;
                      report "IEC: Sampling fourth 2 JiffyDOS bits";
          when 389 => micro_wait(t_j5);
          when 390 => d('0'); iec_status(1) <= '0';
                      iec_status(6) <= '0';
                      iec_status(0) <= '0';
                      if iec_data_i='0' and iec_clk_i='1' then
                        -- Byte received with EOI
                        iec_status(6) <= '1';
                        report "IEC: Received byte via JiffyDOS fast protocol with EOI = $" & to_hexstring(iec_data);
                      elsif iec_data_i='1' and iec_clk_i='0' then
                        -- Byte received without EOI
                        report "IEC: Received byte via JiffyDOS fast protocol (without EOI) = $" & to_hexstring(iec_data);
                      else
                        -- Error
                        report "IEC: Error occurred while receiving byte via JiffyDOS fast protocol";
                        iec_status(1) <= '1'; -- TIMEOUT OCCURRED ...
                        iec_status(0) <= '0'; -- ... WHILE WE WERE LISTENING
                      end if;
                      iec_state <= 0;
                      iec_busy <= '0';
            

            -- SEND A BYTE (no attention)
          when 400 =>

            -- First, make sure ATN has been released.
            a('1');
            -- T_R -- Release of ATN at end of frame: 20 usec
            -- But we don't need to pay it if ATN was already released
            if iec_atn_int = '0' then
              micro_wait(t_ar);
            end if;

            -- Decide whether to send using slow, fast or JiffyDOS protocol
            if iec_devinfo(6)='1' then
              -- Assume drive will be expecting JiffyDOS protocol
              iec_state <= 480;
            elsif iec_devinfo(5)='1' then
              -- Assume drive will be expecting C128 fast serial protocol
            else
              -- Use original slow Commodore serial protocol
              null;
            end if;
            
          when 401 =>
            -- Announce we are ready to send, and wait for receiver to indicate
            -- readiness to receive.
            c('1'); wait_data_high <= '1';
          when 402 =>
            -- Receive is ready: Select SLOW, FAST or JiffyDOS protocol based on
            -- device capability.

            -- SLOW protocol send
            -- As previously noted, bit times from host to device have to be
            -- 70usec or longer, because the 1541's RX loop requires 68 cycles.

            -- Also receiving characters requires a delay after the device indicates
            -- ready to receive of ~ 40 usec, based on disassembly of 1541 ROM.
            -- It can't be too long, or it will be interpretted as an EOI.
            -- 70usec for example, seems to cause problems, even though it shouldn't.
            -- However, if it's EOI, then we expect the drive to pull DATA low
            -- after about 200 usec
            if send_eoi='0' then
              micro_wait(t_ne);
            else
              report "IEC: Sending byte with EOI: Waiting for device to pulse DATA to ACK";
              wait_data_low <= '1';
            end if;
          when 403 => null;
          when 404 =>
            if send_eoi='1' then
              wait_data_low <= '1';
            else
              iec_state <= iec_state + 3;
            end if;
          when 405 => wait_data_high <= '1';  -- wait for high edge of EOI ACK pulse
          when 406 => null;

          when 407 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_st);
                      report "IEC: Sending bit 0 = " & std_logic'image(iec_data_out(0));
          when 408 => c('1'); micro_wait(t_vt);
          when 409 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_st);
                      report "IEC: Sending bit 1 = " & std_logic'image(iec_data_out(0));
          when 410 => c('1'); micro_wait(t_vt);
          when 411 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_st);
                      report "IEC: Sending bit 2 = " & std_logic'image(iec_data_out(0));
          when 412 => c('1'); micro_wait(t_vt);
          when 413 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_st);
                      report "IEC: Sending bit 3 = " & std_logic'image(iec_data_out(0));
          when 414 => c('1'); micro_wait(t_vt);
          when 415 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_st);
                      report "IEC: Sending bit 4 = " & std_logic'image(iec_data_out(0));
          when 416 => c('1'); micro_wait(t_vt);
          when 417 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_st);
                      report "IEC: Sending bit 5 = " & std_logic'image(iec_data_out(0));
          when 418 => c('1'); micro_wait(t_vt);
          when 419 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_st);
                      report "IEC: Sending bit 6 = " & std_logic'image(iec_data_out(0));
          when 420 => c('1'); micro_wait(t_vt);
          when 421 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(t_st);
                      report "IEC: Sending bit 7 = " & std_logic'image(iec_data_out(0));
          when 422 => c('1'); micro_wait(t_vt);
          when 423 => c('0'); d('1');
            -- Allow device 1000usec = 1ms to acknowledge byte by
            -- pulling data low
                      micro_wait(t_f);
                      wait_data_low <= '0';
                      report "IEC: Waiting for device to acknowledge byte";
          when 424 =>
            if iec_data_i='0' then
              report "IEC: Device acknowledged receipt of byte";
              iec_state <= iec_state + 2;
              wait_msec <= 0;
            else
              report "IEC: Timedout waiting for device to acknowledge receipt of byte";
            end if;
          when 425 =>
            -- Timeout detected acknowledging byte

            -- Timeout has occurred: DEVICE NOT PRESENT
            -- (which is not strictly true, it's that device
            -- did not respond in time)
            report "IEC: DEVICE NOT PRESENT: Device failed to acknowledge byte";
            iec_state_reached <= to_unsigned(iec_state,12);
            iec_state <= 0;
            iec_devinfo <= x"00";
            iec_status(7) <= '1'; -- DEVICE NOT PRESENT
            iec_status(1) <= '1'; -- TIMEOUT OCCURRED ...
            iec_status(0) <= '1'; -- ... WHILE WE WERE TALKING

            iec_busy <= '0';

          when 426 => micro_wait(t_bb);
          when 427 =>
            -- Successfully sent byte
            report "IEC: Successfully completed sending byte without attention";
            iec_devinfo(7) <= '1';
            iec_busy <= '0';

            iec_dev_listening <= '0';

            -- And we are still under attention
            iec_under_attention <= '0';
            iec_devinfo(4) <= '0';

            iec_state_reached <= to_unsigned(iec_state,12);
            iec_state <= 0;

            -- If sending EOI, then we should release CLK as well, so that the
            -- device doesn't keep waiting for us to send something.
            if send_eoi='1' then
              send_eoi <= '0';
              c('1');
            end if;

          when 480 => report "IEC: Sending byte $" & to_hexstring(iec_data_out) & " using JiffyDOS(tm) protocol";
                      d('1');                 c('0');                 wait_data_high <= '1';
          when 481 =>                         c('1');                 micro_wait(t_j6);
                      -- Send direction for JiffyDOS uses inverted signals, and
                      -- rearranged bit order to optimise the transfer
          when 482 => d(not iec_data_out(5)); c(not iec_data_out(4)); micro_wait(t_j7);
          when 483 => d(not iec_data_out(7)); c(not iec_data_out(6)); micro_wait(t_j8);
          when 484 => d(not iec_data_out(1)); c(not iec_data_out(3)); micro_wait(t_j9);
          when 485 => d(not iec_data_out(0)); c(not iec_data_out(2)); micro_wait(t_j10);
          when 486 => d('0');                 c(not send_eoi);        micro_wait(t_j11);
          when 487 => c('0');
                      if iec_data_i='1' then
                        -- ERROR: Report timeout
                        iec_dev_listening <= '0';
                        iec_devinfo(1) <= '1';
                        iec_devinfo(0) <= '1'; -- while outputting data
                        iec_busy <= '0';
                        iec_state_reached <= to_unsigned(iec_state,12);
                        iec_state <= 0;
                      else
                        -- No error, JiffyDOS drive is busy again
                        null; 
                      end if;
                      if send_eoi='1' then
                        iec_state <= iec_state + 2;
                      end if;
          when 488 => report "IEC: Successfully sent byte using JiffyDOS(tm) protocol";
                      iec_devinfo(7) <= '0';
                      iec_busy <= '0';

                      iec_dev_listening <= '1';

                      -- And we are still under attention
                      iec_under_attention <= '0';
                      iec_devinfo(4) <= '0';

                      iec_state_reached <= to_unsigned(iec_state,12);
                      iec_state <= 0;

                      -- Send EOI byte (contents will be ignored by JiffyDOS)
          when 489 => -- Pretend we want to send another byte
                      d('1');                 c('1');
                      wait_data_high <= '1';
          when 490 => micro_wait(t_j6);

                      -- We repeat the last byte we sent, not because JiffyDOS
                      -- requires it, but to make tb_iec_serial's probing of most
                      -- recently received byte by drive checks pass.
          when 491 => d(not iec_data_out(5)); c(not iec_data_out(4)); micro_wait(t_j7);
          when 492 => d(not iec_data_out(7)); c(not iec_data_out(6)); micro_wait(t_j8);
          when 493 => d(not iec_data_out(1)); c(not iec_data_out(3)); micro_wait(t_j9);
          when 494 => d(not iec_data_out(0)); c(not iec_data_out(2)); micro_wait(t_j10);
          when 495 => d('0');                 c('0');                 micro_wait(t_j11);
                      -- JiffyDOS requires that ATN line is also pulsed low
                      -- when sending EOI.                      -
                      a('0');
          when 496 => -- But we have to also release ATN again soon after, if
                      -- we want the EOI to be processed.
                      a('1');                                         micro_wait(t_jr);
          when 497 => report "IEC: Successfully sent EOI using JiffyDOS(tm) protocol";
                      iec_devinfo(7) <= '0';
                      iec_busy <= '0';

                      iec_dev_listening <= '0';

                      -- And we are still under attention
                      iec_under_attention <= '0';
                      iec_devinfo(4) <= '0';

                      iec_state_reached <= to_unsigned(iec_state,12);
                      iec_state <= 0;

                      -- Generate a 1KHz pulse train on the CLK and DATA lines
          when 500 => a(msec_toggle); c('1'); d('0'); micro_wait(500);
          when 501 => a(msec_toggle); c('0'); d('1'); micro_wait(500);
          when 502 => iec_state <= 500;            
                      
          when others => iec_state <= 0; iec_busy <= '0';
                         iec_state_reached <= to_unsigned(iec_state,12);

        end case;
      end if;

      if reset_timing_now = '1' then
        report "IEC: Resetting protocol timing to default";
        reset_timing;
        reset_timing_now <= '0';
      end if;
            
      if reset_in = '0' then
        iec_state <= 0;
        wait_clk_high <= '0'; wait_clk_low <= '0';
        wait_data_high <= '0'; wait_data_low <= '0';
        wait_srq_high <= '0'; wait_srq_low <= '0';
        wait_usec <= 0; wait_msec <= 0;
        a('1'); s('1'); d('1'); c('1');
        jiffydos_enabled <= '1';
        report "IEC: Enabling JiffyDOS solicitation via /RESET pin";
        c128fast_enabled <= '0';
        reset_timing_now <= '1';
      end if;

    end if;
  end process;

end questionable;
