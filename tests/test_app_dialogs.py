"""TDD tests for railway_inspector.app.ui.dialogs (6 tests)."""
from __future__ import annotations

from datetime import datetime, timedelta
import pytest

from railway_inspector.app.ui.dialogs import (
    filter_defect_by_dates,
    filter_db_by_dates,
)


# ---------------------------------------------------------------------------
# Test 1: filter_defect_by_dates filtra History per intervallo date
# ---------------------------------------------------------------------------
def test_filter_defect_by_dates_basic():
    """filter_defect_by_dates() ritaglia History a intervallo date."""
    d1 = datetime(2024, 1, 1)

    runs = [
        {"Date": d1, "Amp": 0.5, "Detected": True},
        {"Date": d1 + timedelta(days=1), "Amp": 0.6, "Detected": True},
        {"Date": d1 + timedelta(days=2), "Amp": 0.7, "Detected": False},
        {"Date": d1 + timedelta(days=3), "Amp": 0.8, "Detected": True},
        {"Date": d1 + timedelta(days=4), "Amp": 0.9, "Detected": False},
    ]
    defect = {
        "History": runs,
        "Num_Occurrences": 3,
        "Num_Total_Runs": 5,
        "Max_Severity": 0.9,
    }

    # Filter da giorno 2 a giorno 4 → 3 run
    date_from = d1 + timedelta(days=1)
    date_to = d1 + timedelta(days=3)
    filtered = filter_defect_by_dates(defect, date_from, date_to)

    assert len(filtered["History"]) == 3
    assert filtered["Num_Total_Runs"] == 3
    assert filtered["Num_Occurrences"] == 2  # sum([Hs.Detected]) = 2 True values in range
    assert filtered["Max_Severity"] == 0.8


# ---------------------------------------------------------------------------
# Test 2: filter_defect_by_dates con range vuoto
# ---------------------------------------------------------------------------
def test_filter_defect_by_dates_empty_range():
    """filter_defect_by_dates() con range vuoto → History empty."""
    d1 = datetime(2024, 1, 1)

    runs = [{"Date": d1, "Amp": 0.5, "Detected": True}]
    defect = {
        "History": runs,
        "Num_Occurrences": 1,
        "Num_Total_Runs": 1,
        "Max_Severity": 0.5,
    }

    # Filter range che non copre nessun run
    filtered = filter_defect_by_dates(
        defect,
        datetime(2024, 2, 1),
        datetime(2024, 2, 28),
    )

    assert len(filtered["History"]) == 0
    assert filtered["Num_Total_Runs"] == 0
    assert filtered["Max_Severity"] == 0


# ---------------------------------------------------------------------------
# Test 3: filter_defect_by_dates con d2 < d1 (swap)
# ---------------------------------------------------------------------------
def test_filter_defect_by_dates_auto_swap():
    """filter_defect_by_dates() con d2 < d1 deve swappare automaticamente."""
    d1 = datetime(2024, 1, 1)

    runs = [
        {"Date": d1, "Amp": 0.5, "Detected": True},
        {"Date": d1 + timedelta(days=1), "Amp": 0.6, "Detected": True},
        {"Date": d1 + timedelta(days=2), "Amp": 0.7, "Detected": False},
    ]
    defect = {
        "History": runs,
        "Num_Occurrences": 2,
        "Num_Total_Runs": 3,
        "Max_Severity": 0.7,
    }

    # Passa d2 < d1; funzione deve swappare
    date_to = d1
    date_from = d1 + timedelta(days=2)
    filtered = filter_defect_by_dates(defect, date_from, date_to)

    # Dovrebbe aver considerato [d1, d1+2d] come se fosse passato (d1, d1+2d)
    assert len(filtered["History"]) == 3
    assert filtered["Num_Total_Runs"] == 3


# ---------------------------------------------------------------------------
# Test 4: filter_db_by_dates scarta defect con History empty
# ---------------------------------------------------------------------------
def test_filter_db_by_dates_keeps_nonempty():
    """filter_db_by_dates() scarta defect con History empty dopo filter."""
    d1 = datetime(2024, 1, 1)

    db = [
        {
            "History": [{"Date": d1, "Amp": 0.5, "Detected": True}],
            "Num_Occurrences": 1,
            "Num_Total_Runs": 1,
            "Max_Severity": 0.5,
        },
        {
            "History": [{"Date": d1 + timedelta(days=30), "Amp": 0.6, "Detected": True}],
            "Num_Occurrences": 1,
            "Num_Total_Runs": 1,
            "Max_Severity": 0.6,
        },
    ]

    # Filter solo primo gennaio → solo primo defect rimane
    filtered_db = filter_db_by_dates(db, d1, d1)

    assert len(filtered_db) == 1
    assert len(filtered_db[0]["History"]) == 1
    assert filtered_db[0]["Max_Severity"] == 0.5


# ---------------------------------------------------------------------------
# Test 5: filter_defect_by_dates con d1=None (no filter)
# ---------------------------------------------------------------------------
def test_filter_defect_by_dates_none_date():
    """filter_defect_by_dates() con d1=None deve restituire defect intatto."""
    runs = [
        {"Date": datetime(2024, 1, 1), "Amp": 0.5, "Detected": True},
        {"Date": datetime(2024, 1, 2), "Amp": 0.6, "Detected": False},
    ]
    defect = {
        "History": runs,
        "Num_Occurrences": 1,
        "Num_Total_Runs": 2,
        "Max_Severity": 0.6,
    }

    filtered = filter_defect_by_dates(defect, None, None)

    # Nessun filter applicato
    assert len(filtered["History"]) == 2
    assert filtered["Num_Total_Runs"] == 2


# ---------------------------------------------------------------------------
# Test 6: filter_defect_by_dates senza campo Detected (edge case)
# ---------------------------------------------------------------------------
def test_filter_defect_by_dates_no_detected_field():
    """filter_defect_by_dates() con History senza Detected field."""
    d1 = datetime(2024, 1, 1)

    # Run senza "Detected" field
    runs = [
        {"Date": d1, "Amp": 0.5},
        {"Date": d1 + timedelta(days=1), "Amp": 0.6},
    ]
    defect = {
        "History": runs,
        "Num_Occurrences": 2,  # fallback: count tutti gli elementi
        "Num_Total_Runs": 2,
        "Max_Severity": 0.6,
    }

    filtered = filter_defect_by_dates(defect, d1, d1 + timedelta(days=1))

    assert len(filtered["History"]) == 2
    assert filtered["Num_Total_Runs"] == 2
    # Num_Occurrences rimane invariato perché nessun "Detected" field
    assert filtered["Num_Occurrences"] == 2
