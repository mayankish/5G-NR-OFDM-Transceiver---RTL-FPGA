# Architecture Notes

## Block diagram (text form)

```
                           ┌──────────────────────────── TRANSMITTER ─────────────────────────────┐
  bits ──► qam_mapper ──► subcarrier_mapper ──► ifft64 ──► cp_insert ──► pss_prepend ──► samples_out
                                  ▲                                          ▲
                                  │                                          │
                              dmrs_rom                                  pss_zc_rom
                                                                              
                           ┌──────────────────────────── RECEIVER ───────────────────────────────┐
  samples_in ──► pss_corr ──► cp_remove ──► fft64 ──► chan_est_ls ──► zf_equalizer ──► qam_demap ──► bits
                    │                                       ▲
                    └── start_of_symbol                pilot_extract
```

## Why these blocks, in this order

**PSS prepend / correlator.** Time synchronisation is the first thing the receiver must do — without symbol-edge alignment, CP removal samples the wrong window and the entire chain collapses. Using a Zadoff-Chu sequence here mirrors how NR PSS works in SSB and gives a concrete, sharp autocorrelation peak that's straightforward to detect with a sliding correlator.

**CP insertion / removal.** The cyclic prefix turns linear convolution by the channel into circular convolution from the DFT's point of view, which is what makes one-tap frequency-domain equalisation possible. Removing it correctly *depends* on having time sync right, which is why PSS comes first.

**IFFT / FFT.** Shared radix-2 DIT engine, 6 stages for N=64. We could have used Xilinx FFT IP — most undergrad projects do — but writing the engine ourselves demonstrates real DSP-hardware understanding for the Qualcomm interview. Trade-off: our engine is ~3× larger than the optimised Xilinx IP. That's a fair price for code an interviewer can read.

**DMRS-based LS channel estimation.** Pilot subcarriers are known at TX and RX. The receiver divides the received pilot by the transmitted pilot to get a noisy estimate of the channel at pilot positions, then linearly interpolates across data subcarriers. This is the textbook OFDM channel estimator; MMSE is a refinement (covariance-aware) that we deliberately leave out of RTL but include in the Python model so the BER gap is visible.

**ZF equaliser.** One complex division per subcarrier. Cheap. Has the known noise-enhancement weakness at deep fades — that's a perfect interview-question hook to discuss MMSE as the production answer.

## What an interviewer is likely to ask

1. *Why radix-2 DIT and not radix-4 or SDF?* → Radix-2 DIT is the clearest pedagogically; radix-4 halves the multiplier count but needs N to be a power of 4; SDF (single-path delay feedback) is the streaming-friendly architecture used in production NR FFTs.
2. *How do you handle fixed-point growth in the FFT?* → 1 bit of growth per butterfly stage, rescale at output. Alternative is block floating-point.
3. *Why ZF and not MMSE?* → ZF doesn't need a noise variance estimate; MMSE does. ZF is simpler and the BER gap is small at high SNR but large at low SNR.
4. *How would you add CFO estimation?* → CP-based autocorrelation (Moose / van de Beek) on the repeated CP samples, then a phase rotator before FFT.
5. *Why 64-FFT and not 2048 like real NR?* → DSP and BRAM budget on Artix-7; 2048-FFT would burn most of the chip on a single block.

## Files and their roles

| File                          | Role                                                   |
|-------------------------------|--------------------------------------------------------|
| `rtl/common/fft64_engine.v`   | Shared radix-2 DIT FFT, used for both IFFT and FFT     |
| `rtl/common/complex_mult.v`   | Q1.15 complex multiplier, 3-multiplier form            |
| `rtl/common/twiddle_rom.v`    | Twiddle factor ROM, 32 entries (N/2 for 64-pt)         |
| `rtl/tx/qam_mapper.v`         | QPSK / 16-QAM Gray-coded mapper                        |
| `rtl/tx/subcarrier_mapper.v`  | Inserts DMRS pilots, nulls DC + guard bands            |
| `rtl/tx/cp_insert.v`          | Prepends last 16 samples to each 64-sample symbol      |
| `rtl/tx/pss_gen.v`            | Zadoff-Chu (u=25, L=63) sequence ROM + prepend FSM     |
| `rtl/tx/ofdm_tx_top.v`        | TX-side top wrapper                                    |
| `rtl/rx/pss_correlator.v`     | Sliding correlator, peak detect, emits symbol_start    |
| `rtl/rx/cp_remove.v`          | Drops first 16 samples of each 80-sample window        |
| `rtl/rx/chan_est_ls.v`        | LS estimate at pilots + linear interp on data carriers |
| `rtl/rx/zf_equalizer.v`       | One complex division per data subcarrier               |
| `rtl/rx/qam_demap.v`          | Hard-decision QPSK / 16-QAM demapper                   |
| `rtl/rx/ofdm_rx_top.v`        | RX-side top wrapper                                    |
| `rtl/top/ofdm_transceiver.v`  | Loopback top tying TX → channel hook → RX              |
