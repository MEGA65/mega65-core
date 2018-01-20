-- VHDL SD card interface
-- by Steven J. Merrifield, June 2008

-- Reads and writes a single block of data, and also writes continuous data
-- Tested on Xilinx Spartan 3 hardware, using Transcend and SanDisk Ultra II cards
-- Read states are derived from the Apple II emulator by Stephen Edwards 

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;

entity sd_controller is
  port (
    cs : out std_logic;
    mosi : out std_logic;
    miso : in std_logic;
    sclk : out std_logic;

    sdhc_mode : in std_logic;
    half_speed : in std_logic;

    last_state : out unsigned(7 downto 0) := x"00";
    
    rd : in std_logic;
    wr : in std_logic;
    dm_in : in std_logic;	-- data mode, 0 = write continuously, 1 = write single block
    sector_number : in std_logic_vector(31 downto 0);  -- sector number requested
    reset : in std_logic;
    data_ready : out std_logic;     -- 1= data written, or data accepted,
                                        -- 0= wait for data, or pre-load data
                                        -- for writing
    din : in std_logic_vector(7 downto 0);
    dout : out std_logic_vector(7 downto 0);
    clk : in std_logic	-- twice the SPI clk

    );

end sd_controller;

architecture rtl of sd_controller is
  type states is (
    RST,
    INIT,
    CMD0,
    CMD8,
    CMD7B,
    CMD7A,
    CMD55,
    CMD41,
    POLL_CMD,
    
    IDLE,	-- wait for read or write pulse
    READ_BLOCK,
    READ_BLOCK_WAIT,
    READ_BLOCK_DATA,
    READ_BLOCK_CRC,
    SEND_CMD,
    RECEIVE_BYTE_WAIT,
    RECEIVE_BYTE,
    WRITE_BLOCK_CMD,
    WRITE_BLOCK_INIT,		-- initialise write command
    WRITE_BLOCK_DATA,		-- loop through all data bytes
    WRITE_BLOCK_BYTE,		-- send one byte
    WRITE_BLOCK_WAIT		-- wait until not busy
    );


-- one start byte, plus 512 bytes of data, plus two FF end bytes (CRC)
  constant WRITE_DATA_SIZE : integer := 515;

  signal state, return_state : states;
  signal sclk_sig : std_logic := '0';
  signal cmd_out : std_logic_vector(55 downto 0);
  signal recv_data : std_logic_vector(7 downto 0);
  signal address : std_logic_vector(31 downto 0);
  signal cmd_mode : std_logic := '1';
  signal data_mode : std_logic := '1';
  signal response_mode : std_logic := '1';
  signal data_sig : std_logic_vector(7 downto 0) := x"00";

-- Reset sequence to microsd card should be 80+ clocks at <400KHz.
-- We previously just used CPU clock/2 = 16MHz, and it worked.
-- But at 48MHz, and so 24MHz pulsetrain, it is less reliable.
-- So let's do it right with a 100KHz - 400KHz pulse train.
-- 48MHz clock means we should take at least 48000KHz / 400KHz
-- = 120 cycles per clock.  Allowing a bit for the fact that we
-- are really at about 193.5MHz/4 = 48.4MHz, suggests that about 150
-- cycles per pulse should be okay.  So count to 75 for each half of clock.
  signal fourhundredkhz_counter : integer range 0 to 75 := 0;

  signal half_speed_toggle : std_logic := '0';

begin

  process(clk)
  begin
  end process;
  
  process(clk,reset,dm_in)
    variable byte_counter : integer range 0 to WRITE_DATA_SIZE;
    variable bit_counter : integer range 0 to 176;
  begin
    data_mode <= dm_in;

    if rising_edge(clk) then

      half_speed_toggle <= not half_speed_toggle;
      
      if fourhundredkhz_counter = 75 then
        fourhundredkhz_counter <= 0;
      else
        fourhundredkhz_counter <= fourhundredkhz_counter + 1;
      end if;

      
      if (reset='1') then
        state <= RST;
        sclk_sig <= '0';
        -- Show when we are reseting
        last_state <= x"99";
      else
        case state is
          
          when RST =>
            report "FAKESD: Reseting SD card";
            sclk_sig <= '0';
            cmd_out <= (others => '1');
            address <= x"00000000";
            byte_counter := 0;
            cmd_mode <= '1'; -- 0=data, 1=command
            response_mode <= '1';	-- 0=data, 1=command
            bit_counter := 176;
            cs <= '1';
