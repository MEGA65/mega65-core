//`define EN_MARK_DEBUG 1
`ifdef EN_MARK_DEBUG
`define MARK_DEBUG (* mark_debug = "true", dont_touch = "true" *)
`else
`define MARK_DEBUG
`endif

/* These get mapped into the monitor CPU's address space at $9000 */
`define MON_READ_IDX_LO       5'h00
`define MON_READ_IDX_HI       5'h01           // If we get really cramped on space, we could combine the MON_READ_IDX_HI and MON_READ_IDX_LO registers

`define MON_WRITE_IDX_LO      5'h02
`define MON_WRITE_IDX_HI      5'h03

`define MON_TRACE_CTRL        5'h04
`define MON_TRACE_STEP        5'h05

`define MON_FLAG_MASK0        5'h06
`define MON_FLAG_MASK1        5'h07

`define MON_UART_RX           5'h08
`define MON_UART_TX           5'h08         // These two registers could have the same address.  We never need to read from tx, or write to rx
`define MON_KEYBOARD_RX       5'h09

`define MON_UART_STATUS       5'h0A
`define MON_RESET_TIMEOUT     5'h0B

`define MON_UART_BITRATE_LO   5'h0C
`define MON_UART_BITRATE_HI   5'h0D

`define MON_BREAK_ADDR0       5'h0E
`define MON_BREAK_ADDR1       5'h0F

`define MON_MEM_ADDR0         5'h10
`define MON_MEM_ADDR1         5'h11
`define MON_MEM_ADDR2         5'h12
`define MON_MEM_ADDR3         5'h13
`define MON_MEM_READ          5'h14
`define MON_MEM_WRITE         5'h15
`define MON_MEM_STATUS        5'h16       // Mostly just a status bit (bit 7) that says either read data is ready or we can write again.
`define MON_MEM_INC           5'h17       // Maybe combine this with MEM_STATUS to free up a register?

`define MON_WATCH_ADDR0       5'h18
`define MON_WATCH_ADDR1       5'h19
`define MON_WATCH_ADDR2       5'h1A
`define MON_WATCH_ADDR3       5'h1B
`define MON_STATE_CNT         5'h1C
`define MON_PROT_HARDWARE     5'h1D
`define MON_CHAR_INOUT        5'h1E       // Hypervisor character input/output
`define MON_CHAR_STATUS       5'h1F

