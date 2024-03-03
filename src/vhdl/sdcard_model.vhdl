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

  signal cmd_phase : integer range 0 to 47 := 0;

  signal cmd : unsigned(47 downto 0) := (others => '0');
  signal r1_response : unsigned(7 downto 0) := (others => '0');
  
begin

  process (cs_bo, sclk_o, mosi_o) is
  begin
    if (cs_bo='1') then
      -- If /CS goes high then abort everything
      sdcard_state <= CMD_RX;
      cmd_phase <= 0;
      cmd <= (others => '0');
    elsif rising_edge(sclk_o) then
      case sdcard_state is
        when IDLE => sdcard_state <= CMD_RX; 
                     cmd(0) <= mosi_o;
                     cmd(47 downto 10) <= cmd(46 downto 0);
                     if cmd_phase < 47 then
                       cmd_phase <= cmd_phase + 1;
                     else
                       cmd_phase <= 0;
                       sdcard_state <= CMD_PROCESS;
                     end if;
        when CMD_PROCESS =>
          report "SDCARDMODEL: Received command: " & to_hexstring(cmd);
          -- By default send R1 in response
          sdcard_state <= SEND_R1;
          next_sdcard_state <= IDLE;
          r1_response(0) <= '1'; -- SD card is in idle state
          r1_response(1) <= '0'; -- Erase reset
          r1_response(2) <= '1'; -- Illegal command
          r1_response(3) <= '0'; -- Command CRC error
          r1_response(4) <= '0'; -- Erase Sequence Error
          r1_response(5) <= '0'; -- Address Error
          r1_response(6) <= '0'; -- Parameter Error
          r1_response(7) <= '0'; -- Used to indicate start of R1 TX
          cmd_phase <= 0;
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