--            state <= INIT;
            state <= IDLE;
            
          when INIT =>		-- CS=1, send 80 clocks, CS=0
            report "FAKESD: Waiting to issue CMD0";
            if (bit_counter = 0) then
              cs <= '0';
              state <= CMD0;
            else
              if fourhundredkhz_counter = 0 then
                bit_counter := bit_counter - 1;
                sclk_sig <= not sclk_sig;
              end if;
            end if;	
            
          when CMD0 =>
            report "FAKESD: Issuing CMD0";
            last_state <= x"00";
            cmd_out <= x"FF400000000095";
            bit_counter := 55;
            if sdhc_mode='1' then
              return_state <= CMD8;
            else
              return_state <= CMD55; -- CMD8;                                          
            end if;
            state <= SEND_CMD;

            
          when CMD8 =>
            report "FAKESD: Issuing CMD8";
            -- Tell SDHC card which voltages we support
            last_state <= x"08";
            
            -- Initialising SDHC cards is not as simple as it should be.
            -- It seems to always fail first time around.
            -- Retry CMD0 until it gives result 0x01 (Idle, no errors)
            if recv_data = "00000001" then               
              cmd_out <= x"FF48" & x"000001aa" & x"87"; -- 8d or 40h = 48h
              bit_counter := 55;
              return_state <= CMD7B;
              state <= SEND_CMD;
            else
              state <= CMD0;
            end if;

          when CMD7B =>
            report "FAKESD: Issuing CMD7B";
            -- Tell SDHC card to disable CRC checks
            last_state <= x"7B";

            if recv_data = "00000001" then
              cmd_out <= x"FF7B0000000091";
              bit_counter := 55;
              return_state <= CMD7A;
              state <= SEND_CMD;
            else
              state <= CMD7A; -- proceed anyway
            end if;

          when CMD7A =>
            report "FAKESD: Issuing CMD7A";
            -- Check OCR
            last_state <= x"7A";

            if recv_data = "00000001" then
              cmd_out <= x"FF7A0000000000";
              bit_counter := 55;
              return_state <= CMD55;
              state <= SEND_CMD;
            else
              state <= CMD55; -- proceed anyway
            end if;            
            
          when CMD55 =>
            report "FAKESD: Issuing CMD55";
            last_state <= x"77";
            cmd_out <= x"FF770000000001";	-- 55d OR 40h = 77h
            bit_counter := 55;
            return_state <= CMD41;
            state <= SEND_CMD;
            
          when CMD41 =>
            report "FAKESD: Issuing CMD41";
            last_state <= x"69";
                                        -- Allow setting flags during CMD41
            cmd_out <= x"FF69" & address & x"01";	-- 41d OR 40h = 69h
            bit_counter := 55;
            return_state <= POLL_CMD;
            state <= SEND_CMD;
            
          when POLL_CMD =>
            report "FAKESD: Switching to IDLE state.";
--            if (recv_data(0) = '0') then
              last_state <= x"FF";
              state <= IDLE;
--            else
--              -- Failed to accept CMD55, so retry until it accepts it.
--              state <= CMD55;
--            end if;
            
          when IDLE =>
            report "FAKESD: Idle";
            if (rd = '1') then
              state <= READ_BLOCK;
              address <= sector_number;
            elsif (wr='1') then
              state <= WRITE_BLOCK_CMD;
              address <= sector_number;
            else
              state <= IDLE;
            end if;
            
          when READ_BLOCK =>
            cmd_out <= x"FF" & x"51" & address & x"FF";
            bit_counter := 55;
            return_state <= READ_BLOCK_WAIT;
            state <= SEND_CMD;
            
          when READ_BLOCK_WAIT =>
            if (sclk_sig='1' and miso='0') then
              state <= READ_BLOCK_DATA;
              byte_counter := 511;
              bit_counter := 7;
              return_state <= READ_BLOCK_DATA;
              state <= RECEIVE_BYTE;
            end if;
            sclk_sig <= not sclk_sig;

          when READ_BLOCK_DATA =>
            data_ready <= '0';                                                
            if (byte_counter = 0) then
              bit_counter := 7;
              return_state <= READ_BLOCK_CRC;
              state <= RECEIVE_BYTE;
            else
              byte_counter := byte_counter - 1;
              return_state <= READ_BLOCK_DATA;
              bit_counter := 7;
              state <= RECEIVE_BYTE;
            end if;
            
          when READ_BLOCK_CRC =>
            bit_counter := 7;
            return_state <= IDLE;
            address <= std_logic_vector(unsigned(address) + x"200");
            state <= RECEIVE_BYTE;
            
          when SEND_CMD =>
            report "FAKESD: in SEND_CMD";
            if (sclk_sig = '1') then
              if (bit_counter = 0) then
                state <= RECEIVE_BYTE_WAIT;
                data_ready <= '0';
              else
                if half_speed='0' or half_speed_toggle='0' then
                  bit_counter := bit_counter - 1;
                  cmd_out <= cmd_out(54 downto 0) & '1';
                end if;
              end if;
            end if;
            if half_speed='0' or half_speed_toggle='0' then
              sclk_sig <= not sclk_sig;
            end if;            
          when RECEIVE_BYTE_WAIT =>
            if (sclk_sig = '1') and (half_speed='0' or half_speed_toggle='0') then
