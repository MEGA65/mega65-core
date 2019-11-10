----------------------------------------------------------------------------------
-- Engineer: Mike Field <hamster@snap.net.nz>
-- 
-- Create Date:    06:01:06 01/23/2013 
--
-- Description: 
--      Drive the ADV7511 HDMI encoder directly from the PL fabric
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

Library UNISIM;
use UNISIM.vcomponents.all;

entity zedboard_hdmi is
    Port ( clk_100       : in  STD_LOGIC;
           hdmi_clk      : out  STD_LOGIC;
           hdmi_hsync    : out  STD_LOGIC;
           hdmi_vsync    : out  STD_LOGIC;
           hdmi_d        : out  STD_LOGIC_VECTOR (15 downto 0);
           hdmi_de       : out  STD_LOGIC;
           hdmi_int      : in   STD_LOGIC;
           hdmi_scl      : out  STD_LOGIC;
           hdmi_sda      : inout  STD_LOGIC);
end zedboard_hdmi;

architecture Behavioral of zedboard_hdmi is
   COMPONENT i2c_sender
   PORT(
      clk    : IN std_logic;
      resend : IN std_logic;    
      siod   : INOUT std_logic;      
      sioc   : OUT std_logic
   );
   END COMPONENT;

   signal blanking       : std_logic := '0';
   signal hsync          : std_logic := '0';
   signal vsync          : std_logic := '0';
   signal edge           : std_logic := '0';
   signal colour         : STD_LOGIC_VECTOR (23 downto 0);
   signal Y              : STD_LOGIC_VECTOR (15 downto 0);
   signal Cr             : STD_LOGIC_VECTOR (15 downto 0);
   signal Cb             : STD_LOGIC_VECTOR (15 downto 0);
   signal hdmi_clk_bits  : STD_LOGIC_VECTOR (1 downto 0);
   
   signal   hcounter    : unsigned(10 downto 0) := (others => '0');
   signal   vcounter    : unsigned(10 downto 0) := (others => '0');
   
   constant ZERO        : unsigned(10 downto 0) := (others => '0');
   signal   hVisible    : unsigned(10 downto 0);
   signal   hStartSync  : unsigned(10 downto 0);
   signal   hEndSync    : unsigned(10 downto 0);
   signal   hMax        : unsigned(10 downto 0);
   signal   hSyncActive : std_logic := '1';
   
   signal   vVisible    : unsigned(10 downto 0);
   signal   vStartSync  : unsigned(10 downto 0);
   signal   vEndSync    : unsigned(10 downto 0);
   signal   vMax        : unsigned(10 downto 0);
   signal   vSyncActive : std_logic := '1';
   
   signal clk_vgax2   : std_logic;
   signal clkfb       : std_logic;
   signal clk         : std_logic;
   
   -- Colours converted using The RGB -> YCbCr converter app found on Google Gadgets 
                                                                        --  Y   Cb  Cr
   constant C_RED        : std_logic_vector(23 downto 0) := x"515AF0";  --  81  90 240
   constant C_BLACK      : std_logic_vector(23 downto 0) := x"108080";  --  16 128 128
   constant C_GREEN      : std_logic_vector(23 downto 0) := x"AC2A1B";  -- 172  42  27
   constant C_WHITE      : std_logic_vector(23 downto 0) := x"EA8080";  -- 234 128 128
   constant C_BLUE       : std_logic_vector(23 downto 0) := x"20F076";  --  32 240 118
   
begin   
   -- Set the video mode to 1280x720x60Hz (75MHz pixel clock needed)
   hVisible    <= ZERO + 1280;
   hStartSync  <= ZERO + 1280+72;
   hEndSync    <= ZERO + 1280+72+80;
   hMax        <= ZERO + 1280+72+80+216-1;
   vSyncActive <= '1';

   vVisible    <= ZERO + 720;
   vStartSync  <= ZERO + 720+3;
   vEndSync    <= ZERO + 720+3+5;
   vMax        <= ZERO + 720+3+5+22-1;
   hSyncActive <= '1';

colour_proc: process(hcounter,vcounter)
  begin
   if hcounter < 256 then
      colour <= C_RED;
   elsif hcounter < 512 then
      colour <= C_BLACK;
   elsif hcounter < 768 then
      colour <= C_GREEN;
   elsif hcounter < 1024 then
      colour <= C_WHITE;
   else
      colour <= C_BLUE;
   end if;
  end process;

   -- there is a 16 bit interface into the HDMI transmitter, although I only use 8 bits
   Y   <= colour(23 downto 16) & x"00";
   Cb  <= colour(15 downto  8) & x"00";
   Cr  <= colour( 7 downto  0) & x"00";
      
