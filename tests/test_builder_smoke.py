"""Smoke test for database/builder.py — Task 12."""
import numpy as np
from scipy.io import savemat
from railway_inspector.config import default_config
from railway_inspector.database.builder import build_database_for_route


def _make_run(path, n=20000, res=0.004):
    """Create a synthetic .mat file with a strong repeatable defect burst.

    The burst is ~300 samples wide at amplitude 30, which far exceeds
    ABS_RMS_THRESH=5 over the RMS_WIN_FAST=1 m window (250 samples).
    """
    space = np.arange(n) * res
    sig = np.zeros(n)
    # Wide burst (300 samples) with high amplitude
    half = 150
    center = n // 2
    sig[center - half : center + half] = 30.0 * np.hanning(2 * half)
    d = {
        "section_extracted": {
            "space_neutral": space,
            "curve": np.sin(space),
            "left_sensor_front": sig,
            "left_sensor_rear": sig,
            "right_sensor_front": sig,
            "right_sensor_rear": sig,
            "speed_kmh": np.full(n, 80.0),
            "orientation": "moving forward",
            "time": np.arange(n) * 0.001,
        }
    }
    savemat(str(path), d)


def test_builder_runs_and_finds_cluster(tmp_path):
    c = default_config()
    c.ONLY_JOINTS = False
    c.ONLY_FORWARD = True
    files = []
    for k in range(3):
        p = tmp_path / f"RUN_2024010{k+1}_100000.mat"
        _make_run(p)
        files.append(str(p))

    db = build_database_for_route(
        files,
        route_name="TEST",
        cfg=c,
        track_map=None,
        route_joints=None,
        route_joint_labels=None,
    )

    assert isinstance(db, list)
    assert len(db) >= 1
    assert db[0]["Num_Occurrences"] >= 1


def test_relative_axis_center_matlab_round(tmp_path):
    """Regression: RelativeAxis must contain 0.0 and be centred at the MATLAB
    1-based round(N/2)-1 (0-based) sample, not at the Python banker's-round
    centre.  Verifies the off-by-one fix for Phase B _micro_align_and_crop."""
    c = default_config()
    c.ONLY_JOINTS = False
    c.ONLY_FORWARD = True
    files = []
    for k in range(3):
        p = tmp_path / f"RUN_2024020{k+1}_120000.mat"
        _make_run(p)
        files.append(str(p))

    db = build_database_for_route(
        files,
        route_name="TEST_CENTER",
        cfg=c,
        track_map=None,
        route_joints=None,
        route_joint_labels=None,
    )

    assert len(db) >= 1
    entry = db[0]
    assert len(entry["History"]) >= 1

    for hist in entry["History"]:
        rel_axis = np.asarray(hist["Data"]["RelativeAxis"], dtype=float)
        # The axis must be non-empty
        assert len(rel_axis) > 0, "RelativeAxis is empty"
        # 0.0 must be present (a sample sits exactly at the crop centre)
        assert 0.0 in rel_axis, (
            f"0.0 not in RelativeAxis; min|val|={np.min(np.abs(rel_axis)):.6f}, "
            f"axis={rel_axis[:5]}...{rel_axis[-5:]}"
        )
        # Axis must be symmetric: first and last samples are mirror images
        assert np.isclose(rel_axis[0], -rel_axis[-1], atol=c.SPATIAL_RES * 0.01), (
            f"RelativeAxis not symmetric: rel_axis[0]={rel_axis[0]}, "
            f"rel_axis[-1]={rel_axis[-1]}"
        )
