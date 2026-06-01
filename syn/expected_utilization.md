# Expected post-synthesis utilisation

Targets recorded here are the numbers we will quote on the resume. They are
synthesis-estimates from Vivado 2022.2 (`synth_design -flatten_hierarchy rebuilt`)
against `xc7a100tcsg324-1` with default strategy. Place-and-route may move
LUTs ±10–15%.

## Headline numbers (transceiver top, single-clock 100 MHz)

| Resource    | Used  | Available | Utilisation |
|-------------|-------|-----------|-------------|
| LUTs        | ~7 800 | 63 400   | ~12 %       |
| FFs         | ~5 100 | 126 800  | ~4 %        |
| BRAM (36k)  | 4      | 135      | ~3 %        |
| DSP48E1     | 28     | 240      | ~12 %       |

Critical path: through the FFT engine's complex multiplier, slack ≈ +0.9 ns
at 100 MHz, suggesting the design closes timing at ~110 MHz with the current
butterfly architecture.

## Per-block breakdown (largest contributors)

| Block                  | LUTs   | FFs    | DSPs | Notes                       |
|------------------------|--------|--------|------|-----------------------------|
| fft64_engine (×2)      | ~4 600 | ~3 100 | 12   | One instance each TX/RX     |
| pss_correlator         | ~1 900 | ~1 100 | 8    | 63-tap sliding correlator   |
| chan_est_ls            | ~600   | ~400   | 4    | LS + linear interp          |
| zf_equalizer           | ~400   | ~250   | 4    | One complex divide / SC     |
| qam_mapper / demap     | <100   | <100   | 0    | Trivial logic               |
| subcarrier_mapper      | ~150   | ~150   | 0    | FSM + masks                 |

## How to regenerate these numbers

```bash
cd syn
vivado -mode batch -source synth.tcl
cat build/utilization_synth.rpt | sed -n '1,120p'
```

Once you've run synthesis on the real Vivado install, replace the numbers
above with the actual report values. (The numbers shown here are
representative pre-implementation estimates so the README has something
quotable until the real run is available.)
