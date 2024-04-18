library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;
use work.cputypes.all;

entity sdcard_model is
  port ( clock : in std_logic;
         cs_bo : in std_logic;
         sclk_o : in std_logic;
         mosi_o : in std_logic;
         miso_i : out std_logic;

         flash_address : out unsigned(47 downto 0);
         flash_rdata : in unsigned(7 downto 0)
         );
  
end entity;

architecture cheap_imitation of sdcard_model is  

  type sd_card_state_t is (
    IDLE,
    CMD_RX,
    CMD_PROCESS,
    SEND_R1,
    READ_BLOCK,
    READ_BLOCK_LOOP,
    READ_BLOCK_CRC
    );
  
  signal sdcard_state : sd_card_state_t := IDLE;
  signal next_sdcard_state : sd_card_state_t := IDLE;
  signal last_sdcard_state : sd_card_state_t := IDLE;

  signal cmd_phase : integer range 0 to 47 := 0;

  signal cmd : unsigned(47 downto 0) := (others => '0');
  signal r1_response : unsigned(7 downto 0) := (others => '0');

  signal last_cs : std_logic := '1';

  signal next_cmd_is_acmd : std_logic := '0';

  signal sdcard_idle : std_logic := '1';

  signal block_size : integer range 0 to 4096 := 512;
  signal flash_byte : unsigned(7 downto 0) := x"99";
  signal bits_remaining : integer range 0 to 8 := 0;
  signal bytes_remaining : integer range 0 to 4096 := 0;
  
