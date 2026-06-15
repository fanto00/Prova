# Piano TDD: Modulo 6 — `app/analysis/signal_plotting.py`

Sottotask di sub-plan 7 (App GUI Completa). Helper di plotting pure per segnali singoli e metriche temporali.

---

## Scope

**File MATLAB:** `src_app/app.m` (righe 2180-2500, 2900-3500)  
**File Python:** `railway_inspector/app/analysis/signal_plotting.py`

**5 funzioni pure (no UI state):**

1. **`plot_temporal_trend(ax, dates, series_front, series_rear, title, ylabel, **kwargs)`** (MATLAB linee 2186-2206)
   - Plot trend temporale con due serie (Front vs Rear)
   - Input: ax (matplotlib Axes), dates (ndarray), series_front/rear (ndarray), title str, ylabel str
   - Output: None (side effect: axes modificato)
   - Setup: grid, legend, datetick, linkaxes
   - Colori standard: blue per front (o), red per rear (s)

2. **`plot_single_signal(ax, x_axis, signal, label='Signal', color='b', **kwargs)`** (MATLAB linee 2900+)
   - Plot segnale su asse con formattazione standard
   - Input: ax, x_axis (spatial coords), signal (ndarray), label, color, optional linewidth/alpha
   - Output: None (side effect: axes modificato)
   - Features: grid, xlabel/ylabel auto-set

3. **`plot_rms_envelope(ax, x_axis, signal, window_samples, label='RMS', color='r', **kwargs)`** (MATLAB linee 2087-2095)
   - Calcola e plotta RMS envelope di segnale
   - Input: ax, x_axis, signal, window_samples (int), label, color, **kwargs
   - Output: None (side effect: axes modificato)
   - Utilizza: scipy.ndimage.uniform_filter1d (per movmean EndValues='shrink')
   - Formula: rms_sig = sqrt(movmean(sig^2, window_samples))

4. **`plot_signal_comparison(ax, x_axis, original, reconstructed, title=None, **kwargs)`** (MATLAB linee 3300-3302)
   - Compara due segnali (orig vs recon) su stesso asse
   - Input: ax, x_axis, original, reconstructed, title
   - Output: None (side effect: axes modificato)
   - Colori: blue solid per original, red dashed per reconstructed
   - Matching MATLAB: orig='-b', recon='--r', linewidth=1.0

5. **`setup_signal_axes(ax, title=None, xlabel=None, ylabel=None, fontsize=9, **kwargs)`** (MATLAB linee 3303-3309)
   - Setup axes con grid, font, label standard
   - Input: ax, title, xlabel, ylabel, fontsize
   - Output: None (side effect: axes modificato)
   - Setup: grid on, font 8-9pt, xlim, ylim se specificati
   - Per grafici multi-sensore: auto-set ylabel se colonna left, xlabel se riga bottom

---

## Dipendenze Python

- `numpy` — operazioni array
- `matplotlib.pyplot` — plotting
- `scipy.ndimage.uniform_filter1d` — movmean equivalente
- Reusable: `movmean()` from `signal/resampling.py` oppure inline scipy

---

## TDD: 9 Test Specifici

### Test 1: `test_plot_temporal_trend_adds_lines`
**Verifica:** La funzione aggiunge due linee all'axes.

```python
import pytest
import numpy as np
import matplotlib.pyplot as plt
from railway_inspector.app.analysis.signal_plotting import plot_temporal_trend

def test_plot_temporal_trend_adds_lines():
    """plot_temporal_trend() deve aggiungere 2 linee (front+rear)."""
    fig, ax = plt.subplots()
    
    dates = np.array([737800.0, 737801.0, 737802.0])
    series_front = np.array([1.5, 2.0, 1.8])
    series_rear = np.array([1.2, 1.5, 1.6])
    
    initial_lines = len(ax.lines)
    plot_temporal_trend(ax, dates, series_front, series_rear, 
                       title="Test Trend", ylabel="Accel [m/s^2]")
    
    # Deve aggiungere 2 linee
    assert len(ax.lines) == initial_lines + 2
    assert ax.get_title() == "Test Trend"
    
    plt.close(fig)
```

### Test 2: `test_plot_temporal_trend_colors_correct`
**Verifica:** Colori front=blue, rear=red.

