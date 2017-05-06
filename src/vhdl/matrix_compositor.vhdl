library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity matrix_compositor is
  Port (
    display_shift_in : in std_logic_vector(2 downto 0);
    shift_ready_in : in std_logic;
    shift_ack_out : out std_logic;
    mm_displayMode_in : in unsigned(1 downto 0);
    uart_in : in std_logic;
    xcounter_in : in unsigned(11 downto 0);
    ycounter_in : in unsigned(11 downto 0);
    clk : in std_logic; --48Mhz
    pixelclock : in std_logic; --200Mhz
    matrix_mode_enable : in  STD_LOGIC;
    vgared_in : in  unsigned (7 downto 0);
    vgagreen_in : in  unsigned (7 downto 0);
    vgablue_in : in  unsigned (7 downto 0);
    vgared_out : out  unsigned (7 downto 0);
    vgagreen_out : out  unsigned (7 downto 0);
    vgablue_out : out  unsigned (7 downto 0)
    );
end matrix_compositor;

architecture Behavioral of matrix_compositor is

--Location of start of character memory
  constant CharMemStart : unsigned(11 downto 0):=x"302";
--Location of end of character memory
  constant CharMemEnd : unsigned(11 downto 0):=x"F81";


--Character Map Memory Interface
  signal writeEnable : std_logic_vector(0 downto 0);
  signal writeAddress : unsigned (11 downto 0);
  signal dataInWrite : unsigned(7 downto 0);
  signal charAddr : unsigned (7 downto 0);
  signal readAddress_rom : unsigned(11 downto 0):=CharMemStart;
  signal dataOutRead_rom : unsigned (7 downto 0);


-- Frame boundaries 
  signal startx : unsigned(11 downto 0):=x"079"; --x078 d120  should actually be 121
  signal endx  : unsigned(11 downto 0):=x"814"; --x814 d2068
  signal starty : unsigned(11 downto 0):=x"07C"; --x07C d124
  signal endy : unsigned(11 downto 0):=x"43C"; --x43C d1084



--Mode0 Frame
--640x320
  constant mode0_startx  : unsigned(11 downto 0):=x"096";--x"280";--x"08C"; -- 120+20 = 140 x08C
  constant mode0_starty : unsigned(11 downto 0):=x"07C";--x"1B8";--x"07C"; --x07C 124
  constant mode0_endx  : unsigned(11 downto 0):=mode0_startx+647;--x"313";--x"507";--x"313"; --x814 d780  -1 +8
  constant mode0_endy : unsigned(11 downto 0):=x"1BB";--x"2F8";--x"1BB"; --124+320 = 444, x1BC -1 
  constant mode0_garbage_end_offset : unsigned(11 downto 0):=x"008";  --8
--Mode1 Frame
--1280x640
  constant mode1_startx  : unsigned(11 downto 0):=x"096";--x"081";--x"140";--x"081"; -- 120+9 = 129 x081
  constant mode1_starty : unsigned(11 downto 0):=x"07C";--x"118";--x"07C"; --07C 124 
  constant mode1_endx  : unsigned(11 downto 0):=mode1_startx+1295;--x"590";--x"64F";--x"590"; --x581 d1409 -1
  constant mode1_endy : unsigned(11 downto 0):=mode1_starty+640;--x"2FB";--x"398";--x"2FB"; --x2FC d764 -1
  constant mode1_garbage_end_offset : unsigned(11 downto 0):=x"00F"; 

--Mode2 Frame
--1920x960
  constant mode2_startx  : unsigned(11 downto 0):=x"079"; --120+1 = 121 x079
  constant mode2_starty : unsigned(11 downto 0):=x"07C"; --x814 d2068 
  constant mode2_endx  : unsigned(11 downto 0):=x"813"; --x814 d2068 -1
  constant mode2_endy : unsigned(11 downto 0):=x"43B"; --x43C d1084 -1
  constant mode2_garbage_end_offset : unsigned(11 downto 0):=x"01D"; 

  signal xOffset : unsigned(11 downto 0):=x"000";
  signal yOffset : unsigned(11 downto 0):=x"000";
  signal shift_ack : std_logic:='0';
  signal garbage_end : unsigned(11 downto 0):=x"000"; --blank output between starting, and actually displaying.
  signal garbage_end_offset : unsigned(11 downto 0):=x"000"; -- can make this smaller?

