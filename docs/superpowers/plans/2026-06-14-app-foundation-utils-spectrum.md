# App Foundation — utils + spectrum Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Translate the pure-math foundation functions of `src_app/app.m` (sensor amplitude/RMS helpers, date filters, weighted PSD spectrum) into the Python package, fully unit-tested, as the base layer the IPI/PCA/AE/GUI plans depend on.

**Architecture:** Three new modules under a new `railway_inspector/app/` subpackage: `app/utils/helpers.py` (signal-level scalar helpers + run sorting + fractional shift), `app/utils/filters.py` (Defect/DB date filtering on the dict-based data model), `app/analysis/spectrum.py` (weighted periodogram PSD + dominant-lambda extraction + label). All functions are pure (no GUI, no I/O) and reuse already-translated primitives from Piano 1: `movmean`, `interp1_zero`, `shift_signal_frac`.

**Tech Stack:** Python 3.11+, NumPy, SciPy (`scipy.signal.periodogram`, `scipy.signal.windows.hamming`), pytest.

---

## Context for the implementer

This is **Piano 2** (the GUI app). Piano 1 (database builder) is complete and merged. You are translating MATLAB → Python with the **invariant constraint**: the math must be numerically identical to the MATLAB original (same coefficients, same operation order, same edge-case handling, same 1-based→0-based index conversions). There is **no MATLAB available and no numerical fixtures** — correctness is enforced by analytical line-by-line review (the `revisore-matematico` agent), not by golden numbers. Your unit tests verify *behavior and structure*, not parity against MATLAB output.

### Data model (already established in Piano 1)

The Python DB uses plain dicts (not dataclasses):

- **Defect** = `dict` with keys `History` (list), `Num_Occurrences` (int), `Num_Total_Runs` (int), `Max_Severity` (float).
- **History entry** (a "run") = `dict` with keys `Date` (`datetime.datetime`), `RunName` (str), `Detected` (bool), `Amp` (float), `Data` (dict), and optionally `orientation` (str).
- **Data** = dict containing `Filt` (dict: sensor-name → `np.ndarray`) and `RelativeAxis` (`np.ndarray`).
- A sensor field `F` = `Data["Filt"]`; `isfield(F, name)` → `name in F`; `F.(name)` → `F[name]`.

### MATLAB→Python idiom cheatsheet for this plan

| MATLAB | Python |
|---|---|
| `isfield(S, f)` | `f in S` |
| `double(x)` | `np.asarray(x, dtype=float)` |
| `any(sig ~= 0)` | `np.any(sig != 0)` |
| `sig(:)` | `sig.reshape(-1)` (1-D) |
| `movmean(sig.^2, k)` | `movmean(sig**2, k)` (reuse `detection.trigger.movmean`) |
| `interp1(f, p, q, 'linear', 0)` | `interp1_zero(f, p, q)` (reuse `signal.resampling.interp1_zero`) |
| `round(length/2)` (positive int len) | `(N + 1) // 2` (== MATLAB round-half-away-from-zero for `.5`) |

### Reusable primitives (DO NOT reimplement — import these)

- `from railway_inspector.detection.trigger import movmean`
- `from railway_inspector.signal.resampling import interp1_zero`
- `from railway_inspector.signal.alignment import shift_signal_frac`

---

## File Structure

- Create: `railway_inspector/app/__init__.py` — empty package marker.
- Create: `railway_inspector/app/utils/__init__.py` — empty package marker.
- Create: `railway_inspector/app/utils/helpers.py` — `get_amp`, `get_max_rms`, `safe_ratio`, `get_sign_mean`, `sort_runs_by_direction`, `helper_fft_shift`.
- Create: `railway_inspector/app/utils/filters.py` — `filter_defect_by_dates`, `filter_db_by_dates`.
- Create: `railway_inspector/app/analysis/__init__.py` — empty package marker.
- Create: `railway_inspector/app/analysis/spectrum.py` — `get_spectrum_psd`, `peak_lambda_from_spectrum`, `lambda_to_label`.
- Create: `tests/app/__init__.py`, `tests/app/utils/__init__.py`, `tests/app/analysis/__init__.py` if the test tree needs package markers (match existing `tests/` convention).
- Create: `tests/app/utils/test_helpers.py`, `tests/app/utils/test_filters.py`, `tests/app/analysis/test_spectrum.py`.

---

### Task 1: Scaffold the `app` subpackage

**Files:**
- Create: `railway_inspector/app/__init__.py`
- Create: `railway_inspector/app/utils/__init__.py`
- Create: `railway_inspector/app/analysis/__init__.py`

- [ ] **Step 1: Create the three package markers**

Each file contains a single docstring line:

`railway_inspector/app/__init__.py`:
```python
"""Piano 2 — GUI application package (PyQt6 port of src_app/app.m)."""
```

`railway_inspector/app/utils/__init__.py`:
```python
"""Pure helper/utility functions for the app (no GUI)."""
```

`railway_inspector/app/analysis/__init__.py`:
```python
"""Analysis math for the app: spectrum, classification, drawing data prep."""
```

- [ ] **Step 2: Verify the package imports**

Run: `python -c "import railway_inspector.app, railway_inspector.app.utils, railway_inspector.app.analysis"`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add railway_inspector/app/__init__.py railway_inspector/app/utils/__init__.py railway_inspector/app/analysis/__init__.py
git commit -m "feat(app): scaffold app subpackage (utils, analysis)"
```

---

### Task 2: `get_amp` and `get_max_rms` in helpers.py

**MATLAB (app.m:7180-7189 and 7164-7178):**
```matlab
function a = get_amp(F, sensor_name)
    if isfield(F, sensor_name)
        sig = double(F.(sensor_name));
        if ~isempty(sig) && any(sig ~= 0)
            a = max(abs(sig));
            return;
        end
    end
    a = 0;
end

function a = get_max_rms(F, sensor_name, win_samples)
    if isfield(F, sensor_name)
        sig = double(F.(sensor_name));
        if ~isempty(sig) && any(sig ~= 0)
            if length(sig) >= win_samples
                rms_sig = sqrt(movmean(sig.^2, win_samples));
                a = max(rms_sig);
            else
                a = max(abs(sig));
            end
            return;
        end
    end
    a = 0;
