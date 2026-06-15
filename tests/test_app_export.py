"""TDD tests for railway_inspector.app.analysis.export (8 tests)."""
from __future__ import annotations

import tempfile
from pathlib import Path

import numpy as np
import pytest

from railway_inspector.app.analysis.export import (
    generate_overview_figure,
    generate_global_scatter,
    export_report_latex,
    _format_latex_safe,
)


# ---------------------------------------------------------------------------
# Fixtures: Mock data structures
# ---------------------------------------------------------------------------


@pytest.fixture
def mock_data_full():
    """Mock data_full structure (section_extracted)."""
    return {
        "space_neutral": np.linspace(0, 10000, 10000),
        "left_sensor_front": np.random.randn(10000) * 0.5,
        "left_sensor_rear": np.random.randn(10000) * 0.5,
        "right_sensor_front": np.random.randn(10000) * 0.5,
        "right_sensor_rear": np.random.randn(10000) * 0.5,
        "right_sensor_front_lat": np.random.randn(10000) * 0.3,
        "left_sensor_front_lat": np.random.randn(10000) * 0.3,
        "speed": np.full(10000, 80.0),
        "curve": np.random.randn(10000) * 0.1,
    }


@pytest.fixture
def mock_space_shifted():
    """Mock space_shifted array."""
    return np.linspace(0, 10000, 10000)


@pytest.fixture
def mock_joints_table():
    """Mock joints_table DataFrame."""
    import pandas as pd

    return pd.DataFrame({
        "Stations": ["Track_A", "Track_A", "Track_A"],
        "Position": [1000, 5000, 9000],
        "Joint": ["J1", "J2", "J3"],
    })


@pytest.fixture
def mock_sorted_ipi():
    """Mock sorted_ipi list (top 10 defects)."""
    return [
        {
            "ID": f"PK_{i*100:04d}",
            "IPI": 75 + (10 - i) * 3,  # Descending IPI
            "STrend": 20.0,
            "BonusLat": 5.0,
            "RecentRMS": 2.0 + i * 0.1,
            "BonusIA": 2.0,
            "BonusPCA": 3.0,
            "MaxVert": 10.0 - i,
            "MaxLat": 5.0 - i * 0.5,
            "IncPerc": 15.0 - i,
        }
        for i in range(5)
    ]


@pytest.fixture
def mock_db():
    """Mock DB list with defect information."""
    return [
        {
            "ID_PK": f"PK_{i*100:04d}",
            "Avg_Pos": 500 + i * 1000,
            "History": [{"Date": "2026-01-01", "RMS": 1.0 + i * 0.1}],
        }
        for i in range(5)
    ]


@pytest.fixture
def mock_config():
    """Mock config dictionary."""
    return {
        "SPATIAL_RES": 0.05,
        "IPI_RECENT_DAYS": 30,
        "IPI_SEV_THR_HIGH": 3.0,
        "IPI_SEV_THR_LOW": 1.0,
        "IPI_TREND_SENS": 50,
        "IPI_LAT_THRESH": 0.6,
        "IPI_MIN_RUNS": 5,
        "IPI_MIN_HISTORY_DAYS": 30,
        "IPI_MIN_DAYS": 5,
    }


# ---------------------------------------------------------------------------
# Test 1: generate_overview_figure creates PNG file
# ---------------------------------------------------------------------------


def test_generate_overview_figure_creates_file(
    mock_data_full, mock_space_shifted, mock_joints_table, mock_sorted_ipi, mock_db, mock_config
):
    """generate_overview_figure() crea 00_Overview_Track_RAW.png."""
    with tempfile.TemporaryDirectory() as tmpdir:
        export_dir = Path(tmpdir)

        success = generate_overview_figure(
            mock_data_full,
            mock_space_shifted,
            mock_joints_table,
            mock_sorted_ipi,
            mock_db,
            mock_config,
            export_dir,
        )

        assert success is True
        assert (export_dir / "00_Overview_Track_RAW.png").exists()


# ---------------------------------------------------------------------------
# Test 2: generate_overview_figure handles empty joints
# ---------------------------------------------------------------------------


def test_generate_overview_figure_empty_joints(
    mock_data_full, mock_space_shifted, mock_sorted_ipi, mock_db, mock_config
):
    """generate_overview_figure() gestisce joints_table vuota."""
    import pandas as pd

    with tempfile.TemporaryDirectory() as tmpdir:
        export_dir = Path(tmpdir)
        empty_joints = pd.DataFrame(columns=["Stations", "Position", "Joint"])

        success = generate_overview_figure(
            mock_data_full,
            mock_space_shifted,
            empty_joints,
            mock_sorted_ipi,
            mock_db,
            mock_config,
            export_dir,
        )

        assert success is True
        assert (export_dir / "00_Overview_Track_RAW.png").exists()


