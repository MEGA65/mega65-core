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
    trigger_reconfigure : in std_logic;
    reconfigure_address : in unsigned(31 downto 0) := x"00000000"
    );
end reconfig;

architecture behavioural of reconfig is

  signal icape_out : unsigned(31 downto 0);
  signal icape_in : unsigned(31 downto 0);
  signal cs : std_logic := '1'; -- interface active when low
  signal rw : std_logic := '1'; -- Read or _Write

  type reg_value_pair is ARRAY(0 TO 70) OF unsigned(31 DOWNTO 0);    
  
  signal bitstream_values : reg_value_pair := (
    x"FFFFFFFF", -- Dummy word
    x"FFFFFFFF", -- Dummy word
    x"FFFFFFFF", -- Dummy word
    x"FFFFFFFF", -- Dummy word
    x"FFFFFFFF", -- Dummy word
    x"AA995566", -- Sync word 
    x"20000000", -- Type 1 NOOP
    x"20000000", -- Type 1 NOOP

    -- the below was an attempt to allow reconfig from JTAG loaded bitstream. #156
    -- ... which didn't work for some reason.
--    -- Select QSPIx4, set SPI read command 
--    x"3003E001",x"0000026C",
--    -- Send reiniatialised BPI/SPI re-initiate bitstream read
--    x"30008001",x"00000012",
--    x"20000000", -- Type 1 NOOP
--    -- Reset watchdog timer
--    x"30022001",x"00000000",
--
--    -- Send NOOP command
--    x"30008001",x"00000000",
--    x"20000000", -- Type 1 NOOP
--    -- Send Reset CRC command
--    x"30008001",x"00000007",
--    x"20000000", -- Type 1 NOOP
--    x"20000000", -- Type 1 NOOP
--
--    --Write $0 to undocumented config register #13?
--    x"30026001",x"00000000",
--
--    --  GWE deassert in Startup Phase 4
--    --  GTS deassert in Startup Phase 3
--    --  LOCK_CYCLE stall for MMCM lock disabled.
--    --  MATCH_CYCLE stall for DCI match disabled.
--    --  DONE pin released in Startup Phase 2
--    --  33MHz QSPI clock ($42 gets shifted right one, to be $21 == 33 decimal)
--    -- etc
--    x"30012001",x"02423FE5",
--
--    -- Clear Configuration Options Register 1
--    -- (mostly resetting BPI configuration settings)
--    x"3001C001",x"00000000",
--
--    -- Write ID code to match FPGA
----    x"30018001",x"03631093",
--
--    -- Activate selected frequency for QSPI config reading
--    x"30008001",x"00000009",
--    
--    x"20000000", -- Type 1 NOOP
--
--    -- Set mask register to allow CTL0 and CTL1 writes to be effective
--    x"3000C001",x"00000401",
--    -- Write to CTL0: Enable fallback on configuration failure, clear GLUTMASK
--    -- to allow read-back of changeable memory cell values
--    x"3000A001",x"00000501",
--
--    -- Set mask register to allow CTL0 and CTL1 writes to be effective    
--    x"3000C001",x"00001000",
--    -- Write magic value into reserved CTRL1 register
--    x"30030001",x"00001000",

   
    x"30020001", -- Type 1 write to WBSTAR
    x"00000000", -- Warm-boot start address
    x"20000000", -- Type 1 NOOP
    x"20000000", -- Type 1 NOOP
    x"30008001", -- Type 1 write words to CMD
    x"0000000F", -- IPROG word
    x"20000000", -- Type 1 NOOP
    x"20000000", -- Type 1 NOOP
    others => x"FFFFFFFF"
    );

  signal counter : integer range 0 to 99 := 99;
  
begin

  ICAPE2_inst: ICAPE2 
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
        if counter = 5 then
          cs <= '0';
          rw <= '0';
        end if;
        
        counter <= counter + 1;        

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
        bitstream_values(9) <= reconfigure_address;
        cs <= '1';
        rw <= '1';
        if trigger_reconfigure = '1' then
          counter <= 0;
        end if;
      end if;
            
    end if;
  end process;

end behavioural;