end
```

**Files:**
- Create: `railway_inspector/app/utils/helpers.py`
- Test: `tests/app/utils/test_helpers.py`

- [ ] **Step 1: Write the failing tests**

```python
import numpy as np
import pytest
from railway_inspector.app.utils.helpers import get_amp, get_max_rms


def test_get_amp_missing_sensor_returns_zero():
    assert get_amp({}, "s1") == 0


def test_get_amp_all_zero_returns_zero():
    assert get_amp({"s1": np.zeros(10)}, "s1") == 0


def test_get_amp_returns_max_abs():
    assert get_amp({"s1": np.array([-3.0, 1.0, 2.0])}, "s1") == 3.0


def test_get_max_rms_missing_sensor_returns_zero():
    assert get_max_rms({}, "s1", 4) == 0


def test_get_max_rms_short_signal_falls_back_to_max_abs():
    # length 3 < win_samples 5  -> max(abs(sig))
    assert get_max_rms({"s1": np.array([-3.0, 1.0, 2.0])}, "s1", 5) == 3.0


def test_get_max_rms_uses_movmean_rms():
    from railway_inspector.detection.trigger import movmean
    sig = np.array([1.0, 2.0, 3.0, 4.0, 5.0])
    expected = float(np.max(np.sqrt(movmean(sig**2, 3))))
    assert get_max_rms({"s1": sig}, "s1", 3) == pytest.approx(expected)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/app/utils/test_helpers.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'railway_inspector.app.utils.helpers'`

- [ ] **Step 3: Write the implementation**

```python
"""Scalar signal helpers (port of app.m helper functions).

Pure functions over the dict-based data model. Reuses Piano 1 primitives.
"""
from __future__ import annotations

import numpy as np

from railway_inspector.detection.trigger import movmean


def get_amp(F: dict, sensor_name: str) -> float:
    """max(abs(signal)), or 0 if missing/empty/all-zero (app.m:7180)."""
    if sensor_name in F:
        sig = np.asarray(F[sensor_name], dtype=float).reshape(-1)
        if sig.size > 0 and np.any(sig != 0):
            return float(np.max(np.abs(sig)))
    return 0.0


def get_max_rms(F: dict, sensor_name: str, win_samples: int) -> float:
    """max of moving-RMS, falling back to max(abs) for short signals (app.m:7164)."""
    if sensor_name in F:
        sig = np.asarray(F[sensor_name], dtype=float).reshape(-1)
        if sig.size > 0 and np.any(sig != 0):
            if sig.size >= win_samples:
                rms_sig = np.sqrt(movmean(sig**2, win_samples))
                return float(np.max(rms_sig))
            return float(np.max(np.abs(sig)))
    return 0.0
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/app/utils/test_helpers.py -v`
Expected: PASS (6 passed)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/utils/helpers.py tests/app/utils/test_helpers.py
git commit -m "feat(app): get_amp + get_max_rms helpers"
```

---

### Task 3: `safe_ratio` in helpers.py

**MATLAB (app.m:7357-7367):**
```matlab
function r = safe_ratio(a, b)
    if b < 1e-6
        if a < 1e-6
            r = 1.0;  % entrambi zero -> simmetrico
        else
            r = 999;  % denominatore zero -> infinito
        end
    else
        r = a / b;
    end
end
```

**Files:**
- Modify: `railway_inspector/app/utils/helpers.py`
- Test: `tests/app/utils/test_helpers.py`

- [ ] **Step 1: Append the failing tests**

```python
from railway_inspector.app.utils.helpers import safe_ratio


def test_safe_ratio_both_small_returns_one():
    assert safe_ratio(0.0, 0.0) == 1.0


def test_safe_ratio_zero_denominator_returns_999():
    assert safe_ratio(5.0, 0.0) == 999


def test_safe_ratio_normal_division():
    assert safe_ratio(6.0, 3.0) == 2.0
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/app/utils/test_helpers.py -k safe_ratio -v`
Expected: FAIL with `ImportError: cannot import name 'safe_ratio'`

- [ ] **Step 3: Append the implementation to helpers.py**

```python
def safe_ratio(a: float, b: float) -> float:
    """a/b with MATLAB guards: 1.0 if both ~0, 999 if only denom ~0 (app.m:7357)."""
    if b < 1e-6:
        if a < 1e-6:
            return 1.0
        return 999
    return a / b
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/app/utils/test_helpers.py -k safe_ratio -v`
Expected: PASS (3 passed)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/utils/helpers.py tests/app/utils/test_helpers.py
git commit -m "feat(app): safe_ratio helper"
```

---

### Task 4: `get_sign_mean` in helpers.py

**MATLAB (app.m:7383-7407):**
```matlab
function s = get_sign_mean(Defect, sens1, sens2)
    vals = [];
    for k = 1:length(Defect.History)
        run = Defect.History(k);
        if ~isfield(run.Data, 'Filt'), continue; end
        F = run.Data.Filt;
        for sn = {sens1, sens2}
            if isfield(F, sn{1})
                sig = double(F.(sn{1}));
                if ~isempty(sig)
                    mid = round(length(sig)/2);
                    half = min(5, floor(length(sig)/4));
                    vals(end+1) = mean(sig(mid-half:mid+half));
                end
            end
        end
    end
    if isempty(vals)
        s = 1;
    else
        s = sign(mean(vals));
    end
end
```

**Index conversion note:** MATLAB `mid = round(length/2)` is 1-based. For positive integer `N`, MATLAB round-half-away-from-zero of `N/2` equals `(N + 1) // 2`. The MATLAB slice `sig(mid-half : mid+half)` is inclusive 1-based; in 0-based Python with `mid0 = (N + 1)//2 - 1` the equivalent slice is `sig[mid0-half : mid0+half+1]`. `np.sign(0)` returns `0.0` (matches MATLAB `sign(0)=0`); the empty-vals case must return `1` per the MATLAB fallback.

