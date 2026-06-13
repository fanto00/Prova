"""
tests/test_extraction.py
========================
Tests for railway_inspector.detection.extraction
(Task 9 — TDD, math identical to MATLAB).
"""

import numpy as np
import pytest

from railway_inspector.config import default_config
from railway_inspector.detection.extraction import (
    peak_amp,
    extract_at_position,
    analyze_and_extract,
    extract_at_joints,
)


# ---------------------------------------------------------------------------
# peak_amp
# ---------------------------------------------------------------------------

def test_peak_amp_picks_max_abs_within_window():
    sig = {
        "RelativeAxis": np.linspace(-5, 5, 101),
        "Filt": {
            "left_sensor_front": np.zeros(101),
            "right_sensor_front": np.concatenate([np.zeros(50), [12.0], np.zeros(50)]),
        },
    }
    assert peak_amp(sig, half_w=5.0) == 12.0


def test_peak_amp_respects_window():
    axis = np.linspace(-10, 10, 201)
    f = np.zeros(201)
    f[0] = 99.0  # outside ±5 m
    sig = {"RelativeAxis": axis, "Filt": {"left_sensor_front": f}}
    assert peak_amp(sig, half_w=5.0) == 0.0


def test_peak_amp_no_relative_axis_uses_whole_window():
    """When RelativeAxis is absent, uses the entire Filt array."""
    sig = {
        "Filt": {
            "left_sensor_front": np.array([3.0, -7.0, 1.0]),
        }
    }
    assert peak_amp(sig, half_w=5.0) == 7.0


def test_peak_amp_scalar_filt_ignored():
    """Scalar Filt values (numel <= 1) are skipped per MATLAB `numel(v) > 1`."""
    sig = {
        "RelativeAxis": np.array([-1.0, 0.0, 1.0]),
        "Filt": {
            "right_sensor_front_lat": np.float32(0.0),   # scalar sentinel
            "left_sensor_front": np.array([0.0, 5.0, 0.0]),
        },
    }
    assert peak_amp(sig, half_w=1.0) == 5.0


def test_peak_amp_no_filt_returns_zero():
    sig = {"RelativeAxis": np.array([0.0])}
    assert peak_amp(sig, half_w=5.0) == 0.0


def test_peak_amp_empty_filt_returns_zero():
    sig = {"RelativeAxis": np.array([0.0]), "Filt": {}}
    assert peak_amp(sig, half_w=5.0) == 0.0


# ---------------------------------------------------------------------------
# extract_at_position — integration
# ---------------------------------------------------------------------------

def _make_synthetic_data(cfg, n=30_000, speed=80.0):
    """Synthetic data dict with a strong localized feature in the centre."""
    space = np.arange(n) * cfg.SPATIAL_RES
    center = n // 2
    sig = np.zeros(n)
    sig[center - 100:center + 100] = 15.0 * np.hanning(200)
    return {
        "space_neutral": space,
        "left_sensor_front":  sig.copy(),
        "left_sensor_rear":   sig.copy(),
        "right_sensor_front": sig.copy(),
        "right_sensor_rear":  sig.copy(),
        "speed_kmh": np.full(n, speed),
        "curve":     np.zeros(n),
    }, space[center]


def test_extract_at_position_returns_window():
    c = default_config()
    data, target = _make_synthetic_data(c)
    out = extract_at_position(data, target, c, c.fmin, c.fmax)
    assert out is not None
    assert "left_sensor_front" in out["Filt"]
    assert abs(out["RelativeAxis"].min() + c.WINDOW_EXTRACT) < 0.5
    assert abs(out["RelativeAxis"].max() - c.WINDOW_EXTRACT) < 0.5


def test_extract_at_position_filt_is_float32():
    c = default_config()
    data, target = _make_synthetic_data(c)
    out = extract_at_position(data, target, c, c.fmin, c.fmax)
    assert out is not None
    for nm, arr in out["Filt"].items():
        if np.ndim(arr) > 0:
            assert arr.dtype == np.float32, f"{nm} dtype={arr.dtype}"


