use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

ENTITY slow_devices IS
  generic (
    has_quad_flash : std_logic := '0';
    has_psram : std_logic := '0';
    has_hyperram : std_logic := '0';
    has_c64_cartridge_port : std_logic := '0';
    has_fakecartridge : std_logic := '0';
    target : mega65_target_t := mega65r1
    );
  PORT (
    ------------------------------------------------------------------------
    -- CPU side interface
    ------------------------------------------------------------------------
    pixelclock : in std_logic;
    cpuclock : in std_logic;
    reset : in std_logic;
    cpu_exrom : out std_logic;
    cpu_game : out std_logic;
    sector_buffer_mapped : in std_logic;

    irq_out : out std_logic := '1';
    nmi_out : out std_logic := '1';
    dma_out : out std_logic := '1';

    pin_number : out integer := 255;

    slow_access_request_toggle : in std_logic;
    slow_access_ready_toggle : out std_logic := '0';
    slow_access_write : in std_logic;
    slow_access_address : in unsigned(27 downto 0);
    slow_access_wdata : in unsigned(7 downto 0);
    slow_access_rdata : out unsigned(7 downto 0);

    -- Fast read interface for slow devices linear reading
    -- (only hyperram)
    slow_prefetched_request_toggle : in std_logic := '0';
    slow_prefetched_data : out unsigned(7 downto 0) := x"00";
    slow_prefetched_address : buffer unsigned(26 downto 0) := (others => '1');

    -- Indicate if expansion port is busy with access
    cart_busy : out std_logic;
    cart_access_count : out unsigned(7 downto 0);

    fm_left : out signed(15 downto 0);
    fm_right : out signed(15 downto 0);

    ------------------------------------------------------------------------
    -- Expansion RAM (upto 128MB)
    ------------------------------------------------------------------------
    expansionram_read : out std_logic := '0';
    expansionram_write : out std_logic := '0';
    expansionram_rdata : in unsigned(7 downto 0) := x"FF";
    expansionram_wdata : out unsigned(7 downto 0) := x"FF";
    expansionram_address : out unsigned(26 downto 0);
    expansionram_data_ready_toggle : in std_logic := '0';
    expansionram_busy : in std_logic;

    -- Improve read speed by saving us from having to even enquire of
    -- the HyperRAM controller for the most recently accessed cache line.
    expansionram_current_cache_line : in cache_row_t := (others => (others => '0'));
    expansionram_current_cache_line_address : in unsigned(26 downto 3) := (others => '0');
    expansionram_current_cache_line_valid : in std_logic := '0';
    expansionram_current_cache_line_next_toggle : buffer std_logic := '0';


    ----------------------------------------------------------------------
    -- Flash RAM for holding FPGA config
    ----------------------------------------------------------------------
    QspiSCK : out std_logic := '1';
    QspiDB : inout unsigned(3 downto 0) := (others => 'H');
    QspiCSn : out std_logic := '1';

    ------------------------------------------------------------------------
    -- 3rd and 4th joystick ports
    ------------------------------------------------------------------------
    joya : out std_logic_vector(4 downto 0) := "11111";
    joyb : out std_logic_vector(4 downto 0) := "11111";

    ------------------------------------------------------------------------
    -- C64-compatible cartridge/expansion port
    ------------------------------------------------------------------------
    cart_ctrl_dir : out std_logic;
    cart_haddr_dir : out std_logic;
    cart_laddr_dir : out std_logic;
    cart_data_dir : out std_logic;
    cart_data_en : out std_logic;
    cart_addr_en : out std_logic;

    cart_phi2 : out std_logic := 'H';
    cart_dotclock : out std_logic := 'H';
    cart_reset : out std_logic := 'H';

    cart_nmi : in std_logic;
    cart_irq : in std_logic;
    cart_dma : in std_logic;

    cart_exrom : in std_logic;
    cart_ba : inout std_logic := 'H';
    cart_rw : inout std_logic := 'H';
    cart_roml : inout std_logic := 'H';
    cart_romh : inout std_logic := 'H';
    cart_io1 : inout std_logic := 'H';
    cart_game : in std_logic;
    cart_io2 : inout std_logic := 'H';

    cart_d_in : in unsigned(7 downto 0);
    cart_d : out unsigned(7 downto 0);
    cart_a : inout unsigned(15 downto 0)
    );
