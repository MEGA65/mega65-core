----------------------------------------------------------------------------------
-- company: 
-- Engineer: 
-- 
-- Create Date:    13:20:25 03/17/2017 
-- Design Name: 
-- Module Name:    ps2_to_uart - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity ps2_to_uart is
  Port (
    clk : in  STD_LOGIC; --50mhz
    bit_rate_divisor : in unsigned(13 downto 0);
    reset : in  STD_LOGIC;
    enabled : in std_logic;
    scan_code: in std_logic_vector (12 downto 0);
    mm_displayMode_out : out unsigned(1 downto 0); 
    tx_ps2 : out STD_LOGIC;
    display_shift_out : out std_logic_vector(2 downto 0);
    shift_ready_out : out std_logic;
    matrix_trap_out : out std_logic;
    shift_ack_in : in std_logic	 
    );
end ps2_to_uart;

--
--  signal display_shift : std_logic_vector(1 downto 0):=b"00"; --direction to shift. 1=up, 2=right, 3=down, 4=left
--  signal shift_ack : std_logic; --Has the compositor shifted the display already.
--  signal shift_ready : std_logic;


architecture Behavioral of ps2_to_uart is

  -- Determines which display scale mode to use for matrix mode
  -- 0=1:1 (640x320), 1=2:1 (1280x640), 2=3:1 (1920x960) (Fullscreen)
  -- CMD: Alt-1     , Alt-2           , Alt-3
  signal mm_displayMode : unsigned(1 downto 0):=b"10";
  
  -- Pressing a cursor key will shift the matrix mode display by 8px
  -- Only on modes 0 and 1
  signal display_shift : std_logic_vector(2 downto 0):=b"000"; --direction to shift. 1=up, 2=right, 3=down, 4=left
  signal shift_ack : std_logic; --Has the compositor shifted the display already.
  signal shift_ready : std_logic;
  -- If a cursor key is pressed 
  
  
  --UART Signals
  signal tx_data : unsigned(7 downto 0);
  signal tx_ready : std_logic; 
  signal tx_trigger : std_logic := '0';
  
  -- States in FSM
  type ps2_to_uart_state is (WaitForKey,Enter,KeyPress, Output);
  signal state : ps2_to_uart_state := WaitForKey;
  signal next_state : ps2_to_uart_state;
  signal timer : unsigned(27 downto 0) := (others =>'0');
  
  --Keyboard Timers
  constant timer200ms : unsigned(23 downto 0):=b"110100100111110010011001";
  constant timer30ms : unsigned(20 downto 0):=b"111011111100100010111";
  signal repeatCounter1 : unsigned(23 downto 0):=timer200ms;
  signal repeatCounter2 : unsigned(20 downto 0):=timer30ms;  
  --Keyboard signals
  signal caps : std_logic := '0';
  signal previousScanCode : std_logic_vector (12 downto 0);
  signal firstPress : std_logic := '0';
  signal inputKey : std_logic := '0' ;
  signal firstRepeatDone : std_logic := '0';
  signal altcode : std_logic := '0';
  signal alt_down : std_logic := '0';
begin

  uart_tx1: entity work.UART_TX_CTRL
    port map (
      send    => tx_trigger,
      bit_tmr_max => bit_rate_divisor,
      clk     => clk,
      data    => tx_data,
      ready   => tx_ready,
      uart_tx => tx_ps2
      );
  
  uart_test: process (clk)
    variable the_scan_code : unsigned(8 downto 0);
  begin
    if rising_edge(CLK) then
      if enabled='1' then --Input only run when matrix mode is enabled	     
        case state is 
          when WaitForKey => 
            tx_trigger <='0';
            
          when KeyPress =>
            state<=Output;
            next_state<=WaitForKey;
            
          when Enter =>
            tx_data <= x"0D"; --cr only
            next_state<=WaitForKey;
            state<=Output;
            
          when Output =>
            if tx_ready='1' then
              tx_trigger <= '1';
              state <= next_state;
            end if;
        end case;		
      end if;
      
      --If the scan code is Left Shift
      if scan_code(7 downto 0)=x"12" or scan_code(7 downto 0)=x"59" then
	if scan_code(12)='0' then --and make code
	  caps<='1';
	else --break code
	  caps<='0';
        end if;
      end if; 
      
      
      
      --CursorKeys
      -- E0 75 up
      -- E0 6B left
      -- E0 72 down
      -- E0 74 right
      -- ScanCode(8) is extended code
      
