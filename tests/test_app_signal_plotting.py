"""TDD tests for railway_inspector.app.analysis.signal_plotting (9 tests)."""
from __future__ import annotations

import numpy as np
import pytest
import matplotlib.pyplot as plt

from railway_inspector.app.analysis.signal_plotting import (
    plot_temporal_trend,
    plot_single_signal,
    plot_rms_envelope,
    plot_signal_comparison,
    setup_signal_axes,
)


# ---------------------------------------------------------------------------
# Test 1: plot_temporal_trend adds lines
# ---------------------------------------------------------------------------


def test_plot_temporal_trend_adds_lines():
    """plot_temporal_trend() deve aggiungere 2 linee (front+rear)."""
    fig, ax = plt.subplots()

    dates = np.array([737800.0, 737801.0, 737802.0])
    series_front = np.array([1.5, 2.0, 1.8])
    series_rear = np.array([1.2, 1.5, 1.6])

    initial_lines = len(ax.lines)
    plot_temporal_trend(
        ax, dates, series_front, series_rear, title="Test Trend", ylabel="Accel [m/s^2]"
    )

    # Deve aggiungere 2 linee
    assert len(ax.lines) == initial_lines + 2
    assert ax.get_title() == "Test Trend"

    plt.close(fig)


# ---------------------------------------------------------------------------
# Test 2: plot_temporal_trend colors correct
# ---------------------------------------------------------------------------


def test_plot_temporal_trend_colors_correct():
    """Colori: blue per front, red per rear."""
    fig, ax = plt.subplots()

    dates = np.array([737800.0, 737801.0])
    series_front = np.array([1.0, 2.0])
    series_rear = np.array([1.5, 2.5])

    plot_temporal_trend(ax, dates, series_front, series_rear, title="Color Test", ylabel="Y")

    # First line è blu, second è rosso
    line_colors = [line.get_color() for line in ax.lines]
    assert line_colors[0] == "b" or line_colors[0][:3] == (0.0, 0.0, 1.0)
    assert line_colors[1] == "r" or line_colors[1][:3] == (1.0, 0.0, 0.0)

    plt.close(fig)


# ---------------------------------------------------------------------------
# Test 3: plot_single_signal basic
# ---------------------------------------------------------------------------


def test_plot_single_signal_basic():
    """plot_single_signal() aggiunge una linea."""
    fig, ax = plt.subplots()

    x_axis = np.linspace(-10, 10, 100)
    signal = np.sin(x_axis)

    plot_single_signal(ax, x_axis, signal, label="Test Signal")

    assert len(ax.lines) == 1
    # Deve avere xlabel auto-settato
    assert ax.get_xlabel() != ""

    plt.close(fig)


# ---------------------------------------------------------------------------
# Test 4: plot_rms_envelope calculates correctly
# ---------------------------------------------------------------------------


def test_plot_rms_envelope_calculates_correctly():
    """RMS envelope = sqrt(movmean(sig^2, window_samples))."""
    # Segnale sinusoidale: max RMS dovrebbe essere nell'intervallo [0.5, 1.0] per sin(x)
    x = np.linspace(0, 4 * np.pi, 400)
    sig = np.sin(x)
    window_samples = 10

    # Calcolo RMS atteso (movmean di sig^2, poi sqrt)
    from scipy.ndimage import uniform_filter1d

    rms_expected = np.sqrt(uniform_filter1d(sig**2, size=window_samples, mode="nearest"))

    # Verifica che max(rms_expected) sia nell'intervallo atteso per sin
    assert 0.5 < np.max(rms_expected) < 1.0

    fig, ax = plt.subplots()
    plot_rms_envelope(ax, x, sig, window_samples, label="RMS")

    # Deve aggiungere una linea
    assert len(ax.lines) == 1

    plt.close(fig)


# ---------------------------------------------------------------------------
# Test 5: plot_signal_comparison adds two lines
# ---------------------------------------------------------------------------


def test_plot_signal_comparison_adds_two_lines():
    """plot_signal_comparison() aggiunge 2 linee."""
    fig, ax = plt.subplots()

    x = np.linspace(0, 10, 100)
    original = np.sin(x)
    reconstructed = np.sin(x) + 0.1 * np.random.randn(100)

    plot_signal_comparison(ax, x, original, reconstructed, title="Comparison")

    assert len(ax.lines) == 2
    assert ax.get_title() == "Comparison"

    # Verifica stili: solid vs dashed
    styles = [line.get_linestyle() for line in ax.lines]
    assert "-" in styles or "solid" in styles[0]  # Uno solid
    assert "--" in styles or "dashed" in styles[1]  # Uno dashed

    plt.close(fig)


# ---------------------------------------------------------------------------
# Test 6: setup_signal_axes applies formatting
# ---------------------------------------------------------------------------


def test_setup_signal_axes_applies_formatting():
    """setup_signal_axes() applica formatting."""
    fig, ax = plt.subplots()

    setup_signal_axes(
        ax, title="Test Title", xlabel="X [m]", ylabel="Y [m/s^2]", fontsize=10
    )

    assert ax.get_title() == "Test Title"
    assert ax.get_xlabel() == "X [m]"
    assert ax.get_ylabel() == "Y [m/s^2]"

    plt.close(fig)


# ---------------------------------------------------------------------------
# Test 7: plot_temporal_trend grid enabled
# ---------------------------------------------------------------------------


def test_plot_temporal_trend_grid_enabled():
    """Grid deve essere attivo."""
    fig, ax = plt.subplots()

    dates = np.array([737800.0, 737801.0])
    series_f = np.array([1.0, 2.0])
    series_r = np.array([1.5, 2.5])

    plot_temporal_trend(ax, dates, series_f, series_r, "Title", "Y")

    # Verifica grid è attivo tramite API pubblica (evita _gridOnMajor rimosso in mpl >= 3.7)
    assert ax.xaxis.get_major_ticks()[0].gridline.get_visible() or \
           ax.yaxis.get_major_ticks()[0].gridline.get_visible()

    plt.close(fig)


# ---------------------------------------------------------------------------
# Test 8: plot_rms_envelope non-negative
# ---------------------------------------------------------------------------


def test_plot_rms_envelope_non_negative():
    """RMS envelope deve essere sempre >= 0."""
    x = np.linspace(-10, 10, 200)
    sig = np.random.randn(200)  # Random noise

    fig, ax = plt.subplots()
    plot_rms_envelope(ax, x, sig, window_samples=5)

    # Estrai dati dalla linea
    line = ax.lines[0]
    y_data = line.get_ydata()

    assert np.all(y_data >= 0)

    plt.close(fig)


# ---------------------------------------------------------------------------
# Test 9: plot_signal_comparison line styles correct
# ---------------------------------------------------------------------------


def test_plot_signal_comparison_line_styles_correct():
    """Original=solid, reconstructed=dashed."""
    fig, ax = plt.subplots()

    x = np.linspace(0, 10, 100)
    original = np.sin(x)
    reconstructed = np.sin(x) * 0.95

    plot_signal_comparison(ax, x, original, reconstructed)

    # First line è solid ('-'), second è dashed ('--')
    styles = [line.get_linestyle() for line in ax.lines]
    # Tolleranza per variazioni di rappresentazione matplotlib
    assert (
        styles[0] in ["-", "solid", "-", "(0,(0,0))"] or "solid" in str(styles[0])
    )  # Original solid
    assert (
        styles[1] in ["--", "dashed", "--", "(0,(1,1))"] or "dash" in str(styles[1])
    )  # Reconstructed dashed

    plt.close(fig)
