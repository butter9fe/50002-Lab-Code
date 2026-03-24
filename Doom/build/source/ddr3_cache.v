// ddr3_cache.v -- Direct-mapped BRAM cache for DDR3
//
// Reference: lru_cache.sv (Alchitry, combinational MIG outputs + registered state)
// Reference: nklabs icache.v (direct-mapped, BRAM tag+data arrays)
//
// Architecture matches lru_cache.sv exactly:
//   - MIG outputs (enable, cmd, addr, wr_enable, wr_data, wr_mask) are COMBINATIONAL
//   - CPU outputs (rd_ready, wr_ready) are COMBINATIONAL
//   - rd_data / rd_data_valid are REGISTERED (1-cycle pulse)
//   - State transitions and cache updates are REGISTERED
//
// 256 lines, 16 bytes/line = 4KB data.
// One DDR3 128-bit burst fills one line.
// Write-invalidation: on write, invalidate matching cache line.
//
// Address decomposition (26-bit word address = mem_addr[27:2]):
//   [25:10] = TAG   (16 bits)
//   [9:2]   = INDEX (8 bits -> 256 lines)
//   [1:0]   = WORD  (2 bits -> 4 words/line)
//
// MIG address = {1'b0, word_addr[25:2], 3'b000} (28 bits)
// Reference: lru_cache.sv line 113: mem_in.addr = {D_address_q[entry], 3'h0}

