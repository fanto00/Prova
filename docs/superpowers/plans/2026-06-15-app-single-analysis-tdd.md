# Piano TDD: Modulo 10 — `app/ui/single_analysis.py`

Sottotask di sub-plan 7 (App GUI Completa). **Mega window** per analisi approfondita di un singolo difetto con 5 tab (Trend, Statistiche, STFT, PSD, Matrice 3x3).

---

## Scope

**File MATLAB:** `src_app/app.m` (righe 1986-3289, 4392-4516)  
**File Python:** `railway_inspector/app/ui/single_analysis.py` (~1800 LOC MATLAB → ~2200 Python LOC)

**Struttura finestra:**
- **Tab 1: Trend Temporale** — 4 subplot (1 per coppia sensori Front/Rear)
- **Tab 2: Statistiche & Profilo** — Tabella metrica + 3D waterfall (RMS, Skew, Kurt, Crest)
- **Tab 3: Spettrogramma (STFT)** — Dropdown sensore, run selector, window slider
- **Tab 4: PSD (Power Spectral Density)** — 2D storico + current run, vista 3D evolutiva
- **Tab 5: Matrice 3x3** — Scatter SX/DX vs Front/Rear ratio con colormap tempo
- **Pulsante export** "ESPORTA REPORT PICCO" in alto a destra

**Dependencies:** TUTTI i moduli precedenti:
- `single_analysis_psd.py` → compute_psd_for_run, compute_psd_matrix_3d, plot_psd_2d, plot_psd_3d_waterfall
- `single_analysis_evolutive.py` → compute_amplitude_ratios, compute_evolutive_metrics
- `spectrum.py` → peak_lambda_from_spectrum, get_spectrum_psd, lambda_to_label
- `helpers.py` → get_amp, get_max_rms, safe_ratio, sort_runs_by_direction
- `filters.py` → filter_defect_by_dates
- `ipi_core.py` → compute_ipi_score, ipi_semaphore_color
- `classification.py` → classify_defects
- Signal plotting, figure/export functions

---

## Strategia: Decomposizione in Funzioni Pure + UI Assembly

Data la complessità (PyQt6 è hard to test), suddivido in:

1. **Pure Functions** (TDD testabili):
   - Data extraction & organization
   - Tab data builders (ritornano dict config)
   - Metric calculations (timestamp, IPI, classification)

2. **UI Assembly** (manual test, no pytest):
   - Figure creation
   - Tab construction (uicontrol boilerplate)
   - Callback setup

---

## File di Output

**Main module:** `railway_inspector/app/ui/single_analysis.py`
**Test file:** `tests/test_app_single_analysis_ui.py`

---

## 1. Data Extraction Functions (PURE)

### `prepare_raw_data_store(...) → RawDataStore`

**Input:** `defect_history: List[dict], config: dict (CFG)`  
**Output:** `RawDataStore: List[dict]` con keys: Date, Signals (dict), Axis, Amp, Speed, Detected

**Logica (linee 2042-2115 MATLAB):**
- Itera su ogni run in defect_history
- Per ogni sensore (8), estrae segnale filtrato da run.Data.Filt
- Interpola segnale su common_axis (derivato da run.Data.RelativeAxis)
- Accumula RMS con window = 0.5m (hardcoded in MATLAB riga 2079)
- Ritorna lista ordinata per data (sort_idx come MATLAB 2117-2119)

**Test:**
```python
def test_prepare_raw_data_store_basic():
    """Estrae RawDataStore da defect_history."""
    # Mock defect_history con 3 run
    # Verificare: len(RawDataStore) == 3, keys presenti, ordinamento data
    pass

def test_prepare_raw_data_store_signal_extraction():
    """Estrae segnali filtrati correttamente (8 sensori)."""
    # Verificare: RawDataStore[i]['Signals'] ha 8 keys
    pass

def test_prepare_raw_data_store_sorts_by_date():
    """Ordina per data come MATLAB sort_idx."""
    # Dates cronologico, AllAmps reordered same way
    pass
```

### `compute_all_amps(RawDataStore, sensor_fields_list) → np.ndarray`

**Input:** `RawDataStore: List[dict], sensor_fields_list: List[str]` (8 nomi sensori)  
**Output:** `AllAmps: ndarray (n_runs x 8)` — max(RMS) per run/sensor

**Logica:** For each run, compute max(RMS) over window 0.5m per sensore (linee 2075-2102)

