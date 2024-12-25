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

`timescale 10ns/10ns

module decadj_half_adder(input [3:0] dec_in, output wire [3:0] dec_out, input carry_in, input dec_add, input dec_sub, input half);
  
	wire [3:0] correction_factor;

  wire add_adj, sub_adj;
  
  assign add_adj = dec_add & carry_in;
  assign sub_adj = dec_sub & ~carry_in;
  
  assign correction_factor = {sub_adj,add_adj,add_adj|sub_adj,1'b0};
  assign dec_out = dec_in + correction_factor;
  
endmodule

module alu_half_adder(input [3:0] add_in1, input [3:0] add_in2, input add_cin, input dec_add, 
                      output reg [3:0] add_out, output reg carry_out, output reg dec_carry_out, input half);
  
  reg carry_tmp;
	reg greater_than_nine;
  
  reg [4:0] add_tmp;
  
  always @(*)
  begin
    add_tmp = add_in1 + add_in2 + add_cin;
    greater_than_nine = (add_tmp[3] & (add_tmp[2] | add_tmp[1]));
    carry_out = add_tmp[4] | (dec_add & greater_than_nine);
    dec_carry_out = greater_than_nine;
    add_out = add_tmp[3:0];
  end

endmodule

module alu_adder(input [7:0] add_in1, input [7:0] add_in2, input add_cin, input dec_add, 
                 output wire [7:0] add_out, output wire carry_out, output wire half_carry_out);
    
  wire dec_carry_out; // unused
  
  alu_half_adder  low(add_in1[3:0],add_in2[3:0],add_cin,dec_add,add_out[3:0],half_carry_out,dec_half_carry_out,1'b0);
  alu_half_adder high(add_in1[7:4],add_in2[7:4],half_carry_out,dec_add,add_out[7:4],carry_out,dec_carry_out,1'b1);
    
endmodule

// Input muxing is done outside of the core ALU unit.
`SCHEM_KEEP_HIER module alu_unit(input clk, input ready, 
                                 input [7:0] a, input [7:0] b, output reg [7:0] alu_out,
                                 input c_in,input dec_add,input [3:0] op,
                                 output reg carry_out, output wire half_carry_out,
                                 output wire overflow_out,
                                 output reg alu_carry_out_last);
  
	reg c;
	
	wire [7:0] add_out;
	reg [7:0] tmp;

  wire adder_carry_out;
  
	alu_adder add_u(a, b, c_in, dec_add, add_out, adder_carry_out, half_carry_out);
	  
  assign overflow_out = a[7] == b[7] && a[7] != add_out[7];
  
always @(*) begin
	case(op) // synthesis full_case parallel_case
		`ALU_ORA: 
      begin
      c = 0;
			tmp = a | b;
			end
		`ALU_AND: 
      begin
			tmp = a & b;
      c = | tmp;      // This is a bit of a hack, used for 65C02 branch bit tests.
			end
		`ALU_EOR: 
      begin
      c = 0;
			tmp = a ^ b;
			end
		`ALU_ADC, `ALU_SBC: 
      begin
      c = adder_carry_out;
      tmp = add_out;
			end
		`ALU_ROR: 
      begin
			{tmp,c} = {c_in,a};
      end
    //`ALU_TST:
    //  begin
    //  c = 0;
    //  tmp = ~a & b;
    //  end
    `ALU_PSA:   // Passthrough, used when I just needed the ALU to hold onto something for a cycle. The real 6502 has an output hold register.
      begin
			c = 0;
      tmp = a;
      end
	endcase

	alu_out = tmp;
  carry_out = c;
  
  //$strobe("ALU a: %02x b: %02x c_in: %d -> %02x daa: %d flags vc: %d%d hc: %d",a,b,c_in,tmp,dec_add,overflow_out,carry_out,half_carry_out);
	end

  always @(posedge clk)
  begin
    if(ready)
      alu_carry_out_last <= carry_out;
  end

endmodule

`SCHEM_KEEP_HIER module decoder3to8(input [2:0] index, output reg [7:0] outbits);

always @(*)
begin
  case(index)
    0 : outbits = 8'b00000001;
    1 : outbits = 8'b00000010;
    2 : outbits = 8'b00000100;
    3 : outbits = 8'b00001000;
    4 : outbits = 8'b00010000;
    5 : outbits = 8'b00100000;
    6 : outbits = 8'b01000000;
    7 : outbits = 8'b10000000;
  endcase
end
endmodule