--Check alt-1/2/3 combos
      -- ALT: x"11" b"00010001"
      -- Don't care whats in bits 11-8
      --If the previous key was alt, and is still held. 
      --To Fix: previousScanCode does not update on key up, checking previousScanCode(12) is pointless. 

      --  else --Otherwise normal key press

      -- When keyboard has no keys pressed its last code is a break code
      -- When a key is pressed scan_code(12) will be '1' i.e. make code
      -- Input first keystroke
      -- Wait ~250ms 
      -- firstRepeatDone will be '1'
      -- When first repeat is done second counter will count down ~50ms ish before inputting keys again  
      -- If breakcode or new code is sent, reset everything. 
      -- If the previous scan code wasnt ALT, do normal keys. (this is so 1/2/3 arent input when switching modes)
      if scan_code(12)='0' and firstPress = '0' then --and (previousScanCode(12)&previousScanCode(7 downto 0) /= b"000010001")  then              
        inputKey<='1'; --input key when first instance of key is pressed    	
        firstPress<='1';
        previousScanCode <= scan_code;
      elsif scan_code(12)='0' and firstPress='1' then -- if it has been held down    
        if repeatCounter1=x"000000" then --timer is zero
          if firstRepeatDone='0' then 
            firstRepeatDone<='1';        
          end if;	  
        else	 
          repeatCounter1<=repeatCounter1-1; 	
        end if;		   
      end if;
      
      if firstRepeatDone='1' then
        if repeatCounter2=b"000000000000000000000" then --timers on zero reset      
          repeatCounter2<=timer30ms; --reload timer
          inputKey<='1'; --input character
	else --otherwise decrement the timer
          repeatCounter2<=repeatCounter2-1;    
        end if;  
      end if;   
      
      -- Check for ALT key combinations
      the_scan_code(8) := scan_code(12);
      the_scan_code(7 downto 0) := unsigned(scan_code(7 downto 0));
      case the_scan_code is --make sure its a MAKE code.
        when '0'&x"11" => alt_down <= '1';
        when '1'&x"11" => alt_down <= '0';
        when '0'&x"16" =>
          if (alt_down='1') then
            mm_displayMode <= b"00";
          end if;
        when '0'&x"1E" => --2
          if (alt_down='1') then
            mm_displayMode <= b"01";
          end if;
        when '0'&x"26" => --3
          if (alt_down='1') then
            mm_displayMode <= b"10";
          end if;
        when '0'&x"0D"=> --Alt-tab, activates matrix mode. These are probably temporary commands
          if (alt_down='1') then
            matrix_trap_out<='1'; --setup trap.
          end if;
        when '1'&x"0d" =>
          matrix_trap_out<='0';	 --reset trap
        when others => --Alt anything
      --Do Nothing
      --altcode<='0'; --Why is this here. 
      end case;
      
      --when any key is released or a new key is down, reset repeat timers  
      if scan_code(12)='1' or scan_code/=previousScanCode then 
        repeatCounter1<=timer200ms;
        repeatCounter2<=timer30ms;
        firstRepeatDone<='0';    
        inputKey<='0';  --stop any input;	
        firstPress<='0';
      end if;	 
      
      -- If a key is lifted, no longer an alt-code (keys need to be down at same time)
      -- EXCEPT if the lifted key is 1,2,3 or TAB, so that we can use the various functions
      -- without having to release and re-press TAB.
      if scan_code(12)='1' then
        if (scan_code(7 downto 0) /= x"0D")
          and (scan_code(7 downto 0) /= x"16")
          and (scan_code(7 downto 0) /= x"1E")
          and (scan_code(7 downto 0) /= x"26") then
          altcode <= '0';
        end if;
      end if;	 
      
      if shift_ack = '1' then
        shift_ready<='0';
      end if;

      --Can possibly rewrite this? using "case caps&scan_code(7 downto 0) is" and have it mux the 9-bit code
      --rather than have check for caps each time
      
      --if inputKey='1' and state/=Output and state/=KeyPress then
      if inputKey='1' then
        inputKey<='0'; --Disable input character.
        -- Remember ALT status 
        if scan_code(7 downto 0) /= x"11" then
          if (scan_code(7 downto 0) /= x"16")
            and (scan_code(7 downto 0) /= x"1E")
            and (scan_code(7 downto 0) /= x"26") then
            altcode <= '0';
          end if;
        else
          altcode <= '1';
        end if;
        case scan_code(7 downto 0) is	     	 
          --up / numpad 8 --Don't bother checking for extended code, as numpad isn't implemented
          when x"75" =>
            display_shift<=b"001";
            shift_ready<='1';
          --left / numpad 4
          when x"6B" => 
            display_shift<=b"100";
            shift_ready<='1';
          --down / numpad 2
          when x"72" => 
            display_shift<=b"011";
            shift_ready<='1';
          --right / numpad 6
          when x"74" => 
            display_shift<=b"010";
            shift_ready<='1';
            
          --when x"1C" => tx_data <= 
          -- 3, W, A, 4, Z, S, E, left-SHIFT
          when x"26" =>
            if altcode = '0' then			 
              if caps='0' then		  --3/#
                tx_data <= x"33";
              else
                tx_data<=x"23"; 
              end if;		  
              state<= KeyPress;
            end if; 
            
          when x"1D" => --W
            if caps='0' then
              tx_data <= x"77";
            else tx_data<=x"57";
            end if;
            state<= KeyPress;
            
          when x"1C" => --A
            if caps='0' then
              tx_data <= x"61";
            else tx_data <= x"41";
            end if; 
            state<= KeyPress;
            
          when x"25" => --4/$
            if caps='0' then
              tx_data <= x"34";
            else tx_data<=x"24";
            end if; 
            state<= KeyPress;
            
          when x"1A" => --Z
            if caps='0' then
              tx_data <= x"7A"; 
            else tx_data <= x"5A";
            end if;
            state<= KeyPress;
            
          when x"1B" => --S
            if caps='0' then
              tx_data <= x"73";
            else tx_data <= x"53";
            end if;
            state<= KeyPress;
            
          when x"24" => --E
            if caps='0' then
              tx_data <= x"65";
            else tx_data <= x"45";
            end if;
            state<= KeyPress;

            
          -- 5, R, D, 6, C, F, T, X	
          when x"2E" => 
            if caps='0' then
              tx_data <= x"35";
            else
              tx_data<=x"25";
            end if;
            state<= KeyPress; --5
            
          when x"2D" => 
            if caps='0' then
              tx_data <= x"72";
            else tx_data <= x"52";
            end if;				
            state<= KeyPress;--R
            
          when x"23" => 
            if caps='0' then
              tx_data <= x"64";
            else tx_data <= x"44";
            end if;
            state<= KeyPress;--D
            
          when x"36" => 
            if caps='0' then
              tx_data <= x"36";
            else tx_data<=x"5E";
            end if;
            state<= KeyPress;--6
            
          when x"21" => 
            if caps='0' then
              tx_data <= x"63";
            else tx_data <= x"43";
            end if;
            state<= KeyPress;--C
            
          when x"2B" =>
            if caps='0' then
              tx_data <= x"66";
            else tx_data <= x"46";
            end if;
            state<= KeyPress;--F 
            
          when x"2C" =>
            if caps='0' then
              tx_data <= x"74";
            else tx_data <= x"54";
            end if;
            state<= KeyPress;--T 
            
          when x"22" =>
            if caps='0' then
              tx_data <= x"78";
            else tx_data <= x"58";
            end if;
            state<= KeyPress;--X 	

          -- 7, Y, G, 8, B, H, U, V
          when x"3D" =>
            if caps='0' then
              tx_data <= x"37";
            else tx_data <= x"26";
            end if;
            state<= KeyPress; --7/& 
            
          when x"35" => 
            if caps='0' then
              tx_data <= x"79";
            else tx_data <= x"59";
            end if;
            state<= KeyPress;--Y 
            
          when x"34" =>
            if caps='0' then
              tx_data <= x"67";
            else tx_data <= x"47";
            end if;
            state<= KeyPress;--G
            
          when x"3E" => 
            if caps='0' then
              tx_data <= x"38";
            else
              tx_data<=x"2A"; --8/*
            end if;		  
            state<= KeyPress;		
            
          when x"32" => 
            if caps='0' then
              tx_data <= x"62";
            else tx_data <= x"42";
            end if;
            state<= KeyPress;--B
            
          when x"33" => 
            if caps='0' then
              tx_data <= x"68";
            else tx_data <= x"48";
            end if;
            state<= KeyPress;--H
            
          when x"3C" => 
            if caps='0' then
              tx_data <= x"75";
            else tx_data <= x"55";
            end if;
            state<= KeyPress;--U
            
          when x"2A" =>
            if caps='0' then
              tx_data <= x"76";
            else tx_data <= x"56";
            end if;
            state<= KeyPress;--V	
            
          -- 9, I, J, 0, M, K, O, N		
          when x"46" => 
            if caps='0' then
              tx_data <= x"39";
            else
              tx_data<=x"28";
            end if;
            state<= KeyPress;--9/(
            
          when x"43" =>
            if caps='0' then
              tx_data <= x"69";
            else tx_data <= x"49";
            end if;
            state<= KeyPress;--I
            
          when x"3B" =>
            if caps='0' then
              tx_data <= x"6A";
            else tx_data <= x"4A";
            end if;
            state<= KeyPress;--J
            
          when x"45" =>	
            if caps='0' then		  
              tx_data <= x"30";
            else 
              tx_data<=x"29";
            end if; 
            state<= KeyPress;	--0/)
            
          when x"3A" =>		
            if caps='0' then
              tx_data <= x"6D";
            else tx_data <= x"4D";
            end if;
            state<= KeyPress;--M
            
          when x"42" =>
            if caps='0' then
              tx_data <= x"6B";
            else tx_data <= x"4B";
            end if;
            state<= KeyPress;--K
            
          when x"44" =>
            if caps='0' then
              tx_data <= x"6F";
            else tx_data <= x"4F";
            end if;
            state<= KeyPress;	--O
            
          when x"31" =>
            if caps='0' then
              tx_data <= x"6E";
            else tx_data <= x"4E";
            end if;
            state<= KeyPress;	--N
            
          -- +, P, L, -, ., :, @, COMMA
          when x"4E" =>
            if caps='0' then
              tx_data <= x"2D";
            else tx_data <= x"5F";
            end if;
            state<= KeyPress;	---_
            
          when x"4D" =>
            if caps='0' then
              tx_data <= x"70";
            else tx_data <= x"50";
            end if;
            state<= KeyPress;	--P
            
          when x"4B" =>
            if caps='0' then
              tx_data <= x"6C";
            else tx_data <= x"4C";
            end if;
            state<= KeyPress;	--L
            
          when x"55" =>
            if caps='0' then
              tx_data <= x"3D"; 
            else
              tx_data <= x"2B";
            end if; 
            state<= KeyPress; --=/+ 
            
          when x"49" =>
            if caps='0' then
              tx_data <= x"2E";
            else
              tx_data<=x"3E";
            end if;
            state<= KeyPress;--./>
            
          when x"4C" =>
            if caps='0' then
              tx_data <= x"3B";
            else
              tx_data <= x"3A";
            end if;
            state<= KeyPress;--;/:
            
          when x"54" =>
            tx_data <= x"5B";
            state<= KeyPress;--[
            
          when x"41" =>
            if caps='0' then
              tx_data <= x"2C";
            else 
              tx_data<=x"3C";
            end if;
            state<= KeyPress;--,/<
            
          when x"16" =>
            if altcode = '0' then		
              if caps='0' then		  		 		  
                tx_data <= x"31";
              else
                tx_data <= x"21";		    
              end if;
              state<= KeyPress;	--1/!		 
            end if;
            
            
          when x"1E" =>
            if altcode = '0' then			 
              if caps='0' then		  		
                tx_data <= x"32";
              else 
                tx_data <= x"40";  		  
              end if; 
              state<= KeyPress;	--2/@		 
            end if;
            
            
          when x"15" =>
            if caps='0' then		  		
              tx_data <= x"71";
            else 
              tx_data <= x"51";  		  
            end if; 
            state<= KeyPress;	--Q
            
          when x"5A" =>
            tx_data <= x"2C";
            state<= Enter;	--ENTER
            
          when x"66"=> --del
            tx_data <= x"08";
            state<= KeyPress;			  
            
          when x"29"=> --space
            tx_data <= x"20";
            state<= KeyPress;		  
            
          when others=> state<=WaitForKey; 
        end case;
      end if;
    end if;
  end process uart_test;

  mm_displayMode_out <= mm_displayMode;
  shift_ready_out <= shift_ready;
  shift_ack <= shift_ack_in; 
  display_shift_out <= display_shift;
end Behavioral;


