import numpy as np
import pytest
from railway_inspector.app.ipi.ipi_core import compute_severity_ratio_lv, ipi_semaphore_color, compute_ipi_score
from railway_inspector.config import default_config


def test_severity_is_max_of_vertical_columns():
    # cols: [SX_F, SX_R, DX_F, DX_R, LAT_DX_F, LAT_DX_R, LAT_SX_F, LAT_SX_R]
    amps = np.array([[1.0, 4.0, 2.0, 3.0, 0.0, 0.0, 0.0, 0.0]])
    sev, ratio = compute_severity_ratio_lv(amps)
    assert sev[0] == 4.0  # max vertical


def test_ratio_lv_is_lat_over_vert():
    amps = np.array([[2.0, 2.0, 2.0, 2.0, 1.0, 5.0, 3.0, 0.0]])  # vert max 2, lat max 5
    sev, ratio = compute_severity_ratio_lv(amps)
    assert ratio[0] == pytest.approx(5.0 / 2.0)


def test_ratio_lv_zero_vertical_uses_floor():
    amps = np.array([[0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]])
    sev, ratio = compute_severity_ratio_lv(amps)
    assert ratio[0] == pytest.approx(1.0 / 1e-6)


def test_multiple_runs_shapes():
    amps = np.zeros((5, 8))
    sev, ratio = compute_severity_ratio_lv(amps)
    assert sev.shape == (5,)
    assert ratio.shape == (5,)


@pytest.mark.parametrize("score,rgb", [
    (90, (0.8, 0.0, 0.0)),
    (75, (0.8, 0.0, 0.0)),
    (60, (1.0, 0.5, 0.0)),
    (50, (1.0, 0.5, 0.0)),
    (30, (0.9, 0.8, 0.0)),
    (25, (0.9, 0.8, 0.0)),
    (10, (0.0, 0.6, 0.0)),
    (0, (0.0, 0.6, 0.0)),
])
def test_ipi_semaphore_color_bands(score, rgb):
    assert ipi_semaphore_color(score) == rgb


def test_ipi_insufficient_days_returns_zero():
    cfg = default_config()  # IPI_MIN_DAYS = 10
    # only 3 distinct days
    days = np.array([1.0, 1.0, 2.0, 3.0])
    sev = np.array([20.0, 20.0, 20.0, 20.0])
    ratio = np.array([0.1, 0.1, 0.1, 0.1])
    res = compute_ipi_score(sev, ratio, days, {"History": []}, cfg)
    assert res["ipi_final"] == 0
    assert res["S_trend"] == 0
    assert res["S_absolute"] == 0
    assert res["Bonus_lat"] == 0
    assert res["Bonus_pca"] == 0
    assert res["Bonus_ia"] == 0
    assert res["n_days"] == 3


def test_ipi_short_history_span_no_trend_or_absolute():
    cfg = default_config()  # IPI_MIN_HISTORY_DAYS = 45
    # 12 distinct days but spanning only 11 days (< 45) -> no recent/base split
    days = np.arange(0.0, 12.0)
    sev = np.full(12, 30.0)
    ratio = np.full(12, 1.0)
    res = compute_ipi_score(sev, ratio, days, {"History": []}, cfg)
    assert res["n_days"] == 12
    assert res["S_trend"] == 0
    assert res["S_absolute"] == 0
    assert res["Bonus_lat"] == 0
    assert np.isnan(res["rms_recent"])
    assert res["ipi_final"] == 0  # only PCA(0)+AE(0)


def test_ipi_full_scenario_absolute_and_trend():
    cfg = default_config()
    # 60-day span, daily samples. Base severity 10, recent severity 40.
    days = np.arange(0.0, 61.0)               # 61 distinct days, span 60 >= 45
    sev = np.where(days <= (60 - cfg.IPI_RECENT_DAYS), 10.0, 40.0)
    ratio = np.full(days.size, 0.7)           # recent_ratio_lv/0.7 * 30 -> full lat bonus
    res = compute_ipi_score(sev, ratio, days, {"History": []}, cfg)
    # rms_base = 10, rms_recent = 40 -> inc 300% -> S_trend clamped to 50
    assert res["rms_recent"] == pytest.approx(40.0)
    assert res["S_trend"] == 50
    # rms_recent 40 in (15,50) -> S_absolute = 50*(40-15)/(50-15)
    assert res["S_absolute"] == pytest.approx(50 * (40 - 15) / (50 - 15))
    # ratio 0.7 / 0.7 * 30 = 30 -> Bonus_lat clamped to 30
    assert res["Bonus_lat"] == pytest.approx(30)
    # ipi_final = round(min(100, S_abs + 50 + 30 + 0 + 0))
    expected_raw = res["S_absolute"] + 50 + 30
    assert res["ipi_final"] == round(min(100, expected_raw))


def test_ipi_ae_bonus_is_injectable():
    cfg = default_config()
    days = np.arange(0.0, 61.0)
    sev = np.full(days.size, 5.0)   # below IPI_SEV_THR_LOW -> S_absolute 0, flat -> S_trend 0
    ratio = np.zeros(days.size)
    res = compute_ipi_score(sev, ratio, days, {"History": []}, cfg, ae_bonus=12.0)
    assert res["Bonus_ia"] == 12.0
    assert res["ipi_final"] == 12  # only the injected AE bonus contributes
