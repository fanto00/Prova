"""Weighted PSD spectrum and dominant-wavelength extraction (port of app.m)."""
from __future__ import annotations

import numpy as np
from scipy.signal import periodogram
from scipy.signal.windows import hamming

from railway_inspector.signal.resampling import interp1_zero


def lambda_to_label(lambda_: float, L_giunto: float, L_irreg: float, L_deform: float) -> str:
    """Map a dominant wavelength to a qualitative class label (app.m:7369)."""
    if lambda_ <= 0:
        return "N/D"
    if lambda_ < L_giunto:
        return "Corto"
    if lambda_ < L_irreg:
        return "medio"
    if lambda_ < L_deform:
        return "lungo"
    return "molto lungo"
