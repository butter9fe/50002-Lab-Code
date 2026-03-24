// bram.v Synchronous BRAM with byte-enable writes and hex file init.
// Identical to picosoc_mem except for $readmemh initialization.

module bram #(
    parameter WORDS = 1024
) (
    input clk,
    input [3:0] wen,
    input [$clog2(WORDS)-1:0] addr,
    input [31:0] wdata,
    output reg [31:0] rdata
);
    reg [31:0] mem [0:WORDS-1];

    initial $readmemh("D:/_Work/SUTD/CompStruct/alchitry/Doom/source/firmware.hex", mem);

    always @(posedge clk) begin
        rdata <= mem[addr];
        if (wen[0]) mem[addr][ 7: 0] <= wdata[ 7: 0];
        if (wen[1]) mem[addr][15: 8] <= wdata[15: 8];
        if (wen[2]) mem[addr][23:16] <= wdata[23:16];
        if (wen[3]) mem[addr][31:24] <= wdata[31:24];
    end
endmodule
