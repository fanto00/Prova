"""Load infrastructure and joints data from Excel files (port of src_app/app.m:1938-1965, 9126-9173)."""
from __future__ import annotations

import os

import numpy as np
import pandas as pd

__all__ = ["load_infrastructure_map", "load_joints_map"]


# ---------------------------------------------------------------------------
# Internal helper
# ---------------------------------------------------------------------------

def _helper_clean_val(row: list, idx: int) -> float:
    """Return numeric value at 0-based column idx, or 0 if missing/string/non-numeric.

    Port of app.m:1961-1965 helper_clean_val.
    MATLAB idx is 1-based; callers already pass the 0-based equivalent.
    """
    if idx >= len(row):
        return 0.0
    val = row[idx]
    # pandas may give NaN, None, str, or a numeric type
    if val is None:
        return 0.0
    if isinstance(val, float) and np.isnan(val):
        return 0.0
    if isinstance(val, (str, bytes)):
        return 0.0
    try:
        fval = float(val)
    except (TypeError, ValueError):
        return 0.0
    if np.isnan(fval):
        return 0.0
    return fval


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def load_infrastructure_map(filename: str, track_type: str) -> pd.DataFrame:
    """Load switch (Deviatoio) and transition curve (Raccordo) rows from Excel.

    Port of app.m:1938-1960.

    Parameters
    ----------
    filename:
        Path to the Excel workbook.
    track_type:
        ``'pari'`` selects sheets ``['1 p', '1 dp']``;
        any other value selects ``['1 d', '1 dd']``.
    """
    if track_type.lower() == "pari":
        sheets = ["1 p", "1 dp"]
    else:
        sheets = ["1 d", "1 dd"]

    # MATLAB 1-based column indices → Python 0-based
    idx_descA    = 0   # col 1
    idx_descM    = 12  # col 13
    idx_L_Dev    = 11  # col 12  (read but not used downstream — kept for parity)
    idx_L1       = 15  # col 16
    idx_L2       = 17  # col 18
    idx_Pk_Start = 19  # col 20
    idx_Pk_End   = 20  # col 21

    dati_binario = pd.DataFrame(
        columns=["Foglio", "Tipo", "Pk_Inizio", "Pk_Fine", "Descrizione"]
    )

    if not os.path.isfile(filename):
        return dati_binario

    new_rows: list[dict] = []

    for sheet_name in sheets:
        try:
            # header=None: read every row as raw data (mirrors MATLAB readcell)
            raw_df = pd.read_excel(
                filename, sheet_name=sheet_name, header=None, dtype=object
            )
        except Exception:
            continue

        raw_data = raw_df.values.tolist()   # list of lists (0-based rows)
        num_rows = len(raw_data)

        # MATLAB loop: for i = 3:num_rows  (1-based, so rows index 2..num_rows-1 in 0-based)
        for i in range(2, num_rows):
            row = raw_data[i]

            # MATLAB: if size(row,2) < idx_Pk_End  →  need at least idx_Pk_End+1 columns
            if len(row) < idx_Pk_End + 1:
                continue

            pk_start = _helper_clean_val(row, idx_Pk_Start)
            pk_end   = _helper_clean_val(row, idx_Pk_End)
            if pk_start == 0 and pk_end == 0:
                continue

            # desc_A: MATLAB string(row{idx_descA}), ismissing → ""
            raw_descA = row[idx_descA]
            desc_A = "" if (raw_descA is None or (isinstance(raw_descA, float) and np.isnan(raw_descA))) else str(raw_descA)

            # desc_M: same pattern
            raw_descM = row[idx_descM]
            desc_M = "" if (raw_descM is None or (isinstance(raw_descM, float) and np.isnan(raw_descM))) else str(raw_descM)

            # --- Deviatoio branch ---
            if "dev" in desc_A.lower() or "dev" in desc_M.lower():
                new_rows.append({
                    "Foglio":      sheet_name,
                    "Tipo":        "Deviatoio",
                    "Pk_Inizio":   pk_start,
                    "Pk_Fine":     pk_end,
                    "Descrizione": desc_A + " " + desc_M,
                })

            # --- Raccordo branch ---
            if "destra" in desc_M.lower() or "sinistra" in desc_M.lower():
                # Raccordo Ingresso
                l1 = _helper_clean_val(row, idx_L1)
                if l1 == 0 and i > 0:                      # MATLAB: i>1 (1-based) → i>0 (0-based, because loop starts at 2)
                    l1 = _helper_clean_val(raw_data[i - 1], idx_L1)
                if l1 > 0:
                    new_rows.append({
                        "Foglio":      sheet_name,
                        "Tipo":        "Raccordo Ingresso",
                        "Pk_Inizio":   pk_start,
                        "Pk_Fine":     pk_start + l1,
                        "Descrizione": "Racc. Ing " + desc_M,
                    })

                # Raccordo Uscita
                l2 = _helper_clean_val(row, idx_L2)
                if l2 == 0 and i < num_rows - 1:           # MATLAB: i<num_rows (1-based) → i<num_rows-1 (0-based)
                    l2 = _helper_clean_val(raw_data[i + 1], idx_L2)
                if l2 > 0:
                    new_rows.append({
                        "Foglio":      sheet_name,
                        "Tipo":        "Raccordo Uscita",
                        "Pk_Inizio":   pk_end - l2,
                        "Pk_Fine":     pk_end,
                        "Descrizione": "Racc. Usc " + desc_M,
                    })

    if new_rows:
        dati_binario = pd.DataFrame(
            new_rows,
            columns=["Foglio", "Tipo", "Pk_Inizio", "Pk_Fine", "Descrizione"],
        )

    return dati_binario


