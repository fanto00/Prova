"""
database/builder.py
===================
Implements ``build_database_for_route``, faithfully replicating
Database_Allineamento_nomax.m lines 134-785 for ONE route.

Structure
---------
Phase A  (lines 149-333): per-file loop — macro-alignment, crop, defect
          detection, Global_Event_List accumulation.
Phase B  (lines 335-577): clustering + micro-alignment, first MASTER_DB build.
Phase C  (lines 579-785): second-pass completion (skipped when ONLY_JOINTS).

Internal helpers
----------------
_build_cluster_entry(cluster_rows, avail_sensors, ref_sensor, sorted_signals,
                     sorted_meta, cfg)
    Build one MASTER_DB entry including micro-alignment history (Phase B,
    lines 392-576).

_second_pass_complete(master_db, run_info_list, cached_data, cfg)
    Enrich confirmed defects with non-triggered runs (Phase C, lines 584-782).
"""

from __future__ import annotations

import copy
import os
import math
from datetime import datetime
from typing import Any

import numpy as np

from railway_inspector.io.mat_loader import load_section, parse_run_date


def _matlab_round(x: float) -> int:
    """Round half-away-from-zero, matching MATLAB's round() for non-negative x."""
    return int(np.floor(x + 0.5))
from railway_inspector.signal.alignment import (
    xcorr_lag,
    shift_signal_frac,
    hilbert_envelope,
    build_align_template,
)
from railway_inspector.signal.resampling import interpft
from railway_inspector.detection.extraction import (
    analyze_and_extract,
    extract_at_joints,
    extract_at_position,
    peak_amp,
)
from railway_inspector.detection.clustering import (
    assign_cluster_ids,
    filter_by_mode_speed,
)
from railway_inspector.database.pipeline import (
    determine_orientation,
    compute_geo_signal,
    align_and_crop_run,
)


# ---------------------------------------------------------------------------
# _micro_align_and_crop  (inner helper, lines 467-551)
# ---------------------------------------------------------------------------

def _micro_align_and_crop(
    curr_signals: dict,
    env_template: np.ndarray | None,
    ref_sensor: str,
    corr_radius_samp: int,
    n_up: int,
    max_lag_up: int,
    win_final: float,
    cfg,
) -> tuple[dict, float]:
    """Apply micro-alignment to template and final crop.

    Replicates MATLAB lines 467-538.

    Returns
    -------
    (signals_cropped, shift_m)
    """
    # Work on a copy so callers' data is not mutated
    curr_signals = copy.deepcopy(curr_signals)

    shift_m = 0.0

    # --- Alignment to template (lines 471-486) ---
    if (
        env_template is not None
        and ref_sensor
        and "Filt" in curr_signals
        and ref_sensor in curr_signals["Filt"]
    ):
        curr_filt = np.asarray(curr_signals["Filt"][ref_sensor], dtype=float)
        rel_axis = np.asarray(curr_signals["RelativeAxis"], dtype=float)
        curr_zero_idx = int(np.argmin(np.abs(rel_axis)))

        c_start = curr_zero_idx - corr_radius_samp
        c_end = curr_zero_idx + corr_radius_samp
        if c_start >= 0 and c_end < len(curr_filt):
            curr_focus = curr_filt[c_start : c_end + 1]   # length == focus_len
            curr_up = interpft(curr_focus, n_up)
            env_curr = hilbert_envelope(curr_up)

            lag = xcorr_lag(env_template, env_curr, max_lag_up)
            shift_m = (lag / cfg.UPSAMPLE_FACTOR) * cfg.SPATIAL_RES

    # --- Fractional shift (lines 490-508) ---
    if shift_m != 0.0:
        if "Filt" in curr_signals:
            avail = list(curr_signals["Filt"].keys())
            for sn in avail:
                v = curr_signals["Filt"][sn]
                if isinstance(v, np.ndarray) and v.ndim >= 1 and v.size > 1:
                    curr_signals["Filt"][sn] = shift_signal_frac(v, shift_m, cfg.SPATIAL_RES)
        if "Raw" in curr_signals:
            for sn, v in curr_signals["Raw"].items():
                if isinstance(v, np.ndarray) and v.ndim >= 1 and v.size > 1:
                    curr_signals["Raw"][sn] = shift_signal_frac(v, shift_m, cfg.SPATIAL_RES)

    # --- Final crop (lines 512-538) ---
    n_half = int(round(win_final / cfg.SPATIAL_RES))
    rel_axis = np.asarray(curr_signals["RelativeAxis"], dtype=float)
    center_idx = _matlab_round(len(rel_axis) / 2) - 1   # MATLAB 1-based round(N/2) -> 0-based

    crop_start_ideal = center_idx - n_half
    crop_end_ideal = center_idx + n_half
    safe_start = max(0, crop_start_ideal)
    safe_end = min(len(rel_axis) - 1, crop_end_ideal)

    if "Filt" in curr_signals:
        for sn, v in curr_signals["Filt"].items():
            if isinstance(v, np.ndarray) and v.ndim == 1 and len(v) > 1:
                curr_signals["Filt"][sn] = v[safe_start : safe_end + 1]
    if "Raw" in curr_signals:
        for sn, v in curr_signals["Raw"].items():
            if isinstance(v, np.ndarray) and v.ndim == 1 and len(v) > 1:
                curr_signals["Raw"][sn] = v[safe_start : safe_end + 1]

    # Recompute RelativeAxis (MATLAB lines 537-538)
    idx_vector = np.arange(safe_start, safe_end + 1) - center_idx
    curr_signals["RelativeAxis"] = idx_vector.astype(float) * cfg.SPATIAL_RES

    return curr_signals, shift_m


