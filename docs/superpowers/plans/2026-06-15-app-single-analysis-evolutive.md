# Piano TDD: Modulo 8 — `app/analysis/single_analysis_evolutive.py`

Sottotask di sub-plan 7 (App GUI Completa). Funzioni pure per calcolo e aggregazione temporale delle metriche di evoluzione di un singolo difetto: ratios (SX/DX, Front/Rear, Laterale/Verticale) e lambda spaziale per sensore.

---

## Scope

**File MATLAB:** `src_app/app.m` (righe 2123-2147, 4258-4384)  
**File Python:** `railway_inspector/app/analysis/single_analysis_evolutive.py`

**3 funzioni pure (no UI state, no callbacks):**

1. **`compute_amplitude_ratios(defect_history, all_amps)`** (MATLAB linee 2145-2147)
   - Calcola ratios per ogni run del difetto (SX_DX, FR, LV)
   - Input: defect_history (list of run dict), all_amps (ndarray n_runs x 8)
   - Output: (ratio_sx_dx, ratio_fr, ratio_lv) — tuple di ndarray
   - Logica:
     * Ratio_SX_DX = (A_SX_F + A_SX_R) / max(A_DX_F + A_DX_R, 1e-6)
     * Ratio_FR = (A_SX_F + A_DX_F) / max(A_SX_R + A_DX_R, 1e-6)
     * Ratio_LV = A_LAT_MAX / max(A_VERT_MAX, 1e-6)
     * Colonne all_amps: [0:SX_F, 1:SX_R, 2:DX_F, 3:DX_R, 4-7:LAT sensori]

2. **`compute_lambda_all(defect_history, signal_data, nfft, fs)`** (MATLAB linea 2154 + lambda calc)
   - Calcola lambda spaziale per ogni sensore e run
   - Input: defect_history, signal_data (dict sensor→signal), nfft, fs (spatial sampling)
   - Output: lambda_all (ndarray n_runs x 8) — una per sensore
   - Logica:
     * Estrae segnale filtrato per ogni sensore/run (da defect_history['Signals'])
     * Calcola lambda usando periodogramma Hamming (come in spectrum.py)
     * Ritorna matrice 8 sensori per timeline

3. **`compute_evolutive_metrics(defect_history, ratio_sx_dx, ratio_fr, ratio_lv, lambda_all, dates_num, grouping_mode='daily')`** (MATLAB linee 4277-4296)
   - Aggrega ratios e lambda nel tempo per periodi (run/daily/weekly/monthly)
   - Input: defect_history, three ratio arrays, lambda_all, dates_num (ndarray datenum), grouping_mode
   - Output: (avg_ratio_sx_dx, avg_ratio_fr, avg_ratio_lv, avg_lambda_all, period_dates, periods_valid)
   - Logica:
     * Raggruppa per periodo usando _round_datetime_to_period (come in single_analysis_psd.py)
     * Per ogni periodo: calcola media ratios e lambda (sum / n_valid)
     * Ritorna n_periods x metriche aggregati

---

## Dipendenze Python

- `numpy` — operazioni array, mean
- `railway_inspector.app.analysis.spectrum.peak_lambda_from_spectrum` — calcolo lambda
- `datetime` — conversione datenum
- Riuso: `_round_datetime_to_period()` da `single_analysis_psd.py` (o copia)

---

## TDD: 7 Test Specifici

### Test 1: `test_compute_amplitude_ratios_basic`
**Verifica:** Calcola tre ratios per una lista di run.

```python
def test_compute_amplitude_ratios_basic():
    """compute_amplitude_ratios() ritorna tre array di ratios."""
    all_amps = np.array([
        [1.0, 1.0, 2.0, 2.0, 0.5, 0.5, 0.5, 0.5],  # Run 1
        [2.0, 2.0, 1.0, 1.0, 0.3, 0.3, 0.3, 0.3],  # Run 2
    ])
    defect_history = [{'Date': datetime(2026, 1, 1)}, {'Date': datetime(2026, 1, 2)}]
    
    ratio_sx_dx, ratio_fr, ratio_lv = compute_amplitude_ratios(
        defect_history, all_amps
    )
    
    assert len(ratio_sx_dx) == 2
    assert len(ratio_fr) == 2
    assert len(ratio_lv) == 2
```

### Test 2: `test_compute_amplitude_ratios_formula`
**Verifica:** Formule esatte (SX_DX = (F+R)/max(DX,1e-6), ecc.).

