library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;


-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity hyperram is
  Port ( cpuclock : in STD_LOGIC; -- For slow devices bus interface
         clock240 : in std_logic; -- Used for fast clock for HyperRAM
         reset : in std_logic;

         latency_1x : in Unsigned(7 downto 0);
         latency_2x : in Unsigned(7 downto 0);
         
         read_request : in std_logic;
         write_request : in std_logic;
         address : in unsigned(26 downto 0);
         wdata : in unsigned(7 downto 0);
         
         rdata : out unsigned(7 downto 0);
         data_ready_strobe : out std_logic := '0';
         busy : out std_logic := '0';

         hr_d : inout unsigned(7 downto 0) := (others => 'Z'); -- Data/Address
         hr_rwds : inout std_logic := 'Z'; -- RW Data strobe
--         hr_rsto : in std_logic; -- Unknown PIN
         hr_reset : out std_logic := '1'; -- Active low RESET line to HyperRAM
--         hr_int : in std_logic; -- Interrupt?
         hr_clk_p : out std_logic := '1';
         hr_cs0 : out std_logic := '1'
         );
end hyperram;

architecture gothic of hyperram is

  component hyper_xface is
    port (
      reset : in std_logic;
      clk : in std_logic;
      rd_req : in std_logic;
      wr_req : in std_logic;
      mem_or_reg : in std_logic;
      wr_byte_en : in std_logic_vector(3 downto 0);
      rd_num_dwords : in unsigned(5 downto 0);
      addr : in unsigned(31 downto 0);
      wr_d : in unsigned(31 downto 0);
      rd_d : out unsigned(31 downto 0);
      rd_rdy : out std_logic;
      busy : out std_logic;
      burst_wr_rdy : out std_logic;
      latency_1x : in unsigned(7 downto 0);
      latency_2x : in unsigned(7 downto 0);

      dram_dq_in : in unsigned(7 downto 0);
      dram_dq_out : out unsigned(7 downto 0);
      dram_dq_oe_l : out std_logic;

      dram_rwds_in : in std_logic;
      dram_rwds_out : out std_logic;
      dram_rwds_oe_l : out std_logic;

      dram_ck : out std_logic;
      dram_rst_l : out std_logic;
      dram_cs_l : out std_logic;
      sump_dbg : out unsigned(7 downto 0)
      );
  end component;

  signal reset_hi : std_logic;
  
  signal address_latched : unsigned(26 downto 0);
  signal wdata_latched : unsigned(7 downto 0);
  
  signal hr_clock : std_logic := '0';

  signal data_ready_toggle : std_logic := '0';
  signal last_data_ready_toggle : std_logic := '0';

  signal request_toggle : std_logic := '0';
  signal last_request_toggle : std_logic := '0';

  -- Used to slow down HyperRAM enough that we can watch waveforms on the JTAG
  -- boundary scanner.
  signal slowdown_counter : integer := 0;
  
begin

  hyper0: component hyper_xface
    port map(
    -- Access interface
    reset => reset_hi,  -- active high
    clk => cpuclock,
    rd_req => rd_req,
    wr_req => wr_req,
    mem_or_reg => mem_or_reg,
    wr_byte_en => wr_byte_en,
    rd_num_dwords => rd_num_dwords,
    addr(26 downto 0) => address_latched,
    addr(31 downto 27) => address_dummy,
    wr_d(31 downto 24) => wdata_latched,
    wr_d(23 downto 16) => wdata_latched,
    wr_d(15 downto 8) => wdata_latched,
    wr_d(7 downto 0) => wdata_latched,
    rd_d => rd_d,
    rd_rdy => rd_rdy,
    busy => mem_busy,
    burst_wr_rdy => burst_wr_rdy,
    latency_1x => latency_1x,
    latency_2x => latency_2x,

    -- Hyperram pins
    dram_dq_in => dram_dq_in,
    dram_dq_out => dram_dq_out,
    dram_dq_oe_l => dram_dq_oe_l,
    dram_rwds_in => dram_rwds_in,
    dram_rwds_out => dram_rwds_out,
    dram_rwds_oe_l => dram_rwds_oe_l,

    dram_ck => hr_clk_p,
    dram_rst_l => hr_reset,
    dram_cs_l => hr_cs0
    );

  reset_hi <= not reset;
  
  process (dram_dq_in,dram_dq_out,dram_dq_oe_l,
           dram_rwds_in,dram_rwds_out,dram_rwds_oe_l) is
  begin
    -- Control direction of bi-directional signals
    if dram_dq_oe_l = '0' then
      hr_d <= (others => 'Z');
      dram_dq_in <= hr_d;
    else
      hr_d <= dram_dq_out;
    end if;
    if dram_rwds_oe_l='0' then
      hr_rwds <= 'Z';
      dram_rwds_in <= hr_rwds;
    else
      hr_rwds <= dram_rwds_out;
    end if;
  end process;
  
    
  process (cpuclock,clock240) is
  begin
    if rising_edge(cpuclock) then
      data_ready_strobe <= '0';

    if rising_edge(clock240) then
      -- HyperRAM state machine
      report "State = " & state_t'image(state);
      if (state /= Idle) and ( slowdown_counter /= 0) then
        slowdown_counter <= slowdown_counter - 1;
      else
