library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.debugtools.all;

entity test_ethernet is
end entity;

architecture foo of test_ethernet is

  signal clock5mhz : std_logic := '0';
  signal clock50mhz : std_logic := '0';
  signal clock200mhz : std_logic := '0';
  signal counter5 : integer range 0 to 4 := 0;  
  
  signal reset : std_logic;
  signal irq : std_logic := '1';
  signal ethernet_cs : std_logic;

  signal cpu_ethernet_stream : std_logic := '0';

  signal eth_dibit_counter : integer := 0;
  signal cpu_counter : integer := 0;
  
    ---------------------------------------------------------------------------
    -- IO lines to the ethernet controller
    ---------------------------------------------------------------------------
  signal eth_mdio : std_logic := 'Z';
  signal eth_mdc : std_logic;
  signal eth_reset : std_logic;
  signal eth_rxd : unsigned(1 downto 0);
  signal eth_txd_out : unsigned(1 downto 0);
  signal eth_txen_out : std_logic;
  signal eth_rxdv : std_logic;
  signal eth_rxer : std_logic := '0';
  signal eth_interrupt : std_logic := '0';
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
  signal fastio_addr : unsigned(19 downto 0) := (others => '0');
  signal fastio_write : std_logic := '0';
  signal fastio_read : std_logic := '0';
  signal fastio_wdata : unsigned(7 downto 0) := x"42";
  signal fastio_rdata : unsigned(7 downto 0);

    ---------------------------------------------------------------------------
    -- compressed video stream from the VIC-IV frame packer for autonomous dispatch
    ---------------------------------------------------------------------------    
  signal buffer_moby_toggle :  std_logic := '0';
  signal buffer_offset : unsigned(11 downto 0) := to_unsigned(0,12);
  signal buffer_address : unsigned(11 downto 0);
  signal buffer_rdata : unsigned(7 downto 0) := x"42";

  signal instruction_strobe : std_logic := '0';
  signal raster_number : unsigned(11 downto 0) := (others => '0');
  signal vicii_raster : unsigned(11 downto 0) := (others => '0');
  signal badline_toggle : std_logic := '0';
  signal debug_vector : unsigned(63 downto 0) := (others => '0');
  signal d031_write_toggle : std_logic := '0';
  signal cpu_arrest : std_logic;    

begin

    eth0: entity work.ethernet 
      generic map (
        num_buffers => 4
        )
    port map (
    clock => clock50mhz,
    clock50mhz => clock50mhz,
    clock200 => clock200mhz,
    reset => reset,
    irq => irq,
    ethernet_cs => '1',

    ---------------------------------------------------------------------------
    -- IO lines to the ethernet controller
    ---------------------------------------------------------------------------
    eth_mdio => eth_mdio,
    eth_rxd_in => eth_rxd,
    eth_rxdv_in => eth_rxdv,
    eth_rxer => eth_rxer,
    eth_interrupt => eth_interrupt,
    
    ---------------------------------------------------------------------------
    -- fast IO port (clocked at core clock). 1MB address space
    ---------------------------------------------------------------------------
    fastio_addr => fastio_addr,
    fastio_write => fastio_write,
    fastio_read => fastio_read,
    fastio_wdata => fastio_wdata,
    fastio_rdata => fastio_rdata,

    ---------------------------------------------------------------------------
    -- compressed video stream from the VIC-IV frame packer for autonomous dispatch
    ---------------------------------------------------------------------------    
    buffer_moby_toggle => '0',
    buffer_offset => (others => '0'),
    buffer_rdata => x"00",

    instruction_strobe => '0',
    raster_number => to_unsigned(0,12),
    vicii_raster => to_unsigned(0,12),
    badline_toggle => '0',
    debug_vector => (others => '0'),
    d031_write_toggle => '0'

    );

    process (clock50mhz) is
    begin
      if rising_edge(clock50mhz) then
        if counter5 < 4 then
          counter5 <= counter5 + 1;
        else
          counter5 <= 0;
          clock5mhz <= not clock5mhz;
        end if;
      end if;
    end process;
    
  
    process is
    begin
      for i in 1 to 10000000 loop
        clock200mhz <= '0';
        clock50mhz <= '0';
        wait for 2.5 ns;
        clock200mhz <= '1';
        clock50mhz <= '0';
        wait for 2.5 ns;
        clock200mhz <= '0';
        clock50mhz <= '0';
        wait for 2.5 ns;
        clock200mhz <= '1';
        clock50mhz <= '0';
        wait for 2.5 ns;
        clock200mhz <= '0';
        clock50mhz <= '1';
        wait for 2.5 ns;
        clock200mhz <= '1';
        clock50mhz <= '1';
        wait for 2.5 ns;
        clock200mhz <= '0';
        clock50mhz <= '1';
        wait for 2.5 ns;
        clock200mhz <= '1';
        clock50mhz <= '1';
        wait for 2.5 ns;
      end loop;
    end process;

    process (clock50mhz) is
    begin
      if rising_edge(clock50mhz) then
        cpu_counter <= cpu_counter + 1;

        fastio_read <= '0'; fastio_write <= '0';
        case cpu_counter is
          -- Select 10mbit mode
          when 0 => fastio_read <= '0'; fastio_write <= '1'; fastio_addr <= x"d36e4"; fastio_wdata <= x"10";
                    report "Writing $10 to $FFD36E4 to select 10mbit mode";
          -- Release ethernet from reset
          when 1 => fastio_read <= '0'; fastio_write <= '1'; fastio_addr <= x"d36e0"; fastio_wdata <= x"03";
                    report "Releasing ethernet controller from reset.";
          -- Enable debug mode
