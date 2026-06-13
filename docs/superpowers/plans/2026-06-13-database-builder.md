# Database Builder — Implementation Plan (Piano 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Riscrivere in Python `src_database/Database_Allineamento_nomax.m` come pacchetto modulare (`railway_inspector/`) che produce un `MASTER_DB` con la stessa semantica del MATLAB, preservando esattamente filtraggio, allineamento e clustering.

**Architecture:** Pacchetto Python suddiviso per responsabilità (`config`, `io`, `signal`, `detection`, `database`). La matematica a rischio alto (`interpft`, `xcorr`, shift FFT, doppio `filtfilt`) vive in `signal/` e viene tradotta in serie con revisione rinforzata. Entry point `run_database.py`.

**Tech Stack:** Python 3.11+, NumPy, SciPy (`scipy.signal`, `scipy.io`, `scipy.stats`), pandas + openpyxl, pytest.

**Fonte di verità per la traduzione:** `src_database/Database_Allineamento_nomax.m`. Ogni task indica l'intervallo di righe MATLAB esatto. Il vincolo invariante: **la matematica non cambia** (stessi coefficienti, stesso ordine operazioni, stessa gestione edge case e indicizzazione).

**Nota sui test:** senza MATLAB non esistono fixture numeriche di riferimento. I test verificano **proprietà matematiche** (es. `interpft` di una sinusoide nota, correttezza dei lag di `xcorr`, idempotenza dello shift FFT con lag intero, risposta del filtro). Sono la rete di sicurezza Python; la revisione analitica riga-per-riga resta la difesa principale.

---

## File Structure

| File | Responsabilità | Sorgente MATLAB |
|---|---|---|
| `railway_inspector/config.py` | Dataclass `CFG` con tutti i parametri | righe 8-68 |
| `railway_inspector/signal/resampling.py` | `interpft`, `interp1_zero` (interp1 linear+extrap 0) | `interpft` usi a 214/687/1372; interp1 a 214/872/877 |
| `railway_inspector/signal/filtering.py` | `design_filters`, `filter_pipeline` (demean→filtfilt temporale→interp1 spaziale→filtfilt spaziale) | 855-880, 1073-1094 |
| `railway_inspector/signal/alignment.py` | `xcorr_lag`, `macro_align_shift`, `shift_signal_frac`, `shift_fill`, `build_align_template`, `hilbert_envelope`, micro-align xcorr | 226-230, 446-486, 1195-1224, 1314-1385 |
| `railway_inspector/io/mat_loader.py` | Caricamento `.mat` `section_extracted` in dict/struct | 156-167 |
| `railway_inspector/io/excel_loader.py` | `load_infrastructure_map`, `load_joints_map`, `to_num` | 1151-1166, 1283-1391 |
| `railway_inspector/io/database_io.py` | Salvataggio/caricamento `MASTER_DB` | 786 |
| `railway_inspector/detection/trigger.py` | RMS adattivo, `find_peaks`, raffinamento picco, merging | 852-934 |
| `railway_inspector/detection/extraction.py` | `analyze_and_extract`, `extract_at_position`, `extract_at_joints`, `peak_amp` | 793-1001, 1012-1149, 1227-1281 |
| `railway_inspector/detection/clustering.py` | ClusterID, filtro velocità moda | 339-377 |
| `railway_inspector/database/pipeline.py` | Per-run: macro-align geometrico + crop | 181-280 |
| `railway_inspector/database/builder.py` | Loop principale + clustering + micro-align + secondo passaggio | 105-788 |
| `railway_inspector/run_database.py` | Entry point CLI | 6-7, 1393-1394 |

---

## Task 0: Scaffolding del progetto e agenti custom

**Files:**
- Create: `pyproject.toml`
- Create: `railway_inspector/__init__.py`
- Create: `railway_inspector/signal/__init__.py`, `railway_inspector/io/__init__.py`, `railway_inspector/detection/__init__.py`, `railway_inspector/database/__init__.py`
- Create: `tests/__init__.py`
- Create: `.claude/agents/traduttore-matlab.md`
- Create: `.claude/agents/revisore-matematico.md`

- [ ] **Step 1: Crea `pyproject.toml`**

```toml
[project]
name = "railway-inspector"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    "numpy>=1.26",
    "scipy>=1.11",
    "pandas>=2.1",
    "openpyxl>=3.1",
]

[project.optional-dependencies]
dev = ["pytest>=8.0"]

[tool.pytest.ini_options]
testpaths = ["tests"]

[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"
```

- [ ] **Step 2: Crea i file `__init__.py`** (tutti vuoti, per rendere i package importabili).

- [ ] **Step 3: Crea l'agente custom `traduttore-matlab`** in `.claude/agents/traduttore-matlab.md`

