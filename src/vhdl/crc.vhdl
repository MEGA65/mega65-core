--------------------------------------------------------------------------------
-- CRC GENERATOR
-- Computes the CRC32 (802.3) for the input byte stream. Assert D_VALID to load
-- each byte for calculation. LOAD_INIT should be asserted at the beginning of a     
-- data stream in order to prime with CRC generator with 32'hFFFFFFFF   
-- which will cause the initial 32 bits in to be complemented as per 802.3.
--
-- IO DESCRIPTION
-- Clock: 100MHz Clock
-- Reset: Active high reset
-- Data: 8Bit Data In
-- Load Init: Asserted for one clock period, loads the CRC gen with 32'hFFFFFFFF
-- Calc: Asserted to enable calculation of the CRC.
-- D_valid: Asserted for one clock period, loads in the next byte on DATA.
--           
-- @author         Peter A Bennett
-- @copyright      (c) 2012 Peter A Bennett
-- @version        $Rev: 2 $
-- @lastrevision   $Date: 2012-03-11 15:19:25 +0000 (Sun, 11 Mar 2012) $
-- @license        LGPL      
-- @email          pab850@googlemail.com
-- @contact        www.bytebash.com
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.debugtools.all;

entity CRC is
  generic ( debug : in boolean := false);
  Port (  CLOCK               :   in  std_logic;
          RESET               :   in  std_logic;
          DATA                :   in  std_logic_vector(7 downto 0);
          LOAD_INIT           :   in  std_logic;
          CALC                :   in  std_logic;
          D_VALID             :   in  std_logic;
          CRC                 :   out std_logic_vector(7 downto 0);
          CRC_REG             :   out std_logic_vector(31 downto 0);
          CRC_VALID           :   out std_logic
          );
end CRC;

