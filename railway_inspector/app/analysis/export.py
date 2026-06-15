"""Export utilities: RAW overview figure, global scatter, LaTeX report generation."""
from __future__ import annotations

import logging
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import matplotlib
matplotlib.use("Agg")  # headless: no display required
import matplotlib.pyplot as plt
import matplotlib.cm as cm
import numpy as np
import pandas as pd
from scipy import ndimage

__all__ = [
    "generate_overview_figure",
    "generate_global_scatter",
    "export_report_latex",
    "_format_latex_safe",
]

log = logging.getLogger(__name__)

# Sensor keys and their subplot titles — same order as MATLAB sens_to_plot / titoli_sens
_SENS_KEYS: List[str] = [
    "left_sensor_front",
    "left_sensor_rear",
    "right_sensor_front",
    "right_sensor_rear",
    "right_sensor_front_lat",
    "left_sensor_front_lat",
]
_SENS_TITLES: List[str] = [
    "RAW: Vert SX Front",
    "RAW: Vert SX Rear",
    "RAW: Vert DX Front",
    "RAW: Vert DX Rear",
    "RAW: Lat DX Front",
    "RAW: Lat SX Front",
]

# LaTeX nomi/titoli profili e PSD — preservati identici a MATLAB per allineamento report
_NOMI_PROFILI: List[str] = [
    "Verticale_SX", "Verticale_DX", "Laterale_DX", "Laterale_SX"
]
_TITOLI_PROFILI: List[str] = [
    "Verticale Sinistro", "Verticale Destro", "Laterale Destro", "Laterale Sinistro"
]
_NOMI_PSD: List[str] = [
    "Vert_SX_Front", "Vert_SX_Rear", "Vert_DX_Front", "Vert_DX_Rear",
    "Lat_DX_Front", "Lat_DX_Rear", "Lat_SX_Front", "Lat_SX_Rear",
]
_TITOLI_PSD: List[str] = [
    "Vert. SX Front", "Vert. SX Rear", "Vert. DX Front", "Vert. DX Rear",
    "Lat. DX Front", "Lat. DX Rear", "Lat. SX Front", "Lat. SX Rear",
]

_COL_VIOLA = (0.6, 0.1, 0.8)   # bright purple — matches MATLAB col_viola


# ---------------------------------------------------------------------------
# Public helper
# ---------------------------------------------------------------------------

def _format_latex_safe(s: str) -> str:
    """Escape underscore and special LaTeX characters."""
    return s.replace("_", r"\_")


# ---------------------------------------------------------------------------
# FASE 0 — RAW overview figure
# ---------------------------------------------------------------------------

