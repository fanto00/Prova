"""
detection/extraction.py
=======================
Faithful Python replication of three MATLAB functions from
Database_Allineamento_nomax.m:

  analyze_and_extract     (lines 793-1001)
  extract_at_position     (lines 1012-1149)
  extract_at_joints       (lines 1252-1281)
  peak_amp                (lines 1227-1250)

Math is identical to MATLAB.  Filt/Raw arrays stored as float32 to mirror
MATLAB single().  Variable names kept close to MATLAB originals.

Public API
----------
peak_amp(sig, half_w) -> float
extract_at_position(data, target_pos, cfg, fmin, fmax) -> dict | None
analyze_and_extract(data, cfg, fmin, fmax) -> list[dict]
extract_at_joints(data, joint_pos, joint_labels, cfg, fmin, fmax) -> list[dict]
"""

from __future__ import annotations

import math
from typing import Optional

import numpy as np

from railway_inspector.signal.filtering import design_filters, filter_pipeline
from railway_inspector.signal.resampling import interp1_zero
from railway_inspector.detection.trigger import (
    detect_peaks_on_signal,
    merge_detections,
)


# ---------------------------------------------------------------------------
# Sensor name lists — identical to MATLAB
# ---------------------------------------------------------------------------

_AXIAL_NAMES: list[str] = [
    "left_sensor_front",
    "left_sensor_rear",
    "right_sensor_front",
    "right_sensor_rear",
]

_ALL_LATERAL_NAMES: list[str] = [
    "right_sensor_front_lat",
    "right_sensor_rear_lat",
    "left_sensor_front_lat",
    "left_sensor_rear_lat",
]

_FS_TIME: float = 1000.0  # MATLAB: fs_time = 1000


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _axis_front_rear(data: dict, space_raw: np.ndarray):
    """Return (axis_F, axis_R) replicating MATLAB lines 800-812 / 1024-1037."""
    if "space_front" in data and "space_back" in data:
        axis_F = np.asarray(data["space_front"], dtype=float)
        axis_R = np.asarray(data["space_back"],  dtype=float)
    elif "space_parameters" in data:
        pF = 0.0
        pR = 0.0
        sp = data["space_parameters"]
        if isinstance(sp, dict):
            if "front" in sp:
                pF = float(sp["front"])
            if "back" in sp:
                pR = float(sp["back"])
        axis_F = space_raw + pF
        axis_R = space_raw + pR
    else:
        axis_F = space_raw
        axis_R = space_raw
    return axis_F, axis_R


def _common_space_axis(space_raw: np.ndarray, spatial_res: float) -> np.ndarray:
    """Replicate MATLAB line 814:
        (ceil(min/RES) : floor(max/RES)) * RES
    """
    lo = math.ceil(float(space_raw.min()) / spatial_res)
    hi = math.floor(float(space_raw.max()) / spatial_res)
    return np.arange(lo, hi + 1) * spatial_res


def _filter_one_sensor(
    sig_raw: np.ndarray,
    cur_ax: np.ndarray,
    common_axis: np.ndarray,
    bT, aT, bQ, aQ,
) -> tuple[np.ndarray, np.ndarray]:
    """
    Return (raw_resampled, filt_resampled) for one sensor.

    Raw  = interp1_zero only (no filtering, DC preserved).
    Filt = demean → temporal filtfilt → spatial interp → spatial filtfilt.

    Replicates MATLAB lines 867-880 / 1081-1094.
    """
    from scipy.signal import filtfilt

    # unique-stable  (MATLAB: [ax_u, idx_u] = unique(cur_ax, 'stable'))
    _, idx_u = np.unique(cur_ax, return_index=True)
    idx_u = np.sort(idx_u)        # stable = ascending index order
    ax_u = cur_ax[idx_u]

    # --- RAW: spatial resampling only ---
    raw_res = interp1_zero(ax_u, sig_raw[idx_u], common_axis)

    # --- FILT pipeline ---
    sig_dem = sig_raw - np.nanmean(sig_raw)           # demean (omitnan)
    sig_t   = filtfilt(bT, aT, sig_dem)               # temporal bandpass
    sig_sp  = interp1_zero(ax_u, sig_t[idx_u], common_axis)  # resample
    sig_f   = filtfilt(bQ, aQ, sig_sp)                # spatial bandpass

    return raw_res, sig_f


