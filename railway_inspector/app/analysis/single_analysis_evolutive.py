"""Pure functions for evolutive (multi-run) amplitude-ratio analysis.

Translated from MATLAB app.m:
  - Ratio computation  : lines 2145-2147
  - update_evolutive_plots() : lines 4258-4384

No plotting, no UI callbacks, no RawDataStore access.
"""
from __future__ import annotations

from datetime import datetime
from typing import List, Tuple

import numpy as np

# Re-use the date helpers that already live in single_analysis_psd (same epoch,
# same weekly-grouping convention).  Imported here so callers only need one
# import; also re-exported for convenience.
from railway_inspector.app.analysis.single_analysis_psd import (
    _datenum_to_datetime,       # noqa: F401 – re-export
    _datetime_to_datenum,       # noqa: F401 – re-export
    _round_datetime_to_period,  # noqa: F401 – re-export
)


# ---------------------------------------------------------------------------
# 1. compute_amplitude_ratios
# ---------------------------------------------------------------------------

def compute_amplitude_ratios(
    defect_history: List[dict],
    all_amps: np.ndarray,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Compute per-run amplitude ratios (MATLAB app.m lines 2145-2147).

    Parameters
    ----------
    defect_history : list of dicts (one entry per run; used only for length).
    all_amps : ndarray, shape (n_runs, 8)
        Column layout (0-based, matching MATLAB 1-based cols 1-8):
          0: SX_F   (left front)
          1: SX_R   (left rear)
          2: DX_F   (right front)
          3: DX_R   (right rear)
          4-7: lateral sensors (LAT_0 … LAT_3)

    Returns
    -------
    ratio_sx_dx : ndarray, shape (n_runs,)
        (A_SX_F + A_SX_R) / max(A_DX_F + A_DX_R, 1e-6)
    ratio_fr : ndarray, shape (n_runs,)
        (A_SX_F + A_DX_F) / max(A_SX_R + A_DX_R, 1e-6)
    ratio_lv : ndarray, shape (n_runs,)
        A_LAT_MAX / max(A_VERT_MAX, 1e-6)
        where A_LAT_MAX  = max(cols 4-7)   per row
              A_VERT_MAX = max(cols 0-3)   per row
    """
    amps = np.asarray(all_amps, dtype=float)
    n_runs = amps.shape[0]

    # Column aliases (0-based)
    a_sx_f = amps[:, 0]  # SX_F
    a_sx_r = amps[:, 1]  # SX_R
    a_dx_f = amps[:, 2]  # DX_F
    a_dx_r = amps[:, 3]  # DX_R

    # A_LAT_MAX: max across lateral sensors (cols 4-7); nanmax ignores NaN
    a_lat_max = np.nanmax(amps[:, 4:8], axis=1)

    # A_VERT_MAX: max across vertical sensors (cols 0-3)
    a_vert_max = np.nanmax(amps[:, 0:4], axis=1)

    # MATLAB line 2145
    denom_sx_dx = np.maximum(a_dx_f + a_dx_r, 1e-6)
    ratio_sx_dx = (a_sx_f + a_sx_r) / denom_sx_dx

    # MATLAB line 2146
    denom_fr = np.maximum(a_sx_r + a_dx_r, 1e-6)
    ratio_fr = (a_sx_f + a_dx_f) / denom_fr

    # MATLAB line 2147
    denom_lv = np.maximum(a_vert_max, 1e-6)
    ratio_lv = a_lat_max / denom_lv

    return ratio_sx_dx, ratio_fr, ratio_lv


# ---------------------------------------------------------------------------
# 2. compute_evolutive_metrics
# ---------------------------------------------------------------------------

def compute_evolutive_metrics(
    defect_history: List[dict],
    ratio_sx_dx: np.ndarray,
    ratio_fr: np.ndarray,
    ratio_lv: np.ndarray,
    lambda_all: np.ndarray,
    dates_num: np.ndarray,
    grouping_mode: str = 'daily',
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, List]:
    """Aggregate per-run ratios into temporal periods (MATLAB lines 4258-4296).

    Replicates MATLAB logic:
        dates_rounded = dateshift(all_dates_dt, 'start', <period>)
        [unique_periods, ~, ic] = unique(dates_rounded)   % sorted
        for k = 1:n_periods
            mask = (ic == k)
            avg_Ratio_SX_DX(k) = mean(Ratio_SX_DX(mask), 'omitnan')
            ...
        end

    Parameters
    ----------
    defect_history : list of dicts (one per run; unused beyond implicit length).
    ratio_sx_dx   : ndarray, shape (n_runs,)
    ratio_fr      : ndarray, shape (n_runs,)
    ratio_lv      : ndarray, shape (n_runs,)
    lambda_all    : ndarray, shape (n_runs, 8)
    dates_num     : ndarray, shape (n_runs,) – MATLAB datenum values
    grouping_mode : str – one of 'run', 'daily', 'weekly', 'monthly'

    Returns
    -------
    avg_ratio_sx_dx : ndarray, shape (n_periods,)
    avg_ratio_fr    : ndarray, shape (n_periods,)
    avg_ratio_lv    : ndarray, shape (n_periods,)
    avg_lambda_all  : ndarray, shape (n_periods, 8)
    period_dates    : ndarray, shape (n_periods,)  – datenum of each period start
    periods_valid   : list of datetime, length n_periods
    """
    r_sx_dx = np.asarray(ratio_sx_dx, dtype=float)
    r_fr    = np.asarray(ratio_fr,    dtype=float)
    r_lv    = np.asarray(ratio_lv,    dtype=float)
    lam     = np.asarray(lambda_all,  dtype=float)
    dns     = np.asarray(dates_num,   dtype=float)

    n_runs = dns.shape[0]

    # MATLAB: all_dates_dt = datetime(dates_num, 'ConvertFrom', 'datenum')
    # MATLAB: dates_rounded = dateshift(all_dates_dt, ...)
    run_datetimes: List[datetime] = [_datenum_to_datetime(dn) for dn in dns]
    rounded: List[datetime] = [
        _round_datetime_to_period(dt, grouping_mode) for dt in run_datetimes
    ]

    # MATLAB: [unique_periods, ~, ic] = unique(dates_rounded)
    # unique() in MATLAB returns sorted unique values.
    seen_order: List[datetime] = []
    for rd in rounded:
        if rd not in seen_order:
            seen_order.append(rd)
    unique_periods: List[datetime] = sorted(seen_order)

    period_index: dict = {dt: k for k, dt in enumerate(unique_periods)}
    # ic is 0-based (MATLAB ic is 1-based, but we use it only as mask index)
    ic: List[int] = [period_index[rd] for rd in rounded]

    n_periods = len(unique_periods)

    avg_ratio_sx_dx = np.zeros(n_periods)
    avg_ratio_fr    = np.zeros(n_periods)
    avg_ratio_lv    = np.zeros(n_periods)
    avg_lambda_all  = np.zeros((n_periods, lam.shape[1] if lam.ndim == 2 else 8))

    ic_arr = np.asarray(ic, dtype=int)

    for k in range(n_periods):
        # MATLAB: mask = (ic == k)   [1-based k → 0-based k here]
        mask = (ic_arr == k)

        # MATLAB: mean(..., 'omitnan')  →  np.nanmean
        avg_ratio_sx_dx[k] = np.nanmean(r_sx_dx[mask])
        avg_ratio_fr[k]    = np.nanmean(r_fr[mask])
        avg_ratio_lv[k]    = np.nanmean(r_lv[mask])

        # MATLAB: avg_Lambda_All(k,:) = mean(Lambda_All(mask,:), 1, 'omitnan')
        avg_lambda_all[k, :] = np.nanmean(lam[mask, :], axis=0)

    # MATLAB: avg_dates = datenum(unique_periods)
    period_dates = np.array([_datetime_to_datenum(dt) for dt in unique_periods])

    return (
        avg_ratio_sx_dx,
        avg_ratio_fr,
        avg_ratio_lv,
        avg_lambda_all,
        period_dates,
        unique_periods,
    )