def load_joints_map(filename: str, track_type: str) -> pd.DataFrame:
    """Load rail-joint positions from Excel.

    Port of app.m:9126-9173.

    Parameters
    ----------
    filename:
        Path to the Excel workbook.
    track_type:
        ``'pari'`` selects sheet ``'M2-Pari'``;
        any other value selects ``'M2-Dispari'``.
    """
    if track_type.lower() == "pari":
        sheet_name = "M2-Pari"
    else:
        sheet_name = "M2-Dispari"

    if not os.path.isfile(filename):
        print(f"[!] File Giunti non trovato: {filename}")
        return pd.DataFrame(columns=["Stations", "Position", "Joint"])

    try:
        raw_df = pd.read_excel(
            filename, sheet_name=sheet_name, header=None, dtype=object
        )
        raw = raw_df.values.tolist()

        # MATLAB: data = raw(2:end, :)  →  skip first row (header)
        data = raw[1:]
        n = len(data)

        # MATLAB columns (1-based):  col 1 → staz, col 2 → pos_raw, col 3 → nomi
        # Python 0-based:            col 0 → staz, col 1 → pos_raw, col 2 → nomi
        pos_raw = [row[1] if len(row) > 1 else None for row in data]
        nomi    = [row[2] if len(row) > 2 else None for row in data]
        staz    = [row[0] if len(row) > 0 else None for row in data]

        pos_num = np.full(n, np.nan)
        for i in range(n):
            v = pos_raw[i]
            if isinstance(v, (int, float)) and not (isinstance(v, float) and np.isnan(v)):
                # isnumeric(v) && isscalar(v)
                pos_num[i] = float(v)
            else:
                # testo: gestisce sia il punto che la virgola decimale
                s = str(v).strip().replace(",", ".")
                pos_num[i] = float(s) if s not in ("", "nan", "None") else np.nan
                # str2double returns NaN for unconvertible strings — np.nan matches

        # Round to nearest meter
        pos_num = np.round(pos_num)

        valid = ~np.isnan(pos_num)

        joints_table = pd.DataFrame({
            "Stations": [str(staz[i]) for i in range(n) if valid[i]],
            "Position": pos_num[valid].astype(float),
            "Joint":    [str(nomi[i]) for i in range(n) if valid[i]],
        })

        print(f"[OK] Caricati {len(joints_table)} giunti dal foglio {sheet_name}")
        return joints_table

    except Exception as exc:
        print(f"[!] Errore lettura Excel Giunti: {exc}")
        return pd.DataFrame(columns=["Stations", "Position", "Joint"])
