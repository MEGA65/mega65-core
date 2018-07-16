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

// This is the "secondary bus"
`SCHEM_KEEP_HIER module sb_mux(input [2:0] sb_sel, input [7:0] reg_a, input [7:0] reg_x, input [7:0] reg_y, 
                               input [7:0] reg_s, input [7:0] alu, input [7:0] pch, input [7:0] db, output reg [7:0] sb);

always @(*)
begin
  case(sb_sel)  // synthesis full_case parallel_case
    `SB_A   : sb = reg_a;
    `SB_X   : sb = reg_x;
    `SB_Y   : sb = reg_y;
    `SB_S   : sb = reg_s;
    `SB_ALU : sb = alu;
    `SB_ADH : sb = pch;  // Any time SB is sourcing from ADH, it is always to get PCH
    `SB_DB  : sb = db;
    `SB_FF  : sb = 8'hFF;
  endcase
end

endmodule

`SCHEM_KEEP_HIER module alua_mux(input clk,
                                 input ready,
                                 input [2:0] alu_a, 
                                 input [7:0] sb, 
                                 input [7:0] ir_dec, 
                                 output reg [7:0] alua);
                                 
reg [7:0] aluas;
                             
// ALU A input select
always @(*)
begin
  case(alu_a)  // synthesis full_case parallel_case
    `ALU_A_0   : aluas = 8'h00;
    `ALU_A_SB  : aluas = sb;
    `ALU_A_NSB : aluas = ~sb;
`ifdef CMOS
    `ALU_A_IR  : aluas = ir_dec;
    `ALU_A_NIR : aluas = ~ir_dec;
`endif
  endcase
end

always @(posedge clk)
begin
  if(ready)
  begin
    alua <= aluas;
  end
end

endmodule

`SCHEM_KEEP_HIER module alub_mux(input clk,
                                 input ready,
                                 input [1:0] alu_b, 
                                 input [7:0] db, 
                                 input [7:0] adl, 
                                 output reg [7:0] alub);

reg [7:0] alubs;

// ALU B input select
always @(*)
begin
  case(alu_b)  // synthesis full_case parallel_case
    `ALU_B_DB  : alubs = db;
    `ALU_B_NDB : alubs = ~db;
    `ALU_B_ADL : alubs = adl;
  endcase
end

always @(posedge clk)
begin
  if(ready)
  begin
    alub <= alubs;
  end
end

endmodule


`SCHEM_KEEP_HIER module aluc_mux(input [1:0] alu_c, 
                                 input carry,
                                 input last_carry,
                                 output reg carrys);

// ALU C (carry) input select
always @(*)
begin
  case(alu_c)  // synthesis full_case parallel_case
    `ALU_C_0 : carrys = 0;
    `ALU_C_1 : carrys = 1;
    `ALU_C_P : carrys = carry;
    `ALU_C_A : carrys = last_carry;
  endcase
end

endmodule

`SCHEM_KEEP_HIER module db_in_mux(input [2:0] db_sel, 
                                 input [7:0] data_i,
                                 input [7:0] reg_a,
                                 input alua_highbit,
                                 output reg [7:0] db_in);

// DB input mux
always @(*)
begin
  case(db_sel)  // synthesis full_case parallel_case
    `DB_0   : db_in = 8'h00;
    //`DB_DI  : db_in = data_i;
    //`DB_SB  : db_in = data_i; // Temp hack
    //`DB_PCH : db_in = data_i;
    `DB_A   : db_in = reg_a;
    `DB_BO  : db_in = {8{alua_highbit}};   // The high bit of the last ALU A input is the sign bit for branch offsets
    default : db_in = data_i;
     
  endcase
  //$display("data_i: %02x  db_in: %02x",data_i,db_in);
end

endmodule

`SCHEM_KEEP_HIER module db_out_mux(input [2:0] db_sel, 
                                   input [7:0] reg_a,
                                   input [7:0] sb,
                                   input [7:0] pcl,
                                   input [7:0] pch,
                                   input [7:0] reg_p,
                                   output reg [7:0] db_out);

// DB output mux
always @(*)
begin
  case(db_sel)  // synthesis full_case parallel_case
    `DB_A   : db_out = reg_a;
    `DB_SB  : db_out = sb;
    `DB_PCL : db_out = pcl;
    `DB_PCH : db_out = pch;
    `DB_P   : db_out = reg_p;
    `DB_0   : db_out = 8'h00;
  endcase
end

endmodule

`SCHEM_KEEP_HIER module ir_next_mux(input sync, 
                                    input intg,
                                    input [7:0] data_i,
                                    input [7:0] ir,
                                    output reg [7:0] ir_next);

// IR input
always @(*)
begin
  if(sync)
  begin
    if(intg)
      ir_next = 8'h00;
    else
      ir_next = data_i;
  end
  else
    ir_next = ir;
end

endmodule

// Note: LM_C_DB0, LM_Z_DB1, LM_I_DB2 and LM_D_DB3 are currently always set together and are thus redundant,
// so if we ever went back to predecoded flags we could save 3 bits there.
`SCHEM_KEEP_HIER module flags_decode(input [3:0] load_flags, output reg [14:0] load_flags_decode);
always @(*)
case (load_flags)   // synthesis full_case parallel_case
  `none       : load_flags_decode = 0;
  `FLAGS_DB   : load_flags_decode = (`LM_C_DB0 | `LM_Z_DB1 | `LM_I_DB2 | `LM_D_DB3 | `LM_V_DB6 | `LM_N_DB7);
  `FLAGS_SBZN : load_flags_decode = (`LM_Z_SBZ | `LM_N_SBN);
  `FLAGS_D    : load_flags_decode = (`LM_D_IR5);
  `FLAGS_I    : load_flags_decode = (`LM_I_IR5);
  `FLAGS_C    : load_flags_decode = (`LM_C_IR5);
  `FLAGS_V    : load_flags_decode = (`LM_V_0);
  `FLAGS_Z    : load_flags_decode = (`LM_Z_SBZ);
  `FLAGS_CNZ  : load_flags_decode = (`LM_C_ACR | `LM_Z_SBZ | `LM_N_SBN);
  `FLAGS_ALU  : load_flags_decode = (`LM_C_ACR | `LM_V_AVR | `LM_Z_SBZ | `LM_N_SBN);
  `FLAGS_BIT  : load_flags_decode = (`LM_V_DB6 | `LM_N_DB7);
  `ifdef CMOS
  `FLAGS_SETI : load_flags_decode = (`LM_I_1|`LM_D_IR5);     // Clear D flag too
  `else
  `FLAGS_SETI : load_flags_decode = (`LM_I_1);
  `endif
endcase

endmodule
