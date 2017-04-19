----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    23:38:46 03/23/2017 
-- Design Name: 
-- Module Name:    terminalemulator - Behavioral 
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
use ieee.std_logic_unsigned.all;
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity terminalemulator is
  Port (
    clk : in  STD_LOGIC; --200Mhz?
    uart_clk : in std_logic; --48MHz
  --reset : in  STD_LOGIC;
    uart_in : in  STD_LOGIC;
    topofframe_out : out std_logic_vector(11 downto 0); 
  --clkl_out : IN STD_LOGIC;
    wel_out : out STD_LOGIC_VECTOR(0 DOWNTO 0);
    addrl_out : out STD_LOGIC_VECTOR(11 DOWNTO 0);
    dinl_out : out STD_LOGIC_VECTOR(7 DOWNTO 0)
  );
end terminalemulator;

architecture Behavioral of terminalemulator is

component uart_rx is
  Port (
    clk : in std_logic; 
    UART_RX : in std_logic;
    data : out std_logic_vector(7 downto 0);
    data_ready : out std_logic;
    data_acknowledge : in std_logic
  );
end component; 

type terminal_emulator_state is (clearAck,
                                 incChar,
                                 writeChar, writeChar2,
                                 waitforinput,
                                 processCommand,
                                 newLine, newLine2,
                                 newFrame,
                                 clearLine,
                                 linefeed, linefeed2,
                                 backspace,
											writeCursor,writeCursor2,
											clearCursor,clearCursor2);--,nextchar, carRet, linefeed);--clearFrame
signal state : terminal_emulator_state := waitforinput;
signal next_state : terminal_emulator_state;

constant CharMemStart : std_logic_vector(11 downto 0):=x"302";
constant CharMemEnd : std_logic_vector(11 downto 0):=x"F81";

signal rx_data : std_logic_vector(7 downto 0);
signal rx_ready : std_logic;
signal rx_acknowledge : std_logic; 
signal dataToWrite : std_logic_vector(7 downto 0);
signal charCursor : std_logic_vector(11 downto 0):=CharMemStart; --0 to 3199 char positions
signal charX : std_logic_vector(7 downto 0):=x"00";--50 --execute on first run
signal lastLineStart : std_logic_vector(11 downto 0):=CharMemStart; --0 to 3199 char positions
signal clearLineStart : std_logic_vector(11 downto 0):=CharMemStart;
signal clearLineEnd : std_logic_vector(11 downto 0):=CharMemStart+80;
signal topofframe : std_logic_vector(11 downto 0):=CharMemStart;--(others=>'0'); --position of topofframe in memory. Ring buffer
--has the characters hit the bottom of the frame for the first time? If so always scroll text up on next line.
signal hasHitEoF : std_logic:='0'; 
begin

uart_rx0: uart_rx 
  Port map (
    clk => uart_clk,	            
    UART_RX => uart_in,
    data => rx_data,
    data_ready => rx_ready,
    data_acknowledge => rx_acknowledge);

