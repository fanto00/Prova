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
