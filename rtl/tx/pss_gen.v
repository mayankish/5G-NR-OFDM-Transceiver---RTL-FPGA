// ---------------------------------------------------------------------------
// pss_gen.v
//
// Streams out the Zadoff-Chu PSS sequence (root u=25, length 63) when
// triggered. Values are precomputed in Q1.15 and held in a ROM, mirroring
// what reference_model.zadoff_chu(25, 63) produces.
//
// Usage flow: assert `start` to begin streaming; pss_valid pulses high for
// 63 consecutive cycles with the I/Q samples. pss_done pulses at the end.
//
// To regenerate the ROM values, run:
//   python -c "import numpy as np;
//              u,L=25,63;
//              s=np.exp(-1j*np.pi*u*np.arange(L)*(np.arange(L)+1)/L);
//              for v in s:
//                  print(f'{int(round(v.real*32767))&0xFFFF:04x}{int(round(v.imag*32767))&0xFFFF:04x}')"
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module pss_gen #(
    parameter integer LEN   = 63,
    parameter integer WIDTH = 16
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       start,
    output reg                        pss_valid,
    output reg  signed [WIDTH-1:0]    pss_re,
    output reg  signed [WIDTH-1:0]    pss_im,
    output reg                        pss_done
);
    reg signed [WIDTH-1:0] rom_re [0:LEN-1];
    reg signed [WIDTH-1:0] rom_im [0:LEN-1];

    initial begin
        // Pre-computed Zadoff-Chu u=25, L=63 — see header comment.
        // To save space we initialise the first eight and rely on a $readmemh
        // for the rest (rtl/tx/pss_zc_u25_L63.mem) when synthesising. For
        // simulation, the testbench loads the same .mem file too.
        $readmemh("pss_zc_u25_L63.mem", rom_re, 0, LEN-1);
        // Imaginary part is stored in a second .mem; alternatively pack both
        // into one 32-bit-wide ROM. We keep them split for readability.
        $readmemh("pss_zc_u25_L63_im.mem", rom_im, 0, LEN-1);
    end

    reg [$clog2(LEN):0] cnt;
    reg                 running;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt       <= 0;
            running   <= 1'b0;
            pss_valid <= 1'b0;
            pss_done  <= 1'b0;
            pss_re    <= 0;
            pss_im    <= 0;
        end else begin
            pss_done  <= 1'b0;
            pss_valid <= 1'b0;
            if (!running && start) begin
                running <= 1'b1;
                cnt     <= 0;
            end
            if (running) begin
                pss_re    <= rom_re[cnt];
                pss_im    <= rom_im[cnt];
                pss_valid <= 1'b1;
                cnt       <= cnt + 1;
                if (cnt == LEN - 1) begin
                    running  <= 1'b0;
                    pss_done <= 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
