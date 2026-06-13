import numpy as np
from scipy.io import savemat
from datetime import datetime
from railway_inspector.io.mat_loader import load_section, parse_run_date


def test_load_section_reads_fields(tmp_path):
    """Test that load_section reads fields from section_extracted in .mat file."""
    p = tmp_path / "run.mat"
    savemat(
        str(p),
        {
            "section_extracted": {
                "space_neutral": np.arange(10.0),
                "left_sensor_front": np.ones(10),
            }
        },
    )
    sec = load_section(str(p))
    assert "space_neutral" in sec
    np.testing.assert_allclose(np.asarray(sec["space_neutral"]).ravel(), np.arange(10.0))
    assert "left_sensor_front" in sec
    np.testing.assert_allclose(np.asarray(sec["left_sensor_front"]).ravel(), np.ones(10))


def test_parse_run_date_from_filename():
    """Test that parse_run_date extracts date from filename when section lacks time_start."""
    d = parse_run_date("RUN_20240115_103000", section={})
    assert d.year == 2024
    assert d.month == 1
    assert d.day == 15
    assert d.hour == 10
    assert d.minute == 30
    assert d.second == 0


def test_parse_run_date_from_time_start():
    """Test that parse_run_date prioritizes section.time_start if present."""
    section = {"time_start": np.datetime64("2024-01-15T10:30:00")}
    d = parse_run_date("IGNORED_20240101_000000", section=section)
    assert d.year == 2024
    assert d.month == 1
    assert d.day == 15
    assert d.hour == 10
    assert d.minute == 30
    assert d.second == 0


def test_parse_run_date_handles_various_formats():
    """Test parse_run_date with different filename patterns."""
    # Different run name, same date/time format
    d = parse_run_date("MYRUN_20231225_235959", section={})
    assert d.year == 2023
    assert d.month == 12
    assert d.day == 25
    assert d.hour == 23
    assert d.minute == 59
    assert d.second == 59
