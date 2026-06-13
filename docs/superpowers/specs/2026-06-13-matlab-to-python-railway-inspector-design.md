# Design Spec — Riscrittura MATLAB → Python del Railway Inspector

**Data:** 2026-06-13
**Autore:** Nicco
**Stato:** Approvato (in attesa di review finale)

## 1. Obiettivo

Riscrivere in Python due programmi MATLAB del sistema di manutenzione predittiva ferroviaria:

1. `src_database/Database_Allineamento_nomax.m` — pipeline di detection difetti da accelerazioni axle-box, allineamento geometrico, clustering e costruzione del database storico dei difetti (`MASTER_DB`).
2. `src_app/app.m` — applicazione GUI interattiva (~9000 righe) per l'analisi visiva dei difetti: liste, trend temporali, PSD, PCA, autoencoder, calcolo IPI, report.

### Obiettivi del progetto

- **Primario:** conversione fedele MATLAB → Python.
- **Secondario:** modularizzazione — niente più file monolitici con decine di funzioni interne; le funzioni diventano moduli esterni con responsabilità isolate.
- **Terziario (apprendimento):** orchestrazione multi-agente con Claude Code — un agente orchestratore che coordina subagenti traduttori e subagenti revisori.

### Vincolo invariante (NON NEGOZIABILE)

**Il metodo di filtraggio e tutta la matematica dei due codici madre non deve essere modificato minimamente.** Stessi coefficienti, stesso ordine delle operazioni, stessa gestione degli edge case. Ogni divergenza numerica rispetto al MATLAB originale è un bug.

## 2. Stack tecnologico

| Componente | Scelta |
|---|---|
| Linguaggio | Python 3.11+ |
| GUI | PyQt6 (sostituisce MATLAB App Designer / figure handle) |
| Calcolo numerico | NumPy |
| Signal processing | SciPy (`scipy.signal`, `scipy.io`) |
| Grafici | Matplotlib embedded in PyQt6 (`FigureCanvasQTAgg`) |
| I/O MATLAB | `scipy.io.loadmat` / `savemat` per i `.mat` |
| Excel | `pandas` + `openpyxl` |

## 3. Struttura dei moduli

Approccio scelto: **moduli prima, traduzione per modulo** (design della struttura, poi ogni agente traduce un singolo modulo isolato e verificabile).