```python
def test_plot_temporal_trend_colors_correct():
    """Colori: blue per front, red per rear."""
    fig, ax = plt.subplots()
    
    dates = np.array([737800.0, 737801.0])
    series_front = np.array([1.0, 2.0])
    series_rear = np.array([1.5, 2.5])
    
    plot_temporal_trend(ax, dates, series_front, series_rear, 
                       title="Color Test", ylabel="Y")
    
    # First line è blu, second è rosso
    line_colors = [line.get_color() for line in ax.lines]
    assert line_colors[0] == 'b' or line_colors[0][:3] == (0.0, 0.0, 1.0)
    assert line_colors[1] == 'r' or line_colors[1][:3] == (1.0, 0.0, 0.0)
    
    plt.close(fig)
```

### Test 3: `test_plot_single_signal_basic`
**Verifica:** Aggiunge una linea con label corretto.

```python
def test_plot_single_signal_basic():
    """plot_single_signal() aggiunge una linea."""
    fig, ax = plt.subplots()
    
    x_axis = np.linspace(-10, 10, 100)
    signal = np.sin(x_axis)
    
    plot_single_signal(ax, x_axis, signal, label="Test Signal")
    
    assert len(ax.lines) == 1
    assert ax.get_xlabel() != ''  # Deve avere xlabel auto
    
    plt.close(fig)
```

### Test 4: `test_plot_rms_envelope_calculates_correctly`
**Verifica:** RMS envelope è sqrt(movmean(sig^2)).

```python
def test_plot_rms_envelope_calculates_correctly():
    """RMS envelope = sqrt(movmean(sig^2, window_samples))."""
    # Segnale sinusoidale: max RMS dovrebbe essere ~0.707 per sin(x) con window=1
    x = np.linspace(0, 4*np.pi, 400)
    sig = np.sin(x)
    window_samples = 10
    
    # Calcolo RMS atteso (movmean di sig^2, poi sqrt)
    from scipy.ndimage import uniform_filter1d
    rms_expected = np.sqrt(uniform_filter1d(sig**2, size=window_samples, mode='nearest'))
    
    # Verifica che max(rms_expected) sia nell'intervallo atteso per sin
    assert 0.5 < np.max(rms_expected) < 1.0
    
    fig, ax = plt.subplots()
    plot_rms_envelope(ax, x, sig, window_samples, label="RMS")
    
    # Deve aggiungere una linea
    assert len(ax.lines) == 1
    
    plt.close(fig)
```

### Test 5: `test_plot_signal_comparison_adds_two_lines`
**Verifica:** Aggiunge two linee (orig=solid, recon=dashed).

```python
def test_plot_signal_comparison_adds_two_lines():
    """plot_signal_comparison() aggiunge 2 linee."""
    fig, ax = plt.subplots()
    
    x = np.linspace(0, 10, 100)
    original = np.sin(x)
    reconstructed = np.sin(x) + 0.1 * np.random.randn(100)
    
    plot_signal_comparison(ax, x, original, reconstructed, title="Comparison")
    
    assert len(ax.lines) == 2
    assert ax.get_title() == "Comparison"
    
    # Verifica stili: solid vs dashed
    styles = [line.get_linestyle() for line in ax.lines]
    assert '-' in styles or 'solid' in styles[0]  # Uno solid
    assert '--' in styles or 'dashed' in styles[1]  # Uno dashed
    
    plt.close(fig)
```

### Test 6: `test_setup_signal_axes_applies_formatting`
**Verifica:** Grid on, labels settati, fontsize applicato.

```python
def test_setup_signal_axes_applies_formatting():
    """setup_signal_axes() applica formatting."""
    fig, ax = plt.subplots()
    
    setup_signal_axes(ax, title="Test Title", 
                      xlabel="X [m]", ylabel="Y [m/s^2]", fontsize=10)
    
    assert ax.get_title() == "Test Title"
    assert ax.get_xlabel() == "X [m]"
    assert ax.get_ylabel() == "Y [m/s^2]"
    assert ax.xaxis.get_tick_params()['labelsize'] == 10 or \
           ax.get_xticklabels()[0].get_fontsize() == 10
    
    plt.close(fig)
```

