"""Generate 7+ headless PNG figures for defect analysis (port of app.m:8577-8976)."""
from __future__ import annotations

import datetime
from pathlib import Path
from typing import Any, Dict

import matplotlib
matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import numpy as np
from scipy.signal import periodogram
from sklearn.decomposition import PCA

from railway_inspector.app.utils.helpers import sort_runs_by_direction
from railway_inspector.detection.trigger import movmean
from railway_inspector.signal.resampling import interp1_nan


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _datenum_from_str(date_str: str) -> float:
    """Convert ISO date string to MATLAB-compatible datenum (days since 0-Jan-0000).

    MATLAB datenum('2026-01-01') = 738887.  Python ordinal + 366 replicates it.
    datetime.date.toordinal() counts from 1-Jan-0001 = 1, MATLAB from 0-Jan-0000 = 1
    so offset is exactly 366.
    """
    d = datetime.date.fromisoformat(str(date_str).split("T")[0].split(" ")[0])
    return float(d.toordinal() + 366)


def _datenum_to_matplotlib(dn: float) -> float:
    """Convert MATLAB datenum to matplotlib date number."""
    # matplotlib epoch is 0001-01-01 (ordinal 1) = mdates day 1 (with epoch 0001-01-01)
    # MATLAB datenum: days since 0-Jan-0000; ordinal = dn - 366
    ordinal = dn - 366
    # matplotlib uses proleptic Gregorian calendar days since 0001-01-01
    # mdates.date2num(datetime(1,1,1)) == 1.0  (matplotlib >= 3.3 epoch)
    return mdates.date2num(datetime.date.fromordinal(int(ordinal)))


def _lines4_colors() -> np.ndarray:
    """Return 4 colors matching MATLAB lines(4)."""
    prop_cycle = plt.rcParams["axes.prop_cycle"]
    cols = [c["color"] for c in prop_cycle]
    out = []
    for c in cols[:4]:
        if isinstance(c, str) and c.startswith("#"):
            r = int(c[1:3], 16) / 255
            g = int(c[3:5], 16) / 255
            b = int(c[5:7], 16) / 255
            out.append([r, g, b])
        else:
            out.append(list(matplotlib.colors.to_rgb(c)))
    while len(out) < 4:
        out.append([0.0, 0.0, 0.0])
    return np.array(out[:4])


# ---------------------------------------------------------------------------
# Main function
# ---------------------------------------------------------------------------

