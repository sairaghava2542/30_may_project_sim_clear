// ============================================================================
// 8x8 Pipelined Systolic Array -- INT8 Matrix Multiply Accelerator
//
// Operation: C[8x8] = A[8x8] x B[8x8]
// Inputs   : signed INT8
// Outputs  : signed INT32 accumulated results
//
// High-performance change versus baseline:
//   Each PE has a registered multiplier output, so one extra COMPUTE flush
//   cycle is required. Baseline compute cycles = 22. Pipelined compute cycles
//   = 23.
// ============================================================================

`timescale 1ns/1ps

module systolic_array_8x8 #(
    parameter integer COMPUTE_CYCLES = 23
)(
    input  wire         clk,
    input  wire         rst_n,

    // Control
    input  wire         start,
    output wire         busy,
    output wire         done,

    // Weight loading / streaming: 8 weights per cycle
    input  wire [63:0]  wgt_data,
    input  wire         wgt_valid,

    // Activation streaming: 8 activations per cycle
    input  wire [63:0]  act_data,
    input  wire         act_valid,

    // Result drain: one column of 8 results per cycle
    output wire [255:0] result_data,
    output wire         result_valid,
    output wire [2:0]   result_col
);

    localparam [2:0] S_IDLE    = 3'd0,
                     S_LOAD    = 3'd1,
                     S_COMPUTE = 3'd2,
                     S_DRAIN   = 3'd3,
                     S_DONE    = 3'd4;

    localparam [4:0] COMPUTE_CYCLES_M1 = COMPUTE_CYCLES - 1;

    reg [2:0] state, next_state;
    reg [4:0] cycle_cnt;

    reg pe_weight_load;
    reg pe_compute_en;
    reg pe_acc_clear;
    reg pe_drain;

    // Interconnect wires
    wire [7:0]  act_wire [0:7][0:8];
    wire [7:0]  wgt_wire [0:8][0:7];
    wire [31:0] pe_acc_out [0:7][0:7];
    wire        pe_acc_valid [0:7][0:7];

    genvar r, c;

    // Left activation boundary
    generate
        for (r = 0; r < 8; r = r + 1) begin : gen_act_boundary
            assign act_wire[r][0] = (state == S_COMPUTE && act_valid) ?
                                    act_data[r*8 +: 8] : 8'd0;
        end
    endgenerate

    // Top weight boundary
    generate
        for (c = 0; c < 8; c = c + 1) begin : gen_wgt_boundary
            assign wgt_wire[0][c] = (((state == S_LOAD) || (state == S_COMPUTE)) && wgt_valid) ?
                                    wgt_data[c*8 +: 8] : 8'd0;
        end
    endgenerate

    // PE grid
    generate
        for (r = 0; r < 8; r = r + 1) begin : gen_row
            for (c = 0; c < 8; c = c + 1) begin : gen_col
                systolic_pe pe_inst (
                    .clk         (clk),
                    .rst_n       (rst_n),
                    .a_in        (act_wire[r][c]),
                    .w_in        (wgt_wire[r][c]),
                    .a_out       (act_wire[r][c+1]),
                    .w_out       (wgt_wire[r+1][c]),
                    .acc_out     (pe_acc_out[r][c]),
                    .acc_valid   (pe_acc_valid[r][c]),
                    .weight_load (pe_weight_load),
                    .compute_en  (pe_compute_en),
                    .acc_clear   (pe_acc_clear),
                    .drain       (pe_drain)
                );
            end
        end
    endgenerate

    // State register and cycle counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            cycle_cnt <= 5'd0;
        end else begin
            state <= next_state;
            if (state != next_state)
                cycle_cnt <= 5'd0;
            else if (state != S_IDLE)
                cycle_cnt <= cycle_cnt + 5'd1;
            else
                cycle_cnt <= 5'd0;
        end
    end

    // Next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (start)
                    next_state = S_LOAD;
            end

            S_LOAD: begin
                if (cycle_cnt == 5'd7)
                    next_state = S_COMPUTE;
            end

            S_COMPUTE: begin
                if (cycle_cnt == COMPUTE_CYCLES_M1)
                    next_state = S_DRAIN;
            end

            S_DRAIN: begin
                if (cycle_cnt == 5'd7)
                    next_state = S_DONE;
            end

            S_DONE: begin
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // PE control
    always @(*) begin
        pe_weight_load = 1'b0;
        pe_compute_en  = 1'b0;
        pe_acc_clear   = 1'b0;
        pe_drain       = 1'b0;

        case (state)
            S_IDLE: begin
                if (start)
                    pe_acc_clear = 1'b1;
            end
            S_LOAD: begin
                pe_weight_load = 1'b1;
            end
            S_COMPUTE: begin
                pe_compute_en = 1'b1;
            end
            S_DRAIN: begin
                pe_drain = 1'b1;
            end
            default: ;
        endcase
    end

    assign busy = (state != S_IDLE) && (state != S_DONE);
    assign done = (state == S_DONE);

    // Result drain. Direct cycle-count based result column avoids the duplicate
    // first-column drain behavior in the original RTL.
    assign result_col   = (state == S_DRAIN) ? cycle_cnt[2:0] : 3'd0;
    assign result_valid = (state == S_DRAIN);

    generate
        for (r = 0; r < 8; r = r + 1) begin : gen_drain_mux
            assign result_data[r*32 +: 32] = pe_acc_out[r][result_col];
        end
    endgenerate

endmodule
