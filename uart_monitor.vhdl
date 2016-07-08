--
-- Written by
--    Paul Gardner-Stephen <hld@c64.org>  2013-2014
--
-- *  This program is free software; you can redistribute it and/or modify
-- *  it under the terms of the GNU Lesser General Public License as
-- *  published by the Free Software Foundation; either version 3 of the
-- *  License, or (at your option) any later version.
-- *
-- *  This program is distributed in the hope that it will be useful,
-- *  but WITHOUT ANY WARRANTY; without even the implied warranty of
-- *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- *  GNU General Public License for more details.
-- *
-- *  You should have received a copy of the GNU Lesser General Public License
-- *  along with this program; if not, write to the Free Software
-- *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
-- *  02111-1307  USA.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.version.all;

entity uart_monitor is
  port (
    reset : in std_logic;
    clock : in std_logic;
    tx : out std_logic;
    rx : in  std_logic;
    activity : out std_logic;

    key_scancode : out unsigned(15 downto 0);
    key_scancode_toggle : out std_logic;

    force_single_step : in std_logic;
    
    fastio_read : in std_logic;
    fastio_write : in std_logic;
    
    monitor_proceed : in std_logic;
    monitor_waitstates : in unsigned(7 downto 0);
    monitor_request_reflected : in std_logic;
    monitor_pc : in unsigned(15 downto 0);
    monitor_cpu_state : in unsigned(15 downto 0);
    monitor_hypervisor_mode : in std_logic;
    monitor_ddr_ram_banking : in std_logic;
    monitor_instruction : in unsigned(7 downto 0);
    monitor_watch : out unsigned(27 downto 0) := x"7FFFFFF";
    monitor_watch_match : in std_logic;
    monitor_opcode : in unsigned(7 downto 0);
    monitor_ibytes : in std_logic_vector(3 downto 0);
    monitor_arg1 : in unsigned(7 downto 0);
    monitor_arg2 : in unsigned(7 downto 0);
    monitor_a : in unsigned(7 downto 0);
    monitor_x : in unsigned(7 downto 0);
    monitor_y : in unsigned(7 downto 0);
    monitor_z : in unsigned(7 downto 0);
    monitor_b : in unsigned(7 downto 0);
    monitor_sp : in unsigned(15 downto 0);
    monitor_p : in unsigned(7 downto 0);
    monitor_map_offset_low : in unsigned(11 downto 0);
    monitor_map_offset_high : in unsigned(11 downto 0);
    monitor_map_enables_low : in std_logic_vector(3 downto 0);
    monitor_map_enables_high : in std_logic_vector(3 downto 0);
    monitor_interrupt_inhibit : in std_logic;

    monitor_char : in unsigned(7 downto 0);
    monitor_char_toggle : in std_logic;

    monitor_mem_address : out unsigned(27 downto 0);
    monitor_mem_rdata : in unsigned(7 downto 0);
    monitor_mem_wdata : out unsigned(7 downto 0);
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

  component ram128x1k IS
    PORT (
      clk : IN STD_LOGIC;
      w : IN STD_LOGIC;
      addr : IN integer range 0 to 1023;
      din : IN unsigned(176 downto 0);
      dout : OUT unsigned(176 downto 0)
    );
  END component;

  signal monitor_char_toggle_last : std_logic := '1';
  signal monitor_char_count : unsigned(15 downto 0) := x"0000";
  
  signal history_record : std_logic := '1';
  signal history_record_continuous : std_logic := '0';
  signal history_address : integer range 0 to 1023 := 0;
  signal history_write : std_logic := '0';
  signal history_wdata : unsigned(176 downto 0);
  signal history_rdata : unsigned(176 downto 0);
  signal history_buffer : unsigned(176 downto 0);
  
  signal monitor_mem_byte : unsigned(7 downto 0) := x"BD";

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

  signal blink : std_logic := '1';

  signal trace_continuous : std_logic := '0';
  
  constant crlf : string := cr & lf;

  constant bannerMessage : String :=
    crlf &
    crlf &
    "--------------------------------" & crlf &
    "MEGA65 Serial Monitor" & crlf &
    "build " & gitcommit & crlf &
    "--------------------------------" & crlf &
    "Type ?/h/H for help." & crlf;

  signal banner_position : integer range 0 to 511 := 1;

  constant helpMessage : String :=
    "f<low> <high> <byte> - Fill memory" &    crlf &
    "g<addr> - Set PC" & crlf &
    "m<addr> - Dump memory (28bit addresses) (1-line)" & crlf &
    "M<addr> - Dump memory (28bit addresses) (32-lines)" & crlf &
    "d<addr> - Dump memory (CPU context) (1-line)" & crlf &
    "D<addr> - Dump memory (CPU context) (32-lines)" & crlf &
    "r/R - Print registers" & crlf &
    "c/C - UNSURE" & crlf &
    "e/E - UNSURE" & crlf &
    "z/Z - UNSURE" & crlf &
    "l/L - UNSURE" & crlf &
    "w/W - UNSURE" & crlf &
    "?/h/H - this help" & crlf &
    "s<addr> <value> ... - Set memory (28bit addresses)" & crlf &
    "S<addr> <value> ... - Set memory (CPU memory context)" & crlf &
    "b - Clear CPU breakpoint" & crlf &
    "b<addr> - Set CPU breakpoint" & crlf &
    "t<0|1|2> - Enable/disable tracing" & crlf &
    "tc - Traced execution until keypress" & crlf &
    "t|BLANK LINE - Step one cpu cycle if in trace mode" & crlf;

  constant errorMessage : string := crlf & "?SYNTAX  ERROR ";
  constant timeoutMessage : string := crlf & "?CPU NOT READY  ERROR" & crlf;
  constant requestTimeoutMessage : string := crlf & "?REQUEST TIMEOUT  ERROR" & crlf;
  constant replyTimeoutMessage : string := crlf & "?REPLY TIMEOUT  ERROR" & crlf;

  constant registerMessage : string := crlf & "PC   A  X  Y  Z  B  SP   MAPL MAPH LAST-OP     P  P-FLAGS   RGP uS IO" & crlf;
  
  type monitor_state is (Reseting,
                         PrintBanner,PrintHelp,
                         PrintError,PrintError2,PrintError3,PrintError4,
                         PrintRequestTimeoutError,
                         PrintReplyTimeoutError,
                         NextCommand,NextCommand2,PrintPrompt,
                         AcceptingInput,EraseCharacter,EraseCharacter1,
                         RedrawInputBuffer,RedrawInputBuffer2,RedrawInputBuffer3,
                         RedrawInputBuffer4,
                         EnterPressed,EnterPressed2,EnterPressed3,
                         EraseInputBuffer,
                         SyntaxError,
                         RequestError,
                         RequestTimeoutError,
                         ReplyTimeoutError,
                         CPUTransaction1,CPUTransaction2,CPUTransaction3,
                         ParseHex,
                         PrintHex,PrintSpaces,
                         ParseFlagBreak,                         
                         Watch1,
                         SetMemory1,SetMemory2,SetMemory3,SetMemory4,SetMemory5,
                         SetMemory6,SetMemory7,SetMemory8,
                         LoadMemory1,LoadMemory2,LoadMemory3,LoadMemory4,
                         ShowMemoryCPU1,
                         ShowMemory1,ShowMemory2,ShowMemory3,ShowMemory4,
                         ShowMemory5,ShowMemory6,ShowMemory7,ShowMemory8,
                         ShowMemory9,
                         CPUHistory,CPUHistory1,
                         CPUStateLog,CPUStateLog2,CPUStateLog3,CPUStateLog4,
                         FillMemory1,FillMemory2,FillMemory3,FillMemory4,
                         FillMemory5,
                         SetPC1,
                         ShowRegisters,ShowRegistersDelay,ShowRegistersRead,
                         ShowRegisters1,ShowRegisters2,ShowRegisters3,ShowRegisters4,
                         ShowRegisters5,ShowRegisters6,ShowRegisters7,ShowRegisters8,
                         ShowRegisters9,ShowRegisters10,ShowRegisters11,ShowRegisters12,
                         ShowRegisters13,ShowRegisters14,ShowRegisters15,ShowRegisters16,
                         ShowRegisters17,ShowRegisters18,ShowRegisters19,ShowRegisters20,
                         ShowRegisters21,ShowRegisters22,ShowRegisters23,ShowRegisters24,
                         ShowRegisters25,ShowRegisters26,ShowRegisters27,ShowRegisters28,
                         ShowRegisters29,ShowRegisters30,ShowRegisters31,ShowRegisters32,
                         ShowRegisters33,
                         ShowP1,ShowP2,ShowP3,ShowP4,ShowP5,ShowP6,ShowP7,ShowP8,
                         ShowP9,ShowP10,ShowP11,ShowP12,ShowP13a,
                         ShowP13,ShowP14,ShowP15,ShowP16,ShowP17,
                         ShowP18,ShowP19,ShowP20,
                         TraceStep,CPUBreak1,WaitOneCycle
                         );

  subtype command_len_t is integer range 0 to 64;
  type    command_len_history_t is array (0 to 15) of command_len_t;
  subtype command_t is String(1 to 64);
  type    command_history_t is array (0 to 15) of command_t;
  signal command_history : command_history_t;
  signal command_lengths : command_len_history_t := (others => 0);
  signal command_history_next : integer range 0 to 15 := 0;
  
  signal state : monitor_state := Reseting;
-- Buffer to hold entered command
  signal cmdbuffer : command_t;
  signal cmdlen : integer range 1 to 65 := 1;
  signal prev_cmdlen : integer range 1 to 65 := 1;
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
  signal byte_number : integer range 0 to 16;
  signal line_number : integer range 0 to 31;

  signal key_state : integer range 0 to 5 := 0;

  signal key_scancode_toggle_internal : std_logic := '0';

  -- Processor break point
  signal break_address : unsigned(15 downto 0) := x"0000";
  signal break_enabled : std_logic := '0';
  signal flag_break_enabled : std_logic := '0';
  -- upper bits are flags to be set to trigger break:
  -- Break if (P & flag_break_mask(15 downto 8))
  -- lower bits are flags to be clear to break:
  -- Break if ((~P) & flag_break_mask(7 downto 0))
  signal flag_break_mask : unsigned(15 downto 0) := x"0000";
  
  signal monitor_mem_trace_toggle_internal : std_logic := '0';

  -- Remember last 16 CPU states prior to hitting ProcessorHold
  type sixteenwords is array (0 to 15) of unsigned(15 downto 0);
  signal cpu_state_buf : sixteenwords;
  signal cpu_state_count : integer range 0 to 16;
  signal cpu_state_was_hold : std_logic := '0';

  signal show_register_delay : integer range 0 to 255;
  
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

  historyram0: ram128x1k
    port map ( clk => clock,
               w => history_write,
               addr => history_address,
               din => history_wdata,
               dout => history_rdata);
  
  -- purpose: test uart output
  testclock: process (clock,reset)
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
      if ((char >= ' ' and char < del) or (char > c159)) and (key_state=0) then
        if cmdlen<65 then
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

          -- Remote keyboard
          when 3 =>
            key_scancode(7 downto 0) <= unsigned(to_std_logic_vector(char));
            key_state <= 4;
          when 4 => 
            key_scancode(15 downto 8) <= unsigned(to_std_logic_vector(char));
            key_scancode_toggle <= not key_scancode_toggle_internal;
            key_scancode_toggle_internal <= not key_scancode_toggle_internal;
            key_state <= 0;

          -- Cursor movement
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

          -- ESC pressed, work out state following
          when 1 =>                     -- ESC mode
            case char is
              when '[' => key_state<=2; -- cursor movement etc
              when 'K' => key_state <= 3; -- ESC-K-scanlo-scanhi for remote keyboard
              when others => key_state<=0;
            end case;

          -- Normal key input
          when 0 =>
            case char is
              --when so =>
              --  -- Recall next command in history
              --  if command_history_recall = 15 then
              --    command_history_recall <= 0;
              --  else
              --    command_history_recall <= command_history_recall + 1;
              --  end if;
              --  cmdlen <= 0;
              --  state <= RecallHistory;
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
	 
    procedure print_spaces (
      digits     : in integer;
      next_state : in monitor_state) is
    begin  -- print_hex
      report "asked to print " & integer'image(digits) & " spaces." severity note;
      hex_digits_read <= digits;
      hex_digits_output <= 0;
      success_state <= next_state;
      state <= PrintSpaces;
    end print_spaces;
	 
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
	 
    procedure print_two_spaces (
      next_state : in monitor_state) is
    begin  -- print_hex
      print_spaces(2,next_state);
    end print_two_spaces;
    
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
      trace_continuous <= '0';
    elsif rising_edge(clock) then

      -- Allow a hardware switch to force stopping of the CPU
      if force_single_step='1' then
        monitor_mem_trace_mode<='1';
      end if;
      
      -- Maintain list of recent CPU states
      if (monitor_cpu_state(15 downto 8) /= x"0B") then
        if cpu_state_was_hold='1' then
          cpu_state_buf(0) <= monitor_cpu_state;
          cpu_state_count <= 1;
        else
          if (cpu_state_count < 16) then
            cpu_state_buf(cpu_state_count) <= monitor_cpu_state;
            cpu_state_count <= cpu_state_count + 1;
          end if;
        end if;
        cpu_state_was_hold <= '0';
      else
        cpu_state_was_hold <= '1';
      end if;      

      if history_record='1' and (history_address < 1023) then
        history_write <= '1';
        history_address <= history_address + 1;
      else
        -- Stop recording once we have 1024 entries, unless we are doing continuous
        -- recording.
        history_write <= history_record_continuous;
        history_record <= history_record_continuous;
      end if;
      history_wdata(7 downto 0) <= monitor_p;
      history_wdata(15 downto 8) <= monitor_a;
      history_wdata(23 downto 16) <= monitor_x;
      history_wdata(31 downto 24) <= monitor_y;
      history_wdata(39 downto 32) <= monitor_z;
      history_wdata(55 downto 40) <= monitor_pc;
      history_wdata(71 downto 56) <= unsigned(monitor_cpu_state);
      history_wdata(79 downto 72) <= monitor_waitstates;
      history_wdata(87 downto 80) <= monitor_b;
      history_wdata(104 downto 89) <= monitor_sp;
      history_wdata(112 downto 105)
        <= unsigned(monitor_map_enables_low)
        & monitor_map_offset_low(11 downto 8);
      history_wdata(120 downto 113) <= monitor_map_offset_low(7 downto 0);
      history_wdata(121) <= monitor_ibytes(1);
      history_wdata(122) <= fastio_read;
      history_wdata(123) <= fastio_write;
      history_wdata(124) <= monitor_proceed;
      history_wdata(125) <= monitor_mem_attention_granted;
      history_wdata(126) <= monitor_request_reflected;
      history_wdata(127) <= monitor_interrupt_inhibit;
      
      history_wdata(135 downto 128)
        <= unsigned(monitor_map_enables_high)
        & monitor_map_offset_high(11 downto 8);
      history_wdata(143 downto 136) <= monitor_map_offset_high(7 downto 0);
      history_wdata(151 downto 144) <= monitor_opcode;
      history_wdata(159 downto 152) <= monitor_arg1;
      history_wdata(167 downto 160) <= monitor_arg2;
      history_wdata(175 downto 168) <= monitor_instruction;
      history_wdata(176) <= monitor_ibytes(0);

      -- Stop CPU when we reach the specified location
      if break_enabled='1' and break_address = unsigned(monitor_pc) then
        monitor_mem_trace_mode <= '1';
      end if;
      -- Stop CPU when specified memory location is written to
      if monitor_watch_match='1' then
        monitor_mem_trace_mode <= '1';
      end if;
      -- Stop CPU on flag change
      if flag_break_enabled='1' and
        (
        ((std_logic_vector(monitor_p) and std_logic_Vector(flag_break_mask(15 downto 8))) /= x"00")
        or ((std_logic_vector(not monitor_p) and std_logic_Vector(flag_break_mask(7 downto 0))) /= x"00")
        )
      then
        monitor_mem_trace_mode <= '1';
      end if;
      
      -- Update counter and clear outputs
      counter <= counter + 1;
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
				
          when PrintRequestTimeoutError =>
            monitor_mem_attention_request <= '0';
            if tx_ready='1' then
              tx_data <= to_std_logic_vector(requestTimeoutMessage(banner_position));
              tx_trigger <= '1';
              if banner_position<requestTimeoutMessage'length then
                banner_position <= banner_position + 1;
              else
                state <= NextCommand;
              end if;
            end if;
				
          when PrintReplyTimeoutError =>
            monitor_mem_attention_request <= '0';
            if tx_ready='1' then
              tx_data <= to_std_logic_vector(replyTimeoutMessage(banner_position));
              tx_trigger <= '1';
              if banner_position<replyTimeoutMessage'length then
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
            if monitor_char_toggle /= monitor_char_toggle_last then
              monitor_char_toggle_last <= monitor_char_toggle;
              try_output_char(character'val(to_integer(monitor_char)),
                              AcceptingInput);
              if monitor_char_count < 65535 then
                monitor_char_count <= monitor_char_count + 1;
              else
                monitor_char_count <= x"0000";
              end if;
            elsif rx_ready = '1' and rx_acknowledge='0' then
              blink <= not blink;
              activity <= blink;
              rx_acknowledge<='1';
              trace_continuous <= '0';
              character_received(to_character(rx_data));
            end if;
            if trace_continuous='1' then
              state <= EnterPressed;
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
              elsif cmdbuffer(1) = 'c' or cmdbuffer(1) = 'C' then
                print_hex("000000"&monitor_char_toggle&monitor_char_toggle_last&monitor_char&monitor_char_count,7,NextCommand);
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
                elsif cmdbuffer(2)='c' then
                  monitor_mem_trace_mode<='1';
                  trace_continuous <= '1';
                  state <= NextCommand;
                elsif cmdbuffer(2)='0' then
                  -- Set CPU free running
                  monitor_mem_trace_mode<='0';
                  state <= NextCommand;
                  -- Also start capturing CPU history
                  history_record <= '1';
                  history_record_continuous <= '0';
                  history_address <= 0;
                elsif cmdbuffer(2)='l' then
                  -- Set CPU free running
                  monitor_mem_trace_mode<='0';
                  state <= NextCommand;
                  -- Also start capturing CPU history continuously
                  history_record <= '1';
                  history_record_continuous <= '1';
                  history_address <= 0;
                else
                  state <= TraceStep;
                end if;
              elsif cmdbuffer(1) = 'e' or cmdbuffer(1) = 'e' then
                report "Trigger break based on flags" severity note;
                parse_position <= 2;
                if cmdlen=2 then
                  flag_break_enabled <= '0';
                  state <= NextCommand;
                else
                  flag_break_enabled <= '1';
                  parse_hex(ParseFlagBreak);
                end if;
              elsif cmdbuffer(1) = 'b' or cmdbuffer(1) = 'B' then
                report "CPU break command" severity note;
                parse_position <= 2;
                if cmdlen=2 then
                  break_enabled <= '0';
                  state <= NextCommand;
                else
                  report "trying to parse hex" severity note;
                  parse_hex(CPUBreak1);
                end if;
              elsif cmdbuffer(1) = 'z' or cmdbuffer(1) = 'Z' then
                banner_position <= 0;
                if cmdlen=2 then
                  if cpu_state_count /= 0 then
                    state <= CPUStateLog;
                  else
                    state <= NextCommand;
                  end if;
                else
                  parse_hex(CPUHistory);
                end if;
              elsif cmdbuffer(1) = 'l' or cmdbuffer(1) = 'L' then
                report "load memory command" severity note;
                parse_position <= 2;
                report "trying to parse hex" severity note;
                parse_hex(LoadMemory1);
              elsif cmdbuffer(1) = 'd' or cmdbuffer(1) = 'D' then
                report "read memory (CPU context) command" severity note;
                parse_position <= 2;
                report "trying to parse hex" severity note;
                if cmdlen=2 then
                  -- continue dumping from where we left off
                  byte_number <= 0;
                  state <= ShowMemory2;
                else
                  parse_hex(ShowMemoryCPU1);
                end if;
                if cmdbuffer(1)='d' then
                  -- d prints one line
                  line_number <= 31;
                else
                  -- D prints 32 lines
                  line_number <= 0;
                end if;                
              elsif cmdbuffer(1) = 'm' or cmdbuffer(1) = 'M' then
                report "read memory command" severity note;
                parse_position <= 2;
                report "trying to parse hex" severity note;
                if cmdlen=2 then
                  -- continue dumping from where we left off
                  byte_number <= 0;
                  state <= ShowMemory2;
                else
                  parse_hex(ShowMemory1);
                end if;
                if cmdbuffer(1)='m' then
                  -- m prints one line
                  line_number <= 31;
                else
                  -- M prints 32 lines
                  line_number <= 0;
                end if;
              elsif cmdbuffer(1) = 'w' or cmdbuffer(1) = 'W' then
                report "watch memory location" severity note;
                parse_position <= 2;
                report "trying to parse hex" severity note;
                parse_hex(Watch1);
              else
                errorCode <= x"06";
                state <= SyntaxError;
              end if;
            else
              -- On empty line toggle trace flag so that CPU knows it can do one more instruction
              monitor_mem_trace_toggle <= not monitor_mem_trace_toggle_internal;
              monitor_mem_trace_toggle_internal <= not monitor_mem_trace_toggle_internal;

              -- Also start capturing CPU history
              history_record <= '1';
              history_address <= 0;
              
              cmdlen <= 1;
              state <= ShowRegisters;
            end if;
				
          when CPUHistory =>
            history_record <= '0';
            history_address <= to_integer(hex_value(9 downto 0));
            state <= CPUHistory1;
          when CPUHistory1 =>
            history_buffer <= history_rdata;
            state <= ShowRegisters2;
				
          when CPUStateLog =>
            if banner_position /= cpu_state_count then
              print_hex_byte(cpu_state_buf(banner_position)(15 downto 8),CPUStateLog2);
            else
              state <= NextCommand;
            end if;
          when CPUStateLog2 =>
            try_output_char(':',CPUStateLog3);
          when CPUStateLog3 =>
            if banner_position /= cpu_state_count then
              print_hex_byte(cpu_state_buf(banner_position)(7 downto 0),CPUStateLog4);
              banner_position <= banner_position + 1;
            else
              state <= NextCommand;
            end if;
          when CPUStateLog4 =>
            try_output_char(' ',CPUStateLog);
				
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
              monitor_mem_address <= target_address;
              monitor_mem_wdata <= hex_value(7 downto 0);
              target_address <= target_address + 1;
              cpu_transaction(FillMemory5);
            end if;
				
          when Watch1 => monitor_watch <= hex_value(27 downto 0);
                         state <= NextCommand;
								 
          when LoadMemory1 => target_address <= hex_value(27 downto 0);
                             skip_space(LoadMemory2);
          when LoadMemory2 => parse_hex(LoadMemory3);
          when LoadMemory3 =>
            if target_address(15 downto 0) /= hex_value(15 downto 0) then
              -- check for character
              if rx_acknowledge='1' then
                rx_acknowledge <= '0';
              end if;
              if rx_ready = '1' and rx_acknowledge='0' then
                blink <= not blink;
                activity <= blink;
                rx_acknowledge<='1';

                monitor_mem_read <= '0';
                monitor_mem_write <= '1';
                monitor_mem_address <= target_address;
                monitor_mem_wdata <= unsigned(rx_data);

                target_address(15 downto 0) <= target_address(15 downto 0) + 1;
                
                timeout <= 65535;
                cpu_transaction(LoadMemory3);
              end if;
            else
              rx_acknowledge <= '0';
              state <= NextCommand;
            end if;
				
          when SetMemory1 =>
            if cmdbuffer(1) = 'S' then
              target_address <= x"777"&hex_value(15 downto 0);
            else
              target_address <= hex_value(27 downto 0);
            end if;
            skip_space(SetMemory2);
          when SetMemory2 => parse_hex(SetMemory3);
          when SetMemory3 =>
            target_value <= hex_value(7 downto 0);
            parse_position <= parse_position + 1;
            state <= SetMemory4;
          when SetMemory4 =>
            monitor_mem_write <= '1';
            monitor_mem_read <= '0';
            monitor_mem_address <= target_address;
            monitor_mem_wdata <= target_value;
            cpu_transaction(SetMemory8);
          when SetMemory5 => try_output_char('=',SetMemory6);
          when SetMemory6 => print_hex_addr(target_address,SetMemory7);
          when SetMemory7 => try_output_char(' ',SetMemory8);
          when SetMemory8 =>
            target_address <= target_address + 1;
            if parse_position < cmdlen then
              -- Don't print written bytes in an attempt to fix memory set getting
              -- out of sync when fed data at speed.
              state <= SetMemory2;
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
				
          when PrintSpaces =>
            if hex_digits_output<hex_digits_read then
              if tx_ready='1' then
                try_output_char(' ',PrintSpaces);
                hex_digits_output <= hex_digits_output + 1;
              end if;
            else
              state <= success_state;
            end if;
				
          when ParseFlagBreak =>
            flag_break_mask <= hex_value(15 downto 0);
            state <= NextCommand;
				
          when ShowMemoryCPU1 =>
            -- Read memory from CPU's perspective
            target_address <= x"777"&hex_value(15 downto 0);
            byte_number <= 0;
            end_of_command(ShowMemory2);                          
          when ShowMemory1 =>
            target_address <= hex_value(27 downto 0);
            byte_number <= 0;
            end_of_command(ShowMemory2);              
          when ShowMemory2 =>
            if byte_number=16 then
              state <= ShowMemory4;
            else              
              monitor_mem_read <= '1';
              monitor_mem_write <= '0';
              monitor_mem_address <= target_address + to_unsigned(byte_number,28);
              timeout <= 65535;
              cpu_transaction(ShowMemory3);
            end if;
          when ShowMemory3 =>
            if tx_ready='1' then
              membuf(byte_number) <= monitor_mem_byte;
              byte_number <= byte_number +1;
              state <= ShowMemory2;
            end if;
          when ShowMemory4 => try_output_char(' ',ShowMemory5);
          when ShowMemory5 => try_output_char(':',ShowMemory6); byte_number <= 0;
          when ShowMemory6 => print_hex_addr(target_address,ShowMemory7);
          when ShowMemory7 =>
            if byte_number = 16 then
              if line_number = 31 then
                state<=NextCommand;
              else
                if tx_ready='1' then
                  line_number <= line_number + 1;
                  target_address <= target_address + 16;
                  byte_number <= 0;
                  try_output_char(cr,ShowMemory9);
                end if;
              end if;
            else
              try_output_char(' ',ShowMemory8);
            end if;
          when ShowMemory8 =>
            byte_number <= byte_number + 1;
            print_hex_byte(membuf(byte_number),ShowMemory7);
          when ShowMemory9 => try_output_char(lf,ShowMemory2);
			 
          when ShowRegisters =>
            show_register_delay <= 255;
            state <= ShowRegistersDelay;
				
          when ShowRegistersDelay =>
            -- Wait 60 cycles to give instruction time to run (even when loaded
            -- from slow ram), so that when we latch the exposed CPU state it is post-instruction, not pre-
            -- (or mid-) instruction.
            if show_register_delay=0 then
              state <= ShowRegistersRead;
            else
              show_register_delay <= show_register_delay - 1;
            end if;
				
          when ShowRegistersRead =>            
            history_buffer(7 downto 0) <= monitor_p;
            history_buffer(15 downto 8) <= monitor_a;
            history_buffer(23 downto 16) <= monitor_x;
            history_buffer(31 downto 24) <= monitor_y;
            history_buffer(39 downto 32) <= monitor_z;
            history_buffer(55 downto 40) <= monitor_pc;
            history_buffer(71 downto 56) <= unsigned(monitor_cpu_state);
            history_buffer(79 downto 72) <= monitor_waitstates;
            history_buffer(87 downto 80) <= monitor_b;
            history_buffer(104 downto 89) <= monitor_sp;
            history_buffer(112 downto 105)
              <= unsigned(monitor_map_enables_low)
                          & monitor_map_offset_low(11 downto 8);
            history_buffer(120 downto 113) <= monitor_map_offset_low(7 downto 0);
            history_buffer(121) <= monitor_ibytes(1);
            history_buffer(122) <= fastio_read;
            history_buffer(123) <= fastio_write;
            history_buffer(124) <= monitor_proceed;
            history_buffer(125) <= monitor_mem_attention_granted;
            history_buffer(126) <= monitor_request_reflected;
            history_buffer(127) <= monitor_interrupt_inhibit;

            history_buffer(135 downto 128)
              <= unsigned(monitor_map_enables_high)
                          & monitor_map_offset_high(11 downto 8);
            history_buffer(143 downto 136) <= monitor_map_offset_high(7 downto 0);
            history_buffer(151 downto 144) <= monitor_opcode;
            history_buffer(159 downto 152) <= monitor_arg1;
            history_buffer(167 downto 160) <= monitor_arg2;
            history_buffer(175 downto 168) <= monitor_instruction;
            history_buffer(176) <= monitor_ibytes(0);
            
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
            -- PC(15 downto 8)
            print_hex_byte(history_buffer(55 downto 48),ShowRegisters3);
          when ShowRegisters3 =>
            -- PC(7 downto 0)
            print_hex_byte(history_buffer(47 downto 40),ShowRegisters4);
          when ShowRegisters4 => try_output_char(' ',ShowRegisters5);
          when ShowRegisters5 =>
            -- Accumulator
            print_hex_byte(history_buffer(15 downto 8),ShowRegisters6);
          when ShowRegisters6 => try_output_char(' ',ShowRegisters7);
          when ShowRegisters7 =>
            -- X Register
            print_hex_byte(history_buffer(23 downto 16),ShowRegisters8);
          when ShowRegisters8 => try_output_char(' ',ShowRegisters9);
          when ShowRegisters9 =>
            -- Y Register
            print_hex_byte(history_buffer(31 downto 24),ShowRegisters10);
          when ShowRegisters10 => try_output_char(' ',ShowRegisters11);
          when ShowRegisters11 =>
            -- Z register
            print_hex_byte(history_buffer(39 downto 32),ShowRegisters12);
          when ShowRegisters12 => try_output_char(' ',ShowRegisters13);
          when ShowRegisters13 =>
            -- B register
            print_hex_byte(history_buffer(87 downto 80),ShowRegisters14);
          when ShowRegisters14 => try_output_char(' ',ShowRegisters15);
          when ShowRegisters15 =>
            -- SP(15 downto 8)
            print_hex_byte(history_buffer(104 downto 97),ShowRegisters16);
          when ShowRegisters16 =>
            -- SP(7 downto 0)
            print_hex_byte(history_buffer(96 downto 89),ShowRegisters17);
          when ShowRegisters17 => try_output_char(' ',ShowRegisters18);
          when ShowRegisters18 =>
            -- map low enables and map_offset_low(11 downto 8)
            print_hex_byte(history_buffer(112 downto 105),ShowRegisters19);
          when ShowRegisters19 =>
            -- map_offset_low(7 downto 0)
            print_hex_byte(history_buffer(120 downto 113),ShowRegisters20);
          when ShowRegisters20 => try_output_char(' ',ShowRegisters21);
          when ShowRegisters21 =>
            -- map high enables and map_offset_high(11 downto 8)
            print_hex_byte(history_buffer(135 downto 128),ShowRegisters22);
          when ShowRegisters22 =>
            -- map_offset_high(7 downto 0)
            print_hex_byte(history_buffer(143 downto 136),ShowRegisters23);
          when ShowRegisters23 => try_output_char(' ',ShowRegisters24);
          when ShowRegisters24 =>
            -- monitor_opcode
            print_hex_byte(history_buffer(151 downto 144),ShowRegisters25);
          when ShowRegisters25 => try_output_char(' ',ShowRegisters26);
          when ShowRegisters26 =>
            -- montitor_arg1, tested by monitor_ibytes(1)
            if history_buffer(121)='1' then
              print_hex_byte(history_buffer(159 downto 152),ShowRegisters27);
            else
              print_two_spaces(ShowRegisters27);
            end if;
          when ShowRegisters27 => try_output_char(' ',ShowRegisters28);
          when ShowRegisters28 =>
            -- monitor_arg2, only if monitor_ibytes(1) and monitor_ibytes(0) set
            if history_buffer(121)='1' and history_buffer(176)='1' then
              print_hex_byte(history_buffer(167 downto 160),ShowRegisters29);
            else
              print_two_spaces(ShowRegisters29);
            end if;
          when ShowRegisters29 => try_output_char(' ',ShowRegisters30);
          when ShowRegisters30 =>
            -- monitor_p
            print_hex_byte(history_buffer(7 downto 0),ShowRegisters31);
          when ShowRegisters31 => try_output_char(' ',ShowRegisters32);
          when ShowRegisters32 =>
            -- monitor_instruction
            print_hex_byte(history_buffer(175 downto 168),ShowRegisters33);
          when ShowRegisters33 =>
            try_output_char(' ',ShowP1);
          when ShowP1 =>
            if history_buffer(7)='1' then
              try_output_char('N',ShowP2);
            else              
              try_output_char('.',ShowP2);
            end if;
          when ShowP2 =>
            if history_buffer(6)='1' then
              try_output_char('V',ShowP3);
            else              
              try_output_char('.',ShowP3);
            end if;
          when ShowP3 =>
            if history_buffer(5)='1' then
              try_output_char('E',ShowP4);
            else              
              try_output_char('.',ShowP4);
            end if;
          when ShowP4 =>
            if history_buffer(4)='1' then
              try_output_char('B',ShowP5);
            else              
              try_output_char('.',ShowP5);
            end if;
          when ShowP5 =>
            if history_buffer(3)='1' then
              try_output_char('D',ShowP6);
            else              
              try_output_char('.',ShowP6);
            end if;
          when ShowP6 =>
            if history_buffer(2)='1' then
              try_output_char('I',ShowP7);
            else              
              try_output_char('.',ShowP7);
            end if;
          when ShowP7 =>
            if history_buffer(1)='1' then
              try_output_char('Z',ShowP8);
            else              
              try_output_char('.',ShowP8);
            end if;
          when ShowP8 =>
            if history_buffer(0)='1' then
              try_output_char('C',ShowP9);
            else              
              try_output_char('.',ShowP9);
            end if;
          when ShowP9 =>
            -- monitor_interrupt_inhibit
            if history_buffer(127)='1' then
              try_output_char('M',ShowP10);
            else              
              try_output_char('.',ShowP10);
            end if;
          when ShowP10 =>
            try_output_char(' ',ShowP11);
          when ShowP11 =>
            -- monitor_request_reflected
            if history_buffer(126)='1' then
              try_output_char('R',ShowP12);
            else
              try_output_char('.',ShowP12);
            end if;
          when ShowP12 =>
            -- monitor_mem_attention_granted
            if history_buffer(125)='1' then
              try_output_char('G',ShowP13a);
            else
              try_output_char('.',ShowP13a);
            end if;
          when ShowP13a =>
            -- monitor_proceed
            if history_buffer(124)='1' then
              try_output_char('P',ShowP13);
            else
              try_output_char('.',ShowP13);
            end if;
          when ShowP13 =>
            try_output_char(' ',ShowP14);
          when ShowP14 =>
            -- upper half of monitor_cpu_state
            print_hex_byte(history_buffer(71 downto 64),ShowP15);
          when ShowP15 =>
            try_output_char(' ',ShowP16);
          when ShowP16 =>
            -- fastio_write
            if history_buffer(123)='1' then
              try_output_char('W',ShowP17);
            else
              -- fastio_read
              if history_buffer(122)='1' then
                try_output_char('R',ShowP17);
              else
                try_output_char('-',ShowP17);
              end if;
            end if;
          when ShowP17 =>
            -- monitor_waitstates
            print_hex_byte(history_buffer(79 downto 72),ShowP18);
          when ShowP18 =>
            try_output_char(' ',ShowP19);            
          when ShowP19 =>
            if monitor_hypervisor_mode='1' then
              try_output_char('H',ShowP20);
            else
              try_output_char('-',ShowP20);
            end if;
          when ShowP20 =>
            if monitor_ddr_ram_banking='1' then
              try_output_char('B',NextCommand);
            else
              try_output_char('-',NextCommand);
            end if;
				
          when EraseCharacter => try_output_char(' ',EraseCharacter1);
          when EraseCharacter1 => try_output_char(bs,AcceptingInput);
			 
          when SyntaxError =>
            banner_position <= 1; state <= PrintError;
				
          when RequestTimeoutError =>
            banner_position <= 1; state <= PrintRequestTimeoutError;
				
          when ReplyTimeoutError =>
            banner_position <= 1; state <= PrintReplyTimeoutError;
				
          when SetPC1 =>
            monitor_mem_address(15 downto 0) <= hex_value(15 downto 0);
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
                state <= RequestTimeoutError;
              end if;
              timeout <= timeout - 1;
            end if;
          when CPUTransaction2 =>
            if monitor_mem_attention_granted='1' then
              -- Attention being granted implies that request has been fulfilled.
              monitor_mem_byte <= monitor_mem_rdata;
              monitor_mem_attention_request <= '0';
              timeout <= 65535;
              state <= CPUTransaction3;
            else
              if timeout=0 then
                state <= RequestTimeoutError;
              end if;
              timeout <= timeout - 1;
            end if;
          when CPUTransaction3 =>
            if monitor_mem_attention_granted = '0' then
              state <= post_transaction_state;
            else
              if timeout=0 then
                state <= ReplyTimeoutError;
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
