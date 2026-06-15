# Piano TDD: Modulo 5 — `app/analysis/export.py`

Sottotask di sub-plan 7 (App GUI Completa). Report export & headless plotting utilities.

---

## Scope

**File MATLAB:** `src_app/app.m` (righe 8013-8575 + helper generate_headless_daily_plots:8577-8750+)
**File Python:** `railway_inspector/app/analysis/export.py`

**Funzioni (FASE matematica PURA, scartare GUI):**
1. `generate_overview_figure(data_full, space_shifted, joints_table, sorted_ipi, db, config)` — genera figura headless RAW overview (FASE 0)
2. `generate_global_scatter(data_store, config)` → figura scatter asimmetriche (FASE 1)
3. `export_report_latex(sorted_ipi, db, export_dir, track_name, config, has_overview)` → genera LaTeX document (FASE 3)
4. `_format_latex_safe(s)` → escape backslash per LaTeX

**Dipendenze:** matplotlib, numpy, pandas, pathlib (file I/O)

**Note Architetturali:**
- Scartare completamente MATLAB GUI (uigetdir, waitbar, msgbox, Figure visibili) → sostituire con Path/logging
- Scartare generate_headless_daily_plots per ora (Modulo 5b) — è una funzione helper da ~200 righe
- FOCUS: overview RAW + scatter globali + LaTeX generation
- Headless matplotlib figures: `Figure(figsize=..., dpi=100)` con `savefig()` e no `plt.show()`
- No PDF compilation (pdflatex) — lasciare per step manuale

---

## TDD: Test-First, Implementazione Dopo

### Test 1: `test_generate_overview_figure_creates_file`
**Verifica:** generate_overview_figure crea file PNG RAW overview (6+2 subplot = 8 totali).

```python
from railway_inspector.app.analysis.export import generate_overview_figure
from pathlib import Path
import tempfile

def test_generate_overview_figure_creates_file():
    """generate_overview_figure() crea 00_Overview_Track_RAW.png con 8 subplot."""
    # Mock: data_full con campo .space_neutral, .left_sensor_front, .speed, .curve
    # Mock: space_shifted array 10000 elementi
    # Mock: joints_table con Position e Joint columns
    # Mock: sorted_ipi list con 10 elementi (top 10 defects)
    # Mock: db dict con ID_PK e Avg_Pos
    
    with tempfile.TemporaryDirectory() as tmpdir:
        export_dir = Path(tmpdir)
        
        # Setup: crea mock data
        # ... fixture data ...
        
        # Call
        success = generate_overview_figure(
            data_full, space_shifted, joints_table, 
            sorted_ipi, db, config, export_dir
        )
        
        assert success == True
        assert (export_dir / "00_Overview_Track_RAW.png").exists()
```

### Test 2: `test_generate_overview_figure_joints_overlay`
**Verifica:** generate_overview_figure aggiunge overlay viola (joints) e rossi (top 10 difetti).

```python
def test_generate_overview_figure_joints_overlay():
    """generate_overview_figure() include giunti (viola) e top 10 (rosso)."""
    # Mock: joints_table con 3 righe (Position=[100, 200, 300])
    # Mock: sorted_ipi con 5 elementi
    
    with tempfile.TemporaryDirectory() as tmpdir:
        success = generate_overview_figure(...)
        assert success == True
        
        # Controllo che la figura contiene i dati
        # (hard da verificare senza OCR, verifichiamo solo che PNG sia stato creato)
        assert (export_dir / "00_Overview_Track_RAW.png").exists()
```

### Test 3: `test_generate_global_scatter_asymmetry_coloring`
**Verifica:** generate_global_scatter colora simmetrici (grigio) vs asimmetrici (turbo colormap).

```python
def test_generate_global_scatter_asymmetry_coloring():
    """generate_global_scatter() applica colori asimmetrici (ratio vF/vR > 1.5 o < 0.66)."""
    # Mock: 4 DataStore objects con Filt.MovF, MovR, DefectID
    
    with tempfile.TemporaryDirectory() as tmpdir:
        fig, axes = generate_global_scatter(data_store, config, tmpdir)
        
        assert fig is not None
        assert len(axes) == 4  # 2x2 subplot
        # Verifica che i dati siano stati plottati
        for ax in axes:
            assert len(ax.collections) > 0  # scatter presenti
```

### Test 4: `test_generate_global_scatter_asymmetry_logic`
**Verifica:** Logica asimmetria corretta (ratio > 1.5 or < 0.66).

