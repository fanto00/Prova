import numpy as np
import pytest
from railway_inspector.app.ipi.ipi_core import compute_severity_ratio_lv, ipi_semaphore_color


def test_severity_is_max_of_vertical_columns():
    # cols: [SX_F, SX_R, DX_F, DX_R, LAT_DX_F, LAT_DX_R, LAT_SX_F, LAT_SX_R]
    amps = np.array([[1.0, 4.0, 2.0, 3.0, 0.0, 0.0, 0.0, 0.0]])
    sev, ratio = compute_severity_ratio_lv(amps)
    assert sev[0] == 4.0  # max vertical


def test_ratio_lv_is_lat_over_vert():
    amps = np.array([[2.0, 2.0, 2.0, 2.0, 1.0, 5.0, 3.0, 0.0]])  # vert max 2, lat max 5
    sev, ratio = compute_severity_ratio_lv(amps)
    assert ratio[0] == pytest.approx(5.0 / 2.0)


def test_ratio_lv_zero_vertical_uses_floor():
    amps = np.array([[0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]])
    sev, ratio = compute_severity_ratio_lv(amps)
    assert ratio[0] == pytest.approx(1.0 / 1e-6)


def test_multiple_runs_shapes():
    amps = np.zeros((5, 8))
    sev, ratio = compute_severity_ratio_lv(amps)
    assert sev.shape == (5,)
    assert ratio.shape == (5,)


@pytest.mark.parametrize("score,rgb", [
    (90, (0.8, 0.0, 0.0)),
    (75, (0.8, 0.0, 0.0)),
    (60, (1.0, 0.5, 0.0)),
    (50, (1.0, 0.5, 0.0)),
    (30, (0.9, 0.8, 0.0)),
    (25, (0.9, 0.8, 0.0)),
    (10, (0.0, 0.6, 0.0)),
    (0, (0.0, 0.6, 0.0)),
])
def test_ipi_semaphore_color_bands(score, rgb):
    assert ipi_semaphore_color(score) == rgb
