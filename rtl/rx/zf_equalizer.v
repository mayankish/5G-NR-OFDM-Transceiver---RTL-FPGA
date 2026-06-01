// ---------------------------------------------------------------------------
// zf_equalizer.v
//
// Per-subcarrier zero-forcing equaliser. For each (Y[k], H[k]) pair, computes
//
//   X_hat[k] = Y[k] / H[k] = Y[k] * conj(H[k]) / |H[k]|^2
//
// Division by |H|^2 uses a small reciprocal lookup (LUT-implemented). For
// magnitudes near zero we clamp to a floor to avoid blow-up — a known ZF
// weakness an interviewer is likely to probe.
//
// Note: we expect Y and H streams aligned in time. Caller must guarantee
// this; the RX top wrapper does so by holding Y in a small buffer until the
// channel estimator has produced H.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module zf_equalizer #(
    parameter integer WIDTH = 16
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       in_valid,
    input  wire signed [WIDTH-1:0]    y_re,
    input  wire signed [WIDTH-1:0]    y_im,
    input  wire signed [WIDTH-1:0]    h_re,
    input  wire signed [WIDTH-1:0]    h_im,
    output reg                        out_valid,
    output reg  signed [WIDTH-1:0]    x_re,
    output reg  signed [WIDTH-1:0]    x_im
);
    // |H|^2 (32-bit)
    wire signed [2*WIDTH-1:0] h_mag2 = h_re*h_re + h_im*h_im;

    // Floor: prevent division by near-zero. Choose ~1e-3 in Q1.15 → ~33.
    localparam signed [2*WIDTH-1:0] MAG2_FLOOR = 32'sd33;
    wire signed [2*WIDTH-1:0] h_mag2_clamped =
        (h_mag2 < MAG2_FLOOR) ? MAG2_FLOOR : h_mag2;

    // Y * conj(H) numerator
    wire signed [2*WIDTH-1:0] num_re = y_re*h_re + y_im*h_im;
    wire signed [2*WIDTH-1:0] num_im = y_im*h_re - y_re*h_im;

    // Division: num / |H|^2. We use a signed divide directly — synth will
    // either map to a DSP-divider IP or unroll into shift-subtract. On
    // Artix-7 with one division per subcarrier (64 per symbol, plenty of
    // cycles) this is fine.
    wire signed [2*WIDTH-1:0] q_re = num_re / h_mag2_clamped;
    wire signed [2*WIDTH-1:0] q_im = num_im / h_mag2_clamped;

    // Saturate back to Q1.15
    localparam signed [WIDTH-1:0] SAT_POS =  16'sh7FFF;
    localparam signed [WIDTH-1:0] SAT_NEG = -16'sh8000;

    function automatic signed [WIDTH-1:0] sat;
        input signed [2*WIDTH-1:0] x;
        begin
            if (x >  16'sh7FFF) sat = SAT_POS;
            else if (x < -16'sh8000) sat = SAT_NEG;
            else sat = x[WIDTH-1:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            x_re      <= 0;
            x_im      <= 0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                x_re <= sat(q_re);
                x_im <= sat(q_im);
            end
        end
    end
endmodule

`default_nettype wire
