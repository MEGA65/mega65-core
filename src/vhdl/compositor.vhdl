----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    22:39:49 03/18/2017 
-- Design Name: 
-- Module Name:    Compositor - Behavioral 
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

entity compositor is
  Port (
    uart_in : in std_logic;
    xcounter_in : in unsigned(11 downto 0);
    ycounter_in : in unsigned(10 downto 0);
    clk : in std_logic; --48Mhz
    pixelclock : in std_logic; --200Mhz
    matrix_mode_enable : in  STD_LOGIC;
    vgared_in : in  unsigned (3 downto 0);
    vgagreen_in : in  unsigned (3 downto 0);
    vgablue_in : in  unsigned (3 downto 0);
    vgared_out : out  unsigned (3 downto 0);
    vgagreen_out : out  unsigned (3 downto 0);
    vgablue_out : out  unsigned (3 downto 0)
  );
end compositor;

architecture Behavioral of compositor is

  component uart_charrom is
    Port(
      clkl : IN STD_LOGIC;
      wel : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
      addrl : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
      dinl : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      clkr : IN STD_LOGIC;
      addrr : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
      doutr : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
    );
  end component;
  
  component terminalemulator is
    port (
      clk : in  STD_LOGIC;
      uart_clk : in std_logic;
      uart_in : in  STD_LOGIC;
      topofframe_out : out std_logic_vector(11 downto 0); 
      wel_out : out STD_LOGIC_VECTOR(0 DOWNTO 0);
      addrl_out : out STD_LOGIC_VECTOR(11 DOWNTO 0);
      dinl_out : out STD_LOGIC_VECTOR(7 DOWNTO 0)
    );
  end component;

--Location of start of character memory
constant CharMemStart : std_logic_vector(11 downto 0):=x"302";
--Location of end of character memory
constant CharMemEnd : std_logic_vector(11 downto 0):=x"F81";


--Character Map Memory Interface
signal writeEnable : std_logic_vector(0 downto 0);
signal writeAddress : std_logic_vector (11 downto 0);
signal dataInWrite : std_logic_vector(7 downto 0);
signal charAddr : std_logic_vector (7 downto 0);
signal readAddress_rom : std_logic_vector(11 downto 0):=CharMemStart;
signal dataOutRead_rom : std_logic_vector (7 downto 0);


--Character signals
signal charCount : std_logic_vector(11 downto 0):=CharMemStart;
signal charline : std_logic_vector(3 downto 0); --0 to 7, tracks which line of the characters it is outputting. 
signal eightCounter : std_logic_vector(3 downto 0):=(others=>'0'); 

--Outputs
signal greenOutput : std_logic;
signal redOutput : std_logic:='0';

signal data_buffer : std_logic_vector(7 downto 0):=x"00"; 
signal lineStartAddr : std_logic_vector(11 downto 0):=CharMemStart;--incremented every 3 new lines
signal lineCounter : std_logic_vector(2 downto 0):=b"000";
signal topOfFrame : std_logic_vector(11 downto 0):=CharMemStart;
signal doneEndOfFrame : std_logic:='0';

 -- States in FSM
type comp_state is (tick1, tick2, tick3);
signal state : comp_state := tick1;

begin

  uart_charrom1 : uart_charrom
    port map(
      clkl => pixelclock,
      clkr => pixelclock,
      wel => writeEnable,
      addrl => writeAddress,
      addrr => readAddress_rom,
      dinl => dataInWrite,
      doutr => dataOutRead_rom
    );

  terminalemulator0 : terminalemulator
    port map(
      clk => pixelclock,
      uart_clk => clk,
      uart_in => uart_in,
      topofframe_out => topOfFrame,
      wel_out => writeEnable,
      addrl_out => writeAddress,
      dinl_out => dataInWrite
    );

--Outputs
vgared_out   <= vgared_in   when matrix_mode_enable='0' else redOutput   & redOutput   & vgared_in(3 downto 2);
vgagreen_out <= vgagreen_in when matrix_mode_enable='0' else greenOutput & greenOutput & vgagreen_in(3 downto 2);
vgablue_out  <= vgablue_in  when matrix_mode_enable='0' else b"00"                     & vgablue_in(3 downto 2);