```markdown
---
name: traduttore-matlab
description: Traduce un blocco di codice MATLAB in Python preservando esattamente la matematica. Usare per ogni task di traduzione di modulo nel progetto railway_inspector.
model: sonnet
tools: Read, Write, Edit, Bash, Grep, Glob
---

Sei un traduttore MATLAB→Python specializzato in signal processing numerico.

REGOLA ASSOLUTA: non cambiare la matematica. Stessi coefficienti, stesso ordine
delle operazioni, stessa gestione degli edge case del MATLAB originale.

Quando traduci:
- Converti indicizzazione 1-based (MATLAB) → 0-based (Python) con la massima cura.
- `filtfilt`, `butter`, `hilbert`, `fft/ifft`: usa scipy/numpy con parametri identici.
- `interpft`: reimplementa via zero-padding in frequenza (NON esiste in scipy).
- `xcorr`: ricostruisci il vettore dei lag con la convenzione MATLAB esatta.
- `interp1(...,'linear',0)`: interpolazione lineare con valori fuori range = 0.
- `omitnan` → equivalenti `np.nanmean` ecc.
- Mantieni i nomi delle variabili vicini all'originale dove aiuta la revisione.

Output: solo il file Python richiesto, più i test se specificati nel task.
Non aggiungere feature non presenti nel MATLAB. YAGNI.
```

- [ ] **Step 4: Crea l'agente custom `revisore-matematico`** in `.claude/agents/revisore-matematico.md`

```markdown
---
name: revisore-matematico
description: Verifica analitica riga-per-riga che una traduzione Python preservi esattamente la matematica del MATLAB originale. Usare dopo ogni traduzione di modulo.
model: sonnet
tools: Read, Grep, Glob, Bash
---

Sei il guardiano del vincolo invariante: la matematica del codice MATLAB madre
non deve cambiare minimamente nella traduzione Python.

Procedura di revisione:
1. Leggi il blocco MATLAB originale (file e righe indicati nel task).
2. Leggi la traduzione Python.
3. Confronta RIGA PER RIGA: coefficienti, ordine operazioni, edge case.
4. Controlla esplicitamente: indicizzazione 1-based→0-based, convenzione lag
   xcorr, zero-padding interpft, azzeramento interp1 fuori range, gestione NaN,
   shift di fase FFT, parametri butter/filtfilt.
5. Esegui i test del modulo con pytest e verifica che passino.

Output: verdetto APPROVATO o RICHIEDE CORREZIONI con elenco puntuale delle
divergenze trovate (riferimento riga MATLAB ↔ riga Python). Non correggere tu;
segnala.
```

- [ ] **Step 5: Verifica installazione**

Run: `cd "C:\Users\Nicco\Desktop\Prova" && python -m pip install -e ".[dev]" && python -c "import numpy, scipy, pandas, openpyxl; print('ok')"`
Expected: stampa `ok` senza errori.

- [ ] **Step 6: Commit**

```bash
git add pyproject.toml railway_inspector tests .claude/agents
git commit -m "chore: scaffolding railway_inspector + agenti custom traduttore/revisore"
```

---

## Task 1: `config.py` — parametri centralizzati

**Files:**
- Create: `railway_inspector/config.py`
- Test: `tests/test_config.py`

**Sorgente MATLAB:** righe 8-68 (struct `CFG` e `fmin`/`fmax`).

- [ ] **Step 1: Scrivi il test** in `tests/test_config.py`

```python
from railway_inspector.config import CFG, default_config

def test_default_config_values():
    c = default_config()
    assert c.SPATIAL_RES == 0.004
    assert c.WINDOW_FINAL == 5.0
    assert c.WINDOW_EXTRACT == 7.0
    assert c.fmin == 2
    assert c.fmax == 350
    assert c.ABS_RMS_THRESH == 5.0
    assert c.RMS_MUL == 3
    assert c.CROSS_TOL == 1.5
    assert c.UPSAMPLE_FACTOR == 4
    assert c.JOINT_WINDOW == 7.0

def test_config_is_mutable_dataclass():
    c = default_config()
    c.ROUTE_FILTER = "42"
    assert c.ROUTE_FILTER == "42"
```

- [ ] **Step 2: Esegui il test (deve fallire)**

Run: `pytest tests/test_config.py -v`
Expected: FAIL (`ModuleNotFoundError` / `ImportError`).

- [ ] **Step 3: Implementa `config.py`**

Dataclass `CFG` con un campo per ogni parametro delle righe 8-68 del MATLAB (inclusi `fmin=2`, `fmax=350`, e i campi stringa come `root_folder`, `excel_path`, `save_folder`, `TRACK_TYPE`, `ROUTE_FILTER`, `JOINTS_EXCEL` e i booleani `ONLY_FORWARD`, `ONLY_JOINTS`, `FILTER_SWITCHES`). Fornisci `default_config()` che ritorna l'istanza con i valori MATLAB. Il traduttore deve copiare ogni valore numerico esattamente dalle righe 37-68.

- [ ] **Step 4: Esegui il test (deve passare)**

Run: `pytest tests/test_config.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/config.py tests/test_config.py
git commit -m "feat(config): CFG dataclass con parametri MATLAB"
```

---

## Task 2: `signal/resampling.py` — interpft e interp1_zero (RISCHIO ALTO)