**Files:**
- Modify: `railway_inspector/app/utils/helpers.py`
- Test: `tests/app/utils/test_helpers.py`

- [ ] **Step 1: Append the failing tests**

```python
from railway_inspector.app.utils.helpers import get_sign_mean


def _run(filt):
    return {"Data": {"Filt": filt}}


def test_get_sign_mean_empty_history_returns_one():
    assert get_sign_mean({"History": []}, "a", "b") == 1


def test_get_sign_mean_no_filt_returns_one():
    defect = {"History": [{"Data": {}}]}
    assert get_sign_mean(defect, "a", "b") == 1


def test_get_sign_mean_positive_center():
    # N=11 -> mid0 = (11+1)//2 - 1 = 5 ; half = min(5, 11//4=2) = 2
    # slice sig[3:8] = all +2.0 -> mean +2 -> sign +1
    sig = np.full(11, 2.0)
    defect = {"History": [_run({"a": sig})]}
    assert get_sign_mean(defect, "a", "b") == 1.0


def test_get_sign_mean_negative_center():
    sig = np.full(11, -2.0)
    defect = {"History": [_run({"a": sig})]}
    assert get_sign_mean(defect, "a", "b") == -1.0
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/app/utils/test_helpers.py -k sign_mean -v`
Expected: FAIL with `ImportError: cannot import name 'get_sign_mean'`

- [ ] **Step 3: Append the implementation to helpers.py**

```python
def get_sign_mean(Defect: dict, sens1: str, sens2: str) -> float:
    """Sign of the mean center value, averaged over runs and the two sensors.

    Port of app.m:7383. Empty result falls back to +1.
    """
    vals: list[float] = []
    for run in Defect.get("History", []):
        data = run.get("Data", {})
        if "Filt" not in data:
            continue
        F = data["Filt"]
        for sn in (sens1, sens2):
            if sn in F:
                sig = np.asarray(F[sn], dtype=float).reshape(-1)
                if sig.size > 0:
                    N = sig.size
                    mid0 = (N + 1) // 2 - 1          # MATLAB round(N/2), 1-based -> 0-based
                    half = min(5, N // 4)            # floor(length/4)
                    seg = sig[mid0 - half: mid0 + half + 1]
                    vals.append(float(np.mean(seg)))
    if not vals:
        return 1
    return float(np.sign(np.mean(vals)))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/app/utils/test_helpers.py -k sign_mean -v`
Expected: PASS (4 passed)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/utils/helpers.py tests/app/utils/test_helpers.py
git commit -m "feat(app): get_sign_mean helper (1-based center index)"
```

---

### Task 5: `sort_runs_by_direction` in helpers.py

**MATLAB (app.m:6524-6562):**
```matlab
function [idx_fwd, idx_bwd] = sort_runs_by_direction(History)
    n_runs = length(History);
    idx_fwd = false(n_runs, 1);
    idx_bwd = false(n_runs, 1);
    for i = 1:n_runs
        run_i = History(i);
        d = run_i.Data;
        if ~isfield(d, 'Filt'), continue; end
        Fd = d.Filt;
        ori = '';
        if isfield(run_i, 'orientation') && ~isempty(run_i.orientation)
            ori = lower(strtrim(char(run_i.orientation)));
        elseif isfield(d, 'orientation') && ~isempty(d.orientation)
            ori = lower(strtrim(char(d.orientation)));
        end
        if contains(ori, 'forward')
            idx_fwd(i) = true;
        elseif contains(ori, 'backward')
            idx_bwd(i) = true;
        else
            rms_r = 0; rms_l = 0;
            if isfield(Fd, 'right_sensor_front_lat') && ~isempty(Fd.right_sensor_front_lat)
                s = double(Fd.right_sensor_front_lat); s = s(isfinite(s));
                if ~isempty(s), rms_r = sqrt(mean(s.^2)); end
            end
            if isfield(Fd, 'left_sensor_front_lat') && ~isempty(Fd.left_sensor_front_lat)
                s = double(Fd.left_sensor_front_lat); s = s(isfinite(s));
                if ~isempty(s), rms_l = sqrt(mean(s.^2)); end
            end
            if     rms_r > rms_l, idx_fwd(i) = true;
            elseif rms_l > rms_r, idx_bwd(i) = true;
            end
        end
    end
end
```

**Note:** MATLAB returns two boolean masks. In Python return two `np.ndarray` boolean masks of length `len(History)`. The fallback uses **population RMS** `sqrt(mean(s.^2))` over finite samples only. Ties (`rms_r == rms_l`, including both 0) leave both masks `False` for that run.

**Files:**
- Modify: `railway_inspector/app/utils/helpers.py`
- Test: `tests/app/utils/test_helpers.py`

- [ ] **Step 1: Append the failing tests**

```python
from railway_inspector.app.utils.helpers import sort_runs_by_direction


def test_sort_runs_orientation_forward_backward():
    history = [
        {"orientation": "Forward", "Data": {"Filt": {}}},
        {"orientation": "backward run", "Data": {"Filt": {}}},
    ]
    fwd, bwd = sort_runs_by_direction(history)
    assert list(fwd) == [True, False]
    assert list(bwd) == [False, True]


def test_sort_runs_no_filt_is_skipped():
    history = [{"orientation": "forward", "Data": {}}]
    fwd, bwd = sort_runs_by_direction(history)
    assert list(fwd) == [False]
    assert list(bwd) == [False]


def test_sort_runs_rms_fallback():
    # right lateral RMS > left lateral RMS -> forward
    history = [{
        "Data": {"Filt": {
            "right_sensor_front_lat": np.array([3.0, 3.0, 3.0]),
            "left_sensor_front_lat": np.array([1.0, 1.0, 1.0]),
        }},
    }]
    fwd, bwd = sort_runs_by_direction(history)
    assert list(fwd) == [True]
    assert list(bwd) == [False]


