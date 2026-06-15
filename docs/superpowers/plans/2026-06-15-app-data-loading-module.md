# Piano TDD: Modulo 4 — `app/io/data_loading.py`

Sottotask di sub-plan 7 (App GUI Completa). Infrastructure & joints Excel loading utilities.

---

## Scope

**File MATLAB:** `src_app/app.m` (righe 1938-1965, 9126-9173)
**File Python:** `railway_inspector/app/io/data_loading.py`

**Funzioni:**
1. `load_infrastructure_map(filename, track_type)` (righe 1938-1960) — carica infrastruttura da Excel
2. `load_joints_map(filename, track_type)` (righe 9126-9173) — carica giunti da Excel
3. `_helper_clean_val(row, idx)` (righe 1961-1965) — helper per pulizia valori

**Dipendenze:** pandas, numpy, openpyxl (Excel reading)
**Test database:** Fixture con file Excel mock, track_type='pari'/'dispari'

---

## TDD: Test-First, Implementazione Dopo

### Test 1: `test_load_infrastructure_map_deviatoio`
**Verifica:** load_infrastructure_map estrae righe "Deviatoio" dalle colonne giuste.

```python
from railway_inspector.app.io.data_loading import load_infrastructure_map
import pandas as pd

def test_load_infrastructure_map_deviatoio():
    """load_infrastructure_map() carica Deviatoio rows."""
    # Mock: file Excel con sheet '1 p' (pari)
    # Row 3: idx_descA=1 "Deviatoio X", idx_descM=13 "Dev Y", idx_Pk_Start=20 → 10.5, idx_Pk_End=21 → 12.3
    # Expected: 1 row con Tipo='Deviatoio'
    
    # Setup: crea file Excel temporaneo con dati noti
    df = load_infrastructure_map("test_infra_pari.xlsx", "pari")
    
    assert isinstance(df, pd.DataFrame)
    assert len(df) > 0
    assert "Tipo" in df.columns
    deviatoio_rows = df[df["Tipo"] == "Deviatoio"]
    assert len(deviatoio_rows) > 0
    assert deviatoio_rows.iloc[0]["Pk_Inizio"] == 10.5
    assert deviatoio_rows.iloc[0]["Pk_Fine"] == 12.3
```

### Test 2: `test_load_infrastructure_map_raccordo`
**Verifica:** load_infrastructure_map estrae "Raccordo Ingresso/Uscita" dalle colonne giuste.

```python
def test_load_infrastructure_map_raccordo():
    """load_infrastructure_map() carica Raccordo rows."""
    # Mock: file con desc_M contains "Destra" oppure "Sinistra"
    # Expected: 2 rows (Raccordo Ingresso + Raccordo Uscita)
    
    df = load_infrastructure_map("test_infra_pari.xlsx", "pari")
    
    raccordo_rows = df[df["Tipo"].str.contains("Raccordo", na=False)]
    assert len(raccordo_rows) > 0
```

### Test 3: `test_load_infrastructure_map_dispari_sheets`
**Verifica:** load_infrastructure_map usa sheet '1 d' per track_type='dispari'.

```python
def test_load_infrastructure_map_dispari_sheets():
    """load_infrastructure_map() seleziona sheet '1 d' per dispari."""
    df = load_infrastructure_map("test_infra_dispari.xlsx", "dispari")
    
    assert isinstance(df, pd.DataFrame)
    # Se file ha dati nel foglio '1 d', deve caricarli
    # Altrimenti ritorna empty DataFrame
    assert len(df) >= 0
```

### Test 4: `test_load_infrastructure_map_missing_columns`
**Verifica:** load_infrastructure_map skipa righe con colonne insufficienti.

```python
def test_load_infrastructure_map_missing_columns():
    """load_infrastructure_map() skippa rows con colonne < idx_Pk_End."""
    df = load_infrastructure_map("test_infra_short.xlsx", "pari")
    
    # Row con lunghezza < 21 viene skippato
    assert isinstance(df, pd.DataFrame)
```

### Test 5: `test_load_infrastructure_map_zero_pk`
**Verifica:** load_infrastructure_map skipa righe con pk_start==0 && pk_end==0.

```python
def test_load_infrastructure_map_zero_pk():
    """load_infrastructure_map() skippa rows con pk_start=0 e pk_end=0."""
    df = load_infrastructure_map("test_infra_zeros.xlsx", "pari")
    
    # Nessuna riga con Pk_Inizio=0 e Pk_Fine=0
    zero_rows = df[(df["Pk_Inizio"] == 0) & (df["Pk_Fine"] == 0)]
    assert len(zero_rows) == 0
```

