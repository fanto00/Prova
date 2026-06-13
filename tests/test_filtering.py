import numpy as np
from scipy.signal import butter
from railway_inspector.config import default_config
from railway_inspector.signal.filtering import design_filters


def test_design_filters_matches_butter_params():
    c = default_config()
    bT, aT, bQ, aQ = design_filters(c, fs_time=1000.0)
    fs_space = 1.0 / c.SPATIAL_RES
    bT_ref, aT_ref = butter(2, [c.fmin, c.fmax] / np.array(1000.0 / 2), btype="bandpass")
    bQ_ref, aQ_ref = butter(2, [1/c.L_MAX, 1/c.L_MIN_QUIET] / np.array(fs_space / 2), btype="bandpass")
    np.testing.assert_allclose(bT, bT_ref)
    np.testing.assert_allclose(aT, aT_ref)
    np.testing.assert_allclose(bQ, bQ_ref)
    np.testing.assert_allclose(aQ, aQ_ref)


def test_filter_pipeline_removes_dc():
    from railway_inspector.signal.filtering import filter_pipeline
    c = default_config()
    n = 5000
    ax = np.arange(n) * 0.001  # uniform fake axis
    sig = 100.0 + np.sin(2 * np.pi * 50 * ax)  # strong DC component
    common_axis = np.arange(int(np.ceil(ax.min() / c.SPATIAL_RES)),
                            int(np.floor(ax.max() / c.SPATIAL_RES)) + 1) * c.SPATIAL_RES
    filt = filter_pipeline(sig, ax, common_axis, c, fs_time=1000.0)
    assert abs(np.mean(filt)) < 1.0  # DC removed
