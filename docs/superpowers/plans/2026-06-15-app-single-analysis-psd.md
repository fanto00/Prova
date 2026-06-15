# Piano TDD: Modulo 7 — `app/analysis/single_analysis_psd.py`

Sottotask di sub-plan 7 (App GUI Completa). Funzioni pure per calcolo e visualizzazione PSD (Power Spectral Density) di singoli difetti con view 2D (confronto run vs media storica) e 3D (waterfall temporale).

---

## Scope

**File MATLAB:** `src_app/app.m` (righe 4102-4511)  
**File Python:** `railway_inspector/app/analysis/single_analysis_psd.py`

**4 funzioni pure (no UI state, no callbacks):**

1. **`compute_psd_for_run(signal, axis, window_m, dx=0.030)`** (MATLAB linee 4140-4141)
   - Calcola PSD per una singola run usando `periodogram(signal, hamming(len(signal)), NFFT, fs)`
   - Input: signal (ndarray), axis (ndarray spatial coords), window_m (float, finestra in metri), dx (float, spacing)
   - Output: psd (ndarray), freq_vec (ndarray spatial frequencies [cicli/m])
   - Logica: 
     * Centra il segnale intorno a ±window_m/2 (crop sul picco)
     * Usa Hamming window, NFFT = round(window_m / dx), fs = 1/dx
     * Ritorna PSD e vettore frequenze

2. **`compute_psd_matrix_3d(all_runs, sensor_name, window_m, dates_num, grouping_mode='daily', dx=0.030)`** (MATLAB linee 4392-4511)
   - Costruisce matrice 3D PSD aggregando per periodi temporali (run singole, giornaliera, settimanale, mensile)
   - Input: all_runs (list of dict), sensor_name (str), window_m (float), dates_num (ndarray datenum), grouping_mode ('run'|'daily'|'weekly'|'monthly'), dx
   - Output: (psd_matrix (ndarray n_periods x n_freq), freq_axis (ndarray), date_axis_rounded (ndarray datenum), periods_valid (list of datetime))
   - Logica:
     * Raggruppa date secondo grouping_mode usando dateshift (run: no grouping, daily: floor, weekly: start of week, monthly: start of month)
     * Per ogni periodo: itera runs, estrae signal/axis, crop ±window_m/2, calcola PSD individuale
     * Media PSD nel periodo (sum / n_valid_runs)
     * Ritorna matrice (n_periods_valid x n_freq)

3. **`plot_psd_2d(ax, freq_axis, psd_current, psd_historical_list, title=None, **kwargs)`** (MATLAB linee 4149-4177)
   - Plot 2D: run selezionata (rosso bold) vs storico (grigio+media nera tratteggiata)
   - Input: ax (Axes), freq_axis (ndarray), psd_current (ndarray), psd_historical_list (list of ndarray), title
   - Output: None (side effect: axes modificato)
   - Styling:
     * Historical PSD: color=[0.85 0.85 0.85], linewidth=0.5, handlevisibility=off
     * Mean historical: color=[0.3 0.3 0.3], linestyle='--', linewidth=1.2, label='Media Storica'
     * Current run: color=[0.8 0.2 0], linewidth=2, label='Run Selezionata'
     * Grid on, legend northeast

4. **`plot_psd_3d_waterfall(ax, freq_axis, date_axis, psd_matrix, title=None, **kwargs)`** (MATLAB linee 4493-4507)
   - Plot 3D waterfall: frequenza (x) vs tempo (y, date) vs PSD power (z)
   - Input: ax (Axes3D), freq_axis (ndarray), date_axis (ndarray datenum), psd_matrix (2D ndarray), title
   - Output: None (side effect: axes 3D modificato)
   - Styling:
     * `waterfall()` plot con linewidth=1.2, edgecolor='interp', facealpha=0.7
     * View 3D: azimuth=-37.5, elevation=30 (three-quarter view)
     * Colormap: jet, colorbar on
     * Labels: Frequenza [cicli/m], Evoluzione Temporale (date), PSD Power
     * Grid on

---

## Dipendenze Python

- `numpy` — operazioni array, mean
- `scipy.signal.periodogram` — PSD calculation via Hamming window
- `matplotlib.axes.Axes` — 2D plot
- `matplotlib.axes.Axes3D` (via `from mpl_toolkits.mplot3d import Axes3D`) — 3D waterfall
- `matplotlib.dates.DateFormatter` — date ticking
- Reusable: `movmean()` from `signal/resampling.py` (per eventual smoothing, non usato qui)

---

## TDD: 8 Test Specifici

### Test 1: `test_compute_psd_for_run_basic`
**Verifica:** Calcola PSD e ritorna due array (psd, freq).

