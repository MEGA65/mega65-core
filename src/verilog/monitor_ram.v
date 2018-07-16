// Simple 2K single ported synchronous ram
module monitorram(clk, we, addr, di, do);
input clk;
input we;
input [10:0] addr;
input [7:0] di;
output [7:0] do;
reg [7:0] ram [0:2047];
reg [7:0] do;

always @(posedge clk)
begin
    if(we)
        ram[addr] = di;
    do = ram[addr];
end

endmodule
