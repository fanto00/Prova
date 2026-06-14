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


def _matlab_round_pos(x: float) -> int:
    """Round half-away-from-zero for non-negative x (MATLAB round)."""
    return int(np.floor(x + 0.5))


def get_spectrum_psd(F: dict, sensor_list, weights, cfg):
    """Amplitude-weighted mean one-sided PSD over a sensor list (app.m:7191).

    Returns (psd_mean, freq_vec) as np.ndarray, or (None, None) when no sensor
    contributed. Fixed 10 m analysis window -> NFFT = round(10 / SPATIAL_RES).
    """
    win_m = 10.0
    dx_global = cfg.SPATIAL_RES
    fs_global = 1.0 / dx_global
    nfft = _matlab_round_pos(win_m / dx_global)
    if nfft < 4:
        nfft = 4

    psd_sum = None
    freq_vec = None
    total_weight = 0.0

    for sn, w in zip(sensor_list, weights):
        if w < 1e-6 or sn not in F:
            continue
        sig = np.asarray(F[sn], dtype=float).reshape(-1)
        if sig.size == 0 or sig.size < 4:
            continue

        n_campioni = sig.size
        if n_campioni > nfft:
            start0 = (n_campioni - nfft) // 2     # floor((N-NFFT)/2), 1-based -> 0-based
            sig = sig[start0:start0 + nfft]

        win = hamming(sig.size, sym=True)
        f, pxx = periodogram(sig, fs=fs_global, window=win, nfft=nfft,
                             detrend=False, return_onesided=True, scaling="density")

        if freq_vec is None:
            freq_vec = f
            psd_sum = np.zeros_like(pxx)

        if f.shape[0] != freq_vec.shape[0]:
            pxx = interp1_zero(f, pxx, freq_vec)

        psd_sum = psd_sum + pxx * w
        total_weight += w

    if psd_sum is None or total_weight < 1e-6:
        return None, None
    return psd_sum / total_weight, freq_vec
