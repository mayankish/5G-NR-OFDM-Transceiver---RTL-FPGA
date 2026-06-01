// ---------------------------------------------------------------------------
// tb_ofdm_loopback.v
//
// Top-level testbench for ofdm_transceiver. Generates a stream of random
// bits, pushes them into the TX, and bit-compares the RX output against the
// transmitted bits. Reports BER at the end of the run.
//
// Notes:
//   * No channel impairments (loopback path is wire-direct). This TB validates
//     the chain in the absence of noise — the RTL BER must be 0.
//   * The "with noise" sweep is done from Python (sim/ber_sweep.py) since
//     simulating thousands of symbols in Icarus/Verilator is slow and the
//     headline plots are floating-point anyway.
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module tb_ofdm_loopback;
    parameter integer SYMS_PER_FR = 8;
    parameter integer N_DATA      = 50;
    parameter integer MODE        = 0;       // 0 = QPSK
    parameter integer BITS_PER_SC = (MODE == 0) ? 2 : 4;
    parameter integer TOTAL_BITS  = SYMS_PER_FR * N_DATA * BITS_PER_SC;

    reg clk = 0;
    always #5 clk = ~clk;                    // 100 MHz

    reg rst_n = 0;
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1;
    end

    // DUT
    reg                       start_frame = 0;
    reg                       bits_in_valid = 0;
    reg  [3:0]                bits_in = 0;
    wire                      bits_in_ready;
    wire                      bits_out_valid;
    wire [3:0]                bits_out;
    wire [2:0]                nbits_out;
    wire                      frame_done;
    wire                      symbol_start;

    ofdm_transceiver #(
        .N_FFT(64), .N_CP(16), .N_DATA(N_DATA), .WIDTH(16),
        .SYMS_PER_FR(SYMS_PER_FR)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .mode(MODE[0]),
        .start_frame(start_frame),
        .bits_in_ready(bits_in_ready),
        .bits_in_valid(bits_in_valid),
        .bits_in(bits_in),
        .bits_out_valid(bits_out_valid),
        .bits_out(bits_out),
        .nbits_out(nbits_out),
        .frame_done(frame_done),
        .symbol_start(symbol_start)
    );

    // Bit generator: precomputed random pattern
    reg [TOTAL_BITS-1:0] tx_bits_q;
    reg [TOTAL_BITS-1:0] rx_bits_q;
    integer tx_idx = 0;
    integer rx_idx = 0;
    integer errors = 0;

    initial begin
        // Deterministic test pattern (LFSR-style)
        tx_bits_q = {TOTAL_BITS{1'b0}};
        begin : init_pat
            integer i;
            reg [15:0] lfsr;
            lfsr = 16'hACE1;
            for (i = 0; i < TOTAL_BITS; i = i + 1) begin
                lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
                tx_bits_q[i] = lfsr[0];
            end
        end
        rx_bits_q = {TOTAL_BITS{1'b0}};
    end

    // Drive bits into TX whenever it's hungry
    always @(posedge clk) begin
        if (!rst_n) begin
            bits_in_valid <= 0;
            tx_idx <= 0;
        end else if (bits_in_ready && tx_idx < TOTAL_BITS) begin
            if (MODE == 0) begin
                bits_in <= {2'b00, tx_bits_q[tx_idx+1], tx_bits_q[tx_idx]};
                tx_idx  <= tx_idx + 2;
            end else begin
                bits_in <= {tx_bits_q[tx_idx+3], tx_bits_q[tx_idx+2],
                            tx_bits_q[tx_idx+1], tx_bits_q[tx_idx]};
                tx_idx  <= tx_idx + 4;
            end
            bits_in_valid <= 1'b1;
        end else begin
            bits_in_valid <= 1'b0;
        end
    end

    // Sample RX bits
    always @(posedge clk) begin
        if (!rst_n) begin
            rx_idx <= 0;
        end else if (bits_out_valid && rx_idx < TOTAL_BITS) begin
            if (nbits_out == 3'd2) begin
                rx_bits_q[rx_idx]   <= bits_out[0];
                rx_bits_q[rx_idx+1] <= bits_out[1];
                rx_idx <= rx_idx + 2;
            end else begin
                rx_bits_q[rx_idx]   <= bits_out[0];
                rx_bits_q[rx_idx+1] <= bits_out[1];
                rx_bits_q[rx_idx+2] <= bits_out[2];
                rx_bits_q[rx_idx+3] <= bits_out[3];
                rx_idx <= rx_idx + 4;
            end
        end
    end

    // Stimulus + end-of-test
    initial begin
        @(posedge rst_n);
        repeat (5) @(posedge clk);
        $display("[%0t] starting frame: %0d symbols, %0d bits total, QAM=%0d",
                 $time, SYMS_PER_FR, TOTAL_BITS, (MODE == 0) ? 4 : 16);
        start_frame <= 1; @(posedge clk); start_frame <= 0;

        // Run a generous timeout proportional to frame length
        repeat (SYMS_PER_FR * 250) @(posedge clk);

        begin : check
            integer i;
            errors = 0;
            for (i = 0; i < rx_idx; i = i + 1) begin
                if (rx_bits_q[i] !== tx_bits_q[i]) errors = errors + 1;
            end
            $display("[%0t] RX captured %0d bits; mismatches = %0d (BER = %0d/%0d)",
                     $time, rx_idx, errors, errors, rx_idx);
            if (errors == 0) $display("PASS: noiseless loopback bit-exact.");
            else             $display("FAIL: noiseless loopback has bit errors.");
        end

        $finish;
    end

    // Optional waveform dump
    initial begin
        if ($test$plusargs("dump")) begin
            $dumpfile("tb_ofdm_loopback.vcd");
            $dumpvars(0, tb_ofdm_loopback);
        end
    end
endmodule

`default_nettype wire
