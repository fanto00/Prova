# Piano TDD: Modulo 1 — `app/analysis/drawing.py`

Sottotask di sub-plan 7 (App GUI Completa). Funzioni di rendering base per axes overlay.

---

## Scope

**File MATLAB:** `src_app/app.m` (righe 1846-4101)
**File Python:** `railway_inspector/app/analysis/drawing.py`

**4 funzioni:**
1. `draw_infra_overlay(ax, infra_table, x_limits)` (righe 1869-1916) — infrastruttura (crossing, joint, anomaly)
2. `draw_joints_overlay(ax, joints_table, x_limits)` (righe 1917-1937) — giunti (label + linee verticali)
3. `draw_signature_grid(M, orig_row, recon_row, title_str)` (righe 3290-4101) — griglia 3×8 (sensori vs ricostruzione PCA)
4. `helper_fft_shift(sig, shift_m, spatial_res)` (righe 1846-1865) — shift frequenza spaziale

**Dipendenze:** numpy, matplotlib, pandas
**Test database:** `Data/Database_damage_38-Garibaldi F.S. to Gioia.mat` (5 defetti reali)

---

## TDD: Test-First, Implementazione Dopo

### Test 1: `test_draw_infra_overlay_adds_lines`
**Verifica:** La funzione aggiunge line/scatter all'axes.

```python
import pytest
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from railway_inspector.app.analysis.drawing import draw_infra_overlay

def test_draw_infra_overlay_adds_lines():
    """draw_infra_overlay() deve aggiungere elementi all'axes."""
    fig, ax = plt.subplots()
    
    # Fixture: infra_table pandas con 3 location
    infra_table = pd.DataFrame({
        'coord': [0.5, 5.2, 10.8],
        'tipo': ['crossing', 'joint', 'anomaly'],
        'nome': ['XC-01', 'J-01', 'AN-01'],
    })
    
    # Prima: axes vuoto
    assert len(ax.lines) == 0
    assert len(ax.collections) == 0
    
    # Chiama la funzione
    draw_infra_overlay(ax, infra_table, x_limits=(0, 15))
    
    # Dopo: ax ha almeno una line o scatter
    assert len(ax.lines) > 0 or len(ax.collections) > 0
    
    plt.close(fig)
```

### Test 2: `test_draw_joints_overlay_adds_lines`
**Verifica:** La funzione aggiunge linee verticali per giunti.

```python
def test_draw_joints_overlay_adds_lines():
    """draw_joints_overlay() deve aggiungere vlines per giunti."""
    fig, ax = plt.subplots()
    
    # Fixture: joints_table
    joints_table = pd.DataFrame({
        'coord': [2.0, 8.5, 14.3],
        'name': ['Joint-01', 'Joint-02', 'Joint-03'],
    })
    
    initial_lines = len(ax.lines)
    draw_joints_overlay(ax, joints_table, x_limits=(0, 20))
    
    # Deve aggiungere almeno 3 linee (una per giunto)
    assert len(ax.lines) >= initial_lines + 3
    
    plt.close(fig)
```

### Test 3: `test_draw_signature_grid_shape`
**Verifica:** La griglia ha forma corretta (3×8 immagine).

```python
def test_draw_signature_grid_shape():
    """draw_signature_grid() crea una figura con 3×8 subplot."""
    import matplotlib.pyplot as plt
    from railway_inspector.app.analysis.drawing import draw_signature_grid
    
    # Fixture: matrice 3×8 (3 righe = [orig_reconstructed, original, residual], 8 colonne = sensori)
    M = np.random.randn(3, 8, 100)  # 3×8×100 (3 righe, 8 sensori, 100 sample temporali)
    orig_row = M[0]  # prima riga = originale
    recon_row = M[1]  # seconda riga = ricostruito
    
    fig = draw_signature_grid(M, orig_row, recon_row, title_str="Test Grid")
    
    # Verifica: figura creata, ha subplot
    assert fig is not None
    assert len(fig.axes) >= 24  # 3×8 = 24 subplot
    
    plt.close(fig)
```

### Test 4: `test_helper_fft_shift_preserves_length`
**Verifica:** FFT shift preserva lunghezza del segnale.

```python
def test_helper_fft_shift_preserves_length():
    """helper_fft_shift() preserva lunghezza del segnale."""
    from railway_inspector.app.analysis.drawing import helper_fft_shift
    
    sig = np.random.randn(1000)
    shift_m = 5.0  # 5 metri shift
    spatial_res = 0.030  # 3 cm per sample
    
    shifted = helper_fft_shift(sig, shift_m, spatial_res)
    
    # Lunghezza deve essere identica
    assert len(shifted) == len(sig)
    assert shifted.dtype in [np.float32, np.float64]
```

