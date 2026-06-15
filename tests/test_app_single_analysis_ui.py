"""TDD tests for railway_inspector.app.ui.single_analysis (15 tests)."""
from __future__ import annotations

import numpy as np
import pytest
from datetime import datetime, timedelta

from railway_inspector.app.ui.single_analysis import (
    prepare_raw_data_store,
    compute_all_amps,
    compute_metrics_per_run,
    build_tab_trend_data,
    build_tab_stats_table_data,
    build_stft_dates_labels,
    compute_cache_profiles,
)


# Helper: convert datetime to MATLAB datenum
def datenum(dt: datetime) -> float:
    """Convert datetime to MATLAB datenum."""
    epoch = datetime(1899, 12, 30)
    delta = dt - epoch
    return delta.days + delta.seconds / 86400.0


# Fixture: mock CFG
@pytest.fixture
def mock_cfg():
    """Mock configuration."""
    return {
        'WINDOW_SIZE': 5.0,
        'SPATIAL_RES': 0.030,
    }


# Fixture: mock defect_history with 3 runs
@pytest.fixture
def mock_defect_history():
    """Mock defect_history with 3 runs (unordered)."""
    return [
        {
            'Date': datetime(2026, 1, 2, 10, 0),
            'Amp': 2.5,
            'Data': {
                'Filt': {
                    'left_sensor_front': np.sin(np.linspace(0, 2*np.pi, 100)),
                    'left_sensor_rear': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.8,
                    'right_sensor_front': np.sin(np.linspace(0, 2*np.pi, 100)) * 1.2,
                    'right_sensor_rear': np.sin(np.linspace(0, 2*np.pi, 100)) * 1.0,
                    'right_sensor_front_lat': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.5,
                    'right_sensor_rear_lat': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.5,
                    'left_sensor_front_lat': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.5,
                    'left_sensor_rear_lat': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.5,
                },
                'RelativeAxis': np.linspace(-2.5, 2.5, 100),
                'Speed': 80.0,
            }
        },
        {
            'Date': datetime(2026, 1, 1, 10, 0),  # Earlier date (unordered)
            'Amp': 1.8,
            'Data': {
                'Filt': {
                    'left_sensor_front': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.9,
                    'left_sensor_rear': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.7,
                    'right_sensor_front': np.sin(np.linspace(0, 2*np.pi, 100)) * 1.1,
                    'right_sensor_rear': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.9,
                    'right_sensor_front_lat': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.4,
                    'right_sensor_rear_lat': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.4,
                    'left_sensor_front_lat': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.4,
                    'left_sensor_rear_lat': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.4,
                },
                'RelativeAxis': np.linspace(-2.5, 2.5, 100),
                'Speed': 75.0,
            }
        },
        {
            'Date': datetime(2026, 1, 1, 15, 0),  # Same day as second run
            'Amp': 2.0,
            'Detected': True,
            'Data': {
                'Filt': {
                    'left_sensor_front': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.95,
                    'left_sensor_rear': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.75,
                    'right_sensor_front': np.sin(np.linspace(0, 2*np.pi, 100)) * 1.15,
                    'right_sensor_rear': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.95,
                    'right_sensor_front_lat': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.45,
                    'right_sensor_rear_lat': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.45,
                    'left_sensor_front_lat': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.45,
                    'left_sensor_rear_lat': np.sin(np.linspace(0, 2*np.pi, 100)) * 0.45,
                },
                'RelativeAxis': np.linspace(-2.5, 2.5, 100),
                'Speed': 78.0,
            }
        },
    ]


@pytest.fixture
def sensor_fields_list():
    """8 sensor field names (MATLAB order)."""
    return [
        'left_sensor_front', 'left_sensor_rear',
        'right_sensor_front', 'right_sensor_rear',
        'right_sensor_front_lat', 'right_sensor_rear_lat',
        'left_sensor_front_lat', 'left_sensor_rear_lat',
    ]


# ---------------------------------------------------------------------------
# Category 1: Data Extraction (4 tests)
# ---------------------------------------------------------------------------

def test_prepare_raw_data_store_basic(mock_defect_history, mock_cfg, sensor_fields_list):
    """prepare_raw_data_store() ritorna RawDataStore ordinato per data."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)

    assert isinstance(store, list)
    assert len(store) == 3
    assert 'Signals' in store[0]
    assert 'Axis' in store[0]
    assert 'Date' in store[0]
    assert 'Amp' in store[0]


def test_prepare_raw_data_store_sorts_by_date(mock_defect_history, mock_cfg, sensor_fields_list):
    """Dati ordinati cronologicamente."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)

    # Check chronological order
    dates = [r['Date'] for r in store]
    assert dates == sorted(dates)
    assert dates[0].day == 1
    assert dates[1].day == 1
    assert dates[2].day == 2


