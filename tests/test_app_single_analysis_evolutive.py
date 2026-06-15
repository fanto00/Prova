"""TDD tests for railway_inspector.app.analysis.single_analysis_evolutive (7 tests)."""
from __future__ import annotations

import numpy as np
import pytest
from datetime import datetime

from railway_inspector.app.analysis.single_analysis_evolutive import (
    compute_amplitude_ratios,
    compute_evolutive_metrics,
)


# Helper: convert datetime to MATLAB datenum
def datenum(dt: datetime) -> float:
    """Convert datetime to MATLAB datenum."""
    epoch = datetime(1899, 12, 30)
    delta = dt - epoch
    return delta.days + delta.seconds / 86400.0


# ---------------------------------------------------------------------------
# Test 1: compute_amplitude_ratios basic
# ---------------------------------------------------------------------------

def test_compute_amplitude_ratios_basic():
    """compute_amplitude_ratios() ritorna tre array di ratios."""
    all_amps = np.array([
        [1.0, 1.0, 2.0, 2.0, 0.5, 0.5, 0.5, 0.5],  # Run 1
        [2.0, 2.0, 1.0, 1.0, 0.3, 0.3, 0.3, 0.3],  # Run 2
    ])
    defect_history = [{'Date': datetime(2026, 1, 1)}, {'Date': datetime(2026, 1, 2)}]

    ratio_sx_dx, ratio_fr, ratio_lv = compute_amplitude_ratios(
        defect_history, all_amps
    )

    assert len(ratio_sx_dx) == 2
    assert len(ratio_fr) == 2
    assert len(ratio_lv) == 2
    assert isinstance(ratio_sx_dx, np.ndarray)
    assert isinstance(ratio_fr, np.ndarray)
    assert isinstance(ratio_lv, np.ndarray)


# ---------------------------------------------------------------------------
# Test 2: compute_amplitude_ratios formula exact
# ---------------------------------------------------------------------------

def test_compute_amplitude_ratios_formula():
    """Formule esatte: SX_DX=(F+R)/max(DX,1e-6), FR=(F+F)/(R+R), LV=LAT_MAX/VERT_MAX."""
    # Colonne: [0:SX_F, 1:SX_R, 2:DX_F, 3:DX_R, 4-7:LAT sensori]
    # Per LV: A_LAT_MAX = max(LAT sensori), A_VERT_MAX = max(SX_F, SX_R, DX_F, DX_R)
    all_amps = np.array([[2.0, 2.0, 4.0, 4.0, 1.0, 1.0, 1.0, 1.0]])
    defect_history = [{'Date': datetime(2026, 1, 1)}]

    ratio_sx_dx, ratio_fr, ratio_lv = compute_amplitude_ratios(defect_history, all_amps)

    # SX_DX = (2+2) / (4+4) = 4/8 = 0.5
    assert np.isclose(ratio_sx_dx[0], 0.5)
    # FR = (2+4) / (2+4) = 6/6 = 1.0
    assert np.isclose(ratio_fr[0], 1.0)
    # LV = max(1,1,1,1) / max(2,2,4,4) = 1/4 = 0.25
    assert np.isclose(ratio_lv[0], 0.25)


# ---------------------------------------------------------------------------
# Test 3: compute_amplitude_ratios zero guard
# ---------------------------------------------------------------------------

def test_compute_amplitude_ratios_zero_guard():
    """Denominatore zero protetto da 1e-6 (no inf)."""
    all_amps = np.array([[1.0, 1.0, 0.0, 0.0, 0.5, 0.5, 0.5, 0.5]])
    defect_history = [{'Date': datetime(2026, 1, 1)}]

    ratio_sx_dx, ratio_fr, ratio_lv = compute_amplitude_ratios(defect_history, all_amps)

    # Non dovrebbe dare inf
    assert np.isfinite(ratio_sx_dx[0])
    assert ratio_sx_dx[0] > 0  # (2 / 1e-6) è grande ma finito


# ---------------------------------------------------------------------------
# Test 4: compute_evolutive_metrics daily grouping
# ---------------------------------------------------------------------------

