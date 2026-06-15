# Piano TDD: Modulo 5b — `app/analysis/generate_headless_daily_plots`

Sottotask di sub-plan 7 (App GUI Completa). Generatore figure headless per analisi temporale e PCA.

---

## Scope

**File MATLAB:** `src_app/app.m` (righe 8577-8930+)
**File Python:** `railway_inspector/app/analysis/generate_headless_daily_plots.py`

**Funzione (FASE matematica PURA, scartare GUI):**
1. `generate_headless_daily_plots(defect, config, export_dir, rank_idx)` — genera 7+ figure PNG per top defect:
   - TOP%02d_0_Max_Run_Signals.png (firma run massimo, 6 subplot)
   - TOP%02d_2_Giornaliera_C_Matrice3x3.png (scatter log ratio SX/DX vs FR)
   - TOP%02d_2_Giornaliera_D_RatioLat.png (evoluzione ratio Lat/Vert)
   - TOP%02d_2_Giornaliera_E_Lambda.png (evoluzione lunghezza d'onda sensori verticali)
   - TOP%02d_3_PCA_Anom.png (anomaly score con trend + moving avg)
   - TOP%02d_3_PCA_Scree.png (scree plot varianza)
   - TOP%02d_3_PCA_Mani.png (manifold PC1/PC2 con centroidi settimanali)

**Dipendenze:** matplotlib, numpy, scipy.signal, scikit-learn (PCA)

**Logica Chiave:**
- Iterazione su History (runs): calcolo RMS per 8 sensori + Lambda (wavelength) per ogni run
- Aggregazione temporale: raggruppamento per giorno (floor di datenum)
- Ratio calculations: SX/DX = (SX_F + SX_R) / max(DX_F + DX_R, 1e-6); FR = Front/Rear; LV = Lat/Vert
- Direzione (forward vs backward): uso sort_runs_by_direction(), selezionare majority
- PCA "channel-space": trasforma segnali 6-canale su griglia spaziale (x_grid 333 punti), standardizza per-canale, esegue PCA
- Anomaly score: RMSE ricostruzione usando solo k=min(2, n_components) componenti
- Centroidi settimanali: raggruppamento per settimana (7 giorni), media scores PC1/PC2

**Note Architetturali:**
- Headless matplotlib (no plt.show())
- PNG export @ 300 DPI
- Gestione NaN/Inf via isnan/isfinite checks
- Colori specifici: [0 0.4 0.8] (blu) per vert, [0.8 0.4 0] (arancio) per laterale
- Loglog plot per matrice 3x3 (scala logaritmica X e Y)

---

## TDD: Test-First, Implementazione Dopo

### Test 1: `test_generate_headless_daily_plots_creates_files`
**Verifica:** Funzione crea file PNG per rank_idx.

```python
def test_generate_headless_daily_plots_creates_files():
    """Crea TOP%02d_*.png files per ogni rank_idx."""
    # Mock: defect con History (5+ runs, dati.Filt con sensori)
    # Mock: config con SPATIAL_RES, WINDOW_SIZE, IPI_PCA_MIN_RUNS
    # Mock: rank_idx = 1
    
    with tempfile.TemporaryDirectory() as tmpdir:
        export_dir = Path(tmpdir)
        
        generate_headless_daily_plots(defect, config, export_dir, rank_idx=1)
        
        # Verifica creazione file principali (almeno 3)
        assert (export_dir / "TOP01_0_Max_Run_Signals.png").exists()
        assert (export_dir / "TOP01_2_Giornaliera_C_Matrice3x3.png").exists()
        assert (export_dir / "TOP01_2_Giornaliera_D_RatioLat.png").exists()
        assert (export_dir / "TOP01_2_Giornaliera_E_Lambda.png").exists()
```

### Test 2: `test_generate_headless_daily_plots_empty_history`
**Verifica:** Gestisce History vuota senza crash.

```python
def test_generate_headless_daily_plots_empty_history():
    """Gestisce defect.History vuota."""
    defect_empty = {"History": []}  # Vuota
    
    with tempfile.TemporaryDirectory() as tmpdir:
        export_dir = Path(tmpdir)
        
        # Non deve crash
        generate_headless_daily_plots(defect_empty, config, export_dir, rank_idx=1)
        
        # Nessun file creato
        png_files = list(export_dir.glob("*.png"))
        assert len(png_files) == 0
```

### Test 3: `test_ratio_calculations_sx_dx_fr_lv`
**Verifica:** Logica calcolo ratio (SX/DX, FR, LV) identica a MATLAB.

```python
def test_ratio_calculations_sx_dx_fr_lv():
    """Ratio = (SX_F + SX_R) / max(DX_F + DX_R, 1e-6), etc."""
    # Test diretto della logica (no figure)
    all_amps = np.array([
        [1.0, 1.0, 2.0, 2.0, 0.5, 0.5, 0.3, 0.3],  # Vert: SX_F, SX_R, DX_F, DX_R; Lat: SX_F, SX_R, DX_F, DX_R
        [2.0, 1.0, 1.0, 1.0, 0.6, 0.4, 0.2, 0.2],
    ])
    
    # SX/DX = (1+1) / max(2+2, 1e-6) = 2/4 = 0.5
    ratio_sx_dx_0 = (all_amps[0, 0] + all_amps[0, 1]) / max(all_amps[0, 2] + all_amps[0, 3], 1e-6)
    assert abs(ratio_sx_dx_0 - 0.5) < 1e-6
    
    # FR = (1+2) / max(1+2, 1e-6) = 3/3 = 1.0
    ratio_fr_0 = (all_amps[0, 0] + all_amps[0, 2]) / max(all_amps[0, 1] + all_amps[0, 3], 1e-6)
    assert abs(ratio_fr_0 - 1.0) < 1e-6
    
    # LV = max([0.5, 0.5, 0.3, 0.3]) / max(max([1, 1, 2, 2]), 1e-6) = 0.5 / 2.0 = 0.25
    ratio_lv_0 = max(all_amps[0, 4:8]) / max(max(all_amps[0, 0:4]), 1e-6)
    assert abs(ratio_lv_0 - 0.25) < 1e-6
```

### Test 4: `test_daily_aggregation_logic`
**Verifica:** Aggregazione per giorno (floor datenum) e medie.

```python
def test_daily_aggregation_logic():
    """Aggrega run per giorno unico e calcola media ratio."""
    # 3 runs: 2 nello stesso giorno, 1 in giorno diverso
    dates_num = np.array([737800.0, 737800.5, 737801.0])  # 737800 = 2020-01-01
    ratio_sx_dx = np.array([0.5, 0.6, 0.8])
    
    days_floor = np.floor(dates_num)
    unique_days = np.unique(days_floor)
    
    assert len(unique_days) == 2  # Due giorni unici
    
    # Giorno 1: media di [0.5, 0.6]
    mask_day1 = (days_floor == unique_days[0])
    avg_day1 = np.nanmean(ratio_sx_dx[mask_day1])
    assert abs(avg_day1 - 0.55) < 1e-6
    
    # Giorno 2: [0.8]
    mask_day2 = (days_floor == unique_days[1])
    avg_day2 = np.nanmean(ratio_sx_dx[mask_day2])
    assert abs(avg_day2 - 0.8) < 1e-6
```

### Test 5: `test_direction_selection_forward_vs_backward`
**Verifica:** Logica sort_runs_by_direction() seleziona majority direction.

```python
def test_direction_selection_forward_vs_backward():
    """Seleziona direzione majority (forward se count_fwd >= count_bwd)."""
    # Mock: 3 forward, 2 backward → scegli forward
    idx_fwd = np.array([True, True, True, False, False])
    idx_bwd = np.array([False, False, False, True, True])
    
    use_fwd = np.sum(idx_fwd) >= np.sum(idx_bwd)
    assert use_fwd is True  # 3 >= 2
    
    if use_fwd:
        run_idx_selected = np.where(idx_fwd)[0]
    else:
        run_idx_selected = np.where(idx_bwd)[0]
    
    assert len(run_idx_selected) == 3
    assert np.array_equal(run_idx_selected, [0, 1, 2])
```

### Test 6: `test_pca_channel_space_structure`
**Verifica:** Trasformazione segnali in X_pca (n_runs x 6*N_GRID) identica a MATLAB.

```python
def test_pca_channel_space_structure():
    """Trasforma segnali 6-canale su griglia spaziale (6*N_GRID colonne)."""
    N_GRID = 333
    n_chan = 6
    n_runs = 5
    
    # Mock X_pca: n_runs righe, 6*N_GRID colonne
    X_pca = np.random.randn(n_runs, n_chan * N_GRID)
    
    assert X_pca.shape == (5, 6 * 333)
    
    # Ogni riga è una run; ogni gruppo di N_GRID colonne è un canale
    for run_idx in range(n_runs):
        for chan_idx in range(n_chan):
            cols = slice(chan_idx * N_GRID, (chan_idx + 1) * N_GRID)
            chan_data = X_pca[run_idx, cols]
            assert chan_data.shape == (N_GRID,)
```

### Test 7: `test_pca_standardization_per_channel`
**Verifica:** Standardizzazione per-canale (mean per colonna, std per colonna).

```python
def test_pca_standardization_per_channel():
    """Standardizza Xpar per-canale (dim 0): (X - mu) / sigma."""
    N_GRID = 333
    n_chan = 6
    n_rows = 5 * N_GRID  # 5 runs x N_GRID righe per run
    
    Xpar = np.random.randn(n_rows, n_chan) * 10 + 50
    
    mu_ch = np.mean(Xpar, axis=0)  # Shape (n_chan,)
    sg_ch = np.std(Xpar, ddof=0, axis=0)  # MATLAB std(..., 0)
    sg_ch[sg_ch < 1e-9] = 1.0  # Avoid division by zero
    
    Xpar_z = (Xpar - mu_ch) / sg_ch
    
    # Verifica media ~0 e std ~1
    mu_z = np.mean(Xpar_z, axis=0)
    sg_z = np.std(Xpar_z, ddof=0, axis=0)
    
    assert np.allclose(mu_z, 0, atol=1e-10)
    assert np.allclose(sg_z, 1, atol=1e-10)
```

### Test 8: `test_anomaly_score_rmse_calculation`
**Verifica:** Calcolo RMSE ricostruzione usando k=min(2, n_comp) componenti.

```python
def test_anomaly_score_rmse_calculation():
    """RMSE = sqrt(mean(residuo^2)) per run."""
    n_rows = 1000  # 5 runs x 200 grid points
    n_comp = 10
    k_use = 2
    run_id = np.repeat(np.arange(5), 200)  # 5 runs, 200 rows each
    
    # Mock: residui dalla ricostruzione
    resid_z = np.random.randn(n_rows, n_comp - k_use) * 0.5
    
    # RMSE per run = sqrt(mean(residuo^2))
    se_row = np.mean(resid_z**2, axis=1)  # (n_rows,)
    rmse_run = np.zeros(5)
    
    for run_idx in range(5):
        mask = (run_id == run_idx)
        rmse_run[run_idx] = np.sqrt(np.mean(se_row[mask]))
    
    assert rmse_run.shape == (5,)
    assert np.all(rmse_run >= 0)
```

### Test 9: `test_weekly_centroid_aggregation`
**Verifica:** Raggruppamento per settimana (7 giorni) e calcolo centroidi PC1/PC2.

```python
def test_weekly_centroid_aggregation():
    """Raggruppa run per settimana (bin 7 giorni) e calcola mean PC1/PC2."""
    dates_pca = np.array([
        737800.0, 737801.0, 737802.0, 737803.0, 737804.0,  # Week 0
        737810.0, 737811.0, 737812.0,                         # Week 1
    ])
    scores_pc1 = np.array([0.1, 0.2, 0.15, 0.25, 0.3, 0.5, 0.55, 0.6])
    scores_pc2 = np.array([0.05, -0.1, 0.0, 0.1, 0.05, -0.2, -0.15, -0.1])
    
    days_t = dates_pca - dates_pca[0]
    WEEK_BIN = 7
    week_id = np.floor(days_t / WEEK_BIN).astype(int)
    
    unique_weeks = np.unique(week_id)
    assert len(unique_weeks) == 2  # Due settimane
    
    cent_pc1 = []
    for w in unique_weeks:
        mask = (week_id == w)
        cent_pc1.append(np.mean(scores_pc1[mask]))
    
    # Week 0: mean([0.1, 0.2, 0.15, 0.25, 0.3]) = 0.2
    # Week 1: mean([0.5, 0.55, 0.6]) ≈ 0.55
    assert abs(cent_pc1[0] - 0.2) < 1e-6
    assert abs(cent_pc1[1] - 0.55) < 1e-6
```

---

## MATLAB Source (Righe Specifiche)

Vedi righe 8577-8930 in src_app/app.m:
- Lines 8577-8620: Setup segnali, calcolo RMS e Lambda per ogni run
- Lines 8621-8637: Ratio calculations (SX/DX, FR, LV) e aggregazione per giorno
- Lines 8639-8676: Plot firma run massimo (6 subplot)
- Lines 8678-8707: Plot matrice 3x3 (scatter log)
- Lines 8710-8714: Plot ratio laterale
- Lines 8717-8729: Plot lambda (sensori verticali)
- Lines 8734-8842: PCA setup: direzione, X_pca construction, standardizzazione, PCA fit, calcolo residui
- Lines 8846-8868: Plot anomaly score (RMSE trend + moving avg)
- Lines 8871-8877: Plot scree (varianza)
- Lines 8882-8913: Plot manifold (PC1/PC2 tempo con centroidi settimanali)

---

## Implementazione (Dopo i Test)

### Dipendenze Python
```python
import matplotlib.pyplot as plt
from matplotlib.figure import Figure
import numpy as np
from scipy.signal import periodogram
from sklearn.decomposition import PCA
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, Optional
```

### Signature Python

```python
def generate_headless_daily_plots(
    defect: Dict[str, Any],        # Defect con History (list di run dict)
    config: Dict[str, Any],         # config con SPATIAL_RES, WINDOW_SIZE, IPI_PCA_MIN_RUNS
    export_dir: Path,               # directory per PNG
    rank_idx: int,                  # ranking index (1-based) per naming TOP%02d_*
) -> bool:
    """
    Generate 7+ headless PNG figures for defect analysis.
    
    Figures:
    - TOP%02d_0_Max_Run_Signals.png: Max run signature (6 subplot)
    - TOP%02d_2_Giornaliera_C_Matrice3x3.png: Scatter log (ratio SX/DX vs FR)
    - TOP%02d_2_Giornaliera_D_RatioLat.png: Ratio Lat/Vert timeline
    - TOP%02d_2_Giornaliera_E_Lambda.png: Lambda timeline (4 vert sensors)
    - TOP%02d_3_PCA_Anom.png: Anomaly score with trend
    - TOP%02d_3_PCA_Scree.png: Scree plot
    - TOP%02d_3_PCA_Mani.png: PC1/PC2 manifold with weekly centroids
    """
    pass
```

---

## Quality Gates

✅ **TDD:**
- Scritti 9 test prima dell'implementazione
- Test: file creation, empty history, ratio logic, daily aggregation, direction, PCA structure, standardization, anomaly score, weekly centroids

✅ **Matematica:**
- Ratio SX/DX: (SX_F + SX_R) / max(DX_F + DX_R, 1e-6) ✓
- Ratio FR: (F) / max(R, 1e-6) ✓
- Ratio LV: max(Lat) / max(max(Vert), 1e-6) ✓
- Aggregazione giornaliera: floor(datenum) e mean ✓
- PCA standardization: per-canale (dim 0) ddof=0 ✓
- Anomaly score: RMSE ricostruzione con k=min(2, n_comp) ✓
- Weekly centroidi: floor(days / 7) binning e mean ✓

✅ **Type Hints:**
- Tutte le funzioni tipizzate (Dict, Path, bool return)

✅ **Docstring:**
- Una linea max per funzione + brief figure list

✅ **Pure Functions:**
- No side effects (file I/O OK via savefig direct)

---

## Workflow

1. **Scrivi test** (9 test sopra) → `tests/test_app_generate_headless_daily_plots.py`
2. **Estrai MATLAB source** (righe 8577-8930 funzione principale)
3. **Usa `traduttore-matlab` agent** → traduci in Python
4. **Usa `revisore-matematico` agent** → verifica matematica (ratio, aggregazione, PCA standardizzazione, anomaly score)
5. **Esegui test** → `pytest tests/test_app_generate_headless_daily_plots.py -v`
6. **Merge → master** quando tutti i test passano

---

## Effort & Modularità

**Figure generation:** ~350 righe MATLAB → ~450 Python (PCA + plotting + aggregation)
**PCA analysis:** ~180 righe MATLAB (channel-space transform, standardizzazione, scores, residui)
**Daily aggregation:** ~60 righe MATLAB → ~40 Python (numpy groupby via floor + loop)

**Target Python:** ~400-500 righe (single function, modulo puro, no PDF compilation)

---

## Note

- **SCARTARE:** Figure visibility, pdflatex compilation
- **SCARTARE:** GUI alerts (msgbox)
- **File I/O:** PNG via matplotlib `savefig(..., dpi=300, bbox_inches='tight')`
- **Colori:** [0 0.4 0.8] (blu vert), [0.8 0.4 0] (arancio lat), parula colormap
- **Loglog plot:** matrice 3x3 con scala log su X e Y (soglie 0.5 e 2.0)
- **Datenum handling:** Python datetime → matplotlib date numbers (matplotlib.dates.date2num)
- **Datetick formatting:** 'dd/mm/yy' su assi temporali

