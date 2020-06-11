/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: opl3_pkg.sv
#   AUTHOR: Greg Taylor     CREATION DATE: 13 Oct 2014
#
#   DESCRIPTION:
#   Generates a clk enable pulse based on the frequency specified by
#   OUTPUT_CLK_EN_FREQ.
#
#   CHANGE HISTORY:
#   13 Oct 2014        Greg Taylor
#       Initial version
#
#   Copyright (C) 2014 Greg Taylor <gtaylor@sonic.net>
#    
#   This file is part of OPL3 FPGA.
#    
#   OPL3 FPGA is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Lesser General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#   
#   OPL3 FPGA is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Lesser General Public License for more details.
#   
#   You should have received a copy of the GNU Lesser General Public License
#   along with OPL3 FPGA.  If not, see <http://www.gnu.org/licenses/>.
#   
#   Original Java Code: 
#   Copyright (C) 2008 Robson Cozendey <robson@cozendey.com>
#   
#   Original C++ Code: 
#   Copyright (C) 2012  Steffen Ohrendorf <steffen.ohrendorf@gmx.de>
#   
#   Some code based on forum posts in: 
#   http://forums.submarine.org.uk/phpBB/viewforum.php?f=9,
#   Copyright (C) 2010-2013 by carbon14 and opl3    
#   
#******************************************************************************/

/******************************************************************************
# converted from systemVerilog to Verilog by Magnus Karlsson
*******************************************************************************/

`define REG_MULT_WIDTH 4
`define REG_FNUM_WIDTH 10
`define REG_BLOCK_WIDTH 3
`define REG_WS_WIDTH 2
`define REG_ENV_WIDTH 4
`define REG_TL_WIDTH 6
`define REG_KSL_WIDTH 2
`define REG_FB_WIDTH 3
    
`define SAMPLE_WIDTH 16
`define ENV_WIDTH 9
`define OP_OUT_WIDTH 13
`define PHASE_ACC_WIDTH 20
`define AM_VAL_WIDTH 5
`define ENV_RATE_COUNTER_OVERFLOW_WIDTH 8
`define CHANNEL_ACCUMULATOR_WIDTH 19    
    
`define NUM_OPERATORS_PER_BANK 18
`define NUM_CHANNELS_PER_BANK 9
`define OP_NUM_WIDTH 5

`define OP_NORMAL 0
`define OP_BASS_DRUM 1
`define OP_HI_HAT 2
`define OP_TOM_TOM 3
`define OP_SNARE_DRUM 4
`define OP_TOP_CYMBAL 5

`define CLOG2(x) \
   (x <= 2) ? 1 : (\
   (x <= 4) ? 2 : (\
   (x <= 8) ? 3 : (\
   (x <= 16) ? 4 : (\
   (x <= 32) ? 5 : (\
   (x <= 64) ? 6 : (\
   (x <= 128) ? 7 : (\
   (x <= 256) ? 8 : (\
   (x <= 512) ? 9 : (\
   (x <= 1024) ? 10 : (\
   (x <= 2048) ? 11 : (\
   (x <= 4196) ? 12 : (\
   (x <= 8192) ? 13 : (\
   (x <= 16384) ? 14 : (\
   (x <= 32768) ? 15 : (\
   (x <= 32768) ? 16 : (\
   (x <= 131072) ? 17 : (\
   (x <= 262144) ? 18 : (\
   (x <= 524288) ? 19 : (\
   (x <= 1048576) ? 20 : (\
   (x <= 2097152) ? 21 : (\
   (x <= 4194304) ? 22 : (\
   (x <= 8388608) ? 23 : (\
   (x <= 4194304) ? 24 : (\
   (x <= 16777216) ? 25 : (\
   (x <= 33554432) ? 26 : (\
   -1))))))))))))))))))))))))))
