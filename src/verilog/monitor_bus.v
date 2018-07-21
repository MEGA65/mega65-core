//`define EN_MARK_DEBUG 1
`ifdef EN_MARK_DEBUG
`define MARK_DEBUG (* mark_debug = "true", dont_touch = "true" *)
`else
`define MARK_DEBUG
`endif

module monitor_bus(input clk, input [15:0] cpu_address, input cpu_write, input [7:0] history_lo, input [7:0] history_hi, input [7:0] mem, input [7:0] ctrl,
                   input [7:0] cpu_state,
                   `MARK_DEBUG output reg ram_write, `MARK_DEBUG output reg ctrl_write, `MARK_DEBUG output reg ctrl_read, output reg [7:0] read_data);

`MARK_DEBUG reg [2:0] read_select;
`MARK_DEBUG reg [2:0] read_select_reg;

// Determine which module we'll be reading (or writing to).
always @(*)
begin
  read_select = 0;
  ram_write = 0;
  ctrl_write = 0;
  ctrl_read = 0;
  casez(cpu_address[15:0])
    16'b0000000z_zzzzzzzz: begin read_select = 1; ram_write = cpu_write; end  // $0000-$01ff - RAM (zero page + stack)
    16'b0111zzzz_zzzzzzzz: read_select = 5;                                   // $7000-$7fff - CPU State
    16'b1000zzzz_zzz0zzzz: read_select = 2;                                   // $8000-$800f - History Lo
    16'b1000zzzz_zzz10zzz: read_select = 3;                                   // $8010-$8017 - History Hi
    16'b1001zzzz_zzzzzzzz: begin read_select = 4; ctrl_write = cpu_write; ctrl_read = ~cpu_write; end // $9000-$9000 - Monitor Ctrl
    16'b1111zzzz_zzzzzzzz: read_select = 1;                                   // $f000-$ffff - Monitor "ROM"
    default :              read_select = 0;                                   // Nothing?
  endcase;
end

// Remember this selection as it will determine which input source the CPU reads from on the next clock cycle when
// data is available.
always @(posedge clk)
begin
  read_select_reg <= read_select;
end

// Output mux (combinatorial), controlled by read_select_reg
always @(*)
begin
  case(read_select_reg) // synthesis full_case parallel_case
    0: read_data = 8'h00;
    1: read_data = mem;
    2: read_data = history_lo;
    3: read_data = history_hi;
    4: read_data = ctrl;
    5: read_data = cpu_state;
  endcase;
end  

endmodule
