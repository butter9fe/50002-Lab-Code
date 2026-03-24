// picorv32_soc.v -- CPU + BRAM + simpleuart + GPIO + Timer + DDR3 + Framebuffer + Palette
// Bus architecture follows picosoc.v exactly
// Reference: picosoc.v lines 120-132 (simpleuart wiring, mem_ready, mem_rdata)
//
// UART uses simpleuart.v from PicoRV32 repo (ISC licensed, by Claire Wolf).
// No Alchitry Lucid UART components needed. reg_dat_wait stalls CPU during TX.
//
// IO memory map (0x1xxxxxxx):
//   0x10000000: GPIO LEDs        (R/W)
//   0x10000010: UART data        (R/W) -- simpleuart reg_dat
//   0x10000014: UART baud div    (R/W) -- simpleuart reg_div
//   0x10000020: Timer            (R) free-running 32-bit counter
//   0x10000030: Buttons          (R) bits [4:0] = right,left,down,fire,up

module picorv32_soc (
    input sys_clk,
    input resetn,
    output reg [7:0] gpio_led,

    // UART serial pins (directly to/from FTDI)
    // Reference: picosoc.v lines 194-195
    output ser_tx,
    input  ser_rx,

    // DDR3 read interface (to/from ddr3_cache)
    output [25:0] ddr_rd_addr,
    output        ddr_rd_cmd_valid,
    input         ddr_rd_ready,
    input  [31:0] ddr_rd_data,
    input         ddr_rd_data_valid,

    // DDR3 write interface (to/from ddr3_cache)
    output [25:0] ddr_wr_addr,
    output [31:0] ddr_wr_data,
    output [3:0]  ddr_wr_strb,
    output        ddr_wr_valid,
    input         ddr_wr_ready,

    // Framebuffer write interface (to dual-port RAM in Lucid top)
    output reg [15:0] fb_waddr,
    output reg [7:0]  fb_wdata,
    output reg        fb_wen,

    // Palette write interface (to dual-port RAM in Lucid top)
    output reg [7:0]  pal_waddr,
    output reg [23:0] pal_wdata,
    output reg        pal_wen,

    // Button inputs (active high, active after 2-FF sync)
    input [4:0] buttons_raw
);

    // -------------------------------------------------------
    // PicoRV32 memory bus signals
    // -------------------------------------------------------
    wire        mem_valid;
    wire        mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_rdata;

    wire cpu_trap;

    // -------------------------------------------------------
    // Address decode
    // -------------------------------------------------------
    wire bram_sel    = (mem_addr[31:28] == 4'h0);
    wire io_sel      = (mem_addr[31:28] == 4'h1);
    wire ddr_sel     = (mem_addr[31:28] == 4'h2);
    wire palette_sel = (mem_addr[31:20] == 12'h301);
    wire fb_sel      = (mem_addr[31:28] == 4'h3) && !palette_sel;

    // -------------------------------------------------------
    // BRAM 4KB (1024 x 32-bit words)
    // Reference: picosoc.v ram_ready pattern
    // -------------------------------------------------------
    wire [31:0] bram_rdata;

    reg bram_ready_r;
    always @(posedge sys_clk) begin
        if (!resetn)
            bram_ready_r <= 0;
        else
            bram_ready_r <= mem_valid && bram_sel && !bram_ready_r && (mem_wstrb == 4'b0000);
    end

    wire bram_ready = (mem_valid && bram_sel && |mem_wstrb) || bram_ready_r;
    wire [3:0] bram_wen = (mem_valid && bram_sel) ? mem_wstrb : 4'b0;

    bram #(
        .WORDS(1024)
    ) bram_inst (
        .clk(sys_clk),
        .wen(bram_wen),
        .addr(mem_addr[11:2]),
        .wdata(mem_wdata),
        .rdata(bram_rdata)
    );

    // -------------------------------------------------------
    // simpleuart (from PicoRV32 picosoc, ISC license)
    // Reference: picosoc.v lines 120-128, 190-206
    //
    // 0x10000010: data register (R=rx byte or 0xFFFFFFFF, W=tx byte)
    // 0x10000014: baud divisor  (R/W, DEFAULT_DIV = 88 for 921600 baud)
    //
    // reg_dat_wait stalls the CPU via mem_ready when TX is busy.
    // No firmware busy-wait polling needed.
    // -------------------------------------------------------
    wire uart_dat_sel = mem_valid && io_sel && (mem_addr[7:0] == 8'h10);
    wire uart_div_sel = mem_valid && io_sel && (mem_addr[7:0] == 8'h14);

    wire [31:0] uart_dat_do;
    wire [31:0] uart_div_do;
    wire        uart_dat_wait;

    // Reference: picosoc.v lines 190-206
    simpleuart #(
        .DEFAULT_DIV(88)
    ) simpleuart (
        .clk         (sys_clk),
        .resetn      (resetn),
        .ser_tx      (ser_tx),
        .ser_rx      (ser_rx),
        .reg_div_we  (uart_div_sel ? mem_wstrb : 4'b0000),
        .reg_div_di  (mem_wdata),
        .reg_div_do  (uart_div_do),
        .reg_dat_we  (uart_dat_sel ? mem_wstrb[0] : 1'b0),
        .reg_dat_re  (uart_dat_sel && !mem_wstrb),
        .reg_dat_di  (mem_wdata),
        .reg_dat_do  (uart_dat_do),
        .reg_dat_wait(uart_dat_wait)
    );

    // -------------------------------------------------------
    // Other IO peripherals (0x1xxxxxxx, excluding UART)
    // Combinational ready, zero wait states
    // -------------------------------------------------------
    wire io_other_sel = io_sel && (mem_addr[7:0] != 8'h10) && (mem_addr[7:0] != 8'h14);
    wire io_other_ready = mem_valid && io_other_sel;

    // --- GPIO LEDs ---
    always @(posedge sys_clk) begin
        if (!resetn) begin
            gpio_led <= 8'h00;
        end else begin
            if (mem_valid && io_sel && |mem_wstrb && mem_addr[7:0] == 8'h00)
                gpio_led <= mem_wdata[7:0];
        end
    end

    // --- Button input: 2-FF synchronizer ---
    reg [4:0] btn_sync1, btn_sync2;
    always @(posedge sys_clk) begin
        if (!resetn) begin
            btn_sync1 <= 0;
            btn_sync2 <= 0;
        end else begin
            btn_sync1 <= buttons_raw;
            btn_sync2 <= btn_sync1;
        end
    end

    // --- Timer free-running 32-bit counter ---
    reg [31:0] timer_reg;
    always @(posedge sys_clk) begin
        if (!resetn)
            timer_reg <= 0;
        else
            timer_reg <= timer_reg + 1;
    end

    // --- Non-UART IO read data mux ---
    reg [31:0] io_rdata;
    always @(*) begin
        case (mem_addr[7:0])
            8'h00:   io_rdata = {24'h0, gpio_led};
            8'h20:   io_rdata = timer_reg;
            8'h30:   io_rdata = {27'h0, btn_sync2};
            default: io_rdata = 32'h0;
        endcase
    end

    // -------------------------------------------------------
    // DDR3 via ddr3_cache
    // -------------------------------------------------------
    wire ddr_read  = mem_valid && ddr_sel && (mem_wstrb == 4'b0000);
    wire ddr_write = mem_valid && ddr_sel && |mem_wstrb;

    reg ddr_rd_done;
    always @(posedge sys_clk) begin
        if (!resetn)           ddr_rd_done <= 0;
        else if (!mem_valid)   ddr_rd_done <= 0;
        else if (ddr_rd_data_valid) ddr_rd_done <= 1;
    end

    assign ddr_rd_addr      = mem_addr[27:2];
    assign ddr_rd_cmd_valid = ddr_read && ddr_rd_ready && !ddr_rd_done && !ddr_rd_data_valid;
    wire   ddr_mem_rd_ready = ddr_rd_data_valid;

    reg ddr_wr_done;
    always @(posedge sys_clk) begin
        if (!resetn)         ddr_wr_done <= 0;
        else if (!mem_valid) ddr_wr_done <= 0;
        else if (ddr_write && ddr_wr_ready && !ddr_wr_done) ddr_wr_done <= 1;
    end

    assign ddr_wr_addr  = mem_addr[27:2];
    assign ddr_wr_data  = mem_wdata;
    assign ddr_wr_strb  = mem_wstrb;
    assign ddr_wr_valid = ddr_write && ddr_wr_ready && !ddr_wr_done;
    wire   ddr_mem_wr_ready = ddr_write && ddr_wr_ready && !ddr_wr_done;

    wire ddr_ready = ddr_mem_rd_ready || ddr_mem_wr_ready;

    // -------------------------------------------------------
    // Framebuffer write (write-only, 0x3000xxxx)
    // -------------------------------------------------------
    wire fb_ready = mem_valid && fb_sel && |mem_wstrb;

    always @(posedge sys_clk) begin
        if (!resetn) begin
            fb_wen <= 0;
        end else begin
            fb_wen <= 0;
            if (mem_valid && fb_sel && |mem_wstrb) begin
                fb_waddr <= mem_addr[15:0];
                fb_wen   <= 1;
                if (mem_wstrb[0])      fb_wdata <= mem_wdata[7:0];
                else if (mem_wstrb[1]) fb_wdata <= mem_wdata[15:8];
                else if (mem_wstrb[2]) fb_wdata <= mem_wdata[23:16];
                else                   fb_wdata <= mem_wdata[31:24];
            end
        end
    end

    // -------------------------------------------------------
    // Palette write (write-only, 0x3010xxxx)
    // -------------------------------------------------------
    wire palette_ready = mem_valid && palette_sel && |mem_wstrb;

    always @(posedge sys_clk) begin
        if (!resetn) begin
            pal_wen <= 0;
        end else begin
            pal_wen <= 0;
            if (mem_valid && palette_sel && |mem_wstrb) begin
                pal_waddr <= mem_addr[9:2];
                pal_wdata <= mem_wdata[23:0];
                pal_wen   <= 1;
            end
        end
    end

    // -------------------------------------------------------
    // Bus mux -- Reference: picosoc.v lines 127-132
    // -------------------------------------------------------
    wire unknown_ready = mem_valid && !(bram_sel || io_sel || ddr_sel || fb_sel || palette_sel);

    // Reference: picosoc.v line 128 -- uart_dat_sel stalls on reg_dat_wait
    assign mem_ready = bram_ready || io_other_ready ||
                       uart_div_sel || (uart_dat_sel && !uart_dat_wait) ||
                       ddr_ready || fb_ready || palette_ready || unknown_ready;

    assign mem_rdata = bram_ready      ? bram_rdata  :
                       io_other_ready  ? io_rdata    :
                       uart_div_sel    ? uart_div_do :
                       (uart_dat_sel && !uart_dat_wait) ? uart_dat_do :
                       ddr_ready       ? ddr_rd_data :
                       32'h0000_0000;

    // -------------------------------------------------------
    // PicoRV32 CPU
    // -------------------------------------------------------
    picorv32 #(
        .STACKADDR      (32'h0000_1000),
        .PROGADDR_RESET  (32'h0000_0000),
        .PROGADDR_IRQ    (32'h0000_0000),
        .BARREL_SHIFTER  (1),
        .COMPRESSED_ISA  (0),
        .ENABLE_COUNTERS (0),
        .ENABLE_MUL      (1),
        .ENABLE_DIV      (1),
        .ENABLE_FAST_MUL (0),
        .ENABLE_IRQ      (0),
        .ENABLE_TRACE    (0)
    ) cpu (
        .clk       (sys_clk),
        .resetn    (resetn),
        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),
        .trap      (cpu_trap),
        .mem_la_read  (),
        .mem_la_write (),
        .mem_la_addr  (),
        .mem_la_wdata (),
        .mem_la_wstrb (),
        .pcpi_valid   (),
        .pcpi_insn    (),
        .pcpi_rs1     (),
        .pcpi_rs2     (),
        .pcpi_wr      (1'b0),
        .pcpi_rd      (32'b0),
        .pcpi_wait    (1'b0),
        .pcpi_ready   (1'b0),
        .irq          (32'b0),
        .eoi          (),
        .trace_valid  (),
        .trace_data   ()
    );

endmodule