def test_compute_evolutive_metrics_daily_grouping():
    """Raggruppa due run nello stesso giorno → una media."""
    ratio_sx_dx = np.array([1.0, 1.0])
    ratio_fr    = np.array([0.5, 0.5])
    ratio_lv    = np.array([2.0, 2.0])
    lambda_all  = np.ones((2, 8))
    dates_num   = np.array([datenum(datetime(2026, 1, 1, 10, 0)),
                            datenum(datetime(2026, 1, 1, 15, 0))])
    defect_history = [{'Date': datetime(2026, 1, 1, 10, 0)},
                      {'Date': datetime(2026, 1, 1, 15, 0)}]

    avg_sx_dx, avg_fr, avg_lv, avg_lam, period_dates, periods = compute_evolutive_metrics(
        defect_history, ratio_sx_dx, ratio_fr, ratio_lv, lambda_all,
        dates_num, grouping_mode='daily'
    )

    # Un solo periodo (stesso giorno)
    assert len(avg_sx_dx) == 1
    assert np.isclose(avg_sx_dx[0], 1.0)
    assert np.isclose(avg_fr[0], 0.5)
    assert np.isclose(avg_lv[0], 2.0)


# ---------------------------------------------------------------------------
# Test 5: compute_evolutive_metrics run grouping
# ---------------------------------------------------------------------------

def test_compute_evolutive_metrics_run_grouping():
    """grouping='run' → nessuna aggregazione, identico a input."""
    ratio_sx_dx = np.array([1.0, 2.0, 3.0])
    ratio_fr    = np.array([0.5, 1.0, 1.5])
    ratio_lv    = np.array([2.0, 3.0, 4.0])
    lambda_all  = np.random.rand(3, 8)
    dates_num   = np.array([datenum(datetime(2026, 1, 1)),
                            datenum(datetime(2026, 1, 2)),
                            datenum(datetime(2026, 1, 3))])
    defect_history = [{'Date': datetime(2026, 1, 1)},
                      {'Date': datetime(2026, 1, 2)},
                      {'Date': datetime(2026, 1, 3)}]

    avg_sx_dx, avg_fr, avg_lv, avg_lam, period_dates, periods = compute_evolutive_metrics(
        defect_history, ratio_sx_dx, ratio_fr, ratio_lv, lambda_all,
        dates_num, grouping_mode='run'
    )

    # Tre periodi separati (uno per run)
    assert len(avg_sx_dx) == 3
    assert np.allclose(avg_sx_dx, ratio_sx_dx)


# ---------------------------------------------------------------------------
# Test 6: compute_evolutive_metrics weekly grouping
# ---------------------------------------------------------------------------

def test_compute_evolutive_metrics_weekly_grouping():
    """Raggruppamento settimanale (ISO week lunedì-domenica)."""
    ratio_sx_dx = np.array([1.0, 1.5, 2.0])
    ratio_fr    = np.array([0.5, 0.75, 1.0])
    ratio_lv    = np.array([2.0, 2.5, 3.0])
    lambda_all  = np.ones((3, 8))
    # 2026-01-05 is Monday, 2026-01-12 is next Monday
    dates_num   = np.array([datenum(datetime(2026, 1, 5)),   # Week 1
                            datenum(datetime(2026, 1, 6)),   # Week 1
                            datenum(datetime(2026, 1, 12))]) # Week 2
    defect_history = [{'Date': datetime(2026, 1, 5)},
                      {'Date': datetime(2026, 1, 6)},
                      {'Date': datetime(2026, 1, 12)}]

    avg_sx_dx, avg_fr, avg_lv, avg_lam, period_dates, periods = compute_evolutive_metrics(
        defect_history, ratio_sx_dx, ratio_fr, ratio_lv, lambda_all,
        dates_num, grouping_mode='weekly'
    )

    # Due settimane
    assert len(avg_sx_dx) == 2
    # Week 1: mean([1.0, 1.5]) = 1.25
    assert np.isclose(avg_sx_dx[0], 1.25)
    # Week 2: mean([2.0]) = 2.0
    assert np.isclose(avg_sx_dx[1], 2.0)


# ---------------------------------------------------------------------------
# Test 7: compute_amplitude_ratios nan handling
# ---------------------------------------------------------------------------

def test_compute_amplitude_ratios_nan_handling():
    """NaN nelle ampiezze gestito correttamente (no propagazione errata)."""
    all_amps = np.array([
        [1.0, 1.0, 2.0, 2.0, np.nan, 0.5, 0.5, 0.5],
        [2.0, 2.0, 1.0, 1.0, 0.3, 0.3, 0.3, 0.3],
    ])
    defect_history = [{'Date': datetime(2026, 1, 1)}, {'Date': datetime(2026, 1, 2)}]

    ratio_sx_dx, ratio_fr, ratio_lv = compute_amplitude_ratios(defect_history, all_amps)

    # Primo ratio: numerator ok, denominatore ok → ratio ok
    assert np.isfinite(ratio_sx_dx[0])
    # Secondo ratio completamente ok
    assert np.isfinite(ratio_sx_dx[1])
