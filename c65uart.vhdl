use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity c65uart is
  port (
    pixelclock : in std_logic;
    cpuclock : in std_logic;
    phi0 : in std_logic;
    reset : in std_logic;
    irq : out std_logic := 'Z';
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    cs : in std_logic;
    fastio_address : in unsigned(7 downto 0);
    fastio_write : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0);

    porte_out : out std_logic_vector(1 downto 0);
    porte_in : in std_logic_vector(1 downto 0);

    portf : inout std_logic_vector(7 downto 0);
    portg : in std_logic_vector(7 downto 0)
    
    );
end c65uart;

architecture behavioural of c65uart is

  -- Work out what fraction of a 7.09375MHz tick we cover every pixel clock.
  -- This is used to allow us to match C65 UART speeds.
  -- 7.09375 / 193.5 * 65536 = 2403;
  constant baud_subcounter_step : integer := 2403;
  signal baud_subcounter : integer range 0 to (65536 + baud_subcounter_step);
  -- If 1, then use approximated 7.09375MHz clock, if 0 use 193.5MHz clock
  signal clock709375 : std_logic := '1';

  -- Work out 7.09375ishMHz clock ticks;
  signal tick709375 : std_logic := '0';

  -- Then merge this with 193.5MHz clock to have a single clock source used for
  -- generating half-ticks at the requested baud rate
  signal fine_tick : std_logic := '0';

  -- Count how many fine ticks per half-baud
  signal reg_tick_countdown : unsigned(15 downto 0) := (others => '0');

  -- From that work out the half-baud ticks
  signal half_tick : std_logic := '1';
  
  -- Actual C65 UART registers
  signal reg_status : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_control : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_divisor : unsigned(15 downto 0) := (others => '0');
  signal reg_intmask : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_intflag : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_data_tx : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_data_rx : std_logic_vector(7 downto 0) := (others => '0');

  -- C65 extra 2-bit port for keyboard column 8 and capslock key state.
  signal reg_porte_out : std_logic_vector(1 downto 0) := (others => '0');
  signal reg_porte_ddr : std_logic_vector(1 downto 0) := (others => '0');
  signal reg_porte_read : unsigned(1 downto 0) := (others => '0');

  -- MEGA65 PMOD register for debugging and fiddling
  signal reg_portf_out : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_portf_ddr : std_logic_vector(7 downto 0) := (others => '0');
  signal reg_portf_read : unsigned(7 downto 0) := (others => '0');

begin  -- behavioural
  
  process(pixelclock,cpuclock,fastio_address,fastio_write
          ) is
    variable register_number : unsigned(7 downto 0);
  begin

    if cs='0' then
      -- Tri-state read lines if not selected
      fastio_rdata <= (others => 'Z');
    else
        register_number(7 downto 4) := (others => '0');
        register_number(3 downto 0) := fastio_address(3 downto 0);

        -- Reading of registers
        if fastio_write='1' then
          -- Tri-state read lines if writing
          fastio_rdata <= (others => 'Z');
        else
          -- See 2.3.3.3 in c65manual.txt for register assignments
          -- (in a real C65 these registers are in the 4510)
          case register_number is
            when x"00" =>
              -- @IO:65 $D600 C65 UART data register (read or write)
              fastio_rdata <= unsigned(reg_data_rx);
              -- Clear byte read flag
              reg_status(0) <= '0';
              -- Clear RX over-run flag
              reg_status(1) <= '0';
              -- Clear RX parity error flag
              reg_status(2) <= '0';
              -- Clear RX framing error flag
              reg_status(3) <= '0';
            when x"01" =>
              -- @IO:65 $D601 C65 UART status register
              -- @IO:65 $D601.0 C65 UART RX byte ready flag (clear by reading $D600)
              -- @IO:65 $D601.1 C65 UART RX overrun flag (clear by reading $D600)
              -- @IO:65 $D601.2 C65 UART RX parity error flag (clear by reading $D600)
              -- @IO:65 $D601.3 C65 UART RX framing error flag (clear by reading $D600)
              fastio_rdata <= unsigned(reg_status);
            when x"02" =>
              -- @IO:65 $D602 C65 UART control register
              fastio_rdata <= unsigned(reg_control);
            when x"03" =>
              -- @IO:65 $D603 C65 UART baud rate divisor (low byte)
              fastio_rdata <= reg_divisor(7 downto 0);
            when x"04" =>
              -- @IO:65 $D604 C65 UART baud rate divisor (high byte)
              fastio_rdata <= reg_divisor(15 downto 8);
            when x"05" =>
              -- @IO:65 $D605 C65 UART interrupt mask register              
              fastio_rdata <= unsigned(reg_intmask);
            when x"06" =>
              -- @IO:65 $D606 C65 UART interrupt flag register              
              fastio_rdata <= unsigned(reg_intflag);
            when x"07" =>
              -- @IO:65 $D607 C65 UART 2-bit port data register (used for C65 keyboard)
              fastio_rdata(7 downto 2) <= (others => 'Z');
              fastio_rdata(1 downto 0) <= reg_porte_read;
            when x"08" =>
              -- @IO:65 $D607 C65 UART 2-bit port data direction register (used for C65 keyboard)
              fastio_rdata(7 downto 2) <= (others => 'Z');
              fastio_rdata(1 downto 0) <= unsigned(reg_porte_ddr);
            when x"09" =>
              -- @IO:65 $D609 MEGA65 extended UART control register
              -- @IO:65 $D609.0 UART BAUD clock source: 1 = 7.09375MHz, 0 = 193.5MHz
              fastio_rdata(0) <= clock709375;
              fastio_rdata(7 downto 1) <= (others => '1');
            when x"0d" =>
              -- @IO:65 $D60D DEBUG - Read hyper_trap_count: will be removed after debugging.
              fastio_rdata(7 downto 0) <= unsigned(portg);
            when x"0e" =>
              -- @IO:65 $D60E PMOD port A on FPGA board (data bits)
              fastio_rdata(7 downto 0) <= reg_portf_read;
            when x"0f" =>
              -- @IO:65 $D60F PMOD port A on FPGA board (DDR)
              fastio_rdata(7 downto 0) <= unsigned(reg_portf_ddr);
            when others => fastio_rdata <= (others => 'Z');
          end case;
        end if;
      end if;