begin

  process (cs_bo, sclk_o, mosi_o) is
  begin

    if cs_bo /= last_cs then
      last_cs <= cs_bo;
      report "SDCARDMODEL: CS=" & std_logic'image(cs_bo);
    end if;
  
    if (cs_bo='1') then
      -- If /CS goes high then abort everything
      sdcard_state <= CMD_RX;
      cmd_phase <= 0;
      cmd <= (others => '0');
      next_cmd_is_acmd <= '0';
      sdcard_idle <= '1';
      flash_address <= (others => '0');
    elsif rising_edge(sclk_o) then
      if sdcard_state /= last_sdcard_state then
        report "SDCARDMODEL: state = " & sd_card_state_t'image(sdcard_state);
        last_sdcard_state <= sdcard_state;
      end if;
      
      case sdcard_state is
        when IDLE => sdcard_state <= CMD_RX;
        when CMD_RX => cmd(0) <= mosi_o;
                       cmd(47 downto 1) <= cmd(46 downto 0);
                       if cmd_phase = 0 and mosi_o='1' then
                         -- Wait for leading 0 to indicate start of command
                         null;
                       elsif cmd_phase < 47 then
                         if cmd_phase = 0 then
                           report "SDCARDMODEL: Detected start of command";
                         end if;
                         cmd_phase <= cmd_phase + 1;
                       else
                         cmd_phase <= 0;
                         sdcard_state <= CMD_PROCESS;
                       end if;
        when CMD_PROCESS =>
          if next_cmd_is_acmd='0' then
            report "SDCARDMODEL: Received "
              & "CMD" & integer'image(to_integer(cmd(45 downto 40)))
              & ", full command = $" & to_hexstring(cmd);
          else
            report "SDCARDMODEL: Received "
              & "ACMD" & integer'image(to_integer(cmd(45 downto 40)))
              & ", full command = $" & to_hexstring(cmd);
          end if;
          -- By default send R1 in response
          sdcard_state <= SEND_R1;
          next_sdcard_state <= IDLE;
          r1_response(0) <= sdcard_idle; -- SD card is in idle state
          r1_response(1) <= '0'; -- Erase reset
          r1_response(2) <= '1'; -- Illegal command
          r1_response(3) <= '0'; -- Command CRC error
          r1_response(4) <= '0'; -- Erase Sequence Error
          r1_response(5) <= '0'; -- Address Error
          r1_response(6) <= '0'; -- Parameter Error
          r1_response(7) <= '0'; -- Used to indicate start of R1 TX
          cmd_phase <= 0;
          miso_i <= '0'; -- first bit of R1 TX, because the state switch adds a
                         -- 1 clock delay, and it's easiest to work around here.

          next_cmd_is_acmd <= '0';

          case to_integer(cmd(45 downto 40)) is
            when 0 => -- CMD 0 : Software reset
              r1_response(2) <= '0'; -- Accept command
            when 1 => -- CMD 1 : Initiate initialisation process
              r1_response(2) <= '0'; -- Accept command
            when 8 => -- CMD 8 : Check voltage range
              r1_response(2) <= '0'; -- Accept command
            when 41 => -- ACMD 41 : SDC initiate initialisation process
              if next_cmd_is_acmd = '1' then
                -- Process as ACMD41 : SDC initiate initialisation process
                r1_response(2) <= '0'; -- Accept command                
                r1_response(0) <= '0'; -- SD card no longer idle, i.e., waiting
                -- for R/W access
                sdcard_idle <= '0';
              else
                -- Process as CMD41 -- meaning unknown
                null; 
              end if;
            when 12 => -- CMD 12 : Stop reading data
              r1_response(2) <= '0'; -- Accept command              
            when 16 => -- CMD 16 : Change R/W block size
              null;
            when 17 => -- CMD 17 : Read single block
              r1_response(2) <= '0';
              next_sdcard_state <= READ_BLOCK;
              bytes_remaining <= block_size;
              bits_remaining <= 8;              
              -- Address calculation assumes 512 byte blocks, regardless of
              -- read block size.
              flash_address <= (others => '0');
              flash_address(40 downto 9) <= cmd(39 downto 8);
              report "SDCARDMODE: Reading " & integer'image(block_size) & " bytes from sector $" & to_hexstring(cmd(39 downto 8));
            when 18 => -- CMD 18 : Read multiple blocks
              null;
            when 25 => -- CMD 25 : Write multiple blocks
              null;
            when 55 => -- ACMD 55 : Prefix to indicate following command is ACMD
              next_cmd_is_acmd <= '1';
              r1_response(2) <= '0';
            when 58 => -- CMD58 : Read Operation Conditions register
              null;
            when others =>
              -- Illegal / unsupported command
              -- (already indicated by default above)
          end case;
        
        when SEND_R1 =>
          if cmd_phase = 0 then
            report "SDCARDMODEL: Sending R1 response $" & to_hexstring(r1_response);
          end if;
          report "SDCARDMODEL: Sending R1 bit " & integer'image(cmd_phase);
          miso_i <= r1_response(6);
          r1_response(7 downto 1) <= r1_response(6 downto 0);
          r1_response(0) <= r1_response(7);
          if cmd_phase < 6 then
            cmd_phase <= cmd_phase + 1;
          else
            cmd_phase <= 0;
            sdcard_state <= next_sdcard_state;
            report "SDCARDMODEL: Done sending R1. Advancing to " & sd_card_state_t'image(next_sdcard_state);
          end if;

        when READ_BLOCK =>
          -- Send $FE "start data" token
          miso_i <= '1';
          report "SDCARDMODEL: Sending start token bit " & integer'image(cmd_phase);
          if cmd_phase < 7 then
            cmd_phase <= cmd_phase + 1;
          else
            miso_i <= '0';
            report "SDCARDMODEL: Sent $FE start of data token";
            cmd_phase <= 0;
            bits_remaining <= 7;
            sdcard_state <= READ_BLOCK_LOOP;
          end if;
        when READ_BLOCK_LOOP =>
          if bits_remaining = 7 then
            report "SDCARDMODEL: Sending next byte of sector read = $" & to_hexstring(flash_rdata);
            miso_i <= flash_rdata(7);
            flash_byte(7 downto 1) <= flash_rdata(6 downto 0);
          else
            miso_i <= flash_byte(7);
            flash_byte(7 downto 1) <= flash_byte(6 downto 0);
          end if;
          if bits_remaining = 0 and bytes_remaining /= 0 then
            flash_address <= flash_address + 1;
            report "SDCARDMODEL: Advancing flash_address from $" & to_hexstring(flash_address);
          end if;
          if bits_remaining /= 0 then
            bits_remaining <= bits_remaining - 1;
          else 
            if bytes_remaining /= 0 then
              bytes_remaining <= bytes_remaining - 1;
              bits_remaining <= 7;
            else
              report "SDCARDMODEL: Finished sending sector bytes";
              -- Send CRC and cease reading
              sdcard_state <= READ_BLOCK_CRC;
              bits_remaining <= 7;
              bytes_remaining <= 0;
            end if;
          end if;
        when READ_BLOCK_CRC =>
          miso_i <= '0';
          if bits_remaining /= 0 then
            bits_remaining <= bits_remaining - 1;
          else
            if bytes_remaining /= 0 then
              report "sending next CRC byte";
              bits_remaining <= 7;
              bytes_remaining <= bytes_remaining - 1;
            else
              sdcard_state <= IDLE;
            end if;
          end if;
        when others =>
          assert false report "sdcard_state in illegal state '" & sd_card_state_t'image(sdcard_state) & "'";
      end case;      
    end if;
  end process;
  
end cheap_imitation;