# ---------------------------------------------------------------------------
# _build_cluster_entry  (Phase B, lines 354-576)
# ---------------------------------------------------------------------------

def _build_cluster_entry(
    db_idx: int,
    subset_rows: list[dict],
    cfg,
) -> dict | None:
    """Build one MASTER_DB entry for a cluster.

    Parameters
    ----------
    db_idx      : 1-based index (for debug prints only).
    subset_rows : list of event dicts, each with keys:
                  Pos, Amp, Date, RunName, Signals, Infra_Match, MacroShift.
    cfg         : CFG object.

    Returns
    -------
    MASTER_DB entry dict, or None if the cluster becomes empty after filtering.
    """
    # Extract speed for each row (lines 361-363)
    speeds = np.array([
        float(r["Signals"].get("Speed", np.nan)) for r in subset_rows
    ], dtype=float)

    # Mode-speed filter (lines 365-377)
    keep_mask, mode_speed = filter_by_mode_speed(
        speeds, cfg.SPEED_TOL, cfg.ONLY_JOINTS
    )
    subset_rows = [r for r, k in zip(subset_rows, keep_mask) if k]

    if not subset_rows:
        return None

    avg_p = float(np.mean([r["Pos"] for r in subset_rows]))

    # Preliminary entry (lines 381-386)
    entry: dict[str, Any] = {
        "ID_PK": f"{avg_p / 1000:.3f}",
        "Avg_Pos": avg_p,
        "Max_Severity": float(max(r["Amp"] for r in subset_rows)),
        "Num_Occurrences": len(subset_rows),
        "Infrastructure": subset_rows[0]["Infra_Match"],
        "Mode_Speed": mode_speed,
    }

    # Sort by date (lines 388-389)
    subset_rows = sorted(subset_rows, key=lambda r: r["Date"])

    # Master = max amplitude (lines 394-395)
    master_idx = int(np.argmax([r["Amp"] for r in subset_rows]))
    master_signals = subset_rows[master_idx]["Signals"]

    # Reference sensor = max energy among Filt sensors (lines 397-406)
    ref_sensor = ""
    max_energy = -1.0
    avail_sensors: list[str] = []
    if "Filt" in master_signals and isinstance(master_signals["Filt"], dict):
        avail_sensors = [
            sn for sn, v in master_signals["Filt"].items()
            if isinstance(v, np.ndarray) and v.size > 1
        ]
        for sn in avail_sensors:
            energy = float(np.sum(np.asarray(master_signals["Filt"][sn], dtype=float) ** 2))
            if energy > max_energy:
                max_energy = energy
                ref_sensor = sn

    # Master centre correction (lines 414-436)
    true_avg_pos = float(np.mean([r["Pos"] for r in subset_rows]))

    if ref_sensor and "Filt" in master_signals and ref_sensor in master_signals["Filt"]:
        master_filt = np.asarray(master_signals["Filt"][ref_sensor], dtype=float)
        rel_ax = np.asarray(master_signals.get("RelativeAxis", []), dtype=float)
        if len(rel_ax) > 0 and len(master_filt) > 0:
            true_zero_idx = int(np.argmin(np.abs(rel_ax)))
            search_radius = int(round(cfg.ALIGN_FOCUS / cfg.SPATIAL_RES))
            idx_s = max(0, true_zero_idx - search_radius)
            idx_e = min(len(master_filt) - 1, true_zero_idx + search_radius)
            if idx_e > idx_s:
                local_peak = int(np.argmax(np.abs(master_filt[idx_s : idx_e + 1])))
                master_peak_idx = local_peak + idx_s
                offset_m = (master_peak_idx - true_zero_idx) * cfg.SPATIAL_RES
                true_avg_pos = float(subset_rows[master_idx]["Pos"]) + offset_m

    entry["ID_PK"] = f"{true_avg_pos / 1000:.3f}"
    entry["Avg_Pos"] = true_avg_pos
    entry["Max_Severity"] = float(max(r["Amp"] for r in subset_rows))
    entry["Num_Occurrences"] = len(subset_rows)
    entry["Infrastructure"] = subset_rows[0]["Infra_Match"]

    # --- Template build (lines 446-452) ---
    corr_radius_samp = int(round(cfg.ALIGN_FOCUS / cfg.SPATIAL_RES))
    focus_len = 2 * corr_radius_samp + 1
    n_up = focus_len * cfg.UPSAMPLE_FACTOR
    max_lag_samples = int(round(cfg.ALIGN_MAX_LAG / cfg.SPATIAL_RES))
    max_lag_up = max_lag_samples * cfg.UPSAMPLE_FACTOR

    # build_align_template expects list of dicts with 'Filt' and 'RelativeAxis'
    sorted_signal_dicts = [r["Signals"] for r in subset_rows]

    env_template = build_align_template(
        sorted_signal_dicts,
        ref_sensor,
        focus_len,
        max_lag_samples,
        n_up,
        cfg,
    )

    # --- Per-run micro-alignment history (lines 456-552) ---
    win_final = cfg.JOINT_WINDOW if cfg.ONLY_JOINTS else cfg.WINDOW_FINAL

    hist: list[dict] = []

    for h, row in enumerate(subset_rows):
        curr_signals = copy.deepcopy(row["Signals"])

        aligned_signals, shift_m = _micro_align_and_crop(
            curr_signals,
            env_template,
            ref_sensor,
            corr_radius_samp,
            n_up,
            max_lag_up,
            win_final,
            cfg,
        )

        # Degenerate check (lines 540-547)
        is_valid = True
        if (
            ref_sensor
            and "Filt" in aligned_signals
            and ref_sensor in aligned_signals["Filt"]
        ):
            check = np.asarray(aligned_signals["Filt"][ref_sensor], dtype=float)
            if len(check) > 1 and float(np.std(check, ddof=1)) < 0.01:
                is_valid = False

        if not is_valid:
            continue   # skip degenerate runs (lines 554-563)

        hist.append({
            "Date": row["Date"],
            "RunName": str(row["RunName"]),
            "Detected": True,
            "MacroShift": float(row["MacroShift"]),
            "GeoShift": float(shift_m),
            "OriginalPos": float(true_avg_pos),
            "Amp": peak_amp(aligned_signals, win_final),
            "Data": aligned_signals,
        })

    # --- JOINT_MAX_RUNS cap (lines 565-571) ---
    if cfg.ONLY_JOINTS and len(hist) > cfg.JOINT_MAX_RUNS:
        hist_sorted_desc = sorted(hist, key=lambda x: x["Date"], reverse=True)
        hist_capped = hist_sorted_desc[: cfg.JOINT_MAX_RUNS]
        hist = sorted(hist_capped, key=lambda x: x["Date"])

    entry["Num_Occurrences"] = len(hist)
    if hist:
        entry["Max_Severity"] = float(max(h["Amp"] for h in hist))
    entry["History"] = hist
    entry["Num_Total_Runs"] = len(hist)

    return entry


