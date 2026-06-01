# OFDM Transceiver — 5G NR-Subset — FPGA Implementation

## 1. Purpose

A synthesizable Verilog implementation of a small-scale OFDM transceiver that mirrors a meaningful subset of 5G NR PHY behaviour, suitable for the Xilinx Artix-7 (Nexys A7, XC7A100T-1CSG324C). The design is paired with a Python golden reference model that produces BER-vs-SNR curves for both AWGN and a multipath (TDL-C) channel.

This project is intentionally scoped so that every block on the data path has a recognised 5G NR analogue. The numerology is a *subset*, not a compliant implementation — the goal is to demonstrate hardware design competence at modem PHY layer granularity, not to ship a NR UE.

## 2. Numerology (subset of 5G NR)

| Parameter                    | Value                              | NR analogue                                 |
|------------------------------|------------------------------------|---------------------------------------------|
| FFT size (`N_FFT`)           | 64                                 | 2048 in NR FR1 (we shrink for FPGA fit)     |
| Active subcarriers           | 50 (data) + 8 (DMRS) + 6 (null/guard) | DC, Nyquist, 2 lower & 2 upper edges nulled |
| Cyclic prefix (`N_CP`)       | 16 samples (normal CP, ratio 1/4)  | NR normal CP ≈ 4.7 μs                       |
| Subcarrier spacing (logical) | 15 kHz                             | NR µ=0 numerology                           |
| Sample rate (logical)        | 960 kHz = 64 × 15 kHz              | scaled-down NR µ=0                          |
| Symbol duration              | 80 samples (FFT + CP)              | —                                           |
| Slot                         | 14 OFDM symbols                    | NR slot                                     |
| Sync sequence                | Zadoff-Chu, root u=25, length 63   | NR PSS (root cycled across 0,1,2 in spec)   |
| Channel estimation           | Comb-pilot DMRS, LS + linear interp| Simplified NR DMRS                          |
| Modulation                   | QPSK, 16-QAM                       | Same set as NR PDSCH (lowest two)           |
| Equalization                 | One-tap zero-forcing (ZF)          | Industry uses MMSE; ZF is the educational form |

## 3. Top-level data path

```
TX:  bits ──► QAM mapper ──► subcarrier mapper (DC null, DMRS insert) ──► 64-pt IFFT ──► CP add ──► [PSS prepend] ──► I/Q samples out

CH:  AWGN + multipath (TDL-C truncated to 4 taps for hardware sim)

RX:  I/Q ──► PSS correlator (peak detect → symbol start) ──► CP remove ──► 64-pt FFT ──► DMRS extract ──► LS chan est + interp ──► ZF equaliser ──► QAM demapper ──► bits
```

## 4. Fixed-point format

All datapath samples are signed Q1.15 (16-bit, one sign bit, 15 fractional bits). Twiddle factors are stored as Q1.15. The FFT engine grows internal precision by 1 bit per stage and rescales at output to keep the data path uniform 16-bit wide.

## 5. Synthesis target

| Item            | Value                          |
|-----------------|--------------------------------|
| FPGA            | Xilinx XC7A100T-1CSG324C       |
| Board           | Digilent Nexys A7              |
| Target Fmax     | 100 MHz                        |
| Clock source    | 100 MHz on-board oscillator    |
| Toolchain       | Vivado 2022.2 (or later)       |

Resource budget (target, not measured):

| Resource | Budget | Notes                                |
|----------|--------|--------------------------------------|
| LUT      | < 15 % | The 100T has 63 400 LUTs            |
| FF       | < 10 % |                                      |
| DSP48E1  | < 25 % | 240 available; FFT + equaliser heavy |
| BRAM     | < 15 % | Twiddle ROM + sample buffers         |

## 6. Verification strategy

1. **Python golden model** generates TX bits, modulated samples, channel-distorted samples, and expected RX bits.
2. **CSV vectors** are dumped at every interface (TX bits → IFFT in → IFFT out → channel out → FFT in → equaliser out → bits).
3. **Verilog testbench** reads the same input vectors, runs them through the RTL, and bit-compares against the golden model within a tolerance band (since fixed-point will not match floating-point exactly).
4. **BER closure** is the headline metric — RTL BER must track the floating-point BER curve to within 1 dB at BER = 10⁻³.

## 7. Out of scope (for this project, on purpose)

- Frequency synchronisation (CFO estimation). Time sync only via PSS.
- LDPC / polar coding. Raw bits in, raw bits out — coding is a separate project.
- Multi-antenna / MIMO.
- Full SSB / MIB decoding.
- AXI-Stream wrappers. Plain ready/valid handshakes are used; AXI is a wrapper exercise that can be added later when targeting Zynq.

These omissions are honest scope choices. They are listed explicitly so an interviewer reading the README can see the boundary of what was built versus what was assumed.