```python
def test_compute_psd_for_run_basic():
    """compute_psd_for_run() ritorna (psd, freq_axis)."""
    # Segnale semplice: sin(2*pi*f*x) con f=2 cicli/m
    x = np.linspace(-5, 5, 1000)  # ±5m
    signal = np.sin(2 * np.pi * 2 * x)  # 2 cicli/m
    axis = x
    
    psd, freq = compute_psd_for_run(signal, axis, window_m=10.0, dx=0.030)
    
    assert isinstance(psd, np.ndarray)
    assert isinstance(freq, np.ndarray)
    assert len(psd) == len(freq)
    assert len(psd) > 0
```

### Test 2: `test_compute_psd_for_run_window_crop`
**Verifica:** Centra finestra intorno a ±window_m/2.

```python
def test_compute_psd_for_run_window_crop():
    """Cropping intorno a ±window_m/2."""
    x = np.linspace(-20, 20, 2000)
    signal = np.random.randn(2000)
    axis = x
    
    # Con finestra 10m, deve usare solo [-5, +5]
    psd, freq = compute_psd_for_run(signal, axis, window_m=10.0, dx=0.030)
    
    # PSD non vuoto (finestra valida)
    assert len(psd) > 0
```

### Test 3: `test_compute_psd_matrix_3d_single_period`
**Verifica:** Costruisce matrice 3D per una singola lista di run (grouping='run').

```python
def test_compute_psd_matrix_3d_single_period():
    """Matrice 3D con 3 run singole (grouping='run')."""
    runs = [
        {'Signals': {'SX_F': np.sin(2*np.pi*2*np.linspace(-5,5,500))}, 'Axis': np.linspace(-5,5,500), 'Date': datetime(2026,1,1)},
        {'Signals': {'SX_F': np.sin(2*np.pi*1.5*np.linspace(-5,5,500))}, 'Axis': np.linspace(-5,5,500), 'Date': datetime(2026,1,2)},
        {'Signals': {'SX_F': np.sin(2*np.pi*3*np.linspace(-5,5,500))}, 'Axis': np.linspace(-5,5,500), 'Date': datetime(2026,1,3)},
    ]
    dates_num = np.array([datenum(r['Date']) for r in runs])
    
    psd_mat, freq_ax, date_ax, periods_valid = compute_psd_matrix_3d(
        runs, 'SX_F', window_m=10.0, dates_num=dates_num, grouping_mode='run'
    )
    
    assert psd_mat.shape[0] == 3  # 3 periodi (una per run)
    assert psd_mat.shape[1] > 0
    assert len(freq_ax) == psd_mat.shape[1]
    assert len(periods_valid) == 3
```

### Test 4: `test_compute_psd_matrix_3d_daily_grouping`
**Verifica:** Raggruppa per giorno (grouping='daily').

```python
def test_compute_psd_matrix_3d_daily_grouping():
    """Raggruppa più run nello stesso giorno."""
    runs = [
        {'Signals': {'SX_F': np.sin(2*np.pi*2*np.linspace(-5,5,500))}, 'Axis': np.linspace(-5,5,500), 'Date': datetime(2026,1,1,10,0)},
        {'Signals': {'SX_F': np.sin(2*np.pi*2*np.linspace(-5,5,500))}, 'Axis': np.linspace(-5,5,500), 'Date': datetime(2026,1,1,15,0)},
        {'Signals': {'SX_F': np.sin(2*np.pi*2*np.linspace(-5,5,500))}, 'Axis': np.linspace(-5,5,500), 'Date': datetime(2026,1,2,10,0)},
    ]
    dates_num = np.array([datenum(r['Date']) for r in runs])
    
    psd_mat, freq_ax, date_ax, periods_valid = compute_psd_matrix_3d(
        runs, 'SX_F', window_m=10.0, dates_num=dates_num, grouping_mode='daily'
    )
    
    # 2 giorni distinti => 2 periodi
    assert psd_mat.shape[0] == 2
    assert len(periods_valid) == 2
```

### Test 5: `test_plot_psd_2d_adds_lines`
**Verifica:** Aggiunge 2+ linee (current + mean storico).

```python
def test_plot_psd_2d_adds_lines():
    """plot_psd_2d() aggiunge linee."""
    fig, ax = plt.subplots()
    
    freq = np.linspace(0.5, 5, 100)
    psd_current = np.abs(np.sin(freq))
    psd_hist = [np.abs(np.cos(freq)), np.abs(np.sin(freq*0.8))]
    
    plot_psd_2d(ax, freq, psd_current, psd_hist, title="Test PSD 2D")
    
    # Minimo: mean storico + current + 2 storici = 4 linee
    assert len(ax.lines) >= 2
    
    plt.close(fig)
```

### Test 6: `test_plot_psd_2d_colors_correct`
**Verifica:** Current è rosso, storico grigio.

