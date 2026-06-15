"""IPI composite score (pure math port of app.m:5373-5452 and 2132-2147).

Excludes all UI rendering: only the numeric breakdown and the risk-band colour.
"""
from __future__ import annotations

import numpy as np

from railway_inspector.config import CFG
from railway_inspector.app.analysis.spectrum import _matlab_round_pos
from railway_inspector.app.ipi.pca_model import compute_pca_bonus_for_defect


def compute_severity_ratio_lv(all_amps: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Per-run Severity (max vertical amplitude) and lateral/vertical ratio.

    Port of app.m:2132-2147. ``all_amps`` has 8 columns in the order
    [SX_F, SX_R, DX_F, DX_R, LAT_DX_F, LAT_DX_R, LAT_SX_F, LAT_SX_R]: columns
    0-3 vertical, 4-7 lateral.
    """
    A = np.asarray(all_amps, dtype=float)
    if A.ndim == 1:
        A = A.reshape(1, -1)
    vert = A[:, 0:4]
    lat = A[:, 4:8]
    a_vert_max = np.max(vert, axis=1)
    a_lat_max = np.max(lat, axis=1)
    severity = a_vert_max  # Severity(i) == A_VERT_MAX (app.m:2140)
    ratio_lv = a_lat_max / np.maximum(a_vert_max, 1e-6)
    return severity, ratio_lv


def ipi_semaphore_color(ipi_final: float) -> tuple[float, float, float]:
    """Risk-band RGB for an IPI score (app.m:5447-5450). Grey 'insufficient
    data' state is handled by the widget, not here."""
    if ipi_final >= 75:
        return (0.8, 0.0, 0.0)
    if ipi_final >= 50:
        return (1.0, 0.5, 0.0)
    if ipi_final >= 25:
        return (0.9, 0.8, 0.0)
    return (0.0, 0.6, 0.0)


def compute_ipi_score(severity: np.ndarray, ratio_lv: np.ndarray, days_floor: np.ndarray,
                      Defect: dict, cfg: CFG, ae_bonus: float = 0.0) -> dict:
    """IPI composite score (app.m:5377-5452), UI stripped.

    Returns a dict with ipi_final, ipi_raw, the five components (S_trend,
    S_absolute, Bonus_lat, Bonus_pca, Bonus_ia), rms_recent, inc_perc, n_days.
    AE bonus is injected via ``ae_bonus`` (0.0 == no AE model, the MATLAB default).
    """
    severity = np.asarray(severity, dtype=float).reshape(-1)
    ratio_lv = np.asarray(ratio_lv, dtype=float).reshape(-1)
    days_floor = np.asarray(days_floor, dtype=float).reshape(-1)
    unique_days = np.unique(days_floor)
    n_days = len(unique_days)

    result = {
        "ipi_final": 0, "ipi_raw": 0.0,
        "S_trend": 0, "S_absolute": 0, "Bonus_lat": 0,
        "Bonus_pca": 0, "Bonus_ia": 0,
        "rms_recent": np.nan, "inc_perc": 0, "n_days": n_days,
    }
    if n_days < cfg.IPI_MIN_DAYS:
        return result

    severity_daily = np.zeros(n_days)
    ratio_lv_daily = np.zeros(n_days)
    for d in range(n_days):
        mask = days_floor == unique_days[d]
        severity_daily[d] = np.nanmean(severity[mask])
        ratio_lv_daily[d] = np.nanmean(ratio_lv[mask])

    S_trend = 0
    S_absolute = 0
    inc_perc = 0
    Bonus_lat = 0
    rms_recent = np.nan
    history_span = unique_days[-1] - unique_days[0]
    if history_span >= cfg.IPI_MIN_HISTORY_DAYS:
        cutoff_day = unique_days[-1] - cfg.IPI_RECENT_DAYS
        mask_recent = unique_days > cutoff_day
        mask_base = unique_days <= cutoff_day
        if np.any(mask_recent) and np.any(mask_base):
            rms_base = np.nanmean(severity_daily[mask_base])
            rms_recent = np.nanmean(severity_daily[mask_recent])
            if rms_base > 0:
                inc_perc = ((rms_recent - rms_base) / rms_base) * 100
                S_trend = min(50, max(0, inc_perc * (50 / cfg.IPI_TREND_SENS)))
            if rms_recent < cfg.IPI_SEV_THR_LOW:
                S_absolute = 0
            elif rms_recent > cfg.IPI_SEV_THR_HIGH:
                S_absolute = 50
            else:
                S_absolute = 50 * (rms_recent - cfg.IPI_SEV_THR_LOW) / (
                    cfg.IPI_SEV_THR_HIGH - cfg.IPI_SEV_THR_LOW)
            recent_ratio_lv = np.nanmean(ratio_lv_daily[mask_recent])
            Bonus_lat = min(cfg.IPI_LAT_BONUS,
                            max(0, (recent_ratio_lv / cfg.IPI_LAT_THRESH) * cfg.IPI_LAT_BONUS))

    Bonus_ia = ae_bonus  # AE deferred: 0.0 == no AE model loaded (app.m:5427-5432)
    Bonus_pca = compute_pca_bonus_for_defect(Defect, cfg)[0]

    ipi_raw = S_absolute + S_trend + Bonus_lat + Bonus_pca + Bonus_ia
    ipi_final = _matlab_round_pos(min(100, max(0, ipi_raw)))

    result.update({
        "ipi_final": ipi_final, "ipi_raw": ipi_raw,
        "S_trend": S_trend, "S_absolute": S_absolute, "Bonus_lat": Bonus_lat,
        "Bonus_pca": Bonus_pca, "Bonus_ia": Bonus_ia,
        "rms_recent": rms_recent, "inc_perc": inc_perc, "n_days": n_days,
    })
    return result