def _speed_curve_from_raw(data: dict, space_raw: np.ndarray,
                           c_pos: float, win: float):
    """Extract mean speed and mean |curve| from raw window around c_pos."""
    idx_raw = (space_raw >= (c_pos - win)) & (space_raw <= (c_pos + win))

    if "speed_kmh" in data:
        speed_arr = np.asarray(data["speed_kmh"], dtype=float)
        speed = np.nanmean(speed_arr[idx_raw]) if np.any(idx_raw) else 0.0
    elif "speed" in data:
        speed_arr = np.asarray(data["speed"], dtype=float)
        speed = np.nanmean(speed_arr[idx_raw]) if np.any(idx_raw) else 0.0
    else:
        speed = 0.0

    if "curve" in data:
        curve_arr = np.asarray(data["curve"], dtype=float)
        curve = np.nanmean(np.abs(curve_arr[idx_raw])) if np.any(idx_raw) else 0.0
    else:
        curve = 0.0

    return np.float32(speed), np.float32(curve)


# ---------------------------------------------------------------------------
# peak_amp  (MATLAB lines 1227-1250)
# ---------------------------------------------------------------------------

def peak_amp(sig: dict, half_w: float) -> float:
    """Max |filtered| across all sensors within ±half_w of centre.

    Replicates MATLAB peak_amp (lines 1227-1250).

    Parameters
    ----------
    sig    : Signals dict with keys 'Filt' (dict) and optionally 'RelativeAxis'.
    half_w : half-window in metres.

    Returns
    -------
    float  : maximum absolute amplitude, 0.0 if nothing found.
    """
    a = 0.0

    # Guard: must have Filt
    if not isinstance(sig, dict) or "Filt" not in sig:
        return a

    filt = sig["Filt"]
    if not isinstance(filt, dict):
        return a

    # Build in_win mask (may be empty → use whole array)
    rel_axis = sig.get("RelativeAxis", None)
    if rel_axis is not None:
        rel_axis = np.asarray(rel_axis, dtype=float)
        if rel_axis.size > 0:
            in_win = np.abs(rel_axis) <= half_w
        else:
            in_win = None
    else:
        in_win = None   # fallback: whole window (MATLAB line 1235)

    for nm, v in filt.items():
        v = np.asarray(v, dtype=float)
        if v.ndim == 0 or v.size <= 1:
            # MATLAB: if numel(v) > 1  (scalar sentinels skipped)
            continue
        if in_win is not None:
            m = min(len(v), len(in_win))
            vv = v[in_win[:m]]
        else:
            vv = v
        if vv.size > 0:
            a = max(a, float(np.max(np.abs(vv))))

    return a


# ---------------------------------------------------------------------------
# extract_at_position  (MATLAB lines 1012-1149)
# ---------------------------------------------------------------------------

