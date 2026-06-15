"""PCA-based IPI bonus (port of app.m:6650-6836).

Channel-space ("parallel") PCA over per-channel RMS envelopes, plus the
RMSE-trend and excursion bonus computation. Pure NumPy, no GUI.
"""
from __future__ import annotations

import datetime as dt

import numpy as np

from railway_inspector.detection.trigger import movmean
from railway_inspector.signal.resampling import interp1_nan
from railway_inspector.app.utils.helpers import sort_runs_by_direction
from railway_inspector.app.analysis.spectrum import _matlab_round_pos


def _datenum(date: dt.datetime) -> float:
    """MATLAB datenum-like day count (relative use only: differences + floor)."""
    if isinstance(date, dt.datetime):
        frac = (date - dt.datetime(date.year, date.month, date.day)).total_seconds() / 86400.0
        return date.toordinal() + frac
    return dt.datetime(date.year, date.month, date.day).toordinal()


def _group_mean(group_id: np.ndarray, values: np.ndarray, n_groups: int) -> np.ndarray:
    """accumarray(group_id, values, [n_groups 1], @mean) — per-group mean."""
    group_id = np.asarray(group_id, dtype=int)
    values = np.asarray(values, dtype=float)
    sums = np.bincount(group_id, weights=values, minlength=n_groups)
    counts = np.bincount(group_id, minlength=n_groups)
    counts_safe = np.where(counts == 0, 1, counts)
    return sums / counts_safe


def _matlab_pca(X: np.ndarray):
    """Replicate MATLAB pca(X, 'Economy', true) -> (coeffs, scores).

    Centers columns, SVD, coeffs = right singular vectors, scores = Xc @ coeffs,
    with MATLAB's sign convention (largest-magnitude coeff element positive).
    """
    X = np.asarray(X, dtype=float)
    Xc = X - X.mean(axis=0)
    U, S, Vt = np.linalg.svd(Xc, full_matrices=False)
    coeffs = Vt.T
    scores = U * S
    for j in range(coeffs.shape[1]):
        idx = int(np.argmax(np.abs(coeffs[:, j])))
        if coeffs[idx, j] < 0:
            coeffs[:, j] = -coeffs[:, j]
            scores[:, j] = -scores[:, j]
    return coeffs, scores


def build_pca_model_standalone(History, run_idx, direction, spatial_res,
                               window_size, win_m, MIN_RUNS, k_pca):
    """Channel-space PCA model over per-channel RMS envelopes (app.m:6650).

    Returns a dict with keys coeffs, scores, dates, rmse, n_valid, or None on
    any early exit (too few runs, bad direction, decomposition failure).
    """
    n_sel = len(run_idx)
    if n_sel < MIN_RUNS:
        return None
    N_GRID = 333
    n_chan = 6
    x_grid = np.linspace(-window_size, window_size, N_GRID)
    win_samples = max(3, _matlab_round_pos(win_m / spatial_res))

    dir_l = direction.lower()
    if dir_l == "forward":
        lat_F_field, lat_R_field = "right_sensor_front_lat", "right_sensor_rear_lat"
    elif dir_l == "backward":
        lat_F_field, lat_R_field = "left_sensor_front_lat", "left_sensor_rear_lat"
    else:
        return None
    chan_fields = ["left_sensor_front", "right_sensor_front", lat_F_field,
                   "left_sensor_rear", "right_sensor_rear", lat_R_field]

    Xraw = np.full((n_sel, n_chan * N_GRID), np.nan)
    dates_v = np.full(n_sel, np.nan)
    valid_v = np.zeros(n_sel, dtype=bool)

    for k in range(n_sel):
        run_i = History[run_idx[k]]
        dates_v[k] = _datenum(run_i["Date"])
        d = run_i["Data"]
        if "Filt" not in d:
            continue
        if "RelativeAxis" not in d or len(d["RelativeAxis"]) == 0:
            continue
        ax_src = np.asarray(d["RelativeAxis"], dtype=float).reshape(-1)
        if not np.all(np.diff(ax_src) >= 0) or np.any(~np.isfinite(ax_src)):
            continue
        Fd = d["Filt"]
        row = np.full(n_chan * N_GRID, np.nan)
        row_ok = True
        for c in range(n_chan):
            fn = chan_fields[c]
            if fn not in Fd or len(Fd[fn]) == 0:
                row_ok = False
                break
            sig = np.asarray(Fd[fn], dtype=float).reshape(-1)
            if sig.size != ax_src.size or sig.size < 10:
                row_ok = False
                break
            env = np.sqrt(movmean(sig**2, win_samples))
            env_g = interp1_nan(ax_src, env, x_grid)
            if np.any(~np.isfinite(env_g)):
                row_ok = False
                break
            row[c * N_GRID:(c + 1) * N_GRID] = env_g
        if row_ok:
            Xraw[k, :] = row
            valid_v[k] = True

    Xraw = Xraw[valid_v, :]
    dates_v = dates_v[valid_v]
    n_valid = Xraw.shape[0]
    if n_valid < MIN_RUNS:
        return None

    # Parallel rearrangement: rows = (run x position), columns = channel
    Nrows = n_valid * N_GRID
    Xpar = np.zeros((Nrows, n_chan))
    run_id = np.zeros(Nrows, dtype=int)
    for r in range(n_valid):
        base = r * N_GRID
        run_id[base:base + N_GRID] = r
        for c in range(n_chan):
            Xpar[base:base + N_GRID, c] = Xraw[r, c * N_GRID:(c + 1) * N_GRID]

    mu_ch = np.mean(Xpar, axis=0)
    sg_ch = np.std(Xpar, axis=0, ddof=1)
    sg_ch[sg_ch < 1e-9] = 1
    Xpar_z = (Xpar - mu_ch) / sg_ch

    try:
        coeffs, scores = _matlab_pca(Xpar_z)
    except np.linalg.LinAlgError:
        return None

    k_use = min(k_pca, coeffs.shape[1])
    resid_z = scores[:, k_use:] @ coeffs[:, k_use:].T
    se_row = np.mean(resid_z**2, axis=1)
    rmse_run = np.sqrt(_group_mean(run_id, se_row, n_valid))

    P = scores.shape[1]
    scores_run = np.zeros((n_valid, P))
    for j in range(P):
        scores_run[:, j] = _group_mean(run_id, scores[:, j], n_valid)

    ord_ = np.argsort(dates_v, kind="stable")
    return {
        "coeffs": coeffs,
        "scores": scores_run[ord_, :],
        "dates": dates_v[ord_],
        "rmse": rmse_run[ord_],
        "n_valid": n_valid,
    }
