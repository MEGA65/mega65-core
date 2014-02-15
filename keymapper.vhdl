library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;

entity keymapper is
  
  port (
    pixelclk : in std_logic;

    -- PS2 keyboard interface
    ps2clock  : in  std_logic;
    ps2data   : in  std_logic;
    -- CIA ports
    porta_in  : in  std_logic_vector(7 downto 0);
    porta_out : out std_logic_vector(7 downto 0);
    portb_out : out std_logic_vector(7 downto 0)
    );

end entity keymapper;

architecture behavioural of keymapper is

  type ps2_state is (Idle,StartBit,Bit0,Bit1,Bit2,Bit3,Bit4,Bit5,Bit6,Bit7,
                     ParityBit,StopBit);
  signal ps2state : ps2_state := Idle;

  signal scan_code : unsigned(7 downto 0) := x"FF";
  signal parity : std_logic := '0';

  -- PS2 clock rate is as low as 10KHz.  Allow double that for a timeout
  -- 192MHz/5KHz = 192000/5 = 38400 cycles
  constant ps2timeout : integer := 38400;
  signal ps2timer : integer range 0 to ps2timeout := 0;

  signal ps2clock_samples : std_logic_vector(7 downto 0) := (others => '1');
  signal ps2clock_debounced : std_logic := '0';

  signal ps2data_samples : std_logic_vector(7 downto 0) := (others => '1');
  signal ps2data_debounced : std_logic := '0';

  signal ps2clock_prev : std_logic := '0';

  signal recent_scan_code_list_index : unsigned(7 downto 0) := x"01";

  signal extended : std_logic := '0';
  signal break : std_logic := '0';

  signal matrix : std_logic_vector(63 downto 0) := (others =>'1');
  
begin  -- behavioural