def extract_at_position(
    data: dict,
    target_pos: float,
    cfg,
    fmin: float,
    fmax: float,
) -> Optional[dict]:
    """Extract a signal window centred on target_pos.

    Replicates MATLAB extract_at_position (lines 1012-1149).
    Uses the pre-crop trick: slice raw signal to
    [target_pos ± (WINDOW_EXTRACT + FILTER_MARGIN)] before filtering.

    Returns
    -------
    dict with keys RelativeAxis, Speed, Curve, Filt[, Raw]  — or None.
    """
    space_raw = np.asarray(data["space_neutral"], dtype=float)

    # Coverage check (MATLAB lines 1019-1022)
    if (target_pos < space_raw.min() + cfg.WINDOW_EXTRACT or
            target_pos > space_raw.max() - cfg.WINDOW_EXTRACT):
        return None

    axis_F, axis_R = _axis_front_rear(data, space_raw)

    # --- PRE-CROP (MATLAB lines 1059-1067) ---
    wide_lo = target_pos - cfg.WINDOW_EXTRACT - cfg.FILTER_MARGIN
    wide_hi = target_pos + cfg.WINDOW_EXTRACT + cfg.FILTER_MARGIN
    idx_raw_wide = (space_raw >= wide_lo) & (space_raw <= wide_hi)

    if int(np.sum(idx_raw_wide)) < 100:
        return None

    space_raw_crop = space_raw[idx_raw_wide]
    axis_F_crop    = axis_F[idx_raw_wide]
    axis_R_crop    = axis_R[idx_raw_wide]

    # Common axis on the cropped section (MATLAB line 1070)
    common_axis_crop = _common_space_axis(space_raw_crop, cfg.SPATIAL_RES)

    # Which lateral sensors are present?
    lateral_present = [nm for nm in _ALL_LATERAL_NAMES if nm in data]
    tech_names = _AXIAL_NAMES + lateral_present

    # Design filters once (MATLAB lines 1073-1074)
    bT, aT, bQ, aQ = design_filters(cfg, _FS_TIME)

    Res_Sigs: dict[str, np.ndarray] = {}
    Raw_Sigs: dict[str, np.ndarray] = {}

    for nm in tech_names:
        sig_full = np.asarray(data[nm], dtype=float)
        sig_crop = sig_full[idx_raw_wide]

        # Choose front or rear axis (MATLAB: if contains(nm,'front'))
        cur_ax = axis_F_crop if "front" in nm else axis_R_crop

        raw_res, filt_res = _filter_one_sensor(
            sig_crop, cur_ax, common_axis_crop, bT, aT, bQ, aQ
        )
        Raw_Sigs[nm] = raw_res
        Res_Sigs[nm] = filt_res

    # --- Final extraction window (MATLAB lines 1098-1101) ---
    idx_win = (
        (common_axis_crop >= target_pos - cfg.WINDOW_EXTRACT) &
        (common_axis_crop <= target_pos + cfg.WINDOW_EXTRACT)
    )
    if int(np.sum(idx_win)) < 10:
        return None

    signals: dict = {}
    signals["RelativeAxis"] = (common_axis_crop[idx_win] - target_pos).astype(float)

    # Speed / Curve from narrow raw window (MATLAB lines 1106-1121)
    signals["Speed"], signals["Curve"] = _speed_curve_from_raw(
        data, space_raw, target_pos, cfg.WINDOW_EXTRACT
    )

    # Axial sensors (MATLAB lines 1124-1132)
    filt_dict: dict = {}
    raw_dict:  dict = {}

    for nm in _AXIAL_NAMES:
        if nm in Res_Sigs:
            filt_dict[nm] = Res_Sigs[nm][idx_win].astype(np.float32)
        if cfg.SAVE_RAW and nm in Raw_Sigs:
            raw_dict[nm] = Raw_Sigs[nm][idx_win].astype(np.float32)

    # Lateral sensors (MATLAB lines 1135-1148)
    for nm in _ALL_LATERAL_NAMES:
        if nm in Res_Sigs:
            filt_dict[nm] = Res_Sigs[nm][idx_win].astype(np.float32)
            if cfg.SAVE_RAW and nm in Raw_Sigs:
                raw_dict[nm] = Raw_Sigs[nm][idx_win].astype(np.float32)
        else:
            filt_dict[nm] = np.float32(0.0)   # single(0) sentinel
            if cfg.SAVE_RAW:
                raw_dict[nm] = np.float32(0.0)

    signals["Filt"] = filt_dict
    if cfg.SAVE_RAW:
        signals["Raw"] = raw_dict

    return signals


