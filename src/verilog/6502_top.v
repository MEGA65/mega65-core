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

`SCHEM_KEEP_HIER module cpu6502(input clk, input reset, input nmi, input irq, input ready, output reg write, `MARK_DEBUG output wire write_next, 
  output wire sync, output wire [15:0] address, `MARK_DEBUG output wire [15:0] address_next, `MARK_DEBUG input [7:0] data_i, 
  output wire [7:0] data_o, `MARK_DEBUG output wire [7:0] data_o_next, output wire [7:0] cpu_state, output wire [2:0] t, output wire cpu_int);

// microcode output signals
wire [2:0] tnext_mc;
wire [2:0] t_next;
wire [2:0] adh_sel;
wire [2:0] adl_sel;
wire [2:0] db_sel;
wire [2:0] sb_sel;
wire pchs_sel;
wire pcls_sel;
wire [3:0] alu_op;
wire [2:0] alu_a;
wire [1:0] alu_b;
wire [1:0] alu_c;
wire load_a;
wire load_x;
wire load_y;
wire load_s;
wire load_abh;
wire load_abl;
wire write_cycle;
wire pc_inc;
wire [3:0] load_flags;
wire [14:0] load_flag_decode;

// Internal busses (muxes)
wire [7:0] db_in; 
wire [7:0] db_out;

wire [7:0] adl_abl;      // ADL that feeds into ABL and ALUB input
wire [7:0] sb;      // SB mux

// Clocked internal registers
wire [7:0] abh_next;
wire [7:0] abl_next;
wire [7:0] abh;
wire [7:0] abl;
wire [7:0] pch;
wire [7:0] pcl;
wire [7:0] ir;
wire [7:0] dor;
reg w_reg;

// Clocked architectural registers
wire [7:0] reg_a;
wire [7:0] reg_x;
wire [7:0] reg_y;
wire [7:0] reg_s;
wire [7:0] reg_p;

// ALU inputs and outputs
wire [7:0] aluas;
wire [7:0] alubs;
wire [7:0] alua;
wire [7:0] alub;
wire alucs;
wire [7:0] alu_out;

wire branch_page_cross;
wire taken_branch;
wire [7:0] ir_next;

wire [7:0] decadj_out;
wire dec_add, dec_sub;
wire alu_carry_out,alu_half_carry_out;

wire ready_i;

wire [7:0] pcls;
wire pcl_carry;

wire [7:0] pchs;

wire onecycle;
wire twocycle;
wire decimal_cycle;
wire write_allowed;
wire decimal_extra_cycle;

wire intg;
wire nmig;
wire resp;
wire pc_hold;

assign cpu_int = intg;

wire [7:0] vector_lo;

  // Instantiate ALU
  alu_unit alu_inst(clk, ready_i, alua, alub, alu_out, alucs, dec_add, alu_op, alu_carry_out, alu_half_carry_out, alu_overflow_out, alu_carry_out_last);

  // Note: microcode outputs are *synchronous* and show up on following clock and thus are always driven directly by t_next and not t.
  microcode mc_inst(.clk(clk), .ready(ready_i), .ir(ir_next), .t(t_next), .tnext(tnext_mc), .adh_sel(adh_sel), .adl_sel(adl_sel),
                  .pchs_sel(pchs_sel), .pcls_sel(pcls_sel), .alu_op(alu_op), .alu_a(alu_a), .alu_b(alu_b), .alu_c(alu_c),
                  .db_sel(db_sel), .sb_sel(sb_sel),
                  .load_a(load_a), .load_x(load_x), .load_y(load_y), .load_s(load_s),
                  .load_abh(load_abh), .load_abl(load_abl), 
                  .load_flags(load_flags), 
                  .write_cycle(write_cycle), .pc_inc(pc_inc));

  flags_decode flags_decode(load_flags, load_flag_decode);

  // PGS 20190316 - Following Kenneth's advice to allow the CPU to be single stepped via a clock tick strobe on the ready line
  // assign ready_i = ready | write_next;
  assign ready_i = ready;

  branch_control branch_control(reg_p, ir[7:5], taken_branch);
  
  ir_next_mux ir_next_mux(sync, intg, data_i, ir, ir_next);

  assign address = { abh, abl };
  assign address_next = { abh_next, abl_next };
  
  assign write_next = write_cycle & ~resp & write_allowed;

  assign data_o = dor;
  assign data_o_next = db_out;

  always @(posedge clk)
  begin
    if(ready_i)
      write <= write_next;
  end
  
  assign cpu_state = ir; //{ dec_add, dec_sub, decimal_extra_cycle, decimal_cycle};
  
  // A page is crossed if the carry result is different than the sign of the branch offset input
  assign branch_page_cross = alu_carry_out ^ alua[7];

  predecode predecode(data_i, sync & ~intg, onecycle, twocycle);

  interrupt_control interrupt_control(clk, reset, irq, nmi, t, tnext_mc, reg_p, load_flag_decode[`LF_I_1], intg, nmig, resp, vector_lo);

  // Timing control state machine
  timing_ctrl timing(clk, reset, ready_i, t, t_next, tnext_mc, alu_carry_out, taken_branch, branch_page_cross, intg, pc_hold,
                   sync, load_flag_decode[`LF_Z_SBZ], onecycle, twocycle, decimal_cycle, write_allowed, decimal_extra_cycle);

  clocked_reset_reg8 ir_reg(clk, reset, sync & ready_i, ir_next, ir);
  
  adl_pcl_reg adl_pcl_reg(.clk(clk), .ready(ready_i), .pcls_sel(pcls_sel), .pc_inc(pc_inc & ~pc_hold),
                          .adl_sel(adl_sel), .reg_s(reg_s), .alu(alu_out), 
                          .pcls(pcls), .pcl(pcl), .pcl_carry(pcl_carry));
  adl_abl_reg adl_abl_reg(.clk(clk), .ready(ready_i), .load_abl(load_abl), .adl_sel(adl_sel), .data_i(data_i), .pcls(pcls), .reg_s(reg_s),
                          .alu(alu_out), .vector_lo(vector_lo), .adl_abl(adl_abl), .abl_next(abl_next), .abl(abl));

  db_in_mux db_in_mux(db_sel, data_i, reg_a, alua[7], db_in);
  db_out_mux db_out_mux(db_sel, reg_a, sb, pcl, pch, reg_p, db_out);

  sb_mux sb_mux(sb_sel, reg_a, reg_x, reg_y, reg_s, alu_out, pch, db_in, sb);

  // ADH units
  adh_pch_reg adh_pch_reg(.clk(clk), .ready(ready_i), .pchs_sel(pchs_sel), .pcl_carry(pcl_carry), .adh_sel(adh_sel), .data_i(data_i), .alu(alu_out), .pchs(pchs), .pch(pch), .pch_carry());
  adh_abh_reg adh_abh_reg(.clk(clk), .ready(ready_i), .load_abh(load_abh), .adh_sel(adh_sel), .data_i(data_i), .pchs(pchs), .alu(alu_out), .abh_next(abh_next), .abh(abh));

wire [7:0] ir_dec;
`ifdef CMOS
decoder3to8 dec3to8(ir[6:4], ir_dec);
`endif

  alua_mux alua_mux(clk, alu_a != 0 && ready_i, alu_a, sb, ir_dec, alua);
  alub_mux alub_mux(clk, alu_b != 0 && ready_i, alu_b, db_in, adl_abl, alub);
  aluc_mux aluc_mux(alu_c, reg_p[`PF_C], alu_carry_out_last, alucs);
  
  a_reg a_reg(clk, load_a, sb, alu_carry_out, alu_half_carry_out, dec_add, dec_sub, reg_a);
  
  clocked_reg8 x_reg(clk, load_x && ready_i, sb, reg_x);
  clocked_reg8 y_reg(clk, load_y && ready_i, sb, reg_y);
  clocked_reg8 s_reg(clk, load_s && ready_i, sb, reg_s);
  clocked_reg8 do_reg(clk, db_sel != 0 && ready_i, db_out, dor);
  
  // FIXME - This is kinda hacky right now.  Really should have a pair of dedicated microcode bits for this but
  // I'm currently out of spare microcode bits.   This probably only requires a couple of LUTs though.
  assign dec_add = reg_p[`PF_D] & load_flag_decode[`LF_V_AVR] & (alu_op == `ALU_ADC);
  assign dec_sub = reg_p[`PF_D] & load_flag_decode[`LF_V_AVR] & (alu_op == `ALU_SBC);
