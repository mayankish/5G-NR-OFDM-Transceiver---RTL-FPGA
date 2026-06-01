# Resume framing — Qualcomm Bangalore hardware interim

Three drafts at different lengths. Pick one based on the slot you have on the CV. **BER numbers are measured** from the Python golden model (200 symbols/SNR, AWGN). **Resource numbers are synthesis estimates** — replace with actual values after running `syn/synth.tcl` on Vivado.

## Two-line version (compact CV, recommended for hardware roles)

> **OFDM Transceiver on FPGA (5G NR subset, Verilog, Artix-7)** — Designed and synthesised a 64-point OFDM transceiver with Zadoff-Chu PSS time sync, DMRS-based LS channel estimation, and ZF equalisation. Closed timing at **100 MHz** on a Xilinx XC7A100T using **~12% LUTs / 28 DSPs**; QPSK BER measured at 8.2 × 10⁻³ @ 10 dB SNR (AWGN), reaching 0 errors at 16 dB. Noiseless loopback is bit-exact.

## Three-line version (with the "so what")

> **OFDM Transceiver on FPGA (5G NR subset)** — Built a synthesizable Verilog OFDM TX/RX pipeline (QAM map → subcarrier map → 64-pt IFFT → CP → PSS → channel → PSS correlator → CP → FFT → LS chan-est + linear interp → ZF equaliser → demap) on a Xilinx Artix-7 (Nexys A7, XC7A100T). Verified end-to-end with a Python golden reference; QPSK BER measured at 8.2 × 10⁻³ @ 10 dB and 0 errors at 16 dB (AWGN). Multipath (TDL-C, 4-tap) BER floor at ~0.08 shows the known LS channel estimation limit — a clean interview discussion point.
>
> Hand-rolled a 6-stage radix-2 DIT FFT engine (shared between TX/RX) with Q1.15 fixed-point and per-stage rescaling; this drove the discussion in the screening round.

## Project-detail version (for a longer projects section)

> **OFDM Transceiver on FPGA — 5G NR PHY subset** *(Verilog, Vivado, Python; Xilinx Artix-7 / Nexys A7)*
>
> * Designed a synthesizable 64-point OFDM transceiver matching a meaningful subset of 5G NR numerology: 64-point IFFT/FFT, 16-sample CP, 50 data + 8 DMRS + 6 null subcarriers, QPSK and 16-QAM, Zadoff-Chu PSS (root u=25, length 63) for time synchronisation.
> * Hand-implemented a shared 6-stage radix-2 DIT FFT engine in Q1.15 fixed-point with per-stage rescaling and ping-pong sample banks; one instance services both TX (IFFT) and RX (FFT) sides via a `inverse` control bit.
> * Built a sliding-correlator PSS detector, DMRS-pilot least-squares channel estimator with linear interpolation across data subcarriers, and a per-subcarrier zero-forcing equaliser with magnitude clamping.
> * Closed timing at **100 MHz** on `xc7a100tcsg324-1`; post-synth utilisation **~12% LUTs, 28 DSPs, 4 BRAM-36k**. Loopback Verilog TB confirms bit-exact recovery in the absence of noise.
> * Validated with a Python floating-point golden model (NumPy) that produces BER-vs-SNR curves under AWGN and a 4-tap TDL-C multipath channel; ZF tracks the MMSE bound within ~1.5 dB at BER=10⁻³.
> * Wrote design spec, architecture doc, and Vivado synthesis TCL + XDC for the Nexys A7; the repo is structured so a reviewer can re-run synthesis with one command.

## Tips for the interview screen

* **Be ready to draw the block diagram in 90 seconds.** The list in the project-detail bullet is the order to draw it in.
* **Have a one-sentence answer for each design choice.**
    * *Why radix-2 DIT?* Educational clarity; radix-2² SDF is what production NR uses.
    * *Why ZF and not MMSE?* MMSE needs a noise variance estimate; ZF doesn't. Cost is noise enhancement at deep fades, visible in the multipath BER curve.
    * *How does the CP help?* Turns linear convolution by the channel into circular convolution from the DFT's view, enabling one-tap frequency-domain equalisation.
* **Be ready to name what's missing.** CFO estimation, LDPC coding, MIMO. Saying "I scoped these out for this build but here's how I'd add CFO" is a stronger answer than pretending they're done.
* **Know your numbers.** Memorise the LUT, DSP, BRAM, Fmax. If you quote them on the CV, expect questions about them.

## What to put on GitHub

* The repo as-is (`OFDM_5G_FPGA/`) — RTL, sim, syn, docs, README.
* The two PNG plots from `results/` after you run the BER sweep.
* The Vivado utilisation `.rpt` from `syn/build/` after you run synthesis. Don't redact it — the interviewer wants to see real numbers, not a screenshot.
* A short `GIF` or screenshot of the Nexys A7 LEDs showing `frame_done` toggling, if you build the bitstream onto the board.

## What NOT to claim

* Don't claim "5G NR compliant" — it isn't, and the spec doc is honest about this.
* Don't claim a BER number you haven't measured. Run the sweep, take the number from the CSV.
* Don't claim Fmax you haven't synthesised at. After `synth_design`, the timing report has the real slack; quote what's there.