### Test 5: `test_draw_infra_overlay_with_real_db`
**Verifica:** Funzione funziona con dati veri dal database.

```python
def test_draw_infra_overlay_with_real_db():
    """draw_infra_overlay() funziona con dati reali."""
    from scipy.io import loadmat
    import pandas as pd
    
    # Carica database reale
    db_path = r'Data/Database_damage_38-Garibaldi F.S. to Gioia.mat'
    db = loadmat(db_path, squeeze_me=False)
    
    # Estrai primo difetto
    defect = db['MASTER_DB'][0, 0]
    infra = defect['Infrastructure'][0]  # Infrastructure string/cell
    
    # Crea fixture infra_table (simulato da MATLAB struct)
    infra_table = pd.DataFrame({
        'coord': [1.0, 5.0, 10.0],
        'tipo': ['crossing', 'joint', 'anomaly'],
        'nome': ['XC-01', 'J-01', 'AN-01'],
    })
    
    fig, ax = plt.subplots()
    draw_infra_overlay(ax, infra_table, x_limits=(0, 15))
    
    # Non deve crashare
    assert fig is not None
    plt.close(fig)
```

---

## MATLAB Source (Linee Specifiche)

### Funzione 1: `draw_infra_overlay` (righe 1869-1916)
```matlab
function draw_infra_overlay(ax, infra_table, x_limits)
    % Disegna overlay infrastruttura su axes
    % Visualizza crossing, joint, anomaly come vlines colorate
end
```

### Funzione 2: `draw_joints_overlay` (righe 1917-1937)
```matlab
function draw_joints_overlay(ax, joints_table, x_limits)
    % Disegna overlay giunti (vlines blu con label)
end
```

### Funzione 3: `draw_signature_grid` (righe 3290-4101)
```matlab
function fig = draw_signature_grid(M, orig_row, recon_row, title_str)
    % Crea figura 3×8 (3 righe = [ricostruito, originale, residuo], 8 colonne = sensori)
    % Ogni subplot è time-domain del segnale per uno specifico sensore
end
```

### Funzione 4: `helper_fft_shift` (righe 1846-1865)
```matlab
function shifted_sig = helper_fft_shift(sig, shift_m, spatial_res)
    % Shift frequenza spaziale via FFT
    % shift_m: metri (distanza shift)
    % spatial_res: risoluzione spaziale (metri per sample)
    % Usato per allineamento segnali multi-sensore
end
```

---

## Implementazione (Dopo i Test)

### Dipendenze Python
```python
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
from matplotlib.lines import Line2D
```

### Signature Python

```python
def draw_infra_overlay(
    ax: plt.Axes,
    infra_table: pd.DataFrame,
    x_limits: tuple[float, float]
) -> None:
    """Add infrastructure overlay (crossing/joint/anomaly) to axes."""
    pass

def draw_joints_overlay(
    ax: plt.Axes,
    joints_table: pd.DataFrame,
    x_limits: tuple[float, float]
) -> None:
    """Add joints overlay (vlines + labels) to axes."""
    pass

def draw_signature_grid(
    M: np.ndarray,
    orig_row: np.ndarray,
    recon_row: np.ndarray,
    title_str: str
) -> plt.Figure:
    """Create 3×8 grid (3 rows × 8 sensors) signature plot."""
    pass

def helper_fft_shift(
    sig: np.ndarray,
    shift_m: float,
    spatial_res: float
) -> np.ndarray:
    """Spatial frequency shift via FFT."""
    pass
```

---

## Quality Gates

✅ **TDD:**
- Scritti 5 test prima dell'implementazione
- Almeno 1 test con dati reali dal database

✅ **Matematica:**
- Revisione riga-per-riga MATLAB → Python
- `helper_fft_shift`: verificare fase FFT preservata

✅ **Type Hints:**
- Tutte le funzioni tipizzate

✅ **Docstring:**
- Una linea max per funzione

✅ **Integration:**
- Funzioni non dipendono da PyQt6 (pura matplotlib)
- Axes modificate in-place (no return)

---

## Workflow

1. **Scrivi test** (5 test sopra) → `tests/test_app_drawing.py`
2. **Estrai MATLAB source** (righe 1846-4101)
3. **Usa `traduttore-matlab` agent** → traduci in Python
4. **Usa `revisore-matematico` agent** → verifica matematica
5. **Esegui test** → `pytest tests/test_app_drawing.py -v`
6. **Merge → master** quando tutti i test passano

---

## Effort

- MATLAB source: ~300 linee (4 funzioni + helper)
- Python target: ~350-400 linee (matplotlib boilerplate)
- TDD test: ~150 linee
- **Effort totale:** ~2-3 giorni (traduzione + review + test)

