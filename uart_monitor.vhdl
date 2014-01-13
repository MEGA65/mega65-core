library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;

entity uart_monitor is
  port (
    reset : in std_logic;
    dotclock : in std_logic;
    tx : out std_logic;
    rx : in  std_logic;
    activity : out std_logic);
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

-- Buffer to hold entered command
  signal cmdbuffer : String(1 to 64);
  signal cmdlen : integer := 0;
  signal redraw_position : integer;

  constant crlf : string := cr & lf;
  constant bannerMessage : String :=
    crlf &
    crlf &
    "--------------------------------" & crlf &
    "65GS Serial Monitor" & crlf &
    "---------------------------------" & crlf &
    "Type ? for help." & crlf;
  signal banner_position : integer := 1;
  constant helpMessage : String :=
    "?                       - Display this help" & crlf &
    "r                       - Print processor state." & crlf &
    "s <address> <value>     - Set memory." & crlf &
    "m <address>             - Display contents of memory" & crlf;

  type monitor_state is (Reseting,
                         PrintBanner,PrintPrompt,PrintHelp,
                         AcceptingInput,
                         RedrawInputBuffer,RedrawInputBuffer2,RedrawInputBuffer3,
                         EnterPressed,
                         EraseInputBuffer,EraseInputBuffer2);
  signal state : monitor_state := Reseting;

begin

  uart_tx0: uart_tx_ctrl
    port map (
      send    => tx_trigger,
      clk     => dotclock,
      data    => tx_data,
      ready   => tx_ready,
      uart_tx => tx);

  uart_rx0: uart_rx 
    Port map ( clk => dotclock,
               UART_RX => rx,
               data => rx_data,
               data_ready => rx_ready,
               data_acknowledge => rx_acknowledge);

  -- purpose: test uart output
  testclock: process (dotclock)
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
      if char >=' ' and char < del then
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
        case char is
          when dc2 =>
            -- Redraw line
            redraw_position <= 1;
            state <= RedrawInputBuffer;
          when nak =>
            -- Erase line
            state <= EraseInputBuffer;            
          when bs =>
            if cmdlen>1 then
              -- Delete character from end of line
              tx_data <= to_std_logic_vector(del);
              tx_trigger <= '1';                    
              cmdlen <= cmdlen - 1;
            end if;
          when del =>
            if cmdlen>1 then
              -- Delete character from end of line
              tx_data <= to_std_logic_vector(del);
              tx_trigger <= '1';                    
              cmdlen <= cmdlen - 1;
            end if;
          when cr => state <= EnterPressed;
          when lf => state <= EnterPressed;
          when others =>
            tx_data <= to_std_logic_vector(bel);
            tx_trigger <= '1';                    
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

  begin  -- process testclock
    if reset='0' then
      state <= Reseting;      
    elsif rising_edge(dotclock) then
      -- Update counter and clear outputs
      counter <= counter + 1;
      tx_counter <= std_logic(counter(27));
      rx_acknowledge <= '0';
      tx_trigger<='0';

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
                state <= PrintPrompt;
                cmdlen <= 1;
              end if;
            end if;
          when PrintPrompt => try_output_char(cr,AcceptingInput);
          when AcceptingInput =>
            -- If there is a character waiting
            if rx_ready = '1' and rx_acknowledge='0' then
              blink <= not blink;
              activity <= blink;
              rx_acknowledge<='1';
              character_received(to_character(rx_data));
            end if;
          when RedrawInputBuffer => try_output_char(cr,RedrawInputBuffer2);
          when RedrawInputBuffer2 => try_output_char('.',RedrawInputBuffer3);
          when RedrawInputBuffer3 =>
            if redraw_position<cmdlen then
              try_output_char(cmdbuffer(redraw_position),RedrawInputBuffer3);
              redraw_position <= redraw_position + 1;
            else
              state <= AcceptingInput;
            end if;
          when EraseInputBuffer => redraw_position<=1; try_output_char(cr,EraseInputBuffer2);
          when EraseInputBuffer2 =>
            if redraw_position<cmdlen then
              try_output_char(' ',EraseInputBuffer2);
              redraw_position <= redraw_position + 1;
            else
              cmdlen <= 1;
              try_output_char(cr,PrintPrompt);
            end if;
          when EnterPressed =>
            if cmdlen>1 and
              (cmdbuffer(1) = 'h' or cmdbuffer(1) = 'H' or cmdbuffer(1) = '?') then
              banner_position <= 1;
              state <= PrintHelp;
            end if;
            cmdlen <= 1;
            state <= PrintPrompt;
          when others => null;
        end case;
      end if;
    end if;
  end process testclock;
  
end behavioural;