end slow_devices;

architecture behavioural of slow_devices is

  -- OPL2/3 FM synthesiser
  component opl2 is port (
    clk : in std_logic;
    reset : in std_logic;
    opl2_we : in std_logic;
    opl2_data : in unsigned(7 downto 0);
    opl2_adr : in unsigned(7 downto 0);
    kon : out std_logic_vector(8 downto 0);
    channel_a : out signed(15 downto 0);
    channel_b : out signed(15 downto 0);
    sample_clk : out std_logic;
    sample_clk_128 : out std_logic
    );
  end component;

  signal reset_inverted : std_logic;
  signal sfx_emulation : std_logic := '0';
  signal sfx_opl_adr : unsigned(7 downto 0) := x"00";

  signal last_slow_prefetched_request_toggle : std_logic := '0';

  signal cart_access_request : std_logic := '0';
  signal cart_access_read : std_logic := '1';
  signal cart_access_address : unsigned(31 downto 0) := (others => '1');
  signal cart_access_rdata : unsigned(7 downto 0);
  signal cart_access_wdata : unsigned(7 downto 0) := (others => '1');
  signal cart_access_accept_strobe : std_logic;
  signal cart_access_read_strobe : std_logic;

  signal slow_access_last_request_toggle : std_logic := '0';

  signal expansionram_eternally_busy : std_logic := '1';
  signal expansionram_read_timeout : unsigned(23 downto 0) := to_unsigned(0,24);

  type slow_state is (
    Idle,
    OPL2Request,
    OPL2Read,
    ExpansionRAMRequest,
    ExpansionRAMReadWait,
    CartridgePortRequest,
    CartridgePortAcceptWait
    );

  signal state : slow_state := Idle;

  signal last_expansionram_write_address : unsigned(27 downto 0) := (others => '1');
  signal last_expansionram_write_data : unsigned(7 downto 0) := x"00";
  signal last_expansionram_data_ready_toggle : std_logic := '0';
  signal last_expansionram_data_ready_toggle_sample : std_logic := '0';

  signal opl_we : std_logic := '0';
  signal opl_data : unsigned(7 downto 0) := x"00";
  signal opl_adr : unsigned(7 downto 0) := x"00";
  signal opl_kon : std_logic_vector(8 downto 0);
  signal opl_sc : std_logic;
  signal opl_sc_128 : std_logic;



