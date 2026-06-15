"""TDD tests for railway_inspector.app.analysis.drawing (5 test)."""
from __future__ import annotations

import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")  # headless – no display required
import matplotlib.pyplot as plt
import pytest

from railway_inspector.app.analysis.drawing import (
    draw_infra_overlay,
    draw_joints_overlay,
    draw_signature_grid,
    helper_fft_shift,
)


# ---------------------------------------------------------------------------
# Test 1: draw_infra_overlay aggiunge elementi all'axes
# ---------------------------------------------------------------------------
def test_draw_infra_overlay_adds_lines():
    """draw_infra_overlay() deve aggiungere patch all'axes."""
    fig, ax = plt.subplots()

    infra_table = pd.DataFrame({
        "Pk_Inizio":   [0.5,  5.2, 10.8],
        "Pk_Fine":     [1.5,  6.0, 11.5],
        "Tipo":        ["Deviatoio", "Altro", "Deviatoio"],
        "Descrizione": ["XC-01", "J-01", "AN-01"],
    })

    # Axes inizialmente vuoto
    assert len(ax.patches) == 0

    draw_infra_overlay(ax, infra_table, x_limits=(0.0, 15.0))

    # Almeno un patch deve essere stato aggiunto
    assert len(ax.patches) > 0

    plt.close(fig)


# ---------------------------------------------------------------------------
# Test 2: draw_joints_overlay aggiunge linee verticali
# ---------------------------------------------------------------------------
def test_draw_joints_overlay_adds_lines():
    """draw_joints_overlay() deve aggiungere vlines per giunti."""
    fig, ax = plt.subplots()

    # col 0 = indice, col 1 = posizione, col 2 = nome  (MATLAB: colonne 2 e 3, 1-based)
    joints_table = pd.DataFrame({
        "idx":  [1, 2, 3],
        "coord": [2.0, 8.5, 14.3],
        "name":  ["Joint-01", "Joint-02", "Joint-03"],
    })

    initial_lines = len(ax.lines)
    draw_joints_overlay(ax, joints_table, x_limits=(0.0, 20.0))

    # Una axvline per giunto → almeno 3 linee aggiunte
    assert len(ax.lines) >= initial_lines + 3

    plt.close(fig)


# ---------------------------------------------------------------------------
# Test 3: draw_signature_grid crea figura con subplot corretti
# ---------------------------------------------------------------------------
def test_draw_signature_grid_shape():
    """draw_signature_grid() crea una figura con almeno n_chan subplot."""

    class FakeM:
        N_GRID = 100
        n_chan = 6
        x_grid = np.linspace(-1.5, 1.5, 100)
        ch_labels = [f"CH{i+1}" for i in range(6)]

    n_chan = FakeM.n_chan
    N_GRID = FakeM.N_GRID

    orig_row  = np.random.randn(n_chan * N_GRID)
    recon_row = np.random.randn(n_chan * N_GRID)

    fig = draw_signature_grid(FakeM(), orig_row, recon_row, title_str="Test Grid")

    assert fig is not None
    # Deve esserci almeno n_chan axes visibili
    visible_axes = [a for a in fig.axes if a.get_visible()]
    assert len(visible_axes) >= n_chan

    plt.close(fig)


# ---------------------------------------------------------------------------
# Test 4: helper_fft_shift preserva lunghezza e dtype
# ---------------------------------------------------------------------------
def test_helper_fft_shift_preserves_length():
    """helper_fft_shift() preserva lunghezza del segnale e restituisce float."""
    rng = np.random.default_rng(42)
    sig = rng.standard_normal(1000)
    shift_m = 5.0
    spatial_res = 0.030

    shifted = helper_fft_shift(sig, shift_m, spatial_res)

    assert len(shifted) == len(sig)
    assert shifted.dtype in (np.float32, np.float64)


def test_helper_fft_shift_zero_shift_is_identity():
    """helper_fft_shift() con shift=0 deve restituire il segnale originale."""
    rng = np.random.default_rng(7)
    sig = rng.standard_normal(512)
    shifted = helper_fft_shift(sig, shift_m=0.0, spatial_res=0.025)
    np.testing.assert_allclose(shifted, sig, atol=1e-10)


# ---------------------------------------------------------------------------
# Test 5: draw_infra_overlay con database reale (integration)
# ---------------------------------------------------------------------------
DB_PATH = r"Data/Database_damage_38-Garibaldi F.S. to Gioia.mat"


@pytest.mark.skipif(
    not __import__("os").path.isfile(DB_PATH),
    reason="Database reale non disponibile in questo ambiente",
)
def test_draw_infra_overlay_with_real_db():
    """draw_infra_overlay() non crasha con infra_table da database reale (simulato)."""
    from scipy.io import loadmat  # noqa: PLC0415

    db = loadmat(DB_PATH, squeeze_me=False)
    # Verifica che il file sia caricabile e contenga MASTER_DB
    assert "MASTER_DB" in db

    # Costruiamo infra_table simulata (struttura MATLAB variabile per versione)
    infra_table = pd.DataFrame({
        "Pk_Inizio":   [1.0,  5.0, 10.0],
        "Pk_Fine":     [2.0,  6.0, 11.0],
        "Tipo":        ["Deviatoio", "Altro", "Deviatoio"],
        "Descrizione": ["XC-01", "J-01", "AN-01"],
    })

    fig, ax = plt.subplots()
    draw_infra_overlay(ax, infra_table, x_limits=(0.0, 15.0))

    # Non deve crashare e deve aver aggiunto patch
    assert len(ax.patches) > 0
    plt.close(fig)
