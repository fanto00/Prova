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