--Character signals
  signal charCount : unsigned(11 downto 0):=CharMemStart;
  signal charline : unsigned(3 downto 0); 
  signal eightCounter : unsigned(4 downto 0):=(others=>'0'); 
  signal bufferCounter : unsigned(1 downto 0):=(others=>'0'); 
  signal invert : std_logic;

--Outputs
  signal greenOutput : std_logic:='0';
  signal redOutput : std_logic:='0';
  signal blueOutput : std_logic:='0';

--8-bit Outputs
  signal greenOutput_all : unsigned(7 downto 0);
  signal redOutput_all : unsigned(7 downto 0);
  signal blueOutput_all : unsigned(7 downto 0);

  signal data_buffer : unsigned(7 downto 0):=x"00"; 
  signal lineStartAddr : unsigned(11 downto 0):=CharMemStart;
  signal lineCounter : unsigned(2 downto 0):=b"000";
  signal topOfFrame : unsigned(11 downto 0):=CharMemStart;
  signal doneEndOfFrame : std_logic:='0';
  signal doneEndOfFrame1 : std_logic:='0';
  signal doneEndOfFrame2 : std_logic:='0';


--Display Mode signals
  signal mm_displayMode : unsigned(1 downto 0):=b"10";
  signal end_of_char : unsigned(4 downto 0):=b"11000";
  constant mode0_end_of_char : unsigned(4 downto 0):=b"01000"; --8
  constant mode1_end_of_char : unsigned(4 downto 0):=b"10000"; --16
  constant mode2_end_of_char : unsigned(4 downto 0):=b"11000"; --24

begin

  uart_charrom1 : entity work.uart_charrom
    port map(
      clkl => pixelclock,
      clkr => pixelclock,
      wel => writeEnable,
      addrl => writeAddress,
      addrr => readAddress_rom,
      dinl => dataInWrite,
      doutr => dataOutRead_rom
      );

  terminalemulator0 : entity work.terminalemulator
    port map(
      clk => pixelclock,
      uart_clk => clk,
      uart_in => uart_in,
      topofframe_out => topOfFrame,
      wel_out => writeEnable,
      addrl_out => writeAddress,
      dinl_out => dataInWrite
      );

  vgared_out   <= vgared_in   when matrix_mode_enable='0' else redOutput_all;
  vgagreen_out <= vgagreen_in when matrix_mode_enable='0' else greenOutput_all;
  vgablue_out  <= vgablue_in  when matrix_mode_enable='0' else blueOutput_all;

  ram_test : process(pixelclock)
  begin

    if rising_edge(pixelclock) then
      -- We synchronise to start of line, as the end of line may change with
      -- different video modes.
      if xcounter_in = 0 and  ycounter_in >= starty and ycounter_in < endy then
        if lineCounter=mm_displayMode then	-- 0 (1 px per line), 1 (2 px per line), 2 (3px per line) 
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
      if xcounter_in = 1 and ycounter_in < endy then
        charCount<=lineStartAddr;
        eightCounter<=(others=>'0');
        bufferCounter<=(others=>'0');
      end if;
      
      --End of Frame, reset counters	
      if ycounter_in = 0 then 
        if doneEndOfFrame='0' then
          mm_displayMode <= mm_displayMode_in; --Only change display mode at end of frame		
          doneEndOfFrame<='1';		
          lineCounter<=(others=>'0'); 
          charline<=(others=>'0'); 
          charCount<=topOfFrame;
          lineStartAddr<=topOfFrame;
          eightCounter<=(others=>'0');		
          
          if shift_ack = '0' and shift_ready_in = '1' then
            case display_shift_in is
              when b"001" =>  --up
                if starty > 25 then --i.e. if its at 17, dont decrease anymore
                  yoffset<=yoffset-8;
                end if;
              when b"010" => --right 
                if endx < x"7F8" then
                  xoffset<=xoffset+8;
                end if; 
              when b"011" => --down
                if endy < 1200 then
                  yoffset<=yoffset+8;
                end if;
              when b"100" => --left
                if garbage_end > 150 then
                  xoffset<=xoffset-8;
                end if;
              when others =>
            end case;		  		  
            shift_ack <='1'; 
          else
            shift_ack <='0'; --reset ack
          end if; 
          
          --Load display mode settings
          --Calculates boundaries from mode constants and offset
          --Seems inefficient, is there a better way?
          --set a garbage offset here, to avoid doing another mux later.
          
          case mm_displayMode_in is		
            when b"00" =>
              end_of_char <= mode0_end_of_char; 
              startx <= mode0_startx+xoffset;
              starty <= mode0_starty+yoffset;
              endx <= mode0_endx+xoffset;
              endy <= mode0_endy+yoffset;
              garbage_end_offset <= mode0_garbage_end_offset;
            when b"01" =>
              end_of_char <= mode1_end_of_char; 
              startx <= mode1_startx+xoffset;
              starty <= mode1_starty+yoffset;
              endx <= mode1_endx+xoffset;
              endy <= mode1_endy+yoffset;
              garbage_end_offset <= mode1_garbage_end_offset;
            when b"10" =>
              end_of_char <= mode2_end_of_char; 
              startx <= mode2_startx;
              starty <= mode2_starty;
              endx <= mode2_endx;
              endy <= mode2_endy;
              garbage_end_offset <= mode2_garbage_end_offset;
            when others => 
              end_of_char <= mode2_end_of_char; 
              startx <= mode2_startx;
              starty <= mode2_starty;
              endx <= mode2_endx;
              endy <= mode2_endy;
              garbage_end_offset <= mode2_garbage_end_offset;
          end case;		
        end if;
      end if;