architecture RTL of CRC is
  -- Block Diagram for Parallel CRC-32 generation.
  -- (Based on Xilinx CRC App Note)
  -- http://www.xilinx.com/support/documentation/application_notes/xapp209.pdf     
  -- Data In is byte reversed internally as per the requirements of the easics comb CRC block.

  -- 
  -- The "8-bit CRC Out" register always contains the bit-reversed and complimented most 
  -- significant bits of the "32-bit CRC" register. The final IEEE 802.3 FCS can be read from the 
  -- "8-bit CRC Out" register by asserting d_valid four times after the de-assertion of calc
  --
  --        +--------------------------------------+-----------------------------------+
  --        |                                      |    _____                          |
  --        |     comb_crc_gen      next_crc(23:0) |   |     \                         +--->CRC_REG(31:0)
  --        |   +---------------+          & x"FF" +-->|00    \           +-----+      |
  --        +-->| Combinatorial |--------------------->|01     \__________|D   Q|______|
  --D(7:0) >--->| Next CRC Gen  |        xFFFFFFFF---->|10     /   +--|---|En   |                
  --            +---------------+        xFFFFFFFF---->|11    /    |  |   +-----+    ____    +-----+
  --                              (complements first   |_____/     |  +------------>| =  |-->|D   Q|--> VALID_REG
  --                               32 bits of frame)    | |        |   residue ---->|____| +-|En   |
  --load_init >----------------------+------------------+ |        |   xC704DD7B           | +-----+
  --calc      >-----------+          |                    |        |                       |
  --d_valid   >-------+   |    _     |                    |        |-----------------------+
  --                  |   +---|x\____|____________________|        |
  --                  +---|---|_/    |    _                        |      
  --                  |   |          +---|+\_______________________|       
  --                  +---|----------+---|_/                               
  --                      |          |
  --                      |          +------------------------------------+
  --                      |                  ________              ____   |  +-----+
  --                      |                  crc_reg (16:23)>-----|0    \ +--|En   | 
  --                      |                  ________             |      \___|D   Q|------>CRC(7:0)
  --                      |                  next_crc(24:31)>-----|1     /   +-----+ 
  --                      |                                       |_____/
  --                      |                                          | 
  --                      +------------------------------------------+
  
  
  -- First, the data stream and CRC of the received frame are sent through the circuit. 
  -- Then the value left in the CRC-32 registers can be compared with a constant, commonly
  -- referred to as the residue. In this implementation, the value of the residue is 0xC704DD7B
  -- when no CRC errors are detected. (Xilinx CRC App Note).
  
  -- CRC32 (Easics generator).
  function comb_crc_gen
    (
      data_in :   std_logic_vector(7 downto 0);
      crc_in  :   std_logic_vector(31 downto 0)
      )
    return std_logic_vector is

    variable d:      std_logic_vector(7 downto 0);
    variable c:      std_logic_vector(31 downto 0);
    variable newcrc: std_logic_vector(31 downto 0);

  begin
    d := data_in;
    c := crc_in;
    -- Easics
    newcrc(0) := d(6) xor d(0) xor c(24) xor c(30);
    newcrc(1) := d(7) xor d(6) xor d(1) xor d(0) xor c(24) xor c(25) xor c(30) xor c(31);
    newcrc(2) := d(7) xor d(6) xor d(2) xor d(1) xor d(0) xor c(24) xor c(25) xor c(26) xor c(30) xor c(31);
    newcrc(3) := d(7) xor d(3) xor d(2) xor d(1) xor c(25) xor c(26) xor c(27) xor c(31);
    newcrc(4) := d(6) xor d(4) xor d(3) xor d(2) xor d(0) xor c(24) xor c(26) xor c(27) xor c(28) xor c(30);
    newcrc(5) := d(7) xor d(6) xor d(5) xor d(4) xor d(3) xor d(1) xor d(0) xor c(24) xor c(25) xor c(27) xor c(28) xor c(29) xor c(30) xor c(31);
    newcrc(6) := d(7) xor d(6) xor d(5) xor d(4) xor d(2) xor d(1) xor c(25) xor c(26) xor c(28) xor c(29) xor c(30) xor c(31);
    newcrc(7) := d(7) xor d(5) xor d(3) xor d(2) xor d(0) xor c(24) xor c(26) xor c(27) xor c(29) xor c(31);
    newcrc(8) := d(4) xor d(3) xor d(1) xor d(0) xor c(0) xor c(24) xor c(25) xor c(27) xor c(28);
    newcrc(9) := d(5) xor d(4) xor d(2) xor d(1) xor c(1) xor c(25) xor c(26) xor c(28) xor c(29);
    newcrc(10) := d(5) xor d(3) xor d(2) xor d(0) xor c(2) xor c(24) xor c(26) xor c(27) xor c(29);
    newcrc(11) := d(4) xor d(3) xor d(1) xor d(0) xor c(3) xor c(24) xor c(25) xor c(27) xor c(28);
    newcrc(12) := d(6) xor d(5) xor d(4) xor d(2) xor d(1) xor d(0) xor c(4) xor c(24) xor c(25) xor c(26) xor c(28) xor c(29) xor c(30);
    newcrc(13) := d(7) xor d(6) xor d(5) xor d(3) xor d(2) xor d(1) xor c(5) xor c(25) xor c(26) xor c(27) xor c(29) xor c(30) xor c(31);
    newcrc(14) := d(7) xor d(6) xor d(4) xor d(3) xor d(2) xor c(6) xor c(26) xor c(27) xor c(28) xor c(30) xor c(31);
    newcrc(15) := d(7) xor d(5) xor d(4) xor d(3) xor c(7) xor c(27) xor c(28) xor c(29) xor c(31);
    newcrc(16) := d(5) xor d(4) xor d(0) xor c(8) xor c(24) xor c(28) xor c(29);
    newcrc(17) := d(6) xor d(5) xor d(1) xor c(9) xor c(25) xor c(29) xor c(30);
    newcrc(18) := d(7) xor d(6) xor d(2) xor c(10) xor c(26) xor c(30) xor c(31);
    newcrc(19) := d(7) xor d(3) xor c(11) xor c(27) xor c(31);
    newcrc(20) := d(4) xor c(12) xor c(28);
    newcrc(21) := d(5) xor c(13) xor c(29);
    newcrc(22) := d(0) xor c(14) xor c(24);
    newcrc(23) := d(6) xor d(1) xor d(0) xor c(15) xor c(24) xor c(25) xor c(30);
    newcrc(24) := d(7) xor d(2) xor d(1) xor c(16) xor c(25) xor c(26) xor c(31);
    newcrc(25) := d(3) xor d(2) xor c(17) xor c(26) xor c(27);
    newcrc(26) := d(6) xor d(4) xor d(3) xor d(0) xor c(18) xor c(24) xor c(27) xor c(28) xor c(30);
    newcrc(27) := d(7) xor d(5) xor d(4) xor d(1) xor c(19) xor c(25) xor c(28) xor c(29) xor c(31);
    newcrc(28) := d(6) xor d(5) xor d(2) xor c(20) xor c(26) xor c(29) xor c(30);
    newcrc(29) := d(7) xor d(6) xor d(3) xor c(21) xor c(27) xor c(30) xor c(31);
    newcrc(30) := d(7) xor d(4) xor c(22) xor c(28) xor c(31);
    newcrc(31) := d(5) xor c(23) xor c(29);
    return newcrc;
  end comb_crc_gen;
  
  -- Reverse the input vector.
  function reversed(slv: std_logic_vector) return std_logic_vector is
    variable result: std_logic_vector(slv'reverse_range);
  begin
    for i in slv'range loop
      result(i) := slv(i);
    end loop;
    return result;
  end reversed;
  
  
  -- Magic number for the CRC generator.    
  constant c_crc_residue  : std_logic_vector(31 downto 0) := x"C704DD7B";
  signal s_next_crc       : std_logic_vector(31 downto 0) := (others => '0');
  signal s_crc_reg        : std_logic_vector(31 downto 0) := (others => '0');
  signal s_crc            : std_logic_vector(7 downto 0)  := (others => '0');
  signal s_reversed_byte  : std_logic_vector(7 downto 0) := (others => '0');
  signal s_crc_valid      : std_logic := '0';
  
begin

  CRC         <= s_crc;
  CRC_REG     <= s_crc_reg;
  CRC_VALID   <= s_crc_valid;
  
  BYTE_REVERSE : process (DATA)
  -- Nibble swapped and Bit reversed version of DATA
  begin
    --s_reversed_byte <= reversed(DATA(3 downto 0) & DATA(7 downto 4));
    s_reversed_byte <= reversed(DATA);
  end process;

  COMB_NEXT_CRC_GEN : process (s_reversed_byte, s_crc_reg)
  begin
    s_next_crc    <= comb_crc_gen(s_reversed_byte, s_crc_reg);
  end process COMB_NEXT_CRC_GEN;
  
  CRC_GEN : process (CLOCK)
    variable state : std_logic_vector(2 downto 0);
  begin
    if rising_edge(CLOCK) then
--          report "CRC s_crc_reg = $" & to_hstring(s_crc_reg);
--          report "CRC  reversed  $" & to_hstring(reversed(s_crc_reg));
      if RESET = '1' then
        s_crc_reg    <= (others => '0');
        s_crc        <= (others => '0');
        s_crc_valid  <= '0';
        state        := (others => '0');
      else
        state        := LOAD_INIT & CALC & D_VALID;
        if debug and state/= "000" then
          report "CRC: state = " & to_string(state);
        end if;
        case state is
          when "000" =>
          -- No change.
          when "001" =>
            if debug then
              report "CRC incorporating byte $" & to_hstring(DATA) & ", crc before incorporation = $" & to_hstring(s_next_crc);                        s_crc_reg   <= s_crc_reg(23 downto 0) & x"FF";
            end if;
            s_crc       <= not reversed(s_crc_reg(23 downto 16));    
          when "010" =>
          -- No Change                        
          when "011" =>
            if debug then
              report "CRC incorporating byte $" & to_hstring(DATA) & ", crc before incorporation = $" & to_hstring(s_next_crc);
            end if;
            s_crc_reg   <= s_next_crc;
            s_crc       <= not reversed(s_next_crc(31 downto 24));   
          when "100" =>
            s_crc_reg   <= x"FFFFFFFF";
          when "101" =>
            s_crc_reg   <= x"FFFFFFFF";
            s_crc       <= not reversed(s_crc_reg(23 downto 16));
          when "110" =>
            s_crc_reg   <= x"FFFFFFFF";
          when "111" =>
            s_crc_reg   <= x"FFFFFFFF";
            s_crc       <= not reversed(s_next_crc(31 downto 24));
          when others =>
            null;
        end case;
        if c_crc_residue = s_crc_reg then
          if debug then
            report "CRC: CRC is valid";
          end if;
          s_crc_valid <= '1';
        else
          s_crc_valid <= '0'; 
        end if;
      end if;
    end if;
  end process CRC_GEN;
end RTL;