--        slowdown_counter <= 1000000;
        slowdown_counter <= 0;
        
        case state is
          when Idle =>
            -- Mark us ready for a new job, or pick up a new job
            if request_toggle /= last_request_toggle then
              last_request_toggle <= request_toggle;
              if ram_reading = '1' then
                state <= ReadSetup;
              else
                state <= WriteSetup;
              end if;
              busy_internal <= '1';
              report "Accepting job";
            else
              report "Clearing busy_internal";
              busy_internal <= '0';
            end IF;
            -- Release CS line between transactions
            hr_cs0 <= '1';
            hr_cs1 <= '1';
          when ReadSetup =>
            -- Prepare command vector
            hr_command(47) <= '1'; -- READ
            hr_command(46) <= ram_address(24); -- Memory address space (1) / Register
                                               -- address space select (0) ?
            hr_command(45) <= '1'; -- Linear access (not wrapped)
            hr_command(44 downto 37) <= (others => '0'); -- unused upper address bits
            hr_command(36 downto 16) <= ram_address(23 downto 3);
            hr_command(15 downto 3) <= (others => '0'); -- reserved bits
            hr_command(2 downto 0) <= ram_address(2 downto 0);

            -- Call HyperRAM to attention (Each 8MB half has a separate CS line,
            -- so we gate them on address line 23 = 8MB point)
            hr_cs0 <= ram_address(23);
            hr_cs1 <= not ram_address(23);
            
            hr_reset <= '1'; -- active low reset
            countdown <= 6;

            state <= HyperRAMCSStrobe;
            
          when WriteSetup =>
            -- Prepare command vector
            hr_command(47) <= '0'; -- WRITE
            hr_command(46) <= '0'; -- Memory address space
            hr_command(45) <= '1'; -- Linear access (not wrapped)
            hr_command(44 downto 37) <= (others => '0'); -- unused upper address bits
            hr_command(36 downto 16) <= ram_address(23 downto 3);
            hr_command(15 downto 3) <= (others => '0'); -- reserved bits
            hr_command(2 downto 0) <= ram_address(2 downto 0);

            -- Call HyperRAM to attention
            hr_cs0 <= ram_address(23);
            hr_cs1 <= not ram_address(23);
            
            hr_reset <= '1'; -- active low reset
            countdown <= 6;

            state <= HyperRAMCSStrobe;

          when HyperRAMCSStrobe =>
            if countdown /= 0 then
              countdown <= countdown - 1;
            else
              state <= HyperRAMOutputCommand;
              countdown <= 6; -- 48 bits = 6 x 8 bits
            end if;

          when HyperRAMOutputCommand =>
            hr_rwds <= 'Z';
            next_is_data <= not next_is_data;
            if next_is_data = '0' then
              -- Toggle clock while data steady
              hr_clk_n <= not hr_clock;
              hr_clk_p <= hr_clock;
              hr_clock <= not hr_clock;
            else
              -- Toggle data while clock steady
              hr_d <= hr_command(47 downto 40);
              hr_command(47 downto 8) <= hr_command(39 downto 0);

              if countdown = 3 then
                extra_latency <= hr_rwds;
              end if;
              if countdown /= 0 then
                countdown <= countdown - 1;
              else
                -- Finished shifting out
                if ram_reading = '1' then
                  -- Reading: We can just wait until hr_rwds has gone low, and then
                  -- goes high again to indicate the first data byte
                  countdown <= 99;
                  state <= HyperRAMReadWait;
                else
                  -- Writing, so count down the correct number of cycles;
                  -- Initial latency is reduced by 3 cycles for the last bytes
                  -- of the access command
                  countdown <= 6 - 3;
                  state <= HyperRAMLatencyWait;
                end if;
              end if;
            end if;
          when HyperRAMLatencyWait =>
            hr_rwds <= 'Z';
            next_is_data <= not next_is_data;
            if next_is_data = '0' then
              -- Toggle clock while data steady
              hr_clk_n <= not hr_clock;
              hr_clk_p <= hr_clock;
              hr_clock <= not hr_clock;
            else
              if countdown /= 0 then
                countdown <= countdown - 1;
              else
                if extra_latency='1' then
                  -- If we were asked to wait for extra latency,
                  -- then wait another 6 cycles.
                  extra_latency <= '0';
                  countdown <= 6;
                else
                  -- Latency countdown for writing is over, we can now
                  -- begin writing bytes.
                  -- XXX It is possible we will have mis-timed this by a cycle or
                  -- two, in which case, we will write to the wrong address.
                  -- If it is too high an address, then we are late.
                  -- If it is not written at all, then we are too early.

                  -- Write byte
                  hr_rwds <= '1';
                  hr_d <= ram_wdata;
                  state <= HyperRAMFinishWriting;
                end if;
              end if;
            end if;
          when HyperRAMFinishWriting =>
            -- Last cycle was data, so next cycle is clock.

            -- Indicate no more bytes to write
            hr_rwds <= '0';

            -- Toggle clock
            hr_clk_n <= not hr_clock;
            hr_clk_p <= hr_clock;
            hr_clock <= not hr_clock;

            -- Go back to waiting
            state <= Idle;
          when HyperRAMReadWait =>
            hr_rwds <= 'Z';
            if countdown = 0 then
              -- Timed out waiting for read -- so return anyway, rather
              -- than locking the machine hard forever.
              rdata <= x"DE";
              data_ready_toggle <= not data_ready_toggle;
              state <= Idle;
            else
              countdown <= countdown - 1;
            end if;
            next_is_data <= not next_is_data;
            if next_is_data = '0' then
              -- Toggle clock while data steady
              hr_clk_n <= not hr_clock;
              hr_clk_p <= hr_clock;
              hr_clock <= not hr_clock;
            else
              if hr_rwds = '1' then
                -- Data has arrived
                rdata <= hr_d;
                data_ready_toggle <= not data_ready_toggle;
                state <= Idle;
              end if;
            end if;
          when others =>
            state <= Idle;
        end case;      
      end if;
    end if;
    
  end process;
end gothic;


