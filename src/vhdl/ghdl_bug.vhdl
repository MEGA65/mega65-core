library ieee;
USE ieee.std_logic_1164.ALL;
use ieee.numeric_std.all;
use STD.textio.all;
use work.all;
use work.debugtools.all;
use work.cputypes.all;

entity ghdl_bug is
  
end ghdl_bug;

architecture behavior of ghdl_bug is

  type CharFile is file of character;
  
  signal pmoda : std_logic_vector(7 downto 0) := "ZZZZZZZZ";
  signal pmodc : std_logic_vector(7 downto 0) := "ZZZZZZZZ";
  
  signal pixelclock : std_logic := '1';
  signal cpuclock : std_logic := '1';
  signal clock50mhz : std_logic := '1';
  signal clock27 : std_logic := '1';
  signal clock100 : std_logic := '1';
  signal clock163 : std_logic := '1';
  signal clock325 : std_logic := '1';
  signal reset : std_logic := '0';
  signal irq : std_logic := '1';
  signal nmi : std_logic := '1';
  signal cpu_exrom : std_logic := '1';
  signal cpu_game : std_logic := '1';

  signal vsync : std_logic := '0';
  signal hsync : std_logic := '0';
  signal vgared : unsigned(7 downto 0) := x"00";
  signal vgagreen : unsigned(7 downto 0) := x"00";
  signal vgablue : unsigned(7 downto 0) := x"00";

  signal led : std_logic_vector(15 downto 0) := x"0000";
  signal sw : std_logic_vector(15 downto 0) := (others => '0');
  signal btn : std_logic_vector(4 downto 0) := (others => '0');

  signal qspidb : unsigned(3 downto 0) := (others => '0');
  signal qspicsn : std_logic := '0';
  signal qspisck : std_logic := '0';
  signal aclsck : std_logic := '0';

  signal UART_TXD : std_logic := '0';
  signal RsRx : std_logic := '0';
  
  signal sseg_ca : std_logic_vector(7 downto 0) := x"00";
  signal sseg_an : std_logic_vector(7 downto 0) := x"00";

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
  signal eth_txen : std_logic := '0';
  signal eth_txd : unsigned(1 downto 0) := "00";

  signal cart_ctrl_dir : std_logic := '0';
  signal cart_haddr_dir : std_logic := '0';
  signal cart_laddr_dir : std_logic := '0';
  signal cart_data_dir : std_logic := '0';
  signal cart_phi2 : std_logic := '0';
  signal cart_dotclock : std_logic := '0';
  signal cart_reset : std_logic := '0';

  signal cart_nmi : std_logic := '0';
  signal cart_irq : std_logic := '0';
  signal cart_dma : std_logic := '0';

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
  signal iec_clk_en : std_logic := '0';
  signal iec_data_en : std_logic := '0';
  signal iec_data_o : std_logic := '0';
  signal iec_reset : std_logic := '0';
  signal iec_clk_o : std_logic := '0';
  signal iec_atn_o : std_logic := '0';

  signal iec_data_external : std_logic := '0';
  signal iec_clk_external : std_logic := '1';

  ----------------------------------------------------------------------
  -- Slow devices (cartridge port, slow RAM etc)
  ----------------------------------------------------------------------
  signal slow_access_request_toggle : std_logic := '0';
  signal slow_access_ready_toggle : std_logic := '0';
  signal slow_access_write : std_logic := '0';
  signal slow_access_address : unsigned(27 downto 0) := (others => '0');
  signal slow_access_wdata : unsigned(7 downto 0) := (others => '0');
  signal slow_access_rdata : unsigned(7 downto 0) := (others => '0');

  signal sector_buffer_mapped : std_logic := '0';

  signal pot_drain : std_logic := '0';

  signal f_rdata : std_logic := '1';

  signal pcm_modem1_data_out : std_logic := '0';

  signal lcd_dataenable : std_logic := '1';

  signal hyper_addr : unsigned(18 downto 3) := (others => '0');
  signal hyper_request_toggle : std_logic := '0';
  signal hyper_data : unsigned(7 downto 0) := x"00";
  signal hyper_data_strobe : std_logic := '0';

  signal expansionram_read : std_logic := '0';
  signal expansionram_write : std_logic := '0';
  signal expansionram_rdata : unsigned(7 downto 0) := (others => '0');
  signal expansionram_wdata : unsigned(7 downto 0) := (others => '0');
  signal expansionram_address : unsigned(26 downto 0) := (others => '0');
  signal expansionram_busy : std_logic := '0';

  signal current_cache_line : cache_row_t := (others => (others => '0'));
  signal current_cache_line_address : unsigned(26 downto 3) := (others => '0');
  signal current_cache_line_valid : std_logic := '0';
  signal expansionram_current_cache_line_next_toggle : std_logic := '0';

  signal hr_d : unsigned(7 downto 0);
  signal hr_rwds : std_logic := '0';
  signal hr_reset : std_logic := '0';
  signal hr_clk_n : std_logic := '0';
  signal hr_clk_p : std_logic := '0';
  signal hr_cs0 : std_logic := '0';

  signal hr2_d : unsigned(7 downto 0) := (others => '0');
  signal hr2_rwds : std_logic := '0';
  signal hr2_reset : std_logic := '0';
  signal hr2_clk_n : std_logic := '0';
  signal hr2_clk_p : std_logic := '0';
  signal hr2_cs0 : std_logic := '0'; 

  signal audio_left : std_logic_vector(19 downto 0) := (others => '0');
  signal audio_right : std_logic_vector(19 downto 0) := (others => '0');
  
