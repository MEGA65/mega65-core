----------------------------------------------------------------------
----                                                              ----
---- WD1772 compatible floppy disk controller IP Core.            ----
----                                                              ----
---- This file is part of the SUSKA ATARI clone project.          ----
---- http://www.experiment-s.de                                   ----
----                                                              ----
---- Description:                                                 ----
---- Floppy disk controller with all features of the Western      ----
---- Digital WD1772-02 controller.                                ----
----                                                              ----
---- Top level file for use in systems on programmable chips.     ----
----                                                              ----
----                                                              ----
---- To Do:                                                       ----
---- - Test of the FM portion of the code (if there is any need). ----
---- - Test of the read track command.                            ----
---- - Test of the read address command.                          ----
----                                                              ----
---- Author(s):                                                   ----
---- - Wolfgang Foerster, wf@experiment-s.de; wf@inventronik.de   ----
----                                                              ----
----------------------------------------------------------------------
----                                                              ----
---- Copyright (C) 2006 - 2008 Wolfgang Foerster                  ----
----                                                              ----
---- This source file may be used and distributed without         ----
---- restriction provided that this copyright statement is not    ----
---- removed from the file and that any derivative work contains  ----
---- the original copyright notice and the associated disclaimer. ----
----                                                              ----
---- This source file is free software; you can redistribute it   ----
---- and/or modify it under the terms of the GNU Lesser General   ----
---- Public License as published by the Free Software Foundation; ----
---- either version 2.1 of the License, or (at your option) any   ----
---- later version.                                               ----
----                                                              ----
---- This source is distributed in the hope that it will be       ----
---- useful, but WITHOUT ANY WARRANTY; without even the implied   ----
---- warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ----
---- PURPOSE. See the GNU Lesser General Public License for more  ----
---- details.                                                     ----
----                                                              ----
---- You should have received a copy of the GNU Lesser General    ----
---- Public License along with this source; if not, download it   ----
---- from http://www.gnu.org/licenses/lgpl.html                   ----
----                                                              ----
----------------------------------------------------------------------
-- 
-- Revision History
-- 
-- Revision 2006A  2006/06/03 WF
--   Initial Release: the MFM portion for HD and DD floppies is tested.
--   The FM mode (DDEn = '1') is not completely tested due to the lack 
--   of FM drives.
-- Revision 2K6B  2006/11/05 WF
--   Modified Source to compile with the Xilinx ISE.
--   Fixed the polarity of the precompensation flag.
--   The flag is no active '0'. Thanks to Jorma Oksanen for the information.
--   Top level file provided for SOC (systems on programmable chips).
-- Revision 2K7B  2006/12/29 WF
--   Introduced several improvements based on a very good examination
--   of the pll code by Jean Louis-Guerin.
-- Revision 2K8A  2008/07/14 WF
--   Minor changes.
-- Revision 2K8B  2008/12/24 WF
--   Bugfixes in the controller due to hanging state machine.
--   Removed CRC_BUSY.
--

library work;
use work.WF1772IP_PKG.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity WF1772IP_TOP_SOC is
	port (
		CLK			: in bit; -- 16MHz clock!
		RESETn		: in bit;
		CSn			: in bit;
		RWn			: in bit;
		A1, A0		: in bit;
		DATA_IN		: in std_logic_vector(7 downto 0);
		DATA_OUT	: out std_logic_vector(7 downto 0);
		DATA_EN		: out bit;
		RDn			: in bit;
		TR00n		: in bit;
		IPn			: in bit;
		WPRTn		: in bit;
		DDEn		: in bit;
		HDTYPE		: in bit; -- '0' = DD disks, '1' = HD disks.
		MO			: out bit;
		WG			: out bit;
		WD			: out bit;
		STEP		: out bit;
		DIRC		: out bit;
		DRQ			: out bit;
		INTRQ		: out bit
	);
end entity WF1772IP_TOP_SOC;
	
