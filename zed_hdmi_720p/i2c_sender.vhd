----------------------------------------------------------------------------------
-- Engineer:    Mike Field <hamster@snap.net.nz>
-- 
-- Module Name: i2c_sender h- Behavioral 
--
-- Description: Send register writes over an I2C-like interface
--
-- Feel free to use this how you see fit, and fix any errors you find :-)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity i2c_sender is
    Port ( clk    : in    STD_LOGIC;    
           resend : in    STD_LOGIC;
           sioc   : out   STD_LOGIC;
           siod   : inout STD_LOGIC
    );
end i2c_sender;

architecture Behavioral of i2c_sender is
   signal   divider           : unsigned(8 downto 0)  := (others => '0'); 
    -- this value gives nearly 200ms cycles before the first register is written
   signal   initial_pause     : unsigned(7 downto 0) := (others => '0');
   signal   finished          : std_logic := '0';
   signal   address           : std_logic_vector(7 downto 0)  := (others => '0');
   signal   clk_first_quarter : std_logic_vector(28 downto 0) := (others => '1');
   signal   clk_last_quarter  : std_logic_vector(28 downto 0) := (others => '1');
   signal   busy_sr           : std_logic_vector(28 downto 0) := (others => '1');
   signal   data_sr           : std_logic_vector(28 downto 0) := (others => '1');
   signal   tristate_sr       : std_logic_vector(28 downto 0) := (others => '0');
   signal   reg_value         : std_logic_vector(15 downto 0)  := (others => '0');
   constant i2c_wr_addr       : std_logic_vector(7 downto 0)  := x"7A";

   type reg_value_pair is ARRAY(0 TO 63) OF std_logic_vector(15 DOWNTO 0);    
   
   signal reg_value_pairs : reg_value_pair := (
            -------------------
            -- Powerup please!
            -------------------
            x"4110", 
            ---------------------------------------
            -- These valuse must be set as follows
            ---------------------------------------
            x"9803", x"9AE0", x"9C30", x"9D61", x"A2A4", x"A3A4", x"E0D0", x"5512", x"F900",
            
            ---------------
            -- Input mode
            ---------------
            x"1500", -- Simple RGB video (was $06 = YCbCr 422, DDR, External sync)
            x"4810", -- Left justified data (D23 downto 8)
            -- according to documenation, style 2 should be x"1637" but it isn't. ARGH!
--            x"1637", -- 444 output, 8 bit style 2, 1st half on rising edge - YCrCb clipping
            x"1630", -- more boring pixel format
            x"1700", -- output asp ect ratio 16:9, external DE 
            x"D03C", -- auto sync data - must be set for DDR modes. No DDR clock delay
            ---------------
            -- Output mode
            ---------------
            x"AF04", -- DVI mode
            x"4c04", -- Deep colour off (HDMI only?)     - not needed
            x"4000", -- Turn off additional data packets - not needed

            --------------------------------------------------------------
            -- Here is the YCrCb => RGB conversion, as per programming guide
            -- This is table 57 - HDTV YCbCr (16 to 255) to RGB (0 to 255)
            --------------------------------------------------------------
            -- (Cr * A1       +      Y * A2       +     Cb * A3)/4096 +     A4    =  Red
--            x"18E7", x"1934",   x"1A04", x"1BAD",   x"1C00", x"1D00",   x"1E1C", x"1F1B",
            x"1800", x"1934",   x"1A04", x"1BAD",   x"1C00", x"1D00",   x"1E1C", x"1F1B",
            -- (Cr * B1       +      Y * B2       +     Cb * B3)/4096 +     B4    =  Green
            x"201D", x"21DC",   x"2204", x"23AD",   x"241F", x"2524",   x"2601", x"2735",
            -- (Cr * C1       +      Y * C2       +     Cb * C3)/4096 +     C4    =  Blue
            x"2800", x"2900",   x"2A04", x"2BAD",   x"2C08", x"2D7C",   x"2E1B", x"2F77",

            -- Extra space filled with FFFFs to signify end of data
            x"FFFF", x"FFFF", x"FFFF", x"FFFF", x"FFFF", x"FFFF", x"FFFF",
            x"FFFF", x"FFFF", x"FFFF", x"FFFF", x"FFFF", x"FFFF", x"FFFF", x"FFFF",
            x"FFFF", x"FFFF", x"FFFF", x"FFFF", x"FFFF", x"FFFF", x"FFFF"
   );
begin

registers: process(clk)
   begin
      if rising_edge(clk) then
         reg_value <= reg_value_pairs(to_integer(unsigned(address)));
      end if;
   end process;

i2c_tristate: process(data_sr, tristate_sr)
   begin
      if tristate_sr(tristate_sr'length-1) = '0' then
         siod <= data_sr(data_sr'length-1);
      else
         siod <= 'Z';
      end if;
   end process;
   
   with divider(divider'length-1 downto divider'length-2) 
      select sioc <= clk_first_quarter(clk_first_quarter'length -1) when "00",
                     clk_last_quarter(clk_last_quarter'length -1)   when "11",
                     '1' when others;
                     
i2c_send:   process(clk)
   begin
      if rising_edge(clk) then
         if resend = '1' then 
            address           <= (others => '0');
            clk_first_quarter <= (others => '1');
            clk_last_quarter  <= (others => '1');
            busy_sr           <= (others => '0');
            divider           <= (others => '0');
            initial_pause     <= (others => '0');
            finished <= '0';
         end if;

         if busy_sr(busy_sr'length-1) = '0' then
            if initial_pause(initial_pause'length-1) = '0' then
               initial_pause <= initial_pause+1;
            elsif finished = '0' then
               if divider = "11111111" then
                  divider <= (others =>'0');
                  if reg_value(15 downto 8) = "11111111" then
                     finished <= '1';
                  else
                     -- move the new data into the shift registers
                     clk_first_quarter <= (others => '0'); clk_first_quarter(clk_first_quarter'length-1) <= '1';
                     clk_last_quarter <= (others => '0');  clk_last_quarter(0) <= '1';
                     
                     --             Start    Address    Ack        Register            Ack          Value            Ack    Stop
                     tristate_sr <= "0" & "00000000"  & "1" & "00000000"             & "1" & "00000000"             & "1"  & "0";
                     data_sr     <= "0" & i2c_wr_addr & "1" & reg_value(15 downto 8) & "1" & reg_value( 7 downto 0) & "1"  & "0";
                     busy_sr     <= (others => '1');
                     address     <= std_logic_vector(unsigned(address)+1);
                  end if;
               else
                  divider <= divider+1; 
               end if;
            end if;
         else
            if divider = "11111111" then   -- divide clkin by 256 for I2C
               tristate_sr       <= tristate_sr(tristate_sr'length-2 downto 0) & '0';
               busy_sr           <= busy_sr(busy_sr'length-2 downto 0) & '0';
               data_sr           <= data_sr(data_sr'length-2 downto 0) & '1';
               clk_first_quarter <= clk_first_quarter(clk_first_quarter'length-2 downto 0) & '1';
               clk_last_quarter  <= clk_last_quarter(clk_first_quarter'length-2 downto 0) & '1';
               divider           <= (others => '0');
            else
               divider <= divider+1;
            end if;
         end if;
      end if;
   end process;
end Behavioral;

