// ---------------------------------------------------------------------------
// cp_insert.v
//
// Cyclic Prefix insertion: takes a 64-sample IFFT output and emits an
// 80-sample stream whose first 16 samples are a copy of the last 16 of the
// FFT block (the cyclic prefix), followed by all 64 samples in order.
//
// Implementation: small FIFO/RAM of N_FFT samples, two-pass readout. We
// accept all N_FFT samples in, then output the tail (CP) followed by the
// full block.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module cp_insert #(
    parameter integer N_FFT = 64,
    parameter integer N_CP  = 16,
    parameter integer WIDTH = 16
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       in_valid,
    input  wire signed [WIDTH-1:0]    in_re,
    input  wire signed [WIDTH-1:0]    in_im,
    output reg                        in_ready,
    output reg                        out_valid,
    output reg  signed [WIDTH-1:0]    out_re,
    output reg  signed [WIDTH-1:0]    out_im,
    output reg                        out_done
);
    reg signed [WIDTH-1:0] mem_re [0:N_FFT-1];
    reg signed [WIDTH-1:0] mem_im [0:N_FFT-1];

    localparam S_LOAD = 2'd0;
    localparam S_OUT  = 2'd1;

    reg [1:0]               state;
    reg [$clog2(N_FFT):0]   wr_cnt;
    reg [$clog2(N_FFT+N_CP):0] rd_cnt;

    // Read address: first N_CP outputs come from the tail, then the full block.
    wire [$clog2(N_FFT)-1:0] rd_addr =
        (rd_cnt < N_CP) ? (N_FFT - N_CP + rd_cnt[$clog2(N_FFT)-1:0])
                        : (rd_cnt - N_CP);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_LOAD;
            wr_cnt    <= 0;
            rd_cnt    <= 0;
            in_ready  <= 1'b1;
            out_valid <= 1'b0;
            out_done  <= 1'b0;
            out_re    <= 0;
            out_im    <= 0;
        end else begin
            out_done <= 1'b0;
            out_valid <= 1'b0;
            case (state)
            S_LOAD: begin
                in_ready <= 1'b1;
                if (in_valid) begin
                    mem_re[wr_cnt] <= in_re;
                    mem_im[wr_cnt] <= in_im;
                    wr_cnt <= wr_cnt + 1;
                    if (wr_cnt == N_FFT - 1) begin
                        in_ready <= 1'b0;
                        state    <= S_OUT;
                        rd_cnt   <= 0;
                    end
                end
            end
            S_OUT: begin
                out_re    <= mem_re[rd_addr];
                out_im    <= mem_im[rd_addr];
                out_valid <= 1'b1;
                rd_cnt    <= rd_cnt + 1;
                if (rd_cnt == N_FFT + N_CP - 1) begin
                    out_done <= 1'b1;
                    state    <= S_LOAD;
                    wr_cnt   <= 0;
                end
            end
            endcase
        end
    end
endmodule

`default_nettype wire