# ---------------------------------------------------------------------------
# Test 3: generate_global_scatter creates figure
# ---------------------------------------------------------------------------


def test_generate_global_scatter_creates_figure(mock_config):
    """generate_global_scatter() crea figura con 4 subplot."""
    # Mock 4 DataStore objects
    data_store = [
        {
            "Name": f"Sensor_{i}",
            "Filt": {
                "MovF": np.random.rand(10) * 5,
                "MovR": np.random.rand(10) * 5,
                "DefectID": np.arange(10),
            },
        }
        for i in range(4)
    ]

    with tempfile.TemporaryDirectory() as tmpdir:
        export_dir = Path(tmpdir)
        fig, axes = generate_global_scatter(data_store, mock_config, export_dir)

        assert fig is not None
        assert axes is not None
        assert len(axes) == 4  # 2x2 grid
        assert (export_dir / "00_Global_Scatter_RMS.png").exists()


# ---------------------------------------------------------------------------
# Test 4: generate_global_scatter asymmetry logic
# ---------------------------------------------------------------------------


def test_generate_global_scatter_asymmetry_logic():
    """Test asimmetria logic: ratio > 1.5 or ratio < 0.66."""
    vF = np.array([1.0, 2.0, 3.0, 0.5])
    vR = np.array([1.0, 1.0, 1.0, 1.0])

    ratio = vF / np.maximum(vR, 1e-6)
    asym_mask = (ratio > 1.5) | (ratio < 0.66)

    # Expected: [False (1.0), True (2.0), True (3.0), True (0.5)]
    expected = [False, True, True, True]
    assert np.array_equal(asym_mask, expected)


# ---------------------------------------------------------------------------
# Test 5: export_report_latex creates .tex file
# ---------------------------------------------------------------------------


def test_export_report_latex_creates_file(mock_sorted_ipi, mock_db, mock_config):
    """export_report_latex() scrive file .tex."""
    with tempfile.TemporaryDirectory() as tmpdir:
        export_dir = Path(tmpdir)

        success = export_report_latex(
            mock_sorted_ipi[:3],
            mock_db,
            export_dir,
            track_name="Test_Track",
            config=mock_config,
            has_overview=True,
        )

        assert success is True
        tex_file = export_dir / "Report_Tratta_Test-Track.tex"
        assert tex_file.exists()


# ---------------------------------------------------------------------------
# Test 6: export_report_latex includes LaTeX document structure
# ---------------------------------------------------------------------------


def test_export_report_latex_document_structure(mock_sorted_ipi, mock_db, mock_config):
    """export_report_latex() contiene \documentclass e \maketitle."""
    with tempfile.TemporaryDirectory() as tmpdir:
        export_dir = Path(tmpdir)

        export_report_latex(
            mock_sorted_ipi[:3],
            mock_db,
            export_dir,
            track_name="Test_Track",
            config=mock_config,
            has_overview=True,
        )

        tex_file = export_dir / "Report_Tratta_Test-Track.tex"
        content = tex_file.read_text(encoding="utf-8")

        assert r"\documentclass[11pt]{article}" in content
        assert r"\maketitle" in content
        assert r"\begin{document}" in content
        assert r"\end{document}" in content


# ---------------------------------------------------------------------------
# Test 7: export_report_latex creates sections for top defects
# ---------------------------------------------------------------------------


def test_export_report_latex_top_sections(mock_sorted_ipi, mock_db, mock_config):
    """export_report_latex() crea una sezione per ogni top defect."""
    with tempfile.TemporaryDirectory() as tmpdir:
        export_dir = Path(tmpdir)

        export_report_latex(
            mock_sorted_ipi[:5],  # 5 defects
            mock_db,
            export_dir,
            track_name="Test_Track",
            config=mock_config,
            has_overview=False,
        )

        tex_file = export_dir / "Report_Tratta_Test-Track.tex"
        content = tex_file.read_text(encoding="utf-8")

        # Count sections Posizione #i
        num_sections = content.count(r"\section{Posizione \#")
        assert num_sections == 5


# ---------------------------------------------------------------------------
# Test 8: _format_latex_safe escapes underscores
# ---------------------------------------------------------------------------


def test_format_latex_safe_escapes_underscores():
    """_format_latex_safe() converte underscore in \_."""
    assert _format_latex_safe("Track_Name_01") == r"Track\_Name\_01"
    assert _format_latex_safe("Normal") == "Normal"
    assert _format_latex_safe("A_B_C") == r"A\_B\_C"
    assert _format_latex_safe("PK_0001") == r"PK\_0001"
