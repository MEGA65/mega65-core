/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: env_rate_counter.sv
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

module env_rate_counter (
    input wire clk,
    input wire reset,
    input wire sample_clk_en,
    input wire [`OP_NUM_WIDTH-1:0] op_num,                  
    input wire ksr, // key scale rate    
    input wire nts, // keyboard split selection
    input wire [`REG_FNUM_WIDTH-1:0] fnum,    
    input wire [`REG_BLOCK_WIDTH-1:0] block,    
    input wire [`REG_ENV_WIDTH-1:0] requested_rate,
    output wire [`ENV_RATE_COUNTER_OVERFLOW_WIDTH-1:0] rate_counter_overflow
);
    localparam COUNTER_WIDTH = 15;
    localparam OVERFLOW_TMP_MAX_VALUE = 7<<15;
    
    wire [`ENV_RATE_COUNTER_OVERFLOW_WIDTH-1:0] rate_tmp0;
    wire [`ENV_RATE_COUNTER_OVERFLOW_WIDTH-1:0] rate_tmp1;
    wire [`ENV_RATE_COUNTER_OVERFLOW_WIDTH-1:0] rate_tmp2;
    wire [`ENV_RATE_COUNTER_OVERFLOW_WIDTH-1:0] effective_rate;
    wire [`ENV_RATE_COUNTER_OVERFLOW_WIDTH-1:0] rate_value;
    wire [`ENV_RATE_COUNTER_OVERFLOW_WIDTH-1:0] requested_rate_shifted;
    wire [1:0] rof;
    reg [COUNTER_WIDTH-1:0] counter [0:`NUM_OPERATORS_PER_BANK-1];
//  wire [$clog2(OVERFLOW_TMP_MAX_VALUE)-1:0] overflow_tmp;
    wire [`CLOG2(OVERFLOW_TMP_MAX_VALUE)-1:0] overflow_tmp;
    reg sample_clk_en_d0;
    
    assign rate_tmp0 = nts ? fnum[8] : fnum[9];
    assign rate_tmp1 = rate_tmp0 | (block << 1);
    assign rate_tmp2 = ksr ? rate_tmp1 : rate_tmp1 >> 2;
    assign requested_rate_shifted = requested_rate << 2;
    
    assign effective_rate = (rate_tmp2 + requested_rate_shifted > 60) ? 
     60 : rate_tmp2 + requested_rate_shifted;
        
    assign rate_value = effective_rate >> 2;
    assign rof = effective_rate[1:0];

    always @(posedge clk)
        if (reset)
            sample_clk_en_d0 <= 0;
        else
            sample_clk_en_d0 <= sample_clk_en;

    genvar i;
    generate
        for (i = 0; i < `NUM_OPERATORS_PER_BANK; i = i + 1) begin: named
            always @(posedge clk) begin
                if (reset)
                    counter[i] <= 0;
                else if (sample_clk_en_d0 && requested_rate != 0 && (op_num == i))
                    counter[i] <= counter[i] + ((4 | rof) << rate_value);
            end
        end
    endgenerate
        
    assign overflow_tmp = counter[op_num] + ((4 | rof) << rate_value);
    
    assign
        rate_counter_overflow = overflow_tmp >> 15;
    
endmodule

    