vga_clkx2_process: process (clk_vgax2)
   begin
      if rising_edge(clk_VGAx2) then 
         ---------------------------------------------------------------------------
         -- signal generation for the HDMI encoder
         --
         -- Transfer on rising edge  of clock Y
         --          on falling edge of clock Either Cr or Cb 
         --
         -- Because I am a wimp I don't use any DDR except for generating the DDR clk.
         ----------------------------------------------------------------------------
         if edge =  '0' then
            edge <= '1';
            hdmi_clk_bits <= "11";
            if blanking = '1' then 
               hdmi_d <= (others => '0');
               hdmi_de <= '0';
            else
               hdmi_d  <= Y;
               hdmi_de <= '1';
            end if;
         else
            edge <= '0';
            hdmi_clk_bits <= "00";
            if blanking = '1' then 
               hdmi_d <= (others => '0');
               hdmi_de <= '0';
            else
               if hcounter(0) = '0' then 
                  hdmi_d <= Cr;
               else
                  hdmi_d <= Cb;
               end if;
               hdmi_de <= '1';
            end if;
         end if;
         hdmi_hsync <= hsync;
         hdmi_vsync <= vsync;


         ------------------------------------------------------------------------
         -- VGA Signal Generation
         -- We only update when the second clock edge has been sent 
         --- to the HDMI encoder
         ------------------------------------------------------------------------
         if edge =  '1' then
            if vcounter >= vVisible then 
               blanking <= '1';
            elsif hcounter >= hVisible then 
               blanking <= '1';
            else
               blanking <= '0';
            end if;
            
            -- Generate the sync Pulses
            if vcounter = vStartSync then 
               vSync <= vSyncActive;
            elsif vCounter = vEndSync then
               vSync <= not(vSyncActive);
            end if;

            if hcounter = hStartSync then 
               hSync <= hSyncActive;
            elsif hCounter = hEndSync then
               hSync <= not(hSyncActive);
            end if;

            -- Advance the position counters
            IF hCounter = hMax  THEN
               -- starting a new line
               hCounter <= (others => '0');
               IF vCounter = vMax THEN
                  vCounter <= (others => '0');
               ELSE
                  vCounter <= vCounter + 1;
               END IF;
            ELSE
               hCounter <= hCounter + 1;
            END IF;
         end if;
      end if;
   end process;
   

   ODDR_inst : ODDR
   generic map(
      DDR_CLK_EDGE => "OPPOSITE_EDGE", INIT => '0',SRTYPE => "SYNC") 
   port map (
      Q => hdmi_clk, 
      C => clk_VGAx2,
      D1 => hdmi_clk_bits(0),
      D2 => hdmi_clk_bits(1),
      CE => '1', R => '0', S => '0'
   );
   
   Inst_i2c_sender: i2c_sender PORT MAP(
      clk => clk,
      resend => '0',
      sioc => hdmi_scl,
      siod => hdmi_sda
   );
   
   -- Generate a 130MHz and 100Mhz clock from the input.
   PLLE2_BASE_inst : PLLE2_BASE
   generic map (
      BANDWIDTH => "OPTIMIZED",  -- OPTIMIZED, HIGH, LOW
      CLKFBOUT_MULT  => 9,       -- Multiply value for all CLKOUT, (2-64)
      CLKFBOUT_PHASE => 0.0,     -- Phase offset in degrees of CLKFB, (-360.000-360.000).
      CLKIN1_PERIOD  => 10.0,    -- Input clock period in ns to ps resolution (i.e. 33.333 is 30 MHz).
      -- CLKOUT0_DIVIDE - CLKOUT5_DIVIDE: Divide amount for each CLKOUT (1-128)
      CLKOUT0_DIVIDE => 9,
      CLKOUT1_DIVIDE => 6,
      CLKOUT2_DIVIDE => 1,
      CLKOUT3_DIVIDE => 1,
      CLKOUT4_DIVIDE => 1,
      CLKOUT5_DIVIDE => 1,
      -- CLKOUT0_DUTY_CYCLE - CLKOUT5_DUTY_CYCLE: Duty cycle for each CLKOUT (0.001-0.999).
      CLKOUT0_DUTY_CYCLE => 0.5,
      CLKOUT1_DUTY_CYCLE => 0.5,
      CLKOUT2_DUTY_CYCLE => 0.5,
      CLKOUT3_DUTY_CYCLE => 0.5,
      CLKOUT4_DUTY_CYCLE => 0.5,
      CLKOUT5_DUTY_CYCLE => 0.5,
      -- CLKOUT0_PHASE - CLKOUT5_PHASE: Phase offset for each CLKOUT (-360.000-360.000).
      CLKOUT0_PHASE => 0.0,
      CLKOUT1_PHASE => 0.0,
      CLKOUT2_PHASE => 0.0,
      CLKOUT3_PHASE => 0.0,
      CLKOUT4_PHASE => 0.0,
      CLKOUT5_PHASE => 0.0,
      DIVCLK_DIVIDE => 1,        -- Master division value, (1-56)
      REF_JITTER1 => 0.0,        -- Reference input jitter in UI, (0.000-0.999).
      STARTUP_WAIT => "FALSE"    -- Delay DONE until PLL Locks, ("TRUE"/"FALSE")
   )
   port map (
      -- Clock Outputs: 1-bit (each) output: User configurable clock outputs
      CLKOUT0  => clk,
      CLKOUT1  => clk_VGAx2,
      CLKOUT2  => open,
      CLKOUT3  => open,
      CLKOUT4  => open,
      CLKOUT5  => open,
      CLKFBOUT => clkfb,   -- 1-bit output: Feedback clock
      LOCKED   => open,    -- 1-bit output: LOCK
      CLKIN1   => clk_100, -- 1-bit input: Input clock
      PWRDWN   => '0',     -- 1-bit input: Power-down
      RST      => '0',     -- 1-bit input: Reset
      CLKFBIN  => clkfb    -- 1-bit input: Feedback clock
   );
end Behavioral;