```python
def test_compute_amplitude_ratios_formula():
    """Formule: SX_DX=(SX_F+SX_R)/max(DX_F+DX_R,1e-6), FR=(F+F)/(R+R), LV=LAT/VERT."""
    all_amps = np.array([[2.0, 2.0, 4.0, 4.0, 1.0, 1.0, 1.0, 1.0]])
    defect_history = [{'Date': datetime(2026, 1, 1)}]
    
    ratio_sx_dx, ratio_fr, ratio_lv = compute_amplitude_ratios(defect_history, all_amps)
    
    # SX_DX = (2+2) / (4+4) = 4/8 = 0.5
    assert np.isclose(ratio_sx_dx[0], 0.5)
    # FR = (2+4) / (2+4) = 6/6 = 1.0
    assert np.isclose(ratio_fr[0], 1.0)
    # LV = max(1,1,1,1) / max(1,1,1,1) = 1.0
    assert np.isclose(ratio_lv[0], 1.0)
```

### Test 3: `test_compute_amplitude_ratios_zero_guard`
**Verifica:** Protezione contro divisione per zero (1e-6).

```python
def test_compute_amplitude_ratios_zero_guard():
    """Denominatore zero protetto da 1e-6."""
    all_amps = np.array([[1.0, 1.0, 0.0, 0.0, 0.5, 0.5, 0.5, 0.5]])
    defect_history = [{'Date': datetime(2026, 1, 1)}]
    
    ratio_sx_dx, ratio_fr, ratio_lv = compute_amplitude_ratios(defect_history, all_amps)
    
    # Non dovrebbe dare inf, ma (2.0 / 1e-6) = grande numero ma finito
    assert np.isfinite(ratio_sx_dx[0])
```

### Test 4: `test_compute_evolutive_metrics_daily_grouping`
**Verifica:** Aggrega ratios per giorno.

```python
def test_compute_evolutive_metrics_daily_grouping():
    """Raggruppa due run nello stesso giorno → media."""
    ratio_sx_dx = np.array([1.0, 1.0])  # Identici
    ratio_fr    = np.array([0.5, 0.5])
    ratio_lv    = np.array([2.0, 2.0])
    lambda_all  = np.ones((2, 8))
    dates_num   = np.array([datenum(datetime(2026, 1, 1, 10, 0)), 
                            datenum(datetime(2026, 1, 1, 15, 0))])
    defect_history = [{'Date': datetime(2026, 1, 1, 10, 0)}, 
                      {'Date': datetime(2026, 1, 1, 15, 0)}]
    
    avg_sx_dx, avg_fr, avg_lv, avg_lam, period_dates, periods = compute_evolutive_metrics(
        defect_history, ratio_sx_dx, ratio_fr, ratio_lv, lambda_all, 
        dates_num, grouping_mode='daily'
    )
    
    # Un solo periodo (stesso giorno) con medie
    assert len(avg_sx_dx) == 1
    assert np.isclose(avg_sx_dx[0], 1.0)
    assert np.isclose(avg_fr[0], 0.5)
```

### Test 5: `test_compute_evolutive_metrics_run_grouping`
**Verifica:** Nessun raggruppamento con grouping='run'.

```python
def test_compute_evolutive_metrics_run_grouping():
    """grouping='run' → no aggregation, identico a input."""
    ratio_sx_dx = np.array([1.0, 2.0, 3.0])
    ratio_fr    = np.array([0.5, 1.0, 1.5])
    ratio_lv    = np.array([2.0, 3.0, 4.0])
    lambda_all  = np.random.rand(3, 8)
    dates_num   = np.array([datenum(datetime(2026, 1, 1)), 
                            datenum(datetime(2026, 1, 2)), 
                            datenum(datetime(2026, 1, 3))])
    defect_history = [{'Date': datetime(2026, 1, 1)}, 
                      {'Date': datetime(2026, 1, 2)}, 
                      {'Date': datetime(2026, 1, 3)}]
    
    avg_sx_dx, avg_fr, avg_lv, avg_lam, period_dates, periods = compute_evolutive_metrics(
        defect_history, ratio_sx_dx, ratio_fr, ratio_lv, lambda_all,
        dates_num, grouping_mode='run'
    )
    
    assert len(avg_sx_dx) == 3  # Tre periodi separati
    assert np.allclose(avg_sx_dx, ratio_sx_dx)  # Identici (nessuna aggregazione)
```

### Test 6: `test_compute_evolutive_metrics_weekly_grouping`
**Verifica:** Raggruppamento settimanale (ISO week Monday-based).