**Files:**
- Create: `railway_inspector/signal/resampling.py`
- Test: `tests/test_resampling.py`

**Sorgente MATLAB:** `interpft` (Fourier resampling, MATLAB built-in) usato a 214, 687, 1372; `interp1(x,y,xq,'linear',0)` a 214, 872, 877, 1087, 1092.

**Checklist equivalenza:**
- `interpft(x, n)`: upsampling via zero-padding nello spettro FFT, gestione corretta della frequenza di Nyquist per n pari, scaling `n/N`.
- `interp1_zero`: interpolazione lineare; punti di query fuori dal range degli x noti → 0 (non NaN, non estrapolazione).

- [ ] **Step 1: Scrivi i test** in `tests/test_resampling.py`

```python
import numpy as np
from railway_inspector.signal.resampling import interpft, interp1_zero

def test_interpft_upsamples_sine_without_distortion():
    N = 16
    t = np.arange(N)
    x = np.sin(2 * np.pi * 2 * t / N)
    up = interpft(x, 4 * N)
    # i campioni originali ricompaiono ogni 4 posizioni
    np.testing.assert_allclose(up[::4], x, atol=1e-9)

def test_interpft_length():
    x = np.random.randn(10)
    assert len(interpft(x, 40)) == 40

def test_interp1_zero_inside_range():
    x = np.array([0.0, 1.0, 2.0])
    y = np.array([0.0, 10.0, 20.0])
    xq = np.array([0.5, 1.5])
    np.testing.assert_allclose(interp1_zero(x, y, xq), [5.0, 15.0])

def test_interp1_zero_outside_range_is_zero():
    x = np.array([0.0, 1.0, 2.0])
    y = np.array([5.0, 10.0, 20.0])
    xq = np.array([-1.0, 3.0])
    np.testing.assert_allclose(interp1_zero(x, y, xq), [0.0, 0.0])
```

- [ ] **Step 2: Esegui i test (devono fallire)**

Run: `pytest tests/test_resampling.py -v`
Expected: FAIL (ImportError).

- [ ] **Step 3: Implementa `resampling.py`** — il traduttore implementa `interpft` (Fourier zero-pad fedele a MATLAB) e `interp1_zero` (np.interp con left=0, right=0).

- [ ] **Step 4: Esegui i test (devono passare)**

Run: `pytest tests/test_resampling.py -v`
Expected: PASS.

- [ ] **Step 5: Revisione matematica** — dispaccia `revisore-matematico` su `resampling.py` vs MATLAB. Risolvi eventuali divergenze prima del commit.

- [ ] **Step 6: Commit**

```bash
git add railway_inspector/signal/resampling.py tests/test_resampling.py
git commit -m "feat(signal): interpft via FFT + interp1_zero"
```

---

## Task 3: `signal/filtering.py` — pipeline filtfilt (RISCHIO ALTO)

**Files:**
- Create: `railway_inspector/signal/filtering.py`
- Test: `tests/test_filtering.py`

**Sorgente MATLAB:** 855-880 (`analyze_and_extract`) e 1073-1094 (`extract_at_position`). Pipeline identica:
1. `[bT,aT] = butter(2, [fmin,fmax]/(fs_time/2), 'bandpass')` con `fs_time=1000`.
2. `[bQ,aQ] = butter(2, [1/L_MAX, 1/L_MIN_QUIET]/(fs_space_res/2), 'bandpass')` con `fs_space_res=1/SPATIAL_RES`.
3. RAW: `interp1_zero(ax_u, sig_raw, common_axis)` (nessun filtro).
4. FILT: `sig_dem = sig - mean(sig,omitnan)` → `filtfilt(bT,aT)` → `interp1_zero` su asse spaziale → `filtfilt(bQ,aQ)`.

**Checklist equivalenza:** ordine butter=2, banda passante, `fs` corretti; `filtfilt` (zero-phase) doppio; demean con `omitnan`; nessuna alterazione dell'ordine.

- [ ] **Step 1: Scrivi i test** in `tests/test_filtering.py`

```python
import numpy as np
from scipy.signal import butter
from railway_inspector.config import default_config
from railway_inspector.signal.filtering import design_filters

def test_design_filters_matches_butter_params():
    c = default_config()
    bT, aT, bQ, aQ = design_filters(c, fs_time=1000.0)
    fs_space = 1.0 / c.SPATIAL_RES
    bT_ref, aT_ref = butter(2, [c.fmin, c.fmax] / np.array(1000.0 / 2), btype="bandpass")
    bQ_ref, aQ_ref = butter(2, [1/c.L_MAX, 1/c.L_MIN_QUIET] / np.array(fs_space / 2), btype="bandpass")
    np.testing.assert_allclose(bT, bT_ref); np.testing.assert_allclose(aT, aT_ref)
    np.testing.assert_allclose(bQ, bQ_ref); np.testing.assert_allclose(aQ, aQ_ref)

def test_filter_pipeline_removes_dc():
    from railway_inspector.signal.filtering import filter_pipeline
    c = default_config()
    n = 5000
    ax = np.arange(n) * 0.001  # asse temporale fittizio uniforme
    sig = 100.0 + np.sin(2*np.pi*50*ax)  # forte componente DC
    common_axis = np.arange(int(np.ceil(ax.min()/c.SPATIAL_RES)),
                            int(np.floor(ax.max()/c.SPATIAL_RES))+1) * c.SPATIAL_RES
    filt = filter_pipeline(sig, ax, common_axis, c, fs_time=1000.0)
    assert abs(np.mean(filt)) < 1.0  # DC rimosso
```

