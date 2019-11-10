----------------------------------------------------------------------------------
-- Engineer:    Mike Field <hamster@snap.net.nz> 
-- Module Name: colour_space_conversion - Behavioral 
-- 
-- Description: Convert the input pixel data into YCbCr 422 values
--
-- Feel free to use this how you see fit, and fix any errors you find :-)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
Library UNISIM;
use UNISIM.vcomponents.all;

entity colour_space_conversion is
    Port (  clk : in  STD_LOGIC;
            r1_in        : IN std_logic_vector(8 downto 0);
            g1_in        : IN std_logic_vector(8 downto 0);
            b1_in        : IN std_logic_vector(8 downto 0);
            r2_in        : IN std_logic_vector(8 downto 0);
            g2_in        : IN std_logic_vector(8 downto 0);
            b2_in        : IN std_logic_vector(8 downto 0);
            pair_start_in: IN std_logic;
            de_in        : IN std_logic;
            vsync_in     : IN std_logic;
            hsync_in     : IN std_logic;
      
            y_out     : OUT std_logic_vector(7 downto 0);
            c_out     : OUT std_logic_vector(7 downto 0);
            de_out    : OUT std_logic;
            hsync_out : OUT std_logic;
            vsync_out : OUT std_logic
   );
end colour_space_conversion;

architecture Behavioral of colour_space_conversion is
   signal d_a : std_logic;
   signal h_a : std_logic;
   signal v_a : std_logic;
   
   signal c1                 : STD_LOGIC_VECTOR(47 DOWNTO 0);
   signal a_r1,  a_g1,  a_b1 : STD_LOGIC_VECTOR(29 DOWNTO 0);
   signal b_r1,  b_g1,  b_b1 : STD_LOGIC_VECTOR(17 DOWNTO 0);
   signal pc_r1, pc_g1, p_b1 : STD_LOGIC_VECTOR(47 DOWNTO 0);

   signal c2                 : STD_LOGIC_VECTOR(47 DOWNTO 0);
   signal a_r2,  a_g2 , a_b2 : STD_LOGIC_VECTOR(29 DOWNTO 0);
   signal b_r2,  b_g2,  b_b2 : STD_LOGIC_VECTOR(17 DOWNTO 0);
   signal pc_r2, pc_g2, p_b2 : STD_LOGIC_VECTOR(47 DOWNTO 0);

   signal hs_delay : STD_LOGIC_VECTOR(3 DOWNTO 0) := (others => '0');
   signal vs_delay : STD_LOGIC_VECTOR(3 DOWNTO 0) := (others => '0');
   signal de_delay : STD_LOGIC_VECTOR(3 DOWNTO 0) := (others => '0');



begin

   
   --  y = ( 8432 * r + 16425 * g +  3176 * B) / 32768 + 16;
   -- cb = (-4818 * r -  9527 * g + 14345 * B) / 32768 + 128;
   -- cr = (14345 * r - 12045 * g -  2300 * B) / 32768 + 128; 

   c1   <= x"002000000000";  
   a_r1 <= "000000" & r1_in & x"000" & "000";
   a_g1 <= "000000" & g1_in & x"000" & "000";
   a_b1 <= "000000" & b1_in & x"000" & "000";

   c2   <= x"010000000000";  
   a_r2 <= "000000" & r2_in & x"000" & "000";
   a_g2 <= "000000" & g2_in & x"000" & "000";
   a_b2 <= "000000" & b2_in & x"000" & "000";

   
   b_r1 <= x"20F0"&"00";
   b_g1 <= x"4029"&"00";
   b_b1 <= x"0C68"&"00";

   b_r2 <= x"ED2E"&"00" when pair_start_in = '1' else x"3809"&"00";
   b_g2 <= x"DAC9"&"00" when pair_start_in = '1' else x"D0F3"&"00";
   b_b2 <= x"3809"&"00" when pair_start_in = '1' else x"F704"&"00";