def generate_headless_daily_plots(
    defect: Dict[str, Any],
    config: Dict[str, Any],
    export_dir: Path,
    rank_idx: int,
) -> bool:
    """Generate 7+ headless PNG figures for defect analysis."""
    History: list = defect.get("History", [])
    n_runs: int = len(History)
    if n_runs == 0:
        return False

    export_dir = Path(export_dir)

    SPATIAL_RES: float = float(config["SPATIAL_RES"])
    WINDOW_SIZE: float = float(config["WINDOW_SIZE"])
    IPI_PCA_MIN_RUNS: int = int(config["IPI_PCA_MIN_RUNS"])

    win_samples_base: int = max(3, round(0.5 / SPATIAL_RES))
    NFFT_val: int = max(4, round(10.0 / SPATIAL_RES))
    fs_space: float = 1.0 / SPATIAL_RES

    sens_list: list[str] = [
        "left_sensor_front",
        "left_sensor_rear",
        "right_sensor_front",
        "right_sensor_rear",
        "right_sensor_front_lat",
        "right_sensor_rear_lat",
        "left_sensor_front_lat",
        "left_sensor_rear_lat",
    ]

    dates_num: np.ndarray = np.zeros(n_runs)
    AllAmps: np.ndarray = np.zeros((n_runs, 8))
    Lambda_All: np.ndarray = np.zeros((n_runs, 8))

    max_global_amp: float = 0.0
    max_run_idx: int = 0  # 0-based

    for i, run in enumerate(History):
        dates_num[i] = _datenum_from_str(run.get("Date", "2000-01-01"))
        filt_data = run.get("Data", {}).get("Filt", None)
        if filt_data is not None:
            for s in range(8):
                sn = sens_list[s]
                if sn in filt_data:
                    sig = np.asarray(filt_data[sn], dtype=float).reshape(-1)
                    if sig.size == 0:
                        continue
                    if sig.size >= win_samples_base:
                        rms_sig = np.sqrt(movmean(sig**2, win_samples_base))
                        AllAmps[i, s] = float(np.max(rms_sig))
                    else:
                        AllAmps[i, s] = float(np.max(np.abs(sig)))
                    if sig.size >= 4:
                        pxx, f = periodogram(sig, window="hamming", nfft=NFFT_val, fs=fs_space)
                        p_idx = int(np.argmax(pxx))
                        if f[p_idx] > 0.05:
                            Lambda_All[i, s] = 1.0 / f[p_idx]

        run_max_amp = float(np.max(AllAmps[i, 0:4]))
        if run_max_amp > max_global_amp:
            max_global_amp = run_max_amp
            max_run_idx = i

    # --- Ratio calculations (app.m:8621-8623) ---
    Ratio_SX_DX: np.ndarray = (AllAmps[:, 0] + AllAmps[:, 1]) / np.maximum(
        AllAmps[:, 2] + AllAmps[:, 3], 1e-6
    )
    Ratio_FR: np.ndarray = (AllAmps[:, 0] + AllAmps[:, 2]) / np.maximum(
        AllAmps[:, 1] + AllAmps[:, 3], 1e-6
    )
    Ratio_LV: np.ndarray = np.max(AllAmps[:, 4:8], axis=1) / np.maximum(
        np.max(AllAmps[:, 0:4], axis=1), 1e-6
    )

    # --- Daily aggregation (app.m:8625-8637) ---
    days_floor: np.ndarray = np.floor(dates_num)
    unique_days: np.ndarray = np.unique(days_floor)
    n_days: int = len(unique_days)

    avg_Ratio_SX_DX: np.ndarray = np.zeros(n_days)
    avg_Ratio_FR: np.ndarray = np.zeros(n_days)
    avg_Ratio_LV: np.ndarray = np.zeros(n_days)
    avg_Lambda_All: np.ndarray = np.zeros((n_days, 8))

    for k in range(n_days):
        mask = days_floor == unique_days[k]
        avg_Ratio_SX_DX[k] = float(np.nanmean(Ratio_SX_DX[mask]))
        avg_Ratio_FR[k] = float(np.nanmean(Ratio_FR[mask]))
        avg_Ratio_LV[k] = float(np.nanmean(Ratio_LV[mask]))
        avg_Lambda_All[k, :] = np.nanmean(Lambda_All[mask, :], axis=0)

    # Convert unique_days (MATLAB datenum) to matplotlib dates for plotting
    unique_days_mpl: np.ndarray = np.array([_datenum_to_matplotlib(d) for d in unique_days])

    # =========================================================================
    # Figure 1: Firma Run Massima (app.m:8639-8676)
    # =========================================================================
    run_max = History[max_run_idx]

    rms_dx: float = 0.0
    rms_sx: float = 0.0
    filt_max = run_max.get("Data", {}).get("Filt", None)
    if filt_max is not None:
        sig_rdxf = filt_max.get("right_sensor_front_lat")
        if sig_rdxf is not None and len(sig_rdxf) > 0:
            s = np.asarray(sig_rdxf, dtype=float)
            rms_dx = float(np.sqrt(np.mean(s**2)))
        sig_lsxf = filt_max.get("left_sensor_front_lat")
        if sig_lsxf is not None and len(sig_lsxf) > 0:
            s = np.asarray(sig_lsxf, dtype=float)
            rms_sx = float(np.sqrt(np.mean(s**2)))

    if rms_sx > rms_dx:
        lat_f = "left_sensor_front_lat"
        lat_r = "left_sensor_rear_lat"
    else:
        lat_f = "right_sensor_front_lat"
        lat_r = "right_sensor_rear_lat"

    active_sig_fields: list[str] = [
        "left_sensor_front",
        "left_sensor_rear",
        "right_sensor_front",
        "right_sensor_rear",
        lat_f,
        lat_r,
    ]

    fig1 = plt.figure(figsize=(10, 7.5), facecolor="w")
    rel_axis_max = run_max.get("Data", {}).get("RelativeAxis", None)
    for s_idx in range(6):
        ax_s = fig1.add_subplot(3, 2, s_idx + 1)
        ax_s.grid(True)
        field = active_sig_fields[s_idx]
        filt_run = run_max.get("Data", {}).get("Filt", {})
        if filt_run and field in filt_run and rel_axis_max is not None:
            ax_s.plot(
                rel_axis_max,
                np.asarray(filt_run[field], dtype=float),
                color=(0, 0.4, 0.8),
            )
        ax_s.set_title(field.replace("_", " "))
        ax_s.set_xlabel("Posizione [m]", fontsize=8)
        ax_s.set_ylabel("Acc. [m/s$^2$]", fontsize=8)
    fig1.suptitle(
        f"Firma Run Massima ({max_global_amp:.1f} m/s²)",
        fontweight="bold",
    )
    fig1.tight_layout()
    fig1.savefig(
        export_dir / f"TOP{rank_idx:02d}_0_Max_Run_Signals.png",
        dpi=300,
        bbox_inches="tight",
    )
    plt.close(fig1)

    # =========================================================================
    # Figure 2: Matrice 3x3 (app.m:8678-8707)
    # =========================================================================
    fig2, ax2 = plt.subplots(figsize=(8, 6), facecolor="w")
    ax2.grid(True)

    sc2 = ax2.scatter(
        avg_Ratio_SX_DX,
        avg_Ratio_FR,
        s=60,
        c=unique_days_mpl,
        cmap="viridis",
        edgecolors="k",
    )
    ax2.axvline(x=2.0, color="r", linestyle="--")
    ax2.axvline(x=0.5, color="r", linestyle="--")
    ax2.axhline(y=2.0, color="b", linestyle="--")
    ax2.axhline(y=0.5, color="b", linestyle="--")
    ax2.set_xscale("log")
    ax2.set_yscale("log")

    cb2 = fig2.colorbar(sc2, ax=ax2)
    cb2.ax.yaxis.set_major_formatter(mdates.DateFormatter("%d/%m"))
    cb2.set_label("Evoluzione Temporale", fontweight="bold")

    if len(avg_Ratio_SX_DX) > 0:
        ax2.text(
            avg_Ratio_SX_DX[-1],
            avg_Ratio_FR[-1],
            "  ← ATTUALE",
            color="r",
            fontweight="bold",
            fontsize=9,
        )

    ax2.set_xlabel("Ratio Laterale (SX/DX)")
    ax2.set_ylabel("Ratio Longitudinale (Front/Rear)")
    ax2.set_title("Matrice 3x3 (Giornaliera)")
    fig2.savefig(
        export_dir / f"TOP{rank_idx:02d}_2_Giornaliera_C_Matrice3x3.png",
        dpi=300,
        bbox_inches="tight",
    )
    plt.close(fig2)

    # =========================================================================
    # Figure 3: Ratio Laterale (app.m:8710-8714)
    # =========================================================================
    fig3, ax3 = plt.subplots(figsize=(8, 4), facecolor="w")
    ax3.grid(True)
    ax3.plot(
        unique_days_mpl,
        avg_Ratio_LV,
        "-ok",
        markerfacecolor="y",
        linewidth=2,
    )
    ax3.axhline(y=0.6, color="r", linestyle="-", linewidth=2)
    ax3.xaxis.set_major_formatter(mdates.DateFormatter("%d/%m/%y"))
    fig3.autofmt_xdate()
    ax3.set_xlabel("Data")
    ax3.set_ylabel("Ratio Lat/Vert")
    ax3.set_title("Evoluzione Laterale")
    fig3.savefig(
        export_dir / f"TOP{rank_idx:02d}_2_Giornaliera_D_RatioLat.png",
        dpi=300,
        bbox_inches="tight",
    )
    plt.close(fig3)

    # =========================================================================
    # Figure 4: Lambda (app.m:8717-8729)
    # =========================================================================
    fig4, ax4 = plt.subplots(figsize=(8, 4), facecolor="w")
    ax4.grid(True)
    colors4 = _lines4_colors()
    sensor_names4 = ["SX Front", "SX Rear", "DX Front", "DX Rear"]
    for s in range(4):
        ax4.plot(
            unique_days_mpl,
            avg_Lambda_All[:, s],
            "-o",
            color=colors4[s],
            markerfacecolor=colors4[s],
            label=sensor_names4[s],
        )
    ax4.xaxis.set_major_formatter(mdates.DateFormatter("%d/%m/%y"))
    fig4.autofmt_xdate()
    ax4.set_xlabel("Data")
    ax4.set_ylabel("λ [m]")
    ax4.set_title("Evoluzione Lunghezza d'Onda (Verticali)")
    ax4.legend(loc="upper right", fontsize=7)
    fig4.savefig(
        export_dir / f"TOP{rank_idx:02d}_2_Giornaliera_E_Lambda.png",
        dpi=300,
        bbox_inches="tight",
    )
    plt.close(fig4)

    # =========================================================================
    # PCA block (app.m:8734-8976)
    # =========================================================================
    idx_fwd, idx_bwd = sort_runs_by_direction(History)
    use_fwd: bool = bool(np.sum(idx_fwd) >= np.sum(idx_bwd))

    if use_fwd:
        run_idx_pca: np.ndarray = np.where(idx_fwd)[0]
        dir_label: str = "Forward"
    else:
        run_idx_pca = np.where(idx_bwd)[0]
        dir_label = "Backward"

    if len(run_idx_pca) >= IPI_PCA_MIN_RUNS:
        N_GRID: int = 333
        n_chan: int = 6
        x_grid: np.ndarray = np.linspace(-WINDOW_SIZE, WINDOW_SIZE, N_GRID)
        win_samples_pca: int = max(3, round(0.5 / SPATIAL_RES))

        if use_fwd:
            chan_fields: list[str] = [
                "left_sensor_front",
                "right_sensor_front",
                "right_sensor_front_lat",
                "left_sensor_rear",
                "right_sensor_rear",
                "right_sensor_rear_lat",
            ]
        else:
            chan_fields = [
                "left_sensor_front",
                "right_sensor_front",
                "left_sensor_front_lat",
                "left_sensor_rear",
                "right_sensor_rear",
                "left_sensor_rear_lat",
            ]
        ch_labels: list[str] = ["V SX-F", "V DX-F", "Lat-F", "V SX-R", "V DX-R", "Lat-R"]

        n_pca: int = len(run_idx_pca)
        X_pca: np.ndarray = np.full((n_pca, n_chan * N_GRID), np.nan)
        dates_pca: np.ndarray = np.full(n_pca, np.nan)
        amps_pca: np.ndarray = np.full(n_pca, np.nan)
        valid_pca: np.ndarray = np.zeros(n_pca, dtype=bool)

        for pk in range(n_pca):
            r_i = History[run_idx_pca[pk]]
            data_i = r_i.get("Data", {})
            if "Filt" not in data_i or "RelativeAxis" not in data_i:
                continue
            ax_src = np.asarray(data_i["RelativeAxis"], dtype=float).reshape(-1)
            if not np.all(np.diff(ax_src) > 0) or not np.all(np.isfinite(ax_src)):
                continue
            Fd = data_i["Filt"]
            row_pca = np.full(n_chan * N_GRID, np.nan)
            row_ok: bool = True
            for c in range(n_chan):
                fn = chan_fields[c]
                if fn not in Fd or Fd[fn] is None or len(Fd[fn]) == 0:
                    row_ok = False
                    break
                sig = np.asarray(Fd[fn], dtype=float).reshape(-1)
                if sig.size != ax_src.size or sig.size < 10:
                    row_ok = False
                    break
                env = np.sqrt(movmean(sig**2, win_samples_pca))
                # interp1(ax_src, env, x_grid, 'linear', NaN)
                env_g = interp1_nan(ax_src, env, x_grid)
                if not np.all(np.isfinite(env_g)):
                    row_ok = False
                    break
                row_pca[c * N_GRID: (c + 1) * N_GRID] = env_g

            if row_ok:
                X_pca[pk, :] = row_pca
                dates_pca[pk] = _datenum_from_str(r_i.get("Date", "2000-01-01"))
                amps_pca[pk] = float(r_i.get("Amp", 0.0))
                valid_pca[pk] = True

        X_pca = X_pca[valid_pca, :]
        dates_pca = dates_pca[valid_pca]
        amps_pca = amps_pca[valid_pca]

        if X_pca.shape[0] >= IPI_PCA_MIN_RUNS:
            try:
                n_valid_pca: int = X_pca.shape[0]

                # Channel-space PCA: Xpar shape (n_valid_pca*N_GRID, n_chan)
                Nrows: int = n_valid_pca * N_GRID
                Xpar: np.ndarray = np.zeros((Nrows, n_chan))
                run_id: np.ndarray = np.zeros(Nrows, dtype=int)

                for r in range(n_valid_pca):
                    base = r * N_GRID
                    run_id[base: base + N_GRID] = r
                    for c in range(n_chan):
                        cols_slice = slice(c * N_GRID, (c + 1) * N_GRID)
                        Xpar[base: base + N_GRID, c] = X_pca[r, cols_slice]

                # Per-channel standardisation (app.m:8803-8806)
                mu_ch: np.ndarray = np.mean(Xpar, axis=0)
                sg_ch: np.ndarray = np.std(Xpar, ddof=1, axis=0)
                sg_ch[sg_ch < 1e-9] = 1.0
                Xpar_z: np.ndarray = (Xpar - mu_ch) / sg_ch

                # sklearn PCA (Economy=True equivalent: n_components=min(Nrows, n_chan))
                n_components: int = min(Nrows, n_chan)
                pca_model = PCA(n_components=n_components)
                scores_full: np.ndarray = pca_model.fit_transform(Xpar_z)
                coeffs: np.ndarray = pca_model.components_.T  # shape (n_chan, n_components)
                explained: np.ndarray = pca_model.explained_variance_ratio_ * 100.0
                mu_pca: np.ndarray = pca_model.mean_  # shape (n_chan,)

                # Chronological sort (app.m:8811-8813)
                ord_idx: np.ndarray = np.argsort(dates_pca, kind="stable")
                dates_pca = dates_pca[ord_idx]
                amps_pca = amps_pca[ord_idx]
                X_pca = X_pca[ord_idx, :]

                # Residual and RMSE (app.m:8816-8819)
                k_use: int = min(2, scores_full.shape[1])
                resid_z: np.ndarray = scores_full[:, k_use:] @ coeffs[:, k_use:].T
                se_row: np.ndarray = np.mean(resid_z**2, axis=1)

                # accumarray equivalent: mean of se_row per run
                rmse_run: np.ndarray = np.zeros(n_valid_pca)
                for ri in range(n_valid_pca):
                    mask_ri = run_id == ri
                    rmse_run[ri] = float(np.sqrt(np.mean(se_row[mask_ri])))
                rmse_vec: np.ndarray = rmse_run[ord_idx]

                # Per-run scores (mean over N_GRID rows) (app.m:8823-8828)
                P_comp: int = scores_full.shape[1]
                scores_run: np.ndarray = np.zeros((n_valid_pca, P_comp))
                for j in range(P_comp):
                    for ri in range(n_valid_pca):
                        mask_ri = run_id == ri
                        scores_run[ri, j] = float(np.mean(scores_full[mask_ri, j]))
                scores: np.ndarray = scores_run[ord_idx, :]

                # Reconstruction in original (unscaled) space (app.m:8831-8842)
                recon_chan: np.ndarray = (
                    scores_full[:, :k_use] @ coeffs[:, :k_use].T + mu_pca
                ) * sg_ch + mu_ch

                X_orig_un: np.ndarray = X_pca  # already sorted
                X_rec_un: np.ndarray = np.full((n_valid_pca, n_chan * N_GRID), np.nan)
                for r in range(n_valid_pca):
                    orig_r: int = int(ord_idx[r])
                    base = orig_r * N_GRID
                    for c in range(n_chan):
                        cols_slice = slice(c * N_GRID, (c + 1) * N_GRID)
                        X_rec_un[r, cols_slice] = recon_chan[base: base + N_GRID, c]

                # Convert dates_pca to matplotlib
                dates_pca_mpl: np.ndarray = np.array(
                    [_datenum_to_matplotlib(d) for d in dates_pca]
                )

                # =========================================================
                # Figure 5: PCA Anomaly Score (app.m:8846-8868)
                # =========================================================
                fig5, ax5 = plt.subplots(figsize=(10, 5), facecolor="w")
                ax5.grid(True)

                sc5 = ax5.scatter(
                    dates_pca_mpl,
                    rmse_vec,
                    s=35,
                    c=amps_pca,
                    cmap="viridis",
                    edgecolors="k",
                )

                t_norm: np.ndarray = dates_pca_mpl - dates_pca_mpl[0]
                p_fit: np.ndarray = np.polyfit(t_norm, rmse_vec, 1)
                (h_trend,) = ax5.plot(
                    dates_pca_mpl,
                    np.polyval(p_fit, t_norm),
                    "r-",
                    linewidth=2,
                    label="Trend lineare",
                )

                w_win: int = max(3, round(len(dates_pca_mpl) / 15))
                (h_mov,) = ax5.plot(
                    dates_pca_mpl,
                    movmean(rmse_vec, w_win),
                    "k-",
                    linewidth=1.5,
                    label=f"Media mobile w={w_win}",
                )

                mu_rmse = float(np.mean(rmse_vec))
                sd_rmse = float(np.std(rmse_vec, ddof=0))
                ax5.axhline(
                    y=mu_rmse + 2 * sd_rmse,
                    color="r",
                    linestyle="--",
                    linewidth=1.2,
                    label="μ + 2σ",
                )
                ax5.axhline(
                    y=mu_rmse,
                    color="k",
                    linestyle=":",
                    linewidth=1.0,
                    label="μ",
                )

                ax5.xaxis.set_major_formatter(mdates.DateFormatter("%d/%m/%y"))
                fig5.autofmt_xdate()
                ax5.set_title(
                    f"Anomaly Score (k={k_use}, trend={p_fit[0]:+.5f}/giorno) - {dir_label}"
                )
                ax5.set_xlabel("Data")
                ax5.set_ylabel("RMSE ricostruzione")

                cb5 = fig5.colorbar(sc5, ax=ax5)
                cb5.set_label("Max RMS 0.5m tra i sensori [m/s$^2$]")
                ax5.legend(handles=[h_trend, h_mov], loc="best")

                fig5.savefig(
                    export_dir / f"TOP{rank_idx:02d}_3_PCA_Anom.png",
                    dpi=300,
                    bbox_inches="tight",
                )
                plt.close(fig5)

                # =========================================================
                # Figure 6: Scree Plot (app.m:8871-8877)
                # =========================================================
                fig6, ax6 = plt.subplots(figsize=(7, 4), facecolor="w")
                ax6.grid(True)

                k_show: int = min(15, len(explained))
                ax6.bar(
                    np.arange(1, k_show + 1),
                    explained[:k_show],
                    color=(0.3, 0.5, 0.8),
                )
                ax6.plot(
                    np.arange(1, k_show + 1),
                    np.cumsum(explained[:k_show]),
                    "r-o",
                    linewidth=1.5,
                )
                ax6.axhline(y=95.0, color="k", linestyle="--", label="95%")
                ax6.axvline(
                    x=k_use,
                    color="r",
                    linestyle=":",
                    linewidth=1.5,
                    label=f"k={k_use}",
                )
                ax6.set_title("Scree Plot (Varianza)")
                ax6.set_xlabel("Componenti")
                ax6.set_ylabel("% Varianza")
                ax6.legend()

                fig6.savefig(
                    export_dir / f"TOP{rank_idx:02d}_3_PCA_Scree.png",
                    dpi=300,
                    bbox_inches="tight",
                )
                plt.close(fig6)

                # =========================================================
                # Figure 7: PC1/PC2 vs Time with weekly centroids (app.m:8882-8913)
                # =========================================================
                fig7, ax7 = plt.subplots(figsize=(10, 5), facecolor="w")
                ax7.grid(True)

                days_t: np.ndarray = dates_pca - dates_pca[0]
                WEEK_BIN: int = 7
                week_id: np.ndarray = np.floor(days_t / WEEK_BIN).astype(int)
                uw: np.ndarray = np.unique(week_id)
                n_weeks: int = len(uw)

                cent_pc1: np.ndarray = np.zeros(n_weeks)
                cent_pc2: np.ndarray = np.zeros(n_weeks)
                cent_date: np.ndarray = np.zeros(n_weeks)

                for w_i, w_val in enumerate(uw):
                    mw = week_id == w_val
                    cent_pc1[w_i] = float(np.mean(scores[mw, 0]))
                    cent_pc2[w_i] = float(np.mean(scores[mw, 1]) if scores.shape[1] > 1 else 0.0)
                    cent_date[w_i] = float(np.mean(dates_pca_mpl[mw]))

                # Individual run points (semi-transparent background)
                ax7.scatter(
                    dates_pca_mpl,
                    scores[:, 0],
                    s=25,
                    color=(0, 0.4, 0.8),
                    alpha=0.25,
                    linewidths=0,
                )
                ax7.scatter(
                    dates_pca_mpl,
                    scores[:, 1] if scores.shape[1] > 1 else np.zeros(n_valid_pca),
                    s=25,
                    color=(0.8, 0.4, 0),
                    alpha=0.25,
                    linewidths=0,
                )

                # Weekly centroid lines
                ax7.plot(
                    cent_date,
                    cent_pc1,
                    "-o",
                    color=(0, 0.4, 0.8),
                    linewidth=2,
                    markerfacecolor=(0, 0.4, 0.8),
                    label=f"PC1 ({explained[0]:.1f}%)",
                )
                ax7.plot(
                    cent_date,
                    cent_pc2,
                    "-s",
                    color=(0.8, 0.4, 0),
                    linewidth=2,
                    markerfacecolor=(0.8, 0.4, 0),
                    label=f"PC2 ({explained[1]:.1f}%)" if len(explained) > 1 else "PC2",
                )

                ax7.xaxis.set_major_formatter(mdates.DateFormatter("%d/%m/%y"))
                fig7.autofmt_xdate()
                ax7.set_xlabel("Data", fontweight="bold")
                ax7.set_ylabel("Score PCA", fontweight="bold")
                ax7.set_title(
                    f"Evoluzione Componenti Principali nel Tempo ({n_weeks} sett)",
                    fontweight="bold",
                )
                ax7.legend(loc="best")

                fig7.savefig(
                    export_dir / f"TOP{rank_idx:02d}_3_PCA_Mani.png",
                    dpi=300,
                    bbox_inches="tight",
                )
                plt.close(fig7)

                # =========================================================
                # Figure 8: PCA Sig — 2x3 grid of channel envelopes (app.m:8916-8973)
                # =========================================================
                fig8 = plt.figure(figsize=(14, 8), facecolor="w")
                m_l = 0.06; m_b = 0.08; g_x = 0.04; g_y = 0.12
                a_w = (1 - 2 * m_l - 2 * g_x) / 3
                a_h = (0.85 - m_b - g_y) / 2

                # Biweekly phase bins (app.m:8922-8926)
                bin_time: np.ndarray = np.floor(
                    (dates_pca - float(np.min(dates_pca))) / 14
                ).astype(int)
                # unique-based phase indexing (1-based equivalent in MATLAB via [~,~,ic])
                _, _, phase_ic = np.unique(bin_time, return_index=True, return_inverse=True)
                phase: np.ndarray = phase_ic  # 0-based
                P_phases: int = int(np.max(phase)) + 1

                tt_col: np.ndarray = np.linspace(0, 1, max(P_phases, 2))[:P_phases]
                blue = np.array([0.0, 0.45, 0.74])
                red = np.array([0.85, 0.1, 0.1])
                pcol: np.ndarray = np.outer(1 - tt_col, blue) + np.outer(tt_col, red)

                phase_labels: list[str] = []
                for p_i in range(P_phases):
                    mask_p = phase == p_i
                    if np.any(mask_p):
                        dn_min = float(np.min(dates_pca[mask_p]))
                        d = datetime.date.fromordinal(int(round(dn_min - 366)))
                        phase_labels.append(d.strftime("%d/%m/%y"))
                    else:
                        phase_labels.append("")

                max_y_sig: float = 0.0
                for c in range(n_chan):
                    cols_sl = slice(c * N_GRID, (c + 1) * N_GRID)
                    sub = X_orig_un[:, cols_sl]
                    val = float(np.max(np.mean(sub, axis=0) + np.std(sub, ddof=1, axis=0)))
                    if val > max_y_sig:
                        max_y_sig = val

                for c in range(n_chan):
                    row_ax = c // 3
                    col_ax = c % 3
                    left = m_l + col_ax * (a_w + g_x)
                    bottom = 0.85 - a_h - row_ax * (a_h + g_y)
                    ax_s = fig8.add_axes([left, bottom, a_w, a_h])
                    ax_s.grid(True)

                    cols_sl = slice(c * N_GRID, (c + 1) * N_GRID)
                    for p_i in range(P_phases):
                        mask_p = phase == p_i
                        if not np.any(mask_p):
                            continue
                        sub_rows = X_orig_un[mask_p, cols_sl]
                        mu_sig = np.mean(sub_rows, axis=0)
                        sd_sig = np.std(sub_rows, ddof=1, axis=0)
                        ax_s.fill_between(
                            x_grid,
                            mu_sig - sd_sig,
                            mu_sig + sd_sig,
                            color=pcol[p_i],
                            alpha=0.15,
                            linewidth=0,
                        )
                        ax_s.plot(
                            x_grid,
                            mu_sig,
                            color=pcol[p_i],
                            linewidth=1.5,
                            label=phase_labels[p_i],
                        )

                    ax_s.set_title(ch_labels[c], fontweight="bold", fontsize=10)
                    ax_s.set_ylim([0, max_y_sig * 1.1])
                    ax_s.set_xlim([x_grid[0], x_grid[-1]])
                    if c >= 3:
                        ax_s.set_xlabel("Posizione [m]", fontsize=8)
                    if c % 3 == 0:
                        ax_s.set_ylabel("Inv. RMS [m/s²]", fontsize=8)
                    if c == 0:
                        ax_s.legend(loc="upper left", fontsize=7)

                fig8.suptitle(
                    f"Evoluzione Firma Fisica per Sensore (Dal Blu al Rosso) - {dir_label}",
                    fontweight="bold",
                    fontsize=12,
                )
                fig8.savefig(
                    export_dir / f"TOP{rank_idx:02d}_3_PCA_Sig.png",
                    dpi=300,
                    bbox_inches="tight",
                )
                plt.close(fig8)

            except Exception:
                # Silent: if PCA fails, PCA images are not produced (app.m:8974-8976)
                pass

    return True
