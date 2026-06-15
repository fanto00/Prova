# App Analysis — defect classification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the pure computation of `generate_defect_classification_report` (src_app/app.m:6195-6347) into `railway_inspector/app/analysis/classification.py` as `classify_defects(DB, cfg) -> list[dict]`, fully unit-tested, leaving the dashboard rendering (figures/tabs/pie/scatter, app.m:6350+) to the future GUI layer.

**Architecture:** One new module `railway_inspector/app/analysis/classification.py` with the public `classify_defects` and a small pure helper `_mode_categorical` (MATLAB `mode(categorical(...))` over strings). Reuses already-ported primitives: `get_amp` (helpers), `get_spectrum_psd`, `peak_lambda_from_spectrum`, `lambda_to_label` (spectrum).

**Tech Stack:** Python 3.11+, NumPy, pytest.

---

## Context for the implementer

This is **Piano 2 → sub-plan 5** (the GUI app's defect-classification report data). Piano 1 and Piano 2 sub-plans 1-3 are merged on `master`. Sub-plan 4 (AE) is intentionally skipped.

**Invariant constraint (non-negotiable):** the math must be numerically identical to the MATLAB original — same thresholds, same operation order, same edge cases, same 1-based→0-based conversions. No MATLAB and no numerical fixtures exist; correctness is enforced by analytical line-by-line review (`revisore-matematico`). Unit tests verify behaviour and structure, not parity against MATLAB numbers.

### What is and isn't in scope
`generate_defect_classification_report` mixes a per-defect computation loop (lines 6195-6347, building the `SummaryData` records) with a `figure`/`uitab`/`pie`/`scatter` dashboard (6350+). **Only the computation loop is ported here**, as `classify_defects(DB, cfg)` returning the list of per-defect records. The dashboard and the `draw_*` overlay helpers are pure rendering and belong to the later GUI sub-plan.

### Data model
- **DB** = `list` of defect dicts. Each **Defect** has `History` (list), `ID_PK` (str), `Avg_Pos` (float).
- **History entry** = dict with `Date` (`datetime.datetime`), `Data` (dict). **Data** has `Filt` (dict: sensor → `np.ndarray`).

### Reusable primitives (import — do NOT reimplement)
- `from railway_inspector.app.utils.helpers import get_amp`
- `from railway_inspector.app.analysis.spectrum import get_spectrum_psd, peak_lambda_from_spectrum, lambda_to_label`

### Fixed thresholds (defined locally in the MATLAB function, app.m:6201-6210)
```
THR_LAT_VERT = 0.6   THR_ASYM_HIGH = 2.0   THR_ASYM_LOW = 0.5
THR_PITCH = 2.0      THR_PITCH_LOW = 0.5
L_GIUNTO = 0.5       L_IRREG = 1.0         L_DEFORM = 2.0
```
These are local constants in the MATLAB function (NOT in CFG); define them as module-level constants in `classification.py`. (`THR_LAT_VERT` is declared in MATLAB but not used in the ported loop — include it as a documented module constant for fidelity but do not invent a use.)

### MATLAB → Python notes
| MATLAB | Python |
|---|---|
| `datetime(dt, 'Format', 'yyyy_MM')` | `date.strftime("%Y_%m")` |
| `mode(categorical(cells))` | `_mode_categorical(cells)` — most frequent; ties → alphabetically smallest |
| `sort(fieldnames(MonthlyTracker))` then `{end}` | sort month keys ascending, take the last (most recent; `YYYY_MM` sorts chronologically) |
| `mean(v)` (plain) | `float(np.mean(v))` |
| `get_spectrum_psd` returns `[psd, freq]` | `psd, freq = get_spectrum_psd(...)` (returns `(None, None)` when empty) |

---

## File Structure
- Create: `railway_inspector/app/analysis/classification.py` — `classify_defects`, `_mode_categorical`, module threshold constants.
- Create (test, FLAT in `tests/`): `tests/test_app_classification.py`.

---

### Task 1: `_mode_categorical` helper

**MATLAB:** `mode(categorical(cells))` returns the most frequently occurring category; on ties it returns the **smallest** in category order, which for cellstr input is alphabetical. Replicate: count occurrences, take the max count, and among the tied values return the alphabetically smallest. Returns a `str`.

**Files:**
- Create: `railway_inspector/app/analysis/classification.py` (helper + constants only in this task)
- Test: `tests/test_app_classification.py`

- [ ] **Step 1: Write the failing tests** (`tests/test_app_classification.py`)

```python
import numpy as np
import pytest
from railway_inspector.app.analysis.classification import _mode_categorical


def test_mode_categorical_clear_winner():
    assert _mode_categorical(["A", "B", "A", "A"]) == "A"


def test_mode_categorical_tie_returns_alphabetically_smallest():
    # "Front-Left" and "Rear-Right" each appear twice -> alphabetical first
    cells = ["Rear-Right", "Front-Left", "Rear-Right", "Front-Left"]
    assert _mode_categorical(cells) == "Front-Left"


def test_mode_categorical_single():
    assert _mode_categorical(["Center-Center"]) == "Center-Center"
```

- [ ] **Step 2: Run them, expect FAIL**

Run: `python -m pytest tests/test_app_classification.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'railway_inspector.app.analysis.classification'`

- [ ] **Step 3: Implement** (`railway_inspector/app/analysis/classification.py`)

```python
"""Per-defect 3x3 classification report (pure data port of app.m:6195-6347).

Builds the SummaryData records; the dashboard rendering (figures, pie, scatter)
is left to the GUI layer.
"""
from __future__ import annotations

from collections import Counter

import numpy as np

from railway_inspector.app.utils.helpers import get_amp
from railway_inspector.app.analysis.spectrum import (
    get_spectrum_psd,
    peak_lambda_from_spectrum,
    lambda_to_label,
)

# Classification thresholds (local constants in app.m:6201-6210).
THR_LAT_VERT = 0.6     # declared in MATLAB, unused in this loop (kept for fidelity)
THR_ASYM_HIGH = 2.0
THR_ASYM_LOW = 0.5
THR_PITCH = 2.0
THR_PITCH_LOW = 0.5
L_GIUNTO = 0.5
L_IRREG = 1.0
L_DEFORM = 2.0


def _mode_categorical(cells: list[str]) -> str:
    """MATLAB mode(categorical(cells)): most frequent value; ties -> the
    alphabetically smallest (category order for cellstr is sorted)."""
    counts = Counter(cells)
    max_count = max(counts.values())
    winners = [c for c, n in counts.items() if n == max_count]
    return min(winners)
```

- [ ] **Step 4: Run them, expect PASS**

Run: `python -m pytest tests/test_app_classification.py -v`
Expected: PASS (3 passed)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/analysis/classification.py tests/test_app_classification.py
git commit -m "feat(app): _mode_categorical helper + classification thresholds"
```

---

### Task 2: `classify_defects`

**MATLAB (app.m:6221-6347 — the per-defect computation, dashboard stripped):**
```matlab
for i = 1:n_db
    Defect = DB(i);
    MonthlyTracker = struct();
    Spec_SX = []; Spec_DX = []; freq_vec_SX = []; freq_vec_DX = [];
    W_SX = 0; W_DX = 0;
    for k = 1:length(Defect.History)
        run = Defect.History(k);
        if ~isfield(run.Data, 'Filt'), continue; end
        F = run.Data.Filt;
        dt = run.Date;                                  % datetime
        mese_str = char(datetime(dt, 'Format', 'yyyy_MM'));
        mese_field = ['m_', mese_str];
        A_SX_F = get_amp(F, 'left_sensor_front');
        A_SX_R = get_amp(F, 'left_sensor_rear');
        A_DX_F = get_amp(F, 'right_sensor_front');
        A_DX_R = get_amp(F, 'right_sensor_rear');
        A_LAT_DXF = get_amp(F, 'right_sensor_front_lat');
        A_LAT_DXR = get_amp(F, 'right_sensor_rear_lat');
        A_LAT_SXF = get_amp(F, 'left_sensor_front_lat');
        A_LAT_SXR = get_amp(F, 'left_sensor_rear_lat');
        A_VERT_MAX = max([A_SX_F, A_SX_R, A_DX_F, A_DX_R]);
        A_LAT_MAX  = max([A_LAT_DXF, A_LAT_DXR, A_LAT_SXF, A_LAT_SXR]);
        if A_VERT_MAX < 1e-6, continue; end
        Ratio_SX_DX      = (A_SX_F + A_SX_R) / max(A_DX_F + A_DX_R, 1e-6);
        Ratio_Front_Rear = (A_SX_F + A_DX_F) / max(A_SX_R + A_DX_R, 1e-6);
        Ratio_Lat_Vert   = A_LAT_MAX / max(A_VERT_MAX, 1e-6);
        if Ratio_SX_DX > THR_ASYM_HIGH,        pos_x = 'Left';
        elseif Ratio_SX_DX < THR_ASYM_LOW,     pos_x = 'Right';
        else,                                  pos_x = 'Center'; end
        if Ratio_Front_Rear > THR_PITCH,       pos_y = 'Front';
        elseif Ratio_Front_Rear < THR_PITCH_LOW, pos_y = 'Rear';
        else,                                  pos_y = 'Center'; end
        cella_3x3 = sprintf('%s-%s', pos_y, pos_x);
        % monthly tracking (cells, ratios, amp_max)
        ...
        w_pass_SX = A_SX_F + A_SX_R;  w_pass_DX = A_DX_F + A_DX_R;
        [s_sx, f_sx] = get_spectrum_psd(F, {'left_sensor_front','left_sensor_rear'}, [A_SX_F, A_SX_R], CFG);
        if ~isempty(s_sx)
            if isempty(Spec_SX), Spec_SX = zeros(size(s_sx)); freq_vec_SX = f_sx; end
            if length(s_sx) == length(Spec_SX), Spec_SX = Spec_SX + s_sx * w_pass_SX; W_SX = W_SX + w_pass_SX; end
        end
        [s_dx, f_dx] = get_spectrum_psd(F, {'right_sensor_front','right_sensor_rear'}, [A_DX_F, A_DX_R], CFG);
        if ~isempty(s_dx)
            if isempty(Spec_DX), Spec_DX = zeros(size(s_dx)); freq_vec_DX = f_dx; end
            if length(s_dx) == length(Spec_DX), Spec_DX = Spec_DX + s_dx * w_pass_DX; W_DX = W_DX + w_pass_DX; end
        end
    end
    campi_mesi = sort(fieldnames(MonthlyTracker));
    if isempty(campi_mesi)
        SummaryData(i).ID = Defect.ID_PK; SummaryData(i).Pos = Defect.Avg_Pos;
        SummaryData(i).Cella_Dominante = 'N/D'; SummaryData(i).Lambda_SX = 0; SummaryData(i).Lambda_DX = 0;
        continue;
    end
    ultimo_mese = MonthlyTracker.(campi_mesi{end});
    cella_dominante_mese = char(mode(categorical(ultimo_mese.celle_3x3)));
    Lambda_SX = peak_lambda_from_spectrum(Spec_SX, freq_vec_SX, W_SX, CFG);
    Lambda_DX = peak_lambda_from_spectrum(Spec_DX, freq_vec_DX, W_DX, CFG);
    LAMBDA_MAX_FISICO = CFG.WINDOW_SIZE * 1.5;
    if Lambda_SX > LAMBDA_MAX_FISICO, Lambda_SX = 0; end
    if Lambda_DX > LAMBDA_MAX_FISICO, Lambda_DX = 0; end
    nat_SX = lambda_to_label(Lambda_SX, L_GIUNTO, L_IRREG, L_DEFORM);
    nat_DX = lambda_to_label(Lambda_DX, L_GIUNTO, L_IRREG, L_DEFORM);
    SummaryData(i).ID = Defect.ID_PK; SummaryData(i).Pos = Defect.Avg_Pos;
    SummaryData(i).Amp = ultimo_mese.amp_max;
    SummaryData(i).Cella_Dominante = cella_dominante_mese;
    SummaryData(i).Lambda_SX = Lambda_SX; SummaryData(i).Lambda_DX = Lambda_DX;
    SummaryData(i).NaturaSpettrale_SX = nat_SX; SummaryData(i).NaturaSpettrale_DX = nat_DX;
    SummaryData(i).Ratio_SX_DX_Avg = mean(ultimo_mese.ratios_x);
    SummaryData(i).Ratio_FR_Avg = mean(ultimo_mese.ratios_y);
    SummaryData(i).Ratio_Lat_Vert_Avg = mean(ultimo_mese.ratios_lv);
    SummaryData(i).Mese_Ultimo = ultimo_mese.mese_label;
end
```

**Notes:**
- Returns a `list` of per-defect dicts (one per defect in `DB`, in order). Each record uses the field names: `ID`, `Pos`, `Amp`, `Cella_Dominante`, `Lambda_SX`, `Lambda_DX`, `NaturaSpettrale_SX`, `NaturaSpettrale_DX`, `Ratio_SX_DX_Avg`, `Ratio_FR_Avg`, `Ratio_Lat_Vert_Avg`, `Mese_Ultimo`.
- **Monthly tracker:** keyed by `mese_str` (`"YYYY_MM"`). Each month accumulates: list of cell strings, lists of the three ratios, and a running `amp_max = max(amp_max, max(A_SX_F, A_SX_R, A_DX_F, A_DX_R))`. Use a plain `dict[str, dict]`.
- **PSD accumulation is global per defect** (not per month) — `Spec_SX`/`Spec_DX` accumulate across all runs; the length-guard `len(s_sx) == len(Spec_SX)` mirrors MATLAB.
- **Resolution on the last month:** sort month keys ascending, take the last. Dominant cell = `_mode_categorical(last_month["cells"])`. Lambdas from the *global* accumulated spectra. Clamp each lambda to 0 if it exceeds `cfg.WINDOW_SIZE * 1.5`.
- **No-valid-months case** (`campi_mesi` empty): emit a record with `ID`, `Pos`, `Cella_Dominante="N/D"`, `Lambda_SX=0`, `Lambda_DX=0`, and the other fields set to `None` (MATLAB leaves them empty). Tests assert on the populated fields.
- Skip a run when `Filt` not in `run["Data"]` or `A_VERT_MAX < 1e-6`.
- `mean(ultimo_mese.ratios_x)` is a plain mean (no omitnan).
- Date: `run["Date"].strftime("%Y_%m")`.

**Files:**
- Modify: `railway_inspector/app/analysis/classification.py`
- Test: `tests/test_app_classification.py`

- [ ] **Step 1: Write the failing tests**

```python
import datetime as dt
from railway_inspector.app.analysis.classification import classify_defects
from railway_inspector.config import default_config

SENSORS = ['left_sensor_front', 'left_sensor_rear', 'right_sensor_front',
           'right_sensor_rear', 'right_sensor_front_lat', 'right_sensor_rear_lat',
           'left_sensor_front_lat', 'left_sensor_rear_lat']


def _run(date, amps, n=400):
    """amps keyed by sensor name -> a flat signal of constant |value| (so get_amp == value)."""
    filt = {}
    for s in SENSORS:
        v = amps.get(s, 0.0)
        filt[s] = np.full(n, v)
    return {"Date": date, "Data": {"Filt": filt}}


def test_classify_empty_history_gives_nd_record():
    cfg = default_config()
    DB = [{"ID_PK": "1.234", "Avg_Pos": 1234.0, "History": []}]
    out = classify_defects(DB, cfg)
    assert len(out) == 1
    assert out[0]["ID"] == "1.234"
    assert out[0]["Pos"] == 1234.0
    assert out[0]["Cella_Dominante"] == "N/D"
    assert out[0]["Lambda_SX"] == 0
    assert out[0]["Lambda_DX"] == 0


def test_classify_dominant_cell_and_ratios():
    cfg = default_config()
    # Build a defect whose runs are strongly Left (SX>>DX) and Front (F>>R).
    # A_SX_F=A_SX_R=10, A_DX_F=A_DX_R=1 -> Ratio_SX_DX = 20/2 = 10 > 2 -> 'Left'
    # Ratio_Front_Rear = (10+1)/(10+1) = 1 -> 'Center'  => cell 'Center-Left'
    amps = {'left_sensor_front': 10.0, 'left_sensor_rear': 10.0,
            'right_sensor_front': 1.0, 'right_sensor_rear': 1.0,
            'left_sensor_front_lat': 2.0}
    runs = [_run(dt.datetime(2026, 5, d), amps) for d in (1, 2, 3)]
    DB = [{"ID_PK": "9.9", "Avg_Pos": 9900.0, "History": runs}]
    out = classify_defects(DB, cfg)
    rec = out[0]
    assert rec["Cella_Dominante"] == "Center-Left"
    assert rec["Mese_Ultimo"] == "2026_05"
    assert rec["Ratio_SX_DX_Avg"] == pytest.approx(10.0)
    assert rec["Ratio_FR_Avg"] == pytest.approx(1.0)
    # Ratio_Lat_Vert = max_lat(2)/max_vert(10) = 0.2
    assert rec["Ratio_Lat_Vert_Avg"] == pytest.approx(0.2)
    assert rec["Amp"] == pytest.approx(10.0)
    # lambdas are finite and labels consistent with lambda_to_label
    from railway_inspector.app.analysis.classification import L_GIUNTO, L_IRREG, L_DEFORM
    from railway_inspector.app.analysis.spectrum import lambda_to_label
    assert rec["Lambda_SX"] >= 0
    assert rec["NaturaSpettrale_SX"] == lambda_to_label(rec["Lambda_SX"], L_GIUNTO, L_IRREG, L_DEFORM)


def test_classify_uses_last_month():
    cfg = default_config()
    amps_left = {'left_sensor_front': 10.0, 'left_sensor_rear': 10.0,
                 'right_sensor_front': 1.0, 'right_sensor_rear': 1.0}
    amps_right = {'left_sensor_front': 1.0, 'left_sensor_rear': 1.0,
                  'right_sensor_front': 10.0, 'right_sensor_rear': 10.0}
    runs = [_run(dt.datetime(2026, 1, 5), amps_left),    # Jan -> Left
            _run(dt.datetime(2026, 3, 5), amps_right)]   # Mar -> Right (last month)
    DB = [{"ID_PK": "x", "Avg_Pos": 0.0, "History": runs}]
    out = classify_defects(DB, cfg)
    assert out[0]["Mese_Ultimo"] == "2026_03"
    assert out[0]["Cella_Dominante"] == "Center-Right"
```

- [ ] **Step 2: Run them, expect FAIL**

Run: `python -m pytest tests/test_app_classification.py -k classify -v`
Expected: FAIL with `ImportError: cannot import name 'classify_defects'`

- [ ] **Step 3: Implement** (append to `classification.py`)

```python
def classify_defects(DB: list, cfg) -> list[dict]:
    """Per-defect 3x3 classification + dominant wavelength (app.m:6221-6347).

    Returns one record dict per defect in DB (same order). The dashboard
    rendering is intentionally out of scope.
    """
    summary: list[dict] = []
    for Defect in DB:
        monthly: dict[str, dict] = {}
        spec_sx = None
        spec_dx = None
        freq_sx = None
        freq_dx = None
        w_sx = 0.0
        w_dx = 0.0

        for run in Defect["History"]:
            data = run["Data"]
            if "Filt" not in data:
                continue
            F = data["Filt"]
            mese_str = run["Date"].strftime("%Y_%m")

            a_sx_f = get_amp(F, "left_sensor_front")
            a_sx_r = get_amp(F, "left_sensor_rear")
            a_dx_f = get_amp(F, "right_sensor_front")
            a_dx_r = get_amp(F, "right_sensor_rear")
            a_lat_dxf = get_amp(F, "right_sensor_front_lat")
            a_lat_dxr = get_amp(F, "right_sensor_rear_lat")
            a_lat_sxf = get_amp(F, "left_sensor_front_lat")
            a_lat_sxr = get_amp(F, "left_sensor_rear_lat")

            a_vert_max = max(a_sx_f, a_sx_r, a_dx_f, a_dx_r)
            a_lat_max = max(a_lat_dxf, a_lat_dxr, a_lat_sxf, a_lat_sxr)
            if a_vert_max < 1e-6:
                continue

            ratio_sx_dx = (a_sx_f + a_sx_r) / max(a_dx_f + a_dx_r, 1e-6)
            ratio_front_rear = (a_sx_f + a_dx_f) / max(a_sx_r + a_dx_r, 1e-6)
            ratio_lat_vert = a_lat_max / max(a_vert_max, 1e-6)

            if ratio_sx_dx > THR_ASYM_HIGH:
                pos_x = "Left"
            elif ratio_sx_dx < THR_ASYM_LOW:
                pos_x = "Right"
            else:
                pos_x = "Center"
            if ratio_front_rear > THR_PITCH:
                pos_y = "Front"
            elif ratio_front_rear < THR_PITCH_LOW:
                pos_y = "Rear"
            else:
                pos_y = "Center"
            cella_3x3 = f"{pos_y}-{pos_x}"

            if mese_str not in monthly:
                monthly[mese_str] = {
                    "mese_label": mese_str, "cells": [],
                    "ratios_x": [], "ratios_y": [], "ratios_lv": [], "amp_max": 0.0,
                }
            m = monthly[mese_str]
            m["cells"].append(cella_3x3)
            m["ratios_x"].append(ratio_sx_dx)
            m["ratios_y"].append(ratio_front_rear)
            m["ratios_lv"].append(ratio_lat_vert)
            max_amp_run = max(a_sx_f, a_sx_r, a_dx_f, a_dx_r)
            m["amp_max"] = max(m["amp_max"], max_amp_run)

            w_pass_sx = a_sx_f + a_sx_r
            w_pass_dx = a_dx_f + a_dx_r

            s_sx, f_sx = get_spectrum_psd(
                F, ["left_sensor_front", "left_sensor_rear"], [a_sx_f, a_sx_r], cfg)
            if s_sx is not None:
                if spec_sx is None:
                    spec_sx = np.zeros_like(s_sx)
                    freq_sx = f_sx
                if len(s_sx) == len(spec_sx):
                    spec_sx = spec_sx + s_sx * w_pass_sx
                    w_sx = w_sx + w_pass_sx

            s_dx, f_dx = get_spectrum_psd(
                F, ["right_sensor_front", "right_sensor_rear"], [a_dx_f, a_dx_r], cfg)
            if s_dx is not None:
                if spec_dx is None:
                    spec_dx = np.zeros_like(s_dx)
                    freq_dx = f_dx
                if len(s_dx) == len(spec_dx):
                    spec_dx = spec_dx + s_dx * w_pass_dx
                    w_dx = w_dx + w_pass_dx

        if not monthly:
            summary.append({
                "ID": Defect["ID_PK"], "Pos": Defect["Avg_Pos"],
                "Amp": None, "Cella_Dominante": "N/D",
                "Lambda_SX": 0, "Lambda_DX": 0,
                "NaturaSpettrale_SX": None, "NaturaSpettrale_DX": None,
                "Ratio_SX_DX_Avg": None, "Ratio_FR_Avg": None,
                "Ratio_Lat_Vert_Avg": None, "Mese_Ultimo": None,
            })
            continue

        last_key = sorted(monthly.keys())[-1]
        ultimo_mese = monthly[last_key]
        cella_dominante = _mode_categorical(ultimo_mese["cells"])

        lambda_sx = peak_lambda_from_spectrum(spec_sx, freq_sx, w_sx, cfg)
        lambda_dx = peak_lambda_from_spectrum(spec_dx, freq_dx, w_dx, cfg)
        lambda_max_fisico = cfg.WINDOW_SIZE * 1.5
        if lambda_sx > lambda_max_fisico:
            lambda_sx = 0
        if lambda_dx > lambda_max_fisico:
            lambda_dx = 0

        summary.append({
            "ID": Defect["ID_PK"], "Pos": Defect["Avg_Pos"],
            "Amp": ultimo_mese["amp_max"],
            "Cella_Dominante": cella_dominante,
            "Lambda_SX": lambda_sx, "Lambda_DX": lambda_dx,
            "NaturaSpettrale_SX": lambda_to_label(lambda_sx, L_GIUNTO, L_IRREG, L_DEFORM),
            "NaturaSpettrale_DX": lambda_to_label(lambda_dx, L_GIUNTO, L_IRREG, L_DEFORM),
            "Ratio_SX_DX_Avg": float(np.mean(ultimo_mese["ratios_x"])),
            "Ratio_FR_Avg": float(np.mean(ultimo_mese["ratios_y"])),
            "Ratio_Lat_Vert_Avg": float(np.mean(ultimo_mese["ratios_lv"])),
            "Mese_Ultimo": ultimo_mese["mese_label"],
        })
    return summary
```

- [ ] **Step 4: Run them, expect PASS**

Run: `python -m pytest tests/test_app_classification.py -v`
Expected: PASS (all classification tests green)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/analysis/classification.py tests/test_app_classification.py
git commit -m "feat(app): classify_defects (3x3 cell + dominant lambda per defect)"
```

---

### Task 3: Full suite + review gates

**Files:** none (verification task).

- [ ] **Step 1: Run the entire suite**

Run: `python -m pytest -q`
Expected: PASS — all prior tests plus the new classification tests, 0 failures.

- [ ] **Step 2: Dispatch the math reviewer**

Dispatch `revisore-matematico` on `railway_inspector/app/analysis/classification.py` against MATLAB app.m:6195-6347. Must confirm:
- Thresholds match (ASYM 2.0/0.5, PITCH 2.0/0.5, lambda 0.5/1.0/2.0) and the 3x3 cell string format `"<pos_y>-<pos_x>"`.
- Run skip conditions (`Filt` missing, `A_VERT_MAX < 1e-6`); the three ratio formulas with `max(·, 1e-6)` denominators.
- Monthly tracking accumulation; `amp_max` running max; month key `YYYY_MM`.
- Global (per-defect) PSD accumulation with the length guard and weighted sum; `peak_lambda_from_spectrum` fed the accumulated spectra and weights; lambda clamp at `WINDOW_SIZE*1.5`.
- Last-month resolution: sorted month keys → last; `_mode_categorical` tie-break (alphabetically smallest); plain `mean` of the ratio lists.
- No-valid-months record shape.
Do not close until APPROVED or corrections applied (re-run `pytest -q` after fixes).

- [ ] **Step 3: Dispatch the code-quality reviewer** (only after math review passes)

Standard pass on the new module + test (single responsibility, naming, type hints, DRY reuse of `get_amp`/`get_spectrum_psd`/`peak_lambda_from_spectrum`/`lambda_to_label`, tests meaningful).

- [ ] **Step 4: Update graphify + progress memory**

Run: `graphify update .`
Update `memory/database-builder-progress.md`: Piano 2 sub-plan 5 (classification) done; remaining = drawing overlays (GUI), AE (deferred), and the full GUI layer.

- [ ] **Step 5: Final commit if anything changed in Steps 2-4**

```bash
git add -A
git commit -m "chore(app): classification reviewed + graph/memory updated"
```

---

## Self-Review (completed by plan author)

**1. Spec coverage:** Covers the pure data-building portion of `analysis/classification.py` (`generate_defect_classification_report`) from Section 3 of the design spec. The dashboard rendering and the `draw_*` overlays (`draw_infra_overlay`, `draw_joints_overlay`, `draw_signature_grid`) are pure GUI and deferred to the GUI sub-plan.

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to". Every code step has complete code.

**3. Type/name consistency:** Record field names are identical between the producer (Task 2) and the test assertions. `_mode_categorical` defined in Task 1 and used in Task 2. Reused primitives use their real signatures: `get_amp(F, name)`, `get_spectrum_psd(F, sensor_list, weights, cfg) -> (psd, freq)`, `peak_lambda_from_spectrum(spectrum, freq_vec, total_weight, cfg)`, `lambda_to_label(lam, L_giunto, L_irreg, L_deform)`. `cfg.WINDOW_SIZE` added in sub-plan 2.

**Out of scope (later sub-plans):** `analysis/drawing.py` (overlays), the classification dashboard rendering, AE, and all GUI widgets/dialogs/tabs/main_window/run_app.py.
```
