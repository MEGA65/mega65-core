----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    22:30:37 12/10/2013 
-- Design Name: 
-- Module Name:    container - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.cputypes.all;
use work.types_pkg.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity container is
  Port ( CLK_IN : STD_LOGIC;         

         led_g : out std_logic;
         led_r : out std_logic;

         
         ----------------------------------------------------------------------
         -- keyboard/joystick 
         ----------------------------------------------------------------------

         -- Interface for physical keyboard
         kb_io0 : inout std_logic;
         kb_io1 : out std_logic;
         kb_io2 : in std_logic;

         ----------------------------------------------------------------------
         -- IEC Serial interface
         ----------------------------------------------------------------------
         iec_reset : out std_logic;
         iec_atn : out std_logic;
         iec_clk_en : out std_logic;
         iec_data_en : out std_logic;
         iec_srq_en : out std_logic;
         iec_clk_o : out std_logic := '0';
         iec_data_o : out std_logic;
         iec_srq_o : out std_logic;
         iec_clk_i : in std_logic;
         iec_data_i : in std_logic;
         iec_srq_i : in std_logic;

         ----------------------------------------------------------------------
         -- Serial monitor interface
         ----------------------------------------------------------------------
         UART_TXD : out std_logic;
         RsRx : in std_logic
         
         );
end container;

architecture Behavioral of container is

  signal fpga_done : std_logic := '1';
  
  signal ethclock : std_logic;
  signal cpuclock : std_logic;
  signal clock27 : std_logic;
  signal clock74p22 : std_logic;
  signal pixelclock : std_logic; -- i.e., clock81p
  signal clock100 : std_logic;
  signal clock163 : std_logic;
  signal clock200 : std_logic;
  signal clock270 : std_logic;
  signal clock325 : std_logic;

  -- XXX Actually connect to new keyboard
  signal restore_key : std_logic := '1';
  -- XXX Note that left and up are active HIGH!
  -- XXX Plumb these into the MEGA65R2 keyboard protocol receiver
  signal keyleft : std_logic := '0';
  signal keyup : std_logic := '0';
  -- On the R2, we don't use the "real" keyboard interface, but instead the
  -- widget board interface, so just have these as dummy all-high place holders
  signal column : std_logic_vector(8 downto 0) := (others => '1');
  signal row : std_logic_vector(7 downto 0) := (others => '1');
    
  -- XXX We should read the real temperature and feed this to the DDR controller
  -- so that it can update timing whenever the temperature changes too much.
  signal fpga_temperature : std_logic_vector(11 downto 0) := (others => '0');

  signal widget_matrix_col_idx : integer range 0 to 8 := 5;
  signal widget_matrix_col : std_logic_vector(7 downto 0);
  signal widget_restore : std_logic := '1';
  signal widget_capslock : std_logic := '0';
  signal widget_joya : std_logic_vector(4 downto 0);
  signal widget_joyb : std_logic_vector(4 downto 0);

  signal fastkey : std_logic;
    
  signal ascii_key : unsigned(7 downto 0);
  signal ascii_key_valid : std_logic := '0';
  signal bucky_key : std_logic_vector(6 downto 0);
  signal capslock_combined : std_logic;
  signal key_caps : std_logic := '0';
  signal key_restore : std_logic := '0';
  signal key_up : std_logic := '0';
  signal key_left : std_logic := '0';

  signal matrix_segment_num : std_logic_vector(7 downto 0);
  signal porta_pins : std_logic_vector(7 downto 0) := (others => '1');

  signal key_count : unsigned(15 downto 0) := to_unsigned(0,16);

  signal disco_led_en : std_logic := '0';
  signal disco_led_val : unsigned(7 downto 0);
  signal disco_led_id : unsigned(7 downto 0);  
  
  signal counter : integer := 0;
  
  signal trigger_reconfigure : std_logic := '0';
  signal icape2_read_val : unsigned(31 downto 0);
  signal green_i : unsigned(7 downto 0);
  signal last_x_zero : std_logic := '0';
  signal uart_tx_trigger : std_logic := '0';
  signal uart_txready : std_logic;
  signal uart_txready_last : std_logic;
  signal uart_msg_offset : integer := 0;
  signal uart_txdata : unsigned(7 downto 0) := x"00";

  signal icape2_reg : unsigned(4 downto 0) := "10110";
  signal icape2_reg_int : unsigned(7 downto 0) := x"16";

  signal fastio_write : std_logic := '0';
  signal fastio_read : std_logic := '0';
  signal fastio_addr : unsigned(19 downto 0) := x"00000";
  signal fastio_wdata : unsigned(7 downto 0) := x"00";
  signal fastio_rdata : unsigned(7 downto 0);
  
   type sine_t is array (0 to 8) of unsigned(7 downto 0);
   signal sine_table : sine_t := (
     0 => to_unsigned(0,8),
     1 => to_unsigned(22,8),
     2 => to_unsigned(43,8),
     3 => to_unsigned(64,8),
     4 => to_unsigned(82,8),
     5 => to_unsigned(98,8),
     6 => to_unsigned(110,8),
     7 => to_unsigned(120,8),
     8 => to_unsigned(126,8)
     );

  signal iec_debug_ram : unsigned(7 downto 0) := x"00";
  signal iec_debug_ram2 : unsigned(7 downto 0) := x"00";
  signal iec_debug_raddr : unsigned(7 downto 0) := x"00";
  signal iec_irq : unsigned(7 downto 0) := x"00";
  signal iec_status : unsigned(7 downto 0) := x"00";
  signal iec_data : unsigned(7 downto 0) := x"00";
  signal iec_devinfo : unsigned(7 downto 0) := x"00";
  signal iec_state : unsigned(11 downto 0) := x"000";
  signal iec_state_reached : unsigned(11 downto 0) := x"000";

  signal usec : unsigned(7 downto 0);
  signal msec : unsigned(7 downto 0);
  signal debug_waits : unsigned(7 downto 0);
  
  signal do_write : std_logic := '0';
  signal fastio_state : integer := 0;
  signal val : unsigned(11 downto 0) := x"000";
  signal write_reg : unsigned(3 downto 0) := x"0";
  signal write_val : unsigned(7 downto 0) := x"00";
  signal wcount : unsigned(7 downto 0) := x"00";

  signal uartrx_data : unsigned(7 downto 0);
  signal uartrx_ready : std_logic;
  signal uartrx_ack : std_logic := '0';
  signal last_uartrx_ready : std_logic := '0';
  
