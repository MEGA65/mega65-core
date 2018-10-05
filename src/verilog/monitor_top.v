//`define EN_MARK_DEBUG 1
`ifdef EN_MARK_DEBUG
`define MARK_DEBUG (* mark_debug = "true", dont_touch = "true" *)
`else
`define MARK_DEBUG
`endif

(* keep_hierarchy = "yes" *) module uart_monitor(
  `MARK_DEBUG input reset,
  `MARK_DEBUG output wire reset_out,
  output wire monitor_hyper_trap,
  input clock,
  output wire tx,
  input rx,
  output wire [15:0] bit_rate_divisor,
  output wire activity,
  input [7:0] protected_hardware_in,
  input [7:0] uart_char,
  input uart_char_valid,
  
  output wire [7:0] monitor_char_out,
  output wire monitor_char_valid,
  input terminal_emulator_ready,
  input terminal_emulator_ack,
  
  output reg [15:0] key_scancode,
  output reg key_scancode_toggle,
      
  input force_single_step,
  input secure_mode_from_cpu,
  output secure_mode_from_monitor,
  output clear_matrix_mode_toggle,
    
  input fastio_read,
  input fastio_write,

  input monitor_proceed,
  input [7:0] monitor_waitstates,
  input monitor_request_reflected,
  input [15:0] monitor_pc,
  input [15:0] monitor_cpu_state,
  input monitor_hypervisor_mode,
  input [7:0] monitor_instruction,
  output wire [27:0] monitor_watch,
  input monitor_watch_match,
  input [7:0] monitor_opcode,
  input [3:0] monitor_ibytes,
  input [7:0] monitor_arg1,
  input [7:0] monitor_arg2,
  input [31:0] monitor_memory_access_address,
    
  input [7:0] monitor_a,
  input [7:0] monitor_x,
  input [7:0] monitor_y,
  input [7:0] monitor_z,
  input [7:0] monitor_b,
  input [15:0] monitor_sp,
  input [7:0] monitor_p,
  input [11:0] monitor_map_offset_low,
  input [11:0] monitor_map_offset_high,
  input [3:0] monitor_map_enables_low,
  input [3:0] monitor_map_enables_high,
  input monitor_interrupt_inhibit,
  input [7:0] monitor_roms,
  input [7:0] monitor_char,
  input monitor_char_toggle,
  output wire monitor_char_busy,

  output wire [27:0] monitor_mem_address,
  input [7:0] monitor_mem_rdata,
  output wire [7:0] monitor_mem_wdata,
  output wire monitor_mem_attention_request,
  input monitor_mem_attention_granted,
  output wire monitor_mem_read,
  output wire monitor_mem_write,
  output wire monitor_mem_setpc,
  output wire monitor_irq_inhibit,
  output reg monitor_mem_stage_trace_mode,
  output wire monitor_mem_trace_mode,
  output wire monitor_mem_trace_toggle
    );

  wire [191:0] history_wdata;
  
  // 16 byte wide section
  assign history_wdata[7:0] = monitor_p;
  assign history_wdata[15:8] = monitor_a;
  assign history_wdata[23:16] = monitor_x;
  assign history_wdata[31:24] = monitor_y;
  assign history_wdata[39:32] = monitor_z;
  assign history_wdata[55:40] = monitor_pc;
  assign history_wdata[71:56] = monitor_cpu_state;
  assign history_wdata[79:72] = monitor_waitstates;
  assign history_wdata[87:80] = monitor_b;
  assign history_wdata[103:88] = monitor_sp;
  assign history_wdata[111:104] = {monitor_map_enables_low, monitor_map_offset_low[11:8]};
  assign history_wdata[119:112] = monitor_map_offset_low[7:0];
  assign history_wdata[121:120] = monitor_ibytes[1:0];
  assign history_wdata[122] = fastio_read;
  assign history_wdata[123] = fastio_write;
  assign history_wdata[124] = monitor_proceed;
  assign history_wdata[125] = monitor_mem_attention_granted;
  assign history_wdata[126] = monitor_request_reflected;
  assign history_wdata[127] = monitor_interrupt_inhibit;
  
  // 8 byte wide section, 2 unused bytes at top
  assign history_wdata[135:128] = { monitor_map_enables_high, monitor_map_offset_high[11:8] };
  assign history_wdata[143:136] = monitor_map_offset_high[7:0];
  assign history_wdata[151:144] = monitor_opcode;
  assign history_wdata[159:152] = monitor_arg1;
  assign history_wdata[167:160] = monitor_arg2;
  assign history_wdata[175:168] = monitor_instruction;
  assign history_wdata[183:176] = monitor_roms;
  assign history_wdata[191:184] = 8'h00;
  
  wire [9:0] history_write_index;
  
  wire [7:0] history_rdata_lo;
  wire [7:0] history_rdata_hi;
  
  wire [13:0] history_read_address_lo;
  wire [12:0] history_read_address_hi;
  
  wire [9:0] history_read_index;
  
  `MARK_DEBUG wire [15:0] cpu_address_next;
  `MARK_DEBUG wire [7:0] cpu_di;
  `MARK_DEBUG wire [7:0] cpu_do;
  `MARK_DEBUG wire cpu_write_next;
  
  `MARK_DEBUG wire [7:0] ram_do;
  `MARK_DEBUG wire [7:0] monitor_do;
  wire [7:0] cpu_state_rdata;
  wire cpu_state_write;
  wire [3:0] cpu_state_write_index;
  
  wire reset_internal;
  wire reset_out_internal;
  wire ram_write;
  wire ctrl_read;
  wire ctrl_write;
  
  // Our resets are inverted (active high)
  assign reset_internal = ~reset;
  assign reset_out = ~reset_out_internal;
    
  assign history_read_address_lo = { history_read_index, cpu_address_next[3:0]};
  assign history_read_address_hi = { history_read_index, cpu_address_next[2:0]};
  
  // Conceptually the history RAM is a dual ported 1024x24 byte RAM, broken up into
  // a 1Kx16B and a 1Kx8B.   From the write side, the write width for RAM 0 is
  // 128 bits, and write width for RAM1 is 64 bits.   The write side address width is 10 bits for both.
  // For the read side, RAM 0 is a 16Kx8b, and RAM 1 is a 8Kx8b.   The read side is mapped
  // into the 6502's address space via 16 and 8 byte windows.
  asym_ram_sdp #(.WIDTHA(128),.SIZEA(1024),.ADDRWIDTHA(10), .WIDTHB(8),.SIZEB(16384),.ADDRWIDTHB(14)) 
               historyram0(
               .clkA(clock),.weA(history_write),.enaA(1),
               .addrA(history_write_index),.diA(history_wdata[127:0]),
               .clkB(clock),.enaB(1),.addrB(history_read_address_lo),.doB(history_rdata_lo));
  asym_ram_sdp #(.WIDTHA(64),.SIZEA(1024),.ADDRWIDTHA(10), .WIDTHB(8),.SIZEB(8192),.ADDRWIDTHB(13))
               historyram1(
               .clkA(clock),.weA(history_write),.enaA(1),
               .addrA(history_write_index),.diA(history_wdata[191:128]),
               .clkB(clock),.enaB(1),.addrB(history_read_address_hi),.doB(history_rdata_hi));
  
  // Recent CPU State RAM is relatively small, only 64 bits wide by 16 entires deep used to store all the states (and addresses)
  // of the most recent instruction execution.   The output is directly mapped into 128 bytes of CPU
  // address space rather than using a read index register.
  asym_ram_sdp #(.WIDTHA(64),.SIZEA(16),.ADDRWIDTHA(4), .WIDTHB(8),.SIZEB(128),.ADDRWIDTHB(7)) 
               cpustateram(
               .clkA(clock),.weA(cpu_state_write),.enaA(1),
               .addrA(cpu_state_write_index),.diA({ 16'h0000, monitor_cpu_state, monitor_memory_access_address}),
               .clkB(clock),.enaB(1),.addrB(cpu_address_next[6:0]),.doB(cpu_state_rdata));
  
  // Instantiate the 6502 4K RAM/ROM (zero page, stack space, scratch space, code, etc).
  monitormem monitormem(.clk(clock), .we(ram_write), .addr(cpu_address_next[11:0]), .di(cpu_do), .do(ram_do));
  
  // Will start out simple and slowly add more control outputs as needed for different features and as
  // the software monitor code is written.
    
  monitor_ctrl monitorctrl(.clk(clock), .reset(reset_internal), .reset_out(reset_out_internal), .write(ctrl_write), .read(ctrl_read),
                           .address(cpu_address_next[4:0]), .di(cpu_do), .do(monitor_do), 
                           .history_write_index(history_write_index), .history_write(history_write),
                           .history_read_index(history_read_index),
                           .mem_address(monitor_mem_address),
                           .mem_rdata(monitor_mem_rdata), .mem_wdata(monitor_mem_wdata),
                           .mem_read(monitor_mem_read), .mem_write(monitor_mem_write),
                           .set_pc(monitor_mem_setpc),
                           .cpu_state_write(cpu_state_write),
                           .cpu_state(monitor_cpu_state[15:8]),
                           .cpu_state_write_index(cpu_state_write_index),
                           .mem_attention_granted(monitor_mem_attention_granted),
                           .mem_attention_request(monitor_mem_attention_request),
                           .monitor_mem_trace_mode(monitor_mem_trace_mode),
                           .monitor_mem_trace_toggle(monitor_mem_trace_toggle),
                           .monitor_irq_inhibit(monitor_irq_inhibit),
                           .monitor_hypervisor_mode(monitor_hypervisor_mode),
                           .monitor_hyper_trap(monitor_hyper_trap),
                           .protected_hardware(protected_hardware_in),
			   .secure_mode_from_monitor(secure_mode_from_monitor),
			   .secure_mode_from_cpu(secure_mode_from_cpu),
			   .clear_matrix_mode_toggle(clear_matrix_mode_toggle),
                           .monitor_p(monitor_p), .monitor_pc(monitor_pc),
                           .monitor_watch(monitor_watch), .monitor_watch_match(monitor_watch_match),
                           .monitor_char_out(monitor_char_out), .monitor_char_valid(monitor_char_valid), .terminal_emulator_ready(terminal_emulator_ready),
                           .terminal_emulator_ack(terminal_emulator_ack),
			   .uart_char(uart_char), .uart_char_valid(uart_char_valid),
                           .monitor_char_in(monitor_char), .monitor_char_toggle(monitor_char_toggle), .monitor_char_busy(monitor_char_busy),
                           .bit_rate_divisor(bit_rate_divisor),.rx(rx),.tx(tx),.activity(activity));
                        
  monitor_bus monitorbus(.clk(clock), .cpu_address(cpu_address_next), .cpu_write(cpu_write_next), 
                         .history_lo(history_rdata_lo), .history_hi(history_rdata_hi), .cpu_state(cpu_state_rdata),
                         .mem(ram_do), .ctrl(monitor_do), .ram_write(ram_write),
                         .ctrl_write(ctrl_write), .ctrl_read(ctrl_read), .read_data(cpu_di));
                            
  cpu6502 monitorcpu(.clk(clock), .reset(reset_internal), .nmi(0), .irq(0), .ready(1), 
                      .write_next(cpu_write_next), .address_next(cpu_address_next), 
                      .data_i(cpu_di), .data_o_next(cpu_do));
  
endmodule
