use WORK.ALL;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use Std.TextIO.all;
use work.debugtools.all;

library UNISIM;
use UNISIM.vcomponents.all;


entity reconfig is
  port (
    clock : in std_logic;
    reg_num : in unsigned(4 downto 0) := "01001";
    trigger_reconfigure : in std_logic;
    reconfigure_address : in unsigned(31 downto 0) := x"00000000";
    boot_address : out unsigned(31 downto 0) := x"FFFFFFFF"
    );
end reconfig;

architecture behavioural of reconfig is

  signal icape_out : unsigned(31 downto 0);
  signal icape_in : unsigned(31 downto 0);
  signal cs : std_logic := '1'; -- interface active when low
  signal rw : std_logic := '1'; -- Read or _Write

  type reg_value_pair is ARRAY(0 TO 70) OF unsigned(35 DOWNTO 0);    
  
  signal bitstream_values : reg_value_pair := (
    x"0FFFFFFFF", -- Dummy word CS=0, RDWR=0
    x"0FFFFFFFF", -- Dummy word
    x"0FFFFFFFF", -- Dummy word
    x"0FFFFFFFF", -- Dummy word
    x"0FFFFFFFF", -- Dummy word
    x"0AA995566", -- Sync word 
    x"020000000", -- Type 1 NOOP
    x"020000000", -- Type 1 NOOP
   
    x"030020001", -- Type 1 write to WBSTAR
    x"000000000", -- Warm-boot start address
    x"020000000", -- Type 1 NOOP
    x"020000000", -- Type 1 NOOP
    x"030008001", -- Type 1 write words to CMD
    x"00000000F", -- IPROG word
    x"020000000", -- Type 1 NOOP
    x"020000000", -- Type 1 NOOP


    -- Offset 16: read WBSTAR or other register
    x"3FFFFFFFF", -- Dummy word with CS and R/W released
    x"020000000", -- Type 1 NOOP
    x"0AA995566", -- Sync word 
    x"020000000", -- Type 1 NOOP     
    x"020000000", -- Type 1 NOOP


    -- Offset 21: The actual read command
--    x"20020001", -- Type 1 read from WBSTAR (10000)
--    x"2002c001", -- Type 1 read from BOOTSTS (10110)
--    x"020012001", -- Type 1 read from COR0 (01001) (has value with ones and  zeroes for easy spotting)    
    x"028018001", -- Type 1 read from IDCODE (01100) (has value with ones and  zeroes for easy spotting)

    -- Offset 22: Switch to read and allow time for value to emerge 
    x"220000000", -- Release CS
    x"320000000", -- Switch to READ, CS still released    
    x"120000000", -- Type 1 NOOP with CS asserted and R/W = READ
    x"120000000", -- Type 1 NOOP with CS asserted and R/W = READ
    x"120000000", -- Type 1 NOOP with CS asserted and R/W = READ
    x"120000000", -- Type 1 NOOP with CS asserted and R/W = READ
    x"120000000", -- Type 1 NOOP with CS asserted and R/W = READ

    -- Offset 29: Get value back out
    x"520000000", -- We get our answer now.
    x"020000000", -- Desync
    x"020000000", -- Type 1 NOOP
    x"020000000", -- Type 1 NOOP
    
    
    others => x"3FFFFFFFF"
    );

  signal counter : integer range 0 to 99 := 99;

  signal set_toggle : std_logic := '0';
  
begin

  ICAPE2_inst: ICAPE2 
--  ICAPE2_inst: entity work.ICAPE2 
    generic map(
      DEVICE_ID => X"3651093",    -- Specifies the pre-programmed
      -- Device ID value to be used for
      -- simulation purposes.
      ICAP_WIDTH => "X32",        -- Specifies the input and output
      -- data width.
      SIM_CFG_FILE_NAME => "NONE" -- Specifies the Raw Bitstream (RBT)
      -- file to be parsed by the
      -- simulation model.
      )
    port map (
      unsigned(O) => icape_out,
      CLK => clock,
      CSIB => cs,
      I => std_logic_vector(icape_in),
      rdwrb => rw
      );
  
  process (clock) is
  begin

    if rising_edge(clock) then
      if counter < 70 then

        -- CS and R/W transitions are encoded in the upper bits of our value list
        cs <= bitstream_values(counter)(33);
        rw <= bitstream_values(counter)(32);
        if bitstream_values(counter)(34)='1' then
          -- Flip bit order in bytes
          for bb in 0 to 3 loop
            for j in 0 to 7 loop
              boot_address(bb*8+j) <= icape_out(bb*8+7-j);
            end loop;
          end loop;
          
--          boot_address <= icape_out;
        end if;
        
        counter <= counter + 1;        

        report "counter = " & integer'image(counter)
          & ", writing $" & to_hstring(bitstream_values(counter)(31 downto 0));
        
        icape_in(31) <= bitstream_values(counter)(24);
        icape_in(30) <= bitstream_values(counter)(25);
        icape_in(29) <= bitstream_values(counter)(26);
        icape_in(28) <= bitstream_values(counter)(27);
        icape_in(27) <= bitstream_values(counter)(28);
        icape_in(26) <= bitstream_values(counter)(29);
        icape_in(25) <= bitstream_values(counter)(30);
        icape_in(24) <= bitstream_values(counter)(31);

        icape_in(23) <= bitstream_values(counter)(16);
        icape_in(22) <= bitstream_values(counter)(17);
        icape_in(21) <= bitstream_values(counter)(18);
        icape_in(20) <= bitstream_values(counter)(19);
        icape_in(19) <= bitstream_values(counter)(20);
        icape_in(18) <= bitstream_values(counter)(21);
        icape_in(17) <= bitstream_values(counter)(22);
        icape_in(16) <= bitstream_values(counter)(23);

        icape_in(15) <= bitstream_values(counter)(8);
        icape_in(14) <= bitstream_values(counter)(9);
        icape_in(13) <= bitstream_values(counter)(10);
        icape_in(12) <= bitstream_values(counter)(11);
        icape_in(11) <= bitstream_values(counter)(12);
        icape_in(10) <= bitstream_values(counter)(13);
        icape_in(9) <= bitstream_values(counter)(14);
        icape_in(8) <= bitstream_values(counter)(15);

        icape_in(7) <= bitstream_values(counter)(0);
        icape_in(6) <= bitstream_values(counter)(1);
        icape_in(5) <= bitstream_values(counter)(2);
        icape_in(4) <= bitstream_values(counter)(3);
        icape_in(3) <= bitstream_values(counter)(4);
        icape_in(2) <= bitstream_values(counter)(5);
        icape_in(1) <= bitstream_values(counter)(6);
        icape_in(0) <= bitstream_values(counter)(7);

      else

        set_toggle <= not set_toggle;

        if set_toggle = '0' then
          bitstream_values(9)(31 downto 0) <= reconfigure_address;
        else
          bitstream_values(21)(17 downto 13) <= reg_num;
        end if;
        cs <= '1';
        rw <= '1';
        if trigger_reconfigure = '1' then
          counter <= 0;
        else
          counter <= 16; 
        end if;
      end if;
            
    end if;
  end process;

end behavioural;
