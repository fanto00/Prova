"""Scalar signal helpers (port of app.m helper functions).

Pure functions over the dict-based data model. Reuses Piano 1 primitives.
"""
from __future__ import annotations

import numpy as np

from railway_inspector.detection.trigger import movmean
from railway_inspector.signal.alignment import shift_signal_frac


def get_amp(F: dict, sensor_name: str) -> float:
    """max(abs(signal)), or 0 if missing/empty/all-zero (app.m:7180)."""
    if sensor_name in F:
        sig = np.asarray(F[sensor_name], dtype=float).reshape(-1)
        if sig.size > 0 and np.any(sig != 0):
            return float(np.max(np.abs(sig)))
    return 0.0


def get_max_rms(F: dict, sensor_name: str, win_samples: int) -> float:
    """max of moving-RMS, falling back to max(abs) for short signals (app.m:7164)."""
    if sensor_name in F:
        sig = np.asarray(F[sensor_name], dtype=float).reshape(-1)
        if sig.size > 0 and np.any(sig != 0):
            if sig.size >= win_samples:
                rms_sig = np.sqrt(movmean(sig**2, win_samples))
                return float(np.max(rms_sig))
            return float(np.max(np.abs(sig)))
    return 0.0


def safe_ratio(a: float, b: float) -> float:
    """a/b with MATLAB guards: 1.0 if both ~0, 999 if only denom ~0 (app.m:7357)."""
    if b < 1e-6:
        if a < 1e-6:
            return 1.0
        return 999
    return a / b


def get_sign_mean(Defect: dict, sens1: str, sens2: str) -> float:
    """Sign of the mean center value, averaged over runs and the two sensors.

    Port of app.m:7383. Empty result falls back to +1.
    """
    vals: list[float] = []
    for run in Defect.get("History", []):
        data = run.get("Data", {})
        if "Filt" not in data:
            continue
        F = data["Filt"]
        for sn in (sens1, sens2):
            if sn in F:
                sig = np.asarray(F[sn], dtype=float).reshape(-1)
                if sig.size > 0:
                    N = sig.size
                    mid0 = (N + 1) // 2 - 1          # MATLAB round(N/2), 1-based -> 0-based
                    half = min(5, N // 4)            # floor(length/4)
                    seg = sig[mid0 - half: mid0 + half + 1]
                    vals.append(float(np.mean(seg)))
    if not vals:
        return 1
    return float(np.sign(np.mean(vals)))


def _rms_finite(F: dict, field: str) -> float:
    """Population RMS over finite samples, 0 if missing/empty (app.m fallback)."""
    if field in F:
        s = np.asarray(F[field], dtype=float).reshape(-1)
        s = s[np.isfinite(s)]
        if s.size > 0:
            return float(np.sqrt(np.mean(s**2)))
    return 0.0


def sort_runs_by_direction(History: list) -> tuple[np.ndarray, np.ndarray]:
    """Split runs into forward/backward boolean masks (app.m:6524).

    Uses the run/Data ``orientation`` string if present, else falls back to
    comparing front lateral RMS (right>left -> forward). Ties stay False.
    """
    n_runs = len(History)
    idx_fwd = np.zeros(n_runs, dtype=bool)
    idx_bwd = np.zeros(n_runs, dtype=bool)
    for i, run_i in enumerate(History):
        d = run_i.get("Data", {})
        if "Filt" not in d:
            continue
        Fd = d["Filt"]
        ori = ""
        if run_i.get("orientation"):
            ori = str(run_i["orientation"]).strip().lower()
        elif d.get("orientation"):
            ori = str(d["orientation"]).strip().lower()
        if "forward" in ori:
            idx_fwd[i] = True
        elif "backward" in ori:
            idx_bwd[i] = True
        else:
            rms_r = _rms_finite(Fd, "right_sensor_front_lat")
            rms_l = _rms_finite(Fd, "left_sensor_front_lat")
            if rms_r > rms_l:
                idx_fwd[i] = True
            elif rms_l > rms_r:
                idx_bwd[i] = True
    return idx_fwd, idx_bwd


def helper_fft_shift(sig, shift_m: float, spatial_res: float):
    """Fractional FFT phase shift. Exact alias of signal.alignment.shift_signal_frac
    (the DB-creator function the MATLAB source delegates to). See app.m:1846."""
    sig = np.asarray(sig, dtype=float).reshape(-1)
    if sig.size <= 1:
        return sig
    return shift_signal_frac(sig, shift_m, spatial_res)
