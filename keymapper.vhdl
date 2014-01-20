library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;

entity keymapper is
  
  port (
    clk : in std_logic;

    -- PS2 keyboard interface
    ps2clock  : in  std_logic;
    ps2data   : in  std_logic;
    -- CIA ports
    porta_in  : in  std_logic_vector(7 downto 0);
    porta_out : out std_logic_vector(7 downto 0);
    portb_in  : in  std_logic_vector(7 downto 0);
    portb_out : out std_logic_vector(7 downto 0);

    last_scan_code : out unsigned(11 downto 0) := x"0FF";

    ---------------------------------------------------------------------------
    -- Fastio interface to recent keyboard scan codes
    ---------------------------------------------------------------------------    
    fastio_address : in std_logic_vector(19 downto 0);
    fastio_write : in std_logic;
    fastio_wdata : in std_logic_vector(7 downto 0);
    fastio_rdata : out std_logic_vector(7 downto 0)
    );

end keymapper;

architecture behavioural of keymapper is

  component ram8x256 IS
    PORT (
      clka : IN STD_LOGIC;
      ena : IN STD_LOGIC;
      wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
      addra : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
      clkb : IN STD_LOGIC;
      web : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
      addrb : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      dinb : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
      doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
      );
  END component;

  type ps2_state is (Idle,StartBit,Bit0,Bit1,Bit2,Bit3,Bit4,Bit5,Bit6,Bit7,
                     ParityBit,StopBit);
  signal ps2state : ps2_state := Idle;

  signal scan_code : unsigned(7 downto 0) := x"FF";
  signal parity : std_logic := '0';

  -- PS2 clock rate is as low as 10KHz.  Allow double that for a timeout
  -- 64MHz/5KHz = 64000/5 = 12800 cycles
  constant ps2timeout : integer := 12800;
  signal ps2timer : integer := 0;

  signal ps2clock_samples : std_logic_vector(7 downto 0) := (others => '1');
  signal ps2clock_debounced : std_logic := '0';

  signal ps2data_samples : std_logic_vector(7 downto 0) := (others => '1');
  signal ps2data_debounced : std_logic := '0';

  signal ps2clock_prev : std_logic := '0';

  signal recent_scan_code_list_index : unsigned(7 downto 0) := x"01";

  signal keymem_write : std_logic := '0';
  signal keymem_addr : unsigned(7 downto 0) := x"00";
  signal keymem_data : unsigned(7 downto 0) := x"00";

  signal keymem_fastio_cs : std_logic;

  signal douta : std_logic_vector(7 downto 0);

  signal extended : std_logic := '0';
  signal break : std_logic := '0';

  type matrix_t is array (0 to 7) of std_logic_vector(7 downto 0);
  signal matrix : matrix_t := (others => (others =>'1'));
  
begin  -- behavioural

  keymem1: component ram8x256
    port map (
      -- Port for fastio system to read from.      
      clka => clk,
      ena => keymem_fastio_cs,
      wea(0) => '0',
      addra => fastio_address(7 downto 0),
      dina => (others => '1'),
      douta => douta,

      -- Port for us to write to
      clkb => clk,
      web(0) => keymem_write,
      addrb => std_logic_vector(keymem_addr),
      dinb => std_logic_vector(keymem_data)
      );


  -- Map recent key presses to $FFD4000 - $FFD40FF
  -- (this is a read only register set)
  fastio: process (fastio_address,fastio_write)
  begin  -- process fastio
    if fastio_address(19 downto 8) = x"D40" and fastio_write='0' then
      keymem_fastio_cs <= '1';
      fastio_rdata <= douta;
    elsif fastio_address(19 downto 4) = x"D410" and fastio_write='0' then
      fastio_rdata <= matrix(to_integer(unsigned(fastio_address(3 downto 0))));
    else
      keymem_fastio_cs <= '0';
      fastio_rdata <= (others => 'Z');
    end if;
  end process fastio;