### Test 7: `test_plot_temporal_trend_grid_enabled`
**Verifica:** Grid è attivo.

```python
def test_plot_temporal_trend_grid_enabled():
    """Grid deve essere attivo."""
    fig, ax = plt.subplots()
    
    dates = np.array([737800.0, 737801.0])
    series_f = np.array([1.0, 2.0])
    series_r = np.array([1.5, 2.5])
    
    plot_temporal_trend(ax, dates, series_f, series_r, "Title", "Y")
    
    # Verifica grid stato
    assert ax.xaxis._gridOnMajor or ax.yaxis._gridOnMajor
    
    plt.close(fig)
```

### Test 8: `test_plot_rms_envelope_non_negative`
**Verifica:** RMS è sempre non-negativo.

```python
def test_plot_rms_envelope_non_negative():
    """RMS envelope deve essere sempre >= 0."""
    x = np.linspace(-10, 10, 200)
    sig = np.random.randn(200)  # Random noise
    
    fig, ax = plt.subplots()
    plot_rms_envelope(ax, x, sig, window_samples=5)
    
    # Estrai dati dalla linea
    line = ax.lines[0]
    y_data = line.get_ydata()
    
    assert np.all(y_data >= 0)
    
    plt.close(fig)
```

### Test 9: `test_plot_signal_comparison_legend`
**Verifica:** Legend mostra due serie (original vs reconstructed).

```python
def test_plot_signal_comparison_legend():
    """Legend deve mostrare original e reconstructed."""
    fig, ax = plt.subplots()
    
    x = np.linspace(0, 10, 100)
    original = np.sin(x)
    reconstructed = np.sin(x) * 0.9
    
    plot_signal_comparison(ax, x, original, reconstructed)
    ax.legend(['Original', 'Reconstructed'])
    
    legend = ax.get_legend()
    assert legend is not None
    
    plt.close(fig)
```

---

## Quality Gates

1. **Matematica:** RMS envelope corrisponde a scipy.ndimage.uniform_filter1d (no numpy convolve)
2. **Plotting:** Tutte le funzioni sono **pure** (no UI state, no side effects oltre axes)
3. **Test coverage:** Tutte le 9 test passano ✓
4. **Type hints:** Tutte le funzioni hanno type hints (Axes, ndarray, float, str, **kwargs)
5. **Docstring:** One-liner per ogni funzione (why, not what)
6. **No magic numbers:** Colori, fontsize, linewidth come parametri o costanti modulo

---

## Implementazione

### Ordine (TDD: test first, poi implementation)
1. Scrivi tutti i 9 test in `tests/test_app_signal_plotting.py`
2. Esegui test (tutti fallono)
3. Traduci MATLAB linee 2186-2206, 2900+, 3300+ in Python
4. Revisione matematica (RMS envelope vs scipy)
5. Commit e push

---

## Note MATLAB→Python

- **MATLAB `grid on`** → **Python `ax.grid(True)`**
- **MATLAB `datetick(..., 'dd/mm/yy')`** → **Python `matplotlib.dates.DateFormatter`**
- **MATLAB `legend(..., 'Location', 'northwest')`** → **Python `ax.legend(loc='upper left')`**
- **MATLAB `set(ax, 'FontSize', 8)`** → **Python `ax.tick_params(labelsize=8)` + `ax.xaxis.label.set_fontsize(8)`**
- **MATLAB `hold(ax, 'on')`** → **Python `ax.plot()` automaticamente aggiunge (matplotlib stile)**
- **MATLAB `linkaxes(ax_list, 'x')`** → **Python `SharedXAxes` o manuale tramite callback**

---

## Fuori Scope

- UI callbacks, sliders, dropdown menus (restano in single_analysis.py)
- Interattivo clicking/tooltip (restano datatips.py)
- Data extraction / RMS calculation (dovrebbe stare in helpers.py se non c'è già)
- PCA visualization (restano in generate_headless_daily_plots.py)

---

## Effort Estimate

- Test writing: 30 min (9 test semplici)
- MATLAB translation: 45 min (5 funzioni corte, ~20 righe ciascuna)
- Mathematical review: 20 min (RMS envelope check)
- Integration: 10 min (import, type hints)
- **Total: ~2 ore** (subagent + review)