--Check boundaries

--When a boundary is hit, it will 'rubber band' because the startx/y are already set for the next frame with the offset in the previous step
--Fixed this.

--Issue when matrix mode is switched between mode0 and mode1 at a boundary close to location 0. (right side and 
--causes startx to wrap, which will make it stuck between >x"7F8" and < mode2_startx+8
--This completely breaks matrix mode. 

--This is caused by large offset of x/y between mode0/1 constants.
--Maybe don't have them centered to start, keep the the same/similar

--For piece of mind add an addition condition which slightly less than the wrap around of the 12 bit address
--say b4000 / xFA0

--if ycounter_in = b"10010110010" then 
--    if doneEndOfFrame2='0' then
--	   doneEndOfFrame2<='1';
--	   --If the start of x is less than it ought to be. undo the offset change, and set startx to known good value		
--		--Are these additions really bad for space?
--		--Only in Mode0/1
--		
--		
--		--DO CHECKS WHEN SETTING OFFSETS, but offset the checks to.
--		--Results in no rubber banding, and no out of bounds at all. rt
--		
--		
--		if mm_displayMode < b"10" then
--
---- Move the window position back		
--		
----	     if startx<=(mode2_startx+8) or > slightly_less_than_the_wrap_around_of_12-bit_address then
----		    xoffset<=xoffset+8;
----		    --startx<=mode2_startx;
----        els
--		  if endx>x"7F8" then
--          xoffset<=xoffset-8;	
--        end if; 
--		
----		  if starty < 50 or > slightly_less_than_the_wrap_around_of_12-bit_address then 
----		    yoffset<=yoffset+8;
----		    --starty<=(others=>'0'); 
----		  els
--		  
--		  if endy > x"4B0" then --Should be slightly less than 4B0--This should work, idk why it isnt. 		  
--		    yoffset<=yoffset-8;		  
--		  end if;
--		  
--		end if;
--	 end if;
--	 	
--end if;


--Calc garbage_end
      if ycounter_in = 0 then 
        if doneEndOfFrame1='0' then
          garbage_end<= startx + garbage_end_offset;
        end if;
      end if;
      
--Main draw loop. 1 state, 1 tick for each output pixel

--Tick 1: Updates the actual green output, gets the next character address ready
--xcounter/ycounter checks can change the position the output is on the screen
--actual output is slightly offset from these. 
--if xcounter_in = 0 then
--  greenOutput<='1';
--end if;

      if xcounter_in >=startx and xcounter_in <= endx  and ycounter_in >= starty and ycounter_in <= endy then		   

--====================
-- Generate Outputs:
--====================

        --Green Outline on modes 0 and 1 Only			
        if xcounter_in>=garbage_end then
          if mm_displayMode/=b"10" and (xcounter_in = garbage_end or xcounter_in = endx or ycounter_in = starty or ycounter_in = endy) then			 
            redOutput_all <= b"00"&vgared_in(7 downto 2);
            greenOutput_all <= b"111"&vgagreen_in(4 downto 0);
            blueOutput_all <= b"00"&vgablue_in(7 downto 2);
          else			 
            --Shift background down 3, instead of 2 when displaying text. 
            --Less variation in text colour when there's high frequency in the background
            --Seems to shift ALL output by 1px? 
            if data_buffer(7) = '1' then 
              redOutput_all <=   b"00"&vgared_in(7 downto 2);
              greenOutput_all <= data_buffer(7)&data_buffer(7)&data_buffer(7)&vgagreen_in(4 downto 0);
              blueOutput_all <=  b"00"&vgablue_in(7 downto 2);			 			      			 
            else
              redOutput_all <= b"00"&vgared_in(7 downto 2);
              greenOutput_all <= data_buffer(7)&data_buffer(7) &vgagreen_in(5 downto 0);
              blueOutput_all <= b"00"&vgablue_in(7 downto 2);			      			 
            end if;
          end if;
          
        else  --If its in garbage display background. 
          if mm_displayMode=b"10" then
            redOutput_all <= b"00"&vgared_in(7 downto 2);
            greenOutput_all <= b"00"&vgagreen_in(7 downto 2);
            blueOutput_all <= b"00"&vgablue_in(7 downto 2);
          else 
            redOutput_all <= vgared_in;
            greenOutput_all <= vgagreen_in;
            blueOutput_all <= vgablue_in;
          end if;		    		
        end if;
        
--======================
--Timing and memory
--======================
        
        -- We've got 8 clocks to:		  
        -- Load read address for next screen Memory
        -- Save the output into CharAddr 
        -- Load the address of the character in charrom
        -- Increment charCount
        -- Save new data into buffer			 			 			 
        -- Case for first ~8 counts of eightCounter
        -- End of character count dependent on display mode
        
        case eightCounter is		            
          when b"00001" =>
            readAddress_rom<=charCount; 		  
          when b"00011" =>
            charAddr<=dataOutRead_rom; 
            invert<=dataOutRead_rom(7); --bit 7 is whether to invert or not. 
          when b"00101" =>
            readAddress_rom<=(b"00" & charAddr(6 downto 0) & b"000")+charline;
          when b"00111" =>
            if charCount=CharMemEnd then
              charCount<=CharMemStart;
            else --otherwise increase
              charCount<=charCount+1;					 
            end if;				  				
          when others =>
        --do nothing;
        end case;

        --If it hasnt just loaded new data, 
        if eightCounter/=end_of_char then
          eightCounter<=eightCounter+1; --increment counter		    			 
          if bufferCounter=mm_displayMode then			 
            data_buffer<=data_buffer(6 downto 0)&'0';				
            bufferCounter<=b"00";
          else 
            bufferCounter<=bufferCounter+1;
          end if;
        elsif eightCounter=end_of_char then
          --clear end of frame flags anywhere before end of frame
          doneEndOfFrame<='0'; 
          doneEndOfFrame1<='0';
          doneEndOfFrame2<='0'; 
          eightCounter<=b"00001"; --Reset counter
          if invert='1' then --invert flag, negate data. 
            data_buffer<= not dataOutRead_rom; -- grab new data 	
          else 
            data_buffer<= dataOutRead_rom; -- grab new data 	
          end if;
        end if; 	
      else 
	--If its out of visible area, display background
        if ycounter_in=0 then
          lineCounter<=(others=>'0'); 
          charline<=(others=>'0'); 
          charCount<=topOfFrame;
          lineStartAddr<=topOfFrame;
          eightCounter<=(others=>'0');	
        end if;
        
        if mm_displayMode=b"10" then
          redOutput_all <= b"00"&vgared_in(7 downto 2);
          greenOutput_all <= b"00"&vgagreen_in(7 downto 2);
          blueOutput_all <= b"00"&vgablue_in(7 downto 2);
        else 
          redOutput_all <= vgared_in;
          greenOutput_all <= vgagreen_in;
          blueOutput_all <= vgablue_in;
        end if;		
      end if;  
      
    end if; --end if for rising edge

  end process;

  shift_ack_out <= shift_ack;

end Behavioral;
