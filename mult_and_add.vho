--------------------------------------------------------------------------------
--    This file is owned and controlled by Xilinx and must be used solely     --
--    for design, simulation, implementation and creation of design files     --
--    limited to Xilinx devices or technologies. Use with non-Xilinx          --
--    devices or technologies is expressly prohibited and immediately         --
--    terminates your license.                                                --
--                                                                            --
--    XILINX IS PROVIDING THIS DESIGN, CODE, OR INFORMATION "AS IS" SOLELY    --
--    FOR USE IN DEVELOPING PROGRAMS AND SOLUTIONS FOR XILINX DEVICES.  BY    --
--    PROVIDING THIS DESIGN, CODE, OR INFORMATION AS ONE POSSIBLE             --
--    IMPLEMENTATION OF THIS FEATURE, APPLICATION OR STANDARD, XILINX IS      --
--    MAKING NO REPRESENTATION THAT THIS IMPLEMENTATION IS FREE FROM ANY      --
--    CLAIMS OF INFRINGEMENT, AND YOU ARE RESPONSIBLE FOR OBTAINING ANY       --
--    RIGHTS YOU MAY REQUIRE FOR YOUR IMPLEMENTATION.  XILINX EXPRESSLY       --
--    DISCLAIMS ANY WARRANTY WHATSOEVER WITH RESPECT TO THE ADEQUACY OF THE   --
--    IMPLEMENTATION, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OR          --
--    REPRESENTATIONS THAT THIS IMPLEMENTATION IS FREE FROM CLAIMS OF         --
--    INFRINGEMENT, IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A   --
--    PARTICULAR PURPOSE.                                                     --
--                                                                            --
--    Xilinx products are not intended for use in life support appliances,    --
--    devices, or systems.  Use in such applications are expressly            --
--    prohibited.                                                             --
--                                                                            --
--    (c) Copyright 1995-2014 Xilinx, Inc.                                    --
--    All rights reserved.                                                    --
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
--    Generated from core with identifier:                                    --
--    xilinx.com:ip:xbip_dsp48_macro:2.1                                      --
--                                                                            --
--    The Xilinx LogiCORE DSP48 Macro provides an easy to use interface       --
--    which abstracts the XtremeDSP Slice configuration and simplifies its    --
--    dynamic operation by enabling the specification of multiple             --
--    operations via a set of user defined arithmetic expressions. The        --
--    operations are enumerated and can be selected by the user via single    --
--    port on the generated IP.                                               --
--------------------------------------------------------------------------------

-- Interfaces:
--    sel_intf
--    clk_intf
--    sclr_intf
--    ce_intf
--    carrycascin_intf
--    carryin_intf
--    pcin_intf
--    acin_intf
--    bcin_intf
--    a_intf
--    b_intf
--    c_intf
--    d_intf
--    concat_intf
--    acout_intf
--    bcout_intf
--    carryout_intf
--    carrycascout_intf
--    pcout_intf
--    p_intf
--    ced_intf
--    ced1_intf
--    ced2_intf
--    ced3_intf
--    cea_intf
--    cea1_intf
--    cea2_intf
--    cea3_intf
--    cea4_intf
--    ceb_intf
--    ceb1_intf
--    ceb2_intf
--    ceb3_intf
--    ceb4_intf
--    ceconcat_intf
--    ceconcat3_intf
--    ceconcat4_intf
--    ceconcat5_intf
--    cec_intf
--    cec1_intf
--    cec2_intf
--    cec3_intf
--    cec4_intf
--    cec5_intf
--    cem_intf
--    cep_intf
--    cesel_intf
--    cesel1_intf
--    cesel2_intf
--    cesel3_intf
--    cesel4_intf
--    cesel5_intf
--    sclrd_intf
--    sclra_intf
--    sclrb_intf
--    sclrconcat_intf
--    sclrc_intf
--    sclrm_intf
--    sclrp_intf
--    sclrsel_intf

-- The following code must appear in the VHDL architecture header:

------------- Begin Cut here for COMPONENT Declaration ------ COMP_TAG
COMPONENT mult_and_add
  PORT (
    clk : IN STD_LOGIC;
    a : IN STD_LOGIC_VECTOR(17 DOWNTO 0);
    b : IN STD_LOGIC_VECTOR(17 DOWNTO 0);
    c : IN STD_LOGIC_VECTOR(47 DOWNTO 0);
    p : OUT STD_LOGIC_VECTOR(47 DOWNTO 0)
  );
END COMPONENT;
-- COMP_TAG_END ------ End COMPONENT Declaration ------------

-- The following code must appear in the VHDL architecture
-- body. Substitute your own instance name and net names.

------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
your_instance_name : mult_and_add
  PORT MAP (
    clk => clk,
    a => a,
    b => b,
    c => c,
    p => p
  );
-- INST_TAG_END ------ End INSTANTIATION Template ------------

-- You must compile the wrapper file mult_and_add.vhd when simulating
-- the core, mult_and_add. When compiling the wrapper file, be sure to
-- reference the XilinxCoreLib VHDL simulation library. For detailed
-- instructions, please refer to the "CORE Generator Help".