begin

  opl2fm0: entity work.opl2
    port map (
      clk => cpuclock,
      reset => reset_inverted,
      opl2_we => opl_we,
      opl2_data => opl_data,
      opl2_adr => opl_adr,
      sample_clk => opl_sc,
      sample_clk_128 => opl_sc_128,
      kon => opl_kon,
      channel_a => fm_left,
      channel_b => fm_right
      );

  cartport0: entity work.expansion_port_controller
    generic map ( pixelclock_frequency => 80,
                  target => target
                  )
    port map (
    cpuclock => cpuclock,
    pixelclock => pixelclock,
    reset => reset,
    cpu_game => cpu_game,
    cpu_exrom => cpu_exrom,
    sector_buffer_mapped => sector_buffer_mapped,
    joya => joya,
    joyb => joyb,

    cart_access_request => cart_access_request,
    cart_access_read => cart_access_read,
    cart_access_address => cart_access_address,
    cart_access_rdata => cart_access_rdata,
    cart_access_wdata => cart_access_wdata,
    cart_access_accept_strobe => cart_access_accept_strobe,
    cart_access_read_strobe => cart_access_read_strobe,

    cart_ctrl_dir => cart_ctrl_dir,
    cart_haddr_dir => cart_haddr_dir,
    cart_laddr_dir => cart_laddr_dir,
    cart_data_dir => cart_data_dir,
    cart_data_en => cart_data_en,
    cart_addr_en => cart_addr_en,
    cart_phi2 => cart_phi2,
    cart_dotclock => cart_dotclock,
    cart_reset => cart_reset,

    cart_busy => cart_busy,
    cart_access_count => cart_access_count,

    cart_nmi => cart_nmi,
    cart_irq => cart_irq,
    cart_dma => cart_dma,

    irq_out => irq_out,
    nmi_out => nmi_out,
    dma_out => dma_out,

    cart_exrom => cart_exrom,
    cart_ba => cart_ba,
    cart_rw => cart_rw,
    cart_roml => cart_roml,
    cart_romh => cart_romh,
    cart_io1 => cart_io1,
    cart_game => cart_game,
    cart_io2 => cart_io2,

    cart_d => cart_d,
    cart_d_in => cart_d_in,
    cart_a => cart_a
    );

  generate_fake_cartridge:
  if has_fakecartridge='1' generate

  end generate;


  process (pixelclock,reset)
    function cond_uint(c: boolean; t, f: unsigned)
      return unsigned is
    begin
      if c then
        return t;
      else
        return f;
      end if;
    end function;

    -- TODO: better determine timeout at runtime, depending if hyperram is activated (mega65r4: switchable sdram/hyperram?)
    constant expansionram_read_timeout_default : unsigned := cond_uint((target = mega65r4) or (target = mega65r5) or (target = mega65r6), to_unsigned(128,24), to_unsigned(128, 24));

  begin

    reset_inverted <= not reset;

    if rising_edge(pixelclock) then

      last_expansionram_data_ready_toggle <= expansionram_data_ready_toggle;

      if state /= Idle then
        if expansionram_read_timeout /= to_unsigned(0,24) then
          report "EXRAM-TIMEOUT: Decrementing timeout to " & integer'image(to_integer(expansionram_read_timeout) - 1)
            & ", exram_ready_toggle=" & std_logic'image(expansionram_data_ready_toggle);
          expansionram_read_timeout <= expansionram_read_timeout - 1;
        else
          -- Time out if stuck for too long
          report "EXRAM-TIMEOUT: Timeout occurred. Resorting to IDLE state ";
          state <= Idle;
          -- XXX Debug reading from HyperRAM
          slow_access_rdata(5 downto 0) <= expansionram_rdata(5 downto 0);
          slow_access_rdata(6) <= expansionram_busy;
          slow_access_rdata(7) <= expansionram_data_ready_toggle;
          report "PUBLISH: HyperRAM timeout debug read";
          slow_access_ready_toggle <= slow_access_request_toggle;
        end if;
      end if;

      if slow_prefetched_request_toggle /= last_slow_prefetched_request_toggle then
        report "PREFETCH: slow_prefetched_request_toggle toggled";
        last_slow_prefetched_request_toggle <= slow_prefetched_request_toggle;
        if slow_prefetched_address(2 downto 0) /= "111" then
          -- Present the NEXT byte via the fast interface to the CPU
          report "PREFETCH: Presenting $" & to_hexstring(slow_prefetched_address(26 downto 0) + 1)
            & " = $" & to_hexstring(expansionram_current_cache_line(to_integer(slow_prefetched_address(2 downto 0))+1))
            & " due to CPU request toggle";
          slow_prefetched_address <= slow_prefetched_address(26 downto 0) + 1;
          slow_prefetched_data <= expansionram_current_cache_line(to_integer(slow_prefetched_address(2 downto 0))+1);
        else
          -- Now we would really like to be able to tell the hyperram
          -- controller to give us the next data row
          expansionram_current_cache_line_next_toggle <= not expansionram_current_cache_line_next_toggle;
        end if;
      end if;

      -- Mark expansion RAM as present if the busy flag ever clears
      if expansionram_busy='0' then
        expansionram_eternally_busy <= '0';
      end if;

      report "State = " & slow_state'image(state) & " expansionram_data_ready_toggle = "
        & std_logic'image(expansionram_data_ready_toggle)
        & ", expansionram_busy = " & std_logic'image(expansionram_busy);
      case state is
        when Idle =>
          -- Clear flags for expansion RAM access request
          report "Clearing expansionram_read/write in Idle";
          expansionram_read <= '0';
          expansionram_write <= '0';

          if slow_access_last_request_toggle /= slow_access_request_toggle then
            if slow_access_write='1' then
              report "SLOWWRITE request for $" & to_hexstring(slow_access_address)
                & " <= $" & to_hexstring(slow_access_wdata)
                & ", toggle=" & std_logic'image(slow_access_request_toggle);
            else
              report "SLOWREAD request for $" & to_hexstring(slow_access_address) & ", toggle=" & std_logic'image(slow_access_request_toggle);
            end if;
            -- XXX do job, and acknowledge when done.

            -- CPU maps expansion port access to $7FF0000-$7FFFFFF for
          -- C64-compatible addressing.  In particular, I/O areas 1 and 2 map
          -- to $7FFDE00-$7FFDFFF, and external SIDs, when enabled, are expected
          -- at $7FFD400-$7FFD4FF.  The I/O expansion areas use the normal
          -- I/O1&2 select signals.
          -- (Any othe peripherals that we want to have show up in the
          --  $DExx/$DFxx IO spaces we should do here.  This is one reason why
          --  the OPL2/3 chip is in slow_devices, and not via iomapper.vhdl.)
          --
          -- $4000000-$7EFFFFF (= 63MB) is mapped by default to MEGAcart content.
          -- $8000000-$FEFFFFF (=126MB) is mapped by default to expansion RAM.
          --
          -- For the external SIDs, we don't have that
          -- luxury. We would like the external SID cartridge to be safe to use
          -- in a real C64, so we probably shouldn't just have the external
          -- SIDs listen to $D400-$D4FF without some kind of signalling.  However,
          -- if we just present $D4xx and have I/O1 or I/O2 asserted, then normal
          -- I/O expansion cartridges will map whatever their I/O is there, instead
          -- of being selective.  That's not a big problem, provided that we
          -- have a way to definitively detect the SID cartridge. This could be
          -- done by trying to read some other I/O to confirm that the SIDs are
          -- only visible at $D4xx, and not $DExx.
          --
          -- All we have to do is direct access requests based on whether they
          -- are handled by the cartridge/expansion port, or by on-board
          -- expansion RAM of some sort.

            -- XXX - DEBUG: Also pick which pin to drive a pulse train on
            pin_number <= to_integer(slow_access_wdata);

          if slow_access_address = x"7FEFFFF" then
            -- @IO:GS $7FEFFFF.0 Enable/disable SFX cartridge emulation
            if slow_access_write='1' then
              sfx_emulation <= slow_access_wdata(0);
            end if;
            slow_access_rdata(0) <= sfx_emulation;
            slow_access_rdata(1) <= opl_sc;
            slow_access_rdata(2) <= opl_sc_128;
            slow_access_rdata(7 downto 3) <= (others => '0');
            slow_access_ready_toggle <= slow_access_request_toggle;
            report "PUBLISH: $7FEFFFF read";
            state <= Idle;
          elsif slow_access_address = x"7FFDF40" and sfx_emulation='1' then
            sfx_opl_adr <= slow_access_wdata;
            slow_access_ready_toggle <= slow_access_request_toggle;
            report "PUBLISH: $7FFDF40 read";
            slow_access_rdata <= sfx_opl_adr;
            state <= Idle;
          elsif slow_access_address = x"7FFDF50" and sfx_emulation='1' then
            opl_adr <= sfx_opl_adr;
            opl_we <= slow_access_write;
            opl_data <= slow_access_wdata;
            report "PUBLISH: $7FFDF50 read";
            slow_access_ready_toggle <= slow_access_request_toggle;
            state <= OPL2Request;
          elsif slow_access_address = x"7FFDF60" and sfx_emulation='1' then
            slow_access_rdata <= unsigned(opl_kon(7 downto 0));
            slow_access_ready_toggle <= slow_access_request_toggle;
            report "PUBLISH: $7FFDF60 read";
            state <= Idle;
          elsif slow_access_address(27 downto 20) = x"FE" then
            -- $FExxxxx = Slow IO peripherals
            -- $FE000xx = OPL2/3 FM synthesiser
            if slow_access_address(19 downto 8) = x"000" then
              opl_adr <= slow_access_address(7 downto 0);
              opl_we <= slow_access_write;
              opl_data <= slow_access_wdata;
              if (slow_access_address(0)='0') then
                slow_access_rdata <= unsigned(opl_kon(7 downto 0));
              else
                slow_access_rdata(7 downto 1) <= (others => '1');
                slow_access_rdata(0) <= opl_kon(8);
              end if;
              report "PUBLISH: OPL2 read";
              slow_access_ready_toggle <= slow_access_request_toggle;
              state <= OPL2Request;
            else
              report "PUBLISH: Slow IO peripheral read";
              slow_access_ready_toggle <= slow_access_request_toggle;
              state <= Idle;
            end if;
          elsif slow_access_address(27 downto 8) = x"f0000" then
            slow_access_rdata <= x"00";
            if slow_access_address(7 downto 0) = x"00" then
              slow_access_rdata(2) <= last_expansionram_data_ready_toggle_sample;
              slow_access_rdata(1) <= last_expansionram_data_ready_toggle;
              slow_access_rdata(0) <= expansionram_data_ready_toggle;
            end if;
            if slow_access_address(7 downto 0) = x"01" then
              slow_access_rdata <= expansionram_rdata;
            end if;
            state <= Idle;
            report "PUBLISH: Debug expansion RAM ready toggle";
            slow_access_ready_toggle <= slow_access_request_toggle;

          elsif slow_access_address(27)='1' then
            -- $8000000-$FFFFFFF = expansion RAM
            report "Triaging Expansion RAM request to address $" & to_hexstring(slow_access_address);
            report "cachecs: address=$" & to_hexstring(expansionram_current_cache_line_address&"000")
              & ", valid=" & std_logic'image(expansionram_current_cache_line_valid)
              & ", data = "
              & to_hexstring(expansionram_current_cache_line(0)) & " "
              & to_hexstring(expansionram_current_cache_line(1)) & " "
              & to_hexstring(expansionram_current_cache_line(2)) & " "
              & to_hexstring(expansionram_current_cache_line(3)) & " "
              & to_hexstring(expansionram_current_cache_line(4)) & " "
              & to_hexstring(expansionram_current_cache_line(5)) & " "
              & to_hexstring(expansionram_current_cache_line(6)) & " "
              & to_hexstring(expansionram_current_cache_line(7)) & " ";
            if expansionram_current_cache_line_valid='1' and
              expansionram_current_cache_line_address(26 downto 3) = slow_access_address(26 downto 3) and
              slow_access_write='0'
            then
              -- Read request for expansion RAM that can be serviced using the
              -- exported cache line.

              -- If we do a write to a region already in the current cache
              -- line, we process it so quickly, that the value doesn't have
              -- time to be updated. Thus we need to keep it on hand, return
              -- the new value ourselves.
              report "CACHE: slow_access_address = $" & to_hexstring(slow_access_address)
                & ", last write addr $" & to_hexstring(last_expansionram_write_address);
              if slow_access_address = last_expansionram_write_address then
                report "CACHE: Reading last-written byte $" & to_hexstring(last_expansionram_write_data);
                slow_access_rdata <= last_expansionram_write_data;
              else
                report "CACHE: Reading byte $" & to_hexstring(expansionram_current_cache_line(to_integer(slow_access_address(2 downto 0))))
                  & " from exposed hyperram current cache line";
                slow_access_rdata <= expansionram_current_cache_line(to_integer(slow_access_address(2 downto 0)));
              end if;
              state <= Idle;

              report "PUBLISH: expansionram_current_cache_line read";
              slow_access_ready_toggle <= slow_access_request_toggle;
              -- If we are reading the last byte in the set we have, then tell
              -- hyperram controller to present the next data, if possible.
              if slow_access_address(2 downto 0) = "111" then
