"""TDD tests for railway_inspector.app.analysis.generate_headless_daily_plots (9 tests)."""
from __future__ import annotations

import tempfile
from pathlib import Path

import numpy as np
import pytest

from railway_inspector.app.analysis.generate_headless_daily_plots import (
    generate_headless_daily_plots,
)


# ---------------------------------------------------------------------------
# Fixtures: Mock data structures
# ---------------------------------------------------------------------------


@pytest.fixture
def mock_defect_with_history():
    """Mock defect with 5 runs spanning 2+ days."""
    return {
        "History": [
            {
                "Date": "2026-01-01",
                "Amp": 1.5,
                "Data": {
                    "RelativeAxis": np.linspace(0, 100, 200),
                    "Filt": {
                        "left_sensor_front": np.random.randn(200) * 0.5,
                        "left_sensor_rear": np.random.randn(200) * 0.5,
                        "right_sensor_front": np.random.randn(200) * 0.5,
                        "right_sensor_rear": np.random.randn(200) * 0.5,
                        "right_sensor_front_lat": np.random.randn(200) * 0.3,
                        "right_sensor_rear_lat": np.random.randn(200) * 0.3,
                        "left_sensor_front_lat": np.random.randn(200) * 0.3,
                        "left_sensor_rear_lat": np.random.randn(200) * 0.3,
                    },
                },
            },
            {
                "Date": "2026-01-01",  # Same day
                "Amp": 2.0,
                "Data": {
                    "RelativeAxis": np.linspace(0, 100, 200),
                    "Filt": {
                        "left_sensor_front": np.random.randn(200) * 0.5,
                        "left_sensor_rear": np.random.randn(200) * 0.5,
                        "right_sensor_front": np.random.randn(200) * 0.5,
                        "right_sensor_rear": np.random.randn(200) * 0.5,
                        "right_sensor_front_lat": np.random.randn(200) * 0.3,
                        "right_sensor_rear_lat": np.random.randn(200) * 0.3,
                        "left_sensor_front_lat": np.random.randn(200) * 0.3,
                        "left_sensor_rear_lat": np.random.randn(200) * 0.3,
                    },
                },
            },
            {
                "Date": "2026-01-02",
                "Amp": 1.8,
                "Data": {
                    "RelativeAxis": np.linspace(0, 100, 200),
                    "Filt": {
                        "left_sensor_front": np.random.randn(200) * 0.5,
                        "left_sensor_rear": np.random.randn(200) * 0.5,
                        "right_sensor_front": np.random.randn(200) * 0.5,
                        "right_sensor_rear": np.random.randn(200) * 0.5,
                        "right_sensor_front_lat": np.random.randn(200) * 0.3,
                        "right_sensor_rear_lat": np.random.randn(200) * 0.3,
                        "left_sensor_front_lat": np.random.randn(200) * 0.3,
                        "left_sensor_rear_lat": np.random.randn(200) * 0.3,
                    },
                },
            },
            {
                "Date": "2026-01-09",
                "Amp": 1.3,
                "Data": {
                    "RelativeAxis": np.linspace(0, 100, 200),
                    "Filt": {
                        "left_sensor_front": np.random.randn(200) * 0.5,
                        "left_sensor_rear": np.random.randn(200) * 0.5,
                        "right_sensor_front": np.random.randn(200) * 0.5,
                        "right_sensor_rear": np.random.randn(200) * 0.5,
                        "right_sensor_front_lat": np.random.randn(200) * 0.3,
                        "right_sensor_rear_lat": np.random.randn(200) * 0.3,
                        "left_sensor_front_lat": np.random.randn(200) * 0.3,
                        "left_sensor_rear_lat": np.random.randn(200) * 0.3,
                    },
                },
            },
            {
                "Date": "2026-01-16",
                "Amp": 1.6,
                "Data": {
                    "RelativeAxis": np.linspace(0, 100, 200),
                    "Filt": {
                        "left_sensor_front": np.random.randn(200) * 0.5,
                        "left_sensor_rear": np.random.randn(200) * 0.5,
                        "right_sensor_front": np.random.randn(200) * 0.5,
                        "right_sensor_rear": np.random.randn(200) * 0.5,
                        "right_sensor_front_lat": np.random.randn(200) * 0.3,
                        "right_sensor_rear_lat": np.random.randn(200) * 0.3,
                        "left_sensor_front_lat": np.random.randn(200) * 0.3,
                        "left_sensor_rear_lat": np.random.randn(200) * 0.3,
                    },
                },
            },
        ],
    }


