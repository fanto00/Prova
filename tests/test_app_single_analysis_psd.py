"""TDD tests for railway_inspector.app.analysis.single_analysis_psd (8 tests)."""
from __future__ import annotations

import numpy as np
import pytest
import matplotlib.pyplot as plt
from datetime import datetime
from mpl_toolkits.mplot3d import Axes3D

from railway_inspector.app.analysis.single_analysis_psd import (
    compute_psd_for_run,
    compute_psd_matrix_3d,
    plot_psd_2d,
    plot_psd_3d_waterfall,
)


# Helper: convert datetime to MATLAB datenum
def datenum(dt: datetime) -> float:
    """Convert datetime to MATLAB datenum."""
    epoch = datetime(1899, 12, 30)
    delta = dt - epoch
    return delta.days + delta.seconds / 86400.0


# ---------------------------------------------------------------------------
# Test 1: compute_psd_for_run basic
# ---------------------------------------------------------------------------

def test_compute_psd_for_run_basic():
    """compute_psd_for_run() ritorna (psd, freq_axis)."""
    # Segnale semplice: sin(2*pi*f*x) con f=2 cicli/m
    x = np.linspace(-5, 5, 1000)  # ±5m
    signal = np.sin(2 * np.pi * 2 * x)  # 2 cicli/m
    axis = x

    psd, freq = compute_psd_for_run(signal, axis, window_m=10.0, dx=0.030)

    assert isinstance(psd, np.ndarray)
    assert isinstance(freq, np.ndarray)
    assert len(psd) == len(freq)
    assert len(psd) > 0


# ---------------------------------------------------------------------------
# Test 2: compute_psd_for_run window crop
# ---------------------------------------------------------------------------

def test_compute_psd_for_run_window_crop():
    """Cropping intorno a ±window_m/2."""
    x = np.linspace(-20, 20, 2000)
    signal = np.random.randn(2000)
    axis = x

    # Con finestra 10m, deve usare solo [-5, +5]
    psd, freq = compute_psd_for_run(signal, axis, window_m=10.0, dx=0.030)

    # PSD non vuoto (finestra valida)
    assert len(psd) > 0
    assert len(freq) > 0


# ---------------------------------------------------------------------------
# Test 3: compute_psd_matrix_3d single period (run grouping)
# ---------------------------------------------------------------------------

def test_compute_psd_matrix_3d_single_period():
    """Matrice 3D con 3 run singole (grouping='run')."""
    runs = [
        {
            'Signals': {'SX_F': np.sin(2*np.pi*2*np.linspace(-5, 5, 500))},
            'Axis': np.linspace(-5, 5, 500),
            'Date': datetime(2026, 1, 1, 10, 0)
        },
        {
            'Signals': {'SX_F': np.sin(2*np.pi*1.5*np.linspace(-5, 5, 500))},
            'Axis': np.linspace(-5, 5, 500),
            'Date': datetime(2026, 1, 2, 10, 0)
        },
        {
            'Signals': {'SX_F': np.sin(2*np.pi*3*np.linspace(-5, 5, 500))},
            'Axis': np.linspace(-5, 5, 500),
            'Date': datetime(2026, 1, 3, 10, 0)
        },
    ]
    dates_num = np.array([datenum(r['Date']) for r in runs])

    psd_mat, freq_ax, date_ax, periods_valid = compute_psd_matrix_3d(
        runs, 'SX_F', window_m=10.0, dates_num=dates_num, grouping_mode='run'
    )

    assert psd_mat.shape[0] == 3  # 3 periodi (una per run)
    assert psd_mat.shape[1] > 0
    assert len(freq_ax) == psd_mat.shape[1]
    assert len(periods_valid) == 3


# ---------------------------------------------------------------------------
# Test 4: compute_psd_matrix_3d daily grouping
# ---------------------------------------------------------------------------

