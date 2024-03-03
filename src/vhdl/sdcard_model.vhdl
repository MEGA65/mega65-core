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
         miso_i : out std_logic
         );
  
end entity;

architecture cheap_imitation of sdcard_model is  

  type sd_card_state_t is (
    IDLE,
    CMD_RX,
    CMD_PROCESS,
    SEND_R1
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
          miso_i <= r1_response(7);
          r1_response(7 downto 1) <= r1_response(6 downto 0);
          r1_response(0) <= r1_response(7);
          if cmd_phase < 7 then
            cmd_phase <= cmd_phase + 1;
          else
            cmd_phase <= 0;
            sdcard_state <= next_sdcard_state;
          end if;
        when others =>
          assert false report "sdcard_state in illegal state '" & sd_card_state_t'image(sdcard_state) & "'";
      end case;      
    end if;
  end process;
  
end cheap_imitation;
