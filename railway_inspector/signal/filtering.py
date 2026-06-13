"""
Signal filtering utilities — faithful to the MATLAB pipeline in
Database_Allineamento_nomax.m (lines 855-880 and 1073-1094).

Functions
---------
design_filters(cfg, fs_time)
    Design the temporal and spatial Butterworth bandpass filters.
filter_pipeline(sig_raw, axis, common_space_axis, cfg, fs_time)
    Apply the full FILT pipeline: demean → temporal filtfilt →
    spatial resampling → spatial filtfilt.
"""

import numpy as np
from scipy.signal import butter, filtfilt

from railway_inspector.signal.resampling import interp1_zero


def design_filters(cfg, fs_time: float):
    """Design temporal and spatial Butterworth bandpass filters.

    Replicates MATLAB:
        [bT, aT] = butter(2, [fmin, fmax]/(fs_time/2),     'bandpass')
        [bQ, aQ] = butter(2, [1/L_MAX, 1/L_MIN_QUIET]/(fs_space_res/2), 'bandpass')
    where fs_space_res = 1/SPATIAL_RES.

    Parameters
    ----------
    cfg : CFG
        Configuration object with fmin, fmax, L_MAX, L_MIN_QUIET, SPATIAL_RES.
    fs_time : float
        Temporal sampling rate in Hz (MATLAB fs_time = 1000).

    Returns
    -------
    bT, aT : ndarray
        Numerator / denominator of the temporal bandpass filter.
    bQ, aQ : ndarray
        Numerator / denominator of the spatial bandpass filter.
    """
    fs_space_res = 1.0 / cfg.SPATIAL_RES  # MATLAB: fs_space_res = 1/SPATIAL_RES

    bT, aT = butter(2, [cfg.fmin, cfg.fmax] / np.array(fs_time / 2.0), btype="bandpass")
    bQ, aQ = butter(2, [1.0 / cfg.L_MAX, 1.0 / cfg.L_MIN_QUIET] / np.array(fs_space_res / 2.0),
                    btype="bandpass")

    return bT, aT, bQ, aQ


def filter_pipeline(
    sig_raw: np.ndarray,
    axis: np.ndarray,
    common_space_axis: np.ndarray,
    cfg,
    fs_time: float,
) -> np.ndarray:
    """Apply the FILT signal pipeline, replicating MATLAB lines 875-878.

    Pipeline (exact order):
        1. sig_dem  = sig_raw - nanmean(sig_raw)          [demean, omitnan]
        2. sig_t    = filtfilt(bT, aT, sig_dem)           [zero-phase temporal bandpass]
        3. unique-stable on axis → ax_u, idx_u
        4. sig_sp   = interp1_zero(ax_u, sig_t[idx_u], common_space_axis)
                                                           [resample to spatial axis]
        5. sig_f    = filtfilt(bQ, aQ, sig_sp)            [zero-phase spatial bandpass]

    Parameters
    ----------
    sig_raw : array_like, shape (N,)
        Raw signal samples (temporal domain).
    axis : array_like, shape (N,)
        Spatial axis corresponding to sig_raw (may contain duplicates).
    common_space_axis : array_like, shape (M,)
        Uniformly-spaced target spatial axis.
    cfg : CFG
        Configuration object.
    fs_time : float
        Temporal sampling rate in Hz.

    Returns
    -------
    sig_f : ndarray, shape (M,)
        Filtered signal on common_space_axis.
    """
    sig_raw = np.asarray(sig_raw, dtype=float)
    axis = np.asarray(axis, dtype=float)
    common_space_axis = np.asarray(common_space_axis, dtype=float)

    bT, aT, bQ, aQ = design_filters(cfg, fs_time)

    # Step 1 — demean (MATLAB: mean(..., 'omitnan'))
    sig_dem = sig_raw - np.nanmean(sig_raw)

    # Step 2 — zero-phase temporal bandpass
    sig_t = filtfilt(bT, aT, sig_dem)

    # Step 3 — unique-stable: remove duplicate axis points, keep first occurrence
    # Replicates MATLAB: [ax_u, idx_u] = unique(cur_ax, 'stable')
    _, idx_u = np.unique(axis, return_index=True)
    idx_u = np.sort(idx_u)          # stable = original (ascending-index) order
    ax_u = axis[idx_u]

    # Step 4 — resample to common spatial axis
    sig_sp = interp1_zero(ax_u, sig_t[idx_u], common_space_axis)

    # Step 5 — zero-phase spatial bandpass
    sig_f = filtfilt(bQ, aQ, sig_sp)

    return sig_f