--                report "DISPATCHER: Requesting next 8 bytes";
                expansionram_current_cache_line_next_toggle <= not expansionram_current_cache_line_next_toggle;
              end if;

              if slow_access_address(2 downto 0) /= "111" then
                -- Present the NEXT byte via the fast interface to the CPU
                report "PREFETCH: Presenting $" & to_hexstring(slow_access_address(26 downto 0) + 1)
                  & " = $" & to_hexstring(expansionram_current_cache_line(to_integer(slow_access_address(2 downto 0))+1))
                  & " due to regular slow access read.";
                slow_prefetched_address <= slow_access_address(26 downto 0) + 1;
                slow_prefetched_data <= expansionram_current_cache_line(to_integer(slow_access_address(2 downto 0))+1);
              else
                -- XXX Ideally we should automatically present the next byte
                -- when it becomes available, but it's probably not worth the
                -- complexity for the small incremental benefit it would deliver.
                null;
              end if;

            else
              -- Neither HyperRAM nor SDRAM should take longer than this to
              -- complete a transaction.
              -- There is a bug in the SDRAM controller at least, that can
              -- result in a timeout occurring, which has yet to be tracked down.
              report "EXRAM-TIMEOUT: Reseting timeout to " & integer'image(to_integer(expansionram_read_timeout_default));
              expansionram_read_timeout <= expansionram_read_timeout_default;
              state <= ExpansionRAMRequest;
            end if;
          elsif slow_access_address(26)='1' then
            -- $4000000-$7FFFFFF = cartridge port
            report "Preparing to access from C64 cartridge port";
            report "EXRAM-TIMEOUT: Reseting timeout to " & integer'image(1000);
            expansionram_read_timeout <= to_unsigned(1000,24);
            state <= CartridgePortRequest;
          else

            -- Unmapped address space: Content = "Unmapped"
            case to_integer(slow_access_address(2 downto 0)) is
              when 0 => slow_access_rdata <= x"55";
              when 1 => slow_access_rdata <= x"6e";
              when 2 => slow_access_rdata <= x"6d";
              when 3 => slow_access_rdata <= x"61";
              when 4 => slow_access_rdata <= x"70";
              when 5 => slow_access_rdata <= x"70";
              when 6 => slow_access_rdata <= x"65";
              when 7 => slow_access_rdata <= x"64";
              when others => slow_access_rdata <= x"55";
            end case;
            state <= Idle;
            report "PUBLISH: Unmapped memory read";
            slow_access_ready_toggle <= slow_access_request_toggle;
          end if;
        end if;

        -- Note toggle state
        slow_access_last_request_toggle <= slow_access_request_toggle;
      when OPL2Request =>
        -- we might be out of phase with the 40MHz clock of the OPL, so we
        -- wait an extra cycle to make sure the write gets latched.
        -- It's not (apparently) possible to read from the OPL registers
        state <= OPL2Read;
      when OPL2Read =>
        opl_we <= '0';
        state <= Idle;
      when ExpansionRAMRequest =>
          if expansionram_eternally_busy='1' then
            -- Unmapped address space: Content = "ExtraRAM"
            case to_integer(slow_access_address(2 downto 0)) is
              when 0 => slow_access_rdata <= x"45";
              when 1 => slow_access_rdata <= x"78";
              when 2 => slow_access_rdata <= x"74";
              when 3 => slow_access_rdata <= x"72";
              when 4 => slow_access_rdata <= x"61";
              when 5 => slow_access_rdata <= x"52";
              when 6 => slow_access_rdata <= x"41";
              when 7 => slow_access_rdata <= x"4D";
              when others => slow_access_rdata <= x"45";
            end case;
            state <= Idle;
            report "PUBLISH: Externally busy expansion RAM read";
            slow_access_ready_toggle <= slow_access_request_toggle;
          elsif expansionram_busy = '0' then
            report "Preparing to access HyperRAM";
            -- Prepare request to HyperRAM
            report "CACHE: remembering write to $" & to_hexstring(slow_access_address);
            if slow_access_write = '1' then
              last_expansionram_write_address <= slow_access_address;
              last_expansionram_write_data <= slow_access_wdata;
            end if;
            expansionram_wdata <= slow_access_wdata;
            expansionram_address <= slow_access_address(26 downto 0);
            expansionram_read <= not slow_access_write;
            report "setting expansionram_read to " & std_logic'image(not slow_access_write)
              & " ( = not " & std_logic'image(slow_access_write) & ")";
            expansionram_write <= slow_access_write;

            if slow_access_write='1' then
              -- Write can be delivered, and then ignored, since we aren't
              -- waiting for anything. So just return to the Idle state;
              state <= Idle;
              report "PUBLISH: Instant-acknowledgement of write";
              slow_access_ready_toggle <= slow_access_request_toggle;

              -- Update pre-fetched data when writing
              if slow_access_address = slow_prefetched_address then
                slow_prefetched_data <= slow_access_wdata;
              end if;

            elsif slow_access_write='0' then
              -- Read from expansion RAM -- here we need to wait for a response
              -- from the expansion RAM
              state <= ExpansionRAMReadWait;
              report "Switching to ExpansionRAMReadWait";
            end if;
          else
            -- Expansion RAM is busy, wait for it to become idle
          end if;
      when ExpansionRAMReadWait =>
        -- Clear request flags
      report "Clearing expansionram_read/write in ExpansionRAMReadWait (ready_toggle = "
        & std_logic'image(expansionram_data_ready_toggle) & ").";
        expansionram_read <= '0';
        expansionram_write <= '0';
      if (expansionram_data_ready_toggle /= last_expansionram_data_ready_toggle) then
        last_expansionram_data_ready_toggle_sample <= expansionram_data_ready_toggle;
        report "Saw data. Switching back to Idle state. byte = $" & to_hexstring(expansionram_rdata);
        state <= Idle;
        slow_access_rdata <= expansionram_rdata;
        report "PUBLISH: Expansion RAM completion of read";
        slow_access_ready_toggle <= slow_access_request_toggle;

        if slow_access_address(2 downto 0) /= "111" then
          -- Present the NEXT byte via the fast interface to the CPU
          report "PREFETCH: Presenting $" & to_hexstring(slow_access_address(26 downto 0) + 1)
            & " = $" & to_hexstring(expansionram_current_cache_line(to_integer(slow_access_address(2 downto 0))+1))
            & " due to slow access read that had to ask HyperRAM for data.";
          slow_prefetched_address(26 downto 3) <= expansionram_current_cache_line_address;
          slow_prefetched_address(2 downto 0) <= slow_access_address(2 downto 0)+1;
          slow_prefetched_data <= expansionram_current_cache_line(to_integer(slow_access_address(2 downto 0))+1);
        end if;
