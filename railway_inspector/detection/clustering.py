"""
detection/clustering.py
=======================
Faithful Python replication of the clustering and mode-speed filter logic
from src_database/Database_Allineamento_nomax.m, lines 339-377.

Math is identical to MATLAB.

Public API
----------
assign_cluster_ids(pos_sorted, cross_tol) -> np.ndarray
    Assign 1-based integer cluster IDs to an already-sorted position array.
    A new cluster starts whenever the gap between consecutive positions
    exceeds *cross_tol* (strict >), replicating MATLAB lines 343-347.

filter_by_mode_speed(speeds, speed_tol, only_joints) -> (keep_mask, mode_speed)
    Compute the mode speed and an optional keep-mask, replicating MATLAB
    lines 360-373.
    - valid_speeds = speeds[~isnan & >0]
    - mode_speed   = NaN if valid_speeds empty, else mode(round(valid_speeds))
      with MATLAB tie-break (smallest most-frequent value).
    - keep_mask:
        * empty valid_speeds → all True  (MATLAB skips the inner block)
        * only_joints=True  → all True   (MATLAB skips the filter branch)
        * otherwise         → ~isnan(speeds) & |speeds - mode_speed| <= speed_tol
"""

from __future__ import annotations

import numpy as np


# ---------------------------------------------------------------------------
# assign_cluster_ids
# ---------------------------------------------------------------------------

def assign_cluster_ids(pos_sorted: np.ndarray, cross_tol: float) -> np.ndarray:
    """Return a 1-based integer cluster-ID array (same length as *pos_sorted*).

    Replicates MATLAB lines 342-347::

        ClusterID(1) = 1; curr_id = 1;
        for j = 2:height(T)
            if (T.Pos(j) - T.Pos(j-1)) > CROSS_TOL, curr_id = curr_id + 1; end
            ClusterID(j) = curr_id;
        end

    Parameters
    ----------
    pos_sorted:
        1-D array of positions already sorted ascending.
    cross_tol:
        Gap threshold; a new cluster starts when the difference between
        consecutive positions is strictly greater than this value.
    """
    n = len(pos_sorted)
    cluster_ids = np.empty(n, dtype=np.int64)

    if n == 0:
        return cluster_ids

    curr_id = 1
    cluster_ids[0] = curr_id

    for j in range(1, n):
        if (pos_sorted[j] - pos_sorted[j - 1]) > cross_tol:
            curr_id += 1
        cluster_ids[j] = curr_id

    return cluster_ids


# ---------------------------------------------------------------------------
# _matlab_round  –  round-half-away-from-zero (MATLAB's round behavior)
# ---------------------------------------------------------------------------

def _matlab_round(x: np.ndarray | float) -> np.ndarray | float:
    """Round using MATLAB's round-half-away-from-zero rule.

    MATLAB's round(x) rounds 0.5 away from zero:
    - round(2.5) = 3
    - round(-2.5) = -3

    NumPy's np.round uses banker's rounding (round-half-to-even):
    - np.round(2.5) = 2
    - np.round(-2.5) = -2

    This function replicates MATLAB's behavior using:
    sign(x) * floor(abs(x) + 0.5)
    """
    x = np.asarray(x, dtype=float)
    return np.sign(x) * np.floor(np.abs(x) + 0.5)


# ---------------------------------------------------------------------------
# _matlab_mode  –  mode(round(x)) with MATLAB tie-break
# ---------------------------------------------------------------------------

def _matlab_mode(values: np.ndarray) -> float:
    """Return the statistical mode of *values* with MATLAB tie-breaking.

    MATLAB ``mode`` returns the **smallest** value among those that appear
    most frequently.  ``scipy.stats.mode`` (scipy >= 1.9) does the same
    by default when ``keepdims=False`` and values are integers, but we
    implement it directly to avoid the scipy dependency and any version
    ambiguity.

    *values* is expected to already be rounded integers (as floats).
    """
    if len(values) == 0:
        return np.nan

    # Count occurrences of each unique rounded value.
    unique_vals, counts = np.unique(values, return_counts=True)
    max_count = counts.max()
    # Among all values with the maximum count, return the smallest.
    candidates = unique_vals[counts == max_count]
    return float(candidates[0])  # np.unique returns sorted → candidates[0] is smallest


# ---------------------------------------------------------------------------
# filter_by_mode_speed
# ---------------------------------------------------------------------------

def filter_by_mode_speed(
    speeds: np.ndarray,
    speed_tol: float,
    only_joints: bool,
) -> tuple[np.ndarray, float]:
    """Compute mode speed and a boolean keep-mask for a cluster's speeds.

    Replicates MATLAB lines 360-373::

        valid_speeds = speeds(~isnan(speeds) & speeds > 0);
        mode_speed = NaN;
        if ~isempty(valid_speeds)
            mode_speed = mode(round(valid_speeds));
            if ~CFG.ONLY_JOINTS
                keep_mask = ~isnan(speeds) & (abs(speeds - mode_speed) <= CFG.SPEED_TOL);
                subset = subset(keep_mask, :);
            end
        end

    Parameters
    ----------
    speeds:
        1-D array of speed values (may contain NaN).
    speed_tol:
        Tolerance around the mode speed for the keep filter.
    only_joints:
        When True, the keep-mask is not applied (all elements kept).

    Returns
    -------
    keep_mask : np.ndarray[bool]
        Boolean mask, same length as *speeds*.
    mode_speed : float
        Mode of ``round(valid_speeds)``, or ``nan`` if no valid speeds.
    """
    speeds = np.asarray(speeds, dtype=float)
    n = len(speeds)

    # Default: keep everything (MATLAB behaviour when valid_speeds empty or only_joints)
    keep_mask = np.ones(n, dtype=bool)

    # valid_speeds = speeds(~isnan(speeds) & speeds > 0)
    valid_mask = ~np.isnan(speeds) & (speeds > 0)
    valid_speeds = speeds[valid_mask]

    mode_speed: float = np.nan

    if len(valid_speeds) > 0:
        # mode(round(valid_speeds)) – use MATLAB's round-half-away-from-zero
        rounded = _matlab_round(valid_speeds)
        mode_speed = _matlab_mode(rounded)

        if not only_joints:
            # keep_mask = ~isnan(speeds) & (abs(speeds - mode_speed) <= speed_tol)
            keep_mask = ~np.isnan(speeds) & (np.abs(speeds - mode_speed) <= speed_tol)

    return keep_mask, mode_speed
