use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;
use work.victypes.all;

entity internal1581 is
  port (
    clock : in std_logic;

    -- CPU side interface to read/write both the 32KB drive "ROM" and the 8KB
    -- drive RAM.
    fastio_read : in std_logic;
    fastio_write : in std_logic;
    fastio_address : in unsigned(19 downto 0);
    fastio_wdata : in unsigned(7 downto 0);
    fastio_rdata : out unsigned(7 downto 0);
    cs_driverom : in std_logic;
    cs_driveram : in std_logic;

    address_next : out unsigned(15 downto 0);

    -- Device ID straps: 00 = 8, 11 = 11 (of course ;)
    device_id_straps : in unsigned(1 downto 0) := "00";

    last_rx_byte : out unsigned(7 downto 0);
  
    -- Drive CPU clock strobes.
    -- This allows us to accelerate the 1581 at the same ratio as the CPU,
    -- so that fast loaders can be accelerated.
    drive_clock_cycle_strobe : in std_logic;
    -- Assert low to hold the drive CPU under reset
    drive_reset_n : in std_logic;
    -- Assert when the drive should be fully suspended
    -- (for freezing / resuming )
    drive_suspend : in std_logic;

    -- IEC interface
    iec_atn_i : in std_logic;
    iec_clk_i : in std_logic;
    iec_data_i : in std_logic;
    iec_srq_i : in std_logic;
    -- outputs are in voltage sense, i.e., 1 = 5V, 0 = 0V
    iec_clk_o : out std_logic := '1';
    iec_data_o : out std_logic := '1';
    iec_srq_o : out std_logic := '1';

    silence_internal_drive : in std_logic := '0';
    
    -- Interface to SD card data feed
    -- Here we read non-GCR bytes and turn them to GCR.
    -- We thus have a current byte, and then ask for the next when we will need
    -- it.  We also need to tell the SD controller which track we are on, so that
    -- it can feed the correct data to us.  If the SD card is not ready, then
    -- we keep feeding pretending to feed gap bytes.
    sd_data_byte : in unsigned(7 downto 0);
    sd_data_ready_toggle : in std_logic;
    sd_data_request_toggle : out std_logic := '0';
    sd_1581_enable : out std_logic := '0'; -- data flows only when enabled,
                                           -- i.e., when we think the motor is
                                           -- on
    sd_1581_track : out unsigned(5 downto 0) := to_unsigned(18,6)

    );
end entity internal1581;

architecture romanesque_revival of internal1581 is

  signal phi_2_1mhz_counter : integer := 0;

  -- signals here
  signal address : unsigned(15 downto 0) := x"0000";
  signal rdata : unsigned(7 downto 0);
  signal wdata : unsigned(7 downto 0);
  signal ram_write_enable : std_logic := '0';

  signal nmi : std_logic := '1';
  signal irq : std_logic := '1';

  signal cpu_write_n : std_logic := '1';

  -- Internal CS lines for the 1581
  signal cs_ram : std_logic;
  signal cs_rom : std_logic;
  signal cs_cia : std_logic;
  signal cs_fdc : std_logic;

  signal ram_rdata : unsigned(7 downto 0);
  signal rom_rdata : unsigned(7 downto 0);

  signal address_next_internal : unsigned(15 downto 0);

  signal cia_address : unsigned(3 downto 0) := to_unsigned(0,4);
  signal cia_data_in : unsigned(7 downto 0) := to_unsigned(0,8);
  signal cia_data_out : unsigned(7 downto 0);
  signal cia_data_out_en_n : std_logic := '1';
  signal cia_irq_n : std_logic;
  signal cia_flag_in : std_logic;
  signal cia_spout : std_logic;
  signal cia_spin : std_logic;
  signal cia_countin : std_logic;
  signal cia_countout : std_logic;
  signal cia_porta_in : std_logic_vector(7 downto 0) := (others => '1');
  signal cia_porta_out : std_logic_vector(7 downto 0);
  signal cia_porta_out_en_n : std_logic_vector(7 downto 0);
  signal cia_portb_in : std_logic_vector(7 downto 0) := (others => '1');
  signal cia_portb_out : std_logic_vector(7 downto 0);
  signal cia_portb_out_en_n : std_logic_vector(7 downto 0);

  signal cia_phase2_clock : std_logic := '0';
  
  signal fast_serial_direction : std_logic;
  signal atn_ack : std_logic;

  signal last_address : unsigned(15 downto 0) := to_unsigned(0,16);
  signal report_read : std_logic := '0';
  