process(clk)
   begin
      if rising_edge(clk) then
         hsync_out <= hs_delay(hs_delay'high);
         vsync_out <= vs_delay(vs_delay'high);
         de_out    <= de_delay(de_delay'high);
         
         de_delay  <= de_delay(de_delay'high-1 downto 0) & de_in;
         vs_delay  <= vs_delay(de_delay'high-1 downto 0) & vsync_in;
         hs_delay  <= hs_delay(de_delay'high-1 downto 0) & hsync_in;

         y_out <= p_b1(40 downto 33);
         c_out <= p_b2(40 downto 33);


      end if;
   end process;
mult_r1 : DSP48E1
   generic map (
      -- Feature Control Attributes: Data Path Selection
      A_INPUT => "DIRECT",               -- Selects A input source, "DIRECT" (A port) or "CASCADE" (ACIN port)
      B_INPUT => "DIRECT",               -- Selects B input source, "DIRECT" (B port) or "CASCADE" (BCIN port)
      USE_DPORT => FALSE,                -- Select D port usage (TRUE or FALSE)
      USE_MULT => "MULTIPLY",            -- Select multiplier usage ("MULTIPLY", "DYNAMIC", or "NONE")
      USE_SIMD => "ONE48",               -- SIMD selection ("ONE48", "TWO24", "FOUR12")
      -- Pattern Detector Attributes: Pattern Detection Configuration
      AUTORESET_PATDET => "NO_RESET",    -- "NO_RESET", "RESET_MATCH", "RESET_NOT_MATCH" 
      MASK => X"3fffffffffff",           -- 48-bit mask value for pattern detect (1=ignore)
      PATTERN => X"000000000000",        -- 48-bit pattern match for pattern detect
      SEL_MASK => "MASK",                -- "C", "MASK", "ROUNDING_MODE1", "ROUNDING_MODE2" 
      SEL_PATTERN => "PATTERN",          -- Select pattern value ("PATTERN" or "C")
      USE_PATTERN_DETECT => "NO_PATDET", -- Enable pattern detect ("PATDET" or "NO_PATDET")
      -- Register Control Attributes: Pipeline Register Configuration
      ACASCREG => 0,                     -- Number of pipeline stages between A/ACIN and ACOUT (0, 1 or 2)
      ADREG => 0,                        -- Number of pipeline stages for pre-adder (0 or 1)
      ALUMODEREG => 1,                   -- Number of pipeline stages for ALUMODE (0 or 1)
      AREG => 0,                         -- Number of pipeline stages for A (0, 1 or 2)
      BCASCREG => 0,                     -- Number of pipeline stages between B/BCIN and BCOUT (0, 1 or 2)
      BREG => 0,                         -- Number of pipeline stages for B (0, 1 or 2)
      CARRYINREG => 1,                   -- Number of pipeline stages for CARRYIN (0 or 1)
      CARRYINSELREG => 1,                -- Number of pipeline stages for CARRYINSEL (0 or 1)
      CREG => 0,                         -- Number of pipeline stages for C (0 or 1)
      DREG => 0,                         -- Number of pipeline stages for D (0 or 1)
      INMODEREG => 1,                    -- Number of pipeline stages for INMODE (0 or 1)
      MREG => 1,                         -- Number of multiplier pipeline stages (0 or 1)
      OPMODEREG => 1,                    -- Number of pipeline stages for OPMODE (0 or 1)
      PREG => 1                          -- Number of pipeline stages for P (0 or 1)
   )
   port map (
      -- Cascade: 30-bit (each) output: Cascade Ports
      ACOUT        => open,    -- 30-bit output: A port cascade output
      BCOUT        => open,    -- 18-bit output: B port cascade output
      CARRYCASCOUT => open,    -- 1-bit output: Cascade carry output
      MULTSIGNOUT  => open,    -- 1-bit output: Multiplier sign cascade output
      PCOUT        => PC_r1,   -- 48-bit output: Cascade output
      -- Control: 1-bit (each) output: Control Inputs/Status Bits
      OVERFLOW       => open,  -- 1-bit output: Overflow in add/acc output
      PATTERNBDETECT => open,  -- 1-bit output: Pattern bar detect output
      PATTERNDETECT  => open,  -- 1-bit output: Pattern detect output
      UNDERFLOW      => open,  -- 1-bit output: Underflow in add/acc output
      -- Data: 4-bit (each) output: Data Ports
      CARRYOUT       => open,  -- 4-bit output: Carry output
      P              => open,  -- 48-bit output: Primary data output
      -- Cascade: 30-bit (each) input: Cascade Ports
      ACIN        => (others => '0'), -- 30-bit input: A cascade data input
      BCIN        => (others => '0'), -- 18-bit input: B cascade input
      CARRYCASCIN => '0',             -- 1-bit input: Cascade carry input
      MULTSIGNIN  => '0',             -- 1-bit input: Multiplier sign input
      PCIN        => (others => '0'), -- 48-bit input: P cascade input
      -- Control: 4-bit (each) input: Control Inputs/Status Bits
      CLK        => CLK,        -- 1-bit input: Clock input
      ALUMODE    => "0000",     -- 4-bit input: ALU control input
      CARRYINSEL => "000",      -- 3-bit input: Carry select input
      CEINMODE   => '1',        -- 1-bit input: Clock enable input for INMODEREG
      INMODE     => "00000",    -- 5-bit input: INMODE control input
      OPMODE     => "0110101",  -- 7-bit input: Operation mode input
      RSTINMODE  => '0',           -- 1-bit input: Reset input for INMODEREG
      -- Data: 30-bit (each) input: Data Ports
      A => a_r1,      -- 30-bit input: A data input
      B => b_r1,                        -- 18-bit input: B data input
      C => c1,              -- 48-bit input: C data input
      CARRYIN => '0',                   -- 1-bit input: Carry input signal
      D => (others =>'0'),              -- 25-bit input: D data input
      -- Reset/Clock Enable: 1-bit (each) input: Reset/Clock Enable Inputs
      CEA1 => '0',                     -- 1-bit input: Clock enable input for 1st stage AREG
      CEA2 => '0',                     -- 1-bit input: Clock enable input for 2nd stage AREG
      CEAD => '0',                     -- 1-bit input: Clock enable input for ADREG
      CEALUMODE => '1',           -- 1-bit input: Clock enable input for ALUMODE
      CEB1 => '0',                     -- 1-bit input: Clock enable input for 1st stage BREG
      CEB2 => '0',                     -- 1-bit input: Clock enable input for 2nd stage BREG
      CEC => '0',                       -- 1-bit input: Clock enable input for CREG
      CECARRYIN => '1',           -- 1-bit input: Clock enable input for CARRYINREG
      CECTRL => '1',                 -- 1-bit input: Clock enable input for OPMODEREG and CARRYINSELREG
      CED => '0',                       -- 1-bit input: Clock enable input for DREG
      CEM => '1',                       -- 1-bit input: Clock enable input for MREG
      CEP => '1',                       -- 1-bit input: Clock enable input for PREG
      RSTA => '0',                     -- 1-bit input: Reset input for AREG
      RSTALLCARRYIN => '0',   -- 1-bit input: Reset input for CARRYINREG
      RSTALUMODE => '0',         -- 1-bit input: Reset input for ALUMODEREG
      RSTB => '0',                     -- 1-bit input: Reset input for BREG
      RSTC => '0',                     -- 1-bit input: Reset input for CREG
      RSTCTRL => '0',               -- 1-bit input: Reset input for OPMODEREG and CARRYINSELREG
      RSTD => '0',                     -- 1-bit input: Reset input for DREG and ADREG
      RSTM => '0',                     -- 1-bit input: Reset input for MREG
      RSTP => '0'                      -- 1-bit input: Reset input for PREG
   );

mult_g1 : DSP48E1
   generic map (
      -- Feature Control Attributes: Data Path Selection
      A_INPUT => "DIRECT",               -- Selects A input source, "DIRECT" (A port) or "CASCADE" (ACIN port)
      B_INPUT => "DIRECT",               -- Selects B input source, "DIRECT" (B port) or "CASCADE" (BCIN port)
      USE_DPORT => FALSE,                -- Select D port usage (TRUE or FALSE)
      USE_MULT => "MULTIPLY",            -- Select multiplier usage ("MULTIPLY", "DYNAMIC", or "NONE")
      USE_SIMD => "ONE48",               -- SIMD selection ("ONE48", "TWO24", "FOUR12")
      -- Pattern Detector Attributes: Pattern Detection Configuration
      AUTORESET_PATDET => "NO_RESET",    -- "NO_RESET", "RESET_MATCH", "RESET_NOT_MATCH" 
      MASK => X"3fffffffffff",           -- 48-bit mask value for pattern detect (1=ignore)
      PATTERN => X"000000000000",        -- 48-bit pattern match for pattern detect
      SEL_MASK => "MASK",                -- "C", "MASK", "ROUNDING_MODE1", "ROUNDING_MODE2" 
      SEL_PATTERN => "PATTERN",          -- Select pattern value ("PATTERN" or "C")
      USE_PATTERN_DETECT => "NO_PATDET", -- Enable pattern detect ("PATDET" or "NO_PATDET")
      -- Register Control Attributes: Pipeline Register Configuration
      ACASCREG => 1,                     -- Number of pipeline stages between A/ACIN and ACOUT (0, 1 or 2)
      ADREG => 0,                        -- Number of pipeline stages for pre-adder (0 or 1)
      ALUMODEREG => 1,                   -- Number of pipeline stages for ALUMODE (0 or 1)
      AREG => 1,                         -- Number of pipeline stages for A (0, 1 or 2)
      BCASCREG => 1,                     -- Number of pipeline stages between B/BCIN and BCOUT (0, 1 or 2)
      BREG => 1,                         -- Number of pipeline stages for B (0, 1 or 2)
      CARRYINREG => 1,                   -- Number of pipeline stages for CARRYIN (0 or 1)
      CARRYINSELREG => 1,                -- Number of pipeline stages for CARRYINSEL (0 or 1)
      CREG => 0,                         -- Number of pipeline stages for C (0 or 1)
      DREG => 0,                         -- Number of pipeline stages for D (0 or 1)
      INMODEREG => 1,                    -- Number of pipeline stages for INMODE (0 or 1)
      MREG => 1,                         -- Number of multiplier pipeline stages (0 or 1)
      OPMODEREG => 1,                    -- Number of pipeline stages for OPMODE (0 or 1)
      PREG => 1                          -- Number of pipeline stages for P (0 or 1)
   )
   port map (
      -- Cascade: 30-bit (each) input: Cascade Ports
      ACOUT        => open,    -- 30-bit output: A port cascade output
      BCOUT        => open,    -- 18-bit output: B port cascade output
      CARRYCASCOUT => open,    -- 1-bit output: Cascade carry output
      MULTSIGNOUT  => open,    -- 1-bit output: Multiplier sign cascade output
      PCOUT        => PC_g1,   -- 48-bit output: Cascade output
      -- Control: 1-bit (each) output: Control Inputs/Status Bits
      OVERFLOW       => open,  -- 1-bit output: Overflow in add/acc output
      PATTERNBDETECT => open,  -- 1-bit output: Pattern bar detect output
      PATTERNDETECT  => open,  -- 1-bit output: Pattern detect output
      UNDERFLOW      => open,  -- 1-bit output: Underflow in add/acc output
      -- Data: 4-bit (each) output: Data Ports
      CARRYOUT       => open,  -- 4-bit output: Carry output
      P              => open,  -- 48-bit output: Primary data output
      -- Cascade: 30-bit (each) input: Cascade Ports
      ACIN        => (others => '0'),       -- 30-bit input: A cascade data input
      BCIN        => (others => '0'),       -- 18-bit input: B cascade input
      CARRYCASCIN => '0',       -- 1-bit input: Cascade carry input
      MULTSIGNIN  => '0',       -- 1-bit input: Multiplier sign input
      PCIN        => pc_r1,       -- 48-bit input: P cascade input
      -- Control: 4-bit (each) input: Control Inputs/Status Bits
      CLK        => CLK,        -- 1-bit input: Clock input
      ALUMODE    => "0000",     -- 4-bit input: ALU control input
      CARRYINSEL => "000",      -- 3-bit input: Carry select input
      CEINMODE   => '1',        -- 1-bit input: Clock enable input for INMODEREG
      INMODE     => "00000",                -- 5-bit input: INMODE control input
      OPMODE     => "0010101",                 -- 7-bit input: Operation mode input
      RSTINMODE  => '0',           -- 1-bit input: Reset input for INMODEREG
      -- Data: 30-bit (each) input: Data Ports
      A => a_g1,                        -- 30-bit input: A data input
      B => b_g1,                        -- 18-bit input: B data input
      C => (others =>'0'),              -- 48-bit input: C data input
      CARRYIN => '0',                   -- 1-bit input: Carry input signal
      D => (others =>'0'),              -- 25-bit input: D data input
      -- Reset/Clock Enable: 1-bit (each) input: Reset/Clock Enable Inputs
      CEA1 => '0',                     -- 1-bit input: Clock enable input for 1st stage AREG
      CEA2 => '1',                     -- 1-bit input: Clock enable input for 2nd stage AREG
      CEAD => '1',                     -- 1-bit input: Clock enable input for ADREG
      CEALUMODE => '1',           -- 1-bit input: Clock enable input for ALUMODE
      CEB1 => '0',                     -- 1-bit input: Clock enable input for 1st stage BREG
      CEB2 => '1',                     -- 1-bit input: Clock enable input for 2nd stage BREG
      CEC => '0',                       -- 1-bit input: Clock enable input for CREG
      CECARRYIN => '1',           -- 1-bit input: Clock enable input for CARRYINREG
      CECTRL => '1',                 -- 1-bit input: Clock enable input for OPMODEREG and CARRYINSELREG
      CED => '0',                       -- 1-bit input: Clock enable input for DREG
      CEM => '1',                       -- 1-bit input: Clock enable input for MREG
      CEP => '1',                       -- 1-bit input: Clock enable input for PREG
      RSTA => '0',                     -- 1-bit input: Reset input for AREG
      RSTALLCARRYIN => '0',   -- 1-bit input: Reset input for CARRYINREG
      RSTALUMODE => '0',         -- 1-bit input: Reset input for ALUMODEREG
      RSTB => '0',                     -- 1-bit input: Reset input for BREG
      RSTC => '0',                     -- 1-bit input: Reset input for CREG
      RSTCTRL => '0',               -- 1-bit input: Reset input for OPMODEREG and CARRYINSELREG
      RSTD => '0',                     -- 1-bit input: Reset input for DREG and ADREG
      RSTM => '0',                     -- 1-bit input: Reset input for MREG
      RSTP => '0'                      -- 1-bit input: Reset input for PREG
   );

mult_b1 : DSP48E1
   generic map (
      -- Feature Control Attributes: Data Path Selection
      A_INPUT => "DIRECT",               -- Selects A input source, "DIRECT" (A port) or "CASCADE" (ACIN port)
      B_INPUT => "DIRECT",               -- Selects B input source, "DIRECT" (B port) or "CASCADE" (BCIN port)
      USE_DPORT => FALSE,                -- Select D port usage (TRUE or FALSE)
      USE_MULT => "MULTIPLY",            -- Select multiplier usage ("MULTIPLY", "DYNAMIC", or "NONE")
      USE_SIMD => "ONE48",               -- SIMD selection ("ONE48", "TWO24", "FOUR12")
      -- Pattern Detector Attributes: Pattern Detection Configuration
      AUTORESET_PATDET => "NO_RESET",    -- "NO_RESET", "RESET_MATCH", "RESET_NOT_MATCH" 
      MASK => X"3fffffffffff",           -- 48-bit mask value for pattern detect (1=ignore)
      PATTERN => X"000000000000",        -- 48-bit pattern match for pattern detect
      SEL_MASK => "MASK",                -- "C", "MASK", "ROUNDING_MODE1", "ROUNDING_MODE2" 
      SEL_PATTERN => "PATTERN",          -- Select pattern value ("PATTERN" or "C")
      USE_PATTERN_DETECT => "NO_PATDET", -- Enable pattern detect ("PATDET" or "NO_PATDET")
      -- Register Control Attributes: Pipeline Register Configuration
      ACASCREG => 2,                     -- Number of pipeline stages between A/ACIN and ACOUT (0, 1 or 2)
      ADREG => 0,                        -- Number of pipeline stages for pre-adder (0 or 1)
      ALUMODEREG => 1,                   -- Number of pipeline stages for ALUMODE (0 or 1)
      AREG => 2,                         -- Number of pipeline stages for A (0, 1 or 2)
      BCASCREG => 1,                     -- Number of pipeline stages between B/BCIN and BCOUT (0, 1 or 2)
      BREG => 1,                         -- Number of pipeline stages for B (0, 1 or 2)
      CARRYINREG => 1,                   -- Number of pipeline stages for CARRYIN (0 or 1)
      CARRYINSELREG => 1,                -- Number of pipeline stages for CARRYINSEL (0 or 1)
      CREG => 0,                         -- Number of pipeline stages for C (0 or 1)
      DREG => 0,                         -- Number of pipeline stages for D (0 or 1)
      INMODEREG => 1,                    -- Number of pipeline stages for INMODE (0 or 1)
      MREG => 1,                         -- Number of multiplier pipeline stages (0 or 1)
      OPMODEREG => 1,                    -- Number of pipeline stages for OPMODE (0 or 1)
      PREG => 1                          -- Number of pipeline stages for P (0 or 1)
   )
   port map (
      -- Cascade: 30-bit (each) output: Cascade Ports
      ACOUT        => open,          -- 30-bit output: A port cascade output
      BCOUT        => open,          -- 18-bit output: B port cascade output
      CARRYCASCOUT => open,          -- 1-bit output: Cascade carry output
      MULTSIGNOUT  => open,          -- 1-bit output: Multiplier sign cascade output
      PCOUT        => open,          -- 48-bit output: Cascade output
      -- Control: 1-bit (each) output: Control Inputs/Status Bits
      OVERFLOW       => open,        -- 1-bit output: Overflow in add/acc output
      PATTERNBDETECT => open,        -- 1-bit output: Pattern bar detect output
      PATTERNDETECT  => open,        -- 1-bit output: Pattern detect output
      UNDERFLOW      => open,        -- 1-bit output: Underflow in add/acc output
      -- Data: 4-bit (each) output: Data Ports
      CARRYOUT       => open,        -- 4-bit output: Carry output
      P              => P_b1,        -- 48-bit output: Primary data output
      -- Cascade: 30-bit (each) input: Cascade Ports
      ACIN        => (others =>'0'), -- 30-bit input: A cascade data input
      BCIN        => (others =>'0'), -- 18-bit input: B cascade input
      CARRYCASCIN => '0',            -- 1-bit input: Cascade carry input
      MULTSIGNIN  => '0',            -- 1-bit input: Multiplier sign input
      PCIN        => pc_g1,          -- 48-bit input: P cascade input
      -- Control: 4-bit (each) input: Control Inputs/Status Bits
      CLK        => CLK,            -- 1-bit input: Clock input
      ALUMODE    => "0000",         -- 4-bit input: ALU control input
      CARRYINSEL => "000",          -- 3-bit input: Carry select input
      CEINMODE   => '1',            -- 1-bit input: Clock enable input for INMODEREG
      INMODE     => "00000",        -- 5-bit input: INMODE control input
      OPMODE     => "0010101",      -- 7-bit input: Operation mode input
      RSTINMODE  => '0',            -- 1-bit input: Reset input for INMODEREG
      -- Data: 30-bit (each) input: Data Ports
      A => a_b1,                    -- 30-bit input: A data input
      B => b_b1,                    -- 18-bit input: B data input
      C => (others =>'0'),          -- 48-bit input: C data input
      CARRYIN => '0',               -- 1-bit input: Carry input signal
      D => (others =>'0'),          -- 25-bit input: D data input
      -- Reset/Clock Enable: 1-bit (each) input: Reset/Clock Enable Inputs
      CEA1 => '1',            -- 1-bit input: Clock enable input for 1st stage AREG
      CEA2 => '1',            -- 1-bit input: Clock enable input for 2nd stage AREG
      CEAD => '0',            -- 1-bit input: Clock enable input for ADREG
      CEALUMODE => '1',       -- 1-bit input: Clock enable input for ALUMODE
      CEB1 => '0',            -- 1-bit input: Clock enable input for 1st stage BREG
      CEB2 => '1',            -- 1-bit input: Clock enable input for 2nd stage BREG
      CEC => '0',             -- 1-bit input: Clock enable input for CREG
      CECARRYIN => '1',       -- 1-bit input: Clock enable input for CARRYINREG
      CECTRL => '1',          -- 1-bit input: Clock enable input for OPMODEREG and CARRYINSELREG
      CED => '0',             -- 1-bit input: Clock enable input for DREG
      CEM => '1',             -- 1-bit input: Clock enable input for MREG
      CEP => '1',             -- 1-bit input: Clock enable input for PREG
      RSTA => '0',            -- 1-bit input: Reset input for AREG
      RSTALLCARRYIN => '0',   -- 1-bit input: Reset input for CARRYINREG
      RSTALUMODE => '0',      -- 1-bit input: Reset input for ALUMODEREG
      RSTB => '0',            -- 1-bit input: Reset input for BREG
      RSTC => '0',            -- 1-bit input: Reset input for CREG
      RSTCTRL => '0',         -- 1-bit input: Reset input for OPMODEREG and CARRYINSELREG
      RSTD => '0',            -- 1-bit input: Reset input for DREG and ADREG
      RSTM => '0',            -- 1-bit input: Reset input for MREG
      RSTP => '0'             -- 1-bit input: Reset input for PREG
   );

-----------------------------------------
mult_r2 : DSP48E1
   generic map (
      -- Feature Control Attributes: Data Path Selection
      A_INPUT => "DIRECT",               -- Selects A input source, "DIRECT" (A port) or "CASCADE" (ACIN port)
      B_INPUT => "DIRECT",               -- Selects B input source, "DIRECT" (B port) or "CASCADE" (BCIN port)
      USE_DPORT => FALSE,                -- Select D port usage (TRUE or FALSE)
      USE_MULT => "MULTIPLY",            -- Select multiplier usage ("MULTIPLY", "DYNAMIC", or "NONE")
      USE_SIMD => "ONE48",               -- SIMD selection ("ONE48", "TWO24", "FOUR12")
      -- Pattern Detector Attributes: Pattern Detection Configuration
      AUTORESET_PATDET => "NO_RESET",    -- "NO_RESET", "RESET_MATCH", "RESET_NOT_MATCH" 
      MASK => X"3fffffffffff",           -- 48-bit mask value for pattern detect (1=ignore)
      PATTERN => X"000000000000",        -- 48-bit pattern match for pattern detect
      SEL_MASK => "MASK",                -- "C", "MASK", "ROUNDING_MODE1", "ROUNDING_MODE2" 
      SEL_PATTERN => "PATTERN",          -- Select pattern value ("PATTERN" or "C")
      USE_PATTERN_DETECT => "NO_PATDET", -- Enable pattern detect ("PATDET" or "NO_PATDET")
      -- Register Control Attributes: Pipeline Register Configuration
      ACASCREG => 0,                     -- Number of pipeline stages between A/ACIN and ACOUT (0, 1 or 2)
      ADREG => 0,                        -- Number of pipeline stages for pre-adder (0 or 1)
      ALUMODEREG => 1,                   -- Number of pipeline stages for ALUMODE (0 or 1)
      AREG => 0,                         -- Number of pipeline stages for A (0, 1 or 2)
      BCASCREG => 0,                     -- Number of pipeline stages between B/BCIN and BCOUT (0, 1 or 2)
      BREG => 0,                         -- Number of pipeline stages for B (0, 1 or 2)
      CARRYINREG => 1,                   -- Number of pipeline stages for CARRYIN (0 or 1)
      CARRYINSELREG => 1,                -- Number of pipeline stages for CARRYINSEL (0 or 1)
      CREG => 0,                         -- Number of pipeline stages for C (0 or 1)
      DREG => 0,                         -- Number of pipeline stages for D (0 or 1)
      INMODEREG => 1,                    -- Number of pipeline stages for INMODE (0 or 1)
      MREG => 1,                         -- Number of multiplier pipeline stages (0 or 1)
      OPMODEREG => 1,                    -- Number of pipeline stages for OPMODE (0 or 1)
      PREG => 1                          -- Number of pipeline stages for P (0 or 1)
   )
   port map (
      -- Cascade: 30-bit (each) output: Cascade Ports
      ACOUT        => open,    -- 30-bit output: A port cascade output
      BCOUT        => open,    -- 18-bit output: B port cascade output
      CARRYCASCOUT => open,    -- 1-bit output: Cascade carry output
      MULTSIGNOUT  => open,    -- 1-bit output: Multiplier sign cascade output
      PCOUT        => PC_r2,   -- 48-bit output: Cascade output
      -- Control: 1-bit (each) output: Control Inputs/Status Bits
      OVERFLOW       => open,  -- 1-bit output: Overflow in add/acc output
      PATTERNBDETECT => open,  -- 1-bit output: Pattern bar detect output
      PATTERNDETECT  => open,  -- 1-bit output: Pattern detect output
      UNDERFLOW      => open,  -- 1-bit output: Underflow in add/acc output
      -- Data: 4-bit (each) output: Data Ports
      CARRYOUT       => open,  -- 4-bit output: Carry output
      P              => open,  -- 48-bit output: Primary data output
      -- Cascade: 30-bit (each) input: Cascade Ports
      ACIN        => (others => '0'), -- 30-bit input: A cascade data input
      BCIN        => (others => '0'), -- 18-bit input: B cascade input
      CARRYCASCIN => '0',             -- 1-bit input: Cascade carry input
      MULTSIGNIN  => '0',             -- 1-bit input: Multiplier sign input
      PCIN        => (others => '0'), -- 48-bit input: P cascade input
      -- Control: 4-bit (each) input: Control Inputs/Status Bits
      CLK        => CLK,        -- 1-bit input: Clock input
      ALUMODE    => "0000",     -- 4-bit input: ALU control input
      CARRYINSEL => "000",      -- 3-bit input: Carry select input
      CEINMODE   => '1',        -- 1-bit input: Clock enable input for INMODEREG
      INMODE     => "00000",    -- 5-bit input: INMODE control input
      OPMODE     => "0110101",  -- 7-bit input: Operation mode input
      RSTINMODE  => '0',           -- 1-bit input: Reset input for INMODEREG
      -- Data: 30-bit (each) input: Data Ports
      A => a_r2,      -- 30-bit input: A data input
      B => b_r2,                        -- 18-bit input: B data input
      C => c2,              -- 48-bit input: C data input
      CARRYIN => '0',                   -- 1-bit input: Carry input signal
      D => (others =>'0'),              -- 25-bit input: D data input
      -- Reset/Clock Enable: 1-bit (each) input: Reset/Clock Enable Inputs
      CEA1 => '0',                     -- 1-bit input: Clock enable input for 1st stage AREG
      CEA2 => '0',                     -- 1-bit input: Clock enable input for 2nd stage AREG
      CEAD => '0',                     -- 1-bit input: Clock enable input for ADREG
      CEALUMODE => '1',           -- 1-bit input: Clock enable input for ALUMODE
      CEB1 => '0',                     -- 1-bit input: Clock enable input for 1st stage BREG
      CEB2 => '0',                     -- 1-bit input: Clock enable input for 2nd stage BREG
      CEC => '0',                       -- 1-bit input: Clock enable input for CREG
      CECARRYIN => '1',           -- 1-bit input: Clock enable input for CARRYINREG
      CECTRL => '1',                 -- 1-bit input: Clock enable input for OPMODEREG and CARRYINSELREG
      CED => '0',                       -- 1-bit input: Clock enable input for DREG
      CEM => '1',                       -- 1-bit input: Clock enable input for MREG
      CEP => '1',                       -- 1-bit input: Clock enable input for PREG
      RSTA => '0',                     -- 1-bit input: Reset input for AREG
      RSTALLCARRYIN => '0',   -- 1-bit input: Reset input for CARRYINREG
      RSTALUMODE => '0',         -- 1-bit input: Reset input for ALUMODEREG
      RSTB => '0',                     -- 1-bit input: Reset input for BREG
      RSTC => '0',                     -- 1-bit input: Reset input for CREG
      RSTCTRL => '0',               -- 1-bit input: Reset input for OPMODEREG and CARRYINSELREG
      RSTD => '0',                     -- 1-bit input: Reset input for DREG and ADREG
      RSTM => '0',                     -- 1-bit input: Reset input for MREG
      RSTP => '0'                      -- 1-bit input: Reset input for PREG
   );

mult_g2 : DSP48E1
   generic map (
      -- Feature Control Attributes: Data Path Selection
      A_INPUT => "DIRECT",               -- Selects A input source, "DIRECT" (A port) or "CASCADE" (ACIN port)
      B_INPUT => "DIRECT",               -- Selects B input source, "DIRECT" (B port) or "CASCADE" (BCIN port)
      USE_DPORT => FALSE,                -- Select D port usage (TRUE or FALSE)
      USE_MULT => "MULTIPLY",            -- Select multiplier usage ("MULTIPLY", "DYNAMIC", or "NONE")
      USE_SIMD => "ONE48",               -- SIMD selection ("ONE48", "TWO24", "FOUR12")
      -- Pattern Detector Attributes: Pattern Detection Configuration
      AUTORESET_PATDET => "NO_RESET",    -- "NO_RESET", "RESET_MATCH", "RESET_NOT_MATCH" 
      MASK => X"3fffffffffff",           -- 48-bit mask value for pattern detect (1=ignore)
      PATTERN => X"000000000000",        -- 48-bit pattern match for pattern detect
      SEL_MASK => "MASK",                -- "C", "MASK", "ROUNDING_MODE1", "ROUNDING_MODE2" 
      SEL_PATTERN => "PATTERN",          -- Select pattern value ("PATTERN" or "C")
      USE_PATTERN_DETECT => "NO_PATDET", -- Enable pattern detect ("PATDET" or "NO_PATDET")
      -- Register Control Attributes: Pipeline Register Configuration
      ACASCREG => 1,                     -- Number of pipeline stages between A/ACIN and ACOUT (0, 1 or 2)
      ADREG => 0,                        -- Number of pipeline stages for pre-adder (0 or 1)
      ALUMODEREG => 1,                   -- Number of pipeline stages for ALUMODE (0 or 1)
      AREG => 1,                         -- Number of pipeline stages for A (0, 1 or 2)
      BCASCREG => 1,                     -- Number of pipeline stages between B/BCIN and BCOUT (0, 1 or 2)
      BREG => 1,                         -- Number of pipeline stages for B (0, 1 or 2)
      CARRYINREG => 1,                   -- Number of pipeline stages for CARRYIN (0 or 1)
      CARRYINSELREG => 1,                -- Number of pipeline stages for CARRYINSEL (0 or 1)
      CREG => 0,                         -- Number of pipeline stages for C (0 or 1)
      DREG => 0,                         -- Number of pipeline stages for D (0 or 1)
      INMODEREG => 1,                    -- Number of pipeline stages for INMODE (0 or 1)
      MREG => 1,                         -- Number of multiplier pipeline stages (0 or 1)
      OPMODEREG => 1,                    -- Number of pipeline stages for OPMODE (0 or 1)
      PREG => 1                          -- Number of pipeline stages for P (0 or 1)
   )
   port map (
      -- Cascade: 30-bit (each) output: Cascade Ports
      ACOUT        => open,    -- 30-bit output: A port cascade output
      BCOUT        => open,    -- 18-bit output: B port cascade output
      CARRYCASCOUT => open,    -- 1-bit output: Cascade carry output
      MULTSIGNOUT  => open,    -- 1-bit output: Multiplier sign cascade output
      PCOUT        => PC_g2,   -- 48-bit output: Cascade output
      -- Control: 1-bit (each) output: Control Inputs/Status Bits
      OVERFLOW       => open,  -- 1-bit output: Overflow in add/acc output
      PATTERNBDETECT => open,  -- 1-bit output: Pattern bar detect output
      PATTERNDETECT  => open,  -- 1-bit output: Pattern detect output
      UNDERFLOW      => open,  -- 1-bit output: Underflow in add/acc output
      -- Data: 4-bit (each) output: Data Ports
      CARRYOUT       => open,  -- 4-bit output: Carry output
      P              => open,  -- 48-bit output: Primary data output
      -- Cascade: 30-bit (each) input: Cascade Ports
      ACIN        => (others=>'0'),       -- 30-bit input: A cascade data input
      BCIN        => (others=>'0'),       -- 18-bit input: B cascade input
      CARRYCASCIN => '0',       -- 1-bit input: Cascade carry input
      MULTSIGNIN  => '0',       -- 1-bit input: Multiplier sign input
      PCIN        => pc_r2,       -- 48-bit input: P cascade input
      -- Control: 4-bit (each) input: Control Inputs/Status Bits
      CLK        => CLK,        -- 1-bit input: Clock input
      ALUMODE    => "0000",     -- 4-bit input: ALU control input
      CARRYINSEL => "000",      -- 3-bit input: Carry select input
      CEINMODE   => '1',        -- 1-bit input: Clock enable input for INMODEREG
      INMODE     => "00000",                -- 5-bit input: INMODE control input
      OPMODE     => "0010101",                 -- 7-bit input: Operation mode input
      RSTINMODE  => '0',           -- 1-bit input: Reset input for INMODEREG
      -- Data: 30-bit (each) input: Data Ports
      A => a_g2,                        -- 30-bit input: A data input
      B => b_g2,                        -- 18-bit input: B data input
      C => (others =>'0'),              -- 48-bit input: C data input
      CARRYIN => '0',                   -- 1-bit input: Carry input signal
      D => (others =>'0'),              -- 25-bit input: D data input
      -- Reset/Clock Enable: 1-bit (each) input: Reset/Clock Enable Inputs
      CEA1 => '0',                     -- 1-bit input: Clock enable input for 1st stage AREG
      CEA2 => '1',                     -- 1-bit input: Clock enable input for 2nd stage AREG
      CEAD => '0',                     -- 1-bit input: Clock enable input for ADREG
      CEALUMODE => '1',           -- 1-bit input: Clock enable input for ALUMODE
      CEB1 => '0',                     -- 1-bit input: Clock enable input for 1st stage BREG
      CEB2 => '1',                     -- 1-bit input: Clock enable input for 2nd stage BREG
      CEC => '0',                       -- 1-bit input: Clock enable input for CREG
      CECARRYIN => '1',           -- 1-bit input: Clock enable input for CARRYINREG
      CECTRL => '1',                 -- 1-bit input: Clock enable input for OPMODEREG and CARRYINSELREG
      CED => '0',                       -- 1-bit input: Clock enable input for DREG
      CEM => '1',                       -- 1-bit input: Clock enable input for MREG
      CEP => '1',                       -- 1-bit input: Clock enable input for PREG
      RSTA => '0',                     -- 1-bit input: Reset input for AREG
      RSTALLCARRYIN => '0',   -- 1-bit input: Reset input for CARRYINREG
      RSTALUMODE => '0',         -- 1-bit input: Reset input for ALUMODEREG
      RSTB => '0',                     -- 1-bit input: Reset input for BREG
      RSTC => '0',                     -- 1-bit input: Reset input for CREG
      RSTCTRL => '0',               -- 1-bit input: Reset input for OPMODEREG and CARRYINSELREG
      RSTD => '0',                     -- 1-bit input: Reset input for DREG and ADREG
      RSTM => '0',                     -- 1-bit input: Reset input for MREG
      RSTP => '0'                      -- 1-bit input: Reset input for PREG
   );

mult_b2 : DSP48E1
   generic map (
      -- Feature Control Attributes: Data Path Selection
      A_INPUT => "DIRECT",               -- Selects A input source, "DIRECT" (A port) or "CASCADE" (ACIN port)
      B_INPUT => "DIRECT",               -- Selects B input source, "DIRECT" (B port) or "CASCADE" (BCIN port)
      USE_DPORT => FALSE,                -- Select D port usage (TRUE or FALSE)
      USE_MULT => "MULTIPLY",            -- Select multiplier usage ("MULTIPLY", "DYNAMIC", or "NONE")
      USE_SIMD => "ONE48",               -- SIMD selection ("ONE48", "TWO24", "FOUR12")
      -- Pattern Detector Attributes: Pattern Detection Configuration
      AUTORESET_PATDET => "NO_RESET",    -- "NO_RESET", "RESET_MATCH", "RESET_NOT_MATCH" 
      MASK => X"3fffffffffff",           -- 48-bit mask value for pattern detect (1=ignore)
      PATTERN => X"000000000000",        -- 48-bit pattern match for pattern detect
      SEL_MASK => "MASK",                -- "C", "MASK", "ROUNDING_MODE1", "ROUNDING_MODE2" 
      SEL_PATTERN => "PATTERN",          -- Select pattern value ("PATTERN" or "C")
      USE_PATTERN_DETECT => "NO_PATDET", -- Enable pattern detect ("PATDET" or "NO_PATDET")
      -- Register Control Attributes: Pipeline Register Configuration
      ACASCREG => 2,                     -- Number of pipeline stages between A/ACIN and ACOUT (0, 1 or 2)
      ADREG => 0,                        -- Number of pipeline stages for pre-adder (0 or 1)
      ALUMODEREG => 1,                   -- Number of pipeline stages for ALUMODE (0 or 1)
      AREG => 2,                         -- Number of pipeline stages for A (0, 1 or 2)
      BCASCREG => 2,                     -- Number of pipeline stages between B/BCIN and BCOUT (0, 1 or 2)
      BREG => 2,                         -- Number of pipeline stages for B (0, 1 or 2)
      CARRYINREG => 1,                   -- Number of pipeline stages for CARRYIN (0 or 1)
      CARRYINSELREG => 1,                -- Number of pipeline stages for CARRYINSEL (0 or 1)
      CREG => 0,                         -- Number of pipeline stages for C (0 or 1)
      DREG => 0,                         -- Number of pipeline stages for D (0 or 1)
      INMODEREG => 1,                    -- Number of pipeline stages for INMODE (0 or 1)
      MREG => 1,                         -- Number of multiplier pipeline stages (0 or 1)
      OPMODEREG => 1,                    -- Number of pipeline stages for OPMODE (0 or 1)
      PREG => 1                          -- Number of pipeline stages for P (0 or 1)
   )
   port map (
      -- Cascade: 30-bit (each) output: Cascade Ports
      ACOUT        => open,          -- 30-bit output: A port cascade output
      BCOUT        => open,          -- 18-bit output: B port cascade output
      CARRYCASCOUT => open,          -- 1-bit output: Cascade carry output
      MULTSIGNOUT  => open,          -- 1-bit output: Multiplier sign cascade output
      PCOUT        => open,          -- 48-bit output: Cascade output
      -- Control: 1-bit (each) output: Control Inputs/Status Bits
      OVERFLOW       => open,        -- 1-bit output: Overflow in add/acc output
      PATTERNBDETECT => open,        -- 1-bit output: Pattern bar detect output
      PATTERNDETECT  => open,        -- 1-bit output: Pattern detect output
      UNDERFLOW      => open,        -- 1-bit output: Underflow in add/acc output
      -- Data: 4-bit (each) output: Data Ports
      CARRYOUT       => open,        -- 4-bit output: Carry output
      P              => P_b2,        -- 48-bit output: Primary data output
      -- Cascade: 30-bit (each) input: Cascade Ports
      ACIN        => (others =>'0'), -- 30-bit input: A cascade data input
      BCIN        => (others =>'0'), -- 18-bit input: B cascade input
      CARRYCASCIN => '0',            -- 1-bit input: Cascade carry input
      MULTSIGNIN  => '0',            -- 1-bit input: Multiplier sign input
      PCIN        => pc_g2,          -- 48-bit input: P cascade input
      -- Control: 4-bit (each) input: Control Inputs/Status Bits
      CLK        => CLK,            -- 1-bit input: Clock input
      ALUMODE    => "0000",         -- 4-bit input: ALU control input
      CARRYINSEL => "000",          -- 3-bit input: Carry select input
      CEINMODE   => '1',            -- 1-bit input: Clock enable input for INMODEREG
      INMODE     => "00000",        -- 5-bit input: INMODE control input
      OPMODE     => "0010101",      -- 7-bit input: Operation mode input
      RSTINMODE  => '0',            -- 1-bit input: Reset input for INMODEREG
      -- Data: 30-bit (each) input: Data Ports
      A => a_b2,                    -- 30-bit input: A data input
      B => b_b2,                    -- 18-bit input: B data input
      C => (others =>'0'),          -- 48-bit input: C data input
      CARRYIN => '0',               -- 1-bit input: Carry input signal
      D => (others =>'0'),          -- 25-bit input: D data input
      -- Reset/Clock Enable: 1-bit (each) input: Reset/Clock Enable Inputs
      CEA1 => '1',            -- 1-bit input: Clock enable input for 1st stage AREG
      CEA2 => '1',            -- 1-bit input: Clock enable input for 2nd stage AREG
      CEAD => '0',            -- 1-bit input: Clock enable input for ADREG
      CEALUMODE => '1',       -- 1-bit input: Clock enable input for ALUMODE
      CEB1 => '1',            -- 1-bit input: Clock enable input for 1st stage BREG
      CEB2 => '1',            -- 1-bit input: Clock enable input for 2nd stage BREG
      CEC => '0',             -- 1-bit input: Clock enable input for CREG
      CECARRYIN => '1',       -- 1-bit input: Clock enable input for CARRYINREG
      CECTRL => '1',          -- 1-bit input: Clock enable input for OPMODEREG and CARRYINSELREG
      CED => '0',             -- 1-bit input: Clock enable input for DREG
      CEM => '1',             -- 1-bit input: Clock enable input for MREG
      CEP => '1',             -- 1-bit input: Clock enable input for PREG
      RSTA => '0',            -- 1-bit input: Reset input for AREG
      RSTALLCARRYIN => '0',   -- 1-bit input: Reset input for CARRYINREG
      RSTALUMODE => '0',      -- 1-bit input: Reset input for ALUMODEREG
      RSTB => '0',            -- 1-bit input: Reset input for BREG
      RSTC => '0',            -- 1-bit input: Reset input for CREG
      RSTCTRL => '0',         -- 1-bit input: Reset input for OPMODEREG and CARRYINSELREG
      RSTD => '0',            -- 1-bit input: Reset input for DREG and ADREG
      RSTM => '0',            -- 1-bit input: Reset input for MREG
      RSTP => '0'             -- 1-bit input: Reset input for PREG
   );
end Behavioral;