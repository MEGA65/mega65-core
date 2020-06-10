
module syn_fifo (
clk      , // Clock input
rst      , // Active high reset
data_in  , // Data input
rd_en    , // Read enable
wr_en    , // Write Enable
data_out , // Data Output
empty    , // FIFO empty
half_full, // FIFO half full
full       // FIFO full
);    
 
// FIFO constants
parameter DATA_WIDTH = 32;
parameter ADDR_WIDTH = 10;
parameter RAM_DEPTH = (1 << ADDR_WIDTH);
// Port Declarations
input clk ;
input rst ;
input rd_en ;
input wr_en ;
input [DATA_WIDTH-1:0] data_in ;
output full ;
output half_full;
output empty ;
output [DATA_WIDTH-1:0] data_out ;

//-----------Internal variables-------------------
reg [ADDR_WIDTH-1:0] wr_pointer;
reg [ADDR_WIDTH-1:0] rd_pointer;
reg [ADDR_WIDTH :0] status_cnt;
reg [DATA_WIDTH-1:0] data_out ;
reg [DATA_WIDTH-1:0] ram [2**ADDR_WIDTH-1:0];
//-----------Variable assignments---------------
assign full = (status_cnt == (RAM_DEPTH-1));
assign half_full = (status_cnt >= (RAM_DEPTH/2));
assign empty = (status_cnt == 0);

//-----------Code Start---------------------------
always @ (posedge clk or posedge rst)
begin : WRITE_POINTER
  if (rst) begin
    wr_pointer <= 0;
  end else if (wr_en ) begin
    wr_pointer <= wr_pointer + 1;
  end
end

always @ (posedge clk or posedge rst)
begin : READ_POINTER
  if (rst) begin
    rd_pointer <= 0;
  end else if (rd_en ) begin
    rd_pointer <= rd_pointer + 1;
  end
end


always @ (posedge clk or posedge rst)
begin : STATUS_COUNTER
  if (rst) begin
    status_cnt <= 0;
  // Read but no write.
  end else if (rd_en && !wr_en 
                && (status_cnt != 0)) begin
    status_cnt <= status_cnt - 1;
  // Write but no read.
  end else if (wr_en && !rd_en 
               && (status_cnt != RAM_DEPTH)) begin
    status_cnt <= status_cnt + 1;
  end
end 


always @(posedge clk)
begin
  if (wr_en)
    ram[wr_pointer] <= data_in;
end

always @(posedge clk or posedge rst)
begin
  if (rst) begin
    data_out <= 0;
  end else if (rd_en )
    data_out <= ram[rd_pointer];
end


endmodule