**Test:**
```python
def test_compute_all_amps_basic():
    """Ritorna matrix (n_runs x 8)."""
    pass

def test_compute_all_amps_rms_calculation():
    """Max RMS calcolato correttamente con window."""
    pass
```

### `compute_metrics_per_run(AllAmps, RawDataStore, dates_num) → Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]`

**Input:** `AllAmps, RawDataStore, dates_num`  
**Output:** `(Ratio_SX_DX, Ratio_FR, Ratio_LV, Lambda_All, Severity)` — 5 array

**Logica (linee 2122-2157):**
- `Ratio_*` = formule da `single_analysis_evolutive.py` (già reusato)
- `Lambda_All` = periodogramma per ogni sensore (linea 2154 `get_quick_lambda_local`)
- `Severity` = max([A_SX_F, A_SX_R, A_DX_F, A_DX_R])

**Note:** `get_quick_lambda_local` è una funzione helper MATLAB — va reusata da `spectrum.py:peak_lambda_from_spectrum`

**Test:**
```python
def test_compute_metrics_per_run_basic():
    """Ritorna 5 array con dimensioni corrette."""
    pass

def test_compute_metrics_per_run_lambda_positive():
    """Lambda tutti positivi (o zero se no signal)."""
    pass
```

---

## 2. Tab Builder Functions (PURE)

### `build_tab_trend_data(AllAmps, dates_num, pairs_idx) → Dict`

**Input:** `AllAmps (n_runs x 8), dates_num, pairs_idx=[1,2; 3,4; 5,6; 7,8]`  
**Output:** `Dict` con keys: `plot_titles, mean_F_list, mean_R_list, unique_days` (per disegno grafici)

**Logica (linee 2180-2207):** Aggrega AllAmps per giorno, prepara dati per 4 subplot

**Test:**
```python
def test_build_tab_trend_data_basic():
    """Ritorna dict con keys richieste."""
    pass

def test_build_tab_trend_data_daily_aggregation():
    """Aggrega correttamente Front/Rear per giorno."""
    pass
```

### `build_tab_stats_table_data(RawDataStore, Ratio_SX_DX, Ratio_FR, Ratio_LV, Lambda_All, dates_num, pop_grouping_value) → List[Dict]`

**Input:** RawDataStore, ratios, lambda, dates, grouping_mode (1=run, 2=daily, 3=weekly, 4=monthly)  
**Output:** `List[Dict]` con colonne: Data, Velocità, Picco, Max RMS, Skew, Kurt, Crest, Pos 3x3, Lambda

**Logica (linee 2236-2449):**
- Raggruppa per periodo (grouping_value)
- Calcola metriche statistiche (RMS, skew, kurt, crest)
- Classifica posizione 3x3 (L/C/R × F/C/R)
- Ritorna lista per tabella UI

**Note:** Riusa `compute_evolutive_metrics` da `single_analysis_evolutive.py`

**Test:**
```python
def test_build_tab_stats_table_data_basic():
    """Ritorna lista dict con n_periods righe."""
    pass

def test_build_tab_stats_table_data_grouping():
    """Raggruppa per periodo correttamente (run/daily/weekly/monthly)."""
    pass

def test_build_tab_stats_table_data_3x3_classification():
    """Classifica 3x3 position correttamente."""
    pass
```

### `build_stft_dates_labels(RawDataStore) → List[str]`

**Input:** `RawDataStore`  
**Output:** `List[str]` con formato "dd/mm/yy HH:MM [Picco m/s²]"

**Logica (linee 2590-2593)**

**Test:**
```python
def test_build_stft_dates_labels():
    """Formato data + ampiezza."""
    pass
```

---

## 3. Profile Cache Builder (PURE)

### `compute_cache_profiles(RawDataStore, dates_num, grouping_mode, sensor_pair_idx, WINDOW_SIZE, dx) → List[Dict]`

**Input:** `RawDataStore, dates_num, grouping_mode, sensor_pair, WINDOW_SIZE=5.0, dx=0.030`  
**Output:** `List[Dict]` con keys: RMS, Skew, Kurt, Crest, Axis, Date (per ogni periodo)

**Logica (linee 2246-2449):**
- Raggruppa run per periodo
- Per ogni periodo, calcola profili RMS/Skew/Kurt/Crest via window stats
- Interpola segnali su common_axis
- Media i profili tra le corse del periodo

