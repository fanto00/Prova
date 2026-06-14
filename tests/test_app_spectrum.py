"""Tests for app.analysis.spectrum (port of app.m spectrum functions)."""
import numpy as np
import pytest
from railway_inspector.app.analysis.spectrum import lambda_to_label


@pytest.mark.parametrize("lam,expected", [
    (-1.0, "N/D"),
    (0.0, "N/D"),
    (0.3, "Corto"),
    (1.0, "medio"),
    (3.0, "lungo"),
    (50.0, "molto lungo"),
])
def test_lambda_to_label(lam, expected):
    # boundaries: L_giunto=0.5, L_irreg=2.0, L_deform=10.0
    assert lambda_to_label(lam, 0.5, 2.0, 10.0) == expected