# ---------------------------------------------------------------------------
# analyze_and_extract  (MATLAB lines 793-1001)
# ---------------------------------------------------------------------------

def analyze_and_extract(
    data: dict,
    cfg,
    fmin: float,
    fmax: float,
) -> list[dict]:
    """Detect and extract all defect events in a run.

    Replicates MATLAB analyze_and_extract (lines 793-1001).

    Returns
    -------
    list of event dicts, each with keys Pos, Amp, Signals.
    """
    from scipy.signal import filtfilt  # noqa: F401 (used inside _filter_one_sensor)

    space_raw = np.asarray(data["space_neutral"], dtype=float)
    axis_F, axis_R = _axis_front_rear(data, space_raw)

    # Common spatial axis (MATLAB line 814)
    common_space_axis = _common_space_axis(space_raw, cfg.SPATIAL_RES)

    # Lateral sensors present in this run
    lateral_present = [nm for nm in _ALL_LATERAL_NAMES if nm in data]
    tech_names = _AXIAL_NAMES + lateral_present

    # Design filters once (MATLAB lines 855-856)
    bT, aT, bQ, aQ = design_filters(cfg, _FS_TIME)

    # --- Switch mask (MATLAB lines 838-851) ---
    switch_mask = np.zeros(len(common_space_axis), dtype=bool)
    if (cfg.FILTER_SWITCHES and
            "switch" in data and
            isinstance(data["switch"], dict) and
            "location" in data["switch"] and
            data["switch"]["location"] is not None):
        sw_loc = np.asarray(data["switch"]["location"], dtype=float).ravel()
        n_pairs = len(sw_loc) // 2
        for sp in range(n_pairs):
            lo = sw_loc[2 * sp]     - 1.0   # MATLAB: sw_loc(2*sp-1)-1  (1-based)
            hi = sw_loc[2 * sp + 1] + 1.0   # MATLAB: sw_loc(2*sp)+1
            switch_mask |= (common_space_axis >= lo) & (common_space_axis <= hi)

    keep_det  = ~switch_mask
    axis_det  = common_space_axis[keep_det]

    # --- Per-sensor processing (MATLAB lines 858-916) ---
    Res_Sigs: dict[str, np.ndarray] = {}
    Raw_Sigs: dict[str, np.ndarray] = {}
    # det_locs accumulates [position, amplitude] rows
    det_locs_list: list[np.ndarray] = []

    for nm in tech_names:
        sig_full = np.asarray(data[nm], dtype=float)
        L = min(len(sig_full), len(space_raw))
        sig_raw_s = sig_full[:L]

        cur_ax = (axis_F if "front" in nm else axis_R)[:L]

        raw_res, filt_res = _filter_one_sensor(
            sig_raw_s, cur_ax, common_space_axis, bT, aT, bQ, aQ
        )
        Raw_Sigs[nm] = raw_res
        Res_Sigs[nm] = filt_res

        # Detection on keep_det samples (MATLAB lines 883-916)
        sig_det = filt_res[keep_det]
        positions, amplitudes = detect_peaks_on_signal(sig_det, axis_det, cfg)

        if positions.size > 0:
            rows = np.column_stack([positions, amplitudes])
            det_locs_list.append(rows)

    if not det_locs_list:
        return []

    det_locs = np.vstack(det_locs_list)

    # --- Merging (MATLAB lines 921-934) ---
    merged = merge_detections(det_locs, cfg.CROSS_TOL)

    # --- Edge filter (MATLAB lines 936-942) ---
    if merged.size > 0:
        min_safe = common_space_axis.min() + cfg.WINDOW_EXTRACT
        max_safe = common_space_axis.max() - cfg.WINDOW_EXTRACT
        valid_mask = (merged[:, 0] >= min_safe) & (merged[:, 0] <= max_safe)
        merged = merged[valid_mask]

    if merged.size == 0:
        return []

    # --- Extraction (MATLAB lines 950-1000) ---
    events: list[dict] = []

    for k in range(len(merged)):
        c_pos = float(merged[k, 0])
        amp   = float(merged[k, 1])

        idx_win = (
            (common_space_axis >= c_pos - cfg.WINDOW_EXTRACT) &
            (common_space_axis <= c_pos + cfg.WINDOW_EXTRACT)
        )

        sig_out: dict = {}
        sig_out["RelativeAxis"] = (common_space_axis[idx_win] - c_pos).astype(float)

        # Speed / Curve from raw window (MATLAB lines 960-974)
        sig_out["Speed"], sig_out["Curve"] = _speed_curve_from_raw(
            data, space_raw, c_pos, cfg.WINDOW_EXTRACT
        )

        # Axial sensors (MATLAB lines 976-984)
        filt_dict: dict = {}
        raw_dict:  dict = {}

        for nm in _AXIAL_NAMES:
            if nm in Res_Sigs:
                filt_dict[nm] = Res_Sigs[nm][idx_win].astype(np.float32)
            if cfg.SAVE_RAW and nm in Raw_Sigs:
                raw_dict[nm] = Raw_Sigs[nm][idx_win].astype(np.float32)

        # Lateral sensors (MATLAB lines 986-999)
        for nm in _ALL_LATERAL_NAMES:
            if nm in Res_Sigs:
                filt_dict[nm] = Res_Sigs[nm][idx_win].astype(np.float32)
                if cfg.SAVE_RAW and nm in Raw_Sigs:
                    raw_dict[nm] = Raw_Sigs[nm][idx_win].astype(np.float32)
            else:
                filt_dict[nm] = np.float32(0.0)
                if cfg.SAVE_RAW:
                    raw_dict[nm] = np.float32(0.0)

        sig_out["Filt"] = filt_dict
        if cfg.SAVE_RAW:
            sig_out["Raw"] = raw_dict

        events.append({"Pos": c_pos, "Amp": amp, "Signals": sig_out})

    return events


