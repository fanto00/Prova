"""
Geometric macro-alignment and crop pipeline for per-run processing.

Faithfully replicates Database_Allineamento_nomax.m lines 181-280.

Functions
---------
determine_orientation(data) -> str
    Determine the orientation string from a run data dict.

compute_geo_signal(data, cfg) -> (sig_geo_res, common_axis_ext)
    Build the z-score-normalised geometric reference signal on a
    common extended axis (MATLAB lines 205-215).

align_and_crop_run(data, reference, master_orientation, crop_start, crop_end, cfg) -> dict
    Compute xcorr-based shift, apply sanity checks, shift space axes,
    crop all numeric arrays of matching length, and return result dict.
    Caller is responsible for MASTER initialisation (first valid run).
"""

from __future__ import annotations

import copy

import numpy as np

from railway_inspector.signal.alignment import xcorr_lag
from railway_inspector.signal.resampling import interp1_zero


# ---------------------------------------------------------------------------
# determine_orientation
# ---------------------------------------------------------------------------

def determine_orientation(data: dict) -> str:
    """Determine the orientation string from a run data dict.

    Replicates MATLAB lines 187-196::

        curr_orientation = ""
        if isfield(data_struct, 'orientation')
            curr_orientation = strtrim(string(data_struct.orientation));
        elseif isfield(data_struct, 'space_parameters') && ...
               isfield(data_struct.space_parameters, 'front')
            if data_struct.space_parameters.front < 0
                curr_orientation = "moving backward";
            else
                curr_orientation = "moving forward";
            end
        end

    Parameters
    ----------
    data : dict
        Run data dictionary.

    Returns
    -------
    orientation : str
        One of ``"moving forward"``, ``"moving backward"``, or ``""``.
    """
    if "orientation" in data:
        return str(data["orientation"]).strip()

    if "space_parameters" in data:
        sp = data["space_parameters"]
        if isinstance(sp, dict) and "front" in sp:
            if sp["front"] < 0:
                return "moving backward"
            else:
                return "moving forward"

    return ""


# ---------------------------------------------------------------------------
# compute_geo_signal
# ---------------------------------------------------------------------------

def compute_geo_signal(
    data: dict,
    cfg,
) -> tuple[np.ndarray, np.ndarray]:
    """Build the z-score-normalised geometric signal on a common extended axis.

    Replicates MATLAB lines 205-215::

        if isfield(data_struct, 'curve')
            sig_geo = abs(double(data_struct.curve));
        else
            sig_geo = abs(double(data_struct.left_sensor_front));
        end
        sig_geo(isnan(sig_geo)) = 0;

        common_axis_ext = (min(space_raw)-150) : CFG.SPATIAL_RES : (max(space_raw)+150);
        [ax_u, idx_u] = unique(space_raw, 'stable');
        sig_geo_res = interp1(ax_u, sig_geo(idx_u), common_axis_ext, 'linear', 0);
        sig_geo_res = (sig_geo_res - mean(sig_geo_res)) / (std(sig_geo_res) + 1e-6);

    Notes
    -----
    * ``np.std(..., ddof=1)`` is used to match MATLAB's default N-1 normalisation.
    * The common axis extends ±150 m beyond the raw signal range (MATLAB ``-150``
      and ``+150``), stepped at ``SPATIAL_RES``.
    * ``unique`` with ``'stable'`` order → ``numpy.unique`` with ``return_index``
      and then sorting by index preserves the first-occurrence order.

    Parameters
    ----------
    data : dict
        Run data dict; must contain ``'space_neutral'`` and either ``'curve'``
        or ``'left_sensor_front'``.
    cfg : CFG
        Configuration object; must expose ``SPATIAL_RES``.

    Returns
    -------
    sig_geo_res : ndarray, shape (M,)
        Z-score-normalised, resampled geometric signal.
    common_axis_ext : ndarray, shape (M,)
        The common extended spatial axis used for resampling.
    """
    SPATIAL_RES: float = cfg.SPATIAL_RES

    space_raw = np.asarray(data["space_neutral"], dtype=float)

    # Select geo signal source (MATLAB lines 205-209)
    if "curve" in data:
        sig_geo = np.abs(np.asarray(data["curve"], dtype=float))
    else:
        sig_geo = np.abs(np.asarray(data["left_sensor_front"], dtype=float))

    # Replace NaN with 0 (MATLAB line 210)
    sig_geo = np.where(np.isnan(sig_geo), 0.0, sig_geo)

    # Common extended axis (MATLAB line 212)
    # np.arange replicates MATLAB's colon operator: start:step:stop (inclusive)
    common_axis_ext = np.arange(
        np.min(space_raw) - 150.0,
        np.max(space_raw) + 150.0 + SPATIAL_RES * 0.5,  # +0.5*step so stop is included
        SPATIAL_RES,
    )

    # unique(space_raw, 'stable'): keep first occurrence order
    # np.unique returns sorted unique values; we need stable-order instead.
    _, first_idx = np.unique(space_raw, return_index=True)
    # Sort the first-occurrence indices to preserve original order (stable)
    first_idx_sorted = np.sort(first_idx)
    ax_u = space_raw[first_idx_sorted]
    sig_geo_u = sig_geo[first_idx_sorted]

    # Interpolate onto common axis with zero fill outside (MATLAB line 214)
    sig_geo_res = interp1_zero(ax_u, sig_geo_u, common_axis_ext)

    # Z-score normalisation, ddof=1 to match MATLAB std (N-1) (MATLAB line 215)
    mu = np.mean(sig_geo_res)
    sigma = np.std(sig_geo_res, ddof=1)
    sig_geo_res = (sig_geo_res - mu) / (sigma + 1e-6)

    return sig_geo_res, common_axis_ext


