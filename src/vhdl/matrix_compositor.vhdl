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
    monitor_char_in : in unsigned(7 downto 0);
    monitor_char_valid : in std_logic;
    terminal_emulator_ready : out std_logic;
    pixel_x_640 : in integer;
    ycounter_in : in unsigned(11 downto 0);
    pixel_x_640_out : out integer;
    ycounter_out : out unsigned(11 downto 0);
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
  signal startx : unsigned(13 downto 0):= to_unsigned(160,14);
  signal endx  : unsigned(13 downto 0):=to_unsigned(2068,14);
  signal starty : unsigned(11 downto 0):=x"07C"; --x07C d124
  signal endy : unsigned(11 downto 0):=x"43C"; --x43C d1084



--Mode0 Frame
--640x320
  constant mode0_startx  : unsigned(13 downto 0):= to_unsigned(160,14);
  constant mode0_starty : unsigned(11 downto 0):=x"07C";--x"1B8";--x"07C"; --x07C 124
  constant mode0_endx  : unsigned(13 downto 0):=mode0_startx+647;--x"313";--x"507";--x"313"; --x814 d780  -1 +8
  constant mode0_endy : unsigned(11 downto 0):=x"1BB";--x"2F8";--x"1BB"; --124+320 = 444, x1BC -1 
  constant mode0_garbage_end_offset : unsigned(13 downto 0):=to_unsigned(8,14);
--Mode1 Frame
--1280x640
  constant mode1_startx  : unsigned(13 downto 0):=to_unsigned(160,14);
  constant mode1_starty : unsigned(11 downto 0):=x"07C";--x"118";--x"07C"; --07C 124 
  constant mode1_endx  : unsigned(13 downto 0):=mode1_startx+1295;--x"590";--x"64F";--x"590"; --x581 d1409 -1
  constant mode1_endy : unsigned(11 downto 0):=mode1_starty+640;--x"2FB";--x"398";--x"2FB"; --x2FC d764 -1
  constant mode1_garbage_end_offset : unsigned(13 downto 0):=to_unsigned(16,14);

  signal xOffset : unsigned(13 downto 0):= (others => '0');
  signal yOffset : unsigned(11 downto 0):=x"000";
  signal shift_ack : std_logic:='0';
  signal garbage_end : unsigned(13 downto 0):=to_unsigned(0,14);
  signal garbage_end_offset : unsigned(13 downto 0):=to_unsigned(0,14);

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

  signal last_pixel_x_640 : integer;
  
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
      char_in => monitor_char_in,
      char_in_valid => monitor_char_valid,
      terminal_emulator_ready => terminal_emulator_ready,

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

      pixel_x_640_out <= pixel_x_640;
      ycounter_out <= ycounter_in;
      
      -- We synchronise to start of line, as the end of line may change with
      -- different video modes.
      if pixel_x_640 = 0 and  ycounter_in >= starty and ycounter_in < endy then
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
      if pixel_x_640 = 1 and ycounter_in < endy then
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
                if endx < 4096 then
                  xoffset<=xoffset+8;
                end if; 
              when b"011" => --down
                if endy < 1200 then
                  yoffset<=yoffset+8;
                end if;
              when b"100" => --left
                if xoffset > 7 then
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
            when others =>
              end_of_char <= mode1_end_of_char; 
              startx <= mode1_startx+xoffset;
              starty <= mode1_starty+yoffset;
              endx <= mode1_endx+xoffset;
              endy <= mode1_endy+yoffset;
              garbage_end_offset <= mode1_garbage_end_offset;
          end case;		
        end if;
      end if;

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

      if pixel_x_640 >=startx and pixel_x_640 <= endx  and ycounter_in >= starty and ycounter_in <= endy then		   

--====================
-- Generate Outputs:
--====================

        --Green Outline on modes 0 and 1 Only			
        if pixel_x_640>=garbage_end then
          if mm_displayMode/=b"10" and (pixel_x_640 = garbage_end or pixel_x_640 = endx or ycounter_in = starty or ycounter_in = endy) then			 
            redOutput_all <= b"00"&vgared_in(7 downto 2);
            greenOutput_all <= b"111"&vgagreen_in(4 downto 0);
            blueOutput_all <= b"00"&vgablue_in(7 downto 2);
          else			 
            --Shift background down 3, instead of 2 when displaying text. 
            --Less variation in text colour when there's high frequency in the background
            --Seems to shift ALL output by 1px? 
            if data_buffer(7) = '1' then 
              redOutput_all <=   b"00"&vgared_in(7 downto 2);
              greenOutput_all <= data_buffer(7)&data_buffer(7)&data_buffer(7)&vgagreen_in(7 downto 3);
              blueOutput_all <=  b"00"&vgablue_in(7 downto 2);			 			      			 
            else
              redOutput_all <= b"00"&vgared_in(7 downto 2);
              greenOutput_all <= data_buffer(7)&data_buffer(7) &vgagreen_in(7 downto 2);
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
        
        --If it hasnt just loaded new data,
        if pixel_x_640 /= last_pixel_x_640 then
          last_pixel_x_640 <= pixel_x_640;

          case eightCounter is		            
            when b"00001" =>
              -- Read the character number from terminal emulator screen memory
              readAddress_rom<=charCount; 		  
            when b"00011" =>
              charAddr<=dataOutRead_rom;
              -- Invert read character if required
              invert<=dataOutRead_rom(7); --bit 7 is whether to invert or not. 
            when b"00101" =>
              -- Request character data for the current character
              readAddress_rom<=(b"00" & charAddr(6 downto 0) & b"000")+charline;
            when b"00111" =>
              -- Advance to next character
              if charCount=CharMemEnd then
                charCount<=CharMemStart;
              else --otherwise increase
                charCount<=charCount+1;					 
              end if;				  				
            when others =>
          --do nothing;
          end case;

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