architecture STRUCTURE of WF1772IP_TOP_SOC is
signal DATA_OUT_REG		: std_logic_vector(7 downto 0);
signal DATA_EN_REG		: bit;
signal CMD_I			: std_logic_vector(7 downto 0);
signal DR_I				: bit_vector(7 downto 0);
signal DSR_I			: std_logic_vector(7 downto 0);
signal TR_I				: std_logic_vector(7 downto 0);
signal SR_I				: std_logic_vector(7 downto 0);
signal ID_AM_I			: bit;
signal DATA_AM_I		: bit;
signal DDATA_AM_I		: bit;
signal AM_TYPE_I		: bit;
signal AM_2_DISK_I		: bit;
signal DATA_STRB_I		: bit;
signal BUSY_I			: bit;
signal DRQ_I			: bit;
signal DRQ_IPn_I		: bit;
signal LD_TR00_I		: bit;
signal SP_RT_I			: bit;
signal SEEK_RNF_I		: bit;
signal WR_PR_I			: bit;
signal MO_I				: bit;
signal PLL_DSTRB_I		: bit;
signal PLL_D_I			: bit;
signal CRC_SD_I			: bit;
signal CRC_ERR_I		: bit;
signal CRC_PRES_I		: bit;
signal CRC_ERRFLAG_I	: bit;
signal SD_R_I			: bit;
signal CRC_SDOUT_I		: bit;
signal SHFT_LOAD_SD_I	: bit;
signal SHFT_LOAD_ND_I	: bit;
signal WR_In			: bit;
signal TR_PRES_I		: bit;
signal TR_CLR_I			: bit;
signal TR_INC_I			: bit;
signal TR_DEC_I			: bit;
signal SR_LOAD_I		: bit;
signal SR_INC_I			: bit;
signal DR_CLR_I			: bit;
signal DR_LOAD_I		: bit;
signal TRACK_NR_I		: std_logic_vector(7 downto 0);
signal CRC_2_DISK_I		: bit;
signal DSR_2_DISK_I		: bit;
signal FF_2_DISK_I		: bit;
signal PRECOMP_EN_I		: bit;
signal DISK_RWn_I		: bit;
signal WDATA_I			: bit;
begin
	-- Three state data bus:
	DATA_OUT <= DATA_OUT_REG when DATA_EN_REG = '1' else (others => '0');
	DATA_EN <= DATA_EN_REG;

	-- Some signals copied to the outputs:
    WD <= not WR_In;
	MO <= MO_I;
	DRQ <= DRQ_I;

	-- Write deleted data address mark in MFM mode in 'Write Sector' command in
	-- case of asserted command bit 0.
	AM_TYPE_I <= '0' when CMD_I(7 downto 5) = "101" and CMD_I(0) = '1' else '1';

	-- The CRC unit is used during read from disk and write to disk.
	-- This is the data multiplexer for the data stream to encode.
	CRC_SD_I <= SD_R_I when DISK_RWn_I = '1' else WDATA_I;

	I_CONTROL: WF1772IP_CONTROL
		port map(
            CLK				=> CLK,
			RESETn			=> RESETn,
			A1				=> A0,
			A0				=> A1,
			RWn				=> RWn,
			CSn				=> CSn,
			DDEn			=> DDEn,
			DR				=> DR_I,
			CMD				=> CMD_I,
			DSR				=> DSR_I,
			TR				=> TR_I,
			SR				=> SR_I,
			MO				=> MO_I,
			WR_PR			=> WR_PR_I,
			SPINUP_RECTYPE	=> SP_RT_I,
			SEEK_RNF		=> SEEK_RNF_I,
			CRC_ERRFLAG		=> CRC_ERRFLAG_I,
			LOST_DATA_TR00	=> LD_TR00_I,
			DRQ				=> DRQ_I,
			DRQ_IPn			=> DRQ_IPn_I,
			BUSY			=> BUSY_I,
			AM_2_DISK		=> AM_2_DISK_I,
			ID_AM			=> ID_AM_I,
			DATA_AM			=> DATA_AM_I,
			DDATA_AM		=> DDATA_AM_I,
			CRC_ERR			=> CRC_ERR_I,
			CRC_PRES		=> CRC_PRES_I,
			TR_PRES			=> TR_PRES_I,
			TR_CLR			=> TR_CLR_I,
			TR_INC			=> TR_INC_I,
			TR_DEC			=> TR_DEC_I,
			SR_LOAD			=> SR_LOAD_I,
			SR_INC			=> SR_INC_I,
			TRACK_NR		=> TRACK_NR_I,
			DR_CLR			=> DR_CLR_I,
			DR_LOAD			=> DR_LOAD_I,
			SHFT_LOAD_SD	=> SHFT_LOAD_SD_I,
			SHFT_LOAD_ND	=> SHFT_LOAD_ND_I,
			CRC_2_DISK		=> CRC_2_DISK_I,
			DSR_2_DISK		=> DSR_2_DISK_I,
			FF_2_DISK		=> FF_2_DISK_I,
			PRECOMP_EN		=> PRECOMP_EN_I,
			DATA_STRB		=> DATA_STRB_I,
			DISK_RWn		=> DISK_RWn_I,
			WPRTn			=> WPRTn,
			TRACK00n		=> TR00n,
			IPn				=> IPn,
			DIRC			=> DIRC,
			STEP			=> STEP,
			WG				=> WG,
			INTRQ			=> INTRQ
		);

	I_REGISTERS: WF1772IP_REGISTERS
		port map(
			CLK				=> CLK,
			RESETn			=> RESETn,
			CSn				=> CSn,
			ADR(1)			=> A1,
			ADR(0)			=> A0,
			RWn				=> RWn,
			DATA_IN			=> DATA_IN,
			DATA_OUT		=> DATA_OUT_REG,
			DATA_EN			=> DATA_EN_REG,
			CMD				=> CMD_I,
			TR				=> TR_I,
			SR				=> SR_I,
			DSR				=> DSR_I,
			DR				=> DR_I,
			SD_R			=> SD_R_I,
			DATA_STRB		=> DATA_STRB_I,
			DR_CLR			=> DR_CLR_I,
			DR_LOAD			=> DR_LOAD_I,
			TR_PRES			=> TR_PRES_I,
			TR_CLR			=> TR_CLR_I,
			TR_INC			=> TR_INC_I,
			TR_DEC			=> TR_DEC_I,
			TRACK_NR		=> TRACK_NR_I,
			SR_LOAD			=> SR_LOAD_I,
			SR_INC			=> SR_INC_I,
			SHFT_LOAD_SD	=> SHFT_LOAD_SD_I,
			SHFT_LOAD_ND	=> SHFT_LOAD_ND_I,
			MOTOR_ON		=> MO_I,
			WRITE_PROTECT	=> WR_PR_I,
			SPINUP_RECTYPE	=> SP_RT_I,
			SEEK_RNF		=> SEEK_RNF_I,
			CRC_ERRFLAG		=> CRC_ERRFLAG_I,
			LOST_DATA_TR00	=> LD_TR00_I,
			DRQ				=> DRQ_I,
			DRQ_IPn			=> DRQ_IPn_I,
			BUSY			=> BUSY_I,
			DDEn			=> DDEn
		);

	I_DIGITAL_PLL: WF1772IP_DIGITAL_PLL
		port map(
			CLK			=> CLK,
			RESETn		=> RESETn,
			DDEn		=> DDEn,
			HDTYPE 		=> HDTYPE,
			DISK_RWn	=> DISK_RWn_I,
			RDn			=> RDn,
			PLL_D		=> PLL_D_I,
			PLL_DSTRB	=> PLL_DSTRB_I
		);

	I_AM_DETECTOR: WF1772IP_AM_DETECTOR
		port map(
			CLK			=> CLK,
			RESETn		=> RESETn,
			DDEn		=> DDEn,
			DATA		=> PLL_D_I,
			DATA_STRB	=> PLL_DSTRB_I,
			ID_AM		=> ID_AM_I,
			DATA_AM		=> DATA_AM_I,
			DDATA_AM	=> DDATA_AM_I
		);

	I_CRC_LOGIC: WF1772IP_CRC_LOGIC
		port map(
			CLK			=> CLK,
			RESETn		=> RESETn,
			DDEn		=> DDEn,
			DISK_RWn	=> DISK_RWn_I,
			ID_AM		=> ID_AM_I,
			DATA_AM		=> DATA_AM_I,
			DDATA_AM	=> DDATA_AM_I,
			SD			=> CRC_SD_I,
			CRC_STRB	=> DATA_STRB_I,
			CRC_2_DISK	=> CRC_2_DISK_I,
			CRC_PRES	=> CRC_PRES_I,
			CRC_SDOUT	=> CRC_SDOUT_I,
			CRC_ERR		=> CRC_ERR_I
		);

	I_TRANSCEIVER: WF1772IP_TRANSCEIVER
		port map(
			CLK				=> CLK,
			RESETn			=> RESETn,
			DDEn			=> DDEn,
			HDTYPE 			=> HDTYPE,
			ID_AM			=> ID_AM_I,
			DATA_AM			=> DATA_AM_I,
			DDATA_AM		=> DDATA_AM_I,
			SHFT_LOAD_SD	=> SHFT_LOAD_SD_I,
			DR				=> DR_I,
			PRECOMP_EN		=> PRECOMP_EN_I,
			AM_TYPE			=> AM_TYPE_I,
			AM_2_DISK		=> AM_2_DISK_I,
			CRC_2_DISK		=> CRC_2_DISK_I,
			DSR_2_DISK		=> DSR_2_DISK_I,
			FF_2_DISK		=> FF_2_DISK_I,
			SR_SDOUT		=> DSR_I(7),
			CRC_SDOUT		=> CRC_SDOUT_I,
			WRn				=> WR_In,
			WDATA			=> WDATA_I,
			PLL_DSTRB		=> PLL_DSTRB_I,
			PLL_D			=> PLL_D_I,
			DATA_STRB		=> DATA_STRB_I,
			SD_R			=> SD_R_I
		);
end architecture STRUCTURE;
