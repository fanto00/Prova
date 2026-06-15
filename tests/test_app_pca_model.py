import numpy as np
import pytest
from railway_inspector.app.ipi.pca_model import _matlab_pca, _group_mean, _datenum
import datetime as dt


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