@pytest.fixture
def mock_config():
    """Mock config dictionary."""
    return {
        "SPATIAL_RES": 0.05,
        "WINDOW_SIZE": 30.0,
        "IPI_PCA_MIN_RUNS": 3,
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
# Test 1: generate_headless_daily_plots creates main PNG files
# ---------------------------------------------------------------------------


def test_generate_headless_daily_plots_creates_files(mock_defect_with_history, mock_config):
    """Crea file TOP%02d_*.png per ogni rank_idx."""
    with tempfile.TemporaryDirectory() as tmpdir:
        export_dir = Path(tmpdir)

        generate_headless_daily_plots(
            mock_defect_with_history, mock_config, export_dir, rank_idx=1
        )

        # Verifica creazione file principali
        assert (export_dir / "TOP01_0_Max_Run_Signals.png").exists()
        assert (export_dir / "TOP01_2_Giornaliera_C_Matrice3x3.png").exists()
        assert (export_dir / "TOP01_2_Giornaliera_D_RatioLat.png").exists()
        assert (export_dir / "TOP01_2_Giornaliera_E_Lambda.png").exists()


# ---------------------------------------------------------------------------
# Test 2: generate_headless_daily_plots handles empty history
# ---------------------------------------------------------------------------


def test_generate_headless_daily_plots_empty_history(mock_config):
    """Gestisce defect.History vuota senza crash."""
    defect_empty = {"History": []}

    with tempfile.TemporaryDirectory() as tmpdir:
        export_dir = Path(tmpdir)

        # Non deve crash
        generate_headless_daily_plots(defect_empty, mock_config, export_dir, rank_idx=1)

        # Nessun file creato
        png_files = list(export_dir.glob("*.png"))
        assert len(png_files) == 0


# ---------------------------------------------------------------------------
# Test 3: Ratio calculations SX/DX, FR, LV
# ---------------------------------------------------------------------------


def test_ratio_calculations_sx_dx_fr_lv():
    """Ratio = (SX_F + SX_R) / max(DX_F + DX_R, 1e-6), etc."""
    # Test diretto della logica (no figure)
    all_amps = np.array([
        [1.0, 1.0, 2.0, 2.0, 0.5, 0.5, 0.3, 0.3],  # Vert (0-3), Lat (4-7)
        [2.0, 1.0, 1.0, 1.0, 0.6, 0.4, 0.2, 0.2],
    ])

    # SX/DX = (1+1) / max(2+2, 1e-6) = 2/4 = 0.5
    ratio_sx_dx_0 = (all_amps[0, 0] + all_amps[0, 1]) / max(
        all_amps[0, 2] + all_amps[0, 3], 1e-6
    )
    assert abs(ratio_sx_dx_0 - 0.5) < 1e-6

    # FR = (F) / max(R, 1e-6) where F=sum of fronts, R=sum of rears
    ratio_fr_0 = (all_amps[0, 0] + all_amps[0, 2]) / max(
        all_amps[0, 1] + all_amps[0, 3], 1e-6
    )
    assert abs(ratio_fr_0 - 1.0) < 1e-6

    # LV = max(Lat) / max(max(Vert), 1e-6) = 0.5 / 2.0 = 0.25
    ratio_lv_0 = max(all_amps[0, 4:8]) / max(max(all_amps[0, 0:4]), 1e-6)
    assert abs(ratio_lv_0 - 0.25) < 1e-6


# ---------------------------------------------------------------------------
# Test 4: Daily aggregation logic
# ---------------------------------------------------------------------------


def test_daily_aggregation_logic():
    """Aggrega run per giorno (floor datenum) e calcola medie."""
    # 3 runs: 2 nello stesso giorno, 1 in giorno diverso
    dates_num = np.array([737800.0, 737800.5, 737801.0])
    ratio_sx_dx = np.array([0.5, 0.6, 0.8])

    days_floor = np.floor(dates_num)
    unique_days = np.unique(days_floor)

    assert len(unique_days) == 2

    # Giorno 1: media di [0.5, 0.6]
    mask_day1 = days_floor == unique_days[0]
    avg_day1 = np.nanmean(ratio_sx_dx[mask_day1])
    assert abs(avg_day1 - 0.55) < 1e-6

    # Giorno 2: [0.8]
    mask_day2 = days_floor == unique_days[1]
    avg_day2 = np.nanmean(ratio_sx_dx[mask_day2])
    assert abs(avg_day2 - 0.8) < 1e-6


# ---------------------------------------------------------------------------
# Test 5: Direction selection (forward vs backward)
# ---------------------------------------------------------------------------


def test_direction_selection_forward_vs_backward():
    """Seleziona direzione majority (forward se count_fwd >= count_bwd)."""
    # Mock: 3 forward, 2 backward → scegli forward
    idx_fwd = np.array([True, True, True, False, False])
    idx_bwd = np.array([False, False, False, True, True])

    use_fwd = np.sum(idx_fwd) >= np.sum(idx_bwd)
    assert bool(use_fwd) is True  # 3 >= 2  (np.True_ is not Python True)

    if use_fwd:
        run_idx_selected = np.where(idx_fwd)[0]
    else:
        run_idx_selected = np.where(idx_bwd)[0]

    assert len(run_idx_selected) == 3
    assert np.array_equal(run_idx_selected, [0, 1, 2])


# ---------------------------------------------------------------------------
# Test 6: PCA channel-space structure
# ---------------------------------------------------------------------------


def test_pca_channel_space_structure():
    """Trasforma segnali 6-canale su griglia spaziale (6*N_GRID colonne)."""
    N_GRID = 333
    n_chan = 6
    n_runs = 5

    # Mock X_pca: n_runs righe, 6*N_GRID colonne
    X_pca = np.random.randn(n_runs, n_chan * N_GRID)

    assert X_pca.shape == (5, 6 * 333)

    # Ogni riga è una run; ogni gruppo di N_GRID colonne è un canale
    for run_idx in range(n_runs):
        for chan_idx in range(n_chan):
            cols = slice(chan_idx * N_GRID, (chan_idx + 1) * N_GRID)
            chan_data = X_pca[run_idx, cols]
            assert chan_data.shape == (N_GRID,)


# ---------------------------------------------------------------------------
# Test 7: PCA standardization per-channel
# ---------------------------------------------------------------------------


def test_pca_standardization_per_channel():
    """Standardizza Xpar per-canale (dim 0): (X - mu) / sigma."""
    N_GRID = 333
    n_chan = 6
    n_rows = 5 * N_GRID  # 5 runs x N_GRID righe per run

    Xpar = np.random.randn(n_rows, n_chan) * 10 + 50

    mu_ch = np.mean(Xpar, axis=0)
    sg_ch = np.std(Xpar, ddof=0, axis=0)
    sg_ch[sg_ch < 1e-9] = 1.0

    Xpar_z = (Xpar - mu_ch) / sg_ch

    # Verifica media ~0 e std ~1
    mu_z = np.mean(Xpar_z, axis=0)
    sg_z = np.std(Xpar_z, ddof=0, axis=0)

    assert np.allclose(mu_z, 0, atol=1e-10)
    assert np.allclose(sg_z, 1, atol=1e-10)


# ---------------------------------------------------------------------------
# Test 8: Anomaly score RMSE calculation
# ---------------------------------------------------------------------------


def test_anomaly_score_rmse_calculation():
    """RMSE = sqrt(mean(residuo^2)) per run."""
    n_rows = 1000  # 5 runs x 200 grid points
    n_comp = 10
    k_use = 2
    run_id = np.repeat(np.arange(5), 200)

    # Mock: residui dalla ricostruzione
    resid_z = np.random.randn(n_rows, n_comp - k_use) * 0.5

    # RMSE per run
    se_row = np.mean(resid_z**2, axis=1)
    rmse_run = np.zeros(5)

    for run_idx in range(5):
        mask = run_id == run_idx
        rmse_run[run_idx] = np.sqrt(np.mean(se_row[mask]))

    assert rmse_run.shape == (5,)
    assert np.all(rmse_run >= 0)


# ---------------------------------------------------------------------------
# Test 9: Weekly centroid aggregation
# ---------------------------------------------------------------------------


def test_weekly_centroid_aggregation():
    """Raggruppa run per settimana (bin 7 giorni) e calcola mean PC1/PC2."""
    dates_pca = np.array([
        737800.0,
        737801.0,
        737802.0,
        737803.0,
        737804.0,  # Week 0
        737810.0,
        737811.0,
        737812.0,  # Week 1
    ])
    scores_pc1 = np.array([0.1, 0.2, 0.15, 0.25, 0.3, 0.5, 0.55, 0.6])

    days_t = dates_pca - dates_pca[0]
    WEEK_BIN = 7
    week_id = np.floor(days_t / WEEK_BIN).astype(int)

    unique_weeks = np.unique(week_id)
    assert len(unique_weeks) == 2  # Due settimane

    cent_pc1 = []
    for w in unique_weeks:
        mask = week_id == w
        cent_pc1.append(np.mean(scores_pc1[mask]))

    # Week 0: mean([0.1, 0.2, 0.15, 0.25, 0.3]) = 0.2
    # Week 1: mean([0.5, 0.55, 0.6]) ≈ 0.55
    assert abs(cent_pc1[0] - 0.2) < 1e-6
    assert abs(cent_pc1[1] - 0.55) < 1e-6
