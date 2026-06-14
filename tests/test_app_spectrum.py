"""Tests for app.analysis.spectrum (port of app.m spectrum functions)."""
import numpy as np
import pytest
from railway_inspector.app.analysis.spectrum import lambda_to_label, peak_lambda_from_spectrum
from railway_inspector.config import default_config


@pytest.mark.parametrize("lam,expected", [
    (-1.0, "N/D"),
    (0.0, "N/D"),
    (0.3, "Corto"),
    (1.0, "medio"),
    (3.0, "lungo"),
    (50.0, "molto lungo"),
])
def test_lambda_to_label(lam, expected):
    # boundaries: L_giunto=0.5, L_irreg=2.0, L_deform=10.0
    assert lambda_to_label(lam, 0.5, 2.0, 10.0) == expected


def test_peak_lambda_empty_returns_zero():
    cfg = default_config()
    assert peak_lambda_from_spectrum(np.array([]), np.array([]), 1.0, cfg) == 0


def test_peak_lambda_zero_weight_returns_zero():
    cfg = default_config()
    spec = np.array([1.0, 2.0, 3.0])
    freq = np.array([0.1, 0.2, 0.3])
    assert peak_lambda_from_spectrum(spec, freq, 0.0, cfg) == 0


def test_peak_lambda_picks_dominant_in_band():
    cfg = default_config()  # L_MAX=15 -> f_min=1/15; L_MIN_QUIET=0.01 -> f_max=100
    freq = np.array([0.01, 0.1, 0.5, 2.0])   # 0.01 (1/15=0.0667) is below band
    spec = np.array([100.0, 1.0, 9.0, 2.0])  # peak at 0.01 excluded; in-band peak at 0.5
    lam = peak_lambda_from_spectrum(spec, freq, 1.0, cfg)
    assert lam == pytest.approx(1.0 / 0.5)


def test_peak_lambda_no_band_returns_zero():
    cfg = default_config()
    freq = np.array([0.001, 0.002])  # all below 1/15
    spec = np.array([5.0, 6.0])
    assert peak_lambda_from_spectrum(spec, freq, 1.0, cfg) == 0
