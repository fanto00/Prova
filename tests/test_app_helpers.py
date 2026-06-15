"""Tests for app.utils.helpers (port of app.m helper functions)."""
import numpy as np
import pytest
from railway_inspector.app.utils.helpers import get_amp, get_max_rms


def test_get_amp_missing_sensor_returns_zero():
    assert get_amp({}, "s1") == 0


def test_get_amp_all_zero_returns_zero():
    assert get_amp({"s1": np.zeros(10)}, "s1") == 0


def test_get_amp_returns_max_abs():
    assert get_amp({"s1": np.array([-3.0, 1.0, 2.0])}, "s1") == 3.0


def test_get_max_rms_missing_sensor_returns_zero():
    assert get_max_rms({}, "s1", 4) == 0


def test_get_max_rms_short_signal_falls_back_to_max_abs():
    # length 3 < win_samples 5  -> max(abs(sig))
    assert get_max_rms({"s1": np.array([-3.0, 1.0, 2.0])}, "s1", 5) == 3.0


def test_get_max_rms_uses_movmean_rms():
    from railway_inspector.detection.trigger import movmean
    sig = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
    expected = float(np.max(np.sqrt(movmean(sig**2, 3))))
    assert get_max_rms({"s1": sig}, "s1", 3) == pytest.approx(expected)


def test_safe_ratio_both_small_returns_one():
    from railway_inspector.app.utils.helpers import safe_ratio
    assert safe_ratio(0.0, 0.0) == 1.0


def test_safe_ratio_zero_denominator_returns_999():
    from railway_inspector.app.utils.helpers import safe_ratio
    assert safe_ratio(5.0, 0.0) == 999


def test_safe_ratio_normal_division():
    from railway_inspector.app.utils.helpers import safe_ratio
    assert safe_ratio(6.0, 3.0) == 2.0


def _run(filt):
    return {"Data": {"Filt": filt}}


def test_get_sign_mean_empty_history_returns_one():
    from railway_inspector.app.utils.helpers import get_sign_mean
    assert get_sign_mean({"History": []}, "a", "b") == 1


def test_get_sign_mean_no_filt_returns_one():
    from railway_inspector.app.utils.helpers import get_sign_mean
    defect = {"History": [{"Data": {}}]}
    assert get_sign_mean(defect, "a", "b") == 1


def test_get_sign_mean_positive_center():
    from railway_inspector.app.utils.helpers import get_sign_mean
    # N=11 -> mid0 = (11+1)//2 - 1 = 5 ; half = min(5, 11//4=2) = 2
    # slice sig[3:8] = all +2.0 -> mean +2 -> sign +1
    sig = np.full(11, 2.0)
    defect = {"History": [_run({"a": sig})]}
    assert get_sign_mean(defect, "a", "b") == 1.0


def test_get_sign_mean_negative_center():
    from railway_inspector.app.utils.helpers import get_sign_mean
    sig = np.full(11, -2.0)
    defect = {"History": [_run({"a": sig})]}
    assert get_sign_mean(defect, "a", "b") == -1.0


def test_sort_runs_orientation_forward_backward():
    from railway_inspector.app.utils.helpers import sort_runs_by_direction
    history = [
        {"orientation": "Forward", "Data": {"Filt": {}}},
        {"orientation": "backward run", "Data": {"Filt": {}}},
    ]
    fwd, bwd = sort_runs_by_direction(history)
    assert list(fwd) == [True, False]
    assert list(bwd) == [False, True]


def test_sort_runs_no_filt_is_skipped():
    from railway_inspector.app.utils.helpers import sort_runs_by_direction
    history = [{"orientation": "forward", "Data": {}}]
    fwd, bwd = sort_runs_by_direction(history)
    assert list(fwd) == [False]
    assert list(bwd) == [False]


def test_sort_runs_rms_fallback():
    from railway_inspector.app.utils.helpers import sort_runs_by_direction
    # right lateral RMS > left lateral RMS -> forward
    history = [{
        "Data": {"Filt": {
            "right_sensor_front_lat": np.array([3.0, 3.0, 3.0]),
            "left_sensor_front_lat": np.array([1.0, 1.0, 1.0]),
        }},
    }]
    fwd, bwd = sort_runs_by_direction(history)
    assert list(fwd) == [True]
    assert list(bwd) == [False]


def test_sort_runs_rms_tie_leaves_both_false():
    from railway_inspector.app.utils.helpers import sort_runs_by_direction
    history = [{
        "Data": {"Filt": {
            "right_sensor_front_lat": np.array([2.0, 2.0]),
            "left_sensor_front_lat": np.array([2.0, 2.0]),
        }},
    }]
    fwd, bwd = sort_runs_by_direction(history)
    assert list(fwd) == [False]
    assert list(bwd) == [False]


def test_helper_fft_shift_short_signal_returned_unchanged():
    from railway_inspector.app.utils.helpers import helper_fft_shift
    sig = np.array([5.0])
    out = helper_fft_shift(sig, 0.1, 0.004)
    assert np.array_equal(out, sig)


def test_helper_fft_shift_matches_shift_signal_frac():
    from railway_inspector.app.utils.helpers import helper_fft_shift
    from railway_inspector.signal.alignment import shift_signal_frac
    sig = np.sin(np.linspace(0, 4 * np.pi, 64))
    out = helper_fft_shift(sig, 0.012, 0.004)
    expected = shift_signal_frac(sig, 0.012, 0.004)
    np.testing.assert_allclose(out, expected, atol=1e-12)