-- Don't retry, as this can result in an infinite loop. If we don't get a
-- response within the allowed time, it's just aborted.
--      elsif expansionram_read_timeout = to_unsigned(1,24) then
--        -- Read about to timeout from expansion RAM
--        -- So try re-issuing the request
--        expansionram_read <= '1';
--        report "EXRAM-TIMEOUT: Retrying expansion RAM read after timeout";
--        report "EXRAM-TIMEOUT: Reseting timeout to " & integer'image(to_integer(expansionram_read_timeout_default));
--        expansionram_write <= '0';
--        expansionram_read_timeout <= expansionram_read_timeout_default;
      end if;

      when CartridgePortRequest =>
          report "Starting cartridge port access request, w="
            & std_logic'image(slow_access_write);
        cart_access_request <= '1';
        cart_access_read <= not slow_access_write;
        cart_access_address(27 downto 0) <= slow_access_address;
        cart_access_address(31 downto 28) <= (others => '0');
        cart_access_wdata <= slow_access_wdata;
        if cart_access_accept_strobe = '1' then
          cart_access_request <= '0';
          if slow_access_write = '1' then
            report "PUBLISH: C64 cartridge port write dispatched asynchronously.";
            slow_access_ready_toggle <= slow_access_request_toggle;
            state <= Idle;
          else
            state <= CartridgePortAcceptWait;
            report "C64 cartridge port read commenced.";
          end if;
        else
          state <= CartridgePortRequest;
        end if;
      when CartridgePortAcceptWait =>
        if cart_access_read_strobe = '1' then
          cart_access_request <= '0';
          report "PUBLISH: C64 cartridge port access complete";
          slow_access_rdata <= cart_access_rdata;
          slow_access_ready_toggle <= slow_access_request_toggle;
          state <= Idle;
        end if;
      end case;

    end if;
  end process;

end behavioural;