**Note:** Molto computazionale, usa `moving_window_stat` helper

**Test:**
```python
def test_compute_cache_profiles_basic():
    """Ritorna lista profili con shape corretti."""
    pass

def test_compute_cache_profiles_interpolation():
    """Interpola segnali su common_axis."""
    pass
```

---

## 4. Classification & IPI Builder (PURE)

### `compute_defect_classification(RawDataStore, AllAmps, Ratio_SX_DX, Ratio_FR, Lambda_All, ...) → Dict`

**Input:** Tutti i dati aggregati + CFG  
**Output:** `Dict` con defect classification (cellule 3x3, IPI score, semaforo)

**Logica:** Riusa `classify_defects` da `app/analysis/classification.py` + `compute_ipi_score` da `app/ipi/ipi_core.py`

**Test:**
```python
def test_compute_defect_classification():
    """IPI score e colore semaforo."""
    pass
```

---

## 5. Main UI Function (NOT TDD-TESTED)

### `open_single_analysis(defect, db, config, track_name) → QMainWindow`

**Input:** defect dict, db (list), config dict, track_name  
**Output:** QMainWindow (modal, modeless configurable)

**Logica:**
1. Valida input (defect non vuoto, n_runs >= 3)
2. Chiama prepare_raw_data_store → data extraction
3. Chiama compute_*_* funzioni per tutti i dati aggregati
4. Crea figure PyQt6 e tabgroup
5. Per ogni tab:
   - Chiama builder function → Dict
   - Unpack dict e crea UI elements (axes, tables, controls)
   - Lega callbacks
6. Restituisce figure (manager per close/destroy)

**Manual test only** (PyQt6 is complex):
- Apri finestra manualmente, verifica:
  - Tab switch funziona
  - Dati nel table correct
  - Grafici rendono senza errori
  - Callbacks react to widget changes (dropdown, slider, button)

---

## TDD: 15+ Test Specifici

### Categoria 1: Data Extraction (4 test)

```python
def test_prepare_raw_data_store_basic():
    """Extract RawDataStore da defect_history."""
    defect_history = [
        {'Date': datetime(2026, 1, 1, 10, 0), 'Data': {...}},
        {'Date': datetime(2026, 1, 2, 10, 0), 'Data': {...}},
    ]
    store = prepare_raw_data_store(defect_history, CFG)
    assert len(store) == 2
    assert 'Signals' in store[0]
    assert 'Axis' in store[0]

def test_prepare_raw_data_store_sorts_by_date():
    """Chronological order."""
    # Mixed order input, check output sorted
    pass

def test_compute_all_amps_shape():
    """Output (n_runs x 8)."""
    pass

def test_compute_all_amps_rms_window():
    """Max RMS with 0.5m window."""
    pass
```

### Categoria 2: Metrics Computation (3 test)

```python
def test_compute_metrics_per_run_shape():
    """Output 5 arrays, correct shapes."""
    pass

def test_compute_metrics_per_run_ratios_formula():
    """SX_DX, FR, LV formulas (reuse from single_analysis_evolutive)."""
    pass

def test_compute_metrics_per_run_lambda_range():
    """Lambda in [0, ∞) or NaN."""
    pass
```

### Categoria 3: Tab Builders (6 test)

```python
def test_build_tab_trend_data_aggregation():
    """Daily aggregation per coppia sensori."""
    pass

def test_build_tab_stats_table_data_run_grouping():
    """grouping=1 (run mode)."""
    pass

def test_build_tab_stats_table_data_daily_grouping():
    """grouping=2 (daily)."""
    pass

def test_build_tab_stats_table_data_weekly_grouping():
    """grouping=3 (weekly)."""
    pass

def test_build_tab_stats_table_data_3x3_classification():
    """L/C/R × F/C/R mapping."""
    pass

def test_build_stft_dates_labels_format():
    """dd/mm/yy HH:MM [m/s²] format."""
    pass
```

### Categoria 4: Profile Cache (2 test)

```python
def test_compute_cache_profiles_shape():
    """n_periods × metrics."""
    pass

def test_compute_cache_profiles_daily_grouping():
    """Daily aggregation + interpolation."""
    pass
```

---

## Quality Gates

