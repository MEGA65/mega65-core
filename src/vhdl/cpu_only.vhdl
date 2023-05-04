library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use STD.textio.all;
use work.all;
use work.debugtools.all;
use work.cputypes.all;
use work.victypes.all;

entity cpu_only is

end cpu_only;

architecture simulation_top_level of cpu_only is

  signal mathclock : std_logic;
  signal Clock     : std_logic;
  signal phi_1mhz  : std_logic;
  signal phi_2mhz  : std_logic;
  signal phi_3mhz  : std_logic;

  signal cpu_slow : std_logic := '0';

  signal reset         : std_logic;
  signal reset_out     : std_logic;
  signal irq           : std_logic;
  signal nmi           : std_logic;
  signal exrom         : std_logic;
  signal game          : std_logic;
  signal eth_hyperrupt : std_logic;

  signal all_pause : std_logic;

  signal hyper_trap            : std_logic;
  signal cpu_hypervisor_mode   : std_logic := '0';
  signal privileged_access     : std_logic := '0';
  signal matrix_trap_in        : std_logic;
  signal eth_load_enable       : std_logic;
  signal hyper_trap_f011_read  : std_logic;
  signal hyper_trap_f011_write : std_logic;
  signal protected_hardware    : unsigned(7 downto 0);
  signal virtualised_hardware  : unsigned(7 downto 0);
  signal chipselect_enables    : std_logic_vector(7 downto 0);

  signal iomode_set        : std_logic_vector(1 downto 0) := "11";
  signal iomode_set_toggle : std_logic                    := '0';

  signal dat_bitplane_bank      : unsigned(2 downto 0);
  signal dat_offset             : unsigned(15 downto 0);
  signal dat_even               : std_logic;
  signal dat_bitplane_addresses : sprite_vector_eight;
  signal pixel_frame_toggle     : std_logic;

  signal sid_audio : signed(17 downto 0);

  signal cpuis6502 : std_logic            := '0';
  signal cpuspeed  : unsigned(7 downto 0) := x"01";

  signal power_down : std_logic := '1';

  signal irq_hypervisor : std_logic_vector(2 downto 0) := "000";

  signal secure_mode_out          : std_logic := '0';
  signal secure_mode_from_monitor : std_logic;
  signal clear_matrix_mode_toggle : std_logic;

  signal matrix_rain_seed : unsigned(15 downto 0) := (others => '0');

  signal cpu_pcm_left    : signed(15 downto 0) := x"0000";
  signal cpu_pcm_right   : signed(15 downto 0) := x"0000";
  signal cpu_pcm_enable  : std_logic           := '0';
  signal cpu_pcm_bypass  : std_logic           := '0';
  signal pwm_mode_select : std_logic           := '1';

  signal fast_key : std_logic;

  signal no_hyppo : std_logic;

  signal reg_isr_out  : unsigned(7 downto 0);
  signal imask_ta_out : std_logic;

  signal monitor_char        : unsigned(7 downto 0);
  signal monitor_char_toggle : std_logic;
  signal monitor_char_busy   : std_logic;

  signal monitor_proceed               : std_logic;
  signal monitor_waitstates            : unsigned(7 downto 0);
  signal monitor_request_reflected     : std_logic;
  signal monitor_hypervisor_mode       : std_logic;
  signal monitor_instruction_strobe    : std_logic := '0';
  signal monitor_pc                    : unsigned(15 downto 0);
  signal monitor_state                 : unsigned(15 downto 0);
  signal monitor_instruction           : unsigned(7 downto 0);
  signal monitor_watch                 : unsigned(27 downto 0);
  signal monitor_watch_match           : std_logic;
  signal monitor_instructionpc         : unsigned(15 downto 0);
  signal monitor_opcode                : unsigned(7 downto 0);
  signal monitor_ibytes                : unsigned(3 downto 0);
  signal monitor_arg1                  : unsigned(7 downto 0);
  signal monitor_arg2                  : unsigned(7 downto 0);
  signal monitor_a                     : unsigned(7 downto 0);
  signal monitor_b                     : unsigned(7 downto 0);
  signal monitor_x                     : unsigned(7 downto 0);
  signal monitor_y                     : unsigned(7 downto 0);
  signal monitor_z                     : unsigned(7 downto 0);
  signal monitor_sp                    : unsigned(15 downto 0);
  signal monitor_p                     : unsigned(7 downto 0);
  signal monitor_map_offset_low        : unsigned(11 downto 0);
  signal monitor_map_offset_high       : unsigned(11 downto 0);
  signal monitor_map_enables_low       : unsigned(3 downto 0);
  signal monitor_map_enables_high      : unsigned(3 downto 0);
  signal monitor_interrupt_inhibit     : std_logic;
  signal monitor_memory_access_address : unsigned(31 downto 0);
  signal monitor_cpuport               : unsigned(2 downto 0);

  signal ethernet_cpu_arrest : std_logic;

  signal monitor_mem_address           : unsigned(27 downto 0);
  signal monitor_mem_rdata             : unsigned(7 downto 0);
  signal monitor_mem_wdata             : unsigned(7 downto 0);
  signal monitor_mem_read              : std_logic;
  signal monitor_mem_write             : std_logic;
  signal monitor_mem_setpc             : std_logic;
  signal monitor_mem_attention_request : std_logic;
  signal monitor_mem_attention_granted : std_logic;
  signal monitor_irq_inhibit           : std_logic;
  signal monitor_mem_trace_mode        : std_logic;
  signal monitor_mem_stage_trace_mode  : std_logic;
  signal monitor_mem_trace_toggle      : std_logic;

  signal debug_address_w_dbg_out : std_logic_vector(16 downto 0);
  signal debug_address_r_dbg_out : std_logic_vector(16 downto 0);
  signal debug_rdata_dbg_out     : std_logic_vector(7 downto 0);
  signal debug_wdata_dbg_out     : std_logic_vector(7 downto 0);
  signal debug_write_dbg_out     : std_logic;
  signal debug_read_dbg_out      : std_logic;
  signal debug4_state_out        : std_logic_vector(3 downto 0);

  signal proceed_dbg_out : std_logic;

  signal f_read  : std_logic;
  signal f_write : std_logic := '1';

  signal chipram_we      : std_logic             := '0';
  signal chipram_clk     : std_logic;
  signal chipram_address : unsigned(19 downto 0) := to_unsigned(0, 20);
  signal chipram_dataout : unsigned(7 downto 0);

  signal cpu_leds : std_logic_vector(3 downto 0);

  signal vicii_2mhz        : std_logic;
  signal viciii_fast       : std_logic;
  signal viciv_fast        : std_logic;
  signal iec_bus_active    : std_logic;
  signal speed_gate        : std_logic;
  signal speed_gate_enable : std_logic := '1';
  signal badline_toggle    : std_logic;

  signal fastio_addr       : std_logic_vector(19 downto 0) := (others => '0');
  signal fastio_addr_fast  : std_logic_vector(19 downto 0) := (others => '0');
  signal fastio_read       : std_logic                     := '0';
  signal fastio_write      : std_logic                     := '0';
  signal fastio_wdata      : std_logic_vector(7 downto 0)  := (others => '0');
  signal fastio_rdata      : std_logic_vector(7 downto 0);
  signal hyppo_rdata       : std_logic_vector(7 downto 0);
  signal hyppo_wdata       : std_logic_vector(7 downto 0);
  signal hyppo_rd          : std_logic;
  signal hyppo_wr          : std_logic;
  signal hyppo_address_out : std_logic_vector(13 downto 0);

  signal cia_2mhz          : std_logic;
  signal vicii_roml_access : std_logic;
  signal vicii_romh_access : std_logic;

  signal sid_clock   : std_logic;
  signal sid_enable  : std_logic;
  signal sid_byte    : std_logic_vector(7 downto 0);
  signal sid_address : std_logic_vector(4 downto 0);
  signal sid_rw      : std_logic;
  signal sid_data    : std_logic_vector(7 downto 0);

  signal sdcard_controller_read     : std_logic;
  signal sdcard_controller_write    : std_logic;
  signal sdcard_controller_data_in  : std_logic_vector(7 downto 0);
  signal sdcard_controller_data_out : std_logic_vector(7 downto 0);
  signal sdcard_controller_address  : std_logic_vector(15 downto 0);

  signal ethernet_controller_read     : std_logic;
  signal ethernet_controller_write    : std_logic;
  signal ethernet_controller_data_in  : std_logic_vector(7 downto 0);
  signal ethernet_controller_data_out : std_logic_vector(7 downto 0);
  signal ethernet_controller_address  : std_logic_vector(15 downto 0);

  signal usb_controller_read     : std_logic;
  signal usb_controller_write    : std_logic;
  signal usb_controller_data_in  : std_logic_vector(7 downto 0);
  signal usb_controller_data_out : std_logic_vector(7 downto 0);
  signal usb_controller_address  : std_logic_vector(15 downto 0);

  signal rtc_data    : std_logic_vector(7 downto 0);
  signal rtc_address : std_logic_vector(7 downto 0);
  signal rtc_rw      : std_logic;
  signal rtc_cs      : std_logic;
  signal rtc_clk     : std_logic;

  signal uart_tx_data : std_logic_vector(7 downto 0);
  signal uart_rx_data : std_logic_vector(7 downto 0);
  signal uart_read    : std_logic;
  signal uart_write   : std_logic;
  signal uart_address : std_logic_vector(2 downto 0);

  signal audio_left   : std_logic_vector(15 downto 0);
  signal audio_right  : std_logic_vector(15 downto 0);
  signal audio_enable : std_logic;

  signal system_reset : std_logic;

  signal sector_buffer_mapped       : std_logic                    := '0';
  signal fastio_vic_rdata           : std_logic_vector(7 downto 0) := x"00";
  signal fastio_colour_ram_rdata    : std_logic_vector(7 downto 0) := x"00";
  signal fastio_charrom_rdata       : std_logic_vector(7 downto 0) := x"00";
  signal colour_ram_cs              : std_logic                    := '0';
  signal slow_access_request_toggle : std_logic                    := '0';
  signal slow_access_ready_toggle   : std_logic                    := '0';
  signal slow_access_address        : unsigned(27 downto 0)        := (others => '1');
  signal slow_access_write          : std_logic                    := '0';
  signal slow_access_wdata          : unsigned(7 downto 0)         := x"00";
  signal slow_access_rdata          : unsigned(7 downto 0);

  -- Fast read interface for slow devices linear reading
  -- (presents only the next available byte)
  signal slow_prefetched_request_toggle : std_logic             := '0';
  signal slow_prefetched_data           : unsigned(7 downto 0)  := x"00";
  signal slow_prefetched_address        : unsigned(26 downto 0) := (others => '1');

  -- Interface for lower latency reading from slow RAM
  -- (presents a whole cache line of 8 bytes)
  signal slowram_cache_line            : cache_row_t           := (others => (others => '0'));
  signal slowram_cache_line_valid      : std_logic             := '0';
  signal slowram_cache_line_addr       : unsigned(26 downto 3) := (others => '0');
  signal slowram_cache_line_inc_toggle : std_logic             := '0';
  signal slowram_cache_line_dec_toggle : std_logic             := '0';


  ---------------------------------------------------------------------------
  -- VIC-III memory banking control
  ---------------------------------------------------------------------------
  signal viciii_iomode : std_logic_vector(1 downto 0);

  signal colourram_at_dc00 : std_logic;
  signal rom_at_e000       : std_logic;
  signal rom_at_c000       : std_logic;
  signal rom_at_a000       : std_logic;
  signal rom_at_8000       : std_logic;


