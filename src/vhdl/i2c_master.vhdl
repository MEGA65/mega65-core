--------------------------------------------------------------------------------
--
--   FileName:         i2c_master.vhd
--   Dependencies:     none
--   Design Software:  Quartus II 64-bit Version 13.1 Build 162 SJ Full Version
--
--   HDL CODE IS PROVIDED "AS IS."  DIGI-KEY EXPRESSLY DISCLAIMS ANY
--   WARRANTY OF ANY KIND, WHETHER EXPRESS OR IMPLIED, INCLUDING BUT NOT
--   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
--   PARTICULAR PURPOSE, OR NON-INFRINGEMENT. IN NO EVENT SHALL DIGI-KEY
--   BE LIABLE FOR ANY INCIDENTAL, SPECIAL, INDIRECT OR CONSEQUENTIAL
--   DAMAGES, LOST PROFITS OR LOST DATA, HARM TO YOUR EQUIPMENT, COST OF
--   PROCUREMENT OF SUBSTITUTE GOODS, TECHNOLOGY OR SERVICES, ANY CLAIMS
--   BY THIRD PARTIES (INCLUDING BUT NOT LIMITED TO ANY DEFENSE THEREOF),
--   ANY CLAIMS FOR INDEMNITY OR CONTRIBUTION, OR OTHER SIMILAR COSTS.
--
--   Version History
--   Version 1.0 11/01/2012 Scott Larson
--     Initial Public Release
--   Version 2.0 06/20/2014 Scott Larson
--     Added ability to interface with different slaves in the same transaction
--     Corrected ack_error bug where ack_error went 'Z' instead of '1' on error
--     Corrected timing of when ack_error signal clears
--   Version 2.1 10/21/2014 Scott Larson
--     Replaced gated clock with clock enable
--     Adjusted timing of SCL during start and stop conditions
--   Version 2.2 02/05/2015 Scott Larson
--     Corrected small SDA glitch introduced in version 2.1
-- 
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;

ENTITY i2c_master IS
  generic (
    input_clk : INTEGER := 40_500_000; --input clock speed from user logic in Hz
    bus_clk   : INTEGER := 400_000   --speed the i2c bus (scl) will run at in Hz
    );
  PORT(
    clk       : IN     STD_LOGIC;                    --system clock
    reset_n   : IN     STD_LOGIC;                    --active low reset
    ena       : IN     STD_LOGIC;                    --latch in command
    addr      : IN     STD_LOGIC_VECTOR(6 DOWNTO 0); --address of target slave
    rw        : IN     STD_LOGIC;                    --'0' is write, '1' is read
    data_wr   : IN     STD_LOGIC_VECTOR(7 DOWNTO 0); --data to write to slave
    busy      : OUT    STD_LOGIC;                    --indicates transaction in progress
    data_rd   : OUT    STD_LOGIC_VECTOR(7 DOWNTO 0); --data read from slave
    ack_error : BUFFER STD_LOGIC;                    --flag if improper acknowledge from slave
    sda       : INOUT  STD_LOGIC;                    --serial data output of i2c bus
    scl       : INOUT  STD_LOGIC;                   --serial clock output of i2c bus

    latch_toggle : out std_logic := '0';
    
    -- Debug inputs that allow us to pull the lines low to test
    swap : in std_logic := '0';
    debug_scl : in std_logic := '0';
    debug_sda : in std_logic := '0');
    
END i2c_master;

ARCHITECTURE logic OF i2c_master IS
  CONSTANT divider  :  INTEGER := (input_clk/bus_clk)/4; --number of clocks in 1/4 cycle of scl
  constant divider_minus_1 : integer := divider - 1;
  constant divider2_minus_1 : integer := divider*2-1;
  constant divider2 : integer := divider*2;
  constant divider3_minus_1 : integer := divider*3-1;
  constant divider3 : integer := divider*3;
  
  TYPE machine IS(ready, start, command, slv_ack1, wr, rd, slv_ack2, mstr_ack, stop); --needed states
  SIGNAL state         : machine;                        --state machine
  SIGNAL data_clk      : STD_LOGIC;                      --data clock for sda
  SIGNAL data_clk_prev : STD_LOGIC;                      --data clock during previous system clock
  SIGNAL scl_clk       : STD_LOGIC;                      --constantly running internal scl
  SIGNAL scl_ena       : STD_LOGIC := '0';               --enables internal scl to output
  SIGNAL sda_int       : STD_LOGIC := '1';               --internal sda
  SIGNAL sda_ena_n     : STD_LOGIC;                      --enables internal sda to output
  SIGNAL addr_rw       : STD_LOGIC_VECTOR(7 DOWNTO 0);   --latched in address and read/write
  SIGNAL data_tx       : STD_LOGIC_VECTOR(7 DOWNTO 0);   --latched in data to write to slave
  SIGNAL data_rx       : STD_LOGIC_VECTOR(7 DOWNTO 0);   --data received from slave
  SIGNAL bit_cnt       : INTEGER RANGE 0 TO 7 := 7;      --tracks bit number in transaction
  SIGNAL stretch       : STD_LOGIC := '0';               --identifies if slave is stretching scl

  signal latch_toggle_int : std_logic := '0';
