"""
detection/trigger.py
====================
Replicates the MATLAB detection logic from Database_Allineamento_nomax.m
lines 852–934 (analyze_and_extract / detection block).

Public API
----------
movmean(x, k)                        -- MATLAB-compatible centered moving average
detect_peaks_on_signal(sig, axis, c) -- per-signal RMS envelope trigger
merge_detections(det_locs, cross_tol)-- MATLAB merging loop
"""

from __future__ import annotations

import numpy as np
from scipy.signal import find_peaks


# ---------------------------------------------------------------------------
# MATLAB movmean replica
# ---------------------------------------------------------------------------

def movmean(x: np.ndarray, k: int) -> np.ndarray:
    """Centered moving average matching MATLAB movmean(A, k).

    Window placement:
      - Odd  k: symmetric,  half = (k-1)//2  elements on each side.
      - Even k: asymmetric, floor((k-1)/2) elements BEFORE, floor(k/2) AFTER.

    At boundaries the window is truncated to available samples (no zero-padding),
    exactly as MATLAB does.

    Parameters
    ----------
    x : 1-D array
    k : window length (positive integer)

    Returns
    -------
    out : same shape as x, dtype float64
    """
    x = np.asarray(x, dtype=np.float64)
    n = len(x)
    out = np.empty(n, dtype=np.float64)

    # Number of elements before and after centre (MATLAB convention)
    before = (k - 1) // 2          # floor((k-1)/2)
    after  = k // 2                 # floor(k/2)

    for i in range(n):
        lo = max(0, i - before)
        hi = min(n - 1, i + after)
        out[i] = x[lo: hi + 1].mean()

    return out


# ---------------------------------------------------------------------------
# Per-signal detection  (MATLAB lines 885-916)
# ---------------------------------------------------------------------------

def detect_peaks_on_signal(
    sig_det: np.ndarray,
    axis_det: np.ndarray,
    cfg,
) -> tuple[np.ndarray, np.ndarray]:
    """Replicate the MATLAB per-signal detection block (lines 885-916).

    Parameters
    ----------
    sig_det  : 1-D filtered signal (spatial domain)
    axis_det : spatial axis in metres, same length as sig_det
    cfg      : CFG dataclass (railway_inspector.config)

    Returns
    -------
    positions : 1-D array of detection positions in metres (axis_det values)
    amplitudes: 1-D array of abs(sig_det) at each refined location
    """
    sig_det  = np.asarray(sig_det,  dtype=np.float64)
    axis_det = np.asarray(axis_det, dtype=np.float64)

    N_f = int(round(cfg.RMS_WIN_FAST / cfg.SPATIAL_RES))
    N_f = max(N_f, 1)  # guard against degenerate window

    # Fast RMS envelope  (MATLAB: sqrt(movmean(sig_det.^2, N_f)))
    env = np.sqrt(movmean(sig_det ** 2, N_f))

    # Slow background threshold
    N_s = int(round(cfg.RMS_WIN_SLOW / cfg.SPATIAL_RES))
    N_s = max(N_s, 1)
    th_bkg = movmean(env, N_s)

    # Dynamic threshold  (MATLAB: max(th_bkg * RMS_MUL, 0.05))
    th_dynamic = np.maximum(th_bkg * cfg.RMS_MUL, 0.05)

    # Peak finding on envelope
    # scipy find_peaks excludes endpoints (same as MATLAB findpeaks)
    min_dist_samples = int(round(cfg.MIN_DIST / cfg.SPATIAL_RES))
    pks_idx, _ = find_peaks(env, distance=max(min_dist_samples, 1))

    if pks_idx.size == 0:
        return np.array([]), np.array([])

    pks = env[pks_idx]

    # Validity filter
    valid_mask = (pks > th_dynamic[pks_idx]) & (pks > cfg.ABS_RMS_THRESH)
    valid_locs = pks_idx[valid_mask]   # 0-based indices into sig_det

    if valid_locs.size == 0:
        return np.array([]), np.array([])

    # Peak refinement: search within ±search_radius samples for argmax(|sig_det|)
    # Replicates MATLAB lines 897-910 (converting 1-based to 0-based)
    search_radius = int(round(5.0 / cfg.SPATIAL_RES))
    refined_locs = np.empty(len(valid_locs), dtype=np.intp)

    for j, c_loc in enumerate(valid_locs):
        # MATLAB: start_idx = max(1, c_loc - radius)  (1-based)
        #  => Python: max(0, c_loc - radius)
        start_idx = max(0, c_loc - search_radius)
        end_idx   = min(len(sig_det) - 1, c_loc + search_radius)
        segment   = np.abs(sig_det[start_idx: end_idx + 1])
        max_local_idx = int(np.argmax(segment))
        # MATLAB: refined = start_idx + max_local_idx - 1  (1-based)
        # Python: start_idx + max_local_idx               (0-based)
        refined_locs[j] = start_idx + max_local_idx

    positions  = axis_det[refined_locs]
    amplitudes = np.abs(sig_det[refined_locs])

    return positions, amplitudes


# ---------------------------------------------------------------------------
# Detection merging  (MATLAB lines 921-934)
# ---------------------------------------------------------------------------

def merge_detections(det_locs: np.ndarray, cross_tol: float) -> np.ndarray:
    """Replicate MATLAB merging loop (lines 921-934).

    Parameters
    ----------
    det_locs  : Nx2 array, col-0 = position (m), col-1 = amplitude.
                Will be sorted by position internally (matching MATLAB sortrows).
    cross_tol : maximum gap between detections to merge (C.CROSS_TOL)

    Returns
    -------
    merged : Mx2 array after merging
    """
    det_locs = np.asarray(det_locs, dtype=np.float64)
    if det_locs.ndim == 1:
        det_locs = det_locs.reshape(1, 2)

    # MATLAB: det_locs = sortrows(det_locs, 1)
    order = np.argsort(det_locs[:, 0], kind='stable')
    det_locs = det_locs[order]

    rows = []
    cp = det_locs[0, 0]
    ma = det_locs[0, 1]

    for i in range(1, len(det_locs)):
        pos_i = det_locs[i, 0]
        amp_i = det_locs[i, 1]

        if pos_i - cp <= cross_tol:
            # Within tolerance: keep higher amplitude and its position
            if amp_i > ma:
                ma = amp_i
                cp = pos_i
        else:
            rows.append([cp, ma])
            cp = pos_i
            ma = amp_i

    rows.append([cp, ma])

    return np.array(rows, dtype=np.float64)
