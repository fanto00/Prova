# App IPI — PCA bonus model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Translate the PCA-based IPI bonus layer of `src_app/app.m` (`build_pca_model_standalone` + `compute_pca_bonus_for_defect`, app.m:6650-6836) into Python, fully unit-tested, preserving the channel-space PCA math exactly.

**Architecture:** One new module `railway_inspector/app/ipi/pca_model.py` containing the two public functions plus three small pure helpers (`_matlab_pca`, `_group_mean`, `_datenum`). Adds one reusable primitive `interp1_nan` to `railway_inspector/signal/resampling.py` (sibling of the existing `interp1_zero`) and the IPI/window constants to `railway_inspector/config.py`. Reuses Piano-1/foundation primitives: `movmean`, `sort_runs_by_direction`, `_matlab_round_pos`.

**Tech Stack:** Python 3.11+, NumPy (`np.linalg.svd`, `np.bincount`), pytest.

---

## Context for the implementer

This is **Piano 2 → sub-plan 2** (the GUI app's IPI math core). Piano 1 (database builder) and Piano 2 sub-plan 1 (foundation utils + spectrum) are complete and merged on `master`.

**Invariant constraint (non-negotiable):** the math must be numerically identical to the MATLAB original — same coefficients, same operation order, same edge-case handling, same 1-based→0-based index conversions. No MATLAB and no numerical fixtures exist; correctness is enforced by analytical line-by-line review (`revisore-matematico` agent). Unit tests verify *behavior, structure and internal consistency*, not parity against MATLAB output.

### Data model (dict-based, established in Piano 1)
- **Defect** = `dict` with key `History` (list) and others.
- **History entry** (a "run") = `dict` with keys `Date` (`datetime.datetime`), `Data` (dict), and others.
- **Data** = dict with `Filt` (dict: sensor-name → `np.ndarray`) and `RelativeAxis` (`np.ndarray`).

### Reusable primitives (import — do NOT reimplement)
- `from railway_inspector.detection.trigger import movmean`
- `from railway_inspector.app.utils.helpers import sort_runs_by_direction`
- `from railway_inspector.app.analysis.spectrum import _matlab_round_pos` — round-half-away-from-zero for non-negative x (already used in spectrum.py). If the reviewer prefers it not be imported from a `_private` name in another module, the implementer may instead inline the one-liner `int(np.floor(x + 0.5))`; either is acceptable, but do not write a third rounding rule.

### MATLAB → Python notes specific to this module
| MATLAB | Python |
|---|---|
| `pca(X, 'Economy', true)` | center columns, `np.linalg.svd(Xc, full_matrices=False)`; `coeffs = Vt.T`, `scores = U*S`; apply sign convention (see Task 3) |
| `std(X, 0, 1)` | `np.std(X, axis=0, ddof=1)` — MATLAB default normalizes by N-1 |
| `accumarray(idx, v, [n 1], @mean)` | group-mean by integer group id (Task 4) |
| `datenum(date)` | day count incl. fractional time; only **differences** and `floor`-to-day are used, so any consistent origin works (Task 5) |
| `issorted(a)` (ascending, equals allowed) | `np.all(np.diff(a) >= 0)` |
| `interp1(x, y, xq, 'linear', NaN)` | `interp1_nan` (Task 2): linear, NaN outside `[x[0], x[-1]]` |
| `mean(v, 'omitnan')` | `np.nanmean(v)` |
| `std(v, 'omitnan')` | `np.nanstd(v, ddof=1)` — MATLAB `std` default is N-1 |
| `sort(v)` | `np.argsort(v, kind='stable')` — MATLAB sort is stable |

---

## File Structure
- Modify: `railway_inspector/config.py` — add IPI + WINDOW_SIZE constants to `CFG`.
- Modify: `railway_inspector/signal/resampling.py` — add `interp1_nan`.
- Create: `railway_inspector/app/ipi/__init__.py` — package marker.
- Create: `railway_inspector/app/ipi/pca_model.py` — `build_pca_model_standalone`, `compute_pca_bonus_for_defect`, `_matlab_pca`, `_group_mean`, `_datenum`.
- Create (tests, FLAT in `tests/`): `tests/test_app_pca_model.py`. Add `interp1_nan` tests to existing `tests/test_resampling.py`, and IPI-constant test to existing `tests/test_config.py`.

---

### Task 1: Add IPI + WINDOW_SIZE constants to CFG

**MATLAB (app.m:39, 54-80) — the values to mirror:**
```
WINDOW_SIZE=5.0; IPI_MIN_RUNS=5; IPI_RECENT_DAYS=30; IPI_MIN_HISTORY_DAYS=45;
IPI_MIN_DAYS=10; IPI_TREND_MAX=100; IPI_TREND_SENS=80; IPI_LAT_BONUS=30;
IPI_LAT_THRESH=0.7; IPI_PCA_BONUS=20; IPI_PCA_SENS=50; IPI_PCA_EXCUR_BONUS=5;
IPI_PCA_EXCUR_DAYS=7; IPI_PCA_K=2; IPI_PCA_MIN_RUNS=30; IPI_CREST_BONUS=10;
IPI_IA_BONUS=20; IPI_SEV_PENALTY_MAX=20; IPI_SEV_THR_LOW=15; IPI_SEV_THR_HIGH=50;
```

**Files:**
- Modify: `railway_inspector/config.py` (add fields to the `CFG` dataclass, after the existing `MAX_TOTAL_RUNS` line)
- Test: `tests/test_config.py`

- [ ] **Step 1: Write the failing test** (append to `tests/test_config.py`)

```python
def test_cfg_has_ipi_constants():
    from railway_inspector.config import default_config
    c = default_config()
    assert c.WINDOW_SIZE == 5.0
    assert c.IPI_PCA_K == 2
    assert c.IPI_PCA_MIN_RUNS == 30
    assert c.IPI_PCA_BONUS == 20
    assert c.IPI_PCA_SENS == 50
    assert c.IPI_PCA_EXCUR_BONUS == 5
    assert c.IPI_PCA_EXCUR_DAYS == 7
    assert c.IPI_RECENT_DAYS == 30
    assert c.IPI_MIN_HISTORY_DAYS == 45
    assert c.IPI_MIN_DAYS == 10
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `python -m pytest tests/test_config.py::test_cfg_has_ipi_constants -v`
Expected: FAIL with `AttributeError: 'CFG' object has no attribute 'WINDOW_SIZE'`

- [ ] **Step 3: Add the constants to the CFG dataclass**

Insert after the `MAX_TOTAL_RUNS: int = 150` line in `railway_inspector/config.py`:
```python

    # --- IPI scoring (app.m:39, 54-80) ---
    WINDOW_SIZE: float = 5.0            # m, same as database
    IPI_MIN_RUNS: int = 5
    IPI_RECENT_DAYS: int = 30
    IPI_MIN_HISTORY_DAYS: int = 45
    IPI_MIN_DAYS: int = 10
    IPI_TREND_MAX: int = 100
    IPI_TREND_SENS: int = 80
    IPI_LAT_BONUS: int = 30
    IPI_LAT_THRESH: float = 0.7
    IPI_PCA_BONUS: int = 20
    IPI_PCA_SENS: int = 50
    IPI_PCA_EXCUR_BONUS: int = 5
    IPI_PCA_EXCUR_DAYS: int = 7
    IPI_PCA_K: int = 2
    IPI_PCA_MIN_RUNS: int = 30
    IPI_CREST_BONUS: int = 10
    IPI_IA_BONUS: int = 20
    IPI_SEV_PENALTY_MAX: int = 20
    IPI_SEV_THR_LOW: int = 15
    IPI_SEV_THR_HIGH: int = 50
```

- [ ] **Step 4: Run it, expect PASS**

Run: `python -m pytest tests/test_config.py -v`
Expected: PASS (existing config tests + the new one)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/config.py tests/test_config.py
git commit -m "feat(config): add IPI scoring + WINDOW_SIZE constants"
```

---

### Task 2: Add `interp1_nan` to resampling.py

**MATLAB:** `interp1(x, y, xq, 'linear', NaN)` — linear interpolation, query points strictly outside `[x[0], x[-1]]` become `NaN` (the extrap value passed). Identical to the existing `interp1_zero` except the fill value is `NaN` instead of `0.0`.

**Files:**
- Modify: `railway_inspector/signal/resampling.py` (add after `interp1_zero`)
- Test: `tests/test_resampling.py`

- [ ] **Step 1: Write the failing test** (append to `tests/test_resampling.py`)

```python
def test_interp1_nan_fills_outside_with_nan():
    import numpy as np
    from railway_inspector.signal.resampling import interp1_nan
    x = np.array([0.0, 1.0, 2.0])
    y = np.array([10.0, 20.0, 30.0])
    xq = np.array([-0.5, 0.5, 1.5, 2.5])
    out = interp1_nan(x, y, xq)
    assert np.isnan(out[0])
    assert out[1] == 15.0
    assert out[2] == 25.0
    assert np.isnan(out[3])
```

- [ ] **Step 2: Run it, expect FAIL**

Run: `python -m pytest tests/test_resampling.py::test_interp1_nan_fills_outside_with_nan -v`
Expected: FAIL with `ImportError: cannot import name 'interp1_nan'`

- [ ] **Step 3: Implement `interp1_nan`** (append in `resampling.py`, after `interp1_zero`)

```python
def interp1_nan(
    x: np.ndarray,
    y: np.ndarray,
    xq: np.ndarray,
) -> np.ndarray:
    """Piecewise-linear interpolation with NaN fill outside the data range.

    Replicates MATLAB ``interp1(x, y, xq, 'linear', NaN)``: query points
    strictly outside ``[x[0], x[-1]]`` are assigned NaN rather than 0 or an
    extrapolated value. Sibling of :func:`interp1_zero`.
    """
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    xq = np.asarray(xq, dtype=float)

    return np.interp(xq, x, y, left=np.nan, right=np.nan)
```

- [ ] **Step 4: Run it, expect PASS**

Run: `python -m pytest tests/test_resampling.py -v`
Expected: PASS (existing resampling tests + the new one)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/signal/resampling.py tests/test_resampling.py
git commit -m "feat(signal): add interp1_nan (linear, NaN extrapolation)"
```

---

### Task 3: `_matlab_pca` + `_group_mean` + `_datenum` helpers and package marker

**Files:**
- Create: `railway_inspector/app/ipi/__init__.py`
- Create: `railway_inspector/app/ipi/pca_model.py` (helpers only in this task)
- Test: `tests/test_app_pca_model.py`

**MATLAB reference for `_matlab_pca`:** `pca(Xpar_z, 'Economy', true)` returns `[coeffs, scores]`. MATLAB `pca`:
1. centers each column (subtracts the column mean) before decomposition;
2. computes the SVD of the centered data;
3. returns `coeffs` (principal directions, columns) and `scores = Xc * coeffs`;
4. **sign convention:** each `coeffs` column is sign-flipped so that its largest-magnitude element is positive (scores flipped accordingly).

For the tall matrix here (rows = n_valid·333 ≫ 6 columns), all 6 components are returned. The downstream residual reconstruction `scores[:,k:] @ coeffs[:,k:].T` is sign-invariant, but the sign convention is reproduced for full fidelity of returned `scores`.

**MATLAB reference for `_group_mean`:** `accumarray(run_id, v, [n_valid 1], @mean)` — group the values of `v` by integer group id `run_id` and return the per-group mean as a length-`n_valid` vector.

- [ ] **Step 1: Write the failing tests** (`tests/test_app_pca_model.py`)

```python
import numpy as np
import pytest
from railway_inspector.app.ipi.pca_model import _matlab_pca, _group_mean, _datenum
import datetime as dt


def test_group_mean_basic():
    run_id = np.array([0, 0, 1, 2, 2, 2])
    v = np.array([2.0, 4.0, 9.0, 1.0, 2.0, 3.0])
    out = _group_mean(run_id, v, 3)
    np.testing.assert_allclose(out, [3.0, 9.0, 2.0])


def test_matlab_pca_reconstruction_full_rank():
    # full reconstruction (all components) returns the centered data
    rng = np.random.default_rng(0)
    X = rng.standard_normal((200, 6))
    coeffs, scores = _matlab_pca(X)
    Xc = X - X.mean(axis=0)
    np.testing.assert_allclose(scores @ coeffs.T, Xc, atol=1e-10)


def test_matlab_pca_coeffs_orthonormal():
    rng = np.random.default_rng(1)
    X = rng.standard_normal((200, 6))
    coeffs, _ = _matlab_pca(X)
    # columns orthonormal
    np.testing.assert_allclose(coeffs.T @ coeffs, np.eye(coeffs.shape[1]), atol=1e-10)


def test_matlab_pca_sign_convention():
    rng = np.random.default_rng(2)
    X = rng.standard_normal((200, 6))
    coeffs, _ = _matlab_pca(X)
    for j in range(coeffs.shape[1]):
        col = coeffs[:, j]
        assert col[np.argmax(np.abs(col))] > 0  # largest-magnitude element positive


def test_datenum_difference_is_days():
    d1 = dt.datetime(2026, 1, 1, 0, 0)
    d2 = dt.datetime(2026, 1, 11, 12, 0)
    assert _datenum(d2) - _datenum(d1) == pytest.approx(10.5)
    assert np.floor(_datenum(d2)) - np.floor(_datenum(d1)) == 10
```

- [ ] **Step 2: Run them, expect FAIL**

Run: `python -m pytest tests/test_app_pca_model.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'railway_inspector.app.ipi'`

- [ ] **Step 3: Create the package marker and helpers**

`railway_inspector/app/ipi/__init__.py`:
```python
"""IPI scoring math (PCA / AE bonuses, core score) — no GUI."""
```

`railway_inspector/app/ipi/pca_model.py`:
```python
"""PCA-based IPI bonus (port of app.m:6650-6836).

Channel-space ("parallel") PCA over per-channel RMS envelopes, plus the
RMSE-trend and excursion bonus computation. Pure NumPy, no GUI.
"""
from __future__ import annotations

import datetime as dt

import numpy as np

from railway_inspector.detection.trigger import movmean
from railway_inspector.signal.resampling import interp1_nan
from railway_inspector.app.utils.helpers import sort_runs_by_direction


def _datenum(date: dt.datetime) -> float:
    """MATLAB datenum-like day count (relative use only: differences + floor)."""
    if isinstance(date, dt.datetime):
        frac = (date - dt.datetime(date.year, date.month, date.day)).total_seconds() / 86400.0
        return date.toordinal() + frac
    return dt.datetime(date.year, date.month, date.day).toordinal()


def _group_mean(group_id: np.ndarray, values: np.ndarray, n_groups: int) -> np.ndarray:
    """accumarray(group_id, values, [n_groups 1], @mean) — per-group mean."""
    group_id = np.asarray(group_id, dtype=int)
    values = np.asarray(values, dtype=float)
    sums = np.bincount(group_id, weights=values, minlength=n_groups)
    counts = np.bincount(group_id, minlength=n_groups)
    counts_safe = np.where(counts == 0, 1, counts)
    return sums / counts_safe


def _matlab_pca(X: np.ndarray):
    """Replicate MATLAB pca(X, 'Economy', true) -> (coeffs, scores).

    Centers columns, SVD, coeffs = right singular vectors, scores = Xc @ coeffs,
    with MATLAB's sign convention (largest-magnitude coeff element positive).
    """
    X = np.asarray(X, dtype=float)
    Xc = X - X.mean(axis=0)
    U, S, Vt = np.linalg.svd(Xc, full_matrices=False)
    coeffs = Vt.T
    scores = U * S
    for j in range(coeffs.shape[1]):
        idx = int(np.argmax(np.abs(coeffs[:, j])))
        if coeffs[idx, j] < 0:
            coeffs[:, j] = -coeffs[:, j]
            scores[:, j] = -scores[:, j]
    return coeffs, scores
```

- [ ] **Step 4: Run them, expect PASS**

Run: `python -m pytest tests/test_app_pca_model.py -v`
Expected: PASS (5 passed)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/ipi/__init__.py railway_inspector/app/ipi/pca_model.py tests/test_app_pca_model.py
git commit -m "feat(app): IPI pca_model helpers (_matlab_pca, _group_mean, _datenum)"
```

---

### Task 4: `build_pca_model_standalone`

**MATLAB (app.m:6650-6755):**
```matlab
function M = build_pca_model_standalone(History, run_idx, direction, ...
                                         spatial_res, window_size, win_m, MIN_RUNS, k_pca)
    M = [];
    n_sel = numel(run_idx);
    if n_sel < MIN_RUNS, return; end
    N_GRID = 333; n_chan = 6;
    x_grid = linspace(-window_size, window_size, N_GRID);
    win_samples = max(3, round(win_m / spatial_res));
    switch lower(direction)
        case 'forward'
            lat_F_field = 'right_sensor_front_lat'; lat_R_field = 'right_sensor_rear_lat';
        case 'backward'
            lat_F_field = 'left_sensor_front_lat';  lat_R_field = 'left_sensor_rear_lat';
        otherwise, return;
    end
    chan_fields = {'left_sensor_front', 'right_sensor_front', lat_F_field, ...
                   'left_sensor_rear', 'right_sensor_rear', lat_R_field};
    Xraw = nan(n_sel, n_chan*N_GRID); dates_v = nan(n_sel,1); valid_v = false(n_sel,1);
    for k = 1:n_sel
        i = run_idx(k); run_i = History(i);
        dates_v(k) = datenum(run_i.Date);
        d = run_i.Data;
        if ~isfield(d, 'Filt'), continue; end
        if ~isfield(d, 'RelativeAxis') || isempty(d.RelativeAxis), continue; end
        ax_src = double(d.RelativeAxis(:));
        if ~issorted(ax_src) || any(~isfinite(ax_src)), continue; end
        Fd = d.Filt;
        row = nan(1, n_chan*N_GRID); row_ok = true;
        for c = 1:n_chan
            fn = chan_fields{c};
            if ~isfield(Fd, fn) || isempty(Fd.(fn)), row_ok = false; break; end
            sig = double(Fd.(fn)(:));
            if length(sig) ~= length(ax_src) || numel(sig) < 10, row_ok = false; break; end
            env = sqrt(movmean(sig.^2, win_samples));
            env_g = interp1(ax_src, env, x_grid, 'linear', NaN);
            if any(~isfinite(env_g)), row_ok = false; break; end
            row((c-1)*N_GRID + 1 : c*N_GRID) = env_g;
        end
        if row_ok, Xraw(k, :) = row; valid_v(k) = true; end
    end
    Xraw = Xraw(valid_v, :); dates_v = dates_v(valid_v);
    n_valid = size(Xraw, 1);
    if n_valid < MIN_RUNS, return; end
    Nrows = n_valid * N_GRID;
    Xpar  = zeros(Nrows, n_chan); run_id = zeros(Nrows, 1);
    for r = 1:n_valid
        base = (r-1)*N_GRID;
        run_id(base+1 : base+N_GRID) = r;
        for c = 1:n_chan
            cols = (c-1)*N_GRID + 1 : c*N_GRID;
            Xpar(base+1 : base+N_GRID, c) = Xraw(r, cols).';
        end
    end
    mu_ch = mean(Xpar, 1); sg_ch = std(Xpar, 0, 1);
    sg_ch(sg_ch < 1e-9) = 1;
    Xpar_z = (Xpar - mu_ch) ./ sg_ch;
    try
        [coeffs, scores] = pca(Xpar_z, 'Economy', true);
    catch
        return;
    end
    k_use = min(k_pca, size(coeffs, 2));
    resid_z  = scores(:, k_use+1:end) * coeffs(:, k_use+1:end)';
    se_row   = mean(resid_z.^2, 2);
    rmse_run = sqrt(accumarray(run_id, se_row, [n_valid 1], @mean));
    P = size(scores, 2); scores_run = zeros(n_valid, P);
    for j = 1:P
        scores_run(:, j) = accumarray(run_id, scores(:, j), [n_valid 1], @mean);
    end
    [dates_sorted, ord] = sort(dates_v);
    rmse_sorted = rmse_run(ord); scores_sorted = scores_run(ord, :);
    M = struct('coeffs',coeffs,'scores',scores_sorted,'dates',dates_sorted, ...
               'rmse',rmse_sorted,'n_valid',n_valid);
end
```

**Index notes:** `run_idx` holds 1-based indices in MATLAB; in Python the caller passes 0-based positions into `History`. `accumarray` group ids are 1-based in MATLAB; use 0-based `run_id` (r = 0..n_valid-1) in Python so `np.bincount` lines up. `k_use = min(k_pca, P)`; residual uses components `k_use:` (Python slice = MATLAB `k_use+1:end`). Return `None` on any early exit (MATLAB `M = []`).

**Files:**
- Modify: `railway_inspector/app/ipi/pca_model.py`
- Test: `tests/test_app_pca_model.py`

- [ ] **Step 1: Write the failing tests**

```python
import datetime as dt
from railway_inspector.app.ipi.pca_model import build_pca_model_standalone

N_GRID_REF = 333

def _make_run(date, n_samples=400, scale=1.0, seed=0):
    rng = np.random.default_rng(seed)
    ax = np.linspace(-5.0, 5.0, n_samples)  # sorted, finite
    sensors = ['left_sensor_front', 'right_sensor_front', 'right_sensor_front_lat',
               'left_sensor_rear', 'right_sensor_rear', 'right_sensor_rear_lat']
    filt = {s: scale * rng.standard_normal(n_samples) for s in sensors}
    return {"Date": date, "Data": {"Filt": filt, "RelativeAxis": ax}}


def test_build_pca_returns_none_below_min_runs():
    hist = [_make_run(dt.datetime(2026, 1, 1))]
    out = build_pca_model_standalone(hist, [0], "forward", 0.004, 5.0, 0.5, 30, 2)
    assert out is None


def test_build_pca_returns_none_bad_direction():
    hist = [_make_run(dt.datetime(2026, 1, 1)) for _ in range(5)]
    out = build_pca_model_standalone(hist, list(range(5)), "sideways", 0.004, 5.0, 0.5, 3, 2)
    assert out is None


def test_build_pca_model_shapes_and_sort():
    base = dt.datetime(2026, 1, 1)
    # build out of order dates to verify sorting; 6 valid runs, MIN_RUNS=3
    hist = [_make_run(base + dt.timedelta(days=d), seed=d) for d in [5, 1, 3, 0, 4, 2]]
    out = build_pca_model_standalone(hist, list(range(6)), "forward", 0.004, 5.0, 0.5, 3, 2)
    assert out is not None
    assert out["n_valid"] == 6
    assert out["rmse"].shape == (6,)
    assert out["dates"].shape == (6,)
    assert out["scores"].shape[0] == 6
    assert out["coeffs"].shape[0] == 6  # n_chan
    # dates sorted ascending
    assert np.all(np.diff(out["dates"]) >= 0)
    # rmse is non-negative (sqrt of mean square residual)
    assert np.all(out["rmse"] >= 0)


def test_build_pca_skips_run_with_mismatched_axis():
    base = dt.datetime(2026, 1, 1)
    hist = [_make_run(base + dt.timedelta(days=d), seed=d) for d in range(4)]
    # corrupt one run: signal length != RelativeAxis length -> run dropped
    bad = hist[2]
    for s in bad["Data"]["Filt"]:
        bad["Data"]["Filt"][s] = bad["Data"]["Filt"][s][:-5]
    out = build_pca_model_standalone(hist, list(range(4)), "forward", 0.004, 5.0, 0.5, 3, 2)
    assert out is not None
    assert out["n_valid"] == 3  # the corrupted run was excluded
```

- [ ] **Step 2: Run them, expect FAIL**

Run: `python -m pytest tests/test_app_pca_model.py -k build_pca -v`
Expected: FAIL with `ImportError: cannot import name 'build_pca_model_standalone'`

- [ ] **Step 3: Implement** (append to `pca_model.py`)

```python
def build_pca_model_standalone(History, run_idx, direction, spatial_res,
                               window_size, win_m, MIN_RUNS, k_pca):
    """Channel-space PCA model over per-channel RMS envelopes (app.m:6650).

    Returns a dict with keys coeffs, scores, dates, rmse, n_valid, or None on
    any early exit (too few runs, bad direction, decomposition failure).
    """
    n_sel = len(run_idx)
    if n_sel < MIN_RUNS:
        return None
    N_GRID = 333
    n_chan = 6
    x_grid = np.linspace(-window_size, window_size, N_GRID)
    win_samples = max(3, _matlab_round_pos(win_m / spatial_res))

    dir_l = direction.lower()
    if dir_l == "forward":
        lat_F_field, lat_R_field = "right_sensor_front_lat", "right_sensor_rear_lat"
    elif dir_l == "backward":
        lat_F_field, lat_R_field = "left_sensor_front_lat", "left_sensor_rear_lat"
    else:
        return None
    chan_fields = ["left_sensor_front", "right_sensor_front", lat_F_field,
                   "left_sensor_rear", "right_sensor_rear", lat_R_field]

    Xraw = np.full((n_sel, n_chan * N_GRID), np.nan)
    dates_v = np.full(n_sel, np.nan)
    valid_v = np.zeros(n_sel, dtype=bool)

    for k in range(n_sel):
        run_i = History[run_idx[k]]
        dates_v[k] = _datenum(run_i["Date"])
        d = run_i["Data"]
        if "Filt" not in d:
            continue
        if "RelativeAxis" not in d or len(d["RelativeAxis"]) == 0:
            continue
        ax_src = np.asarray(d["RelativeAxis"], dtype=float).reshape(-1)
        if not np.all(np.diff(ax_src) >= 0) or np.any(~np.isfinite(ax_src)):
            continue
        Fd = d["Filt"]
        row = np.full(n_chan * N_GRID, np.nan)
        row_ok = True
        for c in range(n_chan):
            fn = chan_fields[c]
            if fn not in Fd or len(Fd[fn]) == 0:
                row_ok = False
                break
            sig = np.asarray(Fd[fn], dtype=float).reshape(-1)
            if sig.size != ax_src.size or sig.size < 10:
                row_ok = False
                break
            env = np.sqrt(movmean(sig**2, win_samples))
            env_g = interp1_nan(ax_src, env, x_grid)
            if np.any(~np.isfinite(env_g)):
                row_ok = False
                break
            row[c * N_GRID:(c + 1) * N_GRID] = env_g
        if row_ok:
            Xraw[k, :] = row
            valid_v[k] = True

    Xraw = Xraw[valid_v, :]
    dates_v = dates_v[valid_v]
    n_valid = Xraw.shape[0]
    if n_valid < MIN_RUNS:
        return None

    # Parallel rearrangement: rows = (run x position), columns = channel
    Nrows = n_valid * N_GRID
    Xpar = np.zeros((Nrows, n_chan))
    run_id = np.zeros(Nrows, dtype=int)
    for r in range(n_valid):
        base = r * N_GRID
        run_id[base:base + N_GRID] = r
        for c in range(n_chan):
            Xpar[base:base + N_GRID, c] = Xraw[r, c * N_GRID:(c + 1) * N_GRID]

    mu_ch = np.mean(Xpar, axis=0)
    sg_ch = np.std(Xpar, axis=0, ddof=1)
    sg_ch[sg_ch < 1e-9] = 1
    Xpar_z = (Xpar - mu_ch) / sg_ch

    try:
        coeffs, scores = _matlab_pca(Xpar_z)
    except np.linalg.LinAlgError:
        return None

    k_use = min(k_pca, coeffs.shape[1])
    resid_z = scores[:, k_use:] @ coeffs[:, k_use:].T
    se_row = np.mean(resid_z**2, axis=1)
    rmse_run = np.sqrt(_group_mean(run_id, se_row, n_valid))

    P = scores.shape[1]
    scores_run = np.zeros((n_valid, P))
    for j in range(P):
        scores_run[:, j] = _group_mean(run_id, scores[:, j], n_valid)

    ord_ = np.argsort(dates_v, kind="stable")
    return {
        "coeffs": coeffs,
        "scores": scores_run[ord_, :],
        "dates": dates_v[ord_],
        "rmse": rmse_run[ord_],
        "n_valid": n_valid,
    }
```

Add the rounding import at the top of `pca_model.py` (with the other imports):
```python
from railway_inspector.app.analysis.spectrum import _matlab_round_pos
```

- [ ] **Step 4: Run them, expect PASS**

Run: `python -m pytest tests/test_app_pca_model.py -k build_pca -v`
Expected: PASS (4 passed)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/ipi/pca_model.py tests/test_app_pca_model.py
git commit -m "feat(app): build_pca_model_standalone (channel-space PCA + RMSE)"
```

---

### Task 5: `compute_pca_bonus_for_defect`

**MATLAB (app.m:6760-6836):**
```matlab
function [bonus_pca, info] = compute_pca_bonus_for_defect(Defect, C)
    bonus_pca = 0;
    info = struct('direction_used','none', 'k_pca',C.IPI_PCA_K, ...
                  'rmse_base',NaN, 'rmse_recent',NaN, 'pca_inc_perc',0, ...
                  'n_excursions',0, 'bonus_trend',0, 'bonus_excursion',0);
    History = Defect.History;
    if length(History) < C.IPI_PCA_MIN_RUNS, return; end
    [idx_fwd, idx_bwd] = sort_runs_by_direction(History);
    M = [];
    if sum(idx_fwd) >= sum(idx_bwd) && sum(idx_fwd) >= C.IPI_PCA_MIN_RUNS
        M = build_pca_model_standalone(History, find(idx_fwd), 'forward', ...
              C.SPATIAL_RES, C.WINDOW_SIZE, 0.5, C.IPI_PCA_MIN_RUNS, C.IPI_PCA_K);
        info.direction_used = 'forward';
    end
    if isempty(M) && sum(idx_bwd) >= C.IPI_PCA_MIN_RUNS
        M = build_pca_model_standalone(History, find(idx_bwd), 'backward', ...
              C.SPATIAL_RES, C.WINDOW_SIZE, 0.5, C.IPI_PCA_MIN_RUNS, C.IPI_PCA_K);
        info.direction_used = 'backward';
    end
    if isempty(M), return; end
    rmse_k = M.rmse;
    days_v   = floor(M.dates);
    days_un  = unique(days_v);
    n_days   = length(days_un);
    history_span = days_un(end) - days_un(1);
    if history_span < C.IPI_MIN_HISTORY_DAYS, return; end
    if n_days < C.IPI_MIN_DAYS, return; end
    rmse_daily = zeros(n_days, 1);
    for dd = 1:n_days
        rmse_daily(dd) = mean(rmse_k(days_v == days_un(dd)), 'omitnan');
    end
    cutoff_day  = days_un(end) - C.IPI_RECENT_DAYS;
    mask_recent = days_un >  cutoff_day;
    mask_base   = days_un <= cutoff_day;
    if ~any(mask_recent) || ~any(mask_base), return; end
    rmse_base   = mean(rmse_daily(mask_base),   'omitnan');
    rmse_recent = mean(rmse_daily(mask_recent), 'omitnan');
    bonus_trend = 0; pca_inc = 0;
    if rmse_base > 1e-9
        pca_inc     = ((rmse_recent - rmse_base) / rmse_base) * 100;
        bonus_trend = min(C.IPI_PCA_BONUS, max(0, pca_inc * (C.IPI_PCA_BONUS / C.IPI_PCA_SENS)));
    end
    base_runs = days_v <= cutoff_day;
    mu_b = mean(rmse_k(base_runs), 'omitnan');
    sg_b = std(rmse_k(base_runs), 'omitnan');
    thr  = mu_b + 2*sg_b;
    last_d   = max(M.dates);
    rec_mask = (M.dates >= last_d - C.IPI_PCA_EXCUR_DAYS);
    n_excur  = sum(rmse_k(rec_mask) > thr);
    bonus_excur = 0;
    if n_excur > 0
        bonus_excur = min(C.IPI_PCA_EXCUR_BONUS, n_excur * (C.IPI_PCA_EXCUR_BONUS / 3));
    end
    bonus_pca = bonus_trend + bonus_excur;
    info.rmse_base = rmse_base; info.rmse_recent = rmse_recent;
    info.pca_inc_perc = pca_inc; info.n_excursions = n_excur;
    info.bonus_trend = bonus_trend; info.bonus_excursion = bonus_excur;
end
```

**Notes:**
- `find(idx_fwd)` → `np.flatnonzero(idx_fwd)` (0-based positions). `sum(idx_fwd)` → `int(idx_fwd.sum())`.
- `info` is a dict initialized exactly as the MATLAB struct (string `'none'`, `k_pca` from config, `NaN`s, zeros). On every early return, the partially-filled `info` is returned alongside `bonus_pca`.
- `days_v = floor(M.dates)` (`np.floor`), `days_un = np.unique(days_v)` (sorted ascending). `days_un[-1]`/`days_un[0]` are end/start.
- `'omitnan'` means `np.nanmean`; `std(...,'omitnan')` is `np.nanstd(..., ddof=1)` (MATLAB std default N-1). For the per-day mean over a boolean mask, use `np.nanmean(rmse_k[mask])`.
- Forward is attempted when `sum(idx_fwd) >= sum(idx_bwd)` AND `sum(idx_fwd) >= MIN_RUNS`; `info.direction_used` is set to `'forward'` inside that branch even if the model build returns None (mirror MATLAB exactly — the assignment is unconditional inside the `if`). Backward is attempted only if `M is None` and `sum(idx_bwd) >= MIN_RUNS`.
- Return type: `(bonus_pca: float, info: dict)`.

**Files:**
- Modify: `railway_inspector/app/ipi/pca_model.py`
- Test: `tests/test_app_pca_model.py`

- [ ] **Step 1: Write the failing tests**

```python
from railway_inspector.app.ipi.pca_model import compute_pca_bonus_for_defect
from railway_inspector.config import default_config


def test_compute_pca_bonus_too_few_runs_returns_zero():
    cfg = default_config()
    defect = {"History": [_make_run(dt.datetime(2026, 1, 1)) for _ in range(3)]}
    bonus, info = compute_pca_bonus_for_defect(defect, cfg)
    assert bonus == 0
    assert info["direction_used"] == "none"
    assert info["k_pca"] == cfg.IPI_PCA_K
    assert info["bonus_trend"] == 0
    assert info["bonus_excursion"] == 0


def _forward_run(date, scale, seed):
    # forward orientation: right front lateral RMS must exceed left front lateral.
    r = _make_run(date, scale=scale, seed=seed)
    n = r["Data"]["RelativeAxis"].size
    rng = np.random.default_rng(seed + 999)
    r["Data"]["Filt"]["right_sensor_front_lat"] = 3.0 * scale * rng.standard_normal(n)
    r["Data"]["Filt"]["left_sensor_front_lat"] = 0.1 * scale * rng.standard_normal(n)
    return r


def test_compute_pca_bonus_full_scenario_trend_positive():
    cfg = default_config()
    base = dt.datetime(2026, 1, 1)
    runs = []
    # 40 forward runs over 60 days; envelope amplitude grows in the recent window
    # so recent RMSE > base RMSE -> positive trend bonus.
    for i in range(40):
        day = int(i * 60 / 39)               # spread across 0..60 days (>45 span, >=10 days)
        scale = 1.0 if day <= 30 else 3.0    # amplify after cutoff day
        runs.append(_forward_run(base + dt.timedelta(days=day), scale=scale, seed=i))
    defect = {"History": runs}
    bonus, info = compute_pca_bonus_for_defect(defect, cfg)
    assert info["direction_used"] == "forward"
    assert bonus >= 0
    assert 0 <= info["bonus_trend"] <= cfg.IPI_PCA_BONUS
    assert 0 <= info["bonus_excursion"] <= cfg.IPI_PCA_EXCUR_BONUS
    assert info["bonus_trend"] + info["bonus_excursion"] == pytest.approx(bonus)
```

> Note: the trend test asserts the bonus is in range and consistent (not an exact value — the invariant is verified analytically, not numerically). If `direction_used` is `'forward'` but the model can't be built (e.g. fewer than 30 valid forward runs after filtering), increase the run count; the orientation helper requires the right-front-lateral RMS to dominate, which `_forward_run` guarantees.

- [ ] **Step 2: Run them, expect FAIL**

Run: `python -m pytest tests/test_app_pca_model.py -k compute_pca_bonus -v`
Expected: FAIL with `ImportError: cannot import name 'compute_pca_bonus_for_defect'`

- [ ] **Step 3: Implement** (append to `pca_model.py`)

```python
def compute_pca_bonus_for_defect(Defect, C):
    """PCA RMSE-trend + excursion bonus for the IPI score (app.m:6760).

    Returns (bonus_pca, info) where info is the MATLAB-equivalent struct dict.
    """
    bonus_pca = 0
    info = {
        "direction_used": "none", "k_pca": C.IPI_PCA_K,
        "rmse_base": np.nan, "rmse_recent": np.nan, "pca_inc_perc": 0,
        "n_excursions": 0, "bonus_trend": 0, "bonus_excursion": 0,
    }
    History = Defect["History"]
    if len(History) < C.IPI_PCA_MIN_RUNS:
        return bonus_pca, info

    idx_fwd, idx_bwd = sort_runs_by_direction(History)
    n_fwd, n_bwd = int(idx_fwd.sum()), int(idx_bwd.sum())

    M = None
    if n_fwd >= n_bwd and n_fwd >= C.IPI_PCA_MIN_RUNS:
        M = build_pca_model_standalone(
            History, np.flatnonzero(idx_fwd), "forward",
            C.SPATIAL_RES, C.WINDOW_SIZE, 0.5, C.IPI_PCA_MIN_RUNS, C.IPI_PCA_K)
        info["direction_used"] = "forward"
    if M is None and n_bwd >= C.IPI_PCA_MIN_RUNS:
        M = build_pca_model_standalone(
            History, np.flatnonzero(idx_bwd), "backward",
            C.SPATIAL_RES, C.WINDOW_SIZE, 0.5, C.IPI_PCA_MIN_RUNS, C.IPI_PCA_K)
        info["direction_used"] = "backward"
    if M is None:
        return bonus_pca, info

    rmse_k = M["rmse"]
    days_v = np.floor(M["dates"])
    days_un = np.unique(days_v)
    n_days = len(days_un)
    history_span = days_un[-1] - days_un[0]
    if history_span < C.IPI_MIN_HISTORY_DAYS:
        return bonus_pca, info
    if n_days < C.IPI_MIN_DAYS:
        return bonus_pca, info

    rmse_daily = np.zeros(n_days)
    for dd in range(n_days):
        rmse_daily[dd] = np.nanmean(rmse_k[days_v == days_un[dd]])

    cutoff_day = days_un[-1] - C.IPI_RECENT_DAYS
    mask_recent = days_un > cutoff_day
    mask_base = days_un <= cutoff_day
    if not np.any(mask_recent) or not np.any(mask_base):
        return bonus_pca, info

    rmse_base = np.nanmean(rmse_daily[mask_base])
    rmse_recent = np.nanmean(rmse_daily[mask_recent])

    bonus_trend = 0
    pca_inc = 0
    if rmse_base > 1e-9:
        pca_inc = ((rmse_recent - rmse_base) / rmse_base) * 100
        bonus_trend = min(C.IPI_PCA_BONUS, max(0, pca_inc * (C.IPI_PCA_BONUS / C.IPI_PCA_SENS)))

    base_runs = days_v <= cutoff_day
    mu_b = np.nanmean(rmse_k[base_runs])
    sg_b = np.nanstd(rmse_k[base_runs], ddof=1)
    thr = mu_b + 2 * sg_b
    last_d = np.max(M["dates"])
    rec_mask = M["dates"] >= last_d - C.IPI_PCA_EXCUR_DAYS
    n_excur = int(np.sum(rmse_k[rec_mask] > thr))

    bonus_excur = 0
    if n_excur > 0:
        bonus_excur = min(C.IPI_PCA_EXCUR_BONUS, n_excur * (C.IPI_PCA_EXCUR_BONUS / 3))

    bonus_pca = bonus_trend + bonus_excur
    info["rmse_base"] = rmse_base
    info["rmse_recent"] = rmse_recent
    info["pca_inc_perc"] = pca_inc
    info["n_excursions"] = n_excur
    info["bonus_trend"] = bonus_trend
    info["bonus_excursion"] = bonus_excur
    return bonus_pca, info
```

- [ ] **Step 4: Run them, expect PASS**

Run: `python -m pytest tests/test_app_pca_model.py -k compute_pca_bonus -v`
Expected: PASS (2 passed)

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/app/ipi/pca_model.py tests/test_app_pca_model.py
git commit -m "feat(app): compute_pca_bonus_for_defect (RMSE trend + excursion)"
```

---

### Task 6: Full suite + analytical review gate

**Files:** none (verification task).

- [ ] **Step 1: Run the entire suite**

Run: `python -m pytest -q`
Expected: PASS — all prior tests plus the new pca_model / interp1_nan / config tests, 0 failures.

- [ ] **Step 2: Dispatch the math reviewer**

Dispatch `revisore-matematico` on `railway_inspector/app/ipi/pca_model.py` and the new `interp1_nan`, against MATLAB app.m:6650-6836. Must confirm at minimum:
- `_matlab_pca`: column-centering before SVD, `coeffs = Vt.T`, `scores = U*S`, sign convention; note the residual `scores[:,k:]@coeffs[:,k:].T` is sign-invariant.
- `build_pca_model_standalone`: `win_samples = max(3, round(win_m/spatial_res))`; channel field order per direction; per-channel z-score with `ddof=1` and the `<1e-9 → 1` guard; parallel rearrangement indexing; `k_use = min(k_pca, P)` and residual over components `k_use:`; `accumarray @mean` → `_group_mean`; stable sort by date; `interp1_nan` (NOT zero-fill); the run-validity filters (Filt present, RelativeAxis sorted+finite, length match, `< 10` samples, NaN in regridded env).
- `compute_pca_bonus_for_defect`: `MIN_RUNS` gate; direction selection (`>=` comparisons, unconditional `direction_used` assignment inside the forward branch); `floor` to days + `unique`; history-span / n-days gates; daily mean with `omitnan`; cutoff masks (`>` recent, `<=` base); trend formula and `min/max` clamps; excursion threshold `mu+2σ` with `ddof=1`; excursion window `>= last_d - EXCUR_DAYS`; bonus formulas and the `/3` divisor.
Do not close the task until APPROVED or all raised corrections are applied (re-run `pytest -q` after any fix).

- [ ] **Step 3: Dispatch the code-quality reviewer** (only after spec/math review passes)

Standard code-quality pass on the new module + the resampling/config edits (one responsibility per file, naming, type hints consistent with the codebase, tests meaningful, DRY reuse of `movmean`/`sort_runs_by_direction`/`_matlab_round_pos`).

- [ ] **Step 4: Update graphify + progress memory**

Run: `graphify update .`
Update `memory/database-builder-progress.md`: Piano 2 sub-plan 2 (IPI pca_model) done; next = AE bonus (needs decision on porting the MATLAB-trained autoencoder network) and the IPI core orchestration.

- [ ] **Step 5: Final commit if anything changed in Steps 2-4**

```bash
git add -A
git commit -m "chore(app): IPI pca_model reviewed + graph/memory updated"
```

---

## Self-Review (completed by plan author)

**1. Spec coverage:** Targets `app/ipi/pca_model.py` (`build_pca_model_standalone`, `compute_pca_bonus_for_defect`) from Section 3 of the design spec. `ipi/ae_model.py` and `ipi/ipi_core.py` are explicitly deferred (AE needs a decision on porting the MATLAB `network` object; `update_IPI_Score` is ~800 lines GUI-coupled). `interp1_nan` and the IPI constants are prerequisites pulled in here.

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"/"similar to". Every code step has complete code.

**3. Type/name consistency:** Model dict keys (`coeffs`, `scores`, `dates`, `rmse`, `n_valid`) are identical between Task 4 producer and Task 5 consumer. Helper names (`_matlab_pca`, `_group_mean`, `_datenum`) match between Task 3 definitions and Task 4/5 calls. `_matlab_round_pos` imported from `analysis.spectrum` (where it lives). Config constants referenced (`IPI_PCA_*`, `IPI_MIN_*`, `IPI_RECENT_DAYS`, `WINDOW_SIZE`, `SPATIAL_RES`) all added in Task 1.

**Out of scope (later sub-plans):** `ae_model.py` (AE bonus), `ipi_core.py` (`update_IPI_Score`), `analysis/classification.py`, `analysis/drawing.py`, all GUI widgets/dialogs/tabs.
```
