// ---------------------------------------------------------------------------
// ofdm_transceiver.v
//
// Loopback top tying the TX directly to the RX via an optional channel
// emulator hook. For synthesis we connect TX→RX directly (the channel hook
// is a passthrough); for simulation the testbench can inject a multi-tap
// FIR + AWGN between the two.
//
// This is the file you point Vivado at for synthesis when the goal is "fit
// the whole transceiver on the FPGA and report utilisation".
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module ofdm_transceiver #(
    parameter integer N_FFT       = 64,
    parameter integer N_CP        = 16,
    parameter integer N_DATA      = 50,
    parameter integer WIDTH       = 16,
    parameter integer SYMS_PER_FR = 8
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       mode,
    input  wire                       start_frame,
    // Bit input
    output wire                       bits_in_ready,
    input  wire                       bits_in_valid,
    input  wire [3:0]                 bits_in,
    // Recovered bit output
    output wire                       bits_out_valid,
    output wire [3:0]                 bits_out,
    output wire [2:0]                 nbits_out,
    output wire                       frame_done,
    output wire                       symbol_start    // debug
);
    wire                       tx_samp_valid;
    wire signed [WIDTH-1:0]    tx_samp_re, tx_samp_im;

    ofdm_tx_top #(
        .N_FFT(N_FFT), .N_CP(N_CP), .N_DATA(N_DATA), .WIDTH(WIDTH),
        .SYMS_PER_FR(SYMS_PER_FR)
    ) u_tx (
        .clk(clk), .rst_n(rst_n), .mode(mode),
        .start_frame(start_frame),
        .bits_ready(bits_in_ready),
        .bits_valid(bits_in_valid),
        .bits_in(bits_in),
        .samp_valid(tx_samp_valid),
        .samp_re(tx_samp_re), .samp_im(tx_samp_im),
        .frame_done(frame_done)
    );

    // Channel hook: passthrough in synthesis; the TB swaps this for a
    // multi-tap convolution + AWGN model.
    wire                       ch_valid = tx_samp_valid;
    wire signed [WIDTH-1:0]    ch_re    = tx_samp_re;
    wire signed [WIDTH-1:0]    ch_im    = tx_samp_im;

    ofdm_rx_top #(
        .N_FFT(N_FFT), .N_CP(N_CP), .WIDTH(WIDTH)
    ) u_rx (
        .clk(clk), .rst_n(rst_n), .mode(mode),
        .in_valid(ch_valid),
        .in_re(ch_re), .in_im(ch_im),
        .bits_valid(bits_out_valid),
        .bits_out(bits_out),
        .nbits_out(nbits_out),
        .symbol_start(symbol_start)
    );
endmodule

`default_nettype wire