def test_sort_runs_rms_tie_leaves_both_false():
    history = [{
        "Data": {"Filt": {
            "right_sensor_front_lat": np.array([2.0, 2.0]),
            "left_sensor_front_lat": np.array([2.0, 2.0]),
        }},
    }]
    fwd, bwd = sort_runs_by_direction(history)
    assert list(fwd) == [False]
    assert list(bwd) == [False]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/app/utils/test_helpers.py -k sort_runs -v`
Expected: FAIL with `ImportError: cannot import name 'sort_runs_by_direction'`

- [ ] **Step 3: Append the implementation to helpers.py**

```python
def _rms_finite(F: dict, field: str) -> float:
    """Population RMS over finite samples, 0 if missing/empty (app.m fallback)."""
    if field in F:
        s = np.asarray(F[field], dtype=float).reshape(-1)
        s = s[np.isfinite(s)]
        if s.size > 0:
            return float(np.sqrt(np.mean(s**2)))
    return 0.0


def sort_runs_by_direction(History: list) -> tuple[np.ndarray, np.ndarray]:
    """Split runs into forward/backward boolean masks (app.m:6524).

    Uses the run/Data ``orientation`` string if present, else falls back to
    comparing front lateral RMS (right>left -> forward). Ties stay False.
    """
    n_runs = len(History)
    idx_fwd = np.zeros(n_runs, dtype=bool)
    idx_bwd = np.zeros(n_runs, dtype=bool)
    for i, run_i in enumerate(History):
        d = run_i.get("Data", {})
        if "Filt" not in d:
            continue
        Fd = d["Filt"]
        ori = ""
        if run_i.get("orientation"):
            ori = str(run_i["orientation"]).strip().lower()
        elif d.get("orientation"):
            ori = str(d["orientation"]).strip().lower()
        if "forward" in ori:
            idx_fwd[i] = True
        elif "backward" in ori:
            idx_bwd[i] = True
        else:
            rms_r = _rms_finite(Fd, "right_sensor_front_lat")
            rms_l = _rms_finite(Fd, "left_sensor_front_lat")
            if rms_r > rms_l:
                idx_fwd[i] = True
            elif rms_l > rms_r:
                idx_bwd[i] = True
    return idx_fwd, idx_bwd
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/app/utils/test_helpers.py -k sort_runs -v`
Expected: PASS (4 passed)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/utils/helpers.py tests/app/utils/test_helpers.py
git commit -m "feat(app): sort_runs_by_direction (orientation + RMS fallback)"
```

---

### Task 6: `helper_fft_shift` in helpers.py (delegates to Piano 1 `shift_signal_frac`)

**MATLAB (app.m:1846-1864):**
```matlab
function shifted_sig = helper_fft_shift(sig, shift_m, spatial_res)
    % Questa funzione replica esattamente shift_signal_frac del DB Creator
    N = length(sig);
    if N <= 1, shifted_sig = sig; return; end
    sig_work = double(sig(:));
    shift_samples = shift_m / spatial_res;
    X = fft(sig_work);
    k = (0:N-1)';
    k(k > floor(N/2)) = k(k > floor(N/2)) - N;
    phase_shift = exp(-1i * 2 * pi * k * shift_samples / N);
    shifted_sig = real(ifft(X .* phase_shift));
    if isrow(sig), shifted_sig = shifted_sig'; end
end
```

**Note (DRY):** The MATLAB comment states this *exactly* replicates `shift_signal_frac` from the DB creator, which is already translated in `railway_inspector/signal/alignment.py` (`shift_signal_frac(sig, shift_m, spatial_res)`). Do NOT reimplement the FFT math. `helper_fft_shift` is a thin alias that preserves the `N <= 1` early-return guard, then delegates. (`shift_signal_frac` already handles the `N<=1` case as a no-op shift, but keep the explicit guard to mirror the MATLAB source 1:1 and make the delegation obvious to the reviewer.)

**Files:**
- Modify: `railway_inspector/app/utils/helpers.py`
- Test: `tests/app/utils/test_helpers.py`

- [ ] **Step 1: Append the failing tests**

```python
from railway_inspector.app.utils.helpers import helper_fft_shift
from railway_inspector.signal.alignment import shift_signal_frac


def test_helper_fft_shift_short_signal_returned_unchanged():
    sig = np.array([5.0])
    out = helper_fft_shift(sig, 0.1, 0.004)
    assert np.array_equal(out, sig)


def test_helper_fft_shift_matches_shift_signal_frac():
    sig = np.sin(np.linspace(0, 4 * np.pi, 64))
    out = helper_fft_shift(sig, 0.012, 0.004)
    expected = shift_signal_frac(sig, 0.012, 0.004)
    np.testing.assert_allclose(out, expected, atol=1e-12)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/app/utils/test_helpers.py -k fft_shift -v`
Expected: FAIL with `ImportError: cannot import name 'helper_fft_shift'`

- [ ] **Step 3: Append the implementation to helpers.py**

Add the import near the top of the file (next to the existing imports):
```python
from railway_inspector.signal.alignment import shift_signal_frac
```

Then append:
```python
def helper_fft_shift(sig, shift_m: float, spatial_res: float):
    """Fractional FFT phase shift. Exact alias of signal.alignment.shift_signal_frac
    (the DB-creator function the MATLAB source delegates to). See app.m:1846."""
    sig = np.asarray(sig, dtype=float).reshape(-1)
    if sig.size <= 1:
        return sig
    return shift_signal_frac(sig, shift_m, spatial_res)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/app/utils/test_helpers.py -k fft_shift -v`
Expected: PASS (2 passed)

- [ ] **Step 5: Run the full helpers test file**

Run: `pytest tests/app/utils/test_helpers.py -v`
Expected: PASS (all helper tests green)

- [ ] **Step 6: Commit**

```bash
git add railway_inspector/app/utils/helpers.py tests/app/utils/test_helpers.py
git commit -m "feat(app): helper_fft_shift delegating to shift_signal_frac"
```

---

### Task 7: `filter_defect_by_dates` in filters.py