`ifdef CMOS
  assign decimal_cycle = reg_p[`PF_D] & load_flag_decode[`LF_V_AVR];
`else
  assign decimal_cycle = 0;
`endif
  // In the real 6502 the internal data bus is bidirectional and so it doesn't matter whether it is a "source" or destination.  But
  // in an FPGA you never want to have combinatorial loops since it generally makes the synthesis tools really unhappy.  So because
  // I had to split the data bus into two unidirectional busses, I was faced with the problem that sometimes I needed to update the Z
  // and N flags based on data coming into the CPU (Load, BIT, etc), and sometimes when it was just the result of an internal operation.

  // However, my secondary (SB) bus is essentially unidirectional, and in all cases where I needed to update the Z or N flags it was
  // possible to either have the input data bus feed the secondary bus to pick up the flags, or just pick up the flags from the secondary
  // bus directly (which is a case where the original would have cross connected the two busses).  So, I always just get Z or N from
  // the secondary bus instead.
  assign sb_z = ~|sb;
  assign sb_n = sb[7];

  p_reg p_reg(clk, reset, ready_i, intg, load_flag_decode, sync & ready_i, db_in, sb_z, sb_n, alu_carry_out, alu_overflow_out, ir[5], reg_p);


  // Branch-to-self detection
  // synthesis translate off
  reg [15:0] last_fetch_addr;
  always @(posedge clk)
    begin
       $display("sync = %d, ready_i = %d, reset = %d",sync,ready_i,reset);
       
    if(sync & ready_i)
      begin
	 $display("Sync & ready_i asserted");
	 
      if(last_fetch_addr == address)
      begin
        $display("Halting, branch to self detected: %04x   A: %02x X: %02x Y: %02x S: %02x P: %02x ",last_fetch_addr,
          reg_a, reg_x, reg_y, reg_s, reg_p);
        $finish;
      end
      if(pc_hold == 0)
        last_fetch_addr <= address;
    
      $display("FETCH ADDR: %04x byte: %02x  1C: %d 2C: %d  pc_hold: %d intg: %g",address,ir_next,onecycle,twocycle,pc_hold, intg);
    end
  end
  // synthesis translate on

endmodule