begin

  ram: entity work.dpram8x8192 generic map (
    SIZE => 8192,
    ADDR_WIDTH => 13
    )
    port map (
    -- Fastio interface
    clka => clock,
    ena => cs_driveram, -- host CPU side
    wea(0) => fastio_write,
    addra => std_logic_vector(fastio_address(12 downto 0)),
    dina => std_logic_vector(fastio_wdata),
    unsigned(douta) => fastio_rdata,

    enb => cs_ram,  -- 1581 CPU side
    clkb => clock,
    web(0) => ram_write_enable,
    addrb => std_logic_vector(address(12 downto 0)),
    dinb => std_logic_vector(wdata),
    unsigned(doutb) => ram_rdata,

    silence_internal_drive => silence_internal_drive
    );

  rom: entity work.driverom1581 port map (
    -- Fast IO interface
    clka => clock,
    csa => cs_driverom,
    addressa => to_integer(fastio_address(14 downto 0)),
    wea => fastio_write,
    dia => fastio_wdata,
    doa => fastio_rdata,

    -- CPU interface
    clkb => clock,
    addressb => to_integer(address(14 downto 0)),
    dob => rom_rdata
    );

  cia: entity work.cia6526
    generic map (
      unit => x"8"
      )
    port map (
    cpuclock => clock,
    phi0_1mhz => cia_phase2_clock,
    todclock => cia_phase2_clock,
    reset => drive_reset_n,
    irq => cia_irq_n,

    cpu_slow => '0',  -- dont perform any CIA write delay compensation for fast CPUs

    hypervisor_mode => '0',

    cs => cs_cia,
    fastio_address => address(7 downto 0),
    fastio_write => not cpu_write_n,
    fastio_wdata => wdata,
    fastio_rdata => cia_data_out,

    portaddr => cia_porta_out_en_n,
    portaout => cia_porta_out,
    portain => cia_porta_in,

    portbddr => cia_portb_out_en_n,
    portbout => cia_portb_out,
    portbin => cia_portb_in,

    flagin => cia_flag_in,
--    pcout => cia_pcout,
    spout => cia_spout,
    spin => cia_spin,

    countout => cia_countout,
    countin => cia_countin
    );
  
  cpu: entity work.cpu6502 port map (
    clk => clock,
    reset => drive_reset_n,
    nmi => nmi,
    irq => irq,
    ready => drive_clock_cycle_strobe,
    write_n => cpu_write_n,
--    sync => cpu_sync,
    address => address,
    address_next => address_next_internal,
    data_i => rdata,
    data_o => wdata,

    silence_internal_drive => silence_internal_drive
    );

  process(clock,address,address_next_internal,cs_ram,ram_rdata,cs_rom,rom_rdata,cia_data_out,cpu_write_n)
  begin

    ram_write_enable <= not cpu_write_n;

    if rising_edge(clock) then

      if address = x"0076" and ram_write_enable='1' then
        report "1581: FSFLAGS writing $" & to_hexstring(wdata);
      end if;
      
      -- Generate exactly 2MHz strobes for the CIA
      if phi_2_1mhz_counter < (405 - 20) then
        phi_2_1mhz_counter <= phi_2_1mhz_counter + 20;
        cia_phase2_clock <= '0';
      else
        phi_2_1mhz_counter <= phi_2_1mhz_counter + 20 - 405;
        cia_phase2_clock <= '1';
        -- report "MOS6502: 2MHz tick";
      end if;

      irq <= cia_irq_n; -- and fdc_irq_n;

      -- cia_porta_out(0) => f_side0;
      -- cia_porta_out(1) <= f_ready_n;
      -- cia_porta_out(2) => f_motor_n;
      cia_porta_in(4 downto 3) <= std_logic_vector(device_id_straps);
      -- cia_porta_in(4) => f_side0;
      -- cia_porta_out(5) => power_led;
      -- cia_porta_out(6) => drive_activity_led;
      -- cia_porta_in(7) <= f_disk_change_n;
      
      cia_portb_in(0) <= not iec_data_i;
      -- cia_portb_out(1) == iec_data_o (see below)
      cia_portb_in(2) <= not iec_clk_i;
      -- cia_portb_out(3) == iec_clk_o (see below)
      cia_portb_out(4) <= atn_ack;
      cia_portb_out(5) <= fast_serial_direction;
      cia_portb_in(6) <= '1'; -- f_write_protect_n
      cia_portb_in(7) <= not iec_atn_i;
      cia_flag_in <= iec_atn_i;

      iec_data_o <= '0';
      if cia_portb_out(1) = '0' and cia_portb_out_en_n(1)='1' then
        -- Implement U7 NAND gate that also allows DATA to be pulled low by
        -- ATN_ACK line.
        if atn_ack /= '1' or iec_atn_i /= '1' or silence_internal_drive='1' then
          iec_data_o <= '1';
        end if;
      end if;
      

      iec_clk_o <= '0';
      if cia_portb_out(3) = '0' and cia_portb_out_en_n(3)='1' then
        iec_clk_o <= '1';
      end if;

      cia_spin <= iec_srq_i;
      iec_srq_o <= '1';
      if cia_spout = '0' and fast_serial_direction='1' then
        iec_srq_o <= '0';
      end if;
      
    end if;

    address_next <= address_next_internal;

    -- Decode ROM, RAM and IO addresses
    if address(15)='1' then
      -- ROM is repeated twice at $8000 and $C000
      cs_rom <= '1'; cs_ram <= '0'; cs_cia <= '0'; cs_fdc <= '0';
      -- report "1581: Accessing ROM address $" & to_hexstring(address);
    else
      cs_rom <= '0'; cs_ram <= '0'; cs_cia <= '0'; cs_fdc <= '0';
      case address(15 downto 12) is
        when x"0" | x"1" => cs_ram <= '1'; -- $0000-$1FFF = 8KB RAM
          -- report "1581: Accessing RAM address $" & to_hexstring(address) & ", wdata=$" & to_hexstring(fastio_wdata)
          -- & ", write_n=" & std_logic'image(cpu_write_n);
        when x"4" => cs_cia <='1'; -- $400x = 8520A CIA
        when x"6" => cs_fdc <='1'; -- $600x = WDC 1770 FDC
                     if cpu_write_n='1' then
                       report "1581FDC: Reading FDC register $" & to_hexstring(address);
                     else
                       report "1581FDC: Writing FDC register $" & to_hexstring(address) & " <- wdata=$" & to_hexstring(fastio_wdata);
                     end if;
        when others => null;
      end case;

      -- Export last byte written to 1581 RX byte location to support automated
      -- tests of IEC communications in tb_iec_serial.vhdl
      -- Also report 
      report_read <= '0';
      last_address <= address;
      if last_address /= address or cpu_write_n='0' then
        if address = x"0054" and cpu_write_n='0' then
          last_rx_byte <= wdata;
          report "1581DOS: Setting last RX byte to $" & to_hexstring(wdata);
        end if;
        if address = x"0051" and cpu_write_n='0' then
          report "1581DOS: Setting EOI byte to $" & to_hexstring(wdata);
        end if;
        if address = x"0051" and cpu_write_n='1' then
          report_read <= '1';
        end if;
      end if;
      if report_read='1' and cpu_write_n='1' then
        report "1581DOS: Reading EOI byte value $" & to_hexstring(rdata);
      end if;
      
    end if;

    if cs_ram='1' then
      rdata <= ram_rdata;
    elsif cs_rom='1' then
      rdata <= rom_rdata;
    elsif cs_cia='1' then
      rdata <= cia_data_out;
    elsif cs_fdc='1' then
      -- rdata <= fdc_data_out;
      report "1581: Trying to read from FDC";
      rdata <= (others => '1');
    else
      rdata <= (others => '0'); -- This avoids a latch
    end if;

  end process;

end romanesque_revival;
