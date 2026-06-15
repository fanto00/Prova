# Piano Sub-Plan 7: App GUI Completa (PyQt6 - Moduli Paralleli)

**Scope:** Traduzione `src_app/app.m` (~9173 righe MATLAB) → `railway_inspector/app/ui/` (PyQt6). Solo matematica pura + rendering determinisitico. **AE rimandato** (fuori scope).

**Spec ref:** `docs/superpowers/specs/2026-06-13-matlab-to-python-railway-inspector-design.md` + questa guida.

---

## Dipendenze già disponibili

✅ **Math modules** (all completate in sub-plan 1-5):
- `app.utils.helpers` (get_amp, get_max_rms, safe_ratio, get_sign_mean, sort_runs_by_direction, helper_fft_shift)
- `app.utils.filters` (filter_defect_by_dates, filter_db_by_dates)
- `app.analysis.spectrum` (lambda_to_label, peak_lambda_from_spectrum, get_spectrum_psd)
- `app.ipi.pca_model` (build_pca_model_standalone, compute_pca_bonus_for_defect)
- `app.ipi.ipi_core` (compute_severity_ratio_lv, compute_ipi_score, ipi_semaphore_color)
- `app.analysis.classification` (classify_defects)

Riuso: movmean, interp1_zero, shift_signal_frac, interp1_nan da `signal/resampling.py`.

---

## Struttura Modulare (10 Moduli Indipendenti)

### FASE 1: PARALLELO (Nessuna dipendenza cross-module)

#### **Modulo 1: `app/analysis/drawing.py`** (Linee MATLAB: 1869-4101)
**Contenuto:** Base rendering functions (axes overlay).
- `draw_infra_overlay(ax, infra_table, x_limits)` (riga 1869-1916)
- `draw_joints_overlay(ax, joints_table, x_limits)` (riga 1917-1937)
- `draw_signature_grid(M, orig_row, recon_row, title_str)` (riga 3290-4101) — **usato da single_analysis**
- `helper_fft_shift(sig, shift_m, spatial_res)` (riga 1846-1865)

**Input:** ax (matplotlib Axes), table (pandas DataFrame), 1D numpy arrays.
**Output:** Modifica ax in-place; matplotlib compliant.
**Tests:** TDD — fixture con semplici infra_table/joints_table (3-5 righe), verificare che i line/scatter vengono aggiunti correttamente. Nessun OOP, solo function-based.
**Effort:** ~200 MATLAB linee → ~250 Python LOC.

---

#### **Modulo 2: `app/ui/dialogs.py`** (Linee MATLAB: 451-647)
**Contenuto:** Calendar dialog + filter utilities.
- `open_calendar_dialog(main_window)` — QDialog con calendari (QCalendarWidget o QDateEdit).
- `render_calendar(dlg)` / `calendar_nav(dlg, delta)` / `calendar_pick(dlg, d)` / `calendar_clear(dlg)` / `calendar_apply(dlg)` — QDialog callback chain.
- `filter_defect_by_dates(Defect, d1, d2)` (riga 613-637) — math function (già possibile usare da `app.utils.filters`, ma ripetiamo qui per TDD)
- `filter_db_by_dates(DB, d1, d2)` (riga 639-647) — math function

**Input:** QWidget parent, list[dict] defect, date range.
**Output:** QDialog (accept/reject); filtered list[dict] return.
**Tests:** TDD — dialog mock (no GUI), test filter logic con date ranges.
**Effort:** ~200 MATLAB → ~250 Python LOC (PyQt6 boilerplate).

---

#### **Modulo 3: `app/ui/datatips.py`** (Linee MATLAB: 1377-1985, 4517-4655, 7969-8012)
**Contenuto:** Callback decorators per tooltip interattivi.
- `custom_datatip(~, event_obj, pk_list)` (riga 1970-1985)
- `custom_datatip_robust(~, event_obj)` (riga 1377-1399)
- `master_datatip_fcn(~, event_obj)` (riga 4517-4655)
- `classification_datatip(event_obj, SummaryData, tipi)` (riga 7969-8012)

**Input:** matplotlib event_obj (pick event).
**Output:** str (tooltip text per matplotlib `DataCursor` o custom).
**Tests:** TDD — mock event_obj con vari index/data, verificare output string formattazione.
**Effort:** ~200 MATLAB → ~220 Python LOC.

