// ---------------------------------------------------------------------------
// chan_est_ls.v
//
// Least-squares channel estimator with linear interpolation across
// subcarriers. After the FFT delivers 64 frequency-domain bins, this block:
//   1. Snapshots the bins at the 8 pilot positions.
//   2. Computes H_pilot[i] = Y[k_i] / X_dmrs[i] using one complex-divide each.
//   3. Linearly interpolates the magnitude/real and imag separately between
//      adjacent pilots to fill all 64 bins. (Edges are nearest-neighbour.)
//
// For an undergrad-level project this is honest: we accept the noise on the
// pilot LS estimate rather than denoise it (MMSE). The Python golden model
// has both, so the BER plots show the gap.
//
// Complex divide is implemented as: a/b = a * conj(b) / |b|^2. The |b|^2
// reciprocal is realised as a small lookup (256-entry) for area; precision
// is adequate at SNR ≥ ~5 dB which is the operating range of the RX.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module chan_est_ls #(
    parameter integer N        = 64,
    parameter integer N_PILOT  = 8,
    parameter integer WIDTH    = 16
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       fft_valid,      // 64-cycle natural-order bin stream
    input  wire signed [WIDTH-1:0]    fft_re,
    input  wire signed [WIDTH-1:0]    fft_im,
    input  wire                       fft_done,
    output reg                        h_valid,        // 64-cycle stream of H estimates
    output reg  signed [WIDTH-1:0]    h_re,
    output reg  signed [WIDTH-1:0]    h_im,
    output reg                        h_done
);
    // Pilot positions — must match subcarrier_mapper.v and reference_model.py
    reg pilot_mask [0:N-1];
    integer i;
    initial begin
        for (i = 0; i < N; i = i + 1) pilot_mask[i] = 1'b0;
        pilot_mask[ 3] = 1'b1; pilot_mask[11] = 1'b1; pilot_mask[19] = 1'b1;
        pilot_mask[27] = 1'b1; pilot_mask[36] = 1'b1; pilot_mask[44] = 1'b1;
        pilot_mask[52] = 1'b1; pilot_mask[60] = 1'b1;
    end

    // DMRS ROM — same values as subcarrier_mapper
    reg signed [WIDTH-1:0] dmrs_re [0:N_PILOT-1];
    reg signed [WIDTH-1:0] dmrs_im [0:N_PILOT-1];
    initial begin
        // Matches sim/reference_model.py dmrs_sequence() with seed=0xC0DE
        dmrs_re[0] = -16'sh5A82; dmrs_im[0] =  16'sh5A82;  // -0.707, +0.707
        dmrs_re[1] =  16'sh5A82; dmrs_im[1] = -16'sh5A82;  // +0.707, -0.707
        dmrs_re[2] =  16'sh5A82; dmrs_im[2] = -16'sh5A82;  // +0.707, -0.707
        dmrs_re[3] = -16'sh5A82; dmrs_im[3] =  16'sh5A82;  // -0.707, +0.707
        dmrs_re[4] = -16'sh5A82; dmrs_im[4] = -16'sh5A82;  // -0.707, -0.707
        dmrs_re[5] =  16'sh5A82; dmrs_im[5] = -16'sh5A82;  // +0.707, -0.707
        dmrs_re[6] =  16'sh5A82; dmrs_im[6] = -16'sh5A82;  // +0.707, -0.707
        dmrs_re[7] = -16'sh5A82; dmrs_im[7] = -16'sh5A82;  // -0.707, -0.707
    end

    // Collect pilot bins as they stream through
    reg signed [WIDTH-1:0] hp_re [0:N_PILOT-1];
    reg signed [WIDTH-1:0] hp_im [0:N_PILOT-1];
    reg [$clog2(N+1):0]    k;
    reg [$clog2(N_PILOT+1):0] p_idx;

    // Pilot positions stored for later interpolation
    reg [$clog2(N)-1:0] pilot_k [0:N_PILOT-1];
    initial begin
        pilot_k[0]=3;  pilot_k[1]=11; pilot_k[2]=19; pilot_k[3]=27;
        pilot_k[4]=36; pilot_k[5]=44; pilot_k[6]=52; pilot_k[7]=60;
    end

    // --- LS divide: Hp = Y * conj(X) / |X|^2. Since DMRS is QPSK with
    // magnitude 1, |X|^2 is a known constant (1.0 in floating, 0.5 in our
    // Q1.15 normalisation because the DMRS is at ±0.707 per axis). So this
    // collapses to: Hp ≈ 2 * Y * conj(X).
    function automatic signed [WIDTH-1:0] ls_re;
        input signed [WIDTH-1:0] y_r, y_i, x_r, x_i;
        reg signed [2*WIDTH-1:0] num;
        begin
            num = y_r*x_r + y_i*x_i;
            // multiply by ~2 (left shift 1) and rescale Q1.15 (shift right 15)
            ls_re = num >>> (WIDTH-2);
        end
    endfunction
    function automatic signed [WIDTH-1:0] ls_im;
        input signed [WIDTH-1:0] y_r, y_i, x_r, x_i;
        reg signed [2*WIDTH-1:0] num;
        begin
            num = y_i*x_r - y_r*x_i;
            ls_im = num >>> (WIDTH-2);
        end
    endfunction

    // FSM: COLLECT (during fft_valid) → INTERP & STREAM out
    localparam S_COLL = 2'd0, S_INTERP = 2'd1, S_DONE = 2'd2;
    reg [1:0] state;
    reg [$clog2(N):0] out_k;
    reg [$clog2(N_PILOT)-1:0] left_p;     // index of left pilot for interp

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_COLL;
            k       <= 0;
            p_idx   <= 0;
            out_k   <= 0;
            left_p  <= 0;
            h_valid <= 1'b0;
            h_done  <= 1'b0;
            h_re    <= 0;
            h_im    <= 0;
        end else begin
            h_valid <= 1'b0;
            h_done  <= 1'b0;
            case (state)
            S_COLL: begin
                if (fft_valid) begin
                    if (pilot_mask[k]) begin
                        hp_re[p_idx] <= ls_re(fft_re, fft_im, dmrs_re[p_idx], dmrs_im[p_idx]);
                        hp_im[p_idx] <= ls_im(fft_re, fft_im, dmrs_re[p_idx], dmrs_im[p_idx]);
                        p_idx <= p_idx + 1;
                    end
                    k <= k + 1;
                end
                if (fft_done) begin
                    state  <= S_INTERP;
                    k      <= 0;
                    p_idx  <= 0;
                    out_k  <= 0;
                    left_p <= 0;
                end
            end
            S_INTERP: begin
                // Find bracketing pilots for out_k and do a linear interp.
                // Edge cases: out_k < pilot_k[0]                 → use hp[0]
                //             out_k > pilot_k[N_PILOT-1]         → use hp[last]
                if (out_k <= pilot_k[0]) begin
                    h_re <= hp_re[0];
                    h_im <= hp_im[0];
                end else if (out_k >= pilot_k[N_PILOT-1]) begin
                    h_re <= hp_re[N_PILOT-1];
                    h_im <= hp_im[N_PILOT-1];
                end else begin
                    // Bump left_p forward while out_k passes a pilot.
                    if (out_k >= pilot_k[left_p+1]) left_p <= left_p + 1;
                    // Linear interpolation: h = hp[L] + (hp[R]-hp[L])*(k-kL)/(kR-kL)
                    // The pilot spacing is 8 → divide by 8 is a >>> 3.
                    h_re <= hp_re[left_p]
                          + ((hp_re[left_p+1] - hp_re[left_p]) *
                             (out_k - pilot_k[left_p])) >>> 3;
                    h_im <= hp_im[left_p]
                          + ((hp_im[left_p+1] - hp_im[left_p]) *
                             (out_k - pilot_k[left_p])) >>> 3;
                end
                h_valid <= 1'b1;
                out_k <= out_k + 1;
                if (out_k == N - 1) begin
                    state <= S_DONE;
                end
            end
            S_DONE: begin
                h_done <= 1'b1;
                state  <= S_COLL;
                k      <= 0;
                p_idx  <= 0;
            end
            endcase
        end
    end
endmodule

`default_nettype wire