**MATLAB (app.m:613-637):**
```matlab
function Dsub = filter_defect_by_dates(Defect, d1, d2)
    Dsub = Defect;
    if isempty(d1), return; end
    if isempty(d2), d2 = d1; end
    if d2 < d1, t=d1; d1=d2; d2=t; end
    H = Defect.History;
    if isempty(H), return; end
    dk = dateshift([H.Date], 'start', 'day');
    Dsub.History = H(dk >= d1 & dk <= d2);
    Hs = Dsub.History;
    if isempty(Hs)
        if isfield(Dsub,'Num_Occurrences'), Dsub.Num_Occurrences = 0; end
        if isfield(Dsub,'Num_Total_Runs'),  Dsub.Num_Total_Runs  = 0; end
        if isfield(Dsub,'Max_Severity'),     Dsub.Max_Severity     = 0; end
        return;
    end
    amps = [Hs.Amp];
    if isfield(Dsub,'Max_Severity'),    Dsub.Max_Severity    = max(amps); end
    if isfield(Dsub,'Num_Total_Runs'),  Dsub.Num_Total_Runs  = numel(Hs); end
    if isfield(Dsub,'Num_Occurrences')
        if isfield(Hs,'Detected'), Dsub.Num_Occurrences = sum([Hs.Detected]);
        else,                      Dsub.Num_Occurrences = numel(Hs); end
    end
end
```

**Notes:**
- `d1`/`d2` are `datetime.datetime` (or `datetime.date`) or `None`. `dateshift(...,'start','day')` truncates each run's `Date` to midnight; replicate by comparing the **date part** (`.date()`) of each run's `Date` against the date parts of `d1`/`d2`.
- Return a **shallow copy** of the defect dict so the caller's input is not mutated (MATLAB copies by value). `Dsub = dict(Defect)`. The `History` is replaced with a new filtered list, so copying the outer dict suffices.
- The empty/swap/`d2=None` guards must be preserved exactly. `sum([Hs.Detected])` sums booleans; if any run lacks a `Detected` key, MATLAB's `isfield(Hs,'Detected')` is all-or-nothing across the struct array — replicate as: count `Detected` if **all** runs have the key, else `numel(Hs)`.

**Files:**
- Create: `railway_inspector/app/utils/filters.py`
- Test: `tests/app/utils/test_filters.py`

- [ ] **Step 1: Write the failing tests**

```python
import datetime as dt
import numpy as np
from railway_inspector.app.utils.filters import filter_defect_by_dates


def _run(day, amp, detected=True):
    return {"Date": dt.datetime(2026, 1, day, 12, 0), "Amp": amp, "Detected": detected}


def _defect():
    return {
        "History": [_run(1, 10.0), _run(5, 30.0), _run(9, 20.0)],
        "Num_Occurrences": 3,
        "Num_Total_Runs": 3,
        "Max_Severity": 30.0,
    }


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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/app/utils/test_filters.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'railway_inspector.app.utils.filters'`

- [ ] **Step 3: Write the implementation**

```python
"""Date-range filtering of Defect / DB structures (port of app.m:613-647)."""
from __future__ import annotations

import datetime as dt


def _as_day(x):
    """dateshift(x, 'start', 'day') -> the date part."""
    if isinstance(x, dt.datetime):
        return x.date()
    return x  # already a date


def filter_defect_by_dates(Defect: dict, d1, d2) -> dict:
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
        if all("Detected" in run for run in Hs):
            Dsub["Num_Occurrences"] = sum(bool(run["Detected"]) for run in Hs)
        else:
            Dsub["Num_Occurrences"] = len(Hs)
    return Dsub
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/app/utils/test_filters.py -v`
Expected: PASS (7 passed)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/utils/filters.py tests/app/utils/test_filters.py
git commit -m "feat(app): filter_defect_by_dates with aggregate recompute"
```

---

### Task 8: `filter_db_by_dates` in filters.py

**MATLAB (app.m:639-647):**
```matlab
function DBsub = filter_db_by_dates(DB, d1, d2)
    if isempty(d1) || isempty(DB), DBsub = DB; return; end
    DBsub = DB;
    keepDefect = false(1, numel(DB));
    for i = 1:numel(DB)
        DBsub(i) = filter_defect_by_dates(DB(i), d1, d2);
        keepDefect(i) = ~isempty(DBsub(i).History);
    end
    DBsub = DBsub(keepDefect);
end
```

**Note:** `DB` is a Python `list` of defect dicts. Return a new list (do not mutate input). Drop defects whose filtered History is empty.

**Files:**
- Modify: `railway_inspector/app/utils/filters.py`
- Test: `tests/app/utils/test_filters.py`

- [ ] **Step 1: Append the failing tests**

```python
from railway_inspector.app.utils.filters import filter_db_by_dates


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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/app/utils/test_filters.py -k filter_db -v`
Expected: FAIL with `ImportError: cannot import name 'filter_db_by_dates'`

- [ ] **Step 3: Append the implementation to filters.py**

```python
def filter_db_by_dates(DB: list, d1, d2) -> list:
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/app/utils/test_filters.py -v`
Expected: PASS (all filter tests green)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/utils/filters.py tests/app/utils/test_filters.py
git commit -m "feat(app): filter_db_by_dates"
```

---

### Task 9: `lambda_to_label` in spectrum.py

**MATLAB (app.m:7369-7381):**
```matlab
function label = lambda_to_label(lambda, L_giunto, L_irreg, L_deform)
    if lambda <= 0
        label = 'N/D';
    elseif lambda < L_giunto
        label = 'Corto';
    elseif lambda < L_irreg
        label = 'medio';
    elseif lambda < L_deform
        label = 'lungo';
    else
        label = 'molto lungo';
    end
end
```

**Note:** Preserve the exact label strings including capitalization (`'N/D'`, `'Corto'`, `'medio'`, `'lungo'`, `'molto lungo'`) — they are displayed/compared verbatim downstream.

**Files:**
- Create: `railway_inspector/app/analysis/spectrum.py`
- Test: `tests/app/analysis/test_spectrum.py`

- [ ] **Step 1: Write the failing tests**

