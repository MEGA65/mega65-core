/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: operator.sv
#   AUTHOR: Greg Taylor     CREATION DATE: 13 Oct 2014
#
#   DESCRIPTION:
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

module operator (
    input wire clk,
    input wire reset,
    input wire sample_clk_en,
    input wire [`OP_NUM_WIDTH-1:0] op_num,              
    input wire [`REG_FNUM_WIDTH-1:0] fnum,
    input wire [`REG_MULT_WIDTH-1:0] mult,
    input wire [`REG_BLOCK_WIDTH-1:0] block,
    input wire [`REG_WS_WIDTH-1:0] ws,
    input wire vib,
    input wire dvb,
    input wire [`NUM_OPERATORS_PER_BANK-1:0] kon,  
    input wire [`REG_ENV_WIDTH-1:0] ar, // attack rate
    input wire [`REG_ENV_WIDTH-1:0] dr, // decay rate
    input wire [`REG_ENV_WIDTH-1:0] sl, // sustain level
    input wire [`REG_ENV_WIDTH-1:0] rr, // release rate
    input wire [`REG_TL_WIDTH-1:0] tl,  // total level
    input wire ksr,                    // key scale rate
    input wire [`REG_KSL_WIDTH-1:0] ksl, // key scale level
    input wire egt,                     // envelope type
    input wire am,                      // amplitude modulation (tremolo)
    input wire dam,                     // depth of tremolo
    input wire nts,                     // keyboard split selection
    input wire bd,
    input wire sd,
    input wire tom,
    input wire tc,
    input wire hh,        
    input wire use_feedback,
    input wire [`REG_FB_WIDTH-1:0] fb,
    input wire [`OP_OUT_WIDTH-1:0] modulation,
    input wire latch_feedback_pulse,
    input wire [2:0] op_type,
    output wire signed [`OP_OUT_WIDTH-1:0] out
);

    wire [`NUM_OPERATORS_PER_BANK-1:0] key_on_pulse_array;
    wire [`NUM_OPERATORS_PER_BANK-1:0] key_off_pulse_array;
    wire bd_on_pulse;
    wire sd_on_pulse;
    wire tom_on_pulse;
    wire tc_on_pulse;
    wire hh_on_pulse;
    wire key_on_pulse;
    wire key_off_pulse;
    wire [`PHASE_ACC_WIDTH-1:0] phase_inc;
    wire [`ENV_WIDTH-1:0] env;
    reg signed [`OP_OUT_WIDTH-1:0] feedback1 [0:`NUM_OPERATORS_PER_BANK-1];
    reg signed [`OP_OUT_WIDTH-1:0] feedback2 [0:`NUM_OPERATORS_PER_BANK-1];
    wire signed [`OP_OUT_WIDTH-1:0] feedback_result;
    reg signed [`OP_OUT_WIDTH+1+2**`REG_FB_WIDTH-1:0] feedback_result_p0;
    wire rhythm_kon_pulse;

    genvar j;
    generate
        for (j = 0; j < `NUM_OPERATORS_PER_BANK; j = j + 1) begin: detect
            // Detect key on and key off
            edge_detector #(
                .EDGE_LEVEL(1), 
                .CLK_DLY(1)
            ) key_on_edge_detect (
                .clk_en(j == op_num && sample_clk_en),
                .in(kon[j]), 
                .edge_detected(key_on_pulse_array[j]),
                .clk(clk)
            );
            
            edge_detector #(
                .EDGE_LEVEL(0), 
                .CLK_DLY(1)
            ) key_off_edge_detect (
                .clk_en(j == op_num && sample_clk_en && op_type == `OP_NORMAL),
                .in(kon[j]), 
                .edge_detected(key_off_pulse_array[j]),
                .clk(clk)
            );                                   
        end
    endgenerate  

    edge_detector #(
        .EDGE_LEVEL(1), 
        .CLK_DLY(1)
    ) bd_edge_detect (
        .clk_en(op_type == `OP_BASS_DRUM && sample_clk_en),
        .in(bd), 
        .edge_detected(bd_on_pulse),
        .clk(clk)
    );
    edge_detector #(
        .EDGE_LEVEL(1), 
        .CLK_DLY(1)
    ) sd_edge_detect (
        .clk_en(op_type == `OP_SNARE_DRUM && sample_clk_en),
        .in(sd), 
        .edge_detected(sd_on_pulse),
        .clk(clk)
    );
    edge_detector #(
        .EDGE_LEVEL(1), 
        .CLK_DLY(1)
    ) tom_edge_detect (
        .clk_en(op_type == `OP_TOM_TOM && sample_clk_en),
        .in(tom), 
        .edge_detected(tom_on_pulse),
        .clk(clk)
    );       
    edge_detector #(
        .EDGE_LEVEL(1), 
        .CLK_DLY(1)
    ) tc_edge_detect (
        .clk_en(op_type == `OP_TOP_CYMBAL && sample_clk_en),
        .in(tc), 
        .edge_detected(tc_on_pulse),
        .clk(clk)
    );
    edge_detector #(
        .EDGE_LEVEL(1), 
        .CLK_DLY(1)
    ) hh_edge_detect (
        .clk_en(op_type == `OP_HI_HAT && sample_clk_en),
        .in(hh), 
        .edge_detected(hh_on_pulse),
        .clk(clk)
    ); 

    assign rhythm_kon_pulse =
     (op_type == `OP_BASS_DRUM && bd_on_pulse) ||
     (op_type == `OP_SNARE_DRUM && sd_on_pulse) ||
     (op_type == `OP_TOM_TOM && tom_on_pulse) ||
     (op_type == `OP_TOP_CYMBAL && tc_on_pulse) ||
     (op_type == `OP_HI_HAT && hh_on_pulse);
    
    assign key_on_pulse = key_on_pulse_array[op_num] || rhythm_kon_pulse;
    assign key_off_pulse = key_off_pulse_array[op_num];
    
    /*
     * latch_feedback_pulse comes in the last cycle of the time slot so out has had a
     * chance to propagate through
     */
    generate
        for (j = 0; j < `NUM_OPERATORS_PER_BANK; j = j + 1) begin: named
            always @(posedge clk) begin
                if (reset) begin
                    feedback1[j] <= 0;
                    feedback2[j] <= 0;
                end else if (latch_feedback_pulse && (op_num == j)) begin
                    feedback1[j] <= out;
                    feedback2[j] <= feedback1[j];
                end
            end
        end
    endgenerate
    
    always @ *
        if (fb == 0)
            feedback_result_p0 = 0;
        else
            feedback_result_p0 = ((feedback1[op_num] +
             feedback2[op_num]) <<< fb);
        
    assign feedback_result = feedback_result_p0 >>> 9;
    
    calc_phase_inc calc_phase_inc (
        .clk(clk),
        .reset(reset),
        .sample_clk_en(sample_clk_en),  
        .fnum(fnum),
        .mult(mult),
        .block(block),
        .vib(vib),
        .dvb(dvb),
        .phase_inc(phase_inc)
    ); 
    
    envelope_generator envelope_generator (
        .clk(clk),
        .reset(reset),
        .sample_clk_en(sample_clk_en),
        .op_num(op_num),
        .ar(ar),
        .dr(dr),
        .sl(sl),
        .rr(rr),
        .tl(tl),
        .ksr(ksr),
        .ksl(ksl),
        .egt(egt),
        .am(am),
        .dam(dam),
        .nts(nts),
        .fnum(fnum),
        .block(block),
        .key_on_pulse(key_on_pulse),
        .key_off_pulse(key_off_pulse),
        .env(env)
    );

    /*
     * An operator that implements feedback does not take any modulation
     * input (it is always operator 1 in any channel scheme)
     */             
    phase_generator phase_generator (
        .clk(clk),
        .reset(reset),
        .sample_clk_en(sample_clk_en),
        .op_num(op_num),
        .phase_inc(phase_inc),
        .ws(ws),
        .env(env),
        .key_on_pulse(key_on_pulse),
        .modulation(use_feedback ? feedback_result : modulation),
        .op_type(op_type),
        .out(out)
    );
endmodule
