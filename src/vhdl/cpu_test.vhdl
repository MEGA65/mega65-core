library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use STD.textio.all;
use work.all;
use work.debugtools.all;
use work.victypes.all;
use work.cputypes.all;

entity cpu_test is
  
end cpu_test;

architecture behavior of cpu_test is

  type CharFile is file of character;
  
  signal pmoda : std_logic_vector(7 downto 0) := "ZZZZZZZZ";
  signal pmodc : std_logic_vector(7 downto 0) := "ZZZZZZZZ";
  
  signal pixelclock : std_logic := '0';
  signal cpuclock : std_logic := '0';
  signal ioclock : std_logic := '0';
  signal clock50mhz : std_logic := '0';
  signal clock100 : std_logic := '0';
  signal clock162 : std_logic := '0';
  signal clock81 : std_logic := '0';
  signal clock27 : std_logic := '0';
  signal reset : std_logic := '0';
  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';
  signal cpu_exrom : std_logic := '1';
  signal cpu_game : std_logic := '1';

  signal vsync : std_logic;
  signal hsync : std_logic;
  signal vgared : unsigned(7 downto 0);
  signal vgagreen : unsigned(7 downto 0);
  signal vgablue : unsigned(7 downto 0);

  signal led : std_logic_vector(15 downto 0);
  signal sw : std_logic_vector(15 downto 0) := (others => '0');
  signal btn : std_logic_vector(4 downto 0) := (others => '0');

  signal qspidb : std_logic_vector(3 downto 0) := (others => '0');
  signal qspicsn : std_logic;
  signal qspisck : std_logic;
  signal aclsck : std_logic;

  signal UART_TXD : std_logic;
  signal RsRx : std_logic;
  
  signal sseg_ca : std_logic_vector(7 downto 0);
  signal sseg_an : std_logic_vector(7 downto 0);

  component slowram is
    port (address : in std_logic_vector(26 downto 0);
          datain : in std_logic_vector(7 downto 0);
          request_toggle : in std_logic;
          done_toggle : out std_logic;
          cache_address : in std_logic_vector(8 downto 0);
          we : in std_logic;
          cache_read_data : out std_logic_vector(150 downto 0)
          );
  end component;
  
  -- Sample ethernet frame to test CRC calculation
  type ram_t is array (0 to 4095) of unsigned(7 downto 0);
  signal frame : ram_t := (
    -- A real ping packet captured on the wire
    x"FF", x"FF", x"FF", x"FF", x"FF", x"FF", x"C8", x"2A", x"14", x"08",
    x"DA", x"E2", x"08", x"00", x"45", x"00", x"00", x"54", x"53", x"17",
    x"00", x"00", x"FF", x"01", x"6A", x"73", x"A9", x"FE", x"AA", x"21",
    x"A9", x"FE", x"FF", x"FF", x"08", x"00", x"DD", x"A7", x"CF", x"6E",
    x"00", x"79", x"53", x"DB", x"32", x"3C", x"00", x"00", x"D9", x"55",
    x"08", x"09", x"0A", x"0B", x"0C", x"0D", x"0E", x"0F", x"10", x"11",
    x"12", x"13", x"14", x"15", x"16", x"17", x"18", x"19", x"1A", x"1B",
    x"1C", x"1D", x"1E", x"1F", x"20", x"21", x"22", x"23", x"24", x"25",
    x"26", x"27", x"28", x"29", x"2A", x"2B", x"2C", x"2D", x"2E", x"2F",
    x"30", x"31", x"32", x"33", x"34", x"35", x"36", x"37", x"46", x"44",
    x"25", x"A6",

    
    others => x"00");

  signal eth_rxdv : std_logic := '0';
  signal eth_rxd : unsigned(1 downto 0) := "00";
  signal eth_txen : std_logic;
  signal eth_txd : unsigned(1 downto 0);

  signal cart_ctrl_dir : std_logic;
  signal cart_haddr_dir : std_logic;
  signal cart_laddr_dir : std_logic;
  signal cart_data_dir : std_logic;
  signal cart_phi2 : std_logic;
  signal cart_dotclock : std_logic;
  signal cart_reset : std_logic;

  signal cart_nmi : std_logic;
  signal cart_irq : std_logic;
  signal cart_dma : std_logic;

  signal cart_exrom : std_logic := 'Z';
  signal cart_ba : std_logic := 'Z';
  signal cart_rw : std_logic := 'Z';
  signal cart_roml : std_logic := 'Z';
  signal cart_romh : std_logic := 'Z';
  signal cart_io1 : std_logic := 'Z';
  signal cart_game : std_logic := 'Z';
  signal cart_io2 : std_logic := 'Z';

  signal cart_d : unsigned(7 downto 0) := (others => 'Z');
  signal cart_d_read : unsigned(7 downto 0) := (others => 'Z');
  signal cart_a : unsigned(15 downto 0) := (others => 'Z');
  
  ----------------------------------------------------------------------
  -- CBM floppy serial port
  ----------------------------------------------------------------------
  signal iec_clk_en : std_logic;
  signal iec_data_en : std_logic;
  signal iec_data_o : std_logic;
  signal iec_reset : std_logic;
  signal iec_clk_o : std_logic;
  signal iec_atn_o : std_logic;

  signal iec_data_external : std_logic := '0';
  signal iec_clk_external : std_logic := '1';

  signal widget_matrix_col_idx : integer range 0 to 8 := 0;
  signal widget_matrix_col : std_logic_vector(7 downto 0);
  signal widget_restore : std_logic := '1';
  signal widget_capslock : std_logic := '0';
  signal widget_joya : std_logic_vector(4 downto 0);
  signal widget_joyb : std_logic_vector(4 downto 0);
  
  ----------------------------------------------------------------------
  -- Slow devices (cartridge port, slow RAM etc)
  ----------------------------------------------------------------------
  signal slow_access_request_toggle : std_logic;
  signal slow_access_ready_toggle : std_logic;
  signal slow_access_write : std_logic;
  signal slow_access_address : unsigned(27 downto 0);
  signal slow_access_wdata : unsigned(7 downto 0);
  signal slow_access_rdata : unsigned(7 downto 0);

  signal sector_buffer_mapped : std_logic;

  signal pot_drain : std_logic := '0';

  signal f_rdata : std_logic := '1';

  signal pcm_modem1_data_out : std_logic := '0';

  signal lcd_dataenable : std_logic := '1';
  
