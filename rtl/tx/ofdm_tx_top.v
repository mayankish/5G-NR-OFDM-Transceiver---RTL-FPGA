// ---------------------------------------------------------------------------
// ofdm_tx_top.v
//
// OFDM transmitter top: chains qam_mapper → subcarrier_mapper → fft64_engine
// (IFFT mode) → cp_insert, with a PSS prepend at the start of each frame.
//
// Per-frame sequence:
//   1. Stream PSS (63 samples) onto samples_out.
//   2. For each OFDM symbol:
//        a. Drain N_DATA bits into qam_mapper.
//        b. subcarrier_mapper drives 64 grid samples into IFFT.
//        c. IFFT done → cp_insert emits 80 time-domain samples.
//
// Handshake: simple ready/valid on bit input and sample output. Coarse FSM;
// production code would pipeline harder but this is intentionally readable.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module ofdm_tx_top #(
    parameter integer N_FFT       = 64,
    parameter integer N_CP        = 16,
    parameter integer N_DATA      = 50,
    parameter integer WIDTH       = 16,
    parameter integer SYMS_PER_FR = 8     // OFDM symbols per "frame"
) (
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       mode,           // 0=QPSK, 1=16-QAM
    input  wire                       start_frame,
    // Bit input
    output reg                        bits_ready,
    input  wire                       bits_valid,
    input  wire [3:0]                 bits_in,        // up to 4 bits per symbol
    // Sample output
    output reg                        samp_valid,
    output reg  signed [WIDTH-1:0]    samp_re,
    output reg  signed [WIDTH-1:0]    samp_im,
    output reg                        frame_done
);
    // --- PSS generator
    wire                       pss_start;
    wire                       pss_valid;
    wire signed [WIDTH-1:0]    pss_re, pss_im;
    wire                       pss_done;
    pss_gen #(.LEN(63), .WIDTH(WIDTH)) u_pss (
        .clk(clk), .rst_n(rst_n),
        .start(pss_start),
        .pss_valid(pss_valid), .pss_re(pss_re), .pss_im(pss_im),
        .pss_done(pss_done)
    );

    // --- QAM mapper
    reg                        qam_in_valid;
    reg  [3:0]                 qam_bits;
    wire                       qam_out_valid;
    wire signed [WIDTH-1:0]    qam_re, qam_im;
    qam_mapper #(.WIDTH(WIDTH)) u_qam (
        .clk(clk), .rst_n(rst_n), .mode(mode),
        .valid_in(qam_in_valid), .bits_in(qam_bits),
        .valid_out(qam_out_valid), .sym_re(qam_re), .sym_im(qam_im)
    );

    // --- Subcarrier mapper
    reg                        sm_start;
    wire                       sm_data_ready;
    wire                       sm_grid_valid;
    wire signed [WIDTH-1:0]    sm_grid_re, sm_grid_im;
    wire                       sm_grid_done;
    subcarrier_mapper #(.N(N_FFT), .N_DATA(N_DATA), .WIDTH(WIDTH)) u_scm (
        .clk(clk), .rst_n(rst_n), .start(sm_start),
        .data_ready(sm_data_ready),
        .data_valid(qam_out_valid),
        .data_re(qam_re), .data_im(qam_im),
        .grid_valid(sm_grid_valid),
        .grid_re(sm_grid_re), .grid_im(sm_grid_im),
        .grid_done(sm_grid_done)
    );

    // --- IFFT
    reg                        ifft_start;
    wire                       ifft_in_ready;
    wire                       ifft_out_valid;
    wire signed [WIDTH-1:0]    ifft_out_re, ifft_out_im;
    wire                       ifft_done;
    fft64_engine #(.N(N_FFT), .LOG2N(6), .WIDTH(WIDTH)) u_ifft (
        .clk(clk), .rst_n(rst_n),
        .inverse(1'b1),
        .start(ifft_start),
        .in_valid(sm_grid_valid),
        .in_re(sm_grid_re), .in_im(sm_grid_im),
        .in_ready(ifft_in_ready),
        .out_valid(ifft_out_valid),
        .out_re(ifft_out_re), .out_im(ifft_out_im),
        .done(ifft_done)
    );

    // --- CP insert
    wire                       cp_in_ready;
    wire                       cp_out_valid;
    wire signed [WIDTH-1:0]    cp_out_re, cp_out_im;
    wire                       cp_out_done;
    cp_insert #(.N_FFT(N_FFT), .N_CP(N_CP), .WIDTH(WIDTH)) u_cp (
        .clk(clk), .rst_n(rst_n),
        .in_valid(ifft_out_valid),
        .in_re(ifft_out_re), .in_im(ifft_out_im),
        .in_ready(cp_in_ready),
        .out_valid(cp_out_valid),
        .out_re(cp_out_re), .out_im(cp_out_im),
        .out_done(cp_out_done)
    );

    // --- Frame FSM
    localparam S_IDLE    = 3'd0;
    localparam S_PSS     = 3'd1;
    localparam S_SYM_RUN = 3'd2;
    localparam S_SYM_WT  = 3'd3;
    localparam S_FRAME_E = 3'd4;

    reg [2:0] state;
    reg [$clog2(SYMS_PER_FR+1):0] sym_idx;

    assign pss_start  = (state == S_IDLE) && start_frame;

    // bits_ready: assert whenever the subcarrier mapper is asking for a data
    // slot. The qam_in_valid pulse below latches the incoming bits.
    always @(*) begin
        bits_ready    = sm_data_ready && (state == S_SYM_RUN);
        qam_in_valid  = bits_ready && bits_valid;
        qam_bits      = bits_in;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            sym_idx    <= 0;
            sm_start   <= 1'b0;
            ifft_start <= 1'b0;
            samp_valid <= 1'b0;
            samp_re    <= 0;
            samp_im    <= 0;
            frame_done <= 1'b0;
        end else begin
            sm_start   <= 1'b0;
            ifft_start <= 1'b0;
            frame_done <= 1'b0;
            // Sample mux: PSS during preamble, CP-stream during symbols.
            if (state == S_PSS) begin
                samp_valid <= pss_valid;
                samp_re    <= pss_re;
                samp_im    <= pss_im;
            end else begin
                samp_valid <= cp_out_valid;
                samp_re    <= cp_out_re;
                samp_im    <= cp_out_im;
            end

            case (state)
            S_IDLE: begin
                if (start_frame) begin
                    sym_idx <= 0;
                    state   <= S_PSS;
                end
            end
            S_PSS: begin
                if (pss_done) begin
                    sm_start   <= 1'b1;
                    ifft_start <= 1'b1;
                    state      <= S_SYM_RUN;
                end
            end
            S_SYM_RUN: begin
                if (cp_out_done) begin
                    sym_idx <= sym_idx + 1;
                    if (sym_idx + 1 == SYMS_PER_FR) begin
                        state <= S_FRAME_E;
                    end else begin
                        state <= S_SYM_WT;
                    end
                end
            end
            S_SYM_WT: begin
                // one-cycle gap before kicking next symbol
                sm_start   <= 1'b1;
                ifft_start <= 1'b1;
                state      <= S_SYM_RUN;
            end
            S_FRAME_E: begin
                frame_done <= 1'b1;
                state      <= S_IDLE;
            end
            endcase
        end
    end
endmodule

`default_nettype wire