- [ ] **Step 2: Esegui i test (devono fallire)**

Run: `pytest tests/test_filtering.py -v`
Expected: FAIL (ImportError).

- [ ] **Step 3: Implementa `filtering.py`** con `design_filters(cfg, fs_time)` e `filter_pipeline(sig_raw, axis, common_space_axis, cfg, fs_time)` che riproduce esattamente le righe 855-880. Usa `interp1_zero` da `resampling.py`.

- [ ] **Step 4: Esegui i test (devono passare)**

Run: `pytest tests/test_filtering.py -v`
Expected: PASS.

- [ ] **Step 5: Revisione matematica** su `filtering.py` vs righe 855-880 e 1073-1094.

- [ ] **Step 6: Commit**

```bash
git add railway_inspector/signal/filtering.py tests/test_filtering.py
git commit -m "feat(signal): pipeline filtfilt temporale+spaziale"
```

---

## Task 4: `signal/alignment.py` — xcorr, shift FFT, template (RISCHIO ALTO)

**Files:**
- Create: `railway_inspector/signal/alignment.py`
- Test: `tests/test_alignment.py`

**Sorgente MATLAB:**
- `xcorr_lag` + macro-align: 226-230.
- `shift_signal_frac` (fase FFT): 1195-1224.
- `shift_fill` (shift intero zero-fill): 1376-1385.
- `build_align_template`: 1314-1374.
- `hilbert_envelope` (envelope = `abs(hilbert(x))`): usato a 480, 690-691, 1332.
- micro-align xcorr su envelope: 482-484, 694-697.

**Checklist equivalenza:** convenzione lag `xcorr` (lags da `-maxlag` a `+maxlag`, `argmax` → lag in campioni); shift di fase `exp(-1i*2*pi*k*shift/N)` con wrapping `k>floor(N/2)` → `k-N`; `shift_fill` senza wrap-around; medoide del template (colonna più correlata).

- [ ] **Step 1: Scrivi i test** in `tests/test_alignment.py`

```python
import numpy as np
from railway_inspector.signal.alignment import (
    xcorr_lag, shift_signal_frac, shift_fill, hilbert_envelope,
)

def test_xcorr_lag_detects_known_shift():
    ref = np.zeros(100); ref[50] = 1.0
    sig = np.zeros(100); sig[55] = 1.0   # sig in ritardo di 5
    lag = xcorr_lag(ref, sig, max_lag=20)
    assert lag == 5  # ref anticipa sig di 5 campioni (convenzione MATLAB)

def test_shift_signal_frac_integer_lag_matches_roll():
    x = np.sin(2*np.pi*3*np.arange(64)/64)
    shifted = shift_signal_frac(x, shift_m=2*0.004, spatial_res=0.004)  # +2 campioni
    # shift FFT periodico ≈ np.roll per lag intero (interno, lontano dai bordi)
    np.testing.assert_allclose(shifted[10:54], np.roll(x, 2)[10:54], atol=1e-9)

def test_shift_fill_no_wraparound():
    x = np.array([1.0, 2.0, 3.0, 4.0])
    np.testing.assert_allclose(shift_fill(x, 1), [0.0, 1.0, 2.0, 3.0])
    np.testing.assert_allclose(shift_fill(x, -1), [2.0, 3.0, 4.0, 0.0])

def test_hilbert_envelope_of_am_signal_is_positive():
    t = np.linspace(0, 1, 500)
    x = (1 + 0.5*np.cos(2*np.pi*3*t)) * np.cos(2*np.pi*50*t)
    env = hilbert_envelope(x)
    assert np.all(env >= 0)
    assert len(env) == len(x)
```

- [ ] **Step 2: Esegui i test (devono fallire)**

Run: `pytest tests/test_alignment.py -v`
Expected: FAIL (ImportError).

- [ ] **Step 3: Implementa `alignment.py`**:
  - `xcorr_lag(ref, sig, max_lag)` — usa `scipy.signal.correlate` + ricostruzione lag MATLAB, ritorna il lag (in campioni) del massimo.
  - `macro_align_shift(reference, sig_res, spatial_res, max_lag_m)` — righe 226-230.
  - `shift_signal_frac(sig, shift_m, spatial_res)` — fase FFT, righe 1195-1224.
  - `shift_fill(x, k)` — righe 1376-1385.
  - `hilbert_envelope(x)` — `np.abs(scipy.signal.hilbert(x))`.
  - `build_align_template(...)` — righe 1314-1374.

- [ ] **Step 4: Esegui i test (devono passare)**

Run: `pytest tests/test_alignment.py -v`
Expected: PASS.

