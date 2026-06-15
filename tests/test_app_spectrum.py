"""Tests for app.analysis.spectrum (port of app.m spectrum functions)."""
import numpy as np
import pytest
from railway_inspector.app.analysis.spectrum import lambda_to_label, peak_lambda_from_spectrum, get_spectrum_psd
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


def test_get_spectrum_psd_no_valid_sensor_returns_none():
    cfg = default_config()
    psd, freq = get_spectrum_psd({}, ["s1"], [1.0], cfg)
    assert psd is None and freq is None


def test_get_spectrum_psd_zero_weight_skipped():
    cfg = default_config()
    F = {"s1": np.random.default_rng(0).standard_normal(3000)}
    psd, freq = get_spectrum_psd(F, ["s1"], [0.0], cfg)  # weight below 1e-6
    assert psd is None and freq is None


def test_get_spectrum_psd_short_signal_skipped():
    cfg = default_config()
    F = {"s1": np.array([1.0, 2.0, 3.0])}  # length 3 < 4
    psd, freq = get_spectrum_psd(F, ["s1"], [1.0], cfg)
    assert psd is None and freq is None


def test_get_spectrum_psd_matches_scipy_periodogram_single_sensor():
    cfg = default_config()
    rng = np.random.default_rng(42)
    sig = rng.standard_normal(2500)  # exactly NFFT, no cropping
    F = {"s1": sig}
    psd, freq = get_spectrum_psd(F, ["s1"], [2.0], cfg)

    from scipy.signal import periodogram as _pg
    from scipy.signal.windows import hamming as _ham
    fs = 1.0 / cfg.SPATIAL_RES
    f, pxx = _pg(sig, fs=fs, window=_ham(2500, sym=True), nfft=2500,
                 detrend=False, return_onesided=True, scaling="density")
    # single sensor: weighted mean == pxx (weight cancels)
    np.testing.assert_allclose(psd, pxx, rtol=1e-9, atol=1e-12)
    np.testing.assert_allclose(freq, f, rtol=1e-9, atol=1e-12)


def test_get_spectrum_psd_center_crops_long_signal():
    cfg = default_config()
    rng = np.random.default_rng(1)
    sig = rng.standard_normal(3000)  # > NFFT 2500 -> center crop
    F = {"s1": sig}
    psd, freq = get_spectrum_psd(F, ["s1"], [1.0], cfg)

    start0 = (3000 - 2500) // 2
    cropped = sig[start0:start0 + 2500]
    from scipy.signal import periodogram as _pg
    from scipy.signal.windows import hamming as _ham
    fs = 1.0 / cfg.SPATIAL_RES
    _f, pxx = _pg(cropped, fs=fs, window=_ham(2500, sym=True), nfft=2500,
                  detrend=False, return_onesided=True, scaling="density")
    np.testing.assert_allclose(psd, pxx, rtol=1e-9, atol=1e-12)
