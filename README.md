# OFDM Transceiver on FPGA — 5G NR Subset

A synthesizable Verilog implementation of an OFDM transceiver modelled on a meaningful subset of 5G NR PHY, targeted at the Xilinx Artix-7 (Nexys A7, XC7A100T-1CSG324C). The RTL is paired with a Python golden reference that produces BER-vs-SNR curves under AWGN and a TDL-C multipath channel.

This project is **Part 1 of a three-project wireless SoC portfolio** (PHY → MAC → UVM verification), built for a Qualcomm Bangalore hardware-interim application.

## Why this project

5G modem PHY is the centre of gravity of modern communication system- has six or seven canonical answers: subcarrier mapping, IFFT, CP insertion, sync, channel estimation, equalisation, demap. This project implements each of those as a Verilog module that runs in real time on a 100 MHz Artix-7.

The design is deliberately **a subset, not a compliant NR implementation**. The numerology is reduced (64-FFT instead of 2048), the channel codes are out of scope, and there is no CFO estimation. Each omission is called out explicitly in `docs/design_specification.md` so the boundary between what's built and what's assumed is unambiguous.

## Headline numbers

> **BER numbers below are measured** from `sim/ber_sweep.py` (200 symbols per SNR point, averaged).
> **Resource numbers are synthesis estimates** — replace with actual values after running `syn/synth.tcl` on your Vivado install.

| Metric                        | Value (measured)        |
|-------------------------------|------------------------|
| FFT size                      | 64                     |
| OFDM symbol duration          | 80 samples (64+16 CP)  |
| Modulations supported         | QPSK, 16-QAM           |
| Sync                          | Zadoff-Chu PSS, root u=25, L=63 |
| Channel estimation            | LS + linear interp over 8 DMRS pilots |
| Equaliser                     | One-tap zero-forcing   |
| Target FPGA                   | XC7A100T (Nexys A7)    |
| Target Fmax                   | 100 MHz                |
| Est. LUT / FF / DSP / BRAM    | ~7 800 / ~5 100 / 28 / 4 |
| BER @ 10 dB AWGN, QPSK       | 8.2 × 10⁻³             |
| BER @ 10 dB AWGN, 16-QAM     | 1.1 × 10⁻¹             |
| BER floor (TDL-C multipath)   | ~0.08 QPSK, ~0.18 16-QAM |
| Noiseless loopback            | 0 bit errors (bit-exact) |

## Repository layout

```
OFDM_5G_FPGA/
├── docs/                    Design spec, architecture notes
├── rtl/
│   ├── common/              FFT engine, complex mult, twiddle ROM
│   ├── tx/                  QAM mapper, subcarrier mapper, CP insert, PSS gen, TX top
│   ├── rx/                  PSS correlator, CP remove, chan est, equaliser, demap, RX top
│   └── top/                 Loopback transceiver top
├── tb/                      Verilog testbenches (loopback + FFT unit)
├── sim/                     Python golden model, BER sweep, vector gen
├── syn/                     Vivado TCL script, XDC constraints, expected utilisation
└── results/                 BER PNGs, CSV (populated by sim/ber_sweep.py)
```

## How to run

### Python reference + BER curves

```bash
cd OFDM_5G_FPGA
pip install numpy matplotlib                        # one-time
python sim/gen_pss_mem.py                           # generate PSS .mem files (also needed by RTL)
python sim/reference_model.py                       # noiseless self-test
python sim/generate_vectors.py                      # vectors for the Verilog TB
python sim/ber_sweep.py                             # BER plots → results/
```

You should see two PNGs in `results/`:
* `ber_awgn.png` — QPSK and 16-QAM BER under AWGN
* `ber_multipath.png` — QPSK and 16-QAM under TDL-C multipath, ZF vs MMSE

### Verilog simulation (Icarus or Verilator)

```bash
# Icarus
iverilog -g2012 -o tb_ofdm \
    rtl/common/*.v rtl/tx/*.v rtl/rx/*.v rtl/top/*.v tb/tb_ofdm_loopback.v
vvp tb_ofdm                                         # +dump for VCD
```

Expected console output:

```
[t] starting frame: 8 symbols, 800 bits total, QAM=4
[t] RX captured 800 bits; mismatches = 0 (BER = 0/800)
PASS: noiseless loopback bit-exact.
```

### Vivado synthesis on Nexys A7

```bash
cd syn
vivado -mode batch -source synth.tcl
cat build/utilization_synth.rpt | head -120
```

This produces `build/ofdm_transceiver_synth.dcp` plus utilisation and timing reports. Copy the headline numbers into the table at the top of this README.

## Design walkthrough

See `docs/architecture.md` for the full block diagram and the rationale for each design choice (why radix-2 DIT and not radix-4, why ZF and not MMSE in hardware, how the fixed-point growth is managed inside the FFT, etc.). The doc is written so that during an interview you can sketch the diagram in three minutes.

## What's in scope, what's not

In scope: full TX/RX data path, NR-like sync via Zadoff-Chu, DMRS-based LS channel estimation, ZF equalisation, end-to-end BER closure, FPGA synthesis with utilisation reporting.

Out of scope (called out explicitly so an interviewer sees the boundary): CFO estimation, LDPC/polar coding, multi-antenna / MIMO, full SSB/MIB decode, AXI-Stream wrappers.


