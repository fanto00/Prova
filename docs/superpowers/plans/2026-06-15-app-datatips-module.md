# Piano TDD: Modulo 3 — `app/analysis/datatips.py`

Sottotask di sub-plan 7 (App GUI Completa). Tooltip callback functions per interattività grafica.

---

## Scope

**File MATLAB:** `src_app/app.m` (righe 1377-1396, 4517-4600, 7969-8005)
**File Python:** `railway_inspector/app/analysis/datatips.py`

**Funzioni:**
1. `custom_datatip_robust(event_obj)` (righe 1377-1396) — scatter defect tooltips con PK metadati
2. `master_datatip_fcn(event_obj)` (righe 4517-4600) — Master callback 2D/3D (PSD, trend, 3x3 matrix)
3. `classification_datatip(event_obj, SummaryData, tipi)` (righe 7969-8005) — scatter classificazione tooltips

**Dipendenze:** numpy, pandas, datetime, matplotlib (event_obj handling)
**Test database:** Fixture con event_obj mock, dict defect, list SummaryData

---

## TDD: Test-First, Implementazione Dopo

### Test 1: `test_custom_datatip_robust_with_tag`
**Verifica:** custom_datatip_robust restituisce testo con PK per scatter DefectScatter.

```python
from datetime import datetime
from railway_inspector.app.analysis.datatips import custom_datatip_robust

def test_custom_datatip_robust_with_tag():
    """custom_datatip_robust() restituisce PK + Ant/Pos per DefectScatter."""
    # Mock event_obj con Tag 'DefectScatter' e metadati PK
    class MockTarget:
        def __init__(self):
            self.Tag = "DefectScatter"
            self.UserData = ["PK 12.5", "PK 15.3", "PK 18.7"]
    
    class MockEventObj:
        def __init__(self):
            self.Target = MockTarget()
            self.Position = [0.25, 0.8]
            self.DataIndex = 1  # Seleziona "PK 15.3"
    
    event = MockEventObj()
    txt = custom_datatip_robust(None, event)
    
    assert isinstance(txt, list)
    assert len(txt) == 3
    assert "PK 15.3" in txt[0]
    assert "0.25" in txt[1]  # Ant
    assert "0.80" in txt[2]  # Pos
```

### Test 2: `test_custom_datatip_robust_without_tag`
**Verifica:** Fallback a XY coordinate se non è DefectScatter.

```python
def test_custom_datatip_robust_without_tag():
    """custom_datatip_robust() fallback a XY se non DefectScatter."""
    class MockTarget:
        def __init__(self):
            self.Tag = "OtherPlot"
    
    class MockEventObj:
        def __init__(self):
            self.Target = MockTarget()
            self.Position = [1.5, 2.3]
            self.DataIndex = 0
    
    event = MockEventObj()
    txt = custom_datatip_robust(None, event)
    
    assert len(txt) == 2
    assert "1.50" in txt[0]  # X
    assert "2.30" in txt[1]  # Y
```

### Test 3: `test_custom_datatip_robust_out_of_range`
**Verifica:** Fallback "N/A" se DataIndex > len(meta_list).

```python
def test_custom_datatip_robust_out_of_range():
    """custom_datatip_robust() con DataIndex out of range → N/A."""
    class MockTarget:
        def __init__(self):
            self.Tag = "DefectScatter"
            self.UserData = ["PK 12.5", "PK 15.3"]
    
    class MockEventObj:
        def __init__(self):
            self.Target = MockTarget()
            self.Position = [0.25, 0.8]
            self.DataIndex = 10  # Out of range
    
    event = MockEventObj()
    txt = custom_datatip_robust(None, event)
    
    assert "N/A" in txt[0]
```

### Test 4: `test_master_datatip_fcn_psd_2d`
**Verifica:** master_datatip_fcn gestisce PSD 2D (Freq→Lambda conversion).

