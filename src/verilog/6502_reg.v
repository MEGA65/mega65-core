/* 
** Copyright (c) 2018 Kenneth C. Dyke
** 
** Permission is hereby granted, free of charge, to any person obtaining a copy
** of this software and associated documentation files (the "Software"), to deal
** in the Software without restriction, including without limitation the rights
** to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
** copies of the Software, and to permit persons to whom the Software is
** furnished to do so, subject to the following conditions:
** 
** The above copyright notice and this permission notice shall be included in all
** copies or substantial portions of the Software.
** 
** THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
** IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
** FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
** AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
** LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
** OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
** SOFTWARE.
*/

`include "6502_inc.vh"

`SCHEM_KEEP_HIER module clocked_reg8(input clk, input ready, input [7:0] register_in, `MARK_DEBUG output reg [7:0] register_out);

always @(posedge clk)
begin
  if(ready)
  begin
    register_out <= register_in;
  end
end

endmodule

`SCHEM_KEEP_HIER module clocked_reset_reg8(input clk, input reset, input ready, input [7:0] register_in, output reg [7:0] register_out);

always @(posedge clk)
begin
  if(reset)
    register_out <= 0;
  else if(ready)
  begin
    register_out <= register_in;
  end
end

endmodule

`SCHEM_KEEP_HIER module a_reg(input clk, input load_a, input [7:0] dec_in, input carry_in, input half_carry_in, 
                              input dec_add, input dec_sub, `MARK_DEBUG output reg [7:0] reg_a);
  
  wire [7:0] dec_out;
  
  decadj_half_adder  low(dec_in[3:0],dec_out[3:0], half_carry_in, dec_add, dec_sub, 1'b0);
  decadj_half_adder high(dec_in[7:4],dec_out[7:4], carry_in, dec_add, dec_sub, 1'b1);
  
  always @(posedge clk)
  begin
    if(load_a)
      reg_a <= dec_out;
  end
  
endmodule

`SCHEM_KEEP_HIER module p_reg(input clk, input reset, input ready, input intg, 
                              input [14:0] load_flag_decode, input load_b, input [7:0] db_in, 
                              input sb_z, input sb_n, input carry, input overflow, input ir5, `MARK_DEBUG output reg [7:0] reg_p);

always @(*)
begin
  reg_p[`PF_B] = ~intg;
  reg_p[`PF_U] = 1;
end

always @(posedge clk)
begin    
  if(ready)
  begin
    if(load_flag_decode[`LF_C_ACR])       reg_p[`PF_C] = carry;
    else if(load_flag_decode[`LF_C_IR5])  reg_p[`PF_C] = ir5;
    else if(load_flag_decode[`LF_C_DB0])  reg_p[`PF_C] = db_in[0];

    if(load_flag_decode[`LF_Z_SBZ])       reg_p[`PF_Z] = sb_z;
    else if(load_flag_decode[`LF_Z_DB1])  reg_p[`PF_Z] = db_in[1];
    
    if(load_flag_decode[`LF_I_DB2])       reg_p[`PF_I] = db_in[2];
    else if(load_flag_decode[`LF_I_IR5])  reg_p[`PF_I] = ir5;
    else if(load_flag_decode[`LF_I_1])    reg_p[`PF_I] = 1;

    if(load_flag_decode[`LF_D_DB3])       reg_p[`PF_D] = db_in[3];
    else if(load_flag_decode[`LF_D_IR5])  reg_p[`PF_D] = ir5;
    
    if(load_flag_decode[`LF_V_AVR])       reg_p[`PF_V] = overflow;
    else if(load_flag_decode[`LF_V_DB6])  reg_p[`PF_V] = db_in[6];
    else if(load_flag_decode[`LF_V_0])    reg_p[`PF_V] = 0;
      
    if(load_flag_decode[`LF_N_SBN])       reg_p[`PF_N] = sb_n;
    else if(load_flag_decode[`LF_N_DB7])  reg_p[`PF_N] = db_in[7];
  end
end

endmodule

`SCHEM_KEEP_HIER module adl_pcl_reg(input clk, input ready, input pcls_sel, input pc_inc, input [2:0] adl_sel, 
                                    input [7:0] reg_s, input [7:0] alu, output reg [7:0] pcl, output reg [7:0] pcls, output reg pcl_carry);

reg [7:0] adl_pcls;
reg [8:0] pcls_in;

always @(*)
begin
  if(pcls_sel == `PCLS_PCL)
    pcls_in = pcl + pc_inc;
  else
    pcls_in = adl_pcls;
  {pcl_carry, pcls} = pcls_in;
end

always @(*)
begin
  case(adl_sel) // synthesis full_case parallel_case
    `ADL_S     : adl_pcls = reg_s;
    `ADL_ALU   : adl_pcls = alu;
  endcase
end

always @(posedge clk)
begin
  if(ready)
  begin
    pcl <= pcls;
  end
end

endmodule


`SCHEM_KEEP_HIER module adh_pch_reg(input clk, input ready, input pchs_sel, input pcl_carry, 
                                    input [2:0] adh_sel, input [7:0] data_i, input [7:0] alu, 
                                    output reg [7:0] pchs, output reg [7:0] pch, output reg pch_carry);

reg [8:0] pchs_in;
reg [7:0] adh_pchs;

always @(*)
begin
  if(pchs_sel == `PCHS_PCH)
    pchs_in = pch + pcl_carry;
  else
    pchs_in = adh_pchs;
  {pch_carry,pchs} = pchs_in; // This is really weird.  If I don't try to keep the carry like for PCL, it actually uses *more* resources?
  //$display("phs_sel: %d pch: %02x adh: %02x pchs_in: %02x pchs: %02x",pchs_sel,pch,adh,pchs_in,pchs);
end

always @(*)
begin
  case(adh_sel)  // synthesis full_case parallel_case
    `ADH_DI  : adh_pchs = data_i;
    `ADH_ALU : adh_pchs = alu;
  endcase
end

always @(posedge clk)
begin
  if(ready)
  begin
    pch <= pchs;
  end
end

endmodule

`SCHEM_KEEP_HIER module adh_abh_reg(input clk, input ready, input load_abh, input [2:0] adh_sel, 
                                    input [7:0] data_i, input [7:0] pchs, input [7:0] alu, 
                                    output reg [7:0] abh_next, output reg [7:0] abh);

reg [7:0] adh_abh;

always @(*)
begin
  case(adh_sel)  // synthesis full_case parallel_case
    `ADH_DI  : adh_abh = data_i;
    `ADH_PCHS: adh_abh = pchs;
    `ADH_ALU : adh_abh = alu;
    `ADH_0   : adh_abh = 8'h00;
    `ADH_1   : adh_abh = 8'h01;
    `ADH_FF  : adh_abh = 8'hFF;
  endcase
end

always @(*)
begin
  if(load_abh && ready)
    abh_next = adh_abh;
  else
    abh_next = abh;
end

always @(posedge clk)
begin
  if(load_abh && ready)
  begin
    abh <= adh_abh;
  end
end

endmodule

`SCHEM_KEEP_HIER module adl_abl_reg(input clk, input ready, input load_abl, 
                                    input [2:0] adl_sel, input [7:0] data_i, input [7:0] pcls, 
                                    input [7:0] reg_s, input [7:0] alu, input [7:0] vector_lo, 
                                    output reg [7:0] adl_abl, output reg [7:0] abl_next, output reg [7:0] abl);

// ADL -> ABL
always @(*)
begin
  case(adl_sel) // synthesis full_case parallel_case
    `ADL_DI    : adl_abl = data_i;
    `ADL_PCLS  : adl_abl = pcls;
    `ADL_S     : adl_abl = reg_s;
    `ADL_ALU   : adl_abl = alu;
    `ADL_VECLO : adl_abl = vector_lo;
    `ADL_VECHI : adl_abl = { vector_lo[7:1],1'b1 };
  endcase
end

always @(*)
begin
  if(load_abl && ready)
    abl_next = adl_abl;
  else
    abl_next = abl;
end


always @(posedge clk)
begin
  if(load_abl && ready)
  begin
    abl <= adl_abl;
  end
end

endmodule