```python
import numpy as np
import pytest
from railway_inspector.app.analysis.spectrum import lambda_to_label


@pytest.mark.parametrize("lam,expected", [
    (-1.0, "N/D"),
    (0.0, "N/D"),
    (0.3, "Corto"),
    (1.0, "medio"),
    (3.0, "lungo"),
    (50.0, "molto lungo"),
])
def test_lambda_to_label(lam, expected):
    # boundaries: L_giunto=0.5, L_irreg=2.0, L_deform=10.0
    assert lambda_to_label(lam, 0.5, 2.0, 10.0) == expected
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/app/analysis/test_spectrum.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'railway_inspector.app.analysis.spectrum'`

- [ ] **Step 3: Write the implementation**

```python
"""Weighted PSD spectrum and dominant-wavelength extraction (port of app.m)."""
from __future__ import annotations

import numpy as np
from scipy.signal import periodogram
from scipy.signal.windows import hamming

from railway_inspector.signal.resampling import interp1_zero


def lambda_to_label(lambda_, L_giunto: float, L_irreg: float, L_deform: float) -> str:
    """Map a dominant wavelength to a qualitative class label (app.m:7369)."""
    if lambda_ <= 0:
        return "N/D"
    if lambda_ < L_giunto:
        return "Corto"
    if lambda_ < L_irreg:
        return "medio"
    if lambda_ < L_deform:
        return "lungo"
    return "molto lungo"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/app/analysis/test_spectrum.py -v`
Expected: PASS (6 passed)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/analysis/spectrum.py tests/app/analysis/test_spectrum.py
git commit -m "feat(app): lambda_to_label classifier"
```

---

### Task 10: `peak_lambda_from_spectrum` in spectrum.py

**MATLAB (app.m:7335-7355):**
```matlab
function lambda = peak_lambda_from_spectrum(spectrum, freq_vec, total_weight, CFG)
    lambda = 0;
    if isempty(spectrum) || total_weight < 1e-6, return; end
    f_min_band = 1 / CFG.L_MAX;
    f_max_band = 1 / CFG.L_MIN_QUIET;
    mask_band = (freq_vec >= f_min_band) & (freq_vec <= f_max_band);
    if ~any(mask_band), return; end
    spec_norm = spectrum;
    [~, idx_peak] = max(spec_norm(mask_band));
    freq_in_band  = freq_vec(mask_band);
    f_dom = freq_in_band(idx_peak);
    if f_dom > 0
        lambda = 1 / f_dom;
    end
end
```

**Notes:**
- `CFG.L_MAX = 15`, `CFG.L_MIN_QUIET = 0.01` (from `railway_inspector/config.py`). Accept a `CFG` instance and read `cfg.L_MAX` / `cfg.L_MIN_QUIET`.
- `max` on the masked band: `np.argmax` returns the **first** max index, matching MATLAB's `max` tie behavior. Apply the mask, take `argmax`, then index back into the masked frequency sub-vector.
- Empty spectrum → return `0`. Use `spectrum is None or len(spectrum) == 0`.

**Files:**
- Modify: `railway_inspector/app/analysis/spectrum.py`
- Test: `tests/app/analysis/test_spectrum.py`

- [ ] **Step 1: Append the failing tests**

```python
from railway_inspector.app.analysis.spectrum import peak_lambda_from_spectrum
from railway_inspector.config import default_config


def test_peak_lambda_empty_returns_zero():
    cfg = default_config()
    assert peak_lambda_from_spectrum(np.array([]), np.array([]), 1.0, cfg) == 0


def test_peak_lambda_zero_weight_returns_zero():
    cfg = default_config()
    spec = np.array([1.0, 2.0, 3.0])
    freq = np.array([0.1, 0.2, 0.3])
    assert peak_lambda_from_spectrum(spec, freq, 0.0, cfg) == 0


def test_peak_lambda_picks_dominant_in_band():
    cfg = default_config()  # L_MAX=15 -> f_min=1/15; L_MIN_QUIET=0.01 -> f_max=100
    freq = np.array([0.01, 0.1, 0.5, 2.0])   # 0.01 (1/15=0.0667) is below band
    spec = np.array([100.0, 1.0, 9.0, 2.0])  # peak at 0.01 excluded; in-band peak at 0.5
    lam = peak_lambda_from_spectrum(spec, freq, 1.0, cfg)
    assert lam == pytest.approx(1.0 / 0.5)


def test_peak_lambda_no_band_returns_zero():
    cfg = default_config()
    freq = np.array([0.001, 0.002])  # all below 1/15
    spec = np.array([5.0, 6.0])
    assert peak_lambda_from_spectrum(spec, freq, 1.0, cfg) == 0
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/app/analysis/test_spectrum.py -k peak_lambda -v`
Expected: FAIL with `ImportError: cannot import name 'peak_lambda_from_spectrum'`

- [ ] **Step 3: Append the implementation to spectrum.py**

```python
def peak_lambda_from_spectrum(spectrum, freq_vec, total_weight: float, cfg) -> float:
    """Dominant wavelength from the summed spectrum peak in the band of interest
    [1/L_MAX, 1/L_MIN_QUIET] (app.m:7335). Returns 0 when undefined."""
    if spectrum is None or len(spectrum) == 0 or total_weight < 1e-6:
        return 0
    spectrum = np.asarray(spectrum, dtype=float).reshape(-1)
    freq_vec = np.asarray(freq_vec, dtype=float).reshape(-1)

    f_min_band = 1 / cfg.L_MAX
    f_max_band = 1 / cfg.L_MIN_QUIET
    mask_band = (freq_vec >= f_min_band) & (freq_vec <= f_max_band)
    if not np.any(mask_band):
        return 0

    idx_peak = int(np.argmax(spectrum[mask_band]))   # first max, like MATLAB
    f_dom = freq_vec[mask_band][idx_peak]
    if f_dom > 0:
        return 1 / f_dom
    return 0
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/app/analysis/test_spectrum.py -k peak_lambda -v`
Expected: PASS (4 passed)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/analysis/spectrum.py tests/app/analysis/test_spectrum.py
git commit -m "feat(app): peak_lambda_from_spectrum (band-limited dominant freq)"
```

---

### Task 11: `get_spectrum_psd` in spectrum.py