--          when 2 => fastio_read <= '0'; fastio_write <= '1'; fastio_addr <= x"d36e4"; fastio_wdata <= x"de";
--                    report "Enable ETH RX debug mode";
          when others => null;
        end case;
        
      end if;
    end process;
    
    process (clock5mhz) is
    begin
      if rising_edge(clock5mhz) then
        -- Feed in 10mbit ethernet frame data

        if eth_dibit_counter /= 1000 then
          eth_dibit_counter <= eth_dibit_counter + 1;
        else
          eth_dibit_counter <= 0;
        end if;

--        report "ethernet counter = " & integer'image(eth_dibit_counter)
--          & ", eth_rxd = " & to_string(std_logic_vector(eth_rxd));
        
        case eth_dibit_counter is
          when 0   => eth_rxdv <= '0'; eth_rxd <= "00";
                      -- Send 01010111 final preamble byte
          when 10  => eth_rxdv <= '1'; eth_rxd <= "01";  -- x3
          when 11  => eth_rxdv <= '1'; eth_rxd <= "01";
          when 12  => eth_rxdv <= '1'; eth_rxd <= "01";  
          when 13  => eth_rxdv <= '1'; eth_rxd <= "11";
                      -- Dest MAC: FF:FF:FF:FF:FF:FF
          when 14  => eth_rxdv <= '1'; eth_rxd <= "11";
          when 15 to 37 => eth_rxdv <= '1'; eth_rxd <= "11";
                      -- SRC MAC: 10:05:01:12:34:56            
          when 38  => eth_rxdv <= '1'; eth_rxd <= "00";
          when 39  => eth_rxdv <= '1'; eth_rxd <= "00";
          when 40  => eth_rxdv <= '1'; eth_rxd <= "01";
          when 41  => eth_rxdv <= '1'; eth_rxd <= "00";

          when 42  => eth_rxdv <= '1'; eth_rxd <= "01";
          when 43  => eth_rxdv <= '1'; eth_rxd <= "01";
          when 44  => eth_rxdv <= '1'; eth_rxd <= "00";
          when 45  => eth_rxdv <= '1'; eth_rxd <= "00";
                      
          when 46  => eth_rxdv <= '1'; eth_rxd <= "01";
          when 47  => eth_rxdv <= '1'; eth_rxd <= "00";
          when 48  => eth_rxdv <= '1'; eth_rxd <= "00";
          when 49  => eth_rxdv <= '1'; eth_rxd <= "00";
                      
          when 50  => eth_rxdv <= '1'; eth_rxd <= "10";
          when 51  => eth_rxdv <= '1'; eth_rxd <= "00";
          when 52  => eth_rxdv <= '1'; eth_rxd <= "01";
          when 53  => eth_rxdv <= '1'; eth_rxd <= "00";
                      
          when 54  => eth_rxdv <= '1'; eth_rxd <= "00";
          when 55  => eth_rxdv <= '1'; eth_rxd <= "01";
          when 56  => eth_rxdv <= '1'; eth_rxd <= "11";
          when 57  => eth_rxdv <= '1'; eth_rxd <= "00";
                      
          when 58  => eth_rxdv <= '1'; eth_rxd <= "10";
          when 59  => eth_rxdv <= '1'; eth_rxd <= "01";
          when 60  => eth_rxdv <= '1'; eth_rxd <= "01";
          when 61  => eth_rxdv <= '1'; eth_rxd <= "01";
                      
          when others => eth_rxdv <= '0'; eth_rxd <= "00";
        end case;
        
        
      end if;
    end process;
    
    
end foo;
