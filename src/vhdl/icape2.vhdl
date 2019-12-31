Library UNISIM;
use UNISIM.vcomponents.all;

-- ICAPE2: Internal Configuration Access Port
-- 7Series
-- Xilinx HDL Libraries Guide, version 2012.2


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

portmap(
   O => O,        -- 32-bit output : Configuration data output bus
   CLK => CLK,    -- 1-bit input   : Clock Input 
   CSIB => CSIB,  -- 1-bit input   : Active-Low ICAP Enable
   I => I,        -- 32-bit input  : Configuration data input bus
   RDWRB => RDWRB -- 1-bit input   : Read/Write Select input
); 

-- End of ICAPE2_inst instantiation