# ---------------------------------------------------------------------------
# _second_pass_complete  (Phase C, lines 579-782)
# ---------------------------------------------------------------------------

def _second_pass_complete(
    master_db: list[dict],
    run_info_list: list[dict],
    cached_data: list[dict | None],
    cfg,
) -> None:
    """Enrich confirmed defects (Num_Occurrences >= MIN_RUNS_COMPLETE) by
    adding non-triggered runs, up to MAX_TOTAL_RUNS total.

    Modifies master_db entries in-place.  Skipped entirely when ONLY_JOINTS.

    Replicates MATLAB lines 579-782.
    """
    for d_entry in master_db:
        # lines 584-589
        if cfg.ONLY_JOINTS:
            break
        if d_entry["Num_Occurrences"] < cfg.MIN_RUNS_COMPLETE:
            continue

        defect_pos = float(d_entry["Avg_Pos"])
        old_history = d_entry["History"]
        existing_runs = {str(h["RunName"]) for h in old_history}

        # --- Master for micro-align (lines 598-616) ---
        master_h_idx = int(np.argmax([h["Amp"] for h in old_history]))
        master_data = old_history[master_h_idx]["Data"]

        m_avail: list[str] = []
        m_ref_sensor = ""
        m_max_energy = -1.0
        if "Filt" in master_data and isinstance(master_data["Filt"], dict):
            m_avail = [
                sn for sn, v in master_data["Filt"].items()
                if isinstance(v, np.ndarray) and v.size > 1
            ]
            for sn in m_avail:
                e = float(np.sum(np.asarray(master_data["Filt"][sn], dtype=float) ** 2))
                if e > m_max_energy:
                    m_max_energy = e
                    m_ref_sensor = sn

        master_filt_c: np.ndarray | None = None
        if m_ref_sensor and "Filt" in master_data and m_ref_sensor in master_data["Filt"]:
            master_filt_c = np.asarray(master_data["Filt"][m_ref_sensor], dtype=float)

        # --- Sort ALL valid runs newest-first (lines 621-623) ---
        valid_indices = [
            i for i, ri in enumerate(run_info_list) if ri["Valid"]
        ]
        valid_indices.sort(key=lambda i: run_info_list[i]["Date"], reverse=True)

        new_history: list[dict] = []
        filled = 0
        added_no_trigger = 0
        win_final = cfg.JOINT_WINDOW if cfg.ONLY_JOINTS else cfg.WINDOW_FINAL
        corr_radius_samp = int(round(cfg.ALIGN_FOCUS / cfg.SPATIAL_RES))
        max_lag_samples = int(round(cfg.ALIGN_MAX_LAG / cfg.SPATIAL_RES))

        for i in valid_indices:
            if filled >= cfg.MAX_TOTAL_RUNS:
                break

            curr_run_name = str(run_info_list[i]["RunName"])

            # Already in history from Phase B? Copy directly (lines 644-647).
            if curr_run_name in existing_runs:
                match = next((h for h in old_history if str(h["RunName"]) == curr_run_name), None)
                if match is not None:
                    new_history.append(match)
                    filled += 1
                continue

            # Non-triggered run: extract + micro-align (lines 649-773)
            try:
                ds = cached_data[i]
                if ds is None or not ds:
                    continue

                ext_signals = extract_at_position(ds, defect_pos, cfg, cfg.fmin, cfg.fmax)
                if ext_signals is None:
                    continue

                # Speed filter (lines 657-661)
                curr_speed = float(ext_signals.get("Speed", np.nan))
                target_speed = float(d_entry["Mode_Speed"])
                if (
                    math.isnan(curr_speed)
                    or curr_speed <= 0
                    or abs(curr_speed - target_speed) > cfg.SPEED_TOL
                ):
                    continue

                # Micro-align via Hilbert-envelope xcorr (lines 664-698)
                shift_m = 0.0
                if (
                    master_filt_c is not None
                    and m_ref_sensor
                    and "Filt" in ext_signals
                    and m_ref_sensor in ext_signals["Filt"]
                ):
                    curr_filt_c = np.asarray(ext_signals["Filt"][m_ref_sensor], dtype=float)

                    rel_m = np.asarray(master_data.get("RelativeAxis", []), dtype=float)
                    rel_c = np.asarray(ext_signals.get("RelativeAxis", []), dtype=float)

                    mast_zero_idx = int(np.argmin(np.abs(rel_m))) if len(rel_m) > 0 else 0
                    curr_zero_idx = int(np.argmin(np.abs(rel_c))) if len(rel_c) > 0 else 0

                    m_s = max(0, mast_zero_idx - corr_radius_samp)
                    m_e = min(len(master_filt_c) - 1, mast_zero_idx + corr_radius_samp)
                    c_s = max(0, curr_zero_idx - corr_radius_samp)
                    c_e = min(len(curr_filt_c) - 1, curr_zero_idx + corr_radius_samp)

                    master_focus = master_filt_c[m_s : m_e + 1]
                    curr_focus = curr_filt_c[c_s : c_e + 1]

                    min_focus_len = min(len(master_focus), len(curr_focus))
                    if min_focus_len > max_lag_samples * 2:
                        n_up = min_focus_len * cfg.UPSAMPLE_FACTOR
                        master_up = interpft(master_focus[:min_focus_len], n_up)
                        curr_up = interpft(curr_focus[:min_focus_len], n_up)
                        env_master = hilbert_envelope(master_up)
                        env_curr = hilbert_envelope(curr_up)
                        max_lag_up = max_lag_samples * cfg.UPSAMPLE_FACTOR
                        lag = xcorr_lag(env_master, env_curr, max_lag_up)
                        shift_m = (lag / cfg.UPSAMPLE_FACTOR) * cfg.SPATIAL_RES

                # Apply shift (lines 702-717)
                if shift_m != 0.0:
                    for sn in m_avail:
                        if "Filt" in ext_signals and sn in ext_signals["Filt"]:
                            v = ext_signals["Filt"][sn]
                            if isinstance(v, np.ndarray) and v.size > 1:
                                ext_signals["Filt"][sn] = shift_signal_frac(
                                    v, shift_m, cfg.SPATIAL_RES
                                )
                    if "Raw" in ext_signals:
                        for sn, v in ext_signals["Raw"].items():
                            if isinstance(v, np.ndarray) and v.size > 1:
                                ext_signals["Raw"][sn] = shift_signal_frac(
                                    v, shift_m, cfg.SPATIAL_RES
                                )

                # Final crop (lines 720-744)
                n_half = int(round(win_final / cfg.SPATIAL_RES))
                rel_ax = np.asarray(ext_signals.get("RelativeAxis", []), dtype=float)
                center_idx = _matlab_round(len(rel_ax) / 2) - 1   # MATLAB 1-based round(N/2) -> 0-based
                safe_start = max(0, center_idx - n_half)
                safe_end = min(len(rel_ax) - 1, center_idx + n_half)

                if "Filt" in ext_signals:
                    for sn, v in ext_signals["Filt"].items():
                        if isinstance(v, np.ndarray) and v.ndim == 1 and len(v) > 1:
                            ext_signals["Filt"][sn] = v[safe_start : safe_end + 1]
                if "Raw" in ext_signals:
                    for sn, v in ext_signals["Raw"].items():
                        if isinstance(v, np.ndarray) and v.ndim == 1 and len(v) > 1:
                            ext_signals["Raw"][sn] = v[safe_start : safe_end + 1]

                idx_vector = np.arange(safe_start, safe_end + 1) - center_idx
                ext_signals["RelativeAxis"] = idx_vector.astype(float) * cfg.SPATIAL_RES

                # Exact date (lines 746-752)
                exact_date = run_info_list[i]["Date"]
                ds_space = np.asarray(ds.get("space_neutral", []), dtype=float)
                if "time" in ds and len(ds["time"]) > 0 and len(ds_space) > 0:
                    time_arr_s = np.asarray(ds["time"], dtype=float)
                    # build offset in seconds from run_date
                    from datetime import timedelta
                    run_dt = run_info_list[i]["Date"]
                    closest_idx = int(np.argmin(np.abs(ds_space - defect_pos)))
                    if closest_idx < len(time_arr_s):
                        dt_secs = float(time_arr_s[closest_idx])
                        exact_date = run_dt  # keep datetime as-is (MATLAB: run_date + seconds)
                        # We don't have a datetime that supports adding seconds cleanly
                        # without knowing if time_arr is relative — use run_date.
                        try:
                            from datetime import timedelta as _td
                            exact_date = run_dt + _td(seconds=dt_secs)
                        except Exception:
                            exact_date = run_dt

                local_amp = peak_amp(ext_signals, win_final)

                new_history.append({
                    "Date": exact_date,
                    "Amp": local_amp,
                    "RunName": curr_run_name,
                    "Detected": False,
                    "GeoShift": float(shift_m),
                    "MacroShift": float(run_info_list[i]["GeoShift"]),
                    "OriginalPos": float(defect_pos),
                    "Data": ext_signals,
                })
                filled += 1
                added_no_trigger += 1

            except Exception:
                pass  # MATLAB: catch ME_fill — silently skip

        # Replace history (lines 777-778)
        d_entry["History"] = new_history
        d_entry["Num_Total_Runs"] = len(new_history)