def generate_overview_figure(
    data_full: Dict[str, Any],
    space_shifted: np.ndarray,
    joints_table: pd.DataFrame,
    sorted_ipi: List[Dict],
    db: List[Dict],
    config: Dict,
    export_dir: Path,
    run_name: str = "",
) -> bool:
    """Generate headless RAW overview figure with joints and top-10 defects overlay."""
    try:
        L_full = len(space_shifted)

        # --- decimation step identical to MATLAB ---
        # step = max(1, round(0.5 / C.SPATIAL_RES))
        spatial_res: float = float(config["SPATIAL_RES"])
        step: int = max(1, round(0.5 / spatial_res))
        win_samples: int = max(3, round(0.5 / spatial_res))

        # --- pre-extract joints that fall within the spatial range ---
        if len(joints_table) > 0 and "Position" in joints_table.columns:
            mask_vis = (
                (joints_table["Position"] >= space_shifted[0])
                & (joints_table["Position"] <= space_shifted[-1])
            )
            jt_vis: pd.DataFrame = joints_table.loc[mask_vis].reset_index(drop=True)
        else:
            jt_vis = pd.DataFrame(columns=["Position", "Joint"])

        # --- figure: 1600x1200 pt @ 100 dpi → 16x12 inches ---
        fig = plt.figure(figsize=(16, 12), facecolor="w")
        n_plots = 8

        # --- subplots 1–6: sensor signals ---
        axes = []
        for sp in range(6):
            ax = fig.add_subplot(n_plots, 1, sp + 1)
            ax.grid(True)

            # overlay joints (purple vertical lines)
            for _, jrow in jt_vis.iterrows():
                ax.axvline(
                    x=float(jrow["Position"]),
                    color=_COL_VIOLA,
                    linewidth=0.8,
                    alpha=0.5,
                )

            key = _SENS_KEYS[sp]
            if key in data_full:
                sig_raw = np.asarray(data_full[key][:L_full], dtype=float)
                sig_raw = sig_raw - np.nanmean(sig_raw)       # remove DC offset

                # moving-RMS envelope: sqrt(movmean(sig^2, win_samples))
                # scipy.ndimage.uniform_filter1d replicates MATLAB movmean EndValues='shrink' (no zero-padding)
                sig_squared = sig_raw ** 2
                filtered = ndimage.uniform_filter1d(sig_squared, size=win_samples, mode="nearest")
                rms_raw = np.sqrt(filtered)

                ax.plot(
                    space_shifted[::step],
                    rms_raw[::step],
                    color=(0.2, 0.2, 0.2),
                    linewidth=0.6,
                )
                ax.set_ylabel("RMS [m/s²]", fontsize=7)
                ax.set_xlim(space_shifted[0], space_shifted[-1])

            y_lims = ax.get_ylim()

            # joint labels on first subplot only (avoids crowding — MATLAB sp==1)
            if sp == 0:
                for _, jrow in jt_vis.iterrows():
                    ax.text(
                        float(jrow["Position"]),
                        y_lims[0] + (y_lims[1] - y_lims[0]) * 0.05,
                        " " + str(jrow["Joint"]),
                        color=_COL_VIOLA,
                        rotation=90,
                        fontsize=7,
                        fontweight="bold",
                    )

            # overlay top-10 defects (red vertical lines)
            # build a quick id→avg_pos lookup to avoid O(n²) search
            db_lookup: Dict[str, float] = {
                entry["ID_PK"]: float(entry["Avg_Pos"]) for entry in db
            }
            num_top = min(10, len(sorted_ipi))
            for td in range(num_top):
                defect_id = sorted_ipi[td]["ID"]
                if defect_id in db_lookup:
                    pk_pos = db_lookup[defect_id]
                    ax.axvline(
                        x=pk_pos,
                        color="r",
                        linewidth=1.2,
                        alpha=0.6,
                    )
                    if sp == 0:
                        ax.text(
                            pk_pos,
                            y_lims[1] * 0.9,
                            f" #{td + 1}",
                            color="r",
                            fontsize=7,
                            fontweight="bold",
                        )

            ax.set_title(_SENS_TITLES[sp], fontsize=9, fontweight="bold")
            axes.append(ax)

        # --- subplot 7: speed (green) ---
        ax_spd = fig.add_subplot(n_plots, 1, 7)
        ax_spd.grid(True)
        if "speed" in data_full:
            ax_spd.plot(
                space_shifted[::step],
                np.asarray(data_full["speed"][:L_full], dtype=float)[::step],
                color=(0, 0.5, 0),
                linewidth=1.2,
            )
        ax_spd.set_ylabel("Vel. [km/h]", fontsize=7)
        ax_spd.set_xlim(space_shifted[0], space_shifted[-1])

        # --- subplot 8: curve (orange) ---
        ax_crv = fig.add_subplot(n_plots, 1, 8)
        ax_crv.grid(True)
        if "curve" in data_full:
            ax_crv.plot(
                space_shifted[::step],
                np.asarray(data_full["curve"][:L_full], dtype=float)[::step],
                color=(0.8, 0.4, 0),
                linewidth=1.2,
            )
        ax_crv.set_ylabel("Curv. [m]", fontsize=7)
        ax_crv.set_xlabel("Posizione PK [m]", fontweight="bold", fontsize=10)
        ax_crv.set_xlim(space_shifted[0], space_shifted[-1])

        fig.suptitle(
            f"Panoramica RAW della Tratta (Corsa: {run_name}) - Senza Filtri",
            fontweight="bold",
            fontsize=14,
        )

        out_path = export_dir / "00_Overview_Track_RAW.png"
        fig.savefig(out_path, dpi=300, bbox_inches="tight")
        plt.close(fig)
        return True

    except Exception as exc:
        log.error("Errore Overview RAW: %s", exc)
        return False


# ---------------------------------------------------------------------------
# FASE 1 — Global scatter (2×2, asymmetry colouring)
# ---------------------------------------------------------------------------

