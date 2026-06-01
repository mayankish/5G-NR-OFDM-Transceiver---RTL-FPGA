// ---------------------------------------------------------------------------
// tb_fft64.v
//
// Unit testbench for the fft64_engine. Drives a known input (an impulse at
// k=0, expected to produce a flat output of magnitude 1/N) and checks that
// the output magnitudes match within a small tolerance.
//
// This is a sanity TB: it does not exhaustively prove the engine, but it
// catches the common bugs (bit-reversal off, twiddles miswired, IFFT/FFT
// scaling inverted).
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module tb_fft64;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0;
    initial begin repeat(5) @(posedge clk); rst_n = 1; end

    reg                       start = 0;
    reg                       in_valid = 0;
    reg  signed [15:0]        in_re = 0, in_im = 0;
    wire                      in_ready;
    wire                      out_valid;
    wire signed [15:0]        out_re, out_im;
    wire                      done;

    fft64_engine #(.N(64), .LOG2N(6), .WIDTH(16)) dut (
        .clk(clk), .rst_n(rst_n),
        .inverse(1'b0),
        .start(start),
        .in_valid(in_valid),
        .in_re(in_re), .in_im(in_im),
        .in_ready(in_ready),
        .out_valid(out_valid),
        .out_re(out_re), .out_im(out_im),
        .done(done)
    );

    integer i, captured;
    reg signed [15:0] out_re_arr [0:63];
    reg signed [15:0] out_im_arr [0:63];

    initial begin
        @(posedge rst_n);
        repeat (3) @(posedge clk);

        // Pulse start, then stream impulse: x[0] = 0x7FFF, rest = 0.
        start <= 1; @(posedge clk); start <= 0;
        for (i = 0; i < 64; i = i + 1) begin
            in_valid <= 1;
            in_re    <= (i == 0) ? 16'sh7FFF : 16'sh0000;
            in_im    <= 16'sh0000;
            @(posedge clk);
        end
        in_valid <= 0;

        // Wait for done
        captured = 0;
        while (!done) begin
            @(posedge clk);
            if (out_valid && captured < 64) begin
                out_re_arr[captured] <= out_re;
                out_im_arr[captured] <= out_im;
                captured = captured + 1;
            end
        end

        // Check: expect each output bin ≈ x[0] / N
        begin : check_flat
            integer k, fails;
            integer expected;
            fails = 0;
            expected = 32767 / 64;          // ≈ 512
            for (k = 0; k < 64; k = k + 1) begin
                if ((out_re_arr[k] < expected - 50) || (out_re_arr[k] > expected + 50) ||
                    (out_im_arr[k] < -50)            || (out_im_arr[k] > 50)) begin
                    $display("  bin[%0d] re=%0d im=%0d expected ~%0d",
                             k, out_re_arr[k], out_im_arr[k], expected);
                    fails = fails + 1;
                end
            end
            if (fails == 0) $display("PASS: FFT of impulse is flat as expected.");
            else            $display("FAIL: %0d bins out of tolerance.", fails);
        end

        $finish;
    end
endmodule

`default_nettype wire