-- purpose: read from ps2 keyboard interface
  keyread: process (pixelclk, ps2data,ps2clock)
    variable full_scan_code : std_logic_vector(11 downto 0);
    variable portb_value : std_logic_vector(7 downto 0);
  begin  -- process keyread
    if rising_edge(pixelclk) then
      -------------------------------------------------------------------------
      -- Generate timer for keyscan timeout
      -------------------------------------------------------------------------
      ps2timer <= ps2timer +1;
      if ps2timer >= ps2timeout then
        ps2timer <= 0;
        ps2state <= Idle;
      end if;

      ps2clock_samples <= ps2clock_samples(6 downto 0) & ps2clock;
      if ps2clock_samples = "11111111" then
        ps2clock_debounced <= '1';
      end if;
      if ps2clock_samples = "00000000" then
        ps2clock_debounced <= '0';
      end if;

      ps2data_samples <= ps2data_samples(6 downto 0) & ps2data;
      if ps2data_samples = "11111111" then
        ps2data_debounced <= '1';
      end if;
      if ps2data_samples = "00000000" then
        ps2data_debounced <= '0';
      end if;
      
      ps2clock_prev <= ps2clock_debounced;
      if (ps2clock_debounced = '0' and ps2clock_prev = '1') then
        ps2timer <= 0;
        case ps2state is
          when Idle => ps2state <= StartBit; scan_code <= x"FF"; parity <= '0';
          when StartBit => ps2state <= Bit0; scan_code(0) <= ps2data_debounced;
                           parity <= parity xor ps2data_debounced;
          when Bit0 => ps2state <= Bit1; scan_code(1) <= ps2data_debounced;
                       parity <= parity xor ps2data_debounced;
          when Bit1 => ps2state <= Bit2; scan_code(2) <= ps2data_debounced;
                       parity <= parity xor ps2data_debounced;
          when Bit2 => ps2state <= Bit3; scan_code(3) <= ps2data_debounced;
                       parity <= parity xor ps2data_debounced;
          when Bit3 => ps2state <= Bit4; scan_code(4) <= ps2data_debounced;
                       parity <= parity xor ps2data_debounced;
          when Bit4 => ps2state <= Bit5; scan_code(5) <= ps2data_debounced;
                       parity <= parity xor ps2data_debounced;
          when Bit5 => ps2state <= Bit6; scan_code(6) <= ps2data_debounced;
                       parity <= parity xor ps2data_debounced;
          when Bit6 => ps2state <= Bit7; scan_code(7) <= ps2data_debounced;
                       parity <= parity xor ps2data_debounced;
          when Bit7 => ps2state <= parityBit;
                       -- if parity = ps2data then 
                       -- Valid PS2 symbol

                       -- XXX Make a little FSM to set bit 8 on E0 xx sequences
                       -- so that we can have a 9-bit number to look up.
                       -- XXX also work out when a key goes down versus up by F0
                       -- byte.
                       if scan_code = x"F0"  then
                         -- break code
                         break <= '1';
                       elsif scan_code = x"E0" then
                         extended <= '1';
                       else
                         full_scan_code := "000" & extended & std_logic_vector(scan_code);
                         break <= '0';
                         extended <= '0';
                         
                         -- keyboard scancodes for the more normal keys from a keyboard I have here
                         -- (will replace these with the keyrah obtained ones)
                         --                                      $DC01 bits
                         --               0   1   2   3   4   5   6   7
                         -- $DC00 values  
                         -- Bit#0 $FE     1E0 5A  174 83  05  04  03  72
                         -- Bit#1 $FD     26  1D  1C  25  1A  1B  24  12
                         -- Bit#2 $FB     2E  2D  23  36  21  2B  2C  22
                         -- Bit#3 $F7     3D  35  34  3E  32  33  3C  2A
                         -- Bit#4 $EF     46  43  3B  45  3A  42  44  31
                         -- Bit#5 $DF     55  4D  4B  4E  49  54  5B  41
                         -- Bit#6 $BF     52  5D  4C  16C 59  169 75  4A
                         -- Bit#7 $7F     16  6B  14  1E  29  11  15  76
                         -- RESTORE - 0E (`/~ key)

                         case full_scan_code is
                           when x"066" => matrix(0) <= break;
                           when x"05A" => matrix(1) <= break;
                           when x"174" => matrix(2) <= break;
                           when x"083" => matrix(3) <= break;
                           when x"005" => matrix(4) <= break;
                           when x"004" => matrix(5) <= break;
                           when x"003" => matrix(6) <= break;
                           when x"072" => matrix(7) <= break;

                           when x"026" => matrix(8) <= break;
                           when x"01D" => matrix(9) <= break;
                           when x"01C" => matrix(10) <= break;
                           when x"025" => matrix(11) <= break;
                           when x"01A" => matrix(12) <= break;
                           when x"01B" => matrix(13) <= break;
                           when x"024" => matrix(14) <= break;
                           when x"012" => matrix(15) <= break;
                                          
                           when x"02E" => matrix(16) <= break;
                           when x"02D" => matrix(17) <= break;
                           when x"023" => matrix(18) <= break;
                           when x"036" => matrix(19) <= break;
                           when x"021" => matrix(20) <= break;
                           when x"02B" => matrix(21) <= break;
                           when x"02C" => matrix(22) <= break;
                           when x"022" => matrix(23) <= break;

                           when x"03D" => matrix(24) <= break;
                           when x"035" => matrix(25) <= break;
                           when x"034" => matrix(26) <= break;
                           when x"03E" => matrix(27) <= break;
                           when x"032" => matrix(28) <= break;
                           when x"033" => matrix(29) <= break;
                           when x"03C" => matrix(30) <= break;
                           when x"02A" => matrix(31) <= break;
                                          
                           when x"046" => matrix(32) <= break;
                           when x"043" => matrix(33) <= break;
                           when x"03B" => matrix(34) <= break;
                           when x"045" => matrix(35) <= break;
                           when x"03A" => matrix(36) <= break;
                           when x"042" => matrix(37) <= break;
                           when x"044" => matrix(38) <= break;
                           when x"031" => matrix(39) <= break;
                                          
                           when x"055" => matrix(40) <= break;
                           when x"04D" => matrix(41) <= break;
                           when x"04B" => matrix(42) <= break;
                           when x"04E" => matrix(43) <= break;
                           when x"049" => matrix(44) <= break;
                           when x"054" => matrix(45) <= break;
                           when x"05B" => matrix(46) <= break;
                           when x"041" => matrix(47) <= break;
                                          
                           when x"052" => matrix(48) <= break;
                           when x"05D" => matrix(49) <= break;
                           when x"04C" => matrix(50) <= break;
                           when x"16C" => matrix(51) <= break;
                           when x"059" => matrix(52) <= break;
                           when x"169" => matrix(53) <= break;
                           when x"075" => matrix(54) <= break;
                           when x"04A" => matrix(55) <= break;

                           when x"016" => matrix(56) <= break;
                           when x"06B" => matrix(57) <= break;
                           when x"014" => matrix(58) <= break;
                           when x"01E" => matrix(59) <= break;
                           when x"029" => matrix(60) <= break;
                           when x"011" => matrix(61) <= break;
                           when x"015" => matrix(62) <= break;
                           when x"076" => matrix(63) <= break;

                           when others => null;
                         end case;
                         
                       end if;
                       
                       -- The memory of recent scan codes is 255 bytes long, as
                       -- byte 00 is used to indicate the last entry written to
                       -- As events can only arrive at <20KHz a reasonably written
                       -- program can easily ensure it misses no key events,
                       -- especially with a CPU at 64MHz.
                       if recent_scan_code_list_index=x"FF" then
                         recent_scan_code_list_index <= x"01";
                       else
                         recent_scan_code_list_index
                           <= recent_scan_code_list_index + 1;
                       end if;
                       --else
                       --  last_scan_code <= x"FE";
                       --end if;                    
          when ParityBit =>  ps2state <= Idle;  -- was StopBit.  See if
                                                -- changing this fixed munching
                                                -- of first bit of back-to-back bytes.

          when StopBit => ps2state <= Idle;
          when others => ps2state <= Idle;
        end case;        
      end if;      

      -------------------------------------------------------------------------
      -- Update C64 CIA ports
      -------------------------------------------------------------------------
      -- Whenever a PS2 key goes down, clear the appropriate bit(s) in the
      -- matrix.  Whenever the corresponding key goes up, set the appropriate
      -- bit(s) again.  This matrix can then be used to emulate the matrix for
      -- interfacing with the CIAs.

      -- We will use the VICE keyboard mapping so that we are default with the
      -- keyrah2 C64 keyboard to USB adapter.

      -- C64 keyboard matrix can be found at: http://sta.c64.org/cbm64kbdlay.html
      --                                      $DC01 bits
      --                0      1      2      3      4      5      6      7
      -- $DC00 values  
      -- Bit#0 $FE      Delete Return right  F7     F1     F3     F5     down
      -- Bit#1 $FD      3      W      A      4      Z      S      E      left Shift
      -- Bit#2 $FB      5      R      D      6      C      F      T      X
      -- Bit#3 $F7      7      Y      G      8      B      H      U      V
      -- Bit#4 $EF	9      I      J      0      M      K      O      N
      -- Bit#5 $DF	+      P      L      minus  .      :      @      ,
      -- Bit#6 $BF      pound  *      ;	     Home   rshift =	  ^	 slash
      -- Bit#7 $7F	1      _      CTRL   2      Space  C=     Q      Run/Stop
      -- RESTORE - Hardwire to NMI
      
      -- Keyrah v2 claims to use default VICE matrix.  Yet to find that clearly
      -- summarised.  Will probably just exhaustively explore it with my keyrah
      -- when it arrives.

      -- keyboard scancodes for the more normal keys from a keyboard I have here
      -- (will replace these with the keyrah obtained ones)
      --                                      $DC01 bits
      --                0      1      2      3      4      5      6      7
      -- $DC00 values  
      -- Bit#0 $FE      E0 71  5A     E0 74  83     05     04     03     72
      -- Bit#1 $FD      26     1D     1C     25     1A     1B     24     12
      -- Bit#2 $FB      2E     2D     23     36     21     2B     2C     22
      -- Bit#3 $F7      3D     35     34     3E     32     33     3C     2A
      -- Bit#4 $EF	46     43     3B     45     3A     42     44     31
      -- Bit#5 $DF	55     4D     4B     4E     49     54     5B     41
      -- Bit#6 $BF      52     5D     4C     E0 6C  59     E0 69  75	 4A
      -- Bit#7 $7F	16     6B     14     1E     29     11     15     76
      -- RESTORE - 0E (`/~ key)

      -- C64 drives lines low on $DC00, and then reads $DC01
      -- This means that we read from porta_in, to compute values for portb_out
      
      portb_value := x"FF";
      for i in 0 to 7 loop
        if porta_in(i)='0' then
          for j in 0 to 7 loop
            portb_value(j) := portb_value(j) and matrix((i*8)+j);
          end loop;  -- j
        end if;        
      end loop;
      
      -- Keyboard rows and joystick 1
      portb_out <= portb_value;

      -- Keyboard columns and joystick 2
      porta_out <= "11111111";
    end if;
  end process keyread;

end behavioural;