module monitor_ctrl(input clk, input reset, output reg reset_out, 
                    `MARK_DEBUG input 		   write, `MARK_DEBUG input read,
						   `MARK_DEBUG input [4:0] address, 
						   `MARK_DEBUG input [7:0] di, output reg [7:0] do,
				output reg [9:0]   history_write_index, output wire history_write, output reg [9:0] history_read_index,
                    
                    /* CPU Memory Interface */
				output wire [27:0] mem_address, 
				input [7:0] 	   mem_rdata, 
				output reg [7:0]   mem_wdata,
				output reg 	   mem_attention_request, 
				input 		   mem_attention_granted,
				output reg 	   mem_read, 
				output reg 	   mem_write,
				output reg 	   set_pc,
                    
                    /* CPU State Recording Control */
				output reg 	   cpu_state_write,
				input [7:0] 	   cpu_state,
				output wire [3:0]  cpu_state_write_index,
						   
						   /* CPU Trace Interface */
						   `MARK_DEBUG output wire monitor_mem_trace_mode,
						   `MARK_DEBUG output reg monitor_mem_trace_toggle,
						   `MARK_DEBUG output wire monitor_irq_inhibit,
						   
						   /* Hypervisor stuff */
						   `MARK_DEBUG input monitor_hypervisor_mode,
						   `MARK_DEBUG output wire monitor_hyper_trap,
						   `MARK_DEBUG input [7:0] protected_hardware,

		    /* For controling access to secure mode */
				input 		   secure_mode_from_cpu,
				output reg 	   secure_mode_from_monitor,
		                output reg         clear_matrix_mode_toggle,
                                    
                    /* Watch interface */
				output reg [27:0]  monitor_watch,
				input 		   monitor_watch_match,
				input [7:0] 	   monitor_p,
				input [15:0] 	   monitor_pc,
						   
						   /* Monitor char input/output */
						   `MARK_DEBUG output reg [7:0] monitor_char_out,
						   `MARK_DEBUG output reg monitor_char_valid,
						   `MARK_DEBUG input terminal_emulator_ready,
						   `MARK_DEBUG input terminal_emulator_ack,
						   
						   `MARK_DEBUG input [7:0] monitor_char_in,
						   `MARK_DEBUG input monitor_char_toggle,
						   `MARK_DEBUG output reg monitor_char_busy,

				input [7:0] 	   uart_char,
				input 		   uart_char_valid,
		    
		    
				output wire [23:0] bit_rate_divisor, input rx, output wire tx, output reg activity);

   initial  secure_mode_from_monitor = 0;
   
// Internal debugging
`MARK_DEBUG wire [7:0] monitor_di;
assign monitor_di = di;

// MON_RESET_TIMEOUT
reg [7:0] reset_timeout = 0;

always @(posedge clk)
  begin
//     $display("reset=%b, reset_processing=%b, reset_timeout=%u",reset,reset_processing,reset_timeout);

     // reset_out is asserted any time reset_timeout != 0
     // BUT clock latched to prevent glitching
     reset_out <= (reset_timeout != 0);
     
     
  if(reset) 
      // Then as soon as we see the reset signal latched by the system, we stop asserting it
     reset_timeout <= 0;     
  else if(address == `MON_RESET_TIMEOUT && write)
    reset_timeout <= di;
  else if(reset_timeout != 0)
    reset_timeout <= reset_timeout - 1;
  else 
    reset_timeout <= 0;      
end

// CPU State Record control
reg cpu_state_was_hold;
reg [5:0] cpu_state_write_index_reg;
reg cpu_state_was_hold_next;
reg [5:0] cpu_state_write_index_next;
assign cpu_state_write_index = cpu_state_write_index_next;

// This is done as a separate combinatorial chunk because I need to be able to
// update the value of cpu_state_write and cpu_state_write_index (output) during
// the current clock cycle so the state write doesn't lag the CPU by a clock cycle.
always @(*)
begin
//  if(reset) begin
//    cpu_state_write <= 0;
//    cpu_state_was_hold_next <= 0;
//    cpu_state_write_index_next <= 0;
//  end else
  begin
    cpu_state_write <= 0;
    cpu_state_write_index_next <= cpu_state_write_index_reg;
    if(cpu_state != 8'h10) begin
      cpu_state_was_hold_next <= 0;
      if(cpu_state_was_hold) begin
        cpu_state_write <= 1;
        cpu_state_write_index_next <= 0;
      end else begin
        if(cpu_state_write_index_reg < 16) begin
          cpu_state_write <= 1;
          cpu_state_write_index_next <= cpu_state_write_index_reg+1;
        end
      end
    end else begin
      cpu_state_was_hold_next <= 1;
    end
  end
end

always @(posedge clk)
begin
  cpu_state_write_index_reg <= cpu_state_write_index_next;
  cpu_state_was_hold <= cpu_state_was_hold_next;
end

// Shared UART control
reg [23:0] bit_rate_divisor_reg;
assign bit_rate_divisor = bit_rate_divisor_reg;

// TX UART control signals
reg tx_send;
wire tx_ready;
reg [7:0] tx_data;

// RX UART control signals
wire [7:0] rx_data;
wire rx_data_ready;
reg rx_data_ack;

// Keyboard input control signals
reg uart_char_waiting;
   

// Instantiate the VHDL TX and RX UARTS
UART_TX_CTRL tx_ctrl(.SEND(tx_send),.BIT_TMR_MAX(bit_rate_divisor_reg),
                     .DATA(tx_data),.CLK(clk),.READY(tx_ready),.UART_TX(tx));
                     
uart_rx_buffered rx_ctrl(.clk(clk),.bit_rate_divisor(bit_rate_divisor_reg),.UART_RX(rx),
                .data(rx_data), .data_ready(rx_data_ready), .data_acknowledge(rx_data_ack));
                
// MON_UART_BITRATE_LO, MON_UART_BITRATE_HI
always @(posedge clk)
begin
  if(reset)
    bit_rate_divisor_reg <= (40000000/2000000) - 1;
  else if(write)
  begin
    if(address == `MON_UART_BITRATE_LO)
      bit_rate_divisor_reg[7:0] <= di;
    if(address == `MON_UART_BITRATE_HI)
      bit_rate_divisor_reg[15:8] <= di;
  end
end

// UART_TX
always @(posedge clk)
begin
  if(reset)
  begin
    tx_data <= 8'hff;
    tx_send <= 0;
  end
  else
  begin
    // tx_send is automatically set to 1 for one clock cycle whenever 
    // UART TX data register is written to.
    if(address == `MON_UART_TX && write)
    begin
      tx_data <= di;
      tx_send <= 1;
    end
    else
      tx_send <= 0;
  end
end

// UART_RX
always @(posedge clk)
begin
   if (uart_char_valid == 1)
   begin
      uart_char_waiting <= 1;
   end
			
  if(address == `MON_UART_RX && read == 1)
  begin
    rx_data_ack <= 1;
    activity <= ~activity;    // Flip activity output on each UART RX CPU read
  end
  if(address == `MON_KEYBOARD_RX && read == 1)
  begin
     uart_char_waiting <= 0;     
    activity <= ~activity;    // Flip activity output on each KEYBOARD RX CPU read
  end
  else if(rx_data_ready == 0) // Don't reset rx_data_ack until rx_data_ready is dropped by the UART.
    rx_data_ack <= 0;
end


// MON_READ_IDX_LO, MON_READ_IDX_HI
always @(posedge clk)
begin
  if(reset)
    history_read_index <= 0;
  else if(write)
    begin
      if(address == `MON_READ_IDX_LO)
        history_read_index[7:0] <= di;
      if(address == `MON_READ_IDX_HI)
        history_read_index[9:8] <= di[1:0];
    end
end

// MON_WRITE_IDX_LO, MON_WRITE_IDX_HI, MON_TRACE_CTRL
wire history_write_continuous;
wire monitor_watch_en;
wire monitor_break_en;
wire monitor_flag_en;
reg [7:0] mem_trace_reg;
reg monitor_watch_matched;
reg monitor_break_matched;
reg monitor_flag_matched;
reg [15:0] monitor_break_addr;
reg [15:0] flag_break_mask;

assign monitor_mem_trace_mode = mem_trace_reg[0];
assign monitor_flag_en = mem_trace_reg[1];
assign history_write = mem_trace_reg[2];
assign history_write_continuous = mem_trace_reg[3];
assign monitor_irq_inhibit = mem_trace_reg[4];
assign monitor_hyper_trap = 1;   
assign monitor_watch_en = mem_trace_reg[6];
assign monitor_break_en = mem_trace_reg[7];

always @(posedge clk)
begin
  if(reset)
  begin
    history_write_index <= 0;
    mem_trace_reg  <= 0;
    monitor_watch_matched <= 0;
    monitor_break_matched <= 0;
    monitor_flag_matched <= 0;
  end
  else if(write)
  begin
    if(address == `MON_WRITE_IDX_LO)
    begin
      history_write_index[7:0] <= di;
      mem_trace_reg[2] <= 0;
    end
    if(address == `MON_WRITE_IDX_HI)
    begin
      history_write_index[9:8] <= di[1:0];
      mem_trace_reg[2] <= 0;
    end
    if(address == `MON_UART_STATUS)
    begin
       // cancel matrix mode if we write to $900A
       clear_matrix_mode_toggle <= ~clear_matrix_mode_toggle;
    end 
    if(address == `MON_STATE_CNT)
    begin
       // Writing to $901C from the monitor also instructs CPU to
       secure_mode_from_monitor <= di[7];
    end
    if(address == `MON_TRACE_CTRL)
    begin
      mem_trace_reg <= di;
    end
    if(address == `MON_TRACE_STEP)
      // Set trace toggle
        monitor_mem_trace_toggle <= di[0];
     // Also clear flag for watch/break match
        monitor_watch_matched <= 0;
        monitor_break_matched <= 0;
        monitor_flag_matched <= 0;     
    if(address == `MON_FLAG_MASK0)
        flag_break_mask[7:0] <= di;
    if(address == `MON_FLAG_MASK1)
        flag_break_mask[15:8] <= di;
        
  end else if(monitor_watch_match && monitor_watch_en)
  begin
      mem_trace_reg[0] <= 1;    // Auto set trace mode on watch address match
      monitor_watch_matched <= 1;    // Also set watch matched bit
  end
  else if(monitor_break_addr == monitor_pc && monitor_break_en)
  begin
      mem_trace_reg[0] <= 1;    // Auto set trace mode on break address match
     // And alert of breakpoint match if we were not already tracing
     if (mem_trace_reg[0] == 0)
       begin
          monitor_break_matched <= 1;    // Also set break matched bit
       end
  end
  else if(((monitor_p & flag_break_mask[15:8]) || (~monitor_p & flag_break_mask[7:0])) && monitor_flag_en)
  begin
      mem_trace_reg[0] <= 1;
      monitor_flag_matched <= 1;    // Also set flag matched bit
  end
  else if(history_write == 1)
  begin
    // record history continuously until full.   The last slot is reserved for capturing current state.
    if(history_write_index < 1022)
      history_write_index <= history_write_index + 1;
    else if(history_write_continuous)
      history_write_index <= 0; // Wrap around to 0
    else
      mem_trace_reg[2] <= 0; // Disable writes (and auto increment)
  end
end


// MON_MEM_ADDRn, MON_MEM_INC
reg [31:0] mem_addr_reg;
assign mem_address = mem_addr_reg[27:0];

always @(posedge clk)
begin
  if(reset)
  begin
    mem_addr_reg[31:0] <= 0;
  end
  else if(write)
  begin  
    if(address == `MON_MEM_INC)
      mem_addr_reg <= mem_addr_reg + 1;    // Do we need anything but a 1 here?  Will be easy enough to change later.
    else
    begin
      if(address == `MON_MEM_ADDR0)
        mem_addr_reg[7:0] <= di;
      if(address == `MON_MEM_ADDR1)
        mem_addr_reg[15:8] <= di;
      if(address == `MON_MEM_ADDR2)
        mem_addr_reg[23:16] <= di;
      if(address == `MON_MEM_ADDR3)
        mem_addr_reg[31:24] <= di;
    end
  end
end

// This section implements the state machine for performing memory read and write transactions
// with the GS4510 CPU through the monitor interface.
wire mem_done;
reg mem_error;
reg [7:0] mem_read_byte;
reg [1:0] mem_state;
reg [24:0] mem_timeout;

`define MEM_STATE_IDLE    0         // Nothing in progress (also where we go after ACK)
`define MEM_STATE_WAIT    1         // Waiting for monitor_mem_attention_granted to be 0
`define MEM_STATE_REQ     2         // Waiting for CPU to grant request (monitor_mem_attention_request=1)
`define MEM_STATE_ACK     3         // CPU has granted request (monitor_mem_attention_granted is now 1)

reg mem_timer_reset;
wire mem_timer_expired;

assign mem_timer_expired = mem_timeout == 0;
assign mem_done = mem_state == `MEM_STATE_IDLE;

always @(posedge clk)
begin
  if(mem_timer_reset)
    mem_timeout <= 33554431;
  else if(mem_timer_expired == 0)
    mem_timeout = mem_timeout - 1;
end

// MOM_MEM_READ, MON_MEM_WRITE, MON_MEM_STATUS, SET_PC
always @(posedge clk)
begin
  if(reset)
  begin
    mem_error <= 0;
    mem_state <= `MEM_STATE_IDLE;
    mem_read <= 0;
    mem_write <= 0;
    set_pc <= 0;
  end
  else
  begin
    mem_timer_reset <= 0;
    if(mem_timer_expired && ~mem_timer_reset && mem_state != `MEM_STATE_IDLE)
    begin
      mem_attention_request <= 0;
      mem_error <= 1;
      mem_state <= `MEM_STATE_IDLE;
    end
    else
    begin
      case(mem_state)
      `MEM_STATE_IDLE:
      begin
        mem_read <= 0;
        mem_write <= 0;
        set_pc <= 0;
        if(address == `MON_MEM_READ && write)
        begin
          set_pc <= di[7];        /* Top bit turns the read request into a set PC request */
          mem_read <= 1;
          mem_error <= 0;
          mem_state <= `MEM_STATE_WAIT;
          mem_timer_reset <= 1;
        end
        else if(address == `MON_MEM_WRITE && write)
        begin
          mem_write <= 1;
          mem_error <= 0;
          mem_wdata <= di;
          mem_state <= `MEM_STATE_WAIT;
          mem_timer_reset <= 1;
        end
      end
      `MEM_STATE_WAIT:
      begin
        if(mem_attention_granted == 0)
        begin
          mem_timer_reset <= 1;
          mem_state <= `MEM_STATE_REQ;
          mem_attention_request <= 1;
        end
      end
      `MEM_STATE_REQ:
      begin
        if(mem_attention_granted == 1)
        begin
            mem_read_byte <= mem_rdata;
            mem_attention_request <= 0;
            mem_timer_reset <= 1;
            mem_state <= `MEM_STATE_ACK;
        end
      end
      `MEM_STATE_ACK:
      begin
        if(mem_attention_granted == 0)
            mem_state <= `MEM_STATE_IDLE;
      end
      endcase;
    end
  end
end
    
// MON_WATCH_ADDR0-3
always @(posedge clk)
begin
  if(reset)
    monitor_watch <= 0;
  else if(write)
  begin
    if(address == `MON_WATCH_ADDR0)
      monitor_watch[7:0] <= di;
    if(address == `MON_WATCH_ADDR1)
      monitor_watch[15:8] <= di;
    if(address == `MON_WATCH_ADDR2)
      monitor_watch[23:16] <= di;
    if(address == `MON_WATCH_ADDR3)
      monitor_watch[27:24] <= di[3:0];
  end
end

// MON_BREAK_ADDR0-1
always @(posedge clk)
begin
  if(reset)
    monitor_break_addr <= 0;
  else if(write)
  begin
    if(address == `MON_BREAK_ADDR0)
      monitor_break_addr[7:0] <= di;
    if(address == `MON_BREAK_ADDR1)
      monitor_break_addr[15:8] <= di;
  end
end

// MON_CHAR_IN
`MARK_DEBUG reg monitor_char_toggle_last;
`MARK_DEBUG reg monitor_char_sent;

always @(posedge clk)
begin
  if(reset)
  begin
    monitor_char_busy <= 0;
    monitor_char_toggle_last <= monitor_char_toggle;
    monitor_char_sent <= 0;
    monitor_char_valid <= 0;
  end
  else
  begin
    // One CPU reads the character, drop busy bit
    if(address == `MON_CHAR_INOUT && read == 1)
    begin
      monitor_char_busy <= 0;
    end
    else if(monitor_char_toggle_last != monitor_char_toggle)
    begin
      monitor_char_busy <= 1;
      monitor_char_toggle_last <= monitor_char_toggle;
    end
    
    if(address == `MON_CHAR_INOUT && write == 1)
    begin
      monitor_char_out <= di;
      monitor_char_valid <= 1;
      monitor_char_sent <= 1;       // This *may* be totally redundant wrt. monitor_char_valid.
    end
    else
    begin
      // Once terminal emulator acks the character we can deassert monitor_char_valid.  That also
      // then allows us to "trust" terminal_emulator_ready.  We can't just use terminal_emulator_ready
      // going to 0 because it's running at 100Mhz and it might only be zero for one clock cycle and
      // we'll miss it.  But terminal_emulator_ack is held by the matrix compositor until we deassert
      // monitor_char_valid.  So it's a full handshake and avoids needing a timer.
      if(terminal_emulator_ack && monitor_char_valid)
        monitor_char_valid <= 0;
    end
  end
end

// Monitor control register reads (synchronous)
// Note: We could probably save a bunch of resources by not making
// every writable register also be readable.  The CPU doesn't read
// from most of these and it just ties up a bunch of logic resources
// to make them all accessible.
always @(posedge clk)
begin
  case(address) // synthesis parallel_case
//  `MON_READ_IDX_LO:      do <= history_read_index[7:0];
//  `MON_READ_IDX_HI:      do <= { 6'b000000, history_read_index[9:8] };
//  `MON_WRITE_IDX_LO:     do <= history_write_index[7:0];
//  `MON_WRITE_IDX_HI:     do <= { 6'b000000, history_write_index[9:8] };
  `MON_TRACE_CTRL:       do <= { mem_trace_reg[7:0] };
    `MON_TRACE_STEP:       do <= { monitor_break_matched, monitor_watch_matched, monitor_flag_matched, monitor_watch_en, monitor_break_en, monitor_watch_match, 1'b0, monitor_mem_trace_toggle };
  
//  `MON_FLAG_MASK0:       do <= flag_break_mask[7:0];
//  `MON_FLAG_MASK1:       do <= flag_break_mask[15:8];
  
  `MON_MEM_ADDR0:        do <= mem_addr_reg[7:0];
  `MON_MEM_ADDR1:        do <= mem_addr_reg[15:8];
  `MON_MEM_ADDR2:        do <= mem_addr_reg[23:16];
  `MON_MEM_ADDR3:        do <= mem_addr_reg[31:24];
  `MON_MEM_READ:         do <= mem_read_byte;
//  `MON_MEM_WRITE:        do <= mem_wdata;
  `MON_MEM_STATUS:       do <= { mem_done, mem_error, 3'b000, monitor_hypervisor_mode, mem_state};
  `MON_UART_RX:          do <= rx_data;
    `MON_KEYBOARD_RX:    do <= uart_char;    
//  `MON_UART_TX:          do <= tx_data;
  `MON_UART_STATUS:      do <= { rx_data_ready & ~rx_data_ack, tx_ready, uart_char_waiting, 5'b00000}; // Once we ack, mask off data ready bit.
  `MON_STATE_CNT:        do <= { secure_mode_from_cpu, 2'b00, cpu_state_write_index_reg };
  
//  `MON_WATCH_ADDR0:      do <= monitor_watch[7:0];
//  `MON_WATCH_ADDR1:      do <= monitor_watch[15:8];
//  `MON_WATCH_ADDR2:      do <= monitor_watch[23:16];
//  `MON_WATCH_ADDR3:      do <= { 4'b0000, monitor_watch[27:24] };

//  `MON_BREAK_ADDR0:      do <= monitor_break_addr[7:0];
//  `MON_BREAK_ADDR1:      do <= monitor_break_addr[15:8];
  
//  `MON_UART_BITRATE_LO:  do <= bit_rate_divisor_reg[7:0];
//  `MON_UART_BITRATE_HI:  do <= bit_rate_divisor_reg[15:8];
  
  `MON_PROT_HARDWARE:   do <= protected_hardware;
  `MON_CHAR_INOUT:      do <= monitor_char_in;
  `MON_CHAR_STATUS:     do <= { monitor_char_busy, terminal_emulator_ready & ~monitor_char_valid, 6'b000000};
  
  default: do <= 8'hFF;
  endcase;
end

endmodule
