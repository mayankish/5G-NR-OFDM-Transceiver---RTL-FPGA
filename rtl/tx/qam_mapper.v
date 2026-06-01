// ---------------------------------------------------------------------------
// qam_mapper.v
//
// Gray-coded QPSK and 16-QAM mapper. One symbol per cycle when valid_in
// asserted. Constant scaling chosen so each constellation has unit average
// energy (Q1.15 representation of 1/sqrt(2) for QPSK, 1/sqrt(10) for 16-QAM).
//
//   QPSK:    2 bits in → 1 symbol  (b0=I sign, b1=Q sign)
//   16-QAM:  4 bits in → 1 symbol  (b0 b1 = I gray, b2 b3 = Q gray)
//
// mode: 1'b0 = QPSK, 1'b1 = 16-QAM
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module qam_mapper #(
    parameter integer WIDTH = 16
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       mode,           // 0=QPSK, 1=16-QAM
    input  wire                       valid_in,
    input  wire [3:0]                 bits_in,        // up to 4 bits, low bits used for QPSK
    output reg                        valid_out,
    output reg  signed [WIDTH-1:0]    sym_re,
    output reg  signed [WIDTH-1:0]    sym_im
);
    // Q1.15 magnitudes
    localparam signed [WIDTH-1:0] Q15_1_SQRT2  = 16'sh5A82;  //  0.70710678
    localparam signed [WIDTH-1:0] Q15_NEG_1_S2 = -16'sh5A82;

    localparam signed [WIDTH-1:0] Q15_1_SQRT10 = 16'sh2879;  //  0.31622776
    localparam signed [WIDTH-1:0] Q15_3_SQRT10 = 16'sh796D;  //  0.94868330
    localparam signed [WIDTH-1:0] Q15_NEG_1_S10= -16'sh2879;
    localparam signed [WIDTH-1:0] Q15_NEG_3_S10= -16'sh796D;

    // Gray map: 00→-3, 01→-1, 11→+1, 10→+3 (per axis, 16-QAM)
    function automatic signed [WIDTH-1:0] qam16_axis;
        input [1:0] g;
        begin
            case (g)
                2'b00: qam16_axis = Q15_NEG_3_S10;
                2'b01: qam16_axis = Q15_NEG_1_S10;
                2'b11: qam16_axis = Q15_1_SQRT10;
                2'b10: qam16_axis = Q15_3_SQRT10;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            sym_re    <= 0;
            sym_im    <= 0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                if (mode == 1'b0) begin
                    // QPSK: bit0=I sign (1→neg), bit1=Q sign
                    sym_re <= bits_in[0] ? Q15_NEG_1_S2 : Q15_1_SQRT2;
                    sym_im <= bits_in[1] ? Q15_NEG_1_S2 : Q15_1_SQRT2;
                end else begin
                    // 16-QAM: bits[1:0] = I gray, bits[3:2] = Q gray
                    sym_re <= qam16_axis(bits_in[1:0]);
                    sym_im <= qam16_axis(bits_in[3:2]);
                end
            end
        end
    end
endmodule

`default_nettype wire
