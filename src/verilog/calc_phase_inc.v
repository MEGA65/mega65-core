/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: calc_phase_inc.sv
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

module calc_phase_inc (
    input wire clk,
    input wire reset,
    input wire sample_clk_en,     
    input wire [`REG_FNUM_WIDTH-1:0] fnum,
    input wire [`REG_MULT_WIDTH-1:0] mult,
    input wire [`REG_BLOCK_WIDTH-1:0] block,
    input wire vib,
    input wire dvb,
    output reg signed [`PHASE_ACC_WIDTH-1:0] phase_inc
);   
    wire signed [`PHASE_ACC_WIDTH-1:0] pre_mult;
    reg signed [`PHASE_ACC_WIDTH-1:0] post_mult;
    
    wire signed [`REG_FNUM_WIDTH-1:0] vib_val;
    
    assign pre_mult = fnum << block;

    reg signed [4:0] pre_mult_adj;
    always @(*) begin
        case (mult)
        'h0: pre_mult_adj <= 1;
        'h1: pre_mult_adj <= 1;
        'h2: pre_mult_adj <= 2;
        'h3: pre_mult_adj <= 3;
        'h4: pre_mult_adj <= 4;
        'h5: pre_mult_adj <= 5;
        'h6: pre_mult_adj <= 6;
        'h7: pre_mult_adj <= 7;
        'h8: pre_mult_adj <= 8;
        'h9: pre_mult_adj <= 9;
        'hA: pre_mult_adj <= 10;
        'hB: pre_mult_adj <= 10;
        'hC: pre_mult_adj <= 12;
        'hD: pre_mult_adj <= 12;
        'hE: pre_mult_adj <= 15;
        'hF: pre_mult_adj <= 15;
        default: pre_mult_adj <= 1;
        endcase
    end

    always @(posedge clk)
        if (reset)
            post_mult <= 0;
        else
            case (mult)
            'h0: post_mult <= pre_mult >> 1;
            default: post_mult <= pre_mult * pre_mult_adj;
            endcase
    
    always @ *
        if (vib)
            phase_inc = post_mult + vib_val;
        else
            phase_inc = post_mult;
    
    /*
     * Calculate vib_val
     */
    vibrato vibrato (
        .clk(clk),
        .reset(reset),
        .sample_clk_en(sample_clk_en),
        .fnum(fnum),
        .dvb(dvb),
        .vib_val(vib_val)
    );
endmodule
