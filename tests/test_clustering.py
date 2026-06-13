"""
tests/test_clustering.py
========================
TDD tests for railway_inspector.detection.clustering.

Source of truth: src_database/Database_Allineamento_nomax.m, lines 339-377.
"""

import numpy as np
import pytest

from railway_inspector.detection.clustering import assign_cluster_ids, filter_by_mode_speed


# ---------------------------------------------------------------------------
# assign_cluster_ids
# ---------------------------------------------------------------------------

def test_cluster_ids_split_on_gap():
    """Gap > CROSS_TOL triggers a new cluster."""
    pos = np.array([10.0, 10.5, 11.0, 50.0, 50.3])
    ids = assign_cluster_ids(pos, cross_tol=1.5)
    assert list(ids) == [1, 1, 1, 2, 2]


def test_single_point_cluster():
    """A single position always yields cluster 1."""
    ids = assign_cluster_ids(np.array([5.0]), cross_tol=1.5)
    assert list(ids) == [1]


def test_cluster_ids_all_same_cluster():
    """All gaps <= CROSS_TOL → single cluster."""
    pos = np.array([0.0, 1.0, 2.0, 3.0])
    ids = assign_cluster_ids(pos, cross_tol=1.5)
    assert list(ids) == [1, 1, 1, 1]


def test_cluster_ids_every_point_new_cluster():
    """Every consecutive gap > CROSS_TOL → each point its own cluster."""
    pos = np.array([0.0, 10.0, 20.0])
    ids = assign_cluster_ids(pos, cross_tol=5.0)
    assert list(ids) == [1, 2, 3]


def test_cluster_ids_gap_exactly_at_tolerance_no_split():
    """Gap == CROSS_TOL does NOT trigger a new cluster (condition is strict >)."""
    pos = np.array([0.0, 1.5, 3.0])
    ids = assign_cluster_ids(pos, cross_tol=1.5)
    assert list(ids) == [1, 1, 1]


def test_cluster_ids_start_at_1():
    """IDs are 1-based, matching MATLAB."""
    ids = assign_cluster_ids(np.array([1.0, 100.0]), cross_tol=1.0)
    assert ids[0] == 1
    assert ids[1] == 2


def test_cluster_ids_dtype_int():
    """Return array must be an integer dtype."""
    ids = assign_cluster_ids(np.array([1.0, 2.0]), cross_tol=5.0)
    assert np.issubdtype(ids.dtype, np.integer)


# ---------------------------------------------------------------------------
# filter_by_mode_speed
# ---------------------------------------------------------------------------

def test_mode_speed_filter_excludes_outliers():
    """Speeds far from mode are masked out when only_joints=False."""
    speeds = np.array([80.0, 81.0, 80.0, 120.0])   # 120 is outlier
    keep, mode_speed = filter_by_mode_speed(speeds, speed_tol=10, only_joints=False)
    assert mode_speed == 80.0
    assert list(keep) == [True, True, True, False]


def test_mode_speed_filter_only_joints_keeps_all():
    """only_joints=True → no speed filtering, keep_mask all True."""
    speeds = np.array([80.0, 200.0])
    keep, mode_speed = filter_by_mode_speed(speeds, speed_tol=10, only_joints=True)
    assert all(keep)


def test_mode_speed_only_joints_still_computes_mode():
    """only_joints=True still returns a valid mode_speed."""
    speeds = np.array([80.0, 80.0, 120.0])
    keep, mode_speed = filter_by_mode_speed(speeds, speed_tol=10, only_joints=True)
    assert mode_speed == 80.0


def test_mode_speed_nan_excluded_from_mode():
    """NaN values are excluded from mode computation (valid_speeds = speeds(~isnan & >0))."""
    speeds = np.array([np.nan, 80.0, 80.0, 81.0])
    keep, mode_speed = filter_by_mode_speed(speeds, speed_tol=5, only_joints=False)
    assert mode_speed == 80.0
    # nan speed: ~isnan → False, so not kept
    assert keep[0] == False
    assert keep[1] == True
    assert keep[2] == True


def test_mode_speed_zero_excluded_from_valid():
    """Speeds <= 0 excluded from valid_speeds per MATLAB condition (speeds > 0)."""
    speeds = np.array([0.0, 80.0, 80.0])
    keep, mode_speed = filter_by_mode_speed(speeds, speed_tol=5, only_joints=False)
    assert mode_speed == 80.0
    # 0.0 is not NaN, but |0 - 80| = 80 > speed_tol → excluded by keep_mask
    assert keep[0] == False


def test_mode_speed_empty_valid_speeds_returns_nan_keep_all():
    """If no valid speeds, mode_speed=nan and keep_mask is all-True (MATLAB skips block)."""
    speeds = np.array([np.nan, np.nan])
    keep, mode_speed = filter_by_mode_speed(speeds, speed_tol=5, only_joints=False)
    assert np.isnan(mode_speed)
    assert all(keep)


def test_mode_speed_tie_break_smallest():
    """MATLAB mode tie-break: smallest most-frequent value wins."""
    # 80 and 90 appear equally often → MATLAB returns 80
    speeds = np.array([80.0, 90.0, 80.0, 90.0])
    keep, mode_speed = filter_by_mode_speed(speeds, speed_tol=5, only_joints=False)
    assert mode_speed == 80.0


def test_mode_speed_rounding_before_mode():
    """MATLAB does mode(round(valid_speeds)): 80.4 and 80.6 both round to 80."""
    speeds = np.array([80.4, 80.6, 80.4, 120.0])
    keep, mode_speed = filter_by_mode_speed(speeds, speed_tol=10, only_joints=False)
    # round → [80, 81, 80, 120]; mode = 80
    assert mode_speed == 80.0


def test_mode_speed_keep_mask_includes_boundary():
    """abs(speed - mode_speed) == speed_tol is kept (<=, not <)."""
    speeds = np.array([80.0, 90.0])   # |90 - 80| = 10 == speed_tol
    keep, mode_speed = filter_by_mode_speed(speeds, speed_tol=10, only_joints=False)
    assert mode_speed == 80.0
    assert list(keep) == [True, True]
