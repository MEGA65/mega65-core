/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: tremolo.sv
#   AUTHOR: Greg Taylor     CREATION DATE: 2 Nov 2014
#
#   DESCRIPTION:
#
#   CHANGE HISTORY:
#   2 Nov 2014    Greg Taylor
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
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
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
#
# Converted from systemVerilog to Verilog and reduced to the OPL2 subset
# Copyright (C) 2018 Magnus Karlsson <magnus@saanlima.com>
#
*******************************************************************************/

`timescale 1ns / 1ps

`include "opl3.vh"

module tremolo (
    input wire clk,
    input wire reset,
    input wire sample_clk_en,
    input wire [`OP_NUM_WIDTH-1:0] op_num,            
    input wire dam, // depth of tremolo
    output reg [`AM_VAL_WIDTH-1:0] am_val
);
    localparam TREMOLO_MAX_COUNT = 13*1024;
    localparam TREMOLO_INDEX_WIDTH = 14;
    
    reg [TREMOLO_INDEX_WIDTH-1:0] tremolo_index;
    wire [TREMOLO_INDEX_WIDTH-8-1:0] am_val_tmp0;
    wire [TREMOLO_INDEX_WIDTH-8-1:0] am_val_tmp1;
    
    /*
     * Low-Frequency Oscillator (LFO)
     * 3.7 Hz (Sample Freq/2**14)
     */            
    always @(posedge clk)
        if (reset)
            tremolo_index <= 0;
        else if (sample_clk_en && op_num == 0)
            if (tremolo_index == TREMOLO_MAX_COUNT - 1)
                tremolo_index <= 0;
            else
                tremolo_index <= tremolo_index + 1;
    
    assign am_val_tmp0 = tremolo_index >> 8;
    assign am_val_tmp1 = (am_val_tmp0 > 26) ? (2*26 + ~am_val_tmp0) : am_val_tmp0;
        
    always @(posedge clk)
        if (reset)
            am_val <= 0;
        else if (dam)
            am_val <= am_val_tmp1;
        else
            am_val <= am_val_tmp1 >> 2;
endmodule

	