begin

--STARTUPE2:STARTUPBlock--7Series

--XilinxHDLLibrariesGuide,version2012.4
  STARTUPE2_inst: STARTUPE2
    generic map(PROG_USR=>"FALSE", --Activate program event security feature.
                                   --Requires encrypted bitstreams.
  SIM_CCLK_FREQ=>10.0 --Set the Configuration Clock Frequency(ns) for simulation.
    )
    port map(
--      CFGCLK=>CFGCLK,--1-bit output: Configuration main clock output
--      CFGMCLK=>CFGMCLK,--1-bit output: Configuration internal oscillator
                              --clock output
--             EOS=>EOS,--1-bit output: Active high output signal indicating the
                      --End Of Startup.
--             PREQ=>PREQ,--1-bit output: PROGRAM request to fabric output
             CLK=>'0',--1-bit input: User start-up clock input
             GSR=>'0',--1-bit input: Global Set/Reset input (GSR cannot be used
                      --for the port name)
             GTS=>'0',--1-bit input: Global 3-state input (GTS cannot be used
                      --for the port name)
             KEYCLEARB=>'0',--1-bit input: Clear AES Decrypter Key input
                                  --from Battery-Backed RAM (BBRAM)
             PACK=>'0',--1-bit input: PROGRAM acknowledge input

             -- Put CPU clock out on the QSPI CLOCK pin
             USRCCLKO=>'0',--1-bit input: User CCLK input
             USRCCLKTS=>'0',--1-bit input: User CCLK 3-state enable input

             -- Place DONE pin under programmatic control
             USRDONEO=>fpga_done,--1-bit input: User DONE pin output control
             USRDONETS=>'1' --1-bit input: User DONE 3-state enable output DISABLE
             );
