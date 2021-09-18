/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: opl3.sv
#   AUTHOR: Greg Taylor     CREATION DATE: 24 Feb 2015
#
#   DESCRIPTION:
#
#   CHANGE HISTORY:
#   24 Feb 2015        Greg Taylor
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
# Additional tweaks for Spartan 3 tools Skip Hansen 2019
#
*******************************************************************************/

`include "opl3.vh"

module opl2(
	// PGS - We use the 40.5MHz MEGA65 system clock for both
  clk,       // 40.5 MHz system clock
//  clk,       // 100 MHz system clock
//  OPL2_clk,  // 25 MHz OPL2 clock
  reset,     // active high
  opl2_we,   // register write
  opl2_data, // register data
  opl2_adr,  // register address
  kon,       // key on
  channel_a, // output channel a
  channel_b, // output channel b
  sample_clk,
  sample_clk_128   // 128 X sample rate clock
  );

  input         clk;
//  input         OPL2_clk;
  input         reset;
  input         opl2_we;
  input [7:0]   opl2_data;
  input [7:0]   opl2_adr;
  output [8:0]  kon;
  output signed [15:0] channel_a;
  output signed [15:0] channel_b;
  output sample_clk;
  output sample_clk_128;

  localparam OPERATOR_PIPELINE_DELAY = 7; 
  // 18 operators + idle state
  localparam NUM_OPERATOR_UPDATE_STATES = `NUM_OPERATORS_PER_BANK + 1;

  localparam
    IDLE = 0,
    CALC_OUTPUTS = 1;

  reg [7:0] opl2_reg[255:0];

  reg [9:0] cntr;
  reg sample_clk_en;

  reg nts;

  reg [17:0] am;
  reg [17:0] vib;
  reg [17:0] egt;
  reg [17:0] ksr;
  reg [3:0] mult[17:0];

  reg [1:0] ksl[17:0];
  reg [5:0] tl[17:0];

  reg [3:0] ar[17:0];
  reg [3:0] dr[17:0];

  reg [3:0] sl[17:0];
  reg [3:0] rr[17:0];

  reg [9:0] fnum[8:0];

  reg [8:0] kon;
  reg [2:0] block[8:0];
  reg sample_clk;
  reg sample_clk_128;

  reg dam;
  reg dvb;
  reg ryt;
  reg bd;
  reg sd;
  reg tom;
  reg tc;
  reg hh;

  reg [8:0] chb;
  reg [8:0] cha;
  reg [2:0] fb[8:0];
  reg [8:0] cnt;

  reg [1:0] ws[17:0];

  reg [9:0] fnum_tmp[17:0];
  reg [2:0] block_tmp[17:0];
  reg [2:0] fb_tmp[17:0];
  reg [2:0] op_type_tmp[17:0];
  reg [17:0] kon_tmp;
  reg [17:0] use_feedback;
  reg signed [12:0] modulation[17:0];

  reg [`CLOG2(OPERATOR_PIPELINE_DELAY)-1:0] delay_counter;
    
  reg [`CLOG2(NUM_OPERATOR_UPDATE_STATES)-1:0] delay_state;
  reg [`CLOG2(NUM_OPERATOR_UPDATE_STATES)-1:0] next_delay_state;
    
  reg [`CLOG2(`NUM_OPERATORS_PER_BANK)-1:0] op_num;

  wire signed [12:0] operator_out_tmp;
  reg signed [12:0] operator_out[17:0];

  wire latch_feedback_pulse;

  reg calc_state = IDLE;
  reg next_calc_state;
  
  reg [3:0] channel;

  reg signed [`SAMPLE_WIDTH-1:0] channel_2_op[8:0];

  reg signed [`CHANNEL_ACCUMULATOR_WIDTH-1:0] channel_a_acc_pre_clamp = 0;
  reg signed [`CHANNEL_ACCUMULATOR_WIDTH-1:0] channel_a_acc_pre_clamp_p[8:0];    
  reg signed [`CHANNEL_ACCUMULATOR_WIDTH-1:0] channel_b_acc_pre_clamp = 0;
  reg signed [`CHANNEL_ACCUMULATOR_WIDTH-1:0] channel_b_acc_pre_clamp_p[8:0];

  reg signed [`SAMPLE_WIDTH-1:0] channel_a;
  reg signed [`SAMPLE_WIDTH-1:0] channel_b;

  genvar i;
  generate
    for (i = 0; i < 256; i = i + 1) begin: named
      always @ (posedge clk) begin
        if (reset)
          opl2_reg[i] <= 8'd0;
        else if (opl2_we && (opl2_adr == i))
          opl2_reg[i] <= opl2_data;
      end
    end
  endgenerate

  always @(posedge clk)
    if (reset) begin
      cntr <= 10'd0;
      sample_clk_en <= 1'b0;
      sample_clk <= 1'b0;
    end else begin
    // Note: A "real" opl3 generates the sampling clock by dividing 14.318MHz
    // by 288 for sampling rate of 49715.2777..
    // 25 MHz clock (25 MHz/503 = 49702 Hz)
    // 40.5 MHz clock (40.5 MHz/814 = 49754 Hz)
//    cntr <= cntr == 9'd502 ? 9'd0 : cntr + 1'b1;
//      cntr <= cntr == 9'd499 ? 9'd0 : cntr + 1'b1;
      cntr <= cntr == 10'd813 ? 9'd0 : cntr + 1'b1;
      sample_clk_en <= cntr == 10'd0;
      sample_clk <= ~cntr[9];
      sample_clk_128 <= ~cntr[0];
    end

  /*
   * Registers that are not specific to a particular bank
   */
  always @(posedge clk)
    if (reset) begin
      nts <= 1'b0;
      dam <= 1'b0;
      dvb <= 1'b0;
      ryt <= 1'b0;
      bd  <= 1'b0;
      sd  <= 1'b0;
      tom <= 1'b0;
      tc  <= 1'b0;
      hh  <= 1'b0;
    end else if (sample_clk_en) begin
      nts <= opl2_reg[8][6];
      dam <= opl2_reg['hBD][7];
      dvb <= opl2_reg['hBD][6];
      ryt <= opl2_reg['hBD][5];
      bd  <= opl2_reg['hBD][4];
      sd  <= opl2_reg['hBD][3];
      tom <= opl2_reg['hBD][2];
      tc  <= opl2_reg['hBD][1];
      hh  <= opl2_reg['hBD][0];                 
    end
       
  generate
    for (i = 0; i < 6; i = i + 1) begin: name1
      always @(posedge clk) begin
        if (reset) begin
          am[i]   <= 1'b0;
          vib[i]  <= 1'b0;
          egt[i]  <= 1'b0;
          ksr[i]  <= 1'b0;
          mult[i] <= 4'd0;
            
          ksl[i] <= 2'd0;
          tl[i]  <= 6'd0;
            
          ar[i] <= 4'd0;
          dr[i] <= 4'd0;
            
          sl[i] <= 4'd0;
          rr[i] <= 4'd0;
            
          ws[i] <= 2'd0;        
        end else if (sample_clk_en) begin
          am[i]   <= opl2_reg['h20+i][7];
          vib[i]  <= opl2_reg['h20+i][6];
          egt[i]  <= opl2_reg['h20+i][5];
          ksr[i]  <= opl2_reg['h20+i][4];
          mult[i] <= opl2_reg['h20+i][3:0];
            
          ksl[i] <= opl2_reg['h40+i][7:6];
          tl[i]  <= opl2_reg['h40+i][5:0];
            
          ar[i] <= opl2_reg['h60+i][7:4];
          dr[i] <= opl2_reg['h60+i][3:0]; 
            
          sl[i] <= opl2_reg['h80+i][7:4];
          rr[i] <= opl2_reg['h80+i][3:0];
            
          ws[i] <= opl2_reg['hE0+i][1:0];           
        end
        end
      end
    endgenerate

    generate    
    for (i = 6; i < 12; i = i + 1) begin: name2
      always @(posedge clk) begin
        if (reset) begin
          am[i]   <= 1'b0;
          vib[i]  <= 1'b0;
          egt[i]  <= 1'b0;
          ksr[i]  <= 1'b0;
          mult[i] <= 4'd0;
            
          ksl[i] <= 2'd0;
          tl[i]  <= 6'd0;
            
          ar[i] <= 4'd0;
          dr[i] <= 4'd0;
            
          sl[i] <= 4'd0;
          rr[i] <= 4'd0;
            
          ws[i] <= 2'd0;        
        end else if (sample_clk_en) begin         
          am[i]   <= opl2_reg['h22+i][7];
          vib[i]  <= opl2_reg['h22+i][6];
          egt[i]  <= opl2_reg['h22+i][5];
          ksr[i]  <= opl2_reg['h22+i][4];
          mult[i] <= opl2_reg['h22+i][3:0];
              
          ksl[i] <= opl2_reg['h42+i][7:6];
          tl[i]  <= opl2_reg['h42+i][5:0];
              
          ar[i] <= opl2_reg['h62+i][7:4];
          dr[i] <= opl2_reg['h62+i][3:0];
              
          sl[i] <= opl2_reg['h82+i][7:4];
          rr[i] <= opl2_reg['h82+i][3:0];            
              
          ws[i] <= opl2_reg['hE2+i][1:0];         
        end
        end
      end
    endgenerate
    
    generate
    for (i = 12; i < 18; i = i + 1) begin: name3
      always @(posedge clk) begin
        if (reset) begin
          am[i]   <= 1'b0;
          vib[i]  <= 1'b0;
          egt[i]  <= 1'b0;
          ksr[i]  <= 1'b0;
          mult[i] <= 4'd0;
            
          ksl[i] <= 2'd0;
          tl[i]  <= 6'd0;
            
          ar[i] <= 4'd0;
          dr[i] <= 4'd0;
            
          sl[i] <= 4'd0;
          rr[i] <= 4'd0;
            
          ws[i] <= 2'd0;        
        end else if (sample_clk_en) begin            
          am[i]   <= opl2_reg['h24+i][7];
          vib[i]  <= opl2_reg['h24+i][6];
          egt[i]  <= opl2_reg['h24+i][5];
          ksr[i]  <= opl2_reg['h24+i][4];
          mult[i] <= opl2_reg['h24+i][3:0];
              
          ksl[i] <= opl2_reg['h44+i][7:6];
          tl[i]  <= opl2_reg['h44+i][5:0];
              
          ar[i] <= opl2_reg['h64+i][7:4];
          dr[i] <= opl2_reg['h64+i][3:0];
              
          sl[i] <= opl2_reg['h84+i][7:4];
          rr[i] <= opl2_reg['h84+i][3:0];
              
          ws[i] <= opl2_reg['hE4+i][1:0];         
        end
        end
      end
    endgenerate    

    generate
    for (i = 0; i < 9; i = i + 1) begin: name4
      always @(posedge clk) begin
        if (reset) begin
          fnum[i] <= 10'd0;

          kon[i] <= 1'b0;
          block[i] <= 3'd0;
          
          chb[i] <= 1'b0;
          cha[i] <= 1'b0;
          fb[i]  <= 3'd0;
          cnt[i] <= 1'b0;
        end else if (sample_clk_en) begin
          fnum[i][7:0] <= opl2_reg['hA0+i];
          fnum[i][9:8] <= opl2_reg['hB0+i][1:0];

          kon[i] <= opl2_reg['hB0+i][5];
          block[i] <= opl2_reg['hB0+i][4:2];
          
          chb[i] <= opl2_reg['hC0+i][5];
          cha[i] <= opl2_reg['hC0+i][4];
          fb[i]  <= opl2_reg['hC0+i][3:1];
          cnt[i] <= opl2_reg['hC0+i][0];                
        end
        end
      end
    endgenerate   

  always @ (*) begin
    /*
     * Operator input mappings
     * 
     */
    fnum_tmp[0] = fnum[0];
    block_tmp[0] = block[0];
    kon_tmp[0] = kon[0];
    fb_tmp[0] = fb[0];
    op_type_tmp[0] = `OP_NORMAL;
    use_feedback[0] = 1;
    modulation[0] = 0;
    
    fnum_tmp[3] = fnum[0];
    block_tmp[3] = block[0];
    kon_tmp[3] = kon[0];
    fb_tmp[3] = 0;
    op_type_tmp[3] = `OP_NORMAL;
    use_feedback[3] = 0;
    modulation[3] = cnt[0] ? 0 : operator_out[0];
    
    fnum_tmp[1] = fnum[1];
    block_tmp[1] = block[1];
    kon_tmp[1] = kon[1];
    fb_tmp[1] = fb[1];
    op_type_tmp[1] = `OP_NORMAL;
    use_feedback[1] = 1;
    modulation[1] = 0;
    
    fnum_tmp[4] = fnum[1];
    block_tmp[4] = block[1];
    kon_tmp[4] = kon[1];
    fb_tmp[4] = 0;
    op_type_tmp[4] = `OP_NORMAL;
    use_feedback[4] = 0;
    modulation[4] = cnt[1] ? 0 : operator_out[1];
    
    fnum_tmp[2] = fnum[2];
    block_tmp[2] = block[2];
    kon_tmp[2] = kon[2];
    fb_tmp[2] = fb[2];
    op_type_tmp[2] = `OP_NORMAL;
    use_feedback[2] = 1;
    modulation[2] = 0;
    
    fnum_tmp[5] = fnum[2];
    block_tmp[5] = block[2];
    kon_tmp[5] = kon[2];
    fb_tmp[5] = 0;
    op_type_tmp[5] = `OP_NORMAL;
    use_feedback[5] = 0;
    modulation[5] = cnt[2] ? 0 : operator_out[2];
    
    fnum_tmp[6] = fnum[3];
    block_tmp[6] = block[3];
    kon_tmp[6] = kon[3];
    fb_tmp[6] = fb[3];
    op_type_tmp[6] = `OP_NORMAL;
    use_feedback[6] = 1;
    modulation[6] = 0;

    fnum_tmp[9] = fnum[3];
    block_tmp[9] = block[3];
    kon_tmp[9] = kon[3];
    fb_tmp[9] = 0; 
    op_type_tmp[9] = `OP_NORMAL;
    use_feedback[9] = 0;
    modulation[9] = cnt[3] ? 0 : operator_out[6];

    fnum_tmp[7] = fnum[4];
    block_tmp[7] = block[4];
    kon_tmp[7] = kon[4];
    fb_tmp[7] = fb[4];
    op_type_tmp[7] = `OP_NORMAL;
    use_feedback[7] = 1;
    modulation[7] = 0;
    
    fnum_tmp[10] = fnum[4];
    block_tmp[10] = block[4];
    kon_tmp[10] = kon[4];
    fb_tmp[10] = 0;
    op_type_tmp[10] = `OP_NORMAL;
    use_feedback[10] = 0;
    modulation[10] = cnt[4] ? 0 : operator_out[7];

    fnum_tmp[8] = fnum[5];
    block_tmp[8] = block[5];
    kon_tmp[8] = kon[5];
    fb_tmp[8] = fb[5];
    op_type_tmp[8] = `OP_NORMAL;
    use_feedback[8] = 1;
    modulation[8] = 0;

    fnum_tmp[11] = fnum[5];
    block_tmp[11] = block[5];
    kon_tmp[11] = kon[5];
    fb_tmp[11] = 0;   
    op_type_tmp[11] = `OP_NORMAL;
    use_feedback[11] = 0;
    modulation[11] = cnt[5] ? 0 : operator_out[8];

    // aka bass drum operator 1
    fnum_tmp[12] = fnum[6];
    block_tmp[12] = block[6];
    kon_tmp[12] = kon[6];
    fb_tmp[12] = fb[6];
    op_type_tmp[12] = ryt ? `OP_BASS_DRUM : `OP_NORMAL;
    use_feedback[12] = 1;
    modulation[12] = 0;
    
    // aka bass drum operator 2
    fnum_tmp[15] = fnum[6];
    block_tmp[15] = block[6];
    kon_tmp[15] = kon[6];
    fb_tmp[15] = 0;
    op_type_tmp[15] = ryt ? `OP_BASS_DRUM : `OP_NORMAL;
    use_feedback[15] = 0;
    modulation[15] = cnt[6] ? 0 : operator_out[12];
    
    // aka hi hat operator
    fnum_tmp[13] = fnum[7];
    block_tmp[13] = block[7];
    kon_tmp[13] = kon[7];
    fb_tmp[13] = ryt ? 0 : fb[7];
    op_type_tmp[13] = ryt ? `OP_HI_HAT : `OP_NORMAL;
    use_feedback[13] = ryt ? 0 : 1;
    modulation[13] = 0;
    
    // aka snare drum operator
    fnum_tmp[16] = fnum[7];
    block_tmp[16] = block[7];
    kon_tmp[16] = kon[7];
    fb_tmp[16] = 0;
    op_type_tmp[16] = ryt ? `OP_SNARE_DRUM : `OP_NORMAL;        
    use_feedback[16] = 0;
    modulation[16] = cnt[7] || ryt ? 0 : operator_out[13];
    
    // aka tom tom operator
    fnum_tmp[14] = fnum[8];
    block_tmp[14] = block[8];
    kon_tmp[14] = kon[8];
    fb_tmp[14] = ryt ? 0 : fb[8];
    op_type_tmp[14] = ryt ? `OP_TOM_TOM : `OP_NORMAL;        
    use_feedback[14] = ryt ? 0 : 1;
    modulation[14] = 0;
    
    // aka top cymbal operator
    fnum_tmp[17] = fnum[8];
    block_tmp[17] = block[8];
    kon_tmp[17] = kon[8];
    fb_tmp[17] = 0;
    op_type_tmp[17] = ryt ? `OP_TOP_CYMBAL : `OP_NORMAL;
    use_feedback[17] = 0;
    modulation[17] = cnt[8] || ryt ? 0 : operator_out[14];
  end

  always @(posedge clk)
    if (reset)
      delay_state <= 5'd0;
    else
      delay_state <= next_delay_state;
      
  always @ (*)
    if (delay_state == 0)
      next_delay_state = sample_clk_en ? 1 : 0;
    else if (delay_counter == OPERATOR_PIPELINE_DELAY - 1)
      if (delay_state == NUM_OPERATOR_UPDATE_STATES - 1)
        next_delay_state = 0;
      else
        next_delay_state = delay_state + 1;
    else
      next_delay_state = delay_state;
      
  always @(posedge clk)
    if (reset)
      delay_counter <= 0;
    else begin
      if (next_delay_state != delay_state)
        delay_counter <= 0;
      else if (delay_counter == OPERATOR_PIPELINE_DELAY - 1)
        delay_counter <= 0;
      else
        delay_counter <= delay_counter + 1;
    end

  always @ (*) 
    if (delay_state == 0)
      op_num = 0;
    else
      op_num = delay_state - 1;

  /*
   * One operator is instantiated; it replicates the necessary registers for
   * all operator slots (phase accumulation, envelope state and value, etc).
   */    
  operator operator_inst(
    .clk(clk),
    .reset(reset),
    .sample_clk_en(delay_state != 0 && delay_counter == 0),
    .op_num(op_num),              
    .fnum(fnum_tmp[op_num]),
    .mult(mult[op_num]),
    .block(block_tmp[op_num]),
    .ws(ws[op_num]),
    .vib(vib[op_num]),
    .kon(kon_tmp),  
    .ar(ar[op_num]),
    .dr(dr[op_num]),
    .sl(sl[op_num]),
    .rr(rr[op_num]),
    .tl(tl[op_num]),
    .ksr(ksr[op_num]),
    .ksl(ksl[op_num]),
    .egt(egt[op_num]),
    .am(am[op_num]),
    .dam(dam),
    .dvb(dvb),
    .nts(nts),
    .bd(bd),
    .sd(sd),
    .tom(tom),
    .tc(tc),
    .hh(hh),        
    .use_feedback(use_feedback[op_num]),
    .fb(fb_tmp[op_num]),
    .modulation(modulation[op_num]),
    .op_type(op_type_tmp[op_num]),
    .latch_feedback_pulse(latch_feedback_pulse),
    .out(operator_out_tmp)
  );   

  always @(posedge clk) begin
    if (delay_counter == OPERATOR_PIPELINE_DELAY - 1)
      operator_out[op_num] <= operator_out_tmp;
  end
      
  /*
   * Signals to operator to latch output for feedback register
   */
  assign
    latch_feedback_pulse = delay_counter == OPERATOR_PIPELINE_DELAY - 1;     
  
  
  always @(posedge clk)
    if (reset)
      calc_state <= IDLE;
    else
      calc_state <= next_calc_state;
    
  always @ (*)
    case (calc_state)
    IDLE: next_calc_state = sample_clk_en ? CALC_OUTPUTS : IDLE;
    CALC_OUTPUTS: next_calc_state = channel == 8 ? IDLE : CALC_OUTPUTS;
    endcase
      
  always @(posedge clk) begin
    if (calc_state == IDLE || channel == 8)
      channel <= 0;
    else
      channel <= channel + 1;
    end


  always @ (*) begin

    channel_2_op[0] = cnt[0] ? operator_out[0] + operator_out[3]
     : operator_out[3];
    channel_2_op[1] = cnt[1] ? operator_out[1] + operator_out[4]
     : operator_out[4];
    channel_2_op[2] = cnt[2] ? operator_out[2] + operator_out[5]
     : operator_out[5];        
    channel_2_op[3] = cnt[3] ? operator_out[6] + operator_out[9]
     : operator_out[9];
    channel_2_op[4] = cnt[4] ? operator_out[7] + operator_out[10]
     : operator_out[10];
    channel_2_op[5] = cnt[5] ? operator_out[8] + operator_out[11]
     : operator_out[11];
    
    if (ryt)               
      // bass drum is special
      channel_2_op[6] = cnt[6] ? operator_out[15] : operator_out[12];
    else
      channel_2_op[6] = cnt[6] ? operator_out[12] + operator_out[15]
       : operator_out[15];
    
    // aka hi hat and snare drum
    channel_2_op[7] = cnt[7] || (ryt) ? operator_out[13] + operator_out[16]
     : operator_out[16];   
    
    // aka tom tom and top cymbal
    channel_2_op[8] = cnt[8] || (ryt)  ? operator_out[14] + operator_out[17]
     : operator_out[17];

  end
    
  always @(posedge clk) begin
    channel_a_acc_pre_clamp_p[0] <= cha[0] ? channel_2_op[0] : 0;
    channel_a_acc_pre_clamp_p[1] <= cha[1] ? channel_2_op[1] : 0;
    channel_a_acc_pre_clamp_p[2] <= cha[2] ? channel_2_op[2] : 0;
    channel_a_acc_pre_clamp_p[3] <= cha[3] ? channel_2_op[3] : 0;
    channel_a_acc_pre_clamp_p[4] <= cha[4] ? channel_2_op[4] : 0;
    channel_a_acc_pre_clamp_p[5] <= cha[5] ? channel_2_op[5] : 0;
    channel_a_acc_pre_clamp_p[6] <= cha[6] ? channel_2_op[6] : 0;
    channel_a_acc_pre_clamp_p[7] <= cha[7] ? channel_2_op[7] : 0;
    channel_a_acc_pre_clamp_p[8] <= cha[8] ? channel_2_op[8] : 0;
    channel_b_acc_pre_clamp_p[0] <= chb[0] ? channel_2_op[0] : 0;
    channel_b_acc_pre_clamp_p[1] <= chb[1] ? channel_2_op[1] : 0;
    channel_b_acc_pre_clamp_p[2] <= chb[2] ? channel_2_op[2] : 0;
    channel_b_acc_pre_clamp_p[3] <= chb[3] ? channel_2_op[3] : 0;
    channel_b_acc_pre_clamp_p[4] <= chb[4] ? channel_2_op[4] : 0;
    channel_b_acc_pre_clamp_p[5] <= chb[5] ? channel_2_op[5] : 0;
    channel_b_acc_pre_clamp_p[6] <= chb[6] ? channel_2_op[6] : 0;
    channel_b_acc_pre_clamp_p[7] <= chb[7] ? channel_2_op[7] : 0;
    channel_b_acc_pre_clamp_p[8] <= chb[8] ? channel_2_op[8] : 0;
  end
  
  /*
   * Each channel is accumulated (can be up to 19 bits) and then clamped to
   * 16-bits.
   */
  always @(posedge clk)
    if (sample_clk_en)
      channel_a_acc_pre_clamp <= 0;
    else if (calc_state == CALC_OUTPUTS)
      channel_a_acc_pre_clamp <= channel_a_acc_pre_clamp + 
       channel_a_acc_pre_clamp_p[channel];
  
  always @(posedge clk)
    if (sample_clk_en)
      channel_b_acc_pre_clamp <= 0;
    else if (calc_state == CALC_OUTPUTS)
      channel_b_acc_pre_clamp <= channel_b_acc_pre_clamp + 
       channel_b_acc_pre_clamp_p[channel];

  /*
   * Clamp output channels
   */
  always @(posedge clk)
    if (sample_clk_en) begin
      if (channel_a_acc_pre_clamp > 2**15 - 1)
        channel_a <= 2**15 - 1;
      else if (channel_a_acc_pre_clamp < -2**15)
        channel_a <= -2**15;
      else
        channel_a <= channel_a_acc_pre_clamp;

      if (channel_b_acc_pre_clamp > 2**15 - 1)
        channel_b <= 2**15 - 1;
      else if (channel_b_acc_pre_clamp < -2**15)
        channel_b <= -2**15;
      else
        channel_b <= channel_b_acc_pre_clamp;
    end

endmodule
