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

    last_scan_code : out unsigned(7 downto 0) := x"FF"
    );

end keymapper;

architecture behavioural of keymapper is

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
  
  signal ps2clock_prev : std_logic := '0';

begin  -- behavioural
  
  -- purpose: read from ps2 keyboard interface
  keyread: process (clk, ps2data,ps2clock)
  begin  -- process keyread
    if rising_edge(clk) then
      -------------------------------------------------------------------------
      -- Generate timer for keyscan timeout
      -------------------------------------------------------------------------
      ps2timer <= ps2timer +1;
      if ps2timer = ps2timeout then
        ps2timer <= 0;
        ps2state <= Idle;
      end if;

      ps2clock_samples <= ps2clock_samples(7 downto 1) & ps2clock;
      if ps2clock_samples = "11111111" then
        ps2clock_debounced <= '1';
      end if;
      if ps2clock_samples = "00000000" then
        ps2clock_debounced <= '0';
      end if;
      
      ps2clock_prev <= ps2clock_debounced;
      if ps2clock = '0' and ps2clock_prev = '1' then
        ps2timer <= 0;
        case ps2state is
          when Idle => ps2state <= StartBit; scan_code <= x"FF"; parity <= '0';
          when StartBit => ps2state <= Bit0; scan_code(0) <= ps2data;
                           parity <= parity xor ps2data;
          when Bit0 => ps2state <= Bit1; scan_code(1) <= ps2data;
                       parity <= parity xor ps2data;                       
          when Bit1 => ps2state <= Bit2; scan_code(2) <= ps2data;
                       parity <= parity xor ps2data;                       
          when Bit2 => ps2state <= Bit3; scan_code(3) <= ps2data;
                       parity <= parity xor ps2data;                       
          when Bit3 => ps2state <= Bit4; scan_code(4) <= ps2data;
                       parity <= parity xor ps2data;                       
          when Bit4 => ps2state <= Bit5; scan_code(5) <= ps2data;
                       parity <= parity xor ps2data;                       
          when Bit5 => ps2state <= Bit6; scan_code(6) <= ps2data;
                       parity <= parity xor ps2data;                       
          when Bit6 => ps2state <= Bit7; scan_code(7) <= ps2data;
                       parity <= parity xor ps2data;                       
          when Bit7 => ps2state <= parityBit;
            if parity = ps2data then 
              -- Valid PS2 symbol
              last_scan_code <= scan_code;
            else
              last_scan_code <= x"FE";
            end if;                    
          when ParityBit =>  ps2state <= StopBit; 
          when StopBit => ps2state <= Idle;
        end case;        
      end if;
      
      
      -------------------------------------------------------------------------
      -- Update C64 CIA ports
      -------------------------------------------------------------------------
      -- Keyboard rows and joystick 1
      portb_out <= "11111111";

      -- Keyboard columns and joystick 2
      porta_out <= "11111111";

    end if;
  end process keyread;

end behavioural;