--    end if;
  end process;

  process(cpuclock) is
    -- purpose: use DDR to show either input or output bits
    function ddr_pick (
      ddr                            : in std_logic_vector(1 downto 0);
      i                              : in std_logic_vector(1 downto 0);
      o                              : in std_logic_vector(1 downto 0))
    return unsigned is
    variable result : unsigned(1 downto 0);     
  begin  -- ddr_pick
    --report "determining read value for CIA port." &
    --  "  DDR=$" & to_hstring(ddr) &
    --  ", out_value=$" & to_hstring(o) &
    --  ", in_value=$" & to_hstring(i) severity note;
    result := unsigned(i);
    for b in 0 to 1 loop
      if ddr(b)='1' and i(b)='1' then
        result(b) := std_ulogic(o(b));
      end if;
    end loop;  -- b
    return result;
  end ddr_pick;

  variable register_number : unsigned(3 downto 0);
  begin
    if rising_edge(pixelclock) then
      if (baud_subcounter + baud_subcounter_step < 65536) then
        baud_subcounter <= baud_subcounter + baud_subcounter_step;
        tick709375 <= '0';
      else
        baud_subcounter <= baud_subcounter + baud_subcounter_step - 65536;

        -- One baud divisor tick has elapsed.
        -- Based on TX and RX modes, take the appropriate action.
        -- Each tick here is 1/2 a bit.
        tick709375 <= '1';
      end if;
      if tick709375='1' or clock709375='0' then
        -- Depending on whether we are running from the 7.09375MHz
        -- clock or the 193.5MHz pixel clock, see if we are at a baud tick
        -- (193.5MHz clock is used for baud rates above 57.6K.)
        fine_tick <= '1';
      else
        fine_tick <= '0';
      end if;
      if fine_tick='1' then
        if reg_tick_countdown > 0 then
          reg_tick_countdown <= reg_tick_countdown - 1;
          half_tick <= '0';
        else
          reg_tick_countdown <= reg_divisor;
          half_tick <= '1';
        end if;
      end if;
      if half_tick = '1' then
        -- Here we have a clock tick twice per intended bit
        -- XXX work out what to do
      end if;
    end if;
    
    if rising_edge(cpuclock) then
      register_number := fastio_address(3 downto 0);

      -- Calculate read value for porta and portb
      reg_porte_read <= ddr_pick(reg_porte_ddr,porte_in,reg_porte_out);        
      reg_portf_read(7 downto 6) <= ddr_pick(reg_portf_ddr(7 downto 6),
                                             portf(7 downto 6),
                                             reg_portf_out(7 downto 6));
      reg_portf_read(5 downto 4) <= ddr_pick(reg_portf_ddr(5 downto 4),
                                             portf(5 downto 4),
                                             reg_portf_out(5 downto 4));
      reg_portf_read(3 downto 2) <= ddr_pick(reg_portf_ddr(3 downto 2),
                                             portf(3 downto 2),
                                             reg_portf_out(3 downto 2));
      reg_portf_read(1 downto 0) <= ddr_pick(reg_portf_ddr(1 downto 0),
                                             portf(1 downto 0),
                                             reg_portf_out(1 downto 0));

      porte_out <= reg_porte_out or (not reg_porte_ddr);
      -- Support proper tri-stating on port F which connects to FPGA board PMOD
      -- connector.
      for bit in 0 to 7 loop
        if reg_portf_ddr(bit)='1' then
          portf(bit) <= reg_portf_out(bit) or (not reg_portf_ddr(bit));
        else
          portf(bit) <= 'Z';
        end if;
      end loop;
      
      -- Check for register writing
      if fastio_write='1' and cs='1' then
        register_number := fastio_address(3 downto 0);
        case register_number is
          when x"7" => reg_porte_out<=std_logic_vector(fastio_wdata(1 downto 0));
          when x"8" => reg_porte_ddr<=std_logic_vector(fastio_wdata(1 downto 0));
          when x"e" => reg_portf_out <= std_logic_vector(fastio_wdata);
          when x"f" => reg_portf_ddr <= std_logic_vector(fastio_wdata);
          when others => null;
        end case;
      end if;
    end if;
  end process;

end behavioural;