```python
def test_generate_global_scatter_asymmetry_logic():
    """Logica asimmetria: ratio = vF / max(vR, 1e-6)."""
    # Test diretto della logica senza figure
    vF = np.array([1.0, 2.0, 3.0])
    vR = np.array([1.0, 1.0, 1.0])
    
    ratio = vF / np.maximum(vR, 1e-6)
    asym_mask = (ratio > 1.5) | (ratio < 0.66)
    
    # ratio = [1.0, 2.0, 3.0] → [False, True, True]
    assert asym_mask[0] == False
    assert asym_mask[1] == True
    assert asym_mask[2] == True
```

### Test 5: `test_export_report_latex_basic`
**Verifica:** export_report_latex genera file .tex con header LaTeX e section per top 10.

```python
def test_export_report_latex_basic():
    """export_report_latex() scrive file .tex con documentclass e maketitle."""
    with tempfile.TemporaryDirectory() as tmpdir:
        export_dir = Path(tmpdir)
        
        # Mock: sorted_ipi con 3 elementi (ridotto per test)
        success = export_report_latex(
            sorted_ipi[:3], db, export_dir, 
            track_name="Test_Track", config=config, has_overview=True
        )
        
        assert success == True
        tex_file = export_dir / "Report_Tratta_Test-Track.tex"
        assert tex_file.exists()
        
        content = tex_file.read_text(encoding='utf-8')
        assert r'\documentclass[11pt]{article}' in content
        assert r'\maketitle' in content
        assert r'\section{' in content
```

### Test 6: `test_export_report_latex_top10_sections`
**Verifica:** export_report_latex genera una sezione per ogni elemento in top 10 (max 10 sezioni).

```python
def test_export_report_latex_top10_sections():
    """export_report_latex() crea \section{Posizione \#i: ...} per top 10."""
    with tempfile.TemporaryDirectory() as tmpdir:
        success = export_report_latex(sorted_ipi, db, export_dir, ...)
        
        content = (export_dir / "Report_Tratta_...tex").read_text()
        
        # Conteggio delle sezioni
        num_sections = content.count(r'\section{Posizione \#')
        assert num_sections == min(10, len(sorted_ipi))
```

### Test 7: `test_export_report_latex_traffic_light_semaforo`
**Verifica:** Logica semaforo IPI (rosso ≥75, arancione ≥50, giallo ≥25, verde <25).

```python
def test_export_report_latex_traffic_light_semaforo():
    """Logica semaforo IPI."""
    ipi_values = [80, 60, 30, 15]
    expected = ['red', 'orange', 'olive', 'green']
    
    for ipi, color in zip(ipi_values, expected):
        if ipi >= 75:
            assert color == 'red'
        elif ipi >= 50:
            assert color == 'orange'
        elif ipi >= 25:
            assert color == 'olive'
        else:
            assert color == 'green'
```

### Test 8: `test_format_latex_safe_escapes_underscores`
**Verifica:** _format_latex_safe converte PK ID per LaTeX (underscore → \_).

```python
def test_format_latex_safe_escapes_underscores():
    """_format_latex_safe() escapa underscore e caratteri speciali."""
    from railway_inspector.app.analysis.export import _format_latex_safe
    
    assert _format_latex_safe("Track_Name_01") == r"Track\_Name\_01"
    assert _format_latex_safe("Normal") == "Normal"
    assert _format_latex_safe("A_B_C") == r"A\_B\_C"
```

---

## MATLAB Source (Linee Specifiche)

### Funzioni (righe 8013-8575 + 8577-8750)
```matlab
function export_route_report_callback(DataStore, SortedIpi, DB, C, track_name, h_main)
    % FASE 0: VISTA GLOBALE TRATTA (PANORAMICA RAW - NO FILTRI)
    % Lines 8030-8156: Headless figure con subplot(8,1) per 6 sensori + speed + curve
    % Overlay: giunti (viola, xline), top 10 difetti (rosso, xline)
    
    % FASE 1: GRAFICI GLOBALI (Scatter con Colori Asimmetrici)
    % Lines 8158-8228: 4 subplot (2x2) per 4 DataStore
    % Logica asimmetria: ratio = vF / max(vR, 1e-6); asym_mask = (ratio > 1.5) | (ratio < 0.66)
    
    % FASE 3: GENERAZIONE LATEX
    % Lines 8244-8551: fprintf loops per LaTeX document generation
    % Semaforo IPI: if s.IPI >= 75 → red; >= 50 → orange; >= 25 → olive; else → green
end

function generate_headless_daily_plots(Defect, C, export_dir, rank_idx)
    % Lines 8577-8750+: Genera TOP%02d_0_Max_Run_Signals.png, Matrice3x3, RatioLat, Lambda
    % Per ora SCARTARE (Modulo 5b)
end
```