def generate_global_scatter(
    data_store: List[Dict],
    config: Dict,
    export_dir: Path,
) -> Tuple[Any, List[Any]]:
    """Generate 2x2 scatter plot with asymmetry coloring."""
    # 1200×800 pt @ 100 dpi → 12×8 inches
    fig = plt.figure(figsize=(12, 8), facecolor="w")
    fig.suptitle(
        "Contesto Globale: Max RMS (0.5m) Dati Filtrati",
        fontweight="bold",
        fontsize=14,
    )

    axes: List[Any] = []

    for g, ds in enumerate(data_store):
        ax = fig.add_subplot(2, 2, g + 1)
        ax.grid(True)
        axes.append(ax)

        filt = ds.get("Filt", {})
        mov_f = filt.get("MovF")
        mov_r = filt.get("MovR")
        ids   = filt.get("DefectID")

        if mov_f is not None and mov_r is not None and len(mov_f) > 0 and len(mov_r) > 0:
            vF = np.asarray(mov_f, dtype=float)
            vR = np.asarray(mov_r, dtype=float)
            IDs = np.asarray(ids)

            # --- asymmetry logic — identical to MATLAB ---
            ratio = vF / np.maximum(vR, 1e-6)
            asym_mask = (ratio > 1.5) | (ratio < 0.66)
            sym_mask  = ~asym_mask

            # symmetric points: grey, low alpha
            if sym_mask.any():
                ax.scatter(
                    vF[sym_mask], vR[sym_mask],
                    s=15,
                    color=(0.8, 0.8, 0.8),
                    alpha=0.2,
                )

            # asymmetric points: turbo colormap, one colour per unique defect ID
            unique_asym_ids = np.unique(IDs[asym_mask]) if asym_mask.any() else np.array([])
            n_asym = len(unique_asym_ids)

            leg_handles = []
            leg_labels: List[str] = []

            if n_asym > 0:
                cmap = matplotlib.colormaps["turbo"].resampled(max(1, n_asym))
                for k, uid in enumerate(unique_asym_ids):
                    idx_mask = (IDs == uid) & asym_mask

                    # retrieve PK name from DB (DB is not passed here; use str(uid) as fallback)
                    pk_name = str(uid)

                    h_scat = ax.scatter(
                        vF[idx_mask], vR[idx_mask],
                        s=35,
                        color=cmap(k),
                        edgecolors="k",
                        alpha=0.8,
                        label=pk_name,
                    )
                    leg_handles.append(h_scat)
                    leg_labels.append(pk_name)

                lgd = ax.legend(
                    leg_handles,
                    leg_labels,
                    loc="best",
                    fontsize=7,
                )
                lgd.set_title("PK Asimmetriche")
                if n_asym > 15:
                    # matplotlib legend does not have NumColumns — use ncol
                    import math
                    lgd._ncol = math.ceil(n_asym / 15)  # noqa: SLF001

            # identity line and square axes
            mx = max(np.max(np.concatenate([vF, vR])) * 1.1, 5.0)
            ax.plot([0, mx], [0, mx], "k--", linewidth=1)
            ax.set_aspect("equal", adjustable="box")
            ax.set_xlim(0, mx)
            ax.set_ylim(0, mx)

        ax.set_xlabel("Front [m/s²]")
        ax.set_ylabel("Rear [m/s²]")
        ax.set_title(str(ds.get("Name", f"Sensor {g + 1}")))

    out_path = export_dir / "00_Global_Scatter_RMS.png"
    fig.savefig(out_path, dpi=300, bbox_inches="tight")
    plt.close(fig)
    return fig, axes


# ---------------------------------------------------------------------------
# FASE 3 — LaTeX report generation
# ---------------------------------------------------------------------------

def _ipi_semaforo(ipi: float) -> str:
    """Return LaTeX colour bullet for IPI traffic-light logic."""
    # thresholds identical to MATLAB: 75 / 50 / 25
    if ipi >= 75:
        return r"\textcolor{red}{\Large $\bullet$}"
    elif ipi >= 50:
        return r"\textcolor{orange}{\Large $\bullet$}"
    elif ipi >= 25:
        return r"\textcolor{olive}{\Large $\bullet$}"
    else:
        return r"\textcolor{green!70!black}{\Large $\bullet$}"


