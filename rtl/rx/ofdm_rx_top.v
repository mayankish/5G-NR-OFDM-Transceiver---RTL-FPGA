// ---------------------------------------------------------------------------
// ofdm_rx_top.v
//
// OFDM receiver top: chains pss_correlator → cp_remove → fft64_engine (FFT
// mode) → chan_est_ls → zf_equalizer → qam_demap.
//
// The Y bins are also buffered for one pass so they can be re-streamed
// alongside the H estimates into the equaliser (since chan_est_ls needs the
// whole symbol's worth of FFT bins before it can produce H at any subcarrier).
//
// This top assumes a single-symbol pipeline; multi-symbol operation works by
// re-arming on each symbol_start (the correlator pulses once per detected
// PSS in a real frame, and on per-symbol-edge if you swap the correlator for
// a CP-autocorrelator). For the project demo we time-align at PSS once and
// then rely on counter-based symbol boundaries — the RX top wrapper that
// drives a full frame is in rtl/top/ofdm_transceiver.v.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module ofdm_rx_top #(
    parameter integer N_FFT   = 64,
    parameter integer N_CP    = 16,
    parameter integer N_PILOT = 8,
    parameter integer WIDTH   = 16
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       mode,           // 0=QPSK, 1=16-QAM
    input  wire                       in_valid,
    input  wire signed [WIDTH-1:0]    in_re,
    input  wire signed [WIDTH-1:0]    in_im,
    output wire                       bits_valid,
    output wire [3:0]                 bits_out,
    output wire [2:0]                 nbits_out,
    output wire                       symbol_start    // exposed for debug
);
    // --- PSS correlator
    wire sym_start;
    pss_correlator #(.PSS_LEN(63), .WIDTH(WIDTH)) u_corr (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid),
        .in_re(in_re), .in_im(in_im),
        .symbol_start(sym_start)
    );
    assign symbol_start = sym_start;

    // --- CP remove
    wire                       cpr_valid;
    wire signed [WIDTH-1:0]    cpr_re, cpr_im;
    cp_remove #(.N_FFT(N_FFT), .N_CP(N_CP), .WIDTH(WIDTH)) u_cpr (
        .clk(clk), .rst_n(rst_n),
        .symbol_start(sym_start),
        .in_valid(in_valid),
        .in_re(in_re), .in_im(in_im),
        .out_valid(cpr_valid),
        .out_re(cpr_re), .out_im(cpr_im)
    );

    // --- FFT
    reg fft_start;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) fft_start <= 0;
        else        fft_start <= sym_start;          // kick off when symbol begins
    end

    wire                       fft_in_ready;
    wire                       fft_out_valid;
    wire signed [WIDTH-1:0]    fft_out_re, fft_out_im;
    wire                       fft_done;
    fft64_engine #(.N(N_FFT), .LOG2N(6), .WIDTH(WIDTH)) u_fft (
        .clk(clk), .rst_n(rst_n),
        .inverse(1'b0),
        .start(fft_start),
        .in_valid(cpr_valid),
        .in_re(cpr_re), .in_im(cpr_im),
        .in_ready(fft_in_ready),
        .out_valid(fft_out_valid),
        .out_re(fft_out_re), .out_im(fft_out_im),
        .done(fft_done)
    );

    // --- Buffer Y bins so we can replay them alongside H
    reg signed [WIDTH-1:0] y_buf_re [0:N_FFT-1];
    reg signed [WIDTH-1:0] y_buf_im [0:N_FFT-1];
    reg [$clog2(N_FFT):0] y_wr_idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) y_wr_idx <= 0;
        else if (fft_start) y_wr_idx <= 0;
        else if (fft_out_valid) begin
            y_buf_re[y_wr_idx] <= fft_out_re;
            y_buf_im[y_wr_idx] <= fft_out_im;
            y_wr_idx <= y_wr_idx + 1;
        end
    end

    // --- Channel estimator
    wire                       h_valid;
    wire signed [WIDTH-1:0]    h_re, h_im;
    wire                       h_done;
    chan_est_ls #(.N(N_FFT), .N_PILOT(N_PILOT), .WIDTH(WIDTH)) u_ce (
        .clk(clk), .rst_n(rst_n),
        .fft_valid(fft_out_valid),
        .fft_re(fft_out_re), .fft_im(fft_out_im),
        .fft_done(fft_done),
        .h_valid(h_valid),
        .h_re(h_re), .h_im(h_im),
        .h_done(h_done)
    );

    // --- Replay Y in lockstep with H stream
    reg [$clog2(N_FFT):0] y_rd_idx;
    reg                   eq_in_valid;
    reg signed [WIDTH-1:0] y_eq_re, y_eq_im;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_rd_idx    <= 0;
            eq_in_valid <= 0;
        end else if (h_valid) begin
            y_eq_re     <= y_buf_re[y_rd_idx];
            y_eq_im     <= y_buf_im[y_rd_idx];
            eq_in_valid <= 1'b1;
            y_rd_idx    <= y_rd_idx + 1;
        end else begin
            eq_in_valid <= 1'b0;
            if (h_done) y_rd_idx <= 0;
        end
    end

    // --- Equaliser
    wire                       eq_out_valid;
    wire signed [WIDTH-1:0]    eq_re, eq_im;
    zf_equalizer #(.WIDTH(WIDTH)) u_eq (
        .clk(clk), .rst_n(rst_n),
        .in_valid(eq_in_valid),
        .y_re(y_eq_re), .y_im(y_eq_im),
        .h_re(h_re),     .h_im(h_im),
        .out_valid(eq_out_valid),
        .x_re(eq_re),    .x_im(eq_im)
    );

    // --- Pilot/guard mask: only data carriers feed the demap
    reg is_data [0:N_FFT-1];
    integer i;
    initial begin
        for (i = 0; i < N_FFT; i = i + 1) is_data[i] = 1'b1;
        // guard
        is_data[ 0] = 0; is_data[ 1] = 0; is_data[ 2] = 0;
        is_data[32] = 0;
        is_data[62] = 0; is_data[63] = 0;
        // pilots
        is_data[ 3] = 0; is_data[11] = 0; is_data[19] = 0; is_data[27] = 0;
        is_data[36] = 0; is_data[44] = 0; is_data[52] = 0; is_data[60] = 0;
    end

    reg [$clog2(N_FFT):0] eq_k;
    reg                   demap_in_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eq_k <= 0;
            demap_in_valid <= 0;
        end else begin
            demap_in_valid <= 1'b0;
            if (eq_out_valid) begin
                demap_in_valid <= is_data[eq_k];
                eq_k <= (eq_k == N_FFT-1) ? 0 : (eq_k + 1);
            end
        end
    end

    qam_demap #(.WIDTH(WIDTH)) u_demap (
        .clk(clk), .rst_n(rst_n), .mode(mode),
        .valid_in(demap_in_valid),
        .sym_re(eq_re), .sym_im(eq_im),
        .valid_out(bits_valid),
        .bits_out(bits_out),
        .nbits_out(nbits_out)
    );
endmodule

`default_nettype wire