```
railway_inspector/
├── config.py                   # Dataclass CFG, parametri centralizzati
├── io/
│   ├── mat_loader.py           # Caricamento file .mat (scipy.io)
│   ├── excel_loader.py         # load_infrastructure_map, load_joints_map
│   └── database_io.py          # Salvataggio/caricamento MASTER_DB
├── signal/
│   ├── filtering.py            # Pipeline butter→filtfilt (bandpass temporale + spaziale)
│   ├── alignment.py            # Macro-allineamento (xcorr), micro-allineamento (FFT fase + Hilbert), build_align_template, shift_signal_frac, shift_fill
│   └── resampling.py           # Ricampionamento spaziale (equivalente interp1), interpft
├── detection/
│   ├── trigger.py              # Detection RMS adattivo, findpeaks, raffinamento picco
│   ├── clustering.py           # Merging eventi, ClusterID, filtro velocità moda
│   └── extraction.py           # extract_at_position, extract_at_joints, peak_amp, analyze_and_extract
├── database/
│   ├── builder.py              # Loop principale, secondo passaggio (completamento)
│   └── pipeline.py             # Orchestrazione passaggi per singola run
├── app/
│   ├── main_window.py          # QMainWindow, navigation bar, layout principale
│   ├── widgets/
│   │   ├── defect_list.py       # Lista difetti, filtro n, filtro data
│   │   ├── history_panel.py     # Trend temporale + lista run
│   │   ├── signals_panel.py     # 6 grafici dettaglio passaggi
│   │   ├── context_panel.py     # Grafico contesto + RMS + lista giunti
│   │   └── calendar_dialog.py   # Dialogo calendario (selezione date)
│   ├── single_analysis/
│   │   ├── analysis_window.py    # Finestra principale analisi singolo difetto
│   │   ├── psd_tab.py            # update_psd, update_psd_top_axis, update_psd_3d
│   │   ├── evolutive_tab.py      # update_evolutive_plots
│   │   ├── pca_tab.py            # build_pca_model_standalone
│   │   └── ae_tab.py             # run_ae_inference, plot_ae_reconstruction
│   ├── dialogs/
│   │   ├── top20_dashboard.py    # open_top_20_dashboard, launch_analysis_from_top
│   │   ├── global_report.py      # generate_global_report, draw_4_panel_stats, draw_statistical_appendix
│   │   └── export_report.py      # export_route_report_callback, generate_headless_daily_plots
│   ├── ipi/
│   │   ├── ipi_core.py           # Calcolo IPI principale
│   │   ├── pca_model.py          # compute_pca_bonus_for_defect, build_pca_model_standalone
│   │   └── ae_model.py           # load_ae_model_for_track, compute_ae_bonus_for_defect
│   ├── analysis/
│   │   ├── spectrum.py           # get_spectrum_psd, peak_lambda_from_spectrum, lambda_to_label
│   │   ├── classification.py     # generate_defect_classification_report
│   │   └── drawing.py            # draw_infra_overlay, draw_joints_overlay, draw_signature_grid
│   └── utils/
│       ├── datatips.py           # custom_datatip, master_datatip_fcn, classification_datatip
│       ├── filters.py            # filter_defect_by_dates, filter_db_by_dates
│       └── helpers.py            # helper_fft_shift, get_amp, get_max_rms, sort_runs_by_direction, safe_ratio, get_sign_mean
├── run_database.py             # Entry point database builder
└── run_app.py                  # Entry point app
```

### Principio di dimensione dei file

L'obiettivo **non** è un limite rigido di righe. L'obiettivo è: **un file = una responsabilità chiara**. Funzioni MATLAB grandi (es. `generate_global_report` ~450 righe, i tab PSD/evolutivo) produrranno naturalmente file da 600-800 righe; va bene finché ogni file fa una sola cosa.

Vincolo non negoziabile sulla struttura: **nessun file mescola responsabilità diverse** (es. mai calcolo IPI e rendering GUI nello stesso file).

## 4. Matematica critica — mappatura MATLAB → Python

| MATLAB | Python | Rischio | Nota |
|---|---|---|---|
| `butter` / `filtfilt` | `scipy.signal.butter` / `scipy.signal.filtfilt` | Basso | Verificare ordine, tipo bandpass, normalizzazione frequenze identici |
| `fft` / `ifft` | `numpy.fft.fft` / `numpy.fft.ifft` | Basso | Convenzioni identiche |
| `hilbert` | `scipy.signal.hilbert` | Basso | Restituisce segnale analitico complesso; usare `abs()` per envelope |
| `xcorr` con lag | `scipy.signal.correlate` + calcolo lag manuale | **Medio** | `xcorr` MATLAB ha convenzione di lag specifica; ricostruire il vettore `lags` esattamente |
| `interpft` | reimplementazione via FFT | **Alto** | Nessun equivalente diretto SciPy; implementare zero-padding in frequenza fedele a MATLAB |
| `findpeaks` | `scipy.signal.find_peaks` | Medio | `MinPeakDistance` → `distance`; verificare semantica indici |
| `interp1` (`'linear',0`) | `numpy.interp` con gestione extrapolazione=0 | Basso | `numpy.interp` non azzera fuori range di default → gestire esplicitamente |
| `movmean` | implementazione equivalente | Basso | Verificare gestione bordi |
| `mode` | `scipy.stats.mode` | Basso | |

### Funzioni a rischio alto da trattare in serie con revisione rinforzata

