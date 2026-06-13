import numpy as np
import pytest
from railway_inspector.config import default_config
from railway_inspector.detection.trigger import detect_peaks_on_signal


def test_detect_strong_isolated_peak():
    c = default_config()
    axis = np.arange(0, 50, c.SPATIAL_RES)
    sig = np.zeros_like(axis)
    center = len(axis) // 2
    # Burst must be wide enough (~N_f = RMS_WIN_FAST/SPATIAL_RES = 250 samples = 1 m)
    # so the RMS envelope rises above ABS_RMS_THRESH=5.
    # Use a Hanning-shaped burst of width N_f samples at amplitude 20.
    N_f = int(round(c.RMS_WIN_FAST / c.SPATIAL_RES))
    burst_half = N_f // 2
    sig[center - burst_half: center + burst_half] = 20.0 * np.hanning(2 * burst_half)
    locs, amps = detect_peaks_on_signal(sig, axis, c)
    assert len(locs) >= 1
    # detected peak is near the center (within 1 m)
    assert np.min(np.abs(np.array(locs) - axis[center])) < 1.0


def test_movmean_centered():
    from railway_inspector.detection.trigger import movmean
    x = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
    # window 3 centered: edges truncate
    # i=0: window covers [0,1]   -> mean([1,2])   = 1.5
    # i=1: window covers [0,1,2] -> mean([1,2,3]) = 2.0
    # i=2: window covers [1,2,3] -> mean([2,3,4]) = 3.0
    # i=3: window covers [2,3,4] -> mean([3,4,5]) = 4.0
    # i=4: window covers [3,4]   -> mean([4,5])   = 4.5
    np.testing.assert_allclose(movmean(x, 3), [1.5, 2.0, 3.0, 4.0, 4.5])


def test_movmean_even_window():
    from railway_inspector.detection.trigger import movmean
    x = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
    # window 4: MATLAB uses floor((4-1)/2)=1 before, floor(4/2)=2 after
    # i=0: before=max(0,0-1)=0..0+2=2  -> [1,2,3]  mean=2.0
    # i=1: 0..3 -> [1,2,3,4] mean=2.5
    # i=2: 1..4 -> [2,3,4,5] mean=3.5
    # i=3: 2..4 -> [3,4,5]   mean=4.0
    # i=4: 3..4 -> [4,5]     mean=4.5
    np.testing.assert_allclose(movmean(x, 4), [2.0, 2.5, 3.5, 4.0, 4.5])


def test_merge_detections_combines_close():
    from railway_inspector.detection.trigger import merge_detections
    det = np.array([[10.0, 3.0], [10.5, 5.0], [50.0, 2.0]])
    merged = merge_detections(det, cross_tol=1.5)
    # first two merge (gap 0.5 <= 1.5), keep higher amp position
    assert merged.shape[0] == 2
    assert abs(merged[0, 0] - 10.5) < 1e-9 and merged[0, 1] == 5.0


def test_merge_detections_no_merge():
    from railway_inspector.detection.trigger import merge_detections
    det = np.array([[0.0, 1.0], [5.0, 2.0], [10.0, 3.0]])
    merged = merge_detections(det, cross_tol=1.5)
    assert merged.shape[0] == 3


def test_merge_detections_single_row():
    from railway_inspector.detection.trigger import merge_detections
    det = np.array([[7.0, 4.5]])
    merged = merge_detections(det, cross_tol=1.5)
    assert merged.shape == (1, 2)
    assert merged[0, 0] == 7.0 and merged[0, 1] == 4.5


def test_detect_returns_empty_for_flat_signal():
    c = default_config()
    axis = np.arange(0, 50, c.SPATIAL_RES)
    sig = np.zeros_like(axis)
    locs, amps = detect_peaks_on_signal(sig, axis, c)
    assert len(locs) == 0
    assert len(amps) == 0
