// ---------------------------------------------------------------------------
// twiddle_rom.v
//
// Twiddle ROM for a 64-point FFT. Holds W_N^k for k = 0..31 (i.e. N/2 entries)
// in signed Q1.15. Inferred as distributed/block ROM by Vivado.
//
//   W_64^k = exp(-j*2*pi*k/64) = cos(2*pi*k/64) - j*sin(2*pi*k/64)
//
// Values were precomputed and rounded to Q1.15. To regenerate, run:
//   python -c "import numpy as np;
//              N=64;
//              for k in range(N//2):
//                  c=int(round(np.cos(2*np.pi*k/N)*(2**15-1)));
//                  s=int(round(-np.sin(2*np.pi*k/N)*(2**15-1)));
//                  print(f'\\\"{k:02d}\\\": {c & 0xFFFF:04x}{s & 0xFFFF:04x}')"
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module twiddle_rom #(
    parameter integer N     = 64,
    parameter integer WIDTH = 16
) (
    input  wire [$clog2(N/2)-1:0]   addr,
    output wire signed [WIDTH-1:0]  w_re,
    output wire signed [WIDTH-1:0]  w_im
);
    reg signed [WIDTH-1:0] rom_re [0:N/2-1];
    reg signed [WIDTH-1:0] rom_im [0:N/2-1];

    initial begin
        // cos(2*pi*k/64), -sin(2*pi*k/64) in Q1.15
        rom_re[ 0] = 16'h7FFF; rom_im[ 0] = 16'h0000;
        rom_re[ 1] = 16'h7F62; rom_im[ 1] = 16'hF374;
        rom_re[ 2] = 16'h7D8A; rom_im[ 2] = 16'hE707;
        rom_re[ 3] = 16'h7A7D; rom_im[ 3] = 16'hDAD8;
        rom_re[ 4] = 16'h7642; rom_im[ 4] = 16'hCF04;
        rom_re[ 5] = 16'h70E3; rom_im[ 5] = 16'hC3A9;
        rom_re[ 6] = 16'h6A6E; rom_im[ 6] = 16'hB8E3;
        rom_re[ 7] = 16'h62F2; rom_im[ 7] = 16'hAECC;
        rom_re[ 8] = 16'h5A82; rom_im[ 8] = 16'hA57E;
        rom_re[ 9] = 16'h5134; rom_im[ 9] = 16'h9D0E;
        rom_re[10] = 16'h471D; rom_im[10] = 16'h9592;
        rom_re[11] = 16'h3C57; rom_im[11] = 16'h8F1D;
        rom_re[12] = 16'h30FC; rom_im[12] = 16'h89BE;
        rom_re[13] = 16'h2528; rom_im[13] = 16'h8583;
        rom_re[14] = 16'h18F9; rom_im[14] = 16'h8276;
        rom_re[15] = 16'h0C8C; rom_im[15] = 16'h809E;
        rom_re[16] = 16'h0000; rom_im[16] = 16'h8001;
        rom_re[17] = 16'hF374; rom_im[17] = 16'h809E;
        rom_re[18] = 16'hE707; rom_im[18] = 16'h8276;
        rom_re[19] = 16'hDAD8; rom_im[19] = 16'h8583;
        rom_re[20] = 16'hCF04; rom_im[20] = 16'h89BE;
        rom_re[21] = 16'hC3A9; rom_im[21] = 16'h8F1D;
        rom_re[22] = 16'hB8E3; rom_im[22] = 16'h9592;
        rom_re[23] = 16'hAECC; rom_im[23] = 16'h9D0E;
        rom_re[24] = 16'hA57E; rom_im[24] = 16'hA57E;
        rom_re[25] = 16'h9D0E; rom_im[25] = 16'hAECC;
        rom_re[26] = 16'h9592; rom_im[26] = 16'hB8E3;
        rom_re[27] = 16'h8F1D; rom_im[27] = 16'hC3A9;
        rom_re[28] = 16'h89BE; rom_im[28] = 16'hCF04;
        rom_re[29] = 16'h8583; rom_im[29] = 16'hDAD8;
        rom_re[30] = 16'h8276; rom_im[30] = 16'hE707;
        rom_re[31] = 16'h809E; rom_im[31] = 16'hF374;
    end

    assign w_re = rom_re[addr];
    assign w_im = rom_im[addr];
endmodule

`default_nettype wire
