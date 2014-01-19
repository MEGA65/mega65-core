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

    last_scan_code : out unsigned(7 downto 0) := x"FF";

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
  
  signal ps2clock_prev : std_logic := '0';

  signal recent_scan_code_list_index : unsigned(7 downto 0) := x"01";

  signal keymem_write : std_logic := '0';
  signal keymem_addr : unsigned(7 downto 0) := x"00";
  signal keymem_data : unsigned(7 downto 0) := x"00";

  signal keymem_fastio_cs : std_logic;

  signal douta : std_logic_vector(7 downto 0);
  
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
    if fastio_address(19 downto 8) = x"FD5" and fastio_write='0' then
      keymem_fastio_cs <= '0';
      fastio_rdata <= fastio_address(7 downto 0);
    if fastio_address(19 downto 8) = x"FD4" and fastio_write='0' then
      keymem_fastio_cs <= '1';
      fastio_rdata <= douta;
    else
      keymem_fastio_cs <= '0';
      fastio_rdata <= (others => 'Z');
    end if;
  end process fastio;

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

      ps2data_samples <= ps2data_samples(7 downto 1) & ps2data;
      if ps2data_samples = "11111111" then
        ps2data_debounced <= '1';
      end if;
      if ps2data_samples = "00000000" then
        ps2data_debounced <= '0';
      end if;
      
      ps2clock_prev <= ps2clock_debounced;
      ps2clock <= ps2clock_prev;
      if ((ps2clock = '0' and ps2clock_prev = '1') and ps2state=Idle) then
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
                       if scan_code /= x"FF" then
                         last_scan_code <= scan_code;                         
                       end if;

                       keymem_addr <= recent_scan_code_list_index;
                       keymem_data <= scan_code;
                       keymem_write <= '1';

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
          when ParityBit =>  ps2state <= StopBit;
                             keymem_addr <= x"00";
                             keymem_data <= recent_scan_code_list_index;
                             keymem_write <= '1';

          when StopBit => ps2state <= Idle;
                          keymem_write <= '0';
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