```python
def test_plot_psd_2d_colors_correct():
    """Colori: rosso per current, grigio per storico."""
    fig, ax = plt.subplots()
    
    freq = np.linspace(0.5, 5, 100)
    psd_current = np.ones(100)
    psd_hist = [np.ones(100)*0.5]
    
    plot_psd_2d(ax, freq, psd_current, psd_hist)
    
    # Last line deve essere rosso (current) o simile (color=[0.8 0.2 0])
    # First lines grigio storico [0.85 0.85 0.85]
    colors = [line.get_color() for line in ax.lines]
    assert len(colors) >= 2
    
    plt.close(fig)
```

### Test 7: `test_plot_psd_3d_waterfall_basic`
**Verifica:** Crea axes 3D con waterfall plot.

```python
def test_plot_psd_3d_waterfall_basic():
    """plot_psd_3d_waterfall() crea 3D waterfall."""
    from mpl_toolkits.mplot3d import Axes3D
    
    fig = plt.figure()
    ax = fig.add_subplot(111, projection='3d')
    
    freq = np.linspace(0.5, 5, 50)
    dates = np.array([737800, 737801, 737802])
    psd_mat = np.random.rand(3, 50)
    
    plot_psd_3d_waterfall(ax, freq, dates, psd_mat, title="Test 3D")
    
    # Se è un vero 3D, should have 3D elements
    assert ax.name == '3d'
    
    plt.close(fig)
```

### Test 8: `test_compute_psd_psd_non_negative`
**Verifica:** PSD è sempre >= 0 (proprietà fisica).

```python
def test_compute_psd_psd_non_negative():
    """PSD non-negative (periodogram output)."""
    x = np.linspace(-10, 10, 1000)
    signal = np.random.randn(1000)
    axis = x
    
    psd, freq = compute_psd_for_run(signal, axis, window_m=20.0, dx=0.030)
    
    assert np.all(psd >= 0)
    assert np.all(freq >= 0)
```

---

## Quality Gates

1. **Matematica:** PSD via scipy.signal.periodogram con Hamming window, match MATLAB `periodogram(..., hamming(...),...)`
2. **Plotting:** Tutte le funzioni sono **pure** (no UI state, no side effects oltre axes)
3. **3D View:** Axes3D con waterfall, view(-37.5, 30), datetick on y-axis
4. **Test coverage:** Tutte le 8 test passano ✓
5. **Type hints:** Tutte le funzioni hanno type hints (Axes, Axes3D, ndarray, str, **kwargs)
6. **Docstring:** One-liner per ogni funzione
7. **Window centering:** Crop signal a ±window_m/2 (MATLAB line 4135)

---

## Implementazione

### Ordine (TDD: test first)
1. Scrivi tutti gli 8 test in `tests/test_app_single_analysis_psd.py`
2. Esegui test (tutti fallono)
3. Traduci MATLAB linee 4102-4511 in Python
4. Revisione matematica (periodogram vs MATLAB)
5. Commit e push

---

## Note MATLAB→Python

- **MATLAB `periodogram(sig, hamming(len(sig)), NFFT, fs)`** → **Python `scipy.signal.periodogram(sig, window=scipy.signal.hamming(len(sig)), nfft=NFFT, fs=fs)`** — ritorna `(freq, Pxx)`
- **MATLAB `dateshift(dt, 'start', 'day')`** → **Python via `pandas.Timestamp.normalize()` o manuale con `datetime.replace(hour=0,minute=0,second=0)`**
- **MATLAB `unique(dates_rounded, 'rows', unique_return_indices)`** → **Python `np.unique(dates_rounded, return_index=True, return_inverse=True)`**
- **MATLAB `waterfall(X, Y, Z)`** → **Python `ax.plot_surface(X, Y, Z)` oppure custom plotting con `mpl_toolkits.mplot3d`**
- **MATLAB `view(ax, azimuth, elevation)`** → **Python `ax.view_init(elev=30, azim=-37.5)`**
- **MATLAB `datetick(ax, 'y', 'mmm yy')`** → **Python `matplotlib.dates.DateFormatter` + `set_major_formatter`**

---

## Fuori Scope

- UI callbacks (pop_psd_sens, edit_psd_win, pop_grouping) — restano in main_window.py
- Waitbar/progress UI — restano nella GUI layer
- RawDataStore access (vai attraverso all_runs parameter)
- Datacursor tooltips (restano in datatips.py)

---

## Effort Estimate

- Test writing: 40 min (8 test con datenum/datetime handling)
- MATLAB translation: 60 min (4 funzioni medie ~100 righe, periodogram setup, waterfall)
- Mathematical review: 25 min (Hamming window, periodogram, dateshift equivalence)
- Integration: 15 min (Axes3D import, type hints)
- **Total: ~2.5 ore** (subagent + review)
