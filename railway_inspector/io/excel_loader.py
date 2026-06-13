"""
excel_loader.py
---------------
Python port of three MATLAB functions from Database_Allineamento_nomax.m:

  * to_num            (lines 1387-1391)
  * load_infrastructure_map  (lines 1151-1166)
  * load_joints_map   (lines 1283-1313)

Column index conventions (all conversions from 1-based MATLAB to 0-based Python):
  load_infrastructure_map:
    p1          : MATLAB col 20 → pandas iloc col 19
    p2          : MATLAB col 21 → pandas iloc col 20
    desc col 1  : MATLAB col  1 → pandas iloc col  0
    desc col 13 : MATLAB col 13 → pandas iloc col 12
    data rows   : MATLAB row 3 onward → pandas iloc row 2 onward (header=None read)

  load_joints_map:
    header row  : MATLAB row 1 → pandas iloc row 0
    data rows   : MATLAB row 2 onward → pandas iloc row 1 onward
    columns found by substring match on lowercased, stripped header values.
"""

from __future__ import annotations

import math
from typing import Optional

import numpy as np
import pandas as pd


# ---------------------------------------------------------------------------
# to_num
# ---------------------------------------------------------------------------

def to_num(v) -> float:
    """Replicate MATLAB to_num (lines 1387-1391).

    numeric (int, float, np scalar) → float(v)
    str                             → float(v) if parseable, else NaN
    anything else                   → NaN
    """
    if isinstance(v, (int, float, np.number)):
        return float(v)
    if isinstance(v, (str, bytes)):
        s = v.decode() if isinstance(v, bytes) else v
        try:
            return float(s)
        except (ValueError, TypeError):
            return float("nan")
    return float("nan")


# ---------------------------------------------------------------------------
# load_infrastructure_map
# ---------------------------------------------------------------------------

_INFRA_COLS = ["Foglio", "Tipo", "Pk_Inizio", "Pk_Fine", "Descrizione"]
_INFRA_EMPTY = pd.DataFrame(columns=_INFRA_COLS)

# 0-based column indices (MATLAB 1-based → subtract 1)
_COL_P1   = 19   # MATLAB col 20
_COL_P2   = 20   # MATLAB col 21
_COL_D1   = 0    # MATLAB col  1
_COL_D13  = 12   # MATLAB col 13
_DATA_ROW = 2    # MATLAB row 3 onward (0-based)


def load_infrastructure_map(file: str, track_type: str) -> pd.DataFrame:
    """Replicate MATLAB load_infrastructure_map (lines 1151-1166).

    Parameters
    ----------
    file        : path to the Excel workbook
    track_type  : 'pari' or anything else (dispari)

    Returns
    -------
    DataFrame with columns: Foglio, Tipo, Pk_Inizio, Pk_Fine, Descrizione
    """
    if track_type.lower() == "pari":
        sheets = ["1 p", "1 dp"]
    else:
        sheets = ["1 d", "1 dd"]

    rows: list[dict] = []

    for sh in sheets:
        try:
            raw: pd.DataFrame = pd.read_excel(
                file, sheet_name=sh, header=None, dtype=object
            )
        except Exception:
            continue  # sheet missing or unreadable → continue (MATLAB catch/continue)

        for idx in range(_DATA_ROW, len(raw)):
            row = raw.iloc[idx]

            # Safely extract p1 and p2; the row may be shorter than expected
            p1 = row.iloc[_COL_P1] if len(row) > _COL_P1 else None
            p2 = row.iloc[_COL_P2] if len(row) > _COL_P2 else None

            # Both must be numeric and their sum > 0
            try:
                p1f = float(p1)
                p2f = float(p2)
            except (TypeError, ValueError):
                continue
            if math.isnan(p1f) or math.isnan(p2f):
                continue
            if (p1f + p2f) <= 0:
                continue

            d1  = "" if (len(row) <= _COL_D1  or _is_scalar_na(row.iloc[_COL_D1]))  else str(row.iloc[_COL_D1])
            d13 = "" if (len(row) <= _COL_D13 or _is_scalar_na(row.iloc[_COL_D13])) else str(row.iloc[_COL_D13])

            desc = (d1 + " " + d13).strip()

            rows.append(
                {
                    "Foglio": sh,
                    "Tipo": "Elemento",
                    "Pk_Inizio": p1f,
                    "Pk_Fine": p2f,
                    "Descrizione": desc,
                }
            )

    if not rows:
        return _INFRA_EMPTY.copy()

    return pd.DataFrame(rows, columns=_INFRA_COLS)