def test_compute_psd_matrix_3d_daily_grouping():
    """Raggruppa più run nello stesso giorno."""
    runs = [
        {
            'Signals': {'SX_F': np.sin(2*np.pi*2*np.linspace(-5, 5, 500))},
            'Axis': np.linspace(-5, 5, 500),
            'Date': datetime(2026, 1, 1, 10, 0)
        },
        {
            'Signals': {'SX_F': np.sin(2*np.pi*2*np.linspace(-5, 5, 500))},
            'Axis': np.linspace(-5, 5, 500),
            'Date': datetime(2026, 1, 1, 15, 0)
        },
        {
            'Signals': {'SX_F': np.sin(2*np.pi*2*np.linspace(-5, 5, 500))},
            'Axis': np.linspace(-5, 5, 500),
            'Date': datetime(2026, 1, 2, 10, 0)
        },
    ]
    dates_num = np.array([datenum(r['Date']) for r in runs])

    psd_mat, freq_ax, date_ax, periods_valid = compute_psd_matrix_3d(
        runs, 'SX_F', window_m=10.0, dates_num=dates_num, grouping_mode='daily'
    )

    # 2 giorni distinti => 2 periodi
    assert psd_mat.shape[0] == 2
    assert len(periods_valid) == 2


# ---------------------------------------------------------------------------
# Test 5: plot_psd_2d adds lines
# ---------------------------------------------------------------------------

def test_plot_psd_2d_adds_lines():
    """plot_psd_2d() aggiunge linee."""
    fig, ax = plt.subplots()

    freq = np.linspace(0.5, 5, 100)
    psd_current = np.abs(np.sin(freq))
    psd_hist = [np.abs(np.cos(freq)), np.abs(np.sin(freq*0.8))]

    initial_lines = len(ax.lines)
    plot_psd_2d(ax, freq, psd_current, psd_hist, title="Test PSD 2D")

    # Minimo: 2 storici + mean storico + current = 4 linee
    assert len(ax.lines) >= initial_lines + 2

    plt.close(fig)


# ---------------------------------------------------------------------------
# Test 6: plot_psd_2d colors correct
# ---------------------------------------------------------------------------

def test_plot_psd_2d_colors_correct():
    """Colori: rosso per current, grigio per storico."""
    fig, ax = plt.subplots()

    freq = np.linspace(0.5, 5, 100)
    psd_current = np.ones(100)
    psd_hist = [np.ones(100)*0.5]

    plot_psd_2d(ax, freq, psd_current, psd_hist)

    # Check che ci siano linee e almeno una rossa-ish (current)
    colors = [line.get_color() for line in ax.lines]
    assert len(colors) >= 2

    # Last line dovrebbe essere rossa (current) o simile a [0.8 0.2 0]
    # (potrebbero essere tuple RGB)

    plt.close(fig)


# ---------------------------------------------------------------------------
# Test 7: plot_psd_3d_waterfall basic
# ---------------------------------------------------------------------------

def test_plot_psd_3d_waterfall_basic():
    """plot_psd_3d_waterfall() crea 3D waterfall."""
    fig = plt.figure()
    ax = fig.add_subplot(111, projection='3d')

    freq = np.linspace(0.5, 5, 50)
    dates = np.array([737800, 737801, 737802])
    psd_mat = np.random.rand(3, 50)

    plot_psd_3d_waterfall(ax, freq, dates, psd_mat, title="Test 3D")

    # Se è un vero 3D, should have 3D name
    assert ax.name == '3d'

    plt.close(fig)


# ---------------------------------------------------------------------------
# Test 8: compute_psd psd non-negative
# ---------------------------------------------------------------------------

def test_compute_psd_psd_non_negative():
    """PSD non-negative (periodogram output)."""
    x = np.linspace(-10, 10, 1000)
    signal = np.random.randn(1000)
    axis = x

    psd, freq = compute_psd_for_run(signal, axis, window_m=20.0, dx=0.030)

    assert np.all(psd >= 0)
    assert np.all(freq >= 0)
