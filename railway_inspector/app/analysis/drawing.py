"""Rendering helpers for axes overlays and signature grid (port of app.m:1846-4101)."""
from __future__ import annotations

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon

__all__ = [
    "helper_fft_shift",
    "draw_infra_overlay",
    "draw_joints_overlay",
    "draw_signature_grid",
]


def helper_fft_shift(sig: np.ndarray, shift_m: float, spatial_res: float) -> np.ndarray:
    """Spatial frequency shift via FFT (app.m:1846-1865)."""
    sig_1d_input = sig.ndim == 1

    N = sig.size
    if N <= 1:
        return sig.copy()

    # Vettore colonna per sicurezza (MATLAB: sig_work = double(sig(:)))
    sig_work = np.asarray(sig, dtype=np.float64).ravel()

    shift_samples = shift_m / spatial_res

    X = np.fft.fft(sig_work)

    # k = (0:N-1)', poi k(k > floor(N/2)) -= N
    k = np.arange(N, dtype=np.float64)
    k[k > np.floor(N / 2)] -= N

    phase_shift = np.exp(-1j * 2 * np.pi * k * shift_samples / N)
    shifted = np.real(np.fft.ifft(X * phase_shift))

    # MATLAB: se input era riga → output riga (trasposta del vettore colonna)
    # In Python tutto è 1-D; manteniamo lo stesso shape dell'input.
    if sig_1d_input:
        return shifted  # già 1-D, equivalente al vettore colonna/riga MATLAB

    # Input era 2-D (es. shape (1, N) o (N, 1)): ripristina shape originale
    return shifted.reshape(sig.shape)


def draw_infra_overlay(
    ax: plt.Axes,
    infra_table: pd.DataFrame,
    x_limits: tuple[float, float],
) -> None:
    """Add infrastructure overlay (Deviatoio/other) as colored patches to axes (app.m:1869-1882)."""
    if infra_table is None or infra_table.empty:
        return

    # Filtra elementi visibili: Pk_Inizio <= x_limits[1] AND Pk_Fine >= x_limits[0]
    vis_idx = (
        (infra_table["Pk_Inizio"] <= x_limits[1])
        & (infra_table["Pk_Fine"] >= x_limits[0])
    )
    visible_items = infra_table.loc[vis_idx]
    if visible_items.empty:
        return

    y_lims = ax.get_ylim()

    for _, row in visible_items.iterrows():
        x_start = row["Pk_Inizio"]
        x_end = row["Pk_Fine"]

        if str(row["Tipo"]).strip().lower() == "deviatoio":
            col = (1.0, 0.7, 0.7)
            txt_col = (0.8, 0.0, 0.0)
        else:
            col = (0.7, 1.0, 0.7)
            txt_col = (0.0, 0.5, 0.0)

        # MATLAB patch: [x_start x_end x_end x_start], [y1 y1 y2 y2]
        xs = [x_start, x_end, x_end, x_start]
        ys = [y_lims[0], y_lims[0], y_lims[1], y_lims[1]]
        patch = Polygon(
            list(zip(xs, ys)),
            closed=True,
            facecolor=col,
            edgecolor="none",
            alpha=0.3,
        )
        ax.add_patch(patch)

        # Testo solo se larghezza > 2% del range visibile
        if (x_end - x_start) > (x_limits[1] - x_limits[0]) * 0.02:
            lbl = str(row["Descrizione"])
            if len(lbl) > 15:
                lbl = lbl[:14] + ".."
            ax.text(
                x_start,
                y_lims[1],
                lbl,
                color=txt_col,
                verticalalignment="top",
                fontsize=7,
            )


