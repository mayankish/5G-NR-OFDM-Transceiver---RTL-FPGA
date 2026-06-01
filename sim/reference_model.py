"""
OFDM 5G-NR-subset golden reference model.

Floating-point end-to-end TX/RX chain used to:
  1. Generate test vectors for the Verilog testbenches.
  2. Produce BER-vs-SNR curves that the RTL must track within ~1 dB.

Numerology (see docs/design_specification.md):
  N_FFT = 64, N_CP = 16, 52 data + 8 DMRS + 4 guard subcarriers.
  Sync : Zadoff-Chu root u=25, length 63.
  Modulation: QPSK or 16-QAM. Equaliser: one-tap ZF (with MMSE option).
"""

from __future__ import annotations

import numpy as np

# --------------------------------------------------------------------------- #
# Constants
# --------------------------------------------------------------------------- #
N_FFT      = 64
N_CP       = 16
N_SYM      = N_FFT + N_CP                 # 80
N_PILOT_SC = 8
N_GUARD_SC = 6                            # DC + Nyquist + 2 each band edge
PSS_LEN    = 63
PSS_ROOT_U = 25                           # NR PSS uses 25/29/34; we pick one

# Subcarrier indices (k in 0..63). Layout:
#   k = 0           : DC null
#   k = 1, 2        : lower-band guards
#   k = 32          : Nyquist-edge null
#   k = 62, 63      : upper-band guards
#   remaining 58    : active = 8 DMRS pilots + 50 data
ACTIVE_SC = np.array(
    [k for k in range(1, N_FFT)
       if k != N_FFT // 2
       and not (1 <= k <= 2)
       and not (N_FFT - 2 <= k <= N_FFT - 1)
    ]
)
# Pilot positions: every 8th active subcarrier, 8 pilots total.
PILOT_POS = ACTIVE_SC[::8][:N_PILOT_SC]
DATA_POS  = np.array([k for k in ACTIVE_SC if k not in PILOT_POS])
N_DATA_SC = len(DATA_POS)                 # = 50 with the layout above
assert N_DATA_SC == 50, f"DATA_POS={N_DATA_SC}"
assert len(PILOT_POS) == N_PILOT_SC, f"PILOT_POS={len(PILOT_POS)}"


# --------------------------------------------------------------------------- #
# Modulation
# --------------------------------------------------------------------------- #
def qam_mod(bits: np.ndarray, order: int) -> np.ndarray:
    """Gray-coded QPSK (order=4) or 16-QAM (order=16)."""
    if order == 4:                          # QPSK, 2 bits/sym, unit energy
        b = bits.reshape(-1, 2)
        i = 1 - 2 * b[:, 0]
        q = 1 - 2 * b[:, 1]
        return (i + 1j * q) / np.sqrt(2)
    if order == 16:                         # 16-QAM, 4 bits/sym, unit energy
        b = bits.reshape(-1, 4).astype(int)
        # Gray mapping per axis: 00→-3, 01→-1, 11→+1, 10→+3
        gray = {(0, 0): -3, (0, 1): -1, (1, 1): +1, (1, 0): +3}
        i = np.array([gray[(int(b[r, 0]), int(b[r, 1]))] for r in range(b.shape[0])])
        q = np.array([gray[(int(b[r, 2]), int(b[r, 3]))] for r in range(b.shape[0])])
        return (i + 1j * q) / np.sqrt(10)
    raise ValueError(f"Unsupported QAM order {order}")


def qam_demod(syms: np.ndarray, order: int) -> np.ndarray:
    """Hard-decision demap matching qam_mod."""
    if order == 4:
        bits = np.zeros((syms.size, 2), dtype=int)
        bits[:, 0] = (syms.real < 0).astype(int)
        bits[:, 1] = (syms.imag < 0).astype(int)
        return bits.reshape(-1)
    if order == 16:
        s = syms * np.sqrt(10)              # rescale to ±1, ±3 constellation
        inv_gray = {-3: (0, 0), -1: (0, 1), 1: (1, 1), 3: (1, 0)}
        def slice_axis(x):
            # Hard-decision slicer: thresholds at 0 and ±2.
            # No rounding — direct comparison against decision boundaries.
            return np.where(x >= 2, 3,
                   np.where(x >= 0, 1,
                   np.where(x >= -2, -1, -3))).astype(int)
        si = slice_axis(s.real)
        sq = slice_axis(s.imag)
        bits = np.zeros((syms.size, 4), dtype=int)
        for r in range(syms.size):
            bits[r, 0], bits[r, 1] = inv_gray[int(si[r])]
            bits[r, 2], bits[r, 3] = inv_gray[int(sq[r])]
        return bits.reshape(-1)
    raise ValueError(f"Unsupported QAM order {order}")


