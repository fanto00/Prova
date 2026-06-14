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
