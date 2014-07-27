library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;

entity keymapper is
  
  port (
    ioclk : in std_logic;

    last_scan_code : out std_logic_vector(12 downto 0);

    nmi : out std_logic := 'Z';
    reset : out std_logic := 'Z';
    
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
  -- 32MHz/5KHz = 32000/5 = 6400 cycles
  -- for 48 mhz : 48mhz/5khz = 48000/5 = 9600
  constant ps2timeout : integer := 9600;
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
  signal row_0 : std_logic_vector(7 downto 0);
  signal row_1 : std_logic_vector(7 downto 0);
  signal row_2 : std_logic_vector(7 downto 0);
  signal row_3 : std_logic_vector(7 downto 0);
  signal row_4 : std_logic_vector(7 downto 0);
  signal row_5 : std_logic_vector(7 downto 0);
  signal row_6 : std_logic_vector(7 downto 0);
  signal row_7 : std_logic_vector(7 downto 0);
  signal joy1 : std_logic_vector(4 downto 0) := (others =>'1');
  signal joy2 : std_logic_vector(4 downto 0) := (others =>'1');

  signal restore_state : std_logic := '1';
  signal restore_event : std_logic := '0';
  signal restore_down_ticks : unsigned(7 downto 0) := (others => '0');  
  signal fiftyhz_counter : unsigned(7 downto 0) := (others => '0');

  signal process_scan_code : std_logic := '0';
  signal process_full_scan_code : std_logic := '0';
  signal full_scan_code : unsigned(11 downto 0);

begin  -- behavioural

-- purpose: read from ps2 keyboard interface
  keyread: process (ioclk, ps2data,ps2clock, porta_in,row_0,joy1)
    variable portb_value : std_logic_vector(7 downto 0);
  begin  -- process keyread
    if rising_edge(ioclk) then
      -------------------------------------------------------------------------
      -- Generate timer for keyscan timeout
      -------------------------------------------------------------------------
      if ps2timer < ps2timeout then
        ps2timer <= ps2timer + 1;
      else
        -- Reset ps2 keyboard timer
        ps2timer <= 0;
        ps2state <= Idle;

        -- Use this 10KHz loop to divide down to 50 hz to work out how many
        -- 50Hz ticks the restore key has been down.  If restore is not down,
        -- then reset the count to zero.

        fiftyhz_counter <= fiftyhz_counter + 1;
        if fiftyhz_counter = 200 then
          fiftyhz_counter <= (others => '0');
          if restore_state='0' then
            restore_down_ticks <= restore_down_ticks + 1;
          else
            -- If restore key is not down, reset count of how long it has been
            -- down, and release NMI and reset lines in case we were asserting
            -- them.
            -- NOTE: This approach means that NMI and RESET will be asserted for
            -- between 1 cycle and 1/50th of a second. There is a possible problem
            -- with reset and NMI being asserted for less than 2 cycles, but
            -- this should be extremely rare.  We have solved this by resetting
            -- fifyhz_counter when the reset key is released.
            restore_down_ticks <= (others => '0');
            nmi <= 'Z';
            reset <= 'Z';
          end if;
        end if;
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

      if process_scan_code='1' then
        process_scan_code <= '0';

        -- XXX Make a little FSM to set bit 8 on E0 xx sequences
        -- so that we can have a 9-bit number to look up.
        -- XXX also work out when a key goes down versus up by F0
        -- byte.
        -- Let the CPU read the most recent scan code for
        -- debugging keyboard layout.
        last_scan_code <= break & "000" & extended & std_logic_vector(scan_code);
        
        if scan_code = x"F0"  then
          -- break code
          break <= '1';
        elsif scan_code = x"E0" then
          extended <= '1';
        else
          process_full_scan_code <= '1';
          full_scan_code <= unsigned("000" & std_logic(extended) & std_logic_vector(scan_code));
        end if;

        if process_full_scan_code='1' then
          break <= '0';
          extended <= '0';
          case full_scan_code is
            when x"17D" =>
              -- Restore key shall do NMI as expected, but also
              -- reset
              restore_state <= break;
              if break='1' then
                if restore_down_ticks < 25 then
                  nmi <= '0';
                  -- But holding it down for >2 seconds does nothing,
                  -- incase someone holds it by mistake.
                elsif restore_down_ticks < 100 then
                  reset <= '0';
                end if;
                -- Make sure that next check for releasing NMI
                -- and reset is not for almost 1/50th of a second.
                fiftyhz_counter <= (others => '0');
              end if;
              
              -- Joysticks
            when x"06c" =>  -- JOY1 LEFT
              joy1(0) <= break;
            when x"069" =>  -- JOY1 RIGHT
              joy1(1) <= break;
            when x"07d" =>  -- JOY1 UP
              joy1(2) <= break;
            when x"07a" =>  -- JOY1 DOWN
              joy1(3) <= break;
            when x"070" =>  -- JOY1 FIRE
              joy1(4) <= break;
            when x"06b" =>  -- JOY2 LEFT
              joy2(0) <= break;
            when x"074" =>  -- JOY2 RIGHT
              joy2(1) <= break;
--                             when x"072" =>  -- JOY2 DOWN
--                                     joy2(3) <= break;
            when x"075" =>  -- JOY2 UP
              joy2(2) <= break;
            when x"073" =>  -- JOY2 FIRE
              joy2(4) <= break;
              
            -- DELETE, RETURN, RIGHT, F7, F1, F3, F5, down
            when x"066" => matrix(0) <= break;
            when x"05A" => matrix(1) <= break;
            when x"174" => matrix(2) <= break;
            when x"083" => matrix(3) <= break;
            when x"005" => matrix(4) <= break;
            when x"004" => matrix(5) <= break;
            when x"003" => matrix(6) <= break;
            when x"072" => matrix(7) <= break;
                           joy2(3) <= break;  -- keyrah
                                              -- duplicate scan
                                              -- code for down
                                              -- key and joy2 down?
                           
            -- 3, W, A, 4, Z, S, E, left-SHIFT
            when x"026" => matrix(8) <= break;
            when x"01D" => matrix(9) <= break;
            when x"01C" => matrix(10) <= break;
            when x"025" => matrix(11) <= break;
            when x"01A" => matrix(12) <= break;
            when x"01B" => matrix(13) <= break;
            when x"024" => matrix(14) <= break;
            when x"012" => matrix(15) <= break;
                           
            -- 5, R, D, 6, C, F, T, X
            when x"02E" => matrix(16) <= break;
            when x"02D" => matrix(17) <= break;
            when x"023" => matrix(18) <= break;
            when x"036" => matrix(19) <= break;
            when x"021" => matrix(20) <= break;
            when x"02B" => matrix(21) <= break;
            when x"02C" => matrix(22) <= break;
            when x"022" => matrix(23) <= break;

            -- 7, Y, G, 8, B, H, U, V
            when x"03D" => matrix(24) <= break;
            when x"035" => matrix(25) <= break;
            when x"034" => matrix(26) <= break;
            when x"03E" => matrix(27) <= break;
            when x"032" => matrix(28) <= break;
            when x"033" => matrix(29) <= break;
            when x"03C" => matrix(30) <= break;
            when x"02A" => matrix(31) <= break;
                           
            -- 9, I, J, 0, M, K, O, N
            when x"046" => matrix(32) <= break;
            when x"043" => matrix(33) <= break;
            when x"03B" => matrix(34) <= break;
            when x"045" => matrix(35) <= break;
            when x"03A" => matrix(36) <= break;
            when x"042" => matrix(37) <= break;
            when x"044" => matrix(38) <= break;
            when x"031" => matrix(39) <= break;
                           
            -- +, P, L, -, ., :, @, COMMA
            when x"04E" => matrix(40) <= break;
            when x"04D" => matrix(41) <= break;
            when x"04B" => matrix(42) <= break;
            when x"055" => matrix(43) <= break;
            when x"049" => matrix(44) <= break;
            when x"04C" => matrix(45) <= break;
            when x"054" => matrix(46) <= break;
            when x"041" => matrix(47) <= break;
                           
            -- POUND, *, ;, HOME, right SHIFT, =, UP-ARROW, /
            when x"170" => matrix(48) <= break;
            when x"05B" => matrix(49) <= break;
            when x"052" => matrix(50) <= break;
            when x"16C" => matrix(51) <= break;
            when x"059" => matrix(52) <= break;
            when x"05D" => matrix(53) <= break;
            when x"171" => matrix(54) <= break;
            when x"04A" => matrix(55) <= break;

            -- 1, LEFT-ARROW, CTRL, 2, SPACE, C=, Q, RUN/STOP
            when x"016" => matrix(56) <= break;
            when x"00E" => matrix(57) <= break;
            when x"00D" => matrix(58) <= break;
            when x"01E" => matrix(59) <= break;
            when x"029" => matrix(60) <= break;
            when x"014" => matrix(61) <= break;
            when x"015" => matrix(62) <= break;
            when x"076" => matrix(63) <= break;
                                          
            when others => null;
          end case;          
        end if;
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
                       process_scan_code <= '1';
          when ParityBit =>  ps2state <= Idle;  -- was StopBit.  See if
                                                -- changing this fixed munching
                                                -- of first bit of back-to-back bytes.
          when StopBit => ps2state <= Idle;
          when others => ps2state <= Idle;
        end case;        
      end if;      
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

      if porta_in(0)='0' then row_0 <= matrix(7 downto 0); else row_0 <= x"FF"; end if;
      if porta_in(1)='0' then row_1 <= matrix(15 downto 8); else row_1 <= x"FF"; end if;
      if porta_in(2)='0' then row_2 <= matrix(23 downto 16); else row_2 <= x"FF"; end if;
      if porta_in(3)='0' then row_3 <= matrix(31 downto 24); else row_3 <= x"FF"; end if;
      if porta_in(4)='0' then row_4 <= matrix(39 downto 32); else row_4 <= x"FF"; end if;
      if porta_in(5)='0' then row_5 <= matrix(47 downto 40); else row_5 <= x"FF"; end if;
      if porta_in(6)='0' then row_6 <= matrix(55 downto 48); else row_6 <= x"FF"; end if;
      if porta_in(7)='0' then row_7 <= matrix(63 downto 56); else row_7 <= x"FF"; end if;
    
      portb_value := row_0 and row_1 and row_2 and row_3 and row_4 and row_5 and row_6 and row_7;

      -- XXX - Reading keyboard other way around not implemented.
    
      -- Keyboard rows and joystick 1
      portb_out(7 downto 5) <= portb_value(7 downto 5);
      portb_out(4) <= portb_value(4) and joy1(4);
      portb_out(3) <= portb_value(3) and joy1(3);
      portb_out(2) <= portb_value(2) and joy1(2);
      portb_out(1) <= portb_value(1) and joy1(1);
      portb_out(0) <= portb_value(0) and joy1(0);

      -- Keyboard columns and joystick 2
      porta_out(7 downto 5) <= porta_in(7 downto 5);
      porta_out(4) <= porta_in(4) and joy2(4);
      porta_out(3) <= porta_in(3) and joy2(3);
      porta_out(2) <= porta_in(2) and joy2(2);
      porta_out(1) <= porta_in(1) and joy2(1);
      porta_out(0) <= porta_in(0) and joy2(0);

  end process keyread;

end behavioural;
