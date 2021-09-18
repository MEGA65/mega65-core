/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: phase_generator.sv
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

module phase_generator (
    input wire clk,
    input wire reset,
    input wire sample_clk_en,
    input wire [`OP_NUM_WIDTH-1:0] op_num,  
    input wire [`PHASE_ACC_WIDTH-1:0] phase_inc,
    input wire [`REG_WS_WIDTH-1:0] ws,
    input wire [`ENV_WIDTH-1:0] env,
    input wire key_on_pulse,
    input wire [`OP_OUT_WIDTH-1:0] modulation,
    input wire [2:0] op_type,    
    output reg signed [`OP_OUT_WIDTH-1:0] out
);	
    localparam LOG_SIN_OUT_WIDTH = 12;
    localparam EXP_OUT_WIDTH = 10;
    localparam LOG_SIN_PLUS_GAIN_WIDTH = 13;
    localparam PIPELINE_DELAY = 2;     
    
    reg [PIPELINE_DELAY-1:0] sample_clk_en_delayed;
    reg [`PHASE_ACC_WIDTH-1:0] phase_acc [0:`NUM_OPERATORS_PER_BANK-1];
    reg [`PHASE_ACC_WIDTH-1:0] final_phase [0:`NUM_OPERATORS_PER_BANK-1];
    wire [`PHASE_ACC_WIDTH-1:0] rhythm_phase;
    wire [LOG_SIN_OUT_WIDTH-1:0] log_sin_out; 
    wire [LOG_SIN_PLUS_GAIN_WIDTH-1:0] log_sin_plus_gain;     
    wire [EXP_OUT_WIDTH-1:0] exp_out;
    wire [`OP_OUT_WIDTH-1:0] tmp_out0;
    reg signed [`OP_OUT_WIDTH-1:0] tmp_out1;
    reg signed [`OP_OUT_WIDTH-1:0] tmp_out2;    
    wire signed [`OP_OUT_WIDTH-1:0] tmp_ws2;
    
    /*
     * sample_clk_en must be delayed so the phase_inc is correct when it is added
     * to the phase accumulator (inputs must settle for this time slot)
     */
    always @(posedge clk) begin
        if (reset)
            sample_clk_en_delayed <= 0;
        else begin
            sample_clk_en_delayed <= sample_clk_en_delayed << 1;
            sample_clk_en_delayed[0] <= sample_clk_en;
        end
    end
    
    /*
     * Some rhythm instruments require further transformations to the phase.
     * Pass through phase_acc[op_num] normally.
     */
    calc_rhythm_phase calc_rhythm_phase (
        .clk(clk),
        .reset(reset),
        .sample_clk_en(sample_clk_en),
        .op_num(op_num),
        .phase_acc(phase_acc[op_num]),
        .phase_acc_17(phase_acc[17]),
        .phase_acc_13(phase_acc[13]),
        .op_type(op_type),    
        .rhythm_phase(rhythm_phase)
    );

    /*
     * Phase Accumulator. Modulation gets added to the final phase but not
     * back into the accumulator.
     */
    always @(posedge clk)
        if (reset) begin
            phase_acc[op_num] <= 0;
            final_phase[op_num] <= 0;
        end else if (sample_clk_en_delayed[PIPELINE_DELAY-1])
            if (key_on_pulse) begin
                phase_acc[op_num] <= 0;
                final_phase[op_num] <= 0;
            end else begin
                phase_acc[op_num] <= phase_acc[op_num] + phase_inc;
                final_phase[op_num] <= rhythm_phase + phase_inc
                 + (modulation << 10);
            end
        
    assign tmp_ws2 = tmp_out1 < 0 ? ~tmp_out1 : tmp_out1;
                
    opl3_log_sine_lut log_sine_lut_inst (
        .theta(final_phase[op_num][18] ? ~final_phase[op_num][17:10]
         : final_phase[op_num][17:10]),
        .out(log_sin_out),
        .clk(clk),
        .reset(reset)
    );      
    
    assign log_sin_plus_gain = (log_sin_out) + (env << 3);
        
    opl3_exp_lut exp_lut_inst (
        .in(~log_sin_plus_gain[7:0]),
        .out(exp_out),
        .clk(clk),
        .reset(reset)
    );
    
    assign tmp_out0 = (2**10 + exp_out) << 1;
        
    always @ *
        if (final_phase[op_num][19])
            tmp_out1 = ~(tmp_out0 >> log_sin_plus_gain[LOG_SIN_PLUS_GAIN_WIDTH-1:8]);
        else
            tmp_out1 = tmp_out0 >> log_sin_plus_gain[LOG_SIN_PLUS_GAIN_WIDTH-1:8]; 
        
    /*
     * Select waveform, do proper transformations to the wave
     */
    always @ *
        case (ws)
        0: tmp_out2 = tmp_out1;
        1: tmp_out2 = tmp_out1 < 0 ? 0 : tmp_out1;
        2: tmp_out2 = tmp_ws2;
        3: tmp_out2 = final_phase[op_num][`PHASE_ACC_WIDTH-2] ? 0 : tmp_ws2;
        endcase 
            
    always @(posedge clk)
        if (reset)
            out <= 0;
        else
            case (op_type)
            `OP_NORMAL:    out <= tmp_out2;
            `OP_BASS_DRUM: out <= tmp_out2;
            default:      out <= tmp_out2 << 1;
            endcase      
endmodule

	