BEGIN

  --generate the timing for the bus clock (scl_clk) and the data clock (data_clk)
  PROCESS(clk, reset_n)
    VARIABLE count  :  INTEGER RANGE 0 TO divider*4;  --timing for clock generation
  BEGIN
    IF(reset_n = '0') THEN                --reset asserted
      stretch <= '0';
      count := 0;
    ELSIF(clk'EVENT AND clk = '1') THEN
      data_clk_prev <= data_clk;          --store previous value of data clock
      IF(count = divider*4-1) THEN        --end of timing cycle
        count := 0;                       --reset timer
      ELSIF(stretch = '0') THEN           --clock stretching from slave not detected
        count := count + 1;               --continue clock generation timing
      END IF;
      if count >= 0 and count <= divider_minus_1 then           --first 1/4 cycle of clocking
        scl_clk <= '0';
        data_clk <= '0';
      elsif count>=divider and count<=divider2_minus_1 then    --second 1/4 cycle of clocking
        scl_clk <= '0';
        data_clk <= '1';
      elsif  count>=divider2 and count<=divider3_minus_1 then  --third 1/4 cycle of clocking
        scl_clk <= '1';                 --release scl
        IF(scl = '0') THEN              --detect if slave is stretching clock
          stretch <= '1';
        ELSE
          stretch <= '0';
        END IF;
        data_clk <= '1';
      else                    --last 1/4 cycle of clocking
        scl_clk <= '1';
        data_clk <= '0';
      END if;
    END IF;
  END PROCESS;

  --state machine and writing to sda during scl low (data_clk rising edge)
  PROCESS(clk, reset_n)
  BEGIN
    IF(reset_n = '0') THEN                 --reset asserted
      state <= ready;                      --return to initial state
      busy <= '1';                         --indicate not available
      scl_ena <= '0';                      --sets scl high impedance
      sda_int <= '1';                      --sets sda high impedance
      ack_error <= '0';                    --clear acknowledge error flag
      bit_cnt <= 7;                        --restarts data bit counter
      data_rd <= "00000000";               --clear data read port
    ELSIF(clk'EVENT AND clk = '1') THEN
      IF(data_clk = '1' AND data_clk_prev = '0') THEN  --data clock rising edge
--        report "state = " & machine'image(state);
        CASE state IS
          WHEN ready =>                      --idle state
            IF(ena = '1') THEN               --transaction requested
              report "Accepting job: addr=$" & to_hexstring(addr) & ", rw= " & std_logic'image(rw);
              busy <= '1';                   --flag busy
              addr_rw <= addr & rw;          --collect requested slave address and command
              data_tx <= data_wr;            --collect requested data to write
              state <= start;                --go to start bit
              latch_toggle <= not latch_toggle_int;
              latch_toggle_int <= not latch_toggle_int;
            ELSE                             --remain idle
              busy <= '0';                   --unflag busy
              state <= ready;                --remain idle
            END IF;
          WHEN start =>                      --start bit of transaction
            report "sending start for transaction";
            busy <= '1';                     --resume busy if continuous mode
--            report "sending command bit " & integer'image(bit_cnt) & " = " & std_logic'image(addr_rw(bit_cnt));
            sda_int <= addr_rw(bit_cnt);     --set first address bit to bus
            state <= command;                --go to command
          WHEN command =>                    --address and command byte of transaction
            IF(bit_cnt = 0) THEN             --command transmit finished
              sda_int <= '1';                --release sda for slave acknowledge
              bit_cnt <= 7;                  --reset bit counter for "byte" states
              state <= slv_ack1;             --go to slave acknowledge (command)
            ELSE                             --next clock cycle of command state
--              report "sending command bit " & integer'image(bit_cnt-1) & " = " & std_logic'image(addr_rw(bit_cnt-1));
              bit_cnt <= bit_cnt - 1;        --keep track of transaction bits
              sda_int <= addr_rw(bit_cnt-1); --write address/command bit to bus
              state <= command;              --continue with command
            END IF;
          WHEN slv_ack1 =>                   --slave acknowledge bit (command)
            IF(addr_rw(0) = '0') THEN        --write command
              sda_int <= data_tx(bit_cnt);   --write first bit of data
              report "switching to wr following command";
              state <= wr;                   --go to write byte
            ELSE                             --read command
              report "switching to rd following command $" & to_hexstring(addr_rw);
              sda_int <= '1';                --release sda from incoming data
              state <= rd;                   --go to read byte
            END IF;
          WHEN wr =>                         --write byte of transaction
--            report "writing data bit " & integer'image(bit_cnt) & " of $" & to_hexstring(data_tx) & " as " & std_logic'image(sda_int);
            busy <= '1';                     --resume busy if continuous mode
            IF(bit_cnt = 0) THEN             --write byte transmit finished
              sda_int <= '1';                --release sda for slave acknowledge
              bit_cnt <= 7;                  --reset bit counter for "byte" states
              state <= slv_ack2;             --go to slave acknowledge (write)
            ELSE                             --next clock cycle of write state
              bit_cnt <= bit_cnt - 1;        --keep track of transaction bits
              sda_int <= data_tx(bit_cnt-1); --write next bit to bus
              state <= wr;                   --continue writing
            END IF;
          WHEN rd =>                         --read byte of transaction
--            report "reading data bit " & integer'image(bit_cnt);
            busy <= '1';                     --resume busy if continuous mode
            IF(bit_cnt = 0) THEN             --read byte receive finished
              IF(ena = '1' AND addr_rw = addr & rw) THEN  --continuing with another read at same address
                sda_int <= '0';              --acknowledge the byte has been received
              ELSE                           --stopping or continuing with a write
                sda_int <= '1';              --send a no-acknowledge (before stop or repeated start)
              END IF;
              bit_cnt <= 7;                  --reset bit counter for "byte" states
              data_rd <= data_rx;            --output received data
              report "Read byte $" & to_hexstring(data_rx);
              state <= mstr_ack;             --go to master acknowledge
            ELSE                             --next clock cycle of read state
              bit_cnt <= bit_cnt - 1;        --keep track of transaction bits
              state <= rd;                   --continue reading
            END IF;
          WHEN slv_ack2 =>                   --slave acknowledge bit (write)
            IF(ena = '1') THEN               --continue transaction
              latch_toggle <= not latch_toggle_int;
              latch_toggle_int <= not latch_toggle_int;
              busy <= '0';                   --continue is accepted
              addr_rw <= addr & rw;          --collect requested slave address and command
              data_tx <= data_wr;            --collect requested data to write
              report "Writing byte $" & to_hexstring(data_wr) & " via slave_ack2";
              if addr_rw = addr & rw THEN   --continue transaction with
                                                        --another write
                sda_int <= data_wr(bit_cnt); --write first bit of data
                report "re-trigging byte write, because ena is still high";
                state <= wr;                 --go to write byte
              ELSE                           --continue transaction with a read or new slave
                report "repeating start, because target differs";
                state <= start;              --go to repeated start
              END IF;
            ELSE                             --complete transaction
              report "stopping";
              state <= stop;                 --go to stop bit
            END IF;
          WHEN mstr_ack =>                   --master acknowledge bit after a read
            IF(ena = '1') THEN               --continue transaction
              latch_toggle <= not latch_toggle_int;
              latch_toggle_int <= not latch_toggle_int;
              busy <= '0';                   --continue is accepted and data received is available on bus
              addr_rw <= addr & rw;          --collect requested slave address and command
              data_tx <= data_wr;            --collect requested data to write
              if addr_rw = addr & rw THEN   --continue transaction with another
                                                   --read (or write PGS)
                sda_int <= '1';              --release sda from incoming data
                state <= rd;                 --go to read byte
              ELSE                           --continue transaction with a write or new slave
                state <= start;              --repeated start
                report "Repeating start";
              END IF;    
            ELSE                             --complete transaction
              state <= stop;                 --go to stop bit
              report "Stopping";
            END IF;
          WHEN stop =>                       --stop bit of transaction
            busy <= '0';                     --unflag busy
            state <= ready;                  --go to idle state
        END CASE;    
      ELSIF(data_clk = '0' AND data_clk_prev = '1') THEN  --data clock falling edge
        CASE state IS
          WHEN start =>                  
            IF(scl_ena = '0') THEN                  --starting new transaction
              scl_ena <= '1';                       --enable scl output
              ack_error <= '0';                     --reset acknowledge error output
            END IF;
          WHEN slv_ack1 =>                          --receiving slave acknowledge (command)
            IF(sda /= '0' OR ack_error = '1') THEN  --no-acknowledge or previous no-acknowledge
              ack_error <= '1';                     --set error output if no-acknowledge
            END IF;
          WHEN rd =>                                --receiving slave data
            data_rx(bit_cnt) <= sda;                --receive current slave data bit
          WHEN slv_ack2 =>                          --receiving slave acknowledge (write)
            IF(sda /= '0' OR ack_error = '1') THEN  --no-acknowledge or previous no-acknowledge
              ack_error <= '1';                     --set error output if no-acknowledge
            END IF;
          WHEN stop =>
            scl_ena <= '0';                         --disable scl
          WHEN OTHERS =>
            NULL;
        END CASE;
      END IF;
    END IF;
  END PROCESS;  

  --set sda output
  WITH state SELECT
    sda_ena_n <= data_clk_prev WHEN start,     --generate start condition
                 NOT data_clk_prev WHEN stop,  --generate stop condition
                 sda_int WHEN OTHERS;          --set to internal sda signal    
      
  --set scl and sda outputs
  scl <= '0' WHEN ( ( (swap='0') and (scl_ena = '1' AND scl_clk = '0'))
                    or ( (swap='1') and (sda_ena_n = '0'))
                   or (debug_scl='1')) ELSE 'Z';
  sda <= '0' WHEN ( ( (swap='1') and (scl_ena = '1' AND scl_clk = '0'))
                    or ( (swap='0') and (sda_ena_n = '0'))
                   or (debug_sda='1')) ELSE 'Z';
  
END logic;