def draw_joints_overlay(
    ax: plt.Axes,
    joints_table: pd.DataFrame,
    x_limits: tuple[float, float],  # noqa: ARG001 — presente per simmetria API; MATLAB non filtra
) -> None:
    """Add joints overlay (magenta vlines + labels) to axes (app.m:1917-1937)."""
    if joints_table is None or joints_table.empty:
        return

    # MATLAB: colonna 2 = posizioni, colonna 3 = nomi (indice 1-based → iloc[:,1] e iloc[:,2])
    posizioni = joints_table.iloc[:, 1].to_numpy(dtype=float)
    nomi = joints_table.iloc[:, 2].astype(str).to_numpy()

    y_lims = ax.get_ylim()

    # MATLAB disegna TUTTI i giunti (nessun filtro su x_limits)
    for i in range(len(posizioni)):
        pos = posizioni[i]
        if np.isnan(pos):
            continue
        nome_giunto = nomi[i]

        # xline(ax, pos, 'm-', 'LineWidth', 1.5, 'HandleVisibility', 'off')
        ax.axvline(x=pos, color="m", linewidth=1.5)

        # text: y = y_lims(1) + (y_lims(2)-y_lims(1))*0.05
        y_txt = y_lims[0] + (y_lims[1] - y_lims[0]) * 0.05
        ax.text(
            pos,
            y_txt,
            nome_giunto,
            color="m",
            rotation=90,
            fontsize=8,
            fontweight="bold",
        )


def draw_signature_grid(
    M: object,
    orig_row: np.ndarray,
    recon_row: np.ndarray,
    title_str: str,
) -> plt.Figure:
    """Create n_chan-subplot figure (orig vs recon) for PCA signature (app.m:3290-3315)."""
    N_GRID: int = int(M.N_GRID)           # type: ignore[attr-defined]
    xg: np.ndarray = np.asarray(M.x_grid, dtype=np.float64).ravel()  # type: ignore[attr-defined]
    n_chan: int = int(M.n_chan)            # type: ignore[attr-defined]
    ch_labels: list[str] = list(M.ch_labels)  # type: ignore[attr-defined]

    # Layout: 2 righe × ceil(n_chan/2) colonne (generalizzato; MATLAB usava ax_pca_sig handle array)
    # NB: ravel() usa row-major (C-order); MATLAB potrebbe usare column-major per il suo array di handle.
    # Se la sequenza assi diverge, ripristinare order='F' in ravel().
    n_cols = max(1, (n_chan + 1) // 2)
    n_rows = 2 if n_chan > 1 else 1
    fig, axes = plt.subplots(n_rows, n_cols, figsize=(n_cols * 3, n_rows * 2.5), squeeze=False)
    axes_flat = axes.ravel()

    for c in range(n_chan):
        ax = axes_flat[c]
        ax.cla()

        # MATLAB cols = (c-1)*N + 1 : c*N  (1-based) → Python: c*N_GRID : (c+1)*N_GRID
        cols = slice(c * N_GRID, (c + 1) * N_GRID)

        ax.plot(xg, orig_row[cols],  "b-",  linewidth=1.0)
        ax.plot(xg, recon_row[cols], "r--", linewidth=1.0)

        ax.set_title(ch_labels[c], fontweight="normal", fontsize=9)
        ax.grid(True)
        ax.tick_params(labelsize=8)
        ax.set_xlim(xg[0], xg[-1])

        # MATLAB: c >= 4 → xlabel (canali in riga inferiore)
        if c >= 3:  # 0-based: canali 3..n_chan-1 sono in riga inferiore
            ax.set_xlabel("Posizione [m]", fontsize=8)

        # MATLAB: c == 1 || c == 4 → ylabel (colonna sinistra)
        if c == 0 or c == 3:  # 0-based
            ax.set_ylabel("Inviluppo RMS [m/s^2]", fontsize=8)

    # Nascondi axes inutilizzati se n_chan < n_rows*n_cols
    for c in range(n_chan, len(axes_flat)):
        axes_flat[c].set_visible(False)

    fig.suptitle(
        f"{title_str}     blu: originale  ·  rosso tratteggiato: ricostruito",
        fontsize=9,
    )
    fig.tight_layout()
    return fig