- [ ] **Step 5: Revisione matematica** rinforzata (doppia passata) su `alignment.py` — questo è il modulo più a rischio.

- [ ] **Step 6: Commit**

```bash
git add railway_inspector/signal/alignment.py tests/test_alignment.py
git commit -m "feat(signal): xcorr lag, shift FFT, template allineamento"
```

---

## Task 5: `io/mat_loader.py` — caricamento .mat

**Files:**
- Create: `railway_inspector/io/mat_loader.py`
- Test: `tests/test_mat_loader.py`

**Sorgente MATLAB:** 156-167 (`load(f_path,'section_extracted')`, parsing `time_start` / nome file).

**Checklist:** `scipy.io.loadmat(..., struct_as_record=False, squeeze_me=True)` per accedere ai campi come attributi; gestione del fallback del nome file `parts = split(f_name,'_')` → data da `parts[1]_parts[2]`.

- [ ] **Step 1: Scrivi il test** in `tests/test_mat_loader.py`

```python
import numpy as np
from scipy.io import savemat
from railway_inspector.io.mat_loader import load_section, parse_run_date

def test_load_section_reads_fields(tmp_path):
    p = tmp_path / "run.mat"
    savemat(str(p), {"section_extracted": {"space_neutral": np.arange(10.0),
                                            "left_sensor_front": np.ones(10)}})
    sec = load_section(str(p))
    assert "space_neutral" in sec
    np.testing.assert_allclose(np.asarray(sec["space_neutral"]).ravel(), np.arange(10.0))

def test_parse_run_date_from_filename():
    d = parse_run_date("RUN_20240115_103000", section={})
    assert d.year == 2024 and d.month == 1 and d.day == 15
    assert d.hour == 10 and d.minute == 30 and d.second == 0
```

- [ ] **Step 2: Esegui il test (deve fallire)**

Run: `pytest tests/test_mat_loader.py -v`
Expected: FAIL.

- [ ] **Step 3: Implementa `mat_loader.py`** con `load_section(path) -> dict` e `parse_run_date(fname, section) -> datetime` (preferisce `section['time_start']`, fallback al nome file con formato `yyyyMMdd HHmmss`).

- [ ] **Step 4: Esegui il test (deve passare)**

Run: `pytest tests/test_mat_loader.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/io/mat_loader.py tests/test_mat_loader.py
git commit -m "feat(io): caricamento .mat section_extracted + parse data"
```

---

## Task 6: `io/excel_loader.py` — mappe infrastruttura e giunti

**Files:**
- Create: `railway_inspector/io/excel_loader.py`
- Test: `tests/test_excel_loader.py`

**Sorgente MATLAB:** `load_infrastructure_map` 1151-1166, `load_joints_map` 1283-1313, `to_num` 1387-1391.

**Checklist:** scelta fogli per `TRACK_TYPE` ('pari'→`{'1 p','1 dp'}`); colonne 20/21 (1-based) → indici 19/20 (0-based) per Pk_Inizio/Fine; per i giunti, ricerca header per `station`/`joint`/`shared`/`fixed`|`position`; filtro fogli per `type`.

- [ ] **Step 1: Scrivi il test** in `tests/test_excel_loader.py`

```python
import pandas as pd
from railway_inspector.io.excel_loader import load_joints_map, to_num

def test_to_num():
    assert to_num(3.5) == 3.5
    assert to_num("7") == 7.0
    import math
    assert math.isnan(to_num("abc"))

def test_load_joints_map_reads_positions(tmp_path):
    p = tmp_path / "giunti.xlsx"
    df = pd.DataFrame({"Stations": ["37-A", "37-A"],
                       "Position": [100.0, 250.0],
                       "Joint": ["J1", "J2"],
                       "Shared": ["", ""]})
    with pd.ExcelWriter(p, engine="openpyxl") as w:
        df.to_excel(w, sheet_name="M2-Pari", index=False)
    J = load_joints_map(str(p), "pari")
    assert list(J["Position"]) == [100.0, 250.0]
    assert set(J["Stations"]) == {"37-A"}
```

- [ ] **Step 2: Esegui il test (deve fallire)**

Run: `pytest tests/test_excel_loader.py -v`
Expected: FAIL.

- [ ] **Step 3: Implementa `excel_loader.py`** con `load_infrastructure_map(path, track_type) -> DataFrame`, `load_joints_map(path, type) -> DataFrame`, `to_num(v) -> float`. Usa pandas/openpyxl; replica la logica di selezione fogli e colonne del MATLAB.

- [ ] **Step 4: Esegui il test (deve passare)**

Run: `pytest tests/test_excel_loader.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/io/excel_loader.py tests/test_excel_loader.py
git commit -m "feat(io): mappe infrastruttura e giunti da Excel"
```

---

## Task 7: `io/database_io.py` — salvataggio MASTER_DB

**Files:**
- Create: `railway_inspector/io/database_io.py`
- Test: `tests/test_database_io.py`

