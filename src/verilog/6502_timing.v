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

// This may be also defined to "fix" the original 6502 BRK/NMI bug without enabling the full CMOS stuff
`ifdef CMOS
`define NMI_BUG_FIX 1
`endif
`define NMI_BUG_FIX 1

`SCHEM_KEEP_HIER module timing_ctrl(input clk, input reset, input ready, output reg [2:0] t, output reg [2:0] t_next, 
                                    input [2:0] tnext_mc, input alu_carry_out, input taken_branch, input branch_page_cross, 
                                    input intg, output wire pc_hold,
                                    output wire sync, input load_sbz, input onecycle, input twocycle, input decimal_cycle, 
                                    output reg write_allowed, output wire decimal_extra_cycle);

// TODO - Separate the state machine from the output encoding?
parameter T0 = 3'b000,
          T1 = 3'b001,
          T2 = 3'b010,
          T3 = 3'b011,
          T4 = 3'b100,
          T5 = 3'b101,
          T6 = 3'b110,
          T7 = 3'b111;

`ifdef CMOS
assign decimal_extra_cycle = (t == 7 && load_sbz);
   
assign sync = (t == 1 && ~(decimal_cycle)) | decimal_extra_cycle;
// Disable PC increment when processing a BRK with recognized IRQ/NMI, or when about to perform the extra decimal correction cycle
assign pc_hold = intg | decimal_cycle;
`else
assign decimal_extra_cycle = 0;
   
assign sync = (t == 1);
assign pc_hold = intg;
`endif

always @(posedge clk)
  begin
     $display("Setting CMOS sync would use decimal_cycle = %d, decimal_extra_cycle = %d (result = %d)",
	      decimal_cycle,decimal_extra_cycle,(t == 1 && ~(decimal_cycle)) | decimal_extra_cycle);
     
  if(reset)       t <= T2;
  else if(ready) begin
    t <= t_next;
    $display("T: %d t_next: %d",t,t_next);
  end
end

always @(*)
begin
  t_next = t+1;
  write_allowed = 1;
  if(onecycle & sync)
    t_next = T1;
  else if(twocycle & sync)
    t_next = T0;
`ifdef CMOS
  else if(decimal_cycle) // Note: The 'if' and not 'else if' here is important in the case where a twocycle instruction follows a decimal extra cycle
    t_next = T7;
  else if(decimal_extra_cycle)
    t_next = T2;
`endif
    
  if(tnext_mc == `T0)
    t_next = T0;
  else if(tnext_mc == `TNC && alu_carry_out == 0)
    t_next = T0;
  else if(tnext_mc == `TNC && alu_carry_out == 1)
    write_allowed = 0;
  else if(tnext_mc == `TBR && taken_branch == 0)
    t_next = T1;
  else if(tnext_mc == `TBE)
  begin
    if(branch_page_cross == 1)
      t_next = T0;
    else
      t_next = T1;
  end
  else if(tnext_mc == `TBT && alu_carry_out == 0)
    t_next = T1;
  // synthesis translate_off
  else if(t != 1 && tnext_mc == `TKL)
  begin
    $display("Microcode KIL encountered");
    $finish;
  end
  // synthesis translate_on
end

endmodule

`SCHEM_KEEP_HIER module predecode(input [7:0] ir_next, input active, output reg onecycle, output reg twocycle);

// This detects single-cycle instructions
always @(ir_next,active)
begin
`ifdef CMOS
  if((ir_next & 8'b00000111) == 8'b00000011)
    onecycle = active;
  else
`endif
    onecycle = 0;
end

// This detects the instruction patterns where we need to go immediately to T0 instead of T2 during a fetch cycle.
always @(*)
begin
  casez(ir_next)
    `ifdef CMOS
    8'b?1?1_1010: twocycle = 0;
    8'b???0_0010: twocycle = active;
    `endif
    8'b???0_10?1: twocycle = active;
    8'b1??0_00?0: // This would hit the CMOS BRA, but is disabled below
      begin
        twocycle = active;
        `ifdef CMOS
        casez(ir_next)
          8'b?00???0?: twocycle = 0;
        endcase
        `endif
      end
    8'b????_10?0:
      begin
        twocycle = active;
        casez(ir_next)
          8'b0??0??0?: twocycle = 0;
        endcase
      end
    default: twocycle = 0;
  endcase;

end

endmodule

`SCHEM_KEEP_HIER module interrupt_control(input clk, input reset, input irq, input nmi, 
                                          input [2:0] t, input [2:0] tnext_mc, input [7:0] reg_p, 
                                          input load_i, 
                                          output reg intg, output reg nmig, output reg resp, output reg [7:0] vector_lo);

reg nmil; // Delayed NMI for edge detection
reg intp; // Internal interrupt detection

always @(posedge clk)
begin
  if(reset)
    resp = 1;
  else if(t == 0)
    resp = 0;
end

// INT is always the last read value of the interrupt status
always @(posedge clk)
begin
  intp <= irq;
end

// intg is the signal that actually causes interrupts to be processed. It 
// can be updated from intp either during T0 or during T2 if the instruction
// is a branch, or immediately in the case of reset.
always @(posedge clk)
begin
  // NMI edge detection
  // This will be delayed by one cycle so if an NMI happens on T0 it won't get recognized
  // until the next T0 or T2 of a branch.
  if(nmi & ~nmil)
    nmig <= 1;
  nmil <= nmi;    // remember current state
  
  if(reset || (t == 0) || (tnext_mc == `TBR))
  begin
    if((intp & ~reg_p[`PF_I]) | nmig | reset)
      intg <= 1;
  end
  // internal pending interrupt is always cleared at the same time we set interrupt mask.
  else if(load_i)
  begin
      intg <= 0;
`ifdef NMI_BUG_FIX      
      if(intg)
`endif
        nmig <= 0;
  end
end

always @(*)
begin
  if(resp == 1)
    vector_lo = 8'hFC;
  else if(nmig 
`ifdef NMI_BUG_FIX    
    & intg
`endif
    )
    vector_lo = 8'hFA;
  else
    vector_lo = 8'hFE;
end

endmodule

`SCHEM_KEEP_HIER module branch_control(input [7:0] reg_p, input [7:5] ir, output reg taken_branch);

always @(*)
begin
  taken_branch = 0;
	case({ir[7],ir[6]}) // synthesis full_case parallel_case
		2'b00: taken_branch = (reg_p[`PF_N] == ir[5]);
		2'b01: taken_branch = (reg_p[`PF_V] == ir[5]);
		2'b10: taken_branch = (reg_p[`PF_C] == ir[5]);
		2'b11: taken_branch = (reg_p[`PF_Z] == ir[5]);
	endcase
end

endmodule