# --------------------------------------------------------------------------- #
# Pilots and PSS
# --------------------------------------------------------------------------- #
def dmrs_sequence() -> np.ndarray:
    """Deterministic pseudo-random QPSK pilot pattern.

    Real NR DMRS uses a Gold sequence seeded by cell/slot. We use a fixed
    seeded sequence so the TX and RX both know it — equivalent for our PoC.
    """
    rng = np.random.default_rng(seed=0xC0DE)
    bits = rng.integers(0, 2, size=2 * N_PILOT_SC)
    return qam_mod(bits, order=4)


def zadoff_chu(u: int, length: int) -> np.ndarray:
    """Generate ZC sequence of given odd length. Used for PSS."""
    n = np.arange(length)
    return np.exp(-1j * np.pi * u * n * (n + 1) / length)


PSS = zadoff_chu(PSS_ROOT_U, PSS_LEN).astype(np.complex64)


# --------------------------------------------------------------------------- #
# OFDM symbol assembly
# --------------------------------------------------------------------------- #
def build_ofdm_symbol(data_syms: np.ndarray, dmrs: np.ndarray) -> np.ndarray:
    """Place data + pilots on subcarriers and IFFT to time domain. Returns N_FFT samples (no CP)."""
    assert data_syms.size == N_DATA_SC
    grid = np.zeros(N_FFT, dtype=np.complex64)
    grid[DATA_POS]  = data_syms
    grid[PILOT_POS] = dmrs
    # Standard numpy IFFT: includes 1/N normalisation.  Round-trip with
    # np.fft.fft(td) recovers the original grid exactly.  This keeps the
    # time-domain power comparable to the PSS (unit-magnitude ZC), which is
    # critical for the sliding correlator to peak at the preamble.
    return np.fft.ifft(grid)


def add_cp(symbol_td: np.ndarray) -> np.ndarray:
    return np.concatenate([symbol_td[-N_CP:], symbol_td])


def remove_cp(symbol_td_with_cp: np.ndarray) -> np.ndarray:
    return symbol_td_with_cp[N_CP:]


# --------------------------------------------------------------------------- #
# Channel models
# --------------------------------------------------------------------------- #
def awgn(samples: np.ndarray, snr_db: float, rng: np.random.Generator) -> np.ndarray:
    sig_pwr = np.mean(np.abs(samples) ** 2)
    snr_lin = 10 ** (snr_db / 10)
    n_pwr = sig_pwr / snr_lin
    noise = (rng.standard_normal(samples.size) + 1j * rng.standard_normal(samples.size))
    noise *= np.sqrt(n_pwr / 2)
    return samples + noise


# TDL-C (truncated to 4 taps for hardware-realistic short channel)
# Delays in samples, power profile in dB. Values chosen to give a moderately
# selective channel that still equalises well after DMRS estimation.
TDL_C_DELAYS  = np.array([0, 2, 5, 9])
TDL_C_POW_DB  = np.array([0.0, -3.0, -6.0, -9.0])