module ddr3_cache (
    input             clk,
    input             resetn,

    // CPU read interface
    input      [25:0] rd_addr,
    input             rd_cmd_valid,
    output            rd_ready,
    output reg [31:0] rd_data,
    output            rd_data_valid,

    // CPU write interface
    input      [25:0] wr_addr,
    input      [31:0] wr_data,
    input      [3:0]  wr_strb,
    input             wr_valid,
    output            wr_ready,

    // MIG interface (active-high wr_mask = don't write that byte)
    output reg [27:0] mig_addr,
    output reg [2:0]  mig_cmd,
    output reg        mig_enable,
    output reg [127:0] mig_wr_data,
    output reg        mig_wr_enable,
    output reg [15:0] mig_wr_mask,
    input             mig_rdy,
    input      [127:0] mig_rd_data,
    input             mig_rd_valid,
    input             mig_wr_rdy
);

    // State encoding
    localparam [2:0] S_IDLE      = 3'd0;
    localparam [2:0] S_CHECK     = 3'd1;
    localparam [2:0] S_FILL_CMD  = 3'd2;
    localparam [2:0] S_FILL_WAIT = 3'd3;
    localparam [2:0] S_WR_DATA   = 3'd4;
    localparam [2:0] S_WR_CMD    = 3'd5;

    // State register
    reg [2:0] state_q;
    reg [2:0] state_d;

    // Valid bits in registers (async-readable for combinational hit check)
    reg valid [0:255];

    // Tag and data arrays
    reg [15:0]  tags  [0:255];
    reg [127:0] lines [0:255];

    // Latched request info (registered)
    reg [25:0] req_addr_q;
    reg [15:0] req_tag_q;
    reg [7:0]  req_index_q;
    reg [1:0]  req_word_q;

    // Write request latch (registered)
    reg [31:0] wr_data_q;
    reg [3:0]  wr_strb_q;
    reg [25:0] wr_addr_q;

    // Read data output (registered, 1-cycle pulse)
    reg        rd_data_valid_q;
    reg        rd_data_valid_d;

    assign rd_data_valid = rd_data_valid_q;

    // ---- Combinational: CPU-facing ready signals ----
    // Reference: lru_cache.sv lines 116-117
    //   wr_ready = D_write_state_q == 1'h0;
    //   rd_ready = D_read_state_q == 1'h0;
    assign rd_ready = (state_q == S_IDLE);
    assign wr_ready = (state_q == S_IDLE);

    // ---- Combinational: MIG outputs + next-state logic ----
    // Reference: lru_cache.sv lines 89-358 (single always @* block)
    always @(*) begin
        // Defaults (Reference: lru_cache.sv lines 110-114)
        mig_enable = 1'b0;
        mig_wr_enable = 1'b0;
        mig_cmd = 3'bx;
        mig_addr = {1'b0, req_addr_q[25:2], 3'b000};
        mig_wr_data = {wr_data_q, wr_data_q, wr_data_q, wr_data_q};
        mig_wr_mask = 16'hFFFF;

        // Default next state: hold
        state_d = state_q;
        rd_data_valid_d = 1'b0;

        case (state_q)
            S_IDLE: begin
                // Writes have priority (same as LRU cache pattern)
                if (wr_valid) begin
                    state_d = S_WR_DATA;
                end
                else if (rd_cmd_valid) begin
                    state_d = S_CHECK;
                end
            end

            S_CHECK: begin
                // Tag lookup (valid[] is async, tags[] inferred as BRAM)
                if (valid[req_index_q] && tags[req_index_q] == req_tag_q) begin
                    // Hit -- return data
                    rd_data_valid_d = 1'b1;
                    state_d = S_IDLE;
                end else begin
                    // Miss -- fill from DDR3
                    state_d = S_FILL_CMD;
                end
            end

            S_FILL_CMD: begin
                // Reference: lru_cache.sv lines 334-340 (READ_CMD state)
                mig_enable = 1'b1;
                mig_cmd = 3'h1;
                mig_addr = {1'b0, req_addr_q[25:2], 3'b000};
                if (mig_rdy) begin
                    state_d = S_FILL_WAIT;
                end
            end

            S_FILL_WAIT: begin
                // Reference: lru_cache.sv lines 341-356 (WAIT_READ state)
                if (mig_rd_valid) begin
                    rd_data_valid_d = 1'b1;
                    state_d = S_IDLE;
                end
            end

            S_WR_DATA: begin
                // Reference: lru_cache.sv lines 320-324 (WRITE_DATA state)
                mig_wr_enable = 1'b1;
                mig_wr_data = {wr_data_q, wr_data_q, wr_data_q, wr_data_q};
                // Compute write mask: active-high = DON'T write
                if (wr_addr_q[1:0] == 2'd0)
                    mig_wr_mask = {12'hFFF, ~wr_strb_q};
                else if (wr_addr_q[1:0] == 2'd1)
                    mig_wr_mask = {8'hFF, ~wr_strb_q, 4'hF};
                else if (wr_addr_q[1:0] == 2'd2)
                    mig_wr_mask = {4'hF, ~wr_strb_q, 8'hFF};
                else
                    mig_wr_mask = {~wr_strb_q, 12'hFFF};

                if (mig_wr_rdy) begin
                    state_d = S_WR_CMD;
                end
            end

            S_WR_CMD: begin
                // Reference: lru_cache.sv lines 326-332 (WRITE_CMD state)
                mig_enable = 1'b1;
                mig_cmd = 3'h0;
                mig_addr = {1'b0, wr_addr_q[25:2], 3'b000};
                if (mig_rdy) begin
                    state_d = S_IDLE;
                end
            end

            default: begin
                state_d = S_IDLE;
            end
        endcase
    end

    // ---- Combinational: word select from cache line ----
    reg [31:0] cache_word;
    always @(*) begin
        case (req_word_q)
            2'd0: cache_word = lines[req_index_q][ 31:  0];
            2'd1: cache_word = lines[req_index_q][ 63: 32];
            2'd2: cache_word = lines[req_index_q][ 95: 64];
            2'd3: cache_word = lines[req_index_q][127: 96];
        endcase
    end

    // ---- Combinational: word select from fill data ----
    reg [31:0] fill_word;
    always @(*) begin
        case (req_word_q)
            2'd0: fill_word = mig_rd_data[ 31:  0];
            2'd1: fill_word = mig_rd_data[ 63: 32];
            2'd2: fill_word = mig_rd_data[ 95: 64];
            2'd3: fill_word = mig_rd_data[127: 96];
        endcase
    end

    // ---- Sequential: state updates, cache fills, request latching ----
    integer i;
    always @(posedge clk) begin
        if (!resetn) begin
            state_q <= S_IDLE;
            rd_data_valid_q <= 1'b0;
            rd_data <= 32'h0;
            req_addr_q <= 26'h0;
            req_tag_q <= 16'h0;
            req_index_q <= 8'h0;
            req_word_q <= 2'h0;
            wr_data_q <= 32'h0;
            wr_strb_q <= 4'h0;
            wr_addr_q <= 26'h0;
            for (i = 0; i < 256; i = i + 1)
                valid[i] <= 1'b0;
        end else begin
            // Update state
            state_q <= state_d;
            rd_data_valid_q <= rd_data_valid_d;

            case (state_q)
                S_IDLE: begin
                    if (wr_valid) begin
                        // Latch write request
                        wr_addr_q <= wr_addr;
                        wr_data_q <= wr_data;
                        wr_strb_q <= wr_strb;
                        // Write-invalidation (conservative: always clear)
                        valid[wr_addr[9:2]] <= 1'b0;
                    end
                    else if (rd_cmd_valid) begin
                        // Latch read request
                        req_addr_q  <= rd_addr;
                        req_tag_q   <= rd_addr[25:10];
                        req_index_q <= rd_addr[9:2];
                        req_word_q  <= rd_addr[1:0];
                    end
                end

                S_CHECK: begin
                    if (valid[req_index_q] && tags[req_index_q] == req_tag_q) begin
                        // Hit: output word from cache
                        rd_data <= cache_word;
                    end
                end

                S_FILL_WAIT: begin
                    if (mig_rd_valid) begin
                        // Fill cache line
                        lines[req_index_q] <= mig_rd_data;
                        tags[req_index_q]  <= req_tag_q;
                        valid[req_index_q] <= 1'b1;
                        // Output requested word
                        rd_data <= fill_word;
                    end
                end

                S_WR_CMD: begin
                    // Write completes when mig_rdy accepted the command
                    // (combinational block already set mig_enable=1)
                end

                default: begin
                end
            endcase
        end
    end

endmodule
