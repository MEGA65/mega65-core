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
  signal last_msec_toggle : std_logic := '0';
  signal timing_sync_toggle : std_logic := '0';
  signal last_timing_sync_toggle : std_logic := '0';

  signal last_iec_data : std_logic := 'U';
  signal last_iec_clk : std_logic := 'U';
  signal last_iec_srq : std_logic := 'U';

  signal debug_counter : integer range 0 to 4095 := 4095;
  signal debug_ram_write : std_logic := '0';
  signal debug_ram_waddr : integer := 0;
  signal debug_ram_waddr_int : integer := 0;
  signal debug_ram_raddr : integer := 0;
  signal debug_ram_raddr_int : integer := 0;
  signal debug_ram_wdata : unsigned(7 downto 0) := x"00";
  signal debug_ram_rdata : unsigned(7 downto 0);
  signal debug_ram_wdata2 : unsigned(7 downto 0) := x"00";
  signal debug_ram_rdata2 : unsigned(7 downto 0);
  signal iec_clk_o_int : std_logic := '0';
  signal iec_data_o_int : std_logic := '0';
  signal iec_srq_o_int : std_logic := '0';
  signal iec_atn_int : std_logic := '0';
  signal iec_reset_int : std_logic := '0';

begin

  -- Note that we put RX on bit 6, so that the common case of LOADing can be a
  -- little faster, by allowing BIT $D697 / BVC *-3 to be a very tight loop
  -- for waiting for bytes.

  -- @IO:GS $D697.7 AUTOIEC:IRQFLAG Interrupt flag. Set if any IRQ event is triggered.
  -- @IO:GS $D697.6 AUTOIEC:IRQRX Set if a byte has been received from a listener.
  -- @IO:GS $D697.5 AUTOIEC:IRQREADY Set if ready to process a command
  -- @IO:GS $D697.4 AUTOIEC:IRQTO Set if a protocol timeout has occurred, e.g., device not found.
  -- @IO:GS $D697.3 AUTOIEC:IRQEN Enable interrupts if set
  -- @IO:GS $D697.2 AUTOIEC:IRQRXEN Enable RX interrupt source if set
  -- @IO:GS $D697.1 AUTOIEC:IRQREADYEN Enable TX interrupt source if set
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
  -- @IO:GS $D69A.7 AUTOIEC:DIPRESENT Device is present
  -- @IO:GS $D69A.5-6 AUTOIEC:DIPROT Device protocol support (5=C128/C65 FAST, bit 6 = JiffyDOS(tm))
  -- @IO:GS $D69A.4 AUTOIEC:DIATN Device is currently held under attention
  -- @IO:GS $D69A.0-3 AUTOIEC:DIDEVNUM Lower 4 bits of currently selected device number

  ram0: if with_debug generate
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

  ram1: if with_debug generate
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

  process (clock,clock81) is
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
    procedure micro_wait(usecs : integer) is
    begin

      wait_clk_high <= '0'; wait_clk_low <= '0';
      wait_data_high <= '0'; wait_data_low <= '0';
      wait_srq_high <= '0'; wait_srq_low <= '0';
      wait_msec <= 0;

      wait_usec <= usecs;
      not_waiting_usec <= false;
      not_waiting_msec <= true;

    end procedure;
    procedure milli_wait(msecs : integer) is
    begin

      wait_clk_high <= '0'; wait_clk_low <= '0';
      wait_data_high <= '0'; wait_data_low <= '0';
      wait_srq_high <= '0'; wait_srq_low <= '0';
      wait_usec <= 0;

      wait_msec <= msecs;
      not_waiting_msec <= false;
      not_waiting_usec <= true;

    end procedure;
  begin

    if rising_edge(clock81) then

      if timing_sync_toggle /= last_timing_sync_toggle then
        last_timing_sync_toggle <= timing_sync_toggle;
        cycles <= 0;
        usecs <= 0;
      elsif cycles < (81-1) then
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
            fastio_rdata <= debug_ram_rdata2;
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

      if with_debug then
        debug_ram_wdata(0) <= iec_data_i;
        debug_ram_wdata(1) <= iec_clk_i;
        debug_ram_wdata(2) <= iec_srq_i;
        debug_ram_wdata(3) <= iec_data_o_int;
        debug_ram_wdata(4) <= iec_clk_o_int;
        debug_ram_wdata(5) <= iec_srq_o_int;
        debug_ram_wdata(6) <= iec_atn_int;
        debug_ram_wdata(7) <= iec_reset_int;

        debug_ram_wdata2 <= to_unsigned(iec_state,8);

        prev_iec_state <= iec_state;
        if debug_counter < (40-1) and (iec_state = prev_iec_state) then
          debug_counter <= debug_counter + 1;
          debug_ram_write <= '0';
        else
          debug_counter <= 0;
          if debug_ram_waddr_int < 4095 then
            debug_ram_write <= '1';
            debug_ram_waddr_int <= debug_ram_waddr_int + 1;
            debug_ram_waddr <= debug_ram_waddr_int + 1;
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
                if fastio_wdata = x"00" then
                  debug_ram_raddr <= 0;
                  debug_ram_raddr_int <= 0;
                else
                  if debug_ram_raddr_int < 4095 then
                    debug_ram_raddr_int <= debug_ram_raddr_int + 1;
                    debug_ram_raddr <= debug_ram_raddr_int + 1;
                  end if;
                end if;
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
            iec_state <= 0;
            wait_clk_high <= '0'; wait_clk_low <= '0';
            wait_data_high <= '0'; wait_data_low <= '0';
            wait_srq_high <= '0'; wait_srq_low <= '0';
            wait_usec <= 0; wait_msec <= 0;

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
            iec_dev_listening <= '0';
            a('1'); d('1'); c('1');
          when x"72" => -- Drive IEC reset pin 0V
            iec_reset_n <= '0';
            iec_reset_int <= '0';
            iec_dev_listening <= '0';
            a('1'); d('1'); c('1');

            -- Protocol level commands
          when x"30" => -- Request device attention (send data byte under attention)
            iec_state <= 100;
            iec_busy <= '1';

            wait_clk_high <= '0'; wait_clk_low <= '0';
            wait_data_high <= '0'; wait_data_low <= '0';
            wait_srq_high <= '0'; wait_srq_low <= '0';
            wait_usec <= 0; wait_msec <= 0;

            -- Trigger begin collecting debug info during job
            debug_ram_waddr_int <= 0;

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
          when x"34" => -- Send byte with EOI (don't touch ATN)
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
        usec_toggle <= last_usec_toggle;
      end if;
      if msec_toggle /= last_msec_toggle then
        if wait_msec > 0 then
          not_waiting_msec <= false;
          report "TIME: decrementing msec counter to " & integer'image(wait_msec-1);
          wait_msec <= wait_msec - 1;
          if wait_msec = 1 then
            not_waiting_msec <= true;
          end if;
        end if;
        msec_toggle <= last_msec_toggle;
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

            -- DATA to 5V
            -- Ensure SRQ is released to 5V
            d('1'); s('1');

            -- Skip C= fast serial signal if a device is
            -- listening, so that it doesn't get mis-interpretted
            -- as data.
            -- XXX - Actually only required if the device supports
            -- C= fast serial?
            if iec_dev_listening='1' then
              iec_state <= 120;
            end if;

          -- Send data byte $FF using SRQ as clock to indicate our ability
          -- to do C= fast serial
          when 101 => s('1'); micro_wait(5);
          when 102 => s('0'); micro_wait(5);
          when 103 => s('1'); micro_wait(5);
          when 104 => s('0'); micro_wait(5);
          when 105 => s('1'); micro_wait(5);
          when 106 => s('0'); micro_wait(5);
          when 107 => s('1'); micro_wait(5);
          when 108 => s('0'); micro_wait(5);
          when 109 => s('1'); micro_wait(5);
          when 110 => s('0'); micro_wait(5);
          when 111 => s('1'); micro_wait(5);
          when 112 => s('0'); micro_wait(5);
          when 113 => s('1'); micro_wait(5);
          when 114 => s('0'); micro_wait(5);
          when 115 => s('1'); micro_wait(5);
          when 116 => s('0'); micro_wait(5);

          when 117 | 118 | 119 => null;

          when 120 =>
            -- Prepare all IEC lines:
            a('0'); -- ATN to 0V
            c('0'); -- CLK to 0V
            d('1'); -- DATA to 5V
            s('1'); -- Ensure SRQ is released to 5V

            -- Clear relevant status bits
            iec_status(7) <= '0'; -- no DEVICE NOT FOUND error (yet)
            iec_status(1) <= '0'; -- No timeout
            iec_status(0) <= '0'; -- No data direction during timeout

            -- And also device info byte
            iec_devinfo(7) <= '0'; -- Device not (yet) detected
            iec_devinfo(6 downto 5) <= "00"; -- slow protocol
            -- Device ID being requested
            iec_devinfo(4 downto 0) <= iec_data_out(4 downto 0);

            -- Wait a little while before asserting CLK
            micro_wait(20);

          when 121 =>
            -- Wait upto 1ms for DATA to go low
            micro_wait(1000);

          when 122 =>
            c('1');  -- Release CLK to 5V
            if prev_iec_state /= 123 then
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
            milli_wait(64);
            wait_data_high <= '1';

          when 125 =>
            if iec_data_i='0' then
              report "IEC: TIMEDOUT waiting for DATA to go high";
              iec_state <= iec_state + 2;
            else
              report "IEC: Saw DATA go high: Advancing";
              micro_wait(40);
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
            -- After sending 7th bit, we do the JiffyDOS(tm) check
            -- by delaying, and waiting to see if the data line
            -- is pulled low by a device, indicating that it speaks
            -- the JiffyDOS protocol.  More on that when we get to it.

            -- Send the first 7 bits
            report "IEC: Sending data byte $" & to_hexstring(iec_data_out) & "  under ATN";
            null;
          when 129 => c('0'); d(iec_data_out(0)); micro_wait(35);
          when 130 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(35);
                      report "IEC: Sending bit 0 = " & std_logic'image(iec_data_out(0));
          when 131 => c('0'); d(iec_data_out(0)); micro_wait(35);
          when 132 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(35);
                      report "IEC: Sending bit 1 = " & std_logic'image(iec_data_out(0));
          when 133 => c('0'); d(iec_data_out(0)); micro_wait(35);
          when 134 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(35);
                      report "IEC: Sending bit 2 = " & std_logic'image(iec_data_out(0));
          when 135 => c('0'); d(iec_data_out(0)); micro_wait(35);
          when 136 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(35);
                      report "IEC: Sending bit 3 = " & std_logic'image(iec_data_out(0));
          when 137 => c('0'); d(iec_data_out(0)); micro_wait(35);
          when 138 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(35);
                      report "IEC: Sending bit 4 = " & std_logic'image(iec_data_out(0));
          when 139 => c('0'); d(iec_data_out(0)); micro_wait(35);
          when 140 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(35);
                      report "IEC: Sending bit 5 = " & std_logic'image(iec_data_out(0));
          when 141 => c('0'); d(iec_data_out(0)); micro_wait(35);
          when 142 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(35);
                      report "IEC: Sending bit 6 = " & std_logic'image(iec_data_out(0));

          -- Now we have sent 7 bits, release data, keeping clock at 0V, and
          -- check for DATA being pulled low
          when 143 => c('0'); d('1'); micro_wait(500);
                      report "IEC: Performing JiffyDOS(tm) check";
          when 144 =>
            -- If data went low: device speaks JiffyDOS protocol
            if iec_data_i='0' then
              if iec_devinfo(6 downto 5) = "00" then
                report "IEC: Device supports JiffyDOS(tm) protocol. Waiting for DATA to release again.";
              end if;
              -- Record JiffyDOS capability
              iec_devinfo(6 downto 5) <= "10";
              -- Wait for DATA to be released again
              wait_usec <= 0; wait_data_high <= '1';
            end if;
          when 145 => c('0'); d(iec_data_out(0)); micro_wait(35);
          when 146 => c('1'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(35);
                      report "IEC: Sending bit 7 = " & std_logic'image(iec_data_out(0));
          when 147 => c('0'); d('1');
          when 148 =>
            -- Allow device 1000usec = 1ms to acknowledge byte by
            -- pulling data low
                      micro_wait(1000);
                      wait_data_low <= '1';
                      report "IEC: Waiting for device to acknowledge byte";
          when 149 =>
            if iec_data_i='0' then
              report "IEC: Device acknowledged receipt of byte";
              iec_state <= iec_state + 2;
              wait_msec <= 0;
            else
              report "IEC: Timedout waiting for device to acknowledge receipt of byte";
            end if;
          when 150 =>
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

            -- Release all IEC lines
            a('1');
            c('1');

          when 151 =>
            -- Successfully sent byte
            report "IEC: Successfully completed sending byte under attention";
            iec_devinfo(7) <= '1';
            iec_busy <= '0';

            iec_dev_listening <= '1';

            -- And we are still under attention
            iec_under_attention <= '1';
            iec_devinfo(4) <= '1';

            iec_state_reached <= to_unsigned(iec_state,12);
            iec_state <= 0;



            -- TURNAROUND FROM TALKER TO LISTENER
            -- Wait 20 usec, release ATN, wait 20usec
            -- Computer pulls DATA low and releases CLK.
            -- Device then pulls CLK low and releases DATA.

          when 200 => micro_wait(100);
          when 201 => a('1'); micro_wait(100);
          when 202 => d('0'); c('1'); micro_wait(100);
          when 203 => milli_wait(64); wait_clk_low <= '1';
          when 204 =>
            if iec_clk_i = '0' then
              report "IEC: TURNAROUND complete";
              iec_state <= iec_state + 2;
            else
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
          when 301 => d('1');
                      eoi_detected <= '0';
                      micro_wait(200);
                      wait_clk_low <= '1';
          when 302 => if iec_clk_i='1' then
                        report "Acknowledging EOI";
                        eoi_detected <= '1';
                        d('0');
                        micro_wait(80);
                      end if;
          when 303 => d('1'); wait_clk_low <= '1';
          when 304 =>
            -- Get ready to receive first bit
            -- If CLK goes high first, it's slow protocol.
            -- But if SRQ goes low first, it's fast protocol
            iec_state <= iec_state;
            if iec_srq_i='0' then
              iec_state <= 350; -- FAST
              iec_devinfo(5) <= '1'; -- Device using FAST protocol
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
            d('0'); micro_wait(40);
          when 368 =>
            report "IEC: Successfully completed receiving FAST byte = $" & to_hexstring(iec_data);
            iec_devinfo(7) <= '1';
            iec_busy <= '0';

            iec_dev_listening <= '0';

            -- And we are still under attention
            iec_under_attention <= '0';

            iec_state_reached <= to_unsigned(iec_state,12);
            iec_state <= 0;



            -- SEND A BYTE (no attention)
          when 400 =>
            -- XXX Decide whether to send using slow, fast or JiffyDOS protocol

            -- First, make sure ATN has been released.
            a('1');
            -- T_R -- Release of ATN at end of frame: 20 usec
            -- But we don't need to pay it if ATN was already released
            if iec_atn_int = '0' then
              micro_wait(20);
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
              micro_wait(40);
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

          when 407 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(70);
                      report "IEC: Sending bit 0 = " & std_logic'image(iec_data_out(0));
          when 408 => c('1'); micro_wait(20);
          when 409 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(70);
                      report "IEC: Sending bit 1 = " & std_logic'image(iec_data_out(0));
          when 410 => c('1'); micro_wait(20);
          when 411 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(70);
                      report "IEC: Sending bit 2 = " & std_logic'image(iec_data_out(0));
          when 412 => c('1'); micro_wait(20);
          when 413 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(70);
                      report "IEC: Sending bit 3 = " & std_logic'image(iec_data_out(0));
          when 414 => c('1'); micro_wait(20);
          when 415 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(70);
                      report "IEC: Sending bit 4 = " & std_logic'image(iec_data_out(0));
          when 416 => c('1'); micro_wait(20);
          when 417 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(70);
                      report "IEC: Sending bit 5 = " & std_logic'image(iec_data_out(0));
          when 418 => c('1'); micro_wait(20);
          when 419 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(70);
                      report "IEC: Sending bit 6 = " & std_logic'image(iec_data_out(0));
          when 420 => c('1'); micro_wait(20);
          when 421 => c('0'); d(iec_data_out(0)); iec_data_out_rotate; micro_wait(70);
                      report "IEC: Sending bit 7 = " & std_logic'image(iec_data_out(0));
          when 422 => c('1'); micro_wait(20);
          when 423 => c('0'); d('1');
            -- Allow device 1000usec = 1ms to acknowledge byte by
            -- pulling data low
                      micro_wait(1000);
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

          when 426 =>
            -- Successfully sent byte
            report "IEC: Successfully completed sending byte without attention";
            iec_devinfo(7) <= '1';
            iec_busy <= '0';

            iec_dev_listening <= '0';

            -- And we are still under attention
            iec_under_attention <= '1';
            iec_devinfo(4) <= '1';

            iec_state_reached <= to_unsigned(iec_state,12);
            iec_state <= 0;

            -- If sending EOI, then we should release CLK as well, so that the
            -- device doesn't keep waiting for us to send something.
            if send_eoi='1' then
              send_eoi <= '0';
              c('1');
            end if;

          when others => iec_state <= 0; iec_busy <= '0';
                         iec_state_reached <= to_unsigned(iec_state,12);

        end case;
      end if;
    end if;
  end process;

end questionable;
