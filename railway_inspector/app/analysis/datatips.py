"""Tooltip callback functions for interactive matplotlib plots (port of src_app/app.m:1377-8005)."""

import numpy as np
import matplotlib.dates as mdates

__all__ = ["custom_datatip_robust", "master_datatip_fcn", "classification_datatip"]


def custom_datatip_robust(src, event_obj):
    """Port of src_app/app.m:1377-1396 custom_datatip_robust.

    Returns a list of strings for the tooltip.
    event_obj must expose: .Position, .Target (with .Tag and .UserData),
    .DataIndex.
    """
    pos = event_obj.Position
    target = event_obj.Target

    # if ~isprop(target, 'Tag') || ~strcmp(target.Tag, 'DefectScatter')
    tag = getattr(target, "Tag", None)
    if tag is None or tag != "DefectScatter":
        return [
            "X: {:.2f}".format(pos[0]),
            "Y: {:.2f}".format(pos[1]),
        ]

    idx = event_obj.DataIndex  # 0-based in Python (MATLAB 1-based converted by caller)
    meta_list = getattr(target, "UserData", None)  # equivalent of get(target, 'UserData')

    # iscell(meta_list) && idx <= length(meta_list)
    # In Python: list and idx < len(meta_list)  (0-based: idx < len)
    if isinstance(meta_list, list) and idx < len(meta_list):
        pk_str = meta_list[idx]
    else:
        pk_str = "N/A"

    return [
        pk_str,
        "Ant: {:.2f}".format(pos[0]),
        "Pos: {:.2f}".format(pos[1]),
    ]


def _datenum_to_str(d_val, fmt):
    """Convert a matplotlib datenum (float) to a formatted string.

    matplotlib.dates.num2date returns a datetime; strftime is used for formatting.
    fmt uses Python strftime codes.
    """
    dt = mdates.num2date(d_val)
    return dt.strftime(fmt)


def master_datatip_fcn(src, event_obj):
    """Port of src_app/app.m:4517-4600 master_datatip_fcn.

    Returns a list of strings for the tooltip.
    event_obj must expose: .Position, .Target (with .UserData, .axes),
    .Target.axes.get_xlabel().
    """
    pos = event_obj.Position
    target = event_obj.Target

    # --- 1. Controllo PSD 2D ---
    # info = get(target, 'UserData')
    info = getattr(target, "UserData", None)

    # isstruct(info) && isfield(info, 'Type') && isfield(info, 'Date')
    if (
        isinstance(info, dict)
        and "Type" in info
        and "Date" in info
    ):
        d_str = _datenum_to_str(info["Date"], "%d/%m/%Y %H:%M")
        type_str = info["Type"]

        # lambda = 0; if pos(1) > 0, lambda = 1/pos(1); end
        if pos[0] > 0:
            lam = 1.0 / pos[0]
        else:
            lam = 0.0

        return [
            "Run: {}".format(type_str),
            "Data: {}".format(d_str),
            "Freq: {:.2f} cicli/m".format(pos[0]),
            "Lambda: {:.2f} m".format(lam),
            "Amp: {:.1f}".format(pos[1]),
        ]

    # --- 2. Controllo GRAFICI 3D ---
    # if length(pos) == 3
    if len(pos) == 3:
        d_val = pos[1]  # pos(2) in MATLAB → index 1 in Python

        # if abs(d_val - floor(d_val)) < 1e-4
        if abs(d_val - np.floor(d_val)) < 1e-4:
            date_str = _datenum_to_str(d_val, "%d/%m/%y")
        else:
            date_str = _datenum_to_str(d_val, "%d/%m/%y %H:%M")

        # xlab = get(ax.XLabel, 'String')
        ax = target.axes
        xlab = ax.get_xlabel()

        if "frequenza" in xlab.lower() or "freq" in xlab.lower():
            # Grafico PSD 3D
            return [
                "Data: {}".format(date_str),
                "Freq: {:.2f} cicli/m".format(pos[0]),
                "L. d'onda: {:.2f} m".format(1.0 / pos[0]),
                "Power: {:.1f}".format(pos[2]),
            ]
        else:
            # Grafico Statistiche & Profilo 3D (Posizione)
            return [
                "Data: {}".format(date_str),
                "Pos: {:.2f} m".format(pos[0]),
                "RMS Medio: {:.2f} m/s^2".format(pos[2]),
            ]

    # --- 3. Controllo GRAFICI 2D Temporali o Matrice 3x3 ---
    # if length(pos) == 2
    if len(pos) == 2:
        # if pos(1) > 700000  (datenum threshold)
        if pos[0] > 700000:
            return [
                "Data: {}".format(_datenum_to_str(pos[0], "%d/%m/%y")),
                "Valore: {:.2f}".format(pos[1]),
            ]
        else:
            # Matrice 3x3 evolutiva fallback
            return [
                "Ratio Lat (X): {:.2f}".format(pos[0]),
                "Ratio Long (Y): {:.2f}".format(pos[1]),
            ]

    # Implicit return None if pos has unexpected length (mirrors MATLAB implicit no-return)
    return None