def test_extract_at_position_returns_none_outside_coverage():
    c = default_config()
    data, _ = _make_synthetic_data(c)
    space = data["space_neutral"]
    # Request a position too close to the start — should return None
    out = extract_at_position(data, space[0] + 0.1, c, c.fmin, c.fmax)
    assert out is None


def test_extract_at_position_speed_curve_fields():
    c = default_config()
    data, target = _make_synthetic_data(c, speed=60.0)
    out = extract_at_position(data, target, c, c.fmin, c.fmax)
    assert out is not None
    assert "Speed" in out
    assert "Curve" in out
    assert abs(float(out["Speed"]) - 60.0) < 5.0


def test_extract_at_position_lateral_sentinel():
    """Lateral sensors absent → Filt[lateral_name] == single(0) scalar."""
    c = default_config()
    data, target = _make_synthetic_data(c)
    out = extract_at_position(data, target, c, c.fmin, c.fmax)
    assert out is not None
    for lat in ("right_sensor_front_lat", "right_sensor_rear_lat",
                "left_sensor_front_lat", "left_sensor_rear_lat"):
        assert lat in out["Filt"]
        v = out["Filt"][lat]
        assert np.ndim(v) == 0 or (np.ndim(v) == 1 and len(v) == 1)
        assert float(v) == 0.0


def test_extract_at_position_space_parameters():
    """Test axis handling via space_parameters (front/back offsets)."""
    c = default_config()
    n = 30_000
    space = np.arange(n) * c.SPATIAL_RES
    center = n // 2
    sig = np.zeros(n)
    sig[center - 100:center + 100] = 15.0 * np.hanning(200)
    data = {
        "space_neutral": space,
        "space_parameters": {"front": 0.2, "back": -0.2},
        "left_sensor_front":  sig.copy(),
        "left_sensor_rear":   sig.copy(),
        "right_sensor_front": sig.copy(),
        "right_sensor_rear":  sig.copy(),
        "speed_kmh": np.full(n, 80.0),
        "curve":     np.zeros(n),
    }
    target = space[center]
    out = extract_at_position(data, target, c, c.fmin, c.fmax)
    assert out is not None
    assert "left_sensor_front" in out["Filt"]


# ---------------------------------------------------------------------------
# analyze_and_extract — integration
# ---------------------------------------------------------------------------