topofframe_out <= topOfFrame;--b"000000000000";--topOfFrame;
					
  uart_receive: process (clk)
  begin
    if rising_edge(uart_clk) then	 	 
	   case state is 						  
		  when waitforinput => 
		    if rx_ready = '1' and rx_acknowledge='0' then
		        rx_acknowledge<='1';
            if rx_data < x"20" and rx_data /=x"0A" then --ASCII < x"20" is a command											              				     			  
				  state<=clearCursor;
				  next_state<=processCommand;
				elsif rx_data =x"0A" then
				   --(Uart monitor sends CR then LF, so we can check if its on first character)
				   if charX=x"00" then --Don't clear first character. 
					  state<=processCommand;
					else
					  state<=clearCursor; --Clear character (for LF no CR, on Syntax Errors)
				     next_state<=processCommand;
					end if;
				  
			   else 			 
			     state<=writeChar;
				  dataToWrite<=rx_data-32;
            end if;
         --else
           --state<=writeCursor;
           --next_state<=waitforinput;  
		   end if;
		
      --Write cursor by setting bit 7 of the memory location, which will invert output.		
		--Because memory read isn't implmented from this module (yet), we cant put cursor over characters		
      when writeCursor=>
		dinl_out<=b"10000000";
		addrl_out<=charCursor;
		wel_out<=b"1";
		state<=writeCursor2;
		
		when writeCursor2=>		
		wel_out<=b"0";
		state<=next_state;
		
		--Normally cursor would be overwritten by a new character
		--But in the case of: backspace, CR, LF, etc. character doesnt get written at cursor
		--Call before moving charCursor
		
		when clearCursor=>
		  dinl_out<=b"00000000";
		  addrl_out<=charCursor;
		  wel_out<=b"1";		
	     state<=clearCursor2;
		  
      when clearCursor2=>
		  wel_out<=b"0";
        state<=next_state;
		  
	   when writeChar =>
		  addrl_out<=charCursor; --latch address
        dinl_out<=dataToWrite; --latch output data		  
		  wel_out<=b"1"; --enable write
		  state<=WriteChar2;
			
		when writeChar2 =>	
		  rx_acknowledge<='0'; --clear acknowledged 
		  wel_out<=b"0";
	     state<=incChar;

        
		  --Increase char position by 1
        when incChar =>
         --Check boundaries		  
		    if charX >= x"4F" then --if its at the end of a line
		      charX<=(others=>'0'); 
 		    if charCursor >= CharMemEnd then--x"C7F" then --if its at the end of a frame
		      state<=newFrame;			  
			   charCursor<=CharMemStart;--(others=>'0');
			   lastLineStart<=CharMemStart;--others=>'0');
            hasHitEoF<='1';
		  	 else 
			   charCursor<=charCursor+1;				
		      state<=newLine;	
			end if;
			
		   else 		  		  
		    charCursor<=charCursor+1;
		    charX<=charX+1; 
			 --state<=clearAck; 
          state<=writeCursor;
          next_state<=clearAck;  			 
		  end if;
				 
		when newFrame=>
		  charCursor<=CharMemStart;--(others=>'0');
		  lastLineStart<=CharMemStart;--(others=>'0');
		  charX<=(others=>'0');
		  hasHitEoF<='1';
  		  clearLineStart<=CharMemStart;--(others=>'0');
        clearLineEnd<=CharMemStart+80;
		  state<=ClearLine;
        		  
      when newLine=>		
		  lastLineStart<=charCursor;				
		  clearLineStart<=charCursor;
        clearLineEnd<=charCursor+80;		  
		  --Write new cursor whenever charCursor moves
		  state<=newLine2;         		  
		when newLine2=>  
		  next_state<=clearAck;
		  state<=clearLine;
		  
		when processCommand =>        	
		  if rx_data = x"0D" then --CR carriage return		  
          charCursor<=lastLineStart; --go back to start of line?
			 charX<=(others=>'0');
			 state<=clearAck;	
		  elsif rx_data =x"0A" then --LF line feed		    			 			
		    charCursor<=charCursor+80;
		    lastLineStart<=lastLineStart+80;
		    state<=linefeed;
		  elsif rx_data =x"08" then --BS
          charCursor<=charCursor-1;
          charX<=charX-1;			
			 dataToWrite<=x"00";
			 wel_out<=b"1";			 
			 --state<=backspace;
			 state<=writeCursor;
			 next_state<=clearAck;
			 
		  else 
		    state<=clearAck;
		  end if;
		 
       when backspace=> --writes blank char
		  addrl_out<=charCursor; --latch address
        dinl_out<=dataToWrite; --latch output data		  		  
        state<=clearAck;  		 
		  
       --Clear acknowledge, ready for next Char
       when clearAck=>
		 wel_out<=b"0";
       rx_acknowledge<='0';	 
		 state<=waitforinput;

		  
		when linefeed=>
		--Fix boundaries      >3969
        if charCursor>CharMemEnd then--b"110001111111" then
		    charCursor<=charCursor-3200;
          hasHitEoF<='1';  			 
		  end if;          
		                  -- >3120 (the last line start)
		  if lastLineStart>CharMemEnd-79 then --b"110000110000" then
		    lastLineStart<=CharMemStart;
			 hasHitEoF<='1';
		  end if;
		  
		  state<=linefeed2;
		  
		when linefeed2=>
		  clearLineStart<=lastLineStart;
		  clearLineEnd<=lastLineStart+80;
		  state<=clearLine;		  		  		  
		  
		 when clearLine=>	      		 
		 if hasHitEoF = '1' then
		 --If the top of frame was 3120 (last line), next top of frame is first line
		    if topOfFrame >= CharMemEnd-79 then --b"110000110000" then 
		      topOfFrame<=CharMemStart;
		    else --otherwise increase
		      topOfFrame<=topOfFrame+80;
		    end if;
		  end if;
		 
		   wel_out<=b"1";		
		   addrl_out<=clearLineStart;
         dinl_out<=(others=>'0');
		   clearLineStart<=clearLineStart+1;		
			
			if (clearLineStart=clearLineEnd) then			
			  wel_out<=b"0";
			  state<=clearAck;         
			end if;				
		end case;  
    end if;	 
  end process;
end Behavioral;