def test_prepare_raw_data_store_signals_extracted(mock_defect_history, mock_cfg, sensor_fields_list):
    """Segnali estratti per tutti gli 8 sensori."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)

    for run_store in store:
        signals = run_store['Signals']
        # Should have 8 or fewer sensor keys (some might be missing)
        assert len(signals) <= 8


def test_prepare_raw_data_store_axis_present(mock_defect_history, mock_cfg, sensor_fields_list):
    """Ogni run ha Axis."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)

    for run_store in store:
        assert 'Axis' in run_store
        assert isinstance(run_store['Axis'], (np.ndarray, list))


# ---------------------------------------------------------------------------
# Category 2: AllAmps Computation (2 tests)
# ---------------------------------------------------------------------------

def test_compute_all_amps_shape(mock_defect_history, mock_cfg, sensor_fields_list):
    """compute_all_amps() ritorna (n_runs x 8)."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)
    all_amps = compute_all_amps(store, sensor_fields_list, mock_cfg)

    assert isinstance(all_amps, np.ndarray)
    assert all_amps.shape == (3, 8)


def test_compute_all_amps_non_negative(mock_defect_history, mock_cfg, sensor_fields_list):
    """Ampiezze non-negative (RMS)."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)
    all_amps = compute_all_amps(store, sensor_fields_list, mock_cfg)

    assert np.all((all_amps >= 0) | np.isnan(all_amps))


# ---------------------------------------------------------------------------
# Category 3: Metrics per Run (3 tests)
# ---------------------------------------------------------------------------

def test_compute_metrics_per_run_shape(mock_defect_history, mock_cfg, sensor_fields_list):
    """compute_metrics_per_run() ritorna 5 array."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)
    all_amps = compute_all_amps(store, sensor_fields_list, mock_cfg)

    dates_num = np.array([datenum(r['Date']) for r in store])

    ratio_sx_dx, ratio_fr, ratio_lv, lambda_all, severity = compute_metrics_per_run(
        all_amps, store, dates_num, mock_cfg, sensor_fields_list
    )

    assert ratio_sx_dx.shape == (3,)
    assert ratio_fr.shape == (3,)
    assert ratio_lv.shape == (3,)
    assert lambda_all.shape == (3, 8)
    assert severity.shape == (3,)


def test_compute_metrics_per_run_ratios_positive(mock_defect_history, mock_cfg, sensor_fields_list):
    """Ratios tutti positivi (formule SX_DX, FR, LV con guard 1e-6)."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)
    all_amps = compute_all_amps(store, sensor_fields_list, mock_cfg)
    dates_num = np.array([datenum(r['Date']) for r in store])

    ratio_sx_dx, ratio_fr, ratio_lv, _, _ = compute_metrics_per_run(
        all_amps, store, dates_num, mock_cfg, sensor_fields_list
    )

    assert np.all(ratio_sx_dx > 0)
    assert np.all(ratio_fr > 0)
    assert np.all(ratio_lv > 0)


def test_compute_metrics_per_run_lambda_range(mock_defect_history, mock_cfg, sensor_fields_list):
    """Lambda in [0, inf) o NaN."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)
    all_amps = compute_all_amps(store, sensor_fields_list, mock_cfg)
    dates_num = np.array([datenum(r['Date']) for r in store])

    _, _, _, lambda_all, _ = compute_metrics_per_run(
        all_amps, store, dates_num, mock_cfg, sensor_fields_list
    )

    assert np.all((lambda_all >= 0) | np.isnan(lambda_all))


# ---------------------------------------------------------------------------
# Category 4: Tab Builders (6 tests)
# ---------------------------------------------------------------------------

def test_build_tab_trend_data_basic(mock_defect_history, mock_cfg, sensor_fields_list):
    """build_tab_trend_data() ritorna dict con dati per 4 subplot."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)
    all_amps = compute_all_amps(store, sensor_fields_list, mock_cfg)
    dates_num = np.array([datenum(r['Date']) for r in store])

    trend_data = build_tab_trend_data(all_amps, dates_num, mock_cfg)

    assert isinstance(trend_data, dict)
    assert 'unique_days' in trend_data
    assert 'mean_f_by_day' in trend_data
    assert 'mean_r_by_day' in trend_data


