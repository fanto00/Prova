import datetime as dt
import numpy as np
import pytest
from railway_inspector.app.utils.filters import filter_defect_by_dates, filter_db_by_dates


def _run(day, amp, detected=True):
    return {"Date": dt.datetime(2026, 1, day, 12, 0), "Amp": amp, "Detected": detected}


def _defect():
    return {
        "History": [_run(1, 10.0), _run(5, 30.0), _run(9, 20.0)],
        "Num_Occurrences": 3,
        "Num_Total_Runs": 3,
        "Max_Severity": 30.0,
    }


# Task 7: filter_defect_by_dates tests


def test_filter_defect_none_d1_returns_unchanged():
    d = _defect()
    out = filter_defect_by_dates(d, None, None)
    assert len(out["History"]) == 3


def test_filter_defect_does_not_mutate_input():
    d = _defect()
    filter_defect_by_dates(d, dt.datetime(2026, 1, 4), dt.datetime(2026, 1, 6))
    assert len(d["History"]) == 3  # original untouched


def test_filter_defect_window_recomputes_aggregates():
    d = _defect()
    out = filter_defect_by_dates(d, dt.datetime(2026, 1, 4), dt.datetime(2026, 1, 6))
    assert len(out["History"]) == 1
    assert out["Num_Total_Runs"] == 1
    assert out["Num_Occurrences"] == 1
    assert out["Max_Severity"] == 30.0


def test_filter_defect_swaps_reversed_dates():
    d = _defect()
    out = filter_defect_by_dates(d, dt.datetime(2026, 1, 6), dt.datetime(2026, 1, 4))
    assert len(out["History"]) == 1


def test_filter_defect_d2_none_uses_single_day():
    d = _defect()
    out = filter_defect_by_dates(d, dt.datetime(2026, 1, 5), None)
    assert len(out["History"]) == 1
    assert out["History"][0]["Amp"] == 30.0


def test_filter_defect_empty_window_zeroes_aggregates():
    d = _defect()
    out = filter_defect_by_dates(d, dt.datetime(2026, 2, 1), dt.datetime(2026, 2, 2))
    assert out["History"] == []
    assert out["Num_Occurrences"] == 0
    assert out["Num_Total_Runs"] == 0
    assert out["Max_Severity"] == 0


def test_filter_defect_occurrences_sum_detected():
    d = _defect()
    d["History"][1]["Detected"] = False
    out = filter_defect_by_dates(d, dt.datetime(2026, 1, 1), dt.datetime(2026, 1, 9))
    assert out["Num_Total_Runs"] == 3
    assert out["Num_Occurrences"] == 2  # one Detected=False


# Task 8: filter_db_by_dates tests


def test_filter_db_none_d1_returns_input():
    db = [_defect()]
    out = filter_db_by_dates(db, None, None)
    assert out is db or out == db


def test_filter_db_drops_empty_defects():
    in_window = _defect()                      # has a run on Jan 5
    out_window = {"History": [_run(20, 5.0)],   # only Jan 20
                  "Num_Occurrences": 1, "Num_Total_Runs": 1, "Max_Severity": 5.0}
    db = [in_window, out_window]
    out = filter_db_by_dates(db, dt.datetime(2026, 1, 4), dt.datetime(2026, 1, 6))
    assert len(out) == 1
    assert out[0]["History"][0]["Amp"] == 30.0


def test_filter_db_does_not_mutate_input():
    db = [_defect()]
    filter_db_by_dates(db, dt.datetime(2026, 1, 4), dt.datetime(2026, 1, 6))
    assert len(db[0]["History"]) == 3
