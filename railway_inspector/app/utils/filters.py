"""Date-range filtering of Defect / DB structures (port of app.m:613-647)."""
from __future__ import annotations

import datetime as dt


def _as_day(x: dt.date) -> dt.date:
    """dateshift(x, 'start', 'day') -> the date part."""
    if isinstance(x, dt.datetime):
        return x.date()
    return x  # already a date


def filter_defect_by_dates(Defect: dict, d1: dt.date | None, d2: dt.date | None) -> dict:
    """Filter a defect's History to [d1, d2] (inclusive, day resolution) and
    recompute aggregates. Returns a shallow copy; input is not mutated."""
    Dsub = dict(Defect)
    if d1 is None:
        return Dsub
    if d2 is None:
        d2 = d1
    d1d, d2d = _as_day(d1), _as_day(d2)
    if d2d < d1d:
        d1d, d2d = d2d, d1d

    H = Defect.get("History", [])
    if not H:
        return Dsub

    Hs = [run for run in H if d1d <= _as_day(run["Date"]) <= d2d]
    Dsub["History"] = Hs

    if not Hs:
        if "Num_Occurrences" in Dsub:
            Dsub["Num_Occurrences"] = 0
        if "Num_Total_Runs" in Dsub:
            Dsub["Num_Total_Runs"] = 0
        if "Max_Severity" in Dsub:
            Dsub["Max_Severity"] = 0
        return Dsub

    if "Max_Severity" in Dsub:
        Dsub["Max_Severity"] = max(run["Amp"] for run in Hs)
    if "Num_Total_Runs" in Dsub:
        Dsub["Num_Total_Runs"] = len(Hs)
    if "Num_Occurrences" in Dsub:
        # MATLAB struct arrays are homogeneous, so isfield(Hs,'Detected') is true
        # iff every run has the field. `all(...)` mirrors that and is also the safe
        # choice (it guarantees the sum below never KeyErrors on a missing key).
        if all("Detected" in run for run in Hs):
            Dsub["Num_Occurrences"] = sum(bool(run["Detected"]) for run in Hs)
        else:
            Dsub["Num_Occurrences"] = len(Hs)
    return Dsub


def filter_db_by_dates(DB: list, d1: dt.date | None, d2: dt.date | None) -> list:
    """Apply filter_defect_by_dates to every defect, dropping those whose
    filtered History is empty (app.m:639). Input list is not mutated."""
    if d1 is None or not DB:
        return DB
    out = []
    for defect in DB:
        sub = filter_defect_by_dates(defect, d1, d2)
        if sub.get("History"):
            out.append(sub)
    return out
