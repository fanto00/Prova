# Workflow Traduzioni Parallele - Fase 1 (App GUI)

Piano: `docs/superpowers/plans/2026-06-15-app-gui-complete.md`

---

## Setup (Una sola volta)

### 1. Configura Google Gemini API

Segui: `SETUP_GEMINI.md`
- Ottieni chiave gratuita da https://aistudio.google.com/app/apikey
- Salva in env var `GEMINI_API_KEY`

Verifica:
```powershell
$env:GEMINI_API_KEY = "<tua-chiave>"
python -c "import google.generativeai as genai; genai.configure(api_key='$env:GEMINI_API_KEY'); print('✓ OK')"
```

### 2. Installa Dipendenze

```bash
pip install google-generativeai pytest pytest-cov
```

---

## Fase 1: 5 Traduzioni Parallele (Moduli Indipendenti)

### Opzione A: Tutti i 5 Moduli Contemporaneamente (Fast)

**Un solo comando:**
```powershell
.\tools\launch_phase1_parallel.ps1
```

Questo lancia 5 job PowerShell paralleli. Aspetta ~2-3 minuti (dipende da Gemini latency).

**Output:**
- 5 file Python creati in `railway_inspector/app/`:
  - `analysis/drawing.py`
  - `ui/dialogs.py`
  - `ui/datatips.py`
  - `ui/data_loading.py`
  - `ui/export.py`
- Metadati salvati in `railway_inspector/.translations/`

---

### Opzione B: Uno per Uno (Manual, per debug)

Se vuoi controllare ogni modulo singolarmente:

**Terminal 1 (Modulo 1 — drawing.py):**
```powershell
python tools/run_parallel_translations.py --module 1
```

**Terminal 2 (Modulo 2 — dialogs.py):**
```powershell
python tools/run_parallel_translations.py --module 2
```

**Terminal 3 (Modulo 3 — datatips.py):**
```powershell
python tools/run_parallel_translations.py --module 3
```

**Terminal 4 (Modulo 4 — data_loading.py):**
```powershell
python tools/run_parallel_translations.py --module 4
```

**Terminal 5 (Modulo 5 — export.py):**
```powershell
python tools/run_parallel_translations.py --module 5
```

Lancia questi comandi **contemporaneamente** (uno per terminale). Aspetta che tutti finiscano.

---

## Post-Traduzione: TDD + Revisione Matematica

### Step 1: Verifica che i file siano stati creati

```bash
ls -la railway_inspector/app/{analysis,ui}/*.py
```

Dovresti vedere:
```
railway_inspector/app/analysis/drawing.py
railway_inspector/app/ui/dialogs.py
railway_inspector/app/ui/datatips.py
railway_inspector/app/ui/data_loading.py
railway_inspector/app/ui/export.py
```

### Step 2: Leggi i File Tradotti

Prima di eseguire i test, **leggi ogni file tradotto** per:
- Verificare che il codice ha senso
- Controllare che mancano test boilerplate

Esempio:
```powershell
cat railway_inspector/app/analysis/drawing.py | head -100
```

### Step 3: Crea i Test (TDD)

Per ogni modulo, Gemini ha generato test. Salva in:
```
tests/test_app_drawing.py
tests/test_app_dialogs.py
tests/test_app_datatips.py
tests/test_app_data_loading.py
tests/test_app_export.py
```

Se mancano, **copiali dal file tradotto** o creali manualmente:

**Esempio test fixture (test_app_drawing.py):**
```python
import pytest
import numpy as np
import pandas as pd
from railway_inspector.app.analysis.drawing import draw_infra_overlay

def test_draw_infra_overlay_simple():
    import matplotlib.pyplot as plt
    fig, ax = plt.subplots()
    
    # Fixture: semplice infra_table con 3 location
    infra_table = pd.DataFrame({
        'coord': [0.0, 5.0, 10.0],
        'tipo': ['crossing', 'joint', 'anomaly'],
        'nome': ['XC-01', 'J-01', 'AN-01'],
    })
    
    # Test: deve aggiungere elementi all'ax senza errori
    draw_infra_overlay(ax, infra_table, x_limits=(0, 15))
    
    # Verifica: ax ha almeno una line/scatter
    assert len(ax.lines) > 0 or len(ax.collections) > 0
    
    plt.close(fig)
```

