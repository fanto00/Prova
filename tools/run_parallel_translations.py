#!/usr/bin/env python3
"""
Orchestrator per traduzioni MATLAB→Python parallele su Gemini API.

Fase 1: 5 moduli indipendenti, lanciati contemporaneamente.
Ogni terminale esegue UNA linea di questo script per il suo modulo specifico.

Uso:
    # Terminale A (Modulo 1)
    python run_parallel_translations.py --module 1

    # Terminale B (Modulo 2)
    python run_parallel_translations.py --module 2

    # ecc.
"""

import os
import sys
import json
import argparse
from pathlib import Path
import google.generativeai as genai

# Configurazione moduli Fase 1
MODULES_PHASE1 = {
    1: {
        "name": "app/analysis/drawing.py",
        "description": "Base rendering functions (infra_overlay, joints_overlay, signature_grid, fft_shift)",
        "matlab_source": "src_app/app.m",
        "matlab_lines": "1869-1916, 1917-1937, 3290-4101, 1846-1865",
        "functions": [
            "draw_infra_overlay(ax, infra_table, x_limits)",
            "draw_joints_overlay(ax, joints_table, x_limits)",
            "draw_signature_grid(M, orig_row, recon_row, title_str)",
            "helper_fft_shift(sig, shift_m, spatial_res)"
        ],
        "dependencies": ["numpy", "matplotlib.pyplot"],
        "test_template": "tests/test_app_drawing.py",
    },
    2: {
        "name": "app/ui/dialogs.py",
        "description": "Calendar dialog + date filter utilities",
        "matlab_source": "src_app/app.m",
        "matlab_lines": "451-647",
        "functions": [
            "open_calendar_dialog(main_window)",
            "calendar_nav(dlg, delta)",
            "calendar_pick(dlg, d)",
            "calendar_clear(dlg)",
            "calendar_apply(dlg)",
            "filter_defect_by_dates(Defect, d1, d2)",
            "filter_db_by_dates(DB, d1, d2)",
        ],
        "dependencies": ["PyQt6.QtWidgets", "PyQt6.QtCore", "datetime"],
        "test_template": "tests/test_app_dialogs.py",
    },
    3: {
        "name": "app/ui/datatips.py",
        "description": "Matplotlib datacursor callbacks (4 tooltip functions)",
        "matlab_source": "src_app/app.m",
        "matlab_lines": "1377-1399, 1970-1985, 4517-4655, 7969-8012",
        "functions": [
            "custom_datatip(~, event_obj, pk_list)",
            "custom_datatip_robust(~, event_obj)",
            "master_datatip_fcn(~, event_obj)",
            "classification_datatip(event_obj, SummaryData, tipi)",
        ],
        "dependencies": ["matplotlib.pyplot"],
        "test_template": "tests/test_app_datatips.py",
    },
    4: {
        "name": "app/ui/data_loading.py",
        "description": "Infrastructure & joints map loading (pandas)",
        "matlab_source": "src_app/app.m",
        "matlab_lines": "1938-1968, 9126-9173",
        "functions": [
            "load_infrastructure_map(filename, track_type)",
            "load_joints_map(filename, track_type)",
            "helper_clean_val(row, idx)",
        ],
        "dependencies": ["pandas", "openpyxl"],
        "test_template": "tests/test_app_data_loading.py",
    },
    5: {
        "name": "app/ui/export.py",
        "description": "Report export & headless plotting",
        "matlab_source": "src_app/app.m",
        "matlab_lines": "8013-9125",
        "functions": [
            "export_route_report_callback(DataStore, SortedIpi, DB, C, track_name, h_main)",
            "generate_headless_daily_plots(Defect, C, export_dir, rank_idx)",
        ],
        "dependencies": ["matplotlib.pyplot", "pathlib"],
        "test_template": "tests/test_app_export.py",
    },
}

GEMINI_PROMPT_TEMPLATE = """
You are an expert MATLAB→Python translator for a scientific signal processing application.

## Task
Translate the following MATLAB functions to Python with 100% mathematical fidelity.

### MATLAB Source
File: {matlab_source}
Lines: {matlab_lines}
Functions: {functions}

```matlab
{matlab_code}
```

### Requirements
1. **Preserve mathematical operations exactly** — same precision, same order of operations
2. **Type hints** — add `def foo(x: np.ndarray) -> dict[str, Any]:`
3. **Numpy/Pandas compatible** — use numpy for arrays, pandas for DataFrames
4. **PyQt6 compatible** — use PyQt6 for GUI code, matplotlib for plotting
5. **Single-line docstring** — one line max, no doctest
6. **No mocking** — fixtures with real data shapes/dtypes
7. **Clean imports** — explicit `__all__`, no wildcard imports
8. **Test template provided** — create TDD tests before implementation

### Dependencies
Available: {dependencies}

### Test Template
File: {test_template}
(Create tests using pytest format — one test per function)

### Output Format
```python
# File: {target_file}

{imports}

def {function_name}(...):
    # Implementation
    pass
```

Then provide pytest tests.

### Critical Notes
- **MATLAB `std(X,0)` = numpy `ddof=1`** (normalize by N-1, not N)
- **MATLAB `round()` truncates ties differently** than Python — use our `_matlab_round_pos()` if needed
- **MATLAB xcorr sign convention** — verify signal delays are preserved
- **Matplotlib axes** — modify in-place (no return), use `.cla()` for clearing
- **PyQt6 signals** — use `@QtCore.pyqtSlot(...)` decorators

Go step-by-step:
1. Extract logic from MATLAB
2. Map to Python idioms
3. Write tests
4. Implement
"""

