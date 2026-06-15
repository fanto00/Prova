"""Per-defect 3x3 classification report (pure data port of app.m:6195-6347).

Builds the SummaryData records; the dashboard rendering (figures, pie, scatter)
is left to the GUI layer.
"""
from __future__ import annotations

from collections import Counter

import numpy as np

from railway_inspector.app.utils.helpers import get_amp
from railway_inspector.app.analysis.spectrum import (
    get_spectrum_psd,
    peak_lambda_from_spectrum,
    lambda_to_label,
)

# Classification thresholds (local constants in app.m:6201-6210).
THR_LAT_VERT = 0.6     # declared in MATLAB, unused in this loop (kept for fidelity)
THR_ASYM_HIGH = 2.0
THR_ASYM_LOW = 0.5
THR_PITCH = 2.0
THR_PITCH_LOW = 0.5
L_GIUNTO = 0.5
L_IRREG = 1.0
L_DEFORM = 2.0


def _mode_categorical(cells: list[str]) -> str:
    """MATLAB mode(categorical(cells)): most frequent value; ties -> the
    alphabetically smallest (category order for cellstr is sorted)."""
    counts = Counter(cells)
    max_count = max(counts.values())
    winners = [c for c, n in counts.items() if n == max_count]
    return min(winners)
