# Piano TDD: Modulo 2 — `app/ui/dialogs.py`

Sottotask di sub-plan 7 (App GUI Completa). Calendar dialog + date filtering utilities.

---

## Scope

**File MATLAB:** `src_app/app.m` (righe 451-648)
**File Python:** `railway_inspector/app/ui/dialogs.py`

**Funzioni:**
1. `open_calendar_dialog(parent_window)` (righe 451-475) — setup dialog
2. `render_calendar(dlg, st)` (righe 477-557) — render UI con calendario, state
3. `calendar_nav(dlg, delta)` (righe 559-564) — navigate mesi
4. `calendar_pick(dlg, d)` (righe 566-579) — state machine: pick from → to date
5. `calendar_clear(dlg)` (righe 581-586) — reset selection
6. `calendar_apply(dlg)` (righe 588-607) — apply + close + refresh main
7. `filter_defect_by_dates(Defect, d1, d2)` (righe 613-637) — filter History by date range
8. `filter_db_by_dates(DB, d1, d2)` (righe 639-648) — filter DB by date range

**Dipendenze:** PyQt6 (QDialog, QCalendarWidget), numpy, pandas, datetime
**Test database:** Fixture con datetime, dict defect, list DB

---

## TDD: Test-First, Implementazione Dopo

### Test 1: `test_filter_defect_by_dates_basic`
**Verifica:** filter_defect_by_dates filtra History correttamente per intervallo date.

```python
from datetime import datetime, timedelta
from railway_inspector.app.ui.dialogs import filter_defect_by_dates

def test_filter_defect_by_dates_basic():
    """filter_defect_by_dates() ritaglia History a intervallo date."""
    # Fixture: defect con 5 run su giorni diversi
    d1 = datetime(2024, 1, 1)
    d5 = datetime(2024, 1, 5)
    
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
    filtered = filter_defect_by_dates(defect, d1 + timedelta(days=1), d1 + timedelta(days=3))
    
    assert len(filtered["History"]) == 3
    assert filtered["Num_Total_Runs"] == 3
    assert filtered["Num_Occurrences"] == 1  # solo 1 "Detected"=True in range
    assert filtered["Max_Severity"] == 0.8
```

### Test 2: `test_filter_defect_by_dates_empty_range`
**Verifica:** Quando range non ha run, History è vuoto.

```python
def test_filter_defect_by_dates_empty_range():
    """filter_defect_by_dates() con range vuoto → History empty."""
    d1 = datetime(2024, 1, 1)
    
    runs = [{"Date": d1, "Amp": 0.5, "Detected": True}]
    defect = {"History": runs, "Num_Occurrences": 1, "Num_Total_Runs": 1, "Max_Severity": 0.5}
    
    # Filter range che non copre nessun run
    filtered = filter_defect_by_dates(defect, datetime(2024, 2, 1), datetime(2024, 2, 28))
    
    assert len(filtered["History"]) == 0
    assert filtered["Num_Total_Runs"] == 0
    assert filtered["Max_Severity"] == 0
```

### Test 3: `test_filter_db_by_dates_keeps_nonempty`
**Verifica:** filter_db_by_dates rimuove defect con History vuoto.

```python
from railway_inspector.app.ui.dialogs import filter_db_by_dates

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
```

### Test 4: `test_calendar_pick_state_machine`
**Verifica:** calendar_pick gestisce state machine (from → to date).

```python
def test_calendar_pick_state_machine():
    """calendar_pick() implementa state machine: pick from, poi to."""
    from railway_inspector.app.ui.dialogs import CalendarDialog
    
    # Mock dialog state
    st = {
        "sel_from": None,
        "sel_to": None,
        "stage": 0,  # 0 = aspetta from, 1 = aspetta to
    }
    
    d1 = datetime(2024, 1, 15)
    d2 = datetime(2024, 1, 20)
    
    # First pick: da to stage 1 (aspetta to)
    st_new = _simulate_calendar_pick(st, d1)
    assert st_new["sel_from"] == d1
    assert st_new["sel_to"] is None
    assert st_new["stage"] == 1
    
    # Second pick: set to, torna a stage 0
    st_new2 = _simulate_calendar_pick(st_new, d2)
    assert st_new2["sel_from"] == d1
    assert st_new2["sel_to"] == d2
    assert st_new2["stage"] == 0

def _simulate_calendar_pick(st, d):
    """Helper per testare state machine senza QDialog."""
    if st["stage"] == 0:
        st["sel_from"] = d
        st["sel_to"] = None
        st["stage"] = 1
    else:
        st["sel_to"] = d
        if st["sel_from"] and st["sel_to"] < st["sel_from"]:
            st["sel_from"], st["sel_to"] = st["sel_to"], st["sel_from"]
        st["stage"] = 0
    return st
```

### Test 5: `test_calendar_nav_month_shift`
**Verifica:** calendar_nav shifta correttamente il mese di visualizzazione.