**Sorgente MATLAB:** 786 (`save(... 'MASTER_DB')`). In Python il `MASTER_DB` è una lista di dict; serializza con `pickle` (e in parallelo `scipy.io.savemat` per interoperabilità opzionale con MATLAB).

- [ ] **Step 1: Scrivi il test** in `tests/test_database_io.py`

```python
from railway_inspector.io.database_io import save_master_db, load_master_db

def test_roundtrip(tmp_path):
    db = [{"ID_PK": "0.100", "Avg_Pos": 100.0, "Num_Occurrences": 5, "History": []}]
    p = tmp_path / "Database_damage_37-A.pkl"
    save_master_db(db, str(p))
    loaded = load_master_db(str(p))
    assert loaded[0]["ID_PK"] == "0.100"
    assert loaded[0]["Num_Occurrences"] == 5
```

- [ ] **Step 2: Esegui il test (deve fallire)**

Run: `pytest tests/test_database_io.py -v`
Expected: FAIL.

- [ ] **Step 3: Implementa `database_io.py`** con `save_master_db(db, path)` e `load_master_db(path)` (pickle).

- [ ] **Step 4: Esegui il test (deve passare)**

Run: `pytest tests/test_database_io.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/io/database_io.py tests/test_database_io.py
git commit -m "feat(io): salvataggio/caricamento MASTER_DB"
```

---

## Task 8: `detection/trigger.py` — RMS adattivo, findpeaks, merging

**Files:**
- Create: `railway_inspector/detection/trigger.py`
- Test: `tests/test_trigger.py`

**Sorgente MATLAB:** 852-934 (detection: envelope RMS `sqrt(movmean(sig^2))`, soglia dinamica `max(th_bkg*RMS_MUL, 0.05)`, `findpeaks` con `MinPeakDistance`, raffinamento picco entro 5 m, merging entro `CROSS_TOL`).

**Checklist:** `movmean` → finestra centrata; `find_peaks` con `distance=round(MIN_DIST/SPATIAL_RES)`; soglia `pks > th_dynamic[locs] & pks > ABS_RMS_THRESH`; raffinamento = argmax `abs` del segnale entro raggio 5 m; merging sequenziale come righe 921-934.

- [ ] **Step 1: Scrivi il test** in `tests/test_trigger.py`

```python
import numpy as np
from railway_inspector.config import default_config
from railway_inspector.detection.trigger import detect_peaks_on_signal

def test_detect_strong_isolated_peak():
    c = default_config()
    axis = np.arange(0, 50, c.SPATIAL_RES)
    sig = np.zeros_like(axis)
    center = len(axis)//2
    # burst forte ben sopra ABS_RMS_THRESH=5
    sig[center-5:center+5] = 20.0 * np.hanning(10)
    locs, amps = detect_peaks_on_signal(sig, axis, c)
    assert len(locs) >= 1
    # il picco rilevato è vicino al centro
    assert np.min(np.abs(np.array(locs) - axis[center])) < 1.0
```

- [ ] **Step 2: Esegui il test (deve fallire)**

Run: `pytest tests/test_trigger.py -v`
Expected: FAIL.

- [ ] **Step 3: Implementa `trigger.py`** con `detect_peaks_on_signal(sig_det, axis_det, cfg) -> (locs, amps)` (righe 885-916) e `merge_detections(det_locs, cross_tol) -> ndarray` (righe 921-934). Usa `scipy.signal.find_peaks`. `movmean` centrato via convoluzione.

- [ ] **Step 4: Esegui il test (deve passare)**

Run: `pytest tests/test_trigger.py -v`
Expected: PASS.

- [ ] **Step 5: Revisione matematica** su `trigger.py` vs 852-934 (attenzione a `find_peaks` vs `findpeaks` e indici di raffinamento).

- [ ] **Step 6: Commit**

```bash
git add railway_inspector/detection/trigger.py tests/test_trigger.py
git commit -m "feat(detection): RMS adattivo, find_peaks, merging"
```

---

## Task 9: `detection/extraction.py` — estrazione segnali

**Files:**
- Create: `railway_inspector/detection/extraction.py`
- Test: `tests/test_extraction.py`

**Sorgente MATLAB:** `analyze_and_extract` 793-1001, `extract_at_position` 1012-1149, `extract_at_joints` 1252-1281, `peak_amp` 1227-1250.

**Checklist:** gestione assi front/back (`space_front`/`space_back` o `space_parameters`); `switch_mask` (righe 838-851); `common_space_axis` come `(ceil(min/RES):floor(max/RES))*RES`; pre-crop in `extract_at_position` con `FILTER_MARGIN`; `peak_amp` = max `abs` filtrato su tutti i sensori entro `±half_w`; nomi sensori assiali e laterali esatti (818-822, 947-948).

- [ ] **Step 1: Scrivi i test** in `tests/test_extraction.py`