1. **Matematica:** Ratios, lambda, aggregation identiche a MATLAB (righe 2145-2157)
2. **Grouping:** 'run', 'daily', 'weekly', 'monthly' via `compute_evolutive_metrics`
3. **Axis interpolation:** Segnali resampled su common_axis = [-WINDOW_SIZE, WINDOW_SIZE]
4. **Tab data consistency:** Tutti i tab ricevono dati aggregati identici
5. **Type hints:** Tutte le funzioni tipate (List[dict], np.ndarray, str, int, Dict)
6. **Docstrings:** One-liner per ogni funzione
7. **Test coverage:** 15+ test, tutti passing

---

## Workflow: TDD Subagent-Driven

### Fase 1: Test Writing (35 min)
- Scrivi tutti i 15+ test in `tests/test_app_single_analysis_ui.py`
- Tutti fallano (funzioni non ancora definite)

### Fase 2: Traduzione MATLAB (90 min)
- **Traduttore (Haiku):** Traduci linee 2042-2449, 2550-2573 MATLAB → Python
  - Data extraction (prepare_raw_data_store, compute_all_amps)
  - Metrics (compute_metrics_per_run)
  - Tab builders (build_tab_*, compute_cache_profiles)
  - Helper: moving_window_stat → scipy.ndimage utilities

### Fase 3: Review Matematica (40 min)
- **Revisore (Haiku):** Verifica:
  - Ratios formula (SX_DX, FR, LV)
  - Interpolation logic (interp1 → np.interp)
  - Aggregation (mean, omitnan)
  - Window stats (moving RMS, skew, kurt, crest)
  - 3x3 classification boundaries

### Fase 4: UI Integration (30 min)
- Scrivi main function `open_single_analysis`
- Setup figure, tabgroup, callbacks
- Manual test (click buttons, switch tabs, change sliders)

### Fase 5: Commit (5 min)
- Tutti i test passing
- Type hints verificati
- Docstrings in place

**Total Effort: ~3 ore** (subagent traduttore + revisore)

---

## Dependencies (already available)

```python
from railway_inspector.app.analysis.single_analysis_psd import (
    compute_psd_for_run,
    compute_psd_matrix_3d,
    plot_psd_2d,
    plot_psd_3d_waterfall,
)
from railway_inspector.app.analysis.single_analysis_evolutive import (
    compute_amplitude_ratios,
    compute_evolutive_metrics,
)
from railway_inspector.app.analysis.spectrum import (
    peak_lambda_from_spectrum,
    get_spectrum_psd,
    lambda_to_label,
)
from railway_inspector.app.analysis.classification import classify_defects
from railway_inspector.app.ipi.ipi_core import compute_ipi_score, ipi_semaphore_color
from railway_inspector.app.utils.helpers import get_amp, get_max_rms, safe_ratio
from railway_inspector.app.utils.filters import filter_defect_by_dates
```

---

## Out of Scope

- AE (Autoencoder) tab — placeholder "Coming Soon"
- Real-time callback optimization (PyQt6 signal/slot boilerplate)
- Figure window management (PyQt6 parent/child, modal/modeless config)
- File export details (LaTeX, PNG generation) — delegato a export.py

---

## Notes MATLAB→Python

| MATLAB | Python |
|--------|--------|
| `interp1(x, y, xi, 'linear', 0)` | `np.interp(xi, x, y, left=0, right=0)` |
| `movmean(x, k)` | `scipy.ndimage.uniform_filter1d(x, size=k, mode='nearest')` |
| `skewness(x)` | `scipy.stats.skew(x)` |
| `kurtosis(x)` | `scipy.stats.kurtosis(x, fisher=True)` |
| `movmax(abs(x), k) / (rms + eps)` | Crest factor manuale |
| `datestr(dn, 'dd/mm/yy HH:MM')` | `datetime.strftime('%d/%m/%y %H:%M')` |
| `unique(dates_floor)` | `sorted(set(dates_floor))` |
| Figure + uicontrol boilerplate | PyQt6 QMainWindow, QTabWidget, QTableWidget |

---

## Stime Temporali

| Task | Tempo | Chi |
|------|-------|-----|
| Test writing | 35 min | Io (planning) |
| MATLAB translation | 90 min | Traduttore-Matlab |
| Mathematical review | 40 min | Revisore-Matematico |
| UI integration + manual test | 30 min | Io |
| Commit + cleanup | 5 min | Io |
| **TOTAL** | **~3 ore** | Subagent-driven TDD |
