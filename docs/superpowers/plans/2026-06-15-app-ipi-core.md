# App IPI — core score Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the pure scoring math of `update_IPI_Score` (src_app/app.m:5373-5452) into `railway_inspector/app/ipi/ipi_core.py`, fully unit-tested, leaving all UI rendering (labels, colors-on-widgets, text) to the future GUI layer.

**Architecture:** One new module `railway_inspector/app/ipi/ipi_core.py` with three pure functions: `compute_severity_ratio_lv` (per-run Severity and lateral/vertical ratio from sensor amplitudes, app.m:2132-2147), `compute_ipi_score` (the daily-grouped trend + absolute + lateral + PCA + AE composite score, app.m:5377-5452), and `ipi_semaphore_color` (the risk-band RGB, app.m:5447-5450). Reuses `compute_pca_bonus_for_defect` (sub-plan 2) and `_matlab_round_pos` (spectrum.py). AE bonus is **deferred** (the autoencoder is a MATLAB-trained network not yet ported) and enters as an injectable `ae_bonus` argument defaulting to `0.0`, which is exactly the MATLAB behaviour when no AE model is loaded.

**Tech Stack:** Python 3.11+, NumPy, pytest.

---

## Context for the implementer

This is **Piano 2 → sub-plan 3** (the GUI app's IPI composite score). Piano 1 and Piano 2 sub-plans 1-2 are merged on `master`.

**Invariant constraint (non-negotiable):** the math must be numerically identical to the MATLAB original — same coefficients, same operation order, same edge cases, same 1-based→0-based conversions. No MATLAB and no numerical fixtures exist; correctness is enforced by analytical line-by-line review (`revisore-matematico`). Unit tests verify behaviour and structure, not parity against MATLAB numbers.

### What is and isn't in scope
`update_IPI_Score` in MATLAB mixes computation (lines 5377-5452) with `uicontrol`/`set`/`findobj` rendering (lines 5454-5489). **Only the computation is ported here.** The display strings (`score_str`, `coeff_str`, `str_dettaglio`) and the act of painting a widget are presentation and belong to the later GUI sub-plan. The risk-band → RGB mapping (5447-5450) is pure decision logic and *is* included (useful for both the widget and headless reports).

### Data model
- **Defect** = `dict` with key `History` (list) (passed straight through to `compute_pca_bonus_for_defect`).
- `all_amps` = 2-D array, one row per run, **8 columns in this fixed order** (app.m:2134): `[SX_F, SX_R, DX_F, DX_R, LAT_DX_F, LAT_DX_R, LAT_SX_F, LAT_SX_R]` — i.e. columns 0-3 are the four vertical amplitudes, columns 4-7 the four lateral amplitudes.
- `days_floor` = per-run array of integer day numbers (MATLAB `floor(datenum)`); the caller computes it. Tests build it directly.

### Reusable primitives (import — do NOT reimplement)
- `from railway_inspector.app.ipi.pca_model import compute_pca_bonus_for_defect`
- `from railway_inspector.app.analysis.spectrum import _matlab_round_pos`

### MATLAB → Python notes
| MATLAB | Python |
|---|---|
| `mean(x, 'omitnan')` | `np.nanmean(x)` |
| `max([a,b,c,d])` per row | `np.max(cols, axis=1)` |
| `round(min(100, max(0, x)))` (x ≥ 0) | `_matlab_round_pos(min(100, max(0, x)))` |
| `unique(days_floor)` | `np.unique(days_floor)` (sorted ascending) |
| `A_LAT_MAX / max(A_VERT_MAX, 1e-6)` | `a_lat_max / np.maximum(a_vert_max, 1e-6)` |

---

## File Structure
- Create: `railway_inspector/app/ipi/ipi_core.py` — `compute_severity_ratio_lv`, `compute_ipi_score`, `ipi_semaphore_color`.
- Create (test, FLAT in `tests/`): `tests/test_app_ipi_core.py`.

(`railway_inspector/app/ipi/__init__.py` already exists from sub-plan 2.)

---

### Task 1: `compute_severity_ratio_lv`

**MATLAB (app.m:2132-2147, the relevant lines):**
```matlab
for i = 1:n_runs
    A_SX_F = AllAmps(i, 1); A_SX_R = AllAmps(i, 2);
    A_DX_F = AllAmps(i, 3); A_DX_R = AllAmps(i, 4);
    A_LAT_MAX = max(AllAmps(i, 5:8));
    A_VERT_MAX = max([A_SX_F, A_SX_R, A_DX_F, A_DX_R]);
    Severity(i) = max([A_SX_F, A_SX_R, A_DX_F, A_DX_R]);
    Ratio_LV(i) = A_LAT_MAX / max(A_VERT_MAX, 1e-6);
end
```
Note `Severity(i)` and `A_VERT_MAX` are the same value (max of the four vertical columns). Only `Severity` and `Ratio_LV` are in scope; the sibling `Ratio_SX_DX`, `Ratio_FR`, `Lambda_All` belong to the evolutive tab (out of scope here).

**Files:**
- Create: `railway_inspector/app/ipi/ipi_core.py`
- Test: `tests/test_app_ipi_core.py`

- [ ] **Step 1: Write the failing tests** (`tests/test_app_ipi_core.py`)

```python
import numpy as np
import pytest
from railway_inspector.app.ipi.ipi_core import compute_severity_ratio_lv


def test_severity_is_max_of_vertical_columns():
    # cols: [SX_F, SX_R, DX_F, DX_R, LAT_DX_F, LAT_DX_R, LAT_SX_F, LAT_SX_R]
    amps = np.array([[1.0, 4.0, 2.0, 3.0, 0.0, 0.0, 0.0, 0.0]])
    sev, ratio = compute_severity_ratio_lv(amps)
    assert sev[0] == 4.0  # max vertical


def test_ratio_lv_is_lat_over_vert():
    amps = np.array([[2.0, 2.0, 2.0, 2.0, 1.0, 5.0, 3.0, 0.0]])  # vert max 2, lat max 5
    sev, ratio = compute_severity_ratio_lv(amps)
    assert ratio[0] == pytest.approx(5.0 / 2.0)


def test_ratio_lv_zero_vertical_uses_floor():
    amps = np.array([[0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]])
    sev, ratio = compute_severity_ratio_lv(amps)
    assert ratio[0] == pytest.approx(1.0 / 1e-6)


def test_multiple_runs_shapes():
    amps = np.zeros((5, 8))
    sev, ratio = compute_severity_ratio_lv(amps)
    assert sev.shape == (5,)
    assert ratio.shape == (5,)
```

- [ ] **Step 2: Run them, expect FAIL**

Run: `python -m pytest tests/test_app_ipi_core.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'railway_inspector.app.ipi.ipi_core'`

- [ ] **Step 3: Implement** (`railway_inspector/app/ipi/ipi_core.py`)

```python
"""IPI composite score (pure math port of app.m:5373-5452 and 2132-2147).

Excludes all UI rendering: only the numeric breakdown and the risk-band colour.
"""
from __future__ import annotations

import numpy as np

from railway_inspector.config import CFG
from railway_inspector.app.analysis.spectrum import _matlab_round_pos
from railway_inspector.app.ipi.pca_model import compute_pca_bonus_for_defect


def compute_severity_ratio_lv(all_amps: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Per-run Severity (max vertical amplitude) and lateral/vertical ratio.

    Port of app.m:2132-2147. ``all_amps`` has 8 columns in the order
    [SX_F, SX_R, DX_F, DX_R, LAT_DX_F, LAT_DX_R, LAT_SX_F, LAT_SX_R]: columns
    0-3 vertical, 4-7 lateral.
    """
    A = np.asarray(all_amps, dtype=float)
    if A.ndim == 1:
        A = A.reshape(1, -1)
    vert = A[:, 0:4]
    lat = A[:, 4:8]
    a_vert_max = np.max(vert, axis=1)
    a_lat_max = np.max(lat, axis=1)
    severity = a_vert_max  # Severity(i) == A_VERT_MAX (app.m:2140)
    ratio_lv = a_lat_max / np.maximum(a_vert_max, 1e-6)
    return severity, ratio_lv
```

- [ ] **Step 4: Run them, expect PASS**

Run: `python -m pytest tests/test_app_ipi_core.py -v`
Expected: PASS (4 passed)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/ipi/ipi_core.py tests/test_app_ipi_core.py
git commit -m "feat(app): compute_severity_ratio_lv (per-run severity + lat/vert ratio)"
```

---

### Task 2: `ipi_semaphore_color`

**MATLAB (app.m:5447-5450):**
```matlab
if ipi_final >= 75, col_semaforo = [0.8 0 0];
elseif ipi_final >= 50, col_semaforo = [1 0.5 0];
elseif ipi_final >= 25, col_semaforo = [0.9 0.8 0];
else, col_semaforo = [0 0.6 0]; end
```
The "insufficient data" branch (app.m:5379) uses grey `[0.7 0.7 0.7]`; that is a *separate* state, not part of the score-band mapping, and is handled by the widget when `n_days < IPI_MIN_DAYS` (it is not produced by this function).

**Files:**
- Modify: `railway_inspector/app/ipi/ipi_core.py`
- Test: `tests/test_app_ipi_core.py`

- [ ] **Step 1: Append the failing tests**

```python
from railway_inspector.app.ipi.ipi_core import ipi_semaphore_color


@pytest.mark.parametrize("score,rgb", [
    (90, (0.8, 0.0, 0.0)),
    (75, (0.8, 0.0, 0.0)),
    (60, (1.0, 0.5, 0.0)),
    (50, (1.0, 0.5, 0.0)),
    (30, (0.9, 0.8, 0.0)),
    (25, (0.9, 0.8, 0.0)),
    (10, (0.0, 0.6, 0.0)),
    (0, (0.0, 0.6, 0.0)),
])
def test_ipi_semaphore_color_bands(score, rgb):
    assert ipi_semaphore_color(score) == rgb
```

- [ ] **Step 2: Run them, expect FAIL**

Run: `python -m pytest tests/test_app_ipi_core.py -k semaphore -v`
Expected: FAIL with `ImportError: cannot import name 'ipi_semaphore_color'`

- [ ] **Step 3: Append the implementation**

```python
def ipi_semaphore_color(ipi_final: float) -> tuple[float, float, float]:
    """Risk-band RGB for an IPI score (app.m:5447-5450). Grey 'insufficient
    data' state is handled by the widget, not here."""
    if ipi_final >= 75:
        return (0.8, 0.0, 0.0)
    if ipi_final >= 50:
        return (1.0, 0.5, 0.0)
    if ipi_final >= 25:
        return (0.9, 0.8, 0.0)
    return (0.0, 0.6, 0.0)
```

- [ ] **Step 4: Run them, expect PASS**

Run: `python -m pytest tests/test_app_ipi_core.py -k semaphore -v`
Expected: PASS (8 passed)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/ipi/ipi_core.py tests/test_app_ipi_core.py
git commit -m "feat(app): ipi_semaphore_color risk-band mapping"
```

---

### Task 3: `compute_ipi_score`

**MATLAB (app.m:5377-5452 — the pure computation, UI stripped):**
```matlab
if n_days < C.IPI_MIN_DAYS
    ipi_final = 0;
    S_trend = 0; S_absolute = 0; Bonus_lat = 0; Bonus_ia = 0; inc_perc = 0; Bonus_pca = 0;
else
    Severity_Daily = zeros(n_days, 1);
    Ratio_LV_Daily = zeros(n_days, 1);
    for d = 1:n_days
        mask = (days_floor == unique_days(d));
        Severity_Daily(d) = mean(Severity(mask), 'omitnan');
        Ratio_LV_Daily(d) = mean(Ratio_LV(mask), 'omitnan');
    end
    S_trend = 0; S_absolute = 0; inc_perc = 0; Bonus_lat = 0; rms_recent = NaN;
    history_span = unique_days(end) - unique_days(1);
    if history_span >= C.IPI_MIN_HISTORY_DAYS
        cutoff_day  = unique_days(end) - C.IPI_RECENT_DAYS;
        mask_recent = unique_days >  cutoff_day;
        mask_base   = unique_days <= cutoff_day;
        if any(mask_recent) && any(mask_base)
            rms_base   = mean(Severity_Daily(mask_base),   'omitnan');
            rms_recent = mean(Severity_Daily(mask_recent), 'omitnan');
            if rms_base > 0
                inc_perc = ((rms_recent - rms_base) / rms_base) * 100;
                S_trend = min(50, max(0, inc_perc * (50 / C.IPI_TREND_SENS)));
            end
            if rms_recent < C.IPI_SEV_THR_LOW
                S_absolute = 0;
            elseif rms_recent > C.IPI_SEV_THR_HIGH
                S_absolute = 50;
            else
                S_absolute = 50 * (rms_recent - C.IPI_SEV_THR_LOW) / (C.IPI_SEV_THR_HIGH - C.IPI_SEV_THR_LOW);
            end
            recent_ratio_lv = mean(Ratio_LV_Daily(mask_recent), 'omitnan');
            Bonus_lat = min(C.IPI_LAT_BONUS, max(0, (recent_ratio_lv / C.IPI_LAT_THRESH) * C.IPI_LAT_BONUS));
        end
    end
    Bonus_ia = 0;
    if ~isempty(AE_Net) && ~isempty(AE_mu) && ~isempty(AE_sigma)
        AE_Model_Local = struct(...);
        [Bonus_ia, ~] = compute_ae_bonus_for_defect(Defect, AE_Model_Local, h.CFG);
    end
    [Bonus_pca, ~] = compute_pca_bonus_for_defect(Defect, h.CFG);
    ipi_raw = S_absolute + S_trend + Bonus_lat + Bonus_pca + Bonus_ia;
    ipi_final = round(min(100, max(0, ipi_raw)));
end
```

**Notes:**
- The function is self-contained: it derives `unique_days` and `n_days` from `days_floor` (mirrors the caller's `floor`/`unique`).
- AE is deferred. MATLAB sets `Bonus_ia = 0` unless an AE model is loaded; replicate by accepting `ae_bonus: float = 0.0` (the value the future AE sub-plan will pass in). With the default, behaviour matches "no AE model loaded".
- PCA bonus comes from the already-ported `compute_pca_bonus_for_defect(Defect, cfg)` (it returns `(bonus, info)`; take `[0]`). It returns 0 for defects with fewer than `IPI_PCA_MIN_RUNS` runs, so a light Defect keeps this path at 0.
- `round(min(100, max(0, ipi_raw)))`: `ipi_raw` is clamped to `[0, 100]` (non-negative) before rounding, so `_matlab_round_pos` (half-away-from-zero for x ≥ 0) is exact.
- Return a dict with every component plus `ipi_final`, `ipi_raw`, `rms_recent`, `inc_perc`, `n_days`. `rms_recent` stays `NaN` when the history-span/mask gates aren't met (mirrors MATLAB).
- `min(50, ...)`/`min(C.IPI_LAT_BONUS, ...)` use Python `min`/`max` with mixed int/float — fine.

**Files:**
- Modify: `railway_inspector/app/ipi/ipi_core.py`
- Test: `tests/test_app_ipi_core.py`

- [ ] **Step 1: Append the failing tests**

```python
from railway_inspector.app.ipi.ipi_core import compute_ipi_score
from railway_inspector.config import default_config


def test_ipi_insufficient_days_returns_zero():
    cfg = default_config()  # IPI_MIN_DAYS = 10
    # only 3 distinct days
    days = np.array([1.0, 1.0, 2.0, 3.0])
    sev = np.array([20.0, 20.0, 20.0, 20.0])
    ratio = np.array([0.1, 0.1, 0.1, 0.1])
    res = compute_ipi_score(sev, ratio, days, {"History": []}, cfg)
    assert res["ipi_final"] == 0
    assert res["S_trend"] == 0
    assert res["S_absolute"] == 0
    assert res["Bonus_lat"] == 0
    assert res["Bonus_pca"] == 0
    assert res["Bonus_ia"] == 0
    assert res["n_days"] == 3


def test_ipi_short_history_span_no_trend_or_absolute():
    cfg = default_config()  # IPI_MIN_HISTORY_DAYS = 45
    # 12 distinct days but spanning only 11 days (< 45) -> no recent/base split
    days = np.arange(0.0, 12.0)
    sev = np.full(12, 30.0)
    ratio = np.full(12, 1.0)
    res = compute_ipi_score(sev, ratio, days, {"History": []}, cfg)
    assert res["n_days"] == 12
    assert res["S_trend"] == 0
    assert res["S_absolute"] == 0
    assert res["Bonus_lat"] == 0
    assert np.isnan(res["rms_recent"])
    assert res["ipi_final"] == 0  # only PCA(0)+AE(0)


def test_ipi_full_scenario_absolute_and_trend():
    cfg = default_config()
    # 60-day span, daily samples. Base severity 10, recent severity 40.
    days = np.arange(0.0, 61.0)               # 61 distinct days, span 60 >= 45
    sev = np.where(days <= (60 - cfg.IPI_RECENT_DAYS), 10.0, 40.0)
    ratio = np.full(days.size, 0.7)           # recent_ratio_lv/0.7 * 30 -> full lat bonus
    res = compute_ipi_score(sev, ratio, days, {"History": []}, cfg)
    # rms_base = 10, rms_recent = 40 -> inc 300% -> S_trend clamped to 50
    assert res["rms_recent"] == pytest.approx(40.0)
    assert res["S_trend"] == 50
    # rms_recent 40 in (15,50) -> S_absolute = 50*(40-15)/(50-15)
    assert res["S_absolute"] == pytest.approx(50 * (40 - 15) / (50 - 15))
    # ratio 0.7 / 0.7 * 30 = 30 -> Bonus_lat clamped to 30
    assert res["Bonus_lat"] == 30
    # ipi_final = round(min(100, S_abs + 50 + 30 + 0 + 0))
    expected_raw = res["S_absolute"] + 50 + 30
    assert res["ipi_final"] == round(min(100, expected_raw))


def test_ipi_ae_bonus_is_injectable():
    cfg = default_config()
    days = np.arange(0.0, 61.0)
    sev = np.full(days.size, 5.0)   # below IPI_SEV_THR_LOW -> S_absolute 0, flat -> S_trend 0
    ratio = np.zeros(days.size)
    res = compute_ipi_score(sev, ratio, days, {"History": []}, cfg, ae_bonus=12.0)
    assert res["Bonus_ia"] == 12.0
    assert res["ipi_final"] == 12  # only the injected AE bonus contributes
```

- [ ] **Step 2: Run them, expect FAIL**

Run: `python -m pytest tests/test_app_ipi_core.py -k ipi_ -v`
Expected: FAIL with `ImportError: cannot import name 'compute_ipi_score'`

- [ ] **Step 3: Append the implementation**

```python
def compute_ipi_score(severity: np.ndarray, ratio_lv: np.ndarray, days_floor: np.ndarray,
                      Defect: dict, cfg: CFG, ae_bonus: float = 0.0) -> dict:
    """IPI composite score (app.m:5377-5452), UI stripped.

    Returns a dict with ipi_final, ipi_raw, the five components (S_trend,
    S_absolute, Bonus_lat, Bonus_pca, Bonus_ia), rms_recent, inc_perc, n_days.
    AE bonus is injected via ``ae_bonus`` (0.0 == no AE model, the MATLAB default).
    """
    severity = np.asarray(severity, dtype=float).reshape(-1)
    ratio_lv = np.asarray(ratio_lv, dtype=float).reshape(-1)
    days_floor = np.asarray(days_floor, dtype=float).reshape(-1)
    unique_days = np.unique(days_floor)
    n_days = len(unique_days)

    result = {
        "ipi_final": 0, "ipi_raw": 0.0,
        "S_trend": 0, "S_absolute": 0, "Bonus_lat": 0,
        "Bonus_pca": 0, "Bonus_ia": 0,
        "rms_recent": np.nan, "inc_perc": 0, "n_days": n_days,
    }
    if n_days < cfg.IPI_MIN_DAYS:
        return result

    severity_daily = np.zeros(n_days)
    ratio_lv_daily = np.zeros(n_days)
    for d in range(n_days):
        mask = days_floor == unique_days[d]
        severity_daily[d] = np.nanmean(severity[mask])
        ratio_lv_daily[d] = np.nanmean(ratio_lv[mask])

    S_trend = 0
    S_absolute = 0
    inc_perc = 0
    Bonus_lat = 0
    rms_recent = np.nan
    history_span = unique_days[-1] - unique_days[0]
    if history_span >= cfg.IPI_MIN_HISTORY_DAYS:
        cutoff_day = unique_days[-1] - cfg.IPI_RECENT_DAYS
        mask_recent = unique_days > cutoff_day
        mask_base = unique_days <= cutoff_day
        if np.any(mask_recent) and np.any(mask_base):
            rms_base = np.nanmean(severity_daily[mask_base])
            rms_recent = np.nanmean(severity_daily[mask_recent])
            if rms_base > 0:
                inc_perc = ((rms_recent - rms_base) / rms_base) * 100
                S_trend = min(50, max(0, inc_perc * (50 / cfg.IPI_TREND_SENS)))
            if rms_recent < cfg.IPI_SEV_THR_LOW:
                S_absolute = 0
            elif rms_recent > cfg.IPI_SEV_THR_HIGH:
                S_absolute = 50
            else:
                S_absolute = 50 * (rms_recent - cfg.IPI_SEV_THR_LOW) / (
                    cfg.IPI_SEV_THR_HIGH - cfg.IPI_SEV_THR_LOW)
            recent_ratio_lv = np.nanmean(ratio_lv_daily[mask_recent])
            Bonus_lat = min(cfg.IPI_LAT_BONUS,
                            max(0, (recent_ratio_lv / cfg.IPI_LAT_THRESH) * cfg.IPI_LAT_BONUS))

    Bonus_ia = ae_bonus  # AE deferred: 0.0 == no AE model loaded (app.m:5427-5432)
    Bonus_pca = compute_pca_bonus_for_defect(Defect, cfg)[0]

    ipi_raw = S_absolute + S_trend + Bonus_lat + Bonus_pca + Bonus_ia
    ipi_final = _matlab_round_pos(min(100, max(0, ipi_raw)))

    result.update({
        "ipi_final": ipi_final, "ipi_raw": ipi_raw,
        "S_trend": S_trend, "S_absolute": S_absolute, "Bonus_lat": Bonus_lat,
        "Bonus_pca": Bonus_pca, "Bonus_ia": Bonus_ia,
        "rms_recent": rms_recent, "inc_perc": inc_perc, "n_days": n_days,
    })
    return result
```

- [ ] **Step 4: Run them, expect PASS**

Run: `python -m pytest tests/test_app_ipi_core.py -v`
Expected: PASS (all ipi_core tests green)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/ipi/ipi_core.py tests/test_app_ipi_core.py
git commit -m "feat(app): compute_ipi_score composite (trend+absolute+lat+pca+ae)"
```

---

### Task 4: Full suite + review gates

**Files:** none (verification task).

- [ ] **Step 1: Run the entire suite**

Run: `python -m pytest -q`
Expected: PASS — all prior tests plus the new ipi_core tests, 0 failures.

- [ ] **Step 2: Dispatch the math reviewer**

Dispatch `revisore-matematico` on `railway_inspector/app/ipi/ipi_core.py` against MATLAB app.m:5377-5452 (and 2132-2147 for severity/ratio). Must confirm at minimum:
- `compute_severity_ratio_lv`: column split (0-3 vertical, 4-7 lateral); `Severity == max vertical`; `ratio = max_lat / max(max_vert, 1e-6)`.
- `compute_ipi_score`: `n_days < IPI_MIN_DAYS` early-zero branch; daily grouping by unique day with `omitnan`; `history_span = unique_days[-1]-unique_days[0]` gate; cutoff masks (`>` recent, `<=` base); trend (`rms_base>0`, `min(50,max(0, inc*(50/IPI_TREND_SENS)))`); absolute three-way (`<THR_LOW→0`, `>THR_HIGH→50`, else linear interp); lateral bonus formula and clamp; PCA bonus via `compute_pca_bonus_for_defect(...)[0]`; `Bonus_ia` injectable (0 default = MATLAB no-AE branch); `ipi_raw` sum order; `round(min(100,max(0,·)))` via `_matlab_round_pos`; `rms_recent` stays NaN when gates fail.
- `ipi_semaphore_color`: thresholds `>=75 / >=50 / >=25 / else` and exact RGB triples; grey state correctly excluded.
Do not close the task until APPROVED or all corrections applied (re-run `pytest -q` after any fix).

- [ ] **Step 3: Dispatch the code-quality reviewer** (only after math review passes)

Standard pass on the new module + test (one responsibility, naming, type hints consistent with the codebase, DRY reuse of `compute_pca_bonus_for_defect` / `_matlab_round_pos`, tests meaningful).

- [ ] **Step 4: Update graphify + progress memory**

Run: `graphify update .`
Update `memory/database-builder-progress.md`: Piano 2 sub-plan 3 (ipi_core) done; AE (`ae_model.py`) still deferred and feeds `compute_ipi_score(..., ae_bonus=...)`; next candidates = analysis/classification + drawing, then GUI.

- [ ] **Step 5: Final commit if anything changed in Steps 2-4**

```bash
git add -A
git commit -m "chore(app): ipi_core reviewed + graph/memory updated"
```

---

## Self-Review (completed by plan author)

**1. Spec coverage:** Covers the pure-math portion of `ipi/ipi_core.py` (`update_IPI_Score`) from Section 3 of the design spec. UI rendering (labels/text/widget painting) is explicitly deferred to the GUI sub-plan. AE bonus deferred via an injectable argument (the autoencoder network port is a separate decision). `compute_severity_ratio_lv` is included because the IPI score consumes Severity/Ratio_LV and they are otherwise computed inline in the MATLAB stats-window setup.

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to". Every code step has complete code.

**3. Type/name consistency:** `compute_ipi_score` returns a dict whose keys are asserted verbatim in the Task 3 tests. `compute_pca_bonus_for_defect` is called as `(...)[0]` matching its real `(bonus, info)` return (sub-plan 2). `_matlab_round_pos` imported from `analysis.spectrum`. `cfg` is a `CFG` with `IPI_*` fields added in sub-plan 2's Task 1. Severity/ratio column order matches the documented `all_amps` layout.

**Out of scope (later sub-plans):** `ae_model.py` (AE bonus), `analysis/classification.py`, `analysis/drawing.py`, all GUI widgets/dialogs/tabs/main_window/run_app.py, and the display-string formatting of `update_IPI_Score`.
```