begin


  core0: entity work.machine
    generic map ( target => simulation,
    		  cpu_frequency => 40_500_000,
                  hyper_installed => true)
    port map (
      fpga_temperature => (others => '1'),

      portb_pins => (others => '1'),

      lcd_dataenable => lcd_dataenable,
      
      pixelclock      => pixelclock,
      cpuclock      => cpuclock,
      clock50mhz   => clock50mhz,
      clock100 => clock100,
      clock27 => clock27,
      clock162 => clock163,
      
      uartclock    => cpuclock,
      btnCpuReset      => reset,
      irq => irq,
      nmi => '1',
      cpu_exrom => cpu_exrom,
      cpu_game => cpu_game,

      hyper_addr => hyper_addr,
      hyper_request_toggle => hyper_request_toggle,
      hyper_data => hyper_data,
      hyper_data_strobe => hyper_data_strobe,     
      
      sector_buffer_mapped => sector_buffer_mapped,
      
      restore_key => '1',

      caps_lock_key => '1',
      
      no_hyppo => '0',

--      buffereduart_rx => '1',
      buffereduart_ringindicate => '1',
--      buffereduart2_rx => '1',
      
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
      
--      pmod_clock => '0',
--      pmod_start_of_sequence => '1',
--      pmod_data_in => "0000",
--      pmoda => pmoda,

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

      audio_left => audio_left,
      audio_right => audio_right,
      
      vsync           => vsync,
      vga_hsync           => hsync,
      vgared          => vgared,
      vgagreen        => vgagreen,
      vgablue         => vgablue,
      
      led             => led,
      sw              => sw,
      btn             => btn,

      widget_matrix_col => (others => '1'),
      widget_restore => '1',
      widget_capslock => '1',
      widget_joya => (others => '1'),
      widget_joyb => (others => '1'),
      
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

  process(hr_cs0, hr_clk_p, hr_reset, hr_rwds, hr_d,
          hr2_cs0, hr2_clk_p, hr2_reset, hr2_rwds, hr2_d
          ) is
  begin
    report
      "hr_cs0 = " & std_logic'image(hr_cs0) & ", " &
      "hr_clk_p = " & std_logic'image(hr_clk_p) & ", " &
      "hr_reset = " & std_logic'image(hr_reset) & ", " &
      "hr_rwds = " & std_logic'image(hr_rwds) & ", " &
      "hr_d = " & std_logic'image(hr_d(0))
      & std_logic'image(hr_d(1))
      & std_logic'image(hr_d(2))
      & std_logic'image(hr_d(3))
      & std_logic'image(hr_d(4))
      & std_logic'image(hr_d(5))
      & std_logic'image(hr_d(6))
      & std_logic'image(hr_d(7))
      & ".";
    report
      "hr2_cs0 = " & std_logic'image(hr2_cs0) & ", " &
      "hr2_clk_p = " & std_logic'image(hr2_clk_p) & ", " &
      "hr2_reset = " & std_logic'image(hr2_reset) & ", " &
      "hr2_rwds = " & std_logic'image(hr2_rwds) & ", " &
      "hr2_d = " & std_logic'image(hr2_d(0))
      & std_logic'image(hr2_d(1))
      & std_logic'image(hr2_d(2))
      & std_logic'image(hr2_d(3))
      & std_logic'image(hr2_d(4))
      & std_logic'image(hr2_d(5))
      & std_logic'image(hr2_d(6))
      & std_logic'image(hr2_d(7))
      & ".";
  end process;

  process
  begin  -- process tb

    wait for 3 ns;
    
    for i in 1 to 2000000 loop
      clock27 <= '0';
      wait for 18519 ps;
      clock27 <= '1';
      wait for 18519 ps;      
    end loop;
    
  end process;
  
  
  process
  begin  -- process tb
    report "beginning simulation" severity note;

    wait for 3 ns;
    
    for i in 1 to 2000000 loop

    clock325 <= '0';
    pixelclock <= '0';
    cpuclock <= '0';
    clock163 <= '0';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    pixelclock <= '1';
    clock163 <= '0';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    pixelclock <= '0';
    cpuclock <= '1';
    clock163 <= '0';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    pixelclock <= '1';
    clock163 <= '0';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;

    clock163 <= '1';

    clock325 <= '1';
    wait for 1.5 ns;
    clock325 <= '0';
    wait for 1.5 ns;
      
      if i = 10 then
        reset <= '1';
        report "Releasing reset";
      end if;
    end loop;  -- i
    assert false report "End of simulation" severity failure;
  end process;

  -- Deliver dummy ethernet frames
  process
    procedure eth_clock_tick is
    begin
      -- XXX Doesn't tick the 120 or 240 MHz clocks
      clock50mhz <= '0';
      wait for 10 ns;
      clock50mhz <= '1';
      wait for 10 ns;
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
--  process
--  begin
--    wait for 38180 ns;
--    for i in 1 to 2000 loop
--      irq <= '0';
--      report "triggering IRQ for gs4510";
--      wait for 200 ns;
--      irq <= '1';
--      report "releasing IRQ for gs4510";
--      wait for 190 ns;
--    end loop;
--  end process;
  
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
  
end behavior;