```python
import numpy as np
from railway_inspector.config import default_config
from railway_inspector.detection.extraction import peak_amp

def test_peak_amp_picks_max_abs_within_window():
    sig = {
        "RelativeAxis": np.linspace(-5, 5, 101),
        "Filt": {
            "left_sensor_front": np.zeros(101),
            "right_sensor_front": np.concatenate([np.zeros(50), [12.0], np.zeros(50)]),
        },
    }
    assert peak_amp(sig, half_w=5.0) == 12.0

def test_peak_amp_respects_window():
    axis = np.linspace(-10, 10, 201)
    f = np.zeros(201); f[0] = 99.0  # fuori da ±5 m
    sig = {"RelativeAxis": axis, "Filt": {"left_sensor_front": f}}
    assert peak_amp(sig, half_w=5.0) == 0.0
```

- [ ] **Step 2: Esegui i test (devono fallire)**

Run: `pytest tests/test_extraction.py -v`
Expected: FAIL.

- [ ] **Step 3: Implementa `extraction.py`**:
  - `peak_amp(sig, half_w)` — righe 1227-1250.
  - `extract_at_position(data, target_pos, cfg, fmin, fmax) -> dict|None` — righe 1012-1149 (usa `filter_pipeline`).
  - `analyze_and_extract(data, cfg, fmin, fmax) -> list[dict]` — righe 793-1001 (usa `trigger`).
  - `extract_at_joints(data, joint_pos, joint_labels, cfg, fmin, fmax) -> list[dict]` — righe 1252-1281.

- [ ] **Step 4: Esegui i test (devono passare)**

Run: `pytest tests/test_extraction.py -v`
Expected: PASS.

- [ ] **Step 5: Revisione matematica** su `extraction.py` (switch_mask, assi, finestre).

- [ ] **Step 6: Commit**

```bash
git add railway_inspector/detection/extraction.py tests/test_extraction.py
git commit -m "feat(detection): extract_at_position/joints, analyze, peak_amp"
```

---

## Task 10: `detection/clustering.py` — ClusterID e filtro velocità

**Files:**
- Create: `railway_inspector/detection/clustering.py`
- Test: `tests/test_clustering.py`

**Sorgente MATLAB:** 339-377 (assegnazione `ClusterID` per gap `> CROSS_TOL`, filtro velocità moda `abs(speed-mode)<=SPEED_TOL` solo se non ONLY_JOINTS).

- [ ] **Step 1: Scrivi i test** in `tests/test_clustering.py`

```python
import numpy as np
from railway_inspector.detection.clustering import assign_cluster_ids

def test_cluster_ids_split_on_gap():
    pos = np.array([10.0, 10.5, 11.0, 50.0, 50.3])
    ids = assign_cluster_ids(pos, cross_tol=1.5)
    assert list(ids) == [1, 1, 1, 2, 2]

def test_single_point_cluster():
    ids = assign_cluster_ids(np.array([5.0]), cross_tol=1.5)
    assert list(ids) == [1]
```

- [ ] **Step 2: Esegui i test (devono fallire)**

Run: `pytest tests/test_clustering.py -v`
Expected: FAIL.

- [ ] **Step 3: Implementa `clustering.py`** con `assign_cluster_ids(pos_sorted, cross_tol) -> ndarray` (righe 343-347) e `filter_by_mode_speed(speeds, speed_tol, only_joints) -> (keep_mask, mode_speed)` (righe 360-373, usa `scipy.stats.mode` su `round(speed)`).

- [ ] **Step 4: Esegui i test (devono passare)**

Run: `pytest tests/test_clustering.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add railway_inspector/detection/clustering.py tests/test_clustering.py
git commit -m "feat(detection): ClusterID e filtro velocità moda"
```

---

## Task 11: `database/pipeline.py` — macro-align geometrico + crop per-run

**Files:**
- Create: `railway_inspector/database/pipeline.py`
- Test: `tests/test_pipeline.py`

**Sorgente MATLAB:** 181-280 (orientation/fallback, `sig_geo` normalizzato, `common_axis_ext`, macro xcorr `max_lag=round(150/RES)`, sanity check shift vs direzione, applicazione shift a `space_*` e `switch.location`, crop su `[CROP_START, CROP_END]`).

- [ ] **Step 1: Scrivi il test** in `tests/test_pipeline.py`

```python
import numpy as np
from railway_inspector.config import default_config
from railway_inspector.database.pipeline import compute_geo_signal

def test_compute_geo_signal_is_zscored():
    c = default_config()
    space_raw = np.arange(0, 100, c.SPATIAL_RES)
    data = {"space_neutral": space_raw,
            "curve": np.sin(space_raw)}
    geo, axis = compute_geo_signal(data, c)
    # z-score: media ~0, std ~1
    assert abs(np.mean(geo)) < 1e-3
    assert abs(np.std(geo) - 1.0) < 1e-2
```

- [ ] **Step 2: Esegui il test (deve fallire)**

Run: `pytest tests/test_pipeline.py -v`
Expected: FAIL.

- [ ] **Step 3: Implementa `pipeline.py`**:
  - `determine_orientation(data) -> str` — righe 187-196.
  - `compute_geo_signal(data, cfg) -> (sig_geo_res, common_axis_ext)` — righe 205-215 (normalizzazione `(x-mean)/(std+1e-6)`).
  - `align_and_crop_run(data, reference, master_orientation, crop_start, crop_end, cfg) -> (data_aligned, shift, valid)` — righe 217-280 (macro xcorr via `alignment`, sanity check, shift dei campi spaziali, crop con `mask_keep`).