def _make_data_with_two_peaks(cfg):
    """Two strong localized features well inside coverage."""
    n = 60_000
    space = np.arange(n) * cfg.SPATIAL_RES
    sig = np.zeros(n)
    for center in [n // 4, 3 * n // 4]:
        sig[center - 100:center + 100] += 30.0 * np.hanning(200)
    data = {
        "space_neutral": space,
        "left_sensor_front":  sig.copy(),
        "left_sensor_rear":   sig.copy(),
        "right_sensor_front": sig.copy(),
        "right_sensor_rear":  sig.copy(),
        "speed_kmh": np.full(n, 80.0),
        "curve":     np.zeros(n),
    }
    return data


def test_analyze_and_extract_returns_list():
    c = default_config()
    data = _make_data_with_two_peaks(c)
    events = analyze_and_extract(data, c, c.fmin, c.fmax)
    assert isinstance(events, list)


def test_analyze_and_extract_finds_events():
    c = default_config()
    data = _make_data_with_two_peaks(c)
    events = analyze_and_extract(data, c, c.fmin, c.fmax)
    assert len(events) >= 1


def test_analyze_and_extract_event_structure():
    c = default_config()
    data = _make_data_with_two_peaks(c)
    events = analyze_and_extract(data, c, c.fmin, c.fmax)
    assert len(events) >= 1
    ev = events[0]
    assert "Pos" in ev
    assert "Amp" in ev
    assert "Signals" in ev
    sig = ev["Signals"]
    assert "RelativeAxis" in sig
    assert "Speed" in sig
    assert "Curve" in sig
    assert "Filt" in sig
    assert "left_sensor_front" in sig["Filt"]


def test_analyze_and_extract_edge_filter():
    """Events inside WINDOW_EXTRACT of the boundary must be excluded."""
    c = default_config()
    n = 60_000
    space = np.arange(n) * c.SPATIAL_RES
    sig = np.zeros(n)
    # Place a peak very close to the start boundary — should be filtered out
    sig[5:205] = 30.0 * np.hanning(200)
    data = {
        "space_neutral": space,
        "left_sensor_front":  sig.copy(),
        "left_sensor_rear":   sig.copy(),
        "right_sensor_front": sig.copy(),
        "right_sensor_rear":  sig.copy(),
        "speed_kmh": np.full(n, 80.0),
        "curve":     np.zeros(n),
    }
    events = analyze_and_extract(data, c, c.fmin, c.fmax)
    min_safe = space.min() + c.WINDOW_EXTRACT
    for ev in events:
        assert ev["Pos"] >= min_safe - 1e-9


# ---------------------------------------------------------------------------
# extract_at_joints
# ---------------------------------------------------------------------------

def test_extract_at_joints_returns_list():
    c = default_config()
    data, center = _make_synthetic_data(c)
    events = extract_at_joints(data, [center], ["J1"], c, c.fmin, c.fmax)
    assert isinstance(events, list)


def test_extract_at_joints_has_label():
    c = default_config()
    data, center = _make_synthetic_data(c)
    events = extract_at_joints(data, [center], ["J1"], c, c.fmin, c.fmax)
    assert len(events) == 1
    assert events[0]["Label"] == "J1"


def test_extract_at_joints_wider_window():
    """Stored RelativeAxis span should be JOINT_WINDOW + ALIGN_MAX_LAG + 1.0."""
    c = default_config()
    data, center = _make_synthetic_data(c)
    events = extract_at_joints(data, [center], ["J1"], c, c.fmin, c.fmax)
    assert len(events) == 1
    ra = events[0]["Signals"]["RelativeAxis"]
    expected_half = c.JOINT_WINDOW + c.ALIGN_MAX_LAG + 1.0
    assert abs(ra.min() + expected_half) < 0.5
    assert abs(ra.max() - expected_half) < 0.5


def test_extract_at_joints_amp_uses_joint_window():
    """Amplitude should be the peak within ±JOINT_WINDOW (not the wider window)."""
    c = default_config()
    data, center = _make_synthetic_data(c)
    events = extract_at_joints(data, [center], ["J1"], c, c.fmin, c.fmax)
    assert len(events) == 1
    assert events[0]["Amp"] >= 0.0


def test_extract_at_joints_skips_out_of_range():
    """Joint positions outside data coverage produce no events."""
    c = default_config()
    data, _ = _make_synthetic_data(c)
    events = extract_at_joints(data, [-999.0], ["J_bad"], c, c.fmin, c.fmax)
    assert len(events) == 0


def test_extract_at_joints_multiple_joints():
    c = default_config()
    n = 60_000
    space = np.arange(n) * c.SPATIAL_RES
    centers = [n // 4, 3 * n // 4]
    sig = np.zeros(n)
    for ct in centers:
        sig[ct - 100:ct + 100] += 20.0 * np.hanning(200)
    data = {
        "space_neutral": space,
        "left_sensor_front":  sig.copy(),
        "left_sensor_rear":   sig.copy(),
        "right_sensor_front": sig.copy(),
        "right_sensor_rear":  sig.copy(),
        "speed_kmh": np.full(n, 80.0),
        "curve":     np.zeros(n),
    }
    positions = [space[ct] for ct in centers]
    labels = ["J1", "J2"]
    events = extract_at_joints(data, positions, labels, c, c.fmin, c.fmax)
    assert len(events) == 2
    assert events[0]["Label"] == "J1"
    assert events[1]["Label"] == "J2"