-- End of STARTUPE2_inst instantiation


  -- New clocking setup, using more optimised selection of multipliers
  -- and dividers, as well as the ability of some clock outputs to provide an
  -- inverted clock for free.
  -- Also, the 50 and 100MHz ethernet clocks are now independent of the other
  -- clocks, so that Vivado shouldn't try to meet timing closure in the (already
  -- protected) domain crossings used for those.
  clocks1: entity work.clocking
    port map ( clk_in    => CLK_IN,
               clock27   => clock27,    --   27     MHz
               clock41   => cpuclock,   --   40.5   MHz
               clock50   => ethclock,   --   50     MHz
               clock74p22=> clock74p22, --   74.227 MHz
               clock81p  => pixelclock, --   81     MHz
               clock270  => clock270,
               clock163  => clock163,   --  162.5   MHz
               clock200  => clock200,   --  200     MHz
               clock325  => clock325    --  325     MHz
               );

  fpgatemp0: entity work.fpgatemp
    generic map (DELAY_CYCLES => 480)
    port map (
      rst => '0',
      clk => cpuclock,
      temp => fpga_temperature); 
  
  kbd0: entity work.mega65kbd_to_matrix
    port map (
      cpuclock => cpuclock,

      disco_led_en => disco_led_en,
      disco_led_id => disco_led_id,
      disco_led_val => disco_led_val,
      
      powerled => '1',
      flopled0 => '0',
      flopled2 => '0',
      flopledsd => '0',
      flopmotor => '0',
            
      kio8 => kb_io0,
      kio9 => kb_io1,
      kio10 => kb_io2,

--      kbd_datestamp => kbd_datestamp,
--      kbd_commit => kbd_commit,

      eth_load_enable => '0',
      
      matrix_col => widget_matrix_col,
      matrix_col_idx => widget_matrix_col_idx,
      restore => widget_restore,
      fastkey_out => fastkey,
      capslock_out => widget_capslock,
      upkey => keyup,
      leftkey => keyleft
      
      );    
  
  block5: block
  begin
    kc0 : entity work.keyboard_complex
      port map (
      reset_in => '1',
      matrix_mode_in => '0',
      viciv_frame_indicate => '0',

      matrix_disable_modifiers => '0',
      matrix_segment_num => matrix_segment_num,
      suppress_key_glitches => '0',
      suppress_key_retrigger => '0',
    
      scan_mode => "11",
      scan_rate => x"FF",

    widget_disable => '0',
    ps2_disable => '0',
    joyreal_disable => '0',
    joykey_disable => '0',
    physkey_disable => '0',
    virtual_disable => '0',

      joyswap => '0',
      
      joya_rotate => '0',
      joyb_rotate => '0',
      
    cpuclock       => cpuclock,
--    restore_out => restore_nmi,
    keyboard_restore => key_restore,
    keyboard_capslock => key_caps,
    key_left => key_left,
    key_up => key_up,

    key1 => (others => '1'),
    key2 => (others => '1'),
    key3 => (others => '1'),

    touch_key1 => (others => '1'),
    touch_key2 => (others => '1'),

--    keydown1 => osk_key1,
--    keydown2 => osk_key2,
--    keydown3 => osk_key3,
--    keydown4 => osk_key4,
      
--    hyper_trap_out => hyper_trap,
--    hyper_trap_count => hyper_trap_count,
--    restore_up_count => restore_up_count,
--    restore_down_count => restore_down_count,
--    reset_out => reset_out,
    ps2clock       => '1',
    ps2data        => '1',
--    last_scan_code => last_scan_code,
--    key_status     => seg_led(1 downto 0),
    porta_in       => (others => '1'),
    portb_in       => (others => '1'),
--    porta_out      => cia1porta_in,
--    portb_out      => cia1portb_in,
    porta_ddr      => (others => '1'),
    portb_ddr      => (others => '1'),

    joya(4) => '1',
    joya(0) => '1',
    joya(2) => '1',
    joya(1) => '1',
    joya(3) => '1',
    
    joyb(4) => '1',
    joyb(0) => '1',
    joyb(2) => '1',
    joyb(1) => '1',
    joyb(3) => '1',
    
--    key_debug_out => key_debug,
  
    porta_pins => porta_pins, 
    portb_pins => (others => '1'),

--    speed_gate => speed_gate,
--    speed_gate_enable => speed_gate_enable,

    capslock_out => capslock_combined,
--    keyboard_column8_out => keyboard_column8_out,
    keyboard_column8_select_in => '0',

    widget_matrix_col_idx => widget_matrix_col_idx,
    widget_matrix_col => widget_matrix_col,
      widget_restore => '1',
      widget_capslock => '1',
    widget_joya => (others => '1'),
    widget_joyb => (others => '1'),
      
      
    -- remote keyboard input via ethernet
      eth_keycode_toggle => '0',
      eth_keycode => (others => '0'),

    -- remote 
--    eth_keycode_toggle => key_scancode_toggle,
--    eth_keycode => key_scancode,

    -- ASCII feed via hardware keyboard scanner
    ascii_key => ascii_key,
    ascii_key_valid => ascii_key_valid,
    bucky_key => bucky_key(6 downto 0)
    
    );
  end block;

  uart_tx0: entity work.UART_TX_CTRL
    port map (
      send    => uart_tx_trigger,
      BIT_TMR_MAX => to_unsigned((40500000/2000000) - 1,24),
      clk     => cpuclock,
      data    => uart_txdata,
      ready   => uart_txready,
      uart_tx => UART_TXD);

  uart_rx0:     entity work.uart_rx port map (
    clk => cpuclock,
    bit_rate_divisor => to_unsigned((40_500_000/2_000_000) - 1,24),
    uart_rx => rsrx,
    data => uartrx_data,
    data_ready => uartrx_ready,
    data_acknowledge => uartrx_ack
    );
  
  reconfig0: entity work.reconfig
    port map (
      clock => cpuclock,
      reg_num => icape2_reg,
      trigger_reconfigure => trigger_reconfigure,
      reconfigure_address => x"00000000",
      boot_address => icape2_read_val
      );

  process (pixelclock,cpuclock,clock270,clock27,clock74p22) is
    function nybl2char(n : unsigned(3 downto 0)) return unsigned is
    begin
      case n is
        when x"0" => return x"30";
        when x"1" => return x"31";
        when x"2" => return x"32";
        when x"3" => return x"33";
        when x"4" => return x"34";
        when x"5" => return x"35";
        when x"6" => return x"36";
        when x"7" => return x"37";
        when x"8" => return x"38";
        when x"9" => return x"39";
        when x"A" => return x"41";
        when x"B" => return x"42";
        when x"C" => return x"43";
        when x"D" => return x"44";
        when x"E" => return x"45";
        when x"F" => return x"46";
        when others => return x"3F";
      end case;
    end function;
    
  begin
    
    -- Drive most ports, to relax timing
    if rising_edge(cpuclock) then      

      icape2_reg <= icape2_reg_int(4 downto 0);
      
      uart_txready_last <= uart_txready;
      uart_tx_trigger <= '0';
      if uart_txready = '1' and uart_txready_last='0' then
        uart_msg_offset <= uart_msg_offset + 1;
        uart_tx_trigger <= '1';
        case uart_msg_offset is
          when 0 => uart_txdata <= x"20";

          when 1 => uart_txdata <= nybl2char(icape2_reg_int(7 downto 4));
          when 2 => uart_txdata <= nybl2char(icape2_reg_int(3 downto 0));

          when 3 => uart_txdata <= x"3d"; -- = 
                    
          when 4 => uart_txdata <= nybl2char(icape2_read_val(31 downto 28));
          when 5 => uart_txdata <= nybl2char(icape2_read_val(27 downto 24));
          when 6 => uart_txdata <= nybl2char(icape2_read_val(23 downto 20));
          when 7 => uart_txdata <= nybl2char(icape2_read_val(19 downto 16));
          when 8 => uart_txdata <= nybl2char(icape2_read_val(15 downto 12));
          when 9 => uart_txdata <= nybl2char(icape2_read_val(11 downto 8));
          when 10 => uart_txdata <= nybl2char(icape2_read_val(7 downto 4));
          when 11 => uart_txdata <= nybl2char(icape2_read_val(3 downto 0));

          when 12 => uart_txdata <= x"20";
          when 13 => uart_txdata <= x"20";

          when 14 => uart_txdata <= nybl2char(iec_irq(7 downto 4));
          when 15 => uart_txdata <= nybl2char(iec_irq(3 downto 0));                     
          when 16 => uart_txdata <= x"20";
                     
          when 17 => uart_txdata <= nybl2char(iec_status(7 downto 4));
          when 18 => uart_txdata <= nybl2char(iec_status(3 downto 0));                     
          when 19 => uart_txdata <= x"20";
                     
          when 20 => uart_txdata <= nybl2char(iec_data(7 downto 4));
          when 21 => uart_txdata <= nybl2char(iec_data(3 downto 0));                     
          when 22 => uart_txdata <= x"20";
                     
          when 23 => uart_txdata <= nybl2char(iec_devinfo(7 downto 4));
          when 24 => uart_txdata <= nybl2char(iec_devinfo(3 downto 0));                     
          when 25 => uart_txdata <= x"20";

          when 26 => uart_txdata <= nybl2char(val(11 downto 8));
          when 27 => uart_txdata <= nybl2char(val(7 downto 4));
          when 28 => uart_txdata <= nybl2char(val(3 downto 0));                     
          when 29 => uart_txdata <= x"20";

          when 30 => uart_txdata <= nybl2char(wcount(7 downto 4));
          when 31 => uart_txdata <= nybl2char(wcount(3 downto 0));                     
          when 32 => uart_txdata <= x"20";

          when 33 => uart_txdata <= x"53";
          when 34 => uart_txdata <= x"74";
          when 35 => uart_txdata <= x"61";
          when 36 => uart_txdata <= x"74";
          when 37 => uart_txdata <= x"65";
          when 38 => uart_txdata <= x"3a";
          when 39 => uart_txdata <= nybl2char(iec_state(11 downto 8));
          when 40 => uart_txdata <= nybl2char(iec_state(7 downto 4));
          when 41 => uart_txdata <= nybl2char(iec_state(3 downto 0));                     
          when 42 => uart_txdata <= x"2f";
          when 43 => uart_txdata <= nybl2char(iec_state_reached(11 downto 8));
          when 44 => uart_txdata <= nybl2char(iec_state_reached(7 downto 4));
          when 45 => uart_txdata <= nybl2char(iec_state_reached(3 downto 0));                     
          when 46 => uart_txdata <= x"20";
                     
          when 47 => uart_txdata <= nybl2char(write_reg(3 downto 0));
          when 48 => uart_txdata <= nybl2char(write_val(7 downto 4));
          when 49 => uart_txdata <= nybl2char(write_val(3 downto 0));                     
          when 50 => uart_txdata <= x"20";

          when 51 => uart_txdata <= nybl2char(msec(7 downto 4));
          when 52 => uart_txdata <= nybl2char(msec(3 downto 0));                     
          when 53 => uart_txdata <= x"2e";
          when 54 => uart_txdata <= nybl2char(usec(7 downto 4));
          when 55 => uart_txdata <= nybl2char(usec(3 downto 0));                     
          when 56 => uart_txdata <= x"2c";
          when 57 => uart_txdata <= nybl2char(debug_waits(7 downto 4));
          when 58 => uart_txdata <= nybl2char(debug_waits(3 downto 0));                     
          when 59 => uart_txdata <= x"20";

          when 60 => uart_txdata <= nybl2char(iec_debug_ram(7 downto 4));
          when 61 => uart_txdata <= nybl2char(iec_debug_ram(3 downto 0));                     
          when 62 => uart_txdata <= x"3a";                     
          when 63 => uart_txdata <= nybl2char(iec_debug_ram2(7 downto 4));
          when 64 => uart_txdata <= nybl2char(iec_debug_ram2(3 downto 0));                     
          when 65 => uart_txdata <= x"3a";
          when 66 => uart_txdata <= nybl2char(iec_debug_raddr(7 downto 4));
          when 67 => uart_txdata <= nybl2char(iec_debug_raddr(3 downto 0));                     
                     
          when 68 => uart_txdata <= x"0d";
          when 69 => uart_txdata <= x"0a";     uart_msg_offset <= 0;          

          when others => uart_txdata <= x"00"; uart_msg_offset <= 0;            
        end case;
      end if;

      uartrx_ack <= '0';
      last_uartrx_ready <= uartrx_ready;
      if ascii_key_valid='1' then
        case ascii_key is
          -- R = reconfigure
          when x"52" | x"72" => trigger_reconfigure <= '1';
          -- +/- to select ICAPE2 register
          when x"2d" => icape2_reg_int <= icape2_reg_int - 1;
          when x"2b" => icape2_reg_int <= icape2_reg_int + 1;

          when others => null;
        end case;
      elsif uartrx_ready='1' and last_uartrx_ready='0' then
        uartrx_ack <= '1';

        case uartrx_data is
          -- Write to IEC registers
          when x"30" | x"31" | x"32" | x"33" | x"34" | x"35" | x"36" | x"37" | x"38" | x"39" =>
            val(11 downto 4) <= val(7 downto 0);
            val(3 downto 0) <= uartrx_data(3 downto 0);
          when x"41" | x"42" | x"43" | x"44" | x"45" | x"46"
            |  x"61" | x"62" | x"63" | x"64" | x"65" | x"66" =>
            val(11 downto 4) <= val(7 downto 0);
            val(3 downto 0) <= to_unsigned(9 + to_integer(uartrx_data(3 downto 0)),4);
          when x"0d" =>
            do_write <= '1';
            write_reg <= val(11 downto 8);
            write_val <= val(7 downto 0);
            wcount <= wcount + 1;

