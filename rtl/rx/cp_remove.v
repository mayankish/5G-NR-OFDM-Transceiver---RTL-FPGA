// ---------------------------------------------------------------------------
// cp_remove.v
//
// Cyclic Prefix removal. After symbol_start asserts (from pss_correlator),
// we wait for one full symbol to land, then drop the first N_CP samples and
// pass the remaining N_FFT samples through to the FFT.
//
// Operates per-symbol: re-armed at the start of every OFDM symbol. Position
// counter is reset on symbol_start so any drift after sync is bounded to
// the CP length.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module cp_remove #(
    parameter integer N_FFT = 64,
    parameter integer N_CP  = 16,
    parameter integer WIDTH = 16
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       symbol_start,
    input  wire                       in_valid,
    input  wire signed [WIDTH-1:0]    in_re,
    input  wire signed [WIDTH-1:0]    in_im,
    output reg                        out_valid,
    output reg  signed [WIDTH-1:0]    out_re,
    output reg  signed [WIDTH-1:0]    out_im
);
    reg [$clog2(N_FFT+N_CP):0] pos;
    reg                        armed;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pos       <= 0;
            armed     <= 1'b0;
            out_valid <= 1'b0;
            out_re    <= 0;
            out_im    <= 0;
        end else begin
            out_valid <= 1'b0;
            if (symbol_start) begin
                pos   <= 0;
                armed <= 1'b1;
            end else if (armed && in_valid) begin
                if (pos >= N_CP && pos < N_CP + N_FFT) begin
                    out_re    <= in_re;
                    out_im    <= in_im;
                    out_valid <= 1'b1;
                end
                if (pos == N_CP + N_FFT - 1) begin
                    armed <= 1'b0;
                end
                pos <= pos + 1;
            end
        end
    end
endmodule

`default_nettype wire