begin

  fake_expansion_port0: entity work.fake_expansion_port
    port map (
      cpuclock => cpuclock,
      ----------------------------------------------------------------------
      -- Expansion/cartridge port
      ----------------------------------------------------------------------
      cart_ctrl_dir => cart_ctrl_dir,
      cart_haddr_dir => cart_haddr_dir,
      cart_laddr_dir => cart_laddr_dir,
      cart_data_dir => cart_data_dir,
      cart_phi2 => cart_phi2,
      cart_dotclock => cart_dotclock,
      cart_reset => cart_reset,
      
      cart_nmi => cart_nmi,
      cart_irq => cart_irq,
      cart_dma => cart_dma,
      
      cart_exrom => cart_exrom,
      cart_ba => cart_ba,
      cart_rw => cart_rw,
      cart_roml => cart_roml,
      cart_romh => cart_romh,
      cart_io1 => cart_io1,
      cart_game => cart_game,
      cart_io2 => cart_io2,
      
      cart_d => cart_d,
      cart_d_read => cart_d_read,
      cart_a => cart_a
      );

  
  slow_devices0: entity work.slow_devices
    port map (
      cpuclock => cpuclock,
      pixelclock => pixelclock,
      reset => reset,
      cpu_exrom => cpu_exrom,
      cpu_game => cpu_game,

      sector_buffer_mapped => sector_buffer_mapped,
      
      qspidb => qspidb,
      qspicsn => qspicsn,      
      qspisck => qspisck,

      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle => slow_access_ready_toggle,
      slow_access_write => slow_access_write,
      slow_access_address => slow_access_address,
      slow_access_wdata => slow_access_wdata,
      slow_access_rdata => slow_access_rdata,
  
      expansionram_data_ready_strobe => '0',
    
      ----------------------------------------------------------------------
      -- Expansion/cartridge port
      ----------------------------------------------------------------------
      cart_ctrl_dir => cart_ctrl_dir,
      cart_haddr_dir => cart_haddr_dir,
      cart_laddr_dir => cart_laddr_dir,
      cart_data_dir => cart_data_dir,
      cart_phi2 => cart_phi2,
      cart_dotclock => cart_dotclock,
      cart_reset => cart_reset,
      
      cart_nmi => cart_nmi,
      cart_irq => cart_irq,
      cart_dma => cart_dma,
      
      cart_exrom => cart_exrom,
      cart_ba => cart_ba,
      cart_rw => cart_rw,
      cart_roml => cart_roml,
      cart_romh => cart_romh,
      cart_io1 => cart_io1,
      cart_game => cart_game,
      cart_io2 => cart_io2,
      
      cart_d_in => cart_d_read,
      cart_d => cart_d,
      cart_a => cart_a
      );
  
  core0: entity work.machine
    generic map (
      target => mega65r2
      )
    port map (
      fpga_temperature => (others => '1'),

      portb_pins => (others => '1'),

      lcd_dataenable => lcd_dataenable,
      
      pixelclock   => clock81,
      cpuclock     => cpuclock,
      clock50mhz   => clock50mhz,
      clock100     => clock100,
      clock27      => clock27,
      clock162     => clock162,
      ioclock      => cpuclock,
      uartclock    => ioclock,
      btnCpuReset  => reset,
      irq => irq,
      nmi => '1',
      cpu_exrom => cpu_exrom,
      cpu_game => cpu_game,

      sector_buffer_mapped => sector_buffer_mapped,
      
      restore_key => '1',

      caps_lock_key => '1',
      
      no_hyppo => '0',

--      buffereduart_rx => '1',
      buffereduart_ringindicate => '1',
--      buffereduart2_rx => '1',

      -- Connect MEGA65 smart keyboard via JTAG-like remote GPIO interface
      widget_matrix_col_idx => widget_matrix_col_idx,
      widget_matrix_col => widget_matrix_col,
      widget_restore => widget_restore,
      widget_capslock => widget_capslock,
      widget_joya => (others => '1'),
      widget_joyb => (others => '1'),      

      ps2data => '1',
      ps2clock => '1',

      pcm_modem1_data_out => pcm_modem1_data_out,
      
      keyleft => '1',
      keyup => '1',
      
      fa_left => '1',
      fa_right => '1',
      fa_up => '1',
      fa_down => '1',
      fa_fire => '1',
      
      fb_left => '1',
      fb_right => '1',
      fb_up => '1',
      fb_down => '1',
      fb_fire => '1',
      
      fa_potx => '0',
      fa_poty => '0',
      fb_potx => '0',
      fb_poty => '0',

      f_index => '1',
      f_track0 => '1',
      f_writeprotect => '1',
      f_rdata => f_rdata,
      f_diskchanged => '1',      
      
      pot_drain => pot_drain,
      
      slow_access_request_toggle => slow_access_request_toggle,
      slow_access_ready_toggle => slow_access_ready_toggle,
      slow_access_address => slow_access_address,
      slow_access_write => slow_access_write,
      slow_access_wdata => slow_access_wdata,
      slow_access_rdata => slow_access_rdata,
      
      ----------------------------------------------------------------------
      -- CBM floppy  std_logic_vectorerial port
      ----------------------------------------------------------------------
      iec_clk_en => iec_clk_en,
      iec_data_en => iec_data_en,
      iec_data_o => iec_data_o,
      iec_reset => iec_reset,
      iec_clk_o => iec_clk_o,
      iec_atn_o => iec_atn_o,
      iec_data_external => iec_data_external,
      iec_clk_external => iec_clk_external,
      
      uart_rx => pmodc(1),
      uart_tx => pmodc(2),

      miso_i => '1',
      miso2_i => '1',

      aclsck => aclsck,
      aclMISO => '1',
      aclInt1 => '0',
      aclInt2 => '0',
      micData0 => '0',
      micData1 => '0',
      tmpInt => '0',
      tmpCT => '0',      

      eth_txd => eth_txd,
      eth_txen => eth_txen,
      eth_rxd => eth_rxd,
      eth_rxdv => eth_rxdv,
      eth_rxer => '0',
      eth_interrupt => '0',

      vsync           => vsync,
      vga_hsync           => hsync,
      vgared          => vgared,
      vgagreen        => vgagreen,
      vgablue         => vgablue,
      
      led             => led,
      sw              => sw,
      btn             => btn,

      -- UART monitor interface
      uart_txd        => uart_txd,
      rsrx            => rsrx,

      sseg_ca         => sseg_ca,
      sseg_an         => sseg_an);

  process is
    file trace : CharFile;
    variable c : character;
  begin
    while true loop
      file_open(trace,"assets/synthesised-60ns.dat",READ_MODE);
      while not endfile(trace) loop
        Read(trace,c);
        f_rdata <= std_logic(to_unsigned(character'pos(c),8)(4));
        wait for 6 ns;
      end loop;
      file_close(trace);
    end loop;
  end process;

  
  process
  begin  -- process tb
    report "beginning simulation" severity note;
    
    for i in 1 to 2000000 loop
      pixelclock <= '0'; cpuclock <= '0'; ioclock <= '0';
      wait for 3.125 ns;     
      pixelclock <= '0'; cpuclock <= '0'; ioclock <= '0';
      wait for 3.125 ns;     
      pixelclock <= '1'; cpuclock <= '0'; ioclock <= '0';
      wait for 3.125 ns;     
      pixelclock <= '1'; cpuclock <= '0'; ioclock <= '0';
      wait for 3.125 ns;     
      pixelclock <= '0'; cpuclock <= '1'; ioclock <= '1';
      wait for 3.125 ns;     
      pixelclock <= '0'; cpuclock <= '1'; ioclock <= '1';
      wait for 3.125 ns;     
      pixelclock <= '1'; cpuclock <= '1'; ioclock <= '1';
      wait for 3.125 ns;     
      pixelclock <= '1'; cpuclock <= '1'; ioclock <= '1';
      wait for 3.125 ns;
      if i = 10 then
        reset <= '1';
        report "Releasing reset";
      end if;
    end loop;  -- i
    assert false report "End of simulation" severity failure;
  end process;


  process
  begin
    clock27 <= '0';

    clock81 <= '0';
    clock162 <= '0';
    wait for 3.12 ns;
    clock162 <= '1';
    wait for 3.12 ns;

    clock81 <= '1';
    clock162 <= '0';
    wait for 3.12 ns;
    clock162 <= '1';
    wait for 3.12 ns;
    
    clock81 <= '0';
    clock162 <= '0';
    wait for 3.12 ns;
    clock162 <= '1';
    wait for 3.12 ns;

    clock27 <= '1';    
    clock81 <= '1';
    clock162 <= '0';
    wait for 3.12 ns;
    clock162 <= '1';
    wait for 3.12 ns;
    
    clock81 <= '0';
    clock162 <= '0';
    wait for 3.12 ns;
    clock162 <= '1';
    wait for 3.12 ns;

    clock81 <= '1';
    clock162 <= '0';
    wait for 3.12 ns;
    clock162 <= '1';
    wait for 3.12 ns;
    

  end process;

  -- Deliver dummy ethernet frames
  process
    procedure eth_clock_tick is
    begin
      clock50mhz <= '0';
      clock100 <= '0';
      wait for 5 ns;
      clock100 <= '1';
      wait for 5 ns;
      clock50mhz <= '1';
      clock100 <= '0';
      wait for 5 ns;
      clock100 <= '1';
      wait for 5 ns;
    end procedure;
  begin
    for i in 1 to 20 loop
      eth_rxdv <= '0'; eth_rxd <= "00";
      -- Wait a few cycles before feeding frame
      for j in 1 to 50 loop
        eth_clock_tick;
      end loop;

      if false then
        -- Announce RX carrier
        eth_rxdv <= '1'; eth_rxd <= "00";
        eth_clock_tick;
        eth_clock_tick;
        -- Send preamble
        report "CRC: Starting to send preamble";
        for j in 1 to 31 loop
          eth_rxd <= "01";
          eth_clock_tick;
        end loop;
        -- Send end of preamble
        eth_rxd <= "11";
        eth_clock_tick;
        -- Feed bytes
        report "CRC: Starting to send frame";
        for j in 0 to 101 loop
          report "ETHRXINJECT: Injecting $" & to_hstring(frame(j));
          eth_rxd <= frame(j)(1 downto 0);
          eth_clock_tick;
          eth_rxd <= frame(j)(3 downto 2);
          eth_clock_tick;
          eth_rxd <= frame(j)(5 downto 4);
          eth_clock_tick;
          eth_rxd <= frame(j)(7 downto 6);
          eth_clock_tick;
        end loop;
        -- Disassert carrier
        eth_rxdv <= '0';
        eth_clock_tick;
      end if; 
      -- Wait a few cycles before feeding next frame
      for j in 1 to 10000 loop
        eth_clock_tick;
      end loop;
    end loop;
  end process;

  -- Trigger an IRQ to test branch bug
  process
  begin
    wait for 38180 ns;
    for i in 1 to 2000 loop
      irq <= '0';
      report "triggering IRQ for gs4510";
      wait for 200 ns;
      irq <= '1';
      report "releasing IRQ for gs4510";
      wait for 190 ns;
    end loop;
  end process;
  
  process
    variable txbyte : unsigned(7 downto 0) := x"00";
    variable txbits : integer range 0 to 7 := 0;
  begin
    for i in 1 to 200000000 loop
      if clock50mhz='1' then
        if eth_txen='1' then
          report "ETHTX: bits " & to_string(std_logic_vector(eth_txd));
          txbyte := eth_txd & txbyte(7 downto 2);
          if txbits = 6 then
            txbits := 0;
            report "ETHTX: byte $" & to_hstring(txbyte);
          else
            txbits := txbits + 2;
          end if;
        else
--          report "ETHTX: bits NO CARRIER";
        end if;
      end if;
      wait for 10 ns;
      
    end loop;
  end process;

  process (clock50mhz) is
  begin
    if rising_edge(clock50mhz) then
      report "PCM digital audio out = " & std_logic'image(pcm_modem1_data_out);
    end if;
  end process;

  process (pixelclock) is
  begin
    if rising_edge(pixelclock) then
      report "lcd_dataenable = " & std_logic'image(lcd_dataenable);
    end if;
  end process;
  
  
end behavior;

