// ---------------------------------------------------------------------------
// subcarrier_mapper.v
//
// Assembles a 64-point frequency-domain grid:
//   * DC (k=0) and configured guard bands → zero
//   * Pilot positions (PILOT_POS) → DMRS sequence (held in an internal ROM)
//   * Data positions (DATA_POS)   → incoming QAM symbols
//
// Output is streamed out in natural FFT order (k = 0..63), driving the IFFT.
//
// Configuration: pilot/data positions and DMRS values are baked in as
// parameters / initial-block ROMs to keep the design simple. Regenerating
// them is a Python one-liner — see sim/reference_model.py.
//
// One input data symbol consumed per available slot; FSM walks k=0..63 and
// emits the appropriate value each cycle.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module subcarrier_mapper #(
    parameter integer N        = 64,
    parameter integer N_DATA   = 50,
    parameter integer N_PILOT  = 8,
    parameter integer WIDTH    = 16
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       start,            // begin assembling one symbol
    // Data input (from QAM mapper) — accepted when data_ready
    output reg                        data_ready,
    input  wire                       data_valid,
    input  wire signed [WIDTH-1:0]    data_re,
    input  wire signed [WIDTH-1:0]    data_im,
    // Grid output to IFFT
    output reg                        grid_valid,
    output reg  signed [WIDTH-1:0]    grid_re,
    output reg  signed [WIDTH-1:0]    grid_im,
    output reg                        grid_done
);
    // ----- Position tables (compile-time constants) ------------------------
    // PILOT positions chosen to match reference_model.py (every 8th active
    // subcarrier, 8 pilots). Edit both files together if you regenerate.
    reg pilot_mask  [0:N-1];
    reg guard_mask  [0:N-1];

    integer i;
    initial begin
        for (i = 0; i < N; i = i + 1) begin
            pilot_mask[i] = 1'b0;
            guard_mask[i] = 1'b0;
        end
        // Guard: DC (0), Nyquist edge (32), and 2 on each band edge.
        guard_mask[ 0] = 1'b1;
        guard_mask[ 1] = 1'b1;
        guard_mask[ 2] = 1'b1;
        guard_mask[32] = 1'b1;
        guard_mask[62] = 1'b1;
        guard_mask[63] = 1'b1;
        // Pilots — must match sim/reference_model.py PILOT_POS exactly.
        pilot_mask[ 3] = 1'b1;
        pilot_mask[11] = 1'b1;
        pilot_mask[19] = 1'b1;
        pilot_mask[27] = 1'b1;
        pilot_mask[36] = 1'b1;
        pilot_mask[44] = 1'b1;
        pilot_mask[52] = 1'b1;
        pilot_mask[60] = 1'b1;
    end

    // ----- DMRS pilot ROM (QPSK constellation Q1.15) -----------------------
    // 8 pilots, deterministic. Values picked to match reference_model.py
    // dmrs_sequence() seed=0xC0DE result. Re-export via sim/dump_dmrs.py.
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

    // ----- FSM walks k = 0 .. N-1 ------------------------------------------
    reg [$clog2(N):0]  k;
    reg [$clog2(N_PILOT):0] pilot_idx;
    reg                running;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            k          <= 0;
            pilot_idx  <= 0;
            running    <= 1'b0;
            data_ready <= 1'b0;
            grid_valid <= 1'b0;
            grid_done  <= 1'b0;
            grid_re    <= 0;
            grid_im    <= 0;
        end else begin
            grid_valid <= 1'b0;
            grid_done  <= 1'b0;
            data_ready <= 1'b0;

            if (!running && start) begin
                running   <= 1'b1;
                k         <= 0;
                pilot_idx <= 0;
            end

            if (running) begin
                if (guard_mask[k]) begin
                    grid_re    <= 0;
                    grid_im    <= 0;
                    grid_valid <= 1'b1;
                    k          <= k + 1;
                end else if (pilot_mask[k]) begin
                    grid_re    <= dmrs_re[pilot_idx];
                    grid_im    <= dmrs_im[pilot_idx];
                    grid_valid <= 1'b1;
                    pilot_idx  <= pilot_idx + 1;
                    k          <= k + 1;
                end else begin
                    // Data slot — request a symbol from the mapper
                    data_ready <= 1'b1;
                    if (data_valid) begin
                        grid_re    <= data_re;
                        grid_im    <= data_im;
                        grid_valid <= 1'b1;
                        k          <= k + 1;
                    end
                end

                if (k == N - 1 && (guard_mask[k] || pilot_mask[k] || data_valid)) begin
                    running   <= 1'b0;
                    grid_done <= 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