def _is_scalar_na(v) -> bool:
    """Return True if v is a scalar NA/None/NaN, False otherwise."""
    if v is None:
        return True
    try:
        return bool(pd.isna(v))
    except (TypeError, ValueError):
        return False


# ---------------------------------------------------------------------------
# load_joints_map
# ---------------------------------------------------------------------------

_JOINTS_COLS = ["Stations", "Position", "Joint", "Shared"]
_JOINTS_EMPTY = pd.DataFrame(columns=_JOINTS_COLS)


def load_joints_map(file: str, type_: str) -> pd.DataFrame:
    """Replicate MATLAB load_joints_map (lines 1283-1313).

    Parameters
    ----------
    file   : path to the Excel workbook
    type_  : filter string; only sheets whose names CONTAIN this string
             (case-insensitive) are processed.

    Returns
    -------
    DataFrame with columns: Stations, Position, Joint, Shared
    """
    try:
        xl = pd.ExcelFile(file)
        sheet_names: list[str] = xl.sheet_names
    except Exception:
        return _JOINTS_EMPTY.copy()

    rows: list[dict] = []
    filter_lower = type_.lower() if type_ else ""

    for sh in sheet_names:
        # MATLAB: if ~isempty(type) && ~contains(lower(sh), lower(type)), continue
        if filter_lower and filter_lower not in sh.lower():
            continue

        try:
            raw: pd.DataFrame = pd.read_excel(
                file, sheet_name=sh, header=None, dtype=object
            )
        except Exception:
            continue

        if len(raw) < 2:
            continue

        # Header is row 0 (MATLAB row 1); lowercase + strip each cell
        hdr = [
            str(v).strip().lower() if not _is_scalar_na(v) else ""
            for v in raw.iloc[0]
        ]

        # Find column indices by substring (MATLAB contains())
        c_sta = _find_col(hdr, "station")
        c_jnt = _find_col(hdr, "joint")
        c_shr = _find_col(hdr, "shared")
        c_pos = _find_col(hdr, "fixed")           # priority: 'fixed'
        if c_pos is None:
            c_pos = _find_col(hdr, "position")    # fallback: 'position'

        # Skip sheet if mandatory columns are absent
        if c_sta is None or c_pos is None:
            continue

        # Data rows start at index 1 (MATLAB row 2)
        for idx in range(1, len(raw)):
            data_row = raw.iloc[idx]

            pos_raw = data_row.iloc[c_pos] if c_pos < len(data_row) else None
            pos = to_num(pos_raw)
            if math.isnan(pos):
                continue

            sta = _cell_to_str(data_row, c_sta)
            jnt = _cell_to_str(data_row, c_jnt) if c_jnt is not None else ""
            shr = _cell_to_str(data_row, c_shr) if c_shr is not None else ""

            rows.append(
                {
                    "Stations": sta,
                    "Position": pos,
                    "Joint": jnt,
                    "Shared": shr,
                }
            )

    if not rows:
        return _JOINTS_EMPTY.copy()

    return pd.DataFrame(rows, columns=_JOINTS_COLS)


def _find_col(hdr: list[str], substring: str) -> Optional[int]:
    """Return the first column index whose header contains `substring`, or None."""
    for i, h in enumerate(hdr):
        if substring in h:
            return i
    return None


def _cell_to_str(row: pd.Series, col_idx: int) -> str:
    """Convert a cell to string; return '' for NA/None."""
    if col_idx >= len(row):
        return ""
    v = row.iloc[col_idx]
    if _is_scalar_na(v):
        return ""
    return str(v)
