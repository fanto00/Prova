"""Per-defect 3x3 classification report (pure data port of app.m:6195-6347).

Builds the SummaryData records; the dashboard rendering (figures, pie, scatter)
is left to the GUI layer.
"""
from __future__ import annotations

from collections import Counter

import numpy as np

from railway_inspector.config import CFG
from railway_inspector.app.utils.helpers import get_amp
from railway_inspector.app.analysis.spectrum import (
    get_spectrum_psd,
    peak_lambda_from_spectrum,
    lambda_to_label,
)

# Classification thresholds (local constants in app.m:6201-6210).
THR_LAT_VERT = 0.6     # declared in MATLAB, unused in this loop (kept for fidelity)
THR_ASYM_HIGH = 2.0
THR_ASYM_LOW = 0.5
THR_PITCH = 2.0
THR_PITCH_LOW = 0.5
L_GIUNTO = 0.5
L_IRREG = 1.0
L_DEFORM = 2.0


def _mode_categorical(cells: list[str]) -> str:
    """MATLAB mode(categorical(cells)): most frequent value; ties -> the
    alphabetically smallest (category order for cellstr is sorted)."""
    counts = Counter(cells)
    max_count = max(counts.values())
    winners = [c for c, n in counts.items() if n == max_count]
    return min(winners)


def classify_defects(DB: list, cfg: CFG) -> list[dict]:
    """Per-defect 3x3 classification + dominant wavelength (app.m:6221-6347).

    Returns one record dict per defect in DB (same order). The dashboard
    rendering is intentionally out of scope.
    """
    summary: list[dict] = []
    for Defect in DB:
        monthly: dict[str, dict] = {}
        spec_sx = None
        spec_dx = None
        freq_sx = None
        freq_dx = None
        w_sx = 0.0
        w_dx = 0.0

        for run in Defect["History"]:
            data = run["Data"]
            if "Filt" not in data:
                continue
            F = data["Filt"]
            mese_str = run["Date"].strftime("%Y_%m")

            a_sx_f = get_amp(F, "left_sensor_front")
            a_sx_r = get_amp(F, "left_sensor_rear")
            a_dx_f = get_amp(F, "right_sensor_front")
            a_dx_r = get_amp(F, "right_sensor_rear")
            a_lat_dxf = get_amp(F, "right_sensor_front_lat")
            a_lat_dxr = get_amp(F, "right_sensor_rear_lat")
            a_lat_sxf = get_amp(F, "left_sensor_front_lat")
            a_lat_sxr = get_amp(F, "left_sensor_rear_lat")

            a_vert_max = max(a_sx_f, a_sx_r, a_dx_f, a_dx_r)
            a_lat_max = max(a_lat_dxf, a_lat_dxr, a_lat_sxf, a_lat_sxr)
            if a_vert_max < 1e-6:
                continue

            ratio_sx_dx = (a_sx_f + a_sx_r) / max(a_dx_f + a_dx_r, 1e-6)
            ratio_front_rear = (a_sx_f + a_dx_f) / max(a_sx_r + a_dx_r, 1e-6)
            ratio_lat_vert = a_lat_max / max(a_vert_max, 1e-6)

            if ratio_sx_dx > THR_ASYM_HIGH:
                pos_x = "Left"
            elif ratio_sx_dx < THR_ASYM_LOW:
                pos_x = "Right"
            else:
                pos_x = "Center"
            if ratio_front_rear > THR_PITCH:
                pos_y = "Front"
            elif ratio_front_rear < THR_PITCH_LOW:
                pos_y = "Rear"
            else:
                pos_y = "Center"
            cella_3x3 = f"{pos_y}-{pos_x}"

            if mese_str not in monthly:
                monthly[mese_str] = {
                    "mese_label": mese_str, "cells": [],
                    "ratios_x": [], "ratios_y": [], "ratios_lv": [], "amp_max": 0.0,
                }
            m = monthly[mese_str]
            m["cells"].append(cella_3x3)
            m["ratios_x"].append(ratio_sx_dx)
            m["ratios_y"].append(ratio_front_rear)
            m["ratios_lv"].append(ratio_lat_vert)
            max_amp_run = max(a_sx_f, a_sx_r, a_dx_f, a_dx_r)
            m["amp_max"] = max(m["amp_max"], max_amp_run)

            w_pass_sx = a_sx_f + a_sx_r
            w_pass_dx = a_dx_f + a_dx_r

            s_sx, f_sx = get_spectrum_psd(
                F, ["left_sensor_front", "left_sensor_rear"], [a_sx_f, a_sx_r], cfg)
            if s_sx is not None:
                if spec_sx is None:
                    spec_sx = np.zeros_like(s_sx)
                    freq_sx = f_sx
                if len(s_sx) == len(spec_sx):
                    spec_sx = spec_sx + s_sx * w_pass_sx
                    w_sx = w_sx + w_pass_sx

            s_dx, f_dx = get_spectrum_psd(
                F, ["right_sensor_front", "right_sensor_rear"], [a_dx_f, a_dx_r], cfg)
            if s_dx is not None:
                if spec_dx is None:
                    spec_dx = np.zeros_like(s_dx)
                    freq_dx = f_dx
                if len(s_dx) == len(spec_dx):
                    spec_dx = spec_dx + s_dx * w_pass_dx
                    w_dx = w_dx + w_pass_dx

        if not monthly:
            summary.append({
                "ID": Defect["ID_PK"], "Pos": Defect["Avg_Pos"],
                "Amp": None, "Cella_Dominante": "N/D",
                "Lambda_SX": 0, "Lambda_DX": 0,
                "NaturaSpettrale_SX": None, "NaturaSpettrale_DX": None,
                "Ratio_SX_DX_Avg": None, "Ratio_FR_Avg": None,
                "Ratio_Lat_Vert_Avg": None, "Mese_Ultimo": None,
            })
            continue

        last_key = sorted(monthly.keys())[-1]
        ultimo_mese = monthly[last_key]
        cella_dominante = _mode_categorical(ultimo_mese["cells"])

        lambda_sx = peak_lambda_from_spectrum(spec_sx, freq_sx, w_sx, cfg)
        lambda_dx = peak_lambda_from_spectrum(spec_dx, freq_dx, w_dx, cfg)
        lambda_max_fisico = cfg.WINDOW_SIZE * 1.5
        if lambda_sx > lambda_max_fisico:
            lambda_sx = 0
        if lambda_dx > lambda_max_fisico:
            lambda_dx = 0

        summary.append({
            "ID": Defect["ID_PK"], "Pos": Defect["Avg_Pos"],
            "Amp": ultimo_mese["amp_max"],
            "Cella_Dominante": cella_dominante,
            "Lambda_SX": lambda_sx, "Lambda_DX": lambda_dx,
            "NaturaSpettrale_SX": lambda_to_label(lambda_sx, L_GIUNTO, L_IRREG, L_DEFORM),
            "NaturaSpettrale_DX": lambda_to_label(lambda_dx, L_GIUNTO, L_IRREG, L_DEFORM),
            "Ratio_SX_DX_Avg": float(np.mean(ultimo_mese["ratios_x"])),
            "Ratio_FR_Avg": float(np.mean(ultimo_mese["ratios_y"])),
            "Ratio_Lat_Vert_Avg": float(np.mean(ultimo_mese["ratios_lv"])),
            "Mese_Ultimo": ultimo_mese["mese_label"],
        })
    return summary
