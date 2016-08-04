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
    fastio_address : in unsigned(19 downto 0);
    fastio_write : in std_logic;
    fastio_read : in std_logic;
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0);

    porte_out : out std_logic_vector(1 downto 0);
    porte_in : in std_logic_vector(1 downto 0);

    uart_rx : in std_logic;
    uart_tx : out std_logic;
    
    portf : inout std_logic_vector(7 downto 0);
    portg : in std_logic_vector(7 downto 0)
    
    );
end c65uart;

architecture behavioural of c65uart is

  -- Work out what fraction of a 7.09375MHz tick we cover every pixel clock.
  -- This is used to allow us to match C65 UART speeds.
  -- 7.09375 / 193.5 / 16 * 1048576 = 2403;
  -- Note that these ticks are in 1/16ths of the desired baud rate.
  -- This limits our maximum usable baud rate to something like 193.5MHz/16 = ~10MHz
  -- But I am not totally convinced that I have all the calculations right
  -- here. Will need to check what actually comes out the port at particular claimed
  -- speeds to be sure.
  constant baud_subcounter_step : integer := 2403;
  signal baud_subcounter : integer range 0 to (1048576 + baud_subcounter_step);
  -- If 1, then use approximated 7.09375MHz clock, if 0 use 193.5MHz clock
  signal clock709375 : std_logic := '1';

  -- Work out 7.09375ishMHz clock ticks;
  signal tick709375 : std_logic := '0';

  -- Then merge this with 193.5MHz clock to have a single clock source used for
  -- generating half-ticks at the requested baud rate
  signal fine_tick : std_logic := '0';

  -- Count how many fine ticks per half-baud
  signal reg_tick_countdown : unsigned(15 downto 0) := (others => '0');

  -- From that work out the baud ticks
  signal baud_tick : std_logic := '1';

  -- Filtered UART RX line
  signal filtered_rx : std_logic := '1';
  signal rx_samples : std_logic_vector(15 downto 0);

  -- Transmit buffer for current byte
  -- (Note the UART can also have a byte buffered in reg_data_tx, to allow
  -- back-to-back char sending)
  signal tx_buffer : std_logic_vector(7 downto 0);
  signal tx_in_progress : std_logic := '0';
  signal tx_bits_to_send : integer range 0 to 8;
  signal tx_stop_bit_sent : std_logic := '0';
  signal tx_parity_bit_sent : std_logic := '0';
  signal tx_space_bit_sent : std_logic := '0';

  -- Similarly track incoming bytes
  signal rx_buffer : std_logic_vector(7 downto 0);
  signal rx_in_progress : std_logic := '0';
  signal rx_bits_remaining : integer range 0 to 8;
  signal rx_stop_bit_got : std_logic := '0';
  signal rx_clear_flags : std_logic := '0';
  
  -- Actual C65 UART registers
  signal reg_status0_rx_full : std_logic := '0';
  signal reg_status1_rx_overrun : std_logic := '0';
  signal reg_status2_rx_parity_error : std_logic := '0';
  signal reg_status3_rx_framing_error : std_logic := '0';
  signal reg_status4_rx_idle_mode : std_logic := '0';  -- XXX not implemented
  signal reg_status5_tx_eot : std_logic := '0';
  signal reg_status6_tx_empty : std_logic := '1';
  signal reg_status7_xmit_on : std_logic := '0';

  signal reg_ctrl0_parity_even : std_logic := '0';
  signal reg_ctrl1_parity_enable : std_logic := '0';
  signal reg_ctrl23_char_length_deduct : unsigned(1 downto 0) := "00";
  signal reg_ctrl45_sync_mode_flags : std_logic_vector(1 downto 0) := "00"; -- XXX not implemented
  signal reg_ctrl6_rx_enable : std_logic := '1';
  signal reg_ctrl7_tx_enable : std_logic := '1';
  
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

    register_number(3 downto 0) := fastio_address(3 downto 0);
    
    if rising_edge(cpuclock) then
      rx_clear_flags <= '0';
      if (fastio_address(19 downto 16) = x"D")
        and (fastio_address(11 downto 4) = x"60") then
        if fastio_read='1' and register_number = x"0" then
          rx_clear_flags <= '1';
        end if;
      end if;
    end if;
    
    -- Reading of registers
    if fastio_read='0' then
      -- Tri-state read lines if writing
      fastio_rdata <= (others => 'Z');
    else
      -- See 2.3.3.3 in c65manual.txt for register assignments
      -- (in a real C65 these registers are in the 4510)
      if (fastio_address(19 downto 16) /= x"D")
        or (fastio_address(11 downto 4) /= x"60") then
        fastio_rdata <= (others => 'Z');
      else
        report "Reading C65 UART controller register";
        case register_number is
          when x"0" =>
            -- @IO:C65 $D600 C65 UART data register (read or write)
            fastio_rdata <= unsigned(reg_data_rx);            
          when x"1" =>
            -- @IO:C65 $D601 C65 UART status register
            -- @IO:C65 $D601.0 C65 UART RX byte ready flag (clear by reading $D600)
            -- @IO:C65 $D601.1 C65 UART RX overrun flag (clear by reading $D600)
            -- @IO:C65 $D601.2 C65 UART RX parity error flag (clear by reading $D600)
            -- @IO:C65 $D601.3 C65 UART RX framing error flag (clear by reading $D600)
            fastio_rdata(0) <= reg_status0_rx_full;
            fastio_rdata(1) <= reg_status1_rx_overrun;
            fastio_rdata(2) <= reg_status2_rx_parity_error;
            fastio_rdata(3) <= reg_status3_rx_framing_error;
            fastio_rdata(4) <= reg_status4_rx_idle_mode;
            fastio_rdata(5) <= reg_status5_tx_eot;
            fastio_rdata(6) <= reg_status6_tx_empty;
            fastio_rdata(7) <= reg_status7_xmit_on;              
          when x"2" =>
            -- @IO:C65 $D602 C65 UART control register
            fastio_rdata(0) <= reg_ctrl0_parity_even;
            fastio_rdata(1) <= reg_ctrl1_parity_enable;
            fastio_rdata(3 downto 2) <= reg_ctrl23_char_length_deduct;
            fastio_rdata(5 downto 4) <= unsigned(reg_ctrl45_sync_mode_flags);
            fastio_rdata(6) <= reg_ctrl6_rx_enable;
            fastio_rdata(7) <= reg_ctrl7_tx_enable;
          when x"3" =>
            -- @IO:C65 $D603 C65 UART baud rate divisor (low byte)
            fastio_rdata <= reg_divisor(7 downto 0);
          when x"4" =>
            -- @IO:C65 $D604 C65 UART baud rate divisor (high byte)
            fastio_rdata <= reg_divisor(15 downto 8);
          when x"5" =>
            -- @IO:C65 $D605 C65 UART interrupt mask register              
            fastio_rdata <= unsigned(reg_intmask);
          when x"6" =>
            -- @IO:C65 $D606 C65 UART interrupt flag register              
            fastio_rdata <= unsigned(reg_intflag);
          when x"7" =>
            -- @IO:C65 $D607 C65 UART 2-bit port data register (used for C65 keyboard)
            fastio_rdata(7 downto 2) <= (others => 'Z');
            fastio_rdata(1 downto 0) <= reg_porte_read;
          when x"8" =>
            -- @IO:C65 $D607 C65 UART 2-bit port data direction register (used for C65 keyboard)
            fastio_rdata(7 downto 2) <= (others => 'Z');
            fastio_rdata(1 downto 0) <= unsigned(reg_porte_ddr);
          when x"9" =>
            -- @IO:GS $D609 MEGA65 extended UART control register
            -- @IO:GS $D609.0 UART BAUD clock source: 1 = 7.09375MHz, 0 = 193.5MHz
            fastio_rdata(0) <= clock709375;
            fastio_rdata(7 downto 1) <= (others => '1');
          when x"d" =>
            -- @IO:GS $D60D DEBUG - Read hyper_trap_count: will be removed after debugging. XXX - Temporarily reading restore_up_ticks instead
            fastio_rdata(7 downto 0) <= unsigned(portg);
          when x"e" =>
            -- @IO:GS $D60E PMOD port A on FPGA board (data bits)
            fastio_rdata(7 downto 0) <= reg_portf_read;
          when x"f" =>
            -- @IO:GS $D60F PMOD port A on FPGA board (DDR)
            fastio_rdata(7 downto 0) <= unsigned(reg_portf_ddr);
          when others => fastio_rdata <= (others => 'Z');
        end case;
      end if;
    end if;
        
    if rising_edge(pixelclock) then

      if rx_clear_flags='1' then
        -- Clear byte read flag
        reg_status0_rx_full <= '0';
        -- Clear RX over-run flag
        reg_status1_rx_overrun <= '0';
        -- Clear RX parity error flag
        reg_status2_rx_parity_error <= '0';
        -- Clear RX framing error flag
        reg_status3_rx_framing_error <= '0';
      end if;
      
      if (baud_subcounter + baud_subcounter_step < 1048576) then
        baud_subcounter <= baud_subcounter + baud_subcounter_step;
        tick709375 <= '0';
      else
        baud_subcounter <= baud_subcounter + baud_subcounter_step - 1048576;

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
          baud_tick <= '0';
        else
          reg_tick_countdown <= reg_divisor;
          baud_tick <= '1';
        end if;
      end if;

      -- Keep track of last 16 samples, and update RX value accordingly.
      -- We require consensus to switch between 0 and 1
      rx_samples(15 downto 1) <= rx_samples(14 downto 0);
      rx_samples(0) <= uart_rx;
      if rx_samples = "1111111111111111" then
        filtered_rx <= '1';
      end if;
      if rx_samples = "0000000000000000" then
        filtered_rx <= '0';
      end if;
      
      if baud_tick = '1' then
        -- Here we have a clock tick that is 7.09375MHz/reg_divisor
        -- (or 193.5MHz/reg_divisor if clock709375 is not asserted).
        -- So we now have a clock which is the target baud rate.
        -- XXX We should adjust our timing position to try to match the phase
        -- of the sender, but we aren't doing that right now. Instead, we will
        -- use the simple consensus filtered RX signal, and just read it.

        -- Progress TX state machine
        uart_tx <= '1';
        if tx_in_progress = '0' and reg_status6_tx_empty='0' and reg_ctrl7_tx_enable='1' then
          -- Sent stop bit
          uart_tx <= '0';
          tx_in_progress <= '1';
          tx_bits_to_send <= 8 - to_integer(reg_ctrl23_char_length_deduct);
          tx_buffer <= reg_data_tx;
          reg_status6_tx_empty <= '1';
        end if;
        if tx_in_progress='1' then
          if tx_bits_to_send > 0 then
            uart_tx <= tx_buffer(0);
            tx_buffer(6 downto 0) <= tx_buffer(7 downto 1);
            tx_bits_to_send <= tx_bits_to_send - 1;
          else
            -- Stop bit
            -- XXX We don't support parity
            uart_tx <= '0';
            tx_stop_bit_sent <= '1';
          end if;
          if tx_stop_bit_sent = '1' then
            tx_in_progress <= '0';
            tx_stop_bit_sent <= '0';
          end if;
        end if;
        
        -- Progress RX state machine
        if rx_in_progress='0' then
          -- Not yet receiving a byte, so see if we see something interesting
          if filtered_rx='0' and reg_ctrl6_rx_enable='1' then
            -- Start bit
            rx_buffer <= (others => '1');
            rx_in_progress <= '1';
            rx_bits_remaining <= 8 - to_integer(reg_ctrl23_char_length_deduct);
          end if;
        else
          -- Receiving data, parity and/or stop bit
          if rx_bits_remaining > 0 then
            -- Receive next bit
            rx_buffer(6 downto 0) <= rx_buffer(7 downto 1);
            rx_buffer(7) <= filtered_rx;
            rx_bits_remaining <= rx_bits_remaining - 1;
          else
            -- Receive stop bit (or parity when we support it)
            rx_in_progress <= '0';
            -- Stop bit:
            if filtered_rx='0' then
              -- Received byte
              reg_status0_rx_full <= '1';
              if reg_status0_rx_full = '1' then
              end if;
              -- Allow short bytes
              case reg_ctrl23_char_length_deduct is
                when "01" => reg_data_rx(6 downto 0) <= rx_buffer(7 downto 1);
                             reg_data_rx(7) <= '1';
                when "10" => reg_data_rx(5 downto 0) <= rx_buffer(7 downto 2);
                             reg_data_rx(7 downto 6) <= (others => '1');
                when "11" => reg_data_rx(4 downto 0) <= rx_buffer(7 downto 3);
                             reg_data_rx(7 downto 5) <= (others => '1');
                when others => reg_data_rx <= rx_buffer;
              end case;
              -- XXX Work out parity and set state for reading it.
            else
              -- Framing error
              reg_status3_rx_framing_error <= '1';
              -- Make bad data visible, purely for debug purposes
              reg_data_rx <= rx_buffer;
            end if;
            -- XXX Assert IRQ and/or NMI according to RX interrupt masks
          end if;
        end if;
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
      if (fastio_write='1') and (fastio_address(19 downto 16) = x"D")
         and (fastio_address(11 downto 4) = x"60") then
        register_number := fastio_address(3 downto 0);
        case register_number is
          when x"0" =>
            reg_data_tx <= std_logic_vector(fastio_wdata);
            reg_status5_tx_eot <= '0';
            reg_status6_tx_empty <= '0';
          when x"1" => null;
          when x"2" =>
            fastio_rdata(0) <= reg_ctrl0_parity_even;
            fastio_rdata(1) <= reg_ctrl1_parity_enable;
            fastio_rdata(3 downto 2) <= unsigned(reg_ctrl23_char_length_deduct);
            fastio_rdata(5 downto 4) <= unsigned(reg_ctrl45_sync_mode_flags);
            fastio_rdata(6) <= reg_ctrl6_rx_enable;
            fastio_rdata(7) <= reg_ctrl7_tx_enable;
          when x"3" => reg_divisor(7 downto 0) <= fastio_wdata;
          when x"4" => reg_divisor(15 downto 8) <= fastio_wdata;
          when x"5" => reg_intmask <= std_logic_vector(fastio_wdata);
          when x"6" =>
            -- reg_intflag
            -- This register is not used in the C65 ROM, so we don't know how it
            -- should behave.  What is clear, is that there is some other mechanism
            -- besides reading this register that actually clears the IRQ.
            -- Perhaps just reading the data register is enough to clear an RX
            -- IRQ?  What about TX ready IRQ? It seems like writing a character
            -- or disabling the transmitter should clear it.
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