**MATLAB (app.m:7191-7240):**
```matlab
function [psd_mean, freq_vec] = get_spectrum_psd(F, sensor_list, weights, CFG)
    win_m = 10.0;
    dx_global = CFG.SPATIAL_RES;
    fs_global = 1 / dx_global;
    NFFT_global = round(win_m / dx_global);
    if NFFT_global < 4, NFFT_global = 4; end
    psd_sum = [];
    freq_vec = [];
    total_weight = 0;
    for s = 1:length(sensor_list)
        sn = sensor_list{s};
        w  = weights(s);
        if w < 1e-6 || ~isfield(F, sn), continue; end
        sig = double(F.(sn));
        sig = sig(:);
        if isempty(sig) || length(sig) < 4, continue; end
        N_campioni = length(sig);
        if N_campioni > NFFT_global
            start_idx = floor((N_campioni - NFFT_global)/2) + 1;
            sig = sig(start_idx : start_idx + NFFT_global - 1);
        end
        [pxx, f] = periodogram(sig, hamming(length(sig)), NFFT_global, fs_global);
        if isempty(freq_vec)
            freq_vec = f;
            psd_sum = zeros(size(pxx));
        end
        if length(f) ~= length(freq_vec)
            pxx = interp1(f, pxx, freq_vec, 'linear', 0);
        end
        psd_sum = psd_sum + (pxx * w);
        total_weight = total_weight + w;
    end
    if isempty(psd_sum) || total_weight < 1e-6
        psd_mean = [];
        freq_vec = [];
    else
        psd_mean = psd_sum / total_weight;
    end
end
```

**CRITICAL equivalence notes for the reviewer (the invariant constraint lives here):**

1. **`NFFT_global = round(win_m / dx_global)`** — `win_m=10.0`, `dx_global=CFG.SPATIAL_RES=0.004` → `10/0.004 = 2500.0` exactly, so `round` → `2500`. Use `_matlab_round`-equivalent only if you ever pass non-exact values; for the literal default this is an exact integer. Implement with the round-half-away-from-zero rule to be safe (reuse the existing helper or `int(np.floor(x + 0.5))` for positive `x`).
2. **Center crop (1-based → 0-based):** `start_idx = floor((N - NFFT)/2) + 1` is 1-based. The MATLAB slice `sig(start_idx : start_idx+NFFT-1)`. In 0-based Python: `start0 = (N - NFFT) // 2` (floor division on a non-negative numerator), slice `sig[start0 : start0 + NFFT]`. This mirrors the off-by-one fix already applied in Piano 1's database builder.
3. **`periodogram(sig, hamming(L), NFFT, fs)`** — MATLAB defaults: one-sided PSD, **no detrending**, window applied before FFT. SciPy equivalent:
   `periodogram(sig, fs=fs_global, window=hamming(len(sig), sym=True), nfft=NFFT_global, detrend=False, return_onesided=True, scaling='density')`.
   - `detrend=False` is **required** — SciPy's default `detrend='constant'` removes the mean, which MATLAB `periodogram` does NOT do. This is the single highest-risk divergence; the reviewer must confirm it.
   - `scaling='density'` = PSD (matches MATLAB default 'psd').
   - `hamming(L, sym=True)` matches MATLAB `hamming(L)` (symmetric by default).
4. **Interp branch:** only triggers when `len(f) != len(freq_vec)`; with a fixed `NFFT` and `fs` across sensors this is essentially never hit, but replicate it with `interp1_zero(f, pxx, freq_vec)`.
5. **Empty handling:** if no sensor contributed (`psd_sum` empty or `total_weight < 1e-6`), return `(None, None)` — Python equivalent of MATLAB's `[]`/`[]`.
6. **Weighting:** `psd_sum += pxx * w`, then `psd_mean = psd_sum / total_weight`. Weighted mean, not sum.

**Files:**
- Modify: `railway_inspector/app/analysis/spectrum.py`
- Test: `tests/app/analysis/test_spectrum.py`

- [ ] **Step 1: Append the failing tests**

```python
from railway_inspector.app.analysis.spectrum import get_spectrum_psd


def test_get_spectrum_psd_no_valid_sensor_returns_none():
    cfg = default_config()
    psd, freq = get_spectrum_psd({}, ["s1"], [1.0], cfg)
    assert psd is None and freq is None


def test_get_spectrum_psd_zero_weight_skipped():
    cfg = default_config()
    F = {"s1": np.random.default_rng(0).standard_normal(3000)}
    psd, freq = get_spectrum_psd(F, ["s1"], [0.0], cfg)  # weight below 1e-6
    assert psd is None and freq is None


def test_get_spectrum_psd_short_signal_skipped():
    cfg = default_config()
    F = {"s1": np.array([1.0, 2.0, 3.0])}  # length 3 < 4
    psd, freq = get_spectrum_psd(F, ["s1"], [1.0], cfg)
    assert psd is None and freq is None


def test_get_spectrum_psd_matches_scipy_periodogram_single_sensor():
    cfg = default_config()
    rng = np.random.default_rng(42)
    sig = rng.standard_normal(2500)  # exactly NFFT, no cropping
    F = {"s1": sig}
    psd, freq = get_spectrum_psd(F, ["s1"], [2.0], cfg)

    from scipy.signal import periodogram as _pg
    from scipy.signal.windows import hamming as _ham
    fs = 1.0 / cfg.SPATIAL_RES
    pxx, f = _pg(sig, fs=fs, window=_ham(2500, sym=True), nfft=2500,
                 detrend=False, return_onesided=True, scaling="density")
    # single sensor: weighted mean == pxx (weight cancels)
    np.testing.assert_allclose(psd, pxx, rtol=1e-9, atol=1e-12)
    np.testing.assert_allclose(freq, f, rtol=1e-9, atol=1e-12)


def test_get_spectrum_psd_center_crops_long_signal():
    cfg = default_config()
    rng = np.random.default_rng(1)
    sig = rng.standard_normal(3000)  # > NFFT 2500 -> center crop
    F = {"s1": sig}
    psd, freq = get_spectrum_psd(F, ["s1"], [1.0], cfg)

    start0 = (3000 - 2500) // 2
    cropped = sig[start0:start0 + 2500]
    from scipy.signal import periodogram as _pg
    from scipy.signal.windows import hamming as _ham
    fs = 1.0 / cfg.SPATIAL_RES
    pxx, _f = _pg(cropped, fs=fs, window=_ham(2500, sym=True), nfft=2500,
                  detrend=False, return_onesided=True, scaling="density")
    np.testing.assert_allclose(psd, pxx, rtol=1e-9, atol=1e-12)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/app/analysis/test_spectrum.py -k get_spectrum_psd -v`
