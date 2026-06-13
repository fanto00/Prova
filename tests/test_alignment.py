import numpy as np
from railway_inspector.signal.alignment import (
    xcorr_lag, shift_signal_frac, shift_fill, hilbert_envelope,
)


def test_xcorr_lag_detects_known_shift():
    ref = np.zeros(100); ref[50] = 1.0
    sig = np.zeros(100); sig[55] = 1.0   # sig peak is AHEAD of ref peak
    lag = xcorr_lag(ref, sig, max_lag=20)
    # MATLAB convention: lag = p_ref - p_sig = 50 - 55 = -5
    # (negative because sig peak is at a higher index than ref peak)
    assert lag == -5


def test_shift_signal_frac_integer_lag_matches_roll():
    x = np.sin(2*np.pi*3*np.arange(64)/64)
    shifted = shift_signal_frac(x, shift_m=2*0.004, spatial_res=0.004)  # +2 samples
    np.testing.assert_allclose(shifted[10:54], np.roll(x, 2)[10:54], atol=1e-9)


def test_shift_fill_no_wraparound():
    x = np.array([1.0, 2.0, 3.0, 4.0])
    np.testing.assert_allclose(shift_fill(x, 1), [0.0, 1.0, 2.0, 3.0])
    np.testing.assert_allclose(shift_fill(x, -1), [2.0, 3.0, 4.0, 0.0])


def test_hilbert_envelope_of_am_signal_is_positive():
    t = np.linspace(0, 1, 500)
    x = (1 + 0.5*np.cos(2*np.pi*3*t)) * np.cos(2*np.pi*50*t)
    env = hilbert_envelope(x)
    assert np.all(env >= 0)
    assert len(env) == len(x)