ram_test : process(pixelclock)
begin

 if rising_edge(pixelclock) then     
  if xcounter_in = b"100000110100" and  ycounter_in >= 124 and ycounter_in < 1084 then  
	 if lineCounter=b"010" then	 
	   lineCounter<=b"000"; --reset counter
       if charline = b"0111" then --on the ~7th line (0-7)
	      charline<=b"0000"; --reset
			 --Boundary check
			 if lineStartAddr=CharMemEnd-79 then 
			   lineStartAddr<=CharMemStart;
			 else 
			   lineStartAddr<=lineStartAddr+80;--calculate next linestart
			 end if;          
	   else --otherwise
		    charline<=charline+1; --increment line
	   end if;			
	 else --otherwise on every line        
	     lineCounter<=lineCounter+1; --increment 3 line counter
	 end if;		 
 end if;
  
 --Next Tick --Fixes a weird double line issue
 if xcounter_in = b"100000110101" and ycounter_in < 1084 then
   charCount<=lineStartAddr;
	eightCounter<=(others=>'0');
 end if;
  
   --End of Frame, reset counters
  if ycounter_in = b"10010110000" then 
    if doneEndOfFrame='0' then
      doneEndOfFrame<='1';
      lineCounter<=(others=>'0'); 
      charline<=(others=>'0'); 
      charCount<=topOfFrame;
      lineStartAddr<=topOfFrame;
      eightCounter<=(others=>'0');		
    end if;
  end if;
  

--Main draw loop. 3 states 1 tick for each output pixel

--Tick 1: Updates the actual green output, gets the next character address ready
--xcounter/ycounter checks can change the position the output is on the screen
--actual output is slightly offset from these. 

  if xcounter_in >=120 and xcounter_in < b"100000010100"  and ycounter_in >= 124 and ycounter_in < 1084 then
    case state is 
	    when tick1 => 
		 if xcounter_in < "000010010101" then --get rid of a bit of garbage before the frame 			
           redOutput <='0';
		   greenOutput<='0';
		 else
		   redOutput <='0';
		   greenOutput<=data_buffer(7); 
		 end if;


        --Get Correct value into chaAddr before eightCounter reaches 8
		  if eightCounter=b"0011" then		  
			readAddress_rom<=charCount; 		  
		  elsif eightCounter=b"0100" then		  
		   charAddr<=dataOutRead_rom; 
		  else 
           readAddress_rom<=(b"0"&charAddr&b"000")+charline;		  
		  end if;
		  
	     state<=tick2; 
		 
--Tick 2, every 8 ticks (i.e. every ~24px increment character and load new character data, increment char
		when tick2 => --1,0
		doneEndOfFrame<='0'; --clear End of frame done anywhere in next frame
  		  if eightCounter=b"1000" then		
		    --Check boundary			 
			 --If its at the last character, wrap around to 0 instead of increasing
		    if charCount=CharMemEnd then
			    charCount<=CharMemStart;
			 else --otherwise increase
			    charCount<=charCount+1; --increment charCount everytime we grab new data. 
			 end if; 
			   readAddress_rom<=(b"0"&charAddr&b"000")+charline; --Char*8 to get address, add the char line to get full address of data
			   eightCounter<=b"0001"; 
		  else
		    eightCounter<=eightCounter+1; --increment counter		    
   	  end if;   		  		 
		  
		  
--Tick 3 left shifts the data in the buffer, or loads new data into buffer
       state<=tick3;		  		  
		when tick3=>  --2,0
		--Every 24 Pixel Clocks ...	
        if eightCounter=b"0001" then 
		  	data_buffer<=dataOutRead_rom; -- grab new data 	
        else--if it hasnt just refreshed the buffer, then left shift buffer.		  
 		   data_buffer<=data_buffer(6 downto 0)&'0';			 
		  end if;		
	  
		  state<=tick1;		  
     end case;
 
  else --If its out of visible area	      
    state<=tick1;
	greenOutput<='0';
	redOutput<='0'; 
  end if;  
end if;

end process;


end Behavioral;
