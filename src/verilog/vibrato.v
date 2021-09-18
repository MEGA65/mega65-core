/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: vibrato.sv
#   AUTHOR: Greg Taylor     CREATION DATE: 13 Oct 2014
#
#   DESCRIPTION:
#   Prepare the phase increment for the NCO (calc multiplier and vibrato)
#
#   CHANGE HISTORY:
#   13 Oct 2014    Greg Taylor
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

module vibrato (
    input wire clk,
    input wire reset,
    input wire sample_clk_en,   
    input wire [`REG_FNUM_WIDTH-1:0] fnum,
    input wire dvb,    
    output reg [`REG_FNUM_WIDTH-1:0] vib_val
);
    localparam VIBRATO_INDEX_WIDTH = 13;
    
    reg [VIBRATO_INDEX_WIDTH-1:0] vibrato_index = 0;
    wire [`REG_FNUM_WIDTH-1:0] delta0;
    wire [`REG_FNUM_WIDTH-1:0] delta1;
    wire [`REG_FNUM_WIDTH-1:0] delta2;
        
    /*
     * Low-Frequency Oscillator (LFO)
     * 6.07Hz (Sample Freq/2**13)
     */        
    always @(posedge clk)
        if (reset)
            vibrato_index <= 0;
        else if (sample_clk_en)
            vibrato_index <= vibrato_index + 1;
        
    assign delta0 = fnum >> 7;
    assign delta1 = ((vibrato_index >> 10) & 3) == 3 ? delta0 >> 1 : delta0;
    assign delta2 = !dvb ? delta1 >> 1 : delta1;
    
    always @(posedge clk)
        if (reset)
            vib_val <= 0;
        else
            vib_val <= ((vibrato_index >> 10) & 4) != 0 ? ~delta2 : delta2;
endmodule