```python
from railway_inspector.app.analysis.datatips import master_datatip_fcn

def test_master_datatip_fcn_psd_2d():
    """master_datatip_fcn() PSD 2D: Freq→Lambda conversion."""
    class MockTarget:
        def __init__(self):
            self.UserData = {
                'Type': 'Forward',
                'Date': datetime(2024, 6, 15, 14, 30)
            }
    
    class MockEventObj:
        def __init__(self):
            self.Position = [0.1, 5.2]  # freq, amplitude
            self.Target = MockTarget()
    
    class MockAxes:
        def get_xlim(self): return (0, 10)
        def get_ylim(self): return (0, 10)
        class XLabel:
            def get_String(self): return "Frequenza [cicli/m]"
    
    event = MockEventObj()
    txt = master_datatip_fcn(None, event)
    
    assert isinstance(txt, list)
    # Lambda = 1/freq = 1/0.1 = 10.0
    assert "10.00" in str(txt)  # Lambda value
    assert "Forward" in str(txt)  # Run type
    assert "5.20" in str(txt)  # Amplitude
```

### Test 5: `test_master_datatip_fcn_3d_psd`
**Verifica:** master_datatip_fcn gestisce PSD 3D (Freq 2D, Data, Power).

```python
def test_master_datatip_fcn_3d_psd():
    """master_datatip_fcn() PSD 3D: Freq, Date, Power."""
    class MockTarget:
        def __init__(self):
            self.UserData = {'Type': 'Backward', 'Date': datetime(2024, 6, 15)}
    
    class MockAxes:
        class XLabel:
            def get_String(self): return "Frequenza"
        def get_xlim(self): return (0, 10)
        def get_ylim(self): return (0, 10)
    
    class MockEventObj:
        def __init__(self):
            self.Position = [0.2, 730000, 3.5]  # freq, date(datenum), power
            self.Target = MockTarget()
    
    event = MockEventObj()
    txt = master_datatip_fcn(None, event)
    
    assert isinstance(txt, list)
    assert "Frequenza" in str(txt) or "0.20" in str(txt)
```

### Test 6: `test_master_datatip_fcn_trend_2d`
**Verifica:** master_datatip_fcn gestisce Trend 2D (Data datenum, Valore).

```python
def test_master_datatip_fcn_trend_2d():
    """master_datatip_fcn() Trend 2D: datenum X-axis."""
    class MockTarget:
        def __init__(self):
            self.UserData = None
    
    class MockEventObj:
        def __init__(self):
            self.Position = [745000, 2.5]  # datenum (large), valore
            self.Target = MockTarget()
    
    event = MockEventObj()
    txt = master_datatip_fcn(None, event)
    
    assert isinstance(txt, list)
    # Dovrebbe eseguire datestr(745000)
    assert len(txt) == 2
```

### Test 7: `test_classification_datatip_basic`
**Verifica:** classification_datatip formatta testo con tipo, lambda, ratio.

```python
from railway_inspector.app.analysis.datatips import classification_datatip

def test_classification_datatip_basic():
    """classification_datatip() formatta info defect classificazione."""
    summary = {
        'ID': '12.5',
        'TipoStrutturale': 'Giunto',
        'Amp': 8.5,
        'Lambda_SX': 0.25,
        'Lambda_DX': 0.28,
        'NaturaSpettrale_SX': 'Picco',
        'NaturaSpettrale_DX': 'Picco',
        'Ratio_SX_DX': 1.15,
        'Ratio_Lat_Vert': 0.45,
    }
    
    class MockTarget:
        def __init__(self):
            self.DisplayName = "Giunto"
    
    class MockEventObj:
        def __init__(self):
            self.Position = [0.25, 0.28]
            self.DataIndex = 0
            self.Target = MockTarget()
    
    event = MockEventObj()
    txt = classification_datatip(event, [summary], ["Giunto"])
    
    assert isinstance(txt, list)
    assert any("12.5" in str(line) for line in txt)  # PK
    assert any("Giunto" in str(line) for line in txt)  # Tipo
    assert any("8.5" in str(line) for line in txt)  # Amplitude
    assert any("0.25" in str(line) for line in txt)  # Lambda SX
```

### Test 8: `test_classification_datatip_fallback_nearest`
**Verifica:** Fallback a nearest neighbor se DataIndex sbagliato.

