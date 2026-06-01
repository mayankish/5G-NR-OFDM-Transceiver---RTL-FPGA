// ---------------------------------------------------------------------------
// fft64_engine.v
//
// 64-point radix-2 Decimation-In-Time FFT engine, shared by TX (IFFT) and RX
// (FFT). One stage's worth of butterflies is computed sequentially per clock
// — i.e. this is an in-place, memory-based architecture (not fully unrolled).
//
// Architecture summary
// --------------------
//   * Two BRAM-backed sample banks (ping-pong) hold the 64 complex samples.
//   * For each of the log2(64)=6 stages, the controller walks the butterfly
//     pairs (k1, k2), reads them from one bank, computes the butterfly with
//     one complex multiplier, writes results into the other bank.
//   * Twiddle factors come from twiddle_rom (N/2 = 32 entries).
//   * For IFFT mode, conjugate the twiddles on the way in and conjugate the
//     input/output (standard trick: IFFT{x} = (1/N) * conj(FFT{conj(x)})).
//
// Latency is approximately N/2 * log2(N) + a few cycles of pipelining =
// 32 * 6 + ~10 = ~200 cycles. Plenty of slack at 100 MHz for an 80-sample
// OFDM symbol (which arrives over 80 cycles at sample rate).
//
// Interface is a simple block-mode handshake:
//   start    : pulse to begin loading
//   in_valid : qualifies in_re/in_im on each of 64 sample writes
//   done     : pulse when bank holds the result
//   out_re/im, out_valid : streamed out on request after done
//
// NOTE: This is an *educational* sequential implementation. For a production
// 5G FFT you would use a streaming radix-2^2 SDF pipeline (e.g. Xilinx FFT
// IP) — but rolling our own here is the point: it demonstrates DSP-hardware
// fluency for the Qualcomm interview.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module fft64_engine #(
    parameter integer N      = 64,
    parameter integer LOG2N  = 6,
    parameter integer WIDTH  = 16
) (
    input  wire                       clk,
    input  wire                       rst_n,

    input  wire                       inverse,        // 1 = IFFT, 0 = FFT
    input  wire                       start,          // pulse to begin

    // Input stream: 64 complex samples in natural order
    input  wire                       in_valid,
    input  wire signed [WIDTH-1:0]    in_re,
    input  wire signed [WIDTH-1:0]    in_im,
    output reg                        in_ready,

    // Output stream: 64 complex samples in natural order
    output reg                        out_valid,
    output reg  signed [WIDTH-1:0]    out_re,
    output reg  signed [WIDTH-1:0]    out_im,

    output reg                        done
);
    // -----------------------------------------------------------------------
    // Sample memory: two banks, ping-pong between stages
    // -----------------------------------------------------------------------
    reg signed [WIDTH-1:0] bank_re [0:1][0:N-1];
    reg signed [WIDTH-1:0] bank_im [0:1][0:N-1];
    reg                    rd_bank;                    // which bank is "read"

    // -----------------------------------------------------------------------
    // Bit reversal — DIT requires bit-reversed input order. We accept the
    // input in natural order and write it bit-reversed into the bank.
    // -----------------------------------------------------------------------
    function automatic [LOG2N-1:0] bitrev;
        input [LOG2N-1:0] x;
        integer i;
        begin
            bitrev = 0;
            for (i = 0; i < LOG2N; i = i + 1)
                bitrev[i] = x[LOG2N-1-i];
        end
    endfunction

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    localparam S_IDLE   = 3'd0;
    localparam S_LOAD   = 3'd1;
    localparam S_STAGE  = 3'd2;
    localparam S_NEXTST = 3'd3;
    localparam S_UNLOAD = 3'd4;
    localparam S_DONE   = 3'd5;

    reg [2:0] state;
    reg [LOG2N-1:0] load_cnt;
    reg [LOG2N-1:0] unload_cnt;
    reg [2:0]       stage;                            // 0..LOG2N-1
    reg [LOG2N-1:0] bf_cnt;                           // butterfly within stage

    // For each stage, butterfly pair separation is (N >> (stage+1)) for DIT?
    // We use DIT: pairs at distance 2^stage. Group size = 2^(stage+1).
    wire [LOG2N-1:0] pair_dist  = (1 << stage);
    wire [LOG2N-1:0] grp_size   = (1 << (stage + 1));

    // Index of butterfly 'bf_cnt' within the data array.
    // For DIT we sweep all butterflies. Each butterfly touches indices (k, k+pair_dist)
    // where k = group_base + within_group, within_group ∈ [0, pair_dist).
    wire [LOG2N-1:0] within_group = bf_cnt & (pair_dist - 1);
    wire [LOG2N-1:0] group_idx    = bf_cnt >> stage;
    wire [LOG2N-1:0] k1           = (group_idx << (stage + 1)) | within_group;
    wire [LOG2N-1:0] k2           = k1 | pair_dist;

    // Twiddle index for this butterfly: within_group * (N / grp_size)
    wire [LOG2N-1:0] tw_index    = within_group * (N / grp_size);
    wire [LOG2N-2:0] tw_addr     = tw_index[LOG2N-2:0];   // 5 bits = 32 entries

    // Twiddle ROM
    wire signed [WIDTH-1:0] w_re_rom, w_im_rom;
    twiddle_rom #(.N(N), .WIDTH(WIDTH)) u_tw (
        .addr(tw_addr),
        .w_re(w_re_rom),
        .w_im(w_im_rom)
    );

    // For IFFT: use conjugate of twiddles, and conjugate input on load / output on unload.
    wire signed [WIDTH-1:0] w_re = w_re_rom;
    wire signed [WIDTH-1:0] w_im = inverse ? -w_im_rom : w_im_rom;

    // Butterfly: t = W * x[k2]; y[k1] = x[k1] + t; y[k2] = x[k1] - t;
    wire signed [WIDTH-1:0] x1_re = bank_re[rd_bank][k1];
    wire signed [WIDTH-1:0] x1_im = bank_im[rd_bank][k1];
    wire signed [WIDTH-1:0] x2_re = bank_re[rd_bank][k2];
    wire signed [WIDTH-1:0] x2_im = bank_im[rd_bank][k2];

    wire signed [WIDTH-1:0] t_re, t_im;
    complex_mult #(.WIDTH(WIDTH), .FRAC(WIDTH-1)) u_mul (
        .clk(clk), .rst_n(rst_n),
        .a_re(x2_re), .a_im(x2_im),
        .b_re(w_re),  .b_im(w_im),
        .p_re(t_re),  .p_im(t_im)
    );

    // Pipeline: butterfly result is available one clock after the operands
    // are presented. We delay the k1/k2/x1 by one stage to align.
    reg signed [WIDTH-1:0] x1_re_d, x1_im_d;
    reg [LOG2N-1:0] k1_d, k2_d;
    reg do_write_d;

    always @(posedge clk) begin
        x1_re_d   <= x1_re;
        x1_im_d   <= x1_im;
        k1_d      <= k1;
        k2_d      <= k2;
        do_write_d<= (state == S_STAGE);
    end

    // Butterfly outputs (with bit growth controlled by saturation in the mult).
    wire signed [WIDTH:0] y1_re_full = $signed({x1_re_d[WIDTH-1], x1_re_d}) + $signed({t_re[WIDTH-1], t_re});
    wire signed [WIDTH:0] y1_im_full = $signed({x1_im_d[WIDTH-1], x1_im_d}) + $signed({t_im[WIDTH-1], t_im});
    wire signed [WIDTH:0] y2_re_full = $signed({x1_re_d[WIDTH-1], x1_re_d}) - $signed({t_re[WIDTH-1], t_re});
    wire signed [WIDTH:0] y2_im_full = $signed({x1_im_d[WIDTH-1], x1_im_d}) - $signed({t_im[WIDTH-1], t_im});

    // Scale by /2 per stage to prevent overflow growth across LOG2N stages.
    wire signed [WIDTH-1:0] y1_re = y1_re_full[WIDTH:1];
    wire signed [WIDTH-1:0] y1_im = y1_im_full[WIDTH:1];
    wire signed [WIDTH-1:0] y2_re = y2_re_full[WIDTH:1];
    wire signed [WIDTH-1:0] y2_im = y2_im_full[WIDTH:1];

    // -----------------------------------------------------------------------
    // FSM logic
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            load_cnt   <= 0;
            unload_cnt <= 0;
            stage      <= 0;
            bf_cnt     <= 0;
            rd_bank    <= 1'b0;
            in_ready   <= 1'b0;
            out_valid  <= 1'b0;
            done       <= 1'b0;
        end else begin
            done      <= 1'b0;
            out_valid <= 1'b0;
            case (state)
            // -----------------------------------------------------------
            S_IDLE: begin
                in_ready <= 1'b0;
                if (start) begin
                    state    <= S_LOAD;
                    load_cnt <= 0;
                    in_ready <= 1'b1;
                    rd_bank  <= 1'b0;
                end
            end
            // -----------------------------------------------------------
            S_LOAD: begin
                if (in_valid) begin
                    // Write input into bank 0 in bit-reversed order.
                    bank_re[0][bitrev(load_cnt)] <= inverse ?  in_re : in_re;
                    bank_im[0][bitrev(load_cnt)] <= inverse ? -in_im : in_im;   // IFFT trick
                    load_cnt <= load_cnt + 1;
                    if (load_cnt == N - 1) begin
                        in_ready <= 1'b0;
                        state    <= S_STAGE;
                        stage    <= 0;
                        bf_cnt   <= 0;
                    end
                end
            end
            // -----------------------------------------------------------
            S_STAGE: begin
                // Operands are presented combinationally via k1/k2.
                // The butterfly output appears one cycle later (do_write_d).
                bf_cnt <= bf_cnt + 1;
                if (bf_cnt == (N/2) - 1)
                    state <= S_NEXTST;
            end
            // -----------------------------------------------------------
            S_NEXTST: begin
                // Wait one cycle for last butterfly write to complete, then
                // flip banks and either start next stage or unload.
                rd_bank <= ~rd_bank;
                bf_cnt  <= 0;
                if (stage == LOG2N - 1) begin
                    state      <= S_UNLOAD;
                    unload_cnt <= 0;
                end else begin
                    stage <= stage + 1;
                    state <= S_STAGE;
                end
            end
            // -----------------------------------------------------------
            S_UNLOAD: begin
                out_valid <= 1'b1;
                out_re    <= bank_re[rd_bank][unload_cnt];
                out_im    <= inverse ? -bank_im[rd_bank][unload_cnt]
                                      :  bank_im[rd_bank][unload_cnt];
                unload_cnt <= unload_cnt + 1;
                if (unload_cnt == N - 1) begin
                    state <= S_DONE;
                end
            end
            // -----------------------------------------------------------
            S_DONE: begin
                done  <= 1'b1;
                state <= S_IDLE;
            end
            endcase

            // -----------------------------------------------------------
            // Bank write-back: butterfly results land in the *other* bank.
            // -----------------------------------------------------------
            if (do_write_d) begin
                bank_re[~rd_bank][k1_d] <= y1_re;
                bank_im[~rd_bank][k1_d] <= y1_im;
                bank_re[~rd_bank][k2_d] <= y2_re;
                bank_im[~rd_bank][k2_d] <= y2_im;
            end
        end
    end
endmodule

`default_nettype wire
