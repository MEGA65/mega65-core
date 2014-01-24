library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

entity uart_monitor is
  port (
    reset : in std_logic;
    clock : in std_logic;
    tx : out std_logic;
    rx : in  std_logic;
    activity : out std_logic;

    monitor_pc : in std_logic_vector(15 downto 0);
    monitor_opcode : in std_logic_vector(7 downto 0);
    monitor_a : in std_logic_vector(7 downto 0);
    monitor_x : in std_logic_vector(7 downto 0);
    monitor_y : in std_logic_vector(7 downto 0);
    monitor_sp : in std_logic_vector(7 downto 0);
    monitor_p : in std_logic_vector(7 downto 0);
    
    monitor_mem_address : out std_logic_vector(27 downto 0);
    monitor_mem_rdata : in unsigned(7 downto 0);
    monitor_mem_wdata : out unsigned(7 downto 0);
    monitor_mem_register : in unsigned(15 downto 0);
    monitor_mem_attention_request : out std_logic := '0';
    monitor_mem_attention_granted : in std_logic;
    monitor_mem_read : out std_logic := '0';
    monitor_mem_write : out std_logic := '0';
    monitor_mem_setpc : out std_logic := '0';
    monitor_mem_stage_trace_mode : out std_logic := '0';
    monitor_mem_trace_mode : out std_logic := '0';
    monitor_mem_trace_toggle : out std_logic := '0'
    );
end uart_monitor;

architecture behavioural of uart_monitor is
  component UART_TX_CTRL is
    Port ( SEND : in  STD_LOGIC;
           DATA : in  STD_LOGIC_VECTOR (7 downto 0);
           CLK : in  STD_LOGIC;
           READY : out  STD_LOGIC;
           UART_TX : out  STD_LOGIC);
  end component;

  component uart_rx is
    Port ( clk : in  STD_LOGIC;
           UART_RX : in  STD_LOGIC;
           data : out  STD_LOGIC_VECTOR (7 downto 0);
           data_ready : out std_logic;
           data_acknowledge : in std_logic
           );
  end component;

-- raise for one cycle when we have a byte ready to send.
-- should only be asserted when tx_ready='1'.
  signal tx_trigger : std_logic := '0';
-- the byte to send.
  signal tx_data : std_logic_vector(7 downto 0);
-- indicates that uart is ready to TX the next byte.
  signal tx_ready : std_logic;

  signal rx_data : std_logic_vector(7 downto 0);
  signal rx_ready : std_logic;
  signal rx_acknowledge : std_logic := '0';

