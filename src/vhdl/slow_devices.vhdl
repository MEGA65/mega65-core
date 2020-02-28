use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

ENTITY slow_devices IS
  generic (
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

    -- Indicate if expansion port is busy with access
    cart_busy : out std_logic;
    cart_access_count : out unsigned(7 downto 0);

    p1lo : inout std_logic_vector(3 downto 0) := "1111";
    p1hi : inout std_logic_vector(3 downto 0) := "1111";
    p2lo : inout std_logic_vector(3 downto 0) := "1111";
    p2hi : inout std_logic_vector(3 downto 0) := "1111";
    
    ------------------------------------------------------------------------
    -- Expansion RAM (upto 128MB)
    ------------------------------------------------------------------------
    expansionram_read : out std_logic := '0';
    expansionram_write : out std_logic := '0';
    expansionram_rdata : in unsigned(7 downto 0) := x"FF";
    expansionram_wdata : out unsigned(7 downto 0) := x"FF";
    expansionram_address : out unsigned(26 downto 0);
    expansionram_data_ready_strobe : in std_logic;
    expansionram_busy : in std_logic;
    
    ----------------------------------------------------------------------
    -- Flash RAM for holding FPGA config
    ----------------------------------------------------------------------
    QspiSCK : out std_logic := '1';
    QspiDB : inout unsigned(3 downto 0) := (others => 'H');
    QspiCSn : out std_logic := '1';

    ------------------------------------------------------------------------
    -- 3rd and 4th joystick ports
    ------------------------------------------------------------------------
    joya : out std_logic_vector(4 downto 0);
    joyb : out std_logic_vector(4 downto 0);
    
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

  signal cart_access_request : std_logic := '0';
  signal cart_access_read : std_logic := '1';
  signal cart_access_address : unsigned(31 downto 0) := (others => '1');
  signal cart_access_rdata : unsigned(7 downto 0);
  signal cart_access_wdata : unsigned(7 downto 0) := (others => '1');
  signal cart_access_accept_strobe : std_logic;
  signal cart_access_read_strobe : std_logic;

  signal slow_access_last_request_toggle : std_logic := '1';

  signal expansionram_eternally_busy : std_logic := '1';
  signal expansionram_read_timeout : unsigned(23 downto 0) := to_unsigned(0,24);
  
  type slow_state is (
    Idle,
    ExpansionRAMRequest,
    ExpansionRAMReadWait,
    CartridgePortRequest,
    CartridgePortAcceptWait
    );

  signal state : slow_state := Idle;
  
begin
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

  process (pixelclock) is
  begin
    if rising_edge(pixelclock) then

      -- Mark expansion RAM as present if the busy flag ever clears
      if expansionram_busy='0' then
        expansionram_eternally_busy <= '0';
      end if;
      
      report "State = " & slow_state'image(state) & " expansionram_data_ready_strobe = "
        & std_logic'image(expansionram_data_ready_strobe);
      case state is
        when Idle =>
          -- Clear flags for expansion RAM access request
          report "Clearing expansionram_read/write in Idle";
          expansionram_read <= '0';
          expansionram_write <= '0';
          
          if slow_access_last_request_toggle /= slow_access_request_toggle then
            report "Access request for $" & to_hstring(slow_access_address) & ", toggle=" & std_logic'image(slow_access_request_toggle);
            -- XXX do job, and acknowledge when done.

            -- CPU maps expansion port access to $7FF0000-$7FFFFFF for
          -- C64-compatible addressing.  In particular, I/O areas 1 and 2 map
          -- to $7FFDE00-$7FFDFFF, and external SIDs, when enabled, are expected
          -- at $7FFD400-$7FFD4FF.  The I/O expansion areas use the normal
          -- I/O1&2 select signals.
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
            
          if slow_access_address(27)='1' then
            -- $8000000-$FFFFFFF = expansion RAM
            report "Triaging Expansion RAM request";
            expansionram_read_timeout <= (others => '1');
            state <= ExpansionRAMRequest;
          elsif slow_access_address(26)='1' then
            -- $4000000-$7FFFFFF = cartridge port
            report "Preparing to access from C64 cartridge port";
            expansionram_read_timeout <= to_unsigned(1000,24);
            state <= CartridgePortRequest;
          elsif slow_access_address(27 downto 8) = x"3ffff" then
            case to_integer(slow_access_address(7 downto 0)) is
              when 0 =>
                -- @IO:GS $3FFFF00 MEGA65 PMOD P1 data port 
                slow_access_rdata(7 downto 4) <= unsigned(p1hi);
                slow_access_rdata(3 downto 0) <= unsigned(p1lo);
                if slow_access_write='1' then
                  p1hi <= std_logic_vector(slow_access_wdata(7 downto 4));
                  p1lo <= std_logic_vector(slow_access_wdata(3 downto 0));
                end if;
              when 1 =>
                -- @IO:GS $3FFFF01 MEGA65 PMOD P1 data direction port 
                if slow_access_write='1' then
                  if slow_access_wdata(7)='0' then
                    p1hi(3) <= 'Z';
                  end if;
                  if slow_access_wdata(6)='0' then
                    p1hi(2) <= 'Z';
                  end if;
                  if slow_access_wdata(5)='0' then
                    p1hi(1) <= 'Z';
                  end if;
                  if slow_access_wdata(4)='0' then
                    p1hi(0) <= 'Z';
                  end if;
                  if slow_access_wdata(3)='0' then
                    p1lo(3) <= 'Z';
                  end if;
                  if slow_access_wdata(2)='0' then
                    p1lo(2) <= 'Z';
                  end if;
                  if slow_access_wdata(1)='0' then
                    p1lo(1) <= 'Z';
                  end if;
                  if slow_access_wdata(0)='0' then
                    p1lo(0) <= 'Z';
                  end if;
                end if;                
              when 2 =>
                -- @IO:GS $3FFFF02 MEGA65 PMOD P2 data port 
                slow_access_rdata(7 downto 4) <= unsigned(p2hi);
                slow_access_rdata(3 downto 0) <= unsigned(p2lo);
                if slow_access_write='1' then
                  p2hi <= std_logic_vector(slow_access_wdata(7 downto 4));
                  p2lo <= std_logic_vector(slow_access_wdata(3 downto 0));
                end if;
              when 3 =>
                -- @IO:GS $3FFFF03 MEGA65 PMOD P2 data direction port 
                if slow_access_write='1' then
                  if slow_access_wdata(7)='0' then
                    p2hi(3) <= 'Z';
                  end if;
                  if slow_access_wdata(6)='0' then
                    p2hi(2) <= 'Z';
                  end if;
                  if slow_access_wdata(5)='0' then
                    p2hi(1) <= 'Z';
                  end if;
                  if slow_access_wdata(4)='0' then
                    p2hi(0) <= 'Z';
                  end if;
                  if slow_access_wdata(3)='0' then
                    p2lo(3) <= 'Z';
                  end if;
                  if slow_access_wdata(2)='0' then
                    p2lo(2) <= 'Z';
                  end if;
                  if slow_access_wdata(1)='0' then
                    p2lo(1) <= 'Z';
                  end if;
                  if slow_access_wdata(0)='0' then
                    p2lo(0) <= 'Z';
                  end if;
                end if;                
              when others => slow_access_rdata <= x"FF";
            end case;
            state <= Idle;
            slow_access_ready_toggle <= slow_access_request_toggle;            
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
            slow_access_ready_toggle <= slow_access_request_toggle;
          end if;        
        end if;
          
        -- Note toggle state
        slow_access_last_request_toggle <= slow_access_request_toggle;
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
            slow_access_ready_toggle <= slow_access_request_toggle;
          elsif expansionram_busy = '0' then
            report "Preparing to access HyperRAM";
            -- Prepare request to HyperRAM
            expansionram_address <= slow_access_address(26 downto 0);
            expansionram_wdata <= slow_access_wdata;
            expansionram_read <= not slow_access_write;
            report "setting expansionram_read to " & std_logic'image(not slow_access_write)
              & " ( = not " & std_logic'image(slow_access_write) & ")";
            expansionram_write <= slow_access_write;
            if slow_access_write='1' then
              -- Write can be delivered, and then ignored, since we aren't
              -- waiting for anything. So just return to the Idle state;
              state <= Idle;
              slow_access_ready_toggle <= slow_access_request_toggle;
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
        report "Clearing expansionram_read/write in ExpansionRAMReadWait (ready_strobe = " & std_logic'image(expansionram_data_ready_strobe) & ").";
        expansionram_read <= '0';
        expansionram_write <= '0';
        if expansionram_data_ready_strobe = '1' then
          report "Saw data. Switching back to Idle state. byte = $" & to_hstring(expansionram_rdata);
          state <= Idle;
          slow_access_rdata <= expansionram_rdata;
          slow_access_ready_toggle <= slow_access_request_toggle;
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
            report "C64 cartridge port write dispatched asynchronously.";
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
          report "C64 cartridge port access complete"; 
          slow_access_rdata <= cart_access_rdata;
          slow_access_ready_toggle <= slow_access_request_toggle;
          state <= Idle;
        end if;
      end case;

      if state /= Idle then
        if expansionram_read_timeout /= to_unsigned(0,24) then
          expansionram_read_timeout <= expansionram_read_timeout - 1;
        else
          -- Time out if stuck for too long
          state <= Idle;
          -- XXX Debug reading from HyperRAM
          slow_access_rdata(5 downto 0) <= expansionram_rdata(5 downto 0);
          slow_access_rdata(6) <= expansionram_busy;
          slow_access_rdata(7) <= expansionram_data_ready_strobe;
          slow_access_ready_toggle <= slow_access_request_toggle;
        end if;
      end if;
      
    end if;
  end process;
  
end behavioural;
