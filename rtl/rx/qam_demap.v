// ---------------------------------------------------------------------------
// qam_demap.v
//
// Hard-decision QAM demapper, inverse of qam_mapper. For QPSK simply uses
// the sign bits. For 16-QAM slices each axis to one of {-3,-1,+1,+3} and
// returns the gray-coded bit pair.
//
// Output bit ordering matches qam_mapper (see qam_mapper.v header) so a
// loopback TX→RX produces the original bits modulo channel/quantisation.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module qam_demap #(
    parameter integer WIDTH = 16
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       mode,           // 0=QPSK, 1=16-QAM
    input  wire                       valid_in,
    input  wire signed [WIDTH-1:0]    sym_re,
    input  wire signed [WIDTH-1:0]    sym_im,
    output reg                        valid_out,
    output reg  [3:0]                 bits_out,       // low 2 bits used for QPSK
    output reg  [2:0]                 nbits_out       // 2 for QPSK, 4 for 16-QAM
);
    // 16-QAM slicer thresholds in Q1.15: ±2/sqrt(10) ≈ 0.632 → 0x50EA
    localparam signed [WIDTH-1:0] TH = 16'sh50EA;

    function automatic [1:0] gray_axis;
        input signed [WIDTH-1:0] s;
        begin
            if      (s >=  TH) gray_axis = 2'b10;   // +3
            else if (s >=  0 ) gray_axis = 2'b11;   // +1
            else if (s >= -TH) gray_axis = 2'b01;   // -1
            else               gray_axis = 2'b00;   // -3
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out  <= 1'b0;
            bits_out   <= 4'b0;
            nbits_out  <= 3'd0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                if (mode == 1'b0) begin
                    bits_out[0]  <= (sym_re < 0);
                    bits_out[1]  <= (sym_im < 0);
                    bits_out[3:2]<= 2'b00;
                    nbits_out    <= 3'd2;
                end else begin
                    bits_out[1:0] <= gray_axis(sym_re);
                    bits_out[3:2] <= gray_axis(sym_im);
                    nbits_out     <= 3'd4;
                end
            end
        end
    end
endmodule

`default_nettype wire