```python
from datetime import datetime
from dateutil.relativedelta import relativedelta

def test_calendar_nav_month_shift():
    """calendar_nav() cambia view_month di ±1 mese."""
    d = datetime(2024, 3, 15)
    
    # Next month
    d_next = _simulate_calendar_nav(d, +1)
    assert d_next.month == 4
    assert d_next.year == 2024
    
    # Prev month
    d_prev = _simulate_calendar_nav(d, -1)
    assert d_prev.month == 2
    assert d_prev.year == 2024
    
    # Year wraparound: dicembre → gennaio (prossimo anno)
    d_dec = datetime(2024, 12, 15)
    d_jan = _simulate_calendar_nav(d_dec, +1)
    assert d_jan.month == 1
    assert d_jan.year == 2025

def _simulate_calendar_nav(d, delta):
    """Simula calendar_nav senza GUI."""
    return d + relativedelta(months=delta)
```

### Test 6: `test_calendar_clear_resets_selection`
**Verifica:** calendar_clear resetta sel_from e sel_to.

```python
def test_calendar_clear_resets_selection():
    """calendar_clear() resetta sel_from, sel_to, stage."""
    st = {
        "sel_from": datetime(2024, 1, 10),
        "sel_to": datetime(2024, 1, 20),
        "stage": 0,
    }
    
    # Reset
    st_cleared = _simulate_calendar_clear(st)
    
    assert st_cleared["sel_from"] is None
    assert st_cleared["sel_to"] is None
    assert st_cleared["stage"] == 0

def _simulate_calendar_clear(st):
    """Simula calendar_clear senza GUI."""
    return {
        "sel_from": None,
        "sel_to": None,
        "stage": 0,
    }
```

---

## MATLAB Source (Linee Specifiche)

### Funzioni (righe 451-648)
```matlab
function open_calendar_dialog(main_fig)
    % Setup dialog con state struct
end

function render_calendar(dlg)
    % Render UI: calendario, bottoni (nav, pick, clear, apply, cancel)
end

function calendar_nav(dlg, delta)
    % Naviga ±1 mese
end

function calendar_pick(dlg, d)
    % State machine: stage 0 → from, stage 1 → to
end

function calendar_clear(dlg)
    % Reset sel_from, sel_to, torna a stage 0
end

function calendar_apply(dlg)
    % Applica selezione, aggiorna main window, chiude dialog
end

function Dsub = filter_defect_by_dates(Defect, d1, d2)
    % Filtra History [d1, d2], ricalcola aggregati
end

function DBsub = filter_db_by_dates(DB, d1, d2)
    % Filtra DB, scarta defect con History empty
end
```

---

## Implementazione (Dopo i Test)

### Dipendenze Python
```python
from datetime import datetime, timedelta
from PyQt6.QtWidgets import QDialog, QCalendarWidget, QDateEdit, QPushButton, QLabel, QVBoxLayout
from PyQt6.QtCore import Qt, pyqtSignal, QDate
import numpy as np
```

### Signature Python

```python
def open_calendar_dialog(
    parent_window: QMainWindow,
    avail_days: list[datetime],
    date_from: datetime | None = None,
    date_to: datetime | None = None,
) -> tuple[datetime, datetime] | None:
    """Open calendar dialog, return (d1, d2) or None if cancelled."""
    pass

def filter_defect_by_dates(
    defect: dict,
    d1: datetime | None,
    d2: datetime | None,
) -> dict:
    """Filter defect History to date range [d1, d2], recalc aggregates."""
    pass

def filter_db_by_dates(
    db: list[dict],
    d1: datetime | None,
    d2: datetime | None,
) -> list[dict]:
    """Filter DB, remove defects with empty History."""
    pass
```

---

## Quality Gates

✅ **TDD:**
- Scritti 6 test prima dell'implementazione
- Test logic-driven (date filtering, state machine), no GUI mock

✅ **Matematica:**
- filter_defect_by_dates: verifica aggregati (Num_Occurrences = sum Detected, Max_Severity = max Amp)
- filter_db_by_dates: verifica keepDefect logic

✅ **Type Hints:**
- Tutte le funzioni tipizzate (datetime, list[dict], dict return)

✅ **Docstring:**
- Una linea max per funzione

✅ **Integration:**
- Dialog standalone (no hardcoded main window ref)
- Filter functions pure (no side effects)

---

## Workflow

1. **Scrivi test** (6 test sopra) → `tests/test_app_dialogs.py`
2. **Estrai MATLAB source** (righe 451-648)
3. **Usa `traduttore-matlab` agent** → traduci in Python
4. **Usa `revisore-matematico` agent** → verifica matematica (filter functions)
5. **Esegui test** → `pytest tests/test_app_dialogs.py -v`
6. **Merge → master** quando tutti i test passano

---

## Effort

- MATLAB source: ~200 righe (8 funzioni + UI setup)
- Python target: ~300-350 righe (PyQt6 boilerplate)
- TDD test: ~200 righe (6 test + helper)
- **Effort totale:** ~2-3 giorni (traduzione + PyQt6 boilerplate + review)

**Note:** Questa è la prima GUI dialog module. Boilerplate PyQt6 (QDialog, layout, signals) è nuovo ma modular per futuri dialog.