def export_report_latex(
    sorted_ipi: List[Dict],
    db: List[Dict],
    export_dir: Path,
    track_name: str,
    config: Dict,
    has_overview: bool = False,
) -> bool:
    """Generate LaTeX document with global analysis and top-10 sections."""
    # safe_track: replace underscore with dash (MATLAB strrep(track_name,'_','-'))
    safe_track = track_name.replace("_", "-")
    tex_path = export_dir / f"Report_Tratta_{safe_track}.tex"

    lines: List[str] = []
    W = lines.append  # shorthand — keeps formatting close to MATLAB fprintf style

    # --- preamble ---
    W(r"\documentclass[11pt]{article}")
    W(r"\usepackage[utf8]{inputenc}")
    W(r"\usepackage{graphicx}")
    W(r"\usepackage[a4paper, margin=1.5cm]{geometry}")
    W(r"\usepackage{float}")
    W(r"\usepackage{subcaption}")
    W(r"\usepackage{longtable}")
    W(r"\usepackage{xcolor}")
    W(r"\usepackage{amsmath}")
    W(r"\usepackage{amssymb}")
    W("")
    W(rf"\title{{Report Diagnostico di Tratta: \textbf{{{safe_track}}}}}")
    W(r"\author{Analisi Globale}")
    W(r"\date{\today}")
    W("")
    W(r"\begin{document}")
    W(r"\maketitle")
    W("")

    # --- FASE 0 section (conditional) ---
    if has_overview:
        n_top_str = str(min(10, len(sorted_ipi)))
        W(r"\section*{Panoramica e Contesto Spaziale (Dati RAW)}")
        W(
            r"Il seguente grafico illustra la risposta dinamica \textbf{non filtrata} (RAW) dell'intera tratta. "
            r"I segnali sono riportati in termini di inviluppo RMS (0.5m) calcolato direttamente sulle accelerazioni "
            r"grezze, permettendo di identificare la reale energia trasmessa al carrello senza attenuazioni frequenziali.\\"
        )
        W("")
        W(r"Elementi di riferimento sovrapposti:")
        W(r"\begin{itemize}")
        W(r"  \item \textbf{Linee Viola Sottili:} Posizione dei giunti meccanici/saldati (con relativo codice "
          r"identificativo) estratti dal catasto giunti.")
        W(
            rf"  \item \textbf{{Linee Rosse Verticali:}} Ubicazione dei {n_top_str} difetti top "
            r"classificati per rischio di degrado."
        )
        W(r"  \item \textbf{Profili di Base:} Velocità del treno e raggio di curvatura locale "
          r"per la valutazione del contesto operativo.")
        W(r"\end{itemize}")
        W("")
        W(r"\begin{figure}[H]")
        W(r"\centering")
        W(r"\includegraphics[width=\textwidth]{00_Overview_Track_RAW.png}")
        W(r"\caption{Analisi RAW della tratta con identificazione giunti (grigio) e difetti critici (rosso).}")
        W(r"\end{figure}")
        W("")
        W(r"\clearpage")
        W("")

    # --- FASE 1 section: global scatter ---
    W(r"\section{Analisi Globale della Tratta}")
    W("")
    W(
        r"Il seguente scatter plot mostra la distribuzione dell'energia (Max RMS su finestra di 0.5m) "
        r"per tutti gli eventi registrati sulla tratta.\\"
    )
    W("")
    W(r"\textbf{Legenda Colori (Analisi Asimmetria):}")
    W(r"\begin{itemize}")
    W(r"  \item \textbf{Punti Grigi:} Urti simmetrici (rapporto dell'energia tra sensore Front e Rear bilanciato).")
    W(
        r"  \item \textbf{Punti Colorati:} Urti asimmetrici (forte sbilanciamento tra asse anteriore e posteriore). "
        r"Ad ogni difetto è assegnato un colore univoco per tracciarne la dispersione temporale."
    )
    W(r"\end{itemize}")
    W("")
    W(r"\begin{figure}[H]")
    W(r"\centering")
    W(r"\includegraphics[width=0.9\textwidth]{00_Global_Scatter_RMS.png}")
    W(r"\caption{Scatter Plot Globale Max RMS (0.5m).}")
    W(r"\end{figure}")
    W("")
    W(r"\clearpage")
    W("")

    # --- IPI ranking table ---
    W(rf"\section{{Classifica Rischio Degrado (IPI) - Top {len(sorted_ipi)}}}")
    W(r"\begin{longtable}{|c|l|c|c|c|c|}")
    W(r"\hline")
    W(
        r"\textbf{Pos} & \textbf{ID PK} & \textbf{IPI Score} & "
        r"\textbf{Trend / Lat} & \textbf{RMS Recente} & \textbf{Bonus IA / PCA} \\\\hline"
    )
    W(r"\endfirsthead")

    for i, s in enumerate(sorted_ipi, start=1):
        safe_id  = _format_latex_safe(s["ID"])
        semaforo = _ipi_semaforo(float(s["IPI"]))
        W(
            rf"{i} & {safe_id} & {semaforo} \textbf{{{int(s['IPI'])}/100}} & "
            rf"{s['STrend']:.1f} / {s['BonusLat']:.1f} & "
            rf"{s['RecentRMS']:.1f} & "
            rf"{s['BonusIA']:.1f} / {s['BonusPCA']:.1f} \\\\hline"
        )

    W(r"\end{longtable}")
    W("")

    # --- mini top-5 subtables ---
    W(r"\vspace{0.5cm}")
    W(r"\subsection*{Classifiche Specifiche di Severità e Deriva}")
    W(
        r"Oltre all'indice composito IPI, si riportano di seguito i difetti che registrano i picchi assoluti "
        r"di energia (Verticale e Laterale) e quelli con la maggiore velocità di degrado recente (Trend Percentuale)."
    )
    W("")

    # sort arrays — mirror MATLAB [~, sort_v] = sort([SortedIpi.MaxVert], 'descend')
    top5_v = sorted(sorted_ipi, key=lambda x: x["MaxVert"],  reverse=True)[:5]
    top5_l = sorted(sorted_ipi, key=lambda x: x["MaxLat"],   reverse=True)[:5]
    top5_p = sorted(sorted_ipi, key=lambda x: x["IncPerc"],  reverse=True)[:5]

    W(r"\begin{figure}[H]")
    W(r"\centering")

    # minipage 1: Top 5 Verticale
    W(r"\begin{minipage}[t]{0.31\textwidth}")
    W(r"\centering")
    W(r"\textbf{Top 5 Max Verticale}\\")
    W(r"\vspace{0.2cm}")
    W(r"\begin{tabular}{|c|c|c|}")
    W(r"\hline")
    W(r"\textbf{Pos} & \textbf{PK} & \textbf{RMS [$m/s^2$]} \\\\hline")
    for k, entry in enumerate(top5_v, start=1):
        W(rf"{k} & {_format_latex_safe(entry['ID'])} & {entry['MaxVert']:.1f} \\\\hline")
    W(r"\end{tabular}")
    W(r"\end{minipage}\hfill")

    # minipage 2: Top 5 Laterale
    W(r"\begin{minipage}[t]{0.31\textwidth}")
    W(r"\centering")
    W(r"\textbf{Top 5 Max Laterale}\\")
    W(r"\vspace{0.2cm}")
    W(r"\begin{tabular}{|c|c|c|}")
    W(r"\hline")
    W(r"\textbf{Pos} & \textbf{PK} & \textbf{RMS [$m/s^2$]} \\\\hline")
    for k, entry in enumerate(top5_l, start=1):
        W(rf"{k} & {_format_latex_safe(entry['ID'])} & {entry['MaxLat']:.1f} \\\\hline")
    W(r"\end{tabular}")
    W(r"\end{minipage}\hfill")

    # minipage 3: Top 5 Peggioramento
    W(r"\begin{minipage}[t]{0.31\textwidth}")
    W(r"\centering")
    W(r"\textbf{Top 5 Peggioramento}\\")
    W(r"\vspace{0.2cm}")
    W(r"\begin{tabular}{|c|c|c|}")
    W(r"\hline")
    W(r"\textbf{Pos} & \textbf{PK} & \textbf{Trend [\%]} \\\\hline")
    for k, entry in enumerate(top5_p, start=1):
        inc = entry["IncPerc"]
        # explicit '+' for positive trends — mirrors MATLAB conditional sprintf
        trend_str = f"+{inc:.1f}" if inc > 0 else f"{inc:.1f}"
        W(rf"{k} & {_format_latex_safe(entry['ID'])} & {trend_str} \\\\hline")
    W(r"\end{tabular}")
    W(r"\end{minipage}")

    W(r"\end{figure}")
    W("")

    # --- IPI methodology section ---
    W(r"\vspace{0.5cm}")
    W(r"\section*{Metodologia di Calcolo Indice IPI}")
    W(
        r"L'Indice di Priorità Ispezione (IPI) è un parametro sintetico (0-100) che quantifica il rischio "
        r"evolutivo del difetto, bilanciando in egual misura la componente assoluta del danno e la sua "
        r"progressione temporale. La formula applicata è:"
    )
    W(r"\begin{equation*}")
    W(r"IPI = S_{Assoluto} + S_{Trend} + B_{Lat} + B_{PCA} + B_{AI}")
    W(r"\end{equation*}")
    W("")
    W(r"\begin{itemize}")
    W(
        rf"  \item \textbf{{Severità Assoluta ($S_{{Assoluto}}$, Max 50 pts):}} "
        rf"Valuta proattivamente il livello di energia RMS recente (ultimi {config['IPI_RECENT_DAYS']} giorni). "
        rf"Superati i {config['IPI_SEV_THR_HIGH']} m/s$^2$ vengono assegnati 50 punti, "
        rf"mentre sotto i {config['IPI_SEV_THR_LOW']} m/s$^2$ il contributo è nullo."
    )
    W(
        rf"  \item \textbf{{Punteggio Trend ($S_{{Trend}}$, Max 50 pts):}} "
        rf"Incremento percentuale della severità RMS recente rispetto alla baseline storica. "
        rf"Il punteggio massimo è raggiunto con un incremento del {config['IPI_TREND_SENS']}\%."
    )
    W(
        rf"  \item \textbf{{Aggravante Laterale ($B_{{Lat}}$, Max 30 pts):}} "
        rf"Penalità assegnata per rapporti accelerometrici Laterale/Verticale superiori a {config['IPI_LAT_THRESH']:.1f}."
    )
    W(
        r"  \item \textbf{Bonus PCA ($B_{PCA}$, Max 25 pts):} Valuta l'instabilità della firma cinematica "
        r"attraverso l'Analisi delle Componenti Principali e premia trend o escursioni statistiche anomale "
        r"dell'errore di ricostruzione (RMSE)."
    )
    W(
        r"  \item \textbf{Bonus IA ($B_{AI}$, Max 20 pts):} Valuta la perdita di accuratezza di ricostruzione "
        r"del segnale tramite un Autoencoder Neurale (Deep Learning)."
    )
    W(r"\end{itemize}")
    W("")

    W(r"\subsection*{Livelli di Attenzione}")
    W(r"\begin{itemize}")
    W(r"  \item \textcolor{red}{\textbf{Critico ($\ge$75):}} Ispezione urgente / Intervento immediato.")
    W(r"  \item \textcolor{orange}{\textbf{Allerta (50-74):}} Monitoraggio ravvicinato e programmazione manutenzione.")
    W(r"  \item \textcolor{olive}{\textbf{Monitoraggio (25-49):}} Analisi dei trend in ufficio.")
    W(r"  \item \textcolor{green!70!black}{\textbf{Stabile ($<$25):}} Manutenzione ordinaria.")
    W(r"\end{itemize}")

    W(r"\subsection*{Requisiti di Validità}")
    W(
        rf"Il calcolo viene eseguito solo se sono soddisfatti i requisiti minimi di sistema: "
        rf"almeno {config['IPI_MIN_RUNS']} passaggi totali, una storia minima di "
        rf"{config['IPI_MIN_HISTORY_DAYS']} giorni e almeno {config['IPI_MIN_DAYS']} giorni di misurazioni distinte."
    )
    W("")
    W(r"\clearpage")
    W("")

    # --- per-defect detail loop (top 10 max) ---
    num_top = min(10, len(sorted_ipi))
    for i in range(num_top):
        s = sorted_ipi[i]
        safe_id = _format_latex_safe(s["ID"])
        rank = i + 1  # 1-based display

        W(rf"\section{{Posizione \#{rank}: Difetto {safe_id}}}")

        # Executive Summary
        W(r"\subsection*{Executive Summary}")
        W(r"\begin{itemize}")
        W(rf"\item \textbf{{Indice di Priorità Ispezione (IPI):}} {{\large \textbf{{{int(s['IPI'])} / 100}}}}")
        W(
            rf"\item \textbf{{Trend Base:}} {s['STrend']:.1f} \quad "
            rf"\textbf{{Aggravante Lat:}} {s['BonusLat']:.1f} \quad "
            rf"\textbf{{IA/PCA:}} {(s['BonusIA'] + s['BonusPCA']):.1f}"
        )
        W(rf"\item \textbf{{RMS Recente:}} {s['RecentRMS']:.1f} m/s$^2$")
        W(r"\end{itemize}")
        W("")

        # Max-run signals figure
        W(r"\begin{figure}[H]")
        W(r"\centering")
        W(rf"\includegraphics[width=\textwidth]{{TOP{rank:02d}_0_Max_Run_Signals.png}}")
        W(r"\caption{Segnali cinematici del passaggio a massima severità.}")
        W(r"\end{figure}")
        W("")
        W(r"\clearpage")
        W("")

        # PCA section (conditional on file existence — LaTeX compiler handles missing \includegraphics)
        f_pca_anom  = f"TOP{rank:02d}_3_PCA_Anom.png"
        f_pca_scree = f"TOP{rank:02d}_3_PCA_Scree.png"
        f_pca_mani  = f"TOP{rank:02d}_3_PCA_Mani.png"
        f_pca_sig   = f"TOP{rank:02d}_3_PCA_Sig.png"

        # check for file on disk only if we have a concrete export_dir (always do: include the block)
        if (export_dir / f_pca_anom).exists():
            W(r"\subsection*{Analisi delle Componenti Principali (Channel-Space PCA)}")
            W(
                r"L'algoritmo implementa una PCA spazialmente parallela (Channel-Space PCA). "
                r"Riducendo le matrici in un sottospazio di $k=2$ componenti, estrae la firma cinematica "
                r"di base e valuta il disallineamento geometrico (RMSE) dell'urto.\\"
            )
            W("")
            W(r"\begin{figure}[H]")
            W(r"\centering")
            W(rf"\begin{{subfigure}}[b]{{0.48\textwidth}}\centering\includegraphics[width=\textwidth]{{{f_pca_anom}}}\caption{{Anomaly Score (RMSE)}}\end{{subfigure}}\hfill")
            W(rf"\begin{{subfigure}}[b]{{0.48\textwidth}}\centering\includegraphics[width=\textwidth]{{{f_pca_scree}}}\caption{{Scree Plot (Varianza)}}\end{{subfigure}}\\\\[0.4cm]")
            W(rf"\begin{{subfigure}}[b]{{0.48\textwidth}}\centering\includegraphics[width=\textwidth]{{{f_pca_mani}}}\caption{{Evoluzione PC1 e PC2 vs Tempo}}\end{{subfigure}}\hfill")
            W(rf"\begin{{subfigure}}[b]{{0.48\textwidth}}\centering\includegraphics[width=\textwidth]{{{f_pca_sig}}}\caption{{Evoluzione Firma Media per Sensore}}\end{{subfigure}}")
            W(r"\caption{Risultati dell'analisi PCA sul difetto.}")
            W(r"\end{figure}")
            W("")
            W(r"\textbf{Analisi Matematica e Guida alla Lettura:}")
            W(r"\begin{itemize}")
            W(
                r"  \item \textbf{(a) Anomaly Score (RMSE):} Calcolato proiettando le misurazioni nello spazio "
                r"dei residui $\mathbf{R}$. Per ogni passaggio $i$, si valuta lo scostamento geometrico rispetto "
                r"ai $C=6$ canali sensore:"
            )
            W(
                r"  \[ RMSE_i = \sqrt{\frac{1}{M} \sum_{m=1}^{M} \left( \frac{1}{C} \sum_{c=1}^{C} R_{i,m,c}^2 \right)} \]"
            )
            W(
                r"  Un trend in crescita o la presenza di picchi oltre la soglia statistica "
                r"($\mu_{RMSE} + 2\sigma_{RMSE}$) indica un'evoluzione anomala dell'urto o un disassamento meccanico."
            )
            W("")
            W(
                r"  \item \textbf{(b) Scree Plot (Varianza):} Rappresenta la percentuale cumulativa di varianza "
                r"spiegata $EV_k$ dalle componenti principali estratte nello spazio parallelo dei canali. "
                r"Una varianza spiegata molto bassa indica un urto instabile ad alta dispersione energetica spaziale."
            )
            W("")
            W(
                r"  \item \textbf{(c) Evoluzione PC1 e PC2 vs Tempo:} Mostra l'andamento nel tempo delle prime due "
                r"componenti principali (i marcatori opachi indicano le medie settimanali). Una forte deriva "
                r"(trend crescente o decrescente) dei punteggi indica una mutazione progressiva della morfologia dell'onda."
            )
            W("")
            W(
                r"  \item \textbf{(d) Firma Media per Sensore:} Sovrapposizione delle forme d'onda medie suddivise "
                r"per blocchi temporali continui. Mostra come il difetto evolve (in ampiezza o estensione spaziale) "
                r"isolando il comportamento fisico per ciascun punto di misura del carrello."
            )
            W(r"\end{itemize}")
            W("")
            W(r"\clearpage")
            W("")

        # Diagnostic indicators (3×3, Lat, Lambda)
        W(r"\subsection*{Indicatori Diagnostici (Media Giornaliera)}")
        W(r"\begin{figure}[H]")
        W(r"\centering")
        W(
            rf"\begin{{subfigure}}[b]{{0.48\textwidth}}\centering"
            rf"\includegraphics[width=\textwidth]{{TOP{rank:02d}_2_Giornaliera_C_Matrice3x3.png}}"
            rf"\caption{{Matrice 3x3 Simmetria}}\end{{subfigure}}\hfill"
        )
        W(
            rf"\begin{{subfigure}}[b]{{0.48\textwidth}}\centering"
            rf"\includegraphics[width=\textwidth]{{TOP{rank:02d}_2_Giornaliera_D_RatioLat.png}}"
            rf"\caption{{Rapporto Laterale/Verticale}}\end{{subfigure}}\\\\[0.4cm]"
        )
        W(
            rf"\begin{{subfigure}}[b]{{0.48\textwidth}}\centering"
            rf"\includegraphics[width=\textwidth]{{TOP{rank:02d}_2_Giornaliera_E_Lambda.png}}"
            rf"\caption{{Evoluzione Lunghezza d'Onda}}\end{{subfigure}}"
        )
        W(r"\caption{Indicatori evolutivi globali per il difetto.}")
        W(r"\end{figure}")
        W("")
        W(r"\clearpage")
        W("")

        # Waterfall 3D — 4 profili
        W(r"\subsection*{Evoluzione Profilo Spaziale 3D (Max RMS)}")
        W(r"\begin{figure}[H]")
        W(r"\centering")
        for idx_prof, (nome, titolo) in enumerate(zip(_NOMI_PROFILI, _TITOLI_PROFILI), start=1):
            W(rf"\begin{{subfigure}}[b]{{0.48\textwidth}}")
            W(r"\centering")
            W(rf"\includegraphics[width=\textwidth]{{TOP{rank:02d}_2_Giornaliera_A_Profilo_{nome}.png}}")
            W(rf"\caption{{Waterfall {titolo}}}")
            W(r"\end{subfigure}")
            # MATLAB: if mod(idx_prof, 2) == 1 → \hfill; elseif idx_prof == 2 → blank + vspace
            if idx_prof % 2 == 1:
                W(r"\hfill")
            elif idx_prof == 2:
                W("")
                W(r"\vspace{0.4cm}")
                W("")
        W(r"\caption{Evoluzione della forma d'onda spaziale per i 4 gruppi sensori.}")
        W(r"\end{figure}")
        W("")
        W(r"\clearpage")
        W("")

        # PSD verticali (idx_psd 1–4, 0-based 0–3)
        W(r"\subsection*{Evoluzione Spettrale (PSD 3D) - Sensori Verticali}")
        W(r"\begin{figure}[H]")
        W(r"\centering")
        for idx_psd in range(1, 5):  # 1..4
            nome = _NOMI_PSD[idx_psd - 1]
            titolo = _TITOLI_PSD[idx_psd - 1]
            W(rf"\begin{{subfigure}}[b]{{0.48\textwidth}}")
            W(r"\centering")
            W(rf"\includegraphics[width=\textwidth]{{TOP{rank:02d}_2_Giornaliera_B_PSD_{idx_psd}_{nome}.png}}")
            W(rf"\caption{{PSD: {titolo}}}")
            W(r"\end{subfigure}")
            if idx_psd % 2 == 1:
                W(r"\hfill")
            elif idx_psd == 2:
                W("")
                W(r"\vspace{0.4cm}")
                W("")
        W(r"\caption{Contenuto in frequenza spaziale per i sensori verticali.}")
        W(r"\end{figure}")
        W("")

        # PSD laterali (idx_psd 5–8, 0-based 4–7)
        W(r"\subsection*{Evoluzione Spettrale (PSD 3D) - Sensori Laterali}")
        W(r"\begin{figure}[H]")
        W(r"\centering")
        for idx_psd in range(5, 9):  # 5..8
            nome = _NOMI_PSD[idx_psd - 1]
            titolo = _TITOLI_PSD[idx_psd - 1]
            W(rf"\begin{{subfigure}}[b]{{0.48\textwidth}}")
            W(r"\centering")
            W(rf"\includegraphics[width=\textwidth]{{TOP{rank:02d}_2_Giornaliera_B_PSD_{idx_psd}_{nome}.png}}")
            W(rf"\caption{{PSD: {titolo}}}")
            W(r"\end{subfigure}")
            # MATLAB: if mod(idx_psd,2)==1 → \hfill; elseif idx_psd==6 → vspace
            if idx_psd % 2 == 1:
                W(r"\hfill")
            elif idx_psd == 6:
                W("")
                W(r"\vspace{0.4cm}")
                W("")
        W(r"\caption{Contenuto in frequenza spaziale per i sensori laterali.}")
        W(r"\end{figure}")
        W("")
        W(r"\clearpage")
        W("")

    W(r"\end{document}")

    tex_path.write_text("\n".join(lines), encoding="utf-8")
    return True