---

#### **Modulo 4: `app/ui/data_loading.py`** (Linee MATLAB: 1938-1968, 9126-9173)
**Contenuto:** Infrastructure & joints loading.
- `load_infrastructure_map(filename, track_type)` (riga 1938-1960) → pandas DataFrame
- `load_joints_map(filename, track_type)` (riga 9126-9173) → pandas DataFrame
- `helper_clean_val(row, idx)` (riga 1961-1968) — utility

**Input:** str path, str track_type.
**Output:** pandas DataFrame (colonne: [coord, tipo, nome] o simile).
**Tests:** TDD — fixture con file Excel/CSV finti (3-5 righe), verificare parsing.
**Effort:** ~80 MATLAB → ~120 Python LOC (pandas I/O).

---

#### **Modulo 5: `app/ui/export.py`** (Linee MATLAB: 8013-9125)
**Contenuto:** Report export & headless plotting.
- `export_route_report_callback(DataStore, SortedIpi, DB, C, track_name, h_main)` (riga 8013-8577)
- `generate_headless_daily_plots(Defect, C, export_dir, rank_idx)` (riga 8578-9125)

**Input:** dict DB, list SortedIpi, str track_name, str export_dir.
**Output:** PDF/PNG files (matplotlib savefig).
**Tests:** TDD — mock DB/SortedIpi, verificare che i file vengono creati. No visual validation, solo file check.
**Effort:** ~700 MATLAB → ~800 Python LOC.

---

### FASE 2: PARALLELO (Dipendono da Modulo 1 + utils già disponibili)

#### **Modulo 6: `app/ui/signal_plotting.py`** (Linee MATLAB: 1452-1845, 785)
**Contenuto:** Main signal plots (trend, context, CFAR).
- `update_signals_only(h)` (riga 1452-1609) — refresh 3 axes (Trend, Context, CFAR).
- `update_top_plots(h)` (riga 1610-1845) — refresh 8 small axes (sensori 8 canali).
- `update_all_plots(h)` (riga 785) — wrapper per entrambi.

**Deps:** `app.analysis.drawing.py` (draw_infra_overlay, draw_joints_overlay), `app.utils.helpers`, `app.utils.filters`.
**Input:** dict h (axes dict, data dict).
**Output:** Plot axes modified in-place.
**Tests:** TDD — fixture con semplici signal dict, verificare che gli axes vengono clearati e ripopolati.
**Effort:** ~400 MATLAB → ~450 Python LOC.

---

#### **Modulo 7: `app/ui/single_analysis_psd.py`** (Linee MATLAB: 4102-4257)
**Contenuto:** PSD analysis tab.
- `update_psd(~, ~)` (riga 4102-4184) — callback per aggiornamento PSD.
- `update_psd_top_axis(main_ax, parent_tab)` (riga 4185-4257) — top-axis frequency range.

**Deps:** `app.analysis.spectrum.py`, `app.utils.helpers`.
**Input:** dict defect, str sensor_name, bool is_filt.
**Output:** Axes plot (PSD spectrum + freq axis).
**Tests:** TDD — mock defect dict, verificare PSD shape e frequency range.
**Effort:** ~200 MATLAB → ~250 Python LOC.

---

#### **Modulo 8: `app/ui/single_analysis_evolutive.py`** (Linee MATLAB: 4258-4391)
**Contenuto:** Evolutive signal plots (time evolution per run).
- `update_evolutive_plots()` (riga 4258-4391)

**Deps:** `app.utils.helpers`, `app.analysis.spectrum.py`.
**Input:** dict Defect, list History.
**Output:** Multi-panel axes (evolution over time).
**Tests:** TDD — mock History, verificare subplot layout e data shapes.
**Effort:** ~150 MATLAB → ~180 Python LOC.

---

#### **Modulo 9: `app/ui/reports.py`** (Linee MATLAB: 819-1376, 6195-6523, 7659-7968)
**Contenuto:** Report generation (global, classification, top-20).
- `generate_global_report(DB, ~, map, C, track_name, h_main)` (riga 819-1266)
- `draw_4_panel_stats(parent_tab, vF, vR, group_name, meta_list, defectIDs)` (riga 1267-1376)
- `generate_defect_classification_report(DB, CFG)` (riga 6195-6523)
- `open_top_20_dashboard(h_main)` (riga 7659-7932)
- `launch_analysis_from_top(h_table, Top20, h_main, btn_handle)` (riga 7933-7968)