```python
def test_classification_datatip_fallback_nearest():
    """classification_datatip() fallback nearest neighbor."""
    summary_list = [
        {'ID': '10.0', 'TipoStrutturale': 'Giunto', 'Amp': 5.0,
         'Lambda_SX': 0.2, 'Lambda_DX': 0.22, 'NaturaSpettrale_SX': 'Picco',
         'NaturaSpettrale_DX': 'Picco', 'Ratio_SX_DX': 1.0, 'Ratio_Lat_Vert': 0.5},
        {'ID': '15.0', 'TipoStrutturale': 'Difetto', 'Amp': 6.0,
         'Lambda_SX': 0.25, 'Lambda_DX': 0.25, 'NaturaSpettrale_SX': 'Allarga',
         'NaturaSpettrale_DX': 'Allarga', 'Ratio_SX_DX': 1.1, 'Ratio_Lat_Vert': 0.6},
    ]
    
    class MockTarget:
        def __init__(self):
            self.DisplayName = "Unknown"
    
    class MockEventObj:
        def __init__(self):
            self.Position = [0.25, 0.25]  # Vicino a summary_list[1]
            self.DataIndex = 999  # Invalid
            self.Target = MockTarget()
    
    event = MockEventObj()
    txt = classification_datatip(event, summary_list, ["Unknown"])
    
    assert isinstance(txt, list)
    # Dovrebbe trovare l'elemento più vicino (index 1 = ID 15.0)
    assert any("15.0" in str(line) for line in txt) or any("6.0" in str(line) for line in txt)
```

---

## MATLAB Source (Linee Specifiche)

### Funzioni (righe 1377-1396, 4517-4600, 7969-8005)
```matlab
function txt = custom_datatip_robust(~, event_obj)
    % Scatter defect tooltips con PK metadati
end

function txt = master_datatip_fcn(~, event_obj)
    % Master callback 2D/3D: PSD, trend, 3x3 matrix
end

function txt = classification_datatip(event_obj, SummaryData, tipi)
    % Scatter classificazione: tipo, lambda, ratio
end
```

---

## Implementazione (Dopo i Test)

### Dipendenze Python
```python
from datetime import datetime
import numpy as np
```

### Signature Python

```python
def custom_datatip_robust(
    obj: object,
    event_obj: object,
) -> list[str]:
    """Format tooltip text for defect scatter with PK metadata."""
    pass

def master_datatip_fcn(
    obj: object,
    event_obj: object,
) -> list[str]:
    """Format tooltip for 2D/3D plots (PSD, trend, matrix)."""
    pass

def classification_datatip(
    event_obj: object,
    summary_data: list[dict],
    tipi: list[str],
) -> list[str]:
    """Format tooltip for classification scatter."""
    pass
```

---

## Quality Gates

✅ **TDD:**
- Scritti 8 test prima dell'implementazione
- Test: coordinate formatting, metadata lookup, fallback logic, nearest neighbor

✅ **Matematica:**
- Lambda conversion: 1/freq ✓
- Coordinate formatting: 2 decimals ✓
- Fallback distance normalization (dx.^2 + dy.^2) ✓

✅ **Type Hints:**
- Tutte le funzioni tipizzate (object, list[dict], list[str] return)

✅ **Docstring:**
- Una linea max per funzione

✅ **Pure Functions:**
- No side effects (no matplotlib state changes)
- Input: event_obj → Output: txt list

---

## Workflow

1. **Scrivi test** (8 test sopra) → `tests/test_app_datatips.py`
2. **Estrai MATLAB source** (righe 1377-1396, 4517-4600, 7969-8005)
3. **Usa `traduttore-matlab` agent** → traduci in Python
4. **Usa `revisore-matematico` agent** → verifica matematica (Lambda conversion, distance normalization)
5. **Esegui test** → `pytest tests/test_app_datatips.py -v`
6. **Merge → master** quando tutti i test passano

---

## Effort

- MATLAB source: ~230 righe (3 funzioni callback)
- Python target: ~180-220 righe (formattazione stringhe, mock event_obj handling)
- TDD test: ~250 righe (8 test + mock helpers)
- **Effort totale:** ~1-2 giorni (traduzione + test + review)

**Note:** Funzioni pure (no matplotlib binding necessario). Callback patterns stabili per futuri dialog.