Expected: FAIL with `ImportError: cannot import name 'get_spectrum_psd'`

- [ ] **Step 3: Append the implementation to spectrum.py**

```python
def _matlab_round_pos(x: float) -> int:
    """Round half-away-from-zero for non-negative x (MATLAB round)."""
    return int(np.floor(x + 0.5))


def get_spectrum_psd(F: dict, sensor_list, weights, cfg):
    """Amplitude-weighted mean one-sided PSD over a sensor list (app.m:7191).

    Returns (psd_mean, freq_vec) as np.ndarray, or (None, None) when no sensor
    contributed. Fixed 10 m analysis window -> NFFT = round(10 / SPATIAL_RES).
    """
    win_m = 10.0
    dx_global = cfg.SPATIAL_RES
    fs_global = 1.0 / dx_global
    nfft = _matlab_round_pos(win_m / dx_global)
    if nfft < 4:
        nfft = 4

    psd_sum = None
    freq_vec = None
    total_weight = 0.0

    for sn, w in zip(sensor_list, weights):
        if w < 1e-6 or sn not in F:
            continue
        sig = np.asarray(F[sn], dtype=float).reshape(-1)
        if sig.size == 0 or sig.size < 4:
            continue

        n_campioni = sig.size
        if n_campioni > nfft:
            start0 = (n_campioni - nfft) // 2     # floor((N-NFFT)/2), 1-based -> 0-based
            sig = sig[start0:start0 + nfft]

        win = hamming(sig.size, sym=True)
        f, pxx = periodogram(sig, fs=fs_global, window=win, nfft=nfft,
                             detrend=False, return_onesided=True, scaling="density")

        if freq_vec is None:
            freq_vec = f
            psd_sum = np.zeros_like(pxx)

        if f.shape[0] != freq_vec.shape[0]:
            pxx = interp1_zero(f, pxx, freq_vec)

        psd_sum = psd_sum + pxx * w
        total_weight += w

    if psd_sum is None or total_weight < 1e-6:
        return None, None
    return psd_sum / total_weight, freq_vec
```

> **Note on SciPy return order:** `scipy.signal.periodogram` returns `(f, Pxx)`, the **reverse** of MATLAB's `[pxx, f]`. The code above unpacks `f, pxx = periodogram(...)` correctly — do not swap them.

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/app/analysis/test_spectrum.py -v`
Expected: PASS (all spectrum tests green)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/analysis/spectrum.py tests/app/analysis/test_spectrum.py
git commit -m "feat(app): get_spectrum_psd weighted periodogram (detrend=False, center crop)"
```

---

### Task 12: Full suite + analytical review gate

**Files:** none (verification task).

- [ ] **Step 1: Run the entire test suite**

Run: `pytest -q`
Expected: PASS — all Piano 1 tests (89) plus the new app foundation tests, 0 failures.

- [ ] **Step 2: Dispatch the math reviewer**

Per the project workflow, dispatch the `revisore-matematico` agent on the three new modules (`helpers.py`, `filters.py`, `spectrum.py`) against the MATLAB blocks cited in each task. The reviewer must confirm, at minimum:
- `get_spectrum_psd`: `detrend=False`, symmetric Hamming, NFFT, **center-crop 0-based index**, `(f, pxx)` unpack order, weighted-mean normalization.
- `get_sign_mean`: `mid = (N+1)//2` center and `half = N//4` slice bounds.
- `filter_defect_by_dates`: day-resolution comparison, swap guard, empty-window zeroing, `Detected` sum semantics.
- `sort_runs_by_direction`: population RMS over finite samples, tie → both False.
Do not consider the plan complete until the reviewer approves or all raised corrections are applied (re-run `pytest -q` after any fix).

- [ ] **Step 3: Update graphify and the progress memory**

Run: `graphify update .`
Then update `memory/database-builder-progress.md`: Piano 2 foundation layer (utils + spectrum) done; next sub-plan = IPI/PCA/AE math core.

- [ ] **Step 4: Final commit if anything changed in Step 2-3**

```bash
git add -A
git commit -m "chore(app): foundation layer reviewed + graph/memory updated"
```

---

## Self-Review (completed by plan author)

**1. Spec coverage (Section 3 `app/utils/` + `app/analysis/spectrum.py`):**
- `utils/helpers.py`: `helper_fft_shift` (T6), `get_amp` (T2), `get_max_rms` (T2), `sort_runs_by_direction` (T5), `safe_ratio` (T3), `get_sign_mean` (T4) — all covered.
- `utils/filters.py`: `filter_defect_by_dates` (T7), `filter_db_by_dates` (T8) — covered.
- `analysis/spectrum.py`: `get_spectrum_psd` (T11), `peak_lambda_from_spectrum` (T10), `lambda_to_label` (T9) — covered.
- `utils/datatips.py` (custom_datatip, master_datatip_fcn, classification_datatip) is GUI-event glue (needs PyQt/Matplotlib pick events) → deferred to the GUI sub-plan, not this foundation plan. Noted as out of scope here.

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to" — every code step contains complete code.

**3. Type consistency:** Data model is dict-based throughout; reused primitives use their verified real signatures (`movmean(x, k)`, `interp1_zero(x, y, xq)`, `shift_signal_frac(sig, shift_m, spatial_res)`). `cfg` is a `CFG` instance with `.SPATIAL_RES`, `.L_MAX`, `.L_MIN_QUIET`. Spectrum returns `(psd, freq)` consistently; `periodogram` unpack order flagged explicitly.

**Out of scope (later Piano 2 sub-plans):** IPI core/PCA/AE math, classification/drawing, widgets, single_analysis tabs, dialogs, main_window, run_app.py.