**Deps:** `app.analysis.drawing.py`, `app.analysis.classification.py`, `app.utils.helpers`, `app.ipi.ipi_core.py`.
**Input:** dict DB, list SortedIpi, pandas SummaryData.
**Output:** Report dict (JSON/PDF) + matplotlib figures.
**Tests:** TDD — mock DB/SummaryData, verificare report structure e figure count.
**Effort:** ~1200 MATLAB → ~1400 Python LOC.

---

### FASE 3: SEQUENZIALE (Glue layer — dipende da tutto)

#### **Modulo 10: `app/ui/single_analysis.py`** (Linee MATLAB: 1986-3289, 4392-4516)
**Contenuto:** Single defect analysis window (QMainWindow con tabs).
- `open_single_analysis(src, ~)` (riga 1986-3289) — **mega funzione PyQt6 window**
  - Tabs: "PSD", "Evolutive", "Signature Grid", "AE" (AE → placeholder "coming soon")
  - Callbacks per tab switch
  - Real-time plot refresh
- `update_psd_3d(~, ~)` (riga 4392-4516) — 3D reconstruction plot (tab aggiuntivo?)

**Deps:** TUTTI i moduli precedenti.
**Input:** dict defect, dict DB, dict C, str track_name.
**Output:** QMainWindow (modal/modeless).
**Tests:** TDD — mock defect, verificare che la window si apre e i tab caricano correttamente.
**Effort:** ~1800 MATLAB → ~2200 Python LOC (PyQt6 boilerplate).

---

#### **Modulo 11: `app/ui/main_window.py`** (Linee MATLAB: 1-286 + callbacks sparsi)
**Contenuto:** Main application window (QMainWindow con toolbar, panels, list widget).
- UI setup: canvas principal, buttons (Open DB, Calendar, Filters, Top-20, Export, ecc.)
- Panels: track selector, group selector, defect list, run list
- Callbacks: on_change_track, on_change_group, on_select_defect, on_select_run, on_param_change, ecc.
- Data store: h (dict con axes, flags, cached data)

**Deps:** TUTTI i moduli precedenti.
**Input:** str DB_path, dict CFG.
**Output:** QMainWindow (main app).
**Tests:** TDD — mock DB, verificare callbacks chain (track → group → defect → run).
**Effort:** ~600 MATLAB → ~800 Python LOC.

---

#### **Modulo 12: `app/run_app.py`**
**Contenuto:** Entry point.
```python
if __name__ == "__main__":
    app = QApplication([])
    window = MainWindow(db_path="...", cfg=CFG)
    window.show()
    sys.exit(app.exec())
```

**Effort:** ~20 Python LOC.

---

## Timeline & Parallelizzazione

| Fase | Moduli | Dipendenze | Est. Effort | Parallelizzabile? |
|------|--------|-----------|------------|-------------------|
| **1** | 1-5 | None | 10-12 gg | **YES — 5 moduli in parallelo** |
| **2** | 6-9 | Modulo 1 + utils | 12-15 gg | **YES — 4 moduli in parallelo** |
| **3** | 10-12 | Tutti | 8-10 gg | NO — sequenziale glue |

**Total:** ~30-37 gg (vs ~60-70 gg sequenziale).

---

## Workflow per Parallelizzazione (Multi-Terminal)

### Setup per Fase 1 (5 Terminali Paralleli)

**Terminal A (Modulo 1: drawing.py):**
```bash
claude-code --task "Tradurre app/analysis/drawing.py (4 funzioni rendering)"
```

**Terminal B (Modulo 2: dialogs.py):**
```bash
claude-code --task "Tradurre app/ui/dialogs.py (calendar + filters)"
```

**Terminal C (Modulo 3: datatips.py):**
```bash
claude-code --task "Tradurre app/ui/datatips.py (4 tooltip functions)"
```

**Terminal D (Modulo 4: data_loading.py):**
```bash
claude-code --task "Tradurre app/ui/data_loading.py (infra/joints loading)"
```

**Terminal E (Modulo 5: export.py):**
```bash
claude-code --task "Tradurre app/ui/export.py (report export)"
```

