// ============================================================================
// Pipelined Processing Element (PE) -- INT8 Systolic Array
//
// Project : High-Performance Pipelined INT8 Systolic-Array AI Accelerator
// Purpose : Break the original multiplier+adder critical path by inserting a
//           pipeline register at the multiplier output.
//
// Data flow:
//   - Activations flow left -> right through a registered output.
//   - Weights flow top -> bottom through a registered output.
//   - The MAC datapath is split into two sequential stages:
//       Stage 1: signed INT8 x INT8 multiplication -> product_pipe
//       Stage 2: sign extension + 32-bit saturated accumulation
//
// Note:
//   The MAC uses streaming weights (w_in) during COMPUTE. The weight_load path
//   is retained for compatibility with the top-level controller and for passing
//   pre-load data down the array, but the compute datapath is output-stationary
//   with streaming weights.
// ============================================================================

`timescale 1ns/1ps

module systolic_pe (
    input  wire        clk,
    input  wire        rst_n,

    // Data inputs
    input  wire [7:0]  a_in,        // activation from left, signed INT8
    input  wire [7:0]  w_in,        // weight from top, signed INT8

    // Data outputs
    output reg  [7:0]  a_out,       // activation to right
    output reg  [7:0]  w_out,       // weight to bottom

    // Accumulator output
    output wire [31:0] acc_out,
    output reg         acc_valid,

    // Control
    input  wire        weight_load, // forward/load weight stream
    input  wire        compute_en,  // enable MAC pipeline
    input  wire        acc_clear,   // clear accumulator and MAC pipeline
    input  wire        drain        // output-valid marker during drain
);

    // --------------------------------------------------------------------
    // Optional retained weight register. This is not used in the streaming
    // MAC datapath, but it is useful for debug and keeps compatibility with
    // the original PE structure.
    // --------------------------------------------------------------------
    reg [7:0] weight_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            weight_reg <= 8'd0;
        else if (weight_load)
            weight_reg <= w_in;
    end

    // --------------------------------------------------------------------
    // Systolic data forwarding registers
    // --------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            a_out <= 8'd0;
        else if (compute_en)
            a_out <= a_in;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            w_out <= 8'd0;
        else if (weight_load || compute_en)
            w_out <= w_in;
    end

    // --------------------------------------------------------------------
    // Stage 1: registered INT8 multiplier output
    // This is the key high-performance modification. The baseline PE had the
    // multiplier and accumulator adder in one cycle; here they are separated.
    // --------------------------------------------------------------------
    wire signed [7:0]  a_signed     = $signed(a_in);
    wire signed [7:0]  w_signed     = $signed(w_in);
    wire signed [15:0] product_comb = a_signed * w_signed;

    reg signed [15:0] product_pipe;
    reg               product_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_pipe  <= 16'sd0;
            product_valid <= 1'b0;
        end else if (acc_clear) begin
            product_pipe  <= 16'sd0;
            product_valid <= 1'b0;
        end else begin
            if (compute_en)
                product_pipe <= product_comb;
            else
                product_pipe <= 16'sd0;

            product_valid <= compute_en;
        end
    end

    // --------------------------------------------------------------------
    // Stage 2: 32-bit saturated accumulator
    // --------------------------------------------------------------------
    reg signed [31:0] accumulator;

    wire signed [31:0] product_ext  = {{16{product_pipe[15]}}, product_pipe};
    wire signed [32:0] sum_extended = {accumulator[31], accumulator} +
                                      {product_ext[31], product_ext};

    // 33-bit result should be a sign-extension of bit[31]. If not, overflow.
    wire overflow_pos = (sum_extended[32:31] == 2'b01);
    wire overflow_neg = (sum_extended[32:31] == 2'b10);

    wire signed [31:0] sum_saturated = overflow_pos ? 32'sh7FFF_FFFF :
                                       overflow_neg ? 32'sh8000_0000 :
                                                      sum_extended[31:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            accumulator <= 32'sd0;
        else if (acc_clear)
            accumulator <= 32'sd0;
        else if (product_valid)
            accumulator <= sum_saturated;
    end

    assign acc_out = accumulator;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc_valid <= 1'b0;
        else
            acc_valid <= drain;
    end

endmodule
