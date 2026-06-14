"""Weighted PSD spectrum and dominant-wavelength extraction (port of app.m)."""
from __future__ import annotations

import numpy as np
from scipy.signal import periodogram
from scipy.signal.windows import hamming

from railway_inspector.signal.resampling import interp1_zero


def lambda_to_label(lambda_: float, L_giunto: float, L_irreg: float, L_deform: float) -> str:
    """Map a dominant wavelength to a qualitative class label (app.m:7369)."""
    if lambda_ <= 0:
        return "N/D"
    if lambda_ < L_giunto:
        return "Corto"
    if lambda_ < L_irreg:
        return "medio"
    if lambda_ < L_deform:
        return "lungo"
    return "molto lungo"


def peak_lambda_from_spectrum(spectrum, freq_vec, total_weight: float, cfg) -> float:
    """Dominant wavelength from the summed spectrum peak in the band of interest
    [1/L_MAX, 1/L_MIN_QUIET] (app.m:7335). Returns 0 when undefined."""
    if spectrum is None or len(spectrum) == 0 or total_weight < 1e-6:
        return 0
    spectrum = np.asarray(spectrum, dtype=float).reshape(-1)
    freq_vec = np.asarray(freq_vec, dtype=float).reshape(-1)

    f_min_band = 1 / cfg.L_MAX
    f_max_band = 1 / cfg.L_MIN_QUIET
    mask_band = (freq_vec >= f_min_band) & (freq_vec <= f_max_band)
    if not np.any(mask_band):
        return 0

    idx_peak = int(np.argmax(spectrum[mask_band]))   # first max, like MATLAB
    f_dom = freq_vec[mask_band][idx_peak]
    if f_dom > 0:
        return 1 / f_dom
    return 0