-- Counter for slow clock derivation (for testing at least)
  signal counter : unsigned(31 downto 0) := (others => '0');
  signal tx_counter : std_logic;

  signal blink : std_logic := '1';

  constant crlf : string := cr & lf;
  constant bannerMessage : String :=
    crlf &
    crlf &
    "--------------------------------" & crlf &
    "65GS Serial Monitor" & crlf &
    "--------------------------------" & crlf &
    "Type ? for help." & crlf;
  signal banner_position : integer := 1;
  constant helpMessage : String :=
    "? or h[elp]            - Display this help" & crlf &
    "f<low> <high> <byte>   - Fill memory from <low> to <high> with value <byte>" &    crlf &
    "g<address>             - Set PC to <address> and resume execution" & crlf &
    "m<address>             - Display contents of memory" & crlf &
    "r                      - Print processor state." & crlf &
    "s<address> <value> ... - Set memory." & crlf &
    "t<0|1>                 - Enable/disable tracing." & crlf &
    "t                      - Step one instruction if in trace mode." & crlf;

  constant errorMessage : string := crlf & "?SYNTAX  ERROR ";
  constant timeoutMessage : string := crlf & "?DEVICE NOT FOUND  ERROR" & crlf;

  constant registerMessage : string := crlf & "PC   A  X  Y  SP  P" & crlf;
  
  type monitor_state is (Reseting,
                         PrintBanner,PrintHelp,
                         PrintError,PrintError2,PrintError3,PrintError4,
                         PrintTimeoutError,
                         NextCommand,NextCommand2,PrintPrompt,
                         AcceptingInput,EraseCharacter,EraseCharacter1,
                         RedrawInputBuffer,RedrawInputBuffer2,RedrawInputBuffer3,
                         RedrawInputBuffer4,
                         EnterPressed,EnterPressed2,EnterPressed3,
                         EraseInputBuffer,
                         SyntaxError,TimeoutError,
                         CPUTransaction1,CPUTransaction2,CPUTransaction3,
                         ParseHex,
                         PrintHex,
                         SetMemory1,SetMemory2,SetMemory3,SetMemory4,SetMemory5,
                         SetMemory6,SetMemory7,SetMemory8,
                         LoadMemory1,LoadMemory2,LoadMemory3,LoadMemory4,
                         ShowMemory1,ShowMemory2,ShowMemory3,ShowMemory4,
                         ShowMemory5,ShowMemory6,ShowMemory7,ShowMemory8,
                         FillMemory1,FillMemory2,FillMemory3,FillMemory4,
                         FillMemory5,
                         SetPC1,
                         ShowRegisters,
                         ShowRegisters1,ShowRegisters2,ShowRegisters3,ShowRegisters4,
                         ShowRegisters5,ShowRegisters6,ShowRegisters7,ShowRegisters8,
                         ShowRegisters9,ShowRegisters10,ShowRegisters11,ShowRegisters12,
                         ShowRegisters13,ShowRegisters14,ShowRegisters15,
                         TraceStep,CPUBreak1,WaitOneCycle
                         );

  signal state : monitor_state := Reseting;
-- Buffer to hold entered command
  signal cmdbuffer : String(1 to 64);
  signal cmdlen : integer := 1;
  signal prev_cmdlen : integer := 1;
  signal redraw_position : integer;
  
  -- For parsing commands
  signal parse_position : integer := 2;
  signal hex_value : unsigned(31 downto 0);
  signal target_address : unsigned(27 downto 0);
  signal top_address : unsigned(27 downto 0);
  signal target_value : unsigned(7 downto 0);
  signal hex_digits_read : integer;
  signal hex_digits_output : integer;
  signal success_state : monitor_state;
  signal post_transaction_state : monitor_state;
  signal errorCode : unsigned(7 downto 0) := x"00";

  signal timeout : integer;
  
  type sixteenbytes is array (0 to 15) of unsigned(7 downto 0);
  signal membuf : sixteenbytes;
  signal byte_number : integer;

  signal key_state : integer := 0;

  -- Processor break point
  signal break_address : unsigned(15 downto 0) := x"0000";
  signal break_enabled : std_logic := '0';
  
  signal monitor_mem_trace_toggle_internal : std_logic := '0';
