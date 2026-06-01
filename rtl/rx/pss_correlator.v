// ---------------------------------------------------------------------------
// pss_correlator.v
//
// Time-domain sliding correlator against the known PSS (Zadoff-Chu u=25,
// L=63). Implementation uses a single complex MAC walking a 63-deep sample
// shift register. When |corr|^2 exceeds a threshold and is locally maximal,
// the symbol_start pulse fires.
//
// This is the simplest credible RX sync implementation — fine for SNR > ~5 dB
// in AWGN. Strengthening it (matched-filter + delayed-correlation hybrid,
// CFO-tolerant differential PSS) is a separate, larger project.
//
// Threshold is tuned empirically; expose it as a parameter so it can be
// retuned in synthesis without re-editing logic.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module pss_correlator #(
    parameter integer PSS_LEN     = 63,
    parameter integer WIDTH       = 16,
    parameter integer ACC_W       = 32,
    parameter [ACC_W*2-1:0] THRESH = {ACC_W{1'b0}, 16'h0800, 16'h0000} // |corr|^2 threshold
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       in_valid,
    input  wire signed [WIDTH-1:0]    in_re,
    input  wire signed [WIDTH-1:0]    in_im,
    output reg                        symbol_start
);
    // Reference PSS (conjugated for correlation): load from same .mem file
    // as the TX-side pss_gen. To correlate against PSS we use conj(PSS).
    reg signed [WIDTH-1:0] pss_re [0:PSS_LEN-1];
    reg signed [WIDTH-1:0] pss_im [0:PSS_LEN-1];
    initial begin
        $readmemh("pss_zc_u25_L63.mem",    pss_re, 0, PSS_LEN-1);
        $readmemh("pss_zc_u25_L63_im.mem", pss_im, 0, PSS_LEN-1);
    end

    // Sample shift register
    reg signed [WIDTH-1:0] sr_re [0:PSS_LEN-1];
    reg signed [WIDTH-1:0] sr_im [0:PSS_LEN-1];

    integer ii;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (ii = 0; ii < PSS_LEN; ii = ii + 1) begin
                sr_re[ii] <= 0;
                sr_im[ii] <= 0;
            end
        end else if (in_valid) begin
            for (ii = PSS_LEN-1; ii > 0; ii = ii - 1) begin
                sr_re[ii] <= sr_re[ii-1];
                sr_im[ii] <= sr_im[ii-1];
            end
            sr_re[0] <= in_re;
            sr_im[0] <= in_im;
        end
    end

    // Full sliding dot product. We do this combinationally for clarity; in
    // synthesis this maps to a tree of DSP slices. For tighter Fmax replace
    // with a pipelined accumulator that takes PSS_LEN cycles per output.
    integer k;
    reg signed [ACC_W-1:0] acc_re_full;
    reg signed [ACC_W-1:0] acc_im_full;
    always @(*) begin
        acc_re_full = 0;
        acc_im_full = 0;
        for (k = 0; k < PSS_LEN; k = k + 1) begin
            // sr[k] * conj(pss[k]) = (sr_re + j sr_im)(pss_re - j pss_im)
            //                     = (sr_re*pss_re + sr_im*pss_im)
            //                     + j(sr_im*pss_re - sr_re*pss_im)
            acc_re_full = acc_re_full + sr_re[k]*pss_re[k] + sr_im[k]*pss_im[k];
            acc_im_full = acc_im_full + sr_im[k]*pss_re[k] - sr_re[k]*pss_im[k];
        end
    end

    // Magnitude-squared (avoid the sqrt)
    wire [ACC_W*2-1:0] mag2 = acc_re_full*acc_re_full + acc_im_full*acc_im_full;

    // Peak detect: emit symbol_start when mag2 crosses threshold and is a
    // local maximum (one-sample look-back/forward via two-stage compare).
    reg [ACC_W*2-1:0] mag2_d1, mag2_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mag2_d1 <= 0;
            mag2_d2 <= 0;
            symbol_start <= 1'b0;
        end else begin
            mag2_d1 <= mag2;
            mag2_d2 <= mag2_d1;
            // peak at mag2_d1 if it's > both neighbours and over threshold
            symbol_start <= (mag2_d1 > THRESH) && (mag2_d1 > mag2_d2) && (mag2_d1 > mag2);
        end
    end
endmodule

`default_nettype wire
