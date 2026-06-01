"""
BER-vs-SNR sweep for the OFDM golden model.

Produces:
  results/ber_awgn.png
  results/ber_multipath.png
  results/ber_results.csv

These are the headline plots that go on the resume / README.
"""

from __future__ import annotations

import csv
import os
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")                       # headless
import matplotlib.pyplot as plt
import numpy as np

# Local import
sys.path.insert(0, str(Path(__file__).resolve().parent))
from reference_model import (
    transmit, receive, awgn, multipath_tdlc, dmrs_sequence,
    N_FFT, N_CP,
)


RESULTS_DIR = Path(__file__).resolve().parents[1] / "results"
RESULTS_DIR.mkdir(parents=True, exist_ok=True)


def run_awgn(snr_db_grid, qam_order, num_symbols, rng):
    bers = []
    for snr in snr_db_grid:
        tx_bits, tx_samples, dmrs = transmit(num_symbols, qam_order, rng)
        rx_samples = awgn(tx_samples, snr_db=snr, rng=rng)
        rx_bits = receive(rx_samples, dmrs, num_symbols, qam_order, equaliser="zf")
        n = min(rx_bits.size, tx_bits.size)
        ber = np.mean(tx_bits[:n] != rx_bits[:n])
        bers.append(ber)
        print(f"  AWGN  QAM{qam_order:>2}  SNR={snr:5.1f} dB  BER={ber:.4e}")
    return np.array(bers)


def run_multipath(snr_db_grid, qam_order, num_symbols, rng, equaliser="zf",
                  num_channels=20):
    """Average BER across several independent channel realisations."""
    bers = []
    for snr in snr_db_grid:
        snr_lin = 10 ** (snr / 10)
        total_err, total_bit = 0, 0
        for _ in range(num_channels):
            tx_bits, tx_samples, dmrs = transmit(num_symbols, qam_order, rng)
            faded, _h = multipath_tdlc(tx_samples, rng)
            rx_samples = awgn(faded, snr_db=snr, rng=rng)
            rx_bits = receive(rx_samples, dmrs, num_symbols, qam_order,
                              equaliser=equaliser, snr_lin=snr_lin)
            n = min(rx_bits.size, tx_bits.size)
            total_err += int(np.sum(tx_bits[:n] != rx_bits[:n]))
            total_bit += n
        ber = total_err / max(total_bit, 1)
        bers.append(ber)
        print(f"  TDL-C QAM{qam_order:>2}  EQ={equaliser:4s}  SNR={snr:5.1f} dB  BER={ber:.4e}")
    return np.array(bers)


def plot(snr_grid, curves: dict[str, np.ndarray], title: str, out_path: Path):
    plt.figure(figsize=(7, 5))
    for label, ber in curves.items():
        # Avoid log(0) by flooring tiny BER for plotting.
        ber_plot = np.maximum(ber, 1e-6)
        plt.semilogy(snr_grid, ber_plot, marker="o", label=label)
    plt.grid(True, which="both", linestyle=":")
    plt.xlabel("SNR (dB)")
    plt.ylabel("BER")
    plt.title(title)
    plt.legend()
    plt.ylim(1e-5, 1)
    plt.tight_layout()
    plt.savefig(out_path, dpi=140)
    plt.close()
    print(f"  saved {out_path.name}")


def main():
    rng = np.random.default_rng(2025)

    # --- AWGN sweep
    snr_awgn = np.arange(0, 21, 2)
    print("AWGN sweep:")
    ber_qpsk_awgn  = run_awgn(snr_awgn, qam_order=4,  num_symbols=200, rng=rng)
    ber_16qam_awgn = run_awgn(snr_awgn, qam_order=16, num_symbols=200, rng=rng)
    plot(snr_awgn,
         {"QPSK": ber_qpsk_awgn, "16-QAM": ber_16qam_awgn},
         "OFDM BER vs SNR — AWGN channel (LS chan est + ZF)",
         RESULTS_DIR / "ber_awgn.png")

    # --- Multipath sweep (TDL-C, ZF vs MMSE)
    snr_mp = np.arange(0, 31, 3)
    print("\nMultipath (TDL-C) sweep:")
    ber_qpsk_zf   = run_multipath(snr_mp, 4,  num_symbols=80, rng=rng, equaliser="zf",   num_channels=15)
    ber_qpsk_mmse = run_multipath(snr_mp, 4,  num_symbols=80, rng=rng, equaliser="mmse", num_channels=15)
    ber_16qam_zf  = run_multipath(snr_mp, 16, num_symbols=80, rng=rng, equaliser="zf",   num_channels=15)
    plot(snr_mp,
         {
             "QPSK, ZF":   ber_qpsk_zf,
             "QPSK, MMSE": ber_qpsk_mmse,
             "16-QAM, ZF": ber_16qam_zf,
         },
         "OFDM BER vs SNR — TDL-C multipath (LS chan est)",
         RESULTS_DIR / "ber_multipath.png")

    # --- CSV dump
    csv_path = RESULTS_DIR / "ber_results.csv"
    with open(csv_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["channel", "modulation", "equaliser", "snr_db", "ber"])
        for snr, b in zip(snr_awgn, ber_qpsk_awgn):  w.writerow(["AWGN",  "QPSK",   "ZF",   snr, f"{b:.6e}"])
        for snr, b in zip(snr_awgn, ber_16qam_awgn): w.writerow(["AWGN",  "16-QAM", "ZF",   snr, f"{b:.6e}"])
        for snr, b in zip(snr_mp,   ber_qpsk_zf):    w.writerow(["TDL-C", "QPSK",   "ZF",   snr, f"{b:.6e}"])
        for snr, b in zip(snr_mp,   ber_qpsk_mmse):  w.writerow(["TDL-C", "QPSK",   "MMSE", snr, f"{b:.6e}"])
        for snr, b in zip(snr_mp,   ber_16qam_zf):   w.writerow(["TDL-C", "16-QAM", "ZF",   snr, f"{b:.6e}"])
    print(f"\nResults written to {csv_path}")


if __name__ == "__main__":
    main()