begin

  uart_tx0: uart_tx_ctrl
    port map (
      send    => tx_trigger,
      clk     => clock,
      data    => tx_data,
      ready   => tx_ready,
      uart_tx => tx);

  uart_rx0: uart_rx 
    Port map ( clk => clock,
               UART_RX => rx,
               data => rx_data,
               data_ready => rx_ready,
               data_acknowledge => rx_acknowledge);

  -- purpose: test uart output
  testclock: process (clock)
    -- purpose: turn character into std_logic_vector(7 downto 0)
    function to_std_logic_vector (
      c : character)
      return std_logic_vector is
      variable i : integer := character'pos(c);
      variable u : unsigned(7 downto 0) := to_unsigned(i,8);
    begin  -- to_std_logic_vector
      return std_logic_vector(u);
    end to_std_logic_vector;

    -- purpose: convert ascii value in a std_logic_vector to a VHDL character
    function to_character (
      v : std_logic_vector(7 downto 0))
      return character is
    begin  -- to_character
      return character'val(to_integer(unsigned(v)));   
    end to_character;
    
    -- purpose: Process a character typed by the user.
    procedure character_received (char : in character) is
    begin  -- character_received
      if (char >= ' ' and char < del) or char > c159 then
        if cmdlen<63 then
          -- Echo character back to user
          tx_data <= to_std_logic_vector(char);
          tx_trigger <= '1';
          -- Append to input buffer
          cmdbuffer(cmdlen) <= char;
          cmdlen <= cmdlen + 1;
        else
          -- Input buffer full, so ring bell.
          tx_data <= to_std_logic_vector(bel);
          tx_trigger <= '1';
        end if;
      else
        -- Non-printable character, for now print ?
        case key_state is
          when 2 =>
            key_state <= 0;
            case char is
              when 'A' => -- cursor UP
                -- Recall previous command (^P)
                cmdlen <= prev_cmdlen;
                redraw_position <= 1;
                state <= RedrawInputBuffer;
              when 'B' => null; -- cursor down
              when 'D' => null; -- cursor left
              when 'C' => null; -- cursor right                
              when others => null;
            end case;
          when 1 =>                     -- ESC mode
            case char is
              when '[' => key_state<=2;
              when others => key_state<=0;
            end case;
          when 0 =>                     -- Normal key input
            case char is
              when dle =>
                -- Recall previous command (^P)
                cmdlen <= prev_cmdlen;
                redraw_position <= 1;
                state <= RedrawInputBuffer;
              when dc2 =>
                -- Redraw line (^R)
                redraw_position <= 1;
                state <= RedrawInputBuffer;
              when nak =>
                -- Erase line (^U)
                state <= EraseInputBuffer;
              when esc => key_state <= 1;
              when bs =>
                if cmdlen>1 then
                  -- Delete character from end of line
                  tx_data <= to_std_logic_vector(bs);
                  tx_trigger <= '1';
                  cmdlen <= cmdlen - 1;          
                  state <= EraseCharacter;
                end if;
              when del =>
                if cmdlen>1 then
                  -- Delete character from end of line
                  tx_data <= to_std_logic_vector(bs);
                  tx_trigger <= '1';                    
                  cmdlen <= cmdlen - 1;          
                  state <= EraseCharacter;
                end if;
              when ack =>
                -- ^F move forward one character
                -- XXX not implemented
              when stx =>
                -- ^B move backward one character
                -- XXX not implemented
              when cr => state <= EnterPressed;
              when lf => state <= EnterPressed;
              when others =>
                tx_data <= to_std_logic_vector(bel);
                tx_trigger <= '1';                    
            end case;
          when others =>
            null;
        end case;
      end if;
    end character_received;

    -- purpose: If we can write a character, do so and advance the state
    procedure try_output_char (
      char       : in character;
      next_state : in monitor_state) is
    begin  -- try_output_char
      if tx_ready='1' then
        tx_data <= to_std_logic_vector(char);
        tx_trigger <= '1';
        state <= next_state;
      end if;
    end try_output_char;

    -- purpose: output a hex string
    procedure print_hex (
      value      : in unsigned(31 downto 0);
      digits     : in integer;
      next_state : in monitor_state) is
    begin  -- print_hex
      report "asked to print " & integer'image(digits) & " digits of " & to_hstring(value) severity note;
      hex_value <= value;
      hex_digits_read <= digits;
      hex_digits_output <= 0;
      success_state <= next_state;
      state <= PrintHex;
    end print_hex;
    procedure print_hex_addr (
      value      : in unsigned(27 downto 0);
      next_state : in monitor_state) is
    begin  -- print_hex
      print_hex(value & x"0",7,next_state);
    end print_hex_addr;
    procedure print_hex_byte (
      value      : in unsigned(7 downto 0);
      next_state : in monitor_state) is
    begin  -- print_hex
      print_hex(value & x"000000",2,next_state);
    end print_hex_byte;
    
    -- purpose: accept one hex digit
    procedure got_hex_digit (
      digit : in unsigned(3 downto 0)) is
    begin  -- got_hex_digit
      if hex_digits_read=8 then
        errorCode <= x"01";
        state <= SyntaxError;
      end if;
      hex_value <= hex_value(27 downto 0) & digit;
      hex_digits_read <= hex_digits_read + 1;
      parse_position <= parse_position + 1;
    end got_hex_digit;
    
    -- purpose: parse a hex digit
    procedure parse_hex_digit is
    begin  -- parse_hex_digit
      report "parse_hex_digit " & character'image(cmdbuffer(parse_position)) severity note;
      if parse_position>=cmdlen then
        if hex_digits_read = 0 then
          -- If we reach end of command and have parsed no digit, it's an error
          errorCode <= x"02";
          state <= SyntaxError;
        else
          state <= success_state;
        end if;
      else
        report "checkpoint parse_position=" & integer'image(parse_position)
          severity note;
        case cmdbuffer(parse_position) is
          when '0' => got_hex_digit(x"0"); when '1' => got_hex_digit(x"1");
          when '2' => got_hex_digit(x"2"); when '3' => got_hex_digit(x"3");
          when '4' => got_hex_digit(x"4"); when '5' => got_hex_digit(x"5");
          when '6' => got_hex_digit(x"6"); when '7' => got_hex_digit(x"7");
          when '8' => got_hex_digit(x"8"); when '9' => got_hex_digit(x"9");
          when 'a' => got_hex_digit(x"a"); when 'A' => got_hex_digit(x"a");
          when 'b' => got_hex_digit(x"b"); when 'B' => got_hex_digit(x"b");
          when 'c' => got_hex_digit(x"c"); when 'C' => got_hex_digit(x"c");
          when 'd' => got_hex_digit(x"d"); when 'D' => got_hex_digit(x"d");
          when 'e' => got_hex_digit(x"e"); when 'E' => got_hex_digit(x"e");
          when 'f' => got_hex_digit(x"f"); when 'F' => got_hex_digit(x"f");
          when others =>
            if hex_digits_read = 0 then
              errorCode <= x"03";
              state <= SyntaxError;
            else
              state <= success_state;
            end if;
        end case;
        report "checkpoint: hex_value = $" & to_hstring(hex_value)
          severity note;

      end if;
    end parse_hex_digit;

    function hex_char (
      nybl : unsigned(3 downto 0))
      return character is
    begin
      case nybl is
        when x"0" => return '0'; when x"1" => return '1';
        when x"2" => return '2'; when x"3" => return '3';
        when x"4" => return '4'; when x"5" => return '5';
        when x"6" => return '6'; when x"7" => return '7';
        when x"8" => return '8'; when x"9" => return '9';
        when x"a" => return 'A'; when x"b" => return 'B';
        when x"c" => return 'C'; when x"d" => return 'D';
        when x"e" => return 'E'; when x"f" => return 'F';
        when others => return '?';
      end case;
    end hex_char;
    
    -- purpose: parse a hex string from the command buffer
    procedure parse_hex (
      next_state : in monitor_state) is
    begin  -- parse_hex
      success_state <= next_state;
      state <= ParseHex;
      hex_value <= (others => '0');
      hex_digits_read <= 0;    
    end parse_hex;

    -- purpose: skip one space in command buffer
    procedure skip_space (
      next_state : monitor_state) is
    begin  -- skip_space
      if parse_position<cmdlen and cmdbuffer(parse_position)=' ' then
        parse_position <= parse_position + 1;
        state <= next_state;
      else
        errorCode <= x"04";
        state <= SyntaxError;
      end if;
    end skip_space;

    -- purpose: succeed if at end of command
    procedure end_of_command (
      next_state : monitor_state) is
    begin
      if parse_position>=cmdlen then
        state <= next_state;
      else
        errorCode <= x"05";        
        state <= SyntaxError;
      end if;
    end end_of_command;

    -- purpose: perform a memory read or write from the CPU
    procedure cpu_transaction (
      next_state : in monitor_state) is
    begin  -- cpu_transaction
      monitor_mem_attention_request <= '0';
      post_transaction_state <= next_state;
      timeout <= 65535;
      state <= CPUTransaction1;
    end cpu_transaction;
    
  begin  -- process testclock
    if reset='0' then
      state <= Reseting;
      key_state <= 0;
    elsif rising_edge(clock) then

      -- Stop CPU when we reach the specified location
      if break_enabled='1' and break_address = unsigned(monitor_pc) then
        monitor_mem_trace_mode <= '1';
      end if;
      
      -- Update counter and clear outputs
      counter <= counter + 1;
      tx_counter <= std_logic(counter(27));
      rx_acknowledge <= '0';
      tx_trigger<='0';

      -- Make sure we don't leave the CPU locked
      if rx_ready='1' then
        monitor_mem_read <= '0';
        monitor_mem_write <= '0';
        monitor_mem_attention_request <= '0';
      end if;
      
      -- 1 cycle delay after sending characters
      if tx_trigger/='1' then      
        -- General state machine
        case state is
          when Reseting =>
            banner_position <= 1;
            state <= PrintBanner;
          when PrintHelp =>
            if tx_ready='1' then
              tx_data <= to_std_logic_vector(helpMessage(banner_position));
              tx_trigger <= '1';
              if banner_position<helpMessage'length then
                banner_position <= banner_position + 1;
              else
                state <= PrintPrompt;
                cmdlen <= 1;
              end if;
            end if;
          when PrintBanner =>
            if tx_ready='1' then
              tx_data <= to_std_logic_vector(bannerMessage(banner_position));
              tx_trigger <= '1';
              if banner_position<bannerMessage'length then
                banner_position <= banner_position + 1;
              else
                state <= NextCommand;
                cmdlen <= 1;
              end if;
            end if;
          when PrintError =>
            if tx_ready='1' then
              tx_data <= to_std_logic_vector(errorMessage(banner_position));
              tx_trigger <= '1';
              if banner_position<errorMessage'length then
                banner_position <= banner_position + 1;
              else
                print_hex_byte(errorCode,PrintError2);
              end if;
            end if;
          when PrintError2 => try_output_char(cr,PrintError3);
          when PrintError3 => try_output_char(lf,PrintError4);
          when PrintError4 =>
            if parse_position<cmdlen then
              if tx_ready='1' then
                parse_position <= parse_position + 1;
                try_output_char(cmdbuffer(parse_position),PrintError3);
              end if;
            else
              state <= NextCommand;
            end if;
          when PrintTimeoutError =>
            if tx_ready='1' then
              tx_data <= to_std_logic_vector(timeoutMessage(banner_position));
              tx_trigger <= '1';
              if banner_position<timeoutMessage'length then
                banner_position <= banner_position + 1;
              else
                state <= NextCommand;
              end if;
            end if;
          when NextCommand => cmdlen <= 1; try_output_char(cr,NextCommand2);
          when NextCommand2 => try_output_char(lf,PrintPrompt);
          when PrintPrompt => cmdlen <= 1; try_output_char('.',AcceptingInput);
          when AcceptingInput =>
            -- If there is a character waiting
            if rx_ready = '1' and rx_acknowledge='0' then
              blink <= not blink;
              activity <= blink;
              rx_acknowledge<='1';
              character_received(to_character(rx_data));
            end if;
          when RedrawInputBuffer => try_output_char(cr,RedrawInputBuffer2);
          when RedrawInputBuffer2 => redraw_position <= 1; try_output_char('.',RedrawInputBuffer3);
          when RedrawInputBuffer3 =>
            if redraw_position<64 then
              if tx_ready='1' then
                if redraw_position<cmdlen then
                  try_output_char(cmdbuffer(redraw_position),RedrawInputBuffer3);
                else
                  try_output_char(' ',RedrawInputBuffer3);
                end if;
                redraw_position <= redraw_position + 1;                
              end if;
            else
              state <= RedrawInputBuffer4;
            end if;
          when RedrawInputBuffer4 =>
            if redraw_position>cmdlen then
              if tx_ready='1' then
                try_output_char(bs,RedrawInputBuffer4);
                redraw_position <= redraw_position - 1;
              end if;
            else
              state <= AcceptingInput;
            end if;
          when EraseInputBuffer =>
            redraw_position<=1;
            cmdlen <= 1;
            state <= RedrawInputBuffer;
          when EnterPressed =>
            prev_cmdlen <= cmdlen;
            parse_position<=2; try_output_char(cr,EnterPressed2);
          when EnterPressed2 => try_output_char(lf,EnterPressed3);
          when EnterPressed3 =>
            if cmdlen>1 then              
              if (cmdbuffer(1) = 'h' or cmdbuffer(1) = 'H' or cmdbuffer(1) = '?') then
                banner_position <= 1;
                state <= PrintHelp;
              elsif cmdbuffer(1) = 's' or cmdbuffer(1) = 'S' then
                parse_position <= 2;
                parse_hex(SetMemory1);
              elsif cmdbuffer(1) = 'f' or cmdbuffer(1) = 'F' then
                parse_position <= 2;
                parse_hex(FillMemory1);
              elsif cmdbuffer(1) = 'g' or cmdbuffer(1) = 'G' then
                parse_position <= 2;
                parse_hex(SetPC1);
              elsif cmdbuffer(1) = 'r' or cmdbuffer(1) = 'R' then
                state <= ShowRegisters;                
              elsif cmdbuffer(1) = 't' or cmdbuffer(1) = 'T' then
                if cmdbuffer(2)='2' then
                  monitor_mem_stage_trace_mode<='1';
                elsif cmdbuffer(2)='1' then
                  monitor_mem_trace_mode<='1';
                  state <= NextCommand;
                elsif cmdbuffer(2)='0' then
                  monitor_mem_trace_mode<='0';
                  state <= NextCommand;
                else
                  state <= TraceStep;
                end if;
              elsif cmdbuffer(1) = 'b' or cmdbuffer(1) = 'B' then
                report "CPU break command" severity note;
                parse_position <= 2;
                report "trying to parse hex" severity note;
                parse_hex(CPUBreak1);
              elsif cmdbuffer(1) = 'd' or cmdbuffer(1) = 'B' then
                break_enabled <= '0';
              elsif cmdbuffer(1) = 'l' or cmdbuffer(1) = 'L' then
                report "load memory command" severity note;
                parse_position <= 2;
                report "trying to parse hex" severity note;
                parse_hex(LoadMemory1);
              elsif cmdbuffer(1) = 'm' or cmdbuffer(1) = 'M' then
                report "read memory command" severity note;
                parse_position <= 2;
                report "trying to parse hex" severity note;
                parse_hex(ShowMemory1);
              else
                errorCode <= x"06";
                state <= SyntaxError;
              end if;
            else
              -- On empty line toggle trace flag so that CPU knows it can do one more instruction
              monitor_mem_trace_toggle <= not monitor_mem_trace_toggle_internal;
              monitor_mem_trace_toggle_internal <= not monitor_mem_trace_toggle_internal;

              cmdlen <= 1;
              state <= ShowRegisters;
            end if;
          when FillMemory1 =>
            target_address <= hex_value(27 downto 0);
            skip_space(FillMemory2);
          when FillMemory2 =>
            parse_hex(FillMemory3);
          when FillMemory3 =>
            top_address <= hex_value(27 downto 0);
            skip_space(FillMemory4);
          when FillMemory4 =>
            parse_hex(FillMemory5);            
          when FillMemory5 =>
            -- hex_value(7 downto 0) has the fill value
            if target_address = top_address then
              state <= NextCommand;
            else
              monitor_mem_write <= '1';
              monitor_mem_read <= '0';
              monitor_mem_address <= std_logic_vector(target_address);
              monitor_mem_wdata <= hex_value(7 downto 0);
              target_address <= target_address + 1;
              cpu_transaction(FillMemory5);
            end if;
          when LoadMemory1 => target_address <= hex_value(27 downto 0);
                             skip_space(LoadMemory2);
          when LoadMemory2 => parse_hex(LoadMemory3);
          when LoadMemory3 =>
            if target_address(15 downto 0) /= hex_value(15 downto 0) then
              -- check for character
              if rx_ready = '1' and rx_acknowledge='0' then
                blink <= not blink;
                activity <= blink;
                rx_acknowledge<='1';

                monitor_mem_read <= '0';
                monitor_mem_write <= '1';
                monitor_mem_address <= std_logic_vector(target_address);
                monitor_mem_wdata <= unsigned(rx_data);

                target_address(15 downto 0) <= target_address(15 downto 0) + 1;
                
                timeout <= 65535;
                cpu_transaction(ShowMemory3);
              end if;
            else
              state <= NextCommand;
            end if;
          when SetMemory1 => target_address <= hex_value(27 downto 0);
                             skip_space(SetMemory2);
          when SetMemory2 => parse_hex(SetMemory3);
          when SetMemory3 =>
            target_value <= hex_value(7 downto 0);
            parse_position <= parse_position + 1;
            state <= SetMemory4;
          when SetMemory4 =>
            monitor_mem_write <= '1';
            monitor_mem_read <= '0';
            monitor_mem_address <= std_logic_vector(target_address);
            monitor_mem_wdata <= target_value;
            cpu_transaction(SetMemory8);
          when SetMemory5 => try_output_char('=',SetMemory6);
          when SetMemory6 => print_hex_addr(target_address,SetMemory7);
          when SetMemory7 => try_output_char(' ',SetMemory8);
          when SetMemory8 =>
            target_address <= target_address + 1;
            if parse_position < cmdlen then
              print_hex_byte(target_value,SetMemory2);
            else
              state <= NextCommand;
            end if;
          when ParseHex => parse_hex_digit;
          when PrintHex =>
            if hex_digits_output<hex_digits_read then
              if tx_ready='1' then
                try_output_char(hex_char(hex_value(31 downto 28)),PrintHex);
                hex_digits_output <= hex_digits_output + 1;
                hex_value <= hex_value(27 downto 0) & x"0";
              end if;
            else
              state <= success_state;
            end if;
          when ShowMemory1 =>
            -- XXX Need to actually read memory from the CPU
            target_address <= hex_value(27 downto 0);
            byte_number <= 0;
            end_of_command(ShowMemory2);              
          when ShowMemory2 =>
            if byte_number=16 then
              state <= ShowMemory4;
            else
              monitor_mem_read <= '1';
              monitor_mem_write <= '0';
              monitor_mem_address <= std_logic_vector(target_address + to_unsigned(byte_number,28));
              timeout <= 65535;
              cpu_transaction(ShowMemory3);
            end if;
          when ShowMemory3 =>
            if tx_ready='1' then
              membuf(byte_number) <= monitor_mem_rdata;
              byte_number <= byte_number +1;
              state <= ShowMemory2;
            end if;
          when ShowMemory4 => try_output_char(' ',ShowMemory5);
          when ShowMemory5 => try_output_char(':',ShowMemory6); byte_number <= 0;
          when ShowMemory6 => print_hex_addr(target_address,ShowMemory7);
          when ShowMemory7 =>
            if byte_number = 16 then
              state<=NextCommand;
            else
              try_output_char(' ',ShowMemory8);
            end if;
          when ShowMemory8 =>
            byte_number <= byte_number + 1;
            print_hex_byte(membuf(byte_number),ShowMemory7);
          when ShowRegisters =>
            banner_position <= 1; state<= ShowRegisters1;
            monitor_mem_setpc <= '0';
          when ShowRegisters1 =>
            if tx_ready='1' then
              tx_data <= to_std_logic_vector(registerMessage(banner_position));
              tx_trigger <= '1';
              if banner_position<registerMessage'length then
                banner_position <= banner_position + 1;
              else
                state <= ShowRegisters2;
              end if;
            end if;
          when ShowRegisters2 =>
            print_hex_byte(unsigned(monitor_pc(15 downto 8)),ShowRegisters3);
          when ShowRegisters3 =>
            print_hex_byte(unsigned(monitor_pc(7 downto 0)),ShowRegisters4);
          when ShowRegisters4 => try_output_char(' ',ShowRegisters5);
          when ShowRegisters5 => print_hex_byte(unsigned(monitor_a),ShowRegisters6);
          when ShowRegisters6 => try_output_char(' ',ShowRegisters7);
          when ShowRegisters7 => print_hex_byte(unsigned(monitor_x),ShowRegisters8);
          when ShowRegisters8 => try_output_char(' ',ShowRegisters9);
          when ShowRegisters9 => print_hex_byte(unsigned(monitor_y),ShowRegisters10);
          when ShowRegisters10 => try_output_char(' ',ShowRegisters11);
          when ShowRegisters11 => print_hex_byte(unsigned(monitor_sp),ShowRegisters12);
          when ShowRegisters12 => try_output_char(' ',ShowRegisters13);
          when ShowRegisters13 => print_hex_byte(unsigned(monitor_p),ShowRegisters14);
          when ShowRegisters14 => try_output_char(' ',NextCommand);
          when EraseCharacter => try_output_char(' ',EraseCharacter1);
          when EraseCharacter1 => try_output_char(bs,AcceptingInput);
          when SyntaxError =>
            banner_position <= 1; state <= PrintError;
          when TimeoutError =>
            banner_position <= 1; state <= PrintTimeoutError;
          when SetPC1 =>
            monitor_mem_address(15 downto 0) <= std_logic_vector(hex_value(15 downto 0));
            monitor_mem_read <= '1';
            monitor_mem_setpc <= '1';
            monitor_mem_write <= '0';
            cpu_transaction(ShowRegisters);
          when CPUTransaction1 =>
            if monitor_mem_attention_granted='0' then
              monitor_mem_attention_request <= '1';
              timeout <= 65535;
              state <=CPUTransaction2;
            else
              if timeout=0 then
                state <= TimeoutError;
              end if;
              timeout <= timeout - 1;
            end if;
          when CPUTransaction2 =>
            if monitor_mem_attention_granted='1' then
              -- Attention being granted implies that request has been fulfilled.
              monitor_mem_attention_request <= '0';
              timeout <= 65535;
              state <= CPUTransaction3;
            else
              if timeout=0 then
                state <= TimeoutError;
              end if;
              timeout <= timeout - 1;
            end if;
          when CPUTransaction3 =>
            if monitor_mem_attention_granted = '0' then
              state <= post_transaction_state;
            else
              if timeout=0 then
                state <= TimeoutError;
              end if;
              timeout <= timeout - 1;              
            end if;
          when CPUBreak1 =>
            break_address <= hex_value(15 downto 0);
            break_enabled <= '1';
            state <= NextCommand;
          when TraceStep =>
            -- Toggle trace flag so that CPU knows it can do one more instruction
            monitor_mem_trace_toggle <= not monitor_mem_trace_toggle_internal;
            monitor_mem_trace_toggle_internal <= not monitor_mem_trace_toggle_internal;
            -- Give CPU a couple of cycles to leave instruction fetch state
            post_transaction_state <= ShowRegisters;
            state <= WaitOneCycle;
          when WaitOneCycle => state <= post_transaction_state;
          when others => null;
        end case;
      end if;
    end if;
  end process testclock;
  
end behavioural;
