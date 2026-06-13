import numpy as np
from railway_inspector.signal.resampling import interpft, interp1_zero


def test_interpft_upsamples_sine_without_distortion():
    N = 16
    t = np.arange(N)
    x = np.sin(2 * np.pi * 2 * t / N)
    up = interpft(x, 4 * N)
    # original samples reappear every 4 positions
    np.testing.assert_allclose(up[::4], x, atol=1e-9)


def test_interpft_length():
    x = np.random.randn(10)
    assert len(interpft(x, 40)) == 40


def test_interp1_zero_inside_range():
    x = np.array([0.0, 1.0, 2.0])
    y = np.array([0.0, 10.0, 20.0])
    xq = np.array([0.5, 1.5])
    np.testing.assert_allclose(interp1_zero(x, y, xq), [5.0, 15.0])


def test_interp1_zero_outside_range_is_zero():
    x = np.array([0.0, 1.0, 2.0])
    y = np.array([5.0, 10.0, 20.0])
    xq = np.array([-1.0, 3.0])
    np.testing.assert_allclose(interp1_zero(x, y, xq), [0.0, 0.0])