```python
def test_compute_evolutive_metrics_weekly_grouping():
    """Raggruppa per settimana ISO (lunedì-domenica)."""
    ratio_sx_dx = np.array([1.0, 1.5, 2.0])
    ratio_fr    = np.array([0.5, 0.75, 1.0])
    ratio_lv    = np.array([2.0, 2.5, 3.0])
    lambda_all  = np.ones((3, 8))
    # 2026-01-05 is Monday, 2026-01-12 is next Monday
    dates_num   = np.array([datenum(datetime(2026, 1, 5)),   # Week 1
                            datenum(datetime(2026, 1, 6)),   # Week 1
                            datenum(datetime(2026, 1, 12))]) # Week 2
    defect_history = [{'Date': datetime(2026, 1, 5)}, 
                      {'Date': datetime(2026, 1, 6)}, 
                      {'Date': datetime(2026, 1, 12)}]
    
    avg_sx_dx, avg_fr, avg_lv, avg_lam, period_dates, periods = compute_evolutive_metrics(
        defect_history, ratio_sx_dx, ratio_fr, ratio_lv, lambda_all,
        dates_num, grouping_mode='weekly'
    )
    
    # Due settimane
    assert len(avg_sx_dx) == 2
    # Week 1: mean([1.0, 1.5])
    assert np.isclose(avg_sx_dx[0], 1.25)
```

### Test 7: `test_compute_amplitude_ratios_nan_handling`
**Verifica:** Trattamento NaN con 'omitnan' (come MATLAB mean(..., 'omitnan')).

```python
def test_compute_amplitude_ratios_nan_handling():
    """Se un'ampiezza è NaN, il ratio è NaN (mean omitnan gestisce la riga)."""
    all_amps = np.array([
        [1.0, 1.0, 2.0, 2.0, np.nan, 0.5, 0.5, 0.5],
        [2.0, 2.0, 1.0, 1.0, 0.3, 0.3, 0.3, 0.3],
    ])
    defect_history = [{'Date': datetime(2026, 1, 1)}, {'Date': datetime(2026, 1, 2)}]
    
    ratio_sx_dx, ratio_fr, ratio_lv = compute_amplitude_ratios(defect_history, all_amps)
    
    # Primo ratio potrebbe essere NaN o un valore (dipende dalla colonna NaN)
    assert len(ratio_sx_dx) == 2
    # Secondo ratio dovrebbe essere finito
    assert np.isfinite(ratio_sx_dx[1])
```

---

## Quality Gates

1. **Matematica:** Ratios via formule esatte (linee 2145-2147 MATLAB), lambda da periodogramma
2. **Aggregazione:** Media con 'omitnan' (MATLAB default)
3. **Grouping modes:** 'run', 'daily', 'weekly', 'monthly' (riuso dateshift logic da single_analysis_psd.py)
4. **Test coverage:** Tutte le 7 test passano ✓
5. **Type hints:** Tutte le funzioni hanno type hints (ndarray, datetime, str, **kwargs)
6. **Docstring:** One-liner per ogni funzione
7. **Pure functions:** Zero side effects, zero UI state

---

## Implementazione

### Ordine (TDD: test first)
1. Scrivi tutti i 7 test in `tests/test_app_single_analysis_evolutive.py`
2. Esegui test (tutti fallono)
3. Traduci MATLAB linee 2123-2147, 4258-4384 in Python
4. Revisione matematica (ratios, aggregazione, dateshift)
5. Commit e push

---

## Note MATLAB→Python

- **MATLAB `(A_SX_F + A_SX_R) / max(A_DX_F + A_DX_R, 1e-6)`** → **Python elemento-wise con guard clauses**
- **MATLAB `mean(X, 'omitnan')`** → **Python `np.nanmean(X)` oppure `np.mean(X[~np.isnan(X)])`**
- **MATLAB `dateshift(dt - days(1), 'start', 'week') + days(1)`** → **Riuso `_round_datetime_to_period()` da single_analysis_psd.py**
- **MATLAB `unique(dates_rounded)` returns sorted** → **Python `sorted()` + rebuild index map**

---

## Fuori Scope

- UI callbacks (pop_grouping, aggiornamento grafici) — restano in main_window.py
- Plotting (asse X log, scatter colorato, datetick) — restano in signal_plotting.py (plot_temporal_trend) e evolutive_tab.py (GUI)
- RawDataStore access — vai attraverso defect_history parameter

---

## Effort Estimate

- Test writing: 35 min (7 test con datenum/datetime, ratios formula, grouping modes)
- MATLAB translation: 40 min (3 funzioni medie ~80 righe, dateshift logic, mean aggregation)
- Mathematical review: 20 min (ratios formula, aggregazione, dateshift equivalence, NaN handling)
- Integration: 10 min (type hints, docstrings)
- **Total: ~1.5 ore** (subagent + review)