--          when x"21" => iec_clk_o <= '1';
--          when x"22" => iec_clk_o <= '0';
          when x"23" => iec_clk_en <= '1';
          when x"24" => iec_clk_en <= '0';
            
          when others => null;                         
        end case;        
      else
        if fastio_state < 99 then
          fastio_state <= fastio_state + 1;
        else
          fastio_state <= 0;
        end if;
        fastio_write <= '0';

        case fastio_state is
          when 0 => fastio_addr <= x"d3694"; fastio_read <= '1';
          when 1 => null;
          when 2 => iec_debug_ram <= fastio_rdata;
          when 3 => fastio_addr <= x"d3695"; fastio_read <= '1';
          when 4 => null;
          when 5 => iec_debug_ram2 <= fastio_rdata;
          when 6 => fastio_addr <= x"d3696"; fastio_read <= '1';
          when 7 => null;
          when 8 => iec_debug_raddr <= fastio_rdata;
          when 9 => fastio_addr <= x"d3697"; fastio_read <= '1';
          when 10 => null;
          when 11 => iec_irq <= fastio_rdata;
          when 12 => fastio_addr <= x"d3698"; fastio_read <= '1';
          when 13 => null;
          when 14 => iec_status <= fastio_rdata;
          when 15 => fastio_addr <= x"d3699"; fastio_read <= '1';
          when 16 => null;
          when 17 => iec_data <= fastio_rdata;
          when 18 => fastio_addr <= x"d369a"; fastio_read <= '1';
          when 19 => null;
          when 20 => iec_devinfo <= fastio_rdata;
                    fastio_addr <= x"00000"; fastio_read <= '0';

          when 21 => null;
          when 22 =>
            if do_write = '1' then
              fastio_write <= '1';
              fastio_addr(19 downto 4) <= x"d369";
              fastio_addr(3 downto 0) <= write_reg;
              fastio_wdata <= write_val;
              do_write <= '0';
            end if;

          when others => null;
        end case;          
      end if;                        
            
    end if;


  end process;    
  
end Behavioral;