# ---------------------------------------------------------------------------
# align_and_crop_run
# ---------------------------------------------------------------------------

def align_and_crop_run(
    data: dict,
    reference: np.ndarray,
    master_orientation: str,
    crop_start: float,
    crop_end: float,
    cfg,
) -> dict:
    """Compute xcorr-based macro shift, sanity-check, apply shift, crop, return.

    Replicates MATLAB lines 217-280 (the non-MASTER branch + crop block).

    The caller is responsible for detecting the MASTER run and providing
    ``reference``, ``master_orientation``, ``crop_start``, and ``crop_end``.
    This function assumes ``reference`` is not None/empty.

    Steps
    -----
    1. Determine orientation and compute geo signal.
    2. xcorr against ``reference`` over ``L_min`` samples with
       ``max_lag = round(150 / SPATIAL_RES)``.
       ``current_shift = lag * SPATIAL_RES`` (metres).
    3. Sanity checks (MATLAB lines 233-243):
       * ``same_dir AND |shift| > 50``  → SKIP (valid=False).
       * ``NOT same_dir AND |shift| < 50`` → SKIP (valid=False).
    4. Add shift to ``space_neutral``, ``space_front``, ``space_back`` (if
       present), and ``switch.location`` (if ``FILTER_SWITCHES`` and present).
    5. Build ``mask_keep`` from the shifted ``space_neutral``.
    6. If ``sum(mask_keep) < 100`` → SKIP (valid=False).
    7. Crop every top-level numeric array whose length equals
       ``len(mask_keep)`` to ``mask_keep`` (MATLAB lines 270-278).
    8. Return ``{'data': cropped_dict, 'shift': current_shift, 'valid': True}``.

    Parameters
    ----------
    data : dict
        Run data dict.  A shallow copy is made; the caller's dict is not mutated.
    reference : ndarray
        Master geo signal (already z-score normalised).
    master_orientation : str
        Orientation of the master run (``"moving forward"`` / ``"moving backward"``).
    crop_start : float
        Start of the crop window in metres (= ``min(space_raw)`` of master run).
    crop_end : float
        End of the crop window in metres (= ``max(space_raw)`` of master run).
    cfg : CFG
        Configuration; must expose ``SPATIAL_RES`` and ``FILTER_SWITCHES``.

    Returns
    -------
    result : dict with keys:
        ``'data'``  — cropped dict or ``None`` if invalid.
        ``'shift'`` — shift in metres (float); 0.0 if invalid.
        ``'valid'`` — bool.
    """
    SPATIAL_RES: float = cfg.SPATIAL_RES
    FILTER_SWITCHES: bool = cfg.FILTER_SWITCHES

    _INVALID = {"data": None, "shift": 0.0, "valid": False}

    # Work on a shallow copy; arrays will be replaced (not mutated) below
    data = dict(data)

    # --- Step 1: orientation + geo signal ---
    curr_orientation = determine_orientation(data)
    sig_geo_res, _ = compute_geo_signal(data, cfg)

    # --- Step 2: xcorr shift (MATLAB lines 226-230) ---
    reference = np.asarray(reference, dtype=float)
    max_lag = int(round(150.0 / SPATIAL_RES))
    L_min = min(len(reference), len(sig_geo_res))

    lag = xcorr_lag(reference[:L_min], sig_geo_res[:L_min], max_lag)
    current_shift: float = float(lag) * SPATIAL_RES

    # --- Step 3: sanity checks (MATLAB lines 233-243) ---
    same_dir: bool = (curr_orientation == master_orientation)
    if same_dir and abs(current_shift) > 50.0:
        return _INVALID
    if (not same_dir) and abs(current_shift) < 50.0:
        return _INVALID

    # --- Step 4: apply shift to space axes ---
    # space_neutral (always present)
    data["space_neutral"] = np.asarray(data["space_neutral"], dtype=float) + current_shift

    # space_front / space_back (optional, MATLAB lines 252-253)
    if "space_front" in data:
        data["space_front"] = np.asarray(data["space_front"], dtype=float) + current_shift
    if "space_back" in data:
        data["space_back"] = np.asarray(data["space_back"], dtype=float) + current_shift

    # switch.location (optional, MATLAB lines 255-257)
    if FILTER_SWITCHES and "switch" in data:
        sw = data["switch"]
        if isinstance(sw, dict) and "location" in sw:
            # Make a copy of the inner dict too so we don't mutate nested objects
            sw = dict(sw)
            sw["location"] = np.asarray(sw["location"], dtype=float) + current_shift
            data["switch"] = sw

    # --- Step 5: mask_keep (MATLAB lines 261-262) ---
    space_neutral_shifted = np.asarray(data["space_neutral"], dtype=float)
    mask_keep = (space_neutral_shifted >= crop_start) & (space_neutral_shifted <= crop_end)

    # --- Step 6: length check (MATLAB lines 264-268) ---
    if int(np.sum(mask_keep)) < 100:
        return _INVALID

    # --- Step 7: crop all top-level numeric arrays of matching length ---
    # Replicates MATLAB lines 270-278:
    #   fields = fieldnames(data_struct); len_mask = length(mask_keep);
    #   for fn = 1:length(fields)
    #       if isnumeric(val) && (length(val) == len_mask)
    #           data_struct.(fname) = val(mask_keep);
    len_mask = len(mask_keep)
    for fname, val in list(data.items()):
        if isinstance(val, np.ndarray) and val.ndim == 1 and len(val) == len_mask:
            data[fname] = val[mask_keep]

    return {"data": data, "shift": current_shift, "valid": True}