- `interpft` (in `resampling.py`)
- `xcorr` + ricostruzione lag (in `alignment.py`)
- `shift_signal_frac` — shift frazionario via fase FFT (in `alignment.py`)
- pipeline `filtfilt` doppia (temporale + spaziale) in `filtering.py`

## 5. Strategia di verifica

**Scelta: verifica solo analitica. Niente MATLAB disponibile, niente fixture numeriche.**

Implicazione per l'orchestrazione: l'orchestratore **non può confrontare numeri**. La difesa contro la violazione del vincolo invariante è la **revisione analitica riga-per-riga**:

- Ogni traduzione viene confrontata col blocco MATLAB originale corrispondente.
- Il revisore verifica: stessi coefficienti, stesso ordine delle operazioni, stessa gestione edge case (zero-padding `interpft`, normalizzazione `xcorr`, azzeramento fuori range `interp1`, gestione `NaN`/`omitnan`).
- Particolare attenzione alle differenze di indicizzazione 1-based (MATLAB) → 0-based (Python).

**Rischio accettato:** senza confronto numerico reale, errori sottili (es. differenze di arrotondamento o convenzioni interne delle funzioni) potrebbero non emergere. La revisione analitica rigorosa è la mitigazione. Se in futuro MATLAB diventa disponibile, si potranno aggiungere fixture di regressione.

## 6. Orchestrazione multi-agente

Terzo obiettivo del progetto: imparare a orchestrare subagenti Claude Code.

### Ruoli

- **Orchestratore (agente principale):** coordina, mantiene la lista moduli e l'ordine di dipendenza, dispaccia i subagenti, non scrive codice di produzione lui stesso.
- **Subagente Traduttore:** un agente per modulo; traduce MATLAB → Python preservando la matematica esatta.
- **Subagente Revisore matematico:** verifica analitica riga-per-riga; guardiano del vincolo invariante. Approva o richiede correzioni.

### Flusso

1. L'orchestratore dispaccia un Traduttore per il modulo corrente.
2. Al termine, dispaccia un Revisore matematico sullo stesso modulo.
3. Si procede al modulo successivo **solo dopo l'OK del revisore**.

### Ordine di traduzione (per dipendenze)

```
1. config.py            (nessuna dipendenza)
2. signal/              (filtering, alignment, resampling) ← cuore matematico, IN SERIE, revisione rinforzata
3. io/                  (loaders)
4. detection/           (trigger, clustering, extraction)
5. database/            (builder, pipeline) → run_database.py
6. app/                 (GUI, IPI, analysis) → run_app.py
```

### Regole di parallelismo

- I moduli `signal/` (rischio alto) si traducono **in serie**, mai in parallelo.
- I moduli indipendenti dell'app (es. `widgets/`, `dialogs/`, `analysis/`) possono essere tradotti **in parallelo** una volta che `signal/` e `detection/` sono confermati.
- Ogni modulo passa comunque dalla revisione matematica prima di essere considerato chiuso.

## 7. Criteri di successo

1. I due programmi sono completamente riscritti in Python e funzionanti.
2. La struttura modulare rispetta lo schema della Sezione 3; nessun file mescola responsabilità diverse.
3. La matematica è preservata: ogni modulo a rischio ha passato la revisione analitica riga-per-riga.
4. `run_database.py` produce un `MASTER_DB` con la stessa semantica del `.mat` MATLAB.
5. `run_app.py` apre la GUI PyQt6 con le funzionalità dell'app originale.
6. Il flusso multi-agente è stato eseguito: traduttori + revisori, con l'orchestratore che gestisce le dipendenze.

## 8. Fuori scope

- Nuove feature non presenti nei codici madre.
- Ottimizzazioni di performance che alterino la matematica.
- Modifiche all'algoritmo di detection, filtraggio, allineamento, clustering o IPI.
- Fixture di regressione numerica (rinviate a quando MATLAB sarà disponibile).