- [ ] **Step 4: Esegui il test (deve passare)**

Run: `pytest tests/test_pipeline.py -v`
Expected: PASS.

- [ ] **Step 5: Revisione matematica** su `pipeline.py` vs 181-280 (sanity check direzione, applicazione shift).

- [ ] **Step 6: Commit**

```bash
git add railway_inspector/database/pipeline.py tests/test_pipeline.py
git commit -m "feat(database): macro-align geometrico e crop per-run"
```

---

## Task 12: `database/builder.py` + `run_database.py` — orchestrazione completa

**Files:**
- Create: `railway_inspector/database/builder.py`
- Create: `railway_inspector/run_database.py`
- Test: `tests/test_builder_smoke.py`

**Sorgente MATLAB:** 105-788 (loop tratte, accumulo eventi, clustering, micro-align sub-campione con template, primo `MASTER_DB`, secondo passaggio di completamento) + 6-7/1393-1394 (timing).

**Checklist:** loop su tratte filtrate (`ROUTE_FILTER`); per file → `pipeline.align_and_crop_run` → `extraction`; clustering globale (`assign_cluster_ids` su eventi ordinati per `Pos`); per cluster → filtro velocità, micro-align al template (`build_align_template` + `xcorr_lag` su envelope, `shift_signal_frac`), crop finale, `peak_amp`; tetto `JOINT_MAX_RUNS`; secondo passaggio (righe 579-785) con `extract_at_position`, filtro velocità, micro-align, fino a `MAX_TOTAL_RUNS`; salvataggio per tratta.

- [ ] **Step 1: Scrivi il test smoke** in `tests/test_builder_smoke.py`

```python
import numpy as np
from scipy.io import savemat
from railway_inspector.config import default_config
from railway_inspector.database.builder import build_database_for_route

def _make_run(path, n=20000, res=0.004):
    space = np.arange(n) * res
    sig = np.zeros(n)
    sig[n//2-20:n//2+20] = 30.0 * np.hanning(40)  # difetto forte ripetibile
    d = {"section_extracted": {
        "space_neutral": space, "curve": np.sin(space),
        "left_sensor_front": sig, "left_sensor_rear": sig,
        "right_sensor_front": sig, "right_sensor_rear": sig,
        "speed_kmh": np.full(n, 80.0), "orientation": "moving forward",
        "time": np.arange(n) * 0.001,
    }}
    savemat(str(path), d)

def test_builder_runs_and_finds_cluster(tmp_path):
    c = default_config()
    c.ONLY_JOINTS = False
    files = []
    for k in range(3):
        p = tmp_path / f"RUN_2024010{k+1}_100000.mat"
        _make_run(p); files.append(str(p))
    db = build_database_for_route(files, route_name="TEST", cfg=c,
                                  track_map=None, route_joints=None, route_joint_labels=None)
    assert isinstance(db, list)
    assert len(db) >= 1
    assert db[0]["Num_Occurrences"] >= 1
```

- [ ] **Step 2: Esegui il test (deve fallire)**

Run: `pytest tests/test_builder_smoke.py -v`
Expected: FAIL.

- [ ] **Step 3: Implementa `builder.py`** con `build_database_for_route(files, route_name, cfg, track_map, route_joints, route_joint_labels) -> list[dict]` che riproduce le righe 134-785 per una singola tratta. Implementa `run_database.py` come entry point che: carica config, mappe (`excel_loader`), itera le tratte filtrate, chiama `build_database_for_route`, salva con `database_io`. Replica il timing `tic/toc` (righe 7/1393).

- [ ] **Step 4: Esegui il test (deve passare)**

Run: `pytest tests/test_builder_smoke.py -v`
Expected: PASS.

- [ ] **Step 5: Revisione matematica** finale su `builder.py` vs 105-785 (micro-align template, secondo passaggio, ordine cronologico inverso).

- [ ] **Step 6: Esegui l'intera suite**

Run: `pytest -v`
Expected: tutti i test PASS.

- [ ] **Step 7: Commit**

```bash
git add railway_inspector/database/builder.py railway_inspector/run_database.py tests/test_builder_smoke.py
git commit -m "feat(database): builder completo + entry point run_database"
```

---

## Note di esecuzione

- **Ordine obbligato:** Task 0 → 1 → 2 → 3 → 4 (signal/ in serie, rischio alto) → 5/6/7 (io, parallelizzabili) → 8 → 9 → 10 (detection) → 11 → 12.
- **Modelli:** traduzione `signal/` (Task 2-4), `detection`/`database` con `traduttore-matlab` (Sonnet); revisione sempre con `revisore-matematico` (Sonnet). I task io/config possono usare il traduttore standard.
- **Vincolo invariante:** ogni task a rischio alto passa dalla revisione matematica PRIMA del commit.