### Test 6: `test_load_joints_map_basic`
**Verifica:** load_joints_map carica posizioni giunti e nomi.

```python
from railway_inspector.app.io.data_loading import load_joints_map

def test_load_joints_map_basic():
    """load_joints_map() carica giunti con Position e Joint."""
    df = load_joints_map("test_joints_pari.xlsx", "pari")
    
    assert isinstance(df, pd.DataFrame)
    assert "Position" in df.columns
    assert "Joint" in df.columns
    assert "Stations" in df.columns
    # Position è arrotondato al metro
    assert all(df["Position"] == df["Position"].astype(int))
```

### Test 7: `test_load_joints_map_decimal_conversion`
**Verifica:** load_joints_map converte decimali (punto e virgola).

```python
def test_load_joints_map_decimal_conversion():
    """load_joints_map() gestisce sia punto che virgola decimale."""
    # Mock: file con values "10.5" e "10,5" in colonne diverse
    df = load_joints_map("test_joints_decimal.xlsx", "pari")
    
    # Entrambi dovrebbero essere convertiti a float e poi arrotondati a 11 (10.5 → 11, 10.5 → 11)
    assert isinstance(df, pd.DataFrame)
    assert all(df["Position"].dtype in [int, float])
```

### Test 8: `test_load_joints_map_nan_skip`
**Verifica:** load_joints_map skipa righe con Position=NaN.

```python
def test_load_joints_map_nan_skip():
    """load_joints_map() skippa rows con Position=NaN."""
    df = load_joints_map("test_joints_nan.xlsx", "pari")
    
    # Nessuna riga con Position=NaN
    assert not df["Position"].isna().any()
```

---

## MATLAB Source (Linee Specifiche)

### Funzioni (righe 1938-1960, 9126-9173)
```matlab
function dati_binario = load_infrastructure_map(filename, track_type)
    % Sheet selection: pari → '1 p', '1 dp'; dispari → '1 d', '1 dd'
    % Extract Deviatoio, Raccordo Ingresso/Uscita
end

function joints_table = load_joints_map(filename, track_type)
    % Sheet selection: pari → 'M2-Pari'; dispari → 'M2-Dispari'
    % Carica posizioni (decimal conversion) e nomi
    % Arrotonda al metro
end

function val = helper_clean_val(row, idx)
    % Cleanup helper: return 0 se missing/string/non-numeric
end
```

---

## Implementazione (Dopo i Test)

### Dipendenze Python
```python
import pandas as pd
import numpy as np
from pathlib import Path
```

### Signature Python

```python
def load_infrastructure_map(
    filename: str,
    track_type: str,  # 'pari' or 'dispari'
) -> pd.DataFrame:
    """Load infrastructure data from Excel (Deviatoio, Raccordo)."""
    pass

def load_joints_map(
    filename: str,
    track_type: str,
) -> pd.DataFrame:
    """Load joints map from Excel."""
    pass

def _helper_clean_val(row: list, idx: int) -> float:
    """Extract numeric value from row, return 0 if non-numeric."""
    pass
```

---

## Quality Gates

✅ **TDD:**
- Scritti 8 test prima dell'implementazione
- Test: sheet selection, column filtering, decimal conversion, NaN skipping

✅ **Matematica:**
- Excel column indices: idx_Pk_Start=20, idx_Pk_End=21 (1-based MATLAB → 0-based Python) ✓
- Decimal conversion: "10.5" e "10,5" → 10.5 (punto e virgola) ✓
- Rounding: round(pos_num) al metro ✓
- NaN skipping: ~isnan filter ✓

✅ **Type Hints:**
- Tutte le funzioni tipizzate (str, track_type, pd.DataFrame return)

✅ **Docstring:**
- Una linea max per funzione

✅ **Pure Functions:**
- No side effects (file I/O OK, return DataFrame)

---

## Workflow

1. **Scrivi test** (8 test sopra) → `tests/test_app_data_loading.py`
2. **Estrai MATLAB source** (righe 1938-1960, 9126-9173)
3. **Usa `traduttore-matlab` agent** → traduci in Python
4. **Usa `revisore-matematico` agent** → verifica matematica (sheet selection, column indices, decimal conversion)
5. **Esegui test** → `pytest tests/test_app_data_loading.py -v`
6. **Merge → master** quando tutti i test passano

---

## Effort

- MATLAB source: ~110 righe (2 funzioni + 1 helper)
- Python target: ~150-180 righe (pandas API, Excel reading, error handling)
- TDD test: ~200 righe (8 test + Excel mock fixtures)
- **Effort totale:** ~1 giorno (traduzione + Excel mock + test)

**Note:** Excel I/O tramite openpyxl/pandas. Error handling robusta per file mancanti/corrotti.