### Step 4: Esegui Test Locali

```bash
python -m pytest tests/test_app_*.py -v
```

Dovresti vedere output simile:
```
tests/test_app_drawing.py::test_draw_infra_overlay_simple PASSED
tests/test_app_dialogs.py::test_calendar_dialog PASSED
tests/test_app_datatips.py::test_custom_datatip PASSED
tests/test_app_data_loading.py::test_load_infrastructure_map PASSED
tests/test_app_export.py::test_export_route_report PASSED

======================== 5 passed in 3.21s ========================
```

Se test falliscono → debug con Claude Code (`/code-review` o `systematic-debugging`).

### Step 5: Revisione Matematica (Usando Revisore Agente)

Per ogni modulo, esegui la revisione matematica:

```powershell
# Apri Claude Code e esegui:
python tools/run_parallel_translations.py --module 1 --review
```

Questo integra il custom agent `revisore-matematico.md` che:
- Legge il file Python tradotto
- Legge il corrispondente blocco MATLAB (righe specifiche)
- Verifica **riga per riga** che la matematica sia identica
- Emette rapporto di approvazione/non-approvazione

Aspetta che il revisore dia il OK per tutti e 5 i moduli.

---

## Monitoraggio Token Gemini

Ogni traduzione stampa a console:
```
Token usage: 2145 prompt, 1032 completion
```

Calcolo totale (5 moduli):
- Prompt tokens: ~10K (min 5%, max 10% del limite gratis)
- Completion tokens: ~5K (even less)
- **Total: ~15K token** (ben sotto 2M/mese gratuiti)

Se sforato (unlikely), vedi https://ai.google.dev/pricing

---

## Troubleshooting

### Error: `GEMINI_API_KEY not set`

```powershell
$env:GEMINI_API_KEY = "<tua-chiave>"
```

Verifica che la chiave sia visibile:
```powershell
Write-Host $env:GEMINI_API_KEY
```

### Error: `No module named 'google.generativeai'`

```bash
pip install google-generativeai
```

### Gemini Request Timeout

Se la richiesta è lenta (>5 min), riprova:
```powershell
python tools/run_parallel_translations.py --module 1
```

Gemini occasionalmente è lento; retry è safe (non duplicate requests).

### Test Falliscono

1. **Leggi l'errore** — pytest emette riga esatta dove fallisce
2. **Ispeziona il modulo tradotto** — potrebbe mancare import o tipo
3. **Usa `/systematic-debugging`** in Claude Code per investigare

---

## Prossimo: Fase 2 (4 Moduli, dopo Fase 1)

Una volta che Fase 1 è completa (5 moduli OK + test verdi + review matematica OK):

```powershell
# Fase 2 lancia quando Modulo 1 è disponibile
python tools/run_parallel_translations.py --module 6   # signal_plotting.py
python tools/run_parallel_translations.py --module 7   # single_analysis_psd.py
python tools/run_parallel_translations.py --module 8   # single_analysis_evolutive.py
python tools/run_parallel_translations.py --module 9   # reports.py
```

(A fare: estenderò lo script per Fase 2 dopo che Fase 1 è completa)

---

## File Generati

Dopo Fase 1 completata:

```
railway_inspector/
├── app/
│   ├── analysis/
│   │   └── drawing.py ✓
│   └── ui/
│       ├── dialogs.py ✓
│       ├── datatips.py ✓
│       ├── data_loading.py ✓
│       └── export.py ✓
└── .translations/
    ├── module_1.json
    ├── module_2.json
    ├── module_3.json
    ├── module_4.json
    └── module_5.json

tests/
├── test_app_drawing.py ✓
├── test_app_dialogs.py ✓
├── test_app_datatips.py ✓
├── test_app_data_loading.py ✓
└── test_app_export.py ✓
```

---

## Notes

- **Parallel job overhead:** ~30 sec setup + ~120-180 sec Gemini latency
- **Sequential (1-by-1):** ~180-300 sec (same endpoint, but queued)
- **Parallel is faster** → 5 moduli in parallel ~= 200 sec
- **No API cost:** Freemium tier (2M token/mese) — questa Fase 1 = ~15K token
- **Gemini 2.0 Flash** usato per velocità; se accuracy è problema, switch a `gemini-1.5-pro`