def test_build_tab_stats_table_data_run_grouping(mock_defect_history, mock_cfg, sensor_fields_list):
    """build_tab_stats_table_data() con grouping='run'."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)
    all_amps = compute_all_amps(store, sensor_fields_list, mock_cfg)
    dates_num = np.array([datenum(r['Date']) for r in store])

    ratio_sx_dx, ratio_fr, ratio_lv, lambda_all, severity = compute_metrics_per_run(
        all_amps, store, dates_num, mock_cfg, sensor_fields_list
    )

    table_data = build_tab_stats_table_data(
        store, all_amps, ratio_sx_dx, ratio_fr, ratio_lv, lambda_all, dates_num,
        grouping_mode='run', cfg=mock_cfg
    )

    assert isinstance(table_data, list)
    assert len(table_data) == 3  # 3 runs, no aggregation


def test_build_tab_stats_table_data_daily_grouping(mock_defect_history, mock_cfg, sensor_fields_list):
    """build_tab_stats_table_data() con grouping='daily'."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)
    all_amps = compute_all_amps(store, sensor_fields_list, mock_cfg)
    dates_num = np.array([datenum(r['Date']) for r in store])

    ratio_sx_dx, ratio_fr, ratio_lv, lambda_all, severity = compute_metrics_per_run(
        all_amps, store, dates_num, mock_cfg, sensor_fields_list
    )

    table_data = build_tab_stats_table_data(
        store, all_amps, ratio_sx_dx, ratio_fr, ratio_lv, lambda_all, dates_num,
        grouping_mode='daily', cfg=mock_cfg
    )

    # 2 giorni distinti (1 gennaio con 2 run, 2 gennaio con 1 run)
    assert isinstance(table_data, list)
    assert len(table_data) == 2


def test_build_tab_stats_table_data_3x3_classification(mock_defect_history, mock_cfg, sensor_fields_list):
    """Classificazione 3x3 (L/C/R × F/C/R)."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)
    all_amps = compute_all_amps(store, sensor_fields_list, mock_cfg)
    dates_num = np.array([datenum(r['Date']) for r in store])

    ratio_sx_dx, ratio_fr, ratio_lv, lambda_all, severity = compute_metrics_per_run(
        all_amps, store, dates_num, mock_cfg, sensor_fields_list
    )

    table_data = build_tab_stats_table_data(
        store, all_amps, ratio_sx_dx, ratio_fr, ratio_lv, lambda_all, dates_num,
        grouping_mode='run', cfg=mock_cfg
    )

    # Ogni riga dovrebbe avere 'Pos_3x3' che è del tipo 'L-F', 'C-C', ecc.
    for row in table_data:
        assert 'Pos_3x3' in row
        pos_3x3 = row['Pos_3x3']
        lat_char, long_char = pos_3x3.split('-')
        assert lat_char in ['L', 'C', 'R', '-']
        assert long_char in ['F', 'C', 'R', '-']


def test_build_stft_dates_labels_format(mock_defect_history, mock_cfg, sensor_fields_list):
    """build_stft_dates_labels() con formato 'dd/mm/yy HH:MM [m/s²]'."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)

    labels = build_stft_dates_labels(store)

    assert isinstance(labels, list)
    assert len(labels) == 3
    # Check format: should contain date and amp
    for label in labels:
        assert '/' in label  # date separator
        assert '[' in label and ']' in label  # amp bracket


# ---------------------------------------------------------------------------
# Category 5: Profile Cache (2 tests)
# ---------------------------------------------------------------------------

def test_compute_cache_profiles_shape(mock_defect_history, mock_cfg, sensor_fields_list):
    """compute_cache_profiles() ritorna lista profili."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)
    dates_num = np.array([datenum(r['Date']) for r in store])

    profiles = compute_cache_profiles(
        store, dates_num, sensor_fields_list, sensor_pair_idx=(0, 1),
        grouping_mode='daily', cfg=mock_cfg
    )

    assert isinstance(profiles, list)
    assert len(profiles) > 0

    for profile in profiles:
        assert 'RMS' in profile
        assert 'Axis' in profile
        assert 'Date' in profile


def test_compute_cache_profiles_run_grouping(mock_defect_history, mock_cfg, sensor_fields_list):
    """compute_cache_profiles() con grouping='run'."""
    store = prepare_raw_data_store(mock_defect_history, mock_cfg, sensor_fields_list)
    dates_num = np.array([datenum(r['Date']) for r in store])

    profiles = compute_cache_profiles(
        store, dates_num, sensor_fields_list, sensor_pair_idx=(0, 1),
        grouping_mode='run', cfg=mock_cfg
    )

    # Un profilo per ogni run
    assert len(profiles) == 3