Ogni terminale usa **indipendentemente**:
- `traduttore-matlab.md` agent (Haiku/Opus dipendente da modello scelto)
- `revisore-matematico.md` agent (Haiku/Opus)
- Test TDD in parallelo

### Setup per Fase 2 (4 Terminali Paralleli, dopo Fase 1)

Dopo che **Modulo 1 + utils sono disponibili**, lanciare:

**Terminal A (Modulo 6: signal_plotting.py)**
**Terminal B (Modulo 7: single_analysis_psd.py)**
**Terminal C (Modulo 8: single_analysis_evolutive.py)**
**Terminal D (Modulo 9: reports.py)**

### Fase 3 (1 Terminale, sequenziale)

Dopo Fase 2:
**Terminal A:** Modulo 10 (single_analysis.py)
**Terminal A:** Modulo 11 (main_window.py)
**Terminal A:** Modulo 12 (run_app.py) + integrazione

---

## Modelli Non-Anthropic

Suggerimenti per i 4-5 terminali paralleli:

1. **Modulo 1 (drawing):** `ollama run mistral` (rendering = pure math, modello leggero ok)
2. **Modulo 2 (dialogs):** `ollama run llama2` (dialog boilerplate, simple)
3. **Modulo 3 (datatips):** `claude-code` (string formatting + context manager, Anthropic ok)
4. **Modulo 4 (data_loading):** `openai:gpt-4o-mini` (pandas I/O, GPT-mini ok)
5. **Modulo 5 (export):** `openai:gpt-4` (complex plot generation, GPT-4 meglio)

**Alternativa 1:** Tutti con Ollama (Mistral, Llama, Neural Chat) — **gratuito, locale**.
**Alternativa 2:** Alcuni con OpenAI, altri con Anthropic Claude Code — **misto, pagato**.
**Alternativa 3:** Gemini API per alcuni — **gratuito fino a X query/mese, via API**.

---

## Quality Gates

✅ **Per ogni modulo:**
1. **TDD:** Test case scritti prima, implementazione dopo.
2. **Matematica:** Revisione riga-per-riga MATLAB vs Python (agent `revisore-matematico`).
3. **Import clean:** `__all__` esplicito, niente wildcard imports.
4. **Type hints:** `def foo(x: np.ndarray) -> dict[str, Any]:`
5. **Docstring:** Una linea max (purpose). No doctest.
6. **Test coverage:** ≥80% linee; niente mocking `np.array`, solo fixture fixtures.

✅ **Integration (Fase 3):**
1. Test callback chain (track → group → defect → run).
2. Test figure lifecycle (create/update/close).
3. Manual smoke test: aprire app, caricare DB, scorrere defects, aprire single_analysis.

---

## Notes

- **PyQt6 compatibility:** Usare QMainWindow, QDialog, QTabWidget, QTableWidget per UI.
- **Matplotlib:** Usare `FigureCanvas(Figure())` embed in PyQt6 (NO `plt.show()`).
- **Thread safety:** Se update_plots è lento, considerare QThread + signal/slot (future optimization, non in scope sub-plan 7).
- **No AE yet:** Single_analysis tab per AE = placeholder "coming soon" (AE rimandato a sub-plan 6 fuori scope).

---

## Dependency Graph

```
Modulo 1 (drawing) ──┬─→ Modulo 6 (signal_plotting)
                      ├─→ Modulo 7 (psd)
                      ├─→ Modulo 8 (evolutive)
                      └─→ Modulo 9 (reports)

Modulo 2 (dialogs)  ──→ Modulo 11 (main_window)
Modulo 3 (datatips) ──→ Modulo 11
Modulo 4 (loading)  ──→ Modulo 11
Modulo 5 (export)   ──→ Modulo 11

Modulo 6-9 ──→ Modulo 10 (single_analysis)
              ↓
Modulo 10 ──→ Modulo 11 (main_window)
              ↓
Modulo 11 ──→ Modulo 12 (run_app.py)
```

---

## References

- **Spec originale:** `docs/superpowers/specs/2026-06-13-matlab-to-python-railway-inspector-design.md`
- **Piano precedenti:** `docs/superpowers/plans/2026-06-14-*` (foundation, ipi, classification)
- **MATLAB source:** `src_app/app.m` (9173 righe)
- **Python target:** `railway_inspector/app/ui/` (PyQt6 modules)