def classification_datatip(event_obj, SummaryData, tipi):
    """Port of src_app/app.m:7969-8005 classification_datatip.

    Parameters
    ----------
    event_obj   : object exposing .Position, .DataIndex, .Target
    SummaryData : list of objects/dicts with fields
                  ID, TipoStrutturale, Amp, Lambda_SX, NaturaSpettrale_SX,
                  Lambda_DX, NaturaSpettrale_DX, Ratio_SX_DX, Ratio_Lat_Vert
    tipi        : array-like of type-name strings (parallel to SummaryData groups)

    Returns a list of strings for the tooltip.
    """
    pos = event_obj.Position
    idx = event_obj.DataIndex  # 0-based

    try:
        tipo_name = getattr(event_obj.Target, "DisplayName", None)

        # mask = find(tipi == tipo_name)  → indices where tipi matches
        tipi_arr = np.asarray(tipi)
        mask = np.where(tipi_arr == tipo_name)[0]  # 0-based indices

        if len(mask) > 0 and idx < len(mask):
            real_idx = int(mask[idx])
        else:
            # Fallback: nearest neighbour in (Lambda_SX, Lambda_DX) space
            # Support both dicts and objects with attributes
            lambdas_sx = np.array(
                [s.get("Lambda_SX") if isinstance(s, dict) else s.Lambda_SX for s in SummaryData],
                dtype=float,
            )
            lambdas_dx = np.array(
                [s.get("Lambda_DX") if isinstance(s, dict) else s.Lambda_DX for s in SummaryData],
                dtype=float,
            )

            # Normalizza rispetto al range (+ eps MATLAB: 2.22e-16)
            eps = np.finfo(float).eps
            dx = (lambdas_sx - pos[0]) / (
                np.max(lambdas_sx) - np.min(lambdas_sx) + eps
            )
            dy = (lambdas_dx - pos[1]) / (
                np.max(lambdas_dx) - np.min(lambdas_dx) + eps
            )
            real_idx = int(np.argmin(dx**2 + dy**2))

        s = SummaryData[real_idx]
        # Support both dicts and objects with attributes
        if isinstance(s, dict):
            return [
                "PK: {} km".format(s["ID"]),
                "Tipo: {}".format(s["TipoStrutturale"]),
                "Amp: {:.1f} m/s²".format(s["Amp"]),
                "λ SX: {:.2f} m → {}".format(s["Lambda_SX"], s["NaturaSpettrale_SX"]),
                "λ DX: {:.2f} m → {}".format(s["Lambda_DX"], s["NaturaSpettrale_DX"]),
                "R SX/DX: {:.2f}  |  R Lat/Vert: {:.2f}".format(
                    s["Ratio_SX_DX"], s["Ratio_Lat_Vert"]
                ),
            ]
        else:
            return [
                "PK: {} km".format(s.ID),
                "Tipo: {}".format(s.TipoStrutturale),
                "Amp: {:.1f} m/s²".format(s.Amp),
                "λ SX: {:.2f} m → {}".format(s.Lambda_SX, s.NaturaSpettrale_SX),
                "λ DX: {:.2f} m → {}".format(s.Lambda_DX, s.NaturaSpettrale_DX),
                "R SX/DX: {:.2f}  |  R Lat/Vert: {:.2f}".format(
                    s.Ratio_SX_DX, s.Ratio_Lat_Vert
                ),
            ]

    except Exception:
        return [
            "X: {:.2f}".format(pos[0]),
            "Y: {:.2f}".format(pos[1]),
        ]