# ---------------------------------------------------------------------------
# extract_at_joints  (MATLAB lines 1252-1281)
# ---------------------------------------------------------------------------

def extract_at_joints(
    data: dict,
    joint_pos: list[float],
    joint_labels: list,
    cfg,
    fmin: float,
    fmax: float,
) -> list[dict]:
    """Extract signal windows at known joint positions.

    Replicates MATLAB extract_at_joints (lines 1252-1281).

    Parameters
    ----------
    data         : run data dict
    joint_pos    : list of joint positions in metres
    joint_labels : list of labels (strings or any); length may differ from joint_pos
    cfg          : CFG config object
    fmin, fmax   : temporal bandpass bounds (Hz)

    Returns
    -------
    list of event dicts with keys Pos, Amp, Signals, Label.
    """
    if not joint_pos:
        return []

    # Wider config for extraction (MATLAB lines 1260-1261)
    import copy
    Cj = copy.copy(cfg)
    Cj.WINDOW_EXTRACT = cfg.JOINT_WINDOW + cfg.ALIGN_MAX_LAG + 1.0

    events: list[dict] = []

    for j, pos in enumerate(joint_pos):
        sig = extract_at_position(data, float(pos), Cj, fmin, fmax)
        if sig is None:
            continue  # joint outside coverage (MATLAB: if isempty(sig), continue)

        # Amplitude within ±JOINT_WINDOW (MATLAB line 1269)
        amp = peak_amp(sig, cfg.JOINT_WINDOW)

        # Label (MATLAB lines 1275-1278)
        if j < len(joint_labels):
            label = joint_labels[j]
        else:
            label = str(j)

        events.append({
            "Pos":     float(pos),
            "Amp":     amp,
            "Signals": sig,
            "Label":   label,
        })

    return events