def multipath_tdlc(samples: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """Block-fading TDL-C: draw Rayleigh-distributed complex taps and convolve."""
    p_lin = 10 ** (TDL_C_POW_DB / 10)
    p_lin /= p_lin.sum()
    taps = (rng.standard_normal(len(TDL_C_DELAYS)) +
            1j * rng.standard_normal(len(TDL_C_DELAYS))) * np.sqrt(p_lin / 2)
    h = np.zeros(int(TDL_C_DELAYS.max()) + 1, dtype=np.complex64)
    for d, t in zip(TDL_C_DELAYS, taps):
        h[d] = t
    return np.convolve(samples, h)[: samples.size], h


# --------------------------------------------------------------------------- #
# Receiver
# --------------------------------------------------------------------------- #
def pss_correlate(samples: np.ndarray) -> int:
    """Sliding correlator against the known PSS.

    Returns the index of the first sample *after* the PSS, i.e. where the
    first OFDM symbol's CP begins.

    np.convolve(samples, conj(PSS[::-1]), mode='valid') with output index v
    corresponds to a correlation at sample-offset v (i.e. the PSS template
    aligned with samples[v : v+PSS_LEN]). So the peak index is the start of
    the PSS, and the first post-PSS sample is at peak + PSS_LEN.
    """
    pss_conj = np.conj(PSS[::-1])
    corr = np.convolve(samples, pss_conj, mode="valid")
    pss_start = int(np.argmax(np.abs(corr)))
    return pss_start + PSS_LEN


def ls_channel_estimate(rx_grid: np.ndarray, tx_dmrs: np.ndarray) -> np.ndarray:
    """LS estimate at pilot positions, linear interpolation across all subcarriers."""
    h_pilot = rx_grid[PILOT_POS] / tx_dmrs
    # Interpolate magnitude and phase separately for numerical stability.
    k_all = np.arange(N_FFT)
    h_full = np.interp(k_all, PILOT_POS, h_pilot.real) + \
             1j * np.interp(k_all, PILOT_POS, h_pilot.imag)
    return h_full


def zf_equalize(rx_grid: np.ndarray, h_est: np.ndarray) -> np.ndarray:
    eps = 1e-12
    return rx_grid / (h_est + eps)


def mmse_equalize(rx_grid: np.ndarray, h_est: np.ndarray, snr_lin: float) -> np.ndarray:
    """Reference MMSE equaliser for the BER curve."""
    return np.conj(h_est) * rx_grid / (np.abs(h_est) ** 2 + 1.0 / snr_lin)


# --------------------------------------------------------------------------- #
# Full chain
# --------------------------------------------------------------------------- #
def transmit(num_symbols: int, qam_order: int, rng: np.random.Generator):
    """Returns (tx_bits, tx_samples_with_cp_and_pss)."""
    dmrs = dmrs_sequence()
    bits_per_sc = int(np.log2(qam_order))
    tx_bits = rng.integers(0, 2, size=num_symbols * N_DATA_SC * bits_per_sc)
    tx_syms = qam_mod(tx_bits, qam_order).reshape(num_symbols, N_DATA_SC)

    samples = []
    samples.append(PSS)                                     # frame preamble
    for s in range(num_symbols):
        td = build_ofdm_symbol(tx_syms[s], dmrs)
        samples.append(add_cp(td))
    return tx_bits, np.concatenate(samples).astype(np.complex64), dmrs


def receive(samples: np.ndarray, dmrs: np.ndarray, num_symbols: int, qam_order: int,
            equaliser: str = "zf", snr_lin: float | None = None) -> np.ndarray:
    """Returns rx_bits."""
    start = pss_correlate(samples)                          # first sample of first symbol

    rx_bits = []
    for s in range(num_symbols):
        sym = samples[start + s * N_SYM : start + (s + 1) * N_SYM]
        if sym.size < N_SYM:
            # Pad with zeros so demod still produces some bits — keeps shape.
            sym = np.concatenate([sym, np.zeros(N_SYM - sym.size, dtype=np.complex64)])
        td = remove_cp(sym)
        grid = np.fft.fft(td)
        h_est = ls_channel_estimate(grid, dmrs)
        if equaliser == "zf":
            eq = zf_equalize(grid, h_est)
        elif equaliser == "mmse":
            assert snr_lin is not None
            eq = mmse_equalize(grid, h_est, snr_lin)
        else:
            raise ValueError(equaliser)
        rx_bits.append(qam_demod(eq[DATA_POS], qam_order))
    return np.concatenate(rx_bits)


# --------------------------------------------------------------------------- #
# Quick self-test
# --------------------------------------------------------------------------- #
if __name__ == "__main__":
    rng = np.random.default_rng(42)
    bits, tx_samples, dmrs = transmit(num_symbols=4, qam_order=4, rng=rng)
    # Noiseless AWGN sanity check
    rx_bits = receive(tx_samples, dmrs, num_symbols=4, qam_order=4)
    errs = np.sum(bits != rx_bits)
    print(f"[self-test] noiseless: {errs} bit errors out of {bits.size}")