--              if (miso = '0') then
                recv_data <= (others => '0');
                if (response_mode='0') then
                  bit_counter := 3; -- already read bits 7..4
                else
                  bit_counter := 6; -- already read bit 7
--                end if;
                state <= RECEIVE_BYTE;
              end if;
            end if;
            if half_speed='0' or half_speed_toggle='0' then
              sclk_sig <= not sclk_sig;
            end if;
          when RECEIVE_BYTE =>
            if (sclk_sig = '1') and (half_speed='0' or half_speed_toggle='0') then
              recv_data <= recv_data(6 downto 0) & miso;
              if (bit_counter = 0) then
                if (return_state = WRITE_BLOCK_INIT) then
                  state <= return_state;
                elsif (return_state = WRITE_BLOCK_WAIT) then
                  state <= return_state;
                else
                  state <= return_state;
                  dout <= recv_data(6 downto 0) & miso;
                  report "FAKESD: Data byte from SD card is $" & to_hstring(recv_data(6 downto 0) & miso);
                  data_ready <= '1';
                end if;
              else
                bit_counter := bit_counter - 1;
                data_ready <= '0';
              end if;
            end if;
            if half_speed='0' or half_speed_toggle='0' then
              sclk_sig <= not sclk_sig;
            end if;            

          when WRITE_BLOCK_CMD =>
            cmd_mode <= '1';
            if (data_mode = '0') then
              cmd_out <= x"FF" & x"59" & address & x"FF";	-- continuous
            else
              cmd_out <= x"FF" & x"58" & address & x"FF";	-- single block
            end if;
            bit_counter := 55;
            return_state <= WRITE_BLOCK_INIT;
            state <= SEND_CMD;
            
          when WRITE_BLOCK_INIT => 
            cmd_mode <= '0';
            byte_counter := WRITE_DATA_SIZE; 
            state <= WRITE_BLOCK_DATA;
            data_ready <= '0';					
          when WRITE_BLOCK_DATA => 
            if byte_counter = 0 then
              state <= RECEIVE_BYTE_WAIT;
              return_state <= WRITE_BLOCK_WAIT;
              response_mode <= '0';
              cmd_mode <= '1';
            else 	
              if ((byte_counter = 2) or (byte_counter = 1)) then
                data_sig <= x"FF"; -- two CRC bytes
              elsif byte_counter = WRITE_DATA_SIZE then
                if (data_mode='0') then
                  data_sig <= x"FC"; -- start byte, multiple blocks
                else
                  data_sig <= x"FE"; -- start byte, single block
                end if;
              else
                                        -- just a counter, get real data here
                data_sig <= din;
                report "FAKESD: Data byte from computer is $" & to_hstring(din);
                data_ready <= '1';
              end if;
              bit_counter := 7;
              state <= WRITE_BLOCK_BYTE;
              byte_counter := byte_counter - 1;
            end if;
            
          when WRITE_BLOCK_BYTE =>
            data_ready <= '0';
            if (sclk_sig = '1') and (half_speed='0' or half_speed_toggle='0') then
              if bit_counter=0 then
                state <= WRITE_BLOCK_DATA;
              else
                data_sig <= data_sig(6 downto 0) & '1';
                bit_counter := bit_counter - 1;
              end if;
            end if;
            if  (half_speed='0' or half_speed_toggle='0') then
              sclk_sig <= not sclk_sig;
            end if;
          when WRITE_BLOCK_WAIT =>
            response_mode <= '1';
            if (sclk_sig = '1') and (half_speed='0' or half_speed_toggle='0') then
--              if MISO='1' then
                if (data_mode='0') then
                  state <= WRITE_BLOCK_INIT;
                else
                  address <= std_logic_vector(unsigned(address) + x"200");
                  state <= IDLE;
                end if;
--              end if;
            end if;
            if  (half_speed='0' or half_speed_toggle='0') then
              sclk_sig <= not sclk_sig;
            end if;

          when others => state <= IDLE;
        end case;
      end if;
    end if;
  end process;

  sclk <= sclk_sig;
  mosi <= cmd_out(55) when cmd_mode='1' else data_sig(7);
  			
end rtl;

