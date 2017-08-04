use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.debugtools.all;

entity test_kv is
end test_kv;

architecture behavioral of test_kv is

  signal porta_pins : std_logic_vector(7 downto 0) := (others => 'Z');
  signal portb_pins : std_logic_vector(7 downto 0) := (others => 'Z');
  signal keyboard_column8_out : std_logic := '1';
  signal key_left : std_logic;
  signal key_up : std_logic;

  -- Flag to redirect output to UART instead of virtualised keyboard
  -- matrix 
  signal matrix_mode : std_logic;
        
  -- Virtualised keyboard matrix
  signal porta_to_cia : std_logic_vector(7 downto 0) := (others => 'Z');
  signal portb_to_cia : std_logic_vector(7 downto 0) := (others => 'Z');
  signal porta_from_cia : std_logic_vector(7 downto 0);
  signal portb_from_cia : std_logic_vector(7 downto 0);
  signal porta_ddr : std_logic_vector(7 downto 0);
  signal portb_ddr : std_logic_vector(7 downto 0);
  signal column8_from_cia : std_logic;

  -- UART key stream
  signal ascii_key : unsigned(7 downto 0) := (others => '0');
  -- Bucky key list:
  -- 0 = left shift
  -- 1 = right shift
  -- 2 = control
  -- 3 = C=
  -- 4 = ALT
  -- 5 = NO SCROLL
  -- 6 = ASC/DIN/CAPS LOCK (XXX - Has a separate line. Not currently monitored)
  signal bucky_key : std_logic_vector(6 downto 0) := (others  => '0');
  signal ascii_key_valid : std_logic := '0';

  signal pixelclock : std_logic := '0';
  signal cpuclock : std_logic := '0';
  signal ioclock : std_logic := '0';
  
begin
  kv: entity work.keyboard_virtualiser
    generic map (
      clock_frequency => 50000000,
      scan_frequency => 25000000)
    port map (
      clk => cpuclock,
      porta_pins => porta_pins,
      portb_pins => portb_pins,
      keyboard_column8_out => keyboard_column8_out,
      key_left => key_left,
      key_up => key_up,
      matrix_mode => matrix_mode,
      porta_to_cia => porta_to_cia,
      portb_to_cia => portb_to_cia,
      porta_from_cia => porta_from_cia,
      portb_from_cia => portb_from_cia,
      porta_ddr => porta_ddr,
      portb_ddr => portb_ddr,
      column8_from_cia => column8_from_cia,
      ascii_key => ascii_key,
      bucky_key => bucky_key,
      ascii_key_valid => ascii_key_valid
      );

  process
  begin
    for i in 1 to 2000000 loop
      pixelclock <= '0'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '0'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '0'; ioclock <= '0';
      wait for 5 ns;     
      pixelclock <= '0'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;     
      pixelclock <= '0'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;     
      pixelclock <= '1'; cpuclock <= '1'; ioclock <= '1';
      wait for 5 ns;
    end loop;  -- i
    assert false report "End of simulation" severity failure;
  end process;

  -- Pull up resisters
  porta_pins <= (others => 'H');
  portb_pins <= (others => 'H');
  
  -- Monitor keyboard activity
  process (cpuclock)
  begin
    if rising_edge(cpuclock) then
      if ascii_key_valid='1' then
        report "bucky vector = " & to_string(bucky_key)
          & " ASCII code = 0x" & to_hstring(ascii_key);
      end if;
      null;
    end if;
  end process;

  -- Induce some fake keyboard activity
  process (cpuclock)
  begin
    if rising_edge(cpuclock) then
      if porta_pins(0)='0' then
        portb_pins(3) <= '0';
      else
        portb_pins <= (others => 'Z');
      end if;
    end if;
  end process;  
  
end behavioral;
