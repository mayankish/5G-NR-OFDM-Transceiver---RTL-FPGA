"""Generate Verilog $readmemh files for the Zadoff-Chu PSS (u=25, L=63).

Outputs two files into rtl/tx/ AND rtl/rx/ (since both pss_gen and
pss_correlator $readmemh the same data):
  pss_zc_u25_L63.mem      — Q1.15 real parts, one 16-bit hex per line
  pss_zc_u25_L63_im.mem   — Q1.15 imag parts, one 16-bit hex per line
"""
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [ROOT / "rtl" / "tx", ROOT / "rtl" / "rx"]

u, L = 25, 63
n = np.arange(L)
s = np.exp(-1j * np.pi * u * n * (n + 1) / L)

scale = 2**15 - 1
re = np.round(s.real * scale).astype(int).clip(-32768, 32767) & 0xFFFF
im = np.round(s.imag * scale).astype(int).clip(-32768, 32767) & 0xFFFF

for d in TARGETS:
    d.mkdir(parents=True, exist_ok=True)
    (d / "pss_zc_u25_L63.mem").write_text("\n".join(f"{v:04x}" for v in re) + "\n")
    (d / "pss_zc_u25_L63_im.mem").write_text("\n".join(f"{v:04x}" for v in im) + "\n")
    print(f"wrote PSS mem files to {d}")