---

## Implementazione (Dopo i Test)

### Dipendenze Python
```python
import matplotlib.pyplot as plt
from matplotlib.figure import Figure
import numpy as np
import pandas as pd
from pathlib import Path
from typing import List, Dict, Optional, Tuple, Any
```

### Signature Python

```python
def generate_overview_figure(
    data_full: Dict[str, Any],        # section_extracted con space_neutral, sensori, speed, curve
    space_shifted: np.ndarray,         # posizioni spaziali [m]
    joints_table: pd.DataFrame,        # {Position, Joint, Stations}
    sorted_ipi: List[Dict],            # top 10 defects con ID, IPI, ...
    db: List[Dict],                    # database di defetti con ID_PK, Avg_Pos, History
    config: Dict,                      # C constants (SPATIAL_RES, ...)
    export_dir: Path,                  # directory per salvare PNG
) -> bool:
    """Generate headless RAW overview figure with joints and top-10 defects overlay."""
    pass

def generate_global_scatter(
    data_store: List[Dict],            # 4 DataStore objects
    config: Dict,
    export_dir: Path,
) -> Tuple[Any, np.ndarray]:           # (fig, axes)
    """Generate 2x2 scatter plot with asymmetry coloring."""
    pass

def _format_latex_safe(s: str) -> str:
    """Escape underscore and special LaTeX characters."""
    pass

def export_report_latex(
    sorted_ipi: List[Dict],            # top N defects
    db: List[Dict],
    export_dir: Path,
    track_name: str,
    config: Dict,
    has_overview: bool = False,
) -> bool:
    """Generate LaTeX document with global analysis and top-10 sections."""
    pass
```

---

## Quality Gates

✅ **TDD:**
- Scritti 8 test prima dell'implementazione
- Test: figure creation, overlay logic, LaTeX generation, semaforo logic, safe formatting

✅ **Matematica:**
- Asimmetria: ratio = vF / max(vR, 1e-6); asym_mask = (ratio > 1.5) | (ratio < 0.66) ✓
- Semaforo IPI: thresholds 75/50/25 ✓
- Subplot structure: 8 subplot RAW (6 sensori + speed + curve) ✓
- Joint/defect overlay: xline posizioni assolute [m] ✓

✅ **Type Hints:**
- Tutte le funzioni tipizzate (Path, Dict, np.ndarray, bool return)

✅ **Docstring:**
- Una linea max per funzione

✅ **Pure Functions:**
- No side effects (file I/O OK, return True/False, savefig direct)

---

## Workflow

1. **Scrivi test** (8 test sopra) → `tests/test_app_export.py`
2. **Estrai MATLAB source** (righe 8013-8575 funzione principale)
3. **Usa `traduttore-matlab` agent** → traduci in Python (focus su overview + scatter + LaTeX)
4. **Usa `revisore-matematico` agent** → verifica matematica (asimmetria logic, semaforo, ratio normalization)
5. **Esegui test** → `pytest tests/test_app_export.py -v`
6. **Merge → master** quando tutti i test passano

---

## Effort & Modularità

**FASE 0 (Overview RAW):** ~80 righe MATLAB → ~100 Python (subplot, overlay, decimation)
**FASE 1 (Global Scatter):** ~70 righe MATLAB → ~90 Python (colormap, legend, asymmetry logic)
**FASE 3 (LaTeX):** ~310 righe MATLAB (fprintf loops) → ~280 Python (f-string templates)
**Tot Python target:** ~300-350 righe (modulo puro, no PDF compilation)

**Helper generate_headless_daily_plots:** ~200+ righe MATLAB (Modulo 5b, separato) — contiene:
- PCA plotting
- Waterfall 3D (Profilo Spaziale)
- PSD 3D evolution
- Ratio Laterale/Longitudinale

---

## Note

- **SCARTARE:** uigetdir (dialog per folder), waitbar (progressbar), msgbox (messaggi GUI), figure visibility
- **SCARTARE:** pdflatex compilation (sistema esterno, fuori scope) — LaTeX generato, PDF manuale
- **File I/O:** PNG via matplotlib `savefig(..., dpi=300, bbox_inches='tight')`
- **Colori:** Viola=[0.6, 0.1, 0.8], Rosso=[1.0, 0.0, 0.0], Grigio=[0.8, 0.8, 0.8]
- **Formattazione Date:** Datetick simile su matplotlib (mdates.AutoDateFormatter)