begin

  cpu0 : entity work.gs4510
    generic map (
      math_unit_enable => false,
      chipram_1mb      => '0',
      target           => mega65r4
      )
    port map (
      mathclock                     => mathclock,
      Clock                         => Clock,
      phi_1mhz                      => phi_1mhz,
      phi_2mhz                      => phi_2mhz,
      phi_3mhz                      => phi_3mhz,
      cpu_slow                      => cpu_slow,
      reset                         => reset,
      reset_out                     => reset_out,
      irq                           => irq,
      nmi                           => nmi,
      exrom                         => exrom,
      game                          => game,
      eth_hyperrupt                 => eth_hyperrupt,
      all_pause                     => all_pause,
      hyper_trap                    => hyper_trap,
      cpu_hypervisor_mode           => cpu_hypervisor_mode,
      privileged_access             => privileged_access,
      matrix_trap_in                => matrix_trap_in,
      eth_load_enable               => eth_load_enable,
      hyper_trap_f011_read          => hyper_trap_f011_read,
      hyper_trap_f011_write         => hyper_trap_f011_write,
      protected_hardware            => protected_hardware,
      virtualised_hardware          => virtualised_hardware,
      chipselect_enables            => chipselect_enables,
      iomode_set                    => iomode_set,
      iomode_set_toggle             => iomode_set_toggle,
      dat_bitplane_bank             => dat_bitplane_bank,
      dat_offset                    => dat_offset,
      dat_even                      => dat_even,
      dat_bitplane_addresses        => dat_bitplane_addresses,
      pixel_frame_toggle            => pixel_frame_toggle,
      sid_audio                     => sid_audio,
      cpuis6502                     => cpuis6502,
      cpuspeed                      => cpuspeed,
      power_down                    => power_down,
      irq_hypervisor                => irq_hypervisor,
      secure_mode_out               => secure_mode_out,
      secure_mode_from_monitor      => secure_mode_from_monitor,
      clear_matrix_mode_toggle      => clear_matrix_mode_toggle,
      matrix_rain_seed              => matrix_rain_seed,
      cpu_pcm_left                  => cpu_pcm_left,
      cpu_pcm_right                 => cpu_pcm_right,
      cpu_pcm_enable                => cpu_pcm_enable,
      cpu_pcm_bypass                => cpu_pcm_bypass,
      pwm_mode_select               => pwm_mode_select,
      fast_key                      => fast_key,
      no_hyppo                      => no_hyppo,
      reg_isr_out                   => reg_isr_out,
      imask_ta_out                  => imask_ta_out,
      monitor_char                  => monitor_char,
      monitor_char_toggle           => monitor_char_toggle,
      monitor_char_busy             => monitor_char_busy,
      monitor_proceed               => monitor_proceed,
      monitor_waitstates            => monitor_waitstates,
      monitor_request_reflected     => monitor_request_reflected,
      monitor_hypervisor_mode       => monitor_hypervisor_mode,
      monitor_instruction_strobe    => monitor_instruction_strobe,
      monitor_pc                    => monitor_pc,
      monitor_state                 => monitor_state,
      monitor_instruction           => monitor_instruction,
      monitor_watch                 => monitor_watch,
      monitor_watch_match           => monitor_watch_match,
      monitor_instructionpc         => monitor_instructionpc,
      monitor_opcode                => monitor_opcode,
      monitor_ibytes                => monitor_ibytes,
      monitor_arg1                  => monitor_arg1,
      monitor_arg2                  => monitor_arg2,
      monitor_a                     => monitor_a,
      monitor_b                     => monitor_b,
      monitor_x                     => monitor_x,
      monitor_y                     => monitor_y,
      monitor_z                     => monitor_z,
      monitor_sp                    => monitor_sp,
      monitor_p                     => monitor_p,
      monitor_map_offset_low        => monitor_map_offset_low,
      monitor_map_offset_high       => monitor_map_offset_high,
      monitor_map_enables_low       => monitor_map_enables_low,
      monitor_map_enables_high      => monitor_map_enables_high,
      monitor_interrupt_inhibit     => monitor_interrupt_inhibit,
      monitor_memory_access_address => monitor_memory_access_address,
      monitor_cpuport               => monitor_cpuport,
      ethernet_cpu_arrest           => ethernet_cpu_arrest,

      monitor_mem_address           => monitor_mem_address,
      monitor_mem_rdata             => monitor_mem_rdata,
      monitor_mem_wdata             => monitor_mem_wdata,
      monitor_mem_read              => monitor_mem_read,
      monitor_mem_write             => monitor_mem_write,
      monitor_mem_setpc             => monitor_mem_setpc,
      monitor_mem_attention_request => monitor_mem_attention_request,
      monitor_mem_attention_granted => monitor_mem_attention_granted,
      monitor_irq_inhibit           => monitor_irq_inhibit,
      monitor_mem_trace_mode        => monitor_mem_trace_mode,
      monitor_mem_stage_trace_mode  => monitor_mem_stage_trace_mode,
      monitor_mem_trace_toggle      => monitor_mem_trace_toggle,

      debug_address_w_dbg_out => debug_address_w_dbg_out,
      debug_address_r_dbg_out => debug_address_r_dbg_out,
      debug_rdata_dbg_out     => debug_rdata_dbg_out,
      debug_wdata_dbg_out     => debug_wdata_dbg_out,
      debug_write_dbg_out     => debug_write_dbg_out,
      debug_read_dbg_out      => debug_read_dbg_out,
      debug4_state_out        => debug4_state_out,

      proceed_dbg_out => proceed_dbg_out,

      f_read  => f_read,
      f_write => f_write,

      chipram_we                     => chipram_we,
      chipram_clk                    => chipram_clk,
      chipram_address                => chipram_address,
      chipram_dataout                => chipram_dataout,
      cpu_leds                       => cpu_leds,
      vicii_2mhz                     => vicii_2mhz,
      viciii_fast                    => viciii_fast,
      viciv_fast                     => viciv_fast,
      iec_bus_active                 => iec_bus_active,
      speed_gate                     => speed_gate,
      speed_gate_enable              => speed_gate_enable,
      badline_toggle                 => badline_toggle,
      fastio_addr                    => fastio_addr,
      fastio_addr_fast               => fastio_addr_fast,
      fastio_read                    => fastio_read,
      fastio_write                   => fastio_write,
      fastio_wdata                   => fastio_wdata,
      fastio_rdata                   => fastio_rdata,
      hyppo_rdata                    => hyppo_rdata,
      hyppo_address_out              => hyppo_address_out,
      sector_buffer_mapped           => sector_buffer_mapped,
      fastio_vic_rdata               => fastio_vic_rdata,
      fastio_colour_ram_rdata        => fastio_colour_ram_rdata,
      fastio_charrom_rdata           => fastio_charrom_rdata,
      colour_ram_cs                  => colour_ram_cs,
      slow_access_request_toggle     => slow_access_request_toggle,
      slow_access_ready_toggle       => slow_access_ready_toggle,
      slow_access_address            => slow_access_address,
      slow_access_write              => slow_access_write,
      slow_access_wdata              => slow_access_wdata,
      slow_access_rdata              => slow_access_rdata,
      slow_prefetched_request_toggle => slow_prefetched_request_toggle,
      slow_prefetched_data           => slow_prefetched_data,
      slow_prefetched_address        => slow_prefetched_address,
      slowram_cache_line             => slowram_cache_line,
      slowram_cache_line_valid       => slowram_cache_line_valid,
      slowram_cache_line_addr        => slowram_cache_line_addr,
      slowram_cache_line_inc_toggle  => slowram_cache_line_inc_toggle,
      slowram_cache_line_dec_toggle  => slowram_cache_line_dec_toggle,
      viciii_iomode                  => viciii_iomode,
      colourram_at_dc00              => colourram_at_dc00,
      rom_at_e000                    => rom_at_e000,
      rom_at_c000                    => rom_at_c000,
      rom_at_a000                    => rom_at_a000,
      rom_at_8000                    => rom_at_8000
      );

end simulation_top_level;