-- purpose: read from ps2 keyboard interface
  keyread: process (clk, ps2data,ps2clock)
    variable full_scan_code : std_logic_vector(11 downto 0);
    variable portb_value : std_logic_vector(7 downto 0);
  begin  -- process keyread
    if rising_edge(clk) then
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
                       keymem_write <= '0';
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

                       keymem_addr <= recent_scan_code_list_index;
                       keymem_data <= scan_code;
                       keymem_write <= '1';

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

                         last_scan_code <= break&"00"&unsigned(full_scan_code(8 downto 0));
                         
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
                           when x"1E0" => matrix(0) <= (matrix(0) and x"FE") or "0000000"&break;
                           when x"05A" => matrix(0) <= (matrix(0) and x"FD") or "000000"&break&"0";
                           when x"174" => matrix(0) <= (matrix(0) and x"FB") or "00000"&break&"00";
                           when x"083" => matrix(0) <= (matrix(0) and x"F7") or "0000"&break&"000";
                           when x"005" => matrix(0) <= (matrix(0) and x"EF") or "000"&break&"0000";
                           when x"004" => matrix(0) <= (matrix(0) and x"DF") or "00"&break&"00000";
                           when x"003" => matrix(0) <= (matrix(0) and x"BF") or "0"&break&"000000";
                           when x"072" => matrix(0) <= (matrix(0) and x"7F") or break&"0000000";

                           when x"026" => matrix(1) <= (matrix(1) and x"FE") or "0000000"&break;
                           when x"01D" => matrix(1) <= (matrix(1) and x"FD") or "000000"&break&"0";
                           when x"01C" => matrix(1) <= (matrix(1) and x"FB") or "00000"&break&"00";
                           when x"025" => matrix(1) <= (matrix(1) and x"F7") or "0000"&break&"000";
                           when x"01A" => matrix(1) <= (matrix(1) and x"EF") or "000"&break&"0000";
                           when x"01B" => matrix(1) <= (matrix(1) and x"DF") or "00"&break&"00000";
                           when x"024" => matrix(1) <= (matrix(1) and x"BF") or "0"&break&"000000";
                           when x"012" => matrix(1) <= (matrix(1) and x"7F") or break&"0000000";                                          
                                          
                           when x"02E" => matrix(2) <= (matrix(2) and x"FE") or "0000000"&break;
                           when x"02D" => matrix(2) <= (matrix(2) and x"FD") or "000000"&break&"0";
                           when x"023" => matrix(2) <= (matrix(2) and x"FB") or "00000"&break&"00";
                           when x"036" => matrix(2) <= (matrix(2) and x"F7") or "0000"&break&"000";
                           when x"021" => matrix(2) <= (matrix(2) and x"EF") or "000"&break&"0000";
                           when x"02B" => matrix(2) <= (matrix(2) and x"DF") or "00"&break&"00000";
                           when x"02C" => matrix(2) <= (matrix(2) and x"BF") or "0"&break&"000000";
                           when x"022" => matrix(2) <= (matrix(2) and x"7F") or break&"0000000";

                           when x"03D" => matrix(3) <= (matrix(3) and x"FE") or "0000000"&break;
                           when x"035" => matrix(3) <= (matrix(3) and x"FD") or "000000"&break&"0";
                           when x"034" => matrix(3) <= (matrix(3) and x"FB") or "00000"&break&"00";
                           when x"03E" => matrix(3) <= (matrix(3) and x"F7") or "0000"&break&"000";
                           when x"032" => matrix(3) <= (matrix(3) and x"EF") or "000"&break&"0000";
                           when x"033" => matrix(3) <= (matrix(3) and x"DF") or "00"&break&"00000";
                           when x"03C" => matrix(3) <= (matrix(3) and x"BF") or "0"&break&"000000";
                           when x"02A" => matrix(3) <= (matrix(3) and x"7F") or break&"0000000";                                          
                                          
                           when x"046" => matrix(4) <= (matrix(4) and x"FE") or "0000000"&break;
                           when x"043" => matrix(4) <= (matrix(4) and x"FD") or "000000"&break&"0";
                           when x"03B" => matrix(4) <= (matrix(4) and x"FB") or "00000"&break&"00";
                           when x"045" => matrix(4) <= (matrix(4) and x"F7") or "0000"&break&"000";
                           when x"03A" => matrix(4) <= (matrix(4) and x"EF") or "000"&break&"0000";
                           when x"042" => matrix(4) <= (matrix(4) and x"DF") or "00"&break&"00000";
                           when x"044" => matrix(4) <= (matrix(4) and x"BF") or "0"&break&"000000";
                           when x"031" => matrix(4) <= (matrix(4) and x"7F") or break&"0000000";
                                          
                           when x"055" => matrix(5) <= (matrix(5) and x"FE") or "0000000"&break;
                           when x"04D" => matrix(5) <= (matrix(5) and x"FD") or "000000"&break&"0";
                           when x"04B" => matrix(5) <= (matrix(5) and x"FB") or "00000"&break&"00";
                           when x"04E" => matrix(5) <= (matrix(5) and x"F7") or "0000"&break&"000";
                           when x"049" => matrix(5) <= (matrix(5) and x"EF") or "000"&break&"0000";
                           when x"054" => matrix(5) <= (matrix(5) and x"DF") or "00"&break&"00000";
                           when x"05B" => matrix(5) <= (matrix(5) and x"BF") or "0"&break&"000000";
                           when x"041" => matrix(5) <= (matrix(5) and x"7F") or break&"0000000";
                                          
                           when x"052" => matrix(6) <= (matrix(6) and x"FE") or "0000000"&break;
                           when x"05D" => matrix(6) <= (matrix(6) and x"FD") or "000000"&break&"0";
                           when x"04C" => matrix(6) <= (matrix(6) and x"FB") or "00000"&break&"00";
                           when x"16C" => matrix(6) <= (matrix(6) and x"F7") or "0000"&break&"000";
                           when x"059" => matrix(6) <= (matrix(6) and x"EF") or "000"&break&"0000";
                           when x"169" => matrix(6) <= (matrix(6) and x"DF") or "00"&break&"00000";
                           when x"075" => matrix(6) <= (matrix(6) and x"BF") or "0"&break&"000000";
                           when x"04A" => matrix(6) <= (matrix(6) and x"7F") or break&"0000000";

                           when x"016" => matrix(7) <= (matrix(7) and x"FE") or "0000000"&break;
                           when x"06B" => matrix(7) <= (matrix(7) and x"FD") or "000000"&break&"0";
                           when x"014" => matrix(7) <= (matrix(7) and x"FB") or "00000"&break&"00";
                           when x"01E" => matrix(7) <= (matrix(7) and x"F7") or "0000"&break&"000";
                           when x"029" => matrix(7) <= (matrix(7) and x"EF") or "000"&break&"0000";
                           when x"011" => matrix(7) <= (matrix(7) and x"DF") or "00"&break&"00000";
                           when x"015" => matrix(7) <= (matrix(7) and x"BF") or "0"&break&"000000";
                           when x"076" => matrix(7) <= (matrix(7) and x"7F") or break&"0000000";

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
                             keymem_addr <= x"00";
                             keymem_data <= recent_scan_code_list_index;
                             keymem_write <= '1';

          when StopBit => ps2state <= Idle;
                          keymem_write <= '0';
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
      if porta_in(0)='0' then portb_value:=portb_value and matrix(0); end if;
      if porta_in(1)='0' then portb_value:=portb_value and matrix(1); end if;
      if porta_in(2)='0' then portb_value:=portb_value and matrix(2); end if;
      if porta_in(3)='0' then portb_value:=portb_value and matrix(3); end if;
      if porta_in(4)='0' then portb_value:=portb_value and matrix(4); end if;
      if porta_in(5)='0' then portb_value:=portb_value and matrix(5); end if;
      if porta_in(6)='0' then portb_value:=portb_value and matrix(6); end if;
      if porta_in(7)='0' then portb_value:=portb_value and matrix(7); end if;
      
      -- Keyboard rows and joystick 1
      portb_out <= portb_value;

      -- Keyboard columns and joystick 2
      porta_out <= "11111111";
    end if;
  end process keyread;

end behavioural;
