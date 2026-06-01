"""
Generate fixed-point test vectors that the Verilog testbench reads.

Outputs (under sim/vectors/):
  tx_bits.hex          — input bit stream, one bit per line
  tx_samples.hex       — TX time-domain samples after CP + PSS, Q1.15 I,Q packed in 32-bit hex
  rx_samples.hex       — same samples after AWGN (SNR=20 dB) — what RTL RX sees
  expected_rx_bits.hex — golden RX bits the RTL TB will compare against
"""

from __future__ import annotations

from pathlib import Path
import numpy as np

from reference_model import transmit, receive, awgn


VEC_DIR = Path(__file__).resolve().parent / "vectors"
VEC_DIR.mkdir(parents=True, exist_ok=True)

NUM_SYMBOLS = 8
QAM_ORDER   = 4
SNR_DB      = 20.0


def to_q15_hex_pairs(samples: np.ndarray) -> list[str]:
    """Pack each complex sample as 16-bit signed I followed by 16-bit signed Q.

    We normalise by the worst-case magnitude so the largest sample maps to
    near ±0.99 in Q1.15, avoiding overflow during the IFFT input scaling test.
    """
    peak = np.max(np.abs(np.concatenate([samples.real, samples.imag])))
    scale = (2 ** 15 - 1) / max(peak, 1.0)
    i = np.round(samples.real * scale).astype(np.int32).clip(-32768, 32767)
    q = np.round(samples.imag * scale).astype(np.int32).clip(-32768, 32767)
    return [f"{(int(ii) & 0xFFFF):04x}{(int(qq) & 0xFFFF):04x}" for ii, qq in zip(i, q)]


def main():
    rng = np.random.default_rng(7)
    tx_bits, tx_samples, dmrs = transmit(NUM_SYMBOLS, QAM_ORDER, rng)
    rx_samples = awgn(tx_samples, snr_db=SNR_DB, rng=rng)
    rx_bits    = receive(rx_samples, dmrs, NUM_SYMBOLS, QAM_ORDER, equaliser="zf")

    (VEC_DIR / "tx_bits.hex").write_text("\n".join(str(b) for b in tx_bits.tolist()) + "\n")
    (VEC_DIR / "tx_samples.hex").write_text("\n".join(to_q15_hex_pairs(tx_samples)) + "\n")
    (VEC_DIR / "rx_samples.hex").write_text("\n".join(to_q15_hex_pairs(rx_samples)) + "\n")
    n = min(rx_bits.size, tx_bits.size)
    (VEC_DIR / "expected_rx_bits.hex").write_text("\n".join(str(b) for b in rx_bits[:n].tolist()) + "\n")

    print(f"Wrote vectors to {VEC_DIR}")
    errs = int(np.sum(tx_bits[:n] != rx_bits[:n]))
    print(f"Self-check at {SNR_DB} dB AWGN: {errs} bit errors / {n} bits "
          f"({errs / max(n, 1):.2e})")


if __name__ == "__main__":
    main()