def extract_matlab_code(matlab_file: str, line_ranges: str) -> str:
    """Extract MATLAB code by line numbers from source file."""
    ranges = [r.strip() for r in line_ranges.split(",")]
    lines = []

    with open(matlab_file, "r", encoding="utf-8") as f:
        all_lines = f.readlines()

    for r in ranges:
        if "-" in r:
            start, end = map(int, r.split("-"))
        else:
            start = end = int(r)
        lines.extend(all_lines[start-1:end])

    return "".join(lines)

def call_gemini_for_translation(module_id: int, matlab_code: str, module_info: dict) -> dict:
    """Call Gemini API to translate MATLAB module."""

    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise ValueError("GEMINI_API_KEY env var not set. See SETUP_GEMINI.md")

    genai.configure(api_key=api_key)
    model = genai.GenerativeModel("gemini-2.0-flash")

    prompt = GEMINI_PROMPT_TEMPLATE.format(
        matlab_source=module_info["matlab_source"],
        matlab_lines=module_info["matlab_lines"],
        functions="\n".join(module_info["functions"]),
        matlab_code=matlab_code,
        dependencies=", ".join(module_info["dependencies"]),
        target_file=module_info["name"],
        test_template=module_info["test_template"],
        imports="import numpy as np\nimport pandas as pd\nfrom typing import Any, dict",
        function_name=module_info["functions"][0].split("(")[0],
    )

    print(f"\n{'='*60}")
    print(f"[Modulo {module_id}] {module_info['name']}")
    print(f"{'='*60}")
    print(f"Calling Gemini API (gemini-2.0-flash)...")
    print(f"Lines: {module_info['matlab_lines']}")
    print(f"Functions: {len(module_info['functions'])}")

    response = model.generate_content(prompt)

    return {
        "module_id": module_id,
        "module_name": module_info["name"],
        "matlab_lines": module_info["matlab_lines"],
        "functions": module_info["functions"],
        "translation": response.text,
        "usage": {
            "prompt_tokens": response.usage_metadata.prompt_token_count if response.usage_metadata else 0,
            "completion_tokens": response.usage_metadata.completion_token_count if response.usage_metadata else 0,
        },
    }

def save_translation(result: dict, output_dir: str = "railway_inspector"):
    """Save translated code to file."""
    module_name = result["module_name"]
    output_path = Path(output_dir) / module_name
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Extract code block from response
    translation = result["translation"]
    if "```python" in translation:
        code = translation.split("```python")[1].split("```")[0].strip()
    else:
        code = translation

    output_path.write_text(code, encoding="utf-8")
    print(f"✓ Saved to: {output_path}")
    print(f"  Token usage: {result['usage']['prompt_tokens']} prompt, {result['usage']['completion_tokens']} completion")

    return str(output_path)

def main():
    parser = argparse.ArgumentParser(
        description="Translate MATLAB module to Python using Gemini API"
    )
    parser.add_argument(
        "--module",
        type=int,
        required=True,
        choices=list(MODULES_PHASE1.keys()),
        help="Module ID (1-5) to translate",
    )
    parser.add_argument(
        "--output-dir",
        default="railway_inspector",
        help="Output directory for translated code",
    )

    args = parser.parse_args()
    module_id = args.module

    if module_id not in MODULES_PHASE1:
        print(f"Error: Module {module_id} not found. Choose from 1-5.")
        sys.exit(1)

    module_info = MODULES_PHASE1[module_id]

    # Extract MATLAB source
    matlab_file = Path("src_app") / module_info["matlab_source"]
    if not matlab_file.exists():
        print(f"Error: MATLAB source not found: {matlab_file}")
        sys.exit(1)

    matlab_code = extract_matlab_code(str(matlab_file), module_info["matlab_lines"])

    # Call Gemini API
    result = call_gemini_for_translation(module_id, matlab_code, module_info)

    # Save output
    saved_path = save_translation(result, args.output_dir)

    # Save metadata
    metadata_path = Path(args.output_dir) / ".translations" / f"module_{module_id}.json"
    metadata_path.parent.mkdir(parents=True, exist_ok=True)
    metadata_path.write_text(json.dumps(result, indent=2), encoding="utf-8")

    print(f"\n✓ Module {module_id} translation complete!")
    print(f"  Code: {saved_path}")
    print(f"  Metadata: {metadata_path}")

if __name__ == "__main__":
    main()
