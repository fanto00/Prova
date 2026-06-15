import numpy as np
import pytest
from railway_inspector.app.ipi.pca_model import _matlab_pca, _group_mean, _datenum, build_pca_model_standalone, compute_pca_bonus_for_defect
from railway_inspector.config import default_config
import datetime as dt


N_GRID_REF = 333


def _make_run(date, n_samples=400, scale=1.0, seed=0):
    rng = np.random.default_rng(seed)
    ax = np.linspace(-5.0, 5.0, n_samples)  # sorted, finite
    sensors = ['left_sensor_front', 'right_sensor_front', 'right_sensor_front_lat',
               'left_sensor_rear', 'right_sensor_rear', 'right_sensor_rear_lat']
    filt = {s: scale * rng.standard_normal(n_samples) for s in sensors}
    return {"Date": date, "Data": {"Filt": filt, "RelativeAxis": ax}}


def test_group_mean_basic():
    run_id = np.array([0, 0, 1, 2, 2, 2])
    v = np.array([2.0, 4.0, 9.0, 1.0, 2.0, 3.0])
    out = _group_mean(run_id, v, 3)
    np.testing.assert_allclose(out, [3.0, 9.0, 2.0])


def test_matlab_pca_reconstruction_full_rank():
    # full reconstruction (all components) returns the centered data
    rng = np.random.default_rng(0)
    X = rng.standard_normal((200, 6))
    coeffs, scores = _matlab_pca(X)
    Xc = X - X.mean(axis=0)
    np.testing.assert_allclose(scores @ coeffs.T, Xc, atol=1e-10)


def test_matlab_pca_coeffs_orthonormal():
    rng = np.random.default_rng(1)
    X = rng.standard_normal((200, 6))
    coeffs, _ = _matlab_pca(X)
    # columns orthonormal
    np.testing.assert_allclose(coeffs.T @ coeffs, np.eye(coeffs.shape[1]), atol=1e-10)


def test_matlab_pca_sign_convention():
    rng = np.random.default_rng(2)
    X = rng.standard_normal((200, 6))
    coeffs, _ = _matlab_pca(X)
    for j in range(coeffs.shape[1]):
        col = coeffs[:, j]
        assert col[np.argmax(np.abs(col))] > 0  # largest-magnitude element positive


def test_datenum_difference_is_days():
    d1 = dt.datetime(2026, 1, 1, 0, 0)
    d2 = dt.datetime(2026, 1, 11, 12, 0)
    assert _datenum(d2) - _datenum(d1) == pytest.approx(10.5)
    assert np.floor(_datenum(d2)) - np.floor(_datenum(d1)) == 10


def test_build_pca_returns_none_below_min_runs():
    hist = [_make_run(dt.datetime(2026, 1, 1))]
    out = build_pca_model_standalone(hist, [0], "forward", 0.004, 5.0, 0.5, 30, 2)
    assert out is None


def test_build_pca_returns_none_bad_direction():
    hist = [_make_run(dt.datetime(2026, 1, 1)) for _ in range(5)]
    out = build_pca_model_standalone(hist, list(range(5)), "sideways", 0.004, 5.0, 0.5, 3, 2)
    assert out is None


def test_build_pca_model_shapes_and_sort():
    base = dt.datetime(2026, 1, 1)
    # build out of order dates to verify sorting; 6 valid runs, MIN_RUNS=3
    hist = [_make_run(base + dt.timedelta(days=d), seed=d) for d in [5, 1, 3, 0, 4, 2]]
    out = build_pca_model_standalone(hist, list(range(6)), "forward", 0.004, 5.0, 0.5, 3, 2)
    assert out is not None
    assert out["n_valid"] == 6
    assert out["rmse"].shape == (6,)
    assert out["dates"].shape == (6,)
    assert out["scores"].shape[0] == 6
    assert out["coeffs"].shape[0] == 6  # n_chan
    # dates sorted ascending
    assert np.all(np.diff(out["dates"]) >= 0)
    # rmse is non-negative (sqrt of mean square residual)
    assert np.all(out["rmse"] >= 0)


def test_build_pca_skips_run_with_mismatched_axis():
    base = dt.datetime(2026, 1, 1)
    hist = [_make_run(base + dt.timedelta(days=d), seed=d) for d in range(4)]
    # corrupt one run: signal length != RelativeAxis length -> run dropped
    bad = hist[2]
    for s in bad["Data"]["Filt"]:
        bad["Data"]["Filt"][s] = bad["Data"]["Filt"][s][:-5]
    out = build_pca_model_standalone(hist, list(range(4)), "forward", 0.004, 5.0, 0.5, 3, 2)
    assert out is not None
    assert out["n_valid"] == 3  # the corrupted run was excluded


def _forward_run(date, scale, seed):
    # forward orientation: right front lateral RMS must exceed left front lateral.
    r = _make_run(date, scale=scale, seed=seed)
    n = r["Data"]["RelativeAxis"].size
    rng = np.random.default_rng(seed + 999)
    r["Data"]["Filt"]["right_sensor_front_lat"] = 3.0 * scale * rng.standard_normal(n)
    r["Data"]["Filt"]["left_sensor_front_lat"] = 0.1 * scale * rng.standard_normal(n)
    return r


def test_compute_pca_bonus_too_few_runs_returns_zero():
    cfg = default_config()
    defect = {"History": [_make_run(dt.datetime(2026, 1, 1)) for _ in range(3)]}
    bonus, info = compute_pca_bonus_for_defect(defect, cfg)
    assert bonus == 0
    assert info["direction_used"] == "none"
    assert info["k_pca"] == cfg.IPI_PCA_K
    assert info["bonus_trend"] == 0
    assert info["bonus_excursion"] == 0


def test_compute_pca_bonus_full_scenario_trend_positive():
    cfg = default_config()
    base = dt.datetime(2026, 1, 1)
    runs = []
    # 40 forward runs over 60 days; envelope amplitude grows in the recent window
    # so recent RMSE > base RMSE -> positive trend bonus.
    for i in range(40):
        day = int(i * 60 / 39)               # spread across 0..60 days (>45 span, >=10 days)
        scale = 1.0 if day <= 30 else 3.0    # amplify after cutoff day
        runs.append(_forward_run(base + dt.timedelta(days=day), scale=scale, seed=i))
    defect = {"History": runs}
    bonus, info = compute_pca_bonus_for_defect(defect, cfg)
    assert info["direction_used"] == "forward"
    assert bonus >= 0
    assert 0 <= info["bonus_trend"] <= cfg.IPI_PCA_BONUS
    assert 0 <= info["bonus_excursion"] <= cfg.IPI_PCA_EXCUR_BONUS
    assert info["bonus_trend"] + info["bonus_excursion"] == pytest.approx(bonus)