# ---------------------------------------------------------------------------
# build_database_for_route  — PUBLIC API
# ---------------------------------------------------------------------------

def build_database_for_route(
    files: list[str],
    route_name: str,
    cfg,
    track_map,
    route_joints,
    route_joint_labels,
) -> list[dict]:
    """Build MASTER_DB for one route, replicating MATLAB lines 134-785.

    Parameters
    ----------
    files             : list of .mat file paths (strings).
    route_name        : route name string (for logging).
    cfg               : CFG dataclass instance.
    track_map         : infrastructure map (list of dicts or None).
    route_joints      : list/array of joint positions (metres) or None.
    route_joint_labels: list of joint labels or None.

    Returns
    -------
    MASTER_DB as list of dicts.
    """
    fmin: float = cfg.fmin
    fmax: float = cfg.fmax

    # =========================================================================
    # Phase A — per-file loop (MATLAB lines 149-333)
    # =========================================================================
    global_event_list: list[dict] = []

    # State for MASTER init
    reference_signal: np.ndarray | None = None
    master_orientation: str = ""
    crop_start: float = 0.0
    crop_end: float = 0.0

    # RunInfo records and CachedData
    run_info_list: list[dict] = []
    cached_data: list[dict | None] = []

    for i, f_path in enumerate(files):
        f_name = os.path.splitext(os.path.basename(f_path))[0]

        # Default RunInfo (line 171-176)
        run_info: dict = {
            "FilePath": f_path,
            "RunName": f_name,
            "Date": datetime.now(),
            "GeoShift": 0.0,
            "Valid": False,
        }
        cached_data.append(None)

        try:
            data_struct = load_section(f_path)
            run_date = parse_run_date(f_name, data_struct)
            run_info["Date"] = run_date

            if not data_struct:
                run_info_list.append(run_info)
                continue

            # --- Orientation (lines 187-203) ---
            curr_orientation = determine_orientation(data_struct)
            if cfg.ONLY_FORWARD and curr_orientation == "moving backward":
                run_info_list.append(run_info)
                continue

            # --- MASTER init or align_and_crop_run (lines 217-280) ---
            current_shift = 0.0

            if reference_signal is None:
                # This is the MASTER run
                sig_geo_res, _ = compute_geo_signal(data_struct, cfg)
                reference_signal = sig_geo_res
                master_orientation = curr_orientation

                space_raw = np.asarray(data_struct["space_neutral"], dtype=float)
                crop_start = float(np.min(space_raw))
                crop_end = float(np.max(space_raw))

                # Apply shift (0) to space axes and crop
                mask_keep = (space_raw >= crop_start) & (space_raw <= crop_end)
                if int(np.sum(mask_keep)) < 100:
                    # Reset master — degenerate file
                    reference_signal = None
                    run_info_list.append(run_info)
                    continue

                # Crop all numeric arrays of matching length (MATLAB lines 270-278)
                len_mask = len(mask_keep)
                for fname_k, val in list(data_struct.items()):
                    if isinstance(val, np.ndarray) and val.ndim == 1 and len(val) == len_mask:
                        data_struct[fname_k] = val[mask_keep]

                current_shift = 0.0
                run_info["GeoShift"] = 0.0
                run_info["Valid"] = True
                cached_data[-1] = data_struct

            else:
                # Subsequent run — macro-align and crop
                result = align_and_crop_run(
                    data_struct,
                    reference_signal,
                    master_orientation,
                    crop_start,
                    crop_end,
                    cfg,
                )
                if not result["valid"]:
                    run_info_list.append(run_info)
                    continue

                current_shift = float(result["shift"])
                data_struct = result["data"]
                run_info["GeoShift"] = current_shift
                run_info["Valid"] = True
                cached_data[-1] = data_struct

            # --- Defect detection (lines 283-287) ---
            if cfg.ONLY_JOINTS and route_joints is not None:
                file_events = extract_at_joints(
                    data_struct, list(route_joints), list(route_joint_labels or []),
                    cfg, fmin, fmax
                )
            else:
                file_events = analyze_and_extract(data_struct, cfg, fmin, fmax)

            # --- Accumulate Global_Event_List (lines 290-324) ---
            if file_events:
                space_neutral_arr = np.asarray(data_struct.get("space_neutral", []), dtype=float)
                time_array: np.ndarray | None = None
                if "time" in data_struct and len(data_struct["time"]) > 0:
                    try:
                        from datetime import timedelta
                        time_arr_s = np.asarray(data_struct["time"], dtype=float)
                        # Store raw time offsets; exact_date computed per-event below
                        time_array = time_arr_s
                    except Exception:
                        time_array = None

                for ev in file_events:
                    curr_pos = float(ev["Pos"])

                    # Exact date via nearest spatial sample (lines 301-305)
                    exact_date = run_date
                    if time_array is not None and len(space_neutral_arr) > 0:
                        closest_idx = int(np.argmin(np.abs(space_neutral_arr - curr_pos)))
                        if closest_idx < len(time_array):
                            try:
                                from datetime import timedelta
                                exact_date = run_date + timedelta(seconds=float(time_array[closest_idx]))
                            except Exception:
                                exact_date = run_date

                    # Infra match (lines 307-316)
                    infra_note = "Linea"
                    if cfg.ONLY_JOINTS:
                        label = ev.get("Label", "")
                        infra_note = f"Giunto {label}"
                    elif track_map is not None and len(track_map) > 0:
                        matches = []
                        for tm in track_map:
                            pk_start = float(tm.get("Pk_Inizio", tm.get("pk_inizio", 0)))
                            pk_end = float(tm.get("Pk_Fine", tm.get("pk_fine", 0)))
                            if (pk_start - cfg.INFRA_TOL) <= curr_pos <= (pk_end + cfg.INFRA_TOL):
                                tipo = str(tm.get("Tipo", tm.get("tipo", "")))
                                desc = str(tm.get("Descrizione", tm.get("descrizione", "")))
                                matches.append(f"{tipo}: {desc}")
                        if matches:
                            infra_note = " | ".join(matches)

                    global_event_list.append({
                        "Pos": curr_pos,
                        "Amp": float(ev["Amp"]),
                        "Date": exact_date,
                        "RunName": f_name,
                        "Signals": ev["Signals"],
                        "Infra_Match": infra_note,
                        "MacroShift": current_shift,
                    })

        except Exception as exc:
            # MATLAB: catch ME — print error and continue
            print(f"   ERRORE nel file {f_name}: {exc}")

        run_info_list.append(run_info)

    # =========================================================================
    # Phase B — clustering + micro-alignment (MATLAB lines 335-577)
    # =========================================================================
    master_db: list[dict] = []

    if not global_event_list:
        return master_db

    # Sort by Pos, assign ClusterIDs (lines 340-347)
    global_event_list.sort(key=lambda e: e["Pos"])
    positions = np.array([e["Pos"] for e in global_event_list], dtype=float)
    cluster_ids = assign_cluster_ids(positions, cfg.CROSS_TOL)

    unique_clusters = np.unique(cluster_ids)

    for k, cid in enumerate(unique_clusters):
        mask = cluster_ids == cid
        subset = [e for e, m in zip(global_event_list, mask) if m]

        entry = _build_cluster_entry(
            db_idx=k + 1,
            subset_rows=subset,
            cfg=cfg,
        )
        if entry is not None:
            master_db.append(entry)

    # =========================================================================
    # Phase C — second pass completion (MATLAB lines 579-782)
    # =========================================================================
    if not cfg.ONLY_JOINTS:
        _second_pass_complete(master_db, run_info_list, cached_data, cfg)

    return master_db
