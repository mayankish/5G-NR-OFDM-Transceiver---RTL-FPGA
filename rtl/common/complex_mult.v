// ---------------------------------------------------------------------------
// complex_mult.v
//
// Signed Q1.15 complex multiplier using the 3-multiplier Gauss trick:
//   (a + jb)(c + jd) = (ac - bd) + j(ad + bc)
//                    = [c(a+b) - b(c+d)] + j[c(a+b) + a(d-c)]
//
// Inputs:  16-bit Q1.15 signed
// Outputs: 16-bit Q1.15 signed (right-shifted by 15, with symmetric rounding)
//
// One register stage at the output for timing. Latency = 1 clock.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module complex_mult #(
    parameter integer WIDTH = 16,
    parameter integer FRAC  = 15
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire signed [WIDTH-1:0]    a_re,
    input  wire signed [WIDTH-1:0]    a_im,
    input  wire signed [WIDTH-1:0]    b_re,
    input  wire signed [WIDTH-1:0]    b_im,
    output reg  signed [WIDTH-1:0]    p_re,
    output reg  signed [WIDTH-1:0]    p_im
);
    // Full-precision intermediate products: WIDTH+1 + WIDTH = 2*WIDTH+1 bits.
    wire signed [2*WIDTH:0] s1 = $signed(a_re) + $signed(a_im);   // a+b
    wire signed [2*WIDTH:0] s2 = $signed(b_re) + $signed(b_im);   // c+d
    wire signed [2*WIDTH:0] s3 = $signed(b_im) - $signed(b_re);   // d-c

    wire signed [2*WIDTH+2:0] m1 = b_re * s1;                     // c(a+b)
    wire signed [2*WIDTH+2:0] m2 = a_im * s2;                     // b(c+d)
    wire signed [2*WIDTH+2:0] m3 = a_re * s3;                     // a(d-c)

    wire signed [2*WIDTH+3:0] sum_re_full = m1 - m2;              // ac - bd
    wire signed [2*WIDTH+3:0] sum_im_full = m1 + m3;              // ad + bc

    // Round-to-nearest (add 0.5 LSB before truncation) and saturate.
    localparam signed [WIDTH-1:0] SAT_POS =  {1'b0, {(WIDTH-1){1'b1}}};
    localparam signed [WIDTH-1:0] SAT_NEG =  {1'b1, {(WIDTH-1){1'b0}}};

    function automatic signed [WIDTH-1:0] sat_round;
        input signed [2*WIDTH+3:0] x;
        reg signed [2*WIDTH+3:0] rounded;
        begin
            rounded = x + (1 <<< (FRAC - 1));
            rounded = rounded >>> FRAC;
            if (rounded >  $signed({{(2*WIDTH+4-WIDTH){1'b0}}, SAT_POS}))
                sat_round = SAT_POS;
            else if (rounded < $signed({{(2*WIDTH+4-WIDTH){1'b1}}, SAT_NEG}))
                sat_round = SAT_NEG;
            else
                sat_round = rounded[WIDTH-1:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_re <= {WIDTH{1'b0}};
            p_im <= {WIDTH{1'b0}};
        end else begin
            p_re <= sat_round(sum_re_full);
            p_im <= sat_round(sum_im_full);
        end
    end
endmodule

`default_nettype wire
